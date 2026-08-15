--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua
--- Cold-path buff/debuff preview provider for the MSUF2 unit frame preview.
---
--- Reads Auras3 menu-model settings and draws fake aura buttons for layout feedback only.
--- Live aura filtering, icon, stack, and duration data stay in Blizzard's native 12.1 aura containers.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local PREVIEW_ICONS = 4
local Preview = MSUF.UFPreview or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local CurrentPanelKey = PreviewModel.CurrentPanelKey
local MakeFS = PreviewModel.MakeFS
local RoundOffset = (MSUF.UFPreviewCore and MSUF.UFPreviewCore.RoundOffset) or function(v)
    v = tonumber(v) or 0
    if v >= 0 then return floor(v + 0.5) end
    return -floor((-v) + 0.5)
end
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
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local helpers = menu and menu.PreviewHelpers
    local place = helpers and helpers.PlaceHandleAroundRegions
    if type(place) ~= "function" then return false end
    return place(handle, parent, regions, pad) == true
end
local function AuraDurationBarColor()
    local auras3 = MSUF.MSUF_Auras3
    local resolver = auras3 and auras3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
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
local AURA_PREVIEW_KINDS = { "buff", "debuff", "custom1", "custom2", "custom3", "custom4" }
local AURA_PREVIEW_LAYER = {
    buff = "buff", debuff = "debuff",
    custom1 = "auras", custom2 = "auras", custom3 = "auras", custom4 = "auras",
}
local AURA_ANCHOR_OK = {
    TOPLEFT=true, TOP=true, TOPRIGHT=true,
    LEFT=true, CENTER=true, RIGHT=true,
    BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true,
}
--- Justification the live runtime derives from each aura text anchor. Baked into
--- a lookup so per-icon placement costs one table read instead of the runtime's
--- if-chain over anchor strings.
local AURA_TEXT_JUSTIFY = {
    TOPLEFT     = { "LEFT",   "TOP" },
    TOP         = { "CENTER", "TOP" },
    TOPRIGHT    = { "RIGHT",  "TOP" },
    LEFT        = { "LEFT",   "MIDDLE" },
    CENTER      = { "CENTER", "MIDDLE" },
    RIGHT       = { "RIGHT",  "MIDDLE" },
    BOTTOMLEFT  = { "LEFT",   "BOTTOM" },
    BOTTOM      = { "CENTER", "BOTTOM" },
    BOTTOMRIGHT = { "RIGHT",  "BOTTOM" },
}
local AURA_TEXTURES = {
    buff = { 135987, 136116, 135932, 136085, 132333, 135981, 136048, 135964 },
    debuff = { 136118, 136139, 136197, 135817, 132851, 136188, 136170, 135813 },
}
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local function MenuModel()
    local a3 = MSUF and MSUF.MSUF_Auras3
    return type(a3) == "table" and a3.MenuModel or nil
end
local function ApplyService()
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    return (menu and menu.ApplyService) or _G.MSUF_Menu2_ApplyService
end
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
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local selections = type(menu) == "table" and menu.unitAuraTabSelection or nil
    local kind = NormalizeKind(type(selections) == "table" and selections[unit] or nil)
    if not kind then return nil end
    local allTools = menu.unitAuraToolSelection
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
    if key ~= "player" and key ~= "target" and key ~= "focus" and key ~= "boss" then return false end
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
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    return nil
end
local function PreviewUnit(box)
    if not box then return nil end
    local key = box.key
    if not key and box._msufPanel and (box._msufPanel._msufGetCurrentKey or box._msufPanel._msufLastApplyKey ~= nil) then key = CurrentPanelKey(box._msufPanel) end
    key = Auras.PreviewUnitKey(key)
    if key then box.key = key end
    return key
end
local function RuntimeUnit(unit)
    return unit == "boss" and "boss1" or unit
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
    local apply = ApplyService()
    if apply and type(apply.RequestAuras) == "function" then
        apply.RequestAuras(unit, reason)
        if type(apply.Flush) == "function" then apply.Flush() end
        return true
    elseif apply and type(apply.RequestUnit) == "function" then
        apply.RequestUnit(unit, reason, { auras = true, preview = true })
        if type(apply.Flush) == "function" then apply.Flush() end
        return true
    end
    local model = MenuModel()
    if model and type(model.Apply) == "function" then
        model.Apply(unit, reason)
        return true
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.BumpRuntimeConfig) == "function" and type(a3.RefreshUnit) ~= "function" then a3.BumpRuntimeConfig() end
    local function Refresh(runtime)
        if a3 and type(a3.UpdateUnitAnchor) == "function" then
            a3.UpdateUnitAnchor(runtime)
        end
        if a3 and type(a3.RefreshUnit) == "function" then
            a3.RefreshUnit(runtime)
        elseif a3 and type(a3.RequestUnit) == "function" then
            a3.RequestUnit(runtime)
        end
    end
    if unit == "boss" then
        for i = 1, 5 do Refresh("boss" .. i) end
    else
        Refresh(unit)
    end
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
local function SyncPopup(unit)
    if type(_G.MSUF_SyncAuras3PositionPopup) == "function" then _G.MSUF_SyncAuras3PositionPopup(RuntimeUnit(unit)) end
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
        if not SetDragPoint(handle, "Visual", visual, dx, dy) and (dx ~= 0 or dy ~= 0) then
            moved = MoveFrameBy(visual, dx, dy) or moved
        else
            moved = true
        end
    end
    return moved == true
end
function Auras.ClearDragOffsets(handle)
    if not handle then return end
    handle._msufAuraDragX = nil
    handle._msufAuraDragY = nil
    handle._msufAuraDragHandlePoint = nil
    handle._msufAuraDragHandleRel = nil
    handle._msufAuraDragHandleRelPoint = nil
    handle._msufAuraDragHandleX = nil
    handle._msufAuraDragHandleY = nil
    handle._msufAuraDragVisualPoint = nil
    handle._msufAuraDragVisualRel = nil
    handle._msufAuraDragVisualRelPoint = nil
    handle._msufAuraDragVisualX = nil
    handle._msufAuraDragVisualY = nil
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
function Auras.CreateHandles(box, makeHandle)
    if not (box and type(makeHandle) == "function") then return end
    if not box.handleAuraBuffs then
        local spec = AURA_HANDLE_FIELDS.buff
        box.handleAuraBuffs = makeHandle(box, "auraBuffs", {
            auraPreviewKind = "buff",
            defaultX = spec.defaultX,
            defaultY = spec.defaultY,
            visualOnly = true,
            readOffsets = Auras.ReadOffsets,
            writeOffsets = Auras.WriteOffsets,
            dragOffsets = Auras.DragOffsets,
            clearDragOffsets = Auras.ClearDragOffsets,
            commitOffsets = Auras.CommitOffsets,
            section = "auras3",
        }, spec.label, spec.color)
    end
    if not box.handleAuraDebuffs then
        local spec = AURA_HANDLE_FIELDS.debuff
        box.handleAuraDebuffs = makeHandle(box, "auraDebuffs", {
            auraPreviewKind = "debuff",
            defaultX = spec.defaultX,
            defaultY = spec.defaultY,
            visualOnly = true,
            readOffsets = Auras.ReadOffsets,
            writeOffsets = Auras.WriteOffsets,
            dragOffsets = Auras.DragOffsets,
            clearDragOffsets = Auras.ClearDragOffsets,
            commitOffsets = Auras.CommitOffsets,
            section = "auras3",
        }, spec.label, spec.color)
    end
    for index = 1, 4 do
        local kind = "custom" .. tostring(index)
        local field = "handleAuraCustom" .. tostring(index)
        if not box[field] then
            local spec = AURA_HANDLE_FIELDS[kind]
            box[field] = makeHandle(box, "auraCustom" .. tostring(index), {
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
            }, (index == 4 and PreviewUnit(box) == "player") and "Defensive Buffs" or spec.label, spec.color)
        end
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
local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT" end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end
local function Growth(cfg, kind)
    local isBuff = kind == "buff"
    local growth = isBuff and (cfg.buffGrowthX or cfg.growth) or (cfg.debuffGrowthX or cfg.growth)
    local rowWrap = isBuff and (cfg.buffGrowthY or cfg.rowWrap) or (cfg.debuffGrowthY or cfg.rowWrap)
    local gx = growth == "LEFT" and -1 or 1
    local gy = rowWrap == "UP" and 1 or -1
    local vertical = false
    if growth == "UP" then
        gx, gy, vertical = 1, 1, true
    elseif growth == "DOWN" then
        gx, gy, vertical = 1, -1, true
    end
    return gx, gy, vertical, ButtonAnchor(gx, gy)
end
local function AnchorOffset(anchor, w, h)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPLEFT" then return 0, h end
    if anchor == "TOP" then return w * 0.5, h end
    if anchor == "TOPRIGHT" then return w, h end
    if anchor == "LEFT" then return 0, h * 0.5 end
    if anchor == "CENTER" then return w * 0.5, h * 0.5 end
    if anchor == "RIGHT" then return w, h * 0.5 end
    if anchor == "BOTTOMLEFT" then return 0, 0 end
    if anchor == "BOTTOM" then return w * 0.5, 0 end
    if anchor == "BOTTOMRIGHT" then return w, 0 end
    return 0, h
end
local function NormalizeAnchor(anchor, fallback)
    anchor = tostring(anchor or "")
    return AURA_ANCHOR_OK[anchor] and anchor or fallback or "TOPLEFT"
end
--- Inward offset from a lane's initial corner for the shared style padding,
--- mirroring the runtime container's SetFlowLayoutPadding inset.
local function PaddingInset(anchor, pad)
    pad = tonumber(pad) or 0
    if pad == 0 then return 0, 0 end
    anchor = tostring(anchor or "TOPLEFT")
    local dx = anchor:find("LEFT", 1, true) and pad or (anchor:find("RIGHT", 1, true) and -pad or 0)
    local dy = anchor:find("BOTTOM", 1, true) and pad or (anchor:find("TOP", 1, true) and -pad or 0)
    return dx, dy
