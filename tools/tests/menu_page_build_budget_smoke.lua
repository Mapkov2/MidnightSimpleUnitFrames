-- menu_page_build_budget_smoke.lua <repoRoot> [report]
--
-- Cost of the Menu2 page lifecycle, pinned with deterministic measures (never
-- wall-clock time) on the real Mainline core and Options graph:
--   * build:    Lua VM instructions to build a page from scratch (invalidate,
--               select, run the deferred construction timers);
--   * refresh:  instructions for one forced run of the page's refreshers;
--   * relayout: instructions and kilobytes for an unchanged accordion relayout
--               (it must allocate nothing: it runs on every disclosure, resize
--               settle and visible-page settle);
--   * select:   instructions to show the cached page again.
-- Instructions are counted in thousands (at a 100-instruction hook
-- granularity), kilobytes with the
-- collector stopped. Budgets sit 2% above the 2026-10-01 baseline (review
-- C5.2/C5.9 and the Widgets split must not make the menu slower); a lower
-- cost after a fix keeps the old budget until the next deliberate re-measure.
-- Pass "report" to print the measurements.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local report = arg[2] == "report"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_page_build_budget_smoke: " .. message, 2) end
    return condition
end

-- Budgets in thousands of instructions (relayout also in KB) per page: the
-- 1908d740 baseline plus 2%. Relayout budgets stay at the baseline (its
-- 100-instruction granularity makes 2% meaningless) and its allocation at
-- zero since the field-wise relayout comparison (C5.9).
local BUDGETS = {
    opt_colors = { build = 3352, refresh = 78.9, relayout = 0.8, relayoutKB = 0.05, select = 111.0 },
    opt_bars = { build = 1540, refresh = 108.7, relayout = 0.5, relayoutKB = 0.05, select = 117.9 },
    opt_misc = { build = 572, refresh = 23.1, relayout = 0.5, relayoutKB = 0.05, select = 32.1 },
    uf_player = { build = 1085, refresh = 35.8, relayout = 0.8, relayoutKB = 0.05, select = 52.7 },
    gf_layout = { build = 1302, refresh = 30.6, relayout = 1.0, relayoutKB = 0.05, select = 45.3 },
    gf_auras = { build = 1834, refresh = 117.1, relayout = 0.2, relayoutKB = 0.05, select = 133.1 },
    classpower = { build = 864, refresh = 19.6, relayout = 0.6, relayoutKB = 0.05, select = 35.1 },
    home = { build = 137, refresh = 1.0, relayout = 0.1, relayoutKB = 0.05, select = 14.0 },
}
local ORDER = { "opt_colors", "opt_bars", "opt_misc", "uf_player", "gf_layout", "gf_auras", "classpower", "home" }

local mw = MenuWorld.Open(root, "Mainline", { page = "opt_fonts" })
local M = mw.M

