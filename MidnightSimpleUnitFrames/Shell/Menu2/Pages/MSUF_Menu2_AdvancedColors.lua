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
    ["auras.color.aurasOwnBuffHighlightColor"] = "general.aurasOwnBuffHighlightColor",
    ["auras.color.aurasOwnDebuffHighlightColor"] = "general.aurasOwnDebuffHighlightColor",
    ["auras.color.aurasStackCountColor"] = "general.aurasStackCountColor",
    ["auras.cooldown.color_by_time"] = "general.aurasCooldownTextUseBuckets",
    ["auras.cooldown.safe_seconds"] = "general.aurasCooldownTextSafeSeconds",
    ["auras.cooldown.urgent_seconds"] = "general.aurasCooldownTextUrgentSeconds",
    ["auras.cooldown.warning_seconds"] = "general.aurasCooldownTextWarningSeconds",
    ["auras.pandemic_window.color"] = "auras3.shared.pandemicColor",
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
    ["highlight.mouseover.enabled"] = "general.highlightEnabled",
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
local function PrefixedSettingKeys(prefix, tokens)
    local keys = {}
    for token in tostring(tokens or ""):gmatch("%S+") do keys[#keys + 1] = prefix .. token end
    return keys
end
local COLOR_DYNAMIC_SETTING_KEYS_BY_PATH = {
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
    ["power.editor.color"] = PrefixedSettingKeys("general.powerColorOverrides.",
        "MANA RAGE ENERGY FOCUS RUNIC_POWER INSANITY FURY PAIN ESSENCE LUNAR_POWER MAELSTROM"),
    ["class_power.editor.foreground_color"] = PrefixedSettingKeys("general.classPowerColorOverrides.",
        [[COMBO_POINTS HOLY_POWER SOUL_SHARDS CHI ARCANE_CHARGES RUNES ESSENCE CHARGED
           SOUL_FRAGMENTS SOUL_FRAGMENTS_META MAELSTROM MAELSTROM_ABOVE_5 ASTRAL_POWER AP_PREDICTION
           ECLIPSE_SOLAR ECLIPSE_LUNAR ECLIPSE_CA STAGGER_GREEN STAGGER_YELLOW STAGGER_RED
           SOUL_FRAGMENTS_VENG INSANITY MAELSTROM_POWER WHIRLWIND TIP_OF_THE_SPEAR ICICLES EBON_MIGHT
           RESOURCE_TEXT]]),
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
}
local function ColorReviewedDisposition(path)
    if path:match("^bar_gradient%.") then
        return "dynamic", "This color targets the explicit Bars scope shared with the Health and Power gradient controls."
    end
    if path == "prediction.heal_color" then
        return "dynamic", "This RGB swatch writes the three persisted heal-prediction color channels as one visible color."
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
local COLOR_CP_TOKENS = ValueTextPairs [[COMBO_POINTS=Combo Points|HOLY_POWER=Holy Power|SOUL_SHARDS=Soul Shards|CHI=Chi|ARCANE_CHARGES=Arcane Charges|RUNES=Runes|ESSENCE=Essence|CHARGED=Empowered / Charged|SOUL_FRAGMENTS=Soul Fragments|SOUL_FRAGMENTS_META=Soul Fragments (Void Meta)|MAELSTROM=Maelstrom Weapon|MAELSTROM_ABOVE_5=Maelstrom Weapon 5+|ASTRAL_POWER=Astral Power|AP_PREDICTION=Astral Prediction|ECLIPSE_SOLAR=Eclipse Solar|ECLIPSE_LUNAR=Eclipse Lunar|ECLIPSE_CA=Celestial Alignment|STAGGER_GREEN=Stagger Light|STAGGER_YELLOW=Stagger Moderate|STAGGER_RED=Stagger Heavy|SOUL_FRAGMENTS_VENG=Soul Fragments (Vengeance)|INSANITY=Insanity|MAELSTROM_POWER=Maelstrom Power|WHIRLWIND=Whirlwind|TIP_OF_THE_SPEAR=Tip of the Spear|ICICLES=Icicles|EBON_MIGHT=Ebon Might|RESOURCE_TEXT=Resource Text]]
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
        local r, g, b = fn(...)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return dr, dg, db
end
local function ApiSetRGB(name, r, g, b)
    return ApiCall(name, r, g, b)
end
local function GeneralRGB(prefix, dr, dg, db)
    local g = G()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg, tonumber(g[prefix .. "B"]) or db
end
local function SetGeneralRGB(prefix, r, gCol, b)
    local g = G()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
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
function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth, metadata)
    local color = W.Color(section, label)
    M.BindColor(ctx, color, getRGB, setRGB, metadata)
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
        function(r, g, c)
            if not ApiSetRGB(setName, r, g, c) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        labelWidth, swatchWidth, metadata or Meta("api." .. tostring(setName or getName)))
