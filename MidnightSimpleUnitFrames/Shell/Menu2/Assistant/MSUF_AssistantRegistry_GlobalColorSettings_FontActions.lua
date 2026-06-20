-- Assistant global font color action registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterGlobalFontColorActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local MSUFRef = ctx.MSUF or MSUF
    local GeneralDB = ctx.GeneralDB
    local ApplyVisuals = ctx.ApplyVisuals
    local ColorFromName = ctx.ColorFromName
    local Clamp01 = ctx.Clamp01

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(GeneralDB) ~= "function" or type(ApplyVisuals) ~= "function" then return end
    if type(ColorFromName) ~= "function" or type(Clamp01) ~= "function" then return end

    local function ColorDisplayLabel(args)
        local label = args and (args.label or args.color)
        if A and type(A.DisplayColorLabel) == "function" then
            label = A.DisplayColorLabel(label)
        end
        label = tostring(label or "")
        return label ~= "" and label or "custom"
    end

    Registry:RegisterAction({
        key = "set_global_font_color",
        label = "Set Global Font Color",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local r, g, b = args and args.r, args and args.g, args and args.b
            if type(args and args.color) == "string" then
                local cr, cg, cb = ColorFromName(args.color)
                if cr then r, g, b = cr, cg, cb end
            end
            if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                return false, "Which color do you want me to use? A color name, hex value, or RGB value is enough."
            end
            r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
            local api = MSUFRef and MSUFRef._colorsAPI
            if api and type(api.SetGlobalFontColor) == "function" then
                api.SetGlobalFontColor(r, g, b)
            else
                local gen = GeneralDB()
                gen.useCustomFontColor = true
                gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r, g, b
            end
            ApplyVisuals("MSUF_ASSISTANT_FONT_COLOR_CUSTOM")
            return true, "Done. Global font color set to " .. ColorDisplayLabel(args) .. "."
        end,
    })

    Registry:RegisterAction({
        key = "reset_global_font_color",
        label = "Reset Global Font Color",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function()
            local api = MSUFRef and MSUFRef._colorsAPI
            if api and type(api.ResetGlobalFontToPalette) == "function" then
                api.ResetGlobalFontToPalette()
            else
                local gen = GeneralDB()
                gen.useCustomFontColor = false
                gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = nil, nil, nil
            end
            ApplyVisuals("MSUF_ASSISTANT_FONT_COLOR_RESET")
            return true, "Done. Global font color follows the palette again."
        end,
    })
end
