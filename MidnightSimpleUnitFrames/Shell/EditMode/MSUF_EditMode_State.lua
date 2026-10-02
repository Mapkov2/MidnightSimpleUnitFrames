--- EditMode/MSUF_EditMode_State.lua - Edit Mode state machine
--- Manages: enter/exit lifecycle, combat lockdown, AnyEditMode listeners,
--- boss preview, Blizzard EM sync, and keeps all legacy globals in sync.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic
local function PublishCompat(name, value)
    return ExportPublic(name, value)
end
local EM2 = _G.MSUF_EM2
local Util = EM2.Util

local ApplyGroupSettingsForKeySafe = Util.ApplyGroupSettingsForKeySafe
local ProfileIdentity, IsCurrentProfile = Util.ProfileIdentity, Util.IsCurrentProfile
local SharedHistoryService = Util.SharedHistoryService

local State = {}
EM2.State = State
local ENTER_DEFER_DELAY = 0.03

--- Internal state
local active      = false
local unitKey     = nil
local provider    = nil
local externalPreviewSuspended = false
local combatFrame = nil
local combatEventMode = nil
local pendingCombatExitApply = false
local enterGeneration = 0
local externalResumeGeneration = 0

local IsConfigCombatLocked = Util.IsConfigCombatLocked
local ShowConfigCombatLockMessage = Util.ShowConfigCombatLockMessage

--- Legacy global sync (contract with 30+ external files)
local function SyncLegacy()
    local previewActive = active and not externalPreviewSuspended
    PublishCompat("MSUF_UnitEditModeActive", previewActive)
    PublishCompat("MSUF_CurrentEditUnitKey", unitKey)
    local st = _G.MSUF_EditState
    if st then
        st.active  = previewActive
        st.unitKey = unitKey
    end
end

--- Ensure MSUF_EditState table exists (other files rawget it)
local editState = _G.MSUF_EditState
if type(editState) ~= "table" then
    editState = {
        active              = false,
        unitKey             = nil,
        popupOpen           = false,
        arrowBindingsActive = false,
        fatalDisabled       = false,
    }
end
PublishCompat("MSUF_EditState", editState)

--- AnyEditMode listener notifications
local anyEditModeListeners = _G.MSUF_AnyEditModeListeners
if type(anyEditModeListeners) ~= "table" then anyEditModeListeners = {} end
PublishCompat("MSUF_AnyEditModeListeners", anyEditModeListeners)

local MSUF_RegisterAnyEditModeListener = _G.MSUF_RegisterAnyEditModeListener
if type(MSUF_RegisterAnyEditModeListener) ~= "function" then
    MSUF_RegisterAnyEditModeListener = function(fn)
        if type(fn) ~= "function" then return end
        local t = _G.MSUF_AnyEditModeListeners
        t[#t + 1] = fn
    end
end
ExportPublic("MSUF_RegisterAnyEditModeListener", MSUF_RegisterAnyEditModeListener)

local lastNotified = nil
local function NotifyListeners()
    local previewActive = active and not externalPreviewSuspended
    if lastNotified == previewActive then return end
    lastNotified = previewActive
    local t = _G.MSUF_AnyEditModeListeners
    if not t then return end
    for i = 1, #t do
        local fn = t[i]
        if type(fn) == "function" then
            fn(previewActive)
        end
    end
end

local function EnsureDB()
    if _G.MSUF_DB then return true end
    local fn = _G.MSUF_EnsureDB
    if type(fn) == "function" then fn(); return _G.MSUF_DB ~= nil end
    local nsEnsureDB = MSUF and (MSUF.MSUF_EnsureDB or MSUF.EnsureDB)
    if type(nsEnsureDB) == "function" then nsEnsureDB(); return _G.MSUF_DB ~= nil end
    return false
end
local ApplyAllSettingsSafe = Util.ApplyAllSettingsSafe
local ApplySettingsForKeySafe = Util.ApplySettingsForKeySafe
--- Public read-only accessors
function State.IsActive()      return active end
function State.GetUnitKey()    return unitKey end
function State.GetProvider()   return provider end
function State.IsExternalPreviewSuspended() return externalPreviewSuspended end

function State.SetUnitKey(key)
    unitKey = key
    SyncLegacy()
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = "state", syncState = false })
    end
