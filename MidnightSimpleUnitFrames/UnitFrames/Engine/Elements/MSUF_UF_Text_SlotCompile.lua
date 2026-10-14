-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.TextSlotCompile = function(
  ABSORB_HEALTH_MODE_BASE, AbbreviateSecretNumber, BreakUpLargeNumbers, CompileSecretWriter, DISPATCH_KEY, MODE_PLAIN_WRITERS,
    MODE_WRITERS, ModeNeedsCurrent, ModeNeedsMax, ModeNeedsPercent, NormalizePercentDecimals, NormalizeTextDelimiter,
    PlainWriteAbsorbCombined, PlainWriteCurMax, ResolveHealthTextModes, SECRET_MODE_CODES, SECRET_NEEDS_CUR, SECRET_NEEDS_MAX,
    SECRET_NEEDS_PCT, SECRET_SETTERS, Text, WriteAbsorbCombined, WriteCurMax, floor, max, nativeSecrets, tonumber
)

local function BuildSecretPattern(mode, vf, pf)
  if mode == "CURRENT" or mode == "FULLVALUE" or mode == "MAX" then
    return vf
  elseif mode == "PERCENT" then
    return pf
  elseif mode == "CURMAX" or mode == "MAXCUR" then
    return vf .. "%s" .. vf
  elseif mode == "CURPERCENT" or mode == "MAXPERCENT" then
    return vf .. "%s" .. pf
  elseif mode == "PERCENTCUR" or mode == "PERCENTMAX" then
    return pf .. "%s" .. vf
  elseif mode == "CURMAXPERCENT" then
    return vf .. "%s" .. vf .. "%s" .. pf
  elseif mode == "PERCENTMAXCUR" or mode == "PERCENTCURMAX" then
    return pf .. "%s" .. vf .. "%s" .. vf
  end
  return nil
end

local function SecretPercentFormat(slot)
  if NormalizePercentDecimals(slot and slot.percentDecimals) >= 1 then
    return slot.hidePercentSymbol and "%.1f" or "%.1f%%"
  end
  return slot.hidePercentSymbol and "%d" or "%d%%"
end

local function AddTextSlot(slots, index, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals, absorbIcon)
  if not (fs and mode and mode ~= "NONE") then
    return index, false, false, false, false, false, false
  end
  local absorbBaseMode = ABSORB_HEALTH_MODE_BASE[mode]
  local compiledMode = absorbBaseMode or mode
  if not MODE_WRITERS[compiledMode] then
    mode = "CURMAX"
    compiledMode = mode
    absorbBaseMode = nil
  end
  local needsPercent = ModeNeedsPercent(compiledMode)
  local slot = slots[index]
  if not slot then
    slot = {}
    slots[index] = slot
  end
  slot.fs = fs
  slot.mode = mode
  slot.absorbIcon = absorbIcon == true
  slot.absorbBaseWriter = absorbBaseMode and MODE_WRITERS[compiledMode] or nil
  slot.absorbBasePlainWriter = absorbBaseMode and MODE_PLAIN_WRITERS[compiledMode] or nil
  slot.writer = absorbBaseMode and WriteAbsorbCombined or (MODE_WRITERS[compiledMode] or WriteCurMax)
  slot.plainWriter = absorbBaseMode and PlainWriteAbsorbCombined or (MODE_PLAIN_WRITERS[compiledMode] or PlainWriteCurMax)
  local secretCode
  if not absorbBaseMode then secretCode = SECRET_MODE_CODES[compiledMode] end
  slot.secretWriter = nil
  slot.secretCode = secretCode
  slot.secretSetter = secretCode and SECRET_SETTERS[secretCode] or nil
  slot.secretNeedsCur = SECRET_NEEDS_CUR[secretCode]
  slot.secretNeedsMax = SECRET_NEEDS_MAX[secretCode]
  slot.secretNeedsPct = SECRET_NEEDS_PCT[secretCode]
  slot.needsPercent = needsPercent
  slot.delimiter = NormalizeTextDelimiter(delimiter)
  slot.short = short == true
  slot.hidePercentSymbol = hidePercentSymbol == true
  slot.percentDecimals = NormalizePercentDecimals(percentDecimals)
  if secretCode then
    local secretValueFn = slot.short and AbbreviateSecretNumber or BreakUpLargeNumbers
    slot.secretValueFn = secretValueFn
    slot.secretPattern = BuildSecretPattern(mode,
      secretValueFn and "%s" or "%d",
      SecretPercentFormat(slot))
    slot.secretWriter = CompileSecretWriter(slot)
  else
    slot.secretValueFn = nil
    slot.secretPattern = nil
  end
  slot.suffix = nil
  slot.appendSuffix = false
  slot.canSecret = nil
  local usesAbsorb = mode == "ABSORB" or absorbBaseMode ~= nil
  return index + 1, needsPercent, compiledMode == "DEFICIT", ModeNeedsCurrent(compiledMode), ModeNeedsMax(compiledMode), usesAbsorb, mode == "ABSORB"
