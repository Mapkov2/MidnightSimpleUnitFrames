-- Standalone regression for per-render-frame prediction data-event coalescing.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local Methods = {}
local drivers = {}

local function Bump(region, operation)
    local operations = region.operations
    operations[operation] = (operations[operation] or 0) + 1
end

local function OperationCount(region, operation)
    return region.operations[operation] or 0
end

local function NewRegion(kind, parent)
    return setmetatable({
        kind = kind,
        parent = parent,
        scripts = {},
        shown = true,
        width = 100,
        frameLevel = 1,
        frameStrata = "MEDIUM",
        operations = {},
        hooks = {},
        registered = {},
    }, { __index = Methods })
end

function Methods:SetScript(script, callback) self.scripts[script] = callback end
function Methods:HookScript(script, callback) self.hooks[script] = callback end
function Methods:RegisterEvent(event) self.registered[event] = true end
function Methods:RegisterUnitEvent(event, unit) self.registered[event] = unit end
function Methods:UnregisterEvent(event) self.registered[event] = nil end
function Methods:UnregisterAllEvents()
    for event in pairs(self.registered) do self.registered[event] = nil end
end
function Methods:CreateTexture() return NewRegion("Texture", self) end
function Methods:SetMinMaxValues(minimum, maximum)
    Bump(self, "SetMinMaxValues")
    self.minimum, self.maximum = minimum, maximum
end
function Methods:SetValue(value) Bump(self, "SetValue"); self.value = value end
function Methods:SetStatusBarTexture(texture)
    self.statusTexture = self.statusTexture or NewRegion("Texture", self)
    self.statusTexture.path = texture
end
function Methods:GetStatusBarTexture()
    self.statusTexture = self.statusTexture or NewRegion("Texture", self)
    return self.statusTexture
