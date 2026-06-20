-- Assistant mouseover and boss-target highlight color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterHighlightColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local ColorSetting = ctx.ColorSetting
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local GeneralDB = ctx.GeneralDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local ColorFromName = ctx.ColorFromName
    local ApplyColors = ctx.ApplyColors

    if type(ColorSetting) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return end
    if type(SetTableRGB) ~= "function" or type(ColorFromName) ~= "function" then return end

    RegisterGeneralBoolean("highlightEnabled", "mouseoverHighlight", "Mouseover Highlight", true, {
        "mouseover highlight", "hover highlight", "unitframe mouseover highlight",
    }, { category = "Colors / Mouseover Highlight", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_MOUSEOVER_HIGHLIGHT" })
    ColorSetting("general.highlightColor", "Mouseover Highlight Color", {
        "mouseover highlight color", "hover highlight color", "unitframe highlight color",
    }, function()
        local color = GeneralDB().highlightColor
        if type(color) == "table" then return TableRGB(GeneralDB(), "highlightColor", 1, 1, 1) end
        local r, g, b = ColorFromName(color or "white")
        return r or 1, g or 1, b or 1
    end, function(r, g, b)
        GeneralDB().highlightColor = { r, g, b }
    end, { category = "Colors / Mouseover Highlight", attribute = "mouseoverHighlightColor", apply = ApplyColors })
    ColorSetting("general.bossTargetHighlightColor", "Boss Target Highlight Color", {
        "boss target highlight color", "boss target color", "boss target border highlight color",
    }, function()
        return TableRGB(GeneralDB(), "bossTargetHighlightColor", 1, 0.82, 0)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), "bossTargetHighlightColor", r, g, b)
    end, { category = "Colors / Mouseover Highlight", attribute = "bossTargetHighlightColor", defaultR = 1, defaultG = 0.82, defaultB = 0, apply = ApplyColors })
end
