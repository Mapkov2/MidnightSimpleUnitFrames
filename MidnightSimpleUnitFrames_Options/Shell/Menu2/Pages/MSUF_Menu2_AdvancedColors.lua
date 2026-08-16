local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page.
-- Binds global color palettes, class/power overrides, aura colors, and border colors. Color
-- apply is coalesced because one edit may need to refresh several frame families.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local GP = M.GlobalPage or {}
local C_Timer = M.MenuTimer or _G.C_Timer
local floor = math.floor
local max = math.max
local min = math.min
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CallGlobal, DB, G, Bars, Gameplay, BindTableToggle, ApplyAuras, MoveWidget, LabelAt, SwitchAt, ValueToggleAt, ValueSwitchAt, SliderAt, ValueSliderAt, ValueDropdownAt, SetControlEnabled, ControlMeta, RegisterControl = M.Pick(AP, [[CallGlobal DB G Bars Gameplay BindTableToggle ApplyAuras MoveWidget LabelAt SwitchAt ValueToggleAt ValueSwitchAt SliderAt ValueSliderAt ValueDropdownAt SetControlEnabled ControlMeta RegisterControl]])
local CurrentBarsScope, NormalizeScopeKey, ScopeHasOverride, GradientScopeGet, GradientScopeSet = M.Pick(GP, [[CurrentBarsScope NormalizeScopeKey ScopeHasOverride GradientScopeGet GradientScopeSet]])
local COLOR_SETTING_KEY_BY_PATH = {
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
    ["background.dark_mode_custom_color"] = "general.darkBgCustomColor",
    ["background.follow_class_color"] = "general.barBgClassColor",
    ["background.follow_health_color"] = "general.barBgMatchHPColor",
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
local KLR, WL, ColorRows, KeyLabelMap, ValueTextPairs, SetControlsEnabled = M.KeyLabelRows, M.WordList, M.ColorRows, M.KeyLabelMap, M.ValueTextPairs, W.SetControlsEnabled
local ColorValueAt

local function CurrentApplyService()
    return M.ApplyService or _G.MSUF_Menu2_ApplyService
end

local function RequestGeneral(reason, opts)
    if type(M.RequestGeneralApply) == "function" then
        return M.RequestGeneralApply(reason, opts)
    end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneral(reason, opts)
    end
    return false
end

local function ApplyColors()
    local apply = CurrentApplyService()
    if apply and type(apply.RequestColors) == "function" then
        return apply.RequestColors("MSUF2_COLORS")
    end
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        api.PushVisualUpdates()
        return true
    end
    return RequestGeneral("MSUF2_COLORS", { preview = true, applyAll = false, colors = true })
end

local function ApplyUnitframeColorWithReload()
    ApplyColors()
end
local function ApplyCastbarColors()
    M.RequestGeneralApply("MSUF2_CASTBAR_COLORS", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
end
local function ApplyBossTargetHighlightColor()
    local reason = "MSUF2_BOSS_TARGET_HIGHLIGHT_COLOR"
    local apply = CurrentApplyService()
    if apply and type(apply.RequestBossTargetBorder) == "function" then
        return apply.RequestBossTargetBorder(reason, "boss")
    end
    CallGlobal("MSUF_UFCore_RefreshSettingsCache", reason)
    if apply and type(apply.RequestUnit) == "function" then
        return apply.RequestUnit("boss", reason, { preview = true })
    end
    return CallGlobal("MSUF_UFCore_NotifyConfigChanged", "boss", true, true, reason)
end
local function ApplyGameplayColors()
    ApplyColors()
end
local function ApplyAuraColors()
    ApplyColors()
    local apply = CurrentApplyService()
    if apply and type(apply.RequestAuraFonts) == "function" then
        apply.RequestAuraFonts("shared", "MSUF2_AURA_COLORS")
    else
        ApplyAuras()
    end
    CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
end

function M._DispelTypeColorSpec(dispelType)
    for i = 1, #M.DISPEL_COLOR_SPECS do
        local spec = M.DISPEL_COLOR_SPECS[i]
        if spec.key == dispelType then return spec end
    end
end

function M._SetDispelColorPreviewType(dispelType)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.SetDispelColorPreviewType) == "function" then
        a3.SetDispelColorPreviewType(dispelType)
    end
end

function M._GetDispelTypeRGB(dispelType, useOverride)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.GetDispelTypeColor) == "function" then
        return a3.GetDispelTypeColor(dispelType, useOverride)
    end
    if dispelType == "Curse" then return 0.60, 0.00, 1.00 end
    if dispelType == "Disease" then return 0.60, 0.40, 0.00 end
    if dispelType == "Poison" then return 0.00, 0.60, 0.00 end
    if dispelType == "Bleed" then return 0.80, 0.10, 0.10 end
    return 0.20, 0.60, 1.00
end

function M._HasDispelTypeColorOverride(dispelType)
    local overrides = G().dispelTypeColorOverrides
    return type(overrides) == "table" and type(overrides[dispelType]) == "table"
end

function M._SetDispelTypeRGB(dispelType, r, g, b)
    if not M._DispelTypeColorSpec(dispelType) then return false end
    local general = G()
    general.dispelTypeColorOverrides = type(general.dispelTypeColorOverrides) == "table"
        and general.dispelTypeColorOverrides or {}
    general.dispelTypeColorOverrides[dispelType] = {
        max(0, min(1, tonumber(r) or 0)),
        max(0, min(1, tonumber(g) or 0)),
        max(0, min(1, tonumber(b) or 0)),
    }
    M._SetDispelColorPreviewType(dispelType)
    ApplyAuraColors()
    return true
end

function M._SetDispelTypeColorEnabled(dispelType, enabled)
    if not M._DispelTypeColorSpec(dispelType) then return false end
    local general = G()
    if enabled == true then
        if not M._HasDispelTypeColorOverride(dispelType) then
            local r, g, b = M._GetDispelTypeRGB(dispelType, false)
            general.dispelTypeColorOverrides = type(general.dispelTypeColorOverrides) == "table"
                and general.dispelTypeColorOverrides or {}
            general.dispelTypeColorOverrides[dispelType] = { r, g, b }
        end
    elseif type(general.dispelTypeColorOverrides) == "table" then
        general.dispelTypeColorOverrides[dispelType] = nil
        if next(general.dispelTypeColorOverrides) == nil then general.dispelTypeColorOverrides = nil end
    end
    M._SetDispelColorPreviewType(dispelType)
    ApplyAuraColors()
    return true
end
local function ApplyClassPowerColors()
    local apply = CurrentApplyService()
    if apply and type(apply.RequestClassPower) == "function" then
        return apply.RequestClassPower("MSUF2_CLASSPOWER_COLORS", { colors = true, playerHP = true }, { preview = true, applyAll = false, colors = true, colorScope = "player" })
    end
    RequestGeneral("MSUF2_CLASSPOWER_COLORS", { preview = true, applyAll = false, colors = true, colorScope = "player" })
    CallGlobal("MSUF_ClassPower_InvalidateColors")
end
local function ApplyPortraitColors(reason)
    reason = reason or "PORTRAIT_COLORS"
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneral(reason, { preview = true, applyAll = true, colors = true })
    end
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason)
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason)
end
local COLOR_CLASS_TOKENS = WL [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]]
local COLOR_CLASS_LABELS = KeyLabelMap [[WARRIOR=Warrior|PALADIN=Paladin|HUNTER=Hunter|ROGUE=Rogue|PRIEST=Priest|DEATHKNIGHT=Death Knight|SHAMAN=Shaman|MAGE=Mage|WARLOCK=Warlock|MONK=Monk|DRUID=Druid|DEMONHUNTER=Demon Hunter|EVOKER=Evoker]]
local COLOR_NPC_ROWS = ColorRows "friendly|Friendly NPC Color|0|1|0;neutral|Neutral NPC Color|1|1|0;enemy|Enemy NPC Color|0.85|0.10|0.10;dead|Dead NPC Color|0.40|0.40|0.40"
local COLOR_NPC_TYPE_ROWS = ColorRows "npcBoss|Boss|0.74|0.11|0;npcMiniboss|Miniboss / Lieutenant|0.56|0|0.74;npcCaster|Caster|0|0.45|0.74;npcMelee|Melee|0.99|0.99|0.99;npcRegular|Regular|0.70|0.56|0.33"
local COLOR_POWER_TOKENS = ValueTextPairs [[MANA=Mana|RAGE=Rage|ENERGY=Energy|FOCUS=Focus|RUNIC_POWER=Runic Power|INSANITY=Insanity|FURY=Fury|PAIN=Pain|ESSENCE=Essence|LUNAR_POWER=Astral Power|MAELSTROM=Maelstrom]]
local COLOR_CP_TOKENS = ValueTextPairs [[COMBO_POINTS=Combo Points|HOLY_POWER=Holy Power|SOUL_SHARDS=Soul Shards|CHI=Chi|ARCANE_CHARGES=Arcane Charges|RUNES=Runes|ESSENCE=Essence|MANA=Alternative Mana|CHARGED=Empowered / Charged|SOUL_FRAGMENTS=Soul Fragments|SOUL_FRAGMENTS_META=Soul Fragments (Void Meta)|MAELSTROM=Maelstrom Weapon|MAELSTROM_ABOVE_5=Maelstrom Weapon 5+|ASTRAL_POWER=Astral Power|AP_PREDICTION=Astral Prediction|ECLIPSE_SOLAR=Eclipse Solar|ECLIPSE_LUNAR=Eclipse Lunar|ECLIPSE_CA=Celestial Alignment|STAGGER_GREEN=Stagger Light|STAGGER_YELLOW=Stagger Moderate|STAGGER_RED=Stagger Heavy|SOUL_FRAGMENTS_VENG=Soul Fragments (Vengeance)|INSANITY=Insanity|MAELSTROM_POWER=Maelstrom Power|WHIRLWIND=Whirlwind|TIP_OF_THE_SPEAR=Tip of the Spear|ICICLES=Icicles|EBON_MIGHT=Ebon Might|RESOURCE_TEXT=Resource Text]]
local COLOR_CP_SLOT_TOKENS = WL [[COMBO_POINTS_1 COMBO_POINTS_2 COMBO_POINTS_3 COMBO_POINTS_4 COMBO_POINTS_5 COMBO_POINTS_6 COMBO_POINTS_7]]
local COLOR_CP_SLOT_DEFAULTS = {}
for _, row in ipairs(ColorRows [[COMBO_POINTS_1|1|0.00|0.95|1.00;COMBO_POINTS_2|2|0.00|0.95|1.00;COMBO_POINTS_3|3|1.00|1.00|0.00;COMBO_POINTS_4|4|1.00|1.00|0.00;COMBO_POINTS_5|5|1.00|1.00|0.00;COMBO_POINTS_6|6|1.00|0.05|0.05;COMBO_POINTS_7|7|1.00|0.05|0.05]]) do
    COLOR_CP_SLOT_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local COLOR_CP_SLOT_MODES = ValueTextPairs "default=Resource color|ramp=Color ramp|custom=Custom slots"
local COLOR_CP_SLOT_COUNTS = KeyLabelMap [[COMBO_POINTS=7|HOLY_POWER=5|SOUL_SHARDS=5|CHI=6|ARCANE_CHARGES=4|RUNES=6|ESSENCE=6|SOUL_FRAGMENTS_VENG=6|MAELSTROM=10|WHIRLWIND=4|TIP_OF_THE_SPEAR=3|ICICLES=5]]
for token, count in pairs(COLOR_CP_SLOT_COUNTS) do COLOR_CP_SLOT_COUNTS[token] = tonumber(count) or 1 end
local COLOR_DATA = {
    CLASS_LABELS = COLOR_CLASS_LABELS,
    NPC_ROWS = COLOR_NPC_ROWS,
    NPC_TYPE_ROWS = COLOR_NPC_TYPE_ROWS,
    POWER_TOKENS = COLOR_POWER_TOKENS,
    CP_TOKENS = COLOR_CP_TOKENS,
    CP_SLOT_TOKENS = COLOR_CP_SLOT_TOKENS,
    CP_SLOT_MODES = COLOR_CP_SLOT_MODES,
}
local function ColorAPI()
    return (MSUF and MSUF._colorsAPI) or {}
end
local function ApiCall(name, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        fn(...)
        return true
    end
    return false
end
local function ApiValue(name, fallback, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local value = fn(...)
        if value ~= nil then return value end
    end
    if type(fallback) == "function" then return fallback() end
    return fallback
end
local function ApiRGB(name, dr, dg, db, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local r, g, b, a = fn(...)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, a end
    end
    return dr, dg, db
end
function M._ContextConfiguredGlobalFontRGB()
    local getter = _G.MSUF_GetConfiguredFontColor or (MSUF and MSUF.MSUF_GetConfiguredFontColor)
    if type(getter) == "function" then
        local r, g, b = getter()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return ApiRGB("GetGlobalFontColor", 1, 1, 1)
end
local function ApiSetRGB(name, r, g, b, a)
    return ApiCall(name, r, g, b, a)
end
local function GeneralRGB(prefix, dr, dg, db)
    local g = G()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg,
        tonumber(g[prefix .. "B"]) or db, tonumber(g[prefix .. "A"])
end
local function SetGeneralRGB(prefix, r, gCol, b, a)
    local g = G()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
    if type(a) == "number" then g[prefix .. "A"] = a end
end
local function GeneralRGBAlias(primaryPrefix, legacyPrefix, dr, dg, db)
    local g = G()
    return tonumber(g[primaryPrefix .. "R"]) or tonumber(g[legacyPrefix .. "R"]) or dr,
           tonumber(g[primaryPrefix .. "G"]) or tonumber(g[legacyPrefix .. "G"]) or dg,
           tonumber(g[primaryPrefix .. "B"]) or tonumber(g[legacyPrefix .. "B"]) or db
end
local function SetGeneralRGBAlias(primaryPrefix, legacyPrefix, r, gCol, b)
    local g = G()
    g[primaryPrefix .. "R"], g[primaryPrefix .. "G"], g[primaryPrefix .. "B"] = r, gCol, b
    g[legacyPrefix .. "R"], g[legacyPrefix .. "G"], g[legacyPrefix .. "B"] = r, gCol, b
    ApplyColors()
end
local function ApplyGlobalOutlineColor()
    ApplyColors()
end
local function TableRGB(tbl, key, dr, dg, db)
    local t = tbl and tbl[key]
    if type(t) == "table" then
        local r = tonumber(t[1] or t.r or t["1"])
        local g = tonumber(t[2] or t.g or t["2"])
        local b = tonumber(t[3] or t.b or t["3"])
        if r and g and b then return r, g, b end
    end
    return dr, dg, db
end
local function SetTableRGB(tbl, key, r, g, b)
    if not tbl then return end
    tbl[key] = { r, g, b }
end
local function ClearRGB(tbl, prefix)
    if tbl then tbl[prefix .. "R"], tbl[prefix .. "G"], tbl[prefix .. "B"] = nil, nil, nil end
end
local function ClearRGBs(tbl, ...) for i = 1, select("#", ...) do ClearRGB(tbl, select(i, ...)) end end
local function ClearRGBAs(tbl, ...) for i = 1, select("#", ...) do local prefix = select(i, ...); ClearRGB(tbl, prefix); tbl[prefix .. "A"] = nil end end
local function FontPaletteRGB(key, dr, dg, db)
    local colors = _G.MSUF_FONT_COLORS
    if type(colors) == "table" and type(key) == "string" and colors[key:lower()] then
        local c = colors[key:lower()]
        return c[1] or dr, c[2] or dg, c[3] or db
    end
    return dr, dg, db
end
local function HighlightRGB()
    local g = G()
    if type(g.highlightColor) == "table" then return TableRGB(g, "highlightColor", 1, 1, 1) end
    return FontPaletteRGB(g.highlightColor or "white", 1, 1, 1)
end
local function SetHighlightRGB(r, g, b)
    G().highlightColor = { r, g, b }
    ApplyColors()
end
local function TrText(text)
    local translate = M.TranslateText or M.Tr
    if type(translate) == "function" then return translate(text) end
    return text
end
-- Default-aware color controls: an amber dot marks values that differ from the
-- shipped default, right-click restores the default through the normal bound
-- apply path, and section headers show a live "N modified" badge.
local COLOR_DEFAULT_EPS = 0.003
local function FindCollapsibleEntryFor(frame)
    local parent = frame
    for _ = 1, 12 do
        if not parent then return nil end
        local entry = parent._msuf2CollapsibleEntry
        if entry then return entry end
        parent = parent.GetParent and parent:GetParent()
    end
end
local function ColorMatchesDefault(control)
    local defaults = control and control._msuf2DefaultRGB
    if not defaults or not control.GetRGB then return true end
    local r, g, b = control:GetRGB()
    return math.abs((tonumber(r) or 1) - defaults[1]) < COLOR_DEFAULT_EPS
        and math.abs((tonumber(g) or 1) - defaults[2]) < COLOR_DEFAULT_EPS
        and math.abs((tonumber(b) or 1) - defaults[3]) < COLOR_DEFAULT_EPS
end
local function RefreshSectionModifiedBadge(entry)
    if not (entry and entry.body) or type(W.SetCollapsibleBadges) ~= "function" then return end
    local list = entry._msuf2DefaultColorControls
    if not list or #list == 0 then return end
    local count = 0
    for i = 1, #list do
        if not ColorMatchesDefault(list[i]) then count = count + 1 end
    end
    if entry._msuf2ModifiedBadgeCount == count then return end
    entry._msuf2ModifiedBadgeCount = count
    if count > 0 then
        W.SetCollapsibleBadges(entry.body, {{
            text = tostring(count) .. " " .. TrText("modified"),
            kind = "accent",
            showWhenClosed = true,
        }})
    else
        W.SetCollapsibleBadges(entry.body, {})
    end
end
local function AttachDefaultColorBehavior(ctx, control, defaultRGB)
    if not (control and control.GetRGB and control.SetRGB and type(defaultRGB) == "table") then return end
    local dr = tonumber(defaultRGB[1])
    local dg = tonumber(defaultRGB[2])
    local db = tonumber(defaultRGB[3])
    if not (dr and dg and db) then return end
    control._msuf2DefaultRGB = { dr, dg, db }
    local entry = FindCollapsibleEntryFor(control)
    if entry then
        entry._msuf2DefaultColorControls = entry._msuf2DefaultColorControls or {}
        entry._msuf2DefaultColorControls[#entry._msuf2DefaultColorControls + 1] = control
    end
    -- Modified marker: tint the swatch's existing rounded edge amber instead
    -- of drawing an extra corner marker. This reuses the exact pill texture
    -- path every swatch already renders, so it cannot add stray artifacts.
    local edge = control._msuf2Edge
    local function RefreshDot()
        local modified = not ColorMatchesDefault(control)
        if edge and edge.SetVertexColor then
            if modified then
                edge:SetVertexColor(0.98, 0.74, 0.26, 1)
            else
                local base = (T.colors and T.colors.borderSoft) or { 0.30, 0.40, 0.50, 1 }
                edge:SetVertexColor(base[1], base[2], base[3], 0.75)
            end
        end
        if entry then RefreshSectionModifiedBadge(entry) end
    end
    control._msuf2RefreshDefaultDot = RefreshDot
    local baseSetRGB = control.SetRGB
    control.SetRGB = function(self, r, g, b)
        baseSetRGB(self, r, g, b)
        RefreshDot()
    end
    if control.RegisterForClicks then control:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local baseClick = control.GetScript and control:GetScript("OnClick")
    control:SetScript("OnClick", function(self, mouseButton, ...)
        if mouseButton == "RightButton" then
            if self.IsEnabled and not self:IsEnabled() then return end
            local defaults = self._msuf2DefaultRGB
            self:SetRGB(defaults[1], defaults[2], defaults[3])
            if type(self._msuf2OnColorChanged) == "function" then
                self._msuf2OnColorChanged(defaults[1], defaults[2], defaults[3])
            end
            return
        end
        if type(baseClick) == "function" then baseClick(self, mouseButton, ...) end
    end)
    if M.AddTooltip and control._msuf2ColorLabel then
        M.AddTooltip(control, TrText(control._msuf2ColorLabel),
            TrText("Right-click resets this color to its default."), { hook = true })
    end
    RefreshDot()
end
function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth, metadata, defaultRGB)
    local color = W.Color(section, label)
    M.BindColor(ctx, color, getRGB, setRGB, metadata)
    AttachDefaultColorBehavior(ctx, color, defaultRGB)
    if color._msuf2Title then
        local sx, sy = x or 0, y or 0
        local sectionW = section._msuf2Width or 720
        local labelWidth = tonumber(labelWidthOverride) or min(230, max(86, sectionW - sx - 76))
        local buttonWidth = tonumber(swatchWidth) or 44
        color._msuf2Title:ClearAllPoints()
        color._msuf2Title:SetPoint("TOPLEFT", section, "TOPLEFT", sx, sy)
        color._msuf2Title:SetWidth(labelWidth)
        color:SetSize(buttonWidth, 18)
        color:ClearAllPoints()
        color:SetPoint("TOPLEFT", section, "TOPLEFT", sx + labelWidth + 12, sy + 2)
        return color
    end
    return MoveWidget(color, section, x, y)
end
local function ApiColorAt(ctx, section, label, x, y, getName, setName, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c, a)
            if not ApiSetRGB(setName, r, g, c, a) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        labelWidth, swatchWidth, metadata or Meta("api." .. tostring(setName or getName)), { dr, dg, db })
end
local function GeneralColorAt(ctx, section, label, x, y, prefix, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, c, a)
            SetGeneralRGB(prefix, r, g, c, a)
            if type(apply) == "function" then apply() else ApplyColors() end
        end,
        labelWidth, swatchWidth, metadata or Meta("general." .. tostring(prefix)), { dr, dg, db })
end
local function ApiOrGeneralColorAt(ctx, section, label, x, y, getName, setName, prefix, dr, dg, db, apply, alpha, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c, a)
            local nextAlpha = type(a) == "number" and a or alpha
            local ok = nextAlpha ~= nil and ApiCall(setName, r, g, c, nextAlpha) or ApiCall(setName, r, g, c)
            if not ok then
                SetGeneralRGB(prefix, r, g, c, nextAlpha)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        nil, nil, metadata or Meta("general." .. tostring(prefix)), { dr, dg, db })
