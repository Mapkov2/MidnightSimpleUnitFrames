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

--- Edit Mode position fields use one visual coordinate contract regardless of
--- the frame's saved anchor pair. X is the signed gap from the screen center to
--- the center-facing horizontal edge: a frame left of center uses its RIGHT
--- edge, a frame right of center uses its LEFT edge, and an overlapping frame
--- reports zero. Y remains the TOP edge relative to the screen center. Runtime
--- profile offsets stay untouched until the user edits a field; then the
--- requested visual delta is translated back into the existing anchor's local
--- scale. Mirrored left/right elements therefore report equal magnitudes.
local function EditFrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local frameScale = frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale()) or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and tonumber(UIParent:GetEffectiveScale()) or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end
    if not uiScale or uiScale <= 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return left * ratio, right * ratio, top * ratio, bottom * ratio, frameScale, uiScale
end

local function EditScreenCenter()
    local left, right, top, bottom = EditFrameRectToUI(UIParent)
    if left then return (left + right) * 0.5, (bottom + top) * 0.5 end
    return ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0) * 0.5,
        ((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0) * 0.5
end

local function EditRound(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function EditHorizontalPosition(left, right, centerX)
    if right <= centerX then return right - centerX end
    if left >= centerX then return left - centerX end
    return 0
end

function Util.FramePositionValues(frame)
    local left, right, top, bottom = EditFrameRectToUI(frame)
    if not left then return nil end
    local centerX, centerY = EditScreenCenter()
    return EditRound(EditHorizontalPosition(left, right, centerX)), EditRound(top - centerY),
        EditRound(right - left), EditRound(top - bottom)
end

function Util.TranslateFramePosition(frame, currentOffsetX, currentOffsetY, displayX, displayY)
    local left, right, top, _, frameScale, uiScale = EditFrameRectToUI(frame)
    if not left then
        return tonumber(currentOffsetX) or 0, tonumber(currentOffsetY) or 0, false
    end
    local centerX, centerY = EditScreenCenter()
    local currentX, currentY = EditHorizontalPosition(left, right, centerX), top - centerY
    local savedX = tonumber(currentOffsetX) or 0
    local savedY = tonumber(currentOffsetY) or 0
    local requestedX = tonumber(displayX)
    local requestedY = tonumber(displayY)
    local scaleRatio = uiScale / frameScale
    local nextX, nextY = savedX, savedY
    --- The edit boxes show rounded geometry. Treat that same rounded value as
    --- unchanged so editing width/height or another field cannot introduce a
    --- sub-pixel position drift. After a resize, the rounded reference edge
    --- changes and the old field value deliberately restores it.
    if requestedX ~= nil and requestedX ~= EditRound(currentX) then
        local currentEdgeX
        if requestedX < 0 then
            currentEdgeX = right - centerX
        elseif requestedX > 0 then
            currentEdgeX = left - centerX
        elseif right <= centerX then
            currentEdgeX = right - centerX
        elseif left >= centerX then
            currentEdgeX = left - centerX
        end
        if currentEdgeX ~= nil then
            nextX = EditRound(savedX + (requestedX - currentEdgeX) * scaleRatio)
        end
    end
    if requestedY ~= nil and requestedY ~= EditRound(currentY) then
        nextY = EditRound(savedY + (requestedY - currentY) * scaleRatio)
    end
    return nextX, nextY, nextX ~= savedX or nextY ~= savedY
end

function Util.ApplyAllSettingsSafe()
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        UF.Apply(nil)
        return true
    end
    return false
end

local function EditGroupKindForKey(key)
    key = tostring(key or "")
    if key == "gf_party" or key == "party" then return "party" end
    if key == "gf_raid" or key == "raid" then return "raid" end
    if key == "gf_mythicraid" or key == "mythicraid" then return "mythicraid" end
    if key == "gf_priority" or key == "priority" then return "priority" end
end

local function EditCastbarUnitForKey(key)
    key = tostring(key or "")
    if key:sub(1, 8) == "castbar_" then key = key:sub(9) end
    if key == "player" or key == "target" or key == "focus" or key == "boss" then return key end
    if key:match("^boss%d+$") then return "boss" end
end

local function RequestGroupGeometryApply(kind, reason)
    if not kind then return false end
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local apply = (menu and menu.ApplyService) or _G.MSUF_Menu2_ApplyService
    if not (apply and type(apply.RequestGroup) == "function") then return false end
    apply.RequestGroup(kind, "geometry", reason or "EM2_GROUP_GEOMETRY")
    if type(apply.Flush) == "function" then apply.Flush() end
    return true
end

local function ApplyGroupSettingsForKeySafe(kind)
    if RequestGroupGeometryApply(kind, "EM2_CORE_GROUP_GEOMETRY") then
        return true
    end
    local gf = MSUF and MSUF.GF
    if type(gf) ~= "table" or not kind then return false end
    local did = false
    local dirty
    if gf.DIRTY_GEOMETRY and gf.DIRTY_LAYOUT then
        dirty = gf.DIRTY_GEOMETRY + gf.DIRTY_LAYOUT
    else
        dirty = gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() and type(gf.DeferGroupRuntime) == "function" then
        gf.DeferGroupRuntime("layout", kind, dirty)
        did = true
    else
        if type(gf.RefreshGeometry) == "function" then gf.RefreshGeometry(kind); did = true end
        if type(gf.RefreshVisuals) == "function" and dirty then gf.RefreshVisuals(kind, dirty); did = true end
    end
    return did
end

local function ApplyCastbarSettingsForKeySafe(unit)
    unit = EditCastbarUnitForKey(unit)
    if not unit then return false end
    local did = false
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
        did = true
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        did = true
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals(unit)
        did = true
    end
    return did
end

--- Edit Mode writes offsets/sizes straight into MSUF_DB and never routes through
--- MSUF_UFCore_NotifyConfigChanged the way Menu2 does, so nothing marks the
--- UFCore config dirty. Factory.Apply(key) only refreshes the compiled spec for
--- Apply(nil), which means a scoped apply would run against the pre-change spec
--- and can re-anchor the frame to its old offsets. Refresh the spec first.
local function RefreshUnitConfigSpec(UF, key)
    local config = UF and UF.Config
    if not (key and config and type(config.RefreshUnit) == "function") then return false end
    local units = type(UF.UnitsForConfigKey) == "function" and UF.UnitsForConfigKey(key) or nil
    if units then
        for i = 1, #units do config.RefreshUnit(units[i]) end
        return true
    end
    config.RefreshUnit(key)
    return true
end

function Util.ApplySettingsForKeySafe(key)
    local groupKind = EditGroupKindForKey(key)
    if groupKind then return ApplyGroupSettingsForKeySafe(groupKind) end

    if tostring(key or ""):sub(1, 8) == "castbar_" then
        return ApplyCastbarSettingsForKeySafe(key)
    end

    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        RefreshUnitConfigSpec(UF, key)
        return UF.Apply(key) == true
    end
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate) == "function" and key then
        _G.MSUF_ApplyUnitFrameKey_Immediate(key)
        return true
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
        EM2.Movers.SyncAll()
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
local registryListeners = {}

local function NotifyRegistryListeners(action, key, cfg)
    for _, listener in pairs(registryListeners) do
        if type(listener) == "function" then
            pcall(listener, action, key, cfg)
        end
    end
end

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
    NotifyRegistryListeners("register", cfg.key, cfg)
end

function Registry.Unregister(key)
    if not key then return end
    local cfg = elements[key]
    elements[key] = nil
    dirty = true
    NotifyRegistryListeners("unregister", key, cfg)
end

--- Cold-path listener used by optional Edit Mode shells whose elements can
--- register after PLAYER_LOGIN (notably Group Frames). Runtime render paths do
--- not touch this list.
function Registry.RegisterChangeListener(owner, listener)
    if owner == nil or type(listener) ~= "function" then return false end
    registryListeners[owner] = listener
    return true
end

function Registry.UnregisterChangeListener(owner)
    if owner == nil then return end
    registryListeners[owner] = nil
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

local function GetDeepCopy()
    return _G.MSUF_DeepCopy
end

local function SnapshotDB()
    local dc = GetDeepCopy()
    local db = _G.MSUF_DB; if not db or not dc then _snapshot = nil; return end
    _snapshot = dc(db)
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
    RestoreSnapshotTable(db, _snapshot)
    _snapshot = nil
    return true
end

local function SharedHistoryService()
    local menu = (type(MSUF) == "table" and MSUF.MSUF2) or _G.MSUF2
    if type(menu) ~= "table" then return nil end
    return menu
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
    -- before exposing the active state so an immediate Assistant command cannot
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
    local combatLocked = (InCombatLockdown and InCombatLockdown()) and true or false

    --- Stop ticker FIRST (zero overhead from this point)
    if EM2.Ticker and EM2.Ticker.Stop then EM2.Ticker.Stop() end

    --- Combat may interrupt an active drag or a debounced nudge. Cancel its
    --- timers before hiding widgets can fire OnHide commits. The shared
    --- history service retains the before-state and finalizes it only after
    --- combat, without taking a DB snapshot here.
    if combatLocked and EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end

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

--- CANCEL ALL - restore DB to pre-edit-mode state, then exit
function State.CancelAll()
    if not active then return end
    local exitingProvider = provider
    enterGeneration = enterGeneration + 1

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
        pcall(suspendBridge)
    elseif type(_G.MSUF_EllesmereEditMode_ClearMoveState) == "function" then
        pcall(_G.MSUF_EllesmereEditMode_ClearMoveState)
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
    if type(resumeBridge) == "function" then pcall(resumeBridge) end
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
local sharedDebounceKey
local sharedDebounceGeneration = 0
local sharedDebounceTimer
local pendingPreparedTimers = {}
local activeFallbackPrepared
local activeChangeUsesShared = false

local HISTORY_CATEGORY_LABELS = {
    unit = "Unit frame",
    castbar = "Castbar",
    general = "General layout",
    aura = "Aura layout",
    gf = "Group frame",
    external = "External frame",
}

local function HistoryChangeLabel(category, key, action)
    local label = HISTORY_CATEGORY_LABELS[tostring(category or "")] or "Edit Mode"
    key = tostring(key or "")
    if key ~= "" then label = label .. ": " .. key end
    return tostring(action or "Change") .. " " .. label
end

local function HistoryChangeSource(category, key)
    return "edit_mode:" .. tostring(category or "change") .. ":" .. tostring(key or "")
end

local function CommitSharedDebounce()
    if not sharedDebounceKey then return false end
    sharedDebounceKey = nil
    sharedDebounceGeneration = sharedDebounceGeneration + 1
    if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
    sharedDebounceTimer = nil
    local history = SharedHistoryService()
    return history and type(history.CommitHistoryTransaction) == "function"
        and history.CommitHistoryTransaction() or false
end

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
    if key == "priority" then return "gf_priority" end
    if key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority" then return key end
    return nil
end

local function ResolveGFKind(key)
    if key == "gf_party" then return "party" end
    if key == "gf_raid" then return "raid" end
    if key == "gf_mythicraid" then return "mythicraid" end
    if key == "gf_priority" then return "priority" end
    if key == "party" or key == "raid" or key == "mythicraid" or key == "priority" then return key end
    return nil
end

local function NormalizeCastbarUndoUnit(unit)
    unit = tostring(unit or "")
    if unit:match("^boss%d+$") then return "boss" end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    return nil
end

local function ApplyCastbarUndo(unit)
    unit = NormalizeCastbarUndoUnit(unit)
    if unit and type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
        return true
    end
    if unit and type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        return true
    end
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals(unit)
        return true
    end
    return false
end

local function ApplyAuraUndo(unit)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not a3 then return false end
    unit = tostring(unit or "")
    if unit ~= "" and unit ~= "shared" and unit ~= "global" and unit ~= "*" then
        if type(a3.RequestScope) == "function" then return a3.RequestScope(unit, "EM2_AURA_UNDO") end
        if type(a3.RefreshUnit) == "function" then return a3.RefreshUnit(unit) end
    end
    if type(a3.RefreshAll) == "function" then return a3.RefreshAll() end
    return false
end

local function ApplyGFUndo(key, dbKey)
    local gf = MSUF and MSUF.GF
    local kind = ResolveGFKind(key) or ResolveGFKind(dbKey)
    if RequestGroupGeometryApply(kind, "EM2_UNDO_GROUP_GEOMETRY") then
        return true
    end
    if gf and type(gf.RefreshGeometry) == "function" then
        gf.RefreshGeometry(kind)
        if type(gf.RefreshUnitBindings) == "function" then
            gf.RefreshUnitBindings(kind)
        end
        if type(gf.RefreshVisuals) == "function" then
            gf.RefreshVisuals(kind, gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)
        end
        return true
    end
    if gf and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)
        return true
    end
    if kind and type(_G.MSUF_GF_RefreshGeometry) == "function" then
        _G.MSUF_GF_RefreshGeometry(kind)
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then
            _G.MSUF_GF_RefreshUnitBindings(kind)
        end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then
            _G.MSUF_GF_RefreshVisuals(kind)
        end
        return true
    end
    if type(_G.MSUF_GF_RefreshAll) == "function" then
        _G.MSUF_GF_RefreshAll()
        return true
    end
    if type(_G.MSUF_GF_Refresh) == "function" then
        _G.MSUF_GF_Refresh()
        return true
    end
    return false
