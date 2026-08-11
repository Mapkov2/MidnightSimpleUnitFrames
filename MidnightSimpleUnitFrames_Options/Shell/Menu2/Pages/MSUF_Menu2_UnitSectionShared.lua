local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme or {}
local Shared = M.UnitSectionsShared or {}
M.UnitSectionsShared = Shared

-- Shared helpers for Unit page sections.
-- Provides common warning notices, name-anchor filtering, badges, and small UI adapters used
-- by text/status/visual subpages without coupling them to each other's internals.
local CreateFrame = _G.CreateFrame
local pairs = pairs
local tostring = tostring
local type = type
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 }
local WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 }
local WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 }
local function PortableControlToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return token ~= "" and token or (fallback or "control")
end
local function SharedControlMeta(opts, suffix, classification)
    if type(opts) ~= "table" or not opts.controlDomain or not opts.controlPath then return nil end
    local pageKey = PortableControlToken(opts.controlPageKey or M.activeKey, "unknown")
    local domain = PortableControlToken(opts.controlDomain, "shared")
    local path = PortableControlToken(opts.controlPath, "control")
    local tail = PortableControlToken(suffix, "control")
    local semantic = domain .. "." .. path .. "." .. tail
    local resolvedClassification = opts.controlClassification or classification or "ephemeral"
    local meta = {
        controlId = "menu2." .. pageKey .. "." .. semantic,
        pageKey = pageKey,
        identityKey = semantic,
        controlPath = semantic:gsub("%.", "/"),
        classification = resolvedClassification,
        settingKey = opts.settingKey,
        actionKey = opts.actionKey,
        actionFixedArgs = opts.actionFixedArgs,
        actionInputArg = opts.actionInputArg,
        assistantSettingKeys = opts.assistantSettingKeys,
        assistantSettingKeyPatterns = opts.assistantSettingKeyPatterns,
        command = opts.controlCommand,
    }
    -- Shared section actions inherit the owning page's live scope; the
    -- identity must not masquerade as a static Assistant Registry action.
    return meta
end
local function RegisterSharedControl(widget, opts, suffix, label, kind, classification)
    local meta = SharedControlMeta(opts, suffix, classification)
    if not (widget and meta and type(M.RegisterSearchWidget) == "function") then return widget end
    meta.label, meta.kind = label, kind
    if meta.classification == "setting" or meta.classification == "action" then
        meta.assistantDisposition = opts.assistantDisposition
        meta.assistantDispositionReason = opts.assistantDispositionReason
    end
    M.RegisterSearchWidget(widget, meta)
    return widget
end
local function NotifyGuidedInteraction(widget)
    if type(M.NotifyGuidedTourControlInteraction) == "function" then
        M.NotifyGuidedTourControlInteraction(widget)
    end
end
local function IsNameRelativeAnchor(value)
    return value == "NAMERIGHT" or value == "NAMELEFT"
