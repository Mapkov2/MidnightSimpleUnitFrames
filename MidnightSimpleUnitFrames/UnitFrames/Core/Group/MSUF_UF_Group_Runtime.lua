local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInRaid = IsInRaid
local UnitIsUnit = UnitIsUnit
local floor = math.floor
local type = type

local eventFrame
local rosterRebuildQueued = false
local nameEventsRegistered = false
local lastInRaid

GF.DIRTY_GEOMETRY = GF.DIRTY_GEOMETRY or 0x01
GF.DIRTY_VISUAL = GF.DIRTY_VISUAL or 0x02
GF.DIRTY_FONT = GF.DIRTY_FONT or 0x04
GF.DIRTY_COLOR = GF.DIRTY_COLOR or 0x08
GF.DIRTY_BORDER = GF.DIRTY_BORDER or 0x10
GF.DIRTY_LAYOUT = GF.DIRTY_LAYOUT or 0x20
GF.DIRTY_AURAS = GF.DIRTY_AURAS or 0x40
GF.DIRTY_ALL = GF.DIRTY_ALL or 0x7F

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local band = bit and bit.band or bit32 and bit32.band
local function Has(mask, flag)
    if not mask then return false end
    if band then return band(mask, flag) ~= 0 end
    return mask % (flag * 2) >= flag
end

local MASK_FONT = {
    Text = true, NameText = true, HealthText = true, PowerText = true,
    StatusIndicators = true, GroupStatusRuntime = true,
}
local MASK_COLOR = {
    Health = true, Power = true, Text = true, NameText = true,
    HealthText = true, PowerText = true, StatusIndicators = true,
    GroupVisuals = true, GroupCornerIndicators = true, GroupSpellIndicators = true,
    Borders = true,
}
local MASK_BORDER = {
    Borders = true, GroupVisuals = true,
}
local MASK_AURAS = {
    Auras = true, GroupVisuals = true, GroupCornerIndicators = true,
    GroupSpellIndicators = true, Borders = true,
}
local MASK_VISUAL = {
    Health = true, Power = true, Text = true, NameText = true,
    HealthText = true, PowerText = true, StatusIndicators = true,
    Prediction = true, Alpha = true, GroupStatusRuntime = true,
    GroupRangeFade = true, GroupVisuals = true, Borders = true,
}
local MASK_RUNTIME = {
    Health = true, Power = true, Text = true, NameText = true,
    HealthText = true, PowerText = true, StatusIndicators = true,
    Prediction = true, Alpha = true, Auras = true, Borders = true,
    GroupStatusRuntime = true, GroupRangeFade = true, GroupVisuals = true,
    GroupCornerIndicators = true, GroupSpellIndicators = true,
}

local function DirtyApplyMask(mask)
    if not mask or mask == GF.DIRTY_ALL or Has(mask, GF.DIRTY_GEOMETRY) or Has(mask, GF.DIRTY_LAYOUT) then
        return nil
    end
    if mask == GF.DIRTY_FONT then return MASK_FONT end
    if mask == GF.DIRTY_COLOR then return MASK_COLOR end
    if mask == GF.DIRTY_BORDER then return MASK_BORDER end
    if mask == GF.DIRTY_AURAS then return MASK_AURAS end
    if mask == GF.DIRTY_VISUAL then return MASK_VISUAL end
    return MASK_RUNTIME
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
    return UF.ApplySpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask)
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
    local same = UnitIsUnit and frameUnit and UnitIsUnit(frameUnit, unit)
    return same == true or same == 1
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
    return conf.enabled == true and not (IsInRaid and IsInRaid())
end

local function ShouldShowRaid()
    if not (IsInRaid and IsInRaid()) then return false end
    local conf = GF.GetConf and GF.GetConf(LiveRaidKind()) or {}
    return conf.enabled == true
end

local function MarkRosterMode()
    local inRaid = IsInRaid and IsInRaid() or false
    if lastInRaid ~= nil and lastInRaid ~= inRaid then
        GF._forceRecreateHeaders = true
    end
    lastInRaid = inRaid
    return inRaid
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

local function RefreshCombatAlpha()
    if _G.MSUF_RefreshCombatUnitAlphas then
        return _G.MSUF_RefreshCombatUnitAlphas()
    end
    return false
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
    if GF._forceRecreateHeaders == true and GF.RetireHeader then
        GF.RetireHeader(key)
    else
        header:Hide()
    end
end

function GF.UpdateGroupVisibility()
    if InCombat() then
        GF.DeferGroupRuntime("visibility")
        return false
    end
    if GF.EnsureDB then GF.EnsureDB() end

    local party = GF.headers and GF.headers.party
    if ShouldShowParty() then
        party = party or (GF.SetupHeader and GF.SetupHeader("party", "party"))
        if party then party:Show() end
    elseif party then
        HideOrRetireHeader("party")
    end
    ApplyHeaderSceneAlpha("party")

    local raidKind = LiveRaidKind()
    local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
    local raid = GF.headers and GF.headers.raid
    if ShouldShowRaid() and raidConf.enabled == true then
        if (not raid or raid._msufGFKind ~= raidKind) and GF.SetupHeader then
            raid = GF.SetupHeader("raid", raidKind) or raid
        end
        if raid then raid:Show() end
    elseif raid then
        HideOrRetireHeader("raid")
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
    if ShouldShowParty() and GF.SetupHeader then
        local party = GF.SetupHeader("party", "party")
        if party then party:Show() end
    elseif GF.headers and GF.headers.party then
        HideOrRetireHeader("party")
    end
    if ShouldShowRaid() and GF.SetupHeader then
        local raid = GF.SetupHeader("raid", LiveRaidKind())
        if raid then raid:Show() end
    elseif GF.headers and GF.headers.raid then
        HideOrRetireHeader("raid")
    end
    ApplyHeaderSceneAlpha("party")
    ApplyHeaderSceneAlpha("raid")
    if GF.ApplyBlizzardGroupFrameOwnership then
        GF.ApplyBlizzardGroupFrameOwnership("rebuild")
    end
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
GF.RefreshPreviewLayout = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_VISUAL) end
GF.RefreshPreviewBox = GF.RefreshPreviewLayout
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

function GF.StopDispelGlow(frame)
    if frame and frame.MSUFGFDispelOverlay then frame.MSUFGFDispelOverlay:Hide() end
    return true
end

function GF.EM2_SetActivePreviewKind(kind)
    GF._activePreviewKind = kind
    return true
end

function GF.EM2_NudgePreview(key, dx, dy)
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
        elseif GF.HasCombatAlpha and GF.HasCombatAlpha() then
            RefreshCombatAlpha()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        _G.MSUF_InCombat = true
        UnregisterNameEvents()
        if GF.HasCombatAlpha and GF.HasCombatAlpha() then
            RefreshCombatAlpha()
        end
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
        MarkRosterMode()
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end
        ScheduleRosterRebuild()
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
_G.MSUF_GF_RefreshPreviewLayout = function(kind) return GF.RefreshPreviewLayout(kind) end
_G.MSUF_GF_RefreshPreviewBox = function(kind) return GF.RefreshPreviewLayout(kind) end
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
_G.MSUF_GF_StopDispelGlow = function(frame) return GF.StopDispelGlow(frame) end
_G.MSUF_GF_EM2_SetActivePreviewKind = function(kind) return GF.EM2_SetActivePreviewKind(kind) end
_G.MSUF_GF_EM2_NudgePreview = function(key, dx, dy) return GF.EM2_NudgePreview(key, dx, dy) end
