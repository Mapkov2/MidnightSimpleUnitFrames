-- search_exact_route_sections_smoke.lua <repoRoot> [flavor]
--
-- Exact search navigation into closed lazy accordion sections
-- (UnitPage.BuildSectionLazy), on one client's real core and Options graph with
-- the menu open:
--   * a static index row carries no route; opening it still builds the closed
--     section's content, opens the section, resolves the exact control and
--     highlights it, on a cold page and on the cached page;
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

local function Open()
    local mw = MenuWorld.Open(root, flavor, { locale = "enUS" })
    mw.env.InCombatLockdown = function() return false end
    mw.env.UnitAffectingCombat = function() return false end
    return mw
end

-- The row the result list shows for a typed control name.
local function StaticRow(M, label)
    for _, rec in ipairs(M.Search._CoreAPI.SearchPages(label)) do
        if rec.label == label and rec.static == true and rec.exactTarget then return rec end
    end
end

-- What Search_Render's OpenResultRow passes for that row.
local function OpenRow(mw, rec, query)
    local M = mw.M
    local cached = M.cache[rec.key]
    if cached and cached.wrapper then cached.wrapper._msuf2SearchHighlight = nil end
    local selected, anchored, exact = M.Search.OpenTarget(rec.key, query, rec.anchorFallback or rec.label,
        rec.anchor, rec.route, rec.exactTarget)
    mw:RunTimers()
    local entry = M.cache[rec.key]
    local section = entry and entry.sections and entry.sections[rec.exactTarget.sectionId]
    local collapsible = section and section._msuf2CollapsibleEntry
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget(rec.key, rec.exactTarget)
    local highlight = entry and entry.wrapper and entry.wrapper._msuf2SearchHighlight
    return {
        selected = selected, anchored = anchored, exact = exact, entry = entry,
        open = collapsible and collapsible.open == true, widget = widget,
        highlighted = highlight ~= nil and highlight:IsShown() == true,
    }
end

local function Describe(result)
    return ("selected=%s anchored=%s exact=%s open=%s widget=%s highlighted=%s"):format(tostring(result.selected),
        tostring(result.anchored), tostring(result.exact), tostring(result.open), tostring(result.widget ~= nil),
        tostring(result.highlighted))
end

local function Reached(result)
    return result.selected and result.anchored and result.exact == true and result.open and result.widget ~= nil
        and result.highlighted
end

---------------------------------------------------------------------------
-- A static row whose control sits in a closed lazy section (Castbar >
-- Interrupt Ready Indicator, closed by default): cold page, then the cached
-- page after the section was closed again.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    local label = "Show on Target castbar"
    local rec = StaticRow(M, label)
    if Check(rec ~= nil, "no static result for '" .. label .. "'") then
        Check(rec.exactTarget.sectionId == "castbar_interrupt_ready", "the row names section "
            .. tostring(rec.exactTarget.sectionId))
        Check(rec.route == nil, "the static row now carries a route; this smoke covers rows without one")
        Check(M.cache[rec.key] == nil, "the castbar page was built before the search opened it")
        local cold = OpenRow(mw, rec, label)
        Check(Reached(cold), "cold page: the static row did not reach its control (" .. Describe(cold) .. ")")
        local section = cold.entry and cold.entry.sections[rec.exactTarget.sectionId]
        local collapsible = section and section._msuf2CollapsibleEntry
        if collapsible and collapsible.open then collapsible.SetOpenImmediate(false) end
        mw:Select("home")
        local warm = OpenRow(mw, rec, label)
        Check(warm.entry == cold.entry, "the cached castbar page was replaced")
        Check(Reached(warm), "cached page: the static row did not reach its control (" .. Describe(warm) .. ")")
    end
end

