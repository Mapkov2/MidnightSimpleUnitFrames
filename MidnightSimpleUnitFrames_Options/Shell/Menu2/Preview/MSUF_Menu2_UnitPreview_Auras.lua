--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua
--- Aura selection, drag handles and settings inputs for the engine unit scene.
local MSUF = _G.MSUF
local M = MSUF.MSUF2
local floor, max, min = math.floor, math.max, math.min
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local CurrentPanelKey = PreviewModel.CurrentPanelKey
local FILE = "Menu2/UnitPreview_Auras"
local RoundOffset = MSUF.Require("MSUF_RoundOffset", FILE)
local function ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end
local function PlaceMinimumHitHandle(handle, parent, left, bottom, visualWidth, visualHeight, pad, minimum)
    if not (handle and parent) then return false end
    left, bottom = tonumber(left), tonumber(bottom)
    visualWidth, visualHeight = tonumber(visualWidth), tonumber(visualHeight)
    if not (left and bottom and visualWidth and visualHeight) then return false end
    pad, minimum = tonumber(pad) or 0, tonumber(minimum) or 18
    local naturalWidth = max(0, visualWidth) + pad * 2
    local naturalHeight = max(0, visualHeight) + pad * 2
    local handleWidth = max(minimum, naturalWidth)
    local handleHeight = max(minimum, naturalHeight)
    handle:ClearAllPoints()
    handle:SetSize(handleWidth, handleHeight)
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        left - pad - ((handleWidth - naturalWidth) * 0.5),
        bottom - pad - ((handleHeight - naturalHeight) * 0.5))
    return true
end
local function PlaceHandleAroundShownRegions(handle, parent, regions, pad)
    local helpers = M.PreviewHelpers
    local place = helpers and helpers.PlaceHandleAroundRegions
    if type(place) ~= "function" then return false end
    return place(handle, parent, regions, pad) == true
