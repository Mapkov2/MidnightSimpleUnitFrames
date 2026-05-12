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

function M.RequestUnitApply(unit, reason, opts)
    unit = (unit == "tot") and "targettarget" or unit
    if not UNIT_KEYS[unit] then return end
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
    local conf = M.GetUnitDB(unit)
    if conf[key] == value then return false end
    conf[key] = value
    M.RequestUnitApply(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

function M.RequestGeneralApply(reason, opts)
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
    local g = M.GetGeneralDB()
    if g[key] == value then return false end
    g[key] = value
    M.RequestGeneralApply(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

function M.AddRefresher(ctx, fn)
    if not (ctx and type(fn) == "function") then return end
    ctx.refreshers[#ctx.refreshers + 1] = fn
end

function M.BindToggle(ctx, widget, getValue, setValue)
    if not widget then return end
    widget:SetScript("OnClick", function(self)
        local nextValue = not (getValue() and true or false)
        setValue(nextValue)
        self:SetChecked(nextValue)
    end)
    M.AddRefresher(ctx, function()
        widget:SetChecked(getValue() and true or false)
    end)
end

function M.BindSlider(ctx, slider, getValue, setValue)
    if not slider then return end
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if self._msuf2Step and self._msuf2Step >= 1 then
            value = math.floor(value + 0.5)
        end
        setValue(value)
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
            setValue(self._msuf2Value)
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
        setValue(value)
        dropdown:SetValue(value)
    end)
    M.AddRefresher(ctx, function()
        dropdown:SetValue(getValue())
    end)
end

function M.BindTextInput(ctx, editBox, getValue, setValue, commitOnBlur)
    if not editBox then return end
    editBox._msuf2CommitOnBlur = commitOnBlur and true or false
    editBox:SetOnValueCommitted(function(value)
        setValue(value or "")
    end)
    M.AddRefresher(ctx, function()
        if editBox:HasFocus() then return end
        editBox:SetText(tostring(getValue() or ""))
    end)
end

function M.BindColor(ctx, colorButton, getRGB, setRGB)
    if not colorButton then return end
    colorButton:SetOnColorChanged(function(r, g, b)
        setRGB(r, g, b)
    end)
    M.AddRefresher(ctx, function()
        local r, g, b = getRGB()
        colorButton:SetRGB(r or 1, g or 1, b or 1)
    end)
end
