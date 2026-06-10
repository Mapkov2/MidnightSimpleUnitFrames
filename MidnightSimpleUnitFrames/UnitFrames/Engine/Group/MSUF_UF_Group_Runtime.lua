local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF
local Metadata = GF.Metadata or {}

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local floor = math.floor
local table_concat = table.concat
local type = type
local tostring = tostring
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end

local eventFrame
local rosterRebuildQueued = false
local zoneRefreshQueued = false
local rosterSettleToken = 0
local nameEventsRegistered = false
local rosterEventsRegistered = false
local lastRosterMode
local lastRosterSignature

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local band = bit and bit.band or bit32 and bit32.band
local bor = bit and bit.bor or bit32 and bit32.bor
local function Has(mask, flag)
    if not mask then return false end
    if band then return band(mask, flag) ~= 0 end
    return mask % (flag * 2) >= flag
end

local function OrMask(a, b)
    if a == nil or b == nil then return nil end
    if bor then return bor(a, b) end
    local out = a
    local flags = {
        GF.DIRTY_GEOMETRY, GF.DIRTY_VISUAL, GF.DIRTY_FONT, GF.DIRTY_COLOR,
        GF.DIRTY_BORDER, GF.DIRTY_LAYOUT, GF.DIRTY_AURAS,
    }
    for i = 1, #flags do
        local flag = flags[i]
        if flag and Has(b, flag) and not Has(out, flag) then
            out = out + flag
        end
    end
    return out
end

local MASK_RUNTIME = Metadata.MASK_RUNTIME or {}
local DIRTY_APPLY_MASKS = Metadata.dirtyApplyMasks or {}

local function DirtyApplyMask(mask)
    if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
        return nil
    end
    return DIRTY_APPLY_MASKS[mask] or MASK_RUNTIME
end

local function DirtyRuntimeReason(mask, reason)
    if reason ~= nil and reason ~= "MSUF_GF_REFRESH_VISUALS" and reason ~= "MSUF_GF_MARK_DIRTY" then
        return reason
    end
    if mask == GF.DIRTY_FONT then
        return "MSUF_GF_DIRTY_FONT"
    end
    if mask == GF.DIRTY_BORDER then
        return "MSUF_GF_DIRTY_BORDER"
    end
    if mask == GF.DIRTY_AURAS then
        return "MSUF_GF_DIRTY_AURAS"
    end
    return reason or "MSUF_GF_DIRTY"
end

local function InvalidateSpecs(kind)
    if GF.InvalidateCompiledSpecs then
        GF.InvalidateCompiledSpecs(kind)
    end
end

local function DropSpecs(kind)
    if GF.DropCompiledSpecs then
        GF.DropCompiledSpecs(kind)
    elseif GF.InvalidateCompiledSpecs then
        GF.InvalidateCompiledSpecs(kind)
    end
end

local function ApplyFrameDirty(frame, kind, mask, reason)
    local applyMask = DirtyApplyMask(mask)
    if not applyMask then
        return GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FULL")
    end
    if not (UF and UF.ApplySpec and GF.CompileSpec) then
        return GF.ApplyButton and GF.ApplyButton(frame, kind, reason or "MSUF_GF_DIRTY_FALLBACK")
    end
    local spec = GF.CompileSpec(kind, frame, frame and frame.unit)
    return UF.ApplySpec(frame, spec, DirtyRuntimeReason(mask, reason), applyMask)
end

local function AddPendingRefresh(kind, mask)
    if GF._pendingGroupRefresh == true then
        if GF._pendingGroupRefreshKind ~= kind then
            GF._pendingGroupRefreshKind = nil
        end
        if GF._pendingGroupRefreshMaskSet == true then
            GF._pendingGroupRefreshMask = OrMask(GF._pendingGroupRefreshMask, mask)
        else
            GF._pendingGroupRefreshMask = mask
            GF._pendingGroupRefreshMaskSet = true
        end
        return
    end
    GF._pendingGroupRefresh = true
    GF._pendingGroupRefreshKind = kind
    GF._pendingGroupRefreshMask = mask
    GF._pendingGroupRefreshMaskSet = true
end

