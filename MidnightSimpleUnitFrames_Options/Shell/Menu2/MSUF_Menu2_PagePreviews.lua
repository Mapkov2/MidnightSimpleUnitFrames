--- Menu2 page-driven preview coordination.
---
--- Keeps shell routing side effects out of the window builder. These helpers
--- synchronize Menu2 page visibility with boss unit previews and group-frame
--- runtime previews without owning the preview renderers themselves.
local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/MSUF_Menu2_PagePreviews.lua"
local Preview = MSUF.UF.Preview
local previewKind = type(Preview)
assert(previewKind == "table",
  "MSUF: missing required dependency 'UF.Preview' required by Shell/Menu2/MSUF_Menu2_PagePreviews.lua")
local validateKind = type(Preview.Validate)
assert(validateKind == "function",
  "MSUF: missing required dependency 'UF.Preview.Validate' required by Shell/Menu2/MSUF_Menu2_PagePreviews.lua")
Preview.Validate("Shell/Menu2/MSUF_Menu2_PagePreviews.lua")
local SetArenaPage = Preview.SetArenaPage
local SetBossPage = Preview.SetBossPage
local previewState = Preview.State
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or C_Timer
local Optional = MSUF.Optional
local PublicGlobals = MSUF.PublicGlobals
local MAX_ARENA_FRAMES = MSUF.Client.MaxArenaOpponents
local function BossPagePreviewInCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
end
-- The core publishes the preview entry points; a client without one skips that step.
local function CallOptional(name, ...)
    local fn = Optional(name)
    if type(fn) == "function" then return fn(...) end
end
-- Boss and Arena page previews drive the same core entry points under different names.
local BOSS_FAMILY = {
    setPage = SetBossPage,
    reason = "MSUF2_BOSS_PAGE",
    clear = "MSUF_ClearBossUnitframePreviewForCombat",
    apply = "MSUF_ApplyBossUnitframePreviewState",
    sync = "MSUF_SyncBossUnitframePreviewWithUnitEdit",
}
local ARENA_FAMILY = {
    setPage = SetArenaPage,
    reason = "MSUF2_ARENA_PAGE",
    clear = "MSUF_ClearArenaUnitframePreviewForCombat",
    apply = "MSUF_ApplyArenaUnitframePreviewState",
    sync = "MSUF_SyncArenaUnitframePreviewWithUnitEdit",
}
local function ClearPagePreviewForCombat(family)
    return CallOptional(family.clear) == true
end
local function ApplyPagePreviewFallback(family, active, reason)
    if BossPagePreviewInCombat() then
        ClearPagePreviewForCombat(family)
        family.setPage(nil)
        return
    end
    family.setPage(active and true or nil)
    local apply = Optional(family.apply)
    if type(apply) == "function" then
        apply(active and true or false, reason or family.reason)
        return
    end
    CallOptional(family.sync)
end
local CoreFrame = MSUF.UF.GetFrame
local function PreviewFramesVisible(prefix, count)
    local sawFrame = false
    for i = 1, count do
        local unit = prefix .. i
        local frame = CoreFrame(unit) or _G["MSUF_" .. unit]
        if frame then
            sawFrame = true
            if frame.IsShown and not frame:IsShown() then return false end
        end
    end
    return sawFrame
end
local function BossPreviewFramesVisible()
    return PreviewFramesVisible("boss", 5)
end
local lastBossPreviewActive
local lastBossPreviewFn
local lastCastbarPagePreviewUnit

-- Out-of-menu castbar preview target for the global castbar page: the page's
-- unit segment picks which castbar runs a fake cast on the real frames.
local function CastbarPagePreviewUnitForKey(key)
    if key ~= "opt_castbar" then return nil end
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return nil end
    local unit = tostring(M._msuf2CastbarPreviewUnit or "player"):lower()
    if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "boss" and unit ~= "arena" then unit = "player" end
    return unit
end

local function SyncCastbarPagePreviewForKey(key, force)
    local apply = MSUF.Require("MSUF_ApplyCastbarPagePreviewState", FILE)
    local unit = not BossPagePreviewInCombat() and CastbarPagePreviewUnitForKey(key) or nil
    if not force and lastCastbarPagePreviewUnit == unit then return end
    lastCastbarPagePreviewUnit = apply(unit) or nil
end

-- Boss and Arena aura lanes render on the out-of-menu preview frames only while
-- their page owns the preview; Auras3 edit-mode reads these flags. The change
-- test reads the live namespace flag, never a copy.
local function SyncPageAuraPreviewFlag(unit, auraActive)
    auraActive = auraActive == true and not BossPagePreviewInCombat()
    if unit == "boss" then
        if (PublicGlobals.MSUF2_BossPageAuraPreviewActive == true) == auraActive then return end
        MSUF.ExportPublic("MSUF2_BossPageAuraPreviewActive", auraActive or nil)
    else
        if (PublicGlobals.MSUF2_ArenaPageAuraPreviewActive == true) == auraActive then return end
        MSUF.ExportPublic("MSUF2_ArenaPageAuraPreviewActive", auraActive or nil)
    end
    local a3 = MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then a3.RefreshEditPreview(unit) end
