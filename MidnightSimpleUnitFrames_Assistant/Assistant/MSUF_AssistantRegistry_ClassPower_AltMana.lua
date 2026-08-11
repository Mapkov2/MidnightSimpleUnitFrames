-- Assistant ClassPower alternative mana setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterAltManaSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end
    if type(RegisterBarsEnum) ~= "function" then return end

    RegisterBarsBoolean("showAltMana", "altMana", "Alternative Mana Bar", false, {
        "alternative mana bar", "alt mana bar", "dual resource mana bar", "secondary mana bar",
        "show alternative mana", "show alt mana", "hide alternative mana", "hide alt mana",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA",
    })
    RegisterBarsBoolean("altManaSmoothFill", "smoothFill", "Alternative Mana Smooth Fill", false, {
        "alternative mana smooth fill", "alt mana smooth fill", "smooth alternative mana", "smooth alt mana",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_SMOOTH_FILL",
        description = "Uses native StatusBar interpolation and frequent power events for Alternative Mana.",
    })
    RegisterBarsEnum("altManaWidthMode", "widthMode", "Alternative Mana Width Mode", "player", {
        "player", "custom",
    }, {
        "alternative mana width mode", "alt mana width mode", "alternative mana width source",
        "alt mana follows player frame", "alternative mana custom width",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_WIDTH_MODE",
        valueAliases = {
            ["player frame"] = "player", ["follow player"] = "player",
            auto = "player", automatic = "player", manual = "custom", ["custom width"] = "custom",
        },
    })
    RegisterBarsNumber("altManaWidth", "width", "Alternative Mana Width", 0, 20, 1200, {
        "alternative mana width", "alt mana width", "secondary mana width", "dual resource mana width",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_WIDTH",
    })
    RegisterBarsNumber("altManaHeight", "height", "Alternative Mana Height", 4, 2, 30, {
        "alternative mana height", "alt mana height", "secondary mana height", "dual resource mana height",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_HEIGHT",
    })
    RegisterBarsNumber("altManaOffsetX", "offsetX", "Alternative Mana Offset X", 0, -1000, 1000, {
        "alternative mana x", "alternative mana x offset", "alt mana x", "alt mana x offset", "secondary mana x offset",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_X",
    })
    RegisterBarsNumber("altManaOffsetY", "offsetY", "Alternative Mana Offset Y", -2, -50, 50, {
        "alternative mana y", "alternative mana y offset", "alt mana y", "alt mana y offset", "secondary mana y offset",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_Y",
    })
end
