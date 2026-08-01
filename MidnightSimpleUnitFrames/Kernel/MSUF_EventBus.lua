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
    driver:RegisterUnitEvent(event, unpack(units))
end

local function Compact(ev)
    if not ev or not ev.dirty then return end
    local list, idx, w = ev.list, ev.index, 0
    for k in pairs(idx) do idx[k] = nil end
    for i = 1, #list do
        local h = list[i]
        if h and h.fn and not h.dead then
            w = w + 1; list[w] = h; idx[h.key] = w
        end
    end
    for i = w + 1, #list do list[i] = nil end
    ev.dirty = false
end

local function MaybeUnregister(event)
    local ev = bus.handlers[event]
    if not ev then
        if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
        return
    end
    if (ev.dd or 0) > 0 then return end
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
        ev = { list = {}, index = {}, dd = 0, dirty = false, unitEvent = unitEvent }
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
    local ev = bus.handlers[event]; if not ev then return end
    local idx = ev.index[key]; if not idx then return end
    ev.index[key] = nil
    if (ev.dd or 0) > 0 then
        local h = ev.list[idx]; if h then h.fn = nil; h.dead = true end; ev.dirty = true; return
    end
    local last = #ev.list
    if idx ~= last then
        local tail = ev.list[last]; ev.list[idx] = tail
        if tail and tail.key then ev.index[tail.key] = idx end
    end
    ev.list[last] = nil
    MaybeUnregister(event)
end

function bus:UnregisterAll(prefix)
    if type(prefix) ~= "string" or prefix == "" then return end
    local plen = #prefix
    for event, ev in pairs(bus.handlers) do
        local list, changed = ev.list, false
        if (ev.dd or 0) > 0 then
            for i = 1, #list do
                local h = list[i]
                if h and h.fn and h.key and h.key:sub(1, plen) == prefix then
                    ev.index[h.key] = nil; h.fn = nil; h.dead = true; changed = true
                end
            end
            if changed then ev.dirty = true end
        else
            local i = #list
            while i >= 1 do
                local h = list[i]
                if h and h.fn and h.key and h.key:sub(1, plen) == prefix then
                    ev.index[h.key] = nil
                    local last = #list
                    if i ~= last then
                        local tail = list[last]; list[i] = tail
                        if tail and tail.key then ev.index[tail.key] = i end
                    end
                    list[last] = nil; changed = true
                end
                i = i - 1
            end
        end
        if changed then MaybeUnregister(event) end
    end
end

--- Dispatch can unregister handlers while iterating: a handler may call
--- bus:Unregister, which reaches MaybeUnregister and would otherwise Compact the
--- list this loop is walking. `dd` marks "fanout in progress" so removals only
--- mark handlers dead, and compaction happens once the fanout finishes.
---
--- Each subscriber is an independent fault boundary. A broken handler is
--- reported through the normal error handler, while later subscribers and the
--- dispatch-depth/compaction bookkeeping still complete. `dd` remains a real
--- counter because tests and addon code can legitimately fire the same driver
--- recursively even though Blizzard event delivery itself is not recursive.
local function ReportHandlerError(err)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then
        local reported = pcall(handler, err)
        if reported then return end
    end
    if type(_G.print) == "function" then
        _G.print("|cffffd700MSUF EventBus:|r", tostring(err))
    end
end

local function InvokeHandler(fn, event, ...)
    local ok, err = pcall(fn, event, ...)
    if not ok then ReportHandlerError(err) end
end

driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]; if not ev then return end
    ev.dd = ev.dd + 1
    local list, n = ev.list, #ev.list

    if ev.unitEvent then
        local unit = ...
        for i = 1, n do
            local h = list[i]
            local fn = h and h.fn
            local units = h and h.units
            if fn and (not units or (unit and units[unit] == true)) then
                InvokeHandler(fn, event, ...)
                if h.once then ev.index[h.key] = nil; h.fn = nil; h.dead = true; ev.dirty = true end
            end
        end
    else
        for i = 1, n do
            local h = list[i]
            local fn = h and h.fn
            if fn then
                InvokeHandler(fn, event, ...)
                if h.once then ev.index[h.key] = nil; h.fn = nil; h.dead = true; ev.dirty = true end
            end
        end
    end

    ev.dd = ev.dd - 1
    if ev.dd <= 0 then
        ev.dd = 0
        if ev.dirty then Compact(ev) end
        if #ev.list == 0 then
            bus.handlers[event] = nil
            if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
        elseif ev.unitEvent then
            RefreshDriverRegistration(event, ev)
        end
    end
end)
--- Public API
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

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
