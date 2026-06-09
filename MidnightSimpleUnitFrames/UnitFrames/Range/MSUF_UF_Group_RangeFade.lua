local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local tonumber = tonumber
local type = type
local pairs = pairs
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitGUID = UnitGUID
local UnitInRange = UnitInRange
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end

local RANGE_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
}
local OFFLINE_EVENTS = { "UNIT_CONNECTION" }
local RANGE_OFFLINE_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
    "UNIT_CONNECTION",
}
local RANGE_SETTLE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_DIFFICULTY_CHANGED",
    "PLAYER_REGEN_ENABLED",
}
local RANGE_SETTLE_EVENT = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED_NEW_AREA = true,
    PLAYER_DIFFICULTY_CHANGED = true,
    PLAYER_REGEN_ENABLED = true,
}
local EMPTY_EVENTS = {}

local GroupRangeFade = {}

function GroupRangeFade.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.group
        and (spec.group.rangeFadeEnabled == true or spec.group.hideOfflineEnabled == true)
end

function GroupRangeFade.GetUnitlessEvents(frame, spec)
    if GroupRangeFade.IsEnabled(frame, spec) then
        return RANGE_SETTLE_EVENTS
    end
    return EMPTY_EVENTS
end

local function SafeBool(value)
    if IsSecret(value) then
        return nil
    end
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    return nil
end

local function ClearRange(frame)
    if not frame then return end
    frame._msufGFRangeUnit = frame.unit
    frame._msufGFRangeKnown = nil
    frame._msufGFInRangeRaw = nil
    frame._msufGFRangeCacheable = nil
end

local function ClearOfflineDelay(frame)
    if not frame then return end
    frame._msufGFOfflineDelayToken = (frame._msufGFOfflineDelayToken or 0) + 1
    frame._msufGFOfflineDelayUnit = nil
    frame._msufGFOfflineDelayReady = nil
end

local function StoreRange(frame, inRange)
    if not frame then return false end
    local unit = frame.unit
    local unitChanged = frame._msufGFRangeUnit ~= unit
    frame._msufGFRangeUnit = unit

    if IsNil(inRange) then
        if not unitChanged and frame._msufGFRangeKnown == nil and frame._msufGFInRangeRaw == nil then
            return false
        end
        frame._msufGFRangeKnown = nil
        frame._msufGFInRangeRaw = nil
        frame._msufGFRangeCacheable = nil
        return true
    end

    local cacheable = not IsSecret(inRange)
    if cacheable and not unitChanged and frame._msufGFRangeCacheable == true
        and frame._msufGFRangeKnown == true and frame._msufGFInRangeRaw == inRange then
        return false
    end

    frame._msufGFRangeKnown = true
    frame._msufGFInRangeRaw = inRange
    frame._msufGFRangeCacheable = cacheable and true or nil
    return true
end

local function UnitIsPlayer(unit)
    if not (unit and unit ~= "") then
        return false
    end
    if unit == "player" then
        return true
    end
    if UnitGUID then
        local guid = UnitGUID(unit)
        local playerGuid = UnitGUID("player")
        if IsSecret(guid) or IsSecret(playerGuid) then
            return false
        end
        return guid ~= nil and guid == playerGuid
    end
    return false
end

function GroupRangeFade.GetEvents(frame, spec)
    local cfg = spec and spec.group
    local range = cfg and cfg.rangeFadeEnabled == true
    local offline = cfg and cfg.hideOfflineEnabled == true
    if range and offline then
        return RANGE_OFFLINE_EVENTS
    elseif range then
        return RANGE_EVENTS
    elseif offline then
        return OFFLINE_EVENTS
    end
    return EMPTY_EVENTS
end

local ApplyAlpha
local rangeSettleQueued
local rangeSettleAfterCombat

local function PlainUnitExists(unit)
    if not (unit and unit ~= "") then
        return false
    end
    if not UnitExists then
        return true
    end
    local exists = UnitExists(unit)
    if IsSecret(exists) then
        return true
    end
    return exists == true or exists == 1
end

