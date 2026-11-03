-- Group preview chrome owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
local T = M.Theme
local Specs = M.GroupPreviewSpecs
local PreviewHelpers = M.PreviewHelpers
local GFZoomPan = M.GroupPreviewZoomPan
local Fallbacks = M.Fallbacks
local WHITE8X8 = Specs.WHITE8X8
local Tr = M.Tr
local floor = math.floor
local Model = RequireFields("GroupChrome.Model", M.GroupPreviewModel,
    "CurrentScope GF_PREVIEW_ROLE_LABELS NextPreviewRole PreviewRole SetPreviewRole")
local CurrentScope = Model.CurrentScope
local GF_PREVIEW_ROLE_LABELS = Model.GF_PREVIEW_ROLE_LABELS
local NextPreviewRole = Model.NextPreviewRole
local PreviewRole = Model.PreviewRole
local SetPreviewRole = Model.SetPreviewRole

local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/GroupPreview_Chrome")
local PublicGlobals = MSUF.PublicGlobals
local function RegisterGroupPreviewControl(widget, semanticPath, label, kind, classification, extra)
    local page = M.GroupPage
    if page and page.RegisterControl then
        page.RegisterControl(widget, { key = M.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
    end
    return widget
end
local LAYER_HEADER_COLOR = { 0.45, 0.50, 0.62, 0.80 }
local LAYER_TEXT_ON = { 0.76, 0.80, 0.90, 0.95 }
local function TrText(text)
    return (M.Tr and M.Tr(text)) or text
end
local function LayerFont(parent, text, color)
    color = color or LAYER_TEXT_ON
    local fs = PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    fs:SetText(TrText(text or ""))
    if fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    if T and T.StyleFontString then T.StyleFontString(fs, color, 0) end
    return fs
end
local function GroupPreviewDefaultHint()
    local base = Tr("drag to move - Tab picks the next element - ? lists every control")
    local remaining = PreviewHelpers.PreviewMoveHintRemaining and PreviewHelpers.PreviewMoveHintRemaining() or 0
    if remaining > 0 then
        return string.format("|cffff4d3f%s|r   %s",
            string.format(Tr("Drag background (%dx)"), remaining), base)
    end
    return base
end
local function UpdateHint(box)
    if not box then return end
    if M.PreviewSelectionBar then M.PreviewSelectionBar.Refresh(box) end
    if not box._hint then return end
    T.SetTranslatedText(box._hint, GroupPreviewDefaultHint())
end
if GFZoomPan.Configure then
    GFZoomPan.Configure({ T = T, TR = Tr, WHITE8X8 = WHITE8X8, UpdateHint = UpdateHint })
end
local NudgeStep = PreviewHelpers.NudgeStep or Fallbacks.One
local function PreviewAnimationInCombat()
    return (InCombatLockdown and InCombatLockdown()) or PublicGlobals.MSUF_InCombat == true
end
local function PreviewAnimationActive(box)
    return box and box._animationEnabled == true
end
local function SetPillText(btn, text)
    if btn.fs and btn.fs.SetText then
        btn.fs:SetText(text)
    elseif btn.SetText then
        btn:SetText(text)
    end
end
local function RefreshPreviewAnimationButton(box)
    local btn = box and box._previewAnimationButton
    if not btn then return end
    local active = PreviewAnimationActive(box)
    -- The button plays an animation loop; it does not switch the preview into a
    -- combat state. Label it after what it does, matching the Unit preview.
    SetPillText(btn, TrText(active and "Stop" or "Animate"))
    if btn.MSUF2RefreshPreviewPill then
        btn:MSUF2RefreshPreviewPill(active)
    elseif btn.SetActive then
        btn:SetActive(active)
    end
end
--- One animation frame: the light tick advances the last scene; only without
--- one (first frame, scope switch, combat, text drag) the full refresh runs.
local function RefreshPreviewAnimationFrame(box)
    if not box then return end
    if box.RefreshAnimation and box:RefreshAnimation() == true then return end
    if box.Refresh then
        box:Refresh("GROUP_PREVIEW_ANIMATE")
    elseif box.RequestRefresh then
        box:RequestRefresh("GROUP_PREVIEW_ANIMATE")
    end
end
local function ClearPreviewAnimationState(box)
    box._msufGFMenuPreviewAnimState = nil
    box._msufGFMenuPreviewAuraStates = nil
end
local function PreviewAnimationCombatHint(box)
    if box._hint then box._hint:SetText(TrText("Preview animation pauses during combat.")) end
end
local StartPreviewAnimationDriver, StopPreviewAnimationDriver, KillPreviewAnimationForCombat, SetPreviewAnimationEnabled =
    M.PreviewHelpers.CreateAnimationStarter(PreviewAnimationInCombat, RefreshPreviewAnimationFrame,
        RefreshPreviewAnimationButton, ClearPreviewAnimationState, PreviewAnimationCombatHint, RefreshPreviewAnimationFrame)
local function TogglePreviewAnimation(box)
    SetPreviewAnimationEnabled(box, not PreviewAnimationActive(box), "GROUP_PREVIEW_COMBAT_ANIMATE_TOGGLE")
end
local function NewPreviewPill(parent, width)
    local template = (T and T.Template and T.Template()) or "BackdropTemplate"
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent, template))
    btn:SetSize(width, 22)
    if btn.SetBackdrop then PixelLayoutRegion(btn, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 }) end
    btn.fs = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    btn.fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.fs:SetJustifyH("CENTER")
    if btn.fs.SetJustifyV then btn.fs:SetJustifyV("MIDDLE") end
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or LAYER_TEXT_ON, 0) end
    return btn
