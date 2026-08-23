-- Castbar preview runtime for edit-mode/Menu2 preview bars.
-- Keeps the historic public globals while routing new writes through ExportPublic.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end

local PREVIEW_LABELS = {
    player = "Player castbar preview",
    target = "Target castbar preview",
    focus = "Focus castbar preview",
    boss = "Celestial Ruin",
    test = "Test Cast",
}

local PREVIEW_UNITS = {
    player = {
        name = "MSUF_PlayerCastbarPreview",
        width = "castbarPlayerBarWidth",
        height = "castbarPlayerBarHeight",
        x = "castbarPlayerOffsetX",
        y = "castbarPlayerOffsetY",
        detached = "castbarPlayerDetached",
        showTime = "showPlayerCastTime",
        test = "playerCastbarTestMode",
    },
    target = {
        name = "MSUF_TargetCastbarPreview",
        width = "castbarTargetBarWidth",
        height = "castbarTargetBarHeight",
        x = "castbarTargetOffsetX",
        y = "castbarTargetOffsetY",
        detached = "castbarTargetDetached",
        showTime = "showTargetCastTime",
        showTargetName = "castbarTargetShowTargetName",
        test = "targetCastbarTestMode",
    },
    focus = {
        name = "MSUF_FocusCastbarPreview",
        width = "castbarFocusBarWidth",
        height = "castbarFocusBarHeight",
        x = "castbarFocusOffsetX",
        y = "castbarFocusOffsetY",
        detached = "castbarFocusDetached",
        showTime = "showFocusCastTime",
        showTargetName = "castbarFocusShowTargetName",
        test = "focusCastbarTestMode",
    },
}

local function Translate(value)
    if type(value) ~= "string" then return value end

    local namespace = _G.MSUF_NS
    if type(namespace) == "table" and type(namespace.Translate) == "function" then
        return namespace.Translate(value)
    end

    local locale = (type(namespace) == "table" and namespace.L) or _G.MSUF_L
    return (type(locale) == "table" and rawget(locale, value)) or value
end

local function EnsureGeneralDB()
    local ensure = _G.MSUF_EnsureDB or _G.EnsureDB
    if type(ensure) == "function" then ensure() end

    local db = _G.MSUF_DB
    if not db then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    db.general = db.general or {}
    return db.general
end

local function IsInCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end

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

    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fontString, text)
    elseif fontString.SetText then
        fontString:SetText(text)
    end
end

local function FormatTimeText(frame, remaining, total)
    local format = "CURRENT"
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
        format = _G.MSUF_GetCastbarTimeFormat(frame and frame.unit)
    end
    if frame then frame._msufCastTimeFormat = format end

    if type(_G.MSUF_FormatCastbarTimeText) == "function" then
        return _G.MSUF_FormatCastbarTimeText(format, remaining, total)
    end
    return string.format("%.1f", tonumber(remaining) or 0)
end

local function GetDesiredPreviewSize(unit, frame)
    local general = EnsureGeneralDB()
    local config = PREVIEW_UNITS[unit]

    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        return _G.MSUF_GetCastbarDesiredSize(unit, general, frame, 250, 18)
    end

    local width = tonumber(general[config.width]) or tonumber(general.castbarGlobalWidth) or 250
    local height = tonumber(general[config.height]) or tonumber(general.castbarGlobalHeight) or 18
    local unitFrame = CoreFrame(unit)

    if not general[config.detached] and unitFrame and unitFrame.GetWidth then
        width = tonumber(general[config.width]) or unitFrame:GetWidth() or width
    end

    return width, height
end

