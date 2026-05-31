local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF or {}
MSUF.UF = UF

local DispelState = UF.DispelState or {}
UF.DispelState = DispelState

local CUA = _G.C_UnitAuras
local GetAuraDataByIndex = CUA and CUA.GetAuraDataByIndex
local GetAuraSlots = CUA and CUA.GetAuraSlots
local GetAuraDataBySlot = CUA and CUA.GetAuraDataBySlot
local GetAuraDispelTypeColor = CUA and CUA.GetAuraDispelTypeColor
local UnitExists = _G.UnitExists
local UnitIsFriend = _G.UnitIsFriend
local UnitIsUnit = _G.UnitIsUnit
local CreateColor = _G.CreateColor
local C_CurveUtil = _G.C_CurveUtil
local Enum = _G.Enum
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local PlainTrue = Secrets.PlainTrue or function(value) return value == true or value == 1 end
local PlainFalse = Secrets.PlainFalse or function(value) return value == false or value == 0 end
local tonumber = tonumber
local type = type
local tostring = tostring

local HARMFUL = "HARMFUL"
local HARMFUL_PLAYER = "HARMFUL|PLAYER"
local HARMFUL_DISPELLABLE = "HARMFUL|RAID_PLAYER_DISPELLABLE"

local TYPE_INDEX = {
    Magic = 1,
    Curse = 2,
    Disease = 3,
    Poison = 4,
    Bleed = 5,
}

local TYPE_DEFAULTS = {
    Magic = { 0.20, 0.60, 1.00 },
    Curse = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison = { 0.00, 0.60, 0.00 },
    Bleed = { 0.80, 0.10, 0.10 },
}

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function UnitIsFriendly(unit)
    if not unit then return false end
    if UnitIsUnit then
        local isPlayer = UnitIsUnit(unit, "player")
        if PlainTrue(isPlayer) or IsSecret(isPlayer) then return true end
    end
    if UnitIsFriend then
        local isFriend = UnitIsFriend("player", unit)
        if IsSecret(isFriend) then return true end
        return PlainTrue(isFriend)
    end
    return true
end

local function ExistingUnit(unit)
    if not unit then return false end
    if UnitExists then
        return not PlainFalse(UnitExists(unit))
    end
    return true
end

local function AuraInstanceID(data)
    if not data then return nil end
    local auraInstanceID = data.auraInstanceID
    if IsSecret(auraInstanceID) then return nil end
    if auraInstanceID ~= nil then return auraInstanceID end
    auraInstanceID = data.auraInstanceId
    if IsSecret(auraInstanceID) then return nil end
    return auraInstanceID
end

local function ValidDispelName(value)
    if IsSecret(value) then return nil end
    if type(value) ~= "string" or value == "" or value == "None" then return nil end
    return value
end

function DispelState.NormalizeDetectTrigger(value)
    value = tostring(value or ""):upper()
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
        return "ANY_DEBUFF"
    elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
        return "PLAYER_CAST"
    end
    return "BY_ME"
end

function DispelState.NormalizeOverlayTrigger(value)
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then
        return "BORDER"
    end
    return DispelState.NormalizeDetectTrigger(value)
end

local function CanonicalOverlayTrigger(trigger)
    if trigger == "BORDER" or trigger == "ANY_DEBUFF"
        or trigger == "DISPEL_TYPE" or trigger == "PLAYER_CAST"
        or trigger == "BY_ME"
    then
        return trigger
    end
    return DispelState.NormalizeOverlayTrigger(trigger)
end

_G.MSUF_NormalizeDispelBorderTrigger = DispelState.NormalizeDetectTrigger
_G.MSUF_NormalizeUnitDispelOverlayTrigger = DispelState.NormalizeOverlayTrigger

local function FirstAuraBySlots(unit, filter)
    if not (GetAuraSlots and GetAuraDataBySlot) then return nil end
    local first, second = GetAuraSlots(unit, filter, 1)
    local slot
    if type(second) == "table" then
        slot = second[1]
    elseif type(first) == "table" then
        slot = first[1]
    elseif type(second) == "number" then
        slot = second
    elseif type(first) == "number" then
        slot = first
    end
    if slot then return GetAuraDataBySlot(unit, slot) end
    return nil
end

function DispelState.FirstAura(unit, filter)
    if GetAuraDataByIndex then
        local data = GetAuraDataByIndex(unit, 1, filter)
        if data then return data end
    end
    return FirstAuraBySlots(unit, filter)
end

