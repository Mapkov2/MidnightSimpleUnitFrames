-- Advanced class-resource settings. Runtime work stays behind the shared apply queue;
-- this file owns only saved-value bindings, page layout, and control-state dependencies.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min
local RefreshClassPowerInlinePreview = M.RefreshProxy()
local CallGlobal, Bars, BoolValue, NumValue, SetValue, DeepCopyTable, BuildTableControlSpecs, SwitchAt, SetControlEnabled, ControlMeta, RegisterControl = M.Pick(AP, [[CallGlobal Bars BoolValue NumValue SetValue DeepCopyTable BuildTableControlSpecs SwitchAt SetControlEnabled ControlMeta RegisterControl]])
local CLASSPOWER_SETTING_KEY_BY_PATH = {
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
    ["detached_power.layout.orbSize"] = "player.detachedPowerOrbSize",
    ["detached_power.layout.smooth_fill"] = "player.powerSmoothFill",
    ["detached_power.layout.sync"] = "player.detachedPowerBarSyncClassPower",
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
    ["style.text.font"] = "bars.classPowerFontSize",
    ["style.text.layer"] = "bars.classPowerTextLayer",
    ["style.text.textX"] = "bars.classPowerTextOffsetX",
    ["style.text.textY"] = "bars.classPowerTextOffsetY",
    ["visibility.out_of_combat"] = "bars.classPowerHideOOC",
    ["visibility.when_empty"] = "bars.classPowerHideWhenEmpty",
    ["visibility.when_full"] = "bars.classPowerHideWhenFull",
}
local CLASSPOWER_ACTION_KEY_BY_PATH = {
    ["quick_setup.class_bar"] = "class_power_quick_setup",
}
local CLASSPOWER_REVIEWED_BY_PATH = {
    ["detached_power.text.outline"] = {
        "dynamic",
        "Player text outline routes the Player font override plus the mutually exclusive bold/no-outline flags through one coordinated control.",
    },
    ["detached_power.text.preset"] = {
        "compound",
        "A detached-power text preset writes the Player power-text slot modes as one coordinated layout.",
    },
    ["detached_power.text.slot_offset.x"] = {
        "dynamic",
        "This offset targets the currently selected left, center, or right Player power-text slot.",
    },
    ["detached_power.text.slot_offset.y"] = {
        "dynamic",
        "This offset targets the currently selected left, center, or right Player power-text slot.",
    },
}
local CLASSPOWER_DYNAMIC_SETTING_KEYS_BY_PATH = {
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
    if exact.settingKey == nil and exact.actionKey == nil then
        local reviewed = CLASSPOWER_REVIEWED_BY_PATH[path]
        if reviewed then
            exact.assistantDisposition = reviewed[1]
            exact.assistantDispositionReason = reviewed[2]
            exact.assistantSettingKeys = CLASSPOWER_DYNAMIC_SETTING_KEYS_BY_PATH[path]
        end
    end
    return ControlMeta("classpower", "advanced", path, classification, exact)
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
    return segment
end
local MoveWidget = W.MoveWidget or AP.MoveWidget
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
    local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if ApplyService and type(ApplyService.RequestClassPower) == "function" then
        RefreshClassPowerInlinePreview()
        return ApplyService.RequestClassPower(reason or "MSUF2_CLASSPOWER", runtime, flags or APPLY_CLASSPOWER_GENERAL)
    end
    CallGlobal("MSUF_ClassPower_Apply", runtime)
    RefreshClassPowerInlinePreview()
    M.RequestGeneralApply(reason or "MSUF2_CLASSPOWER", flags or APPLY_CLASSPOWER_GENERAL)
end
local function ApplyClassPower() ApplyClassPowerRuntime("MSUF2_CLASSPOWER", CLASSPOWER_FULL, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerSource()
    CallGlobal("MSUF_EnsureCooldownWidthObservers")
    ApplyClassPower()
end
local function ApplyClassPowerVisuals() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_VISUALS", CLASSPOWER_VISUALS, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerSmoothing() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_SMOOTH", CLASSPOWER_SMOOTH, APPLY_CLASSPOWER_GENERAL) end
local function ApplyClassPowerText() ApplyClassPowerRuntime("MSUF2_CLASSPOWER_TEXT", CLASSPOWER_TEXT, APPLY_CLASSPOWER_GENERAL) end
local TextureValues = M.StatusBarTextureItems
local VT, VTP = M.ValueTextList, M.ValueTextPairs
local NormalizeClassPowerShape = CPPreview.NormalizeClassShape
local function NormalizeClassPowerShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
local function NormalizeDetachedPowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
local function NormalizePlayerHPShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "FOLLOW_POWER" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
local function ResolvePlayerHPShape(bars, db)
    local value = NormalizePlayerHPShape(bars and bars.playerHPBarShape)
    if value ~= "FOLLOW_POWER" then return CPPreview.ResolvePowerShape(value) end
    local player = db and db.player or nil
    if not (player and player.powerBarDetached == true) then return "BAR" end
    return CPPreview.ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars and bars.classPowerShape)
