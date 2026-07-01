--- MSUF2 support features split out of the legacy standalone slash menu.
--- Keep this file free of page/UI construction so the old SlashMenu file can be
--- removed from the TOC without losing shared runtime helpers.

local addonName, MSUF = ...
MSUF = MSUF or {}
local function EnsureMenu2Namespace()
    local namespace = MSUF.MSUF2 or _G.MSUF2 or {}
    MSUF.MSUF2 = namespace
    if _G.MSUF2 ~= namespace then _G.MSUF2 = namespace end
    return namespace
end
MSUF.GetMenu2Namespace = MSUF.GetMenu2Namespace or EnsureMenu2Namespace
local M = MSUF.GetMenu2Namespace()
MSUF.MSUF2 = M
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local unpack = table.unpack or unpack
local floor = math.floor
local abs = math.abs
local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function Print(msg)
    if type(print) == "function" then print("|cff00ff00MSUF:|r " .. tostring(msg or "")) end
end
local function Tr(text)
    if type(M.Tr) == "function" then
        local translated = M.Tr(text)
        if translated ~= nil then return translated end
    end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    if type(MSUF.TR) == "function" then
        local translated = MSUF.TR(text)
        if translated ~= nil then return translated end
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    return text
end
M.TranslateText = M.TranslateText or Tr
local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then return _G.MSUF_IsConfigCombatLocked() and true or false end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return true end
    return false
