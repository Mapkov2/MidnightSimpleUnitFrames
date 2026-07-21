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
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local GeneralDB = ctx.GeneralDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local ColorFromName = ctx.ColorFromName
    local ApplyColors = ctx.ApplyColors
    local function CurrentApplyService()
        return (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function ApplyBossTargetHighlightColor(reason)
        reason = reason or "MSUF_ASSISTANT_BOSS_TARGET_HIGHLIGHT_COLOR"
        local apply = CurrentApplyService()
        if apply and type(apply.RequestBossTargetBorder) == "function" then
            return apply.RequestBossTargetBorder(reason, "boss") ~= false
        end
        if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then
            _G.MSUF_UFCore_RefreshSettingsCache(reason)
        end
        if apply and type(apply.RequestUnit) == "function" then
            return apply.RequestUnit("boss", reason, { preview = true }) ~= false
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            return _G.MSUF_UFCore_NotifyConfigChanged("boss", true, true, reason) ~= false
        end
        return false
    end

    if type(ColorSetting) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return end
    if type(SetTableRGB) ~= "function" or type(ColorFromName) ~= "function" then return end

    RegisterGeneralBoolean("highlightEnabled", "mouseoverHighlight", "Mouseover Highlight", true, {
        "mouseover highlight", "hover highlight", "unitframe mouseover highlight",
    }, { category = "Miscellaneous / Mouseover Highlight", frameType = "misc", page = "opt_misc", apply = ApplyColors, reason = "MSUF_ASSISTANT_MOUSEOVER_HIGHLIGHT" })
    if type(RegisterGeneralEnum) == "function" then
        RegisterGeneralEnum("highlightStyle", "mouseoverHighlightStyle", "Mouseover Highlight Style", "GRADIENT",
            { "GRADIENT", "BORDER" }, {
                "mouseover highlight style", "hover highlight style", "hover gradient", "hover border style",
            }, {
                category = "Miscellaneous / Mouseover Highlight", frameType = "misc", page = "opt_misc", apply = ApplyColors,
                valueAliases = { gradient = "GRADIENT", soft = "GRADIENT", border = "BORDER", solid = "BORDER" },
            })
    end
    if type(RegisterGeneralNumberSetting) == "function" then
        RegisterGeneralNumberSetting("highlightThickness", "mouseoverHighlightSize", "Mouseover Highlight Size", 6, 1, 16, {
            "mouseover highlight size", "hover highlight size", "mouseover highlight thickness", "hover border thickness",
        }, {
            category = "Miscellaneous / Mouseover Highlight", frameType = "misc", page = "opt_misc", apply = ApplyColors,
            description = "Controls the width of the soft gradient or solid mouseover border.",
        })
    end
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
    end, { category = "Colors / Mouseover Highlight", attribute = "bossTargetHighlightColor", defaultR = 1, defaultG = 0.82, defaultB = 0, apply = ApplyBossTargetHighlightColor })
end
