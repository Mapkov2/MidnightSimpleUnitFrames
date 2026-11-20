--- Provider-neutral popup for frames registered through MSUF_EditModeAPI.
local addonName, MSUF = ...

local EM2 = MSUF.Optional("MSUF_EM2")
if not EM2 then return end

local Quick = EM2.QuickPopup or {}
local External = EM2.ExternalElements
if not (Quick.CreateShell and External) then return end

local Popup, frame = {}, nil
EM2.ExternalPopup = Popup

local function Blocked()
    return Quick.BlockConfigCombatLocked and Quick.BlockConfigCombatLocked() or false
end

-- Quick buttons come in two looks: the plain one keeps its caption in _label,
-- the menu-styled one (Quick.Button with Menu2Style.Button) in _msuf2Label and
-- sets it through its own SetText.
local function ButtonLabel(button)
    return button and (button._label or button._msuf2Label) or nil
end

local function SetButtonText(button, text)
    if not button then return end
    if button._label then
        if button._label.SetText then button._label:SetText(text or "") end
    elseif button._msuf2Label and button.SetText then
        button:SetText(text or "", true)
    end
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    button._msufExternalEnabled = enabled == true
    button:EnableMouse(enabled == true)
    button:SetAlpha(enabled and 1 or 0.42)
end

local function FormatValues(label, x, y, width, height)
    if x == nil or y == nil then return tostring(label or "External frame") end
    if width ~= nil and height ~= nil then
        return ("W %s     H %s"):format(width, height)
    end
    return ""
end

local function ApplyPosition(axis, box)
    if Blocked() or not (frame and frame._key) or frame._syncing then return end
    local applied = EM2.Ticker.SetExternalPosition(frame._key, axis, box:GetText())
    Popup.Sync()
    return applied
end

local function StepX(amount)
    if Blocked() or not (frame and frame._key) or frame._syncing then return false end
    local applied = EM2.Ticker.SetExternalPosition(frame._key, "x", amount, true)
    Popup.Sync(frame.xBox)
    return applied
end

local function OpenSettings()
    if Blocked() or not frame then return end
    if External.OpenSettings(frame._key) then frame:Hide() end
end

local function ResetPosition()
    if Blocked() or not frame then return end
    if External.Reset(frame._key) then Popup.Sync() end
end

--- Owner-declared quick controls (see extraControls in the public API) render
--- as native MSUF stepper/toggle rows above the buttons. Widget sets are built
--- once per control signature and shared by every element that declares it.
local CONTROLS_TOP, CONTROL_ROW_H, BUTTONS_TOP, BASE_HEIGHT = -144, 40, -150, 264
--- The W/H readout's line (-76) sits above the generic position row; an
--- owner without the readout (sizeSummary = false) lifts every row by it.
local POSITION_TOP, SUMMARY_LIFT = -104, 28

local function ApplyNumberControl(id, box, step)
    if Blocked() or not (frame and frame._key) or frame._syncing then return false end
    local current = External.GetControlValue(frame._key, id)
    if issecretvalue and issecretvalue(current) then return false end
    local fallback = tonumber(current) or 0
    local value = step and (fallback + step) or Quick.San(box:GetText(), fallback)
    local applied = External.ApplyControl(frame._key, id, value)
    Popup.Sync(step and box)
    return applied
end

local function NumberStepper(spec, holder, field)
    if spec.positionAxis ~= "x" then return nil end
    return function(amount) return ApplyNumberControl(spec.id, holder[field], amount) end
end

local function ApplyToggleControl(id, checked)
    if Blocked() or not (frame and frame._key) or frame._syncing then return end
    External.ApplyControl(frame._key, id, checked == true)
    Popup.Sync()
end

local function OwnerPositionControls(controls)
    local x, y
    for i = 1, #(controls or {}) do
        local spec = controls[i]
        if spec.kind == "number" then
            if spec.positionAxis == "x" then x = true end
            if spec.positionAxis == "y" then y = true end
        end
    end
    return x and y or false
end

local function ControlSignature(controls)
    local parts = {}
    for i = 1, #controls do
        parts[i] = ("%s:%s:%s:%s"):format(controls[i].kind, controls[i].id, controls[i].label, controls[i].positionAxis or "")
    end
    return table.concat(parts, "|")
end

