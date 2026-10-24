--- Classic-only local API adapters.
---
--- This file is absent from Mainline's TOC/load graph. Never add or replace
--- fields on Blizzard's global C_* namespace tables here: even assigning the
--- already-existing function gives the field MSUF taint and can later turn a
--- hardware ActionButton click into ADDON_ACTION_FORBIDDEN at UseAction().

local _, MSUF = ...
local Client = MSUF.Client
if Client.IsClassic ~= true then return end

local type = type
local Compat = MSUF.Compat or {}
MSUF.Compat = Compat

local nativeAddOns = type(C_AddOns) == "table" and C_AddOns or nil
Compat.AddOns = {
    GetAddOnMetadata = nativeAddOns and nativeAddOns.GetAddOnMetadata or GetAddOnMetadata,
    IsAddOnLoaded = nativeAddOns and nativeAddOns.IsAddOnLoaded or IsAddOnLoaded,
    LoadAddOn = nativeAddOns and nativeAddOns.LoadAddOn or LoadAddOn,
    EnableAddOn = nativeAddOns and nativeAddOns.EnableAddOn or EnableAddOn,
    DisableAddOn = nativeAddOns and nativeAddOns.DisableAddOn or DisableAddOn,
}

local nativeSpell = type(C_Spell) == "table" and C_Spell or nil
local legacyGetSpellInfo = GetSpellInfo
Compat.Spell = {
    GetSpellName = nativeSpell and nativeSpell.GetSpellName or function(identifier)
        return type(legacyGetSpellInfo) == "function" and legacyGetSpellInfo(identifier) or nil
    end,
    GetSpellTexture = nativeSpell and nativeSpell.GetSpellTexture or GetSpellTexture,
    IsSpellInRange = nativeSpell and nativeSpell.IsSpellInRange or IsSpellInRange,
}

local nativeSpellBook = type(C_SpellBook) == "table" and C_SpellBook or nil
Compat.SpellBook = {
    IsSpellKnown = nativeSpellBook and nativeSpellBook.IsSpellKnown or IsSpellKnown,
    IsSpellKnownOrInSpellBook = nativeSpellBook and nativeSpellBook.IsSpellKnownOrInSpellBook or IsSpellKnown,
}
