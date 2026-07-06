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
local RunCompiledFrameEvent
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
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  end
end

local HOT_EVENT_KIND = Metadata.hotEventKind or {}
local HOT_STATE_SPECS = Metadata.hotStateSpecs or {}

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

local function StrictGroupFrame(frame)
  local spec = frame and frame.MSUFSpec
  return frame and frame._msufIsGroupFrame == true and spec and spec.scope == "group"
end

local function BlockOldGroupHotDispatch(frame, event)
  local gf = MSUF and MSUF.GF
  if gf then
    gf._oldGroupHotDispatchBlocked = (gf._oldGroupHotDispatchBlocked or 0) + 1
  end
  local debug = MSUF and MSUF.Debug
  if debug and debug.groupHot == true then
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    local message = "MSUF GF blocked old dispatcher for " .. tostring(event)
    if type(handler) == "function" then handler(message) else error(message, 2) end
  end
  return true
end

local function StartGFProfileDynamic(prefix, value)
  if not (MSUF and MSUF._profEnabled == true and MSUF.ProfBegin) then
    return nil, nil, nil
  end
  local name = prefix .. tostring(value)
  return MSUF, name, MSUF.ProfBegin(name)
end

local function EndGFProfile(prof, name, token)
  if token and prof and prof.ProfEnd then
    prof.ProfEnd(name, token)
  end
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

