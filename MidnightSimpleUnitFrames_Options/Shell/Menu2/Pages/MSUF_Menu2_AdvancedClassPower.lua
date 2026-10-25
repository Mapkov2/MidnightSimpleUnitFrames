-- Advanced class-resource settings. Runtime work stays behind the shared apply queue;
-- this file owns only saved-value bindings, page layout, and control-state dependencies.
local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"
local ExportPublic = MSUF.ExportPublic
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load; the apply paths use the copies resolved in Core below.
M.RequireGlobals(FILE, {
    "MSUF_UFPreview_RequestRefresh",
    "MSUF_GetEffectiveCooldownFrame",
    "MSUF_IsCooldownAnchorSupported",
    "MSUF_UF_NormalizeShapeAlign",
    "MSUF_UF_NormalizeDetachedPowerShape",
    "MSUF_UF_NormalizePlayerHPShape",
    "MSUF_EnsureCooldownWidthObservers",
})
-- Collaborators the apply helpers and the Quick Setup tooltip reach on every slider step or
-- hover: resolved once here, so those paths never go through MSUF.Require / MSUF.Optional.
local Core = {
    EnsureCooldownWidthObservers = MSUF.Require("MSUF_EnsureCooldownWidthObservers", FILE),
    RequestPreviewRefresh = MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE),
    GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", FILE),
    GetUsableCooldownAnchorSize = MSUF.Require("MSUF_GetUsableCooldownAnchorSize", FILE),
    ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE),
}
local C_Timer = M.MenuTimer or C_Timer
local AP = M.AdvancedPage or {}
local W = M.Widgets
local T = M.Theme

