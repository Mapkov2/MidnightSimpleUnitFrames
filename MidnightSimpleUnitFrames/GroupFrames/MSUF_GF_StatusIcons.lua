-- MSUF_GF_StatusIcons.lua
-- Group frame role, raid, leader, ready-check, summon, resurrection, and phase icons.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected
local UnitIsPlayer = _G.UnitIsPlayer
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitPhaseReason = _G.UnitPhaseReason
local UnitHasIncomingResurrection = _G.UnitHasIncomingResurrection
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetReadyCheckStatus = _G.GetReadyCheckStatus
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local C_IncomingSummon = _G.C_IncomingSummon
local C_Timer = _G.C_Timer

local ICON_TEX = {
    ready     = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notReady  = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting   = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    resurrect = "Interface\\RaidFrame\\Raid-Icon-Rez",
    phase     = "Interface\\TargetingFrame\\UI-PhasingIcon",
}

local SUMMON_TEX = {
    [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}

function GF._UpdatePowerRoleVisibility(f, unit)
    if not f.power then return false end
    local c = f._c
    local hidden = false
    if c then
        local role = (GF.GetUnitGroupRole and GF.GetUnitGroupRole(unit))
            or ((UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit)) or "DAMAGER")
        role = (GF.NormalizeGroupRole and GF.NormalizeGroupRole(role)) or role
        if GF.GetEffectivePowerHeight then
            hidden = GF.GetEffectivePowerHeight(f._msufGFKind or "party", unit, role) <= 0
        else
            hidden = (role == "TANK" and not c.powTank)
                or (role == "HEALER" and not c.powHealer)
                or (role == "DAMAGER" and not c.powDPS) or false
        end
    end

    local prev = f._msufGFPowRoleHidden
    f._msufGFPowRoleHidden = hidden
    if prev ~= nil and prev ~= hidden then
        -- RegisterUnitEvent is legal in combat; keep UNIT_POWER_* subscriptions
        -- aligned with the current role even when the visual relayout must wait.
        if f._msufGFRegEv and GF.RegisterUnitEvents and unit then
            GF.RegisterUnitEvents(f, unit)
        end
        if not (InCombatLockdown and InCombatLockdown()) and GF.MarkDirty then
            GF.MarkDirty(f, (GF.DIRTY_GEOMETRY or 0x01) + (GF.DIRTY_LAYOUT or 0x20))
        end
    end
    return hidden
end

function GF.UpdateRoleIcon(f, unit)
    if not f.roleIcon then
        GF._UpdatePowerRoleVisibility(f, unit)
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if not unit or not UnitExists(unit) then
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        f._msufGFPowRoleHidden = false
        return
    end
    if conf.roleIcon == false then
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        GF._UpdatePowerRoleVisibility(f, unit)
        return
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)

    GF._UpdatePowerRoleVisibility(f, unit)

    if role and role ~= "NONE" then
        local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
        if tex then
            f.roleIcon:SetTexture(tex)
            f.roleIcon:SetTexCoord(l, r, t, b)
            if not f.roleIcon:IsShown() then f.roleIcon:Show() end
        else
            if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        end
    else
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
    end
end

function GF.UpdateRaidMarker(f, unit)
    if not f.raidIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.raidMarker == false or not unit or not UnitExists(unit) then
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        if not f.raidIcon:IsShown() then f.raidIcon:Show() end
    else
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
    end
end

function GF.UpdateLeaderIcon(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if f.leaderIcon then
        if conf.leaderIcon == false or not unit or not UnitExists(unit) then
            if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
        else
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                f.leaderIcon:SetTexture(tex)
                f.leaderIcon:SetTexCoord(l, r, t, b)
                if not f.leaderIcon:IsShown() then f.leaderIcon:Show() end
            else
                if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
            end
        end
    end
    if f.assistIcon then
        if conf.assistIcon == false or not unit or not UnitExists(unit) then
            if f.assistIcon:IsShown() then f.assistIcon:Hide() end
        else
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isAssist and not isLeader then
                local tex, l, r, t, b = GF.GetAssistTexture(kind)
                f.assistIcon:SetTexture(tex)
                f.assistIcon:SetTexCoord(l, r, t, b)
                if not f.assistIcon:IsShown() then f.assistIcon:Show() end
            else
                if f.assistIcon:IsShown() then f.assistIcon:Hide() end
            end
        end
    end
end

local _readyCheckTimers = {}

function GF.CancelReadyCheckTimer(f)
    if f then _readyCheckTimers[f] = nil end
end

function GF.UpdateReadyCheck(f, unit, event)
    if not f.readyCheckIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.readyCheckIcon == false or not unit then
        f.readyCheckIcon:Hide()
        GF.CancelReadyCheckTimer(f)
        return
    end

    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.ready)
        f.readyCheckIcon:Show()
    elseif status == "notready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.notReady)
        f.readyCheckIcon:Show()
    elseif status == "waiting" then
        f.readyCheckIcon:SetTexture(ICON_TEX.waiting)
        f.readyCheckIcon:Show()
    else
        if event == "READY_CHECK_FINISHED" and f.readyCheckIcon:IsShown() then
            GF.CancelReadyCheckTimer(f)
            local token = {}
            _readyCheckTimers[f] = token
            C_Timer.After(6, function()
                if _readyCheckTimers[f] ~= token then return end
                _readyCheckTimers[f] = nil
                if f.readyCheckIcon then
                    f.readyCheckIcon:Hide()
                end
            end)
        else
            f.readyCheckIcon:Hide()
        end
    end
end

function GF.UpdateSummonIcon(f, unit)
    if not f.summonIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.summonIcon == false or not unit then
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
        return
    end
    local status
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        status = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local tex = status and SUMMON_TEX[status]
    if tex then
        f.summonIcon:SetTexture(tex)
        f.summonIcon:Show()
        f._msufGFSummonActive = true
    else
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
    end
end

function GF.UpdateResurrectIcon(f, unit)
    if not f.resurrectIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.resurrectIcon == false or not unit then
        f.resurrectIcon:Hide()
        return
    end
    if f._msufGFSummonActive then
        f.resurrectIcon:Hide()
        return
    end
    local show = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if show then
        f.resurrectIcon:SetTexture(ICON_TEX.resurrect)
        f.resurrectIcon:Show()
    else
        f.resurrectIcon:Hide()
    end
end

function GF.UpdatePhaseIcon(f, unit)
    if not f.phaseIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.phaseIcon == false or not unit then
        f.phaseIcon:Hide()
        return
    end
    local reason
    if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason then
        local conn = UnitIsConnected(unit)
        if issecretvalue and issecretvalue(conn) then conn = true end
        if conn then reason = UnitPhaseReason(unit) end
    end
    if reason then
        f.phaseIcon:SetTexture(ICON_TEX.phase)
        f.phaseIcon:Show()
    else
        f.phaseIcon:Hide()
    end
end