end

local function TrimTextSlots(slots, firstDead)
  for i = firstDead, #slots do
    slots[i] = nil
  end
end

local HEALTH_SLOT_FIELDS = { "hpTextLeft", "hpTextCenter", "hpTextRight" }
local POWER_SLOT_FIELDS = { "powerTextLeft", "powerTextCenter", "powerTextRight" }

local function CompilePowerRuntime(frame, rt, spec, text, plainText)
  local showPower = spec and spec.showPowerText ~= false
  -- Per-slot override wins whenever it is set, including an explicit false.
  local powerFallbackHide = text.hidePercentSymbol == true
  local powerHideLeft, powerHideCenter, powerHideRight =
    text.powerLeftHidePercentSymbol, text.powerCenterHidePercentSymbol, text.powerRightHidePercentSymbol
  if powerHideLeft == nil then powerHideLeft = powerFallbackHide else powerHideLeft = powerHideLeft == true end
  if powerHideCenter == nil then powerHideCenter = powerFallbackHide else powerHideCenter = powerHideCenter == true end
  if powerHideRight == nil then powerHideRight = powerFallbackHide else powerHideRight = powerHideRight == true end
  local slots = rt.powerSlots
  local fields = POWER_SLOT_FIELDS
  local delimiter, short = text.powerDelimiter, text.shortNumbers
  local percentDecimals
  local nextIndex = 1
  local needsPercent, needsMissing, needsCurrent, needsMax = false, false, false, false
  if showPower then
    for i = 1, #fields do
      local fs = frame[fields[i]]
      if fs and fs:IsShown() then
        local mode = i == 1 and text.powerLeft or (i == 2 and text.powerCenter or text.powerRight)
        -- Branch-selected for the same reason as the health slots: a false flag
        -- would otherwise fall through to the Right slot's flag.
        local hidePercentSymbol
        if i == 1 then hidePercentSymbol = powerHideLeft
        elseif i == 2 then hidePercentSymbol = powerHideCenter
        else hidePercentSymbol = powerHideRight end
        local slotNeeds, slotMissing, slotCurrent, slotMax
        nextIndex, slotNeeds, slotMissing, slotCurrent, slotMax = AddTextSlot(slots, nextIndex, fs, mode, delimiter, short, hidePercentSymbol,
          percentDecimals)
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
      end
    end
  end
  TrimTextSlots(slots, nextIndex)
  rt.powerSlotCount = nextIndex - 1
  rt.powerNeedsPercent = needsPercent
  rt.powerNeedsCurrent = needsCurrent
  rt.powerNeedsMax = needsMax
  if needsPercent == true and needsCurrent ~= true then
    rt.powerDispatchKeyMode = needsMax == true and DISPATCH_KEY.PERCENT_MAX or DISPATCH_KEY.PERCENT
  elseif needsCurrent == true and needsMax == true then
    rt.powerDispatchKeyMode = DISPATCH_KEY.CURRENT_MAX
  elseif needsMax == true then
    rt.powerDispatchKeyMode = DISPATCH_KEY.MAX
  elseif needsCurrent == true then
    rt.powerDispatchKeyMode = DISPATCH_KEY.CURRENT
  else
    rt.powerDispatchKeyMode = DISPATCH_KEY.NONE
  end
  if text.directLayout == true and text.powerColorByType ~= true then
    rt.powerColorByType = "STATIC"
  else
    rt.powerColorByType = text.powerColorByType == true
  end
  local powerSpec = spec and spec.power
  rt.powerRefreshTypeOnTick = rt.powerColorByType == true
    and (not powerSpec or powerSpec.mode == nil or powerSpec.mode == "power")
  -- CURRENT-only non-Player text normally needs no power metadata. Player can
  -- switch native identity (forms/vehicles) or hand this surface to Mana while
  -- the text layout itself remains unchanged, so keep its cached identity path
  -- available. Steady bar-fed value events still consume Power's shared payload
  -- and perform no extra native reads.
  frame._msufTextPowerNeedsType = rt.powerSlotCount > 0
    and (frame.MSUFUnitKey == "player"
      or rt.powerColorByType == true
      or needsMax == true
      or needsPercent == true)
    and true
    or nil
  rt.powerPlain = plainText
  rt.plainTextTrusted = plainText
  rt._lastPowerTextPower = nil
  rt._lastPowerTextMax = nil
  rt._dispatchHealthPercent = nil
  rt._dispatchHealthPercentReady = nil
  rt._dispatchHealthMissing = nil
  rt._dispatchHealthMissingReady = nil
  rt._dispatchPowerTextPower = nil
  rt._dispatchPowerTextMax = nil
  frame._msufTextPowerType = nil
  frame._msufTextPowerToken = nil
  frame._msufTextPowerTypeKnown = nil
  frame._msufTextPowerTypeUnit = nil
  frame._msufTextPowerDisplayMana = nil
  frame._msufTextPowerMax = nil
  frame._msufTextPowerMaxUnit = nil
  local hot = Text.RuntimeHotFunctions
  if hot then
    local groupScope = spec and spec.scope == "group"
    if rt.healthValueSlotCount > 0 then
      local fromValues
      if groupScope and (rt.healthNeedsCurrent == true
        or rt.healthNeedsMax == true
        or rt.healthNeedsMissing == true) then
        fromValues = hot.healthFromValues and hot.healthFromValues(frame, rt) or nil
      end
      rt.healthHot = fromValues or hot.healthHot
      rt.healthDrain = hot.healthDrain and hot.healthDrain(rt) or nil
      rt.healthHotFromPercent = hot.healthFromPercent and hot.healthFromPercent(frame, rt) or nil
      rt.healthDirty = groupScope and hot.groupHealthDirty or hot.healthDirty
      rt.healthDefersUnitHealthText = not (groupScope and rt.healthHotFromPercent
        and rt.healthUsesAbsorb ~= true) and true or nil
    else
      rt.healthHot = nil
      rt.healthDrain = nil
      rt.healthHotFromPercent = nil
      rt.healthDirty = nil
      rt.healthDefersUnitHealthText = nil
    end
    if rt.powerSlotCount > 0 then
      local fromValues
      if groupScope and (rt.powerNeedsCurrent == true or rt.powerNeedsMax == true) then
        fromValues = hot.powerFromValues and hot.powerFromValues(frame, rt) or nil
      end
      rt.powerHot = fromValues or hot.powerHot
      rt.powerDrain = hot.powerDrain and hot.powerDrain(rt, groupScope) or nil
      rt.powerHotFromPercent = hot.powerFromPercent and hot.powerFromPercent(frame, rt) or nil
      rt.powerDirty = hot.powerDirty
    else
      rt.powerHot = nil
      rt.powerDrain = nil
      rt.powerHotFromPercent = nil
      rt.powerDirty = nil
    end
  else
    rt.healthHot = nil
    rt.healthDrain = nil
    rt.healthHotFromPercent = nil
    rt.healthDirty = nil
    rt.healthDefersUnitHealthText = nil
    rt.powerHot = nil
    rt.powerDrain = nil
    rt.powerHotFromPercent = nil
    rt.powerDirty = nil
  end
  return rt
