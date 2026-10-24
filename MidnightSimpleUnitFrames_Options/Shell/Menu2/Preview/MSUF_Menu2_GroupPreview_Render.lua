--- Group preview render/composition.
---
--- Native creates the preview host and interaction handles; this module owns
--- the options composition path that binds engine regions to preview handles.
local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Menu2/GroupPreview_Render"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", FILE).MockAuraPainter, "MSUF: missing core mock aura painter")
local PaintSwipe, PaintDurationBar = AuraPainter.Swipe, AuraPainter.DurationBar
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
local SPELL_PREVIEW_ROUNDED_OPTS = {
    bgKey = "_msufSpellRoundedBg",
    edgeKey = "_msufSpellRoundedEdge",
    stackKey = "_msufSpellRoundedEdgeStack",
    countKey = "_msufSpellRoundedEdgeCount",
    whiteTexture = "Interface\\Buttons\\WHITE8X8",
    edgeLayer = "OVERLAY",
    edgeSubLevel = 1,
    maxEdgeSize = 16,
    baseEdgeColor = function(host)
        return host._msufSpellRoundedR or 1, host._msufSpellRoundedG or 1,
            host._msufSpellRoundedB or 1, host._msufSpellRoundedA or 1
    end,
}
local function SetRoundedSpellPreview(root, target, shown, thickness, r, g, b, a, blendMode)
    local helpers = M.PreviewHelpers or {}
    local host = root and root._msufSpellRoundedHost
    local bars = shown and EnsureDB().bars
    if not (bars and bars.roundedFramesEnabled == true and bars.roundedGroupFrames ~= false)
        or not (helpers.ResolveRoundedMedia and helpers.EnsureRoundedVisuals
            and helpers.ApplyRoundedEdgeStack) then
        if host and helpers.SetRoundedEdgeStackShown then
            helpers.SetRoundedEdgeStackShown(host, false, SPELL_PREVIEW_ROUNDED_OPTS)
        end
        return false
    end
    if not host then
        host = PixelLayoutRegion(CreateFrame("Frame", nil, root))
        host:EnableMouse(false)
        root._msufSpellRoundedHost = host
    end
    host:ClearAllPoints()
    host:SetAllPoints(target)
    host._msufSpellRoundedR, host._msufSpellRoundedG = r, g
    host._msufSpellRoundedB, host._msufSpellRoundedA = b, a
    local _, edgePath, strength = helpers.ResolveRoundedMedia()
    SPELL_PREVIEW_ROUNDED_OPTS.edgeTexture = edgePath
    SPELL_PREVIEW_ROUNDED_OPTS.mediaStrength = strength
    SPELL_PREVIEW_ROUNDED_OPTS.snapOff = helpers.SnapOff
    if not helpers.EnsureRoundedVisuals(host, SPELL_PREVIEW_ROUNDED_OPTS)
        or not helpers.ApplyRoundedEdgeStack(host, thickness, SPELL_PREVIEW_ROUNDED_OPTS) then
        return false
    end
    if host._msufSpellRoundedBg then host._msufSpellRoundedBg:Hide() end
    if helpers.ForEachRoundedEdge then
        helpers.ForEachRoundedEdge(host, SPELL_PREVIEW_ROUNDED_OPTS, function(edge)
            if edge.SetBlendMode then edge:SetBlendMode(blendMode or "BLEND") end
        end)
    end
    host:Show()
    return true
end
local SetPreviewFrameLevel, PreviewElementLevel, PreviewInteractionLevel

local function PaintGroupPreviewPortrait(scene)
    local frame, handle = scene.mock._cell, scene.S.portraitHandle
    if not frame then return end
    local portrait = frame.MSUFSpec and frame.MSUFSpec.portrait
    local holder = frame.MSUFPortraitHolder
    local shown = scene.kind == "party" and portrait and portrait.enabled == true
    -- The engine owns mask, border, shadow, artwork, opacity and placement.
    if holder then
        holder:SetShown(shown and scene.layerVisible.portrait ~= false)
    end
    if shown and frame.portrait then
        if portrait.castSpellIcon == true and scene.box._animationEnabled == true then
            frame.portrait:SetTexture(scene.S.CurrentSpellTexture(scene.kind))
            frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif portrait.render ~= "CLASS" and SetPortraitTexture then
            SetPortraitTexture(frame.portrait, "player")
        end
    end
    local helpers = M.PreviewHelpers
    helpers.BindGroupSceneHandle(handle, scene.mock, holder, scene.previewScale, nil,
        tonumber(portrait and portrait.x) or 0, tonumber(portrait and portrait.y) or 0)
    if handle then
        handle._locked = portrait and portrait.placement == "OVERLAY" and portrait.overlayAlign == "FULL"
        handle:SetAlpha((scene.soloLayer and scene.soloLayer ~= "portrait" and 0.15 or 1) * (scene.engineAlpha or 1))
    end
    scene.mock._msufGroupPortrait = holder
end

-- Kept as a narrow module seam so the interaction smoke can exercise the
-- exact production portrait painter with a real preview Button.
Render.PaintGroupPreviewPortrait = PaintGroupPreviewPortrait

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
    { "NudgeHandlePosition", Fallbacks.Noop }, { "AddIconPool", Fallbacks.Noop }, { "RefreshHandleSelection", Fallbacks.Noop },
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
local EMPTY_RAW_LANE = {}
-- Tracked lane field -> the tracked buff setting it copies as it stands.
local TRACKED_LANE_COPIES = {
    showCooldownSwipe = "trackedShowCooldownSwipe", cooldownSwipeReverse = "trackedCooldownSwipeReverse",
    showCooldown = "trackedShowCooldown", showCooldownText = "trackedShowCooldown", showStacks = "trackedShowStacks",
    showTooltip = "trackedShowTooltip", showDurationBar = "trackedShowDurationBar",
    durationBarHeight = "trackedDurationBarHeight", durationBarDisplay = "trackedDurationBarDisplay",
    durationBarPosition = "trackedDurationBarPosition", durationBarDirection = "trackedDurationBarDirection",
    cooldownSize = "trackedCooldownSize", cooldownAnchor = "trackedCooldownAnchor", cooldownX = "trackedCooldownX",
    cooldownY = "trackedCooldownY", cooldownDecimalSeconds = "trackedCooldownDecimalSeconds",
    stackSize = "trackedStackSize", stackAnchor = "trackedStackAnchor", stackX = "trackedStackX", stackY = "trackedStackY",
}
local function RawTrackedBuffLane(scene, rawBuff, out)
    rawBuff = rawBuff or EMPTY_RAW_LANE
    local indicators = scene.conf.spellIndicators
    out.enabled = rawBuff.trackedEnabled == true
        or (rawBuff.trackedEnabled == nil and indicators and indicators.enabled == true)
    out.max = rawBuff.trackedMax or 8
    out.perRow = rawBuff.trackedPerRow or rawBuff.perRow or 4
    out.size = rawBuff.trackedSize or rawBuff.size or 22
    out.spacing = rawBuff.trackedSpacing or rawBuff.spacing or 1
    out.anchor = rawBuff.trackedAnchor or "TOPLEFT"
    out.growth = rawBuff.trackedGrowth or "RIGHTDOWN"
    out.x = rawBuff.trackedX or 0
    out.y = rawBuff.trackedY or 0
    out.layer = rawBuff.trackedLayer or (indicators and indicators.layer) or 9
    out.strata = rawBuff.trackedStrata or (indicators and indicators.strata) or rawBuff.strata
    for field, setting in pairs(TRACKED_LANE_COPIES) do out[field] = rawBuff[setting] end
    return out
end

local function SceneStatusAvailable(scene, spec)
    if scene.runtimeSpec then
        local cfg = scene.S.RuntimeStatusConfig(scene.runtimeStatus, spec)
        return cfg and cfg.enabled == true
    end
    return scene.S.StatusSpecEnabled(scene.conf, spec)
end

local function SceneAuraLaneAvailable(scene, cfg, defaultMax)
    return scene.customRenderer
        and (scene.runtimeAuras and cfg.enabled == true or cfg.enabled ~= false)
        and (tonumber(cfg.max) or defaultMax or 0) > 0
end

--- A compiled Auras3 lane carries a resolved layout signature; a raw config
--- never does. The two spell the cooldown text differently, so every reader of
--- that flag has to branch on the same test.
local function IsRuntimeAuraLane(cfg)
    return cfg._msufA3LayoutSignature ~= nil and cfg.initialAnchor ~= nil
        and cfg.xSign ~= nil and cfg.ySign ~= nil
end

--- The CD/Stack chip owns the timer and stack texts printed on the aura icons,
--- so it is only "on in settings" when a lane that draws icons actually prints
--- one of them. Reporting it available off the bare lane made the chip claim a
--- layer that had nothing to show.
local function SceneAuraLaneTextAvailable(scene, cfg, defaultMax)
    if not SceneAuraLaneAvailable(scene, cfg, defaultMax) then return false end
    if cfg.showStacks ~= false then return true end
    if IsRuntimeAuraLane(cfg) then return cfg.showCooldownText == true end
    return cfg.showCooldown ~= false
end

local function SceneLayerOn(scene, key)
    return scene.layerAvailable[key] ~= false and scene.layerVisible[key] ~= false
end

local function SceneLayerAlpha(scene, key)
    if scene.layerAvailable[key] == false then return 0 end
    return scene.soloLayer and scene.soloLayer ~= key and 0.15 or 1
end

local function ApplyPreviewIconZoom(texture, zoom, baseInset)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    baseInset = tonumber(baseInset) or 0
    local visible = (1 - (baseInset * 2)) * (100 / zoom)
    local inset = math.max(MSUF.MSUF_Auras3.IconShape.IconZoomInset(zoom), (1 - visible) * 0.5)
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local AURA_PREVIEW_RAW_FIELDS = {
    "showCooldownSwipe", "cooldownSwipeReverse", "showCooldown", "showCooldownText", "showStacks", "showTooltip",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY", "cooldownDecimalSeconds",
    "stackSize", "stackAnchor", "stackX", "stackY", "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
}

local function OverlayRawAuraPreviewStyle(compiled, raw)
    if type(compiled) ~= "table" or type(raw) ~= "table" then return compiled end
    for i = 1, #AURA_PREVIEW_RAW_FIELDS do
        local key = AURA_PREVIEW_RAW_FIELDS[i]
        if raw[key] ~= nil then compiled[key] = raw[key] end
    end
    return compiled
end

local function PreviewIconScale(value)
    value = tonumber(value) or 100
    if value < 20 then value = 20 elseif value > 300 then value = 300 end
    return value / 100
end

-- The four aura lanes in paint order: lane key, handle field, config field, default max icons, default layer.
local AURA_LANES = {
    { "buff", "buffHandle", "buffCfg", 6, 5 },
    { "trackedBuff", "trackedBuffHandle", "trackedBuffCfg", 4, 9 },
    { "debuff", "debuffHandle", "debuffCfg", 6, 6 },
    { "external", "externalHandle", "externalCfg", 2, 7 },
}
-- Scene field -> compiled spec section.
local RUNTIME_SPEC_SECTIONS = {
    runtimeText = "text", runtimePower = "power", runtimeHealth = "health", runtimeBorder = "border",
    runtimeTempMaxHealth = "tempMaxHealth", runtimePrediction = "prediction", runtimeStatus = "status",
}

local function EffectKind(effect)
    return type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
end

local function EffectShown(effect)
    local kind = EffectKind(effect)
    return kind ~= "" and kind ~= "none"
end

-- The compiled lane when the runtime resolved one, else the lane rebuilt into a table kept per preview box,
-- else the raw settings.
local function ResolveLaneConfig(scene, runtimeLanes, key, raw, lanes)
    local cfg = runtimeLanes and runtimeLanes[key]
    if cfg then return cfg end
    cfg = scene.runtimeAuras and scene.S.CompiledAuraLane(scene.runtimeAuras, key, raw or {}, lanes[key])
    return cfg or raw or {}
end

