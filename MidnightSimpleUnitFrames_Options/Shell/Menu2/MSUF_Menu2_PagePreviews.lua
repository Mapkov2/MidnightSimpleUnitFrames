--- Menu2 page-driven preview coordination.
---
--- Keeps shell routing side effects out of the window builder. These helpers
--- synchronize Menu2 page visibility with boss unit previews and group-frame
--- runtime previews without owning the preview renderers themselves.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local function BossPagePreviewInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end
local function ClearBossPagePreviewForCombat()
    local clear = _G.MSUF_ClearBossUnitframePreviewForCombat
    return type(clear) == "function" and clear() == true
end
local function ApplyBossPagePreviewFallback(active, reason)
    if BossPagePreviewInCombat() then
        ClearBossPagePreviewForCombat()
        _G.MSUF2_BossUnitframePreviewActive = nil
        return
    end
    _G.MSUF2_BossUnitframePreviewActive = active and true or nil
    if type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
        _G.MSUF_ApplyBossUnitframePreviewState(active and true or false, reason or "MSUF2_BOSS_PAGE")
        return
    end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then _G.MSUF_SyncBossUnitframePreviewWithUnitEdit() end
end
local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end
local function BossPreviewFramesVisible()
    local sawFrame = false
    for i = 1, 5 do
        local unit = "boss" .. i
        local frame = CoreFrame(unit) or _G["MSUF_" .. unit]
        if frame then
            sawFrame = true
            if frame.IsShown and not frame:IsShown() then return false end
        end
    end
    return sawFrame
end
local lastBossPreviewActive
local lastBossPreviewFn
local lastCastbarPagePreviewUnit
local bossPreviewRequestSerial = 0

-- Out-of-menu castbar preview target for the global castbar page: the page's
-- unit segment picks which castbar runs a fake cast on the real frames.
local function CastbarPagePreviewUnitForKey(key)
    if key ~= "opt_castbar" then return nil end
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return nil end
    local unit = tostring(M._msuf2CastbarPreviewUnit or "player"):lower()
    if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "boss" then unit = "player" end
    return unit
end

local function SyncCastbarPagePreviewForKey(key, force)
    local apply = _G.MSUF_ApplyCastbarPagePreviewState
    if type(apply) ~= "function" then return end
    local unit = not BossPagePreviewInCombat() and CastbarPagePreviewUnitForKey(key) or nil
    if not force and lastCastbarPagePreviewUnit == unit then return end
    lastCastbarPagePreviewUnit = apply(unit) or nil
end

-- Boss aura lanes render on the out-of-menu boss preview frames only while the
-- boss page itself owns the preview; Auras3 edit-mode reads this flag.
local function SyncBossPageAuraPreviewFlag(auraActive)
    auraActive = auraActive == true and not BossPagePreviewInCombat()
    local current = _G.MSUF2_BossPageAuraPreviewActive == true
    if current == auraActive then return end
    _G.MSUF2_BossPageAuraPreviewActive = auraActive or nil
    local a3 = (MSUF and MSUF.MSUF_Auras3)
        or (_G.MSUF_NS and _G.MSUF_NS.MSUF_Auras3)
        or _G.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then a3.RefreshEditPreview("boss") end
end

local function SyncBossPagePreviewForKey(key, force)
    local frameShown = M.frame and M.frame.IsShown and M.frame:IsShown()
    local active = (key == "uf_boss") and frameShown
    if BossPagePreviewInCombat() then
        ClearBossPagePreviewForCombat()
        _G.MSUF2_BossUnitframePreviewActive = nil
        _G.MSUF2_BossPageAuraPreviewActive = nil
        lastBossPreviewActive = nil
        SyncCastbarPagePreviewForKey(key, false)
        return
    end
    SyncBossPageAuraPreviewFlag(active == true)
    -- The castbar page's boss segment borrows the boss frame preview so its
    -- castbar previews anchor under visible boss frames, exactly like live.
    local castbarUnit = CastbarPagePreviewUnitForKey(key)
    local bossActive = (active or castbarUnit == "boss") and true or false
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    local globalActive = (_G.MSUF2_BossUnitframePreviewActive == true)
    local visible = (not bossActive) or BossPreviewFramesVisible()
    if not force and lastBossPreviewActive == bossActive and lastBossPreviewFn == fn
        and globalActive == bossActive and visible
        and lastCastbarPagePreviewUnit == castbarUnit then
        return
    end
    lastBossPreviewActive = bossActive
    lastBossPreviewFn = fn
    if type(fn) == "function" then
        fn(bossActive)
        if bossActive and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" and not BossPagePreviewInCombat() then _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_CORE") end
    else
        ApplyBossPagePreviewFallback(bossActive, "MSUF2_BOSS_PAGE_FALLBACK")
    end
    SyncCastbarPagePreviewForKey(key, force)
