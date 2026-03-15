-- ============================================================================
-- MSUF_CP_Balance.lua — Balance Druid Astral Power prediction + eclipse colors
-- Self-contained feature module loaded before the CP core.
-- ============================================================================
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_FEATURE_BUILDERS = builders
end

if _G.__MSUF_CP_Balance_Loaded then return end
_G.__MSUF_CP_Balance_Loaded = true

local UnitClass = UnitClass
local UnitPowerType = UnitPowerType
local UnitPowerMax = UnitPowerMax
local GetTime = GetTime
local CreateFrame = CreateFrame
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local type = type
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local _, PLAYER_CLASS = UnitClass("player")
if PLAYER_CLASS ~= "DRUID" then return end

local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { BAL = {}, SPELL = {} }
local _issecretvalue = _G.issecretvalue
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

local LUNAR_POWER = (Enum and Enum.PowerType and Enum.PowerType.LunarPower) or 8
local _active = false
local _castSpell = nil
local _predAmt = 0
local _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
local _predTex = nil
local _eclColor = nil

local function GetColorOverrides()
    local db = _G.MSUF_DB
    local g = db and db.general
    return g and g.classPowerColorOverrides or nil
end

local function ShowPredictionEnabled()
    local db = _G.MSUF_DB
    local b = db and db.bars
    return not (b and b.classPowerShowPrediction == false)
end

local function _checkActive()
    local spec = GetSpec and GetSpec()
    if spec ~= 1 then _active = false; return end
    local pType = UnitPowerType("player")
    _active = (NotSecret(pType) and pType == LUNAR_POWER) and true or false
end

local function _getPowerBar()
    local pf = _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player)
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

local function _refreshEclipses()
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not getAura then return end
    _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
    for auraID, kind in pairs(CPConst.ECLIPSE_AURAS or {}) do
        local aura = getAura(auraID)
        if aura and aura.expirationTime then
            local exp = aura.expirationTime
            if kind == "SOLAR" then _solarExp = exp
            elseif kind == "LUNAR" then _lunarExp = exp
            elseif kind == "CA" then _caExp = exp
            elseif kind == "INC" then _incExp = exp end
        end
    end
    local now = GetTime()
    local inCA, inInc = (_caExp > now), (_incExp > now)
    if inCA or inInc then
        local r, g, b = _resolveEclColor("ECLIPSE_CA")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_CA
    elseif _solarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_SOLAR")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_SOLAR
    elseif _lunarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_LUNAR")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_LUNAR
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
    if ShowPredictionEnabled() == false then
        if _predTex then _predTex:Hide() end
        return
    end
    if not _predTex then
        local tex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        local getBarTex = _G.MSUF_GetBarTexture
        tex:SetTexture(getBarTex and getBarTex() or "Interface\\Buttons\\WHITE8x8")
        tex:SetVertexColor(1, 1, 1, CPK.BAL.PRED_ALPHA)
        tex:SetHeight(1)
        tex:Hide()
        _predTex = tex
    end
    if _predAmt <= 0 or not _castSpell then
        _predTex:Hide()
        return
    end
    local mx = UnitPowerMax("player", LUNAR_POWER) or 100
    if mx <= 0 then mx = 100 end
    local predFrac = _predAmt / mx
    if predFrac > 1 then predFrac = 1 end
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
f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
f:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD" then
        _checkActive()
        if _active then
            _refreshEclipses()
            _applyEclipseColor()
        else
            _cleanup()
        end
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
        _castSpell = nil
        _predAmt = 0
        _updateOverlay()
        return
    end
    if event == "UNIT_AURA" and arg1 == "player" then
        _refreshEclipses()
        _applyEclipseColor()
        if _castSpell then
            _predAmt = _computeAP(_castSpell)
            _updateOverlay()
        end
        return
    end
    if event == "UNIT_POWER_UPDATE" and arg1 == "player" then
        if _castSpell then _updateOverlay() end
        if _eclColor then _applyEclipseColor() end
    end
end)

_G.MSUF_BAL_InvalidateColors = function()
    if not _active then return end
    _refreshEclipses()
    _applyEclipseColor()
    if _castSpell then _updateOverlay() end
end
