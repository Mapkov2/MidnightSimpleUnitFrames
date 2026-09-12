local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local KS = M.KeySet
local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
if type(ApplyService) ~= "table" then error("MSUF Menu2 ApplyService missing") end


local CLASSPOWER_FULL_RUNTIME = { full = true, cdm = true }
-- The History and Reset siblings (MSUF_Menu2_Bindings_History.lua and
-- MSUF_Menu2_Bindings_Reset.lua) load right after this file and pick the
-- shared values published on M below instead of re-declaring them.
M.CLASSPOWER_FULL_RUNTIME = CLASSPOWER_FULL_RUNTIME

function M.ApplyPlayerPowerSource(reason)
    reason = reason or "MSUF2_PLAYER_POWER_SOURCE"
    _G.MSUF_ApplyModules()
    _G.MSUF_ClassPower_Apply(CLASSPOWER_FULL_RUNTIME)
    _G.MSUF_UFPreview_RequestRefresh(reason)
    local preview = M._msuf2ClassPowerInlinePreview
    if preview and type(preview.Refresh) == "function" then preview.Refresh(preview) end
    return true
end

-- Menu2 binding/apply layer.
-- Owns DB accessors, pending apply coalescing, the page refreshers and the Bind*
-- family that page files use instead of calling globals directly for every
-- slider/toggle movement. Edit history (snapshots, undo/redo, transactions and
-- the SetUnitValue/SetGeneralValue write helpers) lives in
-- MSUF_Menu2_Bindings_History.lua and the page "Reset to defaults" logic in
-- MSUF_Menu2_Bindings_Reset.lua; both load right after this file and publish
-- through the same M table.
local refreshQueued = false
local refreshTimer
local MENU_REFRESH_DELAY = 0.04
local C_Timer = M.MenuTimer or _G.C_Timer
local UNIT_KEYS = KS("player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena")
M.UNIT_KEYS = UNIT_KEYS
local TEXT_SLOT_SIDES = { "Left", "Center", "Right" }
local TEXT_SLOT_SIDE_SET = { Left = true, Center = true, Right = true }
local DIRECT_TEXT_GROUP_ORDER = { "name", "hp", "power" }
local DIRECT_TEXT_GROUPS = {
    name = { single = true, basePrefix = "name", baseAliasPrefix = "nameText", directPrefix = "directName", defaultX = 4, defaultY = -4 },
    hp = { basePrefix = "hp", baseAliasPrefix = "hpText", directPrefix = "directHealth", slotPrefix = "hpText", legacySlotPrefix = "hp", defaultX = -4, defaultY = -4 },
    power = { basePrefix = "power", baseAliasPrefix = "powerText", directPrefix = "directPower", slotPrefix = "powerText", legacySlotPrefix = "power", defaultX = -4, defaultY = 4 },
}

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
M.ProfileSystemNeedsInit = ProfileSystemNeedsInit
local lastEnsuredDB
function M.EnsureDB()
    -- Fast path: the exact table we last ensured and exported is still the
    -- active DB. A profile switch or import replaces _G.MSUF_DB, which breaks
    -- the identity check and re-runs the full ensure/export sequence below.
    local db = _G.MSUF_DB
    if db ~= nil and db == lastEnsuredDB and type(db.general) == "table" and not ProfileSystemNeedsInit() then
        return db
    end
    if ProfileSystemNeedsInit() and type(_G.MSUF_InitProfiles) == "function" then
        _G.MSUF_InitProfiles()
    end
    local ensure = _G.MSUF_EnsureDB
    if type(ensure) == "function" then ensure() end
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    lastEnsuredDB = _G.MSUF_DB
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
    M.SetFixedPreviewExpandedPreference(true)
    return true
end
local function BlockCombatAndRefresh(ctx)
    if not M.BlockCombatAction() then return false end
    M.Refresh(ctx)
    return true
end

local function QueueMenuRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local function Run()
        refreshQueued = false
        refreshTimer = nil
        if IsConfigCombatLocked() then return end
        if M.frame and M.frame.IsShown and M.frame:IsShown() and M.Refresh then M.Refresh() end
    end
    if C_Timer and C_Timer.NewTimer then
        refreshTimer = C_Timer.NewTimer(MENU_REFRESH_DELAY, Run)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(MENU_REFRESH_DELAY, Run)
    else
        Run()
    end
