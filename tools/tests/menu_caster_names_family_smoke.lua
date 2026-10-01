-- The Global / Misc page offers Aura Tooltip Caster Names only on Mainline-family clients.
-- Verify that the live client model and menu predicate agree across client flavors.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Check(condition, message) if not condition then error(message, 2) end end
local MENU_PAGE = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua"
local menuSource = World.Read(root .. "/" .. MENU_PAGE)
local expression = menuSource:match("\nlocal IS_MAINLINE = ([^\n]+)\n")
Check(expression, MENU_PAGE .. " no longer defines IS_MAINLINE on one line")
Check(not expression:find("WOW_PROJECT", 1, true), MENU_PAGE .. " IS_MAINLINE reads a raw project global")
local MenuOffers = assert(loadstring("local MSUF = ...\nreturn " .. expression, "@IS_MAINLINE"))
local cases = {
    { "Mainline", "Mainline", true }, { World.FOREVER, "Mainline", true },
    { "Vanilla", "Classic", false }, { "TBC", "Classic", false }, { "Mists", "Classic", false },
}
for _, case in ipairs(cases) do
    local world = World.New(root, case[1])
    local namespace = {}
    local ok, message = world:LoadFile(root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua",
        "MidnightSimpleUnitFrames", namespace)
    Check(ok, tostring(case[1]) .. ": client initialization failed: " .. tostring(message))
    local client = namespace.Client
    Check(client and client.Family == case[2], tostring(case[1]) .. ": unexpected client family")
    Check(MenuOffers({ Client = client }) == case[3], tostring(case[1]) .. ": menu availability disagrees with client family")
end
print("menu caster names family smoke: ok")
