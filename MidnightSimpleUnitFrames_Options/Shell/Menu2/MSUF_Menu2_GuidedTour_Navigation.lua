-- Guided tour progress, cursor navigation and lifecycle.
local _, MSUF = ...
local Parts = MSUF.GuidedTourParts
local ActiveProfileName = Parts.ActiveProfileName
local ActiveStagePosition = Parts.ActiveStagePosition
local ActiveStages = Parts.ActiveStages
local AllStageControls = Parts.AllStageControls
local BlockedByCombat = Parts.BlockedByCombat
local C_Timer = Parts.C_Timer
local ClearSectionEmphasis = Parts.ClearSectionEmphasis
local ControlIsAction = Parts.ControlIsAction
local CurrentStage = Parts.CurrentStage
local EmphasizeControl = Parts.EmphasizeControl
local EmphasizeSection = Parts.EmphasizeSection
local ExpectedPage = Parts.ExpectedPage
local FirstLoad = Parts.FirstLoad
local Invoke = Parts.Invoke
local IsWidgetInside = Parts.IsWidgetInside
local M = Parts.M
local ProfileMismatch = Parts.ProfileMismatch
local Runtime = Parts.Runtime
local RuntimeControlRecords = Parts.RuntimeControlRecords
local STAGES = Parts.STAGES
local STAGE_BY_ID = Parts.STAGE_BY_ID
local StageSectionControls = Parts.StageSectionControls
local StageSections = Parts.StageSections
local Tour = Parts.Tour
local TourIsActive = Parts.TourIsActive
local TourState = Parts.TourState
local Tr = Parts.Tr
local VALID = Parts.VALID
local floor = Parts.floor
local format = Parts.format
local max = Parts.max
local min = Parts.min
local sort = Parts.sort
local EnsureGuidedTourChrome
local function ResultName(code)
    if code == "s" or code == "skipped" then return "skipped" end
    if code == "k" or code == "kept" then return "kept" end
    return "reviewed"
end

local function RecordControl(stage, section, control, result)
    if not control then return false end
    return Invoke(Tour(), "RecordControl", stage.id, control.id, ResultName(result), {
        pageKey = stage.pageKey,
        sectionId = section.id,
        label = control.label,
        help = control.help,
    })
end

local function RecordControls(stage, section, controls, result)
    controls = type(controls) == "table" and controls or {}
    for i = 1, #controls do RecordControl(stage, section, controls[i], result) end
    return #controls
end

local function RecordSectionOnly(stage, section, result)
    result = ResultName(result)
    Invoke(Tour(), "RecordSection", stage.id, section.id, result, {
        pageKey = stage.pageKey,
        label = section.label,
    })
end

local function RecordSectionAndControls(stage, section, result, sections, records)
    records = type(records) == "table" and records or RuntimeControlRecords()
    local controls = StageSectionControls(stage, section, sections, records)
    RecordControls(stage, section, controls, result)
    RecordSectionOnly(stage, section, result)
    return #controls
end

-- Folds the recorded result codes ("k" kept, "s" skipped) of items into one result.
-- codes is keyed by prefix .. item.id.
local function DerivedResult(codes, items, prefix, fallback)
    local found, allKept, allSkipped = 0, true, true
    for i = 1, #items do
        local code = codes[prefix .. items[i].id]
        if code then
            found = found + 1
            if code ~= "k" then allKept = false end
            if code ~= "s" then allSkipped = false end
        else
            allKept = false
            allSkipped = false
        end
    end
    if found > 0 and found == #items and allSkipped then return "skipped" end
    if found > 0 and found == #items and allKept then return "kept" end
    if found > 0 then return "reviewed" end
    return ResultName(fallback)
end

local function DerivedSectionResult(stage, controls, fallback)
    local state = TourState()
    local byStage = type(state.controlResults) == "table" and state.controlResults[stage.id] or nil
    return DerivedResult(type(byStage) == "table" and byStage or {}, controls, "", fallback)
