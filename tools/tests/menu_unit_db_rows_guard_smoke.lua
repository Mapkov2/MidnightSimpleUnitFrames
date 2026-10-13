-- menu_unit_db_rows_guard_smoke.lua <repoRoot> <flavor>
--
-- Two writers of the menu binding layer guessed instead of refusing:
--   * M.GetUnitDB mapped any unknown unit to "player" and created that table, so
--     a typo or a unit this client does not have wrote a setting into the Player
--     frame. An unknown unit now has no table, and M.SetUnitValue refuses it
--     before it snapshots anything;
--   * the reset arrow of a W.SettingsRows row wrote its default straight into the
--     profile: no combat refusal, no undo entry. It now runs through the history
--     like every other menu edit.
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

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env = mw.M, mw.env
assert(M.ApplyService, "apply service missing").Flush = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local db = M.EnsureDB()

---------------------------------------------------------------------------
-- 1. Unknown units have no table.
---------------------------------------------------------------------------
do
    local playerBefore = {}
    for key, value in pairs(db.player) do playerBefore[key] = value end
    for _, unit in ipairs({ "party1", "raid5", "bogus", "", "Player", "arena1" }) do
        Check(M.GetUnitDB(unit) == nil, "GetUnitDB('" .. unit .. "') answered a table")
    end
    Check(M.GetUnitDB(nil) == nil, "GetUnitDB(nil) answered a table")
    Check(db.party1 == nil and db.raid5 == nil and db.bogus == nil and db[""] == nil and db.arena1 == nil,
        "GetUnitDB created a table for an unknown unit")
    for key, value in pairs(playerBefore) do
        Check(db.player[key] == value, "GetUnitDB changed the Player table (" .. key .. ")")
    end
    Check(M.GetUnitDB("player") == db.player, "the Player table is no longer answered")
    Check(M.GetUnitDB("tot") == M.GetUnitDB("targettarget"), "the 'tot' alias lost its table")
    Check(M.GetUnitDB("focus_target") == M.GetUnitDB("focustarget"), "the 'focus_target' alias lost its table")

    assert(M.StartHistorySession("menu"), "the menu history session did not start")
    local undoBefore = M.GetHistoryState().undoCount
    Check(M.SetUnitValue("bogus", "smokeUnitDbKey", 7, "SMOKE") == false, "SetUnitValue accepted an unknown unit")
    Check(db.player.smokeUnitDbKey == nil, "an unknown unit wrote its setting into the Player table")
    Check(db.bogus == nil, "an unknown unit got a table from SetUnitValue")
    Check(M.GetHistoryState().undoCount == undoBefore, "an unknown unit left an undo entry")
    Check(M.SetUnitValue("player", "smokeUnitDbKey", 7, "SMOKE") == true and db.player.smokeUnitDbKey == 7,
        "a known unit no longer takes its setting")
    db.player.smokeUnitDbKey = nil
    M.ClearHistory()
    M.EndHistorySession("menu")
end

---------------------------------------------------------------------------
-- 2. The reset arrow of a settings row goes through history and the combat guard.
---------------------------------------------------------------------------
do
    local W = M.Widgets
    local parent = env.CreateFrame("Frame", nil, M.frame)
    parent:SetSize(500, 300)
    parent._msuf2Width = 500
    local key = "smokeSettingsRowValue"
    local function Value() return M.EnsureDB().general[key] end
    M.EnsureDB().general[key] = true
    local resetCalls = 0
    local built = W.SettingsRows({ key = "smoke", width = 500 }, parent, { rows = {
        { id = "smokeRow", kind = "toggle", label = "Smoke row toggle",
            get = function() return Value() == true end,
            set = function(v) M.EnsureDB().general[key] = v and true or false end,
            reset = function() resetCalls = resetCalls + 1 M.EnsureDB().general[key] = false end },
    } })
    local button = built and built.resets[1]
    if Check(button ~= nil, "the settings row has no reset button") then
        assert(M.StartHistorySession("menu"), "the menu history session did not start")
        M.ClearHistory()

        -- In combat: refused, nothing written, nothing recorded.
        mw.world.widgets:SetCombat(true)
        env.InCombatLockdown = function() return true end
        button.scripts.OnClick(button)
        env.InCombatLockdown = function() return false end
        mw.world.widgets:SetCombat(false)
        Check(resetCalls == 0 and Value() == true, "the row reset ran in combat")
        Check(M.GetHistoryState().undoCount == 0, "a refused row reset left an undo entry")

        -- Out of combat: written once, one undo step, and Undo brings the value back.
        button.scripts.OnClick(button)
        Check(resetCalls == 1 and Value() == false, "the row reset did not write its default")
        local state = M.GetHistoryState()
        Check(state.undoCount == 1, "the row reset left " .. state.undoCount .. " undo entries, not 1")
        Check(state.canUndo and M.Undo() == true and Value() == true, "Undo did not restore the value the row reset replaced")
        Check(M.Redo() == true and Value() == false, "Redo did not bring the reset back")

        M.EnsureDB().general[key] = nil
        M.ClearHistory()
        M.EndHistorySession("menu")
    end
end

if #failures > 0 then
    error("menu_unit_db_rows_guard_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_unit_db_rows_guard_smoke: " .. flavor .. " ok (unknown units have no table, settings row resets are guarded and undoable)")
