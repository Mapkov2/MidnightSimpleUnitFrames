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
local AURA_HANDLE_FIELDS = {
    buff = { x = "buffGroupOffsetX", y = "buffGroupOffsetY", defaultX = 0, defaultY = 36, label = "Buffs", color = { 0.20, 0.74, 0.42 } },
    debuff = { x = "debuffGroupOffsetX", y = "debuffGroupOffsetY", defaultX = 0, defaultY = 6, label = "Debuffs", color = { 0.84, 0.26, 0.28 } },
    custom1 = { customIndex = 1, defaultX = 0, defaultY = 0, label = "Custom 1", color = { 0.45, 0.72, 1.00 } },
    custom2 = { customIndex = 2, defaultX = 0, defaultY = 0, label = "Custom 2", color = { 0.70, 0.48, 1.00 } },
    custom3 = { customIndex = 3, defaultX = 0, defaultY = 0, label = "Custom 3", color = { 1.00, 0.58, 0.28 } },
    custom4 = { customIndex = 4, defaultX = 0, defaultY = 0, label = "Dots on target", color = { 0.88, 0.24, 0.42 } },
}
local AURA_PREVIEW_KINDS = { "buff", "debuff", "custom1", "custom2", "custom3", "custom4" }
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

local function CustomItem(model, unit, index, create)
    if not (model and type(model.CustomContainer) == "function") then return nil end
    return model.CustomContainer(unit, index, create == true)
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
    local kind = fields and NormalizeKind(fields.auraPreviewKind)
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
    local visual = box.auraPreviewVisuals and box.auraPreviewVisuals[kind]
    local moved = SetDragPoint(handle, "Handle", handle, dx, dy)
    if not moved and (dx ~= 0 or dy ~= 0) then moved = MoveFrameBy(handle, dx, dy) end
    if visual then
        if not SetDragPoint(handle, "Visual", visual, dx, dy) and (dx ~= 0 or dy ~= 0) then
            MoveFrameBy(visual, dx, dy)
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
            }, spec.label, spec.color)
        end
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
local function LaneIconStyle(metrics, unit)
    if metrics and metrics.iconStyle then return metrics.iconStyle end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.IconStylePreviewForScope) == "function" then
        return a3.IconStylePreviewForScope(unit)
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
local function LaneBounds(cfg, kind, frameW, frameH, unit)
    if not cfg then return nil end
    local isBuff = kind == "buff"
    if isBuff and cfg.showBuffs ~= true then return nil end
    if (not isBuff) and cfg.showDebuffs ~= true then return nil end
    local metrics = isBuff and cfg.buffMetrics or cfg.debuffMetrics
    if metrics and metrics.enabled ~= true then return nil end
    local count = metrics and metrics.num or (isBuff and cfg.maxBuffs or cfg.maxDebuffs)
    count = RuntimeRound(ClampNumber(count, isBuff and 8 or 12, 0, 80))
    if count <= 0 then return nil end
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
        iconStyle = LaneIconStyle(metrics, unit),
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

local function CustomLaneBounds(item, kind, frameW, frameH, metrics, previewEntries, unit, fallbackPadding)
    if type(item) ~= "table" then return nil end
    -- Any custom lane with configured spells previews them 1:1 with the real
    -- spell icons; only the dot container may show while disabled.
    local trackedPreview = type(previewEntries) == "table" and #previewEntries > 0
    if item.enabled ~= true and not (kind == "custom4" and trackedPreview) then return nil end
    local placed = type(item.placed) == "table" and item.placed or {}
    local count = metrics and metrics.num or RuntimeRound(ClampNumber(placed.max, 8, 0, 40))
    if trackedPreview then count = min(count, #previewEntries) end
    if count <= 0 then return nil end
    local size = ClampNumber(metrics and metrics.size or placed.size, 24, 1, 128)
    local spacing = ClampNumber(metrics and metrics.spacing or placed.spacing, 2, 0, 64)
    local perRow = metrics and metrics.perRow or RuntimeRound(ClampNumber(placed.perRow, 4, 1, 40))
    local shown = min(max(1, count), trackedPreview and count or PREVIEW_ICONS)
    local anchor = NormalizeAnchor(metrics and metrics.anchor or placed.anchor, "TOPRIGHT")
    local x = metrics and metrics.x or RuntimeRound(ClampNumber(placed.x, 0, -4096, 4096))
    local y = metrics and metrics.y or RuntimeRound(ClampNumber(placed.y, 0, -4096, 4096))
    local growthX, growthY, vertical, initialAnchor
    if metrics then
        growthX = tonumber(metrics.growthX) or -1
        growthY = tonumber(metrics.growthY) or -1
        vertical = metrics.verticalGrowth == true
        initialAnchor = metrics.initialAnchor or ButtonAnchor(growthX, growthY)
    else
        growthX, growthY, vertical = CustomGrowth(placed.growth)
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
        auraType = item.auraType == "DEBUFF" and "debuff" or "buff",
        previewTextures = previewTextures,
        padding = padding,
        iconStyle = LaneIconStyle(metrics, unit),
    }
