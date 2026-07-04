--- MSUF_EM2_Core.lua - Registry + State + Undo + Init (consolidated)

--- MSUF_EM2_Registry.lua

--- MSUF_EM2_Registry.lua
--- Element registration API for Edit Mode 2.
--- Every moveable element (unit frame, castbar, aura group, class power)
--- registers here. EditMode core iterates the registry - never hardcoded lists.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local function PublishCompat(name, value)
    return ExportPublic(name, value)
end

local EM2 = _G.MSUF_EM2
if type(EM2) ~= "table" then EM2 = {} end
PublishCompat("MSUF_EM2", EM2)

local Util = EM2.Util
if type(Util) ~= "table" then Util = {} end
EM2.Util = Util

local function EditCoreProfileStart()
    local menu = MSUF and MSUF.MSUF2
    if menu and menu.PerfProfile and menu.PerfProfile.enabled == true and menu.ProfileStart then
        return menu.ProfileStart()
    end
end

local function EditCoreProfileStop(bucket, key, started)
    local menu = MSUF and MSUF.MSUF2
    if menu and menu.PerfProfile and menu.PerfProfile.enabled == true and menu.ProfileStop then
        menu.ProfileStop(bucket, key, started)
    end
end

function Util.ApplyAllSettingsSafe()
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        local started = EditCoreProfileStart()
        UF.Apply(nil)
        EditCoreProfileStop("editApply", "UF.ApplyAll", started)
        return true
    end
    return false
end

function Util.ApplySettingsForKeySafe(key)
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        local started = EditCoreProfileStart()
        local ok = UF.Apply(key) == true
        EditCoreProfileStop("editApply", "UF.Apply:" .. tostring(key or "nil"), started)
        return ok
    end
    return false
end

function Util.Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then
        return MSUF.Translate(text)
    end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

