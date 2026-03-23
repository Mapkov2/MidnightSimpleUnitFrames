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
-- IMPORTANT: Only called when conf.loadCondActive == true (Alpha hook gate).
-- ---------------------------------------------------------------------------
local function MSUF_LoadCond_ShouldHide(key)
    if not key then return false end
    -- Edit Mode bypass: never hide frames while user is positioning/dragging.
    if _G.MSUF_UnitEditModeActive then return false end
    local db = _G.MSUF_DB
    if not db then return false end
    local conf = db[key]
    if not conf then return false end

    -- Each check is a simple boolean field read + cached state read.
    if conf.loadCondHideMounted     and _state.mounted   then return true end
    if conf.loadCondHideInVehicle   and _state.vehicle    then return true end
    if conf.loadCondHideResting     and _state.resting    then return true end
    -- Combat: read MSUF_InCombat directly instead of cached _state.combat.
    -- The Alpha event frame fires PLAYER_REGEN_* before our event frame (TOC order),
    -- so _state.combat can be stale by one frame when MSUF_RefreshAllUnitAlphas runs.
    -- Reading the global eliminates this race entirely.
    local inCombat = (_G.MSUF_InCombat == true)
    if conf.loadCondHideInCombat    and inCombat       then return true end
    if conf.loadCondHideOutOfCombat and (not inCombat)  then return true end
    if conf.loadCondHideStealthed   and _state.stealthed  then return true end
    if conf.loadCondHideSolo        and _state.solo       then return true end
    if conf.loadCondHideInGroup     and _state.inGroup    then return true end
    if conf.loadCondHideInInstance  and _state.inInstance  then return true end

    return false
end
_G.MSUF_LoadCond_ShouldHide = MSUF_LoadCond_ShouldHide

-- ---------------------------------------------------------------------------
-- loadCondActive flag: set to true when ANY condition is checked for a unit,
-- false/nil when all unchecked.  The Alpha hook reads this single boolean
-- BEFORE calling ShouldHide → zero function-call overhead when unused.
-- ---------------------------------------------------------------------------
local function MSUF_LoadCond_RecomputeActive(conf)
    if not conf then return end
    local active = (conf.loadCondHideMounted == true)
                or (conf.loadCondHideInVehicle == true)
                or (conf.loadCondHideResting == true)
                or (conf.loadCondHideInCombat == true)
                or (conf.loadCondHideOutOfCombat == true)
                or (conf.loadCondHideStealthed == true)
                or (conf.loadCondHideSolo == true)
                or (conf.loadCondHideInGroup == true)
                or (conf.loadCondHideInInstance == true)
    conf.loadCondActive = active or false
end
_G.MSUF_LoadCond_RecomputeActive = MSUF_LoadCond_RecomputeActive

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

-- ---------------------------------------------------------------------------
-- Boot-time loadCondActive recompute: ensures the fast-path flag is correct
-- even after profile import/load where the flag might not have been set.
-- Runs once on PLAYER_ENTERING_WORLD after MSUF_DB is guaranteed to exist.
-- ---------------------------------------------------------------------------
do
    local _bootDone = false
    local _UNIT_KEYS = { "player", "target", "focus", "pet", "boss", "targettarget" }
    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bootFrame:SetScript("OnEvent", function(self)
        if _bootDone then return end
        _bootDone = true
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return end
        for i = 1, #_UNIT_KEYS do
            local conf = db[_UNIT_KEYS[i]]
            if type(conf) == "table" then
                MSUF_LoadCond_RecomputeActive(conf)
            end
        end
    end)
end

-- Expose for debug / external modules.
_G.MSUF_LoadCond_State = _state
_G.MSUF_LoadCond_RefreshAll = function()
    _RefreshAll()
    _ScheduleRefresh()
end

-- ---------------------------------------------------------------------------
-- Edit Mode exit hook: post-hook MSUF_RefreshAllUnitVisibilityDrivers.
-- When forceShow transitions to false (Edit Mode deactivation), schedule an
-- alpha refresh so load conditions apply immediately without waiting for the
-- next event.  This is a one-time hook installed at boot — zero runtime cost
-- when Edit Mode is not in use.
-- ---------------------------------------------------------------------------
do
    local _hooked = false
    local _origVisDriverFn = nil
    local function _TryHookVisDrivers()
        if _hooked then return end
        local orig = _G.MSUF_RefreshAllUnitVisibilityDrivers
        if type(orig) ~= "function" then return end
        _origVisDriverFn = orig
        _hooked = true
        _G.MSUF_RefreshAllUnitVisibilityDrivers = function(forceShow, ...)
            _origVisDriverFn(forceShow, ...)
            -- When exiting Edit Mode (forceShow=false), trigger alpha refresh.
            -- This ensures load conditions + alpha sliders re-evaluate immediately.
            if (not forceShow) and (not _G.MSUF_UnitEditModeActive) then
                _ScheduleRefresh()
            end
        end
    end
    -- The visibility driver function is defined in MidnightSimpleUnitFrames.lua (earlier in TOC).
    -- Try to hook immediately; if not yet available, defer to PLAYER_ENTERING_WORLD.
    _TryHookVisDrivers()
    if not _hooked then
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        hookFrame:SetScript("OnEvent", function(self)
            _TryHookVisDrivers()
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end)
    end
end
