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
            { key = "includeNameplateOnly", label = "including nameplate-only buffs" },
            { key = "cancelable", label = "only cancelable buffs" },
            { key = "notCancelable", label = "only non-cancelable buffs" },
            { key = "externalDefensive", label = "only external defensive buffs" },
            { key = "bigDefensive", label = "only big defensive buffs" },
        },
        debuff = {
            { key = "onlyMine", label = "only your debuffs" },
            { key = "raid", label = "only raid debuffs" },
            { key = "raidInCombat", label = "only raid-in-combat debuffs" },
            { key = "includeNameplateOnly", label = "including nameplate-only debuffs" },
            { key = "includeDispellable", label = "only dispellable debuffs" },
            { key = "crowdControl", label = "only crowd-control debuffs" },
            { key = "nonPlayer", label = "only debuffs not caused by players or player pets" },
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

    local function EnabledEntryCount(entries)
        if type(entries) ~= "table" then return 0 end
        local count = 0
        for _, enabled in pairs(entries) do
            if enabled == true then count = count + 1 end
        end
        return count
    end

    local function UnitBlacklistLane(scope, lane)
        local db = _G.MSUF_DB
        local auras = type(db) == "table" and db.auras3 or nil
        local perUnit = type(auras) == "table" and auras.perUnit or nil
        local runtimeUnit = scope == "boss" and "boss1" or scope
        local unit = type(perUnit) == "table" and perUnit[runtimeUnit] or nil
        local root = type(unit) == "table" and unit.blacklist or nil
        if type(root) ~= "table" then return nil end
        local laneRoot = root[lane == "debuff" and "debuffs" or "buffs"]
        return type(laneRoot) == "table" and laneRoot or root
    end

    local function GroupBlacklistLane(scope, lane)
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return nil end
        local key = scope == "party" and "gf_party" or (scope == "mythicraid" and "gf_mythicraid" or "gf_raid")
        local conf = db[key]
        local auras = type(conf) == "table" and conf.auras or nil
        local group = type(auras) == "table" and auras[lane] or nil
        return type(group) == "table" and group or nil
    end

    local function AddUnitAuraBlacklistDiagnostics(scope, label, lanes, issues, choices)
        lanes = type(lanes) == "table" and lanes or { "buff", "debuff" }
        for i = 1, #lanes do
            local lane = lanes[i]
            local laneLabel = AuraLaneLabel(lane)
            local blacklist = UnitBlacklistLane(scope, lane)
            local hidePermanentKey = "auras3." .. scope .. "." .. lane .. ".blacklist.hidePermanent"
            if type(blacklist) == "table" and blacklist.hidePermanent == true then
                issues[#issues + 1] = label .. " " .. laneLabel .. " hide permanent/no-duration auras. This rule still applies when the normal filter gate is off."
                AddFixChoice(choices, hidePermanentKey, false, "Show permanent " .. label .. " " .. laneLabel)
            end
            local count = EnabledEntryCount(type(blacklist) == "table" and blacklist.spells or nil)
            if count > 0 then
                issues[#issues + 1] = label .. " " .. laneLabel .. " have " .. tostring(count)
                    .. " live exact-SpellID " .. (count == 1 and "entry" or "entries")
                    .. ", used where Blizzard permits identity filtering. Ask to list that blacklist if one specific aura is missing."
            end
        end
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

        local group = GroupBlacklistLane(scope, lane)
        local blacklist = type(group) == "table" and group.blacklist or nil
        local hidePermanentKey = "gf_" .. scope .. ".auras." .. lane .. ".blacklist.hidePermanent"
        if (type(group) == "table" and group.hidePermanent == true)
            or (type(blacklist) == "table" and blacklist.hidePermanent == true) then
            issues[#issues + 1] = label .. " " .. laneLabel .. " hide permanent/no-duration auras."
            AddFixChoice(choices, hidePermanentKey, false, "Show permanent " .. label .. " " .. laneLabel)
        end

        local spells = type(blacklist) == "table" and blacklist.spells or nil
        if type(spells) ~= "table" and type(group) == "table" then spells = group.blacklistSpells end
        local spellCount = EnabledEntryCount(spells)
        if spellCount > 0 then
            issues[#issues + 1] = label .. " " .. laneLabel .. " have " .. tostring(spellCount)
                .. " live exact-SpellID " .. (spellCount == 1 and "entry" or "entries")
                .. ", used where Blizzard permits identity filtering. Ask to list that blacklist if one specific aura is missing."
        end
        local categoryCount = EnabledEntryCount(type(group) == "table" and group.blacklistCats or nil)
        if categoryCount > 0 then
            issues[#issues + 1] = label .. " " .. laneLabel .. " have " .. tostring(categoryCount)
                .. " live hidden aura " .. (categoryCount == 1 and "category" or "categories")
                .. ". Category lists expand to native exact-SpellID exclusions with the same Blizzard restrictions."
        end
    end

    return {
        AddUnitAuraFilterDiagnostics = AddUnitAuraFilterDiagnostics,
        AddUnitAuraBlacklistDiagnostics = AddUnitAuraBlacklistDiagnostics,
        AddGroupAuraFilterDiagnostics = AddGroupAuraFilterDiagnostics,
    }
end