end
local function RuntimeRound(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local Auras = MSUF.UFPreviewAuras or {}
MSUF.UFPreviewAuras = Auras
Auras.PlaceMinimumHitHandle = PlaceMinimumHitHandle
Auras.PlaceHandleAroundShownRegions = PlaceHandleAroundShownRegions
local AURA_HANDLE_FIELDS = {
    buff = { x = "buffGroupOffsetX", y = "buffGroupOffsetY", defaultX = 0, defaultY = 36, label = "Buffs", color = { 0.20, 0.74, 0.42 } },
    debuff = { x = "debuffGroupOffsetX", y = "debuffGroupOffsetY", defaultX = 0, defaultY = 6, label = "Debuffs", color = { 0.84, 0.26, 0.28 } },
    custom1 = { customIndex = 1, defaultX = 0, defaultY = 0, label = "Custom 1", color = { 0.45, 0.72, 1.00 } },
    custom2 = { customIndex = 2, defaultX = 0, defaultY = 0, label = "Custom 2", color = { 0.70, 0.48, 1.00 } },
    custom3 = { customIndex = 3, defaultX = 0, defaultY = 0, label = "Custom 3", color = { 1.00, 0.58, 0.28 } },
    custom4 = { customIndex = 4, defaultX = 0, defaultY = 0, label = "Dots on target", color = { 0.88, 0.24, 0.42 } },
}
local AURA_ANCHOR_OK = {
    TOPLEFT=true, TOP=true, TOPRIGHT=true,
    LEFT=true, CENTER=true, RIGHT=true,
    BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true,
}
local function MenuModel()
    local a3 = MSUF.MSUF_Auras3
    return type(a3) == "table" and a3.MenuModel or nil
end
-- Menu2/ApplyService.lua loads earlier in this addon: resolved once, not per drag step.
local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
local function NormalizeKind(kind)
    kind = tostring(kind or ""):lower()
    if kind == "buffs" then kind = "buff" end
    if kind == "debuffs" then kind = "debuff" end
    local customIndex = kind:match("^custom(%d)$")
    if customIndex and tonumber(customIndex) >= 1 and tonumber(customIndex) <= 4 then return "custom" .. customIndex end
    return AURA_HANDLE_FIELDS[kind] and kind or nil
end

--- The UnitFrame Aura page embeds its style editor below the live frame
--- preview.  When Style is selected, keep the matching dummy lane visible
--- even if that lane/container is currently disabled or has a zero icon
--- limit. This is menu-only state; it never reaches the live aura runtime.
local function SelectedUnitAuraStyleKind(unit)
    local selections = M.unitAuraTabSelection
    local kind = NormalizeKind(type(selections) == "table" and selections[unit] or nil)
    if not kind then return nil end
    local allTools = M.unitAuraToolSelection
    local tools = type(allTools) == "table" and allTools[unit] or nil
    return type(tools) == "table" and tools[kind] == "style" and kind or nil
end

local function CustomItem(model, unit, index, create)
    if not (model and type(model.CustomContainer) == "function") then return nil end
    return model.CustomContainer(unit, index, create == true)
end
local function CustomStyleItem(model, unit, index)
    if model and type(model.CustomContainerStyleItem) == "function" then
        return model.CustomContainerStyleItem(unit, index, false)
    end
    return CustomItem(model, unit, index, false)
end

local FRAME_EFFECT_TYPES = {
    healthtint = true, border = true, glow = true, pulse = true, namecolor = true,
}

--- Reads the effect belonging to the Style workspace currently shown below
--- the large UnitFrame preview.  This intentionally ignores lane enable state:
--- Style already forces its dummy icons visible, and its frame effect must be
--- equally inspectable before the user enables that Aura lane.
local function SelectedUnitAuraFrameEffect(model, unit, kind)
    if not (model and unit and kind) then return nil end
    local raw
    if kind == "buff" or kind == "debuff" then
        if type(model.ReadValue) ~= "function" then return nil end
        local prefix = kind == "buff" and "buff" or "debuff"
        raw = {
            type = model.ReadValue(unit, prefix .. "FrameEffectType", "none"),
            color = model.ReadValue(unit, prefix .. "FrameEffectColor", { 0.69, 0.50, 0.88, 0.80 }),
            priority = model.ReadValue(unit, prefix .. "FrameEffectPriority", 5),
            thickness = model.ReadValue(unit, prefix .. "FrameEffectThickness", 2),
            layer = model.ReadValue(unit, prefix .. "FrameEffectLayer", 0),
            strata = model.ReadValue(unit, prefix .. "FrameEffectStrata", "AUTO"),
        }
    else
        local index = tonumber(tostring(kind):match("^custom(%d)$"))
        local styleItem = index and CustomStyleItem(model, unit, index) or nil
        raw = styleItem and styleItem.frame or nil
    end
    local effectType = tostring(raw and raw.type or "none"):lower()
    if not FRAME_EFFECT_TYPES[effectType] then return nil end
    local color = type(raw.color) == "table" and raw.color or {}
    return {
        type = effectType,
        color = {
            ClampNumber(color[1] or color.r, 0.69, 0, 1),
            ClampNumber(color[2] or color.g, 0.50, 0, 1),
            ClampNumber(color[3] or color.b, 0.88, 0, 1),
            ClampNumber(color[4] or color.a, 0.80, 0, 1),
        },
        priority = RuntimeRound(ClampNumber(raw.priority, 5, 1, 10)),
        thickness = ClampNumber(raw.thickness, 2, 1, 16),
        layer = RuntimeRound(ClampNumber(raw.layer, 0, 0, 30)),
        strata = tostring(raw.strata or "AUTO"),
        tintAlpha = raw.tintAlpha,
    }
end
function Auras.WantsDefensivePortraitAnchor(key, runtimeSpec)
    key = Auras.PreviewUnitKey(key)
    if key ~= "player" and key ~= "target" and key ~= "focus" and key ~= "boss" and key ~= "arena" then return false end
    local model = MenuModel()
    local item = CustomItem(model, key, 4, false)
    local portrait = runtimeSpec and runtimeSpec.portrait
    return item and item.enabled == true
        and item.portraitIcon == true
        and item.portraitPositionWhenDisabled == true
        and portrait and portrait.enabled ~= true
        or false
end
function Auras.PreviewUnitKey(unit)
    if unit == nil then return nil end
    unit = CanonKey(unit)
    if unit == "player" or unit == "pet" or unit == "target" or unit == "focus" or unit == "boss" or unit == "arena" then return unit end
    return nil
end
local function PreviewUnit(box)
    if not box then return nil end
    local key = box.key
    if not key and box._msufPanel
        and (box._msufPanel._msufGetCurrentKey or box._msufPanel._msufLastApplyKey ~= nil) then key = CurrentPanelKey(box._msufPanel) end
    key = Auras.PreviewUnitKey(key)
    if key then box.key = key end
    return key
end
local function RuntimeUnit(unit)
    return unit == "boss" and "boss1" or unit == "arena" and "arena1" or unit
end
local function LiveApplyReason(reason, fallback)
    reason = tostring(reason or "")
    if reason == "" then return fallback or "MSUF2_UNIT_PREVIEW_AURA_APPLY" end
    if reason:find("^MSUF2_", 1, false) or reason:find("^AURAS3_", 1, false) then return reason end
    return "MSUF2_" .. reason
end
local function RefreshRuntime(unit, reason)
    unit = Auras.PreviewUnitKey(unit)
    if not unit then return false end
    reason = LiveApplyReason(reason, "MSUF2_UNIT_PREVIEW_AURA_APPLY")
    ApplyService.RequestAuras(unit, reason)
    ApplyService.Flush()
    return true
end
local function RequestPreviewRefresh(box, reason)
    if not box then return false end
    if type(Preview.RequestRefreshForBox) == "function" then
        Preview.RequestRefreshForBox(box, reason)
        return true
    elseif type(Preview.RequestRefresh) == "function" then
        Preview.RequestRefresh(reason)
        return true
    elseif type(Preview.Refresh) == "function" then
        Preview.Refresh(box, reason)
        return true
    end
    return false
end
-- Edit Mode compat export, loaded with the core addon before this one: resolved once, not per nudge or commit.
local SyncAuras3PositionPopup = MSUF.Require("MSUF_SyncAuras3PositionPopup", FILE)
local function SyncPopup(unit)
    SyncAuras3PositionPopup(RuntimeUnit(unit))
end
function Auras.ReadOffsets(handle)
    local fields = handle and handle._fields
    local spec = fields and AURA_HANDLE_FIELDS[NormalizeKind(fields.auraPreviewKind)]
    local model = spec and MenuModel()
    local unit = PreviewUnit(handle and handle._preview)
    if not (spec and model and unit) then return nil end
    if spec.customIndex then
        local item = CustomItem(model, unit, spec.customIndex, false)
        local placed = item and item.placed
        return tonumber(placed and placed.x) or 0, tonumber(placed and placed.y) or 0, "x", "y"
    end
    if type(model.ReadNumber) ~= "function" then return nil end
    return model.ReadNumber(unit, spec.x, spec.defaultX, -4096, 4096),
        model.ReadNumber(unit, spec.y, spec.defaultY, -4096, 4096),
        spec.x,
        spec.y
end
function Auras.WriteOffsets(handle, x, y, reason)
    local fields = handle and handle._fields
    local kind = fields and NormalizeKind(fields.auraPreviewKind)
    local spec = kind and AURA_HANDLE_FIELDS[kind]
    local model = spec and MenuModel()
    local unit = PreviewUnit(handle and handle._preview)
    if not (spec and model and unit) then return false end
    if spec.customIndex then
        local item = CustomItem(model, unit, spec.customIndex, true)
        if not item then return false end
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.x = RoundOffset(x)
        item.placed.y = RoundOffset(y)
    else
        if type(model.WriteNumber) ~= "function" then return false end
        model.WriteNumber(unit, spec.x, RoundOffset(x), -4096, 4096)
        model.WriteNumber(unit, spec.y, RoundOffset(y), -4096, 4096)
    end
    if reason ~= "UNIT_PREVIEW_DRAG" then
        RefreshRuntime(unit, reason or "MSUF2_UNIT_PREVIEW_AURA_MOVE")
        SyncPopup(unit)
    end
    return true
end
local function MoveFrameBy(frame, dx, dy)
    if not (frame and dx and dy) then return false end
    local point, rel, relPoint, ox, oy = frame:GetPoint(1)
    point = point or "BOTTOMLEFT"
    relPoint = relPoint or point
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, (tonumber(ox) or 0) + dx, (tonumber(oy) or 0) + dy)
    return true
