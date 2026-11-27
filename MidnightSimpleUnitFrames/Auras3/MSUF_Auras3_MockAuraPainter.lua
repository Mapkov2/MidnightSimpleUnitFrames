--- Auras3 mock icon painting shared by the menu and on-screen previews.
--- Callers own pools, geometry, fonts, samples and lifecycle. These painters
--- only update their supplied regions; they create no frames and register no
--- events, unit watch, secure attributes or click handling. Sample state stays
--- on the icon that asked for it.
local _, MSUF = ...
local A3 = assert(MSUF.MSUF_Auras3)
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Auras3/MockAuraPainter")
-- Preview sample builders (UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua loads first).
local Animation = assert(MSUF.PreviewAnimation, "Mock aura painter requires PreviewAnimation")
local GetGeneralDB = MSUF.Require("MSUF_GetGeneralDB", "Auras3/MockAuraPainter")
local BuildPreviewAnimationAuraState = Animation.BuildAuraState
local GetPreviewAnimationAuraState = Animation.AuraState
local WHITE = "Interface\\Buttons\\WHITE8X8"
local IGNORE_ATLAS_SIZE = TextureKitConstants and TextureKitConstants.IgnoreAtlasSize
local type, tonumber, tostring = type, tonumber, tostring
local floor, max, min = math.floor, math.max, math.min
local Painter = { AURA_BAR_FILL_ALPHA = 0.42 }
A3.MockAuraPainter = Painter

local REFLOW_EXPIRES_AT, REFLOW_SECONDS, REFLOW_HOLD_SECONDS = 2.6, 0.18, 3.4

function Painter.PreviewReflowReducedMotion(elapsed)
    if elapsed == nil then return false end
    local general = GetGeneralDB()
    return general and (general.reduceMotion == true or general.reducedMotion == true)
end

function Painter.ConfigurePreviewReflow(icon, host, anchor, first, x, y, compactX, compactY, duration, animate)
    local flow = icon._msufPreviewAuraReflow or {}
    icon._msufPreviewAuraReflow = flow
    flow.host, flow.anchor, flow.first = host, anchor, first
    flow.x, flow.y, flow.compactX, flow.compactY = x, y, compactX, compactY
    flow.duration = duration or REFLOW_EXPIRES_AT
    flow.longSample = duration ~= nil
    flow.animate = animate == true
    flow.currentX, flow.currentY, flow.hidden = x, y, false
    if flow.alpha and flow.alpha ~= 1 then icon:SetAlpha(1) end
    flow.alpha = 1
end

function Painter.ClearPreviewReflow(icon)
    local flow = icon._msufPreviewAuraReflow
    if flow then
        if flow.alpha ~= 1 then icon:SetAlpha(1) end
        flow.host, flow.alpha = nil, 1
    end
end

--- Uses the caller's preview clock and public sample positions only.
--- The first sample expires while the others keep their original artwork.
function Painter.UpdatePreviewReflow(icon, elapsed, reducedMotion)
    local flow = icon._msufPreviewAuraReflow
    if not (flow and flow.host) then return end
    local expiresAt = flow.duration
    local cycle = expiresAt + REFLOW_HOLD_SECONDS
    local phase = elapsed and elapsed % cycle or 0
    local expired = phase >= expiresAt
    local motionTime = phase - expiresAt
    local motion = flow.animate and not reducedMotion
    local exiting = flow.first and expired and motion and motionTime < REFLOW_SECONDS
    local hidden = flow.first and expired and not exiting
    if flow.first then
        local alpha = exiting and 1 - motionTime / REFLOW_SECONDS or 1
        if motion and elapsed and elapsed >= cycle and phase < REFLOW_SECONDS then alpha = phase / REFLOW_SECONDS end
        if flow.alpha ~= alpha then
            icon:SetAlpha(alpha)
            flow.alpha = alpha
        end
    end
    if flow.hidden ~= hidden then
        flow.hidden = hidden
        icon:SetShown(not hidden)
    end
    local progress = expired and 1 or 0
    if motion then
        progress = max(0, min(1, (phase - expiresAt) / REFLOW_SECONDS, (cycle - phase) / REFLOW_SECONDS))
        progress = progress * progress * (3 - 2 * progress)
    end
    local x = flow.x + (flow.compactX - flow.x) * progress
    local y = flow.y + (flow.compactY - flow.y) * progress
    if flow.currentX ~= x or flow.currentY ~= y then
        flow.currentX, flow.currentY = x, y
        icon:ClearAllPoints()
        icon:SetPoint(flow.anchor, flow.host, flow.anchor, x, y)
    end
    if elapsed then
        if flow.first then return phase, expiresAt, expired end
        if flow.longSample then return phase, cycle + REFLOW_SECONDS end
    end