end
local function TableColorAt(ctx, section, label, x, y, getTable, key, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, c)
            SetTableRGB(getTable(), key, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth, metadata or Meta("table." .. tostring(key)), { dr, dg, db })
end
local function BuildApiColorSpecs(ctx, section, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return ApiColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9] or apply, s[10], s[11]), s[12] or s[5] or i end,
    })
end
local function BuildTableColorSpecs(ctx, section, getTable, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return TableColorAt(ctx, section, s[1], s[2], s[3], getTable, s[4], s[5], s[6], s[7], s[8] or apply, s[9]), s[10] or s[4] or i end,
    })
end
local function BuildApiOrGeneralColorSpecs(ctx, section, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return ApiOrGeneralColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10] or apply, s[11]), s[12] or s[6] or i end,
    })
end
local function ButtonAt(parent, label, x, y, width, onClick, semanticPath)
    local btn = T.Button(parent, label, width or 150, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if type(onClick) == "function" then
        btn:SetScript("OnClick", function(self, ...)
            onClick(self, ...)
            if M.RequestRefresh then M.RequestRefresh(nil, "advanced-colors-button") elseif M.Refresh then M.Refresh() end
        end)
    end
    -- These two resets depend on the adjacent ephemeral selectors and have no
    -- stable Assistant action contract. Keep them menu-executable but exclude
    -- them from automatic Assistant mutation.
    local classification = (semanticPath == "castbar.text_color.reset" or semanticPath == "status_text.color.reset")
        and "ephemeral" or "action"
    RegisterControl(btn, Meta(semanticPath, classification), label, "button")
    return btn
end
local function Card(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return card
end
local GROUP_COLOR_DB_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
local GROUP_COLOR_KINDS = { "party", "raid", "mythicraid" }
local GROUP_BAR_MODES = (M.GroupSpecs and M.GroupSpecs.GF_BAR_MODES)
    or ValueTextPairs "GLOBAL=Follow Global Style|CLASS=Class Color|dark=Dark Mode|unified=Unified Color|GRADIENT=Health Gradient|CUSTOM=Custom Color"
local GROUP_HEALTH_MODES = (M.GroupSpecs and M.GroupSpecs.HEALTH_MODES)
    or ValueTextPairs "CLASS=Class|GRADIENT=Gradient|CUSTOM=Custom"
local function GroupDBConf(dbKey)
    local db = DB()
    db[dbKey] = db[dbKey] or {}
    return db[dbKey]
end
local function GroupRead(key, defaultValue)
    local db = DB()
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = db[GROUP_COLOR_DB_KEYS[i]]
        if conf and conf[key] ~= nil then return conf[key] end
    end
    return defaultValue
end
local function GroupNum(key, defaultValue)
    return tonumber(GroupRead(key, defaultValue)) or defaultValue or 0
end
local function GroupBool(key, defaultValue)
    local value = GroupRead(key, defaultValue and true or false)
    return value and true or false
end
local function RequestGroupColorApply(reason, mode)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGroup) == "function" then
        return apply.RequestGroup("group", mode or "visual", reason or "MSUF2_GROUP_COLORS")
    end
    local GP = M.GroupPage
    if GP and type(GP.QueueGF) == "function" then
        for i = 1, #GROUP_COLOR_KINDS do GP.QueueGF(GROUP_COLOR_KINDS[i], mode or "visual") end
        return true
    end
    return false
end
local function SetGroupValue(key, value, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[key] ~= value then
            conf[key] = value
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
    return changed
end
local function SetGroupRGB(prefix, r, g, b, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[prefix .. "R"] ~= r or conf[prefix .. "G"] ~= g or conf[prefix .. "B"] ~= b then
            conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = r, g, b
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
end
local function SetGroupRGBA(prefix, alphaKey, r, g, b, a, reason, mode)
    local changed = false
    for i = 1, #GROUP_COLOR_DB_KEYS do
        local conf = GroupDBConf(GROUP_COLOR_DB_KEYS[i])
        if conf[prefix .. "R"] ~= r or conf[prefix .. "G"] ~= g or conf[prefix .. "B"] ~= b
            or (a ~= nil and conf[alphaKey] ~= a)
        then
            conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = r, g, b
            if a ~= nil then conf[alphaKey] = a end
            changed = true
        end
    end
    if changed then RequestGroupColorApply(reason, mode or "visual") end
end
local function GroupRGB(prefix, dr, dg, db)
    return GroupNum(prefix .. "R", dr), GroupNum(prefix .. "G", dg), GroupNum(prefix .. "B", db)
end
local function GroupColorAt(ctx, section, label, x, y, prefix, dr, dg, db, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GroupRGB(prefix, dr, dg, db) end,
        function(r, g, b) SetGroupRGB(prefix, r, g, b, "MSUF2_GROUP_COLORS", "visual") end,
        labelWidth, swatchWidth, Meta("group_frame.color." .. tostring(prefix)), { dr, dg, db })
end
local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function PercentLabel(label, value)
    return tostring(label or "") .. ": " .. tostring(floor(Clamp01(value, 0) * 100 + 0.5)) .. "%"
end
local function GroupAlphaSlider(ctx, parent, label, x, y, width, key, defaultValue)
    local slider = W.Slider(parent, "", 0, 1, 0.05, width or 260)
    M.BindNumberWidget(ctx, slider,
        function() return GroupNum(key, defaultValue) end,
        function(value) SetGroupValue(key, Clamp01(value, defaultValue), "MSUF2_GROUP_COLORS", "visual") end,
        defaultValue,
        Meta("group_frame.alpha." .. tostring(key)))
    MoveWidget(slider, parent, x, y)
    if M.BindSliderLiveLabel then
        M.BindSliderLiveLabel(ctx, slider, function() return GroupNum(key, defaultValue) end,
            function(value) return PercentLabel(label, value) end, true)
    end
    return slider
end
local function CurrentGlobalBarColor()
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = (type(getCache) == "function") and getCache() or nil
    local modeKey = cache and cache.barMode
    if modeKey == "unified" then
        return cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90
    elseif modeKey == "dark" then
        return cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0
    end
    local g = G()
    return g.unifiedBarR or 0.10, g.unifiedBarG or 0.60, g.unifiedBarB or 0.90
end
local function GroupBarMode()
    local mode = GroupRead("gfBarMode", "GLOBAL")
    if mode == nil or mode == "" then return "GLOBAL" end
    return mode
end
local function GroupHealthBarRGB()
    local mode = GroupBarMode()
    if mode == "GLOBAL" then return CurrentGlobalBarColor() end
    if mode == "dark" then return GroupRGB("gfDark", 0, 0, 0) end
    if mode == "unified" then return GroupRGB("gfUnified", 0.10, 0.60, 0.90) end
    if mode == "CUSTOM" then return GroupRGB("healthCustom", 0.20, 0.80, 0.20) end
    return 0.20, 0.80, 0.20
end
local function SetGroupHealthBarRGB(r, g, b)
    local mode = GroupBarMode()
    if mode == "dark" then
        SetGroupRGB("gfDark", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    elseif mode == "unified" then
        SetGroupRGB("gfUnified", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    elseif mode == "CUSTOM" then
        SetGroupRGB("healthCustom", r, g, b, "MSUF2_GROUP_HEALTH_COLOR", "visual")
    end
end
local function BuildGroupFrameColors(ctx, b)
    local pageW = b.width or ctx.width or 720
    local cardW = max(320, pageW - 32)
    local health = b:CollapsibleSection("colors_group_frames", "Health Bars", 112, true)
    local background = b:CollapsibleSection("colors_group_frames_background", "Bar Background", 112, false)
    local state = b:CollapsibleSection("colors_group_frames_state", "State Tints", 242, false)
    local highlights = b:CollapsibleSection("colors_group_frames_highlights", "Group Highlights", 220, false)

    ValueDropdownAt(ctx, health, "Bar Color Mode", 12, -10, GROUP_BAR_MODES, min(360, cardW - 32),
        GroupBarMode,
        function(value)
            value = value or "GLOBAL"
            SetGroupValue("gfBarMode", value == "GLOBAL" and nil or value, "MSUF2_GROUP_HEALTH_MODE", "visual")
            if value == "CLASS" or value == "GRADIENT" then
                SetGroupValue("healthColorMode", value, "MSUF2_GROUP_HEALTH_MODE", "visual")
            end
            if M.RequestRefresh then M.RequestRefresh(ctx, "group-colors-mode") end
        end,
        Meta("group_frame.health.mode"))
    local healthColor = ColorValueAt(ctx, health, "Health bar color", 12, -64, GroupHealthBarRGB, SetGroupHealthBarRGB,
        nil, nil, Meta("group_frame.health.color"))

    GroupColorAt(ctx, background, "Background Color", 12, -10, "bg", 0.10, 0.10, 0.10)
    ValueDropdownAt(ctx, background, "Health color fallback", 12, -56, GROUP_HEALTH_MODES, min(360, cardW - 32),
        function() return GroupRead("healthColorMode", "CLASS") or "CLASS" end,
        function(value) SetGroupValue("healthColorMode", value or "CLASS", "MSUF2_GROUP_HEALTH_FALLBACK", "visual") end,
        Meta("group_frame.health.fallback_mode"))

    ValueSwitchAt(ctx, state, "Dead / Offline Background", 12, -10, min(320, cardW - 32),
        function() return GroupBool("deadBgEnabled", false) end,
        function(value) SetGroupValue("deadBgEnabled", value and true or false, "MSUF2_GROUP_DEAD_BG", "visual") end,
        Meta("group_frame.state.dead_offline.enabled"))
    local deadColor = GroupColorAt(ctx, state, "Background color", 12, -48, "deadBg", 0.60, 0.05, 0.05)
    local deadAlpha = GroupAlphaSlider(ctx, state, "Dead/offline opacity", 12, -86, max(220, cardW - 58), "deadBgA", 0.90)
    local offline = ValueToggleAt(ctx, state, "Also tint offline members", 12, -132,
        function() return GroupBool("deadBgOffline", true) end,
        function(value) SetGroupValue("deadBgOffline", value and true or false, "MSUF2_GROUP_DEAD_BG_OFFLINE", "visual") end,
        Meta("group_frame.state.dead_offline.include_offline"))
    GroupColorAt(ctx, state, "Debuff stripe color", 12, -166, "debuffStripeColor", 0.80, 0.20, 0.20)
    GroupAlphaSlider(ctx, state, "Debuff stripe opacity", 12, -202, max(220, cardW - 58), "debuffStripeAlpha", 0.60)

    GroupColorAt(ctx, highlights, "Target Highlight Color", 12, -10, "target", 1, 1, 1)
    GroupColorAt(ctx, highlights, "Focus Highlight Color", 12, -48, "hlFocusColor", 0.50, 0.50, 1.00)
    GroupColorAt(ctx, highlights, "Group Border Color", 12, -86, "groupBorder", 0.38, 0.68, 1.00)
    GroupAlphaSlider(ctx, highlights, "Group border opacity", 12, -128, max(220, cardW - 58), "groupBorderA", 0.95)
    GroupColorAt(ctx, highlights, "Corner aggro color", 12, -174, "ciAggroColor", 1.00, 0.55, 0.00)
    M.BindGateGroup(ctx, nil, {
        { controls = healthColor, on = function()
            local current = GroupBarMode()
            return current == "dark" or current == "unified" or current == "CUSTOM"
        end },
        { controls = { deadColor, deadAlpha, offline }, on = function() return GroupBool("deadBgEnabled", false) end },
    })
end
local function NPCColorAt(ctx, section, row, x, y, apply)
    return ColorValueAt(ctx, section, row.label, x, y,
        function() return ApiRGB("GetNPCColor", row.dr, row.dg, row.db, row.key) end,
        function(r, g, c)
            if not ApiCall("SetNPCColor", row.key, r, g, c) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        nil, nil, Meta("npc.color." .. tostring(row.key)), { row.dr, row.dg, row.db })
end
local function ResetNPCColors(apiName)
    if ApiCall(apiName) then return end
    DB().npcColors = nil
    ApplyUnitframeColorWithReload()
end
local function ResetUnitframeColors()
    local db = DB()
    local g = G()
    db.npcColors = nil
    ClearRGB(g, "petFrameColor")
    g.petFrameUsePlayerClassColor = nil
    g.npcClassColorBar = nil
    ApplyUnitframeColorWithReload()
end
local COLOR_HELPERS = {
    ApiColorAt = ApiColorAt,
    ApiColorSpecs = BuildApiColorSpecs,
    ApiOrGeneralColorSpecs = BuildApiOrGeneralColorSpecs,
    ButtonAt = ButtonAt,
    GeneralColorAt = GeneralColorAt,
    TableColorSpecs = BuildTableColorSpecs,
    TableColorAt = TableColorAt,
}
local function GetClassTokens()
    local tokens = ColorAPI().CLASS_TOKENS
    if type(tokens) == "table" and #tokens > 0 then return tokens end
    return COLOR_CLASS_TOKENS
end
local function ClassDefaultRGB(token)
    local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end
local function ClassColorRGB(token)
    local r, g, b = ClassDefaultRGB(token)
    return ApiRGB("GetClassColor", r, g, b, token)
end
local function GetNPCTypeUnits()
    local units = ColorAPI().NPC_TYPE_UNITS
    if type(units) == "table" and #units > 0 then return units end
    return KLR [[npcTypeTarget=Target
npcTypeFocus=Focus
npcTypeBoss=Boss
npcTypeToT=Target of Target]]
end
local function PowerDefaultRGB(token)
    local col = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(col) == "table" then
        local r = tonumber(col.r or col[1])
        local g = tonumber(col.g or col[2])
        local b = tonumber(col.b or col[3])
        if r and g and b then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end
local function EnsurePowerOverrides()
    local g = G()
    if type(g.powerColorOverrides) ~= "table" then g.powerColorOverrides = {} end
    return g.powerColorOverrides
end
local function GetPowerOverrideRGB(token)
    local overrides = G().powerColorOverrides
    local r, g, b = PowerDefaultRGB(token)
    if type(overrides) == "table" then return TableRGB(overrides, token, r, g, b) end
    return r, g, b
end
local function SetPowerOverrideRGB(token, r, g, b)
    EnsurePowerOverrides()[token] = { r, g, b }
    ApplyColors()
end
local function ResetPowerOverride(token)
    local overrides = EnsurePowerOverrides()
    overrides[token] = nil
    ApplyColors()
end
local CLASS_POWER_STATIC_DEFAULTS = {}
for _, row in ipairs(ColorRows [[CHARGED|Charged|0.60|0.20|0.80;SOUL_FRAGMENTS|Soul Fragments|0.00|0.80|0.00;SOUL_FRAGMENTS_META|Soul Fragments Meta|0.60|0.20|0.93;MAELSTROM_ABOVE_5|Maelstrom Above 5|1.00|0.50|0.00;ECLIPSE_SOLAR|Eclipse Solar|0.82|0.56|0.25;ECLIPSE_LUNAR|Eclipse Lunar|0.41|0.49|0.82;ECLIPSE_CA|Eclipse CA|0.30|1.00|0.43;STAGGER_GREEN|Stagger Green|0.52|1.00|0.52;STAGGER_YELLOW|Stagger Yellow|1.00|0.98|0.72;STAGGER_RED|Stagger Red|1.00|0.42|0.42;SOUL_FRAGMENTS_VENG|Soul Fragments Veng|0.34|0.06|0.46;WHIRLWIND|Whirlwind|0.20|0.80|0.20;TIP_OF_THE_SPEAR|Tip of the Spear|0.60|0.80|0.20;ICICLES|Icicles|0.50|0.80|1.00;EBON_MIGHT|Ebon Might|0.40|0.80|0.60]]) do
    CLASS_POWER_STATIC_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local CLASS_POWER_POWER_DEFAULTS = KeyLabelMap [[MAELSTROM=MAELSTROM|MAELSTROM_POWER=MAELSTROM|ASTRAL_POWER=LUNAR_POWER|AP_PREDICTION=LUNAR_POWER|INSANITY=INSANITY]]
local function ClassPowerDefaultRGB(token)
    local slot = COLOR_CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    local static = CLASS_POWER_STATIC_DEFAULTS[token]
    if static then return static[1], static[2], static[3] end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1) end
    local powerToken = CLASS_POWER_POWER_DEFAULTS[token]
    if powerToken then return GetPowerOverrideRGB(powerToken) end
    return GetPowerOverrideRGB(token)
end
local function EnsureClassPowerOverrides()
    local g = G()
    if type(g.classPowerColorOverrides) ~= "table" then g.classPowerColorOverrides = {} end
    if type(g.classPowerBgColorOverrides) ~= "table" then g.classPowerBgColorOverrides = {} end
    return g
end
local function GetClassPowerRGB(token)
    local dr, dg, db = ClassPowerDefaultRGB(token)
    local g = G()
    return TableRGB(g.classPowerColorOverrides, token, dr, dg, db)
end
local function SetClassPowerRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end
local function GetClassPowerBgRGB(token)
    return TableRGB(G().classPowerBgColorOverrides, token, 0, 0, 0)
end
local function SetClassPowerBgRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end
local function ResetClassPowerRGB(token, bg)
    local g = EnsureClassPowerOverrides()
    if bg then g.classPowerBgColorOverrides[token] = nil else g.classPowerColorOverrides[token] = nil end
    ApplyClassPowerColors()
end
local function ClassPowerSlotToken(resourceToken, slot)
    if resourceToken == "COMBO_POINTS" and slot <= #COLOR_CP_SLOT_TOKENS then
        return COLOR_CP_SLOT_TOKENS[slot]
    end
    return tostring(resourceToken or "COMBO_POINTS") .. "_" .. tostring(slot)
end
local function ClassPowerSlotCount(resourceToken)
    return COLOR_CP_SLOT_COUNTS[resourceToken] or 0
end
local function GetClassPowerSlotMode(resourceToken)
    local bars = Bars()
    local modes = bars.classPowerSlotColorModes
    local mode = type(modes) == "table" and modes[resourceToken] or nil
    if mode == nil and resourceToken == "COMBO_POINTS" then mode = bars.classPowerComboPointColorMode end
    if mode ~= "ramp" and mode ~= "custom" then return "default" end
    return mode
end
local function SetClassPowerSlotMode(resourceToken, mode)
    local bars = Bars()
    if type(bars.classPowerSlotColorModes) ~= "table" then bars.classPowerSlotColorModes = {} end
    mode = (mode == "ramp" or mode == "custom") and mode or "default"
    bars.classPowerSlotColorModes[resourceToken] = mode ~= "default" and mode or nil
    if resourceToken == "COMBO_POINTS" then bars.classPowerComboPointColorMode = mode end
    ApplyClassPowerColors()
end
local function GetClassPowerSlotRGB(resourceToken, slot)
    local token = ClassPowerSlotToken(resourceToken, slot)
    local overrides = G().classPowerColorOverrides
    if type(overrides) == "table" and type(overrides[token]) == "table" then
        return TableRGB(overrides, token, 1, 1, 1)
    end
    if resourceToken ~= "COMBO_POINTS" and GetClassPowerSlotMode(resourceToken) ~= "ramp" then
        return GetClassPowerRGB(resourceToken)
    end
    local rampSlot = slot > 7 and 7 or slot
    local fallback = COLOR_CP_SLOT_DEFAULTS[COLOR_CP_SLOT_TOKENS[rampSlot]]
    if fallback then return fallback[1], fallback[2], fallback[3] end
    return GetClassPowerRGB(resourceToken)
end
local function ClassPowerFullColorToken(resourceToken)
    return tostring(resourceToken or "COMBO_POINTS") .. "_FULL"
end
local function ClassPowerFullColorEnabled(resourceToken)
    local enabled = Bars().classPowerFullColorEnabled
    return type(enabled) == "table" and enabled[resourceToken] == true
end
local function SetClassPowerFullColorEnabled(resourceToken, enabled)
    local bars = Bars()
    if type(bars.classPowerFullColorEnabled) ~= "table" then bars.classPowerFullColorEnabled = {} end
    bars.classPowerFullColorEnabled[resourceToken] = enabled == true and true or nil
    ApplyClassPowerColors()
end
local function GetClassPowerFullRGB(resourceToken)
    local token = ClassPowerFullColorToken(resourceToken)
    local overrides = G().classPowerColorOverrides
    if type(overrides) == "table" and type(overrides[token]) == "table" then
        return TableRGB(overrides, token, 1, 1, 1)
    end
    return GetClassPowerRGB(resourceToken)
end
function M._ContextGetAuraSafeRGB()
    local color = G().aurasCooldownTextSafeColor
    if type(color) == "table" then
        return TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1)
    end
    return M._ContextConfiguredGlobalFontRGB()
end
function M._ContextSetAuraSafeRGB(r, g, b)
    G().aurasCooldownTextSafeColor = { r, g, b }
    ApplyAuraColors()
end
local function ReadAuraNumber(key, defaultValue, minValue, maxValue)
    local value = tonumber(G()[key]) or defaultValue
    if minValue then value = max(minValue, value) end
    if maxValue then value = min(maxValue, value) end
    return value
end
local function WriteAuraNumber(key, value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue then value = max(minValue, value) end
    if maxValue then value = min(maxValue, value) end
    if floor(value) == value then value = floor(value + 0.5) end
    G()[key] = value
    ApplyAuraColors()
end
local function ResetAuraColorSettings()
    local g = G()
    g.aurasCooldownTextUseBuckets = false
    g.aurasCooldownTextSafeColor = nil
    g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    g.aurasCooldownTextSafeSeconds = 60
    g.aurasCooldownTextWarningSeconds = 15
    g.aurasCooldownTextUrgentSeconds = 5
    g.dispelTypeColorOverrides = nil
    ApplyAuraColors()
end
local function SetAllPortraitRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
    ApplyPortraitColors(prefix)
end
--- Texture layer colors mirror the portrait pattern: the Colors page writes the
--- general baseline plus every unit's copy, while the unit accordion edits only
--- its own frame. Refreshes are cold path (one re-stamp per frame). Stored on M
--- instead of file locals: this file rides the 200 active-local ceiling.
function M._ApplyTextureLayerColors()
    CallGlobal("MSUF_RefreshUnitTextureLayers")
    CallGlobal("MSUF_UFPreview_RequestRefresh", "MSUF2_TEXLAYER")
end
function M._SetAllTextureLayerRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
    M._ApplyTextureLayerColors()
end
local function BuildPowerAndClassPowerColors(ctx, b, CH)
    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            M.SetMenuStateValue("colorsPowerToken", v or "MANA")
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
            -- The painter's resources preview strip mirrors this selection.
            if M.RequestRefresh then M.RequestRefresh(ctx, "power-color-token") end
        end,
        Meta("power.editor.resource_selector", "ephemeral"))
    powerColor = ColorValueAt(ctx, power, "Color", 360, -10,
        function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
        function(r, g, c) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, c) end,
        nil, nil, Meta("power.editor.color"))
    CH.ButtonAt(power, "Reset", 360, -54, 90, function()
        ResetPowerOverride(M.colorsPowerToken or "MANA")
        if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken or "MANA")) end
    end, "power.editor.reset")
    local classPower = b:CollapsibleSection("colors_class_power", "Class Power Colors", 430, false)
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local cpColor, cpBg, slotMode, slotReset, fullToggle, fullColor, fullReset
    local slotControls = {}
    local visibleSlotCount, slotControlsAvailable
    local function RequestClassPowerEditorRefresh(reason)
        if M.RequestRefresh then
            M.RequestRefresh(ctx, reason or "class-power-resource-editor")
        elseif M.Refresh then
            M.Refresh(ctx)
        end
    end
    local function RefreshSlotControls()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        local count = min(#slotControls, ClassPowerSlotCount(resourceToken))
        local hasSlots = count > 0
        if slotControlsAvailable ~= hasSlots then
            -- New controls start shown. Avoid reapplying that default on the
            -- common slot-based resources; SetControlShown also refreshes the
            -- control layout and is intentionally reserved for real deltas.
            if slotControlsAvailable ~= nil or not hasSlots then
                W.SetControlShown(slotMode, hasSlots)
                W.SetControlShown(slotReset, hasSlots)
                W.SetControlShown(fullToggle, hasSlots)
                W.SetControlShown(fullColor, hasSlots)
                W.SetControlShown(fullReset, hasSlots)
            end
            slotControlsAvailable = hasSlots
        end
        if visibleSlotCount == nil then
            for i = count + 1, #slotControls do W.SetControlShown(slotControls[i], false) end
        elseif count < visibleSlotCount then
            for i = count + 1, visibleSlotCount do W.SetControlShown(slotControls[i], false) end
        elseif count > visibleSlotCount then
            for i = visibleSlotCount + 1, count do W.SetControlShown(slotControls[i], true) end
        end
        visibleSlotCount = count
    end
    ValueDropdownAt(ctx, classPower, "Resource type", 12, -10, COLOR_DATA.CP_TOKENS, 310,
        function() return M.colorsCPToken or "COMBO_POINTS" end,
        function(v)
            M.SetMenuStateValue("colorsCPToken", v or "COMBO_POINTS")
            RequestClassPowerEditorRefresh("class-power-resource-selection")
        end,
        Meta("class_power.editor.resource_selector", "ephemeral"))
    cpColor = ColorValueAt(ctx, classPower, "Color", 360, -10,
        function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end,
        nil, nil, Meta("class_power.editor.foreground_color"))
    cpBg = ColorValueAt(ctx, classPower, "Background", 360, -46,
        function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end,
        nil, nil, Meta("class_power.editor.background_color"))
    CH.ButtonAt(classPower, "Reset color", 360, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", false)
        if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end, "class_power.editor.reset_foreground")
    CH.ButtonAt(classPower, "Reset bg", 480, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", true)
        if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end, "class_power.editor.reset_background")
    slotMode = ValueDropdownAt(ctx, classPower, "Resource slot mode", 12, -92, COLOR_DATA.CP_SLOT_MODES, 230,
        function()
            return GetClassPowerSlotMode(M.colorsCPToken or "COMBO_POINTS")
        end,
        function(v)
            SetClassPowerSlotMode(M.colorsCPToken or "COMBO_POINTS", v)
        end,
        Meta("class_power.resource_slots.mode"))
    fullToggle = ValueSwitchAt(ctx, classPower, "Full resource color", 360, -116, 150,
        function() return ClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS") end,
        function(value)
            SetClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS", value)
        end,
        Meta("class_power.full_resource.enabled"))
    fullColor = ColorValueAt(ctx, classPower, "Full", 540, -116,
        function() return GetClassPowerFullRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, b)
            local resourceToken = M.colorsCPToken or "COMBO_POINTS"
            local enabled = ClassPowerFullColorEnabled(resourceToken)
            if not enabled then SetClassPowerFullColorEnabled(resourceToken, true) end
            SetClassPowerRGB(ClassPowerFullColorToken(resourceToken), r, g, b)
            if not enabled then RequestClassPowerEditorRefresh("class-power-full-color") end
        end, 36, 44, Meta("class_power.full_resource.color"))
    for i = 1, 10 do
        local slot = i
        slotControls[i] = ColorValueAt(ctx, classPower, tostring(i), 12 + ((i - 1) % 4) * 160, -154 - floor((i - 1) / 4) * 38,
            function() return GetClassPowerSlotRGB(M.colorsCPToken or "COMBO_POINTS", slot) end,
            function(r, g, c)
                local resourceToken = M.colorsCPToken or "COMBO_POINTS"
                local custom = GetClassPowerSlotMode(resourceToken) == "custom"
                if not custom then SetClassPowerSlotMode(resourceToken, "custom") end
                SetClassPowerRGB(ClassPowerSlotToken(resourceToken, slot), r, g, c)
                if not custom then RequestClassPowerEditorRefresh("class-power-slot-color") end
            end, 24, 44, Meta("class_power.resource_slots.slot." .. tostring(i)))
    end
    slotReset = CH.ButtonAt(classPower, "Reset slots", 12, -284, 120, function()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        local g = EnsureClassPowerOverrides()
        for i = 1, ClassPowerSlotCount(resourceToken) do
            g.classPowerColorOverrides[ClassPowerSlotToken(resourceToken, i)] = nil
        end
        ApplyClassPowerColors()
        RequestClassPowerEditorRefresh("class-power-slots-reset")
    end, "class_power.resource_slots.reset")
    fullReset = CH.ButtonAt(classPower, "Reset full", 142, -284, 110, function()
        local resourceToken = M.colorsCPToken or "COMBO_POINTS"
        EnsureClassPowerOverrides().classPowerColorOverrides[ClassPowerFullColorToken(resourceToken)] = nil
        SetClassPowerFullColorEnabled(resourceToken, false)
        RequestClassPowerEditorRefresh("class-power-full-color-reset")
    end, "class_power.full_resource.reset")
    M.TrackRefresh(ctx, RefreshSlotControls)
