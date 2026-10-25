-- Castbar preview runtime for edit-mode/Menu2 preview bars.
-- Shares live settings and publishes its compatibility aliases through PublicAPI.
local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_CastbarPreviews.lua").Castbars
local Config = Castbars.Config
local Anchors = Castbars.Anchors
local Backend = Castbars.Backend
local Core = Castbars.Core
local Driver = Castbars.Driver
local Frames = Castbars.Frames
local Manager = Castbars.Manager
local Player = Castbars.Player
local PreviewEdit = Castbars.PreviewEdit
local Previews = Castbars.Previews
local PublicAPI = Castbars.PublicAPI
local Utils = Castbars.Utils
local Visuals = Castbars.Visuals

local Publish = PublicAPI.Publish

local CoreFrame = MSUF.UF.GetFrame

local PREVIEW_LABELS = {
    player = "Player castbar preview",
    target = "Target castbar preview",
    focus = "Focus castbar preview",
    boss = "Celestial Ruin",
    arena = "Greater Pyroblast",
    test = "Test Cast",
}

local UNIT_CASTBAR = MSUF.Castbars.UNIT_CASTBAR
local PREVIEW_UNITS = {
    player = {
        name = "MSUF_PlayerCastbarPreview",
        width = UNIT_CASTBAR.player.w,
        height = UNIT_CASTBAR.player.h,
        x = UNIT_CASTBAR.player.x,
        y = UNIT_CASTBAR.player.y,
        detached = UNIT_CASTBAR.player.detached,
        showTime = "showPlayerCastTime",
        test = "playerCastbarTestMode",
    },
    target = {
        name = "MSUF_TargetCastbarPreview",
        width = UNIT_CASTBAR.target.w,
        height = UNIT_CASTBAR.target.h,
        x = UNIT_CASTBAR.target.x,
        y = UNIT_CASTBAR.target.y,
        detached = UNIT_CASTBAR.target.detached,
        showTime = "showTargetCastTime",
        showTargetName = "castbarTargetShowTargetName",
        test = "targetCastbarTestMode",
    },
    focus = {
        name = "MSUF_FocusCastbarPreview",
        width = UNIT_CASTBAR.focus.w,
        height = UNIT_CASTBAR.focus.h,
        x = UNIT_CASTBAR.focus.x,
        y = UNIT_CASTBAR.focus.y,
        detached = UNIT_CASTBAR.focus.detached,
        showTime = "showFocusCastTime",
        showTargetName = "castbarFocusShowTargetName",
        test = "focusCastbarTestMode",
    },
}

-- Locales/MSUF_Localization.lua publishes the locale table before this file.
local GlobalLocale = MSUF.Require("MSUF_L", "Castbars/MSUF_CastbarPreviews.lua")

local function Translate(value)
    if type(value) ~= "string" then return value end

    local namespace = MSUF
    if type(namespace) == "table" and type(namespace.Translate) == "function" then
        return namespace.Translate(value)
    end

    local locale = (type(namespace) == "table" and namespace.L) or GlobalLocale
    return (type(locale) == "table" and rawget(locale, value)) or value
end

local EnsureGeneralDB = Utils.EnsureCastbarGeneralDB

--- Providers that load before this file in every client TOC (Kernel/MSUF_Util,
--- the castbar Utils, Core, Frames, Anchors, PreviewEdit and the player
--- runtime). A missing one is a load-order bug, so it fails here, loudly,
--- instead of silently skipping a per-call guard.
local FILE = "Castbars/MSUF_CastbarPreviews.lua"
local Require = MSUF.Require
local IsInCombat = Require("MSUF_IsPlayerInCombat", FILE)
local SetTextIfChangedFn = Require("MSUF_SetTextIfChanged", FILE)
local GetCastbarTimeFormat = Require("MSUF_GetCastbarTimeFormat", FILE)
local FormatCastbarTimeText = Require("MSUF_FormatCastbarTimeText", FILE)
local CreateCastbarPreviewFrame = Frames.CreateCastbarPreviewFrame
local GetCastbarDesiredSize = Anchors.GetCastbarDesiredSize
local ApplyPlayerCastbarSizeAndLayout = Anchors.ApplyPlayerCastbarSizeAndLayout
local GetCastbarAutoAnchorOffsetX = Anchors.GetCastbarAutoAnchorOffsetX
local HardSyncCastbarPreview = Utils.HardSyncCastbarPreview
local ApplyCastbarFrameLayer = Core.ApplyCastbarFrameLayer
local ApplyCastbarTexts = Utils.CB_ApplyTexts
local ApplyCastbarGlowFade = Utils.ApplyCastbarGlowFade
local ResetCastbarGlowFade = Utils.ResetCastbarGlowFade
local UpdateCastbarTextures = Core.UpdateCastbarTextures
local SetupCastbarPreviewEditHandlers = PreviewEdit.SetupCastbarPreviewEditHandlers
local UpdateLatencyZone = Player.PlayerCastbar_UpdateLatencyZone

