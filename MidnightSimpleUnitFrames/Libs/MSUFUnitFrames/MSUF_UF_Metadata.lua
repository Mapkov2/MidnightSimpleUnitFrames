-- Instance-local runtime metadata for the embedded MSUFUnitFrames framework.
local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
UF.Metadata = Metadata

-- UnitFrames metadata catalogue.
-- Centralizes element event groups, runtime dirty masks, and reason-to-mask mappings so
-- factory/apply/dispatch code can share stable names without hard-coded duplicates.
-- The unit catalogue and the apply-time spec normalizers live at the end of this
-- file (ahead of MSUF_UF_Core in the embed order) so the core carries only the
-- compiled event routes and the frame runtime.
local pairs = pairs
local type = type
local string_gmatch = string.gmatch

local function BuildNameList(names)
  if type(names) == "table" then return names end
  local list = {}
  for name in string_gmatch(names or "", "%S+") do
    list[#list + 1] = name
  end
  return list
end

local function BuildNameSet(names)
  names = BuildNameList(names)
  local set = {}
  for i = 1, #names do
    set[names[i]] = true
  end
  return set
end

local function BuildEventKindMap(groups)
  local map = {}
  for kind, events in pairs(groups) do
    events = BuildNameList(events)
    for i = 1, #events do
      map[events[i]] = kind
    end
  end
  return map
end

local function AddRuntimeReasonMasks(target, mask, reasons)
  reasons = BuildNameList(reasons)
  for i = 1, #reasons do
    target[reasons[i]] = mask
  end
end

local function BuildHotSpecs(spec)
  local out = {}
  for entry in string_gmatch(spec or "", "%S+") do
    local element, state, mode = entry:match("^([^:]+):([^:]+):?([^:]*)$")
    out[#out + 1] = mode and mode ~= "" and { element, state, mode } or { element, state }
  end
  return out
end

Metadata.BuildNameSet = BuildNameSet
Metadata.BuildNameList = BuildNameList

Metadata.hotEventKind = BuildEventKindMap({
  [1] = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_FLAGS UNIT_FACTION",
  [2] = "UNIT_POWER_UPDATE UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_POWER_BAR_SHOW UNIT_POWER_BAR_HIDE",
  [3] = "UNIT_CONNECTION",
  [4] = "UNIT_NAME_UPDATE",
  [6] = "UNIT_THREAT_SITUATION_UPDATE UNIT_THREAT_LIST_UPDATE",
  [8] = "UNIT_PORTRAIT_UPDATE UNIT_MODEL_CHANGED",
  [9] = "UNIT_HEAL_PREDICTION UNIT_ABSORB_AMOUNT_CHANGED UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
  [10] = "UNIT_LEVEL UNIT_CLASSIFICATION_CHANGED INCOMING_RESURRECT_CHANGED",
  [11] = "PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED",
  [12] = "RAID_TARGET_UPDATE",
  [13] = "GROUP_ROSTER_UPDATE PARTY_LEADER_CHANGED",
  [14] = "PLAYER_LEVEL_UP PLAYER_LEVEL_CHANGED",
  [15] = "PLAYER_FLAGS_CHANGED UNIT_PHASE UNIT_OTHER_PARTY_CHANGED",
  [16] = "PLAYER_UPDATE_RESTING PLAYER_ENTERING_WORLD",
  [17] = "UNIT_TARGET",
  [18] = "SPELL_UPDATE_COOLDOWN SPELLS_CHANGED",
})

Metadata.hotStateSpecs = {
  [1] = BuildHotSpecs(
    "InlineToT:inline:inlineMode Prediction:prediction:predictionMode " ..
    "Health:health HealthText:healthText NameText:name StatusTextIndicator:statusText " ..
    "CombatIndicator:combat PVPIndicator:pvp GroupVisuals:groupVisuals GroupStatusRuntime:groupStatus"),
  [2] = BuildHotSpecs("Power:power PowerText:powerText"),
  [3] = BuildHotSpecs(
    "InlineToT:inline:inlineMode Prediction:prediction:predictionMode Health:health " ..
    "HealthText:healthText Power:power PowerText:powerText NameText:name Portrait:portrait " ..
    "StatusTextIndicator:statusText GroupVisuals:groupVisuals GroupStatusRuntime:groupStatus " ..
    "RangeFade:range GroupRangeFade:groupRange"),
  [4] = BuildHotSpecs("NameText:name InlineToT:inline:inlineMode"),
  [6] = BuildHotSpecs("GroupVisuals:groupVisuals GroupCornerIndicators:groupCorners Borders:borders"),
  [8] = BuildHotSpecs("Portrait:portrait"),
  [9] = BuildHotSpecs("Prediction:prediction:predictionMode"),
  [10] = BuildHotSpecs(
    "LevelIndicator:level EliteIndicator:elite Health:health NameText:name InlineToT:inline:inlineMode " ..
    "IncomingResIndicator:incomingRes GroupStatusRuntime:groupStatus"),
  [11] = BuildHotSpecs("Alpha:alpha CombatIndicator:combat LoadConditions:load"),
  [12] = BuildHotSpecs("RaidMarkerIndicator:raidMarker GroupStatusRuntime:groupStatus"),
  [13] = BuildHotSpecs("LeaderIndicator:leader RaidGroupIndicator:raidGroup GroupStatusRuntime:groupStatus"),
  [14] = BuildHotSpecs("LevelIndicator:level"),
  [15] = BuildHotSpecs("StatusTextIndicator:statusText GroupStatusRuntime:groupStatus"),
  [16] = BuildHotSpecs("RestingIndicator:resting Alpha:alpha LoadConditions:load GroupStatusRuntime:groupStatus"),
  [17] = BuildHotSpecs("InlineToT:inline:inlineMode Prediction:prediction:predictionMode Alpha:alpha"),
  [18] = BuildHotSpecs("Alpha:alpha Borders:borders"),
}

Metadata.runtimeUpdateOwners = BuildNameSet(
  "Health Power Text NameText HealthText PowerText InlineToT Portrait Alpha " ..
  "StatusIndicators RaidMarkerIndicator LeaderIndicator LevelIndicator " ..
  "RaidGroupIndicator EliteIndicator StatusTextIndicator CombatIndicator " ..
  "RestingIndicator IncomingResIndicator PVPIndicator StanceIndicator " ..
  "TempMaxHealth Prediction Borders " ..
  "LoadConditions GroupStatusRuntime RangeFade GroupRangeFade GroupVisuals " ..
  "GroupCornerIndicators")

local MASK_HEALTH = { health = true }
local MASK_POWER = { power = true }
local MASK_ALPHA = { alpha = true }
local MASK_BORDERS = { borders = true }
local MASK_BAR_OUTLINE = { power = true, borders = true }
local MASK_DISPEL_VISUAL = { borders = true, auras = true }
local MASK_PREDICTION = { prediction = true }
local MASK_TEMP_MAX_HEALTH = { tempMaxHealth = true }
local MASK_FONT_RUNTIME = BuildNameSet("health power name")
local MASK_TEXT_STATUS_RUNTIME = BuildNameSet("health power name status")
local MASK_DISABLED = {}
local MASK_CASTBAR_SYNC = BuildNameSet("health power name portrait status borders")
local MASK_BARS_BORDERS = BuildNameSet("health power borders")
local MASK_COLOR_CHANGE = BuildNameSet("health power name inline portrait status tempMaxHealth prediction borders")
local MASK_UNIT_IDENTITY = BuildNameSet("load health power name inline portrait status tempMaxHealth prediction alpha borders")
local MASK_UNIT_IDENTITY_FAST = BuildNameSet("load health power name")
local MASK_UNIT_IDENTITY_VISUAL = BuildNameSet("inline portrait status tempMaxHealth prediction alpha borders")
local MASK_UNIT_IDENTITY_AURAS = { auras = true }
local MASK_UNIT_IDENTITY_SOFT = BuildNameSet("load health power name inline portrait status tempMaxHealth prediction")
local MASK_UNIT_IDENTITY_SOFT_FAST = MASK_UNIT_IDENTITY_FAST
local MASK_UNIT_IDENTITY_SOFT_VISUAL = BuildNameSet("inline portrait status tempMaxHealth prediction")
local MASK_UNIT_IDENTITY_SOFT_AURAS = { auras = true }
local MASK_GROUP_UNIT_IDENTITY = BuildNameSet("load health power name groupStatus tempMaxHealth prediction groupVisuals groupRange borders")
local MASK_GROUP_UNIT_STRUCTURE = BuildNameSet("load health power name groupStatus tempMaxHealth prediction groupVisuals groupRange borders auras")

-- StatusIndicators owns region creation/layout, while the per-indicator elements
-- own initial state, event routing, and their cached status spec.  They therefore
-- form one apply transaction: applying only the structure leaves the icons inert
-- until a later status-specific settings refresh.
local STATUS_APPLY_ELEMENTS =
  "StatusIndicators RaidMarkerIndicator LeaderIndicator LevelIndicator " ..
  "RaidGroupIndicator EliteIndicator StatusTextIndicator CombatIndicator " ..
  "RestingIndicator IncomingResIndicator PVPIndicator StanceIndicator"

local runtimeReasonMasks = {}
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_FONT_RUNTIME, "FONT_RUNTIME MSUF2_HP_TEXT_COLOR")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_CASTBAR_SYNC, "CASTBAR_SYNC")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY, "MSUF_UNIT_IDENTITY")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_FAST, "MSUF_UNIT_IDENTITY_FAST")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_VISUAL, "MSUF_UNIT_IDENTITY_VISUAL")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_AURAS, "MSUF_UNIT_IDENTITY_AURAS")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT, "MSUF_UNIT_IDENTITY_SOFT")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_FAST, "MSUF_UNIT_IDENTITY_SOFT_FAST")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_VISUAL, "MSUF_UNIT_IDENTITY_SOFT_VISUAL")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_AURAS, "MSUF_UNIT_IDENTITY_SOFT_AURAS")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_GROUP_UNIT_IDENTITY, "MSUF_GF_UNIT_IDENTITY")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_GROUP_UNIT_STRUCTURE, "MSUF_GF_UNIT_STRUCTURE")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_ALPHA, "MSUF_ALPHA")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BORDERS, "MSUF_BORDER_LAYOUT MSUF2_BORDER")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BAR_OUTLINE, "MSUF2_BAR_OUTLINE MSUF2_BAR_OUTLINE_COLOR")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_DISPEL_VISUAL,
  "MSUF2_DISPEL_BORDER MSUF2_DISPEL_TRIGGER MSUF2_UF_DISPEL_OVERLAY " ..
  "MSUF2_UF_DISPEL_OVERLAY_TRIGGER MSUF2_UF_DISPEL_OVERLAY_STYLE " ..
  "MSUF2_UF_DISPEL_OVERLAY_HEALTH MSUF2_UF_DISPEL_OVERLAY_ALPHA")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BORDERS, "MSUF_GF_DIRTY_BORDER")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_DISABLED, "MSUF_GF_DIRTY_AURAS")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_TEXT_STATUS_RUNTIME, "MSUF_GF_DIRTY_FONT")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BARS_BORDERS,
  "MSUF2_GRADIENT MSUF2_HP_GRADIENT MSUF2_POWER_GRADIENT " ..
  "MSUF2_GRADIENT_STRENGTH MSUF2_GRADIENT_DIRECTION")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_COLOR_CHANGE, "MSUF_COLOR_CHANGE")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_TEMP_MAX_HEALTH,
  "MSUF2_TEMP_MAX_HEALTH MSUF2_TEMP_MAX_HEALTH_ENABLED MSUF2_TEMP_MAX_HEALTH_TEXTURE " ..
  "MSUF2_TEMP_MAX_HEALTH_COLOR MSUF2_TEMP_MAX_HEALTH_OPACITY " ..
  "MSUF2_TEMP_MAX_HEALTH_BACKGROUND MSUF2_TEMP_MAX_HEALTH_TEST")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_PREDICTION,
  "MSUF2_ABSORB_MODE MSUF2_ABSORB MSUF2_ABSORB_ANCHOR MSUF2_ABSORB_OPACITY " ..
  "MSUF2_ABSORB_TEXTURE MSUF2_ABSORB_TEST MSUF2_ABSORB_TEST_CLEAR " ..
  "MSUF2_OVER_ABSORB_OVERLAY " ..
  "MSUF2_HEAL_ABSORB MSUF2_HEAL_ABSORB_OPACITY MSUF2_HEAL_ABSORB_TEXTURE " ..
  "MSUF2_HEALPRED_ANCHOR MSUF2_SELF_HEAL MSUF2_GF_HEALPRED")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_POWER,
  "MSUF_POWER_LAYOUT MSUF_POWER_TEXT_COLORS MSUF2_POWER_SHOW MSUF2_POWER_BORDER " ..
  "MSUF2_POWER_BORDER_SIZE MSUF2_POWER_HEIGHT MSUF2_POWER_EMBED " ..
  "MSUF2_POWER_SMOOTH MSUF2_BARS_SMOOTH_POWER MSUF2_BARS_REALTIME_POWER " ..
  "MSUF2_POWER_DETACHED MSUF2_POWER_DETACHED_TEXT " ..
  "MSUF2_POWER_DETACHED_SYNC MSUF2_POWER_DETACHED_ANCHOR MSUF2_POWER_DETACHED_X " ..
  "MSUF2_POWER_DETACHED_Y MSUF2_POWER_DETACHED_W MSUF2_POWER_DETACHED_H " ..
  "MSUF2_POWER_DETACHED_LAYER MSUF2_POWER_DETACHED_SHAPE MSUF2_POWER_DETACHED_ORB_SIZE")
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_HEALTH, "MSUF_REVERSE_FILL")
Metadata.runtimeReasonMasks = runtimeReasonMasks

