--- Shared helpers for client-specific Classic aura datasets.
--- Loaded only by Classic-family manifests; Mainline keeps its original data path.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

--- Explicit aliases only, for a configured ID whose aura carries a different
--- ID *and* a different name. Same-name drift needs no entry: Classic aura
--- payloads are readable, so every lane that has includeSpellIDs also gets
--- includeSpellNames (ClassicFeatures.NameHash) and the backend matches the
--- aura name when the ID misses. That covers Vanilla/TBC spell ranks and Mists
--- cast-versus-aura IDs on the live client build, with no generated catalog.
A3.AuraSpellIDAliases = A3.AuraSpellIDAliases or {}

function A3.AddAuraSpellIDAndAliases(out, spellID)
    spellID = tonumber(spellID)
    if not (out and spellID and spellID > 0) then return end
    spellID = math.floor(spellID + 0.5)
    out[spellID] = true
    local aliases = A3.AuraSpellIDAliases[spellID]
    for i = 1, type(aliases) == "table" and #aliases or 0 do
        local auraSpellID = tonumber(aliases[i])
        if auraSpellID and auraSpellID > 0 then
            out[math.floor(auraSpellID + 0.5)] = true
        end
    end
end