--- Two paired steppers only fit the 420px shell when both labels stay
--- inside the fixed budget (two stepper blocks eat ~276px). Long localized
--- labels — the Blizzard Edit Mode strings most visibly — get their own
--- row instead of clipping past the popup edge.
local PAIR_LABEL_BUDGET = 104

local function LabelWidth(text)
    if not frame._labelProbe then
        frame._labelProbe = Quick.FS(frame, "caption")
        frame._labelProbe:Hide()
    end
    --- Measure what the row will actually render: the translated label, with
    --- a small factor covering the readable-size bump the row labels get.
    frame._labelProbe:SetText(Quick.Tr and Quick.Tr(text or "") or text or "")
    return (frame._labelProbe:GetStringWidth() or 0) * 1.08
end

-- Anchor registries can be long. Clip only these owned menus and scroll
-- their existing rows; the shared quick-popup menu keeps its old behavior.
local function ScrollChoices(menu)
    local rows, width = menu._items or {}, menu:GetWidth()
    if not menu._choiceScroll then
        local scroll = CreateFrame("ScrollFrame", nil, menu)
        scroll:SetPoint("TOPLEFT", 2, -3)
        scroll:SetPoint("BOTTOMRIGHT", -2, 3)
        local content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(content)
        menu._choiceScroll, menu._choiceContent = scroll, content
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(_, delta)
            local limit = math.max(0, content:GetHeight() - scroll:GetHeight())
            scroll:SetVerticalScroll(math.max(0, math.min(limit, scroll:GetVerticalScroll() - delta * 48)))
        end)
    end
    local count = 0
    for i, item in ipairs(rows) do
        item:SetParent(menu._choiceContent)
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        if item:IsShown() then count = i end
    end
    menu._choiceContent:SetSize(width - 4, math.max(1, count * 24))
    menu:SetHeight(math.min(12, count) * 24 + 8)
    menu._choiceScroll:SetVerticalScroll(0)
end

