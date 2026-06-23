local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Shared Unit page sections.
-- Builds reusable controls for per-unit basics, load rules, target-of-target text behavior,
-- and copy/edit-mode actions. Runtime ownership stays in UnitFrames and EditMode modules.
local W = M.Widgets
local T = M.Theme
local SetControlsEnabled = W.SetControlsEnabled
local ControlGates = M.ControlGates or {}
local UP = M.UnitPage or {}
local floor = math.floor
local VT = M.ValueTextList
local UNIT_PAGES, LOAD_CONDITIONS, BOSS_LAYOUT_OPTIONS, SEPARATORS, UF_COPY_CATEGORIES = M.PickDefaults(UP, [[UNIT_PAGES LOAD_CONDITIONS BOSS_LAYOUT_OPTIONS SEPARATORS UF_COPY_CATEGORIES]])
local GetConf, GetGeneral, Call, DefaultCopyTarget, UnitTopLabel, UnitTopPillWidth, NewCopyScopeDefaults, CopyUnitSettings, ToggleEditMode, IsEditModeActive, ReadBool, SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetControlEnabled, NormalizeBossLayoutMode, UpdateLoadActive = M.Pick(UP, [[GetConf GetGeneral Call DefaultCopyTarget UnitTopLabel UnitTopPillWidth NewCopyScopeDefaults CopyUnitSettings ToggleEditMode IsEditModeActive ReadBool SetBool ReadNumber SetNumber ReadGeneralBool SetControlEnabled NormalizeBossLayoutMode UpdateLoadActive]])
local UNIT_AURAS_MENU_UNITS = M.KeySetFromWords "player target focus boss"
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
local HEALTH_COLOR_GLOBAL = "GLOBAL"
local HEALTH_COLOR_LABELS = {
    class = "Class / Reaction",
    gradient = "Health Gradient",
    unified = "Unified Color",
    dark = "Dark Mode",
}
local HEALTH_COLOR_ALIASES = {
    CLASS = "class",
    class = "class",
    GRADIENT = "gradient",
    gradient = "gradient",
    UNIFIED = "unified",
    unified = "unified",
    DARK = "dark",
    dark = "dark",
}
local HEALTH_COLOR_OPTIONS = {
    { value = HEALTH_COLOR_GLOBAL, text = "Use Global" },
    { value = "class", text = HEALTH_COLOR_LABELS.class },
    { value = "gradient", text = HEALTH_COLOR_LABELS.gradient },
    { value = "unified", text = HEALTH_COLOR_LABELS.unified },
    { value = "dark", text = HEALTH_COLOR_LABELS.dark },
}
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_ARROW = { 0.88, 0.62, 0.22, 1 }
local WARNING_BADGE_FILL = { 0.205, 0.148, 0.080, 0.96 }
local WARNING_BADGE_EDGE = { 0.52, 0.39, 0.18, 0.78 }
local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
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
local UF_COPY_TARGET_ORDER = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet", "all" }
local UF_COPY_TARGET_WIDTHS = { player = 48, target = 50, targettarget = 38, focustarget = 34, focus = 48, boss = 46, pet = 38, all = 38 }
local UF_COPY_TARGET_SHORT_LABELS = { targettarget = "ToT", focustarget = "FT", boss = "Boss", all = "All" }
local TOT_INLINE_SEPARATOR_VALUES = {}
local TOT_INLINE_SEPARATOR_OPTIONS = {}
for i = 1, #SEPARATORS do
    local item = SEPARATORS[i]
    local value = item and item.value
    TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = item
    if value ~= nil then TOT_INLINE_SEPARATOR_VALUES[value == "" and " " or value] = true end