Metadata.defaultApplyMask = BuildNameSet(
  "Health Power Text NameText HealthText PowerText Portrait " .. STATUS_APPLY_ELEMENTS .. " TempMaxHealth Prediction " ..
  "Borders LoadConditions Alpha RangeFade Auras Castbars ClassPower")

-- ApplyService owns cross-module followers explicitly. Its frame apply uses this
-- mask so Auras/Castbars/ClassPower are not queued a second time by bridge
-- elements. Direct Factory/Profile applies keep defaultApplyMask above.
Metadata.coordinatedApplyMask = BuildNameSet(
  "Health Power Text NameText HealthText PowerText Portrait " .. STATUS_APPLY_ELEMENTS .. " TempMaxHealth Prediction " ..
  "Borders LoadConditions Alpha RangeFade")

Metadata.refreshElementGroups = {
  healthTextBorder = BuildNameList("Health Text NameText HealthText InlineToT Borders"),
  visuals = BuildNameList(
    "Health Power Text NameText HealthText PowerText InlineToT Portrait " ..
    "StatusIndicators RaidMarkerIndicator LeaderIndicator TempMaxHealth Prediction LevelIndicator " ..
    "RaidGroupIndicator EliteIndicator StatusTextIndicator CombatIndicator RestingIndicator " ..
    "IncomingResIndicator PVPIndicator StanceIndicator Alpha Borders RangeFade Auras"),
  powerText = BuildNameList("Power Text PowerText"),
  colors = BuildNameList(
    "Health Power Text NameText HealthText PowerText InlineToT Portrait " ..
    "StatusIndicators LevelIndicator EliteIndicator StatusTextIndicator CombatIndicator " ..
    "RestingIndicator IncomingResIndicator PVPIndicator StanceIndicator " ..
    "TempMaxHealth Prediction Borders"),
  text = BuildNameList("Text NameText HealthText PowerText InlineToT"),
  borders = BuildNameList("Borders Power"),
  reverseFill = BuildNameList("Health Power TempMaxHealth Prediction"),
  alpha = BuildNameList("Alpha RangeFade"),
}

