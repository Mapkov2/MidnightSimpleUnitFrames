-- Generic appended page providers: real Gameplay build, cache, reset and undo.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local combat, regenEdge = false, false
local mw = MenuWorld.Open(root, flavor, { page = "gameplay", beforeCore = function(world)
    world.env.InCombatLockdown = function() return combat end
    world.env.UnitAffectingCombat = function(unit) return unit == "player" and (combat or regenEdge) end
end })
local M, core, env = mw.M, mw.core, mw.env
local checks = 0
local function Check(ok, message)
    assert(ok, "host_page_extension_smoke " .. flavor .. ": " .. message)
    checks = checks + 1
    return ok
end
local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local originalPage = M.pages.gameplay
local originalBuild = originalPage.build
local originalEntry = M.cache.gameplay
local originalVersion = originalPage.version
local originalWarning = M.BuildPageResetWarning("gameplay")
Check(not M.HasPageExtension("gameplay"), "standalone host starts with an extension")
Check(not M.BuildPageExtensions("absent", {}, {}), "empty registry did work")
do
    local ctx, builder = {}, {}
    local function EmptyBuilds()
        for _ = 1, 1000 do M.BuildPageExtensions("absent", ctx, builder) end
    end
    EmptyBuilds()
    local best
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        EmptyBuilds()
        local used = collectgarbage("count") - before
        collectgarbage("restart")
        best = best and math.min(best, used) or used
    end
    Check(best < 0.1, "empty extension builds allocate")
end
Check(Count(originalEntry.sections) == 4, "standalone Gameplay must have four sections")
for _, key in ipairs({ "gameplay_timer", "gameplay_state", "gameplay_class_specific", "gameplay_crosshair" }) do
    Check(originalEntry.sections[key], "missing standalone section " .. key)
end

