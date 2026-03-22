-- ============================================================================
-- MSUF_EM2_State.lua
-- State machine for Edit Mode 2.
-- Manages: enter/exit lifecycle, combat lockdown, AnyEditMode listeners,
-- boss preview, Blizzard EM sync, and keeps all legacy globals in sync.
-- ============================================================================
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local State = {}
EM2.State = State

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local active      = false
local unitKey     = nil
local combatFrame = nil

-- ---------------------------------------------------------------------------
-- Legacy global sync (contract with 30+ external files)
-- ---------------------------------------------------------------------------
local function SyncLegacy()
    _G.MSUF_UnitEditModeActive = active
    _G.MSUF_CurrentEditUnitKey = unitKey
    local st = _G.MSUF_EditState
    if st then
        st.active  = active
        st.unitKey = unitKey
    end
end

-- ---------------------------------------------------------------------------
-- Ensure MSUF_EditState table exists (other files rawget it)
-- ---------------------------------------------------------------------------
if not _G.MSUF_EditState then
    _G.MSUF_EditState = {
        active              = false,
        unitKey             = nil,
        popupOpen           = false,
        arrowBindingsActive = false,
        fatalDisabled       = false,
    }
end

-- ---------------------------------------------------------------------------
-- AnyEditMode listener notifications
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- DB access (always live, never cached)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Public read-only accessors
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Global snapshot for Cancel All (restore pre-edit-mode state)
-- ---------------------------------------------------------------------------
local SNAPSHOT_KEYS = {"player","target","focus","targettarget","pet","boss","general","auras2"}
local _snapshot = nil
local DeepCopy = _G.MSUF_DeepCopy

local function SnapshotDB()
    local db = _G.MSUF_DB; if not db or not DeepCopy then _snapshot = nil; return end
    _snapshot = {}
    for _, k in ipairs(SNAPSHOT_KEYS) do
        if db[k] ~= nil then _snapshot[k] = DeepCopy(db[k]) end
    end
end

local function RestoreDB()
    if not _snapshot or not DeepCopy then return end
    local db = _G.MSUF_DB; if not db then return end
    for _, k in ipairs(SNAPSHOT_KEYS) do
        if _snapshot[k] ~= nil then db[k] = DeepCopy(_snapshot[k]) end
    end
    _snapshot = nil
end

-- ---------------------------------------------------------------------------
-- ENTER Edit Mode
-- ---------------------------------------------------------------------------
function State.Enter(key)
    if active then
        -- Already active: just switch unit
        if key then
            unitKey = key
            SyncLegacy()
            EM2.OnUnitChanged(key)
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end
    if not EnsureDB() then return end

    active  = true
    unitKey = key or "player"
    SyncLegacy()

    SnapshotDB()

    -- Clear undo history for new session
    if type(_G.MSUF_EM_UndoClear) == "function" then
        _G.MSUF_EM_UndoClear()
    end

    -- Refresh Auras2
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end

    -- Arrow key nudge
    if type(_G.MSUF_EnableArrowKeyNudge) == "function" then
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
        if type(_G.MSUF_SyncAllUnitPreviews) == "function" then
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

-- ---------------------------------------------------------------------------
-- EXIT Edit Mode
-- ---------------------------------------------------------------------------
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
    if type(_G.MSUF_EnableArrowKeyNudge) == "function" then
        _G.MSUF_EnableArrowKeyNudge(false)
    end

    -- Visibility drivers restore
    if type(ApplyAllSettings) == "function" then
        ApplyAllSettings()
    end

    -- Preview: disable all previews, restore visibility
    _G.MSUF_UnitPreviewActive = false
    if type(_G.MSUF_SyncAllUnitPreviews) == "function" then
        _G.MSUF_SyncAllUnitPreviews()
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    -- Refresh Auras2
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end

    -- Notify listeners
    NotifyListeners()
end

-- ---------------------------------------------------------------------------
-- CANCEL ALL — restore DB to pre-edit-mode state, then exit
-- ---------------------------------------------------------------------------
function State.CancelAll()
    if not active then return end

    RestoreDB()

    -- Full teardown identical to Exit
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end
    if EM2.Movers and EM2.Movers.Hide then EM2.Movers.Hide() end
    if EM2.HUD    and EM2.HUD.Hide    then EM2.HUD.Hide()    end
    if EM2.Grid   and EM2.Grid.Hide   then EM2.Grid.Hide()   end
    if EM2.Popups and EM2.Popups.CloseAll then EM2.Popups.CloseAll() end

    active  = false
    unitKey = nil
    _G.MSUF_BossTestMode = false
    _G.MSUF_PreviewTestMode = false
    SyncLegacy()

    if type(_G.MSUF_EnableArrowKeyNudge) == "function" then _G.MSUF_EnableArrowKeyNudge(false) end
    if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
    _G.MSUF_UnitPreviewActive = false
    if type(_G.MSUF_SyncAllUnitPreviews) == "function" then _G.MSUF_SyncAllUnitPreviews() end
    if type(_G.MSUF_UpdateAllFonts) == "function" then _G.MSUF_UpdateAllFonts() end
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end

    NotifyListeners()
end

-- ---------------------------------------------------------------------------
-- Combat guard: auto-exit on PLAYER_REGEN_DISABLED
-- Installed at LOAD time (not lazy) so it's always active.
-- ---------------------------------------------------------------------------
function State.EnsureCombatListener()
    if combatFrame then return end
    combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and active then
            State.Exit("combat")
        end
    end)
end
-- Install immediately at file load
State.EnsureCombatListener()

-- ---------------------------------------------------------------------------
-- Stub: called when unit selection changes while already active
-- ---------------------------------------------------------------------------
function EM2.OnUnitChanged(key)
    if EM2.HUD    and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
    if EM2.Movers and EM2.Movers.RefreshSelection then EM2.Movers.RefreshSelection(key) end
end
