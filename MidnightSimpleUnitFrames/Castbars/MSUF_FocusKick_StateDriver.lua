--- Castbars/MSUF_FocusKick_StateDriver.lua
--- Focus-kick ownership subscriber.
---
--- The regular focus castbar driver already owns the complete spellcast event
--- stream. This module subscribes only while the feature is enabled, suppresses
--- the source frame visually, and forwards the driver's canonical state to the
--- detached icon without registering a second event frame.

local G = _G
local _, ns = ...
ns = ns or G.MSUF_NS or {}

G.MSUF_FocusKickUseEngineDriver = true

local refreshQueued = false
local subscribed = false
local pendingState
local pendingStateSet = false
local OnEngineState

local function Engine()
    local engine = ns.MSUF_CastbarEngine
    if engine then return engine end
    local getter = G.MSUF_GetCastbarEngine
    return type(getter) == "function" and getter() or nil
end

local function FocusKickEnabled()
    local db = G.MSUF_DB
    if not db or not db.general then return false end
    if db.focus and db.focus.enabled == false then return false end

    local shouldUseMSUF = G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUseMSUF) == "function" and not shouldUseMSUF("focus", db.general) then
        return false
    end
    return db.general.enableFocusKickIcon == true
end

local function SetFocusCastbarSuppressed(suppressed)
    local focusCastbar = G.MSUF_FocusCastBar or G.MSUF_FocusCastbar
        or ((G.FocusCastBar and G.FocusCastBar._msufCastbarDriver == true) and G.FocusCastBar)
    if not (focusCastbar and focusCastbar.SetAlpha) then return end

    focusCastbar._msufFocusKickSuppressed = suppressed and true or nil
    if suppressed then
        focusCastbar:SetAlpha(0)
    elseif type(G.MSUF_UF_ApplyCastbarRangeAlpha) == "function" then
        G.MSUF_UF_ApplyCastbarRangeAlpha(focusCastbar, nil, true)
    else
        focusCastbar:SetAlpha(1)
    end
end

local function EnsureFocusKickUI()
    if G.__MSUF_FocusKickUIInit or type(G.MSUF_InitFocusKickIcon) ~= "function" then return end
    G.__MSUF_FocusKickUIInit = true
    G.MSUF_InitFocusKickIcon()
end

local function SetSubscribed(enabled)
    enabled = enabled and true or false
    if subscribed == enabled then return end

    local engine = Engine()
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
        if type(G.MSUF_FocusKick_ApplyCastState) == "function" then
            G.MSUF_FocusKick_ApplyCastState(nil)
        elseif G.MSUF_FocusKickIcon and G.MSUF_FocusKickIcon.Hide then
            G.MSUF_FocusKickIcon:Hide()
        end
        return
    end

    EnsureFocusKickUI()
    SetFocusCastbarSuppressed(true)
    if not stateProvided and state == nil and type(G.MSUF_BuildCastState) == "function" then
        state = G.MSUF_BuildCastState("focus")
    end
    if type(G.MSUF_FocusKick_ApplyCastState) == "function" then
        G.MSUF_FocusKick_ApplyCastState(state)
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
        and type(G.MSUF_FocusKick_PlayInterruptFeedback) == "function" then
        G.MSUF_FocusKick_PlayInterruptFeedback()
    end
    QueueRefresh(state, true)
end

G.MSUF_FocusKickDriver_ForceUpdate = function()
    local enabled = FocusKickEnabled()
    SetSubscribed(enabled)
    if not enabled then
        refreshQueued = false
        pendingState = nil
        pendingStateSet = false
        ApplyState(nil, true)
        return
    end
    QueueRefresh(nil, false)
end

if FocusKickEnabled() then
    SetSubscribed(true)
    G.C_Timer.After(0.2, G.MSUF_FocusKickDriver_ForceUpdate)
end
