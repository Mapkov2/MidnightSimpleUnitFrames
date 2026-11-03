--- Unit preview render/composition.
---
--- Coordinates scene inputs and the ordered refresh/animation stages.
--- Geometry and visual presentation live in their dedicated owners.
local _, MSUF = ...
local FILE = "Menu2/UnitPreview_Render"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Vanilla, TBC and Mists load this file too; their differences are client
-- facts read once here. A harness without MSUF.Client renders as Mainline.
-- Classic draws a gold ring where the stock portrait atlas is missing (every
-- client stamps texture layers after the portrait); Era's legacy PlayerFrame has no modern
-- HUD portrait atlases at all; boss pieces need boss units (SupportsUnit).
local Render = MSUF.UFPreviewRender or {}
MSUF.UFPreviewRender = Render
local MenuState = MSUF.MSUF2 or {}
local PickFallbackTable = MenuState.PickFallbackTable
local Fallbacks = MenuState.Fallbacks or {}
local PreviewHelpers = MenuState.PreviewHelpers or {}

-- Read-only stand-in for a scene table the scene has not built.
local EMPTY = {}
local Animation = assert(MSUF.PreviewAnimation, "Unit preview requires PreviewAnimation")
local BuildPreviewAnimationFrameState = Animation.BuildFrameState
local UnitFrameSizeBounds = MSUF.Require("MSUF_UnitFrameSizeBounds", FILE)

-- Preview scale and resolved FULL extents are inputs to the runtime painter.


-- The settings section that owns each sample-effect layer: it switches the layer on while it is open.
Render.SAMPLE_LAYER_SECTIONS = { dispelOverlay = "unit_dispel_overlay", dispelSymbol = "unit_dispel_symbol" }

-- Empties a reusable table and refills it with the fields of source.
local function RefillTable(target, source)
    for k in pairs(target) do target[k] = nil end
    for k, v in pairs(source or EMPTY) do target[k] = v end
    return target
end
local function CopyPreviewAnimationData(box, data, hpFrac, powerFrac)
    local copy = box and box._previewAnimationData
    if not copy then
        copy = {}
        if box then box._previewAnimationData = copy end
    else
        for k in pairs(copy) do copy[k] = nil end
    end
    for k, v in pairs(data or EMPTY) do copy[k] = v end
    copy.hp = hpFrac
    copy.power = powerFrac
    -- Live snapshots carry exact current values; while the combat animation
    -- drives the fractions, value texts must follow the animated fraction on
    -- the live max scale instead of freezing on the sampled current value.
    copy.hpCur = nil
    copy.powerCur = nil
    return copy
end

local function UnitPreviewAnimationState(box, index, key)
    if not (box and box._animationEnabled == true) then return nil end
    local scratch = box._previewAnimationState
    if not scratch then
        scratch = {}
        box._previewAnimationState = scratch
    end
    return BuildPreviewAnimationFrameState(box, index, key, scratch, box._animationElapsed)
end
local function PreviewLayerWanted(box, layerKey)
    local visibility = box and box.layerVisibility
    return not (visibility and visibility[layerKey] == false)
end
local function NumberOrOne(value) return tonumber(value) or 1 end
local function CastbarNumFallback(_, _, fallback) return tonumber(fallback) or 0 end
local UNIT_RENDER_FALLBACKS = {
    RuntimeAppliedPortraitSizeForPreviewKey = Fallbacks.Nil, RuntimeVisualScaleForPreviewKey = Fallbacks.One,
    RuntimeCastbarVisualScaleForPreviewKey = Fallbacks.One, ClampPreviewZoom = NumberOrOne,
    ResolveDefaultPreviewZoomLock = Fallbacks.Noop, UpdatePreviewZoomControls = Fallbacks.Noop,
    CastbarShowIcon = Fallbacks.True, CastbarShowText = Fallbacks.TruePair, ReadCastbarNum = CastbarNumFallback,
    TextScopeGet = Fallbacks.Nil, ApplyPreviewTextFocus = Fallbacks.Noop,
}

local CastbarScene = MSUF.UFPreviewCastbar
local PlaceCastTimeHandle = CastbarScene.RefreshTimeHandle
local function AnimatedPreviewData(st, data, powerFrac)
    local box = st.box
    local animState = UnitPreviewAnimationState(box, 1, st.key)
    local animHp = animState and tonumber(animState.hpPct)
    local animPower = animState and tonumber(animState.powerPct)
    if animHp then
        if animHp < 0 then animHp = 0 elseif animHp > 1 then animHp = 1 end
        if animPower == nil then animPower = powerFrac end
        if animPower < 0 then animPower = 0 elseif animPower > 1 then animPower = 1 end
        powerFrac = animPower
        data = CopyPreviewAnimationData(box, data, animHp, powerFrac)
    end
    return data, powerFrac, animState
