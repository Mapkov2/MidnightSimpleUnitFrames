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
