--- EditMode/MSUF_EditMode_HUD.lua - the Edit Mode toolbar
--- Builds the dock's controls, lays them out for the docked edge, and keeps
--- the inspector row, the status hint and the control states current.
--- Builds EditMode HUD widgets only; secure frame mutation stays behind EditMode helpers.
--- Loads last of the toolbar files in MSUF_EditMode.xml.
local addonName, MSUF = ...
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_HUD.lua"
local ExportPublic = (MSUF or _G.MSUF_NS or {}).ExportPublic
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD, DockUI, Kit, Selection = EM2.HUD, EM2.HUDDock, EM2.HUDKit, EM2.HUDSelection
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local floor, max, min = math.floor, math.max, math.min
local ApplyAllSettingsSafe = (EM2.Util or {}).ApplyAllSettingsSafe

local L, FONT, W8, SharedUI, HelpText, TH = Kit.L, Kit.FONT, Kit.W8, Kit.SharedUI, Kit.HelpText, Kit.TH
local BTN_H, BTN_H2, CLUSTER_H, CLUSTER_BTN_H = Kit.BTN_H, Kit.BTN_H2, Kit.CLUSTER_H, Kit.CLUSTER_BTN_H
local DOCK_HORIZONTAL_W, DOCK_HORIZONTAL_H, DOCK_VERTICAL_W = Kit.DOCK_HORIZONTAL_W, Kit.DOCK_HORIZONTAL_H, Kit.DOCK_VERTICAL_W
local RefreshHUDTheme, ApplyHUDMaterial, MakeFS, MakeBtn = Kit.RefreshHUDTheme, Kit.ApplyHUDMaterial, Kit.MakeFS, Kit.MakeBtn
local SetActive, SetControlEnabled, SetHistoryEnabled = Kit.SetActive, Kit.SetControlEnabled, Kit.SetHistoryEnabled
local SetTip, AttachHistoryIcon, ApplyButtonRole = Kit.SetTip, Kit.AttachHistoryIcon, Kit.ApplyButtonRole
local AddCluster, FinishCluster, AddRowButton, AddAdjustWidget = Kit.AddCluster, Kit.FinishCluster, Kit.AddRowButton, Kit.AddAdjustWidget
local LayoutClusterRow, LayoutClusterColumn = Kit.LayoutClusterRow, Kit.LayoutClusterColumn
local UNIT_KEYS, GROUP_KEY_TO_KIND = Selection.UNIT_KEYS, Selection.GROUP_KEY_TO_KIND
local CurrentFocusSelection, SelectionValues = Selection.CurrentFocusSelection, Selection.SelectionValues
local FormatSelectionSummary, DefaultHintText = Selection.FormatSelectionSummary, Selection.DefaultHintText
local EnsureDockState, ClampDockNumber, IsVerticalDock = DockUI.EnsureDockState, DockUI.ClampDockNumber, DockUI.IsVerticalDock
local RefreshDockContext, AttachDockHover = DockUI.RefreshDockContext, DockUI.AttachDockHover
local PlacePositionPopup, EnsurePositionPopup, RefreshPositionPopup = DockUI.PlacePositionPopup, DockUI.EnsurePositionPopup, DockUI.RefreshPositionPopup
local SetDockExpanded, ScheduleDockAutoHide, StopDockDrag = DockUI.SetDockExpanded, DockUI.ScheduleDockAutoHide, DockUI.StopDockDrag

local hudFrame, row2Frame
local previewBtn, previewAnimBtn, auraBtn, snapToggle, resetBtn, settingsBtn, cdmBtn, anchorBtn
local previewAddonSlot

local previewAnimRefreshRegistered
local undoBtn, redoBtn, cancelAllBtn, exitBtn
local alphaFS, stepFS
local selectionFS, hintFS
local hudStatusText, hudStatusKind, hudStatusUntil
local selectionLastText, hintLastText, hintLastR, hintLastG, hintLastB, hintLastA
local helpBtn
local bgWidget, gridWidget

local function RegisterPreviewAnimationRefreshOwner()
    if previewAnimRefreshRegistered or not previewAnimBtn then return end
    local register = _G.MSUF_RegisterPreviewAnimationRefreshOwner
    if type(register) ~= "function" then return end
    register(previewAnimBtn, function(btn, active)
        SetActive(btn, active == true)
    end)
    previewAnimRefreshRegistered = true
end

local function SetHint(text, r, g, b, a)
    if not hintFS then return end
    text = text or ""
    r, g, b, a = r or TH.mutedR, g or TH.mutedG, b or TH.mutedB, a or 0.78
    if hintLastText ~= text then
        hintFS:SetText(text)
        hintLastText = text
    end
    if hintLastR ~= r or hintLastG ~= g or hintLastB ~= b or hintLastA ~= a then
        hintFS:SetTextColor(r, g, b, a)
        hintLastR, hintLastG, hintLastB, hintLastA = r, g, b, a
    end
end

function HUD.SetStatus(text, kind, seconds)
    seconds = seconds or 1.6
    hudStatusText = text
    hudStatusKind = kind
    hudStatusUntil = (GetTime and GetTime() or 0) + seconds
    HUD.RefreshControls()
    C_Timer.After(seconds, function()
        if HUD.IsShown and HUD.IsShown() then HUD.RefreshControls() end
    end)
end