function Util.SharedUI()
    return (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
end

function Util.ThemeColor(key, fallback)
    local ui = Util.SharedUI()
    if ui and ui.Color then return ui.Color(key, fallback) end
    return fallback
end

function Util.IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then return true end
    return false
end

function Util.ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    elseif print then
        print("|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end

function Util.BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if Util.IsConfigCombatLocked() then
        Util.ShowConfigCombatLockMessage()
        return true
    end
    return false
end

function Util.RefreshUFPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2") end
end

function Util.SyncMovers()
    if EM2.Movers and EM2.Movers.SyncAll then
        local started = EditCoreProfileStart()
        EM2.Movers.SyncAll()
        EditCoreProfileStop("editApply", "Movers.SyncAll", started)
    end
end

function Util.NotifyPositionChanged(key, immediate)
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, immediate) end
end

function Util.SyncMoversAndNotify(key, immediate)
    Util.SyncMovers()
    Util.NotifyPositionChanged(key, immediate)
end

function Util.SetMenuFocusRequest(opts)
    if type(opts) ~= "table" then return nil end
    local request = {
        key = opts.key,
        component = opts.component,
        slot = opts.slot,
        pageKey = opts.pageKey,
        sectionId = opts.sectionId,
        source = opts.source,
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    PublishCompat("MSUF_EM2_MenuFocusRequest", request)
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M then M.editModeSelection = request end
    return request
end

function Util.WirePopupFocus(btn, getKey, component, source, slot)
    if not (btn and btn.HookScript) then return btn end
    btn:HookScript("OnEnter", function()
        local key = type(getKey) == "function" and getKey() or getKey
        if key and EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(key, component, slot, { source = source })
        end
    end)
    btn:HookScript("OnLeave", function()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover(source) end
    end)
    return btn
end

function Util.Round(n)
    return n + (2^52 + 2^51) - (2^52 + 2^51)
end

function Util.UnitSectionForComponent(component)
    if not component or component == "frame" or component == "layout" or component == "bounds" or component == "size" then return "frame_basics" end
    if component == "name" or component == "hp" or component == "power" or component == "text" then return "text" end
    if component == "auras" then return "auras3" end
    if component == "castbar" or component == "cast" then return "castbar" end
    if component == "powerbar" or component == "power_bar" or component == "detached" or component == "detachedpowerbar" then return "power_bar" end
    if component == "anchor" or component == "anchoring" then return "anchoring" end
    if component == "portrait" then return "portrait" end
    if component == "alpha" or component == "transparency" then return "transparency" end
    if component == "status" or component == "status_icons" then return "status_icons" end
    return "frame_basics"
end

--- Shared unit metadata used by EditMode focus and quick popups.
--- Keeping page keys and labels here prevents silent drift between popup buttons,
--- focus routing, and Menu2 deep-link requests.
Util.UNIT_PAGE_KEYS = Util.UNIT_PAGE_KEYS or {
    player = "uf_player",
    target = "uf_target",
    targettarget = "uf_targettarget",
    focustarget = "uf_focustarget",
    focus = "uf_focus",
    pet = "uf_pet",
    boss = "uf_boss",
}
Util.UNIT_LABELS = Util.UNIT_LABELS or {
    player = "Player",
    target = "Target",
    targettarget = "ToT",
    focustarget = "Focus Target",
    focus = "Focus",
    pet = "Pet",
    boss = "Boss",
}
function Util.UnitPageKey(unit, fallback)
    local key = Util.UNIT_PAGE_KEYS[unit]
    if key then return key end
    if fallback ~= nil then return fallback end
    return "uf_player"
end
function Util.UnitLabel(unit)
    return Util.UNIT_LABELS[unit] or tostring(unit or "")
end
function Util.NormalizeUnitKey(unit)
    if not unit then return nil end
    if unit == "targettarget" or unit == "tot" then return "targettarget" end
    if unit == "focustarget" or unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit) then return "boss" end
    return unit
end
function Util.NormalizeSimpleUnit(unit, allowBossIndex)
    if unit == "boss" then return allowBossIndex and "boss1" or "boss" end
    if allowBossIndex and type(unit) == "string" and unit:match("^boss%d+$") then return unit end
    if (not allowBossIndex) and type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "pet" then return unit end
    return nil
end

function Util.NormalizeFocusKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    key = key:lower()
    if key:sub(1, 5) == "aura_" then return Util.NormalizeFocusKey(key:sub(6)) end
    if key == "tot" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if key == "uf_player" then return "player" end
    if key == "uf_target" then return "target" end
    if key == "uf_targettarget" then return "targettarget" end
    if key == "uf_focustarget" then return "focustarget" end
    if key == "uf_focus" then return "focus" end
    if key == "uf_pet" then return "pet" end
    if key == "uf_boss" then return "boss" end
    if key:match("^boss%d+$") then return "boss" end
    return key
end

function Util.NormalizeFocusComponent(component)
    if type(component) ~= "string" or component == "" then return nil end
    component = component:lower()
    if component == "health" or component == "healthtext" or component == "hptext" then return "hp" end
    if component == "powertext" then return "power" end
    if component == "aura" or component == "buff" or component == "buffs" or component == "debuff" or component == "debuffs" then return "auras" end
    if component == "cast" then return "castbar" end
    return component
end

function Util.NormalizeFocusSlot(slot)
    if type(slot) ~= "string" or slot == "" then return nil end
    slot = slot:lower()
    if slot == "l" then return "left" end
    if slot == "c" then return "center" end
    if slot == "r" then return "right" end
    return slot
end

function Util.SyncUnitTextMenuState(M, key, component, slot)
    if not (M and key and (component == "name" or component == "hp" or component == "power")) then return end
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    M.unitTextTabSelection[key] = component
    if slot then
        M.unitTextSlotSelection = M.unitTextSlotSelection or {}
        M.unitTextSlotSelection[key] = M.unitTextSlotSelection[key] or {}
        M.unitTextSlotSelection[key][component] = slot
    end
end

local Registry = {}
EM2.Registry = Registry

local elements = {}
local order    = {}
local dirty    = true

--- Register a moveable element.
--- cfg fields:
--- key (string) unique identifier ("player", "castbar_player", "aura_target", ...)
--- label (string) display name for mover overlay
--- order (number) sort priority (lower = earlier)
--- getFrame (function) -> frame returns the live frame reference
--- getConf (function) -> table returns the DB config table for this element
--- popupType (string) "unit" | "castbar" | "aura" | "classpower" | "custom" | nil
--- isEnabled (function) -> bool whether element exists and should show a mover
--- canResize (bool) whether mover allows resize handles
--- canNudge (bool) whether arrow keys can move this element (default true)
--- onEnter (function) optional callback when edit mode enters
--- onExit (function) optional callback when edit mode exits
function Registry.Register(cfg)
    if not cfg or not cfg.key then return end
    elements[cfg.key] = cfg
    dirty = true
end

function Registry.Unregister(key)
    if not key then return end
    elements[key] = nil
    dirty = true
end

function Registry.Get(key)
    return elements[key]
end

function Registry.All()
    return elements
end

--- Sorted key list. Rebuilt lazily when dirty.
function Registry.Order()
    if not dirty then return order end
    local n = 0
    for k in pairs(elements) do
        n = n + 1
        order[n] = k
    end
    for i = n + 1, #order do order[i] = nil end
    table.sort(order, function(a, b)
        local oa = elements[a].order or 1000
        local ob = elements[b].order or 1000
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    dirty = false
    return order
end

function Registry.Count()
    local n = 0
    for _ in pairs(elements) do n = n + 1 end
    return n
end

--- Iterate in order: fn(key, cfg)
function Registry.ForEach(fn)
    local keys = Registry.Order()
    for i = 1, #keys do
        local k = keys[i]
        fn(k, elements[k])
    end
end

--- MSUF_EM2_State.lua

--- MSUF_EM2_State.lua
--- State machine for Edit Mode 2.
--- Manages: enter/exit lifecycle, combat lockdown, AnyEditMode listeners,
--- boss preview, Blizzard EM sync, and keeps all legacy globals in sync.
local State = {}
EM2.State = State
local ENTER_DEFER_DELAY = 0.03

--- Internal state
local active      = false
local unitKey     = nil
local combatFrame = nil
local combatEventsRegistered = false
local pendingCombatExitApply = false
local enterGeneration = 0

local IsConfigCombatLocked = Util.IsConfigCombatLocked
local ShowConfigCombatLockMessage = Util.ShowConfigCombatLockMessage

--- Legacy global sync (contract with 30+ external files)
local function SyncLegacy()
    PublishCompat("MSUF_UnitEditModeActive", active)
    PublishCompat("MSUF_CurrentEditUnitKey", unitKey)
    local st = _G.MSUF_EditState
    if st then
        st.active  = active
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
    if lastNotified == active then return end
    lastNotified = active
    local t = _G.MSUF_AnyEditModeListeners
    if not t then return end
    for i = 1, #t do
        local fn = t[i]
        if type(fn) == "function" then
            fn(active)
        end
    end
end

--- DB access (always live, never cached)
local function DB()
    return _G.MSUF_DB
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

--- Global snapshot for Cancel All (restore pre-edit-mode state)
local SNAPSHOT_KEYS = {
    "player", "target", "focus", "focustarget", "targettarget", "pet", "boss",
    "general", "auras3", "gf_party", "gf_raid", "gf_mythicraid",
}
local _snapshot = nil

local function GetDeepCopy()
    return _G.MSUF_DeepCopy
end

local function SnapshotDB()
    local dc = GetDeepCopy()
    local db = _G.MSUF_DB; if not db or not dc then _snapshot = nil; return end
    _snapshot = {}
    for _, k in ipairs(SNAPSHOT_KEYS) do
        if db[k] ~= nil then _snapshot[k] = dc(db[k]) end
    end
end

local function InvalidateAllFrameCaches()
    local uf = _G.MSUF_UnitFrames
    if not uf then return end
    for _, f in pairs(uf) do
        if f.cachedConfig then f.cachedConfig = nil end
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
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(false)
    end
    if _G.MSUF_UpdateBossCastbarPreview then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshAll) == "function" then
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
    local dc = GetDeepCopy()
    if not _snapshot or not dc then return false end
    local db = _G.MSUF_DB; if not db then return false end
    for _, k in ipairs(SNAPSHOT_KEYS) do
        if _snapshot[k] ~= nil then db[k] = dc(_snapshot[k]) end
    end
    _snapshot = nil
    return true
end

--- ENTER Edit Mode
function State.Enter(key)
    if IsConfigCombatLocked() then
        ShowConfigCombatLockMessage()
        return false
    end

    if active then
        --- Already active: just switch unit
        if key then
            unitKey = key
            SyncLegacy()
            EM2.OnUnitChanged(key)
        end
        return
    end
    if not EnsureDB() then return end

    active  = true
    unitKey = key or "player"
    enterGeneration = enterGeneration + 1
    local enterToken = enterGeneration
    SyncLegacy()
    PlayLogoIntro()
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end

    --- Arrow key nudge
    if _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(true)
    end

    --- Preview must be active before the apply pipeline queues its boss sync.
    PublishCompat("MSUF_UnitPreviewActive", true)

    --- Start ticker (zero overhead when stopped)
    if EM2.Ticker and EM2.Ticker.Start then EM2.Ticker.Start() end

    --- Show grid + HUD + focus synchronously for instant visual feedback.
    if EM2.Grid   and EM2.Grid.Show   then EM2.Grid.Show()   end
    if EM2.HUD    and EM2.HUD.Show    then EM2.HUD.Show()    end
    if EM2.Focus  and EM2.Focus.Show   then EM2.Focus.Show(unitKey) end

    --- Let the logo and shell paint before the heavier preview/listener work.
    C_Timer.After(ENTER_DEFER_DELAY, function()
        if enterGeneration ~= enterToken or not (EM2.State and EM2.State.IsActive()) then return end
        if IsConfigCombatLocked() then return end

        SnapshotDB()

        --- Clear undo history for new session
        if _G.MSUF_EM_UndoClear then
            _G.MSUF_EM_UndoClear()
        end

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
            if enterGeneration ~= enterToken or not (EM2.State and EM2.State.IsActive()) then return end
            if _G.MSUF_SyncAllUnitPreviewsAsync then
                _G.MSUF_SyncAllUnitPreviewsAsync()
            elseif _G.MSUF_SyncAllUnitPreviews then
                _G.MSUF_SyncAllUnitPreviews()
            end
        end

        local function ReforceUnitPreviewsAfterEnter()
            if enterGeneration ~= enterToken or not (EM2.State and EM2.State.IsActive()) then return end
            if _G.MSUF_EM2_ReforcePreviewFrames then
                _G.MSUF_EM2_ReforcePreviewFrames()
            elseif _G.MSUF_SyncAllUnitPreviews then
                _G.MSUF_SyncAllUnitPreviews()
            end
            Util.SyncMovers()
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

        --- Undo transaction
        if type(MSUF_BeginEditModeTransaction) == "function" then
            MSUF_BeginEditModeTransaction()
        end

        --- Notify listeners (Auras3 previews etc.)
        NotifyListeners()

        --- Movers can create a frame per registered element on first entry; defer
        --- that to the next frame so it doesn't pile onto the entry spike. Guard
        --- against an immediate exit before the timer fires.
        C_Timer.After(0, function()
            if enterGeneration ~= enterToken or not (EM2.State and EM2.State.IsActive()) then return end
            if EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
        end)
    end)
end

--- EXIT Edit Mode
function State.Exit(source)
    if not active then return end
    enterGeneration = enterGeneration + 1
    local exitToken = enterGeneration
    local combatLocked = (InCombatLockdown and InCombatLockdown()) and true or false

    --- Stop ticker FIRST (zero overhead from this point)
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

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
    PublishCompat("MSUF_BossTestMode", false)
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
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
end

--- CANCEL ALL - restore DB to pre-edit-mode state, then exit
function State.CancelAll()
    if not active then return end
    enterGeneration = enterGeneration + 1

    --- Stop ticker FIRST so no OnUpdate can write offsets after restore.
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

    --- Kill any pending async commits - they would re-apply dragged offsets
    --- after we restore the snapshot, overwriting our restore.
    FlushPendingCommits()

    --- Restore DB to pre-edit-mode snapshot.
    local restored = RestoreDB()

    --- Teardown UI
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end
    if EM2.Focus  and EM2.Focus.Hide   then EM2.Focus.Hide()  end
    if EM2.Popups and EM2.Popups.CloseAll then EM2.Popups.CloseAll() end

    active  = false
    unitKey = nil
    PublishCompat("MSUF_BossTestMode", false)
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
    else
        --- Snapshot was unavailable - best-effort exit.
        ApplyAllSettingsSafe()
    end

    HardHideEditModePreviews()
    RestoreRuntimeAfterEditModeExit()

    NotifyListeners()
    if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
end

--- Combat guard: auto-exit on PLAYER_REGEN_DISABLED.
--- Events are registered only while Edit Mode is active or while a combat-exit
--- restore is pending, so normal combat has no Edit Mode shell event overhead.
function State.EnsureCombatListener()
    if combatFrame then return end
    combatFrame = CreateFrame("Frame")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and active then
            State.Exit("combat")
            ShowConfigCombatLockMessage()
        elseif event == "PLAYER_REGEN_ENABLED" and pendingCombatExitApply then
            RestoreAfterCombatExit()
        end
        if State.UpdateCombatListenerRegistration then State.UpdateCombatListenerRegistration() end
    end)