end
function Methods:SetStatusBarColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function Methods:SetAlpha(alpha) self.alpha = alpha end
function Methods:SetTexture(texture) self.path = texture end
function Methods:SetColorTexture(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function Methods:SetBlendMode(mode) self.blendMode = mode end
function Methods:SetShown(shown) self.shown = shown == true end
function Methods:IsShown() return self.shown == true end
function Methods:IsVisible() return self.shown == true end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetAllPoints() Bump(self, "SetAllPoints") end
function Methods:ClearAllPoints() Bump(self, "ClearAllPoints") end
function Methods:SetPoint() Bump(self, "SetPoint") end
function Methods:SetWidth(width) Bump(self, "SetWidth"); self.width = width end
function Methods:GetWidth() Bump(self, "GetWidth"); return self.width end
function Methods:SetHeight(height) Bump(self, "SetHeight"); self.height = height end
function Methods:SetParent(parent) Bump(self, "SetParent"); self.parent = parent end
function Methods:GetParent() Bump(self, "GetParent"); return self.parent end
function Methods:SetFrameLevel(level) Bump(self, "SetFrameLevel"); self.frameLevel = level end
function Methods:GetFrameLevel() Bump(self, "GetFrameLevel"); return self.frameLevel end
function Methods:SetFrameStrata(strata) Bump(self, "SetFrameStrata"); self.frameStrata = strata end
function Methods:GetFrameStrata() Bump(self, "GetFrameStrata"); return self.frameStrata end
function Methods:SetReverseFill(reverse) Bump(self, "SetReverseFill"); self.reverse = reverse == true end
function Methods:SetClipsChildren(clips) self.clipsChildren = clips == true end

_G.CreateFrame = function(kind, _, parent)
    local frame = NewRegion(kind, parent)
    if kind == "Frame" and parent == nil then drivers[#drivers + 1] = frame end
    return frame
end

local calls = {}
local detailedHook
local calculatorAbsorb = 18
local directAbsorbHook
local directIncomingValue = 30
local directHealAbsorbValue = 7

local function ResetCalls()
    calls.detailed = 0
    calls.incoming = 0
    calls.absorb = 0
    calls.healAbsorb = 0
    calls.directIncoming = 0
    calls.directAbsorb = 0
    calls.directHealAbsorb = 0
    calls.lastUnit = nil
    detailedHook = nil
    directAbsorbHook = nil
end

local function DirectReads()
    return calls.directIncoming + calls.directAbsorb + calls.directHealAbsorb
end

ResetCalls()

_G.Enum = {
    UnitIncomingHealClampMode = { MissingHealth = 0, MaximumHealth = 1 },
    UnitDamageAbsorbClampMode = { MissingHealthWithoutIncomingHeals = 1, MaximumHealth = 2 },
    UnitHealAbsorbClampMode = { CurrentHealth = 0 },
    UnitHealAbsorbMode = { Total = 1 },
    LuaCurveType = { Step = 1 },
}
_G.issecretvalue = function(value) return type(value) == "table" and value.__secret == true end
local healthPercentAlpha = 1
local healthPercentReads = 0
_G.C_CurveUtil = {
    CreateCurve = function()
        return {
            SetType = function() end,
            AddPoint = function() end,
        }
    end,
}
_G.UnitHealthPercent = function()
    healthPercentReads = healthPercentReads + 1
    return healthPercentAlpha
end
local unitExists = true
_G.UnitExists = function() return unitExists end
local unitConnected = true
_G.UnitIsConnected = function() return unitConnected end
local healthReads = 0
_G.UnitHealth = function()
    healthReads = healthReads + 1
    return 60
end
local healthMaxReads = 0
local healthMaxValue = 100
_G.UnitHealthMax = function()
    healthMaxReads = healthMaxReads + 1
    return healthMaxValue
end
_G.UnitGetIncomingHeals = function(unit, healer)
    calls.directIncoming = calls.directIncoming + 1
    calls.lastUnit = unit
    Check(healer == "player", "direct incoming-heal read lost its healer filter")
    return directIncomingValue
end
local totalAbsorbValue = 18
local totalAbsorbReads = 0
_G.UnitGetTotalAbsorbs = function(unit)
    calls.directAbsorb = calls.directAbsorb + 1
    calls.lastUnit = unit
    totalAbsorbReads = totalAbsorbReads + 1
    if directAbsorbHook then directAbsorbHook() end
    return totalAbsorbValue
end
_G.UnitGetTotalHealAbsorbs = function(unit)
    calls.directHealAbsorb = calls.directHealAbsorb + 1
    calls.lastUnit = unit
    return directHealAbsorbValue
end

local function NewCalculator()
    return {
        SetIncomingHealClampMode = function() end,
        SetDamageAbsorbClampMode = function() end,
        SetHealAbsorbClampMode = function() end,
        SetHealAbsorbMode = function() end,
        ResetPredictedValues = function() end,
        GetDamageAbsorbs = function()
            calls.absorb = calls.absorb + 1
            return calculatorAbsorb
        end,
        GetHealAbsorbs = function()
            calls.healAbsorb = calls.healAbsorb + 1
            return 7
        end,
        GetCurrentHealth = function() return 60 end,
        GetMaximumHealth = function() return 100 end,
    }
end

_G.CreateUnitHealPredictionCalculator = NewCalculator
_G.UnitGetDetailedHealPrediction = function(unit)
    calls.detailed = calls.detailed + 1
    calls.lastUnit = unit
    if detailedHook then detailedHook(unit) end
end

local captured
local MSUF = {
    UF = {
        RegisterElement = function(name, element)
            if name == "Prediction" then captured = element end
        end,
    },
}
_G.MSUF_NS = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local Prediction = assert(captured, "Prediction element was not registered")

local config = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = true,
    healAnchorMode = 3,
    absorbAnchorMode = 3,
    overAbsorbOverlay = false,
}

local function MakeFrame(unit, cfg)
    local frame = NewRegion("UnitFrame")
    frame.unit = unit
    frame.MSUFUnitKey = unit
    frame.hpBar = NewRegion("StatusBar", frame)
    frame.hpBar:SetStatusBarTexture("health")
    frame.hpBar:SetMinMaxValues(0, 100)
    frame.hpBar:SetValue(60)
    local spec = {
        key = unit,
        unit = unit,
        width = 100,
        texture = "health",
        health = { reverse = false },
        prediction = cfg,
    }
    frame.MSUFSpec = spec
    Prediction.Apply(frame, spec)
    Prediction.Update(frame, "MSUF_TEST_SEED", unit)
    return frame, spec
end

local function FlushDriver()
    local driver = drivers[#drivers]
    Check(driver ~= nil, "prediction driver was not created")
    local callback = driver.scripts.OnUpdate
    Check(type(callback) == "function", "prediction driver is not armed")
    callback(driver, 0)
end

local frame, spec = MakeFrame("player", config)
local queueHeal = Prediction.SelectEventUpdate(frame, spec, "UNIT_HEAL_PREDICTION")
local queueAbsorb = Prediction.SelectEventUpdate(frame, spec, "UNIT_ABSORB_AMOUNT_CHANGED")
local queueHealAbsorb = Prediction.SelectEventUpdate(frame, spec, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
Check(queueHeal == queueAbsorb and queueAbsorb == queueHealAbsorb, "data events do not share one queue path")
Equal(Prediction.SelectEventUpdate(frame, spec, "UNIT_HEALTH"), Prediction.UpdateHealthValue,
    "follow geometry unexpectedly compiled a health calculator selector")
Check(Prediction.UpdateClampedHealthFast == nil and Prediction.ReadDetailedHealth == nil,
    "removed calculator/health-share API remained exported")
Check(type(frame._msufPredictionFlushData) == "function",
    "live prediction plan did not compile its bound render-frame drain")

-- Repeated copies of one data event collapse to one direct native read and keep
-- the event-specific getter plan.
ResetCalls()
for _ = 1, 10 do queueHeal(frame, "UNIT_HEAL_PREDICTION", { __secret = true }) end
Equal(calls.detailed, 0, "prediction work ran before the render-frame flush")
local persistentDriver = drivers[#drivers]
Check(persistentDriver and persistentDriver.shown == true,
    "queued prediction work did not wake its persistent driver")
local persistentCallback = persistentDriver.scripts.OnUpdate
FlushDriver()
Equal(calls.detailed, 0, "common follow geometry created a detailed calculator read")
Equal(calls.directIncoming, 1, "heal event was not coalesced to one direct read")
Equal(calls.directAbsorb, 0, "heal-only event refreshed absorbs")
Equal(calls.directHealAbsorb, 0, "heal-only event refreshed heal absorbs")
Equal(calls.lastUnit, "player", "secret event payload escaped into the queued API read")
Check(persistentDriver.shown == false
    and persistentDriver.scripts.OnUpdate == persistentCallback,
    "idle prediction driver retained frame work or rewrote its OnUpdate")

-- All three events merge into one drain while preserving the union
-- of their component-specific getters.
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "wrong-unit")
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "wrong-unit")
queueHealAbsorb(frame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "wrong-unit")
FlushDriver()
Equal(calls.detailed, 0, "merged direct events used a detailed calculator")
Equal(calls.directIncoming, 1, "merged heal getter count")
Equal(calls.directAbsorb, 1, "merged absorb getter count")
Equal(calls.directHealAbsorb, 1, "merged heal-absorb getter count")

-- Coalescing is per frame, never global across different units.
local second = MakeFrame("target", config)
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
queueHeal(second, "UNIT_HEAL_PREDICTION", "target")
FlushDriver()
Equal(calls.directIncoming, 2, "different unitframes were incorrectly merged")

-- A synchronous full/lifecycle refresh consumes a pending data update because
-- its full plan already covers every component.
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
Prediction.Update(frame, "MSUF_FORCE_UPDATE", "player")
Equal(calls.directIncoming, 1, "synchronous full refresh did not run")
FlushDriver()
Equal(calls.directIncoming, 1, "consumed pending update ran a second time")

-- Apply/Disable invalidates data captured for the previous configuration.
ResetCalls()
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
Prediction.Disable(frame)
Check(frame._msufPredictionFlushData == nil,
    "disabled prediction retained its bound render-frame drain")
FlushDriver()
Equal(calls.detailed, 0, "disabled frame processed stale prediction data")
Prediction.Apply(frame, spec)
Prediction.Update(frame, "MSUF_TEST_RESEED", "player")

-- A transiently missing startup unit may clear Prediction's compiled mask.
-- The first later data event must revalidate the live spec instead of being
-- discarded forever by the coalescer's cached disabled state.
unitExists = false
Prediction.Update(frame, "MSUF_STARTUP_UNIT_MISSING", "player")
Check(frame._msufPredictionDisabled == true, "missing startup unit did not disable prediction")
Equal(frame._msufPredictionMask, 0, "missing startup unit did not clear prediction mask")
unitExists = true
ResetCalls()
for _ = 1, 10 do queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player") end
Equal(calls.detailed, 0, "disabled recovery ran before the render-frame flush")
FlushDriver()
Equal(calls.detailed, 0, "disabled direct recovery created a calculator")
Equal(calls.directAbsorb, 1, "disabled recovery burst was not coalesced")
Check(frame._msufPredictionDisabled ~= true, "valid absorb event left prediction disabled")
Equal(frame._msufPredictionAbsorb, 18, "disabled recovery did not populate absorb state")
Check(type(frame._msufPredictionFlushData) == "function",
    "recovered prediction did not restore its bound render-frame drain")

-- Work raised while the active batch is draining is deferred to the next
-- driver invocation, preventing same-frame queue amplification.
ResetCalls()
local reentered = false
directAbsorbHook = function()
    if not reentered then
        reentered = true
        queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
    end
end
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
FlushDriver()
Equal(calls.directAbsorb, 1, "reentrant event extended the active batch")
directAbsorbHook = nil
FlushDriver()
Equal(calls.directIncoming, 1, "reentrant event was not preserved for the next batch")

-- Absorb-only frames retain the native UNIT_ABSORB event key and therefore do
-- not take the synthetic full-plan/force-max branch.
local absorbOnlyConfig = {
    enabled = true,
    heal = false,
    absorb = true,
    healAbsorb = false,
    absorbAnchorMode = 2,
    overAbsorbOverlay = false,
}
local absorbOnly, absorbOnlySpec = MakeFrame("focus", absorbOnlyConfig)
local queueAbsorbOnly = Prediction.SelectEventUpdate(absorbOnly, absorbOnlySpec, "UNIT_ABSORB_AMOUNT_CHANGED")
ResetCalls()
queueAbsorbOnly(absorbOnly, "UNIT_ABSORB_AMOUNT_CHANGED", "focus")
FlushDriver()
Equal(calls.detailed, 0, "absorb-only path unexpectedly created a detailed calculator read")
Equal(absorbOnly.absorbBar._msufMaxReady, true, "absorb-only bar lost its native max state")

-- Hiding a zero overlay must preserve its already-seeded native range. Resetting
-- the range to 0..1 both adds a setter and leaves the next positive payload
-- clamped because no max-health invalidation occurred between the two events.
local absorbRangeWrites = OperationCount(absorbOnly.absorbBar, "SetMinMaxValues")
local absorbRange = absorbOnly.absorbBar.maximum
totalAbsorbValue = 0
queueAbsorbOnly(absorbOnly, "UNIT_ABSORB_AMOUNT_CHANGED", "focus")
FlushDriver()
Equal(absorbOnly.absorbBar.maximum, absorbRange,
    "zero prediction payload replaced the live native range")
Equal(OperationCount(absorbOnly.absorbBar, "SetMinMaxValues"), absorbRangeWrites,
    "hiding a zero prediction payload repeated the native range setter")
totalAbsorbValue = 18
queueAbsorbOnly(absorbOnly, "UNIT_ABSORB_AMOUNT_CHANGED", "focus")
FlushDriver()
Equal(absorbOnly.absorbBar.maximum, absorbRange,
    "positive prediction recovery lost the retained native range")
Equal(OperationCount(absorbOnly.absorbBar, "SetMinMaxValues"), absorbRangeWrites,
    "positive prediction recovery repeated an unchanged native range setter")

-- Modes 1..5 share one layout implementation. Verify both health directions,
-- the overflow parent, and the mode-3 native clip contract without prediction
-- reads on a health tick.
local expectedNormalReverse = { false, true, false, false, true }
local expectedHealthReverse = { false, true, true, true, false }
for mode = 1, 5 do
    for reverseIndex = 1, 2 do
        local hpReverse = reverseIndex == 2
        local modeFrame = MakeFrame("boss" .. mode, {
            enabled = true,
            heal = false,
            absorb = true,
            healAbsorb = false,
            absorbAnchorMode = mode,
            overAbsorbOverlay = false,
        })
        modeFrame.MSUFSpec.health.reverse = hpReverse
        Prediction.Apply(modeFrame, modeFrame.MSUFSpec)
        Prediction.Update(modeFrame, "UNIT_MAXHEALTH", modeFrame.MSUFUnitKey)
        local modeBar = modeFrame.absorbBar
        local expectedReverse = expectedNormalReverse[mode]
        if hpReverse then expectedReverse = expectedHealthReverse[mode] end
        Equal(modeBar.reverse, expectedReverse,
            "anchor mode " .. mode .. " reverse-fill contract (hpReverse="
                .. tostring(hpReverse) .. ", compiled="
                .. tostring(modeFrame._msufPredictionAbsorbReverse) .. ")")
        Equal(modeBar:GetParent(), mode == 4 and modeFrame or modeFrame.hpBar,
            "anchor mode " .. mode .. " parent contract")
        if mode == 3 then
            Check(modeFrame.hpBar.clipsChildren == true,
                "follow-HP mode did not enable native child clipping")
        end
    end
end

Check(frame.absorbBar._msufPredictionFollowBar == frame.incomingHealBar,
    "follow absorb did not anchor behind the visible incoming-heal texture")
Check(frame.hpBar.clipsChildren == true,
    "common heal+absorb follow geometry is not clipped by the HP bar")

-- Protected direct payloads flow untouched into the three native StatusBars.
local secretIncoming = { __secret = true }
local secretAbsorb = { __secret = true }
local secretHealAbsorb = { __secret = true }
directIncomingValue = secretIncoming
totalAbsorbValue = secretAbsorb
directHealAbsorbValue = secretHealAbsorb
ResetCalls()
local protectedFrame = MakeFrame("raid1", config)
Equal(protectedFrame.incomingHealBar.value, secretIncoming,
    "protected incoming-heal payload was inspected or replaced")
Equal(protectedFrame.absorbBar.value, secretAbsorb,
    "protected absorb payload was inspected or replaced")
Equal(protectedFrame.healAbsorbBar.value, secretHealAbsorb,
    "protected heal-absorb payload was inspected or replaced")
Equal(calls.detailed, 0, "protected common payloads created a detailed calculator")
directIncomingValue = 30
totalAbsorbValue = 18
directHealAbsorbValue = 7

-- Every heal anchor consumes the same event-backed direct value; anchoring and
-- clipping, not a calculator, own its visual bounds.
local nonClampHealConfig = {
    enabled = true,
    heal = true,
    absorb = false,
    healAbsorb = false,
    healAnchorMode = 2,
}
local nonClampHeal, nonClampHealSpec = MakeFrame("party2", nonClampHealConfig)
local queueNonClampHeal = Prediction.SelectEventUpdate(
    nonClampHeal, nonClampHealSpec, "UNIT_HEAL_PREDICTION")
ResetCalls()
queueNonClampHeal(nonClampHeal, "UNIT_HEAL_PREDICTION", "party2")
FlushDriver()
Equal(calls.detailed, 0, "side-anchored incoming heal created a calculator read")
Equal(calls.directIncoming, 1, "side-anchored incoming heal skipped its direct API")
Equal(nonClampHeal._msufPredictionIncoming, 30,
    "side-anchored incoming heal lost its direct event value")

-- A normal mixed group-style configuration remains entirely direct when the
-- absorb bar is not in follow-HP mode.
local mixedConfig = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = true,
    healAnchorMode = 3,
    absorbAnchorMode = 5,
    healAbsorbAnchorMode = 3,
    overAbsorbOverlay = true,
}
local mixed, mixedSpec = MakeFrame("party4", mixedConfig)
local queueMixedHeal = Prediction.SelectEventUpdate(mixed, mixedSpec, "UNIT_HEAL_PREDICTION")
local queueMixedAbsorb = Prediction.SelectEventUpdate(mixed, mixedSpec, "UNIT_ABSORB_AMOUNT_CHANGED")
local queueMixedHealAbsorb = Prediction.SelectEventUpdate(mixed, mixedSpec, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")

ResetCalls()
queueMixedAbsorb(mixed, "UNIT_ABSORB_AMOUNT_CHANGED", "party4")
FlushDriver()
Equal(calls.detailed, 0, "non-follow absorb event paid for the detailed calculator")
Equal(calls.directAbsorb, 1, "non-follow absorb event missed its direct native read")
Equal(calls.absorb, 0, "non-follow absorb event used the calculator getter")

ResetCalls()
queueMixedHeal(mixed, "UNIT_HEAL_PREDICTION", "party4")
FlushDriver()
Equal(calls.detailed, 0, "follow-health incoming heal created a calculator read")
Equal(calls.directIncoming, 1, "follow-health incoming heal skipped its direct API")

ResetCalls()
queueMixedHealAbsorb(mixed, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "party4")
FlushDriver()
Equal(calls.detailed, 0, "heal-absorb created a calculator read")
Equal(calls.directHealAbsorb, 1, "heal-absorb skipped its direct API")

-- One legacy combination cannot use the HP clip alone: an absorb following HP
-- while its visible heal predecessor is independently side/max anchored. Keep
-- the Blizzard absorb clamp compiled only for that configuration.
local mixedFollowConfig = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = false,
    healAnchorMode = 2,
    absorbAnchorMode = 3,
    overAbsorbOverlay = false,
}
local mixedFollow, mixedFollowSpec = MakeFrame("party5", mixedFollowConfig)
Equal(Prediction.SelectEventUpdate(mixedFollow, mixedFollowSpec, "UNIT_HEALTH"),
    Prediction.UpdateMixedFollowHealthFast,
    "mixed follow configuration did not compile its exceptional selector")
local queueMixedFollowAbsorb = Prediction.SelectEventUpdate(
    mixedFollow, mixedFollowSpec, "UNIT_ABSORB_AMOUNT_CHANGED")
ResetCalls()
queueMixedFollowAbsorb(mixedFollow, "UNIT_ABSORB_AMOUNT_CHANGED", "party5")
FlushDriver()
Equal(calls.detailed, 1, "mixed follow absorb skipped its required native clamp")
Equal(calls.absorb, 1, "mixed follow absorb skipped its clamped getter")
Equal(calls.directAbsorb, 0, "mixed follow absorb also performed a raw read")
ResetCalls()
Prediction.UpdateHealthValue(mixedFollow, "UNIT_HEALTH", "party5", 60, 100)
Equal(calls.detailed, 1, "mixed follow health did not refresh its exceptional clamp")
Equal(calls.directIncoming, 0, "mixed follow health refreshed incoming heals")

local mixedFollowStripe = MakeFrame("party6", {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = false,
    healAnchorMode = 2,
    absorbAnchorMode = 3,
    fullHealthAbsorbStripe = true,
})
Equal(mixedFollowStripe.overAbsorbGlowBar.value, 18,
    "mixed follow seed did not write the raw edge-gate payload")
local mixedStripeWrites = OperationCount(mixedFollowStripe.overAbsorbGlowBar, "SetValue")
calculatorAbsorb = 0
ResetCalls()
Prediction.UpdateHealthValue(mixedFollowStripe, "UNIT_HEALTH", "party6", 100, 100)
Equal(calls.detailed, 1, "mixed follow stripe skipped its display clamp refresh")
Equal(OperationCount(mixedFollowStripe.overAbsorbGlowBar, "SetValue"), mixedStripeWrites,
    "mixed follow health overwrote the raw edge-gate payload")
Equal(mixedFollowStripe.overAbsorbGlowBar.value, 18,
    "mixed follow full-health stripe lost its raw event payload")
Check(mixedFollowStripe.overAbsorbGlowBar.shown == true,
    "mixed follow full-health stripe did not reveal its native edge gate")
calculatorAbsorb = 18

-- UNIT_MAXHEALTH owns prediction-bar max invalidation. Once a health-aware
-- frame has been seeded, ordinary health ticks reuse that native max and a
-- disabled over-absorb overlay performs no threshold read.
local healthAwareConfig = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = false,
    healAnchorMode = 3,
    absorbAnchorMode = 3,
    overAbsorbOverlay = false,
}
local healthAware = MakeFrame("party1", healthAwareConfig)
local steadyMaxReads = healthMaxReads
local steadyHealWrites = OperationCount(healthAware.incomingHealBar, "SetValue")
local steadyAbsorbWrites = OperationCount(healthAware.absorbBar, "SetValue")
for _ = 1, 20 do
    Prediction.UpdateHealthValue(healthAware, "UNIT_HEALTH", "party1", 60, nil)
