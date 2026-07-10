-- Assistant GroupFrames status-icon helper core.
-- Builds status-icon lookup, alias, and reset helpers for the shared GroupFrames registry core.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildStatusIconCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local GroupFramesData = ctx.GroupFramesData
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup

    if type(GroupFramesData) ~= "table" then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return nil end
    if type(ApplyGroup) ~= "function" then return nil end

    local GROUP_STATUS_ICON_SPECS = GroupFramesData.GROUP_STATUS_ICON_SPECS or {}

    local function AddGroupStatusIconAliases(out, scope, spec, suffix)
        for i = 1, #(spec.terms or {}) do
            local term = spec.terms[i]
            local alias = suffix and (term .. " " .. suffix) or term
            out[#out + 1] = alias
            out[#out + 1] = "group " .. alias
            out[#out + 1] = "group status " .. alias
            out[#out + 1] = "group indicator " .. alias
            AddAliasesForUnit(out, scope, alias)
            if suffix then
                local prefixAlias = suffix .. " " .. term
                out[#out + 1] = prefixAlias
                out[#out + 1] = "group " .. prefixAlias
                out[#out + 1] = "group status " .. prefixAlias
                out[#out + 1] = "group indicator " .. prefixAlias
                AddAliasesForUnit(out, scope, prefixAlias)
            end
        end
    end

    local GROUP_STATUS_ICON_LOOKUP = {}
    for i = 1, #GROUP_STATUS_ICON_SPECS do
        local spec = GROUP_STATUS_ICON_SPECS[i]
        GROUP_STATUS_ICON_LOOKUP[spec.value:lower()] = spec
        GROUP_STATUS_ICON_LOOKUP[tostring(spec.label or ""):lower():gsub("[^%w]+", "")] = spec
        for j = 1, #(spec.terms or {}) do
            GROUP_STATUS_ICON_LOOKUP[spec.terms[j]:lower():gsub("[^%w]+", "")] = spec
        end
    end

    local function ResolveGroupStatusIcon(value)
        local key = tostring(value or ""):lower():gsub("[^%w]+", "")
        return GROUP_STATUS_ICON_LOOKUP[key]
    end

    local function ResetGroupStatusIcon(scope, spec)
        if not spec then return false end
        local conf = GroupDB(scope)
        for _, key in ipairs({ spec.size, spec.anchor, spec.x, spec.y, spec.layer, spec.iconStyle, spec.customIcon }) do
            if key then conf[key] = nil end
        end
        ApplyGroup(scope, "visual")
        return true
    end

    return {
        AddGroupStatusIconAliases = AddGroupStatusIconAliases,
        ResolveGroupStatusIcon = ResolveGroupStatusIcon,
        ResetGroupStatusIcon = ResetGroupStatusIcon,
        GROUP_STATUS_ICON_STYLE_VALUES = GroupFramesData.GROUP_STATUS_ICON_STYLE_VALUES or {},
        GROUP_STATUS_ICON_STYLE_ALIASES = GroupFramesData.GROUP_STATUS_ICON_STYLE_ALIASES or {},
        GROUP_STATUS_ICON_PACK_VALUES = GroupFramesData.GROUP_STATUS_ICON_PACK_VALUES or {},
        GROUP_STATUS_ICON_PACK_ALIASES = GroupFramesData.GROUP_STATUS_ICON_PACK_ALIASES or {},
        GROUP_STATUS_ANCHOR_VALUES = GroupFramesData.GROUP_STATUS_ANCHOR_VALUES or {},
        GROUP_STATUS_ANCHOR_ALIASES = GroupFramesData.GROUP_STATUS_ANCHOR_ALIASES or {},
        GROUP_STATUS_ICON_SPECS = GROUP_STATUS_ICON_SPECS,
    }
end
