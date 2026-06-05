local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local ControlGates = M.ControlGates or {}
local UP = M.UnitPage or {}

local floor = math.floor
local VT = M.ValueTextList

local UNIT_PAGES, LOAD_CONDITIONS, BOSS_LAYOUT_OPTIONS, SEPARATORS, UF_COPY_CATEGORIES = M.PickDefaults(UP, [[UNIT_PAGES LOAD_CONDITIONS BOSS_LAYOUT_OPTIONS SEPARATORS UF_COPY_CATEGORIES]])
local GetConf, GetGeneral, Call, DefaultCopyTarget, UnitTopLabel, UnitTopPillWidth, NewCopyScopeDefaults, CopyUnitSettings, ToggleEditMode, IsEditModeActive, ReadBool, SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetControlEnabled, NormalizeBossLayoutMode, UpdateLoadActive = M.Pick(UP, [[GetConf GetGeneral Call DefaultCopyTarget UnitTopLabel UnitTopPillWidth NewCopyScopeDefaults CopyUnitSettings ToggleEditMode IsEditModeActive ReadBool SetBool ReadNumber SetNumber ReadGeneralBool SetControlEnabled NormalizeBossLayoutMode UpdateLoadActive]])
local UNIT_AURAS_MENU_UNITS = {
    player = true,
    target = true,
    focus = true,
    boss = true,
}

local TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOT_INLINE_CUSTOM_SEPARATOR_MAX = 5
local TOT_INLINE_COLOR_AUTO = "AUTO"
local TOT_INLINE_COLOR_TOT_NAME = "TOT_NAME"
local TOT_INLINE_COLOR_TARGET_NAME = "TARGET_NAME"
local TOT_INLINE_COLOR_NPC = "NPC"
local TOT_INLINE_COLOR_DEFAULT = "DEFAULT"
local TOT_INLINE_COLOR_VALUES = {
    [TOT_INLINE_COLOR_AUTO] = true,
    [TOT_INLINE_COLOR_TOT_NAME] = true,
    [TOT_INLINE_COLOR_TARGET_NAME] = true,
    [TOT_INLINE_COLOR_NPC] = true,
    [TOT_INLINE_COLOR_DEFAULT] = true,
}
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_ARROW = { 0.88, 0.62, 0.22, 1 }
local WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 }
local WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 }
local WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 }
local WARNING_BADGE_FILL = { 0.205, 0.148, 0.080, 0.96 }
local WARNING_BADGE_EDGE = { 0.52, 0.39, 0.18, 0.78 }
local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
local TOT_INLINE_SEPARATOR_VALUES = {}
local TOT_INLINE_SEPARATOR_OPTIONS = {}

for i = 1, #SEPARATORS do
    local item = SEPARATORS[i]
    local value = item and item.value
    TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = item
    if value ~= nil then
        TOT_INLINE_SEPARATOR_VALUES[value == "" and " " or value] = true
    end
end
TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = { value = TOT_INLINE_CUSTOM_SEPARATOR, text = "Custom" }

local function CleanToTInlineCustomSeparator(value) return M.CleanToTInlineCustomSeparator(value, TOT_INLINE_CUSTOM_SEPARATOR_MAX) end

local function ToTInlineSeparatorDropdownValue(conf)
    local token = conf and conf.totInlineSeparator
    if token == TOT_INLINE_CUSTOM_SEPARATOR then return TOT_INLINE_CUSTOM_SEPARATOR end
    if type(token) == "string" and token ~= "" then
        return TOT_INLINE_SEPARATOR_VALUES[token] and (token == " " and "" or token) or TOT_INLINE_CUSTOM_SEPARATOR
    end
    return "|"
end

local function NormalizeToTInlineColorMode(value)
    value = tostring(value or "")
    if TOT_INLINE_COLOR_VALUES[value] then return value end
    return TOT_INLINE_COLOR_AUTO
end

local function ToTInlineColorDropdownValue(conf)
    return NormalizeToTInlineColorMode(conf and conf.totInlineColorMode)
end


local function ToTInlineNPCColorAvailable()
    local fn = _G.MSUF_UFCore_IsToTInlineNPCColorModeAvailable
    if type(fn) == "function" then return fn() == true end

    local db = _G.MSUF_DB
    local gen = db and db.general
    local wantNpc = gen and gen.npcNameRed
    local conf = GetConf("targettarget")
    if conf and conf.fontOverride and conf.npcNameRed ~= nil then
        wantNpc = conf.npcNameRed
    end
    if wantNpc ~= true then return false end
    if not gen then return false end
    if gen.npcColorMode ~= "type" then return false end
    if gen.npcTypeColorText == false then return false end
    if gen.npcTypeToT == false then return false end
    return true
end

local function ToTInlineColorOptions()
    local npcAvailable = ToTInlineNPCColorAvailable()
    return {
        { value = TOT_INLINE_COLOR_AUTO, text = "Auto" },
        { value = TOT_INLINE_COLOR_TOT_NAME, text = "ToT Name Color" },
        { value = TOT_INLINE_COLOR_TARGET_NAME, text = "Target Name Color" },
        { value = TOT_INLINE_COLOR_NPC, text = "NPC / Type Color", disabled = not npcAvailable },
        { value = TOT_INLINE_COLOR_DEFAULT, text = "Default (Font Color)" },
    }
end