end
Equal(healthMaxReads, steadyMaxReads,
    "steady UNIT_HEALTH reread an unchanged prediction max")
Equal(OperationCount(healthAware.incomingHealBar, "SetValue"), steadyHealWrites,
    "steady UNIT_HEALTH rewrote an unchanged incoming-heal value")
Equal(OperationCount(healthAware.absorbBar, "SetValue"), steadyAbsorbWrites,
    "steady UNIT_HEALTH rewrote an unchanged absorb value")
Check(healthAware.overAbsorbGlow == nil,
    "disabled over-absorb overlay created runtime texture work")

-- Connection recovery is an explicit seed boundary; a stable online state is
-- then cached and does not repeat any prediction payload read.
ResetCalls()
Prediction.UpdateConnectionState(healthAware, "UNIT_CONNECTION", "party1", 60, 100)
Equal(calls.directIncoming, 1, "connection seed missed incoming heals")
Equal(calls.directAbsorb, 1, "connection seed missed absorbs")
local connectionReads = DirectReads()
Prediction.UpdateConnectionState(healthAware, "UNIT_CONNECTION", "party1", 60, 100)
Equal(DirectReads(), connectionReads, "stable connection repeated prediction reads")

-- Common follow/follow geometry is health-driven entirely by native anchors.
-- Health ticks must not refresh any prediction payload or calculator state.
ResetCalls()
local cachedIncoming = healthAware._msufPredictionIncoming
local cachedAbsorb = healthAware._msufPredictionAbsorb
Prediction.UpdateHealthValue(healthAware, "UNIT_HEALTH", "party1", 91, 100)
Equal(calls.detailed + calls.directIncoming + calls.directAbsorb + calls.directHealAbsorb, 0,
    "common follow health tick read prediction data")
