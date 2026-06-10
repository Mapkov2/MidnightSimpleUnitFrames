local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- ClassPower registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsString = C.RegisterBarsString
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterBarsEnum = C.RegisterBarsEnum
local ClassPowerAliases = C.ClassPowerAliases
local ApplyClassPower = C.ApplyClassPower
local ApplyDetachedPowerBar = C.ApplyDetachedPowerBar
local ApplyDetachedPowerBarOutline = C.ApplyDetachedPowerBarOutline
local CallGlobal = C.CallGlobal

local CLASS_POWER_WIDTH_MODE_ALIASES = {
    player = "player",
    frame = "player",
    playerframe = "player",
    playerwidth = "player",
    playerframewidth = "player",
    unitframe = "player",
    unitframewidth = "player",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    essentialcooldownmanager = "cooldown",
    cooldownmanager = "cooldown",
    cooldownsmanager = "cooldown",
    cdmwidth = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    utilitycooldownmanager = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
    trackedbuffwidth = "tracked_buffs",
    custom = "custom",
    manual = "custom",
}

local COMBO_POINT_COLOR_MODE_ALIASES = {
    default = "default",
    resource = "default",
    resourcecolor = "default",
    ramp = "ramp",
    comboramp = "ramp",
    gradient = "ramp",
    custom = "custom",
    slots = "custom",
}

local function NormalizeInheritedTexture(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    local lower = text:lower()
    if lower == "" or lower == "global" or lower == "use global" or lower == "use global bar texture" then return "" end
    if lower == "inherit" or lower == "inherited" or lower == "default" or lower == "follow global" then return "" end
    return text
end

local function NormalizeForegroundTexture(value)
    local text = NormalizeInheritedTexture(value)
    local lower = text:lower()
    if lower == "foreground" or lower == "use foreground" or lower == "use foreground texture" then return "" end
    if lower == "same as foreground" or lower == "follow foreground" then return "" end
    return text
end

local DETACHED_POWER_WIDTH_MODE_ALIASES = {
    manual = "manual",
    custom = "manual",
    player = "manual",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
}

local CLASS_POWER_PREVIEW_VALUES = {
    "deathknight_runes",
    "demonhunter_devourer",
    "demonhunter_vengeance",
    "druid_feral",
    "druid_balance",
    "evoker_essence",
    "evoker_augmentation_ebon",
    "hunter_survival_tip",
    "mage_arcane",
    "monk_brewmaster",
    "monk_windwalker",
    "paladin_holy_power",
    "priest_shadow",
    "rogue_combo",
    "shaman_elemental",
    "shaman_enhancement",
    "warlock_soul_shards",
    "warlock_destruction",
    "warrior_whirlwind",
}

local CLASS_POWER_PREVIEW_LABELS = {
    deathknight_runes = "Death Knight - Runes",
    demonhunter_devourer = "Demon Hunter - Soul Fragments",
    demonhunter_vengeance = "Demon Hunter - Vengeance Fragments",
    druid_feral = "Druid - Feral Combo Points",
    druid_balance = "Druid - Balance (no class bar)",
    evoker_essence = "Evoker - Essence",
    evoker_augmentation_ebon = "Evoker - Augmentation Ebon Might",
    hunter_survival_tip = "Hunter - Survival Tip of the Spear",
    mage_arcane = "Mage - Arcane Charges",
    monk_brewmaster = "Monk - Brewmaster Stagger",
    monk_windwalker = "Monk - Windwalker Chi",
    paladin_holy_power = "Paladin - Holy Power",
    priest_shadow = "Priest - Shadow Insanity",
    rogue_combo = "Rogue - Combo Points",
    shaman_elemental = "Shaman - Elemental Maelstrom",
    shaman_enhancement = "Shaman - Enhancement Maelstrom Weapon",
    warlock_soul_shards = "Warlock - Soul Shards",
    warlock_destruction = "Warlock - Destruction Soul Shards",
    warrior_whirlwind = "Warrior - Whirlwind Stacks",
}

local CLASS_POWER_PREVIEW_ALIASES = {
    ["death knight"] = "deathknight_runes",
    dk = "deathknight_runes",
    runes = "deathknight_runes",
    ["demon hunter soul fragments"] = "demonhunter_devourer",
    ["soul fragments"] = "demonhunter_devourer",
    ["vengeance fragments"] = "demonhunter_vengeance",
    vengeance = "demonhunter_vengeance",
    ["feral combo points"] = "druid_feral",
    feral = "druid_feral",
    ["balance druid"] = "druid_balance",
    boomkin = "druid_balance",
    essence = "evoker_essence",
    evoker = "evoker_essence",
    ["ebon might"] = "evoker_augmentation_ebon",
    augmentation = "evoker_augmentation_ebon",
    aug = "evoker_augmentation_ebon",
    ["tip of the spear"] = "hunter_survival_tip",
    hunter = "hunter_survival_tip",
    ["arcane charges"] = "mage_arcane",
    mage = "mage_arcane",
    stagger = "monk_brewmaster",
    brewmaster = "monk_brewmaster",
    chi = "monk_windwalker",
    windwalker = "monk_windwalker",
    ["holy power"] = "paladin_holy_power",
    paladin = "paladin_holy_power",
    insanity = "priest_shadow",
    shadow = "priest_shadow",
    ["combo points"] = "rogue_combo",
    combo = "rogue_combo",
    rogue = "rogue_combo",
    maelstrom = "shaman_elemental",
    elemental = "shaman_elemental",
    ["maelstrom weapon"] = "shaman_enhancement",
    enhancement = "shaman_enhancement",
    ["soul shards"] = "warlock_soul_shards",
    warlock = "warlock_soul_shards",
    destruction = "warlock_destruction",
    whirlwind = "warrior_whirlwind",
    warrior = "warrior_whirlwind",
}

local function ClassPowerPreviewValueAliases()
    local aliases = {}
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        local key = CLASS_POWER_PREVIEW_VALUES[i]
        aliases[key] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower()] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower():gsub("%s*%-%s*", " ")] = key
        aliases[key:gsub("_", " ")] = key
    end
    for alias, key in pairs(CLASS_POWER_PREVIEW_ALIASES) do aliases[alias] = key end
    return aliases
