--- Game/Forever/Auras/MSUF_Auras3_ForeverData.lua
--- WoW Forever curated aura data and rank broadening.
---
--- WoW Forever reads the _Mainline.toc files, so it loads the Retail curated
--- aura datasets right before this file (Auras3/MSUF_Auras3_DotData.lua,
--- _DefensiveData.lua and _GroupHighlightsData.lua). Its spell database is
--- Classic Era data with spell ranks, where almost none of those Retail IDs
--- exist. On WoW Forever only, this file replaces the datasets and installs
--- Classic rank broadening for custom aura filters. Group Highlights uses
--- an exact list of the player aura IDs and their ranks. Every other client
--- returns at once and keeps the Retail data unchanged.
---
--- Provenance: selected from wago.tools DB2 exports for 1.60.1.69876 and
--- revalidated against 1.60.1.70009 (SpellName enUS sha256 b9a0d125fd47e02c...,
--- SkillLine, SkillLineAbility and SpellEffect).
---   TargetDotData, PlayerDefensiveData: the Classic Era datasets
---     (Game/Vanilla/Auras) with their Forever names. Dropped because Forever
---     no longer has the ID: 12654 Ignite, 12721 Deep Wound, 19386 Wyvern Sting.
---   BigDefensiveData: the Retail entries whose ID keeps its
---     Retail 12.1.0.69497 name on Forever and is a class ability in Forever
---     SkillLineAbility, plus Ice Block 11958 from the Era defensive list
---     (Retail's Ice Block ID 45438 does not exist on Forever).
---   Group Highlights: the current Forever catalog documented below.
local _, MSUF = ...

local Client = MSUF.Client
local IS_FOREVER = Client.IsForever == true
if not IS_FOREVER then return end

local A3 = MSUF.MSUF_Auras3

local math_floor = math.floor
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type

local FOREVER_DATA_BUILD = "Forever-1.60.1.70009"

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

--- Verified against Forever 1.60.1.70938 SpellName, SpellEffect and
--- SkillLineAbility, the active talent trees and Blizzard's class updates.
--- These are the auras that the native Party/Raid Buff filter should see.
--- List ranks and triggered effects explicitly: a name may also belong to an
--- NPC spell, a hidden controller, or a cast that does not apply a buff.
local GROUP_HIGHLIGHTS_VERSION = "Forever-1.60.1.70938-v2"
local groupHighlightSpellIDs = {
    -- Druid
    22812, -- Barkskin
    22842, -- Frenzied Regeneration
    17116, -- Nature's Swiftness (Druid)
    29166, -- Innervate (recipient)
    740, 8918, 9862, 9863, -- Tranquility, ranks 1–4

    -- Hunter
    19263, -- Deterrence
    3045, -- Rapid Fire
    19574, -- Bestial Wrath (pet)

    -- Mage
    11958, -- Ice Block
    11426, 13031, 13032, 13033, -- Ice Barrier, ranks 1–4
    12042, -- Arcane Power
    12043, -- Presence of Mind
    28682, -- Combustion critical-strike aura (triggered by 11129)

    -- Paladin
    498, 5573, -- Divine Protection, ranks 1–2
    642, 1020, -- Divine Shield, ranks 1–2
    1022, 5599, 10278, -- Blessing of Protection, ranks 1–3 (recipient)
    6940, 20729, -- Blessing of Sacrifice, ranks 1–2 (recipient)
    1044, -- Blessing of Freedom (recipient)
    1311015, -- Templar's Bulwark
    19753, -- Divine Intervention aura (triggered by 19752)
    20216, -- Divine Favor

    -- Priest
    2651, -- Elune's Grace
    6346, -- Fear Ward (recipient)
    10060, -- Power Infusion (recipient)
    14751, -- Inner Focus
    1277462, 1277634, 1277638, 1277639, 1277640, -- Contingency Plan, ranks 1–5 (recipient ward)
    1277463, 1277464, 1277465, 1277467, 1277466, -- Contingency Plan, ranks 1–5 (triggered absorb)

    -- Rogue
    5277, -- Evasion
    11327, 11329, -- Vanish auras, ranks 1–2 (triggered by 1856/1857)
    13750, -- Adrenaline Rush
    13877, -- Blade Flurry
    14177, -- Cold Blood

    -- Shaman
    8178, -- Grounding Totem (recipient spell redirection)
    16166, -- Lightning Mastery
    16188, -- Nature's Swiftness (Shaman)
    16191, 17355, 17360, 1325257, -- Mana Tide, ranks 1–4 (party mana aura)
    425336, -- Rage of the Farseer

    -- Warlock
    7812, 19438, 19440, 19441, 19442, 19443, -- Voidwalker Sacrifice, ranks 1–6 (owner shield)
    18288, -- Amplify Curse

    -- Warrior
    871, -- Shield Wall
    12976, -- Last Stand health aura (cast 12975)
    18499, -- Berserker Rage (fear and incapacitate immunity)
    20230, -- Retaliation
    1719, -- Recklessness
    12292, -- Sweeping Strikes in Forever
    12328, -- Death Wish in Forever
}

local GROUP_HIGHLIGHTS_COUNT = #groupHighlightSpellIDs
local GROUP_HIGHLIGHTS_SIGNATURE = "groupHighlights:" .. GROUP_HIGHLIGHTS_VERSION .. ":" .. GROUP_HIGHLIGHTS_COUNT
A3.GroupHighlightsDataVersion = GROUP_HIGHLIGHTS_VERSION
A3.GroupHighlightsDataCount = GROUP_HIGHLIGHTS_COUNT

local groupHighlightsSpellIDHash

--- Build one shared, immutable hash at the first filter compile.
function A3.GetGroupHighlightsSpellIDHash()
    if not groupHighlightsSpellIDHash then
        local hash = {}
        for i = 1, GROUP_HIGHLIGHTS_COUNT do
            hash[groupHighlightSpellIDs[i]] = true
        end
        groupHighlightsSpellIDHash = hash
        groupHighlightSpellIDs = nil
    end
    return groupHighlightsSpellIDHash, GROUP_HIGHLIGHTS_SIGNATURE, GROUP_HIGHLIGHTS_COUNT
end
