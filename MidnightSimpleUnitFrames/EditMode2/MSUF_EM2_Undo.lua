-- ============================================================================
-- MSUF_EM2_Undo.lua
-- Undo/redo for Edit Mode 2.
-- Captures DB snapshots before changes, restores on undo.
-- ============================================================================
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
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
        if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
    elseif snap.category == "aura" then
        db.auras2 = db.auras2 or {}
        DeepRestore(db.auras2, snap.data)
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
    end

    if type(_G.MSUF_UpdateAllFonts) == "function" then _G.MSUF_UpdateAllFonts() end

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
