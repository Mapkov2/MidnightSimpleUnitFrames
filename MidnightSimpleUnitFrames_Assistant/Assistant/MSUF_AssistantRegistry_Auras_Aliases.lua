-- Assistant Auras alias helpers.
-- Builds phrase helpers used by unit/shared/style aura registry splits.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildAliasHelpers(ctx)
    if type(ctx) ~= "table" then return {} end

    local Assistant = ctx.A or A
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UNIT_ALIASES = ctx.UNIT_ALIASES or {}
    local AURA_SCOPE_ALIASES = ctx.AURA_SCOPE_ALIASES or {}
    local AURA_EDIT_SCOPE_ALIASES = ctx.AURA_EDIT_SCOPE_ALIASES or {}
    local AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS or {}
    local MAX_SETTING_ALIASES = tonumber(A.RegistryCore and A.RegistryCore.MAX_SETTING_ALIASES) or 32

    local function AppendAlias(out, value)
        if #out >= MAX_SETTING_ALIASES then return false end
        out[#out + 1] = value
        return #out < MAX_SETTING_ALIASES
    end

    local function AuraScopeLabel(scope)
        if scope == "shared" then return "Shared" end
        return UNIT_LABELS[scope] or tostring(scope or "")
    end

    local function AuraScopeFromArg(value)
        value = tostring(value or "player"):lower():gsub("%s+", "")
        return AURA_EDIT_SCOPE_ALIASES[value] or value
    end

    local function AddAliasesForAuraScope(out, scope, noun, nounDE)
        if #out >= MAX_SETTING_ALIASES then return false end
        local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            if not AppendAlias(out, s .. " " .. noun) then return false end
            if not AppendAlias(out, noun .. " " .. s) then return false end
            if not AppendAlias(out, s .. " aura " .. noun) then return false end
            if not AppendAlias(out, s .. " auras " .. noun) then return false end
            if nounDE then
                if not AppendAlias(out, s .. " " .. nounDE) then return false end
                if not AppendAlias(out, nounDE .. " " .. s) then return false end
            end
        end
        return true
    end

    local function AddAuraLaneAliases(out, scope, lane, noun, nounDE)
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        if not AddAliasesForAuraScope(out, scope, laneWord .. " " .. noun, nounDE and (laneWord .. " " .. nounDE) or nil) then return false end
        if not AddAliasesForAuraScope(out, scope, lanePlural .. " " .. noun, nounDE and (lanePlural .. " " .. nounDE) or nil) then return false end
        if not AddAliasesForAuraScope(out, scope, "aura " .. laneWord .. " " .. noun) then return false end
        return AddAliasesForAuraScope(out, scope, "aura " .. lanePlural .. " " .. noun)
    end

    local function AddAuraLaneRelativeSizeAliases(out, scope, lane)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            if not AddAuraLaneAliases(out, scope, lane, AURA_RELATIVE_SIZE_NOUNS[i]) then return false end
        end
        return true
    end

    Assistant._AssistantAddAuraAllLaneAliases = Assistant._AssistantAddAuraAllLaneAliases or function(out, scope, noun)
        if #out >= MAX_SETTING_ALIASES then return false end
        local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            if not AppendAlias(out, s .. " aura " .. noun) then return false end
            if not AppendAlias(out, s .. " auras " .. noun) then return false end
            if not AppendAlias(out, "aura " .. noun .. " " .. s) then return false end
            if not AppendAlias(out, "auras " .. noun .. " " .. s) then return false end
        end
        return true
    end

    Assistant._AssistantAddAuraAllLaneNouns = Assistant._AssistantAddAuraAllLaneNouns or function(out, scope, nouns)
        for i = 1, #(nouns or {}) do
            if not Assistant._AssistantAddAuraAllLaneAliases(out, scope, nouns[i]) then return false end
        end
        return true
    end

    Assistant._AssistantAddAuraAllLaneRelativeSizeAliases = Assistant._AssistantAddAuraAllLaneRelativeSizeAliases or function(out, scope)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            if not Assistant._AssistantAddAuraAllLaneAliases(out, scope, AURA_RELATIVE_SIZE_NOUNS[i]) then return false end
        end
        return true
    end

    Assistant._AssistantAddAllAuraNounAliases = Assistant._AssistantAddAllAuraNounAliases or function(out, lane, prefix, noun)
        if #out >= MAX_SETTING_ALIASES then return false end
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        if not AppendAlias(out, prefix .. " aura " .. noun) then return false end
        if not AppendAlias(out, prefix .. " auras " .. noun) then return false end
        if not AppendAlias(out, prefix .. " " .. lanePlural .. " " .. noun) then return false end
        if prefix == "all group" then
            local groupNouns = { "group", "group frame", "group frames" }
            for i = 1, #groupNouns do
                local groupNoun = groupNouns[i]
                if not AppendAlias(out, groupNoun .. " aura " .. noun) then return false end
                if not AppendAlias(out, groupNoun .. " auras " .. noun) then return false end
                if not AppendAlias(out, groupNoun .. " " .. laneWord .. " " .. noun) then return false end
                if not AppendAlias(out, groupNoun .. " " .. lanePlural .. " " .. noun) then return false end
                if not AppendAlias(out, noun .. " " .. groupNoun .. " aura") then return false end
                if not AppendAlias(out, noun .. " " .. groupNoun .. " auras") then return false end
                if not AppendAlias(out, noun .. " " .. groupNoun .. " " .. laneWord) then return false end
                if not AppendAlias(out, noun .. " " .. groupNoun .. " " .. lanePlural) then return false end
            end
        end
        return true
    end

    Assistant._AssistantAddAllAuraRelativeSizeAliases = Assistant._AssistantAddAllAuraRelativeSizeAliases or function(out, lane, prefix)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            if not Assistant._AssistantAddAllAuraNounAliases(out, lane, prefix, AURA_RELATIVE_SIZE_NOUNS[i]) then return false end
        end
        return true
    end

    Assistant._AssistantAddAllAuraNouns = Assistant._AssistantAddAllAuraNouns or function(out, lane, prefix, nouns)
        for i = 1, #(nouns or {}) do
            if not Assistant._AssistantAddAllAuraNounAliases(out, lane, prefix, nouns[i]) then return false end
        end
        return true
    end

    return {
        AuraScopeLabel = AuraScopeLabel,
        AuraScopeFromArg = AuraScopeFromArg,
        AddAliasesForAuraScope = AddAliasesForAuraScope,
        AddAuraLaneAliases = AddAuraLaneAliases,
        AddAuraLaneRelativeSizeAliases = AddAuraLaneRelativeSizeAliases,
    }
end