local floor = math.floor
local max = math.max
local min = math.min
local RefreshClassPowerInlinePreview = M.RefreshProxy()
local Bars, BoolValue, NumValue, SetValue = AP.Bars, AP.BoolValue, AP.NumValue, AP.SetValue
local DeepCopyTable = AP.DeepCopyTable
local Schema = M.ControlSchema
local SetControlEnabled, ControlMeta, RegisterControl = AP.SetControlEnabled, AP.ControlMeta, AP.RegisterControl
local CLASSPOWER_SETTING_KEY_BY_PATH = {
    ["visibility.independent"] = "bars.classPowerIndependentVisibility",
    ["detached_power.visibility.independent"] = "bars.playerPowerIndependentVisibility",
    ["detached_power.visibility.out_of_combat"] = "bars.playerPowerHideOOC",
    ["detached_power.visibility.when_full"] = "bars.playerPowerHideWhenFull",
    ["detached_power.visibility.when_empty"] = "bars.playerPowerHideWhenEmpty",
    ["player_hp.visibility.independent"] = "bars.playerHPBarIndependentVisibility",
    ["player_hp.visibility.out_of_combat"] = "bars.playerHPBarHideOOC",
    ["player_hp.visibility.when_full"] = "bars.playerHPBarHideWhenFull",
    ["player_hp.visibility.when_empty"] = "bars.playerHPBarHideWhenEmpty",
    ["alternative_mana.visibility.independent"] = "bars.altManaIndependentVisibility",
    ["alternative_mana.visibility.out_of_combat"] = "bars.altManaHideOOC",
    ["alternative_mana.visibility.when_full"] = "bars.altManaHideWhenFull",
    ["alternative_mana.visibility.when_empty"] = "bars.altManaHideWhenEmpty",
    ["resource_extras.visibility.independent"] = "bars.resourceExtraIndependentVisibility",
    ["resource_extras.visibility.out_of_combat"] = "bars.resourceExtraHideOOC",
    ["alternative_mana.enabled"] = "bars.showAltMana",
    ["alternative_mana.layout.height"] = "bars.altManaHeight",
    ["alternative_mana.layout.widthMode"] = "bars.altManaWidthMode",
    ["alternative_mana.layout.width"] = "bars.altManaWidth",
    ["alternative_mana.layout.x"] = "bars.altManaOffsetX",
    ["alternative_mana.layout.y"] = "bars.altManaOffsetY",
    ["alternative_mana.smooth_fill"] = "bars.altManaSmoothFill",
    ["behavior.anchor"] = "bars.classPowerAnchorToCooldown",
    ["behavior.charged"] = "bars.showChargedComboPoints",
    ["behavior.ebon"] = "bars.showEbonMight",
    ["behavior.sweeping"] = "bars.showSweepingStrikes",
    ["behavior.ele"] = "bars.showEleMaelstrom",
    ["behavior.ironfur"] = "bars.showGuardianIronfur",
    ["behavior.ironfurHashes"] = "bars.guardianIronfurShowHashLines",
    ["behavior.prediction"] = "bars.classPowerShowPrediction",
    ["behavior.reverse"] = "bars.classPowerFillReverse",
    ["behavior.rune"] = "bars.runeShowTime",
    ["behavior.shadow"] = "bars.showShadowMana",
    ["behavior.smooth"] = "bars.classPowerSmoothFill",
    ["behavior.text"] = "bars.classPowerShowText",
    ["detached_power.enabled"] = "player.powerBarDetached",
    ["detached_power.layout.anchor"] = "player.detachedPowerBarAnchorToClassPower",
    ["detached_power.layout.height"] = "player.detachedPowerBarHeight",
    ["detached_power.layout.layer"] = "player.detachedPowerBarFrameLevelOffset",
    ["detached_power.layout.mode"] = "bars.detachedPowerBarWidthMode",
    ["detached_power.layout.resource_source"] = "player.playerPowerSource",
    ["detached_power.layout.orbSize"] = "player.detachedPowerOrbSize",
    ["detached_power.layout.smooth_fill"] = "player.powerSmoothFill",
    ["detached_power.layout.sync"] = "player.detachedPowerBarSyncClassPower",
    ["detached_power.layout.width"] = "player.detachedPowerBarWidth",
    ["detached_power.layout.x"] = "player.detachedPowerBarOffsetX",
    ["detached_power.layout.y"] = "player.detachedPowerBarOffsetY",
    ["detached_power.text.center"] = "player.powerTextCenter",
    ["detached_power.text.layer"] = "player.powerTextLayer",
    ["detached_power.text.left"] = "player.powerTextLeft",
    ["detached_power.text.onBar"] = "player.detachedPowerBarTextOnBar",
    ["detached_power.text.powerTextCenterHidePercentSymbol"] = "player.powerTextCenterHidePercentSymbol",
    ["detached_power.text.powerTextLeftHidePercentSymbol"] = "player.powerTextLeftHidePercentSymbol",
    ["detached_power.text.powerTextRightHidePercentSymbol"] = "player.powerTextRightHidePercentSymbol",
    ["detached_power.text.right"] = "player.powerTextRight",
    ["detached_power.text.sep"] = "player.powerTextSeparator",
    ["detached_power.text.size"] = "player.powerFontSize",
    ["detached_power.text.x"] = "player.powerOffsetX",
    ["detached_power.text.y"] = "player.powerOffsetY",
    ["detached_power.textures.outline"] = "bars.detachedPowerBarOutline",
    ["layout.enabled"] = "bars.showClassPower",
    ["layout.height"] = "bars.classPowerHeight",
    ["layout.level"] = "bars.classPowerFrameLevelOffset",
    ["layout.shape"] = "bars.classPowerShape",
    ["layout.shape_alignment"] = "bars.classPowerShapeAlign",
    ["layout.width"] = "bars.classPowerWidth",
    ["layout.widthMode"] = "bars.classPowerWidthMode",
    ["layout.x"] = "bars.classPowerOffsetX",
    ["layout.y"] = "bars.classPowerOffsetY",
    ["player_hp.enabled"] = "bars.playerHPBarEnabled",
    ["player_hp.layout.anchor"] = "bars.playerHPBarAnchor",
    ["player_hp.layout.gap"] = "bars.playerHPBarGap",
    ["player_hp.layout.height"] = "bars.playerHPBarHeight",
    ["player_hp.layout.layer"] = "bars.playerHPBarFrameLevelOffset",
    ["player_hp.layout.manualWidth"] = "bars.playerHPBarWidth",
    ["player_hp.layout.orbSize"] = "bars.playerHPBarOrbSize",
    ["player_hp.layout.shape"] = "bars.playerHPBarShape",
    ["player_hp.layout.smooth"] = "bars.playerHPBarSmoothFill",
    ["player_hp.layout.widthMode"] = "bars.playerHPBarWidthMode",
    ["player_hp.layout.x"] = "bars.playerHPBarOffsetX",
    ["player_hp.layout.y"] = "bars.playerHPBarOffsetY",
    ["player_hp.text.center"] = "bars.playerHPBarTextCenter",
    ["player_hp.text.enabled"] = "bars.playerHPBarTextEnabled",
    ["player_hp.text.left"] = "bars.playerHPBarTextLeft",
    ["player_hp.text.playerHPBarTextCenterHidePercentSymbol"] = "bars.playerHPBarTextCenterHidePercentSymbol",
    ["player_hp.text.playerHPBarTextLeftHidePercentSymbol"] = "bars.playerHPBarTextLeftHidePercentSymbol",
    ["player_hp.text.playerHPBarTextRightHidePercentSymbol"] = "bars.playerHPBarTextRightHidePercentSymbol",
    ["player_hp.text.reverse"] = "bars.playerHPBarTextReverse",
    ["player_hp.text.right"] = "bars.playerHPBarTextRight",
    ["player_hp.text.sep"] = "bars.playerHPBarTextSeparator",
    ["player_hp.text.size"] = "bars.playerHPBarTextSize",
    ["player_hp.text.use_player_text"] = "bars.playerHPBarUsePlayerText",
    ["player_hp.text.x"] = "bars.playerHPBarTextOffsetX",
    ["player_hp.text.y"] = "bars.playerHPBarTextOffsetY",
    ["player_hp.textures.bg"] = "bars.playerHPBarBgTexture",
    ["player_hp.textures.bgAlpha"] = "bars.playerHPBarBgAlpha",
    ["player_hp.textures.color"] = "bars.playerHPBarColorMode",
    ["player_hp.textures.fg"] = "bars.playerHPBarTexture",
    ["player_hp.textures.outline"] = "bars.playerHPBarOutline",
    ["style.opacity.bg"] = "bars.classPowerBgAlpha",
    ["style.opacity.empty"] = "bars.classPowerEmptyAlpha",
    ["style.opacity.filled"] = "bars.classPowerFilledAlpha",
    ["style.pips.gap"] = "bars.classPowerGap",
    ["style.pips.outline"] = "bars.classPowerOutline",
    ["style.pips.separator"] = "bars.classPowerTickWidth",
    ["style.resources.bgTex"] = "bars.classPowerBgTexture",
    ["style.resources.color"] = "bars.classPowerColorByType",
    ["style.resources.comboColor"] = "bars.classPowerComboPointColorMode",
    ["style.resources.fgTex"] = "bars.classPowerTexture",
    ["style.text.mode"] = "bars.classPowerTextMode",
    ["style.text.font"] = "bars.classPowerFontSize",
    ["style.text.layer"] = "bars.classPowerTextLayer",
    ["style.text.textX"] = "bars.classPowerTextOffsetX",
    ["style.text.textY"] = "bars.classPowerTextOffsetY",
    ["visibility.out_of_combat"] = "bars.classPowerHideOOC",
    ["visibility.sync_player_power_ooc"] = "bars.classPowerSyncPlayerPowerOOC",
    ["visibility.when_empty"] = "bars.classPowerHideWhenEmpty",
    ["visibility.when_full"] = "bars.classPowerHideWhenFull",
}
local CLASSPOWER_ACTION_KEY_BY_PATH = {
    ["quick_setup.class_bar"] = "class_power_quick_setup",
}
local CLASSPOWER_DYNAMIC_SETTING_KEYS_BY_PATH = {
    ["detached_power.text.preset"] = { "player.showPowerText", "player.powerTextMode" },
    ["detached_power.text.outline"] = {
        "player.fontOverride", "player.boldText", "player.noOutline",
    },
    ["detached_power.text.slot_offset.x"] = {
        "player.powerTextLeftOffsetX", "player.powerTextCenterOffsetX", "player.powerTextRightOffsetX",
    },
    ["detached_power.text.slot_offset.y"] = {
        "player.powerTextLeftOffsetY", "player.powerTextCenterOffsetY", "player.powerTextRightOffsetY",
    },
}
local function Meta(path, classification, exact)
    exact = type(exact) == "table" and exact or {}
    if exact.settingKey == nil then exact.settingKey = CLASSPOWER_SETTING_KEY_BY_PATH[path] end
    if exact.actionKey == nil then exact.actionKey = CLASSPOWER_ACTION_KEY_BY_PATH[path] end
    if exact.settingKey == nil and exact.actionKey == nil and CLASSPOWER_DYNAMIC_SETTING_KEYS_BY_PATH[path] then
        exact.searchSettingKeys = CLASSPOWER_DYNAMIC_SETTING_KEYS_BY_PATH[path]
    end
    return ControlMeta("classpower", "advanced", path, classification, M.ClassPowerWorkspace.Decorate(exact, path))
end
local function RegisterSegment(segment, path, values, classification)
    classification = classification or "ephemeral"
    RegisterControl(segment, Meta(path, classification), nil, "segment", values)
    if segment and type(segment.buttons) == "table" then
        local optionClassification = classification == "setting" and "action" or classification
        for i = 1, #segment.buttons do
            local item = values and values[i] or {}
            RegisterControl(segment.buttons[i], Meta(path .. ".option." .. tostring(item.value), optionClassification),
                item.text or item.label or item.value or "", "button")
        end
    end
    if path == "style.workspace_tab" then Schema.Owned(segment, "classpower", "selection") end
    return segment
end
local function MoveWidget(widget, parent, x, y, width, titleJustify)
    -- This page's column widths include the checkbox and its label gap.
    if width and widget and widget._msuf2ControlKind == "toggle" then width = max(20, width - 36) end
    return W.MoveWidget(widget, parent, x, y, width, titleJustify)
