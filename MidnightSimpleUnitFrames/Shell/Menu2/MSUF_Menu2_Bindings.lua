local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M
local KS, KSW, WL = M.KeySet, M.KeySetFromWords, M.WordList

-- Menu2 binding/apply layer.
-- Owns DB accessors, pending apply coalescing, edit history snapshots, and fanout into the
-- older MSUF global refresh APIs. Page files bind controls here instead of calling globals
-- directly for every slider/toggle movement.
local pendingUnits = {}
local pendingGeneral
local pendingOpts = {}
local pendingPreview
local pendingAlpha
local pendingCastbar
local flushQueued = false

local HISTORY_LIMIT = 500
local historyDepth = 0
local historyRestoring = false
local historySessionActive = false
local historySessionBaseSnapshot
local historySessionSnapshot
local historySessionDirty = false
local historyTransaction
local refreshQueued = false

local UNIT_KEYS = KS("player", "target", "targettarget", "focustarget", "focus", "pet", "boss")

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

function M.EnsureDB()
    local ensure = _G.MSUF_EnsureDB
    if type(ensure) == "function" then
        pcall(ensure)
    end
    _G.MSUF_DB = _G.MSUF_DB or {}
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

local function CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then
        return pcall(fn, ...)
    end
    return false
end
local function CallGlobalList(names)
    for i = 1, #(names or {}) do CallGlobal(names[i]) end
end
local PROFILE_APPLY_GLOBALS = WL [[
    MSUF_GF_InvalidateCooldownTextCurve MSUF_GF_ForceCooldownTextRecolor MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllFrames MSUF_UpdateAllBarTextures_Immediate
    MSUF_UpdateAllBarTextures MSUF_UpdateCastbarVisuals_Immediate MSUF_ClassPower_Refresh MSUF_ClassPower_RefreshTextures
]]
local RESTORE_GLOBALS = WL [[
    MSUF_UpdateAllFonts_Immediate MSUF_UpdateAllBarTextures_Immediate MSUF_UpdateAllBarTextures
    MSUF_UpdateCastbarVisuals_Immediate MSUF_UpdateCastbarVisuals MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllUnitAlphas MSUF_RefreshAllFrames
]]

local function ApplyUnitFrame(unit)
    -- Keep the modern UF apply path first, then fall back to legacy globals for older modules
    -- that still listen outside the UnitFrames engine.
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        UF.Apply(unit)
        return true
    end
    return false
end

local function RefreshActiveBossPreview(reason)
    local bossPageActive = _G.MSUF2_BossUnitframePreviewActive == true
    local editPreviewActive = _G.MSUF_UnitEditModeActive == true
        and (_G.MSUF_BossTestMode == true or _G.MSUF_PreviewTestMode == true)
    if not bossPageActive and not editPreviewActive then
        return
    end
    if bossPageActive and CallGlobal("MSUF_ApplyBossUnitframePreviewState", true, reason or "MSUF2_BOSS_PREVIEW") then
        return
    end
    CallGlobal("MSUF_SyncBossUnitframePreviewWithUnitEdit")
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
    if M.Refresh then M.Refresh(ctx) end
    return true
end

local function FlushApply()
    flushQueued = false

    local wantPreview = pendingPreview
    pendingPreview = nil

    local wantAlpha = pendingAlpha
    pendingAlpha = nil

    for unit in pairs(pendingUnits) do
        local opt = pendingOpts[unit] or {}
        local notifyUnit = (unit == "boss") and nil or unit
        local applied = false
        if opt.notify ~= false then
            applied = CallGlobal("MSUF_UFCore_NotifyConfigChanged", notifyUnit, true, true, opt.reason or "MSUF2") and true or false
        end
        if opt.text then
            CallGlobal("MSUF_ForceTextLayoutForUnitKey", unit)
        end
        if opt.power then
            if not (_G.InCombatLockdown and _G.InCombatLockdown()) then
                if not CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", unit, true) then
                    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
                end
            end
            if unit == "player" then
                CallGlobal("MSUF_ClassPower_Refresh")
            end
        end
        if not applied then
            ApplyUnitFrame(unit)
        end
    end

    WipeTable(pendingUnits)
    WipeTable(pendingOpts)

    if pendingGeneral then
        local opt = pendingGeneral
        pendingGeneral = nil
        local applied = false
        local applyAll = opt.applyAll ~= false
        if applyAll and opt.notify ~= false then
            applied = CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, opt.reason or "MSUF2_GENERAL") and true or false
        end
        if applyAll and not applied then
            ApplyUnitFrame(nil)
        end
    end
    if pendingCastbar then
        pendingCastbar = nil
        CallGlobal("MSUF_UpdateCastbarVisuals")
    end
    if wantAlpha then
        CallGlobal("MSUF_RefreshAllUnitAlphas")
    end
    if wantPreview then
        CallGlobal("MSUF_UFPreview_RequestRefresh", wantPreview)
        RefreshActiveBossPreview(wantPreview)
    end
