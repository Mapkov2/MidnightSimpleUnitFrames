-- Assistant Unitframe position reset actions.
-- Loaded before MSUF_AssistantRegistry_UnitframeActions.lua; the action registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.RegisterPositionResetActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UNIT_KEYS = ctx.UNIT_KEYS or {}
    local DisplayUnitLabel = ctx.DisplayUnitLabel
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal
    local ResetUnitPositionFromDefaults = ctx.ResetUnitPositionFromDefaults
    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(ApplyUnit) ~= "function" or type(ResetUnitPositionFromDefaults) ~= "function" then return end
    if type(DisplayUnitLabel) ~= "function" then
        DisplayUnitLabel = function(unit)
            if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
            unit = tostring(unit or "")
            local label = UNIT_LABELS[unit]
            if label ~= nil and tostring(label) ~= "" then return tostring(label) end
            if unit == "targettarget" then return "Target of Target" end
            if unit == "focustarget" then return "Focus Target" end
            unit = unit:gsub("^uf_", ""):gsub("_", " ")
            unit = unit:gsub("(%l)(%u)", "%1 %2")
            return (unit:gsub("^%l", string.upper))
        end
    end

    Registry:RegisterAction({
        key = "reset_unit_position",
        label = "Reset Unit Position",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local unit = args and args.unit
            if type(unit) ~= "string" then return false, "Which frame position do you want me to reset?" end
            local create = (type(MSUFRef) == "table" and MSUFRef.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
            if type(create) ~= "function" then return false, "Open MSUF first so I can restore factory defaults." end
            local defaults = create()
            if not ResetUnitPositionFromDefaults(unit, defaults) then return false, "I don't see the saved default position for " .. DisplayUnitLabel(unit) .. "." end
            ApplyUnit(unit, "MSUF_ASSISTANT_RESET_POSITION", { preview = true })
            return true, "Done. Reset " .. DisplayUnitLabel(unit) .. " frame position."
        end,
    })

    Registry:RegisterAction({
        key = "reset_all_unit_positions",
        label = "Reset All Unit Positions",
        type = "reset",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        run = function()
            local create = (type(MSUFRef) == "table" and MSUFRef.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
            if type(create) ~= "function" then return false, "Open MSUF first so I can restore factory defaults." end
            local defaults = create()
            local count = 0
            for i = 1, #UNIT_KEYS do
                local unit = UNIT_KEYS[i]
                if ResetUnitPositionFromDefaults(unit, defaults) then
                    ApplyUnit(unit, "MSUF_ASSISTANT_RESET_ALL_POSITIONS", { preview = true })
                    count = count + 1
                end
            end
            if count == 0 then return false, "I don't see saved default frame positions to restore." end
            if type(CallGlobal) == "function" then CallGlobal("MSUF_ForceReanchorAllUnitFrames_Once") end
            return true, "Done. Reset " .. tostring(count) .. " unit-frame positions."
        end,
    })
end