local function BuildSceneAuraLanes(scene, box, kind, conf, runtimeSpec)
    local rawAuras = conf.auras or {}
    local trackedRawState = box._msufGFTrackedRawState
    if not trackedRawState then
        trackedRawState = {}
        box._msufGFTrackedRawState = trackedRawState
    end
    local trackedRaw = RawTrackedBuffLane(scene, rawAuras.buff, trackedRawState)
    local a3 = scene.MSUF and scene.MSUF.MSUF_Auras3
    local runtimeAuraConfig
    if runtimeSpec and a3 and a3.ResolveAuraPreviewConfig then
        local proxy = box._msufA3GroupPreviewConfigProxy or {}
        box._msufA3GroupPreviewConfigProxy = proxy
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = kind
        proxy.MSUFUnitKey = "player"
        proxy.MSUFSpec = runtimeSpec
        runtimeAuraConfig = a3.ResolveAuraPreviewConfig(proxy, "player")
    end
    scene.runtimeAuraConfig = runtimeAuraConfig
    local runtimeLanes = runtimeAuraConfig and runtimeAuraConfig.lanes
    scene.rawAuras = rawAuras
    scene.auraIconZoom = tonumber(rawAuras.iconZoom) or tonumber(scene.runtimeAuras and scene.runtimeAuras.iconZoom) or 100
    -- Compiled lanes are rebuilt into tables kept per preview box.
    local lanes = box._msufGFCompiledLaneState
    if not lanes then
        lanes = { buff = {}, trackedBuff = {}, debuff = {}, external = {} }
        box._msufGFCompiledLaneState = lanes
    end
    scene.buffCfg = ResolveLaneConfig(scene, runtimeLanes, "buff", rawAuras.buff, lanes)
    scene.trackedBuffCfg = ResolveLaneConfig(scene, runtimeLanes, "trackedBuff", trackedRaw, lanes)
    scene.debuffCfg = ResolveLaneConfig(scene, runtimeLanes, "debuff", rawAuras.debuff, lanes)
    scene.externalCfg = ResolveLaneConfig(scene, runtimeLanes, "external", rawAuras.externals, lanes)
    if not runtimeLanes then
        OverlayRawAuraPreviewStyle(scene.buffCfg, rawAuras.buff)
        OverlayRawAuraPreviewStyle(scene.trackedBuffCfg, trackedRaw)
        OverlayRawAuraPreviewStyle(scene.debuffCfg, rawAuras.debuff)
        OverlayRawAuraPreviewStyle(scene.externalCfg, rawAuras.externals)
    end
end

-- The selected spell, its placement and frame effect, and the spell items the preview paints.
local function BuildSceneSpells(scene, box, kind, conf)
    local RenderState = scene.S
    scene.statusSpec = RenderState.CurrentStatusSpec()
    scene.selectedSpellCfg = RenderState.CurrentSpellConfig(kind)
    -- The selected frame effect belongs to the selected spell, not to whichever
    -- preview handle happens to render it.  Runtime compilation can temporarily
    -- hand ownership back to the fallback handle across Edit Mode transitions.
    scene.selectedSpellEffect = scene.selectedSpellCfg and scene.selectedSpellCfg.frame
    scene.selectedSpellEffectAvailable = EffectShown(scene.selectedSpellEffect)
    local _, selectedSpellSpecKey, selectedSpellAuraName = RenderState.CurrentSpellInfo(kind)
    scene.selectedSpellSpecKey = selectedSpellSpecKey
    scene.selectedSpellAuraName = selectedSpellAuraName
    scene.previewAllSpecSpellIcons = RenderState.PreviewAllSpecSpellIcons(kind) == true
    scene.rawSelectedPlaced = scene.selectedSpellCfg and scene.selectedSpellCfg.placed
    scene.selectedPlaced = RenderState.CurrentSpellPlaced(kind)
    scene.selectedSpellPlacedEnabled = scene.selectedPlaced
        and (scene.selectedPlaced.type or "icon") ~= "none"
    scene.selectedSpellNeedsPlacementPreview = scene.selectedSpellCfg ~= nil and scene.rawSelectedPlaced == nil
    local runtimeAuraConfig = scene.runtimeAuraConfig
    local exactSpellRoot = runtimeAuraConfig and runtimeAuraConfig.spellIndicators
    scene.runtimeSpellIndicators = exactSpellRoot or (scene.runtimeSpec and scene.runtimeSpec.spellIndicators)
    scene.spellIconZoom = tonumber(scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.iconZoom)
        or tonumber(conf.spellIndicators and conf.spellIndicators.iconZoom) or 100
    scene.spellIconScale = PreviewIconScale(conf.spellIndicators and conf.spellIndicators.iconScale)
    scene.runtimeSpellItems = exactSpellRoot and exactSpellRoot.slots
        or (scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.items)
    local previewSpellItems = box._msufGFPreviewSpellItemsScratch or {}
    box._msufGFPreviewSpellItemsScratch = previewSpellItems
    wipe(previewSpellItems)
    scene.previewSpellItems = previewSpellItems
    scene.runtimeSpellPlacedAvailable = false
    scene.runtimeSpellEffectAvailable = false
    local items = scene.runtimeSpellItems
    if type(items) ~= "table" then return end
    for i = 1, #items do
        local item = items[i]
        local exactSlot = item and item.spellIndicatorSlot == true
        local selectedItem = item and item.specKey == selectedSpellSpecKey and item.auraName == selectedSpellAuraName
        local placed = exactSlot and item or (item and item.placed)
        local placedType = placed and (exactSlot and placed.visual or placed.type) or "none"
        local placedShown = placed and placedType ~= "none" and item.hiddenVisual ~= true
        local effect = item and (exactSlot and item.frameEffect or item.frame) or nil
        local effectShown = EffectShown(effect)
        -- Preview all spells mirrors the compiled runtime set instead of the
        -- one spec the editor happens to show: Multi-Spec compiles every
        -- tracked spec, and a spell whose indicator is a frame effect owns no
        -- placed icon yet still draws. Corner custom slots carry no specKey
        -- and stay out - they belong to Corner Indicators, not to this list.
        local previewAllItem = scene.previewAllSpecSpellIcons == true
            and not selectedItem and item ~= nil and item.specKey ~= nil
            and (placedShown or effectShown)
        if selectedItem or previewAllItem then
            if previewAllItem or placedShown then previewSpellItems[#previewSpellItems + 1] = item end
            if placedShown then scene.runtimeSpellPlacedAvailable = true end
            if effectShown then scene.runtimeSpellEffectAvailable = true end
            if selectedItem and effect ~= nil then
                scene.selectedSpellEffect = effect
                scene.selectedSpellEffectAvailable = effectShown
            end
        end
    end
end

-- Which settings layers have something to show. The layer table is kept per box too;
-- every refresh writes all its keys.
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

local STATUS_TEXTURE_FALLBACKS = {
    raidMarker = { "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0, 0.25, 0, 0.25 },
    readyCheck = { "Interface\\RaidFrame\\ReadyCheck-Ready", 0, 1, 0, 1 },
    summon = { "Interface\\RaidFrame\\Raid-Icon-SummonPending", 0, 1, 0, 1 },
    incomingRes = { "Interface\\RaidFrame\\Raid-Icon-Rez", 0, 1, 0, 1 },
    pvp = { "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 1, 0, 1 },
    phase = { "Interface\\TargetingFrame\\UI-PhasingIcon", 0, 1, 0, 1 },
}

local function ResolveStatusPreviewTexture(scene, spec, runtimeCfg, iconType, variant)
    local customIcon = runtimeCfg and runtimeCfg.customIcon
    if (type(customIcon) ~= "string" or customIcon == "") and spec and spec.customIcon then
        customIcon = scene.conf[spec.customIcon]
    end
    if type(customIcon) == "string" and customIcon ~= "" then return customIcon, 0, 1, 0, 1 end
    local path, l, r, t, b = CoreExports.GetStatusIconTexture("BLIZZARD", iconType, variant,
        scene.runtimeStatus and scene.runtimeStatus.useMidnight == true)
    if type(path) == "string" and path ~= "" then return path, l, r, t, b end
    local fallback = STATUS_TEXTURE_FALLBACKS[iconType]
    if fallback then return fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] end
end

local TEXT_HANDLE_KEYS = {
    "name", "hpGroup", "hpLeft", "hpCenter", "hpRight",
    "powerGroup", "powerLeft", "powerCenter", "powerRight",
}
local TEXT_LEVEL_SPECS = {
    { "name", "nameLayer", "nameTextLayer", 5 },
    { "hpGroup", "healthLayer", "textLayer", 5 },
    { "hpLeft", "healthLayer", "textLayer", 5 },
    { "hpCenter", "healthLayer", "textLayer", 5 },
    { "hpRight", "healthLayer", "textLayer", 5 },
    { "powerGroup", "powerLayer", "powerTextLayer", 2 },
    { "powerLeft", "powerLayer", "powerTextLayer", 2 },
    { "powerCenter", "powerLayer", "powerTextLayer", 2 },
    { "powerRight", "powerLayer", "powerTextLayer", 2 },
}

-- Handle keys per text slot and reused region lists: placing the text handles
-- on every repaint allocates nothing.
local TEXT_SLOT_HANDLE_KEYS = {
    hp = { "hpLeft", "hpCenter", "hpRight" },
    power = { "powerLeft", "powerCenter", "powerRight" },
}
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

local function SpellEffectPriority(value)
    return max(1, min(10, floor((tonumber(value) or 5) + 0.5)))
end

--- Mirror of Layers.AuraEffectLevel inside the preview's private band. The
--- shared renderer floors every full-frame effect above the surface it
--- recolors -- the health bar, or the Name overlay for a Name Overlay --
--- so a low Layer cannot be drawn under the very thing it tints. Rebasing
--- the root into the local band has to carry that floor along or the box
--- shows a different stacking order than the frames.
local function SpellEffectPreviewLevel(mock, layers, layer, priority, kind)
    local level = PreviewElementLevel(mock, layers, layer, 0, 11 - priority)
    local owner
    if kind == "namecolor" then
        owner = mock._nameFS and mock._nameFS.GetParent and mock._nameFS:GetParent()
    else
        owner = mock._health
    end
    local ownerLevel = owner and owner.GetFrameLevel and tonumber(owner:GetFrameLevel())
    if ownerLevel ~= nil then level = max(level, ownerLevel + 1) end
    return level
end

-- Host strata and a bounded local level for one shown frame-effect root.
local function PlaceSpellEffectRoot(scene, root, hostStrata, kind)
    if not (root and root.IsShown and root:IsShown()) then return end
    local RenderState = scene.S
    local priority = SpellEffectPriority(root._msufSpellPreviewPriority)
    local effectLayer = RenderState.ClampLayer(root._msufSpellPreviewLayer, 0)
    ApplyHandleStrata(scene, root, hostStrata)
    SetPreviewFrameLevel(root, SpellEffectPreviewLevel(scene.mock, RenderState.Layers, effectLayer, priority, kind))
end

local function PlaceIconEffectRoot(scene, root, hostStrata, handle)
    if not (root and root.IsShown and root:IsShown()) then return end
    ApplyHandleStrata(scene, root, hostStrata)
    SetPreviewFrameLevel(root, handle:GetFrameLevel() + 4)
end

-- Strata and frame level of the spell indicator handles and their effect roots.
local function FinalizeSpellLevels(scene, hostStrata)
    local RenderState, mock = scene.S, scene.mock
    local layers, box = RenderState.Layers, scene.box
    local spellHandle = RenderState.spellHandle
    local rawIndicators = scene.conf.spellIndicators or {}
    local runtimeIndicators = scene.runtimeSpellIndicators or {}
    local spellLayer = runtimeIndicators.layer ~= nil and runtimeIndicators.layer or rawIndicators.layer
    local selected = scene.selectedSpellCfg
    ApplyHandleStrata(scene, spellHandle, hostStrata)
    SetPreviewFrameLevel(spellHandle, PreviewElementLevel(mock, layers, selected and selected.layer or spellLayer, 9, 1))
    SyncIconDetailLevels(layers, spellHandle)
    local selectedEffectOwner = box._msufGFSelectedSpellEffectOwner
    -- Only one selected full-frame effect is rendered. Its configured live
    -- strata must not be translated relative to an Edit Mode preview frame:
    -- that live frame can remain on a higher strata during teardown and
    -- produce a negative local offset below the menu mock. Keep the preview
    -- root on the host strata and express priority in a bounded local band.
    PlaceSpellEffectRoot(scene, selectedEffectOwner and selectedEffectOwner._msufSpellPreviewEffectRoot, hostStrata,
        EffectKind(scene.selectedSpellEffect))
    if selectedEffectOwner then
        SetPreviewFrameLevel(selectedEffectOwner, (mock.GetFrameLevel and mock:GetFrameLevel() or 1) + 1)
    end
    PlaceIconEffectRoot(scene, spellHandle._msufSpellPreviewIconEffectRoot, hostStrata, spellHandle)
    for _, handle in pairs(scene.dynamicSpellHandlesActive or {}) do
        ApplyHandleStrata(scene, handle, hostStrata)
        SetPreviewFrameLevel(handle, handle._msufEngineFrameLevel
            or PreviewElementLevel(mock, layers, handle._msufSpellIndicatorLayer or spellLayer, 9, 1))
        SyncIconDetailLevels(layers, handle)
        local effectRoot = handle._msufSpellPreviewEffectRoot
        PlaceSpellEffectRoot(scene, effectRoot, hostStrata, effectRoot and effectRoot._msufSpellPreviewKind)
        PlaceIconEffectRoot(scene, handle._msufSpellPreviewIconEffectRoot, hostStrata, handle)
    end
end

-- Strata and frame level of the aura, status, dispel symbol, spell and text handles.
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
local Stage = {}

-- A group lane icon is size x size; the swipe and duration bar painters are the shared core ones.
local function GroupAuraPreviewSwipe(swipe, icon, size, remainingFrac, reverse)
    if not (swipe and icon) then return end
    size = tonumber(size) or 1
    PaintSwipe(swipe, icon, size, size, remainingFrac, reverse)
end
local function GroupAuraDurationBar(bar, icon, cfg, size, auraState)
    if not (bar and icon and cfg and cfg.showDurationBar == true) then
        if bar then bar:Hide() end
        return
    end
    size = math.max(1, tonumber(size) or 1)
    PaintDurationBar(bar, icon, cfg, size, size, auraState)
end
local TEXT_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local function RuntimeAuraTextAnchor(anchor, fallback)
    if TEXT_ANCHORS[anchor] then return anchor end
    return fallback or "CENTER"
end
local function BuildAuraLaneHelpers(st, RenderState)
    local mock = RenderState.mock
    local GF_PREVIEW_ANCHOR_FRAC = RenderState.GF_PREVIEW_ANCHOR_FRAC
    local Round, ConfigToOffset = RenderState.Round, RenderState.ConfigToOffset
    local function LayoutHandle(handle, anchor, x, y, defaultAnchor)
        local previewScale = st.previewScale
        anchor = anchor or defaultAnchor or "CENTER"
        if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaultAnchor or "CENTER" end
        handle._previewScale = previewScale
        handle._previewWriteScale = previewScale
        handle:ClearAllPoints()
        handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))
    end
    return { st = st, S = RenderState, LayoutHandle = LayoutHandle }
