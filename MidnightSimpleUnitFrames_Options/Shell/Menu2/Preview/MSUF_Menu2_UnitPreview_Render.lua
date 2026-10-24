--- Unit preview render/composition.
---
--- The view file builds frames and wires controls; this module owns the hot
--- refresh path that composes the live preview visuals.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF
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
local EnsureDB = MenuState.EnsureDB
local PickFallbackTable = MenuState.PickFallbackTable
local Fallbacks = MenuState.Fallbacks or {}
local PreviewHelpers = MenuState.PreviewHelpers or {}
local CPPreview = MenuState.ClassPowerPreview or {}

local Layers = MSUF.UF and MSUF.UF.Layers or {}
local floor, min, max = math.floor, math.min, math.max
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
-- Read-only stand-in for a scene table the scene has not built.
local EMPTY = {}
-- The animation tick builds its frame state through this export when the module table lacks it.
local BuildPreviewAnimationFrameState = MSUF.Require("MSUF_BuildPreviewAnimationFrameState", FILE)
-- The core font recipe and the unit frame size bounds, resolved once: every preview
-- refresh sets fonts and clamps the size, and their providers load with the core.
local GetGlobalFontSettings = MSUF.Require("MSUF_GetGlobalFontSettings", FILE)
local GetFontPath = MSUF.Require("MSUF_GetFontPath", FILE)
local GetFontFlags = MSUF.Require("MSUF_GetFontFlags", FILE)
local FontPathForKey = MSUF.Require("MSUF_ResolveFontKeyPath", FILE)
local ResolveSafeFontPath = MSUF.Require("MSUF_ResolveSafeFontPath", FILE)
local SetFontChecked = MSUF.Require("MSUF_SetFontChecked", FILE)
local ResolveFontShadowMetrics = MSUF.Require("MSUF_ResolveFontShadowMetrics", FILE)
local UnitFrameSizeBounds = MSUF.Require("MSUF_UnitFrameSizeBounds", FILE)

-- Preview scale and resolved FULL extents are inputs to the runtime painter.


local function ResolvePreviewBodyOffsets(centerX, centerY, scale, manualZoom, frozenX, frozenY)
    if frozenX ~= nil and frozenY ~= nil then return frozenX, frozenY end
    -- Fit mode centers the complete configured footprint. At a manual zoom,
    -- keep the unit body as the stable focal point instead: valid auxiliary
    -- layouts can sit hundreds of pixels away and must not exile the body from
    -- the canvas. Explicit canvas pan is applied separately below.
    if manualZoom ~= nil then return 0, 0 end
    scale = tonumber(scale) or 1
    return -floor(((tonumber(centerX) or 0) * scale) + 0.5),
        -floor(((tonumber(centerY) or 0) * scale) + 0.5)
end
Render.ResolvePreviewBodyOffsets = ResolvePreviewBodyOffsets
-- The settings section that owns each sample-effect layer: it switches the layer on while it is open.
Render.SAMPLE_LAYER_SECTIONS = { dispelOverlay = "unit_dispel_overlay", dispelSymbol = "unit_dispel_symbol" }

-- The container width is the live class resource layout's rule (player frame
-- width, custom width, pip auto-fit, Cooldown Manager viewer), shared with the
-- Class Resources page preview; only the canvas clamp is this preview's own.
local function PreviewClassPowerWidth(bars, frameW, cpH, segCount)
    local w = tonumber(CPPreview.ContainerWidth(bars, frameW, cpH, segCount)) or frameW
    if w < 1 then w = 1 elseif w > 800 then w = 800 end
    return w
end
local ResolvePreviewPowerShape = CPPreview.ResolvePowerShape
local function Clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end
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

--- The fourth return is true when the colour follows the health value, so the
--- animation tick knows to repaint it. The ramp is the live one: the gradient
--- stops of the compiled health spec, interpolated by the engine's own rule.
-- Reused argument of Portrait.BorderColor, which reads only the style.
local function PreviewLiveFrame(key)
    local uf = MSUF.UF
    local unit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    local frame = uf.GetFrame and uf.GetFrame(unit) or nil
    if not frame then frame = uf.frames and uf.frames[unit] or nil end
    return frame
end
--- Whether a status indicator shows in the preview: the compiled runtime
--- switch when there is one (PvP also previews while only its context is
--- off), otherwise the stored or default switch. Units the indicator does
--- not support never show it; outside "all" mode only the selected one does.
local function PreviewLivePowerBar(key)
    local frame = PreviewLiveFrame(key)
    return frame and (frame.targetPowerBar or frame.powerBar or frame.Power) or nil
end
local function UnitPreviewAnimationState(box, index, key)
    if not (box and box._animationEnabled == true) then return nil end
    local previewAnimation = MSUF.PreviewAnimation
    local buildState = previewAnimation and previewAnimation.BuildFrameState or BuildPreviewAnimationFrameState
    local scratch = box._previewAnimationState
    if not scratch then
        scratch = {}
        box._previewAnimationState = scratch
    end
    return buildState(box, index, key, scratch, box._animationElapsed)
end
local function PointCoord(point, w, h)
    point = tostring(point or "CENTER"):upper()
    local x = (point:find("RIGHT", 1, true) and w) or (point:find("LEFT", 1, true) and 0) or (w * 0.5)
    local y = (point:find("TOP", 1, true) and h) or (point:find("BOTTOM", 1, true) and 0) or (h * 0.5)
    return x, y
end
local function ExpandRect(minX, maxX, minY, maxY, left, bottom, right, top)
    if not (left and bottom and right and top) then return minX, maxX, minY, maxY end
    return min(minX, left), max(maxX, right), min(minY, bottom), max(maxY, top)
