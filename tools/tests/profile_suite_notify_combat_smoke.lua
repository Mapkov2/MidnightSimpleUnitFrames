-- profile_suite_notify_combat_smoke.lua <repoRoot>
--
-- State/MSUF_Profiles.lua tells the MSUF Suite (MSUFSuite.OnMSUFProfileChanged)
-- which frame profile is active, so the Suite and the Skin follow it. Profile
-- switches may run in combat (the specialization auto-switch); the runtime
-- apply is deferred to PLAYER_REGEN_ENABLED, but the Suite notification was
-- simply dropped, so the Suite stayed on the old profile until the next switch
-- (quality finding C4.8). Pinned on each client's real load graph:
--   * out of combat the Suite hears every change at once;
--   * in combat nothing reaches it, and the latest change is delivered exactly
--     once after combat;
--   * a combat end with nothing pending delivers nothing.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    -- Runtime helpers capture the client API during load; change its result,
    -- not the function identity after the real core graph has loaded.
    local inCombat = false
    env.InCombatLockdown = function() return inCombat end
    env.UnitAffectingCombat = function() return inCombat end
    env.MAX_BOSS_FRAMES = 5
    -- Native frame layout methods return numbers, unlike unknown-API stubs.
    world.env.TotemFrame = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    -- The runtime apply after a switch rebuilds every frame; that rebuild is
    -- not under test here and needs a live client, so its collaborators idle.
    for _, name in ipairs({ "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll",
        "MSUF_ClassPower_Apply", "MSUF_ApplyPowerBarEmbedLayout_All" }) do
        Check(type(env[name]) == "function", flavor .. ": the runtime apply lost " .. name)
        env[name] = function() end
    end
    local heard = {}
    env.MSUFSuite = { OnMSUFProfileChanged = function(name, reason) heard[#heard + 1] = { name = name, reason = reason } end }
    local print0 = env.print
    env.print = function() end
    env.MSUF_InitProfiles()
    local active = env.MSUF_ActiveProfile
    Check(type(active) == "string" and env.MSUF_CopyProfile(active, "Second") == true,
        flavor .. ": could not copy the active profile")
    local bus = world.core.EventBus
    local function RegenEnabled()
        inCombat = false
        bus.driver:GetScript("OnEvent")(bus.driver, "PLAYER_REGEN_ENABLED")
    end

    heard = {}
    Check(env.MSUF_SwitchProfile("Second") ~= false, flavor .. ": switch out of combat failed")
    Check(#heard == 1 and heard[1].name == "Second" and heard[1].reason == "PROFILE_SWITCH",
        flavor .. ": the Suite did not hear an out-of-combat switch")

    heard = {}
    inCombat = true
    Check(env.MSUF_SwitchProfile(active) ~= false, flavor .. ": switch in combat failed")
    Check(env.MSUF_SwitchProfile("Second") ~= false, flavor .. ": second switch in combat failed")
    Check(#heard == 0, flavor .. ": the Suite was notified in combat")
    RegenEnabled()
    Check(#heard == 1, flavor .. ": the combat switch reached the Suite " .. #heard .. " time(s) after combat, expected once")
    Check(heard[1].name == "Second" and heard[1].reason == "PROFILE_SWITCH",
        flavor .. ": the Suite heard " .. tostring(heard[1].name) .. " after combat, not the latest profile")
    RegenEnabled()
    Check(#heard == 1, flavor .. ": a combat end with nothing pending notified the Suite again")
    env.print = print0
    print("profile_suite_notify_combat_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