Equal(healthAware._msufPredictionIncoming, cachedIncoming,
    "common health tick rewrote cached incoming heals")
Equal(healthAware._msufPredictionAbsorb, cachedAbsorb,
    "common health tick rewrote cached absorbs")

local secretMax = { __secret = true }
Prediction.Update(healthAware, "UNIT_MAXHEALTH", "party1", 60, secretMax)
local incomingMaxWrites = OperationCount(healthAware.incomingHealBar, "SetMinMaxValues")
local absorbMaxWrites = OperationCount(healthAware.absorbBar, "SetMinMaxValues")
for _ = 1, 20 do
    Prediction.UpdateHealthValue(healthAware, "UNIT_HEALTH", "party1", 60, secretMax)
end
Equal(OperationCount(healthAware.incomingHealBar, "SetMinMaxValues"), incomingMaxWrites,
    "steady secret health repeated the incoming-heal max setter")
Equal(OperationCount(healthAware.absorbBar, "SetMinMaxValues"), absorbMaxWrites,
    "steady secret health repeated the absorb max setter")

-- Enabled over-absorb still requires the numeric max and must preserve its
-- visual threshold behavior.
local overAbsorbConfig = {
    enabled = true,
    heal = false,
    absorb = true,
    healAbsorb = false,
    absorbAnchorMode = 2,
    overAbsorbOverlay = true,
}
local overAbsorb = MakeFrame("party2", overAbsorbConfig)
overAbsorb._msufPredictionAbsorb = 50
overAbsorb.hpBar._msufHealthPercentValue = 60
overAbsorb.hpBar._msufHealthPercentUnit = "party2"
local overlayMaxReads = healthMaxReads
local overlayHealthReads = healthReads
local overlayValueWrites = OperationCount(overAbsorb.overAbsorbGlowBar, "SetValue")
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", nil, nil)
Equal(healthMaxReads, overlayMaxReads,
    "enabled over-absorb overlay reread its already-seeded numeric max")
Equal(healthReads, overlayHealthReads,
    "percent health route repeated UnitHealth for the over-absorb threshold")
Check(overAbsorb.overAbsorbGlowBar and overAbsorb.overAbsorbGlowBar.shown == true,
    "enabled over-absorb overlay lost its threshold visual")
Equal(OperationCount(overAbsorb.overAbsorbGlowBar, "SetValue"), overlayValueWrites,
    "over-absorb health path rewrote the cached holder payload")
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", 100, 100)
Check(overAbsorb.overAbsorbGlowBar.shown == false,
    "partial-health over-absorb overlay bypassed the full-health stripe toggle")
Equal(OperationCount(overAbsorb.overAbsorbGlowBar, "SetValue"), overlayValueWrites,
    "hiding the over-absorb edge zeroed its holder payload")
overAbsorb._msufPredictionAbsorb = 0
local zeroOverlayMaxReads = healthMaxReads
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", 60, nil)
Equal(healthMaxReads, zeroOverlayMaxReads,
    "zero over-absorb value performed an unnecessary health-max read")
Equal(OperationCount(overAbsorb.overAbsorbGlowBar, "SetValue"), overlayValueWrites,
    "zero cached absorb was written from UNIT_HEALTH")
totalAbsorbValue = 0
Prediction.Update(overAbsorb, "UNIT_ABSORB_AMOUNT_CHANGED", "party2")
Equal(OperationCount(overAbsorb.overAbsorbGlowBar, "SetValue"), overlayValueWrites + 1,
    "absorb event did not own the zero holder write")
Equal(overAbsorb.overAbsorbGlowBar.value, 0,
    "zero absorb event did not clear the native holder payload")
Check(overAbsorb._msufPredictionPartialGlowHealthActive == nil,
    "zero absorb retained the partial-glow health follower")
totalAbsorbValue = 18
healthMaxValue = 120
local invalidatedOverlayMaxReads = healthMaxReads
Prediction.Update(overAbsorb, "UNIT_MAXHEALTH", "party2")
Equal(healthMaxReads, invalidatedOverlayMaxReads + 1,
    "UNIT_MAXHEALTH reused the previous prediction max")
Equal(overAbsorb._msufPredictionHealthMax, 120,
    "UNIT_MAXHEALTH did not replace the prediction max cache")
Check(overAbsorb._msufPredictionPartialGlowHealthActive == true,
    "plain positive absorb did not arm the partial-glow health follower")
healthMaxValue = 100
local protectedPartialAbsorb = { __secret = true }
totalAbsorbValue = protectedPartialAbsorb
Prediction.Update(overAbsorb, "UNIT_ABSORB_AMOUNT_CHANGED", "party2")
Equal(overAbsorb._msufPredictionAbsorb, protectedPartialAbsorb,
    "protected absorb event did not refresh the partial-glow payload")
Check(overAbsorb._msufPredictionPartialGlowHealthActive == nil,
    "protected absorb retained the unrenderable partial-glow health follower")
local secretOverlayMaxReads = healthMaxReads
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", { __secret = true }, nil)
Equal(healthMaxReads, secretOverlayMaxReads,
    "protected over-absorb state performed an unrenderable health-max read")