local function ResetSnapshot(snapshot, unit)
    snapshot.unit = unit
    snapshot.valid = true
    snapshot.friendly = false
    snapshot.anyDebuff = false
    snapshot.anyDispelType = false
    snapshot.dispellableByMe = false
    snapshot.dispellable = false
    snapshot.playerCastDebuff = false
    snapshot.byMe = false
    snapshot.anyDebuffAuraInstanceID = nil
    snapshot.anyDispelAuraInstanceID = nil
    snapshot.dispelAuraInstanceID = nil
    snapshot.playerAuraInstanceID = nil
    snapshot.dispelName = nil
    snapshot.anyDispelName = nil
    snapshot.borderActive = false
    snapshot.overlayActive = false
    snapshot.borderTrigger = nil
    snapshot.overlayTrigger = nil
    snapshot.borderAuraInstanceID = nil
    snapshot.overlayAuraInstanceID = nil
    snapshot.borderR, snapshot.borderG, snapshot.borderB, snapshot.borderA = nil, nil, nil, nil
    snapshot.overlayR, snapshot.overlayG, snapshot.overlayB, snapshot.overlayA = nil, nil, nil, nil
    snapshot._cacheToken = nil
    snapshot._cacheUnit = nil
    snapshot._scannedAnyDebuff = false
    snapshot._scannedAnyDispelType = false
    snapshot._scannedDispellable = false
    snapshot._scannedPlayerCast = false
    snapshot._scanMaxAuras = 0
end

function DispelState.AuraCanActivePlayerDispel(data)
    return data and PlainTrue(data.canActivePlayerDispel) or false
end

function DispelState.IndexAura(snapshot, data)
    if not (snapshot and data) then return end
    snapshot.anyDebuff = true
    local aid = AuraInstanceID(data)
    if aid and not snapshot.anyDebuffAuraInstanceID then
        snapshot.anyDebuffAuraInstanceID = aid
    end
    local dispelName = ValidDispelName(data.dispelName)
    if dispelName then
        snapshot.anyDispelType = true
        snapshot.anyDispelName = snapshot.anyDispelName or dispelName
        snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or aid
    end
    if DispelState.AuraCanActivePlayerDispel(data) then
        snapshot.anyDispelType = true
        snapshot.anyDispelName = snapshot.anyDispelName or dispelName or "DISPELLABLE"
        snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or aid
        snapshot.dispellableByMe = true
        snapshot.dispellable = true
        snapshot.dispelName = snapshot.dispelName or dispelName
        snapshot.dispelAuraInstanceID = snapshot.dispelAuraInstanceID or aid
    end
    if PlainTrue(data.isFromPlayerOrPlayerPet) then
        snapshot.playerCastDebuff = true
        snapshot.byMe = true
        snapshot.playerAuraInstanceID = snapshot.playerAuraInstanceID or aid
    end
end

local function ScanDispelType(snapshot, unit, maxAuras)
    maxAuras = maxAuras or 40
    if snapshot.anyDispelType == true then
        snapshot._scannedAnyDispelType = true
        return
    end
    if not GetAuraDataByIndex then
        snapshot._scannedAnyDispelType = true
        snapshot._scanMaxAuras = maxAuras
        return
    end
    for index = 1, maxAuras do
        local data = GetAuraDataByIndex(unit, index, HARMFUL)
        if not data then
            snapshot._scannedAnyDebuff = true
            snapshot._scannedAnyDispelType = true
            snapshot._scanMaxAuras = maxAuras
            return
        end
        DispelState.IndexAura(snapshot, data)
        if snapshot.anyDispelType == true then
            snapshot._scannedAnyDebuff = true
            snapshot._scannedAnyDispelType = true
            snapshot._scanMaxAuras = maxAuras
            return
        end
    end
    snapshot._scannedAnyDebuff = true
    snapshot._scannedAnyDispelType = true
    snapshot._scanMaxAuras = maxAuras
end

local function ScanDispellable(snapshot, unit)
    if snapshot._scannedDispellable == true then return end
    local data = DispelState.FirstAura(unit, HARMFUL_DISPELLABLE)
    if data then
        local aid = AuraInstanceID(data)
        snapshot.anyDebuff = true
        snapshot.anyDispelType = true
        snapshot.dispellableByMe = true
        snapshot.dispellable = true
        snapshot.dispelName = ValidDispelName(data.dispelName) or "DISPELLABLE"
        snapshot.anyDispelName = snapshot.anyDispelName or snapshot.dispelName
        snapshot.anyDebuffAuraInstanceID = snapshot.anyDebuffAuraInstanceID or aid
        snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or aid
        snapshot.dispelAuraInstanceID = snapshot.dispelAuraInstanceID or aid
    end
    snapshot._scannedDispellable = true
