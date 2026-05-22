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
    dst.isStealable            = src.isStealable
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
    dst.dispelName             = src.dispelName
    dst.isHelpful              = src.isHelpful
    dst.isHarmful              = src.isHarmful
    dst.isRaid                 = src.isRaid
    dst.isBossAura             = src.isBossAura
    dst.isStealable            = src.isStealable
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
    if s then
        if not s.helpful then s.helpful = {} end
        if not s.harmful then s.harmful = {} end
        return s
    end
    s = {
        all     = {},
        helpful = {},
        harmful = {},
        epoch   = 0,
        changed = true,
    }
    _units[unit] = s
    return s
end

Cache._units = _units

local function StoreAuraInUnit(s, aid, data, isHelpful)
    if not (s and aid and data) then return end
    local helpful = s.helpful
    if not helpful then helpful = {}; s.helpful = helpful end
    local harmful = s.harmful
    if not harmful then harmful = {}; s.harmful = harmful end

    s.all[aid] = data
    if isHelpful == true then
        helpful[aid] = data
        harmful[aid] = nil
    else
        harmful[aid] = data
        helpful[aid] = nil
    end
end

local function RemoveAuraFromUnit(s, aid)
    if not (s and aid) then return nil end
    local entry = s.all and s.all[aid] or nil
    if entry then
        s.all[aid] = nil
        if s.helpful then s.helpful[aid] = nil end
        if s.harmful then s.harmful[aid] = nil end
    end
    return entry
end

local function MarkFullScanPending(unit)
    if not unit then return end

    local s = EnsureUnit(unit)
    s.changed = true
    s.epoch = (s.epoch or 0) + 1
    s.structureChanged = true
    s.structureEpoch = (s.structureEpoch or 0) + 1
    s.updatedIDs = nil
    s._fullScanPending = true
    s._lastFilterGen = nil
    s._lastFilterStructureEpoch = nil
    s._lastNB = nil
    s._lastND = nil

    local _st = API.Store
    if _st and _st._epochs then _st._epochs[unit] = s.epoch end
end

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

local function BuffIsStealable(aura)
    return ReadAccessibleBool(aura and aura.isStealable) == true
end

local function ReadAccessibleDispelName(aura)
    local v = aura and aura.dispelName
    if v == nil then return nil, true end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then return nil, false end
    elseif issecretvalue and issecretvalue(v) == true then
        return nil, false
    end
    if type(v) ~= "string" or v == "" or v == "None" then return nil, true end
    return v, true
end

local function CacheDispelInfo(aura)
    if not aura then return 0 end
    local dispelName, known = ReadAccessibleDispelName(aura)
    if known == false then
        -- Private/secret aura data cannot match a selected dispel type here.
        -- Cache the non-match so FilterAura does not retry every render; the
        -- include-dispellable path still uses Blizzard's filtered fallback.
        aura._msufA2_dispelCode = 0
        aura._msufA2_hasDispelName = 0
        return 0
    end
    local code = 0
    if dispelName == "Magic" then
        code = 1
    elseif dispelName == "Curse" then
        code = 2
    elseif dispelName == "Poison" then
        code = 3
    elseif dispelName == "Disease" then
        code = 4
    end
    aura._msufA2_dispelCode = code
    aura._msufA2_hasDispelName = (dispelName ~= nil) and 1 or 0
    return code
end

local function DebuffMatchesSelectedDispelType(aura, cfg)
    local code = aura and aura._msufA2_dispelCode
    if code == nil then code = CacheDispelInfo(aura) end
    if code == 1 then return cfg._debuffDispelMagic == true end
    if code == 2 then return cfg._debuffDispelCurse == true end
    if code == 3 then return cfg._debuffDispelPoison == true end
    if code == 4 then return cfg._debuffDispelDisease == true end
    return false
end

local function DebuffIsDispellable(unit, aid, aura, lIsFiltered)
    local hasDispelName = aura and aura._msufA2_hasDispelName
    if hasDispelName == nil then
        CacheDispelInfo(aura)
        hasDispelName = (aura and aura._msufA2_hasDispelName) or 0
    end
    if hasDispelName == 1 then return true end
    if lIsFiltered then
        return ReadAccessibleBool(lIsFiltered(unit, aid, HARMFUL_DISPELLABLE)) == false
    end
    return false
end