end
--- Shared icon style for a previewed lane: the compiled runtime style when the
--- lane metrics carry one, otherwise the scope-resolved preview style.
local function LaneIconStyle(metrics, _, kind)
    if metrics and metrics.iconStyle then return metrics.iconStyle end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.IconStylePreviewForKind) == "function" then
        return a3.IconStylePreviewForKind((metrics and metrics.appearanceKind) or kind)
    end
    return nil
end
local function AnchorBase(anchor, frameW, frameH)
    return AnchorOffset(anchor, frameW, frameH)
end
local function GridShape(count, perRow, vertical)
    count = max(1, RoundOffset(count))
    perRow = max(1, RoundOffset(perRow))
    if vertical then return 1, count end
    return min(count, perRow), max(1, ceil(count / perRow))
end
local function IconGridCoord(index, perRow, vertical)
    local per = max(1, RoundOffset(perRow))
    local idx = index - 1
    if vertical then
        return 0, idx
    end
    local col = idx % per
    return col, (idx - col) / per
end
local function IconRect(anchor, laneW, laneH, size, x, y)
    local laneAnchorX, laneAnchorY = AnchorOffset(anchor, laneW, laneH)
    local iconAnchorX, iconAnchorY = AnchorOffset(anchor, size, size)
    local left = laneAnchorX + x - iconAnchorX
    local bottom = laneAnchorY + y - iconAnchorY
    return left, bottom, left + size, bottom + size
end
local function ResolvePreviewIconShape(requested, effective, runtimeSpec)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local portraitShape = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.shape
    if a3 and type(a3.ResolveAuraIconShape) == "function" then
        return a3.ResolveAuraIconShape(requested or effective, portraitShape)
    end
    return effective or "RECTANGLE"
end

local function LaneBounds(cfg, kind, frameW, frameH, unit, runtimeSpec, forcePreview)
    if not cfg then return nil end
    local isBuff = kind == "buff"
    if not forcePreview then
        if isBuff and cfg.showBuffs ~= true then return nil end
        if (not isBuff) and cfg.showDebuffs ~= true then return nil end
    end
    local metrics = isBuff and cfg.buffMetrics or cfg.debuffMetrics
    if metrics and metrics.enabled ~= true and not forcePreview then return nil end
    local count = metrics and metrics.num or (isBuff and cfg.maxBuffs or cfg.maxDebuffs)
    count = RuntimeRound(ClampNumber(count, isBuff and 8 or 12, 0, 80))
    if count <= 0 then
        if not forcePreview then return nil end
        count = PREVIEW_ICONS
    end
    local size = ClampNumber(metrics and metrics.size or (isBuff and cfg.buffSize or cfg.debuffSize), 26, 1, 128)
    local x = metrics and metrics.x or (isBuff and cfg.buffX or cfg.debuffX)
    local y = metrics and metrics.y or (isBuff and cfg.buffY or cfg.debuffY)
    x = RuntimeRound(ClampNumber(x, 0, -4096, 4096))
    y = RuntimeRound(ClampNumber(y, 0, -4096, 4096))
    local defaultAnchor = isBuff and "BOTTOMRIGHT" or "TOPLEFT"
    local anchor = NormalizeAnchor(metrics and metrics.anchor or (isBuff and cfg.buffAnchor or cfg.debuffAnchor), defaultAnchor)
    local spacing = ClampNumber(metrics and metrics.spacing or cfg.spacing, 2, 0, 64)
    local perRow = metrics and metrics.perRow or ((isBuff and cfg.buffPerRow or cfg.debuffPerRow) or cfg.perRow)
    perRow = RuntimeRound(ClampNumber(perRow, 12, 1, 40))
    local shown = min(max(1, count), PREVIEW_ICONS)
    local step = tonumber(metrics and metrics.step) or (size + spacing)
    local growthX, growthY, vertical, initialAnchor
    if metrics then
        growthX = tonumber(metrics.growthX) or 1
        growthY = tonumber(metrics.growthY) or -1
        vertical = metrics.verticalGrowth == true
        initialAnchor = metrics.initialAnchor or ButtonAnchor(growthX, growthY)
    else
        growthX, growthY, vertical, initialAnchor = Growth(cfg, kind)
    end
    local baseX, baseY = AnchorBase(anchor, frameW, frameH)
    -- Runtime lane metrics already include the shared style padding in their
    -- width/height; the raw-config fallback adds it the same way the runtime
    -- compile does.
    local padding = RuntimeRound(ClampNumber(metrics and metrics.padding or cfg.stylePadding, 0, 0, 16))
    local laneW, laneH
    if metrics and metrics.width and metrics.height then
        laneW, laneH = max(1, metrics.width), max(1, metrics.height)
    else
        local cols, rows = GridShape(count, perRow, vertical)
        laneW = max(1, cols * size + max(cols - 1, 0) * spacing + 2 * padding)
        laneH = max(1, rows * size + max(rows - 1, 0) * spacing + 2 * padding)
    end
    local anchorLocalX, anchorLocalY = AnchorOffset(anchor, laneW, laneH)
    local laneLeft = baseX + x - anchorLocalX
    local laneBottom = baseY + y - anchorLocalY
    local padX, padY = PaddingInset(initialAnchor, padding)
    local iconMinX, iconMinY, iconMaxX, iconMaxY
    for i = 1, shown do
        local col, row = IconGridCoord(i, perRow, vertical)
        local l, b, r, t = IconRect(initialAnchor, laneW, laneH, size, col * step * growthX + padX, row * step * growthY + padY)
        iconMinX = iconMinX and min(iconMinX, l) or l
        iconMinY = iconMinY and min(iconMinY, b) or b
        iconMaxX = iconMaxX and max(iconMaxX, r) or r
        iconMaxY = iconMaxY and max(iconMaxY, t) or t
    end
    iconMinX, iconMinY, iconMaxX, iconMaxY = iconMinX or 0, iconMinY or 0, iconMaxX or size, iconMaxY or size
    local left = laneLeft + min(0, iconMinX)
    local right = laneLeft + max(laneW, iconMaxX)
    local bottom = laneBottom + min(0, iconMinY)
    local top = laneBottom + max(laneH, iconMaxY)
    return {
        kind = kind,
        left = left,
        right = right,
        bottom = bottom,
        top = top,
        shown = shown,
        size = size,
        iconZoom = ClampNumber(metrics and metrics.iconZoom or (isBuff and cfg.buffIconZoom or cfg.debuffIconZoom), 100, 100, 200),
        iconShape = ResolvePreviewIconShape(
            metrics and metrics.requestedIconShape or (isBuff and cfg.buffRequestedIconShape or cfg.debuffRequestedIconShape),
            metrics and metrics.iconShape or (isBuff and cfg.buffIconShape or cfg.debuffIconShape), runtimeSpec),
        spacing = spacing,
        perRow = perRow,
        x = x,
        y = y,
        frameW = frameW,
        frameH = frameH,
        laneW = laneW,
        laneH = laneH,
        baseX = baseX,
        baseY = baseY,
        laneLeft = laneLeft,
        laneBottom = laneBottom,
        iconMinX = iconMinX,
        iconMaxX = iconMaxX,
        iconMinY = iconMinY,
        iconMaxY = iconMaxY,
        anchorBottom = laneBottom,
        growthX = growthX,
        growthY = growthY,
        verticalGrowth = vertical == true,
        layer = isBuff and cfg.buffLayer or cfg.debuffLayer,
        point = "BOTTOMLEFT",
        relativePoint = "BOTTOMLEFT",
        initialAnchor = initialAnchor,
        padding = padding,
        iconStyle = LaneIconStyle(metrics, unit, isBuff and "buff" or "debuff"),
    }
end

local function CustomGrowth(growth)
    growth = tostring(growth or "LEFTDOWN"):upper()
    if growth == "LEFTUP" then return -1, 1, false end
    if growth == "RIGHTUP" then return 1, 1, false end
    if growth == "RIGHTDOWN" then return 1, -1, false end
    if growth == "UP" then return 1, 1, true end
    if growth == "DOWN" then return 1, -1, true end
    return -1, -1, false
end

