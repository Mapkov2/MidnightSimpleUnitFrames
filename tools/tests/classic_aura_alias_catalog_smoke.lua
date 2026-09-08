-- Classic aura alias catalog smoke.
--
-- Every Classic flavor ships a generated SpellName catalog
-- (Game/<Flavor>/Auras/AliasData) and loads the shared Retail resolver
-- (Auras3/MSUF_Auras3_AuraAliases.lua) right after it. The Classic alias
-- expander must then broaden a rank-1 / cast ID to every same-name ID, so
-- curated DoT and defensive lists, group indicators and user whitelists match
-- ranked Vanilla/TBC auras and Mists cast-vs-aura ID drift by name, the way
-- WeakAuras matches auras on Classic.
local root = assert(arg[1], "repository root argument missing")

local LOCALES = { "Common", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

local function readFile(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing file: " .. rel)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local function sortedKeys(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- Flavor -> { build, sourceID, expected same-name aura IDs, forbidden ID }.
-- Rejuvenation ranks (Vanilla/TBC), Blessing of Protection ranks (TBC) and
-- the Mists Renewing Mist cast (115151) -> aura (119611) drift are the
-- documented WeakAuras-style cases. 116849 (Life Cocoon) must never leak into
-- a Rejuvenation group.
local CASES = {
    Vanilla = { build = "1.15.9.68940", { 774, { 1058, 1430, 2090, 3627, 25299 } }, { 17, { 592, 600, 10901 } } },
    TBC = { build = "2.5.6.68941", { 774, { 1058, 25299, 26981, 26982 } }, { 1022, { 5599, 10278 } } },
    Mists = { build = "5.5.4.68806", { 115151, { 119611 } }, { 33763, { 33778 } } },
}

local ownership = readFile("tools/classic-owned-addon-paths.txt")

for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local case = CASES[flavor]
    local manifest = readFile("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml")
    local previousAt = assert(manifest:find("MSUF_Auras3_DataShared.lua", 1, true),
        flavor .. " manifest must load the shared Classic data helpers")
    local resolverAt = assert(manifest:find([[<Script file="..\..\Auras3\MSUF_Auras3_AuraAliases.lua"/>]], 1, true),
        flavor .. " manifest must load the shared alias resolver")
    for _, locale in ipairs(LOCALES) do
        local rel = "MidnightSimpleUnitFrames/Game/" .. flavor .. "/Auras/AliasData/MSUF_Auras3_AliasData_" .. locale .. ".lua"
        local line = [[<Script file="Auras\AliasData\MSUF_Auras3_AliasData_]] .. locale .. [[.lua"/>]]
        local at = assert(manifest:find(line, 1, true), flavor .. " manifest must load " .. locale .. " alias data")
        assert(at > previousAt and at < resolverAt,
            flavor .. " alias data " .. locale .. " must load after DataShared and before the resolver")
        assert(ownership:find(rel, 1, true), rel .. " must be declared Classic-owned")
        local source = readFile(rel)
        assert(source:find("-- SpellName / Classic " .. flavor .. " " .. case.build .. " / " .. locale, 1, true),
            rel .. " must carry the " .. flavor .. " " .. case.build .. " build header")
        assert(not source:find("Retail", 1, true), rel .. " must not be a Retail catalog")
    end
    local dotAt = assert(manifest:find("MSUF_Auras3_DotData.lua", 1, true))
    assert(resolverAt < dotAt, flavor .. " resolver must load before the curated datasets")

    _G.GetLocale = function() return "enUS" end
    local MSUF = { MSUF_Auras3 = {} }
    local function run(rel) assert(loadfile(root .. "/" .. rel))("MidnightSimpleUnitFrames", MSUF) end
    run("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_DataShared.lua")
    run("MidnightSimpleUnitFrames/Game/" .. flavor .. "/Auras/AliasData/MSUF_Auras3_AliasData_Common.lua")
    for _, locale in ipairs(LOCALES) do
        if locale ~= "Common" then
            run("MidnightSimpleUnitFrames/Game/" .. flavor .. "/Auras/AliasData/MSUF_Auras3_AliasData_" .. locale .. ".lua")
        end
    end
    local A3 = MSUF.MSUF_Auras3
    assert(A3.AuraAliasCatalog and A3.AuraAliasCatalog.build == flavor .. "-" .. case.build,
        flavor .. " catalog build must be " .. case.build)
    assert(A3.AuraAliasCatalog.locale == "enUS", flavor .. " only the active locale may load its partition")
    assert(type(A3.AuraAliasCatalog.common) == "string" and type(A3.AuraAliasCatalog.localized) == "string",
        flavor .. " catalog must provide common and localized blobs")
    run("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraAliases.lua")
    assert(type(A3.CompileCustomAuraAliases) == "function", flavor .. " resolver did not install")

    for _, expectation in ipairs(case) do
        local sourceID, expected = expectation[1], expectation[2]
        local out = {}
        A3.AddAuraSpellIDAndAliases(out, sourceID)
        local ids = sortedKeys(out)
        assert(contains(ids, sourceID), flavor .. " expansion must keep the source ID " .. sourceID)
        for _, aliasID in ipairs(expected) do
            assert(out[aliasID] == true, string.format("%s: %d must expand to same-name aura %d (got %s)",
                flavor, sourceID, aliasID, table.concat(ids, ",")))
        end
        assert(out[116849] ~= true or sourceID == 116849, flavor .. " expansion leaked an unrelated spell")
        -- Second expansion of the same ID must hit the memoized group.
        local again = {}
        A3.AddAuraSpellIDAndAliases(again, sourceID)
        assert(#sortedKeys(again) == #ids, flavor .. " memoized expansion must be stable")
    end

    -- Unknown IDs stay singletons instead of erroring.
    local lone = {}
    A3.AddAuraSpellIDAndAliases(lone, 999999)
    assert(lone[999999] == true and #sortedKeys(lone) == 1, flavor .. " unknown IDs must stay singletons")
    print(string.format("classic_aura_alias_catalog_smoke: %s ok", flavor))
end

print("classic_aura_alias_catalog_smoke: ok")