end

local function QueueFlush()
    if flushQueued then return end
    flushQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF2_APPLY", FlushApply)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushApply)
    else
        FlushApply()
    end
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

local function SnapshotDB()
    return DeepCopy(M.EnsureDB())
end

local function CurrentHistorySnapshot()
    if historySessionActive and type(historySessionSnapshot) == "table" then
        return historySessionSnapshot
    end
    return SnapshotDB()
end

local function QueueMenuRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local function Run()
        refreshQueued = false
        if M.frame and M.frame.IsShown and M.frame:IsShown() and M.Refresh then
            M.Refresh()
        end
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, Run)
    else
        Run()
    end
end

local function NotifyHistoryChanged(refreshMenu)
    if M.RefreshHistoryControls then pcall(M.RefreshHistoryControls) end
    if M.frame and M.frame.RefreshStatus then pcall(M.frame.RefreshStatus, M.frame) end
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

    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}

    local stack = M.historyUndo
    stack[#stack + 1] = {
        label = label or "MSUF2 change",
        source = source,
        before = before,
        after = after,
    }
    while #stack > HISTORY_LIMIT do
        table.remove(stack, 1)
    end

    WipeTable(M.historyRedo)
    if historySessionActive then
        historySessionSnapshot = after
        historySessionDirty = true
    end
    NotifyHistoryChanged(false)
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

local function ApplyHistorySnapshot(snapshot, reason)
    if type(snapshot) ~= "table" then return false end
    historyRestoring = true
    DeepReplace(M.EnsureDB(), snapshot)
    if historySessionActive then historySessionSnapshot = snapshot end
    historyRestoring = false

    M.RequestGeneralApply(reason or "MSUF2_HISTORY", { preview = true, alpha = true, castbar = true })
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        pcall(MSUF.MSUF_RequestGameplayApply)
    elseif MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(MSUF.MSUF_ApplyGameplayVisuals)
    end
    do
        local db = M.EnsureDB()
        local g = db and db.general
        local ui = type(g) == "table" and type(g.UIScale) == "table" and g.UIScale or nil
        if ui and ui.Enabled == true and type(_G.MSUF_SetGlobalUiScale) == "function" then
            pcall(_G.MSUF_SetGlobalUiScale, tonumber(ui.Scale) or 1, true)
        elseif ui and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            pcall(_G.MSUF_ResetGlobalUiScale, true)
        end
        if M.ApplyMenuFrameScale and M.frame then
            pcall(M.ApplyMenuFrameScale, M.frame)
        elseif M.GetEffectiveMenuScale and M.frame and M.frame.SetScale and type(g) == "table" then
            pcall(M.frame.SetScale, M.frame, M.GetEffectiveMenuScale(g.slashMenuScale))
        end
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        pcall(auras.RequestApply)
    elseif type(_G.MSUF_Auras3_RefreshAll) == "function" then
        pcall(_G.MSUF_Auras3_RefreshAll)
    end
    CallGlobalList(PROFILE_APPLY_GLOBALS)
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, "MSUF2_PROFILE_APPLY")
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RebuildAll) == "function" then pcall(MSUF.GF.RebuildAll) end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then pcall(MSUF.GF.RefreshPreviewLayout) end
        if type(MSUF.GF.RefreshVisuals) == "function" then pcall(MSUF.GF.RefreshVisuals) end
    end
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    if M.MarkMenuDataDirty then M.MarkMenuDataDirty(reason or "history") end
    RebuildActivePage()
    return true
end

function M.IsHistoryCapturing()
    return historyDepth > 0 or historyRestoring
end

