-- menu_undo_deep_history_smoke.lua <repoRoot> <flavor> [benchmark [olderHistoryFile]]
--
-- Menu undo keeps many steps (owner 2026-10-13: "Es sollen ruhig viele Schritte
-- Undo/Redo haben"). A step stores the paths it changed, never a profile copy,
-- so ordinary edits never run into the size budget. On one client's real core
-- and Options graph:
--   * 1000 single-value edits are all kept; undoing all of them restores the
--     exact original profile and redoing all restores the exact final one, for
--     an unknown writer (whole-profile diff) and for a bound setter that names
--     its root (SetGeneralValue: only that root is compared). On Mainline the
--     profile is large (defaults plus 2400 aura entries and 24 presets,
--     tools/tests/menu_history_large_profile_fixture.lua), the cursor plus the
--     1000 steps stay under 4 MB and the bound setter is at least three times
--     cheaper than the whole-profile diff;
--   * a seeded random walk over numbers, strings, false, nil, nested tables and
--     lists, mixing scoped (bound) and whole-profile (bulk) steps with undo/redo
--     branches, checks the state after every single undo and redo; a new edit
--     after undo drops the redo steps; a bound setter that also writes outside
--     its root has that write undone and redone with its step; a write the
--     history did not make (X) after bound steps A, before B and C joins A:
--     undoing C or B keeps it, undoing A removes it;
--   * a write of 40 settings in one capture is one step;
--   * RegisterHistoryProvider keeps its capture/restore contract;
--   * 20 steps survive minimize/restore, close/reopen and the automatic close
--     at combat start (no trim on close at all), and Edit Mode undoes them
--     from the same stacks;
--   * Edit Mode Cancel All and Reset session restore created and removed
--     parents and false values, and the variant-free diff view equals the
--     variant-free profile snapshot;
--   * only oversized diffs evict the oldest steps; the newest stays undoable;
--     steps an open surface still holds count against the same budget.
-- "benchmark" prints the per-edit cost and the retained memory and stops; an
-- older history file as the next argument is loaded over the graph first, to
-- compare against the former snapshot path.
-- Plain Lua 5.1.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local benchmark = arg[3] == "benchmark"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { locale = "enUS" })
local M, core, env = mw.M, mw.core, mw.env
if arg[4] then
    local older = assert(loadfile(arg[4]))
    setfenv(older, env)
    older("MidnightSimpleUnitFrames_Options", core)
    M.EndHistorySession("menu")
    M.StartHistorySession("menu")
end
M.ApplyService.Flush = function() return true end
M.ApplyService.Quiesce = function() return true end
-- Feedback timers and runtime painting are outside this contract.
M.ShowHistoryFeedback = function() end
M.ShowStatusFeedback = function() end
M.RequestGeneralApply = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
env.geterrorhandler = function() return function(message) error(message, 0) end end

local function Check(ok, message)
    if not ok then error("menu_undo_deep_history_smoke " .. flavor .. ": " .. message, 2) end
    return ok
end
local function Resident()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Steps() return M.GetHistoryState().undoCount, M.GetHistoryState().redoCount end
-- A Bars-scoped source keeps each restore to one runtime owner.
local function Capture(fn) return M.RunWithHistory("Smoke edit", "opt_bars:historySmoke", fn) end

local db = M.EnsureDB()
---------------------------------------------------------------------------
-- 1. 1000 single-value edits: all kept, exact round trips, memory, cost.
---------------------------------------------------------------------------
local large = flavor == "Mainline" or benchmark
if large then assert(loadfile(root .. "/tools/tests/menu_history_large_profile_fixture.lua"))()(db) end
db.general.historyDiffValue = 0
M.ClearHistory()
local cursorKB
do
    local before = Resident()
    local copy = M.DeepCopy(db)
    cursorKB = Resident() - before
    copy = nil
end
local original = M.DeepCopy(db)
local held = Resident()
local started = os.clock()
for i = 1, 1000 do
    Check(M.CaptureHistory("History edit", "opt_bars:historyDiffValue", function()
        db.general.historyDiffValue = i
        return true
    end) == true, "edit " .. i .. " was refused")