end
local BODY_ALIASES = {
    healthBar = "hpBar", hpBar = "hpBar", hpBG = "hpBarBG", healthBackgroundBar = "healthBackgroundBar",
    powerBG = "powerBarBG", nameText = "nameText", totInlineSep = "totInlineSep", totInlineText = "totInlineText",
    hpTextLeft = "hpTextLeft", hpTextCenter = "hpTextCenter", hpText = "hpText", hpTextPct = "hpTextPct",
    powerTextLeft = "powerTextLeft", powerTextCenter = "powerTextCenter", powerText = "powerText", powerTextPct = "powerTextPct",
    raidGroupNameText = "raidGroupNameText", portrait = "MSUFPortraitHolder", detachedPower = "targetPowerBar",
    healPred = "incomingHealBar", absorb = "absorbBar", healAbsorb = "healAbsorbBar",
}
local STATUS_REGIONS = {
    raidmarker = "raidTargetIcon", leader = "leaderIcon", assist = "assistIcon", elite = "eliteIcon",
    bossNumber = "bossNumberText", statusAFKTimer = "statusAFKTimerText",
    level = "levelText", raceText = "raceText", classText = "classStatusText", statusCombat = "combatStateIndicatorIcon",
    statusResting = "restingIndicatorIcon", statusIncomingRes = "incomingResIndicatorIcon", statusPvp = "pvpIndicatorIcon",
    statusText = "_msufScene_statusText", statusGhostText = "_msufScene_statusGhostText",
    statusAFKText = "_msufScene_statusAFKText", statusDNDText = "_msufScene_statusDNDText",
    statusPetHappiness = "petHappinessIndicatorHolder", statusThreat = "threatIndicatorHolder", statusPetXP = "petXPBar",
    stance = "stanceIndicatorText",
}
-- Interaction keys that share the hidden sentinel text when the scene paints no region for them.
local SENTINEL_TEXT_KEYS = {
    "nameText", "totInlineSep", "totInlineText", "hpTextLeft", "hpTextCenter", "hpText", "hpTextPct",
    "powerTextLeft", "powerTextCenter", "powerText", "powerTextPct", "raidGroupNameText",
}
local function AliasScene(mock, frame)
    mock._body = frame
    for alias, field in pairs(BODY_ALIASES) do mock[alias] = frame[field] end
    mock.texLayers = frame._msufTexLayers
    mock.bg = frame.hpBarBG
    if mock.portrait then mock.portrait.tex = frame.portrait end
    if mock.detachedPower then
        mock.detachedPower.bg = frame.powerBarBG
        mock.detachedPower.fill = frame.targetPowerBar:GetStatusBarTexture()
        mock.detachedPower.edge = frame.targetPowerBar._msufDetachedShapeEdge
    end
    mock.hp = frame.hpBar and frame.hpBar:GetStatusBarTexture()
    mock.power = frame.targetPowerBar and frame.targetPowerBar:GetStatusBarTexture()
    -- Legacy interaction keys without a live region share one hidden sentinel, never a second painted text.
    local sentinel = mock._emptyText
    if not sentinel then
        sentinel = PixelLayoutRegion(mock:CreateFontString(nil, "OVERLAY"))
        sentinel:Hide()
        mock._emptyText = sentinel
    end
    for i = 1, #SENTINEL_TEXT_KEYS do
        local key = SENTINEL_TEXT_KEYS[i]
        mock[key] = mock[key] or sentinel
    end
    for key, field in pairs(STATUS_REGIONS) do
        local region = frame[field]
        mock.icons[key] = region
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then region.txt = region end
    end
    if frame.threatIndicatorHolder then
        frame.threatIndicatorHolder.txt, frame.threatIndicatorHolder.plate = frame.threatIndicatorText, frame.threatIndicatorPlate
    end
    if frame.petHappinessIndicatorHolder then frame.petHappinessIndicatorHolder.tex = frame.petHappinessIndicatorIcon end
    mock._msufBossTargetIndicator = frame._msufBossTargetIndicator
end

local Stage = {}

