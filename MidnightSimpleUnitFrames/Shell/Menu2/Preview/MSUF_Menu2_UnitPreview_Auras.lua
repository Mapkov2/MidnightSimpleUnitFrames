--- Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua
--- Cold-path buff/debuff preview provider for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local floor, max, min = math.floor, math.max, math.min
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

local function MenuModel()
    local a3 = (MSUF and MSUF.MSUF_Auras3) or _G.MSUF_Auras3
    return type(a3) == "table" and a3.MenuModel or _G.MSUF_Auras3_MenuModel
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
    if not key and box._msufPanel and (box._msufPanel._msufGetCurrentKey or box._msufPanel._msufLastApplyKey ~= nil) then
        key = CurrentPanelKey(box._msufPanel)
    end
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
    local a3 = (MSUF and MSUF.MSUF_Auras3) or _G.MSUF_Auras3
    if a3 and type(a3.BumpRuntimeConfig) == "function" then pcall(a3.BumpRuntimeConfig) end
    local function Refresh(runtime)
        if a3 and type(a3.RequestUnit) == "function" then
            pcall(a3.RequestUnit, runtime, 0)
        else
            if type(_G.MSUF_Auras3_UpdateUnitAnchor) == "function" then pcall(_G.MSUF_Auras3_UpdateUnitAnchor, runtime) end
            if type(_G.MSUF_Auras3_RefreshUnit) == "function" then pcall(_G.MSUF_Auras3_RefreshUnit, runtime) end
            if type(_G.MSUF_Auras3_RefreshEditPreview) == "function" then pcall(_G.MSUF_Auras3_RefreshEditPreview, runtime) end
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
    if type(_G.MSUF_SyncAuras3PositionPopup) == "function" then
        pcall(_G.MSUF_SyncAuras3PositionPopup, RuntimeUnit(unit))
    end
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
    local a3 = (MSUF and MSUF.MSUF_Auras3) or _G.MSUF_Auras3
    if a3 and type(a3.BumpRuntimeConfig) == "function" then
        pcall(a3.BumpRuntimeConfig)
    end
    if reason ~= "UNIT_PREVIEW_DRAG" then
        RefreshRuntime(unit)
        SyncPopup(unit)
    end
    return true
end

function Auras.CommitOffsets(handle)
    local unit = PreviewUnit(handle and handle._preview)
    if not unit then return false end
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
            commitOffsets = Auras.CommitOffsets,
            section = "auras3",
        }, spec.label, spec.color)
    end
end

local function Growth(cfg, kind)
    local isBuff = kind == "buff"
    local growth = isBuff and (cfg.buffGrowthX or cfg.growth) or (cfg.debuffGrowthX or cfg.growth)
    local rowWrap = isBuff and (cfg.buffGrowthY or cfg.rowWrap) or (cfg.debuffGrowthY or cfg.rowWrap)
    local gx = growth == "LEFT" and -1 or 1
    local gy = rowWrap == "UP" and 1 or -1
    if growth == "UP" then
        gx, gy = 1, 1
    elseif growth == "DOWN" then
        gx, gy = 1, -1
    end
    return gx, gy
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
    local spacing = max(0, cfg.spacing or 0)
    local perRow = max(1, (isBuff and cfg.buffPerRow or cfg.debuffPerRow) or cfg.perRow or 1)
    local shown = min(max(1, count), PREVIEW_ICONS)
    local cols = min(shown, perRow)
    local rows = max(1, floor((shown + perRow - 1) / perRow))
    local step = size + spacing
    local growthX, growthY = Growth(cfg, kind)
    local laneRows = max(1, floor((count + perRow - 1) / perRow))
    local laneW = perRow * size + (perRow - 1) * spacing
    local laneH = laneRows * size + (laneRows - 1) * spacing
    local anchorBottom = frameH + y
    local iconMinX = growthX < 0 and -((cols - 1) * step) or 0
    local iconMaxX = growthX < 0 and size or ((cols - 1) * step + size)
    local iconMinY = growthY < 0 and -((rows - 1) * step) or 0
    local iconMaxY = growthY < 0 and size or ((rows - 1) * step + size)
    local left = x + min(0, iconMinX)
    local right = x + max(laneW, iconMaxX)
    local bottom = anchorBottom + min(0, iconMinY)
    local top = anchorBottom + max(laneH, iconMaxY)
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
        iconMinX = iconMinX,
        iconMaxX = iconMaxX,
        iconMinY = iconMinY,
        iconMaxY = iconMaxY,
        anchorBottom = anchorBottom,
        growthX = growthX,
        growthY = growthY,
        point = "BOTTOMLEFT",
        relativePoint = "TOPLEFT",
        initialAnchor = "BOTTOMLEFT",
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
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings()
    end
    fontPath = fontPath or FONT
    fontFlags = fontFlags or "OUTLINE"
    local fontKey = (_G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.fontKey) or "FRIZQT"
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(fs, fontPath, size, fontFlags, fontKey)
    elseif fs.SetFont then
        fs:SetFont(fontPath, size, fontFlags)
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
        visual:EnableMouse(false)
        visual._msufAuraVisualKind = kind
        visual._icons = {}
        box.auraPreviewVisuals[kind] = visual
    end
    if visual.SetFrameLevel then visual:SetFrameLevel((baseLevel or 0) + (kind == "buff" and 29 or 30)) end
    return visual