end
local function CancelQueuedMenuRefresh()
    refreshQueued = false
    if refreshTimer and refreshTimer.Cancel then refreshTimer:Cancel() end
    refreshTimer = nil
end
-- The History sibling notifies through the coalesced menu refresh and the
-- Reset sibling finishes a page reset with it; both pick these from M.
M.QueueMenuRefresh = QueueMenuRefresh
M.CancelQueuedMenuRefresh = CancelQueuedMenuRefresh
local function WidgetHistoryLabel(ctx, widget, fallback)
    local fs = widget and (widget._msuf2Title or widget._msuf2Label)
    if fs and fs.GetText then
        local text = fs.GetText(fs)
        if text and text ~= "" then return text end
    end
    if widget and widget.GetText then
        local text = widget.GetText(widget)
        if text and text ~= "" then return text end
    end
    return fallback or tostring((ctx and ctx.key) or "MSUF2 option")
end
local function WidgetHistorySource(ctx, widget, suffix)
    local explicit = widget and widget._msuf2CommandAction
        and widget._msuf2CommandAction.historySource
    if type(explicit) == "string" and explicit ~= "" then return explicit end
    local key = (ctx and ctx.key) or "page"
    local kind = widget and (widget._msuf2ControlKind or widget.GetObjectType and widget:GetObjectType()) or "control"
    local tail = tostring(key) .. ":" .. tostring(kind) .. ":" .. tostring(suffix or WidgetHistoryLabel(ctx, widget))
    if tostring(key):match("^gf_") then return "group:" .. tostring(M.gfScope or "party") .. ":" .. tail end
    if tostring(key):match("^auras3") then return "auras:" .. tostring(M.auraScope or "shared") .. ":" .. tail end
    return tail
end
local function CaptureWidgetChange(ctx, widget, label, fn)
    label = label or WidgetHistoryLabel(ctx, widget)
    return M.CaptureHistory(label, WidgetHistorySource(ctx, widget, label), fn)
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
        if type(fn) == "function" then fn() end
    end