local function ForEachPageControl(parent, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._msuf2ControlKind and not child._msuf2UnitFrameGateAlwaysEnabled then
            callback(child)
        end
        ForEachPageControl(child, callback)
    end
end

local function ApplyUnitFrameEnabledGate(ctx, unit)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local enabled = ReadBool(unit, "enabled", true)
    local gateKey = "unitFrameEnabled:" .. tostring(unit)
    if ControlGates.Apply then
        ControlGates.Apply(wrapper, gateKey, enabled, { alwaysEnabledFlag = "_msuf2UnitFrameGateAlwaysEnabled" })
        return
    end
    if wrapper._msuf2UnitFrameGateKey == gateKey and wrapper._msuf2UnitFrameGateEnabled == enabled then return end
    wrapper._msuf2UnitFrameGateKey = gateKey
    wrapper._msuf2UnitFrameGateEnabled = enabled
    ForEachPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end

local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus or function() end
local function BuildPreview(ctx, builder, unit)
    local sec = builder:CollapsibleSection("preview", "Hide Preview", 378, true)
    if W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(sec, "Hide Preview", "Show Preview") end

    local previewNote = "Preview updates live here. Use MSUF Edit Mode to drag and place frames."
    if unit == "pet" then
        previewNote = previewNote .. " Pet frames only appear in game while you have an active pet."
    elseif unit == "focus" then
        previewNote = previewNote .. " Focus frames only appear when a focus unit exists."
    elseif unit == "targettarget" then
        previewNote = previewNote .. " Target of Target only appears when your target has a target."
    elseif unit == "focustarget" then
        previewNote = previewNote .. " Focus Target only appears when Focus is enabled and your focus has a target."
    elseif unit == "boss" then
        previewNote = previewNote .. " Boss frames only appear during encounters with boss units."
    end
    W.Text(sec, previewNote, 14, -38, ctx.width - 28, T.colors.muted)

    local createPreview = MSUF.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox
    if not createPreview then
        W.Text(sec, "The shared unit preview module is not loaded.", 14, -70, ctx.width - 28, T.colors.muted)
        return
    end

    local panel, box
    local initialPreviewQueued
    local previewQueueSerial = 0

    local function PreviewHostShown()
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if sec and sec.IsShown and not sec:IsShown() then return false end
        if sec and sec.IsVisible and not sec:IsVisible() then return false end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return false end
        return true
    end

    local function EnsurePreview()
        if box and box.GetParent and box:GetParent() == sec then
            if not PreviewHostShown() then return nil end
            if box.Show then box:Show() end
            return box
        end
        if not PreviewHostShown() then return nil end

        if not panel then
            panel = CreateFrame("Frame", nil, sec)
        elseif panel.SetParent then
            panel:SetParent(sec)
        end
        panel._msufLastApplyKey = unit
        panel._msufGetCurrentKey = function() return unit end
        panel._msufIsFramesTab = function() return true end
        panel._msufAPI = {
            ApplySettingsForKey = function(key)
                key = key or unit
                local UF = MSUF and MSUF.UF
                if UF and UF.Apply then UF.Apply(key) end
            end,
        }
        panel._msufOpenUnitSection = function() end

        box = UP._sharedUnitPreviewBox
        if box and box.Hide then box:Hide() end
        if not box then
            box = createPreview(sec, panel, ctx.width - 28, 292)
            if not box then return nil end
            UP._sharedUnitPreviewBox = box
        else
            box:SetParent(sec)
            box:ClearAllPoints()
            box:SetSize(ctx.width - 28, 292)
            box._msufPanel = panel
        end
        box._msufPanel = panel
        box._msuf2UnitPageHostShown = PreviewHostShown
        box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -70)
        box:Show()
        if box.title and box.title.SetTextColor then
            local c = T.colors.accent
            box.title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        panel.unitPreviewBox = box

        if box.HookScript and not box._msuf2UnitPageShowHooked then
            box._msuf2UnitPageShowHooked = true
            box:HookScript("OnShow", function()
                local hostShown = box._msuf2UnitPageHostShown
                if type(hostShown) == "function" and not hostShown() then return end
                local preview = MSUF.UFPreview
                if type(preview) == "table" and type(preview.RequestRefreshForBox) == "function" then
                    preview.RequestRefreshForBox(box, "MSUF2_UNIT_PAGE_SHOW")
                else
                    Call("MSUF_UFPreview_RequestRefresh", "MSUF2_UNIT_PAGE_SHOW")
                end
            end)
        end

        if W and W.AttachPinnedPreview then
            W.AttachPinnedPreview(sec, box, {
                stateKey = "unitFramePreview",
                title = box.title,
                hint = box.hint,
                left = 14,
                right = 14,
                top = -8,
                pageKey = ctx and ctx.key,
                wrapper = ctx and ctx.wrapper,
            })
        end

        return box
    end

    local function RefreshThisPreview(reason)
        local currentBox = EnsurePreview()
        if not currentBox then return end
        panel._msufLastApplyKey = unit
        local preview = MSUF.UFPreview
        if type(preview) == "table" then
            if type(preview.RequestRefreshForBox) == "function" then
                preview.RequestRefreshForBox(currentBox, reason or "MSUF2_UNIT_PAGE")
                return
            end
            if type(preview.RequestRefresh) == "function" then
                preview.active = currentBox
                preview.RequestRefresh(reason or "MSUF2_UNIT_PAGE")
                return
            end
            preview.active = currentBox
            if type(preview.Refresh) == "function" and currentBox:IsShown() then
                preview.Refresh(currentBox, reason or "MSUF2_UNIT_PAGE")
                return
            end
        end
        Call("MSUF_UFPreview_RequestRefresh", reason or "MSUF2_UNIT_PAGE")
    end

    local function RefreshPreviewState()
        SetSectionHeaderStatus(sec, nil)
        if not PreviewHostShown() then
            previewQueueSerial = previewQueueSerial + 1
            initialPreviewQueued = nil
            return
        end
        if not box and not initialPreviewQueued and _G.C_Timer and _G.C_Timer.After then
            initialPreviewQueued = true
            previewQueueSerial = previewQueueSerial + 1
            local serial = previewQueueSerial
            _G.C_Timer.After(0, function()
                if serial ~= previewQueueSerial then return end
                initialPreviewQueued = nil
                if PreviewHostShown() then RefreshThisPreview("MSUF2_UNIT_PAGE_INITIAL") end
            end)
            return
        end
        RefreshThisPreview("MSUF2_UNIT_PAGE")
    end
    M.SetCollapsibleRefreshState(sec, RefreshPreviewState)
    if sec.HookScript then
        sec:HookScript("OnShow", RefreshPreviewState)
        sec:HookScript("OnHide", function()
            previewQueueSerial = previewQueueSerial + 1
            initialPreviewQueued = nil
        end)
    end
    M.AddRefresher(ctx, RefreshPreviewState)
    RefreshPreviewState()
end