end
TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = { value = TOT_INLINE_CUSTOM_SEPARATOR, text = "Custom" }
local function CleanToTInlineCustomSeparator(value) return M.CleanToTInlineCustomSeparator(value, TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
local function ToTInlineSeparatorDropdownValue(conf)
    local token = conf and conf.totInlineSeparator
    if token == TOT_INLINE_CUSTOM_SEPARATOR then return TOT_INLINE_CUSTOM_SEPARATOR end
    if type(token) == "string" and token ~= "" then return TOT_INLINE_SEPARATOR_VALUES[token] and (token == " " and "" or token) or TOT_INLINE_CUSTOM_SEPARATOR end
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
local function NormalizeHealthColorMode(value)
    if value == nil or value == HEALTH_COLOR_GLOBAL then return nil end
    if type(value) ~= "string" then return nil end
    return HEALTH_COLOR_ALIASES[value] or HEALTH_COLOR_ALIASES[value:lower()]
end
local function GlobalHealthColorMode()
    local g = GetGeneral()
    local mode = g and g.barMode
    if type(mode) == "string" then mode = mode:lower() end
    if not HEALTH_COLOR_LABELS[mode] then
        if g and g.useClassColors == true then
            mode = "class"
        elseif g and g.darkMode == true then
            mode = "dark"
        else
            mode = "dark"
        end
    end
    if mode == "gradient" and g and g.enableHealthGradient == false then mode = "class" end
    return mode
end
local function HealthColorModeLabel(mode)
    return HEALTH_COLOR_LABELS[mode] or HEALTH_COLOR_LABELS.dark
end
local function HealthColorModeOptions()
    HEALTH_COLOR_OPTIONS[1].text = "Use Global (" .. HealthColorModeLabel(GlobalHealthColorMode()) .. ")"
    return HEALTH_COLOR_OPTIONS
end
local function ToTInlineNPCColorAvailable()
    local fn = _G.MSUF_UFCore_IsToTInlineNPCColorModeAvailable
    if type(fn) == "function" then return fn() == true end
    local db = _G.MSUF_DB
    local gen = db and db.general
    local wantNpc = gen and gen.npcNameRed
    local conf = GetConf("targettarget")
    if conf and conf.fontOverride and conf.npcNameRed ~= nil then wantNpc = conf.npcNameRed end
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
        if child and child._msuf2ControlKind and not child._msuf2UnitFrameGateAlwaysEnabled then callback(child) end
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
        box._msuf2PinnedPreviewPageKey = ctx and ctx.key
        box._msuf2PinnedPreviewWrapper = ctx and ctx.wrapper
        box._msuf2PinnedFloating = nil
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
        if not box and not initialPreviewQueued then
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
    if sec.HookScript then
        sec:HookScript("OnShow", RefreshPreviewState)
        sec:HookScript("OnHide", function()
            previewQueueSerial = previewQueueSerial + 1
            initialPreviewQueued = nil
        end)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshPreviewState)
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
    local copy = W.TopButton(sec, M.Tr("Copy To"), compactTop and 82 or 86, 24, nil, false)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -8, actionY)
    local edit = W.TopButton(sec, M.Tr("MSUF Edit Mode"), compactTop and 118 or 128, 24, nil, false)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    if W.CreatePageResetButton then W.CreatePageResetButton(ctx, sec, edit, { width = compactTop and 84 or 88 }) end
    local function RefreshEditButton()
        local active = IsEditModeActive()
        edit:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode"))
        edit:SetActive(false)
    end
    edit:SetScript("OnClick", function()
        local wasActive = IsEditModeActive()
        ToggleEditMode(unit)
        if M.ShowStatusFeedback then M.ShowStatusFeedback(wasActive and M.Tr("Edit mode off") or M.Tr("Edit mode on"), "info", 1.2) end
        C_Timer.After(0, RefreshEditButton)
    end)
    M.TrackRefresh(ctx, RefreshEditButton)
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
    local copyPopup = UnitSectionShared.MakeScopeCopyPopup and UnitSectionShared.MakeScopeCopyPopup(copy, {
        width = 420,
        height = 276,
        categories = UF_COPY_CATEGORIES,
        scopes = copyScopes,
        targets = UF_COPY_TARGET_ORDER,
        targetWidths = UF_COPY_TARGET_WIDTHS,
        sourceKey = function() return unit end,
        sourceLabel = UnitTopLabel,
        targetLabelText = function(key) return UF_COPY_TARGET_SHORT_LABELS[key] or UnitTopLabel(key) end,
        selectedTarget = function() return NormalizeCopyDest(unit) end,
        isTargetVisible = function(key, source) return key ~= source end,
        onTargetClick = function(key) M.unitCopyTarget = key end,
        runLabel = "Copy Selected",
        runWidth = 128,
        onRun = function(api, popup)
            local dest = NormalizeCopyDest(unit)
            local function RunCopy()
                CopyUnitSettings(unit, dest, copyScopes)
            end
            M.RunWithHistory("Copy Unit Settings", "unit:copy:" .. tostring(unit), RunCopy)
            if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Format(M.Tr("Copied to %s"), UnitTopLabel(dest)), "ok", 1.35) end
            popup:Hide()
        end,
    })
    copy:SetScript("OnClick", function(self)
        if copyPopup then copyPopup.Show(self) end
    end)
    sec:SetScript("OnHide", function()
        if copyPopup then copyPopup.Hide() end
    end)
