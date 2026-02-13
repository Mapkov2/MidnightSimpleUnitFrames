-- MSUF_A2_DB.lua
-- Auras 2.0 DB access + session cache.
-- Phase 1: cache pointers + derived flags so UNIT_AURA hot-path never calls EnsureDB/GetAuras2DB.

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

API.DB = (type(API.DB) == "table") and API.DB or {}
local DB = API.DB

-- Internal: Render binds its EnsureDB implementation here once loaded.
DB._ensureFn = DB._ensureFn

DB.cache = DB.cache or {
    ready = false,
    a2 = nil,
    shared = nil,
    enabled = false,
    showInEditMode = false,
    unitEnabled = {}, -- key -> bool (player/target/focus/boss1-5)
}

-- Pre-cached boss unit strings
local _BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

local function _SetUnitEnabled(cache, a2) 
    local ue = cache.unitEnabled
    -- wipe without realloc
    for k in pairs(ue) do ue[k] = nil end

    if type(a2) ~= "table" or a2.enabled ~= true then
         return
    end

    ue.player = (a2.showPlayer == true)
    ue.target = (a2.showTarget == true)
    ue.focus  = (a2.showFocus  == true)

    local showBoss = (a2.showBoss == true)
    for i = 1, 5 do
        ue[_BOSS_UNITS[i]] = showBoss
    end
 end

function DB.InvalidateCache() 
    local c = DB.cache
    if not c then  return end
    c.ready = false
    c.a2 = nil
    c.shared = nil
    c.enabled = false
    c.showInEditMode = false
    c._unitHasVisibleAuras = nil
    if c.unitEnabled then
        for k in pairs(c.unitEnabled) do c.unitEnabled[k] = nil end
    end
 end

function DB.RebuildCache(a2, shared) 
    local c = DB.cache
    if not c then  return end

    if type(a2) ~= "table" or type(shared) ~= "table" then
        DB.InvalidateCache()
         return
    end

    c.a2 = a2
    c.shared = shared
    c.enabled = (a2.enabled == true)
    c.showInEditMode = (shared.showInEditMode == true)

    _SetUnitEnabled(c, a2)

    -- Pre-compute: does the shared config allow any visible auras?
    -- (Used by Events.ShouldProcessUnitEvent to skip UNIT_AURA quickly)
    local hasVisible = false
    if shared.showBuffs == true then
        local n = shared.maxBuffs
        if type(n) == "number" and n > 0 then hasVisible = true end
    end
    if not hasVisible and shared.showDebuffs == true then
        local n = shared.maxDebuffs
        if type(n) == "number" and n > 0 then hasVisible = true end
    end
    c._unitHasVisibleAuras = hasVisible

    c.ready = true
 end

function DB.BindEnsure(fn) 
    if type(fn) == "function" then
        DB._ensureFn = fn
    end
 end

-- Ensure() calls the bound EnsureDB implementation (Render) and refreshes cache.
function DB.Ensure() 
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return c.a2, c.shared
    end

    local fn = DB._ensureFn
    if type(fn) ~= "function" then
         return nil
    end

    local a2, shared = fn()
    if type(a2) == "table" and type(shared) == "table" then
        DB.RebuildCache(a2, shared)
         return a2, shared
    end

    DB.InvalidateCache()
     return nil
end

function DB.GetCached() 
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return c.a2, c.shared
    end
     return nil
end

-- Extremely hot-path helper for events: no DB work.
function DB.UnitEnabledCached(unit) 
    local c = DB.cache
    local ue = c and c.unitEnabled
    return (ue and unit and ue[unit] == true) or false
end

function DB.AnyUnitEnabledCached()
    local c = DB.cache
    if not c or c.ready ~= true then return false end
    if c.enabled ~= true then return false end
    local ue = c.unitEnabled
    if not ue then return false end
    return (ue.player == true)
        or (ue.target == true)
        or (ue.focus == true)
        or (ue.boss1 == true)
        or (ue.boss2 == true)
        or (ue.boss3 == true)
        or (ue.boss4 == true)
        or (ue.boss5 == true)
end


