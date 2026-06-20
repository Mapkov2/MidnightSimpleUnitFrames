-- Assistant GroupFrames spell/corner indicator nested setting registrar.
-- Keeps the registry wrapper separate from the spell indicator context builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorNestedRegistrar(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local ApplyGroup = ctx.ApplyGroup

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(ApplyGroup) ~= "function" then return nil end

    return function(scope, suffix, attr, label, typeName, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. suffix,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            attribute = attr,
            type = typeName,
            aliases = aliases,
            values = opts.values,
            displayValues = opts.displayValues,
            valueAliases = opts.valueAliases,
            valuePrefixes = opts.valuePrefixes or aliases,
            min = opts.min,
            max = opts.max,
            step = opts.step,
            percent = opts.percent == true,
            description = opts.description,
            get = opts.get,
            set = opts.set,
            sameValue = opts.sameValue,
            apply = function() (opts.apply or ApplyGroup)(scope, opts.mode or "visual") end,
            combatSafe = false,
        })
    end
end
