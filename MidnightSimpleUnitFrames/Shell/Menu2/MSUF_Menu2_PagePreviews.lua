--- Menu2 page-driven preview coordination.
---
--- Keeps shell routing side effects out of the window builder. These helpers
--- synchronize Menu2 page visibility with boss unit previews and group-frame
--- runtime previews without owning the preview renderers themselves.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M
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
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) end
end
local lastBossPreviewActive
local lastBossPreviewFn
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
    if not force and lastBossPreviewActive == active and lastBossPreviewFn == fn and globalActive == (active == true) then return end
    lastBossPreviewActive = active
    lastBossPreviewFn = fn
    if type(fn) == "function" then
        local ok = pcall(fn, active and true or false)
        if ok then
            if active and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" and not BossPagePreviewInCombat() then _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_CORE") end
        else
            ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
        end
        return
    end
    ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
end
local function ResetBossPagePreviewCache()
    lastBossPreviewActive = nil
    lastBossPreviewFn = nil
end
local GF_PAGE_KEYS = M.KeySetFromWords "gf_layout gf_bars gf_auras gf_indicators"
local GF_BAR_MENU_PREVIEW_KEYS = M.KeySetFromWords "opt_bars"
local function IsGroupPageKey(key)
    return GF_PAGE_KEYS[key or ""] == true
end
local function IsGFBarMenuPreviewKey(key)
    return GF_BAR_MENU_PREVIEW_KEYS[key or ""] == true
end
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
local function ShowGFBarMenuPreviews(gf)
    if not gf then return end
    gf.ShowPreview("party", GFPreviewCount("party"))
    gf.ShowPreview("raid", GFPreviewCount("raid"))
    gf.HidePreview("mythicraid")
    if type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout("party")
        gf.RefreshPreviewLayout("raid")
    end
end
local function SetGFPagePreviewFlag(active, kind)
    _G.MSUF2_GFPagePreviewActive = active and true or nil
    _G.MSUF2_GFPagePreviewKind = active and kind or nil
end
local function HideGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if not (gf and gf.headers) then return end
    if gf.headers.party then gf.headers.party:Hide() end
    if type(gf.HideRaidHeaders) == "function" then gf.HideRaidHeaders(true)
    elseif gf.headers.raid then gf.headers.raid:Hide() end
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
local function SyncGroupPagePreviewForKey(key, force)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        SetGFPagePreviewFlag(false)
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(nil) end
        return
    end
    local frameVisible = M.frame and M.frame.IsShown and M.frame:IsShown()
    local barMenuPreviews = IsGFBarMenuPreviewKey(key)
    local active = frameVisible and (IsGroupPageKey(key) or barMenuPreviews)
    local gf = MSUF and MSUF.GF
    local kind = barMenuPreviews and "bars" or CurrentGFMenuScope()
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
    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind((active and not barMenuPreviews) and kind or nil) end
    if editMode then
        SetGFPagePreviewFlag(false)
        return
    end
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
    HideGFHeaders(gf)
    if gf.SetPreviewAnchor then
        gf.SetPreviewAnchor("party", nil)
        gf.SetPreviewAnchor("raid", nil)
        gf.SetPreviewAnchor("mythicraid", nil)
    end
    if barMenuPreviews then
        ShowGFBarMenuPreviews(gf)
        return
    end
    if kind ~= "party" then gf.HidePreview("party") end
    if kind ~= "raid" then gf.HidePreview("raid") end
    if kind ~= "mythicraid" then gf.HidePreview("mythicraid") end
    gf.ShowPreview(kind, GFPreviewCount(kind))
    if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(kind) end
end
M.SyncBossPagePreviewForKey = SyncBossPagePreviewForKey
M.ResetBossPagePreviewCache = ResetBossPagePreviewCache
M.ResetStatusIndicatorTestModeOnMenuExit = ResetStatusIndicatorTestModeOnMenuExit
M.SyncGFPagePreviewForKey = SyncGroupPagePreviewForKey