end

function State.SetPopupOpen(open)
    local st = _G.MSUF_EditState
    if st then st.popupOpen = open and true or false end
end

--- Global snapshot for Cancel All (restore pre-edit-mode state). This is the
--- complete active profile, not only geometry keys: Menu2 can remain open
--- while Edit Mode is active, so Cancel All must also roll back settings made
--- from that surface during the same Edit Mode session.
local _snapshot = nil
local _snapshotProfile = nil

local function GetDeepCopy()
    return _G.MSUF_DeepCopy
end

local function SnapshotDB()
    local dc = GetDeepCopy()
    local db = _G.MSUF_DB; if not db or not dc then _snapshot = nil; _snapshotProfile = nil; return end
    _snapshot = dc(db)
    _snapshotProfile = ProfileIdentity()
end

local function RestoreSnapshotTable(dst, src, seen)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    seen = seen or {}
    seen[src] = dst
    for key in pairs(dst) do
        if src[key] == nil then dst[key] = nil end
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if seen[value] then
                dst[key] = seen[value]
            else
                if type(dst[key]) ~= "table" then dst[key] = {} end
                RestoreSnapshotTable(dst[key], value, seen)
            end
        else
            dst[key] = value
        end
    end
    return true
end

local function InvalidateAllFrameCaches()
    local UF = MSUF and MSUF.UF
    if UF and type(UF.ForEachFrame) == "function" then
        UF.ForEachFrame(function(f)
            if f and f.cachedConfig then f.cachedConfig = nil end
        end)
        return
    end
    local frames = UF and UF.frames
    if not frames then return end
    for _, f in pairs(frames) do
        if f and f.cachedConfig then f.cachedConfig = nil end
    end
end

local function FlushPendingCommits()
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
        st.queued  = false
        st.fonts   = false
        st.fontKey = nil
        st.bars    = false
        st.castbars  = false
        st.tickers   = false
        st.bossPreview = false
    end
    local ufSt = _G.MSUF_UnitFrameApplyState
    if ufSt then
        if ufSt.dirty then
            for k in pairs(ufSt.dirty) do ufSt.dirty[k] = nil end
        end
        ufSt.queued = false
    end
end

local function HardHideEditModePreviews()
    PublishCompat("MSUF_UnitPreviewActive", false)
    PublishCompat("MSUF_PreviewTestMode", false)
    PublishCompat("MSUF_BossTestMode", false)
    PublishCompat("MSUF2_BossUnitframePreviewActive", nil)
    --- Arena mirrors the boss preview flags. Leaving them raised keeps the
    --- secure "[nocombat] show" driver on arena1-N after exit.
    PublishCompat("MSUF_ArenaTestMode", false)
    PublishCompat("MSUF2_ArenaUnitframePreviewActive", nil)

    local hideCastbars = _G.MSUF_HideAllCastbarPreviews
    if type(hideCastbars) == "function" then
        hideCastbars()
    end

    local hideGroup = _G.MSUF_GF_EM2_HidePreview
    if type(hideGroup) == "function" then
        hideGroup()
    end
end

local function PlayLogoIntro()
    local play = _G.MSUF_PlayEditModeLogoIntro
    if type(play) == "function" then
        play()
    end
end

local function StopLogoIntro()
    local stop = _G.MSUF_StopEditModeLogoIntro
    if type(stop) == "function" then
        stop()
    end
end

local function RestoreRuntimeAfterEditModeExit()
    --- The arena preview writes synthetic opponent data into the real arena
    --- buttons; its owner strips that data (combat-safe) and re-applies the
    --- arena visibility, alpha, aura and castbar-preview lanes.
    if _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncArenaUnitframePreviewWithUnitEdit()
    end
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(false)
    end
    if _G.MSUF_UpdateBossCastbarPreview then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    --- Inside an arena preparation room the preview replaced the prep
    --- opponent identity; re-seed it exactly as PLAYER_ENTERING_WORLD does.
    if _G.MSUF_ArenaMatch_SyncPrepDisplay then
        _G.MSUF_ArenaMatch_SyncPrepDisplay()
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then
        a3.RefreshEditPreview()
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end
end

