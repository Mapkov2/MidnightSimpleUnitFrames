-- Assistant Global registry: exposes cross-subsystem appearance and behavior controls.
-- Keep broad refreshes explicit so global setting writes do not hide runtime fanout.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Global registry domain.
-- Owns assistant entries for shared colors, fonts, textures, bar behavior, and global visuals.
-- Apply callbacks fan out to the focused runtime refreshers to avoid full addon rebuilds.
local Registry = C.Registry
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local GameplayDB = C.GameplayDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyGeneral = C.ApplyGeneral
local ApplyVisuals = C.ApplyVisuals
local ApplyColors = C.ApplyColors
local ApplyCastbarColors = C.ApplyCastbarColors
local ApplyGameplayColors = C.ApplyGameplayColors
local ApplyClassPowerColors = C.ApplyClassPowerColors
local ApplyAuraColors = C.ApplyAuraColors
local ApplyPortraitColors = C.ApplyPortraitColors
local ApplyFonts = C.ApplyFonts
local ApplyBars = C.ApplyBars
local ApplyBarGradients = C.ApplyBarGradients
local ApplyBarOutline = C.ApplyBarOutline
local ApplyRoundedBars = C.ApplyRoundedBars
local ApplyAggroBorder = C.ApplyAggroBorder
local ApplyDispelPurgeBorder = C.ApplyDispelPurgeBorder
local ApplyBossTargetBorder = C.ApplyBossTargetBorder
local ApplyHighlightBorders = C.ApplyHighlightBorders
local ApplyAbsorbBars = C.ApplyAbsorbBars
local ApplyCastbar = C.ApplyCastbar
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString
local RegisterGeneralMappedEnum = C.RegisterGeneralMappedEnum
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterGameplayBoolean = C.RegisterGameplayBoolean
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting
local RegisterScopedMappedEnum = C.RegisterScopedMappedEnum

local BAR_MODE_ALIASES = {
    "bar mode", "bar color mode", "health bar mode", "bars mode", "bars color mode",
    "dark mode", "class colors", "class color mode", "unified bars", "gradient bars",
    "leisten modus", "balken modus", "dunkler modus", "klassenfarben", "verlauf balken",
}
RegisterGeneralEnum("barMode", "barMode", "Global Bar Mode", "dark", { "dark", "class", "unified", "gradient" }, BAR_MODE_ALIASES, {
    category = "Global / Bars",
    frameType = "bars",
    apply = ApplyVisuals,
    reason = "MSUF_ASSISTANT_BAR_MODE",
    valueAliases = {
        dark = "dark",
        dunkel = "dark",
        black = "dark",
        class = "class",
        classes = "class",
        classcolor = "class",
        classcolors = "class",
        klassenfarben = "class",
        unified = "unified",
        same = "unified",
        einheitlich = "unified",
        gradient = "gradient",
        verlauf = "gradient",
    },
})

RegisterGeneralString("fontKey", "fontFamily", "Global Font", "FRIZQT", {
    "font", "font family", "global font", "shared font", "sharedmedia font",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyFonts,
    reason = "MSUF_ASSISTANT_FONT_FAMILY",
    normalizeValue = function(value)
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        return value ~= "" and value or "FRIZQT"
    end,
})

RegisterGeneralNumberSetting("fontSize", "fontSize", "Global Font Size", 14, 8, 32, {
    "font size", "global font size", "text size", "schrift groesse", "schriftgroesse", "globale schriftgroesse",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyFonts,
    reason = "MSUF_ASSISTANT_FONT_SIZE",
})

RegisterGeneralEnum("fontColor", "fontColor", "Global Font Palette Color", "white", {
    "white", "black", "red", "green", "blue", "yellow", "cyan", "magenta", "orange", "purple", "pink", "turquoise", "grey", "gray", "brown", "gold",
}, {
    "font color", "global font color", "text color", "schriftfarbe", "textfarbe",
}, {
    category = "Global / Fonts",
    frameType = "fonts",
    apply = ApplyVisuals,
    reason = "MSUF_ASSISTANT_FONT_COLOR",
    valueAliases = {
        grey = "grey",
        gray = "grey",
        weiss = "white",
        schwarz = "black",
        rot = "red",
        gruen = "green",
        blau = "blue",
        gelb = "yellow",
        lila = "purple",
        violett = "purple",
        rosa = "pink",
        tuerkis = "turquoise",
        gold = "gold",
    },
})

