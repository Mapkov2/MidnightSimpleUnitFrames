-- Assistant UnitFrame anchoring setting registry.
-- Keeps per-unit anchor controls outside the main UnitFrame registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local function AnchorValueTerms(anchorTerms, value)
    return anchorTerms[value] or { value }
end

local function BuildAnchorValueAliases(unit, anchorValues, anchorTerms, aliasBase)
    local aliases = {}
    for key, value in pairs(aliasBase or {}) do
        aliases[key] = value
    end
    for i = 1, #(anchorValues or {}) do
        local value = anchorValues[i]
        local terms = AnchorValueTerms(anchorTerms or {}, value)
        for j = 1, #terms do
            local term = terms[j]
            aliases["anchor to " .. term] = value
            aliases[tostring(unit) .. " anchor to " .. term] = value
            aliases[tostring(unit) .. " anchor target " .. term] = value
        end
    end
    return aliases
end

function A.UnitframesRegistry.RegisterAnchoringSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitString = ctx.RegisterUnitString
    local UnitDB = ctx.UnitDB
    local AllowedMap = ctx.AllowedMap
    if type(AddAliasesForUnit) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitString) ~= "function" then return end
    if type(UnitDB) ~= "function" or type(AllowedMap) ~= "function" then return end

    local ANCHOR_TARGET_VALUES = ctx.ANCHOR_TARGET_VALUES or {}
    local ANCHOR_TARGET_TERMS = ctx.ANCHOR_TARGET_TERMS or {}
    local ANCHOR_TARGET_ALIAS_BASE = ctx.ANCHOR_TARGET_ALIAS_BASE or {}
    local ANCHOR_POINT_VALUES = ctx.ANCHOR_POINT_VALUES or {}
    local STATUS_ANCHOR_ALIASES = ctx.STATUS_ANCHOR_ALIASES

    local anchorTargetAliases = MakeAliases(unit, "anchor to", "anchor target", "anchor frame")
    for av = 1, #ANCHOR_TARGET_VALUES do
        local anchorValue = ANCHOR_TARGET_VALUES[av]
        if anchorValue ~= unit then
            AddAliasesForUnit(anchorTargetAliases, unit, "anchor to " .. anchorValue)
        end
    end
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to target of target")
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to focus target")
    AddAliasesForUnit(anchorTargetAliases, unit, "anchor to global")
    RegisterUnitEnum(unit, "anchorToUnitframe", "anchorToUnitframe", "Anchor to", "GLOBAL", ANCHOR_TARGET_VALUES, anchorTargetAliases, {
        category = "Anchoring",
        valueAliases = BuildAnchorValueAliases(unit, ANCHOR_TARGET_VALUES, ANCHOR_TARGET_TERMS, ANCHOR_TARGET_ALIAS_BASE),
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            local custom = type(conf.anchorFrameName) == "string" and conf.anchorFrameName or ""
            if custom ~= "" then return "GLOBAL" end
            local value = conf.anchorToUnitframe
            local allowed = AllowedMap(ANCHOR_TARGET_VALUES)
            if allowed[value] and value ~= unitKey then return value end
            return "GLOBAL"
        end,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            if value == unitKey then value = "GLOBAL" end
            conf.anchorToUnitframe = value or "GLOBAL"
            conf.anchorFrameName = nil
        end,
    })
    RegisterUnitEnum(unit, "anchorPoint", "point", "Anchor Point", "CENTER", ANCHOR_POINT_VALUES, MakeAliases(unit, "anchor point", "frame anchor point", "anchor position"), {
        category = "Anchoring",
        valueAliases = STATUS_ANCHOR_ALIASES,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            conf.point = value or "CENTER"
            conf.relativePoint = value or "CENTER"
        end,
    })
    RegisterUnitString(unit, "anchorFrameName", "anchorFrameName", "Custom Anchor Frame", "", MakeAliases(unit, "custom anchor frame", "anchor frame name", "custom anchor"), {
        category = "Anchoring",
        description = "Frame name used by the custom anchor text box. The UI picker remains interactive.",
        set = function(unitKey, value)
            UnitDB(unitKey).anchorFrameName = tostring(value or "")
            UnitDB(unitKey).anchorToUnitframe = "GLOBAL"
        end,
    })
end
