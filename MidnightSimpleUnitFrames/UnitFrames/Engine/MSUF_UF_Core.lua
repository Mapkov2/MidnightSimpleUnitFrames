local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

--- UnitFrames/Engine/MSUF_UF_Core.lua
---
--- Owns the frame registry, element registry, and event-routing contract for
--- the unit-frame engine. Config compiles specs, Factory creates/positions
--- frames, Dispatch runs event updates; Core is the glue that keeps those
--- pieces attached without making every element know about every other element.

MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local Metadata = UF.Metadata or {}
local EMPTY_METADATA_SET = {}
local HOT_EVENT_KIND = Metadata.hotEventKind or {}
local type = type
local pairs = pairs
local next = next
local tostring = tostring
local table_sort = table.sort
local pcall = pcall
local unpack = unpack or table.unpack
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local issecretvalue = _G.issecretvalue or function(_) return false end

UF.version = "6.0-clean-core"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.dirtyQueues = UF.dirtyQueues or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
UF.pendingApply = UF.pendingApply or {}
UF.pendingElementRefreshes = UF.pendingElementRefreshes or {}
UF.visualRefreshCallbacks = UF.visualRefreshCallbacks or {}
UF.initialized = UF.initialized or false

UF.unitOrder = {
  "player",
  "target",
  "focus",
  "targettarget",
  "focustarget",
  "pet",
  "boss1",
  "boss2",
  "boss3",
  "boss4",
  "boss5",
}

UF.unitLookup = UF.unitLookup or {}
for i = 1, #UF.unitOrder do
  UF.unitLookup[UF.unitOrder[i]] = true
end

UF.configKeyUnits = UF.configKeyUnits or {
  player = { "player" },
  target = { "target" },
  focus = { "focus" },
  targettarget = { "targettarget" },
  tot = { "targettarget" },
  targetoftarget = { "targettarget" },
  focustarget = { "focustarget" },
  pet = { "pet" },
  boss = { "boss1", "boss2", "boss3", "boss4", "boss5" },
}
UF.singleUnitLists = UF.singleUnitLists or {}

local BOSS_UNITS = {
  boss1 = true,
  boss2 = true,
  boss3 = true,
  boss4 = true,
  boss5 = true,
}

local DEPENDENT_UNIT_PARENTS = {
  targettarget = "target",
  focustarget = "focus",
}
UF.dependentUnitParents = UF.dependentUnitParents or {}
for unit, parent in pairs(DEPENDENT_UNIT_PARENTS) do
  UF.dependentUnitParents[unit] = UF.dependentUnitParents[unit] or parent
end

--- Dependent units look like normal unit tokens to elements, but their identity
--- is owned by their parent target/focus relationship. Runtime has special
--- polling/coalescing for them; keep the relationship centralized here.
function UF.ParentUnitForDependentUnit(unit)
  return UF.dependentUnitParents[unit]
end

function UF.IsDependentUnit(unit)
  return UF.dependentUnitParents[unit] ~= nil
end

function UF.ConfigKeyForUnit(unit)
  if BOSS_UNITS[unit] then
    return "boss"
  end
  if unit == "targetoftarget" or unit == "tot" then
    return "targettarget"
  end
  return unit
end

function UF.IsManagedUnit(unit)
  return UF.unitLookup[unit] == true
end

