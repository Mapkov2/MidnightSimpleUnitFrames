--- EditMode/MSUF_EditMode_Compat.lua - Edit Mode global entry points
--- Global entry points other files call: the Edit Mode switch, the popup and
--- preview syncs and the castbar anchor toggle. (MSUF_EditState is published
--- by Core, which loads first.)
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic
local EM2 = _G.MSUF_EM2
if not EM2 then return end
--- Loads with Elements: without a registry neither runs.
if not EM2.Registry then return end

local U = EM2.Util or {}
local IsConfigCombatLocked = U.IsConfigCombatLocked
local FrameRectToUI = _G.MSUF_UF_FrameRectToUI
local RefreshUFPreview = EM2.Movers.RefreshUFPreview

--- --- MSUF_IsInEditMode ---
local function MSUF_IsInEditMode()
    if EM2.State then return EM2.State.IsActive() end
    return _G.MSUF_UnitEditModeActive == true
end
ExportPublic("MSUF_IsInEditMode", MSUF_IsInEditMode)

--- Castbar code still calls this guarded refresh; the old edit info panel it
--- updated is gone, so it does nothing.
local function LegacyNoop() end
local function OpenMoverPopup(prefix, fallback, unit, parent)
    if EM2.Popups then
        EM2.Popups.Open(prefix and (prefix .. tostring(unit or "")) or unit, parent)
    elseif fallback and fallback.Open then
        fallback.Open(unit, parent)
    end
end

ExportPublic("MSUF_UpdateCastbarEditInfo", LegacyNoop)

local function MSUF_OpenCastbarPositionPopup(unit, parent)
    OpenMoverPopup("castbar_", EM2.CastPopup, unit, parent)
end
ExportPublic("MSUF_OpenCastbarPositionPopup", MSUF_OpenCastbarPositionPopup)

local function MSUF_OpenAuras3PositionPopup(unit, parent)
    OpenMoverPopup("aura_", EM2.AuraPopup, unit, parent)
end
ExportPublic("MSUF_OpenAuras3PositionPopup", MSUF_OpenAuras3PositionPopup)

--- --- MSUF_SyncUnitPositionPopup ---
local function MSUF_SyncUnitPositionPopup(unit)
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_UNIT_POPUP", unit)
end
ExportPublic("MSUF_SyncUnitPositionPopup", MSUF_SyncUnitPositionPopup)

--- --- MSUF_SyncCastbarPositionPopup ---
local function MSUF_SyncCastbarPositionPopup(unit)
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_CASTBAR_POPUP", unit)
end
ExportPublic("MSUF_SyncCastbarPositionPopup", MSUF_SyncCastbarPositionPopup)