local function GetPreviewScale()
    local general = EnsureGeneralDB()
    local scale = tonumber(general.msufUiScale or general.uiScale) or 1
    if scale < 0.25 then return 0.25 end
    if scale > 2.0 then return 2.0 end
    return scale
end

local function SetTextIfChanged(fontString, text)
    if not fontString then return end
    text = text or ""

    SetTextIfChangedFn(fontString, text)
end

local function FormatTimeText(frame, remaining, total)
    local format = GetCastbarTimeFormat(frame and frame.unit)
    if frame then frame._msufCastTimeFormat = format end
    return FormatCastbarTimeText(format, remaining, total)
end

local function GetDesiredPreviewSize(unit, frame)
    return GetCastbarDesiredSize(unit, EnsureGeneralDB(), frame, 250, 18)
end

local function CreatePreview(unit)
    local config = PREVIEW_UNITS[unit]
    local existing = Frames.Get(unit .. "Preview")
    if existing then return existing end

    local width, height = GetDesiredPreviewSize(unit)
    local frame = CreateCastbarPreviewFrame(unit, config.name, {
        parent = UIParent,
        strata = "DIALOG",
        width = width,
        height = height,
        label = Translate(PREVIEW_LABELS[unit]),
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0.5,
    })
    if not frame then return nil end

    frame:SetScale(GetPreviewScale())
    Frames.Register(unit .. "Preview", nil, frame)
    SetupCastbarPreviewEditHandlers(frame, unit)
    return frame
end

local function SourceCastbarForUnit(unit)
    if unit == "player" then return Frames.player end
    if unit == "target" then return Frames.target end
    return Frames.focus
end

local function PositionPreview(unit, frame)
    if not frame then return end

    local general = EnsureGeneralDB()
    local config = PREVIEW_UNITS[unit]
    local width, height, preserveWidth = GetDesiredPreviewSize(unit, frame)

    ApplyPlayerCastbarSizeAndLayout(frame, general, width, height, preserveWidth)

    local parent = general[config.detached] and UIParent or CoreFrame(unit)
    if not parent then return end

    local offsetX = tonumber(general[config.x])
    local offsetY = tonumber(general[config.y])
    if unit == "player" then
        offsetX = offsetX or 0
        offsetY = offsetY or 5
    elseif unit == "target" then
        offsetX = offsetX or 65
        offsetY = offsetY or -15
    else
        offsetX = offsetX or tonumber(general.castbarTargetOffsetX) or 65
        offsetY = offsetY or tonumber(general.castbarTargetOffsetY) or -15
    end

    frame:ClearAllPoints()
    if general[config.detached] then
        frame:SetPoint("CENTER", parent, "CENTER", offsetX, offsetY)
    elseif unit == "player" then
        frame:SetPoint("BOTTOM", parent, "TOP", offsetX, offsetY)
    else
        local autoX = GetCastbarAutoAnchorOffsetX(general, unit, frame)
        frame:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", offsetX + autoX, offsetY)
    end

    HardSyncCastbarPreview(frame, SourceCastbarForUnit(unit))
    ApplyCastbarFrameLayer(frame, general, unit)
end

local function PositionPlayerCastbarPreview()
    PositionPreview("player", Frames.playerPreview or CreatePreview("player"))
end

