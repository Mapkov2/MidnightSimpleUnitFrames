-- group_gone_state_smoke.lua <repoRoot> <flavor>
--
-- The group dead/offline background (Group Frames > "dead background") on the
-- real core (tools/tests/health_tick_world.lua: the group runtime on the
-- SecureGroupHeader emulator, strict secrets, counted natives).
--
-- The 2026-10-02 raid trace measured the gone-state chain on every group
-- health tick (UpdateGoneState, UpdateDeadBg, ResolveGone, ReadDeadCached:
-- about 73 ms per 13.7k ticks). Since W4-C1 Health's sink resolves a
-- UNIT_HEALTH tick by itself and stops when the state stays as it is, and
-- ReadDeadCached reads UnitIsDeadOrGhost once (it used to turn the alive
-- `false` into nil and read UnitIsDead as well). Pinned, through the frames'
-- own OnEvent routes:
--   * a plain alive tick reads no death state;
--   * plain death and resurrection on UNIT_HEALTH;
--   * protected (secret) health: one UnitIsDeadOrGhost read per tick and no
--     UnitIsDead, death and resurrection still reach the background;
--   * a dead unit's background is repainted after every health-gradient
--     repaint of the same tick;
--   * ghost through UNIT_FLAGS, offline and back through UNIT_CONNECTION.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor, { deadBgOffline = true })
local S, frame, Secrets = w.S, w.group, w.Secrets
local UNIT = "raid1"

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
end

local cfg = assert(frame._msufGFVisualRuntimeGroup, "raid1 has no group visual runtime")
local DEAD_R = cfg.deadBgR or 0.6
Check(frame._msufHealthBgDynamic == true, "the health-gradient background is not dynamic")

local function Gone() return frame._msufGFDeadBgState == true end
local function DeadPainted()
    local bg = frame.bg
    local r = bg and bg.vr
    return r ~= nil and not Secrets.IsSecret(r) and r == DEAD_R
end

local function Tick(pct, dead)
    S.pct, S.dead = pct, dead
    w:StartCounting()
    w:Fire(frame, UNIT, "UNIT_HEALTH")
    return w:StopCounting()
end

local function Scenario(secret)
    local label = secret and "protected" or "plain"
    S.secret, S.absorb, S.connected = secret, 0, true
    w:Prime(frame, UNIT)
    Tick(0.7, false)
    local calls = Tick(0.6, false)
    Check(not Gone(), label .. ": a living unit shows the dead background")
    if secret then
        Check((calls.UnitIsDeadOrGhost or 0) == 1 and (calls.UnitIsDead or 0) == 0, string.format(
            "%s: an alive tick read the death state %d + %d times, want one UnitIsDeadOrGhost",
            label, calls.UnitIsDeadOrGhost or 0, calls.UnitIsDead or 0))
    else
        Check((calls.UnitIsDeadOrGhost or 0) + (calls.UnitIsDead or 0) == 0,
            label .. ": a plain alive tick read the death state")
    end

    -- Death on a health tick.
    Tick(secret and 0.3 or 0, true)
    Check(Gone() and DeadPainted(), label .. ": a death on UNIT_HEALTH did not reach the dead background")
    -- The gradient background repaints every tick; the dead colour follows it.
    calls = Tick(secret and 0.3 or 0, true)
    Check(Gone() and DeadPainted(), label .. ": a later tick left the gradient over the dead background")
    -- Resurrection.
    Tick(0.4, false)
    Check(not Gone() and not DeadPainted(), label .. ": a resurrection kept the dead background")
end

if flavor == "Mainline" then Scenario(true) end
Scenario(false)

-- Ghost through UNIT_FLAGS (health may stay positive).
S.secret = false
Tick(0.5, false)
S.dead = true
w:Fire(frame, UNIT, "UNIT_FLAGS")
Check(Gone(), "UNIT_FLAGS: a ghost does not show the dead background")
S.dead = false
w:Fire(frame, UNIT, "UNIT_FLAGS")
Check(not Gone(), "UNIT_FLAGS: the dead background stays after the unit came back")

-- Offline and back through UNIT_CONNECTION.
S.connected = false
w:Fire(frame, UNIT, "UNIT_CONNECTION", false)
Check(Gone(), "UNIT_CONNECTION: an offline unit does not show the dead background")
S.connected = true
w:Fire(frame, UNIT, "UNIT_CONNECTION", true)
Check(not Gone(), "UNIT_CONNECTION: the dead background stays after the unit reconnected")

if #failures > 0 then
    for index = 1, #failures do print("FAIL " .. failures[index]) end
    os.exit(1)
end
print("group_gone_state_smoke: ok (" .. flavor .. ")")