end
local function BuildAuraAndPortraitColors(ctx, b, CH, part)
    if part ~= "portrait" then
    local auras = b:CollapsibleSection("colors_auras", "Auras", 900, false)
    local w = auras._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(auras, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(auras, "Timer Thresholds", nil, rightX, -42, colW, 380)

    local preview = T.Panel(cooldown, nil, T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.82 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cooldown, "TOPLEFT", 16, -60)
    preview:SetSize(colW - 32, 88)
    W.LabelAt(preview, "Preview", 12, -12, 120, "GameFontNormalSmall", T.colors.muted)
    local samples = {}
    local sampleAreaW = max(180, (colW - 32) - 88)
    local sampleBoxW = min(64, max(52, floor((sampleAreaW - 16) / 3)))
    local sampleGap = max(8, floor((sampleAreaW - sampleBoxW * 3) / 2))
    for i = 1, 3 do
        local box = T.Panel(preview, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.92 }, T.colors.borderSoft)
        box:SetPoint("LEFT", preview, "LEFT", 88 + (i - 1) * (sampleBoxW + sampleGap), -6)
        box:SetSize(sampleBoxW, 54)
        local fs = T.Font(box, nil, i == 1 and "60" or (i == 2 and "15" or "5"), T.colors.text)
        fs:SetFont(FONT, T.FontSize("heading"), "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 6)
        local label = T.Font(box, "GameFontDisableSmall", i == 1 and "Safe" or (i == 2 and "Warn" or "Urgent"), T.colors.muted)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i] = fs
    end
    local function RefreshColorSamples()
        local sr, sg, sb = M._ContextGetAuraSafeRGB()
        local wr, wg, wb = TableRGB(G(), "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        local ur, ug, ub = TableRGB(G(), "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
        local buckets = G().aurasCooldownTextUseBuckets == true
        samples[1]:SetTextColor(sr, sg, sb, 1)
        samples[2]:SetTextColor(buckets and wr or sr, buckets and wg or sg, buckets and wb or sb, 1)
        samples[3]:SetTextColor(buckets and ur or sr, buckets and ug or sg, buckets and ub or sb, 1)
    end
    ValueSwitchAt(ctx, cooldown, "Color by time", 16, -166, colW - 32,
        function() return G().aurasCooldownTextUseBuckets == true end,
        function(v)
            G().aurasCooldownTextUseBuckets = v and true or false
            RefreshColorSamples()
            ApplyAuraColors()
        end,
        Meta("auras.cooldown.color_by_time"))
    local function AuraColorAt(parent, label, y, key, r, g, bcol, after)
        return CH.TableColorAt(ctx, parent, label, 16, y, G, key, r, g, bcol,
            after or ApplyAuraColors, nil, nil, Meta("auras.color." .. tostring(key)))
    end
    local function RefreshTextColors()
        RefreshColorSamples()
        ApplyAuraColors()
    end
    ColorValueAt(ctx, cooldown, "Safe", 16, -210, M._ContextGetAuraSafeRGB,
        function(r, g, b)
            M._ContextSetAuraSafeRGB(r, g, b)
            RefreshColorSamples()
        end, nil, nil, Meta("auras.color.aurasCooldownTextSafeColor"), { 1, 1, 1 })
    AuraColorAt(cooldown, "Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, RefreshTextColors)
    AuraColorAt(cooldown, "Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, RefreshTextColors)
    ValueSliderAt(ctx, markers, "Safe seconds", 16, -72, 0, 600, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) WriteAuraNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end,
        Meta("auras.cooldown.safe_seconds"))
    ValueSliderAt(ctx, markers, "Warning <= sec", 16, -142, 0, 60, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) WriteAuraNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end,
        Meta("auras.cooldown.warning_seconds"))
    ValueSliderAt(ctx, markers, "Urgent <= sec", 16, -212, 0, 30, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) WriteAuraNumber("aurasCooldownTextUrgentSeconds", v, 0, 30) end,
        Meta("auras.cooldown.urgent_seconds"))
    W.Text(markers, "Thresholds choose when Warning and Urgent replace the Safe timer color.", 16, -276, colW - 32, T.colors.muted)
    local dispel = Card(auras, "Dispel Type Colors", nil, 24, -448, w - 48, 310)
    W.Text(dispel, "Optional global overrides for harmful Magic, Curse, Disease, Poison and Bleed indicators. Off uses Blizzard's current default. The last edited type is shown first in every aura preview.", 16, -52, w - 80, T.colors.muted)
    for i = 1, #M.DISPEL_COLOR_SPECS do
        local spec = M.DISPEL_COLOR_SPECS[i]
        local dispelType, y = spec.key, -104 - ((i - 1) * 38)
        local color, custom
        custom = ValueSwitchAt(ctx, dispel, dispelType .. " custom", 16, y, 250,
            function() return M._HasDispelTypeColorOverride(dispelType) end,
            function(value)
                M._SetDispelTypeColorEnabled(dispelType, value)
                if color then color:SetRGB(M._GetDispelTypeRGB(dispelType, true)) end
            end,
            Meta("auras.dispel." .. spec.path .. ".enabled"))
        color = ColorValueAt(ctx, dispel, dispelType .. " color", 330, y,
            function() return M._GetDispelTypeRGB(dispelType, true) end,
            function(r, g, blue)
                M._SetDispelTypeRGB(dispelType, r, g, blue)
                if custom then custom:SetChecked(true) end
            end,
            120, 44, Meta("auras.dispel." .. spec.path .. ".color"))
    end
    W.Text(auras, "Timer and Dispel colors are shared by live unit/group auras and every preview. Icon border and shadow colors live in Appearance > Auras, scoped by Aura type.", 24, -786, w - 48, T.colors.muted)
    CH.ButtonAt(auras, "Reset aura colors", 24, -838, 150, ResetAuraColorSettings, "auras.reset")
    M.TrackRefresh(ctx, RefreshColorSamples)
    end
    if part == "auras" then return end

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end,
        nil, nil, Meta("portrait.border_color"), { 1, 1, 1 })
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end,
        nil, nil, Meta("portrait.background_color"), { 0.05, 0.05, 0.05 })
    CH.ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end, "portrait.reset")
end
local function OpenFontsTextColors()
    if W.CloseDropdown then W.CloseDropdown() end
    local request = {
        pageKey = "opt_fonts",
        sectionId = "fonts_name_power_colors",
        explicit = true,
        consumed = false,
        source = "colors-global-font-to-fonts",
        changedAt = GetTime and GetTime() or 0,
    }
    _G.MSUF_EM2_MenuFocusRequest = request
    if type(M.SelectPage) ~= "function" or M.SelectPage("opt_fonts") == false then
        if _G.MSUF_EM2_MenuFocusRequest == request then _G.MSUF_EM2_MenuFocusRequest = nil end
        return false
    end
    return true
end
-- Text-color MODES mirrored from Fonts > Text Colors, pinned to the SHARED
-- font scope so edits here are deterministic no matter which scope the Fonts
-- page currently targets. Same storage keys, same apply route - one source of
-- truth; per-frame and group overrides stay on the Fonts page.
local function FontColorSwatch()
    local r, g, b = M._ContextConfiguredGlobalFontRGB()
    return { r, g, b }
end
local function PlayerClassSwatch()
    local classToken
    if type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass("player")
        classToken = token
    end
    local r, g, b = ClassColorRGB(classToken or "WARRIOR")
    return { r, g, b }
end
local function NPCReactionSwatch()
    local r, g, b = ApiRGB("GetNPCColor", 0.85, 0.10, 0.10, "enemy")
    return { r, g, b }
end
local function HealthGradientSwatch()
    return { 1, 0.7, 0 }
end
local function PowerTypeSwatch()
    local token
    if type(_G.UnitPowerType) == "function" then
        local _, powerToken = _G.UnitPowerType("player")
        token = powerToken
    end
    local r, g, b = GetPowerOverrideRGB(token and token ~= "" and token or "MANA")
    return { r, g, b }
end
-- Frame and indicator choices for the canonical status text color surface. The
-- indicator value IS the DB key prefix, which keeps this list and the engine's
-- PrefixedStatusDef naming in one piece. Parked on M rather than a file local:
-- this chunk is at Lua 5.1's 200-local ceiling and one more breaks the page.
M._statusTextColor = {
    units = ValueTextPairs "player=Player|target=Target|focus=Focus|targettarget=Target of Target|focustarget=Focus Target|pet=Pet|boss=Boss Frames",
    indicators = ValueTextPairs "levelIndicator=Level Text|raceIndicator=Race Text|classTextIndicator=Class Text|raidGroupName=Raid Group|statusText=Dead / Offline Text|statusGhostText=Ghost Text|statusAFKText=AFK Text|statusDNDText=DND Text",
    unitKeys = {},
    prefixKeys = {},
}
for i = 1, #M._statusTextColor.units do M._statusTextColor.unitKeys[M._statusTextColor.units[i].value] = true end
for i = 1, #M._statusTextColor.indicators do M._statusTextColor.prefixKeys[M._statusTextColor.indicators[i].value] = true end
local FONT_TEXT_MODE_VALUES = {
    name = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassSwatch },
        { value = "CUSTOM", text = "Custom Color", swatchColor = function()
            local g = G()
            return tonumber(g.nameColorR) or 1, tonumber(g.nameColorG) or 1, tonumber(g.nameColorB) or 1
        end },
    },
    npc = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "NPC", text = "NPC / Reaction Color", swatchColor = NPCReactionSwatch },
        { value = "CLASS", text = "Class Color (Reaction fallback)", swatchColor = PlayerClassSwatch },
    },
    health = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassSwatch },
        { value = "HEALTH", text = "Health Gradient", swatchColor = HealthGradientSwatch },
    },
    power = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "RESOURCE", text = "By Power Type", swatchColor = PowerTypeSwatch },
    },
}
local function ApplySharedFontTextColors(reason)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestFonts) == "function" then
        return apply.RequestFonts(reason or "MSUF2_COLORS_TEXT_MODES", "shared")
    end
    return RequestGeneral(reason or "MSUF2_COLORS_TEXT_MODES", { preview = true, applyAll = true })
