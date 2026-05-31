--- Group preview text focus helpers.
---
--- Keeps Menu2/EditMode text-focus coordination out of the native preview
--- renderer.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local TextFocus = M.GroupPreviewTextFocus or {}
M.GroupPreviewTextFocus = TextFocus

function TextFocus.Install(deps)
    deps = deps or {}
    local CurrentScope = deps.CurrentScope or function() return M.gfScope or "party" end
    local min = deps.min or math.min
    local max = deps.max or math.max
local function GFPreviewCurrentTextKind()
    local scope = CurrentScope()
    local selected = M.gfTextTabSelection and M.gfTextTabSelection[scope] or "name"
    if selected == "hp" or selected == "power" then return selected end
    return "name"
end

local function GFPreviewTextOffsetKeys(kind, slot)
    if kind == "hp" then
        if slot == "left" then return "hpTextLeftOffsetX", "hpTextLeftOffsetY" end
        if slot == "center" then return "hpTextCenterOffsetX", "hpTextCenterOffsetY" end
        if slot == "right" then return "hpTextRightOffsetX", "hpTextRightOffsetY" end
        return "hpOffsetX", "hpOffsetY"
    end
    if kind == "power" then
        if slot == "left" then return "powerTextLeftOffsetX", "powerTextLeftOffsetY" end
        if slot == "center" then return "powerTextCenterOffsetX", "powerTextCenterOffsetY" end
        if slot == "right" then return "powerTextRightOffsetX", "powerTextRightOffsetY" end
        return "powerOffsetX", "powerOffsetY"
    end
    return "nameOffsetX", "nameOffsetY"
end

local function GFPreviewTextLabel(kind, slot)
    if kind == "hp" then
        if slot == "left" then return "HP Left Text" end
        if slot == "center" then return "HP Center Text" end
        if slot == "right" then return "HP Right Text" end
        return "HP Text"
    end
    if kind == "power" then
        if slot == "left" then return "Power Left Text" end
        if slot == "center" then return "Power Center Text" end
        if slot == "right" then return "Power Right Text" end
        return "Power Text"
    end
    return "Name Text"
end

local function GFPreviewTextMovesTogether(scope, kind)
    local byScope = M.gfTextMoveTogether and M.gfTextMoveTogether[scope or CurrentScope()]
    local value = byScope and byScope[kind]
    if value == nil then return true end
    return value == true
end

local function GFPreviewSetTextMoveTogether(scope, kind, value)
    scope = scope or CurrentScope()
    M.gfTextMoveTogether = M.gfTextMoveTogether or {}
    M.gfTextMoveTogether[scope] = M.gfTextMoveTogether[scope] or {}
    M.gfTextMoveTogether[scope][kind] = value ~= false
end

local function GFPreviewPlaceHandleAroundRegions(handle, parent, regions, pad)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    pad = tonumber(pad) or 3
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
            if l and r and t and b then
                local regionW = r - l
                if region.GetStringWidth and regionW > 0 then
                    local textW = tonumber(region:GetStringWidth()) or 0
                    if textW > 0 and textW < regionW then
                        local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                        if justify == "RIGHT" then
                            l = r - textW
                        elseif justify == "CENTER" then
                            local cx = (l + r) * 0.5
                            l = cx - (textW * 0.5)
                            r = cx + (textW * 0.5)
                        else
                            r = l + textW
                        end
                    end
                end
                local regionH = t - b
                if region.GetStringHeight and regionH > 0 then
                    local textH = tonumber(region:GetStringHeight()) or 0
                    if textH > 0 and textH < regionH then
                        local cy = (t + b) * 0.5
                        t = cy + (textH * 0.5)
                        b = cy - (textH * 0.5)
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (left and right and top and bottom and pLeft and pBottom) then return false end
    handle:ClearAllPoints()
    handle:SetSize(max(18, right - left + pad * 2), max(18, top - bottom + pad * 2))
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left - pLeft - pad, bottom - pBottom - pad)
    handle:Show()
    return true
end