local function CreatePreview(unit)
    local config = PREVIEW_UNITS[unit]
    local existing = _G[config.name]
    if existing then return existing end

    local width, height = GetDesiredPreviewSize(unit)
    local createFrame = _G.MSUF_CreateCastbarPreviewFrame
    if type(createFrame) ~= "function" then return nil end

    local frame = createFrame(unit, config.name, {
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
    ExportPublic(config.name, frame)

    if type(_G.MSUF_SetupCastbarPreviewEditHandlers) == "function" then
        _G.MSUF_SetupCastbarPreviewEditHandlers(frame, unit)
    end

    return frame
end

local function CreatePlayerCastbarPreview()
    return CreatePreview("player")
end

local function CreateTargetCastbarPreview()
    return CreatePreview("target")
end

local function CreateFocusCastbarPreview()
    return CreatePreview("focus")
end

local function SourceCastbarForUnit(unit)
    if unit == "player" then return _G.MSUF_PlayerCastbar end
    if unit == "target" then return _G.MSUF_TargetCastbar end
    return _G.MSUF_FocusCastbar
end

local function PositionPreview(unit, frame)
    if not frame then return end

    local general = EnsureGeneralDB()
    local config = PREVIEW_UNITS[unit]
    local width, height, preserveWidth = GetDesiredPreviewSize(unit, frame)

    if type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarSizeAndLayout(frame, general, width, height, preserveWidth)
    else
        frame:SetSize(width or 250, height or 18)
    end

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
        local autoX = 0
        if type(_G.MSUF_GetCastbarAutoAnchorOffsetX) == "function" then
            autoX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, unit, frame)
        end
        frame:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", offsetX + autoX, offsetY)
    end

    if type(_G.MSUF_HardSyncCastbarPreview) == "function" then
        _G.MSUF_HardSyncCastbarPreview(frame, SourceCastbarForUnit(unit))
    end
    if type(_G.MSUF_ApplyCastbarFrameLayer) == "function" then
        _G.MSUF_ApplyCastbarFrameLayer(frame, general, unit)
    end
end

local function PositionPlayerCastbarPreview()
    PositionPreview("player", _G.MSUF_PlayerCastbarPreview or CreatePreview("player"))
end

local function PositionTargetCastbarPreview()
    PositionPreview("target", _G.MSUF_TargetCastbarPreview or CreatePreview("target"))
end

local function PositionFocusCastbarPreview()
    PositionPreview("focus", _G.MSUF_FocusCastbarPreview or CreatePreview("focus"))
end

local function ApplyPreviewCastText(frame, label)
    if type(_G.MSUF_CB_ApplyTexts) == "function" then
        _G.MSUF_CB_ApplyTexts(frame, nil, label, nil)
    else
        SetTextIfChanged(frame and frame.castText, label)
    end
end

local function ClearPreviewTest(frame, unit)
    if not frame then return end

    frame.MSUF_testMode = nil
    frame._msufTestActive = nil
    frame.MSUF_testStart = nil
    frame.MSUF_testDur = nil

    if frame.SetScript then frame:SetScript("OnUpdate", nil) end

    if frame.statusBar and frame.statusBar.SetMinMaxValues then
        frame.statusBar:SetMinMaxValues(0, 1)
        frame.statusBar:SetValue(0.5)
    end
    if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
        _G.MSUF_ResetCastbarGlowFade(frame)
    end
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
    local config = PREVIEW_UNITS[frame.unit]
    local showTime = not config or general[config.showTime] ~= false
    if frame.timeText then
        frame.timeText:Show()
        frame.timeText:SetAlpha(showTime and 1 or 0)
        SetTextIfChanged(frame.timeText, showTime and FormatTimeText(frame, remaining, duration) or "")
    end
    if frame.castTargetText then
        local showTargetName = config and config.showTargetName and general[config.showTargetName] == true
        SetTextIfChanged(frame.castTargetText, showTargetName and Translate("Cleave Training Dummy") or "")
        if type(_G.MSUF_ApplyCastTargetTextColor) == "function" then
            _G.MSUF_ApplyCastTargetTextColor(frame)
        end
        frame.castTargetText:SetShown(showTargetName == true)
    end

    if frame.latencyBar and type(_G.MSUF_PlayerCastbar_UpdateLatencyZone) == "function" then
        _G.MSUF_PlayerCastbar_UpdateLatencyZone(frame, false, duration)
    end
    if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
        _G.MSUF_ApplyCastbarGlowFade(frame, remaining, duration)
    end
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
    end

    local requested = transient and enabled == true or general[config.test] == true
    local active = _G.MSUF_UnitEditModeActive == true and requested
    local frame
    if unit == "player" and not (general.castbarPlayerPreviewEnabled and _G.MSUF_PlayerCastbarPreview) then
        if type(_G.MSUF_InitSafePlayerCastbar) == "function" then
            _G.MSUF_InitSafePlayerCastbar()
        end
        frame = _G.MSUF_PlayerCastbar
    else
        frame = _G[config.name] or CreatePreview(unit)
    end

    if not active then
        ClearPreviewTest(frame, unit)
        return
    end

    PositionPreview(unit, frame)
    StartPreviewTest(frame)
    if type(_G.MSUF_RefreshCastbarFrame) == "function" then
        _G.MSUF_RefreshCastbarFrame(frame)
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(unit)
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals(unit)
    end
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

ExportPublic("MSUF_SetPlayerCastbarTestMode", SetPlayerCastbarTestMode)
ExportPublic("MSUF_SetTargetCastbarTestMode", SetTargetCastbarTestMode)
ExportPublic("MSUF_SetFocusCastbarTestMode", SetFocusCastbarTestMode)

local function ForEachBossPreview(callback)
    local maxBossFrames = tonumber(_G.MAX_BOSS_FRAMES) or 5
    if maxBossFrames < 1 or maxBossFrames > 12 then maxBossFrames = 5 end

    local first = _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1
    if first then callback(first, 1) end
    for index = 2, maxBossFrames do
        local frame = _G["MSUF_BossCastbarPreview" .. index]
        if frame then callback(frame, index) end
    end
end

local function HideBossPreviewFill(frame)
    if frame.statusBar and frame.statusBar.GetStatusBarTexture then
        local texture = frame.statusBar:GetStatusBarTexture()
        if texture then texture:SetAlpha(0) end
        frame.statusBar.MSUF_hideFillTexture = true
    end
end

local function SetBossCastbarTestMode(enabled, transient)
    local general = EnsureGeneralDB()
    if enabled and IsInCombat() then enabled = false end
    if not transient then
        general.bossCastbarTestMode = enabled and true or false
    end

    local active = _G.MSUF_UnitEditModeActive == true
        and (transient and enabled == true or general.bossCastbarTestMode == true)
    if active then
        local createBossPreview = _G.MSUF_CreateBossCastbarPreview
        if type(createBossPreview) == "function" then
            local maxBossFrames = tonumber(_G.MAX_BOSS_FRAMES) or 5
            if maxBossFrames < 1 or maxBossFrames > 12 then maxBossFrames = 5 end
            for index = 1, maxBossFrames do createBossPreview(index) end
        end
    end
    if not IsInCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    ForEachBossPreview(function(frame)
        if active then
            frame.unit = "boss"
            frame._msufTestShowTime = general.showBossCastTime ~= false
            StartPreviewTest(frame)
        else
            ClearPreviewTest(frame, "boss")
            HideBossPreviewFill(frame)
        end
    end)
end

ExportPublic("MSUF_SetBossCastbarTestMode", SetBossCastbarTestMode)

local function EditModeCastbarPreviewActive()
    return _G.MSUF_UnitEditModeActive == true
end

local function ShouldShowBossPreview()
    local general = EnsureGeneralDB()
    if not EditModeCastbarPreviewActive() or not general.castbarPlayerPreviewEnabled then return false end

    local db = _G.MSUF_DB
    if db and db.boss and db.boss.enabled == false then return false end

    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar
    return type(shouldUseMSUF) == "function" and shouldUseMSUF("boss", general) == true
        or general.enableBossCastbar ~= false
end

local bossPreviewPending = false

local function RefreshBossPreview()
    if IsInCombat() then
        bossPreviewPending = true
        return
    end

    if ShouldShowBossPreview() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

local function MarkBossPreviewPending()
    bossPreviewPending = true
end

local function FlushBossPreviewPending()
    if bossPreviewPending then
        bossPreviewPending = false
        RefreshBossPreview()
    end
end

local function InstallBossPreviewEventDriver()
    if _G.MSUF_BossPreviewEventDriver then return end
    ExportPublic("MSUF_BossPreviewEventDriver", true)

    local register = _G.MSUF_EventBus_Register
    if type(register) ~= "function" then return end

    local events = {
        "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "ENCOUNTER_START",
        "ENCOUNTER_END",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
    }
    for index = 1, #events do
        register(events[index], "MSUF_BOSS_PREVIEW", RefreshBossPreview)
    end
    register("PLAYER_REGEN_DISABLED", "MSUF_BOSS_PREVIEW_COMBAT_START", MarkBossPreviewPending)
    register("PLAYER_REGEN_ENABLED", "MSUF_BOSS_PREVIEW_COMBAT_END", FlushBossPreviewPending)
end

local function SetupBossCastbarPreviewEditMode()
    if IsInCombat() or not ShouldShowBossPreview() then return end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" and not _G.MSUF_BossCastbarPreview then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    ForEachBossPreview(function(frame)
        HideBossPreviewFill(frame)
        if type(_G.MSUF_SetupCastbarPreviewEditHandlers) == "function" then
            _G.MSUF_SetupCastbarPreviewEditHandlers(frame, "boss")
        end
    end)
