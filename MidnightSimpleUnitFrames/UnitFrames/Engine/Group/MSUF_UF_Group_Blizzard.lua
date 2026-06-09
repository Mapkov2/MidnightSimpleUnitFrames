local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local hooksecurefunc = hooksecurefunc
local type = type
local next = next
local pairs = pairs
local tostring = tostring

local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
local MAX_RAID_GROUPS = _G.NUM_RAID_GROUPS or 8
local MAX_RAID_MEMBERS = _G.MAX_RAID_MEMBERS or 40

local hiddenParent
local eventFrame
local applyScheduled
local hookedSetParent = {}
local hookedShow = {}
local ownedFrames = {}
local pendingHide = {}
local pendingRestore = {}
local lastOwnershipSig
local partyReconcileScheduled
local partyReconcileHideSolo
local rosterEventRegistered = false

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function HiddenParent()
    if hiddenParent then
        return hiddenParent
    end
    hiddenParent = CreateFrame("Frame", "MSUF_GF_BlizzardHiddenParent", UIParent)
    hiddenParent:SetAllPoints()
    hiddenParent:Hide()
    return hiddenParent
end

local function IsForbidden(frame)
    return frame and frame.IsForbidden and frame:IsForbidden()
end

local function ResolveFrame(frame)
    if type(frame) == "string" then
        return _G[frame]
    end
    return frame
end

local function SafeHide(frame)
    if frame and frame.Hide and not IsForbidden(frame) then
        frame:Hide()
    end
end

local function SafeShow(frame)
    if frame and frame.Show and not IsForbidden(frame) then
        frame:Show()
    end
end

local function SafeUnregister(frame)
    if frame and frame.UnregisterAllEvents and not IsForbidden(frame) then
        frame:UnregisterAllEvents()
    end
end

local function SafeSetParent(frame, parent)
    if frame and frame.SetParent and parent and not IsForbidden(frame) then
        frame:SetParent(parent)
    end
end

local function IsHiddenFrameParent(parent)
    return parent
        and parent ~= UIParent
        and parent.IsShown
        and not parent:IsShown()
end

local function EnsureEventFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    return eventFrame
end

local function RegisterRosterEvent()
    if not rosterEventRegistered and not InCombat() then
        EnsureEventFrame():RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterEventRegistered = true
    end
end

local function UnregisterRosterEvent()
    if eventFrame and rosterEventRegistered then
        eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        rosterEventRegistered = false
    end
end

local function DeferHide(frame)
    pendingHide[frame] = true
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function DeferRestore(frame, showAfter)
    pendingRestore[frame] = showAfter and true or false
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function ReparentHidden(frame)
    if not (frame and frame.SetParent) or IsForbidden(frame) then
        return
    end
    local parent = HiddenParent()
    if InCombat() and frame.IsProtected and frame:IsProtected() then
        DeferHide(frame)
        return
    end
    if frame.GetParent and not IsHiddenFrameParent(frame:GetParent()) then
        SafeSetParent(frame, parent)
    end
end

local function ResetParent(frame, parent)
    local info = ownedFrames[frame]
    if not (info and info.hidden) then
        return
    end
    local hidden = HiddenParent()
    if parent == hidden or IsHiddenFrameParent(parent) or IsHiddenFrameParent(frame:GetParent()) then
        return
    end
    ReparentHidden(frame)
end

local function HideIfOwned(frame)
    local info = ownedFrames[frame]
    if info and info.hidden then
        SafeHide(frame)
    end
end

local function HookFrame(frame, doNotReparent)
    if not frame or IsForbidden(frame) then
        return
    end
    if not doNotReparent and frame.SetParent and not hookedSetParent[frame] then
        hooksecurefunc(frame, "SetParent", ResetParent)
        hookedSetParent[frame] = true
    end
    if frame.HookScript and not hookedShow[frame] then
        frame:HookScript("OnShow", HideIfOwned)
        hookedShow[frame] = true
    end
end

