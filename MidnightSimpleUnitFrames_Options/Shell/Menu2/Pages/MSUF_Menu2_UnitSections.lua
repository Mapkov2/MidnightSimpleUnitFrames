local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

-- Shared Unit page sections.
-- Builds reusable controls for per-unit basics, load rules, target-of-target text behavior,
-- and copy/edit-mode actions. Runtime ownership stays in UnitFrames and EditMode modules.
local W = M.Widgets
local T = M.Theme
local SetControlsEnabled = W.SetControlsEnabled
local ControlGates = M.ControlGates or {}
local UP = M.UnitPage or {}
local floor = math.floor
local max, min = math.max, math.min
local VT = M.ValueTextList
local UNIT_PAGES, LOAD_CONDITIONS, BOSS_LAYOUT_OPTIONS, SEPARATORS, UF_COPY_CATEGORIES = M.PickDefaults(UP, [[UNIT_PAGES LOAD_CONDITIONS BOSS_LAYOUT_OPTIONS SEPARATORS UF_COPY_CATEGORIES]])
local GetConf, GetGeneral, Call, DefaultCopyTarget, UnitTopLabel, UnitTopPillWidth, NewCopyScopeDefaults, ConfirmCopyToAll, CopyUnitSettings, ToggleEditMode, IsEditModeActive, ReadBool, SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetControlEnabled, NormalizeBossLayoutMode, UpdateLoadActive, ControlMeta, SettingMeta, ReviewedMeta, RegisterControl = M.Pick(UP, [[GetConf GetGeneral Call DefaultCopyTarget UnitTopLabel UnitTopPillWidth NewCopyScopeDefaults ConfirmCopyToAll CopyUnitSettings ToggleEditMode IsEditModeActive ReadBool SetBool ReadNumber SetNumber ReadGeneralBool SetControlEnabled NormalizeBossLayoutMode UpdateLoadActive ControlMeta SettingMeta ReviewedMeta RegisterControl]])
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
-- Fill Direction merges the fill axis (verticalFillBars) with the in-axis
-- direction (reverseFillBars) into one control. Compiled by CompileUnitHealth/
-- CompileUnitPower (MSUF_UF_Config.lua) and applied via the SetOrientation +
-- SetReverseFill blocks in the Health/Power elements.
local FILL_DIRECTION_OPTIONS = {
    { value = "lr", text = "Left to Right" },
    { value = "rl", text = "Right to Left" },
    { value = "bt", text = "Bottom to Top" },
    { value = "tb", text = "Top to Bottom" },
}
local FILL_DIRECTION_STATE = {
    lr = { reverse = false, vertical = false },
    rl = { reverse = true,  vertical = false },
    bt = { reverse = false, vertical = true  },
    tb = { reverse = true,  vertical = true  },
}
local function FillDirectionValue(reverse, vertical)
    if vertical then return reverse and "tb" or "bt" end
    return reverse and "rl" or "lr"
end
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_BADGE_FILL = { 0.205, 0.148, 0.080, 0.96 }

local function AutomaticCooldownProvider()
    local getter = _G.MSUF_GetAutomaticCooldownAnchorProvider
    if type(getter) ~= "function" then return nil, nil end
    return getter()
end
local function CooldownAnchorEnabled()
    local general = GetGeneral and GetGeneral() or nil
    local getter = _G.MSUF_IsCooldownAnchorEnabled
    if type(getter) == "function" then return getter(general) == true end
    return type(general) == "table" and general.anchorToCooldown == true or false
end
local WARNING_BADGE_EDGE = { 0.52, 0.39, 0.18, 0.78 }
local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
local ENABLED_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local TINTED_ENABLED_HEADER_BG = { 0, 0, 0, 0.48 }
local function EnabledHeaderColor()
    if T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted() then
        local color = T.colors and T.colors.coreSurface
        if color then
            TINTED_ENABLED_HEADER_BG[1] = color[1]
            TINTED_ENABLED_HEADER_BG[2] = color[2]
            TINTED_ENABLED_HEADER_BG[3] = color[3]
            return TINTED_ENABLED_HEADER_BG
        end
    end
    return ENABLED_HEADER_BG
end
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

local function CurrentApplyService()
    local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    if type(apply) == "table" then return apply end
    return nil
end

local function RequestUnitRuntimeApply(unit, reason, opts, flushNow)
    opts = opts or {}
    opts.history = false
    if M and type(M.RequestUnitApply) == "function" then
        local ok = M.RequestUnitApply(unit, reason or "MSUF2_UNIT_SECTION", opts) ~= false
        if ok and flushNow then
            local apply = CurrentApplyService()
            if apply and type(apply.Flush) == "function" then apply.Flush() end
        end
        return ok
    end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestUnit) == "function" then
        apply.RequestUnit(unit, reason or "MSUF2_UNIT_SECTION", opts)
        if flushNow and type(apply.Flush) == "function" then apply.Flush() end
        return true
    end
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged(unit, true, true, reason or "MSUF2_UNIT_SECTION")
        return true
    end
    return false
end
local UF_COPY_TARGET_ORDER = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet", "all" }
local UF_COPY_TARGET_WIDTHS = { player = 48, target = 50, targettarget = 38, focustarget = 34, focus = 48, boss = 46, pet = 38, all = 38 }
local UF_COPY_TARGET_SHORT_LABELS = { targettarget = "ToT", focustarget = "FT", boss = "Boss", all = "All" }
local UNIT_TAB_ORDER = { "player", "target", "boss", "focus", "pet", "targettarget", "focustarget" }
local UNIT_TAB_LABELS = { boss = "Boss Frames", targettarget = "Target's Target", focustarget = "Focus Target" }
local UNIT_TAB_COMPACT_LABELS = { boss = "Boss", targettarget = "ToT", focustarget = "FT" }
local UNIT_TAB_WIDTHS = { player = 58, target = 62, boss = 92, focus = 58, pet = 46, targettarget = 108, focustarget = 98 }
local UNIT_TAB_COMPACT_WIDTHS = { player = 50, target = 54, boss = 54, focus = 50, pet = 40, targettarget = 42, focustarget = 36 }
local UNIT_PAGE_FOR_UNIT = {}
for pageKey, pageInfo in pairs(UNIT_PAGES or {}) do
    if pageInfo and pageInfo.unit then UNIT_PAGE_FOR_UNIT[pageInfo.unit] = pageKey end
end
local function UnitTopTabLabel(unit, compact)
    if compact then return M.Tr(UNIT_TAB_COMPACT_LABELS[unit] or UNIT_TAB_LABELS[unit] or UnitTopLabel(unit)) end
    return M.Tr(UNIT_TAB_LABELS[unit] or UnitTopLabel(unit))
end
local function UnitTopTabWidth(unit, compact)
    local widths = compact and UNIT_TAB_COMPACT_WIDTHS or UNIT_TAB_WIDTHS
    return widths[unit] or UnitTopPillWidth(unit)