end
local function GeneralColorAt(ctx, section, label, x, y, prefix, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, c)
            SetGeneralRGB(prefix, r, g, c)
            if type(apply) == "function" then apply() else ApplyColors() end
        end,
        labelWidth, swatchWidth, metadata or Meta("general." .. tostring(prefix)))
end
local function ApiOrGeneralColorAt(ctx, section, label, x, y, getName, setName, prefix, dr, dg, db, apply, alpha, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c)
            local ok = alpha ~= nil and ApiCall(setName, r, g, c, alpha) or ApiCall(setName, r, g, c)
            if not ok then
                SetGeneralRGB(prefix, r, g, c)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        nil, nil, metadata or Meta("general." .. tostring(prefix)))
end
local function TableColorAt(ctx, section, label, x, y, getTable, key, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, c)
            SetTableRGB(getTable(), key, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth, metadata or Meta("table." .. tostring(key)))
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
    RegisterControl(btn, Meta(semanticPath, "action"), label, "button")
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
local function GroupRGB(prefix, dr, dg, db)
    return GroupNum(prefix .. "R", dr), GroupNum(prefix .. "G", dg), GroupNum(prefix .. "B", db)
end
local function GroupColorAt(ctx, section, label, x, y, prefix, dr, dg, db, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GroupRGB(prefix, dr, dg, db) end,
        function(r, g, b) SetGroupRGB(prefix, r, g, b, "MSUF2_GROUP_COLORS", "visual") end,
        labelWidth, swatchWidth, Meta("group_frame.color." .. tostring(prefix)))
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
        nil, nil, Meta("npc.color." .. tostring(row.key)))
end
local function ResetNPCColors(apiName)
    if ApiCall(apiName) then return end
    DB().npcColors = nil
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
    if powerToken then return PowerDefaultRGB(powerToken) end
    return PowerDefaultRGB(token)
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
local function GetPandemicRGB()
    local db = DB()
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    local sh = db.auras3.shared
    return tonumber(sh.pandemicR) or 0.0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1.0
