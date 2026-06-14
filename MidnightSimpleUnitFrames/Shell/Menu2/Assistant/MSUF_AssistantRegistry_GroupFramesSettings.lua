local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames assistant setting domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for shared group helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.Settings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local AddAliasesForUnit = ctx.AddAliasesForUnit
local GroupDB = ctx.GroupDB
local ClampNumber = ctx.ClampNumber
local ApplyGroup = ctx.ApplyGroup
local RegisterGroupBoolean = ctx.RegisterGroupBoolean
local RegisterGroupNumber = ctx.RegisterGroupNumber
local RegisterGroupEnum = ctx.RegisterGroupEnum
local RegisterGroupString = ctx.RegisterGroupString
local RegisterGroupColor = ctx.RegisterGroupColor
local RegisterGroupTexture = ctx.RegisterGroupTexture
local RegisterGroupTextMode = ctx.RegisterGroupTextMode
local RegisterGroupDelimiter = ctx.RegisterGroupDelimiter
local GroupReverseFillExactAliases = ctx.GroupReverseFillExactAliases
local GroupReverseFillBooleanAliases = ctx.GroupReverseFillBooleanAliases
local GroupNameShorteningMax = ctx.GroupNameShorteningMax
local GroupNameShorteningEnabled = ctx.GroupNameShorteningEnabled
local GroupNameShorteningSide = ctx.GroupNameShorteningSide
local GroupNameShorteningNoEllipsis = ctx.GroupNameShorteningNoEllipsis
local SetGroupFontOverrideValue = ctx.SetGroupFontOverrideValue
local GroupGrowthExactAliases = ctx.GroupGrowthExactAliases
local NormalizeGroupRoleOrder = ctx.NormalizeGroupRoleOrder
local StandardGroupAnchorTarget = ctx.StandardGroupAnchorTarget
local TrimString = ctx.TrimString
local GroupBarModeExactAliases = ctx.GroupBarModeExactAliases
local GroupColorSame = ctx.GroupColorSame
local GetGroupHealthBarColor = ctx.GetGroupHealthBarColor
local SetGroupHealthBarColor = ctx.SetGroupHealthBarColor
local NormalizeGroupDispelTrigger = ctx.NormalizeGroupDispelTrigger
local AddGroupStatusIconAliases = ctx.AddGroupStatusIconAliases
local GROUP_BAR_MODE_VALUES = ctx.GROUP_BAR_MODE_VALUES or {}
local GROUP_HEALTH_MODE_VALUES = ctx.GROUP_HEALTH_MODE_VALUES or {}
local GROUP_ANCHOR_VALUES = ctx.GROUP_ANCHOR_VALUES or {}
local GROUP_ANCHOR_ALIASES = ctx.GROUP_ANCHOR_ALIASES or {}
local GROUP_DISPEL_TRIGGER_VALUES = ctx.GROUP_DISPEL_TRIGGER_VALUES or {}
local GROUP_DISPEL_STYLE_VALUES = ctx.GROUP_DISPEL_STYLE_VALUES or {}
local GROUP_STRIPE_EDGE_VALUES = ctx.GROUP_STRIPE_EDGE_VALUES or {}
local GROUP_RANGE_LAYER_VALUES = ctx.GROUP_RANGE_LAYER_VALUES or {}
local GROUP_STATUS_ICON_STYLE_VALUES = ctx.GROUP_STATUS_ICON_STYLE_VALUES or {}
local GROUP_STATUS_ICON_STYLE_ALIASES = ctx.GROUP_STATUS_ICON_STYLE_ALIASES or {}
local GROUP_STATUS_ICON_PACK_VALUES = ctx.GROUP_STATUS_ICON_PACK_VALUES or {}
local GROUP_STATUS_ICON_PACK_ALIASES = ctx.GROUP_STATUS_ICON_PACK_ALIASES or {}
local GROUP_STATUS_ANCHOR_VALUES = ctx.GROUP_STATUS_ANCHOR_VALUES or {}
local GROUP_STATUS_ANCHOR_ALIASES = ctx.GROUP_STATUS_ANCHOR_ALIASES or {}
local GROUP_STATUS_ICON_SPECS = ctx.GROUP_STATUS_ICON_SPECS or {}

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
if type(ApplyGroup) ~= "function" or type(ClampNumber) ~= "function" then return end
if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end