end
local function AttachBasicsHeaderStatus(sec, unit)
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    if not sectionEntry then return nil end
    if type(sectionEntry._msuf2BasicsHeaderRefresh) == "function" then return sectionEntry._msuf2BasicsHeaderRefresh end
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
        if sectionEntry.arrow and sectionEntry.arrow.SetVertexColor and not on then sectionEntry.arrow:SetVertexColor(WARNING_ARROW[1], WARNING_ARROW[2], WARNING_ARROW[3], WARNING_ARROW[4]) end
    end
    sectionEntry._msuf2BasicsHeaderRefresh = RefreshBasicsState
    RefreshBasicsState()
    return RefreshBasicsState
end
local function BuildBasics(ctx, builder, unit, label)
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 170, false)
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
    M.BindBoolWidget(ctx, enable,
        function() return ReadBool(unit, "enabled", true) end,
        function(v)
            SetBool(unit, "enabled", v, "MSUF2_FRAME_ENABLED", { preview = true })
            M.RequestOrRefresh(ctx, "frame-basics-enabled")
        end)
    local reverse = W.ToggleAt(sec, "Reverse fill direction", x2, row1, labelW)
    M.BindBoolWidget(ctx, reverse,
        function() return ReadBool(unit, "reverseFillBars", false) end,
        function(v) SetBool(unit, "reverseFillBars", v, "MSUF2_REVERSE_FILL", { preview = true }) end)
    local smooth = W.ToggleAt(sec, "Smooth fill", x3, row1, labelW)
    M.BindBoolWidget(ctx, smooth,
        function() return ReadBool(unit, "smoothFill", true) end,
        function(v) SetBool(unit, "smoothFill", v, "MSUF2_SMOOTH_FILL", { preview = true }) end)
    local colorMode = W.Dropdown(sec, "Health Color Scheme", HealthColorModeOptions, math.min(270, math.max(220, colW * 2)))
    UnitSectionShared.PlaceDropdown(sec, colorMode, x1, -84, math.min(270, math.max(220, colW * 2)))
    M.BindDropdownWidget(ctx, colorMode,
        function()
            return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or HEALTH_COLOR_GLOBAL
        end,
        function(v)
            local conf = GetConf(unit)
            conf.healthColorMode = NormalizeHealthColorMode(v)
            M.RequestUnitApply(unit, "MSUF2_HEALTH_COLOR_MODE", { preview = true })
            if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                _G.MSUF_ShowReloadRecommendedPopup("Unitframe color changes")
            end
        end)
    if M.AddTooltip then
        M.AddTooltip(colorMode, "Health Color Scheme", "Use Global follows the Unitframe Global Coloring mode from Colors. Other choices override only this frame.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    if W.AttachUnitEditFocus then
        for _, control in ipairs({ enable, reverse, smooth, colorMode }) do W.AttachUnitEditFocus(control, unit, "frame") end
    end
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local RefreshBasicsState = AttachBasicsHeaderStatus(sec, unit) or function() end
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end
    local unitLabel = label or UnitTopLabel(unit)
    local notice, _, enableNow = UnitSectionShared.CreateSectionNotice(sec, -132, "Enable", 92)
    notice:SetMessage(unitLabel .. " frame is disabled and will not appear.", "warning")
    enableNow:SetScript("OnClick", function()
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true }) end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        M.RequestOrRefresh(ctx, "frame-basics-enable-now")
    end)
    notice:Hide()
    local basicsDependentControls = { reverse, smooth, colorMode }
    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        SetControlEnabled(enable, true)
        SetControlsEnabled(basicsDependentControls, ownOn)
        if parentOff then
            notice:SetMessage("Focus Target follows the Focus frame. Enable Focus to show it.", "warning")
            if enableNow.SetText then enableNow:SetText("Enable Focus") end
        else
            notice:SetMessage(unitLabel .. " frame is disabled and will not appear.", "warning")
            if enableNow.SetText then enableNow:SetText("Enable") end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
    end
    M.TrackRefresh(ctx, RefreshBasicsEnabled)
