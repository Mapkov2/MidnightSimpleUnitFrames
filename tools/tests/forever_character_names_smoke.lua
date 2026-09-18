-- WoW Forever character names smoke.
--
--   lua tools/tests/forever_character_names_smoke.lua <repo root>
--
-- Forever characters carry a surname. Blizzard's Camelot NameUtil reads it from
-- UnitName's second return; with regional unique names the first return can hold
-- both parts. The Fonts page (Name Shortening) offers Full name, First name and
-- Surname for every unit and group frame (general.characterNameParts).
--
-- The separator and every name below are test values: Blizzard's separator
-- constant is not part of the UI source, and the module must never assume one.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"
local MODULE = "Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

---------------------------------------------------------------------------
-- Secret values: opaque tables. String functions raise on them, and a join is
-- only possible through the concat metamethod or the WrapString stub.
---------------------------------------------------------------------------
local secretMeta = {}
local function Secret(text)
    return setmetatable({ secret = true, text = text }, secretMeta)
end
secretMeta.__concat = function(left, right)
    local function Plain(value) return type(value) == "table" and value.text or value end
    return Secret(Plain(left) .. Plain(right))
end

local function LoadClient(isForever, namespace)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_ID = 1, 1
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", isForever and 16001 or 120105 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.GameEvent = isForever and { RegisterCamelotEvents = function() end } or nil
    _G.MSUF, _G.MSUF_NS = nil, nil
    namespace = namespace or {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace.Client, namespace
end

Check(LoadClient(true).HasCharacterSurnames == true, "Forever must report character surnames")
Check(LoadClient(false).HasCharacterSurnames == false, "Midnight must not report character surnames")

---------------------------------------------------------------------------
-- Harness: the real module against a recording text runtime
---------------------------------------------------------------------------
local function Harness(options)
    options = options or {}
    local harness = { units = {}, installs = 0, players = {}, calls = { name = 0, player = 0, regional = 0, cached = 0 } }
    local _, namespace = LoadClient(options.midnight ~= true)
    _G.MSUF_DB = { general = {} }
    _G.Constants = options.noSeparator and {} or {
        CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = options.separator or "^" },
    }
    _G.RegionalUniqueNamesEnabled = function()
        harness.calls.regional = harness.calls.regional + 1
        return options.regional == true
    end
    _G.C_StringUtil = options.noWrapString and {} or {
        WrapString = function(infix, prefix, suffix)
            local text = type(infix) == "table" and infix.text or infix
            if text == "" then return "" end
            harness.wrapped = (harness.wrapped or 0) + 1
            return Secret((prefix or "") .. text .. (suffix or ""))
        end,
    }
    _G.InCombatLockdown = function() return harness.inCombat == true end
    local text = {
        UnitName = function(unit)
            harness.calls.name = harness.calls.name + 1
            local entry = harness.units[unit]
            if not entry then return nil end
            return entry[1], entry[2]
        end,
        UnitIsPlayer = function(unit)
            harness.calls.player = harness.calls.player + 1
            local value = harness.players[unit]
            if value == nil then return false end
            return value
        end,
    }
    function text.SetDisplayNameResolver(resolver)
        harness.installs = harness.installs + 1
        harness.installed = resolver
    end
    harness.originalSetter = text.SetDisplayNameResolver
    namespace.UFText = text
    if options.cachedPlayerFlag then
        -- The engine's identity cache: (isPlayer, known).
        namespace.UF = { ReadUnitIsPlayerCached = function(frame, unit)
            Check(type(frame) == "table", "the cached player flag needs the frame")
            harness.calls.cached = harness.calls.cached + 1
            local value = harness.players[unit]
            if value == nil then return nil, false end
            return value, true
        end }
    end
    assert(loadfile(core .. MODULE))("MidnightSimpleUnitFrames", namespace)
    harness.namespace, harness.text = namespace, text
    function harness.Show(unit, mode)
        _G.MSUF_DB.general.characterNameParts = mode
        return harness.installed(unit, {})
    end
    return harness
end

