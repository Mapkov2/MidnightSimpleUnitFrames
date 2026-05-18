-- MSUF_A2_Core.lua — Cache + Collect + Icons (consolidated)

-- MSUF_A2_Cache.lua

-- MSUF_A2_Cache.lua  Auras v4 Delta Cache
-- Core idea: UNIT_AURA provides updateInfo with addedAuras,
-- updatedAuraInstanceIDs, removedAuraInstanceIDs. We maintain a per-unit
-- cache and only re-filter when the visible set changes.
-- Two filter paths:
--   sortOrder == 0: Pure cache iteration (ZERO C API calls per render)
--   sortOrder != 0: C++ sorted via GetAuraSlots, cache provides enrichment
--                   (saves IsAuraFilteredOutByInstanceID calls per aura)
-- Secret-safe: auraInstanceID is ALWAYS a plain number.
-- Player classification uses IsAuraFilteredOutByInstanceID (returns boolean).
-- Never compare/arithmetic on data.isHarmful, data.duration, etc.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_CACHE_LOADED then return end
ns.__MSUF_A2_CACHE_LOADED = true

API.Cache = (type(API.Cache) == "table") and API.Cache or {}
local Cache = API.Cache

-- Hot locals
local type = type
local next = next
local select = select
local wipe = table.wipe or function(t) for k in next, t do t[k] = nil end return t end
local C_UnitAuras = C_UnitAuras

-- P7: Aura table pool (max 64 entries).
-- "Remove" path: recycles aura tables back into the pool instead of abandoning them to GC.
-- "Added"  path: acquires pooled tables for new entries (reuses instead of {}).
-- "Updated" path: in-place field copy — the existing table is NEVER replaced.
--   → zero Lua allocations for aura updates in steady-state raid combat.
-- Secret-safe: only plain-value C fields + our own _msuf* enrichment fields are touched.
local _auraPool  = {}
local _auraPoolN = 0
local _AURA_POOL_MAX = 64

local function _AuraAcquire()
    if _auraPoolN > 0 then
        local t = _auraPool[_auraPoolN]
        _auraPool[_auraPoolN] = nil
        _auraPoolN = _auraPoolN - 1
        return t
    end
    return {}
end

local function _AuraRelease(t)
    if _auraPoolN < _AURA_POOL_MAX then
        wipe(t)
        _auraPoolN = _auraPoolN + 1
        _auraPool[_auraPoolN] = t
    end
end

-- Copy all fields from src into dst (used to write C API data into a pooled/existing table).
-- Does NOT clear dst first — callers guarantee non-overlapping key sets or explicit wipe.
local function _AuraCopyFields(dst, src)
    -- PERF: Selective copy — only fields used by Cache, FilterAura, RenderUnit.
    -- Saves ~50% of work vs generic `for k,v in next` (10+ unused C API fields skipped).
    dst.auraInstanceID         = src.auraInstanceID
    dst.spellId                = src.spellId
    dst.icon                   = src.icon
    dst.duration               = src.duration
    dst.expirationTime         = src.expirationTime
    dst.applications           = src.applications
    dst.dispelName             = src.dispelName
    dst.isHelpful              = src.isHelpful
    dst.isHarmful              = src.isHarmful
    dst.isRaid                 = src.isRaid
    dst.isBossAura             = src.isBossAura
    dst.isFromPlayerOrPlayerPet = src.isFromPlayerOrPlayerPet
    dst.sourceUnit             = src.sourceUnit
    dst.name                   = src.name
    -- Preserve enriched _msuf* fields on dst (not from src)
end

-- PERF: Lightweight copy for updatedAuraInstanceIDs path.
-- On updates, only mutable fields change (duration/expiration/stacks).
-- Immutable fields (spellId, icon, name, dispelName, isHarmful) never change.
-- Saves 8 table writes per update (31K calls/session).
local function _AuraCopyFieldsUpdate(dst, src)
    dst.duration               = src.duration
    dst.expirationTime         = src.expirationTime
    dst.applications           = src.applications
    dst.isRaid                 = src.isRaid
    dst.isBossAura             = src.isBossAura
    dst._msufA2_updateRev      = (dst._msufA2_updateRev or 0) + 1
end
local C_Secrets = C_Secrets
local GetTime = GetTime
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")
local tonumber = tonumber

local _getSlots, _getBySlot, _getByAid, _isFiltered, _doesExpire
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _getSlots    = C_UnitAuras.GetAuraSlots
    _getBySlot   = C_UnitAuras.GetAuraDataBySlot
    _getByAid    = C_UnitAuras.GetAuraDataByAuraInstanceID
    _isFiltered  = C_UnitAuras.IsAuraFilteredOutByInstanceID
    _doesExpire  = C_UnitAuras.DoesAuraHaveExpirationTime
    _apisBound   = true
end

-- Pre-cached filter strings
local HELPFUL         = "HELPFUL"
local HARMFUL         = "HARMFUL"
local HELPFUL_PLAYER  = "HELPFUL|PLAYER"
local HARMFUL_PLAYER  = "HARMFUL|PLAYER"
local HELPFUL_IMPORTANT = "HELPFUL|IMPORTANT"
local HARMFUL_IMPORTANT = "HARMFUL|IMPORTANT"
local HARMFUL_DISPELLABLE = "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- Sated/Exhaustion spellID hashtable (O(1) lookup, built once at load)
-- Zero steady-state cost: spellId check happens only on ADD.
-- Render path checks a cached integer flag (data._msufA2_isSated == 1).
-- Secret-safe: if spellId is secret/unavailable we fail-closed (not-sated).
local _SATED_SPELLS = {
    [57723]  = true,   -- Exhaustion (Heroism/Bloodlust)
    [57724]  = true,   -- Sated (Heroism/Bloodlust)
    [80354]  = true,   -- Temporal Displacement (Mage Time Warp)
    [95809]  = true,   -- Hunter Pet Insanity
    [160455] = true,   -- Hunter Pet Fatigued
    [264689] = true,   -- Hunter Pet Fatigued (alt ID)
    [390435] = true,   -- Exhaustion (Drums)
}

-- Global Aura Ignore List — Predefined categories of declassified spells.
-- Users toggle categories on/off per-unit (shared or override).
-- Runtime: enabled categories merge into a flat hashtable (_ignoreHash)
-- checked in FilterAura via cached decoded spellId (data._msufA2_sid).
-- Secret-safe: spellId is decoded once on ADD; ignore hash is plain numbers.
local _IGNORE_CAT_SPELLS = {
    DESERTER = {
        [26013]  = true,   -- BG Deserter
        [71041]  = true,   -- Dungeon Deserter
    },
    SKYRIDING = {
        [427490] = true,   -- Ride Along Available
        [447959] = true,   -- Ride Along Active
        [447960] = true,   -- Ride Along Inactive
    },
    RAID_BUFFS = {
        [1126]   = true,   -- Mark of the Wild
        [1459]   = true,   -- Arcane Intellect
        [6673]   = true,   -- Battle Shout
        [21562]  = true,   -- Power Word: Fortitude
        [369459] = true,   -- Source of Magic
        [462854] = true,   -- Skyfury
        [474754] = true,   -- Symbiotic Relationship
    },
    BLESSING_BRONZE = {
        [381732] = true, [381741] = true, [381746] = true, [381748] = true,
        [381749] = true, [381750] = true, [381751] = true, [381752] = true,
        [381753] = true, [381754] = true, [381756] = true, [381757] = true,
        [381758] = true,
    },
    HEALER_HOTS = {
        -- Preservation Evoker
        [355941] = true, [363502] = true, [364343] = true,
        [366155] = true, [367364] = true, [373267] = true, [376788] = true,
        -- Augmentation Evoker
        [360827] = true, [395152] = true, [410089] = true,
        [410263] = true, [410686] = true, [413984] = true,
        -- Resto Druid
        [774]    = true, [8936]   = true, [33763]  = true,
        [48438]  = true, [155777] = true,
        -- Disc Priest
        [17]     = true, [194384] = true, [1253593]= true,
        -- Holy Priest
        [139]    = true, [41635]  = true, [77489]  = true,
        -- Mistweaver Monk
        [115175] = true, [119611] = true, [124682] = true, [450769] = true,
        -- Restoration Shaman
        [974]    = true, [383648] = true, [61295]  = true,
        [207400] = true, [382024] = true, [444490] = true,
        -- Holy Paladin
        [53563]  = true, [156322] = true, [156910] = true, [1244893]= true,
    },
    ROGUE_POISONS = {
        [2823]   = true,   -- Deadly Poison
        [8679]   = true,   -- Wound Poison
        [3408]   = true,   -- Crippling Poison
        [5761]   = true,   -- Numbing Poison
        [315584] = true,   -- Instant Poison
        [381637] = true,   -- Atrophic Poison
        [381664] = true,   -- Amplifying Poison
    },
    SHAMAN_IMBUE = {
        [319773] = true, [319778] = true,   -- Windfury / Flametongue
        [382021] = true, [382022] = true,   -- Earthliving Weapon
        [457496] = true, [457481] = true,   -- Tidecaller's Guard
        [462757] = true, [462742] = true,   -- Thunderstrike Ward
    },
    SELF_BUFFS = {
        [433568] = true,   -- Rite of Sanctification
        [433583] = true,   -- Rite of Adjuration
    },
    RESOURCE_AURAS = {
        [205473] = true,   -- Mage Icicles
        [260286] = true,   -- Hunter Tip of the Spear
    },
    COOLDOWNS = {
        [8690]   = true,   -- Hearthstone
        [20608]  = true,   -- Shaman Reincarnation
    },
}

-- UI metadata (exposed to Options via API)
local _IGNORE_CAT_META = {
    { key = "RAID_BUFFS",       label = "Raid Buffs",              tooltip = "Mark of the Wild, Fortitude, Arcane Intellect, Battle Shout, etc." },
    { key = "BLESSING_BRONZE",  label = "Blessing of the Bronze",  tooltip = "All class-specific Blessing of the Bronze variants." },
    { key = "HEALER_HOTS",      label = "Healer HoTs",             tooltip = "All healer class HoTs and shields (Druid, Priest, Paladin, Shaman, Monk, Evoker)." },
    { key = "ROGUE_POISONS",    label = "Rogue Poisons",           tooltip = "Self-applied poison buffs (Deadly, Wound, Crippling, etc.)." },
    { key = "SHAMAN_IMBUE",     label = "Shaman Imbuements",       tooltip = "Weapon enchant buffs (Windfury, Flametongue, Earthliving, etc.)." },
    { key = "DESERTER",         label = "Deserter",                tooltip = "BG and Dungeon deserter debuffs." },
    { key = "SKYRIDING",        label = "Skyriding",               tooltip = "Ride Along auras (Available, Active, Inactive)." },
    { key = "SELF_BUFFS",       label = "Long-term Self Buffs",    tooltip = "Rite of Sanctification, Rite of Adjuration." },
    { key = "RESOURCE_AURAS",   label = "Resource-like Auras",     tooltip = "Mage Icicles, Hunter Tip of the Spear." },
    { key = "COOLDOWNS",        label = "Cooldowns",               tooltip = "Hearthstone, Reincarnation cooldown auras." },
}

local _HEALER_HOT_SPELLS = _IGNORE_CAT_SPELLS.HEALER_HOTS or {}

-- Expose for Options UI
Cache.IGNORE_CAT_META = _IGNORE_CAT_META

-- Secret-safe spellId decoder (called ONCE per aura on ADD).
-- Returns plain lua number or 0 (secret/nil → passes blacklist).
--
-- CRITICAL (Midnight 12.0): on party/raid/target/focus/boss units,
-- data.spellId for declassified spells comes back as an *accessible*
-- secret-tagged integer. canaccessvalue() returns true, but the value
-- still carries the secret tag — using it as a hash key (hash[sid])
-- silently misses every lookup because the tagged value does not
-- equate to a plain lua number.
--
-- tonumber() strips the tag. For plain numbers it is a no-op C call;
-- for nil / truly-secret values it returns nil → coerced to 0.
-- Self-auras (player) were already plain numbers → fix is a no-op there.
local function _DecodeSpellId(data)
    local sid = data.spellId or data.spellID
    if _hasCanaccessvalue then
        if canaccessvalue(sid) ~= true then return 0 end
    elseif issecretvalue and issecretvalue(sid) == true then
        return 0
    end
    return tonumber(sid) or 0
end

-- Build flat ignore hashtable from enabled category keys.
-- PERF: Caches per category table. Shared + per-unit overrides can coexist
-- without rebuilding on every frame or leaking one unit's hash into another.
-- Zero allocation on steady-state (no string building, no table.concat).
local _ignoreHashPools = setmetatable({}, { __mode = "k" })
local _ignoreHashValid = setmetatable({}, { __mode = "k" })

function Cache.BuildIgnoreHash(enabledCats)
    if not enabledCats then return nil end
    -- PERF: return cached result if still valid
    local hash = _ignoreHashPools[enabledCats]
    if hash and _ignoreHashValid[enabledCats] then
        return hash._any and hash or nil
    end
    if not hash then
        hash = {}
        _ignoreHashPools[enabledCats] = hash
    end
    wipe(hash)
    hash._any = false
    for catKey, enabled in next, enabledCats do
        if enabled == true then
            local spells = _IGNORE_CAT_SPELLS[catKey]
            if spells then
                for sid in next, spells do
                    hash[sid] = true
                    hash._any = true
                end
            end
        end
    end
    _ignoreHashValid[enabledCats] = true
    return hash._any and hash or nil
end

-- Invalidate ignore hash cache (called when user changes ignore settings)
function Cache.InvalidateIgnoreHash()
    wipe(_ignoreHashValid)
end

-- Per-unit state
local _units = {}

local function EnsureUnit(unit)
    local s = _units[unit]
    if s then return s end
    s = {
        all     = {},
        epoch   = 0,
        changed = true,
    }
    _units[unit] = s
    return s
end

Cache._units = _units

-- Check if a unit has any aura whose decoded spellId is in the given set.
-- Used by Buff Reminder to detect missing buffs.  O(N) where N = active auras.
function Cache.HasAnySpell(unit, spellSet)
    local s = _units[unit]
    if not s or not s.all then return false end
    for _, data in next, s.all do
        local sid = data._msufA2_sid
        if sid and sid ~= 0 and spellSet[sid] then return true end
    end
    return false
end

-- Get the minimum remaining time (seconds) for any matching spell.
-- Returns: remainingSec (number) or nil (no matching spell).
-- ALL provider spells (satisfiedBy sets) are whitelisted → expirationTime is
-- a plain number, no secret checks needed.
function Cache.GetMinRemaining(unit, spellSet)
    local s = _units[unit]
    if not s or not s.all then return nil end
    local now = GetTime()
    local best = nil
    for _, data in next, s.all do
        local sid = data._msufA2_sid
        if sid and sid ~= 0 and spellSet[sid] then
            local exp = data.expirationTime
            if exp and exp ~= 0 then
                local rem = exp - now
                if rem < 0 then rem = 0 end
                if not best or rem < best then best = rem end
            else
                -- No expiration (permanent buff) → infinite remaining
                if not best then best = 999999 end
            end
        end
    end
    return best
end

-- Player-aura classification (secret-safe)
local function ClassifyPlayer(unit, aid, isHelpful)
    if not _isFiltered then return false end
    local filter = isHelpful and HELPFUL_PLAYER or HARMFUL_PLAYER
    local r = _isFiltered(unit, aid, filter)
    if issecretvalue and issecretvalue(r) then return false end
    return (r == false)
end

local function ReadAccessibleBool(v)
    if v == nil then return nil end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then return nil end
    elseif issecretvalue and issecretvalue(v) == true then
        return nil
    end
    if v == true then return true end
    if v == false then return false end
    return nil
end

local function ReadAccessibleDispelName(aura)
    local v = aura and aura.dispelName
    if v == nil then return nil end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then return nil end
    elseif issecretvalue and issecretvalue(v) == true then
        return nil
    end
    if type(v) ~= "string" or v == "" or v == "None" then return nil end
    return v
end

local function DebuffMatchesSelectedDispelType(aura, cfg)
    local dispelName = ReadAccessibleDispelName(aura)
    if dispelName == "Magic" then return cfg._debuffDispelMagic == true end
    if dispelName == "Curse" then return cfg._debuffDispelCurse == true end
    if dispelName == "Poison" then return cfg._debuffDispelPoison == true end
    if dispelName == "Disease" then return cfg._debuffDispelDisease == true end
    return false
end

