-- afk_timer_combat_return_smoke.lua <repoRoot>
--
-- The AFK duration text next to the AFK status text hides when combat starts
-- and comes back when it ends. The hide in
-- UnitFrames/Engine/Elements/MSUF_UF_Elements_StatusAFKTimer.lua called the
-- font string's Hide() directly, while the status runtime shows it through
-- Apply.Shown, which keeps its own shown cache: after the first combat that
-- cache still said "shown", the re-show wrote nothing and the timer never
-- returned.
--
-- Boots each client's real core through the client kit, drives the real status
-- runtime and enters and leaves combat in the client's order.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local UNIT, GUID = "party1", "Player-1-0000AFK1"

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    local afk = false
    env.UnitExists = function(unit) return unit == UNIT or unit == "player" end
    env.UnitIsConnected = function() return true end
    env.UnitIsAFK = function(unit) return unit == UNIT and afk end
    env.UnitIsDND = function() return false end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsDead = function() return false end
    env.UnitIsGhost = function() return false end
    env.UnitGUID = function(unit) if unit == UNIT then return GUID end end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local Runtime = assert(world.core.UFStatusRuntime, flavor .. ": no status runtime")

    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = UNIT
    frame.statusIndicatorText = frame:CreateFontString(nil, "OVERLAY")
    local status = { statusText = { enabled = true, showAFK = true, afkTimer = { enabled = true, layer = 5 } } }
    frame._msufStatusIndicatorStatus = status

    -- The AFK-on edge is observed out of combat.
    afk = true
    world:FireEvent("PLAYER_FLAGS_CHANGED", UNIT)
    Runtime.UpdateStatusText(frame, status, "PLAYER_FLAGS_CHANGED")
    local timer = frame.statusAFKTimerText
    Check(timer and timer:IsShown(), flavor .. ": the AFK timer does not show for an AFK member")

    world:EnterCombat()
    Check(not timer:IsShown(), flavor .. ": the AFK timer stays visible in combat")
    world:LeaveCombat()
    Check(timer:IsShown(), flavor .. ": the AFK timer did not come back after combat")

    -- And again: the second fight hides and restores it the same way.
    world:EnterCombat()
    Check(not timer:IsShown(), flavor .. ": the AFK timer stays visible in the second combat")
    world:LeaveCombat()
    Check(timer:IsShown(), flavor .. ": the AFK timer did not come back after the second combat")
    print("afk_timer_combat_return_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