end

local function HideBlizzardPlayerCastbar()
    local shouldUseBlizzard = _G.MSUF_ShouldUseBlizzardCastbar
    local allowShown = type(shouldUseBlizzard) == "function" and shouldUseBlizzard("player") == true

    if allowShown then return end

    local frames = { _G.PlayerCastingBarFrame, _G.CastingBarFrame }
    for index = 1, #frames do
        local frame = frames[index]
        if frame then
            if frame.UnregisterAllEvents then
                frame:UnregisterAllEvents()
            end
            if frame.Hide then frame:Hide() end
        end
    end
end

local function UpdatePlayerCastbarPreview()
    local general = EnsureGeneralDB()
    if not EditModeCastbarPreviewActive() or not general.castbarPlayerPreviewEnabled then
        for unit, config in pairs(PREVIEW_UNITS) do
            local frame = _G[config.name]
            if frame then frame:Hide() end
            SetUnitTestMode(unit, false, true)
        end
        if type(_G.MSUF_SetBossCastbarTestMode) == "function" then
            _G.MSUF_SetBossCastbarTestMode(false, true)
        end
        if _G.MSUF_BossCastbarPreview then _G.MSUF_BossCastbarPreview:Hide() end
        return
    end

    local refreshFrame = _G.MSUF_RefreshCastbarFrame
    for unit in pairs(PREVIEW_UNITS) do
        local frame = CreatePreview(unit)
        if frame then
            PositionPreview(unit, frame)
            if type(refreshFrame) == "function" then refreshFrame(frame) end
            frame:Show()
        end
    end

    if not IsInCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
        SetupBossCastbarPreviewEditMode()
    end
    if type(refreshFrame) ~= "function" then
        local applyUnit = _G.MSUF_ApplyCastbarVisualsForUnit
        if type(applyUnit) == "function" then
            for unit in pairs(PREVIEW_UNITS) do applyUnit(unit) end
            applyUnit("boss")
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            for unit in pairs(PREVIEW_UNITS) do _G.MSUF_UpdateCastbarVisuals(unit) end
            _G.MSUF_UpdateCastbarVisuals("boss")
        end
    end
    if type(_G.MSUF_UpdateCastbarTextures) == "function" then _G.MSUF_UpdateCastbarTextures() end
