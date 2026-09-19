-- Exercise every shipped client/language combination and compare the selected
-- catalog with the old all-language execution. No live WoW timing claim.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local function Read(path)
    local f = assert(io.open(path, "rb"), path)
    local text = f:read("*a"); f:close()
    return text
end
local locales = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT",
    "koKR", "ptBR", "ptPT", "ruRU", "zhCN", "zhTW", "xxXX" }
local count = 0
for _, client in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local suffix = client == "Forever" and "Mainline" or client
    local all = Manifest.Paths(root, suffix)
    for _, locale in ipairs(locales) do
        local selected = Manifest.Paths(root, suffix, locale)
        local bytes, aliases, menuLocales, index = 0, {}, 0, {}
        for i, path in ipairs(selected) do
            bytes = bytes + #Read(path)
            index[path] = i
            if path:find("/AliasData/", 1, true) then aliases[#aliases + 1] = path end
            if path:match("/Locales/%a%a%u%u%.lua$") then menuLocales = menuLocales + 1 end
            assert(not path:find("_Options/", 1, true) and not path:find("_Assistant/", 1, true),
                "optional UI was added to startup")
        end
        assert(menuLocales == 12, client .. ": client locale restricted saved menu language")
        assert(bytes < (suffix == "Mainline" and 16000000 or 14000000),
            client .. ": startup source budget regressed")
        local perCatalog = locale == "xxXX" and 1 or 2
        assert(#aliases == perCatalog * (suffix == "Mainline" and 2 or 1),
            client .. ": wrong count of selected alias files for " .. locale)
        local base = (root == "." and "" or root .. "/") .. "MidnightSimpleUnitFrames/"
        assert(index[base .. "Game/Shared/Initialize.lua"] < index[base .. "Kernel/MSUF_Bootstrap.lua"],
            "client facts must precede Kernel")
        local resolver = assert(index[base .. "Auras3/MSUF_Auras3_AuraAliases.lua"])
        for _, path in ipairs(aliases) do assert(index[path] < resolver, "data loaded after resolver") end

        local expected = locale == "enGB" and "enUS" or locale == "ptPT" and "ptBR" or locale
        if suffix ~= "Mainline" and expected == "itIT" then expected = "enUS" end
        for _, path in ipairs(aliases) do
            local pack = assert(path:match("_AliasData_(%a+)%.lua$"))
            assert(pack == "Common" or pack == expected, client .. ": wrong locale partition")
        end

        -- Only inactive alias files may disappear; every other script retains
        -- the exact union order, including the final RuntimeContracts chunk.
        local at = 1
        for _, path in ipairs(all) do
            if index[path] then
                assert(selected[at] == path, "startup order changed for " .. path)
                at = at + 1
            else
                assert(path:find("/AliasData/", 1, true), "lost non-alias startup file: " .. path)
            end
        end
        assert(at == #selected + 1)

        _G.GetLocale = function() return locale end
        local function Execute(paths)
            local ns = { Client = { IsForever = client == "Forever" },
                LOCALE = locale == "deDE" and "enUS" or "deDE", MSUF_Auras3 = { AuraSpellIDAliases = {} } }
            for _, path in ipairs(paths) do
                if path:find("/AliasData/", 1, true) or path:find("/MSUF_Auras3_AuraAliases.lua", 1, true) then
                    assert(loadfile(path))("MidnightSimpleUnitFrames", ns)
                end
            end
            return ns.MSUF_Auras3
        end
        local previous, current = Execute(all), Execute(selected)
        for _, key in ipairs({ "build", "width", "locale", "common", "localized" }) do
            assert(previous.AuraAliasCatalog[key] == current.AuraAliasCatalog[key],
                client .. "/" .. locale .. ": catalog changed: " .. key)
        end
        -- Cast/aura drift, Classic ranks, cross-language collisions, unknown IDs.
        local ids = { [774] = true, [17] = true, [1022] = true, [115151] = true,
            [33763] = true, [185313] = true, [100] = true, [99999999] = true }
        previous.CompileCustomAuraAliases(ids)
        current.CompileCustomAuraAliases(ids)
        for id in pairs(ids) do
            local before, after = previous.AuraSpellIDAliases[id], current.AuraSpellIDAliases[id]
            assert((before == nil) == (after == nil), "alias presence changed")
            if before then
                assert(#before == #after, "alias count changed")
                for i = 1, #before do assert(before[i] == after[i], "alias member changed") end
            end
        end
        count = count + 1
        if locale == "deDE" then
            print(string.format("PASS %s deDE: %d Lua files, %.2f MB", client, #selected, bytes / 1000000))
        end
    end
end
print("PASS startup locale selection: " .. count .. " client/locale cases; exact catalogs, aliases, order and menu language")