local function PositionTargetCastbarPreview()
    PositionPreview("target", Frames.targetPreview or CreatePreview("target"))
end

local function PositionFocusCastbarPreview()
    PositionPreview("focus", Frames.focusPreview or CreatePreview("focus"))
end

local function ApplyPreviewCastText(frame, label)
    ApplyCastbarTexts(frame, nil, label, nil)
end

--- Drops a preview bar's test-cast state and its timer script (cold: test
--- toggles and preview hides only).
local function StopPreviewTestCast(frame)
    frame.MSUF_testMode = nil
    frame._msufTestActive = nil
    frame.MSUF_testStart = nil
    frame.MSUF_testDur = nil

    if frame.SetScript then frame:SetScript("OnUpdate", nil) end
end

local function ClearPreviewTest(frame, unit)
    if not frame then return end

    StopPreviewTestCast(frame)

    if frame.statusBar and frame.statusBar.SetMinMaxValues then
        frame.statusBar:SetMinMaxValues(0, 1)
        frame.statusBar:SetValue(0.5)
    end
    ResetCastbarGlowFade(frame)
    if frame.latencyBar then frame.latencyBar:Hide() end

    SetTextIfChanged(frame.timeText, "")
    if frame.castText then
        ApplyPreviewCastText(frame, Translate(PREVIEW_LABELS[unit] or PREVIEW_LABELS.boss))
    end
    if frame.castTargetText then
        SetTextIfChanged(frame.castTargetText, "")
        frame.castTargetText:Hide()
    end
end

--- Boss and arena castbars keep indexed previews, one preview object per pool
--- kind (Castbars/MSUF_CastbarPoolPreviews.lua, loaded after this file). The
--- kinds share every test-mode, Edit Mode, drag and page-preview path below.
local NO_POOL_PREVIEWS = {}

--- The pool preview objects in definition order (boss, then arena).
local function PoolPreviews()
    local pools = MSUF.Castbars and MSUF.Castbars.Pools
    return pools and pools.previewOrder or NO_POOL_PREVIEWS
end

local function PoolPreview(kind)
    local pools = MSUF.Castbars and MSUF.Castbars.Pools
    local previews = pools and pools.previews
    return previews and previews[kind]
end

local function ResolvePreviewTestDetails(frame, general)
    local unit = frame and frame.unit
    local config = PREVIEW_UNITS[unit]
    local showTime = not config or general[config.showTime] ~= false
    local showTargetName = config and config.showTargetName
        and general[config.showTargetName] == true or false
    local targetLabel = "Cleave Training Dummy"

    local previews = PoolPreviews()
    for index = 1, #previews do
        local preview = previews[index]
        if unit == preview.kind or (frame and frame[preview.kindFlag]) then
            showTime = general[preview.showTimeKey] ~= false
            showTargetName = general[preview.showTargetKey] == true
            targetLabel = preview.targetLabel
            break
        end
    end
    return showTime, showTargetName, targetLabel
end

local function UpdatePreviewTest(frame)
    if IsInCombat() then
        ClearPreviewTest(frame, frame.unit)
        return
    end

    local duration = frame.MSUF_testDur or 4.0
    local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
    local elapsed = (now - (frame.MSUF_testStart or now)) % duration
    local remaining = duration - elapsed

    if frame.statusBar then
        if not frame.statusBar._msufTestMinMax then
            frame.statusBar:SetMinMaxValues(0, duration)
            frame.statusBar._msufTestMinMax = true
        end
        frame.statusBar:SetValue(elapsed)
    end

    local general = EnsureGeneralDB()
    local showTime, showTargetName, targetLabel = ResolvePreviewTestDetails(frame, general)
    if frame.timeText then
        frame.timeText:Show()
        frame.timeText:SetAlpha(showTime and 1 or 0)
        SetTextIfChanged(frame.timeText, showTime and FormatTimeText(frame, remaining, duration) or "")
    end
    if frame.castTargetText then
        SetTextIfChanged(frame.castTargetText, showTargetName and Translate(targetLabel) or "")
        Driver.ApplyCastTargetTextColor(frame)
        frame.castTargetText:SetShown(showTargetName == true)
    end

    if frame.latencyBar then
        UpdateLatencyZone(frame, false, duration)
    end
    ApplyCastbarGlowFade(frame, remaining, duration)
