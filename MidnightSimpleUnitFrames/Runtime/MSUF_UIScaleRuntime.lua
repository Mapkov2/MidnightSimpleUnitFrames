--- Always-loaded UI/frame scale runtime extracted from Menu2 support.
--- Saved scale behavior predates the options window and must remain active even
--- while the 5 MB options addon has never been loaded.

local _, MSUF = ...
local MAX_ARENA_FRAMES = MSUF.Require("MSUF", "Runtime/MSUF_UIScaleRuntime.lua").Client.MaxArenaOpponents
local ExportPublic, Optional = MSUF.ExportPublic, MSUF.Optional
local PublicGlobals = MSUF.PublicGlobals
local M = MSUF.MSUF2 or Optional("MSUF2") or {}
MSUF.MSUF2 = M
ExportPublic("MSUF2", M)
local Runtime = M.MenuRuntime or {}
M.MenuRuntime = Runtime

local abs = math.abs
local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
--- Chat line: the sentence is translated first and formatted after.
local function Print(text, ...)
    if type(print) == "function" then print("|cff00ff00MSUF:|r " .. string.format(MSUF.Translate(text), ...)) end
end
local function ForEachCoreFrame(fn)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.ForEachFrame) == "function" then
        uf.ForEachFrame(function(frame)
            if frame then fn(frame, frame.MSUFUnitKey or frame.unit) end
        end)
        return true
    end
    local frames = uf and uf.frames
    if type(frames) ~= "table" then return false end
    for unitKey, frame in pairs(frames) do fn(frame, unitKey) end
    return true
end
local IsConfigCombatLocked = InCombatLockdown
--- REQUIRED: Kernel/MSUF_Util.lua owns the combat lock message and loads ahead
--- of this file in every core TOC.
local ShowConfigCombatLockMessage = MSUF.Require("MSUF_ShowConfigCombatLockMessage", "Runtime/MSUF_UIScaleRuntime.lua")
local function BlockConfigCombatLocked(silent)
    if not IsConfigCombatLocked() then return false end
    if not silent then ShowConfigCombatLockMessage() end
    return true
end
--- REQUIRED: State/MSUF_Defaults.lua is listed unconditionally in the TOC and
--- exports MSUF_EnsureDB at its top level, long before this file. Scale state
--- is read straight out of MSUF_DB.general, so the guard is not optional.
local EnsureDB = MSUF.Require("MSUF_EnsureDB", "Runtime/MSUF_UIScaleRuntime.lua")
local function EnsureGeneral()
    EnsureDB()
    local db = MSUF_DB
    db = ExportPublic("MSUF_DB", type(db) == "table" and db or {})
    db.general = type(db.general) == "table" and db.general or {}
    return db.general
end
local pendingMsufScale
local pendingGlobalScale
local pendingDisableScaling
local pendingReloadOnScalingOff
local scaleApplyWatcher
local scaleEvents
local scaleReanchorTimer
local restoreBlizzardScaleTimers = {}
local UpdateGlobalScaleEvents
local lastGlobalUiParentScale
local blizzardUiParentScale
local UI_SCALE_1080 = 768 / 1080
local UI_SCALE_1440 = 768 / 1440
local UI_SCALE_4K = 768 / 2160
local UI_SCALE_PRESETS = { ["1080p"] = UI_SCALE_1080, ["1440p"] = UI_SCALE_1440, ["4k"] = UI_SCALE_4K }
local CASTBAR_SCALE_KINDS = { "player", "target", "focus" }
local function IsGroupFrameUnitKey(unitKey)
    if type(unitKey) ~= "string" then return false end
    return unitKey:sub(1, 5) == "party" or unitKey:sub(1, 4) == "raid"
end
local function IsGroupFrameScaleEnabled(frame, unitKey)
    if not (frame and (frame._msufGFBuilt or frame._msufGFKind or IsGroupFrameUnitKey(unitKey))) then return true end
    local kind = frame._msufGFKind
    if not kind and IsGroupFrameUnitKey(unitKey) then kind = unitKey:sub(1, 4) == "raid" and "raid" or "party" end
    local gf = MSUF and MSUF.GF
    local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(kind) or nil
    local mode = conf and conf.frameScaleMode or "off"
    return mode == "manual" or mode == "auto"