end

local function PositionCastbarPreviewUnit(unit)
    if _G.MSUF_UnitEditModeActive ~= true or not EnsureGeneralDB().castbarPlayerPreviewEnabled then
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

    if (unit == "boss" or tostring(unit):match("^boss%d*$"))
        and not IsInCombat()
    then
        local positioned = false
        local positionBoss = _G.MSUF_PositionBossCastbarPreview
        if type(positionBoss) == "function" then
            ForEachBossPreview(function(frame, index)
                positionBoss(frame, index)
                positioned = true
            end)
        end
        if positioned then return true end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
            return true
        end
    end

    return false
end

local function SyncBossCastbarSliders()
    local general = EnsureGeneralDB()
    local values = {
        MSUF_CastbarBossXOffsetSlider = general.bossCastbarOffsetX or 0,
        MSUF_CastbarBossYOffsetSlider = general.bossCastbarOffsetY or 0,
        MSUF_CastbarBossWidthSlider = general.bossCastbarWidth or 240,
        MSUF_CastbarBossHeightSlider = general.bossCastbarHeight or 18,
    }

    local setSilent = _G.MSUF_SetSliderValueSilent
    local clamp = _G.MSUF_ClampToSlider
    if type(setSilent) ~= "function" or type(clamp) ~= "function" then return end

    for sliderName, value in pairs(values) do
        local slider = _G[sliderName]
        if slider then
            setSilent(slider, clamp(slider, tonumber(value) or 0))
        end
    end
