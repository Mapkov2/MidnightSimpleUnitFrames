-- MSUF_EM_UndoRedo.lua
-- Undo / Redo system for MSUF Edit Mode (unlimited steps per session).
-- Scopes: "unit" (MSUF_DB[key]), "castbar" (MSUF_DB.general), "aura" (MSUF_DB.auras2.perUnit[key].layout)
-- Secret-safe: no comparisons on protected values; operates only on plain DB fields.

local addonName, ns = ...
ns = ns or {}
_G.MSUF_NS = _G.MSUF_NS or ns

local Edit = _G.MSUF_Edit
if not Edit then return end

Edit.Undo = Edit.Undo or {}
local U = Edit.Undo

---------------------------------------------------------------------------
-- Stacks (integer-indexed, newest at [#t], unlimited depth)
---------------------------------------------------------------------------
local undoStack = {}
local redoStack = {}

---------------------------------------------------------------------------
-- Nudge debounce
---------------------------------------------------------------------------
local nudgeGroupOpen   = false
local nudgeTimerHandle = nil
local NUDGE_DEBOUNCE   = 0.45

---------------------------------------------------------------------------
-- Tracked UNIT fields (MSUF_DB[key])
---------------------------------------------------------------------------
local UNIT_FIELDS = {
    "offsetX", "offsetY", "width", "height",
    "nameOffsetX", "nameOffsetY",
    "hpOffsetX", "hpOffsetY",
    "powerOffsetX", "powerOffsetY",
    "showName", "showHP", "showPower",
    "nameTextAnchor", "hpTextAnchor", "powerTextAnchor",
    "nameFontSize", "hpFontSize", "powerFontSize",
    "powerBarDetached",
    "detachedPowerBarWidth", "detachedPowerBarHeight",
    "detachedPowerBarOffsetX", "detachedPowerBarOffsetY",
}
local UNIT_FIELDS_N = #UNIT_FIELDS

---------------------------------------------------------------------------
-- Build castbar field list dynamically from MSUF_DB.general
---------------------------------------------------------------------------
local function BuildCastbarFields(unit)
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if not g then return nil end
    local fields, n = {}, 0

    if unit == "boss" then
        for k in pairs(g) do
            if type(k) == "string" and k:sub(1, 8) == "bossCast" then
                n = n + 1; fields[n] = k
            end
        end
        -- show keys use different prefix: showBossCastName/Icon/Time
        for _, sk in ipairs({
            "showBossCastName", "showBossCastIcon", "showBossCastTime",
        }) do
            if g[sk] ~= nil then n = n + 1; fields[n] = sk end
        end
        return (n > 0) and fields or nil
    end

    local getPrefix = _G.MSUF_GetCastbarPrefix
    if type(getPrefix) ~= "function" then return nil end
    local prefix = getPrefix(unit)
    if not prefix or prefix == "" then return nil end
    local pLen = #prefix
    for k in pairs(g) do
        if type(k) == "string" and k:sub(1, pLen) == prefix then
            n = n + 1; fields[n] = k
        end
    end
    local cap = unit:sub(1, 1):upper() .. unit:sub(2)
    for _, sk in ipairs({
        "show" .. cap .. "CastName",
        "show" .. cap .. "CastIcon",
        "show" .. cap .. "CastTime",
    }) do
        if g[sk] ~= nil then n = n + 1; fields[n] = sk end
    end
    return (n > 0) and fields or nil
end

---------------------------------------------------------------------------
-- UNIT snapshot
---------------------------------------------------------------------------
local function TakeUnitSnapshot(key)
    local db = _G.MSUF_DB
    if not db then return nil end
    local conf = db[key]
    if type(conf) ~= "table" then return nil end
    local data = {}
    for i = 1, UNIT_FIELDS_N do data[UNIT_FIELDS[i]] = conf[UNIT_FIELDS[i]] end
    return { scope = "unit", key = key, fields = UNIT_FIELDS, nf = UNIT_FIELDS_N, data = data }
end

---------------------------------------------------------------------------
-- CASTBAR snapshot
---------------------------------------------------------------------------
local function TakeCastbarSnapshot(unit)
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if type(g) ~= "table" then return nil end
    local fields = BuildCastbarFields(unit)
    if not fields then return nil end
    local nf = #fields
    local data = {}
    for i = 1, nf do data[fields[i]] = g[fields[i]] end
    return { scope = "castbar", key = unit, fields = fields, nf = nf, data = data }
end

---------------------------------------------------------------------------
-- AURA snapshot  (MSUF_DB.auras2.perUnit[key].layout — full shallow copy)
---------------------------------------------------------------------------
local function TakeAuraSnapshot(unitKey)
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    if type(a2) ~= "table" then return nil end
    local pu = a2.perUnit and a2.perUnit[unitKey]
    local layout = pu and pu.layout
    -- Even if layout doesn't exist yet, capture nil state (so undo can restore "no overrides")

    local fields, data, n = {}, {}, 0
    if type(layout) == "table" then
        for k, v in pairs(layout) do
            n = n + 1
            fields[n] = k
            data[k] = v
        end
    end
    -- Always include core offset keys even if they're nil (so restore clears them)
    local coreKeys = {
        "buffGroupOffsetX", "buffGroupOffsetY",
        "debuffGroupOffsetX", "debuffGroupOffsetY",
        "privateOffsetX", "privateOffsetY",
        "iconSize", "spacing",
        "buffGroupIconSize", "debuffGroupIconSize", "privateSize",
        "stackTextSize", "cooldownTextSize",
        "stackTextOffsetX", "stackTextOffsetY",
        "cooldownTextOffsetX", "cooldownTextOffsetY",
        "offsetX", "offsetY",
        "width", "height",
    }
    local have = {}
    for i = 1, n do have[fields[i]] = true end
    for _, ck in ipairs(coreKeys) do
        if not have[ck] then
            n = n + 1
            fields[n] = ck
            -- data[ck] stays nil → restoring nil means "remove override"
        end
    end

    return { scope = "aura", key = unitKey, fields = fields, nf = n, data = data }
end

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------
local function TakeSnapshot(scope, key)
    if scope == "castbar" then return TakeCastbarSnapshot(key) end
    if scope == "aura"    then return TakeAuraSnapshot(key)    end
    return TakeUnitSnapshot(key)
end

---------------------------------------------------------------------------
-- Restore snapshot into MSUF_DB
---------------------------------------------------------------------------
local function RestoreSnapshot(snap)
    if not snap then return end
    local db = _G.MSUF_DB
    if not db then return end

    if snap.scope == "unit" then
        local target = db[snap.key]
        if type(target) ~= "table" then return end
        for i = 1, snap.nf do target[snap.fields[i]] = snap.data[snap.fields[i]] end

    elseif snap.scope == "castbar" then
        local target = db.general
        if type(target) ~= "table" then return end
        for i = 1, snap.nf do target[snap.fields[i]] = snap.data[snap.fields[i]] end

    elseif snap.scope == "aura" then
        local a2 = db.auras2
        if type(a2) ~= "table" then return end
        a2.perUnit = a2.perUnit or {}
        a2.perUnit[snap.key] = a2.perUnit[snap.key] or {}
        local pu = a2.perUnit[snap.key]
        pu.layout = pu.layout or {}
        local layout = pu.layout
        for i = 1, snap.nf do
            layout[snap.fields[i]] = snap.data[snap.fields[i]]
        end
    end
end

---------------------------------------------------------------------------
-- Apply after restore — SYNCHRONOUS paths
---------------------------------------------------------------------------
local function ApplyAfterRestore(snap)
    if not snap then return end

    if snap.scope == "unit" then
        local key = snap.key
        _G.MSUF__UndoRestoring = true
        local imm = _G.MSUF_ApplySettingsForKey_Immediate
        if type(imm) == "function" then
            imm(key)
        else
            local fn = _G.ApplySettingsForKey
            if type(fn) == "function" then fn(key)
            elseif type(_G.ApplyAllSettings) == "function" then _G.ApplyAllSettings() end
        end
        if type(_G.MSUF_UpdateAllFonts) == "function" then _G.MSUF_UpdateAllFonts() end
        if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
        if (key == "target" or key == "targettarget") and ns and ns.MSUF_ToTInline_RequestRefresh then
            ns.MSUF_ToTInline_RequestRefresh("Undo")
        end
        if type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" then
            local UF = _G.MSUF_UnitFrames or _G.UnitFrames
            local f = UF and UF[key]
            if f then pcall(_G.MSUF_ApplyPowerBarEmbedLayout, f) end
        end
        if type(_G.MSUF_SyncUnitPositionPopup) == "function" then _G.MSUF_SyncUnitPositionPopup(key) end
        if type(_G.MSUF_UpdateEditModeInfo) == "function" then _G.MSUF_UpdateEditModeInfo() end
        _G.MSUF__UndoRestoring = false

    elseif snap.scope == "castbar" then
        local unit = snap.key
        -- Global flag: tells popup Apply() in EditMode.lua to not re-fire
        _G.MSUF__UndoRestoring = true
        -- Nuclear but reliable: ApplyAllSettings_Immediate handles real castbar
        -- frames, preview frames, visuals, textures — everything synchronously.
        local applyImm = _G.MSUF_ApplyAllSettings_Immediate
        if type(applyImm) == "function" then
            applyImm()
        else
            local fn = _G.MSUF_ApplyCastbarUnitAndSync
            if type(fn) == "function" then fn(unit)
            elseif type(_G.ApplyAllSettings) == "function" then _G.ApplyAllSettings() end
        end
        if unit == "boss" then
            -- Boss castbar needs explicit position + time apply;
            -- MSUF_ApplyAllSettings_Immediate does NOT call these.
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                pcall(_G.MSUF_ApplyBossCastbarPositionSetting)
            end
            if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then
                pcall(_G.MSUF_ApplyBossCastbarTimeSetting)
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                pcall(_G.MSUF_UpdateBossCastbarPreview)
            end
        end
        -- Explicit reanchor for position changes (belt-and-suspenders)
        local REANCHOR = {
            player = "MSUF_ReanchorPlayerCastBar",
            target = "MSUF_ReanchorTargetCastBar",
            focus  = "MSUF_ReanchorFocusCastBar",
        }
        local rn = REANCHOR[unit]
        if rn and type(_G[rn]) == "function" then pcall(_G[rn]) end
        -- Force visuals refresh (text show/hide, icon, fonts)
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            pcall(_G.MSUF_UpdateCastbarVisuals)
        end
        -- Preview sync: reposition + resize preview to match real castbar
        local PREVIEW_UPDATE = {
            player = "MSUF_UpdatePlayerCastbarPreview",
            target = "MSUF_UpdateTargetCastbarPreview",
            focus  = "MSUF_UpdateFocusCastbarPreview",
        }
        local PREVIEW_POS = {
            player = "MSUF_PositionPlayerCastbarPreview",
            target = "MSUF_PositionTargetCastbarPreview",
            focus  = "MSUF_PositionFocusCastbarPreview",
        }
        local pu = PREVIEW_UPDATE[unit]
        if pu and type(_G[pu]) == "function" then pcall(_G[pu]) end
        local pp = PREVIEW_POS[unit]
        if pp and type(_G[pp]) == "function" then pcall(_G[pp]) end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
            _G.MSUF_SyncCastbarPositionPopup(unit)
        end
        if type(_G.MSUF_UpdateCastbarEditInfo) == "function" then
            _G.MSUF_UpdateCastbarEditInfo(unit)
        end
        _G.MSUF__UndoRestoring = false

    elseif snap.scope == "aura" then
        local unitKey = snap.key
        _G.MSUF__UndoRestoring = true
        -- Invalidate cached config so Auras2 picks up new values
        local API = ns.MSUF_Auras2
        if API and API.InvalidateDB then API.InvalidateDB() end
        -- Refresh anchor position for this unit
        if API and API.UpdateUnitAnchor then API.UpdateUnitAnchor(unitKey) end
        -- Full refresh to re-render icons with new layout
        if type(_G.MSUF_Auras2_RefreshUnit) == "function" then
            _G.MSUF_Auras2_RefreshUnit(unitKey)
        elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
        -- Re-position movers if visible
        if API and API.EditMode and API.EditMode.PositionMovers then
            local aby = API.state and API.state.aurasByUnit
            local entry = aby and aby[unitKey]
            if entry then
                local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
                local shared = a2 and a2.shared
                pcall(API.EditMode.PositionMovers, entry, shared)
            end
        end
        -- Sync aura position popup if open
        if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
            _G.MSUF_SyncAuras2PositionPopup(unitKey)
        end
        _G.MSUF__UndoRestoring = false
    end
end

---------------------------------------------------------------------------
-- Stack operations (with dedup)
---------------------------------------------------------------------------
local function EqualsTop(stack, snap)
    local n = #stack
    if n < 1 then return false end
    local top = stack[n]
    if top.scope ~= snap.scope or top.key ~= snap.key or top.nf ~= snap.nf then
        return false
    end
    local tData, sData, fields = top.data, snap.data, snap.fields
    for i = 1, snap.nf do
        local f = fields[i]
        if tData[f] ~= sData[f] then return false end
    end
    return true
end

local function PushStack(stack, snap)
    if not snap then return end
    if EqualsTop(stack, snap) then return end
    stack[#stack + 1] = snap
end

local function PopStack(stack)
    local n = #stack
    if n < 1 then return nil end
    local snap = stack[n]; stack[n] = nil
    return snap
end

local function WipeStack(stack)
    for i = #stack, 1, -1 do stack[i] = nil end
end

---------------------------------------------------------------------------
-- Button references
---------------------------------------------------------------------------
local undoBtnRef, redoBtnRef

function U.SetButtons(undo, redo)
    undoBtnRef = undo; redoBtnRef = redo
    U.UpdateButtons()
end

function U.UpdateButtons()
    if undoBtnRef then
        local can = #undoStack > 0
        if undoBtnRef.SetEnabled then undoBtnRef:SetEnabled(can) end
        if undoBtnRef.SetAlpha then undoBtnRef:SetAlpha(can and 1.0 or 0.4) end
    end
    if redoBtnRef then
        local can = #redoStack > 0
        if redoBtnRef.SetEnabled then redoBtnRef:SetEnabled(can) end
        if redoBtnRef.SetAlpha then redoBtnRef:SetAlpha(can and 1.0 or 0.4) end
    end
end

---------------------------------------------------------------------------
-- Suppress flag: prevents hooks from firing during undo/redo apply
-- (Sync calls update popup fields → triggers Apply → would overwrite restore)
---------------------------------------------------------------------------
local suppressHooks = false

---------------------------------------------------------------------------
-- BeforeChange — main entry point
---------------------------------------------------------------------------
function U.BeforeChange(scope, key, isNudge)
    if suppressHooks then return end
    if not _G.MSUF_DB or not key then return end

    if isNudge then
        if nudgeTimerHandle then nudgeTimerHandle:Cancel(); nudgeTimerHandle = nil end
        if C_Timer and C_Timer.NewTimer then
            nudgeTimerHandle = C_Timer.NewTimer(NUDGE_DEBOUNCE, function()
                nudgeGroupOpen = false; nudgeTimerHandle = nil
            end)
        end
        if nudgeGroupOpen then return end
        nudgeGroupOpen = true
    else
        nudgeGroupOpen = false
        if nudgeTimerHandle then nudgeTimerHandle:Cancel(); nudgeTimerHandle = nil end
    end

    local snap = TakeSnapshot(scope, key)
    if not snap then return end

    PushStack(undoStack, snap)
    WipeStack(redoStack)
    U.UpdateButtons()
end

---------------------------------------------------------------------------
-- DoUndo / DoRedo
---------------------------------------------------------------------------
function U.DoUndo()
    local prev = PopStack(undoStack)
    if not prev then return end
    local current = TakeSnapshot(prev.scope, prev.key)
    if current then PushStack(redoStack, current) end
    RestoreSnapshot(prev)
    suppressHooks = true
    local ok, err = pcall(ApplyAfterRestore, prev)
    suppressHooks = false
    _G.MSUF__UndoRestoring = false
    if not ok then -- fail-open
    end
    U.UpdateButtons()
end

function U.DoRedo()
    local fwd = PopStack(redoStack)
    if not fwd then return end
    local current = TakeSnapshot(fwd.scope, fwd.key)
    if current then PushStack(undoStack, current) end
    RestoreSnapshot(fwd)
    suppressHooks = true
    local ok, err = pcall(ApplyAfterRestore, fwd)
    suppressHooks = false
    _G.MSUF__UndoRestoring = false
    if not ok then -- fail-open
    end
    U.UpdateButtons()
end

---------------------------------------------------------------------------
-- Clear
---------------------------------------------------------------------------
function U.Clear()
    WipeStack(undoStack); WipeStack(redoStack)
    nudgeGroupOpen = false
    if nudgeTimerHandle then nudgeTimerHandle:Cancel(); nudgeTimerHandle = nil end
    U.UpdateButtons()
end

function U.CanUndo() return #undoStack > 0 end
function U.CanRedo() return #redoStack > 0 end

---------------------------------------------------------------------------
-- Global entry points
---------------------------------------------------------------------------
_G.MSUF_EM_UndoBeforeChange = U.BeforeChange
_G.MSUF_EM_UndoClear        = U.Clear
