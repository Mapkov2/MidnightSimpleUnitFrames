local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Core functions this page calls by their global names: required here at load.
M.RequireGlobals(FILE, {
    "MSUF_ShowReloadRecommendedPopup",
    "MSUF_ApplyRoundedUnitframes",
})
-- Resolved once at load, so the value and refresh paths that call them (setters, the apply
-- request, the anchor refresh) never resolve a name.
local Core = {
    ShowReloadPopup = MSUF.Require("MSUF_ShowReloadRecommendedPopup", FILE),
    ApplyRounded = MSUF.Require("MSUF_ApplyRoundedUnitframes", FILE),
    ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE),
    AutomaticProvider = MSUF.Require("MSUF_GetAutomaticCooldownAnchorProvider", FILE),
    CooldownEnabled = MSUF.Require("MSUF_IsCooldownAnchorEnabled", FILE),
    SetCooldownEnabled = MSUF.Require("MSUF_SetCooldownAnchorEnabled", FILE),
}
local EnsureDB = M.EnsureDB
local C_Timer = M.MenuTimer or C_Timer

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
local UNIT_PAGES, LOAD_CONDITIONS, BOSS_LAYOUT_OPTIONS = UP.UNIT_PAGES or {}, UP.LOAD_CONDITIONS or {}, UP.BOSS_LAYOUT_OPTIONS or {}
local SEPARATORS, UF_COPY_CATEGORIES = UP.SEPARATORS or {}, UP.UF_COPY_CATEGORIES or {}
local GetConf, GetGeneral, DefaultCopyTarget, UnitTopLabel = UP.GetConf, UP.GetGeneral, UP.DefaultCopyTarget, UP.UnitTopLabel
local UnitTopLabelKey = UP.UnitTopLabelKey
local UnitTopPillWidth, NewCopyScopeDefaults, ConfirmCopyToAll = UP.UnitTopPillWidth, UP.NewCopyScopeDefaults, UP.ConfirmCopyToAll
local CopyUnitSettings, ReadBool = UP.CopyUnitSettings, UP.ReadBool
local SetBool, ReadNumber = UP.SetBool, UP.ReadNumber
local SetControlEnabled, NormalizeBossLayoutMode, UpdateLoadActive = UP.SetControlEnabled, UP.NormalizeBossLayoutMode, UP.UpdateLoadActive
local SettingMeta, RegisterControl = UP.SettingMeta, UP.RegisterControl
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
-- Lazy shells declare their header before the body builds, as the pilot sections do.
local function DeclareSection(_, section, unit) Schema.Section(section, unit) end
-- Hover options the Basics and Visibility tips share (AddTooltip only reads them).
local TIP_OPTS = { hook = true, owner = "ANCHOR_RIGHT" }
local UNIT_ANCHOR_SECTION_HEIGHT = 306
local UNIT_AURAS_MENU_UNITS = M.KeySetFromWords "player pet target focus boss arena"
local TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOT_INLINE_CUSTOM_SEPARATOR_MAX = 5
local TOT_INLINE_COLOR_AUTO = "AUTO"
local TOT_INLINE_COLOR_TOT_NAME = "TOT_NAME"
local TOT_INLINE_COLOR_TARGET_NAME = "TARGET_NAME"
local TOT_INLINE_COLOR_NPC = "NPC"
local TOT_INLINE_COLOR_DEFAULT = "DEFAULT"
local TOT_INLINE_COLOR_VALUES = M.KeySet(TOT_INLINE_COLOR_AUTO, TOT_INLINE_COLOR_TOT_NAME, TOT_INLINE_COLOR_TARGET_NAME,
    TOT_INLINE_COLOR_NPC, TOT_INLINE_COLOR_DEFAULT)