local function DebuffMatchesDispelException(unit, aid, aura, cfg, lIsFiltered)
    if cfg and cfg._debuffTypeFilter then
        return DebuffMatchesSelectedDispelType(aura, cfg)
    end
    return DebuffIsDispellable(unit, aid, aura, lIsFiltered)
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
    if isHelpful == false then
        CacheDispelInfo(data)
    else
        data._msufA2_dispelCode = 0
        data._msufA2_hasDispelName = 0
    end
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
    local s = EnsureUnit(unit)
    -- P7: release all cached aura tables back to pool before wiping.
    for _, entry in next, s.all do _AuraRelease(entry) end
    wipe(s.all)
    wipe(s.helpful)
    wipe(s.harmful)
    s.changed = true
    s.epoch = s.epoch + 1
    s.structureChanged = true
    s.structureEpoch = (s.structureEpoch or 0) + 1
    s.updatedIDs = nil
    s._fullScanPending = nil
    local _st = API.Store; if _st and _st._epochs then _st._epochs[unit] = s.epoch end
    local slotsN = _PackSlots(_getSlots(unit, HELPFUL, 40))
    for i = 2, slotsN do
        local data = _getBySlot(unit, _slotBuf[i])
        if data and data.auraInstanceID then
            local aid = data.auraInstanceID
            local isHelpful = ClassifyHelpful(unit, aid, data, true)
            EnrichAura(unit, data, isHelpful)
            StoreAuraInUnit(s, aid, data, isHelpful)
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
                StoreAuraInUnit(s, aid, data, isHelpful)
            end
        end
    end
end

-- Delta Update (HOT PATH)
function Cache.OnUnitAura(unit, updateInfo)
    if not unit then return end
    if not _apisBound then BindAPIs() end

    if not updateInfo or updateInfo.isFullUpdate then
        -- FullUpdate has no granular aura list. Mark the unit stale and let
        -- FilterAndSort perform the expensive FullScan only if that unit/lane
        -- is actually rendered. Player reminders see the epoch bump and fall
        -- back to their direct provider scan while the cache is pending.
        MarkFullScanPending(unit)
        return
    end

    -- PERF: Inlined EnsureUnit (after warmup, always hits cache)
    local s = EnsureUnit(unit)
    if s._fullScanPending then
        MarkFullScanPending(unit)
        return
    end

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
                StoreAuraInUnit(s, aid, entry, isHelpful)
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
                    local oldStealable = BuffIsStealable(entry)
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
                    StoreAuraInUnit(s, aid, entry, newHelpful)
                    if newHelpful == false then
                        if oldHelpful ~= false
                           or entry._msufA2_dispelCode == nil
                           or entry._msufA2_hasDispelName == nil
                        then
                            CacheDispelInfo(entry)
                        end
                    else
                        entry._msufA2_dispelCode = 0
                        entry._msufA2_hasDispelName = 0
                    end
                    -- Blizzard can report filter/classification changes as an
                    -- update-only delta. If membership changed, force a normal
                    -- filter pass instead of reusing the previous visible list.
                    if oldHelpful ~= newHelpful or oldOwn ~= newOwn
                        or oldBossFlag ~= ReadBossFlag(entry)
                        or oldStealable ~= BuffIsStealable(entry) then
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
                    RemoveAuraFromUnit(s, aid)
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
            local entry = RemoveAuraFromUnit(s, aid)
            if entry then
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
            s.structureEpoch = (s.structureEpoch or 0) + 1
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
        s.structureEpoch = (s.structureEpoch or 0) + 1
        s.updatedIDs = nil
        s._lastFilterGen = nil
        s._lastFilterStructureEpoch = nil
        s._lastNB = nil
        s._lastND = nil
    end
end