local function UnregisterKnownChildren(frame)
    if not frame then
        return
    end
    SafeUnregister(frame.healthBar or frame.healthbar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))
    SafeUnregister(frame.manabar or frame.ManaBar or frame.PowerBar)
    SafeUnregister(frame.castBar or frame.spellbar or frame.CastingBarFrame)
    SafeUnregister(frame.powerBarAlt or frame.PowerBarAlt)
    SafeUnregister(frame.BuffFrame or frame.AurasFrame)
    SafeUnregister(frame.DebuffFrame)
    SafeUnregister(frame.petFrame or frame.PetFrame)
    SafeUnregister(frame.totFrame or frame.TargetFrameToT)
    SafeUnregister(frame.CcRemoverFrame)
end

local function HardHideFrame(frame, doNotReparent)
    frame = ResolveFrame(frame)
    if not frame or IsForbidden(frame) then
        return nil
    end

    local info = ownedFrames[frame]
    if not info then
        info = { parent = frame.GetParent and frame:GetParent() or UIParent }
        ownedFrames[frame] = info
    elseif info.parent == nil and frame.GetParent then
        info.parent = frame:GetParent()
    end
    info.hidden = true
    info.hard = true
    info.doNotReparent = doNotReparent and true or false

    SafeUnregister(frame)
    UnregisterKnownChildren(frame)
    SafeHide(frame)
    HookFrame(frame, doNotReparent)

    if not doNotReparent then
        ReparentHidden(frame)
    end
    return frame
end

local function SoftHideFrame(frame, doNotReparent)
    frame = ResolveFrame(frame)
    if not frame or IsForbidden(frame) then
        return nil
    end

    local info = ownedFrames[frame]
    if not info then
        info = { parent = frame.GetParent and frame:GetParent() or UIParent }
        ownedFrames[frame] = info
    end
    info.hidden = true
    info.hard = info.hard == true
    info.doNotReparent = doNotReparent and true or false

    SafeHide(frame)
    HookFrame(frame, doNotReparent)
    if not doNotReparent then
        ReparentHidden(frame)
    end
    return frame
end

local function RestoreFrame(frame, showAfter)
    frame = ResolveFrame(frame)
    if not frame or IsForbidden(frame) then
        return
    end
    local info = ownedFrames[frame]
    if not info then
        return
    end

    info.hidden = false
    pendingHide[frame] = nil

    if InCombat() and frame.IsProtected and frame:IsProtected() then
        DeferRestore(frame, showAfter)
        return
    end

    local hidden = HiddenParent()
    local parent = info.parent or UIParent
    if frame.GetParent and frame:GetParent() == hidden then
        SafeSetParent(frame, parent)
    end
    if showAfter then
        SafeShow(frame)
    end
end

local function ForEachPoolActive(pool, fn)
    if not (pool and pool.EnumerateActive) then
        return
    end
    for frame in pool:EnumerateActive() do
        if frame then
            fn(frame)
        end
    end
end

local function ForEachFrameTable(list, fn)
    if type(list) ~= "table" then
        return
    end
    for _, frame in pairs(list) do
        if type(frame) == "table" then
            fn(frame)
        end
    end
end

local function RefreshBlizzardParty()
    if type(_G.PartyFrame_Update) == "function" and _G.PartyFrame then
        _G.PartyFrame_Update(_G.PartyFrame)
    end
    if type(_G.CompactPartyFrame_UpdateShown) == "function" then
        _G.CompactPartyFrame_UpdateShown()
    end
end

local function RefreshBlizzardRaid()
    if type(_G.CompactRaidFrameManager_UpdateShown) == "function" then
        _G.CompactRaidFrameManager_UpdateShown()
    end
    if type(_G.CompactRaidFrameContainer_TryUpdate) == "function" then
        _G.CompactRaidFrameContainer_TryUpdate(_G.CompactRaidFrameContainer)
    end
    if type(_G.CompactRaidFrameManager_UpdateOptionsFlowContainer) == "function" then
        _G.CompactRaidFrameManager_UpdateOptionsFlowContainer()
    end
end

local function HidePartyFrames(hard)
    local hide = hard and HardHideFrame or SoftHideFrame
    hide(_G.PartyFrame)
    if _G.PartyFrame then
        ForEachPoolActive(_G.PartyFrame.PartyMemberFramePool, function(frame)
            hide(frame, true)
        end)
    end
    hide(_G.CompactPartyFrame)
    hide(_G.CompactPartyFrameTitle)
    if _G.CompactPartyFrame then
        ForEachFrameTable(_G.CompactPartyFrame.memberUnitFrames, function(frame)
            hide(frame, true)
        end)
    end
    for i = 1, MEMBERS_PER_RAID_GROUP do
        hide(_G["CompactPartyFrameMember" .. i])
    end
    for i = 1, 4 do
        hide(_G["PartyMemberFrame" .. i])
        hide(_G["PartyMemberFrame" .. i .. "PetFrame"])
    end