local function ApplyDockLayout()
    if not (hudFrame and UIParent) then return end
    --- A relayout re-anchors the frame, and a running Translation renders
    --- relative to that anchor - so land the entry slide first, or the toolbar
    --- would jump by whatever travel was left.
    if DockUI.introPlaying then DockUI.StopDockIntro() end
    local state = EnsureDockState()
    local dock = state.dock
    local vertical = IsVerticalDock(dock)
    local screenW = tonumber(UIParent:GetWidth()) or 1920
    local screenH = tonumber(UIParent:GetHeight()) or 1080
    local edge = state.edgeOffset

    hudFrame:ClearAllPoints()
    DockUI.primaryContainer:ClearAllPoints()
    DockUI.historyContainer:ClearAllPoints()
    DockUI.grip:ClearAllPoints()
    DockUI.logo:ClearAllPoints()
    DockUI.title:ClearAllPoints()
    DockUI.contextBtn:ClearAllPoints()
    helpBtn:ClearAllPoints()
    cancelAllBtn:ClearAllPoints()
    exitBtn:ClearAllPoints()
    row2Frame:ClearAllPoints()
    DockUI.inspectorSelection:ClearAllPoints()
    hintFS:ClearAllPoints()
    for _, cell in ipairs(DockUI.inspectorMetrics or {}) do cell:ClearAllPoints() end
    if DockUI.primaryContainer.SetScale then DockUI.primaryContainer:SetScale(1) end
    if vertical then
        DockUI.inspectorCompact = true
        local historyHeight = LayoutClusterColumn(DockUI.historyContainer, DockUI.row2 or {})
        local primaryHeight = LayoutClusterColumn(DockUI.primaryContainer, DockUI.row1 or {})
        local totalHeight = min(screenH - 32, 38 + 34 + 32 + historyHeight + primaryHeight + 78)
        hudFrame:SetSize(DOCK_VERTICAL_W, max(390, totalHeight))
        DockUI.AnchorDock(dock, edge)

        DockUI.grip:SetSize(58, 16)
        DockUI.grip:SetPoint("TOP", hudFrame, "TOP", 0, -8)
        DockUI.logo:SetSize(30, 30)
        DockUI.logo:SetPoint("TOP", DockUI.grip, "BOTTOM", 0, -4)
        DockUI.title:Hide()
        DockUI.contextBtn:Hide()
        helpBtn:SetSize(58, 26)
        helpBtn:SetPoint("TOP", DockUI.logo, "BOTTOM", 0, -5)
        DockUI.historyContainer:SetPoint("TOP", helpBtn, "BOTTOM", 0, -7)
        DockUI.primaryContainer:SetPoint("TOP", DockUI.historyContainer, "BOTTOM", 0, -7)
        exitBtn:SetSize(58, 28)
        exitBtn:SetPoint("BOTTOM", hudFrame, "BOTTOM", 0, 8)
        cancelAllBtn:SetSize(58, 28)
        cancelAllBtn:SetPoint("BOTTOM", exitBtn, "TOP", 0, 4)

        row2Frame:SetSize(320, 34)
        if dock == "LEFT" then row2Frame:SetPoint("LEFT", hudFrame, "RIGHT", 8, 0)
        else row2Frame:SetPoint("RIGHT", hudFrame, "LEFT", -8, 0) end
        DockUI.inspectorSelection:SetSize(145, 30)
        DockUI.inspectorSelection:SetPoint("LEFT", row2Frame, "LEFT", 4, 0)
        for _, cell in ipairs(DockUI.inspectorMetrics or {}) do cell:Hide() end
        hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -12, 0)
        hintFS:SetWidth(145)
    else
        DockUI.inspectorCompact = false
        LayoutClusterRow(DockUI.historyContainer, DockUI.row2 or {})
        LayoutClusterRow(DockUI.primaryContainer, DockUI.row1 or {})
        local targetWidth = DockUI.horizontalWidth or DOCK_HORIZONTAL_W
        local dockWidth = min(targetWidth, max(320, screenW - 32))
        hudFrame:SetSize(dockWidth, DOCK_HORIZONTAL_H)
        if dock == "FREE" then
            local maxFreeX = max(0, (screenW - dockWidth) * 0.5)
            local maxFreeY = max(0, (screenH - DOCK_HORIZONTAL_H) * 0.5)
            state.freeX = ClampDockNumber(state.freeX, -maxFreeX, maxFreeX, 0)
            state.freeY = ClampDockNumber(state.freeY, -maxFreeY, maxFreeY, 0)
        end
        DockUI.AnchorDock(dock, edge)

        DockUI.grip:SetSize(20, BTN_H)
        DockUI.grip:SetPoint("LEFT", hudFrame, "LEFT", 12, 0)
        DockUI.logo:SetSize(32, 32)
        DockUI.logo:SetPoint("LEFT", DockUI.grip, "RIGHT", 4, 0)
        local compact = dockWidth < 1080
        DockUI.title:SetShown(not compact)
        if not compact then DockUI.title:SetPoint("LEFT", DockUI.logo, "RIGHT", 7, 0) end
        DockUI.contextBtn:Show()
        DockUI.contextBtn:SetSize(compact and 80 or 96, BTN_H)
        DockUI.contextBtn:SetPoint("LEFT", compact and DockUI.logo or DockUI.title, "RIGHT", 8, 0)
        helpBtn:SetSize(BTN_H, BTN_H)
        helpBtn:SetPoint("LEFT", DockUI.contextBtn, "RIGHT", 8, 0)
        DockUI.historyContainer:SetPoint("LEFT", helpBtn, "RIGHT", 8, 0)
        exitBtn:SetSize(80, BTN_H)
        exitBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -16, -7)
        cancelAllBtn:SetSize(88, BTN_H)
        cancelAllBtn:SetPoint("RIGHT", exitBtn, "LEFT", -8, 0)

        -- Keep the task clusters physically anchored after History.  Merely
        -- centering a scaled container inside an estimated lane allowed its
        -- left edge to slide back over Redo even while the right edge passed
        -- the clipping check.  The relative LEFT anchor makes that collision
        -- impossible; the measured lane is used when WoW has resolved it and
        -- the deterministic width remains the safe first-pass fallback.
        local titleWidth = 0
        if not compact then
            titleWidth = DockUI.title.GetStringWidth and tonumber(DockUI.title:GetStringWidth()) or 72
            titleWidth = min(160, max(56, titleWidth or 72))
        end
        local contextWidth = compact and 80 or 96
        local historyWidth = max(1, tonumber(DockUI.historyContainer:GetWidth()) or 1)
        local laneLeft = 12 + 20 + 4 + 32
            + (compact and 8 or (7 + titleWidth + 8))
            + contextWidth + 8 + BTN_H + 8 + historyWidth
        local laneRight = dockWidth - 16 - 80 - 8 - 88
        local laneWidth = max(1, laneRight - laneLeft - 16)
        local measuredLeft = DockUI.historyContainer:GetRight()
        local measuredRight = cancelAllBtn:GetLeft()
        if measuredLeft and measuredRight and measuredRight > measuredLeft + 16 then
            laneWidth = measuredRight - measuredLeft - 16
        end
        local contentWidth = max(1, tonumber(DockUI.primaryContainer:GetWidth()) or 1)
        if DockUI.primaryContainer.SetScale then
            DockUI.primaryContainer:SetScale(min(1, laneWidth / contentWidth))
        end
        DockUI.primaryContainer:SetPoint("LEFT", DockUI.historyContainer, "RIGHT", 8, 0)

        local inspectorWidth = min(800, max(240, dockWidth - 80))
        row2Frame:SetSize(inspectorWidth, DockUI.inspectorH)
        if dock == "BOTTOM" then row2Frame:SetPoint("BOTTOM", hudFrame, "TOP", 0, 4)
        else row2Frame:SetPoint("TOP", hudFrame, "BOTTOM", 0, -4) end
        DockUI.inspectorSelection:SetSize(DockUI.inspectorLabelW, BTN_H)
        DockUI.inspectorSelection:SetPoint("LEFT", row2Frame, "LEFT", 4, 0)
        local previous = DockUI.inspectorSelection
        for _, cell in ipairs(DockUI.inspectorMetrics or {}) do
            cell:Show()
            cell:SetSize(DockUI.inspectorMetricW, BTN_H)
            cell:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            previous = cell
        end
        hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -16, 0)
        hintFS:SetWidth(max(140, inspectorWidth - DockUI.inspectorLabelW - DockUI.inspectorMetricW * 4 - 36))
    end

    RefreshDockContext()
    PlacePositionPopup()
    if DockUI.positionPopup and DockUI.positionPopup:IsShown() then RefreshPositionPopup() end
    if hudFrame:IsShown() and HUD.RefreshControls then
        selectionLastText = nil
        HUD.RefreshControls(true)
    end
    SetDockExpanded(true)
    if state.autoHide then ScheduleDockAutoHide() end
