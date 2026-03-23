local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local UnitHealthPercent = UnitHealthPercent
local UnitHealthMax = UnitHealthMax
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitName = UnitName
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitPowerPercent = UnitPowerPercent
local UnitPowerType = UnitPowerType
local UnitIsUnit = UnitIsUnit
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor
local issecretvalue = _G.issecretvalue

local owner = {}
local hpCurve

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

local function ScopeForFrame(frame, unit)
    if frame and frame._groupScope then return frame._groupScope end
    local fn = _G.MSUF_Group_GetScopeForUnit
    if type(fn) == "function" then
        return fn(unit)
    end
    return "party"
end

local function EnsureCurve()
    if hpCurve or not C_CurveUtil or not Enum or not Enum.LuaCurveType then return end
    hpCurve = C_CurveUtil.CreateColorCurve()
    hpCurve:SetType(Enum.LuaCurveType.Linear)
    hpCurve:AddPoint(0.0, CreateColor(1, 0, 0))
    hpCurve:AddPoint(0.5, CreateColor(1, 1, 0))
    hpCurve:AddPoint(1.0, CreateColor(0, 1, 0))
end

local function GetFrame(unit)
    return Group.activeFrames and Group.activeFrames[unit]
end

local function SafeSetFontStringText(frame, widget, cacheKey, text)
    if not widget then return end
    if IsSecret(text) then
        frame[cacheKey] = nil
        widget:SetText(text)
        return
    end
    if frame[cacheKey] ~= text then
        frame[cacheKey] = text
        widget:SetText(text or "")
    end
end

local function SetRoleIcon(frame, role)
    if not frame or not frame.roleIcon then return end
    local atlas = (role == "TANK" and "roleicon-tank") or (role == "HEALER" and "roleicon-healer") or ((role == "DAMAGER" or role == "DPS") and "roleicon-dps") or nil
    if atlas then
        frame.roleIcon:SetAtlas(atlas, true)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

local function UpdateName(frame, unit)
    if not frame or not frame.nameText then return end
    local scope = ScopeForFrame(frame, unit)
    local showName = _G.MSUF_Group_GetSetting and _G.MSUF_Group_GetSetting(scope, "font", "showName", true) or true
    if showName ~= true then
        frame._lastName = nil
        frame.nameText:SetText("")
        frame.nameText:Hide()
        return
    end
    local name = UnitName(unit) or unit
    SafeSetFontStringText(frame, frame.nameText, "_lastName", name)
    local _, class = UnitClass(unit)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then
        frame.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
    end
    frame.nameText:Show()
end

local function UpdateHealth(frame, unit)
    if not frame or not frame.hpBar then return end
    EnsureCurve()
    local pct = UnitHealthPercent and UnitHealthPercent(unit, true) or 0
    if IsSecret(pct) then
        frame._lastHealthPct = nil
        _G.MSUF_SetBarValue(frame.hpBar, pct, false)
    elseif frame._lastHealthPct ~= pct then
        frame._lastHealthPct = pct
        _G.MSUF_SetBarValue(frame.hpBar, pct, false)
        local colorObj = hpCurve and UnitHealthPercent(unit, true, hpCurve)
        if colorObj and colorObj.GetRGB then
            local r, g, b = colorObj:GetRGB()
            frame.hpBar:SetStatusBarColor(r, g, b)
        end
    end

    if frame.hpText then
        local shared = Shared()
        local scope = ScopeForFrame(frame, unit)
        local showHPText = _G.MSUF_Group_GetSetting and _G.MSUF_Group_GetSetting(scope, "font", "showHPText", shared.showHPText == true) or (shared.showHPText == true)
        if showHPText == true and not IsSecret(pct) then
            local txt = string.format("%d%%", math.floor((pct * 100) + 0.5))
            if frame._lastHPText ~= txt then
                frame._lastHPText = txt
                frame.hpText:SetText(txt)
            end
            frame.hpText:Show()
        else
            frame._lastHPText = nil
            frame.hpText:SetText("")
            frame.hpText:Hide()
        end
    end

    local maxHP = UnitHealthMax and UnitHealthMax(unit)
    if maxHP and not (issecretvalue and issecretvalue(maxHP)) then
        if ns.Bars and ns.Bars._UpdateAbsorbBar then
            ns.Bars._UpdateAbsorbBar(frame, unit, maxHP)
        end
        if ns.Bars and ns.Bars._UpdateHealAbsorbBar then
            ns.Bars._UpdateHealAbsorbBar(frame, unit, maxHP)
        end
        if frame.healPredictionBar and UnitGetIncomingHeals then
            local incoming = UnitGetIncomingHeals(unit)
            if incoming ~= nil and not (issecretvalue and issecretvalue(incoming)) and incoming > 0 then
                frame.healPredictionBar:SetMinMaxValues(0, maxHP)
                _G.MSUF_SetBarValue(frame.healPredictionBar, incoming, false)
                frame.healPredictionBar:Show()
            else
                frame.healPredictionBar:Hide()
            end
        end
    elseif frame.absorbBar then
        frame.absorbBar:Hide()
        if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
        if frame.healPredictionBar then frame.healPredictionBar:Hide() end
    end
