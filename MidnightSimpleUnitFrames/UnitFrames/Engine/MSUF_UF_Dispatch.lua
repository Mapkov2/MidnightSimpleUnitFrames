local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

MSUF.UF = MSUF.UF or {}

--- UnitFrames/Engine/MSUF_UF_Dispatch.lua
---
--- Hot event dispatcher for unit frames. Core decides which frames/elements own
--- an event; this file decides the cheapest way to run that event. The many
--- small runner functions are intentional: they avoid generic element loops for
--- frequent health/power/connection updates and keep text work conditional.
---
--- Rule of thumb for maintainers: add config interpretation in Config, event
--- ownership in Core/element declarations, and only add direct hot handling here
--- when a measured event path is too expensive through the generic runner.

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local Secrets = MSUF.Secrets or {}
local wipe = wipe
local tonumber = tonumber
local type = type
local next = next
local floor = math.floor
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local UnitHealthPercent = _G.UnitHealthPercent
local UnitPowerPercent = _G.UnitPowerPercent
local UnitPowerType = _G.UnitPowerType
local SCALE_100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100

local EVENT_ALIAS = {
  UNIT_MAX_HEALTH_MODIFIERS_CHANGED = "UNIT_MAXHEALTH",
  UNIT_ENTERED_VEHICLE = "UNIT_PORTRAIT_UPDATE",
  UNIT_EXITED_VEHICLE = "UNIT_PORTRAIT_UPDATE",
}

local EMPTY_METADATA_SET = {}
local UPDATE_KEYS = UF._updateKeys or {}
local FrameIsElementEnabled = UF.FrameIsElementEnabled
local RebuildHotEventState
local DispatchFrameEvent
local FrameRuntimeUpdate
local RunCompiledPowerText
local RunCompiledPowerTextTick

local function MissingHealthFromValues(hp, maxHP)
  if issecretvalue(hp) == true or issecretvalue(maxHP) == true then
    return nil
  end
  if type(hp) ~= "number" or type(maxHP) ~= "number" then
    return nil
  end
  local missing = maxHP - hp
  return missing > 0 and missing or 0
end

local function NormalizePercentDecimals(decimals)
  decimals = tonumber(decimals) or 0
  return decimals >= 1 and 1 or 0
end

local function PercentCacheKey(pct, decimals)
  if type(pct) ~= "number" then
    return nil
  end
  if NormalizePercentDecimals(decimals) >= 1 then
    return floor(pct * 10 + 0.5)
  end
  return floor(pct + 0.5)
end

local function HealthPercent(unit)
  if not UnitHealthPercent or not SCALE_100 or type(unit) ~= "string" or unit == "" then
    return nil
  end
  return UnitHealthPercent(unit, true, SCALE_100)
end

local function PowerPercent(unit)
  if not UnitPowerPercent or not SCALE_100 or type(unit) ~= "string" or unit == "" then
    return nil
  end
  local powerType = UnitPowerType and UnitPowerType(unit) or nil
  if issecretvalue(powerType) == true then powerType = nil end
  return UnitPowerPercent(unit, powerType, false, SCALE_100)
end

local function ClearDispatchHealthPercent(rt)
  if rt then
    rt._dispatchHealthPercent = nil
    rt._dispatchHealthPercentReady = nil
  end
end

local function ClearDispatchPowerPercent(rt)
  if rt then
    rt._dispatchPowerPercent = nil
    rt._dispatchPowerPercentReady = nil
  end
end

local function OwnerModeIsUnitless(mode)
  return mode == "unitless" or mode == "both"
end

local function OwnerModeAllowsUnit(mode, frame, unit)
  if mode == nil then
    return nil, false
  end
  local frameUnit = frame.unit
  if unit and unit ~= frameUnit then
    if OwnerModeIsUnitless(mode) then
      return unit, true
    end
    return nil, false
  end
  return unit or frameUnit, true
end

local function BeginDispatchContext(frame)
  frame._msufDispatchToken = (frame._msufDispatchToken or 0) + 1
  frame._msufDispatchActive = true
end

local function FrameForceUpdate(frame, reason)
  if not frame then
    return
  end
  if FrameRuntimeUpdate then
    return FrameRuntimeUpdate(frame, reason or "MSUF_FORCE_UPDATE")
  end
  reason = reason or "MSUF_FORCE_UPDATE"
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if FrameIsElementEnabled(frame, name) then
      local element = UF.elements[name]
      if element and element.Update then
        element.Update(frame, reason, frame.unit)
      end
    end
  end
end

local function RunElementUpdate(frame, owners, name, event, unit, ...)
  if owners then
    local mode = owners[name]
    if mode == nil then return nil end
    local frameUnit = frame.unit
    if unit and unit ~= frameUnit then
      if mode ~= "unitless" and mode ~= "both" then return nil end
    else
      unit = unit or frameUnit
    end
  else
    unit = unit or frame.unit
  end
  local updateFn = frame[UPDATE_KEYS[name]]
  if updateFn then
    return updateFn(frame, event, unit, ...)
  end
  return nil
end

local function RunTextName(frame, owners, event, unit)
  if owners then
    local mode = owners["NameText"]
    if mode == nil then return end
    local frameUnit = frame.unit
    if unit and unit ~= frameUnit and mode ~= "unitless" and mode ~= "both" then
      return
    end
  end
  local updateFn = frame._msufUpdateNameText
  if updateFn then
    return updateFn(frame, event, unit or frame.unit)
  end
end

local function RunHealthHot(frame, owners, event, unit)
  if owners and owners["Health"] == nil then
    return
  end
  unit = unit or frame.unit
  local updateFn = frame._msufUpdateHealth
  if not updateFn then return end
  local hp, maxHP, calc = updateFn(frame, event, unit)
  local textFn = frame._msufUpdateHealthText
  if textFn then
    textFn(frame, event, unit, hp, maxHP)
  end
  return hp, maxHP, calc
end

local function RunPowerHot(frame, owners, event, unit)
  if owners and owners["Power"] == nil then
    return
  end
  unit = unit or frame.unit
  local updateFn = frame._msufUpdatePower
  if not updateFn then return end
  local power, maxPower, powerType, powerToken, powerMetaChanged = updateFn(frame, event, unit)
  local textFn = frame._msufUpdatePowerText
  if textFn then
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, nil, powerType, powerToken, powerMetaChanged)
  end
end

local HOT_EVENT_KIND = Metadata.hotEventKind or {}
local HOT_STATE_SPECS = Metadata.hotStateSpecs or {}
local PREDICTION_QUEUE_BITS = {
  UNIT_HEAL_PREDICTION = 1,
  UNIT_ABSORB_AMOUNT_CHANGED = 2,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 4,
}

local function PredictionMaskFromSpec(frame)
  local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
  if not (cfg and cfg.enabled == true) then
    return 0
  end
  return (cfg.heal == true and 1 or 0)
    + (cfg.absorb == true and 2 or 0)
    + (cfg.healAbsorb == true and 4 or 0)
end

local function PredictionTestMode(frame)
  local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
  return cfg and cfg.enabled == true and cfg.test == true
end

local function PredictionNeedsHealth(frame)
  if PredictionTestMode(frame) then
    return true
  end
  if frame and frame._msufPredictionNeedsHealth ~= nil then
    return frame._msufPredictionNeedsHealth == true
  end
  local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
  return cfg and cfg.heal == true and (tonumber(cfg.healAnchorMode) or 3) == 3