end
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
    HEALTH_COLOR_OPTIONS[1].text = M.Format("Use Global (%s)", HealthColorModeLabel(GlobalHealthColorMode()))
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
        ControlGates.Apply(wrapper, gateKey, enabled, {
            alwaysEnabledFlag = "_msuf2UnitFrameGateAlwaysEnabled",
            exclusivePrefix = "unitFrameEnabled:",
        })
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
-- Page-level previews are fixed chrome, not form content. Keep their geometry
-- bounded so the settings ScrollFrame always starts below a predictable header.
local UNIT_PREVIEW_BOX_HEIGHT = 132
local UNIT_PREVIEW_EXPANDED_HEIGHT = 358
local UNIT_PREVIEW_SECTION_HEIGHT = 180
local UNIT_PREVIEW_TOP_OFFSET = -40
local function BuildPreview(ctx, builder, unit)
    local previewHeaderTitle = M.Tr("Preview - ") .. UnitTopLabel(unit)
    local sec, previewHeader, fixedRecord = W.FixedPreviewSection(ctx, builder, {
        title = previewHeaderTitle,
        height = UNIT_PREVIEW_SECTION_HEIGHT,
        gap = 8,
    })
    if not sec then return end
    local createPreview = MSUF.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox
    if not createPreview then
        W.Text(sec, "The shared unit preview module is not loaded.", 14, -56, ctx.width - 28, T.colors.muted)
        return
    end
    local panel, box, expander
    local EnsurePreviewExpander
    local initialPreviewQueued
    local previewQueueSerial = 0
    local function PreviewHostShown()
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if sec and sec.IsShown and not sec:IsShown() then return false end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return false end
        return true
    end
    local function SetPreviewOwner(target)
        target = target or box
        if not target then return end
        target._msuf2UnitPageHostShown = PreviewHostShown
        target._msuf2PinnedPreviewPageKey = ctx and ctx.key
        target._msuf2PinnedPreviewWrapper = ctx and ctx.wrapper
        if not (expander and expander.expanded) then target._msuf2PinnedFloating = nil end
        target._msuf2PreferredRestoreHeight = expander and expander.expanded
            and UNIT_PREVIEW_EXPANDED_HEIGHT or UNIT_PREVIEW_BOX_HEIGHT
        target._msuf2PreferredRestoreYOffset = UNIT_PREVIEW_TOP_OFFSET
        target._msuf2CompactHeader = previewHeader
        target._msuf2CompactExpandButton = expander and expander.button or nil
        target._msuf2FixedPreviewExpanderRecord = expander
    end
    local ApplyPreviewPresentation
    local function EnsurePreviewAttachment()
        if not box then return end
        local record = box._msuf2PinnedPreviewRecord
        local pageKey = ctx and ctx.key
        local wrapper = ctx and ctx.wrapper
        if W and W.AttachPinnedPreview
            and (not record or record.pageKey ~= pageKey or record.pageWrapper ~= wrapper)
        then
            W.AttachPinnedPreview(sec, box, {
                stateKey = "unitFramePreview",
                title = box.title,
                hint = box.hint,
                pageKey = pageKey,
                wrapper = wrapper,
            })
            local preview = MSUF.UFPreview
            if preview and type(preview.RegisterRuntimeControlsForPage) == "function" then
                preview.RegisterRuntimeControlsForPage(box, ctx and ctx.key)
            end
        end
        -- The preview is shared across cached unit pages. Reassert the current
        -- page's gate whenever ownership is rebound so no state from the
        -- previous page can survive a close/reopen transition.
        ApplyUnitFrameEnabledGate(ctx, unit)
    end
    local function EnsurePreview()
        if box and box.GetParent and box:GetParent() == sec then
            if not PreviewHostShown() then return nil end
            SetPreviewOwner()
            EnsurePreviewAttachment()
            if EnsurePreviewExpander then EnsurePreviewExpander() end
            if expander and expander.expanded then
                if box.Show then box:Show() end
                expander:Relayout("MSUF2_UNIT_EXPAND_OWNERSHIP")
            elseif box.Show then
                box:Show()
            end
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
                RequestUnitRuntimeApply(key, "MSUF2_UNIT_PREVIEW_APPLY", { preview = true, text = true })
            end,
        }
        panel._msufOpenUnitSection = function() end
        box = UP._sharedUnitPreviewBox
        if box and box.Hide then box:Hide() end
        if not box then
            box = createPreview(sec, panel, ctx.width - 28, UNIT_PREVIEW_BOX_HEIGHT)
            if not box then return nil end
            UP._sharedUnitPreviewBox = box
        else
            box:SetParent(sec)
            box:ClearAllPoints()
            box:SetSize(ctx.width - 28, UNIT_PREVIEW_BOX_HEIGHT)
            box._msufPanel = panel
            local preview = MSUF.UFPreview
            if preview and type(preview.RegisterRuntimeControlsForPage) == "function" then
                preview.RegisterRuntimeControlsForPage(box, ctx and ctx.key)
            end
        end
        box._msufPanel = panel
        SetPreviewOwner()
        box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, UNIT_PREVIEW_TOP_OFFSET)
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
        EnsurePreviewAttachment()
        if EnsurePreviewExpander then EnsurePreviewExpander() end
        if ApplyPreviewPresentation then ApplyPreviewPresentation() end
        return box
    end
    local RefreshPreviewBox
    local function RefreshThisPreview(reason)
        local currentBox = EnsurePreview()
        if not currentBox then return end
        panel._msufLastApplyKey = unit
        RefreshPreviewBox(currentBox, reason or (expander and expander.expanded
            and "MSUF2_UNIT_PAGE_EXPANDED" or "MSUF2_UNIT_PAGE_COMPACT"))
    end
    RefreshPreviewBox = function(target, reason)
        if not target then return end
        local preview = MSUF.UFPreview
        if type(preview) == "table" then
            if type(preview.RequestRefreshForBox) == "function" then
                preview.RequestRefreshForBox(target, reason)
                return
            end
            preview.active = target
            if type(preview.Refresh) == "function" and target.IsShown and target:IsShown() then
                preview.Refresh(target, reason)
                return
            end
        end
        Call("MSUF_UFPreview_RequestRefresh", reason)
    end
    -- Aura Style owns this exact embedded preview box. Publishing the scoped
    -- refresher avoids repainting Preview.active, which may belong to another
    -- cached, pinned, or reparented unit page.
    if ctx then ctx._msuf2RefreshUnitPreview = RefreshThisPreview end
    EnsurePreviewExpander = function()
        if not (box and W.AttachFixedPreviewExpander) then return nil end
        if expander and expander.box == box and not expander.disposed then
            box._msuf2CompactExpandButton = expander.button
            box._msuf2FixedPreviewExpanderRecord = expander
            return expander
        end
        expander = W.AttachFixedPreviewExpander(sec, previewHeader, box, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            compactHeight = UNIT_PREVIEW_BOX_HEIGHT,
            compactTop = UNIT_PREVIEW_TOP_OFFSET,
            expandedHeight = UNIT_PREVIEW_EXPANDED_HEIGHT,
            refreshPreview = function(target, reason)
                RefreshPreviewBox(target, reason or "MSUF2_UNIT_PREVIEW_SIZE")
            end,
            onStateChanged = function()
                if box.ReleasePreviewInteraction then box:ReleasePreviewInteraction() end
            end,
        })
        if expander and expander.button and not expander.button._msuf2UnitExpandRegistered then
            expander.button._msuf2UnitExpandRegistered = true
            RegisterControl(expander.button, ctx, "preview.height.toggle", "Expand Preview", "button", "ephemeral")
        end
        SetPreviewOwner()
        return expander
    end
    local function LayoutPreviewToolbar()
        local layersBtn = box and box._msuf2LayersButton
        if not (layersBtn and previewHeader) then return end
        layersBtn:SetParent(previewHeader)
        layersBtn:ClearAllPoints()
        local expandBtn = expander and expander.button
        if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
        else layersBtn:SetPoint("RIGHT", previewHeader, "RIGHT", -12, 0) end
        if layersBtn.SetFrameLevel and previewHeader.GetFrameLevel then
            layersBtn:SetFrameLevel((previewHeader:GetFrameLevel() or 1) + 3)
        end
    end
    ApplyPreviewPresentation = function()
        EnsurePreviewExpander()
        if expander and expander.expanded then
            expander:Relayout("MSUF2_UNIT_EXPANDED_PRESENTATION")
            return
        end
        if box and box._msuf2PinnedFloating ~= true then
            box._msuf2PreferredRestoreHeight = UNIT_PREVIEW_BOX_HEIGHT
            box._msuf2PreferredRestoreYOffset = UNIT_PREVIEW_TOP_OFFSET
            box._msuf2CompactHeader = previewHeader
            box._msuf2CompactExpandButton = expander and expander.button or nil
            local previousH = (box.GetHeight and box:GetHeight()) or 0
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, UNIT_PREVIEW_TOP_OFFSET)
            box:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, UNIT_PREVIEW_TOP_OFFSET)
            if box.ApplyCompactPreviewPresentation then
                box:ApplyCompactPreviewPresentation(true)
            end
            if box.SetHeight then box:SetHeight(UNIT_PREVIEW_BOX_HEIGHT) end
            LayoutPreviewToolbar()
            if math.abs(previousH - UNIT_PREVIEW_BOX_HEIGHT) > 0.5 and box.RequestRefresh then
                box:RequestRefresh("MSUF2_UNIT_PREVIEW_HEIGHT")
            end
        end
    end
    local function RefreshPreviewState()
        if not PreviewHostShown() then
            previewQueueSerial = previewQueueSerial + 1
            initialPreviewQueued = nil
            return
        end
        if not box and not initialPreviewQueued then
            initialPreviewQueued = true
            previewQueueSerial = previewQueueSerial + 1
            local serial = previewQueueSerial
            C_Timer.After(0, function()
                if serial ~= previewQueueSerial then return end
                initialPreviewQueued = nil
                if PreviewHostShown() then RefreshThisPreview("MSUF2_UNIT_PAGE_INITIAL") end
            end)
            return
        end
        RefreshThisPreview("MSUF2_UNIT_PAGE")
    end
    M._assistantUnitPreviewEnsurers = M._assistantUnitPreviewEnsurers or {}
    M._assistantUnitPreviewEnsurers[ctx.key] = function()
        previewQueueSerial = previewQueueSerial + 1
        initialPreviewQueued = nil
        RefreshThisPreview("MSUF2_ASSISTANT_UNIT_PREVIEW")
        return box ~= nil and PreviewHostShown()
    end
    M.EnsureUnitPagePreviewForAssistant = M.EnsureUnitPagePreviewForAssistant or function(pageKey)
        local ensure = M._assistantUnitPreviewEnsurers and M._assistantUnitPreviewEnsurers[pageKey]
        return type(ensure) == "function" and ensure() == true or false
    end
    if sec.HookScript then
        sec:HookScript("OnShow", RefreshPreviewState)
        sec:HookScript("OnHide", function()
            previewQueueSerial = previewQueueSerial + 1
            initialPreviewQueued = nil
        end)
    end
    M.TrackRefresh(ctx, RefreshPreviewState)
    if fixedRecord then fixedRecord.onActivate = RefreshPreviewState end