end

--- Regions stay private to the caller's icon. Reusing their constructors
--- preserves creation order, draw layers and the supplied initial anchors.
function Painter.NewSwipe(icon, topY, bottomX, bottomY)
    local swipe = PixelLayoutRegion(icon:CreateTexture(nil, "ARTWORK", nil, 1))
    if topY ~= nil then
        swipe:SetPoint("TOPLEFT", icon, "TOP", 0, topY)
        swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bottomX, bottomY)
    end
    swipe:SetTexture(WHITE)
    swipe:SetVertexColor(0, 0, 0, 0.58)
    swipe:Hide()
    return swipe
end

function Painter.NewDurationBar(icon)
    local bar = PixelLayoutRegion(icon:CreateTexture(nil, "OVERLAY"))
    bar:SetTexture(WHITE)
    local r, g, b = A3.GetDurationBarColor()
    bar:SetVertexColor(r, g, b, 0.92)
    bar:Hide()
    return bar
end

local function IconZoom(texture, zoom, width, height)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    texture:SetTexCoord(A3.IconShape.IconTexCoords(zoom, width, height))
end
Painter.IconZoom = IconZoom

--- Shared icon art; caller-specific chrome is applied after this base paint.
--- skinWidth/skinHeight size an icon skin when the caller crops the art square
--- (width and height nil) on an icon that is not.
function Painter.Art(icon, texture, background, swipe, art, zoom, width, height, shape, barOnly, style, size, edge,
    skinWidth, skinHeight)
    texture:SetTexture(art)
    IconZoom(texture, zoom, width, height)
    shape = A3.ApplyAuraIconShape(icon, shape, nil, background, texture, swipe)
    background:SetShown(not barOnly)
    texture:SetShown(not barOnly)
    if edge then edge:SetVertexColor(0, 0, 0, 0) end
    -- A skin sizes itself from the icon's real width and height (flat icons).
    local skinned = A3.ApplyIconStyleSkinned(icon, style, size, shape, skinHeight or height, skinWidth or width)
    Painter.SkinLayers(swipe, skinned)
    return shape, skinned
end

--- Live, an icon skin (ARTWORK 5-7, gloss OVERLAY -1) sits under the
--- cooldown swipe, which sits under the duration bar's and the text's frames
--- only in order bar < swipe < text. A preview icon without a skin keeps its
--- swipe on ARTWORK 1 (the frozen preview output); a skinned one lifts it to
--- OVERLAY 4, above the skin, gloss, dispel border (OVERLAY 0-2) and duration
--- bar (OVERLAY), below text on OVERLAY 6/7. Nothing is written while the
--- state is unchanged.
function Painter.SkinLayers(swipe, skinned)
    skinned = skinned == true
    if not swipe or (swipe._msufSkinned == true) == skinned then return end
    swipe._msufSkinned = skinned
    if skinned then swipe:SetDrawLayer("OVERLAY", 4) else swipe:SetDrawLayer("ARTWORK", 1) end
end

