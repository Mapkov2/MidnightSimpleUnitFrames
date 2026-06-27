-- Assistant aura diagnostic filter and blacklist helpers.
-- Keeps the main aura diagnostic builder focused on flow and response text.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildAuraDiagnosticFilterHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraFiltersEnabled = ctx.AuraFiltersEnabled
    local AuraReadFilter = ctx.AuraReadFilter
    local GFReadAuraValue = ctx.GFReadAuraValue
    local AddFixChoice = ctx.AddFixChoice
    local AuraLaneLabel = ctx.AuraLaneLabel
    local SafeSettingValue = ctx.SafeSettingValue

    if type(AddFixChoice) ~= "function" then return nil end
    if type(AuraLaneLabel) ~= "function" or type(SafeSettingValue) ~= "function" then return nil end

    local function FilterValueLabel(value)
        local parser = A and A.Parser
        if parser and type(parser.ValueDisplay) == "function" then
            return parser.ValueDisplay({ type = "enum" }, value)
        end
        value = tostring(value or "")
        if value == "" then return "blank" end
        return value:gsub("|", " "):gsub("_", " "):lower()
    end

    local UNIT_AURA_FILTER_WARNINGS = {
        buff = {
            { key = "onlyMine", label = "only your buffs" },
            { key = "raid", label = "only raid buffs" },
            { key = "raidInCombat", label = "only raid-in-combat buffs" },
            { key = "cancelable", label = "only cancelable buffs" },
            { key = "notCancelable", label = "only non-cancelable buffs" },
            { key = "externalDefensive", label = "only external defensive buffs" },
            { key = "bigDefensive", label = "only big defensive buffs" },
        },
        debuff = {
            { key = "onlyMine", label = "only your debuffs" },
            { key = "raid", label = "only raid debuffs" },
            { key = "raidInCombat", label = "only raid-in-combat debuffs" },
            { key = "includeDispellable", label = "only dispellable debuffs" },
            { key = "crowdControl", label = "only crowd-control debuffs" },
        },
    }

    local function AddUnitAuraFilterDiagnostics(scope, label, lane, issues, choices)
        local filtersOn = true
        if AuraFiltersEnabled then
            if AuraFiltersEnabled(scope) == false then filtersOn = false end
        end
        if filtersOn == false then return end

        local laneLabel = AuraLaneLabel(lane)
        local exclusive
        if AuraReadFilter then
            exclusive = AuraReadFilter(scope, lane, "exclusive", "none")
        end
        if exclusive == nil then exclusive = SafeSettingValue("auras3." .. scope .. "." .. lane .. ".filter.exclusive") end
        exclusive = tostring(exclusive or "none")
        if exclusive ~= "none" and exclusive ~= "" then
            issues[#issues + 1] = label .. " " .. laneLabel .. " exclusive filter is set to " .. FilterValueLabel(exclusive) .. ", which can hide normal auras."
            AddFixChoice(choices, "auras3." .. scope .. "." .. lane .. ".filter.exclusive", "none", "Set " .. label .. " " .. laneLabel .. " exclusive filter to none")
        end

        local specs = UNIT_AURA_FILTER_WARNINGS[lane] or {}
        for i = 1, #specs do
            local spec = specs[i]
            local key = "auras3." .. scope .. "." .. lane .. ".filter." .. spec.key
            if SafeSettingValue(key) == true then
                issues[#issues + 1] = label .. " " .. laneLabel .. " filter is limited to " .. spec.label .. "."
                AddFixChoice(choices, key, false, "Turn off " .. label .. " " .. laneLabel .. " " .. spec.label .. " filter")
            end
        end
    end

    local function AddUnitAuraBlacklistDiagnostics(scope, label, issues, choices)
        -- 12.1 native AuraContainers currently accept Blizzard filter strings,
        -- not addon SpellID whitelist/blacklist predicates. Keep legacy profile
        -- data out of diagnostics so it is not presented as an active cause.
    end

    local function GroupAuraDefaultMax(lane)
        return lane == "buff" and 6 or 6
    end

    local function AddGroupAuraFilterDiagnostics(scope, label, lane, issues, choices)
        local laneLabel = AuraLaneLabel(lane)
        local maxKey = "gf_" .. scope .. ".auras." .. lane .. ".max"
        local maxValue = SafeSettingValue(maxKey)
        if tonumber(maxValue) ~= nil and tonumber(maxValue) <= 0 then
            issues[#issues + 1] = label .. " " .. laneLabel .. " max icon count is zero."
            AddFixChoice(choices, maxKey, GroupAuraDefaultMax(lane), "Set " .. label .. " " .. laneLabel .. " max icons to " .. tostring(GroupAuraDefaultMax(lane)))
        end

        local sizeKey = "gf_" .. scope .. ".auras." .. lane .. ".size"
        local sizeValue = SafeSettingValue(sizeKey)
        if tonumber(sizeValue) ~= nil and tonumber(sizeValue) < 8 then
            local defaultSize = lane == "buff" and 22 or 20
            issues[#issues + 1] = label .. " " .. laneLabel .. " icon size is extremely small."
            AddFixChoice(choices, sizeKey, defaultSize, "Set " .. label .. " " .. laneLabel .. " icon size to " .. tostring(defaultSize))
        end

        local tokenKey = "gf_" .. scope .. ".auras." .. lane .. ".filterToken"
        local token = SafeSettingValue(tokenKey)
        token = tostring(token or "")
        if token ~= "" and token ~= "ALL" then
            issues[#issues + 1] = label .. " " .. laneLabel .. " filter is set to " .. FilterValueLabel(token) .. ", so normal auras outside that filter may be hidden."
            AddFixChoice(choices, tokenKey, "ALL", "Show all " .. label .. " " .. laneLabel)
        elseif GFReadAuraValue then
            local raw = GFReadAuraValue(scope, lane, "filterToken", nil)
            if raw ~= nil and tostring(raw) ~= "ALL" then
                issues[#issues + 1] = label .. " " .. laneLabel .. " filter is set to " .. FilterValueLabel(raw) .. ", so normal auras outside that filter may be hidden."
                AddFixChoice(choices, tokenKey, "ALL", "Show all " .. label .. " " .. laneLabel)
            end
        end

        -- Group category blacklists are legacy read-only data in the native
        -- container path and cannot hide auras without addon aura scans.
    end

    return {
        AddUnitAuraFilterDiagnostics = AddUnitAuraFilterDiagnostics,
        AddUnitAuraBlacklistDiagnostics = AddUnitAuraBlacklistDiagnostics,
        AddGroupAuraFilterDiagnostics = AddGroupAuraFilterDiagnostics,
    }
end