end

local function CaptureState(category, key)
    if category == "external" then
        local external = EM2.ExternalElements
        return external and type(external.CaptureHistoryState) == "function"
            and external.CaptureHistoryState(key) or nil
    end
    local db = _G.MSUF_DB
    if not db then return nil end
    local snap = { category = category, key = key }
    if category == "unit" then
        snap.data = DeepCopy(db[key] or {})
    elseif category == "castbar" then
        snap.data = DeepCopy(db.general or {})
    elseif category == "general" then
        -- Edit Mode also owns a small number of global layout tools (for
        -- example the external anchor picker).  Keep them in the Edit Mode
        -- undo domain without pretending they are castbar changes.
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
    if snap.category == "external" then
        local external = EM2.ExternalElements
        if external and type(external.RestoreHistoryState) == "function" then
            external.RestoreHistoryState(snap)
        end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(snap.key, true)
        end
        PublishCompat("MSUF__UndoRestoring", false)
        return
    end
    local db = _G.MSUF_DB
    if not db then PublishCompat("MSUF__UndoRestoring", false); return end

    if snap.category == "unit" then
        db[snap.key] = db[snap.key] or {}
        DeepRestore(db[snap.key], snap.data)
        ApplySettingsForKeySafe(snap.key)
    elseif snap.category == "castbar" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        ApplyCastbarUndo(snap.key)
    elseif snap.category == "general" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        ApplyAllSettingsSafe()
    elseif snap.category == "aura" then
        db.auras3 = db.auras3 or {}
        DeepRestore(db.auras3, snap.data)
        ApplyAuraUndo(snap.key)
    elseif snap.category == "gf" then
        local dbKey = snap.dbKey or ResolveGFDBKey(snap.key)
        if dbKey then
            db[dbKey] = db[dbKey] or {}
            DeepRestore(db[dbKey], snap.data)
            ApplyGFUndo(snap.key, dbKey)
            if _G.MSUF_EM2_SyncGFPopups then _G.MSUF_EM2_SyncGFPopups() end
        end
    end

    if snap.category == "unit" and type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
        _G.MSUF_ForceTextLayoutForUnitKey(snap.key)
    end

    --- Sync popups
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    Util.SyncMovers()

    PublishCompat("MSUF__UndoRestoring", false)