end
local perEdit = (os.clock() - started) * 1000 / 1000
local stepsKB = Resident() - held
print(("history benchmark: %s %s profile, 1000 edits %.2f ms/edit, cursor %.0f KB + steps %.0f KB, %d steps kept"):format(
    flavor, large and "large" or "default", perEdit, cursorKB, stepsKB, (Steps())))
if benchmark then return end
Check((Steps()) == 1000, "ordinary edits were trimmed before 1000 steps: " .. Steps())
if large then
    Check(cursorKB + stepsKB < 4096, ("the cursor and 1000 steps hold %.0f KB, expected under 4 MB"):format(cursorKB + stepsKB))
end
local final = M.DeepCopy(db)
for i = 1, 1000 do Check(M.Undo(), "Undo " .. i .. " failed") end
Check(Equal(M.EnsureDB(), original), "undoing all 1000 steps did not restore the exact original profile")
for i = 1, 1000 do Check(M.Redo(), "Redo " .. i .. " failed") end
Check(Equal(M.EnsureDB(), final), "redoing all 1000 steps did not restore the exact final profile")
-- The same through a bound setter, which names its root ("general").
M.ClearHistory()
original = final
started = os.clock()
for i = 1, 1000 do
    Check(M.SetGeneralValue("historyDiffValue", 1000 + i) == true, "bound edit " .. i .. " was refused")
end
local scopedPerEdit = (os.clock() - started) * 1000 / 1000
print(("history benchmark: %s %s profile, 1000 bound-setter edits %.2f ms/edit (whole-profile diff %.2f ms/edit)"):format(
    flavor, large and "large" or "default", scopedPerEdit, perEdit))
Check((Steps()) == 1000, "bound edits were trimmed before 1000 steps: " .. Steps())
if large then
    Check(scopedPerEdit * 3 < perEdit, ("a bound edit costs %.2f ms against %.2f ms for the whole-profile diff"):format(
        scopedPerEdit, perEdit))
end
final = M.DeepCopy(db)
for i = 1, 1000 do Check(M.Undo(), "bound Undo " .. i .. " failed") end
Check(Equal(M.EnsureDB(), original), "undoing 1000 bound steps did not restore the exact profile before them")
for i = 1, 1000 do Check(M.Redo(), "bound Redo " .. i .. " failed") end
Check(Equal(M.EnsureDB(), final), "redoing 1000 bound steps did not restore the exact final profile")
if large then
    db.auras3.historyFixture, db.classPowerPresets = nil, nil
end
db = M.EnsureDB()
M.ClearHistory()
original, final = nil, nil

