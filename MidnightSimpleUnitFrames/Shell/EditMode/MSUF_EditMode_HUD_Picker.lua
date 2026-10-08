--- EditMode/MSUF_EditMode_HUD_Picker.lua - the toolbar's frame and settings pickers
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD, DockUI, Kit, Selection = EM2.HUD, EM2.HUDDock, EM2.HUDKit, EM2.HUDSelection
local TH, HelpText, W8, MakeFS = Kit.TH, Kit.HelpText, Kit.W8, Kit.MakeFS
local CurrentSelectionKey, BlockHUDConfigLocked = Selection.CurrentSelectionKey, Selection.BlockHUDConfigLocked
local LABEL_BY_KEY = Selection.LABEL_BY_KEY
local EnsureDockState = DockUI.EnsureDockState

--- Frame picker
---
--- Clicking a mover is the normal way to select something, but a frame that sits
--- underneath another one cannot be clicked at all - which leaves the user with no
--- way to move it back out. The toolbar's context button therefore opens this list
--- of every placeable element, so selection never depends on hitting a mover.
local PICKER_ROW_H = 24
local PICKER_WIDTH = 190

--- Rows for the picker: everything the Edit Mode registry can currently place.
--- Elements without a live frame have no mover on screen, so listing them would
--- offer a selection that cannot go anywhere.
local function FramePickerRows()
    local registry = EM2.Registry
    local rows = {}
    if not (registry and registry.Order) then return rows end
    local selected = CurrentSelectionKey()
    local keys = registry.Order()
    for i = 1, #keys do
        local key = keys[i]
        local cfg = registry.Get and registry.Get(key)
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        local enabled = not (cfg and cfg.isEnabled) or cfg.isEnabled() ~= false
        if cfg and frame and enabled then
            rows[#rows + 1] = {
                key = key,
                label = EM2.Util.ElementLabel(key, cfg),
                selected = key == selected,
            }
        end
    end
    return rows
end

local function SelectFrameFromPicker(key)
    if BlockHUDConfigLocked() then return end
    if not key then return end
    if EM2.State and EM2.State.SetUnitKey then EM2.State.SetUnitKey(key) end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = "hud-picker" })
    end
    --- Anchoring to the mover puts the popup next to the frame it edits, exactly
    --- like clicking the mover would.
    local mover = EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
    if EM2.Popups and EM2.Popups.Open then EM2.Popups.Open(key, mover) end
    if EM2.Focus and EM2.Focus.Pulse then
        EM2.Focus.Pulse(key, "frame", nil, { source = "hud-picker", duration = 0.32 })
    end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    HUD.SetStatus(string.format(HelpText("Selected %s"), EM2.Util.ElementLabel(key, cfg)), "ok")
    HUD.RefreshControls()
end

--- The inspector row's picker: jump straight into a frame's settings page and do
--- nothing else. No mover popup, no pulse - this is pure menu navigation, which is
--- what the row's chevron has always advertised.
local function OpenSettingsForKey(key)
    if BlockHUDConfigLocked() then return end
    if not key then return end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = "hud-menu-picker", openSettings = true })
    end
    local opener = (EM2.Focus and EM2.Focus.OpenFullSettings) or _G.MSUF_EM2_OpenFocusSettings
    if type(opener) == "function" and opener() then
        HUD.SetStatus(HelpText("Opened settings"), "ok")
    else
        HUD.SetStatus(HelpText("Settings unavailable"), "warn")
    end
    HUD.RefreshControls()
end

local function PositionFramePicker(picker, btn)
    picker:ClearAllPoints()
    local dock = EnsureDockState().dock
    if dock == "BOTTOM" then
        picker:SetPoint("BOTTOM", btn, "TOP", 0, 4)
    elseif dock == "LEFT" then
        picker:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, 0)
    elseif dock == "RIGHT" then
        picker:SetPoint("TOPRIGHT", btn, "TOPLEFT", -6, 0)
    else
        picker:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    end
end