end
local function RequestBossPagePreviewForKey(key, force)
    bossPreviewRequestSerial = bossPreviewRequestSerial + 1
    if force or key ~= "uf_boss" then
        SyncBossPagePreviewForKey(key, force)
        return
    end
    local timer = C_Timer
    if not (timer and type(timer.After) == "function") then
        SyncBossPagePreviewForKey(key, force)
        return
    end
    local serial = bossPreviewRequestSerial
    timer.After(0.05, function()
        if serial ~= bossPreviewRequestSerial then return end
        if M.activeKey ~= key then return end
        SyncBossPagePreviewForKey(key, force)
    end)
end
local function ResetBossPagePreviewCache()
    lastBossPreviewActive = nil
    lastBossPreviewFn = nil
    lastCastbarPagePreviewUnit = nil
    bossPreviewRequestSerial = bossPreviewRequestSerial + 1
end
local GF_PAGE_KEYS = M.KeySetFromWords "gf_layout gf_bars gf_auras gf_indicators"
local GF_BAR_MENU_PREVIEW_KEYS = M.KeySetFromWords "opt_bars"
local GF_SECTION_MENU_PREVIEW_KEYS = {
    opt_colors = {
        colors_group_frames = true,
    },
}
local gfMenuPreviewSectionOpen = M._gfMenuPreviewSectionOpen
if type(gfMenuPreviewSectionOpen) ~= "table" then
    gfMenuPreviewSectionOpen = {}
    M._gfMenuPreviewSectionOpen = gfMenuPreviewSectionOpen
end
local function IsGroupPageKey(key)
    return GF_PAGE_KEYS[key or ""] == true
end
local function IsGFBarMenuPreviewKey(key)
    return GF_BAR_MENU_PREVIEW_KEYS[key or ""] == true
end
local function GFPreviewSectionStateKey(pageKey, sectionId)
    return tostring(pageKey or "") .. "\031" .. tostring(sectionId or "")
end
local function IsGFMenuPreviewSection(pageKey, sectionId)
    local sections = GF_SECTION_MENU_PREVIEW_KEYS[tostring(pageKey or "")]
    return sections and sections[tostring(sectionId or "")] == true
end
local function IsGFSectionMenuPreviewKey(key)
    key = tostring(key or "")
    local sections = GF_SECTION_MENU_PREVIEW_KEYS[key]
    if not sections then return false end
    for sectionId in pairs(sections) do
        if gfMenuPreviewSectionOpen[GFPreviewSectionStateKey(key, sectionId)] == true then return true end
    end
    return false
end
local function IsGFDualMenuPreviewKey(key)
    return IsGFBarMenuPreviewKey(key) or IsGFSectionMenuPreviewKey(key)
end