end

--- The dock frame, its entry slide and the six-dot drag grip.
local function BuildDockFrame()
    --- Compact MSUF command dock.  The existing actions remain unchanged;
    --- only their chrome and cold-path layout are owned here.
    hudFrame = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_HUD", UIParent, "BackdropTemplate"))
    hudFrame:SetFrameStrata("TOOLTIP")
    hudFrame:SetFrameLevel(1200)
    hudFrame:SetSize(DockUI.horizontalWidth, DOCK_HORIZONTAL_H)
    DockUI.PixelLayoutRegion(hudFrame, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    hudFrame:SetBackdropColor(unpack(TH.r1Bg))
    hudFrame:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.48)
    ApplyHUDMaterial(hudFrame, "status")
    hudFrame:SetMovable(true)
    hudFrame:SetClampedToScreen(true)
    hudFrame:EnableMouse(true)
    hudFrame:Hide()

    --- Entry slide: built once, driven entirely C-side.  Both animations share
    --- order 1 so the fade and the move run together.
    if hudFrame.CreateAnimationGroup then
        local intro = hudFrame:CreateAnimationGroup()
        local slide = intro:CreateAnimation("Translation")
        slide:SetDuration(DockUI.introDuration)
        slide:SetOrder(1)
        slide:SetSmoothing("OUT")
        local fade = intro:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetDuration(DockUI.introDuration)
        fade:SetOrder(1)
        fade:SetSmoothing("OUT")
        intro:SetScript("OnFinished", function() DockUI.FinishDockIntro() end)
        intro:SetScript("OnStop", function() DockUI.FinishDockIntro() end)
        DockUI.introGroup = intro
        DockUI.introSlide = slide
    end

    DockUI.grip = DockUI.PixelLayoutRegion(CreateFrame("Button", nil, hudFrame))
    DockUI.grip:RegisterForDrag("LeftButton")
    DockUI.grip:SetScript("OnDragStart", function()
        if DockUI.positionPopup then DockUI.positionPopup:Hide() end
        SetDockExpanded(true)
        DockUI.grip._dockDragging = DockUI.BeginDrag() or nil
    end)
    DockUI.grip:SetScript("OnDragStop", function()
        if not DockUI.grip._dockDragging then return end
        DockUI.grip._dockDragging = nil
        StopDockDrag()
    end)
    for row = 0, 2 do
        for col = 0, 1 do
            local dot = DockUI.PixelLayoutRegion(DockUI.grip:CreateTexture(nil, "ARTWORK"))
            dot:SetSize(2, 2)
            dot:SetPoint("CENTER", DockUI.grip, "CENTER", (col - 0.5) * 6, (row - 1) * 6)
            dot:SetColorTexture(TH.mutedR, TH.mutedG, TH.mutedB, 0.86)
        end
    end
end

--- Logo, title and the frame picker button.
local function BuildDockHeader()
    DockUI.logo = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, hudFrame))
    local logoTexture = DockUI.PixelLayoutRegion(DockUI.logo:CreateTexture(nil, "ARTWORK"))
    logoTexture:SetAllPoints(DockUI.logo)
    logoTexture:SetTexture(MEDIA .. "MSUF_EditModeIcon.png")
    if logoTexture.SetSnapToPixelGrid then
        logoTexture:SetSnapToPixelGrid(false)
        logoTexture:SetTexelSnappingBias(0)
    end

    DockUI.title = MakeFS(hudFrame, "body", TH.onR, TH.onG, TH.onB, 1)
    DockUI.title:SetText(HelpText("Edit Mode"))

    DockUI.contextBtn = MakeBtn(hudFrame, "Groups", 96, BTN_H, "caption", function()
        HUD.ToggleFramePicker()
    end)
    if DockUI.contextBtn._label then
        DockUI.contextBtn._label:ClearAllPoints()
        DockUI.contextBtn._label:SetPoint("LEFT", DockUI.contextBtn, "LEFT", 9, 0)
        DockUI.contextBtn._label:SetPoint("RIGHT", DockUI.contextBtn, "RIGHT", -18, 0)
        DockUI.contextBtn._label:SetJustifyH("LEFT")
    end
    local contextChevron = MakeFS(DockUI.contextBtn, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.88)
    contextChevron:SetPoint("RIGHT", DockUI.contextBtn, "RIGHT", -7, 1)
    contextChevron:SetText("v")
    SetTip(DockUI.contextBtn, "Pick the frame or group to edit, including ones hidden behind another frame.")
