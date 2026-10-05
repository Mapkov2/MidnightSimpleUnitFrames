-- menu_editmode_foreign_globals_smoke.lua <repoRoot>
--
-- The Dashboard asked the menu's Edit Mode helpers to "include Blizzard",
-- which read the globals IsEditModeActive and IsEditModeCombatLocked. Neither
-- exists on any client (Blizzard has only the method
-- EditModeManagerFrameMixin:IsEditModeActive and no combat lock: mirror
-- Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua), so the flag
-- did nothing, except that a global of that name from another addon decided
-- whether MSUF Edit Mode counted as combat locked (bh2 R-C7-06). The helpers
-- now read MSUF's own state and the combat lockdown only.
--
-- Boots the real Midnight core and Options graph. Plain Lua 5.1, repo root.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_editmode_foreign_globals_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Mainline")
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env, M = world.env, world.core.MSUF2
Check(M and M.IsEditModeCombatLocked and M.EditModeLifecycleStatus, "the menu Edit Mode helpers did not load")

-- Another addon's globals with the names the helpers used to read.
env.IsEditModeCombatLocked = function() return false end
env.IsEditModeActive = function() return true end
world:EnterCombat()
Check(M.IsEditModeCombatLocked(true) == true, "a foreign IsEditModeCombatLocked global unlocked MSUF Edit Mode in combat")
local status = M.EditModeLifecycleStatus(true)
Check(status.combatLocked == true and status.active == false,
    "the Edit Mode status followed foreign globals (active " .. tostring(status.active) .. ")")
world:LeaveCombat()
Check(M.IsEditModeCombatLocked(true) == false, "Edit Mode stayed combat locked after combat")

print("menu_editmode_foreign_globals_smoke: ok (Edit Mode state and combat lock come from MSUF and the lockdown only)")
