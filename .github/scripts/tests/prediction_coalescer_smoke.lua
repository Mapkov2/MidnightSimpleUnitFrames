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
function Methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Methods:SetValue(value) self.value = value end
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

local function ResetCalls()
    calls.detailed = 0
    calls.incoming = 0
    calls.absorb = 0
    calls.healAbsorb = 0
    calls.lastUnit = nil
    detailedHook = nil
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
_G.C_CurveUtil = {
    CreateCurve = function()
        return {
            SetType = function() end,
            AddPoint = function() end,
        }
    end,
}
_G.UnitHealthPercent = function() return healthPercentAlpha end
local unitExists = true
_G.UnitExists = function() return unitExists end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 60 end
local healthMaxReads = 0
_G.UnitHealthMax = function()
    healthMaxReads = healthMaxReads + 1
    return 100
end
_G.UnitGetIncomingHeals = function() return 12 end
local totalAbsorbValue = 18
local totalAbsorbReads = 0
_G.UnitGetTotalAbsorbs = function()
    totalAbsorbReads = totalAbsorbReads + 1
    return totalAbsorbValue
end
_G.UnitGetTotalHealAbsorbs = function() return 7 end

local function NewCalculator()
    return {
        SetIncomingHealClampMode = function() end,
        SetDamageAbsorbClampMode = function() end,
        SetHealAbsorbClampMode = function() end,
        SetHealAbsorbMode = function() end,
        ResetPredictedValues = function() end,
        GetIncomingHeals = function()
            calls.incoming = calls.incoming + 1
            return 20, 12
        end,
        GetDamageAbsorbs = function()
            calls.absorb = calls.absorb + 1
            return 18
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
    healAnchorMode = 2,
    absorbAnchorMode = 2,
    overAbsorbOverlay = false,
}

local function MakeFrame(unit, cfg)
    local frame = NewRegion("UnitFrame")
    frame.unit = unit
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

-- Repeated copies of one data event collapse to one calculator update and keep
-- the event-specific getter plan.
ResetCalls()
for _ = 1, 10 do queueHeal(frame, "UNIT_HEAL_PREDICTION", { __secret = true }) end
Equal(calls.detailed, 0, "prediction work ran before the render-frame flush")
FlushDriver()
Equal(calls.detailed, 1, "same-event burst was not coalesced")
Equal(calls.incoming, 1, "heal getter count")
Equal(calls.absorb, 0, "heal-only event refreshed absorbs")
Equal(calls.healAbsorb, 0, "heal-only event refreshed heal absorbs")
Equal(calls.lastUnit, "player", "secret event payload escaped into the queued API read")

-- All three events merge into one calculator read while preserving the union
-- of their component-specific getters.
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "wrong-unit")
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "wrong-unit")
queueHealAbsorb(frame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "wrong-unit")
FlushDriver()
Equal(calls.detailed, 1, "three-event burst used more than one calculator read")
Equal(calls.incoming, 1, "merged heal getter count")
Equal(calls.absorb, 1, "merged absorb getter count")
Equal(calls.healAbsorb, 1, "merged heal-absorb getter count")

-- Coalescing is per frame, never global across different units.
local second = MakeFrame("target", config)
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
queueHeal(second, "UNIT_HEAL_PREDICTION", "target")
FlushDriver()
Equal(calls.detailed, 2, "different unitframes were incorrectly merged")

-- A synchronous full/lifecycle refresh consumes a pending data update because
-- its full plan already covers every component.
ResetCalls()
queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
Prediction.Update(frame, "MSUF_FORCE_UPDATE", "player")
Equal(calls.detailed, 1, "synchronous full refresh did not run")
FlushDriver()
Equal(calls.detailed, 1, "consumed pending update ran a second time")

-- Apply/Disable invalidates data captured for the previous configuration.
ResetCalls()
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
Prediction.Disable(frame)
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
Equal(calls.detailed, 1, "valid absorb burst did not recover disabled prediction")
Equal(calls.absorb, 1, "disabled recovery burst was not coalesced")
Check(frame._msufPredictionDisabled ~= true, "valid absorb event left prediction disabled")
Equal(frame._msufPredictionAbsorb, 18, "disabled recovery did not populate absorb state")

-- Work raised while the active batch is draining is deferred to the next
-- driver invocation, preventing same-frame queue amplification.
ResetCalls()
local reentered = false
detailedHook = function()
    if not reentered then
        reentered = true
        queueHeal(frame, "UNIT_HEAL_PREDICTION", "player")
    end