end
local SetControlsEnabled = W.SetControlsEnabled
local CPPreview = M.ClassPowerPreview or {}
local function AddTooltip(control, title, body) if M.AddTooltip then M.AddTooltip(control, title, body, { hook = true, owner = "ANCHOR_RIGHT" }) end end
local APPLY_CLASSPOWER_GENERAL = { preview = true, applyAll = false, classpower = true, classpowerApplied = true }
local CLASSPOWER_FULL = { full = true, cdm = true }
local CLASSPOWER_VISUALS = { visuals = true }
local CLASSPOWER_SMOOTH = { visuals = true, events = true }
local CLASSPOWER_TEXT = { fonts = true, text = true }
local CLASSPOWER_QUICK_RUNTIME = { full = true, cdm = true, playerHP = true, anchor = true, syncNow = false }
local CLASSPOWER_QUICK_FLAGS = { unit = "player", preview = true, applyAll = false, power = true, classpower = true, classpowerApplied = true }
local function ApplyClassPowerRuntime(reason, runtime, flags)
    RefreshClassPowerInlinePreview()
    return Core.ApplyService.RequestClassPowerDomains(reason or "MSUF2_CLASSPOWER", runtime, flags or APPLY_CLASSPOWER_GENERAL)
end
local function ApplyClassPower() ApplyClassPowerRuntime("MSUF2_CLASSPOWER", CLASSPOWER_FULL, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerSource()
    Core.EnsureCooldownWidthObservers()
    ApplyClassPower()
end
local function ApplyClassPowerVisuals() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_VISUALS", CLASSPOWER_VISUALS, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerSmoothing() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_SMOOTH", CLASSPOWER_SMOOTH, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerText() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_TEXT", CLASSPOWER_TEXT, APPLY_CLASSPOWER_GENERAL) end
local TextureValues = M.StatusBarTextureItems
local VT, VTP = M.ValueTextList, M.ValueTextPairs
local PLAYER_POWER_SOURCE_VALUES = M.PlayerPowerSourceValues
local NormalizePlayerPowerSource = M.NormalizePlayerPowerSource
local NormalizeClassPowerShape = CPPreview.NormalizeClassShape
local NormalizeClassPowerShapeAlign = MSUF.Require("MSUF_UF_NormalizeShapeAlign", FILE)
local NormalizeDetachedPowerShape = MSUF.Require("MSUF_UF_NormalizeDetachedPowerShape", FILE)
local NormalizePlayerHPShape = MSUF.Require("MSUF_UF_NormalizePlayerHPShape", FILE)
local function ResolvePlayerHPShape(bars, db)
    local value = NormalizePlayerHPShape(bars and bars.playerHPBarShape)
    if value ~= "FOLLOW_POWER" then return CPPreview.ResolvePowerShape(value) end
    local player = db and db.player or nil
    if not (player and player.powerBarDetached == true) then return "BAR" end
    return CPPreview.ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars and bars.classPowerShape)
end
local DETACHED_POWER_TEXT_PRESET_VALUES = VTP("OFF=Off|CURRENT=Current|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current + Percent|"
    .. "CURMAXPERCENT=Current / Max + Percent|CUSTOM=Custom Slots")
local CLASS_POWER_TEXT_MODE_VALUES = VTP "AUTO=Automatic (resource default)|CURRENT=Current|MAX=Maximum|CURMAX=Current / Maximum"
local DETACHED_POWER_TEXT_OUTLINE_VALUES = VTP "OUTLINE=Outline|THICKOUTLINE=Thick Outline|NONE=None"
local PLAYER_HP_ANCHOR_VALUES = VTP("CLASS_TOP=Above Class Resource|CLASS_BOTTOM=Below Class Resource|POWER_TOP=Above Player Power|"
    .. "POWER_BOTTOM=Below Player Power")
local PLAYER_HP_WIDTH_VALUES = VTP "class=Class Resource|power=Player Power|player=Player Frame|custom=Custom"
local ALT_MANA_WIDTH_VALUES = VTP "player=Player Frame|custom=Custom"
local PLAYER_HP_SHAPE_VALUES = VTP "BAR=Bar|FOLLOW_POWER=Follow Player Power|ROUND=Round|CRYSTAL=Crystal|ORB=Orb"
local PLAYER_HP_COLOR_VALUES = VTP "GLOBAL=Global|CLASS=Class Color|DARK=Dark Mode|GRADIENT=HP Gradient"
local PLAYER_HP_TEXT_VALUES = VTP("PERCENT=Percent|CURRENT=Current|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|"
    .. "CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|"
    .. "PERCENTCURMAX=Percent / Current / Max|NONE=None")
local DETACHED_POWER_SLOT_VALUES = VTP("CURRENT=Current|MAX=Max|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current / Percent|"
    .. "CURMAXPERCENT=Current / Max / Percent|NONE=None")
