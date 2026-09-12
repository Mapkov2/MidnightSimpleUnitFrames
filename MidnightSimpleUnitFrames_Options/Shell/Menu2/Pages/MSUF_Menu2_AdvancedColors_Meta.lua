local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page: Assistant metadata.
-- Owns the semantic path -> setting/action key maps, the dynamic setting-key
-- lists, the reviewed Assistant dispositions and the Meta(...) builder behind
-- every control on the Colors page. Split from MSUF_Menu2_AdvancedColors.lua:
-- it loads right before that page and publishes through M.ColorsPage, which
-- the page and its later siblings pick from.
local AP = M.AdvancedPage or {}
local ControlMeta = AP.ControlMeta
local CP = M.ColorsPage or {}
M.ColorsPage = CP
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
    ["auras.color.aurasCooldownTextSafeColor"] = "general.aurasCooldownTextSafeColor",
    ["auras.color.aurasCooldownTextUrgentColor"] = "general.aurasCooldownTextUrgentColor",
    ["auras.color.aurasCooldownTextWarningColor"] = "general.aurasCooldownTextWarningColor",
    ["auras.cooldown.color_by_time"] = "general.aurasCooldownTextUseBuckets",
    ["auras.cooldown.safe_seconds"] = "general.aurasCooldownTextSafeSeconds",
    ["auras.cooldown.urgent_seconds"] = "general.aurasCooldownTextUrgentSeconds",
    ["auras.cooldown.warning_seconds"] = "general.aurasCooldownTextWarningSeconds",
    ["auras.dispel.magic.color"] = "general.dispelTypeColorOverrides.Magic",
    ["auras.dispel.curse.color"] = "general.dispelTypeColorOverrides.Curse",
    ["auras.dispel.disease.color"] = "general.dispelTypeColorOverrides.Disease",
    ["auras.dispel.poison.color"] = "general.dispelTypeColorOverrides.Poison",
    ["auras.dispel.bleed.color"] = "general.dispelTypeColorOverrides.Bleed",
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
    ["general.healthGradientHigh"] = "general.healthGradientHigh",
    ["general.healthGradientLow"] = "general.healthGradientLow",
    ["general.healthGradientMid"] = "general.healthGradientMid",
    ["general.unifiedBar"] = "general.unifiedBarColor",
    ["highlight.mouseover.color"] = "general.highlightColor",
    ["npc.color.dead"] = "npcColors.dead",
    ["npc.color.enemy"] = "npcColors.enemy",
    ["npc.color.friendly"] = "npcColors.friendly",
    ["npc.color.neutral"] = "npcColors.neutral",
    ["npc.color.npcBoss"] = "npcColors.npcBoss",
    ["npc.color.npcCaster"] = "npcColors.npcCaster",
    ["npc.color.npcMelee"] = "npcColors.npcMelee",
    ["npc.color.npcMiniboss"] = "npcColors.npcMiniboss",
    ["npc.color.npcRegular"] = "npcColors.npcRegular",
    ["npc.class_color_bar"] = "general.npcClassColorBar",
    ["unit.pet.use_player_class_color"] = "general.petFrameUsePlayerClassColor",
    ["npc_type.enabled"] = "general.npcColorMode",
    ["npc_type.option.npcTypeBoss"] = "general.npcTypeBoss",
    ["npc_type.option.npcTypeColorBar"] = "general.npcTypeColorBar",
    ["npc_type.option.npcTypeColorText"] = "general.npcTypeColorText",
    ["npc_type.option.npcTypeFocus"] = "general.npcTypeFocus",
    ["npc_type.option.npcTypeTarget"] = "general.npcTypeTarget",
    ["npc_type.option.npcTypeToT"] = "general.npcTypeToT",
    ["portrait.background_color"] = "general.portraitBgColor",
    ["portrait.border_color"] = "general.portraitBorderColor",
    ["table.bossTargetHighlightColor"] = "general.bossTargetHighlightColor",
    ["table.combatStateLeaveColor"] = "gameplay.combatStateLeaveColor",
    ["table.combatTimerColor"] = "gameplay.combatTimerColor",
    ["table.crosshairInRangeColor"] = "gameplay.crosshairInRangeColor",
    ["table.crosshairOutRangeColor"] = "gameplay.crosshairOutRangeColor",
    ["table.kickNotReadyColor"] = "general.kickNotReadyColor",
    ["table.kickReadyColor"] = "general.kickReadyColor",
}
local COLOR_ACTION_KEY_BY_PATH = {
    ["appearance.gradient.reset"] = "reset_health_gradient_colors",
    ["auras.reset"] = "reset_aura_colors",
    ["background.reset_to_black"] = "reset_bar_background_color",
    ["bar_gradient.reset"] = "reset_bar_gradient_colors",
    ["bar.reset"] = "reset_bar_colors",
    ["castbar.reset"] = "reset_castbar_colors",
    ["class_bar.reset_all"] = "reset_class_colors",
    ["font.use_palette"] = "reset_global_font_color",
    ["gameplay.reset"] = "reset_gameplay_colors",
    ["npc_type.reset"] = "reset_npc_type_colors",
    ["portrait.reset"] = "reset_portrait_colors",
    ["power.editor.reset"] = "reset_power_color_token",
    ["class_power.editor.reset_foreground"] = "reset_class_power_color_token",
    ["class_power.editor.reset_background"] = "reset_class_power_color_token",
    ["class_power.resource_slots.reset"] = "reset_class_power_slot_colors",
    ["class_power.full_resource.reset"] = "reset_class_power_full_color",
    ["unitframe.reset"] = "reset_unitframe_colors",
}
local COLOR_ACTION_INPUT_BY_PATH = {
    ["power.editor.reset"] = "token",
    ["class_power.editor.reset_foreground"] = "token",
    ["class_power.editor.reset_background"] = "token",
    ["class_power.resource_slots.reset"] = "resourceToken",
    ["class_power.full_resource.reset"] = "resourceToken",
}
local COLOR_ACTION_FIXED_ARGS_BY_PATH = {
    ["class_power.editor.reset_foreground"] = { background = false },
    ["class_power.editor.reset_background"] = { background = true },
}
M.DISPEL_COLOR_SPECS = M.DISPEL_COLOR_SPECS or {
    { key = "Magic", path = "magic" },
    { key = "Curse", path = "curse" },
    { key = "Disease", path = "disease" },
    { key = "Poison", path = "poison" },
    { key = "Bleed", path = "bleed" },
}
local function PrefixedSettingKeys(prefix, tokens)
    local keys = {}
    for token in tostring(tokens or ""):gmatch("%S+") do keys[#keys + 1] = prefix .. token end
    return keys
end
local COLOR_DYNAMIC_SETTING_KEYS_BY_PATH = {
    ["castbar.text_color.spell_name"] = {
        "general.castbarPlayerSpellNameColor", "general.castbarTargetSpellNameColor",
        "general.castbarFocusSpellNameColor", "general.bossCastSpellNameColor",
    },
    ["castbar.text_color.time"] = {
        "general.castbarPlayerTimeColor", "general.castbarTargetTimeColor",
        "general.castbarFocusTimeColor", "general.bossCastTimeColor",
    },
    ["castbar.text_color.target_name"] = {
        "general.castbarPlayerTargetNameColor", "general.castbarTargetTargetNameColor",
        "general.castbarFocusTargetNameColor", "general.bossCastTargetNameColor",
    },
    ["bar_gradient.health.color"] = {
        "general.healthBarGradientColorR", "general.healthBarGradientColorG", "general.healthBarGradientColorB",
    },
    ["bar_gradient.power.color"] = {
        "general.powerBarGradientColorR", "general.powerBarGradientColorG", "general.powerBarGradientColorB",
    },
    ["prediction.heal_color"] = {
        "general.healPredictionColorR",
        "general.healPredictionColorG",
        "general.healPredictionColorB",
    },
    ["bar.health_loss_color"] = {
        "general.healthLossColorR", "general.healthLossColorG", "general.healthLossColorB",
    },
    ["bar.power_loss_color"] = {
        "general.powerLossColorR", "general.powerLossColorG", "general.powerLossColorB",
    },
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
local function ColorReviewedDisposition(path)
    if path:match("^auras%.dispel%.[a-z]+%.enabled$") then
        return "compound", "This switch adds or removes one optional entry in the shared dispel-type color map."
    end
    if path:match("^texture_layer%d*%.") then
        return "compound", "This swatch writes the persisted RGB channels for one texture layer color as a single visible color."
    end
    if path:match("^castbar%.text_color%.") then
        return "dynamic", "This control targets the castbar unit currently selected in the adjacent unit selector."
    end
    if path == "font.name_custom.color" then
        return "compound", "This swatch writes the persisted custom name-color channels as a single visible color."
    end
    if path:match("^status_text%.color%.") then
        return "dynamic", "This control targets the unit and status indicator currently selected in the adjacent selectors."
    end
    if path:match("^bar_gradient%.") then
        return "dynamic", "This color targets the explicit Bars scope shared with the Health and Power gradient controls."
    end
    if path == "prediction.heal_color" then
        return "dynamic", "This RGB swatch writes the three persisted heal-prediction color channels as one visible color."
    end
    if path == "bar.health_loss_color" or path == "bar.power_loss_color" then
        return "dynamic", "This swatch routes one visible color to the three persisted RGB channels for one recent-loss effect."
    end
    if path == "group_frame.health.color" then
        return "dynamic", "This swatch writes the active health-color mode across Party, Raid, and Mythic Raid."
    end
    if path:match("^group_frame%.") then
        return "compound", "This shared control writes the same Group color option across Party, Raid, and Mythic Raid."
    end
    if path:match("^power%.editor%.") then
        return "dynamic", "This control targets the power type currently selected in the adjacent resource selector."
    end
    if path:match("^class_power%.editor%.") or path:match("^class_power%.resource_slots%.")
        or path:match("^class_power%.full_resource%.")
    then
        return "dynamic", "This control targets the Class Resource type currently selected in the adjacent resource selector."
    end
end
local function Meta(path, classification, exact)
    exact = type(exact) == "table" and exact or {}
    if exact.settingKey == nil then
        exact.settingKey = COLOR_SETTING_KEY_BY_PATH[path]
        local classToken = path:match("^class_bar%.token%.([A-Z]+)$")
        if classToken then exact.settingKey = "classColors." .. classToken end
    end
    if exact.actionKey == nil then exact.actionKey = COLOR_ACTION_KEY_BY_PATH[path] end
    if exact.actionInputArg == nil then exact.actionInputArg = COLOR_ACTION_INPUT_BY_PATH[path] end
    if exact.actionFixedArgs == nil then exact.actionFixedArgs = COLOR_ACTION_FIXED_ARGS_BY_PATH[path] end
    if exact.settingKey == nil and exact.actionKey == nil then
        exact.assistantDisposition, exact.assistantDispositionReason = ColorReviewedDisposition(path)
        exact.assistantSettingKeys = COLOR_DYNAMIC_SETTING_KEYS_BY_PATH[path]
        exact.assistantSettingKeyPatterns = COLOR_DYNAMIC_SETTING_PATTERNS_BY_PATH[path]
    end
    return ControlMeta("opt_colors", "advanced", path, classification, exact)
end
CP.Meta = Meta
