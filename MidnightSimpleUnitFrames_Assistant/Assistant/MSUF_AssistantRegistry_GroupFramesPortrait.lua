-- Assistant registry for the Party-only GroupFrames portrait workspace.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterPortraitSettings(ctx)
    if type(ctx) ~= "table" then return end
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupString = ctx.RegisterGroupString
    local RegisterGroupColor = ctx.RegisterGroupColor
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function"
        or type(RegisterGroupEnum) ~= "function"
        or type(RegisterGroupString) ~= "function" or type(RegisterGroupColor) ~= "function" then
        return
    end

    local scope = "party"
    local data = A.UnitframeRegistryData or {}
    local page = { page = "gf_layout" }
    local aliasPrefixes = {
        "group frame", "group frames", "party", "party frame", "party frames",
        "group", "gruppenframe", "gruppenframes",
    }
    local aliasSuffixes = { "party", "group" }
    local function Aliases(...)
        local aliases = {}
        local seen = {}
        local function Add(value)
            value = tostring(value or "")
            if value == "" or seen[value] or #aliases >= 32 then return end
            seen[value] = true
            aliases[#aliases + 1] = value
        end
        for i = 1, select("#", ...) do
            local noun = select(i, ...)
            for j = 1, #aliasPrefixes do Add(aliasPrefixes[j] .. " " .. noun) end
            for j = 1, #aliasSuffixes do Add(noun .. " " .. aliasSuffixes[j]) end
            local beforePortrait = tostring(noun):match("^(.-)%s+in%s+portrait$")
            if beforePortrait then
                Add(beforePortrait .. " in group frame portrait")
                Add(beforePortrait .. " in party frame portrait")
            end
        end
        return aliases
    end
    local function Enum(attr, key, label, defaultValue, values, aliases, valueAliases, description)
        RegisterGroupEnum(scope, attr, key, label, defaultValue, values, valueAliases, "config", aliases, {
            page = page.page,
            description = description,
        })
    end
    local function Number(attr, key, label, defaultValue, minValue, maxValue, step, aliases, percent, description)
        RegisterGroupNumber(scope, attr, key, label, defaultValue, minValue, maxValue, step, "config", aliases, {
            page = page.page,
            percent = percent == true,
            description = description,
        })
    end
    local function Boolean(attr, key, label, defaultValue, aliases)
        RegisterGroupBoolean(scope, attr, key, label, defaultValue, "config", aliases, page)
    end
    local function NormalizePortraitClassStyle(value)
        value = tostring(value or "")
        local normalized = value:upper():gsub("%s+", "_"):gsub("%-", "_")
        if normalized == "RONDO_COLOR" or normalized == "RONDO_WOW" or normalized == "BLIZZARD" then
            return normalized
        end
        if M and type(M.NormalizePortraitClassStyle) == "function" then
            return M.NormalizePortraitClassStyle(value)
        end
        local normalize = _G.MSUF_NormalizePortraitClassStyleValue
        if type(normalize) == "function" then return normalize(value) end
        return "BLIZZARD"
    end

    Enum("portraitMode", "portraitMode", "Portrait Position", "OFF",
        data.PORTRAIT_MODE_VALUES or { "OFF", "LEFT", "RIGHT" },
        Aliases("portrait", "portrait position", "portrait side"), {
            off = "OFF", hide = "OFF", hidden = "OFF", disabled = "OFF", disable = "OFF",
            on = "LEFT", enable = "LEFT", enabled = "LEFT", show = "LEFT", visible = "LEFT",
            left = "LEFT", right = "RIGHT",
        })
    Enum("portraitRender", "portraitRender", "Portrait Render", "2D",
        data.PORTRAIT_RENDER_VALUES or { "2D", "CLASS" },
        Aliases("portrait render", "portrait type", "class portrait"), {
            ["2d"] = "2D", ["2d portrait"] = "2D", portrait = "2D",
            class = "CLASS", ["class portrait"] = "CLASS",
        })
    Boolean("portraitCastSpellIcon", "portraitCastSpellIcon", "Show Cast Spell Icon In Portrait", false,
        Aliases("cast spell icon in portrait", "portrait cast icon", "portrait spell icon"))
    Enum("portraitShape", "portraitShape", "Portrait Shape", "SQUARE",
        data.PORTRAIT_SHAPE_VALUES or { "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND" },
        Aliases("portrait shape"), {
            square = "SQUARE", circle = "CIRCLE", round = "CIRCLE", rounded = "ROUNDED", diamond = "DIAMOND",
        })
    Enum("portraitSizeMode", "portraitSizeMode", "Portrait Size Mode", "UNIFORM",
        { "UNIFORM", "SEPARATE" },
        Aliases("portrait size mode", "uniform portrait size", "separate portrait width and height"), {
            uniform = "UNIFORM", square = "UNIFORM", linked = "UNIFORM", locked = "UNIFORM",
            separate = "SEPARATE", independent = "SEPARATE", custom = "SEPARATE",
            ["width and height"] = "SEPARATE", ["width & height"] = "SEPARATE",
        }, "Uniform uses one size for both axes; Width & Height applies the two axis overrides independently.")
    Number("portraitSizeOverride", "portraitSizeOverride", "Portrait Size Override", 0, 0, 128, 1,
        Aliases("portrait size", "portrait size override"))
    Number("portraitWidth", "portraitWidth", "Portrait Width Override", 0, 0, 256, 1,
        Aliases("portrait width", "portrait width override"))
    Number("portraitHeight", "portraitHeight", "Portrait Height Override", 0, 0, 256, 1,
        Aliases("portrait height", "portrait height override"))
    Number("portraitOffsetX", "portraitOffsetX", "Portrait X Offset", 0, -400, 400, 1,
        Aliases("portrait x", "portrait x offset"))
    Number("portraitOffsetY", "portraitOffsetY", "Portrait Y Offset", 0, -400, 400, 1,
        Aliases("portrait y", "portrait y offset"))
    Number("portraitZoom", "portraitZoom", "Portrait Zoom", 100, 100, 200, 1,
        Aliases("portrait zoom", "2d portrait zoom", "portrait crop"))
    Number("portraitPanX", "portraitPanX", "Portrait Zoom Center X", 0, -100, 100, 1,
        Aliases("portrait zoom center x", "portrait pan x"))
    Number("portraitPanY", "portraitPanY", "Portrait Zoom Center Y", 0, -100, 100, 1,
        Aliases("portrait zoom center y", "portrait pan y"))

    RegisterGroupString(scope, "portraitClassStyle", "portraitClassStyle", "Class Portrait Style", "BLIZZARD",
        "config", Aliases("portrait class style", "class portrait style"), {
            page = page.page,
            mediaType = "portraitpack",
            normalizeValue = NormalizePortraitClassStyle,
            description = "Chooses the class portrait style from the portrait media list.",
        })
    Enum("portraitPlacement", "portraitPlacement", "Portrait Placement", "ATTACHED",
        data.PORTRAIT_PLACEMENT_VALUES or { "ATTACHED", "DETACHED", "OVERLAY" },
        Aliases("portrait placement", "detach portrait", "detached portrait", "portrait overlay"), {
            attached = "ATTACHED", attach = "ATTACHED", default = "ATTACHED",
            detached = "DETACHED", detach = "DETACHED", free = "DETACHED", floating = "DETACHED",
            overlay = "OVERLAY", inside = "OVERLAY", ["on bar"] = "OVERLAY",
        })
    local points = data.PORTRAIT_ANCHOR_POINT_VALUES or {
        "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
    }
    local pointAliases = {
        ["top left"] = "TOPLEFT", topleft = "TOPLEFT", top = "TOP",
        ["top right"] = "TOPRIGHT", topright = "TOPRIGHT", left = "LEFT",
        center = "CENTER", middle = "CENTER", right = "RIGHT",
        ["bottom left"] = "BOTTOMLEFT", bottomleft = "BOTTOMLEFT", bottom = "BOTTOM",
        ["bottom right"] = "BOTTOMRIGHT", bottomright = "BOTTOMRIGHT",
    }
    Enum("portraitDetachedPoint", "portraitDetachedPoint", "Portrait Anchor Point", "RIGHT", points,
        Aliases("portrait anchor point", "detached portrait anchor"), pointAliases)
    Enum("portraitDetachedTo", "portraitDetachedTo", "Portrait Attach To Frame Point", "LEFT", points,
        Aliases("portrait attach to", "detached portrait frame point"), pointAliases)
    Enum("portraitOverlayAlign", "portraitOverlayAlign", "Portrait Overlay Alignment", "LEFT",
        data.PORTRAIT_OVERLAY_ALIGN_VALUES or { "LEFT", "CENTER", "RIGHT", "FULL" },
        Aliases("portrait overlay alignment", "portrait overlay align"), {
            left = "LEFT", center = "CENTER", centre = "CENTER", middle = "CENTER",
            right = "RIGHT", full = "FULL", fill = "FULL", stretch = "FULL",
        })
    Number("portraitLevelOffset", "portraitLevelOffset", "Portrait Layer", 7, 0, 30, 1,
        Aliases("portrait layer", "portrait layer offset", "portrait frame level"))
    Number("portraitAlpha", "portraitAlpha", "Portrait Opacity", 100, 0, 100, 1,
        Aliases("portrait opacity", "portrait alpha", "portrait transparency"))

    Enum("portraitBorderStyle", "portraitBorderStyle", "Portrait Border", "NONE",
        data.PORTRAIT_BORDER_VALUES or { "NONE", "SOLID", "CLASS_COLOR", "REACTION", "CUSTOM" },
        Aliases("portrait border", "portrait border style"), {
            none = "NONE", off = "NONE", disabled = "NONE", solid = "SOLID",
            class = "CLASS_COLOR", ["class color"] = "CLASS_COLOR",
            reaction = "REACTION", ["reaction color"] = "REACTION",
            custom = "CUSTOM", ["custom color"] = "CUSTOM",
        })
    Number("portraitEdgeSoftness", "portraitEdgeSoftness", "Portrait Edge Softness", 0, 0, 30, 2,
        Aliases("portrait edge softness", "soft portrait edge", "portrait feather", "borderless portrait fade"),
        false, "Softens the portrait silhouette when its border is disabled, from 0 to 30 percent.")
    Number("portraitBorderThickness", "portraitBorderThickness", "Portrait Border Thickness", 2, 1, 12, 1,
        Aliases("portrait border thickness", "portrait border size"))
    Boolean("portraitFillBorder", "portraitFillBorder", "Portrait Fill Border Gap", false,
        Aliases("portrait fill border", "fill portrait border gap"))
    Enum("portraitBorderArt", "portraitBorderArt", "Portrait Border Art", "FLAT",
        data.PORTRAIT_BORDER_ART_VALUES or { "FLAT", "RELIEF" },
        Aliases("portrait border art", "portrait relief border", "blizzard portrait border"), {
            flat = "FLAT", plain = "FLAT", simple = "FLAT",
            relief = "RELIEF", beveled = "RELIEF", bevel = "RELIEF", blizzard = "RELIEF",
        })
    Enum("portraitBorderDirection", "portraitBorderDirection", "Portrait Border Direction", "UP",
        data.PORTRAIT_BORDER_DIRECTION_VALUES or { "UP", "RIGHT", "DOWN", "LEFT" },
        Aliases("portrait border direction", "portrait border rotation"), {
            up = "UP", top = "UP", right = "RIGHT", down = "DOWN", bottom = "DOWN", left = "LEFT",
        })
    RegisterGroupColor(scope, "portraitBorderColor", "portraitBorderColor", "Portrait Border Color",
        1, 1, 1, Aliases("portrait border color", "custom portrait border color"), {
            mode = "config",
            page = page.page,
        })
    -- The border color and its opacity are edited through the Advanced Colors
    -- context popup ("group.portrait.border"), not by a slider on the Group
    -- Layout page, so this stays page-less like the Group Border opacity.
    RegisterGroupNumber(scope, "portraitBorderColorA", "portraitBorderColorA", "Portrait Border Opacity",
        1, 0, 1, 0.05, "config", Aliases("portrait border opacity", "portrait border alpha"),
        { percent = true })

    Boolean("portraitBgEnabled", "portraitBgEnabled", "Portrait Background", false,
        Aliases("portrait background", "portrait bg"))
    RegisterGroupColor(scope, "portraitBgColor", "portraitBgColor", "Portrait Background Color",
        0.05, 0.05, 0.05, Aliases("portrait background color", "portrait bg color"), {
            mode = "config",
            page = page.page,
        })
    Number("portraitBgColorA", "portraitBgColorA", "Portrait Background Opacity", 0.85, 0, 1, 0.05,
        Aliases("portrait background opacity", "portrait background alpha"), true)
end