local function IsUnitToken(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end
UF.IsUnitToken = IsUnitToken

local function UnitExistsSafe(unit)
  if not UnitExists then
    return true
  end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then
    return true
  end
  return exists == true or exists == 1
end
UF.UnitExistsSafe = UnitExistsSafe

local function DispatchToken(frame)
  return frame and frame._msufDispatchActive == true and frame._msufDispatchToken or nil
end
UF.DispatchToken = DispatchToken

local function FreshUnitState(frame, unit)
  local state = frame and frame._msufUnitState
  if state
    and state.ready == true
    and state.unit == unit
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken then
    return state
  end
  return nil
end
UF.FreshUnitState = FreshUnitState

local function ReadConnectedCached(frame, unit, state)
  if state == nil then
    state = FreshUnitState(frame, unit)
  end
  if state and state.connectedKnown == true then
    return state.connected == true, true
  end
  local token = DispatchToken(frame)
  if token
    and frame._msufGFConnectedToken == token
    and frame._msufGFConnectedUnit == unit then
    return frame._msufGFConnectedValue, frame._msufGFConnectedKnown
  end
  if not UnitIsConnected then
    return true, true
  end
  local connected = UnitIsConnected(unit)
  if issecretvalue(connected) == true or connected == nil then
    if token then
      frame._msufGFConnectedToken = token
      frame._msufGFConnectedUnit = unit
      frame._msufGFConnectedValue = true
      frame._msufGFConnectedKnown = false
    end
    return true, false
  end
  connected = connected == true or connected == 1
  if token then
    frame._msufGFConnectedToken = token
    frame._msufGFConnectedUnit = unit
    frame._msufGFConnectedValue = connected
    frame._msufGFConnectedKnown = true
  end
  return connected, true
end
UF.ReadConnectedCached = ReadConnectedCached

local function ReadDeadCached(frame, unit, state)
  if state == nil then
    state = FreshUnitState(frame, unit)
  end
  if state and state.deadKnown == true then
    return state.dead == true, true
  end
  local token = DispatchToken(frame)
  if token
    and frame._msufGFDeadToken == token
    and frame._msufGFDeadUnit == unit then
    return frame._msufGFDeadValue, frame._msufGFDeadKnown
  end
  if not (UnitIsDeadOrGhost or UnitIsDead) then
    return false, true
  end
  local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or nil
  if (issecretvalue(dead) == true or dead == nil) and UnitIsDead then
    dead = UnitIsDead(unit)
  end
  if issecretvalue(dead) == true or dead == nil then
    if token then
      frame._msufGFDeadToken = token
      frame._msufGFDeadUnit = unit
      frame._msufGFDeadValue = false
      frame._msufGFDeadKnown = false
    end
    return false, false
  end
  dead = dead == true or dead == 1
  if token then
    frame._msufGFDeadToken = token
    frame._msufGFDeadUnit = unit
    frame._msufGFDeadValue = dead
    frame._msufGFDeadKnown = true
  end
  return dead, true
end
UF.ReadDeadCached = ReadDeadCached

local function Clamp01(value, fallback)
  value = tonumber(value)
  if value == nil then
    value = fallback
  end
  if value < 0 then
    return 0
  elseif value > 1 then
    return 1
  end
  return value
end
UF.Clamp01 = Clamp01

local function NormalizeDispelDetectTrigger(value)
  value = tostring(value or ""):upper()
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
    return "DISPEL_TYPE"
  elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
    return "ANY_DEBUFF"
  elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
    return "PLAYER_CAST"
  end
  return "BY_ME"
end
UF.NormalizeDispelDetectTrigger = NormalizeDispelDetectTrigger

local function NormalizeDispelOverlayTrigger(value)
  value = tostring(value or ""):upper()
  if value == "BORDER" or value == "INHERIT" or value == "SAME" then
    return "BORDER"
  end
  return NormalizeDispelDetectTrigger(value)
end
UF.NormalizeDispelOverlayTrigger = NormalizeDispelOverlayTrigger

local function NormalizeDispelOverlayStyle(value)
  if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then
    return value
  end
  return "FULL"
end
UF.NormalizeDispelOverlayStyle = NormalizeDispelOverlayStyle

local function NormalizeRangeFadeLayerMode(value)
  if value == "health" or value == "hp" or value == "hpbar" or value == "HP" or value == 2 then
    return "health"
  end
  return "frame"
end
UF.NormalizeRangeFadeLayerMode = NormalizeRangeFadeLayerMode

local function NormalizeAbsorbTestScope(scope)
  scope = tostring(scope or "shared"):lower()
  scope = scope:gsub("%s+", "")
  scope = scope:gsub("%-", "_")
  if scope == "" or scope == "all" or scope == "global" then
    return "shared"
  elseif scope == "gf_party" or scope == "group_party" or scope == "gfparty" then
    return "party"
  elseif scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid" or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then
    return "raid"
  elseif scope == "focus_target" then
    return "focustarget"
  elseif scope == "targetoftarget" or scope == "tot" then
    return "targettarget"
  end
  return scope
end
UF.NormalizeAbsorbTestScope = NormalizeAbsorbTestScope

local function AbsorbTextureTestEnabledForScope(scope)
  if _G.MSUF_AbsorbTextureTestMode ~= true then
    return false
  end
  local wanted = NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
  return wanted == "shared" or wanted == NormalizeAbsorbTestScope(scope)
end
UF.AbsorbTextureTestEnabledForScope = AbsorbTextureTestEnabledForScope

local function ConfigScopedValue(conf, general, key, fallback)
  if conf and conf.hlOverride == true and conf[key] ~= nil then
    return conf[key]
  end
  if general and general[key] ~= nil then
    return general[key]
  end
  return fallback
end
UF.ConfigScopedValue = ConfigScopedValue

local BORDER_PRIORITY_DEFAULTS = { "dispel", "aggro", "purge", "bossTarget" }
local BORDER_PRIORITY_ALLOWED = {
  dispel = true,
  aggro = true,
  purge = true,
  bossTarget = true,
}
local BORDER_PRIORITY_ALIAS = {
  Dispel = "dispel", DISPEL = "dispel",
  Magic = "dispel", MAGIC = "dispel",
  Curse = "dispel", CURSE = "dispel",
  Disease = "dispel", DISEASE = "dispel",
  Poison = "dispel", POISON = "dispel",
  Bleed = "dispel", BLEED = "dispel",
  Aggro = "aggro", AGGRO = "aggro",
  Purge = "purge", PURGE = "purge",
  BossTarget = "bossTarget", Boss_Target = "bossTarget",
  ["Boss Target"] = "bossTarget", ["boss target"] = "bossTarget",
  boss_target = "bossTarget", bosstarget = "bossTarget", BOSS_TARGET = "bossTarget",
}

local function ScopedAliasValue(conf, general, key, legacyKey, fallback)
  if conf and conf.hlOverride == true then
    if conf[key] ~= nil then return conf[key] end
    if legacyKey and conf[legacyKey] ~= nil then return conf[legacyKey] end
  end
  if general then
    if general[key] ~= nil then return general[key] end
    if legacyKey and general[legacyKey] ~= nil then return general[legacyKey] end
  end
  return fallback
end

local function CompileBorderPriority(conf, general)
  local enabled = ScopedAliasValue(conf, general, "hlPrioEnabled", "highlightPrioEnabled", false)
  enabled = enabled == true or enabled == 1 or enabled == "1"
  local raw = ScopedAliasValue(conf, general, "hlPrioOrder", "highlightPrioOrder", nil)
  local order, used = {}, {}
  if type(raw) == "table" then
    for i = 1, #raw do
      local key = raw[i]
      if type(key) == "string" then key = BORDER_PRIORITY_ALIAS[key] or key end
      if BORDER_PRIORITY_ALLOWED[key] and not used[key] then
        order[#order + 1] = key
        used[key] = true
      end
    end
  end
  for i = 1, #BORDER_PRIORITY_DEFAULTS do
    local key = BORDER_PRIORITY_DEFAULTS[i]
    if not used[key] then
      order[#order + 1] = key
      used[key] = true
    end
  end
  return enabled, order
end
UF.CompileBorderPriority = CompileBorderPriority

local GRADIENT_DIR_KEYS = {
  LEFT = "gradientDirLeft",
  RIGHT = "gradientDirRight",
  UP = "gradientDirUp",
  DOWN = "gradientDirDown",
}

local function GradientKeyActive(conf, key)
  if not (conf and conf.hlOverride == true and conf.gradientOverride == true) then
    return false
  end
  if conf.gradientOverrideVersion ~= 2 then
    return conf[key] ~= nil
  end
  return type(conf.gradientOverrideKeys) == "table" and conf.gradientOverrideKeys[key] == true
end

local function GradientScopedValue(conf, general, key, fallback)
  if GradientKeyActive(conf, key) and conf[key] ~= nil then
    return conf[key]
  end
  if general and general[key] ~= nil then
    return general[key]
  end
  return fallback
end

local function ResolveBarGradient(conf, general, enabledKey)
  local left = GradientScopedValue(conf, general, "gradientDirLeft", false) == true
  local right = GradientScopedValue(conf, general, "gradientDirRight", false) == true
  local up = GradientScopedValue(conf, general, "gradientDirUp", false) == true
  local down = GradientScopedValue(conf, general, "gradientDirDown", false) == true
  if not (left or right or up or down) then
    local legacy = GradientScopedValue(conf, general, "gradientDirection", "RIGHT")
    if not GRADIENT_DIR_KEYS[legacy] then
      legacy = "RIGHT"
    end
    if legacy == "LEFT" then
      left = true
    elseif legacy == "UP" then
      up = true
    elseif legacy == "DOWN" then
      down = true
    else
      right = true
    end
  end
  return {
    enabled = GradientScopedValue(conf, general, enabledKey, false) == true,
    strength = Clamp01(GradientScopedValue(conf, general, "gradientStrength", 0.45), 0.45),
    left = left,
    right = right,
    up = up,
    down = down,
  }
end
UF.ResolveBarGradient = ResolveBarGradient

local DISPEL_TYPE_COLORS = {
  { "Magic", 0.20, 0.60, 1.00 },
  { "Curse", 0.60, 0.00, 1.00 },
  { "Disease", 0.60, 0.40, 0.00 },
  { "Poison", 0.00, 0.60, 0.00 },
  { "Bleed", 0.80, 0.10, 0.10 },
}

local function NumberWithFallback(value, fallback)
  value = tonumber(value)
  if value == nil then
    return fallback
  end
  return value
end
UF.NumberWithFallback = NumberWithFallback

function UF.FillDispelTypeColors(dst, general, numberFn)
  numberFn = numberFn or NumberWithFallback
  for i = 1, #DISPEL_TYPE_COLORS do
    local color = DISPEL_TYPE_COLORS[i]
    local key = "type" .. color[1]
    dst[key .. "R"] = numberFn(general and general["dispelType" .. color[1] .. "R"], color[2])
    dst[key .. "G"] = numberFn(general and general["dispelType" .. color[1] .. "G"], color[3])
    dst[key .. "B"] = numberFn(general and general["dispelType" .. color[1] .. "B"], color[4])
  end
end

function UF.FillPredictionColors(dst, general, conf, scopedValue, numberFn)
  scopedValue = scopedValue or ConfigScopedValue
  numberFn = numberFn or NumberWithFallback
  dst.healR = numberFn(general and general.healPredictionColorR, 0)
  dst.healG = numberFn(general and general.healPredictionColorG, 1)
  dst.healB = numberFn(general and general.healPredictionColorB, 0)
  dst.healA = Clamp01(general and general.healPredictionColorA, 0.45)
  dst.absorbR = numberFn(general and general.absorbBarColorR, 1)
  dst.absorbG = numberFn(general and general.absorbBarColorG, 1)
  dst.absorbB = numberFn(general and general.absorbBarColorB, 1)
  dst.absorbA = Clamp01(scopedValue(conf, general, "absorbBarOpacity", general and general.absorbBarColorA), 0.75)
  dst.healAbsorbR = numberFn(general and general.healAbsorbBarColorR, 0.7)
  dst.healAbsorbG = numberFn(general and general.healAbsorbBarColorG, 0)
  dst.healAbsorbB = numberFn(general and general.healAbsorbBarColorB, 0)
  dst.healAbsorbA = Clamp01(scopedValue(conf, general, "healAbsorbBarOpacity", general and general.healAbsorbBarColorA), 1)
end

function UF.UnitsForConfigKey(key)
  local units = UF.configKeyUnits[key]
  if units then
    return units
  end
  if UF.unitLookup[key] then
    units = UF.singleUnitLists[key]
    if not units then
      units = { key }
      UF.singleUnitLists[key] = units
    end
    return units
  end
  return nil
end

function UF.FrameName(unit)
  return "MSUF_" .. tostring(unit or "unknown")
end

local function IsElementRegistered(name)
  return type(name) == "string" and type(UF.elements[name]) == "table"
end

local UPDATE_KEYS = UF._updateKeys or setmetatable({}, {
  __index = function(t, name)
    if type(name) ~= "string" then return nil end
    local key = "_msufUpdate" .. name
    t[name] = key
    return key
  end,
})
UF._updateKeys = UPDATE_KEYS

local function GetUpdateKey(name)
  return UPDATE_KEYS[name]
end

--- Elements are small capability modules (Health, Power, Text, Status, etc.).
--- Registering an element only declares it; frames decide at ApplySpec time
--- whether it is enabled and which events it owns.
function UF.ElementEnabled(element, frame, spec)
  return not element or type(element.IsEnabled) ~= "function" or element.IsEnabled(frame, spec) ~= false
end

local ElementEnabled = UF.ElementEnabled

function UF.RegisterElement(name, element)
  if type(name) ~= "string" or type(element) ~= "table" then
    return false
  end
  if not UF.elements[name] then
    UF.elementOrder[#UF.elementOrder + 1] = name
  end
  UF.elements[name] = element
  Elements[name] = element
  GetUpdateKey(name) -- bake "_msufUpdate"..name into UPDATE_KEYS once
  return true
end

local UNIT_EVENT_HAS_UNIT = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
  UNIT_FLAGS = true,
  UNIT_FACTION = true,
  UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true,
  UNIT_MAXPOWER = true,
  UNIT_DISPLAYPOWER = true,
  UNIT_POWER_BAR_SHOW = true,
  UNIT_POWER_BAR_HIDE = true,
  UNIT_CONNECTION = true,
  UNIT_NAME_UPDATE = true,
  UNIT_TARGET = true,
  UNIT_THREAT_SITUATION_UPDATE = true,
  UNIT_THREAT_LIST_UPDATE = true,
  UNIT_PORTRAIT_UPDATE = true,
  UNIT_MODEL_CHANGED = true,
  UNIT_ENTERED_VEHICLE = true,
  UNIT_EXITED_VEHICLE = true,
  UNIT_HEAL_PREDICTION = true,
  UNIT_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
  UNIT_LEVEL = true,
  UNIT_CLASSIFICATION_CHANGED = true,
  INCOMING_RESURRECT_CHANGED = true,
  UNIT_IN_RANGE_UPDATE = true,
  UNIT_PHASE = true,
  UNIT_CTR_OPTIONS = true,
  UNIT_OTHER_PARTY_CHANGED = true,
  UNIT_AURA = true,
}

--- Event routing model:
--- * eventFrames tracks every frame interested in an event.
--- * eventUnitFrames narrows normal UNIT_* events by concrete unit token.
--- * eventUnitlessFrames handles events where Blizzard gives no useful unit.
--- * eventDerivedFrames handles dependent relationships such as ToT/FoT.
--- Dispatch consumes the owner map built here so hot events do not rediscover
--- which element should run.
local ReindexFrameUnitFilter
local ClearFrameUnitFilter
local ApplyFrameUnitFilter
local EnsureEventDriver
local RefreshEventDriverRegistration
local RefreshFrameUnitEventRouting
local RemoveEventUnitFrame

local eventDriver = UF.eventDriver
local eventFrames = UF.eventFrames or {}
local eventFrameCounts = UF.eventFrameCounts or {}
local eventUnitFrames = UF.eventUnitFrames or {}
local eventUnitlessFrames = UF.eventUnitlessFrames or {}
local eventUnitlessFrameCounts = UF.eventUnitlessFrameCounts or {}
local eventDerivedFrames = UF.eventDerivedFrames or {}
local eventDerivedFrameCounts = UF.eventDerivedFrameCounts or {}
UF.eventFrames = eventFrames
UF.eventFrameCounts = eventFrameCounts
UF.eventUnitFrames = eventUnitFrames
UF.eventUnitlessFrames = eventUnitlessFrames
UF.eventUnitlessFrameCounts = eventUnitlessFrameCounts
UF.eventDerivedFrames = eventDerivedFrames
UF.eventDerivedFrameCounts = eventDerivedFrameCounts

local UNIT_EVENT_UNITLESS_ALLOWED = {
  UNIT_NAME_UPDATE = true,
  UNIT_FACTION = true,
  UNIT_FLAGS = true,
  UNIT_CONNECTION = true,
  UNIT_CLASSIFICATION_CHANGED = true,
}
local INLINE_DERIVED_TARGET_EVENTS = UNIT_EVENT_UNITLESS_ALLOWED

local function UnitEventAllowsUnitless(event)
  return not UNIT_EVENT_HAS_UNIT[event] or UNIT_EVENT_UNITLESS_ALLOWED[event] == true
end

local function DerivedEventSource(frame, event)
  local unit = frame and frame.unit
  if event == "UNIT_TARGET" then
    if unit == "targettarget" then
      return "target"
    elseif unit == "focustarget" then
      return "focus"
    end
  elseif unit == "target" and INLINE_DERIVED_TARGET_EVENTS[event] == true then
    return "targettarget"
  end
  return nil
end

local function DependentEventSource(frame, event)
  local unit = frame and frame.unit
  if event == "UNIT_TARGET" then
    return UF.ParentUnitForDependentUnit and UF.ParentUnitForDependentUnit(unit)
  end
  return nil
end

local function AddEventSource(sourceUnits, sourceSet, unit)
  if not unit or sourceSet[unit] then
    return
  end
  sourceSet[unit] = true
  sourceUnits[#sourceUnits + 1] = unit
end

local function BuildCentralUnitSources(event)
  local sourceUnits, sourceSet = {}, {}
  local byUnit = eventUnitFrames[event]
  if byUnit then
    for unit in pairs(byUnit) do
      AddEventSource(sourceUnits, sourceSet, unit)
    end
  end
  local derived = eventDerivedFrames[event]
  if derived then
    for unit in pairs(derived) do
      AddEventSource(sourceUnits, sourceSet, unit)
    end
  end
  if #sourceUnits > 1 then
    table_sort(sourceUnits)
  end
  return sourceUnits
end

local function CentralDriverRegistration(event)
  if not UNIT_EVENT_HAS_UNIT[event] or eventUnitlessFrameCounts[event] ~= nil then
    return "event", nil, 0
  end
  local sourceUnits = BuildCentralUnitSources(event)
  local count = #sourceUnits
  if count > 0 and eventDriver and eventDriver.RegisterUnitEvent then
    local signature = "unit"
    for i = 1, count do
      signature = signature .. ":" .. sourceUnits[i]
    end
    return signature, sourceUnits, count
  end
  return "event", nil, 0
end

local function FrameUnitMatches(frame, unit)
  if not (frame and unit) then
    return false
  end
  if unit and issecretvalue(unit) == true then
    return false
  end
  local frameUnit = frame.unit
  if frameUnit == unit then
    return true
  end
  local attrUnit = frame.GetAttribute and frame:GetAttribute("unit")
  if issecretvalue(attrUnit) == true then
    return false
  end
  return attrUnit == unit
end

local function EventDriverOnEvent(_, event, unit, ...)
  local frames = eventFrames[event]
  if not frames then
    return
  end
  local dispatch = UF.DispatchFrameEvent
  if not dispatch then
    return
  end

  if UNIT_EVENT_HAS_UNIT[event] then
    if not unit or issecretvalue(unit) == true then
      return
    end

    local unitlessFrames = UnitEventAllowsUnitless(event) and eventUnitlessFrames[event] or nil
    if unitlessFrames then
      for ownerFrame in pairs(unitlessFrames) do
        dispatch(ownerFrame, event, unit, ...)
      end
    end
    local derived = eventDerivedFrames[event]
    local derivedFrames = derived and derived[unit]
    if derivedFrames then
      for frame in pairs(derivedFrames) do
        dispatch(frame, event, unit, ...)
      end
    end
    local unitFrames = eventUnitFrames[event]
    unitFrames = unitFrames and unitFrames[unit]
    if unitFrames then
      for frame in pairs(unitFrames) do
        if not FrameUnitMatches(frame, unit) then
          RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or unit)
        elseif not (unitlessFrames and unitlessFrames[frame]) then
          dispatch(frame, event, unit, ...)
        end
      end
    else
      local frame = UF.frames[unit]
      if frame and frames[frame] and not (unitlessFrames and unitlessFrames[frame])
        and not (frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event]) then
        dispatch(frame, event, unit, ...)
      end
    end
    return
  end

  for frame in pairs(frames) do
    dispatch(frame, event, unit, ...)
  end
end

local function AddDerivedEventFrame(frame, event, sourceUnit)
  if not (frame and event and sourceUnit and UNIT_EVENT_HAS_UNIT[event]) then
    return false
  end
  if frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event] then
    ClearFrameUnitFilter(frame, event)
  end
  local centralUnit = frame._msufDriverEventUnits and frame._msufDriverEventUnits[event]
  if centralUnit then
    RemoveEventUnitFrame(frame, event, centralUnit)
  end
  local byEvent = eventDerivedFrames[event]
  if not byEvent then
    byEvent = {}
    eventDerivedFrames[event] = byEvent
  end
  local byUnit = byEvent[sourceUnit]
  if not byUnit then
    byUnit = {}
    byEvent[sourceUnit] = byUnit
  end
  if byUnit[frame] then
    return true
  end
  byUnit[frame] = true
  eventDerivedFrameCounts[event] = (eventDerivedFrameCounts[event] or 0) + 1
  frame._msufDerivedEventUnits = frame._msufDerivedEventUnits or {}
  frame._msufDerivedEventUnits[event] = sourceUnit
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
  return true
end
local function RemoveDerivedEventFrame(frame, event)
  local sourceUnit = frame and frame._msufDerivedEventUnits and frame._msufDerivedEventUnits[event]
  if not (frame and event and sourceUnit) then
    return
  end
  local byEvent = eventDerivedFrames[event]
  local byUnit = byEvent and byEvent[sourceUnit]
  if byUnit and byUnit[frame] then
    byUnit[frame] = nil
    if next(byUnit) == nil then
      byEvent[sourceUnit] = nil
      if next(byEvent) == nil then
        eventDerivedFrames[event] = nil
      end
    end
    local count = (eventDerivedFrameCounts[event] or 1) - 1
    if count <= 0 then
      eventDerivedFrameCounts[event] = nil
    else
      eventDerivedFrameCounts[event] = count
    end
  end
  frame._msufDerivedEventUnits[event] = nil
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
end

local function AddEventUnitFrame(frame, event, unit)
  if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
    return
  end
  local byEvent = eventUnitFrames[event]
  if not byEvent then
    byEvent = {}
    eventUnitFrames[event] = byEvent
  end
  local byUnit = byEvent[unit]
  if not byUnit then
    byUnit = {}
    byEvent[unit] = byUnit
  end
  byUnit[frame] = true
  frame._msufDriverEventUnits = frame._msufDriverEventUnits or {}
  frame._msufDriverEventUnits[event] = unit
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
end

RemoveEventUnitFrame = function(frame, event, unit)
  if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
    return
  end
  local byEvent = eventUnitFrames[event]
  local byUnit = byEvent and byEvent[unit]
  if byUnit then
    byUnit[frame] = nil
    if next(byUnit) == nil then
      byEvent[unit] = nil
      if next(byEvent) == nil then
        eventUnitFrames[event] = nil
      end
    end
  end
  if frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] == unit then
    frame._msufDriverEventUnits[event] = nil
  end
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
end

