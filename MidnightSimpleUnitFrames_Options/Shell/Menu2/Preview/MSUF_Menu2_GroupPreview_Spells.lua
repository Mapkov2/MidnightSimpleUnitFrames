-- Spells state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.GroupRenderFactories = M.GroupRenderFactories or {}

local function RequireFields(domain, values, fields)
    assert(type(values) == "table", domain .. " interface is required")
    for key in fields:gmatch("%S+") do
        assert(values[key] ~= nil, domain .. "." .. key .. " is required")
    end
end

M.GroupRenderFactories.Spells = function(runtime, layout, layers, scene)
    RequireFields("Spells.Runtime", runtime, "Core Menu Wipe")
    RequireFields("Spells.Layout", layout, "PixelLayoutRegion Floor Max Min IconScale")
    RequireFields("Spells.Layers", layers, "API SetFrameLevel ElementLevel ApplyHandleStrata SyncIconDetailLevels")
    RequireFields("Spells.Scene", scene, "Finalize Stage EmptyAppearance SelectedPlacedDefault")
local MSUF, M, wipe = runtime.Core, runtime.Menu, runtime.Wipe
local PixelLayoutRegion, floor, max, min = layout.PixelLayoutRegion, layout.Floor, layout.Max, layout.Min
local PreviewIconScale = layout.IconScale
local Layers, SetPreviewFrameLevel, PreviewElementLevel = layers.API, layers.SetFrameLevel, layers.ElementLevel
local ApplyHandleStrata, SyncIconDetailLevels = layers.ApplyHandleStrata, layers.SyncIconDetailLevels
local FinalizeScene, Stage = scene.Finalize, scene.Stage
local EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT = scene.EmptyAppearance, scene.SelectedPlacedDefault

local function EffectKind(effect)
    return type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
end

local function EffectShown(effect)
    local kind = EffectKind(effect)
    return kind ~= "" and kind ~= "none"
end
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
    local runtime = a3 and (a3.SpellIndicators or a3.ClassicVisuals)
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

local function ApplySpellEffectPreview(env, handle, effect)
    if not (handle and type(effect) == "table") then return end
    local a3 = env.MSUF.MSUF_Auras3
    local runtime = assert(a3.SpellIndicators or a3.ClassicVisuals,
        "MSUF: spell indicator runtime is required by the group preview")
    ApplyRuntimeSpellEffect(env, runtime, handle, effect)
end

local function SuspendSpellPreviewRoot(root)
    if not root then return end
    if root._msufMenuSpellSampleOwner then return MSUF.GF.HidePreviewSpellSample(root._msufMenuSpellSampleOwner) end
    StopPreviewAnimation(root._msufSpellPreviewPulse)
    HidePreviewGlow(root)
    root:Hide()
end
local function SuspendHandleEffects(env, handle)
    HideRuntimePreviewEffect(env, handle)
    SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewEffectRoot)
    SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewIconEffectRoot)
end
local function SpellShowFlag(appearance, placed, key)
    local value = appearance[key]
    if value == nil then value = placed[key] ~= false end
    return value
end

local function HideSpellIconEffectPreview(handle)
    local root = handle and handle._msufSpellPreviewIconEffectRoot
    if not root then return end
    if root._msufMenuSpellSampleOwner then
        MSUF.GF.HidePreviewSpellSample(root._msufMenuSpellSampleOwner)
    else
        HidePreviewGlow(root)
        root:Hide()
    end
