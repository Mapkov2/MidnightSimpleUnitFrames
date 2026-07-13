-- Assistant diagnostics registry: registers read-only checks and safe repair actions.
-- Diagnostics may inspect DB/live state, but mutations must remain explicit snapshot-backed actions.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Diagnostics registry domain.
-- Read-only assistant actions that summarize state for support and self-check workflows.
-- Keep this file observational; repair actions belong in explicit workflows with confirmation.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB or function() return (_G.MSUF_DB and _G.MSUF_DB.bars) or {} end
local GameplayDB = C.GameplayDB or function() return (_G.MSUF_DB and _G.MSUF_DB.gameplay) or {} end
local UnitDB = C.UnitDB
local GroupDB = C.GroupDB
local CASTBAR_KEYS = C.CASTBAR_KEYS
local GetCastbarBackend = C.GetCastbarBackend
local function ActiveProfileName()
    if A and type(A.ActiveProfileName) == "function" then return A.ActiveProfileName() end
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

local function LowOpacity(value)
    value = tonumber(value)
    return value ~= nil and value <= 0.05
end

local function ChoiceValueKey(value)
    local valueType = type(value)
    if valueType == "nil" then return "nil:" end
    if valueType == "boolean" then return "boolean:" .. (value and "1" or "0") end
    if valueType == "number" or valueType == "string" then return valueType .. ":" .. tostring(value) end
    return valueType .. ":" .. tostring(value)
end

local function ChoiceArgsKey(args)
    if type(args) ~= "table" then return "" end
    local keys = {}
    for key in pairs(args) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = key .. "=" .. ChoiceValueKey(args[key])
    end
    return table.concat(parts, "\n")
end

local function HasSettingChoice(choices, setting, value)
    local valueKey = ChoiceValueKey(value)
    for i = 1, #choices do
        local choice = choices[i]
        if choice and choice.setting == setting and ChoiceValueKey(choice.value) == valueKey then
            return true
        end
    end
    return false
end

local function HasActionChoice(choices, action, args)
    local argsKey = ChoiceArgsKey(args)
    for i = 1, #choices do
        local choice = choices[i]
        if choice and choice.action == action and ChoiceArgsKey(choice.args) == argsKey then
            return true
        end
    end
    return false
end

local function AddFixChoice(choices, key, value, label, valueLabel)
    if type(choices) ~= "table" or type(key) ~= "string" or key == "" then return end
    if not (Registry and type(Registry.GetSetting) == "function") then return end
    local setting = Registry:GetSetting(key)
    if not setting or HasSettingChoice(choices, setting, value) then return end
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = label,
        valueLabel = valueLabel,
        diagnosticFix = true,
    }
end

local function AddActionChoice(choices, key, args, label, summary, confirmRequired, diagnosticFix)
    if type(choices) ~= "table" or type(key) ~= "string" or key == "" then return end
    if not (Registry and type(Registry.GetAction) == "function") then return end
    local action = Registry:GetAction(key)
    if not action then return end
    args = type(args) == "table" and args or {}
    if HasActionChoice(choices, action, args) then return end
    choices[#choices + 1] = {
        action = action,
        args = args,
        label = label,
        summary = summary,
        confirmRequired = confirmRequired,
        diagnosticFix = diagnosticFix == true,
    }
end
local function AppendFixChoices(text, choices)
    if type(choices) ~= "table" or #choices == 0 then return text end
    local choiceText
    if A and type(A.SetPendingChoices) == "function" then
        choiceText = A.SetPendingChoices(choices)
    elseif A and type(A._ChoiceTextForTest) == "function" then
        A.pendingChoices = choices
        choiceText = A._ChoiceTextForTest(choices)
    end
    if type(choiceText) == "string" and choiceText ~= "" then
        return tostring(text or "") .. "\n\nSuggested fixes:\n" .. choiceText
    end
    return text
end

local BuildFrameDiagnostics = A.DiagnosticsRegistry and A.DiagnosticsRegistry.BuildFrameDiagnostics
local FrameDiagnostics = type(BuildFrameDiagnostics) == "function" and BuildFrameDiagnostics({
    UNIT_LABELS = UNIT_LABELS,
    UnitDB = UnitDB,
    GroupDB = GroupDB,
    LowOpacity = LowOpacity,
    AddFixChoice = AddFixChoice,
    AppendFixChoices = AppendFixChoices,
}) or nil
local UnitFrameDiagnosticText = FrameDiagnostics and FrameDiagnostics.UnitFrameDiagnosticText
local GroupFrameDiagnosticText = FrameDiagnostics and FrameDiagnostics.GroupFrameDiagnosticText
if type(UnitFrameDiagnosticText) ~= "function" or type(GroupFrameDiagnosticText) ~= "function" then return end