local function ReindexFrameUnitEvents(frame, oldUnit, newUnit)
  local registered = frame and frame._msufDriverEventUnits
  if not registered or oldUnit == newUnit then
    return
  end
  for event, unit in pairs(registered) do
    if unit == oldUnit then
      RemoveEventUnitFrame(frame, event, oldUnit)
      AddEventUnitFrame(frame, event, newUnit)
    end
  end
end

function UF.OnUnitChanged(frame, oldUnit, newUnit)
  if not frame then
    return false
  end
  oldUnit = oldUnit or frame.unit
  if newUnit ~= nil then
    frame.unit = newUnit
    frame.unitKey = newUnit
  end
  if RefreshFrameUnitEventRouting then
    RefreshFrameUnitEventRouting(frame)
  else
    ReindexFrameUnitEvents(frame, oldUnit, frame.unit)
    ReindexFrameUnitFilter(frame, oldUnit, frame.unit)
  end
  return true
end

local function PromoteEventToCentralDriver(frame, event)
  if frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event] then
    ClearFrameUnitFilter(frame, event)
  end
end

local function RegisterDriverFrameUnitlessEvent(frame, event)
  local sourceUnit = DerivedEventSource(frame, event)
  if sourceUnit then
    return AddDerivedEventFrame(frame, event, sourceUnit)
  end
  if UNIT_EVENT_HAS_UNIT[event] and not UnitEventAllowsUnitless(event) then
    return false
  end
  PromoteEventToCentralDriver(frame, event)
  local frames = eventUnitlessFrames[event]
  if not frames then
    frames = {}
    eventUnitlessFrames[event] = frames
  end
  if frames[frame] then
    return true
  end
  frames[frame] = true
  eventUnitlessFrameCounts[event] = (eventUnitlessFrameCounts[event] or 0) + 1
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
  return true
