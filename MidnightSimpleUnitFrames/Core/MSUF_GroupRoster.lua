local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local pairs, next, wipe, type = pairs, next, wipe, type
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local unpack = unpack or table.unpack
local math_min = math.min

local unitEventFrames = {}
local activeEvents = {}
local rosterUnits = {}
local rebuildScheduled = false
local combatQueue = {}

Group.unitEventFrames = unitEventFrames
Group.activeEvents = activeEvents
Group.rosterUnits = rosterUnits
Group.roster = Group.roster or { type = "solo", count = 0, units = {}, roles = {} }

local function FlushCombatQueue()
    if InCombatLockdown and InCombatLockdown() then return end
    for i = 1, #combatQueue do
        local entry = combatQueue[i]
        if entry and entry.fn then
            entry.fn(unpack(entry.args or {}))
        end
    end
    wipe(combatQueue)
end

function Group.DeferIfCombat(fn, ...)
    if InCombatLockdown and InCombatLockdown() then
        combatQueue[#combatQueue + 1] = { fn = fn, args = { ... } }
        return true
    end
    fn(...)
    return false
end

local function DispatchUnitEvent(event, unit, ...)
    local handlers = activeEvents[event]
    if not handlers then return end
    for owner, fn in next, handlers do
        fn(owner, event, unit, ...)
    end
end

local function RegisterRosterUnit(unit)
    if not unit then return end
    local f = unitEventFrames[unit]
    if not f then
        f = CreateFrame("Frame")
        f:Hide()
        f:SetScript("OnEvent", function(_, event, u, ...)
            DispatchUnitEvent(event, u, ...)
        end)
        unitEventFrames[unit] = f
    end
    f:UnregisterAllEvents()
    for event in pairs(activeEvents) do
        f:RegisterUnitEvent(event, unit)
    end
    rosterUnits[unit] = true
end

local function UnregisterRosterUnit(unit)
    local f = unitEventFrames[unit]
    if f then
        f:UnregisterAllEvents()
    end
    rosterUnits[unit] = nil
end

function Group.AddUnitEvent(owner, event, fn)
    if not owner or type(event) ~= "string" or type(fn) ~= "function" then return end
    local bucket = activeEvents[event]
    if not bucket then
        bucket = {}
        activeEvents[event] = bucket
    end
    bucket[owner] = fn
    for unit in pairs(rosterUnits) do
        local f = unitEventFrames[unit]
        if f then
            f:RegisterUnitEvent(event, unit)
        end
    end
end

function Group.RemoveUnitEvent(owner, event)
    local bucket = activeEvents[event]
    if not bucket then return end
    bucket[owner] = nil
    if next(bucket) then return end
    activeEvents[event] = nil
    for unit in pairs(rosterUnits) do
        local f = unitEventFrames[unit]
        if f then
            f:UnregisterEvent(event)
        end
    end
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

local function SortRosterUnits(a, b)
    local roles = Group.roster.roles
    local ra = roles[a] or "NONE"
    local rb = roles[b] or "NONE"
    local oa = ROLE_ORDER[ra] or 99
    local ob = ROLE_ORDER[rb] or 99
    if oa ~= ob then
        return oa < ob
    end
    return a < b
end

function Group.RebuildRoster()
    local roster = Group.roster
    local oldUnits = {}
    for unit in pairs(rosterUnits) do
        oldUnits[unit] = true
    end

    wipe(roster.units)
    wipe(roster.roles)

    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    roster.type = isRaid and "raid" or ((count > 0) and "party" or "solo")
    roster.count = 0

    if isRaid then
        for i = 1, count do
            local unit = "raid" .. i
            if UnitExists(unit) then
                roster.count = roster.count + 1
                roster.units[roster.count] = unit
                roster.roles[unit] = UnitGroupRolesAssigned(unit) or "NONE"
                RegisterRosterUnit(unit)
                oldUnits[unit] = nil
            end
        end
    elseif count > 0 then
        for i = 1, math_min(4, count - 1) do
            local unit = "party" .. i
            if UnitExists(unit) then
                roster.count = roster.count + 1
                roster.units[roster.count] = unit
                roster.roles[unit] = UnitGroupRolesAssigned(unit) or "NONE"
                RegisterRosterUnit(unit)
                oldUnits[unit] = nil
            end
        end
    end

    table.sort(roster.units, SortRosterUnits)

    for unit in pairs(oldUnits) do
        UnregisterRosterUnit(unit)
    end

    if type(Group.OnRosterChanged) == "function" then
        Group.OnRosterChanged(roster)
    end
end

local function ScheduleRosterRebuild()
    if rebuildScheduled then return end
    rebuildScheduled = true
    C_Timer.After(0.1, function()
        rebuildScheduled = false
        local groupDB = _G.MSUF_DB and _G.MSUF_DB.group
        if groupDB and groupDB.enabled == false then
            if type(_G.MSUF_HideAllGroupFrames) == "function" then
                _G.MSUF_HideAllGroupFrames()
            end
            if type(_G.MSUF_SyncBlizzardGroupFrames) == "function" then
                _G.MSUF_SyncBlizzardGroupFrames()
            end
            return
        end
        if type(_G.MSUF_EnsureGroupFrames) == "function" then
            _G.MSUF_EnsureGroupFrames()
        end
        Group.RebuildRoster()
        if type(_G.MSUF_SyncBlizzardGroupFrames) == "function" then
            _G.MSUF_SyncBlizzardGroupFrames()
        end
    end)
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_ROLES_ASSIGNED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        FlushCombatQueue()
        ScheduleRosterRebuild()
    else
        ScheduleRosterRebuild()
    end
end)

Group.ScheduleRosterRebuild = ScheduleRosterRebuild
Group.RegisterRosterUnit = RegisterRosterUnit
Group.UnregisterRosterUnit = UnregisterRosterUnit