end

local function DerivedStageResult(stage, sections, fallback)
    local state = TourState()
    local results = type(state.sectionResults) == "table" and state.sectionResults or {}
    return DerivedResult(results, sections, stage.id .. "\031", fallback)
end

local function RecordWholeStage(stage, sections, result)
    result = ResultName(result)
    sections = sections or {}
    for i = 1, #sections do RecordSectionAndControls(stage, sections[i], result, sections) end
    Invoke(Tour(), "RecordStage", stage.id, result)
end

local function InitialCursor(stage)
    if stage and not stage.special then
        return { overview = false, sectionIndex = 1, controlIndex = 1, controlTotal = 0 }
    end
    return { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 }
end

-- A cursor resting on one control of a section.
local function ControlCursor(section, sectionIndex, control, controlIndex, total)
    return {
        overview = false,
        sectionId = section.id,
        sectionIndex = sectionIndex,
        controlId = control and control.id or nil,
        controlIndex = controlIndex,
        controlTotal = total,
    }
end

local function ReadCursor(stage)
    local ok, cursor = Invoke(Tour(), "GetCursor", stage.id)
    cursor = ok and type(cursor) == "table" and cursor or nil
    if not cursor then return InitialCursor(stage) end
    return {
        overview = cursor.overview ~= false,
        sectionId = type(cursor.sectionId) == "string" and cursor.sectionId or nil,
        sectionIndex = max(0, tonumber(cursor.sectionIndex) or 0),
        controlId = type(cursor.controlId) == "string" and cursor.controlId or nil,
        controlIndex = max(0, tonumber(cursor.controlIndex) or 0),
        controlTotal = max(0, tonumber(cursor.controlTotal) or 0),
    }
end

local function WriteCursor(stage, cursor)
    return Invoke(Tour(), "SetCursor", stage.id, cursor)
end

local function FindCursorSection(cursor, sections)
    if cursor.overview ~= false then return nil, 0 end
    if cursor.sectionId then
        for i = 1, #sections do
            if sections[i].id == cursor.sectionId then return sections[i], i end
        end
    end
    local index = min(max(tonumber(cursor.sectionIndex) or 1, 1), #sections)
    return sections[index], index
end

local function FindCursorControl(cursor, controls)
    if not cursor or (not cursor.controlId and (tonumber(cursor.controlIndex) or 0) < 1) then return nil, 0 end
    if cursor.controlId then
        for i = 1, #controls do
            if controls[i].id == cursor.controlId then return controls[i], i end
        end
    end
    if #controls == 0 then return nil, 0 end
    local index = min(max(tonumber(cursor.controlIndex) or 1, 1), #controls)
    return controls[index], index
end

local function FocusGuidedWidget(widget, fallback, flash)
    local outer = widget or fallback
    local scroll = M.scrollFrame
    local child = M.scrollChild
    Runtime.focusRequest = (tonumber(Runtime.focusRequest) or 0) + 1
    local request = Runtime.focusRequest
    local function OwnsFloatingGuidedSurface(frame)
        local current = frame
        for _ = 1, 24 do
            if not current then return false end
            if current._msuf2GuidedNoScroll then return true end
            if type(current.GetParent) ~= "function" then return false end
            local parent = current:GetParent()
            if parent == current then return false end
            current = parent
        end
        return false
    end
    local function FinishFocus(pass)
        if request ~= Runtime.focusRequest then return end
        if outer and not OwnsFloatingGuidedSurface(outer) and scroll and child
            and outer.GetTop and scroll.GetTop and scroll.GetBottom
            and scroll.GetVerticalScroll and scroll.SetVerticalScroll
        then
            local outerTop = outer:GetTop()
            local scrollTop, scrollBottom = scroll:GetTop(), scroll:GetBottom()
            if outerTop and scrollTop and scrollBottom then
                local visibleTop = scrollTop
                -- Fixed header targets are rejected by OwnsFloatingGuidedSurface
                -- above. Every target that reaches this branch belongs to the
                -- normal settings viewport and uses its regular geometry.
                local topInset = widget and 52 or 16
                local desiredTop = max(scrollBottom + 32, visibleTop - topInset)
                local current = tonumber(scroll:GetVerticalScroll()) or 0
                local childHeight = tonumber(child.GetHeight and child:GetHeight()) or 0
                local scrollHeight = tonumber(scroll.GetHeight and scroll:GetHeight()) or 0
                local maxScroll = max(0, childHeight - scrollHeight)
                local target = min(max(current + (desiredTop - outerTop), 0), maxScroll)
                if math.abs(target - current) >= 1 then scroll:SetVerticalScroll(floor(target + 0.5)) end
                if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
            end
        end
        local T = M.Theme
        if pass == 1 and flash and outer and T and type(T.PlayNeonFlash) == "function" and type(outer.CreateTexture) == "function" then
            T.PlayNeonFlash(outer, "success", { alpha = 0.24, duration = 0.72 })
        end
        -- Accordion expansion and page relayout settle on the next frame.
        if pass == 1 and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() FinishFocus(2) end)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() FinishFocus(1) end)
    else
        FinishFocus(1)
        FinishFocus(2)
    end