local HEALTH_COLOR_GLOBAL = "GLOBAL"
local HEALTH_COLOR_LABELS = {
    class = "Class / Reaction",
    gradient = "Health Gradient",
    unified = "Unified Color",
    dark = "Dark Mode",
}
local HEALTH_COLOR_ALIASES = {}
local HEALTH_COLOR_OPTIONS = { { value = HEALTH_COLOR_GLOBAL, text = "Use Global" } }
for _, mode in ipairs({ "class", "gradient", "unified", "dark" }) do
    HEALTH_COLOR_ALIASES[mode], HEALTH_COLOR_ALIASES[mode:upper()] = mode, mode
    HEALTH_COLOR_OPTIONS[#HEALTH_COLOR_OPTIONS + 1] = { value = mode, text = HEALTH_COLOR_LABELS[mode] }
end
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

local AutomaticCooldownProvider = Core.AutomaticProvider
--- The Integrations module answers whether the switch is on.
local function CooldownAnchorEnabled()
    return Core.CooldownEnabled(GetGeneral and GetGeneral() or nil) == true
end
--- Hides the anchor switch on clients that can never host a Cooldown Manager.
local CooldownAnchorSupported = MSUF.Require("MSUF_CooldownAnchorSupported", FILE)

local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
local ENABLED_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local TINTED_ENABLED_HEADER_BG = { 0, 0, 0, 0.48 }
local function EnabledHeaderColor()
    if T.classicAtlas or T.menuAppearancePreset == "midnightDark"
        or (T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted()) then
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


local function RequestUnitRuntimeApply(unit, reason, opts, flushNow)
    opts = opts or {}
    opts.history = false
    if M and type(M.RequestUnitDomains) == "function" then
        local ok = M.RequestUnitDomains(unit, reason or "MSUF2_UNIT_SECTION", opts) ~= false
        if ok and flushNow then Core.ApplyService.Flush() end
        return ok
    end
    Core.ApplyService.RequestUnitDomains(unit, reason or "MSUF2_UNIT_SECTION", opts)
    if flushNow then Core.ApplyService.Flush() end
    return true
end
local UF_COPY_TARGET_ORDER = { "player", "target", "targettarget", "focustarget", "focus", "boss", "arena", "pet", "pettarget", "all" }
-- The Copy To popup offers only frames the client can produce
-- (MSUF.Client.SupportsUnit): WoW Forever has no arena, TBC no boss, and
-- Classic Era no focus, focus target, boss or arena frames.
if type(M.SupportsFrameScope) == "function" then
    local kept = {}
    for i = 1, #UF_COPY_TARGET_ORDER do
        local target = UF_COPY_TARGET_ORDER[i]
        if target == "all" or M.SupportsFrameScope(target) then kept[#kept + 1] = target end
    end
    UF_COPY_TARGET_ORDER = kept
end
local UF_COPY_TARGET_WIDTHS = { player = 48, target = 50, targettarget = 38, focustarget = 34, focus = 48, boss = 46, arena = 50, pet = 38,
    pettarget = 40, all = 38 }
local UF_COPY_TARGET_SHORT_LABELS = { targettarget = "ToT", focustarget = "FT", pettarget = "PT", boss = "Boss", arena = "Arena", all = "All" }
local UNIT_TAB_ORDER = { "player", "target", "boss", "arena", "focus", "pet", "pettarget", "targettarget", "focustarget" }
local UNIT_TAB_LABELS = { boss = "Boss Frames", arena = "Arena Frames", targettarget = "Target of Target", focustarget = "Focus Target",
    pettarget = "Pet Target" }
local UNIT_TAB_COMPACT_LABELS = { boss = "Boss", arena = "Arena", targettarget = "ToT", focustarget = "FT", pettarget = "PT" }
local UNIT_TAB_WIDTHS = { player = 58, target = 62, boss = 92, arena = 96, focus = 58, pet = 46, targettarget = 108, focustarget = 98, pettarget = 90 }
local UNIT_TAB_COMPACT_WIDTHS = { player = 50, target = 54, boss = 54, arena = 56, focus = 50, pet = 40, targettarget = 42, focustarget = 36, pettarget = 36 }
local UNIT_PAGE_FOR_UNIT = {}
for pageKey, pageInfo in pairs(UNIT_PAGES or {}) do
    if pageInfo and pageInfo.unit then UNIT_PAGE_FOR_UNIT[pageInfo.unit] = pageKey end
end
-- Raw label keys: the scope bar translates its own buttons.
local function UnitTopTabKey(unit, compact)
    if compact then return UNIT_TAB_COMPACT_LABELS[unit] or UNIT_TAB_LABELS[unit] or UnitTopLabelKey(unit) end
    return UNIT_TAB_LABELS[unit] or UnitTopLabelKey(unit)
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
    if type(token) == "string" and token ~= "" then return TOT_INLINE_SEPARATOR_VALUES[token] and (token == " " and "" or token)
        or TOT_INLINE_CUSTOM_SEPARATOR end
    return "|"
end
local function NormalizeToTInlineColorMode(value)
    value = tostring(value or "")
    if TOT_INLINE_COLOR_VALUES[value] then return value end
    return TOT_INLINE_COLOR_AUTO
end
-- The stored choice, also while NPC colours are off (the option is then disabled, so NPC cannot be newly
-- picked): the runtime, the colour picker and the preview keep using it, and the page never rewrites it.
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
        mode = g and g.useClassColors == true and "class" or "dark"
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
    local db = EnsureDB()
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
local function UnitFrameEnabled(unit)
    return ReadBool(unit, "enabled", true)
        and (unit ~= "focustarget" or ReadBool("focus", "enabled", true))
end
-- Hover reason for every control a turned-off frame locks (the notice wording).
function UP.FrameDisabledReason(unit)
    if unit == "focustarget" and not ReadBool("focus", "enabled", true) then
        return M.Tr("Focus Target follows the Focus frame. Enable Focus to show it.")
    end
    return M.Format("%s frame is disabled and will not appear.", UnitTopLabel(unit))
        .. "\n" .. M.Format("Turn on \"%s\" to change this.", M.Tr("Enable"))
end
local function ApplyUnitFrameEnabledGate(ctx, unit)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local enabled = UnitFrameEnabled(unit)
    local gateKey = "unitFrameEnabled:" .. tostring(unit)
    local gateReasons = W._msuf2GateReasons
    if W.SetGateDisabledReason and not (gateReasons and gateReasons[gateKey]) then
        W.SetGateDisabledReason(gateKey, function() return UP.FrameDisabledReason(unit) end)
    end
    if ControlGates.ApplySections then
        ControlGates.ApplySections(ctx, gateKey, enabled, {
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
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus
-- Page-level previews are fixed chrome, not form content. Keep their geometry
-- bounded so the settings ScrollFrame always starts below a predictable header.
local UNIT_PREVIEW_BOX_HEIGHT = 132
local UNIT_PREVIEW_EXPANDED_HEIGHT = 358
local UNIT_PREVIEW_SECTION_HEIGHT = 180
local UNIT_PREVIEW_TOP_OFFSET = -40
-- The page preview controller. One state table P per built page holds the shared preview
-- box with its host panel, the expander record and the queued-refresh bookkeeping; the
-- steps below read and write it instead of closing over per-build upvalues.
local Preview = {}
function Preview.RegisterControls(box, ctx)
    local preview = MSUF.UFPreview
    if preview and type(preview.RegisterRuntimeControlsForPage) == "function" then
        preview.RegisterRuntimeControlsForPage(box, ctx and ctx.key)
    end
end
function Preview.SetOwner(P, target)
    local ctx, expander = P.ctx, P.expander
    target = target or P.box
    if not target then return end
    target._msuf2UnitPageHostShown = P.hostShown
    target._msuf2PinnedPreviewPageKey = ctx and ctx.key
    target._msuf2PinnedPreviewWrapper = ctx and ctx.wrapper
    if not (expander and expander.expanded) then target._msuf2PinnedFloating = nil end
    target._msuf2PreferredRestoreHeight = expander and expander.expanded
        and UNIT_PREVIEW_EXPANDED_HEIGHT or UNIT_PREVIEW_BOX_HEIGHT
    target._msuf2PreferredRestoreYOffset = UNIT_PREVIEW_TOP_OFFSET
    target._msuf2CompactHeader = P.header
    target._msuf2CompactExpandButton = expander and expander.button or nil
    target._msuf2FixedPreviewExpanderRecord = expander
end
function Preview.EnsureAttachment(P)
    local box, ctx = P.box, P.ctx
    if not box then return end
    local record = box._msuf2PinnedPreviewRecord
    local pageKey = ctx and ctx.key
    local wrapper = ctx and ctx.wrapper
    if W and W.AttachPinnedPreview
        and (not record or record.pageKey ~= pageKey or record.pageWrapper ~= wrapper)
    then
        W.AttachPinnedPreview(P.sec, box, {
            stateKey = "unitFramePreview",
            title = box.title,
            hint = box.hint,
            pageKey = pageKey,
            wrapper = wrapper,
        })
        Preview.RegisterControls(box, ctx)
    end
    -- The preview is shared across cached unit pages. Reassert the current
    -- page's gate whenever ownership is rebound so no state from the
    -- previous page can survive a close/reopen transition.
    ApplyUnitFrameEnabledGate(ctx, P.unit)
end
function Preview.RefreshBox(target, reason)
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
    Core.RequestRefresh = Core.RequestRefresh or MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE)
    Core.RequestRefresh(reason)
end
function Preview.EnsureExpander(P)
    local box, expander, ctx = P.box, P.expander, P.ctx
    if not (box and W.AttachFixedPreviewExpander) then return nil end
    if expander and expander.box == box and not expander.disposed then
        box._msuf2CompactExpandButton = expander.button
        box._msuf2FixedPreviewExpanderRecord = expander
        return expander
    end
    expander = W.AttachFixedPreviewExpander(P.sec, P.header, box, {
        pageKey = ctx and ctx.key,
        wrapper = ctx and ctx.wrapper,
        compactHeight = UNIT_PREVIEW_BOX_HEIGHT,
        compactTop = UNIT_PREVIEW_TOP_OFFSET,
        expandedHeight = UNIT_PREVIEW_EXPANDED_HEIGHT,
        refreshPreview = function(target, reason)
            Preview.RefreshBox(target, reason or "MSUF2_UNIT_PREVIEW_SIZE")
        end,
        onStateChanged = function()
            if P.box.ReleasePreviewInteraction then P.box:ReleasePreviewInteraction() end
        end,
    })
    P.expander = expander
    if expander and expander.button and not expander.button._msuf2UnitExpandRegistered then
        expander.button._msuf2UnitExpandRegistered = true
        RegisterControl(expander.button, ctx, "preview.height.toggle", "Expand Preview", "button", "ephemeral")
    end
    Preview.SetOwner(P)
    return expander
end
function Preview.LayoutToolbar(P)
    local header, expander = P.header, P.expander
    local layersBtn = P.box and P.box._msuf2LayersButton
    if not (layersBtn and header) then return end
    layersBtn:SetParent(header)
    layersBtn:ClearAllPoints()
    local expandBtn = expander and expander.button
    if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
    else layersBtn:SetPoint("RIGHT", header, "RIGHT", -12, 0) end
    if layersBtn.SetFrameLevel and header.GetFrameLevel then
        layersBtn:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
    end
end
function Preview.ApplyPresentation(P)
    Preview.EnsureExpander(P)
    local box, expander, sec = P.box, P.expander, P.sec
    if expander and expander.expanded then
        expander:Relayout("MSUF2_UNIT_EXPANDED_PRESENTATION")
        return
    end
    if box and box._msuf2PinnedFloating ~= true then
        box._msuf2PreferredRestoreHeight = UNIT_PREVIEW_BOX_HEIGHT
        box._msuf2PreferredRestoreYOffset = UNIT_PREVIEW_TOP_OFFSET
        box._msuf2CompactHeader = P.header
        box._msuf2CompactExpandButton = expander and expander.button or nil
        local previousH = (box.GetHeight and box:GetHeight()) or 0
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, UNIT_PREVIEW_TOP_OFFSET)
        box:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, UNIT_PREVIEW_TOP_OFFSET)
        if box.ApplyCompactPreviewPresentation then
            box:ApplyCompactPreviewPresentation(true)
        end
        if box.SetHeight then box:SetHeight(UNIT_PREVIEW_BOX_HEIGHT) end
        Preview.LayoutToolbar(P)
        if math.abs(previousH - UNIT_PREVIEW_BOX_HEIGHT) > 0.5 and box.RequestRefresh then
            box:RequestRefresh("MSUF2_UNIT_PREVIEW_HEIGHT")
        end
    end
end
-- The unit page's own host panel for the shared preview box.
function Preview.PreparePanel(P)
    local panel, sec, unit = P.panel, P.sec, P.unit
    if not panel then
        panel = PixelLayoutRegion(CreateFrame("Frame", nil, sec))
    elseif panel.SetParent then
        panel:SetParent(sec)
    end
    P.panel = panel
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
    return panel
end
-- Returns the preview box owned by this page, creating or adopting the shared one on first use.
function Preview.Ensure(P)
    local ctx, sec = P.ctx, P.sec
    local box = P.box
    if box and box.GetParent and box:GetParent() == sec then
        if not P.hostShown() then return nil end
        Preview.SetOwner(P)
        Preview.EnsureAttachment(P)
        Preview.EnsureExpander(P)
        local expander = P.expander
        if expander and expander.expanded then
            if box.Show then box:Show() end
            expander:Relayout("MSUF2_UNIT_EXPAND_OWNERSHIP")
        elseif box.Show then
            box:Show()
        end
        return box
    end
    if not P.hostShown() then return nil end
    local panel = Preview.PreparePanel(P)
    P.box = UP._sharedUnitPreviewBox
    box = P.box
    if box and box.Hide then box:Hide() end
    if not box then
        box = P.createPreview(sec, panel, ctx.width - 28, UNIT_PREVIEW_BOX_HEIGHT)
        P.box = box
        if not box then return nil end
        UP._sharedUnitPreviewBox = box
    else
        box:SetParent(sec)
        box:ClearAllPoints()
        box:SetSize(ctx.width - 28, UNIT_PREVIEW_BOX_HEIGHT)
        box._msufPanel = panel
        Preview.RegisterControls(box, ctx)
    end
    box._msufPanel = panel
    Preview.SetOwner(P)
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
            local hostShown = P.box._msuf2UnitPageHostShown
            if type(hostShown) == "function" and not hostShown() then return end
            local preview = MSUF.UFPreview
            if type(preview) == "table" and type(preview.RequestRefreshForBox) == "function" then
                preview.RequestRefreshForBox(P.box, "MSUF2_UNIT_PAGE_SHOW")
            else
                Core.RequestRefresh = Core.RequestRefresh or MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE)
                Core.RequestRefresh("MSUF2_UNIT_PAGE_SHOW")
            end
        end)
    end
    Preview.EnsureAttachment(P)
    Preview.EnsureExpander(P)
    Preview.ApplyPresentation(P)
    return box