local function RestoreAfterCombatExit()
    pendingCombatExitApply = false
    HardHideEditModePreviews()
    ApplyAllSettingsSafe()
    RestoreRuntimeAfterEditModeExit()
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
end

local function RestoreDB()
    if type(_snapshot) ~= "table" then return false end
    local db = _G.MSUF_DB; if not db then return false end
    if not IsCurrentProfile(_snapshotProfile) then
        _snapshot, _snapshotProfile = nil, nil
        return false
    end
    RestoreSnapshotTable(db, _snapshot)
    _snapshot, _snapshotProfile = nil, nil
    return true
end

--- A focused popup box applies its text on OnEditFocusLost, which the client
--- also fires when the popup hides. Cancel All and the combat exit drop that
--- half-typed text before anything else (EditPopupUI Quick.DiscardFocusedEdits).
local function DiscardFocusedPopupEdits()
    local quick = EM2.QuickPopup
    if quick and quick.DiscardFocusedEdits then quick.DiscardFocusedEdits() end
end

local function ExternalEditModeAPI()
    local api = (type(MSUF) == "table" and MSUF.EditModeAPI) or _G.MSUF_EditModeAPI
    return type(api) == "table" and api or nil
end

--- ENTER Edit Mode
function State.Enter(key, opts)
    if IsConfigCombatLocked() then
        ShowConfigCombatLockMessage()
        return false
    end

    local requestedProvider = type(opts) == "table" and opts.provider or "msuf"
    if requestedProvider ~= "ellesmere" then requestedProvider = "msuf" end

    if active then
        if provider ~= requestedProvider then return false end
        --- Already active: just switch unit
        if key then
            unitKey = key
            SyncLegacy()
            EM2.OnUnitChanged(key)
        end
        return true
    end
    if not EnsureDB() then return end

    -- Cancel All is a transactional guarantee. Capture the pre-entry database
    -- before exposing the active state so an immediate menu action cannot
    -- mutate settings ahead of the old deferred snapshot.
    SnapshotDB()

    if requestedProvider == "msuf" then
        local api = ExternalEditModeAPI()
        if api and type(api._BeginSession) == "function" then api._BeginSession() end
    end

    local history = SharedHistoryService()
    if history and type(history.StartHistorySession) == "function" then
        history.StartHistorySession("edit_mode")
    end

    active  = true
    unitKey = key or "player"
    provider = requestedProvider
    externalPreviewSuspended = false
    local ownsNativeShell = provider == "msuf"
    enterGeneration = enterGeneration + 1
    local enterToken = enterGeneration
    SyncLegacy()
    if ownsNativeShell then PlayLogoIntro() end
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end

    --- Arrow key nudge
    if ownsNativeShell and _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(true)
    end

    --- Preview must be active before the apply pipeline queues its boss sync.
    PublishCompat("MSUF_UnitPreviewActive", true)

    --- Start ticker (zero overhead when stopped)
    if ownsNativeShell and EM2.Ticker and EM2.Ticker.Start then EM2.Ticker.Start() end

    --- Show grid + HUD + focus synchronously for instant visual feedback.
    if ownsNativeShell then
        if EM2.Grid   and EM2.Grid.Show   then EM2.Grid.Show()   end
        if EM2.HUD    and EM2.HUD.Show    then EM2.HUD.Show()    end
        if EM2.Focus  and EM2.Focus.Show  then EM2.Focus.Show(unitKey) end
    end

    local function EntryPreviewReady()
        return enterGeneration == enterToken and active
            and not externalPreviewSuspended and not IsConfigCombatLocked()
    end

    --- Let the logo and shell paint before the heavier preview/listener work.
    C_Timer.After(ENTER_DEFER_DELAY, function()
        if not EntryPreviewReady() then return end

        --- (Auras3 is refreshed inside MSUF_SyncAllUnitPreviews below; calling it
        --- here too just doubled the work on the entry frame and spiked the click.)

        --- Entering edit mode changes no actual settings - it only flips preview
        --- and visibility flags. A full ApplyAllSettings (re-apply every element on
        --- every frame) was the dominant entry CPU spike. We only need frames that
        --- are normally hidden (e.g. target with no target) to appear, which is a
        --- visibility-driver refresh - far cheaper. The heavier per-frame preview
        --- pass runs deferred via MSUF_SyncAllUnitPreviews on the next frame.
        if _G.MSUF_RefreshAllUnitVisibilityDrivers then
            _G.MSUF_RefreshAllUnitVisibilityDrivers(true)
        else
            ApplyAllSettingsSafe()
        end

        local function SyncUnitPreviewsAfterEnter()
            if not EntryPreviewReady() then return end
            if _G.MSUF_SyncAllUnitPreviewsAsync then
                _G.MSUF_SyncAllUnitPreviewsAsync()
            elseif _G.MSUF_SyncAllUnitPreviews then
                _G.MSUF_SyncAllUnitPreviews()
            end
        end

        local function ReforceUnitPreviewsAfterEnter()
            if not EntryPreviewReady() then return end
            if _G.MSUF_EM2_ReforcePreviewFrames then
                _G.MSUF_EM2_ReforcePreviewFrames()
            elseif _G.MSUF_SyncAllUnitPreviews then
                _G.MSUF_SyncAllUnitPreviews()
            end
            if ownsNativeShell then Util.SyncMovers() end
        end

        --- Preview: defer the (heavy) preview sync to the next frame so the click
        --- that opens edit mode stays responsive. Later settle passes only re-force
        --- preview frames and mover bounds; repeating the full sync reruns Auras3,
        --- castbar previews, visibility drivers, and boss preview work.
        C_Timer.After(0, SyncUnitPreviewsAfterEnter)
        C_Timer.After(0.1, function()
            ReforceUnitPreviewsAfterEnter()
        end)
        C_Timer.After(0.25, function()
            ReforceUnitPreviewsAfterEnter()
        end)

        --- Notify listeners (Auras3 previews etc.)
        NotifyListeners()

        --- Movers can create a frame per registered element on first entry; defer
        --- that to the next frame so it doesn't pile onto the entry spike. Guard
        --- against an immediate exit before the timer fires.
        C_Timer.After(0, function()
            if not EntryPreviewReady() then return end
            if ownsNativeShell and EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
        end)
    end)
    return true