end

local function CreateIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    f:SetSize(18, 18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(TEX_W8)
    f.bg:SetVertexColor(0.07, 0.07, 0.08, 0.88)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    if f.tex.SetTexCoord then f.tex:SetTexCoord(0, 1, 0, 1) end
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetAllPoints(f)
    f.edge:SetTexture(TEX_W8)
    f.edge:SetVertexColor(0, 0, 0, 0)
    f.stack = MakeFS(f, "OVERLAY", 8)
    f.timer = MakeFS(f, "OVERLAY", 7)
    f:Hide()
    return f
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

local function LayoutHandle(box, handle, state, kind, S, baseLevel)
    local bounds = state and state[kind]
    if not (handle and bounds) then
        HideHandle(handle)
        if box and box.auraPreviewVisuals then HideVisual(box.auraPreviewVisuals[kind]) end
        return
    end
    local cfg = state.cfg
    local visual = EnsureVisual(box, kind, baseLevel)
    if not visual then
        HideHandle(handle)
        return
    end
    local textures = AURA_TEXTURES[kind] or AURA_TEXTURES.buff
    local size = max(8, S(bounds.size))
    local step = S((bounds.size or 0) + (bounds.spacing or 0))
    local stackSize = max(7, S(cfg.stackSize or 14))
    local cooldownSize = max(7, S(cfg.cooldownSize or 14))
    local cooldownX = S(cfg.cooldownX or 0)
    local cooldownY = S(cfg.cooldownY or 0)
    local laneX = S(bounds.x)
    local laneY = S(bounds.y)
    local handleLeft = S((bounds.x or 0) + (bounds.iconMinX or 0))
    local handleBottom = S((bounds.y or 0) + (bounds.iconMinY or 0))
    local handleW = max(1, S((bounds.iconMaxX or 0) - (bounds.iconMinX or 0)))
    local handleH = max(1, S((bounds.iconMaxY or 0) - (bounds.iconMinY or 0)))

    visual:SetSize(max(1, S(bounds.laneW)), max(1, S(bounds.laneH)))
    visual:ClearAllPoints()
    visual:SetPoint("BOTTOMLEFT", box.mock, "TOPLEFT", laneX, laneY)
    visual:Show()

    if handle.SetFrameLevel then handle:SetFrameLevel((baseLevel or 0) + (kind == "buff" and 50 or 51)) end
    if handle._selBorder and handle._selBorder.SetFrameLevel then handle._selBorder:SetFrameLevel((handle:GetFrameLevel() or 0) + 5) end
    handle:SetSize(max(18, handleW + 8), max(18, handleH + 8))
    handle:ClearAllPoints()
    handle:SetPoint("BOTTOMLEFT", box.mock, "TOPLEFT", handleLeft - 4, handleBottom - 4)

    for i = 1, bounds.shown do
        local icon = EnsureIcon(visual, i)
        if icon.SetFrameLevel then icon:SetFrameLevel((visual:GetFrameLevel() or 0) + 1) end
        local col = (i - 1) % bounds.perRow
        local row = floor((i - 1) / bounds.perRow)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", visual, "BOTTOMLEFT", col * step * bounds.growthX, row * step * bounds.growthY)
        icon.tex:SetTexture(textures[((i - 1) % #textures) + 1])
        icon.edge:SetVertexColor(0, 0, 0, 0)
        ApplyAuraFont(icon.stack, stackSize)
        PlaceStack(icon.stack, icon, cfg, S)
        icon.stack:SetText(cfg.showStackCount and (i % 3 == 1 and "2" or "") or "")
        ApplyAuraFont(icon.timer, cooldownSize)
        icon.timer:ClearAllPoints()
        icon.timer:SetPoint("CENTER", icon, "CENTER", cooldownX, cooldownY)
        icon.timer:SetJustifyH("CENTER")
        icon.timer:SetText(cfg.showCooldownText and (i % 2 == 0 and "18" or "") or "")
        icon:Show()
    end
    for i = bounds.shown + 1, #(visual._icons or {}) do
        visual._icons[i]:Hide()
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