end
-- Installs the page-bound entry points as closures over P, so each outside call (the host
-- test, a refresh, Aura Style) stays one call, as the per-build locals they replace were.
function Preview.Bind(P)
    local ctx, sec = P.ctx, P.sec
    P.hostShown = function()
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if sec and sec.IsShown and not sec:IsShown() then return false end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return false end
        return true
    end
    P.refreshThis = function(reason)
        local currentBox = Preview.Ensure(P)
        if not currentBox then return end
        P.panel._msufLastApplyKey = P.unit
        Preview.RefreshBox(currentBox, reason or (P.expander and P.expander.expanded
            and "MSUF2_UNIT_PAGE_EXPANDED" or "MSUF2_UNIT_PAGE_COMPACT"))
    end
    P.refreshState = function()
        if not P.hostShown() then
            P.serial = P.serial + 1
            P.queued = nil
            return
        end
        if not P.box and not P.queued then
            P.queued = true
            P.serial = P.serial + 1
            local serial = P.serial
            C_Timer.After(0, function()
                if serial ~= P.serial then return end
                P.queued = nil
                if P.hostShown() then P.refreshThis("MSUF2_UNIT_PAGE_INITIAL") end
            end)
            return
        end
        P.refreshThis("MSUF2_UNIT_PAGE")
    end
end
local function BuildPreview(ctx, builder, unit)
    local previewHeaderTitle = M.Tr("Preview - ") .. UnitTopLabel(unit)
    local sec, previewHeader, fixedRecord = W.FixedPreviewSection(ctx, builder, {
        title = previewHeaderTitle,
        height = UNIT_PREVIEW_SECTION_HEIGHT,
        gap = 8,
    })
    if not UnitSectionShared.DeclarePreview(sec, ctx.key, unit, previewHeaderTitle) then return end
    local createPreview = MSUF.MSUF_Menu2_CreateUnitPreviewBox or MSUF.Require("MSUF_Menu2_CreateUnitPreviewBox", FILE)
    local P = { ctx = ctx, sec = sec, unit = unit, header = previewHeader, createPreview = createPreview, serial = 0 }
    Preview.Bind(P)
    -- Aura Style owns this exact embedded preview box. Publishing the scoped
    -- refresher avoids repainting Preview.active, which may belong to another
    -- cached, pinned, or reparented unit page.
    ctx._msuf2RefreshUnitPreview = P.refreshThis
    if sec.HookScript then
        sec:HookScript("OnShow", P.refreshState)
        sec:HookScript("OnHide", function()
            P.serial = P.serial + 1
            P.queued = nil
        end)
    end
    M.TrackRefresh(ctx, P.refreshState)
    if fixedRecord then fixedRecord.onActivate = P.refreshState end
end
local function SectionNumber(value, fallback)
    return tostring(math.floor((tonumber(value) or fallback or 0) + 0.5))
end
local function AttachUnitSectionUX(ctx, unit)
    local fields = UP.SectionFields or {}
    local sections = {
        -- frameBarShape has no Basics control any more, but the rounded surface still
        -- honours a stored ROUNDED/SQUARE; Reset section is the way to clear it.
        frame_basics = { fields = "smoothFill chunkedFill reverseFillBars verticalFillBars healthColorMode frameBarShape", summary = function(c)
            return SectionNumber(c.width, 220) .. " x " .. SectionNumber(c.height, 40) .. " px"
        end },
        portrait = { fields = fields.portrait, copy = "portrait" },
        power_bar = { fields = fields.power_bar, copy = "power" },
        text = { fields = fields.text, copy = "text" },
        auras = { summary = function()
            local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
            if not (model and model.ReadNumber) then return "" end
            return M.Tr("Buffs") .. " " .. SectionNumber(model.ReadNumber(unit, "maxBuffs", 8, 0, 80))
                .. " / " .. M.Tr("Debuffs") .. " " .. SectionNumber(model.ReadNumber(unit, "maxDebuffs", 12, 0, 80))
        end },
        castbar = { copy = "castbar", canCopy = function(a, b) return UP.CASTBAR_FIELDS[a] and UP.CASTBAR_FIELDS[b] end },
        unit_dispel_overlay = { prefixes = "unitDispelOverlay" },
        unit_dispel_symbol = { prefixes = "unitDispelSymbol" },
        -- Arena only (Pages/MSUF_Menu2_UnitArenaTrinket.lua): reset, no copy target.
        pvp_trinket = { fields = UP.ARENA_TRINKET_FIELDS, noCopy = true },
        transparency = { fields = fields.transparency, copy = "transparency", summary = function(c) return SectionNumber((c.hpBarAlpha
            or 1) * 100) .. "%" end },
        load_conditions = { fields = fields.load_conditions, copy = "load", summary = function(c)
            local count = 0
            for key, value in pairs(c) do if key:find("loadCond", 1, true) == 1 and key ~= "loadCondActive" and value == true then count = count + 1 end end
            return count > 0 and M.Format("%d active conditions", count) or ""
        end },
        texture_layer = { fields = fields.texture_layer, copy = "texlayer", summary = function(c)
            local n = (c.texLayerEnabled and 1 or 0) + (c.texLayer2Enabled and 1 or 0) + (c.texLayer3Enabled and 1 or 0)
            return n > 0 and M.Format("%d / 3 textures enabled", n) or ""
        end },
        anchoring = { fields = "point relativePoint offsetX offsetY anchorFrameName anchorToUnitframe", noCopy = true },
    }
    -- The same frames as the unit tabs, so a client never offers a frame it cannot show.
    local targets = {}
    for _, key in ipairs(UNIT_TAB_ORDER) do
        if UNIT_PAGE_FOR_UNIT[key] and (not M.SupportsFrameScope or M.SupportsFrameScope(key)) then
            targets[#targets + 1] = { value = key, text = UnitTopLabelKey(key) }
        end
    end
    UnitSectionShared.AttachSectionUX(ctx, {
        sections = sections, targets = targets, scope = function() return unit end, conf = GetConf, label = UnitTopLabel,
        targetOff = function(key) return not UnitFrameEnabled(key) end,
        defaults = function(scope)
            local defaults = UnitSectionShared.FactoryProfile()
            -- Optional units can be absent from the factory snapshot. Clearing
            -- their overrides restores the same inherited defaults as page reset.
            return type(defaults) == "table" and (defaults[scope] or {}) or nil
        end,
        copy = function(source, target, category) return CopyUnitSettings(source, target, { [category] = true }) end,
        apply = function(scope, id)
            if id == "load_conditions" then UpdateLoadActive(scope) end
            M.RequestUnitDomains(scope, "MSUF2_SECTION_RESET", { preview = true, text = true, fonts = true, power = true, alpha = true })
            -- The frame bar shape decides whether the rounded runtime runs at all.
            if id == "frame_basics" then Core.ApplyRounded() end
        end,
    })
end
-- Copy To: the status line after a copy, the shared target and the popup that runs it.
local UnitCopy = {
    failures = {
        no_categories = "No copy categories selected.",
        unsupported_aura_scope = "Aura settings are only available for Player, Target, Focus, Boss, and Arena Frames.",
        aura_copy_unavailable = "Aura settings are only available for Player, Target, Focus, Boss, and Arena Frames.",
        unsupported_castbar_scope = "Castbar settings are only available for Player, Target, Focus, Boss, and Arena Frames.",
    },
}
function UnitCopy.NormalizeDest(src)
    local dest = M.unitCopyTarget or (DefaultCopyTarget and DefaultCopyTarget(src)) or "target"
    if dest == src then dest = (DefaultCopyTarget and DefaultCopyTarget(src)) or "target" end
    M.unitCopyTarget = dest
    return dest
end
function UnitCopy.DefaultScopes()
    if type(NewCopyScopeDefaults) == "function" then return NewCopyScopeDefaults() end
    local t = {}
    for i = 1, #UF_COPY_CATEGORIES do
        local cat = UF_COPY_CATEGORIES[i]
        t[cat.key] = cat.default ~= false
    end
    return t
end
-- Status line after a copy: success names the target and any skipped categories, failure says why.
function UnitCopy.Feedback(popup, destinationLabel, applied, result)
    result = type(result) == "table" and result or {}
    if applied == true then
        local message = M.Format("Copied to %s", destinationLabel)
        if result.auraSkipped == true then
            message = message .. " " .. M.Tr("Aura settings were skipped for unsupported UnitFrames.")
        end
        if result.castbarSkipped == true then
            message = message .. " " .. M.Tr("Castbar settings were skipped for UnitFrames without Castbars.")
        end
        local skipped = result.auraSkipped == true or result.castbarSkipped == true
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback(message, skipped and "warning" or "ok", 1.8, true)
        end
        popup:Hide()
        return
    end
    if M.ShowStatusFeedback then M.ShowStatusFeedback(UnitCopy.failures[result.reason] or "Nothing was copied.", "warning", 2.0) end
end
function UnitCopy.Run(unit, popup, copyScopes)
    -- Copy popup buttons deliberately bypass the generic combat-click
    -- proxy so this action owns the failure path instead of becoming a
    -- silent no-op before CopyUnitSettings is reached.
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    local dest = UnitCopy.NormalizeDest(unit)
    local destinationLabel = dest == "all" and M.Tr("All") or UnitTopLabel(dest)
    local function RunCopy(allConfirmed)
        return CopyUnitSettings(unit, dest, copyScopes, function(applied, result)
            UnitCopy.Feedback(popup, destinationLabel, applied, result)
        end, allConfirmed == true)
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
end
function UnitCopy.MakePopup(ctx, copy, unit)
    M.unitCopyScopes = (type(M.unitCopyScopes) == "table") and M.unitCopyScopes or UnitCopy.DefaultScopes()
    local copyScopes = M.unitCopyScopes
    return UnitSectionShared.MakeScopeCopyPopup and UnitSectionShared.MakeScopeCopyPopup(copy, {
        controlDomain = "unit",
        controlPageKey = ctx and ctx.key,
        controlPath = "copy",
        declareControl = function(widget) Schema.Owned(widget, unit, "copy") end,
        width = 420,
        height = 304,
        categories = UF_COPY_CATEGORIES,
        scopes = copyScopes,
        targets = UF_COPY_TARGET_ORDER,
        targetWidths = UF_COPY_TARGET_WIDTHS,
        sourceKey = function() return unit end,
        sourceLabel = UnitTopLabel,
        targetLabelText = function(key) return UF_COPY_TARGET_SHORT_LABELS[key] or UnitTopLabelKey(key) end,
        selectedTarget = function() return UnitCopy.NormalizeDest(unit) end,
        isTargetVisible = function(key, source) return key ~= source end,
        onTargetClick = function(key) M.unitCopyTarget = key end,
        runLabel = "Copy Selected",
        runWidth = 128,
        onPopupCreated = function(popup)
            popup._msuf2GuidedNoScroll = true
            if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, popup, "Copy Player settings", "unit_copy_popup") end
            -- The one-row target strip keeps ToT/FT/PT compact; hover names the frame in full.
            for _, key in ipairs({ "targettarget", "focustarget", "pettarget" }) do
                local chip = popup._targetBtns and popup._targetBtns[key]
                if chip and M.AddTooltip then M.AddTooltip(chip, UnitTopLabelKey(key), nil, { hook = true }) end
            end
        end,
        onRun = function(_, popup) return UnitCopy.Run(unit, popup, copyScopes) end,
    })
