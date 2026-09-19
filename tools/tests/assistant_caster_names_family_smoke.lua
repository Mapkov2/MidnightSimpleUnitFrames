-- assistant_caster_names_family_smoke.lua
-- Aura Tooltip Caster Names drives a Mainline-only game option. The Global /
-- Misc menu page offers the switch when MSUF.Client.Family is "Mainline"
-- (IS_MAINLINE in Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua), and the
-- Assistant must register its setting under exactly that answer, never from the
-- raw project ID: WoW Forever keeps Family Mainline whatever project ID it
-- reports, and a Classic TOC tag places a Classic client whatever project ID it
-- reports.
--
-- Each client runs in its own client_world sandbox: the real
-- Game/Shared/Initialize.lua builds the client model, the real Assistant
-- namespace bootstrap links the Assistant's own table to the core namespace the
-- way the LoadOnDemand addon gets it, and the real
-- MSUF_AssistantRegistry_Global_BaseSettings.lua registers into recorders.
-- Every case also evaluates the menu's IS_MAINLINE expression, read from the
-- page source, against the same client, so the two answers cannot drift apart.
-- Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local CORE_INIT = root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"
local ASSISTANT = root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/"
local MENU_PAGE = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua"
local SETTING = "tooltipShowAuraCasterNames"

-- The menu's decision, taken from its source line so a change there is seen here.
local menuSource = World.Read(root .. "/" .. MENU_PAGE)
local menuExpression = menuSource:match("\nlocal IS_MAINLINE = ([^\n]+)\n")
Check(menuExpression, MENU_PAGE .. " no longer defines IS_MAINLINE on one line")
Check(not menuExpression:find("WOW_PROJECT", 1, true), MENU_PAGE .. " IS_MAINLINE reads a raw project global")
local MenuOffers = assert(loadstring("local MSUF = ...\nreturn " .. menuExpression, "@IS_MAINLINE"))

-- options.projectGlobal: the project the client reports instead of its matrix
-- row's. options.bare: no client model at all (the headless harness case).
local function Register(flavor, options)
    options = options or {}
    local world = World.New(root, flavor)
    if options.projectGlobal then
        world.env.WOW_PROJECT_ID = assert(World.ProjectIDValues[options.projectGlobal], options.projectGlobal)
    end
    -- The Assistant's own addon table, as the LoadOnDemand addon receives it.
    local main, private = {}, {}
    local ok, message
    if not options.bare then
        ok, message = world:LoadFile(CORE_INIT, "MidnightSimpleUnitFrames", main)
        Check(ok, flavor .. ": Game/Shared/Initialize.lua failed: " .. tostring(message))
        Check(type(main.Client) == "table", flavor .. ": no client model")
        ok, message = world:LoadFile(ASSISTANT .. "MSUF_AssistantLOD_Bootstrap.lua",
            "MidnightSimpleUnitFrames_Assistant", private)
        Check(ok, flavor .. ": the Assistant bootstrap failed: " .. tostring(message))
        Check(private.Client == main.Client, flavor .. ": the Assistant namespace does not reach the client model")
    end
    ok, message = world:LoadFile(ASSISTANT .. "MSUF_AssistantRegistry_Global_BaseSettings.lua",
        "MidnightSimpleUnitFrames_Assistant", private)
    Check(ok, flavor .. ": the Assistant base settings registry failed: " .. tostring(message))

    local assistant = rawget(private, "Assistant")
    Check(type(assistant) == "table" and type(assistant.GlobalRegistry) == "table"
        and type(assistant.GlobalRegistry.RegisterBaseSettings) == "function",
        flavor .. ": RegisterBaseSettings was not published")
    assistant.GlobalRegistry.RegisterBaseAppearanceSettings = function() end

    local registered, general = {}, {}
    local function Record(key) registered[key] = true end
    assistant.GlobalRegistry.RegisterBaseSettings({
        Registry = { RegisterSetting = function(_, spec) Record(spec.key) end },
        GeneralDB = function() return general end,
        ApplyGeneral = function() end,
        RegisterGeneralBoolean = function(key) Record("general." .. key) end,
        RegisterGeneralString = function(key) Record("general." .. key) end,
    })
    -- A neighbour registered unconditionally: proves the registry really ran.
    Check(registered["general.tooltipShowAuraSpellIDs"] == true,
        flavor .. ": the base settings registry did not run")
    local client = not options.bare and main.Client or nil
    return registered["general." .. SETTING] == true, client, MenuOffers({ Client = client })
end

local CASES = {
    { label = "Midnight", flavor = "Mainline", family = "Mainline", offered = true },
    { label = "WoW Forever", flavor = World.FOREVER, family = "Mainline", offered = true },
    -- A Mainline-family client whose project ID is not Mainline's.
    { label = "WoW Forever reporting the Classic Era project", flavor = World.FOREVER,
        projectGlobal = "WOW_PROJECT_CLASSIC", family = "Mainline", offered = true },
    { label = "Classic Era", flavor = "Vanilla", family = "Classic", offered = false },
    { label = "TBC", flavor = "TBC", family = "Classic", offered = false },
    { label = "Mists", flavor = "Mists", family = "Classic", offered = false },
    -- A Classic-tagged TOC reporting the Mainline project is still Classic.
    { label = "Classic Era tag reporting the Mainline project", flavor = "Vanilla",
        projectGlobal = "WOW_PROJECT_MAINLINE", family = "Classic", offered = false },
    -- Without a client model both keep the Mainline answer, the build they belong to.
    { label = "no client model", flavor = "Mainline", bare = true, offered = true },
}

for _, case in ipairs(CASES) do
    local registered, client, menuOffers = Register(case.flavor, case)
    if case.family then
        Check(client and client.Family == case.family,
            case.label .. ": expected family " .. case.family .. ", the client model says "
                .. tostring(client and client.Family))
    end
    Check(menuOffers == case.offered, case.label .. ": the menu's IS_MAINLINE answers " .. tostring(menuOffers))
    Check(registered == case.offered, case.label .. ": the Assistant "
        .. (registered and "registers" or "does not register") .. " " .. SETTING
        .. " while the menu " .. (menuOffers and "offers" or "hides") .. " it")
end

print(string.format("assistant caster names family smoke: ok (%d clients agree with the menu)", #CASES))
