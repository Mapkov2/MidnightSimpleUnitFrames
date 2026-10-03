-- menu_history_locale_smoke.lua <repoRoot>
--
-- The menu history speaks the menu language (re-review R7, P3):
--   * the Undo / Redo feedback is the whole-sentence "Undid %s" / "Redid %s",
--     not "Undid " .. label;
--   * history labels are translated where they are shown (GetHistoryState,
--     the toolbar feedback), and a page reset names itself like the provider
--     path: "Reset %s" over the translated page title;
--   * "Session changes reset" is in every pack and reaches the status line
--     translated;
--   * feedback labels are cut by UTF-8 characters, never inside one, and the
--     nav rail's Undo / Redo tooltip titles are "Undo: %s" / "Redo: %s".
-- Boots the real Mainline core and Options graph with the German pack
-- (tools/tests/client_world.lua). Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- True when `text` is well-formed UTF-8.
local function ValidUtf8(text)
    local i, n = 1, #text
    while i <= n do
        local b = text:byte(i)
        local size = b < 0x80 and 1 or (b >= 0xC2 and b < 0xE0) and 2 or (b >= 0xE0 and b < 0xF0) and 3
            or (b >= 0xF0 and b < 0xF5) and 4 or nil
        if not size or i + size - 1 > n then return false end
        for k = i + 1, i + size - 1 do
            local c = text:byte(k)
            if c < 0x80 or c > 0xBF then return false end
        end
        i = i + size
    end
    return true
end

-- 1. Every pack carries the new keys.
local KEYS = { "Undid %s", "Redid %s", "Session changes reset", "Undo: %s", "Redo: %s", "Redo", "Menu change", "Reset %s" }
local PACKS = { "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, pack in ipairs(PACKS) do
    local source = Read("MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua")
    for _, key in ipairs(KEYS) do
        local prefix = 'L["' .. key .. '"] = "'
        local start = source:find(prefix, 1, true)
        if Check(start, pack .. ": missing " .. key) and pack ~= "enUS" and pack ~= "enGB" then
            local value = source:sub(start + #prefix, (source:find('"', start + #prefix, true) or 0) - 1)
            Check(value ~= key, pack .. ": " .. key .. " is not translated")
        end
    end
end

-- 2. The nav rail titles are format keys.
local nav = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_NavRail.lua")
Check(nav:find('M.Format("Undo: %s", ', 1, true) and nav:find('M.Format("Redo: %s", ', 1, true)
    and not nav:find('"Undo: " ..', 1, true) and not nav:find('"Redo: " ..', 1, true),
    "the nav rail glues its Undo / Redo tooltip titles together")

-- 3. The German menu at run time.
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline", { locale = "deDE" })
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
assert(not failure, "deDE boot failed: " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, core = world.env, world.core
core.FinalizeLocale()
env.MSUF_InitProfiles()
env.MSUF_EnsureDB(true)
local M = assert(core.MSUF2, "Menu2 did not load")
M.ApplyService.Flush = function() return true end
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
-- A page reset reads the factory profile (menu_page_reset_history_smoke).
local F = assert(core.ProfileFields, "ProfileFields did not load")
local factory = assert(F.CopySnapshot(M.EnsureDB()), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
local function L(key)
    local value = rawget(core.L, key)
    return type(value) == "string" and value ~= "" and value or key
end

-- What the status line shows (Window.lua ShowStatusFeedback: translated = true
-- shows the text as it is, anything else goes through M.Tr).
local shown
M.ShowStatusFeedback = function(text, _, _, translated)
    shown = translated == true and tostring(text) or M.Tr(tostring(text))
end
M.ShowInlineFeedback = M.ShowStatusFeedback
local toolbar
M.ShowHistoryFeedback = function(text) toolbar = text end

Check(M.StartHistorySession("menu") == true, "the menu history session did not start")
local function Change(label, width)
    return M.RunWithHistory(label, "smoke:history:" .. width, function()
        env.MSUF_DB.player.width = width
        return true
    end)
end

-- A plain label: translated where it is shown.
local LABEL = "Profile reset"
Check(L(LABEL) ~= LABEL, "deDE has no translation for " .. LABEL .. "; pick another label")
Change(LABEL, 201)
local state = M.GetHistoryState()
Check(state.undoLabel == L(LABEL), "the undo label is " .. tostring(state.undoLabel) .. ", not " .. L(LABEL))
Check(toolbar == L(LABEL), "the toolbar feedback is " .. tostring(toolbar) .. ", not " .. L(LABEL))
Check(M.Undo() == true, "Undo failed")
local want = string.format(L("Undid %s"), L(LABEL))
Check(shown == want, "Undo said " .. tostring(shown) .. ", not " .. want)
Check(M.Redo() == true, "Redo failed")
want = string.format(L("Redid %s"), L(LABEL))
Check(shown == want, "Redo said " .. tostring(shown) .. ", not " .. want)

-- A long label in letters of two bytes: cut by characters.
local long = string.rep("\195\164", 50) -- 50 x a-umlaut
Change(long, 203)
Check(type(toolbar) == "string" and ValidUtf8(toolbar), "the toolbar feedback split a character: " .. tostring(toolbar))
Check(M.Undo() == true, "Undo of the long label failed")
Check(shown and ValidUtf8(shown), "the Undo feedback split a character")
want = string.format(L("Undid %s"), string.rep("\195\164", 31) .. "...")
Check(shown == want, "the Undo feedback did not keep 31 characters and an ellipsis: " .. tostring(shown))
Check(M.ShortenUtf8 and M.ShortenUtf8("\195\164\195\164\195\164", 3) == "\195\164\195\164\195\164"
    and M.ShortenUtf8(string.rep("\195\164", 5), 4) == "\195\164...", "M.ShortenUtf8 does not count characters")

-- A page reset names itself like the provider path (a changed Bars setting
-- first, so the reset has something to undo).
Check(M.CaptureHistory("Smoke marker", "smoke:marker:opt_bars", function()
    env.MSUF_DB.general.enableGradient = env.MSUF_DB.general.enableGradient ~= true
    return true
end) == true, "the Bars marker edit was refused")
Check(M.ResetPageToDefaults("opt_bars") == true, "the Bars page reset failed")
state = M.GetHistoryState()
want = string.format(L("Reset %s"), L("Bars"))
Check(state.undoLabel == want, "the page reset entry is " .. tostring(state.undoLabel) .. ", not " .. want)

-- The session reset feedback.
Check(M.ResetHistorySession() == true, "the session reset failed")
Check(shown == L("Session changes reset") and shown ~= "Session changes reset",
    "the session reset said " .. tostring(shown))
M.EndHistorySession("menu")

if #failures > 0 then
    error("menu_history_locale_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_history_locale_smoke: ok (12 packs; German undo, redo, labels, page reset, session reset; UTF-8 cuts)")