--- --- MSUF_SyncAuras3PositionPopup ---
local function MSUF_SyncAuras3PositionPopup(unit)
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    local menu = MSUF and MSUF.MSUF2
    if menu and type(menu.SyncAuras3PositionSettings) == "function" then
        menu.SyncAuras3PositionSettings(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
end
ExportPublic("MSUF_SyncAuras3PositionPopup", MSUF_SyncAuras3PositionPopup)

--- --- MSUF_SetMSUFEditModeDirect (THE primary entry point) ---
local function MSUF_SetMSUFEditModeDirect(active, unitKey)
    if not EM2.State then return end
    if active and type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return false end
    if active and IsConfigCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return false
    end
    if active and type(_G.MSUF_EnsureOptionsLoaded) == "function"
        and not _G.MSUF_EnsureOptionsLoaded("edit-mode")
    then
        return false
    end
    if active and type(_G.MSUF_TryOpenExternalEditMode) == "function"
        and _G.MSUF_TryOpenExternalEditMode(unitKey) then
        return true
    end
    if not active and type(_G.MSUF_TryCloseExternalEditMode) == "function"
        and _G.MSUF_TryCloseExternalEditMode() then
        return true
    end
    if active then EM2.State.Enter(unitKey)
    else EM2.State.Exit("direct") end
    return true
end
ExportPublic("MSUF_SetMSUFEditModeDirect", MSUF_SetMSUFEditModeDirect)

--- --- Preview System ---
--- One global flag: MSUF_PreviewTestMode. Mirrors MSUF_BossTestMode exactly.
--- The core's visibility driver (line 2000) checks this flag to force-show.
--- The core's UpdateSimpleUnitFrame (line 4017) already applies EditPrev data.
--- Zero hooks, zero timers, zero pipeline fighting.
ExportPublic("MSUF_UnitPreviewActive", false)
ExportPublic("MSUF_PreviewTestMode", false)

local PREVIEW_UNITS = { "target", "focus", "focustarget", "targettarget", "pet", "pettarget" }
local CASTBAR_TEST_FUNCS = {
    "MSUF_SetPlayerCastbarTestMode",
    "MSUF_SetTargetCastbarTestMode",
    "MSUF_SetFocusCastbarTestMode",
    "MSUF_SetBossCastbarTestMode",
    "MSUF_SetArenaCastbarTestMode",
}
local previewMoverSyncQueued = false
local previewReforceQueued = false
local SyncCastbarEditModeWithUnitEdit

local function SchedulePreviewMoverSync(delay)
    if not (EM2.Movers and EM2.Movers.SyncAll) then return end
    if previewMoverSyncQueued then return end
    previewMoverSyncQueued = true
    local function Run()
        previewMoverSyncQueued = false
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end
    C_Timer.After(delay or 0.08, Run)
end

local function GetPreviewFrame(unitKey)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(unitKey)
        if frame then return frame end
    end
    local frames = UF and UF.frames
    return (frames and frames[unitKey])
        or _G["MSUF_" .. unitKey]
end

local function ReforcePreviewFrame(frame, _, want)
    if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
    if want then
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.EnableMouse then frame:EnableMouse(true) end
    end
end

local function ForPreviewFrames(fn, value)
    for _, unitKey in ipairs(PREVIEW_UNITS) do
        local frame = GetPreviewFrame(unitKey)
        if frame then fn(frame, unitKey, value) end
    end
end

local function SyncMoversAfterReforce()
    if _G.MSUF_PreviewTestMode and EM2.Movers and EM2.Movers.SyncAll then
        EM2.Movers.SyncAll()
    end
end

local function MSUF_EM2_ReforcePreviewFrames()
    if not _G.MSUF_PreviewTestMode then return end
    if IsConfigCombatLocked() then return end
    ForPreviewFrames(ReforcePreviewFrame, true)
    if EM2.Movers and EM2.Movers.SyncAll then
        EM2.Movers.SyncAll()
        C_Timer.After(0, SyncMoversAfterReforce)
    end
end
ExportPublic("MSUF_EM2_ReforcePreviewFrames", MSUF_EM2_ReforcePreviewFrames)

local function RunQueuedPreviewReforce()
    previewReforceQueued = false
    MSUF_EM2_ReforcePreviewFrames()
end

local function MSUF_EM2_SchedulePreviewReforce()
    if previewReforceQueued then return end
    previewReforceQueued = true
    C_Timer.After(0.1, RunQueuedPreviewReforce)
end

local function MSUF_SyncAllUnitPreviews()
    local active = _G.MSUF_UnitPreviewActive and true or false
    local editOn = EM2.State and EM2.State.IsActive()
    local want = active and editOn

    if IsConfigCombatLocked() then
        ExportPublic("MSUF_PreviewTestMode", false)
        ExportPublic("MSUF_BossTestMode", false)
        ExportPublic("MSUF_ArenaTestMode", false)
        if type(_G.MSUF_HideAllCastbarPreviews) == "function" then
            _G.MSUF_HideAllCastbarPreviews()
        end
        return
    end

    --- Set preview flag (core visibility driver reads this)
    ExportPublic("MSUF_PreviewTestMode", want)

    --- 1) Boss: existing system
    ExportPublic("MSUF_BossTestMode", want)
    if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end

    --- 1b) Arena: mirrors the boss preview system
    ExportPublic("MSUF_ArenaTestMode", want)
    if _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit()
    end

    --- 2) Non-player: refresh visibility drivers (reads MSUF_PreviewTestMode),
    --- then update each frame (pipeline calls EditPrev for unitless frames)
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
    end

    ForPreviewFrames(ReforcePreviewFrame, want)
    --- 3) Castbars
    local beginBossBatch = _G.MSUF_BeginBossCastbarPreviewBatch
    local endBossBatch = _G.MSUF_EndBossCastbarPreviewBatch
    local batchingBossPreview = type(beginBossBatch) == "function" and type(endBossBatch) == "function"
    if batchingBossPreview then beginBossBatch() end
    SyncCastbarEditModeWithUnitEdit()
    --- Animated castbar motion is owned by the on-demand preview animation driver.
    for _, fn in ipairs(CASTBAR_TEST_FUNCS) do
        local f = _G[fn]; if type(f) == "function" then f(false, true) end
    end
    if batchingBossPreview then endBossBatch() end

    --- 4) Aura refresh
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then
        a3.RefreshEditPreview()
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end

    --- 5) Sync movers
    SchedulePreviewMoverSync(0.08)
    if want then
        MSUF_EM2_SchedulePreviewReforce()
    end