end

local function ScanAnyDebuff(snapshot, unit)
    if snapshot._scannedAnyDebuff == true then return end
    local data = DispelState.FirstAura(unit, HARMFUL)
    if data then DispelState.IndexAura(snapshot, data) end
    snapshot._scannedAnyDebuff = true
end

local function ScanPlayerCast(snapshot, unit)
    if snapshot._scannedPlayerCast == true then return end
    local data = DispelState.FirstAura(unit, HARMFUL_PLAYER)
    if data then
        snapshot.playerCastDebuff = true
        snapshot.byMe = true
        snapshot.anyDebuff = true
        snapshot.playerAuraInstanceID = snapshot.playerAuraInstanceID or AuraInstanceID(data)
        snapshot.anyDebuffAuraInstanceID = snapshot.anyDebuffAuraInstanceID or snapshot.playerAuraInstanceID
    end
    snapshot._scannedPlayerCast = true
end

local function ScanStateSatisfies(snapshot, needAnyDebuff, needAnyDispelType, needDispellable, needPlayerCast, maxAuras)
    if needAnyDebuff and snapshot._scannedAnyDebuff ~= true then return false end
    if needAnyDispelType and snapshot.anyDispelType ~= true then
        if snapshot._scannedAnyDispelType ~= true or (snapshot._scanMaxAuras or 0) < maxAuras then
            return false
        end
    end
    if needDispellable and snapshot._scannedDispellable ~= true then return false end
    if needPlayerCast and snapshot._scannedPlayerCast ~= true then return false end
    return true
end

function DispelState.Update(frame, options)
    local isFrame = type(frame) == "table"
    local unit = isFrame and frame.unit or frame
    local snapshot = isFrame and frame._msufDispelState or {}
    if isFrame and not frame._msufDispelState then frame._msufDispelState = snapshot end

    local needAnyDebuff = options and options.needAnyDebuff == true
    local needAnyDispelType = options and options.needAnyDispelType == true
    local needDispellable = options == nil or options.needDispellable ~= false
    local needPlayerCast = options and options.needPlayerCast == true
    local maxAuras = options and options.maxAuras or 40
    local cacheToken = isFrame and (options and options.cacheToken or frame._msufDispatchToken) or nil

    if not (cacheToken and snapshot._cacheToken == cacheToken and snapshot._cacheUnit == unit) then
        ResetSnapshot(snapshot, unit)
        snapshot._cacheToken = cacheToken
        snapshot._cacheUnit = unit
        if not (ExistingUnit(unit) and UnitIsFriendly(unit)) then
            return snapshot
        end
        snapshot.friendly = true
    elseif snapshot.friendly ~= true then
        return snapshot
    elseif ScanStateSatisfies(snapshot, needAnyDebuff, needAnyDispelType, needDispellable, needPlayerCast, maxAuras) then
        return snapshot
    end

    if needDispellable then
        ScanDispellable(snapshot, unit)
    end

    if needAnyDispelType then
        ScanDispelType(snapshot, unit, maxAuras)
    end

    if needAnyDebuff and snapshot.anyDebuff ~= true then
        ScanAnyDebuff(snapshot, unit)
    elseif needAnyDebuff then
        snapshot._scannedAnyDebuff = true
    end

    if needPlayerCast then
        ScanPlayerCast(snapshot, unit)
    end

    return snapshot
end

function DispelState.ActiveForTrigger(snapshot, trigger, borderActive)
    if not snapshot then return false end
    trigger = CanonicalOverlayTrigger(trigger)
    if trigger == "BORDER" then return borderActive == true end
    if trigger == "ANY_DEBUFF" then return snapshot.anyDebuff == true end
    if trigger == "DISPEL_TYPE" then return snapshot.anyDispelType == true end
    if trigger == "PLAYER_CAST" then return snapshot.playerCastDebuff == true end
    return snapshot.dispellableByMe == true or snapshot.dispellable == true
end

local function ColorObject(r, g, b, a)
    if CreateColor then return CreateColor(r, g, b, a or 1) end
    return nil
end

local function ColorRGB(color)
    if not color then return nil end
    if color.GetRGBA then return color:GetRGBA() end
    return color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4]
end

local function TypeColor(cfg, key)
    local def = TYPE_DEFAULTS[key]
    local prefix = "type" .. key
    return Number(cfg and cfg[prefix .. "R"], def and def[1] or 0.25),
        Number(cfg and cfg[prefix .. "G"], def and def[2] or 0.75),
        Number(cfg and cfg[prefix .. "B"], def and def[3] or 1)