-- Status test mode is a temporary visual aid from the menu. Clear it when Menu2 closes so
-- runtime frames do not keep fake dead/ghost/AFK indicators after the preview is gone.
local function ResetStatusIndicatorTestModeOnMenuExit()
    if type(M.EnsureDB) ~= "function" then return false end
    local db = M.EnsureDB()
    if type(db) ~= "table" then return false end
    local changed = false
    local generalChanged = false
    db.general = (type(db.general) == "table") and db.general or {}
    if db.general.stateIconsTestMode == true then
        db.general.stateIconsTestMode = false
        changed = true
        generalChanged = true
    end
    local unitsToApply = {}
    local seenUnits = {}
    local unitPages = M.UnitPage and M.UnitPage.UNIT_PAGES
    if type(unitPages) == "table" then
        for _, page in pairs(unitPages) do
            local unit = page and page.unit
            if unit == "tot" then unit = "targettarget" end
            if unit and not seenUnits[unit] then
                seenUnits[unit] = true
                local unitConf = db[unit]
                if type(unitConf) == "table" and unitConf.stateIconsTestMode == true then
                    unitConf.stateIconsTestMode = false
                    changed = true
                    unitsToApply[#unitsToApply + 1] = unit
                elseif generalChanged then
                    unitsToApply[#unitsToApply + 1] = unit
                end
            end
        end
    end
    if not changed then return false end
    if type(M.RequestUnitApply) ~= "function" then return true end
    for i = 1, #unitsToApply do
        M.RequestUnitApply(unitsToApply[i], "MSUF2_STATUS_TEST_MENU_EXIT", {
            preview = false,
        })
    end
    return true
end
local function CurrentGFMenuScope()
    local scope = M.gfScope
    if scope == "party" or scope == "raid" or scope == "mythicraid" then return scope end
    return "party"
end
local gfScalingBreakpointPreview = M._gfScalingBreakpointPreview
if type(gfScalingBreakpointPreview) ~= "table" then
    gfScalingBreakpointPreview = {}
    M._gfScalingBreakpointPreview = gfScalingBreakpointPreview
end
local function ApplyGFScalingBreakpointTransform(gf, kind)
    local layout = gf and gf._previewLayoutFrame and gf._previewLayoutFrame[kind]
    if not (layout and layout.SetScale) then return false end
    local state = gfScalingBreakpointPreview[kind]
    local ratio = 1
    if state then
        local liveScale = type(gf.ResolveFrameScale) == "function" and tonumber(gf.ResolveFrameScale(kind)) or 1
        if not liveScale or liveScale <= 0 then liveScale = 1 end
        local targetScale = (tonumber(state.scalePct) or 100) / 100
        if targetScale < 0.5 then targetScale = 0.5 elseif targetScale > 1.5 then targetScale = 1.5 end
        ratio = targetScale / liveScale
        if ratio < 0.2 then ratio = 0.2 elseif ratio > 3 then ratio = 3 end
    end
    if layout._msufGFMenuBreakpointScale ~= ratio then
        layout._msufGFMenuBreakpointScale = ratio
        layout:SetScale(ratio)
    end
    return true
end
local function GFPreviewCount(kind)
    local state = gfScalingBreakpointPreview[kind]
    local count = state and tonumber(state.count)
    if count and count > 0 then return math.floor(count + 0.5) end
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end
local BARS_MENU_PREVIEW_COUNT = 1
local function LiveRaidKind(gf)
    local kind = gf and type(gf.GetLiveRaidKind) == "function" and gf.GetLiveRaidKind() or nil
    if kind == "mythicraid" then return "mythicraid" end
    return "raid"
end
local function LiveGroupKind(gf)
    if gf and type(gf.GetLiveGroupKind) == "function" then return gf.GetLiveGroupKind() end
    if _G.IsInRaid and _G.IsInRaid() then return LiveRaidKind(gf) end
    if _G.IsInGroup and _G.IsInGroup() then return "party" end
    return nil
end
local function GroupPreviewRosterState(gf)
    local inGroup = _G.IsInGroup and _G.IsInGroup() and true or false
    local inRaid = _G.IsInRaid and _G.IsInRaid() and true or false
    local count = _G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers()) or 0
    if count < 0 then count = 0 end
    return inGroup, inRaid, math.floor(count + 0.5), LiveGroupKind(gf)
end
local function GroupConfEnabled(gf, kind)
    local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(kind) or nil
    return conf and conf.enabled == true
end
local function LiveGroupFramesCoverKind(gf, kind)
    kind = kind == "gf_party" and "party" or (kind == "gf_raid" and "raid" or (kind == "gf_mythicraid" and "mythicraid" or kind))
    local liveKind = LiveGroupKind(gf)
    if kind == "party" then
        if not GroupConfEnabled(gf, "party") then return false end
        local conf = gf and type(gf.GetConf) == "function" and gf.GetConf("party") or nil
        return liveKind == "party" or (liveKind == nil and conf and conf.showSolo == true) or false
    elseif kind == "raid" or kind == "mythicraid" then
        return liveKind == kind and GroupConfEnabled(gf, kind)
    end
    return false
end
local function RestoreGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if gf and type(gf.UpdateGroupVisibility) == "function" then gf.UpdateGroupVisibility() end
end
local function ShowGFPreviewWhenNoLiveFrames(gf, kind, count)
    if not (gf and type(gf.ShowPreview) == "function" and type(gf.HidePreview) == "function") then return false end
    if LiveGroupFramesCoverKind(gf, kind) then
        ApplyGFScalingBreakpointTransform(gf, kind)
        gf.HidePreview(kind)
        -- The preview itself suppresses the matching secure header. Hand live
        -- ownership back only after clearing that suppression; restoring first
        -- leaves the runtime with neither a preview nor a live header.
        RestoreGFHeaders(gf)
        return false
    end
    local shown = gf.ShowPreview(kind, count or GFPreviewCount(kind)) == true
    ApplyGFScalingBreakpointTransform(gf, kind)
    return shown
end

-- The global Bars page only needs one representative frame per group scope to show textures,
-- gradients, outlines, and highlights. Building the normal 5 + 30 full preview frames here
-- needlessly applies unit specs, auras, and spell indicators when the page opens.
local function ShowGFBarMenuPreviews(gf)
    if not gf then return end
    ShowGFPreviewWhenNoLiveFrames(gf, "party", BARS_MENU_PREVIEW_COUNT)
    ShowGFPreviewWhenNoLiveFrames(gf, "raid", BARS_MENU_PREVIEW_COUNT)
    gf.HidePreview("mythicraid")
end
local function SetGFPagePreviewFlag(active, kind)
    _G.MSUF2_GFPagePreviewActive = active and true or nil
    _G.MSUF2_GFPagePreviewKind = active and kind or nil
end
local function GFPreviewRuntimeActive(gf)
    if _G.MSUF2_GFPagePreviewActive == true then return true end
    local active = gf and gf._previewActive
    return active and (active.party or active.raid or active.mythicraid) and true or false
end
local function HideGFRuntimePreviews(gf, restoreHeaders)
    if not (gf and type(gf.HidePreview) == "function") then return end
    SetGFPagePreviewFlag(false)
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        gfScalingBreakpointPreview[kind] = nil
        ApplyGFScalingBreakpointTransform(gf, kind)
    end
    gf.HidePreview("party")
    gf.HidePreview("raid")
    gf.HidePreview("mythicraid")
    if gf.SetPreviewAnchor then
        gf.SetPreviewAnchor("party", nil)
        gf.SetPreviewAnchor("raid", nil)
        gf.SetPreviewAnchor("mythicraid", nil)
    end
    if restoreHeaders ~= false then RestoreGFHeaders(gf) end
end
local lastGFPreviewActive
local lastGFPreviewKind
local lastGFPreviewEditMode
local lastGFPreviewRuntime
local lastGFPreviewInGroup
local lastGFPreviewInRaid
local lastGFPreviewRosterCount
local lastGFPreviewLiveRaidKind
local groupPreviewRequestSerial = 0

-- Page previews borrow runtime group headers only while the menu owns focus. This cache avoids
-- repeatedly hiding/restoring secure headers when the selected page key has not changed.
local function SyncGroupPagePreviewForKey(key, force)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        SetGFPagePreviewFlag(false)
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(nil) end
        return
    end
    local frameVisible = M.frame and M.frame.IsShown and M.frame:IsShown()
    local dualMenuPreviews = IsGFDualMenuPreviewKey(key)
    local active = frameVisible and (IsGroupPageKey(key) or dualMenuPreviews)
    local gf = MSUF and MSUF.GF
    local kind = dualMenuPreviews and "bars" or CurrentGFMenuScope()
    local editMode = M.IsMSUFEditModeActive and M.IsMSUFEditModeActive() and true or false
    local hasRuntime = gf and type(gf.ShowPreview) == "function" and type(gf.HidePreview) == "function"
    local inGroup, inRaid, rosterCount, liveRaidKind = GroupPreviewRosterState(gf)
    if not force
        and lastGFPreviewActive == active
        and lastGFPreviewKind == kind
        and lastGFPreviewEditMode == editMode
        and lastGFPreviewRuntime == hasRuntime
        and lastGFPreviewInGroup == inGroup
        and lastGFPreviewInRaid == inRaid
        and lastGFPreviewRosterCount == rosterCount
        and lastGFPreviewLiveRaidKind == liveRaidKind
    then
        if active or not GFPreviewRuntimeActive(gf) then return end
    end
    lastGFPreviewActive = active
    lastGFPreviewKind = kind
    lastGFPreviewEditMode = editMode
    lastGFPreviewRuntime = hasRuntime
    lastGFPreviewInGroup = inGroup
    lastGFPreviewInRaid = inRaid
    lastGFPreviewRosterCount = rosterCount
    lastGFPreviewLiveRaidKind = liveRaidKind
    if editMode then
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(nil) end
        SetGFPagePreviewFlag(false)
        return
    end
    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind((active and not dualMenuPreviews) and kind or nil) end
    if not hasRuntime then
        SetGFPagePreviewFlag(active, kind)
        return
    end
    if not active then
        local classicPanel = _G.MSUF_GFOptionsPanel
        if classicPanel and classicPanel.IsShown and classicPanel:IsShown() then return end
        HideGFRuntimePreviews(gf, true)
        return
    end
    SetGFPagePreviewFlag(true, kind)
    RestoreGFHeaders(gf)
    if gf.SetPreviewAnchor then
        gf.SetPreviewAnchor("party", nil)
        gf.SetPreviewAnchor("raid", nil)
        gf.SetPreviewAnchor("mythicraid", nil)
    end
    if dualMenuPreviews then
        ShowGFBarMenuPreviews(gf)
        return
    end
    if kind ~= "party" then gf.HidePreview("party") end
    if kind ~= "raid" then gf.HidePreview("raid") end
    if kind ~= "mythicraid" then gf.HidePreview("mythicraid") end
    ShowGFPreviewWhenNoLiveFrames(gf, kind)
end
local function RequestGroupPagePreviewForKey(key, force)
    groupPreviewRequestSerial = groupPreviewRequestSerial + 1
    if force or not (IsGroupPageKey(key) or IsGFDualMenuPreviewKey(key)) then
        SyncGroupPagePreviewForKey(key, force)
        return
    end
    local timer = C_Timer
    if not (timer and type(timer.After) == "function") then
        SyncGroupPagePreviewForKey(key, force)
        return
    end
    local serial = groupPreviewRequestSerial
    timer.After(0.09, function()
        if serial ~= groupPreviewRequestSerial then return end
        if M.activeKey ~= key then return end
        SyncGroupPagePreviewForKey(key, force)
    end)
end
function M.SetGFScalingBreakpointPreview(kind, count, scalePct)
    if kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" then return false end
    local previous = gfScalingBreakpointPreview[kind]
    count, scalePct = tonumber(count), tonumber(scalePct)
    if count and count > 0 and scalePct and scalePct > 0 then
        gfScalingBreakpointPreview[kind] = {
            count = math.floor(count + 0.5),
            scalePct = scalePct,
        }
    else
        gfScalingBreakpointPreview[kind] = nil
    end
    local gf = MSUF and MSUF.GF
    local current = gfScalingBreakpointPreview[kind]
    if previous and current and previous.count == current.count then
        ApplyGFScalingBreakpointTransform(gf, kind)
        return true
    end
    local editMode = M.IsMSUFEditModeActive and M.IsMSUFEditModeActive() and true or false
    if editMode and gf and type(gf.ShowPreview) == "function" then
        gf.ShowPreview(kind, GFPreviewCount(kind))
        ApplyGFScalingBreakpointTransform(gf, kind)
        return true
    end
    RequestGroupPagePreviewForKey(M.activeKey, true)
    return true
end
local previousCollapsibleSectionStateChanged = M.OnCollapsibleSectionStateChanged
function M.OnCollapsibleSectionStateChanged(pageKey, sectionId, open, entry)
    if type(previousCollapsibleSectionStateChanged) == "function" then previousCollapsibleSectionStateChanged(pageKey, sectionId, open, entry) end
    if not IsGFMenuPreviewSection(pageKey, sectionId) then return end
    gfMenuPreviewSectionOpen[GFPreviewSectionStateKey(pageKey, sectionId)] = open and true or nil
    if M.activeKey == pageKey then RequestGroupPagePreviewForKey(pageKey, true) end
end
M.SyncBossPagePreviewForKey = SyncBossPagePreviewForKey
M.RequestBossPagePreviewForKey = RequestBossPagePreviewForKey
M.ResetBossPagePreviewCache = ResetBossPagePreviewCache
M.ResetStatusIndicatorTestModeOnMenuExit = ResetStatusIndicatorTestModeOnMenuExit
M.SyncGFPagePreviewForKey = SyncGroupPagePreviewForKey
M.RequestGFPagePreviewForKey = RequestGroupPagePreviewForKey
