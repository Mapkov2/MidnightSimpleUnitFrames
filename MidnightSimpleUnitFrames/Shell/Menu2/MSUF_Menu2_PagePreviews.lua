--- Menu2 page-driven preview coordination.
---
--- Keeps shell routing side effects out of the window builder. These helpers
--- synchronize Menu2 page visibility with boss unit previews and group-frame
--- runtime previews without owning the preview renderers themselves.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local function BossPagePreviewInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end
local function ApplyBossPagePreviewFallback(active, reason)
    if BossPagePreviewInCombat() then
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
local bossPreviewRequestSerial = 0
local function SyncBossPagePreviewForKey(key, force)
    local active = (key == "uf_boss")
        and M.frame and M.frame.IsShown and M.frame:IsShown()
    if BossPagePreviewInCombat() then
        _G.MSUF2_BossUnitframePreviewActive = nil
        lastBossPreviewActive = nil
        return
    end
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    local globalActive = (_G.MSUF2_BossUnitframePreviewActive == true)
    local visible = (not active) or BossPreviewFramesVisible()
    if not force and lastBossPreviewActive == active and lastBossPreviewFn == fn and globalActive == (active == true) and visible then return end
    lastBossPreviewActive = active
    lastBossPreviewFn = fn
    if type(fn) == "function" then
        fn(active and true or false)
        if active and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" and not BossPagePreviewInCombat() then _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_CORE") end
        return
    end
    ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
end
local function RequestBossPagePreviewForKey(key, force)
    bossPreviewRequestSerial = bossPreviewRequestSerial + 1
    if force or key ~= "uf_boss" then
        SyncBossPagePreviewForKey(key, force)
        return
    end
    local timer = _G.C_Timer
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
            notify = false,
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
local function GFPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end
local function LiveRaidKind(gf)
    local kind = gf and type(gf.GetLiveRaidKind) == "function" and gf.GetLiveRaidKind() or nil
    if kind == "mythicraid" then return "mythicraid" end
    return "raid"
end
local function GroupConfEnabled(gf, kind)
    local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(kind) or nil
    return conf and conf.enabled == true
end
local function LiveGroupFramesCoverKind(gf, kind)
    kind = kind == "gf_party" and "party" or (kind == "gf_raid" and "raid" or (kind == "gf_mythicraid" and "mythicraid" or kind))
    if kind == "party" then
        if _G.IsInRaid and _G.IsInRaid() then return false end
        if not GroupConfEnabled(gf, "party") then return false end
        local conf = gf and type(gf.GetConf) == "function" and gf.GetConf("party") or nil
        return (_G.IsInGroup and _G.IsInGroup()) or (conf and conf.showSolo == true) or false
    elseif kind == "raid" or kind == "mythicraid" then
        if not (_G.IsInRaid and _G.IsInRaid()) then return false end
        local liveKind = LiveRaidKind(gf)
        return GroupConfEnabled(gf, liveKind)
    end
    return false
end
local function ShowGFPreviewWhenNoLiveFrames(gf, kind)
    if not (gf and type(gf.ShowPreview) == "function" and type(gf.HidePreview) == "function") then return false end
    if LiveGroupFramesCoverKind(gf, kind) then
        gf.HidePreview(kind)
        return false
    end
    return gf.ShowPreview(kind, GFPreviewCount(kind)) == true
end

-- The global Bars page previews party and raid at once. Mythic raid stays hidden here because
-- it shares raid settings and would add visual noise without showing a different control path.
local function ShowGFBarMenuPreviews(gf)
    if not gf then return end
    ShowGFPreviewWhenNoLiveFrames(gf, "party")
    ShowGFPreviewWhenNoLiveFrames(gf, "raid")
    gf.HidePreview("mythicraid")
end
local function SetGFPagePreviewFlag(active, kind)
    _G.MSUF2_GFPagePreviewActive = active and true or nil
    _G.MSUF2_GFPagePreviewKind = active and kind or nil
end
local function RestoreGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if gf and type(gf.UpdateGroupVisibility) == "function" then gf.UpdateGroupVisibility() end
end
local function GFPreviewRuntimeActive(gf)
    if _G.MSUF2_GFPagePreviewActive == true then return true end
    local active = gf and gf._previewActive
    return active and (active.party or active.raid or active.mythicraid) and true or false
end
local function HideGFRuntimePreviews(gf, restoreHeaders)
    if not (gf and type(gf.HidePreview) == "function") then return end
    SetGFPagePreviewFlag(false)
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
    if not force
        and lastGFPreviewActive == active
        and lastGFPreviewKind == kind
        and lastGFPreviewEditMode == editMode
        and lastGFPreviewRuntime == hasRuntime
    then
        if active or not GFPreviewRuntimeActive(gf) then return end
    end
    lastGFPreviewActive = active
    lastGFPreviewKind = kind
    lastGFPreviewEditMode = editMode
    lastGFPreviewRuntime = hasRuntime
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
    local timer = _G.C_Timer
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