end

local function StatusTextConfig(frame)
  local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
  return status and status.runtimeStatusText == true and status.statusText or nil
end

local function IsGroupFrame(frame)
  local spec = frame and frame.MSUFSpec
  return frame and (frame._msufIsGroupFrame == true or frame._msufCoreScope == "group" or (spec and spec.scope == "group"))
end

--- Text can be as expensive as the bar update it follows. These helpers cache
--- the last relevant numeric key so plain text modes do not rewrite FontStrings
--- when the displayed value would be identical.
local function PowerTextNeedsTickUpdate(frame, power, powerMax)
  local rt = frame and frame._msufTextRuntime
  if not (rt and rt.powerPlain == true) then
    return true
  end
  if nativeSecrets and (issecretvalue(power) == true or issecretvalue(powerMax) == true) then
    ClearDispatchPowerPercent(rt)
    return true
  end
  if power == nil or powerMax == nil then
    ClearDispatchPowerPercent(rt)
    return true
  end
  local keyPower, keyMax
  local mode = rt.powerDispatchKeyMode or 0
  local dispatchPercent, dispatchPercentReady
  if mode == 1 then
    keyPower, keyMax = power, false
  elseif mode == 2 then
    keyPower, keyMax = false, powerMax
  elseif mode == 3 then
    keyPower, keyMax = power, powerMax
  elseif mode == 4 or mode == 5 then
    dispatchPercent = PowerPercent(frame and frame.unit)
    dispatchPercentReady = issecretvalue(dispatchPercent) == true or dispatchPercent ~= nil
    if issecretvalue(dispatchPercent) == true then
      rt._dispatchPowerPercent = dispatchPercent
      rt._dispatchPowerPercentReady = true
      return true
    end
    keyPower = PercentCacheKey(dispatchPercent, 0)
    if keyPower == nil then
      ClearDispatchPowerPercent(rt)
      rt._dispatchPowerTextPower = nil
      rt._dispatchPowerTextMax = nil
      return true
    end
    keyMax = mode == 5 and powerMax or false
  else
    keyPower, keyMax = false, false
  end
  if rt._dispatchPowerTextPower == keyPower and rt._dispatchPowerTextMax == keyMax then
    ClearDispatchPowerPercent(rt)
    return false
  end
  rt._dispatchPowerTextPower = keyPower
  rt._dispatchPowerTextMax = keyMax
  if mode == 4 or mode == 5 then
    rt._dispatchPowerPercent = dispatchPercent
    rt._dispatchPowerPercentReady = dispatchPercentReady
  end
  return true
end

local function PowerTextNeedsUpdate(frame, powerTick, power, powerMax)
  if not powerTick then
    return true
  end
  return PowerTextNeedsTickUpdate(frame, power, powerMax)
end

local function HealthTextNeedsTickUpdate(frame, hp, maxHP)
  local rt = frame and frame._msufTextRuntime
  if not (rt and rt.healthPlain == true) then
    return true
  end
  if nativeSecrets and (issecretvalue(hp) == true or issecretvalue(maxHP) == true) then
    ClearDispatchHealthPercent(rt)
    rt._dispatchHealthMissing = nil
    rt._dispatchHealthMissingReady = nil
    rt.healthMissing = nil
    return true
  end
  if hp == nil or maxHP == nil then
    ClearDispatchHealthPercent(rt)
    rt._dispatchHealthMissing = nil
    rt._dispatchHealthMissingReady = nil
    rt.healthMissing = nil
    return true
  end
  local keyMissing = false
  if rt.healthNeedsMissing == true then
    local missing = MissingHealthFromValues(hp, maxHP)
    if missing == nil then
      local calc = frame and frame._msufHealthCalc
      missing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
    end
    if issecretvalue(missing) == true then
      ClearDispatchHealthPercent(rt)
      return true
    end
    rt._dispatchHealthMissing = missing
    rt._dispatchHealthMissingReady = true
    rt.healthMissing = missing
    keyMissing = missing or false
  else
    rt._dispatchHealthMissing = nil
    rt._dispatchHealthMissingReady = nil
    rt.healthMissing = nil
  end
  local keyHP, keyMax
  local mode = rt.healthDispatchKeyMode or 0
  local dispatchPercent, dispatchPercentReady
  if mode == 1 then
    keyHP, keyMax = hp, false
  elseif mode == 2 then
    keyHP, keyMax = false, maxHP
  elseif mode == 3 then
    keyHP, keyMax = hp, maxHP
  elseif mode == 4 or mode == 5 then
    dispatchPercent = HealthPercent(frame and frame.unit)
    dispatchPercentReady = issecretvalue(dispatchPercent) == true or dispatchPercent ~= nil
    if issecretvalue(dispatchPercent) == true then
      rt._dispatchHealthPercent = dispatchPercent
      rt._dispatchHealthPercentReady = true
      return true
    end
    keyHP = PercentCacheKey(dispatchPercent, rt.healthPercentDecimals)
    if keyHP == nil then
      ClearDispatchHealthPercent(rt)
      rt._dispatchHealthTextHP = nil
      rt._dispatchHealthTextMax = nil
      rt._dispatchHealthTextMissing = nil
      return true
    end
    keyMax = mode == 5 and maxHP or false
  else
    keyHP, keyMax = false, false
  end
  if rt._dispatchHealthTextHP == keyHP
    and rt._dispatchHealthTextMax == keyMax
    and rt._dispatchHealthTextMissing == keyMissing then
    ClearDispatchHealthPercent(rt)
    return false
  end
  rt._dispatchHealthTextHP = keyHP
  rt._dispatchHealthTextMax = keyMax
  rt._dispatchHealthTextMissing = keyMissing
  if mode == 4 or mode == 5 then
    rt._dispatchHealthPercent = dispatchPercent
    rt._dispatchHealthPercentReady = dispatchPercentReady
  end
  return true
end

local function HealthTextNeedsUpdate(frame, healthTick, hp, maxHP)
  if not healthTick then
    return true
  end
  return HealthTextNeedsTickUpdate(frame, hp, maxHP)
end