end

ExportPublic("MSUF_HideBlizzardPlayerCastbar", HideBlizzardPlayerCastbar)
ExportPublic("MSUF_CreatePlayerCastbarPreview", _G.MSUF_CreatePlayerCastbarPreview or CreatePlayerCastbarPreview)
ExportPublic("MSUF_CreateTargetCastbarPreview", _G.MSUF_CreateTargetCastbarPreview or CreateTargetCastbarPreview)
ExportPublic("MSUF_CreateFocusCastbarPreview", _G.MSUF_CreateFocusCastbarPreview or CreateFocusCastbarPreview)
ExportPublic("MSUF_PositionPlayerCastbarPreview", PositionPlayerCastbarPreview)
ExportPublic("MSUF_PositionTargetCastbarPreview", PositionTargetCastbarPreview)
ExportPublic("MSUF_PositionFocusCastbarPreview", PositionFocusCastbarPreview)
ExportPublic("MSUF_PositionCastbarPreviewUnit", PositionCastbarPreviewUnit)
ExportPublic("MSUF_UpdatePlayerCastbarPreview", UpdatePlayerCastbarPreview)
ExportPublic("MSUF_SetupBossCastbarPreviewEditMode", SetupBossCastbarPreviewEditMode)
ExportPublic("MSUF_SyncBossCastbarSliders", SyncBossCastbarSliders)

InstallBossPreviewEventDriver()

if hooksecurefunc
    and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
    and not _G.MSUF_BossPreviewSetupHooked
then
    ExportPublic("MSUF_BossPreviewSetupHooked", true)
    hooksecurefunc("MSUF_UpdateBossCastbarPreview", function()
        if not IsInCombat() then SetupBossCastbarPreviewEditMode() end
    end)
end

local function HideCastbarPreviewFrame(frame)
    if not frame then return end

    frame.MSUF_testMode = nil
    frame._msufTestActive = nil
    frame.MSUF_testStart = nil
    frame.MSUF_testDur = nil

    if frame.SetScript then frame:SetScript("OnUpdate", nil) end

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
    local db = _G.MSUF_DB
    local general = db and db.general
    if general then
        general.castbarPlayerPreviewEnabled = false
        general.playerCastbarTestMode = false
        general.targetCastbarTestMode = false
        general.focusCastbarTestMode = false
        general.bossCastbarTestMode = false
    end

    HideCastbarPreviewFrame(_G.MSUF_PlayerCastbarPreview)
    HideCastbarPreviewFrame(_G.MSUF_TargetCastbarPreview)
    HideCastbarPreviewFrame(_G.MSUF_FocusCastbarPreview)

    if type(_G.MSUF_HideAllBossCastbarPreviews) == "function" then
        _G.MSUF_HideAllBossCastbarPreviews()
    end

    local maxBossFrames = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if maxBossFrames < 1 or maxBossFrames > 12 then maxBossFrames = 5 end

    HideCastbarPreviewFrame(_G.MSUF_BossCastbarPreview)
    HideCastbarPreviewFrame(_G.MSUF_BossCastbarPreview1)
    for index = 2, maxBossFrames do
        HideCastbarPreviewFrame(_G["MSUF_BossCastbarPreview" .. index])
    end