function M.CaptureHistory(label, source, fn)
    if type(fn) ~= "function" then return nil end
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring then
        local result = fn()
        if result ~= false and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
        return result
    end

    local before = CurrentHistorySnapshot()
    historyDepth = historyDepth + 1
    local ok, result = pcall(fn)
    historyDepth = historyDepth - 1
    if not ok then
        CommandFeedback("Action failed", "danger", 1.8)
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then handler(result) else print(result) end
        return nil
    end
    if result == false then return result end
    local pushed = PushHistory(label, source, before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return result
end

function M.StartHistorySession()
    if IsConfigCombatLocked() then return false end
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionActive = true
    historySessionBaseSnapshot = SnapshotDB()
    historySessionSnapshot = historySessionBaseSnapshot
    historySessionDirty = false
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    WipeTable(M.historyUndo)
    WipeTable(M.historyRedo)
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
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    WipeTable(M.historyUndo)
    WipeTable(M.historyRedo)
    if historySessionActive then
        historySessionBaseSnapshot = SnapshotDB()
        historySessionSnapshot = historySessionBaseSnapshot
        historySessionDirty = false
    end
    NotifyHistoryChanged()
end

function M.GetHistoryState()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local undo = M.historyUndo[#M.historyUndo]
    local redo = M.historyRedo[#M.historyRedo]
    return {
        canUndo = undo ~= nil,
        canRedo = redo ~= nil,
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and historySessionDirty,
        undoLabel = undo and undo.label or nil,
        redoLabel = redo and redo.label or nil,
        undoCount = #M.historyUndo,
        redoCount = #M.historyRedo,
    }
end

function M.Undo()
    if M.BlockCombatAction() then return false end
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyUndo)
    if not entry then return false end
    M.historyRedo[#M.historyRedo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.before, "MSUF2_HISTORY_UNDO")
    if ok and historySessionActive then historySessionDirty = #M.historyUndo > 0 end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Undid " .. FeedbackLabel(entry.label), "info", 1.25) end
    return ok
end

function M.Redo()
    if M.BlockCombatAction() then return false end
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyRedo)
    if not entry then return false end
    M.historyUndo[#M.historyUndo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.after, "MSUF2_HISTORY_REDO")
    if ok and historySessionActive then historySessionDirty = true end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Redid " .. FeedbackLabel(entry.label), "info", 1.25) end
    return ok
end

local function WidgetHistoryLabel(ctx, widget, fallback)
    local fs = widget and (widget._msuf2Title or widget._msuf2Label)
    if fs and fs.GetText then
        local text = fs:GetText()
        if text and text ~= "" then return text end
    end
    if widget and widget.GetText then
        local ok, text = pcall(widget.GetText, widget)
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
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then return end
    M.CheckpointHistory(reason or ("MSUF2_" .. tostring(unit)), "apply:unit:" .. tostring(unit) .. ":" .. tostring(reason or "change"))
    pendingUnits[unit] = true
    local o = pendingOpts[unit]
    if not o then
        o = {}
        pendingOpts[unit] = o
    end
    o.reason = reason or o.reason or "MSUF2"
    if opts then
        if opts.text then o.text = true end
        if opts.power then o.power = true end
        if opts.castbar then pendingCastbar = true end
        if opts.notify == false then o.notify = false end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2" end
        if opts.alpha then pendingAlpha = true end
    else
        pendingPreview = reason or "MSUF2"
    end
    QueueFlush()
end

function M.SetUnitValue(unit, key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "unit:" .. tostring(unit) .. ":" .. tostring(key), function()
            return M.SetUnitValue(unit, key, value, reason, opts)
        end)
    end
    local conf = M.GetUnitDB(unit)
    if conf[key] == value then return false end
    conf[key] = value
    M.RequestUnitApply(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

function M.RequestGeneralApply(reason, opts)
    if M.BlockCombatAction() then return false end
    M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    if not pendingGeneral then pendingGeneral = {} end
    pendingGeneral.reason = reason or pendingGeneral.reason or "MSUF2_GENERAL"
    if opts and opts.applyAll == false then
        if pendingGeneral.applyAll == nil then pendingGeneral.applyAll = false end
    else
        pendingGeneral.applyAll = true
    end
    if opts and opts.notify == false then pendingGeneral.notify = false end
    if opts then
        if opts.castbar then pendingCastbar = true end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2_GENERAL" end
        if opts.alpha then pendingAlpha = true end
    else
        pendingPreview = reason or "MSUF2_GENERAL"
    end
    QueueFlush()
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
    if key == "menuLocale" and M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
    M.RequestGeneralApply(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

local UNIT_PAGE_RESETS = {
    uf_player = { unit = "player", label = "Player" },
    uf_target = { unit = "target", label = "Target" },
    uf_targettarget = { unit = "targettarget", label = "Target of Target" },
    uf_focustarget = { unit = "focustarget", label = "Focus Target" },
    uf_focus = { unit = "focus", label = "Focus" },
    uf_boss = { unit = "boss", label = "Boss Frames" },
    uf_pet = { unit = "pet", label = "Pet" },
}

local UNIT_CASTBAR_GENERAL_KEYS = {
    player = WL("enablePlayerCastbar castbarPlayerBackend castbarPlayerBackendBeforeHide showPlayerCastTime castbarPlayerShowIcon castbarPlayerShowSpellName castbarPlayerTimeFormat castbarPlayerIconPosition castbarPlayerIconSize castbarPlayerIconOffsetX castbarPlayerIconOffsetY castbarPlayerIconSpacing castbarPlayerIconBorderStyle castbarPlayerSpellNamePosition castbarPlayerSpellNameFontSize castbarPlayerTextOffsetX castbarPlayerTextOffsetY castbarPlayerSpellNameAlign castbarPlayerSpellNameMaxWidth castbarPlayerSpellNameTruncate castbarPlayerTimePosition castbarPlayerTimeFontSize castbarPlayerTimeOffsetX castbarPlayerTimeOffsetY"),
    target = WL("enableTargetCastbar castbarTargetBackend castbarTargetBackendBeforeHide showTargetCastTime castbarTargetShowIcon castbarTargetShowSpellName castbarTargetTimeFormat castbarTargetIconPosition castbarTargetIconSize castbarTargetIconOffsetX castbarTargetIconOffsetY castbarTargetIconSpacing castbarTargetIconBorderStyle castbarTargetSpellNamePosition castbarTargetSpellNameFontSize castbarTargetTextOffsetX castbarTargetTextOffsetY castbarTargetSpellNameAlign castbarTargetSpellNameMaxWidth castbarTargetSpellNameTruncate castbarTargetTimePosition castbarTargetTimeFontSize castbarTargetTimeOffsetX castbarTargetTimeOffsetY"),
    focus = WL("enableFocusCastbar castbarFocusBackend castbarFocusBackendBeforeHide showFocusCastTime castbarFocusShowIcon castbarFocusShowSpellName castbarFocusTimeFormat castbarFocusIconPosition castbarFocusIconSize castbarFocusIconOffsetX castbarFocusIconOffsetY castbarFocusIconSpacing castbarFocusIconBorderStyle castbarFocusSpellNamePosition castbarFocusSpellNameFontSize castbarFocusTextOffsetX castbarFocusTextOffsetY castbarFocusSpellNameAlign castbarFocusSpellNameMaxWidth castbarFocusSpellNameTruncate castbarFocusTimePosition castbarFocusTimeFontSize castbarFocusTimeOffsetX castbarFocusTimeOffsetY"),
    boss = WL("enableBossCastbar bossCastbarBackend bossCastbarBackendBeforeHide showBossCastTime showBossCastIcon showBossCastName bossCastTimeFormat bossCastIconPosition bossCastIconSize bossCastIconOffsetX bossCastIconOffsetY bossCastIconSpacing bossCastIconBorderStyle bossCastSpellNamePosition bossCastSpellNameFontSize bossCastTextOffsetX bossCastTextOffsetY bossCastSpellNameAlign bossCastSpellNameMaxWidth bossCastSpellNameTruncate bossCastTimePosition bossCastTimeFontSize bossCastTimeOffsetX bossCastTimeOffsetY"),
}

local function ResetInfo(label, kind, summary)
    return { label = label, kind = kind, summary = summary }
end

local GROUP_RESET_INFO = ResetInfo("Group Frames", "group", "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions")
local AURA_STYLE_SUMMARY = "scope-aware Buff and Debuff text, cooldown and stack styling"

local PAGE_RESET_INFO = {
    gf_layout = GROUP_RESET_INFO,
    gf_bars = GROUP_RESET_INFO,
    gf_auras = GROUP_RESET_INFO,
    gf_indicators = GROUP_RESET_INFO,
    opt_bars = ResetInfo("Bars", "bars", "shared bar textures, gradients, rounded frame corners, absorb display, outlines, highlight borders, power smoothing and all per-unit/group bar overrides"),
    opt_fonts = ResetInfo("Fonts", "fonts", "shared font family, text style, name/power text coloring, name shortening and all per-unit/group font overrides"),
    auras3 = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    auras3_buffs = ResetInfo("Aura Buffs", "auras", "Buff text, cooldown and stack styling"),
    auras3_debuffs = ResetInfo("Aura Debuffs", "auras", "Debuff text, cooldown and stack styling"),
    auras3_rendering = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    auras3_filters = ResetInfo("Aura Filters", "auras", "scope-aware Buff and Debuff filters and blacklists"),
    auras3_styling = ResetInfo("Aura Style", "auras", AURA_STYLE_SUMMARY),
    opt_castbar = ResetInfo("Castbar", "castbar", "global castbar behavior, textures, boss castbar and interrupt indicator settings"),
    opt_colors = ResetInfo("Colors", "colors", "frame colors, class/NPC colors, power colors, castbar colors, aura colors and gameplay color settings"),
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
    absorbBarTexture healAbsorbBarTexture dispelBorderTrigger unitDispelOverlayEnabled unitDispelOverlayStyle
    unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger bossTargetOutlineMode
    bossTargetHighlightEnabled highlightPrioEnabled highlightPrioOrder roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedMouseover barOutlineColorR barOutlineColorG
    barOutlineColorB barOutlineColorA
]]

local BARS_SCOPE_KEYS = KSW [[
    hlOverride hpPowerTextOverride barTexture barBackgroundTexture barBgTexture absorbTextMode absorbAnchorMode healPredEnabled healPredAnchorMode
    absorbBarOpacity healAbsorbBarOpacity barOutlineThickness highlightBorderThickness hlAggroSize
    aggroOutlineMode dispelOutlineMode dispelBorderTrigger unitDispelOverlayEnabled unitDispelOverlayStyle
    unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger
    purgeOutlineMode hlPrioEnabled hlPrioOrder enableGradient enablePowerGradient gradientStrength
    gradientDirection gradientDirRight gradientDirLeft gradientDirUp gradientDirDown powerSmoothFill
    barOutlineColorR barOutlineColorG barOutlineColorB barOutlineColorA
]]

local BARS_TABLE_KEYS = KSW [[
    barOutlineThickness smoothPowerBar realtimePowerText roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedMouseover
]]

local FONT_GENERAL_KEYS = KS("fontKey", "boldText", "noOutline", "textBackdrop", "fontMonochrome", "fontShadowStrength", "fontTextAlpha", "fontBaselineOffset", "nameClassColor", "npcNameRed", "nameNpcClassColor", "colorPowerTextByType", "colorHealthTextByHealth")

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
    showMinimapIcon playTargetSelectLostSounds
]]

local MISC_UNIT_KEYS = {}
local MISC_UNIT_RESET_KEYS = WL [[target focus boss]]

local CASTBAR_GENERAL_KEYS = KSW [[
    empowerColorStages enableFocusKickIcon focusKickIconWidth focusKickIconHeight focusKickTextSize
    focusKickIconOffsetX focusKickIconOffsetY kickReadyShowTarget kickReadyShowFocus kickReadyShowBoss
    kickReadyStyle kickReadySize kickReadyAutoSize kickReadyAnchor kickReadyOffsetX kickReadyOffsetY
]]

local MODULES_GENERAL_KEYS = KS("styleEnabled")

local COLOR_GENERAL_KEYS = KS(
    "highlightEnabled", "playerCastbarOverrideEnabled", "playerCastbarOverrideMode",
    "npcTypeTarget", "npcTypeFocus", "npcTypeBoss", "npcTypeToT")

local COLOR_GAMEPLAY_KEYS = KS("combatStateColorSync")

local COLOR_BARS_KEYS = KS("classPowerComboPointColorMode")

local AURAS_GENERAL_PREFIXES = {
    "auras",
}

local AURAS_SHARED_COLOR_KEYS = KS("pandemicR", "pandemicG", "pandemicB")

local function StartsWith(value, prefix)
    return type(value) == "string" and type(prefix) == "string" and value:sub(1, #prefix) == prefix
end

local function AnyPrefix(key, prefixes)
    if type(key) ~= "string" then return false end
    for i = 1, #(prefixes or {}) do
        if StartsWith(key, prefixes[i]) then return true end
    end
    return false
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
        if filter(key) then
            dst[key] = nil
        end
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if filter(key) then
            dst[key] = DeepCopy(value)
        end
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
    if type(db) == "table" and type(db.targettarget) == "table" then
        db.tot = db.targettarget
    end
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

local function IsBarsGeneralKey(key)
    return BARS_GENERAL_KEYS[key] == true or BARS_SCOPE_KEYS[key] == true
end

local function IsBarsScopeKey(key)
    return BARS_SCOPE_KEYS[key] == true
end

local function IsFontScopeKey(key)
    return FONT_SCOPE_KEYS[key] == true
end

local function IsGameplayColorKey(key)
    return COLOR_GAMEPLAY_KEYS[key] == true or IsColorKey(key)
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
    local ok, defaults = pcall(create)
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
        return gf.ResetAllToDefaults()
    end
    ReplaceRootTable(db, defaults, "gf_party")
    ReplaceRootTable(db, defaults, "gf_raid")
    ReplaceRootTable(db, defaults, "gf_mythicraid")
    return true
end

local function ResetBarsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", IsBarsGeneralKey)
    ResetRootFiltered(db, defaults, "bars", function(key) return BARS_TABLE_KEYS[key] == true end)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, IsBarsScopeKey)
    end
    EnsureTargetTargetAlias(db)
end

local function ResetFontsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return FONT_GENERAL_KEYS[key] == true end)
    ResetKeySet(db, defaults, FONT_ROOT_KEYS)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, IsFontScopeKey)
    end
    EnsureTargetTargetAlias(db)
