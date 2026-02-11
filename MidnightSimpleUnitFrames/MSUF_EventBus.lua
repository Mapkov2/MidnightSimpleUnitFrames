-- MSUF_EventBus.lua
-- Midnight Simple Unit Frames (MSUF)
-- Step 4: Global Fanout ONLY
--
-- Design rules:
--   * This bus is for GLOBAL events only (roster, raid markers, CVARs, login/combat state, etc.).
--   * Unitframes MUST NOT register UNIT_* events through the bus.
--   * Handlers should set Dirty Bits / schedule work, never do heavy rendering here.
--
-- Backwards-compatible API:
--   MSUF_EventBus_Register(event, key, fn, unitFilter, once)
--   MSUF_EventBus_Unregister(event, key)
--
-- Notes:
--   * unitFilter is ignored (and UNIT_* registrations are rejected) by design.
--   * safeCalls: if true, handler invocations are protected (pcall). Defaults to false for speed.
--
-- Perf notes:
--   * Hot path avoids pairs() over handler maps. Each event stores handlers in a dense numeric array.
--   * Unregister during dispatch is supported: handlers are marked dead and compacted after dispatch.

local addonName, ns = ...
ns = ns or {}

local _G = _G
local type = _G.type
local pairs = _G.pairs
local tostring = _G.tostring
local pcall = _G.pcall

local CreateFrame = _G.CreateFrame

local function IsUnitEvent(event)
    return type(event) == "string" and event:sub(1, 5) == "UNIT_"
end

-- One-time warning per event
local warnedUnitEvents = {}

local function WarnUnitEvent(event, key)
    if warnedUnitEvents[event] then return end
    warnedUnitEvents[event] = true
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555MSUF: EventBus refused UNIT_* event|r "..tostring(event).." (key="..tostring(key).."). Register unit events directly on the frame (oUF-style).")
    end
end

local bus = {
    safeCalls = false,
    -- handlers[event] = {
    --   list = { { key=string, fn=function, once=bool, dead=bool }, ... },
    --   index = { [key]=pos },
    --   dispatchDepth = number,
    --   dirty = bool,
    -- }
    handlers = {},
    -- Internal: print-once error gate for safeCalls mode.
    _errOnce = {},
}

-- Dispatch strategy (hot path): avoid per-handler branching and keep pcall
-- completely off the fast path unless explicitly enabled for debugging.
--
-- Note: Don't inline pcall behind a flag check inside the per-handler loop.
-- Even when safeCalls is false, that check still costs in event storms.

local driver = CreateFrame("Frame")
driver:Hide()

local function EnsureEventRegistered(event)
    -- We don't keep a refcount; we simply register on first handler and unregister when empty.
    if not driver:IsEventRegistered(event) then
        driver:RegisterEvent(event)
    end
end

local function _Ev_Compact(ev)
    if not ev or not ev.dirty then return end

    local list = ev.list
    local idx = ev.index

    -- Clear index (compaction is rare; correctness > micro perf here).
    for k in pairs(idx) do
        idx[k] = nil
    end

    local write = 0
    local n = #list
    for i = 1, n do
        local h = list[i]
        if h and h.fn and not h.dead then
            write = write + 1
            if write ~= i then
                list[write] = h
            end
            idx[h.key] = write
        end
    end
    for i = write + 1, n do
        list[i] = nil
    end
    ev.dirty = false
end

local function MaybeUnregisterEvent(event)
    local ev = bus.handlers[event]
    if not ev then
        if driver:IsEventRegistered(event) then
            driver:UnregisterEvent(event)
        end
        return
    end

    -- Don't unregister mid-dispatch; defer to the dispatcher epilogue.
    if (ev.dispatchDepth or 0) > 0 then
        return
    end

    if ev.dirty then
        _Ev_Compact(ev)
    end
    if #ev.list == 0 then
        bus.handlers[event] = nil
        if driver:IsEventRegistered(event) then
            driver:UnregisterEvent(event)
        end
    end
end

local function _EnsureEventTable(event)
    local ev = bus.handlers[event]
    if not ev then
        ev = { list = {}, index = {}, dispatchDepth = 0, dirty = false }
        bus.handlers[event] = ev
        EnsureEventRegistered(event)
    end
    return ev
end

