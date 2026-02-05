--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua"); -- MSUF_EventBus.lua
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

local function IsUnitEvent(event) Perfy_Trace(Perfy_GetTime(), "Enter", "IsUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:29:6");
    return Perfy_Trace_Passthrough("Leave", "IsUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:29:6", type(event) == "string" and event:sub(1, 5) == "UNIT_")
end

-- One-time warning per event
local warnedUnitEvents = {}

local function WarnUnitEvent(event, key) Perfy_Trace(Perfy_GetTime(), "Enter", "WarnUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:36:6");
    if warnedUnitEvents[event] then Perfy_Trace(Perfy_GetTime(), "Leave", "WarnUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:36:6"); return end
    warnedUnitEvents[event] = true
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555MSUF: EventBus refused UNIT_* event|r "..tostring(event).." (key="..tostring(key).."). Register unit events directly on the frame (oUF-style).")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "WarnUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:36:6"); end

local bus = {
    safeCalls = false,
    handlers = {},  -- handlers[event][key] = { fn=..., once=bool }
    -- Internal: print-once error gate for safeCalls mode.
    _errOnce = {},
}

local driver = CreateFrame("Frame")
driver:Hide()

local function EnsureEventRegistered(event) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureEventRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:54:6");
    -- We don't keep a refcount; we simply register on first handler and unregister when empty.
    if not driver:IsEventRegistered(event) then
        driver:RegisterEvent(event)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureEventRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:54:6"); end

local function MaybeUnregisterEvent(event) Perfy_Trace(Perfy_GetTime(), "Enter", "MaybeUnregisterEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:61:6");
    local t = bus.handlers[event]
    if not t then
        if driver:IsEventRegistered(event) then
            driver:UnregisterEvent(event)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MaybeUnregisterEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:61:6"); return
    end
    -- Check if empty
    for _ in pairs(t) do
        Perfy_Trace(Perfy_GetTime(), "Leave", "MaybeUnregisterEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:61:6"); return
    end
    bus.handlers[event] = nil
    if driver:IsEventRegistered(event) then
        driver:UnregisterEvent(event)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MaybeUnregisterEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:61:6"); end

function bus:Register(event, key, fn, unitFilter, once) Perfy_Trace(Perfy_GetTime(), "Enter", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0");
    if type(event) ~= "string" or event == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0"); return false end
    if type(key) ~= "string" or key == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0"); return false end
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0"); return false end

    -- Hard rule: no UNIT_* on the EventBus (Step 4)
    if IsUnitEvent(event) then
        WarnUnitEvent(event, key)
        Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0"); return false
    end

    local ev = bus.handlers[event]
    if not ev then
        ev = {}
        bus.handlers[event] = ev
        EnsureEventRegistered(event)
    end

    ev[key] = { fn = fn, once = once and true or false }
    Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:79:0"); return true
end

function bus:Unregister(event, key) Perfy_Trace(Perfy_GetTime(), "Enter", "bus:Unregister file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:101:0");
    local ev = bus.handlers[event]
    if not ev then Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Unregister file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:101:0"); return end
    ev[key] = nil
    MaybeUnregisterEvent(event)
Perfy_Trace(Perfy_GetTime(), "Leave", "bus:Unregister file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:101:0"); end

function bus:UnregisterAll(keyPrefix) Perfy_Trace(Perfy_GetTime(), "Enter", "bus:UnregisterAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:108:0");
    if type(keyPrefix) ~= "string" or keyPrefix == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "bus:UnregisterAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:108:0"); return end
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
Perfy_Trace(Perfy_GetTime(), "Leave", "bus:UnregisterAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:108:0"); end

local function _PrintSafeCallErrorOnce(event, key, err) Perfy_Trace(Perfy_GetTime(), "Enter", "_PrintSafeCallErrorOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:124:6");
    -- Only used when bus.safeCalls == true.
    -- Avoid spamming; keep one line per (event,key) pair.
    local eo = bus._errOnce
    if type(eo) ~= "table" then
        eo = {}
        bus._errOnce = eo
    end
    local gate = tostring(event) .. "|" .. tostring(key)
    if eo[gate] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_PrintSafeCallErrorOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:124:6"); return
    end
    eo[gate] = true

    local msg = "|cffff5555MSUF EventBus handler error|r in '" .. tostring(event) .. "' (key=" .. tostring(key) .. "): " .. tostring(err)
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    elseif _G.print then
        _G.print(msg)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_PrintSafeCallErrorOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:124:6"); end

local function CallHandler(key, fn, event, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "CallHandler file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:146:6");
    if not bus.safeCalls then
        fn(event, ...)
        Perfy_Trace(Perfy_GetTime(), "Leave", "CallHandler file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:146:6"); return
    end
    local ok, err = pcall(fn, event, ...)
    if not ok then
        _PrintSafeCallErrorOnce(event, key, err)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "CallHandler file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:146:6"); end

driver:SetScript("OnEvent", function(_, event, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:157:28");
    local ev = bus.handlers[event]
    if not ev then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:157:28"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:157:28"); end)

-- Public globals (back-compat)
_G.MSUF_EventBus = bus

_G.MSUF_EventBus_Register = function(event, key, fn, unitFilter, once) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_EventBus_Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:193:28");
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_EventBus_Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:193:28", bus:Register(event, key, fn, unitFilter, once))
end

_G.MSUF_EventBus_Unregister = function(event, key) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_EventBus_Unregister file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:197:30");
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_EventBus_Unregister file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:197:30", bus:Unregister(event, key))
end

_G.MSUF_EventBus_UnregisterAll = function(keyPrefix) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_EventBus_UnregisterAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:201:33");
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_EventBus_UnregisterAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua:201:33", bus:UnregisterAll(keyPrefix))
end

-- Namespaced export too (some modules use ns)
ns.MSUF_EventBus = bus

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EventBus.lua"); return bus
