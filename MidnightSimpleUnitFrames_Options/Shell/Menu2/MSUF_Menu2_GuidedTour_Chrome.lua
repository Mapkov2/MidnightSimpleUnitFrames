-- Guided tour chrome layout, rendering and native interactions.
local _, MSUF = ...
local Parts = MSUF.GuidedTourParts
local ActiveStagePosition = Parts.ActiveStagePosition
local AdvanceCurrent = Parts.AdvanceCurrent
local AllStageControls = Parts.AllStageControls
local BackCurrent = Parts.BackCurrent
local BlockedByCombat = Parts.BlockedByCombat
local C_Timer = Parts.C_Timer
local ClearSectionEmphasis = Parts.ClearSectionEmphasis
local ControlIsAction = Parts.ControlIsAction
local CooldownAnchorDecision = Parts.CooldownAnchorDecision
local CooldownAnchorDecisionComplete = Parts.CooldownAnchorDecisionComplete
local CreateFrame = Parts.CreateFrame
local CurrentControlTouched = Parts.CurrentControlTouched
local CurrentPosition = Parts.CurrentPosition
local CurrentStage = Parts.CurrentStage
local EditDone = Parts.EditDone
local EditModeStatus = Parts.EditModeStatus
local EmphasizeControl = Parts.EmphasizeControl
local EmphasizeSection = Parts.EmphasizeSection
local ExpectedPage = Parts.ExpectedPage
local FocusCurrentSection = Parts.FocusCurrentSection
local FocusGuidedWidget = Parts.FocusGuidedWidget
local Gfx = Parts.Gfx
local KeepLabel = Parts.KeepLabel
local M = Parts.M
local OpenGuidedEditModePopup = Parts.OpenGuidedEditModePopup
local PauseTour = Parts.PauseTour
local PersonalizedTitle = Parts.PersonalizedTitle
local PixelLayoutRegion = Parts.PixelLayoutRegion
local ProfileMismatch = Parts.ProfileMismatch
local ReconcileGuidedEditModePopup = Parts.ReconcileGuidedEditModePopup
local RefreshEditModeOpenCue = Parts.RefreshEditModeOpenCue
local RefreshEditModePlacementCue = Parts.RefreshEditModePlacementCue
local Runtime = Parts.Runtime
local RuntimeControlRecords = Parts.RuntimeControlRecords
local SelectExpectedPage = Parts.SelectExpectedPage
local SelectedSetupArea = Parts.SelectedSetupArea
local SelectedSetupMode = Parts.SelectedSetupMode
local SetupAreaDecisionComplete = Parts.SetupAreaDecisionComplete
local ShouldShowEditModeOpenCue = Parts.ShouldShowEditModeOpenCue
local SkipCurrent = Parts.SkipCurrent
local StageCue = Parts.StageCue
local StageSectionControls = Parts.StageSectionControls
local TourExperience = Parts.TourExperience
local TourIsActive = Parts.TourIsActive
local Tr = Parts.Tr
local ceil = Parts.ceil
local floor = Parts.floor
local format = Parts.format
local max = Parts.max
local min = Parts.min
local EnsureGuidedTourChrome
local function SetButtonEnabled(button, enabled)
    if not button then return end
    button._msuf2GuidedEnabled = enabled and true or false
    if type(button.SetEnabled) == "function" then button:SetEnabled(enabled and true or false) end
    if type(button.SetAlpha) == "function" then button:SetAlpha(enabled and 1 or 0.42) end
end

local function SetButtonText(button, text)
    if button and type(button.SetText) == "function" then button:SetText(Tr(text), true) end
    if button and M.Theme and type(M.Theme.CenterButtonLabel) == "function" then M.Theme.CenterButtonLabel(button) end
end

local function SetFontColor(fontString, color)
    if fontString and color and type(fontString.SetTextColor) == "function" then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function SetStageIcon(chrome, stage)
    local T = M.Theme
    local icon = chrome and chrome.icon
    if not (T and icon) then return end
    Gfx.NavIcon(icon, T, stage.icon)
end