local function BuildTopActions(ctx, builder, unit, label)
    local compactTop = (tonumber(builder.width) or 0) < 600
    local sectionH = compactTop and 72 or 30
    local sec = CreateFrame("Frame", nil, builder.parent)
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, sectionH)
    sec._msuf2Width = builder.width
    builder.y = builder.y - sectionH - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end

    local line = sec:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 4, 1)
    line:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -4, 1)
    line:SetHeight(1)
    line:SetColorTexture(0.22, 0.42, 0.70, 0.42)

    local TOP_BUTTON_STYLE = {
        bg = { 0.022, 0.032, 0.064, 0.94 },
        border = { 0.090, 0.135, 0.250, 0.58 },
        textColor = { 0.78, 0.87, 0.98, 1 },
        hoverBg = { 0.032, 0.046, 0.086, 0.96 },
        hoverBorder = { 0.120, 0.215, 0.405, 0.72 },
        activeBg = { 0.026, 0.038, 0.074, 0.96 },
        activeBorder = { 0.145, 0.270, 0.560, 0.82 },
        activeTextColor = { 0.90, 0.95, 1.00, 1 },
        stripe = false,
    }

    local TOP_ACTION_STYLE = {
        bg = { 0.018, 0.028, 0.058, 0.95 },
        border = { 0.082, 0.125, 0.245, 0.66 },
        textColor = { 0.82, 0.90, 1.00, 1 },
        hoverBg = { 0.026, 0.040, 0.078, 0.97 },
        hoverBorder = { 0.125, 0.220, 0.430, 0.80 },
        activeBg = { 0.018, 0.028, 0.058, 0.95 },
        activeBorder = { 0.082, 0.125, 0.245, 0.66 },
        activeTextColor = { 0.82, 0.90, 1.00, 1 },
    }

    local function MakeTopButton(parent, text, width, active, opts)
        return W.TopButton(parent, text, width, 24, opts or TOP_BUTTON_STYLE, active)
    end

    local editing = T.Font(sec, "GameFontNormalSmall", M.Tr("Editing:"), { 0.72, 0.82, 1.00, 1 })
    editing:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, compactTop and -15 or -6)

    local unitPill = MakeTopButton(sec, UnitTopLabel(unit), UnitTopPillWidth(unit), true, {
        bg = { 0.030, 0.045, 0.092, 0.94 },
        border = { 0.105, 0.170, 0.320, 0.56 },
        textColor = { 0.86, 0.92, 1.00, 1 },
        hoverBg = { 0.036, 0.052, 0.104, 0.96 },
        hoverBorder = { 0.180, 0.330, 0.680, 0.86 },
        activeBg = { 0.030, 0.045, 0.092, 0.96 },
        activeBorder = { 0.205, 0.390, 0.820, 0.92 },
        activeTextColor = { 0.94, 0.98, 1.00, 1 },
    })
    unitPill:SetPoint("LEFT", editing, "RIGHT", 8, 0)
    unitPill:EnableMouse(false)

    local actionY = compactTop and -42 or -2
    local copy = MakeTopButton(sec, M.Tr("Copy To"), compactTop and 82 or 86, false, TOP_ACTION_STYLE)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -8, actionY)

    local edit = MakeTopButton(sec, M.Tr("MSUF Edit Mode"), compactTop and 118 or 128, false, TOP_ACTION_STYLE)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, sec, edit, { width = compactTop and 84 or 88 })
    end

    local function RefreshEditButton()
        local active = IsEditModeActive()
        edit:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode"))
        edit:SetActive(false)
    end

    edit:SetScript("OnClick", function()
        local wasActive = IsEditModeActive()
        ToggleEditMode(unit)
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback(wasActive and M.Tr("Edit mode off") or M.Tr("Edit mode on"), "info", 1.2)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshEditButton)
        else
            RefreshEditButton()
        end
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    local function DefaultScopes()
        if type(NewCopyScopeDefaults) == "function" then return NewCopyScopeDefaults() end
        local t = {}
        for i = 1, #UF_COPY_CATEGORIES do
            local cat = UF_COPY_CATEGORIES[i]
            t[cat.key] = cat.default ~= false
        end
        return t
    end

    M.unitCopyScopes = (type(M.unitCopyScopes) == "table") and M.unitCopyScopes or DefaultScopes()
    local copyScopes = M.unitCopyScopes

    local function NormalizeCopyDest(src)
        local dest = M.unitCopyTarget or (DefaultCopyTarget and DefaultCopyTarget(src)) or "target"
        if dest == src then dest = (DefaultCopyTarget and DefaultCopyTarget(src)) or "target" end
        M.unitCopyTarget = dest
        return dest
    end

    local copyPopup
    local function RefreshCopyPopupTargets()
        if not copyPopup then return end
        local dest = NormalizeCopyDest(unit)
        if copyPopup._title then copyPopup._title:SetText(M.Format(M.Tr("Copy from %s"), UnitTopLabel(unit))) end
        local x = 16
        local order = copyPopup._targetOrder or {}
        local widths = copyPopup._targetWidths or {}
        for i = 1, #order do
            local key = order[i]
            local btn = copyPopup._targetBtns and copyPopup._targetBtns[key]
            if btn then
                local visible = key ~= unit
                btn:SetShown(visible)
                if visible then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", x, -58)
                    x = x + (widths[key] or btn:GetWidth() or 48) + 6
                end
                if btn.SetActive then btn:SetActive(dest == key) end
            end
        end
    end

    local function MakePopupButton(parent, text, width, bg, border, textColor, activeBg, activeBorder)
        local defaultHoverBg = { 0.030, 0.055, 0.120, 0.98 }
        local defaultHoverBorder = { 0.105, 0.205, 0.410, 0.78 }
        local btn = MakeTopButton(parent, text, width, false, {
            bg = bg or { 0.022, 0.040, 0.090, 0.96 },
            border = border or { 0.075, 0.140, 0.290, 0.70 },
            textColor = textColor or { 0.76, 0.85, 0.96, 1 },
            hoverBg = activeBg or defaultHoverBg,
            hoverBorder = activeBorder or defaultHoverBorder,
            activeBg = activeBg or { 0.045, 0.095, 0.205, 0.98 },
            activeBorder = activeBorder or { 0.130, 0.280, 0.560, 0.86 },
            activeTextColor = { 0.88, 0.94, 1.00, 1 },
            stripe = false,
        })
        btn:SetHeight(22)
        return btn
    end

    local function MakeCopyPanel(parent)
        local panel = CreateFrame("Frame", nil, parent, T.Template and T.Template() or nil)
        local glassBg = T.colors.glassPopup or { 0.014, 0.024, 0.050, 0.985 }
        if panel.SetBackdrop then
            panel:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            panel:SetBackdropColor(glassBg[1], glassBg[2], glassBg[3], glassBg[4] or 0.985)
            panel:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
        else
            local bg = panel:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(glassBg[1], glassBg[2], glassBg[3], glassBg[4] or 0.985)
            local edge = panel:CreateTexture(nil, "BORDER")
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
            edge:SetColorTexture(0.10, 0.22, 0.44, 0.80)
        end
        if T.ApplyGlass then T.ApplyGlass(panel, "popup") end
        return panel
    end

    local function ShowCopyPopup(anchor)
        if copyPopup and copyPopup:IsShown() then copyPopup:Hide(); return end
        if not copyPopup then
            copyPopup = MakeCopyPanel(UIParent)
            copyPopup:SetSize(420, 276)
            M.ApplyPopupFramePriority(copyPopup)
            copyPopup:EnableMouse(true)

            local title = T.Font(copyPopup, "GameFontNormal", "", T.colors.accent)
            title:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -12)
            copyPopup._title = title

            local close = MakePopupButton(copyPopup, "x", 20, { 0.070, 0.026, 0.034, 0.94 }, { 0.34, 0.090, 0.110, 0.82 }, { 0.95, 0.70, 0.70, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.42, 0.12, 0.14, 0.90 })
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", copyPopup, "TOPRIGHT", -12, -9)
            close:SetScript("OnClick", function() copyPopup:Hide() end)

            local destLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Destination"), T.colors.dim)
            destLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -40)

            copyPopup._targetBtns = {}
            local order = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet", "all" }
            local widths = { player = 48, target = 50, targettarget = 38, focustarget = 34, focus = 48, boss = 46, pet = 38, all = 38 }
            copyPopup._targetOrder = order
            copyPopup._targetWidths = widths
            local shortLabel = { targettarget = "ToT", focustarget = "FT", boss = M.Tr("Boss"), all = M.Tr("All") }
            local x = 16
            for i = 1, #order do
                local key = order[i]
                local target = MakePopupButton(copyPopup, shortLabel[key] or UnitTopLabel(key), widths[key], { 0.020, 0.048, 0.105, 0.96 }, { 0.070, 0.160, 0.330, 0.72 }, { 0.76, 0.86, 0.98, 1 }, { 0.050, 0.110, 0.240, 0.98 }, { 0.135, 0.300, 0.600, 0.86 })
                target:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", x, -58)
                target._msuf2UnitCopyValue = key
                target:SetScript("OnClick", function()
                    M.unitCopyTarget = key
                    RefreshCopyPopupTargets()
                end)
                copyPopup._targetBtns[key] = target
                x = x + widths[key] + 6
            end

            local catLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Copy categories"), T.colors.dim)
            catLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -90)

            copyPopup._checks = {}
            for i, cat in ipairs(UF_COPY_CATEGORIES) do
                local col = (i > 5) and 1 or 0
                local row = (i - 1) % 5
                local cb = W.SwitchAt(copyPopup, cat.label, 16 + col * 198, -110 - row * 28, 140)
                cb:SetChecked(copyScopes[cat.key] == true)
                cb:SetScript("OnClick", function(self)
                    copyScopes[cat.key] = self:GetChecked() and true or false
                end)
                copyPopup._checks[i] = cb
            end

            local allBtn = MakePopupButton(copyPopup, M.Tr("All"), 48, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            allBtn:SetPoint("BOTTOMLEFT", copyPopup, "BOTTOMLEFT", 16, 12)
            allBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = true
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(true) end
                end
                if M.ShowStatusFeedback then
                    M.ShowStatusFeedback(M.Tr("All copy categories selected"), "info", 1.15)
                end
            end)

            local noneBtn = MakePopupButton(copyPopup, M.Tr("None"), 58, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
            noneBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = false
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(false) end
                end
                if M.ShowStatusFeedback then
                    M.ShowStatusFeedback(M.Tr("Copy categories cleared"), "info", 1.15)
                end
            end)

            local runBtn = MakePopupButton(copyPopup, M.Tr("Copy Selected"), 128, { 0.050, 0.125, 0.270, 0.98 }, { 0.170, 0.350, 0.610, 0.86 }, { 0.88, 0.96, 1, 1 }, { 0.060, 0.150, 0.320, 0.98 }, { 0.210, 0.420, 0.720, 0.90 })
            runBtn:SetPoint("BOTTOMRIGHT", copyPopup, "BOTTOMRIGHT", -14, 11)
            runBtn:SetScript("OnClick", function()
                local dest = NormalizeCopyDest(unit)
                local function RunCopy()
                    CopyUnitSettings(unit, dest, copyScopes)
                end
                if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                    M.CaptureHistory("Copy Unit Settings", "unit:copy:" .. tostring(unit), RunCopy)
                else
                    RunCopy()
                end
                if M.ShowStatusFeedback then
                    M.ShowStatusFeedback(M.Format(M.Tr("Copied to %s"), UnitTopLabel(dest)), "ok", 1.35)
                end
                copyPopup:Hide()
            end)
        end

        for i, cat in ipairs(UF_COPY_CATEGORIES) do
            if copyPopup._checks and copyPopup._checks[i] then
                copyPopup._checks[i]:SetChecked(copyScopes[cat.key] == true)
            end
        end
        RefreshCopyPopupTargets()
        M.ApplyPopupFramePriority(copyPopup)
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("TOPRIGHT", anchor or copy, "BOTTOMRIGHT", 0, -6)
        copyPopup:Show()
    end

    copy:SetScript("OnClick", function(self)
        ShowCopyPopup(self)
    end)

    sec:SetScript("OnHide", function()
        if copyPopup then copyPopup:Hide() end
    end)