end

local function FocusCurrentSection(stage)
    if stage.special then return end
    local cursor = ReadCursor(stage)
    if cursor.overview ~= false then
        M.CloseAutoFocusedSections(stage.pageKey)
        ClearSectionEmphasis(stage.pageKey)
        return
    end
    local sections = StageSections(stage)
    local section, index = FindCursorSection(cursor, sections)
    if not section then
        WriteCursor(stage, InitialCursor(stage))
        return
    end
    local controls = StageSectionControls(stage, section, sections)
    local control, controlIndex = FindCursorControl(cursor, controls)
    if cursor.sectionId ~= section.id
        or cursor.sectionIndex ~= index
        or cursor.controlId ~= (control and control.id or nil)
        or cursor.controlIndex ~= controlIndex
        or cursor.controlTotal ~= #controls
    then
        WriteCursor(stage, ControlCursor(section, index, control, controlIndex, #controls))
    end
    local W = M.Widgets
    M.CloseAutoFocusedSections(stage.pageKey)
    if W and type(W.FocusCollapsibleSection) == "function" then
        for i = 1, #sections do
            local ancestor = sections[i]
            if ancestor.collapsible
                and ancestor.id ~= section.id
                and section.outer
                and IsWidgetInside(section.outer, ancestor.body)
            then
                W.FocusCollapsibleSection(ancestor.body, { persist = false, flash = false })
            end
        end
        if section.collapsible then
            W.FocusCollapsibleSection(section.body, { persist = false, flash = true })
        else
            FocusGuidedWidget(section.outer, nil, true)
        end
    end
    if control then FocusGuidedWidget(control.widget, section.outer, false) end
    EmphasizeSection(stage.pageKey, section, control)
    EmphasizeControl(stage, section, controls, control)
end

local function RefreshTourDashboard()
    M.MarkMenuDataDirty("guided-tour")
    local entry = M.cache.home
    -- Onboarding/highlight scenes have a different structure. The normal
    -- Dashboard launcher reads its live tour state through its refresher.
    if entry and not entry.guidedSetupLauncher then M.InvalidatePage("home") end
end

local function SelectExpectedPage(stage)
    local pageKey = ExpectedPage(stage)
    if EnsureGuidedTourChrome then EnsureGuidedTourChrome() end
    Runtime.manualAway = nil
    Runtime.warning = nil
    M.MarkMenuDataDirty("guided-stage")
    if M.frame and type(M.frame.IsShown) == "function" and M.frame:IsShown() then
        -- Special stages share a page key, but declare separate bounded views.
        -- SelectPage restores that view's controls and click-target ownership.
        if not stage.special and M.activeKey == pageKey and M.cache and M.cache[pageKey] then
            if type(M.RefreshGuidedTourChrome) == "function" then M.RefreshGuidedTourChrome("SAME_PAGE_STAGE") end
            return true
        end
        return M.SelectPage(pageKey)
    end
    return M.Open(pageKey)
end

local function SetStage(stage, resetCursor)
    if not stage then return false end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if resetCursor or not select(2, Invoke(Tour(), "GetCursor", stage.id)) then
        WriteCursor(stage, InitialCursor(stage))
    end
    return SelectExpectedPage(stage)
end

local function CompleteTour()
    ClearSectionEmphasis()
    Invoke(Tour(), "Complete")
    Invoke(FirstLoad(), "Complete", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.touchedSignature = nil
    Runtime.lastVisualSignature = nil
    M.RefreshGuidedTourChrome("COMPLETE")
    RefreshTourDashboard()
    M.SelectPage("home")
    return true
end

local function AdvanceStage(stage, resetCursor)
    local current, total, stages = ActiveStagePosition(stage)
    if current >= total then return CompleteTour() end
    return SetStage(stages[current + 1], resetCursor ~= false)
end

local function ReturnToPreviousStage(stage)
    local current, _, stages = ActiveStagePosition(stage)
    if current <= 1 then return false end
    local previous = stages[current - 1]
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", previous.id, previous.index)
    return SelectExpectedPage(previous)
end

local function FindAvailableControl(stage, sections, startIndex, direction)
    sections = type(sections) == "table" and sections or {}
    direction = direction == -1 and -1 or 1
    local index = min(max(tonumber(startIndex) or (direction == 1 and 1 or #sections), 1), max(1, #sections))
    while sections[index] do
        local section = sections[index]
        local controls = StageSectionControls(stage, section, sections)
        if #controls > 0 then
            local controlIndex = direction == 1 and 1 or #controls
            return section, index, controls, controls[controlIndex], controlIndex
        end
        index = index + direction
    end
    return nil, 0, {}, nil, 0
end

local function CurrentPosition(stage)
    if stage.special then return { overview = true, sections = {}, index = 0 } end
    local sections = StageSections(stage)
    local cursor = ReadCursor(stage)
    local section, index = FindCursorSection(cursor, sections)
    local controls = section and StageSectionControls(stage, section, sections) or {}
    local control, controlIndex = FindCursorControl(cursor, controls)
    local normalized = false
    if cursor.overview ~= false or not section or not control then
        local startIndex = section and index or 1
        section, index, controls, control, controlIndex = FindAvailableControl(stage, sections, startIndex, 1)
        if not control and startIndex > 1 then
            section, index, controls, control, controlIndex = FindAvailableControl(stage, sections, 1, 1)
        end
        if control then
            cursor = ControlCursor(section, index, control, controlIndex, #controls)
            WriteCursor(stage, cursor)
            normalized = true
        else
            cursor = InitialCursor(stage)
            cursor.overview = true
        end
    end
    return {
        overview = control == nil,
        cursor = cursor,
        cursorNormalized = normalized,
        sections = sections,
        section = section,
        index = index,
        controls = controls,
        control = control,
        controlIndex = controlIndex,
    }
end

local function TouchSignature(stage, position)
    local control = position and position.control
    if not (stage and control) then return nil end
    return table.concat({ stage.id or "", position.section and position.section.id or "", control.id or "" }, "\031")
end

local function CurrentControlTouched(stage, position)
    local signature = TouchSignature(stage, position)
    return signature ~= nil and Runtime.touchedSignature == signature
end

local function TourExperience()
    local summary = M.GetGuidedTourSummary and M.GetGuidedTourSummary() or {}
    return ((tonumber(summary.reviewedControls) or 0) * 10)
        + ((tonumber(summary.keptControls) or 0) * 5)
        + ((tonumber(summary.reviewedSections) or 0) * 20)
        + ((tonumber(summary.reviewedStages) or 0) * 50)
end

function M.NotifyGuidedTourControlInteraction(widget)
    if not TourIsActive() or Runtime.manualAway or Runtime.warning or ProfileMismatch() then return false end
    local stage = CurrentStage()
    if stage.special then return false end
    local position = CurrentPosition(stage)
    local control = position.control
    if not (control and control.actionable ~= false) then return false end
    local command = widget and widget._msuf2CommandAction
    local controlId = command and command.controlId or (widget and widget._msuf2ControlId)
    if widget ~= control.widget and tostring(controlId or "") ~= tostring(control.id or "") then return false end
    local signature = TouchSignature(stage, position)
    if not signature then return false end
    Runtime.touchedSignature = signature
    local T = M.Theme
    if T and type(T.PlayNeonFlash) == "function" and control.widget and type(control.widget.CreateTexture) == "function" then
        T.PlayNeonFlash(control.widget, "success", { alpha = 0.34, duration = 0.92 })
    end
    if type(M.RefreshGuidedTourChrome) == "function" then M.RefreshGuidedTourChrome("CONTROL_USED") end
    return true
end

local function KeepLabel(stage, position)
    if stage.special then return "Keep as is" end
    if ControlIsAction(position.control) then return "Keep action" end
    if position.control then return "Keep unchanged" end
    return "Skip empty mission"
end

local function SetSectionCursor(stage, sections, sectionIndex, controlIndex, reason)
    local section = sections[sectionIndex]
    if not section then return false end
    local controls = StageSectionControls(stage, section, sections)
    if #controls == 0 then return false end
    controlIndex = min(max(tonumber(controlIndex) or 1, 1), #controls)
    local control = controls[controlIndex]
    WriteCursor(stage, ControlCursor(section, sectionIndex, control, controlIndex, #controls))
    FocusCurrentSection(stage)
    M.RefreshGuidedTourChrome(reason or "GUIDED_POSITION")
    return true
end

local function SetAvailableControlCursor(stage, sections, startIndex, direction, reason)
    local _, sectionIndex, _, _, controlIndex = FindAvailableControl(stage, sections, startIndex, direction)
    if sectionIndex < 1 or controlIndex < 1 then return false end
    return SetSectionCursor(stage, sections, sectionIndex, controlIndex, reason)
end

local function AdvanceCurrent(result)
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    result = ResultName(result)

    if stage.id == "final_review" then return CompleteTour() end
    if stage.special then
        Invoke(Tour(), "RecordStage", stage.id, result)
        return AdvanceStage(stage, true)
    end
    if position.overview or not position.control then
        if result == "reviewed" and SetAvailableControlCursor(stage, position.sections, 1, 1, "FIRST_CONTROL") then return true end
        RecordWholeStage(stage, position.sections, result)
        return AdvanceStage(stage, true)
    end

    RecordControl(stage, position.section, position.control, result)
    if position.controlIndex < #position.controls then
        return SetSectionCursor(stage, position.sections, position.index, position.controlIndex + 1, "NEXT_CONTROL")
    end
    RecordSectionOnly(stage, position.section, DerivedSectionResult(stage, position.controls, result))

    if position.index < #position.sections
        and SetAvailableControlCursor(stage, position.sections, position.index + 1, 1, "NEXT_CONTROL")
    then return true end
    Invoke(Tour(), "RecordStage", stage.id, DerivedStageResult(stage, position.sections, result))
    return AdvanceStage(stage, true)
end

local function BackCurrent()
    if ProfileMismatch() then
        return type(M.StartGuidedTour) == "function"
            and M.StartGuidedTour({ source = "profile_change", restart = true })
            or false
    end
    if Runtime.warning then
        Runtime.warning = nil
        M.RefreshGuidedTourChrome("CANCEL_SKIP")
        return true
    end
    if Runtime.manualAway then
        Runtime.manualAway = nil
        return SelectExpectedPage(CurrentStage())
    end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    if stage.special or position.overview then return ReturnToPreviousStage(stage) end
    if position.control then
        local previousControl = position.controlIndex - 1
        if previousControl > 0 then
            return SetSectionCursor(stage, position.sections, position.index, previousControl, "PREVIOUS_CONTROL")
        end
        if position.index > 1
            and SetAvailableControlCursor(stage, position.sections, position.index - 1, -1, "PREVIOUS_CONTROL")
        then return true end
    end
    return ReturnToPreviousStage(stage)
end

local function SkipWarning(stage, position)
    if position.control then
        return format(Tr("SKIP CHECKPOINT? %s stays unchanged. Press Confirm skip."), Tr(position.control.label)), 1
    end

    local controls = position.section and position.controls
        or (not stage.special and AllStageControls(stage, position.sections))
        or {}
    local parts = {}
    if position.section then
        parts[1] = format(Tr("SKIP CHECKPOINT? %s and %d settings stay unchanged."), Tr(position.section.label), #controls)
    elseif not stage.special and #position.sections > 0 then
        parts[1] = format(Tr("SKIP MISSION? %d checkpoints and %d settings stay unchanged."), #position.sections, #controls)
    else
        parts[1] = format(Tr("SKIP MISSION? %s"), Tr(stage.impact))
    end
    parts[#parts + 1] = Tr("Press Confirm skip to continue.")
    return table.concat(parts, "\n"), #controls
end

local function SkipCurrent()
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    if stage.id == "final_review" then return false end
    local position = CurrentPosition(stage)
    local signature = table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
    }, "\031")
    if Runtime.warning then
        local warning = Runtime.warning
        local sectionId = position.section and position.section.id or nil
        if warning.stageId == stage.id and warning.sectionId == sectionId then
            Runtime.warning = nil
            return AdvanceCurrent("skipped")
        end
    end
    local text, count = SkipWarning(stage, position)
    Runtime.warning = {
        signature = signature,
        stageId = stage.id,
        sectionId = position.section and position.section.id or nil,
        controlId = position.control and position.control.id or nil,
        text = text,
        count = count,
    }
    M.RefreshGuidedTourChrome("SKIP_WARNING")
    return true
end

local function PauseTour()
    Runtime.warning = nil
    Runtime.manualAway = nil
    ClearSectionEmphasis()
    M.HideSlashMenuAndMinibar(M.frame)
    return true
end

function M.StartGuidedTour(opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(opts.stageId or "")] or STAGES[1]
    local restorePoint
    local value = M.CaptureGuidedTourRestorePoint()
    if type(value) == "table" then restorePoint = value end
    local ok = Invoke(Tour(), "Start", ActiveProfileName(), stage.id, restorePoint)
    if not ok then return false end
    local requestedMode = tostring(opts.mode or "")
    if not VALID.setupMode[requestedMode] then
        requestedMode = opts.stageId and "complete" or "quick"
    end
    Invoke(Tour(), "SetPreference", "setupMode", requestedMode)
    if VALID.setupArea[tostring(opts.setupArea or "")] then
        Invoke(Tour(), "SetPreference", "setupArea", tostring(opts.setupArea))
    end
    Invoke(FirstLoad(), "Start", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.touchedSignature = nil
    Runtime.lastVisualSignature = nil
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    WriteCursor(stage, InitialCursor(stage))
    RefreshTourDashboard()
    return SelectExpectedPage(stage)
end

function M.ResumeGuidedTour()
    if BlockedByCombat() or not TourIsActive() then return false end
    Invoke(Tour(), "Resume")
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(CurrentStage())
end

function M.OpenGuidedTourAtStage(stageId, opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(stageId or "")]
    if not stage then return false end
    if not TourIsActive() then
        opts.stageId = stage.id
        return M.StartGuidedTour(opts)
    end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if opts.resetCursor == true then WriteCursor(stage, InitialCursor(stage)) end
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(stage)
end

function M.GetGuidedTourCurrentPage()
    return ExpectedPage(CurrentStage())
end

function M.GetGuidedTourSummary()
    local ok, source = Invoke(Tour(), "GetSummary")
    source = ok and type(source) == "table" and source or {}
    local activeStages = ActiveStages()
    local activeStageIds = {}
    for i = 1, #activeStages do activeStageIds[activeStages[i].id] = true end
    local summary = {
        totalStages = #activeStages,
        skippedItems = {},
        skippedAreas = {},
        skippedSectionItems = {},
    }
    for _, counter in ipairs({ "reviewedStages", "keptStages", "skippedStages", "reviewedSections", "keptSections",
        "skippedSections", "reviewedControls", "keptControls", "skippedControls" }) do
        summary[counter] = tonumber(source[counter]) or 0
    end
    local state = TourState()
    local stageResults = type(state.stageResults) == "table" and state.stageResults or {}
    for i = 1, #activeStages do
        local stage = activeStages[i]
        if stageResults[stage.id] == "s" then
            summary.skippedAreas[#summary.skippedAreas + 1] = Tr(stage.title)
        end
    end
    local sectionResults = type(state.sectionResults) == "table" and state.sectionResults or {}
    local sectionMetadata = type(state.sectionMetadata) == "table" and state.sectionMetadata or {}
    for resultKey, code in pairs(sectionResults) do
        if code == "s" then
            local metadata = type(sectionMetadata[resultKey]) == "table" and sectionMetadata[resultKey] or {}
            local stageId = tostring(metadata.stageId or resultKey:match("^(.-)\031") or "")
            local stage = STAGE_BY_ID[stageId]
            if stage and activeStageIds[stageId] and stageResults[stageId] ~= "s" then
                summary.skippedSectionItems[#summary.skippedSectionItems + 1] = {
                    stageIndex = stage.index,
                    stageLabel = Tr(stage.title),
                    label = Tr(metadata.label or metadata.sectionId or "Section"),
                }
            end
        end
    end
    sort(summary.skippedSectionItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        return a.label < b.label
    end)
    local skipped = type(state.skippedControls) == "table" and state.skippedControls or {}
    for controlId, item in pairs(skipped) do
        if type(item) == "table" then
            local stageId = tostring(item.stageId or "")
            local sectionId = tostring(item.sectionId or "")
            local coveredByStage = stageResults[stageId] == "s"
            local coveredBySection = sectionId ~= "" and sectionResults[stageId .. "\031" .. sectionId] == "s"
            if activeStageIds[stageId] and not coveredByStage and not coveredBySection then
                local stage = STAGE_BY_ID[stageId]
                summary.skippedItems[#summary.skippedItems + 1] = {
                    controlId = tostring(controlId),
                    stageId = stageId,
                    stageIndex = stage and stage.index or (#STAGES + 1),
                    stageLabel = stage and Tr(stage.title) or Tr("Guided setup"),
                    label = tostring(item.label or controlId),
                    pageKey = item.pageKey,
                    sectionId = item.sectionId,
                }
            end
        end
    end
    sort(summary.skippedItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.controlId < b.controlId or al < bl
    end)
    return summary
end


Parts.AdvanceCurrent = AdvanceCurrent
Parts.BackCurrent = BackCurrent
Parts.CurrentControlTouched = CurrentControlTouched
Parts.CurrentPosition = CurrentPosition
Parts.FocusCurrentSection = FocusCurrentSection
Parts.FocusGuidedWidget = FocusGuidedWidget
Parts.KeepLabel = KeepLabel
Parts.PauseTour = PauseTour
Parts.SelectExpectedPage = SelectExpectedPage
Parts.SkipCurrent = SkipCurrent
Parts.TourExperience = TourExperience
function Parts.Bind2()
    EnsureGuidedTourChrome = Parts.EnsureGuidedTourChrome
end