local function AnchorTourScroll(chrome, active)
    if not (chrome and chrome.scroll and chrome.host and chrome.status) then return end
    local scroll = chrome.scroll
    local topOwner = chrome.status
    if active then topOwner = chrome end
    if type(M.LayoutPageHeaderHost) == "function" then
        M.LayoutPageHeaderHost(topOwner, chrome.host)
    elseif scroll._msuf2TourAnchorOwner ~= topOwner or scroll._msuf2TourAnchorHost ~= chrome.host then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", chrome.host, "BOTTOMRIGHT", -24, 0)
        scroll._msuf2TourAnchorOwner = topOwner
        scroll._msuf2TourAnchorHost = chrome.host
    end
    scroll._msuf2MaxScroll = nil
    scroll._msuf2SmoothScrollTarget = nil
    if type(scroll._msuf2RefreshScrollBar) == "function" then scroll:_msuf2RefreshScrollBar() end
end

local function LayoutChrome(chrome, warning, helpText)
    local hostWidth = max(420, tonumber(chrome.host and chrome.host:GetWidth()) or 760)
    local compact = hostWidth < 700
    local baseHeight = compact and (warning and 234 or 196) or (warning and 164 or 132)
    local charsPerLine = max(36, floor((hostWidth - 28) / 6.2))
    local estimatedLines = min(9, max(1, ceil(#tostring(helpText or "") / charsPerLine)))
    local includedLines = compact and (warning and 5 or 3) or (warning and 3 or 2)
    local height = baseHeight + (max(0, estimatedLines - includedLines) * 13)
    chrome:SetHeight(height)
    chrome._msuf2Compact = compact

    chrome.iconWell:ClearAllPoints()
    chrome.iconWell:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, -12)
    chrome.iconWell:SetSize(36, 36)
    chrome.title:ClearAllPoints()
    chrome.title:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -12)
    chrome.title:SetPoint("RIGHT", chrome.step, "LEFT", -12, 0)
    chrome.step:ClearAllPoints()
    chrome.step:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -16)
    chrome.step:SetWidth(compact and 118 or 166)
    chrome.section:ClearAllPoints()
    chrome.section:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -32)
    chrome.section:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -32)
    chrome.cueArrow:ClearAllPoints()
    chrome.cueArrow:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, compact and -64 or -56)
    chrome.help:ClearAllPoints()
    chrome.help:SetPoint("TOPLEFT", chrome, "TOPLEFT", 36, compact and -60 or -52)
    chrome.help:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 88 or 60)
    chrome.help:SetWidth(hostWidth - 48)
    chrome.progress:ClearAllPoints()
    chrome.progress:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, compact and 76 or 44)
    chrome.progress:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 76 or 44)
    chrome.progress:SetHeight(4)

    local buttons = { chrome.back, chrome.keep, chrome.skip, chrome.next, chrome.pause }
    local minimums = compact and { 48, 72, 58, 60, 54 } or { 58, 82, 68, 72, 64 }
    local maximums = compact and { 112, 126, 138, 112, 96 } or { 126, 146, 158, 126, 108 }
    local widths = {}
    for i = 1, #buttons do
        local preferred = minimums[i]
        local fontString = buttons[i]._msuf2Label
            or (type(buttons[i].GetFontString) == "function" and buttons[i]:GetFontString() or nil)
        if fontString and type(fontString.GetStringWidth) == "function" then
            local textWidth = fontString:GetStringWidth()
            if tonumber(textWidth) then
                minimums[i] = max(minimums[i], ceil(textWidth + 8))
                preferred = ceil(textWidth + 22)
                maximums[i] = max(maximums[i], minimums[i])
            end
        end
        widths[i] = min(max(preferred, minimums[i]), maximums[i])
    end
    local gap = compact and 5 or 7
    local function FitRow(indices)
        local available = hostWidth - 20 - (gap * (#indices - 1))
        local widthTotal, flexible = 0, 0
        for i = 1, #indices do
            local index = indices[i]
            widthTotal = widthTotal + widths[index]
            flexible = flexible + max(0, widths[index] - minimums[index])
        end
        if widthTotal <= available or flexible <= 0 then return end
        local overflow = widthTotal - available
        for i = 1, #indices do
            local index = indices[i]
            local room = max(0, widths[index] - minimums[index])
            local reduction = min(room, floor((overflow * room / flexible) + 0.5))
            widths[index] = widths[index] - reduction
        end
        widthTotal = 0
        for i = 1, #indices do widthTotal = widthTotal + widths[indices[i]] end
        local remainder = max(0, widthTotal - available)
        while remainder > 0 do
            local changed = false
            for i = #indices, 1, -1 do
                local index = indices[i]
                if widths[index] > minimums[index] and remainder > 0 then
                    widths[index] = widths[index] - 1
                    remainder = remainder - 1
                    changed = true
                end
            end
            if not changed then break end
        end
    end
    local function PlaceRow(indices, bottom)
        FitRow(indices)
        local total = gap * (#indices - 1)
        for i = 1, #indices do total = total + widths[indices[i]] end
        local x = max(10, floor((hostWidth - total) / 2))
        for i = 1, #indices do
            local index = indices[i]
            local button = buttons[index]
            button:ClearAllPoints()
            button:SetSize(widths[index], 24)
            button:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", x, bottom)
            x = x + widths[index] + gap
        end
    end
    if compact then
        PlaceRow({ 1, 2, 3 }, 39)
        PlaceRow({ 4, 5 }, 10)
    else
        PlaceRow({ 1, 2, 3, 4, 5 }, 10)
    end
    AnchorTourScroll(chrome, true)
end

local function ProgressFraction(stage, position)
    local within = 0
    if not stage.special and position.control and #position.sections > 0 then
        local total, completed = 0, 0
        local records = RuntimeControlRecords()
        for i = 1, #position.sections do
            local controls = StageSectionControls(stage, position.sections[i], position.sections, records)
            total = total + #controls
            if i < position.index then
                completed = completed + #controls
            elseif i == position.index and position.control then
                completed = completed + max(0, position.controlIndex - 1)
            end
        end
        within = min(max(completed / max(1, total), 0), 0.99)
    elseif stage.id == "final_review" then
        within = 1
    end
    local current, total = ActiveStagePosition(stage)
    return min(max(((current - 1) + within) / max(1, total), 0), 1)
end

local function PlayChromeTransition(chrome, signature, reason)
    if Runtime.lastVisualSignature == signature or reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    Runtime.lastVisualSignature = signature
    local T = M.Theme
    if not (T and type(T.PlayMotion) == "function") then return end
    T.PlayMotion(chrome.iconWell, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.18 })
    T.PlayMotion(chrome.title, "controlFocusIn", { fromAlpha = 0.38, toAlpha = 1, duration = 0.16 })
    T.PlayMotion(chrome.help, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.20 })
    T.PlayMotion(chrome.progressFill, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.22 })
