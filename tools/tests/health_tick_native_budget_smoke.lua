-- health_tick_native_budget_smoke.lua <repoRoot> <flavor> [print]
--
-- Native-call budget of one UNIT_HEALTH tick (quality program wave 4, W4-C1).
-- The 2026-10-02 raid trace (C:\tmp\perfy\raid-20261002\DEEP_DIVE.md, C1-C3)
-- measured the wave-3 over-absorb glow at about 30 % of core CPU although
-- every offline VM-instruction budget was green: its cost is native. This
-- smoke therefore counts the client API and widget calls one health tick
-- makes, next to the VM instructions and the allocation of the same tick.
--
-- tools/tests/health_tick_world.lua boots the real core on the
-- SecureGroupHeader emulator under the raid trace's profile. Two frames
-- receive UNIT_HEALTH through their own OnEvent script, so the compiled Core
-- routes run: raid1, a secure group child built by the group runtime, and
-- target, a single unit frame compiled from its own spec.
--
-- Scenarios per frame:
--   * protected: Midnight in combat. Health, absorbs, heal prediction and
--     every calculator result are secrets as strict as the client
--     (tools/tests/classpower_secrets.lua: type() answers "number", any
--     operation raises), and a line watcher records each `==`, `~=` or `not`
--     on a secret local in the owned files;
--   * plain, no absorb: the common raid member;
--   * plain, overflowing absorb: the glow is shown.
-- Vanilla runs the plain scenarios (Classic clients return no secrets).
--
-- Counted per tick: UnitHealthPercent, UnitHealth, UnitHealthMax,
-- UnitGetDetailedHealPrediction, UnitGetTotalAbsorbs, UnitGetIncomingHeals,
-- UnitIsDeadOrGhost, UnitIsDead, UnitIsConnected, UnitExists, every
-- calculator method, StatusBar SetValue / SetMinMaxValues, SetVertexColor,
-- SetStatusBarColor, SetAlpha, SetAlphaFromBoolean, GetStatusBarTexture,
-- SetShown, and the secret predicates issecretvalue / hasanysecretvalues.
-- VM instructions count the core addon's own code only (not the native
-- stubs); KB is measured with the collector stopped, on the plain scenarios
-- (the protected stubs allocate their secrets).
--
-- Baseline 2026-10-02 (f4b08c62, before W4-C1), per tick, Mainline protected:
--   group: UnitHealthPercent 5 (bar, missing-health bar, two gradient
--     channels, glow step curve), UnitGetDetailedHealPrediction 1,
--     calc:GetDamageAbsorbs 1, GetStatusBarTexture 1, SetAlphaFromBoolean 1,
--     SetAlpha 1, SetValue 2, SetVertexColor 1, UnitIsDeadOrGhost 1,
--     UnitIsDead 1: 15 natives, 9 secret predicates, 454 addon instructions;
--   unit: the same without the gone state: 13 natives, 5 predicates, 355.
-- Plain, both flavors: 4 natives (UnitHealthPercent, two SetValue,
-- SetVertexColor); group 294 / overflow 583, unit 243 / overflow 532
-- instructions, 0 KB. The limits below follow each W4-C1 change and only ever
-- move down. "print" (or MSUF_BUDGET_MEASURE=1) reports without checking.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local PRINT = arg[3] == "print" or os.getenv("MSUF_BUDGET_MEASURE") == "1"

-- [flavor][scenario] = { natives = { [name] = per tick }, predicates = n, k = VM instructions, kb }
-- A native not listed must stay at 0. VM limits sit 2 % above the measurement.
local PLAIN = { UnitHealthPercent = 1, SetValue = 2, SetVertexColor = 1 }
local PLAIN_BUDGETS = {
    ["group plain"] = { natives = PLAIN, predicates = 4, k = 284, kb = 0 },
    ["group plain overflow"] = { natives = PLAIN, predicates = 16, k = 579, kb = 0 },
    ["unit plain"] = { natives = PLAIN, predicates = 2, k = 248, kb = 0 },
    ["unit plain overflow"] = { natives = PLAIN, predicates = 14, k = 543, kb = 0 },
}
local BUDGETS = {
    Mainline = {
        -- W4-C1 glow: one calculator read, the predicted-health step curve
        -- fed straight into the one flag sink, the cached texture (6 glow
        -- natives -> 4); the health follower renders a warm protected tick
        -- directly; ReadDeadCached reads UnitIsDeadOrGhost once; the group
        -- gone state resolves a health tick in Health's sink.
        ["group protected"] = { natives = { UnitHealthPercent = 5, UnitGetDetailedHealPrediction = 1,
            ["calc:GetDamageAbsorbs"] = 1, SetAlphaFromBoolean = 1,
            SetValue = 2, SetVertexColor = 1, UnitIsDeadOrGhost = 1 }, predicates = 8, k = 399 },
        ["unit protected"] = { natives = { UnitHealthPercent = 5, UnitGetDetailedHealPrediction = 1,
            ["calc:GetDamageAbsorbs"] = 1, SetAlphaFromBoolean = 1,
            SetValue = 2, SetVertexColor = 1 }, predicates = 4, k = 322 },
    },
    Vanilla = {},
}
for _, scenarios in pairs(BUDGETS) do
    for label, budget in pairs(PLAIN_BUDGETS) do scenarios[label] = budget end