--- Justification the live runtime derives from each aura text anchor. Baked into
--- a lookup so per-icon placement costs one table read instead of the runtime's
--- if-chain over anchor strings.
local TEXT_JUSTIFY = {
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

--- Unit/Edit Mode callers supply normalized settings. Mode "WORKBENCH" (the
--- Aura Style workbench) also accepts lowercase anchors and numeric offsets
--- supplied as strings. Mode "POINT_ONLY" (core group previews) normalizes the
--- same way but leaves the text justification alone. No placement record is built.
function Painter.PlaceText(fs, icon, anchor, x, y, mode)
    if not (fs and icon) then return end
    local justify = TEXT_JUSTIFY[anchor]
    if mode then
        if not justify then
            anchor = tostring(anchor or "CENTER"):upper()
            justify = TEXT_JUSTIFY[anchor]
        end
        x, y = tonumber(x) or 0, tonumber(y) or 0
    end
    if not justify then
        if mode ~= "WORKBENCH" then anchor = "CENTER" end
        justify = TEXT_JUSTIFY.CENTER
    end
    fs:ClearAllPoints()
    fs:SetPoint(anchor, icon, anchor, x or 0, y or 0)
    if mode ~= "POINT_ONLY" then
        fs:SetJustifyH(justify[1])
        if fs.SetJustifyV then fs:SetJustifyV(justify[2]) end
    end
end

local DISPEL_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
--- Shaped/typed borders use the live painter. The atlas fallback is retained
--- for clients or fixtures whose border region has only native atlas support.
function Painter.DispelBorder(border, icon, size, mode, shape, index)
    if mode == nil or mode == "OFF" then
        if border then border:Hide() end
        return
    end
    if type(A3.ApplyAuraDispelPreview) == "function"
        and A3.ApplyAuraDispelPreview(border, icon, size, mode, shape,
            A3.PreviewDispelTypeForIndex(index)) then
        return
    end
    local atlas = DISPEL_ATLAS[mode]
    if not (border and icon and atlas and border.SetAtlas) then
        if border then border:Hide() end
        return
    end
    local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
        and A3.NativeAuraDispelBorderPadding(size)
        or max(1, floor((tonumber(size) or 24) / 6 + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetAtlas(atlas, IGNORE_ATLAS_SIZE)
    border:Show()
end

--- Dummy cooldown swipe over a preview aura icon of width x height: the
--- remaining share of the width (8-92 %, a number or nil) from the right edge,
--- or from the left edge when reversed. The unit, group and Edit Mode previews paint it.
function Painter.Swipe(swipe, icon, width, height, remainingFrac, reverse)
    remainingFrac = max(0.08, min(0.92, remainingFrac or 0.48))
    swipe:ClearAllPoints()
    swipe:SetWidth(max(1, floor(width * remainingFrac + 0.5)))
    swipe:SetHeight(max(1, height))
    if reverse == true then
        swipe:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    else
        swipe:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end
end

--- Core group icons keep a static top share of the icon, shown opaque.
function Painter.TopSwipe(swipe, icon, size, share)
    swipe:ClearAllPoints()
    swipe:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, size * share)
    swipe:SetTexture(WHITE)
    swipe:SetVertexColor(0, 0, 0, 0.58)
    swipe:Show()
end

--- Places a preview aura's duration bar inside icon: height px tall on the
--- configured edge (TOP, else bottom), inset px in. With a fill share it
--- covers that share of the inner width from the left edge, otherwise all of
--- it. The Edit Mode and the menu previews share it.
local function LayoutDurationBar(bar, icon, position, height, inset, width, frac)
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if frac then
        bar:SetWidth(max(1, floor(max(1, width - inset * 2) * frac + 0.5)))
        if position == "TOP" then
            bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        else
            bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        end
    elseif position == "TOP" then
        bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
    end
    local r, g, b = A3.GetDurationBarColor()
    bar:SetVertexColor(r, g, b, 0.92)
    bar:Show()
end

Painter.LayoutDurationBar = LayoutDurationBar

--- Core group icons draw the bar full width, one pixel in, opaque, and keep
--- the anchor-before-height order of their pooled regions.
function Painter.GroupDurationBar(bar, icon, position, height)
    bar:ClearAllPoints()
    if position == "TOP" then
        bar:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -1, -1)
    else
        bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
        bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    end
    bar:SetHeight(height)
    bar:SetTexture(WHITE)
    local r, g, b = A3.GetDurationBarColor()
    bar:SetVertexColor(r, g, b, 1)
    bar:Show()
end

--- Dummy duration bar inside a preview aura icon of width x height: the
--- configured height and edge, inset by 1/32 of the icon, and with an aura
--- state the elapsed or remaining share of the width (else the full width).
function Painter.DurationBar(bar, icon, cfg, width, height, auraState)
    local scaleSize = max(1, min(width, height))
    local barHeight = max(1, min(height, floor((tonumber(cfg.durationBarHeight) or 2) + 0.5)))
    local inset = max(1, floor(scaleSize / 32 + 0.5))
    local frac
    if cfg.durationBarDirection == "ELAPSED" then
        frac = auraState and auraState.elapsedFrac or 0.38
    else
        frac = auraState and auraState.remainingFrac or 0.62
    end
    frac = max(0.02, min(1, tonumber(frac) or 0.62))
    LayoutDurationBar(bar, icon, cfg.durationBarPosition, barHeight, inset, width,
        auraState and frac or nil)
end

--- Sample aura state (stacks, timer text, remaining/elapsed share) for one
--- preview icon. The scratch and option tables stay on the icon, so neither a
--- repaint nor an animation tick allocates. A nil elapsed reads the shared
--- static sample; a number follows the animation clock, and a target-dot lane
--- passes its one-shot duration and pandemic window.
function Painter.AuraState(icon, kind, index, cfg, elapsed, duration, oneShot, pandemic)
    local fn
    if elapsed ~= nil then
        local animation = MSUF.PreviewAnimation
        fn = animation and animation.BuildAuraState or BuildPreviewAnimationAuraState
    else
        fn = GetPreviewAnimationAuraState
    end
    local scratch, options = icon._msufAuraScratch, icon._msufAuraOptions
    if not options then
        scratch, options = {}, {}
        icon._msufAuraScratch, icon._msufAuraOptions = scratch, options
    end
    options.decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    options.duration, options.oneShot, options.pandemicThreshold = duration, oneShot, pandemic
    if elapsed ~= nil then return fn(kind, index, scratch, options, elapsed) end
    return fn(kind, index, scratch, options)
end

local AURA_BAR_OUTLINE_SIDES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function AutomaticAuraBarColor(kind, dispelType, mode, inputs)
    local r, g, b
    if dispelType and A3.DispelSymbol.defaultColors[dispelType] then
        r, g, b = A3.GetDispelTypeColor(dispelType, true, inputs)
    elseif kind == "debuff" then
        r, g, b = 0.91, 0.28, 0.23
    else
        r, g, b = 0.28, 0.72, 0.49
    end
    if mode == "DARK" then return 0.05 + 0.36 * r, 0.05 + 0.36 * g, 0.05 + 0.36 * b, 1 end
    return r, g, b, 1
end

function Painter.AuraBarFillColor(lane, dispelType, inputs)
    local appearance = lane.auraBarAppearance
    local mode = appearance and appearance.fillColorMode
    if mode == "CUSTOM" then
        local rgb = appearance.fillColor
        return rgb[1], rgb[2], rgb[3], 0.86
    end
    if mode == "AUTO" or mode == "DARK" then return AutomaticAuraBarColor(lane.kind, dispelType, mode, inputs) end
    if inputs then
        local rgb = inputs.durationColor
        return rgb[1], rgb[2], rgb[3], Painter.AURA_BAR_FILL_ALPHA
    end
    local r, g, b = A3.GetDurationBarColor()
    return r, g, b, Painter.AURA_BAR_FILL_ALPHA
end

local function AuraBarOutlineColor(lane, appearance, dispelType, inputs)
    if appearance.outlineColorMode == "AUTO" then
        return AutomaticAuraBarColor(lane.kind, dispelType, "AUTO", inputs)
    end
    if appearance.outlineColor then
        local rgb = appearance.outlineColor
        return rgb[1], rgb[2], rgb[3], 1
    end
    if appearance.outlineTexture then return 1, 1, 1, 1 end
    return 0, 0, 0, 0.9
end

-- Options are copied by Blizzard at binding. Build at most one palette per
-- lane kind and mode for the current visual inputs, with no addon aura reads.
local tintInputs, tintOptions = nil, {}
local function AuraBarTintOptions(lane, mode)
    local inputs = lane._msufA3NativeVisualInputs
    if tintInputs ~= inputs then
        tintInputs, tintOptions = inputs, {}
    end
    local kind = lane.kind
    local key = kind .. mode
    local options = tintOptions[key]
    if options then return options end
    local fallback = CreateColor(AutomaticAuraBarColor(kind, nil, mode, inputs))
    local map = { None = fallback, [""] = fallback, Enrage = fallback }
    local types = A3.DispelSymbol.types
    for i = 1, #types do
        local token = types[i]
        map[token] = CreateColor(AutomaticAuraBarColor(kind, token, mode, inputs))
    end
    options = { showAlways = true, style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, customDispelColorMap = map }
    tintOptions[key] = options
    return options
end

function Painter.BindAuraBarTints(button, bar, lane, fillTexture)
    local appearance = lane.auraBarAppearance
    if not appearance then return end
    if fillTexture then button:AddDispelTypeTexture(fillTexture, AuraBarTintOptions(lane, appearance.fillColorMode)) end
    if appearance.outlineColorMode ~= "AUTO" then return end
    local pieces = appearance.outlineTexture and bar._msufA3AuraBarEdge or bar._msufA3AuraBarStrips
    local options = AuraBarTintOptions(lane, "AUTO")
    for i = 1, #pieces do button:AddDispelTypeTexture(pieces[i], options) end
end

local function HideOutline(pieces)
    if not pieces then return end
    for i = 1, #pieces do pieces[i]:Hide() end
end

local function LayoutSolidOutline(bar, size, r, g, b, a)
    local strips = bar._msufA3AuraBarStrips
    if not strips then
        strips = {}
        bar._msufA3AuraBarStrips = strips
    end
    for i = 1, #AURA_BAR_OUTLINE_SIDES do
        local strip = strips[i]
        if not strip then
            strip = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY"))
            strip:SetTexture(WHITE)
            strips[i] = strip
        end
        strip:SetVertexColor(r, g, b, a)
        strip:ClearAllPoints()
        MSUF.BorderStyles.LayoutEdgeStrip(strip, bar, AURA_BAR_OUTLINE_SIDES[i], size)
        strip:Show()
    end
end

local function LayoutAuraBarOutline(bar, lane, dispelType, inputs)
    local appearance = lane and lane.auraBarAppearance
    local size = appearance and appearance.outlineSize
    local texture = appearance and appearance.outlineTexture
    if not texture then HideOutline(bar._msufA3AuraBarEdge) end
    if not size or texture then HideOutline(bar._msufA3AuraBarStrips) end
    if not size then return end
    local r, g, b, a = AuraBarOutlineColor(lane, appearance, dispelType, inputs)
    if texture then
        local borders = MSUF.BorderStyles
        local edge = bar._msufA3AuraBarEdge
        if not edge then
            edge = borders.Create(bar, "OVERLAY", 0, texture)
            bar._msufA3AuraBarEdge = edge
        elseif bar._msufA3AuraBarEdgeTexture ~= texture then
            borders.SetTexture(edge, texture)
        end
        bar._msufA3AuraBarEdgeTexture = texture
        borders.Apply(edge, bar, size, appearance.barWidth, appearance.barHeight, r, g, b, a, size * 0.5)
    else
        LayoutSolidOutline(bar, size, r, g, b, a)
    end
end

-- Configure artwork and the visual edge before the timer binds to the bar.
function Painter.LayoutAuraBar(bar, owner, lane, dispelType, inputs)
    local fill, appearance = lane.auraBarFill, lane.auraBarAppearance
    local vertical = fill == "UP" or fill == "DOWN"
    bar:ClearAllPoints()
    if appearance and (appearance.left ~= 0 or appearance.right ~= 0) then
        bar:SetPoint("TOPLEFT", owner, "TOPLEFT", appearance.left, 0)
        bar:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -appearance.right, 0)
    else
        bar:SetAllPoints(owner)
    end
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(fill == "LEFT" or fill == "DOWN")
    local texture = appearance and appearance.texture
    if bar._msufA3AuraBarTexture ~= texture then
        bar:SetStatusBarTexture(texture or WHITE)
        bar._msufA3AuraBarTexture = texture
    end
    LayoutAuraBarOutline(bar, lane, dispelType, inputs)
    local background = bar._msufA3AuraBarBackground
    if not background then
        background = bar:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(bar)
        bar._msufA3AuraBarBackground = background
    end
    local dark = appearance ~= nil and appearance.fillColorMode == "DARK"
    if bar._msufA3DarkBarBackground ~= dark then
        bar._msufA3DarkBarBackground = dark
        local shade = dark and 0.025 or 0.08
        background:SetColorTexture(shade, shade, shade, dark and 0.95 or 0.85)
    end
    background:Show()