end

local function AttachBasicsHeaderStatus(sec, unit)
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    if not sectionEntry then return nil end
    if type(sectionEntry._msuf2BasicsHeaderRefresh) == "function" then
        return sectionEntry._msuf2BasicsHeaderRefresh
    end

    local badge
    local badgeFill
    local badgeEdge
    if sectionEntry.header then
        sectionEntry._msuf2ManualHintLayout = true
        badge = CreateFrame("Frame", nil, sectionEntry.header)
        badge:SetSize(116, 18)
        badgeFill, badgeEdge = T.CreateSuperellipseLayers(badge, "_msuf2DisabledBadge", 1, "ARTWORK", "ARTWORK")
        local badgeLabel = T.Font(badge, "GameFontDisableSmall", M.Tr("Frame disabled"), { 1.00, 0.86, 0.74, 1 })
        badgeLabel:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badgeLabel:SetWidth(104)
        badgeLabel:SetJustifyH("CENTER")
        badge:Hide()

        if sectionEntry.hint then
            sectionEntry.hint:ClearAllPoints()
            sectionEntry.hint:SetPoint("RIGHT", sectionEntry.header, "RIGHT", -12, 0)
            sectionEntry.hint:SetWidth(110)
            sectionEntry.hint:SetJustifyH("RIGHT")
            badge:SetPoint("RIGHT", sectionEntry.hint, "LEFT", -8, 0)
        else
            badge:SetPoint("RIGHT", sectionEntry.header, "RIGHT", -122, 0)
        end
        if sectionEntry.label then
            sectionEntry.label:ClearAllPoints()
            sectionEntry.label:SetPoint("LEFT", sectionEntry.arrow, "RIGHT", 6, 0)
            sectionEntry.label:SetPoint("RIGHT", badge, "LEFT", -10, 0)
            sectionEntry.label:SetJustifyH("LEFT")
        end
    end

    local function RefreshBasicsState()
        T.ApplyCollapseVisual(sectionEntry.arrow, sectionEntry.hint, sectionEntry.open)

        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        local on = ownOn and not parentOff
        if sectionEntry.headerBg then
            if on then
                sectionEntry.headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
            else
                sectionEntry.headerBg:SetColorTexture(WARNING_HEADER_BG[1], WARNING_HEADER_BG[2], WARNING_HEADER_BG[3], WARNING_HEADER_BG[4])
            end
        end
        if sectionEntry.label and sectionEntry.label.SetTextColor then
            if on then
                sectionEntry.label:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3], T.colors.text[4] or 1)
            else
                sectionEntry.label:SetTextColor(0.92, 0.88, 0.82, 1)
            end
        end
        if badge then
            badge:SetShown(not on)
            if not on and badgeFill and badgeEdge then
                badgeFill:SetVertexColor(WARNING_BADGE_FILL[1], WARNING_BADGE_FILL[2], WARNING_BADGE_FILL[3], WARNING_BADGE_FILL[4])
                badgeEdge:SetVertexColor(WARNING_BADGE_EDGE[1], WARNING_BADGE_EDGE[2], WARNING_BADGE_EDGE[3], WARNING_BADGE_EDGE[4])
            end
        end
        if sectionEntry.hint then
            if on then
                sectionEntry.hint:SetText(M.Tr("ON"))
                sectionEntry.hint:SetTextColor(0.52, 0.76, 0.58, 1)
            else
                sectionEntry.hint:SetText(M.Tr("OFF"))
                sectionEntry.hint:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4])
            end
        end
        if sectionEntry.arrow and sectionEntry.arrow.SetVertexColor and not on then
            sectionEntry.arrow:SetVertexColor(WARNING_ARROW[1], WARNING_ARROW[2], WARNING_ARROW[3], WARNING_ARROW[4])
        end
    end

    sectionEntry._msuf2BasicsHeaderRefresh = RefreshBasicsState
    RefreshBasicsState()
    return RefreshBasicsState