--- One list frame serves both dropdowns; the owning button and the action to run
--- are set per open, so the toolbar picker and the inspector menu picker cannot be
--- on screen at once and share all chrome.
local function EnsureFramePicker()
    if DockUI.framePicker then return DockUI.framePicker end
    local picker = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, UIParent, "BackdropTemplate"))
    picker:SetFrameStrata("TOOLTIP")
    picker:SetFrameLevel(1300)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    DockUI.PixelLayoutRegion(picker, "SetBackdrop", { bgFile = W8, edgeFile = W8, edgeSize = 1,
                         insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    picker:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], 0.98)
    picker:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
    picker:Hide()
    picker._rows = {}
    --- Close once the pointer has left both the button and the list, the same
    --- forgiving behaviour the quick popups use for their small menus. The
    --- Forever gamepad navigation (Game/Forever/PadNavigation.lua) holds it open.
    picker:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        local owner = self._owner
        if self._msufPadHeld or (owner and owner:IsMouseOver()) or self:IsMouseOver() then
            self._closeAt = nil
        elseif not self._closeAt then
            self._closeAt = GetTime() + 0.4
        elseif GetTime() >= self._closeAt then
            self:Hide()
        end
    end)
    DockUI.framePicker = picker
    return picker
end

local function BuildFramePickerRows(picker)
    local rows = FramePickerRows()
    local widgets = picker._rows
    for i = 1, #rows do
        local data = rows[i]
        local item = widgets[i]
        if not item then
            item = DockUI.PixelLayoutRegion(CreateFrame("Button", nil, picker))
            item:SetSize(PICKER_WIDTH - 6, PICKER_ROW_H)
            item._bg = DockUI.PixelLayoutRegion(item:CreateTexture(nil, "BACKGROUND"))
            item._bg:SetAllPoints()
            item._fs = MakeFS(item, "caption", TH.textR, TH.textG, TH.textB, 0.94)
            --- Both edges anchored plus no wrapping: a long localized label is
            --- truncated inside its row instead of spilling out of the list.
            item._fs:SetPoint("LEFT", item, "LEFT", 9, 0)
            item._fs:SetPoint("RIGHT", item, "RIGHT", -8, 0)
            item._fs:SetJustifyH("LEFT")
            item._fs:SetWordWrap(false)
            local hl = DockUI.PixelLayoutRegion(item:CreateTexture(nil, "HIGHLIGHT"))
            hl:SetAllPoints()
            hl:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.18)
            item:SetScript("OnClick", function(self)
                local action = picker._onPick
                picker:Hide()
                if action then action(self._msufKey) end
            end)
            widgets[i] = item
        end
        item:SetPoint("TOPLEFT", picker, "TOPLEFT", 3, -(3 + (i - 1) * PICKER_ROW_H))
        item._msufKey = data.key
        item._fs:SetText(data.label)
        if data.selected then
            item._bg:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.16)
            item._fs:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
        else
            item._bg:SetColorTexture(0, 0, 0, 0)
            item._fs:SetTextColor(TH.textR, TH.textG, TH.textB, 0.94)
        end
        item:Show()
    end
    for i = #rows + 1, #widgets do widgets[i]:Hide() end
    picker:SetSize(PICKER_WIDTH, math.max(PICKER_ROW_H, #rows * PICKER_ROW_H) + 6)
    return #rows
end

local function TogglePicker(owner, onPick)
    if not owner then return end
    local picker = EnsureFramePicker()
    --- Clicking the button that already owns the open list closes it; clicking the
    --- other one hands the list over instead of stacking a second menu.
    if picker:IsShown() then
        picker:Hide()
        if picker._owner == owner then return end
    end
    picker._owner, picker._onPick = owner, onPick
    if BuildFramePickerRows(picker) == 0 then
        HUD.SetStatus(HelpText("No frames to select"), "warn")
        return
    end
    picker._closeAt = nil
    PositionFramePicker(picker, owner)
    picker:Show()
end

--- Reached through HUD: the toolbar buttons, its refresh and HUD.Hide call
--- these.
function HUD.ToggleFramePicker()
    TogglePicker(DockUI.contextBtn, SelectFrameFromPicker)
end

--- The inspector row's chevron: choose which settings page to open, nothing else.
function HUD.ToggleMenuPicker()
    TogglePicker(DockUI.inspectorSelection, OpenSettingsForKey)
end

--- Re-renders the open list so its highlight follows the current selection.
function HUD.RefreshFramePicker()
    local picker = DockUI.framePicker
    if picker and picker:IsShown() then BuildFramePickerRows(picker) end
end

function HUD.CloseFramePicker()
    if DockUI.framePicker then DockUI.framePicker:Hide() end
end