RegisterGeneralBoolean("slashMenuSnapEnabled", "menuSnap", "Menu Edge Snap", true, {
    "menu edge snap", "edge snap", "window snap", "menu snapping", "snapping feature", "snap feature",
    "menu snap feature", "windows style edge snap", "windows-style edge snap", "enable windows style edge snap for this menu",
    "enable windows-style edge snap for this menu", "fenster andocken",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MENU_SNAP" })
Registry:RegisterSetting({
    key = "general.hideAdvancedMenu",
    label = "Advanced Menu Section",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "advancedMenuVisible",
    type = "boolean",
    aliases = { "advanced menu", "advanced menu section", "advanced section", "hide advanced menu", "hide advanced menu section", "show advanced menu", "show advanced menu section", "erweitertes menu" },
    get = function() return GeneralDB().hideAdvancedMenu ~= true end,
    set = function(value) GeneralDB().hideAdvancedMenu = not (value and true or false) end,
    apply = function()
        ApplyGeneral("MSUF_ASSISTANT_ADVANCED_MENU", { preview = false, applyAll = false, notify = false })
        if M and type(M.RefreshAdvancedNavVisibility) == "function" then M.RefreshAdvancedNavVisibility() end
    end,
    combatSafe = false,
})
RegisterGeneralBoolean("reduceMotion", "reduceMotion", "Reduce Menu Motion", false, {
    "reduce motion", "menu motion", "animations", "reduce animations", "reduce menu motion", "menu animations", "bewegung reduzieren",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_REDUCE_MOTION" })
RegisterGeneralBoolean("showWelcomeMessage", "welcomeMessage", "Welcome Message", true, {
    "welcome message", "startup welcome", "start message", "show welcome message", "login welcome message", "startup message", "willkommensnachricht",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_WELCOME" })
RegisterGeneralBoolean("versionCheckEnabled", "versionCheck", "Peer Version Check", true, {
    "version check", "peer version check", "update check", "enable version check", "peer-to-peer version check", "version check peer to peer", "versions pruefung", "versionscheck",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_VERSION_CHECK" })
RegisterGeneralBoolean("showMinimapIcon", "minimapIcon", "MSUF Minimap Icon", true, {
    "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button", "show minimap icon", "hide minimap icon", "minikarten symbol",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MINIMAP_ICON" })
RegisterGeneralBoolean("playTargetSelectLostSounds", "targetSounds", "Target Select/Lost Sounds", false, {
    "target sounds", "target sound", "target lost sound", "target lost sounds", "target select sound", "target select sounds",
    "target select lost sounds", "play sound on target", "play sound on target lost", "play sound on target select", "ziel sound", "ziel sounds",
}, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_TARGET_SOUNDS" })
Registry:RegisterSetting({
    key = "general.disableBlizzardUnitFrames",
    label = "Blizzard Unitframes",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "blizzardFramesVisible",
    type = "boolean",
    aliases = { "blizzard unitframes", "blizzard unit frames", "disable blizzard unitframes", "disable blizzard unit frames", "enable blizzard unitframes", "enable blizzard unit frames", "blizzard frames", "standard frames", "default frames" },
    get = function() return GeneralDB().disableBlizzardUnitFrames == false end,
    set = function(value) GeneralDB().disableBlizzardUnitFrames = not (value and true or false) end,
    apply = function() ApplyGeneral("MSUF_ASSISTANT_BLIZZARD_FRAMES", { preview = false, applyAll = false }) end,
    combatSafe = false,
    requiresReload = true,
})

Registry:RegisterSetting({
    key = "general.hardKillBlizzardPlayerFrame",
    label = "Fully Hide Blizzard PlayerFrame",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "hardKillBlizzardPlayerFrame",
    type = "boolean",
    aliases = {
        "fully hide blizzard playerframe", "hard hide blizzard playerframe",
        "hard kill blizzard playerframe", "resource bar compatibility",
        "blizzard player frame compatibility", "hide blizzard player frame completely",
        "fully hide blizzard player frame", "hard hide blizzard player frame",
        "hard kill blizzard player frame", "fully hide blizzard playerframe resource bar compatibility",
        "fully hide blizzard playerframe - resource bar compatibility",
    },
    get = function() return GeneralDB().hardKillBlizzardPlayerFrame == true end,
    set = function(value) GeneralDB().hardKillBlizzardPlayerFrame = value and true or false end,
    apply = function()
        ApplyGeneral("MSUF_ASSISTANT_HARDKILL_PLAYERFRAME", { preview = false, applyAll = false })
        if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then _G.MSUF_ShowReloadRecommendedPopup("Blizzard PlayerFrame hide mode") end
    end,
    combatSafe = false,
    requiresReload = true,
})

Registry:RegisterSetting({
    key = "general.menuLocale",
    label = "Menu Language",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "menuLocale",
    type = "enum",
    aliases = { "menu language", "msuf language", "menu locale", "locale", "language" },
    values = { "auto", "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" },
    valueAliases = {
        auto = "auto",
        blizzard = "auto",
        default = "auto",
        english = "enUS",
        ["english us"] = "enUS",
        ["us english"] = "enUS",
        ["english gb"] = "enGB",
        ["british english"] = "enGB",
        german = "deDE",
        deutsch = "deDE",
        spanish = "esES",
        ["spanish eu"] = "esES",
        ["spanish mx"] = "esMX",
        mexican = "esMX",
        french = "frFR",
        francais = "frFR",
        italian = "itIT",
        portuguese = "ptBR",
        brazilian = "ptBR",
        russian = "ruRU",
        korean = "koKR",
        chinese = "zhCN",
        simplified = "zhCN",
        traditional = "zhTW",
        taiwan = "zhTW",
    },
    get = function()
        local value = GeneralDB().menuLocale
        if value == "enUS" or value == "enGB" or value == "deDE" or value == "esES" or value == "esMX"
            or value == "frFR" or value == "itIT" or value == "ptBR" or value == "ruRU"
            or value == "koKR" or value == "zhCN" or value == "zhTW"
        then
            return value
        end
        return "auto"
    end,
    set = function(value) GeneralDB().menuLocale = tostring(value or "auto") end,
    apply = function()
        local value = GeneralDB().menuLocale or "auto"
        ApplyGeneral("MSUF_ASSISTANT_LOCALE", { preview = false, applyAll = false })
        if M and type(M.ApplyLocaleSelection) == "function" then M.ApplyLocaleSelection(value) end
        if M and type(M.InvalidatePage) == "function" then M.InvalidatePage() end
        if M and type(M.SelectPage) == "function" then M.SelectPage("opt_misc") end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "general.unitTooltipProvider",
    label = "Unitframe Tooltip Source",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipProvider",
    type = "enum",
    aliases = { "tooltip source", "unitframe tooltip source", "unit tooltip source", "group frame tooltip source", "game tooltip source", "gametooltip source" },
    values = { "GAME", "MSUF" },
    valueAliases = {
        game = "GAME",
        gametooltip = "GAME",
        blizzard = "GAME",
        addoncompatible = "GAME",
        msuf = "MSUF",
        custom = "MSUF",
        panel = "MSUF",
    },
    get = function() return A.Workflow.ReadTooltipProvider() end,
    set = function(value) A.Workflow.WriteTooltipSettings(value, A.Workflow.ReadTooltipAnchor()) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipAnchor",
    label = "Unitframe Tooltip Anchor",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipAnchor",
    type = "enum",
    aliases = { "tooltip anchor", "unitframe tooltip anchor", "unit tooltip anchor", "tooltip position", "tooltip location" },
    values = { "EXTERNAL", "FIXED", "CURSOR" },
    valueAliases = {
        external = "EXTERNAL",
        addon = "EXTERNAL",
        blizzard = "EXTERNAL",
        fixed = "FIXED",
        msuffixed = "FIXED",
        cursor = "CURSOR",
        mouse = "CURSOR",
        modern = "CURSOR",
    },
    get = function() return A.Workflow.ReadTooltipAnchor() end,
    set = function(value) A.Workflow.WriteTooltipSettings(A.Workflow.ReadTooltipProvider(), value) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipMode",
    label = "Show Unitframe Tooltips",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipMode",
    type = "enum",
    aliases = { "show unitframe tooltips", "unitframe tooltips", "unit frame tooltips", "unit tooltips", "group frame tooltips", "tooltips", "show tooltips", "tooltip mode", "tooltip visibility" },
    values = { "ALWAYS", "OOC", "MODIFIER", "NEVER" },
    valueAliases = {
        always = "ALWAYS",
        on = "ALWAYS",
        show = "ALWAYS",
        ooc = "OOC",
        outofcombat = "OOC",
        ["out of combat"] = "OOC",
        modifier = "MODIFIER",
        key = "MODIFIER",
        alt = "MODIFIER",
        ctrl = "MODIFIER",
        shift = "MODIFIER",
        never = "NEVER",
        off = "NEVER",
        hide = "NEVER",
        disable = "NEVER",
    },
    get = function() return A.Workflow.NormalizeTooltipMode(GeneralDB().unitTooltipMode) end,
    set = function(value) A.Workflow.WriteTooltipBehavior(value, GeneralDB().unitTooltipModifier or "ALT") end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.unitTooltipModifier",
    label = "Tooltip Modifier Key",
    category = "Global / Misc",
    unit = "global",
    frameType = "misc",
    attribute = "tooltipModifier",
    type = "enum",
    aliases = { "tooltip modifier", "tooltip modifier key", "unit tooltip modifier", "unitframe tooltip modifier" },
    values = { "ALT", "CTRL", "SHIFT" },
    valueAliases = {
        alt = "ALT",
        option = "ALT",
        ctrl = "CTRL",
        control = "CTRL",
        shift = "SHIFT",
    },
    get = function() return A.Workflow.NormalizeTooltipModifier(GeneralDB().unitTooltipModifier) end,
    set = function(value) A.Workflow.WriteTooltipBehavior(GeneralDB().unitTooltipMode or "MODIFIER", value) end,
    apply = function() A.Workflow.RefreshTooltipPreview() end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.styleEnabled",
    label = "MSUF Style Module",
    category = "Modules / Style",
    unit = "global",
    frameType = "modules",
    attribute = "styleEnabled",
    type = "boolean",
    aliases = { "msuf style", "msuf style module", "midnight style", "style module", "module style" },
    get = function() return A.Workflow.ModuleStyleEnabled() end,
    set = function(value) A.Workflow.SetModuleStyleEnabled(value and true or false) end,
    apply = function() CallGlobal("MSUF_ApplyModules") end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "general.dropdownStyleMode",
    label = "Dropdown Style",
    category = "Modules / Style",
    unit = "global",
    frameType = "modules",
    attribute = "dropdownStyle",
    type = "enum",
    aliases = { "dropdown style", "dropdown style mode", "dropdown module style", "menu dropdown style" },
    values = { "msuf", "old" },
    valueAliases = {
        msuf = "msuf",
        modern = "msuf",
        superellipse = "msuf",
        midnight = "msuf",
        old = "old",
        legacy = "old",
        blizzard = "old",
        classic = "old",
    },
    get = function() return A.Workflow.DropdownStyleMode() end,
    set = function(value) A.Workflow.SetDropdownStyleMode(value) end,
    apply = function() end,
    combatSafe = true,
})

RegisterGeneralBoolean("castbarShowGlow", "glow", "Castbar Glow", false, {
    "castbar glow", "cast bar glow", "castbar glow effect", "zauberleiste glow",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_GLOW" })
RegisterGeneralBoolean("castbarShowLatency", "latency", "Castbar Latency Indicator", true, {
    "castbar latency", "latency indicator", "castbar latency indicator", "latenz anzeige",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_LATENCY" })
RegisterGeneralBoolean("castbarShowSpark", "spark", "Castbar Spark", false, {
    "castbar spark", "spark", "leading edge highlight", "zauberleiste spark",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK" })
RegisterGeneralBoolean("castbarSparkOverflow", "sparkOverflow", "Castbar Spark Overflow", true, {
    "spark overflow", "castbar spark overflow", "spark extends beyond bar",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK_OVERFLOW" })
RegisterGeneralBoolean("castbarShowChannelTicks", "channelTicks", "Castbar Channel Tick Lines", false, {
    "channel ticks", "castbar ticks", "tick lines", "kanal ticks",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TICKS" })
RegisterGeneralBoolean("castbarInterruptShake", "interruptShake", "Castbar Interrupt Shake", false, {
    "interrupt shake", "castbar shake", "shake on interrupt", "unterbrechung wackeln",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE" })
RegisterGeneralBoolean("castbarUnifiedDirection", "unifiedDirection", "Unified Castbar Fill Direction", false, {
    "castbar unified direction", "same castbar direction", "all castbars same direction",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_UNIFIED_DIRECTION" })
RegisterGeneralBoolean("castbarOpositeDirectionTarget", "oppositeTargetDirection", "Opposite Fill Direction For Target", false, {
    "opposite target castbar direction", "target opposite fill direction", "target castbar opposite direction",
    "target castbar normal direction", "target castbar same direction", "target castbar not opposite",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TARGET_DIRECTION" })
RegisterGeneralNumberSetting("castbarShakeStrength", "shakeStrength", "Castbar Shake Strength", 8, 0, 30, {
    "castbar shake strength", "shake strength", "interrupt shake strength",
}, { category = "Global / Castbar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE_STRENGTH" })
RegisterGeneralEnum("castbarFillDirection", "fillDirection", "Castbar Fill Direction", "RTL", { "RTL", "LTR" }, {
    "castbar fill direction", "fill direction", "cast direction", "zauberleiste fuellrichtung",
    "castbar reverse fill", "castbar fill backwards", "castbar fill normal", "castbar normal direction",
}, {
    category = "Global / Castbar",
    frameType = "castbarGlobal",
    apply = ApplyCastbar,
    reason = "MSUF_ASSISTANT_CASTBAR_FILL_DIRECTION",
    valueAliases = {
        left = "RTL",
        rtl = "RTL",
        righttoleft = "RTL",
        backwards = "RTL",
        backward = "RTL",
        reverse = "RTL",
        reversed = "RTL",
        links = "RTL",
        right = "LTR",
        ltr = "LTR",
        lefttoright = "LTR",
        normal = "LTR",
        forward = "LTR",
        rechts = "LTR",
    },
})


A.GlobalRegistry = A.GlobalRegistry or {}
A.GlobalRegistry.Actions = {
    Registry = Registry,
    M = M,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeSetOverride = GlobalScopeSetOverride,
    GlobalScopeLabel = GlobalScopeLabel,
    GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
    ApplyBars = ApplyBars,
    ApplyFonts = ApplyFonts,
    ApplyAbsorbBars = ApplyAbsorbBars,
}

A.GlobalRegistry = A.GlobalRegistry or {}
A.GlobalRegistry.ColorSettings = {
    Registry = Registry,
    M = M,
    MSUF = MSUF,
    EnsureDB = EnsureDB,
    GeneralDB = GeneralDB,
    BarsDB = BarsDB,
    GameplayDB = GameplayDB,
    ClampNumber = ClampNumber,
    CallGlobal = CallGlobal,
    ApplyGeneral = ApplyGeneral,
    ApplyVisuals = ApplyVisuals,
    ApplyColors = ApplyColors,
    ApplyCastbarColors = ApplyCastbarColors,
    ApplyGameplayColors = ApplyGameplayColors,
    ApplyClassPowerColors = ApplyClassPowerColors,
    ApplyAuraColors = ApplyAuraColors,
    ApplyPortraitColors = ApplyPortraitColors,
    ApplyBarOutline = ApplyBarOutline,
    RegisterGeneralBoolean = RegisterGeneralBoolean,
    RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
    RegisterGeneralEnum = RegisterGeneralEnum,
    RegisterGameplayBoolean = RegisterGameplayBoolean,
    GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeLabel = GlobalScopeLabel,
    GlobalScopeRead = GlobalScopeRead,
    GlobalScopeWrite = GlobalScopeWrite,
    GlobalScopeAliases = GlobalScopeAliases,
}
