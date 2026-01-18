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
    handlers = {},  -- handlers[event][key] = { fn=..., once=bool }
    -- Internal: print-once error gate for safeCalls mode.
    _errOnce = {},
}

local driver = CreateFrame("Frame")
driver:Hide()

local function EnsureEventRegistered(event)
    -- We don't keep a refcount; we simply register on first handler and unregister when empty.
    if not driver:IsEventRegistered(event) then
        driver:RegisterEvent(event)
    end
end

local function MaybeUnregisterEvent(event)
    local t = bus.handlers[event]
    if not t then
        if driver:IsEventRegistered(event) then
            driver:UnregisterEvent(event)
        end
        return
    end
    -- Check if empty
    for _ in pairs(t) do
        return
    end
    bus.handlers[event] = nil
    if driver:IsEventRegistered(event) then
        driver:UnregisterEvent(event)
    end
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

    local ev = bus.handlers[event]
    if not ev then
        ev = {}
        bus.handlers[event] = ev
        EnsureEventRegistered(event)
    end

    ev[key] = { fn = fn, once = once and true or false }
    return true
end

function bus:Unregister(event, key)
    local ev = bus.handlers[event]
    if not ev then return end
    ev[key] = nil
    MaybeUnregisterEvent(event)
end

function bus:UnregisterAll(keyPrefix)
    if type(keyPrefix) ~= "string" or keyPrefix == "" then return end
    for event, ev in pairs(bus.handlers) do
        local changed = false
        for key in pairs(ev) do
            if key:sub(1, #keyPrefix) == keyPrefix then
                ev[key] = nil
                changed = true
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

local function CallHandler(key, fn, event, ...)
    if not bus.safeCalls then
        fn(event, ...)
        return
    end
    local ok, err = pcall(fn, event, ...)
    if not ok then
        _PrintSafeCallErrorOnce(event, key, err)
    end
end

driver:SetScript("OnEvent", function(_, event, ...)
    local ev = bus.handlers[event]
    if not ev then return end

    -- Snapshot keys for :once handlers because handlers may unregister themselves.
    -- Reuse a small array to reduce table churn during event storms.
    local toRemove = bus._toRemove
    if type(toRemove) ~= "table" then
        toRemove = {}
        bus._toRemove = toRemove
    end
    local removeCount = 0

    for key, h in pairs(ev) do
        if h and h.fn then
            CallHandler(key, h.fn, event, ...)
            if h.once then
                removeCount = removeCount + 1
                toRemove[removeCount] = key
            end
        end
    end

    if removeCount > 0 then
        for i = 1, removeCount do
            local k = toRemove[i]
            ev[k] = nil
            toRemove[i] = nil
        end
        MaybeUnregisterEvent(event)
    end
end)

-- Public globals (back-compat)
_G.MSUF_EventBus = bus

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
