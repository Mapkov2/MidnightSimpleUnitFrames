local function fail(message)
  error("boss range update rate smoke: " .. tostring(message), 0)
end

local function expect(condition, message)
  if not condition then fail(message) end
end

local function near(actual, expected, epsilon)
  return math.abs((actual or 0) - expected) <= (epsilon or 0.0001)
end

local repoRoot = arg and arg[1] or "."
local runtimePath = repoRoot .. "/MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_RangeFade.lua"
local menuPath = repoRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua"
local windowPath = repoRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua"
local configPath = repoRoot .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua"
local auraPath = repoRoot .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
local corePath = repoRoot .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"

local now = 0
local timers = {}
local afterCallbacks = {}
local driverFrames = {}
local rangeCalls = 0
local focusRangeCalls = 0
local registeredElement

local function newTimer(delay, callback)
  local timer = {
    delay = delay,
    due = now + delay,
    callback = callback,
  }
  function timer:Cancel()
    self.cancelled = true
  end
  timers[#timers + 1] = timer
  return timer
end

local function activeTimer()
  for i = #timers, 1, -1 do
    local timer = timers[i]
    if not timer.cancelled and not timer.fired then return timer end
  end
end

local function fireActiveTimer()
  local timer = activeTimer()
  expect(timer, "expected an armed timer")
  timer.fired = true
  now = timer.due
  timer.callback()
  return timer
end

local function flushAfterCallbacks()
  while #afterCallbacks > 0 do
    local callbacks = afterCallbacks
    afterCallbacks = {}
    for i = 1, #callbacks do callbacks[i]() end
  end
end

local function driverFrame()
  local frame = { events = {} }
  function frame:SetScript(script, callback) self[script] = callback end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:RegisterUnitEvent(event) self.events[event] = true end
  function frame:UnregisterAllEvents() self.events = {} end
  driverFrames[#driverFrames + 1] = frame
  return frame
end

local bossFrame = { MSUFUnitKey = "boss1", visible = true }
function bossFrame:IsVisible() return self.visible end
function bossFrame:HookScript(script, callback) self[script] = callback end
local focusFrame = { MSUFUnitKey = "focus", visible = true }
function focusFrame:IsVisible() return self.visible end
function focusFrame:HookScript(script, callback) self[script] = callback end

local UF = {
  frames = { boss1 = bossFrame, focus = focusFrame },
  UnitExistsSafe = function(unit) return unit == "boss1" or unit == "focus" end,
  CompileAlphaRuntime = function() end,
  ApplyRangeModifier = function(frame, multiplier)
    frame.rangeMultiplier = multiplier
    return true
  end,
  RegisterElement = function(name, element)
    if name == "RangeFade" then registeredElement = element end
  end,
}

local MSUF = { UF = UF }
_G.C_Timer = {
  NewTimer = newTimer,
  After = function(_, callback) afterCallbacks[#afterCallbacks + 1] = callback end,
}
_G.C_Spell = {
  IsSpellInRange = function(_, unit)
    if unit == "boss1" then rangeCalls = rangeCalls + 1 end
    if unit == "focus" then focusRangeCalls = focusRangeCalls + 1 end
    return true
  end,
}
_G.CreateFrame = function() return driverFrame() end
_G.UnitCanAssist = function() return false end
_G.UnitCanAttack = function(_, unit) return unit == "boss1" or unit == "focus" end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitInRange = function() return nil, false end
_G.UnitClass = function() return "Warlock", "WARLOCK" end
_G.IsPlayerSpell = function(spellID) return spellID == 234153 end
_G.GetUnitSpeed = function() return 0 end
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return true end
_G.issecretvalue = function() return false end
_G.wipe = function(tbl)
  for key in pairs(tbl) do tbl[key] = nil end
end

local runtimeChunk, runtimeError = loadfile(runtimePath)
expect(runtimeChunk, runtimeError)
runtimeChunk("MidnightSimpleUnitFrames", MSUF)
expect(registeredElement, "RangeFade element did not register")

registeredElement.Apply(focusFrame, {
  range = { active = true, alpha = 0.4, updateRate = 0 },
})
registeredElement.Apply(bossFrame, {
  range = { active = true, alpha = 0.4, updateRate = 20 },
})
local fastTimer = activeTimer()
expect(fastTimer, "custom Boss rate did not arm the shared timer")
expect(near(fastTimer.delay, 0.05), "20 updates/sec must schedule a 50 ms interval")
local callsBeforeFastTick = rangeCalls
local focusCallsBeforeFastTick = focusRangeCalls
fireActiveTimer()
expect(rangeCalls == callsBeforeFastTick + 1,
  "custom Boss rate must evaluate even when player and boss speeds are zero")
expect(focusRangeCalls == focusCallsBeforeFastTick,
  "custom Boss ticks must not accelerate another unit's adaptive fallback")
expect(near(activeTimer() and activeTimer().delay, 0.05), "custom Boss rate did not re-arm at 50 ms")

local rangeDriver
for i = 1, #driverFrames do
  local frame = driverFrames[i]
  if frame.events.INSTANCE_ENCOUNTER_ENGAGE_UNIT and type(frame.OnEvent) == "function" then
    rangeDriver = frame
    break
  end
end
expect(rangeDriver, "Boss lifecycle range driver is missing")
local callsBeforeBossReset = rangeCalls
rangeDriver.OnEvent(rangeDriver, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
rangeDriver.OnEvent(rangeDriver, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
rangeDriver.OnEvent(rangeDriver, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
expect(rangeCalls == callsBeforeBossReset,
  "Boss lifecycle burst must not evaluate range synchronously")
expect(#afterCallbacks == 1,
  "Boss lifecycle burst must queue exactly one next-frame reconciliation")
flushAfterCallbacks()
expect(rangeCalls == callsBeforeBossReset + 1,
  "Boss lifecycle burst must reconcile each active Boss once")
expect(near(activeTimer() and activeTimer().delay, 0.05),
  "Boss lifecycle reconciliation did not restart the selected cadence")

registeredElement.Apply(bossFrame, {
  range = { active = true, alpha = 0.4, updateRate = 0 },
})
local standardTimer = activeTimer()
expect(standardTimer, "Standard mode did not keep the adaptive Boss heartbeat")
expect(near(standardTimer.delay, 2.0), "Standard idle mode must retain the existing 2 second heartbeat")
local callsBeforeStandardTick = rangeCalls
local focusCallsBeforeStandardTick = focusRangeCalls
fireActiveTimer()
expect(rangeCalls == callsBeforeStandardTick,
  "Standard idle heartbeat must retain the existing speed-gated range evaluation")
expect(focusRangeCalls == focusCallsBeforeStandardTick,
  "Standard idle heartbeat changed another unit's speed-gated evaluation")

registeredElement.Disable(bossFrame)
registeredElement.Disable(focusFrame)
expect(not activeTimer(), "Boss timer must retire after its last visible consumer is disabled")

local registeredSection
local sliders = {}
local numberBindings = {}
local writes = {}
local tooltips = {}
local sectionHeights = {}
local popupShows = {}
local popupDialogs = {}

local function widget()
  local control = {}
  function control:SetValueFormatter(formatter) self.formatter = formatter end
  function control:SetValueParser(parser) self.parser = parser end
  return control
end

local Menu = {
  _msuf2MenuSessionSerial = 1,
  KeySetFromWords = function(words)
    local set = {}
    for token in words:gmatch("%S+") do set[token] = true end
    return set
  end,
  ValueTextList = function(...) return { ... } end,
  PercentValue = function(value) return tostring(value) end,
  RefreshProxy = function()
    return function(callback) return callback end
  end,
  BindBoolWidget = function() end,
  BindSegment = function() end,
  BindSliderDragPreview = nil,
  BindNumberWidget = function(_, control, getValue, setValue, fallback, metadata)
    numberBindings[#numberBindings + 1] = {
      control = control,
      get = getValue,
      set = setValue,
      fallback = fallback,
      metadata = metadata,
    }
  end,
  TrackRefresh = function() end,
  AddTooltip = function(control, title, body)
    tooltips[#tooltips + 1] = { control = control, title = title, body = body }
  end,
  InstallStaticPopup = function(key, spec)
    popupDialogs[key] = popupDialogs[key] or spec
    return popupDialogs[key]
  end,
}
Menu.Widgets = {
  ControlCard = function() return {} end,
  ToggleAt = function() return widget() end,
  Slider = function(_, label, minimum, maximum, step)
    local control = widget()
    control.label, control.minimum, control.maximum, control.step = label, minimum, maximum, step
    function control:SetValueBoxWidth(width) self.valueBoxWidth = width end
    sliders[#sliders + 1] = control
    return control
  end,
  Segment = function() return widget() end,
  MoveWidget = function() end,
}
Menu.UnitPage = {
  RegisterSection = function(spec) registeredSection = spec end,
  SettingMeta = function(_, path, unit, key)
    return { controlId = path, settingKey = unit .. "." .. key }
  end,
  ReadBool = function(_, _, default) return default end,
  SetBool = function() end,
  ReadNumber = function(_, _, default) return default end,
  SetNumber = function(unit, key, value, reason)
    writes[#writes + 1] = { unit = unit, key = key, value = value, reason = reason }
  end,
  SetString = function() end,
  SetControlEnabled = function() end,
  GetConf = function() return {} end,
}
_G.StaticPopupDialogs = popupDialogs
_G.StaticPopup_Show = function(key) popupShows[#popupShows + 1] = key end

local menuChunk, menuError = loadfile(menuPath)
expect(menuChunk, menuError)
menuChunk("MidnightSimpleUnitFrames_Options", { MSUF2 = Menu })
expect(registeredSection, "Range Fade section did not register")
expect(registeredSection.height(nil, nil, "boss") == 350, "Boss Range Fade section height is stale")
expect(registeredSection.height(nil, nil, "target") == 230, "non-Boss Range Fade height changed")

local builder = {}
function builder:CollapsibleSection(_, _, height)
  sectionHeights[#sectionHeights + 1] = height
  return { _msuf2Width = 720 }
end

registeredSection.build({ width = 720 }, builder, "boss")
expect(#sliders == 2, "Boss Range Fade must expose alpha and update-rate sliders")
local rateSlider = sliders[2]
expect(rateSlider.minimum == 0 and rateSlider.maximum == 20 and rateSlider.step == 1,
  "Boss update-rate slider must span Standard through 20 updates/sec")
expect(rateSlider.formatter and rateSlider.formatter(0) == "Standard", "zero rate must render as Standard")
expect(rateSlider.formatter and rateSlider.formatter(20) == "20 / sec", "20 Hz label is incorrect")
expect(rateSlider.parser and rateSlider.parser("Standard") == 0, "Standard input must parse to zero")
expect(rateSlider.valueBoxWidth == 76, "Boss rate value box must fit Standard and the per-second suffix")

local rateBinding
for i = 1, #numberBindings do
  if numberBindings[i].metadata and numberBindings[i].metadata.settingKey == "boss.rangeFadeUpdateRate" then
    rateBinding = numberBindings[i]
    break
  end
end
expect(rateBinding, "Boss update-rate setting metadata is missing")
rateBinding.set(20)
local write = writes[#writes]
expect(write and write.unit == "boss" and write.key == "rangeFadeUpdateRate" and write.value == 20,
  "Boss update-rate slider did not write its Boss setting")
expect(write.reason == "MSUF2_BOSS_RANGE_UPDATE_RATE", "Boss update-rate apply reason is incorrect")
expect(#popupShows == 1 and popupShows[1] == "MSUF2_BOSS_RANGE_UPDATE_RATE_WARNING",
  "first custom Boss rate in a menu session must show the performance warning")
rateBinding.set(19)
expect(#popupShows == 1, "Boss rate warning must not spam within one menu session")
Menu._msuf2MenuSessionSerial = 2
rateBinding.set(18)
expect(#popupShows == 2, "Boss rate warning must reset for the next menu session")
Menu._msuf2MenuSessionSerial = 3
rateBinding.set(0)
expect(#popupShows == 2, "Standard Boss rate must not show a performance warning")
expect(#tooltips == 1 and tooltips[1].body:find("50 ms", 1, true), "Boss update-rate cost tooltip is missing")

local sliderCountBeforeTarget = #sliders
registeredSection.build({ width = 720 }, builder, "target")
expect(#sliders == sliderCountBeforeTarget + 1, "non-Boss Range Fade must not expose the Boss update slider")

local configFile = assert(io.open(configPath, "rb"))
local configSource = configFile:read("*a")
configFile:close()
expect(configSource:find("range.updateRate = updateRate", 1, true), "compiled range spec does not carry update rate")
expect(configSource:find('key ~= "boss"', 1, true), "compiled update rate is not restricted to Boss frames")

local auraFile = assert(io.open(auraPath, "rb"))
local auraSource = auraFile:read("*a")
auraFile:close()
expect(auraSource:find('local deferBossBurst = event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"', 1, true),
  "Boss AuraContainer identity refreshes are not burst-gated")
expect(auraSource:find("A3._ScheduleDirectIdentityEventRefresh(units[i])", 1, true),
  "Boss AuraContainer identity refreshes do not use the existing coalescer")

local coreFile = assert(io.open(corePath, "rb"))
local coreSource = coreFile:read("*a")
coreFile:close()
expect(coreSource:find('AddEventHandler(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", QueueBossIdentity, true)', 1, true),
  "Boss unit-frame identity refreshes are not burst-coalesced")

local windowFile = assert(io.open(windowPath, "rb"))
local windowSource = windowFile:read("*a")
windowFile:close()
expect(windowSource:find('M._msuf2MenuSessionSerial = (tonumber(M._msuf2MenuSessionSerial) or 0) + 1', 1, true),
  "Menu2 open lifecycle no longer resets the once-per-session Boss rate warning")

print("boss range update rate smoke: OK")
