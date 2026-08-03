--- MSUF_CP_BalanceDruid.lua
--- Balance Druid Astral Power prediction and eclipse coloring runtime.
--- Kept out of the controller because it owns its own events and class gate.
--- MSUF_CP_Balance.lua ? Balance Druid Astral Power prediction + eclipse colors
--- Self-contained feature module. Wrapped in do?end so the Druid-class-gate
--- below uses a scoped 'do return end' that skips only this block, not the
--- whole file. Previous layout used two file-scope 'return' statements which
--- aborted parsing of the rest of the file on non-Druid characters (meaning
--- any trailing code added after this block would silently vanish).
do
    local _, MSUF = ...
    MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
    local ExportPublic = MSUF.ExportPublic or function(name, value)
        _G[name] = value
        return value
    end

    local function CoreUnitFrame(unit)
        local UF = MSUF and MSUF.UF
        if UF and type(UF.GetFrame) == "function" then
            local frame = UF.GetFrame(unit)
            if frame then return frame end
        end
        local frames = UF and UF.frames
        return unit and frames and frames[unit] or nil
    end

    local balanceBuilders = _G.MSUF_CP_FEATURE_BUILDERS
    if type(balanceBuilders) ~= "table" then
        balanceBuilders = {}
        ExportPublic("MSUF_CP_FEATURE_BUILDERS", balanceBuilders)
    end

    --- Class gate: Balance-specific runtime setup only applies to Druids.
    --- Everything inside this do-block is cold-dead code for other classes
    --- (the mode/feature builders in MSUF_CP_Modes.lua are class-neutral
    --- registrations and remain registered for all classes ? consumer-side
    --- spec checks gate which mode is actually rendered).
    local _, _playerClass = UnitClass("player")
    if _playerClass ~= "DRUID" then
        --- Scoped return: exits this do-block only, NOT the file.
        do return end
    end

    --- One-time load guard (scoped ? only relevant once we know we're Druid).
    if _G.__MSUF_CP_Balance_Loaded then
        do return end
    end
    _G.__MSUF_CP_Balance_Loaded = true

    local UnitClass = UnitClass
    local UnitPower = UnitPower
    local UnitPowerType = UnitPowerType
    local UnitPowerMax = UnitPowerMax
    local GetTime = GetTime
    local CreateFrame = CreateFrame
    local C_Timer = C_Timer
    local C_UnitAuras = C_UnitAuras
    local C_Spell = C_Spell
    local C_SpellBook = C_SpellBook
    local type = type
    local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local PLAYER_CLASS = _playerClass

    local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { BAL = {}, SPELL = {} }
local _issecretvalue = _G.issecretvalue
local _canaccesstable = _G.canaccesstable
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

local function CanAccessTableValue(value)
    if NotSecret(value) == false or value == nil or type(value) ~= "table" then return false end
    if _canaccesstable and _canaccesstable(value) == false then return false end
    return true
end

local function CanAccessOptionalTableValue(value)
    if NotSecret(value) == false then return false end
    if value == nil then return true end
    return CanAccessTableValue(value)
end

local LUNAR_POWER = (Enum and Enum.PowerType and Enum.PowerType.LunarPower) or 8
local _active = false
local _castSpell = nil
local _predAmt = 0
local _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
local _predTex = nil
local _eclColor = nil
local _eclColorScratch = { 1, 1, 1 }
local _featureOn = true
local _predictionOn = true
local _colorOverrides = nil
local _auraDeferred = false

local function _refreshConfig()
    local db = _G.MSUF_DB
    local b = db and db.bars
    local g = db and db.general
    _featureOn = not (b and b.showClassPower == false)
    _predictionOn = _featureOn and not (b and b.classPowerShowPrediction == false)
    _colorOverrides = g and g.classPowerColorOverrides or nil
end

local function GetColorOverrides()
    return _colorOverrides
end

local function _checkActive()
    if not _featureOn then _active = false; return end
    local spec = GetSpec and GetSpec()
    if spec ~= 1 then _active = false; return end
    local pType = UnitPowerType("player")
    _active = (NotSecret(pType) and pType == LUNAR_POWER) and true or false
end

local function _getPowerBar()
    local pf = CoreUnitFrame("player") or _G.MSUF_player
    return pf and pf.targetPowerBar or nil
end

local function _resolveEclColor(token)
    local ov = GetColorOverrides()
    if type(ov) == "table" then
        local c = token and ov[token]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    if token == "ECLIPSE_SOLAR" then return CPK.BAL.CLR_SOLAR[1], CPK.BAL.CLR_SOLAR[2], CPK.BAL.CLR_SOLAR[3] end
    if token == "ECLIPSE_LUNAR" then return CPK.BAL.CLR_LUNAR[1], CPK.BAL.CLR_LUNAR[2], CPK.BAL.CLR_LUNAR[3] end
    if token == "ECLIPSE_CA" then return CPK.BAL.CLR_CA[1], CPK.BAL.CLR_CA[2], CPK.BAL.CLR_CA[3] end
    return nil
end

local function _SetEclipseColor(r, g, b, fallback)
    if r then
        _eclColorScratch[1], _eclColorScratch[2], _eclColorScratch[3] = r, g, b
        _eclColor = _eclColorScratch
    else
        _eclColor = fallback
    end
end

local _balAuras = {
    watched = {},
    bySpell = {},
    spellByInstance = {},
}

local function _AuraID(value)
    if value == nil or not NotSecret(value) then return nil end
    return tonumber(value)
end

local function _AuraSpellID(aura)
    return aura and _AuraID(aura.spellId or aura.spellID or aura.id) or nil
end

local function _AuraInstanceID(aura)
    return aura and _AuraID(aura.auraInstanceID) or nil
end

local function _ClearTrackedAura(spellID, auraInstanceID)
    spellID = _AuraID(spellID)
    auraInstanceID = _AuraID(auraInstanceID)
    if auraInstanceID then _balAuras.spellByInstance[auraInstanceID] = nil end
    if spellID then
        local current = _balAuras.bySpell[spellID]
        if not auraInstanceID or not current or _AuraInstanceID(current) == auraInstanceID then
            _balAuras.bySpell[spellID] = nil
        end
    end
end

local function _StoreTrackedAura(aura)
    if not CanAccessTableValue(aura) then return false end
    local spellID = _AuraSpellID(aura)
    if not (spellID and _balAuras.watched[spellID]) then return false end
    local auraInstanceID = _AuraInstanceID(aura)
    if auraInstanceID then _balAuras.spellByInstance[auraInstanceID] = spellID end
    _balAuras.bySpell[spellID] = aura
    return true
end

local function _FetchTrackedAura(spellID)
    spellID = _AuraID(spellID)
    if not spellID then return nil end

    local shared = _G.MSUF_CP_GetTrackedPlayerAura
    if type(shared) == "function" then
        local aura = shared(spellID)
        if CanAccessTableValue(aura) then
            _StoreTrackedAura(aura)
            return aura
        end
    end

    if not C_UnitAuras then return nil end
    local aura
    if type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end
    if (not CanAccessTableValue(aura)) and type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetUnitAuraBySpellID("player", spellID)
    end
    if CanAccessTableValue(aura) then
        _StoreTrackedAura(aura)
    else
        aura = nil
    end
    return aura
end

local function _GetTrackedAura(spellID)
    spellID = _AuraID(spellID)
    if not spellID then return nil end
    local aura = _balAuras.bySpell[spellID]
    if aura then
        local expirationTime = aura.expirationTime
        local exp = NotSecret(expirationTime) and tonumber(expirationTime) or nil
        if exp and exp > 0 and exp <= GetTime() then
            _ClearTrackedAura(spellID, _AuraInstanceID(aura))
            aura = nil
        end
    end
    return aura or _FetchTrackedAura(spellID)
end

local function _ScanUnitAuras()
    if not (C_UnitAuras and type(C_UnitAuras.GetUnitAuras) == "function") then return end
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if not CanAccessTableValue(auras) then return end
    for i = 1, #auras do _StoreTrackedAura(auras[i]) end
end

local function _RebuildTrackedAuras()
    for k in pairs(_balAuras.bySpell) do _balAuras.bySpell[k] = nil end
    for k in pairs(_balAuras.spellByInstance) do _balAuras.spellByInstance[k] = nil end
    for auraID in pairs(CPConst.ECLIPSE_AURAS or {}) do
        _balAuras.watched[auraID] = true
    end
    local canFetchBySpell = C_UnitAuras and (
        type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
        or type(C_UnitAuras.GetUnitAuraBySpellID) == "function"
    )
    if canFetchBySpell then
        for auraID in pairs(CPConst.ECLIPSE_AURAS or {}) do
            _FetchTrackedAura(auraID)
        end
    else
        _ScanUnitAuras()
    end
end

local function _CanProcessIncrementalAuraUpdate(unitAuraUpdateInfo)
    if not CanAccessTableValue(unitAuraUpdateInfo) then return false end

    --- Midnight/PTR can secret-wrap both the full-update flag and the aura
    --- delta tables for tainted addon execution. Re-scan the tracked player
    --- auras instead of performing any forbidden boolean test or iteration.
    local isFullUpdate = unitAuraUpdateInfo.isFullUpdate
    if NotSecret(isFullUpdate) == false or isFullUpdate then return false end

    return CanAccessOptionalTableValue(unitAuraUpdateInfo.addedAuras)
        and CanAccessOptionalTableValue(unitAuraUpdateInfo.updatedAuraInstanceIDs)
        and CanAccessOptionalTableValue(unitAuraUpdateInfo.removedAuraInstanceIDs)
end

local function _ProcessAuraUpdate(unitAuraUpdateInfo)
    if not _CanProcessIncrementalAuraUpdate(unitAuraUpdateInfo) then
        _RebuildTrackedAuras()
        return
    end

    local addedAuras = unitAuraUpdateInfo.addedAuras
    if addedAuras then
        for i = 1, #addedAuras do _StoreTrackedAura(addedAuras[i]) end
    end

    local updatedAuraInstanceIDs = unitAuraUpdateInfo.updatedAuraInstanceIDs
    if updatedAuraInstanceIDs and C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
        for i = 1, #updatedAuraInstanceIDs do
            local auraInstanceID = _AuraID(updatedAuraInstanceIDs[i])
            local spellID = auraInstanceID and _balAuras.spellByInstance[auraInstanceID]
            if spellID then
                local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
                if CanAccessTableValue(aura) then _StoreTrackedAura(aura) else _ClearTrackedAura(spellID, auraInstanceID) end
            end
        end
    end

    local removedAuraInstanceIDs = unitAuraUpdateInfo.removedAuraInstanceIDs
    if removedAuraInstanceIDs then
        for i = 1, #removedAuraInstanceIDs do
            local auraInstanceID = _AuraID(removedAuraInstanceIDs[i])
            local spellID = auraInstanceID and _balAuras.spellByInstance[auraInstanceID]
            if spellID then _ClearTrackedAura(spellID, auraInstanceID) end
        end
    end
end

local function _refreshEclipses()
    _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
    for auraID, kind in pairs(CPConst.ECLIPSE_AURAS or {}) do
        local aura = _GetTrackedAura(auraID)
        if aura then
            local expirationTime = aura.expirationTime
            local exp = NotSecret(expirationTime) and tonumber(expirationTime) or nil
            if exp then
                if kind == "SOLAR" then _solarExp = exp
                elseif kind == "LUNAR" then _lunarExp = exp
                elseif kind == "CA" then _caExp = exp
                elseif kind == "INC" then _incExp = exp end
            end
        end
    end
    local now = GetTime()
    local inCA, inInc = (_caExp > now), (_incExp > now)
    if inCA or inInc then
        local r, g, b = _resolveEclColor("ECLIPSE_CA")
        _SetEclipseColor(r, g, b, CPK.BAL.CLR_CA)
    elseif _solarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_SOLAR")
        _SetEclipseColor(r, g, b, CPK.BAL.CLR_SOLAR)
    elseif _lunarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_LUNAR")
        _SetEclipseColor(r, g, b, CPK.BAL.CLR_LUNAR)
    else
        _eclColor = nil
    end
end

local function _computeAP(spellID)
    if not spellID then return 0 end
    local base = (CPConst.AP_GENERATORS or {})[spellID]
    if not base then return 0 end
    if spellID == CPK.SPELL.AP_WRATH or spellID == CPK.SPELL.AP_STARFIRE then
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if known and known(CPK.SPELL.NATURES_BALANCE) then base = base + 2 end
        local now = GetTime()
        local inCA, inInc = (_caExp > now), (_incExp > now)
        local inEcl = false
        if spellID == CPK.SPELL.AP_WRATH then
            inEcl = (_solarExp > now) or inCA or inInc
        else
            inEcl = (_lunarExp > now) or inCA or inInc
        end
        if inEcl then base = base * 1.4 end
    end
    return base
end

local function _resolvePredColor()
    local ov = GetColorOverrides()
    if type(ov) == "table" then
        local c = ov["AP_PREDICTION"]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    if _G.MSUF_GetPowerBarColor then
        local r, g, b = _G.MSUF_GetPowerBarColor(LUNAR_POWER, "LUNAR_POWER")
        if type(r) == "number" then return r, g, b end
    end
    return 0.30, 0.52, 0.90
end

local function _applyEclipseColor()
    local bar = _getPowerBar()
    if not bar or not _eclColor then return end
    bar:SetStatusBarColor(_eclColor[1], _eclColor[2], _eclColor[3], 1)
end

local function _updateOverlay()
    local bar = _getPowerBar()
    if not bar then return end
    if _predictionOn == false then
        if _predTex then _predTex:Hide() end
        return
    end
    if not _predTex then
        local tex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetVertexColor(1, 1, 1, CPK.BAL.PRED_ALPHA)
        tex:SetHeight(1)
        tex:Hide()
        _predTex = tex
    end
    local getBarTex = _G.MSUF_GetBarTexture
    local texture = getBarTex and getBarTex() or "Interface\\Buttons\\WHITE8x8"
    if _predTex._msufTexture ~= texture then
        _predTex:SetTexture(texture)
        _predTex._msufTexture = texture
    end
    if _predAmt <= 0 or not _castSpell then
        _predTex:Hide()
        return
    end
    local rawMx = UnitPowerMax("player", LUNAR_POWER)
    if not NotSecret(rawMx) then _predTex:Hide(); return end
    local mx = tonumber(rawMx) or 100
    if mx <= 0 then mx = 100 end
    local predFrac = _predAmt / mx
    if predFrac > 1 then predFrac = 1 end
    local rawCur = UnitPower("player", LUNAR_POWER)
    if NotSecret(rawCur) then
        local cur = tonumber(rawCur) or 0
        local remainingFrac = (mx - cur) / mx
        if remainingFrac < 0 then remainingFrac = 0 end
        if predFrac > remainingFrac then predFrac = remainingFrac end
    end
    if predFrac <= 0 then _predTex:Hide(); return end
    local barW, barH = bar:GetWidth(), bar:GetHeight()
    if barW <= 0 or barH <= 0 then _predTex:Hide(); return end
    local predW = barW * predFrac
    if predW < 1 then _predTex:Hide(); return end
    if _eclColor then
        _predTex:SetVertexColor(_eclColor[1], _eclColor[2], _eclColor[3], CPK.BAL.PRED_ALPHA)
    else
        local pr, pg, pb = _resolvePredColor()
        _predTex:SetVertexColor(pr, pg, pb, CPK.BAL.PRED_ALPHA)
    end
    _predTex:ClearAllPoints()
    _predTex:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    _predTex:SetSize(predW, barH)
    _predTex:Show()
end

local function _cleanup()
    _castSpell, _predAmt, _eclColor = nil, 0, nil
    if _predTex then _predTex:Hide() end
end

local f = CreateFrame("Frame")
local _stateEventsBound = false
local _castEventsBound = false
local _structuralEventsBound = false

local function _clearPrediction()
    _castSpell, _predAmt = nil, 0
    if _predTex then _predTex:Hide() end
end

local function _setStateEventsBound(active)
    active = active and true or false
    if _stateEventsBound == active then return end
    _stateEventsBound = active

    if active then
        f:RegisterUnitEvent("UNIT_AURA", "player")
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    else
        f:UnregisterEvent("UNIT_AURA")
        f:UnregisterEvent("UNIT_POWER_UPDATE")
    end
end

local function _setCastEventsBound(active)
    active = active and true or false
    if _castEventsBound == active then return end
    _castEventsBound = active

    if active then
        f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        f:UnregisterEvent("UNIT_SPELLCAST_START")
        f:UnregisterEvent("UNIT_SPELLCAST_STOP")
        f:UnregisterEvent("UNIT_SPELLCAST_FAILED")
        f:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        f:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        _clearPrediction()
    end
end

local function _syncHotEvents()
    _setStateEventsBound(_active)
    _setCastEventsBound(_active and _predictionOn)
end

local function _setStructuralEventsBound(active)
    active = active and true or false
    if _structuralEventsBound == active then return end
    _structuralEventsBound = active

    if active then
        f:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        f:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        f:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
        f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        _active = false
        _syncHotEvents()
        _cleanup()
    end
end

local function _refreshActiveState()
    _refreshConfig()
    _setStructuralEventsBound(_featureOn)
    if not _featureOn then
        _active = false
        _syncHotEvents()
        _cleanup()
        return
    end
    _checkActive()
    if _active then
        _RebuildTrackedAuras()
        _refreshEclipses()
        _applyEclipseColor()
    else
        _cleanup()
    end
    _syncHotEvents()
end

local function _runDeferredAuraRefresh()
    _auraDeferred = false
    if not _active then
        return
    end
    _refreshEclipses()
    _applyEclipseColor()
    if _castSpell then
        _predAmt = _computeAP(_castSpell)
        _updateOverlay()
    end
end

local function _deferAuraRefresh()
    if _auraDeferred then return end
    _auraDeferred = true
    local scheduleOnce = _G.MSUF_ScheduleOnce
    if type(scheduleOnce) == "function" then
        scheduleOnce("MSUF_BALANCE_AURA_REFRESH", _runDeferredAuraRefresh)
    else
        C_Timer.After(0, _runDeferredAuraRefresh)
    end
end

    local function BalanceOnEvent(_, event, arg1, arg2, arg3)
        if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD" then
            _refreshActiveState()
            return
    end
    if not _active then return end
    if event == "UNIT_SPELLCAST_START" and arg1 == "player" then
        _castSpell = arg3
        _predAmt = _computeAP(arg3)
        _updateOverlay()
        return
    end
    if (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED") and arg1 == "player" then
        _clearPrediction()
        _updateOverlay()
        return
    end
    if event == "UNIT_AURA" and arg1 == "player" then
        _ProcessAuraUpdate(arg2)
        _deferAuraRefresh()
        return
    end
    if event == "UNIT_POWER_UPDATE" and arg1 == "player" then
        if _castSpell then _updateOverlay() end
        if _eclColor then _applyEclipseColor() end
    end
    end

    f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
        return BalanceOnEvent(self, event, arg1, arg2, arg3)
    end)

_refreshActiveState()

ExportPublic("MSUF_BAL_RefreshRuntime", _refreshActiveState)

ExportPublic("MSUF_BAL_InvalidateColors", function()
    _refreshConfig()
    if not _active then return end
    _refreshEclipses()
    _applyEclipseColor()
    if _castSpell then _updateOverlay() end
end)

end --- close do-block started at Balance module header (Druid class gate)
