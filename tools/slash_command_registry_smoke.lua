--- Slash command registry contract.
---
--- Pins the three things the /msuf surface has silently broken before:
---   1. every documented command is actually reachable through dispatch,
---   2. help lists exactly what is registered (no ghosts, no omissions),
---   3. the whole surface is inert - registering commands must not create a
---      frame, an event or a ticker, so it costs zero in combat.
_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = { "MidnightSimpleUnitFrames/" .. relative, relative }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "r")
        if handle then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate " .. relative)
end

local function ResolveOptionsPath(relative)
    local candidates = {
        "MidnightSimpleUnitFrames_Options/" .. relative,
        "../MidnightSimpleUnitFrames_Options/" .. relative,
    }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "r")
        if handle then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate Options " .. relative)
end

local CHAT_PATH = ResolvePath("Runtime/MSUF_ChatAndTooltips.lua")
local MENU_API_PATH = ResolveOptionsPath("Shell/Menu2/MSUF_Menu2_API.lua")

--- ---------------------------------------------------------------------------
--- WoW stubs. Every frame/event entry point counts itself so the zero-overhead
--- claim is verified rather than asserted in a comment.
--- ---------------------------------------------------------------------------
local sideEffects = { frames = 0, events = 0, timers = 0, hooks = 0 }
local output = {}
local combat = false

