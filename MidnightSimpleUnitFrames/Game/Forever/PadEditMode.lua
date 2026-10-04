-- MSUF Edit Mode and the menu's named popups on UIParent for the Forever gamepad
-- navigation (PadNavigation.lua). The mover layer is the Edit Mode window: its
-- HUD, group containers and aura groups join it as roots, and it starts on the
-- element Edit Mode has selected. A clicks like the mouse (a click without
-- movement opens the element's popup), Y or the right stick moves the selected
-- element through Edit Mode's own nudge router, LB/RB step to the previous/next
-- element, View jumps between the toolbar and the elements, and B leaves Edit
-- Mode like the HUD's Done. The button hints sit beside the toolbar. The MSUF
-- menu, which covers most of the screen, is minimized while the pad runs Edit
-- Mode; Start brings it back, and it returns by itself when Edit Mode ends.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PadNav = MSUF.PadNavigation
if not PadNav then return end
local Kit = PadNav.Kit

local GROUP_CONTAINERS = { "party", "raid", "mythicraid", "priority" }
local EDIT_POPUPS = {
    "MSUF_EM2_UnitPopup", "MSUF_EM2_ResourcePopup", "MSUF_EM2_CastPopup", "MSUF_EM2_AuraPopup",
    "MSUF_EM2_ExternalPopup", "MSUF_EM2_GFPopup_party", "MSUF_EM2_GFPopup_raid", "MSUF_EM2_GFPopup_mythicraid",
}
local MENU_POPUPS = {
    "MSUF_EM2_CancelConfirm", "MSUF_EM2_BlizzardLayoutDialog", "MSUF2LayerOverview", "MSUF_CopyLinkPopup",
    "MSUF_EM2_HUD_PositionPopup",
}
local EDIT_HINTS = {
    "PADLSHOULDER/PADRSHOULDER", "Previous / next element", "PADBACK", "Toolbar / elements", "PADFORWARD", "Menu",
}

local function EditModeRoots(list)
    local hud = _G.MSUF_EM2_HUD
    if type(hud) == "table" then list[#list + 1] = hud end
    for index = 1, #GROUP_CONTAINERS do
        local container = _G["MSUF_GF_Container_" .. GROUP_CONTAINERS[index]]
        if type(container) == "table" then list[#list + 1] = container end
    end
    local auras = MSUF.MSUF_Auras3
    local groups = type(auras) == "table" and type(auras.EditMode) == "table" and auras.EditMode.groups or nil
    if type(groups) ~= "table" then return end
    for _, byUnit in pairs(groups) do
        if type(byUnit) == "table" then
            for _, group in pairs(byUnit) do
                if type(group) == "table" and type(group.IsObjectType) == "function" then list[#list + 1] = group end
            end
        end
    end
end

local function EditMode()
    local editMode = _G.MSUF_EM2
    return type(editMode) == "table" and editMode or nil
end

local function ExitEditMode()
    local editMode = EditMode()
    if editMode and editMode.State and type(editMode.State.Exit) == "function" then editMode.State.Exit("hud_exit") end
end

local function NudgeEditMode(dx, dy)
    local editMode = EditMode()
    local nudge = editMode and editMode.Nudge and editMode.Nudge.By
    if type(nudge) == "function" then nudge(dx, dy) end
end

-- The Edit Mode key of a mover, a group container or a group preview frame.
local function ElementKey(control)
    if not control then return nil end
    local kind = control._msufGFEM2Kind
    local key = control._barKey or control.msufConfigKey or (type(kind) == "string" and "gf_" .. kind)
    return type(key) == "string" and key or nil
end

-- An aura group of Edit Mode's aura preview (Auras3/MSUF_Auras3_EditMode_Drag.lua).
local function AuraGroup(control)
    if control and control._msufA3Unit ~= nil and control._msufA3MoverKind ~= nil then return control end
    return nil
end

-- The selected element becomes Edit Mode's selection first, the way a click
-- selects it, but without opening its popup. An aura group moves through Edit
-- Mode's aura nudge, which otherwise needs the group's popup open.
local function NudgeEditElement(_, control, dx, dy)
    local editMode = EditMode()
    local aura = AuraGroup(control)
    if aura then
        local nudge = editMode and editMode.Nudge and editMode.Nudge.AuraBy
        if type(nudge) == "function" then nudge(aura._msufA3Unit, aura._msufA3MoverKind, dx, dy) end
        return
    end
    local key = ElementKey(control)
    local state = editMode and editMode.State
    if not (key and state) then return end
    if state.GetUnitKey() ~= key then
        if type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        state.SetUnitKey(key)
        if editMode.HUD and type(editMode.HUD.RefreshUnitSelector) == "function" then editMode.HUD.RefreshUnitSelector() end
        if editMode.Focus and type(editMode.Focus.SetSelection) == "function" then
            editMode.Focus.SetSelection(key, nil, nil, { source = "gamepad" })
        end
    end
    NudgeEditMode(dx, dy)
end

local function Movable(control)
    return ElementKey(control) ~= nil or AuraGroup(control) ~= nil
end

-- An open popup edits the element Edit Mode has selected.
local function NudgeEditPopup(_, _, dx, dy)
    NudgeEditMode(dx, dy)
end

-- A on an element opens its settings popup.
local function AcceptLabel(control)
    return Movable(control) and "Open settings" or nil
end

-- The mover of the element Edit Mode has selected, else the player frame's.
local function SelectedMover()
    local editMode = EditMode()
    local movers = editMode and editMode.Movers
    if not (editMode and editMode.State and type(movers) == "table" and type(movers.Get) == "function") then
        return nil
    end
    local key = editMode.State.GetUnitKey()
    return (type(key) == "string" and movers.Get(key)) or movers.Get("player")
end

local function Toolbar()
    local hud = _G.MSUF_EM2_HUD
    return type(hud) == "table" and hud:IsVisible() and hud or nil
end

-- The hints sit beside the toolbar and its second row, not at the screen's edge.
local function ToolbarAnchors(list)
    local hud = Toolbar()
    if not hud then return end
    list[#list + 1] = hud
    local row = _G.MSUF_EM2_HUD_Row2
    if type(row) == "table" and row:IsVisible() then list[#list + 1] = row end
end

-- LT held with LB/RB: Edit Mode's undo/redo (shared with the menu's history),
-- the toolbar's buttons repainted as their clicks do.
local function UndoRedo(redo)
    local editMode = EditMode()
    local undo = editMode and editMode.Undo
    local run = undo and (redo and undo.DoRedo or undo.DoUndo)
    if type(run) ~= "function" then return false end
    local done = run()
    if editMode.HUD and type(editMode.HUD.RefreshControls) == "function" then editMode.HUD.RefreshControls() end
    return done ~= false
end

-- View jumps between the toolbar and the elements, back to where it left each.
local spots = {}
local function JumpToolbar()
    local hud = Toolbar()
    local selection = PadNav.GetSelection()
    if hud and PadNav.IsSelectionIn(hud) then
        spots.toolbar = selection
        local mover = SelectedMover()
        if (spots.element and PadNav.SelectControl(spots.element)) or (mover and PadNav.SelectControl(mover)) then
            return
        end
    elseif hud and PadNav.SelectFirstIn(hud, spots.toolbar) then
        spots.element = selection
        return
    end
    Kit.Haptic("edge")
end

-- The MSUF menu (Shell/Menu2, loaded on demand) ------------------------------
local menuParked = false

local function Menu()
    local menu = MSUF.MSUF2
    return type(menu) == "table" and menu or nil
end

-- Start: the minimized menu comes back, an open one comes to the front, a
-- closed one opens. The menu window takes the pad again.
local function ShowMenu()
    local menu = Menu()
    menuParked = false
    if not menu then return false end
    local bar, frame = menu.minimizedBar, menu.frame
    if type(bar) == "table" and bar:IsShown() and type(menu.RestoreMinimizedSlashMenu) == "function" then
        menu.RestoreMinimizedSlashMenu()
    elseif type(frame) == "table" and frame:IsShown() then
        PadNav.Activate(frame)
        return true
    elseif type(menu.Open) == "function" then
        return menu.Open(menu.activeKey) ~= false
    else
        return false
    end
    if type(menu.ResumeForeverPadNavigation) == "function" then menu.ResumeForeverPadNavigation() end
    return true
end

local function StartButton()
    if not ShowMenu() then Kit.Haptic("edge") end
end

local function ParkMenu()
    local menu = Menu()
    local frame = menu and menu.frame
    if type(frame) ~= "table" or not frame:IsShown() or frame._msuf2Minimized then return end
    if type(menu.MinimizeSlashMenuWindow) == "function" then menuParked = menu.MinimizeSlashMenuWindow() == true end
end

-- Edit Mode hides its mover layer when it ends. The check waits a frame, so a
-- hidden interface (Alt+Z) is not taken for an exit; in combat the menu stays
-- on its title bar.
local function ReturnMenu()
    local editMode = EditMode()
    if not menuParked or (editMode and editMode.State and editMode.State.IsActive()) then return end
    if InCombatLockdown() then
        menuParked = false
        return
    end
    ShowMenu()
end

local function MoverLayerHidden()
    if menuParked then C_Timer.After(0, ReturnMenu) end
end

local hookedLayer
local function ActivateEditMode(moverParent)
    if hookedLayer ~= moverParent then
        hookedLayer = moverParent
        moverParent:HookScript("OnHide", MoverLayerHidden)
    end
    ParkMenu()
    return SelectedMover()
end

-- The toolbar's frame list (MSUF_EditMode_HUD_Picker.lua) has no name.
local function FramePicker()
    local editMode = EditMode()
    local dock = editMode and editMode.HUDDock
    local picker = type(dock) == "table" and dock.framePicker or nil
    return type(picker) == "table" and picker or nil
end

PadNav.Watch("MSUF_EM2_MoverParent", ExitEditMode, { PADBACK = JumpToolbar, PADFORWARD = StartButton }, {
    roots = EditModeRoots, nudge = NudgeEditElement, movable = Movable, cycle = true,
    backLabel = "Leave Edit Mode", acceptLabel = AcceptLabel, hints = EDIT_HINTS,
    promptAnchors = ToolbarAnchors, onActivate = ActivateEditMode,
    undo = function() return UndoRedo(false) end, redo = function() return UndoRedo(true) end,
})
for index = 1, #EDIT_POPUPS do
    PadNav.Watch(EDIT_POPUPS[index], nil, nil, { nudge = NudgeEditPopup })
end
for index = 1, #MENU_POPUPS do
    PadNav.Watch(MENU_POPUPS[index])
end
PadNav.Watch(FramePicker)

-- Anchor picker (Shell/UI/MSUF_AnchorPicker.lua) ----------------------------
-- With the mouse it anchors to the named frame under the pointer on
-- CTRL + click. With the pad, the D-pad walks the named frames on screen, LB/RB
-- step through frames stacked at the same spot (smallest first), A anchors
-- through the picker's own _isCandidateAllowed/_onPick and B cancels. The
-- candidates are collected once per open (UIParent's children three levels
-- deep, at most MAX_VISITS frames), never per frame.
local MAX_VISITS, MIN_SIZE, MAX_SHARE = 4000, 8, 0.9
local PICKER_PROMPTS = {
    "PADLSHOULDER/PADRSHOULDER", "Previous / next element", "PAD1", "Select", "PAD2", "Close",
}
local SKIPPED = { UIParent = true, WorldFrame = true }
local picker = { list = {}, current = nil }

local function PlainName(frame)
    local name = frame:GetName()
    local isSecret = _G.issecretvalue
    if type(name) ~= "string" or name == "" or (isSecret and isSecret(name)) then return nil end
    return name
end

-- Frames MSUF's own chrome or the picker itself; the picker never anchors to these.
local function OwnChrome(name)
    return SKIPPED[name] or name:find("^MSUF_AnchorPicker") or name:find("^MSUF_EM2_") or name:find("^MSUF2")
end

local function CollectCandidates(overlay)
    local list, visits = {}, 0
    local isForbidden = UIParent.IsForbidden
    local _, _, screenRight, screenTop = Kit.Rect(UIParent)
    local function Consider(frame, depth)
        visits = visits + 1
        if visits > MAX_VISITS or frame == overlay or (isForbidden and isForbidden(frame)) or not frame:IsVisible() then
            return
        end
        local name = PlainName(frame)
        if name and not OwnChrome(name) and rawget(frame, "unitToken") == nil then
            local left, bottom, right, top = Kit.Rect(frame)
            if left and right - left >= MIN_SIZE and top - bottom >= MIN_SIZE
                and right - left < screenRight * MAX_SHARE and top - bottom < screenTop * MAX_SHARE
            then
                list[#list + 1] = frame
            end
        end
        if depth < 3 and frame:GetNumChildren() > 0 then
            local children = { frame:GetChildren() }
            for index = 1, #children do Consider(children[index], depth + 1) end
        end
    end
    local roots = { UIParent:GetChildren() }
    for index = 1, #roots do Consider(roots[index], 1) end
    return list
end

-- The picker's own highlight and hover line show the pad's choice.
local function MarkCandidate(overlay, frame)
    picker.current = frame
    local highlight, hover = overlay._highlight, overlay._hover
    local left, bottom, right, top = Kit.Rect(frame)
    local scale = Kit.Plain(UIParent:GetEffectiveScale()) or 1
    if highlight and left then
        highlight:ClearAllPoints()
        highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / scale, bottom / scale)
        highlight:SetSize((right - left) / scale, (top - bottom) / scale)
        highlight:Show()
    end
    if hover and type(overlay._lHoverFmt) == "string" then hover:SetText(overlay._lHoverFmt:format(PlainName(frame) or "?")) end
end

local function Center(frame)
    local left, bottom, right, top = Kit.Rect(frame)
    if not left then return nil end
    return (left + right) * 0.5, (bottom + top) * 0.5
end

-- Candidates still shown with a readable size; frames can hide after the open.
local function LiveCandidates()
    local live = {}
    for index = 1, #picker.list do
        local frame = picker.list[index]
        if frame:IsVisible() and Kit.Rect(frame) then live[#live + 1] = frame end
    end
    return live
end

local function ActivatePicker(overlay)
    -- The picker's mouse hover loop would move its highlight to whatever is
    -- under the idle pointer; the picker sets it again on its next OnShow.
    overlay:SetScript("OnUpdate", nil)
    picker.list = CollectCandidates(overlay)
    picker.current = nil
    local sub, hint = overlay._sub, overlay._ctrlHint
    local L = MSUF.L
    local text = "Pick a frame with the D-pad, then press A to anchor it. B cancels."
    if sub then sub:SetText((L and L[text]) or text) end
    if hint then hint:SetText("") end
    -- Start at the screen centre; of frames sharing that spot, the smallest.
    local _, _, screenRight, screenTop = Kit.Rect(UIParent)
    if not screenRight then return end
    local best, bestDistance, bestArea
    local live = LiveCandidates()
    for index = 1, #live do
        local left, bottom, right, top = Kit.Rect(live[index])
        local dx, dy = (left + right - screenRight) * 0.5, (bottom + top - screenTop) * 0.5
        local distance, area = dx * dx + dy * dy, (right - left) * (top - bottom)
        if not best or distance < bestDistance or (distance == bestDistance and area < bestArea) then
            best, bestDistance, bestArea = live[index], distance, area
        end
    end
    if best then MarkCandidate(overlay, best) end
end

local function StepPicker(overlay, dx, dy)
    if not (picker.current and Kit.Rect(picker.current)) then
        ActivatePicker(overlay)
        return
    end
    local nextFrame = Kit.Pick(LiveCandidates(), picker.current, dx, dy)
    if nextFrame then MarkCandidate(overlay, nextFrame) else Kit.Haptic("edge") end
end

-- Frames containing the current one's centre, smallest first.
local function CyclePicker(overlay, direction)
    if not picker.current then return end
    local x, y = Center(picker.current)
    if not x then return end
    local stack, live = {}, LiveCandidates()
    for index = 1, #live do
        local frame = live[index]
        local left, bottom, right, top = Kit.Rect(frame)
        if left and x >= left and x <= right and y >= bottom and y <= top then
            stack[#stack + 1] = { frame = frame, area = (right - left) * (top - bottom) }
        end
    end
    if #stack < 2 then
        Kit.Haptic("edge")
        return
    end
    table.sort(stack, function(a, b) return a.area < b.area end)
    for index = 1, #stack do
        if stack[index].frame == picker.current then
            MarkCandidate(overlay, stack[(index - 1 + direction) % #stack + 1].frame)
            return
        end
    end
end

local function ConfirmPicker(overlay)
    local frame = picker.current
    local name = frame and PlainName(frame)
    if not name then return end
    if type(overlay._isCandidateAllowed) == "function" and overlay._isCandidateAllowed(frame, name) ~= true then
        if overlay._sub and type(overlay._lTargetNotAllowed) == "string" then overlay._sub:SetText(overlay._lTargetNotAllowed) end
        Kit.Haptic("edge")
        return
    end
    if type(overlay._onPick) == "function" then overlay._onPick(name) end
    overlay:Hide()
end

local function Step(dx, dy)
    return function(overlay) StepPicker(overlay, dx, dy) end
end

PadNav.Watch("MSUF_AnchorPickerOverlay", function(overlay) overlay:Hide() end, {
    PADDUP = Step(0, 1), PADDDOWN = Step(0, -1), PADDLEFT = Step(-1, 0), PADDRIGHT = Step(1, 0),
    PADLSHOULDER = function(overlay) CyclePicker(overlay, -1) end,
    PADRSHOULDER = function(overlay) CyclePicker(overlay, 1) end,
    PAD1 = ConfirmPicker,
    repeatable = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true },
}, { prompts = PICKER_PROMPTS, onActivate = ActivatePicker })
