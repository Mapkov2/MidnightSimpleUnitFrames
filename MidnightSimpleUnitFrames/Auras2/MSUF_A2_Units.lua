-- MSUF_A2_Units.lua
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
function Units.IsBoss(unit) 
    if type(unit) ~= "string" then  return false end
    return unit:sub(1, 4) == "boss"
end

function Units.ForEachAll(fn) 
    if type(fn) ~= "function" then  return end
    local t = Units.ALL
    for i = 1, #t do
        fn(t[i])
    end
 end

function Units.ForEachBoss(fn) 
    if type(fn) ~= "function" then  return end
    local t = Units.BOSS
    for i = 1, #t do
        fn(t[i])
    end
 end

-- Optionally expose simple getter.
function Units.GetAll() 
    return Units.ALL
end