-- Unit catalogue. Cold lookups shared by the factory, apply and runtime
-- drivers. The frame engine core reads these through UF at call time only,
-- so they live here, ahead of it in the embed load order.
local tostring = tostring
local tonumber = tonumber
local Framework = MSUF.MSUFUnitFrames or MSUF.UFCore
local HOST_VALUES = UF._hostValues or _G

UF.unitOrder = UF.unitOrder or {
  "player", "target", "focus", "targettarget", "focustarget", "pet",
  "boss1", "boss2", "boss3", "boss4", "boss5",
  "arena1", "arena2", "arena3",
}

-- Prune unsupported client tokens before factories, events and edit-mode owners
-- consume the managed-unit list. Imported profiles cannot re-enable these units.
local client = (_G.MSUF_NS or MSUF).Client
if client and client.SupportsUnit then
  for i = #UF.unitOrder, 1, -1 do
    if not client.SupportsUnit(UF.unitOrder[i]) then
      table.remove(UF.unitOrder, i)
    end
  end
end
UF.unitLookup = {}
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
  arena = { "arena1", "arena2", "arena3" },
}
UF.singleUnitLists = UF.singleUnitLists or {}

local BOSS_UNITS = {
  boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

local ARENA_UNITS = {
  arena1 = true, arena2 = true, arena3 = true,
}

UF.dependentUnitParents = UF.dependentUnitParents or {
  targettarget = "target",
  focustarget = "focus",
}

function UF.ParentUnitForDependentUnit(unit)
  return UF.dependentUnitParents and UF.dependentUnitParents[unit]
end

function UF.IsDependentUnit(unit)
  return UF.ParentUnitForDependentUnit(unit) ~= nil
end

function UF.ConfigKeyForUnit(unit)
  if BOSS_UNITS[unit] then return "boss" end
  if ARENA_UNITS[unit] then return "arena" end
  if unit == "targetoftarget" or unit == "tot" then return "targettarget" end
  return unit
end

function UF.IsManagedUnit(unit)
  return UF.unitLookup[unit] == true
end

function UF.UnitsForConfigKey(key)
  local units = UF.configKeyUnits[key]
  if units then return units end
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
  local prefix = UF.frameNamePrefix
    or (Framework and Framework.framePrefix)
    or "MSUF"
  return tostring(prefix) .. "_" .. tostring(unit or "unknown")
end

-- Spec normalizers and scoped-config resolvers. Apply-time helpers only:
-- Config/Group_Config resolve highlight, gradient, prediction and test-mode
-- settings through them once per apply, and element files capture the
-- exported UF.* functions at their own load time. Nothing here runs per event.
local function Clamp01(value, fallback)
  value = tonumber(value)
  if value == nil then value = fallback end
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end
UF.Clamp01 = Clamp01

local function NumberWithFallback(value, fallback)
  value = tonumber(value)
  return value == nil and fallback or value
end
UF.NumberWithFallback = NumberWithFallback

local function NormalizeDispelDetectTrigger(value)
  value = tostring(value or ""):upper()
  if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then
    return "BY_RAID"
  end
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
    return "DISPEL_TYPE"
  elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
    return "DISPEL_TYPE"
  elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
    return "PLAYER_CAST"
  end
  return "BY_ME"
end
UF.NormalizeDispelDetectTrigger = NormalizeDispelDetectTrigger

local function NormalizeDispelOverlayTrigger(value)
  value = tostring(value or ""):upper()
  if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
  return NormalizeDispelDetectTrigger(value)
end
UF.NormalizeDispelOverlayTrigger = NormalizeDispelOverlayTrigger

local function NormalizeDispelOverlayStyle(value)
  if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
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
  scope = tostring(scope or "shared"):lower():gsub("%s+", ""):gsub("%-", "_")
  if scope == "" or scope == "all" or scope == "global" then return "shared" end
  if scope == "gf_party" or scope == "group_party" or scope == "gfparty" then return "party" end
  if scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid"
    or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then return "raid" end
  if scope == "focus_target" then return "focustarget" end
  if scope == "targetoftarget" or scope == "tot" then return "targettarget" end
  return scope
end
UF.NormalizeAbsorbTestScope = NormalizeAbsorbTestScope

local PREDICTION_TEST_CATEGORIES = {
  heal = true,
  absorb = true,
  healAbsorb = true,
  tempMaxHealth = true,
}

local function NormalizePredictionTestCategory(category)
  if category == "heal" or category == "prediction" or category == "healPrediction" then return "heal" end
  if category == "healAbsorb" or category == "negative" or category == "negativeAbsorb" then return "healAbsorb" end
  if category == "absorb" or category == "positive" or category == "positiveAbsorb" then return "absorb" end
  if category == "tempMaxHealth" or category == "maxHealthLoss" or category == "reducedMaxHealth" then return "tempMaxHealth" end
  return nil
end
UF.NormalizePredictionTestCategory = NormalizePredictionTestCategory

local function PredictionTestBucketEnabled(bucket, category)
  if type(bucket) ~= "table" then return false end
  category = NormalizePredictionTestCategory(category)
  if category then return bucket[category] == true end
  return bucket.heal == true or bucket.absorb == true or bucket.healAbsorb == true
end

local function AbsorbTextureTestEnabledForScope(scope, category)
  local modes = HOST_VALUES.MSUF_PredictionTestModes
  if type(modes) == "table" then
    local normalized = NormalizeAbsorbTestScope(scope)
    if PredictionTestBucketEnabled(modes.shared, category) then return true end
    if normalized ~= "shared" and PredictionTestBucketEnabled(modes[normalized], category) then return true end
    return normalized == "shared" and PredictionTestBucketEnabled(modes.shared, category) or false
  end
  if HOST_VALUES.MSUF_AbsorbTextureTestMode ~= true then return false end
  local wanted = NormalizeAbsorbTestScope(HOST_VALUES.MSUF_AbsorbTextureTestScope)
  return wanted == "shared" or wanted == NormalizeAbsorbTestScope(scope)
end
UF.AbsorbTextureTestEnabledForScope = AbsorbTextureTestEnabledForScope
UF.PREDICTION_TEST_CATEGORIES = PREDICTION_TEST_CATEGORIES

local function ConfigScopedValue(conf, general, key, fallback)
  if conf and conf.hlOverride == true and conf[key] ~= nil then return conf[key] end
  if general and general[key] ~= nil then return general[key] end
  return fallback
end
UF.ConfigScopedValue = ConfigScopedValue

local BORDER_PRIORITY_DEFAULTS = { "dispel", "aggro", "purge", "bossTarget" }
local BORDER_PRIORITY_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
local BORDER_PRIORITY_ALIAS = {
  Dispel = "dispel", DISPEL = "dispel", Magic = "dispel", MAGIC = "dispel",
  Curse = "dispel", CURSE = "dispel", Disease = "dispel", DISEASE = "dispel",
  Poison = "dispel", POISON = "dispel", Bleed = "dispel", BLEED = "dispel",
  Aggro = "aggro", AGGRO = "aggro", Purge = "purge", PURGE = "purge",
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
        used[key] = true
        order[#order + 1] = key
      end
    end
  end
  for i = 1, #BORDER_PRIORITY_DEFAULTS do
    local key = BORDER_PRIORITY_DEFAULTS[i]
    if not used[key] then
      used[key] = true
      order[#order + 1] = key
    end
  end
  return enabled, order
end
UF.CompileBorderPriority = CompileBorderPriority

local function GradientKeyActive(conf, key)
  if not (conf and conf.hlOverride == true and conf.gradientOverride == true) then return false end
  if conf.gradientOverrideVersion ~= 2 then return conf[key] ~= nil end
  return type(conf.gradientOverrideKeys) == "table" and conf.gradientOverrideKeys[key] == true
end

local function GradientScopedValue(conf, general, key, fallback, legacyKey)
  if GradientKeyActive(conf, key) and conf[key] ~= nil then return conf[key] end
  if legacyKey and GradientKeyActive(conf, legacyKey) and conf[legacyKey] ~= nil then return conf[legacyKey] end
  if general and general[key] ~= nil then return general[key] end
  if legacyKey and general and general[legacyKey] ~= nil then return general[legacyKey] end
  return fallback
end

local function ResolveBarGradient(conf, general, enabledKey)
  local power = enabledKey == "enablePowerGradient"
  local useLegacyDirections = false
  if power then
    local scopedPower = GradientKeyActive(conf, "powerGradientDirLeft") or GradientKeyActive(conf, "powerGradientDirRight")
      or GradientKeyActive(conf, "powerGradientDirUp") or GradientKeyActive(conf, "powerGradientDirDown")
    local scopedLegacy = GradientKeyActive(conf, "gradientDirLeft") or GradientKeyActive(conf, "gradientDirRight")
      or GradientKeyActive(conf, "gradientDirUp") or GradientKeyActive(conf, "gradientDirDown")
    local generalPower = general and (general.powerGradientDirLeft ~= nil or general.powerGradientDirRight ~= nil
      or general.powerGradientDirUp ~= nil or general.powerGradientDirDown ~= nil)
    useLegacyDirections = not scopedPower and (scopedLegacy or not generalPower)
  end
  local prefix = power and not useLegacyDirections and "powerGradientDir" or "gradientDir"
  local left = GradientScopedValue(conf, general, prefix .. "Left", false) == true
  local right = GradientScopedValue(conf, general, prefix .. "Right", false) == true
  local up = GradientScopedValue(conf, general, prefix .. "Up", false) == true
  local down = GradientScopedValue(conf, general, prefix .. "Down", false) == true
  if not (left or right or up or down) then
    local directionKey = power and not useLegacyDirections and "powerGradientDirection" or "gradientDirection"
    local legacy = GradientScopedValue(conf, general, directionKey, "RIGHT")
    left = legacy == "LEFT"
    up = legacy == "UP"
    down = legacy == "DOWN"
    right = not (left or up or down)
  end
  local strengthKey = power and "powerGradientStrength" or "gradientStrength"
  local colorPrefix = power and "powerBarGradientColor" or "healthBarGradientColor"
  return {
    enabled = GradientScopedValue(conf, general, enabledKey, false) == true,
    strength = Clamp01(GradientScopedValue(conf, general, strengthKey, 0.45,
      power and "gradientStrength" or nil), 0.45),
    r = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "R", 0), 0),
    g = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "G", 0), 0),
    b = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "B", 0), 0),
    left = left, right = right, up = up, down = down,
  }