do
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    local aliases = {}
    AddAliasesForUnit(aliases, scope, "frames", "frames")
    AddAliasesForUnit(aliases, scope, "group frames", "gruppenframes")
    RegisterGroupBoolean(scope, "enabled", "enabled", "Frames Enabled", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade", "range fade")
    AddAliasesForUnit(aliases, scope, "range fading", "reichweite fade")
    RegisterGroupBoolean(scope, "rangeFade", "rangeFadeEnabled", "Range Fade", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show player", "spieler anzeigen")
    AddAliasesForUnit(aliases, scope, "player in group", "spieler in gruppe")
    AddAliasesForUnit(aliases, scope, "player in group frames")
    AddAliasesForUnit(aliases, scope, "show player in group")
    AddAliasesForUnit(aliases, scope, "show player in group frames")
    AddAliasesForUnit(aliases, scope, "show player when solo")
    AddAliasesForUnit(aliases, scope, "show player in group when solo")
    RegisterGroupBoolean(scope, "showPlayer", "showPlayer", "Show Player", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show solo", "solo anzeigen")
    AddAliasesForUnit(aliases, scope, "solo mode", "solo modus")
    AddAliasesForUnit(aliases, scope, "show while solo")
    AddAliasesForUnit(aliases, scope, "show frame while solo")
    AddAliasesForUnit(aliases, scope, "show frame when solo")
    AddAliasesForUnit(aliases, scope, "show group while solo")
    AddAliasesForUnit(aliases, scope, "show group frame while solo")
    AddAliasesForUnit(aliases, scope, "show group frame when solo")
    AddAliasesForUnit(aliases, scope, "show group frames while solo")
    AddAliasesForUnit(aliases, scope, "hide frame while solo")
    AddAliasesForUnit(aliases, scope, "hide frame when solo")
    AddAliasesForUnit(aliases, scope, "hide group frame while solo")
    AddAliasesForUnit(aliases, scope, "hide group frame when solo")
    RegisterGroupBoolean(scope, "showSolo", "showSolo", "Show While Solo", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "click casting", "klick zauber")
    AddAliasesForUnit(aliases, scope, "clique", "clique")
    RegisterGroupBoolean(scope, "clickCast", "clickCastEnabled", "Click Casting", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "blizzard fallback", "blizzard fallback")
    AddAliasesForUnit(aliases, scope, "fallback mode", "fallback modus")
    AddAliasesForUnit(aliases, scope, "disabled group frame behavior")
    RegisterGroupEnum(scope, "blizzardFallbackMode", "blizzardFallbackMode", "Blizzard Fallback Mode", "AUTO", { "AUTO", "SHOW", "NONE" }, {
        auto = "AUTO",
        automatic = "AUTO",
        default = "AUTO",
        blizzarddefault = "AUTO",
        ["blizzard default"] = "AUTO",
        show = "SHOW",
        force = "SHOW",
        forceblizzard = "SHOW",
        ["force blizzard"] = "SHOW",
        forceblizzardframes = "SHOW",
        hide = "NONE",
        none = "NONE",
        off = "NONE",
        hideall = "NONE",
        ["hide all"] = "NONE",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide during client scene", "client szene ausblenden")
    AddAliasesForUnit(aliases, scope, "hide in client scene")
    RegisterGroupBoolean(scope, "hideInClientScene", "hideInClientScene", "Hide During Client Scene", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline members", "offline spieler ausblenden")
    AddAliasesForUnit(aliases, scope, "offline members")
    RegisterGroupBoolean(scope, "hideOfflineEnabled", "hideOfflineEnabled", "Hide Offline Members", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline in combat", "offline im kampf ausblenden")
    AddAliasesForUnit(aliases, scope, "combat offline hide")
    RegisterGroupBoolean(scope, "hideOfflineInCombat", "hideOfflineInCombat", "Hide Offline In Combat", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline delay", "offline ausblenden verzoegerung")
    AddAliasesForUnit(aliases, scope, "hide offline after")
    AddAliasesForUnit(aliases, scope, "offline delay")
    RegisterGroupNumber(scope, "hideOfflineDelay", "hideOfflineDelay", "Hide Offline Delay", 0, 0, 120, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "smooth fill", "weiche fuellung")
    AddAliasesForUnit(aliases, scope, "smooth health", "weiche leben")
    RegisterGroupBoolean(scope, "smoothFill", "smoothFill", "Smooth Health Fill", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse fill", "fuellung umkehren")
    AddAliasesForUnit(aliases, scope, "reverse health fill", "leben umkehren")
    AddAliasesForUnit(aliases, scope, "fill backwards")
    AddAliasesForUnit(aliases, scope, "backwards fill")
    AddAliasesForUnit(aliases, scope, "right to left fill")
    AddAliasesForUnit(aliases, scope, "fill right to left")
    AddAliasesForUnit(aliases, scope, "normal fill")
    AddAliasesForUnit(aliases, scope, "left to right fill")
    RegisterGroupBoolean(scope, "reverseFill", "reverseFill", "Reverse Health Fill", false, "visual", aliases, {
        exactAliases = GroupReverseFillExactAliases(scope),
        booleanAliases = GroupReverseFillBooleanAliases(scope),
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name", "name")
    AddAliasesForUnit(aliases, scope, "names", "namen")
    RegisterGroupBoolean(scope, "name", "showName", "Names", true, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text", "leben text")
    AddAliasesForUnit(aliases, scope, "health text", "gesundheit text")
    RegisterGroupBoolean(scope, "hpText", "showHPText", "HP Text", true, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text", "power text")
    AddAliasesForUnit(aliases, scope, "mana text", "mana text")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".showPowerText",
        label = UNIT_LABELS[scope] .. " Power Text",
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = "powerText",
        type = "boolean",
        aliases = aliases,
        get = function()
            local db = GroupDB(scope)
            return db.showPowerText == true or db.showPower == true
        end,
        set = function(value)
            local enabled = value and true or false
            local db = GroupDB(scope)
            db.showPowerText = enabled
            db.showPower = enabled
        end,
        apply = function() ApplyGroup(scope, "font") end,
        combatSafe = false,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power bar", "power balken")
    AddAliasesForUnit(aliases, scope, "mana bar", "mana balken")
    RegisterGroupBoolean(scope, "powerBar", "powerBarEnabled", "Power Bar", true, "rebuild", aliases)

    local widthDefault = scope == "party" and 120 or 80
    local heightDefault = scope == "party" and 40 or 32
    local powerHeightDefault = scope == "party" and 6 or 4
    local hpFontDefault = scope == "party" and 10 or 9
    local nameFontDefault = scope == "party" and 12 or 10
    local textCenterDefault = scope == "party" and "PERCENT" or "NONE"
    local maxColumnsDefault = scope == "party" and 1 or 8

    aliases = {}
    AddAliasesForUnit(aliases, scope, "width", "breite")
    AddAliasesForUnit(aliases, scope, "frame width", "frame breite")
    RegisterGroupNumber(scope, "width", "width", "Width", widthDefault, 40, 300, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "height", "hoehe")
    AddAliasesForUnit(aliases, scope, "frame height", "frame hoehe")
    RegisterGroupNumber(scope, "height", "height", "Height", heightDefault, 16, 120, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "frame", "frame")
    AddAliasesForUnit(aliases, scope, "frame position", "frame position")
    AddAliasesForUnit(aliases, scope, "x position", "x position")
    AddAliasesForUnit(aliases, scope, "x offset", "x versatz")
    AddAliasesForUnit(aliases, scope, "frame x", "frame x")
    AddAliasesForUnit(aliases, scope, "frame x offset", "frame x versatz")
    AddAliasesForUnit(aliases, scope, "horizontal position", "horizontale position")
    RegisterGroupNumber(scope, "offsetX", "offsetX", "X Position", 0, -4096, 4096, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "frame", "frame")
    AddAliasesForUnit(aliases, scope, "frame position", "frame position")
    AddAliasesForUnit(aliases, scope, "y position", "y position")
    AddAliasesForUnit(aliases, scope, "y offset", "y versatz")
    AddAliasesForUnit(aliases, scope, "frame y", "frame y")
    AddAliasesForUnit(aliases, scope, "frame y offset", "frame y versatz")
    AddAliasesForUnit(aliases, scope, "vertical position", "vertikale position")
    RegisterGroupNumber(scope, "offsetY", "offsetY", "Y Position", 0, -4096, 4096, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spacing", "abstand")
    AddAliasesForUnit(aliases, scope, "frame spacing", "frame abstand")
    AddAliasesForUnit(aliases, scope, "space between frames")
    AddAliasesForUnit(aliases, scope, "gap between frames")
    AddAliasesForUnit(aliases, scope, "closer together")
    AddAliasesForUnit(aliases, scope, "farther apart")
    AddAliasesForUnit(aliases, scope, "more space between frames")
    AddAliasesForUnit(aliases, scope, "less space between frames")
    RegisterGroupNumber(scope, "spacing", "spacing", "Spacing", 1, 0, 20, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "units per column", "einheiten pro spalte")
    AddAliasesForUnit(aliases, scope, "members per column", "spieler pro spalte")
    AddAliasesForUnit(aliases, scope, "players per column")
    AddAliasesForUnit(aliases, scope, "frames per column")
    RegisterGroupNumber(scope, "unitsPerColumn", "unitsPerColumn", "Units Per Column", 5, 1, 40, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "max columns", "max spalten")
    AddAliasesForUnit(aliases, scope, "columns", "spalten")
    AddAliasesForUnit(aliases, scope, "frames in columns")
    AddAliasesForUnit(aliases, scope, "number of columns")
    RegisterGroupNumber(scope, "maxColumns", "maxColumns", "Max Columns", maxColumnsDefault, 1, 8, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "preserve raid groups", "raid gruppen beibehalten")
    AddAliasesForUnit(aliases, scope, "keep raid groups")
    RegisterGroupBoolean(scope, "preserveRaidGroups", "preserveRaidGroups", "Preserve Raid Groups", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power height", "power hoehe")
    AddAliasesForUnit(aliases, scope, "power bar height", "power balken hoehe")
    RegisterGroupNumber(scope, "powerHeight", "powerHeight", "Power Bar Height", powerHeightDefault, 0, 30, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name font size", "name schriftgroesse")
    AddAliasesForUnit(aliases, scope, "name size", "name groesse")
    AddAliasesForUnit(aliases, scope, "names font size")
    AddAliasesForUnit(aliases, scope, "names size")
    RegisterGroupNumber(scope, "nameFontSize", "nameFontSize", "Name Font Size", nameFontDefault, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp font size", "leben schriftgroesse")
    AddAliasesForUnit(aliases, scope, "health font size", "gesundheit schriftgroesse")
    AddAliasesForUnit(aliases, scope, "hp text size")
    AddAliasesForUnit(aliases, scope, "health text size")
    RegisterGroupNumber(scope, "hpFontSize", "hpFontSize", "HP Font Size", hpFontDefault, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power font size", "power schriftgroesse")
    AddAliasesForUnit(aliases, scope, "mana font size", "mana schriftgroesse")
    AddAliasesForUnit(aliases, scope, "power text size")
    AddAliasesForUnit(aliases, scope, "mana text size")
    RegisterGroupNumber(scope, "powerFontSize", "powerFontSize", "Power Font Size", 9, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name max chars", "name max zeichen")
    AddAliasesForUnit(aliases, scope, "name length", "name laenge")
    RegisterGroupNumber(scope, "nameMaxChars", "nameMaxChars", "Name Max Characters", 0, 0, 30, 1, "font", aliases, {
        get = GroupNameShorteningMax,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameMaxChars", ClampNumber(value, 0, 30, 1))
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "shorten group names")
    AddAliasesForUnit(aliases, scope, "shorten names")
    AddAliasesForUnit(aliases, scope, "name shortening")
    RegisterGroupBoolean(scope, "nameShortening", "nameShortenEnabled", "Name Shortening", false, "font", aliases, {
        get = GroupNameShorteningEnabled,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameShortenEnabled", value and true or false)
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name truncation style")
    AddAliasesForUnit(aliases, scope, "truncation style")
    AddAliasesForUnit(aliases, scope, "name clip side")
    RegisterGroupEnum(scope, "nameClipSide", "nameClipSide", "Name Truncation Style", "RIGHT", { "LEFT", "RIGHT" }, {
        left = "LEFT",
        endletters = "LEFT",
        ["keep end"] = "LEFT",
        right = "RIGHT",
        startletters = "RIGHT",
        ["keep start"] = "RIGHT",
    }, "font", aliases, {
        get = GroupNameShorteningSide,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameClipSide", value == "LEFT" and "LEFT" or "RIGHT")
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "no ellipsis")
    AddAliasesForUnit(aliases, scope, "name no ellipsis")
    AddAliasesForUnit(aliases, scope, "truncate without dots")
    RegisterGroupBoolean(scope, "nameNoEllipsis", "nameNoEllipsis", "Name No Ellipsis", false, "font", aliases, {
        get = GroupNameShorteningNoEllipsis,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameNoEllipsis", value and true or false)
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade alpha", "reichweite fade alpha")
    AddAliasesForUnit(aliases, scope, "out of range alpha", "ausser reichweite alpha")
    AddAliasesForUnit(aliases, scope, "range fade opacity")
    AddAliasesForUnit(aliases, scope, "out of range opacity")
    RegisterGroupNumber(scope, "rangeFadeAlpha", "rangeFadeAlpha", "Range Fade Alpha", 0.4, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "growth", "wachstum")
    AddAliasesForUnit(aliases, scope, "growth direction", "wachstumsrichtung")
    AddAliasesForUnit(aliases, scope, "grow")
    AddAliasesForUnit(aliases, scope, "to grow")
    AddAliasesForUnit(aliases, scope, "grow direction")
    AddAliasesForUnit(aliases, scope, "frames grow")
    AddAliasesForUnit(aliases, scope, "frames to grow")
    RegisterGroupEnum(scope, "growth", "growth", "Growth Direction", "DOWN", { "DOWN", "UP", "RIGHT", "LEFT" }, {
        ["right then down"] = "RIGHT",
        ["right and down"] = "RIGHT",
        ["right first"] = "RIGHT",
        ["grow right"] = "RIGHT",
        ["to the right"] = "RIGHT",
        horizontal = "RIGHT",
        horizontally = "RIGHT",
        down = "DOWN",
        ["down then right"] = "DOWN",
        ["down and right"] = "DOWN",
        ["down first"] = "DOWN",
        ["grow down"] = "DOWN",
        downwards = "DOWN",
        vertical = "DOWN",
        vertically = "DOWN",
        runter = "DOWN",
        unten = "DOWN",
        up = "UP",
        ["up then right"] = "UP",
        ["up and right"] = "UP",
        ["up first"] = "UP",
        ["grow up"] = "UP",
        upwards = "UP",
        hoch = "UP",
        oben = "UP",
        right = "RIGHT",
        rechts = "RIGHT",
        left = "LEFT",
        ["left then down"] = "LEFT",
        ["left and down"] = "LEFT",
        ["left first"] = "LEFT",
        ["grow left"] = "LEFT",
        ["to the left"] = "LEFT",
        links = "LEFT",
    }, "rebuild", aliases, {
        exactAliases = GroupGrowthExactAliases(scope),
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health text center", "leben text mitte")
    AddAliasesForUnit(aliases, scope, "hp text center", "hp text mitte")
    AddAliasesForUnit(aliases, scope, "center text", "text mitte")
    AddAliasesForUnit(aliases, scope, "center hp text", "hp text mitte")
    RegisterGroupEnum(scope, "healthTextCenter", "textCenter", "Center HP Text", textCenterDefault, { "NONE", "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX" }, {
        none = "NONE",
        off = "NONE",
        aus = "NONE",
        percent = "PERCENT",
        percentage = "PERCENT",
        prozent = "PERCENT",
        current = "CURRENT",
        aktuell = "CURRENT",
        max = "MAX",
        deficit = "DEFICIT",
        missing = "DEFICIT",
        curmax = "CURMAX",
        currentmax = "CURMAX",
        currentpercent = "CURPERCENT",
        currentpercentage = "CURPERCENT",
    }, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort mode", "sortierung")
    AddAliasesForUnit(aliases, scope, "sort order", "sortiermodus")
    RegisterGroupEnum(scope, "sortMode", "sortMode", "Sort Mode", "INDEX", { "INDEX", "ROLE", "GROUP", "GROUP_ROLE", "NAME" }, {
        index = "INDEX",
        default = "INDEX",
        simple = "INDEX",
        off = "INDEX",
        disable = "INDEX",
        disabled = "INDEX",
        role = "ROLE",
        roles = "ROLE",
        byrole = "ROLE",
        ["by role"] = "ROLE",
        group = "GROUP",
        raidgroup = "GROUP",
        ["raid group"] = "GROUP",
        group_role = "GROUP_ROLE",
        grouprole = "GROUP_ROLE",
        ["group role"] = "GROUP_ROLE",
        ["group and role"] = "GROUP_ROLE",
        ["group plus role"] = "GROUP_ROLE",
        name = "NAME",
        alphabetical = "NAME",
        alpha = "NAME",
    }, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            local mode = conf.sortMode
            if mode == "INDEX" or mode == "ROLE" or mode == "GROUP" or mode == "GROUP_ROLE" or mode == "NAME" then return mode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value ~= "ROLE" and value ~= "GROUP" and value ~= "GROUP_ROLE" and value ~= "NAME" then value = "INDEX" end
            conf.sortMode = value
            conf.sortByRole = value == "ROLE"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort by role")
    AddAliasesForUnit(aliases, scope, "role sorting")
    AddAliasesForUnit(aliases, scope, "sort roles")
    RegisterGroupBoolean(scope, "sortByRole", "sortByRole", "Sort By Role", false, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.sortByRole = value and true or false
            conf.sortMode = value and "ROLE" or "INDEX"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "player first in role")
    AddAliasesForUnit(aliases, scope, "player first")
    RegisterGroupBoolean(scope, "playerFirstInRole", "playerFirstInRole", "Player First In Role", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role priority order")
    AddAliasesForUnit(aliases, scope, "role order")
    AddAliasesForUnit(aliases, scope, "role sorting order")
    RegisterGroupEnum(scope, "roleOrder", "roleOrder", "Role Priority Order", "TANK,HEALER,DAMAGER", {
        "TANK,HEALER,DAMAGER", "TANK,DAMAGER,HEALER", "HEALER,TANK,DAMAGER",
        "HEALER,DAMAGER,TANK", "DAMAGER,TANK,HEALER", "DAMAGER,HEALER,TANK",
    }, {
        ["tank healer dps"] = "TANK,HEALER,DAMAGER",
        ["tank heal dps"] = "TANK,HEALER,DAMAGER",
        ["tank dps healer"] = "TANK,DAMAGER,HEALER",
        ["tank dps heal"] = "TANK,DAMAGER,HEALER",
        ["healer tank dps"] = "HEALER,TANK,DAMAGER",
        ["heal tank dps"] = "HEALER,TANK,DAMAGER",
        ["healer dps tank"] = "HEALER,DAMAGER,TANK",
        ["heal dps tank"] = "HEALER,DAMAGER,TANK",
        ["dps tank healer"] = "DAMAGER,TANK,HEALER",
        ["dps tank heal"] = "DAMAGER,TANK,HEALER",
        ["dps healer tank"] = "DAMAGER,HEALER,TANK",
        ["dps heal tank"] = "DAMAGER,HEALER,TANK",
    }, "rebuild", aliases, {
        get = function(scopeKey) return NormalizeGroupRoleOrder(GroupDB(scopeKey).roleOrder) end,
        set = function(scopeKey, value) GroupDB(scopeKey).roleOrder = NormalizeGroupRoleOrder(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale mode", "skalierungsmodus")
    AddAliasesForUnit(aliases, scope, "group scale mode")
    RegisterGroupEnum(scope, "frameScaleMode", "frameScaleMode", "Frame Scaling Mode", "off", { "off", "manual", "auto" }, {
        off = "off",
        none = "off",
        disable = "off",
        disabled = "off",
        ["false"] = "off",
        manual = "manual",
        on = "manual",
        enable = "manual",
        enabled = "manual",
        custom = "manual",
        auto = "auto",
        automatic = "auto",
        breakpoint = "auto",
        breakpoints = "auto",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "frame scaling")
    AddAliasesForUnit(aliases, scope, "group frame scaling")
    AddAliasesForUnit(aliases, scope, "scaling")
    RegisterGroupBoolean(scope, "frameScaleEnabled", "frameScaleEnabled", "Frame Scaling", false, "rebuild", aliases, {
        get = function(scopeKey)
            local mode = GroupDB(scopeKey).frameScaleMode
            return mode == "manual" or mode == "auto"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value then
                if conf.frameScaleMode ~= "manual" and conf.frameScaleMode ~= "auto" then conf.frameScaleMode = "manual" end
            else
                conf.frameScaleMode = "off"
            end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "manual scale", "manuelle skalierung")
    AddAliasesForUnit(aliases, scope, "scale")
    AddAliasesForUnit(aliases, scope, "frame scale")
    AddAliasesForUnit(aliases, scope, "scale percent")
    AddAliasesForUnit(aliases, scope, "frame scale percent")
    RegisterGroupNumber(scope, "frameScaleManual", "frameScaleManual", "Manual Frame Scale", 100, 50, 150, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 10")
    AddAliasesForUnit(aliases, scope, "1-10 player scale")
    AddAliasesForUnit(aliases, scope, "small group scale")
    AddAliasesForUnit(aliases, scope, "scale when 10 players")
    AddAliasesForUnit(aliases, scope, "scale for 10 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 10 players")
    RegisterGroupNumber(scope, "scaleAt10", "scaleAt10", "Scale 1-10 Players", 100, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 1 to 10 players. Example: set raid scale for 10 players to 95.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 20")
    AddAliasesForUnit(aliases, scope, "11-20 player scale")
    AddAliasesForUnit(aliases, scope, "scale when 20 players")
    AddAliasesForUnit(aliases, scope, "scale for 20 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 20 players")
    RegisterGroupNumber(scope, "scaleAt20", "scaleAt20", "Scale 11-20 Players", 85, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 11 to 20 players. Example: set raid scale for 20 players to 80.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 25")
    AddAliasesForUnit(aliases, scope, "21-25 player scale")
    AddAliasesForUnit(aliases, scope, "scale when 25 players")
    AddAliasesForUnit(aliases, scope, "scale for 25 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 25 players")
    RegisterGroupNumber(scope, "scaleAt25", "scaleAt25", "Scale 21-25 Players", 80, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 21 to 25 players. Example: set raid scale for 25 players to 75.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale over 25")
    AddAliasesForUnit(aliases, scope, "26 plus player scale")
    AddAliasesForUnit(aliases, scope, "large raid scale")
    AddAliasesForUnit(aliases, scope, "scale when over 25 players")
    AddAliasesForUnit(aliases, scope, "scale for more than 25 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 26 players")
    RegisterGroupNumber(scope, "scaleOver25", "scaleOver25", "Scale 26+ Players", 70, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 26 or more players. Example: set mythic raid scale over 25 players to 70.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "opacity affects")
    AddAliasesForUnit(aliases, scope, "transparency affects")
    AddAliasesForUnit(aliases, scope, "alpha target")
    -- Unified transparency: HP bar fill opacity, background opacity, and a toggle to
    -- keep text + portrait opaque while bars dim.
    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp bar opacity")
    AddAliasesForUnit(aliases, scope, "hp fill opacity")
    AddAliasesForUnit(aliases, scope, "health bar opacity")
    RegisterGroupNumber(scope, "hpBarAlpha", "hpBarAlpha", "HP Bar Opacity", 1, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "background opacity")
    AddAliasesForUnit(aliases, scope, "backdrop opacity")
    AddAliasesForUnit(aliases, scope, "background alpha")
    AddAliasesForUnit(aliases, scope, "hp track opacity")
    AddAliasesForUnit(aliases, scope, "health track opacity")
    AddAliasesForUnit(aliases, scope, "track opacity")
    AddAliasesForUnit(aliases, scope, "bar background opacity")
    RegisterGroupNumber(scope, "hpBgAlpha", "hpBgAlpha", "Background Opacity", 0.85, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "keep text visible")
    AddAliasesForUnit(aliases, scope, "keep text portrait visible")
    AddAliasesForUnit(aliases, scope, "keep text and portrait visible")
    AddAliasesForUnit(aliases, scope, "exclude text from opacity")
    AddAliasesForUnit(aliases, scope, "keep portrait visible")
    AddAliasesForUnit(aliases, scope, "keep text visible when faded")
    AddAliasesForUnit(aliases, scope, "keep names visible when faded")
    RegisterGroupBoolean(scope, "alphaExcludeTextPortrait", "alphaExcludeTextPortrait", "Keep Text & Portrait Visible", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group backdrop color")
    AddAliasesForUnit(aliases, scope, "group background color")
    AddAliasesForUnit(aliases, scope, "frame background color")
    AddAliasesForUnit(aliases, scope, "background color")
    AddAliasesForUnit(aliases, scope, "backdrop color")
    RegisterGroupColor(scope, "groupBackdropColor", "bg", "Backdrop Color", 0.10, 0.10, 0.10, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background")
    AddAliasesForUnit(aliases, scope, "dead member background")
    AddAliasesForUnit(aliases, scope, "dead offline background")
    AddAliasesForUnit(aliases, scope, "dead background tint")
    RegisterGroupBoolean(scope, "deadBgEnabled", "deadBgEnabled", "Dead Background", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background color")
    AddAliasesForUnit(aliases, scope, "dead member background color")
    AddAliasesForUnit(aliases, scope, "dead offline background color")
    AddAliasesForUnit(aliases, scope, "dead bg color")
    RegisterGroupColor(scope, "deadBgColor", "deadBg", "Dead Background Color", 0.60, 0.05, 0.05, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background opacity")
    AddAliasesForUnit(aliases, scope, "dead background alpha")
    AddAliasesForUnit(aliases, scope, "dead member background opacity")
    AddAliasesForUnit(aliases, scope, "dead offline background opacity")
    AddAliasesForUnit(aliases, scope, "dead bg opacity")
    RegisterGroupNumber(scope, "deadBgAlpha", "deadBgA", "Dead Background Opacity", 0.90, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "tint offline members")
    AddAliasesForUnit(aliases, scope, "also tint offline members")
    AddAliasesForUnit(aliases, scope, "dead background offline members")
    AddAliasesForUnit(aliases, scope, "dead offline tint")
    RegisterGroupBoolean(scope, "deadBgOffline", "deadBgOffline", "Tint Offline Members", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor to")
    AddAliasesForUnit(aliases, scope, "anchor target")
    AddAliasesForUnit(aliases, scope, "anchor frame")
    RegisterGroupEnum(scope, "anchorToFrame", "anchorToFrame", "Anchor To", "FREE", { "FREE", "player", "target", "targettarget", "focustarget", "focus" }, {
        free = "FREE",
        none = "FREE",
        clear = "FREE",
        ui = "FREE",
        uiparent = "FREE",
        player = "player",
        target = "target",
        targettarget = "targettarget",
        ["target of target"] = "targettarget",
        tot = "targettarget",
        focustarget = "focustarget",
        ["focus target"] = "focustarget",
        focus = "focus",
    }, "rebuild", aliases, {
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and (value and value ~= "" and value or "FREE") or "FREE"
        end,
        set = function(scopeKey, value)
            GroupDB(scopeKey).anchorToFrame = (value == "FREE") and nil or value
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "custom anchor frame")
    AddAliasesForUnit(aliases, scope, "custom anchor")
    AddAliasesForUnit(aliases, scope, "custom anchor name")
    RegisterGroupString(scope, "customAnchorFrame", "customAnchorFrame", "Custom Anchor Frame", "", "rebuild", aliases, {
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and "" or tostring(value or "")
        end,
        set = function(scopeKey, value)
            value = TrimString(value)
            local lower = value:lower()
            GroupDB(scopeKey).anchorToFrame = (value == "" or lower == "free" or lower == "clear" or lower == "none") and nil or value
        end,
        description = "Sets a custom frame name for the group-frame anchor target.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor point")
    AddAliasesForUnit(aliases, scope, "anchor position")
    RegisterGroupEnum(scope, "anchorPoint", "anchorPoint", "Anchor Point", "CENTER", { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOP",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        left = "LEFT",
        center = "CENTER",
        centre = "CENTER",
        middle = "CENTER",
        right = "RIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOM",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "bar color mode")
    AddAliasesForUnit(aliases, scope, "health bar color mode")
    AddAliasesForUnit(aliases, scope, "group bar style")
    AddAliasesForUnit(aliases, scope, "use class colors")
    AddAliasesForUnit(aliases, scope, "class colored bars")
    AddAliasesForUnit(aliases, scope, "colored by class")
    AddAliasesForUnit(aliases, scope, "use global colors")
    AddAliasesForUnit(aliases, scope, "use default colors")
    RegisterGroupEnum(scope, "groupBarMode", "gfBarMode", "Bar Color Mode", "GLOBAL", GROUP_BAR_MODE_VALUES, {
        global = "GLOBAL",
        ["global color"] = "GLOBAL",
        ["global colors"] = "GLOBAL",
        inherit = "GLOBAL",
        ["inherit color"] = "GLOBAL",
        ["inherit colors"] = "GLOBAL",
        default = "GLOBAL",
        ["default color"] = "GLOBAL",
        ["default colors"] = "GLOBAL",
        ["global style"] = "GLOBAL",
        class = "CLASS",
        classcolor = "CLASS",
        ["class color"] = "CLASS",
        ["class colors"] = "CLASS",
        ["class colored"] = "CLASS",
        ["colored by class"] = "CLASS",
        ["coloured by class"] = "CLASS",
        ["class colored bars"] = "CLASS",
        ["class color bars"] = "CLASS",
        dark = "dark",
        darkmode = "dark",
        ["dark mode"] = "dark",
        unified = "unified",
        unifiedcolor = "unified",
        ["unified color"] = "unified",
        gradient = "GRADIENT",
        healthgradient = "GRADIENT",
        ["health gradient"] = "GRADIENT",
        custom = "CUSTOM",
        manual = "CUSTOM",
    }, "visual", aliases, {
        exactAliases = GroupBarModeExactAliases(scope),
        get = function(scopeKey) return GroupDB(scopeKey).gfBarMode or "GLOBAL" end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.gfBarMode = value == "GLOBAL" and nil or value
            if value == "CLASS" or value == "GRADIENT" then conf.healthColorMode = value end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "foreground texture")
    AddAliasesForUnit(aliases, scope, "bar texture")
    AddAliasesForUnit(aliases, scope, "health bar texture")
    RegisterGroupTexture(scope, "barTexture", "barTexture", "Foreground Texture", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "background texture")
    AddAliasesForUnit(aliases, scope, "bar background texture")
    AddAliasesForUnit(aliases, scope, "health background texture")
    RegisterGroupTexture(scope, "barBackgroundTexture", "barBgTexture", "Background Texture", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health color mode")
    AddAliasesForUnit(aliases, scope, "health mode")
    RegisterGroupEnum(scope, "healthColorMode", "healthColorMode", "Health Color Mode", "CLASS", GROUP_HEALTH_MODE_VALUES, {
        class = "CLASS",
        classcolor = "CLASS",
        ["class color"] = "CLASS",
        gradient = "GRADIENT",
        healthgradient = "GRADIENT",
        ["health gradient"] = "GRADIENT",
        custom = "CUSTOM",
        manual = "CUSTOM",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health bar color")
    AddAliasesForUnit(aliases, scope, "health color")
    AddAliasesForUnit(aliases, scope, "bar color")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".healthBarColor",
        label = UNIT_LABELS[scope] .. " Health Bar Color",
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = "healthBarColor",
        type = "color",
        aliases = aliases,
        get = function() return GetGroupHealthBarColor(scope) end,
        set = function(value) SetGroupHealthBarColor(scope, value) end,
        sameValue = GroupColorSame,
        apply = function() ApplyGroup(scope, "visual") end,
        combatSafe = false,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "custom health color")
    AddAliasesForUnit(aliases, scope, "health custom color")
    AddAliasesForUnit(aliases, scope, "health bar custom color")
    RegisterGroupColor(scope, "healthCustomColor", "healthCustom", "Custom Health Color", 0.20, 0.80, 0.20, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dark health color")
    AddAliasesForUnit(aliases, scope, "dark bar color")
    AddAliasesForUnit(aliases, scope, "dark mode health color")
    RegisterGroupColor(scope, "darkBarColor", "gfDark", "Dark Bar Color", 0, 0, 0, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "unified health color")
    AddAliasesForUnit(aliases, scope, "unified bar color")
    AddAliasesForUnit(aliases, scope, "unified color")
    RegisterGroupColor(scope, "unifiedBarColor", "gfUnified", "Unified Bar Color", 0.10, 0.60, 0.90, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power smooth fill")
    AddAliasesForUnit(aliases, scope, "smooth power fill")
    RegisterGroupBoolean(scope, "powerSmoothFill", "powerSmoothFill", "Power Smooth Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show tank power")
    AddAliasesForUnit(aliases, scope, "tank power bar")
    AddAliasesForUnit(aliases, scope, "tank power bars")
    AddAliasesForUnit(aliases, scope, "tank mana")
    AddAliasesForUnit(aliases, scope, "tank mana bars")
    AddAliasesForUnit(aliases, scope, "power for tanks")
    RegisterGroupBoolean(scope, "powerShowTank", "powerShowTank", "Show Tank Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show healer power")
    AddAliasesForUnit(aliases, scope, "healer power bar")
    AddAliasesForUnit(aliases, scope, "healer power bars")
    AddAliasesForUnit(aliases, scope, "healer mana")
    AddAliasesForUnit(aliases, scope, "healer mana bars")
    AddAliasesForUnit(aliases, scope, "power for healers")
    RegisterGroupBoolean(scope, "powerShowHealer", "powerShowHealer", "Show Healer Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show dps power")
    AddAliasesForUnit(aliases, scope, "dps power bar")
    AddAliasesForUnit(aliases, scope, "dps power bars")
    AddAliasesForUnit(aliases, scope, "dps mana")
    AddAliasesForUnit(aliases, scope, "dps mana bars")
    AddAliasesForUnit(aliases, scope, "damage dealer power")
    AddAliasesForUnit(aliases, scope, "damage dealer mana")
    AddAliasesForUnit(aliases, scope, "power for dps")
    RegisterGroupBoolean(scope, "powerShowDamager", "powerShowDamager", "Show DPS Power", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide name on dead offline")
    AddAliasesForUnit(aliases, scope, "hide name when dead")
    AddAliasesForUnit(aliases, scope, "hide name when offline")
    RegisterGroupBoolean(scope, "hideNameOnDeadOffline", "hideNameOnDeadOffline", "Hide Name On Dead Or Offline", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name anchor")
    AddAliasesForUnit(aliases, scope, "name text anchor")
    RegisterGroupEnum(scope, "nameAnchor", "nameAnchor", "Name Anchor", "LEFT", GROUP_ANCHOR_VALUES, GROUP_ANCHOR_ALIASES, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name x")
    AddAliasesForUnit(aliases, scope, "name x offset")
    AddAliasesForUnit(aliases, scope, "name text x offset")
    RegisterGroupNumber(scope, "nameOffsetX", "nameOffsetX", "Name X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name y")
    AddAliasesForUnit(aliases, scope, "name y offset")
    AddAliasesForUnit(aliases, scope, "name text y offset")
    RegisterGroupNumber(scope, "nameOffsetY", "nameOffsetY", "Name Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name layer")
    AddAliasesForUnit(aliases, scope, "name text layer")
    RegisterGroupNumber(scope, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5, 1, 15, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp left text")
    AddAliasesForUnit(aliases, scope, "health left text")
    AddAliasesForUnit(aliases, scope, "left hp text")
    RegisterGroupTextMode(scope, "healthTextLeft", "textLeft", "Left HP Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp right text")
    AddAliasesForUnit(aliases, scope, "health right text")
    AddAliasesForUnit(aliases, scope, "right hp text")
    RegisterGroupTextMode(scope, "healthTextRight", "textRight", "Right HP Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text delimiter")
    AddAliasesForUnit(aliases, scope, "health text delimiter")
    AddAliasesForUnit(aliases, scope, "health delimiter")
    RegisterGroupDelimiter(scope, "healthTextDelimiter", "textDelimiter", "HP Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse hp text")
    AddAliasesForUnit(aliases, scope, "reverse health text")
    AddAliasesForUnit(aliases, scope, "hp text reverse order")
    RegisterGroupBoolean(scope, "healthTextReverse", "hpTextReverse", "Reverse HP Text", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text x")
    AddAliasesForUnit(aliases, scope, "hp text x offset")
    AddAliasesForUnit(aliases, scope, "health text x offset")
    RegisterGroupNumber(scope, "healthTextOffsetX", "hpOffsetX", "HP Text X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text y")
    AddAliasesForUnit(aliases, scope, "hp text y offset")
    AddAliasesForUnit(aliases, scope, "health text y offset")
    RegisterGroupNumber(scope, "healthTextOffsetY", "hpOffsetY", "HP Text Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text layer")
    AddAliasesForUnit(aliases, scope, "health text layer")
    RegisterGroupNumber(scope, "healthTextLayer", "textLayer", "HP Text Layer", 5, 1, 15, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power left text")
    AddAliasesForUnit(aliases, scope, "left power text")
    RegisterGroupTextMode(scope, "powerTextLeft", "powerTextLeft", "Left Power Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power center text")
    AddAliasesForUnit(aliases, scope, "power middle text")
    AddAliasesForUnit(aliases, scope, "center power text")
    RegisterGroupTextMode(scope, "powerTextCenter", "powerTextCenter", "Center Power Text", "PERCENT", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power right text")
    AddAliasesForUnit(aliases, scope, "right power text")
    RegisterGroupTextMode(scope, "powerTextRight", "powerTextRight", "Right Power Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text delimiter")
    AddAliasesForUnit(aliases, scope, "power delimiter")
    RegisterGroupDelimiter(scope, "powerTextDelimiter", "powerTextDelimiter", "Power Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text x")
    AddAliasesForUnit(aliases, scope, "power text x offset")
    RegisterGroupNumber(scope, "powerTextOffsetX", "powerOffsetX", "Power Text X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text y")
    AddAliasesForUnit(aliases, scope, "power text y offset")
    RegisterGroupNumber(scope, "powerTextOffsetY", "powerOffsetY", "Power Text Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text layer")
    RegisterGroupNumber(scope, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2, 1, 15, 1, "font", aliases)

    for _, slotInfo in ipairs({
        { label = "HP Left Text", prefix = "hpTextLeft", words = { "hp left slot", "health left slot", "left hp slot" } },
        { label = "HP Center Text", prefix = "hpTextCenter", words = { "hp center slot", "health center slot", "center hp slot" } },
        { label = "HP Right Text", prefix = "hpTextRight", words = { "hp right slot", "health right slot", "right hp slot" } },
        { label = "Power Left Text", prefix = "powerTextLeft", words = { "power left slot", "left power slot" } },
        { label = "Power Center Text", prefix = "powerTextCenter", words = { "power center slot", "center power slot" } },
        { label = "Power Right Text", prefix = "powerTextRight", words = { "power right slot", "right power slot" } },
    }) do
        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetX", slotInfo.prefix .. "OffsetX", slotInfo.label .. " Slot X Offset", 0, -100, 100, 1, "font", aliases)

        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetY", slotInfo.prefix .. "OffsetY", slotInfo.label .. " Slot Y Offset", 0, -100, 100, 1, "font", aliases)
    end

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay")
    AddAliasesForUnit(aliases, scope, "debuff overlay")
    RegisterGroupBoolean(scope, "dispelOverlay", "dispelOverlayEnabled", "Dispel Overlay", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay detects")
    AddAliasesForUnit(aliases, scope, "dispel overlay trigger")
    AddAliasesForUnit(aliases, scope, "debuff overlay trigger")
    RegisterGroupEnum(scope, "dispelOverlayTrigger", "dispelOverlayTrigger", "Dispel Overlay Detects", "BORDER", GROUP_DISPEL_TRIGGER_VALUES, {
        border = "BORDER",
        inherit = "BORDER",
        same = "BORDER",
        ["dispel border"] = "BORDER",
        byme = "BY_ME",
        ["by me"] = "BY_ME",
        dispellable = "BY_ME",
        ["dispellable by me"] = "BY_ME",
        type = "DISPEL_TYPE",
        dispeltype = "DISPEL_TYPE",
        ["dispel type"] = "DISPEL_TYPE",
        any = "ANY_DEBUFF",
        debuff = "ANY_DEBUFF",
        ["any debuff"] = "ANY_DEBUFF",
        ["all debuffs"] = "ANY_DEBUFF",
    }, "visual", aliases, {
        get = function(scopeKey) return NormalizeGroupDispelTrigger(GroupDB(scopeKey).dispelOverlayTrigger) end,
        set = function(scopeKey, value) GroupDB(scopeKey).dispelOverlayTrigger = NormalizeGroupDispelTrigger(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay style")
    AddAliasesForUnit(aliases, scope, "debuff overlay style")
    RegisterGroupEnum(scope, "dispelOverlayStyle", "dispelOverlayStyle", "Dispel Overlay Style", "FULL", GROUP_DISPEL_STYLE_VALUES, {
        full = "FULL",
        ["full frame"] = "FULL",
        bottom = "BOTTOM",
        top = "TOP",
        left = "LEFT",
        right = "RIGHT",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay current health")
    AddAliasesForUnit(aliases, scope, "dispel overlay current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay current health only")
    RegisterGroupBoolean(scope, "dispelOverlayOnHealth", "dispelOverlayOnHealth", "Dispel Overlay On Current Health", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay opacity")
    AddAliasesForUnit(aliases, scope, "dispel overlay alpha")
    AddAliasesForUnit(aliases, scope, "debuff overlay opacity")
    RegisterGroupNumber(scope, "dispelOverlayAlpha", "dispelOverlayAlpha", "Dispel Overlay Opacity", 0.35, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe")
    AddAliasesForUnit(aliases, scope, "debuff stripe enabled")
    RegisterGroupBoolean(scope, "debuffStripe", "debuffStripeEnabled", "Debuff Stripe", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe edge")
    AddAliasesForUnit(aliases, scope, "debuff stripe position")
    RegisterGroupEnum(scope, "debuffStripeEdge", "debuffStripeEdge", "Debuff Stripe Edge", "BOTTOM", GROUP_STRIPE_EDGE_VALUES, {
        bottom = "BOTTOM",
        lower = "BOTTOM",
        top = "TOP",
        upper = "TOP",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe height")
    AddAliasesForUnit(aliases, scope, "debuff stripe size")
    RegisterGroupNumber(scope, "debuffStripeHeight", "debuffStripeHeight", "Debuff Stripe Height", 3, 1, 8, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe opacity")
    AddAliasesForUnit(aliases, scope, "debuff stripe alpha")
    RegisterGroupNumber(scope, "debuffStripeAlpha", "debuffStripeAlpha", "Debuff Stripe Opacity", 0.60, 0.10, 1, 0.05, "visual", aliases, { percent = true })
    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe color")
    AddAliasesForUnit(aliases, scope, "stripe color")
    RegisterGroupColor(scope, "debuffStripeColor", "debuffStripeColor", "Debuff Stripe Color", 0.80, 0.20, 0.20, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade affects")
    AddAliasesForUnit(aliases, scope, "range fade layer")
    AddAliasesForUnit(aliases, scope, "range fade mode")
    RegisterGroupEnum(scope, "rangeFadeLayerMode", "rangeFadeLayerMode", "Range Fade Affects", "frame", GROUP_RANGE_LAYER_VALUES, {
        frame = "frame",
        whole = "frame",
        ["whole frame"] = "frame",
        health = "health",
        hp = "health",
        ["hp only"] = "health",
        ["health only"] = "health",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "offline alpha")
    AddAliasesForUnit(aliases, scope, "offline opacity")
    AddAliasesForUnit(aliases, scope, "offline member opacity")
    AddAliasesForUnit(aliases, scope, "offline transparency")
    AddAliasesForUnit(aliases, scope, "fade offline members")
    AddAliasesForUnit(aliases, scope, "offline member fade")
    RegisterGroupNumber(scope, "offlineAlpha", "offlineAlpha", "Offline Opacity", 0.5, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number")
    AddAliasesForUnit(aliases, scope, "group index")
    AddAliasesForUnit(aliases, scope, "group number label")
    RegisterGroupBoolean(scope, "groupNumber", "showGroupNumber", "Group Number", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number size")
    AddAliasesForUnit(aliases, scope, "group index size")
    RegisterGroupNumber(scope, "groupNumberSize", "groupNumberSize", "Group Number Size", 10, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number anchor")
    AddAliasesForUnit(aliases, scope, "group index anchor")
    RegisterGroupEnum(scope, "groupNumberAnchor", "groupNumberAnchor", "Group Number Anchor", "BOTTOMRIGHT", { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOPLEFT",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOMRIGHT",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number x")
    AddAliasesForUnit(aliases, scope, "group number x offset")
    AddAliasesForUnit(aliases, scope, "group index x offset")
    RegisterGroupNumber(scope, "groupNumberX", "groupNumberX", "Group Number X Offset", -2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number y")
    AddAliasesForUnit(aliases, scope, "group number y offset")
    AddAliasesForUnit(aliases, scope, "group index y offset")
    RegisterGroupNumber(scope, "groupNumberY", "groupNumberY", "Group Number Y Offset", 2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hover highlight thickness")
    AddAliasesForUnit(aliases, scope, "mouseover highlight thickness")
    AddAliasesForUnit(aliases, scope, "hover border thickness")
    RegisterGroupNumber(scope, "hoverHighlightSize", "hlHoverSize", "Hover Highlight Thickness", 1, 1, 6, 1, "visual", aliases, {
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.hlHoverSize = ClampNumber(value, 1, 6, 1)
            conf.hlOverride = true
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "target highlight")
    AddAliasesForUnit(aliases, scope, "target border")
    AddAliasesForUnit(aliases, scope, "selected target border")
    RegisterGroupBoolean(scope, "targetHighlight", "targetIndicator", "Target Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight")
    AddAliasesForUnit(aliases, scope, "focus border")
    AddAliasesForUnit(aliases, scope, "focus glow")
    RegisterGroupBoolean(scope, "focusHighlight", "hlFocusEnabled", "Focus Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight thickness")
    AddAliasesForUnit(aliases, scope, "focus border thickness")
    AddAliasesForUnit(aliases, scope, "focus glow thickness")
    RegisterGroupNumber(scope, "focusHighlightSize", "hlFocusSize", "Focus Highlight Thickness", 2, 1, 6, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight color")
    AddAliasesForUnit(aliases, scope, "focus border color")
    AddAliasesForUnit(aliases, scope, "focus glow color")
    RegisterGroupColor(scope, "focusHighlightColor", "hlFocusColor", "Focus Highlight Color", 0.50, 0.50, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border")
    AddAliasesForUnit(aliases, scope, "full group border")
    AddAliasesForUnit(aliases, scope, "group frame border")
    RegisterGroupBoolean(scope, "groupBorder", "groupBorderEnabled", "Group Border", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border thickness")
    AddAliasesForUnit(aliases, scope, "group frame border thickness")
    RegisterGroupNumber(scope, "groupBorderSize", "groupBorderSize", "Group Border Thickness", 1, 1, 12, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border padding")
    AddAliasesForUnit(aliases, scope, "group frame border padding")
    RegisterGroupNumber(scope, "groupBorderPadding", "groupBorderPadding", "Group Border Padding", 2, 0, 40, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border color")
    AddAliasesForUnit(aliases, scope, "group frame border color")
    RegisterGroupColor(scope, "groupBorderColor", "groupBorder", "Group Border Color", 0.38, 0.68, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "status icon style")
    AddAliasesForUnit(aliases, scope, "status icons style")
    AddAliasesForUnit(aliases, scope, "group icon style")
    RegisterGroupEnum(scope, "statusIconStyle", "iconStyle", "Status Icon Style", "BLIZZARD", GROUP_STATUS_ICON_STYLE_VALUES, GROUP_STATUS_ICON_STYLE_ALIASES, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "midnight status icons")
    AddAliasesForUnit(aliases, scope, "midnight icon style")
    AddAliasesForUnit(aliases, scope, "use midnight icons")
    RegisterGroupBoolean(scope, "useMidnightIcons", "useMidnightIcons", "Use Midnight Status Icons", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon tanks")
    AddAliasesForUnit(aliases, scope, "show role icon for tanks")
    AddAliasesForUnit(aliases, scope, "tank role icon")
    RegisterGroupBoolean(scope, "roleIconShowTank", "roleIconShowTank", "Role Icon For Tanks", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon healers")
    AddAliasesForUnit(aliases, scope, "show role icon for healers")
    AddAliasesForUnit(aliases, scope, "healer role icon")
    RegisterGroupBoolean(scope, "roleIconShowHealer", "roleIconShowHealer", "Role Icon For Healers", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon dps")
    AddAliasesForUnit(aliases, scope, "show role icon for dps")
    AddAliasesForUnit(aliases, scope, "dps role icon")
    RegisterGroupBoolean(scope, "roleIconShowDPS", "roleIconShowDPS", "Role Icon For DPS", true, "visual", aliases)

    for _, spec in ipairs(GROUP_STATUS_ICON_SPECS) do
        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec)
        AddGroupStatusIconAliases(aliases, scope, spec, "enabled")
        RegisterGroupBoolean(scope, "statusIcon" .. spec.value .. "Enabled", spec.enabled, spec.label, false, "visual", aliases, { description = spec.description })

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "size")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 6, 40, 1, "visual", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "anchor")
        AddGroupStatusIconAliases(aliases, scope, spec, "position")
        RegisterGroupEnum(scope, "statusIcon" .. spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, GROUP_STATUS_ANCHOR_VALUES, GROUP_STATUS_ANCHOR_ALIASES, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "x")
        AddGroupStatusIconAliases(aliases, scope, spec, "x offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "X", spec.x, spec.label .. " X Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "y")
        AddGroupStatusIconAliases(aliases, scope, spec, "y offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Y", spec.y, spec.label .. " Y Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "layer")
        AddGroupStatusIconAliases(aliases, scope, spec, "draw layer")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 0, 30, 1, "visual", aliases)

        if spec.iconStyle then
            aliases = {}
            AddGroupStatusIconAliases(aliases, scope, spec, "icon pack")
            AddGroupStatusIconAliases(aliases, scope, spec, "style")
            RegisterGroupEnum(scope, "statusIcon" .. spec.value .. "Style", spec.iconStyle, spec.label .. " Icon Pack", "DEFAULT", GROUP_STATUS_ICON_PACK_VALUES, GROUP_STATUS_ICON_PACK_ALIASES, "visual", aliases)
        end
    end

end
end