end
local function BuildTopActions(ctx, builder, unit, label)
    local pageW = tonumber(builder.width) or 720
    local scopeValues = {}
    for i = 1, #UNIT_TAB_ORDER do
        local tabUnit = UNIT_TAB_ORDER[i]
        scopeValues[i] = {
            value = tabUnit,
            text = UnitTopTabLabel(tabUnit, false),
            width = UnitTopTabWidth(tabUnit, false),
        }
    end
    local scopeOpts = {
        values = scopeValues,
        width = pageW,
        maxRight = pageW - 112,
        label = "Editing:",
        labelWidth = 64,
        getValue = function() return unit end,
        setValue = function(tabUnit)
            local pageKey = UNIT_PAGE_FOR_UNIT[tabUnit]
            if pageKey and pageKey ~= ctx.key then M.SelectPage(pageKey) end
        end,
    }
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, scopeOpts)
    local sectionH = math.max(54, math.abs((scopeMetrics and scopeMetrics.bottomY) or -40) + 14)
    local sec = T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(sec, "status")
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(pageW, sectionH)
    sec._msuf2Width = pageW
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, sec, "Player frame and Copy To", "unit_scope") end
    builder.y = builder.y - sectionH - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end
    local rowY = -15
    local scopeBar = W.ScopeOverrideBar and W.ScopeOverrideBar(ctx, sec, scopeOpts)
    RegisterControl(scopeBar, ctx, "navigation.unit_page.selector", "Editing", "segment", "ephemeral")
    local copy = (W.RoleButton and W.RoleButton(sec, M.Tr("Copy To"), "success", 82, 24))
        or W.TopButton(sec, M.Tr("Copy To"), 82, 24, nil, false)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, rowY)
    -- Opening the selector is safe in combat. The actual copy remains guarded
    -- in onRun below, where a blocked click can produce visible feedback.
    copy._msuf2AllowCombatClick = true
    copy._msuf2SkipHistoryCheckpoint = true
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
        controlDomain = "unit",
        controlPageKey = ctx and ctx.key,
        controlPath = "copy",
        assistantDisposition = "compound",
        assistantDispositionReason = "Copy actions apply a selected category set from this Unit page to a chosen destination.",
        width = 420,
        height = 304,
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
        onPopupCreated = function(popup)
            popup._msuf2GuidedNoScroll = true
            if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, popup, "Copy Player settings", "unit_copy_popup") end
        end,
        onRun = function(api, popup)
            -- Copy popup buttons deliberately bypass the generic combat-click
            -- proxy so this action owns the failure path instead of becoming a
            -- silent no-op before CopyUnitSettings is reached.
            if M.BlockCombatAction and M.BlockCombatAction() then return false end
            local dest = NormalizeCopyDest(unit)
            local destinationLabel = dest == "all" and M.Tr("All") or UnitTopLabel(dest)
            local function CopyFeedback(applied, result)
                result = type(result) == "table" and result or {}
                if applied == true then
                    local message = M.Format(M.Tr("Copied to %s"), destinationLabel)
                    if result.auraSkipped == true then
                        message = message .. " " .. M.Tr("Aura settings were skipped for unsupported UnitFrames.")
                    end
                    if result.castbarSkipped == true then
                        message = message .. " " .. M.Tr("Castbar settings were skipped for UnitFrames without Castbars.")
                    end
                    local skipped = result.auraSkipped == true or result.castbarSkipped == true
                    if M.ShowStatusFeedback then
                        M.ShowStatusFeedback(message, skipped and "warning" or "ok", 1.8)
                    end
                    popup:Hide()
                    return
                end
                local message
                if result.reason == "no_categories" then
                    message = M.Tr("No copy categories selected.")
                elseif result.reason == "unsupported_aura_scope" or result.reason == "aura_copy_unavailable" then
                    message = M.Tr("Aura settings are only available for Player, Target, Focus, and Boss Frames.")
                elseif result.reason == "unsupported_castbar_scope" then
                    message = M.Tr("Castbar settings are only available for Player, Target, Focus, and Boss Frames.")
                else
                    message = M.Tr("Nothing was copied.")
                end
                if M.ShowStatusFeedback then M.ShowStatusFeedback(message, "warning", 2.0) end
            end
            local function RunCopy(allConfirmed)
                return CopyUnitSettings(unit, dest, copyScopes, CopyFeedback, allConfirmed == true)
            end
            local historyKey = "unit:copy:" .. tostring(unit)
            if dest == "all" and type(ConfirmCopyToAll) == "function" then
                -- Confirm before opening the history transaction. The old order
                -- committed an empty undo step and announced success even when
                -- the player cancelled the confirmation dialog.
                ConfirmCopyToAll(function()
                    M.RunWithHistory("Copy Unit Settings", historyKey, function() RunCopy(true) end)
                end)
                return true
            else
                return M.RunWithHistory("Copy Unit Settings", historyKey, RunCopy)
            end
        end,
    })
    RegisterControl(copy, ctx, "copy.open", "Copy To", "button", "ephemeral")
    copy:SetScript("OnClick", function(self)
        if copyPopup then copyPopup.Show(self) end
    end)
    if type(M.RegisterGuidedCopyPopup) == "function" then
        M.RegisterGuidedCopyPopup("unit", ctx.key, function()
            local popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
            if popup and popup.IsShown and popup:IsShown() then return true end
            if copyPopup then copyPopup.Show(copy) end
            popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
            return popup and popup.IsShown and popup:IsShown() or false
        end)
    end
    sec:SetScript("OnHide", function()
        if copyPopup then copyPopup.Hide() end
    end)
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(sec, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = builder,
            ctx = ctx,
            flowGap = 8,
        })
    end
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
            sectionEntry.label:SetPoint("LEFT", sectionEntry.arrow, "RIGHT", 8, 0)
            sectionEntry.label:SetPoint("RIGHT", badge, "LEFT", -12, 0)
            sectionEntry.label:SetJustifyH("LEFT")
        end
    end
    local function RefreshBasicsState()
        T.ApplyCollapseVisual(sectionEntry.arrow, sectionEntry.hint, sectionEntry.open)
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        local on = ownOn and not parentOff
        local headerColor = on and EnabledHeaderColor() or WARNING_HEADER_BG
        if W.SetCollapsibleHeaderBaseTone then
            W.SetCollapsibleHeaderBaseTone(sectionEntry, headerColor, headerColor[4])
        elseif sectionEntry.headerBg then
            sectionEntry.headerBg:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], headerColor[4])
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
    end
    sectionEntry._msuf2BasicsHeaderRefresh = RefreshBasicsState
    RefreshBasicsState()
    return RefreshBasicsState
