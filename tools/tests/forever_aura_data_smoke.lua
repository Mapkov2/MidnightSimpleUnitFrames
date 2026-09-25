-- WoW Forever aura data smoke.
--
-- WoW Forever runs the Mainline load graph on Classic Era spell data with
-- ranks. UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml therefore loads
-- Game/Forever/Auras/MSUF_Auras3_ForeverData.lua after the Retail curated
-- datasets and the generated Forever SpellName catalog after the Retail one.
-- On WoW Forever they replace the Retail DoT, defensive, Big Defensive and
-- Group Highlights data with IDs that exist in build 1.60.1.70009 and broaden
-- every ID to its same-name ranks. On every other client (and in harnesses
-- without MSUF.Client) both stay inert, so Retail data and behaviour are
-- byte-for-byte what the Retail files define.
local root = assert(arg[1], "repository root argument missing")

local LOCALES = { "Common", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local FOREVER_BUILD = "1.60.1.70009"
local FOREVER_DATA = "MidnightSimpleUnitFrames/Game/Forever/Auras/MSUF_Auras3_ForeverData.lua"
local FOREVER_CLASSES = {
    WARRIOR = true, PALADIN = true, PRIEST = true, SHAMAN = true, DRUID = true,
    ROGUE = true, MAGE = true, WARLOCK = true, HUNTER = true,
}

-- Every curated Forever ID with its enUS name in SpellName 1.60.1.70009
-- (wago.tools export, sha256 b9a0d125fd47e02c13790504e2f10c4e67a3e5d5c4a91295bd96514ba36610a6).
-- Adding an ID to the Forever data requires checking it against that build.
local PROVENANCE = {
    [17] = "Power Word: Shield", [133] = "Fireball", [172] = "Corruption", [348] = "Immolate",
    [498] = "Divine Protection", [586] = "Fade", [589] = "Shadow Word: Pain",
    [603] = "Bane of Doom", [642] = "Divine Shield", [703] = "Garrote", [740] = "Tranquility",
    [772] = "Rend", [871] = "Shield Wall", [980] = "Bane of Agony", [1020] = "Divine Shield",
    [1022] = "Blessing of Protection", [1044] = "Blessing of Freedom", [1079] = "Rip",
    [1463] = "Mana Shield", [1719] = "Recklessness", [1822] = "Rake", [1943] = "Rupture",
    [1966] = "Feint", [1978] = "Serpent Sting", [2818] = "Deadly Poison",
    [2944] = "Devouring Plague", [3034] = "Viper Sting", [3043] = "Scorpid Sting",
    [5277] = "Evasion", [5570] = "Insect Swarm", [5573] = "Divine Protection",
    [5599] = "Blessing of Protection", [6940] = "Blessing of Sacrifice", [7812] = "Sacrifice",
    [8050] = "Flame Shock", [8921] = "Moonfire", [9007] = "Pounce Bleed",
    [10060] = "Power Infusion", [10278] = "Blessing of Protection", [11366] = "Pyroblast",
    [11426] = "Ice Barrier", [11958] = "Ice Block", [12975] = "Last Stand",
    [13750] = "Adrenaline Rush", [13797] = "Immolation Trap Effect", [14914] = "Holy Fire",
    [18265] = "Siphon Life", [19028] = "Soul Link", [19236] = "Desperate Prayer",
    [19263] = "Deterrence", [19574] = "Bestial Wrath", [20230] = "Retaliation",
    [22812] = "Barkskin", [22842] = "Frenzied Regeneration", [29166] = "Innervate",
}

local function readFile(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing file: " .. rel)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function run(rel, namespace)
    assert(loadfile(root .. "/" .. rel))("MidnightSimpleUnitFrames", namespace)
end

local function aliasPath(dir, locale)
    return "MidnightSimpleUnitFrames/" .. dir .. "/MSUF_Auras3_AliasData_" .. locale .. ".lua"
end

-- 1. Manifest: the data file follows the Retail datasets; the Forever catalog
-- follows the Retail catalog and precedes the shared resolver.
do
    local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    local xml = table.concat(Manifest.Paths(root, "Mainline"), "\n")
    local function at(line)
        local position = xml:find(line, 1, true)
        assert(position, "Mainline elements manifest is missing: " .. line)
        assert(not xml:find(line, position + 1, true), "Mainline elements manifest repeats: " .. line)
        return position
    end
    local groupHighlightsAt = at("Auras3/MSUF_Auras3_GroupHighlightsData.lua")
    local dataAt = at("Game/Forever/Auras/MSUF_Auras3_ForeverData.lua")
    local retailCatalogAt = at("Auras3/AliasData/MSUF_Auras3_AliasData_Common.lua")
    local retailCatalogEndAt = at("Auras3/AliasData/MSUF_Auras3_AliasData_zhTW.lua")
    local resolverAt = at("Auras3/MSUF_Auras3_AuraAliases.lua")
    assert(groupHighlightsAt < dataAt and dataAt < retailCatalogAt,
        "Forever data must load after the Retail curated datasets and before the catalogs")
    local previous = retailCatalogEndAt
    for _, locale in ipairs(LOCALES) do
        local position = at("Game/Forever/Auras/AliasData/MSUF_Auras3_AliasData_" .. locale .. ".lua")
        assert(position > previous and position < resolverAt,
            "Forever " .. locale .. " catalog must load after the Retail catalog, in locale order, before the resolver")
        previous = position
        local source = readFile(aliasPath("Game/Forever/Auras/AliasData", locale))
        assert(source:find("-- SpellName / Forever " .. FOREVER_BUILD .. " / " .. locale, 1, true),
            locale .. " Forever catalog must carry the " .. FOREVER_BUILD .. " build header")
        assert(source:find("\nif not (Client ~= nil and Client.IsForever == true) then return end\n", 1, true),
            locale .. " Forever catalog must be gated on the Forever client fact")
    end
    assert(not xml:find("Game/Vanilla", 1, true) and not xml:find("Game/Classic", 1, true),
        "the Mainline elements manifest must not load Classic data")
end

local function newNamespace(client)
    _G.MSUF_NS = nil
    return { MSUF_Auras3 = {}, Client = client }
end

local function loadRetailData(namespace)
    run("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DotData.lua", namespace)
    run("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua", namespace)
    run("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_GroupHighlightsData.lua", namespace)
end

local function loadForeverCatalog(namespace)
    for _, locale in ipairs(LOCALES) do run(aliasPath("Game/Forever/Auras/AliasData", locale), namespace) end
end

_G.GetLocale = function() return "enUS" end

-- 2. Every other client, and harnesses without a client model: inert.
for _, client in ipairs({ false, { IsForever = false, IsRetail = true } }) do
    local namespace = newNamespace(client or nil)
    loadRetailData(namespace)
    local A3 = namespace.MSUF_Auras3
    local snapshot = {
        TargetDotData = A3.TargetDotData, PlayerDefensiveData = A3.PlayerDefensiveData,
        BigDefensiveData = A3.BigDefensiveData, AuraSpellIDAliases = A3.AuraSpellIDAliases,
        AddAuraSpellIDAndAliases = A3.AddAuraSpellIDAndAliases,
        GetBigDefensiveSpellIDHash = A3.GetBigDefensiveSpellIDHash,
        GetGroupHighlightsSpellIDHash = A3.GetGroupHighlightsSpellIDHash,
        TargetDotDataVersion = A3.TargetDotDataVersion,
        PlayerDefensiveDataVersion = A3.PlayerDefensiveDataVersion,
        BigDefensiveDataVersion = A3.BigDefensiveDataVersion,
        GroupHighlightsDataVersion = A3.GroupHighlightsDataVersion,
        GroupHighlightsDataCount = A3.GroupHighlightsDataCount,
    }
    local sentinelCatalog = { build = "sentinel", width = 4 }
    A3.AuraAliasCatalog = sentinelCatalog
    run(FOREVER_DATA, namespace)
    loadForeverCatalog(namespace)
    for key, value in pairs(snapshot) do
        assert(rawequal(A3[key], value), "non-Forever client changed A3." .. key)
    end
    assert(rawequal(A3.AuraAliasCatalog, sentinelCatalog) and sentinelCatalog.common == nil
        and sentinelCatalog.localized == nil and sentinelCatalog.locale == nil,
        "non-Forever client loaded the Forever catalog")
    assert(A3.TargetDotDataVersion == "12.0.7.68453+12.1.0.68745"
        and A3.BigDefensiveDataVersion == "EUI-8.8.3+12.1.0.69189",
        "non-Forever client lost the Retail dataset baselines")
    local _, signature, highlightCount = A3.GetGroupHighlightsSpellIDHash()
    assert(highlightCount == 122 and signature == "groupHighlights:12.1.0.69497-v1:122",
        "non-Forever client lost the Retail Group Highlights set")
    local out = {}
    A3.AddAuraSpellIDAndAliases(out, 17)
    assert(count(out) == 1 and out[17] == true, "non-Forever client must keep the explicit-alias Retail expander")
end

-- 3. WoW Forever: the full Mainline order, Retail catalog included.
local namespace = newNamespace({ IsForever = true, IsRetail = true })
local A3 = namespace.MSUF_Auras3
loadRetailData(namespace)
run(FOREVER_DATA, namespace)

-- A request before the resolver loads must not pin an unbroadened set.
do
    local early, earlySignature, earlyCount = A3.GetGroupHighlightsSpellIDHash()
    assert(earlyCount == 17 and count(early) == 17 and earlySignature:find(":17$"),
        "a premature Group Highlights request must return the 17 exact base IDs")
    for spellID in pairs(early) do
        assert(PROVENANCE[spellID] ~= nil, "Group Highlights ID " .. spellID .. " is not verified against " .. FOREVER_BUILD)
    end
    local later = A3.GetGroupHighlightsSpellIDHash()
    assert(not rawequal(early, later), "a premature Group Highlights request must not be cached")
    local earlyBig = A3.GetBigDefensiveSpellIDHash()
    assert(not rawequal(earlyBig, A3.GetBigDefensiveSpellIDHash()), "a premature Big Defensive request must not be cached")
end

run(aliasPath("Auras3/AliasData", "Common"), namespace)
run(aliasPath("Auras3/AliasData", "enUS"), namespace)
assert(A3.AuraAliasCatalog.build == "12.1.0.69587", "Retail catalog precondition")
loadForeverCatalog(namespace)
local catalog = A3.AuraAliasCatalog
assert(catalog.build == "Forever-" .. FOREVER_BUILD, "WoW Forever must replace the Retail catalog")
assert(catalog.locale == "enUS", "only the active locale may load its Forever partition")
assert(type(catalog.common) == "string" and type(catalog.localized) == "string",
    "the Forever catalog must provide common and localized blobs")
run("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraAliases.lua", namespace)
assert(type(A3.CompileCustomAuraAliases) == "function", "resolver did not install")

-- Dataset versions and class coverage.
assert(A3.TargetDotDataVersion == "Forever-" .. FOREVER_BUILD
    and A3.PlayerDefensiveDataVersion == "Forever-" .. FOREVER_BUILD
    and A3.BigDefensiveDataVersion == "Forever-" .. FOREVER_BUILD .. "-v1"
    and A3.GroupHighlightsDataVersion == "Forever-" .. FOREVER_BUILD .. "-v1"
    and A3.GroupHighlightsDataCount == 17,
    "WoW Forever dataset versions")

local seen = 0
local function checkEntries(label, data, expectedIDs)
    local ids = 0
    for class, entries in pairs(data) do
        assert(FOREVER_CLASSES[class], label .. " lists a class WoW Forever does not have: " .. tostring(class))
        assert(#entries > 0, label .. " has an empty class list: " .. class)
        for i = 1, #entries do
            local spellID, name = entries[i][1], entries[i][2]
            assert(PROVENANCE[spellID] ~= nil, label .. " ID " .. tostring(spellID) .. " is not verified against " .. FOREVER_BUILD)
            assert(PROVENANCE[spellID] == name, label .. " label for " .. spellID .. " must be the Forever name " .. PROVENANCE[spellID])
            ids = ids + 1
            seen = seen + 1
        end
    end
    assert(ids == expectedIDs, label .. " entry count " .. ids .. ", expected " .. expectedIDs)
end
checkEntries("TargetDotData", A3.TargetDotData, 24)
checkEntries("PlayerDefensiveData", A3.PlayerDefensiveData, 22)
checkEntries("BigDefensiveData", A3.BigDefensiveData, 10)
for _, removed in ipairs({ 12654, 12721, 19386 }) do
    for _, entries in pairs(A3.TargetDotData) do
        for i = 1, #entries do assert(entries[i][1] ~= removed, "removed Era DoT ID came back: " .. removed) end
    end
end

-- Rank broadening, as on Classic.
local function expands(sourceID, expected, forbidden)
    local out = {}
    A3.AddAuraSpellIDAndAliases(out, sourceID)
    assert(out[sourceID] == true, "expansion must keep source ID " .. sourceID)
    for _, id in ipairs(expected) do
        assert(out[id] == true, sourceID .. " must expand to same-name Forever ID " .. id)
    end
    for _, id in ipairs(forbidden or {}) do
        assert(out[id] == nil, sourceID .. " must not expand to " .. id)
    end
end
expands(17, { 592, 600, 10901 }, { 116849 })
expands(589, { 594, 10892, 10893, 10894 })
expands(980, { 1014, 6217, 11711, 11712, 11713 })
expands(774, { 1058, 1430, 25299 }, { 116849 })
local lone = {}
A3.AddAuraSpellIDAndAliases(lone, 999999)
assert(count(lone) == 1 and lone[999999] == true, "unknown IDs stay singletons")

-- Big Defensive: Forever IDs and their ranks; no Retail-only IDs.
do
    local hash, signature = A3.GetBigDefensiveSpellIDHash()
    local same, sameSignature = A3.GetBigDefensiveSpellIDHash()
    assert(rawequal(hash, same) and signature == sameSignature, "Big Defensive hash must be cached once broadened")
    assert(signature:find("^bigDefensive:"), "Big Defensive signature contract")
    for _, id in ipairs({ 22812, 22842, 22845, 11958, 498, 5573, 642, 1020, 19236, 19243, 586, 10942, 5277, 1966, 25302, 871 }) do
        assert(hash[id] == true, "Big Defensive must include Forever ID " .. id)
    end
    for _, id in ipairs({ 48707, 45438, 31224, 61336, 186265, 12472 }) do
        assert(hash[id] == nil, "Big Defensive must not include Retail-only or renamed ID " .. id)
    end
end

-- Group Highlights: same return contract, broadened, no renamed IDs.
do
    local hash, signature, total = A3.GetGroupHighlightsSpellIDHash()
    local same, sameSignature, sameTotal = A3.GetGroupHighlightsSpellIDHash()
    assert(rawequal(hash, same) and signature == sameSignature and total == sameTotal,
        "Group Highlights hash must be shared and stable once broadened")
    assert(total == count(hash) and total > 17, "Group Highlights count must cover the broadened ranks")
    assert(signature == "groupHighlights:Forever-" .. FOREVER_BUILD .. "-v1:" .. total, "Group Highlights signature contract")
    for _, id in ipairs({ 642, 1020, 740, 9863, 871, 1022, 5599, 10278, 1966, 5277, 6940, 20729, 11958, 19236,
        22812, 498, 5573, 1044, 1719, 10060, 13750, 19574, 29166 }) do
        assert(hash[id] == true, "Group Highlights must include Forever ID " .. id)
    end
    -- 12472 is Cold Snap on Forever (Icy Veins on Retail); 45438/31224 do not exist there.
    for _, id in ipairs({ 12472, 45438, 31224, 33206, 8178, 23920 }) do
        assert(hash[id] == nil, "Group Highlights must not include " .. id)
    end
end

print(string.format("forever_aura_data_smoke: ok (%d curated entries verified against %s)", seen, FOREVER_BUILD))