local ticks = 0
local function Tick() ticks = ticks + 1 end
local function Count(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    ticks = 0
    local before = collectgarbage("count")
    debug.sethook(Tick, "", 100)
    fn()
    debug.sethook()
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    return ticks / 10, kb
end
local function Builders(entry)
    local list, seen = {}, {}
    for _, body in pairs(entry.sections or {}) do
        local section = body and body._msuf2CollapsibleEntry
        local builder = section and section.builder
        if builder and not seen[builder] then
            seen[builder] = true
            list[#list + 1] = builder
        end
    end
    return list
end

local lines, failures = {}, {}
for _, key in ipairs(ORDER) do
    local budget = BUDGETS[key]
    -- Warm: the first build pays one-time costs (fonts, shared previews).
    mw:Select(key)
    mw:Select("opt_fonts")
    local build = Count(function()
        M.InvalidatePage(key)
        M.SelectPage(key)
        mw:RunTimers()
    end)
    local entry = Check(M.cache[key], key .. " was not built")
    local refresh = Count(function() M.RunEntryRefreshers(entry, { force = true }) end)
    local builders = Builders(entry)
    for i = 1, #builders do builders[i]:RelayoutCollapsibles() end
    local relayout, relayoutKB = Count(function()
        for i = 1, #builders do builders[i]:RelayoutCollapsibles() end
    end)
    mw:Select("opt_fonts")
    M.MarkMenuDataDirty("budget")
    local select = Count(function() M.SelectPage(key) end)
    mw:RunTimers()
    local measured = { build = build, refresh = refresh, relayout = relayout, relayoutKB = relayoutKB, select = select }
    lines[#lines + 1] = string.format("%-11s build %7.1fk  refresh %6.1fk  relayout %5.1fk %6.1f KB  select %6.1fk",
        key, build, refresh, relayout, relayoutKB, select)
    for field, value in pairs(measured) do
        local limit = budget[field]
        if limit and limit > 0 and value > limit then
            failures[#failures + 1] = string.format("%s %s: %s over budget %s", key, field,
                string.format(field == "relayoutKB" and "%.1f KB" or "%.1fk", value), tostring(limit))
        end
    end
end
if report then for _, line in ipairs(lines) do print(line) end end
table.sort(failures)
Check(#failures == 0, "page lifecycle cost regressed:\n  " .. table.concat(failures, "\n  ") .. "\n" .. table.concat(lines, "\n"))
---------------------------------------------------------------------------
-- Work that must not repeat per refresh (review C5.9)
---------------------------------------------------------------------------
-- The persisted menu state resolves once per selection, not once per
-- accordion section (it re-exported the GlobalDB and walked every state
-- field each time).
local ensureCalls, tableCalls = 0, 0
local Ensure, GetTable = M.EnsurePersistentMenuState, M.GetPersistentMenuStateTable
M.EnsurePersistentMenuState = function(...) ensureCalls = ensureCalls + 1; return Ensure(...) end
M.GetPersistentMenuStateTable = function(...) tableCalls = tableCalls + 1; return GetTable(...) end
M.InvalidatePage("opt_misc")
mw:Select("opt_misc")
M.EnsurePersistentMenuState, M.GetPersistentMenuStateTable = Ensure, GetTable
local sectionCount = 0
for _, body in pairs(M.cache.opt_misc.sections or {}) do
    if body._msuf2CollapsibleEntry then sectionCount = sectionCount + 1 end
end
Check(sectionCount >= 6, "opt_misc built only " .. sectionCount .. " accordion sections")
-- SelectPage resolves it once itself; the builder and its sections reuse it.
Check(ensureCalls == 0 and tableCalls < sectionCount, string.format(
    "a page build resolved the persisted menu state again per section (%d ensure, %d table reads, %d sections)",
    ensureCalls, tableCalls, sectionCount))
-- An unchanged badge set re-anchors nothing; a changed one re-lays the header once.
local section
for _, body in pairs(M.cache.opt_misc.sections or {}) do
    if body._msuf2CollapsibleEntry and not body._msuf2CollapsibleEntry._msuf2UXSummary then section = body break end
end
section = Check(section, "opt_misc has no plain accordion section")
local entry = section._msuf2CollapsibleEntry
local relayouts = 0
local RefreshLayout = entry._msuf2RefreshLayout
entry._msuf2RefreshLayout = function(...) relayouts = relayouts + 1; return RefreshLayout(...) end
local W = M.Widgets
local specs = { { text = "Smoke", kind = "ok", showWhenClosed = true } }
W.SetCollapsibleBadges(section, specs)
relayouts = 0
for _ = 1, 5 do W.SetCollapsibleBadges(section, specs) end
Check(relayouts == 0, relayouts .. " header re-layouts for an unchanged badge set")
W.SetCollapsibleBadges(section, { { text = "Smoke changed", kind = "ok", showWhenClosed = true } })
Check(relayouts == 1, "a changed badge did not re-lay the header once")
W.SetCollapsibleBadges(section, {})
Check(relayouts == 2, "removing the badges did not re-lay the header")
entry._msuf2RefreshLayout = RefreshLayout

print(string.format("menu_page_build_budget_smoke: ok (%d pages: build, refresh, relayout and cached select within budget; state and badges resolve once)", #ORDER))
