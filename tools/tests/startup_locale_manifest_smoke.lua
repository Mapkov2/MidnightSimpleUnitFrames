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
        local bytes, aliases, index = 0, {}, {}
        for i, path in ipairs(selected) do
            -- Counted with LF line ends: the shipped package holds the LF blobs,
            -- and a CRLF checkout (core.autocrlf) must not read as growth.
            bytes = bytes + #(Read(path):gsub("\r\n", "\n"))
            index[path] = i
            if path:find("/AliasData/", 1, true) then aliases[#aliases + 1] = path end
            assert(not path:find("_Options/", 1, true), "optional UI was added to startup")
        end
        local companion = Manifest.Paths(root, suffix, nil, nil, "MidnightSimpleUnitFrames_Locales")
        local available = {}
        for _, path in ipairs(companion) do
            local pack = assert(path:match("/Locales/(%a%a%u%u)%.lua$"), "companion contains non-pack code")
            assert(not available[pack], "duplicate companion pack")
            available[pack] = true
        end
        local menuLocales = 0
        for _ in pairs(available) do menuLocales = menuLocales + 1 end
        assert(menuLocales == 12, client .. ": companion restricted saved menu language")
        local expectedPack = locale == "ptPT" and "enUS" or locale
        local startupPacks = 0
        for _, path in ipairs(selected) do
            local pack = path:match("/Locales/(%a%a%u%u)%.lua$")
            if pack then
                assert(pack == expectedPack or (locale == "enGB" and pack == "enUS"), "inactive menu pack parsed")
                startupPacks = startupPacks + 1
            end
        end
        assert(startupPacks == (locale == "xxXX" and 0 or locale == "enGB" and 2 or 1), "wrong startup pack count")
        -- 2026-10-14: locale-selective core TOCs replace the temporary all-pack
        -- allowances. Measured worst LF selections: Mainline/ruRU 9,820,168,
        -- Forever/ruRU 9,460,798, TBC/ruRU 7,707,589. About 30 KB headroom.
        -- The companion's twelve packs remain available for saved menu choices.
        -- 2026-10-14: shared History/Apply execution adds 113,478 core LF
        -- bytes on every client (f8202558); ceilings add 116,000,
        -- under relocation + 5 KB. The enUS Edit Mode session drops from
        -- 17,009,067 to 9,444,283 Mainline; TBC 14,725,840 to 7,338,657.
        -- Core-only gesture/late-UI smoke proves no Options request or parse.
        -- 2026-10-16: the group import compatibility fix adds 8,598 LF bytes to the
        -- worst (ruRU) selection of every client: Mainline 9,965,909 -> 9,974,507,
        -- TBC 7,842,031 -> 7,850,629. Cold import confirmation and format
        -- handling, reset safety and four translated keys in twelve packs. Only the
        -- Mainline ceiling rises, by that exact delta; the Classic selection still
        -- fits its existing ceiling. No Options code, startup catalog or
        -- runtime-cost budget changed.
        -- 2026-10-16: the shared mock aura painter (Auras3/MSUF_Auras3_MockAuraPainter.lua) moves the
        -- Edit Mode, group and menu aura preview painting into one core module and removes it from
        -- five copies; it adds 1,983 LF bytes to core startup on every client (Mainline/ruRU
        -- 9,973,605 -> 9,975,588) while the Options addon shrinks by 323 lines. The Mainline
        -- ceiling rises by exactly that, 9,974,598 -> 9,976,581; the Classic ceiling is unchanged.
        -- 2026-10-16: legacy group filter tables read as 6.21 did; the import confirmation, its
        -- format stamp and its four translated keys are retired. That frees 5,753 LF bytes in the
        -- worst (ruRU) selection of every client: Mainline 9,975,537 -> 9,969,784, TBC 7,851,659
        -- -> 7,845,906. The Mainline ceiling falls by exactly that, 9,976,581 -> 9,970,828; the
        -- Classic ceiling never rose for the confirmation and is unchanged.
        -- 2026-10-16: the preview kit (MSUF_UF_PreviewKit.lua: host lifecycle and pools) and the isolated,
        -- static group preview scenes (GF.NewPreviewScene: per-scene pool, kit-hosted root, the scene apply
        -- UF.ApplySceneSpec and the elements' SceneApply forms) add 25,997 LF bytes to core startup on every client (Mainline/ruRU
        -- 9,970,540 -> 9,996,537, TBC/ruRU 7,846,662 -> 7,872,659) while the menu keeps drawing its own
        -- group cell until it is switched over (Options code removed: none). Both ceilings rise by exactly that
        -- delta: Mainline 9,970,828 -> 9,996,825, Classic 7,856,000 -> 7,881,997.
        -- 2026-10-17: the Options group preview paints its cell with an embedded scene (Scene:Configure with SetScale,
        -- SetLevel, SetSample, SetBodyOnly and ignoreOocFade, SetClock, Layers.SetLevelBias, the sample prediction,
        -- reduced max health and absorb text paints, the pinned sample class) and drops its own mock-cell renderer.
        -- Measured as this smoke counts (LF bytes, worst locale ruRU): +10,437 on every client, Mainline 9,996,537 ->
        -- 10,006,974 and TBC 7,872,659 -> 7,883,096. The Options addon loses MSUF_Menu2_GroupPreview_Rounded.lua and
        -- about 1,300 net lines, which do not count toward core startup. Both ceilings rise by exactly the measured
        -- delta: Mainline 9,996,825 -> 10,007,262, Classic 7,881,997 -> 7,892,434.
        assert(bytes < (suffix == "Mainline" and 10007262 or 7892434),
            client .. ": startup source budget regressed")
        local perCatalog = locale == "xxXX" and 1 or 2
        assert(#aliases == perCatalog * CATALOGS[client] + (client == "Forever" and locale ~= "xxXX" and 1 or 0),
            client .. ": wrong count of selected alias files for " .. locale)
        local base = (root == "." and "" or root .. "/") .. "MidnightSimpleUnitFrames/"
        assert(index[base .. "Game/Shared/Initialize.lua"] < index[base .. "Kernel/MSUF_Bootstrap.lua"],
            "client facts must precede Kernel")
        local resolver = index[base .. "Auras3/MSUF_Auras3_AuraAliases.lua"]
        assert((resolver ~= nil) == (CATALOGS[client] > 0), client .. ": catalog resolver presence is wrong")
        for _, path in ipairs(aliases) do assert(index[path] < resolver, "data loaded after resolver") end
        -- The locale-gated Retail partition also parses on camelot: its Lua
        -- guard returns before touching the Forever catalog (first condition only).

        local expected = locale == "enGB" and "enUS" or locale == "ptPT" and "ptBR" or locale
        for _, path in ipairs(aliases) do
            local pack = assert(path:match("_AliasData_(%a+)%.lua$"))
            assert(pack == "Common" or pack == expected, client .. ": wrong locale partition")
        end

        -- Only inactive alias/menu packs and, outside WoW Forever, gamepad files
        -- ([AllowLoadGameType camelot]) may disappear; every other script retains
        -- the exact union order, including the final RuntimeContracts chunk.
        local at = 1
        for _, path in ipairs(all) do
            if index[path] then
                assert(selected[at] == path, "startup order changed for " .. path)
                at = at + 1
            else
                assert(path:match("/Locales/%a%a%u%u%.lua$")
                    or path:find("/AliasData/", 1, true)
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
