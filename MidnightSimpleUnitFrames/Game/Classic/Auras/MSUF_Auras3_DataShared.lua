--- Shared helpers for client-specific Classic aura datasets.
--- Loaded only by Classic-family manifests; Mainline keeps its original data path.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

A3.AuraSpellIDAliases = A3.AuraSpellIDAliases or {}

--- Classic aura payloads carry rank-specific IDs (Vanilla, TBC) or a
--- different aura ID than the cast (Mists). Every ID that reaches the alias
--- expander is therefore resolved once against the flavor's generated
--- SpellName catalog (Game/<Flavor>/Auras/AliasData + the shared
--- Auras3/MSUF_Auras3_AuraAliases.lua resolver) so curated DoT/defensive
--- lists, group indicators and user whitelists match every same-name ID,
--- the way WeakAuras matches auras by name on Classic. Retail only expands
--- user-selected IDs; Classic deliberately broadens curated data as well.
--- The resolver memoizes hits and misses, so repeated compiles stay O(1).
local singleID = {}
local function ResolveCatalogAliases(spellID)
    local compile = A3.CompileCustomAuraAliases
    if type(compile) ~= "function" then return end
    singleID[spellID] = true
    compile(singleID)
    singleID[spellID] = nil
end

function A3.AddAuraSpellIDAndAliases(out, spellID)
    spellID = tonumber(spellID)
    if not (out and spellID and spellID > 0) then return end
    spellID = math.floor(spellID + 0.5)
    out[spellID] = true
    ResolveCatalogAliases(spellID)
    local aliases = A3.AuraSpellIDAliases[spellID]
    for i = 1, type(aliases) == "table" and #aliases or 0 do
        local auraSpellID = tonumber(aliases[i])
        if auraSpellID and auraSpellID > 0 then
            out[math.floor(auraSpellID + 0.5)] = true
        end
    end
end
