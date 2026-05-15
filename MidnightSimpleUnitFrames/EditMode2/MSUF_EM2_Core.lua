-- MSUF_EM2_Core.lua — Registry + State + Undo + Init (consolidated)

-- MSUF_EM2_Registry.lua

-- MSUF_EM2_Registry.lua
-- Element registration API for Edit Mode 2.
-- Every moveable element (unit frame, castbar, aura group, class power)
-- registers here. EditMode core iterates the registry — never hardcoded lists.
local addonName, ns = ...

_G.MSUF_EM2 = _G.MSUF_EM2 or {}
local EM2 = _G.MSUF_EM2

local Registry = {}
EM2.Registry = Registry

local elements = {}
local order    = {}
local dirty    = true

-- Register a moveable element.
-- cfg fields:
--   key        (string)   unique identifier ("player", "castbar_player", "aura_target", …)
--   label      (string)   display name for mover overlay
--   order      (number)   sort priority (lower = earlier)
--   getFrame   (function) → frame   returns the live frame reference
--   getConf    (function) → table   returns the DB config table for this element
--   popupType  (string)   "unit" | "castbar" | "aura" | "classpower" | "custom" | nil
--   isEnabled  (function) → bool    whether element exists and should show a mover
--   canResize  (bool)     whether mover allows resize handles
--   canNudge   (bool)     whether arrow keys can move this element (default true)
--   onEnter    (function) optional callback when edit mode enters
--   onExit     (function) optional callback when edit mode exits
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

-- Sorted key list. Rebuilt lazily when dirty.
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

-- Iterate in order: fn(key, cfg)
function Registry.ForEach(fn)
    local keys = Registry.Order()
    for i = 1, #keys do
        local k = keys[i]
        fn(k, elements[k])
    end
end

-- MSUF_EM2_State.lua

-- MSUF_EM2_State.lua
-- State machine for Edit Mode 2.
-- Manages: enter/exit lifecycle, combat lockdown, AnyEditMode listeners,
-- boss preview, Blizzard EM sync, and keeps all legacy globals in sync.
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local State = {}
EM2.State = State

-- Internal state
local active      = false
local unitKey     = nil
local combatFrame = nil

local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then return true end
    return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