end

function Painter.ClearAuraBarDecoration(bar)
    local background = bar._msufA3AuraBarBackground
    if not background then return end
    background:Hide()
    bar:SetOrientation("HORIZONTAL")
    if bar._msufA3AuraBarTexture then
        bar:SetStatusBarTexture(WHITE)
        bar._msufA3AuraBarTexture = nil
    end
    LayoutAuraBarOutline(bar)
end

function Painter.LayoutAuraBarIcon(icon, owner, lane)
    local appearance = lane.auraBarAppearance
    local anchor, size = appearance.iconAnchor, appearance.iconSize
    icon:ClearAllPoints()
    icon:SetPoint(anchor, owner, anchor, appearance.iconX, 0)
    icon:SetSize(size, size)
    Painter.IconZoom(icon, lane.iconZoom, size, size)
    icon:Show()
end

function Painter.LayoutAuraBarName(text, owner, lane)
    text:ClearAllPoints()
    local appearance = lane.auraBarAppearance
    text:SetPoint("LEFT", owner, "LEFT", appearance and appearance.nameLeft or 4, 0)
    text:SetPoint("RIGHT", owner, "RIGHT", -lane.auraBarNameInset, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
end

function Painter.AuraBarSampleName(kind)
    local key = kind == "debuff" and "Debuff" or "Buff"
    return MSUF.L and MSUF.L[key] or key
end

local function EnsureAuraBarSample(owner)
    local bar = owner._msufA3AuraBarSample
    if bar then return bar end
    bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, owner))
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar.name = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    bar.time = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    bar.stacks = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    owner._msufA3AuraBarSample = bar
    return bar
