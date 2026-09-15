-- /msuf clientinfo contract. The command lives in the runtime slash registry, is
-- listed in the short help, prints the Game/Shared/Initialize.lua report even in
-- combat without creating a frame, event or timer, and prints one line instead of
-- failing when client detection did not run. Plain Lua 5.1; arg[1] is the repo root.
local repo = assert(arg[1], "repo root required")

local realPrint = print
local output = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    output[#output + 1] = table.concat(parts, " ")
end
local function ResetOutput()
    for i = #output, 1, -1 do output[i] = nil end
end
local function OutputText()
    return table.concat(output, "\n")
end
local function AssertOutputContains(fragment, context)
    assert(OutputText():find(fragment, 1, true), context .. ": output lacks '" .. fragment .. "':\n" .. OutputText())
end
local function CountKeys(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local sideEffects = { frames = 0, events = 0, timers = 0 }
CreateFrame = function()
    sideEffects.frames = sideEffects.frames + 1
    return {
        RegisterEvent = function() sideEffects.events = sideEffects.events + 1 end,
        UnregisterEvent = function() end,
        SetScript = function() end,
    }
end
C_Timer = { After = function() sideEffects.timers = sideEffects.timers + 1 end }
SlashCmdList = {}
InCombatLockdown = function() return true end
ReloadUI = function() end
GetLocale = function() return "enUS" end

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
GetBuildInfo = function() return "12.1.5", "69594", "test", 120105 end
issecretvalue = function() return false end
C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    DoesAddOnExist = function(name) return name ~= "Blizzard_ArenaUI" end,
    IsAddOnLoaded = function(name) return name == "Blizzard_AuraContainer" end,
    GetAddOnInfo = function(name)
        if name == "Blizzard_CompactRaidFrames" then return name, name, "", false, "DEMAND_LOADED" end
        return name, name, "", true, ""
    end,
}
-- Test values only: Blizzard does not document the Enum.GameMode numbers.
Enum = { GameMode = { Standard = 0, Plunderstorm = 1, WoWHack = 2 }, GameRule = { EditModeDisabled = 7 } }
C_GameRules = {
    GetActiveGameMode = function() return 0 end,
    IsStandard = function() return true end,
    IsPlunderstorm = function() return false end,
    IsWoWHack = function() return false end,
    IsGameRuleActive = function(rule) return rule == 7 end,
    IsClassAllowedForGameMode = function() error("clientinfo must never call a C_GameRules function that takes arguments") end,
}
local addOnKeys, gameRuleKeys = CountKeys(C_AddOns), CountKeys(C_GameRules)

MSUF_EnsureDB = function() end
MSUF_CreateProfile = function() return false end
MSUF_SwitchProfile = function() return false end
MSUF_DeleteProfile = function() return false end
MSUF_ResetProfile = function() return false end
MSUF_GetAllProfiles = function() return { "Default" } end
MSUF_ActiveProfile = "Default"

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
    Translate = function(text) return text end,
}
for _, relative in ipairs({
    "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua",
    "MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua",
    "MidnightSimpleUnitFrames/Runtime/MSUF_SlashCommands.lua",
}) do
    local chunk = assert(loadfile(repo .. "/" .. relative))
    chunk("MidnightSimpleUnitFrames", namespace)
end

assert(#output == 0, "loading the client detection and the slash registry printed:\n" .. OutputText())
assert(sideEffects.frames == 0 and sideEffects.events == 0 and sideEffects.timers == 0,
    "a known Standard client and the slash registry must load without frames, events or timers")

local Commands = assert(namespace.SlashCommands, "MSUF.SlashCommands missing")
local entry = assert(Commands.Get("clientinfo"), "/msuf clientinfo is not registered")
assert(Commands.Get("client") == entry and Commands.Get("CLIENTINFO") == entry, "clientinfo words do not resolve")
assert(entry.group == "diagnostics" and entry.dev ~= true, "clientinfo must be a non-dev diagnostics command")
assert(entry.usage == "/msuf clientinfo" and type(entry.help) == "string" and entry.help ~= "",
    "clientinfo usage or help missing")

ResetOutput()
Commands.PrintHelp(false)
AssertOutputContains("/msuf clientinfo", "short help")

-- In combat: the report is print-only.
local lines = namespace.Client.DescribeLines()
assert(type(lines) == "table" and #lines >= 8, "DescribeLines returned too few lines")
ResetOutput()
Commands.Dispatch("clientinfo")
assert(output[1] == "|cff00b7ebMSUF|r client info", "clientinfo header: " .. tostring(output[1]))
assert(#output == #lines + 1, "clientinfo must print its header plus one line per report line:\n" .. OutputText())
for i = 1, #lines do
    assert(output[i + 1] == "  " .. lines[i], "clientinfo line " .. i .. " differs from DescribeLines")
end
for _, fragment in ipairs({
    "Project 1 (WOW_PROJECT_MAINLINE), build 12.1.5 (69594), interface 120105",
    "TOC X-MSUF-Client none; family Mainline, flavor Mainline",
    "Game mode Standard (0) at load, Standard (0) now",
    "C_GameRules IsStandard=true IsPlunderstorm=false IsWoWHack=false",
    "other Is functions: IsClassAllowedForGameMode IsGameRuleActive",
    "Game rules: EditModeDisabled=true",
    "issecretvalue present; arena slots 3; unsupported units: none",
    "Blizzard_AuraContainer loaded, Blizzard_CooldownViewer loadable, Blizzard_EditMode loadable",
    "Blizzard_CompactRaidFrames not loadable (DEMAND_LOADED), Blizzard_ArenaUI absent",
    "Login diagnostic: none",
}) do
    AssertOutputContains(fragment, "clientinfo report")
end

-- The live game mode is read when the command runs; the load-time fact stays.
C_GameRules.GetActiveGameMode = function() return 1 end
ResetOutput()
Commands.Dispatch("client")
AssertOutputContains("Game mode Standard (0) at load, Plunderstorm (1) now", "live game mode")
C_GameRules.GetActiveGameMode = function() return 0 end

assert(sideEffects.frames == 0 and sideEffects.events == 0 and sideEffects.timers == 0,
    "clientinfo created a frame, event or timer")
assert(CountKeys(C_AddOns) == addOnKeys and CountKeys(C_GameRules) == gameRuleKeys,
    "clientinfo wrote into a Blizzard namespace")

-- Without client detection the command explains itself in one line.
local client = namespace.Client
namespace.Client = nil
ResetOutput()
Commands.Dispatch("clientinfo")
assert(#output == 1 and output[1]:find("client info is unavailable", 1, true),
    "clientinfo without client detection:\n" .. OutputText())
namespace.Client = client

print = realPrint
print("client info command smoke passed")