end

--- Arena page preview coordination: mirrors the boss lanes against the arena
--- preview globals so the same Window call sites drive both stacks.
local lastArenaPreviewActive
local lastArenaPreviewFn
local function SyncArenaPagePreviewForKey(key, force)
    local frameShown = M.frame and M.frame.IsShown and M.frame:IsShown()
    local active = (key == "uf_arena") and frameShown
    if BossPagePreviewInCombat() then
        ClearPagePreviewForCombat(ARENA_FAMILY)
        SetArenaPage(nil)
        SyncPageAuraPreviewFlag("arena", false)
        lastArenaPreviewActive = nil
        return
    end
    SyncPageAuraPreviewFlag("arena", active == true)
    -- The castbar page's arena segment borrows the Arena frame preview so its
    -- three castbar previews keep their live unit-frame-relative anchors.
    local castbarUnit = CastbarPagePreviewUnitForKey(key)
    local arenaActive = (active or castbarUnit == "arena") and true or false
    local fn = M.UnitPage and M.UnitPage.SetArenaPagePreviewActive
    local globalActive = (previewState.arenaPage == true)
    local visible = (not arenaActive) or PreviewFramesVisible("arena", MAX_ARENA_FRAMES)
    if not force and lastArenaPreviewActive == arenaActive and lastArenaPreviewFn == fn
        and globalActive == arenaActive and visible
        and lastCastbarPagePreviewUnit == castbarUnit then
        return
    end
    lastArenaPreviewActive = arenaActive
    lastArenaPreviewFn = fn
    if type(fn) == "function" then
        fn(arenaActive)
        if arenaActive and not BossPagePreviewInCombat() then CallOptional(ARENA_FAMILY.apply, true, "MSUF2_ARENA_PAGE_CORE") end
    else
        ApplyPagePreviewFallback(ARENA_FAMILY, arenaActive, "MSUF2_ARENA_PAGE_FALLBACK")
    end
end
local function SyncBossPagePreviewForKey(key, force)
    local frameShown = M.frame and M.frame.IsShown and M.frame:IsShown()
    local active = (key == "uf_boss") and frameShown
    -- Keep the arena preview in step for every Window-driven page change.
    SyncArenaPagePreviewForKey(key, force)
    if BossPagePreviewInCombat() then
        ClearPagePreviewForCombat(BOSS_FAMILY)
        SetBossPage(nil)
        SyncPageAuraPreviewFlag("boss", false)
        lastBossPreviewActive = nil
        SyncCastbarPagePreviewForKey(key, false)
        return
    end
    SyncPageAuraPreviewFlag("boss", active == true)
    -- The castbar page's boss segment borrows the boss frame preview so its
    -- castbar previews anchor under visible boss frames, exactly like live.
    local castbarUnit = CastbarPagePreviewUnitForKey(key)
    local bossActive = (active or castbarUnit == "boss") and true or false
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    local globalActive = (previewState.bossPage == true)
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
        if bossActive and not BossPagePreviewInCombat() then CallOptional(BOSS_FAMILY.apply, true, "MSUF2_BOSS_PAGE_CORE") end
    else
        ApplyPagePreviewFallback(BOSS_FAMILY, bossActive, "MSUF2_BOSS_PAGE_FALLBACK")
    end
    SyncCastbarPagePreviewForKey(key, force)
end
-- A newer request (or a cache reset) bumps its serial, which retires a still queued sync.
local requestSerial = { boss = 0, group = 0 }
local function RequestPagePreviewSync(which, delay, sync, key, force, immediate)
    requestSerial[which] = requestSerial[which] + 1
    local timer = C_Timer
    if force or immediate or not (timer and type(timer.After) == "function") then
        sync(key, force)
        return
    end
    local serial = requestSerial[which]
    timer.After(delay, function()
        if serial ~= requestSerial[which] then return end
        if M.activeKey ~= key then return end
        sync(key, force)
    end)
end
local function RequestBossPagePreviewForKey(key, force)
    RequestPagePreviewSync("boss", 0.05, SyncBossPagePreviewForKey, key, force, key ~= "uf_boss" and key ~= "uf_arena")
end
local function RequestArenaPagePreviewForKey(key, force)
    return RequestBossPagePreviewForKey(key, force)