end
local DISABLED_NAME_ANCHOR_VALUE_CACHE = setmetatable({}, { __mode = "k" })
function Shared.DisabledNameAnchorValues(values)
    if type(values) ~= "table" then return {} end
    local cached = DISABLED_NAME_ANCHOR_VALUE_CACHE[values]
    if cached then return cached end
    local out = {}
    for i = 1, #(values or {}) do
        local item = values[i]
        if type(item) == "table" then
            local value = item.value or item.key or item[2] or item[1]
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy.disabled = IsNameRelativeAnchor(value)
            out[#out + 1] = copy
        else
            out[#out + 1] = item
        end
    end
    DISABLED_NAME_ANCHOR_VALUE_CACHE[values] = out
    return out
end
function Shared.SetSectionHeaderStatus(sec, opts)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end
    M.CallIf(T.ApplyCollapseVisual, entry.arrow, entry.hint, entry.open)
    opts = opts or {}
    if W.SetCollapsibleHeaderBaseTone then
        local bg = opts.bg
        W.SetCollapsibleHeaderBaseTone(entry, bg, bg and (bg[4] or 0.48) or nil)
    elseif entry.headerBg and entry.headerBg.SetColorTexture then
        local c = (T.colors and T.colors.coreSurface) or { 0.014, 0.038, 0.072 }
        entry.headerBg:SetColorTexture(c[1], c[2], c[3], entry.open and 0.40 or 0.34)
        if opts.bg then
            local bg = opts.bg
            entry.headerBg:SetColorTexture(bg[1] or 0.035, bg[2] or 0.075, bg[3] or 0.157, bg[4] or 0.48)
        end
    end
    if entry.label and entry.label.SetTextColor and T and T.colors and T.colors.text then
        local c = T.colors.text
        entry.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if opts.labelColor and entry.label and entry.label.SetTextColor then
        local c = opts.labelColor
        entry.label:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if entry.hint and entry.hint.SetText then
        if opts.hint ~= nil then
            entry.hint:SetText(opts.hint)
            if opts.hintColor and entry.hint.SetTextColor then
                local c = opts.hintColor
                entry.hint:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
        else
            M.CallIf(T.ApplyCollapseVisual, entry.arrow, entry.hint, entry.open)
        end
    end
end
function Shared.CreateSectionNotice(sec, topY, buttonLabel, buttonWidth, gateKey)
    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 16, topY)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, topY)
    notice:SetHeight(24)
    gateKey = gateKey or "_msuf2UnitFrameGateAlwaysEnabled"
    notice[gateKey] = true
    local bg = notice:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local coreShadow = (T.colors and T.colors.coreShadow) or { 0.006, 0.016, 0.032 }
    local coreSurface = (T.colors and T.colors.coreSurface) or { 0.014, 0.038, 0.072 }
    local coreBlue = (T.colors and T.colors.coreBlue) or { 0.095, 0.360, 0.560 }
    bg:SetColorTexture(coreShadow[1], coreShadow[2], coreShadow[3], 0.30)
    local top = notice:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(coreBlue[1], coreBlue[2], coreBlue[3], 0.42)
    local bottom = notice:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(coreSurface[1], coreSurface[2], coreSurface[3], 0.48)
    local text = T.Font(notice, "GameFontDisableSmall", "", T.colors.dim)
    text:SetPoint("LEFT", notice, "LEFT", 12, 0)
    text:SetJustifyH("LEFT")
    local button
    if buttonLabel and buttonLabel ~= "" then
        button = (W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, buttonLabel, buttonWidth or 92, 20))) or T.Button(notice, buttonLabel, buttonWidth or 92, 20)
        button:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
        button[gateKey] = true
        text:SetPoint("RIGHT", notice, "RIGHT", -(buttonWidth or 92) - 20, 0)
    else
        text:SetPoint("RIGHT", notice, "RIGHT", -12, 0)
    end
    function notice:SetTone(kind)
        if kind == "warning" then
            bg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
            top:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
            bottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])
            if text.SetTextColor then text:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4]) end
        else
            bg:SetColorTexture(coreShadow[1], coreShadow[2], coreShadow[3], 0.30)
            top:SetColorTexture(coreBlue[1], coreBlue[2], coreBlue[3], 0.42)
            bottom:SetColorTexture(coreSurface[1], coreSurface[2], coreSurface[3], 0.48)
            if text.SetTextColor and T.colors and T.colors.dim then text:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1) end
        end
    end
    function notice:SetMessage(message, tone)
        self:SetTone(tone)
        text:SetText(tostring(message or ""))
    end
    notice:Hide()
    return notice, text, button
