-- prediction_queued_glow_tick_smoke.lua <repoRoot> <flavor>
--
-- Protected over-absorb glow: one render per rendered frame when a prediction
-- data event is queued (raid trace 2026-10-07).
-- The trace counted 11,772 glow renders
-- (ShowProtectedOverAbsorb, about 160 ms inclusive, UnitGetDetailedHealPrediction
-- 81.8 ms): 9,483 from the UNIT_HEALTH follower and 2,289 from the prediction
-- queue drain. In its frame dump every drain ran after all events of its frame,
-- and 121 of 377 follower renders fell into a frame whose unit was already
-- queued, so the drain rendered the glow again before the frame was drawn.
-- UNIT_HEALTH, UNIT_ABSORB_AMOUNT_CHANGED and UNIT_HEAL_PREDICTION are
-- synchronous events (UnitDocumentation.lua), so both renders read the same
-- unit state.
--
-- Pinned on the real core (tools/tests/health_tick_world.lua, strict secrets):
--   1. absorb queued, then a health tick: the tick leaves the glow to the
--      drain; the frame makes one calculator read and one flag write, and the
--      glow ends on the drain's flag;
--   2. heal or heal-absorb queued (their drain plans draw no glow), then a
--      tick: the drain repeats the deferred tick once, after its own writes;
--   3. a tick on an unqueued frame still renders at once;
--   4. a cold Apply that drops the queued entry also drops the deferral;
--   5. no owned line compares or truth-tests a secret on these routes;
--   6. the absorb-only writer (no heal lanes) settles a deferred tick too.
--
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2 (a client with secrets).

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor)
local S = w.S
local PREDICTION = "UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"

-- The prediction queue's render-frame driver: the frame whose OnUpdate script
-- is the Prediction file's queue drain.
local function Drain()
    local frames = w.h.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local script = frame.scripts and frame.scripts.OnUpdate
        if script and debug.getinfo(script, "S").source:find(PREDICTION, 1, true) then
            if frame:IsShown() then script(frame, 1 / 60) end
            return
        end
    end
end

-- The calculator flag each render hands to the glow's one sink.
local lastFlag = {}
local function Track(frame)
    local calc = assert(frame._msufPredictionOverAbsorbCalc, "no over-absorb calculator after a protected tick")
    local read = calc.GetDamageAbsorbs
    calc.GetDamageAbsorbs = function(self)
        local amount, clamped = read(self)
        lastFlag[frame] = clamped
        return amount, clamped
    end
end

-- Native calls since the previous window; counting restarts at once.
local function Window()
    local calls = w:StopCounting()
    w:StartCounting()
    return calls
end
local function Reads(calls) return calls.UnitGetDetailedHealPrediction or 0 end
local function Flags(calls) return calls.SetAlphaFromBoolean or 0 end

local function GlowSettled(label, frame)
    local holder = frame.overAbsorbGlowBar
    local glow = holder and holder._msufOverAbsorbGlowTexture
    Check(glow ~= nil, label .. ": no glow texture")
    Check(rawequal(glow.alphaBoolean, lastFlag[frame]), label .. ": the glow does not carry the last calculator flag")
    Check(holder._msufOverAbsorbShown == true, label .. ": the glow holder is hidden")
    Check(frame._msufPredictionGlowDeferred == nil, label .. ": a deferred tick survived the drain")
    Check(frame._msufPredictionQueued == nil, label .. ": the frame is still queued")
end

local step = 0
local function Health(frame, unit)
    step = step + 1
    S.pct = 0.61 + (step % 20) / 100
    w:Fire(frame, unit, "UNIT_HEALTH")
end