local protectedOverlayFast = Prediction.SelectEventUpdate(overAbsorb, overAbsorb.MSUFSpec, "UNIT_HEALTH")
Equal(protectedOverlayFast, Prediction.UpdateGlowHealthFast,
    "partial over-absorb did not compile its direct health selector")
local inactiveFastFrame = setmetatable({
    _msufPredictionFullHealthStripe = false,
    _msufPredictionPartialGlowHealthActive = false,
}, {
    __index = function(_, key)
        error("inactive partial-glow health path touched " .. tostring(key))
    end,
})
protectedOverlayFast(inactiveFastFrame, "UNIT_HEALTH", "party2", { __secret = true }, nil)
local protectedOverlayHealthReads = healthReads
local protectedOverlayPercentReads = healthPercentReads
local protectedOverlayShown = overAbsorb.overAbsorbGlowBar.shown
protectedOverlayFast(overAbsorb, "UNIT_HEALTH", "party2", { __secret = true }, nil)
Equal(healthReads, protectedOverlayHealthReads,
    "protected partial over-absorb fastpath performed an unrenderable health read")
Equal(healthPercentReads, protectedOverlayPercentReads,
    "stripe-off partial over-absorb fastpath read a full-health curve")
Equal(overAbsorb.overAbsorbGlowBar.shown, protectedOverlayShown,
    "protected partial over-absorb fastpath reprocessed the native glow")

-- The optional full-health stripe reuses the same Blizzard edge texture but
-- only subscribes to health-aware work while enabled. It must not inherit the
-- broader partial-health over-absorb threshold.
local fullHealthStripeConfig = {
    enabled = true,
    heal = false,
    absorb = true,
    healAbsorb = false,
    absorbAnchorMode = 2,
    overAbsorbOverlay = false,
    fullHealthAbsorbStripe = true,
}
local fullHealthStripe, fullHealthStripeSpec = MakeFrame("party3", fullHealthStripeConfig)
Equal(Prediction.SelectEventUpdate(fullHealthStripe, fullHealthStripeSpec, "UNIT_HEALTH"),
    Prediction.UpdateGlowHealthFast,
    "edge-only health plan did not compile its direct glow selector")
fullHealthStripe._msufPredictionAbsorb = 18
local stripeMaxReads = healthMaxReads
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, nil)
Equal(healthMaxReads, stripeMaxReads,
    "enabled full-health stripe reread its already-seeded numeric max")
Check(fullHealthStripe.overAbsorbGlowBar and fullHealthStripe.overAbsorbGlowBar.shown == true,
    "full-health absorb stripe did not show at maximum health")
Equal(fullHealthStripe.overAbsorbGlowBar:GetParent(), fullHealthStripe,
    "live full-health absorb stripe holder was not owned by the unitframe")
Equal(fullHealthStripe.overAbsorbGlow:GetParent(), fullHealthStripe.overAbsorbGlowBar,
    "live full-health absorb stripe texture was not owned by its status gate")
Check(fullHealthStripe.overAbsorbGlowBar:GetFrameLevel() > fullHealthStripe.hpBar:GetFrameLevel(),
    "live full-health absorb stripe did not render above the health bar")
local connectionHolderValue = fullHealthStripe.overAbsorbGlowBar.value
local connectionHolderWrites = OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue")
unitConnected = false
Prediction.UpdateConnectionState(fullHealthStripe, "UNIT_CONNECTION", "party3", 100, 100)
Check(fullHealthStripe.overAbsorbGlowBar.shown == false,
    "offline connection did not hide the absorb edge")
Equal(fullHealthStripe.overAbsorbGlowBar.value, connectionHolderValue,
    "offline connection zeroed the event-owned holder payload")
Equal(OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue"), connectionHolderWrites,
    "offline connection rewrote the event-owned holder payload")
unitConnected = true
Prediction.UpdateConnectionState(fullHealthStripe, "UNIT_CONNECTION", "party3", 100, 100)
Equal(OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue"), connectionHolderWrites + 1,
    "reconnect seed did not refresh the holder payload exactly once")
Check(fullHealthStripe.overAbsorbGlowBar.shown == true,
    "reconnect seed did not restore the full-health stripe")
local steadyGlowLevelReads = OperationCount(fullHealthStripe.hpBar, "GetFrameLevel")
local steadyGlowValueWrites = OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue")
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, 100)
Equal(OperationCount(fullHealthStripe.hpBar, "GetFrameLevel"), steadyGlowLevelReads,
    "steady full-health stripe repeated layout/frame-level work")
for _ = 1, 20 do
    Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, 100)
end
Equal(OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue"), steadyGlowValueWrites,
    "repeated full-health events rewrote the holder payload")
local protectedAbsorb = { __secret = true }
totalAbsorbValue = protectedAbsorb
Prediction.Update(fullHealthStripe, "UNIT_ABSORB_AMOUNT_CHANGED", "party3", 100, 100)
Equal(OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue"), steadyGlowValueWrites + 1,
    "absorb event did not write its protected holder payload exactly once")
Equal(fullHealthStripe.overAbsorbGlowBar.value, protectedAbsorb,
    "protected absorb event did not feed the native status gate")
local protectedValueWrites = OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue")
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, 100)
Equal(OperationCount(fullHealthStripe.overAbsorbGlowBar, "SetValue"), protectedValueWrites,
    "protected full-health event rewrote the holder payload")
Check(fullHealthStripe.overAbsorbGlowBar.shown == true,
    "protected absorb value was rejected by the live full-health stripe")
local protectedHealth = { __secret = true }
local protectedFullAlpha = { __secret = true }
healthPercentAlpha = protectedFullAlpha
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", protectedHealth, protectedHealth)
Equal(fullHealthStripe.overAbsorbGlowBar.alpha, protectedFullAlpha,
    "protected full-health gate was not passed directly to the live stripe")
local fullHealthStripeFast = Prediction.SelectEventUpdate(
    fullHealthStripe, fullHealthStripeSpec, "UNIT_HEALTH")
fullHealthStripe._msufPredictionOverAbsorbOverlay = true
fullHealthStripe.hpBar._msufHealthPercentValue = nil
fullHealthStripe.hpBar._msufHealthPercentUnit = nil
local protectedFastHealthReads = healthReads
local protectedFastMaxReads = healthMaxReads
local protectedFastPercentReads = healthPercentReads
fullHealthStripeFast(fullHealthStripe, "UNIT_HEALTH", "party3")
Equal(healthReads, protectedFastHealthReads,
    "protected warm full-health stripe reread UnitHealth")
Equal(healthMaxReads, protectedFastMaxReads,
    "protected warm full-health stripe reread UnitHealthMax")
Equal(healthPercentReads, protectedFastPercentReads + 1,
    "protected warm full-health stripe did not use exactly one native curve read")
Equal(fullHealthStripe.overAbsorbGlowBar.alpha, protectedFullAlpha,
    "protected warm full-health stripe lost its native alpha payload")
fullHealthStripe._msufPredictionOverAbsorbOverlay = false

-- A plain percent produced by Health resolves the same warm stripe without any
-- health API. Both exact-full and partial states stay cache-only.
fullHealthStripe.hpBar._msufHealthPercentUnit = "party3"
fullHealthStripe.hpBar._msufHealthPercentValue = 100
local plainFastHealthReads = healthReads
local plainFastMaxReads = healthMaxReads
local plainFastPercentReads = healthPercentReads
fullHealthStripeFast(fullHealthStripe, "UNIT_HEALTH", "party3")
Equal(healthReads, plainFastHealthReads, "plain warm stripe reread UnitHealth")
Equal(healthMaxReads, plainFastMaxReads, "plain warm stripe reread UnitHealthMax")
Equal(healthPercentReads, plainFastPercentReads,
    "plain warm stripe ignored Health's cached percent")
Check(fullHealthStripe.overAbsorbGlowBar.shown == true,
    "plain full-health percent did not reveal the warm stripe")
