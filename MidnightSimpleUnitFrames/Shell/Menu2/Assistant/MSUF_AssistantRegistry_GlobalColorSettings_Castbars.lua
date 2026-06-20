-- Assistant global castbar color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterCastbarColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local ColorSetting = ctx.ColorSetting
    local GeneralRGB = ctx.GeneralRGB
    local SetGeneralRGB = ctx.SetGeneralRGB
    local GeneralDB = ctx.GeneralDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local ApiRGB = ctx.ApiRGB
    local ApiSetRGB = ctx.ApiSetRGB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local ApplyCastbarColors = ctx.ApplyCastbarColors
    local COLOR_CASTBAR_ROWS = ctx.COLOR_CASTBAR_ROWS or {}

    if type(ColorSetting) ~= "function" then return end
    if type(GeneralRGB) ~= "function" or type(SetGeneralRGB) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return end
    if type(SetTableRGB) ~= "function" or type(ApiRGB) ~= "function" or type(ApiSetRGB) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralEnum) ~= "function" then return end

    for _, row in ipairs(COLOR_CASTBAR_ROWS) do
        ColorSetting("general." .. row.key .. "Color", row.label, row.aliases, function()
            return ApiRGB(row.get, row.dr, row.dg, row.db, function() return GeneralRGB(row.key, row.dr, row.dg, row.db) end)
        end, function(r, g, b)
            local fallbackPrefix = row.key
            if row.key == "castbarFont" then fallbackPrefix = "castbarFont" end
            if not ApiSetRGB(row.set, r, g, b) then SetGeneralRGB(fallbackPrefix, r, g, b) end
        end, { category = "Colors / Cast Bar", attribute = row.key .. "Color", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyCastbarColors })
    end

    ColorSetting("general.castbarBorderColor", "Castbar Border Color", {
        "castbar border color", "cast bar border color", "castbar outline color",
    }, function()
        return ApiRGB("GetCastbarBorderColor", 0, 0, 0, function() return GeneralRGB("castbarBorder", 0, 0, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetCastbarBorderColor", r, g, b, 1) then SetGeneralRGB("castbarBorder", r, g, b) end
    end, { category = "Colors / Cast Bar", attribute = "castbarBorderColor", defaultR = 0, defaultG = 0, defaultB = 0, apply = ApplyCastbarColors })

    ColorSetting("general.castbarBackgroundColor", "Castbar Background Color", {
        "castbar background color", "cast bar background color", "castbar bg color",
    }, function()
        return ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10, function() return GeneralRGB("castbarBg", 0.10, 0.10, 0.10) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetCastbarBackgroundColor", r, g, b, 0.85) then SetGeneralRGB("castbarBg", r, g, b) end
    end, { category = "Colors / Cast Bar", attribute = "castbarBackgroundColor", defaultR = 0.10, defaultG = 0.10, defaultB = 0.10, apply = ApplyCastbarColors })

    RegisterGeneralBoolean("playerCastbarOverrideEnabled", "playerCastbarOverride", "Player Castbar Color Override", true, {
        "player castbar color override", "player castbar override", "player cast color override",
    }, { category = "Colors / Cast Bar", frameType = "colors", apply = ApplyCastbarColors, reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE" })
    RegisterGeneralEnum("playerCastbarOverrideMode", "playerCastbarOverrideMode", "Player Castbar Override Mode", "CLASS", { "CLASS", "CUSTOM" }, {
        "player castbar override mode", "player castbar color mode",
    }, {
        category = "Colors / Cast Bar",
        frameType = "colors",
        apply = ApplyCastbarColors,
        reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE_MODE",
        valueAliases = { class = "CLASS", classcolor = "CLASS", custom = "CUSTOM", color = "CUSTOM", manual = "CUSTOM" },
    })
    ColorSetting("general.playerCastbarOverrideColor", "Player Castbar Override Color", {
        "player castbar override color", "player castbar custom color", "player cast custom color",
    }, function()
        return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1, function() return GeneralRGB("playerCastbarOverride", 0, 0.6, 1) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, b) then SetGeneralRGB("playerCastbarOverride", r, g, b) end
    end, { category = "Colors / Cast Bar", attribute = "playerCastbarOverrideColor", defaultR = 0, defaultG = 0.6, defaultB = 1, apply = ApplyCastbarColors })

    ColorSetting("general.kickReadyColor", "Kick Ready Color", {
        "kick ready color", "interrupt ready color", "ready kick color",
    }, function()
        return TableRGB(GeneralDB(), "kickReadyColor", 0, 1, 0)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), "kickReadyColor", r, g, b)
    end, { category = "Colors / Cast Bar", attribute = "kickReadyColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyCastbarColors })
    ColorSetting("general.kickNotReadyColor", "Kick Not Ready Color", {
        "kick not ready color", "interrupt not ready color", "kick cooldown color",
    }, function()
        return TableRGB(GeneralDB(), "kickNotReadyColor", 1, 0, 0)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), "kickNotReadyColor", r, g, b)
    end, { category = "Colors / Cast Bar", attribute = "kickNotReadyColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyCastbarColors })
end
