--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua"); -- MSUF_A2_Units.lua
-- Auras 2.0 unit model helpers.
-- Phase 3: centralize unit lists + helpers so Render can loop without repeated string logic.

local addonName, ns = ...
ns = ns or {}

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Units = (type(API.Units) == "table") and API.Units or {}
local Units = API.Units

-- Boss unit tokens max. MSUF uses boss1-boss5.
Units.BOSS_MAX = (type(Units.BOSS_MAX) == "number" and Units.BOSS_MAX) or 5

-- Build lists once (no per-frame allocations).
if type(Units.BASE) ~= "table" then
    Units.BASE = { "player", "target", "focus" }
end

if type(Units.BOSS) ~= "table" then
    local t = {}
    for i = 1, Units.BOSS_MAX do
        t[i] = "boss" .. i
    end
    Units.BOSS = t
end

if type(Units.ALL) ~= "table" then
    local t = {}
    local n = 0
    for i = 1, #Units.BASE do
        n = n + 1
        t[n] = Units.BASE[i]
    end
    for i = 1, #Units.BOSS do
        n = n + 1
        t[n] = Units.BOSS[i]
    end
    Units.ALL = t
end

-- Tiny helpers.
function Units.IsBoss(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "Units.IsBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:45:0");
    if type(unit) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "Units.IsBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:45:0"); return false end
    return Perfy_Trace_Passthrough("Leave", "Units.IsBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:45:0", unit:sub(1, 4) == "boss")
end

function Units.ForEachAll(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "Units.ForEachAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:50:0");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "Units.ForEachAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:50:0"); return end
    local t = Units.ALL
    for i = 1, #t do
        fn(t[i])
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Units.ForEachAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:50:0"); end

function Units.ForEachBoss(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "Units.ForEachBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:58:0");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "Units.ForEachBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:58:0"); return end
    local t = Units.BOSS
    for i = 1, #t do
        fn(t[i])
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Units.ForEachBoss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:58:0"); end

-- Optionally expose simple getter.
function Units.GetAll() Perfy_Trace(Perfy_GetTime(), "Enter", "Units.GetAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:67:0");
    return Perfy_Trace_Passthrough("Leave", "Units.GetAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua:67:0", Units.ALL)
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Units.lua");