end

local function BuildHelpButton()
    --- Guided help remains available, but no longer dominates the toolbar.
    helpBtn = DockUI.PixelLayoutRegion(CreateFrame("Button", nil, hudFrame, "BackdropTemplate"))
    helpBtn:SetSize(BTN_H, BTN_H)
    DockUI.PixelLayoutRegion(helpBtn, "SetBackdrop", { bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    helpBtn:SetBackdropColor(TH.onR * 0.20, TH.onG * 0.20, TH.onB * 0.20, 0.85)
    helpBtn:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.60)
    do
        local glow = DockUI.PixelLayoutRegion(helpBtn:CreateTexture(nil, "BACKGROUND", nil, -1))
        glow:SetPoint("TOPLEFT", -3, 3)
        glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.08)
        helpBtn._glow = glow

        local hl = DockUI.PixelLayoutRegion(helpBtn:CreateTexture(nil, "HIGHLIGHT"))
        hl:SetAllPoints()
        hl:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.12)

        local lbl = MakeFS(helpBtn, "body", TH.onR, TH.onG, TH.onB, 1)
        lbl:SetPoint("CENTER", 0, 0)
        lbl:SetText("?")
        helpBtn._label = lbl

        local pulse = helpBtn:CreateAnimationGroup()
        local fadeOut = pulse:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = pulse:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("IN_OUT")
        pulse:SetLooping("REPEAT")
        helpBtn._pulse = pulse
    end
    helpBtn:SetScript("OnClick", DockUI.OpenGuidedTour)
    helpBtn:SetScript("OnEnter", function(self)
        if self._pulse then self._pulse:Stop() end
        self:SetAlpha(1)
        if not DockUI.OwnTooltip(self, "ANCHOR_BOTTOM", 0, -6) then return end
        GameTooltip:SetText(HelpText("EM_HELP_BTN_TIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function()
        DockUI.ReleaseTooltip()
    end)
end

local function BuildExitControls()
    --- Right-side: Cancel All | Exit
    exitBtn = MakeBtn(hudFrame, "EM_TOUR_DONE", 80, BTN_H, "body", function()
        if EM2.State then EM2.State.Exit("hud_exit") end
    end)
    ApplyButtonRole(exitBtn, "primary")
    exitBtn._dot:Hide()
    SetTip(exitBtn, "Keep the current positions and exit Edit Mode.")

    cancelAllBtn = MakeBtn(hudFrame, "Discard", 88, BTN_H, "body", function()
        if not EM2.State or not EM2.State.CancelAll then return end
        local cf = _G["MSUF_EM2_CancelConfirm"]
        if cf then
            cf:Show()
            return
        end
        cf = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_CancelConfirm", UIParent, "BackdropTemplate"))
        cf:SetSize(320, 120)
        cf:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        cf:SetFrameStrata("TOOLTIP")
        cf:SetFrameLevel(1400)
        DockUI.PixelLayoutRegion(cf, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
        cf:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], TH.r1Bg[4] or 0.97)
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        ApplyHUDMaterial(cf, "popup")
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        cf:EnableMouse(true)
        local msg = MakeFS(cf, "body", TH.textR, TH.textG, TH.textB, 1)
        msg:SetPoint("TOP", cf, "TOP", 0, -24)
        msg:SetText(HelpText("Discard all changes and exit?"))
        local function ConfBtn(text, xOff, role, onClick)
            local ui = SharedUI()
            local b = ui and ui.Button and ui.Button(cf, HelpText(text), 112, 32, {
                align = "CENTER",
                skipHistory = true,
                variant = role == "danger" and "danger" or nil,
                onClick = onClick,
            }) or DockUI.PixelLayoutRegion(CreateFrame("Button", nil, cf, "BackdropTemplate"))
            b:SetSize(112, 32)
            b:SetPoint("BOTTOM", cf, "BOTTOM", xOff, 16)
            if ui and ui.ApplyButtonRole then ui.ApplyButtonRole(b, role or "normal") end
            --- Same Blizzard-font-object inheritance as the toolbar buttons.
            local sharedLabel = b._msuf2Label or b._label
            if sharedLabel and ui and ui.ApplyFontRole then
                ui.ApplyFontRole(sharedLabel, "body", FONT, "")
            end
            if not (ui and ui.Button) then
                DockUI.PixelLayoutRegion(b, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1 })
                b:SetBackdropColor(TH.r2Bg[1], TH.r2Bg[2], TH.r2Bg[3], TH.r2Bg[4] or 0.90)
                b:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.65)
                local hl = DockUI.PixelLayoutRegion(b:CreateTexture(nil, "HIGHLIGHT"))
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                local fs = MakeFS(b, "body", TH.textR, TH.textG, TH.textB, 1)
                fs:SetPoint("CENTER")
                fs:SetText(HelpText(text))
                b:SetScript("OnClick", onClick)
            end
            return b
        end
        ConfBtn("Yes, discard", -64, "danger", function() cf:Hide(); EM2.State.CancelAll() end)
        ConfBtn("No, keep", 64, "normal", function() cf:Hide() end)
        cf:EnableKeyboard(true)
        cf:SetScript("OnKeyDown", function(s, k)
            if k == "ESCAPE" then s:SetPropagateKeyboardInput(false); cf:Hide()
            else s:SetPropagateKeyboardInput(true) end
        end)
        cf:HookScript("OnHide", function(s)
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        end)
        cf:Show()
    end)
    ApplyButtonRole(cancelAllBtn, "normal")
    cancelAllBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.90)
    cancelAllBtn._dot:Hide()
    SetTip(cancelAllBtn, "Discard ALL changes made in Edit Mode\nand restore settings to the state\nbefore Edit Mode was opened.")
end