end
local function CollectMsufScaleFrames()
    local frames, seen = {}, {}
    local function add(frame, unitKey)
        if not frame or seen[frame] then return end
        if not IsGroupFrameScaleEnabled(frame, unitKey) then return end
        if type(frame) == "table" and type(frame.SetScale) == "function" then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    ForEachCoreFrame(add)
    local castbarFrames = MSUF.Castbars.Frames
    for i = 1, #CASTBAR_SCALE_KINDS do
        local kind = CASTBAR_SCALE_KINDS[i]
        add(castbarFrames.Get(kind))
        add(castbarFrames.Get(kind .. "Preview"))
    end
    for i = 1, 5 do
        add(castbarFrames.Get("boss", i))
        add(castbarFrames.Get("bossPreview", i))
    end
    for i = 1, tonumber(MAX_ARENA_FRAMES) or 3 do
        add(castbarFrames.Get("arena", i))
        add(castbarFrames.Get("arenaPreview", i))
    end
    return frames
end
local function GetSavedMsufScale()
    local g = EnsureGeneral()
    return Clamp(tonumber(g.msufUiScale) or tonumber(g.uiScale) or 1, 0.25, 2.0)
end
local function RefreshGroupFrameGeometryAfterScale()
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshHeaderLayout) == "function" then
        gf.RefreshHeaderLayout()
    end
end
local function FlushUnitframeReanchorAfterScale()
    scaleReanchorTimer = nil
    ExportPublic("MSUF_ScaleReanchorPending", false)
    if InCombatLockdown and InCombatLockdown() then
        local UF = MSUF.UF
        if UF and UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
        RefreshGroupFrameGeometryAfterScale()
        return
    end
    -- UnitFrames/Engine/MSUF_UF_Factory.lua owns both and loads ahead of this file.
    MSUF.Require("MSUF_UpdateAllExternalAnchorProxies", "Runtime/MSUF_UIScaleRuntime.lua")()
    local forceReanchor = MSUF.Require("MSUF_ForceReanchorAllUnitFrames_Once", "Runtime/MSUF_UIScaleRuntime.lua")
    local previous = PublicGlobals.MSUF_ExternalAnchorForceReanchor
    ExportPublic("MSUF_ExternalAnchorForceReanchor", true)
    forceReanchor(true)
    ExportPublic("MSUF_ExternalAnchorForceReanchor", previous)
    RefreshGroupFrameGeometryAfterScale()
end
local function ScheduleUnitframeReanchorAfterScale()
    if PublicGlobals.MSUF_ScaleReanchorPending then return end
    ExportPublic("MSUF_ScaleReanchorPending", true)
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        scaleReanchorTimer = C_Timer.NewTimer(0, FlushUnitframeReanchorAfterScale)
    else
        C_Timer.After(0, FlushUnitframeReanchorAfterScale)
    end
end
local EnsureScaleApplyAfterCombat
local ResetGlobalUiScale
local function CancelScaleTimer(timer)
    if not (timer and type(timer.Cancel) == "function") then return end
    timer.Cancel(timer)
end
--- Cancels the Blizzard-scale restores RestoreBlizzardUiScale scheduled and
--- returns how many were pending.
local function CancelBlizzardRestoreTimers()
    local restoreCount = 0
    while true do
        local record = next(restoreBlizzardScaleTimers)
        if record == nil then break end
        restoreBlizzardScaleTimers[record] = nil
        CancelScaleTimer(record.timer)
        restoreCount = restoreCount + 1
    end
    return restoreCount
end
local function CancelPendingScaleTimers()
    local reanchorPending = PublicGlobals.MSUF_ScaleReanchorPending == true
    local reanchorTimer = scaleReanchorTimer
    scaleReanchorTimer = nil
    CancelScaleTimer(reanchorTimer)
    ExportPublic("MSUF_ScaleReanchorPending", false)
    return reanchorPending, CancelBlizzardRestoreTimers()
end
local function ApplyMsufScale(scale, onlyChanged)
    scale = tonumber(scale)
    if not scale then return end
    scale = Clamp(scale, 0.25, 2.0)
    if InCombatLockdown and InCombatLockdown() then
        pendingMsufScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        return
    end
    local frames = CollectMsufScaleFrames()
    local changed = false
    for i = 1, #frames do
        local frame = frames[i]
        if not onlyChanged or abs(frame:GetScale() - scale) > 0.0001 then
            frame:SetScale(scale)
            changed = true
        end
    end
    -- Lifecycle repeats use live geometry, including newly created frames.
    -- Explicit applies still force repair and replay cancelled combat work.
    if onlyChanged and not changed then return end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then a3.RefreshEditPreview() end
    ScheduleUnitframeReanchorAfterScale()
end
local function GetCurrentGlobalUiScale()
    if UIParent and UIParent.GetScale then return tonumber(UIParent:GetScale()) end
    return nil
end
local function GetPixelPerfectScale()
    if type(GetPhysicalScreenSize) == "function" then
        local _, height = GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    return UI_SCALE_1440