local function DebuffIsDispellable(unit, aid, aura, lIsFiltered)
    if ReadAccessibleDispelName(aura) then return true end
    if lIsFiltered then
        return ReadAccessibleBool(lIsFiltered(unit, aid, HARMFUL_DISPELLABLE)) == false
    end
    return false
end

-- Helpful/harmful classification (secret-safe).
-- Prefer explicit AuraData polarity when the client exposes it. Some player
-- auras can give ambiguous filter answers during UNIT_AURA deltas, which made
-- harmless self auras land in the debuff lane.
local function ClassifyHelpful(unit, aid, data, fallbackHelpful)
    local v = ReadAccessibleBool(data and data.isHelpful)
    if v ~= nil then return v, "data" end

    v = ReadAccessibleBool(data and data.isHarmful)
    if v ~= nil then return not v, "data" end

    if _isFiltered then
        local helpfulFiltered = ReadAccessibleBool(_isFiltered(unit, aid, HELPFUL))
        local harmfulFiltered = ReadAccessibleBool(_isFiltered(unit, aid, HARMFUL))
        local helpfulVisible
        local harmfulVisible
        if helpfulFiltered ~= nil then helpfulVisible = (helpfulFiltered == false) end
        if harmfulFiltered ~= nil then harmfulVisible = (harmfulFiltered == false) end

        if helpfulVisible ~= nil and harmfulVisible ~= nil then
            if helpfulVisible ~= harmfulVisible then return helpfulVisible, "filter" end
        elseif helpfulVisible ~= nil then
            return helpfulVisible, "filter"
        elseif harmfulVisible ~= nil then
            return not harmfulVisible, "filter"
        end
    end

    if fallbackHelpful ~= nil then return fallbackHelpful == true, "fallback" end
    return true, "fallback"
end

-- Boss flag (secret-safe, cached on data table)
local function ReadBossFlag(data)
    if not data then return -1 end
    local cached = data._msufA2_bossFlag
    if cached ~= nil then return cached end
    local v = data.isBossAura
    if v == nil then
        data._msufA2_bossFlag = -1
        return -1
    end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then data._msufA2_bossFlag = -1; return -1 end
    elseif issecretvalue and issecretvalue(v) == true then
        data._msufA2_bossFlag = -1
        return -1
    end
    local f = (v == true) and 1 or 0
    data._msufA2_bossFlag = f
    return f
end

Cache.ReadBossFlag = ReadBossFlag

-- Enrichment (called ONCE per aura on add)
local function EnrichAura(unit, data, isHelpful)
    if not data then return end
    local aid = data.auraInstanceID
    if not aid then return end
    data._msufIsHelpful    = isHelpful
    data._msufIsPlayerAura = ClassifyPlayer(unit, aid, isHelpful)
    -- Decode spellId once (secret-safe), cache for sated + ignore lookups
    local sid = _DecodeSpellId(data)
    data._msufA2_sid       = sid
    data._msufA2_isSated   = (sid ~= 0 and _SATED_SPELLS[sid] == true) and 1 or 0
    data._msufA2_isHealerHot = (sid ~= 0 and _HEALER_HOT_SPELLS[sid] == true) and 1 or 0
    -- _msufA2_isIgnored is set per-frame in FilterAura (depends on per-unit cfg)
    return data
end

-- Full Scan

-- P1 PERFORMANCE: Slot buffer for GetAuraSlots varargs packing.
-- Eliminates 2-4 table allocations per FilterAndSort / FullScan call.
-- At 5 units × 60fps = 300-600 tables/sec → 0 tables/sec.
local _slotBuf = {}
local _slotBufPrevN = 0

-- Pack varargs from C_UnitAuras.GetAuraSlots() into reusable buffer.
-- Returns count (including continuation token at index 1).
-- Caller iterates: for i = 2, n do ... _slotBuf[i] ... end
local function _PackSlots(...)
    local n = select('#', ...)
    local buf = _slotBuf
    for i = 1, n do buf[i] = select(i, ...) end
    -- Nil-terminate: clear trailing entries from a previous longer pack
    for i = n + 1, _slotBufPrevN do buf[i] = nil end
    _slotBufPrevN = n
    return n
end

function Cache.FullScan(unit)
    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then return end
    -- PERF: Inlined EnsureUnit
    local s = _units[unit]
    if not s then s = { all = {}, epoch = 0, changed = true }; _units[unit] = s end
    -- P7: release all cached aura tables back to pool before wiping.
    for _, entry in next, s.all do _AuraRelease(entry) end
    wipe(s.all)
    s.changed = true
    s.epoch = s.epoch + 1
    s.structureChanged = true
    s.updatedIDs = nil
    local _st = API.Store; if _st and _st._epochs then _st._epochs[unit] = s.epoch end
    local slotsN = _PackSlots(_getSlots(unit, HELPFUL, 40))
    for i = 2, slotsN do
        local data = _getBySlot(unit, _slotBuf[i])
        if data and data.auraInstanceID then
            EnrichAura(unit, data, ClassifyHelpful(unit, data.auraInstanceID, data, true))
            s.all[data.auraInstanceID] = data
        end
    end

    slotsN = _PackSlots(_getSlots(unit, HARMFUL, 40))
    for i = 2, slotsN do
        local data = _getBySlot(unit, _slotBuf[i])
        if data and data.auraInstanceID then
            local aid = data.auraInstanceID
            local isHelpful, source = ClassifyHelpful(unit, aid, data, false)
            local existing = s.all[aid]
            if not (existing and existing._msufIsHelpful == true and isHelpful == false and source == "fallback") then
                EnrichAura(unit, data, isHelpful)
                s.all[aid] = data
            end
        end
    end
end

-- Delta Update (HOT PATH)
function Cache.OnUnitAura(unit, updateInfo)
    if not unit then return end
    if not _apisBound then BindAPIs() end

    if not updateInfo or updateInfo.isFullUpdate then
        -- PERF: If _units[unit] is nil (wiped by Store.InvalidateUnit on target/focus swap),
        -- skip immediate FullScan. FilterAndSort will rebuild on demand in the render pipeline.
        -- Saves 60-322µs from the target-click hot path.
        -- For party/raid units, _units[unit] is always non-nil → FullScan runs normally.
        -- Player can be the only live consumer when only reminders are enabled.
        if unit == "player" or _units[unit] then
            Cache.FullScan(unit)
        end
        return
    end

    -- PERF: Inlined EnsureUnit (after warmup, always hits cache)
    local s = _units[unit]
    if not s then s = { all = {}, epoch = 0, changed = true }; _units[unit] = s end

    local any = false
    -- PERF: track structure change inline instead of re-scanning the arrays
    -- via `next()` after the loops complete (2 redundant calls eliminated).
    local hasAdd, hasRem = false, false
    local updatedIDs = s.updatedIDs

    local added = updateInfo.addedAuras
    if added then
        -- PERF: numeric-for on Blizzard's dense array is ~30% faster than
        -- `for _, v in next, t do` in Lua 5.1 (FORLOOP vs TFORLOOP+next call).
        for i = 1, #added do
            local data = added[i]
            local aid = data.auraInstanceID
            if aid then
                -- P7: copy C data into pooled table so we own the lifecycle.
                -- Enables release-on-remove instead of abandoning to GC.
                local entry = _AuraAcquire()
                _AuraCopyFields(entry, data)
                local isHelpful = ClassifyHelpful(unit, aid, entry, nil)
                EnrichAura(unit, entry, isHelpful)
                s.all[aid] = entry
                any = true
                hasAdd = true
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            local aid = updated[i]
            local entry = s.all[aid]
            if entry then
                local fresh = _getByAid and _getByAid(unit, aid)
                if fresh then
                    local oldHelpful = entry._msufIsHelpful
                    local oldOwn = entry._msufIsPlayerAura
                    local oldBossFlag = ReadBossFlag(entry)
                    -- PERF: Lightweight update — only mutable fields (duration/stacks/raid).
                    -- Saves 8 field writes vs full _AuraCopyFields on the hottest path.
                    _AuraCopyFieldsUpdate(entry, fresh)
                    -- Defensive: invalidate cached bossFlag so next ReadBossFlag
                    -- re-reads entry.isBossAura. Reverted from a prior "drop this"
                    -- optimization — I cannot prove isBossAura is immutable for a
                    -- given auraInstanceID across Blizzard's implementation, and
                    -- the saving (~0.1µs/call) is far less than the risk of
                    -- onlyBoss/merge filter failure from stale cache.
                    entry._msufA2_bossFlag = nil
                    local newHelpful = ClassifyHelpful(unit, aid, fresh, entry._msufIsHelpful)
                    local newOwn = ClassifyPlayer(unit, aid, newHelpful)
                    entry._msufIsHelpful = newHelpful
                    entry._msufIsPlayerAura = newOwn
                    -- Blizzard can report filter/classification changes as an
                    -- update-only delta. If membership changed, force a normal
                    -- filter pass instead of reusing the previous visible list.
                    if oldHelpful ~= newHelpful or oldOwn ~= newOwn or oldBossFlag ~= ReadBossFlag(entry) then
                        hasAdd = true
                    end
                    if not updatedIDs then
                        updatedIDs = {}
                        s.updatedIDs = updatedIDs
                    end
                    updatedIDs[aid] = true
                    any = true
                else
                    -- Blizzard can report an aura as "updated" after it has
                    -- already expired. Treat a nil fresh lookup exactly like a
                    -- remove so stale icons cannot survive the next render.
                    s.all[aid] = nil
                    _AuraRelease(entry)
                    if updatedIDs then updatedIDs[aid] = nil end
                    any = true
                    hasRem = true
                end
            end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local aid = removed[i]
            local entry = s.all[aid]
            if entry then
                s.all[aid] = nil
                -- P7: return pooled table for reuse instead of abandoning to GC.
                _AuraRelease(entry)
                any = true
                hasRem = true
            end
        end
    end

    if any then
        s.changed = true
        s.epoch = s.epoch + 1
        -- PERF: Track whether list structure changed (add/remove) vs data-only update.
        -- update-only → FilterAndSort can skip full rescan and reuse previous output.
        if hasAdd or hasRem then
            s.structureChanged = true
            -- A structural delta can keep the visible count unchanged
            -- (remove one aura, add another). Do not leave an empty
            -- updatedIDs table behind, or RenderUnit may treat the pass as
            -- update-only and skip committing the changed icon slots.
            s.updatedIDs = nil
        end
        -- PERF: Inlined Store epoch tracking (was separate Store.OnUnitAura wrapper)
        local _st = API.Store; if _st and _st._epochs then _st._epochs[unit] = s.epoch end
    end
end

-- Invalidate / Query
function Cache.Invalidate(unit)
    local s = _units[unit]
    if s then
        s.changed = true
        s.epoch = s.epoch + 1
        s.structureChanged = true
        s.updatedIDs = nil
        s._lastFilterGen = nil
        s._lastNB = nil
        s._lastND = nil
    end
end

function Cache.InvalidateAll()
    for _, s in next, _units do
        s.changed = true
        s.epoch = s.epoch + 1
        s.structureChanged = true
        s.updatedIDs = nil
        -- Clear fast-path filter cache: options changes (Important, OnlyMine,
        -- Caps, IgnoreList, etc.) must force a full re-filter on next
        -- FilterAndSort, even when no aura add/remove occurred.
        s._lastFilterGen = nil
        s._lastNB = nil
        s._lastND = nil
    end
end

function Cache.HasChanges(unit)
    local s = _units[unit]
    return s and s.changed or false
end

function Cache.ClearChanged(unit)
    local s = _units[unit]
    if s then
        s.changed = false
        if s.updatedIDs then wipe(s.updatedIDs) end
    end
end

function Cache.GetUpdatedAuraIDs(unit)
    local s = _units[unit]
    return s and s.updatedIDs or nil
end

function Cache.GetEpoch(unit)
    local s = _units[unit]
    return s and s.epoch or 0
end

function Cache.GetAll(unit)
    local s = _units[unit]
    return s and s.all or nil
end

-- Secret-safe expiration check
local function BindDoesExpire()
    if _doesExpire then return end
    if C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime then
        _doesExpire = C_UnitAuras.DoesAuraHaveExpirationTime
    end
end

local _secretActive = nil
local _secretCheckAt = 0

local function SecretsActive()
    local now = GetTime()
    if _secretActive ~= nil and now < _secretCheckAt then
        return _secretActive
    end
    _secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _secretActive = (type(fn) == "function" and fn() == true) or false
    return _secretActive
end

Cache.SecretsActive = SecretsActive

-- Pre-allocated scratch tables (zero alloc steady-state)
local _mergedBossBuffScratch = {}
local _mergedBossDebuffScratch = {}

-- Shared filter logic (used by both unsorted + sorted paths)
-- Returns: accept (boolean)
local function FilterAura(data, aid, unit, isHelpful, isOwn, cfg, secretsNow, now,
                          lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue)
    -- PERF: Fast-exit when no filters active (covers ~90% of default configs)
    if cfg._noFilters then return true end

    -- Global Ignore List (O(1) hashtable lookup on pre-decoded spellId)
    local ignHash = cfg._ignoreHash
    if ignHash then
        local sid = data._msufA2_sid
        if sid ~= 0 and ignHash[sid] then return false end
    end

    -- Sated/Exhaustion: ZERO overhead when sated is shown normally (default).
    -- _checkSated is only true when showSated=false OR satedShowAt>0.
    if cfg._checkSated and data._msufA2_isSated == 1 then
        if cfg._showSated ~= true then
            return false
        end
        local thr = cfg._satedShowAt
        if thr > 0 then
            local exp = data.expirationTime
            if not exp or exp == 0 then return false end
            if exp - now > thr then return false end
        end
    end

    if isHelpful then
        if cfg._hideOtherBossHealAuras and data._msufA2_isHealerHot == 1 and not isOwn then return false end
        if cfg._buffsOnlyMine and not cfg._useMergeBuffs and not isOwn then return false end

        if cfg._hidePermanent and not secretsNow and lDoesExpire then
            local v = lDoesExpire(unit, aid)
            if v ~= nil then
                if lHasCanaccessvalue and lCanaccessvalue(v) ~= true then
                    -- secret → fail-open
                elseif lIssecretvalue and lIssecretvalue(v) then
                    -- secret → fail-open
                elseif v == false then
                    return false
                end
            end
        end

        if cfg._onlyBoss and ReadBossFlag(data) == 0 then return false end

        if cfg._onlyImpBuffs and lIsFiltered then
            if ReadAccessibleBool(lIsFiltered(unit, aid, HELPFUL_IMPORTANT)) == true then return false end
        end
    else
        if cfg._debuffTypeFilter and not DebuffMatchesSelectedDispelType(data, cfg) then return false end
        if cfg._debuffsOnlyMine and not cfg._useMergeDebuffs and not isOwn then
            if not (cfg._includeDispellableDebuffs and DebuffIsDispellable(unit, aid, data, lIsFiltered)) then
                return false
            end
        end
        if cfg._onlyBoss and ReadBossFlag(data) == 0 then return false end

        if cfg._onlyImpDebuffs and lIsFiltered then
            if ReadAccessibleBool(lIsFiltered(unit, aid, HARMFUL_IMPORTANT)) == true then
                if not (cfg._includeDispellableDebuffs and DebuffIsDispellable(unit, aid, data, lIsFiltered)) then
                    return false
                end
            end
        end
    end

    return true
end

-- Emit: place aura into output or boss scratch (handles merged mode)
-- Returns: nB, nD, nBossB, nBossD (updated counts)
local function EmitAura(data, isHelpful, isOwn, cfg,
                        buffOut, debuffOut, bossBufScratch, bossDebScratch,
                        nB, nD, nBossB, nBossD)
    if isHelpful then
        if cfg._useMergeBuffs then
            if isOwn then
                nB = nB + 1; buffOut[nB] = data
            elseif ReadBossFlag(data) == 1 then
                nBossB = nBossB + 1; bossBufScratch[nBossB] = data
            end
        else
            nB = nB + 1; buffOut[nB] = data
        end
    else
        if cfg._useMergeDebuffs then
            if isOwn then
                nD = nD + 1; debuffOut[nD] = data
            elseif ReadBossFlag(data) == 1 then
                nBossD = nBossD + 1; bossDebScratch[nBossD] = data
            end
        else
            nD = nD + 1; debuffOut[nD] = data
        end
    end
    return nB, nD, nBossB, nBossD
end

