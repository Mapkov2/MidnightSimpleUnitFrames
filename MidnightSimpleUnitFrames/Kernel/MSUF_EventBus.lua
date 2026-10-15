--- MSUF_EventBus.lua - Global and unit-filtered event fanout.
--- API: MSUF_EventBus_Register(event, key, fn, unitFilter, once)
--- MSUF_EventBus_Unregister(event, key)
--- MSUF_EventBus_UnregisterAll(keyPrefix)
---
--- This keeps shared runtime events on one hidden driver frame. Unit events
--- (UNIT_* and the NONPREFIX_UNIT_EVENTS below) are registered with the union
--- of requested unit filters so modules do not each create their own event
--- frame for the same traffic. A unit event needs a unit filter.
local _, MSUF = ...
MSUF = MSUF or {}
local type, pairs = type, pairs
local unpack = unpack or table.unpack
-- Every subscriber runs through secureexecuterange (Blizzard's CallbackRegistry
-- dispatches with it on every client): a subscriber that raises goes to the
-- error handler and the rest of the fan-out still runs. A test harness that
-- lacks it gets a plain loop with the same order.
local RunEach = secureexecuterange
if type(RunEach) ~= "function" then
    RunEach = function(list, fn, ...)
        for i = 1, #list do fn(i, list[i], ...) end
    end
end

local bus = { handlers = {}, internalEvents = {} }
local driver = CreateFrame("Frame")
driver:Hide()
bus.driver = driver

-- Unit events whose first payload is a unit token although the name has no
-- UNIT_ prefix. The unit-frame engine classifies its frame subscriptions with
-- the same list (bus.IsUnitEvent), so a filter on one of these reaches
-- RegisterUnitEvent instead of being dropped.
local NONPREFIX_UNIT_EVENTS = {
    INCOMING_RESURRECT_CHANGED = true,
    -- AFK/DND flag edges for one unit despite the PLAYER_ prefix.
    PLAYER_FLAGS_CHANGED = true,
}

local function IsUnitEvent(event)
    return type(event) == "string" and (event:sub(1, 5) == "UNIT_" or NONPREFIX_UNIT_EVENTS[event] == true)
end
bus.IsUnitEvent = IsUnitEvent

local function NormalizeUnitFilter(unitFilter)
    if type(unitFilter) == "string" then
        if unitFilter ~= "" then return { [unitFilter] = true }, 1 end
        return nil, 0
    end
    if type(unitFilter) ~= "table" then return nil, 0 end

    local units, n = {}, 0
    for k, v in pairs(unitFilter) do
        local unit
        if type(v) == "string" then
            unit = v
        elseif v and type(k) == "string" then
            unit = k
        end
        if unit and unit ~= "" and not units[unit] then
            units[unit] = true
            n = n + 1
        end
    end
    if n == 0 then return nil, 0 end
    return units, n
end