end
local function SetPandemicRGB(r, g, b)
    local db = DB()
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    db.auras3.shared.pandemicR, db.auras3.shared.pandemicG, db.auras3.shared.pandemicB = r, g, b
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
    g.aurasOwnBuffHighlightColor = { 1.00, 0.85, 0.20 }
    g.aurasOwnDebuffHighlightColor = { 1.00, 0.30, 0.30 }
    g.aurasStackCountColor = { 1.00, 1.00, 1.00 }
    g.aurasCooldownTextUseBuckets = false
    g.aurasCooldownTextSafeColor = nil
    g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    g.aurasCooldownTextSafeSeconds = 60
    g.aurasCooldownTextWarningSeconds = 15
    g.aurasCooldownTextUrgentSeconds = 5
    local db = DB()
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    db.auras3.shared.pandemicR, db.auras3.shared.pandemicG, db.auras3.shared.pandemicB = 0.0, 0.4, 1.0
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
local function BuildPowerAndClassPowerColors(ctx, b, CH)
    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            M.SetMenuStateValue("colorsPowerToken", v or "MANA")
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
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
local function BuildAuraAndPortraitColors(ctx, b, CH)
    local auras = b:CollapsibleSection("colors_auras", "Auras", 526, false)
    local w = auras._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(auras, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(auras, "Stack & Highlights", nil, rightX, -42, colW, 380)

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
        local sr, sg, sb = TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1)
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
    AuraColorAt(cooldown, "Safe", -210, "aurasCooldownTextSafeColor", 1, 1, 1, RefreshTextColors)
    AuraColorAt(cooldown, "Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, RefreshTextColors)
    AuraColorAt(cooldown, "Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, RefreshTextColors)
    AuraColorAt(markers, "Stack Count", -62, "aurasStackCountColor", 1, 1, 1, ApplyAuraColors)
    AuraColorAt(markers, "Own Buff", -102, "aurasOwnBuffHighlightColor", 1, 0.85, 0.20, ApplyAuraColors)
    AuraColorAt(markers, "Own Debuff", -142, "aurasOwnDebuffHighlightColor", 1, 0.30, 0.30, ApplyAuraColors)
    ColorValueAt(ctx, markers, "Pandemic window color", 16, -180, GetPandemicRGB, SetPandemicRGB,
        nil, nil, Meta("auras.pandemic_window.color"))
    ValueSliderAt(ctx, markers, "Safe seconds", 16, -232, 0, 600, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) WriteAuraNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end,
        Meta("auras.cooldown.safe_seconds"))
    ValueSliderAt(ctx, markers, "Warning <= sec", 16, -292, 0, 60, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) WriteAuraNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end,
        Meta("auras.cooldown.warning_seconds"))
    ValueSliderAt(ctx, markers, "Urgent <= sec", 16, -352, 0, 30, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) WriteAuraNumber("aurasCooldownTextUrgentSeconds", v, 0, 30) end,
        Meta("auras.cooldown.urgent_seconds"))
    W.Text(auras, "Timer and marker colors are shared by unit and group aura previews.", 24, -440, w - 48, T.colors.muted)
    CH.ButtonAt(auras, "Reset aura colors", 24, -476, 150, ResetAuraColorSettings, "auras.reset")
    M.TrackRefresh(ctx, RefreshColorSamples)

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end,
        nil, nil, Meta("portrait.border_color"))
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end,
        nil, nil, Meta("portrait.background_color"))
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
local function BuildFontAndClassColors(ctx, b, CH, part)
    if part ~= "classes" then
    local font = b:CollapsibleSection("colors_font", "Global Font Color", 100, false)
    CH.ApiColorAt(ctx, font, "Global font color", 12, -10, "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1)
    CH.ButtonAt(font, "Use font palette", 12, -50, 150, function()
        if not ApiCall("ResetGlobalFontToPalette") then
            G().useCustomFontColor = false
            ClearRGB(G(), "fontColorCustom")
            ApplyColors()
        end
    end, "font.use_palette")
    local openFonts = T.Button(font, "Fonts > Text Colors", 190, 22)
    openFonts:SetPoint("TOPRIGHT", font, "TOPRIGHT", -16, -50)
    if T.CenterButtonLabel then T.CenterButtonLabel(openFonts) end
    if M.AddTooltip then
        M.AddTooltip(openFonts, "Fonts > Text Colors", "Open the Fonts page at its Text Colors section.", { hook = true })
    end
    openFonts:SetScript("OnClick", OpenFontsTextColors)
    RegisterControl(openFonts, Meta("font.open_text_colors", "navigation", { navigationKey = "opt_fonts" }), "Fonts > Text Colors", "button")
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
        ColorValueAt(ctx, classColors, COLOR_DATA.CLASS_LABELS[token] or token, 12 + col * classColW, -34 - row * 36,
            function() return ClassColorRGB(token) end,
            function(r, g, c)
                if not ApiCall("SetClassColor", token, r, g, c) then ApplyUnitframeColorWithReload() end
            end, classLabelW, 44, Meta("class_bar.token." .. tostring(token)))
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
        compact and 180 or 190, 52, Meta("bar_gradient.health.color"))
    ColorValueAt(ctx, section, "Power gradient color", powerX, powerY,
        function() return GradientRGB("powerBarGradientColor") end,
        function(r, g, bcol) SetGradientRGB("powerBarGradientColor", r, g, bcol, "MSUF2_POWER_GRADIENT_COLOR") end,
        compact and 180 or 190, 52, Meta("bar_gradient.power.color"))
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
    LabelAt(background, "Tint applied to the bar background in *all* bar modes. Dark Mode uses this tint too.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
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
    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 350, true)
    local refreshBarModeControls
    local function CurrentBarMode()
        local g = G()
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then mode = (g.useClassColors and "class") or "dark" end
        return mode
    end
    ValueDropdownAt(ctx, appearance, "Bar mode", 12, -10, ValueTextPairs "dark=Dark Mode (dark black bars)|class=Class Color Mode (color HP bars)|unified=Unified Color Mode (one color for all frames)|gradient=Color Gradient", 320,
        function()
            return CurrentBarMode()
        end,
        function(mode)
            local g = G()
            g.barMode = mode
            g.darkMode = (mode == "dark")
            g.useClassColors = (mode == "class")
            ApplyUnitframeColorWithReload()
            if refreshBarModeControls then refreshBarModeControls() end
        end,
        Meta("appearance.bar_mode"))
    local unifiedColor = CH.GeneralColorAt(ctx, appearance, "Unified bar color", 12, -70, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
    local darkColor = ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -112, 0, 100, 1, 300,
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
    local gradientStrength = SliderAt(ctx, appearance, "Gradient strength", 360, -70, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyUnitframeColorWithReload, Meta("appearance.gradient.strength"))
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -118, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end, Meta("appearance.gradient.enabled"))
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -166, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = CH.GeneralColorAt(ctx, appearance, "Low", 12, -196, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = CH.GeneralColorAt(ctx, appearance, "Mid", 170, -196, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = CH.GeneralColorAt(ctx, appearance, "High", 328, -196, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = CH.ButtonAt(appearance, "Reset gradient", 486, -196, 150, function()
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
    CH.ApiColorAt(ctx, unit, "Pet Frame Color", 360, -10, "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
    ValueToggleAt(ctx, unit, "Friendly NPC class colors on HP bars (Class Color mode only)", 360, -54,
        function() return ApiValue("GetNPCClassColorBar", function() return G().npcClassColorBar == true end) end,
        function(v)
            if not ApiCall("SetNPCClassColorBar", v) then
                G().npcClassColorBar = v and true or false
                ApplyUnitframeColorWithReload()
            end
        end,
        Meta("npc.class_color_bar"))
    CH.ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190,
        function() ResetNPCColors("ResetAllNPCColors") end, "unitframe.reset")
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
    ColorValueAt(ctx, barColors, "Positive Heal Prediction", barLeftX, -146,
        function() return GeneralRGB("healPredictionColor", 0, 1, 0) end,
        function(r, g, c)
            local general = G()
            general.healPredictionColorR, general.healPredictionColorG, general.healPredictionColorB = r, g, c
            ApplyColors()
        end,
        nil, nil, Meta("prediction.heal_color"))
    ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end,
        nil, nil, Meta("bar.purge_border_color"))
    ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end,
        nil, nil, Meta("bar.outline_color"))
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
    CH.ButtonAt(barColors, "Reset Bar Colors", barLeftX, -234, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        ClearRGB(g, "healPredictionColor")
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
        overrideColorLabelW, nil, Meta("castbar.player_override.custom_color"))
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
end

local function BuildHighlightAndGameplayColors(ctx, b, CH, part)
    if part ~= "gameplay" then
    local highlight = b:CollapsibleSection("colors_highlight", "Mouseover Highlight", 210, false)
    local highlightColor = ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -48, HighlightRGB, SetHighlightRGB,
        nil, nil, Meta("highlight.mouseover.color"))
    SwitchAt(ctx, highlight, "Mouseover Highlight", 12, -10, 260, G, "highlightEnabled", true, function()
        SetHighlightRGB(HighlightRGB())
        SetControlEnabled(highlightColor, G().highlightEnabled ~= false)
    end, Meta("highlight.mouseover.enabled"))
    CH.TableColorAt(ctx, highlight, "Boss target highlight color", 12, -104, G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
    M.BindGateGroup(ctx, nil, {
        { controls = highlightColor, on = function() return G().highlightEnabled ~= false end },
    })
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
        nil, nil, Meta("gameplay.combat_enter_color"))
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

local function BuildColorPainter(ctx, b)
    local painter = M.ColorPainter
    if not (painter and type(painter.Build) == "function") then return end
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local function ApiSpec(label, role, getName, setName, dr, dg, db, apply)
        return {
            label = label, role = role,
            get = function() return ApiRGB(getName, dr, dg, db) end,
            set = function(r, g, bcol)
                if not ApiSetRGB(setName, r, g, bcol) then (apply or ApplyColors)() end
            end,
        }
    end
    local function GeneralSpec(label, role, prefix, dr, dg, db, apply)
        return {
            label = label, role = role,
            get = function() return GeneralRGB(prefix, dr, dg, db) end,
            set = function(r, g, bcol) SetGeneralRGB(prefix, r, g, bcol); (apply or ApplyColors)() end,
        }
    end
    local function TableSpec(label, role, getTable, key, dr, dg, db, apply)
        return {
            label = label, role = role,
            get = function() return TableRGB(getTable(), key, dr, dg, db) end,
            set = function(r, g, bcol) SetTableRGB(getTable(), key, r, g, bcol); (apply or ApplyColors)() end,
        }
    end
    local categories = {
        {
            key = "unit", title = "Unit Frames", shortTitle = "Bars & Text", subtitle = "Health, overlays, portrait and frame treatment.",
            pickerNote = "HP, name and power text share Font Coloring and remain editable here.",
            colors = {
                GeneralSpec("Unified health", "health", "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload),
                GeneralSpec("Health gradient - low", "gradientLow", "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload),
                GeneralSpec("Health gradient - mid", "gradientMid", "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload),
                GeneralSpec("Health gradient - high", "gradientHigh", "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload),
                ApiSpec("Bar background", "background", "GetClassBarBgColor", "SetClassBarBgColor", 0, 0, 0, ApplyUnitframeColorWithReload),
                ApiSpec("Power background", "powerBg", "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0),
                ApiSpec("Absorb overlay", "absorb", "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1),
                ApiSpec("Heal-absorb", "healAbsorb", "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0),
                GeneralSpec("Positive heal prediction", "healPrediction", "healPredictionColor", 0, 1, 0),
                GeneralSpec("Frame outline", "outline", "barOutlineColor", 0, 0, 0, ApplyGlobalOutlineColor),
                ApiSpec("HP / name / power text", "font", "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1),
                { label = "Portrait border", role = "portraitBorder", get = function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
                    set = function(r, g, bcol) SetAllPortraitRGB("portraitBorderColor", r, g, bcol) end },
                { label = "Portrait background", role = "portraitBg", get = function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
                    set = function(r, g, bcol) SetAllPortraitRGB("portraitBgColor", r, g, bcol) end },
                { label = "Mouseover highlight", role = "mouseover", get = HighlightRGB, set = SetHighlightRGB },
            },
        },
        {
            key = "group", title = "Group Frames", shortTitle = "Group", subtitle = "Shared by Party, Raid and Mythic Raid.",
            pickerNote = "Shared by Party, Raid and Mythic Raid.",
            colors = {
                { label = "Custom health", role = "health", get = function() return GroupRGB("healthCustom", 0.20, 0.80, 0.20) end,
                    set = function(r, g, bcol) SetGroupRGB("healthCustom", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Background", role = "background", get = function() return GroupRGB("bg", 0.10, 0.10, 0.10) end,
                    set = function(r, g, bcol) SetGroupRGB("bg", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Group border", role = "border", get = function() return GroupRGB("groupBorder", 0.38, 0.68, 1.00) end,
                    set = function(r, g, bcol) SetGroupRGB("groupBorder", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Target highlight", role = "target", get = function() return GroupRGB("target", 1, 1, 1) end,
                    set = function(r, g, bcol) SetGroupRGB("target", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Focus highlight", role = "focus", get = function() return GroupRGB("hlFocusColor", 0.50, 0.50, 1.00) end,
                    set = function(r, g, bcol) SetGroupRGB("hlFocusColor", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Aggro corners", role = "aggro", get = function() return GroupRGB("ciAggroColor", 1, 0.55, 0) end,
                    set = function(r, g, bcol) SetGroupRGB("ciAggroColor", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Dead / offline", role = "dead", get = function() return GroupRGB("deadBg", 0.60, 0.05, 0.05) end,
                    set = function(r, g, bcol) SetGroupRGB("deadBg", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                { label = "Debuff stripe", role = "debuff", get = function() return GroupRGB("debuffStripeColor", 0.80, 0.20, 0.20) end,
                    set = function(r, g, bcol) SetGroupRGB("debuffStripeColor", r, g, bcol, "MSUF2_GROUP_PAINTER", "visual") end },
                ApiSpec("Absorb overlay", "absorb", "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1),
                ApiSpec("Heal-absorb", "healAbsorb", "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0),
                GeneralSpec("Positive heal prediction", "healPrediction", "healPredictionColor", 0, 1, 0),
            },
        },
        {
            key = "cast", title = "Castbars", shortTitle = "Castbar", subtitle = "Interrupt states, text, border and kick feedback.",
            pickerNote = "Cast states, feedback, text, border and background.",
            colors = {
                ApiSpec("Interruptible", "interruptible", "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8, ApplyCastbarColors),
                ApiSpec("Non-interruptible", "nonInterruptible", "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01, ApplyCastbarColors),
                ApiSpec("Interrupted", "interrupted", "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1, 0.82, 0, ApplyCastbarColors),
                ApiSpec("Kick unavailable", "unavailable", "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1, 0.49, 0.14, ApplyCastbarColors),
                ApiSpec("Cast text", "text", "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1, ApplyCastbarColors),
                ApiSpec("Cast Target Name", "targetName", "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1, ApplyCastbarColors),
                ApiSpec("Cast border", "border", "GetCastbarBorderColor", "SetCastbarBorderColor", 0, 0, 0, ApplyCastbarColors),
                ApiSpec("Cast background", "background", "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", 0.10, 0.10, 0.10, ApplyCastbarColors),
                TableSpec("Kick ready", "kickReady", G, "kickReadyColor", 0, 1, 0, ApplyCastbarColors),
                TableSpec("Kick not ready", "kickNotReady", G, "kickNotReadyColor", 1, 0, 0, ApplyCastbarColors),
            },
        },
        {
            key = "auras", title = "Auras & Icons", shortTitle = "Auras", subtitle = "Timer urgency, ownership, stacks and pandemic state.",
            pickerNote = "Timers, ownership, stacks, pandemic and purge.",
            colors = {
                TableSpec("Safe timer", "safe", G, "aurasCooldownTextSafeColor", 1, 1, 1, ApplyAuraColors),
                TableSpec("Warning timer", "warning", G, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, ApplyAuraColors),
                TableSpec("Urgent timer", "urgent", G, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, ApplyAuraColors),
                TableSpec("Own buff", "ownBuff", G, "aurasOwnBuffHighlightColor", 1, 0.85, 0.20, ApplyAuraColors),
                TableSpec("Own debuff", "ownDebuff", G, "aurasOwnDebuffHighlightColor", 1, 0.30, 0.30, ApplyAuraColors),
                TableSpec("Stack count", "stack", G, "aurasStackCountColor", 1, 1, 1, ApplyAuraColors),
                { label = "Pandemic window", role = "pandemic", get = GetPandemicRGB, set = SetPandemicRGB },
                { label = "Purge border", role = "purge", get = function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0) end,
                    set = function(r, g, bcol) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, bcol) end },
            },
        },
        {
            key = "resources", title = "Resources", shortTitle = "Resources", subtitle = "Current power and Class Resource selections.",
            pickerNote = "Power and Class Resource colors.",
            colors = {
                { label = "Selected power", role = "power", get = function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
                    set = function(r, g, bcol) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, bcol) end },
                ApiSpec("Power background", "powerBg", "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0),
                { label = "Class Resource", role = "class", get = function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
                    set = function(r, g, bcol) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, bcol) end },
                { label = "Resource background", role = "classBg", get = function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
                    set = function(r, g, bcol) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, bcol) end },
                { label = "First custom slot", role = "slot", get = function() return GetClassPowerSlotRGB(M.colorsCPToken or "COMBO_POINTS", 1) end,
                    set = function(r, g, bcol)
                        local token = M.colorsCPToken or "COMBO_POINTS"
                        if GetClassPowerSlotMode(token) ~= "custom" then SetClassPowerSlotMode(token, "custom") end
                        SetClassPowerRGB(ClassPowerSlotToken(token, 1), r, g, bcol)
                    end },
                { label = "Full resource", role = "full", get = function() return GetClassPowerFullRGB(M.colorsCPToken or "COMBO_POINTS") end,
                    set = function(r, g, bcol)
                        local token = M.colorsCPToken or "COMBO_POINTS"
                        if not ClassPowerFullColorEnabled(token) then SetClassPowerFullColorEnabled(token, true) end
                        SetClassPowerRGB(ClassPowerFullColorToken(token), r, g, bcol)
                    end },
            },
        },
    }
    painter.Build(ctx, b, categories)
end

local function ColorGroupHasPendingFocus(ctx, sectionIds)
    local request = _G.MSUF_EM2_MenuFocusRequest
    if type(request) ~= "table" or request.explicit ~= true or request.consumed == true then return false end
    if request.pageKey and tostring(request.pageKey) ~= tostring(ctx and ctx.key or "") then return false end
    local wanted = tostring(request.sectionId or "")
    for i = 1, #(sectionIds or {}) do
        if wanted == sectionIds[i] then return true end
    end
    return false
end

local function BuildColorGroup(ctx, builder, id, title, subtitle, defaultOpen, sectionIds, build)
    local group = builder:CollapsibleSection(id, title, 96, defaultOpen)
    local entry = group._msuf2CollapsibleEntry
    local groupW = group._msuf2Width or ctx.width or 720
    local hasSubtitle = subtitle and subtitle ~= ""
    if hasSubtitle then
        LabelAt(group, subtitle, 16, -8, groupW - 32, "GameFontHighlightSmall", T.colors.muted)
    end

    local inner, built, building
    local function BuildContent()
        if built or building or not entry then return false end
        building = true
        local refreshers = ctx and ctx.refreshers
        local refreshStart = type(refreshers) == "table" and #refreshers or 0
        local wasBuilding = ctx and ctx._msuf2Building
        if ctx then ctx._msuf2Building = true end
        inner = W.PageBuilder(ctx, {
            parent = group,
            width = groupW,
            contentX = 0,
            topInset = hasSubtitle and 30 or 0,
            ancestorEntry = entry,
            onContentHeight = function(height)
                height = max(72, tonumber(height) or 72)
                if entry.contentHeight == height then return end
                entry.contentHeight = height
                if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
                if entry.outer and entry.outer.SetHeight then
                    entry.outer:SetHeight(entry.headerHeight + (entry.open and height or 0))
                end
                builder:RequestRelayoutCollapsibles()
            end,
        })
        build(inner)
        inner:RelayoutCollapsibles()
        built = true
        building = nil
        if ctx then ctx._msuf2Building = wasBuilding end
        if not wasBuilding and type(refreshers) == "table" then
            for i = refreshStart + 1, #refreshers do
                local refresh = refreshers[i]
                if type(refresh) == "function" then refresh() end
            end
            -- The current outer relayout reads the updated body height after
            -- this callback, so its pending marker has already been satisfied.
            builder._msuf2RelayoutPending = nil
        end
        return true
    end
    local function RefreshLazyGroup()
        if entry.open and not built then return BuildContent() end
    end
    if (ctx and ctx.hiddenBuild) or entry.open or ColorGroupHasPendingFocus(ctx, sectionIds) then
        BuildContent()
    else
        entry._msuf2RefreshState = RefreshLazyGroup
    end
    return group
end

local function BuildColors(ctx)
    local b, CH = W.PageBuilder(ctx), COLOR_HELPERS
    b:GlobalStyleHeader("Colors", "Frame, group-frame, bar, aura, castbar and resource colors.", 72)
    BuildColorPainter(ctx, b)

    BuildColorGroup(ctx, b, "colors_group_general", "General", "The shared color rules used across MSUF.", false,
        { "colors_appearance", "colors_font" }, function(inner)
        BuildBackgroundAndAppearance(ctx, inner, CH, "appearance")
        BuildFontAndClassColors(ctx, inner, CH, "font")
    end)
    BuildColorGroup(ctx, b, "colors_group_units", "Unit Frames", "Reaction colors and feedback for individual units.", false,
        { "colors_unit", "colors_npc_type", "colors_highlight" }, function(inner)
        BuildUnitAndNPCColors(ctx, inner, CH)
        BuildHighlightAndGameplayColors(ctx, inner, CH, "highlight")
    end)
    BuildColorGroup(ctx, b, "colors_group_groups", "Group Frames", nil, false,
        { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state", "colors_group_frames_highlights" }, function(inner)
        BuildGroupFrameColors(ctx, inner)
    end)
    BuildColorGroup(ctx, b, "colors_group_bars", "Bars", "Health, power, class resources, castbars and predictions.", false,
        { "colors_classes", "colors_background", "colors_bar_colors", "colors_bar_gradients", "colors_castbar", "colors_power", "colors_class_power" }, function(inner)
        BuildFontAndClassColors(ctx, inner, CH, "classes")
        BuildBackgroundAndAppearance(ctx, inner, CH, "background")
        BuildBarAndGroupColors(ctx, inner, CH, false)
        BuildBarGradientColors(ctx, inner, CH)
        BuildCastbarColors(ctx, inner, CH)
        BuildPowerAndClassPowerColors(ctx, inner, CH)
    end)
    BuildColorGroup(ctx, b, "colors_group_additional", "Additional", "Combat feedback, aura timers and portraits.", false,
        { "colors_gameplay", "colors_auras", "colors_portrait" }, function(inner)
        BuildHighlightAndGameplayColors(ctx, inner, CH, "gameplay")
        BuildAuraAndPortraitColors(ctx, inner, CH)
    end)
    b:RelayoutCollapsibles()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 18 })