-- FilterAndSort: produce ordered visible list from cache
-- cfg.sortOrder:
--   0 or nil: Pure cache iteration (ZERO C API calls) — fastest path
--   1-6:      C++ sorted via GetAuraSlots, cache provides enrichment
local function PrepareFilterConfig(cfg, cfgGen)
    if cfg._msufA2FilterPrepGen == cfgGen and cfg._msufA2FilterPrepIgnoreCats == cfg.ignoreCats then
        return
    end
    cfg._msufA2FilterPrepGen = cfgGen
    cfg._msufA2FilterPrepIgnoreCats = cfg.ignoreCats

    cfg._maxBuffs  = cfg.maxBuffs or 12
    cfg._maxDebuffs = cfg.maxDebuffs or 12
    cfg._buffsOnlyMine    = cfg.buffsOnlyMine
    cfg._debuffsOnlyMine  = cfg.debuffsOnlyMine
    cfg._hidePermanent    = cfg.hidePermanentBuffs
    cfg._onlyBoss         = cfg.onlyBossAuras
    cfg._onlyImpBuffs     = cfg.onlyImportantBuffs
    cfg._onlyImpDebuffs   = cfg.onlyImportantDebuffs
    cfg._useMergeBuffs    = cfg.buffsOnlyMine and cfg.buffsIncludeBoss
    cfg._useMergeDebuffs  = cfg.debuffsOnlyMine and cfg.debuffsIncludeBoss
    cfg._includeDispellableDebuffs = (cfg.debuffsIncludeDispellable == true)
        and (cfg._debuffsOnlyMine or cfg._onlyImpDebuffs)
    cfg._debuffDispelMagic = (cfg.debuffDispelMagic == true)
    cfg._debuffDispelCurse = (cfg.debuffDispelCurse == true)
    cfg._debuffDispelPoison = (cfg.debuffDispelPoison == true)
    cfg._debuffDispelDisease = (cfg.debuffDispelDisease == true)
    cfg._debuffTypeFilter = cfg._debuffDispelMagic or cfg._debuffDispelCurse
        or cfg._debuffDispelPoison or cfg._debuffDispelDisease
    cfg._hideOtherBossHealAuras = (cfg.bossHealHideOthers == true)
    cfg._showSated = (cfg.showSated ~= false)
    local satedThr = cfg.satedShowAtSeconds
    cfg._satedShowAt = (type(satedThr) == "number" and satedThr > 0) and satedThr or 0
    cfg._checkSated = (cfg._showSated ~= true) or (cfg._satedShowAt > 0)

    local ic = cfg.ignoreCats
    cfg._ignoreHash = (type(ic) == "table" and next(ic) ~= nil) and Cache.BuildIgnoreHash(ic) or nil
    cfg._noFilters = not cfg._ignoreHash and not cfg._checkSated and not cfg._onlyBoss
        and not cfg._buffsOnlyMine and not cfg._debuffsOnlyMine
        and not cfg._hidePermanent and not cfg._onlyImpBuffs and not cfg._onlyImpDebuffs
        and not cfg._useMergeBuffs and not cfg._useMergeDebuffs
        and not cfg._includeDispellableDebuffs and not cfg._debuffTypeFilter
        and not cfg._hideOtherBossHealAuras
    cfg._sortOrder = cfg.sortOrder or cfg.capsSortOrder or 0
end