end
local function StylePreviewPill(btn, parent)
    if PreviewHelpers.StylePreviewPillButton then PreviewHelpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    if btn.SetFrameLevel and parent.GetFrameLevel then btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
end
local function CreatePreviewAnimationButton(box, registerControl)
    if not box or box._previewAnimationButton then return end
    local parent = box._stage or box
    local btn = NewPreviewPill(parent, 74)
    btn._preview = box
    btn._msuf2AllowCombatClick = true
    if box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -6, 0)
    elseif box._stage then
        btn:SetPoint("TOPRIGHT", box._stage, "TOPRIGHT", -154, -6)
    else
        btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -104, -34)
    end
    StylePreviewPill(btn, parent)
    PreviewHelpers.BindPreviewAnimationButton(btn, box, TogglePreviewAnimation, PreviewAnimationActive,
        PreviewAnimationInCombat, SetPreviewAnimationEnabled, "GROUP_PREVIEW_SEARCH_ANIMATION")
    local register = registerControl or RegisterGroupPreviewControl
    register(btn, "combat_animation", "Group Preview Animation", "button", "ephemeral")
    if M.AddTooltip then
        M.AddTooltip(btn, "Animate Preview",
            "Animates health, power, prediction bars, text values, aura timers, and combat-state indicators in this preview only. Pauses during combat.",
            { hook = true })
    end
    box._previewAnimationButton = btn
    box.RefreshAnimationButton = RefreshPreviewAnimationButton
    RefreshPreviewAnimationButton(box)
end
local function RefreshPreviewRoleButton(box, kind)
    local btn = box and box._previewRoleButton
    if not btn then return end
    SetPillText(btn, TrText(GF_PREVIEW_ROLE_LABELS[PreviewRole(kind)]))
end
local function CreatePreviewRoleButton(box, registerControl)
    if not box or box._previewRoleButton then return end
    local parent = box._stage or box
    local btn = NewPreviewPill(parent, 92)
    if box._previewAnimationButton then
        btn:SetPoint("RIGHT", box._previewAnimationButton, "LEFT", -6, 0)
    elseif box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -86, 0)
    end
    StylePreviewPill(btn, parent)
    btn:SetScript("OnClick", function()
        local kind = CurrentScope()
        SetPreviewRole(kind, NextPreviewRole(kind))
        RefreshPreviewRoleButton(box, kind)
        if box.Refresh then box:Refresh("GROUP_PREVIEW_ROLE") end
    end)
    local register = registerControl or RegisterGroupPreviewControl
    register(btn, "member_role", "Group Preview Member Role", "button", "ephemeral")
    box._previewRoleButton = btn
    box.RefreshRoleButton = RefreshPreviewRoleButton
    RefreshPreviewRoleButton(box)
end
local function ApplyGroupPreviewFlatBackdrop(frame, bg, border)
    if not (frame and frame.SetBackdrop) then return end
    PixelLayoutRegion(frame, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
    bg = bg or { 0, 0, 0, 1 }
    frame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1)
    if border and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 1)
    end
end
-- Role chrome from the shared helper; the flat colours apply only when it is missing.
local function ApplyGroupChrome(frame, role, bg, border)
    if PreviewHelpers.ApplyPreviewChrome then
        return PreviewHelpers.ApplyPreviewChrome(frame, role, T, ApplyGroupPreviewFlatBackdrop)
    end
    ApplyGroupPreviewFlatBackdrop(frame, bg, border)