local DETACHED_POWER_SEPARATORS = VT("", "space", "-", "-", "/", "/", "\\", "\\", "|", "|", "<", "<", ">", ">", "~", "~", ":", ":")
local TEXT_SLOT_VALUES = VT("left", "Left", "center", "Center", "right", "Right")
local DETACHED_POWER_TEXT_PRESETS = M.KeySetFromWords "CURRENT CURMAX PERCENT CURPERCENT CURMAXPERCENT"
local CLASS_POWER_PREVIEW_SPECS = {
    { key = "deathknight_runes", specIndex = 1, label = "Death Knight - Runes", token = "RUNES", mode = "rune", segments = 6, value = 3,
        previewText = "3", runeDuration = 10 },
    --- Devourer's Soul Fragment maximum is talent-dependent and far above the
    --- ten-pip ceiling, so the live bar is one continuous fill whose fragment
    --- boundaries are drawn as separator notches. `fragments` previews that
    --- division at a representative maximum.
    { key = "demonhunter_devourer", specIndex = 3,
        label = "Demon Hunter - Soul Fragments", token = "SOUL_FRAGMENTS", mode = "aura_single", segments = 1, value = 0.5,
        previewText = "20", fragments = 40 },
    { key = "demonhunter_vengeance", specIndex = 2,
        label = "Demon Hunter - Vengeance Fragments", token = "SOUL_FRAGMENTS_VENG", mode = "aura_segmented", segments = 6, value = 4, previewText = "4 / 6" },
    { key = "druid_feral", specIndex = 2, primaryPower = 3,
        label = "Druid - Feral Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "druid_guardian", specIndex = 3, primaryPower = 1,
        label = "Druid - Guardian Ironfur", token = "IRONFUR", mode = "ironfur", segments = 1, value = 0.72, previewText = "3" },
    { key = "druid_balance", specIndex = 1, primaryPower = 8, label = "Druid - Balance (no class bar)", mode = "none", enabled = false },
    { key = "evoker_essence", specIndex = 1, label = "Evoker - Essence", token = "ESSENCE", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "evoker_augmentation_ebon", specIndex = 3, label = "Evoker - Augmentation Ebon Might", token = "ESSENCE", mode = "segmented", segments = 6,
        value = 4, previewText = "4",
        secondaryTimer = { token = "EBON_MIGHT", mode = "timer_bar", segments = 1, value = 0.6, previewText = "12.0", nativeDurationText = true } },
    { key = "hunter_survival_tip", specIndex = 3,
        label = "Hunter - Survival Tip of the Spear", token = "TIP_OF_THE_SPEAR", mode = "aura_segmented", segments = 3, value = 2, previewText = "2" },
    { key = "mage_arcane", specIndex = 1,
        label = "Mage - Arcane Charges", token = "ARCANE_CHARGES", mode = "segmented", segments = 4, value = 3, previewText = "3" },
    { key = "mage_frost", specIndex = 3,
        label = "Mage - Frost Icicles", token = "ICICLES", mode = "aura_segmented", segments = 5, value = 3, previewText = "3" },
    { key = "monk_brewmaster", specIndex = 1, label = "Monk - Brewmaster Stagger", token = "STAGGER_YELLOW", mode = "stagger", segments = 1,
        value = 0.42, previewText = "14K" },
    { key = "monk_windwalker", specIndex = 3, label = "Monk - Windwalker Chi", token = "CHI", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "paladin_holy_power", specIndex = 1,
        label = "Paladin - Holy Power", token = "HOLY_POWER", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "priest_shadow", specIndex = 3, label = "Priest - Shadow Insanity", token = "INSANITY", mode = "continuous", segments = 1, value = 0.62,
        previewText = "62 / 100" },
    { key = "rogue_combo", specIndex = 1,
        label = "Rogue - Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 7, value = 5, previewText = "5",
        chargedSlots = { [1] = true, [2] = true } },
    { key = "shaman_elemental", specIndex = 1, label = "Shaman - Elemental Maelstrom", token = "MAELSTROM", mode = "continuous", segments = 1, value = 0.68,
        previewText = "68 / 100" },
    { key = "shaman_enhancement", specIndex = 2,
        label = "Shaman - Enhancement Maelstrom Weapon", token = "MAELSTROM", mode = "aura_segmented", segments = 10, value = 7, previewText = "7",
        threshold = 5, thresholdToken = "MAELSTROM_ABOVE_5" },
    { key = "warlock_soul_shards", specIndex = 1,
        label = "Warlock - Soul Shards", token = "SOUL_SHARDS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "warlock_destruction", specIndex = 3, label = "Warlock - Destruction Soul Shards", token = "SOUL_SHARDS", mode = "fractional", segments = 5,
        value = 3.4, previewText = "3.4" },
    { key = "warrior_whirlwind", specIndex = 2,
        label = "Warrior - Whirlwind Stacks", token = "WHIRLWIND", mode = "aura_segmented", segments = 4, value = 2, previewText = "2" },
    { key = "warrior_sweeping", specIndex = 1,
        label = "Warrior - Sweeping Strikes", token = "SWEEPING_STRIKES", mode = "aura_segmented", segments = 18, value = 12, previewText = "12" },
}
-- Preview the active provider's resources, including its Classic variants.
if MSUF.Client.IsMists then
    local replacements = {
        druid_balance = { token = "ECLIPSE_SOLAR", label = "Druid - Eclipse", mode = "continuous", segments = 1, value = 0.65,
            previewText = "65", enabled = true },
        mage_arcane = { mode = "aura_segmented" },
        monk_windwalker = { label = "Monk - Chi", segments = 5, value = 3, previewText = "3" },
        priest_shadow = { label = "Priest - Shadow Orbs", token = "SHADOW_ORBS", mode = "segmented", segments = 3, value = 2, previewText = "2" },
        warlock_soul_shards = { segments = 4 },
        warlock_destruction = { label = "Warlock - Burning Embers", token = "BURNING_EMBERS", segments = 4, value = 2.4, previewText = "2.4" },
    }
    for _, spec in ipairs(CLASS_POWER_PREVIEW_SPECS) do
        for key, value in pairs(replacements[spec.key] or {}) do spec[key] = value end
    end
    CLASS_POWER_PREVIEW_SPECS[#CLASS_POWER_PREVIEW_SPECS + 1] = {
        key = "warlock_demonic_fury", specIndex = 2, label = "Warlock - Demonic Fury", token = "DEMONIC_FURY",
        mode = "continuous", segments = 1, value = 0.65, previewText = "650 / 1000",
    }
end
if MSUF.Client.SupportsClassResource and not MSUF.Client.SupportsClassResource("CHARGED") then
    for _, spec in ipairs(CLASS_POWER_PREVIEW_SPECS) do
        if spec.key == "rogue_combo" then
            spec.segments, spec.value, spec.previewText, spec.chargedSlots = 5, 3, "3", nil
        end
    end