function Cache.FilterAndSort(unit, cfg, buffOut, debuffOut)
    if not _apisBound then BindAPIs() end
    BindDoesExpire()

    local s = _units[unit]
    if not s then
        Cache.FullScan(unit)
        s = _units[unit]
        if not s then return buffOut, 0, debuffOut, 0 end
    end

    -- PERF: Update-only fast path — when only duration/stacks changed (no add/remove),
    -- the filtered list is structurally identical. Skip full iteration + filter.
    -- Saves ~52µs per update-only event (the most common case in sustained combat).
    local cfgGen = cfg._gen or -1
    if not s.structureChanged and s._lastFilterGen == cfgGen
       and s._lastNB and s._lastND then
        s.changed = false
        return buffOut, s._lastNB, debuffOut, s._lastND
    end
    s.structureChanged = false

    -- Pre-compute config flags (avoid repeated table lookups in inner loop)
    PrepareFilterConfig(cfg, cfgGen)
    local maxBuffs  = cfg._maxBuffs
    local maxDebuffs = cfg._maxDebuffs
    -- Sated/Exhaustion runtime flags (from shared, not filters)
    -- PERF: _checkSated = false means sated code is COMPLETELY skipped in FilterAura.
    -- Only active when sated is hidden OR threshold is set (actual filtering work to do).
    -- Global Ignore List: ZERO overhead when no categories enabled.
    -- Only call BuildIgnoreHash if ignoreCats table exists and is non-empty.

    local secretsNow = cfg._hidePermanent and SecretsActive() or false
    local now = GetTime()  -- PERF: cache once, passed to FilterAura

    -- PERF: Pre-computed "no filters active" flag — single boolean check in FilterAura
    -- covers ~90% of default configurations where all filters are off.
    -- Localize for inner loop
    local lIsFiltered = _isFiltered
    local lDoesExpire = _doesExpire
    local lIssecretvalue = issecretvalue
    local lCanaccessvalue = canaccessvalue
    local lHasCanaccessvalue = _hasCanaccessvalue

    local nB, nD = 0, 0
    local nBossB, nBossD = 0, 0
    local bossBufScratch = cfg._useMergeBuffs and _mergedBossBuffScratch or nil
    local bossDebScratch = cfg._useMergeDebuffs and _mergedBossDebuffScratch or nil

    local sortOrder = cfg._sortOrder

    -- PERF: Hoist _noFilters gate out of FilterAura.
    -- FilterAura() line 613: `if cfg._noFilters then return true end` — so when
    -- _noFilters is set, the 13-arg call is wasted. Gate here instead: skip
    -- the call entirely when no filters are active (~90% of default configs).
    -- Saves one function call per aura × N auras × 39k FilterAndSort runs.
    local noFilters = cfg._noFilters

    -- PERF: Hoist merge flags. Inlining the non-merge EmitAura path saves
    -- one 12-arg function call + 4-return per emitted aura (~90% of users
    -- don't have boss-merge enabled). EmitAura's non-merge branch is just
    -- `nB = nB + 1; buffOut[nB] = data` — easy to inline.
    local useMergeBuffs = cfg._useMergeBuffs
    local useMergeDebuffs = cfg._useMergeDebuffs

    if sortOrder == 0 then
        -- FAST PATH: unsorted — pure cache iteration, ZERO C API calls
        for aid, data in next, s.all do
            if (nB + nBossB) >= maxBuffs and (nD + nBossD) >= maxDebuffs then break end

            local isHelpful = data._msufIsHelpful
            local isOwn     = data._msufIsPlayerAura

            if isHelpful and (nB + nBossB) < maxBuffs then
                if noFilters or FilterAura(data, aid, unit, true, isOwn, cfg, secretsNow, now,
                              lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                    if useMergeBuffs then
                        nB, nD, nBossB, nBossD = EmitAura(data, true, isOwn, cfg,
                            buffOut, debuffOut, bossBufScratch, bossDebScratch,
                            nB, nD, nBossB, nBossD)
                    else
                        nB = nB + 1
                        buffOut[nB] = data
                    end
                end
            elseif not isHelpful and (nD + nBossD) < maxDebuffs then
                if noFilters or FilterAura(data, aid, unit, false, isOwn, cfg, secretsNow, now,
                              lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                    if useMergeDebuffs then
                        nB, nD, nBossB, nBossD = EmitAura(data, false, isOwn, cfg,
                            buffOut, debuffOut, bossBufScratch, bossDebScratch,
                            nB, nD, nBossB, nBossD)
                    else
                        nD = nD + 1
                        debuffOut[nD] = data
                    end
                end
            end
        end
    else
        -- SORTED PATH: C++ provides ordering via GetAuraSlots.
        -- Cache provides enrichment (isPlayerAura, bossFlag) → saves
        -- 1 IsAuraFilteredOutByInstanceID call per aura.
        if not _getSlots or not _getBySlot then
            return buffOut, 0, debuffOut, 0
        end

        local allCache = s.all

        -- Process HELPFUL (preserves C++ sort order)
        if (nB + nBossB) < maxBuffs then
            -- P1: Reuse _slotBuf instead of allocating { _getSlots(...) } table
            local slotsN = _PackSlots(_getSlots(unit, HELPFUL, 40, sortOrder))
            for i = 2, slotsN do
                if (nB + nBossB) >= maxBuffs then break end
                local data = _getBySlot(unit, _slotBuf[i])
                if data then
                    local aid = data.auraInstanceID
                    if aid then
                        -- Reuse cache enrichment if available
                        local cached = allCache[aid]
                        local actualHelpful = ClassifyHelpful(unit, aid, data, true)
                        if cached then
                            data._msufIsHelpful    = actualHelpful
                            data._msufIsPlayerAura = (cached._msufIsHelpful == actualHelpful) and cached._msufIsPlayerAura or ClassifyPlayer(unit, aid, actualHelpful)
                            cached._msufIsHelpful = actualHelpful
                            cached._msufIsPlayerAura = data._msufIsPlayerAura
                            data._msufA2_bossFlag  = cached._msufA2_bossFlag
                            data._msufA2_sid       = cached._msufA2_sid
                            data._msufA2_isSated   = cached._msufA2_isSated
                            data._msufA2_isHealerHot = cached._msufA2_isHealerHot
                        else
                            EnrichAura(unit, data, actualHelpful)
                            allCache[aid] = data
                        end

                        local isOwn = data._msufIsPlayerAura
                        if actualHelpful and (noFilters or FilterAura(data, aid, unit, true, isOwn, cfg, secretsNow, now,
                                      lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue)) then
                            if useMergeBuffs then
                                nB, nD, nBossB, nBossD = EmitAura(data, true, isOwn, cfg,
                                    buffOut, debuffOut, bossBufScratch, bossDebScratch,
                                    nB, nD, nBossB, nBossD)
                            else
                                nB = nB + 1
                                buffOut[nB] = data
                            end
                        end
                    end
                end
            end
        end

        -- Process HARMFUL (preserves C++ sort order)
        if (nD + nBossD) < maxDebuffs then
            -- P1: Reuse _slotBuf instead of allocating { _getSlots(...) } table
            local slotsN = _PackSlots(_getSlots(unit, HARMFUL, 40, sortOrder))
            for i = 2, slotsN do
                if (nD + nBossD) >= maxDebuffs then break end
                local data = _getBySlot(unit, _slotBuf[i])
                if data then
                    local aid = data.auraInstanceID
                    if aid then
                        local cached = allCache[aid]
                        local actualHelpful = ClassifyHelpful(unit, aid, data, false)
                        if cached then
                            data._msufIsHelpful    = actualHelpful
                            data._msufIsPlayerAura = (cached._msufIsHelpful == actualHelpful) and cached._msufIsPlayerAura or ClassifyPlayer(unit, aid, actualHelpful)
                            cached._msufIsHelpful = actualHelpful
                            cached._msufIsPlayerAura = data._msufIsPlayerAura
                            data._msufA2_bossFlag  = cached._msufA2_bossFlag
                            data._msufA2_sid       = cached._msufA2_sid
                            data._msufA2_isSated   = cached._msufA2_isSated
                            data._msufA2_isHealerHot = cached._msufA2_isHealerHot
                        else
                            EnrichAura(unit, data, actualHelpful)
                            allCache[aid] = data
                        end

                        local isOwn = data._msufIsPlayerAura
                        if (not actualHelpful) and (noFilters or FilterAura(data, aid, unit, false, isOwn, cfg, secretsNow, now,
                                      lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue)) then
                            if useMergeDebuffs then
                                nB, nD, nBossB, nBossD = EmitAura(data, false, isOwn, cfg,
                                    buffOut, debuffOut, bossBufScratch, bossDebScratch,
                                    nB, nD, nBossB, nBossD)
                            else
                                nD = nD + 1
                                debuffOut[nD] = data
                            end
                        end
                    end
                end
            end
        end
    end

    -- Merged: append boss auras after player auras
    if cfg._useMergeBuffs and nBossB > 0 then
        for i = 1, nBossB do
            if nB >= maxBuffs then break end
            nB = nB + 1
            buffOut[nB] = bossBufScratch[i]
        end
        for i = nBossB, 1, -1 do bossBufScratch[i] = nil end
    end
    if cfg._useMergeDebuffs and nBossD > 0 then
        for i = 1, nBossD do
            if nD >= maxDebuffs then break end
            nD = nD + 1
            debuffOut[nD] = bossDebScratch[i]
        end
        for i = nBossD, 1, -1 do bossDebScratch[i] = nil end
    end

    -- Tail clear
    local prevBN = buffOut._msufA2_n or 0
    if nB < prevBN then
        for i = nB + 1, prevBN do buffOut[i] = nil end
    end
    buffOut._msufA2_n = nB

    local prevDN = debuffOut._msufA2_n or 0
    if nD < prevDN then
        for i = nD + 1, prevDN do debuffOut[i] = nil end
    end
    debuffOut._msufA2_n = nD

    -- PERF: Cache results for update-only fast path
    s._lastNB = nB
    s._lastND = nD
    s._lastFilterGen = cfgGen

    return buffOut, nB, debuffOut, nD
end

-- Wire into API.Store
API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store
Store._epochs = Store._epochs or {}

-- PERF: Store.OnUnitAura = Cache.OnUnitAura directly (epoch tracking inlined into Cache)
Store.OnUnitAura = Cache.OnUnitAura

Store.InvalidateUnit = function(unit)
    -- PERF: Wipe cache only — do NOT FullScan here.
    -- WoW fires UNIT_AURA (isFullUpdate=true) immediately after target/focus change.
    -- That triggers Cache.OnUnitAura → FullScan. Pre-scanning here is redundant
    -- and costs 200-400µs per target click (was the #1 spike cause).
    _units[unit] = nil
    Store._epochs[unit] = nil
end

Store.FullScanUnit = function(unit)
    if unit then
        Cache.FullScan(unit)
    end
end

if not Store.GetEpoch then Store.GetEpoch = function(unit) return Cache.GetEpoch(unit) end end
if not Store.GetEpochSig then Store.GetEpochSig = function(unit) return Cache.GetEpoch(unit) end end

-- MSUF_A2_Collect.lua

-- MSUF_A2_Collect.lua  Auras 3.0 — Fast-Path Helpers
-- Responsibilities:
--   1. Fast-path helpers: GetDurationObjectFast, GetStackCountFast,
--      HasExpirationFast (used by Icons.lua hot path, zero guard overhead)
--   2. Guarded helpers: GetDurationObject, GetStackCount, HasExpiration
--   3. Secret-safe utility exports: SecretsActive, IsBossAura, IsSV
--   4. Store table creation (real methods provided by Cache.lua)
-- All aura collection removed — Cache.lua handles everything via
-- delta (sortOrder==0) and C++ sorted (sortOrder!=0) paths.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type = type
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_COLLECT_LOADED then return end
ns.__MSUF_A2_COLLECT_LOADED = true

API.Collect = (type(API.Collect) == "table") and API.Collect or {}
local Collect = API.Collect

-- Hot locals
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

local _doesExpire, _getDuration, _getStackCount
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _doesExpire    = C_UnitAuras.DoesAuraHaveExpirationTime
    _getDuration   = C_UnitAuras.GetAuraDuration
    _getStackCount = C_UnitAuras.GetAuraApplicationDisplayCount
    _apisBound = true
end

-- Secret-safe helpers

local function IsSV(v)
    if v == nil then return false end
    if issecretvalue then return (issecretvalue(v) == true) end
    return false
end

local _secretActive = nil
local _secretCheckAt = 0

local function SecretsActive()
    local now = GetTime()
    if _secretActive ~= nil and now < _secretCheckAt then
        return _secretActive
    end
    _secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _secretActive = (type(fn) == "function" and fn() == true) or false
    return _secretActive
end

local function IsBossAura(data)
    if not data then return false end
    local f = data._msufA2_bossFlag
    if f ~= nil then return (f == 1) end
    local v = data.isBossAura
    if v == nil then
        data._msufA2_bossFlag = -1
        return false
    end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then data._msufA2_bossFlag = -1; return false end
    elseif issecretvalue and issecretvalue(v) == true then
        data._msufA2_bossFlag = -1
        return false
    end
    f = (v == true) and 1 or 0
    data._msufA2_bossFlag = f
    return (f == 1)
end

-- Store table (created here; Cache.lua provides real implementations)
API.Store = (type(API.Store) == "table") and API.Store or {}
API.Store._epochs = API.Store._epochs or {}

-- No-op stubs (Render.lua / external addons may still reference these)
Collect.InvalidateCache = function() end
function Collect.SetScanFlags() end
function Collect.SetScanLimits() end
function Collect.SetSortOrder() end
function Collect.SetSortReverse() end
function Collect.SetUnitSortOrder() end

-- Stack count / Duration / Expiration (guarded)

function Collect.GetStackCount(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getStackCount) ~= "function" then return nil end
    return _getStackCount(unit, auraInstanceID, 2, 99)
end

function Collect.GetDurationObject(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getDuration) ~= "function" then return nil end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.HasExpiration(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_doesExpire) ~= "function" then return nil end
    local v = _doesExpire(unit, auraInstanceID)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- Fast-path (no guards — Icons.lua binds after APIs confirmed available)

function Collect.GetDurationObjectFast(unit, aid)
    if not _getDuration then BindAPIs(); if not _getDuration then return nil end end
    local obj = _getDuration(unit, aid)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.GetStackCountFast(unit, aid)
    if not _getStackCount then BindAPIs(); if not _getStackCount then return nil end end
    return _getStackCount(unit, aid, 2, 99)
end

function Collect.HasExpirationFast(unit, aid)
    if not _doesExpire then BindAPIs(); if not _doesExpire then return nil end end
    local v = _doesExpire(unit, aid)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- Exports
Collect.SecretsActive = SecretsActive
Collect.IsBossAura = IsBossAura
Collect.IsSV = IsSV

-- MSUF_A2_Icons.lua

-- MSUF_A2_Icons.lua  Auras 3.0 Icon Factory + Visual Commit + Layout
-- Replaces the core of MSUF_A2_Apply.lua
-- Responsibilities:
--   1. Icon pool (AcquireIcon / HideUnused)
--   2. Visual commit (CommitIcon  texture, cooldown, stacks, border)
--   3. Grid layout (LayoutIcons)
--   4. Refresh helpers (RefreshAssignedIcons)
-- Secret-safe: uses Collect.GetDurationObject() for timers,
-- Collect.GetStackCount() for stacks, never reads secret fields.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- PERF LOCALS (Auras2 runtime)
local type, tostring = type, tostring
local pairs, ipairs, next = pairs, ipairs, next
local math_max = math.max
local CreateFrame, GetTime = CreateFrame, GetTime
local C_UnitAuras = C_UnitAuras
local C_CurveUtil = C_CurveUtil
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Icons = (type(API.Icons) == "table") and API.Icons or {}
local Icons = API.Icons

-- Also register as API.Apply for backward compatibility
API.Apply = (type(API.Apply) == "table") and API.Apply or {}
local Apply = API.Apply

-- Hot locals
local GameTooltip = GameTooltip
local floor = math.floor
local max = math_max
local C_Timer = C_Timer

-- Secret value detector (Midnight/Beta)
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

-- Lazy-bound references
local Collect   -- bound on first use
local Colors    -- API.Colors
local Masque    -- API.Masque
local CT        -- API.CooldownText (cooldown text manager)

local function EnsureBindings()
    if not Collect then Collect = API.Collect end
    if not Colors then Colors = API.Colors end
    if not Masque then Masque = API.Masque end
    if not CT then CT = API.CooldownText end
end

--  Fast-path Collect helpers (skip guard checks in hot path)
local _getDurationFast   -- Collect.GetDurationObjectFast (bound on first use)
local _getStackCountFast -- Collect.GetStackCountFast
local _hasExpirationFast -- Collect.HasExpirationFast
-- PERF: Direct C API refs for inlined CommitIcon path (skip wrapper function calls)
local _getDurationDirect   -- C_UnitAuras.GetAuraDuration
local _getStackCountDirect -- C_UnitAuras.GetAuraApplicationDisplayCount
local _getByAidDirect      -- C_UnitAuras.GetAuraDataByAuraInstanceID (numeric timer fallback)
local _fastPathBound = false

local function BindFastPaths()
    if _fastPathBound then return end
    if not Collect then return end
    _getDurationFast   = Collect.GetDurationObjectFast or Collect.GetDurationObject
    _getStackCountFast = Collect.GetStackCountFast or Collect.GetStackCount
    _hasExpirationFast = Collect.HasExpirationFast or Collect.HasExpiration
    -- Direct C API for inlined hot path
    local CUA = _G.C_UnitAuras
    if CUA then
        _getDurationDirect   = CUA.GetAuraDuration
        _getStackCountDirect = CUA.GetAuraApplicationDisplayCount
        _getByAidDirect      = CUA.GetAuraDataByAuraInstanceID
    end
    _fastPathBound = true
end

local function ReadAccessibleNumber(v)
    if v == nil then return nil end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then return nil end
    elseif issecretvalue and issecretvalue(v) == true then
        return nil
    end
    return tonumber(v)
end

local function ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, durationValue)
    if not icon or not cd or not cd.SetCooldown then return false end

    local data
    if _getByAidDirect and unit and aid then
        data = _getByAidDirect(unit, aid)
    end
    if type(data) ~= "table" then
        data = aura
    end
    if type(data) ~= "table" then return false end

    local duration = ReadAccessibleNumber(durationValue)
    if not duration then
        duration = ReadAccessibleNumber(data.duration)
    end
    local expiration = ReadAccessibleNumber(data.expirationTime)
    if not duration or not expiration or duration <= 0 or expiration <= 0 then
        return false
    end

    local remaining = expiration - GetTime()
    if remaining <= 0 then
        return false
    end

    cd:SetCooldown(expiration - duration, duration)
    icon._msufA2_durationObj = nil
    cd._msufA2_durationObj = nil
    icon._msufA2_cdNumericFallback = true
    return true
end

-- Phase 8: file-scope locals for Icons._ methods (eliminates hash-table
-- lookup per icon in tight loops).  Assigned after method definitions.
local _fast_ApplyTimer
local _fast_RefreshTimer
local _fast_ApplyStacks
local _fast_ApplyOwnHighlight
local _fast_ApplyDispelBorder
local _fast_ApplyPandemic
local _RefreshDynamicIfNeeded

--  Cached shared.* flags (resolve once per configGen, not per icon)
local _sharedFlagsGen   = -1
local _showSwipe        = false
local _showText         = true
local _swipeReverse     = false
local _showStacks       = false
local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local _wantBuffHL       = false
local _wantDebuffHL     = false
local _useBlizzardTimer = true   -- PERF C++ DELEGATION: Blizzard native countdown text (default)
local _useDispelBorders = false  -- dispel-type border coloring for debuffs
local _clickThrough     = false  -- true = all auras non-interactive (mouse pass-through)
local _showTooltip      = true   -- cached shared.showTooltip (for click-through + tooltip combo)
local _masqueEnabled    = false  -- cached shared.masqueEnabled (gates per-icon backdrop call)
local _showPandemic     = false  -- pandemic window active (any mode except OFF)
local _pandemicMode     = 0      -- 0=OFF 1=BORDER 2=PULSE 3=GLOW
local _panR, _panG, _panB = 0.0, 0.4, 1.0  -- cached pandemic color

--  Debuff dispel-type color lookup (Ã‚Â  la R41z0r / Blizzard)
-- Maps dispel index  Blizzard color object; used for both manual
-- fallback and the C_CurveUtil-based GetAuraDispelTypeColor() API.
local _debuffColorByIndex = {
    [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
    [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
    [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
    [4] = _G.DEBUFF_TYPE_POISON_COLOR,
    [5] = _G.DEBUFF_TYPE_BLEED_COLOR,
    [0] = _G.DEBUFF_TYPE_NONE_COLOR,
}
local _dispelNameToIndex = {
    Magic   = 1,
    Curse   = 2,
    Disease = 3,
    Poison  = 4,
    Bleed   = 5,
    None    = 0,
}

-- Build a step-curve for C_UnitAuras.GetAuraDispelTypeColor() (secret-safe).
-- This mirrors R41z0r's approach: one-time init, reused every commit.
local _debuffColorCurve
do
    local ok, curve = pcall(function()
        if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
        if not Enum or not Enum.LuaCurveType or not Enum.LuaCurveType.Step then return nil end
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        for idx, col in pairs(_debuffColorByIndex) do
            if col then c:AddPoint(idx, col) end
        end
        return c
    end)
    _debuffColorCurve = ok and curve or nil
end

-- Pandemic window step-curve: returns 1 when ≤30% remaining, 0 otherwise.
-- Secret-safe: EvaluateRemainingPercent + IsZero, zero value comparisons.
local _pandemicCurve
local _pandemicEvalBool  -- C_CurveUtil.EvaluateColorValueFromBoolean
do
    if C_CurveUtil and C_CurveUtil.CreateCurve
       and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        local ok2, curve2 = pcall(function()
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 1)    -- 0-30% remaining → 1 (in pandemic window)
            c:AddPoint(0.3, 0)  -- 30%+ remaining  → 0
            return c
        end)
        if ok2 and curve2 then _pandemicCurve = curve2 end
    end
    _pandemicEvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean or nil
end

-- Manual fallback: dispelName string  r, g, b
local function GetDebuffColorFromName(name)
    local idx = _dispelNameToIndex[name] or 0
    local col = _debuffColorByIndex[idx] or _debuffColorByIndex[0]
    if not col then return 1, 0, 0 end
    if col.GetRGBA then return col:GetRGBA() end
    if col.GetRGB  then return col:GetRGB()  end
    if col.r       then return col.r, col.g, col.b end
    return col[1] or 1, col[2] or 0, col[3] or 0
end

-- Cached global MSUF font family (resolved once, updated by ApplyFontsFromGlobal)
local _globalFontPath   = nil   -- nil = not yet resolved
local _globalFontFlags  = "OUTLINE"

-- Resolve the global MSUF font (lazy; caches after first call)
local function ResolveGlobalFont()
    if _globalFontPath then return _globalFontPath, _globalFontFlags end
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        local p, fl = gfs()
        if type(p) == "string" then _globalFontPath = p end
        if type(fl) == "string" then _globalFontFlags = fl end
    end
    return _globalFontPath, _globalFontFlags
end

local function ResolveGlobalFontKey()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return (g and g.fontKey) or "FRIZQT"
end

local function RefreshSharedFlags(shared, gen)
    if not shared then return end
    if _sharedFlagsGen == gen then return end
    _sharedFlagsGen = gen
    _showSwipe    = (shared and shared.showCooldownSwipe == true) or false
    _showText     = (shared and shared.showCooldownText ~= false) -- default true
    _swipeReverse = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    _showStacks   = (shared and shared.showStackCount ~= false) -- default true
    _wantBuffHL   = (shared and shared.highlightOwnBuffs == true) or false
    _wantDebuffHL = (shared and shared.highlightOwnDebuffs == true) or false
    -- PERF C++ DELEGATION: Default to Blizzard native countdown text.
    -- Only fall back to Lua CooldownText manager if user explicitly disables it.
    _useBlizzardTimer = not (shared and shared.useBlizzardTimerText == false)
    _useDispelBorders = (shared and shared.useDebuffTypeBorders == true) or false
    _clickThrough     = (shared and shared.clickThroughAuras == true) or false
    _showTooltip      = (shared and shared.showTooltip == true) or false
    _G.MSUF_A2_ClickThrough = _clickThrough
    _G.MSUF_A2_ShowTooltip  = _showTooltip
    _masqueEnabled    = (shared and shared.masqueEnabled == true) or false
    -- Pandemic mode: "OFF"/"BORDER"/"PULSE"/"GLOW" → numeric (0/1/2/3)
    -- Migration: old boolean showPandemic=true → PULSE
    do
        local pm = shared and shared.pandemicMode
        if pm == nil and shared then pm = shared.showPandemic end -- migration
        if pm == true then pm = "PULSE" end
        if pm == "BORDER" then _pandemicMode = 1
        elseif pm == "PULSE" then _pandemicMode = 2
        elseif pm == "GLOW" then _pandemicMode = 3
        else _pandemicMode = 0
        end
        _showPandemic = (_pandemicMode > 0) and (_pandemicCurve ~= nil)
        -- Start/stop pandemic ticker based on feature state (zero idle overhead when off)
        if _showPandemic then
            if API._StartPandemicTicker then API._StartPandemicTicker() end
        else
            if API._StopPandemicTicker then API._StopPandemicTicker() end
        end
        -- Cache color
        local pr = shared and shared.pandemicR; if type(pr) == "number" then _panR = pr end
        local pg = shared and shared.pandemicG; if type(pg) == "number" then _panG = pg end
        local pb = shared and shared.pandemicB; if type(pb) == "number" then _panB = pb end
    end
end

-- Masque backdrop compatibility
-- When Masque skins are used (often non-square shapes like circles), MSUF's
-- subtle background texture can remain visible as a square "box" behind the
-- skinned icon. This can also appear intermittently due to icon reuse.
-- Fix: diff-gated show/hide of the background texture whenever Masque is
-- enabled and the icon has been registered with Masque.

local function ApplyMasqueBackdrop(icon, shared)
    local bg = icon and icon._msufBG
    if not bg then return end

    local hide = (shared and shared.masqueEnabled == true and icon.MSUF_MasqueAdded == true) or false
    if icon._msufA2_bgHidden ~= hide then
        icon._msufA2_bgHidden = hide
        if hide then
            bg:Hide()
        else
            bg:Show()
        end
    end
end

-- Text config resolution (per-icon; cached by configGen)
-- Applies stack/cooldown text sizes + offsets from shared + per-unit layout
-- Zero per-frame cost: runs only when configGen changes.

local function ResolveTextConfig(icon, unit, shared, gen)
    if not icon then return end
    if icon._msufA2_textCfgGen == gen then return end
    icon._msufA2_textCfgGen = gen

    local stackSize = (shared and shared.stackTextSize) or 14
    local cdSize = (shared and shared.cooldownTextSize) or 14

    local stackOffX = (shared and shared.stackTextOffsetX)
    if type(stackOffX) ~= "number" then stackOffX = -1 end
    local stackOffY = (shared and shared.stackTextOffsetY)
    if type(stackOffY) ~= "number" then stackOffY = 1 end
    local cdOffX = (shared and shared.cooldownTextOffsetX) or 0
    local cdOffY = (shared and shared.cooldownTextOffsetY) or 0

    -- Per-unit overrides (a2.perUnit[unit].layout)
    local a2 = nil
    local DB = API and API.DB
    local cache = DB and DB.cache
    if cache and cache.ready and type(cache.a2) == "table" then
        a2 = cache.a2
    else
        -- Fallback for early load-order: query via API.GetDB if present
        local getdb = API and API.GetDB
        if type(getdb) == "function" then
            local aa, ss = getdb()
            if type(aa) == "table" then a2 = aa end
            if not shared and type(ss) == "table" then shared = ss end
        end
    end

    local pu = a2 and a2.perUnit and unit and a2.perUnit[unit]
    if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
        local lay = pu.layout
        if type(lay.stackTextSize) == "number" then stackSize = lay.stackTextSize end
        if type(lay.cooldownTextSize) == "number" then cdSize = lay.cooldownTextSize end

        if type(lay.stackTextOffsetX) == "number" then stackOffX = lay.stackTextOffsetX end
        if type(lay.stackTextOffsetY) == "number" then stackOffY = lay.stackTextOffsetY end
        if type(lay.cooldownTextOffsetX) == "number" then cdOffX = lay.cooldownTextOffsetX end
        if type(lay.cooldownTextOffsetY) == "number" then cdOffY = lay.cooldownTextOffsetY end
    end

    if type(stackSize) ~= "number" or stackSize <= 0 then stackSize = 14 end
    if type(cdSize) ~= "number" or cdSize <= 0 then cdSize = 14 end
    if type(stackOffX) ~= "number" then stackOffX = 0 end
    if type(stackOffY) ~= "number" then stackOffY = 0 end
    if type(cdOffX) ~= "number" then cdOffX = 0 end
    if type(cdOffY) ~= "number" then cdOffY = 0 end

    icon._msufA2_stackTextSize = stackSize
    icon._msufA2_cooldownTextSize = cdSize
    icon._msufA2_stackTextOffsetX = stackOffX
    icon._msufA2_stackTextOffsetY = stackOffY
    icon._msufA2_cooldownTextOffsetX = cdOffX
    icon._msufA2_cooldownTextOffsetY = cdOffY
end

-- DB access
local function GetAuras2DB()
    local api = ns and ns.MSUF_Auras2
    if api and api.GetDB then return api.GetDB() end
    if not _G.MSUF_DB then
        local ensureDB = _G.MSUF_EnsureDB
        if type(ensureDB) == "function" then ensureDB() end
    end
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    return a2, a2 and a2.shared
end

-- Color helpers (late-bound from API.Colors or fallback)

local function GetOwnBuffHighlightRGB()
    local f = _G.MSUF_A2_GetOwnBuffHighlightRGB
    if type(f) == "function" then return f() end
    return 1.0, 0.85, 0.2
end

local function GetOwnDebuffHighlightRGB()
    local f = _G.MSUF_A2_GetOwnDebuffHighlightRGB
    if type(f) == "function" then return f() end
    return 1.0, 0.3, 0.3
end

local function GetStackCountRGB()
    local f = _G.MSUF_A2_GetStackCountRGB
    if type(f) == "function" then return f() end
    return 1.0, 1.0, 1.0
end

-- Icon Pool

-- Icons are stored on container._msufIcons[index]
-- Each icon is a Button with: .tex, .cooldown, .count, .border, .overlay

local function HideButtonStateTexture(texture)
    if not texture then return end
    if texture.SetAlpha then texture:SetAlpha(0) end
    if texture.Hide then texture:Hide() end
end

local function SuppressAuraButtonState(icon)
    if not icon then return end
    if icon.SetButtonState then icon:SetButtonState("NORMAL", false) end
    if icon.UnlockHighlight then icon:UnlockHighlight() end
    HideButtonStateTexture(icon.GetHighlightTexture and icon:GetHighlightTexture())
    HideButtonStateTexture(icon.GetPushedTexture and icon:GetPushedTexture())
    HideButtonStateTexture(icon.GetCheckedTexture and icon:GetCheckedTexture())
end

local function RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
    if not icon then return end

    expectedSize = tonumber(expectedSize) or tonumber(icon._msufA2_lastSize)
    if expectedSize and expectedSize > 0 and icon.SetSize then
        local w = icon.GetWidth and icon:GetWidth()
        local h = icon.GetHeight and icon:GetHeight()
        if w ~= expectedSize or h ~= expectedSize then
            icon._msufA2_restoringGeometry = true
            icon:SetSize(expectedSize, expectedSize)
            icon._msufA2_restoringGeometry = nil
        end
    end

    expectedScale = tonumber(expectedScale) or tonumber(icon._msufA2_baseScale)
    if expectedScale and expectedScale > 0 and icon.SetScale and icon.GetScale then
        local scale = icon:GetScale()
        if scale ~= expectedScale then
            icon:SetScale(expectedScale)
        end
    end

    SuppressAuraButtonState(icon)
end

local function RestoreAuraButtonGeometrySoon(icon, expectedSize, expectedScale)
    RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if icon and icon._msufA2_hovering then
                RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
            end
        end)
    end
end

-- Mouse interaction state helper (safe on 12.0+)
-- 0 = normal (hover + clicks)
-- 1 = tooltip only (hover on, clicks off)
-- 2 = full click-through (hover off, clicks off)
local function ApplyMouseState(icon, wantMS)
    if not icon then return end
    if icon._msufA2_mouseState == wantMS then return end
    icon._msufA2_mouseState = wantMS

    local wantHover = (wantMS ~= 2)
    local wantClicks = (wantMS == 0)

    if icon.SetMouseMotionEnabled then
        icon:SetMouseMotionEnabled(wantHover)
    end
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(wantClicks)
    end

    -- Backward-compatible fallback for older clients/widgets without the split API.
    if (not icon.SetMouseMotionEnabled) or (not icon.SetMouseClickEnabled) then
        icon:EnableMouse(wantHover or wantClicks)
        if icon.RegisterForClicks then
            if wantClicks then
                icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            else
                icon:RegisterForClicks()
            end
        end
    end
end

-- Export for MSUF_A2_EditMode.lua (file-scope locals are invisible across files)
_G.MSUF_A2_ApplyMouseState = ApplyMouseState
_G.MSUF_A2_ResolveTextConfig = ResolveTextConfig

local function CreateIcon(container, index)
    local icon = CreateFrame("Button", nil, container)
    icon:SetSize(26, 26)
    icon._msufA2_baseScale = (icon.GetScale and icon:GetScale()) or 1

    -- Stack count overlay frame (keeps stacks above Masque/borders)
    local countFrame = CreateFrame("Frame", nil, icon)
    countFrame:SetAllPoints(icon)
    countFrame:SetFrameLevel(icon:GetFrameLevel() + 10)
    icon.countFrame = countFrame

    ApplyMouseState(icon, 0)
    SuppressAuraButtonState(icon)
    icon._msufA2_container = container

    -- Texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.tex = tex

    -- Cooldown
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)
    cd:SetSwipeColor(0, 0, 0, 0.65)
    cd:SetHideCountdownNumbers(true)
    cd._msufA2_lastHideNumbers = true
    cd._msufA2_lastUseAuraDisplayTime = false
    icon.cooldown = cd

    -- Stack count text
    local count = (icon.countFrame or icon):CreateFontString(nil, "OVERLAY")
    -- Use global MSUF font when available, fallback to default
    local _initFont, _initFlags = "Fonts\\FRIZQT__.TTF", "OUTLINE"
    local _gfs = _G.MSUF_GetGlobalFontSettings
    if type(_gfs) == "function" then
        local p, fl = _gfs()
        if type(p) == "string" then _initFont = p end
        if type(fl) == "string" then _initFlags = fl end
    end
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(count, _initFont, 14, _initFlags, ResolveGlobalFontKey())
    else
        count:SetFont(_initFont, 14, _initFlags)
    end
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(GetStackCountRGB())
    icon.count = count

    -- Own-aura highlight glow (hidden by default)
    local glow = icon:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(1, 1, 1, 0.3)
    glow:Hide()
    icon._msufOwnGlow = glow

    -- Dispel-type colored border overlay (hidden by default)
    -- Uses Blizzard's standard debuff overlay texture, colored per dispel type.
    local dispelBdr = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    dispelBdr:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    dispelBdr:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    dispelBdr:SetAllPoints(icon)
    dispelBdr:Hide()
    icon._msufDispelBorder = dispelBdr

    -- Pandemic window border/glow (hidden by default)
    -- Architecture: outer frame (alpha gate via SetAlpha(secret)) × inner child (visuals + animation).
    -- Modes: BORDER (static border), PULSE (border + glow + throb), GLOW (soft glow + throb).
    do
        -- Outer: alpha gate (receives secret curve result)
        local pf = CreateFrame("Frame", nil, icon)
        pf:SetAllPoints(icon)
        pf:SetFrameLevel(icon:GetFrameLevel() + 8)
        pf:SetAlpha(0)
        -- Inner: holds textures + animation
        local inner = CreateFrame("Frame", nil, pf)
        inner:SetAllPoints(pf)
        -- Border texture (Blizzard debuff overlay, bright green)
        local pt = inner:CreateTexture(nil, "OVERLAY", nil, 7)
        pt:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        pt:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        pt:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        pt:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        pt:SetVertexColor(0.0, 0.4, 1.0, 1)
        -- Soft outer glow (color texture, larger inset)
        local pg = inner:CreateTexture(nil, "OVERLAY", nil, 6)
        pg:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
        pg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
        pg:SetColorTexture(0.0, 0.4, 1.0, 0.35)
        -- Alpha pulse animation on inner
        local ag = inner:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local pulse = ag:CreateAnimation("Alpha")
        pulse:SetFromAlpha(0.35)
        pulse:SetToAlpha(1.0)
        pulse:SetDuration(0.4)
        pulse:SetSmoothing("IN_OUT")
        -- Store refs for per-mode reconfiguration
        pf._border = pt
        pf._glow   = pg
        pf._anim   = ag
        pf._inner  = inner
        pf:Hide()
        icon._msufPandemic = pf
        icon._msufPanLastMode = 0  -- tracks applied mode for diff-gate
    end

    -- Background (subtle dark backdrop)
    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    icon._msufBG = bg

    -- Tooltip support
    icon:SetScript("OnEnter", function(self)
        self._msufA2_hovering = true
        local expectedSize = self._msufA2_lastSize or (self.GetWidth and self:GetWidth()) or 26
        local expectedScale = (self.GetScale and self:GetScale()) or self._msufA2_baseScale or 1
        local _, shared = GetAuras2DB()
        if shared and shared.showTooltip ~= true then
            RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
            return
        end
        local unit = self._msufUnit
        local aid = self._msufAuraInstanceID
        if not unit or not aid then
            RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        -- Secret-safe: SetUnitAuraByAuraInstanceID handles secrets internally
        if self._msufFilter == "HARMFUL" and GameTooltip.SetUnitDebuffByAuraInstanceID then
            GameTooltip:SetUnitDebuffByAuraInstanceID(unit, aid)
        elseif GameTooltip.SetUnitBuffByAuraInstanceID then
            GameTooltip:SetUnitBuffByAuraInstanceID(unit, aid)
        elseif GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(unit, aid, self._msufFilter or "HELPFUL")
        end
        GameTooltip:Show()
        RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
    end)

    icon:SetScript("OnLeave", function(self)
        self._msufA2_hovering = nil
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
        RestoreAuraButtonGeometry(self)
    end)
    icon:HookScript("OnSizeChanged", function(self, width, height)
        if self._msufA2_restoringGeometry or self._msufA2_hovering ~= true then return end
        local expectedSize = tonumber(self._msufA2_lastSize)
        if expectedSize and expectedSize > 0 and (width ~= expectedSize or height ~= expectedSize) then
            RestoreAuraButtonGeometrySoon(self, expectedSize, self._msufA2_baseScale)
        end
    end)

    -- Masque integration (MSA pattern: register button, regions built in AddButton)
    EnsureBindings()
    local _, shared = GetAuras2DB()
    if Masque and Masque.IsEnabled and Masque.IsEnabled(shared) and Masque.AddButton then
        if Masque.AddButton(icon, shared) then
            icon.MSUF_MasqueAdded = true
        end
    end
    RestoreAuraButtonGeometry(icon, icon._msufA2_lastSize or icon:GetWidth(), icon._msufA2_baseScale)

    return icon
end

local ClearCooldownVisual

function Icons.AcquireIcon(container, index)
    if not container then return nil end

    local pool = container._msufIcons
    if not pool then
        pool = {}
        container._msufIcons = pool
    end

    -- Track high water mark for HideUnused bounded iteration
    local activeN = container._msufA2_activeN or 0
    if index > activeN then container._msufA2_activeN = index end

    local icon = pool[index]
    if icon then
        -- PERF: Skip Show() if already visible (IsShown() is cheaper than Show())
        if not icon:IsShown() then
            icon:Show()
        end
        return icon
    end

    icon = CreateIcon(container, index)
    pool[index] = icon

    -- Keep an icon map on the container for fast delta lookups
    if not container._msufA2_iconByAid then
        container._msufA2_iconByAid = {}
    end

    icon:Show()
    return icon
end

function Icons.HideUnused(container, fromIndex)
    if not container then return end
    local pool = container._msufIcons
    if not pool then return end

    -- Bound iteration to the last known active count (high water mark).
    local highWater = container._msufA2_activeN or 0

    -- PERF: Early exit if nothing to hide (fromIndex > active count)
    -- This skips the loop entirely when all icons are already in use
    if fromIndex > highWater then
        -- Still update active count for caller's bookkeeping
        container._msufA2_activeN = fromIndex - 1
        return
    end

    -- PERF: Early exit if activeN already matches (no change)
    if highWater == fromIndex - 1 then return end

    local map = container._msufA2_iconByAid
    for i = fromIndex, highWater do
        local icon = pool[i]
        if icon then
            if icon:IsShown() then
                if ClearCooldownVisual and icon.cooldown then
                    ClearCooldownVisual(icon, icon.cooldown)
                end
                icon:Hide()
                local aid = icon._msufAuraInstanceID
                if aid and map and map[aid] == icon then
                    map[aid] = nil
                end
                icon._msufAuraInstanceID = nil
                icon._msufAura = nil
                -- Bug 1 fix: Clear stale commit + texture cache so recycled
                -- icons always do a full CommitIcon on next AcquireIcon.
                -- PERF: Reuse the lastCommit table (avoid ~96B alloc on recycle).
                -- Clearing .aid forces full re-apply in CommitIcon's diff gate.
                local lc = icon._msufA2_lastCommit
                if lc then lc.aid = nil end
                icon._msufA2_lastTexAid = nil
                icon._msufA2_timerRev = nil
                icon._msufA2_dynRev = nil
                icon._msufA2_dynGen = nil
                icon._msufA2_dynAnchor = nil
            end
        end
    end

    -- Update active count (the caller just committed fromIndex-1 icons)
    container._msufA2_activeN = fromIndex - 1

    -- Invalidate layout cache when count shrinks (forces re-layout on next grow)
    if container._msufA2_lastLayoutN and fromIndex - 1 < container._msufA2_lastLayoutN then
        container._msufA2_lastLayoutN = nil
    end
end

-- Config generation counter: MUST be declared before LayoutIcons and BumpConfigGen
-- so Lua 5.1 captures it as a proper upvalue (not a global nil reference).
local _configGen = 0
_G.MSUF_A2_ConfigGen = _configGen
local _bindingsDone = false

function Icons.BumpConfigGen()
    _configGen = _configGen + 1
    _G.MSUF_A2_ConfigGen = _configGen
    _bindingsDone = false  -- re-bind on next commit (picks up late-loaded modules)
    _fastPathBound = false -- re-bind fast paths
    _sharedFlagsGen = -1   -- force shared flags refresh
end

-- Layout Engine

function Icons.LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap, configGen)
    if not container or count <= 0 then return end

    --  Layout diff gate
    -- If count and configGen match last call, positions are identical. Skip.
    -- configGen covers iconSize, spacing, perRow, growth, rowWrap (all settings).
    local gen = configGen or _configGen
    if count == container._msufA2_lastLayoutN and gen == container._msufA2_lastLayoutGen then return end
    container._msufA2_lastLayoutN = count
    container._msufA2_lastLayoutGen = gen

    iconSize = iconSize or 26
    spacing = spacing or 2
    perRow = perRow or 12
    if perRow < 1 then perRow = 1 end

    local step = iconSize + spacing
    local vertical = (growth == "UP" or growth == "DOWN")

    -- Direction multipliers + anchor
    local dx, dy = 1, -1  -- defaults: growth RIGHT, wrap DOWN
    local anchorX, anchorY = "LEFT", "BOTTOM"

    if vertical then
        -- Vertical: fill a column first (perRow icons), then wrap rightward.
        -- UP:   anchor BOTTOMLEFT, icons go upward   (dy = +1)
        -- DOWN: anchor TOPLEFT,    icons go downward  (dy = -1)
        if growth == "DOWN" then
            anchorY = "TOP"
            dy = -1
        else -- UP
            anchorY = "BOTTOM"
            dy = 1
        end
        dx = 1
        anchorX = "LEFT"
    else
        -- Horizontal: fill a row first, then wrap vertically.
        if growth == "LEFT" then
            dx = -1
            anchorX = "RIGHT"
        end
        if rowWrap == "UP" then
            dy = 1
        end
    end

    -- Precompute anchor string ONCE (not per icon)
    local anchor = anchorY .. anchorX

    local pool = container._msufIcons
    if not pool then return end

    -- PERF: Cache container-level layout params to skip per-icon checks
    local lastSize = container._msufA2_lastIconSize
    local sizeChanged = (lastSize ~= iconSize)
    if sizeChanged then container._msufA2_lastIconSize = iconSize end

    for i = 1, count do
        local icon = pool[i]
        if icon then
            local idx = i - 1
            local col, row
            if vertical then
                -- Fill column first (row within column), then wrap to next column
                row = idx % perRow
                col = (idx - row) / perRow  -- integer division
            else
                -- Fill row first (col within row), then wrap to next row
                col = idx % perRow
                row = (idx - col) / perRow  -- integer division
            end
            local x = col * step * dx
            local y = row * step * dy

            -- PERF: Skip SetPoint if position unchanged
            if icon._msufA2_lastX ~= x or icon._msufA2_lastY ~= y or icon._msufA2_lastAnchor ~= anchor then
                icon._msufA2_lastX = x
                icon._msufA2_lastY = y
                icon._msufA2_lastAnchor = anchor
                icon:ClearAllPoints()
                icon:SetPoint(anchor, container, anchor, x, y)
            end

            -- PERF: Skip SetSize if unchanged
            if sizeChanged or icon._msufA2_lastSize ~= iconSize then
                icon._msufA2_lastSize = iconSize
                icon:SetSize(iconSize, iconSize)
            end
        end
    end
end

-- Visual Commit (CommitIcon)
-- This is the ONLY function that touches icon visuals.
-- Called once per icon per render. Uses diff gating on
-- auraInstanceID + config generation to skip redundant work.

function Icons.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor, configGen)
    if not icon then return false end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    local gen = configGen or _configGen
    -- PERF: Inline gen-check to skip function call overhead (most calls hit this fast-path)
    if _sharedFlagsGen ~= gen then
        RefreshSharedFlags(shared, gen)
    end

    -- PERF: Inlined ApplyMasqueBackdrop (was separate function call per icon)
    if _masqueEnabled then
        local bg = icon._msufBG
        if bg then
            local hide = (shared and shared.masqueEnabled == true and icon.MSUF_MasqueAdded == true) or false
            if icon._msufA2_bgHidden ~= hide then
                icon._msufA2_bgHidden = hide
                if hide then bg:Hide() else bg:Show() end
            end
        end
    end

    if not aura then
        local container = icon._msufA2_container or icon:GetParent()
        local aidMap = container and container._msufA2_iconByAid
        local prevAid = icon._msufAuraInstanceID
        if prevAid and aidMap and aidMap[prevAid] == icon then
            aidMap[prevAid] = nil
        end
        icon._msufAuraInstanceID = nil
        icon._msufA2_lastOwnHelpful = nil
        icon._msufA2_lastDispelAid = nil
        icon._msufA2_forceOwnBuffHighlight = nil
        icon._msufA2_dynRev = nil
        icon._msufA2_dynGen = nil
        icon._msufA2_dynAnchor = nil
        if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
        if icon._msufPandemic then icon._msufPandemic:Hide() end
        return false
    end

    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    local forceOwnBuffHighlight = (aura._msufA2_forceBossHealHighlight == true)

    --  Fast-path diff gate: same aura, same config Ã¢â€ â€™ skip all bookkeeping
    local last = icon._msufA2_lastCommit
    if last
        and last.aid == aid
        and last.gen == gen
        and last.isOwn == isOwn
        and last.forceOwnBuffHighlight == forceOwnBuffHighlight
    then
        -- Same aura, same config. Only refresh timer + stacks (values may have changed).
        -- Timer/stacks refresh only when the aura cache revision changes. The
        -- revision is our own plain value, so this avoids secret-value compares
        -- while still updating on real UNIT_AURA deltas.
        icon._msufAura = aura
        if _RefreshDynamicIfNeeded then
            _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
        else
            _fast_RefreshTimer(icon, unit, aid, shared, aura)
            _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
        end
        return true
    end

    --  Full apply: update all bookkeeping + visuals
    icon._msufUnit = unit
    icon._msufFilter = isHelpful and "HELPFUL" or "HARMFUL"

    -- Clear preview state if recycled (only when actually preview)
    if icon._msufA2_isPreview then
        icon._msufA2_isPreview = nil
        icon._msufA2_previewKind = nil
        local lbl = icon._msufA2_previewLabel
        if lbl and lbl.Hide then lbl:Hide() end
        -- Hide private aura preview overlays
        if icon._msufPrivateBorder then icon._msufPrivateBorder:Hide() end
        if icon._msufPrivateLock then icon._msufPrivateLock:Hide() end
        if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
        icon._msufA2_lastOwnHelpful = nil
        icon._msufA2_lastDispelAid = nil
        last = nil
        icon._msufA2_lastCommit = nil
    end

    local container = icon._msufA2_container or icon:GetParent()
    local aidMap = container and container._msufA2_iconByAid

    local prevAid = icon._msufAuraInstanceID
    if prevAid and prevAid ~= aid and aidMap and aidMap[prevAid] == icon then
        aidMap[prevAid] = nil
    end
    icon._msufAuraInstanceID = aid
    icon._msufAura = aura  -- PERF: Store aura ref for cached duration/stacks
    if aid and aidMap then aidMap[aid] = icon end

    if not last then
        last = {}
        icon._msufA2_lastCommit = last
    end
    last.aid = aid
    last.gen = gen
    last.isOwn = isOwn
    last.forceOwnBuffHighlight = forceOwnBuffHighlight
    icon._msufA2_forceOwnBuffHighlight = forceOwnBuffHighlight

    -- PERF: Inline gen-check to skip function call overhead
    if icon._msufA2_textCfgGen ~= gen then
        ResolveTextConfig(icon, unit, shared, gen)
    end

    -- 1. Texture (update when aid changed)
    -- SECRET-SAFE: aura.icon CAN be a secret value in WoW 12.0.
    -- Never compare, store, or nil-check it. SetTexture handles secrets internally.
    if icon._msufA2_lastTexAid ~= aid then
        icon._msufA2_lastTexAid = aid
        if icon.tex then
            icon.tex:SetTexture(aura.icon)
        end
    end

    -- 2. Cooldown / Timer
    _fast_ApplyTimer(icon, unit, aid, shared, aura)

    -- 3. Stack count
    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    icon._msufA2_dynRev = aura and aura._msufA2_updateRev or nil
    icon._msufA2_dynGen = gen
    icon._msufA2_dynAnchor = stackCountAnchor or "TOPRIGHT"

    -- 4. Own-aura highlight (same effective state rarely changes across full commits)
    local ownHelpfulKey = ((isOwn and 1) or 0) * 4
        + ((isHelpful and 1) or 0) * 2
        + ((forceOwnBuffHighlight and 1) or 0)
    if icon._msufA2_lastOwnHelpful ~= ownHelpfulKey then
        icon._msufA2_lastOwnHelpful = ownHelpfulKey
        _fast_ApplyOwnHighlight(icon, isOwn, isHelpful, shared)
    end

    -- 5. Dispel-type border (Magic/Curse/Poison/Disease colored)
    if icon._msufA2_lastDispelAid ~= aid then
        icon._msufA2_lastDispelAid = aid
        _fast_ApplyDispelBorder(icon, unit, aura, isHelpful)
    end

    -- 6. Pandemic window pulsing border (secret-safe curve → Show/Hide)
    if _showPandemic then _fast_ApplyPandemic(icon) end

    -- 7. Click-through + tooltip interaction (3-state, diff-gated)
    -- 0 = normal (mouse on, no pass-through)
    -- 1 = click-through but tooltips on (mouse on, all buttons pass-through)
    -- 2 = full click-through (mouse off — no hover, no clicks)
    local wantMS = _clickThrough and (_showTooltip and 1 or 2) or 0
    ApplyMouseState(icon, wantMS)

    icon:Show()
    return true
end

-- Timer application (cooldown swipe + text)
-- Uses duration objects (secret-safe pass-through)

function ClearCooldownVisual(icon, cd)
    if not icon or not cd then return end

    -- Unregister from the cooldown text manager to prevent stale updates.
    CT = CT or (API and API.CooldownText)
    if CT and CT.UnregisterIcon then
        CT.UnregisterIcon(icon)
    end

    -- Clear swipe/timer state (works across template variants).
    if cd.Clear then cd:Clear() end
    if cd.SetCooldown then cd:SetCooldown(0, 0) end
    if cd.SetUseAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = false
        cd:SetUseAuraDisplayTime(false)
    end

    -- Force-hide countdown numbers when no timer is present (prevents stale text).
    if cd.SetHideCountdownNumbers then
        cd._msufA2_lastHideNumbers = true
        cd:SetHideCountdownNumbers(true)
    end

    -- If we already discovered the cooldown fontstring, clear its text.
    local fs = cd._msufCooldownFontString
    if fs and fs ~= false and fs.SetText then
        fs:SetText("")
    end

    icon._msufA2_durationObj = nil
    cd._msufA2_durationObj = nil
    icon._msufA2_lastHadTimer = false
    icon._msufA2_lastCdDurationObj = nil
    icon._msufA2_lastCdAid = nil
    icon._msufA2_lastCdShown = false
    icon._msufA2_timerRev = nil

    -- Pandemic: immediately hide pulsing border when timer clears.
    local pan = icon._msufPandemic
    if pan and pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
end

local function ApplyCooldownTextStyle(icon, cd, now, force)
    if not icon or not cd then return end
    if icon._msufA2_hideCDNumbers == true then return end
    if not force and _showText ~= true then return end

    local size = icon._msufA2_cooldownTextSize or 14
    local offX = icon._msufA2_cooldownTextOffsetX or 0
    local offY = icon._msufA2_cooldownTextOffsetY or 0

    local fs = cd._msufCooldownFontString
    if fs == false then fs = nil end

    -- Only discover the cooldown fontstring when needed (rare) to keep hot paths cheap.
    if not fs then
        if type(now) ~= "number" then
            now = GetTime()
        end
        CT = CT or (API and API.CooldownText)
        local getfs = CT and CT.GetCooldownFontString
        if type(getfs) == "function" then
            fs = getfs(icon, now)
        end
    end

    if not fs then return end
    cd._msufCooldownFontString = fs

    -- Resolve global font family (cached, cheap)
    local gFont, gFlags = ResolveGlobalFont()

    -- Apply font family + size (diff-gated on both size AND font path)
    if fs.GetFont and fs.SetFont then
        local curFont, curSize, curFlags = fs:GetFont()
        local wantFont = gFont or curFont
        local wantFlags = gFlags or curFlags or "OUTLINE"
        if cd._msufA2_cdTextSize ~= size or cd._msufA2_cdFontPath ~= wantFont then
            if wantFont then
                if type(_G.MSUF_SetFontSafe) == "function" then
                    _G.MSUF_SetFontSafe(fs, wantFont, size, wantFlags, ResolveGlobalFontKey())
                else
                    fs:SetFont(wantFont, size, wantFlags)
                end
            end
            cd._msufA2_cdTextSize = size
            cd._msufA2_cdFontPath = wantFont
        end
    end

    -- Apply offsets (only when changed)
    if cd._msufA2_cdTextOffX ~= offX or cd._msufA2_cdTextOffY ~= offY then
        cd._msufA2_cdTextOffX = offX
        cd._msufA2_cdTextOffY = offY
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", cd, "CENTER", offX, offY)
    end
end

-- PERF: aura parameter for pre-cached duration object (ZERO C API calls!)
function Icons._ApplyTimer(icon, unit, aid, shared, aura)
    local cd = icon.cooldown
    if not cd then return end

    local auraRev = aura and aura._msufA2_updateRev
    if auraRev and icon._msufA2_timerRev ~= auraRev then
        if icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            ClearCooldownVisual(icon, cd)
        end
        icon._msufA2_timerRev = auraRev
    end

    local hadTimer = false

    -- PERF: Inline GetDurationObjectFast — direct C API call, skip wrapper
    local obj
    local numericDuration
    if _getDurationDirect then
        obj = _getDurationDirect(unit, aid)
        if obj ~= nil and type(obj) == "number" then
            numericDuration = obj
            obj = nil
        end
    end

    local hadDurationObject = false
    if obj then
        local cdSetFn = cd._msufA2_cdSetFn
        if cdSetFn == nil then
            if type(cd.SetCooldownFromDurationObject) == "function" then
                cdSetFn = cd.SetCooldownFromDurationObject
            elseif type(cd.SetTimerDuration) == "function" then
                cdSetFn = cd.SetTimerDuration
            else
                cdSetFn = false
            end
            cd._msufA2_cdSetFn = cdSetFn
        end

        if cdSetFn then
            cdSetFn(cd, obj)
            hadTimer = true
            hadDurationObject = true
        end

        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
        icon._msufA2_cdNumericFallback = nil
    elseif ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, numericDuration) then
        hadTimer = true
    end

    -- Pass-through: tell Blizzard CooldownFrame to render aura timer natively in C++.
    local wantAuraDisplayTime = (_useBlizzardTimer == true and hadDurationObject == true)
    if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= wantAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = wantAuraDisplayTime
        cd:SetUseAuraDisplayTime(wantAuraDisplayTime)
    end

    -- PERF: Diff-gate cooldown visual flags (avoid redundant C-API calls per icon).
    if cd._msufA2_lastSwipe ~= _showSwipe then
        cd._msufA2_lastSwipe = _showSwipe
        cd:SetDrawSwipe(_showSwipe)
    end
    if cd._msufA2_lastReverse ~= _swipeReverse then
        cd._msufA2_lastReverse = _swipeReverse
        cd:SetReverse(_swipeReverse)
    end
    if hadTimer then
        local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
        if cd._msufA2_lastHideNumbers ~= wantHide or icon._msufA2_lastHadTimer ~= true then
            cd._msufA2_lastHideNumbers = wantHide
            cd:SetHideCountdownNumbers(wantHide)
        end
    else
        ClearCooldownVisual(icon, cd)
    end

    -- Cooldown text manager only recolors the existing Cooldown FontString.
    -- This also works in Blizzard-native timer mode: Blizzard owns the text,
    -- MSUF only applies Safe/Warning/Urgent colors from the Colors menu.
    CT = CT or API.CooldownText
    local wantText = _showText and (icon._msufA2_hideCDNumbers ~= true)
    if CT then
        if wantText and hadTimer then
            local wasRegistered = (icon._msufA2_cdMgrRegistered == true)
            if (not wasRegistered) and CT.RegisterIcon then
                CT.RegisterIcon(icon)
                wasRegistered = (icon._msufA2_cdMgrRegistered == true)
            end

            local objChanged = (icon._msufA2_lastCdDurationObj ~= obj)
            local aidChanged = (icon._msufA2_lastCdAid ~= aid)
            local textStateChanged = (icon._msufA2_lastCdWantText ~= true)
            local shownChanged = (icon._msufA2_lastCdShown ~= true)

            if wasRegistered and CT.TouchIcon and (objChanged or aidChanged or textStateChanged or shownChanged) then
                CT.TouchIcon(icon)
            end

            icon._msufA2_lastCdDurationObj = obj
            icon._msufA2_lastCdAid = aid
            icon._msufA2_lastCdWantText = true
            icon._msufA2_lastCdShown = true
        else
            icon._msufA2_lastCdWantText = false
            icon._msufA2_lastCdShown = false
            icon._msufA2_lastCdDurationObj = nil
            icon._msufA2_lastCdAid = nil
            if CT.UnregisterIcon then
                CT.UnregisterIcon(icon)
            end
        end
    end

    -- Apply cooldown text font size + offsets (styles Blizzard native text too).
    if hadTimer and _showText == true and icon._msufA2_hideCDNumbers ~= true then
        ApplyCooldownTextStyle(icon, cd, nil)
    end

    icon._msufA2_lastHadTimer = hadTimer
