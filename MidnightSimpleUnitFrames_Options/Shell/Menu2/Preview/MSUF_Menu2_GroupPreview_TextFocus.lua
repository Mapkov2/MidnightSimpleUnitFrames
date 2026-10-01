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
    local CurrentScope = deps.CurrentScope
    local Conf = deps.Conf
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
local GFPreviewNormalizeTextFocusKind = PreviewHelpers.NormalizeTextFocusKind
local GFPreviewNormalizeTextFocusSlot = PreviewHelpers.NormalizeTextFocusSlot
-- Focus region lists live on the mock and the focus options are one constant
-- table, so a repaint or an animation tick refits the ring without allocating.
local function FocusRegionList(mock, field, a, b, c)
    local lists = mock._msufFocusRegionLists
    if not lists then lists = {}; mock._msufFocusRegionLists = lists end
    local list = lists[field]
    if not list then list = {}; lists[field] = list end
    list[1], list[2], list[3] = a, b, c
    return list
end
local function GFPreviewTextFocusRegions(mock, kind, slot)
    if not mock then return nil end
    if kind == "name" then
        return FocusRegionList(mock, "name", mock._nameFS)
    elseif kind == "hp" then
        slot = GFPreviewMapHpSlot(kind, slot)
        if slot == "left" then return FocusRegionList(mock, "hpLeft", mock._hpLeftFS) end
        if slot == "center" then return FocusRegionList(mock, "hpCenter", mock._hpCenterFS) end
        if slot == "right" then return FocusRegionList(mock, "hpRight", mock._hpRightFS) end
        return FocusRegionList(mock, "hp", mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS)
    elseif kind == "power" then
        if slot == "left" then return FocusRegionList(mock, "powerLeft", mock._powerLeftFS) end
        if slot == "center" then return FocusRegionList(mock, "powerCenter", mock._powerCenterFS) end
        if slot == "right" then return FocusRegionList(mock, "powerRight", mock._powerRightFS) end
        return FocusRegionList(mock, "power", mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS)
    end
    return nil
end
local FOCUS_OPTIONS = {
    Regions = GFPreviewTextFocusRegions,
    Place = GFPreviewPlaceHandleAroundRegions,
    colors = { hp = { 0.25, 0.90, 0.42 } },
}
local function GFPreviewApplyTextFocus(box, mock)
    return PreviewHelpers.ApplyTextFocus(box, mock, mock, FOCUS_OPTIONS)
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
