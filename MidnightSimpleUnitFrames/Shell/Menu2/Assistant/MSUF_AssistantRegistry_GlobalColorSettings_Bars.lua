-- Bar, outline, and dispel global color assistant settings.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main registry passes shared color helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterBarColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local ColorSetting = ctx.ColorSetting
    local ApiRGB = ctx.ApiRGB
    local ApiSetRGB = ctx.ApiSetRGB
    local GeneralDB = ctx.GeneralDB
    local GeneralRGB = ctx.GeneralRGB
    local SetGeneralRGB = ctx.SetGeneralRGB
    local GeneralRGBAlias = ctx.GeneralRGBAlias
    local SetGeneralRGBAlias = ctx.SetGeneralRGBAlias
    local ColorComponents = ctx.ColorComponents
    local ColorSame = ctx.ColorSame
    local Clamp01 = ctx.Clamp01
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local ApplyColors = ctx.ApplyColors
    local ApplyBarOutline = ctx.ApplyBarOutline
    local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER or {}
    local NormalizeGlobalScope = ctx.NormalizeGlobalScope
    local GlobalScopeLabel = ctx.GlobalScopeLabel
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local COLOR_DISPEL_TYPE_ROWS = ctx.COLOR_DISPEL_TYPE_ROWS or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(ColorSetting) ~= "function" or type(ApiRGB) ~= "function" or type(ApiSetRGB) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(GeneralRGB) ~= "function" or type(SetGeneralRGB) ~= "function" then return end
    if type(GeneralRGBAlias) ~= "function" or type(SetGeneralRGBAlias) ~= "function" then return end
    if type(ColorComponents) ~= "function" or type(ColorSame) ~= "function" or type(Clamp01) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralEnum) ~= "function" then return end
    if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeLabel) ~= "function" then return end
    if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" or type(GlobalScopeAliases) ~= "function" then return end

    ColorSetting("general.absorbBarColor", "Absorb Bar Color", {
        "absorb bar color", "absorb color", "absorb overlay color",
    }, function()
        return ApiRGB("GetAbsorbOverlayColor", 1, 1, 1, function() return GeneralRGB("absorbBarColor", 1, 1, 1) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetAbsorbOverlayColor", r, g, b, 0.45) then SetGeneralRGB("absorbBarColor", r, g, b) end
    end, { category = "Colors / Bar Colors", attribute = "absorbColor", apply = ApplyColors })
    ColorSetting("general.healAbsorbBarColor", "Heal-Absorb Bar Color", {
        "heal absorb bar color", "heal absorb color", "heal-absorb color",
    }, function()
        return ApiRGB("GetHealAbsorbOverlayColor", 0.7, 0, 0, function() return GeneralRGB("healAbsorbBarColor", 0.7, 0, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetHealAbsorbOverlayColor", r, g, b, 0.45) then SetGeneralRGB("healAbsorbBarColor", r, g, b) end
    end, { category = "Colors / Bar Colors", attribute = "healAbsorbColor", defaultR = 0.7, apply = ApplyColors })
    ColorSetting("general.powerBarBgColor", "Power Bar Background Color", {
        "power bar background color", "power background color", "mana bar background color",
    }, function()
        return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0, function() return GeneralRGB("powerBarBgColor", 0, 0, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetPowerBarBackgroundColor", r, g, b) then SetGeneralRGB("powerBarBgColor", r, g, b) end
    end, { category = "Colors / Bar Colors", attribute = "powerBackgroundColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })
    ColorSetting("general.aggroBorderColor", "Aggro Border Color", {
        "aggro border color", "threat border color", "aggro outline color",
    }, function()
        return ApiRGB("GetAggroBorderColor", 1, 0.5, 0, function() return GeneralRGBAlias("hlAggroColor", "aggroBorderColor", 1, 0.5, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetAggroBorderColor", r, g, b) then SetGeneralRGBAlias("hlAggroColor", "aggroBorderColor", r, g, b) end
    end, { category = "Colors / Bar Colors", attribute = "aggroBorderColor", defaultR = 1, defaultG = 0.5, defaultB = 0, apply = ApplyColors })
    ColorSetting("general.purgeBorderColor", "Purge Border Color", {
        "purge border color", "purgeable border color", "purge outline color",
    }, function()
        return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0)
    end, function(r, g, b)
        SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, b)
    end, { category = "Colors / Bar Colors", attribute = "purgeBorderColor", defaultR = 1, defaultG = 0.85, defaultB = 0, apply = ApplyColors })
    ColorSetting("general.barOutlineColor", "Bar Outline Color", {
        "bar outline color", "frame outline color", "bar border color", "bars border color", "border outline color", "outline border color",
    }, function()
        return ApiRGB("GetBarOutlineColor", 0, 0, 0, function() return GeneralRGB("barOutlineColor", 0, 0, 0) end)
    end, function(r, g, b)
        local gdb = GeneralDB()
        gdb.barOutlineColorMode = nil
        gdb.barOutlineColorA = 1
        if not ApiSetRGB("SetBarOutlineColor", r, g, b) then SetGeneralRGB("barOutlineColor", r, g, b) end
    end, { category = "Colors / Bar Colors", attribute = "barOutlineColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })

    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        Registry:RegisterSetting({
            key = "barScope." .. NormalizeGlobalScope(scope) .. ".barOutlineColor",
            label = GlobalScopeLabel(scope) .. " Bar Outline Color",
            category = "Global / Bars / Scoped",
            unit = NormalizeGlobalScope(scope),
            frameType = "globalBars",
            attribute = "barOutlineColor",
            type = "color",
            aliases = GlobalScopeAliases(scope, { "bar outline color", "frame outline color", "bar border color", "bars border color", "border outline color", "outline border color", "border color", "outline color" }),
            get = function()
                return {
                    r = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorR", 0)),
                    g = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorG", 0)),
                    b = Clamp01(GlobalScopeRead(scope, "hlOverride", GeneralDB(), "barOutlineColorB", 0)),
                }
            end,
            set = function(value)
                local r, g, b = ColorComponents(value, 0, 0, 0)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorR", r)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorG", g)
                GlobalScopeWrite(scope, "hlOverride", GeneralDB(), "barOutlineColorB", b)
            end,
            sameValue = ColorSame,
            apply = function() ApplyBarOutline("MSUF_ASSISTANT_SCOPED_BAR_OUTLINE_COLOR") end,
            combatSafe = false,
        })
    end

    RegisterGeneralBoolean("powerBarBgMatchBarColor", "powerBackgroundMatchesHP", "Power Background Matches HP", false, {
        "power background matches hp", "power bar background matches hp", "power background follows hp",
    }, { category = "Colors / Bar Colors", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_POWER_BG_MATCH_HP" })

    RegisterGeneralEnum("hlDispelColorMode", "dispelColorMode", "Dispel Color Mode", "SINGLE", { "SINGLE", "TYPE" }, {
        "dispel color mode", "dispel colors mode", "debuff type color mode",
    }, {
        category = "Colors / Dispel",
        frameType = "colors",
        apply = ApplyColors,
        reason = "MSUF_ASSISTANT_DISPEL_COLOR_MODE",
        valueAliases = { single = "SINGLE", one = "SINGLE", type = "TYPE", types = "TYPE", pertype = "TYPE", debufftype = "TYPE" },
    })
    ColorSetting("general.hlDispelColor", "Dispel Color", {
        "dispel color", "dispel border color", "all dispel color", "single dispel color",
    }, function()
        return GeneralRGBAlias("hlDispelColor", "dispelBorderColor", 0.25, 0.75, 1)
    end, function(r, g, b)
        SetGeneralRGBAlias("hlDispelColor", "dispelBorderColor", r, g, b)
    end, { category = "Colors / Dispel", attribute = "dispelColor", defaultR = 0.25, defaultG = 0.75, defaultB = 1, apply = ApplyColors })

    for _, row in ipairs(COLOR_DISPEL_TYPE_ROWS) do
        ColorSetting("general.dispelType" .. row.key, row.label, row.aliases, function()
            return GeneralRGB("dispelType" .. row.key, row.dr, row.dg, row.db)
        end, function(r, g, b)
            SetGeneralRGB("dispelType" .. row.key, r, g, b)
        end, { category = "Colors / Dispel", attribute = "dispelTypeColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
    end
end
