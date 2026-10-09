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
-- WoW Forever shares the Mainline TOC; its game type (camelot) skips the Retail
-- catalog and keeps its own. Classic flavors ship no catalog at all: their
-- backend matches ranked and cast-versus-aura IDs by aura name at runtime.
local GAME_TYPES = { Mainline = "standard", Forever = "camelot" }
local CATALOGS = { Mainline = 2, Forever = 1, Vanilla = 0, TBC = 0, Mists = 0 }
for _, client in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local suffix = client == "Forever" and "Mainline" or client
    local all = Manifest.Paths(root, suffix)
    for _, locale in ipairs(locales) do
        local selected = Manifest.Paths(root, suffix, locale, GAME_TYPES[client])
        local bytes, aliases, menuLocales, index = 0, {}, 0, {}
        for i, path in ipairs(selected) do
            -- Counted with LF line ends: the shipped package holds the LF blobs,
            -- and a CRLF checkout (core.autocrlf) must not read as growth.
            bytes = bytes + #(Read(path):gsub("\r\n", "\n"))
            index[path] = i
            if path:find("/AliasData/", 1, true) then aliases[#aliases + 1] = path end
            if path:match("/Locales/%a%a%u%u%.lua$") then menuLocales = menuLocales + 1 end
            assert(not path:find("_Options/", 1, true), "optional UI was added to startup")
        end
        assert(menuLocales == 12, client .. ": client locale restricted saved menu language")
        -- A tripwire for large startup additions (a whole catalog or the Options
        -- addon), not for ordinary growth: every pack carries each new menu label.
        -- 2026-10-01: 16,000,000 -> 16,050,000 for the review fixes plus the
        -- restored options (largest selection koKR/standard 16,004,468).
        -- 2026-10-02: 16,050,000 -> 16,150,000 for the wave-2 quality splits
        -- (Edit Mode, engine and class power modules: file headers and imports)
        -- plus translated group and Edit Mode feedback; no catalog was added.
        -- 2026-10-02 (wave 4, W4-C2): 16,150,000 -> 16,200,000 and 14,000,000 ->
        -- 14,050,000 for about 49 KB of translations: the engine and state chat
        -- lines, key binding labels, unit tooltip and status words in the ten
        -- translated packs (every pack is parsed at startup); no catalog was added.
        -- 2026-10-03: bytes are counted with LF line ends (checkout-independent);
        -- the LF tree measured Mainline 15,979,430 and Vanilla 13,830,064.
        -- 2026-10-04: complete menu translations add about 503 KB across twelve
        -- packs; raise only this source-size tripwire by that translation budget.
        -- 2026-10-09 (rc1 E): 16,710,000 -> 16,770,000 and 14,560,000 ->
        -- 14,620,000 for about 54 KB of aura filter labels and tooltips in the
        -- twelve packs (largest selections Mainline 16,709,048, TBC 14,592,928);
        -- no catalog was added.
        -- 2026-10-09 (6.50 changelog): 16,770,000 -> 16,860,000 and 14,620,000 ->
        -- 14,710,000: the core's compact changelog (State/MSUF_Changelog.lua) now
        -- carries the full 6.5 notes with their menu links as the 6.50 entry,
        -- about 82 KB more (largest selections Mainline 16,807,225, TBC 14,690,089);
        -- no catalog was added.
        -- 2026-10-10 (6.50 arena PvP trinket): 16,860,000 -> 16,880,000 and
        -- 14,710,000 -> 14,730,000 for the trinket placement runtime, its preview and
        -- four menu strings in the twelve packs (about 12 KB); no catalog was added.
        assert(bytes < (suffix == "Mainline" and 16880000 or 14730000),
            client .. ": startup source budget regressed")
        local perCatalog = locale == "xxXX" and 1 or 2
        assert(#aliases == perCatalog * CATALOGS[client],
            client .. ": wrong count of selected alias files for " .. locale)
        local base = (root == "." and "" or root .. "/") .. "MidnightSimpleUnitFrames/"
        assert(index[base .. "Game/Shared/Initialize.lua"] < index[base .. "Kernel/MSUF_Bootstrap.lua"],
            "client facts must precede Kernel")
        local resolver = index[base .. "Auras3/MSUF_Auras3_AuraAliases.lua"]
        assert((resolver ~= nil) == (CATALOGS[client] > 0), client .. ": catalog resolver presence is wrong")
        for _, path in ipairs(aliases) do assert(index[path] < resolver, "data loaded after resolver") end
        if client == "Forever" then
            for _, path in ipairs(aliases) do
                assert(path:find("/Game/Forever/Auras/AliasData/", 1, true),
                    "WoW Forever must not parse the Retail catalog: " .. path)
            end
        end

        local expected = locale == "enGB" and "enUS" or locale == "ptPT" and "ptBR" or locale
        for _, path in ipairs(aliases) do
            local pack = assert(path:match("_AliasData_(%a+)%.lua$"))
            assert(pack == "Common" or pack == expected, client .. ": wrong locale partition")
        end

        -- Only inactive alias files and, outside WoW Forever, its gamepad files
        -- ([AllowLoadGameType camelot]) may disappear; every other script retains
        -- the exact union order, including the final RuntimeContracts chunk.
        local at = 1
        for _, path in ipairs(all) do
            if index[path] then
                assert(selected[at] == path, "startup order changed for " .. path)
                at = at + 1
            else
                assert(path:find("/AliasData/", 1, true)
                    or (GAME_TYPES[client] ~= "camelot" and path:find("/Game/Forever/Pad", 1, true)),
                    "lost non-alias startup file: " .. path)
            end
        end
        assert(at == #selected + 1)

        -- The selection must resolve exactly what executing every branch did:
        -- on Forever the unconditioned run ends on the Forever catalog too,
        -- because its files replace the Retail one.
        if CATALOGS[client] > 0 then
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
            -- Cast/aura drift, ranks, cross-language collisions, unknown IDs.
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
        end
        count = count + 1
        if locale == "deDE" then
            print(string.format("PASS %s deDE: %d Lua files, %.2f MB", client, #selected, bytes / 1000000))
        end
    end
end

-- WoW Forever's game type while the Forever marker is not recognized (renamed at
-- launch, Client.IsForever false): the TOC skips the Retail catalog and every
-- Forever catalog file returns early, so no catalog exists. The resolver must
-- still load and resolve nothing; before, it raised at load and every enabled
-- custom container then called the missing A3.CompileCustomAuraAliases.
do
    _G.GetLocale = function() return "enUS" end
    local ns = { Client = { IsForever = false }, MSUF_Auras3 = { AuraSpellIDAliases = {} } }
    local resolverLoaded = false
    for _, path in ipairs(Manifest.Paths(root, "Mainline", "enUS", "camelot")) do
        local resolver = path:find("/MSUF_Auras3_AuraAliases.lua", 1, true) ~= nil
        if resolver or path:find("/AliasData/", 1, true) then
            local ok, err = pcall(assert(loadfile(path)), "MidnightSimpleUnitFrames", ns)
            assert(ok, "camelot without the Forever marker: " .. path .. " raised " .. tostring(err))
            resolverLoaded = resolverLoaded or resolver
        end
    end
    local A3 = ns.MSUF_Auras3
    assert(resolverLoaded and A3.AuraAliasCatalog == nil,
        "precondition: the unrecognized camelot client did not end without a catalog")
    assert(type(A3.CompileCustomAuraAliases) == "function",
        "camelot without the Forever marker: the alias resolver is missing")
    A3.CompileCustomAuraAliases({ [774] = true, [17] = true })
    assert(next(A3.AuraSpellIDAliases) == nil, "the alias resolver invented aliases without a catalog")
    count = count + 1
end
print("PASS startup locale selection: " .. count .. " client/locale cases; exact catalogs, aliases, order and menu language")