end

-- Fast-path timer refresh (same auraInstanceID, possible reapply)
-- PERF: Uses pre-cached duration object from aura (ZERO C API calls!)
function Icons._RefreshTimer(icon, unit, aid, shared, aura)
    local cd = icon.cooldown
    if not cd then return end

    local auraRev = aura and aura._msufA2_updateRev
    if auraRev and icon._msufA2_timerRev ~= auraRev then
        if icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            ClearCooldownVisual(icon, cd)
        end
        icon._msufA2_timerRev = auraRev
    end

    -- PERF: Inline GetDurationObjectFast — direct C API call, skip wrapper
    local obj
    local numericDuration
    if _getDurationDirect then
        obj = _getDurationDirect(unit, aid)
        if obj ~= nil and type(obj) == "number" then
            numericDuration = obj
            obj = nil
        end
    end

    if not obj then
        if ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, numericDuration) then
            local wasTimerActive = (icon._msufA2_lastHadTimer == true)
            icon._msufA2_lastHadTimer = true

            if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= false then
                cd._msufA2_lastUseAuraDisplayTime = false
                cd:SetUseAuraDisplayTime(false)
            end
            if cd._msufA2_lastSwipe ~= _showSwipe then
                cd._msufA2_lastSwipe = _showSwipe
                cd:SetDrawSwipe(_showSwipe)
            end
            if cd._msufA2_lastReverse ~= _swipeReverse then
                cd._msufA2_lastReverse = _swipeReverse
                cd:SetReverse(_swipeReverse)
            end
            local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
            if cd._msufA2_lastHideNumbers ~= wantHide or not wasTimerActive then
                cd._msufA2_lastHideNumbers = wantHide
                cd:SetHideCountdownNumbers(wantHide)
            end

            if _showText and icon._msufA2_hideCDNumbers ~= true then
                CT = CT or API.CooldownText
                if CT and icon._msufA2_cdMgrRegistered ~= true and CT.RegisterIcon then
                    CT.RegisterIcon(icon)
                elseif CT and CT.TouchIcon then
                    CT.TouchIcon(icon)
                end
                icon._msufA2_lastCdDurationObj = nil
                icon._msufA2_lastCdAid = aid
                icon._msufA2_lastCdShown = true
                icon._msufA2_lastCdWantText = true
                ApplyCooldownTextStyle(icon, cd, nil)
            else
                icon._msufA2_lastCdWantText = false
                icon._msufA2_lastCdShown = false
                icon._msufA2_lastCdDurationObj = nil
                icon._msufA2_lastCdAid = nil
                CT = CT or API.CooldownText
                if CT and CT.UnregisterIcon then CT.UnregisterIcon(icon) end
            end

            if _showPandemic then _fast_ApplyPandemic(icon) end
        elseif icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            -- PERF: Only clear if there WAS a timer before (avoid redundant ClearCooldownVisual calls)
            ClearCooldownVisual(icon, cd)
        end
        return
    end

    -- Both swipe and text disabled: nothing visual to update (except pandemic).
    if not _showSwipe and not _showText then
        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
        icon._msufA2_lastHadTimer = true
        if _showPandemic then _fast_ApplyPandemic(icon) end
        return
    end

    -- Refresh duration on the CooldownFrame (needed for both swipe and text).
    local cdSetFn = cd._msufA2_cdSetFn
    if cdSetFn == nil then
        if type(cd.SetCooldownFromDurationObject) == "function" then
            cdSetFn = cd.SetCooldownFromDurationObject
        elseif type(cd.SetTimerDuration) == "function" then
            cdSetFn = cd.SetTimerDuration
        else
            cdSetFn = false
        end
        cd._msufA2_cdSetFn = cdSetFn
    end

    if cdSetFn then
        cdSetFn(cd, obj)
    end

    local wasTimerActive = (icon._msufA2_lastHadTimer == true)
    icon._msufA2_durationObj = obj
    cd._msufA2_durationObj = obj
    icon._msufA2_lastHadTimer = true
    icon._msufA2_cdNumericFallback = nil

    -- A prior no-duration pass calls ClearCooldownVisual(), which hides native
    -- numbers and disables aura display time. Same-aura refreshes must restore
    -- those visual flags without waiting for a full CommitIcon.
    local wantAuraDisplayTime = (_useBlizzardTimer == true)
    if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= wantAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = wantAuraDisplayTime
        cd:SetUseAuraDisplayTime(wantAuraDisplayTime)
    end
    if cd._msufA2_lastSwipe ~= _showSwipe then
        cd._msufA2_lastSwipe = _showSwipe
        cd:SetDrawSwipe(_showSwipe)
    end
    if cd._msufA2_lastReverse ~= _swipeReverse then
        cd._msufA2_lastReverse = _swipeReverse
        cd:SetReverse(_swipeReverse)
    end
    local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
    if cd._msufA2_lastHideNumbers ~= wantHide or not wasTimerActive then
        cd._msufA2_lastHideNumbers = wantHide
        cd:SetHideCountdownNumbers(wantHide)
    end

    -- CT ticker recolors the existing Cooldown FontString in both timer modes.
    if _showText and icon._msufA2_hideCDNumbers ~= true then
        CT = CT or API.CooldownText
        local wasRegistered = (icon._msufA2_cdMgrRegistered == true)
        if CT and (not wasRegistered) and CT.RegisterIcon then
            CT.RegisterIcon(icon)
            wasRegistered = (icon._msufA2_cdMgrRegistered == true)
        end
        local objChanged = (icon._msufA2_lastCdDurationObj ~= obj)
        local aidChanged = (icon._msufA2_lastCdAid ~= aid)
        local shownChanged = (icon._msufA2_lastCdShown ~= true)
        if CT and wasRegistered and CT.TouchIcon and (objChanged or aidChanged or shownChanged) then
            CT.TouchIcon(icon)
        end
        icon._msufA2_lastCdDurationObj = obj
        icon._msufA2_lastCdAid = aid
        icon._msufA2_lastCdShown = true
        icon._msufA2_lastCdWantText = true
        ApplyCooldownTextStyle(icon, cd, nil)
    else
        icon._msufA2_lastCdWantText = false
        icon._msufA2_lastCdShown = false
        icon._msufA2_lastCdDurationObj = nil
        icon._msufA2_lastCdAid = nil
        CT = CT or API.CooldownText
        if CT and CT.UnregisterIcon then CT.UnregisterIcon(icon) end
    end

    -- Pandemic: update when duration object refreshes.
    if _showPandemic then _fast_ApplyPandemic(icon) end