end
function Stage.PrepareAuraLanes(st)
    local scene = st.scene
    local RenderState, box = scene.S, scene.box
    local helpers = box._msufGFAuraLaneHelpers
    if not helpers or helpers.st ~= st or helpers.S ~= RenderState then
        helpers = BuildAuraLaneHelpers(st, RenderState)
        box._msufGFAuraLaneHelpers = helpers
    end
    st.previewScale = scene.previewScale
    st.LayoutHandle = helpers.LayoutHandle
end

-- Auras3 icon shape and style on a preview owner; the style is dropped while only the duration bar shows.
local function ApplyPreviewIconLook(a3, owner, shape, style, barOnly, size, tex, swipe)
    if not a3 then return end
    if a3.ApplyAuraIconShape then a3.ApplyAuraIconShape(owner, shape, nil, tex, swipe) end
    if a3.ApplyIconStylePreview then
        if barOnly then style = nil end
        a3.ApplyIconStylePreview(owner, style, size, shape)
    end
end

-- Layout preparation and visual adoption are separate cold options stages. The old
-- 233-line icon painter duplicated the engine's own lane/shape/font painters.
function Stage.PrepareAuraHandle(st, handle, groupKey, cfg)
    local scene, frame = st.scene, st.scene.mock._cell
    local hosts = frame and frame._msufGFFrameAuraPreviewHosts
    local host = hosts and hosts[groupKey]
    if not host then handle:Hide() return nil end
    -- Restore engine ownership before measuring the configured layout. A previous
    -- drag may have parented the host to its interaction handle.
    local scale = scene.previewScale
    handle._previewWriteScale = scale * ((scene.runtimeAuras and scene.runtimeAuras.dynamicScaleValue) or 1)
    return host, scale
end
function Stage.LayoutAuraGroup(st, handle, groupKey, cfg)
    local host, scale = Stage.PrepareAuraHandle(st, handle, groupKey, cfg)
    if not host then return end
    local frame = st.scene.mock._cell
    -- Engine aura visuals are pooled on the cell, with anchors in the lane host.
    -- Adopt them into that host once; native parent motion then follows a drag.
    for _, visual in ipairs(frame._msufGFFrameAuraPreviews or {}) do
        if visual._sceneAuraLane == cfg and visual:GetParent() ~= host then visual:SetParent(host) end
    end
    M.PreviewHelpers.BindGroupSceneHandle(handle, st.scene.mock, host, scale, cfg.anchor)
    local textAlpha = min(1, SceneLayerAlpha(st.scene, "auraText") / max(0.0001, SceneLayerAlpha(st.scene, groupKey)))
    for _, visual in ipairs(frame._msufGFFrameAuraPreviews or {}) do
        if visual._sceneAuraLane == cfg then
            if visual._timer then
                st.scene.SetPreviewFont(visual._timer, tonumber(cfg.cooldownSize) or 8)
                visual._timer:SetAlpha(textAlpha)
            end
            if visual._stack then
                st.scene.SetPreviewFont(visual._stack, tonumber(cfg.stackSize) or 10)
                visual._stack:SetAlpha(textAlpha)
            end
        end
    end
    handle._previewWriteScale = scale * ((st.scene.runtimeAuras and st.scene.runtimeAuras.dynamicScaleValue) or 1)
end

--- Lays out the buff, tracked buff, debuff and external lanes and publishes
--- the lane helpers on the scene for the status and spell indicator stages.
local function RenderAuras(scene)
    -- The lane state is kept per preview box and emptied for each refresh.
    local box = scene.box
    local st = box._msufGFAuraState
    if st then wipe(st) else
        st = {}
        box._msufGFAuraState = st
    end
    st.scene = scene
    -- Aura samples follow the box's animation time; a static preview has none.
    st.auraElapsed = box._animationEnabled == true and (tonumber(box._animationElapsed) or 0) or nil
    Stage.PrepareAuraLanes(st)
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle = scene.S[lane[2]]
        if handle then Stage.LayoutAuraGroup(st, handle, lane[1], scene[lane[3]]) end
    end
    scene.LayoutHandle = st.LayoutHandle
end

Render.Components = { Plan = BuildScene, Auras = RenderAuras, Finalize = FinalizeScene }
Render.ComponentOrder = { "Plan", "FrameAndText", "Auras", "Indicators", "Finalize" }

--- Spell frame-effect preview: glow textures, effect roots and the runtime
--- owner frame, plus the name overlay used by the namecolor effect. They read
--- only install-time state (env), so every refresh reuses them.
local function StopPreviewAnimation(group)
    if group and group.IsPlaying and group:IsPlaying() then group:Stop() end
end
local function HidePreviewGlow(root)
    local glow = root and root._msufSpellPreviewGlow
    if not glow then return end
    StopPreviewAnimation(glow.animation)
    glow.halo:Hide()
    glow.ants:Hide()
end
local function NewGlowTexture(root, subLevel, texture)
    local region = PixelLayoutRegion(root:CreateTexture(nil, "OVERLAY", nil, subLevel))
    region:SetTexture(texture)
    region:SetBlendMode("ADD")
    return region
end
-- The glow ants sprite sheet: 5x5 cells, 22 frames of 48x48, one loop per 0.37 s.
local GLOW_FLIPBOOK = {
    { "SetFlipBookRows", 5 }, { "SetFlipBookColumns", 5 }, { "SetFlipBookFrames", 22 },
    { "SetFlipBookFrameWidth", 48 }, { "SetFlipBookFrameHeight", 48 }, { "SetDuration", 0.37 },
}
local function EnsurePreviewGlow(env, root)
    local glow = root and root._msufSpellPreviewGlow
    if glow then return glow end
    glow = {}
    glow.halo = NewGlowTexture(root, 6, [[Interface\SpellActivationOverlay\IconAlert]])
    glow.halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    glow.ants = NewGlowTexture(root, 7, [[Interface\SpellActivationOverlay\IconAlertAnts]])
    glow.animation = glow.ants:CreateAnimationGroup()
    if env.T.TrackMenuAnimationGroup then env.T.TrackMenuAnimationGroup(glow.animation) end
    glow.animation:SetLooping("REPEAT")
    local flipbook = glow.animation:CreateAnimation("FlipBook")
    for i = 1, #GLOW_FLIPBOOK do flipbook[GLOW_FLIPBOOK[i][1]](flipbook, GLOW_FLIPBOOK[i][2]) end
    root._msufSpellPreviewGlow = glow
    return glow
end
local function PlaceGlowRegion(region, target, padding, r, g, b, a)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
    region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
    region:SetDesaturated(true)
    region:SetVertexColor(r, g, b, a)
    region:Show()
end
local function ShowPreviewGlow(env, root, target, r, g, b, a, padding)
    local glow = EnsurePreviewGlow(env, root)
    if not (glow and target) then return end
    PlaceGlowRegion(glow.halo, target, padding * 1.55, r, g, b, a)
    PlaceGlowRegion(glow.ants, target, padding, r, g, b, a)
    if not glow.animation:IsPlaying() then glow.animation:Play() end
end
local function EnsureSpellEffectPreview(env, handle)
    local root = handle and handle._msufSpellPreviewEffectRoot
    if root then return root end
    root = PixelLayoutRegion(CreateFrame("Frame", nil, handle))
    root:EnableMouse(false)
    root:SetAllPoints(env.mock._health)
    handle._msufSpellPreviewEffectRoot = root
    return root
end
local function EnsureSpellEffectRuntimeOwner(env, handle)
    if not handle then return nil end
    local mock = env.mock
    local owner = handle._msufSpellPreviewRuntimeOwner
    if not owner then
        owner = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
        owner:EnableMouse(false)
        handle._msufSpellPreviewRuntimeOwner = owner
    elseif owner.GetParent and owner:GetParent() ~= mock and owner.SetParent then
        owner:SetParent(mock)
    end
    owner:ClearAllPoints()
    owner:SetAllPoints(mock)
    return owner
end
-- Hides the Auras3 frame effect a handle's runtime owner currently shows.
local function HideRuntimePreviewEffect(env, handle)
    local a3 = env.MSUF.MSUF_Auras3
    local runtime = a3 and a3.SpellIndicators
    local owner = handle and handle._msufSpellPreviewRuntimeOwner
    if owner and runtime and runtime.HidePreviewFrameEffect then runtime.HidePreviewFrameEffect(owner) end
end
local function HideSpellEffectPreview(env, handle)
    HideRuntimePreviewEffect(env, handle)
    local root = handle and handle._msufSpellPreviewEffectRoot
    if not root then return end
    StopPreviewAnimation(root._msufSpellPreviewPulse)
    root:SetAlpha(1)
    HidePreviewGlow(root)
    root:Hide()
end
local function EnsureSpellPreviewEdges(env, root)
    if root._msufSpellPreviewEdges then return root._msufSpellPreviewEdges end
    local edges = {}
    for i = 1, 4 do
        edges[i] = PixelLayoutRegion(root:CreateTexture(nil, "OVERLAY"))
        edges[i]:SetTexture(env.WHITE8X8)
        edges[i]:Hide()
    end
    root._msufSpellPreviewEdges = edges
    return edges
end
local function HideSpellPreviewRegions(root)
    if root._msufSpellPreviewTint then root._msufSpellPreviewTint:Hide() end
    if root._msufSpellPreviewName then root._msufSpellPreviewName:Hide() end
    local edges = root._msufSpellPreviewEdges
    for i = 1, type(edges) == "table" and #edges or 0 do edges[i]:Hide() end
    SetRoundedSpellPreview(root, nil, false)
    StopPreviewAnimation(root._msufSpellPreviewPulse)
    root:SetAlpha(1)
    HidePreviewGlow(root)
