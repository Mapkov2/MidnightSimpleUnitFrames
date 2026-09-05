-- Exercise the public gradient and Health update routes with native API stubs.
-- Allocation assertions count ColorMixin construction, not simulated CPU time.
local root = arg and arg[1] or "."
local function Load(path, ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
local function Near(a, b, label)
    assert(type(a) == "number" and math.abs(a - b) < 1e-9, label or "color mismatch")
end
local function Clamp(value, fallback)
    value = tonumber(value) or fallback or 0
    return math.max(0, math.min(1, value))
end

local allocations, scalarReads, colorReads = 0, 0, 0
local pct, opaque = 0.37, false
local function Forbidden() error("opaque health was inspected in Lua") end
local secretMeta = { __eq = Forbidden, __lt = Forbidden, __le = Forbidden,
    __add = Forbidden, __sub = Forbidden, __mul = Forbidden, __div = Forbidden,
    __index = Forbidden, __tostring = Forbidden }
local SECRET = setmetatable({}, secretMeta)
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
_G.hasanysecretvalues = function(r, g, b)
    return rawequal(r, SECRET) or rawequal(g, SECRET) or rawequal(b, SECRET)
end
_G.CreateColor = function(r, g, b, a)
    allocations = allocations + 1
    return { r = r, g = g, b = b, a = a,
        GetRGB = function(self) return self.r, self.g, self.b end }
end
local function Lerp(a, b, t) return a + (b - a) * t end
local function NewCurve(color)
    local curve = { points = {}, color = color, curveType = color and "linear" or "unset" }
    function curve:GetType() return self.curveType end
    function curve:SetType(value) self.curveType = value end
    function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    function curve:Evaluate(x)
        assert(self.curveType == "linear", "scalar curve did not retain color-curve interpolation")
        assert(not rawequal(x, SECRET), "secret percentage passed to Lua curve evaluation")
        local points = self.points
        local left, right = points[1], points[2]
        if x > 0.5 then left, right = points[2], points[3] end
        local t = Clamp((x - left[1]) / (right[1] - left[1]))
        if not self.color then return Lerp(left[2], right[2], t) end
        return CreateColor(Lerp(left[2].r, right[2].r, t), Lerp(left[2].g, right[2].g, t),
            Lerp(left[2].b, right[2].b, t), 1)
    end
    return curve
end
_G.C_CurveUtil = {
    CreateColorCurve = function() return NewCurve(true) end,
    CreateCurve = function() return NewCurve(false) end,
}
local function EvaluateNative(curve)
    if curve.color then
        colorReads = colorReads + 1
        if opaque then return CreateColor(SECRET, SECRET, SECRET, 1) end
    else
        scalarReads = scalarReads + 1
        if opaque then return SECRET end
    end
    return curve:Evaluate(pct)
end
_G.UnitHealthPercent = function(unit, predicted, curve)
    assert(unit == "party1" or unit == "target", "gradient lost its unit binding")
    assert(predicted == true, "gradient lost predicted-health semantics")
    return EvaluateNative(curve)
end
local function Namespace()
    return { UF = { Clamp01 = Clamp }, Secrets = { IsSecret = issecretvalue } }
end
local ns = Namespace()
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", ns)
local common = ns.UFBarTextCommon
local default = {}
local custom = { gradientLowR = 0.17, gradientLowG = 0.89, gradientLowB = 0.71,
    gradientMidR = 0.91, gradientMidG = 0.24, gradientMidB = 0.13,
    gradientHighR = 0.31, gradientHighG = 0.68, gradientHighB = 0.96 }
local constant = { gradientLowR = 0.2, gradientLowG = 0.4, gradientLowB = 0.6,
    gradientMidR = 0.2, gradientMidG = 0.4, gradientMidB = 0.6,
    gradientHighR = 0.2, gradientHighG = 0.4, gradientHighB = 0.6 }
local calcReads = 0
local calc = { EvaluateCurrentHealthPercent = function(_, curve)
    calcReads = calcReads + 1
    return EvaluateNative(curve)
end }
for _, health in ipairs({ default, custom, constant }) do
    local frame = { MSUFSpec = { health = health } }
    frame._msufHealthGradientCurve, frame._msufHealthGradientChannels = common.PrepareHealthGradientCurve(health)
    for step = 0, 100 do
        pct = step / 100
        local expected = frame._msufHealthGradientCurve:Evaluate(pct)
        local before = allocations
        local r, g, b, raw = common.GradientColor("party1", nil, frame)
        Near(r, expected.r); Near(g, expected.g); Near(b, expected.b)
        assert(raw == true and allocations == before, "unit gradient created a ColorMixin")
        r, g, b, raw = common.GradientColor("party1", calc, frame)
        Near(r, expected.r); Near(g, expected.g); Near(b, expected.b)
        assert(raw == true and allocations == before, "calculator gradient created a ColorMixin")
    end
end
assert(calcReads == 505 and scalarReads == 1010 and colorReads == 0,
    "constant channels were evaluated, or hot gradients used the ColorMixin API")

local firstCurve, firstChannels = common.PrepareHealthGradientCurve({})
local secondCurve, secondChannels = common.PrepareHealthGradientCurve({})
assert(firstCurve == secondCurve and firstChannels == secondChannels, "identical specs did not share immutable curves")
local frame = { MSUFSpec = { health = custom } } -- lazy text-only consumer
opaque = true
local r, g, b, raw = common.GradientColor("target", nil, frame)
assert(rawequal(r, SECRET) and rawequal(g, SECRET) and rawequal(b, SECRET) and raw,
    "unit native secret components were changed")
r, g, b, raw = common.GradientColor("party1", calc, frame)
assert(rawequal(r, SECRET) and rawequal(g, SECRET) and rawequal(b, SECRET) and raw,
    "calculator native secret components were changed")
opaque = false
pct = 0.75
local oldCurve = frame._msufHealthGradientCurve
custom.gradientHighR = 0.99
frame._msufHealthGradientCurve, frame._msufHealthGradientChannels = common.PrepareHealthGradientCurve(custom)
assert(frame._msufHealthGradientCurve ~= oldCurve, "live stop edit reused stale curves")
r = common.GradientColor("target", nil, frame)
Near(r, 0.95, "live stop edit was not visible")
local previewR = common.PreviewHealthGradientColor(custom, pct)
Near(r, previewR, "preview and runtime gradients diverged")

-- Invalid and secret unit tokens must stop before the native gradient API.
for _, case in ipairs({ {}, { unit = "" }, { unit = false }, { unit = 123 }, { unit = SECRET } }) do
    local reads = scalarReads + colorReads
    local _, _, _, valid = common.GradientColor(case.unit, nil, frame)
    assert(valid == false and scalarReads + colorReads == reads,
        "invalid/secret gradient unit reached a native API")
end

-- Capability fallback retains the original public ColorCurve result contract.
_G.C_CurveUtil.CreateCurve = nil
local legacy = Namespace()
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", legacy)
local before = colorReads
local legacyR, legacyG, legacyB = legacy.UFBarTextCommon.GradientColor("target", nil, { MSUFSpec = { health = {} } })
Near(legacyR, 0.5); Near(legacyG, 1); Near(legacyB, 0)
assert(colorReads == before + 1, "missing scalar API lost its ColorCurve fallback")
_G.C_CurveUtil.CreateCurve = function() return NewCurve(false) end

-- Public background runtime: input changes, force, plain cache and secrets.
local function Noop() end
_G["EssentialCooldownViewer_MSA_Container"] = { ClearAllPoints = Noop, SetSize = Noop, SetPoint = Noop }
Load("Runtime/MSUF_BarBackgroundRuntime.lua", ns)
local writes = 0
local background = { SetVertexColor = function(self, rr, gg, bb, aa)
    writes = writes + 1
    self.r, self.g, self.b, self.a = rr, gg, bb, aa
end }
frame.hpBarBG, frame.MSUFUnitKey = background, "target"
custom.backgroundColorMode, custom.background = "health_gradient", { a = 0.42 }
local Refresh = ns.Bars.RefreshHealthBarBackgroundColor
local alphaClamps = 0
for i = 1, 50 do
    local name, fn = debug.getupvalue(Refresh, i)
    if not name then break end
    if name == "MSUF_Clamp01" then
        debug.setupvalue(Refresh, i, function(value)
            alphaClamps = alphaClamps + 1
            return fn(value)
        end)
        break
    end
end
assert(Refresh(frame, "UNIT_HEALTH"))
Near(background.a, 0.42)
Refresh(frame, "UNIT_HEALTH")
assert(writes == 1, "unchanged plain background bypassed its color cache")
assert(alphaClamps == 1, "unchanged configured background alpha was resolved again")
custom.background.a = 1.5
Refresh(frame, "UNIT_HEALTH")
Near(background.a, 1, "in-place opacity change was not clamped")
custom.background = nil
frame.MSUFSpec.backgroundAlpha = 0.19
Refresh(frame, "UNIT_HEALTH")
Near(background.a, 0.19, "spec opacity fallback was not refreshed")
before = writes
Refresh(frame, "MSUF_BACKGROUND_VISUAL", nil, nil, nil, nil, true)
assert(writes == before + 1, "forced background repaint was dropped")
opaque = true
Refresh(frame, "UNIT_HEALTH")
Refresh(frame, "UNIT_HEALTH")
assert(rawequal(background.r, SECRET) and frame._msufHPBgR == nil and writes == before + 3,
    "secret background channels were compared or cached")
opaque = false
custom.backgroundColorMode = "custom"
assert(Refresh(frame, "UNIT_HEALTH") == false, "disabled dynamic color retained its old mode")

-- Legacy capability and alternate region ownership retain secret forwarding.
_G.hasanysecretvalues = nil
local legacyBackground = { UF = {}, UFBarTextCommon = { GradientColor = function()
    return SECRET, SECRET, SECRET, true
end } }
Load("Runtime/MSUF_BarBackgroundRuntime.lua", legacyBackground)
local alternate = { healthBg = background, MSUFSpec = { health = {
    backgroundColorMode = "health_gradient", background = { a = 0.31 },
} }, _msufFrameBgR = 0.1, _msufFrameBgG = 0.2, _msufFrameBgB = 0.3, _msufFrameBgA = 1 }
before = writes
legacyBackground.Bars.RefreshHealthBarBackgroundColor(alternate, "UNIT_HEALTH", "target")
assert(writes == before + 1 and rawequal(background.r, SECRET) and background.a == 0.31,
    "fallback secret predicate lost the alternate background region")
assert(alternate._msufFrameBgR == nil and alternate._msufFrameBgG == nil
    and alternate._msufFrameBgB == nil and alternate._msufFrameBgA == nil,
    "alternate region retained a plain cache after a secret write")

-- Test the actual folded Group update with and without a gone/status sink.
local refreshes, foregroundWrites, statusCalls, goneCalls = 0, 0, 0, 0
local healthPct = 62
_G.MSUF_RefreshHealthBarBackgroundColor = function()
    refreshes = refreshes + 1
    return true
end
local Health
local healthNS = { UF = { RegisterElement = function(name, element)
    if name == "Health" then Health = element end
end }, UFBarTextCommon = {
    SCALE_100 = {}, WHITE = "white",
    UnitHealthPercent = function() return healthPct end,
    ApplyHealthStatusColor = function() foregroundWrites = foregroundWrites + 1 end,
    PrepareHealthGradientCurve = common.PrepareHealthGradientCurve,
} }
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", healthNS)
local colorHandoffs = 0
for i = 1, 50 do
    local name, fn = debug.getupvalue(Health.UpdateValueGroupPercentLean, i)
    if not name then break end
    if name == "ApplyRuntimeColor" then
        debug.setupvalue(Health.UpdateValueGroupPercentLean, i, function(...)
            colorHandoffs = colorHandoffs + 1
            return fn(...)
        end)
        break
    end
end
local bar = { SetValue = function(self, value, interpolation)
    self.value, self.interpolation = value, interpolation
end, SetMinMaxValues = function() end }
local group = { hpBar = bar, MSUFUnitKey = "party1",
    _msufIsGroupFrame = true,
    MSUFSpec = { scope = "group", health = { mode = "unified" } },
    _msufHealthBackgroundGradient = true, _msufHealthRuntimeGradient = false,
    _msufHealthBackgroundColorDynamic = true, _msufHealthRuntimeColorEnabled = false,
    _msufHealthRuntimeColorUpdateEnabled = true,
}
local function Tick(event)
    local old = refreshes
    Health.UpdateValueGroupPercentLean(group, event or "UNIT_HEALTH", "party1")
    assert(refreshes == old + 1, "one group update evaluated its background more than once")
end
Tick() -- static early return
group._msufUpdateGroupVisualsGoneState = function() goneCalls = goneCalls + 1 end
group._msufUpdateGroupStatusState = function() statusCalls = statusCalls + 1 end
Tick() -- original trace's duplicate path
assert(goneCalls == 1 and statusCalls == 0 and foregroundWrites == 0)
assert(colorHandoffs == 0, "completed background-only update entered a redundant color handoff")
for _, status in ipairs({ "DEAD", "GHOST", "OFFLINE" }) do
    group._msufStatusTextValue = nil
    before = statusCalls
    healthPct = 0
    Tick()
    group._msufStatusTextValue = status
    healthPct = 62
    Tick("UNIT_CONNECTION")
    assert(statusCalls == before + 2, "visible gone status lost its transition/recovery")
end
group._msufStatusTextValue = nil
healthPct = SECRET
bar._msufSmoothInterp = "smooth"
Tick()
assert(rawequal(bar.value, SECRET) and bar.interpolation == "smooth" and bar._msufHealthPercentValue == nil,
    "secret group health lost native smoothing or entered the comparison cache")
group._msufHealthRuntimeColorEnabled = true
group._msufHealthRuntimeGradient = true
before = foregroundWrites
Tick()
assert(foregroundWrites == before + 1, "combined gradient lost its foreground update")

-- Apply owns preparation/invalidation, including a text-only color consumer.
-- Geometry has separate native StatusBar coverage; isolate the cold color work.
Health.Layout = Noop
local applyBar = { SetStatusBarTexture = Noop, SetStatusBarColor = Noop }
local applyFrame = { hpBar = applyBar, MSUFUnitKey = "party1" }
local applySpec = { scope = "group", health = { mode = "gradient" } }
applyFrame.MSUFSpec = applySpec
Health.Apply(applyFrame, applySpec)
assert(applyFrame._msufHealthGradientChannels and applyFrame._msufHealthGradientCurve,
    "Health.Apply deferred gradient preparation until a health event")
local oldChannels = applyFrame._msufHealthGradientChannels
applySpec.health.gradientHighR = 0.47
Health.Apply(applyFrame, applySpec)
assert(applyFrame._msufHealthGradientChannels ~= oldChannels, "Health.Apply retained stale gradient stops")
applySpec.health.mode = "unified"
Health.Apply(applyFrame, applySpec)
assert(applyFrame._msufHealthGradientCurve == nil and applyFrame._msufHealthGradientChannels == nil,
    "non-gradient Apply retained a stale text-only gradient cache")
common.GradientColor("party1", nil, applyFrame)
assert(applyFrame._msufHealthGradientChannels, "text-only gradient did not prepare after Apply")

print("worldboss_health_hotpath_smoke: ok (gradient parity, allocation contract, secret forwarding, status transitions)")