local function ChoiceButton(spec, y, set)
    local openedKey
    local choice = { id = spec.id, label = spec.label }
    local function Entries()
        openedKey = frame._key
        choice.key = nil
        local values = External.GetControlChoices(openedKey, spec.id) or {}
        local rows, current = {}, External.GetControlValue(openedKey, spec.id)
        if issecretvalue and issecretvalue(current) then return rows end
        for i, value in ipairs(values) do
            rows[i] = { label = value.text, value = value.value, highlight = current == value.value }
        end
        return rows
    end
    local button, menu = Quick.MenuButtonAt(frame, spec.label, 20, y, 380, 32, Entries, function(row)
        if Blocked() or frame._key ~= openedKey then return end
        External.ApplyControl(openedKey, spec.id, row.value)
        Popup.Sync()
    end, { flashSelection = false })
    local label = ButtonLabel(button)
    if label then
        label:SetWidth(356)
        label:SetMaxLines(1)
    end
    menu:HookScript("OnShow", function() ScrollChoices(menu) end)
    choice.btn = button
    set.choices[#set.choices + 1] = choice
    set.rows[#set.rows + 1] = button
end

local function BuildControlSet(controls, lift)
    local set = { rows = {}, numbers = {}, toggles = {}, choices = {}, height = 0 }
    local top = CONTROLS_TOP + lift + (OwnerPositionControls(controls) and CONTROL_ROW_H or 0)
    local numbers, toggles, choices = {}, {}, {}
    for i = 1, #controls do
        local spec = controls[i]
        if spec.kind == "number" then numbers[#numbers + 1] = spec
        elseif spec.kind == "choice" then choices[#choices + 1] = spec
        else toggles[#toggles + 1] = spec end
    end
    local rowIndex = 0
    local index = 1
    while index <= #numbers do
        rowIndex = rowIndex + 1
        local y = top - (rowIndex - 1) * CONTROL_ROW_H
        local first, second = numbers[index], numbers[index + 1]
        if second and LabelWidth(first.label) + LabelWidth(second.label) > PAIR_LABEL_BUDGET then
            second = nil
        end
        local holder, row = {}, nil
        if second then
            row = Quick.ValuePairAt(holder, frame, 20, y,
                first.label, "boxA", function() ApplyNumberControl(first.id, holder.boxA) end,
                second.label, "boxB", function() ApplyNumberControl(second.id, holder.boxB) end,
                { boxWidth = 48, onStepFirst = NumberStepper(first, holder, "boxA"),
                    onStepSecond = NumberStepper(second, holder, "boxB") })
            holder.boxA._msufStep = tonumber(first.step)
            holder.boxB._msufStep = tonumber(second.step)
            set.numbers[#set.numbers + 1] = { id = first.id, box = holder.boxA }
            set.numbers[#set.numbers + 1] = { id = second.id, box = holder.boxB }
            index = index + 2
        else
            row = Quick.SingleValueAt(holder, frame, 20, y,
                first.label, "boxA", function() ApplyNumberControl(first.id, holder.boxA) end,
                { boxWidth = 48, onStep = NumberStepper(first, holder, "boxA") })
            holder.boxA._msufStep = tonumber(first.step)
            set.numbers[#set.numbers + 1] = { id = first.id, box = holder.boxA }
            index = index + 1
        end
        set.rows[#set.rows + 1] = row
    end
    index = 1
    while index <= #toggles do
        rowIndex = rowIndex + 1
        local y = top - (rowIndex - 1) * CONTROL_ROW_H
        local first, second = toggles[index], toggles[index + 1]
        local btnA = Quick.ToggleAt(frame, first.label, 20, y, second and 184 or 200, 32, function(checked)
            ApplyToggleControl(first.id, checked)
        end)
        set.toggles[#set.toggles + 1] = { id = first.id, btn = btnA }
        set.rows[#set.rows + 1] = btnA
        if second then
            local btnB = Quick.ToggleAt(frame, second.label, 216, y, 184, 32, function(checked)
                ApplyToggleControl(second.id, checked)
            end)
            set.toggles[#set.toggles + 1] = { id = second.id, btn = btnB }
            set.rows[#set.rows + 1] = btnB
        end
        index = index + 2
    end
    for _, spec in ipairs(choices) do
        rowIndex = rowIndex + 1
        ChoiceButton(spec, top - (rowIndex - 1) * CONTROL_ROW_H, set)
    end
    set.height = rowIndex * CONTROL_ROW_H
    return set
end

local function SetControlSetShown(set, shown)
    if not set then return end
    for i = 1, #set.rows do
        if shown then set.rows[i]:Show() else set.rows[i]:Hide() end
    end
end

local function LayoutControls(key, lift)
    local controls = External.GetControls and External.GetControls(key)
    local set
    if controls then
        frame._controlSets = frame._controlSets or {}
        local signature = ControlSignature(controls) .. "|" .. lift
        set = frame._controlSets[signature]
        if not set then
            set = BuildControlSet(controls, lift)
            frame._controlSets[signature] = set
        end
    end
    if frame._activeControlSet and frame._activeControlSet ~= set then
        SetControlSetShown(frame._activeControlSet, false)
    end
    frame._activeControlSet = set
    SetControlSetShown(set, true)
    return set
end

local function SyncControlValues(set, key, committedBox)
    if not set then return end
    for _, choice in ipairs(set.choices) do
        local value = External.GetControlValue(key, choice.id)
        if issecretvalue and issecretvalue(value) then value = nil end
        if choice.key ~= key or choice.value ~= value then
            local text = "Unavailable"
            for _, row in ipairs(External.GetControlChoices(key, choice.id) or {}) do
                if row.value == value then text = row.text break end
            end
            local tr = Quick.Tr or tostring
            SetButtonText(choice.btn, tr("%s: %s"):format(tr(choice.label), tr(text)))
            choice.key, choice.value = key, value
        end
    end
    for i = 1, #set.numbers do
        local value = External.GetControlValue(key, set.numbers[i].id)
        Quick.SetBoxText(set.numbers[i].box, value ~= nil and value or "", set.numbers[i].box == committedBox)
    end
    for i = 1, #set.toggles do
        set.toggles[i].btn:SetCheckedVisual(External.GetControlValue(key, set.toggles[i].id) == true)
    end
end

local function Build()
    if frame then return frame end
    frame = Quick.CreateShell("MSUF_EM2_ExternalPopup", {
        width = 420, height = BASE_HEIGHT, title = "External frame", liveStatus = "Managed by its addon",
        hoverSource = "external-popup", blocker = Blocked,
    })
    --- External labels are owner-supplied and can be long: pin the status pill
    --- left of the close button and let the title truncate before the pill
    --- instead of clipping underneath both.
    if frame._liveStatus then
        frame._liveStatus:ClearAllPoints()
        frame._liveStatus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -18)
        frame._titleFS:SetPoint("RIGHT", frame._liveStatus, "LEFT", -10, 0)
    else
        frame._titleFS:SetPoint("RIGHT", frame, "TOPRIGHT", -44, 0)
    end
    if frame._titleFS.SetWordWrap then frame._titleFS:SetWordWrap(false) end
    frame._titleFS:SetJustifyH("LEFT")
    frame._summaryFS = Quick.FS(frame, "body")
    frame._summaryFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -76)
    frame._summaryFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -76)
    frame._summaryFS:SetJustifyH("LEFT")
    frame._positionRow = Quick.ValuePairAt(frame, frame, 20, POSITION_TOP,
        "X", "xBox", function() ApplyPosition("x", frame.xBox) end,
        "Y", "yBox", function() ApplyPosition("y", frame.yBox) end,
        { boxWidth = 48, onStepFirst = StepX })

    frame._settingsBtn = Quick.ButtonAt(frame, "Open settings", 20, BUTTONS_TOP, 252, 36, OpenSettings, {
        variant = "primary", hoverWash = true,
    })
    frame._resetBtn = Quick.ButtonAt(frame, "Reset position", 284, BUTTONS_TOP, 116, 36, ResetPosition, {
        hoverWash = true,
    })
    Quick.AddFooterControls(frame, { anchor = "BOTTOM", bottomGap = 12 })
    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(frame) end
    return frame
end

function Popup.Sync(committedBox)
    if not (frame and frame._key) then return false end
    local label, group, settingsLabel, canSettings, canReset = External.GetDisplayInfo(frame._key)
    if not label then
        frame:Hide()
        return false
    end
    frame._syncing = true
    frame._titleFS:SetText(label)
    local title, x, y, width, height = External.GetInspectorValues(frame._key)
    local summary = External.ShowsSizeSummary(frame._key)
    local lift = summary and 0 or SUMMARY_LIFT
    frame._summaryFS:SetText(summary and FormatValues(title, x, y, width, height) or "")
    frame._summaryFS:SetShown(summary)
    frame._positionRow:ClearAllPoints()
    frame._positionRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, POSITION_TOP + lift)
    Quick.SetBoxText(frame.xBox, x ~= nil and x or "", frame.xBox == committedBox)
    Quick.SetBoxText(frame.yBox, y ~= nil and y or "")
    local ownedPosition = OwnerPositionControls(External.GetControls(frame._key))
    frame._positionRow:SetShown(not ownedPosition)
    local enabled = not ownedPosition and External.GetPositionFrame(frame._key) ~= nil
    frame._positionRow:SetAlpha(enabled and 1 or 0.42)
    for _, child in ipairs({ frame._positionRow:GetChildren() }) do
        child:EnableMouse(enabled)
        if enabled then child:Enable() else child:Disable() end
    end
    if not enabled then
        frame.xBox:ClearFocus()
        frame.yBox:ClearFocus()
    end
    local set = LayoutControls(frame._key, lift)
    SyncControlValues(set, frame._key, committedBox)
    local extra = (set and set.height or 0) - (ownedPosition and CONTROL_ROW_H or 0) - lift
    frame._settingsBtn:ClearAllPoints()
    frame._settingsBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, BUTTONS_TOP - extra)
    frame._resetBtn:ClearAllPoints()
    frame._resetBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 284, BUTTONS_TOP - extra)
    frame:SetHeight(BASE_HEIGHT + extra)
    SetButtonText(frame._settingsBtn, settingsLabel or string.format(
        Quick.Tr and Quick.Tr("Open %s settings") or "Open %s settings", tostring(group or label)))
    SetButtonEnabled(frame._settingsBtn, canSettings)
    SetButtonEnabled(frame._resetBtn, canReset)
    if frame._refreshUndoRedo then frame._refreshUndoRedo() end
    frame._syncing = nil
    return true
end

function Popup.Open(key)
    if Blocked() then return false end
    local record = External.GetRecord(key)
    if not record then return false end
    Build()._key = key
    frame._msufEM2CenterOnShow = record.centerPopup == true
    if not Popup.Sync() then return false end
    if frame._msufEM2CenterOnShow then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:Show()
    return true
end

function Popup.Close() if frame then frame:Hide() end end
function Popup.IsOpen() return frame and frame:IsShown() or false end
function Popup.GetKey() return frame and frame._key or nil end
function Popup.RefreshHistory() if frame and frame:IsShown() and frame._refreshUndoRedo then frame._refreshUndoRedo() end end