end
-- Getter and setter pairs the name overlay copies from the name it recolors.
local NAME_OVERLAY_COPIES = {
    { "GetJustifyH", "SetJustifyH" }, { "GetJustifyV", "SetJustifyV" },
    { "GetShadowColor", "SetShadowColor" }, { "GetShadowOffset", "SetShadowOffset" },
}
local function SyncSpellPreviewName(root, source, r, g, b, a)
    if not source then return end
    local overlay = root._msufSpellPreviewName
    if not overlay then
        overlay = PixelLayoutRegion(root:CreateFontString(nil, "OVERLAY"))
        root._msufSpellPreviewName = overlay
    end
    local path, size, flags = source:GetFont()
    if path and size then overlay:SetFont(path, size, flags) end
    for i = 1, #NAME_OVERLAY_COPIES do
        local copy = NAME_OVERLAY_COPIES[i]
        if source[copy[1]] then overlay[copy[2]](overlay, source[copy[1]](source)) end
    end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(source)
    overlay:SetText(source:GetText())
    overlay:SetTextColor(r, g, b, a)
    overlay:SetShown(source.IsShown == nil or source:IsShown())
end

-- Spell effect edges: edge index, size setter and two anchors {point, relative edge or "target", relative point,
-- x and y in thickness units}. The side edges hang between the top and bottom ones.
local SPELL_EDGE_LAYOUT = {
    { 1, "SetHeight", { "TOPLEFT", "target", "TOPLEFT", -1, 1 }, { "TOPRIGHT", "target", "TOPRIGHT", 1, 1 } },
    { 2, "SetHeight", { "BOTTOMLEFT", "target", "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", "target", "BOTTOMRIGHT", 1, -1 } },
    { 3, "SetWidth", { "TOPLEFT", 1, "BOTTOMLEFT", 0, 0 }, { "BOTTOMLEFT", 2, "TOPLEFT", 0, 0 } },
    { 4, "SetWidth", { "TOPRIGHT", 1, "BOTTOMRIGHT", 0, 0 }, { "BOTTOMRIGHT", 2, "TOPRIGHT", 0, 0 } },
}
local function LayoutSpellPreviewEdges(env, root, target, effect, r, g, b, a)
    local edges = EnsureSpellPreviewEdges(env, root)
    local glowLike = effect.type == "glow" or effect.type == "pulse"
    local rawThickness = tonumber(effect.thickness) or (effect.type == "glow" and 3 or 2)
    local thickness = max(1, env.ScaleValue(glowLike and max(rawThickness, 3) or rawThickness, env.mock._previewScale or 1, 1))
    if glowLike then a = min(1, a * 0.85) end
    for i = 1, #SPELL_EDGE_LAYOUT do
        local row = SPELL_EDGE_LAYOUT[i]
        local edge = edges[row[1]]
        edge:ClearAllPoints()
        for j = 3, 4 do
            local anchor = row[j]
            edge:SetPoint(anchor[1], anchor[2] == "target" and target or edges[anchor[2]], anchor[3],
                anchor[4] * thickness, anchor[5] * thickness)
        end
        edge[row[2]](edge, thickness)
    end
    for i = 1, 4 do
        if edges[i].SetBlendMode then edges[i]:SetBlendMode(glowLike and "ADD" or "BLEND") end
        edges[i]:SetVertexColor(r, g, b, a)
        edges[i]:Show()
    end
    if (not glowLike and SetRoundedSpellPreview(root, target, true, thickness, r, g, b, a, "BLEND"))
        or (effect.type == "pulse" and SetRoundedSpellPreview(root, target, true, thickness, r, g, b, a, "ADD")) then
        for i = 1, 4 do edges[i]:Hide() end
    end
end

-- The Auras3 renderer's own frame effect, shown through the group mock.
local function ApplyRuntimeSpellEffect(env, runtime, handle, effect)
    local mock = env.mock
    -- The Group mock predates the runtime-shaped health/name keys.
    -- Publish the exact native surfaces expected by the shared
    -- renderer; otherwise it rejects the preview and the legacy
    -- stretched action-button glow below silently takes over.
    mock.health = mock._health
    mock.Name = mock._nameFS
    local owner = EnsureSpellEffectRuntimeOwner(env, handle)
    local legacyRoot = handle._msufSpellPreviewEffectRoot
    if legacyRoot and legacyRoot ~= owner._msufA3SpellIndicatorEffectRoot then legacyRoot:Hide() end
    local previewEffect = owner._msufSpellPreviewRuntimeEffect
    if not previewEffect then
        previewEffect = {}
        owner._msufSpellPreviewRuntimeEffect = previewEffect
    end
    local kind = EffectKind(effect)
    previewEffect.type = effect.type
    previewEffect.color = effect.color
    previewEffect.priority = effect.priority
    previewEffect.thickness = max(1, env.ScaleValue(effect.thickness
        or (kind == "glow" and 3 or 2), mock._previewScale or 1, 1))
    previewEffect.layer = effect.layer
    previewEffect.strata = effect.strata or handle._msufSpellIndicatorStrata
    previewEffect.tintAlpha = effect.tintAlpha
    if runtime.ApplyPreviewFrameEffect(owner, previewEffect, mock) then
        local runtimeRoot = owner._msufA3SpellIndicatorEffectRoot
        if runtimeRoot then
            -- FinalizeScene rebases this established preview
            -- field into the local layer band after painting.
            handle._msufSpellPreviewEffectRoot = runtimeRoot
            runtimeRoot._msufSpellPreviewStrata = previewEffect.strata
            runtimeRoot._msufSpellPreviewPriority = SpellEffectPriority(previewEffect.priority)
            runtimeRoot._msufSpellPreviewLayer = env.ClampLayer(previewEffect.layer, 0)
            runtimeRoot._msufSpellPreviewKind = kind
            return
        end
    end
    -- Runtime is authoritative when present. Never paint the old
    -- square IconAlert fallback after a rejected runtime apply.
    HideSpellEffectPreview(env, handle)
end

-- The legacy edge/glow/tint/name fallback when no runtime renderer exists.
local function ApplyLegacySpellEffect(env, handle, effect)
    local mock = env.mock
    local root = EnsureSpellEffectPreview(env, handle)
    local healthBar = mock._health
    local target = healthBar and healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture() or nil
    if not (root and healthBar and target) then
        HideSpellEffectPreview(env, handle)
        return
    end
    HideSpellPreviewRegions(root)
    root:ClearAllPoints()
    root:SetAllPoints(healthBar)
    root._msufSpellPreviewStrata = effect.strata or handle._msufSpellIndicatorStrata
    root._msufSpellPreviewPriority = SpellEffectPriority(effect.priority)
    root._msufSpellPreviewLayer = env.ClampLayer(effect.layer, 0)
    local kind = EffectKind(effect)
    root._msufSpellPreviewKind = kind
    local color = effect.color or {}
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    if kind == "healthtint" then
        local tint = root._msufSpellPreviewTint
        if not tint then
            tint = PixelLayoutRegion(root:CreateTexture(nil, "OVERLAY"))
            tint:SetTexture(env.WHITE8X8)
            root._msufSpellPreviewTint = tint
        end
        tint:ClearAllPoints()
        tint:SetAllPoints(target)
        tint:SetBlendMode("BLEND")
        local tintAlpha = tonumber(effect.tintAlpha or effect.alpha)
        if tintAlpha == nil then tintAlpha = a > 0 and a or 0.20 end
        tint:SetVertexColor(r, g, b, max(0, min(1, tintAlpha)))
        tint:Show()
    elseif kind == "namecolor" then
        SyncSpellPreviewName(root, mock._nameFS, r, g, b, a)
    elseif kind == "glow" then
        local padding = max(1, env.ScaleValue((tonumber(effect.thickness) or 3) + 2, mock._previewScale or 1, 1))
        ShowPreviewGlow(env, root, target, r, g, b, a, padding)
    elseif kind == "border" or kind == "pulse" then
        LayoutSpellPreviewEdges(env, root, target, effect, r, g, b, a)
        if kind == "pulse" then
            local pulse = root._msufSpellPreviewPulse
            if not pulse then
                pulse = root:CreateAnimationGroup()
                if env.T.TrackMenuAnimationGroup then env.T.TrackMenuAnimationGroup(pulse) end
                pulse:SetLooping("BOUNCE")
                local alpha = pulse:CreateAnimation("Alpha")
                alpha:SetDuration(0.7)
                alpha:SetFromAlpha(0.45)
                alpha:SetToAlpha(1)
                if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
                root._msufSpellPreviewPulse = pulse
            end
            if not pulse:IsPlaying() then pulse:Play() end
        end
    else
        HideSpellEffectPreview(env, handle)
        return
    end
    root:Show()
end

--- Applies one spell frame effect (border, glow, pulse, health tint, name
--- color) to a handle: the live Auras3 renderer when present, else the legacy
--- edge/glow fallback.
local function ApplySpellEffectPreview(env, handle, effect)
    if not (handle and type(effect) == "table") then return end
    local a3 = env.MSUF.MSUF_Auras3
    local runtime = a3 and a3.SpellIndicators
    if runtime and runtime.ApplyPreviewFrameEffect then
        ApplyRuntimeSpellEffect(env, runtime, handle, effect)
    else
        ApplyLegacySpellEffect(env, handle, effect)
    end
end

local function SuspendSpellPreviewRoot(root)
    if not root then return end
    StopPreviewAnimation(root._msufSpellPreviewPulse)
    HidePreviewGlow(root)
    root:Hide()
end
local function SuspendHandleEffects(env, handle)
    HideRuntimePreviewEffect(env, handle)
    SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewEffectRoot)
    SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewIconEffectRoot)
end

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
    Stage.RenderCell(st, env)
    Stage.ResolveFont(st, env)
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
    M.PreviewHelpers.RestoreGroupSceneHandles(self)
    -- The scene's own clock: the engine repaints bars, texts and prediction at this elapsed time.
    if self._scene then self._scene:SetClock(self._animationElapsed) end
    PlaceTextHandles(scene)
    local RenderState = scene.S
    scene.gf.AnimateUnitFrameAuras(st.mock._cell, tonumber(self._animationElapsed) or 0)
    Stage.RenderChrome(st)
    RenderAuras(scene)
    Stage.ConfigureStatusHandles(st, env)
    if scene.engineConfig and scene.engineConfig.spellIndicators then Stage.RenderSpellIndicators(st, env)
    else FinalizeScene(scene) end
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

