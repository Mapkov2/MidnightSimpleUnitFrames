-- Compound filters must not fall back to unrelated unit traffic. Only target
-- and pet targets may sample vitals when no direct event token matches.
local root = assert(arg[1]):gsub("\\", "/")
local flavor = arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, flavor)
local env = world.env
env.TotemFrame = false
env.PowerBarColor = {
  MANA = { r = 0.2, g = 0.4, b = 1 },
  ENERGY = { r = 1, g = 0.8, b = 0.1 },
}
local parents = { targettarget = "target", focustarget = "focus", pettarget = "pet" }
local states = {}
local reads = 0
env.issecretvalue = Secrets.IsSecret
local function Current(unit)
  reads = reads + 1
  local state = states[unit]
  if state then
    if state.opaque then return Secrets.New("number") end
    return state.hp
  end
  return unit == "player" and 1000 or 0
end
env.UnitHealth = Current
env.UnitHealthMax = function(unit)
  reads = reads + 1
  local state = states[unit]
  if state and state.opaque then return Secrets.New("number") end
  return state and state.maximum or 1000
end
local absorbReads = 0
env.UnitGetTotalAbsorbs = function(unit)
  absorbReads = absorbReads + 1
  return states[unit] and states[unit].absorb or 0
end
env.UnitGetIncomingHeals = function(unit) return states[unit] and states[unit].incoming or 0 end
env.UnitGetTotalHealAbsorbs = function(unit) return states[unit] and states[unit].healAbsorb or 0 end
env.UnitPower = function(unit)
  local state = states[unit]
  return state and state.power or 50
end
env.UnitPowerMax = function(unit)
  local state = states[unit]
  return state and state.powerMax or 100
end
local powerTypeReads = 0
env.UnitPowerType = function(unit)
  powerTypeReads = powerTypeReads + 1
  local state = states[unit]
  if state and state.opaquePowerType then
    local secret = state.opaquePowerType
    return secret == "token" and 3 or Secrets.New("number"),
      secret == "type" and "ENERGY" or Secrets.New("string")
  end
  if state and state.energy then return 3, "ENERGY" end
  return 0, "MANA"
end
env.UnitPowerPercent = function(unit, kind, _, curve)
  local state = states[unit]
  local powerType = state and state.energy and not state.opaquePowerType and 3 or 0
  assert(kind == powerType, "power percent read used stale power type")
  local value = env.UnitPower(unit) / env.UnitPowerMax(unit)
  return curve and value * 100 or value
end
world.widgets.Methods.SetFormattedText = function(self, format, ...)
  self.format, self.formatArguments = format, { ... }
end
env.UnitHealthPercent = function(unit, _, curve)
  local state = states[unit]
  if state and state.opaque then reads = reads + 1; return Secrets.New("number") end
  local value = Current(unit) / (state and state.maximum or 1000)
  return curve and value * 100 or value
end
env.UnitExists = function(unit) return not states[unit] or states[unit].exists end
env.UnitIsConnected = function() return true end
env.UnitIsDeadOrGhost = function(unit) return states[unit] ~= nil and states[unit].hp == 0 end
env.UnitIsDead = env.UnitIsDeadOrGhost
env.UnitIsGhost = function() return false end
env.UnitName = function(unit) return unit, nil end
local aliases = {}
env.UnitGUID = function(unit)
  local alias = aliases[unit]
  if alias == "opaque" then return Secrets.New("string") end
  return (alias or unit) .. "-guid"
end

local filters, nativeFilters = {}, {}
local create = env.CreateFrame
env.CreateFrame = function(...)
  local frame = create(...)
  filters[frame] = {}
  local register, unregister, unregisterAll = frame.RegisterEvent, frame.UnregisterEvent, frame.UnregisterAllEvents
  frame.RegisterEvent = function(self, event)
    filters[self][event] = true
    return register(self, event)
  end
  frame.RegisterUnitEvent = function(self, event, unit)
    -- Model the native fallback for a chained unit filter. Direct tokens filter normally.
    filters[self][event] = parents[unit] and not nativeFilters[unit] and true or unit
    return register(self, event)
  end
  frame.IsEventRegistered = function(self, event)
    local filter = filters[self][event]
    return filter ~= nil, type(filter) == "string" and filter or nil
  end
  frame.UnregisterEvent = function(self, event)
    filters[self][event] = nil
    return unregister(self, event)
  end
  frame.UnregisterAllEvents = function(self)
    filters[self] = {}
    return unregisterAll(self)
  end
  return frame
end
local setValue = world.widgets.Methods.SetValue
world.widgets.Methods.SetValue = function(self, value, interpolation)
  self._testInterpolation = interpolation
  return setValue(self, value, interpolation)
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and (failure.file .. ": " .. failure.message))
local UF = world.core.UF
local config = UF.Config
local db = config.GetDB()
db.general.barMode = "unified"
db.general.barBgColorMode = "custom"
db.general.barBgFillMode = "missing"
config.Refresh()

