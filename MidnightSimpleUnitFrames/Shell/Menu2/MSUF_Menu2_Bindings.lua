local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local KS, KSW, WL = M.KeySet, M.KeySetFromWords, M.WordList
local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
if type(ApplyService) ~= "table" then error("MSUF Menu2 ApplyService missing") end
local SafeInvoke = ApplyService.SafeInvoke
local CallGlobal = ApplyService.CallGlobal

-- Menu2 binding/apply layer.
-- Owns DB accessors, pending apply coalescing, edit history snapshots, and fanout into the
-- older MSUF global refresh APIs. Page files bind controls here instead of calling globals
-- directly for every slider/toggle movement.
local HISTORY_LIMIT = 500
local historyDepth = 0
local historyRestoring = false
local historySessionActive = false
local historySessionBaseSnapshot
local historySessionSnapshot
local historySessionDirty = false
local historyTransaction
local refreshQueued = false
local MENU_REFRESH_DELAY = 0.04
local C_Timer = _G.C_Timer
local UNIT_KEYS = KS("player", "target", "targettarget", "focustarget", "focus", "pet", "boss")
local TEXT_SLOT_SIDES = { "Left", "Center", "Right" }
local TEXT_SLOT_SIDE_SET = { Left = true, Center = true, Right = true }
local DIRECT_TEXT_GROUP_ORDER = { "name", "hp", "power" }
local DIRECT_TEXT_GROUPS = {
    name = { single = true, basePrefix = "name", baseAliasPrefix = "nameText", directPrefix = "directName", defaultX = 4, defaultY = -4 },
    hp = { basePrefix = "hp", baseAliasPrefix = "hpText", directPrefix = "directHealth", slotPrefix = "hpText", legacySlotPrefix = "hp", defaultX = -4, defaultY = -4 },
    power = { basePrefix = "power", baseAliasPrefix = "powerText", directPrefix = "directPower", slotPrefix = "powerText", legacySlotPrefix = "power", defaultX = -4, defaultY = 4 },
}

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end
local function EnsureHistoryStacks()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    return M.historyUndo, M.historyRedo
end
local function ProfileSystemNeedsInit()
    local active = _G.MSUF_ActiveProfile
    local gdb = _G.MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    local activeTable = type(active) == "string" and type(profiles) == "table" and profiles[active] or nil
    return type(active) ~= "string"
        or active == ""
        or type(_G.MSUF_DB) ~= "table"
        or type(activeTable) ~= "table"
        or _G.MSUF_DB ~= activeTable
end
function M.EnsureDB()
    if ProfileSystemNeedsInit() and type(_G.MSUF_InitProfiles) == "function" then
        SafeInvoke(_G.MSUF_InitProfiles)
    end
    local ensure = _G.MSUF_EnsureDB
    if type(ensure) == "function" then SafeInvoke(ensure) end
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    return _G.MSUF_DB
end
function M.GetUnitDB(unit)
    local db = M.EnsureDB()
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then unit = "player" end
    db[unit] = db[unit] or {}
    return db[unit], db
end
function M.GetGeneralDB()
    local db = M.EnsureDB()
    db.general = db.general or {}
    return db.general, db
end
local function NumberOr(value, fallback)
    local n = tonumber(value)
    if n ~= nil then return n end
    return fallback or 0
end
local function TextDefault(spec, axis)
    return axis == "X" and (spec.defaultX or 0) or (spec.defaultY or 0)
end
local function TextBaseOffset(conf, spec, axis, overrideValue)
    if overrideValue ~= nil then return NumberOr(overrideValue, TextDefault(spec, axis)) end
    local value = conf and conf[spec.basePrefix .. "Offset" .. axis]
    if value == nil and spec.baseAliasPrefix then value = conf and conf[spec.baseAliasPrefix .. "Offset" .. axis] end
    return NumberOr(value, TextDefault(spec, axis))
end
local function TextSlotOffset(conf, spec, side, axis, overrideValue)
    if overrideValue ~= nil then return NumberOr(overrideValue, 0) end
    return NumberOr((conf and conf[spec.slotPrefix .. side .. "Offset" .. axis]) or (conf and conf[spec.legacySlotPrefix .. side .. "Offset" .. axis]), 0)
end
local function HasModernTextAxis(conf, spec, axis)
    if not conf then return false end
    if conf[spec.basePrefix .. "Offset" .. axis] ~= nil or (spec.baseAliasPrefix and conf[spec.baseAliasPrefix .. "Offset" .. axis] ~= nil) then return true end
    if not spec.single then
        for i = 1, #TEXT_SLOT_SIDES do
            local side = TEXT_SLOT_SIDES[i]
            if conf[spec.slotPrefix .. side .. "Offset" .. axis] ~= nil or conf[spec.legacySlotPrefix .. side .. "Offset" .. axis] ~= nil then return true end
        end
    end
    return false
end
local function DirectTextChangedKey(spec, changedKey)
    if changedKey == nil or changedKey == "directTextLayout" then return nil end
    local key = tostring(changedKey)
    local axis = key:match("^" .. spec.basePrefix .. "Offset([XY])$")
    if not axis and spec.baseAliasPrefix then axis = key:match("^" .. spec.baseAliasPrefix .. "Offset([XY])$") end
    if axis then return "base", axis end
    if not spec.single then
        local side
        side, axis = key:match("^" .. spec.slotPrefix .. "([A-Za-z]+)Offset([XY])$")
        if not side then side, axis = key:match("^" .. spec.legacySlotPrefix .. "([A-Za-z]+)Offset([XY])$") end
        if side and axis and TEXT_SLOT_SIDE_SET[side] then return "slot", axis, side end
    end
end
local function SyncDirectTextGroupOffsets(conf, group, changedKey, changedValue)
    if type(conf) ~= "table" or conf.directTextLayout ~= true then return false end
    local spec = DIRECT_TEXT_GROUPS[group]
    if not spec then return false end
    local kind, axis, changedSide = DirectTextChangedKey(spec, changedKey)
    if changedKey ~= nil and changedKey ~= "directTextLayout" and not kind then return false end
    local changed = false
    local function SetDirect(suffix, axis, value)
        local key = spec.directPrefix .. suffix .. "Offset" .. axis
        value = math.floor((tonumber(value) or 0) + 0.5)
        if conf[key] ~= value then
            conf[key] = value
            changed = true
        end
    end
    local function SyncAxis(axis, baseOverride)
        if baseOverride == nil and not HasModernTextAxis(conf, spec, axis) then return end
        local base = TextBaseOffset(conf, spec, axis, baseOverride)
        if spec.single then
            SetDirect("", axis, base)
            return
        end
        for i = 1, #TEXT_SLOT_SIDES do
            local side = TEXT_SLOT_SIDES[i]
            SetDirect(side, axis, base + TextSlotOffset(conf, spec, side, axis))
        end
    end
    if changedKey == nil or changedKey == "directTextLayout" then
        SyncAxis("X")
        SyncAxis("Y")
        return changed
    end
    if kind == "base" then
        SyncAxis(axis, changedValue)
        return changed
    end
    if kind == "slot" and changedSide then
        SetDirect(changedSide, axis, TextBaseOffset(conf, spec, axis) + TextSlotOffset(conf, spec, changedSide, axis, changedValue))
    end
    return changed
end
function M.SyncDirectTextOffsets(conf, changedKey, changedValue)
    local changed = false
    for i = 1, #DIRECT_TEXT_GROUP_ORDER do
        if SyncDirectTextGroupOffsets(conf, DIRECT_TEXT_GROUP_ORDER[i], changedKey, changedValue) then changed = true end
    end
    return changed
end
function M.SyncDirectPowerTextOffsets(conf, changedKey, changedValue)
    return SyncDirectTextGroupOffsets(conf, "power", changedKey, changedValue)
end
local IsConfigCombatLocked = M.IsConfigCombatLocked
function M.IsConfigCombatLocked()
    return IsConfigCombatLocked()
