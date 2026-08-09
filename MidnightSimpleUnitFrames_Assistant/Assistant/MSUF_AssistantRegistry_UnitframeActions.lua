local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Unitframe assistant action domain.
-- Depends on MSUF_AssistantRegistry_Unitframes.lua for shared DB/apply helpers.
local ctx = A.UnitframesRegistry and A.UnitframesRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local UnitDB = ctx.UnitDB
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local UNIT_KEYS = ctx.UNIT_KEYS or {}
local ApplyUnit = ctx.ApplyUnit
local CallGlobal = ctx.CallGlobal
local ResolveUnitStatusSpec = ctx.ResolveUnitStatusSpec
local ApplyStatusRefresh = ctx.ApplyStatusRefresh
local AllowedMap = ctx.AllowedMap
local ANCHOR_TARGET_VALUES = ctx.ANCHOR_TARGET_VALUES or {}
M = ctx.M or M
MSUF = ctx.MSUF or MSUF

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(UnitDB) ~= "function" or type(ApplyUnit) ~= "function" then return end

local BuildUnitframeActionHelpers = A.UnitframesRegistry and A.UnitframesRegistry.BuildUnitframeActionHelpers
local ActionHelpers = type(BuildUnitframeActionHelpers) == "function" and BuildUnitframeActionHelpers({
    UnitDB = UnitDB,
}) or nil
if type(ActionHelpers) ~= "table" then return end
local ResetUnitPositionFromDefaults = ActionHelpers.ResetUnitPositionFromDefaults
local UnitCopyScopeSummary = ActionHelpers.UnitCopyScopeSummary
if type(ResetUnitPositionFromDefaults) ~= "function" or type(UnitCopyScopeSummary) ~= "function" then return end

local function DisplayUnitLabel(unit)
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

local function ApplyEnabledUnit(unit, reason, opts)
    local conf = UnitDB(unit)
    if type(conf) ~= "table" then return false end
    conf.enabled = true
    ApplyUnit(unit, reason, opts or { preview = true })
    return true
end

Registry:RegisterAction({
    key = "enable_focus_target_frame",
    label = "Enable Focus Target Frame",
    page = "uf_focustarget",
    type = "enable",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "enable focus and focus target frames", "activate focus target frame",
        "turn on both focus frames",
    },
    aliasNoArgs = true,
    run = function()
        local focus = UnitDB("focus")
        if type(focus) ~= "table" then return false, "Focus frame settings are not available." end
        if focus.enabled == false then
            ApplyEnabledUnit("focus", "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true })
        end
        if not ApplyEnabledUnit("focustarget", "MSUF2_FRAME_ENABLED", { preview = true }) then
            return false, "Focus Target frame settings are not available."
        end
        return true, "Done. Enabled the Focus and Focus Target frames."
    end,
})

Registry:RegisterAction({
    key = "show_player_power_or_open_class_resources",
    label = "Show Player Power",
    page = "uf_player",
    type = "enable",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "restore the player power display", "bring back the player power bar",
        "re-enable player power bar",
    },
    aliasNoArgs = true,
    run = function()
        local conf = UnitDB("player")
        if type(conf) ~= "table" then return false, "Player power settings are not available." end
        if conf.powerBarDetached == true and conf.detachedPowerBarAnchorToClassPower == true then
            if M and type(M.SelectPage) == "function" then
                M.SelectPage("classpower")
                return true, "Opened Class Resources, which currently manages the Player power bar."
            end
            return false, "Open Class Resources to manage the Player power bar."
        end
        conf.showPowerBar = true
        ApplyUnit("player", "MSUF2_POWER_SHOW", { power = true, preview = true })
        return true, "Done. Showing the Player power bar."
    end,
})