local function PollCurrentRange(unit)
    if UnitIsPlayer(unit) then
        return true, true
    end
    if not (UnitInRange and PlainUnitExists(unit)) then
        return nil, false
    end
    local inRange, checked = UnitInRange(unit)
    if IsSecret(checked) then
        return inRange, true
    end
    if checked == true or checked == 1 then
        return inRange, true
    end
    return nil, false
end

local function RefreshSettledRange(frame)
    if not (frame and frame.MSUFSpec and GroupRangeFade.IsEnabled(frame, frame.MSUFSpec)) then
        return
    end
    local value, checked = PollCurrentRange(frame.unit)
    if not checked then
        value = nil
    end
    if StoreRange(frame, value) then
        ApplyAlpha(frame)
    end
end

local function FlushRangeSettle()
    rangeSettleQueued = nil
    if InCombatLockdown and InCombatLockdown() then
        rangeSettleAfterCombat = true
        return
    end
    rangeSettleAfterCombat = nil

    local list = GF and GF.frameList
    if type(list) == "table" then
        for i = 1, #list do
            local frame = list[i]
            if frame and (not GF.frames or GF.frames[frame] == true) then
                RefreshSettledRange(frame)
            end
        end
        return
    end

    local frames = GF and GF.frames
    if type(frames) == "table" then
        for frame in pairs(frames) do
            RefreshSettledRange(frame)
        end
    end
end

local function QueueRangeSettle(delay)
    if InCombatLockdown and InCombatLockdown() then
        rangeSettleAfterCombat = true
        return
    end
    if rangeSettleQueued then
        return
    end
    rangeSettleQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, FlushRangeSettle)
    else
        FlushRangeSettle()
    end
end

local function SetAlphaCached(region, alpha, key)
    if region and region.SetAlpha and region[key] ~= alpha then
        region:SetAlpha(alpha)
        region[key] = alpha
    end
end

local function ClearAlphaCaches(frame)
    if not frame then return end
    frame._msufGFRangeFrameAlpha = nil
    frame._msufGFRangeHealthAlpha = nil
    frame._msufGFRangeHealthBool = nil
    frame._msufGFRangeHealthBoolIn = nil
    frame._msufGFRangeHealthBoolOut = nil
end

local function StatusTexture(bar)
    if not (bar and bar.GetStatusBarTexture) then
        return nil
    end
    local tex = bar._msufGFStatusBarTextureWidget
    if tex == nil then
        tex = bar:GetStatusBarTexture()
        bar._msufGFStatusBarTextureWidget = tex or false
    end
    return tex ~= false and tex or nil
end

local function SetStatusAlpha(bar, alpha, key)
    SetAlphaCached(bar, alpha, key)
    local tex = StatusTexture(bar)
    if tex and tex ~= bar then
        SetAlphaCached(tex, alpha, key .. "Tex")
    end
end

local function SetTextureAlpha(tex, alpha, key)
    SetAlphaCached(tex, alpha, key)
end

local function SetStatusAlphaFromBoolean(bar, value, inAlpha, outAlpha)
    local applied = false
    if bar and bar.SetAlphaFromBoolean then
        bar:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        applied = true
    end
    local tex = StatusTexture(bar)
    if tex and tex.SetAlphaFromBoolean then
        tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        applied = true
    end
    return applied
end

local function SetTextureAlphaFromBoolean(tex, value, inAlpha, outAlpha)
    if tex and tex.SetAlphaFromBoolean then
        tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        return true
    end
    return false
end

local function RefreshHealthVisual(frame)
    local element = UF.elements and UF.elements.GroupVisuals
    if frame and frame._msufActiveElements and frame._msufActiveElements.GroupVisuals == true and element and element.Update then
        element.Update(frame, "MSUF_GF_RANGE_ALPHA", frame.unit)
        return true
    end
    return false
end