end
local function BuildBasics(ctx, builder, unit, label)
    -- Default-open so the page greets users with real settings instead of a
    -- stack of closed headers; saved accordion state still wins afterwards.
    -- Leave a full footer gutter below the disabled-frame notice. The next
    -- accordion header is created later and can otherwise cover the notice's
    -- lower edge at some UI scales.
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 216, true)
    if W.AttachContextColorReferences then
        local function EffectiveHealthMode()
            return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or GlobalHealthColorMode()
        end
        W.AttachContextColorReferences(sec, function()
            local mode = EffectiveHealthMode()
            local refs = {}
            local general = GetGeneral()
            if mode == "gradient" then
                refs = { "health.gradient.low", "health.gradient.mid", "health.gradient.high" }
            elseif mode == "unified" then
                refs = { "health.unified" }
            elseif mode == "class" then
                if unit == "pet" and general.petFrameUsePlayerClassColor == true then
                    refs = { "unit.class.current" }
                else
                    refs = { unit == "pet" and "unit.pet" or "health.current" }
                end
            end
            if general.barBgMatchHPColor ~= true and general.barBgClassColor ~= true then
                refs[#refs + 1] = "bar.background_tint"
            end
            refs[#refs + 1] = "bar.health_loss"
            return refs
        end, {
            title = M.Format("%s Health Colors", UnitTopLabel(unit)),
            note = "Colors follow this frame's effective Health Color Scheme.",
            historySource = "menu:unit-frame-basics-health-colors",
            maxTargets = 5,
            context = function()
                local context = { unit = unit, healthMode = EffectiveHealthMode() }
                if unit == "pet" and GetGeneral().petFrameUsePlayerClassColor == true and type(_G.UnitClass) == "function" then
                    local _, token = _G.UnitClass("player")
                    context.classToken = token
                end
                return context
            end,
        })
    end
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42
    local function SetHealthFillMode(key, peerKey, value, reason, historyLabel)
        value = value == true
        local function Write()
            local conf = GetConf(unit)
            local changed = conf[key] ~= value
            conf[key] = value
            if value and conf[peerKey] ~= false then
                conf[peerKey] = false
                changed = true
            end
            if not changed then return false end
            M.RequestUnitApply(unit, reason, { preview = true })
            if M.RequestRefresh then M.RequestRefresh(ctx, "unit-health-fill-mode") end
            return true
        end
        if type(M.RunWithHistory) == "function" then
            return M.RunWithHistory(historyLabel, "unit:" .. tostring(unit) .. ":healthFillMode", Write)
        end
        return Write()
    end
    local enable = W.SwitchAt(sec, "Enable", x1, row1, labelW)
    enable._msuf2UnitFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, enable,
        function() return ReadBool(unit, "enabled", true) end,
        function(v)
            SetBool(unit, "enabled", v, "MSUF2_FRAME_ENABLED", { preview = true })
            M.RequestOrRefresh(ctx, "frame-basics-enabled")
        end,
        SettingMeta(ctx, "basics.enabled", unit, "enabled"))
    -- Fill Direction (axis + in-axis direction) is a 4-way dropdown placed on
    -- its own row below Health Color Scheme; Smooth takes the freed x2 slot.
    local smooth = W.ToggleAt(sec, "Smooth fill", x2, row1, labelW)
    M.BindBoolWidget(ctx, smooth,
        function() return ReadBool(unit, "smoothFill", false) end,
        function(v) SetHealthFillMode("smoothFill", "chunkedFill", v, "MSUF2_SMOOTH_FILL", "Smooth health fill") end,
        SettingMeta(ctx, "basics.smooth_fill", unit, "smoothFill"))
    local chunked = W.ToggleAt(sec, "Chunked health loss", x3, row1, labelW)
    M.BindBoolWidget(ctx, chunked,
        function() return ReadBool(unit, "chunkedFill", false) end,
        function(v) SetHealthFillMode("chunkedFill", "smoothFill", v, "MSUF2_CHUNKED_FILL", "Chunked health loss") end,
        SettingMeta(ctx, "basics.chunked_fill", unit, "chunkedFill"))
    local blizzard = W.SwitchAt(sec, "Force Blizzard frame on", x1, -76, math.max(196, colW + 24))
    blizzard._msuf2UnitFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, blizzard,
        function() return ReadBool(unit, "useBlizzardFrame", false) end,
        function(v)
            if ReadBool(unit, "useBlizzardFrame", false) == (v == true) then return end
            SetBool(unit, "useBlizzardFrame", v, "MSUF2_BLIZZARD_FRAME_OWNERSHIP", { preview = false })
            local reloadLabel = M.Format("%s Blizzard frame ownership", label or UnitTopLabel(unit))
            if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                _G.MSUF_ShowReloadRecommendedPopup(reloadLabel)
            elseif print then
                print("|cffffd700MSUF:|r Changing Blizzard frame ownership requires a /reload.")
            end
        end,
        SettingMeta(ctx, "basics.force_blizzard_frame", unit, "useBlizzardFrame"))
    local blizzardHint = "Independent from MSUF Enable; /reload required."
    if unit == "targettarget" then
        blizzardHint = "Also keeps Blizzard Target visible; /reload required."
    elseif unit == "focustarget" then
        blizzardHint = "Also keeps Blizzard Focus visible; /reload required."
    end
    W.Text(sec, blizzardHint, x2, -80, math.max(190, sectionW - x2 - 14), T.colors.muted)
    if M.AddTooltip then
        local tooltip = M.Format("Keeps Blizzard's native frame active independently of the MSUF frame. Leave MSUF Enable on to show both, or turn MSUF Enable off to use only Blizzard. A UI reload is required.")
        if unit == "targettarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Target of Target is a child of Blizzard Target, so both native frames must remain active.")
        elseif unit == "focustarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Focus Target is a child of Blizzard Focus, so both native frames must remain active.")
        end
        M.AddTooltip(blizzard, "Force Blizzard frame on", tooltip, { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local colorMode = W.Dropdown(sec, "Health Color Scheme", HealthColorModeOptions, math.min(270, math.max(220, colW * 2)))
    UnitSectionShared.PlaceDropdown(sec, colorMode, x1, -116, math.min(270, math.max(220, colW * 2)))
    M.BindDropdownWidget(ctx, colorMode,
        function()
            return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or HEALTH_COLOR_GLOBAL
        end,
        function(v)
            local conf = GetConf(unit)
            conf.healthColorMode = NormalizeHealthColorMode(v)
            M.RequestUnitApply(unit, "MSUF2_HEALTH_COLOR_MODE", { preview = true, colors = true })
            if M.Refresh then M.Refresh(ctx) end
        end,
        SettingMeta(ctx, "basics.health_color_mode", unit, "healthColorMode"))
    if M.AddTooltip then
        M.AddTooltip(colorMode, "Health Color Scheme", "Use Global follows the Unitframe Global Coloring mode from Colors. Other choices override only this frame.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    -- Shares the Health Color Scheme row so the section stays within its
    -- declared height instead of overlapping the next accordion header. Snap to
    -- the column grid when there is room, otherwise sit just right of the
    -- width-capped Health Color Scheme dropdown; clamp the width so it never
    -- runs into the third column (Pet keeps its class-color toggle there).
    local fillDirW = math.min(270, math.max(220, colW * 2))
    local fillDirX = math.max(x2, x1 + fillDirW + gap)
    local fillDirFit = (x3 - gap) - fillDirX
    if fillDirFit > 0 and fillDirW > fillDirFit then fillDirW = fillDirFit end
    local fillDir = W.Dropdown(sec, "Fill Direction", FILL_DIRECTION_OPTIONS, fillDirW)
    UnitSectionShared.PlaceDropdown(sec, fillDir, fillDirX, -116, fillDirW)
    M.BindDropdownWidget(ctx, fillDir,
        function()
            return FillDirectionValue(ReadBool(unit, "reverseFillBars", false), ReadBool(unit, "verticalFillBars", false))
        end,
        function(v)
            local state = FILL_DIRECTION_STATE[v] or FILL_DIRECTION_STATE.lr
            -- Write both booleans, then a single apply/preview (mirrors the
            -- Health Color Scheme setter) so a 4-way change never double-applies.
            local conf = GetConf(unit)
            conf.reverseFillBars = state.reverse
            conf.verticalFillBars = state.vertical
            M.RequestUnitApply(unit, "MSUF2_FILL_DIRECTION", { preview = true })
            if M.Refresh then M.Refresh(ctx) end
        end,
        SettingMeta(ctx, "basics.fill_direction", unit, "verticalFillBars"))
    if M.AddTooltip then
        M.AddTooltip(fillDir, "Fill Direction", "Axis and direction the Health and Power bars fill. Vertical options fill bottom-to-top or top-to-bottom; combines with Smooth fill.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local petPlayerClassColor
    if unit == "pet" then
        petPlayerClassColor = W.ToggleAt(sec, "Player Class Color", x3, -116, labelW)
        M.BindBoolWidget(ctx, petPlayerClassColor,
            function() return GetGeneral().petFrameUsePlayerClassColor == true end,
            function(v)
                GetGeneral().petFrameUsePlayerClassColor = v and true or false
                M.RequestUnitApply("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                if M.Refresh then M.Refresh(ctx) end
            end,
            SettingMeta(ctx, "basics.use_player_class_color", "general", "petFrameUsePlayerClassColor"))
        if M.AddTooltip then
            M.AddTooltip(petPlayerClassColor, "Use player's class color for Pet Frame",
                "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", { hook = true, owner = "ANCHOR_RIGHT" })
        end
    end
    if W.AttachUnitEditFocus then
        for _, control in ipairs({ enable, smooth, chunked, blizzard, colorMode, fillDir, petPlayerClassColor }) do
            W.AttachUnitEditFocus(control, unit, "frame")
        end
    end
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local RefreshBasicsState = AttachBasicsHeaderStatus(sec, unit) or function() end
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end
    local unitLabel = label or UnitTopLabel(unit)
    local notice, _, enableNow = UnitSectionShared.CreateSectionNotice(sec, -164, "Enable", 92)
    local enableShortcutMeta
    if unit ~= "focustarget" then
        enableShortcutMeta = {
            settingKey = unit .. ".enabled",
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return ReadBool(unit, "enabled", true) end,
                set = function(value) SetBool(unit, "enabled", value == true, "MSUF2_FRAME_ENABLED", { preview = true }) end,
            },
        }
    else
        enableShortcutMeta = {
            actionKey = "enable_focus_target_frame",
        }
    end
    RegisterControl(enableNow, ctx, "basics.enable_now", "Enable", "button",
        unit ~= "focustarget" and "setting" or "action", enableShortcutMeta)
    notice:SetMessage(M.Format("%s frame is disabled and will not appear.", unitLabel), "warning")
    enableNow:SetScript("OnClick", function()
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true }) end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        M.RequestOrRefresh(ctx, "frame-basics-enable-now")
    end)
    notice:Hide()
    local basicsDependentControls = { smooth, chunked, colorMode, fillDir }
    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        SetControlEnabled(enable, true)
        SetControlEnabled(blizzard, true)
        SetControlsEnabled(basicsDependentControls, ownOn)
        if parentOff then
            notice:SetMessage(M.Tr("Focus Target follows the Focus frame. Enable Focus to show it."), "warning")
            if enableNow.SetText then enableNow:SetText(M.Tr("Enable Focus")) end
        else
            notice:SetMessage(M.Format("%s frame is disabled and will not appear.", unitLabel), "warning")
            if enableNow.SetText then enableNow:SetText(M.Tr("Enable")) end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
    end
    M.TrackRefresh(ctx, RefreshBasicsEnabled)
end
local function BuildLayout(ctx, builder, unit)
    local sec = builder:CollapsibleSection("anchoring", "Anchoring", 306, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, sectionW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
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
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = "Custom: " .. text }
        end
        for i = 1, #anchorChoices do
            local item = anchorChoices[i]
            if item.value == "GLOBAL" or item.value ~= unit then
                if item.value == "GLOBAL" and automaticProviderLabel and cooldownAnchorEnabled then
                    values[#values + 1] = {
                        value = "GLOBAL",
                        text = M.Format("Global anchor (%s Anchor)", automaticProviderLabel),
                    }
                else
                    values[#values + 1] = item
                end
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
    local anchorTo = W.Dropdown(sec, "Anchor To", AnchorValues, anchorControlW)
    UnitSectionShared.PlaceDropdown(sec, anchorTo, anchorLeftX, -38, anchorControlW)
    W.AttachUnitEditFocus(anchorTo, unit, "anchoring")
    M.BindDropdownWidget(ctx, anchorTo,
        AnchorValue,
        function(v)
            if v == "__CUSTOM" then return end
            local conf = GetConf(unit)
            conf.anchorToUnitframe = v or "GLOBAL"
            conf.anchorFrameName = nil
            ApplyAnchorChange()
        end,
        ReviewedMeta(ctx, "anchoring.anchor_to", "setting", "compound",
            "Changing the anchor target also clears any custom anchor frame name."))
    local anchorPoint = W.Dropdown(sec, "Anchor Point", anchorPoints, anchorControlW)
    UnitSectionShared.PlaceDropdown(sec, anchorPoint, anchorRightX, -38, anchorControlW)
    W.AttachUnitEditFocus(anchorPoint, unit, "anchoring")
    M.BindDropdownWidget(ctx, anchorPoint,
        AnchorPointValue,
        function(v)
            local conf = GetConf(unit)
            v = v or "CENTER"
            conf.point = v
            conf.relativePoint = v
            ApplyAnchorChange()
        end,
        ReviewedMeta(ctx, "anchoring.anchor_point", "setting", "compound",
            "Changing the anchor point writes both point and relativePoint together."))
    local function SetCustomAnchorValue(value)
        value = value or ""
        local conf = GetConf(unit)
        conf.anchorFrameName = (value ~= "") and value or nil
        if value ~= "" or CustomAnchorName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        ApplyAnchorChange()
    end
    local customAnchor = UnitSectionShared.CustomAnchorEditor(ctx, sec, {
        x = anchorLeftX,
        y = -112,
        width = customAnchorW,
        getValue = function() return CustomAnchorName(GetConf(unit)) end,
        setValue = function(value) SetCustomAnchorValue(value) end,
        isCandidateAllowed = function(frame)
            local factory = MSUF.UF and MSUF.UF.Factory
            return not factory or type(factory.IsAnchorCandidateAllowed) ~= "function"
                or factory.IsAnchorCandidateAllowed(frame, unit)
        end,
        clearValue = function()
            SetCustomAnchorValue("")
        end,
        commitTitle = "Set Unit Anchor",
        commitKey = function() return "unit:anchorCustom:" .. tostring(unit) end,
        pickTitle = "Pick custom anchor",
        pickKey = function() return "unit:anchorPick:" .. tostring(unit) end,
        attachFocus = function(widget) W.AttachUnitEditFocus(widget, unit, "anchoring") end,
        controlDomain = "unit",
        controlPageKey = ctx and ctx.key,
        controlPath = "anchoring.custom",
        assistantDisposition = "compound",
        assistantDispositionReason = "Custom anchor editing coordinates anchorFrameName with anchorToUnitframe.",
    })
    customAnchor.clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        if CustomAnchorName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        customAnchor.box:SetText("")
        ApplyAnchorChange()
    end)
    RegisterControl(customAnchor.clear, ctx, "anchoring.custom.clear", "Clear", "button", "action", {
        actionKey = "clear_unit_custom_anchor", actionFixedArgs = { unit = unit },
    })
    RegisterControl(customAnchor.pick, ctx, "anchoring.custom.pick", "Pick", "button", "action", {
        actionKey = "start_unit_custom_anchor_picker", actionFixedArgs = { unit = unit },
    })
    local cooldownAnchor = W.SwitchAt(sec, "Follow Blizzard's Essential Cooldowns", anchorLeftX, -184, anchorInnerW)
    M.BindBoolWidget(ctx, cooldownAnchor,
        CooldownAnchorEnabled,
        function(enabled)
            local setter = _G.MSUF_SetCooldownAnchorEnabled
            if type(setter) == "function" then
                setter(enabled, true)
            else
                local general = GetGeneral()
                general.anchorToCooldown = enabled == true
            end
            M.RequestOrRefresh(ctx, "unit-anchoring-cooldown-manager")
        end,
        SettingMeta(ctx, "anchoring.cooldown_manager", "general", "anchorToCooldown"))
    local automaticNotice = UnitSectionShared.CreateSectionNotice(sec, -238)
    local function RefreshLayoutState()
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        local cooldownAnchorLabel = automaticProviderLabel and (automaticProviderLabel .. " Anchor") or M.Tr("Follow Blizzard's Essential Cooldowns")
        if cooldownAnchor._msuf2Label and cooldownAnchor._msuf2Label.SetText then
            cooldownAnchor._msuf2Label:SetText(cooldownAnchorLabel)
        end
        customAnchor.Refresh()
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
        if anchorPoint.SetValue then anchorPoint:SetValue(AnchorPointValue()) end
        if automaticProviderLabel then
            if cooldownAnchorEnabled then
                automaticNotice:SetMessage(M.Format(
                    "%s detected: Global anchor follows Essential Cooldown Manager. Toggle Cooldown in MSUF Edit Mode to turn it off.",
                    automaticProviderLabel
                ), "info")
            else
                automaticNotice:SetMessage(M.Format(
                    "%s detected: Cooldown Manager anchoring is off. Toggle Cooldown in MSUF Edit Mode to turn it on.",
                    automaticProviderLabel
                ), "info")
            end
            automaticNotice:Show()
            local accent = (T.colors and (cooldownAnchorEnabled and (T.colors.ok or T.colors.accent) or T.colors.muted))
                or (cooldownAnchorEnabled and { 0.52, 0.76, 0.58, 1 } or { 0.55, 0.58, 0.66, 1 })
            SetSectionHeaderStatus(sec, {
                hint = automaticProviderLabel .. " Anchor " .. (cooldownAnchorEnabled and "ON" or "OFF"),
                hintColor = accent,
            })
        else
            automaticNotice:Hide()
            SetSectionHeaderStatus(sec, nil)
        end
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
        RequestUnitRuntimeApply("target", reason, inlineApplyFlags)
        RequestUnitRuntimeApply("targettarget", reason, inlineApplyFlags, forceToT == true)
        Call("MSUF_UpdateTargetToTInlineNow")
        if not skipRefresh and RefreshInlineControlState then RefreshInlineControlState() end
    end
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(sec, {
            title = "Inline Text Settings",
            historyLabel = "Inline text color",
            historySource = "menu:target-inline-text-color",
            textSettings = {
                scope = "target",
                unit = "target",
                kind = "inline",
                colorReferences = { "text.inline_tot.current" },
                colorTitle = "Inline Text Color",
                colorModeValues = ToTInlineColorOptions,
                getColorMode = function()
                    return ToTInlineColorDropdownValue(GetConf("targettarget"))
                end,
                setColorMode = function(value)
                    GetConf("targettarget").totInlineColorMode = NormalizeToTInlineColorMode(value)
                    ApplyToTInline("MSUF2_TOT_INLINE_COLOR", true)
                end,
                subtitle = "Font style follows Target Fonts; color mode follows Inline color.",
            },
        })
    end
    local show = W.Toggle(sec, "Show Target of Target text inline")
    M.BindBoolWidget(ctx, show,
        function() return GetConf("targettarget").showToTInTargetName == true end,
        function(v)
            local conf = GetConf("targettarget")
            conf.showToTInTargetName = v and true or false
            ApplyToTInline("MSUF2_TOT_INLINE")
        end,
        SettingMeta(ctx, "inline_text.show_target_of_target", "targettarget", "showToTInTargetName"))
    local color = W.Dropdown(sec, "Inline color", ToTInlineColorOptions, rightW)
    W.MoveWidget(color, sec, rightX, -72, rightW)
    M.BindDropdownWidget(ctx, color,
        function() return ToTInlineColorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            conf.totInlineColorMode = NormalizeToTInlineColorMode(v)
            ApplyToTInline("MSUF2_TOT_INLINE_COLOR", true)
        end,
        SettingMeta(ctx, "inline_text.color", "targettarget", "totInlineColorMode"))
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
        end,
        SettingMeta(ctx, "inline_text.separator", "targettarget", "totInlineSeparator"))
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
        true,
        SettingMeta(ctx, "inline_text.custom_separator", "targettarget", "totInlineCustomSeparator"))
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
                height = 724,
                build = function(lazyCtx, lazyBuilder, lazyUnit)
                    return fn(lazyCtx, lazyBuilder, lazyUnit)
                end,
            })
        end
        return fn(ctx, builder, unit)
    end
