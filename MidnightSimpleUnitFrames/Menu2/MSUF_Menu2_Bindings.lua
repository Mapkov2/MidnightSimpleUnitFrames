local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

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
local historyTransaction

local UNIT_KEYS = {
    player = true,
    target = true,
    targettarget = true,
    focus = true,
    pet = true,
    boss = true,
}

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

function M.EnsureDB()
    if type(_G.EnsureDB) == "function" then
        pcall(_G.EnsureDB)
    end
    _G.MSUF_DB = _G.MSUF_DB or {}
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    return _G.MSUF_DB
end

function M.GetUnitDB(unit)
    local db = M.EnsureDB()
    unit = (unit == "tot") and "targettarget" or unit
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

local function FlushApply()
    flushQueued = false

    local wantPreview = pendingPreview
    pendingPreview = nil

    local wantAlpha = pendingAlpha
    pendingAlpha = nil

    for unit in pairs(pendingUnits) do
        local opt = pendingOpts[unit] or {}
        local notifyUnit = (unit == "boss") and nil or unit
        if opt.notify ~= false then
            CallGlobal("MSUF_UFCore_NotifyConfigChanged", notifyUnit, true, true, opt.reason or "MSUF2")
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
        if not CallGlobal("ApplySettingsForKey", unit) then
            CallGlobal("MSUF_ApplySettingsForKey_Immediate", unit)
        end
    end

    WipeTable(pendingUnits)
    WipeTable(pendingOpts)

    if pendingGeneral then
        local opt = pendingGeneral
        pendingGeneral = nil
        if opt.notify ~= false then
            CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, opt.reason or "MSUF2_GENERAL")
        end
        if opt.applyAll ~= false then
            if not CallGlobal("ApplyAllSettings") then
                CallGlobal("MSUF_ApplyAllSettings_Immediate")
            end
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

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return out
end

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

local function NotifyHistoryChanged()
    if M.RefreshHistoryControls then pcall(M.RefreshHistoryControls) end
    if M.frame and M.frame.RefreshStatus then pcall(M.frame.RefreshStatus, M.frame) end
    if M.Refresh then M.Refresh() end
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
    if historySessionActive then historySessionSnapshot = after end
    NotifyHistoryChanged()
    return true
end

local function RebuildActivePage()
    local key = M.activeKey
    if key and M.frame and M.frame.IsShown and M.frame:IsShown() and M.InvalidatePage and M.SelectPage then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    else
        NotifyHistoryChanged()
    end
end

local function ApplyHistorySnapshot(snapshot, reason)
    if type(snapshot) ~= "table" then return false end
    historyRestoring = true
    DeepReplace(M.EnsureDB(), snapshot)
    if historySessionActive then historySessionSnapshot = SnapshotDB() end
    historyRestoring = false

    M.RequestGeneralApply(reason or "MSUF2_HISTORY", { preview = true, alpha = true, castbar = true })
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
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
    local auras = ns and ns.MSUF_Auras2
    if auras and type(auras.RequestApply) == "function" then
        pcall(auras.RequestApply)
    elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
        pcall(_G.MSUF_Auras2_RefreshAll)
    end
    CallGlobal("MSUF_A2_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_A2_ForceCooldownTextRecolor")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_PortraitDecoration_RefreshAll")
    if ns and ns.GF then
        if type(ns.GF.RebuildAll) == "function" then pcall(ns.GF.RebuildAll) end
        if type(ns.GF.RefreshPreviewLayout) == "function" then pcall(ns.GF.RefreshPreviewLayout) end
        if type(ns.GF.RefreshVisuals) == "function" then pcall(ns.GF.RefreshVisuals) end
    end
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    if historySessionActive then historySessionSnapshot = SnapshotDB() end
    RebuildActivePage()
    return true
end

function M.IsHistoryCapturing()
    return historyDepth > 0 or historyRestoring
end

function M.CaptureHistory(label, source, fn)
    if type(fn) ~= "function" then return nil end
    if historyDepth > 0 or historyRestoring then return fn() end

    local before = SnapshotDB()
    historyDepth = historyDepth + 1
    local ok, result = pcall(fn)
    historyDepth = historyDepth - 1
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then handler(result) else print(result) end
        return nil
    end
    PushHistory(label, source, before, SnapshotDB())
    return result
end

function M.StartHistorySession()
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionActive = true
    historySessionBaseSnapshot = SnapshotDB()
    historySessionSnapshot = DeepCopy(historySessionBaseSnapshot)
    M.ClearHistory()
end

function M.EndHistorySession()
    historySessionActive = false
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionBaseSnapshot = nil
    historySessionSnapshot = nil
end

function M.CheckpointHistory(label, source)
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    local before = historySessionSnapshot or SnapshotDB()
    local after = SnapshotDB()
    return PushHistory(label or "MSUF2 change", source or "menu:checkpoint", before, after)
end