end

--- EXIT Edit Mode
function State.Exit(source)
    if not active then return end
    local exitingProvider = provider
    enterGeneration = enterGeneration + 1
    local exitToken = enterGeneration
    --- PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns
    --- true, so a combat exit takes the combat path on the source alone; the
    --- deferred restore below would otherwise run one frame into combat.
    local combatLocked = source == "combat" or ((InCombatLockdown and InCombatLockdown()) and true or false)

    --- Combat start cannot apply a half-typed popup value (protected writes)
    --- and the history closes below, so the text is dropped.
    if combatLocked then DiscardFocusedPopupEdits() end

    --- Stop ticker FIRST (zero overhead from this point). A drag that is still
    --- held keeps its position: the ticker commits an external element's
    --- previewed position while the session is open (on a combat exit this is
    --- still inside PLAYER_REGEN_DISABLED, before lockdown).
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop(true) end

    --- Combat may interrupt an active drag or a debounced nudge. Cancel its
    --- timers before hiding widgets can fire OnHide commits. The shared
    --- history service retains the before-state and finalizes it only after
    --- combat, without taking a DB snapshot here.
    if combatLocked and EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange(true) end

    --- Hide movers + HUD + grid first (visual instant response)
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end
    if EM2.Focus  and EM2.Focus.Hide   then EM2.Focus.Hide()  end

    --- Close all popups
    if EM2.Popups and EM2.Popups.CloseAll then
        EM2.Popups.CloseAll()
    end

    --- Flip state
    active  = false
    unitKey = nil
    provider = nil
    externalPreviewSuspended = false
    PublishCompat("MSUF_BossTestMode", false)
    PublishCompat("MSUF_ArenaTestMode", false)
    PublishCompat("MSUF_PreviewTestMode", false)
    SyncLegacy()
    StopLogoIntro()

    --- Arrow keys off
    if _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(false)
    end

    --- Preview state must be cleared exactly once. In combat, protected frames
    --- cannot be safely re-shown/re-anchored, so defer the full restore until
    --- PLAYER_REGEN_ENABLED.
    HardHideEditModePreviews()
    if combatLocked then
        pendingCombatExitApply = true
    else
        local function RestoreAfterExitFrame()
            if enterGeneration ~= exitToken or active then return end
            --- Combat began before this frame ran: restore after combat.
            if InCombatLockdown and InCombatLockdown() then
                pendingCombatExitApply = true
                if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
                return
            end
            ApplyAllSettingsSafe()
            RestoreRuntimeAfterEditModeExit()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RestoreAfterExitFrame)
        else
            RestoreAfterExitFrame()
        end
    end

    --- Notify listeners
    NotifyListeners()
    local history = SharedHistoryService()
    if history and type(history.EndHistorySession) == "function" then
        history.EndHistorySession("edit_mode")
    end
    if exitingProvider == "msuf" then
        local api = ExternalEditModeAPI()
        if api and type(api._EndSession) == "function" then api._EndSession("save") end
    end
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
end