end

local function ResetAurasPage(db, defaults)
    ReplaceRootTable(db, defaults, "auras3")
    ResetRootFiltered(db, defaults, "general", function(key) return AnyPrefix(key, AURAS_GENERAL_PREFIXES) end)
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
    ResetRootFiltered(db, defaults, "gameplay", IsGameplayColorKey)
    ResetRootFiltered(db, defaults, "bars", function(key) return COLOR_BARS_KEYS[key] == true end)
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

local function ApplyAfterPageReset(pageKey, info)
    local reason = "MSUF2_RESET_" .. tostring(pageKey or "PAGE")
    if info and info.unit and M.RequestUnitApply then
        M.RequestUnitApply(info.unit, reason, { preview = true, text = true, power = true, alpha = true, castbar = true })
    end
    if M.RequestGeneralApply then
        M.RequestGeneralApply(reason, { preview = true, alpha = true, castbar = true })
    end

    if info and info.kind == "gameplay" then
        if M.ApplyGameplay then M.ApplyGameplay() end
    end

    local auras = MSUF and MSUF.MSUF_Auras3
    if info and (info.kind == "auras" or info.kind == "colors") then
        if auras and type(auras.RequestApply) == "function" then
            pcall(auras.RequestApply)
        elseif type(_G.MSUF_Auras3_RefreshAll) == "function" then
            pcall(_G.MSUF_Auras3_RefreshAll)
        end
    end

    if info and (info.kind == "group" or info.kind == "bars" or info.kind == "fonts" or info.kind == "colors") then
        local gf = MSUF and MSUF.GF
        if gf then
            if type(gf.InvalidateConfCache) == "function" then pcall(gf.InvalidateConfCache) end
            if type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
            if type(gf.RebuildAll) == "function" then pcall(gf.RebuildAll) end
            if type(gf.RequestAuraRefresh) == "function" then pcall(gf.RequestAuraRefresh) end
        end
    end

    if info and info.kind == "classpower" then
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
        CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    end

    if info and info.kind == "modules" then
        CallGlobal("MSUF_ApplyModules")
    end

    CallGlobalList(RESTORE_GLOBALS)
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, "MSUF2_RESTORE")

    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    if M.ApplyMenuFrameScale and M.frame then pcall(M.ApplyMenuFrameScale, M.frame) end

    if pageKey and M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(pageKey)
        M.activeKey = nil
        M.SelectPage(pageKey)
    else
        QueueMenuRefresh()
    end