end

local function BuildBasics(ctx, builder, unit, label)
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 104, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42

    local enable = W.SwitchAt(sec, "Enable", x1, row1, labelW)
    enable._msuf2UnitFrameGateAlwaysEnabled = true
    M.BindToggle(ctx, enable,
        function() return ReadBool(unit, "enabled", true) end,
        function(v)
            SetBool(unit, "enabled", v, "MSUF2_FRAME_ENABLED", { preview = true })
            if M.RequestRefresh then M.RequestRefresh(ctx, "frame-basics-enabled") elseif M.Refresh then M.Refresh(ctx) end
        end)

    local reverse = W.ToggleAt(sec, "Reverse fill direction", x2, row1, labelW)
    M.BindToggle(ctx, reverse,
        function() return ReadBool(unit, "reverseFillBars", false) end,
        function(v) SetBool(unit, "reverseFillBars", v, "MSUF2_REVERSE_FILL", { preview = true }) end)

    local smooth = W.ToggleAt(sec, "Smooth fill", x3, row1, labelW)
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "smoothFill", true) end,
        function(v) SetBool(unit, "smoothFill", v, "MSUF2_SMOOTH_FILL", { preview = true }) end)
    if W.AttachEditFocus then
        W.AttachEditFocus(enable, unit, "frame", nil, { source = "menu2-unit" })
        W.AttachEditFocus(reverse, unit, "frame", nil, { source = "menu2-unit" })
        W.AttachEditFocus(smooth, unit, "frame", nil, { source = "menu2-unit" })
    end

    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local RefreshBasicsState = AttachBasicsHeaderStatus(sec, unit) or function() end
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end

    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -70)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, -70)
    notice:SetHeight(24)
    notice._msuf2UnitFrameGateAlwaysEnabled = true
    local noticeBg = notice:CreateTexture(nil, "BACKGROUND")
    noticeBg:SetAllPoints()
    noticeBg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
    local noticeEdge = notice:CreateTexture(nil, "BORDER")
    noticeEdge:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    noticeEdge:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    noticeEdge:SetHeight(1)
    noticeEdge:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
    local noticeBottom = notice:CreateTexture(nil, "BORDER")
    noticeBottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    noticeBottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    noticeBottom:SetHeight(1)
    noticeBottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])

    local unitLabel = label or UnitTopLabel(unit)
    local noticeText = T.Font(notice, "GameFontDisableSmall", "", { 0.92, 0.82, 0.72, 1 })
    noticeText:SetPoint("LEFT", notice, "LEFT", 10, 0)
    noticeText:SetPoint("RIGHT", notice, "RIGHT", -122, 0)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetText(unitLabel .. " frame is disabled and will not appear.")

    local enableNow = W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, "Enable", 92, 20)) or T.Button(notice, "Enable", 92, 20)
    enableNow:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
    enableNow._msuf2UnitFrameGateAlwaysEnabled = true
    enableNow:SetScript("OnClick", function()
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then
            SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true })
        end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        if M.RequestRefresh then M.RequestRefresh(ctx, "frame-basics-enable-now") elseif M.Refresh then M.Refresh(ctx) end
    end)
    notice:Hide()

    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        local on = ownOn and not parentOff
        SetControlEnabled(enable, true)
        SetControlEnabled(reverse, ownOn)
        SetControlEnabled(smooth, ownOn)
        if parentOff then
            noticeText:SetText("Focus Target follows the Focus frame. Enable Focus to show it.")
            if enableNow.SetText then enableNow:SetText("Enable Focus") end
        else
            noticeText:SetText(unitLabel .. " frame is disabled and will not appear.")
            if enableNow.SetText then enableNow:SetText("Enable") end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
    end
    M.AddRefresher(ctx, RefreshBasicsEnabled)
    RefreshBasicsEnabled()