end

local function SoftHidePartyFramesOnly()
    SafeHide(_G.PartyFrame)
    if _G.PartyFrame then
        ForEachPoolActive(_G.PartyFrame.PartyMemberFramePool, function(frame)
            SafeHide(frame)
        end)
    end
    SafeHide(_G.CompactPartyFrame)
    SafeHide(_G.CompactPartyFrameTitle)
    if _G.CompactPartyFrame then
        ForEachFrameTable(_G.CompactPartyFrame.memberUnitFrames, function(frame)
            SafeHide(frame)
        end)
    end
    for i = 1, MEMBERS_PER_RAID_GROUP do
        SafeHide(_G["CompactPartyFrameMember" .. i])
    end
    for i = 1, 4 do
        SafeHide(_G["PartyMemberFrame" .. i])
        SafeHide(_G["PartyMemberFrame" .. i .. "PetFrame"])
    end
end

local function RestorePartyFrames(showAfter)
    RestoreFrame(_G.PartyFrame, showAfter)
    if _G.PartyFrame then
        ForEachPoolActive(_G.PartyFrame.PartyMemberFramePool, function(frame)
            RestoreFrame(frame, showAfter)
        end)
    end
    RestoreFrame(_G.CompactPartyFrame, showAfter)
    RestoreFrame(_G.CompactPartyFrameTitle, showAfter)
    if _G.CompactPartyFrame then
        ForEachFrameTable(_G.CompactPartyFrame.memberUnitFrames, function(frame)
            RestoreFrame(frame, showAfter)
        end)
    end
    for i = 1, MEMBERS_PER_RAID_GROUP do
        RestoreFrame(_G["CompactPartyFrameMember" .. i], showAfter)
    end
    for i = 1, 4 do
        RestoreFrame(_G["PartyMemberFrame" .. i], showAfter)
        RestoreFrame(_G["PartyMemberFrame" .. i .. "PetFrame"], showAfter)
    end
    RefreshBlizzardParty()
end

local function SchedulePartyReconcile(hideSolo)
    partyReconcileHideSolo = hideSolo == true
    if partyReconcileScheduled then
        return
    end
    partyReconcileScheduled = true
    local function Run()
        partyReconcileScheduled = nil
        local hideIfSolo = partyReconcileHideSolo
        partyReconcileHideSolo = nil
        RefreshBlizzardParty()
        if hideIfSolo and (not GetNumGroupMembers or (GetNumGroupMembers() or 0) <= 0) then
            SoftHidePartyFramesOnly()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function HideRaidFrames(hard)
    local hide = hard and HardHideFrame or SoftHideFrame
    hide(_G.CompactRaidFrameManager)
    hide(_G.CompactRaidFrameManagerToggleButton)
    hide(_G.CompactRaidFrameReservationManager)
    hide(_G.CompactRaidFrameContainer)
    if _G.CompactRaidFrameContainer then
        ForEachFrameTable(_G.CompactRaidFrameContainer.memberUnitFrames, function(frame)
            hide(frame, true)
        end)
        ForEachFrameTable(_G.CompactRaidFrameContainer.flowFrames, function(frame)
            hide(frame, true)
        end)
        ForEachFrameTable(_G.CompactRaidFrameContainer.groupFrames, function(frame)
            hide(frame, true)
        end)
    end
    for i = 1, MAX_RAID_GROUPS do
        hide(_G["CompactRaidGroup" .. i])
    end
    for i = 1, MAX_RAID_MEMBERS do
        hide(_G["CompactRaidFrame" .. i], true)
    end
end

