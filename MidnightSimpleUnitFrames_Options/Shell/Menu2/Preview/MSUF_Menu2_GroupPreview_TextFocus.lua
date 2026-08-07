--- Group preview text focus helpers.
---
--- Keeps Menu2/EditMode text-focus coordination out of the native preview
--- renderer.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local TextFocus = M.GroupPreviewTextFocus or {}
M.GroupPreviewTextFocus = TextFocus
local PreviewHelpers = M.PreviewHelpers or {}
local NAME_FOCUS_PLACEMENT = { useScaledRect = true }
local VALUE_FOCUS_PLACEMENT = { fitText = true, useScaledRect = true }
function TextFocus.Install(deps)
    deps = deps or {}
    local CurrentScope = deps.CurrentScope or function() return M.gfScope or "party" end
    local Conf = deps.Conf or function(_) return {} end
    -- Under reverse order the configured left HP slot renders on the physical
    -- right FontString (and vice versa); map slot-addressed visuals to the
    -- FontString that actually shows the slot's content.
    local function GFPreviewMapHpSlot(kind, slot)
        if kind == "hp" and (slot == "left" or slot == "right") then
            local conf = Conf(CurrentScope())
            if conf and conf.hpTextReverse == true then
                return slot == "left" and "right" or "left"
            end
        end
        return slot
    end
local function GFPreviewCurrentTextKind()
    local scope = CurrentScope()
    local selected = M.gfTextTabSelection and M.gfTextTabSelection[scope] or "name"
    if selected == "hp" or selected == "power" then return selected end
    return "name"
end
local function GFPreviewTextOffsetKeys(kind, slot)
    return M.TextSlotOffsetKeys(kind, slot)
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
local function GFPreviewPlaceHandleAroundRegions(handle, parent, regions, pad, kind)
    return PreviewHelpers.PlaceHandleAroundRegions(handle, parent, regions, pad,
        kind == "name" and NAME_FOCUS_PLACEMENT or VALUE_FOCUS_PLACEMENT)
end
local GFPreviewNormalizeTextFocusKind = PreviewHelpers.NormalizeTextFocusKind or function(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end
local GFPreviewNormalizeTextFocusSlot = PreviewHelpers.NormalizeTextFocusSlot or function(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end
local function GFPreviewTextFocusRegions(mock, kind, slot)
    if not mock then return nil end
    if kind == "name" then
        return { mock._nameFS }
    elseif kind == "hp" then
        slot = GFPreviewMapHpSlot(kind, slot)
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
    return PreviewHelpers.ApplyTextFocus(box, mock, mock, {
        Regions = GFPreviewTextFocusRegions,
        Place = GFPreviewPlaceHandleAroundRegions,
        colors = { hp = { 0.25, 0.90, 0.42 } },
    })
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
