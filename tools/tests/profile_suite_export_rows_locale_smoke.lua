-- profile_suite_export_rows_locale_smoke.lua <repoRoot> <flavor>
--
-- With MSUF Suite installed, the Profiles page "Export kind" picker offers
-- "Full profile (MSUF + Suite)", "MSUF only - full profile" and one
-- "Suite module: <module>" row per Suite module. The module rows were built
-- as "Suite module: " .. title, a string no pack can translate (every
-- language showed English and the menu logged each row as a missing key),
-- and none of the three texts was a key in any pack.
--
-- Boots the real core and Options graph under deDE (menu_core_world.lua)
-- with a stand-in Suite profile API, opens the picker and checks:
--   1. each row reads the German text built from whole keys;
--   2. no row text reaches the translator a second time;
--   3. each key exists in all twelve packs.
--
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("profile_suite_export_rows_locale_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Every lookup while the picker paints is recorded. The Options files keep
-- the translator they find at load, so it is wrapped before they load.
local seen, recording = {}, false
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = "deDE", beforeOptions = function(world)
    Check(world.core.FinalizeLocale() == "deDE", "the deDE pack was not selected")
    local Translate = world.core.Translate
    world.core.Translate = function(text, ...)
        if recording and type(text) == "string" then seen[text] = true end
        return Translate(text, ...)
    end
end })
local M, env = mw.M, mw.env
-- The Suite's own profile API is outside this repo; the page only asks
-- whether it is available and which modules it lists.
rawset(env, "MSUFSuite", {
    SuiteProfiles = { Available = function() return true end },
    Client = { AddOnEnabled = function() return true end },
    SuiteOrder = { "chat" },
    SuiteCatalog = { chat = { title = "Chat" } },
})

Check(mw:Select("profiles"), "Profiles page did not open")

local frames = mw.world.widgets.frames
local picker
for _, widget in ipairs(frames) do
    if widget._msuf2ControlKind == "dropdown" and widget._msuf2Title
        and widget._msuf2Title._msuf2SearchText == "Export kind" then picker = widget end
end
Check(picker, "Export kind picker missing")
recording = true
picker:Click("LeftButton")
recording = false
local rows = {}
for _, row in ipairs(frames) do
    if row._msuf2Owner == picker and row:IsShown() and row._msuf2Text then rows[row._msuf2Value] = row._msuf2Text:GetText() end
end
Check(next(seen) ~= nil, "precondition: the picker translated nothing while it painted")

local expected = {
    suite_all = M.Tr("Full profile (MSUF + Suite)"),
    all = M.Tr("MSUF only - full profile"),
    ["suite_module:skin"] = string.format(M.Tr("Suite module: %s"), M.Tr("Skinning")),
    ["suite_module:chat"] = string.format(M.Tr("Suite module: %s"), M.Tr("Chat")),
}
for value, text in pairs(expected) do
    Check(rows[value] == text, value .. " reads " .. tostring(rows[value]) .. ", expected " .. text)
    Check(not text:find("Suite module", 1, true) and text ~= "MSUF only - full profile"
        and text ~= "Full profile (MSUF + Suite)", value .. " is still English under deDE: " .. text)
    Check(not seen[text], value .. " was translated a second time: " .. text)
end

local packs = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, locale in ipairs(packs) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    for _, key in ipairs({ "Suite module: %s", "Full profile (MSUF + Suite)", "MSUF only - full profile" }) do
        Check(text:find('["' .. key .. '"]', 1, true), locale .. " has no entry for " .. key)
    end
end

print("profile_suite_export_rows_locale_smoke " .. flavor .. ": OK")