function Cache.InvalidateAll()
    for _, s in next, _units do
        s.changed = true
        s.epoch = s.epoch + 1
        s.structureChanged = true
        s.structureEpoch = (s.structureEpoch or 0) + 1
        s.updatedIDs = nil
        -- Clear fast-path filter cache: options changes (Important, OnlyMine,
        -- Caps, IgnoreList, etc.) must force a full re-filter on next
        -- FilterAndSort, even when no aura add/remove occurred.
        s._lastFilterGen = nil
        s._lastFilterStructureEpoch = nil
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
        if cfg._buffsOnlyMine and not cfg._useMergeBuffs and not isOwn then
            if not (cfg._includeStealableBuffs and BuffIsStealable(data)) then return false end
        end

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
            if ReadAccessibleBool(lIsFiltered(unit, aid, HELPFUL_IMPORTANT)) == true then
                if not (cfg._includeStealableBuffs and BuffIsStealable(data)) then return false end
            end
        end
    else
        if cfg._debuffsOnlyMine and not cfg._useMergeDebuffs and not isOwn then
            if not (cfg._includeDispellableDebuffs and DebuffMatchesDispelException(unit, aid, data, cfg, lIsFiltered)) then
                return false
            end
        end
        if cfg._onlyBoss and ReadBossFlag(data) == 0 then return false end

        if cfg._onlyImpDebuffs and lIsFiltered then
            if ReadAccessibleBool(lIsFiltered(unit, aid, HARMFUL_IMPORTANT)) == true then
                if not (cfg._includeDispellableDebuffs and DebuffMatchesDispelException(unit, aid, data, cfg, lIsFiltered)) then
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
            elseif (cfg.buffsIncludeBoss == true and ReadBossFlag(data) == 1)
                or (cfg._includeStealableBuffs == true and BuffIsStealable(data)) then
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
    local maxBuffs = (type(cfg._maxBuffs) == "number" and cfg._maxBuffs) or tonumber(cfg.maxBuffs) or 12
    local maxDebuffs = (type(cfg._maxDebuffs) == "number" and cfg._maxDebuffs) or tonumber(cfg.maxDebuffs) or 12
    if maxBuffs < 0 then maxBuffs = 0 end
    if maxDebuffs < 0 then maxDebuffs = 0 end

    cfg._maxBuffs  = maxBuffs
    cfg._maxDebuffs = maxDebuffs
    cfg._wantBuffs = (cfg._wantBuffs == true) and maxBuffs > 0
    cfg._wantDebuffs = (cfg._wantDebuffs == true) and maxDebuffs > 0

    if cfg._msufA2FilterPrepGen == cfgGen and cfg._msufA2FilterPrepIgnoreCats == cfg.ignoreCats then
        return
    end
    cfg._msufA2FilterPrepGen = cfgGen
    cfg._msufA2FilterPrepIgnoreCats = cfg.ignoreCats

    cfg._buffsOnlyMine    = cfg.buffsOnlyMine
    cfg._debuffsOnlyMine  = cfg.debuffsOnlyMine
    cfg._hidePermanent    = cfg.hidePermanentBuffs
    cfg._onlyBoss         = cfg.onlyBossAuras
    cfg._onlyImpBuffs     = cfg.onlyImportantBuffs
    cfg._onlyImpDebuffs   = cfg.onlyImportantDebuffs
    cfg._includeStealableBuffs = (cfg.buffsIncludeStealable == true)
        and (cfg._buffsOnlyMine or cfg._onlyImpBuffs)
    cfg._useMergeBuffs    = cfg.buffsOnlyMine and (cfg.buffsIncludeBoss or cfg._includeStealableBuffs)
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
        and not cfg._includeStealableBuffs
        and not cfg._includeDispellableDebuffs
        and not cfg._hideOtherBossHealAuras
    cfg._sortOrder = cfg.sortOrder or cfg.capsSortOrder or 0
end

local function ClearFilterOutput(out)
    local prevN = out._msufA2_n or 0
    if prevN > 0 then
        for i = 1, prevN do out[i] = nil end
    end
    out._msufA2_n = 0
end