-- Midnight: the file returns at once.
do
    local h = Harness({ midnight = true })
    Check(h.installs == 0 and h.installed == nil, "Midnight: a display name resolver was installed")
    Check(h.text.SetDisplayNameResolver == h.originalSetter, "Midnight: the resolver slot was wrapped")
    Check(h.namespace.CharacterNames == nil, "Midnight: the character names module registered itself")
end

local function Plain(value)
    if type(value) == "table" then return "secret:" .. tostring(value.text) end
    return value
end

local function Expect(h, unit, full, first, surname, label)
    Check(Plain(h.Show(unit, nil)) == full, label .. ": full name gave " .. tostring(Plain(h.Show(unit, nil))))
    Check(Plain(h.Show(unit, "FULL")) == full, label .. ": FULL gave " .. tostring(Plain(h.Show(unit, "FULL"))))
    Check(Plain(h.Show(unit, "FIRST")) == first, label .. ": FIRST gave " .. tostring(Plain(h.Show(unit, "FIRST"))))
    Check(Plain(h.Show(unit, "SURNAME")) == surname,
        label .. ": SURNAME gave " .. tostring(Plain(h.Show(unit, "SURNAME"))))
    -- An unknown stored value behaves like the default.
    Check(Plain(h.Show(unit, "BOGUS")) == full, label .. ": an unknown mode must show the full name")
end

-- Surname as UnitName's second return (Blizzard's Camelot NameUtil).
do
    local h = Harness()
    Check(h.installs == 1 and type(h.installed) == "function", "Forever: the resolver must be installed exactly once")
    h.units.target = { "Anna", "Stone" }
    Expect(h, "target", "Anna^Stone", "Anna", "Stone", "separate surname")
    h.units.target = { "Defias Pillager", nil }
    Expect(h, "target", "Defias Pillager", "Defias Pillager", "Defias Pillager", "NPC without surname")
    h.units.target = { "Anna", "" }
    Expect(h, "target", "Anna", "Anna", "Anna", "empty surname")
    h.units.target = nil
    Check(h.Show("target", "SURNAME") == nil, "a missing unit must stay nil")
    -- The first return already ends with the surname: never print it twice.
    h.units.target = { "Anna^Stone", "Stone" }
    Expect(h, "target", "Anna^Stone", "Anna", "Stone", "surname in both returns")
end

-- Regional unique names: both parts arrive in the first return.
do
    local h = Harness({ regional = true })
    h.units.party1, h.players.party1 = { "Anna^Stone", nil }, true
    Expect(h, "party1", "Anna^Stone", "Anna", "Stone", "merged player name")
    -- Only the first separator splits, and an edge separator splits nothing.
    h.units.party1 = { "Anna^Stone^Hill", nil }
    Expect(h, "party1", "Anna^Stone^Hill", "Anna", "Stone^Hill", "two separators")
    h.units.party1 = { "^Stone", nil }
    Expect(h, "party1", "^Stone", "^Stone", "^Stone", "leading separator")
    h.units.party1 = { "Anna^", nil }
    Expect(h, "party1", "Anna^", "Anna^", "Anna^", "trailing separator")
    -- An NPC name that happens to contain the separator is never split.
    h.units.target, h.players.target = { "Guard^Captain", nil }, false
    Expect(h, "target", "Guard^Captain", "Guard^Captain", "Guard^Captain", "NPC with separator")
    h.players.target = Secret(true)
    Expect(h, "target", "Guard^Captain", "Guard^Captain", "Guard^Captain", "secret player flag")

    local off = Harness({ regional = false })
    off.units.party1, off.players.party1 = { "Anna^Stone", nil }, true
    Expect(off, "party1", "Anna^Stone", "Anna^Stone", "Anna^Stone", "regional unique names off")
end

-- The separator is plain text, whatever characters Blizzard picked.
for _, separator in ipairs({ "-", ".", " ", "%", "[" }) do
    local h = Harness({ regional = true, separator = separator })
    h.units.party1, h.players.party1 = { "Anna" .. separator .. "Stone", nil }, true
    Expect(h, "party1", "Anna" .. separator .. "Stone", "Anna", "Stone", "separator '" .. separator .. "'")
    h.units.party2 = { "Bert", "Hill" }
    Expect(h, "party2", "Bert" .. separator .. "Hill", "Bert", "Hill", "joined with '" .. separator .. "'")