local function Frames(label, frame, unit)
    -- 1. Absorb queued, then a health tick.
    w:StartCounting()
    w:Fire(frame, unit, "UNIT_ABSORB_AMOUNT_CHANGED")
    Check(frame._msufPredictionQueued == true, label .. ": the absorb event did not queue")
    Window()
    Health(frame, unit)
    local tick = Window()
    Check(Reads(tick) == 0 and Flags(tick) == 0, label .. ": a queued frame rendered the glow on its health tick")
    Check(frame._msufPredictionGlowDeferred == true, label .. ": the queued tick was not deferred")
    Drain()
    local drain = w:StopCounting()
    Check(Reads(drain) == 1 and Flags(drain) == 1,
        label .. ": absorb drain: " .. Reads(drain) .. " calculator reads, " .. Flags(drain) .. " flag writes, want 1 and 1")
    GlowSettled(label .. " absorb queued", frame)

    -- 2. A drain whose plan draws no glow repeats the deferred tick.
    for _, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
        local mask = event == "UNIT_HEAL_PREDICTION" and 1 or 4
        local plan = frame._msufPredictionEventPlans and frame._msufPredictionEventPlans[mask]
        Check(plan ~= nil and not plan[5], label .. ": " .. event .. " plan draws the absorb lane; the case is gone")
        w:Fire(frame, unit, event)
        Check(frame._msufPredictionQueued == true, label .. ": " .. event .. " did not queue")
        w:StartCounting()
        Health(frame, unit)
        tick = Window()
        Check(Reads(tick) == 0, label .. ": " .. event .. ": the queued tick rendered")
        Drain()
        drain = w:StopCounting()
        Check(Reads(drain) == 1 and Flags(drain) == 1,
            label .. ": " .. event .. ": the drain did not repeat the deferred tick once")
        GlowSettled(label .. " " .. event .. " queued", frame)
    end

    -- 3. An unqueued tick renders at once; the later drain renders again.
    w:StartCounting()
    Health(frame, unit)
    tick = Window()
    Check(Reads(tick) == 1, label .. ": an unqueued tick did not render at once")
    w:Fire(frame, unit, "UNIT_ABSORB_AMOUNT_CHANGED")
    Drain()
    drain = w:StopCounting()
    Check(Reads(drain) == 1, label .. ": the drain after an unqueued tick did not render")
    GlowSettled(label .. " tick then absorb", frame)
end

local function Scenarios(label, frame, unit)
    S.secret, S.absorb, S.incoming, S.dead = true, 0.6, 0, false
    w:Prime(frame, unit)
    Health(frame, unit)
    Check(frame._msufPredictionOverAbsorbOverlay == true, label .. ": the over-absorb overlay is off")
    Check(frame._msufPredictionAbsorbSecret == true, label .. ": the absorb is not protected")
    Track(frame)
    Frames(label, frame, unit)
    -- 5. The same frames under the strict secret watcher, one owned file each.
    for index = 1, #World.OWNED do
        local stop = w.Watch(root .. "/" .. World.OWNED[index])
        Frames(label, frame, unit)
        local violations = stop()
        Check(#violations == 0, label .. ": a secret was inspected: " .. table.concat(violations, "; "))
    end
end

Scenarios("raid1", w.group, "raid1")
Scenarios("target", w.single, "target")

-- 4. A cold Apply drops the queued entry and the deferral with it, also when
--    the new spec turns the overlay off (its update draws no glow).
do
    local frame = w.single
    local spec = w.UF.Config.GetSpec("target")
    w:Fire(frame, "target", "UNIT_ABSORB_AMOUNT_CHANGED")
    Health(frame, "target")
    Check(frame._msufPredictionGlowDeferred == true, "target: the queued tick was not deferred before Apply")
    spec.prediction.overAbsorbOverlay = false
    w.UF.ApplySpec(frame, spec, "MSUF_APPLY", true)
    Check(frame._msufPredictionQueued == nil, "target: Apply left the frame queued")
    Check(frame._msufPredictionGlowDeferred == nil, "target: Apply left a deferred tick behind")
    Check(frame.overAbsorbGlowBar._msufOverAbsorbShown == false, "target: the glow stayed up without the overlay")
    spec.prediction.overAbsorbOverlay = true
end

-- 6. Absorb-only prediction with the overlay drains through the shared absorb
--    writer instead of the general plan; it settles a deferred tick as well.
do
    local frame = w.single
    local spec = w.UF.Config.GetSpec("target")
    spec.prediction.heal, spec.prediction.healAbsorb = false, false
    w.UF.ApplySpec(frame, spec, "MSUF_APPLY", true)
    Check(frame._msufPredictionMask == 2 and frame._msufPredictionSimpleAbsorb == nil,
        "target: absorb-only overlay did not bind a queued absorb writer")
    S.secret, S.absorb = true, 0.6
    w:Fire(frame, "target", "UNIT_ABSORB_AMOUNT_CHANGED")
    Drain()
    Health(frame, "target")
    Track(frame)
    w:StartCounting()
    w:Fire(frame, "target", "UNIT_ABSORB_AMOUNT_CHANGED")
    Check(frame._msufPredictionQueued == true, "target absorb-only: the absorb event did not queue")
    Window()
    Health(frame, "target")
    local tick = Window()
    Check(Reads(tick) == 0, "target absorb-only: the queued tick rendered")
    Drain()
    local drain = w:StopCounting()
    Check(Reads(drain) == 1 and Flags(drain) == 1, "target absorb-only: the drain rendered "
        .. Reads(drain) .. " times, want once")
    GlowSettled("target absorb-only", frame)
end

print("prediction_queued_glow_tick_smoke: ok (" .. flavor .. ")")