end

local function StartPreviewTest(frame)
    if not (frame and frame.statusBar) then return end

    frame.MSUF_testMode = true
    frame._msufTestActive = true
    frame.MSUF_testStart = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
    frame.MSUF_testDur = 4.0
    frame.statusBar._msufTestMinMax = nil
    frame.statusBar.MSUF_hideFillTexture = nil
    local fillTexture = frame.statusBar.GetStatusBarTexture and frame.statusBar:GetStatusBarTexture()
    if fillTexture and fillTexture.SetAlpha then fillTexture:SetAlpha(1) end

    ApplyPreviewCastText(frame, Translate(PREVIEW_LABELS.test))
    if frame.icon then
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if frame.icon.Show then frame.icon:Show() end
    end

    frame:Show()
    frame:SetScript("OnUpdate", UpdatePreviewTest)
end

local function SetUnitTestMode(unit, enabled, transient)
    local general = EnsureGeneralDB()
    if enabled and IsInCombat() then enabled = false end

    local config = PREVIEW_UNITS[unit]
    if not transient then
        general[config.test] = enabled and true or false
        Config.Invalidate()
    end

    local requested = transient and enabled == true or general[config.test] == true
    local active = MSUF_UnitEditModeActive == true and requested
    local frame
    if unit == "player" and not (general.castbarPlayerPreviewEnabled and Frames.playerPreview) then
        Manager.InitSafePlayerCastbar()
        frame = Frames.player
    else
        frame = Frames.Get(unit .. "Preview") or CreatePreview(unit)
    end

    if not active then
        ClearPreviewTest(frame, unit)
        return
    end

    PositionPreview(unit, frame)
    StartPreviewTest(frame)
    Visuals.RefreshCastbarFrame(frame)
end

local function SetPlayerCastbarTestMode(enabled, transient)
    SetUnitTestMode("player", enabled, transient)
end

local function SetTargetCastbarTestMode(enabled, transient)
    SetUnitTestMode("target", enabled, transient)
end

local function SetFocusCastbarTestMode(enabled, transient)
    SetUnitTestMode("focus", enabled, transient)
end

Previews.SetPlayerCastbarTestMode = SetPlayerCastbarTestMode
Publish("MSUF_SetPlayerCastbarTestMode", Previews.SetPlayerCastbarTestMode)
Previews.SetTargetCastbarTestMode = SetTargetCastbarTestMode
Publish("MSUF_SetTargetCastbarTestMode", Previews.SetTargetCastbarTestMode)
Previews.SetFocusCastbarTestMode = SetFocusCastbarTestMode
Publish("MSUF_SetFocusCastbarTestMode", Previews.SetFocusCastbarTestMode)

local function HidePreviewFill(frame)
    if frame.statusBar and frame.statusBar.GetStatusBarTexture then
        local texture = frame.statusBar:GetStatusBarTexture()
        if texture then texture:SetAlpha(0) end
        frame.statusBar.MSUF_hideFillTexture = true
    end
end

--- The kind's documented global entry point for a per-kind function: a no-op
--- until the kind's preview exists.
local function PoolKindEntry(kind, fn)
    return function(...)
        local preview = PoolPreview(kind)
        if preview then return fn(preview, ...) end
    end
end

--- Test mode of one pool kind: every slot runs a fake cast while Edit Mode is
--- active. transient leaves the saved switch untouched.
local function SetPoolPreviewTestMode(preview, enabled, transient)
    local general = EnsureGeneralDB()
    if enabled and IsInCombat() then enabled = false end
    if not transient then
        general[preview.testModeKey] = enabled and true or false
    end

    local active = MSUF_UnitEditModeActive == true
        and (transient and enabled == true or general[preview.testModeKey] == true)
    if active then
        for index = 1, preview.maxFrames do preview:Create(index) end
    end
    if not IsInCombat() then
        preview:Update()
    end

    local kind = preview.kind
    preview:ForEach(function(frame)
        if active then
            frame.unit = kind
            StartPreviewTest(frame)
        else
            ClearPreviewTest(frame, kind)
            HidePreviewFill(frame)
        end
    end)