RunCompiledPowerText = function(frame, fn, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  if not fn then return end
  local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  if PowerTextNeedsUpdate(frame, powerTick, power, powerMax) then
    fn(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end
end

RunCompiledPowerTextTick = function(frame, fn, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  if not fn then return end
  if PowerTextNeedsTickUpdate(frame, power, powerMax) then
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
  return textFn(frame, event, unit, hp, maxHP)
end

local function RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
  local textFn = state.healthText
  if not textFn then return end
  if not HealthTextNeedsTickUpdate(frame, hp, maxHP) then
    return
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
    RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  end
  return true
end

local function RunHotPowerTextTickOnly(frame, state, event, unit, sameUnit)
  if sameUnit then
    local power, maxPower, powerType, powerToken, powerMetaChanged = state.power(frame, event, unit)
    RunCompiledPowerTextTick(frame, state.powerText, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  end
  return true
end

local function RunHotPowerTextStandalone(frame, state, event, unit, sameUnit)
  if sameUnit then
    RunCompiledPowerText(frame, state.powerText, event, unit)
  end
  return true
end

local function RunHotPowerTextTickStandalone(frame, state, event, unit, sameUnit)
  if sameUnit then
    RunCompiledPowerTextTick(frame, state.powerText, event, unit)
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
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  else
    fn = state.powerText
    RunCompiledPowerText(frame, fn, event, unit)
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
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  else
    fn = state.powerText
    RunCompiledPowerText(frame, fn, event, unit)
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
    RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
  else
    RunCompiledPowerText(frame, state.powerText, event, unit)
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
      local fn = state.prediction
      if fn then fn(frame, event, unit, a, b, c) end
    end
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
  if not StrictGroupFrame(frame) then
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

-- Bakes a direct closure for the unit-filtered case of the NON-value group-state
-- events (UNIT_FLAGS group visuals/status). The pure health/power VALUE cases
-- that used to live here were removed: BuildDirectValueHandler (tried first at
-- the StoreFastEventHandler call) is the single data-driven baker for them, and a
-- /msufprof runnerprobe session proved this legacy baker never produced a
-- health/power handler in practice. Value runners that ever slip through still
-- run correctly via the generic runner path in BuildFastEventHandler.
local function BuildUnitFilteredDirectHandler(event, state, runner)
  local healthFn = state.health
  if runner == RunHotHealthFlagsGroupState then
    local groupVisualsFn = state.groupVisuals
    local groupStatusFn = state.groupStatus
    if healthFn or groupVisualsFn or groupStatusFn then
      return function(frame, _, a, b, c)
        if frame._msufDisabledByConfig == true then return true end
        local unit = frame.unit
        if healthFn then healthFn(frame, event, unit, a, b, c) end
        if groupVisualsFn then groupVisualsFn(frame, event, unit, a, b, c) end
        if groupStatusFn then groupStatusFn(frame, event, unit, a, b, c) end
        return true
      end
    end
  elseif runner == RunHotGroupFlagsState then
    local groupVisualsFn = state.groupVisuals
    local groupStatusFn = state.groupStatus
    if groupVisualsFn or groupStatusFn then
      return function(frame, _, a, b, c)
        if frame._msufDisabledByConfig == true then return true end
        local unit = frame.unit
        if groupVisualsFn then groupVisualsFn(frame, event, unit, a, b, c) end
        if groupStatusFn then groupStatusFn(frame, event, unit, a, b, c) end
        return true
      end
    end
  elseif runner == RunHotGroupStatusOnly and state.groupStatus then
    local groupStatusFn = state.groupStatus
    return function(frame, _, a, b, c)
      if frame._msufDisabledByConfig == true then return true end
      groupStatusFn(frame, event, frame.unit, a, b, c)
      return true
    end
  end
  return nil
end

local function IgnoreFastEvent()
  return true
end

local DIRECT_VALUE_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true,
  UNIT_MAXPOWER = true,
  UNIT_DISPLAYPOWER = true,
  UNIT_POWER_BAR_SHOW = true,
  UNIT_POWER_BAR_HIDE = true,
}

--- Ellesmere-style value hot path: bake the exact health/power work into one
--- closure per frame/event so value ticks do not enter the generic runner layer.
local function BuildDirectValueHandler(event, state)
  if not (state and DIRECT_VALUE_EVENTS[event] == true and state.unitScoped == true) then
    return nil
  end
  if state.inlineUnitless or state.predictionUnitless then
    return nil
  end

  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    local healthFn = state.health
    local textFn = state.healthText
    local predictionFn = state.prediction
    local nameFn = state.name
    local statusTextFn = state.statusText
    local groupVisualsFn = state.groupVisuals
    local groupStatusFn = state.groupStatus
    if not (healthFn or textFn or predictionFn or nameFn or statusTextFn or groupVisualsFn or groupStatusFn) then
      return nil
    end
    local healthTick = event == "UNIT_HEALTH"
    return function(frame, unit, a, b, c)
      if not frame or frame._msufDisabledByConfig == true then
        return true
      end
      if unit and issecretvalue(unit) == true then
        unit = nil
      end
      local frameUnit = frame.unit
      if unit and unit ~= frameUnit then
        return true
      end
      unit = unit or frameUnit
      local hp, maxHP, calc
      local usedGroupHot
      if healthTick and frame._msufIsGroupFrame == true then
        local hot = frame._msufGFHot
        local hotHealth = hot and hot.health
        if hotHealth then
          hotHealth(frame, event, unit)
          usedGroupHot = true
        end
      end
      if healthFn and not usedGroupHot then
        hp, maxHP, calc = healthFn(frame, event, unit)
      end
      if textFn and not usedGroupHot then
        if healthTick then
          if HealthTextNeedsTickUpdate(frame, hp, maxHP) then
            textFn(frame, event, unit, hp, maxHP)
          end
        elseif HealthTextNeedsUpdate(frame, false, hp, maxHP) then
          textFn(frame, event, unit, hp, maxHP)
        end
      end
      if predictionFn and not usedGroupHot then predictionFn(frame, event, unit, hp, maxHP, calc) end
      if nameFn then nameFn(frame, event, unit) end
      if statusTextFn then statusTextFn(frame, event, unit, a, b, c) end
      if groupVisualsFn and not usedGroupHot then groupVisualsFn(frame, event, unit, hp, maxHP, c) end
      if groupStatusFn then groupStatusFn(frame, event, unit, a, b, c) end
      return true
    end
  end

  local powerFn = state.power
  local textFn = state.powerText
  if not (powerFn or textFn) then
    return nil
  end
  local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
  return function(frame, unit, a, b, c)
    if not frame or frame._msufDisabledByConfig == true then
      return true
    end
    if unit and issecretvalue(unit) == true then
      unit = nil
    end
    local frameUnit = frame.unit
    if unit and unit ~= frameUnit then
      return true
    end
    unit = unit or frameUnit
    local power, maxPower, powerType, powerToken, powerMetaChanged
    local usedGroupHot
    if powerTick and frame._msufIsGroupFrame == true then
      local hot = frame._msufGFHot
      local hotPower = hot and hot.power
      if hotPower then
        hotPower(frame, event, unit)
        usedGroupHot = true
      end
    end
    if powerFn and not usedGroupHot then
      power, maxPower, powerType, powerToken, powerMetaChanged = powerFn(frame, event, unit, a, b, c)
    end
    if textFn and not usedGroupHot and PowerTextNeedsUpdate(frame, powerTick, power, maxPower) then
      textFn(frame, event, unit, power, maxPower, powerType, powerToken, powerMetaChanged)
    end
    return true
  end
end

local function StoreFastEventHandler(frame, event, handler)
  if not frame then
    return
  end
  local handlers = frame._msufFastEventHandlers
  if handler then
    if not handlers then
      handlers = {}
      frame._msufFastEventHandlers = handlers
    end
    handlers[event] = handler
  elseif handlers then
    handlers[event] = nil
  end
end

local function CanBindGroupHotHealth(state)
  return state
    and state.health ~= nil
    and not (state.inline or state.inlineUnitless or state.predictionUnitless
      or state.name or state.statusText or state.combat or state.pvp or state.groupStatus)
end

local function CanBindGroupHotPower(state)
  return state and state.power ~= nil
end

function UF.RebindGroupHotEventHandlers(frame)
  if not (frame and frame._msufIsGroupFrame == true) then
    return false
  end
  local hot = frame._msufGFHot
  if not hot then
    return false
  end
  local states = frame._msufHotEventState
  local handlers = frame._msufFastEventHandlers
  if not (states and handlers) then
    return false
  end

  local health = hot.health
  local healthState = states.UNIT_HEALTH
  if health and CanBindGroupHotHealth(healthState) then
    handlers.UNIT_HEALTH = function(frame, unit)
      if frame._msufDisabledByConfig == true then return true end
      return health(frame, "UNIT_HEALTH", unit or frame.unit)
    end
  end

  local power = hot.power
  if power then
    local powerUpdateState = states.UNIT_POWER_UPDATE
    if CanBindGroupHotPower(powerUpdateState) then
      handlers.UNIT_POWER_UPDATE = function(frame, unit)
        if frame._msufDisabledByConfig == true then return true end
        return power(frame, "UNIT_POWER_UPDATE", unit or frame.unit)
      end
    end
    local powerFrequentState = states.UNIT_POWER_FREQUENT
    if CanBindGroupHotPower(powerFrequentState) then
      handlers.UNIT_POWER_FREQUENT = function(frame, unit)
        if frame._msufDisabledByConfig == true then return true end
        return power(frame, "UNIT_POWER_FREQUENT", unit or frame.unit)
      end
    end
  end
  return true
end

local function BuildFastEventHandler(event, state)
  if not state then
    return nil
  end
  if state.empty == true then
    return IgnoreFastEvent
  end
  local runner = state.runner
  if not runner then
    return nil
  end

  local unitScoped = state.unitScoped == true
  local frameUnitFiltered = state.frameUnitFiltered == true
  local needsContext = state.needsDispatchContext == true

  if unitScoped then
    if frameUnitFiltered and not needsContext then
      local direct = BuildUnitFilteredDirectHandler(event, state, runner)
      if direct then
        return direct
      end
      return function(frame, _, a, b, c)
        if frame._msufDisabledByConfig == true then
          return true
        end
        runner(frame, state, event, frame.unit, true, a, b, c)
        return true
      end
    end
    if needsContext then
      return function(frame, unit, a, b, c)
        if not frame or frame._msufDisabledByConfig == true then
          return true
        end
        if unit and issecretvalue(unit) == true then
          unit = nil
        end
        local frameUnit = frame.unit
        if not frameUnitFiltered and unit and unit ~= frameUnit then
          return true
        end
        BeginDispatchContext(frame)
        runner(frame, state, event, unit or frameUnit, true, a, b, c)
        frame._msufDispatchActive = nil
        return true
      end
    end
    return function(frame, unit, a, b, c)
      if not frame or frame._msufDisabledByConfig == true then
        return true
      end
      if unit and issecretvalue(unit) == true then
        unit = nil
      end
      local frameUnit = frame.unit
      if not frameUnitFiltered and unit and unit ~= frameUnit then
        return true
      end
      runner(frame, state, event, unit or frameUnit, true, a, b, c)
      return true
    end
  end

  if needsContext then
    return function(frame, unit, a, b, c)
      if not frame or frame._msufDisabledByConfig == true then
        return true
      end
      if unit and issecretvalue(unit) == true then
        unit = nil
      end
      local frameUnit = frame.unit
      local sameUnit = (not unit) or unit == frameUnit
      local eventUnit = sameUnit and (unit or frameUnit) or unit
      BeginDispatchContext(frame)
      runner(frame, state, event, eventUnit, sameUnit, a, b, c)
      frame._msufDispatchActive = nil
      return true
    end
  end
  return function(frame, unit, a, b, c)
    if not frame or frame._msufDisabledByConfig == true then
      return true
    end
    if unit and issecretvalue(unit) == true then
      unit = nil
    end
    local frameUnit = frame.unit
    local sameUnit = (not unit) or unit == frameUnit
    local eventUnit = sameUnit and (unit or frameUnit) or unit
    runner(frame, state, event, eventUnit, sameUnit, a, b, c)
    return true
  end
end

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
--- That lets RunCompiledFrameEvent use one preselected runner and prebound
--- update functions for common UNIT_* events.
RebuildHotEventState = function(frame, event, owners)
  local kind = HOT_EVENT_KIND[event]
  local states = frame and frame._msufHotEventState
  if not kind or not owners then
    if states then states[event] = nil end
    StoreFastEventHandler(frame, event, nil)
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
  end
  if state.powerText then
    local rt = frame and frame._msufTextRuntime
    local text = MSUF.UFText
    state.powerText = rt and rt.powerHot or (text and text.UpdatePower) or state.powerText
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
  StoreFastEventHandler(frame, event, BuildDirectValueHandler(event, state) or BuildFastEventHandler(event, state))
end

function RunCompiledFrameEvent(frame, event, unit, ...)
  local handlers = frame and frame._msufFastEventHandlers
  local handler = handlers and handlers[event]
  if handler then
    return handler(frame, unit, ...)
  end
  local alias = EVENT_ALIAS[event]
  if alias then
    handler = handlers and handlers[alias]
    if handler then
      return handler(frame, unit, ...)
    end
    event = alias
  end
  if StrictGroupFrame(frame) and HOT_EVENT_KIND[event] then
    return BlockOldGroupHotDispatch(frame, event)
  end
  if HOT_EVENT_KIND[event] then
    return
  end
  return DispatchFrameEvent(frame, event, unit, ...)
end
UF.RunCompiledFrameEvent = RunCompiledFrameEvent
UF.DispatchFastFrameEvent = RunCompiledFrameEvent

--- Direct frame OnEvent entry for RegisterUnitEvent-owned frames. This mirrors
--- EUI/oUF: event arrives on the owning frame, then the prebuilt event closure
--- runs immediately. Hot events without a compiled closure are deliberately
--- dropped; non-hot events still use the normal owner-list dispatcher.
function UF.DispatchHotFrameEvent(frame, event, unit, ...)
  local handlers = frame and frame._msufFastEventHandlers
  local handler = handlers and handlers[event]
  if handler then
    return handler(frame, unit, ...)
  end
  local alias = EVENT_ALIAS[event]
  if alias then
    event = alias
    handler = handlers and handlers[event]
    if handler then
      return handler(frame, unit, ...)
    end
  end
  if HOT_EVENT_KIND[event] then
    return
  end
  return DispatchFrameEvent(frame, event, unit, ...)
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
  local alias = EVENT_ALIAS[event]
  if alias then
    event = alias
  end
  if StrictGroupFrame(frame) and HOT_EVENT_KIND[event] then
    return BlockOldGroupHotDispatch(frame, event)
  end

  local hotStates = frame._msufHotEventState
  local hotState = hotStates and hotStates[event]
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

  if HOT_EVENT_KIND[event] then
    return
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
  MSUF_GF_UNIT_STRUCTURE = true,
}
-- Identity reasons safe to skip for the /msufprof skipident A/B measurement:
-- the target/focus-swap visual refreshes. Excludes the GF structural reasons.
local IDENTITY_SKIPPABLE = {
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
  MSUF_GF_UNIT_STRUCTURE = true,
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

-- Flat identity update list for the LEAN target/focus/ToT swap path. One array
-- of the frame's actual _msufUpdate<Element> functions, in the same order the
-- generic FAST->VISUAL runners would call them, so a swap is just a tight loop
-- (oUF's __elements model) with NO FrameRuntimeUpdate wrapper, reason masks, or
-- per-element RunElementUpdate owner-mode dispatch -- that machinery was the bulk
-- of the swap cost vs oUF. LoadConditions is intentionally OMITTED (visibility
-- is unit-independent and already registered at apply; see LoadConditions.Update
-- guard). Auras are handled by the caller (deferred-notify semantics preserved).
-- FAST bars/text first (health before its text so text can reuse values), then
-- the VISUAL indicator functions.
local IDENTITY_LEAN_KEYS = {
  "_msufUpdateHealth",
  "_msufUpdateHealthText",
  "_msufUpdatePower",
  "_msufUpdatePowerText",
  "_msufUpdateNameText",
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

-- The first N entries of IDENTITY_LEAN_KEYS are the FAST bars/text (health,
-- healthText, power, powerText, name); the remainder are VISUAL. Auras run at
-- the FAST/VISUAL boundary. Keep in sync with IDENTITY_LEAN_KEYS above.
local IDENTITY_LEAN_FAST_KEYS = 5

--- Bake the flat identity fn list AND record how many baked entries are FAST
--- (health/power/text) vs VISUAL, since the baked list only holds functions that
--- actually exist on the frame -- the boundary index shifts per frame.
local function RebuildIdentityList(frame)
  local list = frame._msufIdentityFns or {}
  frame._msufIdentityFns = list
  local labels = frame._msufIdentityLabels or {}
  frame._msufIdentityLabels = labels
  local n, fastN = 0, 0
  for i = 1, #IDENTITY_LEAN_KEYS do
    local fn = frame[IDENTITY_LEAN_KEYS[i]]
    if fn then
      n = n + 1
      list[n] = fn
      labels[n] = IDENTITY_LEAN_KEYS[i]:gsub("^_msufUpdate", "")
      if i <= IDENTITY_LEAN_FAST_KEYS then
        fastN = n
      end
    end
  end
  for i = n + 1, frame._msufIdentityCount or 0 do
    list[i] = nil
    labels[i] = nil
  end
  frame._msufIdentityCount = n > 0 and n or nil
  frame._msufIdentityFastCount = fastN
  if n <= 0 then
    frame._msufIdentityFns = nil
  end
end

--- Precompute the update lists used by runtime identity refreshes. Identity
--- refreshes are narrower than ForceUpdate and deliberately split fast
--- bars/text from aura and visual passes.
function UF.RebuildRuntimeStatusState(frame)
  if not frame then return end
  RebuildRuntimeList(frame, RUNTIME_VISUAL_UPDATE_KEYS, "_msufRuntimeVisualFns", "_msufRuntimeVisualCount")
  RebuildRuntimeList(frame, RUNTIME_SOFT_VISUAL_UPDATE_KEYS, "_msufRuntimeSoftVisualFns", "_msufRuntimeSoftVisualCount")
  RebuildIdentityList(frame)
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

--- LEAN identity refresh for target/focus/ToT swaps (extensible to all single
--- frames). Replaces the FrameRuntimeUpdate wrapper + FAST/AURAS/VISUAL runner
--- stack with oUF's model: gate on unit-exists, then a tight loop over the
--- prebaked _msufIdentityFns. Keeps the two things that path really needed --
--- the native ping-icon refresh and the deferred aura pass -- but drops the
--- reason-mask lookup, per-element RunElementUpdate owner-mode dispatch, and the
--- profiling string-build that made a swap ~16x an oUF swap. Falls back to the
--- generic FrameRuntimeUpdate when no baked list exists (frame not fully applied
--- yet) so behaviour degrades safely. `event` is the identity reason string the
--- element update fns expect (MSUF_UNIT_IDENTITY).
function UF.RunLeanIdentity(frame, event)
  if not frame then return end
  local count = frame._msufIdentityCount
  if not count then
    -- Not baked yet (pre-apply) -- use the full generic path so nothing is missed.
    return UF.FrameRuntimeUpdate and UF.FrameRuntimeUpdate(frame, event or "MSUF_UNIT_IDENTITY")
  end
  local spec = frame.MSUFSpec
  local active = frame._msufActiveElements
  if (spec and spec.enabled == false) or not active then
    return
  end
  local gfDbg = MSUF and MSUF.GF
  if gfDbg and gfDbg._skipIdentity == true then
    return
  end
  event = event or "MSUF_UNIT_IDENTITY"
  -- Aura pass reason must match the identity variant (soft vs full) so the aura
  -- element branches the same way the generic runners did.
  local auraReason = event == "MSUF_UNIT_IDENTITY_SOFT"
    and "MSUF_UNIT_IDENTITY_SOFT_AURAS" or "MSUF_UNIT_IDENTITY_AURAS"
  local unit = frame.unit
  -- Open a dispatch context around the whole pass. RefreshUnitState (the shared
  -- exists/dead/connected/isPlayer/npcKind probe behind health color, name, and
  -- status) caches its result per dispatch token. Without this, EACH consumer
  -- (health, name, statusText) recomputes it -- ~5 unit API calls x3 per swap.
  -- The token makes it compute ONCE and the rest hit the cache. This is what the
  -- normal event path already does; the lean path was missing it -- and the swap
  -- cost is dominated by the health bar's color resolve, which is exactly this.
  BeginDispatchContext(frame)
  -- Native ping icon (MSUF-only, cheap, GUID-deduped). InstallPingCompatibility
  -- is skipped here: the secure binding is unit-token fixed ("target") and set at
  -- apply, so a GUID swap never changes it -- only the icon needs the GUID refresh.
  if UF.RefreshNativePingIcon then UF.RefreshNativePingIcon(frame) end
  -- Missing-unit exit: nothing to draw for a vanished target.
  if RuntimeCanSkipMissingUnit(frame, event) then
    if frame._msufUpdateAuras then
      local aurasFn = frame._msufUpdateAuras
      aurasFn(frame, auraReason, unit)
    end
    frame._msufDispatchActive = nil
    return
  end
  local fns = frame._msufIdentityFns
  local fastCount = frame._msufIdentityFastCount or 0
  local skipFast = gfDbg and gfDbg._skipFast == true
  local skipVisual = gfDbg and gfDbg._skipVisual == true
  -- No FAST elements: run auras before the visual loop (the i==fastCount boundary
  -- below never triggers when fastCount is 0 since the loop starts at 1).
  if fastCount == 0 and not skipFast and frame._msufUpdateAuras then
    frame._msufA3DeferAuraVisualNotify = true
    frame._msufUpdateAuras(frame, auraReason, unit)
    frame._msufA3DeferAuraVisualNotify = nil
  end
  -- FAST bars/text are the first fastCount baked entries; the rest are VISUAL.
  -- Auras run at the boundary to match the generic order (FAST -> auras -> VISUAL).
  for i = 1, count do
    local isFast = i <= fastCount
    if not (isFast and skipFast) and not ((not isFast) and skipVisual) then
      fns[i](frame, event, unit, nil, nil, nil)
    end
    if i == fastCount and not skipFast and frame._msufUpdateAuras then
      frame._msufA3DeferAuraVisualNotify = true
      frame._msufUpdateAuras(frame, auraReason, unit)
      frame._msufA3DeferAuraVisualNotify = nil
    end
  end
  -- Close the dispatch context (paired with BeginDispatchContext above).
  frame._msufDispatchActive = nil
end

-- Diagnostic: print the actual baked identity element list for a unit's frame,
-- so it's visible exactly which element update fns run on a swap (and whether a
-- supposedly-disabled feature is still in there). /msufprof identdump <unit>.
function UF.DumpIdentityList(unit)
  unit = unit or "target"
  local frame = UF.frames and UF.frames[unit]
  local p = _G.print
  if not frame then
    if p then p("|cff7fd5ffMSUF ident|r no frame for '" .. tostring(unit) .. "'") end
    return
  end
  local count = frame._msufIdentityCount or 0
  local fastCount = frame._msufIdentityFastCount or 0
  local labels = frame._msufIdentityLabels
  if p then
    p(string.format("|cff7fd5ffMSUF ident|r unit=%s  count=%d (FAST=%d, VISUAL=%d)",
      tostring(unit), count, fastCount, count - fastCount))
    for i = 1, count do
      local tag = i <= fastCount and "FAST  " or "VISUAL"
      p(string.format("  %d %s %s", i, tag, labels and labels[i] or "?"))
    end
    if count == 0 then p("  (no baked identity list -- generic fallback path)") end
  end
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
  -- A/B measurement hook (/msufprof skipvisual): isolates the VISUAL element list
  -- so !!AddonProfiler can attribute cost to VISUAL vs FAST. Diagnostic only.
  local gfDbg = MSUF and MSUF.GF
  if gfDbg and gfDbg._skipVisual == true then return end
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
  -- A/B triangulation: skipfast disables ONLY the FAST bars/text (+ its auras),
  -- letting VISUAL run. Complements skipvisual. If skipfast rescues perf but
  -- skipvisual does not, the cost is FAST/auras; if neither does but skipident
  -- (whole wrapper) does, the cost is the FrameRuntimeUpdate wrapper itself.
  local gfDbg = MSUF and MSUF.GF
  local skipFast = gfDbg and gfDbg._skipFast == true
  if not skipFast then
    RuntimeRunIdentityFast(frame, reason)
    if frame._msufUpdateAuras then
      frame._msufA3DeferAuraVisualNotify = true
      RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
      frame._msufA3DeferAuraVisualNotify = nil
    end
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
  MSUF_GF_UNIT_STRUCTURE = RuntimeRunGroupIdentity,
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
  -- A/B measurement hook (/msufprof skipident): when set, skip identity refreshes
  -- entirely so C_AddOnProfiler / !!AddonProfiler can measure the TRUE cost of
  -- this path (external metric, free of ProfBegin/End probe overhead). Diagnostic
  -- only; leaves frames stale on swap while enabled. Auto-off in combat is not
  -- needed since it only drops a visual refresh.
  local gfDbg = MSUF and MSUF.GF
  if gfDbg and gfDbg._skipIdentity == true and IDENTITY_SKIPPABLE[reason] then
    return
  end
  reason = reason or "MSUF_FORCE_UPDATE"
  local profGF, profName, profToken = StartGFProfileDynamic("uf:Runtime:", reason)
  local unit = frame.unit
  if RUNTIME_PING_REFRESH[reason] then
    -- One profile bucket for the whole ping block (MSUF-only subsystem oUF lacks);
    -- single ProfBegin/End so no per-call overhead distortion.
    local gf = MSUF and MSUF.GF
    local pt = gf and gf._profDetail == true and gf.ProfBegin and gf.ProfBegin("tgt:PingBlock")
    if UF.InstallPingCompatibility then UF.InstallPingCompatibility(frame) end
    UF.RefreshNativePingIcon(frame)
    if pt and gf.ProfEnd then gf.ProfEnd("tgt:PingBlock", pt) end
  end
  if RuntimeCanSkipMissingUnit(frame, reason) then
    if RUNTIME_MISSING_AURA_CLEAR[reason] == true then
      RuntimeRunIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    end
    EndGFProfile(profGF, profName, profToken)
    return
  end
  local runner = RUNTIME_REASON_RUNNERS[reason]
  if runner then
    -- One bucket for the whole runner (the element updates) so we can compare
    -- element cost vs the ping block above. Single ProfBegin/End, no distortion.
    local gf = MSUF and MSUF.GF
    local rt = gf and gf._profDetail == true and gf.ProfBegin and gf.ProfBegin("tgt:Runner")
    local result = runner(frame, reason)
    if rt and gf.ProfEnd then gf.ProfEnd("tgt:Runner", rt) end
    EndGFProfile(profGF, profName, profToken)
    return result
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
  EndGFProfile(profGF, profName, profToken)
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
