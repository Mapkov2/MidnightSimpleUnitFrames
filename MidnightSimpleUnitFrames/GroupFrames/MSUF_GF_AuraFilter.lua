-- MSUF_GF_AuraFilter.lua — Group Frames: 2-Tier Aura Filter Engine
-- Tier 1: Blizzard API filter tokens (C-side, zero Lua cost)
-- Tier 2: Declassified spell blacklist (categorized, user-toggleable)
--
-- Midnight 12.0 secret-safe. spellId decoded once per aura via _DecodeSpellId.
-- Declassified spells (Blizzard whitelisted) have readable spellIds even on
-- other players — these are the ONLY spells that can be blacklisted/whitelisted.
-- Non-declassified spellIds are secret → pass through Tier 2 unfiltered.
--
-- Pattern: identical to A2_Core._IGNORE_CAT_SPELLS, adapted for GF context.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local type   = type
local pairs  = pairs
local tonumber = tonumber
local wipe   = wipe or function(t) for k in pairs(t) do t[k] = nil end end
local C_Spell = _G.C_Spell
local GetSpellInfo = _G.GetSpellInfo
local UnitClass = _G.UnitClass

-- Forward: secret-safe check helper
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

------------------------------------------------------------------------
-- Blizzard API Filter Tokens (Tier 1)
-- Passed directly to C_UnitAuras.GetAuraSlots — zero Lua filtering cost.
-- Users select ONE base filter per aura group via dropdown.
------------------------------------------------------------------------
local BUFF_TOKENS = {
    ALL              = "HELPFUL",
    PLAYER           = "HELPFUL|PLAYER",
    RAID             = "HELPFUL|RAID",
    RAID_PLAYER      = "HELPFUL|RAID|PLAYER",
    CANCELABLE       = "HELPFUL|CANCELABLE",
    NOT_CANCELABLE   = "HELPFUL|NOT_CANCELABLE",
    IMPORTANT        = "HELPFUL|IMPORTANT",
}

local DEBUFF_TOKENS = {
    ALL              = "HARMFUL",
    PLAYER           = "HARMFUL|PLAYER",
    RAID             = "HARMFUL|RAID",
    DISPELLABLE      = "HARMFUL|RAID_PLAYER_DISPELLABLE",
    CROWD_CONTROL    = "HARMFUL|CROWD_CONTROL",
    IMPORTANT        = "HARMFUL|IMPORTANT",
}

-- Externals always use BIG_DEFENSIVE (unchanged)
local EXTERNALS_TOKEN = "HELPFUL|BIG_DEFENSIVE"
local DISPEL_CLASSES = {
    PRIEST = true, PALADIN = true, SHAMAN = true, MONK = true,
    DRUID = true, MAGE = true, EVOKER = true,
}

local function PlayerCanUseRaidPlayerDispellable()
    if GF._playerCanDispel ~= nil then return GF._playerCanDispel == true end
    local _, class
    if UnitClass then _, class = UnitClass("player") end
    return class and DISPEL_CLASSES[class] == true
end

-- Resolve buff filter string from DB key
local function ResolveBuffFilter(filterToken)
    return BUFF_TOKENS[filterToken] or BUFF_TOKENS.RAID
end

-- Resolve debuff filter string from DB key
local function ResolveDebuffFilter(filterToken)
    -- RAID_PLAYER_DISPELLABLE is empty on classes with no defensive dispel.
    -- Fall back to plain HARMFUL so DPS-only classes can still use the
    -- debuff group instead of seeing an empty icon set.
    if (filterToken == "DISPELLABLE" or filterToken == DEBUFF_TOKENS.DISPELLABLE)
       and not PlayerCanUseRaidPlayerDispellable()
    then
        return DEBUFF_TOKENS.ALL
    end
    return DEBUFF_TOKENS[filterToken] or DEBUFF_TOKENS.ALL
end

------------------------------------------------------------------------
-- Dropdown metadata (for Options UI)
------------------------------------------------------------------------
local BUFF_FILTER_ITEMS = {
    { key = "ALL",            label = "All Buffs"         },
    { key = "PLAYER",         label = "My Buffs Only"     },
    { key = "RAID",           label = "Raid Buffs"        },
    { key = "RAID_PLAYER",    label = "Raid + My Buffs"   },
    { key = "CANCELABLE",     label = "Cancelable"        },
    { key = "NOT_CANCELABLE", label = "Not Cancelable"    },
    { key = "IMPORTANT",      label = "Important"         },
}