end

local function BuildLayout(ctx, builder, unit)
    local sec = builder:CollapsibleSection("anchoring", "Anchoring", 220, false)
    local anchorChoices = VT("GLOBAL", "Global anchor", "EssentialCooldownViewer", "Essential cooldown viewer", "UtilityCooldownViewer", "Utility cooldown viewer", "BuffIconCooldownViewer", "Tracked buffs viewer", "player", "Player frame", "target", "Target frame", "targettarget", "Target of Target frame", "focustarget", "Focus Target frame", "focus", "Focus frame", "pet", "Pet frame")
    local anchorPoints = VT("TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT")
    local standardAnchorValues = {
        GLOBAL = true,
        global = true,
        FREE = true,
        EssentialCooldownViewer = true,
        UtilityCooldownViewer = true,
        BuffIconCooldownViewer = true,
        player = true,
        target = true,
        targettarget = true,
        focustarget = true,
        focus = true,
        pet = true,
    }
    local function CustomAnchorName(conf)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        if custom ~= "" then return custom end
        local raw = conf.anchorToUnitframe
        if type(raw) == "string" and raw ~= "" and standardAnchorValues[raw] ~= true then
            return raw
        end
        return ""
    end
    local function AnchorValues()
        local values = {}
        local conf = GetConf(unit)
        local custom = CustomAnchorName(conf)
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = "Custom: " .. text }
        end
        for i = 1, #anchorChoices do
            local item = anchorChoices[i]
            if item.value == "GLOBAL" or item.value ~= unit then
                values[#values + 1] = item
            end
        end
        return values
    end
    local function AnchorValue()
        local conf = GetConf(unit)
        if CustomAnchorName(conf) ~= "" then return "__CUSTOM" end
        local v = conf.anchorToUnitframe
        if v == "player" or v == "target" or v == "targettarget" or v == "focustarget" or v == "focus" or v == "pet"
            or v == "EssentialCooldownViewer" or v == "UtilityCooldownViewer" or v == "BuffIconCooldownViewer" then return v end
        return "GLOBAL"
    end
    local function AnchorPointValue()
        local point = GetConf(unit).point or "CENTER"
        for i = 1, #anchorPoints do
            if anchorPoints[i].value == point then return point end
        end
        return "CENTER"
    end
    local function ApplyAnchorChange()
        M.RequestUnitApply(unit, "MSUF2_ANCHORING", { preview = true })
    end
    local function PlaceAnchorDropdown(control, x, y, width)
        if not control then return end
        width = width or 200
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("LEFT")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local anchorTo = W.Dropdown(sec, "Anchor To", AnchorValues, 230)
    PlaceAnchorDropdown(anchorTo, 14, -38, 230)
    if W.AttachEditFocus then W.AttachEditFocus(anchorTo, unit, "anchoring", nil, { source = "menu2-unit" }) end
    M.BindDropdown(ctx, anchorTo,
        AnchorValue,
        function(v)
            if v == "__CUSTOM" then return end
            local conf = GetConf(unit)
            conf.anchorToUnitframe = v or "GLOBAL"
            conf.anchorFrameName = nil
            ApplyAnchorChange()
        end)

    local anchorPoint = W.Dropdown(sec, "Anchor Point", anchorPoints, 160)
    PlaceAnchorDropdown(anchorPoint, 284, -38, 160)
    if W.AttachEditFocus then W.AttachEditFocus(anchorPoint, unit, "anchoring", nil, { source = "menu2-unit" }) end
    M.BindDropdown(ctx, anchorPoint,
        AnchorPointValue,
        function(v)
            local conf = GetConf(unit)
            v = v or "CENTER"
            conf.point = v
            conf.relativePoint = v
            ApplyAnchorChange()
        end)

    local customLabel = T.Font(sec, "GameFontHighlightSmall", M.Tr("Custom Anchor Frame"), { 0.62, 0.74, 0.96, 1 })
    customLabel:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -104)
    customLabel:SetJustifyH("LEFT")

    local customBox = CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
    customBox:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -126)
    customBox:SetSize(200, 22)
    customBox:SetAutoFocus(false)
    customBox:SetMaxLetters(100)
    customBox:SetJustifyH("LEFT")
    customBox._msuf2Title = customLabel
    customBox._msuf2ControlKind = "textinput"
    T.SkinEditBox(customBox)
    if W.AttachEditFocus then W.AttachEditFocus(customBox, unit, "anchoring", nil, { source = "menu2-unit" }) end

    local function RefreshCustomAnchorBox()
        if customBox and not customBox:HasFocus() then
            customBox:SetText(CustomAnchorName(GetConf(unit)))
        end
    end

    customBox:SetScript("OnEnterPressed", function(self)
        local value = self:GetText() or ""
        local function CommitCustomAnchor()
            local conf = GetConf(unit)
            conf.anchorFrameName = (value ~= "") and value or nil
            if value ~= "" or CustomAnchorName(conf) ~= "" then
                conf.anchorToUnitframe = "GLOBAL"
            end
            ApplyAnchorChange()
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Set Unit Anchor", "unit:anchorCustom:" .. tostring(unit), CommitCustomAnchor)
        else
            CommitCustomAnchor()
        end
        self:ClearFocus()
    end)
    customBox:SetScript("OnEscapePressed", function(self)
        RefreshCustomAnchorBox()
        self:ClearFocus()
    end)
    customBox:SetScript("OnEditFocusLost", RefreshCustomAnchorBox)

    local pick = T.Button(sec, "Pick", 50, 22)
    pick:SetPoint("LEFT", customBox, "RIGHT", 6, 0)
    T.CenterButtonLabel(pick)
    if W.AttachEditFocus then W.AttachEditFocus(pick, unit, "anchoring", nil, { source = "menu2-unit" }) end
    pick:SetScript("OnClick", function()
        local ensure = _G.MSUF_EnsureAnchorPicker
        local overlay = type(ensure) == "function" and ensure()
        if not overlay then return end
        overlay._onPick = function(frameName)
            local function PickCustomAnchor()
                local conf = GetConf(unit)
                conf.anchorFrameName = frameName
                conf.anchorToUnitframe = "GLOBAL"
                customBox:SetText(frameName or "")
                ApplyAnchorChange()
            end
            if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Pick custom anchor", "unit:anchorPick:" .. tostring(unit), PickCustomAnchor)
            else
                PickCustomAnchor()
            end
        end
        overlay:Show()
    end)

    local clear = T.SkinDangerButton(T.Button(sec, "Clear", 50, 22))
    clear:SetPoint("LEFT", pick, "RIGHT", 4, 0)
    T.CenterButtonLabel(clear)
    clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        if CustomAnchorName(conf) ~= "" then
            conf.anchorToUnitframe = "GLOBAL"
        end
        customBox:SetText("")
        ApplyAnchorChange()
    end)

    local function RefreshLayoutState()
        RefreshCustomAnchorBox()
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
        if anchorPoint.SetValue then anchorPoint:SetValue(AnchorPointValue()) end
        SetSectionHeaderStatus(sec, nil)
    end
    M.SetCollapsibleRefreshState(sec, RefreshLayoutState)
    M.AddRefresher(ctx, RefreshLayoutState)
    RefreshLayoutState()