end

local function PaintAuraBarSampleIcon(bar, owner, lane, texture)
    local icon = bar._msufA3AuraBarIcon
    if lane.auraBarAppearance and lane.auraBarAppearance.iconAnchor and texture then
        if not icon then
            icon = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY", nil, 2))
            bar._msufA3AuraBarIcon = icon
        end
        icon:SetTexture(texture)
        Painter.LayoutAuraBarIcon(icon, owner, lane)
    elseif icon then
        icon:Hide()
    end
end

function Painter.PaintAuraBarSample(owner, lane, kind, showText, texture, index)
    local bar = EnsureAuraBarSample(owner)
    local dispelType = kind == "debuff" and A3.PreviewDispelTypeForIndex(index) or nil
    Painter.LayoutAuraBar(bar, owner, lane, dispelType)
    PaintAuraBarSampleIcon(bar, owner, lane, texture)
    bar:SetStatusBarColor(Painter.AuraBarFillColor(lane, dispelType))
    local ApplyFont = A3.ApplyAuraBarFont
    ApplyFont(bar.name, min(12, lane.buttonHeight - 2), lane)
    ApplyFont(bar.time, lane.cooldownSize, lane)
    ApplyFont(bar.stacks, lane.stackSize, lane)
    Painter.LayoutAuraBarName(bar.name, owner, lane)
    bar.name:SetText(Painter.AuraBarSampleName(kind))
    bar.time:ClearAllPoints()
    bar.time:SetPoint("RIGHT", owner, "RIGHT", lane.cooldownX, 0)
    bar.time:SetShown(showText and lane.showCooldownText == true)
    bar.stacks:ClearAllPoints()
    bar.stacks:SetPoint("RIGHT", owner, "RIGHT", lane.stackX, 0)
    bar.stacks:SetShown(showText and lane.showStacks == true)
    bar:Show()
