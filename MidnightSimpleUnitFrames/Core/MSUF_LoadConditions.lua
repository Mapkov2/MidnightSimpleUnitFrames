-- Core/MSUF_LoadConditions.lua
-- Per-unit visibility conditions (mounted, vehicle, resting, combat, stealth, group, instance).
-- Secret-safe: uses ONLY standard boolean WoW API calls — no comparisons on secret/protected values.
-- Performance: purely event-driven with cached state, zero OnUpdate polling.
-- Loads AFTER MSUF_Alpha.lua in the TOC.
local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- Upvalue hot-path API (avoid global lookup on every evaluation)
-- ---------------------------------------------------------------------------
local type          = type
local IsMounted     = IsMounted
local IsResting     = IsResting
local IsStealthed   = IsStealthed
local IsInInstance  = IsInInstance
local IsInGroup     = IsInGroup
local IsInRaid      = IsInRaid
local UnitInVehicle = UnitInVehicle
local GetNumGroupMembers = GetNumGroupMembers
local InCombatLockdown   = InCombatLockdown
local pairs = pairs

-- ---------------------------------------------------------------------------
-- DB field names (per-unit, all false by default → never hide)
-- These are simple booleans stored directly in MSUF_DB[key].
-- ---------------------------------------------------------------------------
local LOAD_COND_FIELDS = {
    "loadCondHideMounted",
    "loadCondHideInVehicle",
    "loadCondHideResting",
    "loadCondHideInCombat",
    "loadCondHideOutOfCombat",
    "loadCondHideStealthed",
    "loadCondHideSolo",
    "loadCondHideInGroup",
    "loadCondHideInInstance",
}
_G.MSUF_LOAD_COND_FIELDS = LOAD_COND_FIELDS

-- ---------------------------------------------------------------------------
-- Cached player state — updated ONLY on events, never polled.
-- ---------------------------------------------------------------------------
local _state = {
    mounted   = false,
    vehicle   = false,
    resting   = false,
    combat    = false,
    stealthed = false,
    solo      = true,
    inGroup   = false,
    inRaid    = false,
    inInstance = false,
}

-- Snapshot current state from API (called once on init + per-event).
local function _RefreshMounted()
    _state.mounted = (IsMounted and IsMounted()) and true or false
end
local function _RefreshVehicle()
    _state.vehicle = (UnitInVehicle and UnitInVehicle("player")) and true or false
end
local function _RefreshResting()
    _state.resting = (IsResting and IsResting()) and true or false
end
local function _RefreshCombat()
    -- Prefer the cached global from MSUF_Alpha event frame; fall back to API.
    local v = _G.MSUF_InCombat
    if v == nil then
        v = (InCombatLockdown and InCombatLockdown()) and true or false
    end
    _state.combat = v and true or false
end
local function _RefreshStealth()
    _state.stealthed = (IsStealthed and IsStealthed()) and true or false
end
local function _RefreshGroup()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    _state.solo    = (n <= 1)
    _state.inRaid  = (IsInRaid and IsInRaid()) and true or false
    _state.inGroup = ((not _state.solo) and (not _state.inRaid)) and true or false
end
local function _RefreshInstance()
    local inInst = (IsInInstance and IsInInstance()) and true or false
    _state.inInstance = inInst
end

local function _RefreshAll()
    _RefreshMounted()
    _RefreshVehicle()
    _RefreshResting()
    _RefreshCombat()
    _RefreshStealth()
    _RefreshGroup()
    _RefreshInstance()
end

-- ---------------------------------------------------------------------------
-- Core evaluator: returns true if the frame for `key` should be hidden.
-- Zero allocation, zero secret-value access, pure boolean logic.
-- ---------------------------------------------------------------------------
local function MSUF_LoadCond_ShouldHide(key)
    if not key then return false end
    local db = _G.MSUF_DB
    if not db then return false end
    local conf = db[key]
    if not conf then return false end

    -- Fast-exit: if no load conditions are set, nothing to check.
    -- Each check is a simple boolean field read + cached state read.
    if conf.loadCondHideMounted     and _state.mounted   then return true end
    if conf.loadCondHideInVehicle   and _state.vehicle    then return true end
    if conf.loadCondHideResting     and _state.resting    then return true end
    if conf.loadCondHideInCombat    and _state.combat     then return true end
    if conf.loadCondHideOutOfCombat and (not _state.combat) then return true end
    if conf.loadCondHideStealthed   and _state.stealthed  then return true end
    if conf.loadCondHideSolo        and _state.solo       then return true end
    if conf.loadCondHideInGroup     and _state.inGroup    then return true end
    if conf.loadCondHideInInstance  and _state.inInstance  then return true end

    return false
end
_G.MSUF_LoadCond_ShouldHide = MSUF_LoadCond_ShouldHide

-- ---------------------------------------------------------------------------
-- Apply visibility to all unitframes.  Called when any tracked state changes.
-- Integrates with the existing alpha refresh cycle (MSUF_RefreshAllUnitAlphas).
-- The actual hide/show is handled by the hook in MSUF_ApplyUnitAlpha.
-- ---------------------------------------------------------------------------
local _pendingRefresh = false
local function _ScheduleRefresh()
    if _pendingRefresh then return end
    _pendingRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            _pendingRefresh = false
            local fn = _G.MSUF_RefreshAllUnitAlphas
            if type(fn) == "function" then fn() end
        end)
    else
        _pendingRefresh = false
        local fn = _G.MSUF_RefreshAllUnitAlphas
        if type(fn) == "function" then fn() end
    end
end

-- ---------------------------------------------------------------------------
-- Event handler — maps events to minimal state refreshes, then triggers apply.
-- ---------------------------------------------------------------------------
local _eventHandlers = {
    PLAYER_MOUNT_DISPLAY_CHANGED = function() _RefreshMounted();  _ScheduleRefresh() end,
    UNIT_ENTERED_VEHICLE         = function() _RefreshVehicle();  _ScheduleRefresh() end,
    UNIT_EXITED_VEHICLE          = function() _RefreshVehicle();  _ScheduleRefresh() end,
    PLAYER_UPDATE_RESTING        = function() _RefreshResting();  _ScheduleRefresh() end,
    PLAYER_REGEN_DISABLED        = function() _RefreshCombat();   _ScheduleRefresh() end,
    PLAYER_REGEN_ENABLED         = function() _RefreshCombat();   _ScheduleRefresh() end,
    UPDATE_STEALTH               = function() _RefreshStealth();  _ScheduleRefresh() end,
    GROUP_ROSTER_UPDATE          = function() _RefreshGroup();    _ScheduleRefresh() end,
    PLAYER_ENTERING_WORLD        = function() _RefreshAll();      _ScheduleRefresh() end,
}

-- ---------------------------------------------------------------------------
-- Boot: create the event frame, register all events, snapshot initial state.
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "MSUF_LoadCondEventFrame")
for ev in pairs(_eventHandlers) do
    eventFrame:RegisterEvent(ev)
end
eventFrame:SetScript("OnEvent", function(_, event)
    local handler = _eventHandlers[event]
    if handler then handler() end
end)

-- Initial state snapshot (safe even before login because APIs return defaults).
_RefreshAll()

-- Expose for debug / external modules.
_G.MSUF_LoadCond_State = _state
_G.MSUF_LoadCond_RefreshAll = function()
    _RefreshAll()
    _ScheduleRefresh()
end