end
UF.ResolveBarGradient = ResolveBarGradient

function UF.FillPredictionColors(dst, general, conf, scopedValue, numberFn)
  scopedValue = scopedValue or ConfigScopedValue
  numberFn = numberFn or NumberWithFallback
  dst.healR = numberFn(general and general.healPredictionColorR, 0)
  dst.healG = numberFn(general and general.healPredictionColorG, 1)
  dst.healB = numberFn(general and general.healPredictionColorB, 0)
  dst.healA = Clamp01(scopedValue(conf, general, "healPredictionBarOpacity", general and general.healPredictionColorA), 0.45)
  dst.absorbR = numberFn(general and general.absorbBarColorR, 1)
  dst.absorbG = numberFn(general and general.absorbBarColorG, 1)
  dst.absorbB = numberFn(general and general.absorbBarColorB, 1)
  dst.absorbA = Clamp01(scopedValue(conf, general, "absorbBarOpacity", general and general.absorbBarColorA), 0.75)
  dst.healAbsorbR = numberFn(general and general.healAbsorbBarColorR, 0.7)
  dst.healAbsorbG = numberFn(general and general.healAbsorbBarColorG, 0)
  dst.healAbsorbB = numberFn(general and general.healAbsorbBarColorB, 0)
  dst.healAbsorbA = Clamp01(scopedValue(conf, general, "healAbsorbBarOpacity", general and general.healAbsorbBarColorA), 1)
end
