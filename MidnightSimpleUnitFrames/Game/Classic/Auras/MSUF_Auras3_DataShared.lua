--- Shared helpers for client-specific Classic aura datasets.
--- Loaded only by Classic-family manifests; Mainline keeps its original data path.
local _, MSUF = ...

local A3 = MSUF.MSUF_Auras3

--- Explicit aliases only, for a configured ID whose aura carries a different
--- ID *and* a different name. Same-name drift needs no entry: Classic aura
--- payloads are readable, so every lane that has includeSpellIDs also gets
--- includeSpellNames (ClassicFeatures.NameHash) and the backend matches the
--- aura name when the ID misses. That covers Vanilla/TBC spell ranks and Mists
--- cast-versus-aura IDs on the live client build, with no generated catalog.
A3.AuraSpellIDAliases = A3.AuraSpellIDAliases or {}

A3.AddAuraSpellIDAndAliases = MSUF.AuraConfig.CreateAliasAdder(A3)
