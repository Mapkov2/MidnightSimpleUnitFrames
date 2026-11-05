-- Disabled indicators and stopped pool bars must resume through their real owners.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local clients = arg[2] and { arg[2] } or { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }

local function Run(flavor)
    local world = World.New(root, { flavor = flavor })
    local ns, env = world.core, world.env
    ns.Require("MSUF_EnsureDB", "idle castbar lifecycle")(true)
    local general = env.MSUF_DB.general
    for _, key in ipairs({ "kickReadyShowTarget", "kickReadyShowFocus", "kickReadyShowBoss", "kickReadyShowArena",
        "enableFocusKickIcon", "kickReadyShowNameplates" }) do general[key] = false end
    general.kickReadyStyle, general.showGCDBar = "box", false
    general.enableFocusKickIcon = true
    local cb, ready = ns.Castbars, ns.Castbars.KickReady
    cb.Config.Invalidate()
    ns.Require("MSUF_Castbars_OnSettingsChanged", "idle castbar lifecycle")()
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
    local frame = assert(cb.Frames.Get("target"))
    local stopWatch = world.Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua", { strict = true })

    -- Rebinding A -> B -> A at the same revision must retire B's visuals.
    frame.MSUF_castActive, frame.isNotInterruptible, frame.MSUF_kickInterruptibleConfirmed = true, false, true
    ready.KickReady_RefreshFrame(frame)
    ready.KickReady_RefreshFrame(frame)
    assert(not frame.kickReadyBox, "disabled target created an indicator")
    frame.unit = "focus"
    ready.KickReady_RefreshFrame(frame)
    assert(frame.kickReadyBox and frame.kickReadyBox:IsShown(), "focus override did not activate after rebind")
    frame.unit = "target"
    ready.KickReady_RefreshFrame(frame)
    assert(not frame.kickReadyBox:IsShown(), "rebound disabled target retained the focus indicator")

    -- A new profile revision must activate a previously disabled frame.
    general.kickReadyShowTarget = true
    cb.Config.Invalidate()
    ready.KickReady_RefreshFrame(frame)
    assert(frame.kickReadyBox:IsShown(), "profile enable did not reactivate the indicator")
    general.kickReadyShowTarget = false
    cb.Config.Invalidate()
    ready.KickReady_RefreshFrame(frame)
    assert(not frame.kickReadyBox:IsShown(), "profile disable retained an existing indicator")
    local violations = stopWatch()
    assert(#violations == 0, table.concat(violations, "\n"))
    frame.MSUF_castActive = false

    -- Lifecycle bursts must be quiet after cleanup, while a new cast and an
    -- interrupt hold must still run terminal cleanup and detach active owners.
    cb.Pools.ApplyBossCastbarsEnabled()
    local boss = cb.Frames.Get("boss", 1)
    if boss then
        local runtime, calls = cb.Runtime, 0
        local reset = runtime.CB_ResetStateOnStop
        runtime.CB_ResetStateOnStop = function(...)
            calls = calls + 1
            return reset(...)
        end
        local function ExpectStopped()
            assert(boss.MSUF_castActive == false and not boss:IsShown() and not boss.interrupted,
                "pool stop retained a cast or interrupt hold")
            assert(not boss.events.UNIT_HEALTH, "stopped pool retained active health subscription")
            assert(not runtime._activeDurationFrames[boss], "stopped pool retained duration ownership")
        end
        cb.Pools.Stop(boss)
        ExpectStopped()
        local before = calls
        for _ = 1, 3 do cb.Pools.Stop(boss) end
        assert(calls == before, "idle lifecycle burst repeated complete cleanup")
        world:StartCast("boss1", "Frostbolt", 10, 41)
        world:Fire(boss, "UNIT_SPELLCAST_START", world:Payload("UNIT_SPELLCAST_START", "boss1", 41))
        assert(boss.MSUF_castActive == true and boss:IsShown(), "new cast did not resume a stopped pool bar")
        cb.Pools.Stop(boss)
        assert(calls == before + 1, "new cast was skipped by idle-stop reuse")
        ExpectStopped()
        world:StartCast("boss1", "Frostbolt", 10, 42)
        world:Fire(boss, "UNIT_SPELLCAST_START", world:Payload("UNIT_SPELLCAST_START", "boss1", 42))
        world:Fire(boss, "UNIT_SPELLCAST_INTERRUPTED", world:Payload("UNIT_SPELLCAST_INTERRUPTED", "boss1", 42))
        assert(boss.interrupted and boss:IsShown(), "fixture did not enter interrupt feedback")
        cb.Pools.Stop(boss)
        ExpectStopped()
        runtime.CB_ResetStateOnStop = reset
    end
    assert(#world.errors == 0, table.concat(world.errors, "\n"))
    print("PASS castbar idle lifecycle: " .. flavor)
end

for _, flavor in ipairs(clients) do Run(flavor) end