local function ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    elseif print then
        print("|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end

-- Legacy global sync (contract with 30+ external files)
local function SyncLegacy()
    _G.MSUF_UnitEditModeActive = active
    _G.MSUF_CurrentEditUnitKey = unitKey
    local st = _G.MSUF_EditState
    if st then
        st.active  = active
        st.unitKey = unitKey
    end
end

-- Ensure MSUF_EditState table exists (other files rawget it)
if not _G.MSUF_EditState then
    _G.MSUF_EditState = {
        active              = false,
        unitKey             = nil,
        popupOpen           = false,
        arrowBindingsActive = false,
        fatalDisabled       = false,
    }
end

-- AnyEditMode listener notifications
if not _G.MSUF_AnyEditModeListeners then
    _G.MSUF_AnyEditModeListeners = {}
end

if not _G.MSUF_RegisterAnyEditModeListener then
    function _G.MSUF_RegisterAnyEditModeListener(fn)
        if type(fn) ~= "function" then return end
        local t = _G.MSUF_AnyEditModeListeners
        t[#t + 1] = fn
    end
end

local lastNotified = nil
local function NotifyListeners()
    if lastNotified == active then return end
    lastNotified = active
    local t = _G.MSUF_AnyEditModeListeners
    if not t then return end
    for i = 1, #t do
        local fn = t[i]
        if type(fn) == "function" then
            local ok, err = pcall(fn, active)
            if not ok and type(err) == "string" then
                -- one bad listener must not break the rest
            end
        end
    end
end

-- DB access (always live, never cached)
local function DB()
    return _G.MSUF_DB
end

local function EnsureDB()
    if _G.MSUF_DB then return true end
    local fn = _G.EnsureDB
    if type(fn) == "function" then fn(); return _G.MSUF_DB ~= nil end
    if ns and type(ns.EnsureDB) == "function" then ns.EnsureDB(); return _G.MSUF_DB ~= nil end
    return false
end
-- Public read-only accessors
function State.IsActive()      return active end
function State.GetUnitKey()    return unitKey end

function State.SetUnitKey(key)
    unitKey = key
    SyncLegacy()
end

function State.SetPopupOpen(open)
    local st = _G.MSUF_EditState
    if st then st.popupOpen = open and true or false end
end

-- Global snapshot for Cancel All (restore pre-edit-mode state)
local SNAPSHOT_KEYS = {"player","target","focus","targettarget","pet","boss","general","auras2"}
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

-- ENTER Edit Mode
function State.Enter(key)
    if IsConfigCombatLocked() then
        ShowConfigCombatLockMessage()
        return false
    end

    if active then
        -- Already active: just switch unit
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
    SyncLegacy()

    SnapshotDB()

    -- Clear undo history for new session
    if _G.MSUF_EM_UndoClear then
        _G.MSUF_EM_UndoClear()
    end

    -- Refresh Auras2
    if _G.MSUF_Auras2_RefreshAll then
        _G.MSUF_Auras2_RefreshAll()
    end

    -- Arrow key nudge
    if _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(true)
    end

    -- Visibility drivers: ApplyAllSettings checks MSUF_UnitEditModeActive internally
    if type(ApplyAllSettings) == "function" then
        ApplyAllSettings()
    end

    -- Preview: auto-enable all frames AFTER pipeline settles (async commit)
    _G.MSUF_UnitPreviewActive = true
    C_Timer.After(0.1, function()
        if not (EM2.State and EM2.State.IsActive()) then return end
        if _G.MSUF_SyncAllUnitPreviews then
            _G.MSUF_SyncAllUnitPreviews()
        end
    end)

    -- Undo transaction
    if type(MSUF_BeginEditModeTransaction) == "function" then
        MSUF_BeginEditModeTransaction()
    end

    -- Notify listeners (Auras2 previews etc.)
    NotifyListeners()

    -- Start ticker (zero overhead when stopped)
    if EM2.Ticker and EM2.Ticker.Start then EM2.Ticker.Start() end

    -- Show grid + HUD + movers (EM2 modules)
    if EM2.Grid   and EM2.Grid.Show   then EM2.Grid.Show()   end
    if EM2.HUD    and EM2.HUD.Show    then EM2.HUD.Show()    end
    if EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
end

-- EXIT Edit Mode
function State.Exit(source)
    if not active then return end

    -- Stop ticker FIRST (zero overhead from this point)
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

    -- Hide movers + HUD + grid first (visual instant response)
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end

    -- Close all popups
    if EM2.Popups and EM2.Popups.CloseAll then
        EM2.Popups.CloseAll()
    end

    -- Flip state
    active  = false
    unitKey = nil
    _G.MSUF_BossTestMode = false
    _G.MSUF_PreviewTestMode = false
    SyncLegacy()

    -- Arrow keys off
    if _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(false)
    end

    -- Visibility drivers restore
    if type(ApplyAllSettings) == "function" then
        ApplyAllSettings()
    end

    -- Preview: disable all previews, restore visibility
    _G.MSUF_UnitPreviewActive = false
    if _G.MSUF_SyncAllUnitPreviews then
        _G.MSUF_SyncAllUnitPreviews()
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and _G.MSUF_UpdateBossCastbarPreview
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    -- Refresh Auras2
    if _G.MSUF_Auras2_RefreshAll then
        _G.MSUF_Auras2_RefreshAll()
    end

    -- Notify listeners
    NotifyListeners()
end

-- CANCEL ALL — restore DB to pre-edit-mode state, then exit
function State.CancelAll()
    if not active then return end

    -- Stop ticker FIRST so no OnUpdate can write offsets after restore.
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

    -- Kill any pending async commits — they would re-apply dragged offsets
    -- after we restore the snapshot, overwriting our restore.
    FlushPendingCommits()

    -- Restore DB to pre-edit-mode snapshot.
    local restored = RestoreDB()

    -- Teardown UI
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end
    if EM2.Popups and EM2.Popups.CloseAll then EM2.Popups.CloseAll() end

    active  = false
    unitKey = nil
    _G.MSUF_BossTestMode = false
    _G.MSUF_PreviewTestMode = false
    SyncLegacy()

    if _G.MSUF_EnableArrowKeyNudge then _G.MSUF_EnableArrowKeyNudge(false) end

    if restored then
        -- Invalidate all frame config caches so the pipeline reads the
        -- freshly restored DB tables, not stale references to the old
        -- (dragged) config objects.
        InvalidateAllFrameCaches()

        -- Apply synchronously — the async path can silently drop when a
        -- pending commit is already scheduled.
        local applyImm = _G.MSUF_ApplyAllSettings_Immediate
        if type(applyImm) == "function" then
            applyImm()
        elseif type(ApplyAllSettings) == "function" then
            ApplyAllSettings()
        end

        -- Belt-and-suspenders: force SetPoint on every unit frame with
        -- the restored offsetX/Y from the DB.
        if _G.MSUF_ForceReanchorAllUnitFrames_Once then
            _G.MSUF_ForceReanchorAllUnitFrames_Once()
        end
    else
        -- Snapshot was unavailable — best-effort exit.
        if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
    end

    _G.MSUF_UnitPreviewActive = false
    if _G.MSUF_SyncAllUnitPreviews then _G.MSUF_SyncAllUnitPreviews() end
    if _G.MSUF_Auras2_RefreshAll then _G.MSUF_Auras2_RefreshAll() end

    NotifyListeners()
end

-- Combat guard: auto-exit on PLAYER_REGEN_DISABLED
-- Installed at LOAD time (not lazy) so it's always active.
function State.EnsureCombatListener()
    if combatFrame then return end
    combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and active then
            State.Exit("combat")
            ShowConfigCombatLockMessage()
        end
    end)
end
-- Install immediately at file load
State.EnsureCombatListener()

-- Stub: called when unit selection changes while already active
function EM2.OnUnitChanged(key)
    if EM2.HUD    and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
    if EM2.Movers and EM2.Movers.RefreshSelection then EM2.Movers.RefreshSelection(key) end
end

-- MSUF_EM2_Undo.lua

-- MSUF_EM2_Undo.lua
-- Undo/redo for Edit Mode 2.
-- Captures DB snapshots before changes, restores on undo.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

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

local function CaptureState(category, key)
    local db = _G.MSUF_DB
    if not db then return nil end
    local snap = { category = category, key = key }
    if category == "unit" then
        snap.data = DeepCopy(db[key] or {})
    elseif category == "castbar" then
        snap.data = DeepCopy(db.general or {})
    elseif category == "aura" then
        snap.data = DeepCopy(db.auras2 or {})
    end
    return snap
end

local function RestoreState(snap)
    if not snap then return end
    _G.MSUF__UndoRestoring = true
    local db = _G.MSUF_DB
    if not db then _G.MSUF__UndoRestoring = false; return end

    if snap.category == "unit" then
        db[snap.key] = db[snap.key] or {}
        DeepRestore(db[snap.key], snap.data)
        if type(ApplySettingsForKey) == "function" then ApplySettingsForKey(snap.key) end
    elseif snap.category == "castbar" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
        if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
    elseif snap.category == "aura" then
        db.auras2 = db.auras2 or {}
        DeepRestore(db.auras2, snap.data)
        if _G.MSUF_Auras2_RefreshAll then _G.MSUF_Auras2_RefreshAll() end
    end

    if _G.MSUF_UpdateAllFonts then _G.MSUF_UpdateAllFonts() end

    -- Sync popups
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end

    _G.MSUF__UndoRestoring = false
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
    -- Clear redo on new action
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

-- Legacy globals
_G.MSUF_EM_UndoBeforeChange = function(category, key, debounce) Undo.BeforeChange(category, key, debounce) end
_G.MSUF_EM_UndoClear = function() Undo.Clear() end
_G.MSUF_EM_UndoUndo = function() Undo.DoUndo() end
_G.MSUF_EM_UndoRedo = function() Undo.DoRedo() end

-- MSUF_EM2_Init.lua

-- MSUF_EM2_Init.lua
-- Loads last. Compat.lua already provides all legacy globals.
-- This file ensures combat listener and exposes version tag.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

if EM2.State and EM2.State.EnsureCombatListener then
    EM2.State.EnsureCombatListener()
end

EM2.VERSION = "2.0.0"
