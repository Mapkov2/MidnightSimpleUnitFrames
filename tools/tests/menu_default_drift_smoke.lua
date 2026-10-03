-- menu_default_drift_smoke.lua <repoRoot> <flavor>
--
-- Review R7 P3: menu controls read a fallback for an unset saved key, and two
-- of those fallbacks had drifted from the value the defaults pass seeds:
--   * "Show navigation icons" read false while Defaults_Shell seeds true, so
--     after a key went missing (a page reset copying a profile without it) the
--     toggle showed off and the rail dropped its icons until the next login;
--   * the castbar Manual width slider used 272 for the player castbar, whose
--     default is 271 (State/Defaults/MSUF_Defaults_Bars.lua), and the same
--     176/175/272 chain was copied into three places.
-- Each control of the opened page must read an unset key as the value a
-- fresh profile holds, and the slider's own reset value must be that too.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_default_drift_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env = mw.M, mw.env
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ApplyModules = function() return true end
local general = Check(M.EnsureDB().general, "no general settings")

-- What a fresh profile holds: the booted profile is built by the defaults pass.
local FRESH = {}
for _, key in ipairs({
    "showNavigationIcons",
    "castbarPlayerBarWidth", "castbarPlayerBarHeight", "castbarTargetBarWidth", "castbarTargetBarHeight",
    "castbarFocusBarWidth", "castbarFocusBarHeight", "bossCastbarWidth", "bossCastbarHeight",
    "arenaCastbarWidth", "arenaCastbarHeight",
}) do
    FRESH[key] = general[key]
end
Check(FRESH.showNavigationIcons == true, "the defaults pass no longer seeds navigation icons on")

local function Select(key)
    Check(M.SelectPage(key) ~= false, "could not open " .. key)
    mw:RunTimers()
    -- Closed unit sections build their controls in background slices.
    for _ = 1, 40 do
        if M.UnitPage and M.UnitPage.PumpBackgroundSections then M.UnitPage.PumpBackgroundSections() end
        mw:RunTimers()
    end
    return Check(M.cache[key], key .. " was not built")
end
local function FindControl(entry, kind, settingKey)
    local found
    local function Walk(frame)
        if found then return end
        local command = frame._msuf2CommandAction
        if command and command.kind == kind and command.settingKey == settingKey then found = frame return end
        for _, child in ipairs(frame.children or {}) do
            if child.parent == frame then Walk(child) end
        end
    end
    Walk(entry.wrapper)
    return found
end

---------------------------------------------------------------------------
-- Navigation icons
---------------------------------------------------------------------------
do
    local entry = Select("opt_misc")
    local toggle = Check(FindControl(entry, "toggle", "general.showNavigationIcons"),
        "opt_misc has no navigation icon toggle")
    general.showNavigationIcons = nil
    Check(toggle._msuf2CommandAction.get() == true, "an unset navigation icon key reads off; the default is on")
    local shown = {}
    local Attach = M.Theme.AttachNavIcon
    M.Theme.AttachNavIcon = function(btn, key, nested, visible)
        shown[#shown + 1] = visible
        return Attach(btn, key, nested, visible)
    end
    M.RefreshNavIconVisibility()
    M.Theme.AttachNavIcon = Attach
    Check(#shown > 0, "the rail repainted no navigation icon")
    for i = 1, #shown do Check(shown[i] == true, "an unset navigation icon key hides the rail icons") end
    general.showNavigationIcons = false
    shown = {}
    M.Theme.AttachNavIcon = function(btn, key, nested, visible)
        shown[#shown + 1] = visible
        return Attach(btn, key, nested, visible)
    end
    M.RefreshNavIconVisibility()
    M.Theme.AttachNavIcon = Attach
    for i = 1, #shown do Check(shown[i] == false, "turning navigation icons off kept them") end
    general.showNavigationIcons = true
    M.RefreshNavIconVisibility()
end

---------------------------------------------------------------------------
-- Castbar size sliders
---------------------------------------------------------------------------
local CASTBARS = {
    { page = "uf_player", width = "castbarPlayerBarWidth", height = "castbarPlayerBarHeight" },
    { page = "uf_target", width = "castbarTargetBarWidth", height = "castbarTargetBarHeight" },
    { page = "uf_focus", width = "castbarFocusBarWidth", height = "castbarFocusBarHeight" },
    { page = "uf_boss", width = "bossCastbarWidth", height = "bossCastbarHeight" },
    { page = "uf_arena", width = "arenaCastbarWidth", height = "arenaCastbarHeight" },
}
local checked = 0
for _, spec in ipairs(CASTBARS) do
    if M.pages[spec.page] and FRESH[spec.width] ~= nil then
        local entry = Select(spec.page)
        local width = FindControl(entry, "slider", "general." .. spec.width)
        local height = FindControl(entry, "slider", "general." .. spec.height)
        if width and height then
            local savedW, savedH = general[spec.width], general[spec.height]
            general[spec.width], general[spec.height] = nil, nil
            Check(width._msuf2CommandAction.get() == FRESH[spec.width], spec.page .. ": an unset castbar width reads "
                .. tostring(width._msuf2CommandAction.get()) .. ", a fresh profile holds " .. tostring(FRESH[spec.width]))
            Check(height._msuf2CommandAction.get() == FRESH[spec.height], spec.page .. ": an unset castbar height reads "
                .. tostring(height._msuf2CommandAction.get()) .. ", a fresh profile holds " .. tostring(FRESH[spec.height]))
            general[spec.width], general[spec.height] = savedW, savedH
            checked = checked + 1
        end
    end
end
-- Every client has the player and target castbars; Vanilla has no focus.
Check(checked >= 2, "only " .. checked .. " castbar pages built their size sliders")

print(string.format("menu_default_drift_smoke %s: ok (navigation icons; %d castbar size pairs read their seeded defaults)",
    flavor, checked))
