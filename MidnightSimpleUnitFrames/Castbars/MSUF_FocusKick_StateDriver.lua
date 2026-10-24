--- Focus-kick ownership subscriber.
---
--- The regular focus castbar driver already owns the complete spellcast event
--- stream. This module subscribes only while the feature is enabled, suppresses
--- the source frame visually, and forwards the driver's canonical state to the
--- detached icon without registering a second event frame.

local G = _G
local _, ns = ...
local Castbars = ns.Require("MSUF", "Castbars/MSUF_FocusKick_StateDriver.lua").Castbars
local Config = Castbars.Config
local Backend = Castbars.Backend
local Engine = Castbars.Engine
local FocusDriver = Castbars.FocusDriver
local FocusKick = Castbars.FocusKick
local Frames = Castbars.Frames

FocusDriver.FocusKickUseEngineDriver = true

local refreshQueued = false
local subscribed = false
local pendingState
local pendingStateSet = false
local OnEngineState

local function GetEngine()
    return Engine
end

local function FocusKickEnabled()
    local record = Config.Read("focus")
    return record.enabled and record.unit.enabled ~= false and record.general.enableFocusKickIcon == true
end

local function FocusKickShowsCastbar()
    local db = Config.Read()
    return db and db.general and db.general.focusKickShowCastbar == true
end

local function SetFocusCastbarSuppressed(suppressed)
    local focusCastbar = Frames.focus
    if not (focusCastbar and focusCastbar.SetAlpha) then return end

    focusCastbar._msufFocusKickSuppressed = suppressed and true or nil
    if suppressed then
        focusCastbar:SetAlpha(0)
        return
    end
    -- Releasing the source frame returns it to the range-fade alpha, not to 1.
    local applyRangeAlpha = ns.Optional("MSUF_UF_ApplyCastbarRangeAlpha")
    if applyRangeAlpha then
        applyRangeAlpha(focusCastbar, nil, true)
    else
        focusCastbar:SetAlpha(1)
    end
end

local function EnsureFocusKickUI()
    if ns.PublicGlobals.__MSUF_FocusKickUIInit or type(FocusKick.InitFocusKickIcon) ~= "function" then return end
    ns.ExportPublic("__MSUF_FocusKickUIInit", true)
    FocusKick.InitFocusKickIcon()
end

local function SetSubscribed(enabled)
    enabled = enabled and true or false
    if subscribed == enabled then return end

    local engine = GetEngine()
    if not engine then return end
    if enabled and type(engine.Subscribe) == "function" then
        subscribed = engine:Subscribe("focus", OnEngineState) == true
    elseif not enabled and type(engine.Unsubscribe) == "function" then
        engine:Unsubscribe("focus", OnEngineState)
        subscribed = false
    end
end

local function ApplyState(state, stateProvided)
    local enabled = FocusKickEnabled()
    SetSubscribed(enabled)
    if not enabled then
        SetFocusCastbarSuppressed(false)
        if type(FocusKick.FocusKick_ApplyCastState) == "function" then
            FocusKick.FocusKick_ApplyCastState(nil)
        elseif Frames.Get("focusKick") and Frames.Get("focusKick").Hide then
            Frames.Get("focusKick"):Hide()
        end
        return
    end

    EnsureFocusKickUI()
    SetFocusCastbarSuppressed(not FocusKickShowsCastbar())
    if not stateProvided and state == nil and type(Engine.BuildCastState) == "function" then
        state = Engine.BuildCastState("focus")
    end
    if type(FocusKick.FocusKick_ApplyCastState) == "function" then
        FocusKick.FocusKick_ApplyCastState(state)
    end
end

local function FlushQueuedRefresh()
    refreshQueued = false
    local state = pendingStateSet and pendingState or nil
    local stateProvided = pendingStateSet
    pendingState = nil
    pendingStateSet = false
    ApplyState(state, stateProvided)
end

local function QueueRefresh(state, stateProvided)
    pendingState = state
    pendingStateSet = stateProvided == true
    if refreshQueued then return end
    refreshQueued = true
    G.C_Timer.After(0, FlushQueuedRefresh)
end

OnEngineState = function(state, event)
    if not FocusKickEnabled() then
        SetSubscribed(false)
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED"
        and type(FocusKick.FocusKick_PlayInterruptFeedback) == "function" then
        FocusKick.FocusKick_PlayInterruptFeedback()
    end
    QueueRefresh(state, true)
end

FocusDriver.FocusKickDriver_ForceUpdate = function()
    local enabled = FocusKickEnabled()
    SetSubscribed(enabled)
    if not enabled then
        refreshQueued = false
        pendingState = nil
        pendingStateSet = false
        ApplyState(nil, true)
        return
    end
    SetFocusCastbarSuppressed(not FocusKickShowsCastbar())
    QueueRefresh(nil, false)
end

-- No subscription at file load: the SavedVariables are not loaded yet, so the
-- profile read here answered nil (the tracker off) and subscribed nothing. The
-- unit frame spawn at PLAYER_LOGIN (Factory.SpawnAll) runs
-- MSUF_FocusKickDriver_ForceUpdate with the saved profile, and every castbar
-- settings change after it does too (MSUF_Castbars_OnSettingsChanged).

Castbars.PublicAPI.Publish("MSUF_FocusKickDriver_ForceUpdate", FocusDriver.FocusKickDriver_ForceUpdate)