end

local SetBossCastbarTestMode = PoolKindEntry("boss", SetPoolPreviewTestMode)
local SetArenaCastbarTestMode = PoolKindEntry("arena", SetPoolPreviewTestMode)
Previews.SetBossCastbarTestMode = SetBossCastbarTestMode
Publish("MSUF_SetBossCastbarTestMode", Previews.SetBossCastbarTestMode)
Previews.SetArenaCastbarTestMode = SetArenaCastbarTestMode
Publish("MSUF_SetArenaCastbarTestMode", Previews.SetArenaCastbarTestMode)

local function EditModeCastbarPreviewActive()
    return MSUF_UnitEditModeActive == true
end

local poolPreviewsPending = false

local function RefreshPoolPreviews()
    if IsInCombat() then
        poolPreviewsPending = true
        return
    end

    local previews = PoolPreviews()
    for index = 1, #previews do
        local preview = previews[index]
        if preview:ShownInEditMode() then preview:Update() end
    end
end

local function MarkPoolPreviewsPending()
    poolPreviewsPending = true
end

local function FlushPoolPreviewsPending()
    if poolPreviewsPending then
        RefreshPoolPreviews()
        poolPreviewsPending = false
    end
end

local function InstallPoolPreviewEventDriver()
    if Previews.BossPreviewEventDriver then return end
    Previews.BossPreviewEventDriver = true

    local register = Require("MSUF_EventBus_Register", FILE)

    local events = {
        "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "ENCOUNTER_START",
        "ENCOUNTER_END",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
    }
    for index = 1, #events do
        register(events[index], "MSUF_BOSS_PREVIEW", RefreshPoolPreviews)
    end
    register("PLAYER_REGEN_DISABLED", "MSUF_BOSS_PREVIEW_COMBAT_START", MarkPoolPreviewsPending)
    register("PLAYER_REGEN_ENABLED", "MSUF_BOSS_PREVIEW_COMBAT_END", FlushPoolPreviewsPending)
end

--- Edit Mode drag handlers on every preview slot of one pool kind.
local function SetupPoolPreviewEditMode(preview)
    if IsInCombat() or not preview:ShownInEditMode() then return end
    if not Frames.Get(preview.frameKind, 1) then
        preview:Update()
    end

    local kind = preview.kind
    preview:ForEach(function(frame)
        HidePreviewFill(frame)
        SetupCastbarPreviewEditHandlers(frame, kind)
    end)
end

local SetupBossCastbarPreviewEditMode = PoolKindEntry("boss", SetupPoolPreviewEditMode)
local SetupArenaCastbarPreviewEditMode = PoolKindEntry("arena", SetupPoolPreviewEditMode)

local function HideBlizzardPlayerCastbar()
    local shouldUseBlizzard = Backend.ShouldUseBlizzardCastbar
    local allowShown = type(shouldUseBlizzard) == "function" and shouldUseBlizzard("player") == true

    if allowShown then return end

    local frames = { PlayerCastingBarFrame, CastingBarFrame }
    for index = 1, #frames do
        local frame = frames[index]
        if frame then
            if frame.UnregisterAllEvents then
                frame:UnregisterAllEvents()
            end
            -- Castbars/MSUF_Castbars_Bridge.lua (loads first): a shown managed
            -- bar is concealed, never hidden from here (its OnHide runs the
            -- bottom managed-frame layout tainted).
            MSUF.Castbars.NativeOwner.Conceal(frame)
        end
    end
end

