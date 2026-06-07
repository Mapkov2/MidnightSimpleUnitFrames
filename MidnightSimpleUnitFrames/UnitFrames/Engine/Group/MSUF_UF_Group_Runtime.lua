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
local UnitGUID = UnitGUID
local floor = math.floor
local type = type
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end

local eventFrame
local rosterRebuildQueued = false
local rosterSettleToken = 0
local nameEventsRegistered = false
local lastRosterMode

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local band = bit and bit.band or bit32 and bit32.band
local function Has(mask, flag)
    if not mask then return false end
    if band then return band(mask, flag) ~= 0 end
    return mask % (flag * 2) >= flag
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

function GF.DeferGroupRuntime(reason)
    GF._pendingGroupRuntime = reason or true
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

local function ScheduleRosterRebuild()
    if rosterRebuildQueued then
        return
    end
    rosterRebuildQueued = true
    local function Run()
        rosterRebuildQueued = false
        GF.RebuildAll()
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF_GF_ROSTER_REBUILD", Run)
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

function GF.RebuildAll()
    if InCombat() then
        GF.DeferGroupRuntime("rebuild")
        return false
    end
    InvalidateSpecs()
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
    return true
end

function GF.RefreshVisuals(kind, mask)
    if InCombat() then
        GF.DeferGroupRuntime("refresh")
        return false
    end
    InvalidateSpecs(kind)
    if GF.ForEachFrame then
        GF.ForEachFrame(function(frame, unit, frameKind)
            if not kind or kind == frameKind then
                ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS")
            end
        end, true)
    end
    return true
end

function GF.RefreshAll()
    if InCombat() then
        GF.DeferGroupRuntime("refresh")
        return false
    end
    -- Invalidate once up front; RebuildAll/RefreshVisuals would each invalidate
    -- again (all 3 wipes are idempotent but pointless extra table churn).
    InvalidateSpecs()
    GF.RebuildAll()
    GF.RefreshVisuals(nil, GF.DIRTY_ALL)
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
    return GF.RefreshVisuals(nil, mask)
end

function GF.MarkAllDirty(mask)
    InvalidateSpecs()
    if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
        return GF.RefreshAll()
    end
    return GF.RefreshVisuals(nil, mask)
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

local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        _G.MSUF_InCombat = false
        RegisterNameEvents()
        GF.RefreshGroupNames()
        if GF.RefreshClickCastFrames then
            GF.RefreshClickCastFrames()
        end
        if GF._pendingGroupRuntime then
            GF._pendingGroupRuntime = nil
            GF.RefreshAll()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        _G.MSUF_InCombat = true
        UnregisterNameEvents()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        _G.MSUF_InCombat = InCombat()
        if _G.MSUF_InCombat then
            UnregisterNameEvents()
        else
            RegisterNameEvents()
        end
        MarkRosterMode()
        if event == "PLAYER_ENTERING_WORLD" then
            GF._forceRecreateHeaders = true
        end
        GF.RebuildAll()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
        local mode = MarkRosterMode()
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
        GF._forceScanHeaders = true
        if InCombat() then
            GF.DeferGroupRuntime("roster")
            return
        end
        ScheduleRosterRebuild()
        if event == "GROUP_ROSTER_UPDATE" and mode == "raid" then
            ScheduleRosterSettle()
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        GF._forceRecreateHeaders = true
        GF.RefreshAll()
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
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("BARBER_SHOP_OPEN")
eventFrame:RegisterEvent("BARBER_SHOP_CLOSE")
RegisterNameEvents()

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