end
local function ResolveGlobalPresetScale(preset, scale)
    if preset == "pixel" then return GetPixelPerfectScale() end
    return UI_SCALE_PRESETS[preset] or tonumber(scale)
end
local function EnsureGlobalUiScaleTable(g)
    if not g then return nil end
    local ui = type(g.UIScale) == "table" and g.UIScale or nil
    if not ui then
        ui = {}
        g.UIScale = ui
        local preset = g.globalUiScalePreset
        local scale = ResolveGlobalPresetScale(preset, g.globalUiScaleValue) or 1.0
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
        ui.Scale = scale
        ui._migratedFromGlobalPreset_v1 = true
    end
    if ui.Enabled == nil then
        local preset = g.globalUiScalePreset
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
    end
    ui.Enabled = ui.Enabled == true
    ui.Scale = Clamp(tonumber(ui.Scale) or ResolveGlobalPresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0, 0.3, 1.5)
    g.disableScaling = false
    return ui
end
local function SetGlobalUiScaleState(enabled, scale, preset)
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if not ui then return end
    enabled = enabled == true
    ui.Enabled = enabled
    if scale ~= nil then ui.Scale = Clamp(tonumber(scale) or ui.Scale or 1.0, 0.3, 1.5) end
    if enabled then
        g.globalUiScalePreset = preset or g.globalUiScalePreset or "custom"
        g.globalUiScaleValue = ui.Scale
    else
        g.globalUiScalePreset = preset or "auto"
        g.globalUiScaleValue = nil
    end
    if UpdateGlobalScaleEvents then UpdateGlobalScaleEvents() end
end
local function CaptureBlizzardUiScale()
    if blizzardUiParentScale then return end
    local current = GetCurrentGlobalUiScale()
    if current and current > 0 then blizzardUiParentScale = current end
end
local function GetBlizzardCVarScale()
    local useUiScale
    if type(GetCVarBool) == "function" then
        local value = GetCVarBool("useUiScale")
        do
useUiScale = value
end
    end
    if useUiScale == nil and type(GetCVar) == "function" then
        local value = GetCVar("useUiScale")
        do
useUiScale = tostring(value) == "1"
end
    end
    if useUiScale and type(GetCVar) == "function" then
        local value = GetCVar("uiScale")
        value = tonumber(value) or nil
        if value and value > 0 then return Clamp(value, 0.3, 2.0) end
    end
    if type(GetPhysicalScreenSize) == "function" then
        local _, height = GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    if blizzardUiParentScale and blizzardUiParentScale > 0 then return Clamp(blizzardUiParentScale, 0.3, 2.0) end
    return nil
end
local function RestoreBlizzardUiScaleOnce()
    if type(UIParent_UpdateScale) == "function" then
        UIParent_UpdateScale()
        do
return true
end
    end
    local scale = GetBlizzardCVarScale()
    if scale and UIParent and UIParent.SetScale then
        UIParent.SetScale(UIParent, scale)
        do
return true
end
    end
    return false
end
local function RestoreBlizzardUiScale(silent)
    if BlockConfigCombatLocked(silent) then return false end
    RestoreBlizzardUiScaleOnce()
    local function ScheduleRestore(delay)
        local record = {}
        restoreBlizzardScaleTimers[record] = true
        local function Run()
            -- Cancelled (C_Timer.After has no handle to cancel).
            if not restoreBlizzardScaleTimers[record] then return end
            restoreBlizzardScaleTimers[record] = nil
            if IsConfigCombatLocked() then return end
            RestoreBlizzardUiScaleOnce()
        end
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            record.timer = C_Timer.NewTimer(delay, Run)
        else
            C_Timer.After(delay, Run)
        end
    end
    ScheduleRestore(0)
    ScheduleRestore(0.25)
    ScheduleRestore(1.0)
    lastGlobalUiParentScale = nil
    if not silent then Print("Global UI scale restored to Blizzard settings.") end
    return true
end
Runtime._quiesceScale = function(inCombat)
    local reanchorPending, restoreCount = CancelPendingScaleTimers()
    if inCombat then
        if reanchorPending then
            pendingMsufScale = GetSavedMsufScale()
            if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        end
        return true
    end
    if reanchorPending then FlushUnitframeReanchorAfterScale() end
    if restoreCount > 0 then RestoreBlizzardUiScaleOnce() end
    return true
end
local function EnforceUIParentScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)
    if not (UIParent and UIParent.SetScale) then return end
    local current = UIParent.GetScale and tonumber(UIParent:GetScale()) or 0
    if abs((current or 0) - scale) > 0.001 then UIParent:SetScale(scale) end
    lastGlobalUiParentScale = scale