end
local function EnsureGroupLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local btn = T.Button(box, "", 132, 20)
    btn:SetText(TrText("Preview Layers") .. " v", true)
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    btn:SetScript("OnClick", function()
        if box._layers then box._layers:SetShown(not box._layers:IsShown()) end
    end)
    if M.AddTooltip then M.AddTooltip(btn, "Preview Layers", "Toggle the preview layer list.", { hook = true }) end
    local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
    registerControl(btn, "layers.popover", "Group Preview Layers", "button", "ephemeral")
    box._msuf2LayersButton = btn
    return btn
end
local COMPACT_TOOL_FIELDS = { "_zoomBar", "_previewAnimationButton", "_previewRoleButton" }
local function SetGroupPreviewToolsShown(box, shown)
    if not box then return end
    local controlsHint = box._msuf2PreviewControlsHint
    local method = shown and "Show" or "Hide"
    if not shown and box._msuf2CompactToolsHidden ~= true then
        box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
    end
    box._msuf2CompactToolsHidden = not shown or nil
    for i = 1, #COMPACT_TOOL_FIELDS do
        local tool = box[COMPACT_TOOL_FIELDS[i]]
        if tool then tool[method](tool) end
    end
    if controlsHint and (not shown or box._msuf2CompactControlsHintWasShown) then controlsHint[method](controlsHint) end
end
-- The Theme button translates "Preview Layers" itself; the compact label is
-- composed, so it is translated first and set as translated.
local function LayoutGroupPreviewHeaderControls(box, compact)
    PreviewHelpers.LayoutCompactLayersButton(box, compact, M.Tr)
end
-- The full-size header: title, hint and tool buttons back, layers button back in its docked place.
local function ShowExpandedHeader(box)
    if box._title then box._title:Show() end
    if box._hint then box._hint:Show() end
    SetGroupPreviewToolsShown(box, true)
    LayoutGroupPreviewHeaderControls(box, false)
end
local function ApplyGroupCompactPresentation(box, compact)
    if not box then return end
    compact = compact == true
    box._msuf2CompactPreview = compact
    if box._msuf2PinnedFloating == true then compact = false end
    if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(box, compact, 1.50) end
    local stage, layers = box._stage, box._layers
    if compact then
        if box._title then box._title:Hide() end
        if box._hint then box._hint:Hide() end
        SetGroupPreviewToolsShown(box, false)
        if stage then
            stage:ClearAllPoints()
            stage:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
        end
        local layersBtn = EnsureGroupLayersButton(box)
        if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, false) end
        if layers and stage then
            layers:ClearAllPoints()
            if box._msuf2CompactHeader then layers:SetPoint("TOPRIGHT", layersBtn, "BOTTOMRIGHT", 0, -6)
            else layers:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28) end
            -- The chips keep their flow inside the popover, sized to a readable
            -- column; the caption is redundant behind a "Preview Layers" button.
            local popoverWidth = 268
            box._msuf2LayerPopoverWidth = popoverWidth
            layers:SetWidth(popoverWidth)
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            if box.LayoutLayerRail then box:LayoutLayerRail(popoverWidth) end
            if layers.SetFrameLevel and stage.GetFrameLevel then layers:SetFrameLevel((stage:GetFrameLevel() or 1) + 90) end
            layers:Hide()
        end
        layersBtn:Show()
        LayoutGroupPreviewHeaderControls(box, true)
        return
    end
    box._msuf2LayerPopoverWidth = nil
    ShowExpandedHeader(box)
    if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, true) end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
end

M.GroupPreviewChrome = {
    RegisterGroupPreviewControl = RegisterGroupPreviewControl,
    LayerFont = LayerFont,
    LAYER_HEADER_COLOR = LAYER_HEADER_COLOR,
    UpdateHint = UpdateHint,
    PreviewAnimationInCombat = PreviewAnimationInCombat,
    PreviewAnimationActive = PreviewAnimationActive,
    StartPreviewAnimationDriver = StartPreviewAnimationDriver,
    StopPreviewAnimationDriver = StopPreviewAnimationDriver,
    KillPreviewAnimationForCombat = KillPreviewAnimationForCombat,
    SetPreviewAnimationEnabled = SetPreviewAnimationEnabled,
    RefreshPreviewAnimationButton = RefreshPreviewAnimationButton,
    CreatePreviewAnimationButton = CreatePreviewAnimationButton,
    CreatePreviewRoleButton = CreatePreviewRoleButton,
    ApplyGroupPreviewFlatBackdrop = ApplyGroupPreviewFlatBackdrop,
    ApplyGroupChrome = ApplyGroupChrome,
    ShowExpandedHeader = ShowExpandedHeader,
    ApplyGroupCompactPresentation = ApplyGroupCompactPresentation,
    TrText = TrText,
}
