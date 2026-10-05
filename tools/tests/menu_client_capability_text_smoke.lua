-- menu_client_capability_text_smoke.lua <repoRoot> <flavor>
--
-- Menu controls and help text that name a client capability must match the
-- running client.
--
--   1. Miscellaneous > Blizzard Frames: "Enable native Player resource pings"
--      drives Blizzard's ping system (Blizzard_PingUI, the PingableType
--      mixins). The mirror ships it on upstream/live and upstream/forever only;
--      classic_era, classic_anniversary and classic define
--      PingableUnitFrameTemplate as an empty stub (Blizzard_SharedXML/Classic/
--      Stubs.xml), so UF.ConfigurePlayerResourcePing never enables it there.
--      The switch is built on Midnight and WoW Forever and nowhere else.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_client_capability_text_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Clients whose mirror branch ships Blizzard_PingUI.
local PING_CLIENTS = { Mainline = true, Forever = true }

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M = mw.M
local frames = mw.world.widgets.frames

---------------------------------------------------------------------------
-- 1. Resource ping switch
---------------------------------------------------------------------------
Check(mw:Select("opt_misc"), "Miscellaneous page did not open")
local pingSwitch, minimapSwitch
for _, widget in ipairs(frames) do
    local action = widget._msuf2CommandAction
    if action and action.settingKey == "general.playerResourcePingEnabled" then pingSwitch = widget end
    if action and action.settingKey == "general.showMinimapIcon" then minimapSwitch = widget end
end
Check(minimapSwitch, "precondition: the Blizzard Frames section was not built")
if PING_CLIENTS[flavor] then
    Check(pingSwitch, "the resource ping switch is missing on a client with Blizzard's ping system")
else
    Check(not pingSwitch, "the resource ping switch is built on a client without Blizzard's ping system")
end

print("menu_client_capability_text_smoke " .. flavor .. ": OK (resource ping switch "
    .. (pingSwitch and "built" or "absent") .. ")")