end
local COPY_POPUP_TARGET_STYLE = {
    bg = T.colors and { T.colors.coreShadow[1], T.colors.coreShadow[2], T.colors.coreShadow[3], 0.96 } or { 0.006, 0.016, 0.032, 0.96 },
    border = T.colors and { T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.72 } or { 0.026, 0.070, 0.110, 0.72 },
    textColor = { 0.76, 0.86, 0.98, 1 },
    hoverBg = T.colors and { T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], 0.98 } or { 0.014, 0.038, 0.072, 0.98 },
    hoverBorder = T.colors and { T.colors.coreBlue[1], T.colors.coreBlue[2], T.colors.coreBlue[3], 0.60 } or { 0.095, 0.360, 0.560, 0.60 },
    activeBg = T.colors and { T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3], 0.98 } or { 0.014, 0.038, 0.072, 0.98 },
    activeBorder = T.colors and { T.colors.coreBlue[1], T.colors.coreBlue[2], T.colors.coreBlue[3], 0.60 } or { 0.095, 0.360, 0.560, 0.60 },
    activeTextColor = { 0.88, 0.94, 1.00, 1 },
    stripe = false,
}
local function CopyPopupButton(parent, text, width, role)
    local btn
    if role == "target" then
        btn = W.TopButton(parent, text, width, 24, COPY_POPUP_TARGET_STYLE, false)
    elseif W.RoleButton then
        btn = W.RoleButton(parent, text, role == "danger" and "danger" or (role == "action" and "primary" or "normal"), width, 24)
    else
        btn = W.TopButton(parent, text, width, 24, nil, false)
    end
    btn:SetHeight(24)
    -- Popup chrome and selectors only edit transient menu state. Let their
    -- callbacks run in combat so the owning copy action can report its own
    -- blocked result instead of being swallowed by T.Button's generic proxy.
    -- The mutating callbacks still go through RunWithHistory/BlockCombatAction.
    btn._msuf2AllowCombatClick = true
    btn._msuf2SkipHistoryCheckpoint = true
    return btn
end
-- Category switches flow top-to-bottom into a fixed number of columns. Pages keep
-- adding categories, so the grid has to grow rows instead of wrapping back onto
-- column 1 -- the old "column 1 once past rowsPerColumn" rule stacked entry 11 on
-- top of entry 6 (the last category drawn over Castbar on the Unit page). Grow the
-- panel with it so the last row still clears the All/None/run footer.
local COPY_POPUP_CATEGORY_FOOTER = 66
local function CopyPopupCategoryLayout(opts, count)
    local columns = math.max(1, tonumber(opts.categoryColumns) or 2)
    local rows = math.max(1, tonumber(opts.categoryRowsPerColumn) or 5)
    if count > rows * columns then rows = math.ceil(count / columns) end
    local topY = tonumber(opts.categoryY) or -110
    local rowHeight = tonumber(opts.categoryRowHeight) or 28
    local height = math.max(tonumber(opts.height) or 276, math.abs(topY) + (rows - 1) * rowHeight + COPY_POPUP_CATEGORY_FOOTER)
    return rows, topY, rowHeight, height