end

local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end

    local sec = builder:CollapsibleSection("inline_text", "Inline Text", 214, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local rightX = math.max(260, floor(sectionW * 0.52))
    local rightW = math.min(220, math.max(140, sectionW - rightX - 28))
    local RefreshInlineControlState

    W.Text(sec, "Target of Target inline text is shown on the Target frame name line.", 14, -38, sectionW - 28, T.colors.muted)
    sec._msuf2CursorY = -72

    local show = W.Toggle(sec, "Show Target of Target text inline")
    M.BindToggle(ctx, show,
        function() return GetConf("targettarget").showToTInTargetName == true end,
        function(v)
            local conf = GetConf("targettarget")
            conf.showToTInTargetName = v and true or false
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE", { text = true, preview = true })
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local color = W.Dropdown(sec, "Inline color", ToTInlineColorOptions, rightW)
    W.MoveWidget(color, sec, rightX, -72, rightW)
    M.BindDropdown(ctx, color,
        function() return ToTInlineColorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            conf.totInlineColorMode = NormalizeToTInlineColorMode(v)
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_COLOR", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_COLOR", { text = true, preview = true })
            if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate("targettarget") end
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_COLOR")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local sep = W.Dropdown(sec, "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170)
    W.MoveWidget(sep, sec, 14, -124, 170)
    M.BindDropdown(ctx, sep,
        function() return ToTInlineSeparatorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            if v == TOT_INLINE_CUSTOM_SEPARATOR then
                conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(conf.totInlineCustomSeparator)
            else
                conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
            end
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_SEPARATOR", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_SEPARATOR", { text = true, preview = true })
            if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate("targettarget") end
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_SEPARATOR")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local customSep = W.TextInput(sec, "Custom separator", rightW)
    W.MoveWidget(customSep, sec, rightX, -124, rightW)
    if customSep.SetMaxLetters then customSep:SetMaxLetters(TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
    M.BindTextInput(ctx, customSep,
        function()
            local conf = GetConf("targettarget")
            local token = conf and conf.totInlineSeparator
            if token ~= TOT_INLINE_CUSTOM_SEPARATOR and type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token] then
                return CleanToTInlineCustomSeparator(token)
            end
            return CleanToTInlineCustomSeparator(conf and conf.totInlineCustomSeparator)
        end,
        function(v)
            local conf = GetConf("targettarget")
            local token = conf and conf.totInlineSeparator
            local isCustom = token == TOT_INLINE_CUSTOM_SEPARATOR
                or (type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token])
            conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(v)
            if isCustom then
                conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                M.RequestUnitApply("target", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", { text = true, preview = true })
                M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", { text = true, preview = true })
                if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate("targettarget") end
                Call("MSUF_UpdateTargetToTInlineNow")
                Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR")
            end
        end,
        true)

    RefreshInlineControlState = function()
        local conf = GetConf("targettarget")
        local enabled = GetConf("targettarget").showToTInTargetName == true
        local npcAvailable = ToTInlineNPCColorAvailable()
        if conf.totInlineColorMode == TOT_INLINE_COLOR_NPC and not npcAvailable then
            conf.totInlineColorMode = TOT_INLINE_COLOR_AUTO
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_COLOR_AUTO", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_COLOR_AUTO", { text = true, preview = true })
            if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate("targettarget") end
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_COLOR_AUTO")
        end
        local isCustom = ToTInlineSeparatorDropdownValue(conf) == TOT_INLINE_CUSTOM_SEPARATOR
        SetControlEnabled(color, enabled)
        SetControlEnabled(sep, enabled)
        SetControlEnabled(customSep, enabled and isCustom)
        if color.SetValues then color:SetValues(ToTInlineColorOptions()) end
        if color.SetValue then color:SetValue(ToTInlineColorDropdownValue(conf)) end
    end
    M.AddRefresher(ctx, RefreshInlineControlState)
    RefreshInlineControlState()
end