end

local function ResetProfilePage()
    local name = _G.MSUF_ActiveProfile or "Default"
    if type(_G.MSUF_ResetProfile) ~= "function" then return false end
    pcall(_G.MSUF_ResetProfile, name)
    if M.ClearHistory then M.ClearHistory() end
    ApplyAfterPageReset("profiles", PAGE_RESET_INFO.profiles)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
        _G.MSUF_ShowReloadRecommendedPopup("Profile reset")
    end
    return true
end

local function ResetPageImpl(pageKey)
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return false end
    if info.kind == "profile" then
        return ResetProfilePage()
    end

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

function M.GetPageResetInfo(pageKey)
    return PAGE_RESET_INFO[pageKey or ""]
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
    if info.kind == "profile" then
        return ResetPageImpl(pageKey)
    end
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
        return M.CaptureHistory("Reset " .. tostring(info.label or pageKey), "page:reset:" .. tostring(pageKey), function()
            return ResetPageImpl(pageKey)
        end)
    end
    return ResetPageImpl(pageKey)
end

function M.ShowPageResetConfirm(pageKey)
    if M.BlockCombatAction() then return false end
    if not M.PageHasReset(pageKey) then return false end
    local message = M.BuildPageResetWarning(pageKey)
    if not message then return false end
    if not _G.StaticPopupDialogs then
        return M.ResetPageToDefaults(pageKey)
    end
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
        if type(fn) == "function" then pcall(fn) end
    end
