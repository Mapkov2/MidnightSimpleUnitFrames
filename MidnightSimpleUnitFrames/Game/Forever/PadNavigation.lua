-- Gamepad navigation for MSUF and MSUF Suite windows on WoW Forever's Gamepad UI.
-- Reference: upstream/forever Blizzard_GamepadSharedUtility (FrameControlsManager,
-- InputFunctionBinding, InputAxisBinding) and Blizzard_GamepadSmartNavigation.
--
-- Blizzard's frame controls manager and SmartNavigation keep shared state, and
-- they re-bind the face buttons with closures created in the caller's context.
-- A window registered there from addon code (FrameShown/FrameHidden) leaves that
-- state tainted, so spellbook casts and SetPreferredGamepadInteractTarget are
-- blocked until a reload. SmartNavigation also rescans the whole window on every
-- CreateFrame below it, which froze the client for seconds while a page was built.
--
-- This module never calls either system. One MSUF-owned frame takes the D-pad
-- and face buttons while an attached window is on top, out of combat, and while
-- no Blizzard panel holds SmartNavigation. Controls are found on demand, once
-- per press, with SmartNavigation's rule (buttons, edit boxes, sliders, frames
-- with mouse scripts), so building a page costs nothing. Companion files:
-- PadKeyboard.lua (on-screen keyboard), PadPrompts.lua (button hints) and
-- PadEditMode.lua (Edit Mode and popups on UIParent). Only a 4 Hz name check
-- runs while the Gamepad UI is off.
--
-- Buttons: D-pad moves (a slider's value on left/right, faster while held), A
-- presses (a slider: types its exact value), B goes back, X right-clicks, Y moves
-- the selected preview handle or Edit Mode element (then the D-pad moves it by
-- 1 px and LB/RB pick the previous/next element) or else opens the window's
-- search, LB/RB jump a page in a scrolling list, LT/RT switch between open MSUF
-- windows and, held with LB/RB, undo/redo, the right stick moves or scrolls, a
-- right stick press shows or hides tooltips.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...)
    if type(policy) == "string" then return region[policy](region, ...) end
    return region
end

local PadNav = {}
MSUF.PadNavigation = PadNav
_G.MSUF_PadNavigation = PadNav

local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local REPEAT_DELAY, REPEAT_RATE, MOVE_REPEAT_RATE, POLL_INTERVAL = 0.35, 0.09, 0.05, 0.25
-- The ring, the hint bar and the keyboard sit in TOOLTIP above every MSUF frame
-- there: the Edit Mode toolbar and its lists use levels up to 1500.
local SCROLL_MARGIN, RING_PAD, RING_EDGE, RING_LEVEL = 12, 3, 2, 9000
local RING_COLOR, MOVE_COLOR = { 0.22, 0.78, 0.94, 1 }, { 1, 0.62, 0.15, 1 }
-- Right stick: nudge rates ramp from the first to the second value over
-- RAMP_TIME seconds held (pixels per second for exact nudges, presses per
-- second for arrow-key previews), at most one emission per NUDGE_INTERVAL so
-- the previews' 0.02 s duplicate guard never drops one.
local STICK_DEADZONE, RAMP_TIME, NUDGE_INTERVAL = 0.25, 1.2, 0.026
local PIXEL_RATE, PIXEL_RATE_MAX, STEP_RATE, STEP_RATE_MAX = 40, 360, 10, 36
-- A window's own stepper (the keyboard walks its field's match list) runs
-- slower; scrolling ramps up the same way.
local LIST_RATE, LIST_RATE_MAX = 7, 16
local SCROLL_RATE_MIN, SCROLL_RATE, SCROLL_SETTLE = 400, 900, 0.15
-- Button names from Blizzard_SharedXML GamepadConstants. OnGamePadStick names
-- the right stick "Right" (SoftCursor's default input stick) and by its
-- binding role "Camera" (InputAxisBinding); "Look" is the other right-stick role.
local STEPS = { PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 } }
local ACCEPT, ALTERNATE, BACK, MENU = "PAD1", "PAD3", "PAD2", "PADFORWARD"
local MOVE, TOOLTIP_TOGGLE = "PAD4", "PADRSTICK"
local CYCLE = { PADLTRIGGER = -1, PADRTRIGGER = 1 }
local SHOULDER = { PADLSHOULDER = -1, PADRSHOULDER = 1 }
local NUDGE_STICKS = { Right = true, Camera = true, Look = true }

local scopes = {}
local weakKeys = { __mode = "k" }
local backHandlers = setmetatable({}, weakKeys)
local scopeActions = setmetatable({}, weakKeys)
local scopeOptions = setmetatable({}, weakKeys)
local attached = setmetatable({}, weakKeys)
local tracked = setmetatable({}, weakKeys)
local lastSelection = setmetatable({}, weakKeys)
local watches, rootList, promptList, anchorList = {}, {}, {}, {}
local input, ring
local capturing, inCombat, moveMode, tooltipsHidden = false, false, false, false
local current, heldButton, heldElapsed, heldTime = nil, nil, 0, 0
-- A trigger held for LB/RB undo/redo; it switches windows on release unless used.
local heldTrigger, triggerUsed = nil, false
local stickX, stickY, nudgeX, nudgeY, nudgeWait, stickHeld, settleWait = 0, 0, 0, 0, 0, 0, 0

local function PadUIEnabled()
    local util = _G.InputUtil
    return util ~= nil and type(util.IsGamepadUIEnabled) == "function" and util.IsGamepadUIEnabled() == true
end

-- A Blizzard panel focused by the frame controls manager shows SmartNavigation;
-- its own bindings then own the pad until that panel closes.
local function BlizzardNavigationActive()
    local navigation = _G.SmartNavigation
    return navigation ~= nil and type(navigation.IsShown) == "function" and navigation:IsShown() == true
end

-- Geometry can be secret on Midnight-era clients; such a value is never used.
local function Plain(value)
    if type(value) ~= "number" then return nil end
    local isSecret = _G.issecretvalue
    if isSecret and isSecret(value) then return nil end
    return value
end

-- Frames are created without a parent and re-parented afterwards: SmartNavigation
-- post-hooks CreateFrame and rescans the parent's panel in the caller's context.
local function CreateUnhookedFrame(frameType, parent)
    local frame = PixelLayoutRegion(CreateFrame(frameType))
    frame:SetParent(parent)
    return frame
end

