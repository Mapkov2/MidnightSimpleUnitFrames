-- profile_switch_runtime_refresh_smoke.lua <repoRoot>
--
-- A profile switch, reset or import ends in ProfileRuntime.Apply. Runtime
-- owners whose state the module registry does not switch must be refreshed
-- there too, or the previous profile's state survives the switch:
--   1. Gameplay overlays. The registry runs the Gameplay module's Enable only
--      when its enabled state flips, and Player Totems keep it enabled in
--      practically every profile, so from the second switch of a session on
--      the combat timer kept the old profile's visibility (red without the
--      fix in State/MSUF_ProfileRuntime.lua).
--
-- Real core + Options graph (tools/tests/client_world.lua) and the real
-- MSUF_SwitchProfile -> ProfileRuntime.Apply path; only render steps the
-- harness cannot draw are no-ops. Events and timers reach each frame on
-- their own (test-side pcall), so an unrelated harness gap cannot hide these.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local RENDER_ONLY = {
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
    "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
    "MSUF_UpdateAllFonts_Immediate", "MSUF_ApplyMsufScale", "MSUF_ApplyCurrentProfileGlobalUiScale",
}

local function Fire(world, event, ...)
    local frames = world.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and (events[event] or events["*"]) then pcall(handler, frame, event, ...) end
    end
end

-- Deferred applies run through ScheduleOnce (OnUpdate) or C_Timer.
local function Settle(world)
    for _ = 1, 5 do
        local frames = world.widgets.frames
        for index = 1, #frames do
            local frame = frames[index]
            local scripts = rawget(frame, "scripts")
            if scripts and scripts.OnUpdate then pcall(scripts.OnUpdate, frame, 0.016) end
        end
        pcall(world.widgets.RunTimers, world.widgets, 300)
    end
end

local function Login(flavor, profiles, active)
    local world = World.New(root, flavor)
    rawset(world.env, "MAX_BOSS_FRAMES", 5)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": load failure in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_GlobalDB = {
            profiles = profiles,
            char = { ["Tester-Realm"] = { activeProfile = active } },
            global = { firstLoad6 = { schema = 1, revision = 1, installKind = "upgrade", status = "completed", step = "defaults" } },
        },
    })
    Fire(world, "PLAYER_LOGIN")
    Fire(world, "PLAYER_ENTERING_WORLD", true, false)
    Settle(world)
    for _, name in ipairs(RENDER_ONLY) do rawset(world.env, name, function() end) end
    world.core.UF.DisableBlizzardFrames = function() end
    -- Class power and rounded frames draw too; their registry switches are no-ops.
    local noop = function() end
    for _, module in ipairs(world.core.MSUF_Modules) do
        if module.key == "ClassPower" or module.key == "roundedUnitframes" then module.Enable, module.Disable = noop, noop end
    end
    return world
end

local function Switch(world, name)
    world.env.MSUF_SwitchProfile(name)
    Settle(world)
    assert(world.env.MSUF_ActiveProfile == name, world.flavor .. ": the switch to " .. name .. " did not happen")
end

local function GameplayProfile(timerOn)
    return { _msufProfileSchema = 600, gameplay = { enableCombatTimer = timerOn, lockCombatTimer = false } }
end

local function CheckGameplay(flavor)
    local world = Login(flavor, {
        Default = GameplayProfile(false), A = GameplayProfile(true), B = GameplayProfile(false), C = GameplayProfile(true),
    }, "A")
    local function Expect(step)
        local frame = world.core.MSUF_GetCombatTimerFrame()
        local want = world.env.MSUF_DB.gameplay.enableCombatTimer == true
        local shown = frame ~= nil and frame:IsShown() == true
        assert(shown == want, string.format("%s: after %s the combat timer is %s, but profile %s has it %s",
            flavor, step, shown and "shown" or "hidden", tostring(world.env.MSUF_ActiveProfile), want and "on" or "off"))
    end
    Expect("login on A")
    for _, name in ipairs({ "B", "C", "B", "C" }) do
        Switch(world, name)
        Expect("switching to " .. name)
    end
end

local flavors = World.Flavors(root)
for _, flavor in ipairs(flavors) do
    CheckGameplay(flavor)
end

print("profile_switch_runtime_refresh_smoke: ok (" .. table.concat(flavors, ", ") .. ")")
