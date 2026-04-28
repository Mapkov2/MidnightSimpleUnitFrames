-- MSUF_A2_DB.lua — Auras2 DB + Colors + Filters + Public API + Units (consolidated)

-- MSUF_A2_DB.lua

-- MSUF_A2_DB.lua
-- Auras 2.0 DB access + session cache.
-- Phase 1: cache pointers + derived flags so UNIT_AURA hot-path never calls EnsureDB/GetAuras2DB.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type = type
local pairs = pairs
local tonumber = tonumber

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
    unitHasVisibleAuras = {}, -- key -> bool (per-unit buff/debuff cap+visibility)
}

-- Pre-cached boss unit strings
local _BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

local _AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }

local function _ResolveUnitAuraCaps(a2, shared, unit)
    local showBuffs = (shared and shared.showBuffs == true)
    local showDebuffs = (shared and shared.showDebuffs == true)

    local maxBuffs = shared and shared.maxBuffs
    local maxDebuffs = shared and shared.maxDebuffs

    if type(maxBuffs) ~= "number" then
        maxBuffs = shared and shared.maxIcons or 12
    end
    if type(maxDebuffs) ~= "number" then
        maxDebuffs = shared and shared.maxIcons or 12
    end

    local pu = a2 and a2.perUnit and a2.perUnit[unit]
    if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
        local ls = pu.layoutShared
        if type(ls.maxBuffs) == "number" then maxBuffs = ls.maxBuffs end
        if type(ls.maxDebuffs) == "number" then maxDebuffs = ls.maxDebuffs end
    end

    maxBuffs = tonumber(maxBuffs) or 0
    maxDebuffs = tonumber(maxDebuffs) or 0

    local hasBuffLane = showBuffs and maxBuffs > 0
    local hasDebuffLane = showDebuffs and maxDebuffs > 0
    return (hasBuffLane or hasDebuffLane) == true
end

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

    -- Group frame unit toggles (Phase 7)
    local showParty = (a2.showParty == true)
    for i = 1, 4 do
        ue["party" .. i] = showParty
    end
    local showRaid = (a2.showRaid == true)
    for i = 1, 40 do
        ue["raid" .. i] = showRaid
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
    if c.unitHasVisibleAuras then
        for k in pairs(c.unitHasVisibleAuras) do c.unitHasVisibleAuras[k] = nil end
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

    -- Pre-compute global + per-unit visible aura lanes.
    -- Global flag is preserved for compatibility/hot fallback,
    -- per-unit map enables tighter UNIT_AURA registration gates.
    local hasVisible = false
    local uv = c.unitHasVisibleAuras
    if uv then
        for k in pairs(uv) do uv[k] = nil end
        for i = 1, #_AURA_UNITS do
            local unit = _AURA_UNITS[i]
            local unitVisible = _ResolveUnitAuraCaps(a2, shared, unit)
            uv[unit] = unitVisible
            if unitVisible then hasVisible = true end
        end
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
        or (ue.party1 == true)
        or (ue.raid1 == true)
end

-- MSUF_A2_Colors.lua

-- MSUF_A2_Colors.lua
-- Auras 2.0: highlight/border/stack color helpers.
-- Secret-safe: reads SavedVariables color tables (plain numbers) only.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type, pairs = type, pairs

ns.MSUF_Auras2 = ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.Colors = API.Colors or {}
local Colors = API.Colors
local _G = _G

-- Cached general ref (invalidated by InvalidateCache)
local _general, _generalValid

local function GetGeneral()
    if _generalValid then return _general end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then _general = nil; _generalValid = false; return nil end
    local g = db.general
    if type(g) ~= "table" then _general = nil; _generalValid = false; return nil end
    _general = g; _generalValid = true
    return g
end

-- Read r,g,b from color table. Accepts {r,g,b}, {r=,g=,b=}, {"1","2","3"}.
local function ReadRGB(t, dr, dg, db)
    if not t then return dr, dg, db end
    local r = t[1] or t["1"] or t.r
    local g = t[2] or t["2"] or t.g
    local b = t[3] or t["3"] or t.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return dr, dg, db end
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    return r, g, b
end

-- Per-key cache: avoids re-reading SavedVariables tables every frame.
local _cache = {}

local function CachedColor(key, defR, defG, defB)
    local gen = GetGeneral()
    local t = gen and gen[key]
    local c = _cache[key]
    if c and c.t == t then return c.r, c.g, c.b end
    local r, g, b = ReadRGB(t, defR, defG, defB)
    _cache[key] = { t = t, r = r, g = g, b = b }
    return r, g, b
end

function Colors.InvalidateCache()
    for k in pairs(_cache) do _cache[k] = nil end
    _general = nil; _generalValid = false
end