end
local CLASS_POWER_PREVIEW_BY_KEY = {}
local CLASS_POWER_PREVIEW_VALUES = {}
for i = 1, #CLASS_POWER_PREVIEW_SPECS do
    local spec = CLASS_POWER_PREVIEW_SPECS[i]
    if not MSUF.Client.SupportsClassResource or MSUF.Client.SupportsClassResource(spec.token or "NO_CLASS_BAR") then
        CLASS_POWER_PREVIEW_BY_KEY[spec.key] = spec
        CLASS_POWER_PREVIEW_VALUES[#CLASS_POWER_PREVIEW_VALUES + 1] = { value = spec.key, text = spec.label }
    end
end
local function NormalizeClassPowerPreviewSpecKey(key)
    key = tostring(key or "rogue_combo")
    return CLASS_POWER_PREVIEW_BY_KEY[key] and key or "rogue_combo"
end
local CLASS_POWER_PREVIEW_CLASS_BY_PREFIX = { deathknight = "DEATHKNIGHT", demonhunter = "DEMONHUNTER", druid = "DRUID", evoker = "EVOKER", hunter = "HUNTER",
    mage = "MAGE", monk = "MONK", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
local function ClassPowerPreviewClassTokenForSpec(spec)
    if spec and spec.classToken then return tostring(spec.classToken):upper() end
    if spec and spec.class then return tostring(spec.class):upper() end
    local key = tostring(spec and spec.key or M.GetClassPowerPreviewSpecKey())
    local prefix = key:match("^([^_]+)")
    return prefix and CLASS_POWER_PREVIEW_CLASS_BY_PREFIX[prefix] or nil
end
local function RequestClassPowerPreviewRefresh()
    RefreshClassPowerInlinePreview()
    Core.RequestPreviewRefresh("MSUF2_CLASSPOWER_PREVIEW_SPEC")
end
function M.GetClassPowerPreviewSpecKey() return NormalizeClassPowerPreviewSpecKey(M._msuf2ClassPowerPreviewSpecKey or "rogue_combo") end
function M.SetClassPowerPreviewSpecKey(key)
    key = NormalizeClassPowerPreviewSpecKey(key)
    if M._msuf2ClassPowerPreviewSpecKey == key then return true, key end
    M._msuf2ClassPowerPreviewSpecKey = key
    RequestClassPowerPreviewRefresh()
    return true, key
end
function M.GetClassPowerPreviewSpec() return CLASS_POWER_PREVIEW_BY_KEY[M.GetClassPowerPreviewSpecKey()] end
function M.GetClassPowerPreviewClassToken() return ClassPowerPreviewClassTokenForSpec(M.GetClassPowerPreviewSpec()) end
M.ClassPowerPreviewSpecValues = CLASS_POWER_PREVIEW_VALUES
M.ClassPowerPreviewSpecs = CLASS_POWER_PREVIEW_BY_KEY
RefreshClassPowerInlinePreview = RefreshClassPowerInlinePreview(function()
    local preview = M._msuf2ClassPowerInlinePreview
    if preview and preview.Refresh then preview:Refresh() end
end)
local APPLY_DETACHED_POWER = { preview = true, power = true, detachedPowerBar = true, applyAll = false, unit = "player", classpowerApplied = true }
local APPLY_DETACHED_POWER_TEXT = { preview = true, power = true, text = true, fonts = true, applyAll = false, unit = "player", classpowerApplied = true }
-- detachedPowerBarWidthMode lives in the shared bars table and is compiled for
-- Player, Target, and Focus. Route only this global control through the
-- all-Power cold path; the remaining controls on this page stay Player-scoped.
local APPLY_DETACHED_POWER_WIDTH_MODE = { preview = true, power = true, applyAll = false, classpowerApplied = true }
local APPLY_PLAYER_HP = { preview = true, applyAll = false, classpower = true, classpowerApplied = true }
local CP_APPLY_DETACHED_POWER = { anchor = true, cdm = true, playerHP = true, syncNow = false }
local CP_APPLY_PLAYER_HP = { playerHP = true }
local CP_APPLY_PLAYER_HP_TEXTURES = { playerHPTextures = true }

local function ApplyClassPowerPage(reason, flags, runtime)
    RefreshClassPowerInlinePreview()
    return Core.ApplyService.RequestClassPowerDomains(reason or "MSUF2_CLASSPOWER_PAGE", runtime, flags)
end
local function ApplyDetachedPowerBar() ApplyClassPowerPage("MSUF2_DETACHED_POWER_BAR", APPLY_DETACHED_POWER, CP_APPLY_DETACHED_POWER) end
local function ApplyDetachedPowerSource()
    Core.EnsureCooldownWidthObservers()
    ApplyDetachedPowerBar()
end
local function ApplyDetachedPowerWidthMode()
    Core.EnsureCooldownWidthObservers()
    ApplyClassPowerPage("MSUF2_DETACHED_POWER_WIDTH_MODE", APPLY_DETACHED_POWER_WIDTH_MODE, CP_APPLY_DETACHED_POWER)
end
--- Forward declaration: the smoothing handler below runs before the accessor
--- is defined further down, so the name has to exist as a local first.
local Player
local function ApplyDetachedPlayerPowerSmoothing()
    local player = Player()
    if player.powerSmoothFill == true then player.powerChunkedFill = false end
    RefreshClassPowerInlinePreview()
    M.RequestUnitDomains("player", "MSUF2_CLASSPOWER_PLAYER_POWER_SMOOTH", {
        preview = true, applyAll = false, power = true, classpowerApplied = true,
    })
end
local function ApplyDetachedPowerText()
    local db = M.EnsureDB()
    if db and db.player then
        db.player.hpPowerTextOverride = nil
        if type(M.SyncDirectPowerTextOffsets) == "function" then M.SyncDirectPowerTextOffsets(db.player) end
    end
    ApplyClassPowerPage("MSUF2_DETACHED_POWER_TEXT", APPLY_DETACHED_POWER_TEXT, CP_APPLY_PLAYER_HP)
end
local function ApplyDetachedPowerBarOutline()
    Core.ApplyService.RequestBarOutline("MSUF2_DETACHED_POWER_OUTLINE", "player")
    ApplyDetachedPowerBar()
end
local function ApplyPlayerHPBar() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP) end
local function ApplyPlayerHPTextures() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXTURES", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP_TEXTURES) end
local function ApplyPlayerHPText() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXT", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP) end
function Player()
    local db = M.EnsureDB()
    db.player = db.player or {}
    return db.player
end
--- An unset detached width falls through to the Player frame width at runtime
--- (see the Power element's width precedence), so the slider has to show that
--- rather than a constant, or it would advertise a width the bar never had.
local function PlayerFrameWidth()
    local width = tonumber(Player().width)
    if not width or width < 20 then width = 250 elseif width > 800 then width = 800 end
    return floor(width + 0.5)
end
local function PlayerPowerOutline()
    local outline = tonumber(Bars().detachedPowerBarOutline)
    if outline == nil then
        local player = Player()
        outline = player.powerBarBorderEnabled == true and (tonumber(player.powerBarBorderThickness) or 1) or 0
    end
    if outline < 0 then return 0 end
    if outline > 8 then return 8 end
    return floor(outline + 0.5)
end
local function SetPlayerPowerOutline(value, apply)
    value = floor((tonumber(value) or 0) + 0.5)
    if value < 0 then value = 0 elseif value > 8 then value = 8 end
    local function Write()
        local bars, player = Bars(), Player()
        local enabled, changed = value > 0, false
        if bars.detachedPowerBarOutline ~= value then bars.detachedPowerBarOutline, changed = value, true end
        if player.powerBarBorderEnabled ~= enabled then player.powerBarBorderEnabled, changed = enabled, true end
        if enabled and player.powerBarBorderThickness ~= value then player.powerBarBorderThickness, changed = value, true end
        if changed and type(apply) == "function" then apply() end
        return changed
    end
    if type(M.RunWithHistory) == "function" then
        return M.RunWithHistory("detachedPowerBarOutline", "classpower:detachedPowerBarOutline", Write)
    end
    return Write()
end
local function SetPlayerTextValue(key, value, apply)
    local player = Player()
    if player[key] == value then return end
    local function Write()
        local target = Player()
        if target[key] == value then return false end
        target[key] = value
        target.hpPowerTextOverride = nil
        if type(apply) == "function" then apply() end
        return true
    end
    if type(M.RunWithHistory) == "function" then return M.RunWithHistory(tostring(key), "classpower:detachedPowerText:" .. tostring(key), Write) end
    return Write()
end
local function PlayerPowerTextShown(player)
    player = player or Player()
    if player.showPowerText ~= nil then return player.showPowerText ~= false end
    return player.showPower ~= false
end
local function SetPlayerPowerTextShown(player, shown)
    player = player or Player()
    player.showPowerText = shown and true or false
end
local function NormalizeDetachedPowerTextPreset(player)
    player = player or Player()
    if not PlayerPowerTextShown(player) then return "OFF" end
    local left = tostring(player.powerTextLeft or "NONE"):upper()
    local center = tostring(player.powerTextCenter or player.powerTextMode or "CURPERCENT"):upper()
    local right = tostring(player.powerTextRight or "NONE"):upper()
    if left == "NONE" and right == "NONE" and DETACHED_POWER_TEXT_PRESETS[center] then return center end
    return "CUSTOM"
end
local function SetDetachedPowerTextPreset(value)
    value = tostring(value or "CURPERCENT"):upper()
    if value == "CUSTOM" then return end
    local player = Player()
    if value == "OFF" then
        SetPlayerPowerTextShown(player, false)
        return
    end
    if not DETACHED_POWER_TEXT_PRESETS[value] then value = "CURPERCENT" end
    SetPlayerPowerTextShown(player, true)
    player.detachedPowerBarTextOnBar = true
    player.powerTextLeft = "NONE"
    player.powerTextCenter = value
    player.powerTextRight = "NONE"
    player.powerTextMode = value
end
local QUICK_SETUP_FLAG = "quickSetupClassBarOffered"
local QUICK_CP_HEIGHT = 4
local QUICK_DPB_HEIGHT = 6
local QUICK_DPB_GAP = 4
local QUICK_CDM_GAP = 4
local QUICK_FALLBACK_Y_FRAC = 0.60
local QUICK_KEYS = {
    bars = M.WordList("showClassPower classPowerShape classPowerShapeAlign classPowerShowText classPowerTextMode classPowerAnchorToCooldown "
        .. "classPowerCooldownTopAnchor classPowerWidthMode showEleMaelstrom showEbonMight showChargedComboPoints runeShowTime runeShowTimeText "
        .. "classPowerOffsetX classPowerOffsetY classPowerOutline detachedPowerBarWidthMode smoothPowerBar chunkedPowerBar realtimePowerText "
        .. "classPowerSmoothFill altManaSmoothFill"),
    player = M.WordList("showPowerBar powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarWidth detachedPowerBarHeight "
        .. "detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarAnchorMode detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar "
        .. "detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower powerSmoothFill powerChunkedFill"),
}
M.ClassPowerWorkspace.QuickWriteKeys = QUICK_KEYS
local quickSetupUndoSnapshot
local quickSetupFirstRunChecked = false
local function QuickTr(text) return (M.Tr and M.Tr(text)) or text end
local function QuickSnapshot()
    local db = M.EnsureDB()
    local snapshot = {}
    for scope, keys in pairs(QUICK_KEYS) do
        local source, values = db[scope] or {}, {}
        for i = 1, #keys do values[keys[i]] = DeepCopyTable(source[keys[i]]) end
        snapshot[scope] = values
    end
    return snapshot
end
local function QuickRestore(snapshot)
    if type(snapshot) ~= "table" then return end
    local db = M.EnsureDB()
    for scope, keys in pairs(QUICK_KEYS) do
        db[scope] = db[scope] or {}
        local values = snapshot[scope] or {}
        for i = 1, #keys do
            local key = keys[i]
            db[scope][key] = DeepCopyTable(values[key])
        end
    end
end
local function QuickGetVisibleCDM()
    local ecv = Core.GetEffectiveCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
    if not MSUF.Client.IsClassic then
        return Core.GetUsableCooldownAnchorSize(ecv, true) and ecv or nil
    end
    if ecv and ecv.IsShown and ecv:IsShown() and ecv.GetHeight and ecv.GetCenter then
        local h = ecv:GetHeight()
        if type(h) == "number" and h > 0 then return ecv end
    end
    return nil
end
local function QuickPlayerFrame()
    local uf = MSUF and MSUF.UF
    local frame = uf and type(uf.GetFrame) == "function" and uf.GetFrame("player") or nil
    return frame or (uf and uf.frames and uf.frames.player) or MSUF_player
end
local function QuickClassPowerVisible()
    local frame = MSUF_ClassPowerContainer
    return frame and frame.IsShown and frame:IsShown()
end
local function QuickCalcCPAboveCDM(ecv)
    if not MSUF.Client.IsClassic then
        -- Retail anchors to Essential's top edge. No viewer-height offset.
        return { cpOffsetX = 0, cpOffsetY = 0, anchorCPtoCDM = true }
    end
    local bars = Bars()
    local player = M.EnsureDB().player or {}
    local cpH = tonumber(bars.classPowerHeight) or QUICK_CP_HEIGHT
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local ecvH = (ecv and ecv.GetHeight and ecv:GetHeight()) or 0
    return {
        cpOffsetX = 0,
        cpOffsetY = math.ceil(ecvH + QUICK_CDM_GAP + cpH + QUICK_DPB_GAP + dpbH),
        anchorCPtoCDM = true,
    }
end
local function QuickCalcDPBAboveCDMNoCP(ecv)
    local player = M.EnsureDB().player or {}
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local fallback = { dpbOffsetX = 0, dpbOffsetY = -QUICK_DPB_GAP, anchorDPBtoCP = true }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetCenter and pf.GetBottom and pf.GetEffectiveScale
        and ecv and ecv.GetCenter and ecv.GetTop and ecv.GetEffectiveScale) then
        return fallback
    end
    local pfCenterX = select(1, pf:GetCenter())
    local pfBottom = pf:GetBottom()
    local ecvCenterX = select(1, ecv:GetCenter())
    local ecvTop = ecv:GetTop()
    if not (pfCenterX and pfBottom and ecvCenterX and ecvTop) then return fallback end
    local pfScale = pf:GetEffectiveScale() or 1
    local ecvScale = ecv:GetEffectiveScale() or 1
    if pfScale <= 0 then pfScale = 1 end
    if ecvScale <= 0 then ecvScale = 1 end
    local targetCenterX = ecvCenterX * ecvScale
    local targetTop = ecvTop * ecvScale + (QUICK_CDM_GAP + dpbH) * pfScale
    return {
        dpbOffsetX = floor((targetCenterX - pfCenterX * pfScale) / pfScale + 0.5),
        dpbOffsetY = floor((targetTop - pfBottom * pfScale) / pfScale + 0.5),
        anchorDPBtoCP = false,
    }
end
local function QuickCalcScreenCenter()
    local fallback = { cpOffsetX = 0, cpOffsetY = 0, anchorCPtoCDM = false }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetTop and pf.GetWidth and pf.GetEffectiveScale) then return fallback end
    local pfLeft, pfTop, pfW = pf:GetLeft(), pf:GetTop(), pf:GetWidth()
    if not (pfLeft and pfTop and pfW) then return fallback end
    local pfScale = (pf:GetEffectiveScale()) or 1
    if pfScale <= 0 then pfScale = 1 end
    local uip = UIParent
    local uipScale = (uip and uip.GetEffectiveScale and uip:GetEffectiveScale()) or 1
    if uipScale <= 0 then uipScale = 1 end
    local screenW = (uip and uip.GetWidth and uip:GetWidth()) or 1920
    local screenH = (uip and uip.GetHeight and uip:GetHeight()) or 1080
    local cpW = floor((pfW or 275) + 0.5)
    if cpW < 30 then cpW = 275 end
    return {
        cpOffsetX = floor((screenW * uipScale * 0.5) / pfScale - pfLeft - 2 - cpW * 0.5 + 0.5),
        cpOffsetY = floor((screenH * uipScale * QUICK_FALLBACK_Y_FRAC) / pfScale - pfTop + 2 + 0.5),
        anchorCPtoCDM = false,
    }