local function BuildPreviewCluster(advancedHUD)
    local previewCluster, previewItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Preview", CLUSTER_H, true)
    previewBtn = AddRowButton(previewItems, previewCluster, "Preview", 72, CLUSTER_BTN_H, "caption", function()
        ExportPublic("MSUF_UnitPreviewActive", not (_G.MSUF_UnitPreviewActive and true or false))
        if _G.MSUF_SyncAllUnitPreviews then _G.MSUF_SyncAllUnitPreviews() end
        SetActive(previewBtn, _G.MSUF_UnitPreviewActive)
        HUD.SetStatus(HelpText(_G.MSUF_UnitPreviewActive and "EM_PREVIEW_ON" or "EM_PREVIEW_OFF"), "info")
    end, "Show placeholder data on unitframes\nwithout real units (target, focus, etc.)")

    previewAddonSlot = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_HUD_PreviewAddonSlot", previewCluster))
    previewAddonSlot:SetSize(72, CLUSTER_BTN_H)
    previewItems[#previewItems+1] = previewAddonSlot

    if advancedHUD then
    previewAnimBtn = AddRowButton(previewItems, previewCluster, "Motion", 64, CLUSTER_BTN_H, "caption", function()
        local toggle = _G.MSUF_TogglePreviewAnimation
        if type(toggle) ~= "function" then
            HUD.SetStatus(HelpText("Preview animation unavailable"), "warn")
            return
        end
        local ok, reason = toggle("edit_mode")
        local active = MSUF.Require("MSUF_IsPreviewAnimationEnabled", CALLER)() == true
        SetActive(previewAnimBtn, active)
        if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
        if ok == false and reason == "combat" then
            HUD.SetStatus(HelpText("Preview animation pauses during combat."), "warn")
        else
            HUD.SetStatus(HelpText(active and "Preview animation on" or "Preview animation off"), "info")
        end
    end, "Animate visible preview dummy frames.\nStops automatically in combat\nor when previews are hidden.")
    RegisterPreviewAnimationRefreshOwner()

    auraBtn = AddRowButton(previewItems, previewCluster, "Auras", 64, CLUSTER_BTN_H, "caption", function()
        local db = _G.MSUF_DB
        if not db then
            return
        end
        local a2 = db.auras3
        if not a2 then
            return
        end
        local sh = a2.shared
        if not sh then
            return
        end
        local undo = EM2.Undo
        local tracked = undo and undo.BeginChange and undo.BeginChange("aura", "shared", "Toggle") == true
        sh.showInEditMode = not (sh.showInEditMode and true or false)
        if tracked then undo.CommitChange() end
        SetActive(auraBtn, sh.showInEditMode and _G.MSUF_UnitPreviewActive == true)
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.RefreshEditPreview) == "function" then
            a3.RefreshEditPreview()
        elseif a3 and type(a3.RefreshAll) == "function" then
            a3.RefreshAll()
        end
        HUD.SetStatus(HelpText(sh.showInEditMode and "EM_AURAS_ON" or "EM_AURAS_OFF"), "info")
    end, "Toggle aura preview icons\nand aura mover boxes.")
    end
    FinishCluster(previewCluster, previewItems, CLUSTER_H, -7)
end

local function BuildLayoutCluster()
    local layoutCluster, layoutItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Layout", CLUSTER_H, true)
    snapToggle = AddRowButton(layoutItems, layoutCluster, "Snap", 56, CLUSTER_BTN_H, "caption", function()
        if EM2.Snap then
            local on = not EM2.Snap.IsEnabled()
            EM2.Snap.SetEnabled(on)
            SetActive(snapToggle, on)
            HUD.SetStatus(HelpText(on and "EM_SNAP_ON" or "EM_SNAP_OFF"), "info")
        end
    end, "Snap frames to edges of\nother frames while dragging.")

    gridWidget, stepFS = AddAdjustWidget(layoutItems, layoutCluster, 72, CLUSTER_BTN_H, true, function(_, d)
        if not EM2.Grid then return end
        EM2.Grid.SetGridStep(max(4, min(80, EM2.Grid.GetGridStep() + d * 4)))
        HUD.RefreshControls()
    end, function(_, button)
        if button ~= "LeftButton" or not EM2.Grid or not EM2.Grid.ToggleEnabled then return end
        EM2.Grid.ToggleEnabled()
        HUD.SetStatus(HelpText((not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()) and "EM_GRID_ON" or "EM_GRID_OFF"), "info")
        HUD.RefreshControls()
    end, "Left-click to toggle grid lines.\nScroll to adjust spacing.")

    bgWidget, alphaFS = AddAdjustWidget(layoutItems, layoutCluster, 68, CLUSTER_BTN_H, false, function(_, d)
        if not EM2.Grid then return end
        EM2.Grid.SetBgAlpha(max(0, min(1, EM2.Grid.GetBgAlpha() + d * 0.05)))
        HUD.RefreshControls()
    end, nil, "Background overlay opacity.\nScroll to adjust.")

    resetBtn = AddRowButton(layoutItems, layoutCluster, "Reset", 56, CLUSTER_BTN_H, "caption", function()
        HUD.ResetCurrentPosition()
    end, "Reset the selected frame position.\nSize stays unchanged.")
    FinishCluster(layoutCluster, layoutItems, CLUSTER_H, -7)
    layoutCluster._stepFS = stepFS
    layoutCluster._alphaFS = alphaFS
    layoutCluster._gridWidget = gridWidget
    layoutCluster._bgWidget = bgWidget
    ExportPublic("MSUF_EditModeGridTools", layoutCluster)
end