function Colors.GetOwnBuffHighlightRGB()
    return CachedColor("aurasOwnBuffHighlightColor", 1.0, 0.85, 0.2)
end

function Colors.GetOwnDebuffHighlightRGB()
    return CachedColor("aurasOwnDebuffHighlightColor", 1.0, 0.3, 0.3)
end

function Colors.GetStackCountRGB()
    return CachedColor("aurasStackCountColor", 1.0, 1.0, 1.0)
end

function Colors.GetPrivatePlayerHighlightRGB()
    return 0.75, 0.2, 1.0
end

-- Legacy global exports (Icons.lua reads these via _G.*)
_G.MSUF_A2_GetOwnBuffHighlightRGB = Colors.GetOwnBuffHighlightRGB
_G.MSUF_A2_GetOwnDebuffHighlightRGB = Colors.GetOwnDebuffHighlightRGB
_G.MSUF_A2_GetStackCountRGB = Colors.GetStackCountRGB
_G.MSUF_A2_GetPrivatePlayerHighlightRGB = Colors.GetPrivatePlayerHighlightRGB

-- MSUF_A2_Filters.lua

-- MSUF_A2_Filters.lua
-- Phase F: Centralize Auras2 filter normalization + runtime resolution.
-- Goal: keep Render orchestration-only and avoid duplicated, drift-prone filter logic.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- Locals (used in this file)
local type = type

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Filters = (type(API.Filters) == "table") and API.Filters or {}
local Filters = API.Filters

local function Default(t, key, value)
    if not t then return end
    if t[key] == nil then t[key] = value end
end

-- Normalize a filter config table to the expected schema.
-- sharedSettings is used only for one-time migration from legacy toggles.
function Filters.NormalizeFilters(f, sharedSettings, migrateFlagKey)
    if not f then return end

    Default(f, "enabled", true)
    f.buffs = (type(f.buffs) == "table") and f.buffs or {}
    f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
    local b, d = f.buffs, f.debuffs

    -- One-time migration from legacy shared toggles (Options compatibility).
    if migrateFlagKey and not f[migrateFlagKey] and type(sharedSettings) == "table" then
        if f.hidePermanent == nil then f.hidePermanent = (sharedSettings.hidePermanent == true) end
        if b.onlyMine == nil then b.onlyMine = (sharedSettings.onlyMyBuffs == true) end
        if d.onlyMine == nil then d.onlyMine = (sharedSettings.onlyMyDebuffs == true) end
        f[migrateFlagKey] = true
    end

    -- IMPORTANT split toggle migration (v1):
    -- Legacy config used f.onlyImportantAuras (single toggle) to force both buffs+debuffs to IMPORTANT.
    -- New config uses per-type toggles: f.buffs.onlyImportant and f.debuffs.onlyImportant.
    if not f._msufA2_onlyImportantSplitMigrated_v1 then
        if f.onlyImportantAuras == true then
            if b.onlyImportant == nil then b.onlyImportant = true end
            if d.onlyImportant == nil then d.onlyImportant = true end
            -- Deprecate legacy master flag so users can independently toggle buffs/debuffs.
            f.onlyImportantAuras = false
        end
        f._msufA2_onlyImportantSplitMigrated_v1 = true
    end

    Default(f, "hidePermanent", false)
    Default(b, "onlyMine", false)
    Default(b, "includeBoss", false)
    Default(b, "onlyImportant", false)
    Default(d, "onlyMine", false)
    Default(d, "includeBoss", false)
    Default(d, "onlyImportant", false)
    Default(f, "onlyBossAuras", false)
    Default(f, "onlyImportantAuras", false)
    Default(f, "onlyRaidInCombatAuras", false)
    -- Aura sort order (passed to C_UnitAuras.GetAuraSlots).
    -- 0=Unsorted (default/legacy), 1=Default, 2=BigDefensive, 3=Expiration,
    -- 4=ExpirationOnly, 5=Name, 6=NameOnly.
    Default(f, "sortOrder", 0)
end