end

local function CompileHealthRuntime(frame, rt, spec, text)
  rt.healthSlots = rt.healthSlots or {}
  rt.healthAbsorbSlots = rt.healthAbsorbSlots or {}
  rt.powerSlots = rt.powerSlots or {}
  local showHealth = spec and spec.showHealthText ~= false
  local healthLeft, healthCenter, healthRight, healthHideLeft, healthHideCenter, healthHideRight,
    healthIconLeft, healthIconCenter, healthIconRight = ResolveHealthTextModes(text)
  rt.healthPercentDecimals = NormalizePercentDecimals(text.healthPercentDecimals)

  local valueSlots, absorbSlots = rt.healthSlots, rt.healthAbsorbSlots
  local delimiter, short = text.healthDelimiter, text.healthShortNumbers
  local percentDecimals = rt.healthPercentDecimals
  local valueIndex, absorbIndex = 1, 1
  local combinedAbsorbCount = 0
  local needsPercent, needsMissing, needsCurrent, needsMax = false, false, false, false
  if showHealth then
    for i = 1, #HEALTH_SLOT_FIELDS do
      local fs = frame[HEALTH_SLOT_FIELDS[i]]
      if fs and fs:IsShown() then
        local mode = i == 1 and healthLeft or (i == 2 and healthCenter or healthRight)
        -- Booleans must be selected by branch, never by and/or: a slot whose
        -- flag is false makes `i == n and flagN` yield false and fall through
        -- to the Right slot's flag, so a Left/Center slot silently inherited
        -- Right's "Hide % sign" and absorb icon.
        local hidePercentSymbol, absorbIcon
        if i == 1 then
          hidePercentSymbol, absorbIcon = healthHideLeft, healthIconLeft
        elseif i == 2 then
          hidePercentSymbol, absorbIcon = healthHideCenter, healthIconCenter
        else
          hidePercentSymbol, absorbIcon = healthHideRight, healthIconRight
        end
        local absorbOnly = mode == "ABSORB"
        local slots = absorbOnly and absorbSlots or valueSlots
        local index = absorbOnly and absorbIndex or valueIndex
        local slotNeeds, slotMissing, slotCurrent, slotMax, slotAbsorb, slotAbsorbOnly
        index, slotNeeds, slotMissing, slotCurrent, slotMax, slotAbsorb, slotAbsorbOnly = AddTextSlot(
          slots, index, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals, absorbIcon)
        if slotAbsorbOnly then
          absorbIndex = index
        else
          valueIndex = index
          if slotAbsorb then combinedAbsorbCount = combinedAbsorbCount + 1 end
        end
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
      end
    end
  end
  TrimTextSlots(valueSlots, valueIndex)
  TrimTextSlots(absorbSlots, absorbIndex)
  local valueCount, absorbCount = valueIndex - 1, absorbIndex - 1
  rt.healthSlotCount, rt.healthValueSlotCount, rt.healthAbsorbSlotCount, rt.healthCombinedAbsorbSlotCount =
    valueCount + absorbCount, valueCount, absorbCount, combinedAbsorbCount
  rt.healthUsesAbsorb = (rt.healthAbsorbSlotCount or 0) + (rt.healthCombinedAbsorbSlotCount or 0) > 0
  rt.healthNeedsPercent = needsPercent
  rt.healthNeedsMissing = needsMissing
  rt.healthNeedsCurrent = needsCurrent
  rt.healthNeedsMax = needsMax
  rt.healthColorByHealth = text.healthColorByHealth == true
  rt.healthColorByClass = text.healthColorByClass == true
  if (needsPercent == true or rt.healthColorByHealth == true) and needsCurrent ~= true then
    rt.healthDispatchKeyMode = needsMax == true and DISPATCH_KEY.PERCENT_MAX or DISPATCH_KEY.PERCENT
  elseif needsCurrent == true and needsMax == true then
    rt.healthDispatchKeyMode = DISPATCH_KEY.CURRENT_MAX
  elseif needsMax == true then
    rt.healthDispatchKeyMode = DISPATCH_KEY.MAX
  elseif needsCurrent == true then
    rt.healthDispatchKeyMode = DISPATCH_KEY.CURRENT
  else
    rt.healthDispatchKeyMode = DISPATCH_KEY.NONE
  end
  local baseTextColor = spec and spec.textColor
  rt.textColorR = baseTextColor and baseTextColor.r or 1
  rt.textColorG = baseTextColor and baseTextColor.g or 1
  rt.textColorB = baseTextColor and baseTextColor.b or 1
  rt.textColorA = baseTextColor and baseTextColor.a or 1
  rt.healthTextAlpha = rt.textColorA
  rt._textGradientPct = nil
  -- Slot compilation cannot change the unit key or client secret capability.
  -- Reuse this classification for the three existing plain-writer fields.
  local plainText = nativeSecrets ~= true and frame.MSUFUnitKey == "player"
  rt.healthPlain = plainText
  rt._lastHealthTextHP = nil
  rt._lastHealthTextMax = nil
  rt._lastHealthTextMissing = nil
  rt._lastAbsorbTextValue = nil
  rt.healthAbsorb = nil
  rt._dispatchHealthTextHP = nil
  rt._dispatchHealthTextMax = nil
  rt._dispatchHealthTextMissing = nil
  rt._dispatchHealthMissing = nil
  rt._dispatchHealthMissingReady = nil
  frame._msufTextHealthMax = nil
  frame._msufTextHealthMaxUnit = nil
  frame._msufTextHealthMaxReady = nil

  return CompilePowerRuntime(frame, rt, spec, text, plainText)
