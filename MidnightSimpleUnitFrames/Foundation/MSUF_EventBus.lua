-- MSUF_EventBus.lua — Global event fanout (no UNIT_* events).
-- API: MSUF_EventBus_Register(event, key, fn, unitFilter, once)
--      MSUF_EventBus_Unregister(event, key)
--      MSUF_EventBus_UnregisterAll(keyPrefix)
local _, ns = ...
ns = ns or {}
local type, pairs, pcall, tostring = type, pairs, pcall, tostring

local bus = { safeCalls = false, handlers = {}, _errOnce = {} }
local driver = CreateFrame("Frame")
driver:Hide()
bus.driver = driver

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
    end
end

function bus:Register(event, key, fn, _, once)
    if type(event) ~= "string" or event == "" or type(key) ~= "string" or type(fn) ~= "function" then return false end
    if event:sub(1, 5) == "UNIT_" then return false end
    local ev = bus.handlers[event]
    if not ev then
        ev = { list = {}, index = {}, dd = 0, dirty = false }
        bus.handlers[event] = ev
        driver:RegisterEvent(event)
    end
    local idx = ev.index[key]
    if idx then
        local h = ev.list[idx]
        if h then h.fn = fn; h.once = once and true or false; h.dead = false; return true end
        ev.index[key] = nil
    end
    local n = #ev.list + 1
    ev.list[n] = { key = key, fn = fn, once = once and true or false, dead = false }
    ev.index[key] = n
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

driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]; if not ev then return end
    ev.dd = (ev.dd or 0) + 1
    local list, n, safe = ev.list, #ev.list, bus.safeCalls
    for i = 1, n do
        local h = list[i]
        if h and h.fn then
            if safe then
                local ok, err = pcall(h.fn, event, ...)
                if not ok then
                    local gate = event .. "|" .. (h.key or "")
                    if not bus._errOnce[gate] then
                        bus._errOnce[gate] = true
                        if _G.print then _G.print("|cffff5555MSUF EventBus error|r " .. gate .. ": " .. tostring(err)) end
                    end
                end
            else
                h.fn(event, ...)
            end
            if h.once then ev.index[h.key] = nil; h.fn = nil; h.dead = true; ev.dirty = true end
        end
    end
    ev.dd = (ev.dd or 0) - 1
    if ev.dd <= 0 then
        ev.dd = 0
        if ev.dirty then Compact(ev) end
        if #ev.list == 0 then
            bus.handlers[event] = nil
            if driver:IsEventRegistered(event) then driver:UnregisterEvent(event) end
        end
    end
end)
-- Public API
_G.MSUF_EventBus = bus
_G.MSUF_EventBus_Register = function(e, k, f, u, o) return bus:Register(e, k, f, u, o) end
_G.MSUF_EventBus_Unregister = function(e, k) return bus:Unregister(e, k) end
_G.MSUF_EventBus_UnregisterAll = function(p) return bus:UnregisterAll(p) end
_G.MSUF_EventBus_SetSafeCalls = function(v) bus.safeCalls = v and true or false end
ns.MSUF_EventBus = bus
return bus