end
local function QuickApplyPhase1(offsets)
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    db.player = db.player or {}
    local bars = db.bars
    local player = db.player
    M.Assign(bars, {
        showClassPower = true, classPowerShowText = true, classPowerWidthMode = "cooldown", detachedPowerBarWidthMode = "cooldown",
        showEleMaelstrom = true, showEbonMight = true, showChargedComboPoints = true, runeShowTime = true, runeShowTimeText = true,
        classPowerOutline = 1,
        -- One-click always opts the managed Player power bar into native smooth
        -- interpolation and the high-frequency player power event contract.
        smoothPowerBar = true, chunkedPowerBar = false, realtimePowerText = true,
        classPowerSmoothFill = true, altManaSmoothFill = true,
    })
    bars.classPowerAnchorToCooldown = offsets.anchorCPtoCDM and true or false
    bars.classPowerCooldownTopAnchor = offsets.anchorCPtoCDM
        and not MSUF.Client.IsClassic and true or nil
    bars.classPowerOffsetX, bars.classPowerOffsetY = offsets.cpOffsetX, offsets.cpOffsetY
    M.Assign(player, {
        showPowerBar = true,
        powerBarDetached = true,
        detachedPowerBarAnchorToClassPower = true,
        detachedPowerBarSyncClassPower = true,
        detachedPowerBarShape = "BAR",
        detachedPowerOrbSize = tonumber(player.detachedPowerOrbSize) or 54,
        detachedPowerBarOffsetX = 0,
        detachedPowerBarOffsetY = -QUICK_DPB_GAP,
        detachedPowerBarAnchorMode = "CENTER",
        detachedPowerBarHeight = tonumber(player.detachedPowerBarHeight) or 6,
        detachedPowerBarFrameLevelOffset = tonumber(player.detachedPowerBarFrameLevelOffset) or 6,
        powerSmoothFill = true,
        powerChunkedFill = false,
    })
