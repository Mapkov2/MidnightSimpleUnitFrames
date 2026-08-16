--- Group preview render/composition.
---
--- Native creates the preview host and interaction handles; this module owns
--- the hot refresh path that lays out the mock group frame and preview layers.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Render = M.GroupPreviewRender or {}
M.GroupPreviewRender = Render
local F = M.Fallbacks or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local issecretvalue = _G.issecretvalue or function(_) return false end
local wipe = _G.wipe or function(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
local function ResolvePreviewNameGeometry(conf, runtimeText, baselineOffset)
    conf, runtimeText = conf or {}, runtimeText or {}
    local x = tonumber(conf.nameOffsetX)
    if x == nil then x = tonumber(runtimeText.nameX) or 0 end
    local y = tonumber(conf.nameOffsetY)
    if y ~= nil then
        y = y + (tonumber(baselineOffset) or 0)
    else
        y = tonumber(runtimeText.nameY) or 0
    end
    return conf.nameAnchor or runtimeText.nameAnchor or "LEFT", x, y
end
local function ResolvePreviewNamePoint(anchor, x, y)
    anchor = tostring(anchor or "LEFT"):upper()
    x, y = tonumber(x) or 0, tonumber(y) or 0
    -- LayoutBarAnchoredName uses a 3px inset on both ends of its runtime span.
    -- Resolve the visible glyph endpoint from that span so the natural-width
    -- preview FontString and its interaction outline share one exact rectangle.
    if anchor == "TOPLEFT" then
        return "TOPLEFT", x + 3, y, "LEFT"
    elseif anchor == "TOP" then
        return "TOP", x, y, "CENTER"
    elseif anchor == "TOPRIGHT" then
        return "TOPRIGHT", x - 3, y, "RIGHT"
    elseif anchor == "CENTER" then
        return "CENTER", x, y, "CENTER"
    elseif anchor == "RIGHT" then
        return "RIGHT", x - 3, y, "RIGHT"
    end
    return "LEFT", x + 3, y, "LEFT"
end
local function LayoutPreviewName(fs, relativeTo, point, x, y, justify)
    if not (fs and relativeTo) then return end
    if fs._msufPreviewNameGeometryDirty == true
        or fs._msufPreviewNameNaturalWidth ~= true
        or fs._msufPreviewNameRelativeTo ~= relativeTo
        or fs._msufPreviewNamePoint ~= point
        or fs._msufPreviewNameX ~= x
        or fs._msufPreviewNameY ~= y then
        fs:ClearAllPoints()
        if fs._msufPreviewNameNaturalWidth ~= true then
            fs:SetWidth(0)
            fs._msufPreviewNameNaturalWidth = true
        end
        fs:SetPoint(point, relativeTo, point, x, y)
        fs._msufPreviewNameRelativeTo = relativeTo
        fs._msufPreviewNamePoint = point
        fs._msufPreviewNameX = x
        fs._msufPreviewNameY = y
        fs._msufPreviewNameGeometryDirty = nil
    end
    if fs._msufPreviewJustifyH ~= justify then
        fs:SetJustifyH(justify)
        fs._msufPreviewJustifyH = justify
    end
end
-- Kept as narrow test seams: Group Preview is the only consumer, and exposing
-- the pure geometry avoids testing a second copy of these anchor rules.
Render._ResolvePreviewNameGeometry = ResolvePreviewNameGeometry
Render._ResolvePreviewNamePoint = ResolvePreviewNamePoint
Render._LayoutPreviewName = LayoutPreviewName
local function DefaultCompiledAuraLane(_, _, fallback) return fallback or {} end
local function DefaultInt(value, fallback, minValue, maxValue)
    local n = math.floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end
local function NumberOrOne(value) return tonumber(value) or 1 end
local SPELL_PREVIEW_ROUNDED_OPTS = {
    bgKey = "_msufSpellRoundedBg",
    edgeKey = "_msufSpellRoundedEdge",
    stackKey = "_msufSpellRoundedEdgeStack",
    countKey = "_msufSpellRoundedEdgeCount",
    whiteTexture = "Interface\\Buttons\\WHITE8X8",
    edgeLayer = "OVERLAY",
    edgeSubLevel = 1,
    maxEdgeSize = 16,
    baseEdgeColor = function(host)
        return host._msufSpellRoundedR or 1, host._msufSpellRoundedG or 1,
            host._msufSpellRoundedB or 1, host._msufSpellRoundedA or 1
    end,
}
local function RoundedSpellPreviewEnabled()
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    return bars and bars.roundedFramesEnabled == true and bars.roundedGroupFrames ~= false
end
local function SetRoundedSpellPreview(root, target, shown, thickness, r, g, b, a, blendMode)
    local helpers = M.PreviewHelpers or {}
    local host = root and root._msufSpellRoundedHost
    if not shown or not RoundedSpellPreviewEnabled()
        or not (helpers.ResolveRoundedMedia and helpers.EnsureRoundedVisuals
            and helpers.ApplyRoundedEdgeStack) then
        if host and helpers.SetRoundedEdgeStackShown then
            helpers.SetRoundedEdgeStackShown(host, false, SPELL_PREVIEW_ROUNDED_OPTS)
        end
        return false
    end
    if not host then
        host = CreateFrame("Frame", nil, root)
        host:EnableMouse(false)
        root._msufSpellRoundedHost = host
    end
    host:ClearAllPoints()
    host:SetAllPoints(target)
    host._msufSpellRoundedR, host._msufSpellRoundedG = r, g
    host._msufSpellRoundedB, host._msufSpellRoundedA = b, a
    local _, edgePath, strength = helpers.ResolveRoundedMedia()
    SPELL_PREVIEW_ROUNDED_OPTS.edgeTexture = edgePath
    SPELL_PREVIEW_ROUNDED_OPTS.mediaStrength = strength
    SPELL_PREVIEW_ROUNDED_OPTS.snapOff = helpers.SnapOff
    if not helpers.EnsureRoundedVisuals(host, SPELL_PREVIEW_ROUNDED_OPTS)
        or not helpers.ApplyRoundedEdgeStack(host, thickness, SPELL_PREVIEW_ROUNDED_OPTS) then
        return false
    end
    if host._msufSpellRoundedBg then host._msufSpellRoundedBg:Hide() end
    if helpers.ForEachRoundedEdge then
        helpers.ForEachRoundedEdge(host, SPELL_PREVIEW_ROUNDED_OPTS, function(edge)
            if edge.SetBlendMode then edge:SetBlendMode(blendMode or "BLEND") end
        end)
    end
    host:Show()
    return true
end
--- Sample subgroup label for the preview, formatted by the live raid-group
--- formatter so the preview cannot drift from the runtime text.
local GROUP_BLOCK_BORDER_EDGES = { "top", "bottom", "left", "right" }
local SetPreviewFrameLevel, PreviewElementLevel, PreviewInteractionLevel
--- Mirror of ApplyGroupBorder in the group header engine: same edge geometry,
--- scaled into preview space. Without this the Group Border card had no visual
--- feedback at all in the menu preview.
local function PaintGroupBlockBorder(mock, conf, previewScale, ScaleValue)
    if not mock then return end
    local edges = mock._msufGroupBlockBorder
    if conf.groupBorderEnabled ~= true then
        if edges then
            for i = 1, #GROUP_BLOCK_BORDER_EDGES do
                local edge = edges[GROUP_BLOCK_BORDER_EDGES[i]]
                if edge then edge:Hide() end
            end
        end
        local rounded = _G.MSUF_RoundedUF_OnGroupBlockBorder
        if rounded then rounded(mock, conf, false) end
        return
    end
    edges = edges or {}
    mock._msufGroupBlockBorder = edges
    local size = ScaleValue(tonumber(conf.groupBorderSize) or 1, previewScale, 1)
    local pad = ScaleValue(tonumber(conf.groupBorderPadding) or 2, previewScale, 0)
    local r = tonumber(conf.groupBorderR) or 0.38
    local g = tonumber(conf.groupBorderG) or 0.68
    local b = tonumber(conf.groupBorderB) or 1
    local a = tonumber(conf.groupBorderA) or 0.95
    local roundedConf = mock._msufGroupBlockRoundedConf or {}
    mock._msufGroupBlockRoundedConf = roundedConf
    roundedConf.groupBorderSize, roundedConf.groupBorderPadding = size, pad
    roundedConf.groupBorderR, roundedConf.groupBorderG = r, g
    roundedConf.groupBorderB, roundedConf.groupBorderA = b, a
    for i = 1, #GROUP_BLOCK_BORDER_EDGES do
        local key = GROUP_BLOCK_BORDER_EDGES[i]
        local edge = edges[key]
        if not edge then
            edge = mock:CreateTexture(nil, "OVERLAY")
            edges[key] = edge
        end
        edge:SetColorTexture(r, g, b, a)
        edge:ClearAllPoints()
        if key == "top" then
            edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -pad, pad)
            edge:SetPoint("TOPRIGHT", mock, "TOPRIGHT", pad, pad)
            edge:SetHeight(size)
        elseif key == "bottom" then
            edge:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", -pad, -pad)
            edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", pad, -pad)
            edge:SetHeight(size)
        elseif key == "left" then
            edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -pad, pad)
            edge:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", -pad, -pad)
            edge:SetWidth(size)
        else
            edge:SetPoint("TOPRIGHT", mock, "TOPRIGHT", pad, pad)
            edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", pad, -pad)
            edge:SetWidth(size)
        end
        edge:Show()
    end
    local rounded = _G.MSUF_RoundedUF_OnGroupBlockBorder
    if rounded and rounded(mock, roundedConf, true) then
        for i = 1, #GROUP_BLOCK_BORDER_EDGES do
            local edge = edges[GROUP_BLOCK_BORDER_EDGES[i]]
            if edge then edge:Hide() end
        end
    end
end

local GROUP_PORTRAIT_MASKS = {
    SQUARE = "Interface\\Buttons\\WHITE8x8",
    CIRCLE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\circle_mask.tga",
    ROUNDED = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\rounded_mask.tga",
    DIAMOND = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\diamond_mask.tga",
}
local GROUP_PORTRAIT_SOFT_EDGE_MASKS = { SQUARE = {}, CIRCLE = {}, ROUNDED = {}, DIAMOND = {} }
do
    local root = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    for level = 1, 15 do
        local suffix = (level < 10 and "0" or "") .. tostring(level) .. ".png"
        GROUP_PORTRAIT_SOFT_EDGE_MASKS.SQUARE[level] = root .. "texture_layer_edge_softness_" .. suffix
        GROUP_PORTRAIT_SOFT_EDGE_MASKS.CIRCLE[level] = root .. "portrait_edge_softness_circle_" .. suffix
        GROUP_PORTRAIT_SOFT_EDGE_MASKS.ROUNDED[level] = root .. "portrait_edge_softness_rounded_" .. suffix
        GROUP_PORTRAIT_SOFT_EDGE_MASKS.DIAMOND[level] = root .. "portrait_edge_softness_diamond_" .. suffix
    end
end
local GROUP_PORTRAIT_SHAPED = { CIRCLE = true, ROUNDED = true, DIAMOND = true }
local GROUP_PORTRAIT_RING_ART = {
    SQUARE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_square.tga",
    CIRCLE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_circle.tga",
    ROUNDED = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_rounded.tga",
    DIAMOND = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_diamond.tga",
}
local GROUP_PORTRAIT_RING_ROTATION = {
    UP = { 0, 0, 0, 1, 1, 0, 1, 1 },
    RIGHT = { 0, 1, 1, 1, 0, 0, 1, 0 },
    DOWN = { 1, 1, 1, 0, 0, 1, 0, 0 },
    LEFT = { 1, 0, 0, 0, 1, 1, 0, 1 },
}

local function DisableGroupPreviewPortraitMouse(frame)
    if not frame then return end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
end

local function EnsureGroupPreviewPortrait(mock, handle)
    local holder = mock and mock._msufGroupPortrait
    if handle and holder ~= handle then
        if holder then holder:Hide() end
        holder = handle
        mock._msufGroupPortrait = holder
    end
    if holder and holder._msufGroupPortraitVisual == true then
        DisableGroupPreviewPortraitMouse(holder.border)
        return holder
    end
    if not mock then return nil end
    holder = holder or handle or CreateFrame("Frame", nil, mock)
    if holder ~= handle then
        DisableGroupPreviewPortraitMouse(holder)
    else
        -- Match the working Unit Preview contract: the portrait Button itself
        -- owns the visible texture and therefore remains the top mouse target.
        if holder.EnableMouse then holder:EnableMouse(true) end
        if holder.SetMouseClickEnabled then holder:SetMouseClickEnabled(true) end
        if holder.SetMouseMotionEnabled then holder:SetMouseMotionEnabled(true) end
    end
    holder.bg = holder:CreateTexture(nil, "BACKGROUND", nil, -1)
    holder.bg:SetAllPoints(holder)
    holder.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    holder.tex = holder:CreateTexture(nil, "ARTWORK")
    holder.tex:SetAllPoints(holder)
    if holder.CreateMaskTexture and holder.tex.AddMaskTexture then
        holder.mask = holder:CreateMaskTexture()
        holder.mask:SetAllPoints(holder)
        holder.tex:AddMaskTexture(holder.mask)
        holder.bg:AddMaskTexture(holder.mask)
    end
    holder.border = CreateFrame("Frame", nil, holder)
    DisableGroupPreviewPortraitMouse(holder.border)
    holder.border:SetAllPoints(holder)
    holder.edges = {}
    for i = 1, 4 do
        local edge = holder.border:CreateTexture(nil, "OVERLAY")
        edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        edge:Hide()
        holder.edges[i] = edge
    end
    holder:Hide()
    holder._msufGroupPortraitVisual = true
    mock._msufGroupPortrait = holder
    return holder
end

local function HideGroupPreviewPortraitBorder(holder)
    if not holder then return end
    for i = 1, #(holder.edges or {}) do holder.edges[i]:Hide() end
    if holder.ring then holder.ring:Hide() end
    if holder.artBorder then holder.artBorder:Hide() end
end

local function LayoutGroupPreviewPortraitBorder(holder, portrait, previewScale, ScaleValue, ClassColor, classToken)
    local cfg = portrait and portrait.border
    local style = cfg and cfg.style or "NONE"
    if style == "NONE" then
        HideGroupPreviewPortraitBorder(holder)
        return
    end
    local r, g, b, a
    if style == "CLASS_COLOR" then
        r, g, b = ClassColor(classToken, 1, 1, 1)
        a = 1
    elseif style == "REACTION" then
        r, g, b, a = 0.1, 0.85, 0.1, 1
    else
        r, g, b, a = cfg.r or 1, cfg.g or 1, cfg.b or 1, cfg.a or 1
    end
    local thick = ScaleValue(cfg.thickness or 2, previewScale, 1)
    local shape = portrait.shape or "SQUARE"
    if cfg.art == "RELIEF" then
        local art = holder.artBorder
        if not art then
            art = holder.border:CreateTexture(nil, "OVERLAY", nil, 2)
            holder.artBorder = art
        end
        local width = tonumber(holder._msufPreviewWidth) or tonumber(holder:GetWidth()) or 36
        local height = tonumber(holder._msufPreviewHeight) or tonumber(holder:GetHeight()) or 36
        local multiplier = 0.0952380952 * ((tonumber(thick) or 2) / 2)
        local inflateX = math.floor(math.max(1, width * multiplier) + 0.5)
        local inflateY = math.floor(math.max(1, height * multiplier) + 0.5)
        local direction = cfg.direction or "UP"
        local key = shape .. "|" .. inflateX .. "|" .. inflateY .. "|" .. direction
        if holder._msufPreviewArtKey ~= key then
            art:ClearAllPoints()
            art:SetPoint("TOPLEFT", holder, "TOPLEFT", -inflateX, inflateY)
            art:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", inflateX, -inflateY)
            art:SetTexture(GROUP_PORTRAIT_RING_ART[shape] or GROUP_PORTRAIT_RING_ART.SQUARE)
            local rotation = GROUP_PORTRAIT_RING_ROTATION[direction] or GROUP_PORTRAIT_RING_ROTATION.UP
            art:SetTexCoord(rotation[1], rotation[2], rotation[3], rotation[4],
                rotation[5], rotation[6], rotation[7], rotation[8])
            holder._msufPreviewArtKey = key
        end
        art:SetVertexColor(r, g, b, a)
        art:Show()
        for i = 1, #holder.edges do holder.edges[i]:Hide() end
        if holder.ring then holder.ring:Hide() end
        return
    end
    if holder.artBorder then holder.artBorder:Hide() end
    if GROUP_PORTRAIT_SHAPED[shape] then
        local ring = holder.ring
        if not ring then
            ring = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
            ring:SetTexture("Interface\\Buttons\\WHITE8x8")
            if holder.CreateMaskTexture and ring.AddMaskTexture then
                holder.ringMask = holder:CreateMaskTexture()
                ring:AddMaskTexture(holder.ringMask)
            end
            holder.ring = ring
        end
        local key = shape .. "|" .. thick
        if holder._msufPreviewRingKey ~= key then
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
            ring:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
            if holder.ringMask then
                holder.ringMask:ClearAllPoints()
                holder.ringMask:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
                holder.ringMask:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
                holder.ringMask:SetTexture(GROUP_PORTRAIT_MASKS[shape])
            end
            holder._msufPreviewRingKey = key
        end
        ring:SetVertexColor(r, g, b, a)
        ring:Show()
        for i = 1, #holder.edges do holder.edges[i]:Hide() end
        return
    end
    if holder.ring then holder.ring:Hide() end
    local fill = cfg.fill == true
    local key = thick .. "|" .. (fill and "1" or "0")
    local top, bottom, left, right = holder.edges[1], holder.edges[2], holder.edges[3], holder.edges[4]
    if holder._msufPreviewBorderKey ~= key then
        for i = 1, #holder.edges do holder.edges[i]:ClearAllPoints() end
        local pad = fill and 0 or thick
        top:SetPoint("TOPLEFT", holder, "TOPLEFT", -pad, pad)
        top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", pad, pad)
        bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -pad, -pad)
        bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", pad, -pad)
        left:SetPoint("TOPLEFT", holder, "TOPLEFT", -pad, pad)
        left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -pad, -pad)
        right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", pad, pad)
        right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", pad, -pad)
        top:SetHeight(thick)
        bottom:SetHeight(thick)
        left:SetWidth(thick)
        right:SetWidth(thick)
        holder._msufPreviewBorderKey = key
    end
    for i = 1, #holder.edges do
        holder.edges[i]:SetVertexColor(r, g, b, a)
        holder.edges[i]:Show()
    end
end

--- Dispel-type symbol row.
---
--- The live symbol is a native AuraButton texture whose visibility and artwork
--- Blizzard owns, so it only ever appears with a real debuff on the unit. The
--- preview therefore draws stand-in art -- but it reads that art from the SAME
--- per-type tables Auras3 hands to Blizzard (MSUF.MSUF_Auras3.DispelSymbol), so
--- the preview cannot show a set the runtime would not.
---
--- "One per dispel type" is the default, so the row shows all five types side by
--- side along the configured growth axis; TOP mode shows only the first.
local DISPEL_SYMBOL_PREVIEW_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

local function DispelSymbolPreviewArt(texture, DS, style, dispelType)
    if DS and type(DS.PreviewArt) == "function" then
        DS.PreviewArt(texture, style, dispelType)
        return
    end
    texture:SetTexCoord(0, 1, 0, 1)
    local assets = DS and DS.AssetMap and DS.AssetMap(style)
    if assets then
        local asset = assets[dispelType]
        texture:SetTexture(asset and asset.asset or nil)
        return
    end
    local atlas = DS and ((style == "BLIZZARD_RING" and DS.rings)
        or (style == "BLIZZARD_BORDER" and DS.borders)
        or DS.icons)
    atlas = atlas and atlas[dispelType]
    if atlas and texture.SetAtlas then
        texture:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
    else
        texture:SetTexture(nil)
    end
end

local function PaintGroupPreviewDispelOverlay(scene)
    local overlay = scene.runtimeSpec and scene.runtimeSpec.group
    local mock = scene.mock
    local host = mock and mock._msufGFPreviewDispelOverlayHost
    local layerOn = overlay and overlay.dispelOverlayEnabled == true
        and scene.layerAvailable.dispelOverlay ~= false
        and scene.layerVisible.dispelOverlay ~= false
    if not layerOn then
        if host then host:Hide() end
        return
    end
    local health = mock and mock._health
    if not health then
        if host then host:Hide() end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, mock)
        host:EnableMouse(false)
        host.Region = host:CreateTexture(nil, "OVERLAY")
        host.Region:SetTexture("Interface\\Buttons\\WHITE8X8")
        mock._msufGFPreviewDispelOverlayHost = host
        mock._msufGFPreviewDispelOverlayRegion = host.Region
    end
    host:ClearAllPoints()
    host:SetAllPoints(health)
    local level = scene.S.Layers and scene.S.Layers.ElementLevel
        and PreviewElementLevel(mock, scene.S.Layers, overlay.dispelOverlayLayer, 0, 12)
        or (((mock.GetFrameLevel and mock:GetFrameLevel()) or 1)
            + (tonumber(overlay.dispelOverlayLayer) or 0) + 12)
    SetPreviewFrameLevel(host, level)
    local target = overlay.dispelOverlayOnHealth ~= false and health.GetStatusBarTexture
        and health:GetStatusBarTexture() or health
    if not target then
        host:Hide()
        return
    end
    local region = host.Region
    local style = tostring(overlay.dispelOverlayStyle or "FULL"):upper()
    local thickness = scene.S.ScaleValue(tonumber(scene.runtimeBorder.highlightThickness) or 3,
        scene.previewScale, 1)
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
    local a3 = scene.MSUF and scene.MSUF.MSUF_Auras3
    if a3 and type(a3.SetDispelColorTexture) == "function" then
        a3.SetDispelColorTexture(region, a3.GetDispelColorPreviewType(), true, 1)
    else
        local color = scene.runtimeSpec and scene.runtimeSpec.dispel
        region:SetColorTexture(tonumber(color and color.r) or 0.25,
            tonumber(color and color.g) or 0.75, tonumber(color and color.b) or 1, 1)
    end
    local alpha = math.max(0, math.min(1, tonumber(overlay.dispelOverlayAlpha) or 0.35))
    local layerAlpha = scene.soloLayer and scene.soloLayer ~= "dispelOverlay" and 0.15 or 1
    region:SetAlpha(alpha * layerAlpha)
    region:Show()
    host:Show()
end

