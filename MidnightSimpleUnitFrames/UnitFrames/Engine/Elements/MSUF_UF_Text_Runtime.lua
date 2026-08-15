--- UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua
--- Runtime dispatcher for unitframe text slots.
---
--- Decides which text slots refresh for each unit/event, keeps combat-safe
--- visibility updates isolated, and separates secret-value branches from cache hits.

local _, MSUF = ...
local Text = MSUF and MSUF.UFText
local UF = MSUF and MSUF.UF
if not (Text and UF) then return end

local UnitHealth = Text.UnitHealth
local UnitHealthMax = Text.UnitHealthMax
local UnitHealthMissing = _G.UnitHealthMissing
local UnitGetTotalAbsorbs = Text.UnitGetTotalAbsorbs
local ABSORB_HEALTH_MODE_BASE = Text.ABSORB_HEALTH_MODE_BASE or {}
local UnitPower = Text.UnitPower
local UnitPowerMax = Text.UnitPowerMax
local UnitPowerType = Text.UnitPowerType
local InCombatLockdown = Text.InCombatLockdown
local UnitName = Text.UnitName
local ReadDisplayName = UnitName
local displayNameResolverUsesFrame = false
local GetTime = Text.GetTime
local C_Timer = _G.C_Timer
local PowerColor = Text.PowerColor
local SetShownCached = Text.SetShownCached
local SetTextCached = Text.SetTextCached
local ApplyNameTextColor = Text.ApplyNameTextColor or function(frame, unit)
  Text.SetNameTextColor(frame, Text.NameTextColor(frame, unit))
end
local NPCTypeTextColorEnabled = Text.NPCTypeTextColorEnabled
local ApplyInlineTextColor = Text.ApplyInlineTextColor or function(frame, unit, inline)
  Text.SetInlineTextColor(frame, Text.InlineTextColor(frame, unit, inline))