end

function Painter.UpdateAuraBarSample(owner, lane, state)
    local bar = owner._msufA3AuraBarSample
    if not (bar and state) then return end
    local share = lane.durationBarDirection == "ELAPSED" and state.elapsedFrac or state.remainingFrac
    bar:SetValue(share)
    if bar.time:IsShown() then bar.time:SetText(state.text) end
    if bar.stacks:IsShown() then bar.stacks:SetText(state.stacks) end
end

function Painter.HideAuraBarSample(owner)
    local bar = owner._msufA3AuraBarSample
    if bar then bar:Hide() end
end

local SampleButton = {}
local SAMPLE_BINDING_DEFAULTS = {}
local function EmptySampleBinding() end
function SampleButton:CanBeAccessedInContext() return true end
function SampleButton:SetIcon(texture) texture:SetTexture(self.sample.icon) end
function SampleButton:ClearIcon() if self.Icon then self.Icon:Hide() end end
function SampleButton:SetSpellName(fontString) fontString:SetText(self.sample.name) end
SampleButton.ClearSpellName = EmptySampleBinding
function SampleButton:SetDurationBar(bar, options)
    options = options or SAMPLE_BINDING_DEFAULTS
    self.sampleBar, self.sampleBarOptions = bar, options
    bar:SetTimerDuration(self.duration, options.interpolation, options.direction)
end
function SampleButton:GetDurationTextBinding()
    if not self.sampleTextBinding then self.sampleTextBinding = C_DurationUtil.CreateDurationTextBinding() end
    return self.sampleTextBinding