-- Ensure shared.filters exists, migrate legacy storage if needed, and keep legacy shared flags in sync.
-- This is called from Render.EnsureDB() after shared defaults are applied.
function Filters.EnsureSharedFilters(a2, shared)
    if type(a2) ~= "table" or type(shared) ~= "table" then return nil end

    -- Shared filter config: migrate older storage from perUnit.target.filters if needed.
    if type(shared.filters) ~= "table" then
        local migrated = (type(a2.perUnit) == "table" and type(a2.perUnit.target) == "table") and a2.perUnit.target.filters or nil
        shared.filters = (migrated) and migrated or {}
        if migrated then shared.filters._msufA2_sharedFiltersMigratedFromTarget = true end
    end

    local sf = shared.filters
    if type(sf) ~= "table" then
        sf = {}
        shared.filters = sf
    end

    Filters.NormalizeFilters(sf, shared, "_msufA2_sharedFiltersMigrated_v1")

    -- Compatibility: some Options builds still toggle shared.hidePermanent directly.
    -- Mirror that value into shared.filters.hidePermanent so the runtime filter respects the UI.
    if shared.hidePermanent ~= nil and sf.hidePermanent ~= shared.hidePermanent then
        sf.hidePermanent = (shared.hidePermanent == true)
    end

    -- Keep legacy shared flags synced (derived from shared.filters)
    shared.onlyMyBuffs = (sf.buffs and sf.buffs.onlyMine == true) or false
    shared.onlyMyDebuffs = (sf.debuffs and sf.debuffs.onlyMine == true) or false
    shared.hidePermanent = (sf.hidePermanent == true)

    return sf
end

-- Resolve which filter table to use for a unit.
-- Default: shared.filters. If per-unit overrideFilters is enabled, use that unit's filters table.
-- Lazy-normalizes per-unit tables on first access (defensive against manual DB edits).
function Filters.GetEffectiveFilterTable(a2, shared, unitKey)
    if not shared then return nil end
    local tf = shared.filters

    if type(a2) == "table" and type(a2.perUnit) == "table" and unitKey ~= nil then
        local pu = a2.perUnit
        local u = pu and pu[unitKey]
        if u and u.overrideFilters == true then
            local puf = u.filters
            if puf ~= nil then
                -- Lazy normalize: ensure schema is complete (one-time per profile load)
                if not puf._msufA2_normalizedRuntime then
                    Filters.NormalizeFilters(puf)
                    puf._msufA2_normalizedRuntime = true
                end
                tf = puf
            end
        end
    end

    return tf
end

-- Compute runtime flags used by Model/Render loops.
-- Returns:
--   tf, masterOn,
--   onlyBossAuras,
--   onlyImportantBuffs, onlyImportantDebuffs,
--   buffsOnlyMine, debuffsOnlyMine,
--   buffsIncludeBoss, debuffsIncludeBoss,
--   hidePermanentBuffs
function Filters.ResolveRuntimeFlags(a2, shared, unitKey)
    local tf = Filters.GetEffectiveFilterTable(a2, shared, unitKey)

    local masterOn = (tf and tf.enabled == true) and true or false
    local onlyBossAuras = (masterOn and tf and tf.onlyBossAuras == true) and true or false

    -- Legacy (deprecated): a single toggle that forced BOTH buffs+debuffs to IMPORTANT.
    local legacyOnlyImportant = (masterOn and tf and tf.onlyImportantAuras == true) and true or false

    local onlyImportantBuffs, onlyImportantDebuffs = false, false

    local buffsOnlyMine, debuffsOnlyMine = false, false
    local buffsIncludeBoss, debuffsIncludeBoss = false, false
    local hidePermanentBuffs = false

    if masterOn and tf then
        local b = tf.buffs
        local d = tf.debuffs

        -- IMPORTANT per-type toggles (preferred). Fall back to legacyOnlyImportant only if missing.
        if b and b.onlyImportant ~= nil then
            onlyImportantBuffs = (b.onlyImportant == true)
        else
            onlyImportantBuffs = legacyOnlyImportant
        end
        if d and d.onlyImportant ~= nil then
            onlyImportantDebuffs = (d.onlyImportant == true)
        else
            onlyImportantDebuffs = legacyOnlyImportant
        end

        if b and b.onlyMine ~= nil then
            buffsOnlyMine = (b.onlyMine == true)
        else
            buffsOnlyMine = (shared and shared.onlyMyBuffs == true) or false
        end

        if d and d.onlyMine ~= nil then
            debuffsOnlyMine = (d.onlyMine == true)
        else
            debuffsOnlyMine = (shared and shared.onlyMyDebuffs == true) or false
        end

        buffsIncludeBoss = (b and b.includeBoss == true) or false
        debuffsIncludeBoss = (d and d.includeBoss == true) or false

        if tf.hidePermanent ~= nil then
            hidePermanentBuffs = (tf.hidePermanent == true)
        else
            hidePermanentBuffs = (shared and shared.hidePermanent == true) or false
        end

    else
        buffsOnlyMine = (shared and shared.onlyMyBuffs == true) or false
        debuffsOnlyMine = (shared and shared.onlyMyDebuffs == true) or false
        hidePermanentBuffs = (shared and shared.hidePermanent == true) or false
        onlyImportantBuffs = false
        onlyImportantDebuffs = false
    end

    return tf, masterOn, onlyBossAuras, onlyImportantBuffs, onlyImportantDebuffs, buffsOnlyMine, debuffsOnlyMine, buffsIncludeBoss, debuffsIncludeBoss, hidePermanentBuffs