--- Profile boundary (MSUF.ProfileRuntime.BeforeMutation): profile storage is
--- about to switch, reset, rename, delete or import into the active profile.
--- The session ends against the profile it edited, and pending undo work is
--- dropped first so no deferred commit lands in the next profile.
function State.ExitForProfileChange()
    if not active then return false end
    if EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end
    State.Exit("profile")
    return true
end

--- CANCEL ALL - restore DB to pre-edit-mode state, then exit
function State.CancelAll()
    if not active then return end
    local exitingProvider = provider
    enterGeneration = enterGeneration + 1

    --- Drop half-typed popup text before the restore: closing the popups
    --- afterwards would commit it on top of the restored profile.
    DiscardFocusedPopupEdits()

    --- Stop ticker FIRST so no OnUpdate can write offsets after restore.
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

    --- Kill any pending async commits - they would re-apply dragged offsets
    --- after we restore the snapshot, overwriting our restore.
    FlushPendingCommits()
    if EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end

    local history = SharedHistoryService()
    local restored = history and type(history.CancelHistorySurface) == "function"
        and history.CancelHistorySurface("edit_mode", true) == true
    if restored then
        _snapshot = nil
    else
        --- Menu2 history can be unavailable during an early load failure. Keep
        --- the complete local profile snapshot as a fail-safe Cancel All path.
        restored = RestoreDB()
    end

    --- Teardown UI
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end
    if EM2.Focus  and EM2.Focus.Hide   then EM2.Focus.Hide()  end
    if EM2.Popups and EM2.Popups.CloseAll then EM2.Popups.CloseAll() end

    active  = false
    unitKey = nil
    provider = nil
    externalPreviewSuspended = false
    PublishCompat("MSUF_BossTestMode", false)
    PublishCompat("MSUF_ArenaTestMode", false)
    PublishCompat("MSUF_PreviewTestMode", false)
    PublishCompat("MSUF_UnitPreviewActive", false)
    SyncLegacy()
    StopLogoIntro()

    if _G.MSUF_EnableArrowKeyNudge then _G.MSUF_EnableArrowKeyNudge(false) end

    if restored then
        --- Invalidate all frame config caches so the pipeline reads the
        --- freshly restored DB tables, not stale references to the old
        --- (dragged) config objects.
        InvalidateAllFrameCaches()

        --- Apply synchronously - the async path can silently drop when a
        --- pending commit is already scheduled.
        ApplyAllSettingsSafe()

        --- Belt-and-suspenders: force SetPoint on every unit frame with
        --- the restored offsetX/Y from the DB.
        if _G.MSUF_ForceReanchorAllUnitFrames_Once then
            _G.MSUF_ForceReanchorAllUnitFrames_Once()
        end
        -- Cancel replaces the top-level config tables. Force the dedicated
        -- Priority Frames owner to reacquire gf_priority and restore its secure
        -- header/anchor immediately, just like unit frames above.
        ApplyGroupSettingsForKeySafe("priority")
    else
        --- Snapshot was unavailable - best-effort exit.
        ApplyAllSettingsSafe()
    end

    HardHideEditModePreviews()
    RestoreRuntimeAfterEditModeExit()

    NotifyListeners()
    if history and type(history.EndHistorySession) == "function" then
        history.EndHistorySession("edit_mode")
    end
    if exitingProvider == "msuf" then
        local api = ExternalEditModeAPI()
        if api and type(api._EndSession) == "function" then api._EndSession("discard") end
    end
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
end

