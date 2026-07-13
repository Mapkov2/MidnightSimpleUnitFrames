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
}
_G.issecretvalue = function(value) return type(value) == "table" and value.__secret == true end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 60 end
_G.UnitHealthMax = function() return 100 end
_G.UnitGetIncomingHeals = function() return 12 end
_G.UnitGetTotalAbsorbs = function() return 18 end
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

local function HasEvent(events, wanted)
    for index = 1, #events do
        if events[index] == wanted then return true end
    end
    return false
end

-- Dependent frames must expose UNIT_TARGET as a normal unit event. The core
-- can then bind it to the exact parent unit (target/focus) instead of turning
-- every UNIT_TARGET notification into global fanout.
local dependentSpec = {
    key = "targettarget",
    unit = "targettarget",
    scope = "single",
    prediction = config,
}
local dependentFrame = { unit = "targettarget" }
local dependentEvents = Prediction.GetEvents(dependentFrame, dependentSpec)
Check(HasEvent(dependentEvents, "UNIT_TARGET"), "dependent prediction UNIT_TARGET was not a normal unit event")
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
    overAbsorbOverlay = false,
}
local layoutFrame = MakeFrame("target", layoutConfig)
local absorbBar = layoutFrame.absorbBar
local healAbsorbBar = layoutFrame.healAbsorbBar
Equal(absorbBar._msufPredictionParent, layoutFrame, "mode-4 absorb parent cache")
Equal(absorbBar:GetParent(), layoutFrame, "mode-4 absorb actual parent")

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

-- Integration proof: with the real Core, the normal dependent UNIT_TARGET
-- event is bound to its parent source and the compiled route receives the
-- dependent display unit. No Core special case or global registration is used.
_G.InCombatLockdown = function() return false end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
local RoutedMSUF = { UF = { Metadata = { defaultApplyMask = { Prediction = true } } } }
_G.MSUF_NS = RoutedMSUF
local coreChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"))
coreChunk("MidnightSimpleUnitFrames", RoutedMSUF)
local routedPredictionChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))
routedPredictionChunk("MidnightSimpleUnitFrames", RoutedMSUF)
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
    RoutedUF.ApplyElementToFrame(routed, "Prediction", routedSpec)
    return routed
end

local routedTargetTarget = MakeRoutedDependent("targettarget")
Equal(routedTargetTarget.registered.UNIT_TARGET, "target",
    "Core did not bind targettarget UNIT_TARGET to target")
Equal(routedTargetTarget._msufFrameUnitEventTargets.UNIT_TARGET, "targettarget",
    "Core lost targettarget route destination")
ResetCalls()
routedTargetTarget.UNIT_TARGET(routedTargetTarget, "UNIT_TARGET", "target")
Equal(calls.lastUnit, "targettarget", "compiled targettarget route leaked its source unit")

local routedFocusTarget = MakeRoutedDependent("focustarget")
Equal(routedFocusTarget.registered.UNIT_TARGET, "focus",
    "Core did not bind focustarget UNIT_TARGET to focus")
Equal(routedFocusTarget._msufFrameUnitEventTargets.UNIT_TARGET, "focustarget",
    "Core lost focustarget route destination")

print("PASS prediction: coalescing, exact dependent routing, live geometry caches, parent/layer repair, absorb-only semantics")