end

ExportPublic("MSUF_HideAllCastbarPreviews", HideAllCastbarPreviews)

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
    local CreateFrame = _G.CreateFrame
    if type(CreateFrame) ~= "function" then return nil end
    pagePreviewCombatWatcher = CreateFrame("Frame")
    pagePreviewCombatWatcher:Hide()
    pagePreviewCombatWatcher:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyCastbarPagePreviewState(nil)
    end)
    return pagePreviewCombatWatcher
end

local function PagePreviewMaxBossFrames()
    local maxBossFrames = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if maxBossFrames < 1 or maxBossFrames > 12 then maxBossFrames = 5 end
    return maxBossFrames
end

local function PagePreviewRestoreDefaults(unit)
    if PREVIEW_UNITS[unit] then
        local frame = _G[PREVIEW_UNITS[unit].name]
        if frame then
            ClearPreviewTest(frame, unit)
            frame:Hide()
        end
        if EnsureGeneralDB().castbarPlayerPreviewEnabled then
            UpdatePlayerCastbarPreview()
        end
        return
    end
    if unit ~= "boss" then return end
    ForEachBossPreview(function(frame)
        ClearPreviewTest(frame, "boss")
        HideBossPreviewFill(frame)
        frame:Hide()
    end)
    if not IsInCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

local function PagePreviewActivate(unit)
    if PREVIEW_UNITS[unit] then
        local frame = CreatePreview(unit)
        if not frame then return false end
        PositionPreview(unit, frame)
        StartPreviewTest(frame)
        if type(_G.MSUF_RefreshCastbarFrame) == "function" then
            _G.MSUF_RefreshCastbarFrame(frame)
        end
        frame:Show()
        return true
    end
    if unit ~= "boss" then return false end
    local createBossPreview = _G.MSUF_CreateBossCastbarPreview
    if type(createBossPreview) ~= "function" then return false end
    local shown = false
    for index = 1, PagePreviewMaxBossFrames() do
        local frame = createBossPreview(index)
        if frame then
            if type(_G.MSUF_ApplyBossCastbarPreviewLayout) == "function" then
                _G.MSUF_ApplyBossCastbarPreviewLayout(frame, index)
            end
            if type(_G.MSUF_PositionBossCastbarPreview) == "function" then
                _G.MSUF_PositionBossCastbarPreview(frame, index)
            end
            frame.unit = "boss"
            frame._msufTestShowTime = EnsureGeneralDB().showBossCastTime ~= false
            StartPreviewTest(frame)
            frame:Show()
            shown = true
        end
    end
    return shown
end

ApplyCastbarPagePreviewState = function(unit)
    unit = tostring(unit or ""):lower()
    if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "boss" then unit = nil end
    if unit and IsInCombat() then unit = nil end
    local previous = pagePreviewUnit
    -- Published before restore/activation: UpdateBossCastbarPreview consults it
    -- so texture/layout re-applies keep (or drop) the page preview correctly.
    pagePreviewUnit = unit
    _G.MSUF2_CastbarPagePreviewUnit = unit
    if previous and previous ~= unit then
        PagePreviewRestoreDefaults(previous)
    end
    if unit and not PagePreviewActivate(unit) then
        pagePreviewUnit = nil
        _G.MSUF2_CastbarPagePreviewUnit = nil
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
ExportPublic("MSUF_ApplyCastbarPagePreviewState", ApplyCastbarPagePreviewState)