local function UpdatePlayerCastbarPreview()
    local general = EnsureGeneralDB()
    if not EditModeCastbarPreviewActive() or not general.castbarPlayerPreviewEnabled then
        for unit, config in pairs(PREVIEW_UNITS) do
            local frame = Frames.Get(unit .. "Preview")
            if frame then frame:Hide() end
            SetUnitTestMode(unit, false, true)
        end
        -- Boss hides its first slot here (the Retail behaviour), arena every
        -- slot; the test-mode reset above has already refreshed both kinds.
        SetBossCastbarTestMode(false, true)
        if Frames.Get("bossPreview", 1) then Frames.Get("bossPreview", 1):Hide() end
        SetArenaCastbarTestMode(false, true)
        local arena = PoolPreview("arena")
        if arena then arena:HideAll() end
        return
    end

    local refreshFrame = Visuals.RefreshCastbarFrame
    for unit in pairs(PREVIEW_UNITS) do
        local frame = CreatePreview(unit)
        if frame then
            PositionPreview(unit, frame)
            refreshFrame(frame)
            frame:Show()
        end
    end

    local previews = PoolPreviews()
    for index = 1, #previews do
        if not IsInCombat() then
            previews[index]:Update()
            SetupPoolPreviewEditMode(previews[index])
        end
    end
    UpdateCastbarTextures(true)
end

--- Boss and arena castbar drags position their previews every tick: one
--- shared callback instead of a new closure per call.
local positioningPreview, previewPositioned
local function PositionPreviewFrame(frame, index)
    positioningPreview:Position(frame, index)
    previewPositioned = true
end

local function PositionCastbarPreviewUnit(unit)
    if MSUF_UnitEditModeActive ~= true or not EnsureGeneralDB().castbarPlayerPreviewEnabled then
        return false
    end

    if PREVIEW_UNITS[unit] then
        local frame = CreatePreview(unit)
        PositionPreview(unit, frame)
        if frame then
            frame:Show()
            return true
        end
    end

    local previews = PoolPreviews()
    for index = 1, #previews do
        local preview = previews[index]
        if (unit == preview.kind or tostring(unit):match(preview.unitPattern))
            and not IsInCombat()
        then
            positioningPreview, previewPositioned = preview, false
            preview:ForEach(PositionPreviewFrame)
            local positioned = previewPositioned
            positioningPreview = nil
            if positioned then return true end
            preview:Update()
            return true
        end
    end

    return false
end

Previews.HideBlizzardPlayerCastbar = HideBlizzardPlayerCastbar
Previews.PositionPlayerCastbarPreview = PositionPlayerCastbarPreview
Previews.PositionTargetCastbarPreview = PositionTargetCastbarPreview
Previews.PositionFocusCastbarPreview = PositionFocusCastbarPreview
Previews.PositionCastbarPreviewUnit = PositionCastbarPreviewUnit
Publish("MSUF_PositionCastbarPreviewUnit", Previews.PositionCastbarPreviewUnit)
Previews.UpdatePlayerCastbarPreview = UpdatePlayerCastbarPreview
Publish("MSUF_UpdatePlayerCastbarPreview", Previews.UpdatePlayerCastbarPreview)
Previews.SetupBossCastbarPreviewEditMode = SetupBossCastbarPreviewEditMode
Previews.SetupArenaCastbarPreviewEditMode = SetupArenaCastbarPreviewEditMode

InstallPoolPreviewEventDriver()

local function HideCastbarPreviewFrame(frame)
    if not frame then return end

    StopPreviewTestCast(frame)

    if frame.statusBar then
        if frame.statusBar.SetMinMaxValues then frame.statusBar:SetMinMaxValues(0, 1) end
        if frame.statusBar.SetValue then frame.statusBar:SetValue(0) end

        local texture = frame.statusBar.GetStatusBarTexture and frame.statusBar:GetStatusBarTexture()
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
        frame.statusBar.MSUF_hideFillTexture = true
    end

    if frame.timeText and frame.timeText.SetText then frame.timeText:SetText("") end
    if frame.latencyBar and frame.latencyBar.Hide then frame.latencyBar:Hide() end
    if frame.Hide then frame:Hide() end
end

local function HideAllCastbarPreviews()
    local db = Config.Source()
    local general = db and db.general
    if general then
        general.castbarPlayerPreviewEnabled = false
        general.playerCastbarTestMode = false
        general.targetCastbarTestMode = false
        general.focusCastbarTestMode = false
        general.bossCastbarTestMode = false
        general.arenaCastbarTestMode = false
    end

    Config.Refresh()
    HideCastbarPreviewFrame(Frames.playerPreview)
    HideCastbarPreviewFrame(Frames.targetPreview)
    HideCastbarPreviewFrame(Frames.focusPreview)

    local previews = PoolPreviews()
    for index = 1, #previews do
        previews[index]:HideAll()
    end
    for index = 1, #previews do
        previews[index]:ForEach(HideCastbarPreviewFrame)
    end
