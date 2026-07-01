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
local Auras = MSUF.UFPreviewAuras or {}
MSUF.UFPreviewAuras = Auras
local AURA_HANDLE_FIELDS = {
    buff = { x = "buffGroupOffsetX", y = "buffGroupOffsetY", defaultX = 0, defaultY = 36, label = "Buffs", color = { 0.20, 0.74, 0.42 } },
    debuff = { x = "debuffGroupOffsetX", y = "debuffGroupOffsetY", defaultX = 0, defaultY = 6, label = "Debuffs", color = { 0.84, 0.26, 0.28 } },
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
local function NormalizeKind(kind)
    kind = tostring(kind or ""):lower()
    if kind == "buffs" then kind = "buff" end
    if kind == "debuffs" then kind = "debuff" end
    return AURA_HANDLE_FIELDS[kind] and kind or nil
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
local function RefreshRuntime(unit)
    unit = Auras.PreviewUnitKey(unit)
    if not unit then return false end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.BumpRuntimeConfig) == "function" then a3.BumpRuntimeConfig() end
    local function Refresh(runtime)
        if a3 and type(a3.RequestUnit) == "function" then
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
local function SyncPopup(unit)
    if type(_G.MSUF_SyncAuras3PositionPopup) == "function" then _G.MSUF_SyncAuras3PositionPopup(RuntimeUnit(unit)) end
end
function Auras.ReadOffsets(handle)
    local fields = handle and handle._fields
    local spec = fields and AURA_HANDLE_FIELDS[NormalizeKind(fields.auraPreviewKind)]
    local model = spec and MenuModel()
    local unit = PreviewUnit(handle and handle._preview)
    if not (spec and model and unit and type(model.ReadNumber) == "function") then return nil end
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
    if not (spec and model and unit and type(model.WriteNumber) == "function") then return false end
    model.WriteNumber(unit, spec.x, RoundOffset(x), -4096, 4096)
    model.WriteNumber(unit, spec.y, RoundOffset(y), -4096, 4096)
    if reason ~= "UNIT_PREVIEW_DRAG" then
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.BumpRuntimeConfig) == "function" then a3.BumpRuntimeConfig() end
        RefreshRuntime(unit)
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
    local dx = RoundOffset((x - prevX) * scale)
    local dy = RoundOffset((y - prevY) * scale)
    handle._msufAuraDragX = x
    handle._msufAuraDragY = y
    if dx == 0 and dy == 0 then return true end
    local moved = MoveFrameBy(handle, dx, dy)
    local visual = box.auraPreviewVisuals and box.auraPreviewVisuals[kind]
    MoveFrameBy(visual, dx, dy)
    return moved == true
end
function Auras.ClearDragOffsets(handle)
    if not handle then return end
    handle._msufAuraDragX = nil
    handle._msufAuraDragY = nil
end
function Auras.CommitOffsets(handle)
    local unit = PreviewUnit(handle and handle._preview)
    if not unit then return false end
    Auras.ClearDragOffsets(handle)
    RefreshRuntime(unit)
    SyncPopup(unit)
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
        vertical = true
        gx, gy = 1, 1
    elseif growth == "DOWN" then
        vertical = true
        gx, gy = 1, -1
    end
    return gx, gy, vertical, ButtonAnchor(gx, gy)
end
local function AnchorOffset(anchor, w, h)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPRIGHT" then return w, h end
    if anchor == "BOTTOMLEFT" then return 0, 0 end
    if anchor == "BOTTOMRIGHT" then return w, 0 end
    if anchor == "CENTER" then return w * 0.5, h * 0.5 end
    return 0, h
end
local function AnchorBase(anchor, frameW, frameH)
    return AnchorOffset(anchor, frameW, frameH)
end
local function GridShape(count, perRow, vertical)
    count = max(1, RoundOffset(count))
    perRow = max(1, RoundOffset(perRow))
    if vertical then return max(1, ceil(count / perRow)), min(count, perRow) end
    return min(count, perRow), max(1, ceil(count / perRow))