-- Deps every later stage reads from st.
local STAGE_DEP_FIELDS = {
    "TR", "PortraitStyleGet", "max", "min", "abs", "floor", "format", "TEX_W8", "CastbarEnabled",
    "ReadCastbarSize", "CastbarOffsetFields", "CastbarDetached", "CanDetachPowerBarKey", "ClampPreviewLayer",
    "ReadPowerBarHeight", "PlaceHandle", "UnitPreviewText", "UnitPreviewTextMovesTogether", "SetShownSafe",
    "ApplyPreviewLayerVisibility", "ApplyPreviewTransparency", "RefreshHandleSelectionVisuals", "Auras",
}
-- Refresh reasons that leave the bound menu controls alone (they only move or animate the preview).
local SKIP_CONTROL_REFRESH_REASONS = {
    OPTIONS_APPLY_DB = true, UNIT_MENU_ENTER = true, UNIT_MENU_REENTER = true, UNIT_PREVIEW_DRAG = true,
    UNIT_PREVIEW_ANIMATE = true, UNIT_PREVIEW_ANIMATE_TOGGLE = true, UNIT_PREVIEW_COMBAT_ANIMATE = true,
    UNIT_PREVIEW_ZOOM = true, UNIT_PREVIEW_ZOOM_STEP = true, UNIT_PREVIEW_ZOOM_FIT = true, UNIT_PREVIEW_ZOOM_1TO1 = true,
    MENU_TEXT_FOCUS = true, MENU_TEXT_CLEAR_FOCUS = true,
}

--- Resolves deps, the previewed unit, its config, live or mock data and the
--- runtime specs, then refreshes the bound menu controls and the title.
function Stage.ResolveInputs(st)
    local Deps, box, reason = st.D, st.box, st.reason
    local Auras = Deps.Auras
    local panel = box._msufPanel
    local UNIT_DATA = Deps.UNIT_DATA or {}
    local UNIT_LABELS = Deps.UNIT_LABELS or {}
    local key = Deps.CurrentPanelKey(panel)
    local conf, g = Deps.UnitDB(key)
    --- Guides are setting-backed, unlike the other ephemeral preview layers.
    --- Re-read them on every visible preview refresh so a factory reset or
    --- profile switch cannot leave the already-built layer rail stale.
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = g.unitPreviewGuidesEnabled == true
        -- The sample-effect layers follow their open settings section (an edge, so a chip click in between sticks).
        PreviewHelpers.SyncSampleLayerSections(box, box.layerVisibility, box._msuf2PinnedPreviewPageKey,
            Render.SAMPLE_LAYER_SECTIONS, MenuState.accordionState)
    end
    -- Live snapshot first so the preview mirrors the real frame's current
    -- state (exact name/class/HP/power); stylized mock only as fallback.
    box._playerManaSourcePreviewActive = key == "player"
        and PreviewHelpers.PlayerManaSourceActive
        and PreviewHelpers.PlayerManaSourceActive(conf) or false
    local data = (Deps.LiveUnitData and Deps.LiveUnitData(key, box._playerManaSourcePreviewActive))
        or UNIT_DATA[key] or UNIT_DATA.player or {}
    local root = box._unitSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(box.mock)
        box._unitSceneRoot = root
    end
    root:Activate()
    local scene = root:Unit(key)
    if not scene then return false end
    if box._unitScene and box._unitScene ~= scene then box._unitScene:Hide() end
    box._unitScene = scene
    local sample = box._unitSample or {}
    box._unitSample = sample
    RefillTable(sample, data)
    sample.player = data.isPlayer == true
    sample.reaction = data.reactionKind
    sample.level = data.level == "??" and -1 or tonumber(data.level)
    sample.absorb = data.absorb and data.absorb > 0
        and data.absorb / (data.hpMax or MSUF.UF.UnitScene.HEALTH_MAX)
        or MSUF.UF.UnitScene.SAMPLES[key].absorb or 0
    sample.powerType = data.powerType or MSUF.UFPreview.Model.POWER_TYPES[data.powerToken]
    if key == "target" and Deps.LiveUnitData then
        local inline = Deps.LiveUnitData("targettarget")
        if inline then sample.inline = inline.name end
    end
    sample.statusSelection = MSUF.UFPreview.GetStatusPreviewMode() == "all" and "all"
        or MSUF.UFPreview.selectedStatusId or "raidmarker"
    if key ~= "boss" and (sample.statusSelection == "elite" or sample.statusSelection == "all")
        and sample.classification ~= "elite" and sample.classification ~= "rareelite"
        and sample.classification ~= "rare" and sample.classification ~= "worldboss" then
        sample.classification = "elite"
    end
    local stance = MSUF.UFStance
    sample.stance = key == "player" and stance and stance.PreviewText and stance.PreviewText() or nil
    sample.leader, sample.assist, sample.combat, sample.resting, sample.incomingRes = true, true, true, true, true
    sample.frameEffect, sample.frameEffectLayer, sample.auraStyleKey = Auras.SampleEffect(key)
    sample.auraForceStandard = box._msuf2ColorPainterForceAuras == true
    sample.bossTargetPreview = true
    sample.raidTarget, sample.raidGroup, sample.pvp = 8, 2, "Alliance"
    root:SetClock(box._animationEnabled == true and box._animationElapsed or nil, true)
    scene.auraSampleCount = 4
    scene.level = (box.canvas:GetFrameLevel() or 0) + 6
    scene:Frame():SetFrameLevel(scene.level)
    local spec = scene:Compile()
    if data.live and spec.portrait and spec.portrait.enabled and spec.portrait.render ~= "CLASS" then
        local snapshot = box._portraitSnapshot
        if not snapshot then
            snapshot = PixelLayoutRegion(box.mock:CreateTexture(nil, "ARTWORK"))
            snapshot:Hide()
            box._portraitSnapshot = snapshot
        end
        if SetPortraitTexture then
            snapshot:SetTexture(nil)
            SetPortraitTexture(snapshot, data.liveUnit)
            local art = snapshot:GetTexture()
            if issecretvalue(art) ~= true and (type(art) == "number" or type(art) == "string") then sample.portraitTexture = art end
        end
    end
    scene:SetSample(sample, true)
    scene:Show()
    AliasScene(box.mock, scene:Frame())
    local runtimeSpec = scene:Frame().MSUFSpec
    st.runtimeSpec = runtimeSpec
    st.runtimePower = runtimeSpec and runtimeSpec.power
    st.runtimeStatus = runtimeSpec and runtimeSpec.status
    st.runtimeText = runtimeSpec and runtimeSpec.text
    st.runtimeClassPower = runtimeSpec and runtimeSpec.classPower
    box.key = key
    if Deps.SyncLiveStateDriver then Deps.SyncLiveStateDriver(box, key) end
    if panel and panel._msufRefreshUnitTextControls and not SKIP_CONTROL_REFRESH_REASONS[reason] and not box._refreshingControls then
        box._refreshingControls = true
        panel._msufRefreshUnitTextControls()
        if panel._msufRefreshUnitPortraitControls then panel._msufRefreshUnitPortraitControls() end
        if panel._msufRefreshUnitPowerControls then panel._msufRefreshUnitPowerControls() end
        box._refreshingControls = nil
    end
    if box.title then box.title:SetText(Deps.TR("Unit Frame Preview") .. " - " .. Deps.TR(UNIT_LABELS[key] or key)) end
    for i = 1, #STAGE_DEP_FIELDS do
        local name = STAGE_DEP_FIELDS[i]
        st[name] = Deps[name]
    end
    st.UNIT_DATA, st.conf, st.data, st.g, st.key = UNIT_DATA, conf, data, g, key
    return true