end
function Shared.MakeScopeCopyPopup(anchorButton, opts)
    -- Unit and group pages both expose a "copy this scope to another scope" popup.
    -- Keep the chrome and checkbox bookkeeping here; callers keep the actual copy action
    -- local so DB writes, history keys, and preview refreshes stay page-specific.
    opts = opts or {}
    local popup
    local categories = opts.categories or {}
    local scopes = opts.scopes or {}
    local targets = opts.targets or {}
    local targetWidths = opts.targetWidths or {}
    local function SourceKey()
        return opts.sourceKey and opts.sourceKey()
    end
    local function TargetWidth(key, button)
        return targetWidths[key] or (button and button.GetWidth and button:GetWidth()) or opts.targetWidth or 48
    end
    local function SyncChecks()
        if not (popup and popup._checks) then return end
        for i = 1, #categories do
            local cat = categories[i]
            if popup._checks[i] then popup._checks[i]:SetChecked(scopes[cat.key] == true) end
        end
    end
    local function SetAll(selected, feedback)
        for i = 1, #categories do
            local cat = categories[i]
            scopes[cat.key] = selected and true or false
            if popup and popup._checks and popup._checks[i] then popup._checks[i]:SetChecked(selected and true or false) end
        end
        if feedback and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr(feedback), "info", 1.15) end
    end
    local function RefreshTargets()
        if not popup then return end
        local source = SourceKey()
        local selected = opts.selectedTarget and opts.selectedTarget(source)
        if popup._title then popup._title:SetText(M.Format(M.Tr(opts.titleFormat or "Copy from %s"), opts.sourceLabel and opts.sourceLabel(source) or tostring(source or ""))) end
        local x = opts.targetX or 16
        for i = 1, #targets do
            local item = targets[i]
            local key = type(item) == "table" and (item.key or item.value) or item
            local btn = popup._targetBtns and popup._targetBtns[key]
            if btn then
                local visible = not opts.isTargetVisible or opts.isTargetVisible(key, source) ~= false
                btn:SetShown(visible)
                if visible then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", popup, "TOPLEFT", x, opts.targetY or -60)
                    x = x + TargetWidth(key, btn) + (opts.targetGap or 6)
                end
                if btn.SetActive then btn:SetActive(selected == key) end
            end
        end
    end
    local api = {}
    function api.GetPopup() return popup end
    function api.Refresh()
        SyncChecks()
        RefreshTargets()
    end
    function api.Hide()
        if popup then popup:Hide() end
    end
    function api.Show(anchor)
        if popup and popup:IsShown() then popup:Hide(); return end
        if not popup then
            local rowsPerColumn, categoryTopY, categoryRowHeight, popupHeight = CopyPopupCategoryLayout(opts, #categories)
            popup = M.CreateMenuPopupPanel(UIParent)
            popup:SetSize(opts.width or 420, popupHeight)
            local title = T.Font(popup, "GameFontNormal", "", T.colors.accent)
            title:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -12)
            popup._title = title
            local close = CopyPopupButton(popup, "x", 20, "danger")
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -8)
            close:SetScript("OnClick", function() popup:Hide() end)
            RegisterSharedControl(close, opts, "close", "Close copy popup", "button", "ephemeral")
            local destLabel = T.Font(popup, "GameFontDisableSmall", M.Tr(opts.targetLabel or "Destination"), T.colors.dim)
            destLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, opts.targetLabelY or -40)
            popup._targetBtns = {}
            for i = 1, #targets do
                local item = targets[i]
                local key = type(item) == "table" and (item.key or item.value) or item
                local label = type(item) == "table" and (item.text or item.label) or nil
                label = label or (opts.targetLabelText and opts.targetLabelText(key)) or tostring(key or "")
                local btn = CopyPopupButton(popup, M.Tr(label), TargetWidth(key), "target")
                btn._msuf2CopyTarget = key
                btn:SetScript("OnClick", function()
                    NotifyGuidedInteraction(btn)
                    if opts.onTargetClick then opts.onTargetClick(key, api, popup) end
                    RefreshTargets()
                end)
                RegisterSharedControl(btn, opts, "target." .. tostring(key), "Copy target " .. tostring(label), "button", opts.runLabel and "ephemeral" or "action")
                popup._targetBtns[key] = btn
            end
            local catLabel = T.Font(popup, "GameFontDisableSmall", M.Tr(opts.categoryLabel or "Copy categories"), T.colors.dim)
            catLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, opts.categoryLabelY or -90)
            popup._checks = {}
            for i = 1, #categories do
                local cat = categories[i]
                local col = math.floor((i - 1) / rowsPerColumn)
                local row = (i - 1) % rowsPerColumn
                local cb = W.SwitchAt(popup, cat.label, 16 + col * (opts.categoryColumnWidth or 198), categoryTopY - row * categoryRowHeight, opts.categoryWidth or 140)
                cb:SetChecked(scopes[cat.key] == true)
                cb:SetScript("OnClick", function(self)
                    NotifyGuidedInteraction(self)
                    scopes[cat.key] = self:GetChecked() and true or false
                end)
                RegisterSharedControl(cb, opts, "category." .. tostring(cat.key), cat.label, "toggle", "ephemeral")
                if cat.description and M.AddTooltip then
                    M.AddTooltip(cb, cat.label, cat.description, { hook = true, titleAsLine = true })
                end
                popup._checks[i] = cb
            end
            local allBtn = CopyPopupButton(popup, M.Tr("All"), 48, "normal")
            allBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 12)
            allBtn:SetScript("OnClick", function()
                NotifyGuidedInteraction(allBtn)
                SetAll(true, opts.allFeedback or "All copy categories selected")
            end)
            RegisterSharedControl(allBtn, opts, "categories.all", "All copy categories", "button", "ephemeral")
            local noneBtn = CopyPopupButton(popup, M.Tr("None"), 58, "normal")
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
            noneBtn:SetScript("OnClick", function()
                NotifyGuidedInteraction(noneBtn)
                SetAll(false, opts.noneFeedback or "Copy categories cleared")
            end)
            RegisterSharedControl(noneBtn, opts, "categories.none", "No copy categories", "button", "ephemeral")
            if opts.runLabel then
                local runBtn = CopyPopupButton(popup, M.Tr(opts.runLabel), opts.runWidth or 128, "action")
                runBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 12)
                runBtn:SetScript("OnClick", function()
                    NotifyGuidedInteraction(runBtn)
                    if opts.onRun then opts.onRun(api, popup) end
                end)
                RegisterSharedControl(runBtn, opts, "run", opts.runLabel, "button", "action")
                popup._runBtn = runBtn
            end
            if type(opts.onPopupCreated) == "function" then opts.onPopupCreated(popup, api) end
        end
        api.Refresh()
        M.ApplyPopupFramePriority(popup)
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", anchor or anchorButton, "BOTTOMRIGHT", 0, -8)
        popup:Show()
    end
    return api
