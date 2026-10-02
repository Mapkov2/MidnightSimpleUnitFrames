-- over_absorb_protected_glow_smoke.lua <repoRoot>
--
-- The partial-health over-absorb glow (Bars > Prediction "over-absorb overlay")
-- shows when the absorb overflows the missing health. On Midnight
-- UnitGetTotalAbsorbs returns a secret, and health often is one too, so the
-- glow renders through the prediction calculator: its MissingHealth clamp
-- reports the overflow as `clamped`, and a step curve keeps full health to
-- the full-health stripe.
--
-- The 2026-10-02 raid trace measured this path at about 30 % of core CPU
-- (six native calls per health tick). Since W4-C1 one tick fills the
-- calculator once and hands the step curve's result to the one flag sink as
-- its alphaIfTrue: SetAlphaFromBoolean(clamped, partial, 0) on the cached glow
-- texture, with the holder at full alpha. The curve reads PREDICTED health
-- (UnitHealthPercent usePredicted), like the plain path and the stripe; the
-- calculator's own health source is undocumented and only feeds the flag. The
-- model below keeps the two health values apart so it can tell them apart.
--
-- The real element loads with values as strict as the client (a secret
-- refuses comparison, arithmetic, concatenation and indexing). Pinned:
--   1. overlay only: protected values render through the calculator flag and
--      the predicted-health partial curve, without Lua touching a secret, with
--      one calculator read and one curve read;
--   2. overlay plus stripe: the flag alone, at full alpha;
--   3. a following plain update clears the flag gate on the glow;
--   4. the health follower opens for a protected absorb with the overlay on;
--   5. without the calculator the glow still hides (no guessing);
--   6. what the client draws: a model that resolves each secret to the plain
--      value behind it renders the glow for a grid of health, absorb and
--      incoming heals, protected and plain, overlay with and without the
--      stripe, and checks it against the plain rule (partial health:
--      hp + incoming + absorb >= max, the rule of Blizzard's CompactUnitFrame;
--      full health: only with the stripe), including predicted health ahead
--      of or behind the calculator's, and the exact absorb boundary, where the
--      protected path follows the calculator ("in excess", strictly above)
--      and the plain path the >= rule. With the health and incoming-heal
--      inputs in agreement that is the documented difference, with no
--      secret-safe native to close it; where the calculator's health differs
--      from the predicted health, its own inputs decide the overflow too.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Forbidden() error("restricted prediction value inspected", 2) end
local SECRET_META = { __eq = Forbidden, __lt = Forbidden, __le = Forbidden, __add = Forbidden,
    __sub = Forbidden, __mul = Forbidden, __div = Forbidden, __concat = Forbidden,
    __index = Forbidden, __len = Forbidden }
-- secret -> { label, plain value the client would hold behind it }
local secrets = {}
local function Secret(label, payload)
    local value = setmetatable({}, SECRET_META)
    secrets[value] = { label, payload }
    return value
end
local function IsSecret(value) return secrets[value] ~= nil end
local function Plain(value)
    local entry = secrets[value]
    if entry then return entry[2] end
    return value
end
_G.issecretvalue = IsSecret

local log = {}
local function Record(entry) log[#log + 1] = entry end

local Region = {}
Region.__index = Region
local function NewRegion(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1 }, Region)
end
local textureReads = 0
function Region:SetAlpha(alpha) self.alpha = alpha; Record("SetAlpha") end
function Region:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
    self.alphaBoolean, self.alphaIfTrue, self.alphaIfFalse = value, alphaIfTrue, alphaIfFalse
    -- The rendered alpha now follows the (possibly secret) flag.
    self.alpha = "from flag"
    Record("SetAlphaFromBoolean")
