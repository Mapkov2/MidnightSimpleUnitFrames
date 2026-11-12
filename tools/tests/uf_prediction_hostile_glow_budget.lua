-- uf_prediction_hostile_glow_budget.lua <repoRoot> <flavor> [print]
--
-- Native-call budget of a health tick on a single frame that shows a hostile
-- unit (owner decision 2026-11-11). Raid trace 2026-11-11 (Perfy session
-- 20261111-183826-retail-raid, 24-player kill, 300 s): the boss1 and target
-- frames rendered the protected over-absorb glow on every UNIT_HEALTH,
-- 16,023 + 15,792 times, each with UnitGetDetailedHealPrediction,
-- calc:GetDamageAbsorbs, a UnitHealthPercent step curve and
-- SetAlphaFromBoolean (follower subtree about 533 ms, 1.8 ms/s). A single
-- frame whose unit the player can attack now draws no over-absorb glow: the
-- decision is taken once per unit change and on UNIT_FACTION
-- (UnitCanAttack, not secret-returning), never per tick; the absorb bar is
-- still driven by its absorb events. Group frames and friendly units keep
-- the glow and today's per-tick cost.
--
-- Boots the real core through tools/tests/health_tick_world.lua (raid trace
-- profile: over-absorb overlay, gradient missing-health background) with a
-- counted UnitCanAttack. Mainline runs the protected (strict secret) ticks,
-- Vanilla the plain ones. "print" (or MSUF_BUDGET_MEASURE=1) reports only.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local PRINT = arg[3] == "print" or os.getenv("MSUF_BUDGET_MEASURE") == "1"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

-- Hostility model: per unit token; secret answers on request.
local H = { hostile = {}, secret = false, calls = 0 }
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor, { beforeFile = function(_, env)
    env.UnitCanAttack = function(unit, other)
        if H.counting then H.calls = H.calls + 1 end
        if H.secret and H.NewSecret then return H.NewSecret("boolean") end
        return unit == "player" and H.hostile[other] == true
    end
end })
H.NewSecret = w.Secrets.New
local S, group, single, UF = w.S, w.group, w.single, w.UF
local protectedClient = flavor == "Mainline"

-- Budgets per tick. A native not listed must stay at 0. VM limits sit about
-- 2 % above the measurement.
local GLOW = { UnitGetDetailedHealPrediction = 1, ["calc:GetDamageAbsorbs"] = 1, SetAlphaFromBoolean = 1 }
local BUDGETS = {
    -- Before: 11 natives and 316 instructions, as "unit protected" in
    -- health_tick_native_budget_smoke (UnitHealthPercent 5 with the step curve).
    ["hostile protected"] = { natives = { UnitHealthPercent = 4, SetValue = 2, SetVertexColor = 1 }, k = 213 },
    -- Absorb event, health tick, drain: the absorb bar still reads and
    -- writes its value; no calculator. Before: 14 natives, 646 instructions.
    ["hostile protected queued"] = { natives = { UnitHealthPercent = 4, UnitGetTotalAbsorbs = 1,
        SetValue = 3, SetVertexColor = 1 }, k = 470 },
    -- Plain (Classic, out of combat): no calculator either way; the glow is
    -- hidden by Lua. Before: 525 instructions.
    ["hostile plain overflow"] = { natives = { UnitHealthPercent = 1, SetValue = 2, SetVertexColor = 1 }, k = 328 },
}

local PRED_EVENTS_HAS = function(frame, name)
    local element = assert(UF.elements and UF.elements.Prediction, "Prediction element missing")
    local list = element.GetEvents(frame, frame.MSUFSpec)
    for index = 1, #list do if list[index] == name then return true end end
    return false
end

local function Drain()
    local frames = w.h.widgets.frames
    for index = 1, #frames do
        local driver = frames[index]
        local script = driver.scripts and driver.scripts.OnUpdate
        if script and debug.getinfo(script, "S").source:find("MSUF_UF_Prediction_Queue.lua", 1, true) then
            if driver:IsShown() then script(driver, 1 / 60) end
            return
        end
    end
    error("prediction queue driver missing")
end