local function BuildToolsCluster()
    local linksCluster, linksItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Tools", CLUSTER_H, true)
    DockUI.positionBtn = AddRowButton(linksItems, linksCluster, "Position", 76, CLUSTER_BTN_H, "caption", function()
        local popup = EnsurePositionPopup()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end, "Dock the Edit Mode toolbar at any screen edge.")
    settingsBtn = AddRowButton(linksItems, linksCluster, "Settings", 76, CLUSTER_BTN_H, "caption", function()
        HUD.OpenSelectedSettings()
    end, "Open Menu2 at the selected\nframe or component settings.")

    if HUD.CooldownAnchorSupported() then
        cdmBtn = AddRowButton(linksItems, linksCluster, "Cooldown", 116, CLUSTER_BTN_H, "caption", function()
            local db = _G.MSUF_DB
            if not db then
                return
            end
            db.general = db.general or {}
            local enabled = not HUD.CooldownAnchorEnabled(db.general)
            local setter = _G.MSUF_SetCooldownAnchorEnabled
            local undo = EM2.Undo
            local tracked = undo and undo.BeginChange and undo.BeginChange("general", "cooldown", "Toggle") == true
            if type(setter) == "function" then
                setter(enabled, true)
            else
                db.general.anchorToCooldown = enabled
            end
            if tracked then undo.CommitChange() end
            SetActive(cdmBtn, HUD.CooldownAnchorEnabled(db.general))
            ApplyAllSettingsSafe()
            HUD.SetStatus(HelpText(enabled and "EM_CDM_ON" or "EM_CDM_OFF"), "info")
            C_Timer.After(0.1, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
                if _G.MSUF_EM2_ReforcePreviewFrames then _G.MSUF_EM2_ReforcePreviewFrames() end
            end)
        end, "Anchor all unitframes to the\nEssential Cooldown Manager.")
    end

    anchorBtn = AddRowButton(linksItems, linksCluster, "Anchor", 60, CLUSTER_BTN_H, "caption", function()
        local ov = MSUF.Require("MSUF_EnsureAnchorPicker", CALLER)()
        if not ov then return end
        ov._isCandidateAllowed = function(frame)
            local factory = MSUF and MSUF.UF and MSUF.UF.Factory
            return not factory or type(factory.IsAnchorCandidateAllowed) ~= "function"
                or factory.IsAnchorCandidateAllowed(frame)
        end
        ov._onPick = function(frameName)
            local db = _G.MSUF_DB
            if not db then
                return
            end
            db.general = db.general or {}
            local undo = EM2.Undo
            local tracked = undo and undo.BeginChange and undo.BeginChange("general", "anchor", "Set") == true
            db.general.anchorName = frameName
            local setter = _G.MSUF_SetCooldownAnchorEnabled
            if type(setter) == "function" then
                setter(false, true)
            else
                db.general.anchorToCooldown = false
            end
            if tracked then undo.CommitChange() end
            SetActive(cdmBtn, false)
            ApplyAllSettingsSafe()
            HUD.SetStatus(string.format(HelpText("Anchor set: %s"), tostring(frameName or "")), "ok")
            C_Timer.After(0.1, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
        end
        ov:Show()
    end, "Pick any frame as global anchor\nfor all unitframes.\nOverrides CDM anchor.")
    FinishCluster(linksCluster, linksItems, CLUSTER_H, -7)
end

local function BuildInspectorRow()
    --- Compact contextual status capsule.  History lives in the main dock.
    row2Frame = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_HUD_Row2", hudFrame, "BackdropTemplate"))
    row2Frame:SetSize(800, DockUI.inspectorH)
    DockUI.PixelLayoutRegion(row2Frame, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    row2Frame:SetBackdropColor(unpack(TH.r2Bg))
    row2Frame:SetBackdropBorderColor(unpack(TH.edge))
    ApplyHUDMaterial(row2Frame, "status")
    row2Frame:EnableMouse(true)

    DockUI.inspectorSelection = DockUI.PixelLayoutRegion(CreateFrame("Button", nil, row2Frame))
    DockUI.inspectorSelection:SetSize(DockUI.inspectorLabelW, BTN_H)
    local selectionBg = DockUI.PixelLayoutRegion(DockUI.inspectorSelection:CreateTexture(nil, "BACKGROUND"))
    selectionBg:SetAllPoints()
    selectionBg:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.055)
    local selectionHL = DockUI.PixelLayoutRegion(DockUI.inspectorSelection:CreateTexture(nil, "HIGHLIGHT"))
    selectionHL:SetAllPoints()
    selectionHL:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.10)
    DockUI.inspectorSelection:SetScript("OnClick", function() HUD.ToggleMenuPicker() end)
    SetTip(DockUI.inspectorSelection, "Choose which frame's settings page to open.")

    selectionFS = MakeFS(DockUI.inspectorSelection, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    selectionFS:SetPoint("LEFT", DockUI.inspectorSelection, "LEFT", 12, 0)
    selectionFS:SetPoint("RIGHT", DockUI.inspectorSelection, "RIGHT", -24, 0)
    selectionFS:SetJustifyH("LEFT")
    selectionFS:SetText("")

    local selectionChevron = MakeFS(DockUI.inspectorSelection, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.82)
    selectionChevron:SetPoint("RIGHT", DockUI.inspectorSelection, "RIGHT", -10, 1)
    selectionChevron:SetText("v")

    DockUI.inspectorMetrics = {}
    DockUI.inspectorMetricFS = {}
    for i, prefix in ipairs({ "X", "Y", "W", "H" }) do
        local cell = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, row2Frame))
        cell:SetSize(DockUI.inspectorMetricW, BTN_H)
        local divider = DockUI.PixelLayoutRegion(cell:CreateTexture(nil, "BORDER"))
        divider:SetSize(1, BTN_H - 8)
        divider:SetPoint("LEFT", cell, "LEFT", 0, 0)
        divider:SetColorTexture(TH.edge[1], TH.edge[2], TH.edge[3], 0.70)
        local valueFS = MakeFS(cell, "caption", TH.textR, TH.textG, TH.textB, 0.90)
        valueFS:SetPoint("CENTER")
        valueFS:SetText(prefix .. " --")
        cell._metricPrefix = prefix
        cell._valueFS = valueFS
        DockUI.inspectorMetrics[i] = cell
        DockUI.inspectorMetricFS[i] = valueFS
    end
    row2Frame._inspectorSelection = DockUI.inspectorSelection
    row2Frame._inspectorSelectionFS = selectionFS
    row2Frame._inspectorMetrics = DockUI.inspectorMetrics

    hintFS = MakeFS(row2Frame, "caption", TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
    hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -16, 0)
    hintFS:SetWidth(300)
    hintFS:SetJustifyH("RIGHT")
    hintFS:SetText("")
