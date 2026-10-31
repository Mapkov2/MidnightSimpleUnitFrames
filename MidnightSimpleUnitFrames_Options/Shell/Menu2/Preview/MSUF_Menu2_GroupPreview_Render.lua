--- Group preview render/composition.
---
--- Native creates the preview host and interaction handles; this module owns
--- the options composition path that binds engine regions to preview handles.
local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Menu2/GroupPreview_Render"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Core exports the refresh path reads, resolved once (their providers load with the
-- core): the preview animation frame state and the status icon texture resolver.
local CoreExports = {
    BuildAnimationFrameState = MSUF.Require("MSUF_BuildPreviewAnimationFrameState", FILE),
    GetStatusIconTexture = MSUF.Require("MSUF_GetStatusIconTexture", FILE),
}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB
local Render = M.GroupPreviewRender or {}
M.GroupPreviewRender = Render
local Fallbacks = M.Fallbacks or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local issecretvalue, wipe = issecretvalue, wipe
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local Stage = {}
local SceneAuraLaneAvailable, SceneAuraLaneTextAvailable, PreviewIconScale, AURA_LANES, BuildSceneAuraLanes, RenderAuras
local BuildSceneSpells, FinalizeSpellLevels, SuspendHandleEffects
local TEXT_HANDLE_KEYS, TEXT_LEVEL_SPECS, TEXT_SLOT_HANDLE_KEYS, EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT
local MENU_EXTRA_OPTIONS = { position = false, sampleCount = 3 }
local PREDICTION_BAR_FIELDS = { "_healPred", "_absorb", "_healAbsorb" }
-- Blizzard's BackdropTemplateMixin:SetBackdrop skips a table it already holds
-- (HasBackdropInfo compares identity), so each repaint passes the same table.
local MOCK_BACKDROPS = {}
function Render.MockBackdrop(file)
    local backdrop = MOCK_BACKDROPS[file]
    if not backdrop then
        backdrop = { bgFile = file }
        MOCK_BACKDROPS[file] = backdrop
    end
    return backdrop
end
-- Friendly bosses need boss units, which Classic Era and TBC do not have: a
-- client fact read once at load. A harness without MSUF.Client previews them.
local PREVIEW_BOSS_UNITS = MSUF.Client.SupportsUnit("boss1") == true
local ADDITIONAL_PREVIEW_PREFIXES = PREVIEW_BOSS_UNITS and { "pets", "targets", "friendlyBoss", "healerMana" }
    or { "pets", "targets", "healerMana" }
Render.ADDITIONAL_PREVIEW_PREFIXES = ADDITIONAL_PREVIEW_PREFIXES
-- The Group Bars settings section that owns each sample-effect layer.
Render.SAMPLE_LAYER_SECTIONS = { dispelOverlay = "dispel", dispelSymbol = "dispelSymbol" }
-- Menu samples form a compact shared scene. Screen positions belong to the
-- live/Edit Mode layout; projecting them here would hide the group or samples.
-- `out` (optional) is the caller's reused result table, so a settings repaint
-- allocates nothing once the layout exists.
function Render.AdditionalPreviewLayout(gf, kind, conf, liveW, liveH, out)
    if not (gf and gf.GetAdditionalPreviewSpec) or conf.enabled == false
        or (conf.petsEnabled ~= true and (kind ~= "party" or conf.targetsEnabled ~= true)
            and (conf.friendlyBossEnabled ~= true or not PREVIEW_BOSS_UNITS) and conf.healerManaEnabled ~= true) then return nil end
    local count = kind == "party" and 5 or 10
    local result = out or {}
    local items = result._items
    if not items then
        items = {}
        result._items = items
    end
    result.minX, result.maxX, result.minY, result.maxY = -liveW / 2, liveW / 2, -liveH / 2, liveH / 2
    local left = liveW / 2 + 18
    for i = 1, #ADDITIONAL_PREVIEW_PREFIXES do
        local prefix = ADDITIONAL_PREVIEW_PREFIXES[i]
        local spec = gf.GetAdditionalPreviewSpec(kind, prefix, count, MENU_EXTRA_OPTIONS)
        if spec and spec.enabled then
            local x, y = left + spec.totalWidth / 2, liveH / 2 - spec.totalHeight / 2
            local item = items[prefix]
            if not item then
                item = {}
                items[prefix] = item
            end
            item.spec, item.x, item.y = spec, x, y
            result[prefix] = item
            result.maxX = x + spec.totalWidth / 2
            result.minY = math.min(result.minY, y - spec.totalHeight / 2)
            left = result.maxX + 18
        else
            result[prefix] = nil
        end
    end
    return result
end
function Render.HideAdditionalPreview(box)
    for _, root in pairs(box._additionalPreviewRoots or {}) do root:Hide() end
    if box._mock and MSUF.GF and MSUF.GF.HideBuffCoveragePreview then
        MSUF.GF.HideBuffCoveragePreview(box._mock)
    end
end
local function DefaultCompiledAuraLane(_, _, fallback) return fallback or {} end


local SetPreviewFrameLevel, PreviewElementLevel, PreviewInteractionLevel

