-- Issue 165: real Player events must release channel textures before Empower.
-- Channel STOP defers its resync; an Empower in that gap makes it skip cleanup.
-- Covers both spells, three/four stages, restricted cast tuples, custom marker
-- pools, update-only recovery, resize, repeated casts, and return to channels.
local root = assert(arg[1], "repository root missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Visible(textures)
    local count = 0
    for _, texture in ipairs(textures or {}) do
        if texture:IsShown() then count = count + 1 end
    end
    return count
end
local function Fire(world, frame, event, id)
    world:Fire(frame, event, world:Payload(event, "player", id))
end
local function NewWorld(secret, markers)
    local world = World.New(root, { budget = true, playerClass = "EVOKER", setup = function(env, w)
        -- Retail obtains its stage count from UnitChannelInfo. Invalid stage
        -- indices return a non-positive duration; no invented count API.
        env.GetUnitEmpowerStageCount = nil
        env.IsPlayerSpell = function() return false end
        env.C_SpellBook.IsSpellKnownOrInSpellBook = function() return false end
        env.GetUnitEmpowerStageDuration = function(unit, index)
            local cast = w.channeling[unit]
            if not (cast and cast.empowered) or index < 0 or index >= w.stages then return -1 end
            return (index == 0 and 900 or 600) * (w.hasteScale or 1)
        end
        env.GetUnitEmpowerHoldAtMaxTime = function() return 600 end
        local channelInfo = env.UnitChannelInfo
        env.UnitChannelInfo = function(unit)
            local a, b, c, d, e, f, g, h, empowered, stages, id = channelInfo(unit)
            if empowered then stages = w.stages end
            return a, b, c, d, e, f, g, h, empowered, stages, id
        end
    end })
    local env = world.env
    env.MSUF_EnsureDB(true)
    local general = env.MSUF_DB.general
    general.showGCDBar, general.castbarShowChannelTicks = false, markers > 0
    general.empowerColorStages, general.empowerStageBlink = false, false
    if markers ~= 3 then
        local settings = env.MSUF_DB.player.castbar or {}
        env.MSUF_DB.player.castbar = settings
        settings.channelTickUseCustom, settings.channelTickCount = true, markers
    end
    env.MSUF_Castbars_OnSettingsChanged()
    world:Advance(0.5)
    -- Existing full-core fixtures discard unrelated startup callbacks too.
    for index = #world.errors, 1, -1 do world.errors[index] = nil end
    world.secretCasts = secret
    return world, assert(env.MSUF.Castbars.Frames.Get("player"))
end
local function AssertEmpower(world, frame, stages, label)
    Check(frame:IsShown() and frame.isEmpower == true, label .. ": Empower missing")
    Check(Visible(frame._msufPlayerChannelHasteMarkers) == 0, label .. ": old channel ticks survived")
    Check(frame._msufPlayerChannelTickRuntimeActive == nil, label .. ": channel resize owner survived")
    Check(Visible(frame.empowerTicks) == stages, label .. ": wrong Empower stage count")
    local total = 0
    for index = 1, stages do
        total = total + (index == 1 and 0.9 or 0.6) * (world.hasteScale or 1)
        Check(math.abs(frame.empowerStageEnds[index] - total) < 0.000001, label .. ": stage timing changed")
    end
    Check(math.abs(frame.empowerTotalWithGrace - total - 0.6) < 0.000001, label .. ": hold time changed")
end

for _, secret in ipairs({ false, true }) do
    for _, markers in ipairs({ 0, 3, 10 }) do
        local world, frame = NewWorld(secret, markers)
        local stopWatch = world:Watch(world:CastbarPaths())
        for _, spell in ipairs({ { "Fire Breath", 357208 }, { "Eternity Surge", 359073 } }) do
            for stages = 3, 4 do
                for _, firstEvent in ipairs({ "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE" }) do
                    for _, handoff in ipairs({ "deferred", "no_stop", "interrupted" }) do
                        world.stages = stages
                        world.hasteScale = stages == 3 and 1 or 0.65
                        world:StartChannel("player", "Disintegrate", 3, 100, { spellID = 356995 })
                        Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", 100)
                        -- A restricted spell ID uses the intentional five-tick
                        -- fallback unless a custom count was explicitly selected.
                        local expected = secret and markers == 3 and 5 or markers
                        Check(Visible(frame._msufPlayerChannelHasteMarkers) == expected, "preceding channel fixture")
                        world.channeling.player = nil
                        if handoff == "deferred" then
                            Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_STOP", 100)
                            Check(frame._msufSoftResyncPending == true, "channel stop must defer its resync")
                        elseif handoff == "interrupted" then
                            world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_STOP",
                                world:Payload("UNIT_SPELLCAST_CHANNEL_STOP", "player", 100, true))
                        end
                        world:StartChannel("player", spell[1], (0.9 + (stages - 1) * 0.6) * world.hasteScale,
                            101, { empowered = true, spellID = spell[2] })
                        local label = spell[1] .. "/" .. stages .. "/" .. firstEvent .. "/" .. handoff
                        Fire(world, frame, firstEvent, 101)
                        AssertEmpower(world, frame, stages, label)
                        Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_UPDATE", 101)
                        frame.statusBar:SetWidth(frame.statusBar:GetWidth() + 1)
                        world:Advance(0.1)
                        AssertEmpower(world, frame, stages, label .. " after resync/update/resize")
                        world.channeling.player = nil
                        Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_STOP", 101)
                        Check(Visible(frame.empowerTicks) == 0, "Empower stop leaked its own ticks")
                        Check(Visible(frame._msufPlayerChannelHasteMarkers) == 0, "Empower stop revived channel ticks")
                        world:Advance(0.1)
                    end
                end
            end
        end
        -- An Empower recovered by an update owns its cast identity: the terminal
        -- events of the preceding channel (old castBarID) cannot end it, while its
        -- own kick still reaches interrupt feedback.
        world.stages, world.hasteScale = 3, 1
        world:StartChannel("player", "Disintegrate", 3, 110, { spellID = 356995 })
        Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", 110)
        world.channeling.player = nil
        Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_STOP", 110)
        world:StartChannel("player", "Fire Breath", 2.7, 111, { empowered = true, spellID = 357208 })
        Fire(world, frame, "UNIT_SPELLCAST_EMPOWER_UPDATE", 111)
        AssertEmpower(world, frame, 3, "recovery identity")
        world.env.MSUF_DB.player.showInterrupt = true
        local feedback = frame.interruptFeedbackEndTime
        for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
            world:Fire(frame, event, world:Payload(event, "player", 110, true))
            Check(frame.isEmpower == true and frame.interruptFeedbackEndTime == feedback,
                "preceding channel " .. event .. " ended the recovered Empower")
        end
        AssertEmpower(world, frame, 3, "recovery identity after old terminal events")
        world:Fire(frame, "UNIT_SPELLCAST_CHANNEL_STOP", world:Payload("UNIT_SPELLCAST_CHANNEL_STOP", "player", 111, true))
        Check(frame:IsShown() and frame.isEmpower ~= true and frame.castText.text == "Interrupted"
            and frame.interruptFeedbackEndTime ~= nil and frame.interruptFeedbackEndTime ~= feedback,
            "the recovered Empower's own kick showed no feedback")
        world.channeling.player = nil
        world:Advance(1.2)
        world:StartChannel("player", "Disintegrate", 3, 102, { spellID = 356995 })
        Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", 102)
        local expected = secret and markers == 3 and 5 or markers
        Check(Visible(frame._msufPlayerChannelHasteMarkers) == expected, "normal channel ticks lost after Empower")
        local violations = stopWatch()
        Check(#violations == 0, "secret misuse: " .. table.concat(violations, " | "))
        Check(#world.errors == 0, "deferred error: " .. table.concat(world.errors, " | "))
    end
end

-- Measure just the changed event boundary, using the real cleanup and pooled
-- textures. Exclude the unchanged Empower timeline builder from this budget.
local function Upvalue(fn, name)
    for index = 1, 60 do
        local key, value = debug.getupvalue(fn, index)
        if key == name then return value, index end
        if key == nil then break end
    end
    error("missing upvalue " .. name)
end
local world, frame = NewWorld(false, 10)
world:StartChannel("player", "Disintegrate", 3, 200, { spellID = 356995 })
Fire(world, frame, "UNIT_SPELLCAST_CHANNEL_START", 200)
local impl = Upvalue(world.core.Castbars.Player.PlayerCastbar_OnEvent, "playerEventHandler")
local handler = Upvalue(impl, "HandleEmpowerEvent")
local _, startIndex = Upvalue(handler, "CallEmpowerStart")
debug.setupvalue(handler, startIndex, function() end)
local hides = 0
for _, marker in ipairs(frame._msufPlayerChannelHasteMarkers) do
    local hide = marker.Hide
    marker.Hide = function(self) hides = hides + 1; hide(self) end
end
local function Cleanup()
    frame._msufPlayerChannelTickRuntimeActive = true
    handler(frame, "UNIT_SPELLCAST_EMPOWER_UPDATE")
end
local function IdleUpdate()
    handler(frame, "UNIT_SPELLCAST_EMPOWER_UPDATE")
end
Cleanup()
Check(hides == 10, "cleanup must hide each pooled marker once")
-- A real update inside a running Empower: the frame already owns its identity.
frame.isEmpower = true
IdleUpdate()
frame.isEmpower = nil
Check(hides == 10, "repeated Empower update rescanned inactive channel textures")
local timers = world.timerCount
local function Measure(fn)
    for _ = 1, 40 do fn() end
    local vm = world:AddonInstructions(fn)
    local bytes = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do fn() end
        bytes = math.min(bytes, (collectgarbage("count") - before) * 1024 / 1000)
        collectgarbage("restart")
    end
    return vm, bytes
end
local activeVM, activeBytes = Measure(Cleanup)
frame.isEmpower = true
local idleVM, idleBytes = Measure(IdleUpdate)
frame.isEmpower = nil
-- 2026-10-16: frozen at the measured 114/16 VM instructions (10 pooled markers).
-- The cleanup is an Empower start or a recovery by update (frame not yet
-- empowering), which also adopts the cast identity (7 instructions); an update
-- inside a running Empower only tests that state (2 more than before). The
-- former boundary measured separately.
Check(activeVM <= 114 and idleVM <= 16, "Empower cleanup VM budget regressed")
Check(activeBytes <= 1 and idleBytes <= 1, "Empower cleanup allocates per event")
Check(world.timerCount == timers, "Empower cleanup scheduled a timer")
print(string.format("Empower cleanup: %d checks; active10 %d VM / %.2f bytes; idle %d VM / %.2f bytes",
    checks, activeVM, activeBytes, idleVM, idleBytes))