--- Title, zoom resolution and the mock frame's size, position and backdrop.
function Stage.LayoutMockFrame(st, env)
        local conf, gf, kind, label = st.conf, st.gf, st.kind, st.label
        local runtimeBorder, runtimeHealth, runtimePower, runtimeSpec = st.runtimeBorder, st.runtimeHealth, st.runtimePower, st.runtimeSpec
        local self = st.self
        local ClampZoom, H, M, ResolveDefaultZoomLock = env.ClampZoom, env.H, env.M, env.ResolveDefaultZoomLock
        local Round, ScaleValue, UpdateZoomControls, WHITE8X8 = env.Round, env.ScaleValue, env.UpdateZoomControls, env.WHITE8X8
        local T = env.T
        local max, min, width = env.max, env.min, env.width
        T.SetTranslatedText(self._title, string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s",
            (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", label))
        local stageW = self._stage:GetWidth() or (width - 98)
        local stageH = self._stage:GetHeight() or 218
        if stageW <= 1 then stageW = math.max(260, width - 98) end
        if stageH <= 1 then stageH = 218 end
        local liveW, liveH, frameScale = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width) or 120,
            tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height) or 40,
            1
        if gf and gf.GetScaledFrameMetrics then
            local w2, h2, _, sc2 = gf.GetScaledFrameMetrics(kind)
            liveW = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(w2) or liveW
            liveH = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(h2) or liveH
            frameScale = tonumber(sc2) or 1
        end
        liveW, liveH = max(1, liveW), max(1, liveH)
        local additional = Stage.SyncAdditionalLayout(st, liveW, liveH)
        local hasAdditional = (self._additionalPreviewTopology or 0) > 0
        local minX, maxX, minY, maxY
        if hasAdditional then minX, maxX, minY, maxY = additional.minX, additional.maxX, additional.minY, additional.maxY end
        local autoZoom = min(self._msufGFRenderState.GF_PREVIEW_MIN_W / liveW, self._msufGFRenderState.GF_PREVIEW_MIN_H / liveH)
        autoZoom = max(1.4, min(2.8, autoZoom))
        if hasAdditional then
            -- Overview can be smaller than the interactive zoom minimum:
            -- silently clipping enabled samples is not a useful initial view.
            -- Expand and deliberate zoom retain their existing controls.
            autoZoom = min(autoZoom, min(max(1, stageW - 24) / (maxX - minX),
                max(1, stageH - 24) / (maxY - minY)))
        end
        if not hasAdditional then ResolveDefaultZoomLock(self, autoZoom) end
        local manualZoom = tonumber(self._manualZoom)
        local frozenZoom = tonumber(self._dragFrozenScale)
        local previewScale = manualZoom and ClampZoom(manualZoom) or (frozenZoom and ClampZoom(frozenZoom) or autoZoom)
        self._mockAutoScale = autoZoom
        self._mockScale = previewScale
        UpdateZoomControls(self)
        local overview = hasAdditional and not manualZoom and not frozenZoom
        local mockW = max(overview and 1 or 48, Round(liveW * previewScale))
        local mockH = max(overview and 1 or 20, Round(liveH * previewScale))
        local powerH = runtimePower and runtimePower.enabled == true and ScaleValue(runtimePower.height, previewScale, 0) or 0
        if not runtimeSpec then powerH = H.MockPowerHeight(kind, conf, previewScale, frameScale) end
        -- Runtime parity for Power.Apply's three placements: embedded (inside the
        -- frame bottom), attached-below (embed off), and detached (free geometry).
        -- Only the embedded bar insets the health bar (Health.Layout contract).
        local powerEmbed, powerDetached
        if runtimeSpec then
            powerEmbed = runtimePower.embed ~= false
            powerDetached = runtimePower.detached == true
        else
            powerEmbed = conf.embedPowerBarIntoHealth ~= false
            powerDetached = conf.powerBarDetached == true
        end
        local borderEnabled = runtimeSpec and (runtimeBorder.enabled ~= false) or (not runtimeSpec and conf.borderEnabled ~= false)
        local outline = borderEnabled and (tonumber(runtimeBorder and runtimeBorder.thickness) or 1) or 0
        if not runtimeSpec and borderEnabled and gf and gf.GetBarOutlineThickness then outline = tonumber(gf.GetBarOutlineThickness(kind)) or outline end
        local outlineEdge = max(0, Round(outline * previewScale))
        local inset = 0
        local startX = Round((stageW - mockW) * 0.5)
        local startY = -Round((stageH - mockH) * 0.5)
        if hasAdditional then
            startX = Round(stageW / 2 - (minX + maxX) / 2 * previewScale - mockW / 2)
            startY = Round(-stageH / 2 - (minY + maxY) / 2 * previewScale + mockH / 2)
            -- Deliberate zoom may crop the scene; keep its main sample reachable.
            if not overview and mockW < stageW and mockH < stageH then
                startX = max(8, min(stageW - mockW - 8, startX))
                startY = min(-8, max(-stageH + mockH + 8, startY))
            end
        end
        local mock = self._mock
        mock._previewScale = previewScale
        self._mockBaseOffsetX, self._mockBaseOffsetY = startX, startY
        mock:ClearAllPoints()
        mock:SetPoint("TOPLEFT", self._stage, "TOPLEFT", startX + (tonumber(self._zoomPanX) or 0), startY + (tonumber(self._zoomPanY) or 0))
        mock:SetSize(mockW, mockH)
        self._additionalPreviewRoots = self._additionalPreviewRoots or {}
        Stage.RenderAdditionalSamples(st, additional, mock, previewScale)
        PixelLayoutRegion(mock, "SetBackdrop", Render.MockBackdrop(WHITE8X8))
        local bgAlpha = conf.hpBgAlpha or 0.85
        if runtimeSpec and runtimeSpec.backgroundAlpha ~= nil then bgAlpha = runtimeSpec.backgroundAlpha end
        mock:SetBackdropColor(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09,
            (runtimeHealth.backgroundFillMode == "missing"
                or (not runtimeSpec
                    and EnsureDB().general.barBgFillMode == "missing")) and 0 or bgAlpha)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        st.inset, st.liveW, st.mock, st.mockW, st.outlineEdge = inset, liveW, mock, mockW, outlineEdge
        st.powerDetached, st.powerEmbed, st.powerH, st.previewScale = powerDetached, powerEmbed, powerH, previewScale
end

-- The additional sample blocks' layout. A settings repaint recomputes it and refits the zoom when the scene's
-- contents change; the animation tick reuses the last one.
function Stage.SyncAdditionalLayout(st, liveW, liveH)
        local self, kind = st.self, st.kind
        local additional = self._additionalPreviewLayout
        if st.reason == "GROUP_PREVIEW_ANIMATE" then return additional end
        local layoutScratch = self._additionalPreviewLayoutScratch
        if not layoutScratch then
            layoutScratch = {}
            self._additionalPreviewLayoutScratch = layoutScratch
        end
        additional = Render.AdditionalPreviewLayout(st.gf, kind, st.conf, liveW, liveH, layoutScratch)
        self._additionalPreviewLayout = additional
        local topology = additional and ((additional.pets and 1 or 0) + (additional.targets and 2 or 0)
            + (additional.friendlyBoss and 4 or 0) + (additional.healerMana and 8 or 0)) or 0
        if topology ~= self._additionalPreviewTopology or kind ~= self._additionalPreviewKind then
            -- The initial main-only default lock is not a fit for a newly
            -- enabled scene: refit once when the contents change and give
            -- the default lock back when the scene is main-only again. A
            -- lock the user set keeps its zoom and position, as the lock
            -- tooltip promises; an unlocked (Fit) preview refits.
            if topology > 0 or (self._additionalPreviewTopology or 0) > 0 then
                local userLock = self._manualZoom ~= nil and self._msuf2ZoomLockIsDefault ~= true
                if not userLock then
                    local defaultLock = self._msuf2ZoomLockDefaultPending == true
                        or self._msuf2ZoomLockIsDefault == true
                        or self._msuf2ZoomLockDefaultDropped == true
                    self._manualZoom, self._dragFrozenScale = nil, nil
                    self._zoomPanX, self._zoomPanY = nil, nil
                    self._msuf2ZoomLockIsDefault = nil
                    self._msuf2ZoomLockDefaultPending = defaultLock and topology == 0 or nil
                    self._msuf2ZoomLockDefaultDropped = defaultLock and topology > 0 or nil
                end
            end
            self._additionalPreviewTopology, self._additionalPreviewKind = topology, kind
        end
        return additional
end

-- Pets, targets, bosses and healer-mana samples around the mock, and the buff coverage samples on it.
function Stage.RenderAdditionalSamples(st, additional, mock, previewScale)
        if st.reason == "GROUP_PREVIEW_ANIMATE" then return end
        local self, gf, kind, conf = st.self, st.gf, st.kind, st.conf
        local prefixes = Render.ADDITIONAL_PREVIEW_PREFIXES
        for i = 1, #prefixes do
            local prefix = prefixes[i]
            local item = additional and additional[prefix]
            local root = self._additionalPreviewRoots[prefix]
            if item and gf.RenderAdditionalPreview then
                if not root then
                    root = PixelLayoutRegion(CreateFrame("Frame", nil, self._stage))
                    root:EnableMouse(false)
                    self._additionalPreviewRoots[prefix] = root
                end
                root:ClearAllPoints()
                root:SetPoint("CENTER", mock, "CENTER", item.x * previewScale, item.y * previewScale)
                root:SetSize(item.spec.totalWidth * previewScale, item.spec.totalHeight * previewScale)
                local holder = gf.RenderAdditionalPreview(root, kind, prefix, kind == "party" and 5 or 10, MENU_EXTRA_OPTIONS)
                if holder then
                    holder:SetScale(previewScale)
                    holder:ClearAllPoints()
                    holder:SetPoint("CENTER", root, "CENTER", 0, 0)
                    root:Show()
                else
                    root:Hide()
                end
            elseif root then
                if gf and gf.HideAdditionalPreview then gf.HideAdditionalPreview(root, prefix) end
                root:Hide()
            end
        end
        if gf and gf.RenderBuffCoveragePreview then
            if conf.enabled == false then gf.HideBuffCoveragePreview(mock)
            else gf.RenderBuffCoveragePreview(mock, conf, previewScale) end
        end
end

