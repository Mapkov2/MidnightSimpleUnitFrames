-- Assistant aura visibility diagnostic helpers.
-- Builds the Aura diagnostic function consumed by the diagnostics registry shell.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildAuraDiagnostic(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GroupDB = ctx.GroupDB
    local AuraModel = ctx.AuraModel
    local AuraUnitEnabled = ctx.AuraUnitEnabled
    local AuraLaneShown = ctx.AuraLaneShown
    local AuraFiltersEnabled = ctx.AuraFiltersEnabled
    local AuraReadFilter = ctx.AuraReadFilter
    local GFAuraLaneShown = ctx.GFAuraLaneShown
    local GFReadAuraValue = ctx.GFReadAuraValue
    local AddFixChoice = ctx.AddFixChoice
    local AddActionChoice = ctx.AddActionChoice
    local AppendFixChoices = ctx.AppendFixChoices

    if not (Registry and type(Registry.GetSetting) == "function") then return nil end
    if type(GroupDB) ~= "function" or type(AddFixChoice) ~= "function" then return nil end
    if type(AddActionChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end

    local function AuraLaneLabel(lane)
        return lane == "debuff" and "Debuffs" or "Buffs"
    end

    local function ScopeLabel(scope)
        if A and type(A.DisplayGroupLabel) == "function" and (scope == "party" or scope == "raid" or scope == "mythicraid") then return A.DisplayGroupLabel(scope) end
        if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(scope) end
        local label = UNIT_LABELS[scope]
        if label ~= nil and tostring(label) ~= "" then return tostring(label) end
        if scope == "mythicraid" then return "Mythic Raid" end
        if scope == "targettarget" then return "Target of Target" end
        if scope == "focustarget" then return "Focus Target" end
        return tostring(scope or "")
    end

    local function AuraDiagnosticLanes(kind)
        if kind == "buff" or kind == "buffs" then return { "buff" } end
        if kind == "debuff" or kind == "debuffs" then return { "debuff" } end
        return { "buff", "debuff" }
    end

    local function SafeSettingValue(key)
        local setting = Registry:GetSetting(key)
        if not (setting and type(setting.get) == "function") then return nil end
        return setting.get()
    end

    local BuildAuraDiagnosticFilterHelpers = A.DiagnosticsRegistry and A.DiagnosticsRegistry.BuildAuraDiagnosticFilterHelpers
    if type(BuildAuraDiagnosticFilterHelpers) ~= "function" then return nil end
    local FilterHelpers = BuildAuraDiagnosticFilterHelpers({
        AuraModel = AuraModel,
        AuraFiltersEnabled = AuraFiltersEnabled,
        AuraReadFilter = AuraReadFilter,
        GFReadAuraValue = GFReadAuraValue,
        AddFixChoice = AddFixChoice,
        AddActionChoice = AddActionChoice,
        AuraLaneLabel = AuraLaneLabel,
        SafeSettingValue = SafeSettingValue,
    })
    if type(FilterHelpers) ~= "table" then return nil end

    local AddUnitAuraFilterDiagnostics = FilterHelpers.AddUnitAuraFilterDiagnostics
    local AddUnitAuraBlacklistDiagnostics = FilterHelpers.AddUnitAuraBlacklistDiagnostics
    local AddGroupAuraFilterDiagnostics = FilterHelpers.AddGroupAuraFilterDiagnostics
    if type(AddUnitAuraFilterDiagnostics) ~= "function" then return nil end
    if type(AddUnitAuraBlacklistDiagnostics) ~= "function" then return nil end
    if type(AddGroupAuraFilterDiagnostics) ~= "function" then return nil end

    local function AuraDiagnosticText(args)
        args = type(args) == "table" and args or {}
        local scope = tostring(args.scope or "target")
        local lanes = AuraDiagnosticLanes(args.lane)
        local issues = {}
        local choices = {}

        if scope == "party" or scope == "raid" or scope == "mythicraid" then
            local conf = GroupDB(scope)
            local label = ScopeLabel(scope)
            if conf.enabled ~= true then
                issues[#issues + 1] = label .. " group frames are disabled, so their auras cannot be visible."
                AddFixChoice(choices, "gf_" .. scope .. ".enabled", true, "Show " .. label .. " group frames")
            end
            if scope == "party" and conf.showSolo ~= true then
                issues[#issues + 1] = "Party frames hide while solo unless Show while Solo is enabled."
                AddFixChoice(choices, "gf_party.showSolo", true, "Show Party frames while solo")
            end
            for i = 1, #lanes do
                local lane = lanes[i]
                if GFAuraLaneShown and not GFAuraLaneShown(scope, lane) then
                    issues[#issues + 1] = label .. " " .. AuraLaneLabel(lane) .. " are disabled or still owned by Blizzard aura rendering."
                    AddFixChoice(choices, "gf_" .. scope .. ".auras." .. lane .. ".enabled", true, "Show " .. label .. " " .. AuraLaneLabel(lane))
                end
                AddGroupAuraFilterDiagnostics(scope, label, lane, issues, choices)
            end
            if #issues == 0 then
                return label .. " group aura check: the requested aura lanes are enabled, max icon counts are above zero, and native filter settings look OK. If they are still missing, check the active group context and whether the aura exists on party or raid members."
            end
            return AppendFixChoices(label .. " group aura check:\n" .. table.concat(issues, "\n"), choices)
        end

        if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then scope = "target" end
        local label = ScopeLabel(scope)
        local root = Registry:GetSetting("auras3.enabled")
        if root and type(root.get) == "function" and root.get() == false then
            issues[#issues + 1] = "Unit auras are disabled globally."
            AddFixChoice(choices, "auras3.enabled", true, "Turn on unit auras")
        end
        if AuraUnitEnabled and not AuraUnitEnabled(scope) then
            issues[#issues + 1] = label .. " unit auras are disabled."
            for i = 1, #lanes do
                AddFixChoice(choices, "auras3." .. scope .. "." .. lanes[i] .. ".visible", true, "Show " .. label .. " " .. AuraLaneLabel(lanes[i]))
            end
        end
        for i = 1, #lanes do
            local lane = lanes[i]
            if AuraLaneShown and not AuraLaneShown(scope, lane) then
                issues[#issues + 1] = label .. " " .. AuraLaneLabel(lane) .. " are hidden or their max icon count is zero."
                AddFixChoice(choices, "auras3." .. scope .. "." .. lane .. ".visible", true, "Show " .. label .. " " .. AuraLaneLabel(lane))
            end
            AddUnitAuraFilterDiagnostics(scope, label, lane, issues, choices)
        end
        AddUnitAuraBlacklistDiagnostics(scope, label, lanes, issues, choices)
        if #issues == 0 then
            return label .. " aura check: the requested aura lanes are enabled, and native filter settings look OK. If a specific aura is still missing, check whether that aura is currently active and allowed by Blizzard or unit ownership rules."
        end
        return AppendFixChoices(label .. " aura check:\n" .. table.concat(issues, "\n"), choices)
    end

    return {
        AuraDiagnosticText = AuraDiagnosticText,
    }
end