end

-- Two-phase snapshots are used by fail-closed callers which can only know
-- whether an external apply succeeded after the DB write.  Failed applies do
-- not consume undo capacity or destroy the redo stack.
function Undo.PrepareChange(category, key)
    if _G.MSUF__UndoRestoring then return nil end
    local history = SharedHistoryService()
    if history and type(history.PrepareHistoryChange) == "function" then
        local prepared = history.PrepareHistoryChange(
            HistoryChangeLabel(category, key),
            HistoryChangeSource(category, key)
        )
        if prepared then
            return { category = category, key = key, shared = prepared }
        end
    end
    return CaptureState(category, key)
end

function Undo.CommitPrepared(snap)
    if _G.MSUF__UndoRestoring or type(snap) ~= "table" or type(snap.category) ~= "string" then return false end
    if snap.shared then
        local history = SharedHistoryService()
        return history and type(history.CommitPreparedHistory) == "function"
            and history.CommitPreparedHistory(snap.shared) or false
    end
    undoStack[#undoStack + 1] = snap
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    for i = 1, #redoStack do redoStack[i] = nil end
    return true
end

function Undo.BeforeChange(category, key, debounce)
    if _G.MSUF__UndoRestoring then return end
    local history = SharedHistoryService()
    if history and type(history.BeginHistoryTransaction) == "function" then
        local dk = tostring(category or "") .. ":" .. tostring(key or "")
        if debounce then
            if sharedDebounceKey and sharedDebounceKey ~= dk then CommitSharedDebounce() end
            if not sharedDebounceKey then
                if not history.BeginHistoryTransaction(
                    HistoryChangeLabel(category, key),
                    HistoryChangeSource(category, key)
                ) then return false end
                sharedDebounceKey = dk
            end
            sharedDebounceGeneration = sharedDebounceGeneration + 1
            local generation = sharedDebounceGeneration
            if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
            sharedDebounceTimer = nil
            local function CommitAfterDebounce()
                sharedDebounceTimer = nil
                if (InCombatLockdown and InCombatLockdown()) then return end
                if sharedDebounceKey == dk and sharedDebounceGeneration == generation then CommitSharedDebounce() end
            end
            if C_Timer and C_Timer.NewTimer then
                sharedDebounceTimer = C_Timer.NewTimer(DEBOUNCE_SEC, CommitAfterDebounce)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(DEBOUNCE_SEC, function()
                    if (InCombatLockdown and InCombatLockdown()) then return end
                    if sharedDebounceKey == dk and sharedDebounceGeneration == generation then CommitSharedDebounce() end
                end)
            end
            return true
        end
        CommitSharedDebounce()
        local snap = Undo.PrepareChange(category, key)
        if not snap then return false end
        if snap.shared and C_Timer and (C_Timer.NewTimer or C_Timer.After) then
            local pending = { snap = snap, active = true }
            pendingPreparedTimers[pending] = true
            local function CommitPreparedAfterFrame()
                if not pending.active then return end
                pending.active = false
                pendingPreparedTimers[pending] = nil
                Undo.CommitPrepared(snap)
            end
            if C_Timer.NewTimer then
                pending.timer = C_Timer.NewTimer(0, CommitPreparedAfterFrame)
            else
                C_Timer.After(0, CommitPreparedAfterFrame)
            end
            return true
        end
        return Undo.CommitPrepared(snap)
    end
    if debounce then
        local now = GetTime()
        local dk = (category or "") .. ":" .. (key or "")
        if dk == debounceKey and (now - debounceTime) < DEBOUNCE_SEC then return end
        debounceKey = dk
        debounceTime = now
    end
    local snap = Undo.PrepareChange(category, key)
    if not snap then return end
    return Undo.CommitPrepared(snap)
end

function Undo.BeginChange(category, key, action)
    if _G.MSUF__UndoRestoring then return false end
    CommitSharedDebounce()
    local history = SharedHistoryService()
    if history and type(history.BeginHistoryTransaction) == "function" then
        activeChangeUsesShared = history.BeginHistoryTransaction(
            HistoryChangeLabel(category, key, action or "Move"),
            HistoryChangeSource(category, key)
        ) == true
        activeFallbackPrepared = nil
        return activeChangeUsesShared
    end
    activeFallbackPrepared = CaptureState(category, key)
    activeChangeUsesShared = false
    return activeFallbackPrepared ~= nil
end

function Undo.CommitChange()
    if activeChangeUsesShared then
        activeChangeUsesShared = false
        local history = SharedHistoryService()
        return history and type(history.CommitHistoryTransaction) == "function"
            and history.CommitHistoryTransaction() or false
    end
    local snap = activeFallbackPrepared
    activeFallbackPrepared = nil
    if not snap then return false end
    return Undo.CommitPrepared(snap)
end

function Undo.CancelChange()
    local combatLocked = (InCombatLockdown and InCombatLockdown()) and true or false
    local history = SharedHistoryService()
    if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
    sharedDebounceTimer = nil
    for pending in pairs(pendingPreparedTimers) do
        pending.active = false
        if pending.timer and pending.timer.Cancel then pending.timer:Cancel() end
        if combatLocked and pending.snap and pending.snap.shared
            and history and type(history.DeferPreparedHistory) == "function" then
            history.DeferPreparedHistory(pending.snap.shared)
        end
        pendingPreparedTimers[pending] = nil
    end
    local hadSharedChange = activeChangeUsesShared or sharedDebounceKey ~= nil
    activeChangeUsesShared = false
    activeFallbackPrepared = nil
    sharedDebounceKey = nil
    sharedDebounceGeneration = sharedDebounceGeneration + 1
    if combatLocked and hadSharedChange and history and type(history.CommitHistoryTransaction) == "function" then
        return history.CommitHistoryTransaction()
    end
    return history and type(history.CancelHistoryTransaction) == "function"
        and history.CancelHistoryTransaction() or false
end

function Undo.DoUndo()
    CommitSharedDebounce()
    if activeChangeUsesShared or activeFallbackPrepared then Undo.CommitChange() end
    local history = SharedHistoryService()
    if history and type(history.Undo) == "function" then return history.Undo() end
    if #undoStack == 0 then return end
    local snap = undoStack[#undoStack]
    undoStack[#undoStack] = nil
    local current = CaptureState(snap.category, snap.key)
    if current then redoStack[#redoStack + 1] = current end
    RestoreState(snap)
end

function Undo.DoRedo()
    CommitSharedDebounce()
    if activeChangeUsesShared or activeFallbackPrepared then Undo.CommitChange() end
    local history = SharedHistoryService()
    if history and type(history.Redo) == "function" then return history.Redo() end
    if #redoStack == 0 then return end
    local snap = redoStack[#redoStack]
    redoStack[#redoStack] = nil
    local current = CaptureState(snap.category, snap.key)
    if current then undoStack[#undoStack + 1] = current end
    RestoreState(snap)
end

function Undo.Clear()
    CommitSharedDebounce()
    activeFallbackPrepared = nil
    activeChangeUsesShared = false
    for i = 1, #undoStack do undoStack[i] = nil end
    for i = 1, #redoStack do redoStack[i] = nil end
    debounceKey = nil
    local history = SharedHistoryService()
    if history and type(history.ClearHistory) == "function" then history.ClearHistory() end
end

function Undo.CanUndo()
    local history = SharedHistoryService()
    if history and type(history.GetHistoryState) == "function" then
        local state = history.GetHistoryState()
        return state and state.canUndo == true
    end
    return #undoStack > 0
end
function Undo.CanRedo()
    local history = SharedHistoryService()
    if history and type(history.GetHistoryState) == "function" then
        local state = history.GetHistoryState()
        return state and state.canRedo == true
    end
    return #redoStack > 0
end

function Undo.RefreshControls()
    if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
    if EM2.UnitPopup and EM2.UnitPopup.RefreshHistory then EM2.UnitPopup.RefreshHistory() end
    if EM2.CastPopup and EM2.CastPopup.RefreshHistory then EM2.CastPopup.RefreshHistory() end
    if EM2.AuraPopup and EM2.AuraPopup.RefreshHistory then EM2.AuraPopup.RefreshHistory() end
    if type(_G.MSUF_EM2_RefreshGFHistoryControls) == "function" then
        _G.MSUF_EM2_RefreshGFHistoryControls()
    end
end

function EM2.RefreshAfterHistoryRestore(reason)
    Undo.RefreshControls()
    if not (EM2.State and EM2.State.IsActive and EM2.State.IsActive()) then return end
    if Util.IsConfigCombatLocked and Util.IsConfigCombatLocked() then return end

    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    if type(_G.MSUF_EM2_SyncGFPopups) == "function" then _G.MSUF_EM2_SyncGFPopups() end
    Util.SyncMovers()
    Util.RefreshUFPreview(reason or "EM2_HISTORY_RESTORE")

    -- This is a cold, user-triggered restore path. The async preview pipeline
    -- coalesces all UnitFrame preview work without adding an idle/combat loop.
    if type(_G.MSUF_SyncAllUnitPreviewsAsync) == "function" then
        _G.MSUF_SyncAllUnitPreviewsAsync()
    elseif type(_G.MSUF_SyncAllUnitPreviews) == "function" then
        _G.MSUF_SyncAllUnitPreviews()
    end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout() end
end

--- Legacy globals
local function MSUF_EM_UndoBeforeChange(category, key, debounce) Undo.BeforeChange(category, key, debounce) end
local function MSUF_EM_UndoBeginChange(category, key, action) return Undo.BeginChange(category, key, action) end
local function MSUF_EM_UndoCommitChange() return Undo.CommitChange() end
local function MSUF_EM_UndoClear() Undo.Clear() end
local function MSUF_EM_UndoUndo() Undo.DoUndo() end
local function MSUF_EM_UndoRedo() Undo.DoRedo() end
local function MSUF_EM_RefreshHistoryControls() Undo.RefreshControls() end
local function MSUF_EM_RefreshAfterHistoryRestore(reason, source) return EM2.RefreshAfterHistoryRestore(reason, source) end

ExportPublic("MSUF_EM_UndoBeforeChange", MSUF_EM_UndoBeforeChange)
ExportPublic("MSUF_EM_UndoBeginChange", MSUF_EM_UndoBeginChange)
ExportPublic("MSUF_EM_UndoCommitChange", MSUF_EM_UndoCommitChange)
ExportPublic("MSUF_EM_UndoClear", MSUF_EM_UndoClear)
ExportPublic("MSUF_EM_UndoUndo", MSUF_EM_UndoUndo)
ExportPublic("MSUF_EM_UndoRedo", MSUF_EM_UndoRedo)
ExportPublic("MSUF_EM_RefreshHistoryControls", MSUF_EM_RefreshHistoryControls)
ExportPublic("MSUF_EM_RefreshAfterHistoryRestore", MSUF_EM_RefreshAfterHistoryRestore)

--- MSUF_EM2_Init.lua

--- MSUF_EM2_Init.lua
--- Loads last. Compat.lua already provides all legacy globals.
--- This file exposes version tag; combat listener is demand-registered by state.

EM2.VERSION = "2.0.0"