end
local function SetGlobalUiScale(scale, silent)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)
    if InCombatLockdown and InCombatLockdown() then
        pendingGlobalScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end
    -- A reset just before (ApplyUIScaleProfile resets, then sets) scheduled
    -- Blizzard-scale restores for 0, 0.25 and 1 s; they must not undo this scale.
    CancelBlizzardRestoreTimers()
    CaptureBlizzardUiScale()
    EnforceUIParentScale(scale)
    if UpdateGlobalScaleEvents then UpdateGlobalScaleEvents() end
    ScheduleUnitframeReanchorAfterScale()
    if not silent then Print("Global UI scale set to %.4f", scale) end
end
ResetGlobalUiScale = function(silent)
    if InCombatLockdown and InCombatLockdown() then
        pendingDisableScaling = true
        pendingGlobalScale = nil
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return false
    end
    -- MSUF global scaling only overlays UIParent:SetScale. Off must never copy
    -- that overlay into Blizzard's useUiScale/uiScale CVars; restoring from
    -- those untouched CVars recreates the UI state that existed without MSUF.
    RestoreBlizzardUiScale(true)
    SetGlobalUiScaleState(false, nil, "auto")
    pendingGlobalScale = nil
    if not silent then Print("Global UI scale disabled. Restored Blizzard UI scale settings.") end
    ScheduleUnitframeReanchorAfterScale()
    return true
end
EnsureScaleApplyAfterCombat = function()
    if scaleApplyWatcher or not CreateFrame then return end
    local frame = CreateFrame("Frame")
    scaleApplyWatcher = frame
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        if InCombatLockdown and InCombatLockdown() then return end
        if pendingDisableScaling then
            pendingDisableScaling = nil
            pendingGlobalScale = nil
            ResetGlobalUiScale(true)
        else
            local msufScale = pendingMsufScale
            local globalScale = pendingGlobalScale
            pendingMsufScale = nil
            pendingGlobalScale = nil
            if msufScale then ApplyMsufScale(msufScale) end
            if globalScale then SetGlobalUiScale(globalScale, true) end
        end
        if pendingReloadOnScalingOff then
            pendingReloadOnScalingOff = nil
            if type(ReloadUI) == "function" then
                ReloadUI()
                return
            end
        end
        if not pendingDisableScaling and not pendingMsufScale and not pendingGlobalScale then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnEvent", nil)
            scaleApplyWatcher = nil
        end
    end)
end
local function SetScalingDisabled(disable, silent)
    local g = EnsureGeneral()
    disable = disable == true
    g.disableScaling = false
    if not disable then
        pendingDisableScaling = nil
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingDisableScaling = true
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end
    ResetGlobalUiScale(true)
    pendingDisableScaling = nil
    pendingGlobalScale = nil
    if not silent then Print("Global UI scale disabled. Blizzard keeps the current UI size.") end
end
local function GetDesiredGlobalScaleFromDB()
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if ui and ui.Enabled then
        if g.globalUiScalePreset == "pixel" then
            ui.Scale = GetPixelPerfectScale()
            g.globalUiScaleValue = ui.Scale
        end
        return tonumber(ui.Scale)
    end
    return nil
end
local function EnsureGlobalUiScaleApplied(silent)
    local want = tonumber(GetDesiredGlobalScaleFromDB())
    local current = GetCurrentGlobalUiScale()
    if want and want > 0 and (not current or abs(current - want) > 0.0001) then SetGlobalUiScale(want, silent) end
end
local function ApplyCurrentProfileGlobalUiScale()
    if IsConfigCombatLocked and IsConfigCombatLocked() then return false end
    local want = tonumber(GetDesiredGlobalScaleFromDB())
    if want and want > 0 then
        local current = GetCurrentGlobalUiScale()
        if not current or abs(current - want) > 0.0001 then
            SetGlobalUiScale(want, true)
        elseif UpdateGlobalScaleEvents then
            UpdateGlobalScaleEvents()
        end
    else
        -- Profile switches must restore the scale seen before MSUF first
        -- overlaid UIParent. UIParent_UpdateScale can choose a new automatic
        -- pixel scale mid-session, producing a jarring jump until /reload.
        local baseline = blizzardUiParentScale
        local current = GetCurrentGlobalUiScale()
        if baseline and current and abs(current - baseline) > 0.0001 then
            UIParent:SetScale(baseline)
            ScheduleUnitframeReanchorAfterScale()
        end
        lastGlobalUiParentScale = nil
        if UpdateGlobalScaleEvents then UpdateGlobalScaleEvents() end
    end
    return true
