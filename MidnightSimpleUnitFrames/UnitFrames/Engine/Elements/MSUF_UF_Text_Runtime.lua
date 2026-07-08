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
local UnitPower = Text.UnitPower
local UnitPowerMax = Text.UnitPowerMax
local UnitPowerType = Text.UnitPowerType
local InCombatLockdown = Text.InCombatLockdown
local UnitName = Text.UnitName
local ReadDisplayName = UnitName
local GetTime = Text.GetTime
local PowerColor = Text.PowerColor
local SetShownCached = Text.SetShownCached
local SetTextCached = Text.SetTextCached
local SetNameTextColor = Text.SetNameTextColor
local NameTextColor = Text.NameTextColor
local NPCTypeTextColorEnabled = Text.NPCTypeTextColorEnabled
local SetInlineTextColor = Text.SetInlineTextColor
local InlineTextColor = Text.InlineTextColor
local SetPowerTextColor = Text.SetPowerTextColor
local UpdateHealthTextColor = Text.UpdateHealthTextColor
local HealthPercent = Text.HealthPercent
local HealthPercentAvailable = Text.UnitHealthPercent ~= nil
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
local EMPTY_EVENTS = Text.EMPTY_EVENTS
local POWER_EVENTS = Text.POWER_EVENTS
local POWER_EVENTS_FREQUENT = Text.POWER_EVENTS_FREQUENT
local POWER_TEXT_MAX_EVENTS = { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_TEXT_VALUE_META_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
local POWER_TEXT_VALUE_META_EVENTS_FREQUENT = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }

local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

function Text.SetDisplayNameResolver(resolver)
  ReadDisplayName = type(resolver) == "function" and resolver or UnitName
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
  return floor(pct + 0.5)
end

local function PercentFromValues(cur, maxValue)
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
  rt._msufGFHotHealthMissing = nil
end

local function ClearGFHotPowerKeys(rt)
  if not rt then return end
  rt._msufGFHotPower = nil
  rt._msufGFHotPowerMax = nil
end

local function WriteGFHotSlot(slot, cur, maxValue, pct, pctKnown, rt, missing)
  if not slot then return end
  if missing ~= nil then
    rt.healthMissing = missing
  end
  if nativeSecrets and (issecretvalue(cur) == true
    or issecretvalue(maxValue) == true
    or (pctKnown == true and issecretvalue(pct) == true)
    or (missing ~= nil and issecretvalue(missing) == true)) then
    local writer = slot.secretWriter or slot.writer
    if writer then writer(slot, cur, maxValue, pct, true, rt) end
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
    missing = MissingHealthFromValues(hp, hpMax)
    if missing == nil then
      local calc = frame and frame._msufHealthCalc
      missing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
    end
    if issecretvalue(missing) == true then
      ClearGFHotHealthKeys(rt)
      return true, nil, false, missing
    end
    keyMissing = missing or false
  end

  local mode = rt.healthDispatchKeyMode or 0
  local keyHP, keyMax = false, false
  if mode == 1 then
    keyHP = hp
  elseif mode == 2 then
    keyMax = hpMax
  elseif mode == 3 then
    keyHP, keyMax = hp, hpMax
  elseif mode == 4 or mode == 5 then
    pct = PercentFromValues(hp, hpMax) or HealthPercent(unit)
    pctKnown = issecretvalue(pct) == true or pct ~= nil
    if issecretvalue(pct) == true then
      ClearGFHotHealthKeys(rt)
      return true, pct, true, missing
    end
    keyHP = PercentCacheKeyFromValue(pct, rt.healthPercentDecimals)
    if keyHP == false then
      ClearGFHotHealthKeys(rt)
      return true, pct, pctKnown, missing
    end
    keyMax = mode == 5 and hpMax or false
  end

  if rt._msufGFHotHealthHP == keyHP
    and rt._msufGFHotHealthMax == keyMax
    and rt._msufGFHotHealthMissing == keyMissing then
    return false, pct, pctKnown, missing
  end
  rt._msufGFHotHealthHP = keyHP
  rt._msufGFHotHealthMax = keyMax
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

  local mode = rt.powerDispatchKeyMode or 0
  local keyPower, keyMax = false, false
  if mode == 1 then
    keyPower = power
  elseif mode == 2 then
    keyMax = powerMax
  elseif mode == 3 then
    keyPower, keyMax = power, powerMax
  elseif mode == 4 or mode == 5 then
    pct = PercentFromValues(power, powerMax) or PowerPercent(unit)
    pctKnown = issecretvalue(pct) == true or pct ~= nil
    if issecretvalue(pct) == true then
      ClearGFHotPowerKeys(rt)
      return true, pct, true
    end
    keyPower = PercentCacheKeyFromValue(pct, 0)
    if keyPower == false then
      ClearGFHotPowerKeys(rt)
      return true, pct, pctKnown
    end
    keyMax = mode == 5 and powerMax or false
  end

  if rt._msufGFHotPower == keyPower and rt._msufGFHotPowerMax == keyMax then
    return false, pct, pctKnown
  end
  rt._msufGFHotPower = keyPower
  rt._msufGFHotPowerMax = keyMax
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