end

ExportPublic("MSUF_SyncAllUnitPreviews", MSUF_SyncAllUnitPreviews)

--- --- Auto-reforce wrappers ---
--- Visual update functions can overwrite preview text/bars/colors while Edit
--- Mode preview is active. Wrap MSUF-owned entry points only for the active
--- preview window, then restore originals when preview mode stops.
do
    local PIPELINE_REFORCE_NAMES = {
        "MSUF_UpdateAllFonts",
        "MSUF_UpdateAllFonts_Immediate",
        "MSUF_RefreshAllIdentityColors",
        "MSUF_RefreshAllPowerTextColors",
        "MSUF_UpdateAllBarTextures",
        "MSUF_UpdateAllBarTextures_Immediate",
        "MSUF_ApplyBarOutlineThickness_All",
        "MSUF_ApplyPowerBarBorder_All",
        "MSUF_ApplyReverseFillBars",
        "MSUF_UpdateCastbarVisuals",
        "MSUF_UpdateCastbarVisuals_Immediate",
        "MSUF_UpdateCastbarTextures",
        "MSUF_UpdateCastbarTextures_Immediate",
        "MSUF_RefreshUnitDispelOverlays",
        "MSUF_ApplyAllAlpha",
    }
    local wrapped = {}
    local wrappers = {}
    local unpackResults = table.unpack or unpack

    local function ScheduleReforce(delay)
        if not _G.MSUF_PreviewTestMode then return end
        if IsConfigCombatLocked() then return end
        C_Timer.After(delay or 0, function()
            if not _G.MSUF_PreviewTestMode then return end
            if IsConfigCombatLocked() then return end
            MSUF_EM2_ReforcePreviewFrames()
        end)
    end

    local function UninstallPipelineWrappers()
        for name, original in pairs(wrapped) do
            if _G[name] == wrappers[name] then
                _G[name] = original
            end
            wrapped[name] = nil
            wrappers[name] = nil
        end
    end

    local function InstallPipelineWrappers()
        if not _G.MSUF_PreviewTestMode then return end
        for _, name in ipairs(PIPELINE_REFORCE_NAMES) do
            if not wrapped[name] and type(_G[name]) == "function" then
                local original = _G[name]
                local function wrapper(...)
                    if not _G.MSUF_PreviewTestMode then
                        UninstallPipelineWrappers()
                        return original(...)
                    end
                    --- A colour wheel or slider drag calls this per value
                    --- change: queue one coalesced reforce (it runs on a
                    --- timer, so before the call is fine) and tail-call.
                    if not IsConfigCombatLocked() then MSUF_EM2_SchedulePreviewReforce() end
                    return original(...)
                end
                wrapped[name] = original
                wrappers[name] = wrapper
                _G[name] = wrapper
            end
        end
    end

    local originalSyncAllUnitPreviews = MSUF_SyncAllUnitPreviews
    local function SyncAllUnitPreviewsWithPipelineWrappers(...)
        if _G.MSUF_PreviewTestMode then
            InstallPipelineWrappers()
        else
            UninstallPipelineWrappers()
        end

        local results = { originalSyncAllUnitPreviews(...) }

        if _G.MSUF_PreviewTestMode then
            InstallPipelineWrappers()
            ScheduleReforce(0.05)
            ScheduleReforce(0.20)
        else
            UninstallPipelineWrappers()
        end

        return unpackResults(results)
    end

    MSUF_SyncAllUnitPreviews = SyncAllUnitPreviewsWithPipelineWrappers
    ExportPublic("MSUF_SyncAllUnitPreviews", SyncAllUnitPreviewsWithPipelineWrappers)

    local asyncPreviewSerial = 0
    local function SyncAllUnitPreviewsAsync()
        asyncPreviewSerial = asyncPreviewSerial + 1
        local serial = asyncPreviewSerial
        local active = _G.MSUF_UnitPreviewActive and true or false
        local editOn = EM2.State and EM2.State.IsActive()
        local want = active and editOn

        if IsConfigCombatLocked() then
            ExportPublic("MSUF_PreviewTestMode", false)
            ExportPublic("MSUF_BossTestMode", false)
            ExportPublic("MSUF_ArenaTestMode", false)
            if type(_G.MSUF_HideAllCastbarPreviews) == "function" then
                _G.MSUF_HideAllCastbarPreviews()
            end
            UninstallPipelineWrappers()
            return
        end

        ExportPublic("MSUF_PreviewTestMode", want)
        ExportPublic("MSUF_BossTestMode", want)
        ExportPublic("MSUF_ArenaTestMode", want)
        if want then
            InstallPipelineWrappers()
        else
            UninstallPipelineWrappers()
        end

        local timer = C_Timer
        if not (timer and type(timer.After) == "function") then
            return SyncAllUnitPreviewsWithPipelineWrappers()
        end

        local function Alive()
            if serial ~= asyncPreviewSerial then return false end
            if IsConfigCombatLocked() then return false end
            if want and not (_G.MSUF_UnitPreviewActive and EM2.State and EM2.State.IsActive()) then return false end
            return true
        end

        local function Phase(delay, fn)
            timer.After(delay, function()
                if not Alive() then return end
                fn()
            end)
        end

        Phase(0, function()
            if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
                _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
            end
            if _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit then
                _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit()
            end
        end)

        Phase(0.02, function()
            if _G.MSUF_RefreshAllUnitVisibilityDrivers then
                _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
            end
        end)

        Phase(0.04, function()
            ForPreviewFrames(ReforcePreviewFrame, want)
        end)

        Phase(0.06, function()
            local beginBossBatch = _G.MSUF_BeginBossCastbarPreviewBatch
            local endBossBatch = _G.MSUF_EndBossCastbarPreviewBatch
            local batchingBossPreview = type(beginBossBatch) == "function" and type(endBossBatch) == "function"
            if batchingBossPreview then beginBossBatch() end
            SyncCastbarEditModeWithUnitEdit()
            --- Animated castbar motion is owned by the on-demand preview animation driver.
            for _, fn in ipairs(CASTBAR_TEST_FUNCS) do
                local f = _G[fn]; if type(f) == "function" then f(false, true) end
            end
            if batchingBossPreview then endBossBatch() end
        end)

        Phase(0.08, function()
            local a3 = MSUF and MSUF.MSUF_Auras3
            if a3 and type(a3.RefreshEditPreview) == "function" then
                a3.RefreshEditPreview()
            elseif a3 and type(a3.RefreshAll) == "function" then
                a3.RefreshAll()
            end
        end)

        Phase(0.10, function()
            SchedulePreviewMoverSync(0.02)
            if want then
                MSUF_EM2_SchedulePreviewReforce()
                ScheduleReforce(0.05)
                ScheduleReforce(0.20)
                InstallPipelineWrappers()
            else
                UninstallPipelineWrappers()
            end
        end)
    end
    ExportPublic("MSUF_SyncAllUnitPreviewsAsync", SyncAllUnitPreviewsAsync)