end

local RequireFields = MenuState.PreviewContracts.RequireFields
local Layout = RequireFields("UnitPreview.Layout", MSUF.UFPreviewLayout, "Install")
local Presentation = RequireFields("UnitPreview.Presentation", MSUF.UFPreviewPresentation, "Install")
Layout.Install(Stage, { AnimatedPreviewData = AnimatedPreviewData, PreviewLayerWanted = PreviewLayerWanted,
    RefillTable = RefillTable, BodyAliases = BODY_ALIASES, StatusRegions = STATUS_REGIONS, Empty = EMPTY })
Presentation.Install(Stage, { PreviewLayerWanted = PreviewLayerWanted, ClassPowerWidth = Layout.ClassPowerWidth })

--- Install render helpers onto the shared unit-preview object. View owns frame
--- construction; this module owns repeated visual composition.
-- Render.Install fills the shared render state in these stages, in order;
-- s carries the preview object, its deps, the render state and the values a
-- later stage reads.
local InstallStage = {}
function InstallStage.Refreshers(s)
    local Preview = s.Preview

    --- Hot refresh for the unit preview. It composes current DB/model values into
    --- mock regions and handle positions, but never mutates live unit frames. The
    --- per-refresh state table is the box's scene: refilled, never reallocated,
    --- and kept for the animation tick.
    function Preview.Refresh(box, reason)
        box = box or Preview.active
        if not box or not box:IsShown() then return end
        local Deps = Preview.RefreshDeps
        if Deps.PreviewInCombat() then return end
        local st = box._msufPreviewScene
        if st then
            for field in pairs(st) do st[field] = nil end
        else
            st = {}
            box._msufPreviewScene = st
        end
        st.box, st.reason, st.D, st.R = box, reason, Deps, Deps._RenderState or {}
        st.complete = nil
        if Stage.ResolveInputs(st) == false then return end
        Stage.ResolveFrameGeometry(st)
        Stage.ResolvePowerGeometry(st)
        Stage.MeasureTextFootprint(st)
        Stage.MeasureLayerFootprint(st)
        Stage.ResolveScaleAndLevels(st)
        Stage.RenderClassPower(st)
        Stage.RenderCastbar(st)
        Stage.RenderSceneHandles(st, Preview)
        Stage.RenderArenaTrinket(st)
        Stage.FinalizeLayersAndHandles(st)
        st.complete = true
    end

    --- Animation tick: fills, value texts, cast progress and aura timers and
    --- swipes follow the animation clock on the scene the last full refresh built. Geometry, textures, fonts, handles and layer state
    --- stay as that refresh placed them, so a tick reads no settings and creates
    --- nothing. Returns false when there is no complete scene to animate; the
    --- caller then runs a full refresh.
    function Preview.RefreshAnimation(box)
        box = box or Preview.active
        local st = box and box._msufPreviewScene
        if not (st and st.complete == true and st.box == box and box._animationEnabled == true) then return false end
        if not (box.IsShown and box:IsShown()) or st.key ~= box.key then return false end
        if st.D.PreviewInCombat() then return true end
        local data, powerFrac, animState = AnimatedPreviewData(st, st.baseData, st.basePowerFrac)
        if not animState then return false end
        st.data, st.powerFrac, st.animState = data, powerFrac, animState
        box._unitSceneRoot:SetClock(box._animationElapsed)
        Stage.AnimateClassPower(st)
        Stage.PlaceValueTextHandles(st)
        if box._msufMenuTextFocus then st.R.ApplyPreviewTextFocus(box, st.canvas, st.mock) end
        if st.castPreviewVisible and box._castScene then
            local tick = box._castTick
            tick.progress, tick.duration = animState.castPct, animState.castDuration
            box._castScene:Tick(tick)
            PlaceCastTimeHandle(st)
        end
        return true
    end
