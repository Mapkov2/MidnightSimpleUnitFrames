-- health_dispatch_free_death_smoke.lua <repoRoot>
--
-- The dominant UNIT_HEALTH routes (Libs/MSUFUnitFrames/MSUF_UF_Core.lua
-- BuildHealthRoute) run without BeginFrameEvent. The health colour reads the
-- frame's unit state through RefreshUnitState
-- (UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua), which returned
-- the previous dispatch's state for such a tick. A unit that died on that tick
-- kept its alive colour, and one that came back kept the dead grey, until some
-- other event refreshed the state.
--
-- Boots each client's real core through the client kit and pins: a death and a
-- resurrection on a dispatch-free UNIT_HEALTH tick reach the health colour, and
-- a plain alive tick still reads nothing.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local UNIT = "party1"

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    local dead, deadReads = false, 0
    env.UnitExists = function() return true end
    env.UnitIsConnected = function() return true end
    env.UnitIsDeadOrGhost = function(unit)
        if unit == UNIT then deadReads = deadReads + 1 end
        return dead
    end
    env.UnitIsPlayer = function() return true end
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local common = assert(world.core.UFBarTextCommon, flavor .. ": no bar/text common helpers")
    local apply = assert(common.ApplyHealthStatusColor, flavor .. ": ApplyHealthStatusColor is not exported")

    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = UNIT
    frame.MSUFSpec = { key = "party", health = { mode = "unified", r = 0.1, g = 0.7, b = 0.2 } }
    local bar = env.CreateFrame("StatusBar", nil, frame)
    frame.hpBar = bar

    -- A first full refresh (a dispatch) seeds the state: alive.
    frame._msufDispatchActive, frame._msufDispatchToken = true, 1
    apply(bar, frame, UNIT, 800, 1000, nil, "UNIT_HEALTH")
    frame._msufDispatchActive = nil
    Check(frame._msufHealthStatusGone == nil, flavor .. ": an alive unit reads as gone")

    -- A plain alive tick on the dispatch-free route reads nothing.
    deadReads = 0
    apply(bar, frame, UNIT, 700, 1000, nil, "UNIT_HEALTH")
    Check(deadReads == 0, flavor .. ": a plain alive health tick read the death state " .. deadReads .. " time(s)")

    -- The unit dies on a dispatch-free tick.
    dead = true
    apply(bar, frame, UNIT, 0, 1000, nil, "UNIT_HEALTH")
    Check(frame._msufHealthStatusGone == true,
        flavor .. ": a death on a dispatch-free UNIT_HEALTH tick kept the alive health colour")

    -- And comes back on one.
    dead = false
    apply(bar, frame, UNIT, 300, 1000, nil, "UNIT_HEALTH")
    Check(frame._msufHealthStatusGone == nil,
        flavor .. ": a resurrection on a dispatch-free UNIT_HEALTH tick kept the dead grey")
    print("health_dispatch_free_death_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