end
local function ResetBossPagePreviewCache()
    lastBossPreviewActive = nil
    lastBossPreviewFn = nil
    lastArenaPreviewActive = nil
    lastArenaPreviewFn = nil
    lastCastbarPagePreviewUnit = nil
    requestSerial.boss = requestSerial.boss + 1
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
    for i = 1, #unitsToApply do
        M.RequestUnitDomains(unitsToApply[i], "MSUF2_STATUS_TEST_MENU_EXIT", {
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
    if IsInRaid and IsInRaid() then return LiveRaidKind(gf) end
    if IsInGroup and IsInGroup() then return "party" end
    return nil
end
local function GroupPreviewRosterState(gf)
    local inGroup = IsInGroup and IsInGroup() and true or false
    local inRaid = IsInRaid and IsInRaid() and true or false
    local count = GetNumGroupMembers and tonumber(GetNumGroupMembers()) or 0
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
local GF_KINDS = { "party", "raid", "mythicraid" }
local function RestoreGFHeaders(gf)
    if InCombatLockdown and InCombatLockdown() then return end
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
local function SetGFPagePreviewFlag(active)
    MSUF.ExportPublic("MSUF2_GFPagePreviewActive", active and true or nil)
end
local function GFPreviewRuntimeActive(gf)
    if PublicGlobals.MSUF2_GFPagePreviewActive == true then return true end
    local active = gf and gf._previewActive
    return active and (active.party or active.raid or active.mythicraid) and true or false
end
local function ClearGFPreviewAnchors(gf)
    if not gf.SetPreviewAnchor then return end
    for i = 1, #GF_KINDS do gf.SetPreviewAnchor(GF_KINDS[i], nil) end
end
local function HideGFRuntimePreviews(gf, restoreHeaders)
    if not (gf and type(gf.HidePreview) == "function") then return end
    SetGFPagePreviewFlag(false)
    for i = 1, #GF_KINDS do
        gfScalingBreakpointPreview[GF_KINDS[i]] = nil
        ApplyGFScalingBreakpointTransform(gf, GF_KINDS[i])
    end
    for i = 1, #GF_KINDS do gf.HidePreview(GF_KINDS[i]) end
    ClearGFPreviewAnchors(gf)
    if restoreHeaders ~= false then RestoreGFHeaders(gf) end
end
-- The last synced inputs: active, kind, edit mode, runtime present, in group, in
-- raid, roster count and live raid kind. The sync compares them field by field.
local lastGFPreviewInputs = {}
-- The group Edit Mode preview kind setter, a core export resolved once; every
-- sync calls it.
local SetActiveGFPreviewKind = MSUF.Require("MSUF_GF_EM2_SetActivePreviewKind", FILE)

-- Page previews borrow runtime group headers only while the menu owns focus. This cache avoids
-- repeatedly hiding/restoring secure headers when the selected page key has not changed.
local function SyncGroupPagePreviewForKey(key, force)
    if InCombatLockdown and InCombatLockdown() then
        SetGFPagePreviewFlag(false)
        SetActiveGFPreviewKind(nil)
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
    local last = lastGFPreviewInputs
    local unchanged = last.active == active and last.kind == kind and last.editMode == editMode
        and last.runtime == hasRuntime and last.inGroup == inGroup and last.inRaid == inRaid
        and last.rosterCount == rosterCount and last.liveRaidKind == liveRaidKind
    if not unchanged then
        last.active, last.kind, last.editMode, last.runtime = active, kind, editMode, hasRuntime
        last.inGroup, last.inRaid, last.rosterCount, last.liveRaidKind = inGroup, inRaid, rosterCount, liveRaidKind
    end
    if not force and unchanged and (active or not GFPreviewRuntimeActive(gf)) then return end
    if editMode then
        SetActiveGFPreviewKind(nil)
        SetGFPagePreviewFlag(false)
        return
    end
    SetActiveGFPreviewKind((active and not dualMenuPreviews) and kind or nil)
    if not hasRuntime then
        SetGFPagePreviewFlag(active)
        return
    end
    if not active then
        HideGFRuntimePreviews(gf, true)
        return
    end
    SetGFPagePreviewFlag(true)
    RestoreGFHeaders(gf)
    ClearGFPreviewAnchors(gf)
    if dualMenuPreviews then
        ShowGFBarMenuPreviews(gf)
        return
    end
    for i = 1, #GF_KINDS do
        if kind ~= GF_KINDS[i] then gf.HidePreview(GF_KINDS[i]) end
    end
    ShowGFPreviewWhenNoLiveFrames(gf, kind)
end
local function RequestGroupPagePreviewForKey(key, force)
    RequestPagePreviewSync("group", 0.09, SyncGroupPagePreviewForKey, key, force,
        not (IsGroupPageKey(key) or IsGFDualMenuPreviewKey(key)))
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
M.SyncArenaPagePreviewForKey = SyncArenaPagePreviewForKey
M.RequestArenaPagePreviewForKey = RequestArenaPagePreviewForKey
M.ResetBossPagePreviewCache = ResetBossPagePreviewCache
M.ResetStatusIndicatorTestModeOnMenuExit = ResetStatusIndicatorTestModeOnMenuExit
M.SyncGFPagePreviewForKey = SyncGroupPagePreviewForKey
M.RequestGFPagePreviewForKey = RequestGroupPagePreviewForKey

M.BossPreviewFramesVisible = BossPreviewFramesVisible