end

local function UnregisterDriverFrameUnitlessEvent(frame, event)
  if frame and frame._msufDerivedEventUnits and frame._msufDerivedEventUnits[event] then
    RemoveDerivedEventFrame(frame, event)
    return
  end
  local frames = eventUnitlessFrames[event]
  if not (frames and frames[frame]) then
    return
  end
  frames[frame] = nil
  local count = (eventUnitlessFrameCounts[event] or 1) - 1
  if count <= 0 then
    eventUnitlessFrameCounts[event] = nil
    eventUnitlessFrames[event] = nil
  else
    eventUnitlessFrameCounts[event] = count
  end
  if RefreshEventDriverRegistration then
    RefreshEventDriverRegistration(event)
  end
end

EnsureEventDriver = function()
  if not eventDriver then
    eventDriver = CreateFrame("Frame")
    eventDriver:SetScript("OnEvent", EventDriverOnEvent)
    UF.eventDriver = eventDriver
  end
  return eventDriver
end

local function EventNeedsCentralDriver(event)
  if not event then
    return false
  end
  if UNIT_EVENT_HAS_UNIT[event] then
    return eventUnitlessFrameCounts[event] ~= nil
      or eventUnitFrames[event] ~= nil
      or eventDerivedFrameCounts[event] ~= nil
  end
  return eventFrameCounts[event] ~= nil
