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

local function IconShow(icon)
    if icon and icon.IsShown and not icon:IsShown() then icon:Show() end
end

local function IconHide(icon)
    if icon and icon.IsShown and icon:IsShown() then icon:Hide() end
end

local function IconSetTexture(icon, tex)
    if not icon or icon._msufGFCachedTexture == tex then return end
    icon._msufGFCachedTexture = tex
    icon:SetTexture(tex)
end

local function IconSetTexCoord(icon, l, r, t, b)
    if not icon then return end
    if icon._msufGFTexL == l and icon._msufGFTexR == r
        and icon._msufGFTexT == t and icon._msufGFTexB == b
    then
        return
    end
    icon._msufGFTexL = l
    icon._msufGFTexR = r
    icon._msufGFTexT = t
    icon._msufGFTexB = b
    icon:SetTexCoord(l, r, t, b)
end

local function IconSetTextureAndCoords(icon, tex, l, r, t, b)
    IconSetTexture(icon, tex)
    if l ~= nil then IconSetTexCoord(icon, l, r, t, b) end
end

function GF.ResetStatusIconCaches(f)
    if not f then return end
    local icons = {
        f.roleIcon, f.raidIcon, f.leaderIcon, f.assistIcon,
        f.readyCheckIcon, f.summonIcon, f.resurrectIcon, f.phaseIcon,
    }
    for i = 1, #icons do
        local icon = icons[i]
        if icon then
            icon._msufGFCachedTexture = nil
            icon._msufGFTexL = nil
            icon._msufGFTexR = nil
            icon._msufGFTexT = nil
            icon._msufGFTexB = nil
            icon._msufGFRaidMarkerIndex = nil
        end
    end
    f._msufGFSummonActive = nil
end

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
        IconHide(f.roleIcon)
        f._msufGFPowRoleHidden = false
        return
    end
    if conf.roleIcon == false then
        IconHide(f.roleIcon)
        GF._UpdatePowerRoleVisibility(f, unit)
        return
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)

    GF._UpdatePowerRoleVisibility(f, unit)

    if role and role ~= "NONE" then
        local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
        if tex then
            IconSetTextureAndCoords(f.roleIcon, tex, l, r, t, b)
            IconShow(f.roleIcon)
        else
            IconHide(f.roleIcon)
        end
    else
        IconHide(f.roleIcon)
    end
end

function GF.UpdateRaidMarker(f, unit)
    if not f.raidIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.raidMarker == false or not unit or not UnitExists(unit) then
        IconHide(f.raidIcon)
        f.raidIcon._msufGFRaidMarkerIndex = nil
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        -- Midnight/Beta can return a secret number here. Do not cache
        -- or compare it in Lua; hand it directly to the C-side helper.
        f.raidIcon._msufGFRaidMarkerIndex = nil
        f.raidIcon._msufGFCachedTexture = nil
        SetRaidTargetIconTexture(f.raidIcon, idx)
        IconShow(f.raidIcon)
    else
        IconHide(f.raidIcon)
        f.raidIcon._msufGFRaidMarkerIndex = nil
    end
end

function GF.UpdateLeaderIcon(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if f.leaderIcon then
        if conf.leaderIcon == false or not unit or not UnitExists(unit) then
            IconHide(f.leaderIcon)
        else
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                IconSetTextureAndCoords(f.leaderIcon, tex, l, r, t, b)
                IconShow(f.leaderIcon)
            else
                IconHide(f.leaderIcon)
            end
        end
    end
    if f.assistIcon then
        if conf.assistIcon == false or not unit or not UnitExists(unit) then
            IconHide(f.assistIcon)
        else
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isAssist and not isLeader then
                local tex, l, r, t, b = GF.GetAssistTexture(kind)
                IconSetTextureAndCoords(f.assistIcon, tex, l, r, t, b)
                IconShow(f.assistIcon)
            else
                IconHide(f.assistIcon)
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
        IconHide(f.readyCheckIcon)
        GF.CancelReadyCheckTimer(f)
        return
    end

    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        IconSetTexture(f.readyCheckIcon, ICON_TEX.ready)
        IconShow(f.readyCheckIcon)
    elseif status == "notready" then
        IconSetTexture(f.readyCheckIcon, ICON_TEX.notReady)
        IconShow(f.readyCheckIcon)
    elseif status == "waiting" then
        IconSetTexture(f.readyCheckIcon, ICON_TEX.waiting)
        IconShow(f.readyCheckIcon)
    else
        if event == "READY_CHECK_FINISHED" and f.readyCheckIcon:IsShown() then
            GF.CancelReadyCheckTimer(f)
            local token = {}
            _readyCheckTimers[f] = token
            C_Timer.After(6, function()
                if _readyCheckTimers[f] ~= token then return end
                _readyCheckTimers[f] = nil
                if f.readyCheckIcon then
                    IconHide(f.readyCheckIcon)
                end
            end)
        else
            IconHide(f.readyCheckIcon)
        end
    end
end

function GF.UpdateSummonIcon(f, unit)
    if not f.summonIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.summonIcon == false or not unit then
        IconHide(f.summonIcon)
        f._msufGFSummonActive = false
        return
    end
    local status
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        status = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local tex = status and SUMMON_TEX[status]
    if tex then
        IconSetTexture(f.summonIcon, tex)
        IconShow(f.summonIcon)
        f._msufGFSummonActive = true
    else
        IconHide(f.summonIcon)
        f._msufGFSummonActive = false
    end
end

function GF.UpdateResurrectIcon(f, unit)
    if not f.resurrectIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.resurrectIcon == false or not unit then
        IconHide(f.resurrectIcon)
        return
    end
    if f._msufGFSummonActive then
        IconHide(f.resurrectIcon)
        return
    end
    local show = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if show then
        IconSetTexture(f.resurrectIcon, ICON_TEX.resurrect)
        IconShow(f.resurrectIcon)
    else
        IconHide(f.resurrectIcon)
    end
end

function GF.UpdatePhaseIcon(f, unit)
    if not f.phaseIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.phaseIcon == false or not unit then
        IconHide(f.phaseIcon)
        return
    end
    local reason
    if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason then
        local conn = UnitIsConnected(unit)
        if issecretvalue and issecretvalue(conn) then conn = true end
        if conn then reason = UnitPhaseReason(unit) end
    end
    if reason then
        IconSetTexture(f.phaseIcon, ICON_TEX.phase)
        IconShow(f.phaseIcon)
    else
        IconHide(f.phaseIcon)
    end
end