local function ApplyHealthRangeAlpha(frame, alpha)
    alpha = tonumber(alpha) or 1
    if frame._msufGFRangeHealthAlpha == alpha and frame._msufGFRangeHealthBool == nil then
        return
    end
    frame._msufGFRangeHealthAlpha = alpha
    frame._msufGFRangeHealthBool = nil
    frame._msufGFRangeHealthBoolIn = nil
    frame._msufGFRangeHealthBoolOut = nil
    local refreshed = RefreshHealthVisual(frame)
    if not refreshed then
        SetStatusAlpha(frame.hpBar or frame.Health, alpha, "_msufGFRangeHealth")
        SetTextureAlpha(frame.bg, alpha, "_msufGFRangeHealthBg")
        SetTextureAlpha(frame.hpBarBG, alpha, "_msufGFRangeHealthBg")
    end
    SetStatusAlpha(frame.incomingHealBar, alpha, "_msufGFRangePredict")
    SetStatusAlpha(frame.absorbBar, alpha, "_msufGFRangePredict")
    SetStatusAlpha(frame.healAbsorbBar, alpha, "_msufGFRangePredict")
end

local function ApplyHealthRangeAlphaFromBoolean(frame, value, inAlpha, outAlpha)
    local cacheable = not IsSecret(value)
    if cacheable
        and frame._msufGFRangeHealthBool == value
        and frame._msufGFRangeHealthBoolIn == inAlpha
        and frame._msufGFRangeHealthBoolOut == outAlpha then
        return true
    end
    frame._msufGFRangeHealthAlpha = nil
    local applied = SetStatusAlphaFromBoolean(frame.hpBar or frame.Health, value, inAlpha, outAlpha)
    applied = SetTextureAlphaFromBoolean(frame.bg, value, inAlpha, outAlpha) or applied
    applied = SetTextureAlphaFromBoolean(frame.hpBarBG, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.incomingHealBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.absorbBar, value, inAlpha, outAlpha) or applied
    applied = SetStatusAlphaFromBoolean(frame.healAbsorbBar, value, inAlpha, outAlpha) or applied
    if applied and cacheable then
        frame._msufGFRangeHealthBool = value
        frame._msufGFRangeHealthBoolIn = inAlpha
        frame._msufGFRangeHealthBoolOut = outAlpha
    else
        frame._msufGFRangeHealthBool = nil
        frame._msufGFRangeHealthBoolIn = nil
        frame._msufGFRangeHealthBoolOut = nil
    end
    return applied
end

local function CoreAlpha(frame)
    local spec = frame and frame.MSUFSpec
    local alpha = spec and spec.alpha
    if alpha and alpha.active == true then
        local element = UF.elements and UF.elements.Alpha
        if frame._msufAlphaEffective == nil and element and element.Apply then
            element.Apply(frame, spec)
        end
        return tonumber(frame._msufAlphaEffective) or 1
    end
    return 1
end

local function OfflineHideReady(frame, cfg)
    local delay = tonumber(cfg and cfg.hideOfflineDelay) or 0
    if delay <= 0 or not (C_Timer and C_Timer.After) then
        return true
    end
    local unit = frame and frame.unit
    if frame._msufGFOfflineDelayUnit == unit and frame._msufGFOfflineDelayReady == true then
        return true
    end
    if frame._msufGFOfflineDelayUnit == unit and frame._msufGFOfflineDelayPending == true then
        return false
    end

    local token = (frame._msufGFOfflineDelayToken or 0) + 1
    frame._msufGFOfflineDelayToken = token
    frame._msufGFOfflineDelayUnit = unit
    frame._msufGFOfflineDelayPending = true
    frame._msufGFOfflineDelayReady = nil

    C_Timer.After(delay, function()
        if not frame or frame._msufGFOfflineDelayToken ~= token or frame.unit ~= unit then
            return
        end
        frame._msufGFOfflineDelayPending = nil
        frame._msufGFOfflineDelayReady = true
        if ApplyAlpha then
            ApplyAlpha(frame)
        end
    end)
    return false
end

