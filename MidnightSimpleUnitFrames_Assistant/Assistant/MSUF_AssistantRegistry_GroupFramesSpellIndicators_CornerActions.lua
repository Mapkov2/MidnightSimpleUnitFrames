-- Assistant GroupFrames corner indicator action registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSpellIndicators_Actions.lua; the main action registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterSpellIndicatorCornerResetActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local CI_SLOTS = ctx.CI_SLOTS or {}
    local Scope = ctx.Scope
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup
    local ResolveSlot = ctx.ResolveSlot

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(Scope) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(ApplyGroup) ~= "function" or type(ResolveSlot) ~= "function" then return end

    local function GroupLabel(scope)
        if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
        local label = UNIT_LABELS[scope]
        if label ~= nil and tostring(label) ~= "" then return tostring(label) end
        if scope == "mythicraid" then return "Mythic Raid" end
        if scope == "raid" then return "Raid" end
        return "Party"
    end

    Registry:RegisterAction({
        key = "reset_group_corner_indicator_slot",
        label = "Reset Group Corner Indicator Slot",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local scope, slot = Scope(args and args.scope), ResolveSlot(args and args.slot)
            if not slot then return false, "Which corner slot do you want me to use? Examples: top left or bottom right." end
            local conf = GroupDB(scope)
            conf["ciSlot" .. slot.key] = slot.default or "none"
            conf["ciCustom" .. slot.key] = nil
            ApplyGroup(scope, "visual")
            return true, "Done. Reset " .. GroupLabel(scope) .. " " .. tostring(slot.label) .. " corner indicator."
        end,
    })

    Registry:RegisterAction({
        key = "reset_group_corner_indicators",
        label = "Reset Group Corner Indicators",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local scope = Scope(args and args.scope)
            local conf = GroupDB(scope)
            conf.ciEnabled, conf.ciSize, conf.ciAlpha, conf.ciLayer, conf.ciStrata = false, 8, 1, 7, "AUTO"
            for i = 1, #CI_SLOTS do
                local slot = CI_SLOTS[i]
                conf["ciSlot" .. slot.key] = slot.default or "none"
                conf["ciCustom" .. slot.key] = nil
            end
            ApplyGroup(scope, "visual")
            return true, "Done. Reset " .. GroupLabel(scope) .. " corner indicators."
        end,
    })
end