end

--- --- Castbar preview sync ---
function SyncCastbarEditModeWithUnitEdit()
    local db = _G.MSUF_DB
    if not db then return end
    db.general = db.general or {}
    local g = db.general
    local active = EM2.State and EM2.State.IsActive()
    g.castbarPlayerPreviewEnabled = active and true or false
    if not active and type(_G.MSUF_HideAllCastbarPreviews) == "function" then
        _G.MSUF_HideAllCastbarPreviews()
    end

    if type(_G.MSUF_UpdatePlayerCastbarPreview) == "function" then
        _G.MSUF_UpdatePlayerCastbarPreview()
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    elseif not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

--- --- Castbar anchor toggle (detach/attach to unitframe) ---
local function CastbarToggleFrameCenter(unit)
    local preview, runtime
    if unit == "player" then
        preview = _G.MSUF_PlayerCastbarPreview
        runtime = _G.MSUF_PlayerCastbar
    elseif unit == "target" then
        preview = _G.MSUF_TargetCastbarPreview
        runtime = _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar
    elseif unit == "focus" then
        preview = _G.MSUF_FocusCastbarPreview
        runtime = _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar
    elseif unit == "boss" then
        preview = _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1
        local bossCastbars = _G.MSUF_BossCastbars
        runtime = (bossCastbars and bossCastbars[1])
            or _G.MSUF_BossCastbar1
            or _G.MSUF_boss1CastBar
    elseif unit == "arena" then
        preview = _G.MSUF_ArenaCastbarPreview or _G.MSUF_ArenaCastbarPreview1
        local arenaCastbars = _G.MSUF_ArenaCastbars
        runtime = (arenaCastbars and arenaCastbars[1])
            or _G.MSUF_ArenaCastbar1
    end

    local function Center(frame)
        local left, right, top, bottom = FrameRectToUI(frame)
        if left then return frame, (left + right) * 0.5, (top + bottom) * 0.5 end
    end

    local frame, x, y = Center(preview)
    if frame then return frame, x, y end
    return Center(runtime)