end

local function BuildHistoryRow()
    DockUI.historyContainer = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, hudFrame))
    DockUI.historyContainer:SetSize(1, BTN_H2)
    DockUI.row2 = {}

    local historyItems
    DockUI.historyCluster, historyItems = AddCluster(DockUI.row2, DockUI.historyContainer, nil, BTN_H2 + 4, false)
    undoBtn = AddRowButton(historyItems, DockUI.historyCluster, "", BTN_H, BTN_H2, "caption", function()
        if EM2.Undo and EM2.Undo.DoUndo then
            EM2.Undo.DoUndo()
        elseif _G.MSUF_EM_UndoUndo then
            _G.MSUF_EM_UndoUndo()
        end
        HUD.RefreshControls()
    end, "Undo the last MSUF change from Edit Mode or the in-game menu.")
    ExportPublic("MSUF_EditModeUndoBtn", undoBtn)
    AttachHistoryIcon(undoBtn, MEDIA .. "msuf_history_undo_red.png")

    redoBtn = AddRowButton(historyItems, DockUI.historyCluster, "", BTN_H, BTN_H2, "caption", function()
        if EM2.Undo and EM2.Undo.DoRedo then
            EM2.Undo.DoRedo()
        elseif _G.MSUF_EM_UndoRedo then
            _G.MSUF_EM_UndoRedo()
        end
        HUD.RefreshControls()
    end, "Redo the last MSUF change from Edit Mode or the in-game menu.")
    ExportPublic("MSUF_EditModeRedoBtn", redoBtn)
    AttachHistoryIcon(redoBtn, MEDIA .. "msuf_history_redo_green.png")
    FinishCluster(DockUI.historyCluster, historyItems, BTN_H2 + 4, 0)

    LayoutClusterRow(DockUI.historyContainer, DockUI.row2)
end

local function AttachDockHovers()
    AttachDockHover(hudFrame)
    AttachDockHover(row2Frame)
    AttachDockHover(DockUI.grip)
    AttachDockHover(DockUI.logo)
    AttachDockHover(DockUI.contextBtn)
    AttachDockHover(helpBtn)
    AttachDockHover(exitBtn)
    AttachDockHover(cancelAllBtn)
    AttachDockHover(DockUI.positionBtn)
    for _, cluster in ipairs(DockUI.row1) do
        AttachDockHover(cluster)
        for _, item in ipairs(cluster._dockItems or {}) do AttachDockHover(item) end
    end
    for _, cluster in ipairs(DockUI.row2) do
        AttachDockHover(cluster)
        for _, item in ipairs(cluster._dockItems or {}) do AttachDockHover(item) end
    end
end

local function EnsureHUD()
    if hudFrame then return false end
    RefreshHUDTheme()
    local db = _G.MSUF_DB
    local advancedHUD = db and db.general and db.general.hideAdvancedMenu == false
    DockUI.horizontalWidth = advancedHUD and 1480 or DOCK_HORIZONTAL_W

    BuildDockFrame()
    BuildDockHeader()
    BuildHelpButton()
    BuildExitControls()

    --- Center controls: grouped by task so the HUD scans as Preview | Layout | Tools.
    DockUI.primaryContainer = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, hudFrame))
    DockUI.primaryContainer:SetSize(1, CLUSTER_H)
    DockUI.row1 = {}

    BuildPreviewCluster(advancedHUD)
    BuildLayoutCluster()
    BuildToolsCluster()

    LayoutClusterRow(DockUI.primaryContainer, DockUI.row1)

    BuildInspectorRow()
    BuildHistoryRow()
    ApplyButtonRole(DockUI.positionBtn, "primary")
    AttachDockHovers()
    DockUI.layoutEvents = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_HUD_LayoutEvents"))
    DockUI.layoutEvents:SetScript("OnEvent", function()
        if hudFrame and hudFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            ApplyDockLayout()
            DockUI.ScheduleLayoutSettle()
        end
    end)
    DockUI.AttachToolbar(hudFrame, row2Frame, ApplyDockLayout)
    return true
end

local function SetLayoutEventsEnabled(enabled)
    local frame = DockUI.layoutEvents
    if not frame or frame._msufEnabled == (enabled == true) then return end
    frame._msufEnabled = enabled == true
    if enabled then
        frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        frame:RegisterEvent("UI_SCALE_CHANGED")
    else
        frame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        frame:UnregisterEvent("UI_SCALE_CHANGED")
    end
end

function HUD.RefreshUnitSelector()
    HUD.RefreshControls()
end