end

-- Stack count display

-- Cached stack count color (invalidated by BumpConfigGen)
local _stackR, _stackG, _stackB, _stackColorGen = 1, 1, 1, -1

-- PERF: aura parameter for pre-cached stack count (ZERO C API calls!)
function Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    local countFS = icon.count
    if not countFS then return end

    -- Phase 8: ResolveTextConfig already called by all callers (CommitIcon / RefreshAssignedIcons).

    -- Apply stack font family + size (gen-guarded: skip GetFont C-API on hot path)
    if icon._msufA2_stackFontGen ~= _configGen then
        icon._msufA2_stackFontGen = _configGen
        local wantSize = icon._msufA2_stackTextSize or 14
        if countFS.GetFont and countFS.SetFont then
            local gFont, gFlags = ResolveGlobalFont()
            local curFont, curSize, curFlags = countFS:GetFont()
            local wantFont = gFont or curFont
            local wantFlags = gFlags or curFlags or "OUTLINE"
            if icon._msufA2_lastStackFontSize ~= wantSize or icon._msufA2_lastStackFontPath ~= wantFont then
                if wantFont then
                    if type(_G.MSUF_SetFontSafe) == "function" then
                        _G.MSUF_SetFontSafe(countFS, wantFont, wantSize, wantFlags, ResolveGlobalFontKey())
                    else
                        countFS:SetFont(wantFont, wantSize, wantFlags)
                    end
                end
                icon._msufA2_lastStackFontSize = wantSize
                icon._msufA2_lastStackFontPath = wantFont
            end
        end
    end

    -- Anchor style (justify) + offsets
    local anchor = stackCountAnchor or "TOPRIGHT"
    if icon._msufA2_lastStackJustifyAnchor ~= anchor then
        icon._msufA2_lastStackJustifyAnchor = anchor

        if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" then
            countFS:SetJustifyH("LEFT")
        else
            countFS:SetJustifyH("RIGHT")
        end
        if anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT" then
            countFS:SetJustifyV("BOTTOM")
        else
            countFS:SetJustifyV("TOP")
        end
    end

    local offX = icon._msufA2_stackTextOffsetX or 0
    local offY = icon._msufA2_stackTextOffsetY or 0
    if icon._msufA2_lastStackPointAnchor ~= anchor
        or icon._msufA2_lastStackPointX ~= offX
        or icon._msufA2_lastStackPointY ~= offY
    then
        icon._msufA2_lastStackPointAnchor = anchor
        icon._msufA2_lastStackPointX = offX
        icon._msufA2_lastStackPointY = offY

        countFS:ClearAllPoints()
        if anchor == "TOPLEFT" then
            countFS:SetPoint("TOPLEFT", icon, "TOPLEFT", offX, offY)
        elseif anchor == "BOTTOMLEFT" then
            countFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", offX, offY)
        elseif anchor == "BOTTOMRIGHT" then
            countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", offX, offY)
        else
            countFS:SetPoint("TOPRIGHT", icon, "TOPRIGHT", offX, offY)
        end
    end

    -- Shared flags cache determines if stack display is enabled.
    if not _showStacks then
        countFS:Hide()
        return
    end

    -- PERF: Inline GetStackCountFast — direct C API call, skip wrapper
    local count = _getStackCountDirect and _getStackCountDirect(unit, aid, 2, 99)

    if count == nil then
        countFS:Hide()
        icon._msufA2_lastCountText = nil
        return
    end

    -- Midnight/Secret-mode: stack display values can be secret.
    -- PASS-THROUGH to FontStrings is allowed; avoid comparisons/arithmetic.
    if issecretvalue and issecretvalue(count) == true then
        countFS:SetText(count)
        icon._msufA2_lastCountText = nil
    else
        local txt
        if type(count) == "number" then
            if count <= 1 then
                countFS:Hide()
                icon._msufA2_lastCountText = nil
                return
            end
            txt = tostring(count)
        elseif type(count) == "string" then
            if count == "" then
                countFS:Hide()
                icon._msufA2_lastCountText = nil
                return
            end
            txt = count
        else
            countFS:Hide()
            icon._msufA2_lastCountText = nil
            return
        end

        if icon._msufA2_lastCountText ~= txt then
            icon._msufA2_lastCountText = txt
            countFS:SetText(txt)
        end
    end

    -- At this point we have a visible stack display (count already set).
    -- Diff-gate SetTextColor to avoid redundant C-API calls on hot path.
    local wantR, wantG, wantB = GetStackCountRGB()
    if icon._msufA2_lastStackR ~= wantR or icon._msufA2_lastStackG ~= wantG or icon._msufA2_lastStackB ~= wantB then
        icon._msufA2_lastStackR = wantR
        icon._msufA2_lastStackG = wantG
        icon._msufA2_lastStackB = wantB
        countFS:SetTextColor(wantR, wantG, wantB)
    end

    countFS:Show()