end
function Shared.MakeTabFrame(parent, key, topOffset, width, store)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topOffset or -118)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 12)
    frame._msuf2Width = width
    if store and key then store[key] = frame end
    return frame
end
function Shared.MakeTabFrames(parent, topOffset, width, store, ...)
    local frames = {}
    for i = 1, select("#", ...) do frames[i] = Shared.MakeTabFrame(parent, select(i, ...), topOffset, width, store) end
    return (table.unpack or _G.unpack)(frames)
end
function Shared.PlaceDropdown(parent, control, x, y, width) return W.MoveWidget(control, parent, x, y, width or 200, "LEFT") end
function Shared.PlaceSlider(parent, control, x, y, width) W.MoveWidget(control, parent, x, y, width, "CENTER") end
function Shared.TextCard(parent, title, subtitle, x, y, width, height)
    return W.ControlCard(parent, title, subtitle, x, y, width, height)
end
function Shared.PreviewText(parent, text, x, y, width, color)
    local label = W.Text(parent, "Preview", x, y, width, color or T.colors.dim)
    local value = T.Font(parent, "GameFontNormalSmall", text, T.colors.text)
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
    value:SetWidth(width or 220)
    value:SetJustifyH("LEFT")
    return label, value
end
function Shared.TextBadgeValue(value)
    return tostring(value or ""):gsub("%s*/%s*", " + ")
end
function Shared.TextBadgeNumber(value)
    value = tonumber(value) or 0
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end
local HEALTH_ABSORB_BASE = {
    CURRENTABSORB = "CURRENT", FULLVALUEABSORB = "FULLVALUE", MAXABSORB = "MAX", DEFICITABSORB = "DEFICIT",
    CURMAXABSORB = "CURMAX", PERCENTABSORB = "PERCENT", CURPERCENTABSORB = "CURPERCENT",
    CURMAXPERCENTABSORB = "CURMAXPERCENT", MAXPERCENTABSORB = "MAXPERCENT",
    PERCENTCURABSORB = "PERCENTCUR", PERCENTMAXABSORB = "PERCENTMAX", PERCENTCURMAXABSORB = "PERCENTCURMAX",
}
local HEALTH_ABSORB_MODE = {}
for mode, base in pairs(HEALTH_ABSORB_BASE) do HEALTH_ABSORB_MODE[base] = mode end
function Shared.HealthBaseMode(mode)
    if mode == "ABSORB" then return "NONE" end
    return HEALTH_ABSORB_BASE[mode] or mode or "NONE"
end
function Shared.HealthModeHasAbsorb(mode)
    return mode == "ABSORB" or HEALTH_ABSORB_BASE[mode] ~= nil
end
function Shared.HealthModeSupportsAbsorb(mode)
    local base = Shared.HealthBaseMode(mode)
    return base == "NONE" or HEALTH_ABSORB_MODE[base] ~= nil
end
function Shared.HealthModeWithAbsorb(mode, enabled)
    local base = Shared.HealthBaseMode(mode)
    if enabled ~= true then return base end
    if base == "NONE" then return "ABSORB" end
    return HEALTH_ABSORB_MODE[base] or base