end
local function CaptureDragPoint(handle, key, frame)
    if not (handle and key and frame and frame.GetPoint) then return nil end
    local pointKey = "_msufAuraDrag" .. key .. "Point"
    if handle[pointKey] then return true end
    local point, rel, relPoint, ox, oy = frame:GetPoint(1)
    handle[pointKey] = point or "BOTTOMLEFT"
    handle["_msufAuraDrag" .. key .. "Rel"] = rel
    handle["_msufAuraDrag" .. key .. "RelPoint"] = relPoint or point or "BOTTOMLEFT"
    handle["_msufAuraDrag" .. key .. "X"] = tonumber(ox) or 0
    handle["_msufAuraDrag" .. key .. "Y"] = tonumber(oy) or 0
    return true
end
local function SetDragPoint(handle, key, frame, dx, dy)
    if not (handle and key and frame and frame.SetPoint) then return false end
    if not CaptureDragPoint(handle, key, frame) then return false end
    local prefix = "_msufAuraDrag" .. key
    frame:ClearAllPoints()
    frame:SetPoint(
        handle[prefix .. "Point"] or "BOTTOMLEFT",
        handle[prefix .. "Rel"],
        handle[prefix .. "RelPoint"] or handle[prefix .. "Point"] or "BOTTOMLEFT",
        (tonumber(handle[prefix .. "X"]) or 0) + dx,
        (tonumber(handle[prefix .. "Y"]) or 0) + dy
    )
    return true
