local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page: Search metadata.
-- Owns the semantic path -> setting/action key maps, the dynamic setting-key
-- lists, the reviewed Search dispositions and the Meta(...) builder behind
-- every control on the Colors page. Split from MSUF_Menu2_AdvancedColors.lua:
-- it loads right before that page and publishes through M.ColorsPage, which
-- the page and its later siblings pick from.
local AP = M.AdvancedPage or {}
local ControlMeta = AP.ControlMeta
local CP = M.ColorsPage or {}
M.ColorsPage = CP
-- Core functions the Colors files call from color commits and refreshes. Each name resolves on its
-- first read and is a plain table hit afterwards, so those paths never call Require / Optional:
-- Req raises when a provider is missing, Opt keeps false for an absent one.
CP.Req = setmetatable({}, { __index = function(cache, name)
    local value = MSUF.Require(name, "Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
    cache[name] = value
    return value
end })
CP.Opt = setmetatable({}, { __index = function(cache, name)
    local value = MSUF.Optional(name) or false
    cache[name] = value
    return value
end })
local COLOR_SETTING_KEY_BY_PATH = {
    ["power.color_by_class"] = "general.powerColorMode",
    ["api.SetAbsorbOverlayColor"] = "general.absorbBarColor",
    ["api.SetAggroBorderColor"] = "general.aggroBorderColor",
    ["api.SetCastbarTargetNameColor"] = "general.castbarTargetNameColor",
    ["api.SetCastbarTextColor"] = "general.castbarFontColor",
    ["api.SetGlobalFontColor"] = "general.customFontColor",
    ["api.SetHealAbsorbOverlayColor"] = "general.healAbsorbBarColor",
    ["api.SetInterruptFeedbackCastColor"] = "general.castbarInterruptFeedbackColor",
    ["api.SetInterruptUnavailableCastColor"] = "general.castbarInterruptUnavailableColor",
    ["api.SetInterruptibleCastColor"] = "general.castbarInterruptibleColor",
    ["api.SetNonInterruptibleCastColor"] = "general.castbarNonInterruptibleColor",
    ["api.SetPetFrameColor"] = "general.petFrameColor",
    ["api.SetPowerBarBackgroundColor"] = "general.powerBarBgColor",
    ["appearance.bar_mode"] = "general.barMode",
    ["appearance.dark_mode_tone"] = "general.darkBarGray",
    ["appearance.gradient.enabled"] = "general.enableHealthGradient",
    ["appearance.gradient.strength"] = "general.gradientStrength",
    ["auras.cooldown.color_by_time"] = "general.aurasCooldownTextUseBuckets",
    ["auras.cooldown.safe_seconds"] = "general.aurasCooldownTextSafeSeconds",
    ["auras.cooldown.urgent_seconds"] = "general.aurasCooldownTextUrgentSeconds",
    ["auras.cooldown.warning_seconds"] = "general.aurasCooldownTextWarningSeconds",
    ["background.color_mode"] = "general.barBgColorMode",
    ["background.dark_mode_custom_color"] = "general.darkBgCustomColor",
    ["background.fill_mode"] = "general.barBgFillMode",
    ["bar.outline_color"] = "general.barOutlineColor",
    ["bar.power_background_match_health"] = "general.powerBarBgMatchBarColor",
    ["bar.purge_border_color"] = "general.purgeBorderColor",
    ["castbar.player_override.custom_color"] = "general.playerCastbarOverrideColor",
    ["castbar.player_override.enabled"] = "general.playerCastbarOverrideEnabled",
    ["castbar.player_override.mode"] = "general.playerCastbarOverrideMode",
    ["gameplay.combat_enter_color"] = "gameplay.combatStateEnterColor",
    ["gameplay.combat_state_color_sync"] = "gameplay.combatStateColorSync",
    ["general.castbarBg"] = "general.castbarBackgroundColor",
    ["general.castbarBorder"] = "general.castbarBorderColor",
    ["general.classBarBg"] = "general.classBarBgColor",
    ["general.unifiedBar"] = "general.unifiedBarColor",
    ["highlight.mouseover.color"] = "general.highlightColor",
    ["npc.tap_denied_gray"] = "general.tapDeniedGray",
    ["npc.class_color_bar"] = "general.npcClassColorBar",
    ["unit.pet.use_player_class_color"] = "general.petFrameUsePlayerClassColor",
    ["npc_type.enabled"] = "general.npcColorMode",
    ["portrait.background_color"] = "general.portraitBgColor",
    ["portrait.border_color"] = "general.portraitBorderColor",
}
M.DISPEL_COLOR_SPECS = M.DISPEL_COLOR_SPECS or {
    { key = "Magic", path = "magic" },
    { key = "Curse", path = "curse" },
    { key = "Disease", path = "disease" },
    { key = "Poison", path = "poison" },
    { key = "Bleed", path = "bleed" },
}
-- Path families whose last segment is the stored key: path prefix + name -> key prefix + name.
local function AddSettingKeys(pathPrefix, keyPrefix, names)
    for name in names:gmatch("%S+") do COLOR_SETTING_KEY_BY_PATH[pathPrefix .. name] = keyPrefix .. name end
end
AddSettingKeys("auras.color.", "general.", "aurasCooldownTextSafeColor aurasCooldownTextUrgentColor aurasCooldownTextWarningColor")
AddSettingKeys("general.", "general.", "healthGradientHigh healthGradientLow healthGradientMid")
AddSettingKeys("npc.color.", "npcColors.", "dead enemy friendly neutral npcBoss npcCaster npcMelee npcMiniboss npcRegular tapped")
AddSettingKeys("npc_type.option.", "general.", "npcTypeBoss npcTypeColorBar npcTypeColorText npcTypeFocus npcTypeTarget npcTypeToT")
AddSettingKeys("table.", "general.", "bossTargetHighlightColor kickNotReadyColor kickReadyColor")
AddSettingKeys("table.", "gameplay.", "combatStateLeaveColor combatTimerColor crosshairInRangeColor crosshairOutRangeColor")
for i = 1, #M.DISPEL_COLOR_SPECS do
    local spec = M.DISPEL_COLOR_SPECS[i]
    COLOR_SETTING_KEY_BY_PATH["auras.dispel." .. spec.path .. ".color"] = "general.dispelTypeColorOverrides." .. spec.key
end
-- Reset buttons: path -> { action key, input arg name, fixed args }.
local COLOR_ACTION_BY_PATH = {
    ["appearance.gradient.reset"] = { "reset_health_gradient_colors" },
    ["auras.reset"] = { "reset_aura_colors" },
    ["background.reset_to_black"] = { "reset_bar_background_color" },
    ["bar_gradient.reset"] = { "reset_bar_gradient_colors" },
    ["bar.reset"] = { "reset_bar_colors" },
    ["castbar.reset"] = { "reset_castbar_colors" },
    ["class_bar.reset_all"] = { "reset_class_colors" },
    ["font.use_palette"] = { "reset_global_font_color" },
    ["gameplay.reset"] = { "reset_gameplay_colors" },
    ["npc_type.reset"] = { "reset_npc_type_colors" },
    ["portrait.reset"] = { "reset_portrait_colors" },
    ["power.editor.reset"] = { "reset_power_color_token", "token" },
    ["class_power.editor.reset_foreground"] = { "reset_class_power_color_token", "token", { background = false } },
    ["class_power.editor.reset_background"] = { "reset_class_power_color_token", "token", { background = true } },
    ["class_power.resource_slots.reset"] = { "reset_class_power_slot_colors", "resourceToken" },
    ["class_power.full_resource.reset"] = { "reset_class_power_full_color", "resourceToken" },
    ["unitframe.reset"] = { "reset_unitframe_colors" },
}
local function PrefixedSettingKeys(prefix, tokens)
    local keys = {}
    for token in tostring(tokens or ""):gmatch("%S+") do keys[#keys + 1] = prefix .. token end
    return keys
end
-- The castbar text colors keep one stored key per castbar unit.
local CAST_DETAIL_UNIT_KEYS = { "castbarPlayer", "castbarTarget", "castbarFocus", "bossCast", "arenaCast" }
local function CastDetailKeys(suffix)
    local keys = {}
    for i = 1, #CAST_DETAIL_UNIT_KEYS do keys[i] = "general." .. CAST_DETAIL_UNIT_KEYS[i] .. suffix .. "Color" end
    return keys
end
local COLOR_DYNAMIC_SETTING_KEYS_BY_PATH = {
    ["castbar.text_color.spell_name"] = CastDetailKeys("SpellName"),
    ["castbar.text_color.time"] = CastDetailKeys("Time"),
    ["castbar.text_color.target_name"] = CastDetailKeys("TargetName"),
    ["bar_gradient.health.color"] = PrefixedSettingKeys("general.healthBarGradientColor", "R G B"),
    ["bar_gradient.power.color"] = PrefixedSettingKeys("general.powerBarGradientColor", "R G B"),
    ["prediction.heal_color"] = PrefixedSettingKeys("general.healPredictionColor", "R G B"),
    ["bar.health_loss_color"] = PrefixedSettingKeys("general.healthLossColor", "R G B"),
    ["bar.power_loss_color"] = PrefixedSettingKeys("general.powerLossColor", "R G B"),
    ["level_difficulty.impossible"] = PrefixedSettingKeys("general.levelColorImpossible", "R G B"),
    ["level_difficulty.very_difficult"] = PrefixedSettingKeys("general.levelColorVeryDifficult", "R G B"),
    ["level_difficulty.standard"] = PrefixedSettingKeys("general.levelColorStandard", "R G B"),
    ["level_difficulty.easy"] = PrefixedSettingKeys("general.levelColorEasy", "R G B"),
    ["level_difficulty.trivial"] = PrefixedSettingKeys("general.levelColorTrivial", "R G B"),
    ["threat.curve.low"] = PrefixedSettingKeys("general.threatColorLow", "R G B"),
    ["threat.curve.mid"] = PrefixedSettingKeys("general.threatColorMid", "R G B"),
    ["threat.curve.high"] = PrefixedSettingKeys("general.threatColorHigh", "R G B"),
    ["power.editor.color"] = PrefixedSettingKeys("general.powerColorOverrides.",
        "MANA RAGE ENERGY FOCUS RUNIC_POWER INSANITY FURY PAIN ESSENCE LUNAR_POWER MAELSTROM"),
    ["class_power.editor.foreground_color"] = PrefixedSettingKeys("general.classPowerColorOverrides.",
        [[COMBO_POINTS HOLY_POWER SOUL_SHARDS CHI ARCANE_CHARGES RUNES ESSENCE CHARGED
           SOUL_FRAGMENTS SOUL_FRAGMENTS_META MAELSTROM MAELSTROM_ABOVE_5 ASTRAL_POWER AP_PREDICTION
           ECLIPSE_SOLAR ECLIPSE_LUNAR ECLIPSE_CA STAGGER_GREEN STAGGER_YELLOW STAGGER_RED
           SOUL_FRAGMENTS_VENG INSANITY MAELSTROM_POWER WHIRLWIND TIP_OF_THE_SPEAR ICICLES EBON_MIGHT
           MANA RESOURCE_TEXT]]),
}
local CLASS_POWER_SLOT_RESOURCES = {
    { "COMBO_POINTS", 7 }, { "HOLY_POWER", 5 }, { "SOUL_SHARDS", 5 }, { "CHI", 6 },
    { "ARCANE_CHARGES", 4 }, { "RUNES", 6 }, { "ESSENCE", 6 }, { "SOUL_FRAGMENTS_VENG", 6 },
    { "MAELSTROM", 10 }, { "WHIRLWIND", 4 }, { "TIP_OF_THE_SPEAR", 3 }, { "ICICLES", 5 },
}
CP.CLASS_POWER_SLOT_RESOURCES = CLASS_POWER_SLOT_RESOURCES
for slot = 1, 10 do
    local keys = {}
    for i = 1, #CLASS_POWER_SLOT_RESOURCES do
        local resource = CLASS_POWER_SLOT_RESOURCES[i]
        if slot <= resource[2] then
            keys[#keys + 1] = "general.classPowerColorOverrides." .. resource[1] .. "_" .. slot
        end
    end
    COLOR_DYNAMIC_SETTING_KEYS_BY_PATH["class_power.resource_slots.slot." .. slot] = keys
end
local COLOR_DYNAMIC_SETTING_PATTERNS_BY_PATH = {
    ["bar_gradient.health.color"] = { "^barScope%.[%w_]+%.healthBarGradientColor[RGB]$" },
    ["bar_gradient.power.color"] = { "^barScope%.[%w_]+%.powerBarGradientColor[RGB]$" },
    ["class_power.editor.background_color"] = { "^general%.classPowerBgColorOverrides%.[A-Z0-9_]+$" },
    ["class_power.full_resource.color"] = { "^general%.classPowerColorOverrides%.[A-Z_]+_FULL$" },
    ["class_power.full_resource.enabled"] = { "^bars%.classPowerFullColorEnabled%.[A-Z_]+$" },
    ["class_power.resource_slots.mode"] = { "^bars%.classPowerSlotColorModes%.[A-Z_]+$" },
    ["status_text.color.value"] = {
        "^[%a]+%.levelIndicatorColor$", "^[%a]+%.raceIndicatorColor$",
        "^[%a]+%.classTextIndicatorColor$", "^[%a]+%.raidGroupNameColor$",
        "^[%a]+%.statusTextColor$", "^[%a]+%.statusGhostTextColor$",
        "^[%a]+%.statusAFKTextColor$", "^[%a]+%.statusAFKTimerColor$",
        "^[%a]+%.statusDNDTextColor$",
    },
}
local function Meta(path, classification, exact)
    exact = type(exact) == "table" and exact or {}
    if exact.settingKey == nil then
        exact.settingKey = COLOR_SETTING_KEY_BY_PATH[path]
        local classToken = path:match("^class_bar%.token%.([A-Z]+)$")
        if classToken then exact.settingKey = "classColors." .. classToken end
    end
    local action = COLOR_ACTION_BY_PATH[path]
    if action then
        if exact.actionKey == nil then exact.actionKey = action[1] end
        if exact.actionInputArg == nil then exact.actionInputArg = action[2] end
        if exact.actionFixedArgs == nil then exact.actionFixedArgs = action[3] end
    end
    if exact.settingKey == nil and exact.actionKey == nil then
        exact.searchSettingKeys = COLOR_DYNAMIC_SETTING_KEYS_BY_PATH[path]
        exact.searchSettingKeyPatterns = COLOR_DYNAMIC_SETTING_PATTERNS_BY_PATH[path]
    end
    return ControlMeta("opt_colors", "advanced", path, classification, exact)
end
CP.Meta = Meta
