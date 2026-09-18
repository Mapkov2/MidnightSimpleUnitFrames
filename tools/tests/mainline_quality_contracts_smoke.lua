-- Contracts for the defects fixed after the 2026-09-18 code-quality review of
-- the Mainline build (Midnight and WoW Forever). Each block fails when its fix
-- is reverted. Usage: lua tools/tests/mainline_quality_contracts_smoke.lua <repoRoot>

local repo = assert(arg and arg[1], "usage: mainline_quality_contracts_smoke.lua <repoRoot>"):gsub("\\", "/")
local CORE = repo .. "/MidnightSimpleUnitFrames/"
local OPTIONS = repo .. "/MidnightSimpleUnitFrames_Options/"

local function Read(path)
    local handle = assert(io.open(path, "rb"), "missing source: " .. path)
    local body = handle:read("*a")
    handle:close()
    return (body:gsub("\r\n", "\n"))
end

-- Every contract runs even when an earlier one fails, so one run lists every
-- stale or reverted fix at once.
local failures = {}
local function Contract(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function FunctionBody(source, header, label)
    local start = source:find(header, 1, true)
    assert(start, label .. ": function header not found; update this contract")
    local finish = source:find("\nend\n", start, true)
    assert(finish, label .. ": function end not found; update this contract")
    return source:sub(start, finish)
end

-- 1. Every event the identity lifecycle forwards under its raw name resets the
--    cached power identity. Arena slots rebind under the same token, so a
--    missing name leaves a stale power type on a text-only frame.
Contract("identity lifecycle events", function()
    local core = Read(CORE .. "Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
    local lifecycle = FunctionBody(core, "local function AddIdentityLifecycleHandlers(frame)", "identity lifecycle")
    local runtime = Read(CORE .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")
    local identityTable = runtime:match("local POWER_IDENTITY_EVENTS = {(.-)\n}")
    assert(identityTable, "POWER_IDENTITY_EVENTS no longer parses; update this contract")
    local listed = {}
    for name in identityTable:gmatch("([%u_]+)%s*=%s*true") do listed[name] = true end
    local found = 0
    for event in lifecycle:gmatch('AddEventHandler%(frame,%s*"([%u_]+)"') do
        found = found + 1
        assert(listed[event] == true,
            event .. " is routed into the identity path but is missing from POWER_IDENTITY_EVENTS")
    end
    assert(found >= 7, "identity lifecycle handlers did not parse as expected (found " .. found .. ")")
    assert(listed.ARENA_OPPONENT_UPDATE == true, "ARENA_OPPONENT_UPDATE must reset the cached power identity")
end)

-- 2. Profile import asks the font registry through a function that exists.
Contract("font availability API", function()
    local profiles = Read(CORE .. "State/MSUF_Profiles.lua")
    local registry = Read(CORE .. "Runtime/MSUF_FontRegistry.lua")
    assert(not profiles:find("_G.MSUF_FontPathIsLoadable", 1, true),
        "MSUF_Profiles.lua reads MSUF_FontPathIsLoadable, which nothing defines")
    assert(profiles:find("_G.MSUF_IsAvailableFontPath", 1, true),
        "MSUF_Profiles.lua no longer asks MSUF_IsAvailableFontPath for imported font paths")
    assert(registry:find("G.MSUF_IsAvailableFontPath = MSUF_IsAvailableFontPath", 1, true),
        "MSUF_FontRegistry.lua no longer exports MSUF_IsAvailableFontPath")
end)

-- 3. Client model behaviour under fake globals.
Contract("client model", function()
    local chunk = assert(loadfile(CORE .. "Game/Shared/Initialize.lua"))
    local function Load(case)
        WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
        WOW_PROJECT_ID = case.project
        GetAddOnMetadata = nil
        C_AddOns = { GetAddOnMetadata = function(_, key)
            if key == "X-MSUF-Client" then return case.tag end
            if key == "Version" then return "6.5-test" end
            return nil
        end }
        GetBuildInfo = function() return "test", "test", "test", case.interface end
        issecretvalue = function() return false end
        CreateFrame = function()
            return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
        end
        C_EventUtils, C_GameRules, Enum, MAX_ARENA_ENEMIES = nil, nil, nil, nil
        C_PetInfo, C_PlayerInfo, Constants, UnitName = nil, nil, nil, nil
        GameEvent = case.gameEvent
        MSUF, MSUF_NS = nil, nil
        local namespace = {}
        chunk("MidnightSimpleUnitFrames", namespace)
        return namespace.Client
    end
    local marker = { RegisterCamelotEvents = function() error("the Forever marker must never be called") end }

    local midnight = Load({ project = 1, interface = 120105 })
    assert(midnight.IsForever == false and midnight.Diagnostic == nil, "Midnight: unexpected Forever flag or diagnostic")
    assert(midnight.HasEmpoweredCasts == true, "Midnight has Evokers: HasEmpoweredCasts must be true")
    assert(midnight.MaxArenaOpponents == 3 and midnight.SupportsUnit("arena3") == true, "Midnight arena facts changed")

    local forever = Load({ project = 1, interface = 16001, gameEvent = marker })
    assert(forever.IsForever == true and forever.Diagnostic == nil, "Forever: marker not honoured")
    assert(forever.HasEmpoweredCasts == false, "WoW Forever has no Evoker: HasEmpoweredCasts must be false")
    -- Owner-confirmed in game: EllesmereUI's Edit Mode works on WoW Forever too.
    assert(forever.SupportsEllesmereEditMode == true and midnight.SupportsEllesmereEditMode == true,
        "EllesmereUI Edit Mode support must be true on both Mainline-family clients")
    local markerLine
    for _, line in ipairs(forever.DescribeLines()) do
        if line:find("Forever marker", 1, true) then markerLine = line end
    end
    assert(markerLine and markerLine:find("Forever marker GameEvent.RegisterCamelotEvents at load true, now true", 1, true),
        "clientinfo marker line changed: " .. tostring(markerLine))

    -- A renamed marker must not fail silently: same behaviour as before, one login line.
    local renamed = Load({ project = 1, interface = 16001 })
    assert(renamed.IsForever == false and renamed.MaxArenaOpponents == 3,
        "a Mainline client without the marker must keep Midnight behaviour (detection never keys on the interface)")
    assert(type(renamed.Diagnostic) == "string"
        and renamed.Diagnostic:find("without the WoW Forever marker", 1, true)
        and renamed.Diagnostic:find("interface 16001", 1, true),
        "a Mainline client below the Midnight interface range without the marker must print a login diagnostic")

    local vanilla = Load({ project = 2, interface = 11509, tag = "Vanilla" })
    assert(vanilla.HasEmpoweredCasts == false, "Classic Era: HasEmpoweredCasts must be false")

    -- An unplaced client: the unit answer and the slot count must agree.
    local unknown = Load({ project = 20, interface = 11600 })
    assert(unknown.Flavor == "Unknown" and unknown.MaxArenaOpponents == 0, "Unknown client: slots")
    assert(unknown.SupportsUnit("arena1") == false and unknown.SupportsUnit("arena") == false,
        "Unknown client: arena units are supported although it has no arena slots")
    assert(unknown.SupportsUnit("player") == true and unknown.SupportsUnit("target") == true,
        "Unknown client: core units must stay supported")
end)

-- 4. A secret unit token is tested before anything compares it.
Contract("secret unit token order", function()
    local common = Read(CORE .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua")
    local body = FunctionBody(common, "local function PlainUnitIsPlayer(frame, unit)", "PlainUnitIsPlayer")
    local secretAt = body:find("issecretvalue(unit)", 1, true)
    local arenaAt = body:find("IsArenaOpponentUnit(unit)", 1, true)
    assert(secretAt and arenaAt and secretAt < arenaAt,
        "PlainUnitIsPlayer compares the unit token before the secret check")
end)

-- 5. Deleting a profile moves characters to a survivor that does not depend on pairs() order.
Contract("profile delete fallback", function()
    local profiles = Read(CORE .. "State/MSUF_Profiles.lua")
    local body = FunctionBody(profiles, "function MSUF_DeleteProfile(name)", "MSUF_DeleteProfile")
    assert(not body:find("fallbackName = fallbackName or profileName", 1, true),
        "MSUF_DeleteProfile picks its fallback profile by pairs() order")
    assert(body:find('type(profiles["Default"]) == "table"', 1, true) and body:find("profileName < fallbackName", 1, true),
        "MSUF_DeleteProfile must prefer Default, then the alphabetically first profile")
end)

-- 6. Arena slot count: no site may assume three opponents.
Contract("arena slot count", function()
    local anchors = Read(CORE .. "Castbars/MSUF_CastbarAnchors.lua")
    assert(not anchors:find('(unit == "arena" and 3)', 1, true),
        "MSUF_CastbarAnchors.lua hard-codes three arena castbars; TBC and Mists have five")
    local portrait = Read(CORE .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua")
    assert(not portrait:find("^arena[1-3]$", 1, true),
        "MSUF_UF_Elements_Portrait.lua drops the preview class portrait for arena4 and arena5")
end)

-- 7. Arena hot paths: no table per call, no re-anchor per lifecycle event.
Contract("arena hot paths", function()
    local castbars = Read(CORE .. "Castbars/MSUF_ArenaCastbars.lua")
    local body = FunctionBody(castbars, "local function ClearArenaCastbarFontAttempt(frame)", "ClearArenaCastbarFontAttempt")
    assert(not body:find("{", 1, true), "ClearArenaCastbarFontAttempt allocates a table per call")
    local trinkets = Read(CORE .. "Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua")
    local position = FunctionBody(trinkets, "local function PositionHolder(holder, index)", "PositionHolder")
    assert(position:find("holder._msufTrinketAnchor ~= frame", 1, true),
        "PositionHolder re-anchors the trinket holder on every event")
end)

-- 8. Menus read the capability, and the Forever pet-happiness keys are normalized.
Contract("capability menus and defaults", function()
    local castbarPage = Read(OPTIONS .. "Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
    assert(castbarPage:find("HasEmpoweredCasts", 1, true),
        "the Empowered Casts section must follow MSUF.Client.HasEmpoweredCasts (WoW Forever has no Evoker)")
    local defaults = Read(CORE .. "State/MSUF_Defaults.lua")
    assert(defaults:find('petHappinessSpec.statusPrefixes[#petHappinessSpec.statusPrefixes + 1] = "petHappinessIndicator"', 1, true)
        and defaults:find("MSUF.Client.SupportsPetHappiness == true then\n    local petHappinessSpec", 1, true),
        "the Mainline Defaults must normalize the pet-happiness status keys where the client supports them")
end)

-- 9. The Mana display source never assumes a Mana pool on a client without
--    UnitHasPowerType (no Classic branch of Blizzard's UI calls that function).
Contract("mana pool fallback", function()
    local config = Read(CORE .. "ClassPower/MSUF_CP_Controller_Config.lua")
    assert(not config:find("if not _G.UnitHasPowerType then return true end", 1, true),
        "a client without UnitHasPowerType is treated as having a Mana pool")
    assert(config:find('_G.UnitPowerMax("player", manaType)', 1, true),
        "the Mana pool check must ask UnitPowerMax when UnitHasPowerType is missing")
end)

if #failures > 0 then
    for i = 1, #failures do io.stderr:write("FAIL ", failures[i], "\n") end
    os.exit(1)
end
print("mainline quality contracts smoke: ok (9 contracts)")