end

function M.RequestRefresh(ctx, reason)
    if M.MarkMenuDataDirty then M.MarkMenuDataDirty(reason or "request-refresh") end

    local entry = ResolveRefreshEntry(ctx)
    if entry then
        if entry._msuf2RefreshQueued then return true end
        entry._msuf2RefreshQueued = true
        local function Run()
            entry._msuf2RefreshQueued = nil
            if entry._msuf2Invalidated then return end
            if M.RunEntryRefreshers then
                M.RunEntryRefreshers(entry)
            else
                RunRefreshList(entry.refreshers)
            end
        end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, Run) else Run() end
        return true
    end

    if M._msuf2RefreshQueued then return true end
    M._msuf2RefreshQueued = true
    local function Run()
        M._msuf2RefreshQueued = nil
        local active = ResolveRefreshEntry()
        if active then
            if M.RunEntryRefreshers then M.RunEntryRefreshers(active) else RunRefreshList(active.refreshers) end
        end
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, Run) else Run() end
    return true
end

function M.Refresh(ctx)
    if M.MarkMenuDataDirty then M.MarkMenuDataDirty("refresh") end
    local entry = ResolveRefreshEntry(ctx)
    if entry and M.RunEntryRefreshers then
        M.RunEntryRefreshers(entry, { force = true })
        return
    end
    local refreshers = ctx and ctx.refreshers
    if not refreshers then refreshers = entry and entry.refreshers end
    RunRefreshList(refreshers)