end
local function ExpandAnchoredRect(minX, maxX, minY, maxY, point, relPoint, x, y, rw, rh, targetW, targetH)
    rw, rh = tonumber(rw) or 1, tonumber(rh) or 1
    local tx, ty = PointCoord(relPoint or point, tonumber(targetW) or 0, tonumber(targetH) or 0)
    local px, py = PointCoord(point, rw, rh)
    local left = tx + (tonumber(x) or 0) - px
    local bottom = ty + (tonumber(y) or 0) - py
    return ExpandRect(minX, maxX, minY, maxY, left, bottom, left + rw, bottom + rh)
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
    GradientPreviewColor = Fallbacks.HealthRGB, PowerColor = Fallbacks.PowerRGB, FontColor = Fallbacks.WhiteRGB,
    TextScopeGet = Fallbacks.Nil, ApplyPreviewTextFocus = Fallbacks.Noop,
}

--- The castbar slot paints the engine's castbar scene (root:Castbar), so every look setting is read the way the
--- live castbar reads it. This file sizes and places the slot, feeds the sample and fits the handles.
local CAST_SCENE_UNIT = { boss = "boss1", arena = "arena1" }
local CAST_SAMPLE_NAMES = { boss = "Celestial Ruin", arena = "Greater Pyroblast" }
local CAST_KICK_RECOVERY = { 0.4 }
local CAST_PROGRESS = 0.70
local CAST_DURATION = 2.0
-- One-region lists for the handle placer, kept on the region itself.
local function RegionList(region)
    local list = region._msufPreviewRegionList
    if not list then
        list = { region }
        region._msufPreviewRegionList = list
    end
    return list
end
local function CastbarShowTime(key, g)
    return key == "boss" and g.showBossCastTime ~= false
        or (key == "arena" and g.showArenaCastTime ~= false)
        or (key == "target" and g.showTargetCastTime ~= false)
        or (key == "focus" and g.showFocusCastTime ~= false)
        or (key == "player" and g.showPlayerCastTime ~= false)
end
local function CastbarShowTargetName(key, g)
    return (key == "target" and g.castbarTargetShowTargetName == true)
        or (key == "focus" and g.castbarFocusShowTargetName == true)
        or (key == "boss" and g.showBossCastTargetName == true)
        or (key == "arena" and g.showArenaCastTargetName == true)
end
-- The GCD strip: status bar, background, spell and time texts and the spell icon.
-- The GCD owner supplies both the detached surface and the ordinary player
-- castbar surface. Only placement/fitting belongs to this workbench.
local function ApplyGcdSample(mock, canvas, g, key, width, height, S, scale)
    local samples = mock.cast._featureSamples
    if not samples then samples = {} mock.cast._featureSamples = samples end
    if key ~= "player" or g.showGCDBar ~= true then
        if samples.gcd then samples.gcd:Hide() end
        return
    end
    local runtime = MSUF.Castbars.GCD
    local detached = g.gcdBarDetached == true
    local field = detached and "gcdDetached" or "gcdAttached"
    local gcd = samples[field]
    if samples.gcd then samples.gcd:Hide() end
    if not gcd then gcd = runtime.CreateSurface(canvas, detached) samples[field] = gcd end
    samples.gcd = gcd
    if detached then runtime.LayoutSurface(gcd, g, canvas)
    else gcd:SetSize(width / scale, height / scale) end
    gcd:SetScale(scale)
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local w, h = gcd:GetWidth() * scale, gcd:GetHeight() * scale
    local x = detached and (cw * .5 + S(tonumber(g.gcdBarX) or 0) - w * .5) or S(12)
    local y = detached and (ch * .5 + S(tonumber(g.gcdBarY) or -180) - h * .5) or S(8)
    gcd:ClearAllPoints()
    gcd:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", max(S(12), min(cw - w - S(12), x)) / scale,
        max(S(8), min(ch - h - S(8), y)) / scale)
    runtime.PaintSample(gcd, g)
end

-- Everything below that the 20 Hz animation tick reaches (the text handle placers) stays inline: no helper or
-- wrapper call per tick beyond the region list and option getters.
local function CastHandleOptions(box, scale)
    local opts = box._msufCastHandleOptions
    if not opts then
        opts = { fitText = true, useScaledRect = true }
        box._msufCastHandleOptions = opts
    end
    opts.coordinateScale = scale
    return opts
