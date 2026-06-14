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

local POSITION_FIELDS = { "offsetX", "offsetY", "point", "relativePoint", "anchorFrameName", "anchorToUnitframe" }

local function ResetUnitPositionFromDefaults(unit, defaults)
    local src = type(defaults) == "table" and defaults[unit] or nil
    if type(src) ~= "table" then return false end
    local dst = UnitDB(unit)
    for i = 1, #POSITION_FIELDS do
        local key = POSITION_FIELDS[i]
        dst[key] = src[key]
    end
    return true
end

local UNIT_COPY_SCOPE_LABELS = {
    { key = "basics", label = "Frame Basics" },
    { key = "text", label = "Text" },
    { key = "portrait", label = "Portrait" },
    { key = "power", label = "Power Bar" },
    { key = "castbar", label = "Castbar" },
    { key = "status", label = "Status Icons" },
    { key = "load", label = "Load Conditions" },
    { key = "transparency", label = "Transparency" },
    { key = "layout", label = "Size & Anchoring" },
}

local function UnitCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #UNIT_COPY_SCOPE_LABELS do
        local row = UNIT_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " No copy categories were selected." end
    if #selected == total then return " Categories: all unit copy categories." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end

Registry:RegisterAction({
    key = "copy_unit",
    label = "Copy Unit Settings",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local src = args and args.source
        local targets = args and args.targets
        if type(src) ~= "string" or type(targets) ~= "table" or #targets == 0 then
            return false, "Copy needs a source and at least one destination."
        end
        local UP = M and M.UnitPage
        if not (UP and type(UP.CopyUnitSettings) == "function") then
            return false, "Unit copy is not available yet."
        end
        local targetLabels = {}
        for i = 1, #targets do
            UP.CopyUnitSettings(src, targets[i], args.scopes)
            targetLabels[#targetLabels + 1] = tostring(UNIT_LABELS[targets[i]] or targets[i])
        end
        local targetText = table.concat(targetLabels, ", ")
        if targetText == "" then targetText = "the selected destination" end
        return true, "Done. I copied " .. tostring(UNIT_LABELS[src] or src) .. " settings to " .. targetText .. "." .. UnitCopyScopeSummary(args and args.scopes)
    end,
})

Registry:RegisterAction({
    key = "reset_unit_position",
    label = "Reset Unit Position",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local unit = args and args.unit
        if type(unit) ~= "string" then return false, "I do not know which frame position to reset." end
        local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
        if type(create) ~= "function" then return false, "Factory defaults are not available yet." end
        local defaults = create()
        if not ResetUnitPositionFromDefaults(unit, defaults) then return false, "No default position is known for " .. tostring(UNIT_LABELS[unit] or unit) .. "." end
        ApplyUnit(unit, "MSUF_ASSISTANT_RESET_POSITION", { preview = true })
        return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " frame position."
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
        local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
        if type(create) ~= "function" then return false, "Factory defaults are not available yet." end
        local defaults = create()
        local count = 0
        for i = 1, #UNIT_KEYS do
            local unit = UNIT_KEYS[i]
            if ResetUnitPositionFromDefaults(unit, defaults) then
                ApplyUnit(unit, "MSUF_ASSISTANT_RESET_ALL_POSITIONS", { preview = true })
                count = count + 1
            end
        end
        if count == 0 then return false, "No default frame positions are available." end
        if type(CallGlobal) == "function" then CallGlobal("MSUF_ForceReanchorAllUnitFrames_Once") end
        return true, "Done. Reset " .. tostring(count) .. " unit-frame positions."
    end,
})

Registry:RegisterAction({
    key = "reset_unit_page",
    label = "Reset Unit Settings",
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
            return false, "Unit reset is not available right now."
        end
        if M.ResetPageToDefaults(page) then
            return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " settings."
        end
        return false, "Reset failed."
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
            return false, "I do not know which status indicator to reset."
        end

        local conf = UnitDB(unit)
        if spec.inlineName then
            conf[spec.x] = nil
            conf[spec.y] = nil
            conf[spec.anchor] = nil
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
        return true, "Done. Reset " .. tostring(UNIT_LABELS[unit] or unit) .. " " .. tostring(spec.label or "status indicator") .. "."
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
        if type(unit) ~= "string" then return false, "I do not know which custom anchor to clear." end
        local conf = UnitDB(unit)
        local allowed = AllowedMap(ANCHOR_TARGET_VALUES)
        conf.anchorFrameName = nil
        if type(conf.anchorToUnitframe) == "string" and conf.anchorToUnitframe ~= "" and not allowed[conf.anchorToUnitframe] then
            conf.anchorToUnitframe = "GLOBAL"
        end
        ApplyUnit(unit, "MSUF_ASSISTANT_CLEAR_CUSTOM_ANCHOR", { preview = true })
        return true, "Done. Cleared " .. tostring(UNIT_LABELS[unit] or unit) .. " custom anchor."
    end,
})