end

function State.UpdateCombatListenerRegistration()
    if active or pendingCombatExitApply then
        State.EnsureCombatListener()
        if combatFrame and not combatEventsRegistered then
            combatEventsRegistered = true
            combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif combatFrame and combatEventsRegistered then
        combatEventsRegistered = false
        combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

--- Stub: called when unit selection changes while already active
function EM2.OnUnitChanged(key)
    if EM2.HUD    and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
    if EM2.Movers and EM2.Movers.RefreshSelection then EM2.Movers.RefreshSelection(key) end
    if EM2.Focus  and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "state", syncState = false }) end
end

--- MSUF_EM2_Undo.lua

--- MSUF_EM2_Undo.lua
--- Undo/redo for Edit Mode 2.
--- Captures DB snapshots before changes, restores on undo.
local Undo = {}
EM2.Undo = Undo

local undoStack = {}
local redoStack = {}
local MAX_UNDO = 30
local debounceKey = nil
local debounceTime = 0
local DEBOUNCE_SEC = 0.5

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

local function DeepRestore(dst, src)
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepRestore(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function ResolveGFDBKey(key)
    if key == "party" then return "gf_party" end
    if key == "raid" then return "gf_raid" end
    if key == "mythicraid" then return "gf_mythicraid" end
    if key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" then return key end
    return nil
end

local function CaptureState(category, key)
    local db = _G.MSUF_DB
    if not db then return nil end
    local snap = { category = category, key = key }
    if category == "unit" then
        snap.data = DeepCopy(db[key] or {})
    elseif category == "castbar" then
        snap.data = DeepCopy(db.general or {})
    elseif category == "aura" then
        snap.data = DeepCopy(db.auras3 or {})
    elseif category == "gf" then
        local dbKey = ResolveGFDBKey(key)
        if not dbKey then return nil end
        snap.dbKey = dbKey
        snap.data = DeepCopy(db[dbKey] or {})
    end
    return snap
end

local function RestoreState(snap)
    if not snap then return end
    PublishCompat("MSUF__UndoRestoring", true)
    local db = _G.MSUF_DB
    if not db then PublishCompat("MSUF__UndoRestoring", false); return end

    if snap.category == "unit" then
        db[snap.key] = db[snap.key] or {}
        DeepRestore(db[snap.key], snap.data)
        ApplySettingsForKeySafe(snap.key)
    elseif snap.category == "castbar" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
        ApplyAllSettingsSafe()
    elseif snap.category == "aura" then
        db.auras3 = db.auras3 or {}
        DeepRestore(db.auras3, snap.data)
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.RefreshAll) == "function" then a3.RefreshAll() end
    elseif snap.category == "gf" then
        local dbKey = snap.dbKey or ResolveGFDBKey(snap.key)
        if dbKey then
            db[dbKey] = db[dbKey] or {}
            DeepRestore(db[dbKey], snap.data)
            if _G.MSUF_GF_RefreshAll then
                _G.MSUF_GF_RefreshAll()
            elseif _G.MSUF_GF_RebuildAll then
                _G.MSUF_GF_RebuildAll()
            end
            if _G.MSUF_EM2_SyncGFPopups then _G.MSUF_EM2_SyncGFPopups() end
        end
    end

    if _G.MSUF_UpdateAllFonts then _G.MSUF_UpdateAllFonts() end

    --- Sync popups
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    Util.SyncMovers()

    PublishCompat("MSUF__UndoRestoring", false)
