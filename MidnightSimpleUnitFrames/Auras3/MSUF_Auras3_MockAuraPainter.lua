--- Auras3 mock icon painting shared by the menu and on-screen previews.
--- Callers own pools, geometry, fonts, samples and lifecycle. These painters
--- only update their supplied regions; they create no frames and register no
--- events, unit watch, secure attributes or click handling. The one table pair
--- they keep is the sample-state scratch on the icon that asked for it.
local _, MSUF = ...
local A3 = assert(MSUF.MSUF_Auras3)
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Auras3/MockAuraPainter")
-- Preview sample builders (UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua loads first).
local BuildPreviewAnimationAuraState = MSUF.Require("MSUF_BuildPreviewAnimationAuraState", "Auras3/MockAuraPainter")
local GetPreviewAnimationAuraState = MSUF.Require("MSUF_GetPreviewAnimationAuraState", "Auras3/MockAuraPainter")
local WHITE = "Interface\\Buttons\\WHITE8X8"
local IGNORE_ATLAS_SIZE = TextureKitConstants and TextureKitConstants.IgnoreAtlasSize
local type, tonumber, tostring = type, tonumber, tostring
local floor, max, min = math.floor, math.max, math.min
local Painter = {}
A3.MockAuraPainter = Painter

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

local SampleButton = {}
local SAMPLE_BINDING_DEFAULTS = {}
local function EmptySampleBinding() end
function SampleButton:CanBeAccessedInContext() return true end
function SampleButton:SetIcon(texture) texture:SetTexture(self.sample.icon) end
function SampleButton:ClearIcon() if self.Icon then self.Icon:Hide() end end
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
    self.config, self.frame = lane, self.canvas
    local native = A3.Runtime and A3.Runtime.ButtonVisuals
    local classic = not native and A3._ClassicBackend.Buttons
    for i = 1, count do
        local sample = self.samples[i] or {}
        self.samples[i] = sample
        sample.index, sample.duration, sample.remaining = i, 20, i % 2 == 0 and 12 or 2.7
        sample.expirationTime, sample.applications = GetTime() + sample.remaining, i % 3 == 1 and 2 or 0
        sample.auraInstanceID, sample.dispelName = i, A3.PreviewDispelTypeForIndex(i)
        sample.icon = textures[((i - 1) % #textures) + 1]
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