---------------------------------------------------------------------------
-- 2. A seeded random walk: every undo and redo step lands on its state.
---------------------------------------------------------------------------
do
    local seed = 20261013
    local function Random(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return math.floor(seed / 65536) % n + 1
    end
    local function Value(depth)
        local pick = Random(depth < 3 and 9 or 6)
        if pick == 1 then return false end
        if pick == 2 then return true end
        if pick <= 4 then return Random(1000) - 500 + Random(4) / 4 end
        if pick <= 6 then return "s" .. Random(50) end
        local t = {}
        if pick == 7 then
            for i = 1, Random(5) do t[i] = Value(depth + 1) end
        else
            for _ = 1, Random(4) do t["k" .. Random(6)] = Value(depth + 1) end
            if Random(3) == 1 then t[0] = false end
        end
        return t
    end
    local function Pick(t, depth)
        local keys = {}
        for key, value in pairs(t) do
            if type(value) == "table" and depth < 4 and Random(2) == 1 then keys[#keys + 1] = key end
        end
        if #keys > 0 then
            local key = keys[Random(#keys)]
            return Pick(t[key], depth + 1)
        end
        return t
    end
    local ROOT_OF_OP = { [5] = "player", [6] = "target" }
    local function Mutate(op)
        local fuzz = db.general.historyFuzz
        if not fuzz or op == 1 then
            db.general.historyFuzz = Value(0)
            if type(db.general.historyFuzz) ~= "table" or op == 1 and Random(4) == 1 then db.general.historyFuzz = nil end
            return
        end
        if type(fuzz) ~= "table" then
            db.general.historyFuzz = Value(1)
            return
        end
        local t = Pick(fuzz, 0)
        if op == 2 and #t > 0 then
            table.remove(t, Random(#t))
        elseif op == 3 then
            table.insert(t, Random(#t + 1), Value(2))
        elseif op == 4 then
            t["k" .. Random(6)] = nil
        elseif op == 5 then
            db.player.width = 100 + Random(200)
        elseif op == 6 then
            db.target.historyFlag = Random(3) == 1 and false or (Random(2) == 1 and true or nil)
        else
            t["k" .. Random(6)] = Value(2)
        end
    end
    local function Probe()
        return { fuzz = M.DeepCopy(db.general.historyFuzz), width = db.player.width, flag = db.target.historyFlag }
    end
    local start = M.DeepCopy(db)
    local expected = { Probe() }
    local function Edit()
        local count = Steps()
        local op = Random(10)
        local fn = function() Mutate(op) return true end
        if Random(2) == 1 then
            -- A bound setter: only the root it names is compared.
            Check(M.CaptureHistory("Smoke edit", "opt_bars:historySmoke", fn, ROOT_OF_OP[op] or "general") ~= false,
                "a scoped random edit was refused")
        else
            Check(Capture(fn) ~= false, "a random edit was refused")
        end
        db = M.EnsureDB()
        local probe = Probe()
        if Steps() == count + 1 then
            expected[#expected + 1] = probe
        else
            Check(Steps() == count and Equal(probe, expected[#expected]), "a no-op edit pushed a step or a step was lost")
        end
    end
    for round = 1, 400 do
        Edit()
        if round % 50 == 0 then
            -- Branch: undo a few, check each, then edit on (redo is dropped).
            for _ = 1, 7 do
                Check(M.Undo(), "branch undo failed")
                db = M.EnsureDB()
                table.remove(expected)
                Check(Equal(Probe(), expected[#expected]), "a branch undo did not land on its recorded state")
            end
            local count = Steps()
            Capture(function() db.player.width = 1000 + round return true end)
            expected[#expected + 1] = Probe()
            Check(Steps() == count + 1 and select(2, Steps()) == 0, "a new edit after undo kept the redo steps")
        end
    end
    local finalState = M.DeepCopy(db)
    local count = Steps()
    Check(count == #expected - 1 and count > 200, "the random walk kept " .. count .. " of " .. (#expected - 1) .. " steps")
    for i = count, 1, -1 do
        Check(M.Undo(), "random walk undo " .. i .. " failed")
        db = M.EnsureDB()
        Check(Equal(Probe(), expected[i]), "random walk undo " .. i .. " did not land on its recorded state")
    end
    Check(Equal(M.EnsureDB(), start), "undoing the random walk did not restore the exact start profile")
    for i = 2, count + 1 do
        Check(M.Redo(), "random walk redo failed")
        db = M.EnsureDB()
        Check(Equal(Probe(), expected[i]), "random walk redo " .. i .. " did not land on its recorded state")
    end
    Check(Equal(M.EnsureDB(), finalState), "redoing the random walk did not restore the exact final profile")
    -- A bound setter that also writes outside its root: the next undo takes
    -- that write with the step, and redo brings both back. One that wrote
    -- only outside its root still records its step.
    M.ClearHistory()
    local width = db.player.width
    M.CaptureHistory("Side", "opt_bars:historySmoke", function()
        db.player.width = 777
        db.target.historySide = true
        return true
    end, "player")
    Check(M.Undo() and db.player.width == width and db.target.historySide == nil, "undo left a write outside the step's root")
    Check(M.Redo() and db.player.width == 777 and db.target.historySide == true, "redo lost a write outside the step's root")
    local count = Steps()
    M.CaptureHistory("Elsewhere", "opt_bars:historySmoke", function() db.target.historySide = false return true end, "player")
    Check(Steps() == count + 1 and M.Undo() and db.target.historySide == true, "a write only outside the named root was lost")
    Check(M.Undo() and M.Undo() == false and db.player.width == width, "the history did not unwind to its start")
    db.target.historySide = nil
    -- A, X, B, C: X is a write the history did not make, after the bound step A.
    -- It joins A, the first step after the last whole-profile compare.
    M.ClearHistory()
    local height = db.player.height
    local function Bound(root, fn) M.CaptureHistory("Bound", "opt_bars:historySmoke", function() fn() return true end, root) end
    Bound("player", function() db.player.width = (tonumber(width) or 200) + 5 end)
    db.target.historyDrift = 1
    Bound("general", function() db.general.historyStepB = true end)
    Bound("player", function() db.player.height = (tonumber(height) or 40) + 5 end)
    Check(M.Undo() and db.player.height == height and db.target.historyDrift == 1, "undoing C removed the outside write X")
    Check(M.Undo() and db.general.historyStepB == nil and db.target.historyDrift == 1, "undoing B removed the outside write X")
    Check(M.Undo() and db.player.width == width and db.target.historyDrift == nil, "undoing A kept the outside write X")
    Check(M.Redo() and db.target.historyDrift == 1 and M.Redo() and M.Redo() and db.player.height == (tonumber(height) or 40) + 5,
        "redo did not bring X back with A")
    Check(M.Undo() and M.Undo() and M.Undo() and db.target.historyDrift == nil, "the A, X, B, C history did not unwind")
    db.general.historyFuzz, db.target.historyFlag = nil, nil
    M.ClearHistory()
end

---------------------------------------------------------------------------
-- 3. One capture of many writes is one step; providers keep their contract.
---------------------------------------------------------------------------
do
    local count = Steps()
    Capture(function()
        for i = 1, 40 do M.SetGeneralValue("historyBulk" .. i, i) end
        return true
    end)
    Check(Steps() == count + 1, "40 nested writes were not one step")
    Check(M.Undo() and db.general.historyBulk1 == nil and db.general.historyBulk40 == nil, "bulk undo failed")
    Check(M.Redo() and db.general.historyBulk40 == 40, "bulk redo failed")
    for i = 1, 40 do db.general["historyBulk" .. i] = nil end

    local suite, restored = { value = 0, stable = {} }, {}
    for i = 1, 10000 do suite.stable[i] = i end
    Check(M.RegisterHistoryProvider("smokeSuite", function() return M.DeepCopy(suite) end,
        function(value, reason, source)
            suite = value
            restored[#restored + 1] = { reason = reason, source = source }
        end), "provider registration refused")
    M.ClearHistory()
    for i = 1, 20 do Capture(function() suite.value = i return true end) end
    Check(Steps() == 20, "provider changes were not steps")
    Check(M.Undo() and suite.value == 19 and #suite.stable == 10000, "provider undo failed")
    Check(restored[#restored].reason == "MSUF2_HISTORY_UNDO" and restored[#restored].source == "opt_bars:historySmoke",
        "provider restore lost its reason or source")
    Check(M.Redo() and suite.value == 20, "provider redo failed")
    M.UnregisterHistoryProvider("smokeSuite")
    M.ClearHistory()
    local flag = false
    Check(M.RegisterHistoryProvider("smokeFlag", function() return flag end, function(value) flag = value end),
        "boolean provider refused")
    Capture(function() flag = true return true end)
    Check(M.Undo() and flag == false, "a provider's false became absent")
    Check(M.Redo() and flag == true, "boolean provider redo failed")
    M.UnregisterHistoryProvider("smokeFlag")
    M.ClearHistory()
end

---------------------------------------------------------------------------
-- 4. Steps survive minimize, close and the combat close; Edit Mode shares them.
---------------------------------------------------------------------------
do
    db.general.historyDiffValue = 0
    M.EndHistorySession("menu")
    M.StartHistorySession("menu")
    for i = 1, 20 do Capture(function() db.general.historyDiffValue = i return true end) end
    Check(M.MinimizeSlashMenuWindow(), "minimize refused")
    mw:RunTimers()
    -- The harness does not finish native animations; run their hide outcome.
    if M.frame:IsShown() then
        M.frame._msuf2Minimized = true
        M.frame:Hide()
    end
    Check(Steps() == 20, "minimize trimmed the history")
    M.RestoreMinimizedSlashMenu()
    mw:RunTimers()
    if not M.frame:IsShown() then M.frame:Show() end
    M.frame:Hide()
    Check(Steps() == 20, "closing the menu trimmed the history")
    M.frame:Show()
    mw:Fire("PLAYER_REGEN_DISABLED")
    Check(not M.frame:IsShown(), "combat did not close the menu")
    Check(Steps() == 20, "the combat close trimmed the history")
    local ran = false
    Check(M.CaptureHistory("Combat", "general:historyDiffValue", function() ran = true end) == false and not ran,
        "a capture ran in combat")
    mw:Fire("PLAYER_REGEN_ENABLED")
    -- Fire dispatches Options listeners only; deliver the core combat edge too.
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    mw.world.widgets:AdvanceTime(.02)
    -- Edit Mode opens on its own and undoes the menu's steps from the same stack.
    Check(M.StartHistorySession("edit_mode"), "the Edit Mode session did not start")
    for i = 1, 5 do Check(M.Undo(), "Edit Mode undo " .. i .. " failed") end
    Check(db.general.historyDiffValue == 15, "Edit Mode undo did not walk the menu's steps")
    Capture(function() db.general.historyDiffValue = 99 return true end)
    M.EndHistorySession("edit_mode")
    M.frame:Show()
    Check(Steps() == 16, "the menu does not see the Edit Mode step")
    Check(M.Undo() and db.general.historyDiffValue == 15, "the menu could not undo the Edit Mode step")
    for i = 1, 15 do Check(M.Undo(), "lifecycle undo " .. i .. " failed") end
    Check(db.general.historyDiffValue == 0, "the lifecycle lost the original value")
    M.ClearHistory()
end

---------------------------------------------------------------------------
-- 5. Cancel All and Reset session restore created/removed parents and false.
---------------------------------------------------------------------------
do
    Check(M.StartHistorySession("edit_mode"), "the Edit Mode session did not start")
    Capture(function() db.general.historyMarker = { child = false, array = { 1, 2 } } return true end)
    Capture(function() db.general.historyMarker.child = true return true end)
    Capture(function() db.general.historyMarker = nil return true end)
    Check(M.CancelHistorySurface("edit_mode", true) and db.general.historyMarker == nil,
        "Cancel All lost a created and removed parent")
    M.EndHistorySession("edit_mode")
    M.ClearHistory()
    db.general.historyMarker = { child = false, array = { 1, 2 } }
    M.EndHistorySession("menu")
    M.StartHistorySession("menu")
    Capture(function() db.general.historyMarker.child = true return true end)
    -- A write that bypasses the history is part of what Reset session undoes.
    db.general.historyMarker.array[3] = 3
    Capture(function() db.general.historyMarker = nil return true end)
    Check(M.GetHistoryState().canResetAll, "Reset session is not offered after changes")
    Check(M.ResetHistorySession(), "Reset session refused")
    db = M.EnsureDB()
    Check(Equal(db.general.historyMarker, { child = false, array = { 1, 2 } }),
        "Reset session did not restore the parent, its false value and its list")
    Check(not M.GetHistoryState().canResetAll and (Steps()) == 0, "Reset session kept steps or stays offered")
    db.general.historyMarker = nil
    M.ClearHistory()

    -- Reset session reads false exactly: a nil -> false step keeps it offered
    -- after another step is undone, and an original false back in place does not.
    db.general.historyNilToFalse, db.general.historyOriginalFalse = nil, false
    M.EndHistorySession("menu")
    M.StartHistorySession("menu")
    Capture(function() db.general.historyNilToFalse = false return true end)
    Capture(function() db.general.historyOther = 1 return true end)
    Check(M.Undo() and M.GetHistoryState().canResetAll, "Reset session was dropped while a nil -> false step remains")
    Check(M.Undo() and not M.GetHistoryState().canResetAll, "Reset session stayed offered at the start state")
    Capture(function() db.general.historyOriginalFalse = true return true end)
    Check(M.Undo() and db.general.historyOriginalFalse == false and not M.GetHistoryState().canResetAll,
        "Reset session is offered although the original false is back")
    db.general.historyOriginalFalse = nil
    M.ClearHistory()

    -- The variant-free diff view equals the variant-free snapshot.
    local V = core.ProfileVariants
    env.MSUF_ActiveProfile = env.MSUF_ActiveProfile or "Default"
    core.ProfileRuntime.Apply = function() V.ResolveCurrent() end
    local width = db.player.width
    Check(V.Replace(db, { version = 1, entries = { { name = "Smoke", conditions = {}, patch = {
        { path = { "player", "width" }, value = (tonumber(width) or 200) + 33 },
        { path = { "general", "historyCreated", "leaf" }, value = 5 },
        { path = { "general", "historyGone", "leaf" }, remove = true },
    } } } }), "the smoke variant was refused")
    Check(db.general.historyCreated and db.general.historyCreated.leaf == 5, "the smoke variant did not create its path")
    -- The Variants page clears the history after it changes the variants: the
    -- cursor is then the variant-free snapshot. A step diffs it against the
    -- view, so a view that differed from the snapshot anywhere (an overlay, a
    -- created or a removed parent) would add changes to this one-value step.
    M.ClearHistory()
    local live = M.DeepCopy(db)
    local height = (tonumber(db.player.height) or 40) + 1
    Capture(function() db.player.height = height return true end)
    local diff = M.historyUndo[#M.historyUndo].diff
    Check(#diff == 1 and diff[1].path[2] == "player" and diff[1].path[3] == "height",
        "the diff view differs from the variant-free snapshot (" .. #diff .. " changes)")
    live.player.height = height
    Check(Equal(M.EnsureDB(), live), "the diff view changed the live profile")
    Check(M.Undo() and db.player.width == (tonumber(width) or 200) + 33, "undo dropped the live variant overlay")
    V.Replace(db, nil)
    M.ClearHistory()
end

---------------------------------------------------------------------------
-- 6. Only oversized diffs evict the oldest steps; the newest stays.
---------------------------------------------------------------------------
do
    for i = 1, 10 do
        Capture(function()
            local values = {}
            for j = 1, 20000 do values[j] = i + j end
            db.general.historyLargeDiff = values
            return true
        end)
    end
    local kept = Steps()
    Check(kept >= 1 and kept < 10, "oversized diffs did not evict the oldest steps: " .. kept)
    Check(M.Undo() and db.general.historyLargeDiff[1] == 10, "the newest step was lost to the budget")
    Check(M.Redo() and db.general.historyLargeDiff[1] == 11, "redo of the newest step was lost to the budget")
    db.general.historyLargeDiff = nil
    M.ClearHistory()
end

---------------------------------------------------------------------------
-- 7. Steps an open surface still holds count against the same budget.
---------------------------------------------------------------------------
do
    local function Step(i)
        Capture(function()
            local values = {}
            for j = 1, 400 do values[j] = i * 10000 + j end
            db.general.historyMarkerDiff = values
            return true
        end)
    end
    M.ClearHistory()
    for i = 1, 14 do Step(i) end
    Check(M.StartHistorySession("edit_mode"), "the Edit Mode session did not start")
    for i = 15, 18 do Step(i) end
    local retained = M.HistoryRetainedBytes and M.HistoryRetainedBytes() or math.huge
    Check(retained <= 4 * 1024 * 1024, "the history and its open surfaces retain " .. retained .. " estimated bytes")
    Check(db.general.historyMarkerDiff[1] == 180001, "the newest step is missing")
    Check(M.CancelHistorySurface("edit_mode", true) and db.general.historyMarkerDiff[1] == 140001,
        "Cancel All lost its entry state")
    Check(M.Undo() and db.general.historyMarkerDiff[1] == 130001, "the steps before Edit Mode are not undoable")
    M.EndHistorySession("edit_mode")
    db.general.historyMarkerDiff = nil
    M.ClearHistory()
end

print("menu_undo_deep_history_smoke: " .. flavor .. " ok (1000 steps kept and round-tripped exactly"
    .. (large and " on a large profile" or "") .. ", random walk, bulk step, providers, survival across"
    .. " close/minimize/combat with Edit Mode, Cancel All, Reset session, diff view, budget)")