end
local SetPowerTextColor = Text.SetPowerTextColor
local UpdateHealthTextColor = Text.UpdateHealthTextColor
local HealthPercent = Text.HealthPercent
local HealthPercentAvailable = Text.UnitHealthPercent ~= nil and Text.SCALE_100 ~= nil
local PowerPercent = Text.PowerPercent
local PowerPercentAvailable = Text.UnitPowerPercent ~= nil
local floor = Text.floor or math.floor
local Secrets = MSUF.Secrets or {}
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local FreshUnitState = UF.FreshUnitState
local ReadConnectedCached = UF.ReadConnectedCached
local ReadDeadCached = UF.ReadDeadCached
local UpdateTextSlots = Text.UpdateTextSlots
local UpdateTextSlotsPlain = Text.UpdateTextSlotsPlain or UpdateTextSlots
local UpdateTextSlotsSecret = Text.UpdateTextSlotsSecret or UpdateTextSlots
local ResolveHealthTextModes = Text.ResolveHealthTextModes
local AnchorInlineToName = Text.AnchorInlineToName
local RefreshNameCenterClipFit = Text.RefreshNameCenterClipFit
local EMPTY_EVENTS = Text.EMPTY_EVENTS
local POWER_EVENTS = Text.POWER_EVENTS
local POWER_EVENTS_FREQUENT = Text.POWER_EVENTS_FREQUENT
local POWER_TEXT_MAX_EVENTS = { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_TEXT_VALUE_META_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_TEXT_VALUE_META_EVENTS_FREQUENT = { "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local GROUP_LIFECYCLE_EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }
local POWER_IDENTITY_EVENTS = {
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_FAST = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_FAST = true,
  MSUF_GF_UNIT_IDENTITY = true,
  MSUF_GF_UNIT_STRUCTURE = true,
}

-- Match oUF's 250 ms text cadence with one shared, combat-window ticker. The
-- queue retains frames only; restricted event payloads are always reread when
-- the batch drains, while latest plain values already owned by a bar may be
-- reused.
local TEXT_DIRTY_HEALTH = 1
local TEXT_DIRTY_POWER = 2
local TEXT_DIRTY_BOTH = 3
local TEXT_DIRTY_DELAY = 0.25
local dirtyTextQueueA, dirtyTextQueueB = {}, {}
local dirtyTextWriteQueue = dirtyTextQueueA
local dirtyTextWriteCount = 0
local dirtyTextTicker
local FlushDirtyText
local UpdateHealthTextValues
local UpdatePowerTextValues

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

local function MarkGroupHealthTextDirty(frame)
  -- Group UNIT_HEALTH is compiled with Health's percent-only updater. That
  -- route never publishes a dispatch payload, so the generic four-field clear
  -- is dead work on every member tick.
  MarkDirtyText(frame, TEXT_DIRTY_HEALTH)
  local rt = frame and frame._msufTextRuntime
  if rt and (rt._dispatchHealthPercentReady == true
    or rt._dispatchHealthMissingReady == true) then
    -- Defensive recovery for a stale payload left by an interrupted cold-path
    -- recompile; the steady compiled Group route never enters this branch.
    ClearDirtyTextDispatch(frame, TEXT_DIRTY_HEALTH)
  end
end

local function MarkPowerTextDirty(frame)
  MarkDirtyText(frame, TEXT_DIRTY_POWER)
  ClearDirtyTextDispatch(frame, TEXT_DIRTY_POWER)
end

local function DirtyTextFrameVisible(frame)
  local visible = UF.FrameVisibleForEvent
  if type(visible) == "function" then return visible(frame) end
  if frame._msufCoreSpecEnabled == false or frame._msufCoreVisible == false then return false end
  return true
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

local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

function Text.SetDisplayNameResolver(resolver)
  if type(resolver) == "function" then
    ReadDisplayName = resolver
    displayNameResolverUsesFrame = true
  else
    ReadDisplayName = UnitName
    displayNameResolverUsesFrame = false
  end
end

if type(Text._pendingDisplayNameResolver) == "function" then
  Text.SetDisplayNameResolver(Text._pendingDisplayNameResolver)
  Text._pendingDisplayNameResolver = nil
end

local function MissingHealthFromValues(hp, hpMax)
  -- Missing health is derived from API values that may become secret. Return nil in that case
  -- so callers can keep the previous safe display instead of doing math on protected values.
  if issecretvalue(hp) == true or issecretvalue(hpMax) == true then
    return nil
  end
  if not IsFiniteNumber(hp) or not IsFiniteNumber(hpMax) then
    return nil
  end
  local missing = hpMax - hp
  return missing > 0 and missing or 0
end

local function ReadMissingHealth(unit, hp, hpMax)
  local missing = MissingHealthFromValues(hp, hpMax)
  if missing ~= nil then return missing end
  if UnitHealthMissing then return UnitHealthMissing(unit, true) end
  return nil
end

local function NormalizePercentDecimals(decimals)
  decimals = tonumber(decimals) or 0
  return decimals >= 1 and 1 or 0
end

local function PercentCacheKeyFromValue(pct, decimals)
  if type(pct) ~= "number" then
    return pct or false
  end
  if not IsFiniteNumber(pct) then
    return false
  end
  if NormalizePercentDecimals(decimals) >= 1 then
    return floor(pct * 10 + 0.5)
  end
  -- The zero-decimal writers use Lua's %d conversion, which truncates toward
  -- zero. The dedupe key must use the same quantization or a 49.6 -> 50.0
  -- transition can be skipped while the FontString still displays 49.
  return pct >= 0 and floor(pct) or -floor(-pct)
end

local function PercentFromValues(cur, maxValue)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true then return nil end
  if IsFiniteNumber(cur) and IsFiniteNumber(maxValue) and maxValue > 0 then
    return (cur / maxValue) * 100
  end
  return nil
end

local function ConsumeDispatchPercent(rt, valueKey, readyKey)
  if rt and rt[readyKey] == true then
    local pct = rt[valueKey]
    rt[valueKey] = nil
    rt[readyKey] = nil
    return pct, true
  end
  return nil, false
end

local function ClearGFHotHealthKeys(rt)
  if not rt then return end
  rt._msufGFHotHealthHP = nil
  rt._msufGFHotHealthMax = nil
  rt._msufGFHotHealthPercent = nil
  rt._msufGFHotHealthMissing = nil
end

local function ClearGFHotPowerKeys(rt)
  if not rt then return end
  rt._msufGFHotPower = nil
  rt._msufGFHotPowerMax = nil
  rt._msufGFHotPowerPercent = nil
end

local function WriteGFHotSlot(slot, cur, maxValue, pct, pctKnown, rt, missing)
  if not slot then return end
  if missing ~= nil then
    rt.healthMissing = missing
  end
  local curSecret = nativeSecrets and issecretvalue(cur) == true
  local maxSecret = nativeSecrets and issecretvalue(maxValue) == true
  local pctSecret = nativeSecrets and pctKnown == true and issecretvalue(pct) == true
  local missingSecret = nativeSecrets and missing ~= nil and issecretvalue(missing) == true
  if nativeSecrets and (curSecret or maxSecret or pctSecret or missingSecret) then
    local writer = slot.secretWriter or slot.writer
    if writer then writer(slot, cur, maxValue, pct, true, rt, curSecret, maxSecret, pctSecret) end
    return
  end
  local writer = slot.plainWriter or slot.writer
  if writer then writer(slot, cur, maxValue, pct, pctKnown == true, rt) end
end

local function GFHotHealthNeedsUpdate(frame, rt, unit, hp, hpMax)
  local pct, pctKnown = nil, false
  if nativeSecrets and (issecretvalue(hp) == true or issecretvalue(hpMax) == true) then
    if rt.healthNeedsPercent == true then
      pct = HealthPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
    ClearGFHotHealthKeys(rt)
    return true, pct, pctKnown, nil
  end
  if hp == nil or hpMax == nil then
    if rt.healthNeedsPercent == true then
      pct = HealthPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
    ClearGFHotHealthKeys(rt)
    return true, pct, pctKnown, nil
  end

  local keyMissing = false
  local missing
  if rt.healthNeedsMissing == true then
    missing = ReadMissingHealth(unit, hp, hpMax)
    if issecretvalue(missing) == true then
      ClearGFHotHealthKeys(rt)
      return true, nil, false, missing
    end
    keyMissing = missing or false
  end

  local keyPercent = false
  if rt.healthNeedsPercent == true then
    pct = PercentFromValues(hp, hpMax) or HealthPercent(unit)
    pctKnown = issecretvalue(pct) == true or pct ~= nil
    if issecretvalue(pct) == true then
      ClearGFHotHealthKeys(rt)
      return true, pct, true, missing
    end
    keyPercent = PercentCacheKeyFromValue(pct, rt.healthPercentDecimals)
    if keyPercent == false then
      ClearGFHotHealthKeys(rt)
      return true, pct, pctKnown, missing
    end
  end

  local keyHP = rt.healthNeedsCurrent == true and hp or false
  local keyMax = rt.healthNeedsMax == true and hpMax or false

  if rt._msufGFHotHealthHP == keyHP
    and rt._msufGFHotHealthMax == keyMax
    and rt._msufGFHotHealthPercent == keyPercent
    and rt._msufGFHotHealthMissing == keyMissing then
    return false, pct, pctKnown, missing
  end
  rt._msufGFHotHealthHP = keyHP
  rt._msufGFHotHealthMax = keyMax
  rt._msufGFHotHealthPercent = keyPercent
  rt._msufGFHotHealthMissing = keyMissing
  return true, pct, pctKnown, missing
end

local function GFHotPowerNeedsUpdate(rt, unit, power, powerMax)
  local pct, pctKnown = nil, false
  if nativeSecrets and (issecretvalue(power) == true or issecretvalue(powerMax) == true) then
    if rt.powerNeedsPercent == true then
      pct = PowerPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
    ClearGFHotPowerKeys(rt)
    return true, pct, pctKnown
  end
  if power == nil or powerMax == nil then
    if rt.powerNeedsPercent == true then
      pct = PowerPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
    ClearGFHotPowerKeys(rt)
    return true, pct, pctKnown
  end

  local keyPercent = false
  if rt.powerNeedsPercent == true then
    pct = PercentFromValues(power, powerMax) or PowerPercent(unit)
    pctKnown = issecretvalue(pct) == true or pct ~= nil
    if issecretvalue(pct) == true then
      ClearGFHotPowerKeys(rt)
      return true, pct, true
    end
    keyPercent = PercentCacheKeyFromValue(pct, 0)
    if keyPercent == false then
      ClearGFHotPowerKeys(rt)
      return true, pct, pctKnown
    end
  end

  local keyPower = rt.powerNeedsCurrent == true and power or false
  local keyMax = rt.powerNeedsMax == true and powerMax or false

  if rt._msufGFHotPower == keyPower
    and rt._msufGFHotPowerMax == keyMax
    and rt._msufGFHotPowerPercent == keyPercent then
    return false, pct, pctKnown
  end
  rt._msufGFHotPower = keyPower
  rt._msufGFHotPowerMax = keyMax
  rt._msufGFHotPowerPercent = keyPercent
  return true, pct, pctKnown
end

local function GFHotHealthCurrentNeedsUpdate(rt, unit, hp)
  local hpSecret = issecretvalue(hp) == true
  local pct, pctKnown = nil, false
  local keyPercent = false
  if rt.healthNeedsPercent == true then
    pct, pctKnown = ConsumeDispatchPercent(rt, "_dispatchHealthPercent", "_dispatchHealthPercentReady")
    if pctKnown ~= true then
      pct = HealthPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
  end
  if hpSecret or (pctKnown == true and issecretvalue(pct) == true) then
    ClearGFHotHealthKeys(rt)
    return true, pct, pctKnown
  end
  if hp == nil then
    ClearGFHotHealthKeys(rt)
    return true, pct, pctKnown
  end
  if rt.healthNeedsPercent == true then
    keyPercent = PercentCacheKeyFromValue(pct, rt.healthPercentDecimals)
    if keyPercent == false then
      ClearGFHotHealthKeys(rt)
      return true, pct, pctKnown
    end
  end
  if rt._msufGFHotHealthHP == hp
    and rt._msufGFHotHealthMax == false
    and rt._msufGFHotHealthPercent == keyPercent
    and rt._msufGFHotHealthMissing == false then
    return false, pct, pctKnown
  end
  rt._msufGFHotHealthHP = hp
  rt._msufGFHotHealthMax = false
  rt._msufGFHotHealthPercent = keyPercent
  rt._msufGFHotHealthMissing = false
  return true, pct, pctKnown
end

local function GFHotPowerCurrentNeedsUpdate(rt, unit, power)
  local powerSecret = issecretvalue(power) == true
  local pct, pctKnown = nil, false
  local keyPercent = false
  if rt.powerNeedsPercent == true then
    pct, pctKnown = ConsumeDispatchPercent(rt, "_dispatchPowerPercent", "_dispatchPowerPercentReady")
    if pctKnown ~= true then
      pct = PowerPercent(unit)
      pctKnown = issecretvalue(pct) == true or pct ~= nil
    end
  end
  if powerSecret or (pctKnown == true and issecretvalue(pct) == true) then
    ClearGFHotPowerKeys(rt)
    return true, pct, pctKnown
  end
  if power == nil then
    ClearGFHotPowerKeys(rt)
    return true, pct, pctKnown
  end
  if rt.powerNeedsPercent == true then
    keyPercent = PercentCacheKeyFromValue(pct, 0)
    if keyPercent == false then
      ClearGFHotPowerKeys(rt)
      return true, pct, pctKnown
    end
  end
  if rt._msufGFHotPower == power
    and rt._msufGFHotPowerMax == false
    and rt._msufGFHotPowerPercent == keyPercent then
    return false, pct, pctKnown
  end
  rt._msufGFHotPower = power
  rt._msufGFHotPowerMax = false
  rt._msufGFHotPowerPercent = keyPercent
  return true, pct, pctKnown
end

local function RegionShown(region)
  if not region then
    return false
  end
  if region._msufShown ~= nil then
    return region._msufShown == true
  end
  return region.IsShown and region:IsShown() or false
end

local function RefreshCachedPowerType(frame, unit)
  -- Power type changes less often than power values. Cache token/type per frame so frequent
  -- UNIT_POWER_UPDATE events do not repeatedly ask the client for display metadata.
  local cacheUnit = unit
  if not UnitPowerType then
    frame._msufTextPowerType = nil
    frame._msufTextPowerToken = nil
    frame._msufTextPowerTypeKnown = true
    frame._msufTextPowerTypeUnit = cacheUnit
    return false
  end
  local powerType, powerToken = UnitPowerType(unit)
  if issecretvalue(powerType) == true then powerType = nil end
  if issecretvalue(powerToken) == true then powerToken = nil end
  local oldUnit = frame._msufTextPowerTypeUnit
  local sameUnit = cacheUnit ~= nil and oldUnit == cacheUnit
  if powerType == nil
    and powerToken == nil
    and frame._msufTextPowerTypeKnown == true
    and sameUnit then
    return false
  end
  local changed = powerType ~= frame._msufTextPowerType
    or powerToken ~= frame._msufTextPowerToken
    or not sameUnit
  frame._msufTextPowerType = powerType
  frame._msufTextPowerToken = powerToken
  frame._msufTextPowerTypeKnown = true
  frame._msufTextPowerTypeUnit = cacheUnit
  return changed
end

local function SeedCachedPowerType(frame, unit, powerType, powerToken)
  if not frame then
    return false
  end
  if issecretvalue(powerType) == true or issecretvalue(powerToken) == true then
    return false
  end
  if powerType == nil and powerToken == nil then
    return false
  end
  local cacheUnit = unit
  local sameUnit = cacheUnit ~= nil and frame._msufTextPowerTypeUnit == cacheUnit
  local changed = frame._msufTextPowerTypeKnown ~= true
    or not sameUnit
    or powerType ~= frame._msufTextPowerType
    or powerToken ~= frame._msufTextPowerToken
  frame._msufTextPowerType = powerType
  frame._msufTextPowerToken = powerToken
  frame._msufTextPowerTypeKnown = true
  frame._msufTextPowerTypeUnit = cacheUnit
  return changed
end

local function SeedCachedPowerMax(frame, unit, powerMax, powerMaxSecret)
  if not frame then
    return false
  end
  if powerMaxSecret == true then
    frame._msufTextPowerMax = nil
    frame._msufTextPowerMaxUnit = nil
    return false
  end
  if powerMax == nil then
    return false
  end
  frame._msufTextPowerMax = powerMax
  frame._msufTextPowerMaxUnit = unit
  return true
end

local function ReadPowerValuesPlain(frame, unit, event, needPower, needMax, powerTick)
  local powerType
  if frame._msufTextPowerNeedsType == true then
    powerType = frame._msufTextPowerType
    local typeUnit = frame._msufTextPowerTypeUnit
    local typeUnitMatches = typeUnit == unit
    if frame._msufTextPowerTypeKnown ~= true
      or not typeUnitMatches
      or (not powerTick
        and (POWER_IDENTITY_EVENTS[event] == true
          or event == "UNIT_DISPLAYPOWER"
          or event == "UNIT_POWER_BAR_SHOW"
          or event == "UNIT_POWER_BAR_HIDE"
          or event == "MSUF_APPLY"
          or event == "MSUF_FORCE_UPDATE")) then
      RefreshCachedPowerType(frame, unit)
      powerType = frame._msufTextPowerType
    end
  end

  local power
  if needPower ~= false then
    if powerType ~= nil then
      power = UnitPower(unit, powerType)
    else
      power = UnitPower(unit)
    end
  end

  local maxPower = frame._msufTextPowerMax
  if issecretvalue(maxPower) == true then
    maxPower = nil
    frame._msufTextPowerMax = nil
    frame._msufTextPowerMaxUnit = nil
  end
  if needMax ~= false then
    local cacheUnit = unit
    local maxUnit = frame._msufTextPowerMaxUnit
    local maxUnitMatches = cacheUnit ~= nil
      and maxUnit == cacheUnit
    if maxPower == nil
      or not maxUnitMatches
      or (not powerTick
        and (POWER_IDENTITY_EVENTS[event] == true
          or event == "UNIT_MAXPOWER"
          or event == "UNIT_DISPLAYPOWER"
          or event == "UNIT_POWER_BAR_SHOW"
          or event == "UNIT_POWER_BAR_HIDE"
          or event == "MSUF_APPLY"
          or event == "MSUF_FORCE_UPDATE")) then
      if powerType ~= nil then
        maxPower = UnitPowerMax(unit, powerType)
      else
        maxPower = UnitPowerMax(unit)
      end
      if issecretvalue(maxPower) == true then
        frame._msufTextPowerMax = nil
        frame._msufTextPowerMaxUnit = nil
      else
        if maxPower == nil then maxPower = 1 end
        frame._msufTextPowerMax = maxPower
        frame._msufTextPowerMaxUnit = cacheUnit
      end
    end
  else
    maxPower = nil
  end

  if needPower ~= false and issecretvalue(power) ~= true and power == nil then power = 0 end
  return power, maxPower
end

local function ReadHealthValuesCached(frame, unit)
  local bar = frame and (frame.hpBar or frame.Health)
  if not bar then
    return nil, nil
  end
  local cacheUnit = unit
  local hpUnit = bar._msufHealthValueUnit
  local maxUnit = bar._msufHealthMaxUnit
  local hp = cacheUnit ~= nil and hpUnit == cacheUnit and bar._msufHealthValue or nil
  local hpMax
  if bar._msufHealthMaxReady == true
    and cacheUnit ~= nil
    and maxUnit == cacheUnit then
    hpMax = bar._msufHealthMax
  end
  return hp, hpMax
end

local function SeedCachedHealthMax(frame, unit, hpMax, event)
  if not frame then return false end
  if event == "UNIT_HEALTH"
    and frame._msufTextHealthMaxReady == true
    and frame._msufTextHealthMaxUnit == unit then
    return true
  end
  local secret = issecretvalue(hpMax) == true
  if not secret and hpMax == nil then return false end
  frame._msufTextHealthMax = hpMax
  frame._msufTextHealthMaxUnit = unit
  frame._msufTextHealthMaxReady = true
  return true
end

local function ReadHealthMaxCached(frame, unit, event)
  local sameUnit = frame and unit ~= nil and frame._msufTextHealthMaxUnit == unit
  if not frame or frame._msufTextHealthMaxReady ~= true or not sameUnit or event ~= "UNIT_HEALTH" then
    local hpMax = UnitHealthMax(unit)
    SeedCachedHealthMax(frame, unit, hpMax)
    return hpMax
  end
  -- This may be a secret value. It is an opaque native payload owned by the
  -- last UNIT_MAXHEALTH/identity refresh and must not be inspected here.
  return frame._msufTextHealthMax
end

local function UpdateRuntimeHealthTextColor(frame, rt, unit, hp, hpMax, pct, pctReady)
  if not (rt and rt.healthColorByHealth == true and UpdateHealthTextColor) then return end
  local hpMissing = issecretvalue(hp) ~= true and hp == nil
  local maxMissing = issecretvalue(hpMax) ~= true and hpMax == nil
  if (hpMissing or maxMissing) and pctReady == true then
    hp, hpMax = pct, 100
  end
  UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
end

function Text.UpdateNameColor(frame, event, unit)
  if RegionShown(frame and frame.nameText) then
    ApplyNameTextColor(frame, unit or frame.MSUFUnitKey)
    local rt = frame and frame._msufTextRuntime
    if rt and rt.inlineToT and frame._msufIdentityInlineToTScheduled ~= true then
      Text.UpdateInline(frame, event, unit)
    end
  end
end

function Text.UpdateInline(frame, event, unit)
  local rt = frame and frame._msufTextRuntime
  local inline = rt and rt.inlineToT
  if not inline then
    if frame and (frame.totInlineSep or frame.totInlineText) then
      SetShownCached(frame.totInlineSep, false)
      SetShownCached(frame.totInlineText, false)
      SetShownCached(frame._msufInlineDotsFS, false)
    end
    return
  end

  local inlineUnit = inline.unit or "targettarget"
  if (event == "UNIT_NAME_UPDATE" or event == "UNIT_CLASSIFICATION_CHANGED") and unit and unit ~= inlineUnit then
    return
  end
  if not (frame.totInlineSep and frame.totInlineText) then
    return
  end

  if UnitMissing(inlineUnit) then
    SetShownCached(frame.totInlineSep, false)
    SetShownCached(frame.totInlineText, false)
    SetShownCached(frame._msufInlineDotsFS, false)
    frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
    return
  end

  local stamp = inline.stamp
  if frame._msufInlineStamp ~= stamp then
    SetTextCached(frame.totInlineSep, inline.separator)
    frame._msufInlineStamp = stamp
  end
  local name
  if displayNameResolverUsesFrame then
    name = ReadDisplayName(inlineUnit, frame)
  else
    name = ReadDisplayName(inlineUnit)
  end
  SetTextCached(frame.totInlineText, name)
  if AnchorInlineToName then
    AnchorInlineToName(frame)
  end
  SetShownCached(frame.totInlineSep, true)
  SetShownCached(frame.totInlineText, true)
  ApplyInlineTextColor(frame, inlineUnit, inline)
end

local function SetNameTextCached(frame, value)
  SetTextCached(frame.nameText, value)
  local proxy = frame._msufNameAnchorTextActive == true and frame._msufNameAnchorText
  if proxy then SetTextCached(proxy, value) end
  -- Any no-ellipsis clip window (side or centered) needs the warm fit: it
  -- tracks whether the name really overflows the window, which decides the
  -- NAMELEFT/NAMERIGHT status anchor target.
  if frame._msufNameInlineClip ~= nil and RefreshNameCenterClipFit then
    RefreshNameCenterClipFit(frame)
  end
end

-- Native 5.73 Group Frames shortened the actual UTF-8 name and only added
-- dots when its character count exceeded the configured cap. Preserve that
-- behavior for migrated Group profiles instead of showing 6.0's separate
-- clip-marker FontString for every name while shortening is merely enabled.
local function TruncateLegacyGroupName(name, rt)
  local maxChars = rt and rt.nameLegacyTruncation == true and tonumber(rt.nameLegacyShortenMax) or 0
  maxChars = floor((maxChars or 0) + 0.5)
  if name == nil or maxChars <= 0 or issecretvalue(name) == true then return name end

  local function NextByte(pos)
    local byte = string.byte(name, pos)
    if not byte then return pos + 1 end
    if byte < 128 then return pos + 1 end
    if byte < 224 then return pos + 2 end
    if byte < 240 then return pos + 3 end
    return pos + 4
  end

  local count, pos, byteLength = 0, 1, #name
  while pos <= byteLength do
    count = count + 1
    pos = NextByte(pos)
  end
  if count <= maxChars then return name end

  local dots = rt.nameLegacyShortenDots == true and ".." or ""
  if rt.nameShortenSide == "LEFT" then
    pos = 1
    for _ = 1, count - maxChars do pos = NextByte(pos) end
    return dots .. string.sub(name, pos)
  end

  count, pos = 0, 1
  while pos <= byteLength and count < maxChars do
    count = count + 1
    pos = NextByte(pos)
  end
  return string.sub(name, 1, pos - 1) .. dots
end

function Text.UpdateName(frame, event, unit)
  local frameUnit = frame and frame.MSUFUnitKey
  unit = unit or frameUnit
  if frameUnit and unit ~= frameUnit then
    Text.UpdateInline(frame, event, unit)
    return
  end
  local rt = frame and frame._msufTextRuntime
  if not (frame and frame.nameText) then
    return
  end
  if not frameUnit or frameUnit == "" then
    frame._msufNameStatusUnit = nil
    frame._msufNameStatusHidden = nil
    frame._msufNameTextUnit = nil
    SetNameTextCached(frame, "")
    frame.nameText._msufShown = nil
    SetShownCached(frame.nameText, false)
    return
  end
  unit = frameUnit
  local previewName = frame._msufPreviewNameText
  if type(previewName) == "string" and previewName ~= "" then
    frame._msufNameStatusUnit = nil
    frame._msufNameStatusHidden = nil
    frame.nameText._msufShown = nil
    SetShownCached(frame.nameText, true)
    SetNameTextCached(frame, TruncateLegacyGroupName(previewName, rt))
    frame._msufNameTextUnit = unit
    Text.UpdateNameColor(frame, event, unit)
    return
  end
  if rt and rt.showName == false then
    frame._msufNameStatusUnit = nil
    frame._msufNameStatusHidden = nil
    frame._msufNameTextUnit = nil
    SetNameTextCached(frame, "")
    frame.nameText._msufShown = nil
    SetShownCached(frame.nameText, false)
    return
  end
  if rt and rt.hideNameOnDeadOffline == true then
    local connected, connectedKnown = ReadConnectedCached(frame, unit)
    local hidden = false
    if connectedKnown == true and connected == false then
      hidden = true
    else
      local dead, deadKnown = ReadDeadCached(frame, unit)
      if deadKnown == true and dead == true then
        hidden = true
      end
    end
    local statusUnchanged = frame._msufNameStatusUnit == unit
      and frame._msufNameStatusHidden == hidden
    if statusUnchanged then
      if event == "UNIT_HEALTH" then
        return
      elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
        if hidden then
          if frame.nameText._msufShown == false then
            return
          end
        elseif frame.nameText._msufShown == true then
          return
        end
      end
    end
    frame._msufNameStatusUnit = unit
    frame._msufNameStatusHidden = hidden
    if hidden then
      frame._msufNameTextUnit = nil
      SetNameTextCached(frame, "")
      frame.nameText._msufShown = nil
      SetShownCached(frame.nameText, false)
      return
    end
  else
    frame._msufNameStatusUnit = nil
    frame._msufNameStatusHidden = nil
  end
  frame.nameText._msufShown = nil
  SetShownCached(frame.nameText, true)
  if frame._msufNameTextUnit == unit
    and frame.nameText._msufShown == true
    and (event == "UNIT_CONNECTION"
      or event == "UNIT_FLAGS"
      or event == "UNIT_FACTION"
      or event == "UNIT_CLASSIFICATION_CHANGED") then
    Text.UpdateNameColor(frame, event, unit)
    return
  end
  local displayName
  if displayNameResolverUsesFrame then
    displayName = ReadDisplayName(unit, frame)
  else
    displayName = ReadDisplayName(unit)
  end
  SetNameTextCached(frame, TruncateLegacyGroupName(displayName, rt))
  frame._msufNameTextUnit = unit
  Text.UpdateNameColor(frame, event, unit)
end

local function UpdateHealthRuntime(frame, event, unit, hp, hpMax)
  unit = unit or frame.MSUFUnitKey
  local rt = frame._msufTextRuntime
  if not rt or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
    return
  end

  local healthTick = event == "UNIT_HEALTH"
  local needsPercent = rt.healthNeedsPercent == true
  local needsCurrent = rt.healthNeedsCurrent == true
  local needsMax = rt.healthNeedsMax == true
  local colorByHealth = rt.healthColorByHealth == true
  local needHPValue = needsCurrent
  local needMaxValue = needsMax
  local hpMissing = issecretvalue(hp) ~= true and hp == nil
  local maxMissing = issecretvalue(hpMax) ~= true and hpMax == nil
  local colorNeedsPercent = colorByHealth and (hpMissing or maxMissing)
  local pctOverride, pctOverrideSet
  if needsPercent or colorNeedsPercent then
    pctOverride, pctOverrideSet = ConsumeDispatchPercent(rt, "_dispatchHealthPercent", "_dispatchHealthPercentReady")
  end
  SeedCachedHealthMax(frame, unit, hpMax, event)

  if rt.healthPlain == true then
    if (needHPValue and hp == nil) or (needMaxValue and hpMax == nil) then
      local cachedHP, cachedMax = ReadHealthValuesCached(frame, unit)
      if needHPValue and hp == nil then
        hp = cachedHP
      end
      if needMaxValue and hpMax == nil then
        hpMax = cachedMax
      end
    end
    if needHPValue and hp == nil then
      hp = UnitHealth(unit)
    end
    if needMaxValue and hpMax == nil then
      hpMax = ReadHealthMaxCached(frame, unit, event)
    end

    if rt.healthNeedsMissing == true then
      if healthTick and rt._dispatchHealthMissingReady == true then
        rt.healthMissing = rt._dispatchHealthMissing
        rt._dispatchHealthMissingReady = nil
        rt._dispatchHealthMissing = nil
      else
        rt._dispatchHealthMissingReady = nil
        rt._dispatchHealthMissing = nil
        rt.healthMissing = ReadMissingHealth(unit, hp, hpMax)
      end
    else
      rt._dispatchHealthMissingReady = nil
      rt._dispatchHealthMissing = nil
      rt.healthMissing = nil
    end

    if needHPValue and hp == nil then
      hp = 0
    end
    if needMaxValue and hpMax == nil then
      hpMax = 1
    end

    if nativeSecrets and (issecretvalue(hp) == true
      or issecretvalue(hpMax) == true
      or issecretvalue(rt.healthMissing) == true) then
      rt._lastHealthTextHP = nil
      rt._lastHealthTextMax = nil
      rt._lastHealthTextMissing = nil
      rt._dispatchHealthTextHP = nil
      rt._dispatchHealthTextMax = nil
      rt._dispatchHealthTextMissing = nil
      UpdateTextSlotsSecret(rt.healthSlots, rt.healthValueSlotCount or rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
      return
    end

    if (needsPercent or colorNeedsPercent) and pctOverrideSet ~= true then
      pctOverride = PercentFromValues(hp, hpMax)
      pctOverrideSet = pctOverride ~= nil
      if pctOverrideSet ~= true and HealthPercentAvailable then
        pctOverride = HealthPercent(unit)
        pctOverrideSet = issecretvalue(pctOverride) == true or pctOverride ~= nil
      end
    end
    if nativeSecrets and pctOverrideSet == true and issecretvalue(pctOverride) == true then
      rt._lastHealthTextHP = nil
      rt._lastHealthTextMax = nil
      rt._lastHealthTextMissing = nil
      rt._dispatchHealthTextHP = nil
      rt._dispatchHealthTextMax = nil
      rt._dispatchHealthTextMissing = nil
      UpdateTextSlotsSecret(rt.healthSlots, rt.healthValueSlotCount or rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
      return
    end
    local keyHP, keyMax = false, false
    local canCompareText = true
    local mode = rt.healthDispatchKeyMode or 0
    if mode == 1 then
      keyHP = hp
    elseif mode == 2 then
      keyMax = hpMax
    elseif mode == 3 then
      keyHP, keyMax = hp, hpMax
    elseif mode == 4 or mode == 5 then
      if pctOverrideSet and issecretvalue(pctOverride) ~= true then
        keyHP = PercentCacheKeyFromValue(pctOverride, rt.healthPercentDecimals)
      else
        canCompareText = false
      end
      if keyHP == nil or keyHP == false then
        canCompareText = false
        keyHP = false
      end
      keyMax = canCompareText and mode == 5 and hpMax or false
    end
    local valueRefreshEvent = healthTick or event == "UNIT_CONNECTION" or event == "UNIT_MAXHEALTH"
    if valueRefreshEvent
      and canCompareText
      and rt._lastHealthTextHP == keyHP
      and rt._lastHealthTextMax == keyMax
      and rt._lastHealthTextMissing == rt.healthMissing then
      return
    end
    if canCompareText then
      rt._lastHealthTextHP = keyHP
      rt._lastHealthTextMax = keyMax
      rt._lastHealthTextMissing = rt.healthMissing
    else
      rt._lastHealthTextHP = nil
      rt._lastHealthTextMax = nil
      rt._lastHealthTextMissing = nil
    end
    UpdateRuntimeHealthTextColor(frame, rt, unit, hp, hpMax, pctOverride, pctOverrideSet)
    UpdateTextSlotsPlain(rt.healthSlots, rt.healthValueSlotCount or rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
    return
  end

  local hpSecret = issecretvalue(hp) == true
  local hpMaxSecret = issecretvalue(hpMax) == true
  if (needHPValue and not hpSecret and hp == nil) or (needMaxValue and not hpMaxSecret and hpMax == nil) then
    local cachedHP, cachedMax = ReadHealthValuesCached(frame, unit)
    if needHPValue and not hpSecret and hp == nil then
      hp = cachedHP
      hpSecret = issecretvalue(hp) == true
    end
    if needMaxValue and not hpMaxSecret and hpMax == nil then
      hpMax = cachedMax
      hpMaxSecret = issecretvalue(hpMax) == true
    end
  end
  if needHPValue and not hpSecret and hp == nil then
    hp = UnitHealth(unit)
    hpSecret = issecretvalue(hp) == true
  end
  if needMaxValue and not hpMaxSecret and hpMax == nil then
    hpMax = ReadHealthMaxCached(frame, unit, event)
    hpMaxSecret = issecretvalue(hpMax) == true
  end

  rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax

  if rt.healthNeedsMissing == true then
    rt.healthMissing = ReadMissingHealth(unit, hp, hpMax)
  else
    rt.healthMissing = nil
  end

  if (needsPercent or colorNeedsPercent) and pctOverrideSet ~= true then
    pctOverride = PercentFromValues(hp, hpMax)
    pctOverrideSet = pctOverride ~= nil
    if pctOverrideSet ~= true and HealthPercentAvailable then
      pctOverride = HealthPercent(unit)
      pctOverrideSet = issecretvalue(pctOverride) == true or pctOverride ~= nil
    end
  end
  UpdateRuntimeHealthTextColor(frame, rt, unit, hp, hpMax, pctOverride, pctOverrideSet)
  UpdateTextSlotsSecret(rt.healthSlots, rt.healthValueSlotCount or rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
end

local function UpdateAbsorbRuntime(frame, event, unit, skipCombinedRefresh)
  unit = unit or frame.MSUFUnitKey
  local rt = frame._msufTextRuntime
  local count = rt and rt.healthAbsorbSlotCount or 0
  local combinedCount = rt and rt.healthCombinedAbsorbSlotCount or 0
  if count + combinedCount <= 0 then return end

  local absorb = 0
  if UnitGetTotalAbsorbs then absorb = UnitGetTotalAbsorbs(unit) end
  local secret = nativeSecrets and issecretvalue(absorb) == true
  if not secret and rt._lastAbsorbTextValue == absorb then return end
  rt._lastAbsorbTextValue = secret and nil or absorb
  rt.healthAbsorb = absorb
  if count > 0 then
    if secret then
      UpdateTextSlotsSecret(rt.healthAbsorbSlots, count, nil, nil, unit, nil, false, rt)
    else
      UpdateTextSlotsPlain(rt.healthAbsorbSlots, count, nil, nil, unit, nil, false, rt)
    end
  end
  if combinedCount > 0 and skipCombinedRefresh ~= true then
    rt._lastHealthTextHP = nil
    rt._lastHealthTextMax = nil
    rt._lastHealthTextMissing = nil
    UpdateHealthRuntime(frame, event, unit)
  elseif combinedCount <= 0 then
    rt.healthAbsorb = nil
  end
end

local function UpdatePowerRuntime(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  unit = unit or frame.MSUFUnitKey
  local rt = frame._msufTextRuntime
  if not rt or not rt.powerSlotCount or rt.powerSlotCount <= 0 then
    return
  end
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  local identityChanged = not animate and POWER_IDENTITY_EVENTS[event] == true
  if identityChanged then
    frame._msufTextPowerType = nil
    frame._msufTextPowerToken = nil
    frame._msufTextPowerTypeKnown = nil
    frame._msufTextPowerTypeUnit = nil
    frame._msufTextPowerMax = nil
    frame._msufTextPowerMaxUnit = nil
    local seededPowerType = SeedCachedPowerType(frame, unit, powerType, powerToken)
    if rt.powerColorByType == true and seededPowerType ~= true then
      RefreshCachedPowerType(frame, unit)
    end
  elseif not (powerMetaChanged == false
      and animate
      and frame._msufTextPowerTypeKnown == true
      and frame._msufTextPowerTypeUnit == unit
      and issecretvalue(powerType) ~= true
      and issecretvalue(powerToken) ~= true
      and (powerType ~= nil or powerToken ~= nil)
      and frame._msufTextPowerType == powerType
      and frame._msufTextPowerToken == powerToken) then
    -- Power already resolved this metadata for a normal value tick. Preserve
    -- the seed for text-only/bar-missing and unknown/secret payloads, but do
    -- not rewrite four identical cache fields on every bar-fed update.
    SeedCachedPowerType(frame, unit, powerType, powerToken)
  end
  local powerMaxSecret = issecretvalue(powerMax) == true
  if powerMaxSecret or powerMax ~= nil then
    SeedCachedPowerMax(frame, unit, powerMax, powerMaxSecret)
  end
  if rt.powerColorByType == true
    and animate
    and rt.powerRefreshTypeOnTick == true
  then
    local typeUnit = frame._msufTextPowerTypeUnit
    local typeUnitMatches = typeUnit == unit
    if frame._msufTextPowerTypeKnown ~= true or not typeUnitMatches then
      RefreshCachedPowerType(frame, unit)
    end
  end
  local typeUnit = frame._msufTextPowerTypeUnit
  local typeUnitMatches = typeUnit == unit
  local powerTextColorEvent = not animate
    and (event == "UNIT_DISPLAYPOWER"
      or event == "MSUF_APPLY"
      or event == "MSUF_FORCE_UPDATE"
      or event == "MSUF_POWER_LAYOUT"
      or event == "MSUF_POWER_TEXT_COLORS")
  if rt.powerColorByType == true
    and (powerTextColorEvent
      or frame._msufPowerTextColorInitialized ~= true
      or not typeUnitMatches
      or frame._msufPowerTextColorType ~= frame._msufTextPowerType
      or frame._msufPowerTextColorToken ~= frame._msufTextPowerToken) then
    if frame._msufTextPowerTypeKnown ~= true or not typeUnitMatches then
      RefreshCachedPowerType(frame, unit)
      typeUnit = frame._msufTextPowerTypeUnit
      typeUnitMatches = typeUnit == unit
    end
    local metaKnown = frame._msufTextPowerTypeKnown == true and typeUnitMatches
    local r, g, b = PowerColor(
      frame, unit,
      frame._msufTextPowerType, frame._msufTextPowerToken,
      metaKnown
    )
    SetPowerTextColor(frame, r, g, b, rt.textColorA or 1)
    frame._msufPowerTextColorInitialized = true
    frame._msufPowerTextColorType = frame._msufTextPowerType
    frame._msufPowerTextColorToken = frame._msufTextPowerToken
  elseif rt.powerColorByType == false
    and (powerTextColorEvent
      or frame._msufPowerTextColorInitialized ~= true
      or frame._msufPowerTextColorType ~= false) then
    SetPowerTextColor(frame, rt.textColorR or 1, rt.textColorG or 1, rt.textColorB or 1, rt.textColorA or 1)
    frame._msufPowerTextColorInitialized = true
    frame._msufPowerTextColorType = false
    frame._msufPowerTextColorToken = nil
  end

  local needsPercent = rt.powerNeedsPercent == true
  local needsCurrent = rt.powerNeedsCurrent == true
  local needsMax = rt.powerNeedsMax == true
  local percentNeedsValues = false
  local needPowerValue = needsCurrent or percentNeedsValues
  local needMaxValue = needsMax or percentNeedsValues

  if rt.powerPlain == true then
    if (needPowerValue and power == nil) or (needMaxValue and powerMax == nil) then
      local currentPower, currentMax = ReadPowerValuesPlain(frame, unit, event, needPowerValue and power == nil, needMaxValue and powerMax == nil, animate)
      if needPowerValue and power == nil then
        power = currentPower
      end
      if needMaxValue and powerMax == nil then
        powerMax = currentMax
      end
    end
    rt.healthMissing = nil

    if needPowerValue and power == nil then
      power = 0
    end
    if needMaxValue and powerMax == nil then
      powerMax = 1
    end

    local pctOverride, pctOverrideSet
    if needsPercent then
      pctOverride, pctOverrideSet = ConsumeDispatchPercent(rt, "_dispatchPowerPercent", "_dispatchPowerPercentReady")
    end

    if nativeSecrets and (issecretvalue(power) == true or issecretvalue(powerMax) == true) then
      rt._lastPowerTextPower = nil
      rt._lastPowerTextMax = nil
      rt._dispatchPowerTextPower = nil
      rt._dispatchPowerTextMax = nil
      UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt, pctOverride, pctOverrideSet)
      return
    end

    if needsPercent and pctOverrideSet ~= true then
      pctOverride = PercentFromValues(power, powerMax)
      pctOverrideSet = pctOverride ~= nil
      if pctOverrideSet ~= true and PowerPercentAvailable then
        pctOverride = PowerPercent(unit)
        pctOverrideSet = issecretvalue(pctOverride) == true or pctOverride ~= nil
      end
    end
    local keyPower, keyMax = false, false
    local canCompareText = true
    local mode = rt.powerDispatchKeyMode or 0
    if mode == 1 then
      keyPower = power
    elseif mode == 2 then
      keyMax = powerMax
    elseif mode == 3 then
      keyPower, keyMax = power, powerMax
    elseif mode == 4 or mode == 5 then
      if pctOverrideSet and issecretvalue(pctOverride) ~= true then
        keyPower = PercentCacheKeyFromValue(pctOverride, 0)
        if keyPower == false then
          canCompareText = false
        end
      else
        canCompareText = false
      end
      keyMax = mode == 5 and powerMax or false
    end
    local powerValueRefreshEvent = animate
      or event == "UNIT_MAXPOWER"
      or event == "UNIT_DISPLAYPOWER"
      or event == "UNIT_POWER_BAR_SHOW"
      or event == "UNIT_POWER_BAR_HIDE"
    if powerValueRefreshEvent
      and canCompareText
      and mode ~= 0
      and rt._lastPowerTextPower == keyPower
      and rt._lastPowerTextMax == keyMax then
      return
    end
    if canCompareText then
      rt._lastPowerTextPower = keyPower
      rt._lastPowerTextMax = keyMax
    else
      rt._lastPowerTextPower = nil
      rt._lastPowerTextMax = nil
    end
    UpdateTextSlotsPlain(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt, pctOverride, pctOverrideSet)
    return
  end

  local powerSecret = issecretvalue(power) == true
  local powerMaxSecret = issecretvalue(powerMax) == true
  if not powerSecret and not powerMaxSecret
    and ((needPowerValue and power == nil) or (needMaxValue and powerMax == nil)) then
    local currentPower, currentMax = ReadPowerValuesPlain(frame, unit, event, needPowerValue and power == nil, needMaxValue and powerMax == nil, animate)
    if needPowerValue and power == nil then
      power = currentPower
      powerSecret = issecretvalue(power) == true
    end
    if needMaxValue and powerMax == nil then
      powerMax = currentMax
      powerMaxSecret = issecretvalue(powerMax) == true
    end
  end
  rt.healthMissing = nil

  rt._lastPowerRaw, rt._lastPowerMaxRaw = power, powerMax

  local pctOverride, pctOverrideSet
  if needsPercent then
    pctOverride, pctOverrideSet = ConsumeDispatchPercent(rt, "_dispatchPowerPercent", "_dispatchPowerPercentReady")
    if pctOverrideSet ~= true then
      pctOverride = PercentFromValues(power, powerMax)
      pctOverrideSet = pctOverride ~= nil
      if pctOverrideSet ~= true and PowerPercentAvailable then
        pctOverride = PowerPercent(unit)
        pctOverrideSet = issecretvalue(pctOverride) == true or pctOverride ~= nil
      end
    end
  end
  UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt, pctOverride, pctOverrideSet)
end

Text.RuntimeHotFunctions = {
  healthHot = UpdateHealthRuntime,
  healthDirty = MarkHealthTextDirty,
  groupHealthDirty = MarkGroupHealthTextDirty,
  absorbHot = UpdateAbsorbRuntime,
  powerHot = UpdatePowerRuntime,
  powerDirty = MarkPowerTextDirty,
}

Text.UpdateHealth = UpdateHealthRuntime
Text.UpdateAbsorb = UpdateAbsorbRuntime
Text.UpdatePower = UpdatePowerRuntime

local NAME_EVENTS = { "UNIT_NAME_UPDATE" }
local NAME_COLOR_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED" }
local NAME_STATUS_COLOR_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" }
local NAME_STATUS_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FLAGS", "UNIT_CONNECTION" }
local NAME_STATUS_PLAYER_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FLAGS" }
local NAME_STATUS_COLD_EVENTS = NAME_STATUS_EVENTS
local HEALTH_TEXT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }
local HEALTH_TEXT_PLAYER_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local HEALTH_TEXT_VALUE_EVENTS = { "UNIT_HEALTH", "UNIT_CONNECTION" }
local HEALTH_TEXT_VALUE_PLAYER_EVENTS = { "UNIT_HEALTH" }
local HEALTH_TEXT_MAX_EVENTS = { "UNIT_MAXHEALTH" }
local HEALTH_TEXT_CLASS_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_NAME_UPDATE" }
local HEALTH_TEXT_CLASS_VALUE_EVENTS = { "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_NAME_UPDATE" }
local HEALTH_TEXT_CLASS_MAX_EVENTS = { "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }
local ABSORB_TEXT_EVENTS = { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION" }
local ABSORB_TEXT_PLAYER_EVENTS = { "UNIT_ABSORB_AMOUNT_CHANGED" }
local ABSORB_TEXT_CLASS_EVENTS = { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION", "UNIT_NAME_UPDATE" }
local HEALTH_TEXT_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_PLAYER_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_VALUE_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_VALUE_PLAYER_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_MAX_EVENTS_ABSORB = { "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_MAX_PLAYER_EVENTS_ABSORB = { "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_CLASS_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_CLASS_VALUE_EVENTS_ABSORB = { "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" }
local HEALTH_TEXT_CLASS_MAX_EVENTS_ABSORB = { "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" }
local INLINE_TARGET_EVENTS = { "UNIT_TARGET" }
local INLINE_NAME_UNITLESS_EVENTS = { "UNIT_NAME_UPDATE" }
local INLINE_COLOR_UNITLESS_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED" }

local function NameNeedsNPCColorEvents(text)
  if not text then
    return false
  end
  if NPCTypeTextColorEnabled and NPCTypeTextColorEnabled(text) then
    return true
  end
  return type(text.nameColor) ~= "table"
    and (text.nameNpcColor == true or text.nameNpcClassColor == true)
end

local function ModeEnabled(mode)
  return mode ~= nil and mode ~= "NONE"
end

local function PowerModeNeedsValueTicks(mode)
  if not ModeEnabled(mode) then
    return false
  end
  return mode ~= "MAX"
end

local TEXT_MAX_EVENT_MODES = {
  MAX = true,
  CURMAX = true,
  MAXCUR = true,
  PERCENT = true,
  CURPERCENT = true,
  PERCENTCUR = true,
  CURMAXPERCENT = true,
  PERCENTMAXCUR = true,
  MAXPERCENT = true,
  PERCENTMAX = true,
  PERCENTCURMAX = true,
}

local function PowerModeNeedsMaxEvents(mode)
  return TEXT_MAX_EVENT_MODES[mode] == true
end

local function HealthModeNeedsValueTicks(mode)
  if not ModeEnabled(mode) then
    return false
  end
  mode = ABSORB_HEALTH_MODE_BASE[mode] or mode
  return mode ~= "MAX" and mode ~= "ABSORB"
end

local function HealthModeNeedsMaxEvents(mode)
  mode = ABSORB_HEALTH_MODE_BASE[mode] or mode
  if mode == "ABSORB" then return false end
  return mode == "DEFICIT" or TEXT_MAX_EVENT_MODES[mode] == true
end

local function HealthTextNeedsAbsorbEvents(spec)
  local left, center, right = ResolveHealthTextModes(spec and spec.text)
  return left == "ABSORB" or center == "ABSORB" or right == "ABSORB"
    or ABSORB_HEALTH_MODE_BASE[left] ~= nil
    or ABSORB_HEALTH_MODE_BASE[center] ~= nil
    or ABSORB_HEALTH_MODE_BASE[right] ~= nil
end

local function HealthTextEnabled(spec)
  if not (spec and spec.showHealthText ~= false) then
    return false
  end
  local left, center, right = ResolveHealthTextModes(spec.text)
  return ModeEnabled(left) or ModeEnabled(center) or ModeEnabled(right)
end

local function HealthTextNeedsValueTicks(spec)
  local text = spec and spec.text
  if text and text.healthColorByHealth == true then
    return true
  end
  local left, center, right = ResolveHealthTextModes(text)
  return HealthModeNeedsValueTicks(left)
    or HealthModeNeedsValueTicks(center)
    or HealthModeNeedsValueTicks(right)
end

local function HealthTextNeedsMaxEvents(spec)
  local text = spec and spec.text
  if text and text.healthColorByHealth == true then
    return true
  end
  local left, center, right = ResolveHealthTextModes(text)
  return HealthModeNeedsMaxEvents(left)
    or HealthModeNeedsMaxEvents(center)
    or HealthModeNeedsMaxEvents(right)
end

local function PowerTextEnabled(spec)
  if not (spec and spec.showPowerText ~= false) then
    return false
  end
  local text = spec.text or {}
  return ModeEnabled(text.powerLeft) or ModeEnabled(text.powerCenter) or ModeEnabled(text.powerRight)
end

local function PowerTextNeedsValueTicks(spec)
  local text = spec and spec.text
  return PowerModeNeedsValueTicks(text and text.powerLeft)
    or PowerModeNeedsValueTicks(text and text.powerCenter)
    or PowerModeNeedsValueTicks(text and text.powerRight)
end

local function PowerTextNeedsMaxEvents(spec)
  local text = spec and spec.text
  return PowerModeNeedsMaxEvents(text and text.powerLeft)
    or PowerModeNeedsMaxEvents(text and text.powerCenter)
    or PowerModeNeedsMaxEvents(text and text.powerRight)
end

local function InlineEnabled(frame, spec)
  local text = spec and spec.text
  local inline = text and text.inlineToT
  return frame and frame.MSUFUnitKey == "target" and spec and spec.showName ~= false and inline and inline.enabled == true
end

local function GFHotHealthPercentNeedsUpdate(rt, pct)
  local pctSecret = issecretvalue(pct) == true
  if pctSecret then
    ClearGFHotHealthKeys(rt)
    return true, true
  end
  local keyHP = PercentCacheKeyFromValue(pct, rt.healthPercentDecimals)
  if keyHP == false then
    ClearGFHotHealthKeys(rt)
    return true, pct ~= nil
  end
  if rt._msufGFHotHealthHP == keyHP and rt._msufGFHotHealthMax == false then
    return false, pct ~= nil
  end
  rt._msufGFHotHealthHP = keyHP
  rt._msufGFHotHealthMax = false
  rt._msufGFHotHealthMissing = false
  return true, pct ~= nil
end

local function BuildGFHotHealthTextFromPercent(frame, rt)
  if not (rt
    and (rt.healthCombinedAbsorbSlotCount or 0) == 0
    and rt.healthValueSlotCount == 1
    and rt.healthColorByHealth ~= true
    and rt.healthDispatchKeyMode == 4
    and rt.healthNeedsCurrent ~= true
    and rt.healthNeedsMax ~= true
    and rt.healthNeedsMissing ~= true) then
    return nil
  end
  local slot = rt.healthSlots and rt.healthSlots[1]
  if not (slot and (slot.plainWriter or slot.secretWriter or slot.writer)) then
    return nil
  end
  ClearGFHotHealthKeys(rt)
  return function(frame, event, unit, pct)
    local update, pctKnown = GFHotHealthPercentNeedsUpdate(rt, pct)
    if not update then return end
    rt.healthMissing = nil
    rt._lastHpRaw, rt._lastHpMaxRaw = nil, nil
    WriteGFHotSlot(slot, nil, nil, pct, pctKnown, rt)
  end
end

local function BuildGFHotHealthText(frame, rt)
  if not (rt and (rt.healthCombinedAbsorbSlotCount or 0) == 0
    and rt.healthValueSlotCount == 1 and rt.healthColorByHealth ~= true) then
    return nil
  end
  local slot = rt.healthSlots and rt.healthSlots[1]
  if not (slot and (slot.plainWriter or slot.secretWriter or slot.writer)) then
    return nil
  end
  local partialCurrent = rt.healthNeedsCurrent == true
    and rt.healthNeedsMax ~= true
    and rt.healthNeedsMissing ~= true
  ClearGFHotHealthKeys(rt)
  return function(frame, event, unit, hp, hpMax)
    local hpSecret = issecretvalue(hp) == true
    local maxSecret = issecretvalue(hpMax) == true
    if not maxSecret and hpMax == nil then
      if partialCurrent and (hpSecret or hp ~= nil) then
        local update, pct, pctKnown = GFHotHealthCurrentNeedsUpdate(rt, unit, hp)
        if not update then return end
        rt.healthMissing = nil
        rt._lastHpRaw, rt._lastHpMaxRaw = hp, nil
        return WriteGFHotSlot(slot, hp, nil, pct, pctKnown, rt)
      end
      return UpdateHealthRuntime(frame, event, unit, hp, hpMax)
    end
    if not hpSecret and hp == nil then return UpdateHealthRuntime(frame, event, unit, hp, hpMax) end
    local update, pct, pctKnown, missing = GFHotHealthNeedsUpdate(frame, rt, unit, hp, hpMax)
    if not update then return end
    rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax
    if rt.healthNeedsMissing == true then
      rt.healthMissing = missing
    else
      rt.healthMissing = nil
    end
    WriteGFHotSlot(slot, hp, hpMax, pct, pctKnown, rt, missing)
  end
end

local function BuildGFHotPowerText(frame, rt)
  if not (rt and rt.powerSlotCount == 1 and rt.powerColorByType ~= true) then
    return nil
  end
  local slot = rt.powerSlots and rt.powerSlots[1]
  if not (slot and (slot.plainWriter or slot.secretWriter or slot.writer)) then
    return nil
  end
  local partialCurrent = rt.powerNeedsCurrent == true and rt.powerNeedsMax ~= true
  ClearGFHotPowerKeys(rt)
  return function(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    local powerSecret = issecretvalue(power) == true
    local maxSecret = issecretvalue(powerMax) == true
    if not maxSecret and powerMax == nil then
      if partialCurrent and (powerSecret or power ~= nil) then
        local update, pct, pctKnown = GFHotPowerCurrentNeedsUpdate(rt, unit, power)
        if not update then return end
        rt._lastPowerRaw, rt._lastPowerMaxRaw = power, nil
        return WriteGFHotSlot(slot, power, nil, pct, pctKnown, rt)
      end
      return UpdatePowerRuntime(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    if not powerSecret and power == nil then
      return UpdatePowerRuntime(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    local update, pct, pctKnown = GFHotPowerNeedsUpdate(rt, unit, power, powerMax)
    if not update then return end
    rt._lastPowerRaw, rt._lastPowerMaxRaw = power, powerMax
    WriteGFHotSlot(slot, power, powerMax, pct, pctKnown, rt)
  end
end

local function GFHotPowerPercentNeedsUpdate(rt, pct)
  if issecretvalue(pct) == true then
    ClearGFHotPowerKeys(rt)
    return true, true
  end
  local keyPower = PercentCacheKeyFromValue(pct, 0)
  if keyPower == false then
    ClearGFHotPowerKeys(rt)
    return true, pct ~= nil
  end
  if rt._msufGFHotPower == keyPower and rt._msufGFHotPowerMax == false then
    return false, pct ~= nil
  end
  rt._msufGFHotPower = keyPower
  rt._msufGFHotPowerMax = false
  return true, pct ~= nil
end

local function BuildGFHotPowerTextFromPercent(frame, rt)
  if not (rt
    and rt.powerSlotCount == 1
    and rt.powerColorByType ~= true
    and rt.powerDispatchKeyMode == 4
    and rt.powerNeedsCurrent ~= true
    and rt.powerNeedsMax ~= true) then
    return nil
  end
  local slot = rt.powerSlots and rt.powerSlots[1]
  if not (slot and (slot.plainWriter or slot.secretWriter or slot.writer)) then
    return nil
  end
  ClearGFHotPowerKeys(rt)
  return function(frame, event, unit, pct)
    local update, pctKnown = GFHotPowerPercentNeedsUpdate(rt, pct)
    if not update then return end
    rt._lastPowerRaw, rt._lastPowerMaxRaw = nil, nil
    WriteGFHotSlot(slot, nil, nil, pct, pctKnown, rt)
  end
end

if Text.RuntimeHotFunctions then
  Text.RuntimeHotFunctions.healthFromPercent = BuildGFHotHealthTextFromPercent
  Text.RuntimeHotFunctions.healthFromValues = BuildGFHotHealthText
  Text.RuntimeHotFunctions.powerFromPercent = BuildGFHotPowerTextFromPercent
  Text.RuntimeHotFunctions.powerFromValues = BuildGFHotPowerText
end

function Text.IsEnabled(frame, spec)
  return (spec and spec.showName ~= false)
    or HealthTextEnabled(spec)
    or PowerTextEnabled(spec)
    or InlineEnabled(frame, spec)
end
local Runtime = {
  EMPTY_EVENTS = EMPTY_EVENTS,
  NAME_EVENTS = NAME_EVENTS,
  NAME_COLOR_EVENTS = NAME_COLOR_EVENTS,
  NAME_STATUS_EVENTS = NAME_STATUS_EVENTS,
  NAME_STATUS_COLD_EVENTS = NAME_STATUS_COLD_EVENTS,
  HEALTH_TEXT_EVENTS = HEALTH_TEXT_EVENTS,
  INLINE_TARGET_EVENTS = INLINE_TARGET_EVENTS,
  INLINE_NAME_UNITLESS_EVENTS = INLINE_NAME_UNITLESS_EVENTS,
  INLINE_COLOR_UNITLESS_EVENTS = INLINE_COLOR_UNITLESS_EVENTS,
  POWER_EVENTS = POWER_EVENTS,
  POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT,
  HealthTextEnabled = HealthTextEnabled,
  PowerTextEnabled = PowerTextEnabled,
  InlineEnabled = InlineEnabled,
  SetShownCached = SetShownCached,
  UpdateName = Text.UpdateName,
  UpdateHealth = Text.UpdateHealth,
  UpdatePower = Text.UpdatePower,
  UpdateInline = Text.UpdateInline,
}

MSUF.UFTextRuntime = Runtime

local TextStructure = {}
TextStructure.GetEvents = Text.GetEvents
TextStructure.GetUnitlessEvents = Text.GetUnitlessEvents
TextStructure.Create = Text.Create
TextStructure.Apply = Text.Apply
TextStructure.IsEnabled = Text.IsEnabled
UF.RegisterElement("Text", TextStructure)

local NameText = {}

function NameText.IsEnabled(frame, spec)
  return spec and spec.showName ~= false
end

function NameText.GetEvents(frame, spec)
  if spec and spec.scope == "group" then
    return EMPTY_EVENTS
  end
  local text = spec and spec.text
  if text and text.hideNameOnDeadOffline == true then
    if (frame and frame.MSUFUnitKey == "player") or (spec and spec.key == "player") then
      return NAME_STATUS_PLAYER_EVENTS
    end
    return NameNeedsNPCColorEvents(text) and NAME_STATUS_COLOR_EVENTS or NAME_STATUS_EVENTS
  end
  if (frame and frame.MSUFUnitKey == "player") or (spec and spec.key == "player") then
    return NAME_EVENTS
  end
  return NameNeedsNPCColorEvents(text) and NAME_COLOR_EVENTS or NAME_EVENTS
end

function NameText.Update(frame, event, unit)
  Text.UpdateName(frame, event, unit or frame.MSUFUnitKey)
end

function NameText.Disable(frame)
  SetShownCached(frame and frame.nameText, false)
end

UF.RegisterElement("NameText", NameText)

local HealthText = {}

function HealthText.IsEnabled(frame, spec)
  return HealthTextEnabled(spec)
end

function HealthText.GetEvents(frame, spec)
  if not HealthTextEnabled(spec) then
    return EMPTY_EVENTS
  end
  local classColor = spec and spec.text and spec.text.healthColorByClass == true
  local absorb = HealthTextNeedsAbsorbEvents(spec)
  local needsValue = HealthTextNeedsValueTicks(spec)
  local needsMax = HealthTextNeedsMaxEvents(spec)
  local player = (frame and frame.MSUFUnitKey == "player") or (spec and spec.key == "player")
  if not needsValue then
    if not needsMax then
      if not absorb then return EMPTY_EVENTS end
      if player then return ABSORB_TEXT_PLAYER_EVENTS end
      return classColor and ABSORB_TEXT_CLASS_EVENTS or ABSORB_TEXT_EVENTS
    end
    if absorb then
      if player then return HEALTH_TEXT_MAX_PLAYER_EVENTS_ABSORB end
      return classColor and HEALTH_TEXT_CLASS_MAX_EVENTS_ABSORB or HEALTH_TEXT_MAX_EVENTS_ABSORB
    end
    return classColor and HEALTH_TEXT_CLASS_MAX_EVENTS or HEALTH_TEXT_MAX_EVENTS
  end
  if player then
    if not needsMax then
      return absorb and HEALTH_TEXT_VALUE_PLAYER_EVENTS_ABSORB or HEALTH_TEXT_VALUE_PLAYER_EVENTS
    end
    return absorb and HEALTH_TEXT_PLAYER_EVENTS_ABSORB or HEALTH_TEXT_PLAYER_EVENTS
  end
  if not needsMax then
    if absorb then
      return classColor and HEALTH_TEXT_CLASS_VALUE_EVENTS_ABSORB or HEALTH_TEXT_VALUE_EVENTS_ABSORB
    end
    return classColor and HEALTH_TEXT_CLASS_VALUE_EVENTS or HEALTH_TEXT_VALUE_EVENTS
  end
  if absorb then return classColor and HEALTH_TEXT_CLASS_EVENTS_ABSORB or HEALTH_TEXT_EVENTS_ABSORB end
  return classColor and HEALTH_TEXT_CLASS_EVENTS or HEALTH_TEXT_EVENTS
end

function HealthText.GetUnitlessEvents(frame, spec)
  return HealthTextEnabled(spec) and spec and spec.scope == "group" and GROUP_LIFECYCLE_EVENTS or EMPTY_EVENTS
end

UpdateHealthTextValues = function(frame, event, unit, hp, hpMax)
  if frame and frame._msufTextDirtyMask ~= nil then
    CancelDirtyTextFrame(frame, TEXT_DIRTY_HEALTH, true)
  end
  local rt = frame and frame._msufTextRuntime
  if rt and rt.healthColorByClass == true and event ~= "UNIT_HEALTH" then
    UpdateHealthTextColor(frame, rt, unit or frame.MSUFUnitKey)
    if event == "UNIT_NAME_UPDATE" then return end
  end
  local percentFn = rt and rt.healthHotFromPercent
  if percentFn then
    local pct, pctReady
    if hp ~= nil and hpMax == nil then
      pct, pctReady = hp, true
    elseif rt._dispatchHealthPercentReady == true then
      pct, pctReady = rt._dispatchHealthPercent, true
      rt._dispatchHealthPercent = nil
      rt._dispatchHealthPercentReady = nil
    end
    if pctReady == true then
      return percentFn(frame, event, unit or frame.MSUFUnitKey, pct)
    end
  end
  local fn = rt and rt.healthHot
  if fn then
    return fn(frame, event, unit or frame.MSUFUnitKey, hp, hpMax)
  end
  return Text.UpdateHealth(frame, event, unit or frame.MSUFUnitKey, hp, hpMax)
end

local function UpdateHealthTextAll(frame, event, unit, hp, hpMax)
  UpdateAbsorbRuntime(frame, event, unit or frame.MSUFUnitKey, true)
  return UpdateHealthTextValues(frame, event, unit, hp, hpMax)
end

function HealthText.SelectUpdate(frame)
  local rt = frame and frame._msufTextRuntime
  if rt and rt.healthUsesAbsorb == true then
    return rt.healthValueSlotCount and rt.healthValueSlotCount > 0 and UpdateHealthTextAll or UpdateAbsorbRuntime
  end
  return UpdateHealthTextValues
end

function HealthText.SelectEventUpdate(frame, spec, event, update)
  if event == "UNIT_ABSORB_AMOUNT_CHANGED" then return UpdateAbsorbRuntime end
  if event == "UNIT_HEALTH" then
    local rt = frame and frame._msufTextRuntime
    -- Flat inline write for a group frame with a single percent-only health
    -- slot: write in the same route pass as the bar (which published the plain
    -- percent), skipping the deferred dirty-text queue/ticker/drain. Any other
    -- text shape (absorb-combined, value/missing modes) keeps the coalescer.
    if spec and spec.scope == "group" and rt and rt.healthHotFromPercent
      and rt.healthUsesAbsorb ~= true then
      return UpdateHealthTextValues
    end
    return rt and rt.healthDirty or MarkHealthTextDirty
  end
  if event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE" then
    return UpdateHealthTextValues
  end
  return update
end

HealthText.Update = UpdateHealthTextAll

function HealthText.Disable(frame)
  CancelDirtyTextFrame(frame, TEXT_DIRTY_HEALTH)
  SetShownCached(frame and frame.hpTextLeft, false)
  SetShownCached(frame and frame.hpTextCenter, false)
  SetShownCached(frame and frame.hpTextRight, false)
end

UF.RegisterElement("HealthText", HealthText)

local PowerText = {}

function PowerText.IsEnabled(frame, spec)
  if frame and frame._msufAugPowerReplacementActive == true then return false end
  return PowerTextEnabled(spec)
end

function PowerText.GetEvents(frame, spec)
  if frame and frame._msufAugPowerReplacementActive == true then
    return EMPTY_EVENTS
  end
  if not PowerTextEnabled(spec) then
    return EMPTY_EVENTS
  end
  if not PowerTextNeedsValueTicks(spec) then
    return POWER_TEXT_MAX_EVENTS
  end
  if not PowerTextNeedsMaxEvents(spec) then
    return spec and spec.power and spec.power.frequent == true and POWER_TEXT_VALUE_META_EVENTS_FREQUENT or POWER_TEXT_VALUE_META_EVENTS
  end
  return spec and spec.power and spec.power.frequent == true and POWER_EVENTS_FREQUENT or POWER_EVENTS
end

UpdatePowerTextValues = function(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  if frame and frame._msufTextDirtyMask ~= nil then
    CancelDirtyTextFrame(frame, TEXT_DIRTY_POWER, true)
  end
  local rt = frame and frame._msufTextRuntime
  local percentFn = rt and rt.powerHotFromPercent
  if percentFn then
    local pct, pctReady
    if power ~= nil and powerMax == nil then
      pct, pctReady = power, true
    elseif rt._dispatchPowerPercentReady == true then
      pct, pctReady = rt._dispatchPowerPercent, true
      rt._dispatchPowerPercent = nil
      rt._dispatchPowerPercentReady = nil
    end
    if pctReady == true then
      return percentFn(frame, event, unit or frame.MSUFUnitKey, pct)
    end
  end
  local fn = rt and rt.powerHot
  if fn then
    return fn(frame, event, unit or frame.MSUFUnitKey, power, powerMax, powerType, powerToken, powerMetaChanged)
  end
  return Text.UpdatePower(frame, event, unit or frame.MSUFUnitKey, power, powerMax, powerType, powerToken, powerMetaChanged)
end
PowerText.Update = UpdatePowerTextValues

function PowerText.SelectEventUpdate(frame, spec, event, update)
  -- The explicit realtime player option promises event-accurate text. Keep
  -- UNIT_POWER_FREQUENT on the direct compiled Power -> PowerText route so the
  -- text consumes the value the bar already resolved in this event. Ordinary
  -- power text remains on the shared 250 ms coalescer.
  if event == "UNIT_POWER_FREQUENT"
    and spec and spec.power and spec.power.frequent == true then
    return UpdatePowerTextValues
  end
  if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
    local rt = frame and frame._msufTextRuntime
    -- Flat inline write: a group frame with a single percent-only power
    -- slot writes its text synchronously in the same compiled route pass as the
    -- bar (which just published the plain percent to rt._dispatchPowerPercent),
    -- consuming that value with the existing bucket dedup. This drops the
    -- deferred dirty-text machinery (MarkDirty -> C_Timer ticker -> FlushDirtyText
    -- -> per-frame state re-fetch) that an inline SetFormattedText
    -- never pays. Any other text shape keeps the deferred coalescer.
    if spec and spec.scope == "group" and rt and rt.powerHotFromPercent then
      return UpdatePowerTextValues
    end
    return rt and rt.powerDirty or MarkPowerTextDirty
  end
  return update
end

function PowerText.Disable(frame)
  CancelDirtyTextFrame(frame, TEXT_DIRTY_POWER)
  SetShownCached(frame and frame.powerTextLeft, false)
  SetShownCached(frame and frame.powerTextCenter, false)
  SetShownCached(frame and frame.powerTextRight, false)
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
              and cachedPower ~= nil
              and issecretvalue(cachedPower) ~= true then
              power = cachedPower
            end
            local cachedMax = bar._msufPowerMax
            if rt.powerNeedsMax == true
              and bar._msufPowerMaxReady == true
              and bar._msufPowerMaxUnit == unit
              and cachedMax ~= nil
              and issecretvalue(cachedMax) ~= true then
              powerMax = cachedMax
            end
          end
          UpdatePowerTextValues(frame, "UNIT_POWER_UPDATE", unit, power, powerMax, nil, nil, false)
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

HealthText.MarkValueDirty = MarkHealthTextDirty
HealthText.MarkGroupValueDirty = MarkGroupHealthTextDirty
PowerText.MarkValueDirty = MarkPowerTextDirty
HealthText.NoDispatchUpdates = {
  [MarkHealthTextDirty] = true,
  [MarkGroupHealthTextDirty] = true,
}
-- Core may omit a repeated UNIT_HEALTH marker while either mask containing the
-- health bit is already pending. The deferred writer rereads the latest unit
-- values at drain time, so repeated markers carry no event payload or state.
HealthText.DirtyGateUpdates = {
  [MarkHealthTextDirty] = true,
  [MarkGroupHealthTextDirty] = true,
}
PowerText.NoDispatchUpdates = { [MarkPowerTextDirty] = true }

UF.RegisterElement("PowerText", PowerText)

local InlineToT = {}

local inlineToTDriver
local inlineToTOwner
local inlineToTUnit

local function InlineToTNeedsColorEvents(inline)
  return inline and ((inline.colorMode and inline.colorMode ~= "DEFAULT")
    or inline.targetNameClassColor == true
    or inline.targetNameNpcColor == true
    or inline.targetNameNpcClassColor == true
    or inline.totNameClassColor == true
    or inline.totNameNpcColor == true
    or inline.totNameNpcClassColor == true)
end

local function ClearInlineToTDriver(owner)
  if owner ~= nil and inlineToTOwner ~= owner then return end
  if inlineToTDriver and inlineToTDriver.UnregisterAllEvents then
    inlineToTDriver:UnregisterAllEvents()
  end
  inlineToTOwner = nil
  inlineToTUnit = nil
end

local function ConfigureInlineToTDriver(frame, spec)
  local inline = spec and spec.text and spec.text.inlineToT
  if not InlineEnabled(frame, spec) then
    ClearInlineToTDriver(frame)
    return false
  end
  if not inlineToTDriver then
    local createFrame = _G.CreateFrame
    if type(createFrame) ~= "function" then return false end
    inlineToTDriver = createFrame("Frame")
    inlineToTDriver:SetScript("OnEvent", function(_, event)
      local owner = inlineToTOwner
      local active = owner and owner._msufActiveElements
      if not (owner and active and active.InlineToT == true) then return end
      InlineToT.Update(owner, event, inlineToTUnit)
    end)
  end

  inlineToTDriver:UnregisterAllEvents()
  inlineToTOwner = frame
  inlineToTUnit = inline.unit or "targettarget"
  local events = InlineToTNeedsColorEvents(inline) and INLINE_COLOR_UNITLESS_EVENTS or INLINE_NAME_UNITLESS_EVENTS
  for i = 1, #events do
    inlineToTDriver:RegisterUnitEvent(events[i], inlineToTUnit)
  end
  return true
end

function InlineToT.IsEnabled(frame, spec)
  return InlineEnabled(frame, spec)
end

function InlineToT.GetEvents()
  return INLINE_TARGET_EVENTS
end

function InlineToT.GetUnitlessEvents()
  return EMPTY_EVENTS
end

function InlineToT.Apply(frame, spec)
  return ConfigureInlineToTDriver(frame, spec)
end

function InlineToT.Update(frame, event, unit)
  Text.UpdateInline(frame, event, unit)
end
InlineToT.NoDispatchUpdates = { [InlineToT.Update] = true }

function InlineToT.Disable(frame)
  ClearInlineToTDriver(frame)
  SetShownCached(frame and frame.totInlineSep, false)
  SetShownCached(frame and frame.totInlineText, false)
  if frame then
    frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
  end
end

UF.RegisterElement("InlineToT", InlineToT)
