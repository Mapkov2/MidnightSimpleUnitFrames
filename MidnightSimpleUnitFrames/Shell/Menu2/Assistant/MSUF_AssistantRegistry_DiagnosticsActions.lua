local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Diagnostics assistant diagnostic and repair action domain.
-- Navigation, help, support, and telemetry actions live in the adjacent split file.
local ctx = A.DiagnosticsRegistry and A.DiagnosticsRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

local UNIT_LABELS = ctx.UNIT_LABELS or {}
local GeneralDB = ctx.GeneralDB
local UnitDB = ctx.UnitDB
local CASTBAR_KEYS = ctx.CASTBAR_KEYS or {}
local GetCastbarBackend = ctx.GetCastbarBackend
local AddFixChoice = ctx.AddFixChoice
local AppendFixChoices = ctx.AppendFixChoices
local UnitFrameDiagnosticText = ctx.UnitFrameDiagnosticText
local GroupFrameDiagnosticText = ctx.GroupFrameDiagnosticText
local AuraDiagnosticText = ctx.AuraDiagnosticText
local ClearBrokenSpecProfileMappings = ctx.ClearBrokenSpecProfileMappings
local ProfileDiagnosticText = ctx.ProfileDiagnosticText
local ClassPowerDiagnosticText = ctx.ClassPowerDiagnosticText
local GameplayDiagnosticText = ctx.GameplayDiagnosticText
local DashboardSetupDiagnosticText = ctx.DashboardSetupDiagnosticText

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(UnitDB) ~= "function" or type(GetCastbarBackend) ~= "function" then return end
if type(AddFixChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return end
if type(UnitFrameDiagnosticText) ~= "function" or type(GroupFrameDiagnosticText) ~= "function" or type(AuraDiagnosticText) ~= "function" then return end
if type(ClearBrokenSpecProfileMappings) ~= "function" or type(ProfileDiagnosticText) ~= "function" then return end
if type(ClassPowerDiagnosticText) ~= "function" or type(GameplayDiagnosticText) ~= "function" or type(DashboardSetupDiagnosticText) ~= "function" then return end

local function UnitLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local label = UNIT_LABELS[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit Frame")
end

local function UnitCommandLabel(unit)
    return UnitLabel(unit):lower()
end

Registry:RegisterAction({
    key = "diagnose_castbar_visibility",
    label = "Check Cast Bar Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "target"
        if not CASTBAR_KEYS[unit] then return false, "I can check Player, Target, Focus, or Boss cast bars here." end
        local g = GeneralDB()
        local backend = GetCastbarBackend(unit, g)
        local unitEnabled = true
        if unit ~= "boss" then unitEnabled = UnitDB(unit).enabled ~= false end
        local label = UnitLabel(unit)
        local choices = {}
        if backend == "HIDE" then
            AddFixChoice(choices, "general." .. tostring(CASTBAR_KEYS[unit].enable), true, "Show " .. label .. " cast bar")
            return true, AppendFixChoices(label .. " cast bar is hidden by its cast bar visibility option. You can ask for 'show " .. UnitCommandLabel(unit) .. " cast bar' or open Cast Bar settings.", choices)
        end
        if unitEnabled == false then
            AddFixChoice(choices, unit .. ".enabled", true, "Show " .. label .. " frame")
            return true, AppendFixChoices(label .. " frame is disabled, so its attached cast bar may not be visible. You can ask for 'show " .. UnitCommandLabel(unit) .. " frame' first.", choices)
        end
        if unit == "player" and backend == "BLIZZARD" then
            AddFixChoice(choices, "general.castbarPlayerBackend", "MSUF", "Use the MSUF player cast bar")
            return true, AppendFixChoices("The player cast bar is assigned to Blizzard's cast bar. Ask for 'show player cast bar' to use the MSUF cast bar.", choices)
        end
        return true, label .. " cast bar is enabled in MSUF. If it still is not visible, check Edit Mode position, cast bar text/icon settings, and whether the unit is currently casting."
    end,
})

Registry:RegisterAction({
    key = "diagnose_unit_visibility",
    label = "Check Unit Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "player"
        if not UNIT_LABELS[unit] then return false, "Which unit frame do you want me to check?" end
        return true, UnitFrameDiagnosticText(unit)
    end,
})

Registry:RegisterAction({
    key = "diagnose_group_visibility",
    label = "Check Group Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local scope = args and args.scope or "party"
        if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        return true, GroupFrameDiagnosticText(scope)
    end,
})

Registry:RegisterAction({
    key = "diagnose_aura_visibility",
    label = "Check Aura Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, AuraDiagnosticText(args)
    end,
})

Registry:RegisterAction({
    key = "clear_broken_spec_profile_mappings",
    label = "Clear Broken Spec Profile Links",
    type = "profile",
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function()
        local count = ClearBrokenSpecProfileMappings()
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_SPEC_MAPPING_REPAIR") end
        if M and type(M.Refresh) == "function" then M.Refresh() end
        if count <= 0 then return true, "Spec profile links look clean." end
        return true, "Done. Cleared " .. tostring(count) .. " broken spec profile link" .. (count == 1 and "." or "s.")
    end,
})

Registry:RegisterAction({
    key = "diagnose_profile_status",
    label = "Check Profiles",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ProfileDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_class_power_status",
    label = "Check Class Resources",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ClassPowerDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_gameplay_helpers",
    label = "Check Gameplay Helpers",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, GameplayDiagnosticText(args and args.feature or "all")
    end,
})

Registry:RegisterAction({
    key = "diagnose_dashboard_setup",
    label = "Check Dashboard Setup",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, DashboardSetupDiagnosticText()
    end,
})

local RegisterGuidedSetupActions = A.DiagnosticsRegistry and A.DiagnosticsRegistry.RegisterGuidedSetupActions
if type(RegisterGuidedSetupActions) == "function" then
    RegisterGuidedSetupActions({
        Registry = Registry,
        A = A,
    })
end
