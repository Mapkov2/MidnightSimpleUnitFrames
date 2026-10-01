-- menu_refresh_queue_smoke.lua <repoRoot> <flavor>
--
-- Queued menu work must survive the menu runtime cancelling it. Every delayed
-- Menu2 task goes through M.MenuTimer, and the runtime cancels all of them
-- when the menu hides or combat starts. A "queued" flag kept beside such a task
-- stayed set once its task was cancelled, so every later request returned
-- early and the work never ran again for the session:
--   * M.RequestRefresh for a page entry and for the active page;
--   * the coalesced whole-menu refresh (M.QueueMenuRefresh), used by history;
--   * the two ownership checks of a docked preview box (W.AttachPinnedPreview).
-- A request refused during combat lockdown must not stick either.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_refresh_queue_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "profiles" })
local M, world = mw.M, mw.world
local runtime = Check(M.MenuRuntime, "the menu runtime is missing")
mw:Select("profiles")
local entry = Check(M.cache and M.cache.profiles, "the profiles page was not built")
local runs = 0
entry.refreshers[#entry.refreshers + 1] = function() runs = runs + 1 end

local function CancelAll(reason) runtime:CancelPendingTasks(reason) end

---------------------------------------------------------------------------
-- 1. RequestRefresh for a page entry
---------------------------------------------------------------------------
Check(M.RequestRefresh({ entry = entry }, "smoke") == true, "a page refresh request was refused")
CancelAll("smoke-hide")
mw:RunTimers()
Check(runs == 0, "a cancelled page refresh still ran")
M.RequestRefresh({ entry = entry }, "smoke")
mw:RunTimers()
Check(runs == 1, "a page refresh requested after a cancelled one never ran (stuck queued flag)")

---------------------------------------------------------------------------
-- 2. RequestRefresh for the active page (no entry known to the caller)
---------------------------------------------------------------------------
local activeKey, cached = M.activeKey, M.cache[M.activeKey]
-- No entry resolves while the request is made, so the active-page branch runs;
-- the active page is resolved again when the task fires.
M.activeKey = nil
M.RequestRefresh(nil, "smoke")
M.activeKey = activeKey
CancelAll("smoke-hide")
mw:RunTimers()
Check(runs == 1, "a cancelled active-page refresh still ran")
M.activeKey = nil
M.RequestRefresh(nil, "smoke")
M.activeKey = activeKey
mw:RunTimers()
Check(runs == 2 and M.cache[activeKey] == cached, "an active-page refresh after a cancelled one never ran (stuck queued flag)")

---------------------------------------------------------------------------
-- 3. The coalesced whole-menu refresh
---------------------------------------------------------------------------
Check(type(M.QueueMenuRefresh) == "function", "M.QueueMenuRefresh is missing")
M.QueueMenuRefresh()
M.QueueMenuRefresh()
CancelAll("smoke-hide")
mw:RunTimers()
Check(runs == 2, "a cancelled menu refresh still ran")
M.QueueMenuRefresh()
M.QueueMenuRefresh()
mw:RunTimers()
Check(runs == 3, "a menu refresh queued after a cancelled one did not run exactly once")
M.QueueMenuRefresh()
M.CancelQueuedMenuRefresh()
mw:RunTimers()
Check(runs == 3, "CancelQueuedMenuRefresh did not cancel the queued refresh")
M.QueueMenuRefresh()
mw:RunTimers()
Check(runs == 4, "a menu refresh after CancelQueuedMenuRefresh never ran")

---------------------------------------------------------------------------
-- 4. A request refused in combat lockdown does not stick
---------------------------------------------------------------------------
world.widgets:SetCombat(true)
M.RequestRefresh({ entry = entry }, "smoke")
M.QueueMenuRefresh()
world.widgets:SetCombat(false)
mw:RunTimers()
Check(runs == 4, "menu refresh work ran although it was requested during lockdown")
M.RequestRefresh({ entry = entry }, "smoke")
mw:RunTimers()
Check(runs == 5, "a page refresh after a combat-refused one never ran")
M.QueueMenuRefresh()
mw:RunTimers()
Check(runs == 6, "a menu refresh after a combat-refused one never ran")

---------------------------------------------------------------------------
-- 5. The docked preview box ownership checks
---------------------------------------------------------------------------
local W = Check(M.Widgets, "M.Widgets is missing")
local env = mw.env
local body = env.CreateFrame("Frame", nil, entry.wrapper)
local box = env.CreateFrame("Frame", nil, entry.wrapper)
local syncs = 0
local function Attach()
    local record = Check(W.AttachPinnedPreview(body, box, { pageKey = activeKey, wrapper = entry.wrapper }),
        "the preview box did not attach")
    record.update = function() syncs = syncs + 1 end
end
Attach()
CancelAll("smoke-hide")
mw:RunTimers()
Check(syncs == 0, "a cancelled preview ownership check still ran")
Attach()
mw:RunTimers()
Check(syncs == 2, "the preview ownership checks after cancelled ones did not run (stuck queued flags), ran " .. syncs)

---------------------------------------------------------------------------
-- 6. A profile apply repaints cached pages (C5.8)
---------------------------------------------------------------------------
-- MSUF.ProfileRuntime.Apply calls the menu's RebaseHistoryForProfileChange
-- after every profile switch, reset, import and variant context change; a
-- cached page skips its refreshers while the menu data revision is unchanged.
local runtimeSource = assert(io.open(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileRuntime.lua", "rb")):read("*a")
Check(runtimeSource:find("RebaseHistoryForProfileChange", 1, true), "ProfileRuntime no longer notifies the menu after a profile apply")
mw:Select("opt_misc")
local misc = Check(M.cache.opt_misc, "the misc page was not built")
local miscRuns = 0
misc.refreshers[#misc.refreshers + 1] = function() miscRuns = miscRuns + 1 end
mw:Select("opt_fonts")
mw:Select("opt_misc")
local settled = miscRuns
mw:Select("opt_fonts")
mw:Select("opt_misc")
Check(miscRuns == settled, "a cached page reran its refreshers without a data change")
mw:Select("opt_fonts")
local fontsRuns = 0
M.cache.opt_fonts.refreshers[#M.cache.opt_fonts.refreshers + 1] = function() fontsRuns = fontsRuns + 1 end
-- Another profile becomes active outside the menu (slash command, spec swap).
local switched = mw.core.ProfileFields.CopySnapshot(env.MSUF_DB)
env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] = switched
env.MSUF_DB = switched
M.RebaseHistoryForProfileChange()
mw:RunTimers()
Check(fontsRuns >= 1, "the visible page was not refreshed after a profile apply")
mw:Select("opt_misc")
Check(miscRuns == settled + 1, "a cached page showed the previous profile's values after a profile apply")

print(string.format("menu_refresh_queue_smoke: ok (%s: page, active-page, whole-menu and preview checks re-queue after cancel and lockdown; profile applies repaint cached pages)", flavor))