RunCompiledPowerText = function(frame, fn, event, unit, power, powerMax, dirtyFn, powerType, powerToken, powerMetaChanged)
  if not fn then return end
  local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if PowerTextNeedsUpdate(frame, powerTick, power, powerMax) then
    if dirtyFn and powerTick then
      return dirtyFn(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    fn(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end
end

RunCompiledPowerTextTick = function(frame, fn, event, unit, power, powerMax, dirtyFn, powerType, powerToken, powerMetaChanged)
  if not fn then return end
  if PowerTextNeedsTickUpdate(frame, power, powerMax) then
    if dirtyFn then
      return dirtyFn(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    fn(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end
end

local function HotElementAllowed(frame, event, name)
  if name == "Prediction" then
    if event == "UNIT_HEALTH" then
      return PredictionNeedsHealth(frame)
    end
    if PredictionTestMode(frame) then
      return true
    end
    if frame and frame._msufPredictionMask ~= nil then
      return frame._msufPredictionMask ~= 0
    end
    return PredictionMaskFromSpec(frame) ~= 0
  elseif name == "HealthText" then
    local rt = frame and frame._msufTextRuntime
    return not rt or (rt.healthSlotCount or 0) > 0
  elseif name == "PowerText" then
    local rt = frame and frame._msufTextRuntime
    return not rt or (rt.powerSlotCount or 0) > 0
  elseif name == "StatusTextIndicator" then
    if event == "UNIT_HEALTH" or IsGroupFrame(frame) then
      return false
    end
  elseif name == "PVPIndicator" then
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    local pvp = status and status.pvp
    return event == "UNIT_FACTION" and pvp and pvp.enabled == true
  elseif name == "NameText" and event == "UNIT_HEALTH" then
    return false
  elseif name == "GroupStatusRuntime" then
    local cfg = StatusTextConfig(frame)
    if event == "UNIT_HEALTH" then
      return false
    elseif event == "UNIT_CONNECTION" then
      return cfg and cfg.showDead == true
    elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
      return cfg and (cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true)
    elseif event == "UNIT_FACTION" then
      local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
      return status and status.runtimePVP == true
    end
  end
  return true
end

local function HotAdd(frame, event, state, owners, name, fnKey, modeKey)
  local mode = owners[name]
  if mode == nil then return end
  if HotElementAllowed(frame, event, name) ~= true then return end
  local update = frame and frame[UPDATE_KEYS[name]]
  if not update then
    local element = UF.elements[name]
    update = element and element.Update
  end
  if not update then return end
  state.hasWork = true
  state[fnKey] = update
  if modeKey then
    state[modeKey] = mode
  end
end

local function RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
  local textFn = state.healthText
  if not textFn then return end
  local healthTick = event == "UNIT_HEALTH"
  if not HealthTextNeedsUpdate(frame, healthTick, hp, maxHP) then
    return
  end
  if healthTick then
    local dirtyFn = state.healthTextDirty
    if dirtyFn then
      return dirtyFn(frame, event, unit, hp, maxHP)
    end
  end
  return textFn(frame, event, unit, hp, maxHP)
end

local function RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
  local textFn = state.healthText
  if not textFn then return end
  if not HealthTextNeedsTickUpdate(frame, hp, maxHP) then
    return
  end
  local dirtyFn = state.healthTextDirty
  if dirtyFn then
    return dirtyFn(frame, event, unit, hp, maxHP)
  end
  return textFn(frame, event, unit, hp, maxHP)
end

local function RunHotHealthOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    state.health(frame, event, unit)
  end
  return true
end

local function RunHotHealthNameOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    state.health(frame, event, unit)
    state.name(frame, event, unit)
  end
  return true
end

local function RunHotHealthTextOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP = state.health(frame, event, unit)
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthTextTickOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP = state.health(frame, event, unit)
    RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthPredictionOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    state.prediction(frame, event, unit, hp, maxHP, calc)
  end
  return true
end

local function RunHotHealthTextPredictionOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    state.prediction(frame, event, unit, hp, maxHP, calc)
  end
  return true
end

local function RunHotHealthTextPredictionTickOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    state.prediction(frame, event, unit, hp, maxHP, calc)
  end
  return true
end

local function RunHotHealthGroupVisualsOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP = state.health(frame, event, unit)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthTextGroupVisuals(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP = state.health(frame, event, unit)
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthTextTickGroupVisuals(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP = state.health(frame, event, unit)
    RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthPredictionGroupVisuals(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    state.prediction(frame, event, unit, hp, maxHP, calc)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthTextPredictionGroupVisuals(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    state.prediction(frame, event, unit, hp, maxHP, calc)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthTextPredictionTickGroupVisuals(frame, state, event, unit, sameUnit)
  if sameUnit then
    local hp, maxHP, calc = state.health(frame, event, unit)
    RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    state.prediction(frame, event, unit, hp, maxHP, calc)
    state.groupVisuals(frame, event, unit, hp, maxHP)
  end
  return true
end

local function RunHotHealthFlagsGroupState(frame, state, event, unit, sameUnit)
  if sameUnit then
    local fn = state.health
    if fn then fn(frame, event, unit) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
  end
  return true
end

local function RunHotPowerOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    state.power(frame, event, unit)
  end
  return true
end

local function RunHotPowerTextOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local power, maxPower, powerType, powerToken, powerMetaChanged = state.power(frame, event, unit)
    RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty, powerType, powerToken, powerMetaChanged)
  end
  return true
end

local function RunHotPowerTextTickOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local power, maxPower, powerType, powerToken, powerMetaChanged = state.power(frame, event, unit)
    RunCompiledPowerTextTick(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty, powerType, powerToken, powerMetaChanged)
  end
  return true
end

local function RunHotPowerTextStandalone(frame, state, event, unit, sameUnit)
  if sameUnit then
    RunCompiledPowerText(frame, state.powerText, event, unit, nil, nil, state.powerTextDirty)
  end
  return true
end

local function RunHotPowerTextTickStandalone(frame, state, event, unit, sameUnit)
  if sameUnit then
    RunCompiledPowerTextTick(frame, state.powerText, event, unit, nil, nil, state.powerTextDirty)
  end
  return true
end

local function RunHotKindHealth(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    if state.predictionUnitless then
      local fn = state.prediction
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local hp, maxHP, calc
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    local fn = state.health
    if fn then
      hp, maxHP, calc = fn(frame, event, unit)
      if event == "UNIT_HEALTH" then
        RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
      else
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
      end
    else
      if event == "UNIT_HEALTH" then
        RunCompiledHealthTextTick(frame, state, event, unit)
      else
        RunCompiledHealthText(frame, state, event, unit)
      end
    end
    fn = state.prediction
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit, hp, maxHP, c) end
  else
    local fn = state.health
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.name
    if fn then fn(frame, event, unit) end
    if event == "UNIT_FLAGS" then
      fn = state.statusText
      if fn then fn(frame, event, unit, a, b, c) end
      fn = state.combat
      if fn then fn(frame, event, unit, a, b, c) end
      fn = state.groupVisuals
      if fn then fn(frame, event, unit, a, b, c) end
    end
  end

  local fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotHealthValue(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    if state.predictionUnitless then
      local fn = state.prediction
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local hp, maxHP, calc
  local fn = state.health
  if fn then
    hp, maxHP, calc = fn(frame, event, unit)
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
  else
    RunCompiledHealthText(frame, state, event, unit)
  end
  fn = state.prediction
  if fn then fn(frame, event, unit, hp, maxHP, calc) end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.statusText
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupVisuals
  if fn then fn(frame, event, unit, hp, maxHP, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotHealthFlags(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local fn = state.health
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.statusText
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.combat
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupVisuals
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotHealthFlagsNoCombat(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local fn = state.health
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.statusText
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupVisuals
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotHealthFaction(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local fn = state.health
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.pvp
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotHealthFactionNoPVP(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end

  local fn = state.health
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindPower(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    return true
  end
  local fn = state.power
  if fn then
    local power, maxPower, powerType, powerToken, powerMetaChanged = fn(frame, event, unit)
    local textFn = state.powerText
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, state.powerTextDirty, powerType, powerToken, powerMetaChanged)
  else
    fn = state.powerText
    RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
  end
  return true
end

local function RunHotKindConnection(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.inlineUnitless then
      local fn = state.inline
      if fn then fn(frame, event, unit) end
    end
    if state.predictionUnitless then
      local fn = state.prediction
      if fn then fn(frame, event, unit) end
    end
    return true
  end

  local hp, maxHP, calc
  local fn = state.health
  if fn then
    hp, maxHP, calc = fn(frame, event, unit)
    if event == "UNIT_HEALTH" then
      RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    else
      RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end
  else
    if event == "UNIT_HEALTH" then
      RunCompiledHealthTextTick(frame, state, event, unit)
    else
      RunCompiledHealthText(frame, state, event, unit)
    end
  end
  fn = state.power
  if fn then
    local power, maxPower, powerType, powerToken, powerMetaChanged = fn(frame, event, unit)
    local textFn = state.powerText
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, state.powerTextDirty, powerType, powerToken, powerMetaChanged)
  else
    fn = state.powerText
    RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
  end
  fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.portrait
  if fn then fn(frame, event, unit) end
  fn = state.prediction
  if fn then fn(frame, event, unit, hp, maxHP, calc) end
  fn = state.statusText
  if fn then fn(frame, event, unit) end
  fn = state.groupVisuals
  if fn then fn(frame, event, unit) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit) end
  fn = state.range
  if fn then fn(frame, event, unit) end
  fn = state.groupRange
  if fn then fn(frame, event, unit) end
  return true
end

local function RunConnectionRange(frame, state, event, unit)
  local fn = state.range
  if fn then fn(frame, event, unit) end
  fn = state.groupRange
  if fn then fn(frame, event, unit) end
end

local function RunConnectionGroupState(frame, state, event, unit)
  local fn = state.groupVisuals
  if fn then fn(frame, event, unit) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit) end
end

local function RunConnectionHealth(frame, state, event, unit, force)
  local hp, maxHP, calc
  local fn = state.health
  if fn then
    hp, maxHP, calc = fn(frame, event, unit)
  elseif force then
    hp, maxHP, calc = state.health(frame, event, unit)
  end
  if state.healthText then
    RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
  end
  return hp, maxHP, calc
end

local function RunConnectionPower(frame, state, event, unit)
  local fn = state.power
  if fn then
    local power, maxPower, powerType, powerToken, powerMetaChanged = fn(frame, event, unit)
    RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty, powerType, powerToken, powerMetaChanged)
  else
    RunCompiledPowerText(frame, state.powerText, event, unit, nil, nil, state.powerTextDirty)
  end
end

local function RunConnectionState(frame, state, event, unit, withHealth, withGroup, withRange, withStatusText)
  if withHealth then
    RunConnectionHealth(frame, state, event, unit, true)
  elseif state.healthText then
    RunCompiledHealthText(frame, state, event, unit)
  end
  if withGroup then RunConnectionGroupState(frame, state, event, unit) end
  if withRange then RunConnectionRange(frame, state, event, unit) end
  if withStatusText then
    local fn = state.statusText
    if fn then fn(frame, event, unit) end
  end
end

local function RunConnectionBars(frame, state, event, unit, withName, withPortrait, withPrediction, withGroup, withRange, withStatusText)
  local hp, maxHP, calc = RunConnectionHealth(frame, state, event, unit)
  RunConnectionPower(frame, state, event, unit)
  local fn
  if withName then
    fn = state.name
    if fn then fn(frame, event, unit) end
  end
  if withPortrait then
    fn = state.portrait
    if fn then fn(frame, event, unit) end
  end
  if withPrediction then
    fn = state.prediction
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
  end
  if withGroup then RunConnectionGroupState(frame, state, event, unit) end
  if withRange then RunConnectionRange(frame, state, event, unit) end
  if withStatusText then
    fn = state.statusText
    if fn then fn(frame, event, unit) end
  end
end

local function RunHotConnectionRangeOnly(frame, state, event, unit, sameUnit)
  if sameUnit then RunConnectionRange(frame, state, event, unit) end
  return true
end

local function ConnectionStateRunner(withHealth, withGroup, withRange, withStatusText)
  return function(frame, state, event, unit, sameUnit)
    if sameUnit then RunConnectionState(frame, state, event, unit, withHealth, withGroup, withRange, withStatusText) end
    return true
  end
end

local function ConnectionBarsRunner(withName, withPortrait, withPrediction, withGroup, withRange, withStatusText)
  return function(frame, state, event, unit, sameUnit)
    if sameUnit then RunConnectionBars(frame, state, event, unit, withName, withPortrait, withPrediction, withGroup, withRange, withStatusText) end
    return true
  end
end

local RunHotConnectionLightState = ConnectionStateRunner(false, true, true, true)
local RunHotConnectionHealthRangeState = ConnectionStateRunner(true, true, true, true)
local RunHotConnectionHealthRangeOnly = ConnectionStateRunner(true, false, true, false)
local RunHotConnectionHealthGroupState = ConnectionStateRunner(true, true, false, true)
local RunHotConnectionBarsOnly = ConnectionBarsRunner(false, false, false, false, false, true)
local RunHotConnectionBarsName = ConnectionBarsRunner(true, false, false, false, false, true)
local RunHotConnectionPrimary = ConnectionBarsRunner(true, true, true, false, false, true)
local RunHotConnectionBarsGroupState = ConnectionBarsRunner(false, false, false, true, false, true)
local RunHotConnectionBarsRange = ConnectionBarsRunner(false, false, false, false, true, false)
local RunHotConnectionBarsGroupRange = ConnectionBarsRunner(false, false, false, true, true, true)

local function RunHotKindAura(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    return true
  end
  local fn = state.auras
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindPrediction(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then
    if state.predictionUnitless then
      local queue = state.predictionQueueBit
      if queue and queue(frame, state.predictionBit, unit) then
        return true
      end
      queue = state.predictionQueue or frame._msufQueuePredictionUpdate
      if queue and queue(frame, event, unit) then
        return true
      end
      local fn = state.prediction
      if fn then fn(frame, event, unit, a, b, c) end
    end
    return true
  end
  local queue = state.predictionQueueBit
  if queue and queue(frame, state.predictionBit, unit) then
    return true
  end
  queue = state.predictionQueue or frame._msufQueuePredictionUpdate
  if queue and queue(frame, event, unit) then
    return true
  end
  local fn = state.prediction
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindName(frame, state, event, unit)
  local fn = state.name
  if fn then fn(frame, event, unit) end
  fn = state.inline
  if fn then fn(frame, event, unit) end
  return true
end

local function RunHotKindThreat(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then return true end
  local fn = state.groupVisuals
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupCorners
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.borders
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindPortrait(frame, state, event, unit, sameUnit, a, b, c)
  if not sameUnit then return true end
  local fn = state.portrait
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindClassification(frame, state, event, unit, sameUnit, a, b, c)
  local fn
  if event == "UNIT_LEVEL" then
    fn = state.level
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.elite
    if fn then fn(frame, event, unit, a, b, c) end
  elseif event == "UNIT_CLASSIFICATION_CHANGED" then
    if sameUnit then
      fn = state.health
      if fn then fn(frame, event, unit, a, b, c) end
    end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.inline
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.elite
    if fn then fn(frame, event, unit, a, b, c) end
  elseif event == "INCOMING_RESURRECT_CHANGED" then
    fn = state.incomingRes
    if fn then fn(frame, event, unit, a, b, c) end
  end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindCombat(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.alpha
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.combat
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.load
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.auras
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindRaidTarget(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.raidMarker
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindGroupLeader(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.leader
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.raidGroup
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindLevel(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.level
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindStatus(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.statusText
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindResting(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.resting
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.alpha
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.load
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupStatus
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindTarget(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.inline
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.prediction
  if fn then
    local frameUnit = frame.unit
    if (frameUnit == "targettarget" and unit == "target")
      or (frameUnit == "focustarget" and unit == "focus") then
      fn(frame, event, frameUnit, a, b, c)
    end
  end
  fn = state.alpha
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotKindCooldown(frame, state, event, unit, sameUnit, a, b, c)
  local fn = state.alpha
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.dispel
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupVisuals
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.groupCorners
  if fn then fn(frame, event, unit, a, b, c) end
  fn = state.borders
  if fn then fn(frame, event, unit, a, b, c) end
  return true
end

local function RunHotGroupConnectionState(frame, state, event, unit, sameUnit)
  if sameUnit then
    if state.healthText then
      RunCompiledHealthText(frame, state, event, unit)
    end
    local fn = state.prediction
    if fn then fn(frame, event, unit) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
  end
  return true
end

local function RunHotGroupFlagsState(frame, state, event, unit, sameUnit, a, b, c)
  if sameUnit then
    local fn = state.groupVisuals
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
  end
  return true
end

local function RunHotGroupStatusOnly(frame, state, event, unit, sameUnit, a, b, c)
  if sameUnit then
    local fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
  end
  return true
end

local function SelectHotHealthValueRunner(state, event)
  if state.inline or state.inlineUnitless or state.predictionUnitless
    or state.name or state.statusText or state.combat or state.pvp or state.groupStatus then
    return nil
  end
  local hasHealthText = state.healthText ~= nil
  local hasPrediction = state.prediction ~= nil
  local healthTick = event == "UNIT_HEALTH"
  if not state.health then
    return nil
  end
  if state.groupVisuals then
    if hasPrediction and hasHealthText then
      return healthTick and RunHotHealthTextPredictionTickGroupVisuals or RunHotHealthTextPredictionGroupVisuals
    elseif hasPrediction then
      return RunHotHealthPredictionGroupVisuals
    elseif hasHealthText then
      return healthTick and RunHotHealthTextTickGroupVisuals or RunHotHealthTextGroupVisuals
    end
    return RunHotHealthGroupVisualsOnly
  elseif hasPrediction and hasHealthText then
    return healthTick and RunHotHealthTextPredictionTickOnly or RunHotHealthTextPredictionOnly
  elseif hasPrediction then
    return RunHotHealthPredictionOnly
  elseif hasHealthText then
    return healthTick and RunHotHealthTextTickOnly or RunHotHealthTextOnly
  end
  return RunHotHealthOnly
end

local function SelectHotPowerRunner(state, event)
  local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if state.powerText and state.power then
    return powerTick and RunHotPowerTextTickOnly or RunHotPowerTextOnly
  elseif state.power then
    return RunHotPowerOnly
  elseif state.powerText then
    return powerTick and RunHotPowerTextTickStandalone or RunHotPowerTextStandalone
  end
  return nil
end

local function SelectHotConnectionRunner(state)
  if state.inline or state.inlineUnitless or state.predictionUnitless then
    return nil
  end
  local hasRange = state.range ~= nil or state.groupRange ~= nil
  if not (state.health or state.healthText or state.power or state.powerText
    or state.name or state.portrait or state.prediction or state.groupVisuals or state.groupStatus
    or state.statusText or hasRange) then
    return nil
  end
  if not (state.health or state.power or state.powerText or state.name or state.portrait or state.prediction) then
    if hasRange and not (state.healthText or state.groupVisuals or state.groupStatus or state.statusText) then
      return RunHotConnectionRangeOnly
    end
    if state.healthText or state.groupVisuals or state.groupStatus or state.statusText or hasRange then
      return RunHotConnectionLightState
    end
  end
  if hasRange then
    if state.health
      and not (state.power or state.powerText or state.name or state.portrait or state.prediction) then
      if not (state.groupVisuals or state.groupStatus or state.statusText) then
        return RunHotConnectionHealthRangeOnly
      end
      return RunHotConnectionHealthRangeState
    end
    if not (state.name or state.portrait or state.prediction) then
      if not (state.groupVisuals or state.groupStatus or state.statusText) then
        return RunHotConnectionBarsRange
      end
      return RunHotConnectionBarsGroupRange
    end
    return nil
  end
  if not (state.power or state.powerText or state.portrait) then
    local healthRunner = SelectHotHealthValueRunner(state)
    if healthRunner then
      return healthRunner
    end
    if state.health and (state.groupVisuals or state.groupStatus)
      and not (state.name or state.prediction) then
      return RunHotConnectionHealthGroupState
    end
  end
  if not (state.name or state.portrait or state.prediction) then
    if state.groupVisuals or state.groupStatus then
      return RunHotConnectionBarsGroupState
    end
    return RunHotConnectionBarsOnly
  elseif state.name and not (state.portrait or state.prediction or state.groupVisuals or state.groupStatus) then
    return RunHotConnectionBarsName
  end
  if state.groupVisuals or state.groupStatus then
    return nil
  end
  return RunHotConnectionPrimary
end

local function SelectHotGroupRunner(frame, event, state)
  if not IsGroupFrame(frame) then
    return nil
  end
  if state.inline or state.inlineUnitless or state.predictionUnitless then
    return nil
  end
  if event == "UNIT_CONNECTION" then
    if state.health or state.power or state.powerText
      or state.name or state.portrait or state.statusText then
      return nil
    end
    if state.healthText or state.prediction or state.groupVisuals
      or state.groupStatus or state.range or state.groupRange then
      return RunHotGroupConnectionState
    end
  elseif event == "UNIT_FLAGS" then
    if state.health or state.name or state.statusText or state.combat then
      return nil
    end
    if state.groupVisuals or state.groupStatus then
      return RunHotGroupFlagsState
    end
  elseif event == "UNIT_FACTION" then
    if state.health or state.name or state.pvp then
      return nil
    end
    if state.groupStatus then
      return RunHotGroupStatusOnly
    end
  elseif event == "INCOMING_RESURRECT_CHANGED"
    or event == "UNIT_PHASE"
    or event == "UNIT_OTHER_PARTY_CHANGED" then
    if state.level or state.elite or state.health or state.name or state.incomingRes then
      return nil
    end
    if state.groupStatus then
      return RunHotGroupStatusOnly
    end
  end
  return nil
end

local function SelectHotHealthFlagsRunner(state)
  if state.inline or state.inlineUnitless or state.predictionUnitless
    or state.combat then
    return nil
  end
  if state.statusText then
    return RunHotHealthFlagsNoCombat
  end
  if state.name then
    return state.health and RunHotHealthNameOnly or nil
  end
  if state.groupVisuals or state.groupStatus then
    return RunHotHealthFlagsGroupState
  end
  return state.health and RunHotHealthOnly or nil
end

local function SelectHotHealthFactionRunner(state)
  if state.inline or state.inlineUnitless or state.predictionUnitless
    or state.pvp or state.groupStatus then
    return nil
  end
  if state.name then
    return state.health and RunHotHealthNameOnly or nil
  end
  return state.health and RunHotHealthOnly or nil
end

local HOT_RUNNERS = {
  [1] = RunHotKindHealth,
  [2] = RunHotKindPower,
  [3] = RunHotKindConnection,
  [4] = RunHotKindName,
  [5] = RunHotKindAura,
  [6] = RunHotKindThreat,
  [8] = RunHotKindPortrait,
  [9] = RunHotKindPrediction,
  [10] = RunHotKindClassification,
  [11] = RunHotKindCombat,
  [12] = RunHotKindRaidTarget,
  [13] = RunHotKindGroupLeader,
  [14] = RunHotKindLevel,
  [15] = RunHotKindStatus,
  [16] = RunHotKindResting,
  [17] = RunHotKindTarget,
  [18] = RunHotKindCooldown,
}

local HOT_EVENT_RUNNERS = {
  UNIT_HEALTH = RunHotHealthValue,
  UNIT_MAXHEALTH = RunHotHealthValue,
  UNIT_FLAGS = RunHotHealthFlags,
  UNIT_FACTION = RunHotHealthFaction,
}

do
  local missing
  for event, kind in pairs(HOT_EVENT_KIND) do
    if not (HOT_EVENT_RUNNERS[event] or HOT_RUNNERS[kind]) then
      missing = missing and (missing .. ", " .. tostring(event)) or tostring(event)
    end
  end
  if missing then
    local message = "MSUF UF Dispatch: hot event(s) without a runner -> " .. missing
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then
      handler(message)
    else
      print(message)
    end
  end
end

--- Hot state is built when element ownership changes, not when an event fires.
--- That lets DispatchFrameEvent use one preselected runner and prebound update
--- functions for common UNIT_* events.
RebuildHotEventState = function(frame, event, owners)
  local kind = HOT_EVENT_KIND[event]
  local states = frame and frame._msufHotEventState
  if not kind or not owners then
    if states then states[event] = nil end
    return
  end
  if not states then
    states = {}
    frame._msufHotEventState = states
  end

  local state = states[event]
  if not state then
    state = {}
    states[event] = state
  else
    wipe(state)
  end
  state.kind = kind
  state.runner = HOT_EVENT_RUNNERS[event] or HOT_RUNNERS[kind]

  local spec = HOT_STATE_SPECS[kind]
  if spec then
    for i = 1, #spec do
      local item = spec[i]
      HotAdd(frame, event, state, owners, item[1], item[2], item[3])
    end
  end
  if event == "UNIT_FACTION" and state.pvp == nil then
    state.runner = RunHotHealthFactionNoPVP
  end

  state.inlineUnitless = OwnerModeIsUnitless(state.inlineMode)
  state.predictionUnitless = OwnerModeIsUnitless(state.predictionMode)
  if state.healthText then
    local rt = frame and frame._msufTextRuntime
    local text = MSUF.UFText
    state.healthText = rt and rt.healthHot or (text and text.UpdateHealth) or state.healthText
    state.healthTextDirty = rt and rt.healthDirty or nil
  end
  if state.powerText then
    local rt = frame and frame._msufTextRuntime
    local text = MSUF.UFText
    state.powerText = rt and rt.powerHot or (text and text.UpdatePower) or state.powerText
    state.powerTextDirty = rt and rt.powerDirty or nil
  end
  if state.health and event == "UNIT_HEALTH" then
    state.health = frame._msufUpdateHealthValue or state.health
  elseif state.health and event == "UNIT_MAXHEALTH" then
    state.health = frame._msufUpdateHealthMaxValue or state.health
  elseif state.health and event == "UNIT_CONNECTION" then
    state.health = frame._msufUpdateHealthConnection or state.health
  elseif state.health and event == "UNIT_CLASSIFICATION_CHANGED" then
    state.health = frame._msufUpdateHealthIdentityColor or state.health
  end
  if state.power and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") then
    state.power = frame._msufUpdatePowerValue or state.power
  end
  if state.prediction and event == "UNIT_HEALTH" then
    state.prediction = frame._msufUpdatePredictionHealthValue or state.prediction
  elseif state.prediction and event == "UNIT_CONNECTION" then
    state.prediction = frame._msufUpdatePredictionConnectionState or state.prediction
  elseif state.prediction and kind == 9 then
    state.predictionQueue = frame._msufQueuePredictionUpdate
    state.predictionQueueBit = frame._msufQueuePredictionBit
    state.predictionBit = PREDICTION_QUEUE_BITS[event]
  end
  if state.groupVisuals and (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") then
    state.groupVisuals = frame._msufUpdateGroupVisualsHealthValue or state.groupVisuals
  elseif state.groupVisuals and (event == "UNIT_CONNECTION" or event == "UNIT_FLAGS") then
    state.groupVisuals = frame._msufUpdateGroupVisualsGoneState or state.groupVisuals
  end
  if state.groupStatus and (event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED") then
    state.groupStatus = frame._msufUpdateGroupStatusState or state.groupStatus
  end
  if state.groupRange and event == "UNIT_CONNECTION" then
    state.groupRange = frame._msufUpdateGroupRangeConnection or state.groupRange
  end
  if state.portrait and event == "UNIT_CONNECTION" then
    state.portrait = frame._msufUpdatePortraitConnection or state.portrait
  end
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    state.runner = SelectHotHealthValueRunner(state, event) or state.runner
  elseif event == "UNIT_FLAGS" then
    state.runner = SelectHotHealthFlagsRunner(state) or state.runner
  elseif event == "UNIT_FACTION" then
    state.runner = SelectHotHealthFactionRunner(state) or state.runner
  elseif kind == 2 then
    state.runner = SelectHotPowerRunner(state, event) or state.runner
  elseif kind == 3 then
    state.runner = SelectHotConnectionRunner(state) or state.runner
  end
  state.runner = SelectHotGroupRunner(frame, event, state) or state.runner
  state.unitScoped = not (frame._msufEventUnitless and frame._msufEventUnitless[event])
  state.frameUnitFiltered = state.unitScoped == true
    and frame._msufFrameUnitEvents
    and frame._msufFrameUnitEvents[event] == frame.unit
  local statusEvent = event == "UNIT_CONNECTION" or event == "UNIT_FLAGS"
  if statusEvent then
    local statusConsumers = 0
    if state.name ~= nil then statusConsumers = statusConsumers + 1 end
    if state.prediction ~= nil then statusConsumers = statusConsumers + 1 end
    if state.groupVisuals ~= nil then statusConsumers = statusConsumers + 1 end
    if state.groupStatus ~= nil then statusConsumers = statusConsumers + 1 end
    if state.range ~= nil then statusConsumers = statusConsumers + 1 end
    if state.groupRange ~= nil then statusConsumers = statusConsumers + 1 end
    if state.statusText ~= nil then statusConsumers = statusConsumers + 1 end
    state.needsDispatchContext = (state.health ~= nil and statusConsumers > 0) or statusConsumers > 1
  else
    state.needsDispatchContext = nil
  end
  state.empty = state.hasWork ~= true
end

--- Single frame OnEvent entry point installed by Core. Prefer adding new event
--- handling through hot-state metadata or element ownership rather than adding
--- broad logic here; this function is on every unit-frame event path.
function DispatchFrameEvent(frame, event, unit, ...)
  if not frame or frame._msufDisabledByConfig == true then
    return
  end

  local frameUnit = frame.unit
  if unit and issecretvalue(unit) == true then
    unit = nil
  end

  local hotStates = frame._msufHotEventState
  local hotState = hotStates and hotStates[event]
  if not hotState then
    local alias = EVENT_ALIAS[event]
    if alias then
      event = alias
      hotState = hotStates and hotStates[event]
    end
  end
  if hotState then
    if hotState.empty == true then
      return
    end
    local runner = hotState.runner
    if runner then
      local unitScoped = hotState.unitScoped == true
      if unitScoped and hotState.frameUnitFiltered ~= true and unit and unit ~= frameUnit then
        return
      elseif not unitScoped and unit and unit ~= frameUnit then
        local unitless = frame._msufEventUnitless
        if not (unitless and unitless[event]) then
          return
        end
      end
      local needsContext = hotState.needsDispatchContext == true
      if needsContext then
        BeginDispatchContext(frame)
      end
      local sameUnit = true
      local eventUnit = unit or frameUnit
      if not unitScoped then
        sameUnit = (not unit) or unit == frameUnit
        eventUnit = sameUnit and eventUnit or unit
      end
      if runner(frame, hotState, event, eventUnit, sameUnit, ...) then
        if needsContext then
          frame._msufDispatchActive = nil
        end
        return
      end
      if needsContext then
        frame._msufDispatchActive = nil
      end
    end
  end

  if unit and unit ~= frameUnit then
    local unitless = frame._msufEventUnitless
    if not (unitless and unitless[event]) then
      return
    end
  end

  local allOwners = frame._msufEventOwners
  if not (allOwners and allOwners[event]) then return end
  local lists = frame._msufEventElementLists
  local list = lists and lists[event]
  if not list then
    return
  end
  BeginDispatchContext(frame)
  for i = 1, #list, 2 do
    local update = list[i]
    local eventUnit, ok = OwnerModeAllowsUnit(list[i + 1], frame, unit)
    if ok then
      update(frame, event, eventUnit, ...)
    end
  end
  frame._msufDispatchActive = nil
end
UF.DispatchFrameEvent = DispatchFrameEvent

local RUNTIME_UPDATE_OWNERS = Metadata.runtimeUpdateOwners or EMPTY_METADATA_SET
local RUNTIME_REASON_MASKS = Metadata.runtimeReasonMasks or EMPTY_METADATA_SET
local RUNTIME_IDENTITY_MISSING_EXIT = {
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_DEFERRED = true,
  MSUF_UNIT_IDENTITY_FAST = true,
  MSUF_UNIT_IDENTITY_VISUAL = true,
  MSUF_UNIT_IDENTITY_AURAS = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_DEFERRED = true,
  MSUF_UNIT_IDENTITY_SOFT_FAST = true,
  MSUF_UNIT_IDENTITY_SOFT_VISUAL = true,
  MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
  MSUF_GF_UNIT_IDENTITY = true,
}
local RUNTIME_MISSING_AURA_CLEAR = {
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_DEFERRED = true,
  MSUF_UNIT_IDENTITY_AURAS = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_DEFERRED = true,
  MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
}
local RUNTIME_PING_REFRESH = {
  MSUF_UNIT_IDENTITY = true,
  MSUF_UNIT_IDENTITY_DEFERRED = true,
  MSUF_UNIT_IDENTITY_FAST = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_DEFERRED = true,
  MSUF_GF_UNIT_IDENTITY = true,
}
local BOSS_IDENTITY_UNITS = {
  boss1 = true,
  boss2 = true,
  boss3 = true,
  boss4 = true,
  boss5 = true,
}

local RUNTIME_VISUAL_UPDATE_KEYS = {
  "_msufUpdateInlineToT",
  "_msufUpdatePortrait",
  "_msufUpdateRaidMarkerIndicator",
  "_msufUpdateLeaderIndicator",
  "_msufUpdateLevelIndicator",
  "_msufUpdateRaidGroupIndicator",
  "_msufUpdateEliteIndicator",
  "_msufUpdateStatusTextIndicator",
  "_msufUpdateCombatIndicator",
  "_msufUpdateRestingIndicator",
  "_msufUpdateIncomingResIndicator",
  "_msufUpdatePVPIndicator",
  "_msufUpdateGroupStatusRuntime",
  "_msufUpdatePrediction",
  "_msufUpdateAlpha",
  "_msufUpdateBorders",
}

local RUNTIME_SOFT_VISUAL_UPDATE_KEYS = {
  "_msufUpdateInlineToT",
  "_msufUpdatePortrait",
  "_msufUpdateRaidMarkerIndicator",
  "_msufUpdateLeaderIndicator",
  "_msufUpdateLevelIndicator",
  "_msufUpdateRaidGroupIndicator",
  "_msufUpdateEliteIndicator",
  "_msufUpdateStatusTextIndicator",
  "_msufUpdateCombatIndicator",
  "_msufUpdateRestingIndicator",
  "_msufUpdateIncomingResIndicator",
  "_msufUpdatePVPIndicator",
  "_msufUpdateGroupStatusRuntime",
  "_msufUpdatePrediction",
}

local function RebuildRuntimeList(frame, keys, listKey, countKey)
  local list = frame[listKey]
  if not list then
    list = {}
    frame[listKey] = list
  end
  local n = 0
  for i = 1, #keys do
    local fn = frame[keys[i]]
    if fn then
      n = n + 1
      list[n] = fn
    end
  end
  for i = n + 1, frame[countKey] or 0 do
    list[i] = nil
  end
  frame[countKey] = n > 0 and n or nil
  if n <= 0 then
    frame[listKey] = nil
  end
end

--- Precompute the update lists used by runtime identity refreshes. Identity
--- refreshes are narrower than ForceUpdate and deliberately split fast
--- bars/text from aura and visual passes.
function UF.RebuildRuntimeStatusState(frame)
  if not frame then return end
  RebuildRuntimeList(frame, RUNTIME_VISUAL_UPDATE_KEYS, "_msufRuntimeVisualFns", "_msufRuntimeVisualCount")
  RebuildRuntimeList(frame, RUNTIME_SOFT_VISUAL_UPDATE_KEYS, "_msufRuntimeSoftVisualFns", "_msufRuntimeSoftVisualCount")
end

local function RuntimeCanSkipMissingUnit(frame, reason)
  if not (frame and RUNTIME_IDENTITY_MISSING_EXIT[reason]) then
    return false
  end
  if _G.MSUF_PreviewTestMode == true then
    return false
  end
  if BOSS_IDENTITY_UNITS[frame.unit] == true
    and (_G.MSUF_BossTestMode == true or _G.MSUF2_BossUnitframePreviewActive == true) then
    return false
  end
  return UnitMissing(frame.unit)
end

local function RuntimeRunIdentityFast(frame, reason)
  local unit = frame.unit
  local updateFn = frame._msufUpdateLoadConditions
  if updateFn then updateFn(frame, reason, unit) end
  RunHealthHot(frame, nil, reason, unit)
  RunPowerHot(frame, nil, reason, unit)
  RunTextName(frame, nil, reason, unit)
end

local function RuntimeRunIdentityVisual(frame, reason)
  local count = frame._msufRuntimeVisualCount
  if not count then return end
  local list = frame._msufRuntimeVisualFns
  local unit = frame.unit
  for i = 1, count do
    list[i](frame, reason, unit, nil, nil, nil)
  end
end

local function RuntimeRunIdentitySoftVisual(frame, reason)
  local count = frame._msufRuntimeSoftVisualCount
  if not count then return end
  local list = frame._msufRuntimeSoftVisualFns
  local unit = frame.unit
  for i = 1, count do
    list[i](frame, reason, unit, nil, nil, nil)
  end
end

local function RuntimeRunIdentityAuras(frame, reason)
  local updateFn = frame._msufUpdateAuras
  if updateFn then return updateFn(frame, reason, frame.unit) end
end

local function RuntimeRunIdentityFull(frame, reason)
  RuntimeRunIdentityFast(frame, reason)
  if frame._msufUpdateAuras then
    frame._msufA3DeferAuraVisualNotify = true
    RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    frame._msufA3DeferAuraVisualNotify = nil
  end
  RuntimeRunIdentityVisual(frame, "MSUF_UNIT_IDENTITY_VISUAL")
end

local function RuntimeRunIdentityDeferred(frame)
  if frame._msufUpdateAuras then
    frame._msufA3DeferAuraVisualNotify = true
    RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    frame._msufA3DeferAuraVisualNotify = nil
  end
  RuntimeRunIdentityVisual(frame, "MSUF_UNIT_IDENTITY_VISUAL")
end

local function RuntimeRunIdentitySoftDeferred(frame)
  RuntimeRunIdentityFast(frame, "MSUF_UNIT_IDENTITY_SOFT_FAST")
  if frame._msufUpdateAuras then
    frame._msufA3DeferAuraVisualNotify = true
    RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_SOFT_AURAS")
    frame._msufA3DeferAuraVisualNotify = nil
  end
  RuntimeRunIdentitySoftVisual(frame, "MSUF_UNIT_IDENTITY_SOFT_VISUAL")
end

local function RuntimeRunIdentitySoftFull(frame, reason)
  RuntimeRunIdentityFast(frame, reason)
  if frame._msufUpdateAuras then
    frame._msufA3DeferAuraVisualNotify = true
    RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_SOFT_AURAS")
    frame._msufA3DeferAuraVisualNotify = nil
  end
  RuntimeRunIdentitySoftVisual(frame, "MSUF_UNIT_IDENTITY_SOFT_VISUAL")
end

local function RuntimeRunGroupIdentity(frame, reason)
  local unit = frame.unit
  local updateFn = frame._msufUpdateLoadConditions
  if updateFn then updateFn(frame, reason, unit) end
  local hp, maxHP, calc = RunHealthHot(frame, nil, reason, unit)
  RunPowerHot(frame, nil, reason, unit)
  RunTextName(frame, nil, reason, unit)
  updateFn = frame._msufUpdateGroupStatusRuntime
  if updateFn then updateFn(frame, reason, unit) end
  updateFn = frame._msufUpdatePrediction
  if updateFn then updateFn(frame, reason, unit, hp, maxHP, calc) end
  updateFn = frame._msufUpdateAuras
  if updateFn then
    frame._msufA3DeferAuraVisualNotify = true
    updateFn(frame, reason, unit)
    frame._msufA3DeferAuraVisualNotify = nil
  end
  updateFn = frame._msufUpdateGroupVisuals
  if updateFn then updateFn(frame, reason, unit, hp, maxHP) end
  updateFn = frame._msufUpdateGroupRangeFade
  if updateFn then updateFn(frame, reason, unit) end
  updateFn = frame._msufUpdateBorders
  if updateFn then updateFn(frame, reason, unit) end
end

local RUNTIME_REASON_RUNNERS = {
  MSUF_UNIT_IDENTITY = RuntimeRunIdentityFull,
  MSUF_UNIT_IDENTITY_DEFERRED = RuntimeRunIdentityDeferred,
  MSUF_UNIT_IDENTITY_SOFT = RuntimeRunIdentitySoftFull,
  MSUF_UNIT_IDENTITY_SOFT_DEFERRED = RuntimeRunIdentitySoftDeferred,
  MSUF_UNIT_IDENTITY_FAST = RuntimeRunIdentityFast,
  MSUF_UNIT_IDENTITY_SOFT_FAST = RuntimeRunIdentityFast,
  MSUF_UNIT_IDENTITY_VISUAL = RuntimeRunIdentityVisual,
  MSUF_UNIT_IDENTITY_SOFT_VISUAL = RuntimeRunIdentitySoftVisual,
  MSUF_UNIT_IDENTITY_AURAS = RuntimeRunIdentityAuras,
  MSUF_UNIT_IDENTITY_SOFT_AURAS = RuntimeRunIdentityAuras,
  MSUF_GF_UNIT_IDENTITY = RuntimeRunGroupIdentity,
}

FrameRuntimeUpdate = function(frame, reason)
  if not frame then
    return
  end
  local spec = frame.MSUFSpec
  local active = frame._msufActiveElements
  if (spec and spec.enabled == false) or not active or next(active) == nil then
    return
  end
  reason = reason or "MSUF_FORCE_UPDATE"
  local unit = frame.unit
  if RUNTIME_PING_REFRESH[reason] then
    if UF.InstallPingCompatibility then UF.InstallPingCompatibility(frame) end
    UF.RefreshNativePingIcon(frame)
  end
  if RuntimeCanSkipMissingUnit(frame, reason) then
    if RUNTIME_MISSING_AURA_CLEAR[reason] == true then
      RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    end
    return
  end
  local runner = RUNTIME_REASON_RUNNERS[reason]
  if runner then
    return runner(frame, reason)
  end
  local mask = RUNTIME_REASON_MASKS[reason]
  local hp, maxHP, calc
  if not mask or mask.load then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LoadConditions", reason, unit)
  end
  if not mask or mask.health then
    hp, maxHP, calc = RunHealthHot(frame, RUNTIME_UPDATE_OWNERS, reason, unit)
  end
  if not mask or mask.power then
    RunPowerHot(frame, RUNTIME_UPDATE_OWNERS, reason, unit)
  end
  if not mask or mask.name then
    RunTextName(frame, RUNTIME_UPDATE_OWNERS, reason, unit)
  end
  if not mask or mask.inline then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "InlineToT", reason, unit)
  end
  if not mask or mask.portrait then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Portrait", reason, unit)
  end
  if not mask or mask.status then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RaidMarkerIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LeaderIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LevelIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RaidGroupIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "EliteIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "StatusTextIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "CombatIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RestingIndicator", reason, unit)
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "IncomingResIndicator", reason, unit)
    local status = frame.MSUFSpec and frame.MSUFSpec.status
    local pvp = status and status.pvp
    if pvp and pvp.enabled == true then
      RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "PVPIndicator", reason, unit)
    end
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupStatusRuntime", reason, unit)
  end
  if mask and mask.groupStatus and not mask.status then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupStatusRuntime", reason, unit)
  end
  if not mask or mask.groupVisuals then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupVisuals", reason, unit, hp, maxHP)
  end
  if not mask or mask.prediction then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Prediction", reason, unit, hp, maxHP, calc)
  end
  if not mask or mask.alpha then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Alpha", reason, unit)
  end
  if not mask or mask.range then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RangeFade", reason, unit)
  end
  if not mask or mask.groupRange then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupRangeFade", reason, unit)
  end
  if not mask or mask.borders then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Borders", reason, unit)
  end
  if not mask or mask.auras then
    RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Auras", reason, unit)
  end
end

local function RuntimeUpdateFrame(frame, _, reason)
  FrameRuntimeUpdate(frame, reason)
end

function UF.UpdateRuntime(unit, reason)
  if unit then
    if issecretvalue(unit) == true then
      return false
    end
    local frame = UF.frames[unit]
    if frame then
      FrameRuntimeUpdate(frame, reason)
      return true
    end
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return false
    end
    for i = 1, #units do
      FrameRuntimeUpdate(UF.frames[units[i]], reason)
    end
    return true
  end
  UF.ForEachFrame(RuntimeUpdateFrame, reason)
  return true
end

UF.RebuildHotEventState = RebuildHotEventState
UF.FrameRuntimeUpdate = FrameRuntimeUpdate
UF.FrameForceUpdate = FrameForceUpdate