end

local function MarkCommandSearchDirty()
    if M.SearchBridge and type(M.SearchBridge.MarkSearchIndexDirty) == "function" then
        M.SearchBridge.MarkSearchIndexDirty()
    elseif M.Search and type(M.Search.MarkIndexDirty) == "function" then
        M.Search.MarkIndexDirty()
    end
end

local function AttachCommandAction(ctx, widget, kind, getValue, setValue, opts)
    if not widget then return end
    opts = opts or {}
    local minValue, maxValue
    if kind == "slider" and widget.GetMinMaxValues then
        minValue, maxValue = widget:GetMinMaxValues()
    end
    widget._msuf2CommandAction = {
        kind = kind,
        ctxKey = ctx and ctx.key,
        get = getValue,
        set = setValue,
        values = opts.values or widget.values,
        getValues = function()
            return widget.values
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
            if M.RequestRefresh then M.RequestRefresh(ctx, "command-refresh") elseif M.Refresh then M.Refresh(ctx) end
        end,
        blockCombat = function()
            return BlockCombatAndRefresh(ctx)
        end,
    }
    MarkCommandSearchDirty()
end

function M.BindToggle(ctx, widget, getValue, setValue)
    if not widget then return end
    AttachCommandAction(ctx, widget, "toggle", getValue, setValue)
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
        local nativeValue = self.GetChecked and self:GetChecked()
        local nextValue = nativeValue ~= nil and (nativeValue and true or false) or not currentValue
        if nextValue == currentValue then
            SyncFromValue(self)
            return
        end
        CaptureWidgetChange(ctx, self, nil, function()
            setValue(nextValue)
        end)
        SyncFromValue(self)
    end)
    M.AddRefresher(ctx, function()
        SyncFromValue(widget)
    end)