end

-- Without Blizzard's constant nothing is assumed: no join and no split.
do
    local h = Harness({ regional = true, noSeparator = true })
    h.units.party1, h.players.party1 = { "Anna", "Stone" }, true
    Expect(h, "party1", "Anna", "Anna", "Stone", "no separator constant, separate surname")
    h.units.party1 = { "Anna^Stone", nil }
    Expect(h, "party1", "Anna^Stone", "Anna^Stone", "Anna^Stone", "no separator constant, merged name")
end

-- Secret names: never searched or compared; a part that cannot be proven keeps
-- the whole name instead of an empty one.
do
    local h = Harness({ regional = true })
    h.players.target = true
    h.units.target = { Secret("Anna"), Secret("Stone") }
    Expect(h, "target", "secret:Anna^Stone", "secret:Anna", "secret:Anna^Stone", "secret name and surname")
    Check((h.wrapped or 0) > 0, "a secret surname must be joined through C_StringUtil.WrapString")
    h.units.target = { Secret("Defias Pillager"), Secret("") }
    Expect(h, "target", "secret:Defias Pillager", "secret:Defias Pillager", "secret:Defias Pillager", "secret empty surname")
    h.units.target = { Secret("Anna"), nil }
    Expect(h, "target", "secret:Anna", "secret:Anna", "secret:Anna", "secret name without surname")
    h.units.target = { Secret("Anna"), "Stone" }
    Expect(h, "target", "secret:Anna^Stone", "secret:Anna", "Stone", "secret name with a plain surname")
    h.units.target = { Secret("Anna^Stone"), nil }
    Expect(h, "target", "secret:Anna^Stone", "secret:Anna^Stone", "secret:Anna^Stone", "secret merged name stays whole")

    local bare = Harness({ noWrapString = true })
    bare.units.target = { Secret("Anna"), Secret("Stone") }
    Expect(bare, "target", "secret:Anna", "secret:Anna", "secret:Anna", "secret surname without WrapString")
end

-- The beta's own facts (build 1.60.1.69913): regional unique names on, the
-- separator is a space, and UnitName has no second return. NPC names are full of
-- spaces, so only the player check keeps them whole.
do
    local h = Harness({ regional = true, separator = " " })
    h.units.target, h.players.target = { "Anna Stone", nil }, true
    Expect(h, "target", "Anna Stone", "Anna", "Stone", "beta player name")
    h.units.target = { "Anna von Stone", nil }
    Expect(h, "target", "Anna von Stone", "Anna", "von Stone", "beta surname with a space")
    h.units.target, h.players.target = { "Kobold Vermin", nil }, false
    Expect(h, "target", "Kobold Vermin", "Kobold Vermin", "Kobold Vermin", "beta NPC name")
    h.units.pet, h.players.pet = { "Old Blue", nil }, false
    Expect(h, "pet", "Old Blue", "Old Blue", "Old Blue", "beta pet name")
end

-- Cost contract. Name reads are event-driven, and each read does no more than its
-- case needs: the default asks nothing, a one-word name asks no unit API, the
-- player check reuses the engine's cached identity, and the realm's naming
-- policy is asked once.
do
    local h = Harness({ regional = true, separator = " ", cachedPlayerFlag = true })
    local function Reset() for key in pairs(h.calls) do h.calls[key] = 0 end end
    h.units.party1, h.players.party1 = { "Anna Stone", nil }, true
    h.units.party2, h.players.party2 = { "Bert", nil }, true

    Reset()
    for _ = 1, 25 do Check(h.Show("party1", nil) == "Anna Stone", "cost: full name") end
    Check(h.calls.name == 25 and h.calls.player == 0 and h.calls.cached == 0 and h.calls.regional == 0,
        "cost: the default must read the name once and ask nothing else")

    Reset()
    for _ = 1, 25 do Check(h.Show("party2", "FIRST") == "Bert", "cost: one-word name") end
    Check(h.calls.name == 25 and h.calls.player == 0 and h.calls.cached == 0 and h.calls.regional == 0,
        "cost: a name without the separator must not ask a unit API")

    Reset()
    for _ = 1, 25 do Check(h.Show("party1", "SURNAME") == "Stone", "cost: split name") end
    Check(h.calls.name == 25 and h.calls.cached == 25 and h.calls.player == 0,
        "cost: the split must reuse the engine's cached player flag, never UnitIsPlayer")
    Check(h.calls.regional == 1, "cost: the realm's naming policy must be asked once, got " .. h.calls.regional)

    -- An identity the engine has not read yet is not a player yet: nothing is cut.
    h.units.party3 = { "Cara Hill", nil }
    Check(h.Show("party3", "FIRST") == "Cara Hill", "an unknown player flag must keep the whole name")

    -- A policy that answers "off" is asked again, so a too-early answer cannot stick.
    local off = Harness({ regional = false, separator = " " })
    off.units.party1, off.players.party1 = { "Anna Stone", nil }, true
    for _ = 1, 3 do Check(off.Show("party1", "FIRST") == "Anna Stone", "policy off: no split") end
    Check(off.calls.regional == 3, "an 'off' answer must not be cached")