function GF.DeferGroupRuntime(reason, kind, mask)
    reason = reason or "refresh"
    GF._pendingGroupRuntime = reason
    if reason == "roster" or reason == "zone" then
        GF._pendingGroupRebuild = true
        GF._pendingGroupDropSpecs = true
    elseif reason == "rebuild" then
        GF._pendingGroupRebuild = true
    elseif reason == "visibility" then
        GF._pendingGroupVisibility = true
    else
        AddPendingRefresh(kind, mask)
    end
    if eventFrame then
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function GroupUnitMatches(frame, unit)
    local frameUnit = frame and frame.unit
    if not unit or unit == "" then
        return true
    end
    if frameUnit == unit then
        return true
    end
    if not (UnitGUID and frameUnit) then
        return false
    end
    local frameGuid = UnitGUID(frameUnit)
    local unitGuid = UnitGUID(unit)
    if IsSecret(frameGuid) or IsSecret(unitGuid) then
        return false
    end
    return frameGuid ~= nil and frameGuid == unitGuid
end

function GF.RefreshGroupNames(unit)
    if InCombat() then
        return false
    end
    local runtime = MSUF.UFTextRuntime
    if not (runtime and runtime.UpdateName and GF.ForEachFrame) then
        return false
    end
    local updated = false
    GF.ForEachFrame(function(frame)
        local active = frame and frame._msufActiveElements
        if active and active.NameText == true and GroupUnitMatches(frame, unit) then
            runtime.UpdateName(frame, "MSUF_GF_NAME_UPDATE", frame.unit)
            updated = true
        end
    end, true)
    return updated
end

local function RegisterNameEvents()
    if eventFrame and not nameEventsRegistered and not InCombat() then
        eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
        nameEventsRegistered = true
    end
end

local function UnregisterNameEvents()
    if eventFrame and nameEventsRegistered then
        eventFrame:UnregisterEvent("UNIT_NAME_UPDATE")
        nameEventsRegistered = false
    end
end

local function RegisterRosterEvents()
    if eventFrame and not rosterEventsRegistered and not InCombat() then
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
        rosterEventsRegistered = true
    end
end

local function UnregisterRosterEvents()
    if eventFrame and rosterEventsRegistered then
        eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
        eventFrame:UnregisterEvent("ROLE_CHANGED_INFORM")
        rosterEventsRegistered = false
    end
end

local function LiveRaidKind()
    return GF.GetLiveRaidKind and GF.GetLiveRaidKind() or "raid"
end

local function ShouldShowParty()
    local conf = GF.GetConf and GF.GetConf("party") or {}
    if conf.enabled ~= true or (IsInRaid and IsInRaid()) then
        return false
    end
    if IsInGroup and IsInGroup() then
        return true
    end
    return conf.showSolo == true and conf.showPlayer ~= false
end

local function RosterMode()
    if IsInRaid and IsInRaid() then
        return "raid"
    end
    if IsInGroup and IsInGroup() then
        return "party"
    end
    return "solo"
end

local function MarkRosterMode()
    local mode = RosterMode()
    if lastRosterMode ~= nil and lastRosterMode ~= mode then
        GF._forceRecreateHeaders = true
    end
    lastRosterMode = mode
    return mode
end

local function UnitIdentity(unit)
    if UnitGUID and unit then
        local guid = UnitGUID(unit)
        if guid and not IsSecret(guid) then return guid end
    end
    if UnitName and unit then
        local name, realm = UnitName(unit)
        if name and name ~= "" then
            return realm and realm ~= "" and (name .. "-" .. realm) or name
        end
    end
    return unit or ""
end

local function UnitRoleToken(unit)
    return (UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit)) or ""
end