local function PaintGroupPreviewDispelSymbol(scene)
    local symbol = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    local handle = scene.S and scene.S.dispelSymbolHandle
    if not handle then return end
    local layerOn = symbol and symbol.enabled == true
        and scene.layerAvailable and scene.layerAvailable.dispelSymbol ~= false
        and scene.layerVisible and scene.layerVisible.dispelSymbol ~= false
    if not layerOn then
        handle:Hide()
        return
    end
    local DS = scene.MSUF and scene.MSUF.MSUF_Auras3 and scene.MSUF.MSUF_Auras3.DispelSymbol
    local scale, ScaleValue = scene.previewScale, scene.S.ScaleValue
    local size = ScaleValue(tonumber(symbol.size) or 12, scale, 1)
    local spacing = ScaleValue(tonumber(symbol.spacing) or 2, scale, 0)
    local count = (tostring(symbol.mode or "ALL"):upper() ~= "TOP") and #DISPEL_SYMBOL_PREVIEW_ORDER or 1
    -- Resolved through the runtime helper so the preview row and the live row
    -- can never disagree about which way the symbols march.
    local growth = (DS and DS.ResolveGrowth and DS.ResolveGrowth(symbol.growth, symbol.anchor))
        or tostring(symbol.growth or "RIGHT"):upper()
    local vertical = growth == "UP" or growth == "DOWN"
    local step = size + spacing
    local span = size + (count - 1) * step
    -- The handle is the whole row so a single drag moves the set, exactly like
    -- the live sensor keeps its per-type steps relative to one stored origin.
    if not (handle._dragging == true) then
        handle:ClearAllPoints()
        handle:SetSize(vertical and size or span, vertical and span or size)
        local anchor = tostring(symbol.anchor or "TOPRIGHT")
        handle:SetPoint(anchor, scene.mock, anchor,
            ScaleValue(tonumber(symbol.x) or 0, scale), ScaleValue(tonumber(symbol.y) or 0, scale))
    end
    -- Same solo-layer dimming SceneLayerAlpha applies; that helper is declared
    -- further down the file, so the two lines are inlined here.
    handle:SetAlpha(scene.soloLayer and scene.soloLayer ~= "dispelSymbol" and 0.15 or 1)
    local icons = handle._icons or {}
    for i = 1, #icons do
        local tex = icons[i]
        if i > count then
            tex:Hide()
        else
            local offset = (i - 1) * step
            tex:ClearAllPoints()
            tex:SetSize(size, size)
            if growth == "LEFT" then
                tex:SetPoint("TOPRIGHT", handle, "TOPRIGHT", -offset, 0)
            elseif growth == "UP" then
                tex:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", 0, offset)
            elseif growth == "DOWN" then
                tex:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, -offset)
            else
                tex:SetPoint("TOPLEFT", handle, "TOPLEFT", offset, 0)
            end
            local iconAlpha = tonumber(symbol.alpha) or 1
            if iconAlpha < 0 then iconAlpha = 0 elseif iconAlpha > 1 then iconAlpha = 1 end
            tex:SetAlpha(iconAlpha)
            local dispelType = DISPEL_SYMBOL_PREVIEW_ORDER[i]
            DispelSymbolPreviewArt(tex, DS, symbol.style, dispelType)
            tex:Show()
        end
    end
    handle:Show()
end