end
local function BuildLoadConditions(ctx, builder, unit)
    local sec = builder:CollapsibleSection("load_conditions", "Load Conditions", 178, false)
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
            end,
            SettingMeta(ctx, "load_condition." .. tostring(spec.key), unit, spec.key))
    end
    local function RefreshLoadConditionState()
        SetSectionHeaderStatus(sec, nil)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshLoadConditionState)
end
local BOSS_LAYOUT_TILE_VALUES = {
    { value = "VERTICAL_DOWN", text = "Down", tooltip = "Vertical (top -> bottom)", dx = 0, dy = -1, arrow = "v" },
    { value = "VERTICAL_UP", text = "Up", tooltip = "Vertical (bottom -> top)", dx = 0, dy = 1, arrow = "^" },
    { value = "HORIZONTAL_RIGHT", text = "Right", tooltip = "Horizontal (left -> right)", dx = 1, dy = 0, arrow = ">" },
    { value = "HORIZONTAL_LEFT", text = "Left", tooltip = "Horizontal (right -> left)", dx = -1, dy = 0, arrow = "<" },
}
local function BuildBossLayoutTiles(parent, x, y, tileW, tileH, gap)
    if not parent then return nil end
    tileW, tileH, gap = tileW or 64, tileH or 70, gap or 8
    local control = CreateFrame("Frame", nil, parent)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -44)
    control:SetSize((tileW * #BOSS_LAYOUT_TILE_VALUES) + (gap * (#BOSS_LAYOUT_TILE_VALUES - 1)), tileH + 20)
    control._msuf2ControlKind = "segment"
    control.values = BOSS_LAYOUT_OPTIONS
    control.buttons = {}

    local title = T.Font(control, "GameFontNormalSmall", M.Tr("Boss frame layout"), T.colors.accent)
    title:SetPoint("TOPLEFT", control, "TOPLEFT", 0, 0)
    control._msuf2Title = title

    local function SetTileVisual(btn, active, hover)
        if not btn then return end
        if btn.SetBackdropColor then
            if active then
                btn:SetBackdropColor(0.100, 0.180, 0.300, hover and 0.98 or 0.92)
                btn:SetBackdropBorderColor(0.260, 0.620, 1.000, 1.00)
            elseif hover then
                btn:SetBackdropColor(0.115, 0.135, 0.185, 0.95)
                btn:SetBackdropBorderColor(0.380, 0.450, 0.620, 0.95)
            else
                btn:SetBackdropColor(0.045, 0.052, 0.076, 0.92)
                btn:SetBackdropBorderColor(0.190, 0.220, 0.310, 0.85)
            end
        end
        if btn._label then
            if active then
                btn._label:SetTextColor(0.95, 1.00, 1.00, 1)
            else
                btn._label:SetTextColor(0.74, 0.80, 0.90, 0.95)
            end
        end
    end

    local function DrawMiniBossPreview(btn, info)
        if not (btn and info) then return end
        btn._frames = btn._frames or {}
        local count = 5
        local pad = 6
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local frameGap = 2
        local frameW, frameH
        if info.dy ~= 0 then
            frameW = math.max(18, math.floor(innerW * 0.82))
            frameH = math.max(4, math.floor((innerH - ((count - 1) * frameGap)) / count))
        else
            frameW = math.max(6, math.floor((innerW - ((count - 1) * frameGap)) / count))
            frameH = math.max(14, math.floor(innerH * 0.56))
        end
        local totalW = (info.dy ~= 0) and frameW or ((count * frameW) + ((count - 1) * frameGap))
        local totalH = (info.dy ~= 0) and ((count * frameH) + ((count - 1) * frameGap)) or frameH
        local originX = pad + math.floor((innerW - totalW) * 0.5 + 0.5)
        local originY = -pad - math.floor((innerH - totalH) * 0.5 + 0.5)
        for i = 1, count do
            local tex = btn._frames[i]
            if not tex then
                tex = btn:CreateTexture(nil, "ARTWORK")
                btn._frames[i] = tex
            end
            local orderIndex = i - 1
            local visualIndex = orderIndex
            if info.dy == 1 or info.dx == -1 then visualIndex = count - i end
            local px = originX
            local py = originY
            if info.dy == 0 then px = originX + (visualIndex * (frameW + frameGap)) end
            if info.dy ~= 0 then py = originY - (visualIndex * (frameH + frameGap)) end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", btn, "TOPLEFT", px, py)
            tex:SetSize(frameW, frameH)
            if i == 1 then
                tex:SetColorTexture(0.120, 0.950, 0.620, 0.98)
            elseif i <= 3 then
                tex:SetColorTexture(0.220, 0.580, 0.940, 0.76)
            else
                tex:SetColorTexture(0.160, 0.360, 0.640, 0.42)
            end
            tex:Show()
        end
        if not btn._firstText then
            btn._firstText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._firstText.SetFont then btn._firstText:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
            btn._firstText:SetText("1")
            btn._firstText:SetTextColor(0, 0, 0, 1)
        end
        local firstVisualIndex = (info.dy == 1 or info.dx == -1) and (count - 1) or 0
        btn._firstText:ClearAllPoints()
        btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
            originX + ((info.dy == 0 and firstVisualIndex or 0) * (frameW + frameGap)) + (frameW * 0.5),
            originY - ((info.dy ~= 0 and firstVisualIndex or 0) * (frameH + frameGap)) - (frameH * 0.5))
        btn._firstText:Show()

        if not btn._arrow then
            btn._arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._arrow.SetFont then btn._arrow:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("caption"), "OUTLINE") end
            btn._arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
        btn._arrow:SetText(info.arrow)
        btn._arrow:ClearAllPoints()
        if info.dy == -1 then
            btn._arrow:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
        elseif info.dy == 1 then
            btn._arrow:SetPoint("TOP", btn, "TOP", 0, -4)
        elseif info.dx == 1 then
            btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -4, labelH * 0.5)
        else
            btn._arrow:SetPoint("LEFT", btn, "LEFT", 4, labelH * 0.5)
        end
        btn._arrow:Show()
    end

    function control:SetValue(value)
        local current = NormalizeBossLayoutMode(value)
        self._msuf2Value = current
        for i = 1, #BOSS_LAYOUT_TILE_VALUES do
            local btn = self.buttons[i]
            local info = BOSS_LAYOUT_TILE_VALUES[i]
            if btn then
                DrawMiniBossPreview(btn, info)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end

    for i = 1, #BOSS_LAYOUT_TILE_VALUES do
        local info = BOSS_LAYOUT_TILE_VALUES[i]
        local btn = CreateFrame("Button", nil, control, T.Template and T.Template() or nil)
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", control, "TOPLEFT", (i - 1) * (tileW + gap), -20)
        btn._msuf2Value = info.value
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if text.SetFont then text:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
        text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
        text:SetText(M.Tr(info.text or ""))
        btn._label = text
        btn:SetScript("OnEnter", function(self) SetTileVisual(self, control._msuf2Value == info.value, true) end)
        btn:SetScript("OnLeave", function(self) SetTileVisual(self, control._msuf2Value == info.value, false) end)
        M.AddTooltip(btn, function() return M.Format(M.Tr("Boss frame layout: %s"), M.Tr(info.tooltip or info.text or "")) end, "Click to set how boss frames are arranged.", { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        control.buttons[i] = btn
    end
    control:SetValue("VERTICAL_DOWN")
    return control
end
local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = builder:CollapsibleSection("boss_layout", "Boss Layout", 204, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(sec, { "highlight.boss_target" }, {
            title = "Boss Target Highlight Color",
            historySource = "menu:unit-boss-target-highlight-color",
        })
    end
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    local spacing = W.Slider(sec, "Boss spacing", -400, 0, 1, 300)
    W.MoveWidget(spacing, sec, leftX, -42, sliderW, "CENTER")
    M.BindNumberWidget(ctx, spacing,
        function() return ReadNumber(unit, "spacing", -36) end,
        function(v) SetNumber(unit, "spacing", v, "MSUF2_BOSS_SPACING", { preview = true }) end,
        -36, (function()
            local meta = SettingMeta(ctx, "boss_layout.spacing", unit, "spacing")
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    local layout = BuildBossLayoutTiles(sec, rightX, -42, 60, 70, 8)
    M.BindSegment(ctx, layout,
        function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, conf.invertBossOrder)
        end,
        function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            conf.invertBossOrder = nil
            M.RequestUnitApply(unit, "MSUF2_BOSS_LAYOUT_MODE", { preview = true })
        end,
        SettingMeta(ctx, "boss_layout.mode", unit, "bossLayoutMode"))
    local highlight = W.ToggleAt(sec, "Boss target highlight", leftX, -156, 260)
    M.BindBoolWidget(ctx, highlight,
        function() return ReadGeneralBool("bossTargetHighlightEnabled", true) end,
        function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v and true or false
            g.bossTargetOutlineMode = v and 1 or 0
            M.RequestUnitApply("boss", "MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
        end,
        SettingMeta(ctx, "boss_layout.target_highlight", "general", "bossTargetHighlightEnabled"))
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
                if active and type(M.RequestBossPagePreviewForKey) == "function" then
                    M.RequestBossPagePreviewForKey("uf_boss")
                    return
                end
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
            height = 216,
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
            -- This workspace owns nested Buff/Debuff/Custom sections and previews;
            -- the lazy one-section proxy would stack those sections into one body.
            M.BuildAuras3UnitSection(ctx, builder, info.unit)
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_auras") end
        if info.unit == "target" then
            BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildInlineText, { sectionId = "inline_text", title = "Inline Text", height = 214 })
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_inline_text") end
        BuildStatus(ctx, builder, info.unit)
        if info.unit == "boss" then
            BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildBossLayout, { sectionId = "boss_layout", title = "Boss Layout", height = 204 })
        end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLoadConditions, { sectionId = "load_conditions", title = "Load Conditions", height = 178 })
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, info.unit, "after_load_conditions") end
        BuildUnitSectionMaybeLazy(ctx, builder, info.unit, BuildLayout, { sectionId = "anchoring", title = "Anchoring", height = 220 })
        M.TrackRefresh(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, info.unit)
        end)
        if builder.RelayoutCollapsibles then builder:RelayoutCollapsibles() end
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end
for key, info in pairs(UNIT_PAGES) do
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 29,
    })
end