--- Power bar handle: placement for the embedded, attached-below and detached bar. The engine draws the bar
--- itself (Stage.RenderCell); the handle rides over it.
function Stage.PlacePowerHandle(st, env)
        local powerBarHandle = env.powerBarHandle
        if not powerBarHandle then return end
        local scene, conf, runtimePower, mock = st.scene, st.conf, st.runtimePower, st.mock
        local inset, powerH, previewScale, powerDetached = st.inset, st.powerH, st.previewScale, st.powerDetached
        local Round, ScaleValue = env.Round, env.ScaleValue
        -- LayoutDetached geometry (compiler resolves width to the frame width
        -- when unset; the conf fallback mirrors that for the no-spec path).
        local detachedPowerW = tonumber(runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or 0
        if detachedPowerW <= 0 then detachedPowerW = st.liveW end
        local detachedPowerH = tonumber(runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6
        local detachedPowerX = tonumber(runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
        local detachedPowerY = tonumber(runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
        -- Runtime parity for interaction too: only the detached bar owns
        -- free offsets, so the handle locks itself while the bar is
        -- embedded/attached (single-click settings still work there).
        powerBarHandle._locked = not powerDetached
        if powerBarHandle._dragging ~= true then
            powerBarHandle._previewScale = previewScale
            powerBarHandle._previewWriteScale = previewScale
            powerBarHandle:ClearAllPoints()
            if powerDetached then
                powerBarHandle:SetPoint("TOP", mock, "BOTTOM",
                    Round(detachedPowerX * previewScale), Round(detachedPowerY * previewScale))
                powerBarHandle:SetSize(ScaleValue(detachedPowerW, previewScale, 1),
                    ScaleValue(detachedPowerH, previewScale, 1))
            elseif not st.powerEmbed then
                powerBarHandle:SetPoint("TOP", mock, "BOTTOM", 0, -max(1, Round(previewScale)))
                powerBarHandle:SetSize(max(1, st.mockW - inset * 2), max(12, powerH))
            else
                powerBarHandle:SetPoint("BOTTOM", mock, "BOTTOM", 0, inset)
                powerBarHandle:SetSize(max(1, st.mockW - inset * 2), max(12, powerH))
            end
        end
        powerBarHandle:SetShown(powerH > 0 and SceneLayerOn(scene, "power"))
        powerBarHandle:SetAlpha(SceneLayerAlpha(scene, "power"))
        local powerFrameLevel = powerDetached
            and PreviewElementLevel(mock, Layers,
                runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, 6, 0)
            or ((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + 1
        SetPreviewFrameLevel(powerBarHandle, powerFrameLevel)
end

--- The engine paints the frame body: bars, texts, prediction, frame and block border, rounded art. An isolated
--- preview scene (GF.NewPreviewScene) hangs on the mock, zoomed by the preview scale, in the mock's level band; this
--- stage hands it the page's inputs and aliases its regions onto the mock for the handles, the focus ring and the
--- colour painter. No unit is read: the cell shows a fixed sample.
local CELL_ALIASES = {
    { "_health", "hpBar", "Health", "health" }, { "_power", "targetPowerBar", "powerBar", "Power", "power" },
    { "_healPred", "incomingHealBar" }, { "_absorb", "absorbBar" }, { "_healAbsorb", "healAbsorbBar" },
    { "_tempMaxHealth", "tempMaxHealthBar" }, { "_healthBg", "hpBarBG", "healthBg" },
    { "_nameFS", "nameText" }, { "_hpLeftFS", "hpTextLeft" }, { "_hpCenterFS", "hpTextCenter" },
    { "_hpRightFS", "hpTextRight" }, { "_hpFS", "hpTextRight" },
    { "_powerLeftFS", "powerTextLeft" }, { "_powerCenterFS", "powerTextCenter" },
    { "_powerRightFS", "powerTextRight" }, { "_powerFS", "powerTextCenter" },
}
local function AliasCell(mock, frame)
    for i = 1, #CELL_ALIASES do
        local item = CELL_ALIASES[i]
        local region
        for j = 2, #item do
            region = frame and frame[item[j]]
            if region then break end
        end
        -- A text slot the settings leave unused has no engine region: a hidden stand-in keeps the handle and focus
        -- region lists dense (a hidden region is skipped).
        if not region and item[1]:sub(-2) == "FS" then
            local standIn = mock._cellStandInFS
            if not standIn then
                standIn = PixelLayoutRegion(mock:CreateFontString(nil, "OVERLAY"))
                standIn:Hide()
                mock._cellStandInFS = standIn
            end
            region = standIn
        end
        mock[item[1]] = region
    end
    mock._cell = frame
end

local CELL_SAMPLE = { hpMax = 1000000, powerMax = 100, absorb = 125000, healAbsorbPct = 0.07, tempMaxPct = 0.20,
    powerColor = { 0.13, 0.27, 0.67 } }
function Stage.RenderCell(st, env)
        local mock, scene, self, kind = st.mock, st.scene, st.self, st.kind
        local root = self._scene
        if not root then
            root = scene.gf.NewPreviewScene(mock)
            self._scene = root
        end
        root:Activate()
        local cell = root:Group(kind)
        for other, group in pairs(root.groups) do
            if other ~= kind and group:IsActive() then group:Hide() end
        end
        local names, classes = env.GF_PREVIEW_NAMES, env.GF_PREVIEW_CLASSES
        local sample = self._msufGFCellSample
        if not sample then
            sample = {}
            for key, value in pairs(CELL_SAMPLE) do sample[key] = value end
            sample.powerColor = { CELL_SAMPLE.powerColor[1], CELL_SAMPLE.powerColor[2], CELL_SAMPLE.powerColor[3] }
            self._msufGFCellSample = sample
        end
        -- The live player when it can be read, the stylized sample for any missing field. The exact maxima and the
        -- absorb amount scale the value texts; while the animation runs the animated fraction drives the current
        -- value on that live maximum.
        local live = scene.liveData
        sample.name = live and live.name or names[5]
        sample.class = live and live.class or classes[((kind == "party" and 5 or 2) % #classes) + 1]
        sample.hpMax = live and live.hpMax or CELL_SAMPLE.hpMax
        sample.powerMax = live and live.powerMax or CELL_SAMPLE.powerMax
        sample.absorb = live and live.absorb or CELL_SAMPLE.absorb
        sample.hpPct, sample.powerPct = scene.hpPct, scene.powerPct
        sample.healPct, sample.absorbPct = scene.healPct, scene.absorbPct
        scene.sampleClass = sample.class
        cell:Configure({
            scale = st.previewScale, level = mock._msufPreviewElementLevelBias, role = scene.previewRole,
            sample = sample, bodyOnly = false, layerVisible = scene.layerVisible, layerSolo = false,
            ignoreOocFade = true, fit = true,
        })
        root:SetClock(self._animationEnabled == true and self._animationElapsed or nil, true)
        cell:Show(1, { immediate = true, reason = st.reason })
        local frames = cell:Frames()
        local frame = frames and frames[1]
        if frame then
            scene.engineConfig = M.PreviewHelpers.PrepareGroupSceneSamples(frame, cell, scene)
            cell:RefreshData()
            -- Capture the live Power painter's configured colour once per settings refresh.
            -- The scene then reuses it on animation ticks without another query or call.
            local power = MSUF.UF.elements.Power
            if frame.targetPowerBar then
                power.PaintSample(frame, "player", floor(scene.powerPct * sample.powerMax + 0.5), sample.powerMax,
                    live and live.powerType or 0, live and live.powerToken or "MANA")
                local r, g, b, a = frame.targetPowerBar:GetStatusBarColor()
                if not issecretvalue(r) and not issecretvalue(g) and not issecretvalue(b) and not issecretvalue(a) then
                    local color = sample.powerColor
                    color[1], color[2], color[3], color[4] = r, g, b, a
                end
            end
            local lanes = scene.engineConfig and scene.engineConfig.lanes or {}
            for i = 1, #AURA_LANES do
                local lane = AURA_LANES[i]
                if lanes[lane[1]] then scene[lane[3]] = lanes[lane[1]] end
            end
        end
        scene.engineAlpha = frame and frame:GetAlpha() or 1
        AliasCell(mock, frame)
end

--- Dispel overlay, portrait and dispel symbol: widgets of the preview's own (the portrait and the symbol row are
--- handles). The frame border, rounded surface and text layers belong to the engine scene.
function Stage.RenderChrome(st)
    local scene, frame = st.scene, st.mock._cell
    if not frame then return end
    scene.previewScale = st.previewScale
    -- SceneApply uses the exact runtime portrait layout before handles adopt it.
    MSUF.UF.elements.Portrait.SceneApply(frame, frame.MSUFSpec)
    PaintGroupPreviewPortrait(scene)
    M.PreviewHelpers.PaintGroupSceneDispel(frame, scene.engineConfig)
    local overlay, symbol = frame._msufSceneDispelOverlay, frame._msufSceneDispelSymbol
    if overlay then
        overlay:SetShown(scene.layerAvailable.dispelOverlay and scene.layerVisible.dispelOverlay ~= false)
        overlay:SetAlpha(scene.soloLayer and scene.soloLayer ~= "dispelOverlay" and 0.15 or 1)
    end
    if symbol then symbol:SetShown(scene.layerAvailable.dispelSymbol and scene.layerVisible.dispelSymbol ~= false) end
    local cfg = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    M.PreviewHelpers.BindGroupSceneHandle(scene.S.dispelSymbolHandle, scene.mock, symbol,
        scene.previewScale, cfg and cfg.anchor, tonumber(cfg and cfg.x) or 0, tonumber(cfg and cfg.y) or 0)
    if scene.S.dispelSymbolHandle then
        scene.S.dispelSymbolHandle:SetAlpha(SceneLayerAlpha(scene, "dispelSymbol") * (scene.engineAlpha or 1))
    end
    scene.mock._msufGFPreviewDispelOverlayHost = overlay
    scene.mock._msufGFPreviewDispelOverlayRegion = overlay and overlay.Region
end

--- The aura lanes set their texts' fonts through the preview font: path, flags and shadow of the group's font.
local function BuildPreviewFontSetter(st)
        local resolveSafe = MSUF.Require("MSUF_ResolveSafeFontPath", FILE)
        local SetFontChecked = MSUF.Require("MSUF_SetFontChecked", FILE)
        return function(fs, size)
            if not fs then return end
            local path, fontFlags = st.previewFontPath, st.previewFontFlags
            local g = EnsureDB().general
            path = resolveSafe(path, size, fontFlags, g and g.fontKey)
            if not SetFontChecked(fs, path, size, fontFlags) then
                SetFontChecked(fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, fontFlags)
            end
            if fs.SetShadowOffset then
                if st.previewFontShadow then
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, st.previewFontShadowAlpha or 1) end
                    fs:SetShadowOffset(st.previewFontShadowX or 1, st.previewFontShadowY or -1)
                else
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
end

--- Font resolution for the widgets the preview draws itself (the aura lanes' timers and stacks).
function Stage.ResolveFont(st, env)
        local gf, kind, runtimeSpec = st.gf, st.kind, st.runtimeSpec
        local fontPath = (runtimeSpec and runtimeSpec.font) or (gf and gf.ResolveFontPath and gf.ResolveFontPath(kind))
            or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local fontFlags = (runtimeSpec and runtimeSpec.fontFlags) or (gf and gf.ResolveFontFlags and gf.ResolveFontFlags(kind)) or "OUTLINE"
        local fontShadow = true
        local fontShadowAlpha = tonumber(runtimeSpec and runtimeSpec.fontShadowAlpha) or 1
        local fontShadowX = tonumber(runtimeSpec and runtimeSpec.fontShadowX) or 1
        local fontShadowY = tonumber(runtimeSpec and runtimeSpec.fontShadowY) or -1
        if runtimeSpec then
            fontShadow = runtimeSpec.fontShadow == true
        elseif gf and gf.ResolveFontShadow then
            fontShadow, fontShadowAlpha, fontShadowX, fontShadowY = gf.ResolveFontShadow(kind)
        end
        st.previewFontPath, st.previewFontFlags, st.previewFontShadow = fontPath, fontFlags, fontShadow
        st.previewFontShadowAlpha, st.previewFontShadowX, st.previewFontShadowY = fontShadowAlpha, fontShadowX, fontShadowY
        -- One setter per preview box; it reads this refresh's font from the stage state.
        local setter = env._msufGFFontSetter
        if not setter or setter.st ~= st then
            setter = { st = st, fn = BuildPreviewFontSetter(st) }
            env._msufGFFontSetter = setter
        end
        st.SetPreviewFont = setter.fn
end

--- Group block border, bounds guide and the aura lanes (RenderAuras), whose
--- layout helpers later stages reuse.
function Stage.RenderBoundsAndAuras(st, env)
        local scene, mock, self = st.scene, st.mock, st.self
        env.ApplyBoundsGuide(self, max(1, st.outlineEdge))
        if self._bounds.SetFrameLevel and mock.GetFrameLevel then
            SetPreviewFrameLevel(self._bounds, Layers.ElementLevel and (PreviewElementLevel(mock, Layers, 30, 30, 31) + 16)
                or ((mock:GetFrameLevel() or 1) + (Layers.PREVIEW_BOUNDS_OFFSET or 48)))
        end
        self._bounds:SetShown(SceneLayerOn(scene, "bounds"))
        scene.previewScale = st.previewScale
        scene.SetPreviewFont = st.SetPreviewFont
        RenderAuras(scene)
        st.LayoutHandle = scene.LayoutHandle
end

-- Status icon value -> the shared fallback texture table entry and variant.
local STATUS_ICON_TEXTURES = {
    raidMarker = { "raidMarker", 1 }, readyCheckIcon = { "readyCheck", "ready" }, summonIcon = { "summon", 1 },
    resurrectIcon = { "incomingRes", "resurrect" }, pvpIcon = { "pvp", "Alliance" }, phaseIcon = { "phase", "phase" },
}
-- The texture and coords one status icon shows: a custom icon, the group's own role/leader/assist art, or the
-- shared Blizzard texture.
function Stage.StatusIconTexture(scene, spec, runtimeCfg)
    local conf, gf, kind, value = scene.conf, scene.gf, scene.kind, spec.value
    local style = runtimeCfg and runtimeCfg.style
    if runtimeCfg and type(runtimeCfg.customIcon) == "string" and runtimeCfg.customIcon ~= "" then
        return runtimeCfg.customIcon, 0, 1, 0, 1
    elseif spec.customIcon and type(conf[spec.customIcon]) == "string" and conf[spec.customIcon] ~= "" then
        return conf[spec.customIcon], 0, 1, 0, 1
    elseif value == "roleIcon" and gf and gf.GetRoleTexture then
        return gf.GetRoleTexture(kind, scene.previewRole, style)
    elseif value == "leaderIcon" and gf and gf.GetLeaderTexture then
        return gf.GetLeaderTexture(kind, style)
    elseif value == "assistIcon" and gf and gf.GetAssistTexture then
        return gf.GetAssistTexture(kind, style)
    end
    local texture = STATUS_ICON_TEXTURES[value]
    if texture then return ResolveStatusPreviewTexture(scene, spec, runtimeCfg, texture[1], texture[2]) end
end

local ENGINE_STATUS_FIELDS = {
    roleIcon = "roleIcon", leaderIcon = "leaderIcon", assistIcon = "assistIcon", raidMarker = "raidTargetIcon",
    readyCheckIcon = "readyCheckIcon", summonIcon = "summonIcon", resurrectIcon = "incomingResIndicatorIcon",
    pvpIcon = "pvpIndicatorIcon", phaseIcon = "phaseIcon", showGroupNumber = "raidGroupNameText", levelText = "levelText",
    statusText = "_msufScene_statusText", statusGhostText = "_msufScene_statusGhostText",
    statusAFKText = "_msufScene_statusAFKText", statusDNDText = "_msufScene_statusDNDText",
    statusAFKTimer = "statusAFKTimerText", threatText = "threatIndicatorText",
}
function Stage.ConfigureStatusHandle(st, env, handle)
    local spec, frame = handle._statusSpec, st.mock._cell
    local cfg = env.RuntimeStatusConfig(st.scene.runtimeStatus, spec)
    local region = frame and frame[ENGINE_STATUS_FIELDS[spec.value] or spec.value]
    local shown = cfg and cfg.enabled == true and env.StatusSpecInMode(spec, st.scene.statusSpec)
        and SceneLayerOn(st.scene, "status")
    handle._previewText = spec.text or "Status"
    if handle._label then handle._label:SetText(env.StatusLabel(spec)) end
    if region then
        if env.StatusSpecIsText(spec) then
            region:SetText(env.StatusText(spec, cfg, st.conf))
        else
            local texture, l, r, t, b = Stage.StatusIconTexture(st.scene, spec, cfg)
            if texture then
                region:SetTexture(texture)
                region:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
            end
        end
        region:SetShown(shown)
        if region.SetAlpha then region:SetAlpha((region._msufStatusAlpha or 1) * (frame._msufAlphaLastFG or 1)) end
    end
    M.PreviewHelpers.BindGroupSceneHandle(handle, st.mock, region, st.previewScale, cfg and cfg.anchor)
end
function Stage.ConfigureStatusHandles(st, env)
    local frame = st.mock._cell
    if not frame then return end
    local elements, runtime = MSUF.UF.elements, MSUF.UFStatusRuntime
    elements.StatusIndicators.SceneApply(frame, frame.MSUFSpec)
    local sample = st.self._msufGFCellSample
    sample.player, sample.leader, sample.assist, sample.statusSelection = true, true, true, "all"
    sample.raidTarget, sample.raidGroup, sample.incomingRes, sample.pvp, sample.level = 1, 3, true, "Alliance", 80
    runtime.PaintSampleIdentityTexts(frame, frame.MSUFSpec.status, sample)
    runtime.PaintSampleIndicators(frame, frame.MSUFSpec.status, sample)
    runtime.PaintSceneStatus(frame, frame.MSUFSpec.status, "all", sample)
    for i = 1, #env.statusHandles do Stage.ConfigureStatusHandle(st, env, env.statusHandles[i]) end
end

--- Spell indicator handle painters: icon glow effect and the per-visual
--- (icon, bar, square, number) handle configuration.
-- Read-only fallbacks for a handle without its own color or appearance.
local WHITE_RGBA = { 1, 1, 1, 1 }
local EMPTY_APPEARANCE = {}
-- The selected spell's placement before the editor stored one.
local SELECTED_SPELL_PLACED_DEFAULT = { type = "icon", size = 20, anchor = "TOPLEFT", x = 0, y = 0 }
-- The spell handle's region lists, in the order of SpellPreviewRegions.
local SPELL_REGION_LISTS = { "_icons", "_iconSwipes", "_iconStacks", "_iconTimers", "_iconDurationBars" }
local function SpellPreviewRegions(handle)
    local swipes, stacks, timers, bars = handle._iconSwipes, handle._iconStacks, handle._iconTimers, handle._iconDurationBars
    return handle._icons[1], swipes and swipes[1], stacks and stacks[1], timers and timers[1], bars and bars[1]
end
-- Hides the first region of the handle's lists `first` to `last` of SPELL_REGION_LISTS.
local function HideSpellRegions(handle, first, last)
    for i = first, last do
        local list = handle[SPELL_REGION_LISTS[i]]
        local region = list and list[1]
        if region then region:Hide() end
    end
end
-- Solid fill of a spell indicator bar, square or duration bar region.
local function FillSpellRegion(region, white, r, g, b, a)
    region:SetTexture(white)
    region:SetTexCoord(0, 1, 0, 1)
    region:SetVertexColor(r, g, b, a)
    region:ClearAllPoints()
end
-- Font, colour and anchor of one spell indicator text.
local function PlaceSpellText(st, fs, size, owner, anchor, x, y)
    st.SetPreviewFont(fs, size)
    fs:SetTextColor(1, 1, 1, 1)
    PlaceAuraPreviewText(fs, owner, anchor, x, y)
end
-- Appearance flag, else the placement's own flag (on unless it is explicitly false).
local function SpellShowFlag(appearance, placed, key)
    local value = appearance[key]
    if value == nil then value = placed[key] ~= false end
    return value
end

local function HideSpellIconEffectPreview(handle)
    local root = handle and handle._msufSpellPreviewIconEffectRoot
    if not root then return end
    HidePreviewGlow(root)
    root:Hide()
end
local function ApplySpellIconEffectPreview(st, handle, placed, spellSize)
    local visual = placed and (placed.visual or placed.type)
    if not (handle and placed and visual == "icon" and placed.iconEffect == "glow") then
        HideSpellIconEffectPreview(handle)
        return
    end
    local root = handle._msufSpellPreviewIconEffectRoot
    if not root then
        root = PixelLayoutRegion(CreateFrame("Frame", nil, handle))
        root:EnableMouse(false)
        handle._msufSpellPreviewIconEffectRoot = root
    end
    root:ClearAllPoints()
    root:SetAllPoints(handle)
    local color = handle._msufSpellIndicatorColor or WHITE_RGBA
    ShowPreviewGlow(st.env, root, root, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1,
        max(2, spellSize * 0.15))
    root:Show()
end

-- A bar indicator: tinted track, one representative native-fill duration bar and the optional timer.
function Stage.PaintSpellBar(st, handle, placed, appearance, placedScale, spellBaseSize, spellSize)
    local env, previewScale = st.env, st.previewScale
    local ScaleValue, ConfigToOffset = env.ScaleValue, env.ConfigToOffset
    local color = handle._msufSpellIndicatorColor
    local r, g, b, a = color[1], color[2], color[3], color[4]
    local exactSlot = placed.spellIndicatorSlot == true
    local spellTex, _, _, spellTimer, spellDurationBar = SpellPreviewRegions(handle)
    local barWidth = tonumber(exactSlot and placed.width or placed.barWidth)
    if barWidth then barWidth = barWidth * placedScale end
    local barW = max(spellSize * 2, ScaleValue(barWidth or (spellBaseSize * 3), previewScale, 16))
    handle:SetSize(barW, spellSize)
    if spellTex then
        FillSpellRegion(spellTex, env.WHITE8X8, r * 0.18, g * 0.18, b * 0.18, a * 0.55)
        spellTex:SetAllPoints(handle)
        spellTex:Show()
    end
    if spellDurationBar then
        -- Menu previews have no live AuraDurationObject. Show one
        -- representative native-fill state without adding preview
        -- animation or recurring work.
        FillSpellRegion(spellDurationBar, env.WHITE8X8, r, g, b, a)
        local reverseFill = exactSlot and placed.durationBarReverseFill == true
            or (not exactSlot and tostring(placed.growth or "RIGHTDOWN"):upper():sub(1, 4) == "LEFT")
        local edge = reverseFill and "RIGHT" or "LEFT"
        spellDurationBar:SetPoint("TOP" .. edge, handle, "TOP" .. edge, 0, 0)
        spellDurationBar:SetPoint("BOTTOM" .. edge, handle, "BOTTOM" .. edge, 0, 0)
        spellDurationBar:SetWidth(max(1, barW * 0.68))
        spellDurationBar:Show()
    end
    local showTimer = exactSlot and placed.showCooldownText == true
        or (not exactSlot and placed.barShowTimer == true)
    if spellTimer and showTimer then
        PlaceSpellText(st, spellTimer, max(6, ScaleValue(appearance.cooldownSize or placed.cooldownSize or 8, previewScale, 6)), handle,
            RuntimeAuraTextAnchor(exactSlot and placed.cooldownAnchor or placed.barTimerAnchor, "CENTER"),
            ConfigToOffset(exactSlot and placed.cooldownX or placed.barTimerX or 0, previewScale),
            ConfigToOffset(exactSlot and placed.cooldownY or placed.barTimerY or 0, previewScale))
        spellTimer:SetText("12")
        spellTimer:Show()
    end
end

-- An icon indicator: spell texture, timer, swipe, duration bar, stack count and the Auras3 icon look.
function Stage.PaintSpellIcon(st, handle, item, placed, appearance, fallbackTexture, spellSize)
    local env, scene, previewScale = st.env, st.scene, st.previewScale
    local ScaleValue, ConfigToOffset = env.ScaleValue, env.ConfigToOffset
    local exactSlot = placed.spellIndicatorSlot == true
    local spellTex, spellSwipe, spellStack, spellTimer, spellDurationBar = SpellPreviewRegions(handle)
    handle:SetSize(spellSize, spellSize)
    if spellTex then
        spellTex:SetTexture((item and item.icon) or fallbackTexture or env.CurrentSpellTexture(st.kind))
        ApplyPreviewIconZoom(spellTex, exactSlot and placed.iconZoom or scene.spellIconZoom, 0)
        spellTex:SetVertexColor(1, 1, 1, 1)
        spellTex:ClearAllPoints()
        spellTex:SetAllPoints(handle)
        spellTex:Show()
    end
    local showCooldown = appearance.showCooldownText
    if showCooldown == nil then showCooldown = SpellShowFlag(appearance, placed, "showCooldown") end
    local showSwipe = SpellShowFlag(appearance, placed, "showCooldownSwipe")
    local showStacks = SpellShowFlag(appearance, placed, "showStacks")
    local barOnly = appearance.showDurationBar == true and (appearance.durationBarDisplay or "BAR_ONLY") == "BAR_ONLY"
    if spellTex and spellTex.SetAlpha then spellTex:SetAlpha(barOnly and 0 or 1) end
    local owner = spellTex or handle
    if spellTimer then
        PlaceSpellText(st, spellTimer, max(6, ScaleValue(appearance.cooldownSize or placed.cooldownSize or 8, previewScale, 6)), owner,
            RuntimeAuraTextAnchor(appearance.cooldownAnchor, "CENTER"),
            ConfigToOffset(appearance.cooldownX or 0, previewScale), ConfigToOffset(appearance.cooldownY or 0, previewScale))
        spellTimer:SetText(showCooldown and "12" or "")
        spellTimer:SetShown(showCooldown)
    end
    if spellSwipe and showSwipe and not barOnly then
        GroupAuraPreviewSwipe(spellSwipe, owner, spellSize, 0.48, appearance.cooldownSwipeReverse == true)
        spellSwipe:SetVertexColor(0, 0, 0, 0.58)
        spellSwipe:Show()
    end
    GroupAuraDurationBar(spellDurationBar, owner, appearance, spellSize, nil)
    if spellStack and showStacks then
        PlaceSpellText(st, spellStack, max(6, ScaleValue(appearance.stackSize or 10, previewScale, 6)), owner,
            RuntimeAuraTextAnchor(appearance.stackAnchor, "BOTTOMRIGHT"),
            ConfigToOffset(appearance.stackX or 0, previewScale), ConfigToOffset(appearance.stackY or 0, previewScale))
        spellStack:SetText("2")
        spellStack:Show()
    end
    local a3 = env.MSUF.MSUF_Auras3
    local previewShape = appearance.iconShape or "RECTANGLE"
    if a3 and a3.ResolveAuraIconShape then
        previewShape = a3.ResolveAuraIconShape(previewShape, st.conf.portraitShape or (st.conf.portrait and st.conf.portrait.shape))
    end
    ApplyPreviewIconLook(a3, handle, previewShape, appearance.iconStyle, barOnly, spellSize, spellTex, spellSwipe)
end

local function ConfigureSpellPreviewHandle(st, handle, item, placed, appearance, fallbackTexture, fallbackColor)
    if not (handle and placed) then return false end
    local env = st.env
    local ScaleValue = env.ScaleValue
    appearance = appearance or EMPTY_APPEARANCE
    local exactSlot = placed.spellIndicatorSlot == true
    local spellType = exactSlot and (placed.visual or "none") or (placed.type or "icon")
    local placedScale = (exactSlot or placed._msufIconScaleApplied == true) and 1 or st.scene.spellIconScale
    local spellBaseSize = (tonumber(placed.size) or 20) * placedScale
    local spellSize = max(1, ScaleValue(spellBaseSize, st.previewScale, 1))
    if handle.SetAlpha then handle:SetAlpha(tonumber(appearance.alpha) or 1) end
    local color = item and item.color or fallbackColor
    local spellR, spellG, spellB = (color and color[1]) or 0.69, (color and color[2]) or 0.50, (color and color[3]) or 0.88
    if handle.SetBackdropColor then handle:SetBackdropColor(spellR * 0.12, spellG * 0.12, spellB * 0.12, 0.42) end
    if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(spellR, spellG, spellB, 0.95) end
    handle._icons = handle._icons or {}
    local spellTex, spellSwipe, spellStack = SpellPreviewRegions(handle)
    local handleColor = handle._msufSpellIndicatorColor
    if not handleColor then
        handleColor = {}
        handle._msufSpellIndicatorColor = handleColor
    end
    handleColor[1], handleColor[2], handleColor[3], handleColor[4] = spellR, spellG, spellB, (color and color[4]) or 1
    handle._color = handleColor
    if handle._label and handle._label.SetText then
        handle._label:SetText(item and (item.display or item.auraName) or "SPELL")
        handle._label:Show()
    end
    HideSpellRegions(handle, 2, 5)
    if spellType == "bar" then
        Stage.PaintSpellBar(st, handle, placed, appearance, placedScale, spellBaseSize, spellSize)
    elseif spellType == "square" then
        handle:SetSize(spellSize, spellSize)
        if spellTex then
            FillSpellRegion(spellTex, env.WHITE8X8, spellR, spellG, spellB, 1)
            spellTex:SetAllPoints(handle)
            spellTex:Show()
        end
    elseif spellType == "number" then
        handle:SetSize(max(18, spellSize), max(18, spellSize))
        if spellTex then spellTex:Hide() end
        if spellStack then
            st.SetPreviewFont(spellStack, max(8, spellSize * 0.72))
            spellStack:SetTextColor(spellR, spellG, spellB, 1)
            spellStack:ClearAllPoints()
            spellStack:SetPoint("CENTER", handle, "CENTER", 0, 0)
            local showStacks = SpellShowFlag(appearance, placed, "showStacks")
            spellStack:SetText(showStacks and "9" or "")
            spellStack:SetShown(showStacks)
        end
    else
        Stage.PaintSpellIcon(st, handle, item, placed, appearance, fallbackTexture, spellSize)
    end
    if spellType ~= "icon" then
        local a3 = env.MSUF.MSUF_Auras3
        if a3 then
            if a3.ApplyAuraIconShape then a3.ApplyAuraIconShape(handle, "RECTANGLE", nil, spellTex, spellSwipe) end
            if a3.ApplyIconStylePreview then a3.ApplyIconStylePreview(handle, nil) end
        end
    end
    handle._msufSpellIndicatorLayer = item and item.layer or nil
    handle._msufSpellIndicatorStrata = item and item.strata or nil
    st.LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")
    ApplySpellIconEffectPreview(st, handle, placed, spellSize)
    return true
end

-- The selected spell's fallback handle (no runtime slot drew it): the stored placement, or the default one.
function Stage.ConfigureSelectedSpellHandle(st, spellHandle)
    local env, scene, conf = st.env, st.scene, st.conf
    local selectedSpellIcon = env.CurrentSpellTexture(st.kind)
    local spellR, spellG, spellB = env.CurrentSpellColor(st.kind)
    local selectedFallbackItem = spellHandle._msufGFSelectedFallbackItem
    if not selectedFallbackItem then
        selectedFallbackItem = {}
        spellHandle._msufGFSelectedFallbackItem = selectedFallbackItem
    end
    selectedFallbackItem.specKey = scene.selectedSpellSpecKey
    selectedFallbackItem.auraName = scene.selectedSpellAuraName
    selectedFallbackItem.display = scene.selectedSpellAuraName or "Spell"
    local selectedAppearance = scene.selectedSpellCfg.cornerSlotKey == nil
        and type(conf.spellIndicators) == "table" and conf.spellIndicators.style or nil
    local buffCfg = scene.buffCfg
    if selectedAppearance and buffCfg and buffCfg.iconStyle and selectedAppearance.iconStyle == nil then
        local fallbackAppearance = spellHandle._msufGFSelectedFallbackAppearance
        if not fallbackAppearance then
            fallbackAppearance = {}
            spellHandle._msufGFSelectedFallbackAppearance = fallbackAppearance
        end
        wipe(fallbackAppearance)
        for key, value in pairs(selectedAppearance) do fallbackAppearance[key] = value end
        fallbackAppearance.iconStyle = buffCfg.iconStyle
        selectedAppearance = fallbackAppearance
    end
    local selectedFallbackColor = spellHandle._msufGFSelectedFallbackColor
    if not selectedFallbackColor then
        selectedFallbackColor = {}
        spellHandle._msufGFSelectedFallbackColor = selectedFallbackColor
    end
    selectedFallbackColor[1], selectedFallbackColor[2] = spellR, spellG
    selectedFallbackColor[3], selectedFallbackColor[4] = spellB, 1
    ConfigureSpellPreviewHandle(st, spellHandle, selectedFallbackItem,
        scene.selectedPlaced or SELECTED_SPELL_PLACED_DEFAULT,
        selectedAppearance, selectedSpellIcon, selectedFallbackColor)
end

-- One runtime spell item: its handle (placed visual and/or frame effect). Returns true when the
-- selected spell's own handle drew it.
function Stage.RenderLegacySpellItem(st, box, item, index, dynamicSpellHandlesActive)
    local env, scene = st.env, st.scene
    local exactSlot = item and item.spellIndicatorSlot == true
    local placed = exactSlot and item or (item and item.placed)
    local selectedItem = item and item.specKey == scene.selectedSpellSpecKey
        and item.auraName == scene.selectedSpellAuraName
    local effect = (exactSlot and item.frameEffect) or item.frame
        or (selectedItem and scene.selectedSpellEffect) or nil
    local handle = box:EnsureSpellIndicatorHandle(item, index)
    if handle and not handle._icons then env.AddIconPool(handle, 1) end
    local placedType = placed and (exactSlot and placed.visual or placed.type) or "none"
    local placedShown = placed and placedType ~= "none" and item.hiddenVisual ~= true
    local selectedDrawn = false
    if handle and placedShown and ConfigureSpellPreviewHandle(st, handle, item, placed, item) then
        selectedDrawn = selectedItem
    elseif handle and effect then
        handle:SetSize(1, 1)
        if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(0, 0, 0, 0) end
        if handle._label then handle._label:Hide() end
        HideSpellRegions(handle, 1, 4)
        handle._msufSpellIndicatorLayer = item.layer
        handle._msufSpellIndicatorStrata = item.strata
        st.LayoutHandle(handle, "CENTER", 0, 0, "CENTER")
        HideSpellIconEffectPreview(handle)
    end
    if handle and (placedShown or effect) then
        dynamicSpellHandlesActive[handle._msufSpellIndicatorPreviewKey] = handle
        -- The selected spell's full-frame effect keeps its stable
        -- mock-owned preview root. Every other previewed spell owns
        -- its own root, so Preview all spells composites the frame
        -- effects by priority exactly like the live frame does.
        if effect and not selectedItem then
            ApplySpellEffectPreview(env, handle, effect)
        else
            HideSpellEffectPreview(env, handle)
        end
    end
    return selectedDrawn
end

function Stage.RenderLegacySpellIndicators(st, env)
        local scene, box, spellHandle = st.scene, env.box, env.spellHandle
        local runtimeSpellIndicators, runtimeSpellItems = scene.runtimeSpellIndicators, scene.previewSpellItems
        local selectedSpellEffectOwner, selectedSpellEffect = env.selectedSpellEffectOwner, scene.selectedSpellEffect
        -- Built per box and reused: the handles painted this refresh, by indicator key.
        local dynamicSpellHandlesActive = box._msufGFSpellHandlesActiveScratch or {}
        box._msufGFSpellHandlesActiveScratch = dynamicSpellHandlesActive
        wipe(dynamicSpellHandlesActive)
        st.dynamicSpellHandlesActive = dynamicSpellHandlesActive
        local selectedRuntimeSpellHandleUsed = false
        if runtimeSpellIndicators and runtimeSpellIndicators.enabled == true and type(runtimeSpellItems) == "table" and box.EnsureSpellIndicatorHandle then
            for i = 1, #runtimeSpellItems do
                if Stage.RenderLegacySpellItem(st, box, runtimeSpellItems[i], i, dynamicSpellHandlesActive) then
                    selectedRuntimeSpellHandleUsed = true
                end
            end
        end
        for key, handle in pairs(box._spellIndicatorHandles or EMPTY_APPEARANCE) do
            if not dynamicSpellHandlesActive[key] then
                HideSpellEffectPreview(env, handle)
                HideSpellIconEffectPreview(handle)
            end
        end
        if box.HideUnusedSpellIndicatorHandles then box:HideUnusedSpellIndicatorHandles(dynamicSpellHandlesActive) end
        if selectedRuntimeSpellHandleUsed then
            HideSpellEffectPreview(env, spellHandle)
            HideSpellIconEffectPreview(spellHandle)
            spellHandle:Hide()
        elseif scene.selectedSpellCfg and (scene.selectedSpellPlacedEnabled or scene.selectedSpellNeedsPlacementPreview) then
            Stage.ConfigureSelectedSpellHandle(st, spellHandle)
            HideSpellEffectPreview(env, spellHandle)
        else
            HideSpellEffectPreview(env, spellHandle)
            HideSpellIconEffectPreview(spellHandle)
            spellHandle:Hide()
        end
        selectedSpellEffectOwner:ClearAllPoints()
        selectedSpellEffectOwner:SetAllPoints(st.mock)
        if scene.selectedSpellEffectAvailable and selectedSpellEffect then
            ApplySpellEffectPreview(env, selectedSpellEffectOwner, selectedSpellEffect)
        else
            HideSpellEffectPreview(env, selectedSpellEffectOwner)
        end
        scene.dynamicSpellHandlesActive = dynamicSpellHandlesActive
        FinalizeScene(scene)
end

-- Configured indicators are painted by the engine. The editor's unplaced/disabled
-- selected sample remains a handle-owned insertion preview until it has a live slot.
function Stage.RenderSpellIndicators(st, env)
    if not (st.scene.engineConfig and st.scene.engineConfig.spellIndicators) then
        return Stage.RenderLegacySpellIndicators(st, env)
    end
    local scene, box, frame = st.scene, st.self, st.mock._cell
    local active = box._msufGFSpellHandlesActiveScratch or {}
    box._msufGFSpellHandlesActiveScratch = active
    wipe(active)
    local root = scene.engineConfig and scene.engineConfig.spellIndicators
    local pool, used, selectedDrawn = frame and frame._msufGFSpellIndicatorPreviews, 0, false
    local effects = MSUF.MSUF_Auras3.SpellIndicators
    local engineEffects = effects and effects.ApplyPreviewFrameEffect
    for i, item in ipairs(root and root.slots or {}) do
        if item.enabled then
            used = used + 1
            local visual = pool and pool[used]
            local handle = box:EnsureSpellIndicatorHandle(item, i)
            local selected = item.specKey == scene.selectedSpellSpecKey and item.auraName == scene.selectedSpellAuraName
            if visual and handle then
                handle._msufSpellIndicatorLayer = item.layer
                handle._msufSpellIndicatorStrata = item.strata
                if handle._label then handle._label:SetText(item.display or item.auraName or "SPELL") end
                if visual._timer then st.SetPreviewFont(visual._timer, tonumber(item.cooldownSize) or 8) end
                if visual._stack then
                    st.SetPreviewFont(visual._stack, item.visual == "number" and (tonumber(item.size) or 18) * 0.72
                        or tonumber(item.stackSize) or 10)
                end
                local shown = M.PreviewHelpers.BindGroupSceneHandle(handle, st.mock, visual, st.previewScale, item.anchor)
                local legacyEffect = not engineEffects and EffectShown(item.frameEffect)
                if legacyEffect then ApplySpellEffectPreview(env, handle, item.frameEffect)
                else HideSpellEffectPreview(env, handle) end
                if not shown and (visual._frameEffectOwner or legacyEffect) then
                    handle:SetSize(1, 1)
                    if handle._label then handle._label:Hide() end
                    st.LayoutHandle(handle, "CENTER", 0, 0, "CENTER")
                end
                if shown or visual._frameEffectOwner or legacyEffect then
                    active[handle._msufSpellIndicatorPreviewKey] = handle
                    selectedDrawn = selectedDrawn or selected
                end
            end
        end
    end
    if box.HideUnusedSpellIndicatorHandles then box:HideUnusedSpellIndicatorHandles(active) end
    local fallback = env.spellHandle
    if not selectedDrawn and scene.selectedSpellCfg
        and (scene.selectedSpellPlacedEnabled or scene.selectedSpellNeedsPlacementPreview) then
        Stage.ConfigureSelectedSpellHandle(st, fallback)
    else
        HideSpellIconEffectPreview(fallback)
        fallback:Hide()
    end
    local effectOwner = env.selectedSpellEffectOwner
    if not selectedDrawn and scene.selectedSpellEffectAvailable then
        ApplySpellEffectPreview(env, effectOwner, scene.selectedSpellEffect)
    else
        HideSpellEffectPreview(env, effectOwner)
    end
    scene.dynamicSpellHandlesActive = active
    FinalizeScene(scene)
end
