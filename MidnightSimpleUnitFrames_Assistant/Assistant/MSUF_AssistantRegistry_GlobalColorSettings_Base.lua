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
        key = "general.barBgFillMode",
        label = "Background Fill",
        category = "Colors / Bar Background",
        unit = "global",
        frameType = "colors",
        attribute = "barBackgroundFillMode",
        type = "enum",
        aliases = {
            "background fill", "health background fill", "bar background fill",
            "missing health fill", "missing hp fill", "background filling",
            "hintergrund fuellung", "fehlende gesundheit fuellung", "fehlende hp fuellung",
        },
        values = { "full", "missing" },
        valueLabels = { full = "Full bar", missing = "Missing health only" },
        valueAliases = {
            full = "full", ["full bar"] = "full", ["whole bar"] = "full", ["entire bar"] = "full",
            normal = "full", ["normal fill"] = "full", ["voller balken"] = "full", ["ganzer balken"] = "full",
            missing = "missing", ["missing health"] = "missing", ["missing health only"] = "missing",
            ["missing hp"] = "missing", ["missing hp only"] = "missing", ["health deficit"] = "missing",
            ["fehlende gesundheit"] = "missing", ["fehlende hp"] = "missing", ["nur fehlende gesundheit"] = "missing",
        },
        dbScopes = { { scope = "general", dbKey = "barBgFillMode" } },
        dbScopesReplace = true,
        get = function()
            local fn = ColorAPI().GetBarBgFillMode
            local value = type(fn) == "function" and fn() or GeneralDB().barBgFillMode
            return value == "missing" and "missing" or "full"
        end,
        set = function(value)
            value = value == "missing" and "missing" or "full"
            local fn = ColorAPI().SetBarBgFillMode
            if type(fn) == "function" then fn(value) else GeneralDB().barBgFillMode = value end
        end,
        apply = ApplyColors,
        combatSafe = false,
        description = "Chooses whether the health background covers the full bar or only the missing-health region.",
    })

    Registry:RegisterSetting({
        key = "general.barBgColorMode",
        label = "Background Color",
        category = "Colors / Bar Background",
        unit = "global",
        frameType = "colors",
        attribute = "barBackgroundColorMode",
        type = "enum",
        aliases = {
            "background color mode", "background colour mode", "health background color mode",
            "health background colour mode", "bar background color source", "bar background colour source",
            "background follows hp color", "bar background follows hp", "background matches hp",
            "health background follows class color", "bar background class color", "background follows class color",
            "hintergrund farbmodus", "gesundheitsleisten hintergrundfarbe",
        },
        values = { "custom", "match_health", "class", "health_gradient" },
        valueLabels = {
            custom = "Custom tint", match_health = "Match health bar",
            class = "Class color", health_gradient = "Health gradient",
        },
        valueAliases = {
            custom = "custom", ["custom tint"] = "custom", ["custom color"] = "custom",
            ["custom colour"] = "custom", ["eigene farbe"] = "custom", benutzerdefiniert = "custom",
            ["match health"] = "match_health", ["match health bar"] = "match_health",
            ["same as health"] = "match_health", ["follow health"] = "match_health",
            ["background follows hp color"] = "match_health", ["bar background follows hp"] = "match_health",
            ["background matches hp"] = "match_health", ["wie gesundheitsleiste"] = "match_health",
            class = "class", ["class color"] = "class", ["class colour"] = "class",
            ["health background follows class color"] = "class", ["bar background class color"] = "class",
            ["background follows class color"] = "class", ["klassenfarbe"] = "class",
            ["health gradient"] = "health_gradient", ["hp gradient"] = "health_gradient",
            ["health color gradient"] = "health_gradient", ["health colour gradient"] = "health_gradient",
            ["gesundheitsverlauf"] = "health_gradient",
        },
        -- The two booleans are retained only as synchronized import/API
        -- projections. One reviewed enum owns all three persisted fields.
        dbScopes = {
            { scope = "general", dbKey = "barBgColorMode" },
            { scope = "general", dbKey = "barBgMatchHPColor" },
            { scope = "general", dbKey = "barBgClassColor" },
        },
        dbScopesReplace = true,
        get = function()
            local fn = ColorAPI().GetBarBgColorMode
            local g = GeneralDB()
            local value = type(fn) == "function" and fn() or g.barBgColorMode
            if value == "custom" or value == "match_health" or value == "class" or value == "health_gradient" then
                return value
            end
            if g.barBgClassColor == true then return "class" end
            if g.barBgMatchHPColor == true then return "match_health" end
            return "custom"
        end,
        set = function(value)
            if value ~= "match_health" and value ~= "class" and value ~= "health_gradient" then value = "custom" end
            local fn = ColorAPI().SetBarBgColorMode
            if type(fn) == "function" then
                fn(value)
            else
                local g = GeneralDB()
                g.barBgColorMode = value
                g.barBgMatchHPColor = value == "match_health"
                g.barBgClassColor = value == "class"
            end
        end,
        apply = ApplyColors,
        combatSafe = false,
        description = "Chooses the health-background color source independently from the foreground health bar.",
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
