-- Assistant GroupFrames basic text setting registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesText.lua; callers use A.GroupFramesRegistry.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterTextBasics(ctx, scope, defaults)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end
    defaults = type(defaults) == "table" and defaults or {}

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local ApplyGroup = ctx.ApplyGroup
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local GroupNameShorteningMax = ctx.GroupNameShorteningMax
    local GroupNameShorteningEnabled = ctx.GroupNameShorteningEnabled
    local GroupNameShorteningSide = ctx.GroupNameShorteningSide
    local GroupNameShorteningNoEllipsis = ctx.GroupNameShorteningNoEllipsis
    local SetGroupFontOverrideValue = ctx.SetGroupFontOverrideValue

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(ApplyGroup) ~= "function" or type(ClampNumber) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(SetGroupFontOverrideValue) ~= "function" then return end
    local scopeLabel = tostring(UNIT_LABELS[scope] or scope):lower()

    local aliases = {}
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
    AddAliasesForUnit(aliases, scope, "power number")
    AddAliasesForUnit(aliases, scope, "power numbers")
    AddAliasesForUnit(aliases, scope, "mana number")
    AddAliasesForUnit(aliases, scope, "mana numbers")
    AddAliasesForUnit(aliases, scope, "resource text")
    AddAliasesForUnit(aliases, scope, "resource number")
    AddAliasesForUnit(aliases, scope, "resource numbers")
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".showPowerText",
        label = UNIT_LABELS[scope] .. " Power Text",
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = "powerText",
        type = "boolean",
        aliases = aliases,
        exactAliases = {
            scope .. " power text",
            scopeLabel .. " power text",
            scope .. " mana text",
            scopeLabel .. " mana text",
            scope .. " power numbers",
            scopeLabel .. " power numbers",
            scope .. " mana numbers",
            scopeLabel .. " mana numbers",
            scope .. " resource text",
            scopeLabel .. " resource text",
            scope .. " resource numbers",
            scopeLabel .. " resource numbers",
        },
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
        description = "Controls the saved group-frame power/resource text. Power bars are a separate setting.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name font size", "name schriftgroesse")
    AddAliasesForUnit(aliases, scope, "name size", "name groesse")
    AddAliasesForUnit(aliases, scope, "names font size")
    AddAliasesForUnit(aliases, scope, "names size")
    RegisterGroupNumber(scope, "nameFontSize", "nameFontSize", "Name Font Size", defaults.nameFontSize or 10, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp font size", "leben schriftgroesse")
    AddAliasesForUnit(aliases, scope, "health font size", "gesundheit schriftgroesse")
    AddAliasesForUnit(aliases, scope, "hp text size")
    AddAliasesForUnit(aliases, scope, "health text size")
    RegisterGroupNumber(scope, "hpFontSize", "hpFontSize", "HP Font Size", defaults.hpFontSize or 9, 6, 24, 1, "font", aliases)

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
        page = "opt_fonts",
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
        page = "opt_fonts",
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
        page = "opt_fonts",
        get = GroupNameShorteningSide,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameClipSide", value == "LEFT" and "LEFT" or "RIGHT")
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "no ellipsis")
    AddAliasesForUnit(aliases, scope, "name no ellipsis")
    AddAliasesForUnit(aliases, scope, "truncate without dots")
    AddAliasesForUnit(aliases, scope, "shortened name dots")
    AddAliasesForUnit(aliases, scope, "name shortening dots")
    AddAliasesForUnit(aliases, scope, "name dots")
    AddAliasesForUnit(aliases, scope, "name ellipsis")
    AddAliasesForUnit(aliases, scope, "trailing dots on shortened names")
    RegisterGroupBoolean(scope, "nameNoEllipsis", "nameNoEllipsis", "Name No Ellipsis", false, "font", aliases, {
        page = "opt_fonts",
        get = GroupNameShorteningNoEllipsis,
        set = function(groupScope, value)
            SetGroupFontOverrideValue(groupScope, "nameNoEllipsis", value and true or false)
        end,
        description = "Controls only the trailing ellipsis on shortened group names. The name visibility and shortening length are separate controls.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health text center", "leben text mitte")
    AddAliasesForUnit(aliases, scope, "hp text center", "hp text mitte")
    AddAliasesForUnit(aliases, scope, "center text", "text mitte")
    AddAliasesForUnit(aliases, scope, "center hp text", "hp text mitte")
    RegisterGroupEnum(scope, "healthTextCenter", "textCenter", "Center HP Text", defaults.textCenter or "NONE", { "NONE", "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT", "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX" }, {
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
end
