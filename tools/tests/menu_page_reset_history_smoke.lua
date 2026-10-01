-- menu_page_reset_history_smoke.lua <repoRoot> <flavor>
--
-- Every "Reset page" must work on every client and leave undo/redo usable.
-- Classic Era, TBC and Mists never load the Retail spell-indicator renderer or
-- the Ellesmere/Blizzard Edit Mode adapters, so the reset fanout must not call
-- them there (review 2026-09-30, F1). History must also survive an edit that
-- raises: Lua 5.1 without pcall cannot release the capture depth on that error
-- path, so the depth heals on the next frame instead of refusing every later
-- edit until /reload. A profile value the snapshot refuses (F4) still lets the
-- edit apply, without an undo entry, and is reported once. The undo stack
-- also keeps a memory budget (review 2026-10-01, C5.5): whole-profile
-- snapshots of a large profile never pile up to the 500-step limit.
--
-- Boots the real core and Options graph of one client (client_world.lua).
-- Plain Lua 5.1, repo root as arg 1 and the client flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_page_reset_history_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor)
-- Harness gap only: every client defines MAX_BOSS_FRAMES = 5 in Blizzard_UnitFrame,
-- and Kernel/MSUF_BlizzardFrames.lua reads it once at load.
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env, core = world.env, world.core
local M = Check(core.MSUF2, "Menu2 did not load")
local F = Check(core.ProfileFields, "ProfileFields did not load")
-- The queued unit-frame runtime apply is outside this contract (and reads APIs
-- the harness only stubs); the reset fanout's direct calls still run for real.
Check(M.ApplyService, "apply service missing").Flush = function() return true end
-- Same for the synchronous re-anchor of every unit frame a unit reset forces;
-- count it instead, so unit resets still prove they ask for it.
Check(type(env.MSUF_ForceReanchorAllUnitFrames_Once) == "function", "unit-frame re-anchor missing")
local reanchors = 0
env.MSUF_ForceReanchorAllUnitFrames_Once = function() reanchors = reanchors + 1 end
local reports = {}
env.geterrorhandler = function()
    return function(message) reports[#reports + 1] = tostring(message) end
end

local db = Check(M.EnsureDB(), "profile DB missing")
-- The harness cannot decode the embedded factory string, so the booted profile
-- is the factory baseline every reset must return to.
local factory = Check(F.CopySnapshot(db), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end

local function UndoCount() return M.GetHistoryState().undoCount end
local function Edit(label, key)
    return M.CaptureHistory(label, "general:" .. key, function()
        db.general[key] = (db.general[key] or 0) + 1
        return true
    end)
end

---------------------------------------------------------------------------
-- 1. A value the snapshot refuses: the edit applies, no entry, reported once
---------------------------------------------------------------------------
-- No session yet, so CaptureHistory needs a fresh before-snapshot.
db.general.smokeUnsnapshottable = function() end
local undoBefore = UndoCount()
local ran = false
local result = M.CaptureHistory("Smoke unsnapshottable", "general:smokeUnsnapshottable", function()
    ran = true
    db.general.smokeAfterSnapshotFailure = true
    return true
end)
Check(ran and result == true and db.general.smokeAfterSnapshotFailure == true,
    "a profile value the snapshot refuses blocked the edit itself")
Check(UndoCount() == undoBefore, "an edit without a before-snapshot pushed history")
Check(#reports == 1 and reports[1]:find("undo snapshot", 1, true), "the snapshot failure was not reported")
Check(Edit("Smoke second failure", "smokeSecondFailure") == true and #reports == 1,
    "the snapshot failure was reported more than once or blocked the second edit")
Check(not M.IsHistoryCapturing(), "a snapshot failure left history capturing")
db.general.smokeUnsnapshottable = nil
Check(Edit("Smoke recovered", "smokeRecovered") == true and UndoCount() == undoBefore + 1,
    "history did not recover once the refused value was gone")
db.general.smokeAfterSnapshotFailure, db.general.smokeSecondFailure, db.general.smokeRecovered = nil, nil, nil

Check(M.StartHistorySession("menu"), "history session did not start")

---------------------------------------------------------------------------
-- 2. An edit that raises releases the capture depth on the next frame
---------------------------------------------------------------------------
local ok = pcall(M.CaptureHistory, "Smoke raise", "general:smokeRaise", function() error("smoke raise") end)
Check(not ok, "the raising edit did not raise")
world.widgets:AdvanceTime(0.02)
Check(not M.IsHistoryCapturing(), "history stayed capturing after an edit raised")
undoBefore = UndoCount()
Check(Edit("Smoke after raise", "smokeAfterRaise") == true and UndoCount() == undoBefore + 1,
    "an edit after a raised edit created no undo entry")
-- A slider transaction spans frames on purpose; the heal must never end it.
Check(M.BeginHistoryTransaction("Smoke drag", "general:smokeDrag"), "a transaction could not start after a raised edit")
world.widgets:AdvanceTime(0.5)
Check(M.IsHistoryCapturing(), "an open transaction was treated as a leaked capture")
Check(M.CaptureHistory("Smoke drag step", "general:smokeDrag", function()
    db.general.smokeDrag = (db.general.smokeDrag or 0) + 1
    return true
end) == true, "a drag step was refused")
Check(UndoCount() == undoBefore + 1, "a drag step inside the transaction pushed its own entry")
Check(M.CommitHistoryTransaction() and UndoCount() == undoBefore + 2 and not M.IsHistoryCapturing(),
    "the transaction did not commit as one entry")
-- A restore that raises (here a companion history provider) holds no frame
-- stamp; the next fresh session (the menu opening again) releases it.
local providerValue = 1
Check(M.RegisterHistoryProvider("smoke-raising-restore", function() return { value = providerValue } end,
    function() error("smoke restore raise") end), "history provider registration failed")
Check(Edit("Smoke provider edit", "smokeProviderEdit") == true, "edit before the raising restore refused")
ok = pcall(M.Undo)
Check(not ok, "the raising restore did not raise")
M.UnregisterHistoryProvider("smoke-raising-restore")
world.widgets:AdvanceTime(0.02)
M.EndHistorySession("menu")
Check(M.StartHistorySession("menu"), "history session did not restart")
Check(not M.IsHistoryCapturing(), "a new history session started with a leaked restore")
undoBefore = UndoCount()
Check(Edit("Smoke after restore raise", "smokeAfterRestoreRaise") == true and UndoCount() == undoBefore + 1,
    "an edit after a raised restore created no undo entry")
db.general.smokeAfterRaise, db.general.smokeDrag = nil, nil
db.general.smokeProviderEdit, db.general.smokeAfterRestoreRaise = nil, nil

---------------------------------------------------------------------------
-- 3. Every page reset of this client, each undone afterwards
---------------------------------------------------------------------------
local function AuraKind(pageKey)
    if pageKey == "auras3_buffs" then return "buff" end
    if pageKey == "auras3_debuffs" then return "debuff" end
    return tostring(M.auraAppearanceContainer or "buff")
end
local function Read(tbl, path)
    for i = 1, #path do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[path[i]]
    end
    return tbl
end
local function Write(tbl, path, value)
    for i = 1, #path - 1 do
        tbl[path[i]] = type(tbl[path[i]]) == "table" and tbl[path[i]] or {}
        tbl = tbl[path[i]]
    end
    tbl[path[#path]] = value
end
-- One setting each reset owns, set to a value of its own type that differs
-- from the factory baseline; returns the path, that value and the value the
-- reset must restore.
local function Marker(pageKey)
    local unit = pageKey:match("^uf_(.+)$")
    if unit then return { unit, "smokeResetMarker" }, true, nil end
    if pageKey:match("^gf_") then return { "gf_party", "smokeResetMarker" }, true, nil end
    if pageKey:match("^auras3_") then
        local kind = AuraKind(pageKey)
        local path = { "auras3", "shared", "appearanceIconShapes", kind }
        local expected = Read(factory, path) or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE")
        return path, expected == "RECTANGLE" and "FOLLOW_PORTRAIT" or "RECTANGLE", expected
    end
    -- Booleans the page's key list names; unused keys where it resets by pattern.
    local paths = {
        opt_bars = { "general", "enableGradient" },
        opt_fonts = { "general", "boldText" },
        opt_castbar = { "general", "smokeCastbarResetValue" },
        opt_colors = { "general", "smokeResetColor" },
        opt_misc = { "general", "showWelcomeMessage" },
        classpower = { "bars", "classPowerSmokeResetMarker" },
        gameplay = { "gameplay", "smokeResetMarker" },
        modules = { "general", "styleEnabled" },
    }
    local path = Check(paths[pageKey], "no marker for reset page " .. pageKey .. "; add one")
    local expected = Read(factory, path)
    return path, expected ~= true, expected
end

local keys = {}
for pageKey in pairs(M.pages or {}) do
    if M.PageHasReset(pageKey) and pageKey ~= "profiles" then keys[#keys + 1] = pageKey end
end
table.sort(keys)
Check(#keys >= 10, "only " .. #keys .. " resettable pages registered")
for _, pageKey in ipairs(keys) do
    local path, marker, factoryValue = Marker(pageKey)
    -- Through history like any menu edit, so the session snapshot holds it.
    Check(M.CaptureHistory("Smoke marker", "smoke:marker:" .. pageKey, function()
        Write(db, path, marker)
        return true
    end) == true, "the " .. pageKey .. " marker edit was refused")
    local count = UndoCount()
    local resetOk, resetResult = pcall(M.ResetPageToDefaults, pageKey)
    Check(resetOk, "resetting " .. pageKey .. " raised: " .. tostring(resetResult))
    Check(resetResult == true, "resetting " .. pageKey .. " returned " .. tostring(resetResult))
    Check(not M.IsHistoryCapturing(), "resetting " .. pageKey .. " left history capturing")
    Check(Read(M.EnsureDB(), path) == factoryValue, pageKey .. " reset did not restore its setting")
    Check(UndoCount() == count + 1, pageKey .. " reset pushed no undo entry")
    if pageKey:match("^uf_") then
        Check(reanchors > 0, pageKey .. " reset did not re-anchor the unit frames")
        reanchors = 0
    end
    Check(M.Undo(), "undoing the " .. pageKey .. " reset failed")
    Check(Read(M.EnsureDB(), path) == marker, "undo did not bring back the " .. pageKey .. " setting")
    Check(M.Redo() and Read(M.EnsureDB(), path) == factoryValue, "redo of the " .. pageKey .. " reset failed")
    db = M.EnsureDB()
end
undoBefore = UndoCount()
Check(Edit("Smoke after resets", "smokeAfterResets") == true and UndoCount() == undoBefore + 1,
    "history refused edits after the page resets")

-- The profile reset clears history by design; it must not raise or stick.
-- The core's whole-profile reset and apply are stubbed like the flush above.
env.MSUF_ResetProfile = function()
    local live = M.EnsureDB()
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(F.CopySnapshot(factory)) do live[key] = value end
end
local profileOk, profileResult = pcall(M.ResetPageToDefaults, "profiles")
Check(profileOk and profileResult == true, "the profile reset failed: " .. tostring(profileResult))
Check(not M.IsHistoryCapturing(), "the profile reset left history capturing")
db = M.EnsureDB()
undoBefore = UndoCount()
Check(Edit("Smoke after profile reset", "smokeAfterProfileReset") == true and UndoCount() == undoBefore + 1,
    "history refused edits after the profile reset")

---------------------------------------------------------------------------
-- 4. A refused restore keeps the active profile variant's overlays
---------------------------------------------------------------------------
-- Undo strips the variant overlays before it restores; when an external
-- profile root (the Suite's) refuses its part, the overlays must come back.
local V = Check(core.ProfileVariants, "ProfileVariants did not load")
env.MSUF_ActiveProfile = env.MSUF_ActiveProfile or "Default"
core.ProfileRuntime.Apply = function() V.ResolveCurrent() end
local suiteStore = { smoke = 1 }
F.RegisterExternal("suiteModules", {
    Resolve = function() return suiteStore end,
    Restore = function() return false, "smoke refusal" end,
})
local baseWidth = db.player.width
Check(V.Replace(db, { version = 1, entries = { { name = "Smoke", conditions = {},
    patch = { { path = { "player", "width" }, value = 333 } } } } }), "the smoke variant was refused")
Check(db.player.width == 333 and baseWidth ~= 333, "the smoke variant overlay is not live")
-- A new session snapshot carries the external root the provider now owns.
M.EndHistorySession("menu")
Check(M.StartHistorySession("menu"), "history session did not restart for the variant check")
Check(Edit("Smoke before refused undo", "smokeBeforeRefusedUndo") == true, "edit before the refused undo refused")
Check(M.Undo() == false, "a restore the external profile root refused reported success")
Check(M.EnsureDB().player.width == 333, "a refused undo left the active variant overlay stripped")
Check(not M.IsHistoryCapturing(), "a refused undo left history restoring")

---------------------------------------------------------------------------
-- 5. The undo stack keeps a memory budget, not only a step count (C5.5)
---------------------------------------------------------------------------
-- Each step holds whole-profile snapshots. A large profile (here 40,000
-- extra values, about 1.6 MB per snapshot) must not keep 500 steps alive; the
-- oldest steps go first and the newest stays undoable. The budget does not
-- depend on the client, so one flavor pays for the large profile.
local budgetChecked = flavor == "Mainline"
if budgetChecked then
    F.RegisterExternal("suiteModules", { Resolve = function() return suiteStore end, Restore = function() return true end })
    V.Replace(db, nil)
    M.ClearHistory()
    db = M.EnsureDB()
    local bulk = {}
    for i = 1, 40000 do bulk[i] = i end
    db.general.smokeHistoryBulk = bulk
    M.EndHistorySession("menu")
    Check(M.StartHistorySession("menu"), "history session did not restart for the budget check")
    local pushes = 45
    for i = 1, pushes do
        Check(Edit("Smoke budget " .. i, "smokeHistoryBudget") == true, "budget edit " .. i .. " was refused")
    end
    local kept = UndoCount()
    Check(kept >= 1 and kept < pushes, "the undo stack kept " .. kept .. " whole-profile steps of a large profile")
    local last = db.general.smokeHistoryBudget
    Check(M.Undo() and M.EnsureDB().general.smokeHistoryBudget == last - 1, "the newest step was not undoable after trimming")
    db = M.EnsureDB()
    db.general.smokeHistoryBulk, db.general.smokeHistoryBudget = nil, nil
end

print("menu_page_reset_history_smoke: " .. flavor .. " ok (" .. #keys .. " page resets undone and redone,"
    .. " profile reset, raised edit healed, transaction kept, unsnapshottable profile reported once,"
    .. " refused undo keeps variant overlays" .. (budgetChecked and ", undo stack within its memory budget)" or ")"))