end

local function ClassPowerPreviewLabel(key)
    return CLASS_POWER_PREVIEW_LABELS[key] or tostring(key or "rogue_combo")
end

local function NormalizeClassPowerPreviewKey(key)
    key = tostring(key or "rogue_combo")
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        if CLASS_POWER_PREVIEW_VALUES[i] == key then return key end
    end
    return "rogue_combo"
end

local function RefreshClassPowerPreview()
    if type(CallGlobal) == "function" then CallGlobal("MSUF_UFPreview_RequestRefresh", "MSUF_ASSISTANT_CLASSPOWER_PREVIEW") end
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF_ASSISTANT_CLASSPOWER_PREVIEW", { preview = true, applyAll = false, notify = false })
    end
    local preview = M and M._msuf2ClassPowerInlinePreview
    if preview and type(preview.Refresh) == "function" then preview:Refresh() end
end

RegisterBarsBoolean("showClassPower", "enabled", "Class Resource", true, {
    "class power enabled", "class resource enabled", "class resources enabled",
    "class power bar enabled", "class resource bar enabled", "resource bar enabled",
}, {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ENABLED",
    matchLabel = false,
    description = "Enables or disables MSUF Class Resources live outside combat.",
})
RegisterBarsNumber("classPowerHeight", "height", "Class Resource Height", 4, 1, 40, ClassPowerAliases("height", "class resource bar height"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HEIGHT",
})
RegisterBarsEnum("classPowerWidthMode", "widthMode", "Class Resource Width Mode", "player", {
    "player", "cooldown", "utility", "tracked_buffs", "custom",
}, ClassPowerAliases("width mode", "class resource width source", "class power width source"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH_MODE",
    valueAliases = CLASS_POWER_WIDTH_MODE_ALIASES,
})
RegisterBarsNumber("classPowerWidth", "width", "Class Resource Width", 0, 30, 800, ClassPowerAliases("width", "class resource bar width"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH",
})
RegisterBarsNumber("classPowerOffsetX", "offsetX", "Class Resource Offset X", 0, -800, 800, ClassPowerAliases("x offset", "class resource x", "class power x", "move class resource horizontally"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_X",
})
RegisterBarsNumber("classPowerOffsetY", "offsetY", "Class Resource Offset Y", 0, -800, 800, ClassPowerAliases("y offset", "class resource y", "class power y", "move class resource vertically"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_Y",
})
RegisterBarsNumber("classPowerFrameLevelOffset", "frameLevel", "Class Resource Frame Level", 5, 0, 30, ClassPowerAliases("frame level", "class resource strata level"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FRAME_LEVEL",
})