end

-- MSUF_A2_Public.lua

-- MSUF_A2_Public.lua
-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Load-order safe: Public/Events/Render can load in any order, so Init can be called multiple times.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type = type
local C_Timer = C_Timer

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}

function API.Init()
    -- Prime DB cache once so UNIT_AURA hot-path never does migrations/default work.
    -- Load-order safety: DB.Ensure() can legitimately return nil early (EnsureDB not bound yet).
    -- Only mark __dbInited once we actually have valid pointers.
    local a2_ok, a2_ptr
    if not API.__dbInited then
        local DB = API.DB
        if DB and DB.Ensure then
            local a2, shared = DB.Ensure()
            if type(a2) == "table" and type(shared) == "table" then
                API.__dbInited = true
                a2_ok, a2_ptr = true, a2
            end
        end
    else
        local DB = API.DB
        local c = DB and DB.cache
        if c and c.ready and c.a2 then
            a2_ok, a2_ptr = true, c.a2
        end
    end

    -- Bind + register events (UNIT_AURA helper frames, target/focus/boss changes, edit mode preview refresh)
    if not API.__eventsInited then
        local Ev = API.Events
        if Ev and Ev.Init then
            API.__eventsInited = true
            Ev.Init()
        end
    end

    -- Load-order edge case fix:
    -- Events.Init can run before Render has bound EnsureDB, causing ApplyEventRegistration() to
    -- disable all UNIT_AURA bindings. Once DB pointers are valid, re-apply event registration once
    -- and prime the Player unit so player auras don't "wake up" only after Edit Mode toggles.
    if a2_ok and API.__eventsInited and not API.__eventRegPrimed then
        local Ev = API.Events
        local apply = Ev and Ev.ApplyEventRegistration
        if type(apply) == "function" then
            API.__eventRegPrimed = true
            apply()

            -- Prime initial player render only when player unit is enabled.
            if a2_ptr and a2_ptr.enabled == true and a2_ptr.showPlayer == true then
                local req = API.RequestUnit or API.MarkDirty
                if type(req) == "function" then
                    req("player", 0)
                end
            end
        end
    end
end

-- Public API: coalesced apply (used by Options toggles)
-- Ensures Auras2 is initialized and a full refresh is requested next frame.
API.__applyPending = (API.__applyPending == true)

-- File-scope apply function (avoid closure allocation per RequestApply call)
local function _DoApply()
    API.__applyPending = false

    if API.Init then
        API.Init()
    end

    -- 4.0b1 fix:
    -- Auras2 now has a cached "update-only" fast path that reuses the previous
    -- filtered result when the aura structure did not change. Options edits
    -- (Important/Only Mine/Only Boss/ignore list/caps/layout, etc.) can therefore
    -- look stale unless we explicitly bump the config generation and wipe cached
    -- filter results before asking for a refresh.
    local invalidate = API.InvalidateDB
    if type(invalidate) == "function" then
        invalidate()
    end

    local r = API.RefreshAll
    if type(r) == "function" then
        r()
    elseif type(_G) == "table" and type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
end

function API.RequestApply()
    if API.__applyPending then return end
    API.__applyPending = true

    local sched = _G.MSUF_ScheduleOnce
    if sched then
        sched("A2_DB_APPLY", _DoApply)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, _DoApply)
    else
        _DoApply()
    end
end

-- Legacy/global entrypoint (optional)
if type(_G) == "table" then
    _G.MSUF_Auras2_RequestApply = function() return API.RequestApply() end
end

-- MSUF_A2_Units.lua

-- MSUF_A2_Units.lua
-- Auras 2.0 unit model helpers.
-- Phase 3: centralize unit lists + helpers so Render can loop without repeated string logic.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
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

-- Party unit tokens (SecureGroupHeader assigns party1-party4)
if type(Units.PARTY) ~= "table" then
    Units.PARTY = { "party1", "party2", "party3", "party4" }
end
Units.PARTY_MAX = 4

-- Raid unit tokens (raid1-raid40)
if type(Units.RAID) ~= "table" then
    local t = {}
    for i = 1, 40 do t[i] = "raid" .. i end
    Units.RAID = t
end
Units.RAID_MAX = 40

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

function Units.IsParty(unit)
    if type(unit) ~= "string" then return false end
    return unit:sub(1, 5) == "party"
end

function Units.IsRaid(unit)
    if type(unit) ~= "string" then return false end
    return unit:sub(1, 4) == "raid"
end

function Units.IsGroupUnit(unit)
    if type(unit) ~= "string" then return false end
    local p = unit:sub(1, 5)
    return p == "party" or unit:sub(1, 4) == "raid"
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