end
function Region:SetShown(shown) self.shown = shown == true end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:SetBlendMode() end
function Region:SetVertexColor() end
function Region:SetTexture() end
function Region:SetAllPoints() end
function Region:ClearAllPoints() end
function Region:SetPoint() end
function Region:SetWidth() end
function Region:SetHeight() end
function Region:GetWidth() return 100 end
function Region:GetHeight() return 20 end
function Region:EnableMouse() end
function Region:SetMinMaxValues() end
function Region:SetValue(value) self.value = value end
function Region:SetStatusBarTexture() self.fill = self.fill or NewRegion("Texture", self) end
function Region:GetStatusBarTexture()
    textureReads = textureReads + 1
    self.fill = self.fill or NewRegion("Texture", self)
    return self.fill
end
function Region:SetStatusBarColor() end
function Region:SetReverseFill() end
function Region:SetOrientation() end
function Region:SetFrameLevel(level) self.level = level end
function Region:GetFrameLevel() return self.level or 1 end
function Region:SetFrameStrata() end
function Region:GetFrameStrata() return "MEDIUM" end
function Region:SetParent(parent) self.parent = parent end
function Region:GetParent() return self.parent end
function Region:SetClipsChildren() end
function Region:HookScript() end
function Region:SetScript() end
function Region:CreateTexture() return NewRegion("Texture", self) end

-- The unit the calculator and the unit APIs read (fractions of max health).
-- hp is the calculator's (current) health; predicted is what UnitHealthPercent
-- returns with usePredicted (nil: the same as hp).
local unitState = { hp = 0.5, absorb = 0.6, incoming = 0, protected = true }
local function Predicted() return unitState.predicted or unitState.hp end
local function UnitValue(label, value)
    if unitState.protected then return Secret(label, value) end
    return value
end