end
local function BuildTopActions(ctx, builder, unit, label)
    local pageW = tonumber(builder.width) or 720
    local scopeValues = {}
    for i = 1, #UNIT_TAB_ORDER do
        local tabUnit = UNIT_TAB_ORDER[i]
        if UNIT_PAGE_FOR_UNIT[tabUnit] and (not M.SupportsFrameScope or M.SupportsFrameScope(tabUnit)) then
            scopeValues[#scopeValues + 1] = {
                value = tabUnit,
                text = UnitTopTabKey(tabUnit, false),
                width = UnitTopTabWidth(tabUnit, false),
            }
        end
    end
    local scopeOpts = {
        values = scopeValues,
        width = pageW,
        maxRight = pageW - 112,
        label = "",
        labelWidth = 0,
        startX = 16,
        getValue = function() return unit end,
        setValue = function(tabUnit)
            local pageKey = UNIT_PAGE_FOR_UNIT[tabUnit]
            if pageKey and pageKey ~= ctx.key then M.SelectPage(pageKey) end
        end,
    }
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, scopeOpts)
    local scopeH = math.max(54, math.abs((scopeMetrics and scopeMetrics.bottomY) or -40) + 14)
    local sectionH = scopeH
    local sec = T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(sec, "status")
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(pageW, sectionH)
    sec._msuf2Width = pageW
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, sec, "Player frame and Copy To", "unit_scope") end
    builder.y = builder.y - sectionH - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end
    local rowY = -15
    if W.ScopeOverrideBar then Schema.Build(ctx, sec, {
        { "scopebar", "unit_page", nil, { scopeOpts }, scope = unit, domain = "navigation",
            beforeBind = function(widget)
                RegisterControl(widget, ctx, "navigation.unit_page.selector", "Editing", "segment", "ephemeral")
            end },
    }) end
    local copy = Schema.Build(ctx, sec, {
        { "roleButton", "copy", nil, { "Copy To", "success", 82, 24 } },
    }).copy
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, rowY)
    -- Opening the selector is safe in combat. The actual copy remains guarded
    -- in UnitCopy.Run, where a blocked click can produce visible feedback.
    copy._msuf2AllowCombatClick = true
    copy._msuf2SkipHistoryCheckpoint = true
    local copyPopup = UnitCopy.MakePopup(ctx, copy, unit)
    -- Opening the popup changes nothing, but search should still find where copying lives.
    RegisterControl(copy, ctx, "copy.open", "Copy To", "button", "ephemeral", { searchIndexed = true })
    copy:SetScript("OnClick", function(self)
        if copyPopup then copyPopup.Show(self) end
    end)
    Schema.Owned(copy, unit, "copy")
    if type(M.RegisterGuidedCopyPopup) == "function" then
        M.RegisterGuidedCopyPopup("unit", ctx.key, M.CreateGuidedCopyOpener(copyPopup, copy))
    end
    sec:SetScript("OnHide", function()
        if copyPopup then copyPopup.Hide() end
    end)
    UnitSectionShared.AttachStickyHeader(ctx, builder, sec)