local function CurrentRosterSignature()
    local mode = RosterMode()
    local parts = { mode }
    if mode == "raid" then
        local count = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
        parts[#parts + 1] = tostring(count)
        for i = 1, count do
            local unit = "raid" .. i
            local subgroup = GetRaidRosterInfo and select(3, GetRaidRosterInfo(i)) or ""
            parts[#parts + 1] = UnitIdentity(unit)
            parts[#parts + 1] = UnitRoleToken(unit)
            parts[#parts + 1] = tostring(subgroup or "")
        end
    elseif mode == "party" then
        local count = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
        parts[#parts + 1] = tostring(count)
        parts[#parts + 1] = UnitIdentity("player")
        parts[#parts + 1] = UnitRoleToken("player")
        for i = 1, count do
            local unit = "party" .. i
            parts[#parts + 1] = UnitIdentity(unit)
            parts[#parts + 1] = UnitRoleToken(unit)
        end
    end
    return table_concat(parts, "\031")
end

local function RefreshRosterSignature()
    lastRosterSignature = CurrentRosterSignature()
end

local function RosterSignatureChanged()
    local current = CurrentRosterSignature()
    return current ~= lastRosterSignature
end

local function HeaderKindForKey(key)
    if key == "raid" then
        return LiveRaidKind()
    end
    return key
end

local function ClientSceneHidden(key)
    if GF._clientSceneActive ~= true then
        return false
    end
    local kind = HeaderKindForKey(key)
    local conf = GF.GetConf and GF.GetConf(kind) or nil
    return conf and conf.hideInClientScene ~= false or false
end

local function ApplyHeaderSceneAlpha(key)
    local header = GF.headers and GF.headers[key]
    local anchor = GF.anchors and GF.anchors[key]
    local hidden = ClientSceneHidden(key)
    if header then
        header._msufGF_clientSceneHidden = hidden and true or nil
    end
    if anchor and anchor.SetAlpha then
        anchor:SetAlpha(hidden and 0 or 1)
    elseif header and header.SetAlpha then
        header:SetAlpha(hidden and 0 or 1)
    end
end

local function ApplyAllSceneAlphas()
    ApplyHeaderSceneAlpha("party")
    ApplyHeaderSceneAlpha("raid")
end

local function ScheduleRosterSettle()
    if not (C_Timer and C_Timer.After) then
        return
    end
    if RosterMode() ~= "raid" then
        return
    end
    rosterSettleToken = rosterSettleToken + 1
    local token = rosterSettleToken
    local function Run()
        if token ~= rosterSettleToken or RosterMode() ~= "raid" then
            return
        end
        GF._forceScanHeaders = true
        GF.RebuildAll()
    end
    C_Timer.After(0.15, Run)
    C_Timer.After(0.60, Run)
end

-- DB-readiness retry. On a /reload (or an early PLAYER_ENTERING_WORLD) the
-- group rebuild can run before _G.MSUF_DB is populated. In that window
-- GF.EnsureDB early-returns and GF.GetConf falls back to RAID_DEFAULTS, whose
-- `enabled` is false -- so wantRaid is false and the raid header is never built,
-- with no event left to retry on (the player was already out of combat / no
-- further roster change). Re-arm the build a few times until the DB appears so
-- the header recovers on its own instead of staying blank until the next roster
-- change. Bounded retry count; cleared as soon as the DB is ready.
local dbReadyRetryToken = 0
local function DBReady()
    return type(_G.MSUF_DB) == "table"
end

local function ScheduleDBReadyRetry(builder)
    if DBReady() or not (C_Timer and C_Timer.After) then
        return
    end
    dbReadyRetryToken = dbReadyRetryToken + 1
    local token = dbReadyRetryToken
    local attempt = 0
    local function Run()
        if token ~= dbReadyRetryToken then return end
        if not DBReady() then
            attempt = attempt + 1
            if attempt <= 20 then
                C_Timer.After(0.1, Run)
            end
            return
        end
        builder()
    end
    C_Timer.After(0.1, Run)
end

local function ScheduleRosterRebuild()
    if rosterRebuildQueued then
        return
    end
    rosterRebuildQueued = true
    local function Run()
        rosterRebuildQueued = false
        DropSpecs()
        GF.RebuildAll(true)
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF_GF_ROSTER_REBUILD", Run)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function ScheduleZoneRefresh()
    if zoneRefreshQueued then
        return
    end
    zoneRefreshQueued = true
    local function Run()
        zoneRefreshQueued = false
        if InCombat() then
            GF.DeferGroupRuntime("zone")
            return
        end
        DropSpecs()
        GF.RefreshAll(true)
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF_GF_ZONE_REFRESH", Run)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function HideOrRetireHeader(key)
    local header = GF.headers and GF.headers[key]
    if not header then return end
    if GF.RetireHeader then
        GF.RetireHeader(key)
    else
        header:Hide()
    end
end

local function PreviewSuppressesHeader(key)
    if _G.MSUF_UnitEditModeActive == true then
        return false
    end
    local active = GF._previewActive
    if not active then return false end
    if key == "party" then
        return active.party == true
    end
    if key == "raid" then
        return active.raid == true or active.mythicraid == true
    end
    return false
end

function GF.UpdateGroupVisibility()
    if InCombat() then
        GF.DeferGroupRuntime("visibility")
        return false
    end
    if not DBReady() then
        ScheduleDBReadyRetry(GF.RebuildAll)
        return false
    end
    if GF.EnsureDB then GF.EnsureDB() end

    local wantParty = ShouldShowParty() and not PreviewSuppressesHeader("party")
    local raidKind = LiveRaidKind()
    local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
    local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true and not PreviewSuppressesHeader("raid")

    local party = GF.headers and GF.headers.party
    local raid = GF.headers and GF.headers.raid
    if not wantParty and party then
        HideOrRetireHeader("party")
        party = nil
    end
    if not wantRaid and raid then
        HideOrRetireHeader("raid")
        raid = nil
    end

    if wantParty then
        party = party or (GF.SetupHeader and GF.SetupHeader("party", "party"))
        if party then party:Show() end
    end
    ApplyHeaderSceneAlpha("party")

    if wantRaid then
        if (not raid or raid._msufGFKind ~= raidKind) and GF.SetupHeader then
            raid = GF.SetupHeader("raid", raidKind) or raid
        end
        if raid then raid:Show() end
    end
    ApplyHeaderSceneAlpha("raid")
    if GF.ApplyBlizzardGroupFrameOwnership then
        GF.ApplyBlizzardGroupFrameOwnership("visibility")
    end
    return true
end

function GF.RebuildAll(preInvalidated)
    if InCombat() then
        GF.DeferGroupRuntime("rebuild")
        return false
    end
    if not DBReady() then
        -- SavedVariables not ready yet (early /reload or PLAYER_ENTERING_WORLD
        -- race). Building now would read RAID_DEFAULTS (enabled=false) and skip
        -- the raid header permanently; re-arm until the DB exists.
        ScheduleDBReadyRetry(GF.RebuildAll)
        return false
    end
    if preInvalidated ~= true then
        InvalidateSpecs()
    end
    if GF.EnsureDB then GF.EnsureDB() end

    local wantParty = ShouldShowParty() and not PreviewSuppressesHeader("party")
    local raidKind = LiveRaidKind()
    local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
    local wantRaid = (IsInRaid and IsInRaid()) and raidConf.enabled == true and not PreviewSuppressesHeader("raid")

    if not wantParty and GF.headers and GF.headers.party then
        HideOrRetireHeader("party")
    end
    if not wantRaid and GF.headers and GF.headers.raid then
        HideOrRetireHeader("raid")
    end

    if wantParty and GF.SetupHeader then
        local party = GF.SetupHeader("party", "party")
        if party then party:Show() end
    end
    if wantRaid and GF.SetupHeader then
        local raid = GF.SetupHeader("raid", raidKind)
        if raid then raid:Show() end
    end
    ApplyHeaderSceneAlpha("party")
    ApplyHeaderSceneAlpha("raid")
    if GF.ApplyBlizzardGroupFrameOwnership then
        GF.ApplyBlizzardGroupFrameOwnership("rebuild")
    end
    GF._forceScanHeaders = nil
    GF._forceRecreateHeaders = nil
    RefreshRosterSignature()
    return true
end

function GF.RefreshVisuals(kind, mask, preInvalidated)
    if InCombat() then
        GF.DeferGroupRuntime("refresh", kind, mask)
        return false
    end
    if preInvalidated ~= true then
        InvalidateSpecs(kind)
    end
    if GF.ForEachFrame then
        GF.ForEachFrame(function(frame, unit, frameKind)
            if not kind or kind == frameKind then
                ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS")
            end
        end, true)
    end
    return true
end

function GF.RefreshAll(preInvalidated)
    if InCombat() then
        GF.DeferGroupRuntime("refresh", nil, GF.DIRTY_ALL)
        return false
    end
    -- Invalidate once up front; RebuildAll/RefreshVisuals would each invalidate
    -- again (all 3 wipes are idempotent but pointless extra table churn).
    if preInvalidated ~= true then
        InvalidateSpecs()
    end
    GF.RebuildAll(true)
    GF.RefreshVisuals(nil, GF.DIRTY_ALL, true)
    return true
end

GF.Refresh = GF.RefreshAll
GF.RefreshGeometry = GF.RebuildAll
-- NOTE: GF.RefreshPreviewLayout / GF.RefreshPreviewBox are owned by
-- MSUF_UF_Group_Preview.lua (loads after this file), which installs the real
-- preview-repositioning implementation. Do not alias them here; a duplicate
-- definition would just be overwritten and confuse the call graph.
GF.RefreshOverlays = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_AURAS) end
GF.RefreshColors = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_COLOR) end
GF.RefreshBorder = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_BORDER) end
GF.RefreshOutlineGeometry = GF.RefreshBorder
GF.RefreshFonts = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_FONT) end

function GF.MarkDirty(frame, mask)
    -- When we know the frame's kind, only that kind's compiled spec is stale.
    -- Avoid invalidating other kinds (e.g., raid spec stays cached when only
    -- a party frame is being marked dirty).
    InvalidateSpecs(frame and frame._msufGFKind)
    if frame and frame._msufGFKind then
        return ApplyFrameDirty(frame, frame._msufGFKind, mask, "MSUF_GF_MARK_DIRTY")
    end
    return GF.RefreshVisuals(nil, mask, true)
end

function GF.MarkAllDirty(mask)
    InvalidateSpecs()
    if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
        if InCombat() then
            GF.DeferGroupRuntime("rebuild")
            GF.DeferGroupRuntime("refresh", nil, GF.DIRTY_ALL)
            return false
        end
        return GF.RefreshAll(true)
    end
    return GF.RefreshVisuals(nil, mask, true)
end

function GF.BuildFrameCache(frame)
    return frame and frame.MSUFSpec
end

function GF.EM2_SetActivePreviewKind(kind)
    GF._activePreviewKind = kind
    return true
end

function GF.EM2_NudgePreview(key, dx, dy)
    if InCombat() then return true end
    local kind = key
    if key == "gf_party" then kind = "party"
    elseif key == "gf_raid" then kind = "raid"
    elseif key == "gf_mythicraid" then kind = "mythicraid" end
    if kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" then return false end
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf then return false end
    conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + (tonumber(dx) or 0)) + 0.5)
    conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + (tonumber(dy) or 0)) + 0.5)
    GF.RefreshAll()
    return true
end

local function TakePendingGroupRuntime(rosterChanged)
    local pending = GF._pendingGroupRuntime
    local rebuild = GF._pendingGroupRebuild == true
    local dropSpecs = GF._pendingGroupDropSpecs == true
    local visibility = GF._pendingGroupVisibility == true
    local refresh = GF._pendingGroupRefresh == true
    local refreshKind = GF._pendingGroupRefreshKind
    local refreshMask = GF._pendingGroupRefreshMask

    GF._pendingGroupRuntime = nil
    GF._pendingGroupRebuild = nil
    GF._pendingGroupDropSpecs = nil
    GF._pendingGroupVisibility = nil
    GF._pendingGroupRefresh = nil
    GF._pendingGroupRefreshKind = nil
    GF._pendingGroupRefreshMask = nil
    GF._pendingGroupRefreshMaskSet = nil

    if pending and not (rebuild or dropSpecs or visibility or refresh) then
        if pending == "roster" or pending == "zone" then
            rebuild = true
            dropSpecs = true
        elseif pending == "rebuild" then
            rebuild = true
        elseif pending == "visibility" then
            visibility = true
        else
            refresh = true
        end
    end

    if rosterChanged then
        rebuild = true
        dropSpecs = true
    end

    return pending or rosterChanged, rebuild, dropSpecs, visibility, refresh, refreshKind, refreshMask
end

local function FlushPendingGroupRuntime(rosterChanged)
    local hasPending, rebuild, dropSpecs, visibility, refresh, refreshKind, refreshMask = TakePendingGroupRuntime(rosterChanged)
    if not hasPending then
        return false
    end

    -- Do not promote combat-deferred work into RefreshAll here. Runtime combat
    -- events may request narrow refresh/visibility/rebuild work, but full layout
    -- plus full visual apply belongs to explicit cold paths.
    if dropSpecs then
        DropSpecs()
    end
    if rebuild then
        GF.RebuildAll(dropSpecs == true)
    end
    if visibility and not rebuild then
        GF.UpdateGroupVisibility()
    end
    if refresh then
        GF.RefreshVisuals(refreshKind, refreshMask, dropSpecs == true)
    end
    return true
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        _G.MSUF_InCombat = false
        RegisterNameEvents()
        RegisterRosterEvents()
        local rosterChanged = RosterSignatureChanged()
        if rosterChanged then
            MarkRosterMode()
            if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
            GF._forceScanHeaders = true
        end
        if not FlushPendingGroupRuntime(rosterChanged) then
            GF.RefreshGroupNames()
            if GF.RefreshClickCastFrames then
                GF.RefreshClickCastFrames()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        _G.MSUF_InCombat = true
        UnregisterNameEvents()
        UnregisterRosterEvents()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        _G.MSUF_InCombat = InCombat()
        if _G.MSUF_InCombat then
            UnregisterNameEvents()
            UnregisterRosterEvents()
        else
            RegisterNameEvents()
            RegisterRosterEvents()
        end
        MarkRosterMode()
        if event == "PLAYER_ENTERING_WORLD" then
            GF._forceRecreateHeaders = true
        end
        DropSpecs()
        GF.RebuildAll(true)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
        if InCombat() then
            if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
            GF._forceScanHeaders = true
            GF.DeferGroupRuntime("roster")
            return
        end
        local mode = MarkRosterMode()
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
        GF._forceScanHeaders = true
        ScheduleRosterRebuild()
        if event == "GROUP_ROSTER_UPDATE" and mode == "raid" then
            ScheduleRosterSettle()
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        GF._forceRecreateHeaders = true
        ScheduleZoneRefresh()
    elseif event == "BARBER_SHOP_OPEN" then
        GF._clientSceneActive = true
        ApplyAllSceneAlphas()
    elseif event == "BARBER_SHOP_CLOSE" then
        GF._clientSceneActive = nil
        ApplyAllSceneAlphas()
        GF.UpdateGroupVisibility()
    elseif event == "UNIT_NAME_UPDATE" then
        GF.RefreshGroupNames(select(1, ...))
    end
end

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("BARBER_SHOP_OPEN")
eventFrame:RegisterEvent("BARBER_SHOP_CLOSE")
RegisterNameEvents()
RegisterRosterEvents()

-- Public globals route through the granular GF.* variants so the DIRTY_*
-- mask and per-kind filter survive the boundary. Previously several aliases
-- dropped both and re-dispatched through bare GF.RefreshVisuals() (all kinds,
-- all elements), defeating the per-kind spec cache and the dirty-mask system
-- on every external call.
_G.MSUF_GF_RebuildAll = function() return GF.RebuildAll() end
_G.MSUF_GF_RefreshAll = function() return GF.RefreshAll() end
_G.MSUF_GF_Refresh = function() return GF.RefreshAll() end
_G.MSUF_GF_RefreshVisuals = function(kind, mask) return GF.RefreshVisuals(kind, mask) end
_G.MSUF_GF_RefreshGeometry = function() return GF.RefreshGeometry() end
_G.MSUF_GF_UpdateGroupVisibility = function() return GF.UpdateGroupVisibility() end
-- _G.MSUF_GF_RefreshPreviewLayout / _G.MSUF_GF_RefreshPreviewBox are installed by
-- MSUF_UF_Group_Preview.lua (loads after this file) once the real preview
-- implementation exists; defining them here would only be overwritten.
_G.MSUF_GF_RefreshOverlays = function(kind) return GF.RefreshOverlays(kind) end
_G.MSUF_GF_RefreshBorder = function(kind) return GF.RefreshBorder(kind) end
_G.MSUF_GF_RefreshOutlineGeometry = function(kind) return GF.RefreshOutlineGeometry(kind) end
_G.MSUF_GF_RefreshColors = function(kind) return GF.RefreshColors(kind) end
_G.MSUF_GF_RefreshFonts = function(kind) return GF.RefreshFonts(kind) end
_G.MSUF_GF_InvalidateCooldownTextCurve = function()
    local A3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    local CT = A3 and A3.CooldownText
    if CT and CT.Invalidate then CT.Invalidate("group") end
    return true
end
_G.MSUF_GF_ForceCooldownTextRecolor = function()
    local A3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    local CT = A3 and A3.CooldownText
    if CT and CT.ForceRecolor then CT.ForceRecolor("group") end
    return GF.RefreshVisuals()
end
_G.MSUF_GF_ForceAuraTextColorRefresh = function() return GF.RefreshVisuals() end
_G.MSUF_GF_EM2_SetActivePreviewKind = function(kind) return GF.EM2_SetActivePreviewKind(kind) end
_G.MSUF_GF_EM2_NudgePreview = function(key, dx, dy) return GF.EM2_NudgePreview(key, dx, dy) end