local function Evaluate(curve, x)
    local p = curve.points
    if x <= p[1][1] then return p[1][2] end
    for index = 2, #p do
        if x <= p[index][1] then
            if curve.kind == 1 then return x < p[index][1] and p[index - 1][2] or p[index][2] end
            return p[index - 1][2] + (p[index][2] - p[index - 1][2]) * (x - p[index - 1][1]) / (p[index][1] - p[index - 1][1])
        end
    end
    return p[#p][2]
end

_G.CreateFrame = function(kind, _, parent) return NewRegion(kind, parent) end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return UnitValue("health", unitState.hp * 1000) end
_G.UnitHealthMax = function() return UnitValue("max", 1000) end
local curveReads, curveResults = {}, {}
_G.UnitHealthPercent = function(unit, usePredicted, curve)
    assert(usePredicted == true, "UnitHealthPercent without predicted health")
    curveReads[#curveReads + 1] = curve
    local result = UnitValue("curve alpha", curve and Evaluate(curve, Predicted()) or Predicted())
    curveResults[#curveResults + 1] = result
    return result
end
_G.UnitGetIncomingHeals = function() return UnitValue("incoming", unitState.incoming * 1000) end
_G.UnitGetTotalAbsorbs = function() return UnitValue("absorb", unitState.absorb * 1000) end
_G.UnitGetTotalHealAbsorbs = function() return UnitValue("heal absorb", 0) end
local calculators = {}
local calculatorAvailable = true
_G.CreateUnitHealPredictionCalculator = function()
    if not calculatorAvailable then return nil end
    local calc = {}
    function calc:SetDamageAbsorbClampMode(mode) self.mode = mode end
    -- MissingHealth: in excess of the missing health less the incoming heals.
    function calc:GetDamageAbsorbs()
        local boundary = (1 - self.hp) - self.incoming
        if boundary < 0 then boundary = 0 end
        self.clamped = Secret("clamped", self.absorb > boundary)
        return Secret("clamped amount", self.absorb), self.clamped
    end
    function calc:EvaluateCurrentHealthPercent(curve)
        self.evaluated = Secret("calculator curve", Evaluate(curve, self.hp))
        self.evaluatedCurve = curve
        return self.evaluated
    end
    calculators[#calculators + 1] = calc
    return calc
end
local detailedReads = 0
_G.UnitGetDetailedHealPrediction = function(unit, healer, calc)
    detailedReads = detailedReads + 1
    calc.lastUnit, calc.lastHealer = unit, healer
    calc.hp, calc.absorb, calc.incoming = unitState.hp, unitState.absorb, unitState.incoming
end
_G.Enum = { UnitDamageAbsorbClampMode = { MissingHealth = 0, MissingHealthWithoutIncomingHeals = 1 },
    LuaCurveType = { Linear = 0, Step = 1 } }
_G.C_CurveUtil = { CreateCurve = function()
    local curve = { points = {} }
    function curve:SetType(kind) self.kind = kind end
    function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    return curve
end }

local registered
local namespace = { UF = { Layers = {}, RegisterElement = function(name, element)
    if name == "Prediction" then registered = element end
end } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
    "MidnightSimpleUnitFrames", namespace)
assert(registered, "the prediction element did not register")

local function Upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing prediction upvalue: " .. wanted)
end
local UpdateOverAbsorbGlow = Upvalue(registered.UpdateGlowHealthFast, "UpdateOverAbsorbGlow")

local failures = {}
local function Check(condition, message) if not condition then failures[#failures + 1] = message end end

local function NewFrame(overlay, stripe)
    local frame = NewRegion("Button")
    frame.MSUFUnitKey = "target"
    frame.hpBar = NewRegion("StatusBar", frame)
    frame._msufPredictionOverAbsorbOverlay = overlay or nil
    frame._msufPredictionFullHealthStripe = stripe or nil
    return frame
end

local function Run(label, fn)
    local ok, err = pcall(fn)
    Check(ok, label .. ": " .. tostring(err))
end

-- What the client draws: holder fill, holder alpha and texture alpha, each
-- secret resolved to the plain value behind it.
local function Drawn(frame)
    local holder = frame.overAbsorbGlowBar
    if not (holder and holder.shown) then return false end
    -- The holder is a 0..1 StatusBar fed the raw absorb: a zero draws no fill.
    if holder.value ~= nil and not (Plain(holder.value) > 0) then return false end
    local holderAlpha = Plain(holder.alpha)
    local glow = holder.fill
    local glowAlpha = glow and glow.alpha or 1
    if glow and glowAlpha == "from flag" then
        if Plain(glow.alphaBoolean) == true then glowAlpha = Plain(glow.alphaIfTrue) else glowAlpha = Plain(glow.alphaIfFalse) end
    end
    return (holderAlpha or 0) * (glowAlpha or 0) > 0
end

-- 1. Overlay only, protected absorb and health.
Run("overlay only", function()
    unitState.protected, unitState.hp, unitState.absorb, unitState.incoming = true, 0.5, 0.6, 0
    local frame = NewFrame(true, false)
    local reads, curveCalls = detailedReads, #curveReads
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, true, true)
    local holder = frame.overAbsorbGlowBar
    Check(holder and holder:IsShown(), "overlay only: the protected over-absorb glow does not render")
    local calc = calculators[#calculators]
    Check(calc and calc.mode == 0, "overlay only: the calculator does not clamp to the missing health")
    Check(calc and calc.lastUnit == "target" and calc.lastHealer == "player",
        "overlay only: the calculator did not read the frame's unit for the player's heals")
    Check(detailedReads == reads + 1, "overlay only: one tick did not read the calculator exactly once")
    Check(#curveReads == curveCalls + 1, "overlay only: one tick did not read the partial-health curve exactly once")
    local glow = holder and holder.fill
    Check(glow and glow.alphaBoolean == calc.clamped and glow.alphaIfFalse == 0,
        "overlay only: the glow is not gated by the calculator's clamped flag")
    Check(glow and glow.alphaIfTrue == curveResults[#curveResults] and calc.evaluated == nil,
        "overlay only: the flag's alpha does not come from the predicted-health curve")
    local curve = curveReads[#curveReads]
    Check(curve and curve.kind == 1 and #curve.points == 2 and curve.points[1][1] == 0 and curve.points[1][2] == 1
        and curve.points[2][1] == 1 and curve.points[2][2] == 0,
        "overlay only: full health is not kept off by a partial-health step curve")
    Check(holder and holder.alpha == 1, "overlay only: the holder is not at full alpha")

    -- The glow texture handle is cached: health ticks do not ask for it.
    local textureCalls = textureReads
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, nil, true)
    Check(textureReads == textureCalls, "overlay only: a protected tick looked the glow texture up again")

    -- 3. A plain update afterwards clears the flag gate.
    unitState.protected = false
    local before = #log
    UpdateOverAbsorbGlow(frame, {}, "target", 600, 1000, 500, true, true, false)
    Check(holder:IsShown() and glow.alpha == 1 and holder.alpha == 1,
        "overlay only: a plain overflow after a protected one stays gated by the old flag")
    for index = before + 1, #log do
        Check(log[index] ~= "SetAlphaFromBoolean", "overlay only: the plain path asked the calculator")
    end
end)

-- 2. Overlay plus stripe: the flag alone is the union.
Run("overlay and stripe", function()
    unitState.protected = true
    local frame = NewFrame(true, true)
    local reads = #curveReads
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, true, true)
    local holder = frame.overAbsorbGlowBar
    local glow = holder and holder.fill
    Check(holder and holder:IsShown() and glow and IsSecret(glow.alphaBoolean) and glow.alphaIfTrue == 1,
        "overlay and stripe: the protected glow does not render through the clamped flag alone")
    Check(holder and holder.alpha == 1 and #curveReads == reads,
        "overlay and stripe: the holder is not at full alpha (the flag covers full health)")
end)

-- 4. The health follower opens for a protected absorb with the overlay on.
Run("health follower", function()
    unitState.protected = true
    local source = io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua", "rb")
    local text = source:read("*a"):gsub("\r\n", "\n")
    source:close()
    local opened = 0
    for _ in text:gmatch("absorbSecret and %(fullStripe or frame%._msufPredictionOverAbsorbOverlay == true%)") do opened = opened + 1 end
    for _ in text:gmatch("absorbSecret and %(frame%._msufPredictionFullHealthStripe == true\n%s*or frame%._msufPredictionOverAbsorbOverlay == true%)") do opened = opened + 1 end
    Check(opened == 2, "health follower: a protected absorb does not open the health follower for the overlay")
    -- _msufPredictionHealthVisualActive is the one health-follower gate; the
    -- write-only partial-glow twin is gone (W4-C1, grep proof over the addons).
    Check(not text:find("_msufPredictionPartialGlowHealthActive", 1, true),
        "health follower: the write-only partial-glow flag is written again")
    local frame = NewFrame(true, false)
    frame._msufPredictionHealthVisualActive = true
    frame._msufPredictionAbsorb = Secret("absorb")
    frame._msufPredictionAbsorbSecret = true
    frame._msufPredictionRuntimeCfg = {}
    frame._msufPredictionCacheReady, frame._msufPredictionCacheUnit, frame._msufPredictionCacheCfg = true, "target",
        frame._msufPredictionRuntimeCfg
    frame.hpBar._msufHealthPercentValue = 55
    frame.hpBar._msufHealthPercentUnit = "target"
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(frame.overAbsorbGlowBar and frame.overAbsorbGlowBar:IsShown(),
        "health follower: a health tick with a protected absorb does not render the glow")

    -- Warm layout: the tick is the calculator render alone, and it draws.
    unitState.hp, unitState.absorb, unitState.incoming = 0.55, 0.6, 0
    local holder = frame.overAbsorbGlowBar
    -- The absorb-data owner feeds the holder its raw absorb on
    -- UNIT_ABSORB_AMOUNT_CHANGED (writeAbsorbValue).
    UpdateOverAbsorbGlow(frame, {}, "target", nil, nil, Secret("absorb", 600), false, true, true)
    local reads = detailedReads
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(detailedReads == reads + 1 and Drawn(frame),
        "health follower: a warm protected tick does not render the overflow from one calculator read")
    unitState.hp = 1
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(not Drawn(frame), "health follower: a warm protected tick at full health still draws the partial glow")

    -- No calculator on a warm layout: hide, never keep the last flag up.
    unitState.hp = 0.55
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    local calc = frame._msufPredictionOverAbsorbCalc
    frame._msufPredictionOverAbsorbCalc, calculatorAvailable = nil, false
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(not holder:IsShown(), "health follower: a warm tick without a calculator kept the old glow")
    frame._msufPredictionOverAbsorbCalc, calculatorAvailable = calc, true

    -- A changed layout goes through the authoritative path, which re-anchors.
    unitState.hp = 0.55
    frame._msufPredictionHpReverse = true
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(holder._msufOverAbsorbReverse == true and Drawn(frame),
        "health follower: a reversed health bar kept the glow on the old edge")

    -- Overlay switched off: the authoritative path hides.
    frame._msufPredictionOverAbsorbOverlay = nil
    registered.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "target")
    Check(not holder:IsShown(), "health follower: the glow stays up after the overlay was switched off")
end)

-- 5. Without the calculator nothing is guessed.
Run("no calculator", function()
    unitState.protected = true
    calculatorAvailable = false
    local frame = NewFrame(true, false)
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, true, true)
    Check(not (frame.overAbsorbGlowBar and frame.overAbsorbGlowBar:IsShown()),
        "no calculator: the glow showed without a clamped flag")
    calculatorAvailable = true
end)

-- 6. What the client draws, against the plain rule (Drawn is above).
-- The intended rule. `current` is the calculator's health, `predicted` the
-- health bar's (UnitHealthPercent usePredicted). The plain path knows only the
-- predicted value and uses Blizzard's CompactUnitFrame overflow rule
-- (health + incoming + absorb >= max, CompactUnitFrame.lua
-- CompactUnitFrame_UpdateHealPrediction). The protected path cannot compare:
-- predicted health gates full health through the step curve, and the overflow
-- is the calculator's MissingHealth flag, documented as "in excess of the
-- clamp boundary" (UnitHealPredictionCalculatorAPIDocumentation). When the
-- health and incoming-heal inputs agree, the exact boundary (absorb ==
-- missing - incoming) is where that flag stays off while the plain rule shows
-- (no secret-safe API reports >=). When the calculator's health differs from
-- the predicted health, the overflow follows the calculator's inputs (for
-- example calculator 0.20, predicted 0.30, absorb 0.50, incoming 0.25: plain
-- shows, protected does not).
local function Rule(protected, current, predicted, absorb, incoming, overlay, stripe)
    if absorb <= 0 then return false end
    if not protected then
        if predicted >= 1 then return stripe end
        if not overlay then return false end
        return predicted + incoming + absorb >= 1
    end
    local boundary = (1 - current) - incoming
    if boundary < 0 then boundary = 0 end
    local overflow = absorb > boundary
    if overlay and stripe then return overflow end
    if overlay then return overflow and predicted < 1 end
    -- The stripe alone: the full-health curve on predicted health.
    return predicted >= 1
end

local HEALTH = { 0.2, 0.5, 0.55, 0.75, 0.9, 1 }
local ABSORB = { 0, 0.05, 0.25, 0.3, 0.5, 0.6 }
local INCOMING = { 0, 0.25 }
-- Predicted health ahead of, equal to, and behind the calculator's.
local PREDICTED_SHIFT = { 0, 0.1, -0.1 }
local function Render(protected, current, predicted, absorb, incoming, overlay, stripe)
    unitState.protected, unitState.hp, unitState.predicted, unitState.absorb, unitState.incoming =
        protected, current, predicted, absorb, incoming
    local frame = NewFrame(overlay, stripe)
    frame._msufPredictionIncoming = incoming * 1000
    -- The plain path's health seed is the health bar's (predicted) value.
    local hpValue, maxValue, absorbValue = UnitValue("hp", predicted * 1000), UnitValue("max", 1000),
        UnitValue("absorb", absorb * 1000)
    UpdateOverAbsorbGlow(frame, {}, "target", hpValue, maxValue, absorbValue, true, true, protected)
    -- A second tick on the same frame must agree with the first.
    UpdateOverAbsorbGlow(frame, {}, "target", hpValue, maxValue, absorbValue, true, nil, protected)
    unitState.predicted = nil
    return Drawn(frame)
end

Run("rendered visibility", function()
    for _, protected in ipairs({ true, false }) do
        for _, shape in ipairs({ { true, false }, { true, true }, { false, true } }) do
            local overlay, stripe = shape[1], shape[2]
            for _, hp in ipairs(HEALTH) do
                for _, shift in ipairs(PREDICTED_SHIFT) do
                    local predicted = math.floor((hp + shift) * 100 + 0.5) / 100
                    if predicted > 1 then predicted = 1 elseif predicted < 0 then predicted = 0 end
                    for _, absorb in ipairs(ABSORB) do
                        for _, incoming in ipairs(INCOMING) do
                            local drawn = Render(protected, hp, predicted, absorb, incoming, overlay, stripe)
                            local want = Rule(protected, hp, predicted, absorb, incoming, overlay, stripe)
                            Check(drawn == want, string.format(
                                "rendered visibility: %s, overlay %s, stripe %s, health %.2f (predicted %.2f), "
                                    .. "absorb %.2f, incoming %.2f draws %s, the rule says %s",
                                protected and "protected" or "plain", tostring(overlay), tostring(stripe), hp,
                                predicted, absorb, incoming, tostring(drawn), tostring(want)))
                        end
                    end
                end
            end
        end
    end
end)

-- The documented edge, spelled out: an absorb that exactly fills the missing
-- health (incoming heals counted) shows by the plain >= rule, but not through
-- the calculator flag ("in excess of the clamp boundary").
Run("exact absorb boundary", function()
    for _, case in ipairs({ { 0.5, 0.5, 0 }, { 0.75, 0.25, 0 }, { 0.5, 0.25, 0.25 } }) do
        local hp, absorb, incoming = case[1], case[2], case[3]
        Check(Render(false, hp, hp, absorb, incoming, true, false) == true, string.format(
            "exact absorb boundary: plain health %.2f, absorb %.2f, incoming %.2f does not show", hp, absorb, incoming))
        Check(Render(true, hp, hp, absorb, incoming, true, false) == false, string.format(
            "exact absorb boundary: protected health %.2f, absorb %.2f, incoming %.2f no longer follows the "
                .. "calculator's strict flag; update the documented difference", hp, absorb, incoming))
    end
end)

-- Predicted health at full while the calculator still sees partial health:
-- the partial glow keeps to the health bar and stays hidden.
Run("predicted full health", function()
    Check(Render(true, 0.9, 1, 0.6, 0, true, false) == false,
        "predicted full health: the partial glow shows while the health bar is full")
    Check(Render(true, 1, 0.9, 0.6, 0, true, false) == true,
        "predicted full health: the partial glow hides while the health bar is partial")
end)

-- The stripe alone gates full health on the holder alpha. Switching the
-- overlay on afterwards must not leave that gate on the holder.
Run("stripe then overlay", function()
    unitState.protected, unitState.hp, unitState.absorb, unitState.incoming = true, 0.55, 0.6, 0
    local frame = NewFrame(false, true)
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp", 550), Secret("max", 1000), Secret("absorb", 600),
        true, true, true)
    Check(not Drawn(frame), "stripe then overlay: the stripe alone drew at partial health")
    frame._msufPredictionOverAbsorbOverlay = true
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp", 550), Secret("max", 1000), Secret("absorb", 600),
        true, nil, true)
    Check(Drawn(frame), "stripe then overlay: the overflow stays hidden behind the stripe's full-health gate")
end)

if #failures > 0 then
    for i = 1, #failures do print("FAIL " .. failures[i]) end
    os.exit(1)
end
print("over_absorb_protected_glow_smoke: ok")
