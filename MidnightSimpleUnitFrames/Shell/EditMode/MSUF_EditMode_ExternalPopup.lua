--- Provider-neutral popup for frames registered through MSUF_EditModeAPI.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local EM2 = _G.MSUF_EM2
if not EM2 then return end
if type(_G.MSUF_InstallEditPopupUI) == "function" then
    _G.MSUF_InstallEditPopupUI(addonName, MSUF)
end

local Quick = EM2.QuickPopup or {}
local External = EM2.ExternalElements
if not (Quick.CreateShell and External) then return end

local Popup, frame = {}, nil
EM2.ExternalPopup = Popup

local function Blocked()
    return Quick.BlockConfigCombatLocked and Quick.BlockConfigCombatLocked() or false
end

local function SetButtonText(button, text)
    if button and button._label and button._label.SetText then button._label:SetText(text or "") end
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
        return ("X %s     Y %s     W %s     H %s"):format(x, y, width, height)
    end
    return ("X %s     Y %s"):format(x, y)
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
local CONTROLS_TOP, CONTROL_ROW_H, BUTTONS_TOP, BASE_HEIGHT = -104, 40, -110, 224

local function ApplyNumberControl(id, box)
    if Blocked() or not (frame and frame._key) then return end
    local fallback = tonumber(External.GetControlValue(frame._key, id)) or 0
    External.ApplyControl(frame._key, id, Quick.San(box:GetText(), fallback))
    Popup.Sync()
end

local function ApplyToggleControl(id, checked)
    if Blocked() or not (frame and frame._key) then return end
    External.ApplyControl(frame._key, id, checked == true)
    Popup.Sync()
end

local function ControlSignature(controls)
    local parts = {}
    for i = 1, #controls do
        parts[i] = ("%s:%s:%s"):format(controls[i].kind, controls[i].id, controls[i].label)
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

local function BuildControlSet(controls)
    local set = { rows = {}, numbers = {}, toggles = {}, height = 0 }
    local numbers, toggles = {}, {}
    for i = 1, #controls do
        local spec = controls[i]
        if spec.kind == "number" then numbers[#numbers + 1] = spec else toggles[#toggles + 1] = spec end
    end
    local rowIndex = 0
    local index = 1
    while index <= #numbers do
        rowIndex = rowIndex + 1
        local y = CONTROLS_TOP - (rowIndex - 1) * CONTROL_ROW_H
        local first, second = numbers[index], numbers[index + 1]
        if second and LabelWidth(first.label) + LabelWidth(second.label) > PAIR_LABEL_BUDGET then
            second = nil
        end
        local holder, row = {}, nil
        if second then
            row = Quick.ValuePairAt(holder, frame, 20, y,
                first.label, "boxA", function() ApplyNumberControl(first.id, holder.boxA) end,
                second.label, "boxB", function() ApplyNumberControl(second.id, holder.boxB) end,
                { boxWidth = 48 })
            holder.boxA._msufStep = tonumber(first.step)
            holder.boxB._msufStep = tonumber(second.step)
            set.numbers[#set.numbers + 1] = { id = first.id, box = holder.boxA }
            set.numbers[#set.numbers + 1] = { id = second.id, box = holder.boxB }
            index = index + 2
        else
            row = Quick.SingleValueAt(holder, frame, 20, y,
                first.label, "boxA", function() ApplyNumberControl(first.id, holder.boxA) end,
                { boxWidth = 48 })
            holder.boxA._msufStep = tonumber(first.step)
            set.numbers[#set.numbers + 1] = { id = first.id, box = holder.boxA }
            index = index + 1
        end
        set.rows[#set.rows + 1] = row
    end
    index = 1
    while index <= #toggles do
        rowIndex = rowIndex + 1
        local y = CONTROLS_TOP - (rowIndex - 1) * CONTROL_ROW_H
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
    set.height = rowIndex * CONTROL_ROW_H
    return set
end

local function SetControlSetShown(set, shown)
    if not set then return end
    for i = 1, #set.rows do
        if shown then set.rows[i]:Show() else set.rows[i]:Hide() end
    end
end

local function LayoutControls(key)
    local controls = External.GetControls and External.GetControls(key)
    local set
    if controls then
        frame._controlSets = frame._controlSets or {}
        local signature = ControlSignature(controls)
        set = frame._controlSets[signature]
        if not set then
            set = BuildControlSet(controls)
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

local function SyncControlValues(set, key)
    if not set then return end
    for i = 1, #set.numbers do
        local value = External.GetControlValue(key, set.numbers[i].id)
        Quick.SetBoxText(set.numbers[i].box, value ~= nil and value or "")
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

function Popup.Sync()
    if not (frame and frame._key) then return false end
    local label, group, settingsLabel, canSettings, canReset = External.GetDisplayInfo(frame._key)
    if not label then frame:Hide(); return false end
    frame._titleFS:SetText(label)
    frame._summaryFS:SetText(FormatValues(External.GetInspectorValues(frame._key)))
    local set = LayoutControls(frame._key)
    SyncControlValues(set, frame._key)
    local extra = set and set.height or 0
    frame._settingsBtn:ClearAllPoints()
    frame._settingsBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, BUTTONS_TOP - extra)
    frame._resetBtn:ClearAllPoints()
    frame._resetBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 284, BUTTONS_TOP - extra)
    frame:SetHeight(BASE_HEIGHT + extra)
    SetButtonText(frame._settingsBtn, settingsLabel or ("Open " .. tostring(group or label) .. " settings"))
    SetButtonEnabled(frame._settingsBtn, canSettings)
    SetButtonEnabled(frame._resetBtn, canReset)
    if frame._refreshUndoRedo then frame._refreshUndoRedo() end
    return true
end

function Popup.Open(key)
    if Blocked() or not External.GetRecord(key) then return false end
    Build()._key = key
    if not Popup.Sync() then return false end
    frame:Show()
    return true
end

function Popup.Close() if frame then frame:Hide() end end
function Popup.IsOpen() return frame and frame:IsShown() or false end
function Popup.GetKey() return frame and frame._key or nil end
function Popup.RefreshHistory() if frame and frame:IsShown() and frame._refreshUndoRedo then frame._refreshUndoRedo() end end