end
function Auras.DragOffsets(handle, x, y)
    local fields = handle and handle._fields
    local kind = fields and (NormalizeKind(fields.auraPreviewKind)
        or (fields.dispelSymbolPreview and "dispelSymbol"))
    local box = handle and handle._preview
    if not (kind and box) then return false end
    x = RoundOffset(x)
    y = RoundOffset(y)
    local prevX = handle._msufAuraDragX
    local prevY = handle._msufAuraDragY
    if prevX == nil then prevX = tonumber(handle._startX) or x end
    if prevY == nil then prevY = tonumber(handle._startY) or y end
    if prevX == x and prevY == y then return true end
    local scale = tonumber(box._mockEffectiveScale) or tonumber(box._mockScale) or 1
    if scale <= 0 then scale = 1 end
    local startX = tonumber(handle._startX) or prevX or x
    local startY = tonumber(handle._startY) or prevY or y
    local dx = RoundOffset((x - startX) * scale)
    local dy = RoundOffset((y - startY) * scale)
    handle._msufAuraDragX = x
    handle._msufAuraDragY = y
    local portraitVisual = handle._msufAuraPortraitVisual
    local visual = portraitVisual or handle._msufAuraDragVisual
        or (box.auraPreviewVisuals and box.auraPreviewVisuals[kind])
    local moved = false
    if not portraitVisual then
        moved = SetDragPoint(handle, "Handle", handle, dx, dy)
        if not moved and (dx ~= 0 or dy ~= 0) then moved = MoveFrameBy(handle, dx, dy) end
    end
    if visual then
        local ratio = visual:GetEffectiveScale() / box.mock:GetEffectiveScale()
        if not SetDragPoint(handle, "Visual", visual, dx / ratio, dy / ratio) and (dx ~= 0 or dy ~= 0) then
            moved = MoveFrameBy(visual, dx / ratio, dy / ratio) or moved
        else
            moved = true
        end
    end
    return moved == true
end
-- Drag state a handle carries between the first drag step and the commit (see CaptureDragPoint).
local DRAG_STATE_FIELDS = {
    "_msufAuraDragX", "_msufAuraDragY",
    "_msufAuraDragHandlePoint", "_msufAuraDragHandleRel", "_msufAuraDragHandleRelPoint", "_msufAuraDragHandleX", "_msufAuraDragHandleY",
    "_msufAuraDragVisualPoint", "_msufAuraDragVisualRel", "_msufAuraDragVisualRelPoint", "_msufAuraDragVisualX", "_msufAuraDragVisualY",
}
function Auras.ClearDragOffsets(handle)
    if not handle then return end
    for i = 1, #DRAG_STATE_FIELDS do handle[DRAG_STATE_FIELDS[i]] = nil end
