--- Castbars/MSUF_FocusKick_StateDriver.lua
--- Focus-kick ownership driver.
---
--- When the focus kick icon is enabled, this driver suppresses the regular focus
--- castbar, watches focus spellcast events, asks the CastbarEngine for current
--- cast-state, and hands that state to the icon UI. The icon file should stay
--- visual; backend decisions and event registration belong here.

local G = _G

G.MSUF_FocusKickUseEngineDriver = true

local FOCUS_CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local frame
local refreshQueued = false
local eventsRegistered = false
local lifecycleEventsRegistered = false

local function FocusKickEnabled()
    local db = G.MSUF_DB
    if not db or not db.general then
        return false
    end

    if db.focus and db.focus.enabled == false then
        return false
    end

    local shouldUseMSUF = G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUseMSUF) == "function" and not shouldUseMSUF("focus", db.general) then
        return false
    end

    return db.general.enableFocusKickIcon == true
end

--- Suppression uses alpha rather than destroying/hiding the focus castbar so the
--- cast-state plumbing and range-alpha refresh can still coexist safely.
local function SetFocusCastbarSuppressed(suppressed)
    local focusCastbar = G.MSUF_FocusCastBar or G.MSUF_FocusCastbar
        or ((G.FocusCastBar and G.FocusCastBar._msufCastbarDriver == true) and G.FocusCastBar)
    if focusCastbar and focusCastbar.SetAlpha then
        focusCastbar._msufFocusKickSuppressed = suppressed and true or nil
        if suppressed then
            focusCastbar:SetAlpha(0)
        elseif type(G.MSUF_UF_ApplyCastbarRangeAlpha) == "function" then
            G.MSUF_UF_ApplyCastbarRangeAlpha(focusCastbar, nil, true)
        else
            focusCastbar:SetAlpha(1)
        end
    end
end

local function EnsureFocusKickUI()
    if G.__MSUF_FocusKickUIInit then
        return
    end

    if type(G.MSUF_InitFocusKickIcon) ~= "function" then
        return
    end

    G.__MSUF_FocusKickUIInit = true
    G.MSUF_InitFocusKickIcon()
end

local function SetEventsRegistered(enabled)
    enabled = enabled and true or false
    if eventsRegistered == enabled then
        return
    end

    eventsRegistered = enabled
    if enabled then
        for index = 1, #FOCUS_CAST_EVENTS do
            frame:RegisterUnitEvent(FOCUS_CAST_EVENTS[index], "focus")
        end
    else
        for index = 1, #FOCUS_CAST_EVENTS do
            frame:UnregisterEvent(FOCUS_CAST_EVENTS[index])
        end
    end
end

local function SetLifecycleEventsRegistered(enabled)
    enabled = enabled and true or false
    if lifecycleEventsRegistered == enabled then return end
    lifecycleEventsRegistered = enabled
    if enabled then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    else
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        frame:UnregisterEvent("PLAYER_FOCUS_CHANGED")
    end
end

--- Recompute ownership and current cast-state. Event handlers queue this to the
--- next frame so several spellcast events from the same transition collapse into
--- one UI update.
local function Refresh()
    local enabled = FocusKickEnabled()
    SetEventsRegistered(enabled)
    SetLifecycleEventsRegistered(enabled)

    if enabled then
        EnsureFocusKickUI()
    end

    if not enabled then
        SetFocusCastbarSuppressed(false)

        if type(G.MSUF_FocusKick_ApplyCastState) == "function" then
            G.MSUF_FocusKick_ApplyCastState(nil)
        else
            local icon = G.MSUF_FocusKickIcon
            if icon and icon.Hide then
                icon:Hide()
            end
        end

        return
    end

    SetFocusCastbarSuppressed(true)

    local castState
    if type(G.MSUF_BuildCastState) == "function" then
        castState = G.MSUF_BuildCastState("focus")
    end

    if type(G.MSUF_FocusKick_ApplyCastState) == "function" then
        G.MSUF_FocusKick_ApplyCastState(castState)
    end
end

local function FlushQueuedRefresh()
    refreshQueued = false
    Refresh()
end

local function QueueRefresh()
    if refreshQueued then
        return
    end

    refreshQueued = true
    G.C_Timer.After(0, FlushQueuedRefresh)
end

frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_SPELLCAST_INTERRUPTED" and unit == "focus" then
        if FocusKickEnabled() and type(G.MSUF_FocusKick_PlayInterruptFeedback) == "function" then
            G.MSUF_FocusKick_PlayInterruptFeedback()
        end
    end

    QueueRefresh()
end)

G.MSUF_FocusKickDriver_ForceUpdate = function()
    if not FocusKickEnabled() then
        refreshQueued = false
        Refresh()
        return
    end
    QueueRefresh()
end

if FocusKickEnabled() then G.C_Timer.After(0.2, QueueRefresh) end