function bus:Register(event, key, fn, unitFilter, once)
    if type(event) ~= "string" or event == "" then return false end
    if type(key) ~= "string" or key == "" then return false end
    if type(fn) ~= "function" then return false end

    -- Hard rule: no UNIT_* on the EventBus (Step 4)
    if IsUnitEvent(event) then
        WarnUnitEvent(event, key)
        return false
    end

    local ev = _EnsureEventTable(event)
    local idx = ev.index[key]

    if idx then
        local h = ev.list[idx]
        if h then
            h.fn = fn
            h.once = once and true or false
            h.dead = false
            return true
        end
        -- Corrupt index (shouldn't happen), heal.
        ev.index[key] = nil
    end

    local list = ev.list
    local n = #list + 1
    list[n] = { key = key, fn = fn, once = once and true or false, dead = false }
    ev.index[key] = n
    return true
end

function bus:Unregister(event, key)
    local ev = bus.handlers[event]
    if not ev then return end

    local idx = ev.index[key]
    if not idx then return end

    local list = ev.list
    local h = list[idx]

    -- Remove index entry first so we can suppress calls later in the same dispatch.
    ev.index[key] = nil

    if (ev.dispatchDepth or 0) > 0 then
        -- Mark dead; will be compacted after dispatch.
        if h then
            h.fn = nil
            h.once = false
            h.dead = true
        end
        ev.dirty = true
        return
    end

    -- Swap-remove to keep list dense.
    local last = #list
    if idx ~= last then
        local tail = list[last]
        list[idx] = tail
        if tail and tail.key then
            ev.index[tail.key] = idx
        end
    end
    list[last] = nil

    MaybeUnregisterEvent(event)
end

function bus:UnregisterAll(keyPrefix)
    if type(keyPrefix) ~= "string" or keyPrefix == "" then return end
    local plen = #keyPrefix

    for event, ev in pairs(bus.handlers) do
        local list = ev.list
        local changed = false

        if (ev.dispatchDepth or 0) > 0 then
            -- Dispatching: mark dead; compact after dispatch.
            for i = 1, #list do
                local h = list[i]
                if h and h.fn and h.key and h.key:sub(1, plen) == keyPrefix then
                    ev.index[h.key] = nil
                    h.fn = nil
                    h.once = false
                    h.dead = true
                    changed = true
                end
            end
            if changed then
                ev.dirty = true
            end
        else
            -- Not dispatching: swap-remove in a reverse loop.
            local i = #list
            while i >= 1 do
                local h = list[i]
                if h and h.fn and h.key and h.key:sub(1, plen) == keyPrefix then
                    ev.index[h.key] = nil
                    local last = #list
                    if i ~= last then
                        local tail = list[last]
                        list[i] = tail
                        if tail and tail.key then
                            ev.index[tail.key] = i
                        end
                    end
                    list[last] = nil
                    changed = true
                end
                i = i - 1
            end
        end

        if changed then
            MaybeUnregisterEvent(event)
        end
    end
end

local function _PrintSafeCallErrorOnce(event, key, err)
    -- Only used when bus.safeCalls == true.
    -- Avoid spamming; keep one line per (event,key) pair.
    local eo = bus._errOnce
    if type(eo) ~= "table" then
        eo = {}
        bus._errOnce = eo
    end
    local gate = tostring(event) .. "|" .. tostring(key)
    if eo[gate] then
        return
    end
    eo[gate] = true

    local msg = "|cffff5555MSUF EventBus handler error|r in '" .. tostring(event) .. "' (key=" .. tostring(key) .. "): " .. tostring(err)
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    elseif _G.print then
        _G.print(msg)
    end
end

local function _DispatchFast(_, fn, event, ...)
    fn(event, ...)
end

local function _DispatchSafe(key, fn, event, ...)
    local ok, err = pcall(fn, event, ...)
    if not ok then
        _PrintSafeCallErrorOnce(event, key, err)
    end
end

function bus:SetSafeCalls(enabled)
    enabled = enabled and true or false
    bus.safeCalls = enabled
end

driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]
    if not ev then return end

    local dispatch = bus.safeCalls and _DispatchSafe or _DispatchFast

    ev.dispatchDepth = (ev.dispatchDepth or 0) + 1

    -- Snapshot current list length. Handlers registered during dispatch run next event.
    local list = ev.list
    local n = #list
    for i = 1, n do
        local h = list[i]
        if h and h.fn then
            dispatch(h.key, h.fn, event, ...)
            if h.once then
                -- :once handlers are removed after they fire.
                ev.index[h.key] = nil
                h.fn = nil
                h.once = false
                h.dead = true
                ev.dirty = true
            end
        end
    end

    ev.dispatchDepth = (ev.dispatchDepth or 0) - 1
    if ev.dispatchDepth <= 0 then
        ev.dispatchDepth = 0
        if ev.dirty then
            _Ev_Compact(ev)
        end
        if #ev.list == 0 then
            bus.handlers[event] = nil
            if driver:IsEventRegistered(event) then
                driver:UnregisterEvent(event)
            end
        end
    end
end)

-- Public globals (back-compat)
_G.MSUF_EventBus = bus

-- Optional debug toggle (off by default). Kept as a global helper so it can
-- be enabled quickly via /run without touching internal module state.
_G.MSUF_EventBus_SetSafeCalls = function(enabled)
    return bus:SetSafeCalls(enabled)
end

_G.MSUF_EventBus_Register = function(event, key, fn, unitFilter, once)
    return bus:Register(event, key, fn, unitFilter, once)
end

_G.MSUF_EventBus_Unregister = function(event, key)
    return bus:Unregister(event, key)
end

_G.MSUF_EventBus_UnregisterAll = function(keyPrefix)
    return bus:UnregisterAll(keyPrefix)
end

-- Namespaced export too (some modules use ns)
ns.MSUF_EventBus = bus

return bus