end
local function ClampUnitPreviewSize(w, h)
    local b = UnitFrameSizeBounds
    local minW, maxW = tonumber(b.minW) or 40, tonumber(b.maxW) or 800
    local minH, maxH = tonumber(b.minH) or 8, tonumber(b.maxH) or 200
    if w < minW then w = minW elseif w > maxW then w = maxW end
    if h < minH then h = minH elseif h > maxH then h = maxH end
    return w, h
end
function Render.Install(Preview, deps)
    if type(Preview) ~= "table" then return end
    deps = deps or Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    local renderState = PickFallbackTable(deps, UNIT_RENDER_FALLBACKS, [[
        RuntimeAppliedPortraitSizeForPreviewKey DetachedCastbarOffsetForPreviewKey RuntimeVisualScaleForPreviewKey
        RuntimeCastbarVisualScaleForPreviewKey ClampPreviewZoom ResolveDefaultPreviewZoomLock UpdatePreviewZoomControls
        CastbarShowIcon CastbarShowText ReadCastbarNum
        TextScopeGet ]])
    renderState.ZOOM_MIN = tonumber(deps.ZOOM_MIN) or 0.35
    --- Mock body clamp = the shared legal size range every conf.width/height
    --- writer enforces (State/MSUF_Defaults.lua exports it; the EM2 popup
    --- clamps writes against the same table). Clamping the mock any narrower
    --- makes the preview lie about tall/narrow frames â€” and every
    --- frame-relative offset (status icons, drag targets) with it.
    renderState.ClampUnitPreviewSize = ClampUnitPreviewSize
    renderState.UnitPreviewPortraitTexture = deps.UnitPreviewPortraitTexture
    renderState.ClassPortraitVisual = deps.ClassPortraitVisual
    renderState.STATUS_RUNTIME_KEYS = {
        raidmarker = "raidMarker", leader = "leader", assist = "assist", level = "level",
        raceText = "race", classText = "classText",
        elite = "elite", statusText = "statusDeadText", statusGhostText = "statusGhostText",
        statusAFKText = "statusAFKText", statusDNDText = "statusDNDText",
        statusCombat = "combat", statusResting = "resting",
        statusIncomingRes = "incomingRes", statusPvp = "pvp",
        statusPetHappiness = "petHappiness", statusThreat = "threat",
        statusPetXP = "petXP",
    }
    renderState.ApplyPreviewTextFocus = deps.ApplyPreviewTextFocus or UNIT_RENDER_FALLBACKS.ApplyPreviewTextFocus
    local s = { Preview = Preview, deps = deps, renderState = renderState }
    deps._RenderState = renderState
    InstallStage.Refreshers(s)
end