end

RefreshEventDriverRegistration = function(event)
  if not event then
    return
  end
  local registered = eventDriver and eventDriver._msufRegistered and eventDriver._msufRegistered[event]
  if EventNeedsCentralDriver(event) then
    EnsureEventDriver()
    local signature, units, unitCount = CentralDriverRegistration(event)
    if registered ~= signature then
      if registered then
        eventDriver:UnregisterEvent(event)
      end
      if units and unitCount > 0 then
        local ok = pcall(eventDriver.RegisterUnitEvent, eventDriver, event, unpack(units, 1, unitCount))
        if not ok then
          eventDriver:RegisterEvent(event)
          signature = "event"
        end
      else
        eventDriver:RegisterEvent(event)
      end
      eventDriver._msufRegistered = eventDriver._msufRegistered or {}
      eventDriver._msufRegistered[event] = signature
    end
  elseif registered then
    eventDriver._msufRegistered[event] = nil
    eventDriver:UnregisterEvent(event)
  end
end

ApplyFrameUnitFilter = function(frame, event, unit)
  if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
    return
  end
  if not frame.RegisterUnitEvent then
    return
  end
  local registered = frame._msufFrameUnitEvents
  if not registered then
    registered = {}
    frame._msufFrameUnitEvents = registered
  end
  if registered[event] == unit then
    return true
  end
  if registered[event] ~= nil and frame.UnregisterEvent then
    frame:UnregisterEvent(event)
    registered[event] = nil
  end
  local ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
  if not ok then
    return false
  end
  registered[event] = unit
  return true
end

ClearFrameUnitFilter = function(frame, event)
  local registered = frame and frame._msufFrameUnitEvents
  if not (registered and registered[event]) then
    return
  end
  registered[event] = nil
  if frame.UnregisterEvent then
    frame:UnregisterEvent(event)
  end
end

ReindexFrameUnitFilter = function(frame, oldUnit, newUnit)
  local registered = frame and frame._msufFrameUnitEvents
  if not registered or oldUnit == newUnit then
    return
  end
  if not newUnit then
    for event in pairs(registered) do
      ClearFrameUnitFilter(frame, event)
    end
    return
  end
  for event, unit in pairs(registered) do
    if unit == oldUnit then
      ApplyFrameUnitFilter(frame, event, newUnit)
    end
  end
end

local function FrameHasUnitlessForEvent(frame, event)
  local unitless = frame and frame._msufEventUnitless
  return unitless and unitless[event] == true
end