end

local function StopChromeTransition(chrome)
    local T = M.Theme
    if not (chrome and T and type(T.StopMotion) == "function") then return end
    local regions = { chrome.iconWell, chrome.title, chrome.help, chrome.progressFill }
    for i = 1, #regions do T.StopMotion(regions[i]) end
end

local function RegisterSpecialClickTargets(stageId, key, widgets)
    local targets = Runtime.specialClickTargets
    if type(targets) ~= "table" or targets.stageId ~= stageId then
        targets = { stageId = stageId, groups = {} }
        Runtime.specialClickTargets = targets
    end
    targets.groups[key] = type(widgets) == "table" and widgets or {}
end

local function FlashGuidedClickTargets(chrome, stage, position, context, reason)
    if reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    local T = M.Theme
    if not (T and type(T.PlayNeonFlash) == "function") then return end
    context = context or {}
    local editStatus = (stage.id == "edit_mode" or stage.id == "group_edit_mode") and EditModeStatus() or {}
    local signature = table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
        context.profileMismatch and "profile" or "profile-ok",
        context.manualAway and "away" or "here",
        context.warning and tostring(context.warning.signature or "warning") or "normal",
        tostring(SelectedSetupArea() or ""),
        tostring(SelectedSetupMode()),
        tostring(CooldownAnchorDecision() or ""),
        EditDone.placement() and "placed" or "unplaced",
        EditDone.groupPlacement() and "group-placed" or "group-unplaced",
        editStatus.active and "edit-on" or "edit-off",
    }, "\031")
    if Runtime.lastClickCueSignature == signature then return end
    Runtime.lastClickCueSignature = signature

    local widgets, seen = {}, {}
    local function Add(widget)
        if widget and not seen[widget] then
            seen[widget] = true
            widgets[#widgets + 1] = widget
        end
    end
    local function AddGroup(key)
        local targets = Runtime.specialClickTargets
        local group = targets and targets.stageId == stage.id and targets.groups and targets.groups[key]
        for i = 1, #(group or {}) do Add(group[i]) end
    end

    if context.profileMismatch then
        Add(chrome.back)
    elseif context.manualAway then
        Add(chrome.next)
    elseif context.warning then
        Add(chrome.skip)
    elseif stage.id == "menu_basics" then
        if not SetupAreaDecisionComplete() then
            AddGroup("setupArea")
        else
            Add(chrome.next)
        end
    elseif stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then
            AddGroup("anchor")
        elseif EditDone.placement() then
            Add(chrome.next)
        elseif editStatus.active ~= true then
            AddGroup("edit_mode_toggle")
            Add(M.dashboardToolbarEditModeButton)
        end
    elseif stage.id == "group_edit_mode" then
        if EditDone.groupPlacement() then
            Add(chrome.next)
        elseif editStatus.active ~= true then
            AddGroup("group_edit_mode_toggle")
            Add(M.dashboardToolbarEditModeButton)
        end
    elseif stage.id == "final_review" or not position.control then
        Add(chrome.next)
    end

    for i = 1, #widgets do
        local widget = widgets[i]
        T.PlayNeonFlash(widget, "success", { alpha = 0.28, duration = 0.82 })
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(widget, "controlFocusIn", { fromAlpha = 0.52, toAlpha = 1, duration = 0.18 })
        end
    end
end

--- The chrome's title and section line for the current stage and position.
local function PaintChromeHeadings(chrome, stage, position, profileMismatch, manualAway, tourProfile, activeProfile)
    if profileMismatch then
        M.Theme.SetTranslatedText(chrome.title, Tr("Active profile changed"))
        M.Theme.SetTranslatedText(chrome.section, format(Tr("Tour profile: %s - Active profile: %s"), tourProfile, activeProfile))
    elseif manualAway then
        M.Theme.SetTranslatedText(chrome.title, format(Tr("Tour paused - %s"), PersonalizedTitle(stage)))
        M.Theme.SetTranslatedText(chrome.section, Tr("Progress is saved while you use another page."))
    else
        chrome.title:SetText(PersonalizedTitle(stage))
        if stage.special then
            local labels = {
                menu_basics = "QUICK START",
                unit_intro = "PART 1 - UNITFRAMES",
                edit_mode = "MOVE VS SIZE",
                group_intro = "PART 2 - GROUP FRAMES",
                group_edit_mode = "MOVE VS SIZE",
                class_intro = "PART 3 - CLASS RESOURCES",
                power_moves = "MSUF POWER MOVES",
                final_review = "READY TO PLAY",
            }
            M.Theme.SetTranslatedText(chrome.section, Tr(labels[stage.id] or "GUIDED SETUP"))
        elseif position.overview then
            local controls = AllStageControls(stage, position.sections)
            M.Theme.SetTranslatedText(chrome.section, format(Tr("MISSION BRIEF - %d checkpoints - %d settings"), #position.sections, #controls))
        elseif position.control then
            local template = ControlIsAction(position.control) and Tr("CHECKPOINT %d/%d - ACTION %d/%d - %s")
                or Tr("CHECKPOINT %d/%d - SETTING %d/%d - %s")
            M.Theme.SetTranslatedText(chrome.section, format(template, position.index, #position.sections,
                position.controlIndex, #position.controls, Tr(position.control.label)))
        elseif position.section then
            M.Theme.SetTranslatedText(chrome.section, format(Tr("CHECKPOINT %d/%d - %s - %d settings"), position.index, #position.sections,
                Tr(position.section.label), #position.controls))
        end
    end
end

local function PaintChromeButtons(chrome, stage, position, touched, stagePosition, state, displayHelp)
    local profileMismatch, manualAway, warning = state.profileMismatch, state.manualAway, state.warning
    local alert = profileMismatch or warning
    -- Button texts and states. What the Edit Mode stages still wait for before
    -- Keep and Next unlock (the cooldown anchor choice, the Player move and the
    -- Party move) is read once here and serves both.
    local final = stage.id == "final_review"
    local waitingForAnchorDecision = stage.id == "edit_mode" and not CooldownAnchorDecisionComplete()
    local waitingForEditModeMove = stage.id == "edit_mode" and not waitingForAnchorDecision and not EditDone.placement()
    local waitingForGroupMove = stage.id == "group_edit_mode" and not EditDone.groupPlacement()
    SetButtonText(chrome.back, profileMismatch and "Restart tour" or (warning and "Cancel" or "Back"))
    SetButtonText(chrome.keep, KeepLabel(stage, position))
    SetButtonText(chrome.skip, warning and "Confirm skip" or "Skip")
    local nextLabel = "Next setting"
    if manualAway then nextLabel = "Return"
    elseif final then nextLabel = "Finish setup"
    elseif waitingForEditModeMove then nextLabel = EditDone.movement() and "Open size popup" or "Move Player first"
    elseif waitingForGroupMove then nextLabel = EditDone.groupMovement() and "Open size popup" or "Move Party first"
    elseif touched then nextLabel = "Claim +10 XP"
    elseif stage.id == "menu_basics" then nextLabel = SelectedSetupMode() == "quick" and "Start Quick Setup" or "Start Complete Tour"
    elseif stage.id == "edit_mode" then nextLabel = "Claim checkpoint"
    elseif stage.id == "power_moves" then nextLabel = "Continue"
    elseif position.control then nextLabel = "Change it first"
    end
    SetButtonText(chrome.next, nextLabel)
    SetButtonText(chrome.pause, "Pause")
    LayoutChrome(chrome, alert ~= nil and alert ~= false, displayHelp)
    local backOn, keepOn, skipOn, nextOn
    if profileMismatch then
        backOn, keepOn, skipOn, nextOn = true, false, false, false
    elseif manualAway then
        backOn, keepOn, skipOn, nextOn = false, false, false, true
    elseif warning then
        backOn, keepOn, skipOn, nextOn = true, false, true, false
    else
        local editPopupActionReady = waitingForEditModeMove and EditDone.movement()
        local groupPopupActionReady = waitingForGroupMove and EditDone.groupMovement()
        local changeReady = stage.special or not position.control or touched
        backOn = not (stagePosition == 1 and stage.special)
        keepOn = not final and stage.id ~= "menu_basics" and not waitingForAnchorDecision and not waitingForEditModeMove and not waitingForGroupMove
        skipOn = not final
        nextOn = changeReady
            and (stage.id ~= "menu_basics" or SetupAreaDecisionComplete())
            and not waitingForAnchorDecision
            and (not waitingForEditModeMove or editPopupActionReady)
            and (not waitingForGroupMove or groupPopupActionReady)
    end
    SetButtonEnabled(chrome.back, backOn)
    SetButtonEnabled(chrome.keep, keepOn)
    SetButtonEnabled(chrome.skip, skipOn)
    SetButtonEnabled(chrome.next, nextOn)
    SetButtonEnabled(chrome.pause, true)
end

function M.RefreshGuidedTourChrome(reason)
    local chrome = Runtime.chrome
    if not chrome then return false end
    if not TourIsActive() then
        if Runtime.tourVisualsDirty ~= true then return false end
        Runtime.warning = nil
        Runtime.manualAway = nil
        Runtime.lastVisualSignature = nil
        Runtime.lastClickCueSignature = nil
        ClearSectionEmphasis()
        StopChromeTransition(chrome)
        chrome:Hide()
        RefreshEditModeOpenCue(false)
        AnchorTourScroll(chrome, false)
        Runtime.tourVisualsDirty = nil
        return false
    end
    Runtime.tourVisualsDirty = true

    local stage = CurrentStage()
    local reconciledPopup = ReconcileGuidedEditModePopup(stage)
    if reconciledPopup and M.activeKey == "guided_setup" and not Runtime.popupReconcileRefreshQueued then
        Runtime.popupReconcileRefreshQueued = true
        C_Timer.After(0, function()
            Runtime.popupReconcileRefreshQueued = nil
            M.RequestRefresh(nil, "GUIDED_POPUP_RECONCILED")
        end)
    end
    local profileMismatch, tourProfile, activeProfile = ProfileMismatch()
    if profileMismatch then
        Runtime.warning = nil
        Runtime.manualAway = nil
    end
    local expected = ExpectedPage(stage)
    local position = CurrentPosition(stage)
    local touched = CurrentControlTouched(stage, position)
    local currentPage = M.activeKey
    if currentPage and currentPage ~= expected then Runtime.manualAway = true end
    local manualAway = Runtime.manualAway == true and currentPage ~= expected
    local warning = Runtime.warning
    if position.cursorNormalized and not profileMismatch and not manualAway then
        FocusCurrentSection(stage)
    end
    local showEditModeOpenCue = not profileMismatch
        and not manualAway
        and not warning
        and ShouldShowEditModeOpenCue()
    local displayHelp = profileMismatch
        and format(Tr("This tour belongs to profile %s. You are now editing %s. Restart the tour here or switch back to continue safely."),
            tourProfile, activeProfile)
        or manualAway and Tr("Return to the guided page when you are ready to continue.")
        or warning and warning.text
        or StageCue(stage, position, touched)
    if profileMismatch or manualAway then
        ClearSectionEmphasis()
    elseif stage.special or position.overview then
        ClearSectionEmphasis(stage.pageKey)
    elseif position.section then
        EmphasizeSection(stage.pageKey, position.section, position.control)
        EmphasizeControl(stage, position.section, position.controls, position.control)
    end
    SetStageIcon(chrome, stage)
    local stagePosition, stageTotal = ActiveStagePosition(stage)
    M.Theme.SetTranslatedText(chrome.step, format(Tr("MISSION %d/%d - %d XP"), stagePosition, stageTotal, TourExperience()))

    PaintChromeHeadings(chrome, stage, position, profileMismatch, manualAway, tourProfile, activeProfile)
    chrome.help:SetText(displayHelp)
    local alert = profileMismatch or warning
    local controlCue = not alert and not stage.special and position.control ~= nil
    local guidedGreen = M.Theme.colors.ok or { 0.24, 0.88, 0.40, 1 }
    SetFontColor(chrome.help, alert and (M.Theme.colors.warning or M.Theme.colors.warn)
        or controlCue and guidedGreen
        or M.Theme.colors.muted)
    local cueColor = alert and (M.Theme.colors.warning or M.Theme.colors.warn)
        or controlCue and guidedGreen
        or M.Theme.colors.accent
    if cueColor then chrome.cueArrow:SetVertexColor(cueColor[1], cueColor[2], cueColor[3], 1) end

    local fraction = ProgressFraction(stage, position)
    chrome.progressFill:SetWidth(max(1, floor(((chrome.progress:GetWidth() or 1) - 2) * fraction)))

    local state = { profileMismatch = profileMismatch, manualAway = manualAway, warning = warning }
    PaintChromeButtons(chrome, stage, position, touched, stagePosition, state, displayHelp)
    chrome:Show()
    if (reason == "HOST_SIZE" or reason == "WINDOW_RESIZE")
        and not profileMismatch and not manualAway
        and not stage.special and not position.overview and position.section
    then
        FocusGuidedWidget(position.control and position.control.widget, position.section.outer, false)
    end
    local signature = table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
        profileMismatch and "profile" or (warning and "warning" or "normal"),
        manualAway and "away" or "guided",
    }, "\031")
    PlayChromeTransition(chrome, signature, reason)
    RefreshEditModeOpenCue(showEditModeOpenCue)
    RefreshEditModePlacementCue()
    FlashGuidedClickTargets(chrome, stage, position, state, reason)
    return true
end

local function ChromeButton(parent, T, label, handler)
    local button = T.Button(parent, label, 70, 24)
    button._msuf2SkipHistoryCheckpoint = true
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    button:SetScript("OnClick", function(self)
        if self._msuf2GuidedEnabled == false or BlockedByCombat() then return end
        handler()
    end)
    return button
end

local function RegisterChromeControl(button, suffix, label, help)
    M.RegisterMenuChromeControl(button, "guided-tour." .. suffix, Tr(label), "action", {
        actionKey = "guided_setup_step",
        actionFixedArgs = { step = suffix },
        historyMode = "none",
        help = Tr(help),
    })
end

function M.RunGuidedTourStep(step)
    step = tostring(step or ""):lower()
    if BlockedByCombat() or not TourIsActive() then return false, "guided_setup_inactive" end
    local stage = CurrentStage()
    ReconcileGuidedEditModePopup(stage)
    if step == "next" and stage.id == "menu_basics" and not SetupAreaDecisionComplete() then
        return false, "guided_setup_area_required"
    end
    if (step == "keep" or step == "next") and stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then return false, "guided_edit_mode_anchor_required" end
        if not EditDone.placement() then
            if step == "next" and EditDone.movement() and OpenGuidedEditModePopup("player", stage) then
                return true, "guided_edit_mode_popup_opened"
            end
            return false, "guided_edit_mode_move_required"
        end
    end
    if (step == "keep" or step == "next") and stage.id == "group_edit_mode"
        and not EditDone.groupPlacement()
    then
        if step == "next" and EditDone.groupMovement() and OpenGuidedEditModePopup("gf_party", stage) then
            return true, "guided_group_edit_mode_popup_opened"
        end
        return false, "guided_group_edit_mode_move_required"
    end
    if step == "next" and not Runtime.manualAway and not Runtime.warning
        and not select(1, ProfileMismatch()) and not stage.special
    then
        local position = CurrentPosition(stage)
        if position.control and not CurrentControlTouched(stage, position) then
            return false, "guided_setting_change_required"
        end
    end
    if step == "back" then
        BackCurrent()
    elseif step == "keep" then
        AdvanceCurrent("kept")
    elseif step == "skip" then
        local skipped = SkipCurrent()
        if skipped and Runtime.warning then
            return true, "confirmation_needed", Runtime.warning.text
        end
    elseif step == "next" then
        if Runtime.manualAway then
            Runtime.manualAway = nil
            SelectExpectedPage(CurrentStage())
        else
            AdvanceCurrent("reviewed")
        end
    elseif step == "pause" then
        PauseTour()
    else
        return false, "unknown_guided_setup_step"
    end
    return true, step
end

function M.InstallGuidedTourChrome(frame, status, host, scroll)
    Runtime.chromeFrame = frame or Runtime.chromeFrame
    Runtime.chromeStatus = status or Runtime.chromeStatus
    Runtime.chromeHost = host or Runtime.chromeHost
    Runtime.chromeScroll = scroll or Runtime.chromeScroll
    if Runtime.chrome then
        Runtime.chrome.frame = Runtime.chromeFrame or Runtime.chrome.frame
        Runtime.chrome.status = Runtime.chromeStatus or Runtime.chrome.status
        Runtime.chrome.host = Runtime.chromeHost or Runtime.chrome.host
        Runtime.chrome.scroll = Runtime.chromeScroll or Runtime.chrome.scroll
        M.RefreshGuidedTourChrome("REINSTALL")
        return Runtime.chrome
    end
    if not TourIsActive() then return nil end
    frame, status, host, scroll = Runtime.chromeFrame, Runtime.chromeStatus, Runtime.chromeHost, Runtime.chromeScroll
    local T = M.Theme
    if not (frame and status and host and scroll and T and type(T.Panel) == "function" and type(T.Font) == "function" and type(T.Button) == "function") then
        return nil
    end

    local chrome = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(chrome, "status") end
    chrome:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    chrome:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, 0)
    chrome:SetHeight(132)
    if type(chrome.SetFrameLevel) == "function" then chrome:SetFrameLevel((host:GetFrameLevel() or 1) + 5) end
    chrome.frame, chrome.status, chrome.host, chrome.scroll = frame, status, host, scroll

    local divider = PixelLayoutRegion(chrome:CreateTexture(nil, "ARTWORK", nil, 3))
    divider:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, 0)
    divider:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)

    local iconWell = T.Panel(chrome, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(iconWell, "card") end
    local icon = PixelLayoutRegion(iconWell:CreateTexture(nil, "ARTWORK", nil, 2))
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", iconWell, "CENTER", 0, 0)
    chrome.iconWell, chrome.icon = iconWell, icon

    chrome.title = T.Font(chrome, "GameFontNormal", "", T.colors.text)
    chrome.title:SetJustifyH("LEFT")
    chrome.step = T.Font(chrome, "GameFontDisableSmall", "", T.colors.accent)
    chrome.step:SetJustifyH("RIGHT")
    chrome.section = T.Font(chrome, "GameFontDisableSmall", "", T.colors.muted)
    chrome.section:SetJustifyH("LEFT")
    local cueArrow = PixelLayoutRegion(chrome:CreateTexture(nil, "OVERLAY", nil, 4))
    local cueAtlas = false
    if cueArrow.SetAtlas then
        cueArrow:SetAtlas("NPE_ArrowRight", false)
        cueAtlas = true
    end
    if not cueAtlas then cueArrow:SetTexture(T.media.collapseArrow) end
    cueArrow:SetSize(16, 16)
    cueArrow:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    chrome.cueArrow = cueArrow
    chrome.help = T.Font(chrome, "GameFontHighlightSmall", "", T.colors.muted)
    chrome.help:SetJustifyH("LEFT")
    if chrome.help.SetWordWrap then chrome.help:SetWordWrap(true) end
    if chrome.help.SetNonSpaceWrap then chrome.help:SetNonSpaceWrap(true) end

    local progress = PixelLayoutRegion(CreateFrame("Frame", nil, chrome))
    local progressBg = PixelLayoutRegion(progress:CreateTexture(nil, "BACKGROUND"))
    progressBg:SetAllPoints()
    local track = T.colors.coreShadow or T.colors.bg
    progressBg:SetColorTexture(track[1], track[2], track[3], 0.92)
    local progressFill = PixelLayoutRegion(progress:CreateTexture(nil, "ARTWORK"))
    progressFill:SetPoint("TOPLEFT", progress, "TOPLEFT", 1, -1)
    progressFill:SetPoint("BOTTOMLEFT", progress, "BOTTOMLEFT", 1, 1)
    progressFill:SetWidth(1)
    progressFill:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
    chrome.progress, chrome.progressFill = progress, progressFill

    chrome.back = ChromeButton(chrome, T, "Back", function() M.RunGuidedTourStep("back") end)
    chrome.keep = ChromeButton(chrome, T, "Keep current", function() M.RunGuidedTourStep("keep") end)
    chrome.skip = ChromeButton(chrome, T, "Skip", function() M.RunGuidedTourStep("skip") end)
    chrome.next = ChromeButton(chrome, T, "Next", function() M.RunGuidedTourStep("next") end)
    chrome.pause = ChromeButton(chrome, T, "Pause", function() M.RunGuidedTourStep("pause") end)
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(chrome.next) end

    RegisterChromeControl(chrome.back, "back", "Guided setup: Back", "Returns to the previous highlighted setting or mission.")
    RegisterChromeControl(chrome.keep, "keep", "Guided setup: Keep unchanged", "Keeps the highlighted setting unchanged and moves to the next green target.")
    RegisterChromeControl(chrome.skip, "skip", "Guided setup: Skip", "Shows an inline impact warning before skipping.")
    RegisterChromeControl(chrome.next, "next", "Guided setup: Next", "Unlocks after the highlighted setting changes, then marks the next setting in green.")
    RegisterChromeControl(chrome.pause, "pause", "Guided setup: Pause", "Closes the menu while preserving guided setup progress.")

    Runtime.chrome = chrome
    chrome:Hide()
    if type(host.HookScript) == "function" and not host._msuf2GuidedTourSizeHook then
        host._msuf2GuidedTourSizeHook = true
        host:HookScript("OnSizeChanged", function()
            if TourIsActive() then M.RefreshGuidedTourChrome("HOST_SIZE") end
        end)
    end
    if type(frame.HookScript) == "function" and not frame._msuf2GuidedTourHideHook then
        frame._msuf2GuidedTourHideHook = true
        frame:HookScript("OnHide", function()
            ClearSectionEmphasis()
            StopChromeTransition(chrome)
        end)
    end
    M.RefreshGuidedTourChrome("INSTALL")
    return chrome
end

EnsureGuidedTourChrome = function()
    if Runtime.chrome then return Runtime.chrome end
    if not TourIsActive() then return nil end
    if not (Runtime.chromeFrame and Runtime.chromeStatus and Runtime.chromeHost and Runtime.chromeScroll) then return nil end
    return M.InstallGuidedTourChrome(
        Runtime.chromeFrame, Runtime.chromeStatus, Runtime.chromeHost, Runtime.chromeScroll)
end

function M.GuidedTourOnPageSelected(pageKey)
    if not TourIsActive() then
        if Runtime.tourVisualsDirty == true then M.RefreshGuidedTourChrome("PAGE_INACTIVE") end
        return false
    end
    EnsureGuidedTourChrome()
    local stage = CurrentStage()
    local expected = ExpectedPage(stage)
    if tostring(pageKey or "") ~= expected then
        Runtime.manualAway = true
        Runtime.warning = nil
        ClearSectionEmphasis()
        M.RefreshGuidedTourChrome("MANUAL_PAGE")
        return false
    end
    Runtime.manualAway = nil
    if not stage.special then
        CurrentPosition(stage) -- migrate old overview/section cursors to a real control first
        FocusCurrentSection(stage)
    end
    M.RefreshGuidedTourChrome("GUIDED_PAGE")
    return true
end


Parts.EnsureGuidedTourChrome = EnsureGuidedTourChrome
Parts.RegisterSpecialClickTargets = RegisterSpecialClickTargets
Parts.SetButtonEnabled = SetButtonEnabled
Parts.SetButtonText = SetButtonText
Parts.SetFontColor = SetFontColor