end

local function CompileTextRuntime(frame, spec, text)
  local rt = frame._msufTextRuntime
  if not rt then
    rt = {}
    frame._msufTextRuntime = rt
  end
  text = text or {}
  rt.showName = spec and spec.showName ~= false and frame.nameText ~= nil or false
  rt.hideNameOnDeadOffline = text.hideNameOnDeadOffline == true
  local configuredNameShortenMax = text.nameShorten == true and (tonumber(text.nameShortenMax) or 6) or 0
  rt.nameShortenMax = configuredNameShortenMax
  if rt.nameShortenMax > 0 then
    rt.nameShortenMax = floor(max(4, rt.nameShortenMax) + 0.5)
    if rt.nameShortenMax > 40 then
      rt.nameShortenMax = 40
    end
  end
  rt.nameShortenSide = text.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
  local nameAnchor = text.nameAnchor or "LEFT"
  rt.nameShortenDots = text.nameShortenDots ~= false
    and (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "FRAMELEFT")
  rt.nameLegacyTruncation = text.nameLegacyTruncation == true
  rt.nameLegacyShortenMax = rt.nameLegacyTruncation and configuredNameShortenMax or 0
  rt.nameLegacyShortenDots = text.nameShortenDots ~= false
  rt.nameShortenStamp = rt.nameShortenMax > 0 and (rt.nameShortenMax .. ":" .. rt.nameShortenSide .. ":" .. (rt.nameShortenDots and "1" or "0")) or false
  local inline = text.inlineToT
  if inline and inline.enabled == true and spec and spec.key == "target" then
    local inlineRt = rt.inlineToT
    if not inlineRt then
      inlineRt = {}
      rt.inlineToT = inlineRt
    end
    inlineRt.unit = inline.unit or "targettarget"
    inlineRt.separator = inline.separator or " | "
    inlineRt.colorMode = inline.colorMode or "AUTO"
    inlineRt.targetNameClassColor = inline.targetNameClassColor == true
    inlineRt.targetNameNpcColor = inline.targetNameNpcColor == true
    inlineRt.targetNameNpcClassColor = inline.targetNameNpcClassColor == true
    inlineRt.totNameClassColor = inline.totNameClassColor == true
    inlineRt.totNameNpcColor = inline.totNameNpcColor == true
    inlineRt.totNameNpcClassColor = inline.totNameNpcClassColor == true
    inlineRt.nameShortenMax = inline.nameShorten == true and (tonumber(inline.nameShortenMax) or 6) or 0
    if inlineRt.nameShortenMax > 0 then
      inlineRt.nameShortenMax = floor(max(4, inlineRt.nameShortenMax) + 0.5)
      if inlineRt.nameShortenMax > 40 then
        inlineRt.nameShortenMax = 40
      end
    end
    inlineRt.nameShortenSide = inline.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
    inlineRt.nameShortenDots = inline.nameShortenDots ~= false
      and (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "FRAMELEFT")
    inlineRt.stamp = inlineRt.unit .. ":" .. inlineRt.separator .. ":" .. inlineRt.colorMode .. ":" .. (inlineRt.nameShortenMax or 0) .. ":" ..
      inlineRt.nameShortenSide .. ":" .. (inlineRt.nameShortenDots and "1" or "0")
  else
    rt.inlineToT = nil
  end
  return CompileHealthRuntime(frame, rt, spec, text)
end
return AddTextSlot, CompileTextRuntime, TrimTextSlots
end