end
--- A text handle around the scene's FontString as it reads now: the refresh and the animation tick (the cast time
--- counts) share it.
local function PlaceCastTextHandle(st, handle, region, shown, minWidth)
    if not (shown and region and region:IsShown()) then
        handle:Hide()
        return
    end
    local max = st.max
    handle:SetSize(max(minWidth, region:GetStringWidth() + 10), max(18, region:GetStringHeight() + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(handle, st.canvas, RegionList(region), 3,
        CastHandleOptions(st.box, st.box._castHandleScale)) then st.PlaceHandle(handle, region) end
end
local function PlaceCastTimeHandle(st)
    local frame = st.box._castScene and st.box._castScene:Frame()
    if frame then PlaceCastTextHandle(st, st.box.handleCastbarTime, frame.timeText, CastbarShowTime(st.key, st.g), 28) end
end
--- Icon, spell, target and time handles follow the scene's own regions; the castbar handle follows the slot.
local function PlaceCastbarHandles(st, frame)
    local box, g, key = st.box, st.g, st.key
    local scale = st.scale * (box._mockCastFrameScale or 1)
    box._castHandleScale = scale
    local icon = frame.icon
    if st.R.CastbarShowIcon(key, g) and icon:IsShown() then
        box.handleCastbarIcon:SetSize(max(18, icon:GetWidth() * scale + 8), max(18, icon:GetHeight() * scale + 8))
        st.PlaceHandle(box.handleCastbarIcon, icon)
    else
        box.handleCastbarIcon:Hide()
    end
    PlaceCastTextHandle(st, box.handleCastbarText, frame.castText, st.R.CastbarShowText(key, g), 34)
    PlaceCastTextHandle(st, box.handleCastbarTarget, frame.castTargetText, CastbarShowTargetName(key, g), 48)
    PlaceCastTimeHandle(st)
end
-- The Class Resources page previews the picked resource; every other page shows a generic five-pip bar.
local GENERIC_CLASS_POWER_SPEC = { key = "generic", mode = "segmented", segments = 5, value = 3, specIndex = 1, class = "ROGUE" }

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
    "TR", "PortraitStyleGet", "max", "min", "abs", "floor", "format", "TEX_W8", "ApplyPreviewFont", "CastbarEnabled",
    "ReadCastbarSize", "CastbarOffsetFields", "CastbarDetached", "CanDetachPowerBarKey", "ClampPreviewLayer", "SetTex",
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

--- Canvas size, frame size, portrait side/placement/size/border and castbar
--- size/offsets, plus the boss border inset.
function Stage.ResolveFrameGeometry(st)
    local box, conf, g, key, runtimeSpec = st.box, st.conf, st.g, st.key, st.runtimeSpec
    local RenderState, PortraitStyleGet, max, Auras = st.R, st.PortraitStyleGet, st.max, st.Auras
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth)
        or ((key == "boss" or key == "arena") and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight)
        or ((key == "boss" or key == "arena") and 30 or (key == "focus" and 30 or 40))
    w, h = RenderState.ClampUnitPreviewSize(w, h)
    local pspec = runtimeSpec and runtimeSpec.portrait
    local mode = (pspec and pspec.side) or conf.portraitMode
    local hasPortrait
    if pspec then
        hasPortrait = pspec.enabled == true
    else
        hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    end
    box._runtimeDefensivePortraitPositionOnly = not hasPortrait
        and Auras and Auras.WantsDefensivePortraitAnchor
        and Auras.WantsDefensivePortraitAnchor(key, runtimeSpec) == true
        or false
    local showsPortrait = hasPortrait or box._runtimeDefensivePortraitPositionOnly
    if showsPortrait and mode ~= "RIGHT" then mode = "LEFT" end
    local pSize = showsPortrait
        and (tonumber(pspec and pspec.size) or tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0)
        or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    -- Placement/geometry mirrors of the live spec. Parked on the box because the
    -- later stages (portrait, power bar, overlays) read them from there.
    box._runtimePortraitPlacement = (pspec and pspec.placement) or PortraitStyleGet(key, "portraitPlacement", "ATTACHED") or "ATTACHED"
    box._runtimePortraitPoint = (pspec and pspec.point) or PortraitStyleGet(key, "portraitDetachedPoint", "RIGHT") or "RIGHT"
    box._runtimePortraitRelPoint = (pspec and pspec.relPoint) or PortraitStyleGet(key, "portraitDetachedTo", "LEFT") or "LEFT"
    box._runtimePortraitOverlayAlign = (pspec and pspec.overlayAlign) or PortraitStyleGet(key, "portraitOverlayAlign", "LEFT") or "LEFT"
    box._runtimePortraitAlpha = tonumber(pspec and pspec.alpha) or ((tonumber(PortraitStyleGet(key, "portraitAlpha", 100)) or 100) / 100)
    box._runtimePortraitW = tonumber(pspec and pspec.width) or (tonumber(PortraitStyleGet(key, "portraitWidth", 0)) or 0)
    box._runtimePortraitH = tonumber(pspec and pspec.height) or (tonumber(PortraitStyleGet(key, "portraitHeight", 0)) or 0)
    if box._runtimePortraitW <= 0 then box._runtimePortraitW = pSize end
    if box._runtimePortraitH <= 0 then box._runtimePortraitH = pSize end
    -- Auto size (Size override = 0) is resolved by the live Portrait element.
    -- Edit Mode displays that applied holder, so consume the same final geometry
    -- instead of letting Menu2 maintain a second approximation of the auto path.
    if (pspec and pspec.sizeMode) == "SEPARATE"
        or (tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) <= 0
    then
        local appliedW, appliedH = RenderState.RuntimeAppliedPortraitSizeForPreviewKey(key)
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = appliedW, appliedH
        if tonumber(appliedW) and appliedW > 0 then box._runtimePortraitW = appliedW end
        if tonumber(appliedH) and appliedH > 0 then box._runtimePortraitH = appliedH end
    else
        box._runtimeAppliedPortraitW, box._runtimeAppliedPortraitH = nil, nil
    end
    local border = pspec and pspec.border
    box._runtimePortraitBorderStyle = (border and border.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE") or "NONE"
    box._runtimePortraitBorderThickness = 0
    box._runtimePortraitBorderFill = false
    if hasPortrait and box._runtimePortraitBorderStyle ~= "NONE" then
        box._runtimePortraitBorderThickness = max(1, tonumber(border and border.thickness)
            or tonumber(PortraitStyleGet(key, "portraitBorderThickness", 2)) or 2)
        box._runtimePortraitBorderFill = (border and border.fill == true)
            or (not border and PortraitStyleGet(key, "portraitFillBorder", false) == true)
    end
    local castbarSpec = runtimeSpec and runtimeSpec.castbar
    local castEnabled = castbarSpec and castbarSpec.enabled == true
    if not castbarSpec then castEnabled = st.CastbarEnabled(key, g) end
    if box._msuf2ColorPainterForceCastbar == true then castEnabled = true end
    local castW, castBarH = st.ReadCastbarSize(key, g, w, (key == "boss" or key == "arena") and 12 or 18)
    local castXKey, castYKey, castDefX, castDefY = st.CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and st.CastbarDetached(key, g)
    -- Projected position of a detached castbar, from the live layout.
    box._detachedCastProjectedX, box._detachedCastProjectedY = nil, nil
    if castDetached and RenderState.DetachedCastbarOffsetForPreviewKey then
        box._detachedCastProjectedX, box._detachedCastProjectedY = RenderState.DetachedCastbarOffsetForPreviewKey(key)
        if tonumber(box._detachedCastProjectedX) and tonumber(box._detachedCastProjectedY) then
            castOffsetX, castOffsetY = box._detachedCastProjectedX, box._detachedCastProjectedY
        end
    end
    box._bossBorderInset = 0
    if (key == "boss" or key == "arena")
        and runtimeSpec and runtimeSpec.border
        and runtimeSpec.border.enabled == true
    then
        box._bossBorderInset = max(1, st.floor((tonumber(runtimeSpec.border.thickness) or 1) + 0.5))
    end
    box._bossCastbarGap = 3
    st.canvas, st.cw, st.ch, st.w, st.h, st.mode, st.hasPortrait = canvas, cw, ch, w, h, mode, hasPortrait
    st.castEnabled, st.castDetached, st.castPreviewVisible = castEnabled, castDetached, castEnabled and PreviewLayerWanted(box, "castbar")
    st.castW, st.castBarH, st.castOffsetX, st.castOffsetY = castW, castBarH, castOffsetX, castOffsetY
end

--- Class power preview spec, embedded/attached/detached power bar geometry,
--- combat animation state and the detached bar width/height.
function Stage.ResolvePowerGeometry(st)
    local box, conf, key, w, max = st.box, st.conf, st.key, st.w, st.max
    local runtimePower, runtimeClassPower, data = st.runtimePower, st.runtimeClassPower, st.data
    local isPlayer = key == "player"
    local bars = EnsureDB().bars or {}
    local classPowerPreviewSpec
    if isPlayer then
        local menu = MSUF.MSUF2 or MenuState
        if menu.activeKey == "classpower" and menu.GetClassPowerPreviewSpec then
            classPowerPreviewSpec = menu.GetClassPowerPreviewSpec()
        end
    end
    if classPowerPreviewSpec then
        local getClassToken = MenuState.GetClassPowerPreviewClassToken
        local previewClass = getClassToken and getClassToken() or nil
        previewClass = previewClass or classPowerPreviewSpec.classToken or classPowerPreviewSpec.class
        if previewClass and data.class ~= previewClass then
            local copy = RefillTable(box._msufPreviewClassData or {}, data)
            box._msufPreviewClassData = copy
            copy.class = tostring(previewClass):upper()
            data = copy
        end
    end
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = st.D.ReadPowerBarEnabled(conf, key) end
    local detachedPower = st.CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true)
        or (runtimePower == nil and conf.powerBarDetached == true))
    box._runtimePowerEmbedded = powerAllowed and not detachedPower and (
        (runtimePower and runtimePower.embed ~= false)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == true)
        or (runtimePower == nil and conf.embedPowerBarIntoHealth == nil and bars.embedPowerBarIntoHealth ~= false)
    ) or false
    box._runtimePowerAttached = powerAllowed and not detachedPower and box._runtimePowerEmbedded ~= true
    box._runtimeHealthPowerInset = box._runtimePowerEmbedded == true
        and max(0, tonumber(runtimePower and runtimePower.height) or tonumber(st.ReadPowerBarHeight(conf)) or 0)
        or 0
    local classPowerOn = isPlayer and runtimeClassPower and runtimeClassPower.enabled == true or false
    if isPlayer and runtimeClassPower == nil then classPowerOn = bars.showClassPower ~= false end
    if classPowerPreviewSpec then
        classPowerOn = bars.showClassPower ~= false and classPowerPreviewSpec.enabled ~= false
            and classPowerPreviewSpec.mode ~= "none"
    end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and not isPlayer and data.live ~= true then powerFrac = 1 end
    powerFrac = Clamp01(powerFrac)
    -- The animation tick rebuilds the animated data from these two.
    st.baseData, st.basePowerFrac = data, powerFrac
    local animState
    data, powerFrac, animState = AnimatedPreviewData(st, data, powerFrac)
    local displayPowerToken = box._playerManaSourcePreviewActive and "MANA" or data.powerToken
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local cpSpec = classPowerPreviewSpec or GENERIC_CLASS_POWER_SPEC
    local classPowerSegCount = CPPreview.SegmentCount(cpSpec)
    box._runtimeClassPowerW = classPowerOn and PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount) or 0
    -- Augmentation no longer builds a composite surface: Ebon Might is rendered
    -- by the ordinary Player Power bar and Essence stays an ordinary Class
    -- Resource, so there is no second class row and no shared geometry. Only the
    -- power bar's *content* changes, which the render pass reads from
    -- _runtimePowerEbonMight below.
    box._runtimeClassPowerSecondarySpec = classPowerPreviewSpec and classPowerPreviewSpec.secondaryTimer
    box._runtimePowerEbonMight = isPlayer
        and classPowerOn
        and type(box._runtimeClassPowerSecondarySpec) == "table"
        and not box._playerManaSourcePreviewActive
        and bars.showEbonMight ~= false
        and classPowerPreviewSpec and classPowerPreviewSpec.key == "evoker_augmentation_ebon" or false
    box._runtimeDetachedPowerSyncClass = isPlayer and ((runtimePower and runtimePower.detachedSyncClass == true)
        or (runtimePower == nil and conf.detachedPowerBarSyncClassPower ~= false)) or false
    box._runtimeDetachedPowerX = tonumber(runtimePower and runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
    box._runtimeDetachedPowerY = tonumber(runtimePower and runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
    box._runtimeDetachedPowerAnchorMode = tostring((runtimePower and runtimePower.detachedAnchorMode)
        or conf.detachedPowerBarAnchorMode or "CENTER"):upper()
    box._runtimeDetachedPowerAnchorClass = isPlayer and ((runtimePower and runtimePower.detachedAnchorClass == true)
        or (runtimePower == nil and conf.detachedPowerBarAnchorToClassPower == true))
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true)
        or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    box._runtimeDetachedPowerShape = isPlayer
        and ResolvePreviewPowerShape((runtimePower and runtimePower.shape) or conf.detachedPowerBarShape or "FOLLOW_CLASS", bars.classPowerShape)
        or "BAR"
    local resolveDetachedPowerWidth = CPPreview.ResolveDetachedPowerWidth
    if detachedPower and resolveDetachedPowerWidth then
        box._runtimeDetachedPowerW = resolveDetachedPowerWidth({
            -- The live replacement resolver deliberately avoids ClassPower as
            -- both width and anchor input: ClassPower itself consumes this
            -- carrier.  Avoid the preview helper's live/class shortcuts too.
            liveFrame = PreviewLiveFrame(key),
            livePower = runtimePower,
            shape = box._runtimeDetachedPowerShape,
            orbSize = (runtimePower and runtimePower.orbSize) or conf.detachedPowerOrbSize,
            syncClass = box._runtimeDetachedPowerSyncClass,
            classWidth = classPowerOn and box._runtimeClassPowerW or nil,
            classFallbackWidth = (runtimePower and runtimePower.detachedClassWidth) or (w - 4),
            widthFrameName = runtimePower and runtimePower.detachedWidthFrameName,
            widthMode = bars.detachedPowerBarWidthMode,
            manualWidth = (runtimePower and runtimePower.detachedWidth) or conf.detachedPowerBarWidth,
            explicitWidth = (runtimePower and runtimePower.detachedWidthExplicit) or tonumber(conf.detachedPowerBarWidth),
            frameWidth = w,
            relativeTo = PreviewLivePowerBar(key),
        })
    else
        box._runtimeDetachedPowerW = tonumber(runtimePower and runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or w
    end
    local detachedH = detachedPower
        and (tonumber(runtimePower and runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    if detachedPower and box._runtimeDetachedPowerShape == "ORB" then
        local orbSize = tonumber(runtimePower and runtimePower.orbSize) or tonumber(conf.detachedPowerOrbSize) or 54
        if orbSize < 20 then orbSize = 20 elseif orbSize > 160 then orbSize = 160 end
        box._runtimeDetachedPowerW = orbSize
        detachedH = orbSize
    end
    local detachedPowerManagedByClassPreview = detachedPower and isPlayer and box._runtimeDetachedPowerAnchorClass == true
    local detachedPowerInUnitPreview = detachedPower and not detachedPowerManagedByClassPreview
    local wideW = w
    if classPowerOn and PreviewLayerWanted(box, "classPower") then wideW = max(wideW, box._runtimeClassPowerW or w) end
    if detachedPowerInUnitPreview and PreviewLayerWanted(box, "power") then wideW = max(wideW, box._runtimeDetachedPowerW) end
    st.cpSpec, st.cpClass = cpSpec, classPowerPreviewSpec and MenuState.GetClassPowerPreviewClassToken() or cpSpec.class
    st.animState, st.bars, st.data, st.powerFrac, st.displayPowerToken = animState, bars, data, powerFrac, displayPowerToken
    st.classPowerOn, st.classPowerPreviewSpec, st.classPowerSegCount, st.cpH = classPowerOn, classPowerPreviewSpec, classPowerSegCount, cpH
    st.detachedPower, st.detachedH, st.wideW = detachedPower, detachedH, wideW
    st.detachedPowerInUnitPreview, st.detachedPowerManagedByClassPreview = detachedPowerInUnitPreview, detachedPowerManagedByClassPreview
end

-- The scene has already laid out its regions. Measure the real glyphs and anchors for fit, including name-relative
-- status texts, rather than formatting a second set of mock strings.
local function RegionRect(region, frame)
    if region == frame then return 0, 0, frame:GetWidth(), frame:GetHeight() end
    local point, relative, relPoint, x, y = region:GetPoint(1)
    if not point or not relative or relative == region then return 0, 0, 0, 0 end
    local left, bottom, rw, rh = RegionRect(relative, frame)
    local px, py = PointCoord(relPoint or point, rw, rh)
    local width, height = region:GetWidth(), region:GetHeight()
    if region.GetStringWidth then width, height = region:GetStringWidth(), region:GetStringHeight() end
    local ox, oy = PointCoord(point, width, height)
    return left + px - ox + (x or 0), bottom + py - oy + (y or 0), width, height
end
-- Scene tables of host frames (aura hosts, texture layers) that expand the fit rectangle as well.
local FOOTPRINT_HOST_FIELDS = { "_msufGFFrameAuraPreviewHosts", "_msufTexLayers" }
--- Footprint pass one: name, health/power text slots, status indicators and
--- the boss target marker expand the fit rectangle. Each shown region grows it
--- by its measured rect; the test is inline because every refresh runs it.
function Stage.MeasureTextFootprint(st)
    local body = st.box.mock._body
    local minX, maxX, minY, maxY = 0, st.w, 0, st.h
    for _, field in pairs(BODY_ALIASES) do
        local region = body[field]
        if region and region.IsShown and region:IsShown() then
            local x, y, w, h = RegionRect(region, body)
            minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
        end
    end
    for _, field in pairs(STATUS_REGIONS) do
        local region = body[field]
        if region and region.IsShown and region:IsShown() then
            local x, y, w, h = RegionRect(region, body)
            minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
        end
    end
    for i = 1, #FOOTPRINT_HOST_FIELDS do
        for _, host in pairs(body[FOOTPRINT_HOST_FIELDS[i]] or EMPTY) do
            if host and host.IsShown and host:IsShown() then
                local x, y, w, h = RegionRect(host, body)
                minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
            end
        end
    end
    local marker = body._msufBossTargetIndicator
    if marker and marker.IsShown and marker:IsShown() then
        local x, y, w, h = RegionRect(marker, body)
        minX, maxX, minY, maxY = ExpandRect(minX, maxX, minY, maxY, x, y, x + w, y + h)
    end
    st.minX, st.maxX, st.minY, st.maxY = minX, maxX, minY, maxY
end

-- Class resource container origin and width in unit body coordinates (the live ClassPower layout rule).
local function ClassPowerContainerRect(st)
    local bars = st.bars
    local cpW = st.box._runtimeClassPowerW or PreviewClassPowerWidth(bars, st.w, st.cpH, st.classPowerSegCount)
    return CPPreview.ContainerInsetX(bars) + (tonumber(bars.classPowerOffsetX) or 0),
        st.h - 2 - st.cpH + (tonumber(bars.classPowerOffsetY) or 0), cpW
end
local function PowerBarFootprintHeight(st)
    local runtimePower = st.runtimePower
    return tonumber(runtimePower and runtimePower.height) or st.ReadPowerBarHeight(st.conf)
end
-- |castbar setting| read the way the live castbar reads it; an unset value reads as the default.
local function CastNumAbs(st, field, bossField, default)
    return st.abs(st.R.ReadCastbarNum(st.g, st.key, field, bossField, default) or default)
end
-- The castbar slot, its icon, texts and target name expand the fit rectangle.
local function CastbarFootprint(st, minX, maxX, minY, maxY)
    local box, key, w, h = st.box, st.key, st.w, st.h
    local castW, castBarH, castOffsetX, castOffsetY = st.castW, st.castBarH, st.castOffsetX, st.castOffsetY
    local cLeft, cBottom
    if st.castDetached then
        cLeft = (w - castW) * 0.5 + castOffsetX
        cBottom = (h - castBarH) * 0.5 + castOffsetY
    elseif key == "player" then
        cLeft = (w - castW) * 0.5 + castOffsetX
        cBottom = h + castOffsetY
    elseif key == "boss" or key == "arena" then
        cLeft = castOffsetX - box._bossBorderInset
        cBottom = castOffsetY - box._bossBorderInset - box._bossCastbarGap - castBarH
            + (box._runtimePowerEmbedded == true and PowerBarFootprintHeight(st) or 0)
    else
        cLeft = castOffsetX
        cBottom = h + castOffsetY
    end
    local showTargetName = CastbarShowTargetName(key, st.g)
    local targetPadX = showTargetName and (CastNumAbs(st, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0) + 96) or 0
    local targetPadY = showTargetName and (CastNumAbs(st, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1) + 24) or 0
    local iconSize = CastNumAbs(st, "IconSize", "bossCastIconSize", castBarH)
    local detailPadX = st.max(
        CastNumAbs(st, "IconOffsetX", "bossCastIconOffsetX", 0) + iconSize,
        CastNumAbs(st, "TextOffsetX", "bossCastTextOffsetX", 0) + 80,
        CastNumAbs(st, "TimeOffsetX", "bossCastTimeOffsetX", 0) + 46,
        targetPadX
    )
    local detailPadY = st.max(
        CastNumAbs(st, "IconOffsetY", "bossCastIconOffsetY", 0) + iconSize,
        CastNumAbs(st, "TextOffsetY", "bossCastTextOffsetY", 0) + 24,
        CastNumAbs(st, "TimeOffsetY", "bossCastTimeOffsetY", 0) + 24,
        targetPadY
    )
    return st.min(minX, cLeft - detailPadX), st.max(maxX, cLeft + castW + detailPadX),
        st.min(minY, cBottom - detailPadY), st.max(maxY, cBottom + castBarH + detailPadY)
end

--- Footprint pass two: the class resource, power bars, castbar, arena trinket, aura lanes and dispel pieces expand
--- the fit rectangle; any of them being visible also widens the fit margin.
function Stage.MeasureLayerFootprint(st)
    local box, key, w, h, min, max = st.box, st.key, st.w, st.h, st.min, st.max
    local minX, maxX, minY, maxY, wideW = st.minX, st.maxX, st.minY, st.maxY, st.wideW
    local runtimeSpec, Auras = st.runtimeSpec, st.Auras
    local classPowerWanted = st.classPowerOn and PreviewLayerWanted(box, "classPower")
    local detachedWanted = st.detachedPowerInUnitPreview and PreviewLayerWanted(box, "power")
    if classPowerWanted then
        local cx, cy, cpW = ClassPowerContainerRect(st)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + st.cpH)
    end
    if detachedWanted then
        local dW, dx, dy, detachedH = box._runtimeDetachedPowerW, box._runtimeDetachedPowerX, box._runtimeDetachedPowerY, st.detachedH
        local dLeft = box._runtimeDetachedPowerAnchorMode == "LEGACY_TOPLEFT" and dx or ((w - dW) * 0.5 + dx)
        local dBottom = -detachedH + dy
        if box._runtimeDetachedPowerAnchorClass and st.classPowerOn then
            local cx, cy, cpW = ClassPowerContainerRect(st)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if box._runtimePowerAttached == true and PreviewLayerWanted(box, "power") then
        minY = min(minY, -(PowerBarFootprintHeight(st) + 1))
    end
    if st.castPreviewVisible then
        wideW = max(wideW, st.castW)
        minX, maxX, minY, maxY = CastbarFootprint(st, minX, maxX, minY, maxY)
    end
    local arenaTrinket = MenuState.ArenaTrinketPreview
    if key == "arena" and arenaTrinket and PreviewLayerWanted(box, "trinket") then
        minX, maxX, minY, maxY = arenaTrinket.Footprint(minX, maxX, minY, maxY, w, h, ExpandAnchoredRect)
    end
    local auraPreviewState = box.mock._body._msufSceneAuraLanes
    local auraFootprintState = false
    for kind, lane in pairs(auraPreviewState or EMPTY) do
        local layer = (kind == "buff" or kind == "debuff") and kind or "auras"
        if lane.enabled and lane.max > 0 and PreviewLayerWanted(box, layer) then auraFootprintState = true end
    end
    local dispelPreview = Auras and Auras.DispelPreview
    if dispelPreview and dispelPreview.Availability then
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable = dispelPreview.Availability(key, runtimeSpec)
    else
        box._previewDispelOverlayAvailable, box._previewDispelSymbolAvailable = false, false
    end
    local dispelSymbolWanted = box._previewDispelSymbolAvailable and PreviewLayerWanted(box, "dispelSymbol")
    if Auras and Auras.ExpandDispelFootprint then
        minX, maxX, minY, maxY = Auras.ExpandDispelFootprint(runtimeSpec, w, h, minX, maxX, minY, maxY, dispelSymbolWanted)
    end
    if classPowerWanted or detachedWanted or st.castPreviewVisible or auraFootprintState or box._statusFootprintVisible
        or dispelSymbolWanted then
        minX, maxX = minX - 18, maxX + 18
        minY, maxY = minY - 18, maxY + 18
    end
    st.auraPreviewState, st.maxX, st.maxY, st.minX, st.minY, st.wideW = auraPreviewState, maxX, maxY, minX, minY, wideW
end

--- Fit/manual zoom, the S() scaler, frame levels, bar textures and the mock
--- body placement on the canvas.
function Stage.ResolveScaleAndLevels(st)
    local RenderState, box, canvas, bars, g, key, w, h = st.R, st.box, st.canvas, st.bars, st.g, st.key, st.w, st.h
    local floor, max, min, runtimePower = st.floor, st.max, st.min, st.runtimePower
    local maxX, maxY, minX, minY = st.maxX, st.maxY, st.minX, st.minY
    local centerX = ((minX + maxX) * 0.5) - (w * 0.5)
    local centerY = ((minY + maxY) * 0.5) - (h * 0.5)
    local runtimeScale = RenderState.RuntimeVisualScaleForPreviewKey(key, canvas)
    box._mockCastRuntimeScale = RenderState.RuntimeCastbarVisualScaleForPreviewKey(key, canvas)
    box._mockCastFrameScale = runtimeScale > 0 and (box._mockCastRuntimeScale / runtimeScale) or 1
    local autoScale = min(1.0, (st.cw - 60) / max(max(st.wideW, maxX - minX) * runtimeScale, 1), (st.ch - 42) / max(max(h, maxY - minY) * runtimeScale, 1))
    -- Fit mode must fit the complete configured footprint. Manual zoom keeps
    -- its usability floor, but forcing that same floor here clips status icons
    -- with large offsets instead of showing the true layout.
    if autoScale < 0.05 then autoScale = 0.05 end
    RenderState.ResolveDefaultPreviewZoomLock(box, autoScale)
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and RenderState.ClampPreviewZoom(manualZoom) or (frozenScale and RenderState.ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    RenderState.UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    -- Portrait size now comes from box._runtimePortraitW/H (independent axes), so
    -- the scaled square is no longer derived here.
    local sw, sh = S(w), S(h)
    local mockOffsetX, mockOffsetY = ResolvePreviewBodyOffsets(centerX, centerY, scale, manualZoom,
        tonumber(box._dragFrozenBaseOffsetX), tonumber(box._dragFrozenBaseOffsetY))
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if canvas._msufPreviewElementLevelBias ~= baseLevel + 4 then
        canvas._msufPreviewElementLevelBias = baseLevel + 4
        for _, handle in pairs(box.handles) do
            local priority = tonumber(handle._fields and handle._fields.interactionPriority) or 0
            handle:SetFrameLevel(MSUF.UFPreviewCore.InteractionFrameLevel(canvas, priority))
            if handle._selBorder then handle._selBorder:SetFrameLevel(handle:GetFrameLevel() + 1) end
        end
    end
    local body = mock._body
    local geometryChanged = body:GetScale() ~= scale or box._sceneCanvasX ~= mockOffsetX + panX
        or box._sceneCanvasY ~= mockOffsetY + panY
    body:SetScale(scale)
    body:SetFrameLevel(baseLevel + 4)
    body:ClearAllPoints()
    body:SetPoint("CENTER", mock, "CENTER", 0, 0)
    mock:SetSize(sw, sh)
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX + panX, mockOffsetY + panY)
    if geometryChanged then
        box._sceneCanvasX, box._sceneCanvasY = mockOffsetX + panX, mockOffsetY + panY
        -- Boss/arena snapping and shaped masks consume the owner's final effective scale and position.
        box._unitScene:Refresh()
    end
    if mock.sizeTag then mock.sizeTag:SetText(st.format("%d x %d", w, h)) end
    if mock.bounds then mock.bounds:SetFrameLevel(Layers.ElementLevel(30, 30, 31) + 16) end
    local castLayer = RenderState.ReadCastbarNum(g, key, "FrameLevelOffset", "bossCastFrameLevelOffset", 6)
    mock.cast:SetFrameLevel(Layers.ElementLevel(castLayer, 6, 0) + baseLevel + 4)
    mock.classPower:SetFrameLevel(Layers.ElementLevel(bars.classPowerFrameLevelOffset, 5, 0) + baseLevel + 4)
    st.fr, st.fg, st.fb = RenderState.FontColor()
    st.pr, st.pg, st.pb = RenderState.PowerColor(st.displayPowerToken)
    st.powerH = S(runtimePower and runtimePower.height or 0)
    st.powerEnabled = runtimePower and runtimePower.enabled == true
    st.S, st.baseLevel, st.centerX, st.centerY, st.mock = S, baseLevel, centerX, centerY, mock
    MSUF.UFPreviewCore.ApplyBoundsGuide(box, st.runtimeSpec.border and st.runtimeSpec.border.thickness or 1)
    st.scale, st.sw = scale, sw
end


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
function Stage.RenderCastbar(st)
    local S, box, g, key, max, mock = st.S, st.box, st.g, st.key, st.max, st.mock
    local castW, castBarH, castOffsetX, castOffsetY = st.castW, st.castBarH, st.castOffsetX, st.castOffsetY
    local scene = box._castScene
    if not st.castPreviewVisible then
        if scene then scene:Hide() end
        mock.cast:Hide()
        if mock.cast._featureSamples and mock.cast._featureSamples.gcd then mock.cast._featureSamples.gcd:Hide() end
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTarget:Hide()
        box.handleCastbarTime:Hide()
        return
    end
    mock.cast:Show()
    -- The live castbar is not a child of the scaled unit frame. Preserve
    -- that independent frame geometry inside Menu2 instead of stretching
    -- the castbar with the unit-frame preview.
    if mock.cast.SetScale then mock.cast:SetScale(box._mockCastFrameScale or 1) end
    local scw, sch = max(20, S(castW)), max(6, S(castBarH))
    mock.cast:SetSize(scw, sch)
    if mock.cast.sizeTag then
        mock.cast.sizeTag:SetText(st.format("%d x %d", st.floor(castW + 0.5), st.floor(castBarH + 0.5)))
        mock.cast.sizeTag:Show()
    end
    mock.cast:ClearAllPoints()
    if st.castDetached then
        box._detachedCastPreview = true
        box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = S(castOffsetX), S(castOffsetY)
        mock.cast:SetPoint("CENTER", mock._body, "CENTER", box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY)
    elseif key == "player" then
        mock.cast:SetPoint("BOTTOM", mock._body, "TOP", S(castOffsetX), S(castOffsetY))
    elseif key == "boss" or key == "arena" then
        mock.cast:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT",
            S(castOffsetX - box._bossBorderInset),
            S(castOffsetY - box._bossBorderInset - box._bossCastbarGap)
                + (box._runtimePowerEmbedded == true and st.powerH or 0))
    else
        mock.cast:SetPoint("BOTTOMLEFT", mock._body, "TOPLEFT", S(castOffsetX), S(castOffsetY))
    end
    local root = box._castSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(mock.cast)
        box._castSceneRoot = root
        box._castSample = {}
        box._castTick = {}
        box._castOpts = { sample = box._castSample, point = "CENTER", x = 0, y = 0 }
    end
    root:Activate()
    local animState = st.animState
    local sample = box._castSample
    for field in pairs(sample) do sample[field] = nil end
    local channel = key == "player" and g.castbarShowChannelTicks == true
    sample.class = st.data and st.data.class or "MAGE"
    sample.kind = channel and "CHANNEL" or "CAST"
    sample.name = st.TR(channel and "Channel" or CAST_SAMPLE_NAMES[key] or "Arcane Surge")
    sample.icon = 136235
    sample.duration = animState and tonumber(animState.castDuration) or CAST_DURATION
    sample.progress = animState and tonumber(animState.castPct) or CAST_PROGRESS
    if key == "player" then
        sample.latency, sample.latencyMS = 0.12, 50
    else
        sample.targetName = st.TR("Cleave Training Dummy")
    end
    sample.kickReady, sample.kickRecovery = true, CAST_KICK_RECOVERY
    local opts = box._castOpts
    opts.width, opts.height, opts.scale = castW, castBarH, st.scale
    local previous = scene
    scene = root:Castbar(CAST_SCENE_UNIT[key] or key, opts)
    if previous and previous ~= scene then previous:Hide() end
    box._castScene = scene
    local frame = scene:Frame()
    if frame then
        frame:SetFrameLevel(mock.cast:GetFrameLevel() + 1)
        PlaceCastbarHandles(st, frame)
        local bar = frame.statusBar
        ApplyGcdSample(mock, st.canvas, g, key, bar:GetWidth() * st.scale, max(1, bar:GetHeight() * st.scale), S, st.scale)
    end
    box.handleCastbar:SetSize(
        max(36, scw * (box._mockCastFrameScale or 1)),
        max(18, (sch + 8) * (box._mockCastFrameScale or 1)))
    st.PlaceHandle(box.handleCastbar, mock.cast)
end

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
        if region and region:IsShown() then
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
    available.nameText = st.showNamePreview
    available.hpText = st.hpTextOn
    available.powerText = st.powerTextOn
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
    available.status = st.statusLayerAvailable
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


--- Install render helpers onto the shared unit-preview object. View owns frame
--- construction; this module owns repeated visual composition.
-- Render.Install fills the shared render state in these stages, in order;
-- s carries the preview object, its deps, the render state and the values a
-- later stage reads.
local InstallStage = {}
-- The font recipe of the live frames: global font settings, the font key's path, the safe path
-- resolver, the checked setter (the client font when it fails) and the shared text shadow.
function InstallStage.PreviewFont(s)
    local deps = s.deps
    local fallbackFont = deps.FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if type(deps.ApplyPreviewFont) == "function" then return end
    deps.ApplyPreviewFont = function(fs, size)
        if not (fs and fs.SetFont) then return end
        size = tonumber(size) or 12
        local fontPath, fontFlags, _, _, _, _, useShadow = GetGlobalFontSettings()
        if type(fontPath) ~= "string" or fontPath == "" then fontPath = GetFontPath() end
        if fontFlags == nil then fontFlags = GetFontFlags() or "OUTLINE" end
        local db = EnsureDB()
        local general = db and db.general
        local fontKey = general and general.fontKey
        if type(fontPath) ~= "string" or fontPath == "" then
            if fontKey then fontPath = FontPathForKey(fontKey, size, fontFlags) end
        end
        if type(fontPath) ~= "string" or fontPath == "" then fontPath = fallbackFont end
        fontPath = ResolveSafeFontPath(fontPath, size, fontFlags, fontKey)
        if not SetFontChecked(fs, fontPath, size, fontFlags) then SetFontChecked(fs, fallbackFont, size, fontFlags) end
        if not fs.SetShadowOffset then return end
        if useShadow == nil then useShadow = not (general and general.textBackdrop == false) end
        if not useShadow then
            fs:SetShadowOffset(0, 0)
            return
        end
        local shadowAlpha, shadowX, shadowY = ResolveFontShadowMetrics(general and general.fontShadowOpacity,
            general and general.fontShadowDistance, general and general.fontShadowStrength)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, shadowAlpha) end
        fs:SetShadowOffset(shadowX, shadowY)
    end
end
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
        GradientPreviewColor PowerColor FontColor TextScopeGet ]])
    renderState.GradientPreviewColor = Preview.Model and Preview.Model.GradientPreviewColor
        or renderState.GradientPreviewColor
    renderState.ZOOM_MIN = tonumber(deps.ZOOM_MIN) or 0.35
    --- Mock body clamp = the shared legal size range every conf.width/height
    --- writer enforces (State/MSUF_Defaults.lua exports it; the EM2 popup
    --- clamps writes against the same table). Clamping the mock any narrower
    --- makes the preview lie about tall/narrow frames — and every
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
    InstallStage.PreviewFont(s)
    deps._RenderState = renderState
    InstallStage.Refreshers(s)
end
