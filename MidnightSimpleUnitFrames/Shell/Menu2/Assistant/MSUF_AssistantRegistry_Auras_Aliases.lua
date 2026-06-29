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

    local function AuraScopeLabel(scope)
        if scope == "shared" then return "Shared" end
        return UNIT_LABELS[scope] or tostring(scope or "")
    end

    local function AuraScopeFromArg(value)
        value = tostring(value or "shared"):lower():gsub("%s+", "")
        return AURA_EDIT_SCOPE_ALIASES[value] or value
    end

    local function AddAliasesForAuraScope(out, scope, noun, nounDE)
        local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            out[#out + 1] = s .. " " .. noun
            out[#out + 1] = noun .. " " .. s
            out[#out + 1] = s .. " aura " .. noun
            out[#out + 1] = s .. " auras " .. noun
            if nounDE then
                out[#out + 1] = s .. " " .. nounDE
                out[#out + 1] = nounDE .. " " .. s
            end
        end
    end

    local function AddAuraLaneAliases(out, scope, lane, noun, nounDE)
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        AddAliasesForAuraScope(out, scope, laneWord .. " " .. noun, nounDE and (laneWord .. " " .. nounDE) or nil)
        AddAliasesForAuraScope(out, scope, lanePlural .. " " .. noun, nounDE and (lanePlural .. " " .. nounDE) or nil)
        AddAliasesForAuraScope(out, scope, "aura " .. laneWord .. " " .. noun)
        AddAliasesForAuraScope(out, scope, "aura " .. lanePlural .. " " .. noun)
    end

    local function AddAuraLaneRelativeSizeAliases(out, scope, lane)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            AddAuraLaneAliases(out, scope, lane, AURA_RELATIVE_SIZE_NOUNS[i])
        end
    end

    Assistant._AssistantAddAuraAllLaneAliases = Assistant._AssistantAddAuraAllLaneAliases or function(out, scope, noun)
        local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            out[#out + 1] = s .. " aura " .. noun
            out[#out + 1] = s .. " auras " .. noun
            out[#out + 1] = "aura " .. noun .. " " .. s
            out[#out + 1] = "auras " .. noun .. " " .. s
        end
    end

    Assistant._AssistantAddAuraAllLaneNouns = Assistant._AssistantAddAuraAllLaneNouns or function(out, scope, nouns)
        for i = 1, #(nouns or {}) do
            Assistant._AssistantAddAuraAllLaneAliases(out, scope, nouns[i])
        end
    end

    Assistant._AssistantAddAuraAllLaneRelativeSizeAliases = Assistant._AssistantAddAuraAllLaneRelativeSizeAliases or function(out, scope)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            Assistant._AssistantAddAuraAllLaneAliases(out, scope, AURA_RELATIVE_SIZE_NOUNS[i])
        end
    end

    Assistant._AssistantAddAllAuraNounAliases = Assistant._AssistantAddAllAuraNounAliases or function(out, lane, prefix, noun)
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        out[#out + 1] = prefix .. " aura " .. noun
        out[#out + 1] = prefix .. " auras " .. noun
        out[#out + 1] = prefix .. " " .. lanePlural .. " " .. noun
        if prefix == "all group" then
            local groupNouns = { "group", "group frame", "group frames" }
            for i = 1, #groupNouns do
                local groupNoun = groupNouns[i]
                out[#out + 1] = groupNoun .. " aura " .. noun
                out[#out + 1] = groupNoun .. " auras " .. noun
                out[#out + 1] = groupNoun .. " " .. laneWord .. " " .. noun
                out[#out + 1] = groupNoun .. " " .. lanePlural .. " " .. noun
                out[#out + 1] = noun .. " " .. groupNoun .. " aura"
                out[#out + 1] = noun .. " " .. groupNoun .. " auras"
                out[#out + 1] = noun .. " " .. groupNoun .. " " .. laneWord
                out[#out + 1] = noun .. " " .. groupNoun .. " " .. lanePlural
            end
        end
    end

    Assistant._AssistantAddAllAuraRelativeSizeAliases = Assistant._AssistantAddAllAuraRelativeSizeAliases or function(out, lane, prefix)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            Assistant._AssistantAddAllAuraNounAliases(out, lane, prefix, AURA_RELATIVE_SIZE_NOUNS[i])
        end
    end

    Assistant._AssistantAddAllAuraNouns = Assistant._AssistantAddAllAuraNouns or function(out, lane, prefix, nouns)
        for i = 1, #(nouns or {}) do
            Assistant._AssistantAddAllAuraNounAliases(out, lane, prefix, nouns[i])
        end
    end

    return {
        AuraScopeLabel = AuraScopeLabel,
        AuraScopeFromArg = AuraScopeFromArg,
        AddAliasesForAuraScope = AddAliasesForAuraScope,
        AddAuraLaneAliases = AddAuraLaneAliases,
        AddAuraLaneRelativeSizeAliases = AddAuraLaneRelativeSizeAliases,
    }
end