end
function M.ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    elseif print then
        print("|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end
function M.BlockCombatAction()
    if not IsConfigCombatLocked() then return false end
    M.ShowConfigCombatLockMessage()
    return true
end
function M.StageFactoryReset()
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    local fn = _G.MSUF_DoFullReset
    if type(fn) ~= "function" then return false end
    fn({ skipReload = true })
    return true
end
local function BlockCombatAndRefresh(ctx)
    if not M.BlockCombatAction() then return false end
    M.CallIf(M.Refresh, ctx)
    return true
end
local DeepCopy = M.DeepCopy
local function DeepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
local function DeepReplace(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepReplace(dst[k], v)
        else
            dst[k] = v
        end
    end
end
local function HistoryCharacterKey()
    if type(_G.MSUF_GetCharKey) == "function" then
        local ok, value = pcall(_G.MSUF_GetCharKey)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    if type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
        local okName, name = pcall(_G.UnitName, "player")
        local okRealm, realm = pcall(_G.GetRealmName)
        if okName and okRealm and type(name) == "string" and name ~= "" and type(realm) == "string" then
            return name .. "-" .. realm
        end
    end
end
local function SnapshotProfileRouting()
    local key = HistoryCharacterKey()
    if not key then return nil end
    local gdb = _G.MSUF_GlobalDB
    local chars = type(gdb) == "table" and gdb.char or nil
    local char = type(chars) == "table" and chars[key] or nil
    local existed = type(char) == "table"
    local autoSwitch
    if existed then autoSwitch = char.specAutoSwitch end -- Preserve an explicit false value.
    return {
        key = key,
        existed = existed,
        specAutoSwitch = autoSwitch,
        specProfileMap = existed and DeepCopy(char.specProfileMap) or nil,
    }
end
local function SnapshotDB()
    -- Spec-profile routing is the only persisted options family outside the
    -- active profile DB. Keep its tiny per-character state in the same history
    -- transaction so Assistant/UI undo and redo remain truthful for every
    -- setting without copying the complete GlobalDB/profile collection.
    return {
        _msuf2HistoryState = true,
        profileDB = DeepCopy(M.EnsureDB()),
        profileRouting = SnapshotProfileRouting(),
    }
end
local function HistoryProfileDB(snapshot)
    if type(snapshot) == "table" and snapshot._msuf2HistoryState == true then return snapshot.profileDB end
    return snapshot -- Backward compatibility for a history entry created before this schema.
end
local function RestoreProfileRouting(snapshot)
    local routing = type(snapshot) == "table" and snapshot._msuf2HistoryState == true and snapshot.profileRouting or nil
    if type(routing) ~= "table" or type(routing.key) ~= "string" then return end
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    if type(gdb.char) ~= "table" then gdb.char = {} end
    local char = gdb.char[routing.key]
    if type(char) ~= "table" then char = {}; gdb.char[routing.key] = char end
    if routing.existed then
        char.specAutoSwitch = routing.specAutoSwitch
        char.specProfileMap = DeepCopy(routing.specProfileMap)
    else
        char.specAutoSwitch = nil
        char.specProfileMap = nil
        if next(char) == nil then gdb.char[routing.key] = nil end
    end
end
local function CurrentHistorySnapshot()
    if historySessionActive and type(historySessionSnapshot) == "table" then return historySessionSnapshot end
    return SnapshotDB()
end
local function QueueMenuRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local function Run()
        refreshQueued = false
        if M.frame and M.frame.IsShown and M.frame:IsShown() and M.Refresh then M.Refresh() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(MENU_REFRESH_DELAY, Run)
    else
        Run()
    end
end
local function NotifyHistoryChanged(refreshMenu)
    if M.RefreshHistoryControls then SafeInvoke(M.RefreshHistoryControls) end
    if M.frame and M.frame.RefreshStatus then SafeInvoke(M.frame.RefreshStatus, M.frame) end
    if refreshMenu == true then QueueMenuRefresh() end
end
local function FeedbackLabel(text, limit)
    text = tostring(text or "")
    limit = tonumber(limit) or 34
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end
local function CommandFeedback(text, kind, seconds)
    local fn = M.ShowStatusFeedback or M.ShowInlineFeedback
    if type(fn) == "function" then fn(text, kind or "info", seconds or 1.25) end
end
local function PushHistory(label, source, before, after)
    if DeepEqual(before, after) then return false end
    if historySessionActive and type(historySessionBaseSnapshot) ~= "table" then historySessionBaseSnapshot = before end
    local stack, redo = EnsureHistoryStacks()
    stack[#stack + 1] = {
        label = label or "MSUF2 change",
        source = source,
        before = before,
        after = after,
    }
    while #stack > HISTORY_LIMIT do
        table.remove(stack, 1)
    end
    WipeTable(redo)
    if historySessionActive then
        historySessionSnapshot = after
        historySessionDirty = true
    end
    NotifyHistoryChanged(false)
    if type(M.ShowHistoryFeedback) == "function" then
        M.ShowHistoryFeedback(FeedbackLabel(label or "MSUF2 change", 30), 2.0)
    end
    return true
end
local function RebuildActivePage()
    local key = M.activeKey
    if key and M.frame and M.frame.IsShown and M.frame:IsShown() and M.InvalidatePage and M.SelectPage then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    else
        NotifyHistoryChanged(true)
    end
end
local function NormalizeHistoryUnit(unit)
    if ApplyService.NormalizeUnit then return ApplyService.NormalizeUnit(unit) end
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then return nil end
    return unit
end
local HISTORY_PAGE_RESET_UNITS = {
    uf_player = "player",
    uf_target = "target",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_boss = "boss",
}
local HISTORY_PAGE_RESET_FEATURES = {
    opt_castbar = "castbar",
    classpower = "classpower",
    gameplay = "gameplay",
    modules = "modules",
}
local HISTORY_CLASSPOWER_RUNTIME = { full = true, cdm = true }
local HISTORY_CLASSPOWER_FLAGS = { preview = true, applyAll = false, classpower = true, classpowerApplied = true }
local COLOR_CLASSPOWER_RUNTIME = { colors = true, playerHP = true }
local function HistoryUnitFromSource(source)
    if type(source) ~= "string" then return nil end
    local unit = source:match("^unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^apply:unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return NormalizeHistoryUnit(HISTORY_PAGE_RESET_UNITS[pageKey]) end
end
local function HistoryFeatureFromSource(source)
    if type(source) ~= "string" then return nil end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return HISTORY_PAGE_RESET_FEATURES[pageKey] end
end
local function ApplyScopedFeatureRuntime(kind, reason)
    kind = tostring(kind or "")
    reason = reason or "MSUF2_HISTORY_FEATURE"
    if kind == "castbar" then
        if ApplyService.RequestCastbars then return ApplyService.RequestCastbars(reason, "history") ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { history = false, preview = true, applyAll = false, castbar = true, castbarTextures = true }) ~= false end
        local did = CallGlobal("MSUF_UpdateCastbarVisuals")
        did = CallGlobal("MSUF_UpdateBossCastbarPreview") or did
        return did
    end
    if kind == "classpower" then
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason, HISTORY_CLASSPOWER_RUNTIME, HISTORY_CLASSPOWER_FLAGS)
            return true
        end
        return CallGlobal("MSUF_ClassPower_Apply", { full = true, cdm = true })
    end
    if kind == "gameplay" then
        if M.ApplyGameplay then
            local ok, result = SafeInvoke(M.ApplyGameplay)
            return ok == true and result ~= false
        end
        if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
            local ok, result = SafeInvoke(MSUF.MSUF_RequestGameplayApply, reason)
            return ok == true and result ~= false
        end
        if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
            local ok, result = SafeInvoke(MSUF.MSUF_ApplyGameplayVisuals)
            return ok == true and result ~= false
        end
        return false
    end
    if kind == "modules" then
        return CallGlobal("MSUF_ApplyModules")
    end
    return false
end
local function ApplyScopedHistoryRestore(reason, source)
    local unit = HistoryUnitFromSource(source)
    local applyReason = reason or "MSUF2_HISTORY_UNIT"
    if unit then
        local opts = {
            history = false,
            preview = true,
            power = true,
            castbar = true,
            auras = true,
        }
        return M.RequestUnitApply(unit, applyReason, opts) ~= false
    end
    local feature = HistoryFeatureFromSource(source)
    if feature then return ApplyScopedFeatureRuntime(feature, applyReason) end
    return false
end

local function RequestHistoryAurasRuntime(reason)
    if ApplyService.RequestAuraFonts then
        ApplyService.RequestAuraFonts("shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    if ApplyService.RequestAuras then
        ApplyService.RequestAuras("shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        SafeInvoke(auras.RequestApply)
        return true
    end
    return false
end

local function RequestHistoryGroupRuntime(reason)
    if ApplyService.RequestGroupReset then
        ApplyService.RequestGroupReset(reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if ApplyService.RequestGroup then
        ApplyService.RequestGroup("group", "reset", reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RefreshAll) == "function" then
            SafeInvoke(MSUF.GF.RefreshAll)
        else
            if type(MSUF.GF.RefreshVisuals) == "function" then SafeInvoke(MSUF.GF.RefreshVisuals) end
        end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then SafeInvoke(MSUF.GF.RefreshPreviewLayout) end
        return true
    end
    return false
end

local function FlushApplyServiceNow()
    if ApplyService.Flush then
        ApplyService.Flush()
        return true
    end
    return false
end

local function ApplyHistorySnapshot(snapshot, reason, source)
    if type(snapshot) ~= "table" then return false end
    local profileDB = HistoryProfileDB(snapshot)
    if type(profileDB) ~= "table" then return false end
    historyRestoring = true
    DeepReplace(M.EnsureDB(), profileDB)
    RestoreProfileRouting(snapshot)
    if historySessionActive then historySessionSnapshot = snapshot end
    historyRestoring = false
    if ApplyScopedHistoryRestore(reason, source) then
        M.CallIf(M.MarkMenuDataDirty, reason or "history")
        RebuildActivePage()
        return true
    end
    -- A restored profile snapshot may span UnitFrames, Auras3, ClassPower, GroupFrames, and
    -- Menu2 state, so restore fanout is centralized and explicit.
    M.RequestGeneralApply(reason or "MSUF2_HISTORY", { preview = true, alpha = true, castbar = true })
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        SafeInvoke(MSUF.MSUF_RequestGameplayApply)
    elseif MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        SafeInvoke(MSUF.MSUF_ApplyGameplayVisuals)
    end
    do
        local db = M.EnsureDB()
        local g = db and db.general
        local ui = type(g) == "table" and type(g.UIScale) == "table" and g.UIScale or nil
        if ui and ui.Enabled == true and type(_G.MSUF_SetGlobalUiScale) == "function" then
            SafeInvoke(_G.MSUF_SetGlobalUiScale, tonumber(ui.Scale) or 1, true)
        elseif ui and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            SafeInvoke(_G.MSUF_ResetGlobalUiScale, true)
        end
        if M.ApplyMenuFrameScale and M.frame then
            SafeInvoke(M.ApplyMenuFrameScale, M.frame)
        elseif M.GetEffectiveMenuScale and M.frame and M.frame.SetScale and type(g) == "table" then
            local ok, scale = SafeInvoke(M.GetEffectiveMenuScale, g.slashMenuScale)
            if ok and type(scale) == "number" then M.frame:SetScale(scale) end
        end
    end
    RequestHistoryAurasRuntime(reason or "MSUF2_HISTORY_AURAS")
    if ApplyService.RequestClassPower then
        ApplyService.RequestClassPower("MSUF2_HISTORY_CLASSPOWER", { full = true, cdm = true }, {
            preview = false,
            applyAll = false,
            classpower = true,
        })
    end
    RequestHistoryGroupRuntime(reason or "MSUF2_HISTORY_GROUP")
    FlushApplyServiceNow()
    if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
        SafeInvoke(_G.MSUF_ApplySpecProfileIfEnabled, "MSUF2_HISTORY_PROFILE_ROUTING")
    end
    M.CallIf(M.ApplyLocaleSelection, M.GetLocaleSelection and M.GetLocaleSelection() or "auto")
    M.CallIf(M.MarkMenuDataDirty, reason or "history")
    RebuildActivePage()
    return true
end

-- Guided setup can span multiple menu sessions and reloads, while normal Menu2
-- history intentionally cannot. Keep one compact active-profile restore point
-- in guided-tour state and reuse the same proven restore fanout as Undo.
function M.CaptureGuidedTourRestorePoint()
    if IsConfigCombatLocked() then return nil end
    local snapshot = SnapshotDB()
    snapshot._msuf2GuidedProfileName = tostring(_G.MSUF_ActiveProfile or "Default")
    return snapshot
end

function M.RestoreGuidedTourRestorePoint(snapshot)
    if IsConfigCombatLocked() then return false end
    local expectedProfile = type(snapshot) == "table" and tostring(snapshot._msuf2GuidedProfileName or "") or ""
    local activeProfile = tostring(_G.MSUF_ActiveProfile or "Default")
    if expectedProfile == "" or activeProfile ~= expectedProfile then return false, "profile_mismatch" end
    return ApplyHistorySnapshot(snapshot, "MSUF2_GUIDED_TOUR_RESTORE", "guided_tour:restore_point")
end

function M.IsHistoryCapturing()
    return historyDepth > 0 or historyRestoring
end
function M.CaptureHistory(label, source, fn)
    if type(fn) ~= "function" then return nil end
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring then
        local ok, result = SafeInvoke(fn)
        if not ok then return nil end
        if result ~= false then
            if historyTransaction then
                historyTransaction.dirty = true
            elseif M.MarkMenuDataDirty then
                M.MarkMenuDataDirty("history")
            end
        end
        return result
    end
    local before = CurrentHistorySnapshot()
    historyDepth = historyDepth + 1
    local ok, result = SafeInvoke(fn)
    historyDepth = historyDepth - 1
    if not ok then
        CommandFeedback("Action failed", "danger", 1.8)
        return nil
    end
    if result == false then return result end
    local pushed = PushHistory(label, source, before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return result
end
function M.RunWithHistory(label, source, fn)
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then return M.CaptureHistory(label, source, fn) end
    return type(fn) == "function" and fn() or nil
end
function M.StartHistorySession()
    if IsConfigCombatLocked() then return false end
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionActive = true
    historySessionBaseSnapshot = nil
    historySessionSnapshot = nil
    historySessionDirty = false
    local undo, redo = EnsureHistoryStacks()
    WipeTable(undo)
    WipeTable(redo)
    NotifyHistoryChanged()
end
function M.EndHistorySession()
    historySessionActive = false
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionBaseSnapshot = nil
    historySessionSnapshot = nil
    historySessionDirty = false
end
function M.CheckpointHistory(label, source)
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    local before = CurrentHistorySnapshot()
    local after = SnapshotDB()
    local pushed = PushHistory(label or "MSUF2 change", source or "menu:checkpoint", before, after)
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.BeginHistoryTransaction(label, source)
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    historyTransaction = {
        label = label or "MSUF2 change",
        source = source or "menu:transaction",
        before = CurrentHistorySnapshot(),
    }
    historyDepth = historyDepth + 1
    return true
end
function M.CommitHistoryTransaction()
    local tx = historyTransaction
    if not tx then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    local pushed = PushHistory(tx.label, tx.source, tx.before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.ResetHistorySession()
    if M.BlockCombatAction() then return false end
    if not historySessionActive or type(historySessionBaseSnapshot) ~= "table" then return false end
    local ok = ApplyHistorySnapshot(historySessionBaseSnapshot, "MSUF2_HISTORY_RESET_SESSION")
    if ok then M.ClearHistory() end
    if ok then CommandFeedback("Session changes reset", "ok", 1.4) end
    return ok
end
function M.ClearHistory()
    local undo, redo = EnsureHistoryStacks()
    WipeTable(undo)
    WipeTable(redo)
    if historySessionActive then
        historySessionBaseSnapshot = SnapshotDB()
        historySessionSnapshot = historySessionBaseSnapshot
        historySessionDirty = false
    end
    NotifyHistoryChanged()
end
function M.GetHistoryState()
    local undoStack, redoStack = EnsureHistoryStacks()
    local undo = undoStack[#undoStack]
    local redo = redoStack[#redoStack]
    return {
        canUndo = undo ~= nil,
        canRedo = redo ~= nil,
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and historySessionDirty,
        undoLabel = undo and undo.label or nil,
        redoLabel = redo and redo.label or nil,
        undoCount = #undoStack,
        redoCount = #redoStack,
    }
end
function M.Undo()
    if M.BlockCombatAction() then return false end
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(undo)
    if not entry then return false end
    redo[#redo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.before, "MSUF2_HISTORY_UNDO", entry.source)
    if ok and historySessionActive then historySessionDirty = #undo > 0 end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Undid " .. FeedbackLabel(entry.label), "info", 1.25) end
    return ok
end
function M.Redo()
    if M.BlockCombatAction() then return false end
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(redo)
    if not entry then return false end
    undo[#undo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.after, "MSUF2_HISTORY_REDO", entry.source)
    if ok and historySessionActive then historySessionDirty = true end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Redid " .. FeedbackLabel(entry.label), "info", 1.25) end
    return ok
end
local function WidgetHistoryLabel(ctx, widget, fallback)
    local fs = widget and (widget._msuf2Title or widget._msuf2Label)
    if fs and fs.GetText then
        local ok, text = SafeInvoke(fs.GetText, fs)
        if ok and text and text ~= "" then return text end
    end
    if widget and widget.GetText then
        local ok, text = SafeInvoke(widget.GetText, widget)
        if ok and text and text ~= "" then return text end
    end
    return fallback or tostring((ctx and ctx.key) or "MSUF2 option")
end
local function WidgetHistorySource(ctx, widget, suffix)
    local key = (ctx and ctx.key) or "page"
    local kind = widget and (widget._msuf2ControlKind or widget.GetObjectType and widget:GetObjectType()) or "control"
    return tostring(key) .. ":" .. tostring(kind) .. ":" .. tostring(suffix or WidgetHistoryLabel(ctx, widget))
end
local function CaptureWidgetChange(ctx, widget, label, fn)
    label = label or WidgetHistoryLabel(ctx, widget)
    return M.CaptureHistory(label, WidgetHistorySource(ctx, widget, label), fn)
end
function M.RequestUnitApply(unit, reason, opts)
    if M.BlockCombatAction() then return false end
    if ApplyService.NormalizeUnit then
        unit = ApplyService.NormalizeUnit(unit)
    else
        unit = (unit == "tot") and "targettarget" or unit
        unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    end
    if not UNIT_KEYS[unit] then return end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or ("MSUF2_" .. tostring(unit)), "apply:unit:" .. tostring(unit) .. ":" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestUnit then result = ApplyService.RequestUnit(unit, reason, opts) end
    return result
end
function M.SetUnitValue(unit, key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "unit:" .. tostring(unit) .. ":" .. tostring(key), function()
            return M.SetUnitValue(unit, key, value, reason, opts)
        end)
    end
    local conf = M.GetUnitDB(unit)
    local sameValue = conf[key] == value
    if not sameValue then conf[key] = value end
    local directTextChanged = M.SyncDirectTextOffsets(conf, key)
    if sameValue and not directTextChanged then return false end
    M.RequestUnitApply(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end
function M.RequestGeneralApply(reason, opts)
    if M.BlockCombatAction() then return false end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestGeneral then result = ApplyService.RequestGeneral(reason, opts) end
    return result
end
function M.SetGeneralValue(key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "general:" .. tostring(key), function()
            return M.SetGeneralValue(key, value, reason, opts)
        end)
    end
    local g = M.GetGeneralDB()
    if g[key] == value then return false end
    g[key] = value
    if key == "menuLocale" then
        if M.ApplyLocaleSelection then SafeInvoke(M.ApplyLocaleSelection, value) end
        if opts and opts.noRuntime == true then return true end
    end
    M.RequestGeneralApply(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end
local UNIT_PAGE_RESETS = { uf_player = { unit = "player", label = "Player" }, uf_target = { unit = "target", label = "Target" }, uf_targettarget = { unit = "targettarget", label = "Target of Target" }, uf_focustarget = { unit = "focustarget", label = "Focus Target" }, uf_focus = { unit = "focus", label = "Focus" }, uf_boss = { unit = "boss", label = "Boss Frames" }, uf_pet = { unit = "pet", label = "Pet" } }
local CASTBAR_SUFFIX_KEYS = WL "TimeFormat IconPosition IconSize IconOffsetX IconOffsetY IconSpacing IconBorderStyle SpellNamePosition SpellNameFontSize TextOffsetX TextOffsetY SpellNameAlign SpellNameMaxWidth SpellNameTruncate TimePosition TimeFontSize TimeOffsetX TimeOffsetY"
local CASTBAR_TARGET_NAME_SUFFIX_KEYS = WL "TargetNamePosition TargetNameFontSize TargetNameAlign TargetNameOffsetX TargetNameOffsetY"
local function BuildUnitCastbarResetKeys(spec)
    local keys = { spec.enable, spec.backend .. "Backend", spec.backend .. "BackendBeforeHide", spec.time, spec.icon, spec.name }
    if spec.targetName then
        keys[#keys + 1] = spec.targetName
        for i = 1, #CASTBAR_TARGET_NAME_SUFFIX_KEYS do keys[#keys + 1] = spec.base .. CASTBAR_TARGET_NAME_SUFFIX_KEYS[i] end
    end
    for i = 1, #CASTBAR_SUFFIX_KEYS do keys[#keys + 1] = spec.base .. CASTBAR_SUFFIX_KEYS[i] end
    return keys
end
local UNIT_CASTBAR_GENERAL_KEYS = {
    player = BuildUnitCastbarResetKeys({ base = "castbarPlayer", backend = "castbarPlayer", enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", name = "castbarPlayerShowSpellName" }),
    target = BuildUnitCastbarResetKeys({ base = "castbarTarget", backend = "castbarTarget", enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", name = "castbarTargetShowSpellName", targetName = "castbarTargetShowTargetName" }),
    focus = BuildUnitCastbarResetKeys({ base = "castbarFocus", backend = "castbarFocus", enable = "enableFocusCastbar", time = "showFocusCastTime", icon = "castbarFocusShowIcon", name = "castbarFocusShowSpellName", targetName = "castbarFocusShowTargetName" }),
    boss = BuildUnitCastbarResetKeys({ base = "bossCast", backend = "bossCastbar", enable = "enableBossCastbar", time = "showBossCastTime", icon = "showBossCastIcon", name = "showBossCastName", targetName = "showBossCastTargetName" }),
}
local function ResetInfo(label, kind, summary)
    return { label = label, kind = kind, summary = summary }
end
local GROUP_RESET_INFO = ResetInfo("Group Frames", "group", "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions")
local AURA_STYLE_SUMMARY = "scope-aware Buff and Debuff basics, cooldown and stack styling"
local PAGE_RESET_INFO = {
    gf_layout = GROUP_RESET_INFO,
    gf_bars = GROUP_RESET_INFO,
    gf_auras = GROUP_RESET_INFO,
    gf_indicators = GROUP_RESET_INFO,
    opt_bars = ResetInfo("Bars", "bars", "shared bar textures, gradients, rounded frame corners, absorb display, outlines, highlight borders, power smoothing and all per-unit/group bar overrides"),
    opt_fonts = ResetInfo("Fonts", "fonts", "shared font family, text style, name/power text coloring, name shortening and all per-unit/group font overrides"),
    auras3 = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    auras3_buffs = ResetInfo("Aura Buffs", "auras", "Buff basics, cooldown and stack styling"),
    auras3_debuffs = ResetInfo("Aura Debuffs", "auras", "Debuff basics, cooldown and stack styling"),
    auras3_custom = ResetInfo("Custom Auras", "auras", "named UnitFrame SpellID displays, icon placement and Full-Frame effects"),
    auras3_rendering = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    auras3_filters = ResetInfo("Aura Filters", "auras", "scope-aware Buff and Debuff filters and blacklists"),
    auras3_styling = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    opt_castbar = ResetInfo("Castbar", "castbar", "global castbar behavior, textures, boss castbar and interrupt indicator settings"),
    opt_colors = ResetInfo("Colors", "colors", "frame colors, group-frame colors, class/NPC colors, power colors, castbar colors, aura colors and gameplay color settings"),
    opt_misc = ResetInfo("Miscellaneous", "misc", "language/menu behavior, update pacing, tooltips, Blizzard-frame handling, minimap icon, sounds and range-fade settings"),
    classpower = ResetInfo("Class Resources", "classpower", "class-resource layout, behavior, style, auto-hide, detached power bar and alternative mana settings"),
    gameplay = ResetInfo("Gameplay", "gameplay", "gameplay enhancement settings such as combat text, crosshair and click-cast behavior"),
    modules = ResetInfo("Modules", "modules", "optional style/module settings such as MSUF Style and dropdown style"),
    profiles = ResetInfo("Profiles", "profile", "the entire active profile"),
}
for pageKey, info in pairs(UNIT_PAGE_RESETS) do
    PAGE_RESET_INFO[pageKey] = {
        label = info.label,
        kind = "unit",
        unit = info.unit,
        summary = info.label .. " unit-frame settings, including layout, text, portrait, power, status icons, transparency, load conditions and this unit's castbar toggles",
    }
end
local BARS_GENERAL_KEYS = KSW [[
    barTexture barBackgroundTexture enableGradient enablePowerGradient gradientStrength gradientDirection
    gradientDirRight gradientDirLeft gradientDirUp gradientDirDown showSelfHealPrediction healPredAnchorMode
    overAbsorbOverlay absorbBarTexture healAbsorbBarTexture dispelBorderTrigger unitDispelOverlayEnabled unitDispelOverlayStyle
    unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger bossTargetOutlineMode
    bossTargetHighlightEnabled hlPrioEnabled hlPrioOrder highlightPrioEnabled highlightPrioOrder roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedMouseover barOutlineColorR barOutlineColorG
    barOutlineColorB barOutlineColorA
]]
local BARS_SCOPE_KEYS = KSW [[
    hlOverride hpPowerTextOverride barTexture barBackgroundTexture barBgTexture absorbTextMode absorbAnchorMode healPredEnabled healPredAnchorMode
    overAbsorbOverlay absorbBarOpacity healAbsorbBarOpacity barOutlineThickness barOutlineStrata highlightBorderThickness hlAggroSize
    aggroOutlineMode dispelOutlineMode dispelBorderTrigger unitDispelOverlayEnabled unitDispelOverlayStyle
    unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger
    purgeOutlineMode hlPrioEnabled hlPrioOrder enableGradient enablePowerGradient gradientStrength
    gradientDirection gradientDirRight gradientDirLeft gradientDirUp gradientDirDown powerSmoothFill
    barOutlineColorR barOutlineColorG barOutlineColorB barOutlineColorA
]]
local BARS_TABLE_KEYS = KSW [[
    barOutlineThickness barOutlineStrata smoothPowerBar realtimePowerText roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedMouseover
]]
local FONT_GENERAL_KEYS = KSW "fontKey boldText noOutline textBackdrop fontMonochrome fontShadowStrength fontTextAlpha fontBaselineOffset nameClassColor npcNameRed nameNpcClassColor colorPowerTextByType colorHealthTextByHealth"
local FONT_SCOPE_KEYS = KSW [[
    fontOverride fontKey boldText noOutline textBackdrop fontMonochrome fontShadowStrength fontTextAlpha fontBaselineOffset nameClassColor npcNameRed nameNpcClassColor colorPowerTextByType colorHealthTextByHealth
    fontOutline useGlobalFontColor fontR fontG fontB nameColorMode nameShortenEnabled nameClipSide
    nameMaxChars nameNoEllipsis shortenNames shortenNameClipSide shortenNameMaxChars shortenNameShowDots
]]
local FONT_ROOT_KEYS = KS("shortenNames", "shortenNameClipSide", "shortenNameMaxChars", "shortenNameShowDots")
local UNIT_AND_GROUP_RESET_KEYS = WL [[player target targettarget focustarget focus pet boss gf_party gf_raid gf_mythicraid]]
local MISC_GENERAL_KEYS = KSW [[
    menuLocale slashMenuSnapEnabled hideAdvancedMenu showWelcomeMessage versionCheckEnabled disableUnitInfoTooltips
    unitInfoTooltipStyle unitTooltipProvider unitTooltipAnchor unitTooltipMode unitTooltipModifier
    disableBlizzardUnitFrames hardKillBlizzardPlayerFrame
    showMinimapIcon showNavigationIcons playTargetSelectLostSounds
]]
local MISC_UNIT_KEYS = {}
local MISC_UNIT_RESET_KEYS = WL [[target focus boss]]
local CASTBAR_GENERAL_KEYS = KSW [[
    empowerColorStages enableFocusKickIcon focusKickIconWidth focusKickIconHeight focusKickTextSize
    focusKickIconOffsetX focusKickIconOffsetY kickReadyShowTarget kickReadyShowFocus kickReadyShowBoss
    kickReadyStyle kickReadySize kickReadyAutoSize kickReadyAnchor kickReadyOffsetX kickReadyOffsetY
]]
local MODULES_GENERAL_KEYS = KS("styleEnabled")
local COLOR_GENERAL_KEYS = KSW "highlightEnabled playerCastbarOverrideEnabled playerCastbarOverrideMode npcClassColorBar npcTypeTarget npcTypeFocus npcTypeBoss npcTypeToT"
local COLOR_GAMEPLAY_KEYS = KS("combatStateColorSync")
local COLOR_BARS_KEYS = KS("classPowerComboPointColorMode", "classPowerSlotColorModes", "classPowerFullColorEnabled")
local GROUP_COLOR_KEYS = KSW [[
    gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB
    gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBgTexture bgR bgG bgB hpBarAlpha hpBgAlpha
    alphaExcludeTextPortrait deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA
    debuffStripeAlpha debuffStripeColorR debuffStripeColorG debuffStripeColorB targetR targetG targetB
    hlFocusColorR hlFocusColorG hlFocusColorB groupBorderR groupBorderG groupBorderB groupBorderA
    ciAggroColorR ciAggroColorG ciAggroColorB
]]
local AURAS_GENERAL_PREFIXES = WL "auras"
local AURAS_SHARED_COLOR_KEYS = KS("pandemicR", "pandemicG", "pandemicB")
local function StartsWith(value, prefix)
    return type(value) == "string" and type(prefix) == "string" and value:sub(1, #prefix) == prefix
end
local function ResetTableToDefaults(dst, src)
    if type(dst) ~= "table" then return end
    for key in pairs(dst) do
        dst[key] = nil
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        dst[key] = DeepCopy(value)
    end
end
local function ReplaceRootTable(db, defaults, key)
    if type(db) ~= "table" then return end
    db[key] = db[key] or {}
    ResetTableToDefaults(db[key], type(defaults) == "table" and defaults[key] or nil)
end
local function ResetKeySet(dst, src, keys)
    if type(dst) ~= "table" or type(keys) ~= "table" then return end
    for key in pairs(keys) do
        if type(src) == "table" and src[key] ~= nil then
            dst[key] = DeepCopy(src[key])
        else
            dst[key] = nil
        end
    end
end
local function ResetFilteredKeys(dst, src, filter)
    if type(dst) ~= "table" or type(filter) ~= "function" then return end
    for key in pairs(dst) do
        if filter(key) then dst[key] = nil end
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if filter(key) then dst[key] = DeepCopy(value) end
    end
end
local function ResetRootFiltered(db, defaults, rootKey, filter)
    if type(db) ~= "table" then return end
    db[rootKey] = db[rootKey] or {}
    ResetFilteredKeys(db[rootKey], type(defaults) == "table" and defaults[rootKey] or nil, filter)
end
local function ResetUnitFiltered(db, defaults, unit, filter)
    if type(db) ~= "table" or type(unit) ~= "string" then return end
    db[unit] = db[unit] or {}
    ResetFilteredKeys(db[unit], type(defaults) == "table" and defaults[unit] or nil, filter)
end
local function EnsureTargetTargetAlias(db)
    if type(db) == "table" and type(db.targettarget) == "table" then db.tot = db.targettarget end
end
local function IsColorKey(key)
    if type(key) ~= "string" then return false end
    if COLOR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("color", 1, true) then return true end
    if lower == "barmode" or lower == "darkmode" or lower == "darkbartone" or lower == "darkbgbrightness" then return true end
    if lower == "useclasscolors" or lower == "enablehealthgradient" or lower == "gradientstrength" then return true end
    if lower == "fontcolor" or lower == "highlightcolor" or lower == "usecustomfontcolor" then return true end
    if lower == "nameclasscolor" or lower == "npcnamered" then return true end
    local last = lower:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        if lower:find("color", 1, true)
            or lower:find("font", 1, true)
            or lower:find("bg", 1, true)
            or lower:find("border", 1, true)
            or lower:find("outline", 1, true)
            or lower:find("gradient", 1, true)
            or lower:find("castbar", 1, true)
        then
            return true
        end
        if lower == "fontcolorcustomr" or lower == "fontcolorcustomg" or lower == "fontcolorcustomb" then return true end
    end
    return false
end
local function IsCastbarKey(key)
    if type(key) ~= "string" then return false end
    if CASTBAR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("castbar", 1, true) then return true end
    if lower:find("bosscast", 1, true) then return true end
    if lower:find("empower", 1, true) then return true end
    if lower == "enableplayercastbar" or lower == "enabletargetcastbar" or lower == "enablefocuscastbar" then return true end
    if lower:find("spellnamefontsize", 1, true) or lower:find("timefontsize", 1, true) then return true end
    return false
end
local function IsClassPowerBarsKey(key)
    if type(key) ~= "string" then return false end
    return StartsWith(key, "classPower")
        or StartsWith(key, "detachedPowerBar")
        or StartsWith(key, "altMana")
        or key == "showClassPower"
        or key == "showChargedComboPoints"
        or key == "runeShowTime"
        or key == "showEleMaelstrom"
        or key == "showEbonMight"
        or key == "showShadowMana"
        or key == "showAltMana"
        or key == "classPowerComboPointColorMode"
end
local function ResetAurasSharedColors(db, defaults)
    if type(db) ~= "table" then return end
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    local src = type(defaults) == "table" and type(defaults.auras3) == "table" and defaults.auras3.shared or nil
    ResetKeySet(db.auras3.shared, src, AURAS_SHARED_COLOR_KEYS)
end
local function FactoryDefaults()
    local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
    if type(create) ~= "function" then return nil end
    local ok, defaults = SafeInvoke(create)
    if ok and type(defaults) == "table" then return defaults end
    return nil
end
local function ResetUnitPage(db, defaults, unit)
    ReplaceRootTable(db, defaults, unit)
    if unit == "targettarget" then EnsureTargetTargetAlias(db) end
    local castbarKeys = UNIT_CASTBAR_GENERAL_KEYS[unit]
    if castbarKeys then
        db.general = db.general or {}
        local src = type(defaults) == "table" and defaults.general or nil
        for i = 1, #castbarKeys do
            local key = castbarKeys[i]
            db.general[key] = type(src) == "table" and DeepCopy(src[key]) or nil
        end
    end
end
local function ResetGroupFrames(db, defaults)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResetAllToDefaults) == "function" then
        local ok, result = SafeInvoke(gf.ResetAllToDefaults)
        return ok and result
    end
    ReplaceRootTable(db, defaults, "gf_party")
    ReplaceRootTable(db, defaults, "gf_raid")
    ReplaceRootTable(db, defaults, "gf_mythicraid")
    return true
end
local function ResetBarsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return BARS_GENERAL_KEYS[key] == true or BARS_SCOPE_KEYS[key] == true end)
    ResetRootFiltered(db, defaults, "bars", function(key) return BARS_TABLE_KEYS[key] == true end)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return BARS_SCOPE_KEYS[scopeKey] == true end)
    end
    EnsureTargetTargetAlias(db)
end
local function ResetFontsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return FONT_GENERAL_KEYS[key] == true end)
    ResetKeySet(db, defaults, FONT_ROOT_KEYS)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return FONT_SCOPE_KEYS[scopeKey] == true end)
    end
    EnsureTargetTargetAlias(db)
end
local function ResetAurasPage(db, defaults)
    ReplaceRootTable(db, defaults, "auras3")
    ResetRootFiltered(db, defaults, "general", function(key) return StartsWith(key, AURAS_GENERAL_PREFIXES[1]) end)
end
local function ResetCastbarPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key)
        return CASTBAR_GENERAL_KEYS[key] == true or (IsCastbarKey(key) and not IsColorKey(key))
    end)
end
local function ResetColorsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", IsColorKey)
    ReplaceRootTable(db, defaults, "classColors")
    ReplaceRootTable(db, defaults, "npcColors")
    ResetRootFiltered(db, defaults, "gameplay", function(key) return COLOR_GAMEPLAY_KEYS[key] == true or IsColorKey(key) end)
    ResetRootFiltered(db, defaults, "bars", function(key) return COLOR_BARS_KEYS[key] == true end)
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return GROUP_COLOR_KEYS[scopeKey] == true end)
    end
    ResetAurasSharedColors(db, defaults)
end
local function ResetMiscPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MISC_GENERAL_KEYS[key] == true end)
    for _, key in ipairs(MISC_UNIT_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(unitKey) return MISC_UNIT_KEYS[unitKey] == true end)
    end
end
local function ResetClassPowerPage(db, defaults)
    ResetRootFiltered(db, defaults, "bars", IsClassPowerBarsKey)
end
local function ResetGameplayPage(db, defaults)
    ReplaceRootTable(db, defaults, "gameplay")
end
local function ResetModulesPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MODULES_GENERAL_KEYS[key] == true end)
end
local PAGE_RESET_HANDLERS = {
    unit = function(db, defaults, info) ResetUnitPage(db, defaults, info.unit) end,
    group = ResetGroupFrames,
    bars = ResetBarsPage,
    fonts = ResetFontsPage,
    auras = ResetAurasPage,
    castbar = ResetCastbarPage,
    colors = ResetColorsPage,
    misc = ResetMiscPage,
    classpower = ResetClassPowerPage,
    gameplay = ResetGameplayPage,
    modules = ResetModulesPage,
}
local function FinishPageResetApply(pageKey)
    M.CallIf(M.ApplyLocaleSelection, M.GetLocaleSelection and M.GetLocaleSelection() or "auto")
    if M.ApplyMenuFrameScale and M.frame then SafeInvoke(M.ApplyMenuFrameScale, M.frame) end
    if pageKey and M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(pageKey)
        M.activeKey = nil
        M.SelectPage(pageKey)
    else
        QueueMenuRefresh()
    end
end

local function ApplyGroupPageResetRuntime(reason)
    if ApplyService.RequestGroupReset then
        return ApplyService.RequestGroupReset(reason or "MSUF2_RESET_GROUP") ~= false
    end
    local gf = MSUF and MSUF.GF
    if not gf then return false end
    if type(gf.InvalidateConfCache) == "function" then SafeInvoke(gf.InvalidateConfCache) end
    if type(gf.RefreshAll) == "function" then
        SafeInvoke(gf.RefreshAll)
    elseif type(gf.RebuildAll) == "function" then
        SafeInvoke(gf.RebuildAll)
    elseif type(gf.RefreshVisuals) == "function" then
        SafeInvoke(gf.RefreshVisuals, nil, gf.DIRTY_ALL or gf.DIRTY_CONFIG or gf.DIRTY_VISUAL)
    end
    if type(gf.RequestAuraRefresh) == "function" then SafeInvoke(gf.RequestAuraRefresh) end
    if type(gf.RefreshPreviewLayout) == "function" then SafeInvoke(gf.RefreshPreviewLayout) end
    return true
end

local function ApplyAurasPageResetRuntime(reason, visuals)
    if visuals and ApplyService.RequestAuraFonts then
        return ApplyService.RequestAuraFonts("shared", reason or "MSUF2_RESET_AURA_VISUALS") ~= false
    end
    if ApplyService.RequestAuras then
        return ApplyService.RequestAuras("shared", reason or "MSUF2_RESET_AURAS", visuals and { visuals = true } or nil) ~= false
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        SafeInvoke(auras.RequestApply, "shared", reason or "MSUF2_RESET_AURAS")
        return true
    end
    if auras and type(auras.RefreshAll) == "function" then
        SafeInvoke(auras.RefreshAll)
        return true
    end
    return false
end

local function ApplyDomainPageResetRuntime(info, reason)
    if not info then return false end
    local kind = info.kind
    if kind == "group" then
        return ApplyGroupPageResetRuntime(reason)
    end
    if kind == "bars" then
        if ApplyService.RequestBars then return ApplyService.RequestBars(reason) ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { preview = true, applyAll = false, bars = true }) ~= false end
        return false
    end
    if kind == "fonts" then
        if ApplyService.RequestFonts then return ApplyService.RequestFonts(reason) ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { preview = true, applyAll = false, fonts = true }) ~= false end
        return false
    end
    if kind == "colors" then
        local did = false
        if ApplyService.RequestColors then
            did = ApplyService.RequestColors(reason) ~= false or did
        elseif M.RequestGeneralApply then
            M.RequestGeneralApply(reason, { preview = true, applyAll = false, colors = true })
            did = true
        end
        did = ApplyAurasPageResetRuntime(reason, true) or did
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason or "MSUF2_RESET_COLORS", COLOR_CLASSPOWER_RUNTIME)
            did = true
        else
            did = CallGlobal("MSUF_ClassPower_InvalidateColors") or did
        end
        return did
    end
    if kind == "auras" then
        return ApplyAurasPageResetRuntime(reason)
    end
    return false
end

local function ApplyAfterPageReset(pageKey, info)
    local reason = "MSUF2_RESET_" .. tostring(pageKey or "PAGE")
    if info and info.kind == "unit" and info.unit then
        if M.RequestUnitApply then
            M.RequestUnitApply(info.unit, reason, { history = false, preview = true, power = true, castbar = true, auras = true })
        end
        FinishPageResetApply(pageKey)
        return
    end
    if info and ApplyScopedFeatureRuntime(info.kind, reason) then
        FinishPageResetApply(pageKey)
        return
    end
    if ApplyDomainPageResetRuntime(info, reason) then
        FinishPageResetApply(pageKey)
        return
    end
    if M.RequestGeneralApply then M.RequestGeneralApply(reason, { preview = true, alpha = true, castbar = true, frames = true }) end
    if info and info.kind == "gameplay" then M.CallIf(M.ApplyGameplay) end
    -- Page reset fanout is intentionally keyed by page kind so a unit reset does not rebuild
    -- secure group headers or Auras3 lanes unnecessarily.
    if info and (info.kind == "auras" or info.kind == "colors") then
        ApplyAurasPageResetRuntime(reason, info.kind == "colors")
    end
    if info and (info.kind == "group" or info.kind == "bars" or info.kind == "fonts" or info.kind == "colors") then
        if info.kind == "group" then
            ApplyGroupPageResetRuntime(reason)
        elseif ApplyService.RequestGroupDirtyMask then
            local gf = MSUF and MSUF.GF
            local dirty = gf and ((info.kind == "fonts" and gf.DIRTY_FONT)
                or (info.kind == "colors" and gf.DIRTY_COLOR)
                or gf.DIRTY_VISUAL)
            if dirty then
                ApplyService.RequestGroupDirtyMask("group", dirty, reason)
            elseif ApplyService.RequestGroup then
                local mode = (info.kind == "fonts" and "fonts") or (info.kind == "colors" and "colors") or "visual"
                ApplyService.RequestGroup("group", mode, reason)
            end
        elseif ApplyService.RequestGroup then
            local mode = (info.kind == "fonts" and "fonts") or (info.kind == "colors" and "colors") or "visual"
            ApplyService.RequestGroup("group", mode, reason)
        else
            local gf = MSUF and MSUF.GF
            if gf then
                if type(gf.InvalidateConfCache) == "function" then SafeInvoke(gf.InvalidateConfCache) end
                if info.kind == "fonts" and type(gf.RefreshFonts) == "function" then
                    SafeInvoke(gf.RefreshFonts)
                elseif info.kind == "colors" and type(gf.RefreshColors) == "function" then
                    SafeInvoke(gf.RefreshColors)
                elseif type(gf.RefreshVisuals) == "function" then
                    SafeInvoke(gf.RefreshVisuals, nil, gf.DIRTY_VISUAL or 2)
                elseif type(gf.RebuildAll) == "function" then
                    SafeInvoke(gf.RebuildAll)
                end
                if type(gf.RequestAuraRefresh) == "function" then SafeInvoke(gf.RequestAuraRefresh) end
            end
        end
    end
    if info and info.kind == "classpower" then
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason or "MSUF2_RESET_CLASSPOWER", { full = true, cdm = true }, { preview = true, applyAll = false, classpower = true })
        else
            CallGlobal("MSUF_ClassPower_Apply", { full = true, cdm = true })
        end
    end
    if info and info.kind == "modules" then CallGlobal("MSUF_ApplyModules") end
    FlushApplyServiceNow()
    FinishPageResetApply(pageKey)
end
local function ResetProfilePage()
    local name = _G.MSUF_ActiveProfile or "Default"
    if type(_G.MSUF_ResetProfile) ~= "function" then return false end
    SafeInvoke(_G.MSUF_ResetProfile, name)
    M.CallIf(M.ClearHistory)
    ApplyAfterPageReset("profiles", PAGE_RESET_INFO.profiles)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then _G.MSUF_ShowReloadRecommendedPopup("Profile reset") end
    return true
end
local function ResetPageImpl(pageKey)
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return false end
    if info.kind == "profile" then return ResetProfilePage() end
    local defaults = FactoryDefaults()
    if type(defaults) ~= "table" then
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback("Reset failed: defaults unavailable", "danger", 1.8)
        elseif print then
            print("|cffff0000MSUF:|r Reset failed: factory defaults are not available yet.")
        end
        return false
    end
    local db = M.EnsureDB()
    local handler = PAGE_RESET_HANDLERS[info.kind]
    if not handler then return false end
    handler(db, defaults, info)
    EnsureTargetTargetAlias(db)
    ApplyAfterPageReset(pageKey, info)
    if M.ShowStatusFeedback then
        M.ShowStatusFeedback(tostring(info.label or pageKey) .. " reset", "ok", 1.4)
    elseif print then
        print("|cffffd700MSUF:|r " .. tostring(info.label or pageKey) .. " reset to defaults.")
    end
    return true
end
function M.PageHasReset(pageKey)
    return PAGE_RESET_INFO[pageKey or ""] ~= nil
end
function M.BuildPageResetWarning(pageKey)
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return nil end
    local title = info.label or ((M.pages and M.pages[pageKey] and M.pages[pageKey].title) or pageKey or "this menu")
    title = M.Tr and M.Tr(title) or title
    if info.kind == "profile" then
        local profileName = _G.MSUF_ActiveProfile or "Default"
        return string.format(
            M.Tr("Reset %s to defaults?\n\nThis resets the entire active profile '%s' to the current MSUF factory defaults. Every menu in that profile will be affected."),
            tostring(title),
            tostring(profileName)
        )
    end
    return string.format(
        M.Tr("Reset %s to defaults?\n\nThis resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."),
        tostring(title),
        tostring((M.Tr and M.Tr(info.summary or title)) or info.summary or title)
    )
end
function M.ResetPageToDefaults(pageKey)
    if M.BlockCombatAction() then return false end
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return false end
    if info.kind == "profile" then return ResetPageImpl(pageKey) end
    return M.RunWithHistory("Reset " .. tostring(info.label or pageKey), "page:reset:" .. tostring(pageKey), function()
        return ResetPageImpl(pageKey)
    end)
end
function M.ShowPageResetConfirm(pageKey)
    if M.BlockCombatAction() then return false end
    if not M.PageHasReset(pageKey) then return false end
    local message = M.BuildPageResetWarning(pageKey)
    if not message then return false end
    if not _G.StaticPopupDialogs then return M.ResetPageToDefaults(pageKey) end
    M.InstallStaticPopup("MSUF2_PAGE_RESET_CONFIRM", {
        text = "%s",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        OnAccept = function(_, data)
            if data and data.pageKey then M.ResetPageToDefaults(data.pageKey) end
        end,
    })
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF2_PAGE_RESET_CONFIRM", message, nil, { pageKey = pageKey })
        return true
    end
    return M.ResetPageToDefaults(pageKey)
end
function M.AddRefresher(ctx, fn, key)
    if not (ctx and type(fn) == "function") then return end
    local refreshers = ctx.refreshers or (ctx.entry and ctx.entry.refreshers)
    if type(refreshers) ~= "table" then return end
    if key ~= nil then
        local seenKeys = ctx._msuf2RefresherKeys or (ctx.entry and ctx.entry._msuf2RefresherKeys)
        if not seenKeys then
            seenKeys = {}
            if ctx.entry then ctx.entry._msuf2RefresherKeys = seenKeys else ctx._msuf2RefresherKeys = seenKeys end
        end
        key = tostring(key)
        if seenKeys[key] then return fn end
        seenKeys[key] = true
    end
    local seenFns = ctx._msuf2RefresherFns or (ctx.entry and ctx.entry._msuf2RefresherFns)
    if not seenFns then
        seenFns = {}
        if ctx.entry then ctx.entry._msuf2RefresherFns = seenFns else ctx._msuf2RefresherFns = seenFns end
    end
    if seenFns[fn] then return fn end
    seenFns[fn] = true
    refreshers[#refreshers + 1] = fn
    return fn
end
function M.AddRefresherOnce(ctx, key, fn)
    if type(fn) ~= "function" then return end
    return M.AddRefresher(ctx, fn, key or fn)
end
local function ResolveRefreshEntry(ctx)
    if ctx and ctx.entry then return ctx.entry end
    return M.activeKey and M.cache and M.cache[M.activeKey] or nil
end
local function RunRefreshList(refreshers)
    if type(refreshers) ~= "table" then return end
    for i = 1, #refreshers do
        local fn = refreshers[i]
        if type(fn) == "function" then SafeInvoke(fn) end
    end
end
function M.RequestRefresh(ctx, reason)
    local entry = ResolveRefreshEntry(ctx)
    if entry then
        if entry._msuf2RefreshQueued then return true end
        M.CallIf(M.MarkMenuDataDirty, reason or "request-refresh")
        entry._msuf2RefreshQueued = true
        -- Refreshers are entry-local and de-duplicated, so rebuilding one page does not force
        -- all Menu2 controls to resync.
        local function Run()
            entry._msuf2RefreshQueued = nil
            if entry._msuf2Invalidated then return end
            if M.RunEntryRefreshers then
                SafeInvoke(M.RunEntryRefreshers, entry)
            else
                RunRefreshList(entry.refreshers)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(MENU_REFRESH_DELAY, Run)
        else
            Run()
        end
        return true
    end
    if M._msuf2RefreshQueued then return true end
    M.CallIf(M.MarkMenuDataDirty, reason or "request-refresh")
    M._msuf2RefreshQueued = true
    local function Run()
        M._msuf2RefreshQueued = nil
        local active = ResolveRefreshEntry()
        if active then
            if M.RunEntryRefreshers then SafeInvoke(M.RunEntryRefreshers, active) else RunRefreshList(active.refreshers) end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(MENU_REFRESH_DELAY, Run)
    else
        Run()
    end
    return true
end
function M.Refresh(ctx)
    M.CallIf(M.MarkMenuDataDirty, "refresh")
    local entry = ResolveRefreshEntry(ctx)
    if entry and M.RunEntryRefreshers then
        SafeInvoke(M.RunEntryRefreshers, entry, { force = true })
        return
    end
    local refreshers = ctx and ctx.refreshers
    if not refreshers then refreshers = entry and entry.refreshers end
    RunRefreshList(refreshers)
end
local function MarkCommandSearchDirty()
    if M.SearchBridge and type(M.SearchBridge.MarkSearchIndexDirty) == "function" then
        SafeInvoke(M.SearchBridge.MarkSearchIndexDirty)
    elseif M.Search and type(M.Search.MarkIndexDirty) == "function" then
        SafeInvoke(M.Search.MarkIndexDirty)
    end
end
local function NotifyGuidedControlInteraction(widget)
    if type(M.NotifyGuidedTourControlInteraction) == "function" then
        M.NotifyGuidedTourControlInteraction(widget)
    end
end
-- metadata is optional and backward-compatible.  Stable controlId/identityKey
-- and settingKey/actionKey/navigationKey values flow into both the executable
-- command and the canonical runtime-control catalog.
local function AttachCommandAction(ctx, widget, kind, getValue, setValue, opts)
    if not widget then return end
    opts = type(opts) == "table" and opts or {}
    local minValue, maxValue
    if kind == "slider" and widget.GetMinMaxValues then minValue, maxValue = widget:GetMinMaxValues() end
    local command = {
        kind = kind,
        ctxKey = ctx and ctx.key,
        controlId = opts.controlId or widget._msuf2ControlId,
        identityKey = opts.identityKey,
        controlPath = opts.controlPath,
        settingKey = opts.settingKey,
        actionKey = opts.actionKey,
        navigationKey = opts.navigationKey,
        assistantDisposition = opts.assistantDisposition,
        assistantDispositionReason = opts.assistantDispositionReason,
        assistantSettingKeys = opts.assistantSettingKeys,
        assistantSettingKeyPatterns = opts.assistantSettingKeyPatterns,
        classification = opts.classification,
        historyMode = opts.historyMode or (opts.classification == "ephemeral" and "none" or nil),
        valueKind = opts.valueKind,
        percentIsValue = opts.percentIsValue == true,
        confirmRequired = opts.confirmRequired == true,
        get = getValue,
        set = setValue,
        values = type(opts.values or widget.values) == "table" and (opts.values or widget.values) or nil,
        getValues = function()
            local values = opts.values or widget.values
            -- Keep provider failures observable. RuntimeControlCatalog owns the
            -- outer protected call and must be able to fail coverage when a
            -- real bound dropdown cannot materialize its choices. Returning an
            -- empty table here used to turn provider exceptions into a vacuous
            -- 100% value-coverage result. A provider may still intentionally
            -- return an empty table; only errors/non-table contracts fail.
            if type(values) == "function" then values = values() end
            return values
        end,
        min = opts.min or minValue,
        max = opts.max or maxValue,
        step = opts.step or widget._msuf2Step,
        label = opts.label,
        labelFn = function()
            return WidgetHistoryLabel(ctx, widget, opts.label)
        end,
        sourceFn = function(label)
            return WidgetHistorySource(ctx, widget, label)
        end,
        refresh = function()
            M.RequestOrRefresh(ctx, "command-refresh")
        end,
        blockCombat = function()
            return BlockCombatAndRefresh(ctx)
        end,
    }
    widget._msuf2CommandAction = command
    if type(M.RegisterRuntimeControl) == "function" then
        pcall(M.RegisterRuntimeControl, widget, {
            controlId = command.controlId,
            pageKey = ctx and ctx.key,
            kind = kind,
            label = opts.label or widget._msuf2SearchText or widget._msuf2SearchTitle,
            identityLabel = widget._msuf2SearchText or widget._msuf2SearchTitle or opts.label,
            identityKey = command.identityKey,
            controlPath = command.controlPath,
            settingKey = command.settingKey,
            actionKey = command.actionKey,
            navigationKey = command.navigationKey,
            assistantDisposition = command.assistantDisposition,
            assistantDispositionReason = command.assistantDispositionReason,
            assistantSettingKeys = command.assistantSettingKeys,
            assistantSettingKeyPatterns = command.assistantSettingKeyPatterns,
            classification = command.classification,
            confirmRequired = command.confirmRequired,
            command = command,
        }, "binding")
    end
    MarkCommandSearchDirty()
end
local function AddRefreshCall(ctx, fn, a, b) if type(fn) == "function" then return M.AddRefresher(ctx, function() return fn(a, b) end) end end
local function RefreshSlider(slider, getValue)
    local value = tonumber(getValue()) or 0
    local current = slider.GetValue and tonumber(slider:GetValue()) or nil
    if current ~= nil and math.abs(current - value) < 0.0001 then
        if slider.editBox and slider._msuf2FormatValue and not slider._msuf2Editing then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        return
    end
    slider._msuf2Refreshing = true
    slider:SetValue(value)
    if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
    if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
    slider._msuf2Refreshing = nil
end
local function RefreshValueControl(control, getValue) control:SetValue(getValue()) end
local function RefreshTextInput(editBox, getValue) if not editBox:HasFocus() then editBox:SetText(tostring(getValue() or "")) end end
function M.BindToggle(ctx, widget, getValue, setValue, metadata)
    if not widget then return end
    AttachCommandAction(ctx, widget, "toggle", getValue, setValue, metadata)
    local function SyncFromValue(self)
        local value = getValue() and true or false
        self:SetChecked(value)
        return value
    end
    widget:SetScript("OnClick", function(self)
        if BlockCombatAndRefresh(ctx) then
            SyncFromValue(self)
            return
        end
        local currentValue = getValue() and true or false
        local nextValue = not currentValue
        CaptureWidgetChange(ctx, self, nil, function()
            setValue(nextValue)
        end)
        SyncFromValue(self)
        NotifyGuidedControlInteraction(self)
    end)
    AddRefreshCall(ctx, SyncFromValue, widget)
end
function M.BindSlider(ctx, slider, getValue, setValue, metadata)
    if not slider then return end
    AttachCommandAction(ctx, slider, "slider", getValue, setValue, metadata)
    local function BeginSliderHistory(self)
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Refreshing or self._msuf2HistoryTransaction then return end
        if not M.BeginHistoryTransaction then return end
        local label = WidgetHistoryLabel(ctx, self)
        if M.BeginHistoryTransaction(label, WidgetHistorySource(ctx, self, label)) then self._msuf2HistoryTransaction = true end
    end
    local function CommitSliderHistory(self)
        if not self._msuf2HistoryTransaction then return end
        self._msuf2HistoryTransaction = nil
        M.CallIf(M.CommitHistoryTransaction)
    end
    slider._msuf2BeginSliderHistory = BeginSliderHistory
    slider._msuf2CommitSliderHistory = CommitSliderHistory
    slider:HookScript("OnMouseDown", BeginSliderHistory)
    slider:HookScript("OnMouseUp", CommitSliderHistory)
    slider:HookScript("OnHide", CommitSliderHistory)
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Step and self._msuf2Step >= 1 then value = math.floor(value + 0.5) end
        local current = tonumber(getValue()) or 0
        if math.abs(current - value) < 0.0001 then return end
        CaptureWidgetChange(ctx, self, nil, function()
            setValue(value)
        end)
        NotifyGuidedControlInteraction(self)
    end)
    AddRefreshCall(ctx, RefreshSlider, slider, getValue)
end
function M.BindSegment(ctx, segment, getValue, setValue, metadata)
    if not segment then return end
    AttachCommandAction(ctx, segment, "segment", getValue, setValue, metadata)
    for i = 1, #(segment.buttons or {}) do
        local btn = segment.buttons[i]
        btn:SetScript("OnClick", function(self)
            if BlockCombatAndRefresh(ctx) then return end
            if getValue() == self._msuf2Value then
                segment:SetValue(self._msuf2Value)
                return
            end
            CaptureWidgetChange(ctx, segment, nil, function()
                setValue(self._msuf2Value)
            end)
            segment:SetValue(self._msuf2Value)
            NotifyGuidedControlInteraction(segment)
        end)
    end
    AddRefreshCall(ctx, RefreshValueControl, segment, getValue)
end
function M.BindDropdown(ctx, dropdown, getValue, setValue, metadata)
    if not dropdown then return end
    AttachCommandAction(ctx, dropdown, "dropdown", getValue, setValue, metadata)
    dropdown:SetOnValueChanged(function(value)
        if BlockCombatAndRefresh(ctx) then
            if type(getValue) == "function" then dropdown:SetValue(getValue()) end
            return
        end
        if type(getValue) == "function" and getValue() == value then
            dropdown:SetValue(value)
            return
        end
        CaptureWidgetChange(ctx, dropdown, nil, function()
            setValue(value)
        end)
        if type(getValue) == "function" then
            dropdown:SetValue(getValue())
        else
            dropdown:SetValue(value)
        end
        NotifyGuidedControlInteraction(dropdown)
    end)
    AddRefreshCall(ctx, RefreshValueControl, dropdown, getValue)
end
function M.BindTextInput(ctx, editBox, getValue, setValue, commitOnBlur, metadata)
    if not editBox then return end
    if type(commitOnBlur) == "table" and metadata == nil then
        metadata = commitOnBlur
        commitOnBlur = metadata.commitOnBlur
    end
    AttachCommandAction(ctx, editBox, "textinput", getValue, setValue, metadata)
    editBox._msuf2CommitOnBlur = commitOnBlur and true or false
    editBox:SetOnValueCommitted(function(value)
        if BlockCombatAndRefresh(ctx) then return end
        if tostring(getValue() or "") == tostring(value or "") then return end
        CaptureWidgetChange(ctx, editBox, nil, function()
            setValue(value or "")
        end)
        NotifyGuidedControlInteraction(editBox)
    end)
    AddRefreshCall(ctx, RefreshTextInput, editBox, getValue)
end
function M.BindColor(ctx, colorButton, getRGB, setRGB, metadata)
    if not colorButton then return end
    AttachCommandAction(ctx, colorButton, "color", getRGB, setRGB, metadata)
    local function BeginColorHistory(self)
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2ColorHistoryTransaction then return end
        if not M.BeginHistoryTransaction then return end
        local label = WidgetHistoryLabel(ctx, self)
        if M.BeginHistoryTransaction(label, WidgetHistorySource(ctx, self, label)) then self._msuf2ColorHistoryTransaction = true end
    end
    local function CommitColorHistory(self)
        if not self._msuf2ColorHistoryTransaction then return end
        self._msuf2ColorHistoryTransaction = nil
        M.CallIf(M.CommitHistoryTransaction)
    end
    colorButton._msuf2BeginColorInteraction = BeginColorHistory
    colorButton._msuf2CommitColorInteraction = CommitColorHistory
    local function RefreshColor()
        if type(getRGB) ~= "function" then return end
        local r, g, b = getRGB()
        colorButton:SetRGB(r or 1, g or 1, b or 1)
    end
    colorButton:SetOnColorChanged(function(r, g, b)
        if BlockCombatAndRefresh(ctx) then
            RefreshColor()
            return
        end
        if type(getRGB) == "function" then
            local cr, cg, cb = getRGB()
            if math.abs((cr or 1) - (r or 1)) < 0.0001
                and math.abs((cg or 1) - (g or 1)) < 0.0001
                and math.abs((cb or 1) - (b or 1)) < 0.0001
            then
                RefreshColor()
                return
            end
        end
        CaptureWidgetChange(ctx, colorButton, nil, function()
            if type(setRGB) == "function" then setRGB(r, g, b) end
        end)
        RefreshColor()
        NotifyGuidedControlInteraction(colorButton)
    end)
    colorButton:HookScript("OnHide", CommitColorHistory)
    M.AddRefresher(ctx, RefreshColor)
end