local function RestoreRaidFrames(showAfter)
    RestoreFrame(_G.CompactRaidFrameManager, showAfter)
    RestoreFrame(_G.CompactRaidFrameManagerToggleButton, showAfter)
    RestoreFrame(_G.CompactRaidFrameReservationManager, showAfter)
    RestoreFrame(_G.CompactRaidFrameContainer, showAfter)
    if _G.CompactRaidFrameContainer then
        ForEachFrameTable(_G.CompactRaidFrameContainer.memberUnitFrames, function(frame)
            RestoreFrame(frame, showAfter)
        end)
        ForEachFrameTable(_G.CompactRaidFrameContainer.flowFrames, function(frame)
            RestoreFrame(frame, showAfter)
        end)
        ForEachFrameTable(_G.CompactRaidFrameContainer.groupFrames, function(frame)
            RestoreFrame(frame, showAfter)
        end)
    end
    for i = 1, MAX_RAID_GROUPS do
        RestoreFrame(_G["CompactRaidGroup" .. i], showAfter)
    end
    for i = 1, MAX_RAID_MEMBERS do
        RestoreFrame(_G["CompactRaidFrame" .. i], showAfter)
    end
    RefreshBlizzardRaid()
end

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function ShouldManageBlizzardGroups()
    local g = General()
    return not (g and g.disableBlizzardUnitFrames == false)
end

-- File-local: only used inside this file (party/raid fallback-mode normalizer).
local function NormalizeBlizzardFallbackMode(mode)
    if mode == "SHOW" or mode == "BLIZZARD" or mode == true then
        return "SHOW"
    end
    if mode == "NONE" or mode == "HIDE" or mode == false then
        return "NONE"
    end
    return "AUTO"
end

function GF.AnyMSUFGroupFrameEnabled()
    local party = GF.GetConf and GF.GetConf("party") or nil
    local raid = GF.GetConf and GF.GetConf("raid") or nil
    local mythic = GF.GetConf and GF.GetConf("mythicraid") or nil
    return (party and party.enabled == true)
        or (raid and raid.enabled == true)
        or (mythic and mythic.enabled == true)
        or false
end

local function LiveRaidKind()
    return GF.GetLiveRaidKind and GF.GetLiveRaidKind() or "raid"
end

local function PartyScopeActive()
    local party = GF.GetConf and GF.GetConf("party") or nil
    if not (party and party.enabled == true) or (IsInRaid and IsInRaid()) then
        return false
    end
    if IsInGroup and IsInGroup() then
        return true
    end
    return party.showSolo == true and party.showPlayer ~= false
end

local function RaidScopeActive()
    if not (IsInRaid and IsInRaid()) then return false end
    local raid = GF.GetConf and GF.GetConf(LiveRaidKind()) or nil
    return raid and raid.enabled == true
end

local function MSUFOwnsLiveGroupFrames()
    return PartyScopeActive() or RaidScopeActive()
end

local function BlizzardRaidManagerWantsShown()
    local getSetting = _G.CompactRaidFrameManager_GetSetting
    if type(getSetting) ~= "function" then
        return nil
    end
    local value = getSetting("IsShown")
    if value == 1 or value == true or value == "1" or value == "true" then
        return true
    end
    if value == 0 or value == false or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function ApplyDisabledPartyFallback(mode, msufOwnsGroupFrames)
    mode = NormalizeBlizzardFallbackMode(mode)
    if mode == "NONE" then
        HidePartyFrames(true)
    elseif mode == "SHOW" then
        RestorePartyFrames(true)
        SchedulePartyReconcile(false)
    elseif msufOwnsGroupFrames then
        HidePartyFrames(true)
    else
        RestorePartyFrames(false)
        SchedulePartyReconcile((GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0) <= 0)
    end
end

local function ApplyDisabledRaidFallback(mode, msufOwnsGroupFrames)
    mode = NormalizeBlizzardFallbackMode(mode)
    if mode == "NONE" then
        HideRaidFrames(true)
    elseif mode == "SHOW" then
        RestoreRaidFrames(true)
    elseif msufOwnsGroupFrames then
        HideRaidFrames(true)
    else
        local wantsShown = BlizzardRaidManagerWantsShown()
        RestoreRaidFrames(wantsShown == true)
        if wantsShown == false and _G.CompactRaidFrameContainer and _G.CompactRaidFrameContainer.Hide then
            SafeHide(_G.CompactRaidFrameContainer)
        end
    end
end

function GF.HideBlizzardPartyFrames()
    HidePartyFrames(true)
end

function GF.HideBlizzardRaidFrames()
    HideRaidFrames(true)
end

function GF.RestoreBlizzardGroupFrames(showAfter)
    lastOwnershipSig = nil
    RestorePartyFrames(showAfter == true)
    RestoreRaidFrames(showAfter == true)