local function Rect(frame)
    local left, bottom, width, height = frame:GetRect()
    left, bottom, width, height = Plain(left), Plain(bottom), Plain(width), Plain(height)
    local scale = Plain(frame:GetEffectiveScale())
    if not (left and bottom and width and height and scale) or width <= 1 or height <= 1 then return nil end
    return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end

local function IsInside(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame:GetParent()
    end
    return false
end

-- A window may name extra root frames that belong to it (the Edit Mode HUD,
-- group containers and aura groups sit on UIParent beside the movers).
local function Roots(scope)
    local options = scopeOptions[scope]
    local provider = options and options.roots
    if type(provider) ~= "function" then return nil end
    for index = #rootList, 1, -1 do rootList[index] = nil end
    provider(rootList)
    return rootList
end

local function InScope(frame, scope)
    if not (frame and scope) then return false end
    if IsInside(frame, scope) then return true end
    local roots = Roots(scope)
    if not roots then return false end
    for index = 1, #roots do
        if IsInside(frame, roots[index]) then return true end
    end
    return false
end

local function IsControl(frame)
    if frame:IsObjectType("Button") or frame:IsObjectType("EditBox") or frame:IsObjectType("Slider") then
        return true
    end
    return frame:GetScript("OnMouseDown") ~= nil or frame:GetScript("OnMouseUp") ~= nil
end

local function Reachable(frame)
    if not (frame and frame:IsVisible() and frame:IsMouseEnabled()) then return false end
    local alpha = Plain(frame:GetEffectiveAlpha())
    return alpha ~= nil and alpha > 0.05 and Rect(frame) ~= nil
end

local function Usable(frame, scope)
    return Reachable(frame) and InScope(frame, scope)
end

local function Collect(frame, list)
    if frame.smartNavigationIgnored == true or frame._msufPadIgnore == true then return end
    if frame:GetNumChildren() == 0 then return end
    local children = { frame:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if child:IsShown() then
            if IsControl(child) and Reachable(child) then list[#list + 1] = child end
            Collect(child, list)
        end
    end
end

local function Controls(scope)
    local list = {}
    Collect(scope, list)
    local roots = Roots(scope)
    for index = 1, roots and #roots or 0 do
        local root = roots[index]
        if root:IsShown() and not (root.smartNavigationIgnored == true or root._msufPadIgnore == true) then
            if IsControl(root) and Reachable(root) then list[#list + 1] = root end
            Collect(root, list)
        end
    end
    return list
end

local function RunScript(frame, script, ...)
    if not (frame and frame:HasScript(script)) then return end
    local execute = _G.ExecuteFrameScript
    if type(execute) == "function" then
        execute(frame, script, ...)
        return
    end
    local handler = frame:GetScript(script)
    if handler then handler(frame, ...) end
end

local function AddBorder(frame, color, edge)
    local sides = {
        { "TOPLEFT", "TOPRIGHT", nil, edge },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, edge },
        { "TOPLEFT", "BOTTOMLEFT", edge, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", edge, nil },
    }
    local textures = {}
    for index = 1, #sides do
        local side = sides[index]
        local texture = PixelLayoutRegion(frame:CreateTexture(nil, "OVERLAY"))
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
        texture:SetPoint(side[1])
        texture:SetPoint(side[2])
        if side[3] then texture:SetWidth(side[3]) else texture:SetHeight(side[4]) end
        textures[index] = texture
    end
    return textures
end

-- The selection: a ring around the control and Blizzard's gamepad pointer
-- beside it (SmartNavigationPointerTemplate: the hand atlas bobbing 4 px).
local function EnsureRing()
    if ring then return ring end
    ring = CreateUnhookedFrame("Frame", UIParent)
    ring:SetFrameStrata("TOOLTIP")
    ring:SetFrameLevel(RING_LEVEL)
    ring:EnableMouse(false)
    ring.edges = AddBorder(ring, RING_COLOR, RING_EDGE)
    local pointer = CreateUnhookedFrame("Frame", ring)
    pointer:SetSize(28, 28)
    pointer:SetPoint("RIGHT", ring, "LEFT", 4, 0)
    local hand = PixelLayoutRegion(pointer:CreateTexture(nil, "OVERLAY"))
    hand:SetAtlas("gamepad-largecursor-white")
    hand:SetAllPoints()
    local color = _G.GAMEPAD_SMARTNAV_CURSOR_COLOR
    if type(color) == "table" and type(color.GetRGBA) == "function" then hand:SetVertexColor(color:GetRGBA()) end
    local bob = pointer:CreateAnimationGroup()
    bob:SetLooping("REPEAT")
    for index, offset in ipairs({ 4, -4 }) do
        local step = bob:CreateAnimation("Translation")
        step:SetOffset(offset, 0)
        step:SetDuration(1)
        step:SetOrder(index)
        step:SetSmoothing("IN_OUT")
    end
    bob:Play()
    ring:Hide()
    return ring
end

local function PaintRing()
    if not ring then return end
    local color = moveMode and MOVE_COLOR or RING_COLOR
    for index = 1, #ring.edges do
        ring.edges[index]:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

-- Menu2's scroll frames keep an accessible copy of their range; the native
-- range can be secret there.
local function ScrollRange(scroll)
    return Plain(scroll:GetVerticalScrollRange()) or Plain(scroll._msuf2MaxScroll)
end

-- A scroll frame with Menu2's smooth scroll (_msuf2ScrollTo, the dropdown
-- list) glides to the offset like its mouse wheel does; any other one jumps.
-- Menu2's wheel animation keeps its goal in _msuf2SmoothScrollTarget: a jump
-- drops it so an animation in flight does not pull the view back.
local function ScrollTo(scroll, offset)
    local glide = scroll._msuf2ScrollTo
    if type(glide) == "function" then
        glide(offset)
        return
    end
    scroll._msuf2SmoothScrollTarget = nil
    scroll:SetVerticalScroll(offset)
end

-- Where a gliding scroll frame lands: its animation goal, else where it is.
local function ScrollGoal(scroll, offset)
    return type(scroll._msuf2ScrollTo) == "function" and Plain(scroll._msuf2SmoothScrollTarget) or offset
end

local function ScrollIntoView(control)
    local scroll = control:GetParent()
    while scroll do
        if scroll:IsObjectType("ScrollFrame") then
            local _, bottom, _, top = Rect(scroll)
            local _, controlBottom, _, controlTop = Rect(control)
            local range, offset = ScrollRange(scroll), Plain(scroll:GetVerticalScroll())
            local scale = Plain(scroll:GetEffectiveScale())
            if bottom and controlBottom and range and offset and scale then
                -- The control's edges once a glide in flight has landed.
                local goal = ScrollGoal(scroll, offset)
                local shift = (goal - offset) * scale
                local delta = 0
                if controlTop + shift > top - SCROLL_MARGIN then
                    delta = top - SCROLL_MARGIN - controlTop - shift
                elseif controlBottom + shift < bottom + SCROLL_MARGIN then
                    delta = bottom + SCROLL_MARGIN - controlBottom - shift
                end
                if delta ~= 0 then ScrollTo(scroll, max(0, min(range, goal + delta / scale))) end
            end
        end
        scroll = scroll:GetParent()
    end
end

-- The innermost scroll frame around a control that can scroll at all.
local function ScrollFrameOf(control)
    local scroll = control and control:GetParent()
    while scroll do
        if scroll:IsObjectType("ScrollFrame") then
            local range = ScrollRange(scroll)
            if range and range > 0 then return scroll end
        end
        scroll = scroll:GetParent()
    end
    return nil
end

-- The +/- buttons of a preview's selection bar (Menu2 PreviewSelectionBar),
-- for previews without arrow keys (the Suite's Cooldown Manager preview).
local function StepBar(box)
    local bar = box._msuf2SelectionBar
    local axisX, axisY = type(bar) == "table" and bar.axisX, type(bar) == "table" and bar.axisY
    if type(axisX) == "table" and type(axisY) == "table" and axisX.plusButton and axisX.minusButton
        and axisY.plusButton and axisY.minusButton
    then
        return bar
    end
    return nil
end

-- A preview box holds its selected handle as _selectedHandle.
local function PreviewBox(control)
    local box = control and control:GetParent()
    while box do
        if box._selectedHandle == control then return box end
        box = box:GetParent()
    end
    return nil
end

-- The preview box (Menu2 PreviewSelectionBar) around a control: its element
-- handles, the selection bar with the X/Y fields and the layer chips all sit
-- inside it.
local function PreviewOwner(control)
    local box = control and control:GetParent()
    while box do
        if box._msuf2SelectionBar ~= nil then return box end
        box = box:GetParent()
    end
    return nil
end

-- One of the preview's element handles (its selection deps' HandleList), not a
-- chip or a button of the bar.
local function IsPreviewHandle(box, control)
    local deps = box._msuf2SelectionDeps
    local list = type(deps) == "table" and type(deps.HandleList) == "function" and deps.HandleList(box) or nil
    for index = 1, type(list) == "table" and #list or 0 do
        if list[index] == control then return true end
    end
    return false
end

local TopScope

-- How the selection moves: a control's own _msufPadNudge, a preview's selected
-- handle through its arrow keys or else its selection bar's +/- buttons, or
-- the window's nudge (Edit Mode). Anywhere inside a preview box (the bar, its
-- X/Y fields, the layer chips) the preview's selected element moves, the way
-- Edit Mode moves its selection. Nil when the selection cannot move.
local function NudgeMode()
    local control = current
    if not control then return nil end
    if type(control._msufPadNudge) == "function" then return "own" end
    local box = PreviewBox(control) or PreviewOwner(control)
    if box then
        local handle = box._selectedHandle
        if not (handle and handle:IsVisible()) then return nil end
        if handle:GetScript("OnKeyDown") then return "arrows", handle end
        if box:GetScript("OnKeyDown") then return "arrows", box end
        local bar = StepBar(box)
        if bar then return "bar", bar end
        return nil
    end
    local scope = TopScope()
    local options = scope and scopeOptions[scope]
    if options and type(options.stepper) == "function"
        and (type(options.stepperActive) ~= "function" or options.stepperActive(scope))
    then
        return "steps", scope
    end
    if options and type(options.nudge) == "function"
        and (type(options.movable) ~= "function" or options.movable(control))
    then
        return "window", scope
    end
    return nil
end

local UpdateMotor, Select, RefreshPrompts

local function MuteTooltip(control)
    local tooltip = _G.GameTooltip
    if tooltipsHidden and tooltip and tooltip:IsOwned(control) then tooltip:Hide() end
end

function Select(control)
    if control == current then return end
    local previous = current
    current = control
    if previous then RunScript(previous, "OnLeave") end
    if moveMode and not NudgeMode() then moveMode = false end
    UpdateMotor()
    if not control then
        if ring then ring:Hide() end
        RefreshPrompts()
        return
    end
    ScrollIntoView(control)
    local frame = EnsureRing()
    PaintRing()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", control, "TOPLEFT", -RING_PAD, RING_PAD)
    frame:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", RING_PAD, -RING_PAD)
    frame:Show()
    RunScript(control, "OnEnter", false)
    MuteTooltip(control)
    RefreshPrompts()
end

-- Reading order: top-most row first, then left to right.
local function Before(a, b)
    local aLeft, _, _, aTop = Rect(a)
    local bLeft, _, _, bTop = Rect(b)
    if abs(aTop - bTop) > 8 then return aTop > bTop end
    return aLeft < bLeft
end

local function FirstControl(list)
    local best
    for index = 1, #list do
        if not best or Before(list[index], best) then best = list[index] end
    end
    return best
end

local function Nearest(list, x, y)
    local best, bestDistance
    for index = 1, #list do
        local left, bottom, right, top = Rect(list[index])
        local dx, dy = (left + right) * 0.5 - x, (bottom + top) * 0.5 - y
        local distance = dx * dx + dy * dy
        if not best or distance < bestDistance then best, bestDistance = list[index], distance end
    end
    return best
end

-- The next control in one direction: its centre must lie past this control's
-- centre, and a control that shares this one's column (or row) beats a closer
-- one beside it.
local function Pick(list, from, dx, dy)
    local fromLeft, fromBottom, fromRight, fromTop = Rect(from)
    if not fromLeft then return nil end
    local fromX, fromY = (fromLeft + fromRight) * 0.5, (fromBottom + fromTop) * 0.5
    local extent = dx ~= 0 and (fromRight - fromLeft) or (fromTop - fromBottom)
    local threshold = max(2, extent * 0.3)
    local best, bestScore
    for index = 1, #list do
        local control = list[index]
        if control ~= from then
            local left, bottom, right, top = Rect(control)
            local x, y = (left + right) * 0.5, (bottom + top) * 0.5
            local primary, gap, drift
            if dx ~= 0 then
                primary = (x - fromX) * dx
                gap = max(0, max(bottom, fromBottom) - min(top, fromTop))
                drift = abs(y - fromY)
            else
                primary = (y - fromY) * dy
                gap = max(0, max(left, fromLeft) - min(right, fromRight))
                drift = abs(x - fromX)
            end
            if primary > threshold then
                local score = primary + gap * 3 + drift * 0.1
                if not best or score < bestScore then best, bestScore = control, score end
            end
        end
    end
    return best
end

function TopScope()
    for index = #scopes, 1, -1 do
        local frame = scopes[index]
        if not frame:IsShown() then
            frame._msufPadHeld = nil
            table.remove(scopes, index)
        elseif frame:IsVisible() then
            return frame
        end
    end
end

local function VisibleScopeCount()
    local count = 0
    for index = 1, #scopes do
        if scopes[index]:IsVisible() then count = count + 1 end
    end
    return count
end

local function Validate(scope)
    if Usable(current, scope) then return end
    local remembered = lastSelection[scope]
    if Usable(remembered, scope) then
        Select(remembered)
        return
    end
    -- A press that hid the selected control (a page switch, a collapsed
    -- section) keeps the selection where the ring was.
    local list, x, y = Controls(scope), nil, nil
    if current and ring and ring:IsShown() then
        local left, bottom, right, top = Rect(ring)
        if left then x, y = (left + right) * 0.5, (bottom + top) * 0.5 end
    end
    Select(x and Nearest(list, x, y) or FirstControl(list))
end

-- Short rumbles as feedback: a light tick per step, a firmer one per press,
-- the strongest where the D-pad finds nothing further or move mode toggles.
-- { motor, intensity, seconds }. C_Timer.After takes only a Lua callback.
local HAPTICS = {
    step = { "Low", 0.12, 0.03 }, press = { "High", 0.25, 0.05 },
    edge = { "High", 0.45, 0.09 }, mode = { "High", 0.35, 0.08 },
}
local rumbleEnds = 0

local function StopRumble()
    local pad = _G.C_GamePad
    if pad and type(pad.StopVibration) == "function" and GetTime() + 0.005 >= rumbleEnds then pad.StopVibration() end
end

local function Haptic(kind)
    local pad, spec = _G.C_GamePad, HAPTICS[kind]
    if not (spec and pad and type(pad.SetVibration) == "function") then return end
    pad.SetVibration(spec[1], spec[2])
    rumbleEnds = GetTime() + spec[3]
    C_Timer.After(spec[3], StopRumble)
end

local function Bump()
    Haptic("edge")
end

-- A click anywhere else ends text editing; emulated presses do not do that
-- natively. MSUF previews refuse arrow nudges while a text field has focus.
local function ReleaseTextFocus(except)
    local focus = type(_G.GetCurrentKeyBoardFocus) == "function" and _G.GetCurrentKeyBoardFocus() or nil
    local keyboard = PadNav.Keyboard
    -- The keyboard types into its field; its own keys never end the editing.
    if focus and focus ~= except and focus ~= (keyboard and keyboard.target)
        and focus.IsObjectType and focus:IsObjectType("EditBox")
    then
        focus:ClearFocus()
    end
end

local function PressArrows(target, stepX, stepY)
    if stepX ~= 0 then RunScript(target, "OnKeyDown", stepX > 0 and "RIGHT" or "LEFT") end
    if stepY ~= 0 then RunScript(target, "OnKeyDown", stepY > 0 and "UP" or "DOWN") end
end

local function PressBar(bar, stepX, stepY)
    if stepX ~= 0 then bar.axisX[stepX > 0 and "plusButton" or "minusButton"]:Click("LeftButton") end
    if stepY ~= 0 then bar.axisY[stepY > 0 and "plusButton" or "minusButton"]:Click("LeftButton") end
end

local function NudgeBy(mode, target, stepX, stepY)
    if mode == "own" then
        current._msufPadNudge(current, stepX, stepY)
    elseif mode == "arrows" then
        ReleaseTextFocus()
        PressArrows(target, stepX, stepY)
    elseif mode == "bar" then
        ReleaseTextFocus()
        PressBar(target, stepX, stepY)
    elseif mode == "steps" then
        scopeOptions[target].stepper(target, stepX, stepY)
    else
        scopeOptions[target].nudge(target, current, stepX, stepY)
    end
end

local function Move(scope, button)
    local step = STEPS[button]
    if moveMode then
        local mode, target = NudgeMode()
        if mode then
            NudgeBy(mode, target, step[1], step[2])
            Haptic("step")
            return
        end
        moveMode = false
    end
    if current and current:IsObjectType("Slider") and step[1] ~= 0 then
        -- Held, the steps grow (x3 after 0.6 s, x8 after 1.5 s) where the range
        -- has room for 25 of them; a tick per step, a bump at the end.
        local low, high = current:GetMinMaxValues()
        low, high = Plain(low), Plain(high)
        local valueStep = Plain(current:GetValueStep()) or 1
        if valueStep <= 0 then valueStep = 1 end
        local value = Plain(current:GetValue()) or 0
        local boost = heldTime < 0.6 and 1 or heldTime < 1.5 and 3 or 8
        if low and high then boost = max(1, min(boost, floor((high - low) / valueStep / 25))) end
        local nextValue = value + step[1] * valueStep * boost
        nextValue = max(low or nextValue, min(high or nextValue, nextValue))
        if nextValue == value then
            if heldTime == 0 then Bump() end
        else
            current:SetValue(nextValue)
            Haptic("step")
        end
        return
    end
    if not Usable(current, scope) then
        Validate(scope)
        return
    end
    local target = Pick(Controls(scope), current, step[1], step[2])
    if target then
        Select(target)
        Haptic("step")
    else
        Bump()
    end
end

local function SetMoveMode(enabled)
    moveMode = enabled == true and NudgeMode() ~= nil
    PaintRing()
    UpdateMotor()
    Haptic("mode")
end

-- A preview handle the preview has not selected yet: Y selects it the way a
-- click does (the box takes it as _selectedHandle), so it can move at once.
-- Only element handles are clicked, never a chip or a bar button (Reset). An
-- aura icon of the unit preview forwards its clicks to its element's handle
-- (_msufDragProxyHandle); Y selects that handle.
local function SelectPreviewHandle(control)
    local box = PreviewOwner(control)
    if not box then return false end
    local proxied = control._msufDragProxyHandle
    local handle = IsPreviewHandle(box, control) and control or (IsPreviewHandle(box, proxied) and proxied) or nil
    if not handle or not handle:IsObjectType("Button") or type(handle.MouseDown) ~= "function" then
        return false
    end
    handle:MouseDown("LeftButton")
    handle:MouseUp("LeftButton")
    return NudgeMode() ~= nil
end

local function Accept(scope, mouseButton)
    if moveMode then
        SetMoveMode(false)
        return
    end
    local control = current
    if not Usable(control, scope) then
        Validate(scope)
        return
    end
    ReleaseTextFocus(control)
    Haptic("press")
    if control:IsObjectType("EditBox") then
        local keyboard = PadNav.Keyboard
        if keyboard and not (control.IsEnabled and not control:IsEnabled()) then keyboard.Open(control) end
        return
    end
    if control:IsObjectType("Slider") then
        -- A Menu2 slider's value box (W.Slider's editBox) takes an exact value.
        local box, keyboard = control.editBox, PadNav.Keyboard
        if keyboard and type(box) == "table" and box.IsObjectType and box:IsObjectType("EditBox")
            and box:IsVisible() and not (box.IsEnabled and not box:IsEnabled())
        then
            keyboard.Open(box)
        end
        return
    end
    if control.IsEnabled and not control:IsEnabled() then return end
    if type(control.MouseDown) == "function" then
        control:MouseDown(mouseButton)
        control:MouseUp(mouseButton)
    elseif control:IsObjectType("Button") then
        control:Click(mouseButton)
    end
    -- An Edit Mode popup's dropdown (Quick.MenuButtonAt) opens its list on
    -- UIParent; the list takes the pad until it closes.
    local menu = control._menu
    if type(menu) == "table" and type(menu.IsShown) == "function" and menu:IsShown() then
        PadNav.Attach(menu)
        PadNav.Activate(menu)
    end
end

-- A window's own close path when it has one (the colour picker's Finish hides
-- its full-screen click catcher too), else Hide.
local function CloseWindow(frame)
    if type(frame.Finish) == "function" then
        frame:Finish(true)
    elseif type(frame.Close) == "function" then
        frame:Close()
    else
        frame:Hide()
    end