end
local function IconGridCoord(index, perRow, vertical)
    local per = max(1, RoundOffset(perRow))
    local idx = index - 1
    if vertical then
        local row = idx % per
        return (idx - row) / per, row
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
local function LaneBounds(cfg, kind, frameW, frameH)
    if not cfg then return nil end
    local isBuff = kind == "buff"
    if isBuff and cfg.showBuffs ~= true then return nil end
    if (not isBuff) and cfg.showDebuffs ~= true then return nil end
    local count = tonumber(isBuff and cfg.maxBuffs or cfg.maxDebuffs) or (isBuff and 8 or 12)
    if count <= 0 then return nil end
    local size = max(1, isBuff and cfg.buffSize or cfg.debuffSize)
    local x = isBuff and cfg.buffX or cfg.debuffX
    local y = isBuff and cfg.buffY or cfg.debuffY
    local anchor = isBuff and cfg.buffAnchor or cfg.debuffAnchor
    local spacing = max(0, cfg.spacing or 0)
    local perRow = max(1, (isBuff and cfg.buffPerRow or cfg.debuffPerRow) or cfg.perRow or 1)
    local shown = min(max(1, count), PREVIEW_ICONS)
    local step = size + spacing
    local growthX, growthY, vertical, initialAnchor = Growth(cfg, kind)
    local baseX, baseY = AnchorBase(anchor, frameW, frameH)
    local cols, rows = GridShape(count, perRow, vertical)
    local laneW = max(1, cols * size + max(cols - 1, 0) * spacing)
    local laneH = max(1, rows * size + max(rows - 1, 0) * spacing)
    local anchorLocalX, anchorLocalY = AnchorOffset(anchor, laneW, laneH)
    local laneLeft = baseX + x - anchorLocalX
    local laneBottom = baseY + y - anchorLocalY
    local iconMinX, iconMinY, iconMaxX, iconMaxY
    for i = 1, shown do
        local col, row = IconGridCoord(i, perRow, vertical)
        local l, b, r, t = IconRect(initialAnchor, laneW, laneH, size, col * step * growthX, row * step * growthY)
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
    }
end
function Auras.BuildState(key, frameW, frameH, runtimeSpec)
    local runtimeAuras = runtimeSpec and runtimeSpec.auras
    local model = MenuModel()
    key = Auras.PreviewUnitKey(key)
    if not (key and model and type(model.ReadPreviewConfig) == "function") then return nil end
    local cfg = model.ReadPreviewConfig(key)
    if not cfg then return nil end
    local buff = LaneBounds(cfg, "buff", frameW, frameH)
    local debuff = LaneBounds(cfg, "debuff", frameW, frameH)
    if not buff and not debuff then return nil end
    return { unit = key, cfg = cfg, runtime = runtimeAuras, buff = buff, debuff = debuff }
end
function Auras.ExpandFootprint(state, minX, maxX, minY, maxY)
    if not state then return minX, maxX, minY, maxY end
    for _, kind in ipairs({ "buff", "debuff" }) do
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
local function ApplyAuraFont(fs, size)
    if not fs then return end
    size = max(7, tonumber(size) or 14)
    local fontPath, fontFlags, r, g, b, _, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings() end
    fontPath = fontPath or FONT
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then
        local resolveSafe = _G.MSUF_ResolveSafeFontPath
        if type(resolveSafe) == "function" then
            local gdb = _G.MSUF_DB and _G.MSUF_DB.general
            fontPath = resolveSafe(fontPath, size, fontFlags, gdb and gdb.fontKey)
        end
        local ok = pcall(fs.SetFont, fs, fontPath, size, fontFlags)
        if not ok then
            pcall(fs.SetFont, fs, FONT, size, fontFlags)
        end
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0) end
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
    if visual.SetFrameLevel then visual:SetFrameLevel((baseLevel or 0) + (kind == "buff" and 29 or 30)) end
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
    f.durationBar:SetVertexColor(0.08, 0.78, 1.00, 0.92)
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
    if box.auraPreviewVisuals then
        HideVisual(box.auraPreviewVisuals.buff)
        HideVisual(box.auraPreviewVisuals.debuff)
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
            stackAnchor = cfg.buffStackAnchor or cfg.stackAnchor,
            stackSize = cfg.buffStackSize or cfg.stackSize,
            stackX = cfg.buffStackX or cfg.stackX,
            stackY = cfg.buffStackY or cfg.stackY,
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
        stackAnchor = cfg.debuffStackAnchor or cfg.stackAnchor,
        stackSize = cfg.debuffStackSize or cfg.stackSize,
        stackX = cfg.debuffStackX or cfg.stackX,
        stackY = cfg.debuffStackY or cfg.stackY,
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