fullHealthStripe.hpBar._msufHealthPercentValue = 99
fullHealthStripeFast(fullHealthStripe, "UNIT_HEALTH", "party3")
Equal(healthReads, plainFastHealthReads, "plain partial stripe reread UnitHealth")
Equal(healthMaxReads, plainFastMaxReads, "plain partial stripe reread UnitHealthMax")
Equal(healthPercentReads, plainFastPercentReads,
    "plain partial stripe performed a native curve read")
Check(fullHealthStripe.overAbsorbGlowBar.shown == false,
    "plain partial percent leaked into the full-health-only stripe")

-- A missing Health cache falls back to exactly one curve read. A plain zero
-- result still stops before raw health/max recovery when partial overlay is off.
fullHealthStripe.hpBar._msufHealthPercentValue = nil
fullHealthStripe.hpBar._msufHealthPercentUnit = nil
healthPercentAlpha = 0
local missingFastHealthReads = healthReads
local missingFastMaxReads = healthMaxReads
local missingFastPercentReads = healthPercentReads
fullHealthStripeFast(fullHealthStripe, "UNIT_HEALTH", "party3")
Equal(healthReads, missingFastHealthReads, "missing-cache stripe reread UnitHealth")
Equal(healthMaxReads, missingFastMaxReads, "missing-cache stripe reread UnitHealthMax")
Equal(healthPercentReads, missingFastPercentReads + 1,
    "missing-cache stripe did not stop after its native curve read")
local cachedFullHealthReads = healthPercentReads
totalAbsorbValue = 18
Prediction.Update(fullHealthStripe, "UNIT_ABSORB_AMOUNT_CHANGED", "party3", protectedHealth, protectedHealth)
Equal(healthPercentReads, cachedFullHealthReads,
    "absorb-only data event recomputed an unchanged protected full-health gate")
healthPercentAlpha = 1
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 99, 100)
Check(fullHealthStripe.overAbsorbGlowBar.shown == false,
    "full-health absorb stripe leaked into partial health")

-- Follow-HP clips its raw display amount through geometry. The stripe reuses
-- the same event-backed (potentially protected) payload without a health read.
local followFullHealthConfig = {
    enabled = true,
    heal = false,
    absorb = true,
    healAbsorb = false,
    absorbAnchorMode = 3,
    overAbsorbOverlay = false,
    fullHealthAbsorbStripe = true,
}
local followFullHealth = MakeFrame("party4", followFullHealthConfig)
local protectedFollowAbsorb = { __secret = true }
totalAbsorbValue = protectedFollowAbsorb
local followRawColdReads = totalAbsorbReads
Prediction.Update(followFullHealth, "UNIT_ABSORB_AMOUNT_CHANGED", "party4")
Equal(totalAbsorbReads, followRawColdReads + 1,
    "follow-HP absorb event did not refresh its raw absorb cache")
local followRawReads = totalAbsorbReads
local followHolderWrites = OperationCount(followFullHealth.overAbsorbGlowBar, "SetValue")
Prediction.UpdateHealthValue(followFullHealth, "UNIT_HEALTH", "party4", 99, 100)
Equal(totalAbsorbReads, followRawReads,
    "follow-HP health path reread an unchanged raw absorb below full health")
Prediction.UpdateHealthValue(followFullHealth, "UNIT_HEALTH", "party4", 100, 100)
Equal(totalAbsorbReads, followRawReads,
    "follow-HP full-health stripe reread its event-backed raw absorb cache")
Equal(followFullHealth.overAbsorbGlowBar.value, protectedFollowAbsorb,
    "follow-HP stripe lost the event-backed raw absorb")
Equal(OperationCount(followFullHealth.overAbsorbGlowBar, "SetValue"), followHolderWrites,
    "follow-HP health events rewrote the holder payload")
Check(followFullHealth.overAbsorbGlowBar.shown == true,
    "follow-HP stripe rejected the protected real absorb at full health")
totalAbsorbValue = 18

local fullHealthStripeTestConfig = {
    enabled = true,
    test = true,
    heal = false,
    absorb = true,
    healAbsorb = false,
    absorbAnchorMode = 3,
    overAbsorbOverlay = false,
    fullHealthAbsorbStripe = true,
}
totalAbsorbValue = 0
local fullHealthStripeTest = MakeFrame("party5", fullHealthStripeTestConfig)
Check(fullHealthStripeTest.overAbsorbGlowBar and fullHealthStripeTest.overAbsorbGlowBar.shown == true,
    "prediction test mode did not show the full-health absorb stripe")
Equal(fullHealthStripeTest.overAbsorbGlowBar.value, 25,
    "follow-HP test mode replaced its synthetic stripe with the live absorb value")
totalAbsorbValue = 18

local function HasEvent(events, wanted)
    for index = 1, #events do
        if events[index] == wanted then return true end
    end
    return false
end

Check(not HasEvent(Prediction.GetEvents(healthAware, healthAware.MSUFSpec), "UNIT_HEALTH"),
    "common follow geometry retained calculator-era health-event work")
Check(HasEvent(Prediction.GetEvents(mixedFollow, mixedFollowSpec), "UNIT_HEALTH"),
    "mixed follow exception lost its health clamp subscription")

Check(not HasEvent(Prediction.GetEvents(absorbOnly, absorbOnlySpec), "UNIT_HEALTH"),
    "disabled full-health stripe added health-event work to absorb-only frames")
Check(HasEvent(Prediction.GetEvents(fullHealthStripe, fullHealthStripeSpec), "UNIT_HEALTH"),
    "enabled full-health stripe did not subscribe to its cold health path")

-- Core's coalesced identity route owns dependent UNIT_TARGET. Prediction must
-- not subscribe a second time or one parent/target burst performs two complete
-- calculator reads.
local dependentSpec = {
    key = "targettarget",
    unit = "targettarget",
    scope = "single",
    prediction = config,
}
local dependentFrame = { unit = "targettarget", MSUFUnitKey = "targettarget" }
local dependentEvents = Prediction.GetEvents(dependentFrame, dependentSpec)
Check(not HasEvent(dependentEvents, "UNIT_TARGET"),
    "dependent Prediction duplicated Core's UNIT_TARGET identity route")
Check(not HasEvent(Prediction.GetUnitlessEvents(dependentFrame, dependentSpec), "UNIT_TARGET"),
    "dependent prediction retained global UNIT_TARGET fanout")
Check(Prediction.GetEvents(dependentFrame, dependentSpec) == dependentEvents,
    "dependent event plan was allocated per query")
local focusTargetSpec = {
    key = "focustarget",
    unit = "focustarget",
    scope = "single",
    prediction = config,
}
Check(Prediction.GetEvents({ unit = "focustarget", MSUFUnitKey = "focustarget" }, focusTargetSpec) == dependentEvents,
    "equivalent dependent frames did not share their prebuilt event plan")
Check(not HasEvent(Prediction.GetEvents({ unit = "target", MSUFUnitKey = "target" }, {
    key = "target", unit = "target", scope = "single", prediction = config,
}), "UNIT_TARGET"), "ordinary target prediction inherited dependent UNIT_TARGET")
local groupUnitless = Prediction.GetUnitlessEvents({ unit = "party1", MSUFUnitKey = "party1" }, {
    key = "party", unit = "party1", scope = "group", prediction = config,
})
Check(HasEvent(groupUnitless, "PARTY_MEMBER_ENABLE") and HasEvent(groupUnitless, "PARTY_MEMBER_DISABLE"),
    "group lifecycle unitless events were lost")