local step = 0
local function Tick(frame, unit, queued)
    step = step + 1
    S.pct = 0.61 + (step % 20) / 100
    if queued then w:Fire(frame, unit, "UNIT_ABSORB_AMOUNT_CHANGED") end
    w:Fire(frame, unit, "UNIT_HEALTH")
    if queued then Drain() end
end

-- A unit change: the target frame's own identity route (PLAYER_TARGET_CHANGED).
local function Retarget()
    w:Fire(single, nil, "PLAYER_TARGET_CHANGED")
    w:Prime(single, "target")
end

local function GlowShown(frame)
    local holder = frame.overAbsorbGlowBar
    return holder ~= nil and holder._msufShown == true
end

local TICKS = 10
local ADDON_SOURCE = "@" .. root .. "/MidnightSimpleUnitFrames/"
local results = {}
local function Measure(label, frame, unit, queued)
    for _ = 1, 3 do Tick(frame, unit, queued) end
    if S.secret then
        for index = 1, #World.OWNED do
            local stop = w.Watch(root .. "/" .. World.OWNED[index])
            Tick(frame, unit, queued)
            local violations = stop()
            Check(#violations == 0, label .. ": a secret was inspected: " .. table.concat(violations, "; "))
        end
    end
    H.calls, H.counting = 0, true
    w:StartCounting()
    for _ = 1, TICKS do Tick(frame, unit, queued) end
    local calls = w:StopCounting()
    H.counting = false
    local result = { label = label, natives = {}, canAttack = H.calls / TICKS }
    for name, count in pairs(calls) do
        if not World.PREDICATES[name] then result.natives[name] = count / TICKS end
    end
    local instructions = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and info.source:find(ADDON_SOURCE, 1, true) then instructions = instructions + 1 end
    end, "", 1)
    for _ = 1, TICKS do Tick(frame, unit, queued) end
    debug.sethook()
    result.k = instructions / TICKS
    results[#results + 1] = result
    return result
end

local function Report(result)
    local names, parts, total = {}, {}, 0
    for name in pairs(result.natives) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        parts[#parts + 1] = name .. " " .. result.natives[name]
        total = total + result.natives[name]
    end
    return string.format("%s: natives %g (%s), UnitCanAttack %g, %.0f instructions", result.label, total,
        table.concat(parts, ", "), result.canAttack, result.k)
end

local function Enforce(result)
    if PRINT then return end
    local budget = BUDGETS[result.label]
    Check(result.canAttack == 0, result.label .. ": hostility was resolved on a health tick")
    if not budget then return end
    for name, count in pairs(result.natives) do
        local limit = budget.natives[name] or 0
        Check(count <= limit, string.format("%s: %s %g per tick, budget %g", result.label, name, count, limit))
    end
    Check(result.k <= budget.k, string.format("%s: %.0f VM instructions per tick, budget %d",
        result.label, result.k, budget.k))
end

local function GlowNatives(result)
    local n = 0
    for name in pairs(GLOW) do n = n + (result.natives[name] or 0) end
    return n
end

-- Registration: the single overlay frame listens for UNIT_FACTION, the group frame does not.
Check(single._msufPredictionOverAbsorbOverlay == true, "target: the over-absorb overlay is off")
Check(PRED_EVENTS_HAS(single, "UNIT_FACTION"), "target: Prediction does not re-decide hostility on UNIT_FACTION")
Check(not PRED_EVENTS_HAS(group, "UNIT_FACTION"), "raid1: a group frame registers UNIT_FACTION for prediction")

S.secret, S.absorb, S.incoming, S.dead = protectedClient, 0.6, 0, false

-- 1. Friendly target: today's per-tick glow is unchanged.
H.hostile.target = false
Retarget()
local friendly = Measure(protectedClient and "friendly protected" or "friendly plain overflow", single, "target")
Enforce(friendly)
if protectedClient then
    Check(friendly.natives.UnitGetDetailedHealPrediction == 1, "friendly target lost its per-tick glow query")
end
Check(single._msufPredictionOverAbsorbOverlay == true, "friendly target: overlay off")

-- 2. Hostile target: one decision at the unit change, no glow natives per tick.
H.hostile.target = true
H.calls, H.counting = 0, true
Retarget()
H.counting = false
Check(H.calls >= 1, "the unit change did not resolve hostility")
Check(single._msufPredictionOverAbsorbOverlay == false, "hostile target: overlay still on")
Check(not GlowShown(single), "hostile target: the over-absorb glow is still shown")
Check(single.absorbBar and single.absorbBar._msufShown == true, "hostile target: the absorb bar is hidden")
local hostile = Measure(protectedClient and "hostile protected" or "hostile plain overflow", single, "target")
Enforce(hostile)
Check(GlowNatives(hostile) == 0, "hostile target: a health tick still renders the glow")
Check(not GlowShown(single), "hostile target: a health tick showed the glow")
if protectedClient then
    local queued = Measure("hostile protected queued", single, "target", true)
    Enforce(queued)
    Check(GlowNatives(queued) == 0, "hostile target: an absorb event still queries the calculator")
    Check((queued.natives.UnitGetTotalAbsorbs or 0) == 1, "hostile target: the absorb bar no longer reads absorbs")
end

-- 3. UNIT_FACTION turns the unit friendly: the glow comes back at once.
H.hostile.target = false
w:Fire(single, "target", "UNIT_FACTION")
Check(single._msufPredictionOverAbsorbOverlay == true, "UNIT_FACTION did not restore the friendly glow")
local back = Measure(protectedClient and "refriended protected" or "refriended plain overflow", single, "target")
Enforce(back)
if protectedClient then
    Check(back.natives.UnitGetDetailedHealPrediction == 1, "refriended target: no per-tick glow")
else
    Check(GlowShown(single), "refriended target: the overflowing glow is not shown")
end

-- ... and hostile again through UNIT_FACTION.
H.hostile.target = true
w:Fire(single, "target", "UNIT_FACTION")
Check(single._msufPredictionOverAbsorbOverlay == false, "UNIT_FACTION did not drop the hostile glow")
Check(not GlowShown(single), "UNIT_FACTION left the hostile glow shown")

-- 4. A secret hostility answer keeps the configured glow.
if protectedClient then
    H.secret = true
    Retarget()
    H.secret = false
    Check(single._msufPredictionOverAbsorbOverlay == true, "a secret UnitCanAttack dropped the glow")
end

-- 5. Group frames keep the glow even for an attackable unit.
H.hostile.raid1 = true
group._msufPredictionCacheReady = nil
w:Prime(group, "raid1")
Check(group._msufPredictionOverAbsorbOverlay == true, "raid1: a group frame dropped the glow")
local grouped = Measure(protectedClient and "group hostile protected" or "group hostile plain overflow", group, "raid1")
Enforce(grouped)
if protectedClient then
    Check(grouped.natives.UnitGetDetailedHealPrediction == 1, "raid1: the group glow query is gone")
end

-- 6. A group frame attached in combat: Auras3 defers its _msufIsGroupFrame
-- marker until combat ends, while Core's own scope field is already "group".
-- The group decision must follow Core's scope, so no UnitCanAttack runs and
-- the glow stays for an attackable member.
Check(group._msufCoreScope == "group", "raid1: Core scope is not group")
local auraMarker = group._msufIsGroupFrame
group._msufIsGroupFrame = nil
group._msufPredictionCacheReady = nil
H.calls, H.counting = 0, true
w:Prime(group, "raid1")
H.counting = false
Check(H.calls == 0, "raid1 without the Auras3 marker: hostility was resolved on a group frame")
Check(group._msufPredictionOverAbsorbOverlay == true, "raid1 without the Auras3 marker: the group glow was dropped")
Check(not PRED_EVENTS_HAS(group, "UNIT_FACTION"), "raid1 without the Auras3 marker: registers UNIT_FACTION")
group._msufIsGroupFrame = auraMarker
H.hostile.raid1 = nil

print("uf_prediction_hostile_glow_budget: " .. (PRINT and "measured" or "ok") .. " (" .. flavor .. ")")
for _, result in ipairs(results) do print("  " .. Report(result)) end
