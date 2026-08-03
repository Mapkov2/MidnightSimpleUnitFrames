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