end

-- The nickname integration shares the resolver slot: a nickname wins, every
-- other name still follows the option, and the slot is never handed over.
do
    local h = Harness()
    h.units.party1, h.units.party2 = { "Anna", "Stone" }, { "Bert", "Hill" }
    local nicknames = { party1 = "Annie" }
    h.text.SetDisplayNameResolver(function(unit, frame)
        Check(type(frame) == "table", "the nickname resolver must still receive the frame")
        return nicknames[unit] or (h.text.UnitName(unit))
    end)
    Check(h.installs == 1, "the nickname integration must not replace the installed resolver")
    Check(h.Show("party1", "SURNAME") == "Annie", "a nickname must replace the whole name")
    Check(h.Show("party2", "SURNAME") == "Hill" and h.Show("party2", nil) == "Bert^Hill",
        "names without a nickname must follow the option")
    h.units.party1 = { Secret("Anna"), Secret("Stone") }
    nicknames.party1 = nil
    Check(Plain(h.Show("party1", "FIRST")) == "secret:Anna", "a secret name must pass the nickname resolver untouched")
    h.text.SetDisplayNameResolver(nil)
    h.units.party1 = { "Anna", "Stone" }
    Check(h.Show("party1", "FIRST") == "Anna" and h.installs == 1, "removing the nickname resolver must keep the option")
end

