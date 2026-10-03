-- castbar_secret_paths_smoke.lua <repoRoot>
--
-- Every castbar runtime path on a strict-secret Midnight client
-- (tools/tests/castbar_secret_world.lua): the real Mainline core boots, every
-- secret-capable value the castbars read is secret (cast and channel tuples,
-- event payloads, duration objects, cooldown and GCD info, empower stages,
-- spell target name and class, the colour objects of the curve and class
-- APIs), and a line watcher over every castbar file records each executed
-- comparison or truth test of a secret. The client raised "attempt to compare
-- local 'isReady' (a secret boolean value)" 136 times per raid from a value
-- that came out of a cooldown object; this smoke is the net for that class.
--
-- Covered, each with the castbar feature options switched on: target, focus,
-- boss and arena casts, channels, other units' empowered casts, pushback,
-- interruptibility events, interrupts (with the interrupter's name), failed and
-- stopped casts, kicked channels, unit death, target and focus swaps, the
-- castbar manager ticks to completion, the player castbar (cast, channel,
-- empower stages, interrupt, latency), the interrupt-ready box, border and fill
-- styles with the cooldown projection, the cooldown event and its native wake,
-- the GCD bar (attached and detached, readable and secret cooldowns), the
-- focus interrupt tracker and the WoW Forever swing timer.
--
-- The bar: no Lua error, no watched misuse, every listed function ran, and a
-- secret cast still shows its bar and name.
--
-- Plain Lua 5.1, repo root (absolute) as arg 1. MSUF_SMOKE_STYLES=box|border|
-- fill|forever runs one pass (mutation checks); MSUF_SMOKE_TRACE=1 names each
-- scenario on stderr.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local SecretWorld = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()

local failures = {}
local function Fail(message) failures[#failures + 1] = message end

local function Configure(env, style)
    env.MSUF_EnsureDB(true)
    local db = env.MSUF_DB
    local g = db.general
    g.kickReadyShowTarget, g.kickReadyShowFocus, g.kickReadyShowBoss, g.kickReadyShowArena = true, true, true, true
    g.kickReadyStyle = style
    g.kickReadyTimeMarker, g.kickReadyTimeSegment = true, true
    g.castbarTargetShowTargetName, g.castbarFocusShowTargetName = true, true
    g.showBossCastTargetName, g.showArenaCastTargetName = true, true
    g.castbarShowPushback = true
    g.castbarSpellNameShortening = 1
    g.castbarShowLatency, g.castbarShowLatencyText = true, true
    g.showGCDBar, g.showGCDBarTime, g.showGCDBarSpell = true, true, true
    g.enableFocusKickIcon, g.focusKickShowCastbar = true, true
    g.castbarShowGlow = true
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        db[unit] = db[unit] or {}
        db[unit].showInterruptSource = true
        db[unit].showInterrupt = true
    end
end

local function Scenario(world, label, fn)
    if os.getenv("MSUF_SMOKE_TRACE") then io.stderr:write("scenario ", label, "\n") end
    local before = #world.errors
    local ok, message = pcall(fn)
    if not ok then Fail(label .. ": " .. tostring(message)) end
    for index = before + 1, #world.errors do
        Fail(label .. " (deferred): " .. world.errors[index])
    end
end

local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_INTERRUPTIBLE" }

-- One unit castbar through its whole life: cast with pushback, interruptibility
-- flips, the manager ticks, a stop with its confirmation re-checks, a channel
-- that is kicked, an empowered channel, a cast that is interrupted, a failed
-- cast and unit death.
local function UnitCastbarLife(world, frame, unit, barID)
    local function Fire(event, interrupted, id)
        world:Fire(frame, event, world:Payload(event, unit, id or barID, interrupted))
    end
    world:StartCast(unit, "Shadow Bolt", 2.5, barID, { delayMS = 300 })
    for index = 1, #CAST_EVENTS do Fire(CAST_EVENTS[index]) end
    -- A secret cast still shows: the bar, its secret name and its native timer.
    if not (frame:IsShown() and frame.MSUF_castActive == true) then Fail(unit .. ": a secret cast does not show") end
    if not world.Secrets.IsSecret(frame.castText and frame.castText.text) then
        Fail(unit .. ": the secret spell name did not reach the cast text")
    end
    world:Advance(0.6)
    world.casting[unit] = nil
    Fire("UNIT_SPELLCAST_STOP")
    world:Advance(0.6)

    world:StartChannel(unit, "Mind Flay", 3, barID + 1)
    Fire("UNIT_SPELLCAST_CHANNEL_START", nil, barID + 1)
    world:Advance(0.4)
    Fire("UNIT_SPELLCAST_CHANNEL_UPDATE", nil, barID + 1)
    world.channeling[unit] = nil
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", true, barID + 1)
    world:Advance(0.8)

    world:StartChannel(unit, "Fire Breath", 2, barID + 2, { empowered = true })
    Fire("UNIT_SPELLCAST_EMPOWER_START", nil, barID + 2)
    world:Advance(0.3)
    Fire("UNIT_SPELLCAST_EMPOWER_UPDATE", nil, barID + 2)
    world.channeling[unit] = nil
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", nil, barID + 2)
    world:Advance(0.8)

    world:StartCast(unit, "Frostbolt", 2, barID + 3)
    Fire("UNIT_SPELLCAST_START", nil, barID + 3)
    world:Advance(0.3)
    world.casting[unit] = nil
    Fire("UNIT_SPELLCAST_INTERRUPTED", true, barID + 3)
    -- A secret interrupter falls back to the plain label.
    if frame.castText and frame.castText.text ~= "Interrupted" then
        Fail(unit .. ": the interrupt feedback shows " .. tostring(frame.castText.text))
    end
    world:Advance(1.2)

    world:StartCast(unit, "Fireball", 1.5, barID + 4)
    Fire("UNIT_SPELLCAST_START", nil, barID + 4)
    world.casting[unit] = nil
    Fire("UNIT_SPELLCAST_FAILED", nil, barID + 4)
    world:Advance(0.8)

    world:StartCast(unit, "Pyroblast", 3, barID + 5)
    Fire("UNIT_SPELLCAST_START", nil, barID + 5)
    world:Advance(0.2)
    world.dead[unit] = true
    world:Fire(frame, "UNIT_HEALTH", unit)
    world:Fire(frame, "UNIT_FLAGS", unit)
    world.dead[unit] = nil
    world.casting[unit] = nil
    world:Advance(0.5)

    -- A cast that runs to its end through the manager.
    world:StartCast(unit, "Arcane Blast", 0.8, barID + 6)
    Fire("UNIT_SPELLCAST_START", nil, barID + 6)
    world:Advance(1.2)
    world.casting[unit] = nil
    Fire("UNIT_SPELLCAST_SUCCEEDED", nil, barID + 6)
    world:Advance(0.6)
end

local function PlayerCastbarLife(world, frame)
    local function Fire(event, interrupted, id)
        world:Fire(frame, event, world:Payload(event, "player", id, interrupted))
    end
    world:StartCast("player", "Fireball", 2, 70, { delayMS = 200 })
    Fire("UNIT_SPELLCAST_START", nil, 70)
    world:Advance(0.4)
    Fire("UNIT_SPELLCAST_DELAYED", nil, 70)
    Fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    Fire("UNIT_SPELLCAST_INTERRUPTIBLE")
    world:Advance(0.4)
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_INTERRUPTED", true, 70)
    world:Advance(1)

    world:StartCast("player", "Frostbolt", 1.5, 71)
    Fire("UNIT_SPELLCAST_START", nil, 71)
    world:Advance(1.8)
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_STOP", nil, 71)
    world:Advance(0.3)

    world:StartChannel("player", "Arcane Missiles", 2, 72)
    Fire("UNIT_SPELLCAST_CHANNEL_START", nil, 72)
    world:Advance(0.5)
    Fire("UNIT_SPELLCAST_CHANNEL_UPDATE", nil, 72)
    world.channeling.player = nil
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", nil, 72)
    world:Advance(0.6)

    world:StartCast("player", "Fire Breath", 3, 73, { empowered = true })
    Fire("UNIT_SPELLCAST_EMPOWER_START", nil, 73)
    world:Advance(1.5)
    Fire("UNIT_SPELLCAST_EMPOWER_UPDATE", nil, 73)
    world:Advance(0.5)
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", nil, 73)
    world:Advance(0.5)

    world:StartCast("player", "Scorch", 1, 74)
    Fire("UNIT_SPELLCAST_START", nil, 74)
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_FAILED", nil, 74)
    world:Advance(0.5)

    -- STOP before INTERRUPTED keeps the cast's identity for the late payload.
    -- A restricted payload's castGUID is secret: its NeverSecret castBarID
    -- decides (before 2026-10-03 the feedback was dropped). Another cast's
    -- castBarID is rejected; without castBarIDs a plain castGUID decides.
    local function LateInterrupt(label, secretStart, castBarID, payload, shown)
        world.secretCasts = secretStart
        world:StartCast("player", "Polymorph", 1.5, castBarID)
        Fire("UNIT_SPELLCAST_START", nil, castBarID)
        world.secretCasts = true
        world.casting.player = nil
        Fire("UNIT_SPELLCAST_STOP", nil, castBarID)
        if frame.interruptFeedbackEndTime ~= nil then Fail("player castbar: " .. label .. ": feedback before the interrupt") end
        world:Fire(frame, "UNIT_SPELLCAST_INTERRUPTED", payload())
        if (frame.interruptFeedbackEndTime ~= nil) ~= shown then
            Fail("player castbar: " .. label .. (shown and ": no interrupt feedback" or ": another cast's interrupt shown"))
        end
        world:Advance(0.8)
    end
    local S = world.Secrets.New
    LateInterrupt("readable cast, restricted late INTERRUPTED", false, 75,
        function() return "player", S("string"), S(), S("string"), 75 end, true)
    LateInterrupt("restricted cast, restricted late INTERRUPTED", true, 76,
        function() return "player", S("string"), S(), S("string"), 76 end, true)
    LateInterrupt("late INTERRUPTED of another cast", true, 77,
        function() return "player", S("string"), S(), S("string"), 99 end, false)
    LateInterrupt("readable late INTERRUPTED without castBarID", false, nil,
        function() return "player", "Polymorph-guid", 133, nil, nil end, true)
    LateInterrupt("readable late INTERRUPTED of another castGUID", false, nil,
        function() return "player", "Other-guid", 133, nil, nil end, false)
end

local function FindFrame(world, predicate)
    local frames = world.widgets.frames
    for index = 1, #frames do
        if predicate(frames[index]) then return frames[index] end
    end
end

local function GCDLife(world)
    local env = world.env
    local driver = world:Named("MSUF_GCDBarDriver")
    if not driver then Fail("GCD bar driver missing") return end
    env.MSUF_GCDBar_SyncRegistration()
    for _, secret in ipairs({ false, true }) do
        world.secretCooldowns = secret
        world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
        -- The player's own instant cast: the spell ID payload is readable. The
        -- bar shows for the GCD and ends with it, readable or secret.
        world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", world.Secrets.New("string"), 1449)
        local bar = env.MSUF_DB.general.gcdBarDetached and world:Named("MSUF_DetachedGCDBar") or env.MSUF_PlayerCastbar
        if not (bar and bar._msufGCDActive == true) then Fail("GCD bar did not start (secret " .. tostring(secret) .. ")") end
        world:Advance(1.8)
        if bar and bar._msufGCDActive == true then Fail("GCD bar did not end (secret " .. tostring(secret) .. ")") end
        -- A restricted payload: the spell ID is secret.
        world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
        world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", world:Payload("UNIT_SPELLCAST_SUCCEEDED", "player", nil))
        world:Advance(1.8)
    end
    -- A secret GCD ends on its native completion (1.5 s), well before its
    -- 2.5 s cap; a readable GCD 2.0 s after it with 0.55 s left must keep its
    -- own deadline. Before 2026-10-03 the completion left the cap armed, and
    -- at 2.5 s it ended the readable GCD early.
    world.secretCooldowns = true
    world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
    world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", world.Secrets.New("string"), 1449)
    local bar = env.MSUF_DB.general.gcdBarDetached and world:Named("MSUF_DetachedGCDBar") or env.MSUF_PlayerCastbar
    world:Advance(2.0)
    if bar and bar._msufGCDActive == true then Fail("secret GCD did not end on its native completion") end
    world.secretCooldowns = false
    world.cooldowns[61304] = { startTime = world.clock - 0.95, total = 1.5 }
    world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", world.Secrets.New("string"), 1449)
    world:Advance(0.52)
    if not (bar and bar._msufGCDActive == true) then
        Fail("the secret GCD's cap ended the readable GCD after it early")
    end
    world:Advance(0.3)
    if bar and bar._msufGCDActive == true then Fail("readable GCD after a secret one did not end") end
    world.secretCooldowns = true
end

local function InterruptReadyLife(world)
    local env = world.env
    local eventFrame = world:Named("MSUF_InterruptReady_EventFrame")
    if not eventFrame then Fail("interrupt-ready event frame missing") return end
    local target = env.MSUF_TargetCastBar
    for _, secret in ipairs({ false, true }) do
        world.secretCooldowns = secret
        world:StartCast("target", "Shadow Bolt", 3, 90)
        world:Fire(target, "UNIT_SPELLCAST_START", world:Payload("UNIT_SPELLCAST_START", "target", 90))
        world.cooldowns[2139] = { startTime = world.clock, total = 0.6 }
        world:Fire(eventFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139)
        world:Fire(eventFrame, "SPELL_UPDATE_COOLDOWN", nil, nil)
        env.MSUF_KickReady_RefreshAll()
        -- The native completion wake of every armed slot fires on its own.
        world:Advance(0.8)
        world:Fire(eventFrame, "SPELLS_CHANGED")
        world:Fire(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
        world.casting.target = nil
        world:Fire(target, "UNIT_SPELLCAST_STOP", world:Payload("UNIT_SPELLCAST_STOP", "target", 90))
        world:Advance(0.8)
    end
    world.secretCooldowns = true
end

local function PoolLife(world, poolGlobal, unit, lifecycleEvent, lifecyclePayload)
    local env = world.env
    local pool = env[poolGlobal]
    local bar = pool and pool[1]
    if not bar then Fail(poolGlobal .. "[1] missing") return end
    UnitCastbarLife(world, bar, unit, 40)
    -- The lifecycle pass refreshes a bar whose unit is casting.
    world:StartCast(unit, "Shadow Bolt", 2, 49)
    local pools = world.core.Castbars and world.core.Castbars.Pools
    local kind = pools and pools.kinds[unit:match("^(%a+)")]
    if kind then
        kind.HandleLifecycle(lifecycleEvent, lifecyclePayload)
        world:Advance(0.2)
    else
        Fail("pool kind for " .. unit .. " missing")
    end
    world.casting[unit] = nil
    world:Advance(2.5)
end

-- Functions every Mainline pass must have run, by castbar file: the smoke is
-- only as good as the paths it reaches.
local REQUIRED = {
    ["MSUF_CastbarEngine.lua"] = { "BuildState", "ResolveTargetInfo" },
    ["MSUF_CastbarDriver.lua"] = { "HandleDriverEvent", "RefreshTargetFocusChanged", "ScheduleStopConfirmation",
        "HandleUnitDeathEvent", "UpdateCastTargetText", "ApplyCastTargetTextColor", "MSUF_Castbar_ResolveInterruptLabel",
        "SetInterrupted", "SetSucceeded", "Cast", "FillEmpoweredLikeCast", "UpdateColorForInterruptible" },
    ["MSUF_CastbarRuntime.lua"] = { "ApplyActive", "ApplyTimer", "SnapshotDuration", "PrepareWork",
        "ApplyNativeTimeText", "Stop", "ApplyInterruptValues" },
    ["MSUF_Castbars.lua"] = { "RegisterCastbar", "UpdateCastbarFrame", "UpdateDurationObjectFrame",
        "CheckChannelHardStop", "UpdateEmpowerFrame", "InferRemainingFromStatusBar" },
    ["MSUF_CastbarUtils.lua"] = { "ApplyNonInterruptibleTint", "ShortenCastbarSpellName", "ComposeCastText",
        "PushbackSuffix", "ResolveCastbarPushbackMS", "PlainNumber" },
    ["MSUF_PlayerCastbarRuntime.lua"] = { "ApplyActiveCast", "ShowInterruptFeedback", "UpdateLatencyZone",
        "StopPlayerCastbar", "IsDifferentActiveCast", "PlayerCastbarOnEventImpl", "UpdateColorForInterruptible" },
    ["MSUF_CastbarEmpower.lua"] = { "PlayerCastbarEmpowerStart", "BuildEmpowerTimeline", "LayoutEmpowerTicks",
        "PlayerCastbarClearEmpower" },
    ["MSUF_InterruptReady.lua"] = { "RefreshFrame", "EvaluateIndicatorRGBA", "CombinedStatus",
        "ScheduleCooldownRefresh", "HandleCooldownWakeDone", "RefreshTimeProjection", "CooldownEventAlreadyDisplayed" },
    ["MSUF_CastbarGCD.lua"] = { "OnSucceeded", "StartGCDBar", "ArmFinish", "FinishWake", "OnFinishTimer",
        "FinishGCDBar", "GCDStillActive", "GCDActive", "RefreshDetached" },
    ["MSUF_FocusKickIcon.lua"] = { "ApplyCastState", "ApplyInterruptibilityColor", "AttachTimeDriver",
        "PlayInterruptFeedback", "RefreshReadyColor" },
    ["MSUF_FocusKick_StateDriver.lua"] = { "OnEngineState", "ApplyState" },
    ["MSUF_CastbarPools.lua"] = { "RefreshFromUnit", "HandleLifecycle", "OnPoolFrameEvent", "PrepareForCast" },
}
local STYLE_REQUIRED = {
    box = { "ApplyBoxLayout" },
    border = { "TintOutline" },
    fill = { "MarkActiveFillFrame" },
}

local function CheckCoverage(world, style, coverage)
    local function Require(file, name)
        local line = world:FunctionLine(file, name)
        if not line then Fail(style .. ": coverage list names " .. file .. " " .. name .. ", which does not exist")
        elseif not (coverage[file] and coverage[file][line]) then
            Fail(style .. ": " .. file .. " " .. name .. " (line " .. line .. ") never ran")
        end
    end
    for file, names in pairs(REQUIRED) do
        for index = 1, #names do Require(file, names[index]) end
    end
    for index = 1, #STYLE_REQUIRED[style] do Require("MSUF_InterruptReady.lua", STYLE_REQUIRED[style][index]) end
end

local function RunMainline(style)
    local world = SecretWorld.New(root)
    local env = world.env
    Configure(env, style)
    env.MSUF_Castbars_OnSettingsChanged()
    env.MSUF_KickReady_RefreshAll()
    env.MSUF_FocusKickDriver_ForceUpdate()
    world:Advance(0.5)
    -- Work other modules queued at boot is not this smoke's subject.
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    local stop = world:Watch(world:CastbarPaths())
    Scenario(world, style .. " target", function() UnitCastbarLife(world, env.MSUF_TargetCastBar, "target", 10) end)
    Scenario(world, style .. " focus", function() UnitCastbarLife(world, env.MSUF_FocusCastBar, "focus", 20) end)
    Scenario(world, style .. " target swap", function()
        world:StartCast("target", "Shadow Bolt", 2, 30)
        world:Fire(env.MSUF_TargetCastBar, "PLAYER_TARGET_CHANGED")
        world:StartChannel("focus", "Drain Life", 2, 31)
        world:Fire(env.MSUF_FocusCastBar, "PLAYER_FOCUS_CHANGED")
        world:Advance(0.5)
        world.casting.target, world.channeling.focus = nil, nil
        world:Fire(env.MSUF_TargetCastBar, "PLAYER_TARGET_CHANGED")
        world:Fire(env.MSUF_FocusCastBar, "PLAYER_FOCUS_CHANGED")
        world:Advance(0.5)
    end)
    Scenario(world, style .. " boss", function()
        PoolLife(world, "MSUF_BossCastbars", "boss1", "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    end)
    Scenario(world, style .. " arena", function()
        PoolLife(world, "MSUF_ArenaCastbars", "arena1", "ARENA_OPPONENT_UPDATE", "arena1")
    end)
    Scenario(world, style .. " player", function() PlayerCastbarLife(world, env.MSUF_PlayerCastbar) end)
    Scenario(world, style .. " interrupt ready", function() InterruptReadyLife(world) end)
    Scenario(world, style .. " GCD attached", function()
        env.MSUF_DB.general.gcdBarDetached = false
        GCDLife(world)
    end)
    Scenario(world, style .. " GCD detached", function()
        env.MSUF_DB.general.gcdBarDetached = true
        env.MSUF_GCDBar_RefreshLayout()
        GCDLife(world)
    end)
    local violations, coverage = stop()
    for index = 1, #violations do Fail(style .. ": " .. violations[index]) end
    CheckCoverage(world, style, coverage)
    return world
end

-- WoW Forever: the Mainline castbars plus the native swing timer bars.
local FOREVER_REQUIRED = {
    ["SwingTimer.lua"] = { "Start", "Stop", "RefreshVisibility", "SyncRanges", "PaintReach", "UpdateCue", "OnEvent",
        "BindTimer" },
    ["MSUF_CastbarDriver.lua"] = { "HandleDriverEvent", "SetInterrupted" },
    ["MSUF_PlayerCastbarRuntime.lua"] = { "ApplyActiveCast", "ShowInterruptFeedback" },
}

local function RunForever()
    local world = SecretWorld.New(root, { flavor = "Forever", playerClass = "WARRIOR" })
    local env = world.env
    Configure(env, "box")
    env.MSUF_DB.swingTimers = { enabled = true }
    env.MSUF_Castbars_OnSettingsChanged()
    local swing = world.core.MSUF_ModulesByKey and world.core.MSUF_ModulesByKey.SwingTimers
    if not swing then Fail("Forever: the swing timer module is not registered") return end
    swing.Enable(swing)
    for _, hand in ipairs({ "main", "off", "ranged" }) do
        world.core.SwingTimer.Set(hand, "reachCheck", true)
        world.core.SwingTimer.Set(hand, "enabled", true)
    end
    world.core.SwingTimer.Set("main", "offhandLane", true)
    world:Advance(0.5)
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    local driver = FindFrame(world, function(frame)
        local scripts = rawget(frame, "scripts")
        return scripts and scripts.OnEvent and frame.events.PLAYER_SWING_RANGE_UPDATE
            and debug.getinfo(scripts.OnEvent, "S").source:find("SwingTimer.lua", 1, true) ~= nil
    end)
    if not driver then Fail("Forever: the swing driver does not listen") return end
    local stop = world:Watch(world:CastbarPaths())
    local S = world.Secrets.New
    Scenario(world, "Forever swing", function()
        for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_ATTACK_SPEED", "WEAPON_SLOT_CHANGED",
            "PLAYER_REGEN_DISABLED", "PLAYER_IN_COMBAT_CHANGED", "PLAYER_TARGET_CHANGED",
            "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_UPDATE_STATE" }) do
            world:Fire(driver, event, event == "UNIT_ATTACK_SPEED" and "player" or nil)
        end
        world:Fire(driver, "PLAYER_SWING", 2.4, 0)
        world:Fire(driver, "PLAYER_SWING", 1.8, 1)
        world:Fire(driver, "PLAYER_SWING", 2.9, 2)
        world:Fire(driver, "PLAYER_SWING_RANGE_UPDATE", 0, S("boolean"), S("boolean"))
        world:Advance(0.5)
        world:Fire(driver, "WEAPON_SLOT_CHANGED")
        world:Fire(driver, "CVAR_UPDATE", "showSwingTimer", "1")
        world:Advance(2.5)
    end)
    Scenario(world, "Forever target", function() UnitCastbarLife(world, env.MSUF_TargetCastBar, "target", 10) end)
    Scenario(world, "Forever player", function() PlayerCastbarLife(world, env.MSUF_PlayerCastbar) end)
    local violations, coverage = stop()
    for index = 1, #violations do Fail("Forever: " .. violations[index]) end
    for file, names in pairs(FOREVER_REQUIRED) do
        for index = 1, #names do
            local line = world:FunctionLine(file, names[index])
            if not (line and coverage[file] and coverage[file][line]) then
                Fail("Forever: " .. file .. " " .. names[index] .. " never ran")
            end
        end
    end
end

-- The watcher's own rule (SecretWorld.Misuses): a guard counts only when the
-- expression really short-circuits the use. Before 2026-10-03 it read the
-- names alone, so `i == 1 or (frame.speed ~= nil ...)` passed as `i or ...`
-- and the Forever swing timer's secret attack-speed compare went unseen.
local function WatcherSelfTest(secrets)
    local secret = secrets.New("number")
    local secretFlag = secrets.New("boolean")
    local function Case(line, name, locals, value, expected)
        local got = SecretWorld.Misuses(line, name, locals, value) == true
        if got ~= expected then
            Fail(("watcher self-test: %q with %s reads as %s"):format(line, name, got and "a misuse" or "guarded"))
        end
    end
    local function L(extra)
        local locals = { speed = secret, frame = { speed = secret } }
        for key, value in pairs(extra or {}) do locals[key] = value end
        return locals
    end
    Case("local equipped = i == 1 or (frame.speed ~= nil and Equipped(frame.speed))", "frame.speed", L({ i = 2 }), secret, true)
    Case("local equipped = i == 1 or (frame.speed ~= nil and Equipped(frame.speed))", "frame.speed", L({ i = 1 }), secret, false)
    Case("local equipped = i ~= 1 and frame.speed ~= nil", "frame.speed", L({ i = 1 }), secret, false)
    Case("if hand == \"main\" or speed == nil then", "speed", L({ hand = "off" }), secret, true)
    Case("if hand == \"main\" or speed == nil then", "speed", L({ hand = "main" }), secret, false)
    Case("local x = flag or speed ~= nil", "speed", L({ flag = true }), secret, false)
    Case("local x = flag or speed ~= nil", "speed", L({ flag = false }), secret, true)
    Case("local x = not flag and speed ~= nil", "speed", L({ flag = true }), secret, false)
    Case("local x = not flag and speed ~= nil", "speed", L({ flag = false }), secret, true)
    Case("local x = flag and speed ~= nil", "speed", L({ flag = false }), secret, false)
    Case("local x = flag and other or speed ~= nil", "speed", L({ flag = false, other = 1 }), secret, true)
    Case("local x = (flag or other) and speed ~= nil", "speed", L({ flag = true, other = 1 }), secret, true)
    Case("local x = count + flag or speed ~= nil", "speed", L({ flag = true, count = 1 }), secret, true)
    Case("local x = issecretvalue(speed) or speed > 0", "speed", L(), secret, false)
    Case("if ready then", "ready", L({ ready = secretFlag }), secretFlag, true)
    Case("if known and ready then", "ready", L({ known = false, ready = secretFlag }), secretFlag, false)
    Case("if known == 2 and ready then", "ready", L({ known = 1, ready = secretFlag }), secretFlag, false)
    Case("if known == 2 and ready then", "ready", L({ known = 2, ready = secretFlag }), secretFlag, true)
end

for _, style in ipairs(os.getenv("MSUF_SMOKE_STYLES") and { os.getenv("MSUF_SMOKE_STYLES") } or { "box", "border", "fill" }) do
    if style == "forever" then RunForever() else RunMainline(style) end
end
if not os.getenv("MSUF_SMOKE_STYLES") then RunForever() end
WatcherSelfTest(assert(SecretWorld.CurrentSecrets(), "no secret world ran"))

if #failures > 0 then
    error(("castbar_secret_paths_smoke: %d failure(s):\n  %s"):format(#failures, table.concat(failures, "\n  ")), 0)
end
print("castbar_secret_paths_smoke: ok (target, focus, boss, arena, player, interrupt-ready box/border/fill, GCD,"
    .. " focus tracker on a strict-secret Midnight client; WoW Forever swing timer and castbars)")
