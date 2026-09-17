--- Game/Forever/Auras/MSUF_Auras3_ForeverData.lua
--- WoW Forever curated aura data and rank broadening.
---
--- WoW Forever reads the _Mainline.toc files, so it loads the Retail curated
--- aura datasets right before this file (Auras3/MSUF_Auras3_DotData.lua,
--- _DefensiveData.lua and _GroupHighlightsData.lua). Its spell database is
--- Classic Era data with spell ranks, where almost none of those Retail IDs
--- exist. On WoW Forever only, this file replaces the datasets with IDs that
--- exist there and installs the Classic rank broadening
--- (Game/Classic/Auras/MSUF_Auras3_DataShared.lua): every curated or
--- configured ID expands to all same-name IDs of the Forever SpellName catalog
--- (Game/Forever/Auras/AliasData, loaded before Auras3/MSUF_Auras3_AuraAliases.lua),
--- because ranked auras carry rank-specific spell IDs. Every other client
--- returns at once and keeps the Retail data unchanged.
---
--- Provenance: wago.tools DB2 exports for build 1.60.1.69876 (SpellName enUS
--- sha256 ede393ee7dd2d8a7..., SkillLine, SkillLineAbility).
---   TargetDotData, PlayerDefensiveData: the Classic Era datasets
---     (Game/Vanilla/Auras) with their Forever names. Dropped because Forever
---     no longer has the ID: 12654 Ignite, 12721 Deep Wound, 19386 Wyvern Sting.
---   BigDefensiveData, Group Highlights: the Retail entries whose ID keeps its
---     Retail 12.1.0.69497 name on Forever and is a class ability in Forever
---     SkillLineAbility, plus Ice Block 11958 from the Era defensive list
---     (Retail's Ice Block ID 45438 does not exist on Forever).
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local Client = MSUF.Client
local IS_FOREVER = Client ~= nil and Client.IsForever == true
if not IS_FOREVER then return end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local math_floor = math.floor
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type

local FOREVER_DATA_BUILD = "Forever-1.60.1.69876"

A3.AuraSpellIDAliases = A3.AuraSpellIDAliases or {}

--- Same expansion as Game/Classic/Auras/MSUF_Auras3_DataShared.lua. The
--- resolver memoizes hits and misses, so repeated compiles stay O(1).
local singleID = {}
local function ResolveCatalogAliases(spellID)
    local compile = A3.CompileCustomAuraAliases
    if type(compile) ~= "function" then return end
    singleID[spellID] = true
    compile(singleID)
    singleID[spellID] = nil
end

local function AddAuraSpellIDAndAliases(out, spellID)
    spellID = tonumber(spellID)
    if not (out and spellID and spellID > 0) then return end
    spellID = math_floor(spellID + 0.5)
    out[spellID] = true
    ResolveCatalogAliases(spellID)
    local aliases = A3.AuraSpellIDAliases[spellID]
    for i = 1, type(aliases) == "table" and #aliases or 0 do
        local auraSpellID = tonumber(aliases[i])
        if auraSpellID and auraSpellID > 0 then
            out[math_floor(auraSpellID + 0.5)] = true
        end
    end
end
A3.AddAuraSpellIDAndAliases = AddAuraSpellIDAndAliases

A3.TargetDotDataVersion = FOREVER_DATA_BUILD
A3.TargetDotData = {
    DRUID = {
        { 1079, "Rip" }, { 1822, "Rake" }, { 5570, "Insect Swarm" },
        { 8921, "Moonfire" }, { 9007, "Pounce Bleed" },
    },
    HUNTER = {
        { 1978, "Serpent Sting" }, { 3034, "Viper Sting" },
        { 3043, "Scorpid Sting" }, { 13797, "Immolation Trap Effect" },
    },
    MAGE = {
        { 133, "Fireball" }, { 11366, "Pyroblast" },
    },
    PRIEST = {
        { 589, "Shadow Word: Pain" }, { 2944, "Devouring Plague" },
        { 14914, "Holy Fire" },
    },
    ROGUE = {
        { 703, "Garrote" }, { 1943, "Rupture" }, { 2818, "Deadly Poison" },
    },
    SHAMAN = { { 8050, "Flame Shock" } },
    WARLOCK = {
        { 172, "Corruption" }, { 348, "Immolate" },
        { 603, "Bane of Doom" }, { 980, "Bane of Agony" },
        { 18265, "Siphon Life" },
    },
    WARRIOR = { { 772, "Rend" } },
}

A3.PlayerDefensiveDataVersion = FOREVER_DATA_BUILD
A3.PlayerDefensiveData = {
    DRUID = {
        { 22812, "Barkskin" }, { 22842, "Frenzied Regeneration" },
    },
    HUNTER = { { 19263, "Deterrence" } },
    MAGE = {
        { 1463, "Mana Shield" }, { 11426, "Ice Barrier" },
        { 11958, "Ice Block" },
    },
    PALADIN = {
        { 498, "Divine Protection" }, { 5573, "Divine Protection" },
        { 642, "Divine Shield" }, { 1020, "Divine Shield" },
        { 1022, "Blessing of Protection" }, { 5599, "Blessing of Protection" },
        { 10278, "Blessing of Protection" }, { 1044, "Blessing of Freedom" },
        { 6940, "Blessing of Sacrifice" },
    },
    PRIEST = { { 17, "Power Word: Shield" } },
    ROGUE = { { 5277, "Evasion" } },
    WARLOCK = { { 7812, "Sacrifice" }, { 19028, "Soul Link" } },
    WARRIOR = {
        { 871, "Shield Wall" }, { 12975, "Last Stand" },
        { 20230, "Retaliation" },
    },
}

--- Broadened hashes are built once, on the first cold compile request. Until
--- the catalog resolver has loaded, a request gets the exact IDs uncached, so
--- a premature call can never pin an unbroadened set.
local function BroadenedSpellIDHash(baseIDs)
    local hash, count = {}, 0
    for i = 1, #baseIDs do AddAuraSpellIDAndAliases(hash, baseIDs[i]) end
    for _ in pairs(hash) do count = count + 1 end
    return hash, count, type(A3.CompileCustomAuraAliases) == "function"
end

A3.BigDefensiveDataVersion = FOREVER_DATA_BUILD .. "-v1"
A3.BigDefensiveData = {
    DRUID = {
        { 22812, "Barkskin" },
        { 22842, "Frenzied Regeneration" },
    },
    MAGE = {
        { 11958, "Ice Block" },
    },
    PALADIN = {
        { 498, "Divine Protection" },
        { 642, "Divine Shield" },
    },
    PRIEST = {
        { 19236, "Desperate Prayer" },
        { 586, "Fade" },
    },
    ROGUE = {
        { 5277, "Evasion" },
        { 1966, "Feint" },
    },
    WARRIOR = {
        { 871, "Shield Wall" },
    },
}

local bigDefensiveSpellIDHash
local bigDefensiveSpellIDSignature

--- Forever variant of the Retail all-class Big Defensive hash: the same
--- contract (immutable shared hash, sorted "bigDefensive:" signature), with
--- every entry broadened to its ranks.
function A3.GetBigDefensiveSpellIDHash()
    if bigDefensiveSpellIDHash then
        return bigDefensiveSpellIDHash, bigDefensiveSpellIDSignature
    end
    local baseIDs = {}
    for _, entries in pairs(A3.BigDefensiveData) do
        for i = 1, #entries do
            local entry = entries[i]
            baseIDs[#baseIDs + 1] = entry[1]
            local alts = entry[3]
            for j = 1, type(alts) == "table" and #alts or 0 do
                baseIDs[#baseIDs + 1] = alts[j]
            end
        end
    end
    local hash, _, final = BroadenedSpellIDHash(baseIDs)
    local ids = {}
    for spellID in pairs(hash) do ids[#ids + 1] = spellID end
    table_sort(ids)
    for i = 1, #ids do ids[i] = tostring(ids[i]) end
    local signature = "bigDefensive:" .. table_concat(ids, ",")
    if final then
        bigDefensiveSpellIDHash = hash
        bigDefensiveSpellIDSignature = signature
    end
    return hash, signature
end

--- Group Highlights base aura IDs, in the Retail categories.
local GROUP_HIGHLIGHTS_VERSION = FOREVER_DATA_BUILD .. "-v1"
local groupHighlightSpellIDs = {
    -- Defensive and healer-throughput cooldowns (10).
    642, -- Divine Shield
    740, -- Tranquility
    871, -- Shield Wall
    1022, -- Blessing of Protection
    1966, -- Feint
    5277, -- Evasion
    6940, -- Blessing of Sacrifice
    11958, -- Ice Block
    19236, -- Desperate Prayer
    22812, -- Barkskin

    -- Major offensive and decision-relevant support cooldowns (7).
    498, -- Divine Protection
    1044, -- Blessing of Freedom
    1719, -- Recklessness
    10060, -- Power Infusion
    13750, -- Adrenaline Rush
    19574, -- Bestial Wrath
    29166, -- Innervate
}

A3.GroupHighlightsDataVersion = GROUP_HIGHLIGHTS_VERSION
A3.GroupHighlightsDataCount = #groupHighlightSpellIDs

local groupHighlightsSpellIDHash
local groupHighlightsSpellIDSignature
local groupHighlightsSpellIDCount

--- Forever variant of the Retail Group Highlights set: the same return
--- contract (shared immutable hash, signature, ID count), broadened to ranks.
function A3.GetGroupHighlightsSpellIDHash()
    if groupHighlightsSpellIDHash then
        return groupHighlightsSpellIDHash, groupHighlightsSpellIDSignature, groupHighlightsSpellIDCount
    end
    local hash, count, final = BroadenedSpellIDHash(groupHighlightSpellIDs)
    local signature = "groupHighlights:" .. GROUP_HIGHLIGHTS_VERSION .. ":" .. count
    if final then
        groupHighlightsSpellIDHash = hash
        groupHighlightsSpellIDSignature = signature
        groupHighlightsSpellIDCount = count
    end
    return hash, signature, count
end