local DEBUFF_FILTER_ITEMS = {
    { key = "ALL",            label = "All Debuffs"       },
    { key = "PLAYER",         label = "My Debuffs Only"   },
    { key = "RAID",           label = "Boss / Raid"       },
    { key = "DISPELLABLE",    label = "Dispellable"       },
    { key = "CROWD_CONTROL",  label = "Crowd Control"     },
    { key = "IMPORTANT",      label = "Important"         },
}

------------------------------------------------------------------------
-- Declassified Spell Database (Tier 2)
-- These spellIds are NOT secret in 12.0 — Blizzard whitelisted them.
-- Users toggle categories to HIDE (blacklist) unwanted spells.
-- Source: Blizzard 12.0.1 Spell Declassification Announcement (Mar 2026)
------------------------------------------------------------------------
local DECLASSIFIED_SPELLS = {
    -- ── Sated / Exhaustion ──────────────────────────────────────────
    SATED = {
        [57723]  = true,   -- Exhaustion (Heroism/Bloodlust)
        [57724]  = true,   -- Sated
        [80354]  = true,   -- Temporal Displacement (Time Warp)
        [95809]  = true,   -- Hunter Pet Insanity
        [160455] = true,   -- Hunter Pet Fatigued
        [264689] = true,   -- Hunter Pet Fatigued (alt)
        [390435] = true,   -- Exhaustion (Drums)
    },
    -- ── Deserter ────────────────────────────────────────────────────
    DESERTER = {
        [26013]  = true,   -- BG Deserter
        [71041]  = true,   -- Dungeon Deserter
    },
    -- ── Long-term Raid Buffs ────────────────────────────────────────
    RAID_BUFFS = {
        [1126]   = true,   -- Mark of the Wild
        [1459]   = true,   -- Arcane Intellect
        [6673]   = true,   -- Battle Shout
        [21562]  = true,   -- Power Word: Fortitude
        [369459] = true,   -- Source of Magic
        [462854] = true,   -- Skyfury
        [474754] = true,   -- Symbiotic Relationship
    },
    -- ── Blessing of the Bronze ──────────────────────────────────────
    BLESSING_BRONZE = {
        [381732] = true, [381741] = true, [381746] = true, [381748] = true,
        [381749] = true, [381750] = true, [381751] = true, [381752] = true,
        [381753] = true, [381754] = true, [381756] = true, [381757] = true,
        [381758] = true,
    },
    -- ── Healer HoTs & Shields ───────────────────────────────────────
    HEALER_HOTS = {
        -- Preservation Evoker
        [355941] = true,   -- Dream Breath
        [363502] = true,   -- Dream Flight
        [364343] = true,   -- Echo
        [366155] = true,   -- Reversion
        [367364] = true,   -- Echo Reversion
        [373267] = true,   -- Lifebind
        [376788] = true,   -- Echo Dream Breath
        -- Augmentation Evoker
        [360827] = true,   -- Blistering Scales
        [395152] = true,   -- Ebon Might
        [410089] = true,   -- Prescience
        [410263] = true,   -- Inferno's Blessing
        [410686] = true,   -- Symbiotic Bloom
        [413984] = true,   -- Shifting Sands
        -- Resto Druid
        [774]    = true,   -- Rejuvenation
        [8936]   = true,   -- Regrowth
        [33763]  = true,   -- Lifebloom
        [48438]  = true,   -- Wild Growth
        [155777] = true,   -- Germination
        -- Disc Priest
        [17]     = true,   -- Power Word: Shield
        [194384] = true,   -- Atonement
        [1253593]= true,   -- Void Shield
        -- Holy Priest
        [139]    = true,   -- Renew
        [41635]  = true,   -- Prayer of Mending
        [77489]  = true,   -- Echo of Light
        -- Mistweaver Monk
        [115175] = true,   -- Soothing Mist
        [119611] = true,   -- Renewing Mist
        [124682] = true,   -- Enveloping Mist
        [450769] = true,   -- Aspect of Harmony
        -- Restoration Shaman
        [974]    = true,   -- Earth Shield
        [383648] = true,   -- Earth Shield (alt ID)
        [61295]  = true,   -- Riptide
        [207400] = true,   -- Ancestral Vigor
        [382024] = true,   -- Earthliving Weapon
        [444490] = true,   -- Hydrobubble
        -- Holy Paladin
        [53563]  = true,   -- Beacon of Light
        [156322] = true,   -- Eternal Flame
        [156910] = true,   -- Beacon of Faith
        [1244893]= true,   -- Beacon of the Savior
    },
    -- ── Rogue Poisons ───────────────────────────────────────────────
    ROGUE_POISONS = {
        [2823]   = true,   -- Deadly Poison
        [8679]   = true,   -- Wound Poison
        [3408]   = true,   -- Crippling Poison
        [5761]   = true,   -- Numbing Poison
        [315584] = true,   -- Instant Poison
        [381637] = true,   -- Atrophic Poison
        [381664] = true,   -- Amplifying Poison
    },
    -- ── Shaman Imbuements ───────────────────────────────────────────
    SHAMAN_IMBUE = {
        [319773] = true,   -- Windfury Weapon
        [319778] = true,   -- Flametongue Weapon
        [382021] = true,   -- Earthliving Weapon
        [382022] = true,   -- Earthliving Weapon (alt)
        [457496] = true,   -- Tidecaller's Guard
        [457481] = true,   -- Tidecaller's Guard (alt)
        [462757] = true,   -- Thunderstrike Ward
        [462742] = true,   -- Thunderstrike Ward (alt)
    },
    -- ── Long-term Self Buffs ────────────────────────────────────────
    SELF_BUFFS = {
        [433568] = true,   -- Rite of Sanctification
        [433583] = true,   -- Rite of Adjuration
    },
    -- ── Resource-like Auras ─────────────────────────────────────────
    RESOURCE_AURAS = {
        [205473] = true,   -- Mage Icicles
        [260286] = true,   -- Hunter Tip of the Spear
    },
    -- ── Skyriding ───────────────────────────────────────────────────
    SKYRIDING = {
        [427490] = true,   -- Ride Along Available
        [447959] = true,   -- Ride Along Active
        [447960] = true,   -- Ride Along Inactive
    },
    -- ── Cooldowns ───────────────────────────────────────────────────
    COOLDOWNS = {
        [8690]   = true,   -- Hearthstone
        [20608]  = true,   -- Shaman Reincarnation
    },
}

