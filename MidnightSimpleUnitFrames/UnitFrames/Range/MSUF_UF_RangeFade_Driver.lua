--- UnitFrames/Range/MSUF_UF_RangeFade_Driver.lua
--- Event subscriptions of the unitframe range runtime: the unit catalog
--- (supported units, the driver's unit order and bits, the boss and arena
--- families) and the shared driver frames with the events each one holds.
--- UnitFrames/Range/MSUF_UF_RangeFade.lua owns the range state, the event
--- handler and every evaluation; it loads right after this file and drives
--- the subscriptions through Range.Driver.

local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

local Range = UF.Range or {}
UF.Range = Range

local CreateFrame = _G.CreateFrame
local unpack = unpack or table.unpack
local tonumber = tonumber

-- Bitmasks let one driver frame know which unit families need target/focus/pet/boss events
-- without registering a separate expensive event set for every unitframe.
-- Every per-unit table comes from one ordered list in one pass: the supported
-- set, RANGE_UNITS (the order the driver's unit-event spans follow), the boss
-- and arena families, and one bit per unit for the driver mask. Assigning the
-- bits in that loop keeps them unique by construction; hand-numbered bits once
-- gave pettarget and arena1 the same bit, so a pass that swapped those two
-- units left the unit-event registration stale (and pettarget + arena1 summed
-- to arena2's bit). The builder is a function so its temporaries stay out of
-- this chunk's local budget. Arena slots follow MSUF_MAX_ARENA_FRAMES
-- (MSUF.Client.MaxArenaOpponents from Game/Shared/Initialize.lua: 3 on
-- Mainline, 5 on TBC/Mists), clamped to 3..5.
local SUPPORTED_UNITS, RANGE_UNITS, RANGE_UNIT_BITS, BOSS_UNITS, BOSS_UNIT_SET, ARENA_UNITS = (function(arenaSlots)
  local supported, order, bits, boss, bossSet, arena = {}, {
    "target", "targettarget", "focus", "focustarget", "pet", "pettarget",
    "boss1", "boss2", "boss3", "boss4", "boss5",
  }, {}, {}, {}, {}
  for i = 1, arenaSlots do order[#order + 1] = "arena" .. i end
  for i = 1, #order do
    local unit = order[i]
    supported[unit] = true
    bits[unit] = 2 ^ (i - 1)
    if unit:match("^boss%d$") then
      boss[#boss + 1] = unit
      bossSet[unit] = true
    elseif unit:match("^arena%d$") then
      arena[#arena + 1] = unit
    end
  end
  return supported, order, bits, boss, bossSet, arena
end)(math.max(3, math.min(5, math.floor(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3))))
local TARGET_EVENT_TARGET_BIT = 1
local TARGET_EVENT_FOCUS_BIT = 2
local TARGET_EVENT_PET_BIT = 4
local DRIVER_EVENT_ACTIVE_BIT = 1
local DRIVER_EVENT_TARGET_BIT = 2
local DRIVER_EVENT_FOCUS_BIT = 4
local DRIVER_EVENT_PET_BIT = 8
local DRIVER_EVENT_BOSS_BIT = 16
local DRIVER_EVENT_TARGET_SPELL_BIT = 32
local DRIVER_EVENT_ARENA_BIT = 64

local UNIT_EVENTS = {
  "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
  "UNIT_CONNECTION",
}
local TARGET_UNIT_EVENT = "UNIT_TARGET"

-- ACTIVE_PLAYER_SPECIALIZATION_CHANGED and TRAIT_CONFIG_UPDATED are Retail
-- talent events that never fire on Classic; registering them there is harmless,
-- and SPELLS_CHANGED / PLAYER_TALENT_UPDATE still rebuild the spell picks.
local SPELL_UPDATE_EVENTS = {
  "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
  "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}

local MOVEMENT_EVENTS = {
  "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
}

local UNIT_EVENT_FILTER_LIMIT = 4

-- Units the driver frames filter their unit events to, in driver span order,
-- and the units whose UNIT_TARGET they hear. Rebuilt on every registration.
local unitEventUnits = {}
local targetEventUnits = {}

-- The handler is the range runtime's DriverOnEvent (Range.Driver.SetEventHandler).
local eventHandler
local driver
-- Driver frames for unit spans after the main driver's first four tokens.
local extraUnitDrivers = {}

local driverRegistered = false
local driverUnitMask
local driverTargetMask
local driverEventMask

local function DriverMaskHas(mask, flag)
  return mask ~= nil and mask % (flag + flag) >= flag
end

local function SetDriverEventRegistered(frame, event, wanted, registered)
  if wanted == registered then return end
  if wanted then
    frame:RegisterEvent(event)
  else
    frame:UnregisterEvent(event)
  end
end

local function SetDriverEventBundleRegistered(frame, events, wanted, registered)
  if wanted == registered then return end
  for i = 1, #events do
    local event = events[i]
    if wanted then
      frame:RegisterEvent(event)
    else
      frame:UnregisterEvent(event)
    end
  end
end

local function EnsureDriver()
  if driver then return driver end
  if not CreateFrame then return nil end
  driver = CreateFrame("Frame")
  driver:SetScript("OnEvent", eventHandler)
  return driver
end

local function EnsureExtraUnitDriver(index)
  local frame = extraUnitDrivers[index]
  if frame then return frame end
  if not CreateFrame then return nil end
  frame = CreateFrame("Frame")
  frame:SetScript("OnEvent", eventHandler)
  extraUnitDrivers[index] = frame
  return frame
end

local function ClearDriverUnitSpan(frame)
  if not frame then return end
  frame._msufRangeUnitFirst = nil
  frame._msufRangeUnitLast = nil
end

local function RegisterDriverUnitChunk(frame, first, last)
  if not (frame and first and last and first <= last) then
    ClearDriverUnitSpan(frame)
    return false
  end
  frame._msufRangeUnitFirst = first
  frame._msufRangeUnitLast = last
  for i = 1, #UNIT_EVENTS do
    frame:RegisterUnitEvent(UNIT_EVENTS[i], unpack(unitEventUnits, first, last))
  end
  return true
end

local function UnregisterDriverUnitEvents(frame)
  if not frame then return end
  for i = 1, #UNIT_EVENTS do
    frame:UnregisterEvent(UNIT_EVENTS[i])
  end
  ClearDriverUnitSpan(frame)
end

local function BuildDriverUnitLists(activeUnits)
  local unitCount, targetCount = 0, 0
  local unitMask, targetMask = 0, 0
  for i = 1, #RANGE_UNITS do
    local unit = RANGE_UNITS[i]
    if activeUnits[unit] then
      unitMask = unitMask + RANGE_UNIT_BITS[unit]
      if unit == "targettarget" then
        targetCount = targetCount + 1
        targetEventUnits[targetCount] = "target"
        targetMask = targetMask + TARGET_EVENT_TARGET_BIT
      elseif unit == "focustarget" then
        targetCount = targetCount + 1
        targetEventUnits[targetCount] = "focus"
        targetMask = targetMask + TARGET_EVENT_FOCUS_BIT
      elseif unit == "pettarget" then
        targetCount = targetCount + 1
        targetEventUnits[targetCount] = "pet"
        targetMask = targetMask + TARGET_EVENT_PET_BIT
      else
        unitCount = unitCount + 1
        unitEventUnits[unitCount] = unit
      end
    end
  end
  for i = unitCount + 1, #unitEventUnits do
    unitEventUnits[i] = nil
  end
  for i = targetCount + 1, #targetEventUnits do
    targetEventUnits[i] = nil
  end
  return unitCount, targetCount, unitMask, targetMask
end

local function RegisterDriver(activeUnits, activeCount, targetSpellEvents)
  local f = EnsureDriver()
  if not f then return end
  local unitCount, targetCount, unitMask, targetMask = BuildDriverUnitLists(activeUnits)

  local targetActive = activeUnits.target == true
  local targetDependent = targetActive or activeUnits.targettarget == true
  local focusDependent = activeUnits.focus == true or activeUnits.focustarget == true
  local petActive = activeUnits.pet == true or activeUnits.pettarget == true
  local bossActive = activeUnits.boss1 == true
    or activeUnits.boss2 == true
    or activeUnits.boss3 == true
    or activeUnits.boss4 == true
    or activeUnits.boss5 == true
  local arenaActive = false
  for i = 1, #ARENA_UNITS do
    if activeUnits[ARENA_UNITS[i]] == true then
      arenaActive = true
      break
    end
  end

  local eventMask = 0
  if activeCount > 0 then eventMask = eventMask + DRIVER_EVENT_ACTIVE_BIT end
  if targetDependent then eventMask = eventMask + DRIVER_EVENT_TARGET_BIT end
  if focusDependent then eventMask = eventMask + DRIVER_EVENT_FOCUS_BIT end
  if petActive then eventMask = eventMask + DRIVER_EVENT_PET_BIT end
  if bossActive then eventMask = eventMask + DRIVER_EVENT_BOSS_BIT end
  if arenaActive then eventMask = eventMask + DRIVER_EVENT_ARENA_BIT end
  if targetActive and targetSpellEvents then eventMask = eventMask + DRIVER_EVENT_TARGET_SPELL_BIT end

  if driverRegistered
    and driverUnitMask == unitMask
    and driverTargetMask == targetMask
    and driverEventMask == eventMask then
    return
  end

  -- Keep unchanged subscriptions intact. Visibility churn commonly changes
  -- only the target-related masks; rebuilding every event registration here
  -- makes target frame show/hide substantially more expensive than the range
  -- evaluation itself needs to be.
  if not driverRegistered or driverUnitMask ~= unitMask then
    if driverRegistered and driverUnitMask and driverUnitMask ~= 0 then
      UnregisterDriverUnitEvents(f)
      for i = 1, #extraUnitDrivers do
        UnregisterDriverUnitEvents(extraUnitDrivers[i])
      end
    end
    local extraUsed = 0
    if unitCount > 0 then
      -- target, focus and pet with boss1-5 plus arena1-5 can reach 13 tokens.
      -- The 12.1 API documentation lists RegisterUnitEvent's units as a
      -- variadic list (see the GroupRangeFade note in MSUF_UF_Core.lua), but
      -- no client has been checked in game with more than four, so the spans
      -- stay at UNIT_EVENT_FILTER_LIMIT (4) tokens per driver frame, which is
      -- valid either way. The main driver always keeps the first span.
      local chunkLast = math.min(unitCount, UNIT_EVENT_FILTER_LIMIT)
      RegisterDriverUnitChunk(f, 1, chunkLast)
      while chunkLast < unitCount do
        local chunkFirst = chunkLast + 1
        chunkLast = math.min(unitCount, chunkLast + UNIT_EVENT_FILTER_LIMIT)
        extraUsed = extraUsed + 1
        RegisterDriverUnitChunk(EnsureExtraUnitDriver(extraUsed), chunkFirst, chunkLast)
      end
    else
      ClearDriverUnitSpan(f)
    end
    for i = extraUsed + 1, #extraUnitDrivers do
      ClearDriverUnitSpan(extraUnitDrivers[i])
    end
  end

  if not driverRegistered or driverTargetMask ~= targetMask then
    if driverRegistered and driverTargetMask and driverTargetMask ~= 0 then
      f:UnregisterEvent(TARGET_UNIT_EVENT)
    end
    if targetCount > 0 then
      f:RegisterUnitEvent(TARGET_UNIT_EVENT, unpack(targetEventUnits, 1, targetCount))
    end
  end

  local oldEventMask = driverRegistered and driverEventMask or 0
  local activeEventsWanted = activeCount > 0
  local activeEventsRegistered = DriverMaskHas(oldEventMask, DRIVER_EVENT_ACTIVE_BIT)
  SetDriverEventRegistered(f, "PLAYER_ENTERING_WORLD", activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(f, "PLAYER_REGEN_DISABLED", activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(f, "PLAYER_REGEN_ENABLED", activeEventsWanted, activeEventsRegistered)
  SetDriverEventBundleRegistered(f, SPELL_UPDATE_EVENTS, activeEventsWanted, activeEventsRegistered)
  SetDriverEventBundleRegistered(f, MOVEMENT_EVENTS, activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(
    f, "PLAYER_TARGET_CHANGED", targetDependent,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_TARGET_BIT)
  )
  SetDriverEventRegistered(
    f, "PLAYER_FOCUS_CHANGED", focusDependent,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_FOCUS_BIT)
  )
  SetDriverEventRegistered(
    f, "UNIT_PET", petActive,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_PET_BIT)
  )
  SetDriverEventRegistered(
    f, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", bossActive,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_BOSS_BIT)
  )
  SetDriverEventRegistered(
    f, "ARENA_OPPONENT_UPDATE", arenaActive,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_ARENA_BIT)
  )
  SetDriverEventRegistered(
    f, "SPELL_RANGE_CHECK_UPDATE", targetActive and targetSpellEvents and true or false,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_TARGET_SPELL_BIT)
  )

  driverRegistered = true
  driverUnitMask = unitMask
  driverTargetMask = targetMask
  driverEventMask = eventMask
end

local function UnregisterDriver()
  if not driverRegistered or not driver then return end
  driver:UnregisterAllEvents()
  ClearDriverUnitSpan(driver)
  for i = 1, #extraUnitDrivers do
    local extra = extraUnitDrivers[i]
    extra:UnregisterAllEvents()
    ClearDriverUnitSpan(extra)
  end
  driverRegistered = false
  driverUnitMask = nil
  driverTargetMask = nil
  driverEventMask = nil
end

--- The catalog and the subscription entry points of the range runtime.
--- Register(activeUnits, activeCount, targetSpellEvents) reconciles every
--- driver subscription with the active units; Unregister drops them all.
Range.Driver = {
  SUPPORTED_UNITS = SUPPORTED_UNITS,
  RANGE_UNITS = RANGE_UNITS,
  BOSS_UNITS = BOSS_UNITS,
  BOSS_UNIT_SET = BOSS_UNIT_SET,
  ARENA_UNITS = ARENA_UNITS,
  unitEventUnits = unitEventUnits,
  SetEventHandler = function(handler) eventHandler = handler end,
  Register = RegisterDriver,
  Unregister = UnregisterDriver,
}