RefreshFrameUnitEventRouting = function(frame)
  local ownersByEvent = frame and frame._msufEventOwners
  if not ownersByEvent then
    return
  end
  local unit = frame.unit
  for event in pairs(ownersByEvent) do
    if UNIT_EVENT_HAS_UNIT[event] then
      local centralUnit = frame._msufDriverEventUnits and frame._msufDriverEventUnits[event]
      local dependentSource = DependentEventSource(frame, event)
      if FrameHasUnitlessForEvent(frame, event) then
        if centralUnit then
          RemoveEventUnitFrame(frame, event, centralUnit)
        end
        local sourceUnit = DerivedEventSource(frame, event)
        if sourceUnit then
          AddDerivedEventFrame(frame, event, sourceUnit)
        end
        ClearFrameUnitFilter(frame, event)
      elseif dependentSource then
        if centralUnit then
          RemoveEventUnitFrame(frame, event, centralUnit)
        end
        ClearFrameUnitFilter(frame, event)
        AddDerivedEventFrame(frame, event, dependentSource)
      elseif unit and frame.RegisterUnitEvent and frame._msufCoreOwnEvents ~= false then
        if centralUnit then
          RemoveEventUnitFrame(frame, event, centralUnit)
        end
        if not ApplyFrameUnitFilter(frame, event, unit) then
          AddEventUnitFrame(frame, event, unit)
        end
      else
        ClearFrameUnitFilter(frame, event)
        AddEventUnitFrame(frame, event, unit)
      end
      RefreshEventDriverRegistration(event)
    end
  end
end

local function RegisterDriverFrameEvent(frame, event)
  local frames = eventFrames[event]
  if not frames then
    frames = {}
    eventFrames[event] = frames
  end
  if not frames[frame] then
    frames[frame] = true
    eventFrameCounts[event] = (eventFrameCounts[event] or 0) + 1
  end
  local dependentSource = UNIT_EVENT_HAS_UNIT[event] and DependentEventSource(frame, event) or nil
  if dependentSource then
    ClearFrameUnitFilter(frame, event)
    AddDerivedEventFrame(frame, event, dependentSource)
    RefreshEventDriverRegistration(event)
    return
  end
  if UNIT_EVENT_HAS_UNIT[event]
    and frame.unit
    and frame.RegisterUnitEvent
    and frame._msufCoreOwnEvents ~= false
    and not FrameHasUnitlessForEvent(frame, event)
  then
    if not ApplyFrameUnitFilter(frame, event, frame.unit) then
      AddEventUnitFrame(frame, event, frame.unit)
    end
    RefreshEventDriverRegistration(event)
    return
  end
  ClearFrameUnitFilter(frame, event)
  AddEventUnitFrame(frame, event, frame.unit)
  RefreshEventDriverRegistration(event)
end

local function UnregisterDriverFrameEvent(frame, event)
  local frames = eventFrames[event]
  if not (frames and frames[frame]) then
    return
  end
  frames[frame] = nil
  ClearFrameUnitFilter(frame, event)
  RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or frame.unit)
  local count = (eventFrameCounts[event] or 1) - 1
  if count <= 0 then
    eventFrameCounts[event] = nil
    eventFrames[event] = nil
    eventUnitFrames[event] = nil
    eventUnitlessFrameCounts[event] = nil
    eventUnitlessFrames[event] = nil
    if eventDriver and eventDriver._msufRegistered and eventDriver._msufRegistered[event] then
      eventDriver._msufRegistered[event] = nil
      eventDriver:UnregisterEvent(event)
    end
  else
    eventFrameCounts[event] = count
    RefreshEventDriverRegistration(event)
  end
end

local wipe = _G.wipe or table.wipe
local function ClearArray(t)
  wipe(t)
end

local function RebuildFrameEventList(frame, event)
  local owners = frame and frame._msufEventOwners and frame._msufEventOwners[event]
  local lists = frame and frame._msufEventElementLists
  if not owners then
    if lists then
      lists[event] = nil
    end
    if frame and frame._msufHotEventState then
      frame._msufHotEventState[event] = nil
    end
    return
  end
  if HOT_EVENT_KIND[event] then
    if lists then
      lists[event] = nil
    end
  else
    if not lists then
      lists = {}
      frame._msufEventElementLists = lists
    end
    local list = lists[event]
    if not list then
      list = {}
      lists[event] = list
    else
      ClearArray(list)
    end
    local n = 0
    for i = 1, #UF.elementOrder do
      local name = UF.elementOrder[i]
      local mode = owners[name]
      if mode ~= nil then
        local element = UF.elements[name]
        if element and element.Update then
          n = n + 1
          list[n] = element.Update
          n = n + 1
          list[n] = mode
        end
      end
    end
  end
  local rebuild = UF.RebuildHotEventState
  if rebuild then
    rebuild(frame, event, owners)
  end
end