-- Raise the cached mock above the preview canvas, then use that exact level as
-- the bias for every absolute runtime ElementLevel encoded below.
local PREVIEW_LOCAL_BASE_OFFSET = 400
local PREVIEW_FRAME_LEVEL_MAX = 65535
local function SafePreviewFrameLevel(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value < 0 then return 0 end
    if value > PREVIEW_FRAME_LEVEL_MAX then return PREVIEW_FRAME_LEVEL_MAX end
    return value
end
SetPreviewFrameLevel = function(frame, value)
    if not (frame and frame.SetFrameLevel) then return 0 end
    value = SafePreviewFrameLevel(value)
    frame:SetFrameLevel(value)
    return value
end
--- The live layer encoder is intentionally absolute. Menu2, however, raises
--- its cached Group mock into a private frame-level band so it stays above the
--- preview canvas. Translate every encoded live level by that one mock-owned
--- bias; mixing an unshifted ElementLevel with the raised mock puts ordinary
--- Layer 0..9 content (notably Name/HP/Power text) underneath the health bar.
PreviewElementLevel = function(mock, layerAPI, layer, fallback, detail)
    local encoded
    if layerAPI and layerAPI.ElementLevel then
        encoded = layerAPI.ElementLevel(layer, fallback, detail)
    else
        local value = math.floor((tonumber(layer) or fallback or 0) + 0.5)
        if value < 0 then value = 0 elseif value > 30 then value = 30 end
        detail = math.floor((tonumber(detail) or 0) + 0.5)
        if detail < 0 then detail = 0 elseif detail > 31 then detail = 31 end
        encoded = 100 + value * 32 + detail
    end
    return SafePreviewFrameLevel((tonumber(mock and mock._msufPreviewElementLevelBias) or 0) + encoded)
end
PreviewInteractionLevel = function(mock, layerAPI, extra)
    local top = PreviewElementLevel(mock, layerAPI, 30, 30,
        layerAPI and layerAPI.ELEMENT_DETAIL_MAX or 31)
    return SafePreviewFrameLevel(top + (tonumber(layerAPI and layerAPI.ELEMENT_LEVEL_STRIDE) or 32)
        + (tonumber(extra) or 0))
end
-- Render state field and what stands in for an install dep that is missing (nothing, for the handles).
local GROUP_RENDER_FALLBACKS = {
    { "buffHandle" }, { "trackedBuffHandle" }, { "debuffHandle" }, { "externalHandle" }, { "powerBarHandle" },
    { "portraitHandle" }, { "dispelSymbolHandle" }, { "spellHandle" }, { "ScaleValue" }, { "ConfigToOffset" },
    { "CompiledSpec", Fallbacks.Nil }, { "CompiledAuraLane", DefaultCompiledAuraLane }, { "RuntimeStatusConfig", Fallbacks.Nil },
    { "CurrentStatusSpec", Fallbacks.Nil }, { "StatusSpecEnabled", Fallbacks.False }, { "StatusSpecInMode", Fallbacks.False },
    { "StatusSpecIsText", Fallbacks.False }, { "StatusText", Fallbacks.Empty }, { "StatusLabel", Fallbacks.Status },
    { "CurrentSpellInfo", Fallbacks.Nil }, { "PreviewAllSpecSpellIcons", Fallbacks.False }, { "CurrentSpellConfig", Fallbacks.Nil },
    { "CurrentSpellPlaced", Fallbacks.Nil }, { "CurrentSpellTexture", Fallbacks.QuestionIcon },
    { "CurrentSpellColor", Fallbacks.WhiteRGB }, { "MockSpellTexture", Fallbacks.QuestionIcon }, { "Round", Fallbacks.Round },
    { "ResolveDefaultZoomLock", Fallbacks.Noop }, { "UpdateZoomControls", Fallbacks.Noop }, { "SelectHandle", Fallbacks.Noop },
    { "NudgeHandlePosition", Fallbacks.Noop }, { "RefreshHandleSelection", Fallbacks.Noop },
    { "ClampZoom", function(value) return tonumber(value) or 1 end },
    { "ClampLayer", function(value, fallback) return tonumber(value) or fallback or 0 end },
    { "ClassColor", function(_, r, g, b) return r or 1, g or 1, b or 1 end },
    { "AuraGrowth", function() return { px = 1, py = 0, sx = 0, sy = -1 } end },
    { "Int", function(value, fallback, minValue, maxValue)
        local n = floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
        if minValue ~= nil and n < minValue then n = minValue end
        if maxValue ~= nil and n > maxValue then n = maxValue end
        return n
    end },
}
-- A refresh first resolves immutable inputs into a scene. Render components then
-- measure and paint that scene without reaching back through the install closure.
-- The tracked lane is read into one table kept per preview box: every key is
-- written on each refresh, so the table never carries a stale field.
local function SceneStatusAvailable(scene, spec)
    if scene.runtimeSpec then
        local cfg = scene.S.RuntimeStatusConfig(scene.runtimeStatus, spec)
        return cfg and cfg.enabled == true
    end
    return scene.S.StatusSpecEnabled(scene.conf, spec)
end

local function SceneLayerOn(scene, key)
    return scene.layerAvailable[key] ~= false and scene.layerVisible[key] ~= false
end

local function SceneLayerAlpha(scene, key)
    if scene.layerAvailable[key] == false then return 0 end
    return scene.soloLayer and scene.soloLayer ~= key and 0.15 or 1
end

-- Scene field -> compiled spec section.
local RUNTIME_SPEC_SECTIONS = {
    runtimeText = "text", runtimePower = "power", runtimeHealth = "health", runtimeBorder = "border",
    runtimeTempMaxHealth = "tempMaxHealth", runtimePrediction = "prediction", runtimeStatus = "status",
}

local function BuildSceneLayers(scene, box, kind, conf, runtimeSpec)
    local RenderState, gf = scene.S, scene.gf
    local statusAvailable = false
    for i = 1, #RenderState.statusSpecs do
        local spec = RenderState.statusSpecs[i]
        if RenderState.StatusSpecInMode(spec, scene.statusSpec) and SceneStatusAvailable(scene, spec) then
            statusAvailable = true
            break
        end
    end
    local aurasEnabled, powerTextEnabled
    if scene.runtimeAuras then
        local custom = false
        for i = 1, #AURA_LANES do
            if scene[AURA_LANES[i][3]].enabled == true then
                custom = true
                break
            end
        end
        scene.customRenderer = custom
        aurasEnabled = custom or scene.runtimeAuras.enabled == true
    else
        scene.customRenderer = true
        aurasEnabled = scene.rawAuras.enabled ~= false
    end
    if runtimeSpec then
        powerTextEnabled = runtimeSpec.showPowerText == true
    else
        powerTextEnabled = (gf and gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(kind, conf))
            or conf.showPowerText == true or conf.showPower == true
    end
    local customAuraText = false
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        if SceneAuraLaneTextAvailable(scene, scene[lane[3]], lane[4]) then
            customAuraText = true
            break
        end
    end
    local textAvailable
    if runtimeSpec then
        textAvailable = runtimeSpec.showName == true
            or runtimeSpec.showHealthText == true or powerTextEnabled == true
    else
        textAvailable = conf.showName ~= false or conf.showHPText ~= false or powerTextEnabled == true
    end
    local selectedSpellAvailable = conf.spellIndicators and conf.spellIndicators.enabled == true
        and (scene.selectedSpellPlacedEnabled or scene.selectedSpellNeedsPlacementPreview
            or scene.selectedSpellEffectAvailable)
    -- Same role-gated enablement the runtime uses: the layer is unavailable
    -- (not merely hidden) when the bar is off for the preview role.
    local powerAvailable
    if runtimeSpec then
        powerAvailable = scene.runtimePower and scene.runtimePower.enabled == true or false
    else
        powerAvailable = (tonumber(scene.H.MockPowerHeight(kind, conf, 1, 1)) or 0) > 0
    end
    local layerAvailable = box._msufGFLayerAvailableState
    if not layerAvailable then
        layerAvailable = {}
        box._msufGFLayerAvailableState = layerAvailable
    end
    layerAvailable.guides, layerAvailable.bounds = true, true
    layerAvailable.power = powerAvailable
    layerAvailable.portrait = kind == "party" and runtimeSpec and runtimeSpec.portrait
        and runtimeSpec.portrait.enabled == true or false
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        layerAvailable[lane[1]] = SceneAuraLaneAvailable(scene, scene[lane[3]], lane[4])
    end
    layerAvailable.status = statusAvailable
    layerAvailable.si = scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.enabled == true
        and (scene.runtimeSpellPlacedAvailable or scene.runtimeSpellEffectAvailable)
        or selectedSpellAvailable or false
    layerAvailable.auraText = aurasEnabled and customAuraText
    layerAvailable.text = textAvailable
    layerAvailable.dispelOverlay = runtimeSpec and runtimeSpec.group
        and runtimeSpec.group.dispelOverlayEnabled == true or false
    layerAvailable.dispelSymbol = runtimeSpec and runtimeSpec.dispelSymbol
        and runtimeSpec.dispelSymbol.enabled == true or false
    scene.layerAvailable = layerAvailable
    box._layerAvailable = layerAvailable
    if scene.soloLayer and layerAvailable[scene.soloLayer] == false then
        scene.M.gfPreviewSoloLayer = nil
        scene.soloLayer = nil
    end
end

local function BuildScene(box, reason)
    local RenderState = box._msufGFRenderState
    local H, M, runtimeNS = RenderState.H, RenderState.M, RenderState.MSUF
    local kind = H.CurrentScope()
    local conf = H.Conf(kind)
    local gf = runtimeNS and runtimeNS.GF
    local previewAnimation = runtimeNS and runtimeNS.PreviewAnimation
    local buildFrameState = previewAnimation and previewAnimation.BuildFrameState
        or CoreExports.BuildAnimationFrameState
    local animState = box._animationEnabled == true
        and buildFrameState(box, 1, kind, box._msufGFMenuPreviewAnimState or {}, box._animationElapsed)
    if animState then box._msufGFMenuPreviewAnimState = animState end
    local runtimeSpec = RenderState.CompiledSpec(kind)
    -- The group cell mirrors the player's current state (name, class, exact HP/power/absorb) so the preview matches
    -- the live group frame. Pull-based only: sampled during this refresh, stylized values back any missing field.
    -- The engine scene stays unit-free; this stage reads the unit and hands the scene a sample.
    local preview = runtimeNS and runtimeNS.UFPreview
    local liveData = preview and preview.LiveUnitData and preview.LiveUnitData("player") or nil
    -- One scene table per preview box, emptied for each refresh, so a repaint
    -- builds no new scene (review R7 item 9).
    local scene = box._msufGFSceneState
    if scene then wipe(scene) else
        scene = {}
        box._msufGFSceneState = scene
    end
    scene.S, scene.box, scene.reason, scene.H, scene.M, scene.MSUF = RenderState, box, reason, H, M, runtimeNS
    scene.mock, scene.kind, scene.label, scene.conf, scene.gf = RenderState.mock, kind, H.PreviewScopeLabel(kind), conf, gf
    scene.previewAnimation, scene.animState, scene.liveData = previewAnimation, animState, liveData
    scene.hpPct = animState and max(0.02, min(0.98, tonumber(animState.hpPct) or 0.72)) or (liveData and liveData.hp) or 0.72
    scene.powerPct = animState and max(0, min(1, tonumber(animState.powerPct) or 0.70)) or (liveData and liveData.power) or 0.70
    scene.healPct = animState and max(0.01, min(0.24, tonumber(animState.healPct) or 0.12)) or 0.12
    scene.absorbPct = animState and max(0.01, min(0.24, tonumber(animState.absorbPct) or 0.08)) or 0.08
    scene.runtimeSpec = runtimeSpec
    scene.runtimeAuras = runtimeSpec and runtimeSpec.auras
    for field, section in pairs(RUNTIME_SPEC_SECTIONS) do
        scene[field] = runtimeSpec and runtimeSpec[section] or {}
    end
    scene.focus = H.PreviewFocusForPage(RenderState.ctx.key)
    scene.layerVisible = type(M.gfPreviewLayerVisible) == "table" and M.gfPreviewLayerVisible or {}
    -- The sample-effect layers follow their open settings section on the Group Bars page (an edge, so a chip click sticks).
    M.PreviewHelpers.SyncSampleLayerSections(M, scene.layerVisible, "gf_bars", Render.SAMPLE_LAYER_SECTIONS,
        M.accordionState, M.activeKey)
    scene.soloLayer = M.gfPreviewSoloLayer
    scene.textHandles = box._textHandles or {}
    scene.previewRole = H.PreviewRole and H.PreviewRole(kind) or RenderState.GF_PREVIEW_ROLE
    BuildSceneAuraLanes(scene, box, kind, conf, runtimeSpec)
    BuildSceneSpells(scene, box, kind, conf)
    BuildSceneLayers(scene, box, kind, conf, runtimeSpec)
    return scene
end

local function TextRegionList(box, key, a, b, c)
    local lists = box._msufGFTextRegionLists
    if not lists then
        lists = {}
        box._msufGFTextRegionLists = lists
    end
    local list = lists[key]
    if not list then
        list = {}
        lists[key] = list
    end
    list[1], list[2], list[3] = a, b, c
    return list
end
-- Animation-tick path: the handle placements stay inline, one Lua call per handle and no wrapper.
local function PlaceTextHandleGroup(scene, handles, groupKey, prefix, left, center, right)
    local box, mock, H = scene.box, scene.mock, scene.H
    local keys = TEXT_SLOT_HANDLE_KEYS[prefix]
    if H.TextMovesTogether(scene.kind, prefix) then
        handles[keys[1]]:Hide()
        handles[keys[2]]:Hide()
        handles[keys[3]]:Hide()
        if not H.PlaceHandleAroundRegions(handles[groupKey], mock, TextRegionList(box, prefix, left, center, right), 3) then
            handles[groupKey]:Hide()
        end
    else
        handles[groupKey]:Hide()
        if not H.PlaceHandleAroundRegions(handles[keys[1]], mock, TextRegionList(box, keys[1], left), 3) then
            handles[keys[1]]:Hide()
        end
        if not H.PlaceHandleAroundRegions(handles[keys[2]], mock, TextRegionList(box, keys[2], center), 3) then
            handles[keys[2]]:Hide()
        end
        if not H.PlaceHandleAroundRegions(handles[keys[3]], mock, TextRegionList(box, keys[3], right), 3) then
            handles[keys[3]]:Hide()
        end
    end
end
local function PlaceTextHandles(scene)
    local box, mock, H = scene.box, scene.mock, scene.H
    local handles = scene.textHandles
    for i = 1, #TEXT_HANDLE_KEYS do handles[TEXT_HANDLE_KEYS[i]]._previewScale = scene.previewScale end
    -- With the Text layer off the cell draws no text, so there is nothing for a handle to wrap.
    if not SceneLayerOn(scene, "text") then
        for i = 1, #TEXT_HANDLE_KEYS do handles[TEXT_HANDLE_KEYS[i]]:Hide() end
        H.ApplyTextFocus(box, mock)
        return
    end
    -- Name is a natural-width FontString. Its actual region is the sole source
    -- for glyph, grab-handle and focus geometry.
    if not H.PlaceHandleAroundRegions(handles.name, mock, TextRegionList(box, "name", mock._nameFS), 3, "name") then handles.name:Hide() end
    PlaceTextHandleGroup(scene, handles, "hpGroup", "hp", mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS)
    PlaceTextHandleGroup(scene, handles, "powerGroup", "power", mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS)
    H.ApplyTextFocus(box, mock)
end

--- Strata of the preview host. Handles and effect roots stay on it: the live
--- runtime keeps every layer-aware element on its owning frame's strata, so
--- neither a live frame's strata nor a configured legacy strata applies here.
local function PreviewHostStrata(scene)
    local RenderState = scene.S
    local host = scene.mock.GetFrameStrata and scene.mock:GetFrameStrata()
    if RenderState.issecretvalue(host) == true or not host or host == "" then
        host = scene.box.GetFrameStrata and scene.box:GetFrameStrata()
        if RenderState.issecretvalue(host) == true or host == "" then host = nil end
    end
    return host
end

local function ApplyHandleStrata(scene, handle, host)
    local RenderState = scene.S
    if handle and handle.SetFrameStrata and host then
        local current = handle.GetFrameStrata and handle:GetFrameStrata()
        if RenderState.issecretvalue(current) == true or current ~= host then handle:SetFrameStrata(host) end
    end
end

local function SyncIconDetailLevels(layers, handle)
    if not (handle and handle.GetFrameLevel) then return end
    layers = layers or {}
    local baseLevel = handle:GetFrameLevel() or 0
    SetPreviewFrameLevel(handle._iconDurationLayer,
        baseLevel + (layers.AURA_DURATION_BAR_LEVEL_OFFSET or 2))
    SetPreviewFrameLevel(handle._iconSwipeLayer,
        baseLevel + (layers.AURA_COOLDOWN_LEVEL_OFFSET or 4))
    SetPreviewFrameLevel(handle._iconTextLayer,
        baseLevel + (layers.AURA_TEXT_LEVEL_OFFSET or 8))
end

local function FinalizeLevels(scene, hostStrata)
    local RenderState, mock, conf = scene.S, scene.mock, scene.conf
    local layers = RenderState.Layers
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle = RenderState[lane[2]]
        if handle then
            ApplyHandleStrata(scene, handle, hostStrata)
            local level = SetPreviewFrameLevel(handle, PreviewElementLevel(mock, layers, scene[lane[3]].layer, lane[5], 0))
            if handle._msufEngineFrameLevel then SetPreviewFrameLevel(handle, handle._msufEngineFrameLevel) end
        end
    end
    for i = 1, #RenderState.statusHandles do
        local handle = RenderState.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            local cfg = RenderState.RuntimeStatusConfig(scene.runtimeStatus, spec)
            SetPreviewFrameLevel(handle, handle._msufEngineFrameLevel or PreviewElementLevel(mock, layers,
                cfg and cfg.layer or spec and conf[spec.layer], spec and spec.defaultLayer or 7, 8))
        end
    end
    -- Dispel symbol row. Same foreground band as the aura handles so its Effect
    -- Layer slider is judgeable against them in the preview, mirroring the live
    -- DispelSensorFrameLevel (frame base + aura icon base + configured layer).
    -- Without this the handle kept its creation-time level and the slider looked
    -- dead in the preview while it worked on the real frame.
    local dispelSymbolCfg = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    if RenderState.dispelSymbolHandle then
        ApplyHandleStrata(scene, RenderState.dispelSymbolHandle, hostStrata)
        SetPreviewFrameLevel(RenderState.dispelSymbolHandle,
            RenderState.dispelSymbolHandle._msufEngineFrameLevel
                or PreviewElementLevel(mock, layers, dispelSymbolCfg and dispelSymbolCfg.layer, 8, 8))
    end
    FinalizeSpellLevels(scene, hostStrata)
    for i = 1, #TEXT_LEVEL_SPECS do
        local item = TEXT_LEVEL_SPECS[i]
        SetPreviewFrameLevel(scene.textHandles[item[1]],
            PreviewElementLevel(mock, layers, scene.runtimeText[item[2]] or conf[item[3]], item[4], 8))
    end
end

local ENGINE_TEXT_FIELDS = { "nameText", "hpTextLeft", "hpTextCenter", "hpTextRight",
    "powerTextLeft", "powerTextCenter", "powerTextRight" }
-- Shown state and layer alpha of the handles that follow a settings layer.
local function FinalizeVisibility(scene)
    local RenderState = scene.S
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle, key = RenderState[lane[2]], lane[1]
        if handle then
            handle:SetShown(scene.layerAvailable[key] and SceneLayerOn(scene, key))
            handle:SetAlpha(SceneLayerAlpha(scene, key) * (scene.engineAlpha or 1))
        end
    end
    for i = 1, #RenderState.statusHandles do
        local handle = RenderState.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            handle:SetShown(RenderState.StatusSpecInMode(spec, scene.statusSpec)
                and SceneStatusAvailable(scene, spec) and SceneLayerOn(scene, "status"))
            handle:SetAlpha(SceneLayerAlpha(scene, "status") * (scene.engineAlpha or 1))
        end
    end
    local spellVisible = scene.layerAvailable.si and SceneLayerOn(scene, "si")
    local selectedEffectOwner = scene.box._msufGFSelectedSpellEffectOwner
    if selectedEffectOwner then
        selectedEffectOwner:SetShown(spellVisible and scene.selectedSpellEffectAvailable == true)
    end
    local selected = scene.selectedSpellCfg
    RenderState.spellHandle:SetShown(spellVisible)
    RenderState.spellHandle:SetAlpha(selected and selected.enabled == false and SceneLayerAlpha(scene, "si") * 0.45
        or SceneLayerAlpha(scene, "si"))
    for _, handle in pairs(scene.dynamicSpellHandlesActive or {}) do
        handle:SetShown(spellVisible)
        handle:SetAlpha(SceneLayerAlpha(scene, "si"))
    end
    for i = 1, #TEXT_HANDLE_KEYS do scene.textHandles[TEXT_HANDLE_KEYS[i]]:SetAlpha(SceneLayerAlpha(scene, "text")) end
    local frame, helpers = scene.mock._cell, M.PreviewHelpers
    if frame then
        local textAlpha = SceneLayerAlpha(scene, "text")
        for i = 1, #ENGINE_TEXT_FIELDS do
            helpers.ApplyGroupSceneLayerAlpha(scene.box, frame[ENGINE_TEXT_FIELDS[i]], textAlpha)
        end
        helpers.ApplyGroupSceneLayerAlpha(scene.box, frame.targetPowerBar, SceneLayerAlpha(scene, "power"))
        local bar, trail = frame.targetPowerBar, frame.powerLossTrail
        if bar and trail and bar._msufChunkedLoss then
            local pool = trail._msufLossTrailPool
            local alpha = bar:GetStatusBarTexture():GetAlpha() * bar:GetAlpha()
            for i = 1, pool and #pool or 1 do
                local snapshot = pool and pool[i] or trail
                local fill = snapshot:GetStatusBarTexture()
                if fill:GetAlpha() ~= alpha then fill:SetAlpha(alpha) end
                if not bar:IsShown() then snapshot:Hide() end
            end
        end
    end
end

-- The out-of-range fade of the Options preview: whole frame, or the health bar and its prediction bars only.
local function FinalizeRangeFade(scene)
    local box, mock = scene.box, scene.mock
    local rangeAlpha = tonumber(box._msuf2RangeFadePreviewAlpha)
    if rangeAlpha ~= nil then rangeAlpha = max(0, min(1, rangeAlpha)) end
    local rangeHealthOnly = rangeAlpha ~= nil and box._msuf2RangeFadePreviewLayerMode == "health"
    local wholeFrameMul = rangeAlpha ~= nil and not rangeHealthOnly and rangeAlpha or 1
    local healthMul = rangeHealthOnly and rangeAlpha or 1
    if mock.SetAlpha then mock:SetAlpha(wholeFrameMul) end
    if mock._health and mock._health.SetAlpha then mock._health:SetAlpha(healthMul) end
    local trail = mock._cell and mock._cell.healthLossTrail
    if trail and mock._health._msufChunkedLoss then
        local fill = trail:GetStatusBarTexture()
        local alpha = mock._health:GetStatusBarTexture():GetAlpha() * healthMul
        if fill:GetAlpha() ~= alpha then
            fill:SetAlpha(alpha)
        end
    end
    -- The engine paints each prediction bar at its configured opacity (the bar's alpha): the range fade scales it.
    for i = 1, #PREDICTION_BAR_FIELDS do
        local bar = mock[PREDICTION_BAR_FIELDS[i]]
        if bar and bar.SetAlpha then bar:SetAlpha((tonumber(bar._msufA) or 1) * healthMul) end
    end
    for i = 1, #(box._handleList or {}) do
        local handle = box._handleList[i]
        if handle and handle.SetAlpha and handle.GetParent and handle:GetParent() ~= mock then
            handle:SetAlpha((handle.GetAlpha and handle:GetAlpha() or 1) * wholeFrameMul)
        end
    end
end

local function FinalizeScene(scene)
    local RenderState, box = scene.S, scene.box
    PlaceTextHandles(scene)
    FinalizeLevels(scene, PreviewHostStrata(scene))
    FinalizeVisibility(scene)
    FinalizeRangeFade(scene)
    local visibleLayerButtonCount = 0
    for i = 1, #box._layerButtons do
        local button = box._layerButtons[i]
        local visible = button._layerKey ~= "portrait" or scene.kind == "party"
        if button.SetShown then button:SetShown(visible) end
        if visible then visibleLayerButtonCount = visibleLayerButtonCount + 1 end
        local available = scene.layerAvailable[button._layerKey] ~= false
        button._layerAvailable = available
        if button.Refresh then button:Refresh() end
    end
    box._visibleLayerButtonCount = visibleLayerButtonCount
    M.PreviewHelpers.RefreshSampleEffectHint(box)
    -- The in-world dummies answer to the same rail. Pushing from here instead of
    -- from the chip's OnClick covers every route into the state -- click, Shift
    -- solo, Search command, page re-entry -- and the engine compares a
    -- signature, so a refresh that changed nothing costs one string.
    if scene.gf and scene.gf.SetPreviewLayerFilter then
        scene.gf.SetPreviewLayerFilter(scene.layerVisible, scene.soloLayer)
    end
    if box._selectedHandle and box._selectedHandle.IsShown and not box._selectedHandle:IsShown() then RenderState.SelectHandle(nil) end
    RenderState.RefreshHandleSelection(box)
end

--- Render stages. Each renders one slice of the mock from a shared per-refresh
--- state table (the Refresh stages also take the install-time env table);
--- RenderAuras and Stage.Refresh run them in the original order.

-- Specialize owners at load; refresh and animation keep the original call graph.
SceneAuraLaneAvailable, SceneAuraLaneTextAvailable, PreviewIconScale, AURA_LANES, BuildSceneAuraLanes, RenderAuras = M.GroupRenderFactories.Auras(
    MSUF, M, wipe, max, Stage
)
TEXT_HANDLE_KEYS, TEXT_LEVEL_SPECS, TEXT_SLOT_HANDLE_KEYS, EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT = M.GroupRenderFactories.Frame(
    { Core = MSUF, Menu = M, Exports = CoreExports, EnsureDB = EnsureDB, IsSecret = issecretvalue },
    { Render = Render, Stage = Stage, RenderAuras = RenderAuras, AuraLanes = AURA_LANES,
        ExtraOptions = MENU_EXTRA_OPTIONS, AdditionalPrefixes = ADDITIONAL_PREVIEW_PREFIXES },
    { PixelLayoutRegion = PixelLayoutRegion, Floor = floor, Max = max, Min = min },
    { API = Layers, SetFrameLevel = SetPreviewFrameLevel, ElementLevel = PreviewElementLevel, IsOn = SceneLayerOn, Alpha = SceneLayerAlpha }
)
BuildSceneSpells, FinalizeSpellLevels, SuspendHandleEffects = M.GroupRenderFactories.Spells(
    { Core = MSUF, Menu = M, Wipe = wipe },
    { PixelLayoutRegion = PixelLayoutRegion, Floor = floor, Max = max, Min = min, IconScale = PreviewIconScale },
    { API = Layers, SetFrameLevel = SetPreviewFrameLevel, ElementLevel = PreviewElementLevel,
        ApplyHandleStrata = ApplyHandleStrata, SyncIconDetailLevels = SyncIconDetailLevels },
    { Finalize = FinalizeScene, Stage = Stage, EmptyAppearance = EMPTY_APPEARANCE, SelectedPlacedDefault = SELECTED_SPELL_PLACED_DEFAULT }
)

Render.Components = { Plan = BuildScene, Auras = RenderAuras, Finalize = FinalizeScene }
Render.ComponentOrder = { "Plan", "FrameAndText", "Auras", "Indicators", "Finalize" }
local KEY_NUDGE = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

--- Installs the group preview renderer into the preview host. Native.lua owns
--- frame creation and input handles; this function owns repeated composition
--- from compiled group specs, visible layers, zoom state, and selected handles.
function Render.Install(box, ctx, deps)
    if not box then return end
    deps = deps or {}
    local M = deps.M or M
    local mock = deps.mock or box._mock
    local selectedSpellEffectOwner = box._msufGFSelectedSpellEffectOwner
    if not selectedSpellEffectOwner then
        selectedSpellEffectOwner = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
        selectedSpellEffectOwner:EnableMouse(false)
        selectedSpellEffectOwner:SetAllPoints(mock)
        box._msufGFSelectedSpellEffectOwner = selectedSpellEffectOwner
    end
    local env = {
        floor = floor, max = max, min = min, ceil = ceil,
        H = deps.H or {}, M = M, MSUF = deps.MSUF or MSUF or {}, T = deps.T or M.Theme or {},
        ctx = ctx, width = tonumber(deps.width) or 720, mock = mock,
        WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8",
        GF_PREVIEW_NAMES = deps.NAMES or {}, GF_PREVIEW_CLASSES = deps.CLASSES or {},
        GF_AURA_MOCK_ICON_IDS = deps.AURA_MOCK_ICON_IDS or {},
        GF_PREVIEW_MIN_W = tonumber(deps.MIN_W) or 380, GF_PREVIEW_MIN_H = tonumber(deps.MIN_H) or 130,
        GF_PREVIEW_ROLE = deps.ROLE or "HEALER", GF_PREVIEW_ANCHOR_FRAC = deps.ANCHOR_FRAC or {},
        statusHandles = deps.statusHandles or {}, statusSpecs = deps.statusSpecs or {},
        ApplyBoundsGuide = deps.ApplyBoundsGuide or Fallbacks.Noop,
        Layers = Layers, issecretvalue = issecretvalue, box = box, selectedSpellEffectOwner = selectedSpellEffectOwner,
    }
    for i = 1, #GROUP_RENDER_FALLBACKS do
        local row = GROUP_RENDER_FALLBACKS[i]
        env[row[1]] = deps[row[1]] or row[2]
    end
    box._msufGFRenderState = env
    function box:SuspendSpellPreviewEffects()
        for _, handle in pairs(self._spellIndicatorHandles or {}) do SuspendHandleEffects(env, handle) end
        SuspendHandleEffects(env, env.spellHandle)
        SuspendHandleEffects(env, selectedSpellEffectOwner)
    end
    --- Refresh is menu-only. It reads compiled/runtime-like specs to draw a mock
    --- group frame and must not rebuild secure headers or subscribe to roster
    --- events.
    function box:Refresh(reason)
        return Stage.Refresh(env, self, reason)
    end
    function box:RefreshAnimation()
        return Stage.Animate(env, self)
    end
    local RefreshHandleSelection, NudgeHandlePosition = env.RefreshHandleSelection, env.NudgeHandlePosition
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    -- Key repeat runs this handler: arrow keys nudge the selected handle and Tab steps through the
    -- placed handles; every other key (and any key typed into an edit box) passes through to the game.
    -- Kept inline, with no helper call per key.
    box:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then
            self._selectedHandle = nil
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            RefreshHandleSelection(self)
            return
        end
        local focusFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        -- Tab steps through the placed handles. Overlapping elements in dense
        -- corners cannot all be reached by clicking, so keyboard traversal is
        -- the only way to select what sits underneath. It also works with
        -- nothing selected yet, and never while an edit box has focus.
        if key == "TAB" and not focusFrame and M.PreviewSelectionBar then
            if M.PreviewSelectionBar.CycleHandle(self, IsShiftKeyDown and IsShiftKeyDown()) then
                if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
                return
            end
        end
        local handle, nudge = self._selectedHandle, KEY_NUDGE[key]
        if not handle or handle._locked or focusFrame or not nudge then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        NudgeHandlePosition(handle, nudge[1], nudge[2])
        RefreshHandleSelection(self)
    end)
end

--- Group preview refresh: the combat and text-drag guards, then every stage in
--- the original order over one shared per-refresh state table.
function Stage.Refresh(env, self, reason)
    if (InCombatLockdown and InCombatLockdown()) or MSUF_InCombat == true then
        self._msufGFRefreshAfterCombat = reason or self._msufGFRefreshAfterCombat or true
        return
    end
    if self._msufGFTextDragActive and reason ~= "GROUP_PREVIEW_TEXT_DRAG" and reason ~= "GROUP_PREVIEW_TEXT_DRAG_END" then
        self._msufGFRefreshReason = reason or self._msufGFRefreshReason
        return
    end
    -- One state table per preview box, emptied for each refresh: the stages
    -- share it without a new table per repaint (review R7 item 9).
    local st = self._msufGFRefreshState
    if st then wipe(st) else
        st = {}
        self._msufGFRefreshState = st
    end
    st.env, st.self, st.reason = env, self, reason
    M.PreviewHelpers.RestoreGroupSceneHandles(self)
    Stage.PrepareScene(st, env)
    Stage.LayoutMockFrame(st, env)
    Stage.ResolveFont(st, env)
    Stage.RenderCell(st, env)
    Stage.PlacePowerHandle(st, env)
    Stage.RenderChrome(st, env)
    Stage.RenderBoundsAndAuras(st, env)
    Stage.ConfigureStatusHandles(st, env)
    Stage.RenderSpellIndicators(st, env)
    -- The animation tick advances this scene (Stage.Animate).
    st.complete, st.animated = true, self._animationEnabled == true
    self._msufGFScene = st
end

--- Animation tick: health, prediction and power fills, the value texts and
--- their handles, and the aura timers, stacks, swipes and duration bars follow
--- the clock on the scene the last full refresh built while the animation
--- ran. Layout, textures, fonts, layers and indicators stay as that refresh
--- placed them. False when there is no such scene (first frame, scope switch)
--- or the full refresh has to decide (combat, text drag): the driver then runs
--- it.
function Stage.Animate(env, self)
    local st = self._msufGFScene
    if not (st and st.complete == true and st.animated == true and self._animationEnabled == true) then return false end
    if (InCombatLockdown and InCombatLockdown()) or MSUF_InCombat == true or self._msufGFTextDragActive then
        return false
    end
    local scene = st.scene
    if scene.kind ~= scene.H.CurrentScope() then return false end
    if self._dragFrame and self._dragFrame._handle then return true end
    M.PreviewHelpers.RestoreGroupSceneHandles(self, false, true)
    st.animatingSamples = true
    -- The scene's own clock: the engine repaints bars, texts and prediction at this elapsed time.
    local sample = self._msufGFCellSample
    if sample.portrait.castSpellIcon then sample.portrait.texture = scene.S.CurrentSpellTexture(scene.kind) end
    if self._scene then self._scene:SetClock(self._animationElapsed) end
    PlaceTextHandles(scene)
    local RenderState = scene.S
    scene.gf.AnimateUnitFrameAuras(st.mock._cell, tonumber(self._animationElapsed) or 0)
    Stage.RenderChrome(st)
    RenderAuras(scene)
    Stage.ConfigureStatusHandles(st, env)
    if scene.engineConfig and scene.engineConfig.spellIndicators then Stage.RenderSpellIndicators(st, env)
    else FinalizeScene(scene) end
    st.animatingSamples = nil
    return true
end

-- Scene fields the refresh state carries flat (Stage.LayoutMockFrame reads them from there).
local STAGE_SCENE_FIELDS = {
    "kind", "label", "conf", "gf", "runtimeSpec", "runtimeHealth", "runtimePower", "runtimeBorder",
}

--- Rebases the preview frame-level band and builds the scene the later
--- stages share.
function Stage.PrepareScene(st, env)
    local reason, self = st.reason, st.self
    local mock = env.mock
    -- Rebase the cached preview into a deterministic local level band before
    -- reading or painting any scene state. Ancestor level changes are not a
    -- render input and must never leak into configured layer calculations.
    local previewRootLevel = SafePreviewFrameLevel(self.GetFrameLevel and self:GetFrameLevel() or 0)
    SetPreviewFrameLevel(self._stage, previewRootLevel + 2)
    SetPreviewFrameLevel(self._layers, previewRootLevel + 3)
    SetPreviewFrameLevel(mock, previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
    -- One constant translation preserves the exact live ElementLevel order
    -- while keeping every preview visual above the raised mock body.
    mock._msufPreviewElementLevelBias = mock.GetFrameLevel and (mock:GetFrameLevel() or 0)
        or (previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
    if self._dragFrame then
        SetPreviewFrameLevel(self._dragFrame, PreviewInteractionLevel(mock, Layers, 2))
    end
    local scene = BuildScene(self, reason)
    if self.RefreshRoleButton then self:RefreshRoleButton(scene.kind) end
    for i = 1, #STAGE_SCENE_FIELDS do
        local key = STAGE_SCENE_FIELDS[i]
        st[key] = scene[key]
    end
    st.scene = scene
end