end
local function BuildLayout(ctx, builder, unit)
    local sec = builder:CollapsibleSection("anchoring", "Anchoring", 220, false)
    local anchorChoices = VT("GLOBAL", "Global anchor", "EssentialCooldownViewer", "Essential cooldown viewer", "UtilityCooldownViewer", "Utility cooldown viewer", "BuffIconCooldownViewer", "Tracked buffs viewer", "player", "Player frame", "target", "Target frame", "targettarget", "Target of Target frame", "focustarget", "Focus Target frame", "focus", "Focus frame", "pet", "Pet frame")
    local anchorPoints = VT("TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT")
    local standardAnchorValues = M.KeySetFromWords "GLOBAL global FREE EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer player target targettarget focustarget focus pet"
    local function CustomAnchorName(conf)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        if custom ~= "" then return custom end
        local raw = conf.anchorToUnitframe
        if type(raw) == "string" and raw ~= "" and standardAnchorValues[raw] ~= true then return raw end
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
            if item.value == "GLOBAL" or item.value ~= unit then values[#values + 1] = item end
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
    local anchorTo = W.Dropdown(sec, "Anchor To", AnchorValues, 230)
    UnitSectionShared.PlaceDropdown(sec, anchorTo, 14, -38, 230)
    W.AttachUnitEditFocus(anchorTo, unit, "anchoring")
    M.BindDropdownWidget(ctx, anchorTo,
        AnchorValue,
        function(v)
            if v == "__CUSTOM" then return end
            local conf = GetConf(unit)
            conf.anchorToUnitframe = v or "GLOBAL"
            conf.anchorFrameName = nil
            ApplyAnchorChange()
        end)
    local anchorPoint = W.Dropdown(sec, "Anchor Point", anchorPoints, 160)
    UnitSectionShared.PlaceDropdown(sec, anchorPoint, 284, -38, 160)
    W.AttachUnitEditFocus(anchorPoint, unit, "anchoring")
    M.BindDropdownWidget(ctx, anchorPoint,
        AnchorPointValue,
        function(v)
            local conf = GetConf(unit)
            v = v or "CENTER"
            conf.point = v
            conf.relativePoint = v
            ApplyAnchorChange()
        end)
    local function SetCustomAnchorValue(value)
        value = value or ""
        local conf = GetConf(unit)
        conf.anchorFrameName = (value ~= "") and value or nil
        if value ~= "" or CustomAnchorName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        ApplyAnchorChange()
    end
    local customAnchor = UnitSectionShared.CustomAnchorEditor(ctx, sec, {
        getValue = function() return CustomAnchorName(GetConf(unit)) end,
        setValue = function(value) SetCustomAnchorValue(value) end,
        clearValue = function()
            SetCustomAnchorValue("")
        end,
        commitTitle = "Set Unit Anchor",
        commitKey = function() return "unit:anchorCustom:" .. tostring(unit) end,
        pickTitle = "Pick custom anchor",
        pickKey = function() return "unit:anchorPick:" .. tostring(unit) end,
        attachFocus = function(widget) W.AttachUnitEditFocus(widget, unit, "anchoring") end,
    })
    customAnchor.clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        if CustomAnchorName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        customAnchor.box:SetText("")
        ApplyAnchorChange()
    end)
    local function RefreshLayoutState()
        customAnchor.Refresh()
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
        if anchorPoint.SetValue then anchorPoint:SetValue(AnchorPointValue()) end
        SetSectionHeaderStatus(sec, nil)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshLayoutState)
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
    local inlineApplyFlags = { text = true, preview = true }
    local function ApplyToTInline(reason, forceToT, skipRefresh)
        M.RequestUnitApply("target", reason, inlineApplyFlags)
        M.RequestUnitApply("targettarget", reason, inlineApplyFlags)
        if forceToT and MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate("targettarget") end
        Call("MSUF_UpdateTargetToTInlineNow")
        Call("MSUF_UFPreview_RequestRefresh", reason)
        if not skipRefresh and RefreshInlineControlState then RefreshInlineControlState() end
    end
    local show = W.Toggle(sec, "Show Target of Target text inline")
    M.BindBoolWidget(ctx, show,
        function() return GetConf("targettarget").showToTInTargetName == true end,
        function(v)
            local conf = GetConf("targettarget")
            conf.showToTInTargetName = v and true or false
            ApplyToTInline("MSUF2_TOT_INLINE")
        end)
    local color = W.Dropdown(sec, "Inline color", ToTInlineColorOptions, rightW)
    W.MoveWidget(color, sec, rightX, -72, rightW)
    M.BindDropdownWidget(ctx, color,
        function() return ToTInlineColorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            conf.totInlineColorMode = NormalizeToTInlineColorMode(v)
            ApplyToTInline("MSUF2_TOT_INLINE_COLOR", true)
        end)
    local sep = W.Dropdown(sec, "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170)
    W.MoveWidget(sep, sec, 14, -124, 170)
    M.BindDropdownWidget(ctx, sep,
        function() return ToTInlineSeparatorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            if v == TOT_INLINE_CUSTOM_SEPARATOR then
                conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(conf.totInlineCustomSeparator)
            else
                conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
            end
            ApplyToTInline("MSUF2_TOT_INLINE_SEPARATOR", true)
        end)
    local customSep = W.TextInput(sec, "Custom separator", rightW)
    W.MoveWidget(customSep, sec, rightX, -124, rightW)
    if customSep.SetMaxLetters then customSep:SetMaxLetters(TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
    M.BindTextInput(ctx, customSep,
        function()
            local conf = GetConf("targettarget")
            local token = conf and conf.totInlineSeparator
            if token ~= TOT_INLINE_CUSTOM_SEPARATOR and type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token] then return CleanToTInlineCustomSeparator(token) end
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
                ApplyToTInline("MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", true, true)
            end
        end,
        true)
    local totInlineBaseControls = { color, sep }
    RefreshInlineControlState = function()
        local conf = GetConf("targettarget")
        local enabled = GetConf("targettarget").showToTInTargetName == true
        local npcAvailable = ToTInlineNPCColorAvailable()
        if conf.totInlineColorMode == TOT_INLINE_COLOR_NPC and not npcAvailable then
            conf.totInlineColorMode = TOT_INLINE_COLOR_AUTO
            ApplyToTInline("MSUF2_TOT_INLINE_COLOR_AUTO", true, true)
        end
        local isCustom = ToTInlineSeparatorDropdownValue(conf) == TOT_INLINE_CUSTOM_SEPARATOR
        SetControlsEnabled(totInlineBaseControls, enabled)
        SetControlEnabled(customSep, enabled and isCustom)
        if color.SetValues then color:SetValues(ToTInlineColorOptions()) end
        if color.SetValue then color:SetValue(ToTInlineColorDropdownValue(conf)) end
    end
    M.TrackRefresh(ctx, RefreshInlineControlState)
end
local function BuildStatus(ctx, builder, unit)
    local fn = M.BuildUnitStatusSection
    if type(fn) == "function" then
        if UP.BuildSectionLazy then
            return UP.BuildSectionLazy(ctx, builder, unit, {
                id = "status_icons",
                title = "Status icons",
                height = 646,
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
        M.BindBoolWidget(ctx, toggle,
            function() return ReadBool(unit, spec.key, false) end,
            function(v)
                local conf = GetConf(unit)
                conf[spec.key] = v and true or false
                UpdateLoadActive(unit)
                M.RequestUnitApply(unit, "MSUF2_LOAD_CONDITION", { preview = true })
            end)
    end
    local function RefreshLoadConditionState()
        SetSectionHeaderStatus(sec, nil)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshLoadConditionState)
end
local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = builder:CollapsibleSection("boss_layout", "Boss Layout", 152, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    local spacing = W.Slider(sec, "Boss spacing", -400, 0, 1, 300)
    W.MoveWidget(spacing, sec, leftX, -42, sliderW, "CENTER")
    M.BindNumberWidget(ctx, spacing,
        function() return ReadNumber(unit, "spacing", -36) end,
        function(v) SetNumber(unit, "spacing", v, "MSUF2_BOSS_SPACING", { preview = true }) end,
        -36, { step = 1, roundStep = true })
    local layout = W.Dropdown(sec, "Boss frame layout", BOSS_LAYOUT_OPTIONS, 220)
    UnitSectionShared.PlaceDropdown(sec, layout, rightX, -42, 220)
    M.BindDropdownWidget(ctx, layout,
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
    M.BindBoolWidget(ctx, highlight,
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
            sectionId = opts and opts.sectionId,
            title = opts and opts.title,
            height = opts and opts.height,
            defaultOpen = opts and opts.defaultOpen,
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
            local function SetBossPagePreviewActive(active)
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then M.UnitPage.SetBossPagePreviewActive(active) end
            end
            local function RefreshBossPagePreviewActive()
                SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
            end
            ctx.wrapper:HookScript("OnShow", RefreshBossPagePreviewActive)
            ctx.wrapper:HookScript("OnHide", function() SetBossPagePreviewActive(false) end)
            M.TrackRefresh(ctx, RefreshBossPagePreviewActive)
        end
        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, info.unit, info.label)
        BuildPreview(ctx, builder, info.unit)
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, function(lazyCtx, lazyBuilder, lazyUnit)
            return BuildBasics(lazyCtx, lazyBuilder, lazyUnit, info.label)
        end, {
            sectionId = "frame_basics",
            title = "Frame Basics",
            height = 170,
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
                    title = "Auras",
                    height = 622,
                    build = function(lazyCtx, lazyBuilder, lazyUnit)
                        return M.BuildAuras3UnitSection(lazyCtx, lazyBuilder, lazyUnit)
                    end,
                })
            else
                M.BuildAuras3UnitSection(ctx, builder, info.unit)
            end
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_auras") end
        if info.unit == "target" then
            BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildInlineText, { sectionId = "inline_text", title = "Inline Text", height = 214 })
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_inline_text") end
        BuildStatus(ctx, builder, info.unit)
        if info.unit == "boss" then
            BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildBossLayout, { sectionId = "boss_layout", title = "Boss Layout", height = 152 })
        end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLoadConditions, { sectionId = "load_conditions", title = "Load Conditions", height = 148 })
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_load_conditions") end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLayout, { sectionId = "anchoring", title = "Anchoring", height = 220 })
        M.TrackRefresh(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, info.unit)
        end)
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
