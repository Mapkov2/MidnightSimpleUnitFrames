-- C20-A4: successful pixel nudges share one history snapshot; failed steps
-- preserve offsets and redo. Real Menu2 history, real EditMode undo/router.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local mode = arg[3] or "shared"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local env, ns = world.env, world.core
local M, E = ns.MSUF2, world.env.MSUF_EM2
local db = M.EnsureDB()
M.ApplyService.Flush = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local now, locked, active, selected, applyOK = 100, false, true, "castbar_player", true
local profile = "A"
local timers, timerCount = {}, 0
env.GetTime = function() return now end
env.InCombatLockdown = function() return locked end
local function NewTimer(delay, fn)
    timerCount = timerCount + 1
    local t = { time = now + delay, fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
end
env.C_Timer = { NewTimer = NewTimer, After = NewTimer }
local function Advance(delta)
    now = now + delta
    local due = timers
    timers = {}
    for _, t in ipairs(due) do
        if not t.cancelled then
            if t.time <= now then t.fn() else timers[#timers + 1] = t end
        end
    end
end
local appliedUnits = {}
E.Util.ApplySettingsForKeySafe = function(key) appliedUnits[key] = true; return applyOK end
E.Util.ApplyAllSettingsSafe = function() return true end
E.Util.SyncMovers = function() end
E.Util.RefreshUFPreview = function() end
E.Util.IsConfigCombatLocked = function() return locked end
E.Util.BlockConfigCombatLocked = function() return locked end
E.Util.ProfileIdentity = function() return profile end
E.Util.IsCurrentProfile = function(value) return value == profile end
E.Util.SharedHistoryService = function() return mode == "shared" and M or nil end
E.State = { IsActive = function() return active end, GetUnitKey = function() return selected end }
E.Focus, E.Movers, E.ResourcePopup, E.AuraPopup, E.UnitPopup, E.CastPopup = nil, nil, nil, nil, nil, nil
env.MSUF_SyncCastbarPositionPopup = function() end
env.MSUF_ApplyCastbarUnitAndSync = function() return true end
env.MSUF_ClassPower_RefreshLayout = function() end
env.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() end
env.MSUF_ForceTextLayoutForUnitKey = function() end
local cast = { key = "castbar_player", popupType = "castbar", castbarUnit = "player" }
local resource = { key = "classpower", canNudge = true, popupType = "resource", resourceKind = "classpower",
    historyCategory = "classpower", historyKey = "bars", subframeOffsetXKey = "classPowerOffsetX",
    subframeOffsetYKey = "classPowerOffsetY", getConf = function() return db.bars end,
    getFrame = function() return env.UIParent end, commitSubframePosition = function() return applyOK end }
E.Registry = { Get = function(key) return key == "classpower" and resource or cast end }
for _, path in ipairs({"MSUF_EditMode_Undo.lua", "MSUF_EditMode_Layout_Nudge.lua"}) do
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/" .. path))
    setfenv(chunk, env)("MidnightSimpleUnitFrames", ns)
end
local U = E.Undo
local function Undo() active = false; U.DoUndo(); active = true end
local function Redo() active = false; U.DoRedo(); active = true end
local function Reset()
    U.Clear()
    db.general.castbarPlayerOffsetX, db.general.castbarPlayerOffsetY = 0, 5
    db.bars.classPowerOffsetX, db.bars.classPowerOffsetY = 0, 0
    timers, timerCount = {}, 0
    if mode == "shared" then
        M.EndHistorySession("edit_mode")
        assert(M.StartHistorySession("edit_mode"))
        M.ClearHistory()
    end
end
local function Nudge() return E.Nudge.By(1, 0) end
local snapshots = 0
local snapshot
for i = 1, 50 do
    local name, fn = debug.getupvalue(M.CommitHistoryTransaction, i)
    if not name then break end
    if name == "SnapshotDB" then snapshot = fn end
end
assert(snapshot, "history snapshot owner not found")
local function Count(event)
    if event == "call" and debug.getinfo(2, "f").func == snapshot then snapshots = snapshots + 1 end
end
for _, count in ipairs({30, 1000}) do
    for _, key in ipairs({"castbar_player", "classpower"}) do
        Reset()
        selected = key
        snapshots = 0
        debug.sethook(Count, "c")
        for _ = 1, count do assert(Nudge(), "nudge failed") end
        Advance(0.6)
        debug.sethook()
        if mode == "shared" then
            assert(snapshots == 1, "each pixel captured the full profile: " .. snapshots)
            assert(M.GetHistoryState().undoCount == 1, "one gesture generated multiple undo entries")
        end
        assert(timerCount <= 1, "a timer was allocated for every pixel")
        Undo()
        assert(db.general.castbarPlayerOffsetX == 0 and db.bars.classPowerOffsetX == 0,
            "one undo did not restore the complete gesture")
        assert(not U.CanUndo(), "one gesture left extra undo entries")
        Redo()
        local expected = key == "classpower" and db.bars.classPowerOffsetX or db.general.castbarPlayerOffsetX
        assert(expected == count, "redo did not restore the complete gesture")
        assert(Nudge())
        Advance(0.6)
        Undo()
        expected = key == "classpower" and db.bars.classPowerOffsetX or db.general.castbarPlayerOffsetX
        assert(expected == count, "later gesture was merged into the first")
    end
end
-- A rejected first step and a rejected later step cannot erase redo or add undo.
for _, key in ipairs({"castbar_player", "classpower"}) do
    Reset(); selected = key
    assert(Nudge()); Advance(0.6); Undo()
    assert(U.CanRedo(), "setup has no redo")
    applyOK = false
    assert(not Nudge(), "failed apply was accepted")
    applyOK = true
    assert(U.CanRedo() and not U.CanUndo(), "failed first step modified history")
    Advance(1)
    assert(U.CanRedo() and not U.CanUndo(), "failed first step queued a commit")
    assert(db.general.castbarPlayerOffsetX == 0 and db.bars.classPowerOffsetX == 0, "rollback lost offsets")
    assert(Nudge())
    applyOK = false
    assert(not Nudge())
    applyOK = true
    Advance(0.6); Undo()
    assert(db.general.castbarPlayerOffsetX == 0 and db.bars.classPowerOffsetX == 0, "later failure broke initial snapshot")
end
-- Switching nudge target closes the prior transaction; Menu2 actions own theirs.
Reset(); selected = "castbar_player"; assert(Nudge()); selected = "classpower"; assert(Nudge())
Advance(0.6); Undo()
assert(db.general.castbarPlayerOffsetX == 1 and db.bars.classPowerOffsetX == 0, "target switch was folded")
Undo(); assert(db.general.castbarPlayerOffsetX == 0)
if mode == "shared" then
    Reset(); selected = "castbar_player"; assert(Nudge())
    assert(M.CaptureHistory("Other", "menu:test", function() db.player.width = 234; return true end))
    assert(M.GetHistoryState().undoCount == 2, "menu action merged into pending nudge")
    Advance(0.6)
    assert(M.GetHistoryState().undoCount == 2, "stale timer committed someone else's transaction")
    Reset(); assert(Nudge())
    active = false
    assert(M.Undo(), "Menu2 undo ignored pending nudge")
    active = true
    assert(db.general.castbarPlayerOffsetX == 0)
    Advance(0.6)
    assert(M.GetHistoryState().undoCount == 0, "post-undo timer created an entry")
    -- Combat defers the existing before-state without a snapshot under lock.
    Reset(); assert(Nudge())
    snapshots = 0; debug.sethook(Count, "c")
    locked = true; world.widgets.inCombat = true; U.CancelChange(true); Advance(1)
    debug.sethook(); assert(snapshots == 0, "combat captured a profile")
    locked = false; world.widgets.inCombat = false; M.FlushDeferredHistory(); Undo()
    assert(db.general.castbarPlayerOffsetX == 0, "combat lost the gesture")
    -- Profile boundary cancels work while identity still points to its owner.
    Reset(); assert(Nudge()); U.CancelChange(); profile = "B"; Advance(1)
    assert(M.GetHistoryState().undoCount == 0, "old timer wrote into new profile")
    profile = "A"
end
-- Copy-all fallback has one snapshot across supported unit blocks; absence survives.
Reset()
local refs = {}
for key in pairs(E.Util.UNIT_PAGE_KEYS) do
    if type(db[key]) == "table" then refs[key] = db[key]; db[key].width = 101 end
end
local absent = "pettarget"
db[absent] = nil
if mode == "shared" then M.ClearHistory() end
assert(U.BeginChange("units", "all"))
for key in pairs(E.Util.UNIT_PAGE_KEYS) do db[key] = db[key] or {}; db[key].width = 250 end
assert(U.CommitChange())
appliedUnits = {}
Undo()
for key, ref in pairs(refs) do
    if key ~= absent then assert(db[key] == ref and db[key].width == 101, "copy-all broke sibling identity") end
end
assert(db[absent] == nil, "copy-all undo manufactured an absent unit")
if mode == "fallback" then assert(appliedUnits[absent], "copy-all undo left the removed unit configuration rendered") end
Redo()
for key in pairs(E.Util.UNIT_PAGE_KEYS) do assert(db[key].width == 250, "copy-all redo missed unit") end
print("bh3_runtime_nudge_history_smoke " .. flavor .. " " .. mode .. ": ok")