end
function SampleButton:SetDurationText(text, options)
    options = options or SAMPLE_BINDING_DEFAULTS
    local binding = self:GetDurationTextBinding()
    if options.binding then binding:Assign(options.binding) else binding:SetToDefaults() end
    binding:SetFontString(text)
    binding:SetDuration(self.duration)
    local formatter = options.textFormatter or options.formatter
    if formatter then binding:SetFormatter(formatter) end
    if options.textColor then binding:SetTextColorCurve(options.textColor.curve, options.textColor.property) end
    binding:SetEnabled(true)
end
function SampleButton:SetDurationCooldown(cooldown)
    self.sampleCooldown = cooldown
    cooldown:SetCooldownFromDurationObject(self.duration, true)
end
function SampleButton:SetApplicationCount(text)
    local count = self.sample.applications
    text:SetText(count and count > 1 and count or "")
end
function SampleButton:AddDispelTypeTexture(texture, options)
    local dispel = self.sample.dispelName
    local styles, style = Enum.CustomAuraButtonDispelTypeTextureStyle, options.style
    if style == styles.Border or style == styles.BorderWithIcon then
        AuraUtil.SetAuraBorderAtlas(texture, dispel, style == styles.BorderWithIcon)
        texture:SetVertexColor(1, 1, 1, 1)
    elseif style == styles.Icon then
        AuraUtil.SetAuraDispelTypeIcon(texture, dispel)
        texture:SetVertexColor(1, 1, 1, 1)
    elseif style == styles.PreserveAsset then
        AuraUtil.SetAuraBorderColor(texture, dispel)
    end
    local color = options.customDispelColorMap and options.customDispelColorMap[dispel]
    if color then texture:SetVertexColor(color:GetRGBA()) end
    texture:Show()
end
function SampleButton:SetDispelTypeText(text, options)
    local custom = options.customDispelTextMap and options.customDispelTextMap[self.sample.dispelName]
    if custom ~= nil then text:SetText(custom) text:Show()
    else AuraUtil.SetAuraSymbol(text, self.sample.dispelName) end
end
SampleButton.ClearDurationCooldown, SampleButton.ClearDurationBar = EmptySampleBinding, EmptySampleBinding
function SampleButton:ClearDurationText()
    if self.sampleTextBinding then self.sampleTextBinding:SetEnabled(false) end
end
SampleButton.ClearApplicationCount = EmptySampleBinding
SampleButton.ClearDispelTypeTextures, SampleButton.ClearDispelTypeText = EmptySampleBinding, EmptySampleBinding
function SampleButton:SetSample(sample)
    self.sample = sample
    local now = GetTime()
    self.duration:SetTimeSpan(now - sample.duration + sample.remaining, now + sample.remaining)
    if self.sampleBar then self:SetDurationBar(self.sampleBar, self.sampleBarOptions) end
    if self.sampleCooldown then self:SetDurationCooldown(self.sampleCooldown) end
end
function Painter.NewNativeSample(parent, sample)
    local button = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    button:EnableMouse(false)
    for key, method in pairs(SampleButton) do button[key] = method end
    button.duration = C_DurationUtil.CreateDuration()
    button:SetSample(sample)
    return button
end

-- Workbench data is public and retained. Both backends use their own live
-- button construction, placement, swipe, font, shape and duration painters.
local Workbench = {}
Workbench.__index = Workbench
function Painter.NewWorkbench(parent)
    local canvas = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    canvas:SetSize(1, 1)
    canvas:SetPoint("CENTER", parent, "CENTER")
    return setmetatable({ parent = parent, canvas = canvas, buttons = {}, samples = {}, mine = {} }, Workbench)