local function PaintGroupPreviewPortrait(scene)
    local portrait = scene.runtimeSpec and scene.runtimeSpec.portrait
    local holder = scene.mock and scene.mock._msufGroupPortrait
    local handle = scene.S and scene.S.portraitHandle
    if scene.kind ~= "party" or not (portrait and portrait.enabled == true) then
        if holder then
            HideGroupPreviewPortraitBorder(holder)
            holder:Hide()
        end
        if handle then handle:Hide() end
        return
    end
    holder = EnsureGroupPreviewPortrait(scene.mock, handle)
    if not holder then return end
    local layerAvailable = scene.layerAvailable and scene.layerAvailable.portrait ~= false
    local layerOn = layerAvailable and scene.layerVisible.portrait ~= false
    if not layerOn then
        holder:Hide()
        if handle then handle:Hide() end
        return
    end
    local scale, ScaleValue = scene.previewScale, scene.S.ScaleValue
    local width = ScaleValue(portrait.width or portrait.size or 36, scale, 1)
    local height = ScaleValue(portrait.height or portrait.size or 36, scale, 1)
    local x = ScaleValue(portrait.x or 0, scale)
    local y = ScaleValue(portrait.y or 0, scale)
    holder._msufPreviewWidth, holder._msufPreviewHeight = width, height
    local owner = handle or holder
    if not (handle and handle._dragging == true) then
        owner:ClearAllPoints()
        if portrait.placement == "DETACHED" then
            owner:SetSize(width, height)
            owner:SetPoint(portrait.point or "RIGHT", scene.mock, portrait.relPoint or "LEFT", x, y)
        elseif portrait.placement == "OVERLAY" then
            if portrait.overlayAlign == "FULL" then
                owner:SetPoint("TOPLEFT", scene.mock, "TOPLEFT", x, -y)
                owner:SetPoint("BOTTOMRIGHT", scene.mock, "BOTTOMRIGHT", -x, y)
                holder._msufPreviewWidth = math.max(1, (tonumber(scene.mock:GetWidth()) or width) - x * 2)
                holder._msufPreviewHeight = math.max(1, (tonumber(scene.mock:GetHeight()) or height) - y * 2)
            else
                owner:SetSize(width, height)
                local align = portrait.overlayAlign or "LEFT"
                owner:SetPoint(align, scene.mock, align, x, y)
            end
        else
            owner:SetSize(width, height)
            if portrait.side == "RIGHT" then owner:SetPoint("LEFT", scene.mock, "RIGHT", x, y)
            else owner:SetPoint("RIGHT", scene.mock, "LEFT", x, y) end
        end
    end
    if handle then
        handle._locked = portrait.placement == "OVERLAY" and portrait.overlayAlign == "FULL"
        handle._previewScale, handle._previewWriteScale = scale, scale
        if holder ~= handle then
            holder:ClearAllPoints()
            holder:SetAllPoints(handle)
        end
    end
    local level = math.max(0, math.min(30, tonumber(portrait.levelOffset) or 7))
    if holder.SetFrameLevel and scene.mock.GetFrameLevel then
        local layers = scene.S.Layers or {}
        local handleLevel = layers.ElementLevel and PreviewElementLevel(scene.mock, layers, level, 7, 0)
            or ((scene.mock:GetFrameLevel() or 1) + level)
        if handle then SetPreviewFrameLevel(handle, handleLevel) end
        if holder ~= handle then SetPreviewFrameLevel(holder, handleLevel) end
        SetPreviewFrameLevel(holder.border, (holder:GetFrameLevel() or 1) + 1)
        if handle and handle._selectBorder then
            SetPreviewFrameLevel(handle._selectBorder, (holder.border:GetFrameLevel() or 1) + 1)
        end
    end
    local layerAlpha = scene.soloLayer and scene.soloLayer ~= "portrait" and 0.15 or 1
    local configuredPortraitAlpha = tonumber(portrait.alpha) or 1
    if holder == handle then
        -- Keep the Button/selection affordance interactive at full layer alpha;
        -- only the portrait artwork follows the configured portrait opacity.
        holder:SetAlpha(layerAlpha)
        if holder.bg then holder.bg:SetAlpha(configuredPortraitAlpha) end
        if holder.tex then holder.tex:SetAlpha(configuredPortraitAlpha) end
        if holder.border then holder.border:SetAlpha(configuredPortraitAlpha) end
        if holder.ring then holder.ring:SetAlpha(configuredPortraitAlpha) end
    else
        holder:SetAlpha(configuredPortraitAlpha * layerAlpha)
    end
    if handle and holder ~= handle then
        handle:SetAlpha(layerAlpha)
    end
    if handle then handle:Show() end
    if holder.mask then
        local shape = portrait.shape or "SQUARE"
        local softMasks = GROUP_PORTRAIT_SOFT_EDGE_MASKS[shape]
        local mask = softMasks and softMasks[portrait.edgeSoftnessLevel]
            or GROUP_PORTRAIT_MASKS[shape] or GROUP_PORTRAIT_MASKS.SQUARE
        holder.mask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    local classToken = scene.liveData and scene.liveData.class
        or scene.S.GF_PREVIEW_CLASSES[((scene.kind == "party" and 5 or 2) % #scene.S.GF_PREVIEW_CLASSES) + 1]
    local castTexture = portrait.castSpellIcon == true and scene.box._animationEnabled == true
        and scene.S.CurrentSpellTexture(scene.kind) or nil
    if castTexture then
        holder.tex:SetTexture(castTexture)
        holder.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif portrait.render == "CLASS" then
        local media = scene.MSUF and scene.MSUF.PortraitMedia
        local visual = media and media.ResolveClassPortrait and media.ResolveClassPortrait(classToken, portrait.classStyle)
        if not visual then
            local coords = classToken and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classToken]
            visual = {
                texture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
                left = coords and coords[1] or 0, right = coords and coords[2] or 1,
                top = coords and coords[3] or 0, bottom = coords and coords[4] or 1,
            }
        end
        if visual.atlas and holder.tex.SetAtlas then holder.tex:SetAtlas(visual.atlas)
        else
            holder.tex:SetTexture(visual.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
            holder.tex:SetTexCoord(visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
        end
    else
        if type(_G.SetPortraitTexture) == "function" then _G.SetPortraitTexture(holder.tex, "player")
        else holder.tex:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark") end
        holder.tex:SetTexCoord(portrait.texL or 0.08, portrait.texR or 0.92, portrait.texT or 0.08, portrait.texB or 0.92)
    end
    holder.tex:SetVertexColor(1, 1, 1, 1)
    if portrait.bg and portrait.bg.enabled == true then
        holder.bg:SetVertexColor(portrait.bg.r or 0.05, portrait.bg.g or 0.05, portrait.bg.b or 0.05, portrait.bg.a or 0.85)
        holder.bg:Show()
    else
        holder.bg:Hide()
    end
    LayoutGroupPreviewPortraitBorder(holder, portrait, scale, ScaleValue, scene.S.ClassColor, classToken)
    if holder == handle and holder.ring then holder.ring:SetAlpha(configuredPortraitAlpha) end
    holder:Show()
end

-- Kept as a narrow module seam so the interaction smoke can exercise the
-- exact production portrait painter with a real preview Button.
Render.PaintGroupPreviewPortrait = PaintGroupPreviewPortrait

local function DefaultAuraGrowth() return { px = 1, py = 0, sx = 0, sy = -1 } end
local function DefaultClampLayer(value, fallback) return tonumber(value) or fallback or 0 end
local function AuraDurationBarColor()
    local auras3 = MSUF.MSUF_Auras3
    local resolver = auras3 and auras3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
end
local function NormalizeFrameStrata(value, fallback)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
    if issecretvalue(value) == true then return fallback or "AUTO" end
    if value == nil or value == "" then return fallback or "AUTO" end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or (fallback or "AUTO")
end
local PREVIEW_UNITFRAME_STRATA = "MEDIUM"
-- Raise the cached mock above the preview canvas, then use that exact level as
-- the bias for every absolute runtime ElementLevel encoded below.
local PREVIEW_LOCAL_BASE_OFFSET = 400
local PREVIEW_FRAME_LEVEL_MAX = 65535
local function SafePreviewFrameLevel(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value < 0 then return 0 end
    if value > PREVIEW_FRAME_LEVEL_MAX then return PREVIEW_FRAME_LEVEL_MAX end
    return value
end
SetPreviewFrameLevel = function(frame, value)
    if not (frame and frame.SetFrameLevel) then return 0 end
    value = SafePreviewFrameLevel(value)
    frame:SetFrameLevel(value)
    return value
end
--- The live layer encoder is intentionally absolute. Menu2, however, raises
--- its cached Group mock into a private frame-level band so it stays above the
--- preview canvas. Translate every encoded live level by that one mock-owned
--- bias; mixing an unshifted ElementLevel with the raised mock puts ordinary
--- Layer 0..9 content (notably Name/HP/Power text) underneath the health bar.
PreviewElementLevel = function(mock, layerAPI, layer, fallback, detail)
    local encoded
    if layerAPI and layerAPI.ElementLevel then
        encoded = layerAPI.ElementLevel(layer, fallback, detail)
    else
        local value = math.floor((tonumber(layer) or fallback or 0) + 0.5)
        if value < 0 then value = 0 elseif value > 30 then value = 30 end
        detail = math.floor((tonumber(detail) or 0) + 0.5)
        if detail < 0 then detail = 0 elseif detail > 31 then detail = 31 end
        encoded = 100 + value * 32 + detail
    end
    return SafePreviewFrameLevel((tonumber(mock and mock._msufPreviewElementLevelBias) or 0) + encoded)
end
PreviewInteractionLevel = function(mock, layerAPI, extra)
    local top = PreviewElementLevel(mock, layerAPI, 30, 30,
        layerAPI and layerAPI.ELEMENT_DETAIL_MAX or 31)
    return SafePreviewFrameLevel(top + (tonumber(layerAPI and layerAPI.ELEMENT_LEVEL_STRIDE) or 32)
        + (tonumber(extra) or 0))
end
local function FrameStrataRank(value)
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] or 0
end
local function DefaultClassColor(_, r, g, b) return r or 1, g or 1, b or 1 end
local GROUP_RENDER_FALLBACKS = {
    CompiledSpec = F.Nil, CompiledAuraLane = DefaultCompiledAuraLane, RuntimeStatusConfig = F.Nil,
    CurrentStatusSpec = F.Nil, StatusSpecEnabled = F.False, StatusSpecInMode = F.False, StatusSpecIsText = F.False,
    StatusText = F.Empty, StatusLabel = F.Status, CurrentSpellInfo = F.Nil, PreviewAllSpecSpellIcons = F.False, CurrentSpellConfig = F.Nil, CurrentSpellPlaced = F.Nil,
    CurrentSpellTexture = F.QuestionIcon, CurrentSpellColor = F.WhiteRGB, MockSpellTexture = F.QuestionIcon,
    Int = DefaultInt, Round = F.Round, ClampZoom = NumberOrOne, ResolveDefaultZoomLock = F.Noop, UpdateZoomControls = F.Noop,
    AuraGrowth = DefaultAuraGrowth, ApplyRounded = F.False, ClampLayer = DefaultClampLayer,
    ClassColor = DefaultClassColor, HealthColor = F.HealthRGB,
    SelectHandle = F.Noop, NudgeHandlePosition = F.Noop, AddIconPool = F.Noop, RefreshHandleSelection = F.Noop,
}
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}

-- A refresh first resolves immutable inputs into a scene. Render components then
-- measure and paint that scene without reaching back through the install closure.
local function RawTrackedBuffLane(scene, rawBuff)
    rawBuff = rawBuff or {}
    local indicators = scene.conf.spellIndicators
    return {
        enabled = rawBuff.trackedEnabled == true
            or (rawBuff.trackedEnabled == nil and indicators and indicators.enabled == true),
        max = rawBuff.trackedMax or 8,
        perRow = rawBuff.trackedPerRow or rawBuff.perRow or 4,
        size = rawBuff.trackedSize or rawBuff.size or 22,
        spacing = rawBuff.trackedSpacing or rawBuff.spacing or 1,
        anchor = rawBuff.trackedAnchor or "TOPLEFT",
        growth = rawBuff.trackedGrowth or "RIGHTDOWN",
        x = rawBuff.trackedX or 0,
        y = rawBuff.trackedY or 0,
        layer = rawBuff.trackedLayer or (indicators and indicators.layer) or 9,
        strata = rawBuff.trackedStrata or (indicators and indicators.strata) or rawBuff.strata,
        showCooldownSwipe = rawBuff.trackedShowCooldownSwipe,
        cooldownSwipeReverse = rawBuff.trackedCooldownSwipeReverse,
        showCooldown = rawBuff.trackedShowCooldown,
        showCooldownText = rawBuff.trackedShowCooldown,
        showStacks = rawBuff.trackedShowStacks,
        showTooltip = rawBuff.trackedShowTooltip,
        showDurationBar = rawBuff.trackedShowDurationBar,
        durationBarHeight = rawBuff.trackedDurationBarHeight,
        durationBarDisplay = rawBuff.trackedDurationBarDisplay,
        durationBarPosition = rawBuff.trackedDurationBarPosition,
        durationBarDirection = rawBuff.trackedDurationBarDirection,
        cooldownSize = rawBuff.trackedCooldownSize,
        cooldownAnchor = rawBuff.trackedCooldownAnchor,
        cooldownX = rawBuff.trackedCooldownX,
        cooldownY = rawBuff.trackedCooldownY,
        cooldownDecimalSeconds = rawBuff.trackedCooldownDecimalSeconds,
        stackSize = rawBuff.trackedStackSize,
        stackAnchor = rawBuff.trackedStackAnchor,
        stackX = rawBuff.trackedStackX,
        stackY = rawBuff.trackedStackY,
    }
end

local function SceneStatusAvailable(scene, spec)
    if scene.runtimeSpec then
        local cfg = scene.S.RuntimeStatusConfig(scene.runtimeStatus, spec)
        return cfg and cfg.enabled == true
    end
    return scene.S.StatusSpecEnabled(scene.conf, spec)
end

local function SceneAuraLaneAvailable(scene, cfg, defaultMax)
    return scene.customRenderer
        and (scene.runtimeAuras and cfg.enabled == true or cfg.enabled ~= false)
        and (tonumber(cfg.max) or defaultMax or 0) > 0
end

local function SceneLayerOn(scene, key)
    return scene.layerAvailable[key] ~= false and scene.layerVisible[key] ~= false
end

local function SceneLayerAlpha(scene, key)
    if scene.layerAvailable[key] == false then return 0 end
    return scene.soloLayer and scene.soloLayer ~= key and 0.15 or 1
end

local function AuraPreviewAlpha(cfg)
    if type(cfg) ~= "table" then return 1 end
    if cfg.alpha ~= nil then return tonumber(cfg.alpha) or 1 end
    if cfg.behindBar == true then
        return math.max(0, math.min(1, (tonumber(cfg.behindBarAlpha) or 85) / 100))
    end
    return 1
end

local function ApplyPreviewIconZoom(texture, zoom, baseInset)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    baseInset = tonumber(baseInset) or 0
    local visible = (1 - (baseInset * 2)) * (100 / zoom)
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local AURA_PREVIEW_RAW_FIELDS = {
    "showCooldownSwipe", "cooldownSwipeReverse", "showCooldown", "showCooldownText", "showStacks", "showTooltip",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY", "cooldownDecimalSeconds",
    "stackSize", "stackAnchor", "stackX", "stackY", "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
}

local function OverlayRawAuraPreviewStyle(compiled, raw)
    if type(compiled) ~= "table" or type(raw) ~= "table" then return compiled end
    for i = 1, #AURA_PREVIEW_RAW_FIELDS do
        local key = AURA_PREVIEW_RAW_FIELDS[i]
        if raw[key] ~= nil then compiled[key] = raw[key] end
    end
    return compiled
end

local function PreviewIconScale(value)
    value = tonumber(value) or 100
    if value < 20 then value = 20 elseif value > 300 then value = 300 end
    return value / 100
end

local function BuildScene(box, reason)
    local S = box._msufGFRenderState
    local H, M, MSUF = S.H, S.M, S.MSUF
    local kind = H.CurrentScope()
    local conf = H.Conf(kind)
    local gf = MSUF and MSUF.GF
    local previewAnimation = MSUF and MSUF.PreviewAnimation
    local buildFrameState = previewAnimation and previewAnimation.BuildFrameState
        or _G.MSUF_BuildPreviewAnimationFrameState
    local animState = box._animationEnabled == true and type(buildFrameState) == "function"
        and buildFrameState(box, 1, kind, box._msufGFMenuPreviewAnimState or {}, box._animationElapsed)
    if animState then box._msufGFMenuPreviewAnimState = animState end
    local runtimeSpec = S.CompiledSpec(kind)
    -- Group cells mirror the player's current state (name, class, exact
    -- HP/power) so the preview matches the live group frame. Pull-based only:
    -- sampled during this refresh, stylized values back any missing field.
    local liveData = MSUF and MSUF.UFPreview and type(MSUF.UFPreview.LiveUnitData) == "function"
        and MSUF.UFPreview.LiveUnitData("player") or nil
    local scene = {
        S = S, box = box, reason = reason, H = H, M = M, MSUF = MSUF,
        mock = S.mock, kind = kind, label = H.PreviewScopeLabel(kind), conf = conf, gf = gf,
        previewAnimation = previewAnimation, animState = animState, liveData = liveData,
        hpPct = animState and math.max(0.02, math.min(0.98, tonumber(animState.hpPct) or 0.72)) or (liveData and liveData.hp) or 0.72,
        powerPct = animState and math.max(0, math.min(1, tonumber(animState.powerPct) or 0.70)) or (liveData and liveData.power) or 0.70,
        healPct = animState and math.max(0.01, math.min(0.24, tonumber(animState.healPct) or 0.12)) or 0.12,
        absorbPct = animState and math.max(0.01, math.min(0.24, tonumber(animState.absorbPct) or 0.08)) or 0.08,
        runtimeSpec = runtimeSpec,
        runtimeAuras = runtimeSpec and runtimeSpec.auras,
        runtimeText = runtimeSpec and runtimeSpec.text or {},
        runtimePower = runtimeSpec and runtimeSpec.power or {},
        runtimeHealth = runtimeSpec and runtimeSpec.health or {},
        runtimeBorder = runtimeSpec and runtimeSpec.border or {},
        runtimeTempMaxHealth = runtimeSpec and runtimeSpec.tempMaxHealth or {},
        runtimePrediction = runtimeSpec and runtimeSpec.prediction or {},
        runtimeStatus = runtimeSpec and runtimeSpec.status or {},
        focus = H.PreviewFocusForPage(S.ctx.key),
        layerVisible = type(M.gfPreviewLayerVisible) == "table" and M.gfPreviewLayerVisible or {},
        soloLayer = M.gfPreviewSoloLayer,
        textHandles = box._textHandles or {},
        previewRole = H.PreviewRole and H.PreviewRole(kind) or S.GF_PREVIEW_ROLE,
    }
    local rawAuras = conf.auras or {}
    local trackedRaw = RawTrackedBuffLane(scene, rawAuras.buff)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local runtimeAuraConfig
    if runtimeSpec and a3 and type(a3.ResolveAuraPreviewConfig) == "function" then
        local proxy = box._msufA3GroupPreviewConfigProxy or {}
        box._msufA3GroupPreviewConfigProxy = proxy
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = kind
        proxy.MSUFUnitKey = "player"
        proxy.MSUFSpec = runtimeSpec
        runtimeAuraConfig = a3.ResolveAuraPreviewConfig(proxy, "player")
    end
    scene.runtimeAuraConfig = runtimeAuraConfig
    local runtimeLanes = runtimeAuraConfig and runtimeAuraConfig.lanes
    scene.rawAuras = rawAuras
    scene.auraIconZoom = tonumber(rawAuras.iconZoom) or tonumber(scene.runtimeAuras and scene.runtimeAuras.iconZoom) or 100
    scene.buffCfg = runtimeLanes and runtimeLanes.buff or scene.runtimeAuras
        and S.CompiledAuraLane(scene.runtimeAuras, "buff", rawAuras.buff or {}) or rawAuras.buff or {}
    scene.trackedBuffCfg = runtimeLanes and runtimeLanes.trackedBuff or scene.runtimeAuras
        and S.CompiledAuraLane(scene.runtimeAuras, "trackedBuff", trackedRaw) or trackedRaw
    scene.debuffCfg = runtimeLanes and runtimeLanes.debuff or scene.runtimeAuras
        and S.CompiledAuraLane(scene.runtimeAuras, "debuff", rawAuras.debuff or {}) or rawAuras.debuff or {}
    scene.externalCfg = runtimeLanes and runtimeLanes.external or scene.runtimeAuras
        and S.CompiledAuraLane(scene.runtimeAuras, "external", rawAuras.externals or {}) or rawAuras.externals or {}
    if not runtimeLanes then
        OverlayRawAuraPreviewStyle(scene.buffCfg, rawAuras.buff)
        OverlayRawAuraPreviewStyle(scene.trackedBuffCfg, trackedRaw)
        OverlayRawAuraPreviewStyle(scene.debuffCfg, rawAuras.debuff)
        OverlayRawAuraPreviewStyle(scene.externalCfg, rawAuras.externals)
    end
    scene.statusSpec = S.CurrentStatusSpec()
    scene.selectedSpellCfg = S.CurrentSpellConfig(kind)
    -- The selected frame effect belongs to the selected spell, not to whichever
    -- preview handle happens to render it.  Runtime compilation can temporarily
    -- hand ownership back to the fallback handle across Edit Mode transitions.
    scene.selectedSpellEffect = scene.selectedSpellCfg and scene.selectedSpellCfg.frame
    local selectedEffectKind = type(scene.selectedSpellEffect) == "table"
        and tostring(scene.selectedSpellEffect.type or "none"):lower() or "none"
    scene.selectedSpellEffectAvailable = selectedEffectKind ~= "" and selectedEffectKind ~= "none"
    local _, selectedSpellSpecKey, selectedSpellAuraName = S.CurrentSpellInfo(kind)
    scene.selectedSpellSpecKey = selectedSpellSpecKey
    scene.selectedSpellAuraName = selectedSpellAuraName
    scene.previewAllSpecSpellIcons = S.PreviewAllSpecSpellIcons(kind) == true
    scene.rawSelectedPlaced = scene.selectedSpellCfg and scene.selectedSpellCfg.placed
    scene.selectedPlaced = S.CurrentSpellPlaced(kind)
    scene.selectedSpellPlacedEnabled = scene.selectedPlaced
        and (scene.selectedPlaced.type or "icon") ~= "none"
    scene.selectedSpellNeedsPlacementPreview = scene.selectedSpellCfg ~= nil and scene.rawSelectedPlaced == nil
    local exactSpellRoot = runtimeAuraConfig and runtimeAuraConfig.spellIndicators
    scene.runtimeSpellIndicators = exactSpellRoot or (runtimeSpec and runtimeSpec.spellIndicators)
    scene.spellIconZoom = tonumber(scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.iconZoom)
        or tonumber(conf.spellIndicators and conf.spellIndicators.iconZoom) or 100
    scene.spellIconScale = PreviewIconScale(conf.spellIndicators and conf.spellIndicators.iconScale)
    scene.runtimeSpellItems = exactSpellRoot and exactSpellRoot.slots
        or (scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.items)
    local previewSpellItems = box._msufGFPreviewSpellItemsScratch or {}
    box._msufGFPreviewSpellItemsScratch = previewSpellItems
    wipe(previewSpellItems)
    scene.previewSpellItems = previewSpellItems
    scene.runtimeSpellPlacedAvailable = false
    scene.runtimeSpellEffectAvailable = false
    if type(scene.runtimeSpellItems) == "table" then
        for i = 1, #scene.runtimeSpellItems do
            local item = scene.runtimeSpellItems[i]
            local exactSlot = item and item.spellIndicatorSlot == true
            local selectedItem = item and item.specKey == selectedSpellSpecKey and item.auraName == selectedSpellAuraName
            local placed = exactSlot and item or (item and item.placed)
            local placedType = placed and (exactSlot and placed.visual or placed.type) or "none"
            local placedShown = placed and placedType ~= "none" and item.hiddenVisual ~= true
            local effect = item and (exactSlot and item.frameEffect or item.frame) or nil
            local effectKind = type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
            local effectShown = effectKind ~= "" and effectKind ~= "none"
            -- Preview all spells mirrors the compiled runtime set instead of the
            -- one spec the editor happens to show: Multi-Spec compiles every
            -- tracked spec, and a spell whose indicator is a frame effect owns no
            -- placed icon yet still draws. Corner custom slots carry no specKey
            -- and stay out - they belong to Corner Indicators, not to this list.
            local previewAllItem = scene.previewAllSpecSpellIcons == true
                and not selectedItem and item ~= nil and item.specKey ~= nil
                and (placedShown or effectShown)
            if selectedItem then
                if placedShown then scene.previewSpellItems[#scene.previewSpellItems + 1] = item end
            elseif previewAllItem then
                scene.previewSpellItems[#scene.previewSpellItems + 1] = item
            end
            if selectedItem then
                if placedShown then scene.runtimeSpellPlacedAvailable = true end
                if effect ~= nil then
                    scene.selectedSpellEffect = effect
                    scene.selectedSpellEffectAvailable = effectShown
                end
                if effectShown then scene.runtimeSpellEffectAvailable = true end
            elseif previewAllItem then
                if placedShown then scene.runtimeSpellPlacedAvailable = true end
                if effectShown then scene.runtimeSpellEffectAvailable = true end
            end
        end
    end
    local statusAvailable = false
    for i = 1, #S.statusSpecs do
        local spec = S.statusSpecs[i]
        if S.StatusSpecInMode(spec, scene.statusSpec) and SceneStatusAvailable(scene, spec) then
            statusAvailable = true
            break
        end
    end
    local aurasEnabled, powerTextEnabled
    if scene.runtimeAuras then
        scene.customRenderer = scene.buffCfg.enabled == true
            or scene.trackedBuffCfg.enabled == true or scene.debuffCfg.enabled == true
            or scene.externalCfg.enabled == true
        aurasEnabled = scene.customRenderer or scene.runtimeAuras.enabled == true
    else
        scene.customRenderer = true
        aurasEnabled = rawAuras.enabled ~= false
    end
    if runtimeSpec then
        powerTextEnabled = runtimeSpec.showPowerText == true
    else
        powerTextEnabled = (gf and gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(kind, conf))
            or conf.showPowerText == true or conf.showPower == true
    end
    local customAuraText = SceneAuraLaneAvailable(scene, scene.buffCfg, 6)
        or SceneAuraLaneAvailable(scene, scene.trackedBuffCfg, 4)
        or SceneAuraLaneAvailable(scene, scene.debuffCfg, 6)
        or SceneAuraLaneAvailable(scene, scene.externalCfg, 2)
    local textAvailable
    if runtimeSpec then
        textAvailable = runtimeSpec.showName == true
            or runtimeSpec.showHealthText == true or powerTextEnabled == true
    else
        textAvailable = conf.showName ~= false or conf.showHPText ~= false or powerTextEnabled == true
    end
    local selectedSpellAvailable = conf.spellIndicators and conf.spellIndicators.enabled == true
        and (scene.selectedSpellPlacedEnabled or scene.selectedSpellNeedsPlacementPreview
            or scene.selectedSpellEffectAvailable)
    -- Same role-gated enablement the runtime uses: the layer is unavailable
    -- (not merely hidden) when the bar is off for the preview role.
    local powerAvailable
    if runtimeSpec then
        powerAvailable = scene.runtimePower and scene.runtimePower.enabled == true or false
    else
        powerAvailable = (tonumber(H.MockPowerHeight(kind, conf, 1, 1)) or 0) > 0
    end
    scene.layerAvailable = {
        guides = true, bounds = true,
        power = powerAvailable,
        portrait = kind == "party" and runtimeSpec and runtimeSpec.portrait
            and runtimeSpec.portrait.enabled == true or false,
        buff = SceneAuraLaneAvailable(scene, scene.buffCfg, 6),
        trackedBuff = SceneAuraLaneAvailable(scene, scene.trackedBuffCfg, 4),
        debuff = SceneAuraLaneAvailable(scene, scene.debuffCfg, 6),
        external = SceneAuraLaneAvailable(scene, scene.externalCfg, 2),
        status = statusAvailable,
        si = scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.enabled == true
            and (scene.runtimeSpellPlacedAvailable or scene.runtimeSpellEffectAvailable)
            or selectedSpellAvailable or false,
        auraText = aurasEnabled and customAuraText,
        text = textAvailable,
        dispelOverlay = runtimeSpec and runtimeSpec.group
            and runtimeSpec.group.dispelOverlayEnabled == true or false,
        dispelSymbol = runtimeSpec and runtimeSpec.dispelSymbol
            and runtimeSpec.dispelSymbol.enabled == true or false,
    }
    box._layerAvailable = scene.layerAvailable
    if scene.soloLayer and scene.layerAvailable[scene.soloLayer] == false then
        M.gfPreviewSoloLayer = nil
        scene.soloLayer = nil
    end
    return scene
end

local STATUS_TEXTURE_FALLBACKS = {
    raidMarker = { "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0, 0.25, 0, 0.25 },
    readyCheck = { "Interface\\RaidFrame\\ReadyCheck-Ready", 0, 1, 0, 1 },
    summon = { "Interface\\RaidFrame\\Raid-Icon-SummonPending", 0, 1, 0, 1 },
    incomingRes = { "Interface\\RaidFrame\\Raid-Icon-Rez", 0, 1, 0, 1 },
    pvp = { "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 1, 0, 1 },
    phase = { "Interface\\TargetingFrame\\UI-PhasingIcon", 0, 1, 0, 1 },
}

local function ResolveStatusPreviewTexture(scene, spec, runtimeCfg, iconType, variant)
    local customIcon = runtimeCfg and runtimeCfg.customIcon
    if (type(customIcon) ~= "string" or customIcon == "") and spec and spec.customIcon then
        customIcon = scene.conf[spec.customIcon]
    end
    if type(customIcon) == "string" and customIcon ~= "" then return customIcon, 0, 1, 0, 1 end
    local resolver = _G.MSUF_GetStatusIconTexture or (scene.gf and scene.gf.GetStatusIconTexture)
    if type(resolver) == "function" then
        local path, l, r, t, b = resolver("BLIZZARD", iconType, variant,
            scene.runtimeStatus and scene.runtimeStatus.useMidnight == true)
        if type(path) == "string" and path ~= "" then return path, l, r, t, b end
    end
    local fallback = STATUS_TEXTURE_FALLBACKS[iconType]
    if fallback then return fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] end
end

local TEXT_HANDLE_KEYS = {
    "name", "hpGroup", "hpLeft", "hpCenter", "hpRight",
    "powerGroup", "powerLeft", "powerCenter", "powerRight",
}
local TEXT_LEVEL_SPECS = {
    { "name", "nameLayer", "nameTextLayer", 5 },
    { "hpGroup", "healthLayer", "textLayer", 5 },
    { "hpLeft", "healthLayer", "textLayer", 5 },
    { "hpCenter", "healthLayer", "textLayer", 5 },
    { "hpRight", "healthLayer", "textLayer", 5 },
    { "powerGroup", "powerLayer", "powerTextLayer", 2 },
    { "powerLeft", "powerLayer", "powerTextLayer", 2 },
    { "powerCenter", "powerLayer", "powerTextLayer", 2 },
    { "powerRight", "powerLayer", "powerTextLayer", 2 },
}

local function PlaceTextHandles(scene)
    local box, mock, H = scene.box, scene.mock, scene.H
    local handles = scene.textHandles
    for i = 1, #TEXT_HANDLE_KEYS do handles[TEXT_HANDLE_KEYS[i]]._previewScale = scene.previewScale end
    -- Name is a natural-width FontString. Its actual region is the sole source
    -- for glyph, grab-handle and focus geometry.
    if not H.PlaceHandleAroundRegions(handles.name, mock, { mock._nameFS }, 3, "name") then handles.name:Hide() end
    local function PlaceGroup(groupKey, prefix, regions)
        if H.TextMovesTogether(scene.kind, prefix) then
            handles[prefix .. "Left"]:Hide()
            handles[prefix .. "Center"]:Hide()
            handles[prefix .. "Right"]:Hide()
            if not H.PlaceHandleAroundRegions(handles[groupKey], mock, regions, 3) then handles[groupKey]:Hide() end
        else
            handles[groupKey]:Hide()
            for i = 1, 3 do
                local key = prefix .. ({ "Left", "Center", "Right" })[i]
                if not H.PlaceHandleAroundRegions(handles[key], mock, { regions[i] }, 3) then handles[key]:Hide() end
            end
        end
    end
    PlaceGroup("hpGroup", "hp", { mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS })
    PlaceGroup("powerGroup", "power", { mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS })
    H.ApplyTextFocus(box, mock)
end

local function PreviewHostStrata(scene)
    local gf, kind, S = scene.gf, scene.kind, scene.S
    local live, fallback
    if gf and type(gf.ForEachFrame) == "function" then
        gf.ForEachFrame(function(frame, _, frameKind)
            if not (frame and frame.GetFrameStrata) then return false end
            local strata = frame:GetFrameStrata()
            if S.issecretvalue(strata) == true or not strata or strata == "" then return false end
            strata = S.NormalizeFrameStrata(strata, S.PREVIEW_UNITFRAME_STRATA)
            fallback = fallback or strata
            if frameKind == kind or frame._msufGFKind == kind then live = strata; return true end
            return false
        end, true)
    end
    live = S.NormalizeFrameStrata(live or fallback or S.PREVIEW_UNITFRAME_STRATA, S.PREVIEW_UNITFRAME_STRATA)
    if live == "AUTO" then live = S.PREVIEW_UNITFRAME_STRATA end
    local host = scene.mock.GetFrameStrata and scene.mock:GetFrameStrata()
    if S.issecretvalue(host) == true or not host or host == "" then
        host = scene.box.GetFrameStrata and scene.box:GetFrameStrata()
        if S.issecretvalue(host) == true or host == "" then host = nil end
    end
    return live, host
end

local function ApplyHandleStrata(scene, handle, value, live, host)
    local S = scene.S
    if handle and handle.SetFrameStrata and host then
        local current = handle.GetFrameStrata and handle:GetFrameStrata()
        if S.issecretvalue(current) == true or current ~= host then handle:SetFrameStrata(host) end
    end
    -- Legacy strata is deliberately ignored: the live runtime now keeps every
    -- layer-aware element on the owning frame's strata as well.
    return 0
end

local function SyncIconDetailLevels(layers, handle)
    if not (handle and handle.GetFrameLevel) then return end
    layers = layers or {}
    local baseLevel = handle:GetFrameLevel() or 0
    SetPreviewFrameLevel(handle._iconDurationLayer,
        baseLevel + (layers.AURA_DURATION_BAR_LEVEL_OFFSET or 2))
    SetPreviewFrameLevel(handle._iconSwipeLayer,
        baseLevel + (layers.AURA_COOLDOWN_LEVEL_OFFSET or 4))
    SetPreviewFrameLevel(handle._iconTextLayer,
        baseLevel + (layers.AURA_TEXT_LEVEL_OFFSET or 8))
end

local function FinalizeScene(scene)
    local S, box, mock = scene.S, scene.box, scene.mock
    local conf, runtimeText, runtimeStatus = scene.conf, scene.runtimeText, scene.runtimeStatus
    local baseLevel = mock.GetFrameLevel and mock:GetFrameLevel() or 1
    local function ElementLevel(layer, fallback, detail)
        return PreviewElementLevel(mock, S.Layers, layer, fallback, detail)
    end
    local function SelectedSpellEffectLevel(layer, priority)
        local level = ElementLevel(layer, 0, 11 - priority)
        local effect = scene.selectedSpellEffect
        if type(effect) == "table" and tostring(effect.type or "none"):lower() == "namecolor" then
            -- The shared renderer already places Name Overlay above its source.
            -- Preserve that one target floor when Group Preview rebases the
            -- selected effect into its private frame-level band.
            local nameOwner = mock._nameFS and mock._nameFS.GetParent and mock._nameFS:GetParent()
            local nameLevel = nameOwner and nameOwner.GetFrameLevel and tonumber(nameOwner:GetFrameLevel())
            if nameLevel ~= nil then level = max(level, nameLevel + 1) end
        end
        return level
    end
    PlaceTextHandles(scene)
    local liveStrata, hostStrata = PreviewHostStrata(scene)
    local auraHandles = {
        { S.buffHandle, scene.buffCfg, 5 },
        { S.trackedBuffHandle, scene.trackedBuffCfg, 9 },
        { S.debuffHandle, scene.debuffCfg, 6 },
        { S.externalHandle, scene.externalCfg, 7 },
    }
    for i = 1, #auraHandles do
        local item, handle = auraHandles[i], auraHandles[i][1]
        if handle then
            ApplyHandleStrata(scene, handle, "AUTO", liveStrata, hostStrata)
            local level = SetPreviewFrameLevel(handle, ElementLevel(item[2].layer, item[3], 0))
            for j = 1, #(handle._auraStyleOwners or {}) do
                local owner = handle._auraStyleOwners[j]
                if owner and owner.SetFrameLevel then SetPreviewFrameLevel(owner, level) end
            end
            SyncIconDetailLevels(S.Layers, handle)
        end
    end
    for i = 1, #S.statusHandles do
        local handle = S.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            local cfg = S.RuntimeStatusConfig(runtimeStatus, spec)
            SetPreviewFrameLevel(handle, ElementLevel(cfg and cfg.layer or spec and conf[spec.layer], spec and spec.defaultLayer or 7, 8))
        end
    end
    -- Dispel symbol row. Same foreground band as the aura handles so its Effect
    -- Layer slider is judgeable against them in the preview, mirroring the live
    -- DispelSensorFrameLevel (frame base + aura icon base + configured layer).
    -- Without this the handle kept its creation-time level and the slider looked
    -- dead in the preview while it worked on the real frame.
    local dispelSymbolCfg = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    if S.dispelSymbolHandle then
        ApplyHandleStrata(scene, S.dispelSymbolHandle, dispelSymbolCfg and dispelSymbolCfg.strata or "AUTO", liveStrata, hostStrata)
        SetPreviewFrameLevel(S.dispelSymbolHandle, ElementLevel(dispelSymbolCfg and dispelSymbolCfg.layer, 8, 8))
    end
    local rawIndicators = conf.spellIndicators or {}
    local runtimeIndicators = scene.runtimeSpellIndicators or {}
    local spellLayer = runtimeIndicators.layer ~= nil and runtimeIndicators.layer or rawIndicators.layer
    local spellStrata = runtimeIndicators.strata ~= nil and runtimeIndicators.strata or rawIndicators.strata
    local selected = scene.selectedSpellCfg
    ApplyHandleStrata(scene, S.spellHandle, "AUTO", liveStrata, hostStrata)
    SetPreviewFrameLevel(S.spellHandle, ElementLevel(selected and selected.layer or spellLayer, 9, 1))
    SyncIconDetailLevels(S.Layers, S.spellHandle)
    local selectedEffectOwner = box._msufGFSelectedSpellEffectOwner
    local selectedEffectRoot = selectedEffectOwner and selectedEffectOwner._msufSpellPreviewEffectRoot
    if selectedEffectRoot and selectedEffectRoot.IsShown and selectedEffectRoot:IsShown() then
        local priority = max(1, min(10, floor((tonumber(selectedEffectRoot._msufSpellPreviewPriority) or 5) + 0.5)))
        local effectLayer = S.ClampLayer(selectedEffectRoot._msufSpellPreviewLayer, 0)
        -- Only one selected full-frame effect is rendered. Its configured live
        -- strata must not be translated relative to an Edit Mode preview frame:
        -- that live frame can remain on a higher strata during teardown and
        -- produce a negative local offset below the menu mock. Keep the preview
        -- root on the host strata and express priority in a bounded local band.
        ApplyHandleStrata(scene, selectedEffectRoot, "AUTO", liveStrata, hostStrata)
        SetPreviewFrameLevel(selectedEffectRoot, SelectedSpellEffectLevel(effectLayer, priority))
    end
    if selectedEffectOwner then
        SetPreviewFrameLevel(selectedEffectOwner, baseLevel + 1)
    end
    local selectedIconEffectRoot = S.spellHandle._msufSpellPreviewIconEffectRoot
    if selectedIconEffectRoot and selectedIconEffectRoot.IsShown and selectedIconEffectRoot:IsShown() then
        ApplyHandleStrata(scene, selectedIconEffectRoot,
            selected and selected.strata or spellStrata, liveStrata, hostStrata)
        SetPreviewFrameLevel(selectedIconEffectRoot, S.spellHandle:GetFrameLevel() + 4)
    end
    for _, handle in pairs(scene.dynamicSpellHandlesActive or {}) do
        ApplyHandleStrata(scene, handle, "AUTO", liveStrata, hostStrata)
        SetPreviewFrameLevel(handle, ElementLevel(handle._msufSpellIndicatorLayer or spellLayer, 9, 1))
        SyncIconDetailLevels(S.Layers, handle)
        local effectRoot = handle._msufSpellPreviewEffectRoot
        if effectRoot and effectRoot.IsShown and effectRoot:IsShown() then
            local priority = max(1, min(10, floor((tonumber(effectRoot._msufSpellPreviewPriority) or 5) + 0.5)))
            local effectLayer = S.ClampLayer(effectRoot._msufSpellPreviewLayer, 0)
            ApplyHandleStrata(scene, effectRoot, "AUTO", liveStrata, hostStrata)
            SetPreviewFrameLevel(effectRoot, ElementLevel(effectLayer, 0, 11 - priority))
        end
        local iconEffectRoot = handle._msufSpellPreviewIconEffectRoot
        if iconEffectRoot and iconEffectRoot.IsShown and iconEffectRoot:IsShown() then
            ApplyHandleStrata(scene, iconEffectRoot,
                handle._msufSpellIndicatorStrata or spellStrata, liveStrata, hostStrata)
            SetPreviewFrameLevel(iconEffectRoot, handle:GetFrameLevel() + 4)
        end
    end
    for i = 1, #TEXT_LEVEL_SPECS do
        local item = TEXT_LEVEL_SPECS[i]
        SetPreviewFrameLevel(scene.textHandles[item[1]], ElementLevel(runtimeText[item[2]] or conf[item[3]], item[4], 8))
    end
    local auraKeys = { "buff", "trackedBuff", "debuff", "external" }
    for i = 1, #auraHandles do
        local handle, cfg, key = auraHandles[i][1], auraHandles[i][2], auraKeys[i]
        if handle then
            handle:SetShown(scene.layerAvailable[key] and SceneLayerOn(scene, key))
            handle:SetAlpha(SceneLayerAlpha(scene, key) * AuraPreviewAlpha(cfg))
        end
    end
    for i = 1, #S.statusHandles do
        local handle = S.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            handle:SetShown(S.StatusSpecInMode(spec, scene.statusSpec)
                and SceneStatusAvailable(scene, spec) and SceneLayerOn(scene, "status"))
            handle:SetAlpha(SceneLayerAlpha(scene, "status"))
        end
    end
    local spellVisible = scene.layerAvailable.si and SceneLayerOn(scene, "si")
    if selectedEffectOwner then
        selectedEffectOwner:SetShown(spellVisible and scene.selectedSpellEffectAvailable == true)
    end
    S.spellHandle:SetShown(spellVisible)
    S.spellHandle:SetAlpha(selected and selected.enabled == false and SceneLayerAlpha(scene, "si") * 0.45
        or SceneLayerAlpha(scene, "si"))
    for _, handle in pairs(scene.dynamicSpellHandlesActive or {}) do
        handle:SetShown(spellVisible)
        handle:SetAlpha(SceneLayerAlpha(scene, "si"))
    end
    for i = 1, #TEXT_HANDLE_KEYS do scene.textHandles[TEXT_HANDLE_KEYS[i]]:SetAlpha(SceneLayerAlpha(scene, "text")) end
    local rangeAlpha = tonumber(box._msuf2RangeFadePreviewAlpha)
    if rangeAlpha ~= nil then rangeAlpha = max(0, min(1, rangeAlpha)) end
    local rangeHealthOnly = rangeAlpha ~= nil and box._msuf2RangeFadePreviewLayerMode == "health"
    local wholeFrameMul = rangeAlpha ~= nil and not rangeHealthOnly and rangeAlpha or 1
    local healthMul = rangeHealthOnly and rangeAlpha or 1
    if mock.SetAlpha then mock:SetAlpha(wholeFrameMul) end
    if mock._health and mock._health.SetAlpha then mock._health:SetAlpha(healthMul) end
    if mock._healPred and mock._healPred.SetAlpha then mock._healPred:SetAlpha(healthMul) end
    if mock._absorb and mock._absorb.SetAlpha then mock._absorb:SetAlpha(healthMul) end
    for i = 1, #(box._handleList or {}) do
        local handle = box._handleList[i]
        if handle and handle.SetAlpha and handle.GetParent and handle:GetParent() ~= mock then
            handle:SetAlpha((handle.GetAlpha and handle:GetAlpha() or 1) * wholeFrameMul)
        end
    end
    local visibleLayerButtonCount = 0
    for i = 1, #box._layerButtons do
        local button = box._layerButtons[i]
        local visible = button._layerKey ~= "portrait" or scene.kind == "party"
        if button.SetShown then button:SetShown(visible) end
        if visible then visibleLayerButtonCount = visibleLayerButtonCount + 1 end
        local available = scene.layerAvailable[button._layerKey] ~= false
        button._layerAvailable = available
        if button.Refresh then button:Refresh() end
    end
    box._visibleLayerButtonCount = visibleLayerButtonCount
    if box._selectedHandle and box._selectedHandle.IsShown and not box._selectedHandle:IsShown() then S.SelectHandle(nil) end
    S.RefreshHandleSelection(box)
end

--- Installs the group preview renderer into the preview host. Native.lua owns
--- frame creation and input handles; this function owns repeated composition
--- from compiled group specs, visible layers, zoom state, and selected handles.
local function RenderAuras(scene)
    local S, self, mock = scene.S, scene.box, scene.mock
    local H, gf, kind, conf = scene.H, scene.gf, scene.kind, scene.conf
    local runtimeAuras = scene.runtimeAuras
    local buffCfg, trackedBuffCfg, debuffCfg, externalCfg = scene.buffCfg, scene.trackedBuffCfg, scene.debuffCfg, scene.externalCfg
    local buffHandle, trackedBuffHandle, debuffHandle, externalHandle = S.buffHandle, S.trackedBuffHandle, S.debuffHandle, S.externalHandle
    local GF_PREVIEW_ANCHOR_FRAC, GF_AURA_MOCK_ICON_IDS = S.GF_PREVIEW_ANCHOR_FRAC, S.GF_AURA_MOCK_ICON_IDS
    local Int, Round, ScaleValue, ConfigToOffset = S.Int, S.Round, S.ScaleValue, S.ConfigToOffset
    local AuraGrowth, AddIconPool, MockSpellTexture = S.AuraGrowth, S.AddIconPool, S.MockSpellTexture
    local floor, max, min = S.floor, S.max, S.min
    local previewScale, previewAnimation = scene.previewScale, scene.previewAnimation
    local SetPreviewFont = scene.SetPreviewFont
    local function LayoutHandle(handle, anchor, x, y, defaultAnchor)
        anchor = anchor or defaultAnchor or "CENTER"
        if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaultAnchor or "CENTER" end
        handle._previewScale = previewScale
        handle._previewWriteScale = previewScale
        handle:ClearAllPoints()
        handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))
    end
    local auraDynamicScale = (runtimeAuras and runtimeAuras.dynamicScaleValue) or (gf and gf.GetPreviewDynamicScale and gf.GetPreviewDynamicScale(conf, kind)) or 1
    local function RuntimeAuraGrowth(growth)
        if growth == "LEFTUP" then
            return -1, 1, false, "BOTTOMRIGHT"
        elseif growth == "LEFTDOWN" then
            return -1, -1, false, "TOPRIGHT"
        elseif growth == "RIGHTUP" then
            return 1, 1, false, "BOTTOMLEFT"
        elseif growth == "UP" or growth == "UPRIGHT" or growth == "UPLEFT" then
            return 1, 1, true, "BOTTOMLEFT"
        elseif growth == "DOWN" or growth == "DOWNRIGHT" or growth == "DOWNLEFT" then
            return 1, -1, true, "TOPLEFT"
        end
        return 1, -1, false, "TOPLEFT"
    end
    local function RuntimeAuraAnchor(anchor, fallback)
        anchor = tostring(anchor or ""):upper()
        if GF_PREVIEW_ANCHOR_FRAC[anchor] then return anchor end
        fallback = tostring(fallback or "CENTER"):upper()
        return GF_PREVIEW_ANCHOR_FRAC[fallback] and fallback or "CENTER"
    end
    local function RuntimeAuraTextAnchor(anchor, fallback)
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT"
            or anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT"
            or anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            return anchor
        end
        return fallback or "CENTER"
    end
    local function NormalizeDispelBorderMode(value, legacyEnabled)
        if value == true then return "SYMBOL" end
        if value == false then return "OFF" end
        value = tostring(value or ""):upper()
        if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
        if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
            or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
            return "SYMBOL"
        end
        if value == "OFF" or value == "NONE" or value == "DISABLED" then return legacyEnabled == true and "SYMBOL" or "OFF" end
        return legacyEnabled == true and "SYMBOL" or "OFF"
    end
    local function PlaceAuraPreviewText(fs, relativeTo, anchor, x, y)
        if not (fs and relativeTo) then return end
        anchor = RuntimeAuraTextAnchor(anchor, "CENTER")
        fs:ClearAllPoints()
        fs:SetPoint(anchor, relativeTo, anchor, x or 0, y or 0)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            fs:SetJustifyH("LEFT")
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            fs:SetJustifyH("RIGHT")
        else
            fs:SetJustifyH("CENTER")
        end
        if fs.SetJustifyV then
            if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
                fs:SetJustifyV("TOP")
            elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                fs:SetJustifyV("BOTTOM")
            else
                fs:SetJustifyV("MIDDLE")
            end
        end
    end
    local function LayoutAuraPreviewBorder(border, icon, size, mode, shape, index)
        local atlas = DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[mode]
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.ApplyAuraDispelPreview) == "function"
            and a3.ApplyAuraDispelPreview(border, icon, size, mode, shape,
                a3.PreviewDispelTypeForIndex(index)) then
            return
        end
        if not (border and icon and atlas and border.SetAtlas) then
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
    local function PreviewAuraState(groupKey, index, handle, cfg)
        if not (self._animationEnabled == true and handle) then return nil end
        local buildAuraState = previewAnimation and previewAnimation.BuildAuraState or _G.MSUF_BuildPreviewAnimationAuraState
        if type(buildAuraState) ~= "function" then return nil end
        handle._previewAuraStates = handle._previewAuraStates or {}
        local scratch = handle._previewAuraStates[index] or {}
        handle._previewAuraStates[index] = scratch
        return buildAuraState(groupKey, index, scratch, {
            decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3,
        }, self._animationElapsed)
    end
    local function LayoutAuraPreviewSwipe(swipe, icon, size, remainingFrac, reverse)
        if not (swipe and icon) then return end
        remainingFrac = max(0.08, min(0.92, tonumber(remainingFrac) or 0.48))
        local w = max(1, floor((tonumber(size) or 1) * remainingFrac + 0.5))
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
    local function LayoutAuraDurationBar(bar, icon, cfg, size, auraState)
        if not (bar and icon and cfg and cfg.showDurationBar == true) then
            if bar then bar:Hide() end
            return
        end
        size = max(1, tonumber(size) or 1)
        local height = max(1, min(size, floor((tonumber(cfg.durationBarHeight) or 2) + 0.5)))
        local inset = max(1, floor(size / 32 + 0.5))
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
            bar:SetWidth(max(1, floor(max(1, size - inset * 2) * frac + 0.5)))
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
    local function RuntimeAuraGridShape(count, perRow, verticalGrowth)
        count = max(Round(count), 1)
        perRow = max(Round(perRow), 1)
        if verticalGrowth == true then
            return 1, count
        end
        local cols = min(count, perRow)
        return cols, math.ceil(count / perRow)
    end
    local function LayoutAuraGroup(handle, groupKey, cfg, defaults)
        cfg = cfg or {}
        defaults = defaults or {}
        local runtimeLane = cfg._msufA3LayoutSignature ~= nil
            and cfg.initialAnchor ~= nil and cfg.xSign ~= nil and cfg.ySign ~= nil
        local maxIcons = Int(cfg.max, defaults.max or 6, 0, 40)
        local perRow = Int(cfg.perRow, defaults.perRow or maxIcons, 1, 40)
        local rawSize = cfg.size or defaults.size or 16
        local compiledLane = runtimeLane or cfg._compiled == true
        if not compiledLane then rawSize = rawSize * PreviewIconScale(cfg.iconScale) end
        local minSize = (compiledLane or cfg.iconScale ~= nil) and 1 or (defaults.minSize or 8)
        local laneScale = compiledLane and previewScale or (previewScale * auraDynamicScale)
        local size = max(minSize, ScaleValue(rawSize, laneScale, minSize))
        local spacing = max(0, ScaleValue(cfg.spacing or defaults.spacing or 1, previewScale, 0))
        local anchor = RuntimeAuraAnchor(cfg.anchor, defaults.anchor or "CENTER")
        if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaults.anchor or "CENTER" end
        if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = "CENTER" end
        local textScale = compiledLane and previewScale or laneScale
        local showCooldown
        if runtimeLane then showCooldown = cfg.showCooldownText == true
        else showCooldown = cfg.showCooldown ~= false end
        local showStacks = cfg.showStacks ~= false
        local showSwipe = cfg.showCooldownSwipe ~= false
        local barOnly = cfg.showDurationBar == true and (cfg.durationBarDisplay or "BAR_ONLY") == "BAR_ONLY"
        local cooldownSwipeReverse = cfg.cooldownSwipeReverse == true
        local cooldownSize = max(6, ScaleValue(cfg.cooldownSize or defaults.cooldownSize or 8, textScale, 6))
        local stackSize = max(6, ScaleValue(cfg.stackSize or defaults.stackSize or 10, textScale, 6))
        local cooldownAnchor = RuntimeAuraTextAnchor(cfg.cooldownAnchor, "CENTER")
        local stackAnchor = RuntimeAuraTextAnchor(cfg.stackAnchor, "BOTTOMRIGHT")
        local cooldownX = ConfigToOffset(cfg.cooldownX or 0, textScale)
        local cooldownY = ConfigToOffset(cfg.cooldownY or 0, textScale)
        local stackX = ConfigToOffset(cfg.stackX or 0, textScale)
        local stackY = ConfigToOffset(cfg.stackY or 0, textScale)
        local dispelMode = groupKey == "debuff" and NormalizeDispelBorderMode(cfg.dispelBorderMode, cfg.showDispelBorder == true or cfg.showDispelSymbol == true) or "OFF"
        local growth = cfg.growth or defaults.growth or "RIGHTDOWN"
        local gv = AuraGrowth(growth)
        local centered = runtimeLane ~= true and gv.centered == true
        local anchorTarget = mock
        local anchorFrac = GF_PREVIEW_ANCHOR_FRAC[anchor] or GF_PREVIEW_ANCHOR_FRAC.CENTER
        local ids = GF_AURA_MOCK_ICON_IDS[groupKey] or GF_AURA_MOCK_ICON_IDS.debuff
        local step = size + spacing
        AddIconPool(handle, maxIcons)
        handle._previewRects = handle._previewRects or {}
        local handleW, handleH, originX, originY
        if centered then
            local minL, minB, maxR, maxT
            for i = 1, maxIcons do
                local left, bottom
                local totalPrimary = maxIcons * size + max(0, maxIcons - 1) * spacing
                local halfOfs = totalPrimary * 0.5
                local col = i - 1
                if gv.px ~= 0 then
                    local cx = col * step - halfOfs + size * 0.5
                    left, bottom = cx - size * 0.5, -size * 0.5
                else
                    local cy = -(col * step - halfOfs) - size * 0.5
                    left, bottom = -size * 0.5, cy - size * 0.5
                end
                local right, top = left + size, bottom + size
                local rect = handle._previewRects[i] or {}
                rect[1], rect[2], rect.anchor = left, bottom, nil
                handle._previewRects[i] = rect
                minL = minL and min(minL, left) or left
                minB = minB and min(minB, bottom) or bottom
                maxR = maxR and max(maxR, right) or right
                maxT = maxT and max(maxT, top) or top
            end
            if not minL then minL, minB, maxR, maxT = -size * 0.5, -size * 0.5, size * 0.5, size * 0.5 end
            handleW = max(1, Round(maxR - minL))
            handleH = max(1, Round(maxT - minB))
            originX, originY = -minL, -minB
        else
            local xSign, ySign, verticalGrowth, initialAnchor
            if runtimeLane then
                xSign = tonumber(cfg.xSign) or 1
                ySign = tonumber(cfg.ySign) or -1
                verticalGrowth = cfg.verticalGrowth == true
                initialAnchor = cfg.initialAnchor
            else
                xSign, ySign, verticalGrowth, initialAnchor = RuntimeAuraGrowth(growth)
            end
            local cols, rows
            if runtimeLane then
                cols = max(1, tonumber(cfg.cols) or 1)
                rows = max(1, tonumber(cfg.rows) or 1)
            else
                cols, rows = RuntimeAuraGridShape(maxIcons, perRow, verticalGrowth)
            end
            handleW = max(1, Round(cols * size + max(cols - 1, 0) * spacing))
            handleH = max(1, Round(rows * size + max(rows - 1, 0) * spacing))
            originX = Round(anchorFrac[1] * handleW)
            originY = Round(anchorFrac[2] * handleH)
            for i = 1, maxIcons do
                local idx = i - 1
                local col, row
                if verticalGrowth == true then
                    col, row = 0, idx
                else
                    col = idx % perRow
                    row = (idx - col) / perRow
                end
                local rect = handle._previewRects[i] or {}
                rect[1], rect[2], rect.anchor = col * step * xSign, row * step * ySign, initialAnchor
                handle._previewRects[i] = rect
            end
        end
        handle:SetSize(handleW, handleH)
        handle._previewOriginX = originX
        handle._previewOriginY = originY
        handle._previewAnchorFrame = anchorTarget
        handle._previewScale = previewScale
        handle._previewWriteScale = compiledLane and (previewScale * max(0.0001, auraDynamicScale)) or previewScale
        handle:ClearAllPoints()
        if centered then
            handle:SetPoint(
                "BOTTOMLEFT",
                anchorTarget,
                "CENTER",
                ConfigToOffset(cfg.x or 0, previewScale) - originX,
                ConfigToOffset(cfg.y or 0, previewScale) - originY
            )
        else
            handle:SetPoint(
                anchor,
                anchorTarget,
                anchor,
                ConfigToOffset(cfg.x or 0, previewScale),
                ConfigToOffset(cfg.y or 0, previewScale)
            )
        end
        for i = 1, maxIcons do
            local tex = handle._icons and handle._icons[i]
            local swipe = handle._iconSwipes and handle._iconSwipes[i]
            local border = handle._iconBorders and handle._iconBorders[i]
            local stack = handle._iconStacks and handle._iconStacks[i]
            local timer = handle._iconTimers and handle._iconTimers[i]
            local durationBar = handle._iconDurationBars and handle._iconDurationBars[i]
            local rect = handle._previewRects[i]
            if tex and rect then
                local styleOwner
                if runtimeLane then
                    handle._auraStyleOwners = handle._auraStyleOwners or {}
                    styleOwner = handle._auraStyleOwners[i]
                    if not styleOwner then
                        styleOwner = CreateFrame("Frame", nil, handle)
                        styleOwner:EnableMouse(false)
                        if styleOwner.SetMouseMotionEnabled then styleOwner:SetMouseMotionEnabled(false) end
                        handle._auraStyleOwners[i] = styleOwner
                    end
                end
                local auraState = PreviewAuraState(groupKey, i, handle, cfg)
                tex:SetTexture(MockSpellTexture(ids[((i - 1) % #ids) + 1]))
                ApplyPreviewIconZoom(tex, cfg.iconZoom or scene.auraIconZoom, 0)
                if tex.SetAlpha then tex:SetAlpha(barOnly and 0 or 1) end
                tex:SetSize(size, size)
                tex:ClearAllPoints()
                if rect.anchor then
                    tex:SetPoint(rect.anchor, handle, rect.anchor, rect[1], rect[2])
                else
                    tex:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", rect[1] + originX, rect[2] + originY)
                end
                if styleOwner then
                    styleOwner:ClearAllPoints()
                    styleOwner:SetAllPoints(tex)
                    if styleOwner.SetFrameLevel and handle.GetFrameLevel then
                        SetPreviewFrameLevel(styleOwner, handle:GetFrameLevel() or 0)
                    end
                    local a3 = MSUF and MSUF.MSUF_Auras3
                    if a3 and type(a3.ApplyAuraIconShape) == "function" then
                        a3.ApplyAuraIconShape(styleOwner, cfg.iconShape, nil, tex, swipe)
                    end
                    if a3 and type(a3.ApplyIconStylePreview) == "function" then
                        a3.ApplyIconStylePreview(styleOwner, barOnly and nil or cfg.iconStyle, size, cfg.iconShape)
                    end
                    styleOwner:Show()
                end
                if swipe then
                    if showSwipe and not barOnly then
                        LayoutAuraPreviewSwipe(swipe, tex, size, auraState and auraState.remainingFrac, cooldownSwipeReverse)
                        swipe:Show()
                    else
                        swipe:Hide()
                    end
                end
                LayoutAuraPreviewBorder(border, tex, size, barOnly and "OFF" or dispelMode, cfg.iconShape, i)
                LayoutAuraDurationBar(durationBar, tex, cfg, size, auraState)
                if stack then
                    SetPreviewFont(stack, stackSize)
                    stack:SetTextColor(1, 1, 1, 1)
                    PlaceAuraPreviewText(stack, tex, stackAnchor, stackX, stackY)
                    stack:SetText(showStacks and (auraState and auraState.stacks or (i % 3 == 1 and "2" or "")) or "")
                    stack:SetShown(showStacks)
                end
                if timer then
                    SetPreviewFont(timer, cooldownSize)
                    timer:SetTextColor(1, 1, 1, 1)
                    PlaceAuraPreviewText(timer, tex, cooldownAnchor, cooldownX, cooldownY)
                    timer:SetText(showCooldown and (auraState and auraState.text or (i % 2 == 0 and "12" or "")) or "")
                    timer:SetShown(showCooldown)
                end
                tex:Show()
            end
        end
        for i = maxIcons + 1, #(handle._icons or {}) do
            if handle._icons[i] then handle._icons[i]:Hide() end
            if handle._iconSwipes and handle._iconSwipes[i] then handle._iconSwipes[i]:Hide() end
            if handle._iconBorders and handle._iconBorders[i] then handle._iconBorders[i]:Hide() end
            if handle._iconStacks and handle._iconStacks[i] then handle._iconStacks[i]:Hide() end
            if handle._iconTimers and handle._iconTimers[i] then handle._iconTimers[i]:Hide() end
            if handle._iconDurationBars and handle._iconDurationBars[i] then handle._iconDurationBars[i]:Hide() end
            if handle._auraStyleOwners and handle._auraStyleOwners[i] then
                local a3 = MSUF and MSUF.MSUF_Auras3
                if a3 and type(a3.ApplyIconStylePreview) == "function" then
                    a3.ApplyIconStylePreview(handle._auraStyleOwners[i], nil)
                end
                handle._auraStyleOwners[i]:Hide()
            end
        end
        return size
    end
    LayoutAuraGroup(buffHandle, "buff", buffCfg, {
        anchor = "BOTTOMRIGHT", growth = "LEFTUP",
        size = 22, perRow = 4, max = 6, spacing = 1, minSize = 8,
    })
    if trackedBuffHandle then
        LayoutAuraGroup(trackedBuffHandle, "trackedBuff", trackedBuffCfg, {
            anchor = "TOPLEFT", growth = "RIGHTDOWN",
            size = 22, perRow = 4, max = 4, spacing = 1, minSize = 8,
        })
    end
    LayoutAuraGroup(debuffHandle, "debuff", debuffCfg, {
        anchor = "TOPLEFT", growth = "RIGHTDOWN",
        size = 20, perRow = 3, max = 6, spacing = 1, minSize = 8,
    })
    if externalHandle then
        LayoutAuraGroup(externalHandle, "external", externalCfg, {
            anchor = "CENTER", growth = "RIGHTDOWN",
            size = 28, perRow = 3, max = 2, spacing = 1, minSize = 8,
        })
    end
    scene.LayoutHandle = LayoutHandle
    scene.PlaceAuraPreviewText = PlaceAuraPreviewText
    scene.RuntimeAuraTextAnchor = RuntimeAuraTextAnchor
    scene.LayoutAuraPreviewSwipe = LayoutAuraPreviewSwipe
    scene.LayoutAuraDurationBar = LayoutAuraDurationBar
end

Render.Components = { Plan = BuildScene, Auras = RenderAuras, Finalize = FinalizeScene }
Render.ComponentOrder = { "Plan", "FrameAndText", "Auras", "Indicators", "Finalize" }

function Render.Install(box, ctx, deps)
    if not box then return end
    deps = deps or {}
    local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
    local H = deps.H or {}
    local M = deps.M or _G.MSUF2 or {}
    local MSUF = deps.MSUF or MSUF or {}
    local T = deps.T or M.Theme or {}
    local width = tonumber(deps.width) or 720
    local mock = deps.mock or box._mock
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local GF_PREVIEW_NAMES = deps.NAMES or {}
    local GF_PREVIEW_CLASSES = deps.CLASSES or {}
    local GF_AURA_MOCK_ICON_IDS = deps.AURA_MOCK_ICON_IDS or {}
    local GF_PREVIEW_MIN_W = tonumber(deps.MIN_W) or 380
    local GF_PREVIEW_MIN_H = tonumber(deps.MIN_H) or 130
    local GF_PREVIEW_ROLE = deps.ROLE or "HEALER"
    local GF_PREVIEW_ANCHOR_FRAC = deps.ANCHOR_FRAC or {}
    local buffHandle = deps.buffHandle
    local trackedBuffHandle = deps.trackedBuffHandle
    local debuffHandle = deps.debuffHandle
    local externalHandle = deps.externalHandle
    local powerBarHandle = deps.powerBarHandle
    local portraitHandle = deps.portraitHandle
    local dispelSymbolHandle = deps.dispelSymbolHandle
    local statusHandles = deps.statusHandles or {}
    local spellHandle = deps.spellHandle
    local selectedSpellEffectOwner = box._msufGFSelectedSpellEffectOwner
    if not selectedSpellEffectOwner then
        selectedSpellEffectOwner = CreateFrame("Frame", nil, mock)
        selectedSpellEffectOwner:EnableMouse(false)
        selectedSpellEffectOwner:SetAllPoints(mock)
        box._msufGFSelectedSpellEffectOwner = selectedSpellEffectOwner
    end
    local statusSpecs = deps.statusSpecs or {}
    local CompiledSpec, CompiledAuraLane, RuntimeStatusConfig, CurrentStatusSpec, StatusSpecEnabled, StatusSpecInMode, StatusSpecIsText, StatusText, StatusLabel, CurrentSpellInfo, PreviewAllSpecSpellIcons, CurrentSpellConfig, CurrentSpellPlaced, CurrentSpellTexture, CurrentSpellColor, MockSpellTexture = M.PickFallbacks(deps, GROUP_RENDER_FALLBACKS, [[
        CompiledSpec CompiledAuraLane RuntimeStatusConfig CurrentStatusSpec StatusSpecEnabled StatusSpecInMode StatusSpecIsText StatusText StatusLabel CurrentSpellInfo PreviewAllSpecSpellIcons CurrentSpellConfig CurrentSpellPlaced CurrentSpellTexture CurrentSpellColor MockSpellTexture
    ]])
    local Int, Round, ClampZoom, ResolveDefaultZoomLock, UpdateZoomControls, AuraGrowth, ApplyRounded, ClampLayer, ClassColor, HealthColor, SelectHandle, NudgeHandlePosition, AddIconPool, RefreshHandleSelection = M.PickFallbacks(deps, GROUP_RENDER_FALLBACKS, [[
        Int Round ClampZoom ResolveDefaultZoomLock UpdateZoomControls AuraGrowth ApplyRounded ClampLayer ClassColor HealthColor SelectHandle NudgeHandlePosition AddIconPool RefreshHandleSelection
    ]])
    local ScaleValue = deps.ScaleValue or function(value, scale, minValue)
        local v = Round((tonumber(value) or 0) * (tonumber(scale) or 1))
        if minValue ~= nil and v < minValue then v = minValue end
        return v
    end
    local ApplyFrameBorder = deps.ApplyFrameBorder or F.Noop
    local ApplyBoundsGuide = deps.ApplyBoundsGuide or F.Noop
    local ConfigToOffset = deps.ConfigToOffset or function(value, scale) return Round((tonumber(value) or 0) * (tonumber(scale) or 1)) end
    local ResolvePreviewStatusbarTexture = deps.ResolveStatusbarTexture or function() return WHITE8X8 end
    box._msufGFRenderState = {
        floor = floor,
        max = max,
        min = min,
        ceil = ceil,
        H = H,
        M = M,
        MSUF = MSUF,
        T = T,
        ctx = ctx,
        width = width,
        mock = mock,
        WHITE8X8 = WHITE8X8,
        GF_PREVIEW_NAMES = GF_PREVIEW_NAMES,
        GF_PREVIEW_CLASSES = GF_PREVIEW_CLASSES,
        GF_AURA_MOCK_ICON_IDS = GF_AURA_MOCK_ICON_IDS,
        GF_PREVIEW_MIN_W = GF_PREVIEW_MIN_W,
        GF_PREVIEW_MIN_H = GF_PREVIEW_MIN_H,
        GF_PREVIEW_ROLE = GF_PREVIEW_ROLE,
        GF_PREVIEW_ANCHOR_FRAC = GF_PREVIEW_ANCHOR_FRAC,
        buffHandle = buffHandle,
        trackedBuffHandle = trackedBuffHandle,
        debuffHandle = debuffHandle,
        externalHandle = externalHandle,
        powerBarHandle = powerBarHandle,
        portraitHandle = portraitHandle,
        dispelSymbolHandle = dispelSymbolHandle,
        statusHandles = statusHandles,
        spellHandle = spellHandle,
        statusSpecs = statusSpecs,
        CompiledSpec = CompiledSpec,
        CompiledAuraLane = CompiledAuraLane,
        RuntimeStatusConfig = RuntimeStatusConfig,
        CurrentStatusSpec = CurrentStatusSpec,
        CurrentSpellInfo = CurrentSpellInfo,
        PreviewAllSpecSpellIcons = PreviewAllSpecSpellIcons,
        StatusSpecEnabled = StatusSpecEnabled,
        StatusSpecInMode = StatusSpecInMode,
        StatusSpecIsText = StatusSpecIsText,
        StatusText = StatusText,
        StatusLabel = StatusLabel,
        CurrentSpellConfig = CurrentSpellConfig,
        CurrentSpellPlaced = CurrentSpellPlaced,
        CurrentSpellTexture = CurrentSpellTexture,
        CurrentSpellColor = CurrentSpellColor,
        MockSpellTexture = MockSpellTexture,
        Int = Int,
        Round = Round,
        ClampZoom = ClampZoom,
        ResolveDefaultZoomLock = ResolveDefaultZoomLock,
        UpdateZoomControls = UpdateZoomControls,
        AuraGrowth = AuraGrowth,
        ApplyRounded = ApplyRounded,
        ClampLayer = ClampLayer,
        ClassColor = ClassColor,
        HealthColor = HealthColor,
        AddIconPool = AddIconPool,
        SelectHandle = SelectHandle,
        NudgeHandlePosition = NudgeHandlePosition,
        RefreshHandleSelection = RefreshHandleSelection,
        ScaleValue = ScaleValue,
        ApplyFrameBorder = ApplyFrameBorder,
        ApplyBoundsGuide = ApplyBoundsGuide,
        ConfigToOffset = ConfigToOffset,
        ResolvePreviewStatusbarTexture = ResolvePreviewStatusbarTexture,
        DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = DEBUFF_TYPE_BORDER_PREVIEW_ATLAS,
        PREVIEW_UNITFRAME_STRATA = PREVIEW_UNITFRAME_STRATA,
        NormalizeFrameStrata = NormalizeFrameStrata,
        FrameStrataRank = FrameStrataRank,
        Layers = Layers,
        issecretvalue = issecretvalue,
    }
    local function SuspendSpellPreviewRoot(root)
        if not root then return end
        local pulse = root._msufSpellPreviewPulse
        if pulse and pulse.IsPlaying and pulse:IsPlaying() then pulse:Stop() end
        local glow = root._msufSpellPreviewGlow
        if glow then
            if glow.animation and glow.animation.IsPlaying and glow.animation:IsPlaying() then glow.animation:Stop() end
            if glow.halo then glow.halo:Hide() end
            if glow.ants then glow.ants:Hide() end
        end
        root:Hide()
    end
    local function SuspendRuntimeSpellPreview(handle)
        local owner = handle and handle._msufSpellPreviewRuntimeOwner
        local a3 = MSUF and MSUF.MSUF_Auras3
        local runtime = a3 and a3.SpellIndicators
        if owner and runtime and type(runtime.HidePreviewFrameEffect) == "function" then
            runtime.HidePreviewFrameEffect(owner)
        end
    end
    function box:SuspendSpellPreviewEffects()
        for _, handle in pairs(self._spellIndicatorHandles or {}) do
            SuspendRuntimeSpellPreview(handle)
            SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewEffectRoot)
            SuspendSpellPreviewRoot(handle and handle._msufSpellPreviewIconEffectRoot)
        end
        SuspendRuntimeSpellPreview(spellHandle)
        SuspendSpellPreviewRoot(spellHandle and spellHandle._msufSpellPreviewEffectRoot)
        SuspendSpellPreviewRoot(spellHandle and spellHandle._msufSpellPreviewIconEffectRoot)
        SuspendRuntimeSpellPreview(selectedSpellEffectOwner)
        SuspendSpellPreviewRoot(selectedSpellEffectOwner and selectedSpellEffectOwner._msufSpellPreviewEffectRoot)
    end
    --- Refresh is menu-only. It reads compiled/runtime-like specs to draw a mock
    --- group frame and must not rebuild secure headers or subscribe to roster
    --- events.
    function box:Refresh(reason)
        if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then
            self._msufGFRefreshAfterCombat = reason or self._msufGFRefreshAfterCombat or true
            return
        end
        if self._msufGFTextDragActive and reason ~= "GROUP_PREVIEW_TEXT_DRAG" and reason ~= "GROUP_PREVIEW_TEXT_DRAG_END" then
            self._msufGFRefreshReason = reason or self._msufGFRefreshReason
            return
        end
        -- Rebase the cached preview into a deterministic local level band before
        -- reading or painting any scene state. Ancestor level changes are not a
        -- render input and must never leak into configured layer calculations.
        local previewRootLevel = SafePreviewFrameLevel(self.GetFrameLevel and self:GetFrameLevel() or 0)
        SetPreviewFrameLevel(self._stage, previewRootLevel + 2)
        SetPreviewFrameLevel(self._layers, previewRootLevel + 3)
        SetPreviewFrameLevel(mock, previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
        -- One constant translation preserves the exact live ElementLevel order
        -- while keeping every preview visual above the raised mock body.
        mock._msufPreviewElementLevelBias = mock.GetFrameLevel and (mock:GetFrameLevel() or 0)
            or (previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
        if self._dragFrame then
            SetPreviewFrameLevel(self._dragFrame, PreviewInteractionLevel(mock, Layers, 2))
        end
        local scene = BuildScene(self, reason)
        local S = scene.S
        if self.RefreshRoleButton then self:RefreshRoleButton(scene.kind) end
        local textHandles, kind, label, conf, gf = scene.textHandles, scene.kind, scene.label, scene.conf, scene.gf
        local previewAnimation, hpPct, powerPct, healPct, absorbPct = scene.previewAnimation,
            scene.hpPct, scene.powerPct, scene.healPct, scene.absorbPct
        local runtimeSpec, runtimeAuras = scene.runtimeSpec, scene.runtimeAuras
        local runtimeText, runtimePower, runtimeHealth = scene.runtimeText, scene.runtimePower, scene.runtimeHealth
        local runtimeBorder, runtimeTempMaxHealth, runtimePrediction, runtimeStatus = scene.runtimeBorder,
            scene.runtimeTempMaxHealth, scene.runtimePrediction, scene.runtimeStatus
        local focus, layerVisible, soloLayer, layerAvailable = scene.focus, scene.layerVisible, scene.soloLayer, scene.layerAvailable
        local buffCfg, trackedBuffCfg, debuffCfg, externalCfg = scene.buffCfg, scene.trackedBuffCfg, scene.debuffCfg, scene.externalCfg
        local statusSpec, selectedSpellCfg, selectedPlaced = scene.statusSpec, scene.selectedSpellCfg, scene.selectedPlaced
        local selectedSpellEffect = scene.selectedSpellEffect
        local selectedSpellNeedsPlacementPreview = scene.selectedSpellNeedsPlacementPreview
        local runtimeSpellIndicators, runtimeSpellItems = scene.runtimeSpellIndicators, scene.previewSpellItems
        local function StatusConfigAvailable(spec) return SceneStatusAvailable(scene, spec) end
        local function LayerOn(key) return SceneLayerOn(scene, key) end
        local function LayerAlpha(key) return SceneLayerAlpha(scene, key) end
        local function ResolveStatusTexture(spec, runtimeCfg, iconType, variant)
            return ResolveStatusPreviewTexture(scene, spec, runtimeCfg, iconType, variant)
        end
        local function StopPreviewAnimation(group)
            if group and group.IsPlaying and group:IsPlaying() then group:Stop() end
        end
        local function HidePreviewGlow(root)
            local glow = root and root._msufSpellPreviewGlow
            if not glow then return end
            StopPreviewAnimation(glow.animation)
            glow.halo:Hide()
            glow.ants:Hide()
        end
        local function EnsurePreviewGlow(root)
            local glow = root and root._msufSpellPreviewGlow
            if glow then return glow end
            glow = {}
            glow.halo = root:CreateTexture(nil, "OVERLAY", nil, 6)
            glow.halo:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
            glow.halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
            glow.halo:SetBlendMode("ADD")
            glow.ants = root:CreateTexture(nil, "OVERLAY", nil, 7)
            glow.ants:SetTexture([[Interface\SpellActivationOverlay\IconAlertAnts]])
            glow.ants:SetBlendMode("ADD")
            glow.animation = glow.ants:CreateAnimationGroup()
            if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(glow.animation) end
            glow.animation:SetLooping("REPEAT")
            local flipbook = glow.animation:CreateAnimation("FlipBook")
            flipbook:SetFlipBookRows(5)
            flipbook:SetFlipBookColumns(5)
            flipbook:SetFlipBookFrames(22)
            flipbook:SetFlipBookFrameWidth(48)
            flipbook:SetFlipBookFrameHeight(48)
            flipbook:SetDuration(0.37)
            root._msufSpellPreviewGlow = glow
            return glow
        end
        local function ShowPreviewGlow(root, target, r, g, b, a, padding)
            local glow = EnsurePreviewGlow(root)
            if not (glow and target) then return end
            local haloPadding = padding * 1.55
            glow.halo:ClearAllPoints()
            glow.halo:SetPoint("TOPLEFT", target, "TOPLEFT", -haloPadding, haloPadding)
            glow.halo:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", haloPadding, -haloPadding)
            glow.ants:ClearAllPoints()
            glow.ants:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
            glow.ants:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
            glow.halo:SetDesaturated(true)
            glow.ants:SetDesaturated(true)
            glow.halo:SetVertexColor(r, g, b, a)
            glow.ants:SetVertexColor(r, g, b, a)
            glow.halo:Show()
            glow.ants:Show()
            if not glow.animation:IsPlaying() then glow.animation:Play() end
        end
        local function SpellPreviewHealthBar()
            return mock._health
        end
        local function SpellPreviewHealthFill()
            local health = SpellPreviewHealthBar()
            return health and health.GetStatusBarTexture and health:GetStatusBarTexture() or nil
        end
        local function EnsureSpellEffectPreview(handle)
            local root = handle and handle._msufSpellPreviewEffectRoot
            if root then return root end
            root = CreateFrame("Frame", nil, handle)
            root:EnableMouse(false)
            root:SetAllPoints(SpellPreviewHealthBar())
            handle._msufSpellPreviewEffectRoot = root
            return root
        end
        local function EnsureSpellEffectRuntimeOwner(handle)
            if not handle then return nil end
            local owner = handle._msufSpellPreviewRuntimeOwner
            if not owner then
                owner = CreateFrame("Frame", nil, mock)
                owner:EnableMouse(false)
                handle._msufSpellPreviewRuntimeOwner = owner
            elseif owner.GetParent and owner:GetParent() ~= mock and owner.SetParent then
                owner:SetParent(mock)
            end
            owner:ClearAllPoints()
            owner:SetAllPoints(mock)
            return owner
        end
        local function HideSpellEffectPreview(handle)
            local a3 = MSUF and MSUF.MSUF_Auras3
            local runtime = a3 and a3.SpellIndicators
            local owner = handle and handle._msufSpellPreviewRuntimeOwner
            if owner and runtime and type(runtime.HidePreviewFrameEffect) == "function" then
                runtime.HidePreviewFrameEffect(owner)
            end
            local root = handle and handle._msufSpellPreviewEffectRoot
            if not root then return end
            StopPreviewAnimation(root._msufSpellPreviewPulse)
            root:SetAlpha(1)
            HidePreviewGlow(root)
            root:Hide()
        end
        local function EnsureSpellPreviewEdges(root)
            if root._msufSpellPreviewEdges then return root._msufSpellPreviewEdges end
            local edges = {}
            for i = 1, 4 do
                edges[i] = root:CreateTexture(nil, "OVERLAY")
                edges[i]:SetTexture(WHITE8X8)
                edges[i]:Hide()
            end
            root._msufSpellPreviewEdges = edges
            return edges
        end
        local function HideSpellPreviewRegions(root)
            if root._msufSpellPreviewTint then root._msufSpellPreviewTint:Hide() end
            if root._msufSpellPreviewName then root._msufSpellPreviewName:Hide() end
            local edges = root._msufSpellPreviewEdges
            for i = 1, type(edges) == "table" and #edges or 0 do edges[i]:Hide() end
            SetRoundedSpellPreview(root, nil, false)
            StopPreviewAnimation(root._msufSpellPreviewPulse)
            root:SetAlpha(1)
            HidePreviewGlow(root)
        end
        local function SyncSpellPreviewName(root, source, r, g, b, a)
            if not source then return end
            local overlay = root._msufSpellPreviewName
            if not overlay then
                overlay = root:CreateFontString(nil, "OVERLAY")
                root._msufSpellPreviewName = overlay
            end
            local path, size, flags = source:GetFont()
            if path and size then overlay:SetFont(path, size, flags) end
            if source.GetJustifyH then overlay:SetJustifyH(source:GetJustifyH()) end
            if source.GetJustifyV then overlay:SetJustifyV(source:GetJustifyV()) end
            if source.GetShadowColor then overlay:SetShadowColor(source:GetShadowColor()) end
            if source.GetShadowOffset then overlay:SetShadowOffset(source:GetShadowOffset()) end
            overlay:ClearAllPoints()
            overlay:SetAllPoints(source)
            overlay:SetText(source:GetText())
            overlay:SetTextColor(r, g, b, a)
            overlay:SetShown(source.IsShown == nil or source:IsShown())
        end
        local function LayoutSpellPreviewEdges(root, target, effect, r, g, b, a)
            local edges = EnsureSpellPreviewEdges(root)
            local glowLike = effect.type == "glow" or effect.type == "pulse"
            local rawThickness = tonumber(effect.thickness) or (effect.type == "glow" and 3 or 2)
            local thickness = max(1, ScaleValue(glowLike and max(rawThickness, 3) or rawThickness, mock._previewScale or 1, 1))
            if glowLike then a = min(1, a * 0.85) end
            local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
            top:ClearAllPoints()
            top:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
            top:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness)
            top:SetHeight(thickness)
            bottom:ClearAllPoints()
            bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
            bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness)
            bottom:SetHeight(thickness)
            left:ClearAllPoints()
            left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
            left:SetWidth(thickness)
            right:ClearAllPoints()
            right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
            right:SetWidth(thickness)
            for i = 1, 4 do
                if edges[i].SetBlendMode then edges[i]:SetBlendMode(glowLike and "ADD" or "BLEND") end
                edges[i]:SetVertexColor(r, g, b, a)
                edges[i]:Show()
            end
            if not glowLike and SetRoundedSpellPreview(root, target, true, thickness, r, g, b, a, "BLEND") then
                for i = 1, 4 do edges[i]:Hide() end
            elseif effect.type == "pulse"
                and SetRoundedSpellPreview(root, target, true, thickness, r, g, b, a, "ADD") then
                for i = 1, 4 do edges[i]:Hide() end
            end
        end
        local function ApplySpellEffectPreview(handle, effect)
            if not (handle and type(effect) == "table") then return end
            local a3 = MSUF and MSUF.MSUF_Auras3
            local runtime = a3 and a3.SpellIndicators
            if runtime and type(runtime.ApplyPreviewFrameEffect) == "function" then
                -- The Group mock predates the runtime-shaped health/name keys.
                -- Publish the exact native surfaces expected by the shared
                -- renderer; otherwise it rejects the preview and the legacy
                -- stretched action-button glow below silently takes over.
                mock.health = mock._health
                mock.Name = mock._nameFS
                local owner = EnsureSpellEffectRuntimeOwner(handle)
                local legacyRoot = handle._msufSpellPreviewEffectRoot
                local existingRuntimeRoot = owner and owner._msufA3SpellIndicatorEffectRoot
                if legacyRoot and legacyRoot ~= existingRuntimeRoot then legacyRoot:Hide() end
                local previewEffect = owner and (owner._msufSpellPreviewRuntimeEffect or {})
                if owner then owner._msufSpellPreviewRuntimeEffect = previewEffect end
                if previewEffect then
                    local kind = tostring(effect.type or "none"):lower()
                    previewEffect.type = effect.type
                    previewEffect.color = effect.color
                    previewEffect.priority = effect.priority
                    previewEffect.thickness = max(1, ScaleValue(effect.thickness
                        or (kind == "glow" and 3 or 2), mock._previewScale or 1, 1))
                    previewEffect.layer = effect.layer
                    previewEffect.strata = effect.strata or handle._msufSpellIndicatorStrata
                    previewEffect.tintAlpha = effect.tintAlpha
                    if runtime.ApplyPreviewFrameEffect(owner, previewEffect, mock) then
                        local runtimeRoot = owner._msufA3SpellIndicatorEffectRoot
                        if runtimeRoot then
                            -- FinalizeScene rebases this established preview
                            -- field into the local layer band after painting.
                            handle._msufSpellPreviewEffectRoot = runtimeRoot
                            runtimeRoot._msufSpellPreviewStrata = previewEffect.strata
                            runtimeRoot._msufSpellPreviewPriority = max(1,
                                min(10, floor((tonumber(previewEffect.priority) or 5) + 0.5)))
                            runtimeRoot._msufSpellPreviewLayer = S.ClampLayer(previewEffect.layer, 0)
                            return
                        end
                    end
                end
                -- Runtime is authoritative when present. Never paint the old
                -- square IconAlert fallback after a rejected runtime apply.
                HideSpellEffectPreview(handle)
                return
            end
            local root = EnsureSpellEffectPreview(handle)
            local healthBar = SpellPreviewHealthBar()
            local target = SpellPreviewHealthFill()
            if not (root and healthBar and target) then
                HideSpellEffectPreview(handle)
                return
            end
            HideSpellPreviewRegions(root)
            root:ClearAllPoints()
            root:SetAllPoints(healthBar)
            root._msufSpellPreviewStrata = effect.strata or handle._msufSpellIndicatorStrata
            root._msufSpellPreviewPriority = max(1, min(10, floor((tonumber(effect.priority) or 5) + 0.5)))
            root._msufSpellPreviewLayer = S.ClampLayer(effect.layer, 0)
            local color = effect.color or {}
            local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
            local a = color[4] or 1
            local kind = tostring(effect.type or "none"):lower()
            if kind == "healthtint" then
                local tint = root._msufSpellPreviewTint
                if not tint then
                    tint = root:CreateTexture(nil, "OVERLAY")
                    tint:SetTexture(WHITE8X8)
                    root._msufSpellPreviewTint = tint
                end
                tint:ClearAllPoints()
                tint:SetAllPoints(target)
                tint:SetBlendMode("BLEND")
                local tintAlpha = tonumber(effect.tintAlpha or effect.alpha)
                if tintAlpha == nil then tintAlpha = a > 0 and a or 0.20 end
                tint:SetVertexColor(r, g, b, max(0, min(1, tintAlpha)))
                tint:Show()
            elseif kind == "namecolor" then
                SyncSpellPreviewName(root, mock._nameFS, r, g, b, a)
            elseif kind == "glow" then
                local padding = max(1,
                    ScaleValue((tonumber(effect.thickness) or 3) + 2, mock._previewScale or 1, 1))
                ShowPreviewGlow(root, target, r, g, b, a, padding)
            elseif kind == "border" or kind == "pulse" then
                LayoutSpellPreviewEdges(root, target, effect, r, g, b, a)
                if kind == "pulse" then
                    local pulse = root._msufSpellPreviewPulse
                    if not pulse then
                        pulse = root:CreateAnimationGroup()
                        if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(pulse) end
                        local alpha = pulse:CreateAnimation("Alpha")
                        alpha:SetFromAlpha(0.45)
                        alpha:SetToAlpha(1)
                        alpha:SetDuration(0.7)
                        if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
                        pulse:SetLooping("BOUNCE")
                        root._msufSpellPreviewPulse = pulse
                    end
                    if not pulse:IsPlaying() then pulse:Play() end
                end
            else
                HideSpellEffectPreview(handle)
                return
            end
            root:Show()
        end
        self._title:SetText(string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s", (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", label))
        local stageW = self._stage:GetWidth() or (width - 98)
        local stageH = self._stage:GetHeight() or 218
        if stageW <= 1 then stageW = math.max(260, width - 98) end
        if stageH <= 1 then stageH = 218 end
        local liveW, liveH, frameScale = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width) or 120,
            tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height) or 40,
            1
        if gf and gf.GetScaledFrameMetrics then
            local w2, h2, _, sc2 = gf.GetScaledFrameMetrics(kind)
            liveW = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(w2) or liveW
            liveH = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(h2) or liveH
            frameScale = tonumber(sc2) or 1
        end
        liveW, liveH = max(1, liveW), max(1, liveH)
        local autoZoom = min(self._msufGFRenderState.GF_PREVIEW_MIN_W / liveW, self._msufGFRenderState.GF_PREVIEW_MIN_H / liveH)
        autoZoom = max(1.4, min(2.8, autoZoom))
        ResolveDefaultZoomLock(self, autoZoom)
        local manualZoom = tonumber(self._manualZoom)
        local frozenZoom = tonumber(self._dragFrozenScale)
        local previewScale = manualZoom and ClampZoom(manualZoom) or (frozenZoom and ClampZoom(frozenZoom) or autoZoom)
        self._mockAutoScale = autoZoom
        self._mockScale = previewScale
        UpdateZoomControls(self)
        local mockW = max(48, Round(liveW * previewScale))
        local mockH = max(20, Round(liveH * previewScale))
        local powerH = runtimePower and runtimePower.enabled == true and ScaleValue(runtimePower.height, previewScale, 0) or 0
        if not runtimeSpec then powerH = H.MockPowerHeight(kind, conf, previewScale, frameScale) end
        -- Runtime parity for Power.Apply's three placements: embedded (inside the
        -- frame bottom), attached-below (embed off), and detached (free geometry).
        -- Only the embedded bar insets the health bar (Health.Layout contract).
        local powerEmbed, powerDetached
        if runtimeSpec then
            powerEmbed = runtimePower.embed ~= false
            powerDetached = runtimePower.detached == true
        else
            powerEmbed = conf.embedPowerBarIntoHealth ~= false
            powerDetached = conf.powerBarDetached == true
        end
        local powerInsetH = (powerH > 0 and powerEmbed and not powerDetached) and powerH or 0
        local borderEnabled = runtimeSpec and (runtimeBorder.enabled ~= false) or (not runtimeSpec and conf.borderEnabled ~= false)
        local outline = borderEnabled and (tonumber(runtimeBorder and runtimeBorder.thickness) or 1) or 0
        if not runtimeSpec and borderEnabled and gf and gf.GetBarOutlineThickness then outline = tonumber(gf.GetBarOutlineThickness(kind)) or outline end
        local outlineEdge = max(0, Round(outline * previewScale))
        local powerOutline = 0
        if runtimePower then
            if runtimePower.borderEnabled == true then powerOutline = tonumber(runtimePower.borderThickness) or 1 end
        elseif conf.powerBarBorderEnabled == true then
            powerOutline = tonumber(conf.powerBarBorderThickness) or 1
        end
        local powerOutlineEdge = max(0, Round(powerOutline * previewScale))
        local inset = 0
        local startX = Round((stageW - mockW) * 0.5)
        local startY = -Round((stageH - mockH) * 0.5)
        local mock = self._mock
        mock._previewScale = previewScale
        self._mockBaseOffsetX, self._mockBaseOffsetY = startX, startY
        mock:ClearAllPoints()
        mock:SetPoint("TOPLEFT", self._stage, "TOPLEFT", startX + (tonumber(self._zoomPanX) or 0), startY + (tonumber(self._zoomPanY) or 0))
        mock:SetSize(mockW, mockH)
        mock:SetBackdrop({ bgFile = WHITE8X8 })
        local bgAlpha = conf.hpBgAlpha or 0.85
        if runtimeSpec and runtimeSpec.backgroundAlpha ~= nil then bgAlpha = runtimeSpec.backgroundAlpha end
        mock:SetBackdropColor(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09, bgAlpha)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        local cls = (scene.liveData and scene.liveData.class)
            or self._msufGFRenderState.GF_PREVIEW_CLASSES[((kind == "party" and 5 or 2) % #self._msufGFRenderState.GF_PREVIEW_CLASSES) + 1]
        local br, bg, bb = runtimeBorder.r or conf.borderR or 0, runtimeBorder.g or conf.borderG or 0, runtimeBorder.b or conf.borderB or 0
        mock._msufGFPreviewBorderR = br
        mock._msufGFPreviewBorderG = bg
        mock._msufGFPreviewBorderB = bb
        mock._msufGFPreviewBorderA = borderEnabled and (runtimeBorder.a or conf.borderA or 1) or 0
        mock._msufGFPreviewPowerBorderR = runtimePower and runtimePower.borderR or br
        mock._msufGFPreviewPowerBorderG = runtimePower and runtimePower.borderG or bg
        mock._msufGFPreviewPowerBorderB = runtimePower and runtimePower.borderB or bb
        mock._msufGFPreviewPowerBorderA = runtimePower and runtimePower.borderA or mock._msufGFPreviewBorderA
        local barTex = runtimeHealth.texture or (runtimeSpec and runtimeSpec.texture) or (gf and gf.ResolveBarTexture and gf.ResolveBarTexture(kind)) or ResolvePreviewStatusbarTexture(conf, "barTexture")
        local bgTex = runtimeHealth.backgroundTexture or (runtimeSpec and runtimeSpec.backgroundTexture) or (gf and gf.ResolveBarBgTexture and gf.ResolveBarBgTexture(kind)) or WHITE8X8
        mock._health:SetStatusBarTexture(barTex)
        mock._health:ClearAllPoints()
        mock._health:SetPoint("TOPLEFT", mock, "TOPLEFT", inset, -inset)
        mock._health:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, powerInsetH > 0 and (powerInsetH + inset) or inset)
        local runtimeHealthMode = runtimeHealth and runtimeHealth.mode
        local hr, hg, hb
        if runtimeHealthMode == "dark" or runtimeHealthMode == "unified" or runtimeHealthMode == "custom" then
            hr, hg, hb = runtimeHealth.r, runtimeHealth.g, runtimeHealth.b
        end
        if not hr then hr, hg, hb = HealthColor(conf, hpPct or 0.72, cls) end
        local groupVisual = (runtimeSpec and runtimeSpec.group) or {}
        -- Live parity: the engine dims the fill texture (Elements_Alpha), never
        -- the status-bar color's alpha channel, which the client drops on refill.
        local hpFillAlpha = tonumber(groupVisual.hpBarAlpha) or tonumber(conf.hpBarAlpha) or 1
        mock._health:SetStatusBarColor(hr, hg, hb)
        if mock._health.SetMinMaxValues then mock._health:SetMinMaxValues(0, 1) end
        mock._health:SetValue(hpPct)
        local hpReverse = runtimeHealth.reverse == true or (not runtimeSpec and conf.reverseFill == true)
        if mock._health.SetReverseFill then mock._health:SetReverseFill(hpReverse) end
        if MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.ApplyBarGradient then
            MSUF.UFBarTextCommon.ApplyBarGradient(mock, mock._health,
                runtimeHealth.barGradient, "_msufGFPreviewHealthGradients")
        end
        mock._healthBg:SetTexture(bgTex)
        local hbCfg = runtimeHealth.background or {}
        local hbr, hbg, hbb = hbCfg.r or conf.bgR or 0.06, hbCfg.g or conf.bgG or 0.06, hbCfg.b or conf.bgB or 0.07
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        if runtimeHealth.backgroundMatchHealth == true then hbr, hbg, hbb = hr or hbr, hg or hbg, hb or hbb end
        if runtimeHealth.backgroundClassColor == true or (not runtimeSpec and gen and gen.barBgClassColor) then
            hbr, hbg, hbb = ClassColor(cls, hbr, hbg, hbb)
        end
        mock._healthBg:SetVertexColor(hbr, hbg, hbb, hbCfg.a or groupVisual.hpBgAlpha or conf.hpBgAlpha or 0.85)
        local tempMaxShown
        if runtimeSpec then
            tempMaxShown = runtimeTempMaxHealth.enabled == true
        else
            local enabled = gen and gen.tempMaxHealthEnabled
            if conf.hlOverride == true and conf.tempMaxHealthEnabled ~= nil then enabled = conf.tempMaxHealthEnabled end
            tempMaxShown = enabled == true
            if _G.MSUF_ShouldShowAbsorbTextureTest
                and _G.MSUF_ShouldShowAbsorbTextureTest(nil, kind, "tempMaxHealth") then
                tempMaxShown = true
            end
        end
        mock._tempMaxHealth:ClearAllPoints()
        mock._tempMaxHealth:SetAllPoints(mock._health)
        mock._tempMaxHealth:SetStatusBarTexture(runtimeTempMaxHealth.texture or barTex)
        mock._tempMaxHealth:SetStatusBarColor(
            runtimeTempMaxHealth.r or (gen and gen.tempMaxHealthColorR) or 0.70,
            runtimeTempMaxHealth.g or (gen and gen.tempMaxHealthColorG) or 0.10,
            runtimeTempMaxHealth.b or (gen and gen.tempMaxHealthColorB) or 0.10,
            runtimeTempMaxHealth.a or (gen and gen.tempMaxHealthOpacity) or 1)
        if mock._tempMaxHealth.SetReverseFill then mock._tempMaxHealth:SetReverseFill(not hpReverse) end
        mock._tempMaxHealth:SetValue(0.20)
        mock._tempMaxHealthBg:ClearAllPoints()
        local tempMaxFill = mock._tempMaxHealth.GetStatusBarTexture
            and mock._tempMaxHealth:GetStatusBarTexture()
        mock._tempMaxHealthBg:SetAllPoints(tempMaxFill or mock._tempMaxHealth)
        mock._tempMaxHealthBg:SetColorTexture(0, 0, 0,
            runtimeTempMaxHealth.backgroundAlpha or (gen and gen.tempMaxHealthBackgroundOpacity) or 0.65)
        mock._tempMaxHealth:SetShown(tempMaxShown)
        local hpTex = mock._health.GetStatusBarTexture and mock._health:GetStatusBarTexture()
        if hpTex and hpTex.SetAlpha then hpTex:SetAlpha(hpFillAlpha) end
        local healPredMode = tonumber(runtimePrediction.healAnchorMode) or H.HealPredAnchorMode(conf)
        local healPredShown
        if runtimeSpec then
            healPredShown = runtimePrediction.heal == true
        else
            healPredShown = H.HealPredictionEnabled(kind, conf)
        end
        mock._healPred:SetStatusBarTexture(runtimePrediction.texture or barTex)
        mock._healPred:SetStatusBarColor(
            runtimePrediction.healR or (gen and gen.healPredictionColorR) or 0,
            runtimePrediction.healG or (gen and gen.healPredictionColorG) or 1,
            runtimePrediction.healB or (gen and gen.healPredictionColorB) or 0,
            (runtimePrediction.healA or (gen and gen.healPredictionColorA) or 0.45) * hpFillAlpha
        )
        mock._healPred:ClearAllPoints()
        if (healPredMode == 3 or healPredMode == 4) and hpTex then
            if hpReverse then
                mock._healPred:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
                mock._healPred:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
                if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill(true) end
            else
                mock._healPred:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
                mock._healPred:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
                if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill(false) end
            end
            mock._healPred:SetWidth(max(1, mockW * healPct))
            mock._healPred:SetValue(1)
        else
            mock._healPred:SetAllPoints(mock._health)
            if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill((healPredMode == 1) and false or ((healPredMode == 5) and not hpReverse or true)) end
            mock._healPred:SetValue(healPct)
        end
        mock._healPred:SetShown(healPredShown)
        mock._absorb:ClearAllPoints()
        mock._absorb:SetStatusBarTexture(runtimePrediction.absorbTexture or runtimePrediction.texture or barTex)
        mock._absorb:SetStatusBarColor(
            runtimePrediction.absorbR or (gen and gen.absorbBarColorR) or 1,
            runtimePrediction.absorbG or (gen and gen.absorbBarColorG) or 1,
            runtimePrediction.absorbB or (gen and gen.absorbBarColorB) or 1,
            (runtimePrediction.absorbA or (gen and gen.absorbBarOpacity) or (gen and gen.absorbBarColorA) or 0.75) * hpFillAlpha
        )
        local absorbMode = tonumber(runtimePrediction.absorbAnchorMode) or tonumber((conf.hlOverride and conf.absorbAnchorMode ~= nil and conf.absorbAnchorMode) or (gen and gen.absorbAnchorMode)) or 2
        if absorbMode < 1 or absorbMode > 5 then absorbMode = 2 end
        local absorbShown
        if runtimeSpec then
            absorbShown = runtimePrediction.absorb == true
        else
            local enableAbsorbBar = (conf.hlOverride and conf.enableAbsorbBar ~= nil) and conf.enableAbsorbBar or (gen and gen.enableAbsorbBar)
            if enableAbsorbBar ~= nil then
                absorbShown = enableAbsorbBar ~= false
            else
                local displayMode = (conf.hlOverride and conf.absorbTextMode ~= nil) and conf.absorbTextMode or (gen and gen.absorbTextMode)
                displayMode = tonumber(displayMode)
                absorbShown = displayMode == nil or displayMode == 2 or displayMode == 3
            end
        end
        local absorbAnchorTex = hpTex or mock._health
        if healPredShown and (healPredMode == 3 or healPredMode == 4) and mock._healPred.GetStatusBarTexture then absorbAnchorTex = mock._healPred:GetStatusBarTexture() or absorbAnchorTex end
        local absorbFollows = (absorbMode == 3 or absorbMode == 4) and absorbAnchorTex
        if absorbFollows then
            if hpReverse then
                mock._absorb:SetPoint("TOPRIGHT", absorbAnchorTex, "TOPLEFT", 0, 0)
                mock._absorb:SetPoint("BOTTOMRIGHT", absorbAnchorTex, "BOTTOMLEFT", 0, 0)
                if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill(true) end
            else
                mock._absorb:SetPoint("TOPLEFT", absorbAnchorTex, "TOPRIGHT", 0, 0)
                mock._absorb:SetPoint("BOTTOMLEFT", absorbAnchorTex, "BOTTOMRIGHT", 0, 0)
                if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill(false) end
            end
        else
            mock._absorb:SetAllPoints(mock._health)
            if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill((absorbMode == 1) and false or ((absorbMode == 5) and not hpReverse or true)) end
        end
        if absorbFollows then mock._absorb:SetWidth(max(1, mockW * absorbPct)) end
        mock._absorb:SetValue(absorbFollows and 1 or absorbPct)
        mock._absorb:SetShown(absorbShown)
        local healAbsorbShown
        if runtimeSpec then
            healAbsorbShown = runtimePrediction.healAbsorb == true
        else
            local enabled = gen and gen.healAbsorbEnabled
            if conf.hlOverride == true and conf.healAbsorbEnabled ~= nil then enabled = conf.healAbsorbEnabled end
            healAbsorbShown = enabled ~= false
        end
        mock._healAbsorb:ClearAllPoints()
        mock._healAbsorb:SetStatusBarTexture(runtimePrediction.healAbsorbTexture or barTex)
        mock._healAbsorb:SetStatusBarColor(
            runtimePrediction.healAbsorbR or (gen and gen.healAbsorbBarColorR) or 0.7,
            runtimePrediction.healAbsorbG or (gen and gen.healAbsorbBarColorG) or 0,
            runtimePrediction.healAbsorbB or (gen and gen.healAbsorbBarColorB) or 0,
            (runtimePrediction.healAbsorbA or (gen and gen.healAbsorbBarOpacity) or (gen and gen.healAbsorbBarColorA) or 1) * hpFillAlpha
        )
        if hpReverse then
            mock._healAbsorb:SetPoint("TOPLEFT", hpTex or mock._health, "TOPLEFT", 0, 0)
            mock._healAbsorb:SetPoint("BOTTOMLEFT", hpTex or mock._health, "BOTTOMLEFT", 0, 0)
            if mock._healAbsorb.SetReverseFill then mock._healAbsorb:SetReverseFill(false) end
        else
            mock._healAbsorb:SetPoint("TOPRIGHT", hpTex or mock._health, "TOPRIGHT", 0, 0)
            mock._healAbsorb:SetPoint("BOTTOMRIGHT", hpTex or mock._health, "BOTTOMRIGHT", 0, 0)
            if mock._healAbsorb.SetReverseFill then mock._healAbsorb:SetReverseFill(true) end
        end
        local healAbsorbW = tonumber(mock._health:GetWidth()) or 0
        if healAbsorbW <= 0 then healAbsorbW = mockW end
        mock._healAbsorb:SetWidth(max(1, healAbsorbW))
        mock._healAbsorb:SetValue(0.07)
        mock._healAbsorb:SetShown(healAbsorbShown)
        -- Scoped block: this render function sits near Lua's 200-local limit,
        -- so the power placement locals must release their slots when done.
        do
        -- LayoutDetached geometry (compiler resolves width to the frame width
        -- when unset; the conf fallback mirrors that for the no-spec path).
        local detachedPowerW = tonumber(runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or 0
        if detachedPowerW <= 0 then detachedPowerW = liveW end
        local detachedPowerH = tonumber(runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6
        local detachedPowerX = tonumber(runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
        local detachedPowerY = tonumber(runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
        local powerBarHandle = S.powerBarHandle
        if powerBarHandle then
            -- Runtime parity for interaction too: only the detached bar owns
            -- free offsets, so the handle locks itself while the bar is
            -- embedded/attached (single-click settings still work there).
            powerBarHandle._locked = not powerDetached
            if powerBarHandle._dragging ~= true then
                powerBarHandle._previewScale = previewScale
                powerBarHandle._previewWriteScale = previewScale
                powerBarHandle:ClearAllPoints()
                if powerDetached then
                    powerBarHandle:SetPoint("TOP", mock, "BOTTOM",
                        Round(detachedPowerX * previewScale), Round(detachedPowerY * previewScale))
                    powerBarHandle:SetSize(ScaleValue(detachedPowerW, previewScale, 1),
                        ScaleValue(detachedPowerH, previewScale, 1))
                elseif not powerEmbed then
                    powerBarHandle:SetPoint("TOP", mock, "BOTTOM", 0, -max(1, Round(previewScale)))
                    powerBarHandle:SetSize(max(1, mockW - inset * 2), max(12, powerH))
                else
                    powerBarHandle:SetPoint("BOTTOM", mock, "BOTTOM", 0, inset)
                    powerBarHandle:SetSize(max(1, mockW - inset * 2), max(12, powerH))
                end
            end
            powerBarHandle:SetShown(powerH > 0 and LayerOn("power"))
            powerBarHandle:SetAlpha(LayerAlpha("power"))
        end
        local powerFrameLevel = powerDetached
            and PreviewElementLevel(mock, Layers,
                runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, 6, 0)
            or ((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + 1
        SetPreviewFrameLevel(mock._power, powerFrameLevel)
        if powerBarHandle then SetPreviewFrameLevel(powerBarHandle, powerFrameLevel) end
        -- Layer gating hides only the drawn bar; the health inset keeps following
        -- the settings so hiding the preview layer never fakes a layout change.
        if powerH > 0 and LayerOn("power") then
            mock._power:SetAlpha(LayerAlpha("power"))
            mock._power:SetStatusBarTexture(runtimePower.texture or barTex)
            mock._power:ClearAllPoints()
            if powerDetached and powerBarHandle then
                -- Ride the handle so a drag moves the bar live; the handle sits
                -- at the runtime's TOP -> frame BOTTOM anchor.
                mock._power:SetPoint("TOP", powerBarHandle, "TOP", 0, 0)
                mock._power:SetSize(ScaleValue(detachedPowerW, previewScale, 1), ScaleValue(detachedPowerH, previewScale, 1))
            elseif powerDetached then
                mock._power:SetPoint("TOP", mock, "BOTTOM",
                    Round(detachedPowerX * previewScale), Round(detachedPowerY * previewScale))
                mock._power:SetSize(ScaleValue(detachedPowerW, previewScale, 1), ScaleValue(detachedPowerH, previewScale, 1))
            elseif not powerEmbed then
                -- Embed off: attached directly below the frame (frame BOTTOM, -1).
                local gap = max(1, Round(previewScale))
                mock._power:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", inset, -gap)
                mock._power:SetPoint("TOPRIGHT", mock, "BOTTOMRIGHT", -inset, -gap)
                mock._power:SetHeight(powerH)
            else
                mock._power:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", inset, inset)
                mock._power:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, inset)
                mock._power:SetHeight(powerH)
            end
            mock._powerBg:SetTexture(runtimePower.backgroundTexture or bgTex)
            local pbg = runtimePower.background or {}
            mock._powerBg:SetVertexColor(pbg.r or conf.bgR or 0.06, pbg.g or conf.bgG or 0.06, pbg.b or conf.bgB or 0.07, pbg.a or conf.hpBgAlpha or 0.85)
            if mock._power.SetMinMaxValues then mock._power:SetMinMaxValues(0, 1) end
            mock._power:SetValue(powerPct)
            mock._power:Show()
            mock._powerBg:Show()
        else
            mock._power:Hide()
            mock._powerBg:Hide()
        end
        if MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.ApplyBarGradient then
            MSUF.UFBarTextCommon.ApplyBarGradient(mock, mock._power,
                powerH > 0 and LayerOn("power") and runtimePower.barGradient or nil,
                "_msufGFPreviewPowerGradients")
        end
        end
        scene.previewScale = previewScale
        PaintGroupPreviewDispelOverlay(scene)
        if ApplyRounded(mock, conf, powerH > 0, outlineEdge,
            powerEmbed, powerDetached, powerOutlineEdge) then
            H.SetOutlineShown(mock, false)
            ApplyFrameBorder(self, nil, previewScale)
        else
            H.SetOutlineShown(mock, false)
            ApplyFrameBorder(self, runtimeBorder, previewScale)
        end
        PaintGroupPreviewPortrait(scene)
        PaintGroupPreviewDispelSymbol(scene)
        local textBaseLevel = 0
        if mock._nameTextLayer then
            if mock._nameTextLayer.GetParent and mock._nameTextLayer:GetParent() ~= mock and mock._nameTextLayer.SetParent then mock._nameTextLayer:SetParent(mock) end
            mock._nameTextLayer:ClearAllPoints()
            mock._nameTextLayer:SetAllPoints(mock)
            SetPreviewFrameLevel(mock._nameTextLayer, Layers.ElementLevel and PreviewElementLevel(mock, Layers, runtimeText.nameLayer or conf.nameTextLayer, 5, 8)
                or (((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + ClampLayer(runtimeText.nameLayer or conf.nameTextLayer, 5) + 8))
        end
        if mock._healthTextLayer then
            if mock._healthTextLayer.GetParent and mock._healthTextLayer:GetParent() ~= mock and mock._healthTextLayer.SetParent then mock._healthTextLayer:SetParent(mock) end
            mock._healthTextLayer:ClearAllPoints()
            mock._healthTextLayer:SetAllPoints(mock)
            SetPreviewFrameLevel(mock._healthTextLayer, Layers.ElementLevel and PreviewElementLevel(mock, Layers, runtimeText.healthLayer or conf.textLayer, 5, 8)
                or (((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + ClampLayer(runtimeText.healthLayer or conf.textLayer, 5) + 8))
        end
        if mock._powerTextLayer then
            mock._powerTextLayer:ClearAllPoints()
            mock._powerTextLayer:SetAllPoints(mock)
            SetPreviewFrameLevel(mock._powerTextLayer, Layers.ElementLevel and PreviewElementLevel(mock, Layers, runtimeText.powerLayer or conf.powerTextLayer, 2, 8)
                or (((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + ClampLayer(runtimeText.powerLayer or conf.powerTextLayer, 2) + 8))
        end
        local showText = LayerOn("text")
        local fontPath = (runtimeSpec and runtimeSpec.font) or (gf and gf.ResolveFontPath and gf.ResolveFontPath(kind)) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local fontFlags = (runtimeSpec and runtimeSpec.fontFlags) or (gf and gf.ResolveFontFlags and gf.ResolveFontFlags(kind)) or "OUTLINE"
        local fontShadow = true
        local fontShadowAlpha = tonumber(runtimeSpec and runtimeSpec.fontShadowAlpha) or 1
        local fontShadowX = tonumber(runtimeSpec and runtimeSpec.fontShadowX) or 1
        local fontShadowY = tonumber(runtimeSpec and runtimeSpec.fontShadowY) or -1
        if runtimeSpec then
            fontShadow = runtimeSpec.fontShadow == true
        elseif gf and gf.ResolveFontShadow then
            fontShadow, fontShadowAlpha, fontShadowX, fontShadowY = gf.ResolveFontShadow(kind)
        end
        local function SetPreviewFont(fs, size)
            if not fs then return end
            local path = fontPath
            local resolveSafe = _G.MSUF_ResolveSafeFontPath
            if type(resolveSafe) == "function" then
                local g = _G.MSUF_DB and _G.MSUF_DB.general
                path = resolveSafe(path, size, fontFlags, g and g.fontKey)
            end
            local ok = pcall(fs.SetFont, fs, path, size, fontFlags)
            if not ok then
                pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, fontFlags)
            end
            if fs.SetShadowOffset then
                if fontShadow then
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, fontShadowAlpha or 1) end
                    fs:SetShadowOffset(fontShadowX or 1, fontShadowY or -1)
                else
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
        local function LayoutPreviewText(fs, point, relPoint, x, y, justify, relativeTo)
            if not fs then return end
            fs:ClearAllPoints()
            fs:SetPoint(point, relativeTo or fs:GetParent(), relPoint or point, x or 0, y or 0)
            fs:SetJustifyH(justify or "LEFT")
            fs._msufPreviewJustifyH = justify or "LEFT"
        end
        local function PaintPreviewText(fs, size, mode, point, relPoint, x, y, justify, r, g, b, a, shown, text)
            if not fs then return end
            SetPreviewFont(fs, size)
            fs:SetTextColor(r, g, b, a)
            LayoutPreviewText(fs, point, relPoint, x, y, justify, mock)
            fs:SetText(text)
            fs:SetShown(shown and mode ~= "NONE")
        end
        local fr, fg, fb = T.colors.text[1], T.colors.text[2], T.colors.text[3]
        if runtimeSpec and runtimeSpec.textColor then fr, fg, fb = runtimeSpec.textColor.r, runtimeSpec.textColor.g, runtimeSpec.textColor.b end
        if gf and gf.ResolveFontColor then fr, fg, fb = gf.ResolveFontColor(kind) end
        local textAlpha = tonumber(runtimeSpec and runtimeSpec.textColor and runtimeSpec.textColor.a)
            or (gf and gf.ResolveFontTextAlpha and gf.ResolveFontTextAlpha(kind))
            or 1
        -- Text follows the foreground fade unless "Keep text + portrait visible"
        -- is on, matching SetTextLayerAlpha in the live alpha element.
        local alphaExcludeText = runtimeSpec and runtimeSpec.alpha and runtimeSpec.alpha.excludeTextPortrait == true
            or (not runtimeSpec and conf.alphaExcludeTextPortrait == true)
        if not alphaExcludeText then textAlpha = textAlpha * hpFillAlpha end
        local baselineOffset = (runtimeSpec and 0) or (gf and gf.ResolveFontBaselineOffset and gf.ResolveFontBaselineOffset(kind)) or 0
        do
            SetPreviewFont(mock._nameFS, max(6, ScaleValue((runtimeSpec and runtimeSpec.nameFontSize) or conf.nameFontSize or 12, previewScale, 6)))
            if mock._nameFS.SetWordWrap then mock._nameFS:SetWordWrap(false) end
            if mock._nameFS.SetNonSpaceWrap then mock._nameFS:SetNonSpaceWrap(false) end
            local previewName = (scene.liveData and scene.liveData.name) or self._msufGFRenderState.GF_PREVIEW_NAMES[5]
            if gf and gf.ResolveNameTruncation and gf.TruncateName then
                local maxC, noEllipsis, clipSide = gf.ResolveNameTruncation(kind)
                if maxC and maxC > 0 then previewName = gf.TruncateName(previewName, maxC, noEllipsis, clipSide) end
            end
            local nr, ng, nb = fr, fg, fb
            if gf and gf.ResolveNameColor then nr, ng, nb = gf.ResolveNameColor(kind, cls) end
            mock._nameFS:SetTextColor(nr or 1, ng or 1, nb or 1, textAlpha)
            -- Anchor and offsets are one editor-owned tuple. A queued compiled spec
            -- may legitimately lag this cold preview refresh by one apply tick.
            local nameAnchor, nox, noy = ResolvePreviewNameGeometry(conf, runtimeText,
                (runtimeSpec and gf and gf.ResolveFontBaselineOffset and gf.ResolveFontBaselineOffset(kind)) or baselineOffset)
            local namePoint, nameX, nameY, nameJustify = ResolvePreviewNamePoint(nameAnchor, nox, noy)
            mock._nameFS._msufPreviewNameEndpointX = nameX
            mock._nameFS._msufPreviewNameEndpointY = nameY
            -- Scale the complete runtime endpoint (x +/- 3), not its terms
            -- separately. This avoids a one-pixel drift at fractional Fit scales.
            nameX, nameY = ConfigToOffset(nameX, previewScale), ConfigToOffset(nameY, previewScale)
            local nameAnchorToFrame = runtimeText.nameAnchorToFrame
            if nameAnchorToFrame == nil then nameAnchorToFrame = conf._msufLegacyNameAnchorToFrame == true end
            local nameRef = (runtimeText.anchorToBars ~= false and nameAnchorToFrame ~= true and mock._health) or mock
            LayoutPreviewName(mock._nameFS, nameRef, namePoint, nameX, nameY, nameJustify)
            -- SetText comes after geometry, matching the established natural-width
            -- FontString path and making the region immediately authoritative.
            mock._nameFS:SetText(previewName)
            mock._nameFS:SetShown(showText and ((runtimeSpec and runtimeSpec.showName == true) or (not runtimeSpec and conf.showName ~= false)))
        end
        local pad4 = ScaleValue(4, previewScale, 1)
        local hpSize = (runtimeSpec and runtimeSpec.healthFontSize) or conf.hpFontSize or 10
        -- Reverse order renders the configured Right slot on the physical left
        -- side (and vice versa); per-slot size and offsets follow the content,
        -- mirroring the live engine's apply-time swap.
        local hpRev = (runtimeSpec and runtimeText.healthReverse == true)
            or ((not runtimeSpec) and conf.hpTextReverse == true)
        local hpLeftSize = max(7, ScaleValue(runtimeText[hpRev and "healthRightFontSize" or "healthLeftFontSize"] or conf[hpRev and "hpTextRightFontSize" or "hpTextLeftFontSize"] or hpSize, previewScale, 6))
        local hpCenterSize = max(7, ScaleValue(runtimeText.healthCenterFontSize or conf.hpTextCenterFontSize or hpSize, previewScale, 6))
        local hpRightSize = max(7, ScaleValue(runtimeText[hpRev and "healthLeftFontSize" or "healthRightFontSize"] or conf[hpRev and "hpTextLeftFontSize" or "hpTextRightFontSize"] or hpSize, previewScale, 6))
        local hpTextOn = showText and ((runtimeSpec and runtimeSpec.showHealthText == true) or (not runtimeSpec and conf.showHPText ~= false))
        local hpLeftMode, hpCenterMode, hpRightMode
        if runtimeSpec then
            hpLeftMode, hpCenterMode, hpRightMode = runtimeText.healthLeft or "NONE", runtimeText.healthCenter or "NONE", runtimeText.healthRight or "NONE"
        elseif gf and gf.ResolveHealthTextSlots then
            hpLeftMode, hpCenterMode, hpRightMode = gf.ResolveHealthTextSlots(conf)
        else
            hpLeftMode, hpCenterMode, hpRightMode = runtimeText.healthLeft or conf.textLeft or "NONE", runtimeText.healthCenter or conf.textCenter or "NONE", runtimeText.healthRight or conf.textRight or "NONE"
        end
        local function GlobalHidePercentSymbol()
            local db = M.EnsureDB and M.EnsureDB()
            local g = db and db.general
            return g and g.hidePercentSymbol == true
        end
        local function SlotHidePercentSymbol(runtimeKey, dbKey)
            local value = runtimeText and runtimeText[runtimeKey]
            if value ~= nil then return value == true end
            if conf and conf[dbKey] ~= nil then return conf[dbKey] == true end
            return GlobalHidePercentSymbol()
        end
        local hpLeftHidePercent = SlotHidePercentSymbol("healthLeftHidePercentSymbol", "hpTextLeftHidePercentSymbol")
        local hpCenterHidePercent = SlotHidePercentSymbol("healthCenterHidePercentSymbol", "hpTextCenterHidePercentSymbol")
        local hpRightHidePercent = SlotHidePercentSymbol("healthRightHidePercentSymbol", "hpTextRightHidePercentSymbol")
        if runtimeSpec and runtimeText.healthReverse == true then
            hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
            if gf and gf.ReverseHealthTextMode then
                hpLeftMode = gf.ReverseHealthTextMode(hpLeftMode)
                hpCenterMode = gf.ReverseHealthTextMode(hpCenterMode)
                hpRightMode = gf.ReverseHealthTextMode(hpRightMode)
            end
            hpLeftHidePercent, hpRightHidePercent = hpRightHidePercent, hpLeftHidePercent
        elseif (not runtimeSpec) and conf and conf.hpTextReverse == true then
            hpLeftHidePercent, hpRightHidePercent = hpRightHidePercent, hpLeftHidePercent
        end
        -- Exact live values when available; while the combat animation runs,
        -- the current value follows the animated fraction on the live scale.
        local fakeMax = (scene.liveData and scene.liveData.hpMax) or 1000000
        local fakeHP = (not scene.animState and scene.liveData and scene.liveData.hpCur)
            or max(1, floor(fakeMax * hpPct + 0.5))
        local fakeAbsorb = (scene.liveData and scene.liveData.absorb) or 125000
        local hpTextR, hpTextG, hpTextB = fr or 1, fg or 1, fb or 1
        local healthTextMode = (conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil)
            and conf.colorHealthTextByHealth or (gen and gen.colorHealthTextByHealth)
        local healthTextByClass = runtimeText.healthColorByClass == true
            or (not runtimeSpec and healthTextMode == "CLASS")
        local healthTextByHealth = runtimeText.healthColorByHealth == true
            or (not runtimeSpec and (healthTextMode == true or healthTextMode == "HEALTH"))
        if healthTextByClass then
            hpTextR, hpTextG, hpTextB = ClassColor(cls, hpTextR, hpTextG, hpTextB)
        elseif healthTextByHealth then
            local pct = fakeHP / fakeMax
            if pct <= 0.5 then
                hpTextR, hpTextG, hpTextB = 1, pct * 2, 0
            else
                hpTextR, hpTextG, hpTextB = (1 - pct) * 2, 1, 0
            end
        end
        local hpDelimiter = runtimeText.healthDelimiter or conf.textDelimiter or " - "
        local function PreviewHealthText(mode, hidePercentSymbol, runtimeIconKey, dbIconKey)
            local absorbIcon = runtimeText[runtimeIconKey]
            if absorbIcon == nil then absorbIcon = conf[dbIconKey] end
            if absorbIcon == nil then absorbIcon = runtimeText.healthAbsorbIcon == true or conf.hpAbsorbIcon == true end
            if gf and gf.FormatHealthText then return gf.FormatHealthText(mode, fakeHP, fakeMax, hpDelimiter, false, nil, hidePercentSymbol, runtimeText.healthShortNumbers == true or (runtimeText.healthShortNumbers == nil and conf.hpFullValueShort ~= false), fakeAbsorb, absorbIcon == true) end
            return mode == "PERCENT" and (hidePercentSymbol and "72" or "72%") or "720k"
        end
        PaintPreviewText(mock._hpLeftFS, hpLeftSize, hpLeftMode, "LEFT", "LEFT",
            pad4 + ConfigToOffset(runtimeText[hpRev and "healthRightX" or "healthLeftX"] or ((conf.hpOffsetX or 0) + (conf[hpRev and "hpTextRightOffsetX" or "hpTextLeftOffsetX"] or 0)), previewScale),
            ConfigToOffset(runtimeText[hpRev and "healthRightY" or "healthLeftY"] or ((conf.hpOffsetY or 0) + (conf[hpRev and "hpTextRightOffsetY" or "hpTextLeftOffsetY"] or 0) + baselineOffset), previewScale),
            "LEFT", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpLeftMode, hpLeftHidePercent,
                runtimeText.healthReverse == true and "healthRightAbsorbIcon" or "healthLeftAbsorbIcon",
                conf.hpTextReverse == true and "hpTextRightAbsorbIcon" or "hpTextLeftAbsorbIcon"))
        PaintPreviewText(mock._hpCenterFS, hpCenterSize, hpCenterMode, "CENTER", "CENTER",
            ConfigToOffset(runtimeText.healthCenterX or ((conf.hpOffsetX or 0) + (conf.hpTextCenterOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.healthCenterY or ((conf.hpOffsetY or 0) + (conf.hpTextCenterOffsetY or 0) + baselineOffset), previewScale),
            "CENTER", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpCenterMode, hpCenterHidePercent,
                "healthCenterAbsorbIcon", "hpTextCenterAbsorbIcon"))
        PaintPreviewText(mock._hpRightFS, hpRightSize, hpRightMode, "RIGHT", "RIGHT",
            -pad4 + ConfigToOffset(runtimeText[hpRev and "healthLeftX" or "healthRightX"] or ((conf.hpOffsetX or 0) + (conf[hpRev and "hpTextLeftOffsetX" or "hpTextRightOffsetX"] or 0)), previewScale),
            ConfigToOffset(runtimeText[hpRev and "healthLeftY" or "healthRightY"] or ((conf.hpOffsetY or 0) + (conf[hpRev and "hpTextLeftOffsetY" or "hpTextRightOffsetY"] or 0) + baselineOffset), previewScale),
            "RIGHT", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpRightMode, hpRightHidePercent,
                runtimeText.healthReverse == true and "healthLeftAbsorbIcon" or "healthRightAbsorbIcon",
                conf.hpTextReverse == true and "hpTextLeftAbsorbIcon" or "hpTextRightAbsorbIcon"))
        local pwrSize = (runtimeSpec and runtimeSpec.powerFontSize) or conf.powerFontSize or 9
        local pwrLeftSize = max(6, ScaleValue(runtimeText.powerLeftFontSize or conf.powerTextLeftFontSize or pwrSize, previewScale, 6))
        local pwrCenterSize = max(6, ScaleValue(runtimeText.powerCenterFontSize or conf.powerTextCenterFontSize or pwrSize, previewScale, 6))
        local pwrRightSize = max(6, ScaleValue(runtimeText.powerRightFontSize or conf.powerTextRightFontSize or pwrSize, previewScale, 6))
        local showPowerText = showText
        if runtimeSpec then
            showPowerText = showText and runtimeSpec.showPowerText == true
        elseif gf and gf.IsPowerTextEnabled then
            showPowerText = showText and gf.IsPowerTextEnabled(kind, conf)
        end
        local fakePowMax = (scene.liveData and scene.liveData.powerMax) or 100
        local fakePow = (not scene.animState and scene.liveData and scene.liveData.powerCur)
            or max(0, floor(fakePowMax * powerPct + 0.5))
        local powerDelimiter = runtimeText.powerDelimiter or conf.powerTextDelimiter or conf.textDelimiter or " - "
        local function PreviewPowerText(mode, hidePercentSymbol)
            if gf and gf.FormatPowerText then return gf.FormatPowerText(mode, fakePow, fakePowMax, powerDelimiter, nil, hidePercentSymbol) end
            return mode == "PERCENT" and (hidePercentSymbol and "70" or "70%") or "70"
        end
        local powerLeftMode = runtimeText.powerLeft or conf.powerTextLeft or "NONE"
        local powerCenterMode = runtimeText.powerCenter or conf.powerTextCenter or "NONE"
        local powerRightMode = runtimeText.powerRight or conf.powerTextRight or "NONE"
        local powerLeftHidePercent = SlotHidePercentSymbol("powerLeftHidePercentSymbol", "powerTextLeftHidePercentSymbol")
        local powerCenterHidePercent = SlotHidePercentSymbol("powerCenterHidePercentSymbol", "powerTextCenterHidePercentSymbol")
        local powerRightHidePercent = SlotHidePercentSymbol("powerRightHidePercentSymbol", "powerTextRightHidePercentSymbol")
        PaintPreviewText(mock._powerLeftFS, pwrLeftSize, powerLeftMode, "BOTTOMLEFT", "BOTTOMLEFT",
            pad4 + ConfigToOffset(runtimeText.powerLeftX or ((conf.powerOffsetX or 0) + (conf.powerTextLeftOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.powerLeftY or ((conf.powerOffsetY or 0) + (conf.powerTextLeftOffsetY or 0) + baselineOffset), previewScale),
            "LEFT", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerLeftMode, powerLeftHidePercent))
        PaintPreviewText(mock._powerCenterFS, pwrCenterSize, powerCenterMode, "BOTTOM", "BOTTOM",
            ConfigToOffset(runtimeText.powerCenterX or ((conf.powerOffsetX or 0) + (conf.powerTextCenterOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.powerCenterY or ((conf.powerOffsetY or 0) + (conf.powerTextCenterOffsetY or 0) + baselineOffset), previewScale),
            "CENTER", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerCenterMode, powerCenterHidePercent))
        PaintPreviewText(mock._powerRightFS, pwrRightSize, powerRightMode, "BOTTOMRIGHT", "BOTTOMRIGHT",
            -pad4 + ConfigToOffset(runtimeText.powerRightX or ((conf.powerOffsetX or 0) + (conf.powerTextRightOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.powerRightY or ((conf.powerOffsetY or 0) + (conf.powerTextRightOffsetY or 0) + baselineOffset), previewScale),
            "RIGHT", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerRightMode, powerRightHidePercent))
        -- Group block border. Live it wraps the whole header block; this box
        -- previews a single frame, so it wraps the mock with the configured
        -- padding. That still reads as an outer box, distinct from the
        -- per-frame border, and previews thickness/padding/color faithfully.
        PaintGroupBlockBorder(mock, conf, previewScale, ScaleValue)
        local boundsEdge = max(1, outlineEdge)
        ApplyBoundsGuide(self, boundsEdge)
        if self._bounds.SetFrameLevel and mock.GetFrameLevel then
            SetPreviewFrameLevel(self._bounds, Layers.ElementLevel and (PreviewElementLevel(mock, Layers, 30, 30, 31) + 16)
                or ((mock:GetFrameLevel() or 1) + (Layers.PREVIEW_BOUNDS_OFFSET or 48)))
        end
        self._bounds:SetShown(LayerOn("bounds"))
        scene.previewScale = previewScale
        scene.SetPreviewFont = SetPreviewFont
        RenderAuras(scene)
        local LayoutHandle = scene.LayoutHandle
        local PlaceAuraPreviewText = scene.PlaceAuraPreviewText
        local RuntimeAuraTextAnchor = scene.RuntimeAuraTextAnchor
        local LayoutAuraPreviewSwipe = scene.LayoutAuraPreviewSwipe
        local LayoutAuraDurationBar = scene.LayoutAuraDurationBar
        local function ConfigureStatusHandle(statusHandle)
            local spec = statusHandle and statusHandle._statusSpec
            if not (statusHandle and spec) then return end
            local runtimeCfg = RuntimeStatusConfig(runtimeStatus, spec)
            local enabled
            if runtimeSpec then
                enabled = runtimeCfg and runtimeCfg.enabled == true
            else
                enabled = StatusSpecEnabled(conf, spec)
            end
            local statusIsText = StatusSpecIsText(spec)
            local statusRawSize = tonumber(runtimeCfg and runtimeCfg.size) or tonumber(conf[spec.size]) or tonumber(spec.defaultSize) or 14
            local statusSize = ScaleValue(statusRawSize, previewScale, statusIsText and 10 or 8)
            statusHandle._previewText = spec.text or "Status"
            if statusHandle._label and statusHandle._label.SetText then
                statusHandle._label:SetText(StatusLabel(spec))
                statusHandle._label:SetTextColor(0.80, 0.67, 0.20, enabled and 0.95 or 0.55)
            end
            if statusIsText then
                statusHandle:SetSize(max(42, statusSize * 4), max(18, statusSize + 8))
                if statusHandle._statusText and statusHandle._statusText.SetFont then SetPreviewFont(statusHandle._statusText, max(12, statusSize)) end
                if statusHandle._statusText then
                    statusHandle._statusText:SetText(StatusText(spec, runtimeCfg, conf))
                    statusHandle._statusText:SetTextColor(enabled and 1 or 0.45, enabled and 1 or 0.45, enabled and 1 or 0.50, enabled and 1 or 0.60)
                    statusHandle._statusText:ClearAllPoints()
                    statusHandle._statusText:SetPoint("CENTER", statusHandle, "CENTER", 0, 0)
                    statusHandle._statusText:Show()
                end
                -- The live region is a bare FontString, so its own edges land on
                -- the configured anchor. A fixed handle box with centred text
                -- puts the glyph half a box away from where the frame draws it,
                -- so shrink the handle onto the text and win the hit area back
                -- through hit-rect insets instead.
                if spec.fitTextBounds == true and statusHandle._statusText then
                    local textW = tonumber(statusHandle._statusText.GetStringWidth
                        and statusHandle._statusText:GetStringWidth()) or 0
                    local textH = tonumber(statusHandle._statusText.GetStringHeight
                        and statusHandle._statusText:GetStringHeight()) or 0
                    textW = max(4, textW)
                    textH = max(4, textH)
                    statusHandle:SetSize(textW, textH)
                    if statusHandle.SetHitRectInsets then
                        local padX = max(0, (24 - textW) * 0.5)
                        local padY = max(0, (20 - textH) * 0.5)
                        statusHandle:SetHitRectInsets(-padX, -padX, -max(padY, 14), -padY)
                    end
                end
                if statusHandle._statusTex then statusHandle._statusTex:Hide() end
            else
                statusSize = max(8, statusSize)
                statusHandle:SetSize(statusSize, statusSize)
                if statusHandle._statusText then statusHandle._statusText:Hide() end
                local tex = statusHandle._statusTex
                if tex then
                    local path, atlas, l, r, t, b = nil, nil, 0, 1, 0, 1
                    local value = spec.value
                    if runtimeCfg and type(runtimeCfg.customIcon) == "string" and runtimeCfg.customIcon ~= "" then
                        path, l, r, t, b = runtimeCfg.customIcon, 0, 1, 0, 1
                    elseif spec.customIcon and type(conf[spec.customIcon]) == "string" and conf[spec.customIcon] ~= "" then
                        path, l, r, t, b = conf[spec.customIcon], 0, 1, 0, 1
                    elseif value == "roleIcon" and gf and gf.GetRoleTexture then
                        path, l, r, t, b = gf.GetRoleTexture(kind, scene.previewRole, runtimeCfg and runtimeCfg.style)
                    elseif value == "leaderIcon" and gf and gf.GetLeaderTexture then
                        path, l, r, t, b = gf.GetLeaderTexture(kind, runtimeCfg and runtimeCfg.style)
                    elseif value == "assistIcon" and gf and gf.GetAssistTexture then
                        path, l, r, t, b = gf.GetAssistTexture(kind, runtimeCfg and runtimeCfg.style)
                    elseif value == "raidMarker" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "raidMarker", 1)
                    elseif value == "readyCheckIcon" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "readyCheck", "ready")
                    elseif value == "summonIcon" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "summon", 1)
                    elseif value == "resurrectIcon" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "incomingRes", "resurrect")
                    elseif value == "pvpIcon" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "pvp", "Alliance")
                    elseif value == "phaseIcon" then
                        path, l, r, t, b = ResolveStatusTexture(spec, runtimeCfg, "phase", "phase")
                    end
                    if atlas or path then
                        if atlas and tex.SetAtlas then
                            tex:SetAtlas(atlas)
                        else
                            tex:SetTexture(path or "Interface\\TargetingFrame\\UI-PVP-Alliance")
                            tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                        end
                        if enabled then
                            tex:SetVertexColor(1, 1, 1, 1)
                        else
                            tex:SetVertexColor(0.40, 0.40, 0.45, 0.55)
                        end
                        tex:ClearAllPoints()
                        tex:SetPoint("TOPLEFT", statusHandle, "TOPLEFT", 0, 0)
                        tex:SetPoint("BOTTOMRIGHT", statusHandle, "BOTTOMRIGHT", 0, 0)
                        tex:Show()
                    else
                        tex:Hide()
                    end
                end
            end
            LayoutHandle(statusHandle,
                runtimeCfg and runtimeCfg.anchor or conf[spec.anchor],
                runtimeCfg and runtimeCfg.x or conf[spec.x],
                runtimeCfg and runtimeCfg.y or conf[spec.y],
                spec.defaultAnchor or "CENTER")
        end
        for i = 1, #statusHandles do
            ConfigureStatusHandle(statusHandles[i])
        end
        local dynamicSpellHandlesActive = box._msufGFSpellHandlesActiveScratch or {}
        box._msufGFSpellHandlesActiveScratch = dynamicSpellHandlesActive
        wipe(dynamicSpellHandlesActive)
        local selectedRuntimeSpellHandleUsed = false
        local function HideSpellIconEffectPreview(handle)
            local root = handle and handle._msufSpellPreviewIconEffectRoot
            if not root then return end
            HidePreviewGlow(root)
            root:Hide()
        end
        local function ApplySpellIconEffectPreview(handle, placed, spellSize)
            local visual = placed and (placed.visual or placed.type)
            if not (handle and placed and visual == "icon" and placed.iconEffect == "glow") then
                HideSpellIconEffectPreview(handle)
                return
            end
            local root = handle._msufSpellPreviewIconEffectRoot
            if not root then
                root = CreateFrame("Frame", nil, handle)
                root:EnableMouse(false)
                handle._msufSpellPreviewIconEffectRoot = root
            end
            root:ClearAllPoints()
            root:SetAllPoints(handle)
            local color = handle._msufSpellIndicatorColor or { 1, 1, 1, 1 }
            ShowPreviewGlow(root, root, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1,
                max(2, spellSize * 0.15))
            root:Show()
        end
        local function ConfigureSpellPreviewHandle(handle, item, placed, appearance, fallbackTexture, fallbackColor)
            if not (handle and placed) then return false end
            appearance = appearance or {}
            local exactSlot = placed.spellIndicatorSlot == true
            local spellType = exactSlot and (placed.visual or "none") or (placed.type or "icon")
            local placedScale = (exactSlot or placed._msufIconScaleApplied == true) and 1 or scene.spellIconScale
            local spellBaseSize = (tonumber(placed.size) or 20) * placedScale
            local spellSize = max(1, ScaleValue(spellBaseSize, previewScale, 1))
            if handle.SetAlpha then handle:SetAlpha(tonumber(appearance.alpha) or 1) end
            local color = item and item.color or fallbackColor
            local spellR, spellG, spellB = (color and color[1]) or 0.69, (color and color[2]) or 0.50, (color and color[3]) or 0.88
            if handle.SetBackdropColor then handle:SetBackdropColor(spellR * 0.12, spellG * 0.12, spellB * 0.12, 0.42) end
            if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(spellR, spellG, spellB, 0.95) end
            handle._icons = handle._icons or {}
            local spellTex = handle._icons[1]
            local spellSwipe = handle._iconSwipes and handle._iconSwipes[1]
            local spellStack = handle._iconStacks and handle._iconStacks[1]
            local spellTimer = handle._iconTimers and handle._iconTimers[1]
            local spellDurationBar = handle._iconDurationBars and handle._iconDurationBars[1]
            local handleColor = handle._msufSpellIndicatorColor
            if not handleColor then
                handleColor = {}
                handle._msufSpellIndicatorColor = handleColor
            end
            handleColor[1], handleColor[2], handleColor[3], handleColor[4] = spellR, spellG, spellB, (color and color[4]) or 1
            handle._color = handleColor
            if handle._label and handle._label.SetText then
                handle._label:SetText(item and (item.display or item.auraName) or "SPELL")
                handle._label:Show()
            end
            if spellSwipe then spellSwipe:Hide() end
            if spellStack then spellStack:Hide() end
            if spellTimer then spellTimer:Hide() end
            if spellDurationBar then spellDurationBar:Hide() end
            if spellType == "bar" then
                local barWidth = tonumber(exactSlot and placed.width or placed.barWidth)
                if barWidth then barWidth = barWidth * placedScale end
                local barW = max(spellSize * 2, ScaleValue(barWidth or (spellBaseSize * 3), previewScale, 16))
                handle:SetSize(barW, spellSize)
                if spellTex then
                    spellTex:SetTexture(WHITE8X8)
                    spellTex:SetTexCoord(0, 1, 0, 1)
                    spellTex:SetVertexColor(spellR * 0.18, spellG * 0.18, spellB * 0.18,
                        ((color and color[4]) or 1) * 0.55)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
                if spellDurationBar then
                    -- Menu previews have no live AuraDurationObject. Show one
                    -- representative native-fill state without adding preview
                    -- animation or recurring work.
                    spellDurationBar:SetTexture(WHITE8X8)
                    spellDurationBar:SetTexCoord(0, 1, 0, 1)
                    spellDurationBar:SetVertexColor(spellR, spellG, spellB, (color and color[4]) or 1)
                    spellDurationBar:ClearAllPoints()
                    local reverseFill = exactSlot and placed.durationBarReverseFill == true
                        or (not exactSlot and tostring(placed.growth or "RIGHTDOWN"):upper():sub(1, 4) == "LEFT")
                    local edge = reverseFill and "RIGHT" or "LEFT"
                    spellDurationBar:SetPoint("TOP" .. edge, handle, "TOP" .. edge, 0, 0)
                    spellDurationBar:SetPoint("BOTTOM" .. edge, handle, "BOTTOM" .. edge, 0, 0)
                    spellDurationBar:SetWidth(max(1, barW * 0.68))
                    spellDurationBar:Show()
                end
                local showTimer = exactSlot and placed.showCooldownText == true
                    or (not exactSlot and placed.barShowTimer == true)
                if spellTimer and showTimer then
                    local cooldownSize = max(6, ScaleValue(appearance.cooldownSize or placed.cooldownSize or 8,
                        previewScale, 6))
                    SetPreviewFont(spellTimer, cooldownSize)
                    spellTimer:SetTextColor(1, 1, 1, 1)
                    PlaceAuraPreviewText(spellTimer, handle,
                        RuntimeAuraTextAnchor(exactSlot and placed.cooldownAnchor or placed.barTimerAnchor, "CENTER"),
                        ConfigToOffset(exactSlot and placed.cooldownX or placed.barTimerX or 0, previewScale),
                        ConfigToOffset(exactSlot and placed.cooldownY or placed.barTimerY or 0, previewScale))
                    spellTimer:SetText("12")
                    spellTimer:Show()
                end
            elseif spellType == "square" then
                handle:SetSize(spellSize, spellSize)
                if spellTex then
                    spellTex:SetTexture(WHITE8X8)
                    spellTex:SetTexCoord(0, 1, 0, 1)
                    spellTex:SetVertexColor(spellR, spellG, spellB, 1)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
            elseif spellType == "number" then
                handle:SetSize(max(18, spellSize), max(18, spellSize))
                if spellTex then spellTex:Hide() end
                if spellStack then
                    SetPreviewFont(spellStack, max(8, spellSize * 0.72))
                    spellStack:SetTextColor(spellR, spellG, spellB, 1)
                    spellStack:ClearAllPoints()
                    spellStack:SetPoint("CENTER", handle, "CENTER", 0, 0)
                    local showStacks = appearance.showStacks
                    if showStacks == nil then showStacks = placed.showStacks ~= false end
                    spellStack:SetText(showStacks and "9" or "")
                    spellStack:SetShown(showStacks)
                end
            else
                handle:SetSize(spellSize, spellSize)
                if spellTex then
                    spellTex:SetTexture((item and item.icon) or fallbackTexture or CurrentSpellTexture(kind))
                    ApplyPreviewIconZoom(spellTex, exactSlot and placed.iconZoom or scene.spellIconZoom, 0)
                    spellTex:SetVertexColor(1, 1, 1, 1)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
                local showCooldown = appearance.showCooldownText
                if showCooldown == nil then showCooldown = appearance.showCooldown end
                if showCooldown == nil then showCooldown = placed.showCooldown ~= false end
                local showSwipe = appearance.showCooldownSwipe
                if showSwipe == nil then showSwipe = placed.showCooldownSwipe ~= false end
                local showStacks = appearance.showStacks
                if showStacks == nil then showStacks = placed.showStacks ~= false end
                local barOnly = appearance.showDurationBar == true and (appearance.durationBarDisplay or "BAR_ONLY") == "BAR_ONLY"
                if spellTex and spellTex.SetAlpha then spellTex:SetAlpha(barOnly and 0 or 1) end
                if spellTimer then
                    local cooldownSize = max(6, ScaleValue(appearance.cooldownSize or placed.cooldownSize or 8, previewScale, 6))
                    SetPreviewFont(spellTimer, cooldownSize)
                    spellTimer:SetTextColor(1, 1, 1, 1)
                    PlaceAuraPreviewText(spellTimer, spellTex or handle,
                        RuntimeAuraTextAnchor(appearance.cooldownAnchor, "CENTER"),
                        ConfigToOffset(appearance.cooldownX or 0, previewScale),
                        ConfigToOffset(appearance.cooldownY or 0, previewScale))
                    spellTimer:SetText(showCooldown and "12" or "")
                    spellTimer:SetShown(showCooldown)
                end
                if spellSwipe and showSwipe and not barOnly then
                    LayoutAuraPreviewSwipe(spellSwipe, spellTex or handle, spellSize, 0.48,
                        appearance.cooldownSwipeReverse == true)
                    spellSwipe:SetVertexColor(0, 0, 0, 0.58)
                    spellSwipe:Show()
                end
                LayoutAuraDurationBar(spellDurationBar, spellTex or handle, appearance, spellSize, nil)
                if spellStack and showStacks then
                    SetPreviewFont(spellStack, max(6, ScaleValue(appearance.stackSize or 10, previewScale, 6)))
                    spellStack:SetTextColor(1, 1, 1, 1)
                    PlaceAuraPreviewText(spellStack, spellTex or handle,
                        RuntimeAuraTextAnchor(appearance.stackAnchor, "BOTTOMRIGHT"),
                        ConfigToOffset(appearance.stackX or 0, previewScale),
                        ConfigToOffset(appearance.stackY or 0, previewScale))
                    spellStack:SetText("2")
                    spellStack:Show()
                end
                local a3 = MSUF and MSUF.MSUF_Auras3
                local previewShape = appearance.iconShape or "RECTANGLE"
                if a3 and type(a3.ResolveAuraIconShape) == "function" then
                    previewShape = a3.ResolveAuraIconShape(previewShape,
                        conf.portraitShape or (conf.portrait and conf.portrait.shape))
                end
                if a3 and type(a3.ApplyAuraIconShape) == "function" then
                    a3.ApplyAuraIconShape(handle, previewShape, nil, spellTex, spellSwipe)
                end
                if a3 and type(a3.ApplyIconStylePreview) == "function" then
                    a3.ApplyIconStylePreview(handle, barOnly and nil or appearance.iconStyle, spellSize, previewShape)
                end
            end
            if spellType ~= "icon" then
                local a3 = MSUF and MSUF.MSUF_Auras3
                if a3 and type(a3.ApplyAuraIconShape) == "function" then
                    a3.ApplyAuraIconShape(handle, "RECTANGLE", nil, spellTex, spellSwipe)
                end
                if a3 and type(a3.ApplyIconStylePreview) == "function" then
                    a3.ApplyIconStylePreview(handle, nil)
                end
            end
            handle._msufSpellIndicatorLayer = item and item.layer or nil
            handle._msufSpellIndicatorStrata = item and item.strata or nil
            LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")
            ApplySpellIconEffectPreview(handle, placed, spellSize)
            return true
        end
        if runtimeSpellIndicators and runtimeSpellIndicators.enabled == true and type(runtimeSpellItems) == "table" and box.EnsureSpellIndicatorHandle then
            for i = 1, #runtimeSpellItems do
                local item = runtimeSpellItems[i]
                local exactSlot = item and item.spellIndicatorSlot == true
                local placed = exactSlot and item or (item and item.placed)
                local selectedItem = item and item.specKey == scene.selectedSpellSpecKey
                    and item.auraName == scene.selectedSpellAuraName
                local effect = (exactSlot and item.frameEffect) or item.frame
                    or (selectedItem and selectedSpellEffect) or nil
                local handle = box:EnsureSpellIndicatorHandle(item, i)
                local placedType = placed and (exactSlot and placed.visual or placed.type) or "none"
                local placedShown = placed and placedType ~= "none" and item.hiddenVisual ~= true
                if handle and placedShown and ConfigureSpellPreviewHandle(handle, item, placed, item) then
                    if selectedItem then selectedRuntimeSpellHandleUsed = true end
                elseif handle and effect then
                    handle:SetSize(1, 1)
                    if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
                    if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(0, 0, 0, 0) end
                    if handle._label then handle._label:Hide() end
                    if handle._icons and handle._icons[1] then handle._icons[1]:Hide() end
                    if handle._iconSwipes and handle._iconSwipes[1] then handle._iconSwipes[1]:Hide() end
                    if handle._iconStacks and handle._iconStacks[1] then handle._iconStacks[1]:Hide() end
                    if handle._iconTimers and handle._iconTimers[1] then handle._iconTimers[1]:Hide() end
                    handle._msufSpellIndicatorLayer = item.layer
                    handle._msufSpellIndicatorStrata = item.strata
                    LayoutHandle(handle, "CENTER", 0, 0, "CENTER")
                    HideSpellIconEffectPreview(handle)
                end
                if handle and (placedShown or effect) then
                    dynamicSpellHandlesActive[handle._msufSpellIndicatorPreviewKey] = handle
                    -- The selected spell's full-frame effect keeps its stable
                    -- mock-owned preview root. Every other previewed spell owns
                    -- its own root, so Preview all spells composites the frame
                    -- effects by priority exactly like the live frame does.
                    if effect and not selectedItem then
                        ApplySpellEffectPreview(handle, effect)
                    else
                        HideSpellEffectPreview(handle)
                    end
                end
            end
        end
        for key, handle in pairs(box._spellIndicatorHandles or {}) do
            if not dynamicSpellHandlesActive[key] then
                HideSpellEffectPreview(handle)
                HideSpellIconEffectPreview(handle)
            end
        end
        if box.HideUnusedSpellIndicatorHandles then box:HideUnusedSpellIndicatorHandles(dynamicSpellHandlesActive) end
        if selectedRuntimeSpellHandleUsed then
            HideSpellEffectPreview(spellHandle)
            HideSpellIconEffectPreview(spellHandle)
            spellHandle:Hide()
        elseif selectedSpellCfg and (scene.selectedSpellPlacedEnabled or selectedSpellNeedsPlacementPreview) then
            local selectedSpellIcon = CurrentSpellTexture(kind)
            local spellR, spellG, spellB = CurrentSpellColor(kind)
            local selectedFallbackItem = spellHandle._msufGFSelectedFallbackItem
            if not selectedFallbackItem then
                selectedFallbackItem = {}
                spellHandle._msufGFSelectedFallbackItem = selectedFallbackItem
            end
            selectedFallbackItem.specKey = scene.selectedSpellSpecKey
            selectedFallbackItem.auraName = scene.selectedSpellAuraName
            selectedFallbackItem.display = scene.selectedSpellAuraName or "Spell"
            local selectedAppearance = selectedSpellCfg.cornerSlotKey == nil
                and type(conf.spellIndicators) == "table" and conf.spellIndicators.style or nil
            if selectedAppearance and buffCfg and buffCfg.iconStyle and selectedAppearance.iconStyle == nil then
                local fallbackAppearance = spellHandle._msufGFSelectedFallbackAppearance
                if not fallbackAppearance then
                    fallbackAppearance = {}
                    spellHandle._msufGFSelectedFallbackAppearance = fallbackAppearance
                end
                wipe(fallbackAppearance)
                for key, value in pairs(selectedAppearance) do fallbackAppearance[key] = value end
                fallbackAppearance.iconStyle = buffCfg.iconStyle
                selectedAppearance = fallbackAppearance
            end
            ConfigureSpellPreviewHandle(spellHandle, selectedFallbackItem,
                selectedPlaced or { type = "icon", size = 20, anchor = "TOPLEFT", x = 0, y = 0 },
                selectedAppearance, selectedSpellIcon, { spellR, spellG, spellB, 1 })
            HideSpellEffectPreview(spellHandle)
        else
            HideSpellEffectPreview(spellHandle)
            HideSpellIconEffectPreview(spellHandle)
            spellHandle:Hide()
        end
        selectedSpellEffectOwner:ClearAllPoints()
        selectedSpellEffectOwner:SetAllPoints(mock)
        if scene.selectedSpellEffectAvailable and selectedSpellEffect then
            ApplySpellEffectPreview(selectedSpellEffectOwner, selectedSpellEffect)
        else
            HideSpellEffectPreview(selectedSpellEffectOwner)
        end
        scene.previewScale = previewScale
        scene.textBaseLevel = textBaseLevel
        scene.dynamicSpellHandlesActive = dynamicSpellHandlesActive
        FinalizeScene(scene)
    end
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", function(self, key)
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            self._selectedHandle = nil
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            RefreshHandleSelection(self)
            return
        end
        local focusFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        -- Tab steps through the placed handles. Overlapping elements in dense
        -- corners cannot all be reached by clicking, so keyboard traversal is
        -- the only way to select what sits underneath. It also works with
        -- nothing selected yet, and never while an edit box has focus.
        if key == "TAB" and not focusFrame and M.PreviewSelectionBar then
            if M.PreviewSelectionBar.CycleHandle(self, IsShiftKeyDown and IsShiftKeyDown()) then
                if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
                return
            end
        end
        local handle = self._selectedHandle
        if not handle or handle._locked then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if focusFrame then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        local dx, dy = 0, 0
        if key == "LEFT" then
            dx = -1
        elseif key == "RIGHT" then
            dx = 1
        elseif key == "UP" then
            dy = 1
        elseif key == "DOWN" then
            dy = -1
        else
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        NudgeHandlePosition(handle, dx, dy)
        RefreshHandleSelection(self)
    end)
end