end
local function BuildFontAndClassColors(ctx, b, CH, part)
    if part ~= "classes" then
    local font = b:CollapsibleSection("colors_font", "Text Colors", 296, false)
    local fontW = font._msuf2Width or ctx.width or 720
    CH.ApiColorAt(ctx, font, "Global font color", 12, -10, "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1)
    CH.ButtonAt(font, "Use font palette", 360, -10, 170, function()
        if not ApiCall("ResetGlobalFontToPalette") then
            G().useCustomFontColor = false
            ClearRGB(G(), "fontColorCustom")
            ApplyColors()
        end
    end, "font.use_palette")
    local refreshNameCustomColor
    local nameModeDropdown = ValueDropdownAt(ctx, font, "Player Name Color", 12, -52, FONT_TEXT_MODE_VALUES.name, 300,
        function()
            local g = G()
            if g.nameColorMode == "CUSTOM" then return "CUSTOM" end
            return g.nameClassColor and "CLASS" or "DEFAULT"
        end,
        function(v)
            local g = G()
            if v ~= "CLASS" and v ~= "CUSTOM" then v = "DEFAULT" end
            -- nameColorMode is the new source of truth; nameClassColor stays in
            -- sync so the engine fallback and older profiles keep working.
            g.nameColorMode = v
            g.nameClassColor = v == "CLASS"
            ApplySharedFontTextColors("MSUF2_NAME_CLASS_COLOR")
            if refreshNameCustomColor then refreshNameCustomColor() end
        end,
        Meta("font.text_mode.player_name", "ephemeral"))
    local npcModeDropdown = ValueDropdownAt(ctx, font, "NPC / Boss Name Color", 360, -52, FONT_TEXT_MODE_VALUES.npc, 300,
        function()
            local g = G()
            if g.nameNpcClassColor then return "CLASS" end
            return g.npcNameRed and "NPC" or "DEFAULT"
        end,
        function(v)
            local g = G()
            g.nameNpcClassColor = v == "CLASS"
            g.npcNameRed = v == "NPC"
            ApplySharedFontTextColors("MSUF2_NPC_NAME_COLOR")
        end,
        Meta("font.text_mode.npc_name", "ephemeral"))
    local hpModeDropdown = ValueDropdownAt(ctx, font, "HP Text Color", 12, -112, FONT_TEXT_MODE_VALUES.health, 300,
        function()
            local value = G().colorHealthTextByHealth
            if value == "CLASS" then return "CLASS" end
            return (value == true or value == "HEALTH") and "HEALTH" or "DEFAULT"
        end,
        function(v)
            G().colorHealthTextByHealth = (v == "CLASS") and "CLASS" or (v == "HEALTH")
            ApplySharedFontTextColors("MSUF2_HP_TEXT_COLOR")
        end,
        Meta("font.text_mode.hp_text", "ephemeral"))
    local powerModeDropdown = ValueDropdownAt(ctx, font, "Power Text Color", 360, -112, FONT_TEXT_MODE_VALUES.power, 300,
        function() return G().colorPowerTextByType and "RESOURCE" or "DEFAULT" end,
        function(v)
            G().colorPowerTextByType = v == "RESOURCE"
            ApplySharedFontTextColors("MSUF2_POWER_TEXT_COLOR")
        end,
        Meta("font.text_mode.power_text", "ephemeral"))
    if M.AddTooltip then
        -- "Player" means player CHARACTERS (the unit type), not the player
        -- frame: class colors only exist for players, NPC names are governed
        -- by the dropdown next to it. Spell that out.
        M.AddTooltip(nameModeDropdown, TrText("Player Name Color"),
            TrText("Name color for player characters on ALL frames - target, focus, party and raid included. NPC names use the setting next to this one."), { hook = true })
        M.AddTooltip(npcModeDropdown, TrText("NPC / Boss Name Color"),
            TrText("Name color for NPCs and bosses on all frames that follow the shared text settings."), { hook = true })
        M.AddTooltip(hpModeDropdown, TrText("HP Text Color"),
            TrText("HP text color mode for all frames that follow the shared text settings."), { hook = true })
        M.AddTooltip(powerModeDropdown, TrText("Power Text Color"),
            TrText("Power text color mode for all frames that follow the shared text settings."), { hook = true })
    end
    local nameCustomColor = ColorValueAt(ctx, font, "Custom name color", 12, -166,
        function()
            local g = G()
            return tonumber(g.nameColorR) or 1, tonumber(g.nameColorG) or 1, tonumber(g.nameColorB) or 1
        end,
        function(r, g2, b2)
            local g = G()
            g.nameColorR, g.nameColorG, g.nameColorB = r, g2, b2
            -- Choosing a color is the intent to use it, so the mode follows.
            if g.nameColorMode ~= "CUSTOM" then
                g.nameColorMode = "CUSTOM"
                g.nameClassColor = false
                if nameModeDropdown and nameModeDropdown.SetValue then nameModeDropdown:SetValue("CUSTOM") end
            end
            ApplySharedFontTextColors("MSUF2_NAME_CUSTOM_COLOR")
        end,
        nil, nil, Meta("font.name_custom.color"), { 1, 1, 1 })
    refreshNameCustomColor = function()
        SetControlEnabled(nameCustomColor, G().nameColorMode == "CUSTOM")
    end
    refreshNameCustomColor()
    M.TrackRefresh(ctx, refreshNameCustomColor)
    local sharedNote = W.Text(font, "Shared defaults for all frames. Per-frame and group overrides live in Fonts > Text Colors.",
        12, -212, fontW - 28, T.colors.muted)
    sharedNote:SetJustifyH("LEFT")
    local openFonts = T.Button(font, "Fonts > Text Colors", 190, 22)
    openFonts:SetPoint("TOPLEFT", font, "TOPLEFT", 12, -248)
    if T.CenterButtonLabel then T.CenterButtonLabel(openFonts) end
    if M.AddTooltip then
        M.AddTooltip(openFonts, "Fonts > Text Colors", "Open the Fonts page at its Text Colors section.", { hook = true })
    end
    openFonts:SetScript("OnClick", OpenFontsTextColors)
    RegisterControl(openFonts, Meta("font.open_text_colors", "navigation", { navigationKey = "opt_fonts" }), "Fonts > Text Colors", "button")

    -- Canonical surface for the per-indicator status text colors. Unit > Status
    -- reaches the same three keys through its ::: text shortcut only; it no longer
    -- carries a swatch of its own. Frame and indicator are picked one at a time so
    -- the eight indicators across seven frames stay a single swatch. An indicator
    -- with no stored color shows the font color it currently inherits.
    local statusText = b:CollapsibleSection("colors_status_text", "Status Text Colors", 250, false)
    local statusTextW = statusText._msuf2Width or ctx.width or 720
    local function StatusTextUnit()
        local value = tostring(M._colorsStatusTextUnit or "player")
        return M._statusTextColor.unitKeys[value] and value or "player"
    end
    local function StatusTextPrefix()
        local value = tostring(M._colorsStatusTextIndicator or "levelIndicator")
        return M._statusTextColor.prefixKeys[value] and value or "levelIndicator"
    end
    local function StatusTextConf()
        local db = DB()
        local key = StatusTextUnit()
        local conf = db[key]
        if type(conf) ~= "table" then conf = {}; db[key] = conf end
        return conf
    end
    local function ApplyStatusTextColors()
        M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false })
    end
    LabelAt(statusText, "Color for a single text indicator on one frame. Unset indicators follow that frame's font color.",
        12, -8, statusTextW - 28, "GameFontHighlightSmall", T.colors.muted)
    local statusUnitDropdown = ValueDropdownAt(ctx, statusText, "Frame", 12, -44, M._statusTextColor.units, min(260, statusTextW - 32),
        StatusTextUnit,
        function(value)
            M._colorsStatusTextUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "status-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("status_text.color.unit", "ephemeral"))
    RegisterControl(statusUnitDropdown, Meta("status_text.color.unit", "ephemeral"), "Frame", "dropdown", M._statusTextColor.units)
    local statusIndicatorDropdown = ValueDropdownAt(ctx, statusText, "Indicator", 12, -100, M._statusTextColor.indicators, min(260, statusTextW - 32),
        StatusTextPrefix,
        function(value)
            M._colorsStatusTextIndicator = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "status-text-color-indicator") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("status_text.color.indicator", "ephemeral"))
    RegisterControl(statusIndicatorDropdown, Meta("status_text.color.indicator", "ephemeral"), "Indicator", "dropdown", M._statusTextColor.indicators)
    ColorValueAt(ctx, statusText, "Text color", 12, -156,
        function()
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            local r = tonumber(conf[prefix .. "ColorR"])
            local g = tonumber(conf[prefix .. "ColorG"])
            local bcol = tonumber(conf[prefix .. "ColorB"])
            if r and g and bcol then return r, g, bcol end
            return M._ContextConfiguredGlobalFontRGB()
        end,
        function(r, g, bcol)
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = r, g, bcol
            ApplyStatusTextColors()
        end,
        nil, nil, Meta("status_text.color.value"))
    CH.ButtonAt(statusText, "Follow font color", 12, -196, 190, function()
        local conf, prefix = StatusTextConf(), StatusTextPrefix()
        conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = nil, nil, nil
        ApplyStatusTextColors()
    end, "status_text.color.reset")
    end
    if part == "font" then return end
    local tokens = GetClassTokens()
    local classRows = max(1, floor((#tokens + 3) / 4))
    local classResetY = -36 - (classRows * 36)
    local classHeight = max(190, math.abs(classResetY) + 48)
    local classColors = b:CollapsibleSection("colors_classes", "Class Bar Colors", classHeight, false)
    LabelAt(classColors, "Choose an override bar color per class.", 12, -8, 540, "GameFontHighlightSmall", T.colors.muted)
    local classW = classColors._msuf2Width or ctx.width or 720
    local classColW = max(142, floor((classW - 24) / 4))
    local classLabelW = max(76, min(112, classColW - 62))
    for i = 1, #tokens do
        local token = tokens[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        local cdr, cdg, cdb = ClassDefaultRGB(token)
        ColorValueAt(ctx, classColors, COLOR_DATA.CLASS_LABELS[token] or token, 12 + col * classColW, -34 - row * 36,
            function() return ClassColorRGB(token) end,
            function(r, g, c)
                if not ApiCall("SetClassColor", token, r, g, c) then ApplyUnitframeColorWithReload() end
            end, classLabelW, 44, Meta("class_bar.token." .. tostring(token)), { cdr, cdg, cdb })
    end
    CH.ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        if not ApiCall("ResetAllClassColors") then
            DB().classColors = nil
            ApplyUnitframeColorWithReload()
        end
    end, "class_bar.reset_all")
end

local function ApplyScopedBarGradientColors(reason)
    local apply = CurrentApplyService()
    local scope = CurrentBarsScope()
    if apply and type(apply.RequestBarGradients) == "function" then
        return apply.RequestBarGradients(reason or "MSUF2_BAR_GRADIENT_COLORS", scope)
    end
    return RequestGeneral(reason or "MSUF2_BAR_GRADIENT_COLORS", {
        preview = true,
        applyAll = false,
        notify = false,
        barGradients = true,
        barsScope = scope,
    })
end

-- Feature pages reference these semantic ids instead of duplicating Colors
-- storage or apply logic.  Resolution is click-only (see
-- W.AttachContextColorReferences), so this registry adds no combat/idle path
-- and never forces a lazy Advanced Colors category to build.
(function()
local function ContextTarget(id, label, getRGB, setRGB, opts)
    opts = opts or {}
    return {
        _msuf2ContextColorId = id,
        label = label,
        getRGB = getRGB,
        setRGB = setRGB,
        isEnabled = opts.isEnabled,
        historyLabel = opts.historyLabel or (label .. " color"),
        hasOpacity = opts.hasOpacity == true,
        getOpacity = opts.getOpacity,
        captureState = opts.captureState,
        restoreState = opts.restoreState,
    }
end
local function ContextCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[ContextCopy(key, seen)] = ContextCopy(item, seen) end
    return copy
end
local function ContextStoredState(getTable, keys, apply)
    return {
        captureState = function()
            local source, state = getTable(), {}
            for i = 1, #keys do
                local key = keys[i]
                state[i] = { key, rawget(source, key) ~= nil, ContextCopy(source[key]) }
            end
            return state
        end,
        restoreState = function(state)
            local target = getTable()
            for i = 1, #(state or {}) do
                local item = state[i]
                target[item[1]] = item[2] and ContextCopy(item[3]) or nil
            end
            if apply ~= false then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
    }
end
local function ContextDBRowsState(rowKeys, keys, apply)
    return {
        captureState = function()
            local db, state = DB(), {}
            for i = 1, #rowKeys do
                local rowKey, row = rowKeys[i], db[rowKeys[i]]
                state[i] = { rowKey, type(row) == "table", {} }
                for j = 1, #keys do
                    local key = keys[j]
                    state[i][3][j] = { key, type(row) == "table" and rawget(row, key) ~= nil, type(row) == "table" and ContextCopy(row[key]) or nil }
                end
            end
            return state
        end,
        restoreState = function(state)
            local db = DB()
            for i = 1, #(state or {}) do
                local rowState = state[i]
                local row = db[rowState[1]]
                if type(row) ~= "table" then row = {}; db[rowState[1]] = row end
                for j = 1, #(rowState[3] or {}) do
                    local item = rowState[3][j]
                    row[item[1]] = item[2] and ContextCopy(item[3]) or nil
                end
                if rowState[2] ~= true and next(row) == nil then db[rowState[1]] = nil end
            end
            if apply ~= false then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
    }
end
local function ContextStoredApi(id, label, getName, setName, prefix, dr, dg, db, da, apply, applyAfterSet)
    local keys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    if da ~= nil then keys[#keys + 1] = prefix .. "A" end
    local target = ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            local ok = ApiSetRGB(setName, r, g, b, type(a) == "number" and a or da)
            if not ok then SetGeneralRGB(prefix, r, g, b, type(a) == "number" and a or da) end
            if not ok or applyAfterSet == true then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
    if da ~= nil then
        target.hasOpacity = true
        target.getOpacity = function()
            local _, _, _, a = ApiRGB(getName, dr, dg, db)
            return tonumber(a) or da
        end
    end
    local state = ContextStoredState(G, keys, apply)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
local function ContextStoredApiScopedOpacity(id, label, getName, setName, prefix,
        dr, dg, db, da, opacityKey, opacityDefault, opacityReason)
    local scope = type(CurrentBarsScope) == "function" and CurrentBarsScope() or "shared"
    local generalState = ContextStoredState(G, {
        prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A", opacityKey,
    }, false)
    local scopedState
    local globalPage = M.GlobalPage or {}
    if scope ~= "shared" and type(globalPage.ScopeDBKeys) == "function" then
        scopedState = ContextDBRowsState(globalPage.ScopeDBKeys(scope) or {}, { opacityKey, "hlOverride" }, false)
    end
    local target = ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            if type(a) == "number" and type(globalPage.BarScopeSet) == "function" then
                globalPage.BarScopeSet(opacityKey, a, opacityReason)
                return
            end
            local _, _, _, legacyAlpha = ApiRGB(getName, dr, dg, db)
            local ok = ApiSetRGB(setName, r, g, b, tonumber(legacyAlpha) or da)
            if not ok then SetGeneralRGB(prefix, r, g, b, tonumber(legacyAlpha) or da) end
            ApplyColors()
        end,
        { hasOpacity = true })
    target.getOpacity = function()
        local fallback = tonumber(G()[opacityKey]) or opacityDefault
        if type(globalPage.BarScopeGet) == "function" then return tonumber(globalPage.BarScopeGet(opacityKey, fallback)) or fallback end
        return fallback
    end
    target.captureState = function()
        return {
            general = generalState.captureState(),
            scoped = scopedState and scopedState.captureState() or nil,
        }
    end
    target.restoreState = function(state)
        if not state then return end
        generalState.restoreState(state.general)
        if scopedState then scopedState.restoreState(state.scoped) end
        ApplyColors()
    end
    return target
end
local function ContextApi(id, label, getName, setName, dr, dg, db, apply)
    return ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            if not ApiSetRGB(setName, r, g, b, a) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
end
local function ContextApiOrGeneral(id, label, getName, setName, prefix, dr, dg, db, apply, alpha)
    return ContextTarget(id, label,
        function()
            local api = ColorAPI()
            if type(api[getName]) == "function" then return ApiRGB(getName, dr, dg, db) end
            return GeneralRGB(prefix, dr, dg, db)
        end,
        function(r, g, b, a)
            local nextAlpha = type(a) == "number" and a or alpha
            local ok = nextAlpha ~= nil and ApiCall(setName, r, g, b, nextAlpha) or ApiCall(setName, r, g, b)
            if not ok then
                SetGeneralRGB(prefix, r, g, b, nextAlpha)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
end
local function ContextGeneral(id, label, prefix, dr, dg, db, apply)
    local target = ContextTarget(id, label,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, b, a)
            SetGeneralRGB(prefix, r, g, b, a)
            if type(apply) == "function" then apply() else ApplyColors() end
        end)
    local state = ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A" }, apply)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
local function ContextTable(id, label, getTable, key, dr, dg, db, apply, opts)
    local target = ContextTarget(id, label,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, b)
            SetTableRGB(getTable(), key, r, g, b)
            if type(apply) == "function" then apply() end
        end,
        opts)
    if not target.captureState then
        local state = ContextStoredState(getTable, { key }, apply)
        target.captureState, target.restoreState = state.captureState, state.restoreState
    end
    return target
end
local function ContextGroup(id, label, prefix, dr, dg, db, alphaKey, defaultAlpha)
    local target = ContextTarget(id, label,
        function() return GroupRGB(prefix, dr, dg, db) end,
        function(r, g, b, a)
            if alphaKey then SetGroupRGBA(prefix, alphaKey, r, g, b, a, "MSUF2_GROUP_COLORS", "visual")
            else SetGroupRGB(prefix, r, g, b, "MSUF2_GROUP_COLORS", "visual") end
        end)
    local stateKeys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    if alphaKey then stateKeys[#stateKeys + 1] = alphaKey end
    local state = ContextDBRowsState(GROUP_COLOR_DB_KEYS, stateKeys, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    if alphaKey then
        target.hasOpacity = true
        target.getOpacity = function() return GroupNum(alphaKey, defaultAlpha or 1) end
    end
    return target
end
local function ContextValue(value, context)
    if type(value) == "function" then return value(context) end
    return value
end
local function ContextUnit(context)
    local unit = ContextValue(context and context.unit, context)
    return type(unit) == "string" and unit ~= "" and unit or "player"
end
local function ContextPreviewUnitData(unit)
    local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
    local data = model and model.UNIT_DATA
    return data and data[unit] or nil
end
local function ContextPlainUnitValue(api, unit)
    if type(api) ~= "function" then return nil end
    local value = api(unit)
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(value) == true then return nil end
    return value
end
local function ContextPowerToken(context)
    local token = ContextValue(context and context.powerToken, context)
    if type(token) ~= "string" or token == "" then
        local unit = ContextUnit(context)
        local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
        if exists and type(_G.UnitPowerType) == "function" then
            local _, powerToken = _G.UnitPowerType(unit)
            token = powerToken
        end
    end
    if type(token) ~= "string" or token == "" then
        local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
        local data = model and model.UNIT_DATA
        local preview = data and data[ContextUnit(context)]
        token = preview and preview.powerToken or nil
    end
    return type(token) == "string" and token ~= "" and token or "MANA"
end
local function ContextClassPowerToken(context)
    local token = ContextValue(context and context.resourceToken, context)
    if type(token) ~= "string" or token == "" then
        local spec = type(M.GetClassPowerPreviewSpec) == "function" and M.GetClassPowerPreviewSpec()
        token = type(spec) == "table" and spec.token or nil
    end
    return type(token) == "string" and token ~= "" and token or (M.colorsCPToken or "COMBO_POINTS")
end
local function ContextClassToken(context)
    local token = ContextValue(context and context.classToken, context)
    if type(token) ~= "string" or token == "" then
        if type(_G.UnitClass) == "function" then
            local _, classToken = _G.UnitClass(ContextUnit(context))
            token = classToken
        end
    end
    if type(token) ~= "string" or token == "" then
        local preview = ContextPreviewUnitData(ContextUnit(context))
        token = preview and preview.class or nil
    end
    if (type(token) ~= "string" or token == "") and type(_G.UnitClass) == "function" then
        local _, playerClass = _G.UnitClass("player")
        token = playerClass
    end
    return type(token) == "string" and token ~= "" and token or "WARRIOR"
end
local CONTEXT_COLOR_FACTORIES
local function ContextReactionKind(context)
    local kind = ContextValue(context and context.reaction, context)
    if kind == "friendly" or kind == "neutral" or kind == "enemy" or kind == "dead" then return kind end
    local unit = ContextUnit(context)
    if type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost(unit) then return "dead" end
    local reaction = type(_G.UnitReaction) == "function" and tonumber(_G.UnitReaction(unit, "player")) or nil
    if reaction and reaction >= 5 then return "friendly" end
    if reaction == 4 then return "neutral" end
    local preview = ContextPreviewUnitData(unit)
    local previewKind = preview and (preview.npcKind or preview.reactionKind)
    if type(previewKind) == "string" and previewKind ~= "" then return previewKind end
    return "enemy"
end
local function ContextClassColor(context)
    local token = ContextClassToken(context)
    local dr, dg, db = ClassDefaultRGB(token)
    local target = ContextTarget("unit.class.current", (COLOR_DATA.CLASS_LABELS[token] or token) .. " class color",
        function() return ClassColorRGB(token) end,
        function(r, g, b)
            if not ApiCall("SetClassColor", token, r, g, b) then ApplyUnitframeColorWithReload() end
        end,
        { historyLabel = "Class color" })
    local state = ContextStoredState(DB, { "classColors" }, ApplyUnitframeColorWithReload)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
local NPC_CONTEXT_DEFAULTS = {
    friendly = { 0, 1, 0 }, neutral = { 1, 1, 0 }, enemy = { 0.85, 0.10, 0.10 }, dead = { 0.40, 0.40, 0.40 },
    npcBoss = { 0.74, 0.11, 0 }, npcMiniboss = { 0.56, 0, 0.74 }, npcCaster = { 0, 0.45, 0.74 },
    npcMelee = { 0.99, 0.99, 0.99 }, npcRegular = { 0.70, 0.56, 0.33 },
}
local NPC_CONTEXT_LABELS = {
    friendly = "Friendly NPC", neutral = "Neutral NPC", enemy = "Enemy NPC", dead = "Dead NPC",
    npcBoss = "Boss NPC", npcMiniboss = "Miniboss / Lieutenant", npcCaster = "Caster NPC",
    npcMelee = "Melee NPC", npcRegular = "Regular NPC",
}
local function ContextNPCColor(kind)
    local defaults = NPC_CONTEXT_DEFAULTS[kind] or NPC_CONTEXT_DEFAULTS.enemy
    local target = ContextTarget("unit.npc." .. tostring(kind), (NPC_CONTEXT_LABELS[kind] or tostring(kind)) .. " color",
        function() return ApiRGB("GetNPCColor", defaults[1], defaults[2], defaults[3], kind) end,
        function(r, g, b)
            if not ApiCall("SetNPCColor", kind, r, g, b) then ApplyUnitframeColorWithReload() end
        end)
    local state = ContextStoredState(DB, { "npcColors" }, ApplyUnitframeColorWithReload)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
local function ContextGlobalHealthMode()
    local general = G()
    local mode = general.barMode
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
        mode = general.useClassColors and "class" or "dark"
    end
    if mode == "gradient" and general.enableHealthGradient == false then mode = "class" end
    return mode
end
local function ContextHealthMode(context)
    local mode = ContextValue(context and context.healthMode, context)
    if mode == nil then
        local conf = DB()[ContextUnit(context)]
        mode = type(conf) == "table" and conf.healthColorMode or nil
    end
    mode = type(mode) == "string" and mode or "GLOBAL"
    local upper = mode:upper()
    if upper == "GLOBAL" or upper == "" then return ContextGlobalHealthMode() end
    if upper == "GRADIENT" then return "gradient" end
    if upper == "UNIFIED" then return "unified" end
    if upper == "CLASS" then return "class" end
    return "dark"
end
local function ContextUnitKey(context)
    local key = ContextValue(context and context.unitKey, context)
    if type(key) == "string" and key ~= "" then return key end
    local unit = ContextUnit(context)
    if unit:match("^boss%d+$") then return "boss" end
    return unit
end
local function ContextNPCHealthTarget(context)
    local unit, key, general = ContextUnit(context), ContextUnitKey(context), G()
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    if preview and preview.isPlayer == true and type(preview.class) == "string" and preview.class ~= "" then
        return ContextClassColor({ unit = unit, classToken = preview.class })
    end
    if general.npcClassColorBar == true and key ~= "pet" and key ~= "boss" then
        local reaction = type(_G.UnitReaction) == "function" and _G.UnitReaction(unit, "player") or nil
        local secret = type(_G.issecretvalue) == "function" and _G.issecretvalue(reaction) == true
        if not secret and tonumber(reaction) and tonumber(reaction) >= 5 and type(_G.UnitClass) == "function" then
            local _, token = _G.UnitClass(unit)
            if type(_G.issecretvalue) ~= "function" or _G.issecretvalue(token) ~= true then
                if type(token) == "string" and token ~= "" then
                    return ContextClassColor({ unit = unit, classToken = token })
                end
            end
        end
    end

    local kind
    local common = MSUF and MSUF.UFBarTextCommon
    if exists and common and type(common.UnitNPCKind) == "function" then
        local health = {
            npcColorMode = general.npcColorMode == "type" and "type" or "reaction",
            npcTypeColorBar = general.npcTypeColorBar ~= false,
            npcTypeTarget = general.npcTypeTarget ~= false,
            npcTypeFocus = general.npcTypeFocus ~= false,
            npcTypeBoss = general.npcTypeBoss ~= false,
            npcTypeToT = general.npcTypeToT ~= false,
        }
        kind = common.UnitNPCKind(nil, unit, { key = key, health = health }, false, key)
    end
    if type(kind) ~= "string" then
        preview = preview or ContextPreviewUnitData(unit)
        kind = preview and (preview.npcKind or preview.reactionKind) or nil
    end
    return ContextNPCColor(type(kind) == "string" and kind or ContextReactionKind(context))
end

local function ContextNameColorFlags(key)
    local general, conf = G(), DB()[key]
    local classColor = general.nameClassColor == true
    local npcColor = general.npcNameRed == true
    local npcClassColor = general.nameNpcClassColor == true
    if type(conf) == "table" and conf.fontOverride == true then
        if conf.nameClassColor ~= nil then classColor = conf.nameClassColor == true end
        if conf.npcNameRed ~= nil then npcColor = conf.npcNameRed == true end
        if conf.nameNpcClassColor ~= nil then npcClassColor = conf.nameNpcClassColor == true end
    end
    -- ResolveToTInline intentionally inherits the Target frame's NPC-type text
    -- switch for TARGET_NAME, TOT_NAME and AUTO.
    local targetTypeColor = general.npcColorMode == "type" and general.npcTypeColorText ~= false
    return classColor, npcColor or targetTypeColor, npcClassColor
end

local function ContextTextNPCKind(unit, key)
    local general = G()
    local common = MSUF and MSUF.UFBarTextCommon
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local kind
    if exists and common and type(common.UnitNPCKind) == "function" then
        local text = {
            npcColorMode = general.npcColorMode == "type" and "type" or "reaction",
            npcTypeColorText = general.npcTypeColorText ~= false,
            npcTypeTarget = general.npcTypeTarget ~= false,
            npcTypeFocus = general.npcTypeFocus ~= false,
            npcTypeBoss = general.npcTypeBoss ~= false,
            npcTypeToT = general.npcTypeToT ~= false,
        }
        kind = common.UnitNPCKind(nil, unit, { key = key, text = text }, true, key)
    end
    if type(kind) ~= "string" then
        local preview = ContextPreviewUnitData(unit)
        kind = preview and (preview.npcKind or preview.reactionKind) or nil
    end
    return type(kind) == "string" and kind or ContextReactionKind({ unit = unit })
end

local function ContextNameEntityTarget(unit, key, classColor, npcColor, npcClassColor, npcKey)
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or (preview and preview.isPlayer)
    local _, classToken
    if exists and type(_G.UnitClass) == "function" then
        _, classToken = _G.UnitClass(unit)
        if type(_G.issecretvalue) == "function" and _G.issecretvalue(classToken) == true then classToken = nil end
    elseif preview then
        classToken = preview.class
    end
    if isPlayer == true then
        if classColor and type(classToken) == "string" and classToken ~= "" then
            return ContextClassColor({ unit = unit, classToken = classToken })
        end
        return CONTEXT_COLOR_FACTORIES["font.global"]()
    end
    if npcClassColor and type(classToken) == "string" and classToken ~= "" then
        return ContextClassColor({ unit = unit, classToken = classToken })
    end
    if npcColor or npcClassColor then return ContextNPCColor(ContextTextNPCKind(unit, npcKey or key)) end
    return CONTEXT_COLOR_FACTORIES["font.global"]()
end

CONTEXT_COLOR_FACTORIES = {}
local function ContextFactory(id, builder) CONTEXT_COLOR_FACTORIES[id] = builder end
local function FixedContextFactory(id, builder) ContextFactory(id, function() return builder() end) end

FixedContextFactory("bar.absorb", function()
    return ContextStoredApiScopedOpacity("bar.absorb", "Absorb", "GetAbsorbOverlayColor", "SetAbsorbOverlayColor",
        "absorbBarColor", 1, 1, 1, 0.45, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY")
end)
FixedContextFactory("bar.heal_absorb", function()
    return ContextStoredApiScopedOpacity("bar.heal_absorb", "Heal absorb", "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor",
        "healAbsorbBarColor", 0.7, 0, 0, 0.45, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY")
end)
FixedContextFactory("bar.power_background", function()
    return ContextStoredApi("bar.power_background", "Power background", "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", "powerBarBgColor", 0, 0, 0, 1, ApplyColors, true)
end)
FixedContextFactory("bar.aggro_border", function()
    local target = ContextApi("bar.aggro_border", "Aggro border", "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0)
    local state = ContextStoredState(G, {
        "hlAggroColorR", "hlAggroColorG", "hlAggroColorB",
        "aggroBorderColorR", "aggroBorderColorG", "aggroBorderColorB",
        "aggroBorderR", "aggroBorderG", "aggroBorderB",
    }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("bar.heal_prediction", function()
    return ContextGeneral("bar.heal_prediction", "Heal prediction", "healPredictionColor", 0, 1, 0, ApplyColors)
end)
FixedContextFactory("bar.health_loss", function()
    return ContextGeneral("bar.health_loss", "Health loss glow", "healthLossColor", 1, 0.55, 0.08, ApplyColors)
end)
FixedContextFactory("bar.power_loss", function()
    return ContextGeneral("bar.power_loss", "Power loss glow", "powerLossColor", 0.70, 0.90, 1, ApplyColors)
end)
FixedContextFactory("bar.purge_border", function()
    local target = ContextTarget("bar.purge_border", "Purge border",
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0) end,
        function(r, g, b) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, b) end)
    local state = ContextStoredState(G, {
        "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
        "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB",
    }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("bar.outline", function() return ContextGeneral("bar.outline", "Bar outline", "barOutlineColor", 0, 0, 0, ApplyGlobalOutlineColor) end)
FixedContextFactory("bar.background_tint", function()
    return ContextStoredApi("bar.background_tint", "Bar background tint", "GetClassBarBgColor", "SetClassBarBgColor", "classBarBg", 0, 0, 0, 1, ApplyUnitframeColorWithReload, true)
end)
FixedContextFactory("health.unified", function() return ContextGeneral("health.unified", "Unified health bar", "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload) end)
FixedContextFactory("health.gradient.low", function() return ContextGeneral("health.gradient.low", "Health gradient - low", "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload) end)
FixedContextFactory("health.gradient.mid", function() return ContextGeneral("health.gradient.mid", "Health gradient - middle", "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload) end)
FixedContextFactory("health.gradient.high", function() return ContextGeneral("health.gradient.high", "Health gradient - high", "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload) end)
ContextFactory("health.current", function(context)
    local mode = ContextHealthMode(context)
    if mode == "gradient" then
        return {
            CONTEXT_COLOR_FACTORIES["health.gradient.low"](),
            CONTEXT_COLOR_FACTORIES["health.gradient.mid"](),
            CONTEXT_COLOR_FACTORIES["health.gradient.high"](),
        }
    end
    if mode == "unified" then return CONTEXT_COLOR_FACTORIES["health.unified"]() end
    if mode == "class" then
        local unit, key = ContextUnit(context), ContextUnitKey(context)
        if key == "pet" then return CONTEXT_COLOR_FACTORIES["unit.pet"]() end
        local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
        local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or nil
        if not exists then
            local preview = ContextPreviewUnitData(unit)
            if preview and preview.isPlayer == true then
                return ContextClassColor({ unit = unit, classToken = preview.class })
            end
            return ContextNPCHealthTarget(context)
        end
        if isPlayer == false then return ContextNPCHealthTarget(context) end
        return ContextClassColor(context)
    end
    return nil
end)
ContextFactory("unit.class.current", ContextClassColor)
ContextFactory("unit.npc.current", function(context) return ContextNPCColor(ContextReactionKind(context)) end)
for _, kind in ipairs({ "friendly", "neutral", "enemy", "dead", "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }) do
    local npcKind = kind
    ContextFactory("unit.npc." .. npcKind, function() return ContextNPCColor(npcKind) end)
end
FixedContextFactory("unit.pet", function()
    local target = ContextApi("unit.pet", "Pet frame", "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
    local state = ContextStoredState(G, { "petFrameColorR", "petFrameColorG", "petFrameColorB" }, ApplyUnitframeColorWithReload)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    local setRGB = target.setRGB
    target.setRGB = function(r, g, b) setRGB(r, g, b); ApplyUnitframeColorWithReload() end
    return target
end)
FixedContextFactory("highlight.mouseover", function()
    local target = ContextTarget("highlight.mouseover", "Mouseover highlight", HighlightRGB, SetHighlightRGB)
    local state = ContextStoredState(G, { "highlightColor" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("highlight.boss_target", function()
    return ContextTable("highlight.boss_target", "Boss target highlight", G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
end)
FixedContextFactory("portrait.border", function()
    local target = ContextTarget("portrait.border", "Portrait border",
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, b) SetAllPortraitRGB("portraitBorderColor", r, g, b) end)
    local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
        { "portraitBorderColorR", "portraitBorderColorG", "portraitBorderColorB" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("portrait.background", function()
    local target = ContextTarget("portrait.background", "Portrait background",
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, b) SetAllPortraitRGB("portraitBgColor", r, g, b) end)
    local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
        { "portraitBgColorR", "portraitBgColorG", "portraitBgColorB" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
for _, texSlot in ipairs({
    { id = "texture_layer", prefix = "texLayer", label = "Texture layer" },
    { id = "texture_layer2", prefix = "texLayer2", label = "Texture layer 2" },
    { id = "texture_layer3", prefix = "texLayer3", label = "Texture layer 3" },
}) do
    local slotId, slotPrefix, slotLabel = texSlot.id, texSlot.prefix, texSlot.label
    FixedContextFactory(slotId .. ".color", function()
        local target = ContextTarget(slotId .. ".color", slotLabel,
            function() return GeneralRGB(slotPrefix .. "Color", 1, 1, 1) end,
            function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Color", r, g, b) end)
        local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
            { slotPrefix .. "ColorR", slotPrefix .. "ColorG", slotPrefix .. "ColorB" }, M._ApplyTextureLayerColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory(slotId .. ".gradient", function()
        local target = ContextTarget(slotId .. ".gradient", M.Format("%s gradient end", Tr(slotLabel)),
            function() return GeneralRGB(slotPrefix .. "Gradient2", 0, 0, 0) end,
            function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Gradient2", r, g, b) end)
        local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
            { slotPrefix .. "Gradient2R", slotPrefix .. "Gradient2G", slotPrefix .. "Gradient2B" }, M._ApplyTextureLayerColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
end
FixedContextFactory("font.global", function()
    local target = ContextTarget("font.global", "Default font", M._ContextConfiguredGlobalFontRGB,
        function(r, g, b)
            if not ApiSetRGB("SetGlobalFontColor", r, g, b) then
                local general = G()
                general.useCustomFontColor = true
                general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = r, g, b
                ApplyColors()
            end
        end)
    local state = ContextStoredState(G, { "useCustomFontColor", "fontColorCustomR", "fontColorCustomG", "fontColorCustomB" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
ContextFactory("font.default.current", function(context)
    local globalPage = M.GlobalPage or {}
    local scope = ContextValue(context and context.scope, context) or "shared"
    if type(globalPage.NormalizeScopeKey) == "function" then scope = globalPage.NormalizeScopeKey(scope) end
    local localColor = type(globalPage.IsGFScope) == "function" and globalPage.IsGFScope(scope) == true
        and type(globalPage.FontOverrideGetFor) == "function" and globalPage.FontOverrideGetFor(scope) == true
        and type(globalPage.FontScopeGetFor) == "function"
        and globalPage.FontScopeGetFor(scope, "useGlobalFontColor", true) == false
    if not localColor then return CONTEXT_COLOR_FACTORIES["font.global"]() end

    local target = ContextTarget("font.default." .. tostring(scope), "Group font color",
        function()
            return tonumber(globalPage.FontScopeGetFor(scope, "fontR", 1)) or 1,
                tonumber(globalPage.FontScopeGetFor(scope, "fontG", 1)) or 1,
                tonumber(globalPage.FontScopeGetFor(scope, "fontB", 1)) or 1
        end,
        function(r, g, b)
            globalPage.FontScopeSetFor(scope, "fontR", r, nil, nil, true)
            globalPage.FontScopeSetFor(scope, "fontG", g, nil, nil, true)
            globalPage.FontScopeSetFor(scope, "fontB", b, nil, nil, true)
            globalPage.FontScopeSetFor(scope, "useGlobalFontColor", false, nil, nil, true)
            if type(globalPage.ApplyFontsFor) == "function" then
                globalPage.ApplyFontsFor(scope, "MSUF2_CONTEXT_GROUP_FONT_COLOR")
            else
                ApplyColors()
            end
        end)
    local state = ContextDBRowsState(
        type(globalPage.ScopeDBKeys) == "function" and (globalPage.ScopeDBKeys(scope) or {}) or {},
        { "fontOverride", "fontR", "fontG", "fontB", "useGlobalFontColor" }, false)
    target.captureState = state.captureState
    target.restoreState = function(saved)
        state.restoreState(saved)
        if type(globalPage.ApplyFontsFor) == "function" then
            globalPage.ApplyFontsFor(scope, "MSUF2_CONTEXT_GROUP_FONT_RESTORE")
        else
            ApplyColors()
        end
    end
    return target
end)
ContextFactory("text.inline_tot.current", function()
    local conf = DB().targettarget or DB().tot or {}
    local mode = tostring(conf.totInlineColorMode or "AUTO"):upper()
    if mode == "DEFAULT" then return CONTEXT_COLOR_FACTORIES["font.global"]() end
    if mode == "NPC" then
        local unit = "targettarget"
        local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
        local preview = not exists and ContextPreviewUnitData(unit) or nil
        local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or (preview and preview.isPlayer)
        if isPlayer ~= false then return CONTEXT_COLOR_FACTORIES["font.global"]() end
        return ContextNPCColor(ContextTextNPCKind(unit, "targettarget"))
    end

    local unit, key
    if mode == "TARGET_NAME" then
        unit, key = "target", "target"
    else
        -- AUTO deliberately applies Target-name rules to the ToT entity;
        -- TOT_NAME instead uses the Target-of-Target frame's own name rules.
        unit, key = "targettarget", mode == "TOT_NAME" and "targettarget" or "target"
    end
    local classColor, npcColor, npcClassColor = ContextNameColorFlags(key)
    return ContextNameEntityTarget(unit, key, classColor, npcColor, npcClassColor,
        unit == "targettarget" and "targettarget" or key)
end)

local function CastApiFactory(id, label, getName, setName, prefix, dr, dg, db)
    FixedContextFactory(id, function()
        local target = ContextApi(id, label, getName, setName, dr, dg, db, ApplyCastbarColors)
        local state = ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "Color" }, ApplyCastbarColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
end
CastApiFactory("cast.interruptible", "Interruptible cast", "GetInterruptibleCastColor", "SetInterruptibleCastColor", "castbarInterruptible", 0, 0.9, 0.8)
CastApiFactory("cast.non_interruptible", "Non-interruptible cast", "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", "castbarNonInterruptible", 0.4, 0.01, 0.01)
CastApiFactory("cast.interrupt_feedback", "Interrupt feedback", "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", "castbarInterruptFeedback", 1, 0.82, 0)
CastApiFactory("cast.interrupt_unavailable", "Interrupt unavailable", "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", "castbarInterruptUnavailable", 1, 0.494117647, 0.137254902)
local function CastStoredFactory(id, label, getName, setName, defaults, keys)
    FixedContextFactory(id, function()
        local target = ContextApi(id, label, getName, setName, defaults[1], defaults[2], defaults[3], ApplyCastbarColors)
        local state = ContextStoredState(G, keys, ApplyCastbarColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
end
CastStoredFactory("cast.text", "Cast text", "GetCastbarTextColor", "SetCastbarTextColor", { 1, 1, 1 }, { "castbarFontR", "castbarFontG", "castbarFontB" })
CastStoredFactory("cast.target_text", "Cast target text", "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", { 1, 1, 1 }, { "castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB" })
CastStoredFactory("cast.player_override", "Player cast override", "GetPlayerCastbarOverrideColor", "SetPlayerCastbarOverrideColor", { 0, 0.6, 1 }, { "playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB" })
FixedContextFactory("cast.border", function()
    local target = ContextApiOrGeneral("cast.border", "Castbar border", "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, ApplyCastbarColors, 1)
    local state = ContextStoredState(G, { "castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA" }, ApplyCastbarColors)
    target.hasOpacity, target.getOpacity = true, function() local _, _, _, a = ApiRGB("GetCastbarBorderColor", 0, 0, 0); return tonumber(a) or 1 end
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("cast.background", function()
    local target = ContextApiOrGeneral("cast.background", "Castbar background", "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, ApplyCastbarColors, 0.85)
    local state = ContextStoredState(G, { "castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA" }, ApplyCastbarColors)
    target.hasOpacity, target.getOpacity = true, function() local _, _, _, a = ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10); return tonumber(a) or 0.85 end
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("cast.kick_ready", function() return ContextTable("cast.kick_ready", "Kick ready", G, "kickReadyColor", 0, 1, 0, ApplyCastbarColors) end)
FixedContextFactory("cast.kick_not_ready", function() return ContextTable("cast.kick_not_ready", "Kick not ready", G, "kickNotReadyColor", 1, 0, 0, ApplyCastbarColors) end)
-- Per-castbar detail text colors. A detail with no complete stored triple is
-- still following the shared castbar color, so the factory hands back that
-- shared target instead of a swatch whose first click would quietly create an
-- override nobody asked for. Locals stay inside this IIFE: it sits at the Lua
-- 5.1 upvalue ceiling, so the DB reach-through goes via the exported globals.
local CAST_DETAIL_PREFIX = {
    player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast",
}
local function CastDetailContextTarget(context, detail, label, sharedId)
    local unit = ContextUnit(context)
    local read = _G.MSUF_GetCastbarDetailTextColor
    local write = _G.MSUF_SetCastbarDetailTextColor
    local prefix = CAST_DETAIL_PREFIX[unit]
    if not (prefix and type(read) == "function" and type(write) == "function") then
        return CONTEXT_COLOR_FACTORIES[sharedId]()
    end
    local _, _, _, custom = read(unit, detail)
    if custom ~= true then return CONTEXT_COLOR_FACTORIES[sharedId]() end
    local key = prefix .. detail .. "Color"
    local target = ContextTarget("cast.detail." .. unit .. "." .. detail, label,
        function()
            local r, g, b = read(unit, detail)
            return r, g, b
        end,
        function(r, g, b)
            write(unit, detail, r, g, b)
            ApplyCastbarColors()
        end)
    local state = ContextStoredState(G, { key .. "R", key .. "G", key .. "B" }, ApplyCastbarColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
ContextFactory("cast.spell_text.current", function(context)
    return CastDetailContextTarget(context, "SpellName", "Cast spell text", "cast.text")
end)
ContextFactory("cast.time_text.current", function(context)
    return CastDetailContextTarget(context, "Time", "Cast time text", "cast.text")
end)
ContextFactory("cast.target_text.current", function(context)
    return CastDetailContextTarget(context, "TargetName", "Cast target text", "cast.target_text")
end)
-- Status text indicators (level/race/class/raid group and the Dead, Ghost, AFK
-- and DND states). An unset indicator follows the frame's font color, so it
-- resolves to the shared font target for the same reason as the castbar
-- details above.
ContextFactory("status.text.current", function(context)
    local unit = ContextUnit(context)
    local prefix = ContextValue(context and context.colorPrefix, context)
    local conf = type(prefix) == "string" and prefix ~= "" and DB()[unit] or nil
    if not conf then return CONTEXT_COLOR_FACTORIES["font.global"]() end
    local target = ContextTarget("status.text." .. unit .. "." .. prefix,
        ContextValue(context and context.colorLabel, context) or "Status text",
        function()
            local r = tonumber(conf[prefix .. "ColorR"])
            local g = tonumber(conf[prefix .. "ColorG"])
            local b = tonumber(conf[prefix .. "ColorB"])
            if r and g and b then return r, g, b end
            return M._ContextConfiguredGlobalFontRGB()
        end,
        function(r, g, b)
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = r, g, b
            M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false })
        end)
    local state = ContextStoredState(function() return conf end,
        { prefix .. "ColorR", prefix .. "ColorG", prefix .. "ColorB" },
        function() M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false }) end)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)

local function AuraTableFactory(id, label, key, dr, dg, db)
    FixedContextFactory(id, function() return ContextTable(id, label, G, key, dr, dg, db, ApplyAuraColors) end)
end
local function ContextDispelType(id, dispelType)
    local target = ContextTarget(id, dispelType .. " dispel",
        function() return M._GetDispelTypeRGB(dispelType, true) end,
        function(r, g, b) M._SetDispelTypeRGB(dispelType, r, g, b) end)
    local state = ContextStoredState(G, { "dispelTypeColorOverrides" }, function()
        M._SetDispelColorPreviewType(dispelType)
        ApplyAuraColors()
    end)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
FixedContextFactory("aura.cooldown.safe", function()
    local target = ContextTarget("aura.cooldown.safe", "Cooldown safe", M._ContextGetAuraSafeRGB, M._ContextSetAuraSafeRGB)
    local state = ContextStoredState(G, { "aurasCooldownTextSafeColor" }, ApplyAuraColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
AuraTableFactory("aura.cooldown.warning", "Cooldown warning", "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
AuraTableFactory("aura.cooldown.urgent", "Cooldown urgent", "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
FixedContextFactory("aura.dispel.magic", function() return ContextDispelType("aura.dispel.magic", "Magic") end)
FixedContextFactory("aura.dispel.curse", function() return ContextDispelType("aura.dispel.curse", "Curse") end)
FixedContextFactory("aura.dispel.disease", function() return ContextDispelType("aura.dispel.disease", "Disease") end)
FixedContextFactory("aura.dispel.poison", function() return ContextDispelType("aura.dispel.poison", "Poison") end)
FixedContextFactory("aura.dispel.bleed", function() return ContextDispelType("aura.dispel.bleed", "Bleed") end)

FixedContextFactory("group.health", function()
    local target = ContextTarget("group.health", "Group health bar", GroupHealthBarRGB, SetGroupHealthBarRGB)
    local state = ContextDBRowsState(GROUP_COLOR_DB_KEYS, {
        "gfDarkR", "gfDarkG", "gfDarkB", "gfUnifiedR", "gfUnifiedG", "gfUnifiedB",
        "healthCustomR", "healthCustomG", "healthCustomB",
    }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("group.background", function() return ContextGroup("group.background", "Group bar background", "bg", 0.10, 0.10, 0.10) end)
FixedContextFactory("group.dead", function() return ContextGroup("group.dead", "Dead / offline background", "deadBg", 0.60, 0.05, 0.05, "deadBgA", 0.90) end)
FixedContextFactory("group.debuff_stripe", function() return ContextGroup("group.debuff_stripe", "Debuff stripe", "debuffStripeColor", 0.80, 0.20, 0.20, "debuffStripeAlpha", 0.60) end)
FixedContextFactory("group.target", function() return ContextGroup("group.target", "Target highlight", "target", 1, 1, 1) end)
FixedContextFactory("group.focus", function() return ContextGroup("group.focus", "Focus highlight", "hlFocusColor", 0.50, 0.50, 1) end)
FixedContextFactory("group.border", function() return ContextGroup("group.border", "Group border", "groupBorder", 0.38, 0.68, 1, "groupBorderA", 0.95) end)
FixedContextFactory("group.aggro", function() return ContextGroup("group.aggro", "Corner aggro", "ciAggroColor", 1, 0.55, 0) end)
FixedContextFactory("group.portrait.border", function()
    return ContextGroup("group.portrait.border", "Party portrait border",
        "portraitBorderColor", 1, 1, 1, "portraitBorderColorA", 1)
end)

FixedContextFactory("gameplay.timer", function() return ContextTable("gameplay.timer", "Combat timer", Gameplay, "combatTimerColor", 1, 1, 1, ApplyGameplayColors) end)
FixedContextFactory("gameplay.enter", function()
    local target = ContextTarget("gameplay.enter", "Combat enter",
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, b)
            local gameplay = Gameplay()
            SetTableRGB(gameplay, "combatStateEnterColor", r, g, b)
            if gameplay.combatStateColorSync then SetTableRGB(gameplay, "combatStateLeaveColor", r, g, b) end
            ApplyGameplayColors()
        end)
    local state = ContextStoredState(Gameplay, { "combatStateEnterColor", "combatStateLeaveColor" }, ApplyGameplayColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("gameplay.leave", function()
    return ContextTable("gameplay.leave", "Combat leave", Gameplay, "combatStateLeaveColor", 0.7, 0.7, 0.7, ApplyGameplayColors, {
        isEnabled = function() return Gameplay().combatStateColorSync ~= true end,
    })
end)
FixedContextFactory("gameplay.crosshair_in", function() return ContextTable("gameplay.crosshair_in", "Crosshair in range", Gameplay, "crosshairInRangeColor", 0, 1, 0, ApplyGameplayColors) end)
FixedContextFactory("gameplay.crosshair_out", function() return ContextTable("gameplay.crosshair_out", "Crosshair out of range", Gameplay, "crosshairOutRangeColor", 1, 0, 0, ApplyGameplayColors) end)

local function PowerTokenTarget(id, token, label)
    local target = ContextTarget(id, label,
        function() return GetPowerOverrideRGB(token) end,
        function(r, g, b) SetPowerOverrideRGB(token, r, g, b) end)
    local state = ContextStoredState(G, { "powerColorOverrides" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
ContextFactory("power.current", function(context)
    local token = ContextPowerToken(context)
    return PowerTokenTarget("power.current." .. token, token, (token:gsub("_", " ")) .. " power")
end)
-- A single unit has one resource, so "power.current" resolves it from context.
-- A party or raid roster mixes every resource type at once, so group cards name
-- each color instead. Labels are spelled out rather than read from the page's
-- COLOR_POWER_TOKENS list: this registry is an IIFE sitting at 60 upvalues, and
-- reaching for one more file-level local breaks Lua 5.1's limit. They must stay
-- in sync with that list, and each entry edits the same shared override table.
local POWER_TOKEN_CONTEXT_IDS = {
    { "power.token.mana", "MANA", "Mana" },
    { "power.token.rage", "RAGE", "Rage" },
    { "power.token.energy", "ENERGY", "Energy" },
    { "power.token.focus", "FOCUS", "Focus" },
    { "power.token.runic_power", "RUNIC_POWER", "Runic Power" },
    { "power.token.insanity", "INSANITY", "Insanity" },
    { "power.token.fury", "FURY", "Fury" },
    { "power.token.pain", "PAIN", "Pain" },
    { "power.token.essence", "ESSENCE", "Essence" },
    { "power.token.lunar_power", "LUNAR_POWER", "Astral Power" },
    { "power.token.maelstrom", "MAELSTROM", "Maelstrom" },
}
for i = 1, #POWER_TOKEN_CONTEXT_IDS do
    local entry = POWER_TOKEN_CONTEXT_IDS[i]
    local id, token, label = entry[1], entry[2], entry[3]
    ContextFactory(id, function() return PowerTokenTarget(id, token, label) end)
end
ContextFactory("class_power.current", function(context)
    local token = ContextClassPowerToken(context)
    local spec = type(M.GetClassPowerPreviewSpec) == "function" and M.GetClassPowerPreviewSpec() or nil
    local slot = max(1, min(ClassPowerSlotCount(token), tonumber(ContextValue(context and context.slot, context)) or tonumber(spec and spec.value) or 1))
    local generalState = ContextStoredState(G, { "classPowerColorOverrides", "classPowerBgColorOverrides" }, false)
    local barsState = ContextStoredState(Bars, { "classPowerSlotColorModes", "classPowerComboPointColorMode", "classPowerFullColorEnabled" }, false)
    local function CaptureClassPowerState()
        return { generalState.captureState(), barsState.captureState() }
    end
    local function RestoreClassPowerState(state)
        generalState.restoreState(state and state[1]); barsState.restoreState(state and state[2]); ApplyColors()
    end
    local function ClassPowerTarget(id, label, getRGB, setRGB)
        return ContextTarget(id, label, getRGB, setRGB, {
            captureState = CaptureClassPowerState,
            restoreState = RestoreClassPowerState,
        })
    end
    local targets = {
        ClassPowerTarget("class_power.foreground." .. token, token:gsub("_", " ") .. " foreground",
            function() return GetClassPowerRGB(token) end,
            function(r, g, b) SetClassPowerRGB(token, r, g, b) end),
        ClassPowerTarget("class_power.background." .. token, token:gsub("_", " ") .. " background",
            function() return GetClassPowerBgRGB(token) end,
            function(r, g, b) SetClassPowerBgRGB(token, r, g, b) end),
    }
    if ClassPowerSlotCount(token) > 0 and ContextValue(context and context.includeSlots, context) ~= false then
        targets[#targets + 1] = ClassPowerTarget("class_power.full." .. token, token:gsub("_", " ") .. " full",
            function() return GetClassPowerFullRGB(token) end,
            function(r, g, b)
                if not ClassPowerFullColorEnabled(token) then SetClassPowerFullColorEnabled(token, true) end
                SetClassPowerRGB(ClassPowerFullColorToken(token), r, g, b)
            end)
        targets[#targets + 1] = ClassPowerTarget("class_power.slot." .. token .. "." .. tostring(slot), token:gsub("_", " ") .. " slot " .. tostring(slot),
            function() return GetClassPowerSlotRGB(token, slot) end,
            function(r, g, b)
                if GetClassPowerSlotMode(token) ~= "custom" then SetClassPowerSlotMode(token, "custom") end
                SetClassPowerRGB(ClassPowerSlotToken(token, slot), r, g, b)
            end)
    end
    return targets
end)
FixedContextFactory("class_power.text", function()
    local target = ContextTarget("class_power.text", "Class resource text",
        function() return GetClassPowerRGB("RESOURCE_TEXT") end,
        function(r, g, b) SetClassPowerRGB("RESOURCE_TEXT", r, g, b) end)
    local state = ContextStoredState(G, { "classPowerColorOverrides" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
FixedContextFactory("class_power.alt_mana", function()
    local target = ContextTarget("class_power.alt_mana", "Alternative mana",
        function() return GetClassPowerRGB("MANA") end,
        function(r, g, b) SetClassPowerRGB("MANA", r, g, b) end)
    local state = ContextStoredState(G, { "classPowerColorOverrides" }, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end)
local function ContextGradientFactory(id, label, prefix, reason)
    FixedContextFactory(id, function()
        local scope = type(CurrentBarsScope) == "function" and CurrentBarsScope() or "shared"
        if type(NormalizeScopeKey) == "function" then scope = NormalizeScopeKey(scope) end
        local rows
        if scope == "gf_raid" then rows = { "gf_raid", "gf_mythicraid" }
        elseif scope == "shared" or type(scope) ~= "string" or scope == "" then rows = { "general" }
        else rows = { scope } end
        local target = ContextTarget(id, label,
        function()
                return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
                    tonumber(GradientScopeGet(prefix .. "G", 0)) or 0,
                    tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
        end,
        function(r, g, b)
                GradientScopeSet(prefix .. "R", r); GradientScopeSet(prefix .. "G", g); GradientScopeSet(prefix .. "B", b)
                ApplyScopedBarGradientColors(reason)
        end)
        local state = ContextDBRowsState(rows, {
            prefix .. "R", prefix .. "G", prefix .. "B", "hlOverride", "gradientOverride",
            "gradientOverrideVersion", "gradientOverrideKeys",
        }, function() ApplyScopedBarGradientColors(reason) end)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
end
ContextGradientFactory("gradient.health", "Health bar gradient", "healthBarGradientColor", "MSUF2_HP_GRADIENT_COLOR")
ContextGradientFactory("gradient.power", "Power bar gradient", "powerBarGradientColor", "MSUF2_POWER_GRADIENT_COLOR")

local function AppendContextTargets(out, seen, value, reference)
    if type(value) ~= "table" then return end
    if type(value.getRGB) == "function" and type(value.setRGB) == "function" then
        if type(reference) == "table" and type(reference.label) == "string" then value.label = reference.label end
        local identity = value._msuf2ContextColorId or value
        if not seen[identity] then seen[identity] = true; out[#out + 1] = value end
        return
    end
    for i = 1, #value do AppendContextTargets(out, seen, value[i], reference) end
end
function M.ResolveContextColorReferences(references, context)
    references = ContextValue(references, context)
    context = type(context) == "table" and context or {}
    if type(references) == "string" then references = { references } end
    if type(references) ~= "table" then return {} end
    local targets, seen = {}, {}
    for i = 1, #references do
        local reference = ContextValue(references[i], context)
        local id = type(reference) == "table" and reference.id or reference
        local enabled = type(reference) ~= "table" or type(reference.when) ~= "function" or reference.when(context) ~= false
        local factory = enabled and CONTEXT_COLOR_FACTORIES[id] or nil
        if type(factory) == "function" then AppendContextTargets(targets, seen, factory(context, reference), reference) end
    end
    return targets
end
M.ContextColorReferenceFactories = CONTEXT_COLOR_FACTORIES
end)()

local function BuildBarGradientColors(ctx, b, CH)
    local values = GP.SCOPE_VALUES or {}
    local sectionW = ctx.width or 720
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, { width = sectionW })
    local scopeBottom = (scopeMetrics and scopeMetrics.bottomY) or -40
    local colorY = math.min(-104, scopeBottom - 54)
    local compact = sectionW < 560
    local resetY = compact and (colorY - 86) or (colorY - 44)
    local section = b:CollapsibleSection("colors_bar_gradients", "Bar Gradient Colors", math.abs(resetY) + 54, true)
    local scopeBar = W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = sectionW,
        getValue = CurrentBarsScope,
        setValue = function(value)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(value)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bar-gradient-color-scope")
            elseif M.Refresh then M.Refresh(ctx) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "hlOverride")
        end,
    })
    RegisterControl(scopeBar, Meta("bar_gradient.scope.selector", "ephemeral"), "Editing:", "segment", values)
    local hint = W.Text(section, "Health and Power use separate gradient colors. Choosing a color creates a custom Bars override for the selected scope.",
        14, colorY + 28, sectionW - 28, T.colors.muted)
    hint:SetJustifyH("LEFT")
    local function GradientRGB(prefix)
        return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "G", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
    end
    local function SetGradientRGB(prefix, r, g, bcol, reason)
        GradientScopeSet(prefix .. "R", r)
        GradientScopeSet(prefix .. "G", g)
        GradientScopeSet(prefix .. "B", bcol)
        ApplyScopedBarGradientColors(reason)
    end
    local powerX = compact and 14 or math.max(360, floor(sectionW * 0.50))
    local powerY = compact and (colorY - 38) or colorY
    ColorValueAt(ctx, section, "Health gradient color", 14, colorY,
        function() return GradientRGB("healthBarGradientColor") end,
        function(r, g, bcol) SetGradientRGB("healthBarGradientColor", r, g, bcol, "MSUF2_HP_GRADIENT_COLOR") end,
        compact and 180 or 190, 52, Meta("bar_gradient.health.color"), { 0, 0, 0 })
    ColorValueAt(ctx, section, "Power gradient color", powerX, powerY,
        function() return GradientRGB("powerBarGradientColor") end,
        function(r, g, bcol) SetGradientRGB("powerBarGradientColor", r, g, bcol, "MSUF2_POWER_GRADIENT_COLOR") end,
        compact and 180 or 190, 52, Meta("bar_gradient.power.color"), { 0, 0, 0 })
    CH.ButtonAt(section, "Reset gradient colors", 14, resetY, 180, function()
        GradientScopeSet("healthBarGradientColorR", 0)
        GradientScopeSet("healthBarGradientColorG", 0)
        GradientScopeSet("healthBarGradientColorB", 0)
        GradientScopeSet("powerBarGradientColorR", 0)
        GradientScopeSet("powerBarGradientColorG", 0)
        GradientScopeSet("powerBarGradientColorB", 0)
        ApplyScopedBarGradientColors("MSUF2_RESET_GRADIENT_COLORS")
    end, "bar_gradient.reset")
end

local function BuildBackgroundAndAppearance(ctx, b, CH, part)
    if part ~= "appearance" then
    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 226, false)
    LabelAt(background, "Tint applies in all bar modes, including Dark Mode.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
    LabelAt(background, "Opacity is multiplied by Unitframes > Opacity > Background. Set both to 100% for a solid background.", 12, -24, 660, "GameFontHighlightSmall", T.colors.muted)
    ApiOrGeneralColorAt(ctx, background, "Bar background tint", 12, -46, "GetClassBarBgColor", "SetClassBarBgColor", "classBarBg", 0, 0, 0, ApplyUnitframeColorWithReload)
    ValueToggleAt(ctx, background, "Background follows HP color", 12, -86,
        function() return ApiValue("GetBarBgMatchHP", function() return G().barBgMatchHPColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgMatchHP", v) then
                G().barBgMatchHPColor = v and true or false
                if v then G().barBgClassColor = false end
                ApplyUnitframeColorWithReload()
            end
        end,
        Meta("background.follow_health_color"))
    ValueToggleAt(ctx, background, "Health background follows class color", 12, -114,
        function() return ApiValue("GetBarBgClassColor", function() return G().barBgClassColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgClassColor", v) then
                G().barBgClassColor = v and true or false
                if v then G().barBgMatchHPColor = false end
                ApplyUnitframeColorWithReload()
            end
        end,
        Meta("background.follow_class_color"))
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -142,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyUnitframeColorWithReload() end,
        Meta("background.dark_mode_custom_color"))
    CH.ButtonAt(background, "Reset to black", 12, -184, 140, function()
        if not ApiCall("ResetClassBarBgColor") then
            ClearRGB(G(), "classBarBg")
            ApplyUnitframeColorWithReload()
        end
    end, "background.reset_to_black")
    end
    if part == "background" then return end
    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 290, true)
    local refreshBarModeControls
    local function CurrentBarMode()
        local g = G()
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then mode = (g.useClassColors and "class") or "dark" end
        return mode
    end
    local function SetBarMode(mode)
        local g = G()
        g.barMode = mode
        g.darkMode = (mode == "dark")
        g.useClassColors = (mode == "class")
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
        if M.RequestRefresh then M.RequestRefresh(ctx, "colors-bar-mode") end
    end
    -- Mode-first: the four coloring modes are the most consequential choice on
    -- this page, so they lead the section as one segmented card row. That row
    -- is the canonical bound control for search and Assistant automation.
    local BAR_MODE_CARDS = {
        { mode = "dark", title = "Dark Mode", desc = "Dark, neutral bars for every frame." },
        { mode = "class", title = "Class Colors", desc = "Health bars use Blizzard class colors." },
        { mode = "unified", title = "Unified", desc = "One custom color for all health bars." },
        { mode = "gradient", title = "Gradient", desc = "Bar color follows health percent (low / mid / high)." },
    }
    local appearanceW = appearance._msuf2Width or ctx.width or 720
    local modeRowW = min(appearanceW, 740) - 24
    local modeValues = {}
    for i = 1, #BAR_MODE_CARDS do
        modeValues[i] = { value = BAR_MODE_CARDS[i].mode, text = BAR_MODE_CARDS[i].title }
    end
    local modeRow = W.Segment(appearance, "Bar mode", modeValues, modeRowW)
    MoveWidget(modeRow, appearance, 12, -10, modeRowW)
    M.BindSegment(ctx, modeRow, CurrentBarMode, SetBarMode, Meta("appearance.bar_mode"))
    for i = 1, #BAR_MODE_CARDS do
        local btn = modeRow.buttons[i]
        if btn and M.AddTooltip then M.AddTooltip(btn, TrText(BAR_MODE_CARDS[i].title), TrText(BAR_MODE_CARDS[i].desc), { hook = true }) end
    end
    local modeDescLabel = LabelAt(appearance, "", 12, -64, appearanceW - 24, "GameFontHighlightSmall", T.colors.muted)
    local unifiedColor = CH.GeneralColorAt(ctx, appearance, "Unified bar color", 12, -94, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
    local darkColor = ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -136, 0, 100, 1, 300,
        function()
            local v = tonumber(G().darkBarGray)
            if not v then return 7 end
            if v <= 1 then return floor(v * 100 + 0.5) end
            return floor(v + 0.5)
        end,
        function(v)
            G().darkBarGray = (tonumber(v) or 0) / 100
            G().darkBarTone = nil
            ApplyUnitframeColorWithReload()
        end,
        Meta("appearance.dark_mode_tone"))
    local gradientStrength = SliderAt(ctx, appearance, "Gradient strength", 360, -94, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyUnitframeColorWithReload, Meta("appearance.gradient.strength"))
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -142, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end, Meta("appearance.gradient.enabled"))
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -190, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = CH.GeneralColorAt(ctx, appearance, "Low", 12, -220, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = CH.GeneralColorAt(ctx, appearance, "Mid", 170, -220, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = CH.GeneralColorAt(ctx, appearance, "High", 328, -220, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = CH.ButtonAt(appearance, "Reset gradient", 486, -220, 150, function()
        local g = G()
        g.healthGradientLowR, g.healthGradientLowG, g.healthGradientLowB = 1, 0, 0
        g.healthGradientMidR, g.healthGradientMidG, g.healthGradientMidB = 1, 1, 0
        g.healthGradientHighR, g.healthGradientHighG, g.healthGradientHighB = 0, 1, 0
        ApplyUnitframeColorWithReload()
    end, "appearance.gradient.reset")
    local gradientEditControls = { gradientStrength, gradientStopsLabel, gradientLow, gradientMid, gradientHigh, gradientReset }
    refreshBarModeControls = function()
        local mode = CurrentBarMode()
        local gradientMode = mode == "gradient"
        local gradientEnabled = gradientMode and G().enableHealthGradient ~= false
        SetControlEnabled(unifiedColor, mode == "unified")
        SetControlEnabled(darkColor, mode == "dark")
        SetControlEnabled(healthGradient, gradientMode)
        SetControlsEnabled(gradientEditControls, gradientEnabled)
        if modeRow and modeRow.SetValue then modeRow:SetValue(mode) end
        for i = 1, #BAR_MODE_CARDS do
            if BAR_MODE_CARDS[i].mode == mode and modeDescLabel and modeDescLabel.SetText then
                modeDescLabel:SetText(TrText(BAR_MODE_CARDS[i].desc))
            end
        end
    end
    M.TrackRefresh(ctx, refreshBarModeControls)
    refreshBarModeControls()
end

local function BuildUnitAndNPCColors(ctx, b, CH)
    local unit = b:CollapsibleSection("colors_unit", "Unitframe Colors", 230, false)
    for i = 1, #COLOR_DATA.NPC_ROWS do
        local row = COLOR_DATA.NPC_ROWS[i]
        NPCColorAt(ctx, unit, row, 12, -10 - (i - 1) * 36, ApplyUnitframeColorWithReload)
    end
    local petColor = CH.ApiColorAt(ctx, unit, "Pet Frame Color", 360, -10, "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
    local refreshPetColorControl
    local petPlayerClassColor = ValueToggleAt(ctx, unit, "Use player's class color for Pet Frame", 360, -54,
        function() return G().petFrameUsePlayerClassColor == true end,
        function(v)
            G().petFrameUsePlayerClassColor = v and true or false
            M.RequestUnitApply("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
            if refreshPetColorControl then refreshPetColorControl() end
        end,
        Meta("unit.pet.use_player_class_color"))
    refreshPetColorControl = function()
        SetControlEnabled(petColor, G().petFrameUsePlayerClassColor ~= true)
    end
    M.TrackRefresh(ctx, refreshPetColorControl)
    refreshPetColorControl()
    if M.AddTooltip then
        M.AddTooltip(petPlayerClassColor, "Use player's class color for Pet Frame",
            "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", { hook = true })
    end
    ValueToggleAt(ctx, unit, "Friendly NPC class colors on HP bars (Class Color mode only)", 360, -82,
        function() return ApiValue("GetNPCClassColorBar", function() return G().npcClassColorBar == true end) end,
        function(v)
            if not ApiCall("SetNPCClassColorBar", v) then
                G().npcClassColorBar = v and true or false
                ApplyUnitframeColorWithReload()
            end
        end,
        Meta("npc.class_color_bar"))
    CH.ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190,
        ResetUnitframeColors, "unitframe.reset")
    local npcType = b:CollapsibleSection("colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls = {}
    local npcMaster
    local function RefreshNPCTypeControls(enabled)
        if enabled == nil then enabled = npcMaster and npcMaster:GetChecked() and true or false end
        SetControlsEnabled(npcControls, enabled)
    end
    local function AddNPCTypeControl(control) M.AppendValues(npcControls, control); return control end
    local function AddNPCTypeToggle(label, x, y, apiGet, apiSet, key, apiArg)
        return AddNPCTypeControl(ValueToggleAt(ctx, npcType, label, x, y,
            function() return ApiValue(apiGet, function() return G()[key] ~= false end, apiArg) end,
            function(v)
                local ok
                if apiArg then ok = ApiCall(apiSet, apiArg, v) else ok = ApiCall(apiSet, v) end
                if not ok then
                    G()[key] = v and true or false
                    ApplyUnitframeColorWithReload()
                end
            end,
            Meta("npc_type.option." .. tostring(key))))
    end
    AddNPCTypeToggle("Color HP bar (Class Color mode only)", 32, -38, "GetNPCTypeColorBar", "SetNPCTypeColorBar", "npcTypeColorBar")
    AddNPCTypeToggle("Color name text", 32, -62, "GetNPCTypeColorText", "SetNPCTypeColorText", "npcTypeColorText")
    npcMaster = ValueSwitchAt(ctx, npcType, "NPC Type Colors", 12, -10, 260,
        function()
            return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type"
        end,
        function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then
                G().npcColorMode = v and "type" or "reaction"
                ApplyUnitframeColorWithReload()
            end
            RefreshNPCTypeControls(v and true or false)
        end,
        Meta("npc_type.enabled"))
    local units = GetNPCTypeUnits()
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    for i = 1, #units do
        local info = units[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        AddNPCTypeToggle(info.label or info.key, 32 + col * 180, -114 - row * 24, "GetNPCTypePerUnit", "SetNPCTypePerUnit", info.key, info.key)
    end
    for i = 1, #COLOR_DATA.NPC_TYPE_ROWS do
        local row = COLOR_DATA.NPC_TYPE_ROWS[i]
        local col = (i - 1) % 2
        local line = floor((i - 1) / 2)
        AddNPCTypeControl(NPCColorAt(ctx, npcType, row, 12 + col * 330, -174 - line * 38, ApplyUnitframeColorWithReload))
    end
    CH.ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190,
        function() ResetNPCColors("ResetNPCTypeColors") end, "npc_type.reset")
    M.TrackRefresh(ctx, RefreshNPCTypeControls)
end

-- Colors that write one shared setting used by unit AND group frames get a
-- small inline tag so the duplication reads as intentional, not as two
-- separate settings.
local function MarkSharedColor(control)
    if not control then return end
    local tag = T.Font(control, "GameFontDisableSmall", TrText("Shared with group frames"), T.colors.muted)
    tag:SetPoint("LEFT", control, "RIGHT", 8, 0)
    control._msuf2SharedColorTag = tag
end
local function BuildBarAndGroupColors(ctx, b, CH, includeGroup)
    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar & Prediction Colors", 280, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    local barColorControls = CH.ApiColorSpecs(ctx, barColors, {
        { "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1 },
        { "Heal-Absorb / Negative Heal", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0 },
        { "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0, nil, nil, nil, "powerBg" },
        { "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0 },
    })
    local powerBg = barColorControls.powerBg
    MarkSharedColor(barColorControls.SetAbsorbOverlayColor)
    MarkSharedColor(barColorControls.SetHealAbsorbOverlayColor)
    local healPredictionColor = ColorValueAt(ctx, barColors, "Positive Heal Prediction", barLeftX, -146,
        function() return GeneralRGB("healPredictionColor", 0, 1, 0) end,
        function(r, g, c)
            local general = G()
            general.healPredictionColorR, general.healPredictionColorG, general.healPredictionColorB = r, g, c
            ApplyColors()
        end,
        nil, nil, Meta("prediction.heal_color"), { 0, 1, 0 })
    MarkSharedColor(healPredictionColor)
    ColorValueAt(ctx, barColors, "Health loss glow", barLeftX, -182,
        function() return GeneralRGB("healthLossColor", 1, 0.55, 0.08) end,
        function(r, g, c)
            SetGeneralRGB("healthLossColor", r, g, c)
            ApplyColors()
        end,
        nil, nil, Meta("bar.health_loss_color"), { 1, 0.55, 0.08 })
    ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end,
        nil, nil, Meta("bar.purge_border_color"), { 1.00, 0.85, 0.00 })
    ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end,
        nil, nil, Meta("bar.outline_color"), { 0, 0, 0 })
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Power background matches HP", barRightX, -148,
        function() return ApiValue("GetPowerBarBackgroundMatchHP", function() return G().powerBarBgMatchBarColor == true end) end,
        function(v)
            if not ApiCall("SetPowerBarBackgroundMatchHP", v) then
                G().powerBarBgMatchBarColor = v and true or false
                ApplyColors()
            end
            SetControlEnabled(powerBg, not (v and true or false))
        end,
        Meta("bar.power_background_match_health"))
    ColorValueAt(ctx, barColors, "Power loss glow", barRightX, -182,
        function() return GeneralRGB("powerLossColor", 0.70, 0.90, 1) end,
        function(r, g, c)
            SetGeneralRGB("powerLossColor", r, g, c)
            ApplyColors()
        end,
        nil, nil, Meta("bar.power_loss_color"), { 0.70, 0.90, 1 })
    CH.ButtonAt(barColors, "Reset Bar Colors", barLeftX, -234, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        ClearRGB(g, "healPredictionColor")
        ClearRGB(g, "healthLossColor")
        ClearRGB(g, "powerLossColor")
        g.barOutlineColorMode = nil
        ClearRGBs(g, "hlAggroColor", "hlPurgeColor", "aggroBorderColor")
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end, "bar.reset")
    M.BindGateGroup(ctx, nil, {
        { controls = powerBg, on = function() return not (powerBgMatch:GetChecked() and true or false) end },
    })
    if includeGroup ~= false then BuildGroupFrameColors(ctx, b) end
end

local function BuildCastbarColors(ctx, b, CH)
    local castbar = b:CollapsibleSection("colors_castbar", "Castbar Colors", 580, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    CH.ApiColorSpecs(ctx, castbar, {
        { "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8 },
        { "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01 },
        { "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0 },
        { "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1 },
        { "Cast Target Name Color", 360, -118, "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1 },
    }, ApplyCastbarColors)
    CH.ApiOrGeneralColorSpecs(ctx, castbar, {
        { "Castbar border color", 360, -46, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, nil, 1 },
        { "Castbar background color", 360, -82, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, nil, 0.85 },
    }, ApplyCastbarColors)
    LabelAt(castbar, "Player castbar override", 12, -170, 260, "GameFontNormal", T.colors.text)
    local overrideModeX, overrideModeW = 300, 190
    local overrideColorX = min(max(overrideModeX + overrideModeW + 36, floor(castW * 0.56)), castW - 236)
    local overrideColorLabelW = max(120, min(168, castW - overrideColorX - 76))
    local overrideColorY = -190
    if overrideColorX < overrideModeX + overrideModeW + 24 then
        overrideColorX = overrideModeX
        overrideColorY = -246
        overrideColorLabelW = max(120, min(230, castW - overrideColorX - 76))
    end
    local overrideColor = ColorValueAt(ctx, castbar, "Custom color", overrideColorX, overrideColorY,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c)
            if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c) then ApplyCastbarColors() end
        end,
        overrideColorLabelW, nil, Meta("castbar.player_override.custom_color"), { 0, 0.6, 1 })
    local overrideEnable
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", overrideModeX, -190, ValueTextPairs "CLASS=Class color|CUSTOM=Custom color", overrideModeW,
        function() return ApiValue("GetPlayerCastbarOverrideMode", function() return G().playerCastbarOverrideMode or "CLASS" end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideMode", v) then
                G().playerCastbarOverrideMode = v
                ApplyCastbarColors()
            end
            SetControlEnabled(overrideColor, (overrideEnable and overrideEnable:GetChecked() and true or false) and v == "CUSTOM")
        end,
        Meta("castbar.player_override.mode"))
    local function RefreshCastbarOverrideControls(enabled)
        if enabled == nil then enabled = overrideEnable and overrideEnable:GetChecked() and true or false end
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end
    overrideEnable = ValueSwitchAt(ctx, castbar, "Player override", 12, -190, 260,
        function() return ApiValue("GetPlayerCastbarOverrideEnabled", function() return G().playerCastbarOverrideEnabled == true end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideEnabled", v) then
                G().playerCastbarOverrideEnabled = v and true or false
                ApplyCastbarColors()
            end
            RefreshCastbarOverrideControls(v and true or false)
        end,
        Meta("castbar.player_override.enabled"))
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -280, 260, "GameFontNormal", T.colors.text)
    CH.TableColorSpecs(ctx, castbar, G, {
        { "Ready color (kick available)", 12, -310, "kickReadyColor", 0, 1, 0 },
        { "Not ready color (kick on cooldown)", 12, -346, "kickNotReadyColor", 1, 0, 0 },
    }, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Unavailable fill color", 12, -382, "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1.0, 0.494117647, 0.137254902, ApplyCastbarColors)
    CH.ButtonAt(castbar, "Reset castbar colors", 12, -506, 170, function()
        local apiOwnsRefresh = ApiCall("ResetCastbarTextColorToGlobal")
        apiOwnsRefresh = ApiCall("ResetCastbarTargetNameColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBorderColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBackgroundColor") or apiOwnsRefresh
        local g = G()
        ClearRGBs(g, "castbarInterruptible", "castbarNonInterruptible", "castbarInterruptFeedback", "castbarInterruptUnavailable")
        ClearRGB(g, "castbarTargetName")
        g.castbarInterruptUnavailableColor = nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        ClearRGB(g, "playerCastbarOverride")
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        if not apiOwnsRefresh then ApplyCastbarColors() end
    end, "castbar.reset")
    M.TrackRefresh(ctx, RefreshCastbarOverrideControls)

    -- Canonical surface for the per-castbar text colors that the Unit > Castbar
    -- cards also expose. One castbar is edited at a time so four units stay
    -- three swatches instead of twelve. An unset detail shows the shared castbar
    -- text color it is currently inheriting; the reset button restores that.
    local detail = b:CollapsibleSection("colors_castbar_text", "Castbar Text Colors", 280, false)
    local detailW = detail._msuf2Width or ctx.width or 720
    local function DetailUnit()
        local value = tostring(M._colorsCastbarDetailUnit or "player")
        if value == "target" or value == "focus" or value == "boss" then return value end
        return "player"
    end
    local function DetailRGB(suffix)
        local read = _G.MSUF_GetCastbarDetailTextColor
        if type(read) == "function" then
            local r, g, bcol, custom = read(DetailUnit(), suffix)
            if custom == true then return r, g, bcol end
        end
        return ApiRGB("GetCastbarTextColor", 1, 1, 1)
    end
    local function SetDetailRGB(suffix, r, g, bcol)
        local write = _G.MSUF_SetCastbarDetailTextColor
        if type(write) == "function" then write(DetailUnit(), suffix, r, g, bcol) end
        ApplyCastbarColors()
    end
    LabelAt(detail, "Each castbar text can override the shared castbar text color. Target text exists on Target and Focus only.",
        12, -8, detailW - 28, "GameFontHighlightSmall", T.colors.muted)
    local detailUnitDropdown = ValueDropdownAt(ctx, detail, "Editing:", 12, -44,
        ValueTextPairs "player=Player|target=Target|focus=Focus|boss=Boss", min(260, detailW - 32),
        DetailUnit,
        function(value)
            M._colorsCastbarDetailUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "castbar-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("castbar.text_color.unit", "ephemeral"))
    RegisterControl(detailUnitDropdown, Meta("castbar.text_color.unit", "ephemeral"), "Editing:", "dropdown")
    ColorValueAt(ctx, detail, "Spell text color", 12, -100,
        function() return DetailRGB("SpellName") end,
        function(r, g, bcol) SetDetailRGB("SpellName", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.spell_name"))
    ColorValueAt(ctx, detail, "Cast time color", 12, -136,
        function() return DetailRGB("Time") end,
        function(r, g, bcol) SetDetailRGB("Time", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.time"))
    local detailTargetColor = ColorValueAt(ctx, detail, "Target text color", 12, -172,
        function() return DetailRGB("TargetName") end,
        function(r, g, bcol) SetDetailRGB("TargetName", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.target_name"))
    CH.ButtonAt(detail, "Follow shared color", 12, -218, 190, function()
        local reset = _G.MSUF_ResetCastbarDetailTextColor
        if type(reset) ~= "function" then return end
        local castUnit = DetailUnit()
        reset(castUnit, "SpellName")
        reset(castUnit, "Time")
        reset(castUnit, "TargetName")
        ApplyCastbarColors()
    end, "castbar.text_color.reset")
    M.TrackRefresh(ctx, function()
        SetControlEnabled(detailTargetColor, DetailUnit() == "target" or DetailUnit() == "focus")
    end)
end

local function BuildHighlightAndGameplayColors(ctx, b, CH, part)
    if part ~= "gameplay" then
    local highlight = b:CollapsibleSection("colors_highlight", "Highlight Colors", 154, false)
    ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -10, HighlightRGB, SetHighlightRGB,
        nil, nil, Meta("highlight.mouseover.color"), { 1, 1, 1 })
    CH.TableColorAt(ctx, highlight, "Boss target highlight color", 12, -66, G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
    -- Texture layers: each slot's swatch pair writes the general baseline plus
    -- every unit's per-frame copy (portrait pattern); the unit accordions link
    -- here via context color references instead of hosting swatches.
    local texLayer = b:CollapsibleSection("colors_texture_layer", "Texture Layer Colors", 340, false)
    for texIndex, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", suffix = "" },
        { id = "texture_layer2", prefix = "texLayer2", suffix = " 2" },
        { id = "texture_layer3", prefix = "texLayer3", suffix = " 3" },
    }) do
        local rowY = -10 - (texIndex - 1) * 108
        local slotPrefix = texSlot.prefix
        ColorValueAt(ctx, texLayer, M.Tr("Texture layer color") .. texSlot.suffix, 12, rowY,
            function() return GeneralRGB(slotPrefix .. "Color", 1, 1, 1) end,
            function(r, g, c) M._SetAllTextureLayerRGB(slotPrefix .. "Color", r, g, c) end,
            nil, nil, Meta(texSlot.id .. ".color"), { 1, 1, 1 })
        ColorValueAt(ctx, texLayer, M.Tr("Texture layer gradient end") .. texSlot.suffix, 12, rowY - 36,
            function() return GeneralRGB(slotPrefix .. "Gradient2", 0, 0, 0) end,
            function(r, g, c) M._SetAllTextureLayerRGB(slotPrefix .. "Gradient2", r, g, c) end,
            nil, nil, Meta(texSlot.id .. ".gradient_color"), { 0, 0, 0 })
    end
    end
    if part == "highlight" then return end
    local gameplay = b:CollapsibleSection("colors_gameplay", "Combat Feedback", 310, false)
    CH.TableColorSpecs(ctx, gameplay, Gameplay, {
        { "Combat timer text color", 12, -10, "combatTimerColor", 1, 1, 1 },
    }, ApplyGameplayColors)
    ColorValueAt(ctx, gameplay, "Combat Enter text color", 12, -46,
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, c)
            local gp = Gameplay()
            SetTableRGB(gp, "combatStateEnterColor", r, g, c)
            if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
            ApplyGameplayColors()
        end,
        nil, nil, Meta("gameplay.combat_enter_color"), { 1, 1, 1 })
    local gameplayColors = CH.TableColorSpecs(ctx, gameplay, Gameplay, {
        { "Combat Leave text color", 12, -82, "combatStateLeaveColor", 0.7, 0.7, 0.7 },
        { "Crosshair in-range color", 12, -142, "crosshairInRangeColor", 0, 1, 0 },
        { "Crosshair out-of-range color", 12, -178, "crosshairOutRangeColor", 1, 0, 0 },
    }, ApplyGameplayColors)
    local leaveColor = gameplayColors.combatStateLeaveColor
    local sync = BindTableToggle(ctx, gameplay, "Sync", Gameplay, "combatStateColorSync", false, function()
        local gp = Gameplay()
        if gp.combatStateColorSync then
            local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
            SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
        end
        ApplyGameplayColors()
        SetControlEnabled(leaveColor, not (gp.combatStateColorSync == true))
    end,
    Meta("gameplay.combat_state_color_sync"))
    MoveWidget(sync, gameplay, 360, -82)
    CH.ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors()
    end, "gameplay.reset")
    M.BindGateGroup(ctx, nil, {
        { controls = leaveColor, on = function() return not (Gameplay().combatStateColorSync == true) end },
    })
end

-- The painter paints through the real bound controls of the sections below
-- (each section's color-context owner list), so every color has exactly one
-- source of truth. This shared spec drives the painter tabs, the description
-- line under them AND the headline above the filtered section list, so users
-- see that one tab controls both.
local COLOR_PAINTER_CATEGORIES = {
    { key = "unit", title = "Player & Target Frames", shortTitle = "Player & Target",
        subtitle = "Bars, text, portraits, NPC colors and combat feedback for unit frames.",
        pickerNote = "HP, name and power text share Font Coloring and remain editable here." },
    { key = "group", title = "Party & Raid Frames", shortTitle = "Party & Raid",
        subtitle = "Shared by Party, Raid and Mythic Raid.",
        pickerNote = "Shared by Party, Raid and Mythic Raid." },
    { key = "cast", title = "Castbars", shortTitle = "Castbar",
        subtitle = "Interrupt states, text, border and kick feedback.",
        pickerNote = "Cast states, feedback, text, border and background." },
    { key = "auras", title = "Auras & Icons", shortTitle = "Auras",
        subtitle = "Cooldown timer urgency, global Dispel types, icon borders and shadows.",
        pickerNote = "Safe, Warning, Urgent, Magic, Curse, Disease, Poison, Bleed, icon border and icon shadow." },
    { key = "resources", title = "Power & Class Resources", shortTitle = "Resources",
        subtitle = "Power bar colors and Class Resource colors (combo points, holy power, ...).",
        pickerNote = "Power and Class Resource colors." },
}
local function TokenText(list, value)
    for i = 1, #(list or {}) do
        local item = list[i]
        if item.value == value then return item.text or tostring(value) end
    end
    return tostring(value or "")
end
-- The Resources tab renders a menu-only preview strip instead of the live unit
-- frames: it must follow the Power type / Resource type dropdown selection,
-- which the player's real frames cannot show for foreign classes.
local COLOR_RESOURCES_CATEGORY
for i = 1, #COLOR_PAINTER_CATEGORIES do
    if COLOR_PAINTER_CATEGORIES[i].key == "resources" then COLOR_RESOURCES_CATEGORY = COLOR_PAINTER_CATEGORIES[i] end
end
COLOR_RESOURCES_CATEGORY.preview = {
    powerLabel = function() return TokenText(COLOR_POWER_TOKENS, M.colorsPowerToken or "MANA") end,
    power = function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
    powerBg = function() return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0) end,
    resourceLabel = function() return TokenText(COLOR_CP_TOKENS, M.colorsCPToken or "COMBO_POINTS") end,
    resource = function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
    resourceBg = function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
    slotCount = function() return ClassPowerSlotCount(M.colorsCPToken or "COMBO_POINTS") end,
    slot = function(i) return GetClassPowerSlotRGB(M.colorsCPToken or "COMBO_POINTS", i) end,
    fullEnabled = function() return ClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS") end,
    full = function() return GetClassPowerFullRGB(M.colorsCPToken or "COMBO_POINTS") end,
}
local function BuildColorPainter(ctx, b)
    local painter = M.ColorPainter
    if not (painter and type(painter.Build) == "function") then return end
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    painter.Build(ctx, b, COLOR_PAINTER_CATEGORIES)
end

-- One taxonomy: the painter tabs above decide which category of sections is
-- visible below the preview. Every legacy section id survives unchanged inside
-- its category, so search keywords, Assistant metadata and cross-page focus
-- requests keep working. Categories build lazily on first activation; hidden
-- (coverage/audit) builds materialize everything, matching the old groups.
local COLOR_CATEGORY_ORDER = { "unit", "group", "cast", "auras", "resources" }
local COLOR_CATEGORY_SECTIONS = {
    unit = { "colors_appearance", "colors_bar_colors", "colors_bar_gradients", "colors_background",
        "colors_font", "colors_classes", "colors_unit", "colors_npc_type", "colors_highlight",
        "colors_texture_layer", "colors_gameplay", "colors_portrait", "colors_status_text" },
    group = { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state", "colors_group_frames_highlights" },
    cast = { "colors_castbar", "colors_castbar_text" },
    auras = { "colors_auras" },
    resources = { "colors_power", "colors_class_power" },
}
local COLOR_SECTION_CATEGORY = {}
for categoryKey, sectionIds in pairs(COLOR_CATEGORY_SECTIONS) do
    for i = 1, #sectionIds do COLOR_SECTION_CATEGORY[sectionIds[i]] = categoryKey end
end

-- A category builder may return a continuation function (which may return
-- another one): EnsureCategoryBuilt runs the first slice synchronously and the
-- continuations on following short ticks. The unit category is the default
-- Colors entry view and was the single largest chunk of the entry frame; its
-- later stages hold only default-collapsed sections, so they can fill in
-- below the visible content without moving anything the user already sees.
local COLOR_CATEGORY_BUILDERS = {
    unit = function(ctx, inner, CH)
        BuildBackgroundAndAppearance(ctx, inner, CH, "appearance")
        BuildBarAndGroupColors(ctx, inner, CH, false)
        BuildBarGradientColors(ctx, inner, CH)
        return function()
            BuildBackgroundAndAppearance(ctx, inner, CH, "background")
            BuildFontAndClassColors(ctx, inner, CH)
            return function()
                BuildUnitAndNPCColors(ctx, inner, CH)
                BuildHighlightAndGameplayColors(ctx, inner, CH)
                BuildAuraAndPortraitColors(ctx, inner, CH, "portrait")
            end
        end
    end,
    group = function(ctx, inner)
        BuildGroupFrameColors(ctx, inner)
    end,
    cast = function(ctx, inner, CH)
        BuildCastbarColors(ctx, inner, CH)
    end,
    auras = function(ctx, inner, CH)
        BuildAuraAndPortraitColors(ctx, inner, CH, "auras")
    end,
    resources = function(ctx, inner, CH)
        BuildPowerAndClassPowerColors(ctx, inner, CH)
    end,
}

local function PendingColorFocusCategory(ctx)
    local request = _G.MSUF_EM2_MenuFocusRequest
    if type(request) ~= "table" or request.explicit ~= true or request.consumed == true then return nil end
    if request.pageKey and tostring(request.pageKey) ~= tostring(ctx and ctx.key or "") then return nil end
    return COLOR_SECTION_CATEGORY[tostring(request.sectionId or "")]
end

local function BuildColors(ctx)
    if ctx and ctx.wrapper then ctx.wrapper._msuf2SuppressContextColorShortcuts = true end
    local b, CH = W.PageBuilder(ctx), COLOR_HELPERS
    -- Painter callbacks from a previous build of this page must never fire
    -- into stale closures while this build is in progress.
    M.ColorsOnPainterCategory = nil
    M.ColorsSetPainterCategory = nil
    M.ColorsEnsureCategoryBuilt = nil
    b:GlobalStyleHeader("Colors", "Frame, group-frame, bar, aura, castbar and resource colors.", 72)
    BuildColorPainter(ctx, b)

    if not b._collapsibleStartY then b._collapsibleStartY = b.y end
    local host = CreateFrame("Frame", nil, b.parent)
    host:SetSize(b.width, 1)
    host:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    local hostEntry = { kind = "section", frame = host, height = 1, gap = 12 }
    b.layoutEntries[#b.layoutEntries + 1] = hostEntry
    b.y = b.y - 1 - 12

    local categories = {}
    for i = 1, #COLOR_CATEGORY_ORDER do
        local categoryKey = COLOR_CATEGORY_ORDER[i]
        local container = CreateFrame("Frame", nil, host)
        container:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        container:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        container:SetHeight(1)
        container:Hide()
        categories[categoryKey] = { key = categoryKey, container = container, height = 1 }
    end

    local activeKey
    local function UpdateHostHeight()
        local active = categories[activeKey]
        local height = max(1, tonumber(active and active.height) or 1)
        hostEntry.height = height
        if host:GetHeight() ~= height then host:SetHeight(height) end
        b:RequestRelayoutCollapsibles()
    end
    local ActivateCategory
    local function EnsureCategoryBuilt(categoryKey)
        local category = categories[categoryKey]
        if not category or category.built then return category end
        if category.building then
            local resume = category.resumeStage
            if resume then
                category.resumeStage = nil
                resume()
            end
            return category
        end
        category.building = true
        local refreshers = ctx and ctx.refreshers
        local inner = W.PageBuilder(ctx, {
            parent = category.container,
            width = b.width,
            contentX = 0,
            topInset = 0,
            onContentHeight = function(height)
                height = max(1, tonumber(height) or 1)
                if category.height == height then return end
                category.height = height
                if activeKey == categoryKey then UpdateHostHeight() end
            end,
        })
        local function FinishCategoryBuild()
            category.built = true
            category.building = nil
            for i = 1, #inner.collapsibles do
                local sectionEntry = inner.collapsibles[i]
                sectionEntry._msuf2EnsureVisible = function()
                    if type(M.ColorsSetPainterCategory) == "function" then
                        M.ColorsSetPainterCategory(categoryKey)
                    elseif ActivateCategory then
                        ActivateCategory(categoryKey)
                    end
                end
            end
        end
        -- A builder may return a continuation (which may return another one):
        -- later stages run on short ticks so the entry frame only pays for the
        -- first slice. Without a timer every stage runs inline, so tests and
        -- degraded clients keep the old fully synchronous behavior.
        local function RunCategoryStage(stage)
            local refreshStart = type(refreshers) == "table" and #refreshers or 0
            local wasBuilding = ctx and ctx._msuf2Building
            if ctx then ctx._msuf2Building = true end
            local previousBuildKey = M._msuf2SearchBuildKey
            if ctx and ctx.key then M._msuf2SearchBuildKey = ctx.key end
            local stageOK, nextStage = pcall(stage, ctx, inner, CH)
            M._msuf2SearchBuildKey = previousBuildKey
            if ctx then ctx._msuf2Building = wasBuilding end
            if not stageOK then
                category.building = nil
                category.resumeStage = nil
                error(nextStage, 0)
            end
            inner:RelayoutCollapsibles()
            if not wasBuilding and type(refreshers) == "table" then
                for i = refreshStart + 1, #refreshers do
                    local refresh = refreshers[i]
                    if type(refresh) == "function" then refresh() end
                end
                -- The current outer relayout reads the updated host height after
                -- this callback, so its pending marker has already been satisfied.
                b._msuf2RelayoutPending = nil
            end
            if type(nextStage) == "function" then
                if C_Timer and type(C_Timer.After) == "function" then
                    -- Combat quiescence may cancel the tracked timer; the
                    -- resume hook lets the next EnsureCategoryBuilt call pick
                    -- the build back up instead of leaving it half-finished.
                    category.resumeStage = function() RunCategoryStage(nextStage) end
                    C_Timer.After(0.02, function()
                        if categories[categoryKey] ~= category or category.resumeStage == nil then return end
                        category.resumeStage = nil
                        RunCategoryStage(nextStage)
                    end)
                    return
                end
                return RunCategoryStage(nextStage)
            end
            FinishCategoryBuild()
        end
        RunCategoryStage(COLOR_CATEGORY_BUILDERS[categoryKey])
        return category
    end
    ActivateCategory = function(categoryKey)
        if not categories[categoryKey] then categoryKey = COLOR_CATEGORY_ORDER[1] end
        EnsureCategoryBuilt(categoryKey)
        activeKey = categoryKey
        -- Cached page/search/pin lifecycles can leave a locally hidden active
        -- container behind.  Reconcile every time, including same-category
        -- activation, instead of relying on the key having changed.
        if host.Show then host:Show() end
        for key, category in pairs(categories) do
            category.container:SetShown(key == categoryKey)
        end
        UpdateHostHeight()
    end
    M.ColorsOnPainterCategory = ActivateCategory
    M.ColorsEnsureCategoryBuilt = function(sectionId)
        local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
        if categoryKey then EnsureCategoryBuilt(categoryKey) end
    end
    if ctx.entry then
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
            if not categoryKey then return nil end
            if type(M.ColorsSetPainterCategory) == "function" then
                M.ColorsSetPainterCategory(categoryKey)
            else
                ActivateCategory(categoryKey)
            end
            local sections = ctx.entry.sections
            return sections and sections[tostring(sectionId)]
        end
    end
    if ctx.hiddenBuild then
        for i = 1, #COLOR_CATEGORY_ORDER do EnsureCategoryBuilt(COLOR_CATEGORY_ORDER[i]) end
    end
    local initialKey = PendingColorFocusCategory(ctx)
    if not initialKey then
        local persisted = M.colorsPainterCategory
        initialKey = categories[persisted] and persisted or COLOR_CATEGORY_ORDER[1]
    end
    if type(M.ColorsSetPainterCategory) == "function" then
        M.ColorsSetPainterCategory(initialKey)
    end
    ActivateCategory(initialKey)
    b:RelayoutCollapsibles()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 21 })