local function AddChangedEvent(changedEvents, event)
  if not (changedEvents and event) then
    return
  end
  for i = 1, #changedEvents do
    if changedEvents[i] == event then
      return
    end
  end
  changedEvents[#changedEvents + 1] = event
end

local function RebuildFrameEventListOrDefer(frame, event, changedEvents)
  if changedEvents then
    AddChangedEvent(changedEvents, event)
  else
    RebuildFrameEventList(frame, event)
  end
end

local function RegisterElementEvent(frame, elementName, event, unitless, changedEvents)
  if not (frame and event and elementName) then
    return
  end

  local owners = frame._msufEventOwners
  if not owners then
    owners = {}
    frame._msufEventOwners = owners
  end
  local byElement = owners[event]
  local createdOwners = false
  if not byElement then
    byElement = {}
    owners[event] = byElement
    RegisterDriverFrameEvent(frame, event)
    createdOwners = true
  end

  if unitless == true then
    if not RegisterDriverFrameUnitlessEvent(frame, event) then
      if createdOwners then
        owners[event] = nil
        UnregisterDriverFrameEvent(frame, event)
      end
      return
    end
    local unitlessOwners = frame._msufEventUnitless
    if not unitlessOwners then
      unitlessOwners = {}
      frame._msufEventUnitless = unitlessOwners
    end
    unitlessOwners[event] = true
  end
  local previous = byElement[elementName]
  if unitless == true then
    byElement[elementName] = previous == true and "both" or "unitless"
  else
    byElement[elementName] = previous == "unitless" and "both" or true
  end
  RebuildFrameEventListOrDefer(frame, event, changedEvents)
end

--- Removing an element must also tear down event ownership. The owner map can
--- contain unit-only, unitless, or "both" modes, so unregistration keeps the
--- central driver counts in sync instead of just unregistering the frame event.
local function UnregisterElementEvent(frame, owners, elementName, event, changedEvents)
  local byElement = owners and owners[event]
  if not (byElement and byElement[elementName] ~= nil) then
    return
  end
  byElement[elementName] = nil
  if next(byElement) == nil then
    owners[event] = nil
    if frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
      frame._msufEventUnitless[event] = nil
      if next(frame._msufEventUnitless) == nil then
        frame._msufEventUnitless = nil
      end
      UnregisterDriverFrameUnitlessEvent(frame, event)
    end
    RebuildFrameEventListOrDefer(frame, event, changedEvents)
    UnregisterDriverFrameEvent(frame, event)
  elseif frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
    local hasUnitless = false
    for _, mode in pairs(byElement) do
      if mode == "unitless" or mode == "both" then
        hasUnitless = true
        break
      end
    end
    if not hasUnitless then
      frame._msufEventUnitless[event] = nil
      if next(frame._msufEventUnitless) == nil then
        frame._msufEventUnitless = nil
      end
      UnregisterDriverFrameUnitlessEvent(frame, event)
    end
    RebuildFrameEventListOrDefer(frame, event, changedEvents)
  else
    RebuildFrameEventListOrDefer(frame, event, changedEvents)
  end
end

local function UnregisterElementEvents(frame, elementName, changedEvents)
  local owners = frame and frame._msufEventOwners
  if not owners then
    return
  end

  local refs = frame._msufElementEventRefs and frame._msufElementEventRefs[elementName]
  if refs then
    local events = refs.events
    if type(events) == "table" then
      for i = 1, #events do
        UnregisterElementEvent(frame, owners, elementName, events[i], changedEvents)
      end
    end
    events = refs.unitlessEvents
    if type(events) == "table" then
      for i = 1, #events do
        UnregisterElementEvent(frame, owners, elementName, events[i], changedEvents)
      end
    end
    return
  end

  for event, byElement in pairs(owners) do
    if byElement[elementName] ~= nil then
      UnregisterElementEvent(frame, owners, elementName, event, changedEvents)
    end
  end
end

local function ElementEvents(element, kind, frame, spec)
  local getter = kind == "unitless" and element.GetUnitlessEvents or element.GetEvents
  if type(getter) == "function" then
    return getter(frame, spec)
  end
  return kind == "unitless" and element.unitlessEvents or element.events
end

--- Diff each element's declared event set against the frame. Keep new element
--- event declarations as stable tables when possible; stable refs let this
--- function skip rebuild work during repeated ApplySpec calls.
local function SyncElementEvents(frame, name, element, spec)
  local events = ElementEvents(element, "unit", frame, spec)
  local unitlessEvents = ElementEvents(element, "unitless", frame, spec)
  local eventRefs = frame._msufElementEventRefs
  if eventRefs then
    local refs = eventRefs[name]
    if refs and refs.events == events and refs.unitlessEvents == unitlessEvents then
      return
    end
  end

  local changedEvents = frame._msufChangedEventsScratch
  if not changedEvents then
    changedEvents = {}
    frame._msufChangedEventsScratch = changedEvents
  else
    ClearArray(changedEvents)
  end
  UnregisterElementEvents(frame, name, changedEvents)

  if type(events) == "table" then
    for i = 1, #events do
      RegisterElementEvent(frame, name, events[i], false, changedEvents)
    end
  end

  if type(unitlessEvents) == "table" then
    for i = 1, #unitlessEvents do
      RegisterElementEvent(frame, name, unitlessEvents[i], true, changedEvents)
    end
  end

  for i = 1, #changedEvents do
    RebuildFrameEventList(frame, changedEvents[i])
  end
  ClearArray(changedEvents)

  if not eventRefs then
    eventRefs = {}
    frame._msufElementEventRefs = eventRefs
  end
  local refs = eventRefs[name]
  if not refs then
    refs = {}
    eventRefs[name] = refs
  end
  refs.events = events
  refs.unitlessEvents = unitlessEvents
end

local function FrameEnableElement(frame, name)
  if not (frame and IsElementRegistered(name)) then
    return false
  end
  frame._msufActiveElements = frame._msufActiveElements or {}
  local element = UF.elements[name]
  local spec = frame.MSUFSpec
  if frame._msufActiveElements[name] == true then
    SyncElementEvents(frame, name, element, spec)
    return true
  end

  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, spec)
    frame._msufCreatedElements[name] = true
  end
  if element.Enable and element.Enable(frame, spec) == false then
    return false
  end

  if element and element.Update then
    frame[GetUpdateKey(name)] = element.Update
  end
  SyncElementEvents(frame, name, element, spec)
  frame._msufActiveElements[name] = true
  local rebuildRuntimeStatus = UF.RebuildRuntimeStatusState
  if rebuildRuntimeStatus then
    rebuildRuntimeStatus(frame)
  end
  return true
end

local function FrameDisableElement(frame, name)
  if not (frame and frame._msufActiveElements and frame._msufActiveElements[name]) then
    return false
  end
  local element = UF.elements[name]
  UnregisterElementEvents(frame, name)
  if frame._msufElementEventRefs then
    frame._msufElementEventRefs[name] = nil
  end
  frame._msufActiveElements[name] = nil
  frame[GetUpdateKey(name)] = nil
  if element and element.Disable then
    element.Disable(frame)
  end
  local rebuildRuntimeStatus = UF.RebuildRuntimeStatusState
  if rebuildRuntimeStatus then
    rebuildRuntimeStatus(frame)
  end
  return true
end

local function FrameIsElementEnabled(frame, name)
  return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end
UF.FrameIsElementEnabled = FrameIsElementEnabled


--- AttachFrame installs the small Core API onto a concrete frame. Non-unit
--- adapters can opt out of Core's OnEvent ownership but still reuse element
--- enable/disable, spec storage, and runtime refresh plumbing.
function UF.AttachFrameMethods(frame, opts)
  if not frame then
    return frame
  end
  local ownEventScript = not (opts and opts.ownEvents == false) and frame._msufCoreOwnEvents ~= false
  if frame._msufCleanCoreMethods then
    if ownEventScript then
      if frame:GetScript("OnEvent") ~= UF.DispatchFrameEvent then
        frame:SetScript("OnEvent", UF.DispatchFrameEvent)
      end
    elseif frame:GetScript("OnEvent") == UF.DispatchFrameEvent then
      frame:SetScript("OnEvent", nil)
    end
    frame._msufCleanCoreOwnEventScript = ownEventScript and true or nil
    return frame
  end
  frame._msufCleanCoreMethods = true
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  frame.EnableElement = FrameEnableElement
  frame.DisableElement = FrameDisableElement
  frame.IsElementEnabled = FrameIsElementEnabled
  frame.ForceUpdate = UF.FrameForceUpdate
  frame.RegisterElementEvent = RegisterElementEvent
  frame.UnregisterElementEvents = UnregisterElementEvents
  if ownEventScript then
      frame:SetScript("OnEvent", UF.DispatchFrameEvent)
  elseif frame:GetScript("OnEvent") == UF.DispatchFrameEvent then
    frame:SetScript("OnEvent", nil)
  end
  frame._msufCleanCoreOwnEventScript = ownEventScript and true or nil
  return frame