RegisterBarsBoolean("classPowerAnchorToCooldown", "anchorToCooldown", "Class Resource Anchor To Essential Cooldowns", false, ClassPowerAliases(
    "anchor to cooldown", "anchor to cooldowns", "anchor to essential cooldowns",
    "anchor to essential cooldownmanager", "anchor to cooldownmanager",
    "class resource anchor to essential cooldowns", "class resource anchor to essential cooldownmanager",
    "class power follow cooldowns", "class resource follow essential cooldowns",
    "follow essential cooldowns", "follow cooldownmanager", "position above essential cooldowns"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ANCHOR_COOLDOWN",
})
RegisterBarsBoolean("showChargedComboPoints", "chargedComboPoints", "Empowered Combo Points", true, ClassPowerAliases("empowered combo points", "charged combo points", "combo point charges"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_CHARGED_COMBO_POINTS",
})
RegisterBarsBoolean("classPowerShowText", "text", "Class Resource Text", false, ClassPowerAliases("text", "resource text", "class resource numbers", "class power numbers"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT",
})
RegisterBarsBoolean("runeShowTime", "runeTime", "Rune Time", true, ClassPowerAliases("rune time", "rune timers", "rune timer text"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_RUNE_TIME",
})
RegisterBarsBoolean("classPowerFillReverse", "reverseFill", "Class Resource Reverse Fill", false, ClassPowerAliases("reverse fill", "fill right to left", "right to left fill"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_REVERSE_FILL",
})
RegisterBarsBoolean("showEleMaelstrom", "elementalMaelstrom", "Elemental Maelstrom Bar", false, ClassPowerAliases("elemental maelstrom", "maelstrom bar", "ele maelstrom bar"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ELE_MAELSTROM",
})
RegisterBarsBoolean("showEbonMight", "ebonMight", "Ebon Might Timer", true, ClassPowerAliases("ebon might", "ebon might timer", "augmentation ebon might"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_EBON_MIGHT",
})
RegisterBarsBoolean("showShadowMana", "shadowMana", "Shadow Insanity Bar", false, ClassPowerAliases("shadow insanity", "insanity bar", "shadow mana", "shadow resource bar"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SHADOW_MANA",
})
RegisterBarsBoolean("classPowerShowPrediction", "prediction", "Class Resource Prediction", true, ClassPowerAliases("prediction", "resource prediction", "incoming resource"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_PREDICTION",
})