local function Apply(frame, enabled)
  local unit = frame.MSUFUnitKey
  config.GetUnitDB(unit).enabled = enabled
  config.RefreshUnit(unit)
  UF.ApplySpec(frame, config.GetSpec(unit), "MSUF_APPLY", true)
end

local function NewFrame(unit)
  states[unit] = { hp = 870, maximum = 1000, exists = true }
  local conf = config.GetUnitDB(unit)
  conf.smoothFill, conf.chunkedFill, conf.reverseFillBars = true, false, true
  local frame = env.CreateFrame("Button", nil, env.UIParent)
  frame.MSUFUnitKey = unit
  UF.frames[unit] = frame
  UF.AttachFrame(frame, { scope = "single" })
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  return frame
end

local function Fraction(frame)
  local low, high = frame.hpBar:GetMinMaxValues()
  return (frame.hpBar:GetValue() - low) / (high - low)
end

local function CheckFraction(frame, expected, label)
  local fill = Fraction(frame)
  assert(math.abs(fill - expected) < 0.00001, frame.MSUFUnitKey .. " " .. label .. ": fill=" .. tostring(fill))
end

local function Deliver(frame, event, unit, ...)
  local filter = filters[frame][event]
  if filter == true or filter == unit then
    frame.scripts.OnEvent(frame, event, unit, ...)
  end
end

local function Tick(elapsed)
  local driver = UF.driver
  if not driver then return end
  local ticker = driver.ticker
  if ticker and not ticker:IsCancelled() then
    ticker.testElapsed = (ticker.testElapsed or 0) + elapsed
    if ticker.testElapsed + 1e-9 >= ticker.delay then
      ticker.testElapsed = ticker.testElapsed - ticker.delay
      ticker.callback(ticker)
    end
  elseif driver.scripts and driver.scripts.OnUpdate then
    driver.scripts.OnUpdate(driver, elapsed)
  end
end

-- The shared widget model does not invoke the visibility hooks itself.
local function Visibility(frame, shown)
  frame.shown = shown
  frame.scripts[shown and "OnShow" or "OnHide"](frame)
end

local function FlushQueuedUnitUpdates()
  local scheduler = world.core.Scheduler.frame
  if scheduler.scripts.OnUpdate then scheduler.scripts.OnUpdate(scheduler) end
  world.widgets:RunTimers()
end

local function CheckIdentity(frame, event, source)
  local state = states[frame.MSUFUnitKey]
  local newHP = state.hp == 300 and 600 or 300
  state.hp = newHP
  Deliver(frame, event, source)
  FlushQueuedUnitUpdates()
  CheckFraction(frame, newHP / state.maximum, event .. " refreshed without waiting for a poll")
  assert(frame.hpBar._testInterpolation == nil, event .. " identity refresh must snap")
end

