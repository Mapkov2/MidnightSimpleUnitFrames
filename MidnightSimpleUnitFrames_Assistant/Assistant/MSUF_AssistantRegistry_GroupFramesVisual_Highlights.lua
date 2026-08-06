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
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupColor = ctx.RegisterGroupColor

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end

    local AGGRO_MODE_VALUES = { "ALL", "NON_TANK", "HEALER", "TANK" }
    local AGGRO_MODE_ALIASES = {
        all = "ALL",
        everyone = "ALL",
        ["all roles"] = "ALL",
        nontank = "NON_TANK",
        ["non tank"] = "NON_TANK",
        ["non tanks"] = "NON_TANK",
        ["not tank"] = "NON_TANK",
        ["not tanks"] = "NON_TANK",
        ["non-tank"] = "NON_TANK",
        ["non-tanks"] = "NON_TANK",
        ["non tanks only"] = "NON_TANK",
        healer = "HEALER",
        healers = "HEALER",
        ["healers only"] = "HEALER",
        tank = "TANK",
        tanks = "TANK",
        ["tanks only"] = "TANK",
    }

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
    AddAliasesForUnit(aliases, scope, "group number layer")
    AddAliasesForUnit(aliases, scope, "group number draw layer")
    AddAliasesForUnit(aliases, scope, "group number strata")
    AddAliasesForUnit(aliases, scope, "group number frame strata")
    AddAliasesForUnit(aliases, scope, "group index layer")
    RegisterGroupNumber(scope, "groupNumberLayer", "groupNumberLayer", "Group Number Layer", 7, 0, 30, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "fallback aggro border")
    AddAliasesForUnit(aliases, scope, "fallback threat border")
    AddAliasesForUnit(aliases, scope, "group fallback aggro border")
    AddAliasesForUnit(aliases, scope, "group fallback threat border")
    -- "Fallback" belongs in the LABEL, not only in the aliases: without it this
    -- setting and barScope.<scope>.aggroOutlineMode carried the identical label
    -- ("Party Aggro Border"). A player naming that label got the bar-outline
    -- setting changed instead, and this one could not be reached at all. The
    -- aliases already said "fallback"; the visible name now agrees with them.
    -- Safe to word independently: aggroEnabled has no Menu2 control -- it is a
    -- group-config fallback (MSUF_UF_Group_Config.lua), so this label is the
    -- only user-facing name it has.
    RegisterGroupBoolean(scope, "aggroBorder", "aggroEnabled", "Fallback Aggro Border", true, "visual", aliases, {
        description = "Controls the group-frame fallback aggro border toggle for this scope. Global or scoped bar highlight overrides can still take precedence.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "fallback aggro shows for")
    AddAliasesForUnit(aliases, scope, "fallback aggro role filter")
    AddAliasesForUnit(aliases, scope, "fallback threat role filter")
    AddAliasesForUnit(aliases, scope, "fallback aggro non tanks")
    AddAliasesForUnit(aliases, scope, "fallback aggro not tanks")
    AddAliasesForUnit(aliases, scope, "fallback threat non tanks")
    -- Same duplicate-label fix again: this shared "Party Aggro Shows For" with
    -- barScope.<scope>.aggroMode, and its aliases already say "fallback".
    RegisterGroupEnum(scope, "aggroMode", "aggroMode", "Fallback Aggro Shows For", "ALL", AGGRO_MODE_VALUES, AGGRO_MODE_ALIASES, "visual", aliases, {
        description = "Controls which group-member roles can show the aggro border.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "fallback dispel border")
    AddAliasesForUnit(aliases, scope, "fallback dispellable border")
    AddAliasesForUnit(aliases, scope, "group fallback dispel border")
    AddAliasesForUnit(aliases, scope, "group fallback dispellable border")
    -- Same duplicate-label fix as Fallback Aggro Border above: this shared
    -- "Party Dispel Border" with barScope.<scope>.dispelOutlineMode.
    RegisterGroupBoolean(scope, "dispelBorder", "dispelEnabled", "Fallback Dispel Border", true, "visual", aliases, {
        description = "Controls the group-frame fallback dispellable-debuff border toggle for this scope. Global or scoped bar highlight overrides can still take precedence.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "target highlight")
    AddAliasesForUnit(aliases, scope, "target border")
    AddAliasesForUnit(aliases, scope, "selected target border")
    RegisterGroupBoolean(scope, "targetHighlight", "targetIndicator", "Target Highlight", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "target highlight color")
    AddAliasesForUnit(aliases, scope, "target border color")
    AddAliasesForUnit(aliases, scope, "selected target border color")
    RegisterGroupColor(scope, "targetHighlightColor", "target", "Target Highlight Color", 1.00, 1.00, 1.00, aliases)

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
    AddAliasesForUnit(aliases, scope, "focus highlight offset")
    AddAliasesForUnit(aliases, scope, "focus border offset")
    AddAliasesForUnit(aliases, scope, "focus glow offset")
    RegisterGroupNumber(scope, "focusHighlightOffset", "hlFocusOffset", "Focus Highlight Offset", 0, -20, 20, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "focus highlight color")
    AddAliasesForUnit(aliases, scope, "focus border color")
    AddAliasesForUnit(aliases, scope, "focus glow color")
    RegisterGroupColor(scope, "focusHighlightColor", "hlFocusColor", "Focus Highlight Color", 0.50, 0.50, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border")
    AddAliasesForUnit(aliases, scope, "full group border")
    AddAliasesForUnit(aliases, scope, "whole group border")
    AddAliasesForUnit(aliases, scope, "outer group border")
    RegisterGroupBoolean(scope, "groupBorder", "groupBorderEnabled", "Group Border", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border thickness")
    AddAliasesForUnit(aliases, scope, "full group border thickness")
    AddAliasesForUnit(aliases, scope, "outer group border thickness")
    RegisterGroupNumber(scope, "groupBorderSize", "groupBorderSize", "Group Border Thickness", 1, 1, 12, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border padding")
    AddAliasesForUnit(aliases, scope, "full group border padding")
    AddAliasesForUnit(aliases, scope, "outer group border padding")
    RegisterGroupNumber(scope, "groupBorderPadding", "groupBorderPadding", "Group Border Padding", 2, 0, 40, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border color")
    AddAliasesForUnit(aliases, scope, "full group border color")
    AddAliasesForUnit(aliases, scope, "outer group border color")
    RegisterGroupColor(scope, "groupBorderColor", "groupBorder", "Group Border Color", 0.38, 0.68, 1.00, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group border opacity")
    AddAliasesForUnit(aliases, scope, "group border alpha")
    AddAliasesForUnit(aliases, scope, "full group border opacity")
    AddAliasesForUnit(aliases, scope, "outer group border opacity")
    RegisterGroupNumber(scope, "groupBorderAlpha", "groupBorderA", "Group Border Opacity", 0.95, 0, 1, 0.05, "visual", aliases, { percent = true })
end