end

local function ShouldShowPower(frame, role)
    local db = Shared()
    local scope = frame and frame._groupScope or "party"
    local mode = _G.MSUF_Group_GetSetting and _G.MSUF_Group_GetSetting(scope, "bars", "showPowerBar", db.showPowerBar or "HEALER") or (db.showPowerBar or "HEALER")
    if mode == "NONE" then return false end
    if mode == "ALL" then return true end
    return role == "HEALER"
end

local function UpdatePower(frame, unit, role)
    if not frame or not frame.powerBar then return end
    if not ShouldShowPower(frame, role) then
        frame.powerBar:Hide()
        return
    end
    local pct = UnitPowerPercent(unit, nil, false) or 0
    local pType = UnitPowerType(unit)
    if not IsSecret(pct) and frame._lastPowerPct == pct and frame._lastPowerType == pType and frame.powerBar:IsShown() then return end
    frame._lastPowerPct = IsSecret(pct) and nil or pct
    frame._lastPowerType = pType
    local color = PowerBarColor and PowerBarColor[pType or 0]
    frame.powerBar:SetStatusBarColor((color and color.r) or 0, (color and color.g) or 0.55, (color and color.b) or 1)
    _G.MSUF_SetBarValue(frame.powerBar, pct, false)
    frame.powerBar:Show()
end

local function UpdateState(frame, unit)
    if not frame or not frame.stateText then return end
    local txt
    local connected = UnitIsConnected and UnitIsConnected(unit)
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if connected ~= nil and not IsSecret(connected) and connected ~= true then
        txt = "DC"
    elseif dead ~= nil and not IsSecret(dead) and dead == true then
        txt = "DEAD"
    end
    if frame._lastStateText ~= txt then
        frame._lastStateText = txt
        frame.stateText:SetText(txt or "")
    end
    frame.stateText:SetShown(txt ~= nil)
    if frame.hpText then
        frame.hpText:SetShown((txt == nil) and frame.hpText:GetText() ~= "")
    end
end

local function UpdateOne(unit)
    local frame = GetFrame(unit)
    if not frame then return end
    local role = UnitGroupRolesAssigned(unit) or "NONE"
    UpdateHealth(frame, unit)
    UpdateName(frame, unit)
    SetRoleIcon(frame, role)
    UpdateState(frame, unit)
    UpdatePower(frame, unit, role)
    if frame.UpdateTargetHighlight then
        frame:UpdateTargetHighlight()
    elseif frame.highlightBorder then
        frame.highlightBorder:SetShown(UnitIsUnit(unit, "target"))
    end
end

local function UnitHandler(_, event, unit)
    UpdateOne(unit)
end

function _G.MSUF_Group_RefreshAll()
    if not Group.activeFrames then return end
    for unit in pairs(Group.activeFrames) do
        UpdateOne(unit)
    end
    if type(_G.MSUF_GroupIndicators_RefreshAll) == "function" then _G.MSUF_GroupIndicators_RefreshAll() end
    if type(_G.MSUF_GroupAuras_RefreshAll) == "function" then _G.MSUF_GroupAuras_RefreshAll() end
    if type(_G.MSUF_GroupRange_RefreshAll) == "function" then _G.MSUF_GroupRange_RefreshAll() end
end

Group.AddUnitEvent(owner, "UNIT_HEALTH", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_MAXHEALTH", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_POWER_UPDATE", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_MAXPOWER", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_DISPLAYPOWER", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_ABSORB_AMOUNT_CHANGED", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_HEAL_PREDICTION", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_NAME_UPDATE", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_CONNECTION", UnitHandler)

if type(_G.MSUF_EventBus_Register) == "function" then
    _G.MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_GROUP_TARGET", function()
        _G.MSUF_Group_RefreshAll()
    end)
    _G.MSUF_EventBus_Register("READY_CHECK", "MSUF_GROUP_READY_REFRESH", function()
        _G.MSUF_Group_RefreshAll()
    end)
    _G.MSUF_EventBus_Register("PLAYER_ROLES_ASSIGNED", "MSUF_GROUP_ROLE_REFRESH", function()
        _G.MSUF_Group_RefreshAll()
    end)
end