local function PreviewAuraState(kind, index, icon, cfg)
    local fn = _G.MSUF_GetPreviewAnimationAuraState
    if type(fn) ~= "function" then return nil end
    icon._msufPreviewAuraScratch = icon._msufPreviewAuraScratch or {}
    return fn(kind, index, icon._msufPreviewAuraScratch, {
        decimalSeconds = cfg and cfg.cooldownDecimalSeconds == true,
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
        bar:SetVertexColor(0.22, 0.88, 0.50, 0.92)
    else
        frac = auraState and auraState.remainingFrac or 0.62
        bar:SetVertexColor(0.08, 0.78, 1.00, 0.92)
    end
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

local function PlaceStack(fs, icon, cfg, S)
    if not fs then return end
    local stackAnchor = cfg.stackAnchor or "TOPRIGHT"
    local stackX = S(cfg.stackX or -1)
    local stackY = S(cfg.stackY or 1)
    fs:ClearAllPoints()
    if stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", icon, "TOPLEFT", stackX, stackY)
        fs:SetJustifyH("LEFT")
        if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    elseif stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", stackX, stackY)
        fs:SetJustifyH("LEFT")
        if fs.SetJustifyV then fs:SetJustifyV("BOTTOM") end
    elseif stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", stackX, stackY)
        fs:SetJustifyH("RIGHT")
        if fs.SetJustifyV then fs:SetJustifyV("BOTTOM") end
    else
        fs:SetPoint("TOPRIGHT", icon, "TOPRIGHT", stackX, stackY)
        fs:SetJustifyH("RIGHT")
        if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    end
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
    local textCfg = LaneTextConfig(cfg, kind)
    local visual = EnsureVisual(box, kind, baseLevel)
    if not visual then
        HideHandle(handle)
        return
    end
    BindDragProxy(visual, handle)
    local textures = AURA_TEXTURES[kind] or AURA_TEXTURES.buff
    local size = max(8, S(bounds.size))
    local step = S((bounds.size or 0) + (bounds.spacing or 0))
    local stackSize = max(7, S(textCfg.stackSize or 14))
    local cooldownSize = max(7, S(textCfg.cooldownSize or 14))
    local cooldownX = S(textCfg.cooldownX or 0)
    local cooldownY = S(textCfg.cooldownY or 0)
    local layer = tonumber(bounds.layer) or (kind == "buff" and 5 or 6)
    local debuffBorderMode = kind == "debuff" and PreviewDebuffBorderMode(cfg) or "OFF"
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
        local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
        local col, row = IconGridCoord(i, bounds.perRow, bounds.verticalGrowth == true)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint(bounds.initialAnchor or "TOPLEFT", visual, bounds.initialAnchor or "TOPLEFT", col * step * bounds.growthX, row * step * bounds.growthY)
        icon.tex:SetTexture(textures[((i - 1) % #textures) + 1])
        if icon.bg then icon.bg:SetShown(not barOnly) end
        icon.tex:SetShown(not barOnly)
        icon.edge:SetVertexColor(0, 0, 0, 0)
        if icon.swipe then
            if textCfg.showCooldownSwipe ~= false and not barOnly then
                LayoutPreviewAuraSwipe(icon.swipe, icon, size, auraState and auraState.remainingFrac, textCfg.cooldownSwipeReverse == true)
                icon.swipe:Show()
            else
                icon.swipe:Hide()
            end
        end
        LayoutPreviewDurationBar(icon.durationBar, icon, textCfg, size, auraState)
        LayoutPreviewDispelBorder(icon, size, barOnly and "OFF" or debuffBorderMode)
        ApplyAuraFont(icon.stack, stackSize)
        PlaceStack(icon.stack, icon, textCfg, S)
        icon.stack:SetText(textCfg.showStackCount ~= false and (auraState and auraState.stacks or (i % 3 == 1 and "2" or "")) or "")
        ApplyAuraFont(icon.timer, cooldownSize)
        icon.timer:ClearAllPoints()
        icon.timer:SetPoint("CENTER", icon, "CENTER", cooldownX, cooldownY)
        icon.timer:SetJustifyH("CENTER")
        icon.timer:SetText(textCfg.showCooldownText ~= false and (auraState and auraState.text or (i % 2 == 0 and "18" or "")) or "")
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
end