end
function Auras.CommitOffsets(handle, reason)
    local box = handle and handle._preview
    local unit = PreviewUnit(box)
    if not unit then return false end
    reason = reason or "MSUF2_UNIT_PREVIEW_AURA_DRAG_END"
    Auras.ClearDragOffsets(handle)
    RefreshRuntime(unit, reason)
    SyncPopup(unit)
    RequestPreviewRefresh(box, reason)
    return true
end
--- Builds one aura lane's drag handle (buff, debuff or custom1-4) on the
--- shared offset callbacks unless the box already carries it.
local function CreateAuraHandle(box, makeHandle, field, key, kind, label)
    if box[field] then return end
    local spec = AURA_HANDLE_FIELDS[kind]
    box[field] = makeHandle(box, key, {
        auraPreviewKind = kind,
        defaultX = spec.defaultX,
        defaultY = spec.defaultY,
        visualOnly = true,
        readOffsets = Auras.ReadOffsets,
        writeOffsets = Auras.WriteOffsets,
        dragOffsets = Auras.DragOffsets,
        clearDragOffsets = Auras.ClearDragOffsets,
        commitOffsets = Auras.CommitOffsets,
        section = "auras3",
    }, label or spec.label, spec.color)
end
function Auras.CreateHandles(box, makeHandle)
    if not (box and type(makeHandle) == "function") then return end
    CreateAuraHandle(box, makeHandle, "handleAuraBuffs", "auraBuffs", "buff")
    CreateAuraHandle(box, makeHandle, "handleAuraDebuffs", "auraDebuffs", "debuff")
    for index = 1, 4 do
        CreateAuraHandle(box, makeHandle, "handleAuraCustom" .. tostring(index), "auraCustom" .. tostring(index),
            "custom" .. tostring(index), (index == 4 and PreviewUnit(box) == "player") and "Defensive Buffs" or nil)
    end
    local dispel = Auras.DispelPreview
    if not box.handleDispelSymbol and dispel then
        box.handleDispelSymbol = makeHandle(box, "dispelSymbol", {
            defaultX = 0,
            defaultY = 0,
            visualOnly = true,
            dispelSymbolPreview = true,
            previewLayer = "dispelSymbol",
            readOffsets = dispel.ReadOffsets,
            writeOffsets = dispel.WriteOffsets,
            dragOffsets = Auras.DragOffsets,
            clearDragOffsets = Auras.ClearDragOffsets,
            commitOffsets = dispel.CommitOffsets,
            section = "dispel_symbol",
        }, "Dispel Symbol", { 0.30, 0.80, 1.00 })
    end
end
local AnchorOffset = MSUF.Require("MSUF_AuraAnchorOffset", "Menu2/UnitPreview_Auras")
local function NormalizeAnchor(anchor, fallback)
    anchor = tostring(anchor or "")
    return AURA_ANCHOR_OK[anchor] and anchor or fallback or "TOPLEFT"
end
function Auras.SampleEffect(key)
    local unit = Auras.PreviewUnitKey(key)
    local kind = SelectedUnitAuraStyleKind(unit)
    return SelectedUnitAuraFrameEffect(MenuModel(), unit, kind),
        (kind == "buff" or kind == "debuff") and kind or "auras", kind
end
Auras.DispelPreview = Auras.DispelPreview or {}
local DispelPreview = Auras.DispelPreview

function DispelPreview.ReadOffsets(handle)
    local unit = PreviewUnit(handle and handle._preview)
    if not unit then return nil end
    local page = M.UnitPage
    if page and type(page.ReadDispelSymbolOffsets) == "function" then
        return page.ReadDispelSymbolOffsets(unit)
    end
end