end
local function PrepareBasicsSwitch(ctx, sec, unit)
    Schema.Section(sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local enable = Schema.Build(ctx, sec, {
        { "sectionSwitch", "enabled", true, { "Enable", "Enable" },
            beforeBind = function(widget)
                widget._msuf2UnitFrameGateAlwaysEnabled = true
            end,
            get = function() return ReadBool(unit, "enabled", true) end,
            write = { call = SetBool, args = { "MSUF2_FRAME_ENABLED", { preview = true } }, after = function() M.Refresh(ctx) end },
                --[[schema setter: UnitSections.1]]
            meta = SettingMeta(ctx, "basics.enabled", unit, "enabled"), scope = unit,
        }
    }, ROW_OPTIONS).enabled
    enable:SetChecked(ReadBool(unit, "enabled", true))
    return enable
end
local function AttachBasicsHeaderStatus(sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end
    local function Refresh()
        local enabled = ReadBool(unit, "enabled", true)
            and (unit ~= "focustarget" or ReadBool("focus", "enabled", true))
        local color = enabled and EnabledHeaderColor() or WARNING_HEADER_BG
        W.SetCollapsibleHeaderBaseTone(entry, color, color[4])
        T.SetTranslatedText(entry.label, M.Tr("Basics") .. (enabled and "" or (" - " .. M.Tr("Frame disabled"))))
    end
    Refresh()
    return Refresh
end
local function BuildBasicsColorRows(ctx, sec, unit, colW, gap, x1, x2, x3, labelW)
    local colorW = math.min(270, math.max(220, colW * 2))
    -- Fill Direction shares the Health Color Scheme row so the section stays within its
    -- declared height instead of overlapping the next accordion header. Snap to
    -- the column grid when there is room, otherwise sit just right of the
    -- width-capped Health Color Scheme dropdown; clamp the width so it never
    -- runs into the third column (Pet keeps its class-color toggle there).
    local fillDirW = colorW
    local fillDirX = math.max(x2, x1 + fillDirW + gap)
    local fillDirFit = (x3 - gap) - fillDirX
    if fillDirFit > 0 and fillDirW > fillDirFit then fillDirW = fillDirFit end
    local rows = {
        { "dropdown", "healthColorMode", HEALTH_COLOR_GLOBAL, { "Health Color Scheme", HealthColorModeOptions, colorW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, x1, -116, colorW)
            end,
            get = function()
                return NormalizeHealthColorMode(GetConf(unit).healthColorMode) or HEALTH_COLOR_GLOBAL
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                local conf = GetConf(unit)
                conf.healthColorMode = NormalizeHealthColorMode(v)
                M.RequestUnitDomains(unit, "MSUF2_HEALTH_COLOR_MODE", { preview = true, colors = true })
                if M.Refresh then M.Refresh(ctx) end
            end,
            tip = { "Health Color Scheme",
                "Use Global follows the Unitframe Global Coloring mode from Colors. Other choices override only this frame.",
                TIP_OPTS },
            meta = SettingMeta(ctx, "basics.health_color_mode", unit, "healthColorMode"), scope = unit,
        },
        { "dropdown", "verticalFillBars", "lr", { "Fill Direction", FILL_DIRECTION_OPTIONS, fillDirW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, fillDirX, -116, fillDirW)
            end,
            get = function()
                return FillDirectionValue(ReadBool(unit, "reverseFillBars", false), ReadBool(unit, "verticalFillBars", false))
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                local state = FILL_DIRECTION_STATE[v] or FILL_DIRECTION_STATE.lr
                -- Write both booleans, then a single apply/preview (mirrors the
                -- Health Color Scheme setter) so a 4-way change never double-applies.
                local conf = GetConf(unit)
                conf.reverseFillBars = state.reverse
                conf.verticalFillBars = state.vertical
                M.RequestUnitDomains(unit, "MSUF2_FILL_DIRECTION", { preview = true })
                if M.Refresh then M.Refresh(ctx) end
            end,
            tip = { "Fill Direction",
                "Axis and direction the Health and Power bars fill. Vertical options fill bottom-to-top or top-to-bottom; combines with Smooth fill.",
                TIP_OPTS },
            meta = SettingMeta(ctx, "basics.fill_direction", unit, "verticalFillBars"), scope = unit,
        },
    }
    if unit == "pet" then
        rows[#rows + 1] = { "toggle", "petFrameUsePlayerClassColor", false, { "Player Class Color", x3, -116, labelW },
            get = function() return GetGeneral().petFrameUsePlayerClassColor == true end,
            write = { source = GetGeneral, boolean = true, after = function()
                    M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                    if M.Refresh then M.Refresh(ctx) end
                end } --[[schema setter: UnitSections.4]],
            tip = { "Use player's class color for Pet Frame",
                "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", TIP_OPTS },
            meta = SettingMeta(ctx, "basics.use_player_class_color", "general", "petFrameUsePlayerClassColor"), scope = unit,
        }
    end
    local controls = Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    return controls.healthColorMode, controls.verticalFillBars, controls.petFrameUsePlayerClassColor
end
-- The Basics ::: lists the colors the frame's effective Health Color Scheme paints with.
local function AttachBasicsColorReferences(sec, unit)
    if not W.AttachContextColorReferences then return end
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
        refs[#refs + 1] = "health.background.current"
        refs[#refs + 1] = "bar.health_loss"
        return refs
    end, {
        title = M.Format("%s Health Colors", UnitTopLabel(unit)),
        note = "Colors follow this frame's effective Health Color Scheme.",
        historySource = "menu:unit-frame-basics-health-colors",
        maxTargets = 7,
        context = function()
            local context = { unit = unit, healthMode = EffectiveHealthMode() }
            if unit == "pet" and GetGeneral().petFrameUsePlayerClassColor == true and type(UnitClass) == "function" then
                local _, token = UnitClass("player")
                context.classToken = token
            end
            return context
        end,
    })
end
local function BuildBasics(ctx, builder, unit, label)
    -- Default-open so the page greets users with real settings instead of a
    -- stack of closed headers; saved accordion state still wins afterwards.
    -- Leave a full footer gutter below the disabled-frame notice. The next
    -- accordion header is created later and can otherwise cover the notice's
    -- lower edge at some UI scales.
    local sec = Schema.Section(builder:CollapsibleSection("frame_basics", "Basics", 272, true), unit)
    AttachBasicsColorReferences(sec, unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42
    local enable = PrepareBasicsSwitch(ctx, sec, unit)
    -- Fill Direction (axis + in-axis direction) is a 4-way dropdown placed on
    -- its own row below Health Color Scheme; Smooth takes the freed x2 slot.
    local basics = Schema.Build(ctx, sec, {
        { "toggle", "smoothFill", false, { "Smooth fill", x1, row1, labelW },
            get = function() return ReadBool(unit, "smoothFill", false) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
                UnitSectionShared.SetFillMode(ctx, unit, "health", "smoothFill", "chunkedFill", v, "MSUF2_SMOOTH_FILL",
                    "Smooth health fill", { preview = true })
            end,
            meta = SettingMeta(ctx, "basics.smooth_fill", unit, "smoothFill"), scope = unit,
        },
        { "toggle", "chunkedFill", false, { "Chunked health loss", x2, row1, labelW },
            get = function() return ReadBool(unit, "chunkedFill", false) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
                UnitSectionShared.SetFillMode(ctx, unit, "health", "chunkedFill", "smoothFill", v, "MSUF2_CHUNKED_FILL",
                    "Chunked health loss", { preview = true })
            end,
            meta = SettingMeta(ctx, "basics.chunked_fill", unit, "chunkedFill"), scope = unit,
        },
        { "switch", "useBlizzardFrame", false, { "Force Blizzard frame on", x1, -76, math.max(196, colW + 24) },
            beforeBind = function(widget)
                widget._msuf2UnitFrameGateAlwaysEnabled = true
            end,
            get = function() return ReadBool(unit, "useBlizzardFrame", false) end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                if unit == "pettarget" or ReadBool(unit, "useBlizzardFrame", false) == (v == true) then return end
                SetBool(unit, "useBlizzardFrame", v, "MSUF2_BLIZZARD_FRAME_OWNERSHIP", { preview = false })
                local reloadLabel = M.Format("%s Blizzard frame ownership", label or UnitTopLabel(unit))
                Core.ShowReloadPopup(reloadLabel)
            end,
            meta = SettingMeta(ctx, "basics.force_blizzard_frame", unit, "useBlizzardFrame"), scope = unit,
        }
    }, ROW_OPTIONS)
    local smooth, chunked, blizzard = basics.smoothFill, basics.chunkedFill, basics.useBlizzardFrame
    local blizzardHint = "Independent from MSUF Enable; /reload required."
    if unit == "pettarget" then
        blizzardHint = "Blizzard has no native Pet Target frame."
    elseif unit == "targettarget" then
        blizzardHint = "Also keeps Blizzard Target visible; /reload required."
    elseif unit == "focustarget" then
        blizzardHint = "Also keeps Blizzard Focus visible; /reload required."
    end
    Schema.Build(ctx, sec, { { "text", "unit.note.1", nil, { blizzardHint, x2, -80, math.max(190, sectionW - x2 - 14), T.colors.muted } } })
    if M.AddTooltip then
        local tooltip = M.Format("Keeps Blizzard's native frame active independently of the MSUF frame. Leave MSUF Enable on to show both, or turn " ..
            "MSUF Enable off to use only Blizzard. A UI reload is required.")
        if unit == "targettarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Target of Target is a child of Blizzard Target, so both native frames must remain active.")
        elseif unit == "focustarget" then
            tooltip = tooltip .. " " .. M.Format("Blizzard Focus Target is a child of Blizzard Focus, so both native frames must remain active.")
        end
        if unit == "pettarget" then tooltip = M.Format("Blizzard has no native Pet Target frame.") end
        M.AddTooltip(blizzard, "Force Blizzard frame on", tooltip, TIP_OPTS)
    end
    local colorMode, fillDir, petPlayerClassColor = BuildBasicsColorRows(ctx, sec, unit, colW, gap, x1, x2, x3, labelW)
    if W.AttachUnitEditFocus then
        for _, control in ipairs({ enable, smooth, chunked, blizzard, colorMode, fillDir, petPlayerClassColor }) do
            W.AttachUnitEditFocus(control, unit, "frame")
        end
    end
    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local RefreshBasicsState = AttachBasicsHeaderStatus(sec, unit)
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end
    local unitLabel = label or UnitTopLabel(unit)
    local notice, _, enableNow = UnitSectionShared.CreateSectionNotice(sec, -180, "Enable", 92)
    local enableShortcutMeta
    if unit ~= "focustarget" then
        enableShortcutMeta = {
            settingKey = unit .. ".enabled",
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return ReadBool(unit, "enabled", true) end,
                customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
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
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then
            SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true })
        end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        M.RequestOrRefresh(ctx, "frame-basics-enable-now")
    end)
    Schema.Owned(enableNow, unit, "unit")
    notice:Hide()
    local basicsDependentControls = { smooth, chunked, colorMode, fillDir }
    if W.SetControlsDisabledReason then
        W.SetControlsDisabledReason(basicsDependentControls, function() return UP.FrameDisabledReason(unit) end)
    end
    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        SetControlEnabled(enable, true)
        SetControlEnabled(blizzard, unit ~= "pettarget")
        SetControlsEnabled(basicsDependentControls, ownOn)
        if parentOff then
            notice:SetMessage(M.Tr("Focus Target follows the Focus frame. Enable Focus to show it."), "warning")
            if enableNow.SetText then enableNow:SetText("Enable Focus") end
        else
            notice:SetMessage(M.Format("%s frame is disabled and will not appear.", unitLabel), "warning")
            if enableNow.SetText then enableNow:SetText("Enable") end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
    end
    M.TrackRefresh(ctx, RefreshBasicsEnabled)
end
-- Anchor section sources and rules, per unit rather than per build.
local UnitAnchor = {
    choices = VT("GLOBAL", "Global anchor", "EssentialCooldownViewer", "Essential cooldown viewer",
        "UtilityCooldownViewer", "Utility cooldown viewer", "BuffIconCooldownViewer", "Tracked buffs viewer",
        "player", "Player frame", "target", "Target frame", "targettarget", "Target of Target frame",
        "focustarget", "Focus Target frame", "focus", "Focus frame", "pet", "Pet frame"),
    points = VT("TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", "LEFT", "LEFT", "CENTER", "CENTER",
        "RIGHT", "RIGHT", "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT"),
    standard = M.KeySetFromWords("GLOBAL global FREE EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer player target targettarget " ..
        "focustarget focus pet"),
    listed = M.KeySetFromWords "player target targettarget focustarget focus pet EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer",
}
function UnitAnchor.CustomName(conf)
    local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
    if custom ~= "" then return custom end
    local raw = conf.anchorToUnitframe
    if type(raw) == "string" and raw ~= "" and UnitAnchor.standard[raw] ~= true then return raw end
    return ""
end
-- The closures below are built once per section for its unit, so every dropdown read and
-- every refresh is a single call, as the per-build locals they replace were.
function UnitAnchor.ValuesFor(unit)
    return function()
        local values = {}
        local conf = GetConf(unit)
        local custom = UnitAnchor.CustomName(conf)
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = M.Format("Custom: %s", text) }
        end
        local available = M.AnchorTargetValues(UnitAnchor.choices, conf.anchorToUnitframe, unit)
        for i = 1, #available do
            local item = available[i]
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
end
function UnitAnchor.ValueFor(unit)
    return function()
        local conf = GetConf(unit)
        if UnitAnchor.CustomName(conf) ~= "" then return "__CUSTOM" end
        local v = conf.anchorToUnitframe
        if UnitAnchor.listed[v] then return v end
        return "GLOBAL"
    end
end
function UnitAnchor.PointValueFor(unit)
    return function()
        local point = GetConf(unit).point or "CENTER"
        local points = UnitAnchor.points
        for i = 1, #points do
            if points[i].value == point then return point end
        end
        return "CENTER"
    end
end
function UnitAnchor.Apply(unit)
    M.RequestUnitDomains(unit, "MSUF2_ANCHORING", { preview = true })