local function CustomLaneBounds(item, styleItem, kind, frameW, frameH, metrics, previewEntries, unit, fallbackPadding, runtimeSpec, forcePreview)
    if type(item) ~= "table" then return nil end
    -- Any custom lane with configured spells previews them 1:1 with the real
    -- spell icons; curated index-4 lanes may show while disabled.
    local trackedPreview = type(previewEntries) == "table" and #previewEntries > 0
    local portrait = runtimeSpec and runtimeSpec.portrait
    local portraitContainer = kind == "custom4"
        and (unit == "player" or unit == "target" or unit == "focus" or unit == "boss")
        and item.portraitIcon == true
        and portrait and (portrait.enabled == true or item.portraitPositionWhenDisabled == true)
    local playerDefensives = unit == "player" and kind == "custom4"
    if not forcePreview and item.enabled ~= true
        and not (kind == "custom4" and not playerDefensives and trackedPreview) then
        return nil
    end
    if portraitContainer then return nil end
    local layoutPlaced = type(item.placed) == "table" and item.placed or {}
    local placed = type(styleItem) == "table" and type(styleItem.placed) == "table"
        and styleItem.placed or layoutPlaced
    local count = metrics and metrics.num or RuntimeRound(ClampNumber(layoutPlaced.max, 8, 0, 40))
    if trackedPreview then count = min(count, #previewEntries) end
    if count <= 0 then
        if not forcePreview then return nil end
        count = PREVIEW_ICONS
    end
    local size = ClampNumber(metrics and metrics.size or layoutPlaced.size, 24, 1, 128)
    local spacing = ClampNumber(metrics and metrics.spacing or layoutPlaced.spacing, 2, 0, 64)
    local perRow = metrics and metrics.perRow or RuntimeRound(ClampNumber(layoutPlaced.perRow, 4, 1, 40))
    local shown = min(max(1, count), trackedPreview and count or PREVIEW_ICONS)
    local anchor = NormalizeAnchor(metrics and metrics.anchor or layoutPlaced.anchor, "TOPRIGHT")
    local x = metrics and metrics.x or RuntimeRound(ClampNumber(layoutPlaced.x, 0, -4096, 4096))
    local y = metrics and metrics.y or RuntimeRound(ClampNumber(layoutPlaced.y, 0, -4096, 4096))
    local growthX, growthY, vertical, initialAnchor
    if metrics then
        growthX = tonumber(metrics.growthX) or -1
        growthY = tonumber(metrics.growthY) or -1
        vertical = metrics.verticalGrowth == true
        initialAnchor = metrics.initialAnchor or ButtonAnchor(growthX, growthY)
    else
        growthX, growthY, vertical = CustomGrowth(layoutPlaced.growth)
        initialAnchor = ButtonAnchor(growthX, growthY)
    end
    local padding = RuntimeRound(ClampNumber(metrics and metrics.padding or fallbackPadding, 0, 0, 16))
    local laneW, laneH
    if metrics and metrics.width and metrics.height then
        laneW, laneH = max(1, metrics.width), max(1, metrics.height)
    else
        local cols, rows = GridShape(count, perRow, vertical)
        laneW = max(1, cols * size + max(cols - 1, 0) * spacing + 2 * padding)
        laneH = max(1, rows * size + max(rows - 1, 0) * spacing + 2 * padding)
    end
    local baseX, baseY = AnchorBase(anchor, frameW, frameH)
    local anchorLocalX, anchorLocalY = AnchorOffset(anchor, laneW, laneH)
    local laneLeft, laneBottom = baseX + x - anchorLocalX, baseY + y - anchorLocalY
    local previewTextures
    if trackedPreview then
        previewTextures = {}
        for i = 1, count do previewTextures[i] = previewEntries[i] and previewEntries[i].icon end
    end
    return {
        kind = kind,
        left = laneLeft,
        right = laneLeft + laneW,
        bottom = laneBottom,
        top = laneBottom + laneH,
        shown = shown,
        size = size,
        spacing = spacing,
        perRow = perRow,
        x = x,
        y = y,
        laneW = laneW,
        laneH = laneH,
        laneLeft = laneLeft,
        laneBottom = laneBottom,
        growthX = growthX,
        growthY = growthY,
        verticalGrowth = vertical == true,
        initialAnchor = initialAnchor,
        layer = RuntimeRound(ClampNumber(item.layer, 9, 0, 30)),
        custom = true,
        item = item,
        stylePlaced = placed,
        auraType = item.auraType == "DEBUFF" and "debuff" or "buff",
        previewTextures = previewTextures,
        padding = padding,
        iconStyle = LaneIconStyle(metrics, unit,
            kind == "custom4" and unit == "player" and "playerDefensives"
                or kind == "custom4" and (unit == "target" or unit == "focus" or unit == "boss") and "targetDots"
                or (item.auraType == "DEBUFF" and "debuff" or "buff")),
        alpha = ClampNumber(placed.alpha, 1, 0, 1),
        iconZoom = ClampNumber(placed.iconZoom, 100, 100, 200),
        iconShape = ResolvePreviewIconShape(metrics and metrics.requestedIconShape or placed.iconShape,
            metrics and metrics.iconShape or placed.iconShape, runtimeSpec),
    }
end

local function PortraitAuraBounds(item, styleItem, runtimeSpec, previewEntries, unit, metrics, exactPortraitRect, fallbackKind, forcePreview)
    if not (item and item.portraitIcon == true) then return nil end
    if item.enabled ~= true and not forcePreview then return nil end
    local portrait = runtimeSpec and runtimeSpec.portrait
    if not (portrait and (portrait.enabled == true or item.portraitPositionWhenDisabled == true)) then return nil end
    local layoutPlaced = type(item.placed) == "table" and item.placed or {}
    local placed = type(styleItem) == "table" and type(styleItem.placed) == "table"
        and styleItem.placed or layoutPlaced
    local maxCount = RuntimeRound(ClampNumber(item.portraitMaxIcons, 1, 1, 8))
    if maxCount <= 0 then return nil end
    local trackedCount = type(previewEntries) == "table" and #previewEntries or 0
    local shown = min(maxCount, trackedCount > 0 and trackedCount or PREVIEW_ICONS, PREVIEW_ICONS)
    local previewTextures = {}
    local fallback = AURA_TEXTURES[fallbackKind] or AURA_TEXTURES.buff
    for i = 1, shown do
        previewTextures[i] = previewEntries and previewEntries[i] and previewEntries[i].icon
            or fallback[((i - 1) % #fallback) + 1]
    end
    local portraitWidth = ClampNumber(portrait.width or portrait.size, 24, 8, 128)
    local portraitHeight = ClampNumber(portrait.height or portrait.size, 24, 8, 128)
    local size = min(portraitWidth, portraitHeight)
    local iconWidth = exactPortraitRect == true and portraitWidth or size
    local iconHeight = exactPortraitRect == true and portraitHeight or size
    local growthX, growthY, verticalGrowth = CustomGrowth(layoutPlaced.growth)
    local initialAnchor = ButtonAnchor(growthX, growthY)
    local perRow = verticalGrowth and 1 or RuntimeRound(ClampNumber(layoutPlaced.perRow, 4, 1, 40))
    local cols, rows = GridShape(shown, perRow, verticalGrowth)
    local insetX = (portraitWidth - iconWidth) * 0.5
    local insetY = (portraitHeight - iconHeight) * 0.5
    return {
        size = size,
        iconWidth = iconWidth,
        iconHeight = iconHeight,
        spacing = 0,
        shown = shown,
        perRow = perRow,
        cols = cols,
        rows = rows,
        width = max(1, cols * iconWidth),
        height = max(1, rows * iconHeight),
        growthX = growthX,
        growthY = growthY,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = initialAnchor,
        portraitInsetX = initialAnchor:find("RIGHT", 1, true) and -insetX or insetX,
        portraitInsetY = initialAnchor:find("BOTTOM", 1, true) and insetY or -insetY,
        item = item,
        stylePlaced = placed,
        previewTextures = previewTextures,
        iconStyle = LaneIconStyle(metrics, unit,
            unit == "player" and "playerDefensives"
                or (unit == "target" or unit == "focus" or unit == "boss") and "targetDots"
                or fallbackKind),
        alpha = ClampNumber(placed.alpha, 1, 0, 1),
        iconZoom = ClampNumber(placed.iconZoom, 100, 100, 200),
        iconShape = exactPortraitRect == true
            and ResolvePreviewIconShape("FOLLOW_PORTRAIT", nil, runtimeSpec)
            or ResolvePreviewIconShape(metrics and metrics.requestedIconShape or placed.iconShape,
                metrics and metrics.iconShape or placed.iconShape, runtimeSpec),
        showCooldownText = placed.showCooldown ~= false and item.portraitCooldownText ~= false,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        showStacks = placed.showStacks ~= false,
        showDurationBar = placed.showDurationBar == true,
        cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
        -- Runtime parity: the standalone bar's saved Edit Mode offsets never
        -- move the portrait icon; it sits exactly inside the portrait.
        x = 0,
        y = 0,
    }
end

local function DefensivePortraitBounds(item, styleItem, runtimeSpec, previewEntries, unit, metrics, forcePreview)
    if unit ~= "player" then return nil end
    return PortraitAuraBounds(item, styleItem, runtimeSpec, previewEntries, unit, metrics, false, "buff", forcePreview)
end

local function TargetDotPortraitBounds(item, styleItem, runtimeSpec, previewEntries, unit, metrics, forcePreview)
    if unit ~= "target" and unit ~= "focus" and unit ~= "boss" then return nil end
    return PortraitAuraBounds(item, styleItem, runtimeSpec, previewEntries, unit, metrics, true, "debuff", forcePreview)
end

function Auras.BuildState(key, frameW, frameH, runtimeSpec, forceStandardLanes)
    local runtimeAuras = runtimeSpec and runtimeSpec.auras
    local model = MenuModel()
    key = Auras.PreviewUnitKey(key)
    if not (key and model and type(model.ReadPreviewConfig) == "function") then return nil end
    local cfg = model.ReadPreviewConfig(key)
    if not cfg then return nil end
    local stylePreviewKind = SelectedUnitAuraStyleKind(key)
    forceStandardLanes = forceStandardLanes == true
    local buff = LaneBounds(cfg, "buff", frameW, frameH, key, runtimeSpec,
        forceStandardLanes or stylePreviewKind == "buff")
    local debuff = LaneBounds(cfg, "debuff", frameW, frameH, key, runtimeSpec,
        forceStandardLanes or stylePreviewKind == "debuff")
    local previewFrameEffect = SelectedUnitAuraFrameEffect(model, key, stylePreviewKind)
    local state = {
        unit = key, cfg = cfg, runtime = runtimeAuras,
        buff = buff, debuff = debuff, stylePreviewKind = stylePreviewKind,
        previewFrameEffect = previewFrameEffect,
        previewFrameEffectLayer = previewFrameEffect and AURA_PREVIEW_LAYER[stylePreviewKind] or nil,
    }
    for index = 1, 4 do
        local kind = "custom" .. tostring(index)
        local metrics = type(cfg.customMetrics) == "table" and cfg.customMetrics[index] or nil
        local item = CustomItem(model, key, index, false)
        local styleItem = CustomStyleItem(model, key, index)
        local previewEntries
        if type(model.CustomContainerPreviewEntries) == "function" then
            previewEntries = model.CustomContainerPreviewEntries(key, index)
        elseif type(model.CustomContainerSpellEntries) == "function" then
            previewEntries = model.CustomContainerSpellEntries(key, index)
        end
        local forceStylePreview = stylePreviewKind == kind
        state[kind] = CustomLaneBounds(item, styleItem, kind, frameW, frameH, metrics, previewEntries,
            key, cfg.stylePadding, runtimeSpec, forceStylePreview)
        if index == 4 then
            if key == "player" then
                state.defensivePortrait = DefensivePortraitBounds(
                    item, styleItem, runtimeSpec, previewEntries, key, metrics, forceStylePreview)
            else
                state.targetDotPortrait = TargetDotPortraitBounds(
                    item, styleItem, runtimeSpec, previewEntries, key, metrics, forceStylePreview)
            end
        end
    end
    if not state.buff and not state.debuff and not state.custom1 and not state.custom2
        and not state.custom3 and not state.custom4
        and not state.defensivePortrait and not state.targetDotPortrait then
        return nil
    end
    return state
end
function Auras.HasVisibleLayer(state, visibility)
    if not state then return false end
    for _, kind in ipairs(AURA_PREVIEW_KINDS) do
        if state[kind] and (not visibility or visibility[AURA_PREVIEW_LAYER[kind]] ~= false) then return true end
    end
    return (state.defensivePortrait or state.targetDotPortrait) ~= nil
        and (not visibility or visibility.auras ~= false)
end
function Auras.ExpandFootprint(state, minX, maxX, minY, maxY, visibility)
    if not state then return minX, maxX, minY, maxY end
    for _, kind in ipairs(AURA_PREVIEW_KINDS) do
        local b = state[kind]
        if b and (not visibility or visibility[AURA_PREVIEW_LAYER[kind]] ~= false) then
            minX = min(minX, b.left)
            maxX = max(maxX, b.right)
            minY = min(minY, b.bottom)
            maxY = max(maxY, b.top)
        end
    end
    return minX, maxX, minY, maxY
end

-- Unit-frame dispel preview layers. These frames exist only inside the loaded
-- options preview and are repainted by its cold refresh path; they register no
-- events, timers, or OnUpdate scripts and never participate in live combat.
Auras.DispelPreview = Auras.DispelPreview or {}
local DispelPreview = Auras.DispelPreview
local function UnitDispelPage()
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    return menu and menu.UnitPage
end

function DispelPreview.ReadOffsets(handle)
    local unit = PreviewUnit(handle and handle._preview)
    if not unit then return nil end
    local page = UnitDispelPage()
    if page and type(page.ReadDispelSymbolOffsets) == "function" then
        return page.ReadDispelSymbolOffsets(unit)
    end
end

function DispelPreview.WriteOffsets(handle, x, y, reason)
    local unit = PreviewUnit(handle and handle._preview)
    local page = unit and UnitDispelPage()
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
    local page = UnitDispelPage()
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
    local a3 = MSUF and MSUF.MSUF_Auras3
    local overlay, symbol = runtimeSpec.dispelOverlay, runtimeSpec.dispelSymbol
    return overlay and overlay.enabled == true or false,
        symbol and symbol.enabled == true and a3 and a3.DispelSymbol ~= nil or false
end

function DispelPreview.SymbolMetrics(symbol)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local DS = a3 and a3.DispelSymbol
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
    local baseX, baseY = AnchorBase(anchor, frameW, frameH)
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

function Auras.ApplyDispelLayerVisibility(box)
    local mock = box and box.mock
    if not mock then return end
    local available = box.layerAvailable or {}
    local visible = box.layerVisibility or {}
    local overlayOn = available.dispelOverlay ~= false and visible.dispelOverlay ~= false
    local symbolOn = available.dispelSymbol ~= false and visible.dispelSymbol ~= false
    if mock._msufPreviewDispelOverlayHost then
        mock._msufPreviewDispelOverlayHost:SetShown(overlayOn)
    end
    if mock._msufPreviewDispelSymbolHost then
        mock._msufPreviewDispelSymbolHost:SetShown(symbolOn)
    end
    for i = 1, #(mock._msufPreviewDispelSymbols or {}) do
        local holder = mock._msufPreviewDispelSymbols[i]
        holder:SetShown(symbolOn and i <= (mock._msufPreviewDispelSymbolCount or 0))
    end
    local symbolHandle = box.handleDispelSymbol
    if symbolHandle then
        local shown = symbolOn and (mock._msufPreviewDispelSymbolCount or 0) > 0
        symbolHandle._msufPlaced = shown
        symbolHandle:SetShown(shown)
    end
end

function Auras.LayoutDispelLayers(box, mock, runtimeSpec, S, baseLevel, overlayAvailable, symbolAvailable, frameW, frameH)
    if not (box and mock and type(S) == "function") then return end
    local visible = box.layerVisibility or {}
    local overlay = runtimeSpec and runtimeSpec.dispelOverlay
    local overlayOn = overlayAvailable == true and visible.dispelOverlay ~= false
    local overlayHost = mock._msufPreviewDispelOverlayHost
    if overlayOn then
        if not overlayHost then
            overlayHost = CreateFrame("Frame", nil, mock)
            overlayHost:EnableMouse(false)
            overlayHost.Region = overlayHost:CreateTexture(nil, "OVERLAY")
            overlayHost.Region:SetTexture(TEX_W8)
            mock._msufPreviewDispelOverlayHost = overlayHost
            mock._msufPreviewDispelOverlayRegion = overlayHost.Region
        end
        overlayHost:ClearAllPoints()
        overlayHost:SetAllPoints(mock.healthBar or mock)
        if overlayHost.SetFrameLevel then
            overlayHost:SetFrameLevel(Layers.ElementLevel and Layers.ElementLevel(0, 0, 12)
                or ((baseLevel or 0) + 12))
        end
        local region = overlayHost.Region
        local target = overlay.onHealth ~= false and mock.hp or (mock.healthBar or mock)
        local style = tostring(overlay.style or "FULL"):upper()
        local thickness = max(1, S(runtimeSpec and runtimeSpec.border and runtimeSpec.border.highlightThickness or 3))
        region:ClearAllPoints()
        if style == "TOP" then
            region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
            region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
            region:SetHeight(thickness)
        elseif style == "BOTTOM" then
            region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
            region:SetHeight(thickness)
        elseif style == "LEFT" then
            region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
            region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
            region:SetWidth(thickness)
        elseif style == "RIGHT" then
            region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
            region:SetWidth(thickness)
        else
            region:SetAllPoints(target)
        end
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.SetDispelColorTexture) == "function" then
            a3.SetDispelColorTexture(region, a3.GetDispelColorPreviewType(), true, 1)
        else
            local color = runtimeSpec and runtimeSpec.dispel or nil
            region:SetColorTexture(tonumber(color and color.r) or 0.25,
                tonumber(color and color.g) or 0.75, tonumber(color and color.b) or 1, 1)
        end
        region:SetAlpha(ClampNumber(overlay.alpha, 0.35, 0, 1))
        region:Show()
        overlayHost:Show()
    elseif overlayHost then
        overlayHost:Hide()
    end

    local symbol = runtimeSpec and runtimeSpec.dispelSymbol
    local symbolOn = symbolAvailable == true and visible.dispelSymbol ~= false
    local symbolHandle = box.handleDispelSymbol
    local symbolHost = mock._msufPreviewDispelSymbolHost
    local holders = mock._msufPreviewDispelSymbols
    if symbolOn then
        local rawLeft, rawRight, rawBottom, rawTop, DS, count, rawSize, spacing, anchor, growth =
            DispelPreview.SymbolBounds(symbol, frameW, frameH)
        if not DS then
            mock._msufPreviewDispelSymbolCount = 0
            if symbolHost then symbolHost:Hide() end
            for index = 1, #(holders or {}) do holders[index]:Hide() end
            if symbolHandle then
                symbolHandle._msufAuraDragVisual = nil
                symbolHandle._msufPlaced = false
                symbolHandle:Hide()
            end
            return
        end
        if not symbolHost then
            symbolHost = CreateFrame("Frame", nil, mock)
            symbolHost:EnableMouse(false)
            mock._msufPreviewDispelSymbolHost = symbolHost
        end
        symbolHost:ClearAllPoints()
        symbolHost:SetSize(mock:GetWidth(), mock:GetHeight())
        symbolHost:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", 0, 0)
        symbolHost:Show()
        local size = max(1, S(rawSize))
        local style = DS.Style(symbol.style)
        local level = Layers.ElementLevel and Layers.ElementLevel(symbol.layer, 8, 8)
            or ((baseLevel or 0) + RuntimeRound(ClampNumber(symbol.layer, 8, 0, 30)) + 8)
        local strata = tostring(symbol.strata or "AUTO"):upper()
        if strata == "AUTO" then strata = mock.GetFrameStrata and mock:GetFrameStrata() or nil end
        holders = holders or {}
        mock._msufPreviewDispelSymbols = holders
        mock._msufPreviewDispelSymbolCount = count
        for index = 1, count do
            local holder = holders[index]
            if not holder then
                holder = CreateFrame("Frame", nil, symbolHost)
                holder:EnableMouse(false)
                holder.Texture = holder:CreateTexture(nil, "OVERLAY")
                holder.Texture:SetAllPoints(holder)
                holders[index] = holder
            end
            holder:SetSize(size, size)
            holder:ClearAllPoints()
            local x, y = DispelPreview.SlotOffset(symbol, index, rawSize, spacing, growth)
            holder:SetPoint(anchor, symbolHost, anchor, S(x), S(y))
            if holder.SetFrameLevel then holder:SetFrameLevel(level) end
            if strata and holder.SetFrameStrata then holder:SetFrameStrata(strata) end
            local texture = holder.Texture
            texture:SetAlpha(ClampNumber(symbol.alpha, 1, 0, 1))
            DS.PreviewArt(texture, style, DS.types[index])
            texture:Show()
            holder:Show()
        end
        for index = count + 1, #holders do holders[index]:Hide() end
        if symbolHandle then
            symbolHandle._msufAuraDragVisual = symbolHost
            -- Anchor the picker to the resolved symbol holders. Rebuilding the
            -- union from raw offsets rounds in a different order at fractional
            -- Fit scales and can move the reported center by a screen pixel.
            if not PlaceHandleAroundShownRegions(symbolHandle, mock, holders, 4) then
                PlaceMinimumHitHandle(symbolHandle, mock, S(rawLeft), S(rawBottom),
                    S(rawRight - rawLeft), S(rawTop - rawBottom), 4, 18)
            end
            symbolHandle._msufPlaced = true
            symbolHandle:Show()
        end
    else
        mock._msufPreviewDispelSymbolCount = 0
        if symbolHost then symbolHost:Hide() end
        for index = 1, #(holders or {}) do holders[index]:Hide() end
        if symbolHandle then
            symbolHandle._msufAuraDragVisual = nil
            symbolHandle._msufPlaced = false
            symbolHandle:Hide()
        end
    end
end
-- Reused per-lane font state. Lanes are laid out one after another and nothing
-- retains a reference past its own LayoutHandle call, so two scratch tables keep
-- the resolve allocation-free.
local _stackFontState, _timerFontState = {}, {}
--- Resolves the shared aura font once per lane. The global font lookup and the
--- safe-path resolve are cold-path calls, and every icon in a lane shares their
--- result, so running them per icon only multiplied the work by the sample count.
local function ResolveAuraFont(out, size)
    size = max(7, tonumber(size) or 14)
    local fontPath, fontFlags, r, g, b, _, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings() end
    fontPath = fontPath or FONT
    fontFlags = fontFlags or "OUTLINE"
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        local gdb = _G.MSUF_DB and _G.MSUF_DB.general
        fontPath = resolveSafe(fontPath, size, fontFlags, gdb and gdb.fontKey) or fontPath
    end
    out.path, out.size, out.flags = fontPath, size, fontFlags
    out.r, out.g, out.b = r or 1, g or 1, b or 1
    out.shadow = useShadow and 1 or 0
    -- Carries the addon-wide font epoch, so a late LibSharedMedia registration or
    -- a font switch re-stamps the dummy icons instead of holding a cached path.
    out.epoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    return out
end
--- Stamps a resolved font, skipping the setters while nothing changed. Dragging a
--- slider repaints the preview continuously with identical font state.
local function ApplyAuraFont(fs, font)
    if not (fs and font) then return end
    if fs.SetFont and (fs._msufAuraFontPath ~= font.path or fs._msufAuraFontSize ~= font.size
        or fs._msufAuraFontFlags ~= font.flags or fs._msufAuraFontEpoch ~= font.epoch) then
        if not pcall(fs.SetFont, fs, font.path, font.size, font.flags) then
            pcall(fs.SetFont, fs, FONT, font.size, font.flags)
        end
        fs._msufAuraFontPath, fs._msufAuraFontSize = font.path, font.size
        fs._msufAuraFontFlags, fs._msufAuraFontEpoch = font.flags, font.epoch
    end
    if fs.SetTextColor and (fs._msufAuraFontR ~= font.r or fs._msufAuraFontG ~= font.g or fs._msufAuraFontB ~= font.b) then
        fs:SetTextColor(font.r, font.g, font.b, 1)
        fs._msufAuraFontR, fs._msufAuraFontG, fs._msufAuraFontB = font.r, font.g, font.b
    end
    if fs.SetShadowOffset and fs._msufAuraFontShadow ~= font.shadow then
        fs:SetShadowOffset(font.shadow, -font.shadow)
        fs._msufAuraFontShadow = font.shadow
    end
end
local function EnsureVisual(box, kind, baseLevel)
    if not box then return nil end
    box.auraPreviewVisuals = box.auraPreviewVisuals or {}
    local visual = box.auraPreviewVisuals[kind]
    if not visual then
        visual = CreateFrame("Frame", nil, box.canvas or box.mock)
        visual._msufAuraVisualKind = kind
        visual._icons = {}
        box.auraPreviewVisuals[kind] = visual
    end
    local level = kind == "buff" and 29 or (kind == "debuff" and 30 or 32 + (tonumber(kind:match("(%d)$")) or 1))
    if visual.SetFrameLevel then
        visual:SetFrameLevel(Layers.ElementLevel and Layers.ElementLevel(level, 1, 0) or ((baseLevel or 0) + level))
    end
    return visual
end
local function CreateIcon(parent)
    -- The visible icon can sit above the canvas-owned mover (notably the
    -- portrait defensive lane). Use a Button so the proxy can preserve the
    -- mover's complete click contract in addition to drag forwarding.
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(18, 18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(TEX_W8)
    f.bg:SetVertexColor(0.07, 0.07, 0.08, 0.88)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    if f.tex.SetTexCoord then f.tex:SetTexCoord(0, 1, 0, 1) end
    -- Keep the animated swipe deterministically above the icon artwork.  The
    -- client does not guarantee ordering for two regions on the same draw
    -- layer/sublevel, which could leave this shown region hidden by f.tex.
    f.swipe = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, 0)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.58)
    f.swipe:Hide()
    f.durationBar = f:CreateTexture(nil, "OVERLAY")
    f.durationBar:SetTexture(TEX_W8)
    local durationR, durationG, durationB = AuraDurationBarColor()
    f.durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
    f.durationBar:Hide()
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetAllPoints(f)
    f.edge:SetTexture(TEX_W8)
    f.edge:SetVertexColor(0, 0, 0, 0)
    f.dispelBorder = f:CreateTexture(nil, "OVERLAY")
    f.dispelBorder:Hide()
    f.stealableMarker = f:CreateTexture(nil, "OVERLAY")
    f.stealableMarker:Hide()
    f.stack = MakeFS(f, "OVERLAY", Layers.AURA_STACK_DRAW_SUBLEVEL or 6)
    f.timer = MakeFS(f, "OVERLAY", Layers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
    f:Hide()
    return f
end

local function ApplyIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = ClampNumber(zoom, 100, 100, 200)
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function ForwardHandleScript(handle, scriptName, ...)
    if not (handle and handle.GetScript) then return end
    local script = handle:GetScript(scriptName)
    if type(script) == "function" then return script(handle, ...) end
end

local function BindDragProxy(frame, handle)
    if not (frame and handle) then return end
    if frame.EnableMouse then frame:EnableMouse(true) end
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    if frame.SetPropagateMouseWheel then frame:SetPropagateMouseWheel(false) end
    frame:SetScript("OnMouseWheel", function(_, delta) ForwardHandleScript(handle, "OnMouseWheel", delta) end)
    if frame.RegisterForClicks then
        frame:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
        frame:SetScript("OnClick", function(_, button) ForwardHandleScript(handle, "OnClick", button) end)
    end
    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    frame:SetScript("OnMouseDown", function(_, button) ForwardHandleScript(handle, "OnMouseDown", button) end)
    frame:SetScript("OnMouseUp", function(_, button) ForwardHandleScript(handle, "OnMouseUp", button) end)
    frame:SetScript("OnDragStart", function(_, button) ForwardHandleScript(handle, "OnDragStart", button) end)
    frame:SetScript("OnDragStop", function(_, button) ForwardHandleScript(handle, "OnDragStop", button) end)
    frame:SetScript("OnEnter", function() ForwardHandleScript(handle, "OnEnter") end)
    frame:SetScript("OnLeave", function() ForwardHandleScript(handle, "OnLeave") end)
end

local function EnsureIcon(visual, index)
    visual._icons = visual._icons or {}
    local icon = visual._icons[index]
    if not icon then
        icon = CreateIcon(visual)
        visual._icons[index] = icon
    end
    return icon
end
local function HideHandle(handle)
    if not handle then return end
    handle:Hide()
    for i = 1, #(handle._msufAuraPreviewIcons or {}) do
        handle._msufAuraPreviewIcons[i]:Hide()
    end
end
local function HideVisual(visual)
    if not visual then return end
    visual:Hide()
    for i = 1, #(visual._icons or {}) do
        visual._icons[i]:Hide()
    end
end

local function HideFrameEffectPreview(box)
    local owner = box and box._msufAuraFrameEffectPreviewOwner
    if not owner then return end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local runtime = a3 and a3.SpellIndicators
    if runtime and type(runtime.HidePreviewFrameEffect) == "function" then
        runtime.HidePreviewFrameEffect(owner)
    else
        owner:Hide()
    end
end

local function LayoutFrameEffectPreview(box, mock, effect, S)
    if not (box and mock and type(effect) == "table" and type(S) == "function") then
        HideFrameEffectPreview(box)
        return
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local runtime = a3 and a3.SpellIndicators
    if not (runtime and type(runtime.ApplyPreviewFrameEffect) == "function") then
        HideFrameEffectPreview(box)
        return
    end
    local owner = box._msufAuraFrameEffectPreviewOwner
    if not owner then
        owner = CreateFrame("Frame", nil, mock)
        owner:EnableMouse(false)
        box._msufAuraFrameEffectPreviewOwner = owner
    elseif owner.GetParent and owner:GetParent() ~= mock and owner.SetParent then
        owner:SetParent(mock)
    end
    owner:ClearAllPoints()
    owner:SetAllPoints(mock)
    owner:Show()

    -- The UnitFrame preview scales geometry into its canvas instead of scaling
    -- the frame tree.  Scale only the pixel thickness here; the live renderer
    -- then consumes every remaining value exactly as it does in game.
    local previewEffect = box._msufAuraFrameEffectPreviewConfig or {}
    box._msufAuraFrameEffectPreviewConfig = previewEffect
    previewEffect.type = effect.type
    previewEffect.color = effect.color
    previewEffect.priority = effect.priority
    previewEffect.thickness = max(1, S(effect.thickness or 2))
    previewEffect.layer = effect.layer
    previewEffect.strata = effect.strata
    previewEffect.tintAlpha = effect.tintAlpha
    if not runtime.ApplyPreviewFrameEffect(owner, previewEffect, mock) then
        HideFrameEffectPreview(box)
    end
end

function Auras.Hide(box)
    if not box then return end
    box._msufAuraFrameEffectPreviewLayer = nil
    if box.handleAuraCustom4 then
        box.handleAuraCustom4._msufAuraPortraitVisual = nil
    end
    HideHandle(box.handleAuraBuffs)
    HideHandle(box.handleAuraDebuffs)
    for index = 1, 4 do HideHandle(box["handleAuraCustom" .. tostring(index)]) end
    if box.auraPreviewVisuals then
        for _, kind in ipairs(AURA_PREVIEW_KINDS) do HideVisual(box.auraPreviewVisuals[kind]) end
    end
    HideVisual(box.defensivePortraitPreview)
    HideFrameEffectPreview(box)
end
function Auras.ApplyLayerVisibility(box)
    if not box then return end
    local visible, available = box.layerVisibility or {}, box.layerAvailable or {}
    if visible.buff == false or available.buff == false then
        HideHandle(box.handleAuraBuffs)
        HideVisual(box.auraPreviewVisuals and box.auraPreviewVisuals.buff)
    end
    if visible.debuff == false or available.debuff == false then
        HideHandle(box.handleAuraDebuffs)
        HideVisual(box.auraPreviewVisuals and box.auraPreviewVisuals.debuff)
    end
    if visible.auras == false or available.auras == false then
        if box.handleAuraCustom4 then box.handleAuraCustom4._msufAuraPortraitVisual = nil end
        for index = 1, 4 do
            HideHandle(box["handleAuraCustom" .. tostring(index)])
            HideVisual(box.auraPreviewVisuals and box.auraPreviewVisuals["custom" .. tostring(index)])
        end
        HideVisual(box.defensivePortraitPreview)
    end
    local effectLayer = box._msufAuraFrameEffectPreviewLayer
    if effectLayer and (visible[effectLayer] == false or available[effectLayer] == false) then
        HideFrameEffectPreview(box)
    end
end
local function ValueOr(value, fallback)
    if value ~= nil then return value end
    return fallback
end
local function LaneTextConfig(cfg, kind)
    if kind == "buff" then
        return {
            showStackCount = cfg.buffShowStackCount,
            showCooldownText = cfg.buffShowCooldownText,
            showCooldownSwipe = cfg.buffShowCooldownSwipe,
            cooldownSwipeReverse = cfg.buffCooldownSwipeReverse,
            stackAnchor = NormalizeAnchor(cfg.buffStackAnchor or cfg.stackAnchor, "TOPRIGHT"),
            stackSize = cfg.buffStackSize or cfg.stackSize,
            stackX = cfg.buffStackX or cfg.stackX,
            stackY = cfg.buffStackY or cfg.stackY,
            cooldownAnchor = NormalizeAnchor(cfg.buffCooldownAnchor or cfg.cooldownAnchor, "CENTER"),
            cooldownSize = cfg.buffCooldownSize or cfg.cooldownSize,
            cooldownX = cfg.buffCooldownX or cfg.cooldownX,
            cooldownY = cfg.buffCooldownY or cfg.cooldownY,
            showDurationBar = ValueOr(cfg.buffShowDurationBar, cfg.showDurationBar),
            durationBarHeight = ValueOr(cfg.buffDurationBarHeight, cfg.durationBarHeight),
            durationBarDisplay = ValueOr(cfg.buffDurationBarDisplay, cfg.durationBarDisplay) or "BAR_ONLY",
            durationBarPosition = ValueOr(cfg.buffDurationBarPosition, cfg.durationBarPosition) or "BOTTOM",
            durationBarDirection = ValueOr(cfg.buffDurationBarDirection, cfg.durationBarDirection) or "REMAINING",
            cooldownDecimalSeconds = ValueOr(cfg.buffCooldownDecimalSeconds, cfg.cooldownDecimalSeconds),
        }
    end
    return {
        showStackCount = cfg.debuffShowStackCount,
        showCooldownText = cfg.debuffShowCooldownText,
        showCooldownSwipe = cfg.debuffShowCooldownSwipe,
        cooldownSwipeReverse = cfg.debuffCooldownSwipeReverse,
        stackAnchor = NormalizeAnchor(cfg.debuffStackAnchor or cfg.stackAnchor, "TOPRIGHT"),
        stackSize = cfg.debuffStackSize or cfg.stackSize,
        stackX = cfg.debuffStackX or cfg.stackX,
        stackY = cfg.debuffStackY or cfg.stackY,
        cooldownAnchor = NormalizeAnchor(cfg.debuffCooldownAnchor or cfg.cooldownAnchor, "CENTER"),
        cooldownSize = cfg.debuffCooldownSize or cfg.cooldownSize,
        cooldownX = cfg.debuffCooldownX or cfg.cooldownX,
        cooldownY = cfg.debuffCooldownY or cfg.cooldownY,
        showDurationBar = ValueOr(cfg.debuffShowDurationBar, cfg.showDurationBar),
        durationBarHeight = ValueOr(cfg.debuffDurationBarHeight, cfg.durationBarHeight),
        durationBarDisplay = ValueOr(cfg.debuffDurationBarDisplay, cfg.durationBarDisplay) or "BAR_ONLY",
        durationBarPosition = ValueOr(cfg.debuffDurationBarPosition, cfg.durationBarPosition) or "BOTTOM",
        durationBarDirection = ValueOr(cfg.debuffDurationBarDirection, cfg.durationBarDirection) or "REMAINING",
        cooldownDecimalSeconds = ValueOr(cfg.debuffCooldownDecimalSeconds, cfg.cooldownDecimalSeconds),
    }
end

local function CustomTextConfig(bounds)
    local placed = bounds and bounds.stylePlaced
        or (bounds and bounds.item and bounds.item.placed) or {}
    return {
        showStackCount = placed.showStacks ~= false,
        showCooldownText = placed.showCooldown ~= false,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
        stackAnchor = NormalizeAnchor(placed.stackAnchor, "BOTTOMRIGHT"),
        stackSize = tonumber(placed.stackSize) or 14,
        stackX = tonumber(placed.stackX) or 0,
        stackY = tonumber(placed.stackY) or 0,
        cooldownSize = tonumber(placed.cooldownSize) or 14,
        cooldownAnchor = NormalizeAnchor(placed.cooldownAnchor, "CENTER"),
        cooldownX = tonumber(placed.cooldownX) or 0,
        cooldownY = tonumber(placed.cooldownY) or 0,
        showDurationBar = placed.showDurationBar == true,
        durationBarHeight = tonumber(placed.durationBarHeight) or 2,
        durationBarDisplay = placed.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
        durationBarPosition = placed.durationBarPosition == "TOP" and "TOP" or "BOTTOM",
        durationBarDirection = placed.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING",
        cooldownDecimalSeconds = tonumber(placed.cooldownDecimalSeconds) or 3,
    }
end

local function PreviewAuraState(box, kind, index, icon, cfg, targetDots)
    local options = {
        decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3,
    }
    local fn
    local elapsed
    if box and box._animationEnabled == true then
        local previewAnimation = MSUF and MSUF.PreviewAnimation
        fn = previewAnimation and previewAnimation.BuildAuraState
            or _G.MSUF_BuildPreviewAnimationAuraState
        elapsed = tonumber(box._animationElapsed) or 0
        if targetDots == true then
            -- A target DoT starts at full duration on every Animate press,
            -- enters the real 30% Pandemic window, then expires once instead
            -- of wrapping back to a fresh aura while the rest of the preview
            -- keeps animating.
            kind = "debuff"
            options.duration = 18
            options.oneShot = true
            options.pandemicThreshold = 0.30
        end
    else
        fn = _G.MSUF_GetPreviewAnimationAuraState
    end
    if type(fn) ~= "function" then return nil end
    icon._msufPreviewAuraScratch = icon._msufPreviewAuraScratch or {}
    if elapsed ~= nil then
        return fn(kind, index, icon._msufPreviewAuraScratch, options, elapsed)
    end
    return fn(kind, index, icon._msufPreviewAuraScratch, options)
end

local function LayoutPreviewAuraSwipe(swipe, icon, size, remainingFrac, reverse)
    if not (swipe and icon) then return end
    -- Avoid an effectively invisible one-pixel endpoint while keeping the
    -- shared dummy animation and configured direction obvious.
    remainingFrac = max(0.08, min(0.92, tonumber(remainingFrac) or 0.48))
    local iconWidth = icon.GetWidth and icon:GetWidth() or tonumber(size) or 1
    local iconHeight = icon.GetHeight and icon:GetHeight() or tonumber(size) or 1
    local w = max(1, floor(iconWidth * remainingFrac + 0.5))
    swipe:ClearAllPoints()
    swipe:SetWidth(w)
    swipe:SetHeight(max(1, iconHeight))
    if reverse == true then
        swipe:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    else
        swipe:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end
end

local function LayoutPreviewDurationBar(bar, icon, cfg, size, auraState)
    if not (bar and icon and cfg and cfg.showDurationBar == true) then
        if bar then bar:Hide() end
        return
    end
    local iconWidth = icon.GetWidth and icon:GetWidth() or tonumber(size) or 1
    local iconHeight = icon.GetHeight and icon:GetHeight() or tonumber(size) or 1
    local scaleSize = max(1, min(iconWidth, iconHeight))
    local height = max(1, min(iconHeight, floor((tonumber(cfg.durationBarHeight) or 2) + 0.5)))
    local inset = max(1, floor(scaleSize / 32 + 0.5))
    local avail = max(1, iconWidth - (inset * 2))
    local frac
    if cfg.durationBarDirection == "ELAPSED" then
        frac = auraState and auraState.elapsedFrac or 0.38
    else
        frac = auraState and auraState.remainingFrac or 0.62
    end
    local r, g, b = AuraDurationBarColor()
    bar:SetVertexColor(r, g, b, 0.92)
    frac = max(0.02, min(1, tonumber(frac) or 0.62))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if auraState then
        bar:SetWidth(max(1, floor(avail * frac + 0.5)))
        if cfg.durationBarPosition == "TOP" then
            bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        else
            bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        end
    elseif cfg.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
    end
    bar:Show()
end

--- Places a stack or cooldown text on a dummy icon. Anchor, scaled offsets and
--- justification are resolved once per lane, so this mirrors the live runtime's
--- placement without repeating its per-anchor branching for every icon.
local function PlaceAuraText(fs, icon, anchor, x, y)
    if not fs then return end
    local justify = AURA_TEXT_JUSTIFY[anchor]
    if not justify then
        anchor, justify = "CENTER", AURA_TEXT_JUSTIFY.CENTER
    end
    fs:ClearAllPoints()
    fs:SetPoint(anchor, icon, anchor, x, y)
    fs:SetJustifyH(justify[1])
    if fs.SetJustifyV then fs:SetJustifyV(justify[2]) end
end
local function PreviewDebuffBorderMode(cfg)
    local mode = cfg and cfg.debuffTypeBorderMode
    if mode == true then return "SYMBOL" end
    if mode == false then return "OFF" end
    mode = tostring(mode or ""):upper()
    if mode == "BORDER" or mode == "COLOR" or mode == "ON" then return "BORDER" end
    if mode == "SYMBOL" or mode == "BORDER_SYMBOL" or mode == "BORDER_SYMBOLS"
        or mode == "BORDER+SYMBOL" or mode == "ICON" or mode == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if cfg and cfg.useDebuffTypeBorders == true then return "SYMBOL" end
    return "OFF"
end
local function LayoutPreviewDispelBorder(icon, size, mode, shape, index)
    local atlas = DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[mode]
    local border = icon and icon.dispelBorder
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.ApplyAuraDispelPreview) == "function"
        and a3.ApplyAuraDispelPreview(border, icon, size, mode, shape,
            a3.PreviewDispelTypeForIndex(index)) then
        return
    end
    if not (atlas and border and border.SetAtlas) then
        if border then border:Hide() end
        return
    end
    local pad = a3 and type(a3.NativeAuraDispelBorderPadding) == "function"
        and a3.NativeAuraDispelBorderPadding(size)
        or max(1, floor((tonumber(size) or 24) / 6 + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    border:Show()
end
local function LayoutPreviewStealableMarker(icon, size, enabled, style, shape, index)
    local marker = icon and icon.stealableMarker
    if not (marker and enabled == true and index == 1) then
        if marker then marker:Hide() end
        return
    end
    style = tostring(style or "BORDER_ICON"):upper()
    marker:ClearAllPoints()
    if style == "ICON" then
        local markerSize = max(7, floor((tonumber(size) or 24) * 0.42 + 0.5))
        marker:SetSize(markerSize, markerSize)
        marker:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        if marker.SetAtlas then marker:SetAtlas("RaidFrame-Icon-DebuffMagic", TextureKitConstants and TextureKitConstants.IgnoreAtlasSize) end
        marker:SetVertexColor(1, 1, 1, 1)
        marker:Show()
        return
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local mode = style == "BORDER" and "BORDER" or "SYMBOL"
    if a3 and type(a3.ApplyAuraDispelPreview) == "function"
        and a3.ApplyAuraDispelPreview(marker, icon, size, mode, shape, "Magic", false) then
        return
    end
    marker:Hide()
end
local function LayoutHandle(box, handle, state, kind, S, baseLevel)
    local bounds = state and state[kind]
    if not (handle and bounds) then
        HideHandle(handle)
        if box and box.auraPreviewVisuals then HideVisual(box.auraPreviewVisuals[kind]) end
        return
    end
    local cfg = state.cfg
    local textCfg = bounds.custom and CustomTextConfig(bounds) or LaneTextConfig(cfg, kind)
    local visual = EnsureVisual(box, kind, baseLevel)
    if not visual then
        HideHandle(handle)
        return
    end
    BindDragProxy(visual, handle)
    local textureKind = bounds.auraType or kind
    local textures = AURA_TEXTURES[textureKind] or AURA_TEXTURES.buff
    local size = max(8, S(bounds.size))
    local step = S((bounds.size or 0) + (bounds.spacing or 0))
    local stackSize = max(7, S(textCfg.stackSize or 14))
    local cooldownSize = max(7, S(textCfg.cooldownSize or 14))
    -- Text state is lane-wide: anchors, scaled offsets, the resolved font and the
    -- show flags are identical for every sample icon, so they are resolved once
    -- here instead of once per icon inside the loop below.
    local stackAnchor, stackX, stackY = textCfg.stackAnchor or "TOPRIGHT", S(textCfg.stackX or -1), S(textCfg.stackY or 1)
    local cdAnchor, cdX, cdY = textCfg.cooldownAnchor or "CENTER", S(textCfg.cooldownX or 0), S(textCfg.cooldownY or 0)
    local stackFont = ResolveAuraFont(_stackFontState, stackSize)
    local timerFont = ResolveAuraFont(_timerFontState, cooldownSize)
    local showStacks = textCfg.showStackCount ~= false
    local showCooldown = textCfg.showCooldownText ~= false
    local showSwipe = textCfg.showCooldownSwipe ~= false
    local swipeReverse = textCfg.cooldownSwipeReverse == true
    local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
    local verticalGrowth = bounds.verticalGrowth == true
    local layer = tonumber(bounds.layer) or (kind == "buff" and 5 or 6)
    local debuffBorderMode = textureKind == "debuff" and (bounds.custom
        and PreviewDebuffBorderMode(bounds.stylePlaced or (bounds.item and bounds.item.placed))
        or PreviewDebuffBorderMode(cfg)) or "OFF"
    local padX, padY = PaddingInset(bounds.initialAnchor or "TOPLEFT", S(bounds.padding or 0))
    -- Bar-only lanes render no icon chrome at runtime, so the style stays off.
    local iconStyle = (not barOnly) and bounds.iconStyle or nil
    local a3 = MSUF and MSUF.MSUF_Auras3
    local applyIconStyle = a3 and a3.ApplyIconStylePreview
    local laneX = S(bounds.laneLeft or ((bounds.baseX or 0) + (bounds.x or 0)))
    local laneY = S(bounds.laneBottom or ((bounds.baseY or 0) + (bounds.y or 0)))
    local handleLeft = S(bounds.left or bounds.laneLeft or 0)
    local handleBottom = S(bounds.bottom or bounds.laneBottom or 0)
    local rawHandleW = bounds.left and bounds.right and (bounds.right - bounds.left) or bounds.laneW or 1
    local rawHandleH = bounds.bottom and bounds.top and (bounds.top - bounds.bottom) or bounds.laneH or 1
    local handleW = max(1, S(rawHandleW))
    local handleH = max(1, S(rawHandleH))
    visual:SetSize(max(1, S(bounds.laneW)), max(1, S(bounds.laneH)))
    visual:ClearAllPoints()
    visual:SetPoint("BOTTOMLEFT", box.mock, "BOTTOMLEFT", laneX, laneY)
    if visual.SetAlpha then visual:SetAlpha(ClampNumber(bounds.alpha, 1, 0, 1)) end
    if visual.SetFrameLevel then visual:SetFrameLevel(Layers.ElementLevel and Layers.ElementLevel(layer, 5, 0) or ((baseLevel or 0) + layer)) end
    visual:Show()
    if handle.SetFrameLevel then handle:SetFrameLevel(Layers.ElementLevel and (Layers.ElementLevel(30, 30, 31) + 32) or ((baseLevel or 0) + max(50, layer + 45))) end
    if handle._selBorder and handle._selBorder.SetFrameLevel then handle._selBorder:SetFrameLevel((handle:GetFrameLevel() or 0) + 5) end
    PlaceMinimumHitHandle(handle, box.mock, handleLeft, handleBottom, handleW, handleH, 4, 18)
    for i = 1, bounds.shown do
        local icon = EnsureIcon(visual, i)
        BindDragProxy(icon, handle)
        if icon.SetFrameLevel then icon:SetFrameLevel((visual:GetFrameLevel() or 0) + 1) end
        local targetDots = bounds.item and bounds.item.targetDots == true
        local auraState = PreviewAuraState(box, kind, i, icon, textCfg, targetDots)
        local col, row = IconGridCoord(i, bounds.perRow, verticalGrowth)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint(bounds.initialAnchor or "TOPLEFT", visual, bounds.initialAnchor or "TOPLEFT", col * step * bounds.growthX + padX, row * step * bounds.growthY + padY)
        local previewTexture = bounds.previewTextures and bounds.previewTextures[i]
        icon.tex:SetTexture(previewTexture or textures[((i - 1) % #textures) + 1])
        ApplyIconZoom(icon.tex, bounds.iconZoom)
        if a3 and type(a3.ApplyAuraIconShape) == "function" then
            a3.ApplyAuraIconShape(icon, bounds.iconShape, nil, icon.bg, icon.tex, icon.swipe)
        end
        if icon.bg then icon.bg:SetShown(not barOnly) end
        icon.tex:SetShown(not barOnly)
        icon.edge:SetVertexColor(0, 0, 0, 0)
        if type(applyIconStyle) == "function" then applyIconStyle(icon, iconStyle, size, bounds.iconShape) end
        if icon.swipe then
            if showSwipe and not barOnly then
                LayoutPreviewAuraSwipe(icon.swipe, icon, size, auraState and auraState.remainingFrac, swipeReverse)
                icon.swipe:Show()
            else
                icon.swipe:Hide()
            end
        end
        LayoutPreviewDurationBar(icon.durationBar, icon, textCfg, size, auraState)
        LayoutPreviewDispelBorder(icon, size, barOnly and "OFF" or debuffBorderMode, bounds.iconShape, i)
        LayoutPreviewStealableMarker(icon, size, kind == "buff" and cfg.buffShowStealable == true,
            cfg.buffStealableStyle, bounds.iconShape, i)
        if a3 and type(a3.ApplyPandemicVisual) == "function"
            and ((bounds.item and bounds.item.targetDots == true) or icon._msufA3PandemicRegion) then
            local placed = bounds.stylePlaced or (bounds.item and bounds.item.placed) or nil
            local pandemicVisible = auraState and auraState.pandemicActive
            if pandemicVisible == nil then pandemicVisible = true end
            a3.ApplyPandemicVisual(icon, placed or {}, placed and bounds.item.targetDots == true
                and placed.pandemicEnabled == true and i == 1 and not barOnly and pandemicVisible)
        end
        ApplyAuraFont(icon.stack, stackFont)
        PlaceAuraText(icon.stack, icon, stackAnchor, stackX, stackY)
        icon.stack:SetText(showStacks and (auraState and auraState.stacks or (i % 3 == 1 and "2" or "")) or "")
        ApplyAuraFont(icon.timer, timerFont)
        PlaceAuraText(icon.timer, icon, cdAnchor, cdX, cdY)
        icon.timer:SetText(showCooldown and (auraState and auraState.text or (i % 2 == 0 and "18" or "")) or "")
        icon:Show()
    end
    for i = bounds.shown + 1, #(visual._icons or {}) do
        local icon = visual._icons[i]
        if icon.swipe then icon.swipe:Hide() end
        if icon.durationBar then icon.durationBar:Hide() end
        if icon.dispelBorder then icon.dispelBorder:Hide() end
        if icon.stealableMarker then icon.stealableMarker:Hide() end
        icon:Hide()
    end
    handle:Show()
end

local function LayoutDefensivePortrait(box, mock, state, S)
    local handle = box and box.handleAuraCustom4
    if handle then
        handle._msufAuraPortraitVisual = nil
    end
    local bounds = state and (state.defensivePortrait or state.targetDotPortrait)
    if not (bounds and mock and mock.portrait and mock.portrait.IsShown and mock.portrait:IsShown()) then
        if box then HideVisual(box.defensivePortraitPreview) end
        return
    end
    local visual = box.defensivePortraitPreview
    if not visual then
        visual = CreateFrame("Frame", nil, mock.portrait)
        visual._icons = {}
        box.defensivePortraitPreview = visual
    end
    BindDragProxy(visual, handle)
    local textCfg = CustomTextConfig(bounds)
    textCfg.showCooldownText = bounds.showCooldownText == true
    textCfg.showStackCount = bounds.showStacks ~= false
    textCfg.showCooldownSwipe = bounds.showCooldownSwipe ~= false
    textCfg.cooldownSwipeReverse = bounds.cooldownSwipeReverse == true
    textCfg.showDurationBar = bounds.showDurationBar == true
    local size = max(8, S(bounds.size))
    local iconWidth = max(8, S(bounds.iconWidth or bounds.size))
    local iconHeight = max(8, S(bounds.iconHeight or bounds.size))
    local spacing = max(0, S(bounds.spacing or 0))
    local shown = max(1, tonumber(bounds.shown) or 1)
    local stepX = iconWidth + spacing
    local stepY = iconHeight + spacing
    local visualWidth = max(1, S(bounds.width or size))
    local visualHeight = max(1, S(bounds.height or size))
    visual:SetSize(visualWidth, visualHeight)
    visual:ClearAllPoints()
    local offsetX = S((bounds.x or 0) + (bounds.portraitInsetX or 0))
    local offsetY = S((bounds.y or 0) + (bounds.portraitInsetY or 0))
    local initialAnchor = bounds.initialAnchor or "TOPLEFT"
    visual:SetPoint(initialAnchor, mock.portrait, initialAnchor, offsetX, offsetY)
    if visual.SetAlpha then visual:SetAlpha(ClampNumber(bounds.alpha, 1, 0, 1)) end
    if visual.SetFrameLevel and mock.portrait.GetFrameLevel then
        visual:SetFrameLevel(Layers.ElementLevel and Layers.ElementLevel(bounds.layer, 5, 0)
            or ((mock.portrait:GetFrameLevel() or 1) + 1))
    end
    local stackSize = max(7, S(textCfg.stackSize or 14))
    local cooldownSize = max(7, S(textCfg.cooldownSize or 14))
    local stackAnchor = textCfg.stackAnchor or "BOTTOMRIGHT"
    local stackX, stackY = S(textCfg.stackX or 0), S(textCfg.stackY or 0)
    local cdAnchor = textCfg.cooldownAnchor or "CENTER"
    local cdX, cdY = S(textCfg.cooldownX or 0), S(textCfg.cooldownY or 0)
    local stackFont = ResolveAuraFont(_stackFontState, stackSize)
    local timerFont = ResolveAuraFont(_timerFontState, cooldownSize)
    local showStacks = textCfg.showStackCount ~= false
    local showCooldown = textCfg.showCooldownText ~= false
    local showSwipe = textCfg.showCooldownSwipe ~= false
    local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
    local a3 = MSUF and MSUF.MSUF_Auras3
    local applyIconStyle = a3 and a3.ApplyIconStylePreview
    local iconStyle = (not barOnly) and bounds.iconStyle or nil
    for i = 1, shown do
        local icon = EnsureIcon(visual, i)
        icon:SetSize(iconWidth, iconHeight)
        icon:ClearAllPoints()
        local col, row = IconGridCoord(i, bounds.perRow, bounds.verticalGrowth == true)
        icon:SetPoint(initialAnchor, visual, initialAnchor,
            col * stepX * bounds.growthX, row * stepY * bounds.growthY)
        if icon.SetFrameLevel then icon:SetFrameLevel((visual:GetFrameLevel() or 1) + 1) end
        icon.tex:SetTexture(bounds.previewTextures and bounds.previewTextures[i] or AURA_TEXTURES.buff[1])
        ApplyIconZoom(icon.tex, bounds.iconZoom)
        if a3 and type(a3.ApplyAuraIconShape) == "function" then
            a3.ApplyAuraIconShape(icon, bounds.iconShape, nil, icon.bg, icon.tex, icon.swipe)
        end
        icon.bg:SetShown(not barOnly)
        icon.tex:SetShown(not barOnly)
        icon.edge:SetVertexColor(0, 0, 0, 0)
        if type(applyIconStyle) == "function" then
            applyIconStyle(icon, iconStyle, size, bounds.iconShape)
        end
        if icon.dispelBorder then icon.dispelBorder:Hide() end
        if icon.stealableMarker then icon.stealableMarker:Hide() end
        local targetDots = bounds.item and bounds.item.targetDots == true
        local auraState = PreviewAuraState(box, "custom4", i, icon, textCfg, targetDots)
        if a3 and type(a3.ApplyPandemicVisual) == "function"
            and ((bounds.item and bounds.item.targetDots == true) or icon._msufA3PandemicRegion) then
            local placed = bounds.stylePlaced or (bounds.item and bounds.item.placed) or nil
            local pandemicVisible = auraState and auraState.pandemicActive
            if pandemicVisible == nil then pandemicVisible = true end
            a3.ApplyPandemicVisual(icon, placed or {}, placed and bounds.item.targetDots == true
                and placed.pandemicEnabled == true and i == 1 and not barOnly and pandemicVisible)
        end
        if icon.swipe then
            if showSwipe and not barOnly then
                LayoutPreviewAuraSwipe(icon.swipe, icon, size,
                    auraState and auraState.remainingFrac, textCfg.cooldownSwipeReverse == true)
                icon.swipe:Show()
            else
                icon.swipe:Hide()
            end
        end
        LayoutPreviewDurationBar(icon.durationBar, icon, textCfg, size, auraState)
        ApplyAuraFont(icon.stack, stackFont)
        PlaceAuraText(icon.stack, icon, stackAnchor, stackX, stackY)
        icon.stack:SetText(showStacks
            and (auraState and auraState.stacks or (i % 3 == 1 and "2" or "")) or "")
        ApplyAuraFont(icon.timer, timerFont)
        PlaceAuraText(icon.timer, icon, cdAnchor, cdX, cdY)
        icon.timer:SetText(showCooldown
            and (auraState and auraState.text or tostring(7 + i)) or "")
        icon:Show()
        BindDragProxy(icon, handle)
    end
    for i = shown + 1, #(visual._icons or {}) do
        local icon = visual._icons[i]
        if icon.swipe then icon.swipe:Hide() end
        if icon.durationBar then icon.durationBar:Hide() end
        if icon.dispelBorder then icon.dispelBorder:Hide() end
        if icon.stealableMarker then icon.stealableMarker:Hide() end
        icon:Hide()
    end
    visual:Show()
    if handle then
        handle._msufAuraPortraitVisual = visual
        if handle.SetFrameLevel then
            handle:SetFrameLevel((visual:GetFrameLevel() or 0) + 50)
        end
        if handle._selBorder and handle._selBorder.SetFrameLevel then
            handle._selBorder:SetFrameLevel((handle:GetFrameLevel() or 0) + 1)
        end
        handle:SetSize(max(18, visualWidth + 8), max(18, visualHeight + 8))
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", visual, "CENTER", 0, 0)
        handle._msufPlaced = true
        handle:Show()
    end
end

function Auras.Layout(box, mock, state, S, baseLevel)
    if not (box and mock and type(S) == "function") then return end
    -- The shared preview box builds its handles once and is then rebound
    -- across unit pages. Custom container 4 is the Defensive Buffs lane on the
    -- player frame but the Dots-on-target lane on target/focus/boss, so its
    -- label has to follow the currently bound unit, not the unit that first
    -- created the handles. Tooltip, selection bar and quick actions all read
    -- `_label` live.
    local custom4 = box.handleAuraCustom4
    if custom4 then
        local custom4Label = PreviewUnit(box) == "player" and "Defensive Buffs" or AURA_HANDLE_FIELDS.custom4.label
        if custom4._label ~= custom4Label then custom4._label = custom4Label end
    end
    if not state then
        Auras.Hide(box)
        return
    end
    LayoutHandle(box, box.handleAuraBuffs, state, "buff", S, baseLevel)
    LayoutHandle(box, box.handleAuraDebuffs, state, "debuff", S, baseLevel)
    for index = 1, 4 do
        local kind = "custom" .. tostring(index)
        if kind == "custom4" and (state.defensivePortrait or state.targetDotPortrait) then
            -- The portrait presentation reuses the custom4 mover. Hiding that
            -- shared handle here fires its OnHide path, which drops the active
            -- selection immediately before LayoutDefensivePortrait shows it
            -- again. Only retire the unused bar visual during this handoff.
            if box.auraPreviewVisuals then HideVisual(box.auraPreviewVisuals[kind]) end
        else
            LayoutHandle(box, box["handleAuraCustom" .. tostring(index)], state, kind, S, baseLevel)
        end
    end
    LayoutDefensivePortrait(box, mock, state, S)
    box._msufAuraFrameEffectPreviewLayer = state.previewFrameEffectLayer
    LayoutFrameEffectPreview(box, mock, state.previewFrameEffect, S)
end