local function BaseAlpha(frame)
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.group
    if not cfg then return 1, false end
    local unit = frame.unit
    if frame._msufGFRangeUnit ~= unit then
        ClearRange(frame)
    end
    local base = CoreAlpha(frame)
    local exists = unit ~= nil
    if UnitExists then
        local existsRaw = UnitExists(unit)
        exists = IsSecret(existsRaw) or existsRaw == true or existsRaw == 1
    end
    local connected = UnitIsConnected and exists and UnitIsConnected(unit)
    if not IsSecret(connected) and (connected == false or connected == 0) then
        if cfg.hideOfflineEnabled == true and (not (InCombatLockdown and InCombatLockdown()) or cfg.hideOfflineInCombat == true) then
            if OfflineHideReady(frame, cfg) then
                return 0, true
            end
        end
        return base * (cfg.offlineAlpha or 0.5), true
    end
    ClearOfflineDelay(frame)
    return base, false
end

function ApplyAlpha(frame)
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.group
    local baseAlpha, baseLocked = BaseAlpha(frame)
    if baseLocked == true then
        ApplyHealthRangeAlpha(frame, 1)
        SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
        return
    end

    if cfg and cfg.rangeFadeEnabled == true and frame._msufGFRangeKnown == true then
        local inRange = frame._msufGFInRangeRaw
        if cfg.rangeFadeLayerMode == "health" then
            SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
            local rangeAlpha = cfg.rangeFadeAlpha or 0.4
            if not IsNil(inRange) and ApplyHealthRangeAlphaFromBoolean(frame, inRange, 1, rangeAlpha) then
                return
            end
            local safe = SafeBool(inRange)
            if safe ~= nil then
                ApplyHealthRangeAlpha(frame, safe and 1 or rangeAlpha)
                return
            end
            ApplyHealthRangeAlpha(frame, 1)
            return
        end
        ApplyHealthRangeAlpha(frame, 1)
        if frame.SetAlphaFromBoolean and not IsNil(inRange) then
            frame:SetAlphaFromBoolean(inRange, baseAlpha, baseAlpha * (cfg.rangeFadeAlpha or 0.4))
            frame._msufGFRangeFrameAlpha = nil
            return
        end

        local safe = SafeBool(inRange)
        if safe ~= nil then
            SetAlphaCached(frame, baseAlpha * (safe and 1 or (cfg.rangeFadeAlpha or 0.4)), "_msufGFRangeFrameAlpha")
            return
        end
    end

    ApplyHealthRangeAlpha(frame, 1)
    SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
end

function GroupRangeFade.Apply(frame)
    ClearAlphaCaches(frame)
    local isPlayer = UnitIsPlayer and UnitIsPlayer(frame and frame.unit)
    if not IsSecret(isPlayer) and isPlayer then
        StoreRange(frame, true)
    else
        -- No initial range poll here. Group range fade is driven only by
        -- UNIT_IN_RANGE_UPDATE plus the related phase/party option events.
        StoreRange(frame, nil)
    end
    ApplyAlpha(frame)
end

function GroupRangeFade.Update(frame, event, unit, inRange)
    local changed = false
    if event == "UNIT_IN_RANGE_UPDATE" then
        if not unit or unit == "" or unit == frame.unit then
            changed = StoreRange(frame, UnitIsPlayer(frame and frame.unit) and true or inRange)
        end
    elseif event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" or event == "UNIT_OTHER_PARTY_CHANGED" then
        if not unit or unit == "" or unit == frame.unit then
            changed = StoreRange(frame, UnitIsPlayer(frame and frame.unit) and true or nil)
        end
    elseif event == "UNIT_CONNECTION" then
        changed = true
    elseif RANGE_SETTLE_EVENT[event] then
        if event ~= "PLAYER_REGEN_ENABLED" or rangeSettleAfterCombat == true then
            QueueRangeSettle(event == "PLAYER_ENTERING_WORLD" and 0.2 or 0)
        end
        return
    end
    if changed then
        ApplyAlpha(frame)
    end
end

function GroupRangeFade.Disable(frame)
    ClearRange(frame)
    ClearAlphaCaches(frame)
    ApplyHealthRangeAlpha(frame, 1)
    SetAlphaCached(frame, CoreAlpha(frame), "_msufGFRangeFrameAlpha")
end

UF.RegisterElement("GroupRangeFade", GroupRangeFade)