end

function UF.AttachFrame(frame, opts)
  if not frame then
    return nil
  end
  opts = type(opts) == "table" and opts or nil
  if opts and opts.ownEvents ~= nil then
    frame._msufCoreOwnEvents = opts.ownEvents ~= false
  elseif frame._msufCoreOwnEvents == nil then
    frame._msufCoreOwnEvents = true
  end
  frame._msufCoreScope = opts and opts.scope or frame._msufCoreScope or "unit"
  frame._msufCoreAdapter = opts and opts.adapter or frame._msufCoreAdapter
  frame._msufVisualRoot = opts and opts.visualRoot or frame._msufVisualRoot or frame
  UF.AttachFrameMethods(frame, opts)
  if opts and opts.unit ~= nil then
    UF.OnUnitChanged(frame, frame.unit, opts.unit)
  end
  if frame._msufDispatchToken == nil then
    frame._msufDispatchToken = 0
  end
  if UF.attachedFrames[frame] ~= true then
    UF.attachedFrames[frame] = true
    UF.attachedFrameList[#UF.attachedFrameList + 1] = frame
  end
  return frame
end

function UF.ForEachFrame(fn, a, b, c)
  if type(fn) ~= "function" then
    return
  end
  local any
  for i = 1, #UF.unitOrder do
    local frame = UF.frames[UF.unitOrder[i]]
    if frame then
      if fn(frame, frame.unit, a, b, c) == true then
        any = true
      end
    end
  end
  return any
end

function UF.ForEachAttachedFrame(fn, scope)
  if type(fn) ~= "function" then
    return
  end
  for i = 1, #UF.attachedFrameList do
    local frame = UF.attachedFrameList[i]
    if frame and UF.attachedFrames[frame] == true and (scope == nil or frame._msufCoreScope == scope) then
      fn(frame, frame.unit)
    end
  end
end

function UF.SetFrameSpec(frame, spec, unitFallback)
  if not (frame and spec) then
    return frame
  end
  frame.MSUFSpec = spec
  frame.cachedConfig = spec
  frame.configKey = spec.key
  frame.unitKey = spec.unit or unitFallback or frame.unit
  return frame
end

function UF.DetachFrame(frame)
  if not frame then
    return false
  end
  if frame._msufActiveElements then
    while true do
      local name = next(frame._msufActiveElements)
      if not name then break end
      FrameDisableElement(frame, name)
    end
  end
  local owners = frame._msufEventOwners
  if owners then
    for event in pairs(owners) do
      if frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
        UnregisterDriverFrameUnitlessEvent(frame, event)
      end
      UnregisterDriverFrameEvent(frame, event)
    end
  end
  local driverUnits = frame._msufDriverEventUnits
  if driverUnits then
    for event, unit in pairs(driverUnits) do
      RemoveEventUnitFrame(frame, event, unit)
    end
  end
  local derivedUnits = frame._msufDerivedEventUnits
  if derivedUnits then
    for event in pairs(derivedUnits) do
      RemoveDerivedEventFrame(frame, event)
    end
  end
  frame._msufEventOwners = nil
  frame._msufEventUnitless = nil
  frame._msufElementEventRefs = nil
  frame._msufEventElementLists = nil
  frame._msufHotEventState = nil
  frame._msufRuntimeVisualFns = nil
  frame._msufRuntimeVisualCount = nil
  frame._msufRuntimeSoftVisualFns = nil
  frame._msufRuntimeSoftVisualCount = nil
  frame._msufChangedEventsScratch = nil
  frame._msufDriverEventUnits = nil
  frame._msufDerivedEventUnits = nil
  frame._msufCoreScope = nil
  frame._msufCoreAdapter = nil
  UF.attachedFrames[frame] = nil
  for i = #UF.attachedFrameList, 1, -1 do
    if UF.attachedFrameList[i] == frame then
      table.remove(UF.attachedFrameList, i)
      break
    end
  end
  return true
end

function UF.GetFrame(unit)
  if unit and issecretvalue(unit) == true then return nil end
  return UF.frames[unit]
end

function UF.Apply(unit)
  local factory = UF.Factory
  if not (factory and factory.Apply) then
    return false
  end
  return factory.Apply(unit)
end

local function ForceUpdateFrame(frame)
  UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
end

function UF.ForceUpdate(unit)
  if InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(unit)
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
      factory.EnsureDeferredDriver()
    end
    return false
  end
  if unit then
    if issecretvalue(unit) == true then
      return false
    end
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return false
    end
    for i = 1, #units do
      local frame = UF.frames[units[i]]
      if frame then
        UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
      end
    end
    return true
  end
  UF.ForEachFrame(ForceUpdateFrame)
  return true
end

local function ApplyElementToFrame(frame, name, spec, updateReason)
  local element = UF.elements[name]
  if not (frame and element) then
    return false
  end
  if spec then
    UF.SetFrameSpec(frame, spec)
  elseif frame.MSUFSpec then
    UF.SetFrameSpec(frame, frame.MSUFSpec)
  end
  local enabled = ElementEnabled(element, frame, frame.MSUFSpec)
  if not enabled then
    if not FrameDisableElement(frame, name) and element.Disable then
      element.Disable(frame)
    end
    return true
  end
  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, frame.MSUFSpec)
    frame._msufCreatedElements[name] = true
  end
  if element.Apply then
    element.Apply(frame, frame.MSUFSpec)
  end
  FrameEnableElement(frame, name)
  if updateReason and element.Update then
    element.Update(frame, updateReason, frame.unit)
  end
  return true
end

UF.ApplyElementToFrame = ApplyElementToFrame

local DEFAULT_APPLY_MASK = Metadata.defaultApplyMask or EMPTY_METADATA_SET

function UF.ApplySpec(frame, spec, reason, mask)
  if not (frame and spec) then
    return false
  end
  UF.AttachFrame(frame, {
    scope = frame._msufCoreScope,
    visualRoot = frame._msufVisualRoot,
    ownEvents = frame._msufCoreOwnEvents,
  })
  UF.SetFrameSpec(frame, spec)
  mask = mask or DEFAULT_APPLY_MASK
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if mask == true or mask[name] == true then
      ApplyElementToFrame(frame, name, nil, nil)
    end
  end
  if reason then
    UF.FrameRuntimeUpdate(frame, reason)
  end
  return true
end
