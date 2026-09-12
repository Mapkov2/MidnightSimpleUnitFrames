--- MSUF_EventBus.lua - Global and unit-filtered event fanout.
--- API: MSUF_EventBus_Register(event, key, fn, unitFilter, once)
--- MSUF_EventBus_Unregister(event, key)
--- MSUF_EventBus_UnregisterAll(keyPrefix)
---
--- This keeps shared runtime events on one hidden driver frame. UNIT_* events
--- are registered with the union of requested unit filters so modules do not
--- each create their own event frame for the same traffic.
local _, MSUF = ...
MSUF = MSUF or {}
local type, pairs = type, pairs
local unpack = unpack or table.unpack

local bus = { handlers = {} }
local driver = CreateFrame("Frame")
driver:Hide()
bus.driver = driver

local function IsUnitEvent(event)
    return type(event) == "string" and event:sub(1, 5) == "UNIT_"
end

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

--- Rebuild the driver's event registration when unit filters change. For UNIT_*
--- events this is the only place that talks to RegisterUnitEvent.
local function RefreshDriverRegistration(event, ev)
    if not ev then return end
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
        if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
        return
    end
    if ev.dirty then Compact(ev) end
    if #ev.list == 0 then
        bus.handlers[event] = nil
        if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
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
    local n = #ev.list + 1
    ev.list[n] = { key = key, fn = fn, once = once and true or false, dead = false, units = units }
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

-- Dispatch owns no mutable depth/cleanup state. A thrown callback reaches the
-- client error handler normally; subsequent events remain usable. Removing a
-- once subscription before invocation also makes nested delivery deterministic.
driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]
    if not ev then return end
    local list, unit = ev.list, ...
    for i = 1, #list do
        local handler = list[i]
        local callback, units = handler.fn, handler.units
        if callback and (not ev.unitEvent or not units or (unit and units[unit] == true)) then
            if handler.once then bus:Unregister(event, handler.key) end
            callback(event, ...)
        end
    end
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