--- EllesmereUI owns the unlock shell but keeps MSUF's preview transaction open.
--- Its combat behavior suspends instead of closing Unlock Mode, so these two
--- cold-path hooks hide and restore only preview visuals without committing or
--- discarding the MSUF database snapshot.
function State.SuspendExternalPreview()
    if not active or provider ~= "ellesmere" or externalPreviewSuspended then return false end
    local suspendBridge = _G.MSUF_EllesmereEditMode_SuspendPreview
    if type(suspendBridge) == "function" then
        suspendBridge()
    elseif type(_G.MSUF_EllesmereEditMode_ClearMoveState) == "function" then
        _G.MSUF_EllesmereEditMode_ClearMoveState()
    end
    externalPreviewSuspended = true
    SyncLegacy()
    NotifyListeners()
    HardHideEditModePreviews()
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
    return true
end

function State.ResumeExternalPreview()
    if not active or provider ~= "ellesmere" or not externalPreviewSuspended then return false end
    if IsConfigCombatLocked() then return false end
    externalPreviewSuspended = false
    SyncLegacy()
    PublishCompat("MSUF_UnitPreviewActive", true)
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(true)
    else
        ApplyAllSettingsSafe()
    end
    if _G.MSUF_SyncAllUnitPreviewsAsync then
        _G.MSUF_SyncAllUnitPreviewsAsync()
    elseif _G.MSUF_SyncAllUnitPreviews then
        _G.MSUF_SyncAllUnitPreviews()
    end
    NotifyListeners()
    local resumeBridge = _G.MSUF_EllesmereEditMode_ResumePreview
    if type(resumeBridge) == "function" then resumeBridge() end
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
    return true
end

--- Combat guard: native Edit Mode exits; EllesmereUI sessions suspend and resume.
--- Events are registered only for the active edit session or a pending restore,
--- so normal combat has no Edit Mode shell event overhead.
function State.EnsureCombatListener()
    if combatFrame then return end
    combatFrame = CreateFrame("Frame")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and active then
            if provider == "ellesmere" then
                State.SuspendExternalPreview()
            else
                State.Exit("combat")
                ShowConfigCombatLockMessage()
            end
        elseif event == "PLAYER_REGEN_ENABLED" and pendingCombatExitApply then
            RestoreAfterCombatExit()
        elseif event == "PLAYER_REGEN_ENABLED" and active
            and provider == "ellesmere" and externalPreviewSuspended then
            local token = enterGeneration
            externalResumeGeneration = externalResumeGeneration + 1
            local resumeToken = externalResumeGeneration
            local function resume()
                if token ~= enterGeneration or resumeToken ~= externalResumeGeneration
                    or not active or provider ~= "ellesmere" then return end
                State.ResumeExternalPreview()
            end
            if C_Timer and C_Timer.After then
                -- EllesmereUI restores its own Unlock Mode movers after 0.5s.
                C_Timer.After(0.55, resume)
            else
                resume()
            end
        end
        if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
    end)
end

function State.UpdateCombatListenerRegistration()
    local wantedMode
    if active and provider == "ellesmere" then
        wantedMode = externalPreviewSuspended and "external-regen" or "external"
    elseif active then
        wantedMode = "active"
    elseif pendingCombatExitApply then
        wantedMode = "regen"
    end
    if combatEventMode == wantedMode then return end
    State.EnsureCombatListener()
    if combatFrame and combatEventMode then
        combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    combatEventMode = wantedMode
    if wantedMode == "active" then
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif wantedMode == "external" then
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    elseif wantedMode == "regen" or wantedMode == "external-regen" then
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

--- Stub: called when unit selection changes while already active
function EM2.OnUnitChanged(key)
    if EM2.HUD    and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
    if EM2.Movers and EM2.Movers.RefreshSelection then EM2.Movers.RefreshSelection(key) end
    if EM2.Focus  and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "state", syncState = false }) end
end
