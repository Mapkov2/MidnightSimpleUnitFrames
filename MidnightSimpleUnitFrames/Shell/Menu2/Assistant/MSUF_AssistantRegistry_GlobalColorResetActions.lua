local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Global color reset assistant action domain.
-- Depends on MSUF_AssistantRegistry_Global.lua for color reset helpers.
local ctx = A.GlobalRegistry and A.GlobalRegistry.ColorResetActions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local GeneralDB = ctx.GeneralDB
local ColorAPI = ctx.ColorAPI
local ApplyColors = ctx.ApplyColors
local ApplyCastbarColors = ctx.ApplyCastbarColors

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(ColorAPI) ~= "function" then return end
Registry:RegisterAction({
    key = "reset_class_colors",
    label = "Reset Class Bar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetAllClassColors
        if type(fn) == "function" then fn() else GeneralDB().classColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_CLASS_COLORS")
        return true, "Done. Class bar colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_bar_background_color",
    label = "Reset Bar Background Tint",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetClassBarBgColor
        if type(fn) == "function" then
            fn()
        else
            local g = GeneralDB()
            g.classBarBgR, g.classBarBgG, g.classBarBgB = nil, nil, nil
        end
        ApplyColors("MSUF_ASSISTANT_RESET_BAR_BACKGROUND_COLOR")
        return true, "Done. Bar background tint reset."
    end,
})

Registry:RegisterAction({
    key = "reset_unitframe_colors",
    label = "Reset Unit Frame Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetAllNPCColors
        if type(fn) == "function" then fn() else GeneralDB().npcColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_UNITFRAME_COLORS")
        return true, "Done. Unit frame colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_npc_type_colors",
    label = "Reset NPC Type Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local fn = ColorAPI().ResetNPCTypeColors
        if type(fn) == "function" then fn() else GeneralDB().npcColors = nil end
        ApplyColors("MSUF_ASSISTANT_RESET_NPC_TYPE_COLORS")
        return true, "Done. NPC type colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_bar_colors",
    label = "Reset Bar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = nil, nil, nil, nil
        end
        g.hlAggroColorR, g.hlAggroColorG, g.hlAggroColorB = nil, nil, nil
        g.hlPurgeColorR, g.hlPurgeColorG, g.hlPurgeColorB = nil, nil, nil
        g.aggroBorderColorR, g.aggroBorderColorG, g.aggroBorderColorB = nil, nil, nil
        g.powerBarBgMatchBarColor = nil
        ApplyColors("MSUF_ASSISTANT_RESET_BAR_COLORS")
        return true, "Done. Bar colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_dispel_colors",
    label = "Reset Dispel Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.dispelBorderColorR, g.dispelBorderColorG, g.dispelBorderColorB = nil, nil, nil
        g.hlDispelColorR, g.hlDispelColorG, g.hlDispelColorB = nil, nil, nil
        g.hlDispelColorMode = nil
        for _, key in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
            local prefix = "dispelType" .. key
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
        end
        ApplyColors("MSUF_ASSISTANT_RESET_DISPEL_COLORS")
        return true, "Done. Dispel colors reset."
    end,
})

Registry:RegisterAction({
    key = "reset_castbar_colors",
    label = "Reset Cast Bar Colors",
    type = "color",
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local api = ColorAPI()
        if type(api.ResetCastbarTextColorToGlobal) == "function" then api.ResetCastbarTextColorToGlobal() end
        if type(api.ResetCastbarBorderColor) == "function" then api.ResetCastbarBorderColor() end
        if type(api.ResetCastbarBackgroundColor) == "function" then api.ResetCastbarBackgroundColor() end
        local g = GeneralDB()
        g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil
        g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil
        g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil
        g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = nil, nil, nil
        g.castbarNonInterruptibleR, g.castbarNonInterruptibleG, g.castbarNonInterruptibleB = nil, nil, nil
        g.castbarInterruptFeedbackR, g.castbarInterruptFeedbackG, g.castbarInterruptFeedbackB = nil, nil, nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = nil, nil, nil
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        ApplyCastbarColors("MSUF_ASSISTANT_RESET_CASTBAR_COLORS")
        return true, "Done. Cast bar colors reset."
    end,
})
