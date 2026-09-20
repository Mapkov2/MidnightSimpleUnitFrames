-- Execute the shipped TOC/XML selection contract for every client language.
-- This is a desktop manifest/data test, not a WoW startup timing measurement.
local root = arg and arg[1] or "."
local addon = root .. "/MidnightSimpleUnitFrames"
local function Read(path)
    -- The legacy driver groups split modules for old harnesses. Manifest byte
    -- counts and XML traversal must read physical files, never grouped text.
    local harness = rawget(_G, "MSUF_Auras3TestLoader")
    if harness and harness.ReadSource then return harness.ReadSource(path) end
    local f = assert(io.open(path, "rb"), path)
    local text = f:read("*a")
    f:close()
    return text
end
local function Normalize(path)
    path = path:gsub("\\", "/")
    local absolute, parts = path:sub(1, 1) == "/", {}
    for part in path:gmatch("[^/]+") do
        if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return (absolute and "/" or "") .. table.concat(parts, "/")
end
local function Scripts(locale)
    local paths, seen = {}, {}
    local function Visit(path)
        path = Normalize(path)
        assert(not seen[path], "duplicate startup file: " .. path)
        seen[path] = true
        local source = Read(path)
        if path:match("%.lua$") then
            paths[#paths + 1] = path
        else
            local directory = path:match("^(.*)/")
            for kind, ref in source:gmatch('<(%a+)%s+file="([^"]+)"') do
                assert(kind == "Script" or kind == "Include", kind)
                Visit(directory .. "/" .. ref)
            end
        end
    end
    for line in Read(addon .. "/MidnightSimpleUnitFrames.toc"):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local allowed = line:match("^%[AllowLoadTextLocale:%s*(%a+)%]%s+")
            local selected = not allowed
            if allowed then
                for name in allowed:gmatch("%a+") do
                    if name == locale then selected = true end
                end
                line = line:gsub("^%[AllowLoadTextLocale:%s*%a+%]%s+", "")
            end
            assert(not line:find("[", 1, true), "unhandled TOC condition: " .. line)
            if selected then Visit(addon .. "/" .. line) end
        end
    end
    return paths
end
local locales = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT",
    "koKR", "ptBR", "ptPT", "ruRU", "zhCN", "zhTW" }
local aliasLoader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
local invariantOrder
for _, locale in ipairs(locales) do
    local expectedLocale = locale == "enGB" and "enUS" or locale == "ptPT" and "ptBR" or locale
    local scripts = Scripts(locale)
    local data, order, bytes, indexes, menuLocales = {}, {}, 0, {}, 0
    for i, path in ipairs(scripts) do
        bytes = bytes + #Read(path)
        indexes[path:match("([^/]+)$")] = i
        local aliasLocale = path:match("MSUF_Auras3_AliasData_(%a+)%.lua$")
        if aliasLocale then
            data[#data + 1] = aliasLocale
        else
            order[#order + 1] = path
        end
        if path:match("/Locales/%a%a%u%u%.lua$") then menuLocales = menuLocales + 1 end
        assert(not path:find("_Options/", 1, true) and not path:find("_Assistant/", 1, true),
            "startup eagerly loads an optional companion")
    end
    assert(#data == 2 and data[1] == "Common" and data[2] == expectedLocale,
        "wrong client-language alias payload: " .. locale)
    assert(menuLocales == 12, "client filtering broke independent saved menu language")
    assert(bytes < 15000000, "startup source budget regressed: " .. bytes)
    local commonAt = assert(indexes["MSUF_Auras3_AliasData_Common.lua"])
    assert(indexes["MSUF_Auras3_GroupHighlightsData.lua"] == commonAt - 1,
        "alias data moved ahead of its Auras3 prerequisites")
    assert(indexes["MSUF_Auras3_AuraAliases.lua"] == commonAt + 2,
        "alias compiler must follow Common and selected client data")
    assert(indexes["MSUF_Auras3_UnitFrames.lua"] > commonAt + 2,
        "runtime factories loaded before alias compiler")
    order = table.concat(order, "\n")
    assert(not invariantOrder or order == invariantOrder, "non-alias load order varies with locale")
    invariantOrder = order

    -- Execute the actual selected files, with the UI locale deliberately
    -- different. Spell aliases must always follow the game client language.
    _G.GetLocale = function() return locale end
    local namespace = { LOCALE = locale == "deDE" and "enUS" or "deDE",
        MSUF_Auras3 = { AuraSpellIDAliases = {} } }
    for i = commonAt, commonAt + 2 do
        assert(loadfile(scripts[i]))("MidnightSimpleUnitFrames", namespace)
    end
    local auras = namespace.MSUF_Auras3
    assert(auras.AuraAliasCatalog.locale == expectedLocale, "wrong runtime data for " .. locale)
    auras.CompileCustomAuraAliases({ [185313] = true, [100] = true, [99999999] = true })
    assert(auras.AuraSpellIDAliases[99999999] == nil, "unknown ID gained guessed aliases")
    if expectedLocale == "enUS" then
        assert(#auras.AuraSpellIDAliases[100] == 340, "English aliases changed")
    elseif expectedLocale == "deDE" then
        assert(#auras.AuraSpellIDAliases[100] == 38, "German aliases changed")
    end

    -- Legacy integration harnesses must exercise the same selected data.
    local adapted = {}
    aliasLoader.LoadAliasCatalog(root, adapted)
    assert(adapted.MSUF_Auras3.AuraAliasCatalog.common == auras.AuraAliasCatalog.common)
    assert(adapted.MSUF_Auras3.AuraAliasCatalog.localized == auras.AuraAliasCatalog.localized)
    print(string.format("PASS startup %s: %d scripts, %.2f MB; exact %s aliases",
        locale, #scripts, bytes / 1000000, expectedLocale))
end

-- An unknown future locale previously kept Common only, never English aliases.
local unknownData = 0
for _, path in ipairs(Scripts("xxXX")) do
    if path:find("MSUF_Auras3_AliasData_", 1, true) then
        unknownData = unknownData + 1
        assert(path:find("MSUF_Auras3_AliasData_Common.lua", 1, true))
    end
end
assert(unknownData == 1, "unknown locale gained a cross-language alias fallback")
print("PASS startup locale selection: all clients, locale aliases, menu independence, order and source budget")