------------------------------------------------------------------------
-- Category metadata (for Options UI)
-- Order here = display order in the Options panel.
------------------------------------------------------------------------
local DECLASSIFIED_META = {
    { key = "SATED",           label = "Sated / Exhaustion",
      tooltip = "Exhaustion, Sated, Temporal Displacement, Hunter Pet Fatigued." },
    { key = "DESERTER",        label = "Deserter",
      tooltip = "BG Deserter, Dungeon Deserter." },
    { key = "RAID_BUFFS",      label = "Raid Buffs",
      tooltip = "Mark of the Wild, Arcane Intellect, Fortitude, Battle Shout, Skyfury, etc." },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze",
      tooltip = "All class-specific Blessing of the Bronze variants." },
    { key = "HEALER_HOTS",     label = "Healer HoTs",
      tooltip = "Rejuvenation, Renew, Atonement, Earth Shield, Beacon, and similar healer HoTs or shields." },
    { key = "ROGUE_POISONS",   label = "Rogue Poisons",
      tooltip = "Deadly, Wound, Crippling, Numbing, Instant, Atrophic, Amplifying." },
    { key = "SHAMAN_IMBUE",    label = "Shaman Imbuements",
      tooltip = "Windfury, Flametongue, Earthliving, Tidecaller's Guard, Thunderstrike Ward." },
    { key = "SELF_BUFFS",      label = "Long-term Self Buffs",
      tooltip = "Rite of Sanctification, Rite of Adjuration." },
    { key = "RESOURCE_AURAS",  label = "Resource Auras",
      tooltip = "Mage Icicles, Hunter Tip of the Spear." },
    { key = "SKYRIDING",       label = "Skyriding",
      tooltip = "Ride Along Available / Active / Inactive." },
    { key = "COOLDOWNS",       label = "Cooldowns",
      tooltip = "Hearthstone, Shaman Reincarnation." },
}

------------------------------------------------------------------------
-- Default blacklist presets (per role)
-- Keys match DECLASSIFIED_SPELLS category keys.
-- true = HIDDEN (blacklisted)
------------------------------------------------------------------------
local DEFAULT_BLACKLIST_BUFF = {
    SATED           = true,
    DESERTER        = true,
    ROGUE_POISONS   = true,
    SHAMAN_IMBUE    = true,
    SELF_BUFFS      = true,
    SKYRIDING       = true,
    COOLDOWNS       = true,
}