end
function Shared.HealthBaseModeValues(values)
    local filtered = {}
    for i = 1, #(values or {}) do
        local item = values[i]
        local value = item and (item.value or item.key)
        if value ~= "ABSORB" and HEALTH_ABSORB_BASE[value] == nil then filtered[#filtered + 1] = item end
    end
    return filtered
end
function Shared.MakeTextSlotState(owner, scopeKeyFn, slotTableName, moveTableName)
    -- Unit and group text pages both keep transient UI state for the selected text slot
    -- and for the "move all slots together" toggle. Keep the storage names explicit so
    -- callers preserve their existing SavedVariables-free behaviour and focus routing.
    owner = owner or M
    owner[slotTableName] = owner[slotTableName] or {}
    owner[moveTableName] = owner[moveTableName] or {}
    local function ScopeKey()
        local key = scopeKeyFn and scopeKeyFn()
        return key or "default"
    end
    local state = {}
    function state.CurrentSlot(kind)
        local byScope = owner[slotTableName][ScopeKey()]
        local slot = byScope and byScope[kind] or "center"
        return (slot == "left" or slot == "center" or slot == "right") and slot or "center"
    end
    function state.SetCurrentSlot(kind, slot)
        local key = ScopeKey()
        owner[slotTableName][key] = owner[slotTableName][key] or {}
        owner[slotTableName][key][kind] = slot or "center"
    end
    function state.SlotOffsetKeys(kind)
        return M.TextSlotOffsetKeys(kind, state.CurrentSlot(kind))
    end
    function state.SlotFontSizeKey(kind)
        return M.TextSlotFontSizeKey(kind, state.CurrentSlot(kind))
    end
    function state.MoveTogether(kind)
        local byScope = owner[moveTableName][ScopeKey()]
        local value = byScope and byScope[kind]
        if value == nil then return true end
        return value == true
    end
    function state.SetMoveTogether(kind, value)
        local key = ScopeKey()
        owner[moveTableName][key] = owner[moveTableName][key] or {}
        owner[moveTableName][key][kind] = value ~= false
    end
    return state
end
function Shared.TextSlotSummary(kind, slotsByKind, readValue, modeValues, optionText)
    local slots = slotsByKind and slotsByKind[kind]
    for i = 1, #(slots or {}) do
        local slot = slots[i]
        local value = readValue and readValue(slot)
        if value and value ~= "NONE" then
            local slotText = slot[1]:sub(1, 1):upper() .. slot[1]:sub(2)
            return slotText .. ": " .. Shared.TextBadgeValue(optionText(modeValues, value))
        end
    end
    return "No slot text"
end
function Shared.ValueTextControlSets(kind, controls, layer, hookControls, currentSlot)
    controls = controls or {}
    local delimiter = controls.delimiter or controls.separator
    local function CurrentSlotFocus() return currentSlot and currentSlot(kind) end
    local hookSpecs = {}
    local function AddHook(control, focus)
        if control then hookSpecs[#hookSpecs + 1] = { control, focus } end
    end
    AddHook(controls.show)
    AddHook(controls.left, "left"); AddHook(controls.center, "center"); AddHook(controls.right, "right")
    AddHook(controls.leftHidePercent, "left"); AddHook(controls.centerHidePercent, "center"); AddHook(controls.rightHidePercent, "right")
    AddHook(controls.mode, CurrentSlotFocus); AddHook(controls.hidePercent, CurrentSlotFocus); AddHook(controls.absorb, CurrentSlotFocus)
    AddHook(delimiter); AddHook(controls.moveTogether)
    AddHook(controls.slot, CurrentSlotFocus); AddHook(controls.slotSize, CurrentSlotFocus)
    AddHook(controls.size); AddHook(layer)
    local textControls = {}
    local function AddControl(control)
        if control then textControls[#textControls + 1] = control end
    end
    AddControl(controls.left); AddControl(controls.center); AddControl(controls.right)
    AddControl(controls.leftHidePercent); AddControl(controls.centerHidePercent); AddControl(controls.rightHidePercent)
    AddControl(controls.mode); AddControl(controls.hidePercent); AddControl(controls.absorb); AddControl(controls.slot)
    AddControl(delimiter); AddControl(controls.size); AddControl(controls.slotSize); AddControl(controls.moveTogether); AddControl(layer)
    if controls.reverse then
        hookSpecs[#hookSpecs + 1] = { controls.reverse }
        textControls[#textControls + 1] = controls.reverse
    end
    if hookControls then hookControls(kind, hookSpecs) end
    return textControls, {}
end
function Shared.CustomAnchorEditor(ctx, parent, opts)
    opts = opts or {}
    local x, y, width = opts.x or 14, opts.y or -104, opts.width or 200
    local label = T.Font(parent, "GameFontHighlightSmall", M.Tr(opts.label or "Custom Anchor Frame"), opts.labelColor or { 0.62, 0.74, 0.96, 1 })
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); label:SetJustifyH("LEFT")
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24); box:SetSize(width, 24); box:SetAutoFocus(false)
    box:SetMaxLetters(opts.maxLetters or 100); box:SetJustifyH("LEFT")
    box._msuf2Title, box._msuf2ControlKind = label, "textinput"
    M.CallIf(T.SkinEditBox, box)
    local function Attach(widget) if opts.attachFocus then opts.attachFocus(widget) end end
    Attach(box)
    local function Refresh()
        if box and not box:HasFocus() then box:SetText((opts.getValue and opts.getValue()) or "") end
    end
    local function WithHistory(title, key, fn)
        M.RunWithHistory(type(title) == "function" and title() or title, type(key) == "function" and key() or key, fn)
    end
    box:SetScript("OnEnterPressed", function(self)
        local value = self:GetText() or ""
        WithHistory(opts.commitTitle or "Set Anchor", opts.commitKey, function() if opts.setValue then opts.setValue(value, "commit") end end)
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) Refresh(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Refresh)
    RegisterSharedControl(box, opts, "value", opts.label or "Custom Anchor Frame", "textinput", "setting")
    local function SmallButton(after, labelText, widthText, gap, danger)
        local btn = T.Button(parent, labelText, widthText, 24)
        if danger and T.SkinDangerButton then btn = T.SkinDangerButton(btn) end; btn:SetPoint("LEFT", after, "RIGHT", gap, 0)
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end; Attach(btn)
        return btn
    end
    local pick = SmallButton(box, opts.pickLabel or "Pick", opts.pickWidth or 50, 6)
    pick:SetScript("OnClick", function()
        local overlay = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker() or nil
        if not overlay then return end
        overlay._isCandidateAllowed = opts.isCandidateAllowed
        overlay._onPick = function(frameName)
            WithHistory(opts.pickTitle or opts.commitTitle or "Pick Anchor", opts.pickKey or opts.commitKey, function() if opts.setValue then opts.setValue(frameName or "", "pick") end; box:SetText(frameName or "") end)
        end
        overlay:Show()
    end)
    RegisterSharedControl(pick, opts, "pick", opts.pickLabel or "Pick", "button", "action")
    local clear = SmallButton(pick, opts.clearLabel or "Clear", opts.clearWidth or 50, 4, true)
    clear:SetScript("OnClick", function() if opts.clearValue then opts.clearValue() elseif opts.setValue then opts.setValue("", "clear") end; box:SetText("") end)
    RegisterSharedControl(clear, opts, "clear", opts.clearLabel or "Clear", "button", "action")
    M.TrackRefresh(ctx, Refresh)
    return { label = label, box = box, pick = pick, clear = clear, Refresh = Refresh }
end
function Shared.MakeDragSortRows(parent, defs, opts)
    opts = opts or {}
    defs = defs or {}
    local rowW, rowH, rowGap = opts.width or 220, opts.rowHeight or 22, opts.gap or 4
    local rowCount = opts.maxRows or #defs
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, opts.y or 0)
    holder:SetSize(rowW, rowCount * (rowH + rowGap))
    holder.rows, holder._enabled, holder._activeCount = {}, true, rowCount
    local function SlotY(slot) return -((slot - 1) * (rowH + rowGap)) end
    function holder:SnapRows()
        local active = self._activeCount or rowCount
        for i = 1, #self.rows do
            local row = self.rows[i]
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, SlotY(row.slotIndex))
            if row.frame._numText then row.frame._numText:SetText(tostring(row.slotIndex)) end
            if i <= active then row.frame:Show() else row.frame:Hide() end
        end
        self:SetHeight(active * (rowH + rowGap))
    end
    function holder:SetActiveCount(count)
        self._activeCount = math.max(0, math.min(rowCount, tonumber(count) or rowCount))
        self:SnapRows()
    end
    function holder:SetRowsEnabled(enabled)
        self._enabled = enabled and true or false
        for i = 1, #self.rows do
            local row = self.rows[i]
            local frame = row.frame
            frame:SetAlpha(self._enabled and (opts.enabledAlpha or 1) or (opts.disabledAlpha or 0.42))
            frame:EnableMouse(self._enabled)
            if frame._label and frame._label.SetTextColor then
                local c = self._enabled and (opts.enabledLabelColor or T.colors.text) or (opts.disabledLabelColor or T.colors.dim)
                frame._label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
    local function DragAllowed(row) return holder._enabled and (not opts.dragAllowed or opts.dragAllowed(row, holder) ~= false) end
    local function OnEnter(self)
        local row = self._msuf2DragRow
        if not DragAllowed(row) then return end
        if self.SetBackdropBorderColor then
            local c = opts.hoverBorder or (T.colors and T.colors.coreBlue) or { 0.095, 0.360, 0.560, 0.95 }
            self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
        if opts.tooltip and _G.GameTooltip then opts.tooltip(self, row, _G.GameTooltip) end
    end
    local function OnLeave(self)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        if self.SetBackdropBorderColor then
            local c = opts.border or { 0.210, 0.230, 0.300, 0.78 }
            self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    local function OnDragStart(self)
        local row = self._msuf2DragRow
        if not DragAllowed(row) then return end
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        self._msuf2OldStrata = self.GetFrameStrata and self:GetFrameStrata() or nil
        if self.SetFrameStrata then self:SetFrameStrata("TOOLTIP") end
        self:StartMoving()
    end
    local function OnDragStop(self)
        local row = self._msuf2DragRow
        if not row then return end
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        if self.SetFrameStrata and self._msuf2OldStrata then self:SetFrameStrata(self._msuf2OldStrata) end
        local _, centerY = self:GetCenter()
        local top = holder:GetTop()
        local active, bestSlot, bestDist = holder._activeCount or rowCount, 1, math.huge
        if centerY and top then
            for slot = 1, active do
                local dist = math.abs(centerY - (top + SlotY(slot) - (rowH * 0.5)))
                if dist < bestDist then bestDist, bestSlot = dist, slot end
            end
        end
        local changed = row.slotIndex ~= bestSlot
        if changed then
            for i = 1, #holder.rows do
                if holder.rows[i] ~= row and holder.rows[i].slotIndex == bestSlot then
                    holder.rows[i].slotIndex = row.slotIndex
                    break
                end
            end
            row.slotIndex = bestSlot
        end
        holder:SnapRows()
        if (changed or opts.saveAlways) and opts.onReorder then opts.onReorder(holder.rows, holder) end
    end
    for i = 1, rowCount do
        local def = defs[i] or {}
        local frame = CreateFrame("Frame", nil, holder, T.Template and T.Template() or nil)
        frame:SetSize(rowW, rowH)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if frame.SetBackdrop then
            local bg, border = opts.bg or { 0.055, 0.060, 0.075, 0.88 }, opts.border or { 0.210, 0.230, 0.300, 0.78 }
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end
        local stripe = frame:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("LEFT", frame, "LEFT", 2, 0)
        stripe:SetSize(4, rowH - 2)
        stripe:SetColorTexture(def.r or 0.30, def.g or 0.55, def.b or 0.85, 1)
        frame._stripe = stripe
        local label = T.Font(frame, "GameFontHighlightSmall", def.label or "", T.colors.text)
        label:SetPoint("LEFT", stripe, "RIGHT", opts.labelOffsetX or 8, 0)
        label:SetJustifyH("LEFT")
        frame._label = label
        local number = T.Font(frame, "GameFontNormalSmall", tostring(i), T.colors.dim)
        number:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        number:SetJustifyH("RIGHT")
        frame._numText = number
        frame:SetScript("OnEnter", OnEnter)
        frame:SetScript("OnLeave", OnLeave)
        frame:SetScript("OnDragStart", OnDragStart)
        frame:SetScript("OnDragStop", OnDragStop)
        RegisterSharedControl(frame, opts, "row." .. tostring(def.key or i), def.label or tostring(def.key or i), "dragrow", "action")
        local row = { frame = frame, key = def.key or "", slotIndex = i, def = def }
        frame._msuf2DragRow, holder.rows[i] = row, row
    end
    holder:SnapRows()
    return holder
end