end
queueAbsorb(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
FlushDriver()
Equal(calls.detailed, 1, "reentrant event extended the active batch")
detailedHook = nil
FlushDriver()
Equal(calls.detailed, 2, "reentrant event was not preserved for the next batch")

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
for _ = 1, 20 do
    Prediction.UpdateHealthValue(healthAware, "UNIT_HEALTH", "party1", 60, nil)
end
Equal(healthMaxReads, steadyMaxReads,
    "steady UNIT_HEALTH reread an unchanged prediction max")
Check(healthAware.overAbsorbGlow == nil,
    "disabled over-absorb overlay created runtime texture work")

-- Enabled over-absorb still requires the numeric max and must preserve its
-- visual threshold behavior.
local overAbsorbConfig = {
    enabled = true,
    heal = true,
    absorb = true,
    healAbsorb = false,
    healAnchorMode = 3,
    absorbAnchorMode = 3,
    overAbsorbOverlay = true,
}
local overAbsorb = MakeFrame("party2", overAbsorbConfig)
overAbsorb._msufPredictionAbsorb = 50
local overlayMaxReads = healthMaxReads
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", 60, nil)
Equal(healthMaxReads, overlayMaxReads + 1,
    "enabled over-absorb overlay skipped its numeric max read")
Check(overAbsorb.overAbsorbGlowBar and overAbsorb.overAbsorbGlowBar.shown == true,
    "enabled over-absorb overlay lost its threshold visual")
Prediction.UpdateHealthValue(overAbsorb, "UNIT_HEALTH", "party2", 100, 100)
Check(overAbsorb.overAbsorbGlowBar.shown == false,
    "partial-health over-absorb overlay bypassed the full-health stripe toggle")

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
fullHealthStripe._msufPredictionAbsorb = 18
local stripeMaxReads = healthMaxReads
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, nil)
Equal(healthMaxReads, stripeMaxReads + 1,
    "enabled full-health stripe skipped its numeric max read")
Check(fullHealthStripe.overAbsorbGlowBar and fullHealthStripe.overAbsorbGlowBar.shown == true,
    "full-health absorb stripe did not show at maximum health")
Equal(fullHealthStripe.overAbsorbGlowBar:GetParent(), fullHealthStripe,
    "live full-health absorb stripe holder was not owned by the unitframe")
Equal(fullHealthStripe.overAbsorbGlow:GetParent(), fullHealthStripe.overAbsorbGlowBar,
    "live full-health absorb stripe texture was not owned by its status gate")
Check(fullHealthStripe.overAbsorbGlowBar:GetFrameLevel() > fullHealthStripe.hpBar:GetFrameLevel(),
    "live full-health absorb stripe did not render above the health bar")
local protectedAbsorb = { __secret = true }
fullHealthStripe._msufPredictionAbsorb = protectedAbsorb
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 100, 100)
Equal(fullHealthStripe.overAbsorbGlowBar.value, protectedAbsorb,
    "full-health stripe did not feed a protected absorb value into its status gate")
Check(fullHealthStripe.overAbsorbGlowBar.shown == true,
    "protected absorb value was rejected by the live full-health stripe")
local protectedHealth = { __secret = true }
local protectedFullAlpha = { __secret = true }
healthPercentAlpha = protectedFullAlpha
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", protectedHealth, protectedHealth)
Equal(fullHealthStripe.overAbsorbGlowBar.alpha, protectedFullAlpha,
    "protected full-health gate was not passed directly to the live stripe")
healthPercentAlpha = 1
fullHealthStripe._msufPredictionAbsorb = 18
Prediction.UpdateHealthValue(fullHealthStripe, "UNIT_HEALTH", "party3", 99, 100)
Check(fullHealthStripe.overAbsorbGlowBar.shown == false,
    "full-health absorb stripe leaked into partial health")

-- Follow-HP clamps the displayed absorb to missing health, so its cached value
-- is zero at full HP. The stripe must use the real (potentially protected)
-- absorb value without changing the clamped display bar.
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
followFullHealth._msufPredictionAbsorb = 0
local followRawReads = totalAbsorbReads
Prediction.UpdateHealthValue(followFullHealth, "UNIT_HEALTH", "party4", 99, 100)
Equal(totalAbsorbReads, followRawReads,
    "follow-HP stripe queried the raw absorb amount below full health")
Prediction.UpdateHealthValue(followFullHealth, "UNIT_HEALTH", "party4", 100, 100)
Equal(totalAbsorbReads, followRawReads + 1,
    "follow-HP stripe did not query the raw absorb amount on its full-health cold path")
Equal(followFullHealth.overAbsorbGlowBar.value, protectedFollowAbsorb,
    "follow-HP stripe used the zero missing-health clamp instead of the real absorb")
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
local dependentFrame = { unit = "targettarget" }
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
Check(Prediction.GetEvents({ unit = "focustarget" }, focusTargetSpec) == dependentEvents,
    "equivalent dependent frames did not share their prebuilt event plan")