end
local function ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    else
        Print("Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end
local function BlockConfigCombatLocked(silent)
    if not IsConfigCombatLocked() then return false end
    if not silent then ShowConfigCombatLockMessage() end
    return true
end
M.IsConfigCombatLocked = M.IsConfigCombatLocked or IsConfigCombatLocked
local function EnsureGeneral()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then ensureDB() end
    ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
    _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
    return _G.MSUF_DB.general
end
local function AddTooltip(widget, title, body, opts)
    if not (widget and (widget.SetScript or widget.HookScript)) then return widget end
    opts = opts or {}
    local owner = opts.owner or "ANCHOR_RIGHT"
    local titleColor = opts.titleColor or { 1, 1, 1 }
    local bodyColor = opts.bodyColor or { 0.80, 0.86, 1.00 }
    local function ResolveText(value, ownerFrame) return type(value) == "function" and value(ownerFrame) or value end
    local function ShowTooltip(self)
        if not _G.GameTooltip then return end
        if opts.enabled and not opts.enabled(self) then return end
        local resolvedTitle = ResolveText(title, self)
        local resolvedBody = ResolveText(body, self)
        _G.GameTooltip:SetOwner(self, owner)
        if resolvedTitle and resolvedTitle ~= "" then
            if opts.titleAsLine then
                _G.GameTooltip:AddLine(Tr(resolvedTitle), titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1, titleColor[4])
            else
                _G.GameTooltip:SetText(Tr(resolvedTitle), titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1, titleColor[4])
            end
        end
        if resolvedBody and resolvedBody ~= "" then _G.GameTooltip:AddLine(Tr(resolvedBody), bodyColor[1] or 0.80, bodyColor[2] or 0.86, bodyColor[3] or 1.00, true) end
        _G.GameTooltip:Show()
    end
    local function HideTooltip()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end
    local function Wire(target)
        if opts.hook and target.HookScript then
            target:HookScript("OnEnter", ShowTooltip)
            target:HookScript("OnLeave", HideTooltip)
        elseif target.SetScript then
            target:SetScript("OnEnter", ShowTooltip)
            target:SetScript("OnLeave", HideTooltip)
        end
    end
    Wire(widget)
    if opts.labelHit and widget._msuf2LabelHit and widget._msuf2LabelHit ~= widget then Wire(widget._msuf2LabelHit) end
    return widget
end
ExportPublic("MSUF_AddTooltip", _G.MSUF_AddTooltip or AddTooltip)
M.AddTooltip = M.AddTooltip or AddTooltip
local PREVIEW_NUDGE_DIRECTIONS = { { "LEFT", -1, 0 }, { "RIGHT", 1, 0 }, { "UP", 0, 1 }, { "DOWN", 0, -1 } }
local PREVIEW_NUDGE_BINDING_PREFIXES = { "", "SHIFT-", "CTRL-", "CTRL-SHIFT-", "SHIFT-CTRL-" }

local function ReleasePreviewKeyboardCapture(box)
    local helpers = M.PreviewHelpers
    if helpers and type(helpers.ReleaseKeyboardCapture) == "function" then
        helpers.ReleaseKeyboardCapture(box)
    elseif box and box.SetPropagateKeyboardInput then
        box:SetPropagateKeyboardInput(true)
    end
end

local function PreviewBindingOwner_OnEvent(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.__msufPendingClear = true
        ReleasePreviewKeyboardCapture(self.__msufActiveBox)
        return
    end
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self.__msufPendingClear = nil
    if self.__msufActiveName then _G[self.__msufActiveName] = nil end
    ReleasePreviewKeyboardCapture(self.__msufActiveBox)
    self.__msufActiveBox = nil
    self.__msufActiveName = nil
    if ClearOverrideBindings then ClearOverrideBindings(self) end
    if self.Hide then self:Hide() end
end

local function EnsurePreviewBindingOwner(ownerName)
    if not ownerName then return nil end
    local owner = _G[ownerName]
    if not owner then
        owner = CreateFrame("Frame", ownerName, UIParent)
        _G[ownerName] = owner
    end
    if owner.SetScript and owner.__msufPreviewBindingOwner ~= true then
        owner.__msufPreviewBindingOwner = true
        owner:SetScript("OnEvent", PreviewBindingOwner_OnEvent)
    end
    return owner
end

-- Shared secure arrow-key binding for preview-only movers. The helper only runs
-- while preview handles are selected and exits before touching protected state in combat.
function M.SetPreviewArrowBindings(box, enabled, spec)
    spec = spec or {}
    local ownerName = spec.ownerName
    local activeName = spec.activeName
    local owner = ownerName and _G[ownerName]
    if InCombatLockdown and InCombatLockdown() then
        ReleasePreviewKeyboardCapture(box)
        if activeName and (enabled or _G[activeName] == box or box == nil) then _G[activeName] = nil end
        if not enabled or not box then
            if spec.onDisable then spec.onDisable(box) end
        end
        if owner then
            if owner.SetScript and owner.__msufPreviewBindingOwner ~= true then
                owner.__msufPreviewBindingOwner = true
                owner:SetScript("OnEvent", PreviewBindingOwner_OnEvent)
            end
            owner.__msufActiveBox = box
            owner.__msufActiveName = activeName
            owner.__msufPendingClear = true
            if owner.RegisterEvent then owner:RegisterEvent("PLAYER_REGEN_ENABLED") end
        end
        return false
    end
    if owner and ClearOverrideBindings then ClearOverrideBindings(owner) end
    if owner and owner.Hide then owner:Hide() end
    if not enabled or not box then
        if spec.onDisable then spec.onDisable(box) end
        if activeName and (_G[activeName] == box or box == nil) then _G[activeName] = nil end
        if owner then
            owner.__msufPendingClear = nil
            owner.__msufActiveBox = nil
            owner.__msufActiveName = nil
            if owner.UnregisterEvent then
                owner:UnregisterEvent("PLAYER_REGEN_DISABLED")
                owner:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return
    end
    if activeName then _G[activeName] = box end
    owner = EnsurePreviewBindingOwner(ownerName)
    if not owner then return false end
    owner.__msufPendingClear = nil
    owner.__msufActiveBox = box
    owner.__msufActiveName = activeName
    owner:Show()
    if owner.RegisterEvent then
        owner:RegisterEvent("PLAYER_REGEN_DISABLED")
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    local prefix = spec.buttonPrefix or ownerName or "MSUF_Preview_Nudge"
    for i = 1, #PREVIEW_NUDGE_DIRECTIONS do
        local dir = PREVIEW_NUDGE_DIRECTIONS[i]
        local btnName = prefix .. dir[1]
        local btn = _G[btnName]
        if not btn then
            btn = CreateFrame("Button", btnName, owner, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", function(self)
                local s = self._msufNudgeSpec or {}
                local active = s.getActive and s.getActive() or (s.activeName and _G[s.activeName])
                if s.onClick then s.onClick(active, self._msufDx or 0, self._msufDy or 0, self) end
            end)
        end
        btn._msufNudgeSpec = spec
        btn._msufDx, btn._msufDy = dir[2], dir[3]
        if SetOverrideBindingClick then
            for j = 1, #PREVIEW_NUDGE_BINDING_PREFIXES do
                SetOverrideBindingClick(owner, false, PREVIEW_NUDGE_BINDING_PREFIXES[j] .. dir[1], btnName)
            end
        end
    end
end
local STATIC_POPUP_DEFAULTS = { timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
function M.InstallStaticPopup(key, spec, defaults)
    if not (_G.StaticPopupDialogs and key and type(spec) == "table") then return nil end
    local existing = _G.StaticPopupDialogs[key]
    if existing then return existing end
    for field, value in pairs(defaults or STATIC_POPUP_DEFAULTS) do
        if spec[field] == nil then spec[field] = value end
    end
    _G.StaticPopupDialogs[key] = spec
    return spec
end
local function LeftJustifyButtonText(btn, leftPad)
    leftPad = leftPad or 10
    if not (btn and btn.GetFontString) then return end
    local fontString = btn:GetFontString()
    if not fontString then return end
    if fontString.SetJustifyH then fontString:SetJustifyH("LEFT") end
    if fontString.ClearAllPoints and fontString.SetPoint then
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        fontString:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end
end
ExportPublic("MSUF_LeftJustifyButtonText", _G.MSUF_LeftJustifyButtonText or LeftJustifyButtonText)
function M.ValueTextList(...)
    local out = {}
    local n = select("#", ...)
    for i = 1, n, 2 do
        local value = select(i, ...)
        local text = select(i + 1, ...)
        out[#out + 1] = { value = value, text = text ~= nil and text or value }
    end
    return out
end
function M.Lines(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
function M.ValueTextRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local value, text = line:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = text ~= "" and text or value } end
    end
    return out
end
function M.ValueTextPairs(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local value, text = item:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = text ~= "" and text or value } end
    end
    return out
end
function M.KeyLabelRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local key, label = line:match("^(.-)=(.*)$")
        if key then out[#out + 1] = { key = key, label = label ~= "" and label or key } end
    end
    return out
end
function M.KeyLabelMap(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local key, label = item:match("^(.-)=(.*)$")
        if key then out[key] = label ~= "" and label or key end
    end
    return out
end
function M.PipeRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local cols, n = {}, 0
        for col in (line .. "|"):gmatch("(.-)|") do n = n + 1; cols[n] = col end
        out[#out + 1] = cols
    end
    return out
end
function M.ColorRows(...)
    local out = {}
    local n = select("#", ...)
    if n == 1 and type((...)) == "string" then
        for line in tostring((...) or ""):gmatch("[^;\r\n]+") do
            local key, label, r, g, b = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
            if key then out[#out + 1] = { key = key, label = label, dr = tonumber(r), dg = tonumber(g), db = tonumber(b) } end
        end
        return out
    end
    for i = 1, n, 5 do
        out[#out + 1] = { key = select(i, ...), label = select(i + 1, ...), dr = select(i + 2, ...), dg = select(i + 3, ...), db = select(i + 4, ...) }
    end
    return out
end
function M.KeySet(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[select(i, ...)] = true
    end
    return out
end
function M.KeySetFromWords(text)
    local out = {}
    for key in tostring(text or ""):gmatch("%S+") do out[key] = true end
    return out
end
function M.WordList(text)
    local out = {}
    for value in tostring(text or ""):gmatch("%S+") do out[#out + 1] = value end
    return out
end

--- Cold Menu2 copy dialogs derive field lists from control specs.
function M.CopyFieldsFromSpecs(specs, values, seed, props)
    local out = type(seed) == "table" and seed or M.WordList(seed or "")
    props = props or "show iconStyle x y anchor size layer symbol"
    for value in tostring(values or ""):gmatch("%S+") do
        for i = 1, #(specs or {}) do
            local spec = specs[i]
            if spec.value == value then
                for prop in tostring(spec.copyProps or props):gmatch("%S+") do local key = spec[prop]; if key then out[#out + 1] = key end end
                local extra = spec.copyExtra; if extra then for j = 1, #extra do out[#out + 1] = extra[j] end end
                break
            end
        end
    end
    return out
end
local COMMON_FALLBACKS = {
    Noop = function() end, Nil = function() return nil end, False = function() return false end, True = function() return true end, TruePair = function() return true, true end,
    One = function() return 1 end, Empty = function() return "" end, Identity = function(v) return v end, Round = function(value) return floor((tonumber(value) or 0) + 0.5) end,
    WhiteRGB = function() return 1, 1, 1 end, BlackRGBA = function() return 0, 0, 0, 1 end, DarkRGBA = function() return 0.02, 0.03, 0.04, 0.9 end, HealthRGB = function() return 0.2, 0.8, 0.2 end, PowerRGB = function() return 0.2, 0.45, 1.0 end,
    Center = function() return "CENTER" end, Right = function() return "RIGHT" end, Status = function() return "Status" end, QuestionIcon = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end, ZeroPair = function() return 0, 0 end,
}
M.Fallbacks = M.Fallbacks or COMMON_FALLBACKS
function M.SetMenuStateValue(field, value)
    if type(M.PersistMenuStateValue) == "function" then return M.PersistMenuStateValue(field, value) end
    M[field] = value; return value
end
function M.TextSlotOffsetKeys(kind, slot)
    if kind == "name" then return "nameOffsetX", "nameOffsetY" end
    if kind == "hp" and not slot then return "hpOffsetX", "hpOffsetY" end
    if kind == "power" and not slot then return "powerOffsetX", "powerOffsetY" end
    local prefix
    if kind == "hp" then
        prefix = (slot == "left" and "hpTextLeft") or (slot == "right" and "hpTextRight") or "hpTextCenter"
    elseif kind == "power" then
        prefix = (slot == "left" and "powerTextLeft") or (slot == "right" and "powerTextRight") or "powerTextCenter"
    end
    if not prefix then return "nameOffsetX", "nameOffsetY" end
    return prefix .. "OffsetX", prefix .. "OffsetY"
end
function M.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[M.DeepCopy(k, seen)] = M.DeepCopy(v, seen)
    end
    return out
end
local function PickValues(source, names, fallbacks, defaultEmpty)
    local values, count = {}, 0
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = source[name]
        if fallbacks then value = value or fallbacks[name]
        elseif defaultEmpty then value = value or {} end
        values[count] = value
    end
    return unpack(values, 1, count)
end
local function PickTableValues(target, source, names, fallbacks, defaultEmpty)
    target = type(target) == "table" and target or {}
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        local value = source[name]
        if fallbacks then value = value or fallbacks[name]
        elseif defaultEmpty then value = value or {} end
        target[name] = value
    end
    return target
end
function M.Pick(source, names) return PickValues(source, names) end
function M.PickDefaults(source, names) return PickValues(source, names, nil, true) end
function M.PickFallbacks(source, fallbacks, names) return PickValues(source, names, fallbacks or {}) end
function M.PickTable(source, names, target) return PickTableValues(target, source, names) end
function M.PickDefaultTable(source, names, target) return PickTableValues(target, source, names, nil, true) end
function M.PickFallbackTable(source, fallbacks, names, target) return PickTableValues(target, source, names, fallbacks or {}) end
function M.Assign(target, values)
    if type(target) ~= "table" or type(values) ~= "table" then return target end
    for key, value in pairs(values) do target[key] = value end
    return target
end
function M.AppendValues(target, ...) if type(target) ~= "table" then target = {} end; for i = 1, select("#", ...) do target[#target + 1] = select(i, ...) end; return target end
function M.AppendNamedValues(target, source, names) if type(target) ~= "table" then target = {} end; source = source or {}; for name in tostring(names or ""):gmatch("%S+") do target[#target + 1] = source[name] end; return target end
function M.AssignNamedValues(target, names, ...)
    if type(target) ~= "table" then target = {} end
    local index = 1
    for name in tostring(names or ""):gmatch("%S+") do
        target[name] = select(index, ...)
        index = index + 1
    end
    return target
end
function M.BuildControlSpecs(specs, handlers, nameFn, list)
    local controls = {}
    if type(specs) ~= "table" or type(handlers) ~= "table" then return controls end
    for i = 1, #specs do
        local spec = specs[i]
        local handler = spec and (handlers[spec[1]] or handlers["*"] or handlers.default)
        if handler then
            local control, name = handler(spec, i)
            if control ~= nil then
                controls[name or (nameFn and nameFn(spec, i, control)) or spec.name or i] = control
                if list then list[#list + 1] = control end
            end
        end
    end
    return controls
end

-- Shared Page binder helpers.
-- These keep page files focused on "which control exists" instead of repeating the
-- same create/place/bind ceremony. Callers still supply the exact get/set closures,
-- so no page-specific state or apply behavior is hidden here.
function M.BindBoolWidget(ctx, widget, getValue, setValue)
    M.BindToggle(ctx, widget,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end)
    return widget
end
function M.BindNumberWidget(ctx, widget, getValue, setValue, fallback, opts)
    opts = opts or {}
    M.BindSlider(ctx, widget,
        function() return tonumber(getValue()) or fallback or 0 end,
        function(v)
            v = tonumber(v) or fallback or 0
            if opts.roundStep and (opts.step or 1) >= 1 then v = floor(v + 0.5) end
            setValue(v)
        end)
    return widget
end
function M.BindDropdownWidget(ctx, widget, getValue, setValue)
    M.BindDropdown(ctx, widget, getValue, setValue)
    return widget
end
function M.BindSwitchAt(ctx, parent, label, x, y, width, getValue, setValue)
    return M.BindBoolWidget(ctx, M.Widgets.SwitchAt(parent, label, x, y, width or 180), getValue, setValue)
end
function M.BindToggleAt(ctx, parent, label, x, y, width, getValue, setValue)
    return M.BindBoolWidget(ctx, M.Widgets.ToggleAt(parent, label, x, y, width or 180), getValue, setValue)
end
function M.BindSliderAt(ctx, parent, label, x, y, minVal, maxVal, step, width, getValue, setValue, opts)
    local widget = M.Widgets.Slider(parent, label, minVal, maxVal, step, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    return M.BindNumberWidget(ctx, widget, getValue, setValue, opts and opts.fallback, opts)
end
function M.BindDropdownAt(ctx, parent, label, x, y, values, width, getValue, setValue)
    local widget = M.Widgets.Dropdown(parent, label, values, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    return M.BindDropdownWidget(ctx, widget, getValue, setValue)
end
function M.BindTextInputAt(ctx, parent, label, x, y, width, getValue, setValue, commitOnBlur)
    local widget = M.Widgets.TextInput(parent, label, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    M.BindTextInput(ctx, widget,
        function() return getValue() or "" end,
        function(v) setValue(v or "") end,
        commitOnBlur)
    return widget
end
function M.BindColorAt(ctx, parent, label, x, y, getRGB, setRGB)
    local widget = M.Widgets.Color(parent, label)
    M.Widgets.MoveWidget(widget, parent, x, y)
    M.BindColor(ctx, widget, getRGB, setRGB)
    return widget
end
function M.CallIf(fn, ...)
    if type(fn) == "function" then return fn(...) end
end

-- Lets callbacks call a refresh function before its body is assigned later in the page build.
function M.RefreshProxy() local refresh; return function(fn) if fn then refresh = fn; return fn end; return M.CallIf(refresh) end end

--- Declarative "master toggle gates dependent controls" helper.
--- Replaces the repeated hand-written refresh closures that read a config value and call
--- SetControlEnabled/SetControlsEnabled for each control group. The single most duplicated
--- logic shape in the Pages layer (see disabledRefresh closures), so collapsing each gate
--- from ~3 lines to one declarative row both shrinks pages and removes copy/paste drift.
---
--- source: optional fn returning the config table passed to each entry's predicates.
--- entries: list of {
---   on        = fn(cfg) -> bool   -- whether `controls` are enabled (required)
---   controls  = widget | {widgets} -- gated by `on`
---   enable    = widget | {widgets} -- the master toggle itself; enabled by `enableOn` (default: always on)
---   enableOn  = fn(cfg) -> bool    -- optional gate for `enable` (e.g. hasTotemFrame)
---   when      = fn(cfg) -> bool    -- optional: skip this entry entirely when false (control left untouched)
--- }
--- opts.also:    extra fn run at the end of every refresh (e.g. a preview repaint).
--- opts.override: fn(cfg, setEnabled) run last, for page-specific final adjustments
---               (e.g. a "managed power" branch that force-disables a group).
--- opts.track:   custom registration fn(ctx, refresh); defaults to M.TrackRefresh.
---               Pass M.TrackCollapsibleRefresh-style closures here to keep a page's
---               existing refresh wiring (collapsible/section refreshers).
--- opts.noTrack: when true, return the bare refresh fn WITHOUT registering it (caller
---               wires it into its own combined closure).
--- Returns the refresh fn.
function M.BindGateGroup(ctx, source, entries, opts)
    opts = opts or {}
    local W = M.Widgets
    local function setEnabled(target, enabled)
        if not target then return end
        if type(target) == "table" and target[1] ~= nil and not target.GetObjectType then
            W.SetControlsEnabled(target, enabled)
        else
            W.SetControlEnabled(target, enabled)
        end
    end
    local function refresh()
        local cfg = M.CallIf(source)
        for i = 1, #entries do
            local e = entries[i]
            if (not e.when) or e.when(cfg) then
                if e.enable then setEnabled(e.enable, e.enableOn and (e.enableOn(cfg) and true or false) or true) end
                if e.controls then setEnabled(e.controls, e.on and (e.on(cfg) and true or false) or false) end
            end
        end
        if opts.override then opts.override(cfg, setEnabled) end
        M.CallIf(opts.also)
    end
    if opts.noTrack then return refresh end
    if opts.track then return opts.track(ctx, refresh) or refresh end
    return M.TrackRefresh(ctx, refresh)
end
function M.RequestOrRefresh(ctx, reason) if M.RequestRefresh then return M.RequestRefresh(ctx, reason) end; return M.CallIf(M.Refresh, ctx) end
function M.NormalizeHpMode(mode)
    if type(_G.MSUF_NormalizeHpTextMode) == "function" then return _G.MSUF_NormalizeHpTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end
function M.NormalizePowerMode(mode)
    if type(_G.MSUF_NormalizePowerTextMode) == "function" then return _G.MSUF_NormalizePowerTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end
function M.ApplyGameplay()
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        local result = MSUF.MSUF_RequestGameplayApply()
        return result ~= false
    end
    if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        local result = MSUF.MSUF_ApplyGameplayVisuals()
        return result ~= false
    end
    return false
end
local function GameplayDB()
    local db
    if type(M.EnsureDB) == "function" then db = M.EnsureDB() end
    if type(db) ~= "table" then
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        db = _G.MSUF_DB
    end
    db.gameplay = type(db.gameplay) == "table" and db.gameplay or {}
    return db.gameplay
end
function M.GetGameplayPlayerSpecID()
    if MSUF and type(MSUF.MSUF_GetPlayerSpecID) == "function" then
        return MSUF.MSUF_GetPlayerSpecID()
    end
    if type(_G.MSUF_GetPlayerSpecID) == "function" then
        return _G.MSUF_GetPlayerSpecID()
    end
    if GetSpecialization and GetSpecializationInfo then
        local spec = GetSpecialization()
        if spec then
            local id = GetSpecializationInfo(spec)
            return id
        end
    end
    return nil
end
function M.ResolveGameplaySpellInput(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    if text == "" then return 0 end
    local linkID = text:match("[Ss][Pp][Ee][Ll][Ll]:(%d+)")
    if linkID then return tonumber(linkID) or 0 end
    local asNumber = tonumber(text)
    if asNumber then return floor(asNumber + 0.5) end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(text)
        if type(info) == "table" and info.spellID then return tonumber(info.spellID) or 0 end
    end
    if text ~= "" and GetSpellInfo then
        local _, _, _, _, _, _, spellID = GetSpellInfo(text)
        return tonumber(spellID) or 0
    end
    return 0
end
function M.GetGameplaySpellName(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and info.name then return info.name end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(id)
        return name
    end
    return nil
end
function M.GetGameplayMeleeSpellID(g)
    g = g or GameplayDB()
    local id = 0
    if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
        local specID = M.GetGameplayPlayerSpecID()
        if specID then id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0 end
    end
    if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
        local _, class = UnitClass("player")
        if class then id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0 end
    end
    if id <= 0 then id = tonumber(g.nameplateMeleeSpellID) or 0 end
    return id
end
function M.SeedGameplayMeleeSpellScope(scope)
    local g = GameplayDB()
    if scope == "spec" then
        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
        local specID = M.GetGameplayPlayerSpecID()
        if specID and (tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0) <= 0 then g.nameplateMeleeSpellIDBySpec[specID] = M.GetGameplayMeleeSpellID(g) end
    elseif scope == "class" then
        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
        if UnitClass then
            local _, class = UnitClass("player")
            if class and (tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0) <= 0 then g.nameplateMeleeSpellIDByClass[class] = M.GetGameplayMeleeSpellID(g) end
        end
    end
end
function M.SetGameplayMeleeSpellID(value)
    local spellID = M.ResolveGameplaySpellInput(value)
    local g = GameplayDB()
    if g.meleeSpellPerSpec then
        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
        local specID = M.GetGameplayPlayerSpecID()
        if specID then g.nameplateMeleeSpellIDBySpec[specID] = spellID end
    elseif g.meleeSpellPerClass and UnitClass then
        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
        local _, class = UnitClass("player")
        if class then g.nameplateMeleeSpellIDByClass[class] = spellID end
    end
    g.nameplateMeleeSpellID = spellID
    return spellID
end
function M.StatusBarTextureItems(followText)
    local ui = MSUF and MSUF.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then return ui.StatusBarTextureItems(followText) end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end
function M.PercentValue(value)
    return tostring(floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end
function M.ParsePercentValue(text)
    local raw = tostring(text or "")
    local value = tonumber((raw:gsub("%%", ""):gsub(",", ".")))
    if value == nil then return nil end
    if raw:find("%%") or value > 1 then return value / 100 end
    return value
end
function M.UsePercentInput(widget)
    if widget and widget.SetValueFormatter then widget:SetValueFormatter(M.PercentValue) end
    if widget and widget.SetValueParser then widget:SetValueParser(M.ParsePercentValue) end
end
function M.Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
function M.AlphaLabel(label, value)
    return tostring(label or "") .. ": " .. M.PercentValue(value)
end
function M.BindSliderLiveLabel(ctx, widget, readValue, labelFn, percentInput)
    if percentInput then M.UsePercentInput(widget) end
    local function SetLabel(value)
        if widget and widget._msuf2Title then widget._msuf2Title:SetText(labelFn(value)) end
    end
    widget:HookScript("OnValueChanged", function(_, value) SetLabel(value) end)
    local function RefreshLabel() SetLabel(readValue()) end
    M.TrackRefresh(ctx, RefreshLabel)
    return widget
end
function M.TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end
    local bytePos, valueLen, chars = 1, #value, 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string.byte(value, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return string.sub(value, 1, bytePos - 1)
end
function M.CleanToTInlineCustomSeparator(value, maxChars)
    value = tostring(value or ""):gsub("[%c]", " ")
    return M.TruncateUtf8Chars(value, maxChars or 5)
end
function M.ApplyPopupFramePriority(frame)
    if not frame then return end
    if type(M.ApplyMenuPopupFramePriority) == "function" then
        M.ApplyMenuPopupFramePriority(frame)
    elseif type(M.ApplyMenuFramePriority) == "function" then
        M.ApplyMenuFramePriority(frame, M.MENU_POPUP_FRAME_LEVEL or 120)
    else
        if frame.SetFrameStrata then frame:SetFrameStrata("FULLSCREEN_DIALOG") end
        if frame.SetFrameLevel then frame:SetFrameLevel(120) end
    end
end
function M.CreateMenuPopupPanel(parent, opts)
    opts = opts or {}
    local theme = M.Theme or {}
    local colors = theme.colors or {}
    local panel = CreateFrame("Frame", opts.name, parent, opts.template or (theme.Template and theme.Template() or nil))
    local bg = opts.bg or colors.glassPopup or { 0.014, 0.024, 0.050, 0.985 }
    local border = opts.border or { 0.10, 0.22, 0.44, 0.80 }
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.985)
        panel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 0.80)
    else
        local fill = panel:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.985)
        local edge = panel:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("TOPRIGHT")
        edge:SetHeight(1)
        edge:SetColorTexture(border[1], border[2], border[3], border[4] or 0.80)
    end
    if theme.ApplyGlass then theme.ApplyGlass(panel, opts.glass or "popup") end
    if opts.priority ~= false then M.ApplyPopupFramePriority(panel) end
    if opts.mouse ~= false and panel.EnableMouse then panel:EnableMouse(true) end
    return panel
end
M.Noop = M.Noop or M.Fallbacks.Noop
function M.OnOffBadge(enabled, onText, offText)
    return {
        text = enabled and (onText or "Shown") or (offText or "Hidden"),
        kind = enabled and "ok" or "muted",
    }
end
function M.BadgeNumber(value)
    value = tonumber(value) or 0
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end
function M.OptionText(values, value, fallback)
    if type(values) == "function" then values = values() end
    if type(values) == "table" then
        for i = 1, #values do
            local item = values[i]
            if type(item) == "table" then
                local itemValue = item.value
                if itemValue == nil then itemValue = item.key or item[1] end
                if tostring(itemValue) == tostring(value) then return item.text or item.label or tostring(value or fallback or "") end
            end
        end
    end
    if value == nil or value == "" then return fallback or "" end
    return tostring(value)
end
function M.NormalizePortraitClassStyle(value)
    if value == "class_colored_border" or value == "colored" then return "RONDO_COLOR" end
    if value == "wow_icon_border" or value == "wow" then return "RONDO_WOW" end
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    local PM = MSUF and MSUF.PortraitMedia
    if PM and type(PM.NormalizeClassPack) == "function" then return PM.NormalizeClassPack(value) end
    if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then return value end
    return "BLIZZARD"
end
function M.IsMSUFEditModeActive(includeBlizzard)
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active ~= nil then return st.active == true end
    local em2 = rawget(_G, "MSUF_EM2")
    local state = em2 and em2.State
    if state and type(state.IsActive) == "function" then return state.IsActive() and true or false end
    local fn = rawget(_G, "MSUF_IsMSUFEditModeActive")
        or rawget(_G, "MSUF_IsInEditMode")
        or rawget(_G, "MSUF_IsEditModeActive")
        or (includeBlizzard and rawget(_G, "IsEditModeActive") or nil)
    if type(fn) == "function" then
        return fn() and true or false
    end
    return rawget(_G, "MSUF_UnitEditModeActive") == true
        or rawget(_G, "MSUF_EDITMODE_ACTIVE") == true
end
function M.IsEditModeCombatLocked(includeBlizzard)
    local fn = includeBlizzard and rawget(_G, "IsEditModeCombatLocked") or nil
    if type(fn) == "function" then
        return fn() and true or false
    end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end
local function EditModeState()
    local em2 = rawget(_G, "MSUF_EM2")
    local state = type(em2) == "table" and em2.State or nil
    return type(state) == "table" and state or nil
end
local function RefreshEditModeSurfaces()
    if type(M.RefreshMenuFramePriority) == "function" then M.RefreshMenuFramePriority() end
    if type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
    if M.frame and type(M.frame.RefreshStatus) == "function" then M.frame:RefreshStatus() end
end
function M.EditModeLifecycleStatus(includeBlizzard)
    local state = EditModeState()
    local setFn = rawget(_G, "MSUF_SetMSUFEditModeDirect") or rawget(_G, "MSUF_SetEditMode")
    local unitKey = rawget(_G, "MSUF_CurrentEditUnitKey")
    if state and type(state.GetUnitKey) == "function" then unitKey = state.GetUnitKey() or unitKey end
    return {
        active = M.IsMSUFEditModeActive(includeBlizzard) and true or false,
        combatLocked = M.IsEditModeCombatLocked(includeBlizzard) and true or false,
        unitKey = unitKey,
        hasDirectHelper = type(setFn) == "function",
        hasStateEnter = state and type(state.Enter) == "function" or false,
        hasStateExit = state and type(state.Exit) == "function" or false,
        hasStateCancel = state and type(state.CancelAll) == "function" or false,
    }
end
function M.SetMSUFEditModeActive(active, unitKey, opts)
    opts = opts or {}
    active = active and true or false
    local before = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if before.active == active then return true, active and "already_enabled" or "already_disabled", before end
    if active and before.combatLocked then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        elseif type(M.ShowConfigCombatLockMessage) == "function" then
            M.ShowConfigCombatLockMessage()
        end
        return false, "combat_locked", before
    end
    local fn = rawget(_G, "MSUF_SetMSUFEditModeDirect") or rawget(_G, "MSUF_SetEditMode")
    if type(fn) == "function" then
        local result = fn(active, unitKey)
        if result == false then return false, "helper_failed", before end
        RefreshEditModeSurfaces()
        local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
        if after.active == active then return true, active and "enabled" or "disabled", after end
        return false, "helper_failed", after
    end
    local state = EditModeState()
    if active and state and type(state.Enter) == "function" then
        state.Enter(unitKey)
    elseif (not active) and state and type(state.Exit) == "function" then
        state.Exit(opts.source or "msuf2_menu")
    else
        return false, active and "missing_enter_helper" or "missing_exit_helper", before
    end
    RefreshEditModeSurfaces()
    local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if after.active == active then return true, active and "enabled" or "disabled", after end
    return false, "helper_failed", after
end
function M.CancelMSUFEditMode(opts)
    opts = opts or {}
    local before = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if not before.active then return true, "already_disabled", before end
    local state = EditModeState()
    if not (state and type(state.CancelAll) == "function") then return false, "missing_cancel_helper", before end
    local result = state.CancelAll()
    if result == false then return false, "helper_failed", before end
    RefreshEditModeSurfaces()
    local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if not after.active then return true, "canceled", after end
    return false, "helper_failed", after
end
function M.ToggleMSUFEditMode(unitKey, opts)
    opts = opts or {}
    local status = M.EditModeLifecycleStatus(opts.includeBlizzard)
    return M.SetMSUFEditModeActive(not status.active, unitKey, opts)
end
function M.WireEditModeButton(ctx, button, opts)
    if not button then return nil end
    opts = opts or {}
    local function Refresh()
        local active = M.IsMSUFEditModeActive(opts.includeBlizzard)
        if button.SetText then button:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode")) end
        if button.SetActive then button:SetActive(false) end
        if button.SetEnabled then button:SetEnabled(active or not M.IsEditModeCombatLocked(opts.includeBlizzard)) end
    end
    button:SetScript("OnClick", function()
        if opts.blockConfig and type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then
            Refresh()
            return
        end
        local active = M.IsMSUFEditModeActive(opts.includeBlizzard)
        if (not active) and M.IsEditModeCombatLocked(opts.includeBlizzard) then
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
            Refresh()
            return
        end
        local unit = type(opts.unit) == "function" and opts.unit() or opts.unit
        local nextActive = not active
        M.ToggleMSUFEditMode(unit, { includeBlizzard = opts.includeBlizzard, source = opts.source or "msuf2_menu" })
        if opts.defer then C_Timer.After(0, Refresh) else Refresh() end
        if type(opts.afterClick) == "function" then opts.afterClick(nextActive, active) end
    end)
    M.TrackRefresh(ctx, Refresh)
    return Refresh
end
function M.TrackRefresh(ctx, refresh)
    if type(refresh) ~= "function" then return nil end
    if type(M.AddRefresher) == "function" then M.AddRefresher(ctx, refresh) end
    if ctx and (
        ctx._msuf2Building == true
        or (ctx.entry and ctx.entry._msuf2Building == true)
        or (ctx.hiddenBuild == true)
        or (ctx.entry and ctx.entry.hiddenBuild == true)
    ) then return refresh end
    refresh()
    return refresh
end
function M.TrackCollapsibleRefresh(ctx, section, refresh)
    refresh = M.TrackRefresh(ctx, refresh)
    local entry = section and section._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = refresh end
    return refresh
end
function M.TrackMethodRefresh(ctx, object, method)
    return M.TrackRefresh(ctx, function()
        local fn = object and object[method]; if type(fn) == "function" then return fn(object) end
    end)
end
local GROUP_KEYS_A = "SCOPE_VALUES GROWTH_VALUES "
local GROUP_KEYS_B = "HEALTH_MODES TEXT_MODES "
local GROUP_KEYS_C = "ANCHORS AURA_ANCHORS SORT_MODES GF_BAR_MODES "
local GROUP_KEYS_D = "GF_ANCHOR_TO GF_ANCHOR_POINTS STATUS_ICON_ANCHORS GF_STATUS_ICON_SPECS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES FRAME_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES"
M.GROUP_SPEC_TABLE_KEYS = GROUP_KEYS_A .. "BLIZZARD_FALLBACK_VALUES " .. GROUP_KEYS_B .. "DELIMITER_VALUES " .. GROUP_KEYS_C .. GROUP_KEYS_D
local tips = {}
for tip in ([[
Bigger steps: Hold SHIFT while adjusting sliders to change values faster.|Fine tuning: Hold CTRL while adjusting sliders for smaller steps.|Quick reset: If something feels off, try /msuf reset for frame positions.|Factory reset: Use Menu > Advanced > Factory Reset or /msuf fullreset confirm + /reload.|Edit Mode: Use Toggle Edit Mode to move frames quickly, then fine-tune with the position popup.
Profiles safety: Create a new profile before big experiments so you can switch back instantly.|Colors: The Colors tab lets you customize fonts, bars, castbars and highlights.|Gameplay: The Gameplay tab contains extra UI tools and warnings you can enable or disable.|Recommended: Sensei Resource Bar pairs well with MSUF for clean resource tracking.|UI scale tip: MSUF has its own UI scale, separate from Blizzard global UI scale.
Troubleshoot: If visuals do not update, a quick /reload fixes most UI state issues.|Readability: Slightly larger fonts often help more than bigger frames.|During development of MSUF Unhalted, R41z0r and other addon developers helped out.|Danders is a strong Party/Raidframe addon and works well with MSUF.|Community: If you like MSUF, share it with a friend.
]]):gmatch("[^|]+") do
    tips[#tips + 1] = (tip:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function GetNextTip()
    local g = EnsureGeneral()
    local count = #tips
    if count == 0 then return nil, 0, 0 end
    local index = tonumber(g.tipCycleIndex) or 1
    index = floor(index)
    if index < 1 or index > count then index = 1 end
    local tip = tips[index]
    local nextIndex = index + 1
    if nextIndex > count then nextIndex = 1 end
    g.tipCycleIndex = nextIndex
    return tip, index, count
end
ExportPublic("MSUF_GetNextTip", GetNextTip)
local pendingReloadRecommendedLabel
local function ShowReloadRecommendedPopup(label)
    if BlockConfigCombatLocked(false) then return end
    if not _G.StaticPopupDialogs then return end
    pendingReloadRecommendedLabel = tostring(label or "")
    if pendingReloadRecommendedLabel == "" then pendingReloadRecommendedLabel = "these changes" end
    pendingReloadRecommendedLabel = Tr(pendingReloadRecommendedLabel)
    M.InstallStaticPopup("MSUF_RELOAD_RECOMMENDED", {
        text = Tr("MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?"),
        button1 = _G.RELOAD or Tr("Reload"),
        button2 = _G.CANCEL or Tr("Not now"),
        OnAccept = function()
            pendingReloadRecommendedLabel = nil
            if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
        end,
        OnCancel = function() pendingReloadRecommendedLabel = nil end,
    })
    _G.StaticPopup_Show("MSUF_RELOAD_RECOMMENDED", pendingReloadRecommendedLabel)
end
ExportPublic("MSUF_ShowReloadRecommendedPopup", ShowReloadRecommendedPopup)
local copyLinkPopup
local copyLinkPopupSerial = 0
local function EnsureCopyLinkPopup()
    if not _G.CreateFrame then return nil end
    if copyLinkPopup then
        copyLinkPopup:Hide()
        copyLinkPopup = nil
    end
    copyLinkPopupSerial = copyLinkPopupSerial + 1
    local frame = _G.CreateFrame("Frame", "MSUF_CopyLinkPopup" .. tostring(copyLinkPopupSerial), _G.UIParent, "BackdropTemplate")
    frame:SetSize(420, 150)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.90)
        frame:SetBackdropBorderColor(0.10, 0.10, 0.10, 0.90)
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText(Tr("Link"))
    frame._msufTitleFS = title
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText(Tr("Press Ctrl+C to copy:"))
    hint:SetTextColor(0.90, 0.90, 0.90, 1)
    local editBox = _G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetSize(360, 32)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    if editBox.SetTextInsets then editBox:SetTextInsets(8, 8, 0, 0) end
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)
    frame._msufEditBox = editBox
    local ok = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ok:EnableMouse(true)
    ok:Enable()
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    ok:SetText(_G.OKAY or Tr("Okay"))
    ok:RegisterForClicks("LeftButtonUp")
    ok:SetScript("OnClick", function() frame:Hide() end)
    frame._msufOkButton = ok
    if type(_G.MSUF_SkinButton) == "function" then _G.MSUF_SkinButton(ok) end
    frame:SetScript("OnShow", function(self)
        if self._msufTitleFS then self._msufTitleFS:SetText(Tr(self._msufTitle or "Link")) end
        if self._msufEditBox then
            self._msufEditBox:SetText(self._msufUrl or "")
            self._msufEditBox:HighlightText()
            self._msufEditBox:SetFocus()
        end
    end)
    frame:SetScript("OnHide", function(self)
        if self._msufEditBox then
            self._msufEditBox:SetText("")
            self._msufEditBox:ClearFocus()
        end
        if copyLinkPopup == self then copyLinkPopup = nil end
        self._msufTitle = nil
        self._msufUrl = nil
    end)
    frame:Hide()
    copyLinkPopup = frame
    return frame
end
local function ShowCopyLink(title, url)
    local frame = EnsureCopyLinkPopup()
    if not frame then return end
    if frame.SetFrameStrata then frame:SetFrameStrata("FULLSCREEN_DIALOG") end
    if frame.SetFrameLevel then frame:SetFrameLevel(100) end
    frame._msufTitle = tostring(title or "Link")
    frame._msufUrl = tostring(url or "")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    frame:Show()
    if frame.Raise then frame:Raise() end
    if frame._msufEditBox and frame._msufEditBox.EnableMouse then frame._msufEditBox:EnableMouse(true) end
    if frame._msufEditBox and frame._msufEditBox.SetFocus then frame._msufEditBox:SetFocus() end
    if frame._msufEditBox and frame._msufEditBox.HighlightText then frame._msufEditBox:HighlightText() end
    if frame._msufOkButton and frame._msufOkButton.EnableMouse then frame._msufOkButton:EnableMouse(true) end
    if frame._msufOkButton and frame._msufOkButton.Enable then frame._msufOkButton:Enable() end
    if frame._msufOkButton and frame._msufOkButton.Raise then frame._msufOkButton:Raise() end
end
ExportPublic("MSUF_ShowCopyLink", ShowCopyLink)
do
    local version = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
        and _G.C_AddOns.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version")
    local isAlpha = type(version) == "string" and version:lower():find("alpha", 1, true) ~= nil
    if isAlpha then
        M.InstallStaticPopup("MSUF_ALPHA_DISCORD", {
            text = Tr("|cffb088f0MSUF Alpha Build|r\n\nThis is an early Alpha version.\nPlease report bugs and share feedback on our Discord!\n\n|cff7289dahttps://discord.gg/2Gf9b2Wprz|r"),
            button1 = Tr("Copy Discord Link"),
            button2 = _G.CLOSE or Tr("Close"),
            OnAccept = function()
                if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz") end
            end,
        })
    end
end
local pendingMsufScale
local pendingGlobalScale
local pendingDisableScaling
local pendingReloadOnScalingOff
local scaleApplyWatcher
local scaleEvents
local UpdateGlobalScaleEvents
local lastGlobalUiParentScale
local blizzardUiParentScale
local UI_SCALE_1080 = 768 / 1080
local UI_SCALE_1440 = 768 / 1440
local UI_SCALE_4K = 768 / 2160
local UI_SCALE_PRESETS = { ["1080p"] = UI_SCALE_1080, ["1440p"] = UI_SCALE_1440, ["4k"] = UI_SCALE_4K }
local MSUF_SCALE_FRAME_GLOBALS = { "MSUF_PlayerCastbar", "MSUF_TargetCastbar", "MSUF_FocusCastbar", "MSUF_PlayerCastbarPreview", "MSUF_TargetCastbarPreview", "MSUF_FocusCastbarPreview", "MSUF_BossCastbar", "MSUF_BossCastbarPreview" }
local function IsGroupFrameUnitKey(unitKey)
    if type(unitKey) ~= "string" then return false end
    return unitKey:sub(1, 5) == "party" or unitKey:sub(1, 4) == "raid"
end
local function IsGroupFrameScaleEnabled(frame, unitKey)
    if not (frame and (frame._msufGFBuilt or frame._msufGFKind or IsGroupFrameUnitKey(unitKey))) then return true end
    local kind = frame._msufGFKind
    if not kind and IsGroupFrameUnitKey(unitKey) then kind = unitKey:sub(1, 4) == "raid" and "raid" or "party" end
    local gf = MSUF and MSUF.GF
    local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(kind) or nil
    local mode = conf and conf.frameScaleMode or "off"
    return mode == "manual" or mode == "auto"
end
local function CollectMsufScaleFrames()
    local frames, seen = {}, {}
    local function add(frame, unitKey)
        if not frame or seen[frame] then return end
        if not IsGroupFrameScaleEnabled(frame, unitKey) then return end
        if type(frame) == "table" and type(frame.SetScale) == "function" then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    if type(_G.MSUF_UnitFrames) == "table" then
        for unitKey, frame in pairs(_G.MSUF_UnitFrames) do add(frame, unitKey) end
    end
    for i = 1, #MSUF_SCALE_FRAME_GLOBALS do add(_G[MSUF_SCALE_FRAME_GLOBALS[i]]) end
    if type(_G.MSUF_BossCastbars) == "table" then
        for i = 1, 5 do add(_G.MSUF_BossCastbars[i]) end
    end
    for i = 1, 5 do
        add(_G["MSUF_boss" .. i .. "CastBar"])
        add(_G["MSUF_BossCastbarPreview" .. (i == 1 and "" or i)])
    end
    return frames
end
local function GetSavedMsufScale()
    local g = EnsureGeneral()
    return Clamp(tonumber(g.msufUiScale) or tonumber(g.uiScale) or 1, 0.25, 1.5)
end
local function ScheduleUnitframeReanchorAfterScale()
    if _G.MSUF_ScaleReanchorPending then return end
    ExportPublic("MSUF_ScaleReanchorPending", true)
    local function flush()
        ExportPublic("MSUF_ScaleReanchorPending", false)
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            local UF = _G.MSUF_NS and _G.MSUF_NS.UF
            if UF and UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
            return
        end
        if type(_G.MSUF_UpdateAllExternalAnchorProxies) == "function" then _G.MSUF_UpdateAllExternalAnchorProxies() end
        if type(_G.MSUF_ForceReanchorAllUnitFrames_Once) == "function" then
            local previous = _G.MSUF_ExternalAnchorForceReanchor
            ExportPublic("MSUF_ExternalAnchorForceReanchor", true)
            _G.MSUF_ForceReanchorAllUnitFrames_Once(true)
            ExportPublic("MSUF_ExternalAnchorForceReanchor", previous)
        end
    end
    _G.C_Timer.After(0, flush)
end
local EnsureScaleApplyAfterCombat
local ResetGlobalUiScale
local function ApplyMsufScale(scale)
    scale = tonumber(scale)
    if not scale then return end
    scale = Clamp(scale, 0.25, 1.5)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingMsufScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        return
    end
    local frames = CollectMsufScaleFrames()
    for i = 1, #frames do
        frames[i]:SetScale(scale)
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then a3.RefreshEditPreview() end
    ScheduleUnitframeReanchorAfterScale()
end
local function GetCurrentGlobalUiScale()
    if _G.UIParent and _G.UIParent.GetScale then return tonumber(_G.UIParent:GetScale()) end
    return nil
end
local function GetPixelPerfectScale()
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    return UI_SCALE_1440
end
local function ResolveGlobalPresetScale(preset, scale)
    if preset == "pixel" then return GetPixelPerfectScale() end
    return UI_SCALE_PRESETS[preset] or tonumber(scale)
end
local function EnsureGlobalUiScaleTable(g)
    if not g then return nil end
    local ui = type(g.UIScale) == "table" and g.UIScale or nil
    if not ui then
        ui = {}
        g.UIScale = ui
        local preset = g.globalUiScalePreset
        local scale = ResolveGlobalPresetScale(preset, g.globalUiScaleValue) or 1.0
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
        ui.Scale = scale
        ui._migratedFromGlobalPreset_v1 = true
    end
    if ui.Enabled == nil then
        local preset = g.globalUiScalePreset
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
    end
    ui.Enabled = ui.Enabled == true
    ui.Scale = Clamp(tonumber(ui.Scale) or ResolveGlobalPresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0, 0.3, 1.5)
    g.disableScaling = false
    return ui
end
local function SetGlobalUiScaleState(enabled, scale, preset)
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if not ui then return end
    enabled = enabled == true
    ui.Enabled = enabled
    if scale ~= nil then ui.Scale = Clamp(tonumber(scale) or ui.Scale or 1.0, 0.3, 1.5) end
    if enabled then
        g.globalUiScalePreset = preset or g.globalUiScalePreset or "custom"
        g.globalUiScaleValue = ui.Scale
    else
        g.globalUiScalePreset = preset or "auto"
        g.globalUiScaleValue = nil
    end
    if UpdateGlobalScaleEvents then UpdateGlobalScaleEvents() end
end
local function CaptureBlizzardUiScale()
    if blizzardUiParentScale then return end
    local current = GetCurrentGlobalUiScale()
    if current and current > 0 then blizzardUiParentScale = current end
end
local function GetBlizzardCVarScale()
    local useUiScale
    if type(_G.GetCVarBool) == "function" then
        useUiScale = _G.GetCVarBool("useUiScale")
    end
    if useUiScale == nil and type(_G.GetCVar) == "function" then
        useUiScale = tostring(_G.GetCVar("useUiScale")) == "1"
    end
    if useUiScale and type(_G.GetCVar) == "function" then
        local value = tonumber(_G.GetCVar("uiScale"))
        if value and value > 0 then return Clamp(value, 0.3, 2.0) end
    end
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    if blizzardUiParentScale and blizzardUiParentScale > 0 then return Clamp(blizzardUiParentScale, 0.3, 2.0) end
    return nil
end
local function RestoreBlizzardUiScaleOnce()
    if type(_G.UIParent_UpdateScale) == "function" then
        _G.UIParent_UpdateScale()
        return true
    end
    local scale = GetBlizzardCVarScale()
    if scale and _G.UIParent and _G.UIParent.SetScale then
        _G.UIParent:SetScale(scale)
        return true
    end
    return false
end
local function RestoreBlizzardUiScale(silent)
    if BlockConfigCombatLocked(silent) then return false end
    RestoreBlizzardUiScaleOnce()
    _G.C_Timer.After(0, RestoreBlizzardUiScaleOnce)
    _G.C_Timer.After(0.25, RestoreBlizzardUiScaleOnce)
    _G.C_Timer.After(1.0, RestoreBlizzardUiScaleOnce)
    lastGlobalUiParentScale = nil
    if not silent then Print("Global UI scale restored to Blizzard settings.") end
    return true
end
local function WriteBlizzardUiScaleCVar(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return false end
    scale = Clamp(scale, 0.3, 1.5)
    local value = string.format("%.6f", scale)
    local ok = false
    if _G.C_CVar and type(_G.C_CVar.SetCVar) == "function" then
        _G.C_CVar.SetCVar("useUiScale", "1")
        _G.C_CVar.SetCVar("uiScale", value)
        ok = true
    end
    if type(_G.SetCVar) == "function" then
        _G.SetCVar("useUiScale", "1")
        _G.SetCVar("uiScale", value)
        ok = true
    end
    return ok
end
local function GetGlobalUiScaleHandoffValue(g, ui)
    local current = tonumber(GetCurrentGlobalUiScale())
    if current and current > 0 then return Clamp(current, 0.3, 1.5) end
    if not ui and g then ui = EnsureGlobalUiScaleTable(g) end
    local saved = ui and tonumber(ui.Scale)
    if saved and saved > 0 then return Clamp(saved, 0.3, 1.5) end
    if lastGlobalUiParentScale and lastGlobalUiParentScale > 0 then return Clamp(lastGlobalUiParentScale, 0.3, 1.5) end
    return 1.0
end
local function HandOffGlobalUiScaleToBlizzard(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return false end
    scale = Clamp(scale, 0.3, 1.5)
    WriteBlizzardUiScaleCVar(scale)
    if type(_G.UIParent_UpdateScale) == "function" then _G.UIParent_UpdateScale() end
    if _G.UIParent and _G.UIParent.SetScale then _G.UIParent:SetScale(scale) end
    blizzardUiParentScale = scale
    lastGlobalUiParentScale = nil
    return true
end
local function EnforceUIParentScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)
    if not (_G.UIParent and _G.UIParent.SetScale) then return end
    local current = _G.UIParent.GetScale and tonumber(_G.UIParent:GetScale()) or 0
    if abs((current or 0) - scale) > 0.001 then _G.UIParent:SetScale(scale) end
    lastGlobalUiParentScale = scale
end
local function SetGlobalUiScale(scale, silent)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingGlobalScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end
    CaptureBlizzardUiScale()
    EnforceUIParentScale(scale)
    if UpdateGlobalScaleEvents then UpdateGlobalScaleEvents() end
    ScheduleUnitframeReanchorAfterScale()
    if not silent then Print(string.format("Global UI scale set to %.4f", scale)) end
end
ResetGlobalUiScale = function(silent)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingDisableScaling = true
        pendingGlobalScale = nil
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return false
    end
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    local handoff = GetGlobalUiScaleHandoffValue(g, ui)
    HandOffGlobalUiScaleToBlizzard(handoff)
    SetGlobalUiScaleState(false, nil, "auto")
    pendingGlobalScale = nil
    if not silent then Print(string.format("Global UI scale disabled. Blizzard UI scale kept at %d%%.", floor(handoff * 100 + 0.5))) end
    ScheduleUnitframeReanchorAfterScale()
    return true
end
EnsureScaleApplyAfterCombat = function()
    if scaleApplyWatcher or not _G.CreateFrame then return end
    local frame = _G.CreateFrame("Frame")
    scaleApplyWatcher = frame
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        if _G.InCombatLockdown and _G.InCombatLockdown() then return end
        if pendingDisableScaling then
            pendingDisableScaling = nil
            pendingGlobalScale = nil
            ResetGlobalUiScale(true)
        else
            local msufScale = pendingMsufScale
            local globalScale = pendingGlobalScale
            pendingMsufScale = nil
            pendingGlobalScale = nil
            if msufScale then ApplyMsufScale(msufScale) end
            if globalScale then SetGlobalUiScale(globalScale, true) end
        end
        if pendingReloadOnScalingOff then
            pendingReloadOnScalingOff = nil
            if type(_G.ReloadUI) == "function" then
                _G.ReloadUI()
                return
            end
        end
        if not pendingDisableScaling and not pendingMsufScale and not pendingGlobalScale then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnEvent", nil)
            scaleApplyWatcher = nil
        end
    end)
end
local function SetScalingDisabled(disable, silent)
    local g = EnsureGeneral()
    disable = disable == true
    g.disableScaling = false
    if not disable then
        pendingDisableScaling = nil
        return
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingDisableScaling = true
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end
    ResetGlobalUiScale(true)
    pendingDisableScaling = nil
    pendingGlobalScale = nil
    if not silent then Print("Global UI scale disabled. Blizzard keeps the current UI size.") end
end
local function GetDesiredGlobalScaleFromDB()
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if ui and ui.Enabled then return tonumber(ui.Scale) end
    return nil
end
local function EnsureGlobalUiScaleApplied(silent)
    local want = tonumber(GetDesiredGlobalScaleFromDB())
    if want and want > 0 then SetGlobalUiScale(want, silent) end
end
local function ResetStandaloneWindowGeometry(frame, silent)
    local g = EnsureGeneral()
    g.flashFullW = 900
    g.flashFullH = 700
    g.flashFullPoint = "CENTER"
    g.flashFullRelPoint = "CENTER"
    g.flashFullX = -60
    g.flashFullY = 10
    local uiScale = (_G.UIParent and _G.UIParent.GetScale and _G.UIParent:GetScale()) or 1
    if not uiScale or uiScale == 0 then uiScale = 1 end
    g.flashFullXpx = -60 * uiScale
    g.flashFullYpx = 10 * uiScale
    g.msuf2WindowW = 900
    g.msuf2WindowH = 700
    g.slashMenuScale = 1.0
    local win = frame or _G.MSUF_StandaloneOptionsWindow or (_G.MSUF2 and _G.MSUF2.frame)
    if win then
        local scale = 1.0
        if _G.MSUF2 and type(_G.MSUF2.GetEffectiveMenuScale) == "function" then scale = _G.MSUF2.GetEffectiveMenuScale(1.0) end
        if win.SetScale then win:SetScale(scale) end
        if win.SetSize then win:SetSize(900, 700) end
        if win.ClearAllPoints then win:ClearAllPoints() end
        if win.SetPoint then win:SetPoint("CENTER", _G.UIParent, "CENTER", -60, 10) end
    end
    if not silent then Print("MSUF menu size reset to default.") end
end
ExportPublic("MSUF_ApplyMsufScale", ApplyMsufScale)
ExportPublic("MSUF_GetSavedMsufScale", GetSavedMsufScale)
ExportPublic("MSUF_SetScalingDisabled", SetScalingDisabled)
if type(_G.MSUF_SetGlobalUiScale_GATED) == "function" then
    ExportPublic("MSUF_SetGlobalUiScale_RAW", SetGlobalUiScale)
    ExportPublic("MSUF_SetGlobalUiScale", _G.MSUF_SetGlobalUiScale_GATED)
else
    ExportPublic("MSUF_SetGlobalUiScale", SetGlobalUiScale)
end
ExportPublic("MSUF_ResetGlobalUiScale", ResetGlobalUiScale)
ExportPublic("MSUF_RestoreBlizzardUiScale", RestoreBlizzardUiScale)
ExportPublic("MSUF_ResetStandaloneWindowGeometry", ResetStandaloneWindowGeometry)
ExportPublic("MSUF_GetPixelPerfectScale", GetPixelPerfectScale)
if type(_G.MSUF_InstallGlobalScaleGate) == "function" then _G.MSUF_InstallGlobalScaleGate() end
local function ApplySavedScaleState(applyGlobalCVar)
    ApplyMsufScale(GetSavedMsufScale())
    local want = GetDesiredGlobalScaleFromDB()
    if want then
        if applyGlobalCVar then SetGlobalUiScale(want, true) end
        EnsureGlobalUiScaleApplied(true)
    end
end
UpdateGlobalScaleEvents = function()
    if not _G.CreateFrame then return end
    local enabled = (tonumber(GetDesiredGlobalScaleFromDB()) or 0) > 0
    if enabled then
        if not scaleEvents then
            scaleEvents = _G.CreateFrame("Frame")
            scaleEvents:SetScript("OnEvent", function(_, event)
                ApplySavedScaleState(event == "PLAYER_LOGIN")
            end)
        end
        if not scaleEvents._msuf2Registered then
            scaleEvents._msuf2Registered = true
            scaleEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
        end
    elseif scaleEvents and scaleEvents._msuf2Registered then
        scaleEvents._msuf2Registered = nil
        scaleEvents:UnregisterEvent("PLAYER_ENTERING_WORLD")
        scaleEvents:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
end
local startupScaleApplyQueued
local startupScaleNeedsGlobalCVar
local function QueueStartupScaleApply(applyGlobalCVar)
    startupScaleNeedsGlobalCVar = startupScaleNeedsGlobalCVar or applyGlobalCVar == true
    if startupScaleApplyQueued then return end
    startupScaleApplyQueued = true
    local function flush()
        local needsGlobalCVar = startupScaleNeedsGlobalCVar
        startupScaleApplyQueued = nil
        startupScaleNeedsGlobalCVar = nil
        ApplySavedScaleState(needsGlobalCVar)
    end
    _G.C_Timer.After(0, flush)
end
QueueStartupScaleApply(true)
local startupScaleEvents = _G.CreateFrame("Frame")
startupScaleEvents:RegisterEvent("PLAYER_LOGIN")
startupScaleEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
startupScaleEvents:SetScript("OnEvent", function(self, event)
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    QueueStartupScaleApply(event == "PLAYER_LOGIN")
    UpdateGlobalScaleEvents()
end)
