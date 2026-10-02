-- health_tick_world.lua -- one health tick on the real core, natives counted.
--
-- Shared by the W4-C1 health-tick smokes (health_tick_native_budget_smoke,
-- group_gone_state_smoke). Boots one flavor's whole core load graph on the
-- SecureGroupHeader emulator of tools/tests/group_header_world.lua with:
--   * strict secrets (tools/tests/classpower_secrets.lua: type() answers
--     "number", any operation raises), installed before the sandbox exists
--     so the addon files capture the strict type/tonumber/tostring;
--   * every unit API one health tick reaches, as a counted wrapper over one
--     switchable unit model (world.S): health fraction, absorb, incoming
--     heals, dead, connected, and whether the client returns secrets. The
--     calculator's (current) health and the predicted health that
--     UnitHealthPercent/UnitHealth return with usePredicted are separate
--     (S.pct / S.predicted), because the client does not document them equal;
--   * a prediction calculator, LuaCurves (linear and step) and the
--     CurveConstants curves, counted per method;
--   * counted widget sinks (SetValue, SetVertexColor, SetAlpha,
--     SetAlphaFromBoolean, GetStatusBarTexture, ...), with allocation-free
--     colour setters so KB measures the addon, not the stub;
--   * the raid trace's profile (2026-10-02): unified foreground,
--     health-gradient background in "missing" fill mode with rounded frames
--     (the missing-health bar on its native value path, issue #146), the
--     over-absorb overlay (the default), the group dead background.
-- Two frames are built: raid1 (a secure group child of the group runtime) and
-- target (a single unit frame compiled from its spec).
--
-- Usage:
--   local World = dofile(root .. "/tools/tests/health_tick_world.lua")
--   local w = World.New(root, flavor, { deadBgOffline = true })
--   w.S.secret = true; w:Prime(w.group, "raid1"); w:Fire(w.group, "raid1", "UNIT_HEALTH")
--   w:StartCounting(); ...; local calls = w:StopCounting()
--   local stop = w.Watch(path); ...; local violations = stop()
--
-- Plain Lua 5.1.

local World = {}
local Methods = {}
Methods.__index = Methods

World.PREDICATES = { issecretvalue = true, hasanysecretvalues = true }
World.WIDGET_SINKS = {
    "SetValue", "SetMinMaxValues", "SetVertexColor", "SetStatusBarColor", "SetAlpha",
    "SetAlphaFromBoolean", "GetStatusBarTexture", "SetShown", "SetColorTexture", "SetTexture",
}
World.OWNED = {
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua",
    "MidnightSimpleUnitFrames/Runtime/MSUF_BarBackgroundRuntime.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua",
    "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua",
}

local MAX_HEALTH = 100000
World.MAX_HEALTH = MAX_HEALTH

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
World.NewCurve = NewCurve

---------------------------------------------------------------------------
-- Secret watcher
---------------------------------------------------------------------------
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

local function NewWatcher(Secrets)
    -- True when the text before a use short-circuits it, read the way Lua
    -- does: `flag or` with a true plain local, `flag and` with a false one,
    -- and the negated forms `not flag and` (true flag) and `not flag or`
    -- (false flag).
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
    --- Records every executed line of `path` that compares or truth-tests a
    --- local holding a secret. Returns stop(), which removes the hook and
    --- returns the violations as "file:line: text".
    return function(path)
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
end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
-- options: deadBgOffline (bool) for the raid dead background.
function World.New(root, flavor, options)
    options = options or {}
    local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
    -- Before the sandbox exists: it copies type/tonumber/tostring.
    Secrets.Install()
    local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

    local w = setmetatable({ root = root, flavor = flavor, Secrets = Secrets, calls = {}, counting = false },
        Methods)
    -- The unit every frame shows. pct is the calculator's current/max health
    -- (0..1); predicted is the usePredicted health of the unit APIs (nil: the
    -- same); absorb and incoming are fractions of max health.
    local S = { secret = false, pct = 0.6, absorb = 0, incoming = 0, dead = false, connected = true }
    w.S = S
    local function Predicted() return S.predicted or S.pct end
    local calls = w.calls
    local function Count(name)
        if w.counting then calls[name] = (calls[name] or 0) + 1 end
    end
    local function Number(value)
        if S.secret then return Secrets.New("number") end
        return value
    end

    local function NewCalculator()
        local calc = {}
        local function Method(name, fn)
            calc[name] = function(self, ...) Count("calc:" .. name) return fn(self, ...) end
        end
        Method("SetDamageAbsorbClampMode", function(self, mode) self.mode = mode end)
        -- MissingHealth clamp: the absorb overflows the missing health less
        -- the incoming heals.
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
        Wrap("UnitIsConnected", function(unit)
            if not S.connected then return false end
            return unit == "target" or rosterConnected(unit)
        end)
        Wrap("UnitHealth", function() return Number(Predicted() * MAX_HEALTH) end)
        Wrap("UnitHealthMax", function() return Number(MAX_HEALTH) end)
        Wrap("UnitHealthPercent", function(_, _, curve)
            if S.secret then return Secrets.New("number") end
            if curve then return curve:Evaluate(Predicted()) end
            return Predicted()
        end)
        Wrap("UnitGetTotalAbsorbs", function() return Number(S.absorb * MAX_HEALTH) end)
        Wrap("UnitGetIncomingHeals", function() return Number(S.incoming * MAX_HEALTH) end)
        Wrap("UnitGetTotalHealAbsorbs", function() return Number(0) end)
        -- UnitIsDeadOrGhost / UnitIsDead / UnitIsConnected are not
        -- secret-returning (UnitDocumentation.lua).
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
        local unknown = env.MSUF_HEALTH_TICK_WORLD_UNKNOWN
        env.Enum = setmetatable({
            LuaCurveType = { Linear = 0, Step = 1 },
            UnitDamageAbsorbClampMode = { MissingHealth = 0, MissingHealthWithoutIncomingHeals = 1, MaximumHealth = 2 },
        }, { __index = function() return unknown end })
    end })
    local env, UF, GF = h.env, h.UF, h.GF
    w.h, w.env, w.UF, w.GF = h, env, UF, GF

    -- Widget surface.
    local M = h.widgets.Methods
    -- Region/Frame:SetAlphaFromBoolean (SimpleRegionAPIDocumentation.lua):
    -- the stub keeps the flag and both alphas.
    M.SetAlphaFromBoolean = function(self, value, alphaIfTrue, alphaIfFalse)
        self.alphaBoolean, self.alphaIfTrue, self.alphaIfFalse = value, alphaIfTrue, alphaIfFalse
    end
    -- Text formatting is deferred on health ticks; a secret format argument
    -- must reach the sink untouched.
    M.SetFormattedText = function(self, format) self.text = format end
    M.SetVertexColor = function(self, r, g, b, a) self.vr, self.vg, self.vb, self.va = r, g, b, a end
    M.GetVertexColor = function(self) return self.vr, self.vg, self.vb, self.va end
    M.SetStatusBarColor = function(self, r, g, b, a) self.sr, self.sg, self.sb, self.sa = r, g, b, a end
    M.GetStatusBarColor = function(self) return self.sr, self.sg, self.sb, self.sa end
    for _, name in ipairs(World.WIDGET_SINKS) do
        local original = M[name]
        if original then M[name] = function(...) Count(name) return original(...) end end
    end

    -- The raid trace's profile.
    local Config = UF.Config
    local general = Config.GetDB().general
    general.barMode = "unified"
    general.barBgFillMode = "missing"
    general.barBgColorMode = "health_gradient"
    env.MSUF_RoundedUF_Active = true
    local raid = GF.GetConf("raid")
    raid.enabled = true
    raid.deadBgEnabled = true
    raid.deadBgOffline = options.deadBgOffline == true
    GF.RefreshHeaderLayout()
    h:SetRaid(5)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    w.group = GF.FrameForUnit("raid1")
    assert(w.group and type(w.group.UNIT_HEALTH) == "function", flavor .. ": raid1 compiled no UNIT_HEALTH route")

    local single = env.CreateFrame("Button", "MSUF_target", env.UIParent)
    single.MSUFUnitKey = "target"
    Config.Refresh()
    UF.AttachFrame(single, { scope = "single" })
    UF.frames.target = single
    UF.ApplySpec(single, Config.GetSpec("target"), "MSUF_APPLY", true)
    assert(type(single.UNIT_HEALTH) == "function", flavor .. ": target compiled no UNIT_HEALTH route")
    w.single = single

    w.Watch = NewWatcher(Secrets)
    return w
end

function Methods:Fire(frame, unit, event, ...)
    frame.scripts.OnEvent(frame, event, unit, ...)
end

-- Absorb, heal and max-health payloads arrive before the health ticks; the
-- prediction queue drains synchronously (its test toggle).
function Methods:Prime(frame, unit)
    self.env.MSUF_GF_PredictionSync = true
    self:Fire(frame, unit, "UNIT_MAXHEALTH")
    self:Fire(frame, unit, "UNIT_ABSORB_AMOUNT_CHANGED")
    self:Fire(frame, unit, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    self:Fire(frame, unit, "UNIT_HEAL_PREDICTION")
    self.env.MSUF_GF_PredictionSync = nil
end

function Methods:StartCounting()
    for key in pairs(self.calls) do self.calls[key] = nil end
    self.counting = true
end

-- Returns { [api] = count } since StartCounting.
function Methods:StopCounting()
    self.counting = false
    local out = {}
    for key, value in pairs(self.calls) do out[key] = value end
    return out
end

return World
