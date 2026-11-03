-- Unit preview runtime slots, interaction handles and layer presentation.
-- Frame creation and profile writes belong to the view and selection owners.
local _, MSUF = ...
local MenuState = MSUF.MSUF2
local RequireFields = MenuState.PreviewContracts.RequireFields
local Presentation = {}
MSUF.UFPreviewPresentation = Presentation
function Presentation.Install(Stage, shared)
    RequireFields("UnitPresentation.Stage", Stage, "")
    RequireFields("UnitPresentation.Shared", shared, "PreviewLayerWanted ClassPowerWidth")
    local PreviewLayerWanted = shared.PreviewLayerWanted
    local PreviewClassPowerWidth = shared.ClassPowerWidth
    local CPPreview = MenuState.ClassPowerPreview or {}
    local PreviewHelpers = MenuState.PreviewHelpers or {}
    local CastbarScene = MSUF.UFPreviewCastbar
    local floor, min, max = math.floor, math.min, math.max
-- Region lists and placement options reused by every text handle placement,
-- so neither a repaint nor an animation tick allocates them.

local VALUE_TEXT_HANDLE_FIELDS = {
    hp = { "hpLeft", "hpCenter", "hpRight" },
    power = { "powerLeft", "powerCenter", "powerRight" },
}
local AURA_HANDLE_FIELDS = {
    buff = "handleAuraBuffs", debuff = "handleAuraDebuffs", custom1 = "handleAuraCustom1",
    custom2 = "handleAuraCustom2", custom3 = "handleAuraCustom3", custom4 = "handleAuraCustom4",
}
-- Lanes the Auras layer chip is available for besides buff and debuff.
local AURA_CHIP_LANES = { "custom1", "custom2", "custom3", "custom4", "defensivePortrait", "targetDotPortrait" }
local function HandleRegionList(box, field, a, b, c)
    return PreviewHelpers.CachedRegionList(box, "_msufTextHandleRegionLists", field, a, b, c)
end
local function TextHandleOptions(box, scale)
    local opts = box._msufTextHandleOptions
    if not opts then
        opts = { fitText = true, useScaledRect = true }
        box._msufTextHandleOptions = opts
    end
    opts.coordinateScale = scale
    return opts
