-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.TextDrain = function(
  C_Timer, HealthPercent, HealthPercentAvailable, UF, UpdateHealthTextValues, UpdatePowerTextValues, issecretvalue, type,
    DirtyTextFrameVisible
)

local TEXT_DIRTY_HEALTH = 1
local TEXT_DIRTY_POWER = 2
local TEXT_DIRTY_BOTH = 3
local TEXT_DIRTY_DELAY = 0.25
local dirtyTextQueueA, dirtyTextQueueB = {}, {}
local dirtyTextWriteQueue = dirtyTextQueueA
local dirtyTextWriteCount = 0
local dirtyTextTicker
local FlushDirtyText

local function ClearDirtyTextBit(frame, bit)
  if not frame then return end
  local mask = frame._msufTextDirtyMask
  if mask == TEXT_DIRTY_BOTH then
    frame._msufTextDirtyMask = bit == TEXT_DIRTY_HEALTH and TEXT_DIRTY_POWER or TEXT_DIRTY_HEALTH
  elseif mask == bit then
    frame._msufTextDirtyMask = nil
  end
end

local function ClearDirtyTextDispatch(frame, mask)
  local rt = frame and frame._msufTextRuntime
  if not rt then return end
  if mask == TEXT_DIRTY_HEALTH or mask == TEXT_DIRTY_BOTH then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
    rt._dispatchHealthMissing = nil
    rt._dispatchHealthMissingReady = nil
  end
  if mask == TEXT_DIRTY_POWER or mask == TEXT_DIRTY_BOTH then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
end

local function CancelDirtyTextFrame(frame, mask, preserveDispatch)
  if not frame then return end
  if mask == TEXT_DIRTY_HEALTH or mask == TEXT_DIRTY_POWER then
    ClearDirtyTextBit(frame, mask)
    if preserveDispatch ~= true then ClearDirtyTextDispatch(frame, mask) end
  else
    frame._msufTextDirtyMask = nil
    if preserveDispatch ~= true then ClearDirtyTextDispatch(frame, TEXT_DIRTY_BOTH) end
  end
end

local function ArmDirtyTextTimer()
  if not dirtyTextTicker then
    dirtyTextTicker = C_Timer.NewTicker(TEXT_DIRTY_DELAY, FlushDirtyText)
  end
end

local function MarkDirtyText(frame, bit)
  if not frame then return end
  local mask = frame._msufTextDirtyMask
  if mask == nil then
    frame._msufTextDirtyMask = bit
  elseif mask ~= bit then
    frame._msufTextDirtyMask = TEXT_DIRTY_BOTH
  end
  if frame._msufTextDirtyQueued == true then return end
  frame._msufTextDirtyQueued = true
  dirtyTextWriteCount = dirtyTextWriteCount + 1
  dirtyTextWriteQueue[dirtyTextWriteCount] = frame
  ArmDirtyTextTimer()
end

local function MarkHealthTextDirty(frame)
  MarkDirtyText(frame, TEXT_DIRTY_HEALTH)
  -- The bar route may have published a restricted percent for a synchronous
  -- text writer. A deferred marker must never retain that event payload.
  local rt = frame and frame._msufTextRuntime
  if rt and (rt._dispatchHealthPercentReady == true
      or rt._dispatchHealthMissingReady == true) then
    ClearDirtyTextDispatch(frame, TEXT_DIRTY_HEALTH)
  end
end

local MarkGroupHealthTextDirty = MarkHealthTextDirty

local function MarkPowerTextDirty(frame)
  MarkDirtyText(frame, TEXT_DIRTY_POWER)
  ClearDirtyTextDispatch(frame, TEXT_DIRTY_POWER)
end

local function DirtyTextFrameState(frame)
  if not frame or not DirtyTextFrameVisible(frame) then return false end
  local attached = UF.attachedFrames
  if type(attached) == "table" and attached[frame] ~= true then return false end
  local active = frame._msufActiveElements
  local rt = frame._msufTextRuntime
  if not (rt and type(active) == "table") then return false end
  local unit = frame.MSUFUnitKey or frame.unit
  if unit == nil then return false end
  return rt, unit, active
end

