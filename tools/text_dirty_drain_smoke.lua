_G = _G or _ENV

local function Exists(path)
  local handle = io.open(path, "r")
  if not handle then return false end
  handle:close()
  return true
end

local root = "MidnightSimpleUnitFrames/"
if not Exists(root .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua") then root = "" end

local timers = {}
local createFrameCalls = 0
local timerCancelCalls = 0
local healthPercentReads, powerReads, powerMaxReads = 0, 0, 0
_G.C_Timer = {
  NewTicker = function(delay, callback)
    assert(delay == 0.25, "value-text drain did not match EUI's fixed 250 ms cadence")
    local timer = { callback = callback, cancelled = false, repeating = true }
    function timer:Cancel()
      if not self.cancelled then
        self.cancelled = true
        timerCancelCalls = timerCancelCalls + 1
      end
    end
    timers[#timers + 1] = timer
    return timer
  end,
  NewTimer = function(delay, callback)
    error("value-text drain must prefer the reusable active-window ticker")
  end,
  After = function() error("value-text drain must prefer a cancellable timer") end,
}
_G.CreateFrame = function()
  createFrameCalls = createFrameCalls + 1
  error("value-text drain must not allocate an OnUpdate frame")
end
_G.UnitExists = function() return true end
_G.issecretvalue = function(value)
  return type(value) == "table" and value.secret == true
end

local UF = { elements = {}, attachedFrames = {} }
function UF.RegisterElement(name, element) UF.elements[name] = element end
function UF.FrameVisibleForEvent(frame)
  return frame and frame._msufCoreSpecEnabled ~= false and frame._msufCoreVisible ~= false
end

local Text = {
  tonumber = tonumber,
  type = type,
  format = string.format,
  floor = math.floor,
  max = math.max,
  abs = math.abs,
  GetTime = function() return 1 end,
  UnitHealth = function() return 50 end,
  UnitHealthMax = function() return 100 end,
  UnitPower = function() powerReads = powerReads + 1; return 40 end,
  UnitPowerMax = function() powerMaxReads = powerMaxReads + 1; return 100 end,
  UnitPowerType = function() return 0, "MANA" end,
  UnitHealthPercent = function() healthPercentReads = healthPercentReads + 1; return 50 end,
  UnitPowerPercent = function() return 40 end,
  SetShownCached = function(region, shown) if region then region.shown = shown == true end end,
  SetTextCached = function(region, value) if region then region.text = value end end,
  SetPowerTextColor = function() end,
  EMPTY_EVENTS = {},
  POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
  POWER_EVENTS_FREQUENT = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
}
local MSUF = {
  UF = UF,
  UFText = Text,
  Apply = {},
  Secrets = { UnitMissing = function() return false end },
}
_G.MSUF_NS = MSUF

local function Load(path)
  local chunk, err = loadfile(root .. path)
  assert(chunk, err)
  chunk("MidnightSimpleUnitFrames", MSUF)
end
Load("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")

local HealthText = assert(UF.elements.HealthText, "HealthText element missing")
local PowerText = assert(UF.elements.PowerText, "PowerText element missing")
local hot = assert(Text.RuntimeHotFunctions, "text runtime hot functions missing")
assert(type(hot.healthDirty) == "function" and type(hot.powerDirty) == "function",
  "compiled dirty markers are missing")

local function NewFrame(unit)
  local writes = { health = 0, power = 0 }
  local frame = {
    unit = unit,
    MSUFUnitKey = unit,
    MSUFSpec = { enabled = true },
    _msufCoreSpecEnabled = true,
    _msufCoreVisible = true,
    _msufActiveElements = { HealthText = true, PowerText = true },
  }
  frame._msufTextRuntime = {
    healthSlotCount = 1,
    healthValueSlotCount = 1,
    powerSlotCount = 1,
    healthDirty = hot.healthDirty,
    powerDirty = hot.powerDirty,
    healthHot = function(_, event, currentUnit, hp, hpMax)
      writes.health = writes.health + 1
      writes.healthEvent, writes.healthUnit = event, currentUnit
      writes.healthHP, writes.healthMax = hp, hpMax
    end,
    powerHot = function(_, event, currentUnit, power, powerMax, powerType, powerToken)
      writes.power = writes.power + 1
      writes.powerEvent, writes.powerUnit = event, currentUnit
      writes.powerValue, writes.powerMax = power, powerMax
      writes.powerType, writes.powerToken = powerType, powerToken
    end,
  }
  UF.attachedFrames[frame] = true
  return frame, writes
end

local spec = {
  showHealthText = true,
  showPowerText = true,
  power = { frequent = true },
  text = { healthLeft = "CURRENT", powerLeft = "CURRENT" },
}
local first, firstWrites = NewFrame("player")
local markHealth = HealthText.SelectEventUpdate(first, spec, "UNIT_HEALTH", HealthText.Update)
local markPower = PowerText.SelectEventUpdate(first, spec, "UNIT_POWER_FREQUENT", PowerText.Update)
assert(markHealth == hot.healthDirty and markPower == hot.powerDirty,
  "hot value events did not compile to the shared dirty markers")

local secret = { secret = true }
first._msufTextRuntime._dispatchHealthPercent = secret
first._msufTextRuntime._dispatchHealthPercentReady = true
first._msufTextRuntime._dispatchPowerPercent = secret
first._msufTextRuntime._dispatchPowerPercentReady = true
for _ = 1, 100 do
  markHealth(first, "UNIT_HEALTH", "player", secret, secret)
  markPower(first, "UNIT_POWER_FREQUENT", "player", secret, secret, secret, secret, false)
end
assert(#timers == 1, "one frame's Health/Power burst armed more than one shared timer")
assert(firstWrites.health == 0 and firstWrites.power == 0,
  "value text rendered before the shared drain")
assert(first._msufTextDirtyMask == 3 and first._msufTextDirtyQueued == true,
  "Health/Power dirty bits did not share one frame queue entry")
assert(first._msufTextPendingHealth == nil and first._msufTextPendingPower == nil,
  "dirty queue retained event value payloads")
assert(first._msufTextRuntime._dispatchHealthPercent == nil
    and first._msufTextRuntime._dispatchPowerPercent == nil,
  "dirty queue retained dispatch value payloads")

timers[1].callback()
assert(firstWrites.health == 1 and firstWrites.power == 1,
  "100 Health/Power events did not collapse to one writer call per kind")
assert(firstWrites.healthHP == nil and firstWrites.healthMax == nil
    and firstWrites.powerValue == nil and firstWrites.powerMax == nil
    and firstWrites.powerType == nil and firstWrites.powerToken == nil,
  "shared drain forwarded stale event payloads")
assert(first._msufTextDirtyMask == nil and first._msufTextDirtyQueued == nil,
  "shared drain did not return the frame to a clean idle state")

local second, secondWrites = NewFrame("target")
for _ = 1, 50 do
  markHealth(first, "UNIT_HEALTH", "player")
  HealthText.SelectEventUpdate(second, spec, "UNIT_HEALTH", HealthText.Update)(second, "UNIT_HEALTH", "target")
  markPower(first, "UNIT_POWER_FREQUENT", "player")
  PowerText.SelectEventUpdate(second, spec, "UNIT_POWER_FREQUENT", PowerText.Update)(second, "UNIT_POWER_FREQUENT", "target")
end
assert(#timers == 1, "continuous dirty work allocated a second timer")
timers[1].callback()
assert(firstWrites.health == 2 and firstWrites.power == 2
    and secondWrites.health == 1 and secondWrites.power == 1,
  "shared drain did not process each dirty frame exactly once")

-- A synchronous max/identity-style update supersedes a pending value tick.
markHealth(first, "UNIT_HEALTH", "player")
local timerIndex = #timers
local syncHealth = HealthText.SelectEventUpdate(first, spec, "UNIT_MAXHEALTH", HealthText.Update)
syncHealth(first, "UNIT_MAXHEALTH", "player")
assert(firstWrites.health == 3, "synchronous max-health update did not render immediately")
assert(timers[timerIndex].cancelled == false,
  "synchronous max-health update did not leave the shared combat ticker reusable")
timers[timerIndex].callback()
assert(firstWrites.health == 3, "superseded dirty health text rendered twice")

-- Absorb stays synchronous and distinct; disabling one kind preserves the
-- other bit, while disabling both leaves the already scheduled timer a no-op.
assert(HealthText.SelectEventUpdate(first, spec, "UNIT_ABSORB_AMOUNT_CHANGED", HealthText.Update) ~= markHealth,
  "absorb text was incorrectly moved into the value-text throttle")
assert(PowerText.SelectEventUpdate(first, spec, "UNIT_DISPLAYPOWER", PowerText.Update) == PowerText.Update,
  "power metadata update was incorrectly moved into the value-text throttle")
markHealth(first, "UNIT_HEALTH", "player")
markPower(first, "UNIT_POWER_FREQUENT", "player")
timerIndex = #timers
HealthText.Disable(first)
assert(timers[timerIndex].cancelled == false,
  "per-kind disable cancelled the timer while Power text was still dirty")
timers[timerIndex].callback()
assert(firstWrites.health == 3 and firstWrites.power == 3,
  "per-kind disable did not cancel Health while preserving dirty Power")

markHealth(first, "UNIT_HEALTH", "player")
markPower(first, "UNIT_POWER_FREQUENT", "player")
timerIndex = #timers
HealthText.Disable(first)
PowerText.Disable(first)
assert(timers[timerIndex].cancelled == false and first._msufTextDirtyQueued == true,
  "disabled value text allocated eager queue-removal bookkeeping")
timers[timerIndex].callback()
assert(firstWrites.health == 3 and firstWrites.power == 3,
  "disabled value text wrote from an already scheduled drain")
assert(first._msufTextDirtyQueued == nil,
  "disabled value text remained retained after the scheduled drain")
timers[timerIndex].callback()
assert(timers[timerIndex].cancelled == true and timerCancelCalls == 1,
  "empty value-text window did not stop its shared ticker")
assert(createFrameCalls == 0, "value-text batching allocated an OnUpdate frame")

local function NewPercentHealthFrame(unit, cachedPercent, cachedUnit)
  local frame, writes = NewFrame(unit)
  frame.hpBar = {
    _msufHealthPercentValue = cachedPercent,
    _msufHealthPercentUnit = cachedUnit,
  }
  local rt = frame._msufTextRuntime
  rt.healthNeedsPercent = true
  rt.healthHotFromPercent = function(_, event, currentUnit, pct)
    writes.health = writes.health + 1
    writes.healthEvent, writes.healthUnit = event, currentUnit
    writes.healthPercent = pct
  end
  rt.healthHot = function(_, event, currentUnit)
    writes.health = writes.health + 1
    writes.healthEvent, writes.healthUnit = event, currentUnit
    writes.healthPercent = Text.UnitHealthPercent(currentUnit)
  end
  return frame, writes
end

-- Health already owns the latest plain percentage used by the bar. The dirty
-- text drain must share that value instead of repeating UnitHealthPercent.
local cachedHealth, cachedHealthWrites = NewPercentHealthFrame("party1", 73, "party1")
healthPercentReads = 0
HealthText.SelectEventUpdate(cachedHealth, spec, "UNIT_HEALTH", HealthText.Update)(
  cachedHealth, "UNIT_HEALTH", "party1")
timerIndex = #timers
timers[timerIndex].callback()
assert(cachedHealthWrites.health == 1 and cachedHealthWrites.healthPercent == 73
    and healthPercentReads == 0,
  "deferred HealthText reread a safe percentage already owned by its Health bar")

local mismatchedHealth, mismatchedHealthWrites = NewPercentHealthFrame("party2", 74, "party1")
healthPercentReads = 0
HealthText.SelectEventUpdate(mismatchedHealth, spec, "UNIT_HEALTH", HealthText.Update)(
  mismatchedHealth, "UNIT_HEALTH", "party2")
timers[timerIndex].callback()
assert(mismatchedHealthWrites.health == 1 and mismatchedHealthWrites.healthPercent == 50
    and healthPercentReads == 1,
  "deferred HealthText reused a percentage cached for a different unit")

local protectedHealth, protectedHealthWrites = NewPercentHealthFrame("party3", secret, "party3")
healthPercentReads = 0
HealthText.SelectEventUpdate(protectedHealth, spec, "UNIT_HEALTH", HealthText.Update)(
  protectedHealth, "UNIT_HEALTH", "party3")
timers[timerIndex].callback()
assert(protectedHealthWrites.health == 1 and protectedHealthWrites.healthPercent == 50
    and healthPercentReads == 1,
  "deferred HealthText reused a restricted percentage cache")

local function NewPowerValueFrame(bar)
  local sink = { shown = true }
  function sink:IsShown() return self.shown end
  function sink:SetText(value) self.text = value end
  function sink:SetFormattedText(pattern, ...) self.text = string.format(pattern, ...) end
  local frame = {
    unit = "party1",
    MSUFUnitKey = "party1",
    MSUFSpec = { enabled = true },
    _msufCoreSpecEnabled = true,
    _msufCoreVisible = true,
    _msufActiveElements = { Power = true, PowerText = true },
    targetPowerBar = bar,
    powerTextLeft = sink,
  }
  local valueSpec = {
    scope = "group",
    showName = false,
    showHealthText = false,
    showPowerText = true,
    power = { enabled = true, frequent = true },
    text = { powerLeft = "CURMAX" },
  }
  Text.CompileTextRuntime(frame, valueSpec, valueSpec.text)
  UF.attachedFrames[frame] = true
  return frame, valueSpec
end

local function CachedBar(power, powerMax, unit, maxReady)
  return {
    _msufShown = true,
    _msufPowerValue = power,
    _msufPowerValueUnit = unit,
    _msufPowerMax = powerMax,
    _msufPowerMaxUnit = unit,
    _msufPowerMaxReady = maxReady,
  }
end

-- The Power element runs before its deferred text follower. Reuse its existing
-- non-secret cache instead of issuing the same native reads again at drain time.
local cachedFrame, cachedSpec = NewPowerValueFrame(CachedBar(73, 111, "party1", true))
powerReads, powerMaxReads = 0, 0
PowerText.SelectEventUpdate(cachedFrame, cachedSpec, "UNIT_POWER_FREQUENT", PowerText.Update)(
  cachedFrame, "UNIT_POWER_FREQUENT", "party1")
timerIndex = #timers
timers[timerIndex].callback()
assert(powerReads == 0 and powerMaxReads == 0,
  "deferred PowerText reread a safe current/max pair already owned by its Power bar")

local partialFrame, partialSpec = NewPowerValueFrame(CachedBar(74, nil, "party1", false))
powerReads, powerMaxReads = 0, 0
PowerText.SelectEventUpdate(partialFrame, partialSpec, "UNIT_POWER_FREQUENT", PowerText.Update)(
  partialFrame, "UNIT_POWER_FREQUENT", "party1")
timers[timerIndex].callback()
assert(powerReads == 0 and powerMaxReads == 1,
  "deferred PowerText did not reuse current independently before falling back for max")

local protectedFrame, protectedSpec = NewPowerValueFrame(
  CachedBar({ secret = true }, { secret = true }, "party1", true))
powerReads, powerMaxReads = 0, 0
PowerText.SelectEventUpdate(protectedFrame, protectedSpec, "UNIT_POWER_FREQUENT", PowerText.Update)(
  protectedFrame, "UNIT_POWER_FREQUENT", "party1")
timers[timerIndex].callback()
assert(powerReads == 1 and powerMaxReads == 1,
  "deferred PowerText reused a secret Power bar cache instead of the native fallback")

local syncFrame = NewPowerValueFrame(CachedBar(75, 112, "party1", true))
powerReads, powerMaxReads = 0, 0
PowerText.Update(syncFrame, "UNIT_MAXPOWER", "party1")
assert(powerReads == 1 and powerMaxReads == 1,
  "synchronous PowerText invalidation incorrectly reused the deferred-only bar cache")
timers[timerIndex].callback()

-- A clean active window survives one interval so the next combat burst reuses
-- the same ticker, then cancels after a complete empty cadence.
local idle, idleWrites = NewFrame("focus")
markHealth(idle, "UNIT_HEALTH", "focus")
timerIndex = #timers
timers[timerIndex].callback()
assert(idleWrites.health == 1 and timers[timerIndex].cancelled == false,
  "active-window ticker did not retain its one-interval reuse grace")
timers[timerIndex].callback()
assert(timers[timerIndex].cancelled == true,
  "active-window ticker did not stop after a full empty cadence")

print("text dirty drain smoke: ok")