local function SeedCachedPowerMax(frame, unit, powerMax)
  if not frame then
    return false
  end
  if issecretvalue(powerMax) == true then
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
        and (event == "UNIT_DISPLAYPOWER"
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
        and (event == "UNIT_MAXPOWER"
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

function Text.UpdateNameColor(frame, event, unit)
  if RegionShown(frame and frame.nameText) then
    SetNameTextColor(frame, NameTextColor(frame, unit or frame.unit))
    local rt = frame and frame._msufTextRuntime
    if rt and rt.inlineToT then
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
  local name = ReadDisplayName(inlineUnit)
  SetTextCached(frame.totInlineText, name)
  if AnchorInlineToName then
    AnchorInlineToName(frame)
  end
  SetShownCached(frame.totInlineSep, true)
  SetShownCached(frame.totInlineText, true)
  SetInlineTextColor(frame, InlineTextColor(frame, inlineUnit, inline))
end

function Text.UpdateName(frame, event, unit)
  local frameUnit = frame and frame.unit
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
    SetTextCached(frame.nameText, "")
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
    SetTextCached(frame.nameText, previewName)
    frame._msufNameTextUnit = unit
    Text.UpdateNameColor(frame, event, unit)
    return
  end
  if rt and rt.showName == false then
    frame._msufNameStatusUnit = nil
    frame._msufNameStatusHidden = nil
    frame._msufNameTextUnit = nil
    SetTextCached(frame.nameText, "")
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
      SetTextCached(frame.nameText, "")
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
  SetTextCached(frame.nameText, ReadDisplayName(unit))
  frame._msufNameTextUnit = unit
  Text.UpdateNameColor(frame, event, unit)
end

local function UpdateHealthRuntime(frame, event, unit, hp, hpMax)
  unit = unit or frame.unit
  local rt = frame._msufTextRuntime
  if not rt or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
    return
  end

  local healthTick = event == "UNIT_HEALTH"
  local needsPercent = rt.healthNeedsPercent == true
  local needsCurrent = rt.healthNeedsCurrent == true
  local needsMax = rt.healthNeedsMax == true
  local colorByHealth = rt.healthColorByHealth == true
  local percentNeedsValues = false
  local missingNeedsValues = rt.healthNeedsMissing == true
  local needHPValue = needsCurrent or colorByHealth or percentNeedsValues or missingNeedsValues
  local needMaxValue = needsMax or colorByHealth or percentNeedsValues or missingNeedsValues

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
      hpMax = UnitHealthMax(unit)
    end

    if rt.healthNeedsMissing == true then
      if healthTick and rt._dispatchHealthMissingReady == true then
        rt.healthMissing = rt._dispatchHealthMissing
        rt._dispatchHealthMissingReady = nil
        rt._dispatchHealthMissing = nil
      else
        rt._dispatchHealthMissingReady = nil
        rt._dispatchHealthMissing = nil
        rt.healthMissing = MissingHealthFromValues(hp, hpMax)
        if rt.healthMissing == nil then
          local calc = frame and frame._msufHealthCalc
          rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
        end
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
      UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
      return
    end

    local pctOverride, pctOverrideSet
    if needsPercent then
      pctOverride, pctOverrideSet = ConsumeDispatchPercent(rt, "_dispatchHealthPercent", "_dispatchHealthPercentReady")
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
      UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
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
    if colorByHealth and UpdateHealthTextColor then
      UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
    end
    UpdateTextSlotsPlain(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
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
    hpMax = UnitHealthMax(unit)
    hpMaxSecret = issecretvalue(hpMax) == true
  end

  rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax

  if rt.healthNeedsMissing == true then
    rt.healthMissing = MissingHealthFromValues(hp, hpMax)
    if rt.healthMissing == nil then
      local calc = frame and frame._msufHealthCalc
      rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
    end
  else
    rt.healthMissing = nil
  end

  if colorByHealth and UpdateHealthTextColor then
    UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
  end
  UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
end

local function UpdatePowerRuntime(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  unit = unit or frame.unit
  local rt = frame._msufTextRuntime
  if not rt or not rt.powerSlotCount or rt.powerSlotCount <= 0 then
    return
  end
  local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  local identityChanged = not animate
    and (event == "MSUF_UNIT_IDENTITY"
      or event == "MSUF_UNIT_IDENTITY_FAST"
      or event == "MSUF_UNIT_IDENTITY_SOFT"
      or event == "MSUF_UNIT_IDENTITY_SOFT_FAST"
      or event == "MSUF_GF_UNIT_IDENTITY"
      or event == "MSUF_GF_UNIT_STRUCTURE")
  local seededPowerType
  if identityChanged then
    frame._msufTextPowerType = nil
    frame._msufTextPowerToken = nil
    frame._msufTextPowerTypeKnown = nil
    frame._msufTextPowerTypeUnit = nil
    frame._msufTextPowerMax = nil
    frame._msufTextPowerMaxUnit = nil
    seededPowerType = SeedCachedPowerType(frame, unit, powerType, powerToken)
    if rt.powerColorByType == true and seededPowerType ~= true then
      RefreshCachedPowerType(frame, unit)
    end
  else
    seededPowerType = SeedCachedPowerType(frame, unit, powerType, powerToken)
  end
  SeedCachedPowerMax(frame, unit, powerMax)
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

    if nativeSecrets and (issecretvalue(power) == true or issecretvalue(powerMax) == true) then
      rt._lastPowerTextPower = nil
      rt._lastPowerTextMax = nil
      rt._dispatchPowerTextPower = nil
      rt._dispatchPowerTextMax = nil
      UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt)
      return
    end

    local pctOverride, pctOverrideSet
    if needsPercent then
      pctOverride, pctOverrideSet = ConsumeDispatchPercent(rt, "_dispatchPowerPercent", "_dispatchPowerPercentReady")
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

  UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt)
end

Text.RuntimeHotFunctions = {
  healthHot = UpdateHealthRuntime,
  powerHot = UpdatePowerRuntime,
}

Text.UpdateHealth = UpdateHealthRuntime
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
  return mode ~= "MAX"
end

local function HealthModeNeedsMaxEvents(mode)
  return mode == "DEFICIT" or TEXT_MAX_EVENT_MODES[mode] == true
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
  return frame and frame.unit == "target" and spec and spec.showName ~= false and inline and inline.enabled == true
end

local function StrictGroupSpec(frame, spec)
  return frame
    and frame._msufIsGroupFrame == true
    and spec
    and spec.scope == "group"
end

local function ElementActive(frame, name)
  local active = frame and frame._msufActiveElements
  return active and active[name] == true
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
    and rt.healthSlotCount == 1
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
  return function(frame, event, unit, pct)
    local update, pctKnown = GFHotHealthPercentNeedsUpdate(rt, pct)
    if not update then return end
    rt.healthMissing = nil
    rt._lastHpRaw, rt._lastHpMaxRaw = nil, nil
    WriteGFHotSlot(slot, nil, nil, pct, pctKnown, rt)
  end
end

local function BuildGFHotHealthText(frame, rt)
  if not (rt and rt.healthSlotCount == 1 and rt.healthColorByHealth ~= true) then
    return nil
  end
  local slot = rt.healthSlots and rt.healthSlots[1]
  if not (slot and (slot.plainWriter or slot.secretWriter or slot.writer)) then
    return nil
  end
  return function(frame, event, unit, hp, hpMax)
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
  return function(frame, event, unit, power, powerMax)
    local update, pct, pctKnown = GFHotPowerNeedsUpdate(rt, unit, power, powerMax)
    if not update then return end
    rt.healthMissing = nil
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
  return function(frame, event, unit, pct)
    local update, pctKnown = GFHotPowerPercentNeedsUpdate(rt, pct)
    if not update then return end
    rt.healthMissing = nil
    rt._lastPowerRaw, rt._lastPowerMaxRaw = nil, nil
    WriteGFHotSlot(slot, nil, nil, pct, pctKnown, rt)
  end
end

if Text.RuntimeHotFunctions then
  Text.RuntimeHotFunctions.healthFromPercent = BuildGFHotHealthTextFromPercent
  Text.RuntimeHotFunctions.powerFromPercent = BuildGFHotPowerTextFromPercent
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
    if (frame and frame.unit == "player") or (spec and spec.key == "player") then
      return NAME_STATUS_PLAYER_EVENTS
    end
    return NameNeedsNPCColorEvents(text) and NAME_STATUS_COLOR_EVENTS or NAME_STATUS_EVENTS
  end
  if (frame and frame.unit == "player") or (spec and spec.key == "player") then
    return NAME_EVENTS
  end
  return NameNeedsNPCColorEvents(text) and NAME_COLOR_EVENTS or NAME_EVENTS
end

function NameText.Update(frame, event, unit)
  Text.UpdateName(frame, event, unit or frame.unit)
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
  if not HealthTextNeedsValueTicks(spec) then
    return HEALTH_TEXT_MAX_EVENTS
  end
  if (frame and frame.unit == "player") or (spec and spec.key == "player") then
    if not HealthTextNeedsMaxEvents(spec) then
      return HEALTH_TEXT_VALUE_PLAYER_EVENTS
    end
    return HEALTH_TEXT_PLAYER_EVENTS
  end
  if not HealthTextNeedsMaxEvents(spec) then
    return HEALTH_TEXT_VALUE_EVENTS
  end
  return HEALTH_TEXT_EVENTS
end

function HealthText.Update(frame, event, unit, hp, hpMax)
  local rt = frame and frame._msufTextRuntime
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
      return percentFn(frame, event, unit or frame.unit, pct)
    end
  end
  local fn = rt and rt.healthHot
  if fn then
    return fn(frame, event, unit or frame.unit, hp, hpMax)
  end
  return Text.UpdateHealth(frame, event, unit or frame.unit, hp, hpMax)
end

function HealthText.Disable(frame)
  SetShownCached(frame and frame.hpTextLeft, false)
  SetShownCached(frame and frame.hpTextCenter, false)
  SetShownCached(frame and frame.hpTextRight, false)
end

UF.RegisterElement("HealthText", HealthText)

local PowerText = {}

function PowerText.IsEnabled(frame, spec)
  return PowerTextEnabled(spec)
end

function PowerText.GetEvents(frame, spec)
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

function PowerText.Update(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
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
      return percentFn(frame, event, unit or frame.unit, pct)
    end
  end
  local fn = rt and rt.powerHot
  if fn then
    return fn(frame, event, unit or frame.unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end
  return Text.UpdatePower(frame, event, unit or frame.unit, power, powerMax, powerType, powerToken, powerMetaChanged)
end

function PowerText.Disable(frame)
  SetShownCached(frame and frame.powerTextLeft, false)
  SetShownCached(frame and frame.powerTextCenter, false)
  SetShownCached(frame and frame.powerTextRight, false)
end

UF.RegisterElement("PowerText", PowerText)

local InlineToT = {}

function InlineToT.IsEnabled(frame, spec)
  return InlineEnabled(frame, spec)
end

function InlineToT.GetEvents()
  return INLINE_TARGET_EVENTS
end

function InlineToT.GetUnitlessEvents(frame, spec)
  local inline = spec and spec.text and spec.text.inlineToT
  if not inline then
    return EMPTY_EVENTS
  end
  if (inline.colorMode and inline.colorMode ~= "DEFAULT")
    or inline.targetNameClassColor == true
    or inline.targetNameNpcColor == true
    or inline.targetNameNpcClassColor == true
    or inline.totNameClassColor == true
    or inline.totNameNpcColor == true
    or inline.totNameNpcClassColor == true then
    return INLINE_COLOR_UNITLESS_EVENTS
  end
  return INLINE_NAME_UNITLESS_EVENTS
end

function InlineToT.Update(frame, event, unit)
  Text.UpdateInline(frame, event, unit)
end

function InlineToT.Disable(frame)
  SetShownCached(frame and frame.totInlineSep, false)
  SetShownCached(frame and frame.totInlineText, false)
  if frame then
    frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
  end
end

UF.RegisterElement("InlineToT", InlineToT)