local DEFAULT_BLACKLIST_DEBUFF = {
    SKYRIDING       = true,
    COOLDOWNS       = true,
}

------------------------------------------------------------------------
-- Blacklist hash builder (cached, generation-gated like A2)
-- Merges all enabled category spellIds into a flat lookup table.
-- Zero allocation on steady-state.
------------------------------------------------------------------------
local _hashPools = {}  -- per-gcfg cached hash tables
local _hashValid = {}  -- per-gcfg validity flags
local _spellNameCache = {}

local function GetBlackListableSpellName(sid)
    local cached = _spellNameCache[sid]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local name
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        name = C_Spell.GetSpellName(sid)
    end
    if not name and type(GetSpellInfo) == "function" then
        name = GetSpellInfo(sid)
    end

    if type(name) == "string" and name ~= "" then
        _spellNameCache[sid] = name
        return name
    end

    _spellNameCache[sid] = false
    return nil
end

local function BuildBlacklistHash(gcfg)
    if not gcfg then return nil end
    local cats = gcfg.blacklistCats
    if not cats then return nil end

    -- Use gcfg table identity as cache key
    local hash = _hashPools[gcfg]
    if hash and _hashValid[gcfg] then
        return hash._any and hash or nil
    end

    if not hash then hash = {}; _hashPools[gcfg] = hash end
    wipe(hash)
    hash._any = false

    for catKey, enabled in pairs(cats) do
        if enabled == true then
            local spells = DECLASSIFIED_SPELLS[catKey]
            if spells then
                for sid in pairs(spells) do
                    hash[sid] = true
                    hash._any = true

                    -- Fallback path for API variants where declassified auras expose
                    -- a readable name but not a stable spellId field on Group Frames.
                    local spellName = GetBlackListableSpellName(sid)
                    if spellName then
                        hash[spellName] = true
                    end
                end
            end
        end
    end

    _hashValid[gcfg] = true
    return hash._any and hash or nil
end

--- Invalidate blacklist hash cache (call on config change)
local function InvalidateBlacklistHash(gcfg)
    if gcfg then
        _hashValid[gcfg] = nil
    else
        -- Invalidate all
        for k in pairs(_hashValid) do _hashValid[k] = nil end
    end
end

--- Invalidate all caches (profile swap, preset apply)
local function InvalidateAllBlacklistHashes()
    wipe(_hashValid)
    wipe(_hashPools)
end

------------------------------------------------------------------------
-- Secret-safe spellId decoder (called once per aura in RenderGroup)
-- Returns plain lua number or 0 (secret/nil → passes through blacklist).
--
-- CRITICAL (Midnight 12.0): on non-self units, aura.spellId for
-- declassified spells comes back as an *accessible* secret-tagged integer.
-- canaccessvalue() returns true, but the value still carries the secret
-- tag — using it directly as a hash key (hash[sid]) silently misses every
-- lookup because the tagged value does not equate to a plain lua number.
--
-- The tonumber() pass strips the tag and yields a plain number that works
-- as a hash key. For plain numbers, tonumber() is a no-op C call (cheap).
-- For nil / truly-secret values, tonumber() returns nil → coerced to 0.
------------------------------------------------------------------------
local function DecodeSpellId(aura)
    local sid = aura and (aura.spellId or aura.spellID or aura.spellid)
    -- Secret-safety guard BEFORE any nil / equality check on the field
    if _hasCanaccessvalue then
        if canaccessvalue(sid) ~= true then return 0 end
    elseif issecretvalue and issecretvalue(sid) == true then
        return 0
    end
    -- Normalize: strips secret tag (if any), handles nil, coerces to number
    return tonumber(sid) or 0
end

local function DecodeAuraName(aura)
    local name = aura and (aura.name or aura.spellName)
    if _hasCanaccessvalue then
        if canaccessvalue(name) ~= true then return nil end
    elseif issecretvalue and issecretvalue(name) == true then
        return nil
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

