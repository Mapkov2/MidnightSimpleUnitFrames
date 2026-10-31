local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end }, arg[3])
local M, W, F = mw.M, mw.core.ProfileWorkbench, mw.core.ProfileFields
assert(W, "profile workbench is loaded on every supported client")
local db = M.EnsureDB()

local H = mw.core.History
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local external, mode, target = { color = 1 }, nil, 1
local reports = {}
mw.env.geterrorhandler = function()
    return function(message) reports[#reports + 1] = message end
end
W.RegisterProvider("failure-review", {
    Capture = function() return external end,
    Restore = function(value)
        external.color = value.color
        if mode == "both" or mode and value.color == target then
            external.color = 99
            if mode == "raise" then error("Deliberate provider failure") end
            return false
        end
        return true
    end,
})
Check(mw.core.HistoryProviders.Restore({ externalProviders = {
    ["workbench:failure-review"] = { color = 2 },
} }, "tour"), "persisted provider state restores before the first Workbench snapshot")
Check(external.color == 2, "provider registration makes saved tour state immediately available")
external.color = 1
local baseWidth = db.player.width
local after = assert(W.Snapshot())
after.core.player.width = baseWidth + 7
after.providers["failure-review"].color = 2
Check(W.ApplySnapshot(after, "Provider history failure"), "initial change applies")
local state, entry = H.GetHistoryState(), H.historyUndo[#H.historyUndo]
mode = "false"
local ok, why = H.Undo()
Check(not ok and why == "history_restore_failed", "refused undo fails explicitly")
Check(db.player.width == baseWidth + 7 and external.color == 2, "rollback restores core and provider pre-undo values")
Check(H.GetHistoryState().undoCount == state.undoCount and H.GetHistoryState().redoCount == state.redoCount,
    "refused undo preserves both stacks")
Check(H.historyUndo[#H.historyUndo] == entry, "refused undo keeps exact history entry")
Check(not H.IsHistoryCapturing(), "provider refusal releases restoring state")
mode = nil
Check(H.Undo(), "same undo can be retried")
Check(db.player.width == baseWidth and external.color == 1, "retry restores both values")
local undoneState = H.GetHistoryState()
mode, target = "raise", 2
ok, why = H.Redo()
Check(not ok and why == "history_restore_failed", "raised provider error rejects redo")
Check(db.player.width == baseWidth and external.color == 1, "failed redo rolls back core and provider")
Check(H.GetHistoryState().undoCount == undoneState.undoCount and H.GetHistoryState().redoCount == undoneState.redoCount,
    "raised redo preserves both stacks")
Check(not H.IsHistoryCapturing(), "raised provider releases restoring state")
mode = nil
Check(H.Redo(), "redo can be retried after a raise")
Check(db.player.width == baseWidth + 7 and external.color == 2, "redo retry restores final values")
mode, target = "both", 1
ok, why = H.Undo()
Check(not ok and why == "history_rollback_failed", "failed rollback is reported distinctly")
Check(db.player.width == baseWidth + 7 and external.color == 99, "core rollback succeeds despite unavailable provider rollback")
Check(H.historyUndo[#H.historyUndo] == entry and H.GetHistoryState().redoCount == state.redoCount,
    "failed rollback still keeps the history entry")
Check(not H.IsHistoryCapturing(), "failed rollback releases restoring state")
Check(reports[#reports]:find("previous settings could not be restored", 1, true), "rollback failure visibly reports incomplete recovery")
external.color, mode = 2, "raise"
mw.env.geterrorhandler = function() return function() error("Reporter failure") end end
ok, why = H.Undo()
Check(not ok and why == "history_restore_failed", "a raising reporter cannot abort rollback")
Check(external.color == 2 and db.player.width == baseWidth + 7 and not H.IsHistoryCapturing(),
    "reporter failure cannot leak state or consume history")
mode = nil
Check(H.Undo(), "history remains usable after failing provider and reporter")
Check(external.color == 1 and db.player.width == baseWidth, "post-failure undo restores both values")
local providers = mw.core.HistoryProviders
Check(H.Redo(), "prepare a failed-capture undo")
Check(providers.Register("refused-capture", function() return false end, function() return true end), "register refused capture")
local counts = H.GetHistoryState()
ok, why = H.Undo()
Check(not ok and why == "history_snapshot_failed", "explicit false capture refuses restore before any mutation")
Check(db.player.width == baseWidth + 7 and external.color == 2, "false capture preserves live values")
Check(H.GetHistoryState().undoCount == counts.undoCount and H.GetHistoryState().redoCount == counts.redoCount,
    "false capture preserves stack entries")
Check(not H.IsHistoryCapturing(), "false capture releases restoring state")
providers.Unregister("refused-capture")
Check(H.Undo(), "undo still works after failed capture is removed")
Check(db.player.width == baseWidth and external.color == 1, "capture failure leaves the cursor unchanged")
print("history_provider_restore_smoke: " .. flavor .. " passed " .. checks .. " checks")
