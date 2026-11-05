-- Real first-open navigation input: pending feedback precedes all search work.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { open = false, clientScriptBindings = true })
local M, env = mw.M, mw.env
local palettes, create = {}, M.CreateNavSearchPalette
M.CreateNavSearchPalette = function(...)
    local palette = create(...)
    palettes[#palettes + 1] = palette
    return palette
end
assert(M.Open("home") ~= false)
mw:RunTimers()
MenuWorld.FireVisibilityScripts(M.frame)
local box = M.nav.searchBox
local palette
for _, item in ipairs(palettes) do if item.searchBox == box then palette = item end end
assert(palette, "navigation suggestions were not created")
local clock = 0
env.debugprofilestop = function() clock = clock + 0.05; return clock end
local function Type(text)
    box:SetText(text)
    MenuWorld.FireScript(box, "OnTextChanged", true)
end
local function Drain()
    for _ = 1, 40 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search did not finish")
end
local function Busy(indicator, expected, label)
    assert(indicator, label .. ": missing visible loading indicator")
    assert(indicator:IsShown() == expected, label .. ": wrong indicator visibility")
    assert(indicator.animation:IsPlaying() == expected, label .. ": wrong animation state")
end

Type("castbar")
local spinner = palette.busyIndicator
Busy(spinner, true, "cold keystroke before timers")
assert(M.searchResultsPending and not M.Search.StaticIndex.IsDecoded(), "test warmed the index before feedback")
assert(palette.status:IsShown() and palette.status:GetText() == M.Tr("Searching settings..."), "pending label missing")
assert(spinner.animation.looping == "REPEAT", "loading animation must repeat")
local rotation = spinner.animation.animations[1]
assert(rotation.degrees == -360 and rotation.duration == 1, "loading circle must rotate continuously")
assert(M.Theme._menuAnimationGroups[spinner.animation], "animation must participate in menu shutdown")
assert(spinner:GetScript("OnUpdate") == nil, "loading indicator must not poll in Lua")
Type("font")
assert(palette.busyIndicator == spinner, "typing allocated another indicator")
Busy(spinner, true, "replacement query")
Drain()
assert(#M.searchResults > 0 and M.searchResultsQuery == "font", "latest query did not produce results")
Busy(spinner, false, "results ready")
Type("zzzxqvvzzz")
Drain()
assert(#M.searchResults == 0, "no-result fixture unexpectedly matched")
Busy(spinner, false, "no matches")
Type("castbar")
MenuWorld.FireScript(box, "OnEscapePressed")
Busy(spinner, false, "escape")
Drain()
Busy(spinner, false, "cancelled callbacks")
Type("castbar")
Type("")
Busy(spinner, false, "empty query")
Drain()

env.MSUF_DB.general.reduceMotion = true
Type("castbar")
assert(spinner:IsShown() and not spinner.animation:IsPlaying(), "reduced motion must keep a static busy indication")
env.MSUF_DB.general.reduceMotion = nil
Type("font")
Busy(spinner, true, "motion restored")
M.HideSlashMenuAndMinibar(M.frame)
Busy(spinner, false, "closed menu")
Drain()
assert(M.MenuRuntime:PendingTaskCount() == 0, "closed menu retained search tasks")
assert(M.Open("home") ~= false)
Drain()
Type("castbar")
Busy(spinner, true, "reopened navigation")
M.MenuRuntime:Quiesce("combat", "PLAYER_REGEN_DISABLED")
Busy(spinner, false, "combat quiesce")
Drain()
M.IsConfigCombatLocked("PLAYER_REGEN_ENABLED")
M.MenuRuntime:Resume("test")

-- Example/Enter results use the same indicator, with enough space for text.
M.Search._CoreAPI.OpenSearchResults("castbar")
local view = assert(M.cache.search._msuf2SearchView)
Busy(view.busyIndicator, true, "full results pending")
local fullSpinner = view.busyIndicator
Drain()
Busy(fullSpinner, false, "full results ready")
Type("font")
Busy(spinner, true, "navigation over full page")
Busy(fullSpinner, true, "full page follows navigation")
palette:Hide()
Busy(spinner, false, "navigation click-off")
Busy(fullSpinner, false, "full page click-off")
assert(not view.status:IsShown(), "cancelled query still claims to be searching")
Drain()
M.Search._CoreAPI.OpenSearchResults("castbar")
Drain()
assert(view.rows[1].button:IsShown(), "indicator displaced actual search results")
M.Search._CoreAPI.OpenSearchResults("font")
Busy(fullSpinner, true, "repeated full-page search")
assert(view.busyIndicator == fullSpinner, "full page allocated a repeated indicator")
Type("")
Busy(fullSpinner, false, "full page cleared query")
Drain()
M.Search._CoreAPI.OpenSearchResults("castbar")
Busy(fullSpinner, true, "full page restarted")
Type("x")
Busy(fullSpinner, false, "full page short query")
Drain()
M.Search._CoreAPI.OpenSearchResults("font")
Busy(fullSpinner, true, "full page before close")
M.HideSlashMenuAndMinibar(M.frame)
Busy(fullSpinner, false, "full page closed")
Drain()
assert(M.MenuRuntime:PendingTaskCount() == 0, "spinner left a timer after close")
print("search_busy_indicator_smoke " .. flavor .. ": pending/results/cancel/close/combat/reduced-motion passed")
