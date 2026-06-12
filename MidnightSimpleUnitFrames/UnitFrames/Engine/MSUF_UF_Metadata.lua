local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
UF.Metadata = Metadata

local pairs = pairs

local function BuildNameSet(names)
    local set = {}
    for i = 1, #names do
        set[names[i]] = true
    end
    return set
end

local function BuildEventKindMap(groups)
    local map = {}
    for kind, events in pairs(groups) do
        for i = 1, #events do
            map[events[i]] = kind
        end
    end
    return map
end

local function AddRuntimeReasonMasks(target, mask, reasons)
    for i = 1, #reasons do
        target[reasons[i]] = mask
    end
end

Metadata.BuildNameSet = BuildNameSet

Metadata.hotEventKind = BuildEventKindMap({
    [1] = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS", "UNIT_FACTION" },
    [2] = {
        "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE",
    },
    [3] = { "UNIT_CONNECTION" },
    [4] = { "UNIT_NAME_UPDATE" },
    [5] = { "UNIT_AURA" },
    [6] = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" },
    [8] = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" },
    [9] = { "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
    [10] = { "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "INCOMING_RESURRECT_CHANGED" },
    [11] = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    [12] = { "RAID_TARGET_UPDATE" },
    [13] = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" },
    [14] = { "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED" },
    [15] = { "PLAYER_FLAGS_CHANGED" },
    [16] = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" },
    [17] = { "UNIT_TARGET" },
    [18] = { "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED" },
})

Metadata.hotStateSpecs = {
    [1] = {
        { "InlineToT", "inline", "inlineMode" },
        { "Prediction", "prediction", "predictionMode" },
        { "Health", "health" },
        { "HealthText", "healthText" },
        { "NameText", "name" },
        { "StatusTextIndicator", "statusText" },
        { "CombatIndicator", "combat" },
        { "PVPIndicator", "pvp" },
        { "GroupVisuals", "groupVisuals" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [2] = {
        { "Power", "power" },
        { "PowerText", "powerText" },
    },
    [3] = {
        { "InlineToT", "inline", "inlineMode" },
        { "Prediction", "prediction", "predictionMode" },
        { "Health", "health" },
        { "HealthText", "healthText" },
        { "Power", "power" },
        { "PowerText", "powerText" },
        { "NameText", "name" },
        { "Portrait", "portrait" },
        { "StatusTextIndicator", "statusText" },
        { "GroupVisuals", "groupVisuals" },
        { "GroupStatusRuntime", "groupStatus" },
        { "RangeFade", "range" },
        { "GroupRangeFade", "groupRange" },
    },
    [4] = {
        { "NameText", "name" },
        { "InlineToT", "inline", "inlineMode" },
    },
    [5] = {
        { "Auras", "auras" },
    },
    [6] = {
        { "GroupVisuals", "groupVisuals" },
        { "GroupCornerIndicators", "groupCorners" },
        { "Borders", "borders" },
    },
    [8] = {
        { "Portrait", "portrait" },
    },
    [9] = {
        { "Prediction", "prediction", "predictionMode" },
    },
    [10] = {
        { "LevelIndicator", "level" },
        { "EliteIndicator", "elite" },
        { "NameText", "name" },
        { "InlineToT", "inline", "inlineMode" },
        { "IncomingResIndicator", "incomingRes" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [11] = {
        { "Alpha", "alpha" },
        { "CombatIndicator", "combat" },
        { "LoadConditions", "load" },
        { "Auras", "auras" },
    },
    [12] = {
        { "RaidMarkerIndicator", "raidMarker" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [13] = {
        { "LeaderIndicator", "leader" },
        { "RaidGroupIndicator", "raidGroup" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [14] = {
        { "LevelIndicator", "level" },
    },
    [15] = {
        { "StatusTextIndicator", "statusText" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [16] = {
        { "RestingIndicator", "resting" },
        { "Alpha", "alpha" },
        { "LoadConditions", "load" },
        { "GroupStatusRuntime", "groupStatus" },
    },
    [17] = {
        { "InlineToT", "inline", "inlineMode" },
        { "Prediction", "prediction", "predictionMode" },
        { "Alpha", "alpha" },
    },
    [18] = {
        { "Alpha", "alpha" },
        { "Borders", "borders" },
    },
}

Metadata.runtimeUpdateOwners = BuildNameSet({
    "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
    "InlineToT", "Portrait", "Alpha", "StatusIndicators", "RaidMarkerIndicator",
    "LeaderIndicator", "LevelIndicator", "RaidGroupIndicator", "EliteIndicator",
    "StatusTextIndicator", "CombatIndicator", "RestingIndicator", "IncomingResIndicator",
    "PVPIndicator", "Prediction", "Borders", "LoadConditions", "GroupStatusRuntime",
    "RangeFade", "GroupRangeFade", "GroupVisuals", "GroupCornerIndicators",
    "Auras",
})

local MASK_HEALTH = { health = true }
local MASK_POWER = { power = true }
local MASK_ALPHA = { alpha = true }
local MASK_BORDERS = { borders = true }
local MASK_BAR_OUTLINE = { power = true, borders = true }
local MASK_DISPEL_VISUAL = { borders = true, auras = true }
local MASK_PREDICTION = { prediction = true }
local MASK_FONT_RUNTIME = { health = true, power = true, name = true }
local MASK_TEXT_STATUS_RUNTIME = { health = true, power = true, name = true, status = true }
local MASK_DISABLED = {}
local MASK_CASTBAR_SYNC = { health = true, power = true, name = true, portrait = true, status = true, borders = true }
local MASK_BARS_BORDERS = { health = true, power = true, borders = true }
local MASK_UNIT_IDENTITY = {
    load = true,
    health = true,
    power = true,
    name = true,
    inline = true,
    portrait = true,
    status = true,
    prediction = true,
    alpha = true,
    borders = true,
    auras = true,
}
local MASK_UNIT_IDENTITY_FAST = {
    load = true,
    health = true,
    power = true,
    name = true,
}
local MASK_UNIT_IDENTITY_VISUAL = {
    inline = true,
    portrait = true,
    status = true,
    prediction = true,
    alpha = true,
    borders = true,
}
local MASK_UNIT_IDENTITY_AURAS = { auras = true }
local MASK_UNIT_IDENTITY_SOFT = {
    load = true,
    health = true,
    power = true,
    name = true,
    inline = true,
    portrait = true,
    status = true,
    prediction = true,
    auras = true,
}
local MASK_UNIT_IDENTITY_SOFT_FAST = {
    load = true,
    health = true,
    power = true,
    name = true,
}
local MASK_UNIT_IDENTITY_SOFT_VISUAL = {
    inline = true,
    portrait = true,
    status = true,
    prediction = true,
}
local MASK_UNIT_IDENTITY_SOFT_AURAS = { auras = true }
local MASK_GROUP_UNIT_IDENTITY = {
    load = true,
    health = true,
    power = true,
    name = true,
    groupStatus = true,
    prediction = true,
    groupVisuals = true,
    groupRange = true,
    borders = true,
    auras = true,
}

local runtimeReasonMasks = {}
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_FONT_RUNTIME, { "FONT_RUNTIME", "MSUF2_HP_TEXT_COLOR" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_CASTBAR_SYNC, { "CASTBAR_SYNC" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY, { "MSUF_UNIT_IDENTITY" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_FAST, { "MSUF_UNIT_IDENTITY_FAST" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_VISUAL, { "MSUF_UNIT_IDENTITY_VISUAL" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_AURAS, { "MSUF_UNIT_IDENTITY_AURAS" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT, { "MSUF_UNIT_IDENTITY_SOFT" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_FAST, { "MSUF_UNIT_IDENTITY_SOFT_FAST" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_VISUAL, { "MSUF_UNIT_IDENTITY_SOFT_VISUAL" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_UNIT_IDENTITY_SOFT_AURAS, { "MSUF_UNIT_IDENTITY_SOFT_AURAS" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_GROUP_UNIT_IDENTITY, { "MSUF_GF_UNIT_IDENTITY" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_ALPHA, { "MSUF_ALPHA" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BORDERS, { "MSUF_BORDER_LAYOUT", "MSUF2_BORDER" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BAR_OUTLINE, { "MSUF2_BAR_OUTLINE", "MSUF2_BAR_OUTLINE_COLOR" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_DISPEL_VISUAL, {
    "MSUF2_DISPEL_BORDER", "MSUF2_DISPEL_TRIGGER",
    "MSUF2_UF_DISPEL_OVERLAY", "MSUF2_UF_DISPEL_OVERLAY_TRIGGER",
    "MSUF2_UF_DISPEL_OVERLAY_STYLE", "MSUF2_UF_DISPEL_OVERLAY_HEALTH",
    "MSUF2_UF_DISPEL_OVERLAY_ALPHA",
})
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BORDERS, { "MSUF_GF_DIRTY_BORDER" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_DISABLED, { "MSUF_GF_DIRTY_AURAS" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_TEXT_STATUS_RUNTIME, { "MSUF_GF_DIRTY_FONT" })
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_BARS_BORDERS, {
    "MSUF2_GRADIENT", "MSUF2_HP_GRADIENT", "MSUF2_POWER_GRADIENT",
    "MSUF2_GRADIENT_STRENGTH", "MSUF2_GRADIENT_DIRECTION",
})
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_PREDICTION, {
    "MSUF2_ABSORB_MODE", "MSUF2_ABSORB", "MSUF2_ABSORB_ANCHOR",
    "MSUF2_ABSORB_OPACITY", "MSUF2_ABSORB_TEXTURE", "MSUF2_ABSORB_TEST",
    "MSUF2_ABSORB_TEST_CLEAR", "MSUF2_HEAL_ABSORB", "MSUF2_HEAL_ABSORB_OPACITY",
    "MSUF2_HEAL_ABSORB_TEXTURE", "MSUF2_HEALPRED_ANCHOR", "MSUF2_SELF_HEAL",
    "MSUF2_GF_HEALPRED",
})
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_POWER, {
    "MSUF_POWER_LAYOUT", "MSUF_POWER_TEXT_COLORS", "MSUF2_POWER_SHOW",
    "MSUF2_POWER_BORDER", "MSUF2_POWER_BORDER_SIZE", "MSUF2_POWER_HEIGHT",
    "MSUF2_POWER_EMBED", "MSUF2_POWER_SMOOTH", "MSUF2_POWER_DETACHED",
    "MSUF2_POWER_DETACHED_TEXT", "MSUF2_POWER_DETACHED_SYNC",
    "MSUF2_POWER_DETACHED_ANCHOR", "MSUF2_POWER_DETACHED_X",
    "MSUF2_POWER_DETACHED_Y", "MSUF2_POWER_DETACHED_W", "MSUF2_POWER_DETACHED_H",
    "MSUF2_POWER_DETACHED_LAYER",
})
AddRuntimeReasonMasks(runtimeReasonMasks, MASK_HEALTH, { "MSUF_REVERSE_FILL" })
Metadata.runtimeReasonMasks = runtimeReasonMasks

Metadata.defaultApplyMask = BuildNameSet({
    "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
    "StatusIndicators", "Prediction", "Borders", "LoadConditions",
    "RangeFade", "Auras",
})

Metadata.refreshElementGroups = {
    healthTextBorder = { "Health", "Text", "NameText", "HealthText", "InlineToT", "Borders" },
    visuals = {
        "Health", "Power", "Text", "NameText", "HealthText", "PowerText", "InlineToT",
        "Portrait", "StatusIndicators", "RaidMarkerIndicator", "LeaderIndicator", "Prediction",
        "LevelIndicator", "RaidGroupIndicator", "EliteIndicator", "StatusTextIndicator",
        "CombatIndicator", "RestingIndicator", "IncomingResIndicator", "PVPIndicator", "Alpha", "Borders",
        "RangeFade", "Auras",
    },
    powerText = { "Power", "Text", "PowerText" },
    text = { "Text", "NameText", "HealthText", "PowerText", "InlineToT" },
    borders = { "Borders", "Power" },
    reverseFill = { "Health", "Power", "Prediction" },
    alpha = { "Alpha", "RangeFade" },
}