end
local function PlaceTextSlotHandle(st, handle, region, field)
    if not handle then return end
    if not (region and region.IsShown and region:IsShown()) then
        handle:Hide()
        return
    end
    local max, box = st.max, st.box
    local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
    local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
    handle:SetSize(max(26, w + 10), max(18, h + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(handle, st.canvas, HandleRegionList(box, field, region), 3,
        TextHandleOptions(box, st.scale)) then st.PlaceHandle(handle, region) end
end
local function PlaceValueTextHandles(st, kind, together, mainHandle, leftHandle, centerHandle, rightHandle, leftRegion, centerRegion, rightRegion)
    local box = st.box
    if together then
        st.SetShownSafe(leftHandle, false)
        st.SetShownSafe(centerHandle, false)
        st.SetShownSafe(rightHandle, false)
        if st.UnitPreviewText.PlaceHandleAroundRegions(mainHandle, st.canvas,
            HandleRegionList(box, kind, leftRegion, centerRegion, rightRegion), 3, TextHandleOptions(box, st.scale)) then
            return
        end
        if not ((leftRegion and leftRegion:IsShown()) or (centerRegion and centerRegion:IsShown())
            or (rightRegion and rightRegion:IsShown())) then
            mainHandle:Hide()
            return
        end
        local max = st.max
        mainHandle:SetSize(max(46, rightRegion:GetStringWidth() + 10), max(18, rightRegion:GetStringHeight() + 6))
        st.PlaceHandle(mainHandle, rightRegion)
        return
    end
    if mainHandle then mainHandle:Hide() end
    local fields = VALUE_TEXT_HANDLE_FIELDS[kind]
    PlaceTextSlotHandle(st, leftHandle, leftRegion, fields[1])
    PlaceTextSlotHandle(st, centerHandle, centerRegion, fields[2])
    PlaceTextSlotHandle(st, rightHandle, rightRegion, fields[3])
end
--- Value text handles around the texts as they read now: the full refresh
--- resolves reverse order and moves-together once, the animation tick refits
--- the handles after the values changed width.
function Stage.PlaceValueTextHandles(st)
    local box, mock = st.box, st.mock
    -- Under reverse order the configured left slot renders on the physical
    -- right FontString (and vice versa); pair each slot handle with the
    -- FontString that actually shows its content so drags edit visible text.
    local hpLeft, hpRight = mock.hpTextLeft, mock.hpText
    if st.hpHandlesReversed then hpLeft, hpRight = hpRight, hpLeft end
    PlaceValueTextHandles(st, "hp", st.hpTextMovesTogether, box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, hpLeft,
        mock.hpTextCenter, hpRight)
    PlaceValueTextHandles(st, "power", st.powerTextMovesTogether, box.handlePower, box.handlePowerLeft, box.handlePowerCenter, box.handlePowerRight,
        mock.powerTextLeft, mock.powerTextCenter, mock.powerText)
end
function Stage.PlaceClassPowerTextHandle(st)
    local box, max = st.box, st.max
    local scene = box._cpScene
    local text = scene and scene.CP and scene.CP.text
    if not (text and text:IsShown()) then
        box.handleClassPowerText:Hide()
        return
    end
    box.handleClassPowerText:SetSize(max(26, text:GetStringWidth() + 10), max(18, text:GetStringHeight() + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, st.canvas, HandleRegionList(box, "classPowerText", text), 3,
        TextHandleOptions(box, st.scale)) then st.PlaceHandle(box.handleClassPowerText, text) end
end
--- Animation tick for the class resource: the wave's count, partial and rune states go to the scene, which
--- repaints only the mode painter.
function Stage.AnimateClassPower(st)
    local box, spec = st.box, st.classPowerPreviewSpec
    local scene = box._cpScene
    if not (st.classPowerOn and scene and spec) then return end
    local elapsed = st.animState.elapsed
    CPPreview.SceneValues(box._cpTick, spec, CPPreview.AnimatedValue(spec, elapsed), elapsed, true)
    if scene:Tick(box._cpTick) then Stage.PlaceClassPowerTextHandle(st) end
end
--- The class resource: a slot sized and anchored like the live container, around the engine's ClassPower scene.
--- The scene lays the container out inside a player-frame stand-in over the unit body, as the live layout does.
function Stage.RenderClassPower(st)
    local S, box, bars, cpH, max, mock = st.S, st.box, st.bars, st.cpH, st.max, st.mock
    local scene = box._cpScene
    if not (st.classPowerOn and PreviewLayerWanted(box, "classPower")) then
        if scene then scene:Hide() end
        mock.classPower:Hide()
        box.handleClassPower:Hide()
        box.handleClassPowerText:Hide()
        return
    end
    mock.classPower:Show()
    local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, st.w, cpH, st.classPowerSegCount)
    mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
    mock.classPower:ClearAllPoints()
    -- Same anchor as the live container (ClassPower Layout.Position).
    mock.classPower:SetPoint("TOPLEFT", mock._body, "TOPLEFT",
        S(CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0)),
        S((tonumber(bars.classPowerOffsetY) or 0) - 2))
    local root = box._cpSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(mock)
        box._cpSceneRoot, box._cpSample, box._cpTick, box._cpCooldowns = root, {}, {}, {}
        box._cpOpts = { sample = box._cpSample, point = "CENTER", x = 0, y = 0 }
    end
    root:Activate()
    local sample, spec, animState = box._cpSample, st.cpSpec, st.animState
    local animated = animState ~= nil and st.classPowerPreviewSpec ~= nil
    local elapsed = animState and animState.elapsed
    CPPreview.SceneStatic(sample, spec, st.cpClass)
    CPPreview.SceneValues(sample, spec, animated and CPPreview.AnimatedValue(spec, elapsed) or nil, elapsed, animated)
    local opts = box._cpOpts
    opts.scale, opts.playerWidth, opts.playerHeight = st.scale, st.w, st.h
    opts.cooldowns = CPPreview.ProjectCooldowns(box._cpCooldowns)
    scene = root:ClassPower(opts)
    box._cpScene = scene
    local frame = scene:Frame()
    if frame then frame:SetFrameLevel(mock.classPower:GetFrameLevel()) end
    Stage.PlaceClassPowerTextHandle(st)
    -- The handle follows the container the scene actually laid out (an outline can widen it past the slot).
    local container = scene.CP.container
    box.handleClassPower:SetSize(max(36, container:GetWidth() * st.scale), max(18, max(2, container:GetHeight() * st.scale) + 8))
    st.PlaceHandle(box.handleClassPower, container)
end

--- The castbar slot: a sized, anchored holder (layers, colour painter, selection) around the engine's castbar
--- scene. The scene is made on the first paint and reused for the box.
Stage.RenderCastbar = CastbarScene.ComposeScene

--- Aura lanes, the boss target marker and every status indicator icon/text
--- with its handle. Each handle is sized around the region the scene painted
--- (its size at the preview scale plus a pad, floored where given), placed and
--- shown; a missing or hidden region hides it. Inline: every refresh runs it.
function Stage.RenderSceneHandles(st, Preview)
    local box, mock = st.box, st.mock
    local body = mock._body
    st.hpTextOn = body.hpText and body.hpText:IsShown()
    st.powerTextOn = body.powerText and body.powerText:IsShown()
    st.showNamePreview = body.nameText and body.nameText:IsShown()
    st.statusLayerAvailable = false
    local auras = body._msufGFFrameAuraPreviewHosts or {}
    for key, field in pairs(AURA_HANDLE_FIELDS) do
        local handle = box[field]
        if handle then
            local host = auras[key]
            if key == "custom4" then
                local portrait = auras.defensivePortrait
                if not (portrait and portrait:IsShown()) then portrait = auras.targetDotPortrait end
                if portrait and portrait:IsShown() then host = portrait end
            end
            handle._msufAuraDragVisual = host
            if host and host:IsShown() then
                handle:SetSize(st.max(18, host:GetWidth() * st.scale + 8), st.max(18, host:GetHeight() * st.scale + 8))
                st.PlaceHandle(handle, host)
                handle:Show()
            else handle:Hide() end
        end
    end
    local symbol = body._msufSceneDispelSymbol
    if box.handleDispelSymbol then
        box.handleDispelSymbol._msufAuraDragVisual = symbol
        if symbol and symbol:IsShown() then
            box.handleDispelSymbol:SetSize(st.max(18, symbol:GetWidth() * st.scale + 6), st.max(18, symbol:GetHeight() * st.scale + 6))
            st.PlaceHandle(box.handleDispelSymbol, symbol)
            box.handleDispelSymbol:Show()
        else box.handleDispelSymbol:Hide() end
    end
    -- A sample layer the layer filter hides is hidden, not missing: while its settings are on and the scene built
    -- the region, the chip stays available so a click can bring it back.
    local overlay, spec = body._msufSceneDispelOverlay, st.runtimeSpec
    local specOn = spec ~= nil and spec.enabled ~= false
    local overlayCfg, symbolCfg = spec and spec.dispelOverlay, spec and spec.dispelSymbol
    box._previewDispelOverlayAvailable = overlay ~= nil
        and (overlay:IsShown() or (specOn and overlayCfg ~= nil and overlayCfg.enabled == true))
    box._previewDispelSymbolAvailable = symbol ~= nil
        and (symbol:IsShown() or (specOn and symbolCfg ~= nil and symbolCfg.enabled == true))
    for i, handle in pairs(box.texLayerHandles) do
        local holder = mock.texLayers and mock.texLayers[i]
        if holder and holder:IsShown() then
            handle:SetSize(st.max(18, holder:GetWidth() * st.scale + 6), st.max(18, holder:GetHeight() * st.scale + 6))
            st.PlaceHandle(handle, holder)
            handle:Show()
        else handle:Hide() end
    end
    for _, statusSpec in pairs(st.D.STATUS_PREVIEW) do
        local id = statusSpec.id
        local region, handle = mock.icons[id], box.statusHandles[id]
        if box._unitScene:IsRegionShown(region) then
            st.statusLayerAvailable = true
            handle:SetSize(st.max(18, region:GetWidth() * st.scale + 6), st.max(18, region:GetHeight() * st.scale + 6))
            st.PlaceHandle(handle, region)
            handle:Show()
        else handle:Hide() end
    end
    if box.handleBossTarget then
        local marker = body._msufBossTargetIndicator
        if marker and marker:IsShown() then
            box.handleBossTarget:SetSize(marker:GetWidth() * st.scale + 8, marker:GetHeight() * st.scale + 8)
            st.PlaceHandle(box.handleBossTarget, marker)
            box.handleBossTarget:Show()
        else box.handleBossTarget:Hide() end
    end
    local portrait = mock.portrait
    if portrait and portrait:IsShown() then
        box.handlePortrait:SetSize(portrait:GetWidth() * st.scale + 6, portrait:GetHeight() * st.scale + 6)
        st.PlaceHandle(box.handlePortrait, portrait)
        box.handlePortrait:Show()
    else box.handlePortrait:Hide() end
    if st.detachedPower and mock.detachedPower then
        box.handleDetachedPower:SetSize(mock.detachedPower:GetWidth() * st.scale + 6, mock.detachedPower:GetHeight() * st.scale + 6)
        st.PlaceHandle(box.handleDetachedPower, mock.detachedPower)
        box.handleDetachedPower:Show()
    else box.handleDetachedPower:Hide() end
end

function Stage.RenderArenaTrinket(st)
    local painter, box = MenuState.ArenaTrinketPreview, st.box
    st.trinketAvailable = false
    if not painter then return end
    local available, icon = painter.Paint(st.mock, st.key, PreviewLayerWanted(box, "trinket"), st.S, st.scale)
    st.trinketAvailable = available == true
    local handle = box.handleArenaTrinket
    if not handle then return end
    if icon then
        handle:SetSize(st.max(18, icon:GetWidth() * st.scale + 8), st.max(18, icon:GetHeight() * st.scale + 8))
        st.PlaceHandle(handle, icon)
    else
        handle:Hide()
    end
end

local function AuraLaneAvailable(lanes, kind)
    local lane = lanes and lanes[kind]
    return lane and lane.enabled == true and lane.max > 0 or false
end
--- Layer availability for the layer rail, text handles, text focus, layer
--- visibility, transparency and handle selection visuals.
function Stage.FinalizeLayersAndHandles(st)
    local box, canvas, conf, key, mock = st.box, st.canvas, st.conf, st.key, st.mock
    local available = box.layerAvailable or {}
    box.layerAvailable = available
    available.guides = true
    available.nameText = box._unitScene:HasLayerContent("nameText")
    available.hpText = box._unitScene:HasLayerContent("hpText")
    available.powerText = box._unitScene:HasLayerContent("powerText")
    available.portrait = st.hasPortrait
    available.power = st.powerEnabled == true
    available.classPower = st.classPowerOn
    available.castbar = st.castEnabled
    local lanes = st.auraPreviewState
    available.buff, available.debuff = AuraLaneAvailable(lanes, "buff"), AuraLaneAvailable(lanes, "debuff")
    available.auras = false
    for i = 1, #AURA_CHIP_LANES do
        if AuraLaneAvailable(lanes, AURA_CHIP_LANES[i]) then
            available.auras = true
            break
        end
    end
    available.dispelOverlay = box._previewDispelOverlayAvailable == true
    available.dispelSymbol = box._previewDispelSymbolAvailable == true
    available.status = box._unitScene:HasLayerContent("status")
    available.trinket = st.trinketAvailable == true
    available.texLayer = conf.texLayerEnabled == true or conf.texLayer2Enabled == true or conf.texLayer3Enabled == true
    available.bounds = true
    for i = 1, #(box.layerButtons or {}) do
        local button = box.layerButtons[i]
        if button.key == "classPower" and button.SetShown then button:SetShown(key == "player") end
        if button.key == "trinket" and button.SetShown then button:SetShown(key == "arena") end
        if button.refresh then button:refresh() end
    end
    PreviewHelpers.RefreshSampleEffectHint(box)
    if box.LayoutLayerRail then box:LayoutLayerRail((box.GetWidth and box:GetWidth() or 0) - 24) end
    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep and mock.totInlineSep:IsShown() then
        nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + st.S(8)
    end
    box.handleName:SetSize(st.max(46, nameHandleW), st.max(18, mock.nameText:GetStringHeight() + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas,
        HandleRegionList(box, "name", mock.nameText, mock.totInlineSep, mock.totInlineText), 3,
        TextHandleOptions(box, st.scale)) then st.PlaceHandle(box.handleName, mock.nameText) end
    PlaceTextSlotHandle(st, box.handleRaidGroupName, mock.raidGroupNameText, "raidGroupName")
    st.hpHandlesReversed = st.R.TextScopeGet(key, "hpTextReverse", false) == true
    st.hpTextMovesTogether = st.UnitPreviewTextMovesTogether(key, "hp")
    st.powerTextMovesTogether = st.UnitPreviewTextMovesTogether(key, "power")
    Stage.PlaceValueTextHandles(st)
    st.R.ApplyPreviewTextFocus(box, canvas, mock)
    st.ApplyPreviewLayerVisibility(box)
    st.RefreshHandleSelectionVisuals(box)
end


end