end
function UnitAnchor.SetCustom(unit, value)
    value = value or ""
    local conf = GetConf(unit)
    conf.anchorFrameName = (value ~= "") and value or nil
    if value ~= "" or UnitAnchor.CustomName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
    UnitAnchor.Apply(unit)
end
-- parts: the cooldown switch, its notice, the custom editor, the two dropdowns and their value readers.
function UnitAnchor.RefreshFor(sec, parts)
    local cooldownAnchor, automaticNotice = parts.cooldown, parts.notice
    return function()
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        local cooldownAnchorLabel = automaticProviderLabel and (automaticProviderLabel .. " Anchor") or M.Tr("Follow Blizzard's Essential Cooldowns")
        if cooldownAnchor._msuf2Label and cooldownAnchor._msuf2Label.SetText then
            cooldownAnchor._msuf2Label:SetText(cooldownAnchorLabel)
        end
        parts.custom.Refresh()
        if parts.anchorTo.SetValue then parts.anchorTo:SetValue(parts.value()) end
        if parts.anchorPoint.SetValue then parts.anchorPoint:SetValue(parts.pointValue()) end
        if not CooldownAnchorSupported() then
            -- The stored preference is kept so the profile stays portable, but
            -- there is nothing to anchor to here: hide the switch instead of
            -- offering a control that cannot take effect.
            W.SetControlShown(cooldownAnchor, false)
            automaticNotice:SetMessage(M.Tr("This client has no Cooldown Manager. Unit Frames use their own anchor."), "info")
            automaticNotice:Show()
            SetSectionHeaderStatus(sec, nil)
            return
        end
        W.SetControlShown(cooldownAnchor, true)
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
end
local function BuildLayout(ctx, builder, unit)
    local sec = Schema.Section(builder:CollapsibleSection("anchoring", "Anchor", UNIT_ANCHOR_SECTION_HEIGHT, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, sectionW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
    local AnchorValue, AnchorPointValue = UnitAnchor.ValueFor(unit), UnitAnchor.PointValueFor(unit)
    local anchorRows = Schema.Build(ctx, sec, {
        { "dropdown", "anchorToUnitframe", "GLOBAL", { "Anchor To", UnitAnchor.ValuesFor(unit), anchorControlW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, anchorLeftX, -38, anchorControlW)
                W.AttachUnitEditFocus(widget, unit, "anchoring")
            end,
            get = AnchorValue,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                if v == "__CUSTOM" then return end
                local conf = GetConf(unit)
                conf.anchorToUnitframe = v or "GLOBAL"
                conf.anchorFrameName = nil
                UnitAnchor.Apply(unit)
            end,
            -- Changing the anchor target also clears any custom anchor frame name (same unit root).
            meta = SettingMeta(ctx, "anchoring.anchor_to", unit, "anchorToUnitframe"), scope = unit,
        },
        { "dropdown", "point", "CENTER", { "Anchor Point", UnitAnchor.points, anchorControlW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, anchorRightX, -38, anchorControlW)
                W.AttachUnitEditFocus(widget, unit, "anchoring")
            end,
            get = AnchorPointValue,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                local conf = GetConf(unit)
                v = v or "CENTER"
                conf.point = v
                conf.relativePoint = v
                UnitAnchor.Apply(unit)
            end,
            -- The anchor point writes point and relativePoint together (same unit root).
            meta = SettingMeta(ctx, "anchoring.anchor_point", unit, "point"), scope = unit,
        },
    }, ROW_OPTIONS)
    local customAnchor = UnitSectionShared.CustomAnchorEditor(ctx, sec, {
        x = anchorLeftX,
        y = -112,
        width = customAnchorW,
        getValue = function() return UnitAnchor.CustomName(GetConf(unit)) end,
        setValue = function(value) UnitAnchor.SetCustom(unit, value) end,
        isCandidateAllowed = function(frame)
            local factory = MSUF.UF and MSUF.UF.Factory
            return not factory or type(factory.IsAnchorCandidateAllowed) ~= "function"
                or factory.IsAnchorCandidateAllowed(frame, unit)
        end,
        clearValue = function()
            UnitAnchor.SetCustom(unit, "")
        end,
        commitTitle = "Set Unit Anchor",
        commitKey = function() return "unit:anchorCustom:" .. tostring(unit) end,
        pickTitle = "Pick custom anchor",
        pickKey = function() return "unit:anchorPick:" .. tostring(unit) end,
        attachFocus = function(widget) W.AttachUnitEditFocus(widget, unit, "anchoring") end,
        controlDomain = "unit",
        controlPageKey = ctx and ctx.key,
        controlPath = "anchoring.custom",
        valueSettingKey = unit .. ".anchorFrameName",
    })
    customAnchor.clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        if UnitAnchor.CustomName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        customAnchor.box:SetText("")
        UnitAnchor.Apply(unit)
    end)
    RegisterControl(customAnchor.clear, ctx, "anchoring.custom.clear", "Clear", "button", "action", {
        actionKey = "clear_unit_custom_anchor", actionFixedArgs = { unit = unit },
    })
    RegisterControl(customAnchor.pick, ctx, "anchoring.custom.pick", "Pick", "button", "action", {
        actionKey = "start_unit_custom_anchor_picker", actionFixedArgs = { unit = unit },
    })
    local cooldownAnchor = Schema.Build(ctx, sec, {
        { "switch", "anchorToCooldown", false, { "Follow Blizzard's Essential Cooldowns", anchorLeftX, -184, anchorInnerW },
            get = CooldownAnchorEnabled,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(enabled)
                Core.SetCooldownEnabled(enabled, true)
                M.RequestOrRefresh(ctx, "unit-anchoring-cooldown-manager")
            end,
            meta = SettingMeta(ctx, "anchoring.cooldown_manager", "general", "anchorToCooldown"), scope = unit,
        }
    }, ROW_OPTIONS).anchorToCooldown
    local parts = { cooldown = cooldownAnchor, notice = UnitSectionShared.CreateSectionNotice(sec, -238), custom = customAnchor,
        anchorTo = anchorRows.anchorToUnitframe, anchorPoint = anchorRows.point, value = AnchorValue, pointValue = AnchorPointValue }
    M.TrackCollapsibleRefresh(ctx, sec, UnitAnchor.RefreshFor(sec, parts))
end
local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end
    local sec = Schema.Section(builder:CollapsibleSection("inline_text", "Inline Text", 214, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local rightX = math.max(260, floor(sectionW * 0.52))
    local rightW = math.min(220, math.max(140, sectionW - rightX - 28))
    local RefreshInlineControlState
    Schema.Build(ctx, sec, {
        { "text", "unit.note.2", nil, {
            "Target of Target inline text is shown on the Target frame name line.", 14, -38, sectionW - 28, T.colors.muted } } })
    sec._msuf2CursorY = -72
    local inlineApplyFlags = { text = true, preview = true }
    local function ApplyToTInline(reason, forceToT, skipRefresh)
        RequestUnitRuntimeApply("target", reason, inlineApplyFlags)
        RequestUnitRuntimeApply("targettarget", reason, inlineApplyFlags, forceToT == true)
        if not skipRefresh and RefreshInlineControlState then RefreshInlineControlState() end
    end
    local function ColorMode()
        return ToTInlineColorDropdownValue(GetConf("targettarget"))
    end
    local function SetColorMode(value)
        GetConf("targettarget").totInlineColorMode = NormalizeToTInlineColorMode(value)
        ApplyToTInline("MSUF2_TOT_INLINE_COLOR", true)
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
                getColorMode = ColorMode,
                setColorMode = SetColorMode,
                subtitle = "Font style follows Target Fonts; color mode follows Inline color.",
            },
        })
    end
    local controls = Schema.Build(ctx, sec, {
        { "flowToggle", "showToTInTargetName", false, { "Show Target of Target text inline" },
            get = function() return GetConf("targettarget").showToTInTargetName == true end,
            write = { source = function() return GetConf("targettarget") end, boolean = true,
                after = function() ApplyToTInline("MSUF2_TOT_INLINE") end }, --[[schema setter: UnitSections.12]]
            meta = SettingMeta(ctx, "inline_text.show_target_of_target", "targettarget", "showToTInTargetName"), scope = unit,
        },
        { "dropdown", "totInlineColorMode", TOT_INLINE_COLOR_AUTO, { "Inline color", ToTInlineColorOptions, rightW },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, rightX, -72, rightW)
            end,
            get = ColorMode,
            customSetReason = "Applies the inline-name color mode and refreshes its dependent target text.", set = SetColorMode,
            meta = SettingMeta(ctx, "inline_text.color", "targettarget", "totInlineColorMode"), scope = unit,
        },
        { "dropdown", "totInlineSeparator", "|", { "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170 },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, 14, -124, 170)
            end,
            get = function() return ToTInlineSeparatorDropdownValue(GetConf("targettarget")) end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
                local conf = GetConf("targettarget")
                if v == TOT_INLINE_CUSTOM_SEPARATOR then
                    conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                    conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(conf.totInlineCustomSeparator)
                else
                    conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
                end
                ApplyToTInline("MSUF2_TOT_INLINE_SEPARATOR", true)
            end,
            meta = SettingMeta(ctx, "inline_text.separator", "targettarget", "totInlineSeparator"), scope = unit,
        },
        { "textinput", "totInlineCustomSeparator", "", { "Custom separator", rightW },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, rightX, -124, rightW)
                if widget.SetMaxLetters then widget:SetMaxLetters(TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
            end,
            get = function()
                local conf = GetConf("targettarget")
                local token = conf and conf.totInlineSeparator
                if token ~= TOT_INLINE_CUSTOM_SEPARATOR and type(token) == "string" and token ~= ""
                    and not TOT_INLINE_SEPARATOR_VALUES[token] then return CleanToTInlineCustomSeparator(token) end
                return CleanToTInlineCustomSeparator(conf and conf.totInlineCustomSeparator)
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
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
            commitOnBlur = true,
            meta = SettingMeta(ctx, "inline_text.custom_separator", "targettarget", "totInlineCustomSeparator"), scope = unit,
        },
    }, ROW_OPTIONS)
    local color, customSep = controls.totInlineColorMode, controls.totInlineCustomSeparator
    local totInlineBaseControls = { color, controls.totInlineSeparator }
    RefreshInlineControlState = function()
        local conf = GetConf("targettarget")
        local enabled = GetConf("targettarget").showToTInTargetName == true
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
    if type(fn) ~= "function" then return end
    if not UP.BuildSectionLazy then return fn(ctx, builder, unit) end
    return UP.BuildSectionLazy(ctx, builder, unit, { id = "status_icons", title = "Status icons", height = 724, build = fn })
