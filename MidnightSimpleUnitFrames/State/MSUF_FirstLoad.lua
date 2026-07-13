--- MidnightSimpleUnitFrames 6.0 first-load lifecycle.
---
--- This file intentionally loads before any code that normalizes the SavedVariables.
--- Raw SavedVariable presence is the only reliable way to distinguish a clean install
--- from an upgrade without touching the active profile.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type, tostring = type, tostring
local time = time

local REVISION = 1
local VALID_STATUS = {
    pending = true,
    active = true,
    later = true,
    completed = true,
    dismissed = true,
}
local TERMINAL_STATUS = {
    completed = true,
    dismissed = true,
}

-- SavedVariables are available before the first addon Lua file runs. Capture this
-- before Defaults/Profiles create their normal tables. Any prior payload, including
-- a malformed one, is treated as an upgrade so existing users never enter the clean-
-- install path by accident.
local hadSavedState = rawget(_G, "MSUF_DB") ~= nil or rawget(_G, "MSUF_GlobalDB") ~= nil

local globalDB = rawget(_G, "MSUF_GlobalDB")
if type(globalDB) ~= "table" then
    globalDB = {}
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then
    globalDB.global = {}
end

local function Now()
    return type(time) == "function" and time() or 0
end

local function AddonVersion()
    local api = _G.C_AddOns
    local value
    if type(api) == "table" and type(api.GetAddOnMetadata) == "function" then
        value = api.GetAddOnMetadata(addonName, "Version")
    elseif type(_G.GetAddOnMetadata) == "function" then
        value = _G.GetAddOnMetadata(addonName, "Version")
    end
    return tostring(value or "6.0")
end

local state = globalDB.global.firstLoad6
if type(state) ~= "table" or state.revision ~= REVISION then
    state = {
        schema = 1,
        revision = REVISION,
        installKind = hadSavedState and "upgrade" or "fresh",
        status = "pending",
        step = "welcome",
        firstSeenVersion = AddonVersion(),
        firstSeenAt = Now(),
    }
    globalDB.global.firstLoad6 = state
else
    state.schema = 1
    state.installKind = state.installKind == "fresh" and "fresh" or "upgrade"
    if not VALID_STATUS[state.status] then
        state.status = "pending"
    end
    if type(state.step) ~= "string" or state.step == "" then
        state.step = "welcome"
    end
    if type(state.firstSeenVersion) ~= "string" or state.firstSeenVersion == "" then
        state.firstSeenVersion = AddonVersion()
    end
end

local FirstLoad = MSUF.FirstLoad6 or {}
MSUF.FirstLoad6 = FirstLoad

-- Session-only by design. "Not now" hides the scene until the next reload but
-- remains pending account-wide so it can be offered again later.
FirstLoad.deferredThisSession = false

function FirstLoad:GetState()
    return state
end

function FirstLoad:GetInstallKind()
    return state.installKind
end

function FirstLoad:IsTerminal()
    return TERMINAL_STATUS[state.status] == true
end

function FirstLoad:ShouldShowDashboard()
    if self.deferredThisSession then
        return false
    end
    -- Once the full guided setup owns the flow, reopening /msuf must resume
    -- the tour rather than sending the player back to the welcome decision.
    if state.status == "active" and state.step == "guided_tour" then
        local tour = MSUF and MSUF.GuidedTour6
        if type(tour) == "table" and type(tour.IsActive) == "function" and tour:IsActive() then
            return false
        end
    end
    return state.status == "pending" or state.status == "active" or state.status == "later"
end

local function Transition(status, step)
    if not VALID_STATUS[status] then
        return false
    end
    state.status = status
    if type(step) == "string" and step ~= "" then
        state.step = step
    end
    state.updatedAt = Now()
    return true
end

function FirstLoad:Start(step)
    -- Completion/dismissal closes only the one-time onboarding lifecycle. The
    -- independent Guided Setup controller may still start again from the
    -- normal Dashboard without reviving this welcome scene.
    if self:IsTerminal() then return false, state.status end
    self.deferredThisSession = false
    return Transition("active", step or "personalize")
end

function FirstLoad:DeferForSession(step)
    if self:IsTerminal() then return false, state.status end
    local changed = Transition("later", step or "welcome")
    self.deferredThisSession = true
    return changed
end

function FirstLoad:Complete(step)
    self.deferredThisSession = false
    state.completedAt = Now()
    return Transition("completed", step or "defaults")
end

function FirstLoad:Dismiss(step)
    self.deferredThisSession = false
    state.dismissedAt = Now()
    return Transition("dismissed", step or "full_settings")
end
