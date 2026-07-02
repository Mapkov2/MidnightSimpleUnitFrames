-- Base global color assistant settings.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterBaseColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local ColorSetting = ctx.ColorSetting
    local ColorAPI = ctx.ColorAPI
    local GeneralDB = ctx.GeneralDB
    local GeneralRGB = ctx.GeneralRGB
    local SetGeneralRGB = ctx.SetGeneralRGB
    local ApiRGB = ctx.ApiRGB
    local ApiSetRGB = ctx.ApiSetRGB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local ApplyColors = ctx.ApplyColors
    local COLOR_CLASS_TOKENS = ctx.COLOR_CLASS_TOKENS or {}
    local COLOR_CLASS_LABELS = ctx.COLOR_CLASS_LABELS or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(ColorSetting) ~= "function" or type(ColorAPI) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(GeneralRGB) ~= "function" or type(SetGeneralRGB) ~= "function" then return end
    if type(ApiRGB) ~= "function" or type(ApiSetRGB) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end

    ColorSetting("general.customFontColor", "Global Font Color", {
        "custom font color", "main font color", "global custom font color",
    }, function()
        return ApiRGB("GetGlobalFontColor", 1, 1, 1, function() return GeneralRGB("fontColorCustom", 1, 1, 1) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetGlobalFontColor", r, g, b) then
            local gen = GeneralDB()
            gen.useCustomFontColor = true
            gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r, g, b
        end
    end, { category = "Colors / Global Font", attribute = "customFontColor", apply = ApplyColors })

    for i = 1, #COLOR_CLASS_TOKENS do
        local token = COLOR_CLASS_TOKENS[i]
        local label = COLOR_CLASS_LABELS[token] or token
        local lower = label:lower()
        ColorSetting("classColors." .. token, label .. " Class Bar Color", {
            lower .. " class color", lower .. " class bar color", lower .. " bar color", lower .. " color",
        }, function()
            local fn = ColorAPI().GetClassColor
            if type(fn) == "function" then return fn(token) end
            local db = GeneralDB()
            if type(db.classColors) == "table" then
                local color = db.classColors[token]
                if type(color) == "table" then return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1 end
            end
            local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
            if rc then return rc.r, rc.g, rc.b end
            return 1, 1, 1
        end, function(r, g, b)
            local fn = ColorAPI().SetClassColor
            if type(fn) == "function" then
                fn(token, r, g, b)
            else
                local db = GeneralDB()
                db.classColors = type(db.classColors) == "table" and db.classColors or {}
                db.classColors[token] = { r = r, g = g, b = b }
            end
        end, { category = "Colors / Class Bar", attribute = "classColor", apply = ApplyColors })
    end

    ColorSetting("general.classBarBgColor", "Bar Background Tint", {
        "bar background tint", "bar tint", "class bar background color", "bar background color",
    }, function()
        return ApiRGB("GetClassBarBgColor", 0, 0, 0, function() return GeneralRGB("classBarBg", 0, 0, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetClassBarBgColor", r, g, b) then SetGeneralRGB("classBarBg", r, g, b) end
    end, { category = "Colors / Bar Background", attribute = "barBackgroundTint", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyColors })

    Registry:RegisterSetting({
        key = "general.barBgMatchHPColor",
        label = "Background Follows HP Color",
        category = "Colors / Bar Background",
        unit = "global",
        frameType = "colors",
        attribute = "barBackgroundFollowsHP",
        type = "boolean",
        aliases = { "background follows hp color", "bar background follows hp", "background matches hp" },
        get = function()
            local fn = ColorAPI().GetBarBgMatchHP
            if type(fn) == "function" then return fn() == true end
            return GeneralDB().barBgMatchHPColor == true
        end,
        set = function(value)
            local fn = ColorAPI().SetBarBgMatchHP
            if type(fn) == "function" then
                fn(value and true or false)
            else
                local g = GeneralDB()
                g.barBgMatchHPColor = value and true or false
                if value then g.barBgClassColor = false end
            end
        end,
        apply = ApplyColors,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.barBgClassColor",
        label = "Health Background Follows Class Color",
        category = "Colors / Bar Background",
        unit = "global",
        frameType = "colors",
        attribute = "barBackgroundFollowsClass",
        type = "boolean",
        aliases = { "health background follows class color", "bar background class color", "background follows class color" },
        get = function()
            local fn = ColorAPI().GetBarBgClassColor
            if type(fn) == "function" then return fn() == true end
            return GeneralDB().barBgClassColor == true
        end,
        set = function(value)
            local fn = ColorAPI().SetBarBgClassColor
            if type(fn) == "function" then
                fn(value and true or false)
            else
                local g = GeneralDB()
                g.barBgClassColor = value and true or false
                if value then g.barBgMatchHPColor = false end
            end
        end,
        apply = ApplyColors,
        combatSafe = false,
    })

    RegisterGeneralBoolean("darkBgCustomColor", "darkModeCustomBackgroundColor", "Custom Color In Dark Mode", false, {
        "custom color in dark mode", "dark mode custom background color", "dark mode custom color",
    }, { category = "Colors / Bar Background", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_DARK_MODE_CUSTOM_COLOR" })

    ColorSetting("general.unifiedBarColor", "Unified Bar Color", {
        "unified bar color", "unified color", "all frames color",
    }, function()
        return GeneralRGB("unifiedBar", 0.10, 0.60, 0.90)
    end, function(r, g, b)
        SetGeneralRGB("unifiedBar", r, g, b)
    end, { category = "Colors / Unit Frame Global Coloring", attribute = "unifiedBarColor", defaultR = 0.10, defaultG = 0.60, defaultB = 0.90, apply = ApplyColors })

    RegisterGeneralNumberSetting("darkBarGray", "darkModeBarColor", "Dark Mode Bar Color", 0.07, 0, 1, {
        "dark mode bar color", "dark bar color", "dark mode brightness", "dark bar brightness",
    }, { category = "Colors / Unit Frame Global Coloring", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_DARK_BAR_GRAY", step = 0.01, percent = true })

    RegisterGeneralBoolean("enableHealthGradient", "healthColorGradient", "Health Color Gradient", true, {
        "health color gradient", "color health by gradient", "unitframe health gradient",
    }, { category = "Colors / Unit Frame Global Coloring", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_HEALTH_COLOR_GRADIENT" })

    ColorSetting("general.healthGradientLow", "Health Gradient Low Color", {
        "health gradient low", "health gradient low color", "low health gradient color",
        "low health color", "low hp gradient color", "low hp color",
    }, function()
        return GeneralRGB("healthGradientLow", 1, 0, 0)
    end, function(r, g, b)
        SetGeneralRGB("healthGradientLow", r, g, b)
    end, { category = "Colors / Unit Frame Global Coloring", attribute = "healthGradientLowColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyColors })

    ColorSetting("general.healthGradientMid", "Health Gradient Mid Color", {
        "health gradient mid", "health gradient middle", "health gradient mid color",
        "middle health gradient color", "mid health color", "yellow health gradient color",
    }, function()
        return GeneralRGB("healthGradientMid", 1, 1, 0)
    end, function(r, g, b)
        SetGeneralRGB("healthGradientMid", r, g, b)
    end, { category = "Colors / Unit Frame Global Coloring", attribute = "healthGradientMidColor", defaultR = 1, defaultG = 1, defaultB = 0, apply = ApplyColors })

    ColorSetting("general.healthGradientHigh", "Health Gradient High Color", {
        "health gradient high", "health gradient high color", "high health gradient color",
        "high health color", "full health gradient color", "full hp color",
    }, function()
        return GeneralRGB("healthGradientHigh", 0, 1, 0)
    end, function(r, g, b)
        SetGeneralRGB("healthGradientHigh", r, g, b)
    end, { category = "Colors / Unit Frame Global Coloring", attribute = "healthGradientHighColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyColors })
end