end
-- Translate the editor placement into the engine scene's indicator contract.
-- The retained visual is adopted by its drag handle exactly like a configured
-- spell slot; all art, fonts, masks, timer/bar and icon-style rendering is shared.
local function ConfigureSpellPreviewHandle(st, handle, item, placed, appearance, fallbackTexture, fallbackColor)
    -- Insertion samples are static. Their native animation owns the glow;
    -- geometry and slot translation run only on settings refreshes.
    if st.animatingSamples then return handle and handle._msufEngineVisual ~= nil end
    if not (handle and placed and st.mock._cell) then return false end
    appearance = appearance or EMPTY_APPEARANCE
    local exact = placed.spellIndicatorSlot == true
    local slot = handle._msufSpellSampleSlot
    if not slot then
        slot = {}
        handle._msufSpellSampleSlot = slot
    end
    wipe(slot)
    for key, value in pairs(appearance) do slot[key] = value end
    local scale = (exact or placed._msufIconScaleApplied == true) and 1 or st.scene.spellIconScale
    slot.visual = exact and (placed.visual or "none") or (placed.type or "icon")
    slot.size = max(1, (tonumber(placed.size) or 20) * scale)
    local barWidth = tonumber(exact and placed.width or placed.barWidth)
    slot.width = slot.visual == "bar" and max(slot.size * 2, barWidth and barWidth * scale or slot.size * 3) or slot.size
    slot.height = slot.size
    if slot.visual == "number" then slot.width, slot.height = max(18, slot.size), max(18, slot.size) end
    slot.anchor, slot.x, slot.y = placed.anchor or "TOPLEFT", placed.x or 0, placed.y or 0
    slot.icon = item and item.icon or fallbackTexture or st.env.CurrentSpellTexture(st.kind)
    slot.color = item and item.color or fallbackColor
    slot.iconZoom = exact and placed.iconZoom or st.scene.spellIconZoom
    slot.iconShape = appearance.iconShape or "RECTANGLE"
    slot.iconEffect = placed.iconEffect
    slot.showCooldownText = appearance.showCooldownText
    if slot.showCooldownText == nil then slot.showCooldownText = SpellShowFlag(appearance, placed, "showCooldown") end
    slot.showCooldownSwipe = SpellShowFlag(appearance, placed, "showCooldownSwipe")
    slot.showStacks = SpellShowFlag(appearance, placed, "showStacks")
    if slot.visual == "bar" then
        slot.durationBarReverseFill = exact and placed.durationBarReverseFill == true
            or (not exact and tostring(placed.growth or "RIGHTDOWN"):upper():sub(1, 4) == "LEFT")
        slot.showCooldownText = exact and placed.showCooldownText == true or (not exact and placed.barShowTimer == true)
        slot.cooldownAnchor = (exact and placed.cooldownAnchor or placed.barTimerAnchor) or "CENTER"
        slot.cooldownX = (exact and placed.cooldownX or placed.barTimerX) or 0
        slot.cooldownY = (exact and placed.cooldownY or placed.barTimerY) or 0
    end
    -- Frame effects retain their separate runtime-owned surface below.
    slot.frameEffect = nil
    local color = handle._msufSpellIndicatorColor or {}
    handle._msufSpellIndicatorColor, handle._color = color, color
    local source = slot.color or EMPTY_APPEARANCE
    color[1], color[2], color[3], color[4] = source[1] or 0.69, source[2] or 0.50, source[3] or 0.88, source[4] or 1
    slot.color = color
    slot.font = st.previewFont
    slot.cooldownSize = tonumber(slot.cooldownSize or placed.cooldownSize) or 8
    slot.numberTextSize = slot.visual == "number" and max(8, slot.size * 0.72) or nil
    slot.stackText = slot.visual == "number" and (slot.showStacks and "9" or "") or nil
    local visual = MSUF.GF.PreviewSpellSample(st.mock._cell, handle, slot)
    if not visual then return false end
    handle._msufSpellIndicatorLayer = item and item.layer
    handle._msufSpellIndicatorStrata = item and item.strata
    if handle._label then
        handle._label:SetText(item and (item.display or item.auraName) or "SPELL")
        handle._label:Show()
    end
    return M.PreviewHelpers.BindGroupSceneHandle(handle, st.mock, visual, st.previewScale, slot.anchor, slot.x, slot.y)
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

return BuildSceneSpells, FinalizeSpellLevels, SuspendHandleEffects
end
