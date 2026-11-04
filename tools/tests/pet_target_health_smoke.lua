-- Dependent targets must never consume unrelated unit events. Native chained-token
-- registration may fall back to a unitless subscription (oUF/events.lua).
local root = assert(arg[1]):gsub("\\", "/")
local flavor = arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, flavor)
local env = world.env
env.TotemFrame = false
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
env.UnitPower = function(unit)
  local state = states[unit]
  return state and state.power or 50
end
env.UnitPowerMax = function(unit)
  local state = states[unit]
  return state and state.powerMax or 100
end
env.UnitPowerType = function(unit)
  local state = states[unit]
  if state and state.energy then return 3, "ENERGY" end
  return 0, "MANA"
end
env.UnitPowerPercent = function(unit, kind, _, curve)
  assert(kind == env.UnitPowerType(unit), "power percent read used stale power type")
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
env.UnitGUID = function(unit) return unit .. "-guid" end

local filters = {}
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
    filters[self][event] = parents[unit] and true or unit
    return register(self, event)
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

local function Deliver(frame, event, unit)
  local filter = filters[frame][event]
  if filter == true or filter == unit then
    frame.scripts.OnEvent(frame, event, unit)
  end
end

local function Tick(elapsed)
  local driver = UF.driver
  if driver and driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, elapsed) end
end

-- The shared widget model does not invoke the visibility hooks itself.
local function Visibility(frame, shown)
  frame.shown = shown
  frame.scripts[shown and "OnShow" or "OnHide"](frame)
end

local function CheckIdentity(frame, event, source)
  local state = states[frame.MSUFUnitKey]
  local newHP = state.hp == 300 and 600 or 300
  state.hp = newHP
  Deliver(frame, event, source)
  local scheduler = world.core.Scheduler.frame
  if scheduler.scripts.OnUpdate then scheduler.scripts.OnUpdate(scheduler) end
  world.widgets:RunTimers()
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
  local leanIdentity = UF.RunLeanIdentity
  UF.RunLeanIdentity = function(...)
    pollCount = pollCount + 1
    return leanIdentity(...)
  end
  UF.SyncRuntimeDriver()
  for _ = 1, 100 do Tick(0.01) end
  assert(pollCount >= 4 and pollCount <= 5, "poll exceeded five refreshes per second")
  UF.RunLeanIdentity = leanIdentity

  Visibility(frame, false)
  assert(not UF.driver.scripts.OnUpdate, "hidden dependent retained its poll")
  reads = 0
  Tick(1)
  assert(reads == 0, "hidden dependent queried health")
  Visibility(frame, true)
  assert(UF.driver.scripts.OnUpdate, "shown dependent did not resume")
  CheckFraction(frame, 0.4, "reshow")
  Apply(frame, false)
  assert(not UF.driver.scripts.OnUpdate, "disabled dependent retained its poll")
  return frame
end

local active = {}
for _, unit in ipairs({ "targettarget", "focustarget", "pettarget" }) do
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
assert(UF.driver == driver and driver.scripts.OnUpdate, "dependents must share the existing driver")
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
assert(not driver.scripts.OnUpdate, "driver stayed active with all dependents disabled")

print("pet_target_health_smoke: " .. flavor .. " passed (" .. #active .. " dependent targets)")