end
ExportPublic("MSUF_ApplyCurrentProfileGlobalUiScale", ApplyCurrentProfileGlobalUiScale)
local function ResetStandaloneWindowGeometry(frame, silent)
    local g = EnsureGeneral()
    g.flashFullW = 900
    g.flashFullH = 700
    g.flashFullPoint = "CENTER"
    g.flashFullRelPoint = "CENTER"
    g.flashFullX = -60
    g.flashFullY = 10
    local uiScale = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
    if not uiScale or uiScale == 0 then uiScale = 1 end
    g.flashFullXpx = -60 * uiScale
    g.flashFullYpx = 10 * uiScale
    g.msuf2WindowW = 900
    g.msuf2WindowH = 700
    -- Menu2's calibrated 100% reference preserves the historical 80% size.
    g.slashMenuScale = 0.8
    local menu = Optional("MSUF2")
    local win = frame or Optional("MSUF_StandaloneOptionsWindow") or (menu and menu.frame)
    if win then
        local scale = 1.0
        if menu and type(menu.GetEffectiveMenuScale) == "function" then scale = menu.GetEffectiveMenuScale(0.8) end
        if win.SetScale then win:SetScale(scale) end
        if win.SetSize then win:SetSize(900, 700) end
        if win.ClearAllPoints then win:ClearAllPoints() end
        if win.SetPoint then win:SetPoint("CENTER", UIParent, "CENTER", -60, 12) end
    end
    if not silent then Print("MSUF menu size reset to default.") end
end
ExportPublic("MSUF_ApplyMsufScale", ApplyMsufScale)
ExportPublic("MSUF_GetSavedMsufScale", GetSavedMsufScale)
ExportPublic("MSUF_SetScalingDisabled", SetScalingDisabled)
ExportPublic("MSUF_SetGlobalUiScale", SetGlobalUiScale)
ExportPublic("MSUF_ResetGlobalUiScale", ResetGlobalUiScale)
ExportPublic("MSUF_RestoreBlizzardUiScale", RestoreBlizzardUiScale)
ExportPublic("MSUF_ResetStandaloneWindowGeometry", ResetStandaloneWindowGeometry)
ExportPublic("MSUF_GetPixelPerfectScale", GetPixelPerfectScale)
MSUF.Require("MSUF_InstallGlobalScaleGate", "Runtime/MSUF_UIScaleRuntime.lua")()
local function ApplySavedScaleState(applyGlobalCVar, onlyChanged)
    ApplyMsufScale(GetSavedMsufScale(), onlyChanged)
    local want = GetDesiredGlobalScaleFromDB()
    if want then
        if applyGlobalCVar then SetGlobalUiScale(want, true) end
        EnsureGlobalUiScaleApplied(true)
    end
end
UpdateGlobalScaleEvents = function()
    if not CreateFrame then return end
    local enabled = (tonumber(GetDesiredGlobalScaleFromDB()) or 0) > 0
    if enabled then
        if not scaleEvents then
            scaleEvents = CreateFrame("Frame")
            scaleEvents:SetScript("OnEvent", function(_, event)
                ApplySavedScaleState(event == "PLAYER_LOGIN", event == "PLAYER_ENTERING_WORLD")
            end)
        end
        if not scaleEvents._msuf2Registered then
            scaleEvents._msuf2Registered = true
            scaleEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
        end
    elseif scaleEvents and scaleEvents._msuf2Registered then
        scaleEvents._msuf2Registered = nil
        scaleEvents:UnregisterEvent("PLAYER_ENTERING_WORLD")
        scaleEvents:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
end
local startupScaleApplyQueued
local startupScaleNeedsGlobalCVar
local function FlushStartupScaleApply()
    local needsGlobalCVar = startupScaleNeedsGlobalCVar
    startupScaleApplyQueued = nil
    startupScaleNeedsGlobalCVar = nil
    ApplySavedScaleState(needsGlobalCVar)
end
local function QueueStartupScaleApply(applyGlobalCVar)
    startupScaleNeedsGlobalCVar = startupScaleNeedsGlobalCVar or applyGlobalCVar == true
    if startupScaleApplyQueued then return end
    startupScaleApplyQueued = true
    C_Timer.After(0, FlushStartupScaleApply)
end
local startupScaleEvents = CreateFrame("Frame")
startupScaleEvents:RegisterEvent("PLAYER_LOGIN")
startupScaleEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
startupScaleEvents:SetScript("OnEvent", function(self, event)
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    QueueStartupScaleApply(event == "PLAYER_LOGIN")
    UpdateGlobalScaleEvents()
end)