end

Previews.HideAllCastbarPreviews = HideAllCastbarPreviews
Publish("MSUF_HideAllCastbarPreviews", Previews.HideAllCastbarPreviews)

--- Menu2 castbar-page preview: while the castbar page is open, the selected
--- unit's castbar preview runs a fake cast out on the real frames. Transient by
--- design - it never writes the persistent preview/test-mode settings, only
--- exists while the page is active, and deactivates itself on combat start, so
--- combat overhead stays zero.
local pagePreviewUnit
local pagePreviewCombatWatcher
local ApplyCastbarPagePreviewState

local function EnsurePagePreviewCombatWatcher()
    if pagePreviewCombatWatcher then return pagePreviewCombatWatcher end
    local CreateFrame = CreateFrame
    if type(CreateFrame) ~= "function" then return nil end
    pagePreviewCombatWatcher = CreateFrame("Frame")
    pagePreviewCombatWatcher:Hide()
    pagePreviewCombatWatcher:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyCastbarPagePreviewState(nil)
    end)
    return pagePreviewCombatWatcher
end

local function PagePreviewRestoreDefaults(unit)
    if PREVIEW_UNITS[unit] then
        local frame = Frames.Get(unit .. "Preview")
        if frame then
            ClearPreviewTest(frame, unit)
            frame:Hide()
        end
        if EnsureGeneralDB().castbarPlayerPreviewEnabled then
            UpdatePlayerCastbarPreview()
        end
        return
    end
    local preview = PoolPreview(unit)
    if not preview then return end
    preview:ForEach(function(frame)
        ClearPreviewTest(frame, unit)
        HidePreviewFill(frame)
        frame:Hide()
    end)
    if not IsInCombat() then
        preview:Update()
    end
end

local function PagePreviewActivate(unit)
    if PREVIEW_UNITS[unit] then
        local frame = CreatePreview(unit)
        if not frame then return false end
        PositionPreview(unit, frame)
        StartPreviewTest(frame)
        Visuals.RefreshCastbarFrame(frame)
        frame:Show()
        return true
    end
    local preview = PoolPreview(unit)
    if not preview then return false end
    local shown = false
    for index = 1, preview.maxFrames do
        local frame = preview:Create(index)
        if frame then
            preview:ApplyLayout(frame, index)
            preview:Position(frame, index)
            frame.unit = unit
            StartPreviewTest(frame)
            frame:Show()
            shown = true
        end
    end
    return shown
end

ApplyCastbarPagePreviewState = function(unit)
    unit = tostring(unit or ""):lower()
    if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "boss" and unit ~= "arena" then unit = nil end
    if unit and IsInCombat() then unit = nil end
    local previous = pagePreviewUnit
    -- Published before restore/activation: the indexed preview owners consult it
    -- so texture/layout re-applies keep (or drop) the page preview correctly.
    pagePreviewUnit = unit
    MSUF.ExportPublic("MSUF2_CastbarPagePreviewUnit", unit)
    if previous and previous ~= unit then
        PagePreviewRestoreDefaults(previous)
    end
    if unit and not PagePreviewActivate(unit) then
        pagePreviewUnit = nil
        MSUF.ExportPublic("MSUF2_CastbarPagePreviewUnit", nil)
        unit = nil
    end
    if unit then
        local watcher = EnsurePagePreviewCombatWatcher()
        if watcher then watcher:RegisterEvent("PLAYER_REGEN_DISABLED") end
    elseif pagePreviewCombatWatcher then
        pagePreviewCombatWatcher:UnregisterAllEvents()
    end
    return pagePreviewUnit
end
Previews.ApplyCastbarPagePreviewState = ApplyCastbarPagePreviewState
Publish("MSUF_ApplyCastbarPagePreviewState", Previews.ApplyCastbarPagePreviewState)
