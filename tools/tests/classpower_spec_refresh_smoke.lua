-- classpower_spec_refresh_smoke.lua <repoRoot>
-- Real controller: player-only spec events and one delayed rebuild per burst.

local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))()
local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local events = { "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "UPDATE_SHAPESHIFT_FORM" }

local function Run(flavor, lite, backend)
    local filters = {}
    local t = World.Start(root, flavor, "ROGUE", 1, World.PT.ENERGY, nil, {
        beforeLoad = function(env)
            if backend == "scheduler" then
                assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))(
                    "MidnightSimpleUnitFrames", MSUF_NS)
            end
            local register = env.Methods.RegisterUnitEvent
            env.Methods.RegisterUnitEvent = function(frame, event, unit, ...)
                filters[frame] = filters[frame] or {}
                filters[frame][event] = unit
                return register(frame, event, unit, ...)
            end
        end,
    })
    local label = flavor .. (lite and " lite " or " full ") .. backend
    Check(filters[t.eventFrame] and filters[t.eventFrame].PLAYER_SPECIALIZATION_CHANGED == "player",
        label .. ": specialization event is not registered for player only")
    MSUF_DB.general.perfLiteClassPowerEvents = lite
    t.ns.PublicGlobals.MSUF_ClassPower_Refresh() -- a namespace-only export, not a global
    t.env:RunTimers()
    local fullRefresh = World.Upvalue(t.module.Enable, "FullRefresh")
    local rareEvent = World.Upvalue(t.onEvent, "ClassPowerOnRareEvent")
    local structuralEvent = World.Upvalue(rareEvent, "CP_HandleRareStructuralEvent")
    local calls, structuralCalls = 0, 0
    debug.sethook(function()
        local fn = debug.getinfo(2, "f").func
        if fn == fullRefresh then calls = calls + 1 end
        if fn == structuralEvent then structuralCalls = structuralCalls + 1 end
    end, "c")
    local setters = World.CountSetters(t, function()
        t.onEvent(t.eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "raid2")
        t.onEvent(t.eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "party1")
        t.env:RunTimers()
    end)
    Check(calls == 0 and setters == 0 and structuralCalls == 0,
        label .. ": another player's spec event refreshed class power")
    calls = 0
    -- Turning the display off changes the real structural signature on all
    -- clients; the whole burst must apply the final profile state once.
    MSUF_DB.bars.showClassPower = false
    for _, event in ipairs(events) do t.onEvent(t.eventFrame, event, "player") end
    Check(calls == 0, label .. ": structural refresh was not delayed")
    local pending = #t.env.timers
    Check(pending == 1, label .. ": structural burst queued " .. pending .. " timers instead of one")
    local firstTimer = t.env.timers[1]
    Check(firstTimer and firstTimer.delay == 0.1, label .. ": structural settle delay changed")
    t.env:RunTimers()
    Check(calls == 1, label .. ": structural burst performed " .. calls .. " full refreshes instead of one")
    Check(not t.CP.visible, label .. ": deferred refresh did not apply the final display state")
    -- A later burst must be allowed to queue again, using the same callback.
    calls = 0
    MSUF_DB.bars.showClassPower = true
    for _, event in ipairs(events) do t.onEvent(t.eventFrame, event, "player") end
    local secondTimer = t.env.timers[1]
    Check(firstTimer and secondTimer and firstTimer.callback == secondTimer.callback,
        label .. ": structural bursts did not reuse their callback")
    t.env:RunTimers()
    Check(calls == 1, label .. ": a second burst did not perform exactly one full refresh")
    debug.sethook()
end

for _, backend in ipairs({ "timer", "scheduler" }) do
    for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
        for _, lite in ipairs({ true, false }) do Run(flavor, lite, backend) end
    end
end

-- A real Midnight spec transition switches the Warlock renderer after the burst.
do
    local t = World.Start(root, "Mainline", "WARLOCK", 1, World.PT.MANA)
    local oldMode = t.CP.renderMode
    t.S.spec = 3
    for _, event in ipairs(events) do t.onEvent(t.eventFrame, event, "player") end
    t.env:RunTimers()
    Check(t.CP.visible and t.CP.renderMode ~= oldMode, "spec swap failed to switch the Warlock renderer")
end

if #failures > 0 then error("classpower_spec_refresh_smoke:\n  " .. table.concat(failures, "\n  "), 0) end
print("classpower_spec_refresh_smoke: ok (player-only events, coalesced bursts, renderer change)")
