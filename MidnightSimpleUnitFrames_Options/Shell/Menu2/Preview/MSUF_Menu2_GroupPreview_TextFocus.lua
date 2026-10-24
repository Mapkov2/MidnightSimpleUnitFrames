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
-- Handle label per value text kind and slot; unknown slots take the kind's default.
local TEXT_LABELS = {
    hp = { left = "HP Left Text", center = "HP Center Text", right = "HP Right Text", default = "HP Text" },
    power = { left = "Power Left Text", center = "Power Center Text", right = "Power Right Text", default = "Power Text" },
}
-- Focus region cache key and mock FontString field per value text kind and slot.
local FOCUS_SLOTS = {
    hp = {
        left = { "hpLeft", "_hpLeftFS" }, center = { "hpCenter", "_hpCenterFS" }, right = { "hpRight", "_hpRightFS" },
    },
    power = {
        left = { "powerLeft", "_powerLeftFS" }, center = { "powerCenter", "_powerCenterFS" },
        right = { "powerRight", "_powerRightFS" },
    },
}
function TextFocus.Install(deps)
    deps = deps or {}
    local CurrentScope, Conf = deps.CurrentScope, deps.Conf
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
    local labels = TEXT_LABELS[kind]
    if not labels then return "Name Text" end
    return labels[slot] or labels.default
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
-- Focus region lists live on the mock and the focus options are one constant
-- table, so a repaint or an animation tick refits the ring without allocating.
local function FocusRegionList(mock, field, a, b, c)
    return PreviewHelpers.CachedRegionList(mock, "_msufFocusRegionLists", field, a, b, c)
end
local function GFPreviewTextFocusRegions(mock, kind, slot)
    if not mock then return nil end
    if kind == "name" then return FocusRegionList(mock, "name", mock._nameFS) end
    local slots = FOCUS_SLOTS[kind]
    if not slots then return nil end
    if kind == "hp" then slot = GFPreviewMapHpSlot(kind, slot) end
    local entry = slots[slot]
    if entry then return FocusRegionList(mock, entry[1], mock[entry[2]]) end
    return FocusRegionList(mock, kind, mock[slots.left[2]], mock[slots.center[2]], mock[slots.right[2]])
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
        NormalizeTextFocusKind = PreviewHelpers.NormalizeTextFocusKind,
        NormalizeTextFocusSlot = PreviewHelpers.NormalizeTextFocusSlot,
        ApplyTextFocus = GFPreviewApplyTextFocus,
    }
end
