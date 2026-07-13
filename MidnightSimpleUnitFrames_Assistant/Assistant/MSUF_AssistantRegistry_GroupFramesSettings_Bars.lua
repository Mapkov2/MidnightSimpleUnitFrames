-- Group frame bar, health color, texture, and power assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; the main loop passes shared group helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterBarAndPowerSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupColor = ctx.RegisterGroupColor
    local RegisterGroupTexture = ctx.RegisterGroupTexture
    local RegisterPowerRoleSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterPowerRoleSettings
    local GroupBarModeExactAliases = ctx.GroupBarModeExactAliases
    local GroupColorSame = ctx.GroupColorSame
    local GetGroupHealthBarColor = ctx.GetGroupHealthBarColor
    local SetGroupHealthBarColor = ctx.SetGroupHealthBarColor
    local GROUP_BAR_MODE_VALUES = ctx.GROUP_BAR_MODE_VALUES or {}
    local GROUP_HEALTH_MODE_VALUES = ctx.GROUP_HEALTH_MODE_VALUES or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(ApplyGroup) ~= "function" or type(RegisterGroupBoolean) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end
    if type(RegisterGroupTexture) ~= "function" or type(GroupBarModeExactAliases) ~= "function" then return end
    if type(GetGroupHealthBarColor) ~= "function" or type(SetGroupHealthBarColor) ~= "function" then return end

    local aliases = {}
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
    RegisterGroupTexture(scope, "barBackgroundTexture", "barBackgroundTexture", "Background Texture", aliases)

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

    if type(RegisterPowerRoleSettings) == "function" then
        RegisterPowerRoleSettings(ctx, scope)
    end
end
