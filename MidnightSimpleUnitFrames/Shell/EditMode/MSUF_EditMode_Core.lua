--- EditMode/MSUF_EditMode_Core.lua - Edit Mode namespace and shared utilities
--- Registry, State and Undo, the next files in MSUF_EditMode.xml, build on Util.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic
local function PublishCompat(name, value)
    return ExportPublic(name, value)
end
local EM2 = _G.MSUF_EM2
if type(EM2) ~= "table" then EM2 = {} end
PublishCompat("MSUF_EM2", EM2)

local Util = EM2.Util
if type(Util) ~= "table" then Util = {} end
EM2.Util = Util

--- Edit Mode 2 version tag.
EM2.VERSION = "2.0.0"

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

local EditRound = _G.MSUF_RoundOffset

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
    if key == "player" or key == "target" or key == "focus" or key == "boss" or key == "arena" then return key end
    if key:match("^boss%d+$") then return "boss" end
    if key:match("^arena%d+$") then return "arena" end
end

local RequestGroupGeometryApply = _G.MSUF_RequestGroupGeometryApply

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

Util.Tr = MSUF.Translate

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
    pettarget = "uf_pettarget",
    boss = "uf_boss",
    arena = "uf_arena",
}
Util.UNIT_LABELS = Util.UNIT_LABELS or {
    player = "Player",
    target = "Target",
    targettarget = "ToT",
    focustarget = "Focus Target",
    focus = "Focus",
    pet = "Pet",
    pettarget = "Pet Target",
    boss = "Boss",
    arena = "Arena",
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
--- Translated display label of a registered element. The seven detached power
--- bars share one registry label, so theirs carries the unit.
function Util.ElementLabel(key, cfg)
    local tr = Util.Tr or tostring
    if type(cfg) == "table" and cfg.popupType == "resource" and cfg.resourceUnit then
        return tr(cfg.label or "Detached power bar") .. " (" .. tr(Util.UnitLabel(cfg.resourceUnit)) .. ")"
    end
    return tr(type(cfg) == "table" and cfg.label or key)
end
function Util.NormalizeUnitKey(unit)
    if not unit then return nil end
    if unit == "targettarget" or unit == "tot" then return "targettarget" end
    if unit == "focustarget" or unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit) then return "boss" end
    if _G.MSUF_GetArenaIndexFromToken and _G.MSUF_GetArenaIndexFromToken(unit) then return "arena" end
    return unit
end
function Util.NormalizeSimpleUnit(unit, allowBossIndex)
    if unit == "boss" then return allowBossIndex and "boss1" or "boss" end
    if unit == "arena" then return allowBossIndex and "arena1" or "arena" end
    if allowBossIndex and type(unit) == "string" and unit:match("^boss%d+$") then return unit end
    if (not allowBossIndex) and type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    if allowBossIndex and type(unit) == "string" and unit:match("^arena%d+$") then return unit end
    if (not allowBossIndex) and type(unit) == "string" and unit:match("^arena%d+$") then return "arena" end
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
    if key == "uf_pettarget" then return "pettarget" end
    if key == "uf_boss" then return "boss" end
    if key == "uf_arena" then return "arena" end
    if key:match("^boss%d+$") then return "boss" end
    if key:match("^arena%d+$") then return "arena" end
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

--- Profile identity stamps (MSUF.ProfileRuntime): a snapshot restores only
--- into the profile it was taken from, never into one switched to, reset or
--- imported since.
local function ProfileIdentity()
    local runtime = MSUF and MSUF.ProfileRuntime
    return runtime and runtime.Identity and runtime.Identity() or nil
end

local function IsCurrentProfile(identity)
    local runtime = MSUF and MSUF.ProfileRuntime
    if not (runtime and runtime.IsCurrentIdentity) then return true end
    return runtime.IsCurrentIdentity(identity) == true
end

local function SharedHistoryService()
    local menu = (type(MSUF) == "table" and MSUF.MSUF2) or _G.MSUF2
    if type(menu) ~= "table" then return nil end
    return menu
end

--- State and Undo read these.
Util.ApplyGroupSettingsForKeySafe = ApplyGroupSettingsForKeySafe
Util.ProfileIdentity, Util.IsCurrentProfile = ProfileIdentity, IsCurrentProfile
Util.SharedHistoryService = SharedHistoryService