end

local function CurveKey(cfg)
    return tostring(Number(cfg and cfg.typeMagicR, TYPE_DEFAULTS.Magic[1])) .. ":"
        .. tostring(Number(cfg and cfg.typeMagicG, TYPE_DEFAULTS.Magic[2])) .. ":"
        .. tostring(Number(cfg and cfg.typeMagicB, TYPE_DEFAULTS.Magic[3])) .. ":"
        .. tostring(Number(cfg and cfg.typeCurseR, TYPE_DEFAULTS.Curse[1])) .. ":"
        .. tostring(Number(cfg and cfg.typeCurseG, TYPE_DEFAULTS.Curse[2])) .. ":"
        .. tostring(Number(cfg and cfg.typeCurseB, TYPE_DEFAULTS.Curse[3])) .. ":"
        .. tostring(Number(cfg and cfg.typeDiseaseR, TYPE_DEFAULTS.Disease[1])) .. ":"
        .. tostring(Number(cfg and cfg.typeDiseaseG, TYPE_DEFAULTS.Disease[2])) .. ":"
        .. tostring(Number(cfg and cfg.typeDiseaseB, TYPE_DEFAULTS.Disease[3])) .. ":"
        .. tostring(Number(cfg and cfg.typePoisonR, TYPE_DEFAULTS.Poison[1])) .. ":"
        .. tostring(Number(cfg and cfg.typePoisonG, TYPE_DEFAULTS.Poison[2])) .. ":"
        .. tostring(Number(cfg and cfg.typePoisonB, TYPE_DEFAULTS.Poison[3])) .. ":"
        .. tostring(Number(cfg and cfg.typeBleedR, TYPE_DEFAULTS.Bleed[1])) .. ":"
        .. tostring(Number(cfg and cfg.typeBleedG, TYPE_DEFAULTS.Bleed[2])) .. ":"
        .. tostring(Number(cfg and cfg.typeBleedB, TYPE_DEFAULTS.Bleed[3]))
end

local cachedCurve, cachedCurveKey

function DispelState.ColorCurve(cfg)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local key = CurveKey(cfg or {})
    if cachedCurve and cachedCurveKey == key then return cachedCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then return nil end
    if curve.SetType and Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Step) end
    if curve.AddPoint then
        curve:AddPoint(0, ColorObject(Number(cfg and cfg.r, 0.25), Number(cfg and cfg.g, 0.75), Number(cfg and cfg.b, 1), 1))
        for dispelType, index in pairs(TYPE_INDEX) do
            local r, g, b = TypeColor(cfg, dispelType)
            curve:AddPoint(index, ColorObject(r, g, b, 1))
        end
    end
    cachedCurve, cachedCurveKey = curve, key
    return curve
end

function DispelState.ColorForAura(unit, auraInstanceID, cfg, alpha)
    alpha = Clamp01(alpha, cfg and cfg.a or 1)
    if cfg and cfg.colorMode == "TYPE" and unit and auraInstanceID and GetAuraDispelTypeColor then
        local curve = DispelState.ColorCurve(cfg)
        if curve then
            local color = GetAuraDispelTypeColor(unit, auraInstanceID, curve)
            local r, g, b = ColorRGB(color)
            if r and g and b then return r, g, b, alpha end
        end
    end
    return Number(cfg and cfg.r, 0.25), Number(cfg and cfg.g, 0.75), Number(cfg and cfg.b, 1), alpha
end

function DispelState.AuraIDForTrigger(snapshot, trigger)
    if not snapshot then return nil end
    trigger = CanonicalOverlayTrigger(trigger)
    if trigger == "ANY_DEBUFF" then
        return snapshot.anyDebuffAuraInstanceID
    elseif trigger == "DISPEL_TYPE" then
        return snapshot.anyDispelAuraInstanceID or snapshot.dispelAuraInstanceID
    elseif trigger == "PLAYER_CAST" then
        return snapshot.playerAuraInstanceID
    elseif trigger == "BORDER" then
        return snapshot.borderAuraInstanceID or snapshot.dispelAuraInstanceID or snapshot.anyDispelAuraInstanceID
    end
    return snapshot.dispelAuraInstanceID or snapshot.anyDispelAuraInstanceID
end

function DispelState.ColorForTrigger(snapshot, trigger, cfg, alpha)
    local unit = snapshot and snapshot.unit
    local auraInstanceID = DispelState.AuraIDForTrigger(snapshot, trigger)
    return DispelState.ColorForAura(unit, auraInstanceID, cfg, alpha)
end