function Cache.FilterAndSort(unit, cfg, buffOut, debuffOut)
    if not _apisBound then BindAPIs() end
    BindDoesExpire()

    local cfgGen = cfg._gen or -1

    -- Pre-compute config flags before all fast paths so cap/filter lane
    -- changes cannot return stale counts.
    PrepareFilterConfig(cfg, cfgGen)
    local maxBuffs  = cfg._maxBuffs
    local maxDebuffs = cfg._maxDebuffs
    local wantBuffs = cfg._wantBuffs
    local wantDebuffs = cfg._wantDebuffs

    local s = _units[unit]
    local structureEpoch = s and (s.structureEpoch or 0) or 0

    if not wantBuffs and not wantDebuffs then
        ClearFilterOutput(buffOut)
        ClearFilterOutput(debuffOut)
        if s then
            s.changed = false
            s.structureChanged = false
            s._lastNB = 0
            s._lastND = 0
            s._lastFilterGen = cfgGen
            s._lastFilterStructureEpoch = structureEpoch
            s._lastFilterWantBuffs = wantBuffs
            s._lastFilterWantDebuffs = wantDebuffs
        end
        return buffOut, 0, debuffOut, 0
    end

    if not s then
        Cache.FullScan(unit)
        s = _units[unit]
        if not s then return buffOut, 0, debuffOut, 0 end
        structureEpoch = s.structureEpoch or 0
    elseif s._fullScanPending then
        Cache.FullScan(unit)
        s = _units[unit]
        if not s then return buffOut, 0, debuffOut, 0 end
        structureEpoch = s.structureEpoch or 0
    end

    -- PERF: Update-only fast path — when only duration/stacks changed (no add/remove),
    -- the filtered list is structurally identical. Skip full iteration + filter.
    -- Saves ~52µs per update-only event (the most common case in sustained combat).
    local satedThresholdActive = (cfg.showSated ~= false)
        and (type(cfg.satedShowAtSeconds) == "number" and cfg.satedShowAtSeconds > 0)
    if not satedThresholdActive
       and s._lastFilterGen == cfgGen and s._lastFilterStructureEpoch == structureEpoch
       and s._lastFilterWantBuffs == wantBuffs and s._lastFilterWantDebuffs == wantDebuffs
       and s._lastNB ~= nil and s._lastND ~= nil then
        s.changed = false
        return buffOut, s._lastNB, debuffOut, s._lastND
    end
    s.structureChanged = false

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
    local bossBufScratch = (wantBuffs and cfg._useMergeBuffs) and _mergedBossBuffScratch or nil
    local bossDebScratch = (wantDebuffs and cfg._useMergeDebuffs) and _mergedBossDebuffScratch or nil

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
    local useMergeBuffs = wantBuffs and cfg._useMergeBuffs
    local useMergeDebuffs = wantDebuffs and cfg._useMergeDebuffs

    if sortOrder == 0 then
        -- FAST PATH: unsorted — pure cache iteration, ZERO C API calls
        local helpful = s.helpful
        if not helpful then helpful = {}; s.helpful = helpful end
        local harmful = s.harmful
        if not harmful then harmful = {}; s.harmful = harmful end

        if wantBuffs then
            for aid, data in next, helpful do
                if (nB + nBossB) >= maxBuffs then break end

                local isOwn = data._msufIsPlayerAura
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
            end
        end

        if wantDebuffs then
            for aid, data in next, harmful do
                if (nD + nBossD) >= maxDebuffs then break end

                local isOwn = data._msufIsPlayerAura
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
        if wantBuffs and (nB + nBossB) < maxBuffs then
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
                            data._msufA2_dispelCode = cached._msufA2_dispelCode
                            data._msufA2_hasDispelName = cached._msufA2_hasDispelName
                            if actualHelpful == false and data._msufA2_dispelCode == nil then
                                CacheDispelInfo(data)
                            end
                            StoreAuraInUnit(s, aid, cached, actualHelpful)
                        else
                            EnrichAura(unit, data, actualHelpful)
                            StoreAuraInUnit(s, aid, data, actualHelpful)
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
        if wantDebuffs and (nD + nBossD) < maxDebuffs then
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
                            data._msufA2_dispelCode = cached._msufA2_dispelCode
                            data._msufA2_hasDispelName = cached._msufA2_hasDispelName
                            if actualHelpful == false and data._msufA2_dispelCode == nil then
                                CacheDispelInfo(data)
                            end
                            StoreAuraInUnit(s, aid, cached, actualHelpful)
                        else
                            EnrichAura(unit, data, actualHelpful)
                            StoreAuraInUnit(s, aid, data, actualHelpful)
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
    if wantBuffs and cfg._useMergeBuffs and nBossB > 0 then
        for i = 1, nBossB do
            if nB >= maxBuffs then break end
            nB = nB + 1
            buffOut[nB] = bossBufScratch[i]
        end
        for i = nBossB, 1, -1 do bossBufScratch[i] = nil end
    end
    if wantDebuffs and cfg._useMergeDebuffs and nBossD > 0 then
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
    s._lastFilterStructureEpoch = structureEpoch
    s._lastFilterWantBuffs = wantBuffs
    s._lastFilterWantDebuffs = wantDebuffs

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
    -- Current FullUpdate handling is lazy; this wipe is for hard unit identity invalidation.
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