function DispelPreview.WriteOffsets(handle, x, y, reason)
    local unit = PreviewUnit(handle and handle._preview)
    local page = unit and M.UnitPage
    if page and type(page.WriteDispelSymbolOffsets) == "function" then
        return page.WriteDispelSymbolOffsets(unit, x, y,
            reason or "MSUF2_UNIT_PREVIEW_DISPEL_SYMBOL_MOVE", reason ~= "UNIT_PREVIEW_DRAG")
    end
    return false
end

function DispelPreview.CommitOffsets(handle, reason)
    local box = handle and handle._preview
    local unit = PreviewUnit(box)
    if not unit then return false end
    local page = M.UnitPage
    if not (page and type(page.ApplyDispelSymbolOffsets) == "function") then return false end
    Auras.ClearDragOffsets(handle)
    page.ApplyDispelSymbolOffsets(unit, reason or "MSUF2_UNIT_PREVIEW_DISPEL_SYMBOL_DRAG_END")
    RequestPreviewRefresh(box, reason or "MSUF2_UNIT_PREVIEW_DISPEL_SYMBOL_DRAG_END")
    return true
end

function DispelPreview.Availability(key, runtimeSpec)
    key = Auras.PreviewUnitKey(key)
    local model = key and MenuModel()
    if not (key and type(runtimeSpec) == "table")
        or (model and type(model.UnitEnabled) == "function" and model.UnitEnabled(key) ~= true) then
        return false, false
    end
    local a3 = MSUF.MSUF_Auras3
    local overlay, symbol = runtimeSpec.dispelOverlay, runtimeSpec.dispelSymbol
    return overlay and overlay.enabled == true or false,
        symbol and symbol.enabled == true and a3 and a3.DispelSymbol ~= nil or false
end

function DispelPreview.SymbolMetrics(symbol)
    local DS = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.DispelSymbol
    if not DS then return end
    local size = ClampNumber(symbol and symbol.size, 14, 4, 64)
    local spacing = ClampNumber(symbol and symbol.spacing, 2, 0, 32)
    local count = DS.Mode(symbol and symbol.mode) == "TOP" and 1 or #DS.types
    return DS, count, size, spacing, NormalizeAnchor(symbol and symbol.anchor, "TOPRIGHT"),
        DS.ResolveGrowth(symbol and symbol.growth, symbol and symbol.anchor)
end

function DispelPreview.SlotOffset(symbol, index, size, spacing, growth)
    local offset = ((tonumber(index) or 1) - 1) * (size + spacing)
    local x, y = 0, 0
    if growth == "LEFT" then x = -offset
    elseif growth == "UP" then y = offset
    elseif growth == "DOWN" then y = -offset
    else x = offset end
    return (tonumber(symbol and symbol.x) or 0) + x,
        (tonumber(symbol and symbol.y) or 0) + y
end

function DispelPreview.SymbolBounds(symbol, frameW, frameH)
    local DS, count, size, spacing, anchor, growth = DispelPreview.SymbolMetrics(symbol)
    if not DS then return end
    local baseX, baseY = AnchorOffset(anchor, frameW, frameH)
    local anchorX, anchorY = AnchorOffset(anchor, size, size)
    local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
    for index = 1, count do
        local x, y = DispelPreview.SlotOffset(symbol, index, size, spacing, growth)
        local slotLeft, slotBottom = baseX + x - anchorX, baseY + y - anchorY
        left, right = min(left, slotLeft), max(right, slotLeft + size)
        bottom, top = min(bottom, slotBottom), max(top, slotBottom + size)
    end
    return left, right, bottom, top, DS, count, size, spacing, anchor, growth
end

function Auras.ExpandDispelFootprint(runtimeSpec, frameW, frameH, minX, maxX, minY, maxY, symbolWanted)
    local symbol = runtimeSpec and runtimeSpec.dispelSymbol
    if not (symbolWanted == true and symbol and symbol.enabled == true) then
        return minX, maxX, minY, maxY
    end
    local left, right, bottom, top = DispelPreview.SymbolBounds(symbol, frameW, frameH)
    if not left then return minX, maxX, minY, maxY end
    minX, maxX = min(minX, left), max(maxX, right)
    minY, maxY = min(minY, bottom), max(maxY, top)
    return minX, maxX, minY, maxY
end