local function Exercise(unit)
  local parent = parents[unit]
  local frame = NewFrame(unit)
  local state = states[unit]
  CheckFraction(frame, 0.87, "initial own target")
  for _, foreign in ipairs({ "player", "deadnpc", "pet", "player", "deadnpc" }) do
    Deliver(frame, "UNIT_HEALTH", foreign)
    CheckFraction(frame, 0.87, "foreign health " .. foreign)
    Deliver(frame, "UNIT_MAXHEALTH", foreign)
    CheckFraction(frame, 0.87, "foreign max health " .. foreign)
  end
  assert(filters[frame].UNIT_HEALTH == nil and filters[frame].UNIT_MAXHEALTH == nil,
    unit .. " subscribed to global health traffic")
  assert(filters[frame].UNIT_TARGET == parent, unit .. " target-change notification lost")
  CheckIdentity(frame, "UNIT_TARGET", parent)
  if unit == "pettarget" then
    assert(filters[frame].UNIT_PET == "player", "pet replacement must be player-filtered")
    CheckIdentity(frame, "UNIT_PET", "player")
  else
    local event = parent == "target" and "PLAYER_TARGET_CHANGED" or "PLAYER_FOCUS_CHANGED"
    assert(filters[frame][event] == true, event .. " lifecycle notification lost")
    CheckIdentity(frame, event)
  end

  state.hp = 430
  reads = 0
  Tick(0.19)
  assert(reads == 0, "poll ran before its interval")
  Tick(0.02)
  CheckFraction(frame, 0.43, "health changes without a unit event")
  assert(frame.hpBar._msufSmoothInterp ~= nil, "smooth setting was not applied")
  assert(frame.hpBar._testInterpolation == frame.hpBar._msufSmoothInterp, unit .. " poll skipped Smooth Fill")
  state.hp, state.maximum = 1400, 2000
  Tick(0.2)
  CheckFraction(frame, 0.7, "new target with different max health")
  state.hp = 0
  Tick(0.2)
  CheckFraction(frame, 0, "pet target died")
  state.hp = 1000
  Tick(0.2)
  CheckFraction(frame, 0.5, "new living target")
  state.exists = false
  reads = 0
  Tick(0.2)
  assert(reads == 0, unit .. " queried health while absent")
  state.exists = true
  frame._msufPreviewAnimUnitRestore = {}
  reads = 0
  Tick(0.2)
  assert(reads == 0, "poll overwrote animated preview")
  frame._msufPreviewAnimUnitRestore = nil
  world.core.ExportPublic("MSUF_PreviewTestMode", true)
  Tick(0.2)
  assert(reads == 0, "poll overwrote unit preview")
  world.core.ExportPublic("MSUF_PreviewTestMode", false)
  state.hp = 800
  Tick(0.2)
  CheckFraction(frame, 0.4, "preview release resumes without driver rebuild")
  state.opaque = true
  local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua", { strict = true })
  Tick(0.2)
  assert(#stop() == 0, "poll inspected a secret health value")
  assert(Secrets.IsSecret(frame.hpBar:GetValue()), "opaque health did not reach native bar sink")
  state.opaque = false
  Tick(0.2)
  CheckFraction(frame, 0.4, "opaque-to-readable transition")
  for _, mode in ipairs({ "CURRENT", "CURMAX", "PERCENT", "CURPERCENT" }) do
    config.GetUnitDB(unit).textRight = mode
    Apply(frame, true)
    state.hp, state.maximum = 780, 1200
    Tick(0.2)
    CheckFraction(frame, 0.65, mode .. " uses current maximum")
    state.hp, state.maximum = 800, 2000
    Tick(0.2)
    CheckFraction(frame, 0.4, mode .. " target switch")
  end
  for _, mode in ipairs({ "CURRENT", "CURMAX", "PERCENT", "CURPERCENT" }) do
    for _, animation in ipairs({ "smooth", "chunked", "plain" }) do
      local conf = config.GetUnitDB(unit)
      conf.textRight = mode
      conf.smoothFill, conf.chunkedFill = animation == "smooth", animation == "chunked"
      Apply(frame, true)
      state.hp, state.maximum = 1800, 2000
      UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
      assert(frame.hpBar._testInterpolation == nil, "identity refresh must snap")
      state.hp = 800
      Tick(0.2)
      CheckFraction(frame, 0.4, mode .. " " .. animation)
      assert(frame._msufHealthBackgroundNeedsValue == true, "missing-health fallback not active")
      assert(frame.healthBackgroundBar._testInterpolation == frame.hpBar._msufSmoothInterp,
        mode .. ": missing-health background animation disagrees with fill")
      local trail = frame.healthLossTrail
      if animation == "smooth" then
        assert(frame.hpBar._testInterpolation == frame.hpBar._msufSmoothInterp and frame.hpBar._testInterpolation ~= nil,
          mode .. ": Smooth Fill interpolation missing")
      elseif animation == "chunked" then
        assert(trail and trail._msufLossAnimating == true, mode .. ": chunked loss did not animate")
        assert(trail:GetValue() > frame.hpBar:GetValue(), mode .. ": old health snapshot lost")
      else
        assert(frame.hpBar._testInterpolation == nil, "plain fill unexpectedly animated")
        assert(not trail or trail._msufLossAnimating ~= true, "disabled loss trail still animates")
      end
      state.opaque = true
      local finish = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
        { strict = true })
      Tick(0.2)
      assert(#finish() == 0, "animation inspected secret health")
      assert(Secrets.IsSecret(frame.hpBar:GetValue()), "animation lost secret health")
      if animation == "chunked" then assert(trail._msufLossAnimating == true, "secret chunk lost animation") end
      state.opaque = false
      Tick(0.2)
    end
  end
  -- Suppressing the invalid unit filter also moves configured power to the
  -- poll. The poll must retain interpolation and refresh max and power type.
  local conf = config.GetUnitDB(unit)
  conf.showPowerBar, conf.showPowerText = true, true
  conf.powerTextRight = "CURMAX"
  for _, mode in ipairs({ "smooth", "chunked" }) do
    conf.powerSmoothFill, conf.powerChunkedFill = mode == "smooth", mode == "chunked"
    state.power, state.powerMax, state.energy = 90, 100, false
    Apply(frame, true)
    UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
    local bar = assert(frame.targetPowerBar, "enabled dependent power bar missing")
    assert(bar._testInterpolation == nil, "power identity refresh must snap")
    state.power, state.powerMax, state.energy = 80, 200, true
    Tick(0.2)
    local low, high = bar:GetMinMaxValues()
    assert(math.abs((bar:GetValue() - low) / (high - low) - 0.4) < 0.00001,
      unit .. " power poll did not refresh current and maximum")
    assert(bar._msufPowerType == 3 and bar._msufPowerToken == "ENERGY", "power poll kept stale power type")
    if mode == "smooth" then
      assert(bar._testInterpolation ~= nil and bar._testInterpolation == bar._msufSmoothInterp,
        unit .. " power poll skipped Smooth Fill")
    else
      local trail = bar._msufLossTrail
      assert(trail and trail._msufLossAnimating == true and trail:GetValue() > bar:GetValue(),
        unit .. " power poll lost chunked loss snapshot")
    end
  end
  -- With the bar off, PowerText owns the maximum and display type cache.
  conf.showPowerBar = false
  conf.fontOverride, conf.powerTextColorByType = true, true
  state.power, state.powerMax, state.energy = 90, 100, false
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  assert(not frame.targetPowerBar:IsShown(), "text-only power fixture still shows a bar")
  assert(frame.powerTextRight:IsShown(), "text-only power fixture does not show its value")
  assert(frame._msufTextPowerMax == 100 and frame._msufTextPowerType == 0, "text-only power fixture was not seeded")
  state.power, state.powerMax, state.energy = 80, 200, true
  Tick(0.2)
  assert(frame._msufTextPowerMax == 200, unit .. " text-only power poll kept stale maximum")
  assert(frame._msufTextPowerType == 3 and frame._msufTextPowerToken == "ENERGY",
    unit .. " text-only power poll kept stale power type")
  conf.showPowerBar, conf.showPowerText = false, false
  Apply(frame, true)

  local pollCount = 0
  local vitals, leanIdentity = UF.RunDependentVitals, UF.RunLeanIdentity
  UF.RunDependentVitals = function(...)
    pollCount = pollCount + 1
    return vitals(...)
  end
  UF.RunLeanIdentity = function() error("vitals fallback ran the full identity refresh") end
  UF.SyncRuntimeDriver()
  for _ = 1, 100 do Tick(0.01) end
  assert(pollCount >= 4 and pollCount <= 5, "poll exceeded five refreshes per second")
  UF.RunDependentVitals, UF.RunLeanIdentity = vitals, leanIdentity

  local driver = UF.driver
  local ticker = assert(driver.ticker, "visible dependent must use a native interval ticker")
  assert(not (driver.scripts and driver.scripts.OnUpdate), "dependent must not wake on every rendered frame")
  assert(ticker.delay == 0.2, "native ticker changed the health update interval")
  Visibility(frame, false)
  assert(ticker:IsCancelled() and not driver.ticker, "hidden dependent retained its poll")
  reads = 0
  Tick(1)
  assert(reads == 0, "hidden dependent queried health")
  Visibility(frame, true)
  assert(driver.ticker and driver.ticker ~= ticker, "shown dependent did not resume")
  CheckFraction(frame, 0.4, "reshow")
  reads = 0
  ticker.callback(ticker)
  assert(reads == 0, "a retired ticker reached the new display lifetime")
  Apply(frame, false)
  assert(not driver.ticker, "disabled dependent retained its poll")
  return frame
end

local function CheckPredictionEvents(frame)
  local unit = frame.MSUFUnitKey
  local state = states[unit]
  local conf = config.GetUnitDB(unit)
  conf.enabled, conf.healPredEnabled, conf.healAbsorbEnabled = true, true, true
  state.hp, state.maximum, state.incoming, state.healAbsorb = 500, 1000, 50, 20
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")

  local bar = assert(frame.incomingHealBar, "prediction fixture did not construct the heal bar")
  assert(bar:GetValue() == 50 and frame.healAbsorbBar:GetValue() == 20, "prediction fixture did not render")
  state.hp, state.maximum, state.incoming = 600, 1200, 65
  Tick(0.2)
  CheckFraction(frame, 0.50, "fallback health with prediction configured")
  local _, maximum = bar:GetMinMaxValues()
  assert(maximum == 1000 and bar:GetValue() == 50, "fallback polled healing prediction")

  aliases[unit] = "player"
  CheckIdentity(frame, "UNIT_TARGET", "target")
  assert(filters[frame].UNIT_HEAL_PREDICTION == "player", "prediction lost its filtered event")
  state.incoming = 70
  Deliver(frame, "UNIT_HEAL_PREDICTION", "player")
  assert(frame._msufPredictionQueued == true, "prediction event was not dispatched")
  for _, widget in ipairs(world.widgets.frames) do
    local callback = widget.scripts.OnUpdate
    if callback and widget:IsShown() and debug.getinfo(callback, "S").source:find("MSUF_UF_Prediction_Queue.lua", 1, true) then
      callback(widget)
    end
  end
  assert(bar:GetValue() == 70, "event-driven prediction did not flush")

  local animation = world.core.PreviewAnimation
  animation.enabled = true
  animation.source = "preview"
  assert(animation.ApplyUnitFrame(frame, 1, unit), "preview fixture could not animate the dependent")
  _, maximum = bar:GetMinMaxValues()
  assert(maximum == 1000000, "preview fixture did not replace the native range")
  state.maximum, state.incoming = 1500, 80
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  animation.SetEnabled(false)
  assert(bar:IsShown() and bar._msufShown == true, "restored heal bar lost its follow anchor")
  CheckIdentity(frame, "UNIT_TARGET", "target")
  _, maximum = bar:GetMinMaxValues()
  assert(maximum == 1500 and bar:GetValue() == 80, "next identity event did not restore live prediction")

  aliases[unit] = nil
  conf.healPredEnabled, conf.healAbsorbEnabled = nil, nil
  state.incoming, state.healAbsorb = nil, nil
  Apply(frame, false)
end

if world.core.Client.SupportsUnit("focustarget") then
  local unit = "focustarget"
  nativeFilters[unit] = true
  local frame = NewFrame(unit)
  assert(not (UF.driver and UF.driver.ticker), "focus target acquired a periodic driver")
  assert(filters[frame].UNIT_HEALTH == unit, "focus target lost a verified native health filter")
  states[unit].hp = 340
  Tick(1)
  Deliver(frame, "UNIT_HEALTH", "player")
  CheckFraction(frame, 0.87, "idle or foreign focus event")
  Deliver(frame, "UNIT_HEALTH", unit)
  CheckFraction(frame, 0.34, "filtered focus health event")
  CheckIdentity(frame, "UNIT_TARGET", "focus")
  CheckIdentity(frame, "PLAYER_FOCUS_CHANGED")
  nativeFilters[unit] = nil
  UF.RefreshFrameUnitEventRouting(frame)
  assert(filters[frame].UNIT_HEALTH == nil, "focus accepted an unfiltered health subscription")
  assert(not (UF.driver and UF.driver.ticker), "unsupported focus filter installed a ticker")
  Apply(frame, false)
end

local active = {}
for _, unit in ipairs({ "targettarget", "pettarget" }) do
  if world.core.Client.SupportsUnit(unit) then active[#active + 1] = Exercise(unit) end
end

-- Different HP values catch cross-frame paints. A hidden, previewed or disabled
-- frame must not stop the same driver's updates for its visible siblings.
local driver = UF.driver
for index, frame in ipairs(active) do
  local state = states[frame.MSUFUnitKey]
  state.hp, state.maximum = 870, 1000
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  state.hp = index * 100
end
assert(UF.driver == driver and driver.ticker, "dependents must share the existing driver")
local sharedTicker = driver.ticker
UF.SyncRuntimeDriver()
assert(driver.ticker == sharedTicker, "a live driver was restarted without a visibility edge")
Tick(0.2)
for index, frame in ipairs(active) do CheckFraction(frame, index / 10, "shared driver") end

local first, second = active[1], active[2]
assert(second, "expected two supported dependent frames")
local firstState, secondState = states[first.MSUFUnitKey], states[second.MSUFUnitKey]
first._msufPreviewAnimUnitRestore = {}
firstState.hp, secondState.hp = 400, 500
Tick(0.2)
CheckFraction(first, 0.1, "preview on one frame")
CheckFraction(second, 0.5, "sibling updates during preview")
first._msufPreviewAnimUnitRestore = nil
Visibility(first, false)
secondState.hp = 600
Tick(0.2)
CheckFraction(first, 0.1, "hidden while sibling is active")
CheckFraction(second, 0.6, "sibling updates while first is hidden")
Visibility(first, true)
CheckFraction(first, 0.4, "shown while sibling is active")
Apply(first, false)
secondState.hp = 700
Tick(0.2)
CheckFraction(second, 0.7, "sibling updates while first is disabled")
for index = 2, #active do Apply(active[index], false) end
assert(not driver.ticker and sharedTicker:IsCancelled(), "driver stayed active with all dependents disabled")

local function CheckAliases()
  aliases.targettarget, aliases.pettarget = "player", "target"
  Apply(first, true)
  Apply(second, true)
  assert(not driver.ticker, "direct event tokens retained the fallback")
  assert(filters[first].UNIT_HEALTH == "player" and filters[second].UNIT_HEALTH == "target",
    "aliases were not subscribed through native unit filters")
  firstState.hp, secondState.hp = 230, 450
  Deliver(first, "UNIT_HEALTH", "player")
  Deliver(second, "UNIT_HEALTH", "target")
  CheckFraction(first, 0.23, "player alias health")
  CheckFraction(second, 0.45, "target alias health")

  local conf = config.GetUnitDB("pettarget")
  conf.showPowerBar, conf.showPowerText = true, true
  Apply(second, true)
  secondState.power, secondState.powerMax, secondState.energy = 30, 100, false
  local bar = assert(second.targetPowerBar)
  Deliver(second, "UNIT_DISPLAYPOWER", "target")
  Deliver(second, "UNIT_POWER_UPDATE", "target", "MANA")
  local low, high = bar:GetMinMaxValues()
  assert(math.abs((bar:GetValue() - low) / (high - low) - 0.3) < 0.00001, "target alias power event was lost")
  assert(not driver.ticker, "changing the power display rearmed the alias fallback")

  aliases.pettarget = nil
  local dispatch = second._msufDispatchToken
  Deliver(second, "PLAYER_TARGET_CHANGED")
  assert(second._msufDispatchToken == dispatch + 1 and not second._msufDispatchActive,
    "retargeting the event filter opened a nested dispatch")
  assert(driver.ticker and filters[second].UNIT_HEALTH == nil, "changed target left a stale alias")
  secondState.hp = 610
  Tick(0.2)
  CheckFraction(second, 0.61, "fallback after target alias lost")
  aliases.pettarget = "target"
  Deliver(second, "PLAYER_TARGET_CHANGED")
  assert(not driver.ticker and filters[second].UNIT_HEALTH == "target", "target alias did not recover")

  local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua", { strict = true })
  aliases.targettarget = "opaque"
  Deliver(first, "UNIT_TARGET", "target")
  assert(not filters[first].UNIT_HEALTH, "parent change kept listening to the old alias before the identity refresh")
  CheckIdentity(first, "UNIT_TARGET", "target")
  assert(driver.ticker and filters[first].UNIT_HEALTH == nil, "opaque identity was trusted as an alias")
  assert(#stop() == 0, "alias resolution inspected a secret identity")
  aliases.targettarget = "player"
  CheckIdentity(first, "UNIT_TARGET", "target")
  assert(not driver.ticker and filters[first].UNIT_HEALTH == "player", "player alias did not recover")

  Visibility(first, false)
  assert(not filters[first].UNIT_HEALTH and not driver.ticker, "hidden alias retained its health subscription")
  Visibility(first, true)
  assert(filters[first].UNIT_HEALTH == "player" and not driver.ticker, "reshown alias started a fallback")

  aliases.targettarget = "pet"
  Deliver(first, "UNIT_PET", "player")
  assert(filters[first].UNIT_HEALTH == "pet" and not driver.ticker, "pet replacement did not retarget the filter")
  if world.core.Client.SupportsUnit("focus") then
    aliases.targettarget = "focus"
    Deliver(first, "PLAYER_FOCUS_CHANGED")
    assert(filters[first].UNIT_HEALTH == "focus" and not driver.ticker, "focus change did not retarget the filter")
  end
  aliases.targettarget, aliases.pettarget = nil, nil
  conf.showPowerBar, conf.showPowerText = false, false
  Apply(first, false)
  Apply(second, false)
end

CheckAliases()

local function CheckPetAndTargetUpdates(petTarget)
  local originalPet = UF.frames.pet
  local originalPetState, originalTargetState = states.pet, states.pettarget
  local originalPetAlias, originalTargetAlias = aliases.pet, aliases.pettarget
  local settingKeys = {
    "enabled", "smoothFill", "chunkedFill", "reverseFillBars",
    "showPowerBar", "showPowerText", "powerHideMissingResource",
  }
  local savedSettings = {}
  for _, unit in ipairs({ "pet", "pettarget" }) do
    local conf = config.GetUnitDB(unit)
    local snapshot = {}
    for i, key in ipairs(settingKeys) do snapshot[i] = conf[key] end
    savedSettings[unit] = snapshot
  end

  local pet = NewFrame("pet")
  local petState = states.pet
  local targetState = { hp = 800, maximum = 1000, power = 50, powerMax = 100, exists = true }
  states.pettarget = targetState

  local function SendToBoth(event, unit, ...)
    Deliver(pet, event, unit, ...)
    Deliver(petTarget, event, unit, ...)
    FlushQueuedUnitUpdates()
  end

  local function CheckVitals(frame, health, power, label)
    CheckFraction(frame, health, label)
    local bar = assert(frame.targetPowerBar, frame.MSUFUnitKey .. " missing power bar")
    local low, high = bar:GetMinMaxValues()
    local fill = (bar:GetValue() - low) / (high - low)
    assert(math.abs(fill - power) < 0.00001,
      frame.MSUFUnitKey .. " " .. label .. ": power fill=" .. tostring(fill))
  end

  aliases.pettarget = "target"
  petState.hp, petState.power, petState.powerMax = 700, 60, 100
  for _, frame in ipairs({ pet, petTarget }) do
    local conf = config.GetUnitDB(frame.MSUFUnitKey)
    conf.showPowerBar, conf.showPowerText, conf.powerHideMissingResource = true, false, false
    Apply(frame, true)
  end
  SendToBoth("UNIT_PET", "player")
  CheckVitals(pet, 0.7, 0.6, "pet seed")
  CheckVitals(petTarget, 0.8, 0.5, "pet target seed")
  assert(not driver.ticker, "pet and directly matched pet target started a timer")

  petState.hp, petState.power = 610, 20
  targetState.hp, targetState.power = 430, 30
  SendToBoth("UNIT_HEALTH", "pet")
  CheckVitals(pet, 0.61, 0.6, "filtered pet health event")
  CheckVitals(petTarget, 0.8, 0.5, "pet health event left the target alone")
  SendToBoth("UNIT_POWER_UPDATE", "pet", "MANA")
  CheckVitals(pet, 0.61, 0.2, "filtered pet power event")
  CheckVitals(petTarget, 0.8, 0.5, "pet power event left the target alone")
  SendToBoth("UNIT_HEALTH", "target")
  CheckVitals(petTarget, 0.43, 0.5, "filtered pet-target health event")
  CheckVitals(pet, 0.61, 0.2, "target health event left the pet alone")
  SendToBoth("UNIT_POWER_UPDATE", "target", "MANA")
  CheckVitals(petTarget, 0.43, 0.3, "filtered pet-target power event")
  CheckVitals(pet, 0.61, 0.2, "target power event left the pet alone")

  aliases.pettarget = nil
  targetState.hp, targetState.power = 380, 40
  SendToBoth("UNIT_TARGET", "pet")
  CheckVitals(petTarget, 0.38, 0.4, "pet target changed")
  assert(driver.ticker and driver.petTarget == petTarget
    and not filters[petTarget].UNIT_HEALTH and not filters[petTarget].UNIT_POWER_UPDATE,
    "unmatched pet target did not switch to the vitals fallback")
  petState.hp, petState.power = 570, 35
  targetState.hp, targetState.power = 340, 27
  Tick(0.2)
  CheckVitals(petTarget, 0.34, 0.27, "pet-target fallback")
  CheckVitals(pet, 0.61, 0.2, "pet kept its event-driven values during the target fallback")

  aliases.pet, aliases.pettarget = "replacement-pet", "target"
  petState.hp, petState.maximum, petState.power, petState.powerMax = 200, 500, 50, 200
  targetState.hp, targetState.maximum, targetState.power, targetState.powerMax = 360, 600, 36, 90
  petState.energy = true
  SendToBoth("UNIT_PET", "player")
  CheckVitals(pet, 0.4, 0.25, "replacement pet")
  CheckVitals(petTarget, 0.6, 0.4, "replacement pet target")
  assert(pet.targetPowerBar._msufPowerType == 3 and not driver.ticker,
    "pet replacement did not seed the new resource and stop the target fallback")

  -- The widget harness needs explicit unit-watch visibility transitions.
  petState.exists, targetState.exists = false, false
  Visibility(petTarget, false)
  Visibility(pet, false)
  assert(not filters[pet].UNIT_HEALTH and not filters[pet].UNIT_POWER_UPDATE
    and not filters[petTarget].UNIT_HEALTH and not filters[petTarget].UNIT_POWER_UPDATE,
    "dismissed pet frames kept their vitals subscriptions")
  petState.exists, targetState.exists = true, true
  petState.hp, petState.power = 275, 120
  targetState.hp, targetState.power = 480, 45
  Visibility(pet, true)
  Visibility(petTarget, true)
  CheckVitals(pet, 0.55, 0.6, "pet visible again")
  CheckVitals(petTarget, 0.8, 0.5, "pet target visible again")
  assert(filters[pet].UNIT_HEALTH == "pet" and filters[pet].UNIT_POWER_UPDATE == "pet"
    and filters[petTarget].UNIT_HEALTH == "target" and filters[petTarget].UNIT_POWER_UPDATE == "target",
    "returning pet frames did not restore both direct event filters")
  assert(not driver.ticker, "returning pet frames kept the fallback despite their event filters")

  Apply(petTarget, false)
  Apply(pet, false)
  UF.DetachFrame(pet)
  UF.frames.pet = originalPet
  states.pet, states.pettarget = originalPetState, originalTargetState
  aliases.pet, aliases.pettarget = originalPetAlias, originalTargetAlias
  for unit, snapshot in pairs(savedSettings) do
    local conf = config.GetUnitDB(unit)
    for i, key in ipairs(settingKeys) do conf[key] = snapshot[i] end
    config.RefreshUnit(unit)
  end
end

CheckPetAndTargetUpdates(second)

local unitConfig = config.GetUnitDB("targettarget")
local originalShowName = unitConfig.showName
unitConfig.showName = true
Apply(first, true)
assert(driver.ticker, "fixture did not start the fallback for a visible health bar")
first:DisableElement("Health")
first:DisableElement("HealthText")
first:DisableElement("Power")
first:DisableElement("PowerText")
assert(first:IsElementEnabled("NameText") and not driver.ticker, "name-only frame retained a periodic driver")
reads = 0
Tick(1)
assert(reads == 0, "name-only frame read health while idle")
unitConfig.showName = originalShowName
Apply(first, false)

local function CheckNumericTextFallback(frame)
  local unit = frame.MSUFUnitKey
  local state = states[unit]
  local conf = config.GetUnitDB(unit)
  conf.textLeft, conf.textCenter, conf.textRight = "CURRENT", "NONE", "ABSORB"
  state.hp, state.maximum, state.absorb = 500, 1000, 50
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  local rt = frame._msufTextRuntime
  assert(rt.healthValueSlotCount == 1 and rt._lastAbsorbTextValue == 50, "mixed health and absorb text fixture was not seeded")

  state.hp, state.absorb = 380, 70
  absorbReads = 0
  for _ = 1, 10 do Tick(0.2) end
  CheckFraction(frame, 0.38, "health with an absorb text slot")
  assert(absorbReads == 0 and rt._lastAbsorbTextValue == 50, "vitals fallback sampled absorb text")

  aliases[unit] = "player"
  CheckIdentity(frame, "UNIT_TARGET", "target")
  assert(filters[frame].UNIT_ABSORB_AMOUNT_CHANGED == "player", "absorb text lost its native filter")
  state.absorb = 95
  Deliver(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
  assert(rt._lastAbsorbTextValue == 95, "absorb text did not update through its event")
  aliases[unit] = nil

  conf.textLeft = "NONE"
  Apply(frame, true)
  assert(frame:IsElementEnabled("HealthText") and frame._msufTextRuntime.healthValueSlotCount == 0,
    "absorb-only text fixture contains a health value")
  frame:DisableElement("Health")
  frame:DisableElement("Power")
  frame:DisableElement("PowerText")
  assert(not UF.driver.ticker, "absorb-only text armed the vitals fallback")
  Apply(frame, false)
end

local function CheckFallbackColorWork(frame)
  local unit = frame.MSUFUnitKey
  local state = states[unit]
  local conf = config.GetUnitDB(unit)
  local originalPowerColorMode = db.general.powerColorMode
  conf.healthColorMode, db.general.powerColorMode = "class", "class"
  conf.showPowerBar, conf.showPowerText, conf.powerHideMissingResource = true, false, false
  state.hp, state.maximum, state.power, state.powerMax = 500, 1000, 30, 100
  Apply(frame, true)
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  assert(frame._msufHealthRuntimeColorEnabled == true and frame.targetPowerBar._msufR ~= nil,
    "fallback color fixture did not seed both bars")

  local healthColorCalls, powerColorCalls = 0, 0
  debug.sethook(function()
    local info = debug.getinfo(2, "nS")
    if info.name == "ApplyRuntimeColor" and info.source:find("MSUF_UF_Elements_Health.lua", 1, true) then
      healthColorCalls = healthColorCalls + 1
    elseif info.name == "ResolveDynamicPowerColor" and info.source:find("MSUF_UF_Elements_Power.lua", 1, true) then
      powerColorCalls = powerColorCalls + 1
    end
  end, "c")
  for _ = 1, 10 do Tick(0.2) end
  debug.sethook()
  assert(healthColorCalls == 0 and powerColorCalls == 0,
    "alive value fallback repainted identity color: " .. healthColorCalls .. " health, " .. powerColorCalls .. " power")

  state.hp = 0
  Tick(0.2)
  assert(frame._msufHealthStatusGone == true, "health fallback missed the zero-HP color")
  state.hp = 200
  Tick(0.2)
  assert(frame._msufHealthStatusGone ~= true, "health fallback failed to restore the live color")

  state.opaque, state.hp = true, 0
  Tick(0.2)
  assert(frame._msufHealthStatusGone == true, "health fallback missed death behind opaque HP")
  state.hp = 200
  Tick(0.2)
  assert(frame._msufHealthStatusGone ~= true, "health fallback missed revival behind opaque HP")
  state.opaque = false

  db.general.powerColorMode = "power"
  local originalOverrides = db.general.powerColorOverrides
  db.general.powerColorOverrides = { MANA = { 0.2, 0.4, 1 }, ENERGY = { 1, 0.8, 0.1 } }
  Apply(frame, true)
  local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua",
    { strict = true })
  for _, opaque in ipairs({ true, "type", "token" }) do
    state.opaquePowerType = opaque
    powerTypeReads = 0
    Tick(0.2)
    assert(powerTypeReads == 1, "power fallback read opaque type " .. powerTypeReads .. " times")
    assert(frame.targetPowerBar._msufR == (opaque == true and 0.2 or 1), "power fallback lost readable partial tint")
  end
  assert(#stop() == 0, "power fallback inspected opaque metadata")
  state.opaquePowerType = nil
  db.general.powerColorOverrides = originalOverrides
  conf.healthColorMode, db.general.powerColorMode = nil, originalPowerColorMode
  conf.showPowerBar = false
  Apply(frame, false)
end

if flavor == "Forever" then
  CheckPredictionEvents(first)
  CheckNumericTextFallback(first)
  CheckFallbackColorWork(first)
end

print("pet_target_health_smoke: " .. flavor .. " passed")