end

function Auras.BuildState(key, frameW, frameH, runtimeSpec)
    local runtimeAuras = runtimeSpec and runtimeSpec.auras
    local model = MenuModel()
    key = Auras.PreviewUnitKey(key)
    if not (key and model and type(model.ReadPreviewConfig) == "function") then return nil end
    local cfg = model.ReadPreviewConfig(key)
    if not cfg then return nil end
    local buff = LaneBounds(cfg, "buff", frameW, frameH, key)
    local debuff = LaneBounds(cfg, "debuff", frameW, frameH, key)
    local state = { unit = key, cfg = cfg, runtime = runtimeAuras, buff = buff, debuff = debuff }
    for index = 1, 4 do
        local kind = "custom" .. tostring(index)
        local metrics = type(cfg.customMetrics) == "table" and cfg.customMetrics[index] or nil
        local previewEntries
        if type(model.CustomContainerPreviewEntries) == "function" then
            previewEntries = model.CustomContainerPreviewEntries(key, index)
        elseif type(model.CustomContainerSpellEntries) == "function" then
            previewEntries = model.CustomContainerSpellEntries(key, index)
        end
        state[kind] = CustomLaneBounds(CustomItem(model, key, index, false), kind, frameW, frameH, metrics, previewEntries, key, cfg.stylePadding)
    end
    if not state.buff and not state.debuff and not state.custom1 and not state.custom2 and not state.custom3 and not state.custom4 then return nil end
    return state
end
function Auras.ExpandFootprint(state, minX, maxX, minY, maxY)
    if not state then return minX, maxX, minY, maxY end
    for _, kind in ipairs(AURA_PREVIEW_KINDS) do
        local b = state[kind]
        if b then
            minX = min(minX, b.left)
            maxX = max(maxX, b.right)
            minY = min(minY, b.bottom)
            maxY = max(maxY, b.top)
        end
    end
    return minX, maxX, minY, maxY
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
    if visual.SetFrameLevel then visual:SetFrameLevel((baseLevel or 0) + level) end
    return visual
end
local function CreateIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(TEX_W8)
    f.bg:SetVertexColor(0.07, 0.07, 0.08, 0.88)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    if f.tex.SetTexCoord then f.tex:SetTexCoord(0, 1, 0, 1) end
    f.swipe = f:CreateTexture(nil, "ARTWORK")
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, 0)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.28)
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
    f.stack = MakeFS(f, "OVERLAY", 8)
    f.timer = MakeFS(f, "OVERLAY", 7)
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
function Auras.Hide(box)
    if not box then return end
    HideHandle(box.handleAuraBuffs)
    HideHandle(box.handleAuraDebuffs)
    for index = 1, 4 do HideHandle(box["handleAuraCustom" .. tostring(index)]) end
    if box.auraPreviewVisuals then
        for _, kind in ipairs(AURA_PREVIEW_KINDS) do HideVisual(box.auraPreviewVisuals[kind]) end
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
    local placed = bounds and bounds.item and bounds.item.placed or {}
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

local function PreviewAuraState(kind, index, icon, cfg)
    local fn = _G.MSUF_GetPreviewAnimationAuraState
    if type(fn) ~= "function" then return nil end
    icon._msufPreviewAuraScratch = icon._msufPreviewAuraScratch or {}
    return fn(kind, index, icon._msufPreviewAuraScratch, {
        decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3,
    })