end
local function QuickApplyPhase2NoCP(offsets)
    local player = M.EnsureDB().player or {}
    player.detachedPowerBarSyncClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX = offsets.dpbOffsetX
    player.detachedPowerBarOffsetY = offsets.dpbOffsetY
end
local function QuickRefreshAll(reason)
    reason = reason or "ClassPowerQuickSetup"
    Core.EnsureCooldownWidthObservers()
    RefreshClassPowerInlinePreview()
    return Core.ApplyService.RequestClassPowerDomains(reason, CLASSPOWER_QUICK_RUNTIME, CLASSPOWER_QUICK_FLAGS)
end
local function QuickOffered(mark)
    local db = M.EnsureDB()
    db.general = db.general or {}
    if mark then db.general[QUICK_SETUP_FLAG] = true end
    return db.general and db.general[QUICK_SETUP_FLAG] == true
end
-- The result offers Undo; Escape must not answer it, so it is a menu-owned
-- prompt (M.ShowPrompt). The offer is Blizzard's generic confirmation.
local function ShowQuickSetupResult(popupText)
    M.ShowPrompt("MSUF2_CLASSPOWER_QUICK_RESULT", {
        text = QuickTr(popupText), accept = OKAY, cancel = QuickTr("Undo"), hideOnEscape = false,
        onAccept = function() quickSetupUndoSnapshot = nil end,
        onCancel = function()
            if not quickSetupUndoSnapshot then return end
            QuickRestore(quickSetupUndoSnapshot)
            quickSetupUndoSnapshot = nil
            QuickRefreshAll("ClassPowerQuickSetupUndo")
        end,
    })
end
local function ShowQuickSetupOffer()
    M.ShowPrompt("MSUF2_CLASSPOWER_QUICK_OFFER", {
        text = QuickTr("Welcome to Class Resources!\n\n"
            .. "Would you like to automatically set up a\n"
            .. "detached Class Bar positioned above your\n"
            .. "Essential Cooldowns?\n\n"
            .. "This configures class resource visibility,\n"
            .. "anchoring, width matching and detached\n"
            .. "Player Power in one click.\n\n"
            .. "You can always run this later via the\n"
            .. "|cff00ff00Quick Setup: Class Bar|r button below."),
        accept = QuickTr("Setup Now"), cancel = QuickTr("Not Now"), showAlert = true,
        onAccept = function()
            QuickOffered(true)
            C_Timer.After(0.05, function()
                MSUF.Require("MSUF2_ClassPowerQuickSetup", FILE)()
            end)
        end,
        onCancel = function() QuickOffered(true) end,
    })
end
local function ApplyQuickSetup()
    QuickOffered(true)
    local ecv = QuickGetVisibleCDM()
    local retail = not MSUF.Client.IsClassic
    local supportsCooldown = retail and MSUF.Require("MSUF_IsCooldownAnchorSupported", FILE)()
    local offsets = (ecv or supportsCooldown) and QuickCalcCPAboveCDM(ecv) or QuickCalcScreenCenter()
    quickSetupUndoSnapshot = QuickSnapshot()
    QuickApplyPhase1(offsets)
    ApplyClassPower()
    local popupText
    if ecv and not QuickClassPowerVisible() then
        if not retail then QuickApplyPhase2NoCP(QuickCalcDPBAboveCDMNoCP(ecv)) end
        popupText = "Quick Setup applied!\n\nYour spec has no visible class\nresource bar right now.\n\nPlayer Power follows above\nEssential Cooldowns.\nIf "
            .. "you respec, Class Resources will\nappear automatically."
    elseif ecv then
        popupText = "Quick Setup applied!\n\nClass Power is now positioned\nabove Essential Cooldowns.\n\nPlayer Power is detached and\nattached below it.\n"
            .. "Use Edit Mode for fine-tuning."
    elseif supportsCooldown then
        popupText = "Quick Setup applied!\n\nClass Resources and Player Power\nwill follow above Essential\nCooldowns when the bar appears.\nUntil then they "
            .. "use the Player\nframe or the saved position."
    else
        popupText = "Quick Setup applied!\n\nClass Power is detached and\npositioned at screen center.\n\nEssential Cooldowns not detected.\nPlayer Power is "
            .. "detached and\nattached below it.\n\nUse Edit Mode for fine-tuning."
    end
    QuickRefreshAll("ClassPowerQuickSetup")
    ShowQuickSetupResult(popupText)
end
local function ExecuteQuickSetup()
    return M.RunWithHistory("Quick Setup: Class Bar", "classpower:quick_setup", ApplyQuickSetup)
end
ExportPublic("MSUF2_ClassPowerQuickSetup", ExecuteQuickSetup)
ExportPublic("MSUF_QuickSetup_ResetFirstRun", function()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = nil
    quickSetupFirstRunChecked = false
end)
local function MaybeOfferQuickSetup()
    if quickSetupFirstRunChecked or QuickOffered() then return end
    quickSetupFirstRunChecked = true
    C_Timer.After(0.15, function()
        if not QuickOffered() then ShowQuickSetupOffer() end
    end)
end
local function BuildInlineClassPowerPreview(ctx, b)
    -- ClassPower preview was split into Preview/MSUF_Menu2_ClassPowerPreview.lua.
    -- Keeping only this loader guard prevents a second renderer from drifting out of sync.
    if ctx and ctx.hiddenBuild then
        local section = W.FixedPreviewSection(ctx, b, { title = "Preview", height = 64 })
        Schema.Build(ctx, section, { { "text", "menu2.classpower.preview.placeholder", nil,
            { "Class resource preview is built when this page is opened.", 14, -38, ctx.width - 28, T.colors.muted }, scope = "classpower" } })
        return section
    end
    local preview = M.ClassPowerStackPreview and M.ClassPowerStackPreview.Create
    if type(preview) == "function" then return preview(ctx, b) end
    return W.FixedPreviewSection(ctx, b, { title = "Preview", height = 64 })
