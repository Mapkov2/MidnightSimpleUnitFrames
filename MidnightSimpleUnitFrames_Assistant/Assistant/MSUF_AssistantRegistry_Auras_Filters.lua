-- Assistant Auras filter registry shard.
-- Loaded before MSUF_AssistantRegistry_Auras_StyleFilters.lua; keeps filter settings separate from visual style settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterFilterSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_LANES = ctx.AURA_LANES or {}
    local AURA_FILTER_BOOLEAN_SPECS = ctx.AURA_FILTER_BOOLEAN_SPECS or {}
    local AURA_EXCLUSIVE_FILTER_VALUES = ctx.AURA_EXCLUSIVE_FILTER_VALUES or {}
    local AURA_EXCLUSIVE_FILTER_ALIASES = ctx.AURA_EXCLUSIVE_FILTER_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local AuraScopeLabel = ctx.AuraScopeLabel
    local AuraFiltersEnabled = ctx.AuraFiltersEnabled
    local AuraSetFiltersEnabled = ctx.AuraSetFiltersEnabled
    local AuraReadFilter = ctx.AuraReadFilter
    local AuraWriteFilter = ctx.AuraWriteFilter
    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" then return end
    local scopePage = "uf_" .. tostring(scope)

    local function AddAlias(out, value)
        if type(value) == "string" and value ~= "" then out[#out + 1] = value end
    end

    local function AddNoTimerAliases(out, settingScope, settingLane)
        local scopeLabel = tostring(AuraScopeLabel(settingScope) or settingScope):lower()
        local lanePlural = settingLane == "buff" and "buffs" or "debuffs"
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " with no timer")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " without a timer")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " without timers")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " that have no timer")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " with no duration")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " without a duration")
        AddAlias(out, scopeLabel .. " " .. lanePlural .. " without duration")
        AddAlias(out, scopeLabel .. " permanent " .. lanePlural)
        AddAlias(out, "no timer " .. lanePlural .. " on " .. scopeLabel)
        AddAlias(out, "no duration " .. lanePlural .. " on " .. scopeLabel)
        AddAlias(out, "hide permanent " .. scopeLabel .. " " .. lanePlural)
        AddAlias(out, scopeLabel .. " frame " .. lanePlural .. " without timers")
    end

    local function FallbackHidePermanent(settingScope, settingLane, create, value)
        if type(EnsureAuraFallbackDB) ~= "function" then return false end
        local auras = EnsureAuraFallbackDB()
        local unit = tostring(settingScope)
        local pu = type(auras.perUnit) == "table" and auras.perUnit[unit] or nil
        if create and type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        if type(pu) ~= "table" then return false end
        if create and type(pu.blacklist) ~= "table" then pu.blacklist = {} end
        local blacklist = pu.blacklist
        if type(blacklist) ~= "table" then return false end
        local laneKey = settingLane == "buff" and "buffs" or "debuffs"
        if create and type(blacklist[laneKey]) ~= "table" then blacklist[laneKey] = {} end
        local laneList = blacklist[laneKey]
        if type(laneList) ~= "table" then return false end
        if create then laneList.hidePermanent = value == true end
        return laneList.hidePermanent == true
    end

    local aliases = {}

    for i = 1, #AURA_FILTER_BOOLEAN_SPECS do
        local spec = AURA_FILTER_BOOLEAN_SPECS[i]
        aliases = {}
        for j = 1, #spec.words do AddAliasesForAuraScope(aliases, scope, spec.words[j]) end
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. spec.lane .. ".filter." .. spec.key,
            label = AuraScopeLabel(scope) .. " " .. spec.label,
            category = AuraScopeLabel(scope) .. " / Aura Filters",
            page = scopePage,
            description = (spec.key == "bigDefensive"
                    and "MSUF curated major-defensive Spell-ID filter on friendly frames, with Blizzard's BIG_DEFENSIVE fallback where exact identity filtering is restricted, for "
                    or (spec.key == "includeNameplateOnly"
                        and "Blizzard inclusion modifier that broadens the active filter with nameplate-only auras for "
                        or "Blizzard classification filter for "))
                .. tostring(AuraScopeLabel(scope)) .. " "
                .. (spec.lane == "buff" and "Buffs" or "Debuffs")
                .. ". It is evaluated only while Filters Enabled is on; it does not show or hide the aura lane.",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. spec.lane .. "Filter" .. spec.key,
            type = "boolean",
            aliases = aliases,
            get = function() return AuraReadFilter(scope, spec.lane, spec.key, false) == true end,
            set = function(value)
                value = value and true or false
                if value == true and type(spec.conflicts) == "table" then
                    for k = 1, #spec.conflicts do
                        AuraWriteFilter(scope, spec.lane, spec.conflicts[k], false)
                    end
                end
                if value == true and spec.classification == true then
                    AuraWriteFilter(scope, spec.lane, "exclusive", "none")
                end
                AuraWriteFilter(scope, spec.lane, spec.key, value)
            end,
            apply = function() ApplyAura(scope, "MSUF_ASSISTANT_AURA_FILTER") end,
            combatSafe = false,
        })
    end

    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local settingScope, settingLane = scope, lane
        aliases = {}
        AddAuraLaneAliases(aliases, settingScope, settingLane, "filter gate")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "enable filters")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "blizzard aura filters")
        Registry:RegisterSetting({
            key = "auras3." .. settingScope .. "." .. settingLane .. ".filtersEnabled",
            label = AuraScopeLabel(settingScope) .. " " .. laneInfo.label .. " Filters Enabled",
            category = AuraScopeLabel(settingScope) .. " / Aura Filters",
            page = scopePage,
            description = "Master gate for this exact " .. laneInfo.label
                .. " lane's classification filters. It does not show or hide the lane, and Hide Permanent remains active independently.",
            unit = settingScope,
            frameType = "aura",
            attribute = "aura" .. settingLane .. "FiltersEnabled",
            type = "boolean",
            aliases = aliases,
            get = function() return AuraFiltersEnabled(settingScope, settingLane) end,
            set = function(value) AuraSetFiltersEnabled(settingScope, settingLane, value) end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_FILTER_ENABLE") end,
            combatSafe = false,
        })
        local values = AURA_EXCLUSIVE_FILTER_VALUES[settingLane] or { "none" }
        if #values > 1 then
        local defaultValue = values[1] or "none"
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        local valueAliases = {}
        for alias, value in pairs(AURA_EXCLUSIVE_FILTER_ALIASES) do
            if allowed[value] then valueAliases[alias] = value end
        end
        aliases = {}
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive filter")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive")
        Registry:RegisterSetting({
            key = "auras3." .. settingScope .. "." .. settingLane .. ".filter.exclusive",
            label = AuraScopeLabel(settingScope) .. " " .. laneInfo.label .. " Exclusive Filter",
            category = AuraScopeLabel(settingScope) .. " / Aura Filters",
            page = scopePage,
            description = "Chooses the exclusive Blizzard token filter for " .. tostring(AuraScopeLabel(settingScope))
                .. " " .. laneInfo.plural .. ". It is evaluated only while Filters Enabled is on and does not control lane visibility.",
            unit = settingScope,
            frameType = "aura",
            attribute = "aura" .. settingLane .. "FilterExclusive",
            type = "enum",
            aliases = aliases,
            values = values,
            valueAliases = valueAliases,
            get = function()
                local value = tostring(AuraReadFilter(settingScope, settingLane, "exclusive", defaultValue) or defaultValue)
                return allowed[value] and value or defaultValue
            end,
            set = function(value)
                value = tostring(value or defaultValue)
                AuraWriteFilter(settingScope, settingLane, "exclusive", allowed[value] and value or defaultValue)
            end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_FILTER_EXCLUSIVE") end,
            combatSafe = false,
        })
        end

        if type(AuraModel) == "function" then
            local hideAliases = {}
            AddAuraLaneAliases(hideAliases, settingScope, settingLane, "hide permanent auras")
            AddAuraLaneAliases(hideAliases, settingScope, settingLane, "hide permanent")
            AddNoTimerAliases(hideAliases, settingScope, settingLane)
            Registry:RegisterSetting({
                key = "auras3." .. settingScope .. "." .. settingLane .. ".blacklist.hidePermanent",
                label = AuraScopeLabel(settingScope) .. " " .. laneInfo.label .. " Hide Permanent Auras",
                category = AuraScopeLabel(settingScope) .. " / Aura Filters",
                page = scopePage,
                description = "Hides " .. tostring(AuraScopeLabel(settingScope)) .. " " .. laneInfo.plural
                    .. " that have no finite duration (also called permanent or no-timer auras). This rule remains active when Filters Enabled is off and does not hide the entire "
                    .. laneInfo.label:lower() .. " lane.",
                unit = settingScope,
                frameType = "aura",
                attribute = "aura" .. settingLane .. "BlacklistHidePermanent",
                type = "boolean",
                aliases = hideAliases,
                get = function()
                    local Model = AuraModel()
                    if Model and type(Model.ReadBlacklistHidePermanent) == "function" then
                        return Model.ReadBlacklistHidePermanent(settingScope, settingLane) == true
                    end
                    return FallbackHidePermanent(settingScope, settingLane, false)
                end,
                set = function(value)
                    local Model = AuraModel()
                    if Model and type(Model.WriteBlacklistHidePermanent) == "function" then
                        Model.WriteBlacklistHidePermanent(settingScope, settingLane, value == true)
                    end
                    FallbackHidePermanent(settingScope, settingLane, true, value)
                end,
                apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_HIDE_PERMANENT") end,
                combatSafe = false,
            })
        end
    end
end