local function GFPreviewNormalizeTextFocusKind(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end

local function GFPreviewNormalizeTextFocusSlot(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end

local function GFPreviewTextFocusColor(kind)
    if kind == "hp" then return { 0.25, 0.90, 0.42 } end
    if kind == "power" then return { 0.95, 0.72, 0.18 } end
    return { 0.30, 0.66, 1.00 }
end

local function GFPreviewEnsureTextFocusFrame(box, parent)
    if not (box and parent) then return nil end
    local f = box._msufMenuTextFocusFrame
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:EnableMouse(false)
        f.fill = f:CreateTexture(nil, "BACKGROUND")
        f.fill:SetAllPoints()
        f.lines = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local line = f:CreateTexture(nil, "OVERLAY")
            f.lines[side] = line
        end
        f.lines.top:SetPoint("TOPLEFT")
        f.lines.top:SetPoint("TOPRIGHT")
        f.lines.bottom:SetPoint("BOTTOMLEFT")
        f.lines.bottom:SetPoint("BOTTOMRIGHT")
        f.lines.left:SetPoint("TOPLEFT")
        f.lines.left:SetPoint("BOTTOMLEFT")
        f.lines.right:SetPoint("TOPRIGHT")
        f.lines.right:SetPoint("BOTTOMRIGHT")
        box._msufMenuTextFocusFrame = f
    elseif f.SetParent then
        f:SetParent(parent)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then
        f:SetFrameLevel((parent:GetFrameLevel() or 0) + 85)
    end
    return f
end

local function GFPreviewPaintTextFocusFrame(frame, color, active)
    if not (frame and color) then return end
    local lineAlpha = active and 0.92 or 0.74
    local fillAlpha = active and 0.10 or 0.065
    local thickness = active and 2 or 1
    if frame.fill then frame.fill:SetColorTexture(color[1], color[2], color[3], fillAlpha) end
    if frame.lines then
        frame.lines.top:SetHeight(thickness)
        frame.lines.bottom:SetHeight(thickness)
        frame.lines.left:SetWidth(thickness)
        frame.lines.right:SetWidth(thickness)
        for _, line in pairs(frame.lines) do
            if line then line:SetColorTexture(color[1], color[2], color[3], lineAlpha) end
        end
    end
end

local function GFPreviewTextFocusRegions(mock, kind, slot)
    if not mock then return nil end
    if kind == "name" then
        return { mock._nameFS }
    elseif kind == "hp" then
        if slot == "left" then return { mock._hpLeftFS } end
        if slot == "center" then return { mock._hpCenterFS } end
        if slot == "right" then return { mock._hpRightFS } end
        return { mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS }
    elseif kind == "power" then
        if slot == "left" then return { mock._powerLeftFS } end
        if slot == "center" then return { mock._powerCenterFS } end
        if slot == "right" then return { mock._powerRightFS } end
        return { mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS }
    end
    return nil
end

local function GFPreviewApplyTextFocus(box, mock)
    local focus = box and box._msufMenuTextFocus
    local frame = box and box._msufMenuTextFocusFrame
    if not (focus and mock) then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    local regions = GFPreviewTextFocusRegions(mock, focus.kind, focus.slot)
    if not regions then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    frame = GFPreviewEnsureTextFocusFrame(box, mock)
    if not frame then return end
    GFPreviewPaintTextFocusFrame(frame, GFPreviewTextFocusColor(focus.kind), focus.active == true)
    if not GFPreviewPlaceHandleAroundRegions(frame, mock, regions, focus.active and 5 or 4) then
        frame:Hide()
    end
end


    return {
        CurrentTextKind = GFPreviewCurrentTextKind,
        TextOffsetKeys = GFPreviewTextOffsetKeys,
        TextLabel = GFPreviewTextLabel,
        TextMovesTogether = GFPreviewTextMovesTogether,
        SetTextMoveTogether = GFPreviewSetTextMoveTogether,
        PlaceHandleAroundRegions = GFPreviewPlaceHandleAroundRegions,
        NormalizeTextFocusKind = GFPreviewNormalizeTextFocusKind,
        NormalizeTextFocusSlot = GFPreviewNormalizeTextFocusSlot,
        ApplyTextFocus = GFPreviewApplyTextFocus,
    }
end