local BuildAuraDiagnostic = A.DiagnosticsRegistry and A.DiagnosticsRegistry.BuildAuraDiagnostic
local AuraDiagnostic = type(BuildAuraDiagnostic) == "function" and BuildAuraDiagnostic({
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    GroupDB = GroupDB,
    AuraModel = C.AuraModel,
    AuraUnitEnabled = C.AuraUnitEnabled,
    AuraLaneShown = C.AuraLaneShown,
    AuraFiltersEnabled = C.AuraFiltersEnabled,
    AuraReadFilter = C.AuraReadFilter,
    GFAuraLaneShown = C.GFAuraLaneShown,
    GFReadAuraValue = C.GFReadAuraValue,
    AddFixChoice = AddFixChoice,
    AddActionChoice = AddActionChoice,
    AppendFixChoices = AppendFixChoices,
}) or nil
local AuraDiagnosticText = AuraDiagnostic and AuraDiagnostic.AuraDiagnosticText
if type(AuraDiagnosticText) ~= "function" then return end

local BuildProfileDiagnostic = A.DiagnosticsRegistry and A.DiagnosticsRegistry.BuildProfileDiagnostic
local ProfileDiagnostic = type(BuildProfileDiagnostic) == "function" and BuildProfileDiagnostic({
    M = M,
    ActiveProfileName = ActiveProfileName,
    AddActionChoice = AddActionChoice,
    AppendFixChoices = AppendFixChoices,
}) or nil
local ClearBrokenSpecProfileMappings = ProfileDiagnostic and ProfileDiagnostic.ClearBrokenSpecProfileMappings
local ProfileDiagnosticText = ProfileDiagnostic and ProfileDiagnostic.ProfileDiagnosticText
if type(ClearBrokenSpecProfileMappings) ~= "function" or type(ProfileDiagnosticText) ~= "function" then return end

local BuildGameplayDiagnostic = A.DiagnosticsRegistry and A.DiagnosticsRegistry.BuildGameplayDiagnostic
local GameplayDiagnostic = type(BuildGameplayDiagnostic) == "function" and BuildGameplayDiagnostic({
    A = A,
    M = M,
    BarsDB = BarsDB,
    GameplayDB = GameplayDB,
    UnitDB = UnitDB,
    AddFixChoice = AddFixChoice,
    AddActionChoice = AddActionChoice,
    AppendFixChoices = AppendFixChoices,
    LowOpacity = LowOpacity,
}) or nil
local ClassPowerDiagnosticText = GameplayDiagnostic and GameplayDiagnostic.ClassPowerDiagnosticText
local GameplayDiagnosticText = GameplayDiagnostic and GameplayDiagnostic.GameplayDiagnosticText
local DashboardSetupDiagnosticText = GameplayDiagnostic and GameplayDiagnostic.DashboardSetupDiagnosticText
if type(ClassPowerDiagnosticText) ~= "function" or type(GameplayDiagnosticText) ~= "function" or type(DashboardSetupDiagnosticText) ~= "function" then return end

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}
A.DiagnosticsRegistry.Actions = {
    A = A,
    M = M,
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    GeneralDB = GeneralDB,
    UnitDB = UnitDB,
    CASTBAR_KEYS = CASTBAR_KEYS,
    GetCastbarBackend = GetCastbarBackend,
    AddFixChoice = AddFixChoice,
    AppendFixChoices = AppendFixChoices,
    UnitFrameDiagnosticText = UnitFrameDiagnosticText,
    GroupFrameDiagnosticText = GroupFrameDiagnosticText,
    AuraDiagnosticText = AuraDiagnosticText,
    ClearBrokenSpecProfileMappings = ClearBrokenSpecProfileMappings,
    ProfileDiagnosticText = ProfileDiagnosticText,
    ClassPowerDiagnosticText = ClassPowerDiagnosticText,
    GameplayDiagnosticText = GameplayDiagnosticText,
    DashboardSetupDiagnosticText = DashboardSetupDiagnosticText,
}
Registry:RegisterTodo("Auras3 remaining advanced work: whitelist-style operations where the UI exposes them beyond filters, blacklists, color controls, and group category blacklists.")
Registry:RegisterTodo("Profiles can keep expanding for spec-profile edge cases as more shared profile tools become available in MSUF.")
Registry:RegisterTodo("Preset support can keep expanding when future MSUF preset buttons become available to the Assistant.")
Registry:RegisterTodo("Diagnostics and guided setup can keep expanding with aura-specific help, deeper branch-specific repair paths, and future factory-reset support exposed by MSUF.")
