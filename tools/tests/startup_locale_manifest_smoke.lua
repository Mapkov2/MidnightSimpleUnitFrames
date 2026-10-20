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
        -- 2026-10-18: the Options group preview scene fits its container to the one frame it shows (Raid and Mythic
        -- Raid kept the cell at the corner of a whole group column, outside the preview), lays out the configured
        -- group count instead of reading the roster, and shifts its element levels through the base ElementLevel
        -- reads instead of an extra term in that live function: +1,115 LF bytes on every client (Mainline/ruRU
        -- 10,006,974 -> 10,008,089, TBC/ruRU 7,883,096 -> 7,884,211). Both ceilings rise by exactly that:
        -- Mainline 10,007,262 -> 10,008,377, Classic 7,892,434 -> 7,893,549.
        -- 2026-10-17: the static unit preview scenes (MSUF_UF_UnitScene.lua, the scene forms of the health, power,
        -- prediction, portrait, opacity, status and text elements, the shared aura lane painter) add 31,385 LF bytes to
        -- core startup on every client (Mainline/ruRU 10,008,089 -> 10,039,474, TBC/ruRU 7,884,211 -> 7,915,596) while the
        -- menu keeps drawing its own unit cell until it is switched over (Options code removed: none). Both ceilings
        -- rise by exactly that delta: Mainline 10,008,377 -> 10,039,762, Classic 7,893,549 -> 7,924,934.
        -- 2026-10-17: standalone castbar/ClassPower scenes reuse core builders and painters.
        -- LF startup: Mainline/ruRU 10,039,474 -> 10,069,019 (+29,545); TBC/ruRU
        -- 7,915,596 -> 7,943,322 (+27,726). These are the largest selections per ceiling.
        -- Ceilings rise by exactly those deltas: 10,039,762 -> 10,069,307 and
        -- 7,924,934 -> 7,952,660. Mists adds 27,914; its total is 7,914,755.
        -- 2026-10-18: scene collaborators bind at construction; live colour API exists at load.
        -- LF startup Mainline/ruRU 10,069,019 -> 10,073,781 (+4,762);
        -- TBC/ruRU 7,943,322 -> 7,948,487 (+5,165). Ceilings change by exactly those bytes:
        -- 10,069,307 -> 10,074,069; 7,952,660 -> 7,957,825. Runtime cost pins are unchanged.
        -- 2026-10-19: review cleanup uses the owner clock and removes duplicate combat tracking.
        -- LF startup Mainline/ruRU 10,073,781 -> 10,073,032 (-749);
        -- TBC/ruRU 7,948,487 -> 7,947,738 (-749). Mists drops 884 bytes.
        -- Both ceilings fall by exactly 749: 10,074,069 -> 10,073,320;
        -- 7,957,825 -> 7,957,076. Runtime cost pins are unchanged.
        -- 2026-10-18 (96b): Options paints its unit body through the engine scene; native sample/layer/style bridges
        -- add exactly 23,896 Mainline/Forever and 21,644 Classic LF source bytes, measured against 13a01081c.
        -- Mainline/ruRU 10,039,474 -> 10,063,370; TBC/ruRU 7,915,596 -> 7,937,240.
        -- Source ceilings move by exactly those deltas: Mainline 10,039,762 -> 10,063,658,
        -- Classic 7,924,934 -> 7,946,578. Live VM/native/heap and responsibility ceilings are unchanged.
        -- 2026-10-18 (96b review fixes): shared aura samples restore stealable markers and missing reminders.
        -- Measured core LF delta: +2446 on every client; Mainline/ruRU 10,063,370 -> 10,065,816,
        -- TBC/ruRU 7,937,240 -> 7,939,686. Ceilings add exactly that delta:
        -- Mainline 10,063,658 -> 10,066,104; Classic 7,946,578 -> 7,949,024.
        -- 2026-10-19: 96b stacked on 98 (independent core bytes, summed): Mainline +26,342, Classic +24,090;
        -- Mainline/ruRU 10,073,032 -> 10,099,374, TBC/ruRU 7,947,738 -> 7,971,828.
        -- Ceilings: Mainline 10,073,320 -> 10,099,662; Classic 7,957,076 -> 7,981,166.
        -- 2026-10-19: Edit Mode external X/Y steppers (+4,412) and their review fixes (+549) add 4,961
        -- LF bytes on every client: Mainline/ruRU 10,099,374 -> 10,104,335, TBC/ruRU 7,971,828 -> 7,976,789.
        -- Mainline ceiling 10,099,662 -> 10,104,623 (exact +4,961); the Classic ceiling 7,981,166 still fits.
        -- 2026-10-19 (98b): the Options castbar and class power previews paint through the engine scenes
        -- (castbar scene +874, class power scene +586, preview surfaces +573, empower blink +729 on Mainline only).
        -- Measured core LF delta: Mainline +2,762, Classic +2,033; Mainline/ruRU 10,104,462 -> 10,107,224,
        -- TBC/ruRU 7,976,916 -> 7,978,949. Ceilings add exactly that: Mainline 10,104,623 -> 10,107,385;
        -- Classic 7,981,166 -> 7,983,199.
        -- 2026-10-19: the Edit Mode toolbar keeps its Auras switch without the advanced menu (+150 LF
        -- bytes on every client); the Mainline ceiling 10,107,385 -> 10,107,535 (exact +150).
        -- 2026-10-19: the Options unit and group previews paint a health gradient / match-health background from the
        -- previewed health (scene form Health.PaintSampleBackground, the unit and group scene calls): +1,697 core LF bytes
        -- on every client, Mainline/ruRU 10,106,459 -> 10,108,156, TBC/ruRU 7,979,162 -> 7,980,859. Both ceilings add
        -- exactly that delta: Mainline 10,107,535 -> 10,109,232; Classic 7,983,199 -> 7,984,896. Live paths unchanged.
        -- 2026-10-20: lazy native Priority/Gameplay position popups and the shared menu setter add 7,692 LF bytes on
        -- every client: Mainline/ruRU 10,108,156 -> 10,115,848, TBC/ruRU 7,980,859 -> 7,988,551. Both ceilings add
        -- exactly that delta: Mainline 10,109,232 -> 10,116,924; Classic 7,984,896 -> 7,992,588.
        -- 2026-10-20 review fixes: focused position history sync and dependency binding cleanup add exactly
        -- 106 LF bytes on every client: Mainline/ruRU 10,116,544 -> 10,116,650;
        -- TBC/ruRU 7,989,247 -> 7,989,353. Both ceilings add exactly that delta:
        -- Mainline 10,116,924 -> 10,117,030; Classic 7,992,588 -> 7,992,694.
        assert(bytes < (suffix == "Mainline" and 10117030 or 7992694),
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
