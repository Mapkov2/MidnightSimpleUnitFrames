-- MSUF_A2_Units.lua
-- Auras 2.0 unit model helpers.
-- Phase 3: centralize unit lists + helpers so Render can loop without repeated string logic.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil

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

if type(Units.GROUP_PARTY) ~= "table" then Units.GROUP_PARTY = { "party1", "party2", "party3", "party4" } end
if type(Units.GROUP_RAID) ~= "table" then
    local t = {}
    for i = 1, 40 do t[i] = "raid" .. i end
    Units.GROUP_RAID = t
end

if type(Units.ALL) ~= "table" then
    local t = {}
    local n = 0
    for i = 1, #Units.BASE do n = n + 1; t[n] = Units.BASE[i] end
    for i = 1, #Units.BOSS do n = n + 1; t[n] = Units.BOSS[i] end
    Units.ALL = t
end

-- Tiny helpers.
function Units.IsBoss(unit) 
    if type(unit) ~= "string" then  return false end
    return unit:sub(1, 4) == "boss"
end

function Units.ForEachAll(fn) 
    if type(fn) ~= "function" then  return end
    local t = Units.GetAll()
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

local function AppendActiveGroupUnits(out)
    local groupNS = ns and ns.Group
    local roster = groupNS and groupNS.roster
    if _G.MSUF_GroupPreviewActive and type(roster) == "table" and type(roster.units) == "table" then
        for i = 1, #roster.units do
            local unit = roster.units[i]
            if unit then
                out[#out + 1] = unit
            end
        end
        return
    end

    local rosterUnits = groupNS and groupNS.rosterUnits
    if type(rosterUnits) == "table" then
        for i = 1, #Units.GROUP_PARTY do
            local unit = Units.GROUP_PARTY[i]
            if rosterUnits[unit] then out[#out + 1] = unit end
        end
        for i = 1, #Units.GROUP_RAID do
            local unit = Units.GROUP_RAID[i]
            if rosterUnits[unit] then out[#out + 1] = unit end
        end
    end
end

-- Optionally expose simple getter.
function Units.GetAll() 
    local out = {}
    for i = 1, #Units.ALL do out[#out + 1] = Units.ALL[i] end
    local db = _G.MSUF_DB and _G.MSUF_DB.group
    if db and db.enabled ~= false then
        AppendActiveGroupUnits(out)
    end
    return out
end