---------------------------------------------------------------------------
-- A route that opens a closed section of the cached page (provider rows,
-- changelog links, query routes) opens it in place: the page is not
-- invalidated, its entry and wrapper stay, the section builds and the exact
-- control resolves. A route-only hop (no exact target) opens its section too.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    local label = "Hide profession casts"
    local rec = StaticRow(M, label)
    Check(mw:Select("opt_castbar") ~= false, "the castbar page did not open")
    local entry = M.cache.opt_castbar
    local invalidated = 0
    local invalidate = M.InvalidatePage
    M.InvalidatePage = function(key, ...)
        if key == "opt_castbar" then invalidated = invalidated + 1 end
        return invalidate(key, ...)
    end
    if Check(rec ~= nil and entry ~= nil, "no static result for '" .. label .. "' or no castbar page") then
        local sectionId = rec.exactTarget.sectionId
        local shell = entry.sections[sectionId]
        Check(shell and shell._msuf2CollapsibleEntry and shell._msuf2CollapsibleEntry.open ~= true,
            "section " .. tostring(sectionId) .. " is not a closed accordion on the fresh page")
        local wrapper = entry.wrapper
        local result = OpenRow(mw, { key = rec.key, label = rec.label, exactTarget = rec.exactTarget,
            route = { accordion = { [rec.key .. ":" .. sectionId] = true } } }, label)
        Check(invalidated == 0, "the routed hop invalidated the cached page " .. invalidated .. " time(s)")
        Check(M.cache.opt_castbar == entry and entry.wrapper == wrapper and wrapper:GetParent() ~= nil,
            "the routed hop replaced the cached page tree")
        Check(Reached(result), "routed hop: the control was not reached (" .. Describe(result) .. ")")
    end
    local textures = entry and entry.sections.castbar_textures
    local collapsible = textures and textures._msuf2CollapsibleEntry
    if Check(collapsible and collapsible.open ~= true, "Textures & Outline is not a closed section") then
        M.Search.OpenTarget("opt_castbar", "outline", "outline", nil, { accordion = { ["opt_castbar:castbar_textures"] = true } })
        mw:RunTimers()
        Check(M.cache.opt_castbar == entry and collapsible.open == true and invalidated == 0,
            "a route-only hop did not open its section in place")
        local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("opt_castbar",
            { pageKey = "opt_castbar", sectionId = "castbar_textures", settingKey = "general.castbarTexture",
                controlId = "menu2.opt.castbar.global.textures.castbar.texture" })
        Check(widget ~= nil, "the section a route opened in place did not build its controls")
    end
    M.InvalidatePage = invalidate
end

---------------------------------------------------------------------------
-- Visible page builds park no closed-section job for a background pump:
-- search never pumps (search_navigation_only_smoke), so each parked job only
-- pinned its replaced page entry for the session. Rebuilds and searches leave
-- the queue empty, and a pump builds nothing.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    local function Upvalue(fn, name)
        for i = 1, 255 do
            local upName, value = debug.getupvalue(fn, i)
            if upName == nil then return nil end
            if upName == name then return value end
        end
    end
    local pump = Upvalue(M.UnitPage.PumpBackgroundSections, "PumpHiddenSectionQueue")
    local queue = pump and Upvalue(pump, "hiddenSectionQueue")
    if Check(type(queue) == "table", "the lazy section queue was not found") then
        for _ = 1, 3 do
            M.InvalidatePage("uf_player")
            mw:Select("uf_player")
            M.Search._CoreAPI.SearchPages("health")
            mw:RunTimers()
        end
        Check(#queue == 0, "three visible builds of uf_player parked " .. #queue .. " section jobs")
        local frames = mw:Frames()
        M.UnitPage.PumpBackgroundSections()
        mw:RunTimers()
        Check(mw:Frames() == frames, "a background pump built " .. (mw:Frames() - frames) .. " frames of closed sections")
    end
end

if #failures > 0 then
    error("search_exact_route_sections_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("search_exact_route_sections_smoke: ok (" .. flavor .. "; static rows reach controls in closed lazy sections,"
    .. " routes open sections of the cached page in place, visible builds park no section jobs)")