-- Refresh re-reads unit frame names, inline names and group frame names.
do
    local h = Harness()
    local calls, groupRefreshes = {}, 0
    local frames = {
        { MSUFUnitKey = "target", _msufActiveElements = { NameText = true, Text = true } },
        { MSUFUnitKey = "pet", _msufActiveElements = { NameText = true } },
        { MSUFUnitKey = "focus" },
    }
    h.namespace.UF = { ForEachFrame = function(fn, a) for _, frame in ipairs(frames) do fn(frame, nil, a) end end }
    h.namespace.UFTextRuntime = {
        UpdateName = function(frame, reason, unit) calls[#calls + 1] = "name:" .. unit .. ":" .. reason end,
        UpdateInline = function(frame, reason) calls[#calls + 1] = "inline:" .. frame.MSUFUnitKey .. ":" .. reason end,
    }
    h.namespace.GF = { RefreshGroupNames = function(unit)
        Check(unit == nil, "every group name must refresh")
        groupRefreshes = groupRefreshes + 1
    end }
    h.inCombat = true
    Check(h.namespace.CharacterNames.Refresh() == false and #calls == 0 and groupRefreshes == 0,
        "Refresh must do nothing in combat")
    h.inCombat = false
    Check(h.namespace.CharacterNames.Refresh() == true, "Refresh must report success out of combat")
    Check(table.concat(calls, " ") == "name:target:MSUF_CHARACTER_NAMES inline:target:MSUF_CHARACTER_NAMES "
        .. "name:pet:MSUF_CHARACTER_NAMES" and groupRefreshes == 1, "Refresh touched the wrong frames: " .. table.concat(calls, " "))
end

---------------------------------------------------------------------------
-- Contracts with the Retail files this module relies on
---------------------------------------------------------------------------
do
    local runtime = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")
    for _, line in ipairs({
        "function Text.SetDisplayNameResolver(resolver)",
        "    ReadDisplayName = resolver\n    displayNameResolverUsesFrame = true",
        "    displayName = ReadDisplayName(unit, frame)",
        "    name = ReadDisplayName(inlineUnit, frame)",
    }) do
        Check(runtime:find(line, 1, true), "the unit text runtime no longer has: " .. line)
    end
    local nicknames = Read("MidnightSimpleUnitFrames/Integrations/MSUF_Integration_NicknameProviders.lua")
    Check(nicknames:find('  if type(Text.SetDisplayNameResolver) == "function" then\n    Text.SetDisplayNameResolver(resolver)', 1, true),
        "the nickname integration must look the resolver setter up when it installs")

    -- Load order: after the unit text runtime, before the nickname integration.
    local manifest = Read("MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
    local runtimeAt = Check(manifest:find("Engine\\Elements\\MSUF_UF_Text_Runtime.lua", 1, true), "manifest lost the text runtime")
    local moduleAt = Check(manifest:find("Game\\Forever\\UnitFrames\\MSUF_UF_CharacterNames.lua", 1, true),
        "the Mainline manifest must load the character names module")
    Check(runtimeAt < moduleAt, "the character names module must load after the unit text runtime")
    Check(manifest:find('Auras3\\MSUF_Auras3_IconShape.lua"/>', 1, true) < moduleAt,
        "a Mainline-only script must load behind the shared element prefix")
    local toc = Read("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc")
    Check(toc:find("MSUF_UFCore_Elements.xml", 1, true) < toc:find("MSUF_Integration_NicknameProviders.lua", 1, true),
        "the nickname integration must load after the element manifest")
    for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
        Check(not Read("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml"):find("CharacterNames", 1, true),
            flavor .. " must not load the character names module")
    end
end

---------------------------------------------------------------------------
-- Menu: one Forever-only control, reset, search keywords and locales
---------------------------------------------------------------------------
do
    local fonts = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
    for _, line in ipairs({
        "if MSUF.Client ~= nil and MSUF.Client.HasCharacterSurnames == true then\n    CharacterNameParts = {",
        '        values = VT("FULL", "Full name", "FIRST", "First name", "SURNAME", "Surname"),',
        '            G().characterNameParts = (value == "FIRST" or value == "SURNAME") and value or nil',
        '        resolved.settingKey = resolved.settingKey or "general.characterNameParts"',
        '        if CharacterNameParts then\n            controls.nameParts = W.Segment(parent, "Character names (all frames)", CharacterNameParts.values, 430)',
        "            288 + (CharacterNameParts and CharacterNameParts.rowHeight or 0), true)",
        "            294 + (CharacterNameParts and CharacterNameParts.rowHeight or 0), true)",
    }) do
        Check(fonts:find(line, 1, true), "the Fonts page no longer has: " .. line)
    end
    Check(Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings_Reset.lua")
        :find("nameColorB characterNameParts\"", 1, true), "the Fonts page reset must clear characterNameParts")

    local function Keywords(isForever)
        local main = { Client = LoadClient(isForever), MSUF2 = {} }
        assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        return main.MSUF2.SearchData.KEYWORDS
    end
    local forever, midnight = Keywords(true), Keywords(false)
    Check(forever.opt_fonts:find(" surname ", 1, true) and forever.opt_fonts:find(" first name ", 1, true),
        "Forever: the Fonts page search keywords lack the character name words")
    Check(not midnight.opt_fonts:find("surname", 1, true), "Midnight: the Fonts page search keywords gained surnames")
    Check(forever.opt_fonts:sub(1, #midnight.opt_fonts) == midnight.opt_fonts,
        "Forever: the Fonts page keywords must only append to the Midnight text")

    local labels = { "Character names (all frames)", "Full name", "First name", "Surname" }
    for _, locale in ipairs({ "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local source = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
        for _, label in ipairs(labels) do
            local value = source:match('\nL%["' .. label:gsub("[%(%)]", "%%%0") .. '"%] = "([^"\n]+)"\n')
            Check(value and value ~= "", locale .. " lacks the label: " .. label)
        end
    end
end

print("forever_character_names_smoke: ok")