end
local function Card(parent, title, ...)
    local section = parent
    while section and not section._msuf2SectionId do section = section:GetParent() end
    local id = "menu2.classpower.card." .. (section and section._msuf2SectionId or "style")
        .. "." .. tostring(title):lower():gsub("[^%w]+", ".")
    return Schema.Build(nil, parent, { { "card", id, nil, { title, ... },
        scope = "classpower", domain = "layout" } })[id]
end
local Page = {}
Page.__index = Page

local function PlaceColumn(parent, x, y, step, width, titleJustify, ...)
    for i = 1, select("#", ...) do MoveWidget(select(i, ...), parent, x, y - (i - 1) * step, width, titleJustify or "LEFT") end
end
local function HasPercent(mode) return tostring(mode or ""):find("PERCENT", 1, true) ~= nil end
local function HidePercentValue(source, key)
    if source and source[key] ~= nil then return source[key] == true end
    local db = M.EnsureDB and M.EnsureDB()
    return db and db.general and db.general.hidePercentSymbol == true
end
local function CurrentDetachedTextSlot()
    local slot = M.classPowerDetachedPowerTextSlot
    return (slot == "left" or slot == "right") and slot or "center"
end
local function DetachedTextOffsetKeys()
    if type(M.TextSlotOffsetKeys) == "function" then return M.TextSlotOffsetKeys("power", CurrentDetachedTextSlot()) end
    return "powerTextCenterOffsetX", "powerTextCenterOffsetY"
end
local function ShowQuickSetupTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(QuickTr("Quick Setup: Detached Class Bar"), 1, 1, 1)
    GameTooltip:AddLine(QuickTr("One-click setup for a ready-to-use class bar:"), .85, .85, .85, true)
    GameTooltip:AddLine(" ")
    for _, line in ipairs({ "Enables Class Resources", "Positions class bar ABOVE Essential Cooldowns", "Match width: Essential Cooldowns",
        "Does not change Player power bar" }) do
        GameTooltip:AddLine(QuickTr(line), .7, .7, .7, true)
    end
    local ecv = QuickGetVisibleCDM()
    local classPowerVisible = ecv and QuickClassPowerVisible()
    local status = classPowerVisible and "CDM + Class Power detected"
        or (ecv and "CDM detected (no class resource for this spec)" or "CDM not visible - will center on screen")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(QuickTr(status), classPowerVisible and .3 or .9, classPowerVisible and .9 or (ecv and .8 or .7), .3)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(QuickTr("Click to apply. Undo available in popup."), .5, .8, .5)
    GameTooltip:Show()
end


-- Lexical collaborators shared by the responsibility modules below this load site.
M.ClassPowerPageParts = {
    W = W,
    T = T,
    floor = floor,
    max = max,
    min = min,
    Bars = Bars,
    BoolValue = BoolValue,
    NumValue = NumValue,
    SetValue = SetValue,
    Schema = Schema,
    SetControlEnabled = SetControlEnabled,
    RegisterControl = RegisterControl,
    CLASSPOWER_SETTING_KEY_BY_PATH = CLASSPOWER_SETTING_KEY_BY_PATH,
    Meta = Meta,
    RegisterSegment = RegisterSegment,
    MoveWidget = MoveWidget,
    SetControlsEnabled = SetControlsEnabled,
    AddTooltip = AddTooltip,
    ApplyClassPower = ApplyClassPower,
    ApplyClassPowerSource = ApplyClassPowerSource,
    ApplyClassPowerVisuals = ApplyClassPowerVisuals,
    ApplyClassPowerSmoothing = ApplyClassPowerSmoothing,
    ApplyClassPowerText = ApplyClassPowerText,
    TextureValues = TextureValues,
    VT = VT,
    PLAYER_POWER_SOURCE_VALUES = PLAYER_POWER_SOURCE_VALUES,
    NormalizePlayerPowerSource = NormalizePlayerPowerSource,
    NormalizeClassPowerShape = NormalizeClassPowerShape,
    NormalizeClassPowerShapeAlign = NormalizeClassPowerShapeAlign,
    NormalizeDetachedPowerShape = NormalizeDetachedPowerShape,
    NormalizePlayerHPShape = NormalizePlayerHPShape,
    ResolvePlayerHPShape = ResolvePlayerHPShape,
    DETACHED_POWER_TEXT_PRESET_VALUES = DETACHED_POWER_TEXT_PRESET_VALUES,
    CLASS_POWER_TEXT_MODE_VALUES = CLASS_POWER_TEXT_MODE_VALUES,
    DETACHED_POWER_TEXT_OUTLINE_VALUES = DETACHED_POWER_TEXT_OUTLINE_VALUES,
    PLAYER_HP_ANCHOR_VALUES = PLAYER_HP_ANCHOR_VALUES,
    PLAYER_HP_WIDTH_VALUES = PLAYER_HP_WIDTH_VALUES,
    ALT_MANA_WIDTH_VALUES = ALT_MANA_WIDTH_VALUES,
    PLAYER_HP_SHAPE_VALUES = PLAYER_HP_SHAPE_VALUES,
    PLAYER_HP_COLOR_VALUES = PLAYER_HP_COLOR_VALUES,
    PLAYER_HP_TEXT_VALUES = PLAYER_HP_TEXT_VALUES,
    DETACHED_POWER_SLOT_VALUES = DETACHED_POWER_SLOT_VALUES,
    DETACHED_POWER_SEPARATORS = DETACHED_POWER_SEPARATORS,
    TEXT_SLOT_VALUES = TEXT_SLOT_VALUES,
    CLASS_POWER_PREVIEW_VALUES = CLASS_POWER_PREVIEW_VALUES,
    ApplyDetachedPowerBar = ApplyDetachedPowerBar,
    ApplyDetachedPowerSource = ApplyDetachedPowerSource,
    ApplyDetachedPowerWidthMode = ApplyDetachedPowerWidthMode,
    Player = Player,
    ApplyDetachedPlayerPowerSmoothing = ApplyDetachedPlayerPowerSmoothing,
    ApplyDetachedPowerText = ApplyDetachedPowerText,
    ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
    ApplyPlayerHPBar = ApplyPlayerHPBar,
    ApplyPlayerHPTextures = ApplyPlayerHPTextures,
    ApplyPlayerHPText = ApplyPlayerHPText,
    PlayerFrameWidth = PlayerFrameWidth,
    PlayerPowerOutline = PlayerPowerOutline,
    SetPlayerPowerOutline = SetPlayerPowerOutline,
    SetPlayerTextValue = SetPlayerTextValue,
    PlayerPowerTextShown = PlayerPowerTextShown,
    NormalizeDetachedPowerTextPreset = NormalizeDetachedPowerTextPreset,
    SetDetachedPowerTextPreset = SetDetachedPowerTextPreset,
    ExecuteQuickSetup = ExecuteQuickSetup,
    MaybeOfferQuickSetup = MaybeOfferQuickSetup,
    BuildInlineClassPowerPreview = BuildInlineClassPowerPreview,
    Card = Card,
    Page = Page,
    PlaceColumn = PlaceColumn,
    HasPercent = HasPercent,
    HidePercentValue = HidePercentValue,
    CurrentDetachedTextSlot = CurrentDetachedTextSlot,
    DetachedTextOffsetKeys = DetachedTextOffsetKeys,
    ShowQuickSetupTooltip = ShowQuickSetupTooltip,
}