end

function Undo.BeforeChange(category, key, debounce)
    if _G.MSUF__UndoRestoring then return end
    if debounce then
        local now = GetTime()
        local dk = (category or "") .. ":" .. (key or "")
        if dk == debounceKey and (now - debounceTime) < DEBOUNCE_SEC then return end
        debounceKey = dk
        debounceTime = now
    end
    local snap = CaptureState(category, key)
    if not snap then return end
    undoStack[#undoStack + 1] = snap
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    --- Clear redo on new action
    for i = 1, #redoStack do redoStack[i] = nil end
end

function Undo.DoUndo()
    if #undoStack == 0 then return end
    local snap = undoStack[#undoStack]
    undoStack[#undoStack] = nil
    local current = CaptureState(snap.category, snap.key)
    if current then redoStack[#redoStack + 1] = current end
    RestoreState(snap)
end

function Undo.DoRedo()
    if #redoStack == 0 then return end
    local snap = redoStack[#redoStack]
    redoStack[#redoStack] = nil
    local current = CaptureState(snap.category, snap.key)
    if current then undoStack[#undoStack + 1] = current end
    RestoreState(snap)
end

function Undo.Clear()
    for i = 1, #undoStack do undoStack[i] = nil end
    for i = 1, #redoStack do redoStack[i] = nil end
    debounceKey = nil
end

function Undo.CanUndo() return #undoStack > 0 end
function Undo.CanRedo() return #redoStack > 0 end

--- Legacy globals
local function MSUF_EM_UndoBeforeChange(category, key, debounce) Undo.BeforeChange(category, key, debounce) end
local function MSUF_EM_UndoClear() Undo.Clear() end
local function MSUF_EM_UndoUndo() Undo.DoUndo() end
local function MSUF_EM_UndoRedo() Undo.DoRedo() end

ExportPublic("MSUF_EM_UndoBeforeChange", MSUF_EM_UndoBeforeChange)
ExportPublic("MSUF_EM_UndoClear", MSUF_EM_UndoClear)
ExportPublic("MSUF_EM_UndoUndo", MSUF_EM_UndoUndo)
ExportPublic("MSUF_EM_UndoRedo", MSUF_EM_UndoRedo)

--- MSUF_EM2_Init.lua

--- MSUF_EM2_Init.lua
--- Loads last. Compat.lua already provides all legacy globals.
--- This file exposes version tag; combat listener is demand-registered by state.

EM2.VERSION = "2.0.0"
