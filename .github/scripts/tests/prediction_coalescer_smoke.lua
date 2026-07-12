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

local function NewRegion(kind, parent)
    return setmetatable({
        kind = kind,
        parent = parent,
        scripts = {},
        shown = true,
        width = 100,
        frameLevel = 1,
        frameStrata = "MEDIUM",
    }, { __index = Methods })
end

function Methods:SetScript(script, callback) self.scripts[script] = callback end
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
function Methods:SetAllPoints() end
function Methods:ClearAllPoints() end
function Methods:SetPoint() end
function Methods:SetWidth(width) self.width = width end
function Methods:GetWidth() return self.width end
function Methods:SetParent(parent) self.parent = parent end
function Methods:GetParent() return self.parent end
function Methods:SetFrameLevel(level) self.frameLevel = level end
function Methods:GetFrameLevel() return self.frameLevel end
function Methods:SetFrameStrata(strata) self.frameStrata = strata end
function Methods:GetFrameStrata() return self.frameStrata end
function Methods:SetReverseFill(reverse) self.reverse = reverse == true end
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

print("PASS prediction coalescer: merged data events, per-frame isolation, sync/disable cancellation, next-batch reentry, absorb-only semantics")