Check(not HasEvent(Prediction.GetEvents({ unit = "target" }, {
    key = "target", unit = "target", scope = "single", prediction = config,
}), "UNIT_TARGET"), "ordinary target prediction inherited dependent UNIT_TARGET")
local groupUnitless = Prediction.GetUnitlessEvents({ unit = "party1" }, {
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
local scheduledWorldSeed
local scheduledDependentIdentity
_G.MSUF_EventBus_Register = function(event, key, callback, unitFilter, once)
    if key == "MSUF_UF_PREDICTION_WORLD_ENTRY" then
        worldEntryRegistration = {
            event = event,
            callback = callback,
            unitFilter = unitFilter,
            once = once,
        }
    end
    return true
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
local RoutedUF = RoutedMSUF.UF

local function MakeRoutedDependent(unit)
    local routed = NewRegion("UnitFrame")
    routed.unit = unit
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
    local readsBeforeApply = calls.detailed
    RoutedUF.ApplyElementToFrame(routed, "Prediction", routedSpec)
    Equal(calls.detailed, readsBeforeApply + 1, "Prediction was not seeded during element apply")
    Equal(routed._msufPredictionAbsorb, 18, "apply seed did not populate current absorb state")
    Check(routed._msufPredictionCacheReady == true, "apply seed did not establish prediction cache")
    return routed
end

local routedTargetTarget = MakeRoutedDependent("targettarget")
Equal(routedTargetTarget.registered.UNIT_TARGET, "target",
    "Core did not bind targettarget UNIT_TARGET to target")
Equal(routedTargetTarget._msufFrameUnitEventTargets.UNIT_TARGET, "targettarget",
    "Core lost targettarget route destination")
ResetCalls()
routedTargetTarget.PLAYER_TARGET_CHANGED(routedTargetTarget, "PLAYER_TARGET_CHANGED")
routedTargetTarget.UNIT_TARGET(routedTargetTarget, "UNIT_TARGET", "target")
Equal(calls.detailed, 0, "dependent identity ran before its coalesced flush")
Check(type(scheduledDependentIdentity) == "function",
    "targettarget identity did not schedule its coalesced refresh")
scheduledDependentIdentity()
scheduledDependentIdentity = nil
Equal(calls.detailed, 1, "targettarget identity did not coalesce to one prediction read")
Equal(calls.lastUnit, "targettarget", "compiled targettarget route leaked its source unit")

local routedFocusTarget = MakeRoutedDependent("focustarget")
Equal(routedFocusTarget.registered.UNIT_TARGET, "focus",
    "Core did not bind focustarget UNIT_TARGET to focus")
Equal(routedFocusTarget._msufFrameUnitEventTargets.UNIT_TARGET, "focustarget",
    "Core lost focustarget route destination")
ResetCalls()
routedFocusTarget.PLAYER_FOCUS_CHANGED(routedFocusTarget, "PLAYER_FOCUS_CHANGED")
routedFocusTarget.UNIT_TARGET(routedFocusTarget, "UNIT_TARGET", "focus")
Equal(calls.detailed, 0, "focus-target identity ran before its coalesced flush")
Check(type(scheduledDependentIdentity) == "function",
    "focustarget identity did not schedule its coalesced refresh")
scheduledDependentIdentity()
scheduledDependentIdentity = nil
Equal(calls.detailed, 1, "focustarget identity did not coalesce to one prediction read")
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
Equal(calls.detailed, 0, "world-entry prediction seed did not defer to the next frame")
Check(type(scheduledWorldSeed) == "function", "world-entry prediction seed was not scheduled")
scheduledWorldSeed()
Equal(calls.detailed, 2, "world-entry seed did not refresh both attached prediction frames")
Equal(#drivers, driverCountBeforeRoutedPrediction,
    "world-entry prediction seed created a private OnUpdate driver")

routedInCombat = true
ResetCalls()
worldEntryRegistration.callback("PLAYER_ENTERING_WORLD")
scheduledWorldSeed()
Equal(calls.detailed, 0, "world-entry prediction seed performed protected combat work")
routedInCombat = false

local savedFocusTargetUnit = routedFocusTarget.unit
routedFocusTarget.unit = nil
ResetCalls()
worldEntryRegistration.callback("PLAYER_ENTERING_WORLD")
scheduledWorldSeed()
Equal(calls.detailed, 1, "world-entry seed did not skip a suspended nil-unit group frame")
routedFocusTarget.unit = savedFocusTargetUnit

print("PASS prediction: startup seed/recovery, world-entry reseed, coalescing, exact routing, geometry caches")