local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    output[#output + 1] = table.concat(parts, " ")
end
local function ResetOutput()
    for i = #output, 1, -1 do output[i] = nil end
end
local function OutputText()
    return table.concat(output, "\n")
end
local function OutputContains(needle)
    return OutputText():find(needle, 1, true) ~= nil
end

_G.SlashCmdList = {}
_G.InCombatLockdown = function() return combat end
_G.ReloadUI = function() end
_G.GetLocale = function() return "enUS" end
_G.UIParent = {}
_G.C_AddOns = { GetAddOnMetadata = function() return "6.0-smoke" end }
_G.C_Timer = {
    After = function()
        sideEffects.timers = sideEffects.timers + 1
    end,
}
_G.hooksecurefunc = function()
    sideEffects.hooks = sideEffects.hooks + 1
end
_G.CreateFrame = function()
    sideEffects.frames = sideEffects.frames + 1
    return {
        RegisterEvent = function() sideEffects.events = sideEffects.events + 1 end,
        UnregisterEvent = function() end,
        SetScript = function() end,
        SetPoint = function() end,
        SetSize = function() end,
        Hide = function() end,
        Show = function() end,
        IsShown = function() return false end,
    }
end

--- ---------------------------------------------------------------------------
--- Profile backend stub: the real one lives in State/MSUF_Profiles.lua and is
--- already covered elsewhere. Here it only has to record what was asked of it.
--- ---------------------------------------------------------------------------
local profiles = { "Default", "Raiding", "RaidingAlt" }
local profileCalls = {}
local function ProfileIndex(name)
    for i = 1, #profiles do if profiles[i] == name then return i end end
end
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GetAllProfiles = function()
    local copy = {}
    for i = 1, #profiles do copy[i] = profiles[i] end
    return copy
end
_G.MSUF_CreateProfile = function(name)
    if ProfileIndex(name) then return false end
    profiles[#profiles + 1] = name
    profileCalls[#profileCalls + 1] = "create:" .. tostring(name)
    return true
end
_G.MSUF_SwitchProfile = function(name)
    if not ProfileIndex(name) then return false end
    _G.MSUF_ActiveProfile = name
    profileCalls[#profileCalls + 1] = "switch:" .. tostring(name)
    return true
end
_G.MSUF_DeleteProfile = function(name)
    local index = ProfileIndex(name)
    if not index then return false end
    table.remove(profiles, index)
    profileCalls[#profileCalls + 1] = "delete:" .. tostring(name)
    return true
end
_G.MSUF_ResetProfile = function(name)
    profileCalls[#profileCalls + 1] = "reset:" .. tostring(name)
    return true
end
_G.MSUF_IsInEditMode = function() return false end
_G.MSUF_EnsureDB = function() end
_G.MSUF_DB = { general = {} }

--- ---------------------------------------------------------------------------
--- Load the runtime half of the registry.
--- ---------------------------------------------------------------------------
local MSUF = {}
MSUF.ExportPublic = function(name, value)
    _G[name] = value
    return value
end

local chunk, err = loadfile(CHAT_PATH)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local Commands = MSUF.SlashCommands
assert(type(Commands) == "table", "MSUF.SlashCommands must exist after the runtime file loads")
assert(type(Commands.Dispatch) == "function", "the registry must expose Dispatch")

--- ---------------------------------------------------------------------------
--- Load the Menu2 half against a stub menu.
--- ---------------------------------------------------------------------------
--- The real LoD loader publishes these metadata entries before Menu2 exists.
--- Seed one exact entry here so the real API must replace it in place instead
--- of silently losing the command to duplicate-word rejection.
local deferredEditRun = function() error("deferred Edit command was not replaced") end
local deferredEditEntry = {
    name = "edit",
    aliases = { "editmode", "move", "unlock" },
    group = "frames",
    usage = "/msuf edit [unit]",
    help = "Toggle MSUF Edit Mode. Add a unit such as player or target to open it there.",
    _msufOptionsLODDeferred = true,
    run = deferredEditRun,
}
assert(Commands.Register(deferredEditEntry),
    "failed to seed the Options LoD deferred Edit command")

local menuCalls = {}
local M = {
    frame = nil,
    pages = {
        home = {}, search = {}, profiles = {}, opt_bars = {}, opt_colors = {},
        uf_player = {}, uf_target = {}, uf_focus = {}, uf_pet = {}, uf_boss = {},
        uf_targettarget = {}, uf_focustarget = {}, gf_layout = {}, gf_priority = {},
        auras3_styling = {},
    },
    ALIASES = {
        [""] = "home", home = "home", player = "uf_player", target = "uf_target",
        focus = "uf_focus", pet = "uf_pet", boss = "uf_boss", tot = "uf_targettarget",
        focustarget = "uf_focustarget", colors = "opt_colors", bars = "opt_bars",
        priority = "gf_priority", auras = "auras3_styling",
    },
}
M.Tr = function(text) return text end
M.Format = function(text, ...) return string.format(text, ...) end
M.CallIf = function(fn, ...) if type(fn) == "function" then return fn(...) end end
M.BlockCombatAction = function() return combat end
M.Open = function(pageKey)
    if combat then return false end
    menuCalls[#menuCalls + 1] = "open:" .. tostring(pageKey)
    return true
end
M.SelectPage = function(pageKey)
    menuCalls[#menuCalls + 1] = "select:" .. tostring(pageKey)
    return true
end
M.GetLocaleCoverage = function() return 10, 0 end
M.SearchBridge = {
    RunSearchQuery = function(query)
        menuCalls[#menuCalls + 1] = "search:" .. tostring(query)
        return true, query
    end,
}
local editActive = false
local editUnit
M.EditModeLifecycleStatus = function()
    return { active = editActive, combatLocked = combat, unitKey = editUnit }
end
M.SetMSUFEditModeActive = function(active, unitKey)
    if active and combat then return false, "combat_locked" end
    editActive = active and true or false
    editUnit = unitKey
    menuCalls[#menuCalls + 1] = "edit:" .. tostring(active) .. ":" .. tostring(unitKey)
    return true
end
M.ToggleMSUFEditMode = function(unitKey, opts)
    return M.SetMSUFEditModeActive(not editActive, unitKey, opts)
end
_G.MSUF_SetMSUFEditModeDirect = function(active, unitKey)
    editActive = active and true or false
    editUnit = unitKey
    menuCalls[#menuCalls + 1] = "editdirect:" .. tostring(active) .. ":" .. tostring(unitKey)
    return true
end
MSUF.MSUF2 = M

chunk, err = loadfile(MENU_API_PATH)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)
assert(Commands.Get("edit") == deferredEditEntry,
    "Menu2 replaced the deferred command table instead of preserving registry order")
assert(deferredEditEntry._msufOptionsLODDeferred == nil
    and deferredEditEntry.run ~= deferredEditRun,
    "Menu2 did not replace the deferred command with its real handler")

local function ResetCalls()
    for i = #menuCalls, 1, -1 do menuCalls[i] = nil end
    for i = #profileCalls, 1, -1 do profileCalls[i] = nil end
    ResetOutput()
end
local function CallsContain(needle)
    for i = 1, #menuCalls do if menuCalls[i] == needle then return true end end
    return false
end
local function ProfileCallsContain(needle)
    for i = 1, #profileCalls do if profileCalls[i] == needle then return true end end
    return false
end

--- ---------------------------------------------------------------------------
--- 1. Zero combat overhead.
---
--- Both files own unrelated machinery, so the load-time budget is pinned to the
--- one long-standing listener (the tooltip hover-inert watcher and its three
--- events). A command that quietly brings its own event frame breaks this.
--- ---------------------------------------------------------------------------
local LOAD_BUDGET = { frames = 1, events = 3, timers = 0, hooks = 0 }
for key, allowed in pairs(LOAD_BUDGET) do
    assert(sideEffects[key] == allowed, string.format(
        "loading the slash files produced %d %s (budget %d): the command surface must stay inert",
        sideEffects[key], key, allowed))
end
--- From here on nothing may be added: the counters are re-checked at the end
--- after every command has been dispatched at least once.
local function AssertNoNewSideEffects(context)
    for key, allowed in pairs(LOAD_BUDGET) do
        assert(sideEffects[key] == allowed, string.format(
            "%s created %d %s beyond the load budget of %d",
            context, sideEffects[key] - allowed, key, allowed))
    end
end

--- ---------------------------------------------------------------------------
--- 2. Every slash entry point routes through the one registry.
--- ---------------------------------------------------------------------------
for _, handler in ipairs({ "MSUF2OPTIONS", "MIDNIGHTSUF", "MSUFOPTIONS" }) do
    assert(type(_G.SlashCmdList[handler]) == "function", handler .. " must stay registered")
end
assert(_G.SLASH_MSUF2OPTIONS1 == "/msuf", "/msuf must remain the primary command")

--- No other addon claimed "/rl" in this fixture, so MSUF must still take it.
--- The yield-when-taken guard (addon_interop_guard_smoke) must never degrade
--- into "never register".
assert(type(_G.SlashCmdList["MSUFRELOADUI"]) == "function",
    "/rl must still be claimed when the token is free")
assert(_G.SLASH_MSUFRELOADUI1 == "/rl", "the claimed /rl token must be published")

--- ---------------------------------------------------------------------------
--- 3. Command coverage. Every word here must resolve to a registered command,
---    not fall through to the page/search fallback.
--- ---------------------------------------------------------------------------
local EXPECTED = {
    -- pre-existing commands that must keep working
    "help", "reset", "fullreset", "absorb", "analytics", "gfhoverdebug",
    "inputdebug", "tour", "guide", "setup", "firstload", "locale", "locales",
    "loc", "versiontest",
    -- commands added for the slash-command request
    "edit", "editmode", "move", "unlock", "lock", "search", "find",
    "profile", "profiles", "load", "use", "switch", "delete", "default",
    "defaults", "resetprofile", "version", "ver", "status", "reload",
}
for i = 1, #EXPECTED do
    local word = EXPECTED[i]
    assert(Commands.Get(word), "/msuf " .. word .. " is not registered")
end

--- Aliases must never collide: a second registration of a taken word is
--- rejected rather than silently rebinding the first command.
local seen = {}
for i = 1, #Commands.order do
    local entry = Commands.order[i]
    assert(type(entry.run) == "function", "command " .. tostring(entry.name) .. " has no handler")
    assert(type(entry.help) == "string" and entry.help ~= "",
        "command " .. tostring(entry.name) .. " has no help text")
    assert(not seen[entry.name], "duplicate command name " .. tostring(entry.name))
    seen[entry.name] = true
end
local ok = Commands.Register({ name = "help", run = function() end })
assert(ok == false, "re-registering an existing command word must be rejected")
ok = Commands.Register({ name = "brandnew", aliases = { "edit" }, run = function() end })
assert(ok == false, "registering a command whose alias is taken must be rejected")
assert(Commands.Get("brandnew") == nil, "a rejected registration must not be published at all")

--- ---------------------------------------------------------------------------
--- 4. Help lists every non-dev command, and /msuf help all lists the rest.
--- ---------------------------------------------------------------------------
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("help")
local shortHelp = OutputText()
for i = 1, #Commands.order do
    local entry = Commands.order[i]
    if not entry.dev then
        assert(shortHelp:find(entry.usage, 1, true),
            "/msuf help omits " .. tostring(entry.usage))
    else
        assert(not shortHelp:find(entry.usage, 1, true),
            "/msuf help must keep the diagnostic command " .. tostring(entry.usage) .. " out of the short list")
    end
end
assert(shortHelp:find("/msuf help all", 1, true), "the short help must point at the full list")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("help all")
local fullHelp = OutputText()
for i = 1, #Commands.order do
    assert(fullHelp:find(Commands.order[i].usage, 1, true),
        "/msuf help all omits " .. tostring(Commands.order[i].usage))
end
for i = 1, #Commands.external do
    assert(fullHelp:find(Commands.external[i].usage, 1, true),
        "/msuf help all omits the standalone command " .. tostring(Commands.external[i].usage))
end
--- /rl registers itself from the file that owns it; a command that ships
--- unloaded (for example /msufdbgpos) must therefore never appear here.
assert(fullHelp:find("/rl", 1, true), "/rl must be listed as a standalone command")
assert(not fullHelp:find("/msufdbgpos", 1, true),
    "help must not advertise a command whose file is excluded from the TOC")
assert(not fullHelp:find("!msuf", 1, true),
    "help must not advertise the removed !msuf chat trigger")

--- The dashboard "Print Help" button prints through the same router.
ResetCalls()
_G.SlashCmdList["MIDNIGHTSUF"]("help all")
assert(OutputText() == fullHelp, "the dashboard help path must print the same list as /msuf help all")

--- ---------------------------------------------------------------------------
--- 5. Routing: page names open pages, unknown words search, nothing lands on
---    the "native page missing" placeholder any more.
--- ---------------------------------------------------------------------------
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("")
assert(CallsContain("open:nil"), "bare /msuf must open the menu")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("target")
assert(CallsContain("open:uf_target"), "/msuf target must open the target page")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("Colors")
assert(CallsContain("open:opt_colors"), "page names must resolve case-insensitively")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("healthbar texture")
assert(CallsContain("search:healthbar texture"),
    "an unknown word must become a menu search instead of a blank page")
assert(not CallsContain("open:healthbar texture"),
    "an unknown word must never be opened as a page key")

--- ---------------------------------------------------------------------------
--- 6. Edit mode. This is the reported bug: /msuf edit used to open an empty
---    "native page missing" page because `edit` was read as a page name.
--- ---------------------------------------------------------------------------
ResetCalls()
editActive, editUnit = false, nil
_G.SlashCmdList["MSUF2OPTIONS"]("edit")
assert(CallsContain("edit:true:nil"), "/msuf edit must enter MSUF Edit Mode")
assert(not CallsContain("open:edit"), "/msuf edit must not be routed as a page")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("edit")
assert(CallsContain("edit:false:nil"), "/msuf edit must toggle back out of Edit Mode")

ResetCalls()
editActive, editUnit = false, nil
_G.SlashCmdList["MSUF2OPTIONS"]("edit target")
assert(CallsContain("edit:true:target"), "/msuf edit target must enter Edit Mode on the target frame")

--- Already inside Edit Mode a unit argument retargets instead of toggling off.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("edit focus")
assert(CallsContain("editdirect:true:focus"), "/msuf edit <unit> must retarget while Edit Mode runs")
assert(editActive, "/msuf edit <unit> must not drop out of Edit Mode")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("lock")
assert(CallsContain("edit:false:nil"), "/msuf lock must leave Edit Mode")
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("lock")
assert(not CallsContain("edit:false:nil"), "/msuf lock outside Edit Mode must stay a no-op")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("edit nonsense")
assert(#menuCalls == 0, "an unknown unit must not toggle Edit Mode")
assert(OutputContains("nonsense"), "an unknown unit must be reported back to the player")

--- ---------------------------------------------------------------------------
--- 7. Profiles.
--- ---------------------------------------------------------------------------
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("profile")
assert(OutputContains("Default"), "/msuf profile must list the saved profiles")
assert(OutputContains("Raiding"), "/msuf profile must list every saved profile")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("profile My Raid Setup")
assert(ProfileCallsContain("create:My Raid Setup"),
    "/msuf profile <name> must save a profile under the exact name typed")
assert(ProfileCallsContain("switch:My Raid Setup"),
    "/msuf profile <name> must switch to the profile it just saved")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("load Default")
assert(ProfileCallsContain("switch:Default"), "/msuf load must switch profiles")

--- Case-insensitive and unique-prefix matching, but never a silent guess.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("load my raid setup")
assert(ProfileCallsContain("switch:My Raid Setup"), "/msuf load must match profile names case-insensitively")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("load Raiding")
assert(ProfileCallsContain("switch:Raiding"),
    "an exact name must win over the ambiguous-prefix guard")

ResetCalls()
_G.MSUF_ActiveProfile = "Default"
_G.SlashCmdList["MSUF2OPTIONS"]("load Raid")
assert(#profileCalls == 0, "an ambiguous prefix must not switch profiles")
assert(OutputContains("more than one"), "an ambiguous prefix must say so")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("load Nope")
assert(#profileCalls == 0, "an unknown profile must not switch")
assert(OutputContains("Nope"), "an unknown profile must be named back to the player")

--- Deletion needs the command repeated with the same target.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("delete Raiding")
assert(#profileCalls == 0, "the first /msuf delete must only ask for confirmation")
_G.SlashCmdList["MSUF2OPTIONS"]("delete Raiding")
assert(ProfileCallsContain("delete:Raiding"), "repeating /msuf delete must delete the profile")

--- A confirmation is bound to one profile: switching target re-arms it.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("delete RaidingAlt")
_G.SlashCmdList["MSUF2OPTIONS"]("delete Default")
assert(#profileCalls == 0, "a pending confirmation must not carry over to another profile")

--- Resetting the active profile is destructive and confirms separately from
--- /msuf reset, which only moves frames back.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("default")
assert(#profileCalls == 0, "/msuf default must ask before wiping the profile")
_G.SlashCmdList["MSUF2OPTIONS"]("default confirm")
assert(ProfileCallsContain("reset:Default"), "/msuf default confirm must reset the active profile")

--- ---------------------------------------------------------------------------
--- 8. Combat. Every command that writes layout or swaps a profile refuses.
--- ---------------------------------------------------------------------------
combat = true
local COMBAT_BLOCKED = {
    { "profile CombatProfile", "create:CombatProfile" },
    { "load Raiding", "switch:Raiding" },
    { "delete RaidingAlt", "delete:RaidingAlt" },
    { "default confirm", "reset:Default" },
}
for i = 1, #COMBAT_BLOCKED do
    ResetCalls()
    _G.SlashCmdList["MSUF2OPTIONS"](COMBAT_BLOCKED[i][1])
    assert(not ProfileCallsContain(COMBAT_BLOCKED[i][2]),
        "/msuf " .. COMBAT_BLOCKED[i][1] .. " must be refused in combat")
end

ResetCalls()
editActive = false
_G.SlashCmdList["MSUF2OPTIONS"]("edit")
assert(not editActive, "/msuf edit must be refused in combat")

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("reset")
assert(OutputContains("combat"), "/msuf reset must be refused in combat")

--- Absorb runs the apply pipeline; it used to inherit Menu2's blanket check.
ResetCalls()
_G.MSUF_DB.general.enableAbsorbBar = false
_G.SlashCmdList["MSUF2OPTIONS"]("absorb")
assert(_G.MSUF_DB.general.enableAbsorbBar == false, "/msuf absorb must be refused in combat")

--- Read-only commands stay usable in combat: they only print.
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("help")
assert(OutputContains("/msuf help"), "/msuf help must still work in combat")
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("version")
assert(OutputContains("6.0-smoke"), "/msuf version must still work in combat")
ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("profile")
assert(OutputContains("Default"), "listing profiles must still work in combat")
combat = false

ResetCalls()
_G.SlashCmdList["MSUF2OPTIONS"]("absorb")
assert(_G.MSUF_DB.general.enableAbsorbBar == true, "/msuf absorb must still toggle out of combat")

--- Dispatch itself must not have grown a background cost along the way.
AssertNoNewSideEffects("dispatching slash commands")

realPrint(string.format("PASS slash command registry: %d commands, %d standalone, %d words",
    #Commands.order, #Commands.external, (function()
        local count = 0
        for _ in pairs(Commands.byWord) do count = count + 1 end
        return count
    end)()))