local events, builds, allowed, failPrepare, failReset = {}, 0, true, false, false
local external = { value = 8 }
local prepareValue
local function Log(event) events[#events + 1] = event end
local function ResetEvents() for i = #events, 1, -1 do events[i] = nil end end
Check(M.RegisterHistoryProvider("extension-smoke", function()
    return { value = external.value }
end, function(snapshot) external.value = snapshot.value end), "history provider registration failed")
local provider = {
    build = function(ctx, b)
        builds = builds + 1
        Check(ctx.key == "gameplay", "provider got another page context")
        Check(b.y < 0, "provider ran before host rows")
        b:CollapsibleSection("extension_smoke", "Extension smoke", 80, false)
    end,
    canReset = function() return allowed end,
    warning = function() return "Reset extension smoke settings." end,
    prepare = function()
        Log("prepare")
        Check(not M.IsHistoryCapturing(), "prepare must run before history")
        if prepareValue then external.value = prepareValue end
        return not failPrepare
    end,
    reset = function()
        Log("reset")
        Check(M.IsHistoryCapturing(), "extension reset is outside host history")
        external.value = 0
        if failReset then error("extension smoke reset failure") end
        return true
    end,
    finish = function()
        Log("finish")
        Check(not M.IsHistoryCapturing(), "finish ran inside host history")
    end,
}

-- Late registration invalidates the visible cached page, preserves the host
-- builder, and executes only one append even when the same id is registered.
Check(M.RegisterPageExtension("gameplay", "smoke", provider), "registration failed")
Check(M.HasPageExtension("gameplay", "smoke") and not M.HasPageExtension("gameplay", "missing"), "id lookup failed")
Check(M.pages.gameplay == originalPage and originalPage.build == originalBuild, "registration replaced the host page")
Check(originalPage.version == originalVersion + 1 and M.cache.gameplay ~= originalEntry, "visible cache stayed stale")
Check(Count(M.cache.gameplay.sections) == 5 and M.cache.gameplay.sections.extension_smoke, "append did not join Gameplay")
local currentEntry, built = M.cache.gameplay, builds
Check(M.RegisterPageExtension("gameplay", "smoke", provider), "duplicate registration failed")
Check(M.cache.gameplay == currentEntry and builds == built, "identical registration rebuilt the page")
Check(M.BuildPageResetWarning("gameplay") == originalWarning .. "\n\nReset extension smoke settings.", "warning lost core or extension scope")
Check(M.BuildPageResetWarning("opt_bars"):find("extension smoke", 1, true) == nil, "warning leaked into another page")
local bad = { build = provider.build, reset = "invalid" }
Check(not pcall(M.RegisterPageExtension, "gameplay", "smoke", bad), "malformed replacement accepted")
Check(M.cache.gameplay == currentEntry and M.HasPageExtension("gameplay", "smoke"), "malformed replacement changed registry")

-- The provider stores a callback snapshot, not the caller's mutable table.
local oldBuild = provider.build
provider.build = function(ctx, b)
    builds = builds + 1
    b:CollapsibleSection("extension_smoke_replaced", "Extension smoke", 80, false)
end
Check(M.RegisterPageExtension("gameplay", "smoke", provider), "replacement failed")
Check(Count(M.cache.gameplay.sections) == 5 and M.cache.gameplay.sections.extension_smoke_replaced, "replacement appended twice")
provider.build = oldBuild
Check(M.cache.gameplay.sections.extension_smoke_replaced, "provider mutation changed cached layout")

-- Registration in combat only changes the registry/version. It touches no
-- current wrapper; normal page selection retires that version after combat.
currentEntry, built = M.cache.gameplay, builds
combat = true
Check(M.RegisterPageExtension("gameplay", "smoke", provider), "combat registration failed")
Check(M.cache.gameplay == currentEntry and builds == built, "combat registration rebuilt frames")
combat = false
Check(M.SelectPage("gameplay") ~= false and M.cache.gameplay ~= currentEntry, "deferred cache did not rebuild")
Check(M.cache.gameplay.sections.extension_smoke and Count(M.cache.gameplay.sections) == 5, "replacement was not snapshotted")

-- The real core Gameplay reset and external saved settings share one undo
-- transaction, including state loaded during prepare inside an open session.
local F = core.ProfileFields
local factory = Check(F.CopySnapshot(M.EnsureDB()), "factory fixture is not copyable")
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local function Edit(marker, value)
    return M.CaptureHistory("Extension smoke edit", "smoke:edit", function()
        M.EnsureDB().gameplay.smokeResetMarker = marker
        external.value = value
        return true
    end)
end
local function UndoCount() return M.GetHistoryState().undoCount end
Check(Edit(42, 8), "initial edit failed")
prepareValue = 17
local before = UndoCount()
ResetEvents()
Check(M.ResetPageToDefaults("gameplay"), "composed reset failed")
Check(table.concat(events, ",") == "prepare,reset,finish", "reset lifecycle order changed")
Check(M.EnsureDB().gameplay.smokeResetMarker == nil and external.value == 0, "reset did not restore both owners")
Check(UndoCount() == before + 1 and not M.IsHistoryCapturing(), "reset was not one closed history entry")
Check(M.Undo() and M.EnsureDB().gameplay.smokeResetMarker == 42 and external.value == 17, "undo lost prepared or core state")
Check(M.Redo() and M.EnsureDB().gameplay.smokeResetMarker == nil and external.value == 0, "redo lost composed state")
prepareValue = nil

Check(Edit(55, 9), "refusal fixture edit failed")
before = UndoCount()
ResetEvents()
combat = true
Check(M.ResetPageToDefaults("gameplay") == false and #events == 0, "combat called extension reset")
combat, regenEdge = false, true
Check(M.ResetPageToDefaults("gameplay") == false and #events == 0, "combat edge called extension reset")
regenEdge = false
Check(M.EnsureDB().gameplay.smokeResetMarker == 55 and external.value == 9 and UndoCount() == before, "combat mutated settings/history")
failPrepare = true
Check(M.ResetPageToDefaults("gameplay") == false, "failed prepare did not abort")
Check(table.concat(events, ",") == "prepare" and external.value == 9, "failed prepare called reset/finish")
Check(M.EnsureDB().gameplay.smokeResetMarker == 55 and UndoCount() == before, "failed prepare mutated core/history")
failPrepare = false

-- An unavailable extension does not prevent the core reset or enter history.
allowed = false
Check(M.BuildPageResetWarning("gameplay") == originalWarning, "unavailable provider polluted warning")
ResetEvents()
Check(M.ResetPageToDefaults("gameplay") and #events == 0, "unavailable provider blocked core reset")
Check(M.EnsureDB().gameplay.smokeResetMarker == nil and external.value == 9, "unavailable provider reset external state")
allowed = true

-- Partial failure is reported, its changes stay undoable, and finish releases
-- the provider's UI after the transaction closes.
Check(Edit(77, 21), "failure fixture edit failed")
before = UndoCount()
local errors = {}
env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
failReset = true
ResetEvents()
Check(M.ResetPageToDefaults("gameplay") == false, "raising reset reported success")
Check(#errors == 1 and tostring(errors[1]):find("extension smoke reset failure", 1, true), "reset error was not reported")
Check(UndoCount() == before + 1 and not M.IsHistoryCapturing(), "partial failure lost history")
Check(table.concat(events, ",") == "prepare,reset,finish", "partial failure skipped finish")
Check(M.Undo() and M.EnsureDB().gameplay.smokeResetMarker == 77 and external.value == 21, "partial failure cannot be undone")

-- Stable order is independent of table enumeration and replacing a provider.
local order = {}
local function First() order[#order + 1] = "first" end
local function Second() order[#order + 1] = "second" end
M.RegisterPageExtension("smoke_order", "a", { build = First })
M.RegisterPageExtension("smoke_order", "b", { build = Second })
M.RegisterPageExtension("smoke_order", "a", { build = function() order[#order + 1] = "replacement" end })
M.BuildPageExtensions("smoke_order", {}, {})
Check(table.concat(order, ",") == "replacement,second", "replacement changed registration order")
print(("host_page_extension_smoke: ok (%s, %d checks)"):format(flavor, checks))
