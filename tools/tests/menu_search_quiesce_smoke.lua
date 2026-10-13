-- menu_search_quiesce_smoke.lua <repoRoot> <flavor>
--
-- Menu search keeps two pieces of transient state that a menu quiesce (close or
-- combat) has to settle, because the timers that would have settled them are
-- cancelled with every other MenuTimer task:
--   * a first search cut off before it ran left an empty result list labelled
--     with its own query, so the next paint showed "No exact setting found" for a
--     query that was never answered. The label is forgotten and the next paint
--     searches again;
--   * the one-time search introduction closes itself on a 10 second task. A quiesce
--     cancels that task, so it closes at once, and it still closes on its timer
--     when nothing interrupts it.
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

local function Open()
    local mw = MenuWorld.Open(root, flavor, { page = "home" })
    mw.env.InCombatLockdown = function() return false end
    mw.env.UnitAffectingCombat = function() return false end
    return mw
end

local QUERY = "health"

-- Shows the search page again the way the client does after a reopen: the page
-- wrapper's OnShow repaints it.
local function Repaint(mw)
    local entry = mw.M.cache.search
    Check(entry ~= nil and entry.wrapper ~= nil, "the search page was not built")
    if not (entry and entry.wrapper) then return nil end
    MenuWorld.FireScript(entry.wrapper, "OnShow")
    return entry._msuf2SearchView
end

local function CheckAnswered(mw, context)
    local M = mw.M
    local view = Repaint(mw)
    if not view then return end
    Check(#(M.searchResults or {}) > 0, context .. ": the interrupted query '" .. QUERY .. "' stayed unanswered")
    local status = tostring(view.status:GetText())
    Check(not status:find("No exact setting", 1, true), context .. ": the page says '" .. status .. "'")
    Check(not status:find("Searching", 1, true), context .. ": the page still says '" .. status .. "'")
    Check(M.searchResultsPending ~= true, context .. ": the search is still pending")
end

---------------------------------------------------------------------------
-- 1. Closing the menu before the first search ran.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    M.Search.ScheduleInputQuery(M.nav.searchBox, QUERY, true, nil)
    Check(M.searchResultsPending == true and M.activeKey == "search", "the search was not scheduled")
    M.frame:Hide()
    mw:RunTimers()
    Check(M.searchResultsPending ~= true, "closing the menu left the search pending")
    M.frame:Show()
    mw:RunTimers()
    CheckAnswered(mw, "close")
end

---------------------------------------------------------------------------
-- 2. Combat starting before the first search ran.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    M.Search.ScheduleInputQuery(M.nav.searchBox, QUERY, true, nil)
    mw.world.widgets:SetCombat(true)
    mw.env.InCombatLockdown = function() return true end
    M.MenuRuntime:Quiesce("combat", "PLAYER_REGEN_DISABLED")
    mw:RunTimers()
    mw.world.widgets:SetCombat(false)
    mw.env.InCombatLockdown = function() return false end
    Check(M.searchResultsPending ~= true, "combat left the search pending")
    CheckAnswered(mw, "combat")
end

---------------------------------------------------------------------------
-- 3. A finished search keeps its answer through a quiesce.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    -- The scheduled run answers only while the box still holds its query.
    M.nav.searchBox._msuf2SearchInternal = true
    M.nav.searchBox:SetText(QUERY)
    M.nav.searchBox._msuf2SearchInternal = nil
    M.Search.ScheduleInputQuery(M.nav.searchBox, QUERY, true, nil)
    mw:RunTimers()
    local answered = #(M.searchResults or {})
    Check(answered > 0 and M.searchResultsPending ~= true, "the query did not finish when its timers ran")
    local label = M.searchResultsQuery
    M.MenuRuntime:Quiesce("menu-hide")
    Check(M.searchResultsQuery == label and #(M.searchResults or {}) == answered,
        "a quiesce discarded the answer of a finished search")
end

---------------------------------------------------------------------------
-- 4. The search introduction closes on its timer, and on a quiesce.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    local box = M.nav.searchBox
    local function ShowIntro()
        M.SetSearchIntroSeen(false)
        MenuWorld.FireScript(box, "OnEditFocusGained")
        local intro = box:GetParent()._msuf2SearchIntro
        Check(intro ~= nil and intro:IsShown(), "focusing the empty search box did not show the introduction")
        return intro
    end

    local intro = ShowIntro()
    if intro then
        mw:RunTimers()
        Check(not intro:IsShown(), "the introduction did not close on its 10 second timer")
    end

    intro = ShowIntro()
    if intro then
        M.frame:Hide()
        Check(not intro:IsShown(), "closing the menu left the introduction open (its timer task was cancelled)")
        mw:RunTimers()
        M.frame:Show()
        Check(not intro:IsShown(), "the introduction was open again after reopening the menu")
    end

    intro = ShowIntro()
    if intro then
        M.MenuRuntime:Quiesce("combat", "PLAYER_REGEN_DISABLED")
        Check(not intro:IsShown(), "a combat quiesce left the introduction open")
    end
end

if #failures > 0 then
    error("menu_search_quiesce_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_search_quiesce_smoke: " .. flavor .. " ok (an interrupted first search is answered on the next paint,"
    .. " the search introduction closes on a quiesce)")
