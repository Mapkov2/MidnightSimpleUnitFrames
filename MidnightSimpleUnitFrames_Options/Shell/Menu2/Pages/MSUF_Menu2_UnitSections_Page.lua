-- Page state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.UnitSectionFactories = M.UnitSectionFactories or {}

M.UnitSectionFactories.Page = function(
    MSUF, M, FILE, PixelLayoutRegion, Core, C_Timer, W, T, ControlGates, UP, floor, max, UNIT_PAGES, UF_COPY_CATEGORIES,
    DefaultCopyTarget, UnitTopLabel, UnitTopLabelKey, UnitTopPillWidth, NewCopyScopeDefaults, ConfirmCopyToAll, CopyUnitSettings,
    ReadBool, RegisterControl, Schema, RequestUnitRuntimeApply, UnitSectionShared
)

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

return BuildPreview, BuildTopActions, ApplyUnitFrameEnabledGate, Preview, UNIT_TAB_ORDER, UNIT_PAGE_FOR_UNIT, UnitFrameEnabled, SectionNumber
end