local function BuildStatus(ctx, builder, unit)
    local fn = M.BuildUnitStatusSection
    if type(fn) == "function" then
        if UP.BuildSectionLazy then
            return UP.BuildSectionLazy(ctx, builder, unit, {
                id = "status_icons",
                build = function(lazyCtx, lazyBuilder, lazyUnit)
                    return fn(lazyCtx, lazyBuilder, lazyUnit)
                end,
            })
        end
        return fn(ctx, builder, unit)
    end
end

local function BuildLoadConditions(ctx, builder, unit)
    local sec = builder:CollapsibleSection("load_conditions", "Load Conditions", 148, false)
    local colW = math.floor(((ctx.width or 720) - 42) / 3)
    for i = 1, #LOAD_CONDITIONS do
        local spec = LOAD_CONDITIONS[i]
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local toggle
        if W.ToggleAt then
            toggle = W.ToggleAt(sec, spec.label, 14 + col * colW, -42 - row * 30, colW - 34)
        else
            toggle = W.Toggle(sec, spec.label)
        end
        M.BindToggle(ctx, toggle,
            function() return ReadBool(unit, spec.key, false) end,
            function(v)
                local conf = GetConf(unit)
                conf[spec.key] = v and true or false
                UpdateLoadActive(unit)
                M.RequestUnitApply(unit, "MSUF2_LOAD_CONDITION", { preview = true })
            end)
    end

    local function RefreshLoadConditionState()
        local activeCount = 0
        for i = 1, #LOAD_CONDITIONS do
            if ReadBool(unit, LOAD_CONDITIONS[i].key, false) then activeCount = activeCount + 1 end
        end
        SetSectionHeaderStatus(sec, nil)
    end
    M.SetCollapsibleRefreshState(sec, RefreshLoadConditionState)
    M.AddRefresher(ctx, RefreshLoadConditionState)
    RefreshLoadConditionState()
end

local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = builder:CollapsibleSection("boss_layout", "Boss Layout", 152, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or sliderW, "CENTER")
    end
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or 220)
    end

    local spacing = W.Slider(sec, "Boss spacing", -400, 0, 1, 300)
    PlaceSlider(spacing, leftX, -42, sliderW)
    M.BindSlider(ctx, spacing,
        function() return ReadNumber(unit, "spacing", -36) end,
        function(v) SetNumber(unit, "spacing", v, "MSUF2_BOSS_SPACING", { preview = true }) end)

    local layout = W.Dropdown(sec, "Boss frame layout", BOSS_LAYOUT_OPTIONS, 220)
    PlaceDropdown(layout, rightX, -42, 220)
    M.BindDropdown(ctx, layout,
        function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, conf.invertBossOrder)
        end,
        function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            conf.invertBossOrder = nil
            M.RequestUnitApply(unit, "MSUF2_BOSS_LAYOUT_MODE", { preview = true })
        end)

    local highlight = W.ToggleAt(sec, "Boss target highlight", leftX, -116, 260)
    M.BindToggle(ctx, highlight,
        function() return ReadGeneralBool("bossTargetHighlightEnabled", true) end,
        function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v and true or false
            g.bossTargetOutlineMode = v and 1 or 0
            M.RequestGeneralApply("MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
        end)
end

local function BuildUnitSectionMaybeLazy(ctx, builder, unit, buildFn, opts)
    if UP.BuildSectionLazy and not (opts and opts.lazy == false) then
        return UP.BuildSectionLazy(ctx, builder, unit, {
            prepareShell = opts and opts.prepareShell,
            build = function(lazyCtx, lazyBuilder, lazyUnit)
                return buildFn(lazyCtx, lazyBuilder, lazyUnit)
            end,
        })
    end
    return buildFn(ctx, builder, unit)
end

local function BuildUnitPage(info)
    return function(ctx)
        if info.unit == "boss" and ctx and ctx.wrapper then
            local function BossPagePreviewShouldBeActive()
                return M.frame and M.frame.IsShown and M.frame:IsShown()
                    and M.activeKey == "uf_boss"
                    and ctx.wrapper and ctx.wrapper.IsShown and ctx.wrapper:IsShown()
            end

            ctx.wrapper:HookScript("OnShow", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
                end
            end)
            ctx.wrapper:HookScript("OnHide", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(false)
                end
            end)
            M.AddRefresher(ctx, function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
                end
            end)
            if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
            end
        end

        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, info.unit, info.label)
        BuildPreview(ctx, builder, info.unit)
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, function(lazyCtx, lazyBuilder, lazyUnit)
            return BuildBasics(lazyCtx, lazyBuilder, lazyUnit, info.label)
        end, {
            prepareShell = function(lazyCtx, sec, lazyUnit)
                local refresh = AttachBasicsHeaderStatus(sec, lazyUnit)
                if refresh then
                    if M.AddRefresherOnce then
                        M.AddRefresherOnce(lazyCtx, "frame-basics-header:" .. tostring(lazyUnit), refresh)
                    else
                        M.AddRefresher(lazyCtx, refresh)
                    end
                end
                return refresh
            end,
        })
        if UNIT_AURAS_MENU_UNITS[info.unit] and type(M.BuildAuras3UnitSection) == "function" then
            if UP.BuildSectionLazy then
                UP.BuildSectionLazy(ctx, builder, info.unit, {
                    id = "auras3",
                    build = function(lazyCtx, lazyBuilder, lazyUnit)
                        return M.BuildAuras3UnitSection(lazyCtx, lazyBuilder, lazyUnit)
                    end,
                })
            else
                M.BuildAuras3UnitSection(ctx, builder, info.unit)
            end
        end
        if UP.BuildRegisteredSections then
            UP.BuildRegisteredSections(ctx, builder, info.unit, "after_auras")
        end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildInlineText)
        if UP.BuildRegisteredSections then
            UP.BuildRegisteredSections(ctx, builder, info.unit, "after_inline_text")
        end
        BuildStatus(ctx, builder, info.unit)
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildBossLayout)
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLoadConditions)
        if UP.BuildRegisteredSections then
            UP.BuildRegisteredSections(ctx, builder, info.unit, "after_load_conditions")
        end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLayout)
        M.AddRefresher(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, info.unit)
        end)
        ApplyUnitFrameEnabledGate(ctx, info.unit)
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end

for key, info in pairs(UNIT_PAGES) do
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 22,
    })
end