-- Exercise the geometry caches through public updates. UNIT_MAXHEALTH carries
-- forceMax for status-bar values but must not force otherwise-current anchors.
local layoutConfig = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = true,
    healAnchorMode = 2,
    absorbAnchorMode = 4,
    healAbsorbAnchorMode = 3,
    healHeight = 6,
    healOffsetY = 1,
    absorbHeight = 7,
    absorbOffsetY = -2,
    healAbsorbHeight = 8,
    healAbsorbOffsetY = 3,
    overAbsorbOverlay = false,
}
local layoutFrame = MakeFrame("target", layoutConfig)
local absorbBar = layoutFrame.absorbBar
local healAbsorbBar = layoutFrame.healAbsorbBar
Equal(absorbBar._msufPredictionParent, layoutFrame, "mode-4 absorb parent cache")
Equal(absorbBar:GetParent(), layoutFrame, "mode-4 absorb actual parent")
Equal(layoutFrame.incomingHealBar._msufPredictionHeight, 6, "incoming-heal height was not compiled into layout")
Equal(absorbBar._msufPredictionHeight, 7, "positive absorb height was not compiled into layout")
Equal(absorbBar._msufPredictionOffsetY, -2, "positive absorb offset was not compiled into layout")
Equal(healAbsorbBar._msufHealAbsorbHeight, 8, "negative absorb height was not compiled into layout")
Equal(healAbsorbBar._msufHealAbsorbOffsetY, 3, "negative absorb offset was not compiled into layout")

local absorbAnchors = OperationCount(absorbBar, "ClearAllPoints")
local healAbsorbAnchors = OperationCount(healAbsorbBar, "ClearAllPoints")
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(OperationCount(absorbBar, "ClearAllPoints"), absorbAnchors,
    "forceMax incorrectly forced absorb geometry")
Equal(OperationCount(healAbsorbBar, "ClearAllPoints"), healAbsorbAnchors,
    "current heal-absorb geometry was rebuilt")

-- The live health-bar width, not a stale frame/spec width, owns prediction
-- geometry. Both overlay types must repair themselves on the next real event.
layoutFrame.hpBar.width = 137
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(absorbBar._msufPredictionWidth, 137, "absorb layout ignored live health width")
Equal(healAbsorbBar._msufHealAbsorbWidth, 137, "heal-absorb layout ignored live health width")

-- Replacing the follow texture invalidates the exact anchor target even when
-- mode, follow bar and width remain identical.
local replacementFollowTexture = NewRegion("Texture", layoutFrame.incomingHealBar)
layoutFrame.incomingHealBar.statusTexture = replacementFollowTexture
layoutFrame.incomingHealBar._msufPredictionStatusTexture = nil
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(absorbBar._msufPredictionAnchorTarget, replacementFollowTexture,
    "absorb layout retained a replaced follow texture")

-- Cached parent identity is insufficient: repair actual external reparenting.
local foreignParent = NewRegion("Frame")
absorbBar.parent = foreignParent
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(absorbBar:GetParent(), layoutFrame, "absorb layout did not repair actual parent drift")

-- Heal-absorb validates parent, layer and anchor before its cached fast exit.
healAbsorbBar.parent = foreignParent
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(healAbsorbBar:GetParent(), layoutFrame.hpBar, "heal-absorb did not repair actual parent drift")
Equal(healAbsorbBar._msufHealAbsorbParent, layoutFrame.hpBar, "heal-absorb parent cache")

local absorbLayerAnchors = OperationCount(absorbBar, "ClearAllPoints")
local healAbsorbLayerAnchors = OperationCount(healAbsorbBar, "ClearAllPoints")
layoutFrame.hpBar.frameLevel = 9
layoutFrame.frameStrata = "HIGH"
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(absorbBar.frameLevel, 11, "absorb frame level did not follow health level")
Equal(absorbBar.frameStrata, "HIGH", "absorb frame strata did not follow its frame")
Equal(OperationCount(absorbBar, "ClearAllPoints"), absorbLayerAnchors,
    "layer-only absorb repair rewrote geometry")
Equal(healAbsorbBar.frameLevel, 12, "heal-absorb frame level did not follow health level")
Equal(healAbsorbBar.frameStrata, "HIGH", "heal-absorb frame strata did not follow its frame")
Equal(OperationCount(healAbsorbBar, "ClearAllPoints"), healAbsorbLayerAnchors,
    "layer-only heal-absorb repair rewrote geometry")

-- Incoming-heal geometry normally runs on Apply. A pure layer change must
-- synchronize there without invalidating its already-correct anchors.
local incomingBar = layoutFrame.incomingHealBar
Prediction.Apply(layoutFrame, layoutFrame.MSUFSpec)
Equal(incomingBar.frameLevel, 10, "incoming-heal frame level did not follow health level")
Equal(incomingBar.frameStrata, "HIGH", "incoming-heal frame strata did not follow its frame")
local incomingLayerAnchors = OperationCount(incomingBar, "ClearAllPoints")
layoutFrame.hpBar.frameLevel = 10
layoutFrame.frameStrata = "DIALOG"
Prediction.Apply(layoutFrame, layoutFrame.MSUFSpec)
Equal(incomingBar.frameLevel, 11, "incoming-heal frame level did not resynchronize")
Equal(incomingBar.frameStrata, "DIALOG", "incoming-heal frame strata did not resynchronize")
Equal(OperationCount(incomingBar, "ClearAllPoints"), incomingLayerAnchors,
    "layer-only incoming-heal repair rewrote geometry")

local replacementHealthTexture = NewRegion("Texture", layoutFrame.hpBar)
layoutFrame.hpBar.statusTexture = replacementHealthTexture
layoutFrame.hpBar._msufPredictionStatusTexture = nil
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(healAbsorbBar._msufHealAbsorbAnchorTarget, replacementHealthTexture,
    "heal-absorb retained a replaced health texture")

layoutFrame._msufPredictionHpReverse = true
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(healAbsorbBar._msufHealAbsorbHpReverse, true, "heal-absorb reverse anchor cache")
Equal(healAbsorbBar.reverse, false, "heal-absorb reverse fill was not synchronized")

-- Once repaired, another forceMax event stays entirely on the geometry cache.
absorbAnchors = OperationCount(absorbBar, "ClearAllPoints")
healAbsorbAnchors = OperationCount(healAbsorbBar, "ClearAllPoints")
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(OperationCount(absorbBar, "ClearAllPoints"), absorbAnchors,
    "stable absorb geometry regressed after repair")
Equal(OperationCount(healAbsorbBar, "ClearAllPoints"), healAbsorbAnchors,
    "stable heal-absorb geometry regressed after repair")

-- A host without GetFrameLevel is legal in reduced harnesses. If hpBar also
-- yields no level, the guarded fallback remains deterministic and never calls
-- a missing frame method.
local savedFrameGetLevel = layoutFrame.GetFrameLevel
local savedHealthGetLevel = layoutFrame.hpBar.GetFrameLevel
layoutFrame.GetFrameLevel = false
layoutFrame.hpBar.GetFrameLevel = function() return nil end
absorbAnchors = OperationCount(absorbBar, "ClearAllPoints")
Prediction.Update(layoutFrame, "UNIT_MAXHEALTH", "target")
Equal(absorbBar.frameLevel, 3, "absorb missing-level fallback")
Equal(OperationCount(absorbBar, "ClearAllPoints"), absorbAnchors,
    "missing-level fallback rewrote absorb geometry")
layoutFrame.GetFrameLevel = savedFrameGetLevel
layoutFrame.hpBar.GetFrameLevel = savedHealthGetLevel

-- Category tests are independent: enabling only negative absorbs must hide the
-- positive and incoming-heal synthetic bars even if all live categories are configured.
local negativeTestFrame = MakeFrame("pet", {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = true,
    test = true,
    healTest = false,
    absorbTest = false,
    healAbsorbTest = true,
    healAnchorMode = 3,
    absorbAnchorMode = 2,
    healAbsorbAnchorMode = 2,
    healAbsorbHeight = 5,
    healAbsorbOffsetY = -4,
    overAbsorbOverlay = false,
})
Check(negativeTestFrame.incomingHealBar.shown == false, "negative test leaked incoming-heal bars")
Check(negativeTestFrame.absorbBar.shown == false, "negative test leaked positive absorb bars")
Check(negativeTestFrame.healAbsorbBar.shown == true, "negative test did not show heal absorbs")
Equal(negativeTestFrame.healAbsorbBar._msufPredictionMode, 2, "negative absorb anchor did not use its own mode")
Equal(negativeTestFrame.healAbsorbBar._msufPredictionHeight, 5, "negative absorb generic height cache")
Equal(negativeTestFrame.healAbsorbBar._msufPredictionOffsetY, -4, "negative absorb generic offset cache")

