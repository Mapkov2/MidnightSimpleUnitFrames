local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Input.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local C_Timer, min = M.MenuTimer or C_Timer, math.min
local EDGE_ANCHORS = H._Shared.EDGE_ANCHORS

function H.IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end
function H.KeyDelta(key)
    if key == "LEFT" then return -1, 0 end
    if key == "RIGHT" then return 1, 0 end
    if key == "UP" then return 0, 1 end
    if key == "DOWN" then return 0, -1 end
    return nil, nil
end
function H.NudgeStep(opts)
    opts = opts or {}
    if IsControlKeyDown and IsControlKeyDown() then return tonumber(opts.ctrlStep) or 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return tonumber(opts.shiftStep) or 5 end
    return tonumber(opts.step) or 1
end
function H.ShouldSkipDuplicateNudge(owner, dx, dy, opts)
    if not owner then return false end
    opts = opts or {}
    local now = GetTime and GetTime() or 0
    if now <= 0 then return false end
    local sigKey = opts.sigKey or "_msufLastNudgeSig"
    local atKey = opts.atKey or "_msufLastNudgeAt"
    local sig = tostring(dx or 0) .. ":" .. tostring(dy or 0)
    if owner[sigKey] == sig and (now - (owner[atKey] or 0)) < (tonumber(opts.window) or 0.02) then return true end
    owner[sigKey] = sig
    owner[atKey] = now
    return false
end
local function SetKeyboardPropagate(frame, propagate)
    if frame and frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(propagate == true) end
