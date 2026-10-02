-- health_tick_native_budget_smoke.lua <repoRoot> <flavor> [print]
--
-- Native-call budget of one UNIT_HEALTH tick (quality program wave 4, W4-C1).
-- The 2026-10-02 raid trace (C:\tmp\perfy\raid-20261002\DEEP_DIVE.md, C1-C3)
-- measured the wave-3 over-absorb glow at about 30 % of core CPU although
-- every offline VM-instruction budget was green: its cost is native. This
-- smoke therefore counts the client API and widget calls one health tick
-- makes, next to the VM instructions and the allocation of the same tick.
--
-- The real core load graph boots on the SecureGroupHeader emulator of
-- tools/tests/group_header_world.lua. Two frames receive UNIT_HEALTH through
-- their own OnEvent script, so the compiled Core routes run:
--   * raid1, a secure group child built by the group runtime;
--   * target, a single unit frame compiled from its own spec.
-- Their profile is the raid trace's: unified foreground, health-gradient
-- background in "missing" fill mode with rounded frames on (the missing-health
-- bar takes the native value path, issue #146), the over-absorb overlay on
-- (the default) and the group dead background on.
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
-- VM instructions include the native stubs of this harness; KB is measured
-- with the collector stopped, on the plain scenarios (the protected stubs
-- allocate their secrets).
--
-- Baseline 2026-10-02 (f4b08c62, before W4-C1), per tick, Mainline protected:
--   group: UnitHealthPercent 5 (bar, missing-health bar, two gradient
--     channels, glow step curve), UnitGetDetailedHealPrediction 1,
--     calc:GetDamageAbsorbs 1, GetStatusBarTexture 1, SetAlphaFromBoolean 1,
--     SetAlpha 1, SetValue 2, SetVertexColor 1, UnitIsDeadOrGhost 1,
--     UnitIsDead 1: 15 natives, 9 secret predicates, 923 instructions;
--   unit: the same without the gone state: 13 natives, 5 predicates, 726.
-- Plain, both flavors: 4 natives (UnitHealthPercent, two SetValue,
-- SetVertexColor); group 556 / overflow 1102, unit 461 / overflow 1007
-- instructions, 0 KB. The limits below follow each W4-C1 change and only ever
-- move down. "print" (or MSUF_BUDGET_MEASURE=1) reports without checking.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local PRINT = arg[3] == "print" or os.getenv("MSUF_BUDGET_MEASURE") == "1"
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
-- Before the world exists: the sandbox copies type/tonumber/tostring.
Secrets.Install()
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local NATIVES = {
    "UnitHealthPercent", "UnitHealth", "UnitHealthMax", "UnitGetDetailedHealPrediction",
    "UnitGetTotalAbsorbs", "UnitGetIncomingHeals", "UnitGetTotalHealAbsorbs",
    "UnitIsDeadOrGhost", "UnitIsDead", "UnitIsConnected", "UnitExists",
    "calc:SetDamageAbsorbClampMode", "calc:GetDamageAbsorbs", "calc:EvaluateCurrentHealthPercent",
    "calc:EvaluateMissingHealthPercent", "calc:HasSecretValues",
    "SetValue", "SetMinMaxValues", "SetVertexColor", "SetStatusBarColor", "SetAlpha",
    "SetAlphaFromBoolean", "GetStatusBarTexture", "SetShown",
}
local PREDICATES = { "issecretvalue", "hasanysecretvalues" }

-- [flavor][scenario] = { natives = { [name] = per tick }, predicates = n, k = VM instructions, kb }
-- A native not listed must stay at 0. VM limits sit 2 % above the measurement.
local PLAIN = { UnitHealthPercent = 1, SetValue = 2, SetVertexColor = 1 }
local PLAIN_BUDGETS = {
    ["group plain"] = { natives = PLAIN, predicates = 4, k = 568, kb = 0 },
    ["group plain overflow"] = { natives = PLAIN, predicates = 16, k = 1125, kb = 0 },
    ["unit plain"] = { natives = PLAIN, predicates = 2, k = 471, kb = 0 },
    ["unit plain overflow"] = { natives = PLAIN, predicates = 14, k = 1028, kb = 0 },
}
local BUDGETS = {
    Mainline = {
        ["group protected"] = { natives = { UnitHealthPercent = 5, UnitGetDetailedHealPrediction = 1,
            ["calc:GetDamageAbsorbs"] = 1, GetStatusBarTexture = 1, SetAlphaFromBoolean = 1, SetAlpha = 1,
            SetValue = 2, SetVertexColor = 1, UnitIsDeadOrGhost = 1, UnitIsDead = 1 }, predicates = 9, k = 941 },
        ["unit protected"] = { natives = { UnitHealthPercent = 5, UnitGetDetailedHealPrediction = 1,
            ["calc:GetDamageAbsorbs"] = 1, GetStatusBarTexture = 1, SetAlphaFromBoolean = 1, SetAlpha = 1,
            SetValue = 2, SetVertexColor = 1 }, predicates = 5, k = 741 },
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

---------------------------------------------------------------------------
-- Native surface: counted wrappers over one switchable unit model
---------------------------------------------------------------------------
local calls, counting = {}, false
local function Count(name)
    if counting then calls[name] = (calls[name] or 0) + 1 end
end

-- The unit every frame shows. pct is current/max health (0..1); absorb and
-- incoming are fractions of max health.
local S = { secret = false, pct = 0.6, absorb = 0, incoming = 0, dead = false }
local MAX_HEALTH = 100000
local function Number(value)
    if S.secret then return Secrets.New("number") end
    return value
end

local function NewCurve()
    local curve = { points = {} }
    function curve:SetType(kind) self.kind = kind end
    function curve:GetType() return self.kind or 0 end
    function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    -- Linear and step evaluation, like LuaCurve (step holds the previous point
    -- until x reaches the next one).
    function curve:Evaluate(x)
        local points = self.points
        if #points == 0 then return 0 end
        if x <= points[1][1] then return points[1][2] end
        for index = 2, #points do
            local p, q = points[index - 1], points[index]
            if x <= q[1] then
                if self.kind == 1 then return x < q[1] and p[2] or q[2] end
                return p[2] + (q[2] - p[2]) * (x - p[1]) / (q[1] - p[1])
            end
        end
        return points[#points][2]
    end
    return curve
end

local function NewCalculator()
    local calc = {}
    local function Method(name, fn)
        calc[name] = function(self, ...) Count("calc:" .. name) return fn(self, ...) end
    end
    Method("SetDamageAbsorbClampMode", function(self, mode) self.mode = mode end)
    -- MissingHealth clamp: the absorb overflows the missing health less the
    -- incoming heals.
    Method("GetDamageAbsorbs", function()
        if S.secret then return Secrets.New("number"), Secrets.New("boolean") end
        local boundary = (1 - S.pct) - S.incoming
        if boundary < 0 then boundary = 0 end
        return S.absorb * MAX_HEALTH, S.absorb > boundary
    end)
    Method("EvaluateCurrentHealthPercent", function(_, curve)
        if S.secret then return Secrets.New("number") end
        return curve:Evaluate(S.pct)
    end)
    Method("EvaluateMissingHealthPercent", function(_, curve)
        if S.secret then return Secrets.New("number") end
        return curve:Evaluate(1 - S.pct)
    end)
    Method("HasSecretValues", function() return S.secret end)
    return calc
end

local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    local env = harness.env
    env.MAX_BOSS_FRAMES = 5
    local rosterExists, rosterConnected = env.UnitExists, env.UnitIsConnected
    local function Wrap(name, fn)
        env[name] = function(...) Count(name) return fn(...) end
    end
    Wrap("UnitExists", function(unit) return unit == "target" or rosterExists(unit) end)
    Wrap("UnitIsConnected", function(unit) return unit == "target" or rosterConnected(unit) end)
    Wrap("UnitHealth", function() return Number(S.pct * MAX_HEALTH) end)
    Wrap("UnitHealthMax", function() return Number(MAX_HEALTH) end)
    Wrap("UnitHealthPercent", function(_, _, curve)
        if S.secret then return Secrets.New("number") end
        if curve then return curve:Evaluate(S.pct) end
        return S.pct
    end)
    Wrap("UnitGetTotalAbsorbs", function() return Number(S.absorb * MAX_HEALTH) end)
    Wrap("UnitGetIncomingHeals", function() return Number(S.incoming * MAX_HEALTH) end)
    Wrap("UnitGetTotalHealAbsorbs", function() return Number(0) end)
    -- UnitIsDeadOrGhost / UnitIsDead / UnitIsConnected are not secret-returning
    -- (UnitDocumentation.lua).
    Wrap("UnitIsDeadOrGhost", function() return S.dead end)
    Wrap("UnitIsDead", function() return S.dead end)
    Wrap("UnitIsGhost", function() return false end)
    Wrap("CreateUnitHealPredictionCalculator", NewCalculator)
    Wrap("UnitGetDetailedHealPrediction", function(unit, healer, calc) calc.unit, calc.healer = unit, healer end)
    env.issecretvalue = function(value) Count("issecretvalue") return Secrets.IsSecret(value) end
    env.hasanysecretvalues = function(...)
        Count("hasanysecretvalues")
        for index = 1, select("#", ...) do
            if Secrets.IsSecret((select(index, ...))) then return true end
        end
        return false
    end
    env.C_CurveUtil = { CreateCurve = NewCurve, CreateColorCurve = NewCurve }
    local scale = NewCurve(); scale:SetType(0); scale:AddPoint(0, 0); scale:AddPoint(1, 100)
    local reverse = NewCurve(); reverse:SetType(0); reverse:AddPoint(0, 100); reverse:AddPoint(1, 0)
    env.CurveConstants = { ScaleTo100 = scale, ReverseTo100 = reverse }
    local unknown = env.MSUF_HEALTH_TICK_SMOKE_UNKNOWN
    env.Enum = setmetatable({
        LuaCurveType = { Linear = 0, Step = 1 },
        UnitDamageAbsorbClampMode = { MissingHealth = 0, MissingHealthWithoutIncomingHeals = 1, MaximumHealth = 2 },
    }, { __index = function() return unknown end })
end })
local env, UF, GF = h.env, h.UF, h.GF

-- Widget surface: the client methods the tick reaches, counted.
local M = h.widgets.Methods
-- Region/Frame:SetAlphaFromBoolean (SimpleRegionAPIDocumentation.lua): the
-- stub keeps the flag and both alphas.
M.SetAlphaFromBoolean = function(self, value, alphaIfTrue, alphaIfFalse)
    self.alphaBoolean, self.alphaIfTrue, self.alphaIfFalse = value, alphaIfTrue, alphaIfFalse
end
-- Text formatting is deferred on health ticks; a secret format argument must
-- reach the sink untouched.
M.SetFormattedText = function(self, format) self.text = format end
-- Colour setters store fields instead of a fresh table, so the KB figure
-- measures the addon, not this stub.
M.SetVertexColor = function(self, r, g, b, a) self.vr, self.vg, self.vb, self.va = r, g, b, a end
M.GetVertexColor = function(self) return self.vr, self.vg, self.vb, self.va end
M.SetStatusBarColor = function(self, r, g, b, a) self.sr, self.sg, self.sb, self.sa = r, g, b, a end
M.GetStatusBarColor = function(self) return self.sr, self.sg, self.sb, self.sa end
for index = 1, #NATIVES do
    local name = NATIVES[index]
    local original = M[name]
    if original and not name:find(":", 1, true) then
        M[name] = function(...) Count(name) return original(...) end
    end
end

---------------------------------------------------------------------------
-- Frames under the raid trace's profile
---------------------------------------------------------------------------
local Config = UF.Config
local general = Config.GetDB().general
general.barMode = "unified"
general.barBgFillMode = "missing"
general.barBgColorMode = "health_gradient"
env.MSUF_RoundedUF_Active = true
local raid = GF.GetConf("raid")
raid.enabled = true
raid.deadBgEnabled = true
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local group = GF.FrameForUnit("raid1")
Check(group and type(group.UNIT_HEALTH) == "function", "raid1 compiled no UNIT_HEALTH route")

local single = env.CreateFrame("Button", "MSUF_target", env.UIParent)
single.MSUFUnitKey = "target"
Config.Refresh()
UF.AttachFrame(single, { scope = "single" })
UF.frames.target = single
UF.ApplySpec(single, Config.GetSpec("target"), "MSUF_APPLY", true)
Check(type(single.UNIT_HEALTH) == "function", "target compiled no UNIT_HEALTH route")

for _, frame in ipairs({ group, single }) do
    local name = frame == group and "raid1" or "target"
    Check(frame._msufPredictionOverAbsorbOverlay == true, name .. ": the over-absorb overlay is off")
    Check(frame._msufHealthBackgroundNeedsValue == true, name .. ": the missing-health bar is not on its value path")
    Check(frame._msufHealthBackgroundGradient == true, name .. ": the background is not a health gradient")
end
Check(group._msufUpdateGroupVisualsGoneState ~= nil, "raid1: the dead background is off")

local function Fire(frame, unit, event)
    frame.scripts.OnEvent(frame, event, unit)
end

-- Absorb, heal and max-health payloads arrive before the health ticks; the
-- prediction queue is drained synchronously (its test toggle).
local function Prime(frame, unit)
    env.MSUF_GF_PredictionSync = true
    Fire(frame, unit, "UNIT_MAXHEALTH")
    Fire(frame, unit, "UNIT_ABSORB_AMOUNT_CHANGED")
    Fire(frame, unit, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    Fire(frame, unit, "UNIT_HEAL_PREDICTION")
    env.MSUF_GF_PredictionSync = nil
end

local OWNED = {
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua",
    "MidnightSimpleUnitFrames/Runtime/MSUF_BarBackgroundRuntime.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua",
    "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua",
}

-- The line watcher of tools/tests/classpower_secrets.lua reads one line at a
-- time. The owned files guard a comparison with a plain flag on the line
-- before (`if secret` / `or cache ~= value`) or negate it (`not secret and`).
-- This watcher reads the whole condition: the lines of the statement that
-- continue with `or` / `and` belong to its prefix, and `not flag and` with a
-- true flag short-circuits as well.
local function SourceLines(path)
    local file = assert(io.open(path, "rb"), "missing source: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end
local function Escape(name) return (name:gsub("%W", "%%%0")) end
-- True when the text before a use short-circuits it, read the way Lua does:
-- `flag or` with a true plain local, `flag and` with a false one, and the
-- negated forms `not flag and` (true flag) and `not flag or` (false flag).
local function Guarded(prefix, locals)
    for position, flag in prefix:gmatch("()([%a_][%w_]*)") do
        local operator = prefix:match("^[%a_][%w_]*%s+(%a+)%s", position)
        local value = locals[flag]
        if (operator == "or" or operator == "and") and flag ~= "not" and value ~= nil
            and not Secrets.IsSecret(value) and prefix:sub(position - 1, position - 1) ~= "." then
            local truthy = value and true or false
            if prefix:sub(1, position - 1):match("%f[%w_]not%s+$") then truthy = not truthy end
            if operator == "or" and truthy then return true end
            if operator == "and" and not truthy then return true end
        end
    end
    return false
end
local USES = { "%%f[%%w_]%s%%s*[=~]=", "[=~]=%%s*%s%%f[^%%w_]", "%%f[%%w_]not%%s+%s%%f[^%%w_]" }
local function Misused(text, name, locals)
    local n = Escape(name)
    if text:find("issecretvalue%(%s*" .. n .. "%s*%)") then return false end
    for index = 1, #USES do
        local start = text:find(USES[index]:format(n))
        if start and not Guarded(text:sub(1, start - 1), locals) then return true end
    end
    return false
end
local function Watch(path)
    local lines = SourceLines(path)
    local wanted = ("@" .. path):gsub("\\", "/")
    local violations, seen = {}, {}
    debug.sethook(function(_, lineNumber)
        local info = debug.getinfo(2, "S")
        if not info or info.source:gsub("\\", "/") ~= wanted then return end
        local text = lines[lineNumber]
        if not text or seen[lineNumber] then return end
        local locals, index = {}, 1
        while true do
            local name, value = debug.getlocal(2, index)
            if not name then break end
            locals[name] = value
            index = index + 1
        end
        -- A continuation line (`or ...` / `and ...`) carries the earlier
        -- lines of its statement as its prefix.
        local first = lineNumber
        while first > 1 and (lines[first]:match("^%s*or%s") or lines[first]:match("^%s*and%s")) do
            first = first - 1
        end
        local statement = table.concat(lines, " ", first, lineNumber)
        for name, value in pairs(locals) do
            if Secrets.IsSecret(value) and Misused(statement, name, locals) then
                seen[lineNumber] = true
                violations[#violations + 1] = ("%s:%d: %s"):format(path:match("[^/\\]+$"), lineNumber,
                    text:match("^%s*(.-)%s*$"))
                break
            end
        end
    end, "l")
    return function()
        debug.sethook()
        return violations
    end
end

local TICKS = 10
local step = 0
local function Ticks(frame, unit, count)
    for _ = 1, count do
        -- Every tick carries a new value, so no plain dedupe hides a write.
        step = step + 1
        S.pct = 0.61 + (step % 20) / 100
        Fire(frame, unit, "UNIT_HEALTH")
    end
end

local results = {}
local function Measure(label, frame, unit, secret, absorb)
    S.secret, S.absorb, S.incoming, S.dead = secret, absorb, 0, false
    Prime(frame, unit)
    Ticks(frame, unit, 3)
    if secret then
        -- No owned line compares or truth-tests a secret local.
        for index = 1, #OWNED do
            local stop = Watch(root .. "/" .. OWNED[index])
            Ticks(frame, unit, 2)
            local violations = stop()
            Check(#violations == 0, label .. ": a secret was inspected: " .. table.concat(violations, "; "))
        end
    end
    for key in pairs(calls) do calls[key] = nil end
    counting = true
    Ticks(frame, unit, TICKS)
    counting = false
    local result = { label = label, natives = {}, predicates = 0 }
    for name, count in pairs(calls) do
        local isPredicate = name == "issecretvalue" or name == "hasanysecretvalues"
        if isPredicate then
            result.predicates = result.predicates + count / TICKS
        else
            result.natives[name] = count / TICKS
        end
    end
    local instructions = 0
    debug.sethook(function() instructions = instructions + 1 end, "", 1)
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
