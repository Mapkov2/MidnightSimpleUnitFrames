--- Classic-only local API adapters.
---
--- This file is absent from Mainline's TOC/load graph. Never add or replace
--- fields on Blizzard's global C_* namespace tables here: even assigning the
--- already-existing function gives the field MSUF taint and can later turn a
--- hardware ActionButton click into ADDON_ACTION_FORBIDDEN at UseAction().

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local Client = MSUF.Client
if not (Client and Client.IsClassic == true) then return end

local type = type
local Compat = MSUF.Compat or {}
MSUF.Compat = Compat

local nativeAddOns = type(_G.C_AddOns) == "table" and _G.C_AddOns or nil
Compat.AddOns = {
    GetAddOnMetadata = nativeAddOns and nativeAddOns.GetAddOnMetadata or _G.GetAddOnMetadata,
    IsAddOnLoaded = nativeAddOns and nativeAddOns.IsAddOnLoaded or _G.IsAddOnLoaded,
    LoadAddOn = nativeAddOns and nativeAddOns.LoadAddOn or _G.LoadAddOn,
    EnableAddOn = nativeAddOns and nativeAddOns.EnableAddOn or _G.EnableAddOn,
    DisableAddOn = nativeAddOns and nativeAddOns.DisableAddOn or _G.DisableAddOn,
}

local nativeSpell = type(_G.C_Spell) == "table" and _G.C_Spell or nil
local legacyGetSpellInfo = _G.GetSpellInfo
Compat.Spell = {
    GetSpellName = nativeSpell and nativeSpell.GetSpellName or function(identifier)
        return type(legacyGetSpellInfo) == "function" and legacyGetSpellInfo(identifier) or nil
    end,
    GetSpellTexture = nativeSpell and nativeSpell.GetSpellTexture or _G.GetSpellTexture,
    IsSpellInRange = nativeSpell and nativeSpell.IsSpellInRange or _G.IsSpellInRange,
}

local nativeSpellBook = type(_G.C_SpellBook) == "table" and _G.C_SpellBook or nil
Compat.SpellBook = {
    IsSpellKnown = nativeSpellBook and nativeSpellBook.IsSpellKnown or _G.IsSpellKnown,
    IsSpellKnownOrInSpellBook = nativeSpellBook and nativeSpellBook.IsSpellKnownOrInSpellBook or _G.IsSpellKnown,
}
