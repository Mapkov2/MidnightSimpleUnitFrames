-- over_absorb_protected_glow_smoke.lua <repoRoot>
--
-- The partial-health over-absorb glow (Bars > Prediction "over-absorb overlay")
-- shows when the absorb overflows the missing health. On Midnight
-- UnitGetTotalAbsorbs returns a secret, and health often is one too: the
-- element had no secret-safe path and hid the glow for every protected
-- operand, so it never rendered there.
--
-- The prediction calculator's MissingHealth clamp reports that overflow as
-- `clamped`; SetAlphaFromBoolean consumes it on the glow texture, a step curve
-- on the holder keeps full health to the full-health stripe. This smoke loads
-- the real element with values as strict as the client (a secret refuses
-- comparison, arithmetic, concatenation and indexing) and pins:
--   1. overlay only: protected values render through the calculator flag and
--      the partial-health curve, without Lua touching a secret;
--   2. overlay plus stripe: the flag alone, holder at full alpha;
--   3. a following plain update clears the flag gate on the glow;
--   4. the health follower opens for a protected absorb with the overlay on;
--   5. without the calculator the glow still hides (no guessing).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Forbidden() error("restricted prediction value inspected", 2) end
local SECRET_META = { __eq = Forbidden, __lt = Forbidden, __le = Forbidden, __add = Forbidden,
    __sub = Forbidden, __mul = Forbidden, __div = Forbidden, __concat = Forbidden,
    __index = Forbidden, __len = Forbidden }
local secrets = {}
local function Secret(label)
    local value = setmetatable({}, SECRET_META)
    secrets[value] = label
    return value
end
local function IsSecret(value) return secrets[value] ~= nil end
_G.issecretvalue = IsSecret

local log = {}
local function Record(entry) log[#log + 1] = entry end

local Region = {}
Region.__index = Region
local function NewRegion(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1 }, Region)
end
function Region:SetAlpha(alpha) self.alpha = alpha end
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
function Region:GetStatusBarTexture() self.fill = self.fill or NewRegion("Texture", self); return self.fill end
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

_G.CreateFrame = function(kind, _, parent) return NewRegion(kind, parent) end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return Secret("health") end
_G.UnitHealthMax = function() return Secret("max") end
local curveReads = {}
_G.UnitHealthPercent = function(unit, _, curve)
    curveReads[#curveReads + 1] = curve
    return Secret("curve alpha")
end
_G.UnitGetIncomingHeals = function() return Secret("incoming") end
_G.UnitGetTotalAbsorbs = function() return Secret("absorb") end
_G.UnitGetTotalHealAbsorbs = function() return Secret("heal absorb") end
local calculators = {}
local calculatorAvailable = true
_G.CreateUnitHealPredictionCalculator = function()
    if not calculatorAvailable then return nil end
    local calc = { clamped = Secret("clamped") }
    function calc:SetDamageAbsorbClampMode(mode) self.mode = mode end
    function calc:GetDamageAbsorbs() return Secret("clamped amount"), self.clamped end
    calculators[#calculators + 1] = calc
    return calc
end
local detailedReads = 0
_G.UnitGetDetailedHealPrediction = function(unit, healer, calc)
    detailedReads = detailedReads + 1
    calc.lastUnit, calc.lastHealer = unit, healer
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

-- 1. Overlay only, protected absorb and health.
Run("overlay only", function()
    local frame = NewFrame(true, false)
    local absorb = Secret("absorb")
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), absorb, true, true, true)
    local holder = frame.overAbsorbGlowBar
    Check(holder and holder:IsShown(), "overlay only: the protected over-absorb glow does not render")
    local calc = calculators[#calculators]
    Check(calc and calc.mode == 0, "overlay only: the calculator does not clamp to the missing health")
    Check(calc and calc.lastUnit == "target" and calc.lastHealer == "player",
        "overlay only: the calculator did not read the frame's unit for the player's heals")
    local glow = holder and holder:GetStatusBarTexture()
    Check(glow and glow.alphaBoolean == calc.clamped and glow.alphaIfTrue == 1 and glow.alphaIfFalse == 0,
        "overlay only: the glow is not gated by the calculator's clamped flag")
    local curve = curveReads[#curveReads]
    Check(curve and curve.kind == 1 and #curve.points == 2 and curve.points[1][1] == 0 and curve.points[1][2] == 1
        and curve.points[2][1] == 1 and curve.points[2][2] == 0,
        "overlay only: full health is not kept off by a partial-health step curve")
    Check(IsSecret(holder.alpha), "overlay only: the holder alpha does not come from the health curve")

    -- 3. A plain update afterwards clears the flag gate.
    local before = #log
    UpdateOverAbsorbGlow(frame, {}, "target", 600, 1000, 500, true, true, false)
    Check(holder:IsShown() and glow.alpha == 1 and holder.alpha == 1,
        "overlay only: a plain overflow after a protected one stays gated by the old flag")
    Check(#log == before, "overlay only: the plain path asked the calculator")
end)

-- 2. Overlay plus stripe: the flag alone is the union.
Run("overlay and stripe", function()
    local frame = NewFrame(true, true)
    local reads = #curveReads
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, true, true)
    local holder = frame.overAbsorbGlowBar
    local glow = holder and holder:GetStatusBarTexture()
    Check(holder and holder:IsShown() and glow and IsSecret(glow.alphaBoolean),
        "overlay and stripe: the protected glow does not render through the clamped flag")
    Check(holder and holder.alpha == 1 and #curveReads == reads,
        "overlay and stripe: the holder is not at full alpha (the flag covers full health)")
end)

-- 4. The health follower opens for a protected absorb with the overlay on.
Run("health follower", function()
    local source = io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua", "rb")
    local text = source:read("*a"):gsub("\r\n", "\n")
    source:close()
    local opened = 0
    for _ in text:gmatch("absorbSecret and %(fullStripe or frame%._msufPredictionOverAbsorbOverlay == true%)") do opened = opened + 1 end
    for _ in text:gmatch("absorbSecret and %(frame%._msufPredictionFullHealthStripe == true\n%s*or frame%._msufPredictionOverAbsorbOverlay == true%)") do opened = opened + 1 end
    Check(opened == 2, "health follower: a protected absorb does not open the health follower for the overlay")
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
end)

-- 5. Without the calculator nothing is guessed.
Run("no calculator", function()
    calculatorAvailable = false
    local frame = NewFrame(true, false)
    UpdateOverAbsorbGlow(frame, {}, "target", Secret("hp"), Secret("max"), Secret("absorb"), true, true, true)
    Check(not (frame.overAbsorbGlowBar and frame.overAbsorbGlowBar:IsShown()),
        "no calculator: the glow showed without a clamped flag")
    calculatorAvailable = true
end)

if #failures > 0 then
    for i = 1, #failures do print("FAIL " .. failures[i]) end
    os.exit(1)
end
print("over_absorb_protected_glow_smoke: ok")