FlushDirtyText = function()
  if dirtyTextWriteCount == 0 then
    local ticker = dirtyTextTicker
    dirtyTextTicker = nil
    if ticker then ticker:Cancel() end
    return
  end
  local batch = dirtyTextWriteQueue
  local count = dirtyTextWriteCount
  dirtyTextWriteQueue = batch == dirtyTextQueueA and dirtyTextQueueB or dirtyTextQueueA
  dirtyTextWriteCount = 0

  for i = 1, count do
    local frame = batch[i]
    batch[i] = nil
    if frame and frame._msufTextDirtyQueued == true then
      frame._msufTextDirtyQueued = nil
      local mask = frame._msufTextDirtyMask
      frame._msufTextDirtyMask = nil
      local rt, unit, active = DirtyTextFrameState(frame)
      if rt then
        if (mask == TEXT_DIRTY_HEALTH or mask == TEXT_DIRTY_BOTH)
          and active.HealthText == true and (rt.healthSlotCount or 0) > 0 then
          -- No event payload is retained. Force max-dependent modes to resolve
          -- the authoritative value at drain time rather than reusing a cache
          -- that may predate the dirty window.
          frame._msufTextHealthMaxReady = nil
          local bar = frame.hpBar or frame.Health
          local pct = bar and bar._msufHealthPercentValue
          local percentFn = rt.healthHotFromPercent
          local percentReady = (rt.healthNeedsPercent == true or rt.healthColorByHealth == true)
            and bar
            and bar._msufHealthPercentUnit == unit
            and pct ~= nil
            and issecretvalue(pct) ~= true
          if percentFn and HealthPercentAvailable then
            -- Percent-only Group text can bypass the generic value resolver.
            -- Reuse Health's plain cache; protected values are reread once at
            -- drain time and passed directly to the precompiled writer.
            if percentReady ~= true then pct = HealthPercent(unit) end
            percentFn(frame, "UNIT_HEALTH", unit, pct)
          elseif rt.healthDrain then
            rt.healthDrain(frame, unit, pct, percentReady)
          else
            if percentReady == true then
              -- The Health element already read this latest plain percentage
              -- for the same unit. Share it with the generic deferred writer;
              -- opaque values never enter this cache.
              rt._dispatchHealthPercent = pct
              rt._dispatchHealthPercentReady = true
            end
            UpdateHealthTextValues(frame, "UNIT_HEALTH", unit, nil, nil)
          end
        elseif mask == TEXT_DIRTY_HEALTH or mask == TEXT_DIRTY_BOTH then
          ClearDirtyTextDispatch(frame, TEXT_DIRTY_HEALTH)
        end
        if (mask == TEXT_DIRTY_POWER or mask == TEXT_DIRTY_BOTH)
          and active.PowerText == true and (rt.powerSlotCount or 0) > 0 then
          local bar = frame.targetPowerBar
          local power, powerMax
          if bar and bar._msufShown == true then
            local cachedPower = bar._msufPowerValue
            if rt.powerNeedsCurrent == true
              and bar._msufPowerValueUnit == unit
              and issecretvalue(cachedPower) ~= true
              and cachedPower ~= nil then
              power = cachedPower
            end
            local cachedMax = bar._msufPowerMax
            if rt.powerNeedsMax == true
              and bar._msufPowerMaxReady == true
              and bar._msufPowerMaxUnit == unit
              and issecretvalue(cachedMax) ~= true
              and cachedMax ~= nil then
              powerMax = cachedMax
            end
          end
          if rt.powerDrain then
            rt.powerDrain(frame, unit, power)
          else
            UpdatePowerTextValues(frame, "UNIT_POWER_UPDATE", unit, power, powerMax, nil, nil, false)
          end
        elseif mask == TEXT_DIRTY_POWER or mask == TEXT_DIRTY_BOTH then
          ClearDirtyTextDispatch(frame, TEXT_DIRTY_POWER)
        end
      else
        ClearDirtyTextDispatch(frame, mask)
      end
    end
  end

  -- New work queued during the drain already shares the active ticker.
end

local function BindTextDrain(values)
  UpdateHealthTextValues = values.UpdateHealthTextValues
  UpdatePowerTextValues = values.UpdatePowerTextValues
end

return CancelDirtyTextFrame, DirtyTextFrameState, MarkGroupHealthTextDirty, MarkHealthTextDirty, MarkPowerTextDirty, TEXT_DIRTY_HEALTH,
  TEXT_DIRTY_POWER, BindTextDrain
end
