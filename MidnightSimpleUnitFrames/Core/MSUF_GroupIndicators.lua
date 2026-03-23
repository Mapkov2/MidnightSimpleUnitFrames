local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local pairs = pairs
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitThreatSituation = UnitThreatSituation
local UnitIsAFK = UnitIsAFK
local UnitPhaseReason = UnitPhaseReason
local UnitIsUnit = UnitIsUnit
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local GetReadyCheckStatus = GetReadyCheckStatus
local C_IncomingSummon = C_IncomingSummon
local issecretvalue = _G.issecretvalue

local owner = {}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function RefreshUnit(unit)
    local frame = Group.activeFrames and Group.activeFrames[unit]
    if not frame then return end

    if frame.resIcon then
        frame.resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        frame.resIcon:SetShown(UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit) or false)
    end

    if frame.summonIcon then
        frame.summonIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Summon")
        local shown = false
        if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
            shown = C_IncomingSummon.HasIncomingSummon(unit) and true or false
        end
        frame.summonIcon:SetShown(shown)
    end

    if frame.readyCheckIcon then
        local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
        if status == "ready" then
            frame.readyCheckIcon:SetAtlas("ReadyCheck-Ready", true)
            frame.readyCheckIcon:Show()
        elseif status == "notready" then
            frame.readyCheckIcon:SetAtlas("ReadyCheck-NotReady", true)
            frame.readyCheckIcon:Show()
        elseif status == "waiting" then
            frame.readyCheckIcon:SetAtlas("ReadyCheck-Waiting", true)
            frame.readyCheckIcon:Show()
        else
            frame.readyCheckIcon:Hide()
        end
    end

    if frame.threatBorder then
        local threat = UnitThreatSituation and UnitThreatSituation(unit)
        if threat ~= nil and not IsSecret(threat) and threat > 0 then
            local r, g, b = 1, 1, 0
            if threat >= 3 then r, g, b = 1, 0.1, 0.1 elseif threat == 2 then r, g, b = 1, 0.45, 0 end end
            frame.threatBorder:SetBackdropBorderColor(r, g, b, 0.95)
            frame.threatBorder:Show()
        else
            frame.threatBorder:Hide()
        end
    end

    if frame.selfBorder then
        frame.selfBorder:SetShown(UnitIsUnit and UnitIsUnit(unit, "player") or false)
    end

    if frame.afkText then
        local afk = UnitIsAFK and UnitIsAFK(unit)
        frame.afkText:SetShown(afk and not (_G.MSUF_InCombat == true))
        if afk then frame.afkText:SetText("AFK") end
    end

    if frame.phasedIcon then
        local phaseReason = UnitPhaseReason and UnitPhaseReason(unit)
        frame.phasedIcon:SetShown(phaseReason ~= nil and not IsSecret(phaseReason))
    end

    if frame.raidMarkerIcon then
        local idx = GetRaidTargetIndex and GetRaidTargetIndex(unit)
        if idx then
            SetRaidTargetIconTexture(frame.raidMarkerIcon, idx)
            frame.raidMarkerIcon:Show()
        else
            frame.raidMarkerIcon:Hide()
        end
    end
end

local function UnitHandler(_, event, unit)
    RefreshUnit(unit)
end

function _G.MSUF_GroupIndicators_RefreshAll()
    if not Group.activeFrames then return end
    for unit in pairs(Group.activeFrames) do
        RefreshUnit(unit)
    end
end

Group.AddUnitEvent(owner, "UNIT_THREAT_SITUATION_UPDATE", UnitHandler)
Group.AddUnitEvent(owner, "UNIT_FLAGS", UnitHandler)

if type(_G.MSUF_EventBus_Register) == "function" then
    for _, ev in ipairs({ "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED", "RAID_TARGET_UPDATE", "PLAYER_FLAGS_CHANGED", "PLAYER_TARGET_CHANGED" }) do
        _G.MSUF_EventBus_Register(ev, "MSUF_GROUP_INDICATORS_" .. ev, function()
            _G.MSUF_GroupIndicators_RefreshAll()
        end)
    end
end