RegisterBarsBoolean("classPowerColorByType", "colorByType", "Class Resource Color By Type", true, ClassPowerAliases("color by type", "resource type colors", "class resource class colors"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_COLOR_TYPE",
})
RegisterBarsEnum("classPowerComboPointColorMode", "comboPointColorMode", "Combo Point Color Mode", "default", {
    "default", "ramp", "custom",
}, ClassPowerAliases("combo point color mode", "combo point slot mode", "combo slot mode", "combo point colors", "combo colors"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_COMBO_COLOR_MODE",
    valueAliases = COMBO_POINT_COLOR_MODE_ALIASES,
})
RegisterBarsNumber("classPowerFontSize", "fontSize", "Class Resource Font Size", 16, 6, 32, ClassPowerAliases("font size", "text size", "number size"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FONT_SIZE",
})
RegisterBarsNumber("classPowerTextOffsetX", "textOffsetX", "Class Resource Text Offset X", 0, -200, 200, ClassPowerAliases("text x", "text x offset", "number x offset"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_X",
})
RegisterBarsNumber("classPowerTextOffsetY", "textOffsetY", "Class Resource Text Offset Y", 0, -200, 200, ClassPowerAliases("text y", "text y offset", "number y offset"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_Y",
})
RegisterBarsNumber("classPowerBgAlpha", "backgroundAlpha", "Class Resource Background Opacity", 0.3, 0, 1, ClassPowerAliases("background opacity", "background alpha", "empty background opacity", "bg alpha"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_BG_ALPHA",
    percent = true,
    step = 0.01,
})
RegisterBarsNumber("classPowerTickWidth", "separator", "Class Resource Separator Width", 1, 0, 4, ClassPowerAliases("separator", "separator width", "tick width", "pip separator", "divider", "divider width", "divider line width"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SEPARATOR",
})
RegisterBarsNumber("classPowerOutline", "outline", "Class Resource Outline", 1, 0, 4, ClassPowerAliases(
    "outline", "border", "outline width", "border width",
    "outline thickness", "border thickness", "class resource outline thickness", "class resource border thickness",
    "make outline bigger", "make outline smaller", "make class resource outline bigger", "make class resource outline smaller",
    "turn off outline", "turn on outline", "turn off class resource outline", "turn on class resource outline"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_OUTLINE",
})
RegisterBarsNumber("classPowerFilledAlpha", "filledAlpha", "Class Resource Filled Opacity", 1.0, 0, 1, ClassPowerAliases("filled opacity", "filled alpha", "active opacity"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FILLED_ALPHA",
    percent = true,
    step = 0.05,
})
RegisterBarsNumber("classPowerEmptyAlpha", "emptyAlpha", "Class Resource Empty Opacity", 0.3, 0, 1, ClassPowerAliases("empty opacity", "empty alpha", "inactive opacity"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_EMPTY_ALPHA",
    percent = true,
    step = 0.05,
})
RegisterBarsNumber("classPowerGap", "gap", "Class Resource Pip Gap", 0, 0, 8, ClassPowerAliases("pip gap", "gap", "resource gap", "point gap", "divider gap", "divider spacing", "separator spacing"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_GAP",
})
RegisterBarsString("classPowerTexture", "texture", "Class Resource Foreground Texture", "", {
    "class resource foreground texture", "class resource texture", "class power foreground texture",
    "class power texture", "resource foreground texture", "resource bar foreground texture",
}, {
    category = "Global / Class Resources",
    frameType = "classPower",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXTURE",
    normalizeValue = NormalizeInheritedTexture,
    description = "Sets the Class Resource foreground texture, or leaves it empty to inherit the global bar texture.",
})
RegisterBarsString("classPowerBgTexture", "backgroundTexture", "Class Resource Background Texture", "", {
    "class resource background texture", "class resource bg texture", "class power background texture",
    "class power bg texture", "resource background texture", "resource bar background texture",
}, {
    category = "Global / Class Resources",
    frameType = "classPower",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_BG_TEXTURE",
    normalizeValue = NormalizeForegroundTexture,
    description = "Sets the Class Resource background texture, or leaves it empty to follow the foreground texture.",
})

RegisterBarsBoolean("classPowerHideOOC", "hideOOC", "Class Resource Hide Out Of Combat", false, ClassPowerAliases("hide out of combat", "hide ooc", "out of combat hide", "hide when out of combat", "hide class resource out of combat", "hide class power out of combat", "hide class bar out of combat"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_OOC",
})
RegisterBarsBoolean("classPowerHideWhenFull", "hideFull", "Class Resource Hide When Full", false, ClassPowerAliases("hide when full", "hide full", "full hide", "hide class resource when full", "hide class power when full"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_FULL",
})
RegisterBarsBoolean("classPowerHideWhenEmpty", "hideEmpty", "Class Resource Hide When Empty", false, ClassPowerAliases("hide when empty", "hide empty", "empty hide", "hide class resource when empty", "hide class power when empty"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_EMPTY",
})

RegisterBarsEnum("detachedPowerBarWidthMode", "widthMode", "Detached Power Bar Width Mode", "manual", {
    "manual", "cooldown", "utility", "tracked_buffs",
}, {
    "detached power bar width mode", "detached power width mode", "detached mana width mode",
    "detached power bar width source", "detached power follows cooldowns", "detached power follows tracked buffs",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_WIDTH_MODE",
    nilValue = "manual",
    valueAliases = DETACHED_POWER_WIDTH_MODE_ALIASES,
})
RegisterBarsString("detachedPowerBarTexture", "texture", "Detached Power Bar Foreground Texture", "", {
    "detached power bar foreground texture", "detached power bar texture", "detached power texture",
    "detached mana foreground texture", "detached mana texture",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_TEXTURE",
    normalizeValue = NormalizeInheritedTexture,
    description = "Sets the detached power bar foreground texture, or leaves it empty to inherit the global bar texture.",
})
RegisterBarsString("detachedPowerBarBgTexture", "backgroundTexture", "Detached Power Bar Background Texture", "", {
    "detached power bar background texture", "detached power bar bg texture", "detached power background texture",
    "detached mana background texture", "detached mana bg texture",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_BG_TEXTURE",
    normalizeValue = NormalizeForegroundTexture,
    description = "Sets the detached power bar background texture, or leaves it empty to follow the foreground texture.",
})
RegisterBarsNumber("detachedPowerBarOutline", "outline", "Detached Power Bar Outline", 1, 0, 6, {
    "detached power bar outline", "detached power outline", "detached mana outline", "detached power bar border",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBarOutline,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_OUTLINE",
})