end

local function LayoutPreviewAuraSwipe(swipe, icon, size, remainingFrac, reverse)
    if not (swipe and icon) then return end
    remainingFrac = max(0.02, min(1, tonumber(remainingFrac) or 0.48))
    local w = max(1, floor((tonumber(size) or icon:GetWidth() or 1) * remainingFrac + 0.5))
    swipe:ClearAllPoints()
    swipe:SetWidth(w)
    swipe:SetHeight(max(1, tonumber(size) or 1))
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
    size = max(1, tonumber(size) or 1)
    local height = max(1, min(size, floor((tonumber(cfg.durationBarHeight) or 2) + 0.5)))
    local inset = max(1, floor(size / 32 + 0.5))
    local avail = max(1, size - (inset * 2))
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
local function LayoutPreviewDispelBorder(icon, size, mode)
    local atlas = DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[mode]
    local border = icon and icon.dispelBorder
    if not (atlas and border and border.SetAtlas) then
        if border then border:Hide() end
        return
    end
    local pad = max(1, floor((tonumber(size) or 24) / 24 + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    border:Show()
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
    local debuffBorderMode = textureKind == "debuff" and (bounds.custom and PreviewDebuffBorderMode(bounds.item and bounds.item.placed) or PreviewDebuffBorderMode(cfg)) or "OFF"
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
    if visual.SetFrameLevel then visual:SetFrameLevel((baseLevel or 0) + layer) end
    visual:Show()
    if handle.SetFrameLevel then handle:SetFrameLevel((baseLevel or 0) + max(50, layer + 45)) end
    if handle._selBorder and handle._selBorder.SetFrameLevel then handle._selBorder:SetFrameLevel((handle:GetFrameLevel() or 0) + 5) end
    handle:SetSize(max(18, handleW + 8), max(18, handleH + 8))
    handle:ClearAllPoints()
    handle:SetPoint("BOTTOMLEFT", box.mock, "BOTTOMLEFT", handleLeft - 4, handleBottom - 4)
    for i = 1, bounds.shown do
        local icon = EnsureIcon(visual, i)
        BindDragProxy(icon, handle)
        if icon.SetFrameLevel then icon:SetFrameLevel((visual:GetFrameLevel() or 0) + 1) end
        local auraState = PreviewAuraState(kind, i, icon, textCfg)
        local col, row = IconGridCoord(i, bounds.perRow, verticalGrowth)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint(bounds.initialAnchor or "TOPLEFT", visual, bounds.initialAnchor or "TOPLEFT", col * step * bounds.growthX + padX, row * step * bounds.growthY + padY)
        local previewTexture = bounds.previewTextures and bounds.previewTextures[i]
        icon.tex:SetTexture(previewTexture or textures[((i - 1) % #textures) + 1])
        ApplyIconZoom(icon.tex, bounds.iconZoom)
        if icon.bg then icon.bg:SetShown(not barOnly) end
        icon.tex:SetShown(not barOnly)
        icon.edge:SetVertexColor(0, 0, 0, 0)
        if type(applyIconStyle) == "function" then applyIconStyle(icon, iconStyle, size) end
        if icon.swipe then
            if showSwipe and not barOnly then
                LayoutPreviewAuraSwipe(icon.swipe, icon, size, auraState and auraState.remainingFrac, swipeReverse)
                icon.swipe:Show()
            else
                icon.swipe:Hide()
            end
        end
        LayoutPreviewDurationBar(icon.durationBar, icon, textCfg, size, auraState)
        LayoutPreviewDispelBorder(icon, size, barOnly and "OFF" or debuffBorderMode)
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
        icon:Hide()
    end
    handle:Show()
end
function Auras.Layout(box, mock, state, S, baseLevel)
    if not (box and mock and type(S) == "function") then return end
    if not state then
        Auras.Hide(box)
        return
    end
    LayoutHandle(box, box.handleAuraBuffs, state, "buff", S, baseLevel)
    LayoutHandle(box, box.handleAuraDebuffs, state, "debuff", S, baseLevel)
    for index = 1, 4 do
        local kind = "custom" .. tostring(index)
        LayoutHandle(box, box["handleAuraCustom" .. tostring(index)], state, kind, S, baseLevel)
    end
end