end
function Workbench:Paint(cfg, count, kind, style, textures)
    local lane = {}
    self.lane = lane
    for key, value in pairs(cfg) do lane[key] = value end
    lane.kind, lane.unit = kind or "buff", "player"
    lane.size = cfg.actualSize or cfg.size
    lane.buttonWidth, lane.buttonHeight = lane.size, lane.size * (cfg.heightPercent or 100) / 100
    lane.stepX, lane.stepY = lane.buttonWidth + (cfg.spacing or 0), lane.buttonHeight + (cfg.spacing or 0)
    lane.step, lane.perRow, lane.padding = lane.stepX, math.max(1, cfg.perRow or count), 0
    local growth = tostring(cfg.growth or "RIGHTDOWN"):upper()
    local left, up = growth:find("LEFT", 1, true), growth:find("UP", 1, true)
    lane.xSign, lane.ySign = left and -1 or 1, up and 1 or -1
    lane.initialAnchor = up and (left and "BOTTOMRIGHT" or "BOTTOMLEFT") or (left and "TOPRIGHT" or "TOPLEFT")
    lane.anchor, lane.verticalGrowth = lane.initialAnchor, growth == "UP" or growth == "DOWN"
    lane.showCooldownSwipe, lane.showCooldownText = cfg.showSwipe ~= false, cfg.showTimers == true
    lane.showCooldown = lane.showCooldownSwipe or lane.showCooldownText
    lane.showAuraBorder = kind == "debuff" and cfg.debuffBorderMode ~= "OFF"
    lane.showAuraSymbol = lane.showAuraBorder and cfg.debuffBorderMode == "SYMBOL"
    lane.showDispelTypeBorder, lane.showDispelTypeSymbol = lane.showAuraBorder, lane.showAuraSymbol
    lane.showTooltip, lane.iconStyle = false, style
    if cfg.auraBar then
        for key, value in pairs(cfg.auraBar) do lane[key] = value end
        lane.showTooltip = false
    elseif cfg.auraBarFill then
        lane.max = cfg.maxIcons
        MSUF.AuraConfig.ApplyAuraBarGeometry(lane, cfg.auraBarFill, cfg.compactAuraBars, cfg.auraBarStyle)
    end
    self.config, self.frame = lane, self.canvas
    local native = A3.Runtime and A3.Runtime.ButtonVisuals
    local classic = not native and A3._ClassicBackend.Buttons
    for i = 1, count do
        local sample = self.samples[i] or {}
        self.samples[i] = sample
        sample.index, sample.duration, sample.remaining = i, 20, i % 2 == 0 and 12 or 2.7
        sample.expirationTime, sample.applications = GetTime() + sample.remaining, i % 3 == 1 and 2 or 0
        sample.auraInstanceID = i
        sample.dispelName = (kind == "debuff" or not lane.auraBarFill) and A3.PreviewDispelTypeForIndex(i) or nil
        sample.icon = textures[((i - 1) % #textures) + 1]
        if lane.auraBarFill then sample.name = Painter.AuraBarSampleName(kind) end
        sample.pandemic = cfg.pandemicEnabled == true and i == 1
        local button = self.buttons[i]
        if native then
            if not button then button = Painter.NewNativeSample(self.canvas, sample) self.buttons[i] = button end
            native.LayoutSample(button, lane, i)
            native.PaintSample(button, lane, i, sample)
        else
            button = classic.EnsureButton(self, i)
            self.buttons[i] = button
            classic.PaintSample(self, button, sample)
        end
    end
    for i = count + 1, #self.buttons do
        if classic then classic.HideButton(self.buttons[i]) else self.buttons[i]:Hide() end
    end
    self.canvas:SetScale(1)
    local l, b, r, t
    for i = 1, count do
        local x, y, w, h = self.buttons[i]:GetRect()
        if x then
            l, b, r, t = math.min(l or x, x), math.min(b or y, y), math.max(r or x, x + w), math.max(t or y, y + h)
        end
    end
    local x, y = self.canvas:GetCenter()
    self.offsetX, self.offsetY = x and l and ((l + r) / 2 - x) or 0, y and b and ((b + t) / 2 - y) or 0
    self.width, self.height = l and math.max(1, r - l) or 1, b and math.max(1, t - b) or 1
    return self.width, self.height
end
function Workbench:Fit(scale)
    self.canvas:SetScale(scale)
    self.canvas:ClearAllPoints()
    self.canvas:SetPoint("CENTER", self.parent, "CENTER", -self.offsetX * scale, -self.offsetY * scale)
end

function Workbench:PreviewEntrance(enabled)
    if self.motionEnabled == enabled then return end
    self.motionEnabled = enabled
    local button = self.buttons[1]
    if not button or not button.CreateAnimationGroup then return end
    if not enabled then
        if self.entrance then self.entrance:Stop() end
        return
    end
    if not self.entrance then
        self.entrance = button:CreateAnimationGroup()
        local fade = self.entrance:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetDuration(REFLOW_SECONDS)
        fade:SetSmoothing("OUT")
    end
    self.entrance:Play()
end