end

local function ApplyCastbarAnchorState(unit)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
    else
        local reanchorFns = {
            player = "MSUF_ReanchorPlayerCastBar",
            target = "MSUF_ReanchorTargetCastBar",
            focus  = "MSUF_ReanchorFocusCastBar",
            boss   = "MSUF_ApplyBossCastbarPositionSetting",
            arena  = "MSUF_ApplyArenaCastbarPositionSetting",
        }
        local ra = reanchorFns[unit]
        if ra and type(_G[ra]) == "function" then _G[ra]() end
        if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        elseif _G.MSUF_UpdateCastbarVisuals then
            _G.MSUF_UpdateCastbarVisuals(unit)
        end
    end

    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then
        _G.MSUF_PositionCastbarPreviewUnit(unit)
    end
end

local RoundCastbarOffset = _G.MSUF_RoundOffset

local MSUF_EM_SetCastbarAnchoredToUnit = function(unit, anchored)
    if not unit then return end
    local db = _G.MSUF_DB; if not db then return end
    db.general = db.general or {}
    local g = db.general

    local detachedKey, oxKey, oyKey
    if unit == "boss" then
        detachedKey = "bossCastbarDetached"
        oxKey = "bossCastbarOffsetX"
        oyKey = "bossCastbarOffsetY"
    elseif unit == "arena" then
        detachedKey = "arenaCastbarDetached"
        oxKey = "arenaCastbarOffsetX"
        oyKey = "arenaCastbarOffsetY"
    else
        local prefix = _G.MSUF_GetCastbarPrefix and _G.MSUF_GetCastbarPrefix(unit)
        if not prefix then return end
        detachedKey = prefix .. "Detached"
        oxKey = prefix .. "OffsetX"
        oyKey = prefix .. "OffsetY"
    end

    local wantDetached = (anchored == false)
    if (g[detachedKey] == true) == wantDetached then return end

    local castbar, beforeX, beforeY = CastbarToggleFrameCenter(unit)
    g[detachedKey] = wantDetached or nil
    ApplyCastbarAnchorState(unit)

    if castbar and beforeX and beforeY then
        local left, right, top, bottom = FrameRectToUI(castbar)
        if left then
            local afterX = (left + right) * 0.5
            local afterY = (top + bottom) * 0.5
            local frameScale = castbar.GetEffectiveScale and tonumber(castbar:GetEffectiveScale()) or 1
            local uiScale = UIParent.GetEffectiveScale and tonumber(UIParent:GetEffectiveScale()) or 1
            if not frameScale or frameScale <= 0 then frameScale = 1 end
            if not uiScale or uiScale <= 0 then uiScale = 1 end

            local defaultX, defaultY = 0, 0
            if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then
                defaultX, defaultY = _G.MSUF_GetCastbarDefaultOffsets(unit)
            end
            local currentX = tonumber(g[oxKey]) or tonumber(defaultX) or 0
            local currentY = tonumber(g[oyKey]) or tonumber(defaultY) or 0
            local localPerUI = uiScale / frameScale
            local nextX = RoundCastbarOffset(currentX + (beforeX - afterX) * localPerUI)
            local nextY = RoundCastbarOffset(currentY + (beforeY - afterY) * localPerUI)
            if nextX ~= currentX or nextY ~= currentY then
                g[oxKey], g[oyKey] = nextX, nextY
                ApplyCastbarAnchorState(unit)
            end
        end
    end

    RefreshUFPreview("EM2_CASTBAR_ANCHOR_TOGGLE", unit)
end
ExportPublic("MSUF_EM_SetCastbarAnchoredToUnit", MSUF_EM_SetCastbarAnchoredToUnit)