function HUD.RefreshControls(force)
    if not hudFrame or (not force and not hudFrame:IsShown()) then return end
    local key, component, slot = CurrentFocusSelection()
    local label, x, y, w, h = SelectionValues(key, component, slot)
    local text = DockUI.inspectorCompact and FormatSelectionSummary(label, x, y, w, h) or label
    if selectionLastText ~= text then
        selectionFS:SetText(text)
        selectionLastText = text
    end
    for i, fs in ipairs(DockUI.inspectorMetricFS or {}) do
        local value = i == 1 and x or (i == 2 and y or (i == 3 and w or h))
        local rendered = (DockUI.inspectorMetrics[i]._metricPrefix or "") .. " " .. (value == nil and "--" or tostring(value))
        if force or fs._msufValue ~= rendered then
            fs._msufValue = rendered
            fs:SetText(rendered)
        end
    end
    RefreshDockContext(key)
    --- Keep the open list's highlight on whatever is selected now, even when the
    --- selection changed through a mover click instead of the list itself.
    HUD.RefreshFramePicker()
    if hintFS then
        local now = GetTime and GetTime() or 0
        if InCombatLockdown and InCombatLockdown() then
            SetHint(HelpText("Combat locked"), TH.exitR, TH.exitG, TH.exitB, 0.95)
        elseif hudStatusText and hudStatusUntil and now <= hudStatusUntil then
            if hudStatusKind == "ok" then
                SetHint(hudStatusText, TH.okR, TH.okG, TH.okB, 0.95)
            elseif hudStatusKind == "warn" then
                SetHint(hudStatusText, TH.warnR, TH.warnG, TH.warnB, 0.95)
            else
                SetHint(hudStatusText, TH.onR, TH.onG, TH.onB, 0.95)
            end
        else
            hudStatusText, hudStatusKind, hudStatusUntil = nil, nil, nil
            SetHint(DefaultHintText(key ~= nil), TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
        end
    end
    if alphaFS and EM2.Grid then
        local value = floor(EM2.Grid.GetBgAlpha() * 100 + 0.5)
        if force or alphaFS._msufValue ~= value then
            alphaFS._msufValue = value
            alphaFS:SetText(string.format(HelpText("BG %d%%"), value))
        end
    end
    if stepFS and EM2.Grid then
        local enabled = not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()
        local value = floor(EM2.Grid.GetGridStep())
        if force or stepFS._msufValue ~= value then
            stepFS._msufValue = value
            stepFS:SetText(string.format(HelpText("Grid %dpx"), value))
        end
        if gridWidget._msufEnabled ~= enabled then
            gridWidget._msufEnabled = enabled
            if enabled then
                stepFS:SetTextColor(TH.okR, TH.okG, TH.okB, 0.95)
                if gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.okR, TH.okG, TH.okB, 0.18) end
            else
                stepFS:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 0.95)
                if gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.exitR, TH.exitG, TH.exitB, 0.20) end
            end
        end
    end
    if snapToggle and EM2.Snap then SetActive(snapToggle, EM2.Snap.IsEnabled()) end
    local selectedCfg = key and EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    local external = selectedCfg and selectedCfg.externalPublicElement == true and EM2.ExternalElements or nil
    SetControlEnabled(resetBtn, key and (UNIT_KEYS[key] == true or GROUP_KEY_TO_KIND[key] ~= nil
        or (external and external.CanReset and external.CanReset(key))))
    SetControlEnabled(settingsBtn, key ~= nil and (not external
        or (external.CanOpenSettings and external.CanOpenSettings(key))))
    if settingsBtn then
        settingsBtn._msufTipText = external
            and string.format(HelpText("%s settings"), selectedCfg.label or key)
            or "Choose which frame's settings page to open."
    end
    RegisterPreviewAnimationRefreshOwner()
    if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
    if previewAnimBtn then
        local active = MSUF.Require("MSUF_IsPreviewAnimationEnabled", CALLER)() == true
        SetActive(previewAnimBtn, active)
    end
    if cdmBtn then
        local db = _G.MSUF_DB
        local general = db and db.general
        local providerId, providerLabel = HUD.AutomaticCooldownProvider()
        local detected = providerId ~= nil
        local verticalDock = IsVerticalDock(EnsureDockState().dock)
        local providerAnchorText = detected
            and (verticalDock and providerLabel or string.format(HelpText("%s Anchor"), providerLabel))
            or HelpText("Cooldown")
        if force or cdmBtn._msufProviderAnchorText ~= providerAnchorText then
            cdmBtn._msufProviderAnchorText = providerAnchorText
            if cdmBtn._label and cdmBtn._label.SetText then cdmBtn._label:SetText(providerAnchorText) end
        end
        if force or cdmBtn._msufAutomaticProviderId ~= providerId then
            cdmBtn._msufAutomaticProviderId = providerId
            cdmBtn._msufTipText = detected
                and string.format(L["%s detected. Toggle the %s Anchor for all global Unitframes."], providerLabel, providerLabel)
                or L["Anchor all unitframes to the\nEssential Cooldown Manager."]
        end
        SetActive(cdmBtn, HUD.CooldownAnchorEnabled(general))
    end
    SetControlEnabled(anchorBtn, true)
    if auraBtn then
        local db = _G.MSUF_DB
        local a2 = db and db.auras3
        local sh = a2 and a2.shared
        SetActive(auraBtn, sh and sh.showInEditMode and _G.MSUF_UnitPreviewActive == true)
    end
    SetHistoryEnabled(undoBtn, EM2.Undo and EM2.Undo.CanUndo())
    SetHistoryEnabled(redoBtn, EM2.Undo and EM2.Undo.CanRedo())
    if DockUI.positionPopup and DockUI.positionPopup:IsShown() then RefreshPositionPopup() end
end

function HUD.Show()
    if InCombatLockdown and InCombatLockdown() then return false end
    EnsureHUD()
    --- Only a real entry animates.  The group-frame bridge wraps HUD.Show and
    --- calls it again while the toolbar is already on screen, which must not
    --- replay the slide.
    local entering = not hudFrame:IsShown()
    hudFrame:Show()
    if row2Frame then
        row2Frame:Show()
    end
    ApplyDockLayout()
    DockUI.ScheduleLayoutSettle()
    HUD.RefreshControls(true)
    SetLayoutEventsEnabled(true)
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Play() end
    SetDockExpanded(true)
    if entering then DockUI.ArmDockIntro() end
    if EnsureDockState().autoHide then ScheduleDockAutoHide() end
    return true
end

function HUD.Hide()
    if DockUI.tooltipRestoreLevel ~= nil then DockUI.ReleaseTooltip() end
    if DockUI.drag then StopDockDrag() end
    local cf = _G["MSUF_EM2_CancelConfirm"]
    if cf then
        cf:Hide()
    end
    SetLayoutEventsEnabled(false)
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Stop() end
    if row2Frame then
        row2Frame:Hide()
    end
    if hudFrame then
        hudFrame:Hide()
    end
    --- After the Hide: the slide gives back the anchor and clamping without
    --- reviving alpha or auto-hide work for a toolbar that just left.
    DockUI.StopDockIntro()
    if DockUI.positionPopup then DockUI.positionPopup:Hide() end
    HUD.CloseFramePicker()
    DockUI.CancelAutoHide()
end

function HUD.IsShown() return hudFrame and hudFrame:IsShown() or false end

local function MSUF_EM2_SetHUDStatus(text, kind, seconds)
    return HUD.SetStatus(text, kind, seconds)
end
ExportPublic("MSUF_EM2_SetHUDStatus", MSUF_EM2_SetHUDStatus)