Registry:RegisterAction({
    key = "copy_unit",
    label = "Copy Unit Options",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local src = args and args.source
        local targets = args and args.targets
        if type(src) ~= "string" or type(targets) ~= "table" or #targets == 0 then
            return false, "Which source and destination do you want me to use for the copy?", {
                noMutation = true,
                userFacingFailure = true,
            }
        end
        local UP = M and M.UnitPage
        if not (UP and type(UP.CopyUnitSettings) == "function") then
            return false, "Open a unit frame page first so I can copy those options.", {
                noMutation = true,
                userFacingFailure = true,
            }
        end
        local targetLabels, skippedLabels = {}, {}
        local unsupportedAuraOnly = false
        for i = 1, #targets do
            local applied, result = UP.CopyUnitSettings(src, targets[i], args.scopes)
            -- Older Menu2 providers returned nil after a successful copy. Treat
            -- only an explicit false as failure so the Assistant remains
            -- compatible while current providers can report a precise no-op.
            if applied == false then
                skippedLabels[#skippedLabels + 1] = DisplayUnitLabel(targets[i])
                unsupportedAuraOnly = unsupportedAuraOnly
                    or (type(result) == "table"
                        and (result.reason == "unsupported_aura_scope" or result.reason == "aura_copy_unavailable"))
            else
                targetLabels[#targetLabels + 1] = DisplayUnitLabel(targets[i])
                if type(result) == "table" and result.auraSkipped == true then
                    skippedLabels[#skippedLabels + 1] = DisplayUnitLabel(targets[i])
                end
            end
        end
        if #targetLabels == 0 then
            local message = unsupportedAuraOnly
                and "Nothing was copied. Aura settings are only available for Player, Target, Focus, and Boss Frames."
                or "Nothing was copied to the selected destination."
            return false, message, { noMutation = true, userFacingFailure = true }
        end
        local targetText = table.concat(targetLabels, ", ")
        if targetText == "" then targetText = "the selected destination" end
        local message = "Done. I copied " .. DisplayUnitLabel(src) .. " options to " .. targetText .. "."
            .. UnitCopyScopeSummary(args and args.scopes)
        if #skippedLabels > 0 then
            message = message .. " Aura settings were skipped for " .. table.concat(skippedLabels, ", ") .. "."
        end
        return true, message
    end,
})

local RegisterPositionResetActions = A.UnitframesRegistry and A.UnitframesRegistry.RegisterPositionResetActions
if type(RegisterPositionResetActions) == "function" then
    RegisterPositionResetActions({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        UNIT_KEYS = UNIT_KEYS,
        DisplayUnitLabel = DisplayUnitLabel,
        ApplyUnit = ApplyUnit,
        CallGlobal = CallGlobal,
        ResetUnitPositionFromDefaults = ResetUnitPositionFromDefaults,
        M = M,
        MSUF = MSUF,
    })
end

Registry:RegisterAction({
    key = "reset_unit_page",
    label = "Reset Unit Options",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function(args)
        local unit = args and args.unit
        local page = unit and ("uf_" .. unit)
        if unit == "targettarget" then page = "uf_targettarget" end
        if unit == "focustarget" then page = "uf_focustarget" end
        if type(page) ~= "string" or not (M and type(M.ResetPageToDefaults) == "function") then
            return false, "Open a unit frame page first so I can reset it."
        end
        if M.ResetPageToDefaults(page) then
            return true, "Done. Reset " .. DisplayUnitLabel(unit) .. " options."
        end
        return false, "I kept that frame as it was."
    end,
})

Registry:RegisterAction({
    key = "reset_unit_status_indicator",
    label = "Reset Unit Status Indicator",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "reset selected status indicator", "reset status indicator", "reset status icon", "reset unit status icon" },
    run = function(args)
        local unit = args and args.unit
        local spec = ResolveUnitStatusSpec(unit, args and (args.status or args.text))
        if type(unit) ~= "string" or not spec then
            return false, "Which status indicator do you want me to reset?"
        end

        local conf = UnitDB(unit)
        if spec.inlineName then
            conf[spec.x] = nil
            conf[spec.y] = nil
            conf[spec.anchor] = nil
            conf[spec.layer] = nil
            conf.raidGroupNameStyle = nil
        else
            conf[spec.x] = nil
            conf[spec.y] = nil
            conf[spec.anchor] = nil
            conf[spec.size] = nil
            conf[spec.layer] = nil
            if spec.symbol then conf[spec.symbol] = nil end
            if spec.iconStyle then conf[spec.iconStyle] = nil end
        end
        ApplyStatusRefresh(unit, spec.refresh, spec.statusRuntime, spec.level)
        return true, "Done. Reset " .. DisplayUnitLabel(unit) .. " " .. tostring(spec.label or "status indicator") .. "."
    end,
})

Registry:RegisterAction({
    key = "preview_unit_status_indicator",
    label = "Preview Unit Status Indicator",
    type = "preview",
    combatSafe = true,
    aliases = { "preview current status indicator", "show all status indicators", "preview status icon", "show all status icons" },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local unit = args and args.unit
        local spec = ResolveUnitStatusSpec(unit, args and (args.status or args.text))
        CallGlobal("MSUF_UFPreview_SetStatusPreviewMode", mode)
        if mode == "current" and spec then CallGlobal("MSUF_UFPreview_SelectStatusIcon", spec.value) end
        if mode == "all" then return true, "Done. Showing all status indicators in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current status indicator") .. "."
    end,
})

Registry:RegisterAction({
    key = "clear_unit_custom_anchor",
    label = "Clear Unit Custom Anchor",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "clear custom anchor", "clear custom anchor frame", "reset custom anchor", "remove custom anchor" },
    run = function(args)
        local unit = args and args.unit
        if type(unit) ~= "string" then return false, "Which frame custom anchor do you want me to clear?" end
        local conf = UnitDB(unit)
        local allowed = AllowedMap(ANCHOR_TARGET_VALUES)
        conf.anchorFrameName = nil
        if type(conf.anchorToUnitframe) == "string" and conf.anchorToUnitframe ~= "" and not allowed[conf.anchorToUnitframe] then
            conf.anchorToUnitframe = "GLOBAL"
        end
        ApplyUnit(unit, "MSUF_ASSISTANT_CLEAR_CUSTOM_ANCHOR", { preview = true })
        return true, "Done. Cleared " .. DisplayUnitLabel(unit) .. " custom anchor."
    end,
})
