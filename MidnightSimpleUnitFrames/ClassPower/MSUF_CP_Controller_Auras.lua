--- ClassPower/MSUF_CP_Controller_Auras.lua - controller player-aura cache
--- The player auras the aura-driven class resources read: Maelstrom Weapon,
--- Icicles and the Devourer Soul Fragment auras (Mists Arcane Charges on the
--- Classic clients). The cache keeps the watched spells by spell and by aura
--- instance and turns a UNIT_AURA payload into "did the active resource
--- change". Restricted IDs, payloads and fields are never compared or
--- iterated.
---
--- Only a resource the controller follows through UNIT_AURA is watched: the
--- cache is exactly as fresh as those events. Any other spell (the Balance
--- runtime's Eclipse auras, which it tracks with its own UNIT_AURA cache) is
--- read live, so an aura that ends before its expiration time (death, a
--- dispel) is never handed back from here.
---
--- The controller binds it once at load (CONTROLLER_AURAS) and keeps the
--- returned cache as CPAuras; the mode runners read it through
--- MSUF_CP_GetTrackedPlayerAura.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local builders = _G.MSUF_CP_CONST.BuilderRegistry("MSUF_CP_CORE_BUILDERS")

local type, tonumber, pairs = type, tonumber, pairs

--- Bound once by CONTROLLER_AURAS at controller load.
local CPConst, CPK, NotSecret, CanAccessTableValue, CanAccessOptionalTableValue
local C_UnitAuras, GetTime, wipe

local CPAuras = {
    watched = {},
    bySpell = {},
    spellByInstance = {},
}

--- A restricted spell or aura instance ID is never compared, not even with
--- nil: the secret check comes first.
function CPAuras.NormalizeID(value)
    if NotSecret(value) == false then return nil end
    if value == nil then return nil end
    return tonumber(value)
end

function CPAuras.AddSpell(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if spellID then CPAuras.watched[spellID] = true end
end

--- The aura's spell ID. A restricted ID is never boolean-tested: the first
--- field is read once, a secret one answers nil, and the other spellings are
--- read only when it is a plain nil. UNIT_AURA payloads run through here, so
--- the usual spelling returns after one secret check.
function CPAuras.AuraSpellID(aura)
    if not aura then return nil end
    local id = aura.spellId
    if NotSecret(id) == false then return nil end
    if id ~= nil then return tonumber(id) end
    id = aura.spellID
    if NotSecret(id) == false then return nil end
    if id == nil then id = aura.id end
    return CPAuras.NormalizeID(id)
end

function CPAuras.AuraInstanceID(aura)
    return aura and CPAuras.NormalizeID(aura.auraInstanceID) or nil
end

function CPAuras.ClearSpell(spellID, auraInstanceID)
    spellID = CPAuras.NormalizeID(spellID)
    auraInstanceID = CPAuras.NormalizeID(auraInstanceID)
    if auraInstanceID then CPAuras.spellByInstance[auraInstanceID] = nil end
    if spellID then
        local current = CPAuras.bySpell[spellID]
        if not auraInstanceID or not current or CPAuras.AuraInstanceID(current) == auraInstanceID then
            CPAuras.bySpell[spellID] = nil
        end
    end
end

function CPAuras.Store(aura)
    if not CanAccessTableValue(aura) then return false end
    local spellID = CPAuras.AuraSpellID(aura)
    if not (spellID and CPAuras.watched[spellID]) then return false end

    local auraInstanceID = CPAuras.AuraInstanceID(aura)
    if auraInstanceID then
        local oldSpellID = CPAuras.spellByInstance[auraInstanceID]
        if oldSpellID and oldSpellID ~= spellID then
            CPAuras.ClearSpell(oldSpellID, auraInstanceID)
        end
        CPAuras.spellByInstance[auraInstanceID] = spellID
    end

    CPAuras.bySpell[spellID] = aura
    return true
end

function CPAuras.ClearAll()
    if wipe then
        wipe(CPAuras.bySpell)
        wipe(CPAuras.spellByInstance)
        return
    end
    for k in pairs(CPAuras.bySpell) do CPAuras.bySpell[k] = nil end
    for k in pairs(CPAuras.spellByInstance) do CPAuras.spellByInstance[k] = nil end
end

function CPAuras.Fetch(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not (spellID and C_UnitAuras) then return nil end

    local aura
    if type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    elseif type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetUnitAuraBySpellID("player", spellID)
    end
    if CanAccessTableValue(aura) then
        CPAuras.Store(aura)
    else
        aura = nil
    end
    return aura
end

local function CPAuraFieldEqual(left, right, key)
    local a = left and left[key]
    local b = right and right[key]
    if NotSecret(a) == false or NotSecret(b) == false then return false end
    return a == b
end

function CPAuras.SameState(left, right, stateKind)
    if left == right then return true end
    if not left or not right then return false end
    if stateKind == "timer" then
        return CPAuraFieldEqual(left, right, "expirationTime")
    end
    if stateKind == "tip" then
        return CPAuraFieldEqual(left, right, "applications")
            and CPAuraFieldEqual(left, right, "expirationTime")
    end
    --- Stack resources only render presence/application changes. Aura-instance
    --- and duration churn must not repaint ten Enhancement segments.
    return CPAuraFieldEqual(left, right, "applications")
end

function CPAuras.RefreshSpell(spellID, stateKind)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return false end

    local previous = CPAuras.bySpell[spellID]
    CPAuras.ClearSpell(spellID, previous and CPAuras.AuraInstanceID(previous))
    local current = CPAuras.Fetch(spellID)
    return not CPAuras.SameState(previous, current, stateKind)
end

function CPAuras.ActiveSpellKind(powerType, renderMode, spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return nil end
    if powerType == "MAELSTROM_WEAPON" and spellID == CPK.SPELL.MAELSTROM_WEAPON then return "stacks" end
    if powerType == "ICICLES" and CPConst.ICICLES and spellID == CPConst.ICICLES.AURA_ID then return "stacks" end
    if powerType == "SOUL_FRAGMENTS" then
        if spellID == CPK.SPELL.VOID_METAMORPHOSIS
            or spellID == CPK.SPELL.SILENCE_THE_WHISPERS
            or spellID == CPK.SPELL.DARK_HEART then
            return "stacks"
        end
    end
    return nil
end

function CPAuras.RefreshActive(powerType, renderMode)
    local changed = false
    local handled = true
    local function Refresh(spellID, stateKind)
        if CPAuras.RefreshSpell(spellID, stateKind) then changed = true end
    end

    if powerType == "MAELSTROM_WEAPON" then
        Refresh(CPK.SPELL.MAELSTROM_WEAPON, "stacks")
    elseif powerType == "ICICLES" then
        Refresh(CPConst.ICICLES and CPConst.ICICLES.AURA_ID, "stacks")
    elseif powerType == "SOUL_FRAGMENTS" then
        Refresh(CPK.SPELL.VOID_METAMORPHOSIS, "stacks")
        Refresh(CPK.SPELL.SILENCE_THE_WHISPERS, "stacks")
        Refresh(CPK.SPELL.DARK_HEART, "stacks")
    elseif powerType == "SOUL_FRAGMENTS_VENG" then
        --- Vengeance reads the native spell cast count; UNIT_AURA is only a
        --- value-change signal and does not require any aura-cache queries.
        changed = true
    else
        handled = false
    end

    if not handled then
        CPAuras.Rebuild()
        return true
    end
    return changed
end

function CPAuras.IsExpired(aura)
    local expirationTime = aura and aura.expirationTime
    if NotSecret(expirationTime) == false or expirationTime == nil then return false end
    expirationTime = tonumber(expirationTime)
    return expirationTime and expirationTime > 0 and expirationTime <= GetTime()
end

function CPAuras.Get(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return nil end

    local aura = CPAuras.bySpell[spellID]
    if aura then
        if not CPAuras.IsExpired(aura) then return aura end
        CPAuras.ClearSpell(spellID, CPAuras.AuraInstanceID(aura))
    end

    return CPAuras.Fetch(spellID)
end

function CPAuras.Rebuild()
    CPAuras.ClearAll()
    local canFetchBySpell = C_UnitAuras and (
        type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
        or type(C_UnitAuras.GetUnitAuraBySpellID) == "function"
    )
    if canFetchBySpell then
        --- Only the small watched set matters to ClassPower. This avoids a
        --- full helpful-aura scan on secret UNIT_AURA fallback updates.
        for spellID in pairs(CPAuras.watched) do
            CPAuras.Fetch(spellID)
        end
    else
        CPAuras.ScanUnitAuras()
    end
end

function CPAuras.FetchByInstanceID(auraInstanceID)
    auraInstanceID = CPAuras.NormalizeID(auraInstanceID)
    if not (auraInstanceID and C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function") then
        return nil
    end
    return C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
end

function CPAuras.CanProcessIncrementalUpdate(unitAuraUpdateInfo)
    if not CanAccessTableValue(unitAuraUpdateInfo) then return false end

    --- Midnight/PTR can mark UNIT_AURA update fields secret. Addon code may
    --- pass those values to issecretvalue, but it must not branch on them or
    --- iterate secret tables. Fall back to the small player-aura rebuild.
    local isFullUpdate = unitAuraUpdateInfo.isFullUpdate
    if NotSecret(isFullUpdate) == false or isFullUpdate then return false end

    local addedAuras = unitAuraUpdateInfo.addedAuras
    local updatedAuraInstanceIDs = unitAuraUpdateInfo.updatedAuraInstanceIDs
    local removedAuraInstanceIDs = unitAuraUpdateInfo.removedAuraInstanceIDs
    return CanAccessOptionalTableValue(addedAuras)
        and CanAccessOptionalTableValue(updatedAuraInstanceIDs)
        and CanAccessOptionalTableValue(removedAuraInstanceIDs)
end

function CPAuras.ScanUnitAuras()
    if not (C_UnitAuras and type(C_UnitAuras.GetUnitAuras) == "function") then return end
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if not CanAccessTableValue(auras) then return end
    for i = 1, #auras do
        CPAuras.Store(auras[i])
    end
end

function CPAuras.ProcessUnitAuraUpdate(unitAuraUpdateInfo, powerType, renderMode)
    if powerType == "ICICLES" then
        --- Icicles owns one exact player aura. Refresh it directly on each
        --- UNIT_AURA signal instead of relying on incremental aura identity,
        --- which can be restricted, incomplete, or unrelated on Midnight.
        --- The returned applications value remains secret-safe because the
        --- segmented renderer passes it only to native StatusBar setters.
        CPAuras.RefreshSpell(CPConst.ICICLES and CPConst.ICICLES.AURA_ID, "stacks")
        return true
    end

    if not CPAuras.CanProcessIncrementalUpdate(unitAuraUpdateInfo) then
        --- Midnight can hide the incremental payload. Refresh only the aura(s)
        --- consumed by the active resource instead of querying every class.
        return CPAuras.RefreshActive(powerType, renderMode)
    end

    local changed = powerType == "SOUL_FRAGMENTS_VENG"
    local addedAuras = unitAuraUpdateInfo.addedAuras
    if addedAuras then
        for i = 1, #addedAuras do
            local aura = addedAuras[i]
            local spellID = CanAccessTableValue(aura) and CPAuras.AuraSpellID(aura) or nil
            if CPAuras.Store(aura) and CPAuras.ActiveSpellKind(powerType, renderMode, spellID) then
                changed = true
            end
        end
    end

    local updatedAuraInstanceIDs = unitAuraUpdateInfo.updatedAuraInstanceIDs
    if updatedAuraInstanceIDs then
        for i = 1, #updatedAuraInstanceIDs do
            local auraInstanceID = CPAuras.NormalizeID(updatedAuraInstanceIDs[i])
            local spellID = auraInstanceID and CPAuras.spellByInstance[auraInstanceID]
            if spellID then
                local previous = CPAuras.bySpell[spellID]
                local aura = CPAuras.FetchByInstanceID(auraInstanceID)
                local current
                if CanAccessTableValue(aura) then
                    CPAuras.Store(aura)
                    current = aura
                else
                    CPAuras.ClearSpell(spellID, auraInstanceID)
                end
                local stateKind = CPAuras.ActiveSpellKind(powerType, renderMode, spellID)
                if stateKind and not CPAuras.SameState(previous, current, stateKind) then changed = true end
            end
        end
    end

    local removedAuraInstanceIDs = unitAuraUpdateInfo.removedAuraInstanceIDs
    if removedAuraInstanceIDs then
        for i = 1, #removedAuraInstanceIDs do
            local auraInstanceID = CPAuras.NormalizeID(removedAuraInstanceIDs[i])
            local spellID = auraInstanceID and CPAuras.spellByInstance[auraInstanceID]
            if spellID then
                CPAuras.ClearSpell(spellID, auraInstanceID)
                if CPAuras.ActiveSpellKind(powerType, renderMode, spellID) then changed = true end
            end
        end
    end
    return changed
end

--- Binds the controller's constants and secret-value helpers, seeds the
--- watched spells and returns the cache.
builders.CONTROLLER_AURAS = function(E)
    CPConst, CPK = E.CPConst, E.CPK
    NotSecret = E.NotSecret
    CanAccessTableValue, CanAccessOptionalTableValue = E.CanAccessTableValue, E.CanAccessOptionalTableValue
    C_UnitAuras, GetTime, wipe = E.C_UnitAuras, E.GetTime, E.wipe

    CPAuras.AddSpell(CPK.SPELL.MAELSTROM_WEAPON)
    CPAuras.AddSpell(CPConst.ICICLES and CPConst.ICICLES.AURA_ID)
    CPAuras.AddSpell(CPK.SPELL.VOID_METAMORPHOSIS)
    CPAuras.AddSpell(CPK.SPELL.SILENCE_THE_WHISPERS)
    CPAuras.AddSpell(CPK.SPELL.DARK_HEART)
    --- Classic: Mists Arcane Charges is the only aura resource a Classic provider
    --- routes, so it is the whole watched set there, and its incremental and
    --- fallback aura updates are answered before the Retail resources are asked.
    if E.IS_CLASSIC then
        CPAuras.watched = {}
        CPAuras.AddSpell(CPK.SPELL.MISTS_ARCANE_CHARGE)
        local RetailActiveSpellKind, RetailRefreshActive = CPAuras.ActiveSpellKind, CPAuras.RefreshActive
        function CPAuras.ActiveSpellKind(powerType, renderMode, spellID)
            if powerType == "MISTS_ARCANE_CHARGES" then
                return CPAuras.NormalizeID(spellID) == CPK.SPELL.MISTS_ARCANE_CHARGE and "stacks" or nil
            end
            return RetailActiveSpellKind(powerType, renderMode, spellID)
        end
        function CPAuras.RefreshActive(powerType, renderMode)
            if powerType == "MISTS_ARCANE_CHARGES" then
                return CPAuras.RefreshSpell(CPK.SPELL.MISTS_ARCANE_CHARGE, "stacks") == true
            end
            return RetailRefreshActive(powerType, renderMode)
        end
    end

    return CPAuras
end