end

function M.BindSlider(ctx, slider, getValue, setValue)
    if not slider then return end
    local minValue, maxValue
    if slider.GetMinMaxValues then minValue, maxValue = slider:GetMinMaxValues() end
    AttachCommandAction(ctx, slider, "slider", getValue, setValue, {
        min = minValue,
        max = maxValue,
        step = slider._msuf2Step,
    })
    local function BeginSliderHistory(self)
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Refreshing or self._msuf2HistoryTransaction then return end
        if not M.BeginHistoryTransaction then return end
        local label = WidgetHistoryLabel(ctx, self)
        if M.BeginHistoryTransaction(label, WidgetHistorySource(ctx, self, label)) then
            self._msuf2HistoryTransaction = true
        end
    end
    local function CommitSliderHistory(self)
        if not self._msuf2HistoryTransaction then return end
        self._msuf2HistoryTransaction = nil
        if M.CommitHistoryTransaction then M.CommitHistoryTransaction() end
    end
    slider._msuf2BeginSliderHistory = BeginSliderHistory
    slider._msuf2CommitSliderHistory = CommitSliderHistory
    slider:HookScript("OnMouseDown", BeginSliderHistory)
    slider:HookScript("OnMouseUp", CommitSliderHistory)
    slider:HookScript("OnHide", CommitSliderHistory)
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Step and self._msuf2Step >= 1 then
            value = math.floor(value + 0.5)
        end
        local current = tonumber(getValue()) or 0
        if math.abs(current - value) < 0.0001 then return end
        CaptureWidgetChange(ctx, self, nil, function()
            setValue(value)
        end)
    end)
    M.AddRefresher(ctx, function()
        local value = tonumber(getValue()) or 0
        local current = slider.GetValue and tonumber(slider:GetValue()) or nil
        if current ~= nil and math.abs(current - value) < 0.0001 then
            if slider.editBox and slider._msuf2FormatValue and not slider._msuf2Editing then
                slider.editBox:SetText(slider._msuf2FormatValue(value))
            end
            if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
            return
        end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then
            slider.editBox:SetText(slider._msuf2FormatValue(value))
        end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end)
end

function M.BindSegment(ctx, segment, getValue, setValue)
    if not segment then return end
    AttachCommandAction(ctx, segment, "segment", getValue, setValue, { values = segment.values })
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
        end)
    end
    M.AddRefresher(ctx, function()
        segment:SetValue(getValue())
    end)
end

function M.BindDropdown(ctx, dropdown, getValue, setValue)
    if not dropdown then return end
    AttachCommandAction(ctx, dropdown, "dropdown", getValue, setValue, { values = dropdown.values })
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
    end)
    M.AddRefresher(ctx, function()
        dropdown:SetValue(getValue())
    end)
end

function M.BindTextInput(ctx, editBox, getValue, setValue, commitOnBlur)
    if not editBox then return end
    AttachCommandAction(ctx, editBox, "textinput", getValue, setValue)
    editBox._msuf2CommitOnBlur = commitOnBlur and true or false
    editBox:SetOnValueCommitted(function(value)
        if BlockCombatAndRefresh(ctx) then return end
        if tostring(getValue() or "") == tostring(value or "") then return end
        CaptureWidgetChange(ctx, editBox, nil, function()
            setValue(value or "")
        end)
    end)
    M.AddRefresher(ctx, function()
        if editBox:HasFocus() then return end
        editBox:SetText(tostring(getValue() or ""))
    end)
end

function M.BindColor(ctx, colorButton, getRGB, setRGB)
    if not colorButton then return end
    AttachCommandAction(ctx, colorButton, "color", getRGB, setRGB)
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
    end)
    M.AddRefresher(ctx, RefreshColor)
end