end
local DETACHED_POWER_TEXT_PRESET_VALUES = VTP "OFF=Off|CURRENT=Current|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current + Percent|CURMAXPERCENT=Current / Max + Percent|CUSTOM=Custom Slots"
local DETACHED_POWER_TEXT_OUTLINE_VALUES = VTP "OUTLINE=Outline|THICKOUTLINE=Thick Outline|NONE=None"
local PLAYER_HP_ANCHOR_VALUES = VTP "CLASS_TOP=Above Class Resource|CLASS_BOTTOM=Below Class Resource|POWER_TOP=Above Player Power|POWER_BOTTOM=Below Player Power"
local PLAYER_HP_WIDTH_VALUES = VTP "class=Class Resource|power=Player Power|player=Player Frame|custom=Custom"
local ALT_MANA_WIDTH_VALUES = VTP "player=Player Frame|custom=Custom"
local PLAYER_HP_SHAPE_VALUES = VTP "BAR=Bar|FOLLOW_POWER=Follow Player Power|ROUND=Round|CRYSTAL=Crystal|ORB=Orb"
local PLAYER_HP_COLOR_VALUES = VTP "GLOBAL=Global|CLASS=Class Color|DARK=Dark Mode|GRADIENT=HP Gradient"
local PLAYER_HP_TEXT_VALUES = VTP "PERCENT=Percent|CURRENT=Current|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max|NONE=None"
local DETACHED_POWER_SLOT_VALUES = VTP "CURRENT=Current|MAX=Max|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|NONE=None"
local DETACHED_POWER_SEPARATORS = VT("", "space", "-", "-", "/", "/", "\\", "\\", "|", "|", "<", "<", ">", ">", "~", "~", ":", ":")
local PLAYER_HP_SEPARATORS = DETACHED_POWER_SEPARATORS
local TEXT_SLOT_VALUES = VT("left", "Left", "center", "Center", "right", "Right")
local DETACHED_POWER_TEXT_PRESETS = M.KeySetFromWords "CURRENT CURMAX PERCENT CURPERCENT CURMAXPERCENT"
local CLASS_POWER_PREVIEW_SPECS = {
    { key = "deathknight_runes", label = "Death Knight - Runes", token = "RUNES", mode = "rune", segments = 6, value = 3, previewText = "3", runeDuration = 10 },
    { key = "demonhunter_devourer", label = "Demon Hunter - Soul Fragments", token = "SOUL_FRAGMENTS", mode = "aura_segmented", segments = 5, value = 3, previewText = "3" },
    { key = "demonhunter_vengeance", label = "Demon Hunter - Vengeance Fragments", token = "SOUL_FRAGMENTS_VENG", mode = "aura_segmented", segments = 6, value = 4, previewText = "4 / 6" },
    { key = "druid_feral", label = "Druid - Feral Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "druid_guardian", label = "Druid - Guardian Ironfur", token = "IRONFUR", mode = "ironfur", segments = 1, value = 0.72, previewText = "3" },
    { key = "druid_balance", label = "Druid - Balance (no class bar)", mode = "none", enabled = false },
    { key = "evoker_essence", label = "Evoker - Essence", token = "ESSENCE", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "evoker_augmentation_ebon", label = "Evoker - Augmentation Ebon Might", token = "ESSENCE", mode = "segmented", segments = 6, value = 4, previewText = "4",
        secondaryTimer = { token = "EBON_MIGHT", mode = "timer_bar", segments = 1, value = 0.6, previewText = "12.0", nativeDurationText = true } },
    { key = "hunter_survival_tip", label = "Hunter - Survival Tip of the Spear", token = "TIP_OF_THE_SPEAR", mode = "aura_segmented", segments = 3, value = 2, previewText = "2" },
    { key = "mage_arcane", label = "Mage - Arcane Charges", token = "ARCANE_CHARGES", mode = "segmented", segments = 4, value = 3, previewText = "3" },
    { key = "mage_frost", label = "Mage - Frost Icicles", token = "ICICLES", mode = "aura_segmented", segments = 5, value = 3, previewText = "3" },
    { key = "monk_brewmaster", label = "Monk - Brewmaster Stagger", token = "STAGGER_YELLOW", mode = "stagger", segments = 1, value = 0.42, previewText = "14K" },
    { key = "monk_windwalker", label = "Monk - Windwalker Chi", token = "CHI", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "paladin_holy_power", label = "Paladin - Holy Power", token = "HOLY_POWER", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "priest_shadow", label = "Priest - Shadow Insanity", token = "INSANITY", mode = "continuous", segments = 1, value = 0.62, previewText = "62 / 100" },
    { key = "rogue_combo", label = "Rogue - Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 7, value = 5, previewText = "5", chargedSlots = { [1] = true, [2] = true } },
    { key = "shaman_elemental", label = "Shaman - Elemental Maelstrom", token = "MAELSTROM", mode = "continuous", segments = 1, value = 0.68, previewText = "68 / 100" },
    { key = "shaman_enhancement", label = "Shaman - Enhancement Maelstrom Weapon", token = "MAELSTROM", mode = "aura_segmented", segments = 10, value = 7, previewText = "7", threshold = 5, thresholdToken = "MAELSTROM_ABOVE_5" },
    { key = "warlock_soul_shards", label = "Warlock - Soul Shards", token = "SOUL_SHARDS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "warlock_destruction", label = "Warlock - Destruction Soul Shards", token = "SOUL_SHARDS", mode = "fractional", segments = 5, value = 3.4, previewText = "3.4" },
    { key = "warrior_whirlwind", label = "Warrior - Whirlwind Stacks", token = "WHIRLWIND", mode = "aura_segmented", segments = 4, value = 2, previewText = "2" },
}
local CLASS_POWER_PREVIEW_BY_KEY = {}
local CLASS_POWER_PREVIEW_VALUES = {}
for i = 1, #CLASS_POWER_PREVIEW_SPECS do
    local spec = CLASS_POWER_PREVIEW_SPECS[i]
    CLASS_POWER_PREVIEW_BY_KEY[spec.key] = spec
    CLASS_POWER_PREVIEW_VALUES[i] = { value = spec.key, text = spec.label }
end
local function NormalizeClassPowerPreviewSpecKey(key) key = tostring(key or "rogue_combo"); return CLASS_POWER_PREVIEW_BY_KEY[key] and key or "rogue_combo" end
local CLASS_POWER_PREVIEW_CLASS_BY_PREFIX = { deathknight = "DEATHKNIGHT", demonhunter = "DEMONHUNTER", druid = "DRUID", evoker = "EVOKER", hunter = "HUNTER", mage = "MAGE", monk = "MONK", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
local function ClassPowerPreviewClassTokenForSpec(spec)
    if spec and spec.classToken then return tostring(spec.classToken):upper() end
    if spec and spec.class then return tostring(spec.class):upper() end
    local key = tostring(spec and spec.key or M.GetClassPowerPreviewSpecKey())
    local prefix = key:match("^([^_]+)")
    return prefix and CLASS_POWER_PREVIEW_CLASS_BY_PREFIX[prefix] or nil
end
local function RequestClassPowerPreviewRefresh()
    RefreshClassPowerInlinePreview()
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh("MSUF2_CLASSPOWER_PREVIEW_SPEC")
    elseif type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF2_CLASSPOWER_PREVIEW_SPEC", { preview = true, applyAll = false, notify = false, classpower = true })
    end
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
local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step, metadata)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    local opts = {}
    if type(metadata) == "table" then for metaKey, value in pairs(metadata) do opts[metaKey] = value end end
    opts.step, opts.roundStep = step or 5, true
    M.BindNumberWidget(ctx, slider,
        function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end,
        function(v)
            v = tonumber(v) or ((default or 0) * 100)
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            SetValue(Bars(), key, v / 100, apply)
        end,
        (default or 0) * 100, opts)
    return slider
end
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
    local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if ApplyService and type(ApplyService.RequestClassPower) == "function" then
        RefreshClassPowerInlinePreview()
        return ApplyService.RequestClassPower(reason or "MSUF2_CLASSPOWER_PAGE", runtime, flags)
    end
    CallGlobal("MSUF_ClassPower_Apply", runtime)
    RefreshClassPowerInlinePreview()
    if type(flags) == "table" and flags.unit and type(M.RequestUnitApply) == "function" then
        M.RequestUnitApply(flags.unit, reason, flags)
    else
        M.RequestGeneralApply(reason, flags)
    end
end
local function ApplyDetachedPowerBar() ApplyClassPowerPage("MSUF2_DETACHED_POWER_BAR", APPLY_DETACHED_POWER, CP_APPLY_DETACHED_POWER) end
local function ApplyDetachedPowerSource()
    CallGlobal("MSUF_EnsureCooldownWidthObservers")
    ApplyDetachedPowerBar()
end
local function ApplyDetachedPowerWidthMode()
    CallGlobal("MSUF_EnsureCooldownWidthObservers")
    ApplyClassPowerPage("MSUF2_DETACHED_POWER_WIDTH_MODE", APPLY_DETACHED_POWER_WIDTH_MODE, CP_APPLY_DETACHED_POWER)
end
local function ApplyDetachedPlayerPowerSmoothing()
    local player = Player()
    if player.powerSmoothFill == true then player.powerChunkedFill = false end
    RefreshClassPowerInlinePreview()
    M.RequestUnitApply("player", "MSUF2_CLASSPOWER_PLAYER_POWER_SMOOTH", {
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
    local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if ApplyService and type(ApplyService.RequestBarOutline) == "function" then
        ApplyService.RequestBarOutline("MSUF2_DETACHED_POWER_OUTLINE", "player")
    else
        CallGlobal("MSUF_ApplyBarOutlineThickness_All", "player")
    end
    ApplyDetachedPowerBar()
end
local function ApplyPlayerHPBar() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP) end
local function ApplyPlayerHPTextures() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXTURES", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP_TEXTURES) end
local function ApplyPlayerHPText() ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXT", APPLY_PLAYER_HP, CP_APPLY_PLAYER_HP) end
local function Player()
    local db = M.EnsureDB()
    db.player = db.player or {}
    return db.player
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
local function SetPlayerPowerTextShown(player, shown) player = player or Player(); player.showPowerText = shown and true or false end
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
    bars = M.WordList [[showClassPower classPowerShape classPowerShapeAlign classPowerShowText classPowerAnchorToCooldown classPowerWidthMode showEleMaelstrom showEbonMight showChargedComboPoints runeShowTime runeShowTimeText classPowerOffsetX classPowerOffsetY classPowerOutline detachedPowerBarWidthMode smoothPowerBar chunkedPowerBar realtimePowerText classPowerSmoothFill altManaSmoothFill]],
    player = M.WordList [[showPowerBar powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarWidth detachedPowerBarHeight detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarAnchorMode detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower powerSmoothFill powerChunkedFill]],
}
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
    local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
        or _G.EssentialCooldownViewer
    if ecv and ecv.IsShown and ecv:IsShown() and ecv.GetHeight and ecv.GetCenter then
        local h = ecv:GetHeight()
        if type(h) == "number" and h > 0 then return ecv end
    end
    return nil
end
local function QuickPlayerFrame()
    local uf = MSUF and MSUF.UF
    local frame = uf and type(uf.GetFrame) == "function" and uf.GetFrame("player") or nil
    return frame or (uf and uf.frames and uf.frames.player) or _G.MSUF_player
end
local function QuickClassPowerVisible() local frame = _G.MSUF_ClassPowerContainer; return frame and frame.IsShown and frame:IsShown() end
local function QuickCalcCPAboveCDM(ecv)
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
    CallGlobal("MSUF_EnsureCooldownWidthObservers")
    local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if ApplyService and type(ApplyService.RequestClassPower) == "function" then
        RefreshClassPowerInlinePreview()
        return ApplyService.RequestClassPower(reason, CLASSPOWER_QUICK_RUNTIME, CLASSPOWER_QUICK_FLAGS)
    end
    ApplyClassPower()
    if not CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", "player", true) then
        CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    end
    CallGlobal("MSUF_ClassPower_Apply", { playerHP = true })
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", "player", false, true, reason)
end
local function QuickOffered(mark)
    local db = M.EnsureDB()
    db.general = db.general or {}
    if mark then db.general[QUICK_SETUP_FLAG] = true end
    return db.general and db.general[QUICK_SETUP_FLAG] == true
end
local function QuickEnsurePopups()
    if not _G.StaticPopupDialogs then return end
    M.InstallStaticPopup("MSUF2_CLASSPOWER_QUICK_RESULT", {
        text = "%s", button1 = OKAY, button2 = QuickTr("Undo"), hideOnEscape = false,
        OnAccept = function() quickSetupUndoSnapshot = nil end,
        OnCancel = function()
            if not quickSetupUndoSnapshot then return end
            QuickRestore(quickSetupUndoSnapshot)
            quickSetupUndoSnapshot = nil
            QuickRefreshAll("ClassPowerQuickSetupUndo")
        end,
    })
    M.InstallStaticPopup("MSUF2_CLASSPOWER_QUICK_OFFER", {
        text = QuickTr("Welcome to Class Resources!\n\n"
            .. "Would you like to automatically set up a\n"
            .. "detached Class Bar positioned above your\n"
            .. "Essential Cooldowns?\n\n"
            .. "This configures class resource visibility,\n"
            .. "anchoring, width matching and detached\n"
            .. "Player Power in one click.\n\n"
            .. "You can always run this later via the\n"
            .. "|cff00ff00Quick Setup: Class Bar|r button below."),
        button1 = QuickTr("Setup Now"), button2 = QuickTr("Not Now"), hideOnEscape = true, showAlert = true,
        OnAccept = function()
            QuickOffered(true)
            C_Timer.After(0.05, function()
                if _G.MSUF2_ClassPowerQuickSetup then _G.MSUF2_ClassPowerQuickSetup() end
            end)
        end,
        OnCancel = function() QuickOffered(true) end,
    })
end
local function ExecuteQuickSetup()
    QuickEnsurePopups()
    QuickOffered(true)
    local ecv = QuickGetVisibleCDM()
    local offsets = ecv and QuickCalcCPAboveCDM(ecv) or QuickCalcScreenCenter()
    quickSetupUndoSnapshot = QuickSnapshot()
    QuickApplyPhase1(offsets)
    ApplyClassPower()
    local popupText
    if ecv and not QuickClassPowerVisible() then
        QuickApplyPhase2NoCP(QuickCalcDPBAboveCDMNoCP(ecv))
        popupText = "Quick Setup applied!\n\nYour spec has no visible class\nresource bar right now.\n\nPlayer Power is positioned above\nEssential Cooldowns.\nIf you respec, Class Resources will\nappear automatically."
    elseif ecv then
        popupText = "Quick Setup applied!\n\nClass Power is now positioned\nabove Essential Cooldowns.\n\nPlayer Power is detached and\nattached below it.\nUse Edit Mode for fine-tuning."
    else
        popupText = "Quick Setup applied!\n\nClass Power is detached and\npositioned at screen center.\n\nEssential Cooldowns not detected.\nPlayer Power is detached and\nattached below it.\n\nUse Edit Mode for fine-tuning."
    end
    QuickRefreshAll("ClassPowerQuickSetup")
    if StaticPopup_Show then StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_RESULT", QuickTr(popupText)) end
end
_G.MSUF2_ClassPowerQuickSetup = ExecuteQuickSetup
ExportPublic("MSUF_QuickSetup_ResetFirstRun", function()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = nil
    quickSetupFirstRunChecked = false
end)
local function MaybeOfferQuickSetup()
    if quickSetupFirstRunChecked or QuickOffered() then return end
    quickSetupFirstRunChecked = true
    QuickEnsurePopups()
    C_Timer.After(0.15, function()
        if not QuickOffered() and StaticPopup_Show then StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER") end
    end)
end
local function BuildInlineClassPowerPreview(ctx, b)
    -- ClassPower preview was split into Preview/MSUF_Menu2_ClassPowerPreview.lua.
    -- Keeping only this loader guard prevents a second renderer from drifting out of sync.
    if ctx and ctx.hiddenBuild then
        local section = W.FixedPreviewSection(ctx, b, { title = "Preview", height = 64 })
        W.Text(section, "Class resource preview is built when this page is opened.", 14, -38, ctx.width - 28, T.colors.muted)
        return section
    end
    local preview = M.ClassPowerStackPreview and M.ClassPowerStackPreview.Create
    if type(preview) == "function" then return preview(ctx, b) end
    return W.FixedPreviewSection(ctx, b, { title = "Preview", height = 64 })
end
local Page = {}
Page.__index = Page

local function PlaceColumn(parent, x, y, step, width, titleJustify, ...)
    for i = 1, select("#", ...) do MoveWidget(select(i, ...), parent, x, y - (i - 1) * step, width, titleJustify) end
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
    for _, line in ipairs({ "Enables Class Resources", "Positions class bar ABOVE Essential Cooldowns", "Match width: Essential Cooldowns", "Does not change Player power bar" }) do
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

function Page.New(ctx)
    local groups = {}
    for _, key in ipairs({ "cp", "cpText", "detached", "detachedPlayer", "detachedText", "detachedSlot", "hp", "hpText", "hpCustomText", "hpTextPosition", "hpManual", "hpOrb", "hpTexture", "altMana" }) do groups[key] = {} end
    local self = setmetatable({ ctx = ctx, b = W.PageBuilder(ctx), width = ctx.width or 900, groups = groups, refresh = M.RefreshProxy() }, Page)
    self.kinds = self:CreateControlKinds()
    return self
end
function Page:Add(group, ...) M.AppendValues(self.groups[group], ...) end
function Page:AddNamed(group, controls, names) M.AppendNamedValues(self.groups[group], controls, names) end
function Page:WithRefresh(apply)
    return function(...)
        apply(...)
        self.refresh()
    end
end
function Page:Controls(parent, source, apply, prefix, specs)
    for i = 1, #specs do specs[i].meta = specs[i].meta or Meta(prefix .. "." .. tostring(specs[i][1])) end
    local controls = BuildTableControlSpecs(self.ctx, parent, source, apply, specs, self.kinds)
    for i = 1, #specs do
        local spec, control = specs[i], controls[specs[i][1]]
        if spec.help then AddTooltip(control, spec.helpTitle or spec[3], spec.help) end
        for group in tostring(spec.group or ""):gmatch("%S+") do self:Add(group, control) end
    end
    return controls
end
function Page:SourceToggle(parent, label, source, key, apply, prefix)
    local control = W.Toggle(parent, label)
    M.BindBoolWidget(self.ctx, control, function() return HidePercentValue(source(), key) end,
        function(value)
            value = value and true or false
            if source == Player then SetPlayerTextValue(key, value, apply) else SetValue(source(), key, value, apply) end
        end, Meta(prefix .. "." .. key))
    return control
end

function Page:CreateControlKinds()
    return {
        playerPowerOutline = function(_, parent, _, apply, spec)
            local control = W.Slider(parent, spec[3], spec[4], spec[5], spec[6], spec[7])
            M.BindNumberWidget(self.ctx, control, PlayerPowerOutline,
                function(value) SetPlayerPowerOutline(value, spec[10] or apply) end,
                spec[9], spec.meta)
            return control
        end,
        alpha = function(_, parent, _, apply, spec)
            return BindBarsAlphaPercent(self.ctx, parent, spec[3], spec[4], spec[5], spec[6] or apply, spec[7], spec.meta)
        end,
        nilDefaultDropdown = function(_, parent, source, apply, spec)
            local control, key, default = W.Dropdown(parent, spec[3], spec[4], spec[5]), spec[6], spec[7]
            apply = spec[8] or apply
            M.BindDropdownWidget(self.ctx, control, function() return source()[key] or default end,
                function(value) source()[key] = value ~= default and value or nil; apply() end, spec.meta)
            return control
        end,
        detachedTextOnBar = function(_, parent, source, apply, spec)
            local control, key, default = W.Toggle(parent, spec[3]), spec[4], spec[5]
            apply = spec[6] or apply
            M.BindBoolWidget(self.ctx, control, function() return PlayerPowerTextShown(source()) and BoolValue(source(), key, default) end,
                function(value)
                    local function Write()
                        local player, changed = source(), false
                        value = value and true or false
                        if player[key] ~= value then player[key], changed = value, true end
                        if value and player.showPowerText ~= true then SetPlayerPowerTextShown(player, true); changed = true end
                        if changed then apply() end
                        return changed
                    end
                    if type(M.RunWithHistory) == "function" then return M.RunWithHistory(tostring(key), "classpower:detachedPowerText:" .. key, Write) end
                    return Write()
                end, spec.meta)
            return control
        end,
        detachedTextPreset = function(_, parent, _, apply, spec)
            local control = W.Dropdown(parent, spec[3], spec[4], spec[5])
            apply = spec[6] or apply
            M.BindDropdownWidget(self.ctx, control, function() return NormalizeDetachedPowerTextPreset(Player()) end,
                function(value) SetDetachedPowerTextPreset(value); apply(); self.refresh() end, spec.meta)
            return control
        end,
    }
end

function Page:BuildHeader()
    local b, ctx = self.b, self.ctx
    local head = T.Panel(b.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(head, "status")
    head:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    head:SetSize(b.width, 54)
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, head, "Class resource preview and quick setup") end
    head._msuf2Width, b.y = b.width, b.y - 62
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(b.y) + 28) end
    local desiredPreviewW = min(330, max(180, self.width - 438))
    local previewW = min(desiredPreviewW, max(120, self.width - 316))
    local preview = W.Dropdown(head, "Preview resource", CLASS_POWER_PREVIEW_VALUES, previewW)
    RegisterControl(preview, Meta("preview.resource", "setting", {
        settingKey = "menu.classPowerPreviewResource",
    }), "Preview resource", "dropdown", CLASS_POWER_PREVIEW_VALUES)
    MoveWidget(preview, head, 14, -15, previewW)
    preview:SetOnValueChanged(function(value) M.SetClassPowerPreviewSpecKey(value); preview:SetValue(M.GetClassPowerPreviewSpecKey()) end)
    preview:SetValue(M.GetClassPowerPreviewSpecKey())
    AddTooltip(preview, "Class Resource Preview", "Shows the selected class/spec resource below without changing your character, spec or saved settings.")
    M.TrackRefresh(ctx, function() preview:SetValue(M.GetClassPowerPreviewSpecKey()) end)
    local quick = T.Button(head, "Quick Setup: Class Bar", 158, 24)
    if W.StyleTopSuccessButton then W.StyleTopSuccessButton(quick) elseif W.StyleTopActionButton then W.StyleTopActionButton(quick) end
    quick:SetPoint("TOPRIGHT", head, "TOPRIGHT", -16, -16)
    quick:SetScript("OnClick", ExecuteQuickSetup)
    quick:SetScript("OnEnter", ShowQuickSetupTooltip)
    quick:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    RegisterControl(quick, Meta("quick_setup.class_bar", "action", { confirmRequired = true }), "Quick Setup: Class Bar", "button")
    -- Dock the selector strip like the unit pages' Editing strip and the
    -- Colors category bar: both selector and preview occupy the fixed stack,
    -- in that order, before the settings ScrollFrame begins.
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(head, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = b,
            ctx = ctx,
            flowGap = 8,
        })
    end
end

function Page:BuildClassLayout()
    local compact, width = self.width < 620, self.width
    local section = self.b:CollapsibleSection("classpower_display", "Layout", compact and 760 or 440, true)
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    local applySourceRefresh = self:WithRefresh(ApplyClassPowerSource)
    self.cpEnable = SwitchAt(self.ctx, section, "Class Resource", 32, -64, 180, Bars, "showClassPower", true, applySourceRefresh, Meta("layout.enabled"))
    self.cp = self:Controls(section, Bars, ApplyClassPower, "layout", {
        { "shape", "dropdown", "Class Resource shape", VT("BAR", "Bar", "CIRCLE", "Circle", "DIAMOND", "Diamond", "HEX", "Hex"), 260, "classPowerShape", "BAR", applyRefresh },
        { "height", "slider", "Height", 1, 40, 1, 300, "classPowerHeight", 4 },
        { "widthMode", "dropdown", "Width mode", VT("player", "Player frame", "auto_pips", "Auto fit pips", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs", "custom", "Custom"), 260, "classPowerWidthMode", "player", applySourceRefresh,
            help = "Auto fit pips is active only for Circle, Diamond and Hex. It uses pip count x pip size plus gaps." },
        { "width", "slider", "Width", 30, 800, 1, 300, "classPowerWidth", 0 },
        { "x", "slider", "Offset X", -800, 800, 1, 300, "classPowerOffsetX", 0 },
        { "y", "slider", "Offset Y", -800, 800, 1, 300, "classPowerOffsetY", 0 },
        { "level", "slider", "Class Resource layer", 0, 30, 1, 300, "classPowerFrameLevelOffset", 5 },
    })
    local alignValues = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right")
    self.cpAlign = W.Segment(section, "Shape alignment", alignValues, 300)
    M.BindSegment(self.ctx, self.cpAlign, function() return NormalizeClassPowerShapeAlign(Bars().classPowerShapeAlign) end,
        function(value) Bars().classPowerShapeAlign = NormalizeClassPowerShapeAlign(value); ApplyClassPower() end, Meta("layout.shape_alignment"))
    RegisterSegment(self.cpAlign, "layout.shape_alignment", alignValues, "setting")
    self:Add("cp", self.cp.shape, self.cp.height, self.cp.widthMode, self.cpAlign, self.cp.x, self.cp.y, self.cp.level)
    self.cpPowerShape = W.Dropdown(section, "Powerbar shape (independent)", VT("BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal", "ORB", "Orb"), 300)
    M.BindDropdownWidget(self.ctx, self.cpPowerShape,
        function() return NormalizeDetachedPowerShape(Player().detachedPowerBarShape) end,
        function(value)
            local player = Player()
            player.detachedPowerBarShape = NormalizeDetachedPowerShape(value)
            if player.detachedPowerBarShape == "ORB" and player.detachedPowerOrbSize == nil then player.detachedPowerOrbSize = 54 end
            ApplyDetachedPowerSource(); self.refresh()
        end,
        Meta("layout.independent_powerbar_shape", "setting", { settingKey = "player.detachedPowerBarShape" }))
    AddTooltip(self.cpPowerShape, "Independent Powerbar Shape", "Changes only the detached Player Powerbar. Class Resource shape on the left changes only Class Resources.")
    AddTooltip(self.cp.level, "Class Resource Layer", "Orders the Class Resource bar and pips. Its numeric, Rune and Ebon duration text uses the separate Class Resource text layer under Appearance > Text.")
    self:Add("detachedPlayer", self.cpPowerShape)
    local rightX = compact and 32 or min(max(430, floor(width * .52)), max(360, width - 360))
    local leftW = compact and max(250, width - 64) or max(250, rightX - 74)
    local rightW = compact and leftW or max(250, width - rightX - 32)
    local controlW = compact and max(250, min(320, width - 74)) or 300
    W.ControlCard(section, "Shape & Size", nil, 18, -38, leftW + 28, 370)
    W.ControlCard(section, "Powerbar & Position", nil, rightX - 14, compact and -430 or -38, rightW + 28, 286)
    MoveWidget(self.cpEnable, section, 32, -78)
    PlaceColumn(section, 32, -116, 54, controlW, nil, self.cp.shape, self.cp.height, self.cp.widthMode, self.cp.width, self.cpAlign)
    PlaceColumn(section, rightX, compact and -484 or -92, 54, controlW, nil, self.cpPowerShape, self.cp.x, self.cp.y, self.cp.level)
end

function Page:BuildClassBehavior()
    local section = self.b:CollapsibleSection("classpower_behavior", "Behavior", 282, false)
    local fields = self:Controls(section, Bars, ApplyClassPower, "behavior", {
        { "anchor", "toggle", "Anchor to Essential Cooldown", "classPowerAnchorToCooldown", false, group = "cp" },
        { "charged", "toggle", "Show empowered combo points", "showChargedComboPoints", true, group = "cp" },
        { "text", "toggle", "Show resource text", "classPowerShowText", false, group = "cp" },
        { "rune", "toggle", "Show rune time (per rune)", "runeShowTime", true, group = "cp" },
        { "reverse", "toggle", "Fill right-to-left", "classPowerFillReverse", false, group = "cp" },
        { "ele", "toggle", "Show Maelstrom bar (Ele)", "showEleMaelstrom", false, group = "cp" },
        { "ebon", "toggle", "Show Ebon Might duration (Aug)", "showEbonMight", true, group = "cp" },
        { "shadow", "toggle", "Show Insanity bar (Shadow)", "showShadowMana", false, group = "cp" },
        { "ironfur", "toggle", "Show Ironfur tracker (Guardian)", "showGuardianIronfur", false, group = "cp",
            helpTitle = "Guardian Ironfur Tracker", help = "In Bear Form, replaces the empty Guardian class-resource slot with an estimated Ironfur lifetime bar. Each successful cast adds one moving marker; Ursoc's Endurance and Guardian of Elune are included." },
        { "ironfurHashes", "toggle", "Show Ironfur cast markers", "guardianIronfurShowHashLines", true, group = "cp",
            helpTitle = "Ironfur Cast Markers", help = "Shows one moving marker per tracked Ironfur cast. The 30 Hz motion ticker exists only while the optional tracker has active casts." },
        { "prediction", "toggle", "Show resource prediction", "classPowerShowPrediction", true, group = "cp" },
        { "smooth", "toggle", "Smooth fill", "classPowerSmoothFill", false, ApplyClassPowerSmoothing, group = "cp",
            helpTitle = "Class Resource Smooth Fill", help = "Smooths resource changes. Runes, Essence recharge, and timers keep their own animation." },
    })
    local rightX = min(max(380, floor(self.width * .45)), max(320, self.width - 420))
    W.ControlCardBackdrop(section, 14, -38, max(280, rightX - 42), 230)
    W.ControlCardBackdrop(section, rightX - 14, -38, max(280, (section._msuf2Width or self.width) - rightX - 28) + 14, 230)
    PlaceColumn(section, 14, -38, 32, nil, nil, fields.anchor, fields.charged, fields.text, fields.rune, fields.reverse)
    PlaceColumn(section, rightX, -38, 32, nil, nil, fields.ele, fields.ebon, fields.shadow,
        fields.ironfur, fields.ironfurHashes, fields.prediction, fields.smooth)
    self.ironfurHashes = fields.ironfurHashes
end

function Page:BuildClassStyle()
    local section = self.b:CollapsibleSection("classpower_visuals", "Appearance", 430, false)
    local width, inner = section._msuf2Width or self.width, max(320, (section._msuf2Width or self.width) - 64)
    local cardW, controlW, frames = min(540, inner), min(360, min(540, inner) - 32), {}
    local resources, text, opacity, pips = M.UnitSectionsShared.MakeTabFrames(section, -88, width, frames, "resources", "text", "opacity", "pips")
    local values = VT("resources", "Textures", "text", "Text", "opacity", "Opacity", "pips", "Pips")
    RegisterSegment(W.SegmentTabs(self.ctx, section, { stateKey = "classPowerStyleTab", label = "Style area", values = values,
        width = min(620, inner), frames = frames, defaultTab = "resources", x = 32, y = -44 }), "style.workspace_tab", values)
    M.Assign(self.cp, self:Controls(resources, Bars, ApplyClassPowerVisuals, "style.resources", {
        { "color", "toggle", "Color by resource type", "classPowerColorByType", true, group = "cp" },
        { "comboColor", "dropdown", "Combo point colors", VT("default", "Resource color", "ramp", "Combo ramp", "custom", "Custom slots"), 260, "classPowerComboPointColorMode", "default", group = "cp" },
        { "fgTex", "dropdown", "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, "classPowerTexture", "", group = "cp" },
        { "bgTex", "dropdown", "Background texture", function() return TextureValues("Use foreground texture") end, 300, "classPowerBgTexture", "", group = "cp" },
    }))
    M.Assign(self.cp, self:Controls(text, Bars, ApplyClassPowerText, "style.text", {
        { "font", "slider", "Font size", 6, 32, 1, 300, "classPowerFontSize", 16, group = "cpText" },
        { "layer", "slider", "Class Resource text layer", 0, 30, 1, 300, "classPowerTextLayer", 5, ApplyClassPower, group = "cpText" },
        { "textX", "slider", "Text X", -200, 200, 1, 300, "classPowerTextOffsetX", 0, group = "cpText" },
        { "textY", "slider", "Text Y", -200, 200, 1, 300, "classPowerTextOffsetY", 0, group = "cpText" },
    }))
    AddTooltip(self.cp.layer, "Class Resource Text Layer", "Orders Class Resource numeric text, Rune times and the Ebon Might duration text independently from the Class Resource bar and Player Power text.")
    M.Assign(self.cp, self:Controls(opacity, Bars, ApplyClassPower, "style.opacity", {
        { "bg", "alpha", "BG opacity", "classPowerBgAlpha", .3, nil, 1, group = "cp" },
        { "filled", "alpha", "Filled %", "classPowerFilledAlpha", 1, nil, 5, group = "cp" },
        { "empty", "alpha", "Empty %", "classPowerEmptyAlpha", .3, nil, 5, group = "cp" },
    }))
    M.Assign(self.cp, self:Controls(pips, Bars, ApplyClassPower, "style.pips", {
        { "separator", "slider", "Separator", 0, 4, 1, 300, "classPowerTickWidth", 1, group = "cp" },
        { "outline", "slider", "Outline", 0, 4, 1, 300, "classPowerOutline", 1, group = "cp" },
        { "gap", "slider", "Pip gap", 0, 8, 1, 300, "classPowerGap", 0, group = "cp" },
    }))
    local resourcesCard, textCard, pipsCard
    for _, card in ipairs({ { resources, "Resource & Textures", 248 }, { text, "Text", 262 }, { opacity, "Opacity", 204 }, { pips, "Pips & Border", 230 } }) do
        local controlCard = W.ControlCard(card[1], card[2], nil, 18, -38, cardW + 28, card[3])
        if card[1] == resources then resourcesCard = controlCard end
        if card[1] == text then textCard = controlCard end
        if card[1] == pips then pipsCard = controlCard end
    end
    if W.AttachContextColorReferences then
        local function CurrentClassPowerRefs()
            return { "class_power.current" }
        end
        local function CurrentClassPowerContext(includeSlots)
            local spec = type(M.GetClassPowerPreviewSpec) == "function" and M.GetClassPowerPreviewSpec() or nil
            return {
                resourceToken = type(spec) == "table" and spec.token or nil,
                slot = type(spec) == "table" and spec.value or nil,
                includeSlots = includeSlots,
            }
        end
        local colorOptions = {
            title = "Class Resource Colors",
            note = "Colors follow the currently selected preview resource.",
            historySource = "menu:class-power-resource-colors",
            context = function() return CurrentClassPowerContext(false) end,
        }
        W.AttachContextColorReferences(resourcesCard, CurrentClassPowerRefs, colorOptions)
        W.AttachContextColorReferences(pipsCard, CurrentClassPowerRefs, {
            title = colorOptions.title,
            note = colorOptions.note,
            historySource = "menu:class-power-pip-colors",
            context = function() return CurrentClassPowerContext(true) end,
        })
    end
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(textCard, {
            title = "Class Resource Text Settings",
            historyLabel = "Class resource text color",
            historySource = "menu:class-power-text-color",
            textSettings = {
                scope = "shared",
                kind = "class_power",
                colorReferences = { "class_power.text" },
                colorTitle = "Class Resource Text Color",
                subtitle = "Class Resource text follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    MoveWidget(self.cp.color, resources, 32, -72)
    MoveWidget(self.cp.comboColor, resources, 32, -104, controlW)
    PlaceColumn(resources, 32, -192, 54, controlW, nil, self.cp.fgTex, self.cp.bgTex)
    PlaceColumn(text, 32, -84, 52, controlW, nil, self.cp.font, self.cp.layer, self.cp.textX, self.cp.textY)
    PlaceColumn(opacity, 32, -84, 52, controlW, nil, self.cp.bg, self.cp.filled, self.cp.empty)
    PlaceColumn(pips, 32, -84, 52, controlW, nil, self.cp.separator, self.cp.outline, self.cp.gap)
end

function Page:BuildClassVisibility()
    local section = self.b:CollapsibleSection("classpower_visibility", "Auto-Hide", 216, false)
    local width = min(560, (section._msuf2Width or self.width) - 28)
    W.ControlCard(section, "Auto-Hide Rules", nil, 14, -54, width, 142)
    for i, spec in ipairs({
        { "Hide out of combat", "classPowerHideOOC", "out_of_combat" },
        { "Hide when full", "classPowerHideWhenFull", "when_full" },
        { "Hide when empty", "classPowerHideWhenEmpty", "when_empty" },
    }) do
        self:Add("cp", SwitchAt(self.ctx, section, spec[1], 32, -54 - i * 32, width - 48, Bars, spec[2], false, ApplyClassPower, Meta("visibility." .. spec[3])))
    end
end

local function DetachedPowerSectionHeight(width)
    return width < 680 and 1000 or 780
end

function Page:BuildDetachedPower()
    local compact = self.width < 680
    local section = self.b:CollapsibleSection("classpower_detached_power", "Player Power", DetachedPowerSectionHeight(self.width), false)
    local width = section._msuf2Width or self.width
    local cardW, controlW = min(650, width - 28), min(300, max(240, min(650, width - 28) - 64))
    local twoColumns, frames = not compact and cardW >= 620, {}
    local rightX = twoColumns and 60 + controlW or 32
    local layout, textures, text = M.UnitSectionsShared.MakeTabFrames(section, -88, width, frames, "layout", "textures", "text")
    local values = VT("layout", "Layout", "textures", "Textures", "text", "Text")
    RegisterSegment(W.SegmentTabs(self.ctx, section, { stateKey = "classPowerDetachedPowerTab", label = "Power area", values = values,
        width = min(520, max(320, width - 64)), frames = frames, defaultTab = "layout", x = 32, y = -44 }), "detached_power.workspace_tab", values)
    W.ControlCard(layout, "Detached Player Power", "When anchored here, Player power settings are managed by Class Resources.", 14, -38, cardW, twoColumns and 482 or 760)
    self.dpbUse = W.SwitchAt(layout, "Detached player power", 32, -104, controlW)
    M.BindBoolWidget(self.ctx, self.dpbUse, function() return Player().powerBarDetached == true end,
        function(value)
            local player = Player()
            player.powerBarDetached = value and true or false
            if value then
                player.showPowerBar = true
                if player.detachedPowerBarSyncClassPower == nil then player.detachedPowerBarSyncClassPower = true end
                if player.detachedPowerBarAnchorToClassPower == nil then player.detachedPowerBarAnchorToClassPower = true end
                player.detachedPowerBarOffsetX = tonumber(player.detachedPowerBarOffsetX) or 0
                player.detachedPowerBarOffsetY = tonumber(player.detachedPowerBarOffsetY) or -4
                player.detachedPowerBarHeight = tonumber(player.detachedPowerBarHeight) or 6
                player.detachedPowerBarFrameLevelOffset = tonumber(player.detachedPowerBarFrameLevelOffset) or 6
            end
            ApplyDetachedPowerSource(); self.refresh()
        end, Meta("detached_power.enabled"))
    local smooth = SwitchAt(self.ctx, layout, "Smooth fill", twoColumns and rightX or 32, twoColumns and -104 or -138, controlW,
        Player, "powerSmoothFill", false, ApplyDetachedPlayerPowerSmoothing, Meta("detached_power.layout.smooth_fill"))
    local mode = self:Controls(layout, Bars, ApplyDetachedPowerWidthMode, "detached_power.layout", {
        { "mode", "nilDefaultDropdown", "Width mode", VT("manual", "Manual", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs"), 260, "detachedPowerBarWidthMode", "manual", group = "detached" },
    })
    self.dpb = self:Controls(layout, Player, ApplyDetachedPowerBar, "detached_power.layout", {
        { "anchor", "toggle", "Anchor to Class Resource", "detachedPowerBarAnchorToClassPower", false, group = "detachedPlayer" },
        { "sync", "toggle", "Sync width to Class Resource", "detachedPowerBarSyncClassPower", true, ApplyDetachedPowerSource, group = "detachedPlayer" },
        { "orbSize", "slider", "Orb size", 20, 160, 1, 300, "detachedPowerOrbSize", 54, group = "detachedPlayer" },
        { "x", "slider", "Power X", -1000, 1000, 1, 300, "detachedPowerBarOffsetX", 0, group = "detachedPlayer" },
        { "y", "slider", "Power Y", -1000, 1000, 1, 300, "detachedPowerBarOffsetY", -4, group = "detachedPlayer" },
        { "height", "slider", "Power height", 2, 80, 1, 300, "detachedPowerBarHeight", 6, group = "detachedPlayer" },
        { "layer", "slider", "Player Power layer", 0, 30, 1, 300, "detachedPowerBarFrameLevelOffset", 6, group = "detachedPlayer" },
    })
    AddTooltip(self.dpbUse, "Detached Player Power", "Moves the Player power bar out of the unit frame. Anchor connects it to the Class Resources stack; Sync only follows the stack width.")
    AddTooltip(self.dpb.anchor, "Anchor To Class Resource", "Keeps detached Player power attached to the Class Resource bar. Player power controls are disabled while this connection is active.")
    AddTooltip(self.dpb.sync, "Sync Width", "Uses the Class Resource width for detached Player power without making Class Resources own the Player power controls.")
    AddTooltip(self.dpb.layer, "Player Power Layer", "Orders only the normal Player Power bar. It does not control Class Resource pips or their text.")
    local powerTextCard = W.ControlCard(text, "Power Text", nil, 14, -38, cardW, twoColumns and 620 or 850)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(powerTextCard, {
            title = "Player Power Text Settings",
            historyLabel = "Player power text color",
            historySource = "menu:class-power-player-power-text-color",
            textSettings = {
                scope = "player",
                unit = "player",
                kind = "power",
            },
        })
    end
    self.dpbText = self:Controls(text, Player, ApplyDetachedPowerText, "detached_power.text", {
        { "onBar", "detachedTextOnBar", "Power text on bar", "detachedPowerBarTextOnBar", false, group = "detachedPlayer" },
        { "preset", "detachedTextPreset", "Power text", DETACHED_POWER_TEXT_PRESET_VALUES, 300, group = "detachedPlayer" },
        { "right", "dropdown", "Right slot", DETACHED_POWER_SLOT_VALUES, 300, "powerTextRight", "CURPERCENT", group = "detachedText" },
        { "left", "dropdown", "Left slot", DETACHED_POWER_SLOT_VALUES, 300, "powerTextLeft", "NONE", group = "detachedText" },
        { "center", "dropdown", "Center slot", DETACHED_POWER_SLOT_VALUES, 300, "powerTextCenter", "NONE", group = "detachedText" },
        { "sep", "dropdown", "Delimiter", DETACHED_POWER_SEPARATORS, 180, "powerTextSeparator", "", group = "detachedText" },
        { "size", "slider", "Power text size", 6, 48, 1, 300, "powerFontSize", 14, group = "detachedText" },
        { "x", "slider", "Text X", -300, 300, 1, 300, "powerOffsetX", -4, group = "detachedText" },
        { "y", "slider", "Text Y", -300, 300, 1, 300, "powerOffsetY", 4, group = "detachedText" },
        { "layer", "slider", "Player Power text layer", 0, 30, 1, 300, "powerTextLayer", 2, group = "detachedText" },
    })
    self.dpbHide = {
        self:SourceToggle(text, "Hide right % sign", Player, "powerTextRightHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
        self:SourceToggle(text, "Hide left % sign", Player, "powerTextLeftHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
        self:SourceToggle(text, "Hide center % sign", Player, "powerTextCenterHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
    }
    local fontOutline = W.Segment(text, "Player text outline", DETACHED_POWER_TEXT_OUTLINE_VALUES, controlW)
    M.BindSegment(self.ctx, fontOutline, function()
        local globalPage = M.GlobalPage
        if globalPage and type(globalPage.FontOutlineGetFor) == "function" then
            return globalPage.FontOutlineGetFor("player")
        end
        return "OUTLINE"
    end, function(value)
        local globalPage = M.GlobalPage
        if globalPage and type(globalPage.FontOutlineSetFor) == "function" then
            globalPage.FontOutlineSetFor("player", value, "MSUF2_DETACHED_POWER_TEXT_OUTLINE")
        end
        self.refresh()
    end, Meta("detached_power.text.outline", "setting"))
    RegisterSegment(fontOutline, "detached_power.text.outline", DETACHED_POWER_TEXT_OUTLINE_VALUES, "setting")
    M.classPowerDetachedPowerTextSlot = M.classPowerDetachedPowerTextSlot or "center"
    local slot = W.Segment(text, "Slot", TEXT_SLOT_VALUES, controlW)
    M.BindSegment(self.ctx, slot, CurrentDetachedTextSlot, function(value)
        M.classPowerDetachedPowerTextSlot = value or "center"
        if M.RequestRefresh then M.RequestRefresh(self.ctx, "classpower-detached-power-text-slot") elseif M.Refresh then M.Refresh(self.ctx) end
    end, Meta("detached_power.text.slot_selector", "ephemeral"))
    RegisterSegment(slot, "detached_power.text.slot_selector", TEXT_SLOT_VALUES, "ephemeral")
    local offsets = {}
    for index, axis in ipairs({ "X", "Y" }) do
        local slider = W.Slider(text, "Slot " .. axis, -300, 300, 1, 300)
        M.BindNumberWidget(self.ctx, slider, function()
            local x, y = DetachedTextOffsetKeys()
            return tonumber(Player()[index == 1 and x or y]) or 0
        end, function(value)
            local x, y = DetachedTextOffsetKeys()
            SetPlayerTextValue(index == 1 and x or y, value, ApplyDetachedPowerText)
        end, 0, Meta("detached_power.text.slot_offset." .. axis:lower(), "setting", { step = 1, roundStep = true }))
        offsets[index] = slider
    end
    AddTooltip(self.dpbText.preset, "Power Text", "Simple presets for Player power text while detached power is managed by Class Resources. Custom Slots means the existing slot layout is kept until you choose a preset.")
    AddTooltip(self.dpbText.onBar, "Power Text On Bar", "Places Player power text on the detached power bar. When off, the same Player power text remains positioned by the normal text layout.")
    AddTooltip(self.dpbText.x, "Text X", "Moves all detached Player power text slots together. Slot X/Y controls below add per-slot offsets.")
    AddTooltip(self.dpbText.layer, "Player Power Text Layer", "Orders only the normal Player Power text. The visible Essence count and Ebon Might time belong to Class Resource text.")
    AddTooltip(fontOutline, "Player Text Outline", "Sets the Player font scope used by detached Power text. Player Name and HP text share this outline setting.")
    -- Power art is owned by the Bars page and the Player unit page (detached or
    -- not); this tab keeps only the shape edge that Class Resources still owns.
    local powerTexturesCard = W.ControlCard(textures, "Shape Outline", "Power textures live on the Bars page.", 14, -38, cardW, 160)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(powerTexturesCard, function()
            local refs = { "power.current" }
            local db = M.EnsureDB()
            local general = db and db.general or {}
            local bars = Bars()
            if not (general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true) then
                refs[#refs + 1] = "bar.power_background"
            end
            return refs
        end, {
            title = "Detached Player Power Colors",
            note = "The resource color follows Player power. A matched background is derived from Health instead.",
            historySource = "menu:class-power-detached-power-colors",
            context = function() return { unit = "player" } end,
        })
    end
    local texture = self:Controls(textures, Bars, ApplyDetachedPowerBar, "detached_power.textures", {
        { "outline", "playerPowerOutline", "Power bar outline", 0, 8, 1, 300, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline, group = "detached" },
    })
    self.dpbTextures = texture
    AddTooltip(texture.outline, "Power Bar Outline", "Edge strength of every detached Player power shape, including Bar, Round, Crystal and Orb. 0 disables only that edge.")
    PlaceColumn(layout, 32, twoColumns and -154 or -188, 54, controlW, "LEFT", self.dpb.anchor, self.dpb.sync, mode.mode, self.dpb.orbSize, self.dpb.height)
    PlaceColumn(layout, rightX, twoColumns and -154 or -520, 54, controlW, "LEFT", self.dpb.x, self.dpb.y, self.dpb.layer)
    PlaceColumn(textures, 32, -104, 54, controlW, "LEFT", texture.outline)
    PlaceColumn(text, 32, -104, 54, controlW, "LEFT", self.dpbText.onBar, self.dpbText.preset, self.dpbText.right)
    for i, control in ipairs({ self.dpbHide[1], self.dpbText.left, self.dpbHide[2], self.dpbText.center, self.dpbHide[3], self.dpbText.sep }) do
        MoveWidget(control, text, 32, ({ -264, -298, -350, -384, -436, -470 })[i], controlW, "LEFT")
    end
    PlaceColumn(text, rightX, twoColumns and -154 or -446, 54, controlW, "LEFT", self.dpbText.size, fontOutline, self.dpbText.x, self.dpbText.y, self.dpbText.layer, slot, offsets[1], offsets[2])
    self:Add("detachedPlayer", smooth)
    self:Add("detachedText", fontOutline, unpack(self.dpbHide))
    self:Add("detachedSlot", slot, offsets[1], offsets[2])
end

function Page:BuildPlayerHP()
    local compact = self.width < 680
    local section = self.b:CollapsibleSection("classpower_player_hp", "Extra Health Bar", compact and 980 or 700, false)
    local width = section._msuf2Width or self.width
    local cardW, controlW = min(650, width - 28), min(300, max(240, min(650, width - 28) - 64))
    local twoColumns, frames = not compact and cardW >= 620, {}
    local rightX = twoColumns and 60 + controlW or 32
    local layout, textures, text = M.UnitSectionsShared.MakeTabFrames(section, -88, width, frames, "layout", "textures", "text")
    local values = VT("layout", "Layout", "textures", "Textures", "text", "Text")
    RegisterSegment(W.SegmentTabs(self.ctx, section, { stateKey = "classPowerPlayerHPTab", label = "HP area", values = values,
        width = min(520, max(320, width - 64)), frames = frames, defaultTab = "layout", x = 32, y = -44 }), "player_hp.workspace_tab", values)
    W.ControlCard(layout, "Visibility & Position", nil, 14, -38, cardW, twoColumns and 500 or 760)
    local applyRefresh = self:WithRefresh(ApplyPlayerHPBar)
    self.hpUse = SwitchAt(self.ctx, layout, "Second Player HP bar", 32, -104, controlW, Bars, "playerHPBarEnabled", false, applyRefresh, Meta("player_hp.enabled"))
    self.hp = self:Controls(layout, Bars, ApplyPlayerHPBar, "player_hp.layout", {
        { "anchor", "dropdown", "Anchor", PLAYER_HP_ANCHOR_VALUES, 300, "playerHPBarAnchor", "CLASS_TOP" },
        { "widthMode", "dropdown", "Width mode", PLAYER_HP_WIDTH_VALUES, 300, "playerHPBarWidthMode", "class", applyRefresh },
        { "manualWidth", "slider", "Custom width", 20, 1200, 1, 300, "playerHPBarWidth", 0 },
        { "shape", "dropdown", "HP shape", PLAYER_HP_SHAPE_VALUES, 300, "playerHPBarShape", "BAR", applyRefresh },
        { "orbSize", "slider", "Orb size", 20, 160, 1, 300, "playerHPBarOrbSize", 54 },
        { "height", "slider", "Height", 2, 80, 1, 300, "playerHPBarHeight", 6 },
        { "smooth", "toggle", "Smooth fill", "playerHPBarSmoothFill", false },
        { "gap", "slider", "Gap", 0, 60, 1, 300, "playerHPBarGap", 2 },
        { "x", "slider", "Offset X", -1000, 1000, 1, 300, "playerHPBarOffsetX", 0 },
        { "y", "slider", "Offset Y", -1000, 1000, 1, 300, "playerHPBarOffsetY", 0 },
        { "layer", "slider", "Frame layer", 0, 30, 1, 300, "playerHPBarFrameLevelOffset", 7 },
    })
    PlaceColumn(layout, 32, -154, 54, controlW, "LEFT", self.hp.anchor, self.hp.widthMode, self.hp.manualWidth, self.hp.shape, self.hp.orbSize, self.hp.height, self.hp.smooth)
    PlaceColumn(layout, rightX, twoColumns and -154 or -580, 54, controlW, "LEFT", self.hp.gap, self.hp.x, self.hp.y, self.hp.layer)
    self:AddNamed("hp", self.hp, "anchor widthMode shape height smooth gap x y layer"); self:AddNamed("hpManual", self.hp, "manualWidth"); self:AddNamed("hpOrb", self.hp, "orbSize")
    AddTooltip(self.hpUse, "Second Player HP Bar", "Renders a second native Player health bar. The normal Player unitframe HP bar is untouched, so you can show HP twice.")
    AddTooltip(self.hp.anchor, "Anchor", "Power anchors use the Player power bar when it is visible; otherwise the HP bar falls back to the Class Resource anchor.")
    AddTooltip(self.hp.widthMode, "Width Mode", "Class Resource and Player Power follow existing frames. Custom uses the slider below. Width is resolved only during layout refresh.")
    AddTooltip(self.hp.shape, "HP Shape", "Bar keeps the normal statusbar. Follow Player Power mirrors the independent detached Player power shape. Orb uses a single vertical fill.")
    AddTooltip(self.hp.orbSize, "Orb Size", "Used only when this HP bar is explicitly set to Orb. Follow Player Power inherits the Player power orb size instead.")
    AddTooltip(self.hp.smooth, "Smooth Fill", "Optional interpolation for this second HP bar. Off keeps direct native SetValue updates.")
    local hpTexturesCard = W.ControlCard(textures, "HP Textures", nil, 14, -38, cardW, 346)
    if W.AttachContextColorReferences then
        local function PlayerHPColorMode()
            local mode = tostring(Bars().playerHPBarColorMode or "GLOBAL"):upper()
            if mode == "CLASS" or mode == "DARK" or mode == "GRADIENT" then return mode end
            return "GLOBAL"
        end
        W.AttachContextColorReferences(hpTexturesCard, function()
            return PlayerHPColorMode() == "DARK" and {} or { "health.current" }
        end, {
            title = "Extra Health Bar Colors",
            note = "The foreground follows the selected HP color mode. Dark Mode uses the shared dark-tone control.",
            historySource = "menu:class-power-player-hp-colors",
            context = function()
                return { unit = "player", unitKey = "player", healthMode = PlayerHPColorMode() }
            end,
        })
    end
    local function ApplyPlayerHPColorMode()
        ApplyPlayerHPBar()
        if M.Refresh then M.Refresh(self.ctx) end
    end
    local texture = self:Controls(textures, Bars, ApplyPlayerHPBar, "player_hp.textures", {
        { "color", "dropdown", "HP color", PLAYER_HP_COLOR_VALUES, 300, "playerHPBarColorMode", "GLOBAL", ApplyPlayerHPColorMode },
        { "fg", "dropdown", "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, "playerHPBarTexture", "", ApplyPlayerHPTextures },
        { "bg", "dropdown", "Background texture", function() return TextureValues("Use foreground texture") end, 300, "playerHPBarBgTexture", "", ApplyPlayerHPTextures },
        { "bgAlpha", "alpha", "BG opacity", "playerHPBarBgAlpha", .35, ApplyPlayerHPBar, 1 },
        { "outline", "slider", "Outline", 0, 8, 1, 300, "playerHPBarOutline", 1 },
    })
    PlaceColumn(textures, 32, -104, 54, controlW, "LEFT", texture.color, texture.fg, texture.bg, texture.bgAlpha, texture.outline)
    self:AddNamed("hp", texture, "color fg bg bgAlpha outline"); self:AddNamed("hpTexture", texture, "fg bg")
    AddTooltip(texture.color, "HP Color", "Global follows the normal MSUF health color mode. Class Color forces your class color. Dark Mode forces the configured dark bar color. HP Gradient colors only this second HP bar by current health.")
    AddTooltip(texture.bg, "Background Texture", "Visible behind the filled HP amount. At 100% HP the fill covers the background; Outline 0 does not disable this texture.")
    AddTooltip(texture.outline, "HP Outline", "Controls only the second HP bar outline. Bar uses four outside border edges; shapes use their fixed edge texture. 0 disables only the outline.")
    local hpTextCard = W.ControlCard(text, "HP Text", nil, 14, -38, cardW, twoColumns and 520 or 690)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(hpTextCard, {
            title = "Extra Health Text Settings",
            historyLabel = "Extra health text color",
            historySource = "menu:class-power-player-hp-text-color",
            textSettings = {
                scope = "shared",
                modeScope = "player",
                unit = "player",
                kind = "hp",
                colorReferences = function()
                    if Bars().playerHPBarUsePlayerText == true then return nil end
                    return {}
                end,
                capabilities = function()
                    local mirror = Bars().playerHPBarUsePlayerText == true
                    return {
                        shadow = false,
                        opacity = false,
                        baseline = false,
                        shadowAlpha = false,
                        shadowDistance = false,
                        colorMode = mirror,
                        colors = mirror,
                    }
                end,
                subtitle = function()
                    if Bars().playerHPBarUsePlayerText == true then
                        return "Font face follows Shared; text and color mode mirror Player HP."
                    end
                    return "Local HP text uses shared face settings and a fixed white color."
                end,
            },
        })
    end
    local textRefresh = self:WithRefresh(ApplyPlayerHPText)
    self.hpTextEnable = SwitchAt(self.ctx, text, "Show HP text", 32, -104, controlW, Bars, "playerHPBarTextEnabled", true, textRefresh, Meta("player_hp.text.enabled"))
    local shared = SwitchAt(self.ctx, text, "Use Player HP text", 32, -136, controlW, Bars, "playerHPBarUsePlayerText", true, textRefresh, Meta("player_hp.text.use_player_text"))
    self.hpText = self:Controls(text, Bars, ApplyPlayerHPText, "player_hp.text", {
        { "right", "dropdown", "Right slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextRight", "CURPERCENT" },
        { "left", "dropdown", "Left slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextLeft", "NONE" },
        { "center", "dropdown", "Center slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextCenter", "NONE" },
        { "sep", "dropdown", "Delimiter", PLAYER_HP_SEPARATORS, 180, "playerHPBarTextSeparator", "" },
        { "reverse", "toggle", "Reverse order", "playerHPBarTextReverse", false },
        { "size", "slider", "Text size", 6, 48, 1, 300, "playerHPBarTextSize", 14 },
        { "x", "slider", "Text X", -300, 300, 1, 300, "playerHPBarTextOffsetX", 0 },
        { "y", "slider", "Text Y", -300, 300, 1, 300, "playerHPBarTextOffsetY", 0 },
    })
    self.hpHide = {
        self:SourceToggle(text, "Hide right % sign", Bars, "playerHPBarTextRightHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
        self:SourceToggle(text, "Hide left % sign", Bars, "playerHPBarTextLeftHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
        self:SourceToggle(text, "Hide center % sign", Bars, "playerHPBarTextCenterHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
    }
    for i, control in ipairs({ self.hpText.right, self.hpHide[1], self.hpText.left, self.hpHide[2], self.hpText.center, self.hpHide[3], self.hpText.sep }) do
        MoveWidget(control, text, 32, ({ -188, -240, -274, -326, -360, -412, -446 })[i], controlW, "LEFT")
    end
    PlaceColumn(text, rightX, twoColumns and -188 or -440, 54, controlW, "LEFT", self.hpText.reverse, self.hpText.size, self.hpText.x, self.hpText.y)
    self:Add("hp", self.hpTextEnable); self:Add("hpText", shared)
    self:AddNamed("hpCustomText", self.hpText, "right left center sep reverse size"); self:Add("hpCustomText", unpack(self.hpHide))
    self:AddNamed("hpTextPosition", self.hpText, "x y")
    AddTooltip(self.hpTextEnable, "HP Text", "Controls only this second HP bar. The normal Player unitframe HP text remains separate.")
    AddTooltip(shared, "Use Player HP Text", "Uses Player HP text settings and copies already-rendered Player HP text when it is current. Local Text X/Y still belong to this bar.")
end

function Page:BuildAlternativeMana()
    local section = self.b:CollapsibleSection("classpower_alt_mana", "Alternative Mana", 476, false)
    local cardW = min(620, (section._msuf2Width or self.width) - 28)
    local controlW = min(360, cardW - 64)
    local manaCard = W.ControlCard(section, "Visibility & Size", "For specializations that use mana alongside another resource.", 14, -38, cardW, 404)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(manaCard, { "class_power.alt_mana" }, {
            title = "Alternative Mana Color",
            historySource = "menu:class-power-alternative-mana-color",
        })
    end
    self.altToggle = SwitchAt(self.ctx, section, "Show mana bar (dual resource)", 32, -98, controlW, Bars, "showAltMana", false, ApplyClassPower, Meta("alternative_mana.enabled"))
    local smooth = SwitchAt(self.ctx, section, "Smooth fill", 32, -132, controlW, Bars, "altManaSmoothFill", false, ApplyClassPowerSmoothing, Meta("alternative_mana.smooth_fill"))
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    local fields = self:Controls(section, Bars, ApplyClassPower, "alternative_mana.layout", {
        { "widthMode", "dropdown", "Width mode", ALT_MANA_WIDTH_VALUES, 300, "altManaWidthMode", "player", applyRefresh },
        { "width", "slider", "Custom width", 20, 1200, 1, 300, "altManaWidth", 0 },
        { "height", "slider", "Height", 2, 30, 1, 300, "altManaHeight", 4 },
        { "x", "slider", "X offset", -1000, 1000, 1, 300, "altManaOffsetX", 0 },
        { "y", "slider", "Y offset", -50, 50, 1, 300, "altManaOffsetY", -2 },
    })
    PlaceColumn(section, 32, -174, 54, controlW, "LEFT", fields.widthMode, fields.width, fields.height, fields.x, fields.y)
    self.altManaWidth = fields.width
    self:AddNamed("altMana", fields, "widthMode width height x y"); self:Add("altMana", smooth)
end

function Page:RefreshControlState()
    local bars, db = Bars(), M.EnsureDB()
    local cpOn = BoolValue(bars, "showClassPower", true)
    SetControlsEnabled(self.groups.cp, cpOn)
    if self.ironfurHashes then SetControlEnabled(self.ironfurHashes, cpOn and BoolValue(bars, "showGuardianIronfur", false)) end
    SetControlEnabled(self.cp.width, cpOn and (bars.classPowerWidthMode or "player") == "custom")
    local classBar = NormalizeClassPowerShape(bars.classPowerShape) == "BAR"
    if self.cp.height and self.cp.height._msuf2Title then self.cp.height._msuf2Title:SetText(M.Tr(classBar and "Height" or "Pip size")) end
    SetControlEnabled(self.cp.separator, cpOn and classBar); SetControlEnabled(self.cp.outline, cpOn and classBar)
    SetControlEnabled(self.cpAlign, cpOn and not classBar)
    -- Ebon Might owns a native duration text even when the optional aggregate
    -- resource text is disabled, so its shared text styling/layer stays usable.
    SetControlsEnabled(self.groups.cpText, cpOn)
    local anyDetached = false
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        if db[key] and db[key].powerBarDetached then anyDetached = true; break end
    end
    local playerDetached = db.player and db.player.powerBarDetached == true
    SetControlsEnabled(self.groups.detached, anyDetached); SetControlsEnabled(self.groups.detachedPlayer, playerDetached)
    SetControlEnabled(self.dpbUse, true)
    -- Lazy sections leave their control tables nil until first expand.
    local playerShape = NormalizeDetachedPowerShape(db.player and db.player.detachedPowerBarShape)
    if self.dpb then
        SetControlEnabled(self.dpb.orbSize, playerDetached and playerShape == "ORB")
        SetControlEnabled(self.dpb.height, playerDetached and playerShape ~= "ORB")
    end
    if self.dpbTextures then
        SetControlEnabled(self.dpbTextures.outline, playerDetached)
    end
    local playerTextOn = db.player and PlayerPowerTextShown(db.player)
    if self.dpbText then
        SetControlEnabled(self.dpbText.onBar, playerDetached); SetControlEnabled(self.dpbText.size, playerDetached and playerTextOn)
    end
    SetControlsEnabled(self.groups.detachedText, playerDetached and playerTextOn)
    if self.dpbHide then
        for i, mode in ipairs({ (db.player and (db.player.powerTextRight or db.player.powerTextMode)) or "CURPERCENT", db.player and db.player.powerTextLeft or "NONE", db.player and db.player.powerTextCenter or "NONE" }) do
            SetControlEnabled(self.dpbHide[i], playerDetached and playerTextOn and HasPercent(mode))
        end
    end
    SetControlsEnabled(self.groups.detachedSlot, playerDetached and playerTextOn)
    local hpOn, hpShape = BoolValue(bars, "playerHPBarEnabled", false), ResolvePlayerHPShape(bars, db)
    local hpOrb = hpShape == "ORB"
    SetControlsEnabled(self.groups.hp, hpOn)
    SetControlsEnabled(self.groups.hpManual, hpOn and not hpOrb and (bars.playerHPBarWidthMode or "class") == "custom")
    SetControlsEnabled(self.groups.hpOrb, hpOn and NormalizePlayerHPShape(bars.playerHPBarShape) == "ORB")
    SetControlsEnabled(self.groups.hpTexture, hpOn and hpShape == "BAR")
    if self.hp then SetControlEnabled(self.hp.height, hpOn and not hpOrb) end
    local hpTextOn = hpOn and BoolValue(bars, "playerHPBarTextEnabled", true)
    local hpCustom = hpTextOn and not BoolValue(bars, "playerHPBarUsePlayerText", true)
    SetControlsEnabled(self.groups.hpText, hpTextOn); SetControlsEnabled(self.groups.hpCustomText, hpCustom)
    if self.hpHide then
        for i, mode in ipairs({ bars.playerHPBarTextRight or "CURPERCENT", bars.playerHPBarTextLeft or "NONE", bars.playerHPBarTextCenter or "NONE" }) do
            SetControlEnabled(self.hpHide[i], hpCustom and HasPercent(mode))
        end
    end
    SetControlsEnabled(self.groups.hpTextPosition, hpTextOn)
    SetControlEnabled(self.hpUse, true)
    local altManaOn = BoolValue(bars, "showAltMana", false)
    SetControlsEnabled(self.groups.altMana, altManaOn)
    SetControlEnabled(self.altManaWidth, altManaOn and (bars.altManaWidthMode or "player") == "custom")
    SetControlEnabled(self.altToggle, true); SetControlEnabled(self.cpEnable, true)
end

-- Collapsed sections build only their shell on the visible cold path; content
-- builds on first expand through the shared lazy-section registry. Hidden
-- search-index builds and persisted-open sections still build synchronously
-- inside BuildSectionLazy, so search, Assistant coverage, and reopened
-- sections keep seeing the full page.
function Page:LazySection(id, title, height, method)
    local UnitPage = M.UnitPage
    if UnitPage and type(UnitPage.BuildSectionLazy) == "function" then
        local page = self
        UnitPage.BuildSectionLazy(self.ctx, self.b, "player", {
            id = id,
            title = title,
            height = height,
            defaultOpen = false,
            build = function(_, proxyBuilder)
                local outerBuilder = page.b
                page.b = proxyBuilder
                local buildOK, buildError = pcall(method, page)
                page.b = outerBuilder
                if not buildOK then error(buildError, 0) end
                -- Newly built controls need their enabled/disabled state; the
                -- proxy is a safe no-op while the page itself is still building.
                page.refresh()
            end,
        })
        return
    end
    method(self)
end

function Page:Build()
    self:BuildHeader()
    BuildInlineClassPowerPreview(self.ctx, self.b)
    self:BuildClassLayout()
    self:LazySection("classpower_behavior", "Behavior", 282, Page.BuildClassBehavior)
    self:LazySection("classpower_visuals", "Appearance", 430, Page.BuildClassStyle)
    self:LazySection("classpower_visibility", "Auto-Hide", 216, Page.BuildClassVisibility)
    self:LazySection("classpower_detached_power", "Player Power", function() return DetachedPowerSectionHeight(self.width) end, Page.BuildDetachedPower)
    self:LazySection("classpower_player_hp", "Extra Health Bar", function() return self.width < 680 and 980 or 700 end, Page.BuildPlayerHP)
    self:LazySection("classpower_alt_mana", "Alternative Mana", 476, Page.BuildAlternativeMana)
    -- All callbacks share one late-bound state refresh instead of capturing every control.
    self.refresh = self.refresh(function() self:RefreshControlState() end)
    M.RefreshClassPowerDetachedState = self.refresh
    M.TrackRefresh(self.ctx, self.refresh)
    MaybeOfferQuickSetup()
    self.ctx:SetContentHeight(math.abs(self.b.y) + 42)
end

local function BuildClassPower(ctx) Page.New(ctx):Build() end
M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 21 })