function M.BeginHistoryTransaction(label, source)
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    historyTransaction = {
        label = label or "MSUF2 change",
        source = source or "menu:transaction",
        before = SnapshotDB(),
    }
    historyDepth = historyDepth + 1
    return true
end

function M.CommitHistoryTransaction()
    local tx = historyTransaction
    if not tx then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    return PushHistory(tx.label, tx.source, tx.before, SnapshotDB())
end

function M.CancelHistoryTransaction()
    if not historyTransaction then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    NotifyHistoryChanged()
    return true
end

function M.ResetHistorySession()
    if not historySessionActive or type(historySessionBaseSnapshot) ~= "table" then return false end
    local ok = ApplyHistorySnapshot(historySessionBaseSnapshot, "MSUF2_HISTORY_RESET_SESSION")
    if ok then M.ClearHistory() end
    return ok
end

function M.ClearHistory()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    WipeTable(M.historyUndo)
    WipeTable(M.historyRedo)
    if historySessionActive then
        historySessionBaseSnapshot = SnapshotDB()
        historySessionSnapshot = DeepCopy(historySessionBaseSnapshot)
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
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and not DeepEqual(historySessionBaseSnapshot, M.EnsureDB()),
        undoLabel = undo and undo.label or nil,
        redoLabel = redo and redo.label or nil,
        undoCount = #M.historyUndo,
        redoCount = #M.historyRedo,
    }
end

function M.Undo()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyUndo)
    if not entry then return false end
    M.historyRedo[#M.historyRedo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.before, "MSUF2_HISTORY_UNDO")
    NotifyHistoryChanged()
    return ok
end

function M.Redo()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyRedo)
    if not entry then return false end
    M.historyUndo[#M.historyUndo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.after, "MSUF2_HISTORY_REDO")
    NotifyHistoryChanged()
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

function M.RequestUnitApply(unit, reason, opts)
    unit = (unit == "tot") and "targettarget" or unit
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

function M.AddRefresher(ctx, fn)
    if not (ctx and type(fn) == "function") then return end
    ctx.refreshers[#ctx.refreshers + 1] = fn
end

function M.Refresh(ctx)
    local refreshers = ctx and ctx.refreshers
    if not refreshers then
        local entry = M.activeKey and M.cache and M.cache[M.activeKey]
        refreshers = entry and entry.refreshers
    end
    if not refreshers then return end
    for i = 1, #refreshers do
        local fn = refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

function M.BindToggle(ctx, widget, getValue, setValue)
    if not widget then return end
    widget:SetScript("OnClick", function(self)
        local nextValue = not (getValue() and true or false)
        local label = WidgetHistoryLabel(ctx, self)
        M.CaptureHistory(label, WidgetHistorySource(ctx, self, label), function()
            setValue(nextValue)
        end)
        self:SetChecked(nextValue)
    end)
    M.AddRefresher(ctx, function()
        widget:SetChecked(getValue() and true or false)
    end)
end

function M.BindSlider(ctx, slider, getValue, setValue)
    if not slider then return end
    local function BeginSliderHistory(self)
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
    slider:HookScript("OnMouseDown", BeginSliderHistory)
    slider:HookScript("OnMouseUp", CommitSliderHistory)
    slider:HookScript("OnHide", CommitSliderHistory)
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if self._msuf2Step and self._msuf2Step >= 1 then
            value = math.floor(value + 0.5)
        end
        local label = WidgetHistoryLabel(ctx, self)
        M.CaptureHistory(label, WidgetHistorySource(ctx, self, label), function()
            setValue(value)
        end)
    end)
    M.AddRefresher(ctx, function()
        local value = tonumber(getValue()) or 0
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
    for i = 1, #(segment.buttons or {}) do
        local btn = segment.buttons[i]
        btn:SetScript("OnClick", function(self)
            local label = WidgetHistoryLabel(ctx, segment)
            M.CaptureHistory(label, WidgetHistorySource(ctx, segment, label), function()
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
    dropdown:SetOnValueChanged(function(value)
        local label = WidgetHistoryLabel(ctx, dropdown)
        M.CaptureHistory(label, WidgetHistorySource(ctx, dropdown, label), function()
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
    editBox._msuf2CommitOnBlur = commitOnBlur and true or false
    editBox:SetOnValueCommitted(function(value)
        local label = WidgetHistoryLabel(ctx, editBox)
        M.CaptureHistory(label, WidgetHistorySource(ctx, editBox, label), function()
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
    local function RefreshColor()
        if type(getRGB) ~= "function" then return end
        local r, g, b = getRGB()
        colorButton:SetRGB(r or 1, g or 1, b or 1)
    end
    colorButton:SetOnColorChanged(function(r, g, b)
        local label = WidgetHistoryLabel(ctx, colorButton)
        M.CaptureHistory(label, WidgetHistorySource(ctx, colorButton, label), function()
            if type(setRGB) == "function" then setRGB(r, g, b) end
        end)
        RefreshColor()
    end)
    M.AddRefresher(ctx, RefreshColor)
end