------------------------------------------------------------------------
-- Tier 2 filter: check decoded spellId against blacklist hash
-- Returns true if aura should be SKIPPED (hidden)
-- Secret spellIds fall back to readable aura names when Blizzard exposes
-- them for declassified spells on this client branch.
------------------------------------------------------------------------
local function IsBlacklisted(decodedSid, hash, aura)
    if not hash then return false end
    if decodedSid ~= 0 and hash[decodedSid] == true then
        return true
    end
    local auraName = DecodeAuraName(aura)
    if auraName and hash[auraName] == true then
        return true
    end
    return false
end

local function GetAuraGroupConfig(kind, groupKey)
    if type(groupKey) ~= "string" or groupKey == "" then return nil end
    if type(kind) == "table" then return kind end
    local conf = GF.GetConf and GF.GetConf(kind)
    local auras = conf and conf.auras
    return auras and auras[groupKey] or nil
end

local function GetBlacklistHashForGroup(kind, groupKey)
    local gcfg = GetAuraGroupConfig(kind, groupKey)
    return gcfg and BuildBlacklistHash(gcfg) or nil
end

local function IsSpellOrNameBlacklisted(spellId, spellName, hash)
    if not hash then return false end
    local sid = tonumber(spellId) or 0
    if sid ~= 0 and hash[sid] == true then
        return true
    end
    if type(spellName) == "string" and spellName ~= "" and hash[spellName] == true then
        return true
    end
    if sid ~= 0 then
        local resolvedName = GetBlackListableSpellName(sid)
        if resolvedName and hash[resolvedName] == true then
            return true
        end
    end
    return false
end

local function ShouldHideAura(kind, groupKey, aura)
    local hash = GetBlacklistHashForGroup(kind, groupKey)
    if not hash then return false end
    return IsBlacklisted(DecodeSpellId(aura), hash, aura)
end

local function ShouldHideBuffAura(kind, aura)
    return ShouldHideAura(kind, "buff", aura)
end

local function ShouldHideDebuffAura(kind, aura)
    return ShouldHideAura(kind, "debuff", aura)
end

local function ShouldSuppressFamily(kind, spellIds, groupKey)
    local hash = GetBlacklistHashForGroup(kind, groupKey or "buff")
    if not hash or type(spellIds) ~= "table" then return false end
    for i = 1, #spellIds do
        if IsSpellOrNameBlacklisted(spellIds[i], nil, hash) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Export to GF namespace
------------------------------------------------------------------------
local AuraFilter = {}
GF.AuraFilter = AuraFilter

-- Tables
AuraFilter.BUFF_TOKENS          = BUFF_TOKENS
AuraFilter.DEBUFF_TOKENS        = DEBUFF_TOKENS
AuraFilter.EXTERNALS_TOKEN      = EXTERNALS_TOKEN
AuraFilter.DECLASSIFIED_SPELLS  = DECLASSIFIED_SPELLS
AuraFilter.DECLASSIFIED_META    = DECLASSIFIED_META
AuraFilter.BUFF_FILTER_ITEMS    = BUFF_FILTER_ITEMS
AuraFilter.DEBUFF_FILTER_ITEMS  = DEBUFF_FILTER_ITEMS
AuraFilter.DEFAULT_BLACKLIST_BUFF   = DEFAULT_BLACKLIST_BUFF
AuraFilter.DEFAULT_BLACKLIST_DEBUFF = DEFAULT_BLACKLIST_DEBUFF

-- Functions
AuraFilter.ResolveBuffFilter    = ResolveBuffFilter
AuraFilter.ResolveDebuffFilter  = ResolveDebuffFilter
AuraFilter.BuildBlacklistHash   = BuildBlacklistHash
AuraFilter.InvalidateBlacklistHash     = InvalidateBlacklistHash
AuraFilter.InvalidateAllBlacklistHashes = InvalidateAllBlacklistHashes
AuraFilter.DecodeSpellId        = DecodeSpellId
AuraFilter.IsBlacklisted        = IsBlacklisted
AuraFilter.GetAuraGroupConfig   = GetAuraGroupConfig
AuraFilter.GetBlacklistHashForGroup = GetBlacklistHashForGroup
AuraFilter.IsSpellOrNameBlacklisted = IsSpellOrNameBlacklisted
AuraFilter.ShouldHideAura       = ShouldHideAura
AuraFilter.ShouldHideBuffAura   = ShouldHideBuffAura
AuraFilter.ShouldHideDebuffAura = ShouldHideDebuffAura
AuraFilter.ShouldSuppressFamily = ShouldSuppressFamily

-- Global export for other modules
_G.MSUF_GF_AuraFilter = AuraFilter