RegisterBarsBoolean("showAltMana", "altMana", "Alternative Mana Bar", false, {
    "alternative mana bar", "alt mana bar", "dual resource mana bar", "secondary mana bar",
    "show alternative mana", "show alt mana", "hide alternative mana", "hide alt mana",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA",
})
RegisterBarsNumber("altManaHeight", "height", "Alternative Mana Height", 4, 2, 30, {
    "alternative mana height", "alt mana height", "secondary mana height", "dual resource mana height",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA_HEIGHT",
})
RegisterBarsNumber("altManaOffsetY", "offsetY", "Alternative Mana Offset Y", -2, -50, 50, {
    "alternative mana y", "alternative mana y offset", "alt mana y", "alt mana y offset", "secondary mana y offset",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA_Y",
})

Registry:RegisterSetting({
    key = "menu.classPowerPreviewResource",
    label = "Class Resource Preview Resource",
    category = "Class Resources / Preview",
    unit = "global",
    frameType = "classPower",
    attribute = "classPowerPreviewResource",
    type = "enum",
    aliases = {
        "class resource preview resource",
        "class resource preview",
        "preview class resource",
        "preview class resources",
        "class power preview resource",
        "class power preview",
        "preview class power",
        "preview class bar",
        "preview resource",
        "resource preview",
    },
    values = CLASS_POWER_PREVIEW_VALUES,
    valueAliases = ClassPowerPreviewValueAliases(),
    get = function()
        if M and type(M.GetClassPowerPreviewSpecKey) == "function" then return M.GetClassPowerPreviewSpecKey() end
        return NormalizeClassPowerPreviewKey(M and M._msuf2ClassPowerPreviewSpecKey)
    end,
    set = function(value)
        value = NormalizeClassPowerPreviewKey(value)
        if M and type(M.SetClassPowerPreviewSpecKey) == "function" then
            M.SetClassPowerPreviewSpecKey(value)
        elseif M then
            M._msuf2ClassPowerPreviewSpecKey = value
        end
    end,
    apply = RefreshClassPowerPreview,
    combatSafe = true,
    description = "Selects the Class Resources page preview dropdown without changing saved class-resource settings.",
})

Registry:RegisterAction({
    key = "class_power_preview_animate",
    label = "Animate Class Resource Preview",
    type = "classPower",
    aliases = {
        "animate class resource preview",
        "animate class power preview",
        "animate class resource",
        "animate class power",
        "start class resource animation",
        "stop class resource animation",
        "start class power animation",
        "stop class power animation",
        "turn on class resource animation",
        "turn off class resource animation",
        "start class resource preview animation",
        "stop class resource preview animation",
        "toggle class resource preview animation",
        "start resource preview animation",
        "stop resource preview animation",
    },
    combatSafe = true,
    run = function(args)
        local preview = M and M._msuf2ClassPowerInlinePreview
        if not (preview and type(preview.SetPreviewAnimating) == "function") then
            return false, "Open Class Resources first, then I can animate its preview."
        end
        local value = args and args.value
        if value == nil then value = not preview._msuf2Animating end
        preview:SetPreviewAnimating(value and true or false)
        return true, value and "Started the Class Resource preview animation." or "Stopped the Class Resource preview animation."
    end,
})

Registry:RegisterAction({
    key = "class_power_quick_setup",
    label = "Quick Setup Class Bar",
    type = "classPower",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        local fn = _G.MSUF2_ClassPowerQuickSetup
        if type(fn) ~= "function" then return false, "Class Bar quick setup is not loaded yet. Open Class Resources once, then try again." end
        fn()
        return true, "Done. Started Class Bar quick setup."
    end,
})
