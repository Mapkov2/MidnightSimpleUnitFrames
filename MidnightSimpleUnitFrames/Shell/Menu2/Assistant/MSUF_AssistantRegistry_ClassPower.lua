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

local CLASS_POWER_WIDTH_MODE_ALIASES = {
    player = "player",
    frame = "player",
    playerframe = "player",
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

RegisterBarsBoolean("showClassPower", "enabled", "Class Resource", true, {
    "class power enabled", "class resource enabled", "class resources enabled",
    "class power bar enabled", "class resource bar enabled", "resource bar enabled",
}, {
    requiresReload = true,
    reason = "MSUF_ASSISTANT_CLASSPOWER_ENABLED",
    matchLabel = false,
    description = "Enables or disables MSUF Class Resources. Reload UI is required for the change to fully take effect.",
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

RegisterBarsBoolean("classPowerAnchorToCooldown", "anchorToCooldown", "Class Resource Anchor To Essential Cooldowns", false, ClassPowerAliases("anchor to cooldown", "class resource anchor to essential cooldowns", "class power follow cooldowns"), {
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
}, ClassPowerAliases("combo point color mode", "combo point colors", "combo colors"), {
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
RegisterBarsNumber("classPowerTickWidth", "separator", "Class Resource Separator Width", 1, 0, 4, ClassPowerAliases("separator", "separator width", "tick width", "pip separator"), {
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
RegisterBarsNumber("classPowerGap", "gap", "Class Resource Pip Gap", 0, 0, 8, ClassPowerAliases("pip gap", "gap", "resource gap", "point gap"), {
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