-- Integration proof: with the real Core, the normal dependent UNIT_TARGET
-- event is bound to its parent source and the compiled route receives the
-- dependent display unit. No Core special case or global registration is used.
local routedInCombat = false
_G.InCombatLockdown = function() return routedInCombat end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
local RoutedMSUF = { UF = { Metadata = { defaultApplyMask = { Prediction = true } } } }
_G.MSUF_NS = RoutedMSUF
local coreChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"))
coreChunk("MidnightSimpleUnitFrames", RoutedMSUF)
local worldEntryRegistration
local worldEntryRegisterCount = 0
local worldEntryUnregisterCount = 0
local scheduledWorldSeed
local scheduledDependentIdentity
_G.MSUF_EventBus_Register = function(event, key, callback, unitFilter, once)
    if key == "MSUF_UF_PREDICTION_WORLD_ENTRY" then
        worldEntryRegisterCount = worldEntryRegisterCount + 1
        worldEntryRegistration = {
            event = event,
            callback = callback,
            unitFilter = unitFilter,
            once = once,
        }
    end
    return true
end
_G.MSUF_EventBus_Unregister = function(event, key)
    if event == "PLAYER_ENTERING_WORLD" and key == "MSUF_UF_PREDICTION_WORLD_ENTRY" then
        worldEntryUnregisterCount = worldEntryUnregisterCount + 1
    end
end
_G.MSUF_ScheduleOnce = function(key, callback)
    if key == "UF_PREDICTION_WORLD_ENTRY" then
        scheduledWorldSeed = callback
    elseif type(key) == "function" and callback == key then
        scheduledDependentIdentity = callback
    end
end
local routedPredictionChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))
local driverCountBeforeRoutedPrediction = #drivers
routedPredictionChunk("MidnightSimpleUnitFrames", RoutedMSUF)
Equal(#drivers, driverCountBeforeRoutedPrediction,
    "prediction world-entry hook allocated a private event/update frame")
Check(worldEntryRegistration == nil,
    "disabled prediction registered a global world-entry handler at module load")
local RoutedUF = RoutedMSUF.UF

local function MakeRoutedDependent(unit)
    local routed = NewRegion("UnitFrame")
    routed.unit = unit
    routed.MSUFUnitKey = unit
    routed.unitKey = unit
    routed.hpBar = NewRegion("StatusBar", routed)
    routed.hpBar:SetStatusBarTexture("health")
    local routedSpec = {
        enabled = true,
        key = unit,
        unit = unit,
        scope = "single",
        width = 100,
        texture = "health",
        health = { reverse = false },
        prediction = config,
    }
    routed.MSUFSpec = routedSpec
    RoutedUF.AttachFrame(routed, { scope = "single" })
    local readsBeforeApply = DirectReads()
    RoutedUF.ApplyElementToFrame(routed, "Prediction", routedSpec)
    Equal(DirectReads(), readsBeforeApply + 3, "Prediction was not seeded during element apply")
    Equal(routed._msufPredictionAbsorb, 18, "apply seed did not populate current absorb state")
    Check(routed._msufPredictionCacheReady == true, "apply seed did not establish prediction cache")
    return routed
end

local routedTargetTarget = MakeRoutedDependent("targettarget")
Check(worldEntryRegistration ~= nil, "first active prediction frame did not register world-entry recovery")
Equal(worldEntryRegisterCount, 1, "first active prediction frame registered world-entry recovery more than once")
Equal(routedTargetTarget.registered.UNIT_TARGET, "target",
    "Core did not bind targettarget UNIT_TARGET to target")
Equal(routedTargetTarget._msufFrameUnitEventTargets.UNIT_TARGET, "targettarget",
    "Core lost targettarget route destination")
ResetCalls()
routedTargetTarget.PLAYER_TARGET_CHANGED(routedTargetTarget, "PLAYER_TARGET_CHANGED")
routedTargetTarget.UNIT_TARGET(routedTargetTarget, "UNIT_TARGET", "target")
Equal(DirectReads(), 0, "dependent identity ran before its coalesced flush")
Check(type(scheduledDependentIdentity) == "function",
    "targettarget identity did not schedule its coalesced refresh")
scheduledDependentIdentity()
scheduledDependentIdentity = nil
Equal(calls.directIncoming, 1, "targettarget identity did not coalesce to one prediction read")
Equal(calls.lastUnit, "targettarget", "compiled targettarget route leaked its source unit")

local routedFocusTarget = MakeRoutedDependent("focustarget")
Equal(worldEntryRegisterCount, 1, "second active prediction frame duplicated the shared world-entry handler")
Equal(routedFocusTarget.registered.UNIT_TARGET, "focus",
    "Core did not bind focustarget UNIT_TARGET to focus")
Equal(routedFocusTarget._msufFrameUnitEventTargets.UNIT_TARGET, "focustarget",
    "Core lost focustarget route destination")
ResetCalls()
routedFocusTarget.PLAYER_FOCUS_CHANGED(routedFocusTarget, "PLAYER_FOCUS_CHANGED")
routedFocusTarget.UNIT_TARGET(routedFocusTarget, "UNIT_TARGET", "focus")
Equal(DirectReads(), 0, "focus-target identity ran before its coalesced flush")
Check(type(scheduledDependentIdentity) == "function",
    "focustarget identity did not schedule its coalesced refresh")
scheduledDependentIdentity()
scheduledDependentIdentity = nil
Equal(calls.directIncoming, 1, "focustarget identity did not coalesce to one prediction read")
Equal(calls.lastUnit, "focustarget", "focus-target identity read the parent unit")

-- PLAYER_ENTERING_WORLD uses the shared EventBus and shared next-frame
-- scheduler. It reseeds already-active frames once unit data is authoritative,
-- without allocating a private frame or rebuilding their specs.
Check(worldEntryRegistration ~= nil, "prediction world-entry hook was not registered")
Equal(worldEntryRegistration.event, "PLAYER_ENTERING_WORLD", "prediction startup hook uses wrong event")
Check(worldEntryRegistration.unitFilter == nil, "prediction startup hook unexpectedly uses a unit filter")
Check(worldEntryRegistration.once ~= true, "prediction startup hook would miss later world transitions")
ResetCalls()
worldEntryRegistration.callback("PLAYER_ENTERING_WORLD")
Equal(DirectReads(), 0, "world-entry prediction seed did not defer to the next frame")
Check(type(scheduledWorldSeed) == "function", "world-entry prediction seed was not scheduled")
scheduledWorldSeed()
Equal(calls.directIncoming, 2, "world-entry seed did not refresh both attached prediction frames")
Equal(#drivers, driverCountBeforeRoutedPrediction,
    "world-entry prediction seed created a private OnUpdate driver")

routedInCombat = true
ResetCalls()
worldEntryRegistration.callback("PLAYER_ENTERING_WORLD")
scheduledWorldSeed()
Equal(DirectReads(), 0, "world-entry prediction seed performed protected combat work")
routedInCombat = false

local savedFocusTargetUnit = routedFocusTarget.MSUFUnitKey
routedFocusTarget.MSUFUnitKey = nil
ResetCalls()
worldEntryRegistration.callback("PLAYER_ENTERING_WORLD")
scheduledWorldSeed()
Equal(calls.directIncoming, 1, "world-entry seed did not skip a suspended nil-unit group frame")
routedFocusTarget.MSUFUnitKey = savedFocusTargetUnit

-- The shared lifecycle event exists only while at least one Prediction element
-- is active. Transient unit suspension above must not affect this ownership.
routedTargetTarget:DisableElement("Prediction")
Equal(worldEntryUnregisterCount, 0, "world-entry recovery unregistered while one prediction frame remained")
routedFocusTarget:DisableElement("Prediction")
Equal(worldEntryUnregisterCount, 1, "last disabled prediction frame retained world-entry recovery")

print("PASS prediction: startup seed/recovery, world-entry reseed, coalescing, exact routing, geometry caches")