local function BuildUnitList(ev)
    local list, seen = {}, {}
    local handlers = ev and ev.list
    if not handlers then return list end
    for i = 1, #handlers do
        local h = handlers[i]
        local units = h and h.fn and not h.dead and h.units
        if units then
            for unit in pairs(units) do
                if not seen[unit] then
                    seen[unit] = true
                    list[#list + 1] = unit
                end
            end
        end
    end
    return list
end

--- Rebuild the driver's event registration when unit filters change. For unit
--- events this is the only place that talks to RegisterUnitEvent.
local function RefreshDriverRegistration(event, ev)
    if not ev or bus.internalEvents[event] then return end
    if not ev.unitEvent then
        if not driver:IsEventRegistered(event) then driver:RegisterEvent(event) end
        return
    end

    if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
    local units = BuildUnitList(ev)
    if #units == 0 then return end
    --- RegisterUnitEvent reports failure by value (12.1 SimpleFrameAPI: it takes
    --- a variadic unit-token list and returns a bool). A silent false leaves the
    --- subscription missing, which stays invisible until the feature quietly
    --- stops updating, so surface it instead of discarding the result.
    if driver:RegisterUnitEvent(event, unpack(units)) == false then
        local report = MSUF.ReportError or _G.MSUF_ReportError
        if type(report) == "function" then
            report("EventBus", "RegisterUnitEvent refused '" .. tostring(event)
                .. "' for " .. #units .. " unit token(s)")
        end
    end
end

local function Compact(ev)
    if not ev.dirty then return end
    -- Existing dispatches retain their array; only subscription changes copy.
    -- Shared records are tombstoned immediately so cancelled callbacks stop.
    local list, index = {}, {}
    for i = 1, #ev.list do
        local handler = ev.list[i]
        if handler.fn and not handler.dead then
            list[#list + 1] = handler
            index[handler.key] = #list
        end
    end
    ev.list, ev.index, ev.dirty = list, index, false
end

local function MaybeUnregister(event)
    local ev = bus.handlers[event]
    if not ev then
        if not bus.internalEvents[event] and driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
        return
    end
    if ev.dirty then Compact(ev) end
    if #ev.list == 0 then
        bus.handlers[event] = nil
        if not bus.internalEvents[event] and driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
    elseif ev.unitEvent then
        RefreshDriverRegistration(event, ev)
    end
end

function bus:Register(event, key, fn, unitFilter, once)
    if type(event) ~= "string" or event == "" or type(key) ~= "string" or type(fn) ~= "function" then return false end
    local unitEvent = IsUnitEvent(event)
    local units
    if unitEvent then
        units = NormalizeUnitFilter(unitFilter)
        if not units then return false end
    end
    local ev = bus.handlers[event]
    if not ev then
        ev = { list = {}, index = {}, dirty = false, unitEvent = unitEvent }
        bus.handlers[event] = ev
    elseif ev.unitEvent ~= unitEvent then
        return false
    end
    local idx = ev.index[key]
    if idx then
        local h = ev.list[idx]
        if h then
            h.fn = fn
            h.once = once and true or false
            h.units = units
            h.dead = false
            RefreshDriverRegistration(event, ev)
            return true
        end
        ev.index[key] = nil
    end
    -- Copy-on-write like Compact: a dispatch in progress keeps walking the
    -- array it started with, which never gains a key while it runs.
    local old, list = ev.list, {}
    for i = 1, #old do list[i] = old[i] end
    local n = #list + 1
    list[n] = { key = key, fn = fn, once = once and true or false, dead = false, units = units }
    ev.list = list
    ev.index[key] = n
    RefreshDriverRegistration(event, ev)
    return true
end

function bus:Unregister(event, key)
    local ev = bus.handlers[event]
    local index = ev and ev.index[key]
    if not index then return end
    local handler = ev.list[index]
    handler.fn, handler.dead = nil, true
    ev.index[key], ev.dirty = nil, true
    MaybeUnregister(event)
end

function bus:UnregisterAll(prefix)
    if type(prefix) ~= "string" or prefix == "" then return end
    local length = #prefix
    for event, ev in pairs(bus.handlers) do
        for i = 1, #ev.list do
            local handler = ev.list[i]
            if handler.key:sub(1, length) == prefix then
                handler.fn, handler.dead = nil, true
                ev.index[handler.key], ev.dirty = nil, true
            end
        end
        if ev.dirty then MaybeUnregister(event) end
    end
end

-- Dispatch owns no mutable depth/cleanup state and allocates nothing. A thrown
-- callback reaches the client error handler and the next subscriber still
-- runs. Removing a once subscription before invocation also makes nested
-- delivery deterministic. Only unit events carry a unit filter.
local function Deliver(_, handler, event, ...)
    local callback, units = handler.fn, handler.units
    if callback then
        if units then
            local unit = ...
            if not (unit and units[unit] == true) then return end
        end
        if handler.once then bus:Unregister(event, handler.key) end
        callback(event, ...)
    end
end
-- Internal state delivery is superseded by a nested publication. The native
-- dispatcher below keeps its original fast path and instruction count.
local function DeliverInternal(index, handler, ev, revision, event, ...)
    if ev.revision ~= revision or bus.handlers[event] ~= ev then return end
    return Deliver(index, handler, event, ...)
end

function bus:Publish(event, ...)
    local ev = bus.handlers[event]
    if not ev then return end
    local list = ev.list
    -- A native event returns to the client dispatcher. Internal publishers
    -- must also finish their own lifecycle after a subscriber raises.
    if self.internalEvents[event] then
        ev.revision = (ev.revision or 0) + 1
        return RunEach(list, DeliverInternal, ev, ev.revision, event, ...)
    end
    if #list == 1 then return Deliver(1, list[1], event, ...) end
    RunEach(list, Deliver, event, ...)
end

function bus:DefineEvent(event)
    self.internalEvents[event] = true
end

-- Settings owners publish after applying, independently of the Options addon.
bus:DefineEvent("CONFIG_APPLIED")

-- Native dispatch retains its instruction budget; internal publication is a cold path.
driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]
    if not ev then return end
    local list = ev.list
    if #list == 1 then return Deliver(1, list[1], event, ...) end
    RunEach(list, Deliver, event, ...)
end)
--- Public API
local ExportPublic = MSUF.ExportPublic

local function EventBusRegister(e, k, f, u, o) return bus:Register(e, k, f, u, o) end
local function EventBusUnregister(e, k) return bus:Unregister(e, k) end
local function EventBusUnregisterAll(p) return bus:UnregisterAll(p) end

MSUF.EventBus = bus
MSUF.MSUF_EventBus = bus
ExportPublic("MSUF_EventBus", bus)
ExportPublic("MSUF_EventBus_Register", EventBusRegister)
ExportPublic("MSUF_EventBus_Unregister", EventBusUnregister)
ExportPublic("MSUF_EventBus_UnregisterAll", EventBusUnregisterAll)
return bus