end

local function TextFocus(scope)
    local focus = type(_G.GetCurrentKeyBoardFocus) == "function" and _G.GetCurrentKeyBoardFocus() or nil
    if focus and focus.IsObjectType and focus:IsObjectType("EditBox") and InScope(focus, scope) then return focus end
    return nil
end

local function Back(scope)
    if moveMode then
        SetMoveMode(false)
        return
    end
    local focus = TextFocus(scope)
    if focus then
        focus:ClearFocus()
        return
    end
    local handler = backHandlers[scope] or scope.SmartNavigationCloseHandler
    if type(handler) == "function" then
        handler(scope)
    else
        CloseWindow(scope)
    end
end

-- LB/RB while moving (and always in a window with options.cycle): the
-- preview's own element order (Tab), else the window's movable controls in
-- reading order. True when the selection went to an element.
local function CycleElement(scope, direction)
    local box = PreviewBox(current) or PreviewOwner(current)
    local menu = _G.MSUF2
    local bar = box and type(menu) == "table" and menu.PreviewSelectionBar
    if bar and type(bar.CycleHandle) == "function" then
        bar.CycleHandle(box, direction < 0)
        if Usable(box._selectedHandle, scope) then Select(box._selectedHandle) end
        return true
    end
    local options = scopeOptions[scope]
    local movable = options and options.movable
    if type(movable) ~= "function" then return false end
    local list, kept = Controls(scope), {}
    for index = 1, #list do
        if movable(list[index]) then kept[#kept + 1] = list[index] end
    end
    table.sort(kept, Before)
    for index = 1, #kept do
        if kept[index] == current then
            local nextControl = kept[(index - 1 + direction) % #kept + 1]
            if nextControl then Select(nextControl) end
            return #kept > 1
        end
    end
    if kept[1] then Select(kept[1]) end
    return kept[1] ~= nil
end

local function ToggleTooltips()
    tooltipsHidden = not tooltipsHidden
    if tooltipsHidden then
        MuteTooltip(current)
    elseif current then
        RunScript(current, "OnEnter", false)
    end
end

-- LT/RT bring the next open MSUF window to the front (the menu stays open
-- during Edit Mode), like Blizzard's own window cycling.
local function CycleScopes(direction)
    local top = TopScope()
    if not top or VisibleScopeCount() < 2 then return end
    if current and InScope(current, top) then lastSelection[top] = current end
    if direction > 0 then
        for index = #scopes, 1, -1 do
            if scopes[index] == top then table.remove(scopes, index) end
        end
        table.insert(scopes, 1, top)
    else
        local bottom = table.remove(scopes, 1)
        scopes[#scopes + 1] = bottom
    end
    moveMode = false
    Select(nil)
end

local UpdateCapture, CheckWatches

-- LB/RB in a scrolling list (a dropdown) jump a page: to the control about a
-- view height above or below, which the list then glides to.
local function PageJump(scope, direction)
    local scroll = ScrollFrameOf(current)
    if not scroll then return false end
    local _, bottom, _, top = Rect(scroll)
    local left, controlBottom, right, controlTop = Rect(current)
    if not (bottom and left) then return false end
    local y = (controlBottom + controlTop) * 0.5
    local list, ahead = Controls(scope), {}
    for index = 1, #list do
        local control = list[index]
        if control ~= current and IsInside(control, scroll) then
            local _, cBottom, _, cTop = Rect(control)
            local cy = (cBottom + cTop) * 0.5
            if (direction > 0 and cy < y - 1) or (direction < 0 and cy > y + 1) then ahead[#ahead + 1] = control end
        end
    end
    local target = Nearest(ahead, (left + right) * 0.5, y - direction * (top - bottom))
    if not target then return false end
    Select(target)
    return true
end

-- Y where nothing moves: the window's search field (options.searchField) with
-- the keyboard open on it.
local function OpenSearch(scope, options)
    local field = options and type(options.searchField) == "function" and options.searchField(scope)
    local keyboard = PadNav.Keyboard
    if not (field and keyboard and Usable(field, scope)) then return false end
    Select(field)
    Haptic("press")
    keyboard.Open(field)
    return true
end

-- options.undo/options.redo (LT held with LB/RB); they return true when done.
local function UndoRedo(scope, options, direction)
    local run = direction < 0 and options.undo or options.redo
    Haptic(type(run) == "function" and run(scope) and "press" or "edge")
end

local function RunHeld(scope)
    local actions = scopeActions[scope]
    local action = actions and actions[heldButton]
    if action then action(scope) elseif STEPS[heldButton] then Move(scope, heldButton) end
end

local function WholeSteps(value)
    return value >= 0 and floor(value) or -floor(-value)
end

-- Keeps the selection on screen after the right stick scrolled the page.
local function SettleInView(scroll)
    local scope = TopScope()
    if not (scope and current) then return end
    local left, bottom, right, top = Rect(scroll)
    local _, controlBottom, _, controlTop = Rect(current)
    if not (left and controlBottom) or (controlBottom >= bottom and controlTop <= top) then return end
    local list, inside = Controls(scope), {}
    for index = 1, #list do
        local control = list[index]
        local _, cBottom, _, cTop = Rect(control)
        if IsInside(control, scroll) and cBottom >= bottom and cTop <= top then inside[#inside + 1] = control end
    end
    local controlLeft, _, controlRight = Rect(current)
    local y = min(top, max(bottom, (controlBottom + controlTop) * 0.5))
    local target = Nearest(inside, controlLeft and (controlLeft + controlRight) * 0.5 or (left + right) * 0.5, y)
    if target then Select(target) end
end

local function DriveStick(elapsed)
    if stickX == 0 and stickY == 0 then return false end
    stickHeld = stickHeld + elapsed
    local mode, target = NudgeMode()
    if mode then
        local ramp = min(1, stickHeld / RAMP_TIME)
        local stepped = mode == "arrows" or mode == "bar" or mode == "steps"
        local rate = mode == "steps" and (LIST_RATE + (LIST_RATE_MAX - LIST_RATE) * ramp)
            or stepped and (STEP_RATE + (STEP_RATE_MAX - STEP_RATE) * ramp)
            or (PIXEL_RATE + (PIXEL_RATE_MAX - PIXEL_RATE) * ramp)
        nudgeX, nudgeY = nudgeX + stickX * rate * elapsed, nudgeY + stickY * rate * elapsed
        nudgeWait = nudgeWait - elapsed
        if nudgeWait > 0 then return true end
        local stepX, stepY = WholeSteps(nudgeX), WholeSteps(nudgeY)
        if stepped then stepX, stepY = max(-1, min(1, stepX)), max(-1, min(1, stepY)) end
        if stepX == 0 and stepY == 0 then return true end
        nudgeX, nudgeY, nudgeWait = nudgeX - stepX, nudgeY - stepY, NUDGE_INTERVAL
        NudgeBy(mode, target, stepX, stepY)
        return true
    end
    local scroll = ScrollFrameOf(current)
    if not scroll or stickY == 0 then return false end
    local range, offset = ScrollRange(scroll), Plain(scroll:GetVerticalScroll())
    if not (range and offset) then return false end
    local rate = SCROLL_RATE_MIN + (SCROLL_RATE - SCROLL_RATE_MIN) * min(1, stickHeld / RAMP_TIME)
    ScrollTo(scroll, max(0, min(range, ScrollGoal(scroll, offset) - stickY * rate * elapsed)))
    settleWait = settleWait - elapsed
    if settleWait <= 0 then
        settleWait = SCROLL_SETTLE
        SettleInView(scroll)
    end
    return true
end

-- One OnUpdate drives a held D-pad direction (or a repeatable action) and the
-- right stick; it is cleared whenever neither is active.
local function OnInputUpdate(self, elapsed)
    local scope = TopScope()
    if not scope then
        self:SetScript("OnUpdate", nil)
        return
    end
    if heldButton then
        heldElapsed, heldTime = heldElapsed + elapsed, heldTime + elapsed
        if heldElapsed >= REPEAT_DELAY then
            heldElapsed = REPEAT_DELAY - (moveMode and MOVE_REPEAT_RATE or REPEAT_RATE)
            RunHeld(scope)
        end
    end
    if not DriveStick(elapsed) and not heldButton then
        self:SetScript("OnUpdate", nil)
    end
end

local function StickTarget()
    return capturing and (NudgeMode() ~= nil or ScrollFrameOf(current) ~= nil)
end

function UpdateMotor()
    if not input then return end
    local active = StickTarget()
    input:EnableGamePadStick(active)
    if not active then stickX, stickY, nudgeX, nudgeY, nudgeWait, stickHeld = 0, 0, 0, 0, 0, 0 end
    if heldButton or (active and (stickX ~= 0 or stickY ~= 0)) then
        input:SetScript("OnUpdate", OnInputUpdate)
    end
end

local function StopRepeat()
    heldButton = nil
end

local function OnButtonDown(_, button)
    local scope = TopScope()
    if not scope then
        UpdateCapture()
        return
    end
    local actions = scopeActions[scope]
    local action = actions and actions[button]
    local options = scopeOptions[scope]
    local undoable = options and type(options.undo) == "function"
    if heldTrigger and SHOULDER[button] and undoable then
        triggerUsed = true
        UndoRedo(scope, options, SHOULDER[button])
    elseif SHOULDER[button] and (moveMode or (options and options.cycle and not action)) then
        Haptic(CycleElement(scope, SHOULDER[button]) and "step" or "edge")
    elseif action then
        -- The tick comes first so an action's own stronger feedback wins.
        Haptic("step")
        heldTime = 0
        action(scope)
        if actions.repeatable and actions.repeatable[button] then heldButton, heldElapsed = button, 0 end
    elseif SHOULDER[button] then
        Haptic(PageJump(scope, SHOULDER[button]) and "step" or "edge")
    elseif CYCLE[button] then
        -- With undo/redo the trigger waits for its release: held, it is LB/RB's modifier.
        if undoable then heldTrigger, triggerUsed = button, false else CycleScopes(CYCLE[button]) end
    elseif STEPS[button] then
        heldTime = 0
        Move(scope, button)
        heldButton, heldElapsed = button, 0
    elseif button == ACCEPT then
        Accept(scope, "LeftButton")
    elseif button == ALTERNATE then
        Accept(scope, "RightButton")
    elseif button == MOVE then
        if moveMode or NudgeMode() or SelectPreviewHandle(current) then
            SetMoveMode(not moveMode)
        elseif not OpenSearch(scope, options) then
            Bump()
        end
    elseif button == TOOLTIP_TOGGLE then
        ToggleTooltips()
    elseif button == BACK or button == MENU then
        Back(scope)
    end
    -- A press may open a popup, close or rebuild the window; follow it now.
    CheckWatches()
    UpdateCapture()
    UpdateMotor()
    RefreshPrompts()
end

local function OnButtonUp(_, button)
    if button == heldButton then StopRepeat() end
    if button ~= heldTrigger then return end
    heldTrigger = nil
    if triggerUsed then return end
    CycleScopes(CYCLE[button])
    UpdateCapture()
    UpdateMotor()
    RefreshPrompts()
end

-- Returning true leaves the stick to the game (walking, camera).
local function OnStick(_, stick, x, y)
    if not NUDGE_STICKS[stick] or not StickTarget() then return true end
    x, y = Plain(x) or 0, Plain(y) or 0
    local idle = stickX == 0 and stickY == 0
    stickX = abs(x) >= STICK_DEADZONE and x or 0
    stickY = abs(y) >= STICK_DEADZONE and y or 0
    -- The first deflection acts at once, like a key press; holding repeats.
    if idle then
        nudgeX = stickX > 0 and 0.99 or stickX < 0 and -0.99 or 0
        nudgeY = stickY > 0 and 0.99 or stickY < 0 and -0.99 or 0
    end
    if stickX == 0 and stickY == 0 then
        nudgeX, nudgeY, nudgeWait, stickHeld, settleWait = 0, 0, 0, 0, 0
        local scroll = not NudgeMode() and ScrollFrameOf(current)
        if scroll then SettleInView(scroll) end
    end
    UpdateMotor()
    return false
end

local function EnsureInput()
    if input then return input end
    input = CreateUnhookedFrame("Frame", UIParent)
    input:SetSize(1, 1)
    input:SetPoint("TOPLEFT")
    input:SetScript("OnGamePadButtonDown", OnButtonDown)
    input:SetScript("OnGamePadButtonUp", OnButtonUp)
    input:SetScript("OnGamePadStick", OnStick)
    input:Hide()
    return input
end

local function SetCapturing(enabled)
    if capturing == enabled then return end
    capturing = enabled
    EnsureInput()
    if enabled then
        input:Show()
        input:EnableGamePadButton(true)
    else
        StopRepeat()
        input:EnableGamePadButton(false)
        input:Hide()
        moveMode = false
        -- Combat or a Blizzard panel took the pad; the selection waits for it.
        local scope = TopScope()
        if scope and current and InScope(current, scope) then lastSelection[scope] = current end
        Select(nil)
    end
    UpdateMotor()
end

function UpdateCapture()
    local scope = TopScope()
    SetCapturing(scope ~= nil and not inCombat and PadUIEnabled() and not BlizzardNavigationActive())
    if capturing then Validate(scope) end
    local keyboard = PadNav.Keyboard
    if keyboard then keyboard.Check() end
end

-- Button hints for the window on top, built here and drawn by PadPrompts.lua:
-- a flat list of button keys ("PAD1", "PADLSHOULDER/PADRSHOULDER") and English
-- labels that MSUF.L translates.
local function AddPrompt(keys, label)
    promptList[#promptList + 1] = keys
    promptList[#promptList + 1] = label
end

local function BuildPrompts(scope)
    for index = #promptList, 1, -1 do promptList[index] = nil end
    local options = scopeOptions[scope]
    local fixed = options and options.prompts
    if type(fixed) == "function" then fixed = fixed(scope) end
    if fixed then
        for index = 1, #fixed do promptList[index] = fixed[index] end
        return
    end
    if moveMode then
        AddPrompt("DIRPAD", "Move 1 px")
        AddPrompt("PADLSHOULDER/PADRSHOULDER", "Previous / next element")
        AddPrompt("PAD4", "Done moving")
        return
    end
    local control, actions = current, scopeActions[scope]
    if control and control:IsObjectType("EditBox") then
        AddPrompt("PAD1", "Type text")
    elseif control and control:IsObjectType("Slider") then
        AddPrompt("DIRPADHORIZONTAL", "Adjust")
        if control.editBox then AddPrompt("PAD1", "Type a value") end
    elseif control then
        local label = options and type(options.acceptLabel) == "function" and options.acceptLabel(control)
        AddPrompt("PAD1", label or "Select")
    end
    local scroll = ScrollFrameOf(control)
    if NudgeMode() then
        AddPrompt("PAD4", "Move")
    else
        if scroll then AddPrompt("PADRSTICKAXIS", "Scroll") end
        if options and type(options.searchField) == "function" then AddPrompt("PAD4", "Find a setting") end
    end
    if scroll and not (actions and (actions.PADLSHOULDER or actions.PADRSHOULDER)) and not (options and options.cycle) then
        AddPrompt("PADLSHOULDER/PADRSHOULDER", "Previous / next page")
    end
    local hints = options and options.hints
    for index = 1, hints and #hints or 0 do promptList[#promptList + 1] = hints[index] end
    if options and type(options.undo) == "function" then
        AddPrompt("PADLTRIGGER+PADLSHOULDER/PADRSHOULDER", "Undo / redo")
    end
    if VisibleScopeCount() > 1 then AddPrompt("PADLTRIGGER/PADRTRIGGER", "Switch window") end
    AddPrompt("PADRSTICK", "Tooltips")
    AddPrompt("PAD2", TextFocus(scope) and "Back" or (options and options.backLabel) or "Close")
end

-- The frames the hint bar sits beside: the window, or the ones its
-- options.promptAnchors names (the Edit Mode toolbar, not the screen's edge).
local function PromptAnchors(scope)
    for index = #anchorList, 1, -1 do anchorList[index] = nil end
    local options = scopeOptions[scope]
    if options and type(options.promptAnchors) == "function" then options.promptAnchors(anchorList) end
    if #anchorList == 0 then anchorList[1] = scope end
    return anchorList
end

function RefreshPrompts()
    local prompts = PadNav.Prompts
    if not prompts then return end
    local scope = capturing and TopScope() or nil
    if not scope then
        prompts.Hide()
        return
    end
    BuildPrompts(scope)
    prompts.Show(promptList, PromptAnchors(scope), moveMode)
end

local function RemoveScope(frame)
    -- _msufPadHeld tells a window's own hover-close (Quick.MenuButtonAt) that
    -- the pad, not the mouse, is using it.
    frame._msufPadHeld = nil
    for index = #scopes, 1, -1 do
        if scopes[index] == frame then table.remove(scopes, index) end
    end
end

-- Put a shown window on top; its last selection comes back with it unless
-- preferred names the control to start on (a dropdown's chosen row). A window
-- that fades in is selected by the poll once it is visible.
function PadNav.Activate(frame, preferred)
    if not (frame and frame:IsShown()) or not PadUIEnabled() then return end
    local top = scopes[#scopes]
    if top ~= frame then
        if top and current and InScope(current, top) then lastSelection[top] = current end
        RemoveScope(frame)
        scopes[#scopes + 1] = frame
        frame._msufPadHeld = true
        moveMode = false
        Select(nil)
        local options = scopeOptions[frame]
        -- onActivate may name the control the window starts on.
        if options and type(options.onActivate) == "function" then
            preferred = preferred or options.onActivate(frame)
        end
    end
    if preferred then
        lastSelection[frame] = preferred
        if current ~= preferred then Select(nil) end
    end
    EnsureInput()
    UpdateCapture()
    RefreshPrompts()
end

function PadNav.Release(frame)
    if not frame then return end
    if current and InScope(current, frame) then
        lastSelection[frame] = current
        Select(nil)
    end
    RemoveScope(frame)
    if input then
        UpdateCapture()
        RefreshPrompts()
    end
end

local function ReleaseOnHide(frame)
    PadNav.Release(frame)
end

-- onBack runs for B and Start; without it SmartNavigationCloseHandler, then the
-- window's own Finish/Close, then Hide. actions maps pad buttons to
-- function(window) for this window only (actions.repeatable[button] = true
-- repeats it while held). options: roots(list) adds frames outside the window;
-- nudge(window, control, dx, dy) moves the selection; movable(control) picks
-- the controls LB/RB step through while moving (cycle: always, when the window
-- has no LB/RB action); hints (button keys and labels in pairs), backLabel,
-- acceptLabel(control) and prompts (a fixed hint list, or a function returning
-- one) feed the button hints; stepper(window, dx, dy) takes the right stick in
-- whole steps while stepperActive(window) allows it; searchField(window) is the
-- edit box Y opens where nothing moves; undo(window)/redo(window) run on a held
-- trigger with LB/RB;
-- promptAnchors(list) the frames they sit beside; onActivate(window) runs
-- whenever the window comes to the top and may return the control to start on.
function PadNav.Attach(frame, onBack, actions, options)
    if not frame then return end
    if type(onBack) == "function" then backHandlers[frame] = onBack end
    if type(actions) == "table" then scopeActions[frame] = actions end
    if type(options) == "table" then scopeOptions[frame] = options end
    if attached[frame] then return end
    attached[frame] = true
    frame:HookScript("OnHide", ReleaseOnHide)
end

local function ActivateOnShow(frame)
    PadNav.Activate(frame)
end

-- A popup that takes the pad whenever it shows (Menu2 popups on UIParent).
function PadNav.Track(frame, onBack, actions, options)
    if not frame then return end
    PadNav.Attach(frame, onBack, actions, options)
    if not tracked[frame] then
        tracked[frame] = true
        frame:HookScript("OnShow", ActivateOnShow)
    end
    if frame:IsVisible() then PadNav.Activate(frame) end
end

local function Stacked(frame)
    for index = 1, #scopes do
        if scopes[index] == frame then return true end
    end
    return false
end

-- A named MSUF window outside the menu (Edit Mode, its popups) is taken over
-- once it shows; it is never pulled back to the top while already stacked.
-- name may be a function returning the frame (an unnamed list).
function PadNav.Watch(name, onBack, actions, options)
    watches[#watches + 1] = { name = name, onBack = onBack, actions = actions, options = options }
end

function CheckWatches()
    for index = 1, #watches do
        local watch = watches[index]
        local name = watch.name
        local frame = type(name) == "function" and name() or _G[name]
        if type(frame) == "table" and type(frame.IsVisible) == "function" and frame:IsVisible()
            and not Stacked(frame)
        then
            PadNav.Attach(frame, watch.onBack, watch.actions, watch.options)
            PadNav.Activate(frame)
        end
    end
end

function PadNav.IsCapturing()
    return capturing
end

function PadNav.GetSelection()
    return current
end

PadNav.IsGamepadUI = PadUIEnabled

-- Select a control of the window on top (a menu jump, a remembered page spot).
function PadNav.SelectControl(control)
    local scope = TopScope()
    if not (capturing and scope and Usable(control, scope)) then return false end
    moveMode = false
    Select(control)
    return true
end

function PadNav.IsSelectionIn(frame)
    return current ~= nil and frame ~= nil and IsInside(current, frame)
end

-- The preferred control when it is usable, else the first one inside frame.
function PadNav.SelectFirstIn(frame, preferred)
    local scope = TopScope()
    if not (capturing and scope and frame) then return false end
    if preferred and IsInside(preferred, frame) and PadNav.SelectControl(preferred) then return true end
    local list, inside = Controls(scope), {}
    for index = 1, #list do
        if IsInside(list[index], frame) then inside[#inside + 1] = list[index] end
    end
    local first = FirstControl(inside)
    return first ~= nil and PadNav.SelectControl(first)
end

-- Shared helpers for PadKeyboard.lua, PadPrompts.lua and PadEditMode.lua.
PadNav.Kit = {
    Plain = Plain, Rect = Rect, RunScript = RunScript, AddBorder = AddBorder,
    CreateUnhookedFrame = CreateUnhookedFrame, PixelLayoutRegion = PixelLayoutRegion,
    Pick = Pick, Nearest = Nearest, Haptic = Haptic,
    RING_COLOR = RING_COLOR, RING_LEVEL = RING_LEVEL,
}

-- SmartNavigation and the watched windows have no event an addon can follow
-- without hooking Blizzard's frames, so one ticker polls them.
local function Poll()
    if not PadUIEnabled() then
        if capturing then UpdateCapture() end
        return
    end
    CheckWatches()
    if #scopes > 0 or capturing then
        UpdateCapture()
        RefreshPrompts()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        inCombat = InCombatLockdown() == true
        -- Blizzard's own tooltip switch for the Gamepad UI (read, never written).
        tooltipsHidden = type(GetCVarBool) == "function" and GetCVarBool("GamepadDisableTooltips") == true
        C_Timer.NewTicker(POLL_INTERVAL, Poll)
        return
    end
    -- InCombatLockdown() is still false on PLAYER_REGEN_DISABLED.
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if input then
        UpdateCapture()
        RefreshPrompts()
    end
end)