end
function M.RequestRefresh(ctx, reason)
    local entry = ResolveRefreshEntry(ctx)
    if entry then
        if entry._msuf2RefreshQueued then return true end
        M.MarkMenuDataDirty(reason or "request-refresh")
        entry._msuf2RefreshQueued = true
        -- Refreshers are entry-local and de-duplicated, so rebuilding one page does not force
        -- all Menu2 controls to resync.
        local function Run()
            entry._msuf2RefreshQueued = nil
            if entry._msuf2Invalidated then return end
            if M.RunEntryRefreshers then
                M.RunEntryRefreshers(entry)
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
    M.MarkMenuDataDirty(reason or "request-refresh")
    M._msuf2RefreshQueued = true
    local function Run()
        M._msuf2RefreshQueued = nil
        local active = ResolveRefreshEntry()
        if active then
            if M.RunEntryRefreshers then M.RunEntryRefreshers(active) else RunRefreshList(active.refreshers) end
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
    M.MarkMenuDataDirty("refresh")
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
        -- An action-backed bound widget carries its argument contract here too.
        -- RuntimeControlCatalog reads both off the command, and without them an
        -- action control looks argument-less and is downgraded to "guided",
        -- which the release schema refuses to publish.
        actionInputArg = opts.actionInputArg,
        actionFixedArgs = opts.actionFixedArgs,
        navigationKey = opts.navigationKey,
        historySource = opts.historySource,
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
        M.RegisterRuntimeControl(widget, {
            controlId = command.controlId,
            pageKey = ctx and ctx.key,
            kind = kind,
            label = opts.label or widget._msuf2SearchText or widget._msuf2SearchTitle,
            identityLabel = widget._msuf2SearchText or widget._msuf2SearchTitle or opts.label,
            identityKey = command.identityKey,
            controlPath = command.controlPath,
            settingKey = command.settingKey,
            actionKey = command.actionKey,
            actionInputArg = command.actionInputArg,
            actionFixedArgs = command.actionFixedArgs,
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
local function RegisterVisibleSliderRefresh(ctx, slider, refresh)
    local owner = ctx and (ctx.entry or ctx)
    if not (owner and slider and type(refresh) == "function") then return refresh end
    local refreshers = owner._msuf2VisibleSliderRefreshers
    if type(refreshers) ~= "table" then
        refreshers = {}
        owner._msuf2VisibleSliderRefreshers = refreshers
    end
    refreshers[slider] = refresh
    return refresh
end
function M.RefreshVisibleSliders(reason)
    local entry = ResolveRefreshEntry()
    local refreshers = entry and entry._msuf2VisibleSliderRefreshers
    if type(refreshers) ~= "table" or entry._msuf2Invalidated then return false end
    local refreshed = false
    for slider, refresh in pairs(refreshers) do
        if slider and type(refresh) == "function" then
            refresh()
            refreshed = true
        end
    end
    return refreshed
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
local function SliderPointerDragActive(self)
    if self._msuf2SliderActive == true then return true end
    local isMouseButtonDown = _G.IsMouseButtonDown
    return type(isMouseButtonDown) == "function"
        and self.IsMouseOver and self:IsMouseOver()
        and isMouseButtonDown("LeftButton") == true
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
        -- Keep the transaction open through the complete native MouseUp event.
        -- Some Slider implementations deliver their final OnValueChanged after
        -- OnMouseUp; committing on the next event tick folds that value into the
        -- same single Undo/Redo step without any recurring timer or idle work.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() M.CommitHistoryTransaction() end)
        else
            M.CommitHistoryTransaction()
        end
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
        -- Blizzard may emit the first value tick before our OnMouseDown hook.
        -- Begin lazily while the pointer is actively dragging this Slider so
        -- even that first tick belongs to the release-time transaction.
        if not self._msuf2HistoryTransaction and SliderPointerDragActive(self) then
            BeginSliderHistory(self)
        end
        CaptureWidgetChange(ctx, self, nil, function()
            setValue(value)
        end)
        NotifyGuidedControlInteraction(self)
    end)
    -- Keep the bound model refresh reachable for narrow external sync paths
    -- (for example Edit Mode position drags) without refreshing the whole page.
    slider._msuf2RefreshFromModel = RegisterVisibleSliderRefresh(ctx, slider,
        AddRefreshCall(ctx, RefreshSlider, slider, getValue))
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
        M.CommitHistoryTransaction()
    end
    colorButton._msuf2BeginColorInteraction = BeginColorHistory
    colorButton._msuf2CommitColorInteraction = CommitColorHistory
    colorButton._msuf2GetColorOpacity = function()
        if type(getRGB) ~= "function" then return nil end
        local _, _, _, alpha = getRGB()
        return type(alpha) == "number" and alpha or nil
    end
    local function RefreshColor()
        if type(getRGB) ~= "function" then return end
        local r, g, b, alpha = getRGB()
        colorButton._msuf2ColorHasOpacity = type(alpha) == "number"
        colorButton:SetRGB(r or 1, g or 1, b or 1)
    end
    colorButton:SetOnColorChanged(function(r, g, b, alpha)
        if BlockCombatAndRefresh(ctx) then
            RefreshColor()
            return
        end
        local currentAlpha
        if type(getRGB) == "function" then
            local cr, cg, cb, ca = getRGB()
            currentAlpha = ca
            local alphaUnchanged = alpha == nil
                or (type(ca) == "number" and math.abs(ca - alpha) < 0.0001)
            if math.abs((cr or 1) - (r or 1)) < 0.0001
                and math.abs((cg or 1) - (g or 1)) < 0.0001
                and math.abs((cb or 1) - (b or 1)) < 0.0001
                and alphaUnchanged
            then
                RefreshColor()
                return
            end
        end
        local nextAlpha = alpha
        if nextAlpha == nil and type(currentAlpha) == "number" then nextAlpha = currentAlpha end
        CaptureWidgetChange(ctx, colorButton, nil, function()
            if type(setRGB) == "function" then setRGB(r, g, b, nextAlpha) end
        end)
        RefreshColor()
        NotifyGuidedControlInteraction(colorButton)
    end)
    colorButton:HookScript("OnHide", CommitColorHistory)
    M.AddRefresher(ctx, RefreshColor)
    RefreshColor()
    local widgets = M.Widgets
    if widgets and type(widgets.AttachBoundColorToCollapsible) == "function" then
        widgets.AttachBoundColorToCollapsible(ctx, colorButton)
    end
end