end
local function InCombatLocked()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end
local function ForEachPreviewKeyboardFrame(owner, callback)
    if not (owner and type(callback) == "function") then return end
    local seen = {}
    local function Visit(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
    Visit(owner)
    local handles = owner.handles
    if type(handles) == "table" then
        for i = 1, #handles do
            Visit(handles[i])
        end
    end
    handles = owner._handleList
    if type(handles) == "table" then
        for i = 1, #handles do
            Visit(handles[i])
        end
    end
end
function H.ReleaseKeyboardCapture(owner)
    ForEachPreviewKeyboardFrame(owner, function(frame)
        SetKeyboardPropagate(frame, true)
    end)
end
function H.FocusKeyboardTarget(owner, handle, defer, opts)
    if not owner then return end
    opts = opts or {}
    local selectedField = opts.selectedField or "_selectedHandle"
    handle = handle or (selectedField and owner[selectedField])
    H.ReleaseKeyboardCapture(owner)
    if InCombatLocked() then return end
    if owner.EnableKeyboard then owner:EnableKeyboard(true) end
    SetKeyboardPropagate(owner, handle and false or true)
    if handle and handle.EnableKeyboard then handle:EnableKeyboard(true) end
    SetKeyboardPropagate(handle, false)
    if handle and handle.SetFocus then
        handle:SetFocus()
    elseif owner.SetFocus then
        owner:SetFocus()
    end
    if defer then
        local selected = handle
        C_Timer.After(0, function()
            if not (owner and owner.IsShown and owner:IsShown()) then return end
            if selected and selected.IsShown and not selected:IsShown() then return end
            if selected and selectedField and owner[selectedField] ~= selected then return end
            H.FocusKeyboardTarget(owner, selected, false, opts)
        end)
    end
end
function H.ArrowKeyDown(self, keyName, opts)
    opts = opts or {}
    local owner = (opts.owner and opts.owner(self)) or (self and self._preview) or self or (opts.active and opts.active())
    if InCombatLocked() then
        H.ReleaseKeyboardCapture(owner)
        SetKeyboardPropagate(self, true)
        return false
    end
    local dx, dy = H.KeyDelta(keyName)
    if not dx then
        SetKeyboardPropagate(self, true)
        SetKeyboardPropagate(owner, true)
        return false
    end
    if H.IsTextInputFocused() then
        H.ReleaseKeyboardCapture(owner)
        SetKeyboardPropagate(self, true)
        return false
    end
    SetKeyboardPropagate(self, false)
    SetKeyboardPropagate(owner, false)
    if opts.nudge and opts.nudge(owner, dx, dy) then
        local selectedField = opts.selectedField or "_selectedHandle"
        local selected = (opts.selected and opts.selected(owner)) or (owner and selectedField and owner[selectedField])
        H.FocusKeyboardTarget(owner, selected, true, opts)
        return true
    end
    SetKeyboardPropagate(self, true)
    SetKeyboardPropagate(owner, true)
    return false
end
function H.RegisterEditModeNudgeTarget(owner, opts)
    if not owner then return end
    local fn = MSUF.Require("MSUF_EM2_SetPreviewNudgeTarget", FILE)
    opts = opts or {}
    local targetField = opts.targetField or "_msufPreviewNudgeTarget"
    local selectedField = opts.selectedField or "_selectedHandle"
    local function Selected() return opts.selected and opts.selected(owner) or (selectedField and owner[selectedField]) end
    owner[targetField] = owner[targetField] or {
        frame = owner,
        IsActive = function()
            if InCombatLocked() then return false end
            if not (owner and owner.IsShown and owner:IsShown()) then return false end
            local selected = Selected()
            if opts.canNudge and not opts.canNudge(selected, owner) then return false end
            return selected ~= nil and not H.IsTextInputFocused()
        end,
        Nudge = function(_, dx, dy)
            local ok = opts.nudgeDelta and opts.nudgeDelta(owner, dx, dy)
            if ok then H.FocusKeyboardTarget(owner, Selected(), true, opts) end
            return ok
        end,
    }
    fn(owner[targetField])
end
local TEXT_FOCUS_SIDES = { "top", "bottom", "left", "right" }
function H.NormalizeTextFocusKind(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end
function H.NormalizeTextFocusSlot(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end
-- Read-only defaults: a focus ring repainted on every repaint or animation
-- tick reuses them instead of a new colour table per call.
local TEXT_FOCUS_DEFAULT_COLORS = {
    hp = { 0.28, 0.86, 0.45 },
    power = { 0.95, 0.72, 0.18 },
    name = { 0.30, 0.66, 1.00 },
}
function H.TextFocusColor(kind, colors)
    if kind == "hp" then return colors and colors.hp or TEXT_FOCUS_DEFAULT_COLORS.hp end
    if kind == "power" then return colors and colors.power or TEXT_FOCUS_DEFAULT_COLORS.power end
    return colors and colors.name or TEXT_FOCUS_DEFAULT_COLORS.name
end
function H.EnsureTextFocusFrame(box, parent)
    if not (box and parent) then return nil end
    local f = box._msufMenuTextFocusFrame
    if not f then
        f = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
        f:EnableMouse(false)
        f.fill = PixelLayoutRegion(f:CreateTexture(nil, "BACKGROUND"))
        f.fill:SetAllPoints()
        f.lines = {}
        for i = 1, #TEXT_FOCUS_SIDES do
            local side = TEXT_FOCUS_SIDES[i]
            local line = PixelLayoutRegion(f:CreateTexture(nil, "OVERLAY"))
            line:SetPoint(EDGE_ANCHORS[side][1])
            line:SetPoint(EDGE_ANCHORS[side][2])
            f.lines[side] = line
        end
        box._msufMenuTextFocusFrame = f
    elseif f.SetParent then
        f:SetParent(parent)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then f:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
    return f
end
function H.PaintTextFocusFrame(frame, color, active)
    if not (frame and color) then return end
    local lineAlpha = active and 0.92 or 0.74
    local fillAlpha = active and 0.10 or 0.065
    local thickness = active and 2 or 1
    if frame.fill then frame.fill:SetColorTexture(color[1], color[2], color[3], fillAlpha) end
    if frame.lines then
        for side, line in pairs(frame.lines) do
            line[EDGE_ANCHORS[side][3]](line, thickness)
            line:SetColorTexture(color[1], color[2], color[3], lineAlpha)
        end
    end
end
-- A region's effective scale relative to its parent's (1 when it reports none).
local function RegionScaleRatio(region, parentScale)
    local regionScale = region.GetEffectiveScale and tonumber(region:GetEffectiveScale()) or parentScale
    if not regionScale or regionScale <= 0 then regionScale = parentScale end
    return regionScale / parentScale
end
function H.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    opts = opts or {}
    pad = tonumber(pad) or 3
    local min, max = math.min, math.max
    local parentScale = parent.GetEffectiveScale and tonumber(parent:GetEffectiveScale()) or 1
    if not parentScale or parentScale <= 0 then parentScale = 1 end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (pLeft and pBottom) then return false end
    local parentScaledLeft, parentScaledBottom
    if opts.useScaledRect and parent.GetScaledRect then
        parentScaledLeft, parentScaledBottom = parent:GetScaledRect()
    end
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b, scaleRatio
            if parentScaledLeft and parentScaledBottom and region.GetScaledRect then
                local scaledLeft, scaledBottom, scaledWidth, scaledHeight = region:GetScaledRect()
                if scaledLeft and scaledBottom and scaledWidth and scaledHeight then
                    -- GetScaledRect is already the final on-screen rectangle.
                    -- Convert it directly into the unscaled handle parent's
                    -- coordinate space instead of inferring the scaled origin.
                    l = (scaledLeft - parentScaledLeft) / parentScale
                    r = (scaledLeft + scaledWidth - parentScaledLeft) / parentScale
                    b = (scaledBottom - parentScaledBottom) / parentScale
                    t = (scaledBottom + scaledHeight - parentScaledBottom) / parentScale
                    scaleRatio = RegionScaleRatio(region, parentScale)
                end
            end
            if not (l and r and t and b) then
                l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
                scaleRatio = tonumber(opts.coordinateScale)
                if not scaleRatio or scaleRatio <= 0 then
                    scaleRatio = RegionScaleRatio(region, parentScale)
                end
                if l and r and t and b then
                    l, r = l * scaleRatio - pLeft, r * scaleRatio - pLeft
                    t, b = t * scaleRatio - pBottom, b * scaleRatio - pBottom
                end
            end
            if l and r and t and b then
                if opts.fitText then
                    local regionW = r - l
                    if region.GetStringWidth and regionW > 0 then
                        local textW = (tonumber(region:GetStringWidth()) or 0) * scaleRatio
                        if textW > 0 and textW < regionW then
                            local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                            if justify == "RIGHT" then
                                l = r - textW
                            elseif justify == "CENTER" then
                                local cx = (l + r) * 0.5
                                l, r = cx - (textW * 0.5), cx + (textW * 0.5)
                            else
                                r = l + textW
                            end
                        end
                    end
                    local regionH = t - b
                    if region.GetStringHeight and regionH > 0 then
                        local textH = (tonumber(region:GetStringHeight()) or 0) * scaleRatio
                        if textH > 0 and textH < regionH then
                            local cy = (t + b) * 0.5
                            t, b = cy + (textH * 0.5), cy - (textH * 0.5)
                        end
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    if not (left and right and top and bottom) then return false end
    local naturalWidth = right - left + pad * 2
    local naturalHeight = top - bottom + pad * 2
    local handleWidth = max(18, naturalWidth)
    local handleHeight = max(18, naturalHeight)
    handle:ClearAllPoints()
    handle:SetSize(handleWidth, handleHeight)
    -- A minimum hit area must grow equally around the rendered region. Growing
    -- only towards the top/right moves handle:GetCenter() away from the visual
    -- center, which in turn biases the shared X/Y readout at small Fit scales.
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        left - pad - ((handleWidth - naturalWidth) * 0.5),
        bottom - pad - ((handleHeight - naturalHeight) * 0.5))
    handle._msufPreviewPanFollower = true
    handle:Show()
    return true
end
function H.ApplyTextFocus(box, parent, mock, opts)
    opts = opts or {}
    local focus = box and box._msufMenuTextFocus
    local frame = box and box._msufMenuTextFocusFrame
    if not (focus and parent and mock) then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    local regions = opts.Regions and opts.Regions(mock, focus.kind, focus.slot)
    if not regions then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    frame = H.EnsureTextFocusFrame(box, parent)
    if not frame then return end
    local color = (opts.Color and opts.Color(focus.kind)) or H.TextFocusColor(focus.kind, opts.colors)
    H.PaintTextFocusFrame(frame, color, focus.active == true)
    if not (opts.Place and opts.Place(frame, parent, regions, focus.active and 5 or 4, focus.kind, focus.slot)) then frame:Hide() end
end
