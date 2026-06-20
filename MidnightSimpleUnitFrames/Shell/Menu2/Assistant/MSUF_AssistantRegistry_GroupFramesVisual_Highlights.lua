-- Assistant GroupFrames highlight and border visual settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesVisual.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterVisualHighlightSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupColor = ctx.RegisterGroupColor

    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" or type(ClampNumber) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "group number")
    AddAliasesForUnit(aliases, scope, "group index")
    AddAliasesForUnit(aliases, scope, "group number label")
    RegisterGroupBoolean(scope, "groupNumber", "showGroupNumber", "Group Number", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number size")
    AddAliasesForUnit(aliases, scope, "group index size")
    RegisterGroupNumber(scope, "groupNumberSize", "groupNumberSize", "Group Number Size", 10, 6, 24, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number anchor")
    AddAliasesForUnit(aliases, scope, "group index anchor")
    RegisterGroupEnum(scope, "groupNumberAnchor", "groupNumberAnchor", "Group Number Anchor", "BOTTOMRIGHT", { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOPLEFT",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOMRIGHT",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number x")
    AddAliasesForUnit(aliases, scope, "group number x offset")
    AddAliasesForUnit(aliases, scope, "group index x offset")
    RegisterGroupNumber(scope, "groupNumberX", "groupNumberX", "Group Number X Offset", -2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group number y")
    AddAliasesForUnit(aliases, scope, "group number y offset")
    AddAliasesForUnit(aliases, scope, "group index y offset")
    RegisterGroupNumber(scope, "groupNumberY", "groupNumberY", "Group Number Y Offset", 2, -100, 100, 1, "geometry", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hover highlight thickness")
    AddAliasesForUnit(aliases, scope, "mouseover highlight thickness")
    AddAliasesForUnit(aliases, scope, "hover border thickness")
    RegisterGroupNumber(scope, "hoverHighlightSize", "hlHoverSize", "Hover Highlight Thickness", 1, 1, 6, 1, "visual", aliases, {
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.hlHoverSize = ClampNumber(value, 1, 6, 1)
            conf.hlOverride = true
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "target highlight")
    AddAliasesForUnit(aliases, scope, "target border")
    AddAliasesForUnit(aliases, scope, "selected target border")
    RegisterGroupBoolean(scope, "targetHighlight", "targetIndicator", "Target Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight")
    AddAliasesForUnit(aliases, scope, "focus border")
    AddAliasesForUnit(aliases, scope, "focus glow")
    RegisterGroupBoolean(scope, "focusHighlight", "hlFocusEnabled", "Focus Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight thickness")
    AddAliasesForUnit(aliases, scope, "focus border thickness")
    AddAliasesForUnit(aliases, scope, "focus glow thickness")
    RegisterGroupNumber(scope, "focusHighlightSize", "hlFocusSize", "Focus Highlight Thickness", 2, 1, 6, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight color")
    AddAliasesForUnit(aliases, scope, "focus border color")
    AddAliasesForUnit(aliases, scope, "focus glow color")
    RegisterGroupColor(scope, "focusHighlightColor", "hlFocusColor", "Focus Highlight Color", 0.50, 0.50, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border")
    AddAliasesForUnit(aliases, scope, "full group border")
    AddAliasesForUnit(aliases, scope, "group frame border")
    RegisterGroupBoolean(scope, "groupBorder", "groupBorderEnabled", "Group Border", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border thickness")
    AddAliasesForUnit(aliases, scope, "group frame border thickness")
    RegisterGroupNumber(scope, "groupBorderSize", "groupBorderSize", "Group Border Thickness", 1, 1, 12, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border padding")
    AddAliasesForUnit(aliases, scope, "group frame border padding")
    RegisterGroupNumber(scope, "groupBorderPadding", "groupBorderPadding", "Group Border Padding", 2, 0, 40, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border color")
    AddAliasesForUnit(aliases, scope, "group frame border color")
    RegisterGroupColor(scope, "groupBorderColor", "groupBorder", "Group Border Color", 0.38, 0.68, 1.00, aliases)
end