end
local budgets = assert(BUDGETS[flavor], "no budgets for flavor " .. flavor)
local protectedClient = budgets["group protected"] ~= nil

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor)
local S, group, single = w.S, w.group, w.single
for _, frame in ipairs({ group, single }) do
    local name = frame == group and "raid1" or "target"
    Check(frame._msufPredictionOverAbsorbOverlay == true, name .. ": the over-absorb overlay is off")
    Check(frame._msufHealthBackgroundNeedsValue == true, name .. ": the missing-health bar is not on its value path")
    Check(frame._msufHealthBackgroundGradient == true, name .. ": the background is not a health gradient")
end
Check(group._msufUpdateGroupVisualsGoneState ~= nil, "raid1: the dead background is off")

local TICKS = 10
local ADDON_SOURCE = "@" .. root .. "/MidnightSimpleUnitFrames/"
local step = 0
local function Ticks(frame, unit, count)
    for _ = 1, count do
        -- Every tick carries a new value, so no plain dedupe hides a write.
        step = step + 1
        S.pct = 0.61 + (step % 20) / 100
        w:Fire(frame, unit, "UNIT_HEALTH")
    end
end

local results = {}
local function Measure(label, frame, unit, secret, absorb)
    S.secret, S.absorb, S.incoming, S.dead = secret, absorb, 0, false
    w:Prime(frame, unit)
    Ticks(frame, unit, 3)
    if secret then
        -- No owned line compares or truth-tests a secret local.
        for index = 1, #World.OWNED do
            local stop = w.Watch(root .. "/" .. World.OWNED[index])
            Ticks(frame, unit, 2)
            local violations = stop()
            Check(#violations == 0, label .. ": a secret was inspected: " .. table.concat(violations, "; "))
        end
    end
    w:StartCounting()
    Ticks(frame, unit, TICKS)
    local calls = w:StopCounting()
    local result = { label = label, natives = {}, predicates = 0 }
    for name, count in pairs(calls) do
        if World.PREDICATES[name] then
            result.predicates = result.predicates + count / TICKS
        else
            result.natives[name] = count / TICKS
        end
    end
    -- Only the addon's own instructions count: the native stubs and this
    -- harness stay out of the VM figure.
    local instructions = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and info.source:find(ADDON_SOURCE, 1, true) then instructions = instructions + 1 end
    end, "", 1)
    Ticks(frame, unit, TICKS)
    debug.sethook()
    result.k = instructions / TICKS
    if not secret then
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        Ticks(frame, unit, 100)
        result.kb = (collectgarbage("count") - before) / 100
        collectgarbage("restart")
    end
    results[#results + 1] = result
end

if protectedClient then
    Measure("group protected", group, "raid1", true, 0.6)
    Measure("unit protected", single, "target", true, 0.6)
end
Measure("group plain", group, "raid1", false, 0)
Measure("group plain overflow", group, "raid1", false, 0.6)
Measure("unit plain", single, "target", false, 0)
Measure("unit plain overflow", single, "target", false, 0.6)

---------------------------------------------------------------------------
-- Report / check
---------------------------------------------------------------------------
local lines = {}
for _, result in ipairs(results) do
    local names = {}
    for name in pairs(result.natives) do names[#names + 1] = name end
    table.sort(names)
    local parts, total = {}, 0
    for _, name in ipairs(names) do
        parts[#parts + 1] = name .. " " .. result.natives[name]
        total = total + result.natives[name]
    end
    lines[#lines + 1] = string.format("%s: natives %g (%s), predicates %g, %.0f instructions%s",
        result.label, total, table.concat(parts, ", "), result.predicates, result.k,
        result.kb and string.format(", %.3f KB", result.kb) or "")
    if not PRINT then
        local budget = assert(budgets[result.label], "no budget for " .. result.label)
        for _, name in ipairs(names) do
            local limit = budget.natives[name] or 0
            Check(result.natives[name] <= limit, string.format("%s: %s %g per tick, budget %g",
                result.label, name, result.natives[name], limit))
        end
        Check(result.predicates <= budget.predicates, string.format("%s: %g secret predicates per tick, budget %g",
            result.label, result.predicates, budget.predicates))
        Check(result.k <= budget.k, string.format("%s: %.0f VM instructions per tick, budget %d",
            result.label, result.k, budget.k))
        if budget.kb and result.kb then
            Check(result.kb <= budget.kb + 0.001, string.format("%s: %.3f KB per tick, budget %g",
                result.label, result.kb, budget.kb))
        end
    end
end
print("health_tick_native_budget_smoke: " .. (PRINT and "measured" or "ok") .. " (" .. flavor .. ")")
for _, line in ipairs(lines) do print("  " .. line) end