end

-- Own-aura highlight

-- Cached highlight colors (invalidated by configGen change)
local _hlBuffR, _hlBuffG, _hlBuffB = 1.0, 0.85, 0.2
local _hlDebR, _hlDebG, _hlDebB = 1.0, 0.3, 0.3
local _hlColorGen = -1

function Icons._ApplyOwnHighlight(icon, isOwn, isHelpful, shared)
    local glow = icon._msufOwnGlow
    if not glow then return end

    -- Use cached shared flags (no shared table reads)
    local show = false
    if isOwn then
        if isHelpful then
            show = _wantBuffHL or icon._msufA2_forceOwnBuffHighlight == true
        else
            show = _wantDebuffHL
        end
    end

    if show then
        -- Refresh cached colors when config changes
        local gen = _configGen
        if _hlColorGen ~= gen then
            _hlBuffR, _hlBuffG, _hlBuffB = GetOwnBuffHighlightRGB()
            _hlDebR, _hlDebG, _hlDebB = GetOwnDebuffHighlightRGB()
            _hlColorGen = gen
        end

        if isHelpful then
            glow:SetColorTexture(_hlBuffR, _hlBuffG, _hlBuffB, 0.3)
        else
            glow:SetColorTexture(_hlDebR, _hlDebG, _hlDebB, 0.3)
        end
        glow:Show()
    else
        glow:Hide()
    end
end

--  Dispel-type border (Magic/Curse/Poison/Disease/Bleed colored)
-- Purely cosmetic classification border for debuffs that have an actual
-- dispel school (Magic/Curse/Disease/Poison/Bleed).  Non-dispellable
-- debuffs (dispelName == nil / "" / "None") are left without a border.
-- This is independent of the bar-outline dispel highlight (Bars menu)
-- which tracks whether the *player* can actively dispel on that unit.
-- Color resolution:
--   1. Try C_UnitAuras.GetAuraDispelTypeColor() with step-curve (secret-safe)
--   2. Fallback to manual dispelName  DEBUFF_TYPE_*_COLOR lookup
function Icons._ApplyDispelBorder(icon, unit, aura, isHelpful)
    local bdr = icon._msufDispelBorder
    if not bdr then return end

    -- Only show on harmful auras when the feature is enabled
    if isHelpful or not _useDispelBorders or not aura then
        bdr:Hide()
        return
    end

    -- Gate: only debuffs with a *real* dispel school get a border.
    -- dispelName may be a secret value on private auras in that case
    -- we allow the API path below to resolve the color (it's secret-safe).
    local dName = aura.dispelName
    local isSecret = issecretvalue and dName ~= nil and issecretvalue(dName)
    if not isSecret then
        if not dName or dName == "" or dName == "None" then
            bdr:Hide()
            return
        end
    end

    local r, g, b = 1, 0.25, 0.25  -- default debuff red
    local usedApi = false

    -- Primary: C_UnitAuras.GetAuraDispelTypeColor (secret-safe, works for private auras)
    -- PERF: Direct call (no pcall). C API is guaranteed callable; pcall cost ~10× per icon.
    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    if aid and unit and _debuffColorCurve
       and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
        local color = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, _debuffColorCurve)
        if color then
            usedApi = true
            if color.GetRGBA then
                r, g, b = color:GetRGBA()
            elseif color.r then
                r, g, b = color.r, color.g, color.b
            end
        end
    end

    -- Fallback: manual dispelName lookup (only reached for non-secret values)
    if not usedApi then
        if isSecret then
            -- Secret dispelName but API unavailable can't determine type safely
            bdr:Hide()
            return
        end
        local fr, fg, fb = GetDebuffColorFromName(dName)
        if fr then r, g, b = fr, fg, fb end
    end

    bdr:SetVertexColor(r, g, b, 1)
    bdr:Show()
end

-- Pandemic window pulsing border
-- Secret-safe: uses EvaluateRemainingPercent (curve-based, no value comparisons).
-- Called from CommitIcon, _RefreshTimer, and the 100ms pandemic ticker.

function Icons._ApplyPandemic(icon)
    local pan = icon._msufPandemic
    if not pan then return end

    if not _showPandemic or not _pandemicCurve then
        if pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
        icon._msufPanLastMode = 0
        return
    end

    local obj = icon._msufA2_durationObj
    if not obj then
        if pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
        return
    end

    -- Mode reconfiguration (diff-gated: only when pandemicMode changes)
    local mode = _pandemicMode
    local modeColorKey = mode * 1000003 + _panR * 997 + _panG * 991 + _panB * 983
    if icon._msufPanLastMode ~= modeColorKey then
        icon._msufPanLastMode = modeColorKey
        local border = pan._border
        local glow   = pan._glow
        local anim   = pan._anim
        local inner  = pan._inner
        -- Apply cached color to textures
        if border then border:SetVertexColor(_panR, _panG, _panB, 1) end
        if glow then glow:SetColorTexture(_panR, _panG, _panB, 0.35) end
        if mode == 1 then         -- BORDER: static green border, no glow, no animation
            if border then border:Show() end
            if glow then glow:Hide() end
            if anim and anim:IsPlaying() then anim:Stop() end
            if inner then inner:SetAlpha(1) end
        elseif mode == 2 then     -- PULSE: border + glow + throb animation
            if border then border:Show() end
            if glow then glow:Show() end
            if anim and not anim:IsPlaying() then anim:Play() end
        elseif mode == 3 then     -- GLOW: soft glow only + throb animation
            if border then border:Hide() end
            if glow then glow:Show() end
            if anim and not anim:IsPlaying() then anim:Play() end
        end
    end

    -- Alpha gate: secret-safe sink. 0 × childVisuals = invisible.
    if not pan:IsShown() then pan:Show() end
    local alpha
    if _pandemicEvalBool and obj.IsZero then
        alpha = _pandemicEvalBool(obj:IsZero(), 0, obj:EvaluateRemainingPercent(_pandemicCurve))
    else
        alpha = obj:EvaluateRemainingPercent(_pandemicCurve)
    end
    pan:SetAlpha(alpha)
end

-- Phase 8: bind file-scope locals (defined above) now that methods exist.
_fast_ApplyTimer        = Icons._ApplyTimer
_fast_RefreshTimer      = Icons._RefreshTimer
_fast_ApplyStacks       = Icons._ApplyStacks
_fast_ApplyOwnHighlight = Icons._ApplyOwnHighlight
_fast_ApplyDispelBorder = Icons._ApplyDispelBorder
_fast_ApplyPandemic     = Icons._ApplyPandemic

_RefreshDynamicIfNeeded = function(icon, unit, aid, shared, stackCountAnchor, aura, gen)
    local auraRev = aura and aura._msufA2_updateRev
    local anchor = stackCountAnchor or "TOPRIGHT"
    if auraRev
        and icon._msufA2_dynRev == auraRev
        and icon._msufA2_dynGen == gen
        and icon._msufA2_dynAnchor == anchor
    then
        if _showPandemic then _fast_ApplyPandemic(icon) end
        return
    end

    _fast_RefreshTimer(icon, unit, aid, shared, aura)
    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    icon._msufA2_dynRev = auraRev
    icon._msufA2_dynGen = gen
    icon._msufA2_dynAnchor = anchor
end

-- Refresh all assigned icons (fast path: timer + stacks only)
-- Called when aura membership hasn't changed but values may have

function Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
    if not entry then return end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    -- PERF: Inline gen-check to skip function call overhead
    if _sharedFlagsGen ~= _configGen then
        RefreshSharedFlags(shared, _configGen)
    end

    -- Inline container refresh (no closure allocation)
    -- Use activeN for bounded iteration (avoids walking dead pool entries)
    local pool, activeN, icon, aid
    local gen = _configGen  -- Cache for inner loop

    pool = entry.buffs and entry.buffs._msufIcons
    if pool then
        activeN = entry.buffs._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    -- PERF: Inline gen-check for ResolveTextConfig
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    -- PERF: Use stored aura ref for cached duration/stacks
                    local aura = icon._msufAura
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
                end
            end
        end
    end

    pool = entry.debuffs and entry.debuffs._msufIcons
    if pool then
        activeN = entry.debuffs._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    -- PERF: Inline gen-check
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    local aura = icon._msufAura
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
                end
            end
        end
    end

    pool = entry.mixed and entry.mixed._msufIcons
    if pool then
        activeN = entry.mixed._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    -- PERF: Inline gen-check
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    local aura = icon._msufAura
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
                end
            end
        end
    end
end

-- Preview icons (Edit Mode)

-- Sample textures for varied preview icons (common WoW spell icons)
local _PREVIEW_BUFF_TEXTURES = {
    136116,  -- generic buff (INV_Misc_QuestionMark)
    135932,  -- Arcane Intellect
    135987,  -- Power Word: Fortitude
    136085,  -- Mark of the Wild
    135915,  -- Blessing of Kings
    132333,  -- Renew
    136075,  -- Rejuvenation
    135981,  -- Prayer of Mending
    136076,  -- Regrowth
    135964,  -- Shield
    136048,  -- Heroism / Bloodlust
    132316,  -- Beacon of Light
}
local _PREVIEW_DEBUFF_TEXTURES = {
    136118,  -- generic debuff
    136139,  -- Shadow Word: Pain
    136197,  -- Corruption
    135817,  -- Agony
    132851,  -- Flame Shock
    135813,  -- Moonfire
    136188,  -- Curse of Tongues
    136186,  -- Slow
    135975,  -- Polymorph
    132337,  -- Frost Nova
    136093,  -- Rend
    136170,  -- Deep Wounds
}
local _PREVIEW_BUFF_TEX_N = #_PREVIEW_BUFF_TEXTURES
local _PREVIEW_DEBUFF_TEX_N = #_PREVIEW_DEBUFF_TEXTURES
-- Export for MSUF_A2_EditMode.lua (file-scope locals are invisible across files)
_G.MSUF_A2_PREVIEW_BUFF_TEXTURES  = _PREVIEW_BUFF_TEXTURES
_G.MSUF_A2_PREVIEW_DEBUFF_TEXTURES = _PREVIEW_DEBUFF_TEXTURES
_G.MSUF_A2_PREVIEW_BUFF_TEX_N     = _PREVIEW_BUFF_TEX_N
_G.MSUF_A2_PREVIEW_DEBUFF_TEX_N   = _PREVIEW_DEBUFF_TEX_N

-- Cooldown durations per preview slot (varying so they don't all tick together)
local _PREVIEW_CD_DURATIONS = { 12, 18, 8, 25, 15, 10, 20, 30, 6, 22, 14, 9 }
local _PREVIEW_CD_DUR_N = #_PREVIEW_CD_DURATIONS
_G.MSUF_A2_PREVIEW_CD_DURATIONS = _PREVIEW_CD_DURATIONS
_G.MSUF_A2_PREVIEW_CD_DUR_N     = _PREVIEW_CD_DUR_N

-- Pandemic window ticker (100ms)
-- Re-evaluates pandemic pulsing border for all visible icons so the glow
-- appears as soon as the aura enters the ≤30% remaining window.
-- Secret-safe: delegates to _ApplyPandemic (curve eval → Show/Hide only).

do
    local _panTickWasActive = false
    local function PandemicTick()
        local state = API.state
        local aby = state and state.aurasByUnit
        if not aby then return end

        -- Feature turned off: one cleanup pass then idle.
        if not _showPandemic then
            if _panTickWasActive then
                _panTickWasActive = false
                for _, entry in pairs(aby) do
                    if entry then
                        local pool, n, ic
                        pool = entry.debuffs and entry.debuffs._msufIcons
                        if pool then
                            n = entry.debuffs._msufA2_activeN or #pool
                            for i = 1, n do ic = pool[i]; if ic and ic._msufPandemic then ic._msufPandemic:Hide() end end
                        end
                        pool = entry.buffs and entry.buffs._msufIcons
                        if pool then
                            n = entry.buffs._msufA2_activeN or #pool
                            for i = 1, n do ic = pool[i]; if ic and ic._msufPandemic then ic._msufPandemic:Hide() end end
                        end
                    end
                end
            end
            return
        end

        _panTickWasActive = true
        local _applyPan = Icons._ApplyPandemic
        for _, entry in pairs(aby) do
            if entry then
                local pool, n, ic
                pool = entry.debuffs and entry.debuffs._msufIcons
                if pool then
                    n = entry.debuffs._msufA2_activeN or #pool
                    for i = 1, n do
                        ic = pool[i]
                        if ic and ic:IsShown() and ic._msufAuraInstanceID then _applyPan(ic) end
                    end
                end
                pool = entry.buffs and entry.buffs._msufIcons
                if pool then
                    n = entry.buffs._msufA2_activeN or #pool
                    for i = 1, n do
                        ic = pool[i]
                        if ic and ic:IsShown() and ic._msufAuraInstanceID then _applyPan(ic) end
                    end
                end
            end
        end
    end

    -- Demand-driven loop: only runs when pandemic display is active.
    -- Zero idle overhead when _showPandemic is false (default).
    local _pandemicTicker
    local function PandemicLoopStep()
        local loop = _pandemicTicker
        if not loop then return end
        PandemicTick()
        if _pandemicTicker == loop and C_Timer and C_Timer.After then
            C_Timer.After(0.10, loop.step)
        elseif _pandemicTicker == loop then
            _pandemicTicker = nil
        end
    end
    local function _StartPandemicTicker()
        if _pandemicTicker then return end
        if not (C_Timer and C_Timer.After) then return end
        local loop = {}
        loop.step = function()
            if _pandemicTicker == loop then
                PandemicLoopStep()
            end
        end
        _pandemicTicker = loop
        C_Timer.After(0.10, loop.step)
    end
    local function _StopPandemicTicker()
        if not _pandemicTicker then return end
        _pandemicTicker = nil
        -- One cleanup pass
        PandemicTick()
    end
    -- Export for RefreshSharedFlags
    API._StartPandemicTicker = _StartPandemicTicker
    API._StopPandemicTicker  = _StopPandemicTicker
    if _showPandemic then _StartPandemicTicker() end
end

-- Backward-compatible exports into API.Apply
-- (Options, CooldownText, Preview, Masque all reference API.Apply.*)

Apply.AcquireIcon = Icons.AcquireIcon
Apply.HideUnused = Icons.HideUnused
Apply.LayoutIcons = Icons.LayoutIcons
Apply.CommitIcon = Icons.CommitIcon
Apply.RefreshAssignedIcons = function(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs)
    return Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
end
Apply.RefreshAssignedIconsDelta = function(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs, upd, updN)
    return Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
end
Apply.RenderPreviewIcons = Icons.RenderPreviewIcons
Apply.RenderPreviewPrivateIcons = Icons.RenderPreviewPrivateIcons

-- Stubs for Apply helpers referenced by Render
Apply.ApplyAuraToIcon = function(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor)
    return Icons.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor)
end

-- Font application helpers (referenced by Options/Fonts)
function Apply.ApplyFontsFromGlobal()
    -- Bump configGen so ResolveTextConfig cache is invalidated and new
    -- font values from shared.stackTextSize / cooldownTextSize take effect.
    _configGen = _configGen + 1
    _G.MSUF_A2_ConfigGen = _configGen
    _sharedFlagsGen = -1

    -- Resolve global MSUF font family (path + flags) and flush the file-scope cache
    -- so ApplyCooldownTextStyle / _ApplyStacks pick up the new font immediately.
    _globalFontPath = nil
    _globalFontFlags = "OUTLINE"
    local fontPath, fontFlags
    local getFontSettings = _G.MSUF_GetGlobalFontSettings
    if type(getFontSettings) == "function" then
        fontPath, fontFlags = getFontSettings()
    end
    if type(fontPath) ~= "string" then fontPath = nil end
    if type(fontFlags) ~= "string" then fontFlags = "OUTLINE" end
    -- Update file-scope cache
    _globalFontPath = fontPath
    _globalFontFlags = fontFlags

    -- Iterate all active icons and re-apply text settings + font family
    local state = API.state
    local aby = state and state.aurasByUnit
    if not aby then return end

    local a2, shared = GetAuras2DB()
    if not shared then return end

    -- Helper: apply font family + size to a FontString
    local function ApplyFontFamily(fs, wantSize)
        if not fs or not fs.SetFont or not fs.GetFont then return end
        local curFont, curSize, curFlags = fs:GetFont()
        local newFont = fontPath or curFont
        local newFlags = fontFlags or curFlags or "OUTLINE"
        local newSize = wantSize or curSize or 14
        if newFont then
            if type(_G.MSUF_SetFontSafe) == "function" then
                _G.MSUF_SetFontSafe(fs, newFont, newSize, newFlags, ResolveGlobalFontKey())
            else
                fs:SetFont(newFont, newSize, newFlags)
            end
        end
    end

    -- Helper: refresh font on all icons in a container
    local function RefreshContainerFonts(container, unit, sca)
        if not container or not container._msufIcons then return end
        local pool = container._msufIcons
        local activeN = container._msufA2_activeN or #pool
        for i = 1, activeN do
            local icon = pool[i]
            if icon and icon:IsShown() then
                -- Resolve text config (sizes, offsets) for this configGen
                ResolveTextConfig(icon, unit, shared, _configGen)

                -- Apply font family to stack count text
                if icon.count then
                    ApplyFontFamily(icon.count, icon._msufA2_stackTextSize)
                end

                -- Apply font family to cooldown text
                local cd = icon.cooldown
                if cd then
                    -- Use the cached fontstring from CooldownText module
                    local cdFS = cd._msufCooldownFontString
                    if cdFS == false then cdFS = nil end
                    -- Fallback: try to discover via EnumerateRegions
                    if not cdFS and cd.EnumerateRegions then
                        for region in cd:EnumerateRegions() do
                            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                                cdFS = region
                                cd._msufCooldownFontString = region
                                break
                            end
                        end
                    end
                    if cdFS and cdFS.SetFont then
                        ApplyFontFamily(cdFS, icon._msufA2_cooldownTextSize)
                    end
                end
            end
        end
    end

    for _, entry in pairs(aby) do
        if entry then
            local unit = entry.unit
            local stackCountAnchor = shared.stackCountAnchor

            -- Respect per-unit stack anchor overrides
            local pu = a2 and a2.perUnit and unit and a2.perUnit[unit]
            if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
                local v = pu.layoutShared.stackCountAnchor
                if type(v) == "string" then
                    stackCountAnchor = v
                end
            end

            -- Standard refresh (timer + stacks positioning)
            Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)

            -- Font family refresh (the part that was missing)
            if fontPath then
                RefreshContainerFonts(entry.buffs, unit, stackCountAnchor)
                RefreshContainerFonts(entry.debuffs, unit, stackCountAnchor)
                RefreshContainerFonts(entry.mixed, unit, stackCountAnchor)
                RefreshContainerFonts(entry.private, unit, stackCountAnchor)
            end

            -- Also refresh preview icons (they lack _msufAuraInstanceID so
            -- RefreshAssignedIcons skips them)
            if entry._msufA2_previewActive then
                local gen = _configGen
                local function RefreshPreviewFonts(ctr)
                    if not ctr or not ctr._msufIcons then return end
                    for _, icon in ipairs(ctr._msufIcons) do
                        if icon and icon:IsShown() and icon._msufA2_isPreview then
                            ResolveTextConfig(icon, unit, shared, gen)
                            -- Stack count font
                            if icon.count and fontPath then
                                ApplyFontFamily(icon.count, icon._msufA2_stackTextSize)
                            end
                            -- Cooldown text font
                            if fontPath then
                                local cd = icon.cooldown
                                if cd then
                                    local cdFS = cd._msufCooldownFontString
                                    if cdFS == false then cdFS = nil end
                                    if not cdFS and cd.EnumerateRegions then
                                        for region in cd:EnumerateRegions() do
                                            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                                                cdFS = region
                                                cd._msufCooldownFontString = region
                                                break
                                            end
                                        end
                                    end
                                    if cdFS and cdFS.SetFont then
                                        ApplyFontFamily(cdFS, icon._msufA2_cooldownTextSize)
                                    end
                                end
                            end
                        end
                    end
                end
                RefreshPreviewFonts(entry.buffs)
                RefreshPreviewFonts(entry.debuffs)
                RefreshPreviewFonts(entry.private)
            end
        end
    end
end

-- Text offset stubs (Edit Mode references)

function Apply.ApplyStackCountAnchorStyle(icon, stackCountAnchor)
    local countFS = icon and icon.count
    if not countFS then return end

    local anchor = stackCountAnchor or "TOPRIGHT"
    -- Always apply (Preview-only; force-invalidate)
    icon._msufA2_lastStackJustifyAnchor = anchor

    if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" then
        countFS:SetJustifyH("LEFT")
    else
        countFS:SetJustifyH("RIGHT")
    end
    if anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT" then
        countFS:SetJustifyV("BOTTOM")
    else
        countFS:SetJustifyV("TOP")
    end
end

function Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)
    local countFS = icon and icon.count
    if not countFS then return end

    -- Force-invalidate text config cache so ResolveTextConfig re-reads DB.
    -- This function is Preview-only (ticker + RenderPreviewIcons), so the
    -- unconditional invalidation has zero cost on live aura hot paths.
    icon._msufA2_textCfgGen = nil
    ResolveTextConfig(icon, unit, shared, _configGen)

    -- Font family + size (always re-apply: Preview-only)
    local wantSize = icon._msufA2_stackTextSize or 14
    if countFS.GetFont and countFS.SetFont then
        local gFont, gFlags = ResolveGlobalFont()
        local curFont, _, curFlags = countFS:GetFont()
        local wantFont = gFont or curFont
        local wantFlags = gFlags or curFlags or "OUTLINE"
        if wantFont then
            if type(_G.MSUF_SetFontSafe) == "function" then
                _G.MSUF_SetFontSafe(countFS, wantFont, wantSize, wantFlags, ResolveGlobalFontKey())
            else
                countFS:SetFont(wantFont, wantSize, wantFlags)
            end
        end
    end
    icon._msufA2_lastStackFontSize = wantSize

    -- Anchor style + offsets (always re-apply: clear diff cache)
    local anchor = stackCountAnchor or "TOPRIGHT"
    icon._msufA2_lastStackJustifyAnchor = nil
    Apply.ApplyStackCountAnchorStyle(icon, anchor)

    local offX = icon._msufA2_stackTextOffsetX or 0
    local offY = icon._msufA2_stackTextOffsetY or 0
    icon._msufA2_lastStackPointAnchor = nil
    icon._msufA2_lastStackPointX = nil
    icon._msufA2_lastStackPointY = nil

    countFS:ClearAllPoints()
    if anchor == "TOPLEFT" then
        countFS:SetPoint("TOPLEFT", icon, "TOPLEFT", offX, offY)
    elseif anchor == "BOTTOMLEFT" then
        countFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", offX, offY)
    elseif anchor == "BOTTOMRIGHT" then
        countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", offX, offY)
    else
        countFS:SetPoint("TOPRIGHT", icon, "TOPRIGHT", offX, offY)
    end

    local r, g, b = GetStackCountRGB()
    countFS:SetTextColor(r, g, b, 1)
end

function Apply.ApplyCooldownTextOffsets(icon, unit, shared)
    local cd = icon and icon.cooldown
    if not cd then return end

    -- Force-invalidate text config cache (Preview-only function).
    icon._msufA2_textCfgGen = nil
    ResolveTextConfig(icon, unit, shared, _configGen)

    -- Force-invalidate cooldown diff caches so new values always apply
    cd._msufA2_cdTextSize = nil
    cd._msufA2_cdFontPath = nil
    cd._msufA2_cdTextOffX = nil
    cd._msufA2_cdTextOffY = nil

    -- Ensure fontstring is discovered (safe: uses cached retry logic in cooldown module)
    CT = CT or API.CooldownText
    local getfs = CT and CT.GetCooldownFontString
    if type(getfs) ~= "function" then return end

    local now = GetTime()
    ApplyCooldownTextStyle(icon, cd, now, true)
end

API.ApplyFontsFromGlobal = Apply.ApplyFontsFromGlobal

-- Global wrapper (referenced by MidnightSimpleUnitFrames.lua)
if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) ~= "function" then
    _G.MSUF_Auras2_ApplyFontsFromGlobal = function() return Apply.ApplyFontsFromGlobal() end
end