end

function GF.ApplyBlizzardGroupFrameOwnership(reason)
    if InCombat() then
        GF._pendingBlizzardGroupOwnership = reason or true
        EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if GF.EnsureDB then
        GF.EnsureDB()
    end
    local force = type(reason) == "string" and reason:sub(1, 12) == "addon-loaded"
    local groupCount = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid and IsInRaid() and true or false

    if not ShouldManageBlizzardGroups() then
        local sig = "off|" .. tostring(groupCount) .. "|" .. tostring(inRaid)
        if not force and lastOwnershipSig == sig and not next(pendingHide) and not next(pendingRestore) then
            return true
        end
        lastOwnershipSig = sig
        GF.RestoreBlizzardGroupFrames(false)
        lastOwnershipSig = sig
        return true
    end

    local partyConf = GF.GetConf and GF.GetConf("party") or {}
    local raidKind = LiveRaidKind()
    local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
    local msufOwnsGroupFrames = MSUFOwnsLiveGroupFrames()
    local partyActive = PartyScopeActive()
    local raidActive = RaidScopeActive()
    local partyMode = NormalizeBlizzardFallbackMode(partyConf.blizzardFallbackMode)
    local raidMode = NormalizeBlizzardFallbackMode(raidConf.blizzardFallbackMode)
    local wantsShown = (not raidActive and raidMode == "AUTO" and not msufOwnsGroupFrames) and BlizzardRaidManagerWantsShown() or nil
    local sig = "on|" .. tostring(groupCount)
        .. "|" .. tostring(inRaid)
        .. "|" .. tostring(raidKind)
        .. "|" .. tostring(msufOwnsGroupFrames)
        .. "|" .. tostring(partyActive)
        .. "|" .. tostring(raidActive)
        .. "|" .. tostring(partyMode)
        .. "|" .. tostring(raidMode)
        .. "|" .. tostring(wantsShown)

    if not force and lastOwnershipSig == sig and not next(pendingHide) and not next(pendingRestore) then
        return true
    end
    lastOwnershipSig = sig

    if partyActive then
        HidePartyFrames(true)
    else
        ApplyDisabledPartyFallback(partyMode, msufOwnsGroupFrames)
    end

    if raidActive then
        HideRaidFrames(true)
    else
        ApplyDisabledRaidFallback(raidMode, msufOwnsGroupFrames)
    end

    if not msufOwnsGroupFrames
        and inRaid
        and partyMode == "AUTO"
    then
        HidePartyFrames(true)
    end

    return true
end

local function ScheduleApply(reason)
    if applyScheduled then
        return
    end
    applyScheduled = reason or true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local r = applyScheduled
            applyScheduled = nil
            GF.ApplyBlizzardGroupFrameOwnership(r)
        end)
    else
        local r = applyScheduled
        applyScheduled = nil
        GF.ApplyBlizzardGroupFrameOwnership(r)
    end
end

local function FlushPending()
    for frame in next, pendingHide do
        pendingHide[frame] = nil
        if frame and ownedFrames[frame] and ownedFrames[frame].hidden then
            SafeHide(frame)
            ReparentHidden(frame)
        end
    end
    for frame, showAfter in pairs(pendingRestore) do
        pendingRestore[frame] = nil
        RestoreFrame(frame, showAfter)
    end
end

local function OnEvent(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        RegisterRosterEvent()
        FlushPending()
        if GF._pendingBlizzardGroupOwnership then
            local reason = GF._pendingBlizzardGroupOwnership
            GF._pendingBlizzardGroupOwnership = nil
            ScheduleApply(reason)
        else
            ScheduleApply("regen-enabled")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        UnregisterRosterEvent()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_CompactRaidFrames" or arg1 == "Blizzard_UnitFrame" or arg1 == addonName then
            ScheduleApply("addon-loaded:" .. tostring(arg1))
        end
    else
        if event == "GROUP_ROSTER_UPDATE" and InCombat() then
            return
        end
        ScheduleApply(event)
    end
end

eventFrame = EnsureEventFrame()
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
RegisterRosterEvent()

_G.MSUF_GF_DisableBlizzard = function()
    return GF.ApplyBlizzardGroupFrameOwnership("legacy-global")
end
