-- group_class_priority_drag_smoke.lua <repoRoot> <flavor>
--
-- The Group Layout class priority list inserts a dropped class at the drop
-- slot (owner decision 2026-10-17): the classes in between close up and keep
-- their order, and the saved classOrder follows. It used to swap the dropped
-- class with the one standing there, so moving Evoker to third sent Hunter to
-- the end of the list. Drops go through the real row OnDragStop handler of the
-- real page; the expected order is an independent remove/insert model.
--
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_fonts" })
local M, UP = mw.M, mw.M.UnitPage
local Shared = M.UnitSectionsShared
local function Check(ok, message)
    if not ok then error("group_class_priority_drag_smoke: " .. message, 2) end
end

local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
if flavor == "Mists" or flavor == "Mainline" then tokens[#tokens + 1] = "DEATHKNIGHT"; tokens[#tokens + 1] = "MONK" end
if flavor == "Mainline" then tokens[#tokens + 1] = "DEMONHUNTER"; tokens[#tokens + 1] = "EVOKER" end
mw.env.CLASS_SORT_ORDER = tokens

local classRows
local Rows = Shared.MakeDragSortRows
Shared.MakeDragSortRows = function(parent, defs, opts)
    local holder = Rows(parent, defs, opts)
    if type(opts) == "table" and opts.controlPath == "sorting.class_priority" then classRows = holder end
    return holder
end

mw:Select("opt_fonts")
local Lazy = UP.BuildSectionLazy
UP.BuildSectionLazy = nil
M.InvalidatePage("gf_layout")
M.BuildPageEntry("gf_layout", true)
mw:RunTimers(20000)
UP.BuildSectionLazy = Lazy
Shared.MakeDragSortRows = Rows
local entry = assert(M.cache.gf_layout, "gf_layout page not built")
local body = assert(entry.sections.sorting, "no sorting section")
body._msuf2CollapsibleEntry.SetOpenImmediate(true)
mw:RunTimers(20000)
Check(classRows and #classRows.rows == #tokens, flavor .. ": class priority rows missing")

local conf = M.GroupPage.Conf(M.GroupPage.CurrentScope())
conf.sortClassPriority = true
M.RunEntryRefreshers(M.cache.gf_layout, { force = true })
Check(classRows._enabled, "Use class priority no longer enables the rows")

local function Shown()
    local order = {}
    for _, row in ipairs(classRows.rows) do order[row.slotIndex] = row.key end
    return order
end
local expected = Shown()
Check(#expected == #tokens, "class rows do not fill one slot each")

-- Drop the row of `key` with its centre on `slot` (rows are 22 px + 4 px gap).
local function Drop(key, slot)
    local row
    for _, candidate in ipairs(classRows.rows) do
        if candidate.key == key then row = candidate end
    end
    Check(row ~= nil, "no row for " .. key)
    for index, value in ipairs(expected) do
        if value == key then table.remove(expected, index) break end
    end
    table.insert(expected, slot, key)
    classRows.GetTop = function() return 0 end
    row.frame.GetCenter = function() return 0, -((slot - 1) * 26) - 11 end
    MenuWorld.FireScript(row.frame, "OnDragStop")
    mw:RunTimers(20000)
    local want, shown = table.concat(expected, ","), table.concat(Shown(), ",")
    Check(shown == want, ("drop %s on %d:\n  expected %s\n  shown    %s"):format(key, slot, want, shown))
    Check(conf.classOrder == want, ("drop %s on %d saved %s"):format(key, slot, tostring(conf.classOrder)))
end

local last = #expected
Drop(expected[last], 3) -- up from the end: everything from slot 3 moves down one
Drop(expected[2], last - 1) -- down: the rows in between move up one
Drop(expected[1], 1) -- onto its own slot: nothing changes

print(("group_class_priority_drag_smoke: ok (%s, %d classes)"):format(flavor, #tokens))