end
local function BuildLoadConditions(ctx, builder, unit)
    local sec = Schema.Section(builder:CollapsibleSection("load_conditions", "Visibility", 210, false), unit)
    local function Row(key, label, x, y, width)
        return { "toggle", key, false, { label, x, y, width },
            meta = SettingMeta(ctx, "load_condition." .. tostring(key), unit, key),
            scope = unit, domain = "loadCondition",
            get = function() return ReadBool(unit, key, false) end,
            write = { source = function() return GetConf(unit) end, boolean = true, after = function()
                    UpdateLoadActive(unit) M.RequestUnitDomains(unit, "MSUF2_LOAD_CONDITION", { preview = true })
                end } --[[schema setter: UnitSections.15]] }
    end
    local rows = {}
    local colW = math.floor(((ctx.width or 720) - 42) / 3)
    for i, condition in ipairs(LOAD_CONDITIONS) do
        rows[#rows + 1] = Row(condition.key, condition.label, 14 + ((i - 1) % 3) * colW,
            -42 - math.floor((i - 1) / 3) * 30, colW - 34)
    end
    local label = "Show only below 100% health"
    local injured = Row("loadCondShowWhenInjured", label, 14, -166, (ctx.width or 720) - 70)
    injured.tip = { label,
        "Show this frame only when its unit is below full health. At full health it is transparent, even in combat or with a target. Replaces the " ..
            "Out of combat, No target, and Out of combat and no target rules; other hide conditions still apply. Edit Mode keeps the frame visible " ..
            "for editing. The transparent frame can still receive mouse clicks.",
        TIP_OPTS }
    rows[#rows + 1] = injured
    Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    M.TrackCollapsibleRefresh(ctx, sec, function() SetSectionHeaderStatus(sec, nil) end)
end
local BOSS_LAYOUT_TILE_VALUES = {
    { value = "VERTICAL_DOWN", text = "Down", tooltip = "Vertical (top -> bottom)", dx = 0, dy = -1, arrow = "v" },
    { value = "VERTICAL_UP", text = "Up", tooltip = "Vertical (bottom -> top)", dx = 0, dy = 1, arrow = "^" },
    { value = "HORIZONTAL_RIGHT", text = "Right", tooltip = "Horizontal (left -> right)", dx = 1, dy = 0, arrow = ">" },
    { value = "HORIZONTAL_LEFT", text = "Left", tooltip = "Horizontal (right -> left)", dx = -1, dy = 0, arrow = "<" },
}
local function BuildBossLayoutTiles(parent, x, y, tileW, tileH, gap, titleText)
    if not parent then return nil end
    tileW, tileH, gap = tileW or 64, tileH or 70, gap or 8
    local control = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -44)
    control:SetSize((tileW * #BOSS_LAYOUT_TILE_VALUES) + (gap * (#BOSS_LAYOUT_TILE_VALUES - 1)), tileH + 20)
    control._msuf2ControlKind = "segment"
    control.values = BOSS_LAYOUT_OPTIONS
    control.buttons = {}

    local title = T.Font(control, "GameFontNormalSmall", titleText or "Boss frame layout", T.colors.accent)
    title:SetPoint("TOPLEFT", control, "TOPLEFT", 0, 0)
    control._msuf2Title = title
    -- The title is the picker's name, on screen and in search.
    control._msuf2SearchText = titleText or "Boss frame layout"

    local SetTileVisual = W.SetTileVisual

    local function DrawMiniBossPreview(btn, info)
        if not (btn and info) then return end
        btn._frames = btn._frames or {}
        local count = 5
        local pad = 6
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local frameGap = 2
        local vertical = info.dy ~= 0
        local reversed = info.dy == 1 or info.dx == -1
        local frameW, frameH
        if vertical then
            frameW = math.max(18, math.floor(innerW * 0.82))
            frameH = math.max(4, math.floor((innerH - ((count - 1) * frameGap)) / count))
        else
            frameW = math.max(6, math.floor((innerW - ((count - 1) * frameGap)) / count))
            frameH = math.max(14, math.floor(innerH * 0.56))
        end
        local totalW = vertical and frameW or ((count * frameW) + ((count - 1) * frameGap))
        local totalH = vertical and ((count * frameH) + ((count - 1) * frameGap)) or frameH
        local originX = pad + math.floor((innerW - totalW) * 0.5 + 0.5)
        local originY = -pad - math.floor((innerH - totalH) * 0.5 + 0.5)
        for i = 1, count do
            local tex = btn._frames[i]
            if not tex then
                tex = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
                btn._frames[i] = tex
            end
            local visualIndex = reversed and (count - i) or (i - 1)
            local px, py = originX, originY
            if vertical then py = originY - (visualIndex * (frameH + frameGap))
            else px = originX + (visualIndex * (frameW + frameGap)) end
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
        W.EnsureTileFirstBadge(btn)
        local firstVisualIndex = reversed and (count - 1) or 0
        btn._firstText:ClearAllPoints()
        btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
            originX + ((vertical and 0 or firstVisualIndex) * (frameW + frameGap)) + (frameW * 0.5),
            originY - ((vertical and firstVisualIndex or 0) * (frameH + frameGap)) - (frameH * 0.5))
        btn._firstText:Show()

        W.PaintTileDirectionArrow(btn, info, labelH)
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
        local btn = UnitSectionShared.TileButton(control, tileW, tileH, (i - 1) * (tileW + gap), -20, info.text or "")
        btn._msuf2Value = info.value
        btn:SetScript("OnEnter", function(self) SetTileVisual(self, control._msuf2Value == info.value, true) end)
        btn:SetScript("OnLeave", function(self) SetTileVisual(self, control._msuf2Value == info.value, false) end)
        M.AddTooltip(btn, function() return M.Format("Boss frame layout: %s", M.Tr(info.tooltip or info.text or "")) end,
            "Click to set how boss frames are arranged.", { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        control.buttons[i] = btn
    end
    control:SetValue("VERTICAL_DOWN")
    return control
end
-- Boss and Arena stack their frames with the same model: a spacing slider and a layout tile picker.
local function BuildStackedLayout(ctx, builder, unit, def)
    local sec = Schema.Section(builder:CollapsibleSection(def.id, def.title, def.height, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    Schema.Build(ctx, sec, {
        { "slider", "spacing", def.spacingDefault, { def.spacingLabel, -400, 0, 1, 300 },
            { leftX, -42, sliderW, "CENTER" },
            meta = SettingMeta(ctx, def.id .. ".spacing", unit, "spacing"),
            scope = unit, unit = unit, domain = "layout", reason = def.spacingReason, roundStep = true },
    }, ROW_OPTIONS)
    local layout = BuildBossLayoutTiles(sec, rightX, -42, 60, 70, 8, def.tilesTitle)
    local meta = SettingMeta(ctx, def.id .. ".mode", unit, "bossLayoutMode")
    Schema.Bind(ctx, layout, {
        id = meta.controlId, kind = "segment", labelKey = layout._msuf2SearchText, meta = meta, scope = unit,
        applyDomain = "layout",
        get = function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, def.legacyInvert and conf.invertBossOrder)
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            if def.legacyInvert then conf.invertBossOrder = nil end
            M.RequestUnitDomains(unit, def.modeReason, { preview = true })
        end,
    })
end
local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    BuildStackedLayout(ctx, builder, unit, { id = "boss_layout", title = "Boss Layout", height = 150,
        spacingLabel = "Boss spacing", spacingDefault = -36, spacingReason = "MSUF2_BOSS_SPACING",
        modeReason = "MSUF2_BOSS_LAYOUT_MODE", legacyInvert = true })
end
local function BuildBossTargetHighlight(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = Schema.Section(builder:CollapsibleSection("boss_target_highlight", "Boss target highlight", 450, false), unit)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(sec, { "highlight.boss_target" }, {
            title = "Boss Target Highlight Color", historySource = "menu:unit-boss-target-highlight-color",
        })
    end
    local function Apply()
        M.RequestUnitDomains("boss", "MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
    end
    local styles = VT("OFF", "Off", "BORDER", "Border", "ARROW", "Arrow", "DOUBLE_ARROW", "Double arrow",
        "TRIPLE_ARROW", "Triple arrow", "DIAMOND", "Diamond", "CROSS", "Cross", "BORDER_ARROW", "Border and arrow")
    local anchors = VT("LEFT", "Left", "RIGHT", "Right", "TOP", "Top", "BOTTOM", "Bottom", "CENTER", "Center",
        "TOPLEFT", "Top left", "TOPRIGHT", "Top right", "BOTTOMLEFT", "Bottom left", "BOTTOMRIGHT", "Bottom right")
    local directions = VT("RIGHT", "Right", "LEFT", "Left", "UP", "Up", "DOWN", "Down")
    local layouts = VT("SINGLE", "Single marker", "BOTH_IN", "Both sides: > frame <", "BOTH_OUT", "Both sides: < frame >")
    local function Row(kind, label, key, default, x, y, arguments)
        local native = { label }
        for _, value in ipairs(arguments) do native[#native + 1] = value end
        native[#native + 1] = 270
        return { kind, key, default, native,
            kind == "slider" and { x, y, 270, "CENTER" } or nil,
            beforeBind = kind == "dropdown" and function(widget) UnitSectionShared.PlaceDropdown(sec, widget, x, y, 270) end or nil,
            meta = SettingMeta(ctx, "boss_target_highlight." .. key, unit, key), scope = unit,
            domain = "bossHighlight", roundStep = kind == "slider",
            get = function() return kind == "slider" and ReadNumber(unit, key, default) or GetConf(unit)[key] or default end,
            write = { source = function() return GetConf(unit) end, after = Apply } --[[schema setter: UnitSections.17]] }
    end
    local rows = {
        Row("dropdown", "Marker anchor", "bossTargetIndicatorAnchor", "LEFT", 350, -42, { anchors }),
        Row("dropdown", "Arrow direction", "bossTargetIndicatorDirection", "RIGHT", 14, -112, { directions }),
        Row("slider", "Marker size", "bossTargetIndicatorSize", 24, 350, -112, { 8, 96, 1 }),
        Row("slider", "Marker X offset", "bossTargetIndicatorOffsetX", -28, 14, -188, { -500, 500, 1 }),
        Row("slider", "Marker Y offset", "bossTargetIndicatorOffsetY", 0, 350, -188, { -500, 500, 1 }),
        Row("dropdown", "Marker layout", "bossTargetIndicatorLayout", "SINGLE", 14, -264, { layouts }),
    }
    local styleMeta = SettingMeta(ctx, "boss_target_highlight.style", "general", "bossTargetHighlightStyle")
    table.insert(rows, 1, { "dropdown", "bossTargetHighlightStyle", nil, { "Highlight style", styles, 270 },
        beforeBind = function(widget) UnitSectionShared.PlaceDropdown(sec, widget, 14, -42, 270) end,
        meta = styleMeta, scope = unit, domain = "bossHighlight",
        get = function()
            local g = GetGeneral()
            local conf = GetConf(unit)
            local mode = conf.hlOverride == true and conf.bossTargetOutlineMode or nil
            if mode == nil then mode = g.bossTargetOutlineMode end
            if mode == 0 or (mode == nil and g.bossTargetHighlightEnabled == false) then return "OFF" end
            return MSUF.BossTargetIndicator.Style(g)
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v ~= "OFF"
            g.bossTargetOutlineMode = v ~= "OFF" and 1 or 0
            GetConf(unit).bossTargetOutlineMode = nil
            if v ~= "OFF" then g.bossTargetHighlightStyle = v end
            Apply()
        end })
    Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    Schema.Build(ctx, sec, {
        { "text", "unit.note.3", nil, {
            "Both sides mirror the X offset. Y moves both markers together. Drag the left marker to adjust the pair.", 350, -264, 280, T.colors.muted } },
        { "text", "unit.note.4", nil, {
            "Drag the marker in either boss preview to position it. Boss 1 shows the selected target.", 14, -340, 630, T.colors.muted } },
            { "toggle", "bossTargetMultipleOnly", false, { "Only highlight with multiple boss frames", 14, -390, 500 },
            meta = SettingMeta(ctx, "boss_target_highlight.multiple_only", unit, "bossTargetMultipleOnly"),
            scope = unit, domain = "bossHighlight",
            get = function() return GetConf(unit).bossTargetMultipleOnly == true end,
            write = { source = function() return GetConf(unit) end, strictBoolean = true, after = Apply }, --[[schema setter: UnitSections.19]]
            tip = { "Only highlight with multiple boss frames",
                "Requires at least two existing boss units, not two bosses taking damage. Updates during combat. Previews remain visible." } },
    }, ROW_OPTIONS)
end
--- Arena reuses the boss stacked-container model and its exact key names
--- (spacing/bossLayoutMode), so the same tile control edits the arena scope.
local function BuildArenaLayout(ctx, builder, unit)
    if unit ~= "arena" then return end
    BuildStackedLayout(ctx, builder, unit, { id = "arena_layout", title = "Arena Layout", height = 160,
        spacingLabel = "Arena spacing", spacingDefault = -96, spacingReason = "MSUF2_ARENA_SPACING",
        modeReason = "MSUF2_ARENA_LAYOUT_MODE", tilesTitle = "Arena frame layout" })
end
local function LazySection(ctx, builder, unit, buildFn, sectionId, title, height, prepareShell)
    if not UP.BuildSectionLazy then return buildFn(ctx, builder, unit) end
    return UP.BuildSectionLazy(ctx, builder, unit, {
        sectionId = sectionId,
        title = title,
        height = height,
        prepareShell = prepareShell or DeclareSection,
        build = buildFn,
    })
end
local function PrepareBasicsShell(ctx, sec, unit)
    PrepareBasicsSwitch(ctx, sec, unit)
    local refresh = AttachBasicsHeaderStatus(sec, unit)
    if refresh then
        if M.AddRefresherOnce then
            M.AddRefresherOnce(ctx, "frame-basics-header:" .. tostring(unit), refresh)
        else
            M.AddRefresher(ctx, refresh)
        end
    end
    return refresh
end
-- Boss and Arena keep their stacked-frame page preview alive only while the page is showing.
Preview.pages = {
    boss = { key = "uf_boss", request = "RequestBossPagePreviewForKey", set = "SetBossPagePreviewActive" },
    arena = { key = "uf_arena", request = "RequestArenaPagePreviewForKey", set = "SetArenaPagePreviewActive" },
}
function Preview.TrackPage(ctx, def)
    local function SetActive(active)
        if active and type(M[def.request]) == "function" then
            M[def.request](def.key)
            return
        end
        if M.UnitPage and M.UnitPage[def.set] then M.UnitPage[def.set](active) end
    end
    local function Refresh()
        SetActive(M.frame and M.frame.IsShown and M.frame:IsShown()
            and M.activeKey == def.key
            and ctx.wrapper and ctx.wrapper.IsShown and ctx.wrapper:IsShown())
    end
    ctx.wrapper:HookScript("OnShow", Refresh)
    ctx.wrapper:HookScript("OnHide", function() SetActive(false) end)
    M.TrackRefresh(ctx, Refresh)
end
local function BuildUnitPage(info)
    return function(ctx)
        local unit = info.unit
        local pagePreview = Preview.pages[unit]
        if pagePreview and ctx and ctx.wrapper then Preview.TrackPage(ctx, pagePreview) end
        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, unit, info.label)
        BuildPreview(ctx, builder, unit)
        LazySection(ctx, builder, unit, function(lazyCtx, lazyBuilder, lazyUnit)
            return BuildBasics(lazyCtx, lazyBuilder, lazyUnit, info.label)
        end, "frame_basics", "Basics", 216, PrepareBasicsShell)
        LazySection(ctx, builder, unit, BuildLayout, "anchoring", "Anchor", UNIT_ANCHOR_SECTION_HEIGHT)
        if UNIT_AURAS_MENU_UNITS[unit] and type(M.BuildAuras3UnitSection) == "function" then
            -- This workspace owns nested Buff/Debuff/Custom sections and previews;
            -- the lazy one-section proxy would stack those sections into one body.
            M.BuildAuras3UnitSection(ctx, builder, unit)
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_auras") end
        if unit == "target" then
            LazySection(ctx, builder, unit, BuildInlineText, "inline_text", "Inline Text", 214)
        end
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_inline_text") end
        BuildStatus(ctx, builder, unit)
        if unit == "boss" then
            LazySection(ctx, builder, unit, BuildBossLayout, "boss_layout", "Boss Layout", 150)
            LazySection(ctx, builder, unit, BuildBossTargetHighlight, "boss_target_highlight", "Boss target highlight", 450)
        end
        if unit == "arena" then
            LazySection(ctx, builder, unit, BuildArenaLayout, "arena_layout", "Arena Layout", 160)
        end
        LazySection(ctx, builder, unit, BuildLoadConditions, "load_conditions", "Visibility", 210)
        if UP.BuildRegisteredSections then UP.BuildRegisteredSections(ctx, builder, unit, "after_load_conditions") end
        AttachUnitSectionUX(ctx, unit)
        M.TrackRefresh(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, unit)
        end)
        if builder.RelayoutCollapsibles then builder:RelayoutCollapsibles() end
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end
-- The aura workspace's container tab and tool are the unit page's declared
-- views: a selector click shows that view's cached entry or builds it once.
local UNIT_AURA_VIEW_STATE = { unitAuraTabSelection = true, unitAuraToolSelection = true }
local function UnitAuraViewKey(unit)
    if not UNIT_AURAS_MENU_UNITS[unit] then return nil end
    return function()
        local view = M.UnitAuraWorkspaceView
        return view and view(unit) or nil
    end
end
for key, info in pairs(UNIT_PAGES) do
    local variantKey = UnitAuraViewKey(info.unit)
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 29,
        variantKey = variantKey,
        viewStateKeys = variantKey and UNIT_AURA_VIEW_STATE or nil,
    })
end
