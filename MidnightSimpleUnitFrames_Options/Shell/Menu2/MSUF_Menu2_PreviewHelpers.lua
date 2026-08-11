local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local F = M.Fallbacks or {}
local H = M.PreviewHelpers or {}
M.PreviewHelpers = H
local CP = M.ClassPowerPreview or {}
M.ClassPowerPreview = CP

-- Shared Menu2 preview helpers.
-- Centralizes mock class-power colors, shape helpers, and small rendering utilities used by
-- preview modules. Keep preview-only fallbacks here instead of coupling pages to live runtime.
local floor = math.floor
local min = math.min
CP.WHITE8 = CP.WHITE8 or "Interface\\Buttons\\WHITE8X8"
CP.MEDIA = CP.MEDIA or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\ClassPower\\")
local ROUNDED_MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local ROUNDED_SLICE_MARGIN = 9.5
local ROUNDED_MASK_PATHS, ROUNDED_EDGE_PATHS = {}, {}
for i = 1, 5 do
    ROUNDED_MASK_PATHS[i] = ROUNDED_MEDIA_ROOT .. "rounded_clean_mask_s" .. i .. ".png"
    ROUNDED_EDGE_PATHS[i] = ROUNDED_MEDIA_ROOT .. "rounded_clean_edge_s" .. i .. ".png"
end
local STRETCHED_SLICE_MODE = _G.Enum and _G.Enum.UITextureSliceMode
    and _G.Enum.UITextureSliceMode.Stretched
local PREVIEW_BACKGROUND_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\PreviewBackgrounds\\"
-- Onboarding tour screenshots. They live beside the preview backgrounds in the
-- Options companion and deliberately stay out of `T.media`: theme media must
-- resolve against the core addon (options_lod_namespace_media_smoke). Every
-- entry is authored 2:1 so a tour card can size it from its width alone.
local TOUR_PREVIEW_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\Tour\\"
H.TourPreviews = {
    rounded_frames = { texture = TOUR_PREVIEW_MEDIA .. "rounded_frames.png", aspect = 2 },
}

-- Full Unit/Group previews use the exact clean media family selected by the
-- live rounded runtime. Resolving this only while a preview is repainted keeps
-- slider feedback accurate without putting any work on gameplay paths.
function H.ResolveRoundedMedia()
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local strength = floor((tonumber(bars and bars.roundedCornerStrength) or 3) + 0.5)
    if strength < 1 then strength = 1 elseif strength > 5 then strength = 5 end
    return ROUNDED_MASK_PATHS[strength], ROUNDED_EDGE_PATHS[strength], strength
end

function H.ApplyRoundedMediaSlice(region, strength)
    if not region then return end
    strength = tonumber(strength) or 3
    if region._msufPreviewRoundedSliceStrength == strength then return end
    region._msufPreviewRoundedSliceStrength = strength
    if type(region.SetTextureSliceMargins) == "function" then
        region:SetTextureSliceMargins(ROUNDED_SLICE_MARGIN, ROUNDED_SLICE_MARGIN,
            ROUNDED_SLICE_MARGIN, ROUNDED_SLICE_MARGIN)
    end
    if STRETCHED_SLICE_MODE ~= nil and type(region.SetTextureSliceMode) == "function" then
        region:SetTextureSliceMode(STRETCHED_SLICE_MODE)
    end
end
local PREVIEW_BACKGROUND_DEFAULT = "silvermoon"
local PREVIEW_BACKGROUND_ASPECT = 2
local PREVIEW_BACKGROUND_CLEAR = { 0, 0, 0, 0 }
local PREVIEW_BACKGROUND_CUSTOM_DEFAULT = { 0.08, 0.12, 0.18, 1 }
local PREVIEW_BACKGROUND_SPECS = {
    {
        key = "bright_stone",
        label = "Bright stone",
        tooltip = "A bright surface for checking dark borders and text.",
        texture = PREVIEW_BACKGROUND_MEDIA .. "bright_stone.png",
    },
    {
        key = "city_scene",
        label = "City scene",
        tooltip = "A mixed game scene for checking readability in normal play.",
        texture = PREVIEW_BACKGROUND_MEDIA .. "city_scene.png",
    },
    {
        key = "dark_stone",
        label = "Dark stone",
        tooltip = "A dark surface for checking bright borders and text.",
        texture = PREVIEW_BACKGROUND_MEDIA .. "dark_stone.png",
    },
    {
        key = "silvermoon",
        label = "Silvermoon",
        tooltip = "A colored Silvermoon interior for checking frames on tinted surfaces.",
        texture = PREVIEW_BACKGROUND_MEDIA .. "silvermoon.png",
    },
    {
        key = "custom",
        label = "Custom",
        tooltip = "Choose a solid custom color for the preview background.",
        customColor = true,
    },
    {
        key = "studio",
        label = "Studio",
        tooltip = "The original neutral preview gradient.",
        swatchColor = { 0.020, 0.039, 0.071, 1 },
    },
}
local PREVIEW_BACKGROUND_BY_KEY = {}
for i = 1, #PREVIEW_BACKGROUND_SPECS do
    local spec = PREVIEW_BACKGROUND_SPECS[i]
    PREVIEW_BACKGROUND_BY_KEY[spec.key] = spec
end
local PREVIEW_BACKGROUND_CANVASES = setmetatable({}, { __mode = "k" })
local PREVIEW_BACKGROUND_BUTTONS = setmetatable({}, { __mode = "k" })
function CP.ShapeTextures(prefix, axis)
    local tex = { fill = CP.MEDIA .. prefix .. "_fill.tga", bg = CP.MEDIA .. prefix .. "_bg.tga", edge = CP.MEDIA .. prefix .. "_edge.tga" }
    tex.axis = axis
    return tex
end
local function PreviewBackgroundText(text)
    local tr = M.TranslateText or M.Tr
    return type(tr) == "function" and tr(text) or text
end
local function PreviewBackgroundSpec()
    local key = tostring(M.previewBackground or PREVIEW_BACKGROUND_DEFAULT)
    return PREVIEW_BACKGROUND_BY_KEY[key] or PREVIEW_BACKGROUND_BY_KEY[PREVIEW_BACKGROUND_DEFAULT]
end
local function ClampPreviewColor(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function PreviewBackgroundCustomRGB()
    return ClampPreviewColor(M.previewBackgroundCustomR, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[1]),
        ClampPreviewColor(M.previewBackgroundCustomG, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[2]),
        ClampPreviewColor(M.previewBackgroundCustomB, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[3])
end
local function PreviewBackgroundSwatch(spec)
    if spec and spec.customColor then
        local r, g, b = PreviewBackgroundCustomRGB()
        return r, g, b, 1
    end
    local color = spec and spec.swatchColor or PREVIEW_BACKGROUND_CUSTOM_DEFAULT
    return color[1], color[2], color[3], color[4] or 1
end
function H.GetPreviewBackground()
    local spec = PreviewBackgroundSpec()
    return spec.key, spec
end
local function PaintPreviewStudioGradient(gradient, palette, theme)
    if not (gradient and palette) then return end
    if theme and type(theme.ApplyTextureGradient) == "function" then
        theme.ApplyTextureGradient(gradient, "VERTICAL", palette.canvasTop, palette.canvasBottom)
    elseif gradient.SetGradientAlpha then
        gradient:SetGradientAlpha("VERTICAL",
            palette.canvasTop[1], palette.canvasTop[2], palette.canvasTop[3], palette.canvasTop[4],
            palette.canvasBottom[1], palette.canvasBottom[2], palette.canvasBottom[3], palette.canvasBottom[4])
    elseif gradient.SetColorTexture then
        gradient:SetColorTexture(palette.canvasBg[1], palette.canvasBg[2], palette.canvasBg[3], palette.canvasBg[4])
    end
end
local function PaintPreviewCanvasBackdrop(frame, color, green, blue, alpha)
    if not (frame and color) then return end
    local red
    if type(color) == "table" then
        red, green, blue, alpha = color[1], color[2], color[3], color[4]
    else
        red = color
    end
    if frame.SetBackdropColor then
        frame:SetBackdropColor(red, green, blue, alpha or 1)
    elseif frame._msuf2Bg and frame._msuf2Bg.SetColorTexture then
        frame._msuf2Bg:SetColorTexture(red, green, blue, alpha or 1)
    end
end
local function UpdatePreviewBackgroundButton(button)
    if not button then return end
    local spec = PreviewBackgroundSpec()
    local preview = button._msuf2PreviewBackgroundTexture
    if preview then
        preview:SetTexture(spec.texture or CP.WHITE8)
        local r, g, b, a
        if spec.texture then
            r, g, b, a = 1, 1, 1, 1
        else
            r, g, b, a = PreviewBackgroundSwatch(spec)
        end
        preview:SetVertexColor(r, g, b, a)
    end
    button._msuf2DropdownListValue = spec.key
    button._msuf2PreviewBackgroundSpec = spec
end
local function CropPreviewBackground(frame)
    local image = frame and frame._msuf2PreviewCanvasImage
    if not (image and image.SetTexCoord and frame.GetWidth and frame.GetHeight) then return end
    local width, height = tonumber(frame:GetWidth()) or 0, tonumber(frame:GetHeight()) or 0
    if width <= 0 or height <= 0 then
        image:SetTexCoord(0, 1, 0, 1)
        return
    end
    local aspect = width / height
    if aspect > PREVIEW_BACKGROUND_ASPECT then
        local visible = PREVIEW_BACKGROUND_ASPECT / aspect
        local crop = (1 - visible) * 0.5
        image:SetTexCoord(0, 1, crop, 1 - crop)
    else
        local visible = aspect / PREVIEW_BACKGROUND_ASPECT
        local crop = (1 - visible) * 0.5
        image:SetTexCoord(crop, 1 - crop, 0, 1)
    end
end
function H.ApplyPreviewBackground(frame, palette, theme)
    if not (frame and palette) then return end
    local spec = PreviewBackgroundSpec()
    local image = frame._msuf2PreviewCanvasImage
    if not image and frame.CreateTexture then
        image = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        image:SetAllPoints(frame)
        frame._msuf2PreviewCanvasImage = image
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function(self) CropPreviewBackground(self) end)
        end
    end
    local gradient = frame._msuf2PreviewCanvasGradient
    if spec.texture and image then
        -- The canvas backdrop is intentionally opaque for the original Studio
        -- view. Make it fully transparent for scene textures so it cannot sit
        -- above the image and read as a dark film.
        PaintPreviewCanvasBackdrop(frame, PREVIEW_BACKGROUND_CLEAR)
        image:SetTexture(spec.texture)
        image:SetVertexColor(1, 1, 1, 1)
        CropPreviewBackground(frame)
        image:Show()
        if gradient and gradient.SetColorTexture then
            gradient:SetColorTexture(0, 0, 0, 0)
        end
    elseif spec.customColor then
        if image then image:Hide() end
        local r, g, b = PreviewBackgroundCustomRGB()
        PaintPreviewCanvasBackdrop(frame, r, g, b, 1)
        if gradient and gradient.SetColorTexture then gradient:SetColorTexture(0, 0, 0, 0) end
    else
        if image then image:Hide() end
        PaintPreviewCanvasBackdrop(frame, palette.canvasBg)
        PaintPreviewStudioGradient(gradient, palette, theme)
    end
    PREVIEW_BACKGROUND_CANVASES[frame] = { palette = palette, theme = theme }
end
local function RefreshPreviewBackgrounds()
    for frame, state in pairs(PREVIEW_BACKGROUND_CANVASES) do
        H.ApplyPreviewBackground(frame, state.palette, state.theme)
    end
    for button in pairs(PREVIEW_BACKGROUND_BUTTONS) do UpdatePreviewBackgroundButton(button) end
end
function H.SetPreviewBackground(key)
    local spec = PREVIEW_BACKGROUND_BY_KEY[tostring(key or "")]
    if not spec then return false end
    if type(M.SetMenuStateValue) == "function" then
        M.SetMenuStateValue("previewBackground", spec.key)
    else
        M.previewBackground = spec.key
    end
    RefreshPreviewBackgrounds()
    return true
end
local PREVIEW_BACKGROUND_CUSTOM_OWNER = {
    _msuf2ColorLabel = "Custom preview background",
}
function PREVIEW_BACKGROUND_CUSTOM_OWNER:GetRGB()
    return PreviewBackgroundCustomRGB()
end
function PREVIEW_BACKGROUND_CUSTOM_OWNER:SetRGB(r, g, b)
    M.previewBackgroundCustomR = ClampPreviewColor(r, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[1])
    M.previewBackgroundCustomG = ClampPreviewColor(g, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[2])
    M.previewBackgroundCustomB = ClampPreviewColor(b, PREVIEW_BACKGROUND_CUSTOM_DEFAULT[3])
end
function PREVIEW_BACKGROUND_CUSTOM_OWNER:IsEnabled()
    return true
end
PREVIEW_BACKGROUND_CUSTOM_OWNER._msuf2OnColorChanged = function(r, g, b)
    PREVIEW_BACKGROUND_CUSTOM_OWNER:SetRGB(r, g, b)
    RefreshPreviewBackgrounds()
end
local function PersistPreviewBackgroundCustomColor()
    local state = type(M.EnsurePersistentMenuState) == "function" and M.EnsurePersistentMenuState() or nil
    if type(state) == "table" then
        state.previewBackgroundCustomR = M.previewBackgroundCustomR
        state.previewBackgroundCustomG = M.previewBackgroundCustomG
        state.previewBackgroundCustomB = M.previewBackgroundCustomB
        return
    end
    local persist = M.SetMenuStateValue or M.PersistMenuStateValue
    if type(persist) ~= "function" then return end
    persist("previewBackgroundCustomR", M.previewBackgroundCustomR)
    persist("previewBackgroundCustomG", M.previewBackgroundCustomG)
    persist("previewBackgroundCustomB", M.previewBackgroundCustomB)
end
function H.OpenPreviewBackgroundColorPicker()
    local widgets = M.Widgets
    if not (widgets and type(widgets.OpenColorContextPicker) == "function") then return false end
    widgets.OpenColorContextPicker(
        PreviewBackgroundText("Custom preview background"),
        { PREVIEW_BACKGROUND_CUSTOM_OWNER },
        PreviewBackgroundText("Choose a solid color. Changes are shown live in every preview."),
        PREVIEW_BACKGROUND_CUSTOM_OWNER,
        PersistPreviewBackgroundCustomColor,
        PreviewBackgroundText("Preview background")
    )
    return true
end
local function PreviewBackgroundDropdownValues()
    local values = {}
    for i = 1, #PREVIEW_BACKGROUND_SPECS do
        local spec = PREVIEW_BACKGROUND_SPECS[i]
        local item = {
            value = spec.key,
            text = spec.label,
            tooltip = spec.tooltip,
        }
        if spec.texture then
            item.previewKind = "statusbar"
            item.texture = spec.texture
        else
            local r, g, b, a = PreviewBackgroundSwatch(spec)
            item.swatchColor = { r, g, b, a }
        end
        values[i] = item
    end
    return values
end
function H.EnsurePreviewBackgroundButton(box, zoomBar, opts)
    if not (box and zoomBar and CreateFrame) then return nil end
    local field = (opts and opts.fieldPrefix or "") .. "previewBackgroundButton"
    local existing = box[field]
    if existing then
        UpdatePreviewBackgroundButton(existing)
        return existing
    end
    local button = CreateFrame("Button", nil, zoomBar, "BackdropTemplate")
    button:SetSize(46, 20)
    zoomBar._msuf2PreviewBackgroundButton = button
    button._msuf2DropdownPreferredWidth = 260
    button._msuf2DropdownClampFrame = M.frame or _G.UIParent
    -- Keep the selector on its own row: Unit, Group, and Class Resources all
    -- place animation/role controls immediately to the left of the zoom bar.
    button:SetPoint("TOPRIGHT", zoomBar, "BOTTOMRIGHT", 0, -4)
    if button.SetBackdrop then
        button:SetBackdrop({ bgFile = CP.WHITE8, edgeFile = CP.WHITE8, edgeSize = 1 })
        button:SetBackdropColor(0.010, 0.018, 0.030, 0.96)
        button:SetBackdropBorderColor(0.18, 0.28, 0.42, 0.92)
    end
    local preview = button:CreateTexture(nil, "ARTWORK")
    preview:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    preview:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -12, 2)
    button._msuf2PreviewBackgroundTexture = preview
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("RIGHT", button, "RIGHT", -3, 0)
    arrow:SetSize(8, 8)
    arrow:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_dropdown_chevron_down.tga")
    arrow:SetVertexColor(0.86, 0.92, 1.00, 1)
    button._msuf2PreviewBackgroundArrow = arrow
    button:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.32, 0.66, 0.96, 1) end
        local tooltip = _G.GameTooltip
        if tooltip then
            local spec = self._msuf2PreviewBackgroundSpec or PreviewBackgroundSpec()
            tooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltip:SetText(PreviewBackgroundText("Preview background"), 1, 1, 1)
            tooltip:AddLine(PreviewBackgroundText(spec.label), 0.62, 0.84, 1.00)
            tooltip:AddLine(PreviewBackgroundText("Choose a background to check frame readability on bright and dark game surfaces."), 0.80, 0.86, 1.00, true)
            tooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.18, 0.28, 0.42, 0.92) end
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        local widgets = M.Widgets
        if widgets and type(widgets.OpenDropdown) == "function" then
            widgets.OpenDropdown(self, PreviewBackgroundDropdownValues(), PreviewBackgroundSpec().key, function(value)
                H.SetPreviewBackground(value)
                if value == "custom" then H.OpenPreviewBackgroundColorPicker() end
            end)
            return
        end
        local current = PreviewBackgroundSpec().key
        local nextIndex = 1
        for i = 1, #PREVIEW_BACKGROUND_SPECS do
            if PREVIEW_BACKGROUND_SPECS[i].key == current then
                nextIndex = (i % #PREVIEW_BACKGROUND_SPECS) + 1
                break
            end
        end
        local nextKey = PREVIEW_BACKGROUND_SPECS[nextIndex].key
        H.SetPreviewBackground(nextKey)
        if nextKey == "custom" then H.OpenPreviewBackgroundColorPicker() end
    end)
    box[field] = button
    PREVIEW_BACKGROUND_BUTTONS[button] = true
    UpdatePreviewBackgroundButton(button)
    return button
end
CP.CLASS_SHAPES = CP.CLASS_SHAPES or {
    CIRCLE = CP.ShapeTextures("pip_circle"),
    DIAMOND = CP.ShapeTextures("pip_diamond"),
    HEX = CP.ShapeTextures("pip_hex"),
}
CP.POWER_SHAPES = CP.POWER_SHAPES or {
    ROUND = CP.ShapeTextures("power_round"),
    CRYSTAL = CP.ShapeTextures("power_crystal"),
    ORB = CP.ShapeTextures("pip_circle", "VERTICAL"),
}
function CP.NormalizeClassShape(value)
    value = tostring(value or "BAR"):upper()
    return (value == "CIRCLE" or value == "DIAMOND" or value == "HEX") and value or "BAR"
end
function CP.ResolvePowerShape(value, classShape)
    value = tostring(value or "BAR"):upper()
    if value == "ROUND" or value == "CRYSTAL" or value == "ORB" or value == "BAR" then return value end
    if value == "FOLLOW_CLASS" then
        classShape = CP.NormalizeClassShape(classShape)
        if classShape == "CIRCLE" then return "ROUND" end
        if classShape == "DIAMOND" or classShape == "HEX" then return "CRYSTAL" end
    end
    return "BAR"
end
local DETACHED_POWER_WIDTH_FRAMES = {
    cooldown = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}
local function PreviewFrameWidth(frame)
    if not (frame and frame.GetWidth) then return nil end
    if frame._msufLegacyCooldownAnchor == true then return nil end
    if frame.IsShown and not frame:IsShown() then return nil end
    local width = frame:GetWidth()
    if type(width) == "number" and width > 1 then return width end
    return nil
end
local function PreviewExternalFrameWidth(frameName, relativeTo)
    local common = MSUF and MSUF.UFBarTextCommon
    local resolve = common and common.ExternalFrameWidth
    if type(resolve) == "function" then return resolve(frameName, relativeTo) end
    local resolver = _G.MSUF_GetEffectiveCooldownFrame
    local source = type(resolver) == "function" and resolver(frameName) or nil
    return PreviewFrameWidth(source or _G[frameName])
end
local function ClampDetachedPowerWidth(value, fallback, minValue, maxValue)
    value = tonumber(value) or tonumber(fallback) or 1
    minValue, maxValue = minValue or 20, maxValue or 800
    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
    return floor(value + 0.5)
end
function CP.ResolveDetachedPowerWidth(opts)
    opts = opts or {}
    if tostring(opts.shape or "BAR"):upper() == "ORB" then
        return ClampDetachedPowerWidth(opts.orbSize, 54, 20, 160)
    end
    local liveFrame, livePower = opts.liveFrame, opts.livePower
    local powerElement = MSUF and MSUF.UF and MSUF.UF.Elements and MSUF.UF.Elements.Power
    local liveResolver = powerElement and powerElement.ResolveDetachedWidth
    if liveFrame and livePower and type(liveResolver) == "function" then
        -- Unit Preview must not maintain a second width policy. When the live
        -- unit exists, consume the same resolver and its per-bar combat cache.
        return liveResolver(liveFrame, livePower)
    end
    -- Mirrors the live resolver's precedence: the Detached width mode, then a
    -- matched Class Resource bar, then a Detached width configured on this
    -- frame, then the shared Class Resource width mode as the sync fallback.
    local frameName = opts.widthFrameName
    if type(frameName) ~= "string" or frameName == "" then
        local cdmFrames = _G.MSUF_CP_CONST and _G.MSUF_CP_CONST.CDM_FRAMES or DETACHED_POWER_WIDTH_FRAMES
        frameName = cdmFrames and cdmFrames[opts.widthMode]
    end
    if type(frameName) == "string" and frameName ~= "" then
        local sourceWidth = PreviewExternalFrameWidth(frameName, opts.relativeTo)
        if sourceWidth then return ClampDetachedPowerWidth(sourceWidth) end
    end
    if opts.syncClass == true then
        local classWidth = tonumber(opts.classWidth)
        if classWidth and classWidth > 1 then return ClampDetachedPowerWidth(classWidth) end
    end
    local explicitWidth = tonumber(opts.explicitWidth)
    if explicitWidth then return ClampDetachedPowerWidth(explicitWidth) end
    if opts.syncClass == true then
        local classWidth = tonumber(opts.classFallbackWidth)
        if classWidth and classWidth > 1 then return ClampDetachedPowerWidth(classWidth) end
    end
    return ClampDetachedPowerWidth(opts.manualWidth, opts.frameWidth)
end
CP.FALLBACK_COLORS = CP.FALLBACK_COLORS or {
    ARCANE_CHARGES = { 0.45, 0.55, 1.00 },
    CHARGED = { 0.60, 0.20, 0.80 },
    CHI = { 0.70, 1.00, 0.86 },
    COMBO_POINTS = { 1.00, 0.82, 0.10 },
    EBON_MIGHT = { 0.40, 0.80, 0.60 },
    ESSENCE = { 0.32, 0.74, 1.00 },
    HOLY_POWER = { 0.95, 0.86, 0.20 },
    IRONFUR = { 1.00, 0.49, 0.04 },
    INSANITY = { 0.55, 0.32, 0.95 },
    MAELSTROM = { 0.00, 0.55, 1.00 },
    MAELSTROM_ABOVE_5 = { 1.00, 0.50, 0.00 },
    RUNES = { 0.55, 0.85, 1.00 },
    SOUL_FRAGMENTS = { 0.00, 0.80, 0.00 },
    SOUL_FRAGMENTS_META = { 0.60, 0.20, 0.93 },
    SOUL_FRAGMENTS_VENG = { 0.34, 0.06, 0.46 },
    SOUL_SHARDS = { 0.58, 0.28, 0.92 },
    STAGGER_GREEN = { 0.52, 1.00, 0.52 },
    STAGGER_YELLOW = { 1.00, 0.98, 0.72 },
    STAGGER_RED = { 1.00, 0.42, 0.42 },
    TIP_OF_THE_SPEAR = { 0.60, 0.80, 0.20 },
    WHIRLWIND = { 0.20, 0.80, 0.20 },
}
CP.COMBO_POINT_SLOT_TOKENS = CP.COMBO_POINT_SLOT_TOKENS or {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}
local COMBO_POINT_RAMP_R = CP.COMBO_POINT_RAMP_R or { 0.00, 0.00, 1.00, 1.00, 1.00, 1.00, 1.00 }
local COMBO_POINT_RAMP_G = CP.COMBO_POINT_RAMP_G or { 0.95, 0.95, 1.00, 1.00, 1.00, 0.05, 0.05 }
local COMBO_POINT_RAMP_B = CP.COMBO_POINT_RAMP_B or { 1.00, 1.00, 0.00, 0.00, 0.00, 0.05, 0.05 }
CP.COMBO_POINT_RAMP_R, CP.COMBO_POINT_RAMP_G, CP.COMBO_POINT_RAMP_B = COMBO_POINT_RAMP_R, COMBO_POINT_RAMP_G, COMBO_POINT_RAMP_B
function CP.ColorOverride(tableName, token)
    local db = _G.MSUF_DB
    local general = db and db.general
    local overrides = general and general[tableName]
    local c = overrides and token and overrides[token]
    if type(c) ~= "table" then return nil end
    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end
function CP.ResolveColor(token, fallbackR, fallbackG, fallbackB, powerColorFn)
    -- User overrides should show in preview, then fall back to runtime power-color helpers,
    -- and finally to fixed preview colors when the real runtime is unavailable.
    local r, g, b = CP.ColorOverride("classPowerColorOverrides", token)
    if r then return r, g, b end
    if type(_G.MSUF_GetPowerBarColor) == "function" and token then
        r, g, b = _G.MSUF_GetPowerBarColor(0, token)
        if type(r) == "number" then return r, g, b end
    end
    local pbc = _G.PowerBarColor
    local c = pbc and token and pbc[token]
    if c then
        r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
        if type(r) == "number" then return r, g, b end
    end
    c = token and CP.FALLBACK_COLORS[token]
    if c then return c[1], c[2], c[3] end
    if type(powerColorFn) == "function" and token then
        r, g, b = powerColorFn(token)
        if type(r) == "number" then return r, g, b end
    end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
function CP.ResolveBaseColor(spec, bars, fallbackR, fallbackG, fallbackB, powerColorFn)
    if bars and bars.classPowerColorByType == false then return 1, 1, 1 end
    return CP.ResolveColor(spec and spec.token, fallbackR, fallbackG, fallbackB, powerColorFn)
end
function CP.ResolveTextColor(fallbackR, fallbackG, fallbackB, powerColorFn)
    return CP.ResolveColor("RESOURCE_TEXT", fallbackR or 1, fallbackG or 1, fallbackB or 1, powerColorFn)
end
function CP.ResolveSlotColor(bars, resourceToken, slot, baseR, baseG, baseB)
    local modes = bars and bars.classPowerSlotColorModes
    local mode = type(modes) == "table" and modes[resourceToken] or nil
    if mode == nil and resourceToken == "COMBO_POINTS" then mode = bars and bars.classPowerComboPointColorMode end
    if mode ~= "ramp" and mode ~= "custom" then return baseR, baseG, baseB end
    slot = tonumber(slot) or 1
    if slot < 1 then slot = 1 elseif slot > 10 then slot = 10 end
    if mode == "custom" then
        local slotToken = resourceToken == "COMBO_POINTS" and CP.COMBO_POINT_SLOT_TOKENS[slot]
            or (resourceToken and (resourceToken .. "_" .. tostring(slot)))
        local r, g, b = CP.ColorOverride("classPowerColorOverrides", slotToken)
        if r then return r, g, b end
        if resourceToken ~= "COMBO_POINTS" then return baseR, baseG, baseB end
    end
    local rampSlot = slot > 7 and 7 or slot
    return COMBO_POINT_RAMP_R[rampSlot] or baseR, COMBO_POINT_RAMP_G[rampSlot] or baseG, COMBO_POINT_RAMP_B[rampSlot] or baseB
end
function CP.ResolveComboColor(bars, slot, baseR, baseG, baseB)
    return CP.ResolveSlotColor(bars, "COMBO_POINTS", slot, baseR, baseG, baseB)
end
function CP.ResolveFullColor(bars, resourceToken, baseR, baseG, baseB)
    local enabled = bars and bars.classPowerFullColorEnabled
    if not (type(enabled) == "table" and enabled[resourceToken] == true) then
        return false, baseR, baseG, baseB
    end
    local r, g, b = CP.ColorOverride("classPowerColorOverrides", tostring(resourceToken) .. "_FULL")
    return true, r or baseR, g or baseG, b or baseB
end
function CP.IsFull(spec, valueOverride)
    if not spec or CP.IsSingleBarMode(spec.mode) then return false end
    local maxValue = floor(tonumber(spec.segments) or 0)
    local value = tonumber(valueOverride)
    if value == nil then value = tonumber(spec.value) or 0 end
    return maxValue > 0 and value >= maxValue
end
function CP.IsCharged(spec, bars, slot)
    return spec and spec.token == "COMBO_POINTS"
        and bars and bars.showChargedComboPoints ~= false
        and spec.chargedSlots and spec.chargedSlots[slot] == true
end
function CP.IsSingleBarMode(mode)
    return mode == "continuous" or mode == "timer_bar" or mode == "stagger" or mode == "aura_single" or mode == "ironfur"
end
function CP.IsEssence(spec)
    return spec and spec.token == "ESSENCE"
end
function CP.TokenForValue(spec, value)
    if spec and spec.mode == "stagger" then
        value = tonumber(value)
        if value == nil then value = tonumber(spec.value) or 0 end
        if value >= 0.60 then return "STAGGER_RED" end
        if value > 0.30 then return "STAGGER_YELLOW" end
        return "STAGGER_GREEN"
    end
    return spec and spec.token
end
function CP.FillForSegment(spec, index, valueOverride)
    if not spec then return index <= 3 and 1 or 0 end
    if spec.nativeDurationText == true then return 0 end
    local mode = spec.mode or "segmented"
    local value = tonumber(valueOverride)
    if value == nil then value = tonumber(spec.value) or 0 end
    if CP.IsSingleBarMode(mode) then
        if index ~= 1 then return 0 end
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        return value
    end
    local full = floor(value)
    if mode == "fractional" or CP.IsEssence(spec) then
        local partial = value - full
        if index <= full then return 1 end
        if index == full + 1 and partial > 0.001 then return partial end
        return 0
    end
    return index <= full and 1 or 0
end
function CP.AnimatedValue(spec, elapsed)
    if not spec then return nil end
    local mode = spec.mode or "segmented"
    local maxValue = tonumber(spec.segments) or 1
    if CP.IsSingleBarMode(mode) then maxValue = 1 elseif maxValue < 1 then maxValue = 1 end
    elapsed = tonumber(elapsed) or 0
    if mode == "timer_bar" then return 1 - ((elapsed % 4.8) / 4.8) end
    local phase = (elapsed % 2.4) / 2.4
    local wave = phase < 0.5 and (phase * 2) or ((1 - phase) * 2)
    if mode == "continuous" or mode == "stagger" or mode == "aura_single" then return 0.08 + (wave * 0.88) end
    if CP.IsEssence(spec) then
        local cycle = (elapsed / 1.15) % (maxValue + 1)
        if cycle >= maxValue then return maxValue end
        local full = floor(cycle)
        return full + (cycle - full)
    end
    if mode == "fractional" then return wave * maxValue end
    local steps = maxValue * 2
    local step = floor((elapsed / 0.42) % steps)
    if step <= maxValue then return step end
    return steps - step
end
function CP.TextForValue(spec, value)
    if not spec then return "" end
    if value == nil then return spec.previewText or "" end
    local mode = spec.mode or "segmented"
    if mode == "continuous" then return tostring(floor((value * 100) + 0.5)) .. " / 100" end
    if mode == "timer_bar" then return string.format("%.1f", floor((value * 20 * 10) + 0.5) / 10) end
    if mode == "stagger" then return tostring(floor((value * 34) + 0.5)) .. "K" end
    if mode == "aura_single" then return tostring(floor((value * 5) + 0.5)) end
    if mode == "fractional" then return string.format("%.1f", value) end
    local rounded = CP.IsEssence(spec) and floor(value) or floor(value + 0.5)
    if spec.token == "SOUL_FRAGMENTS_VENG" then return tostring(rounded) .. " / " .. tostring(tonumber(spec.segments) or 6) end
    return tostring(rounded)
end
local RUNE_PREVIEW_REMAINING = { nil, 7.2, nil, 4.1, nil, 1.4 }
local RUNE_PREVIEW_OFFSET = { nil, 0.0, nil, 3.1, nil, 6.2 }
local RUNE_PREVIEW_READY_HOLD = 1.2
function CP.FormatSeconds(remaining)
    remaining = tonumber(remaining) or 0
    if remaining <= 0.05 then return "" end
    return string.format("%.1f", floor((remaining * 10) + 0.5) / 10)
end
function CP.FillRuneState(out, runeID, totalDuration, elapsed, animated)
    out.id = runeID
    out.total = totalDuration
    local baseRemaining = RUNE_PREVIEW_REMAINING[runeID]
    if not baseRemaining then
        out.ready = true
        out.elapsed = totalDuration
        out.remaining = 0
        return out
    end
    out.ready = false
    if animated then
        local cycle = totalDuration + RUNE_PREVIEW_READY_HOLD
        local progress = ((tonumber(elapsed) or 0) + (RUNE_PREVIEW_OFFSET[runeID] or 0)) % cycle
        if progress >= totalDuration then
            out.ready = true
            out.elapsed = totalDuration
            out.remaining = 0
        else
            out.elapsed = progress
            out.remaining = totalDuration - progress
        end
    else
        out.remaining = baseRemaining
        out.elapsed = totalDuration - baseRemaining
    end
    if out.remaining < 0.05 then
        out.ready = true
        out.elapsed = totalDuration
        out.remaining = 0
    end
    return out
end
function CP.BuildRuneOrder(scratch, bars, spec, elapsed, animated)
    local states = scratch.runeStates
    if not states then
        states = {}
        scratch.runeStates = states
    end
    local totalDuration = tonumber(spec and spec.runeDuration) or 10
    if totalDuration < 1 then totalDuration = 10 end
    for i = 1, 6 do states[i] = CP.FillRuneState(states[i] or {}, i, totalDuration, elapsed, animated) end
    for i = 7, #states do states[i] = nil end
    local sortOrder = bars and bars.runeSortOrder
    if sortOrder == "asc" then
        table.sort(states, function(a, b)
            if a.ready ~= b.ready then return a.ready == true end
            return (a.id or 0) < (b.id or 0)
        end)
    elseif sortOrder == "desc" then
        table.sort(states, function(a, b)
            if a.ready ~= b.ready then return a.ready ~= true end
            return (a.id or 0) < (b.id or 0)
        end)
    else
        table.sort(states, function(a, b) return (a.id or 0) < (b.id or 0) end)
    end
    return states
end
function CP.ResolveTexture(key, fallback)
    if key and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        local path = type(resolve) == "function" and resolve(key) or nil
        if path and path ~= "" then return path end
    end
    if fallback and fallback ~= "" then return fallback end
    if type(_G.MSUF_GetBarTexture) == "function" then
        local path = _G.MSUF_GetBarTexture()
        if path and path ~= "" then return path end
    end
    return CP.WHITE8
end
function H.StylePreviewPillButton(btn, T, opts)
    if not btn then return btn end
    opts = opts or {}
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
    local fontField = opts.fontField or "fs"
    local useSuperellipse = T and T.CreateSuperellipseLayers
    if useSuperellipse and not btn._msuf2PreviewPillFill then
        local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2PreviewPill", 2, "BACKGROUND", "BORDER")
        btn._msuf2PreviewPillFill = fill
        btn._msuf2PreviewPillEdge = edge
        if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 0) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
    end
    local tc = T and T.colors
    local shadow = tc and tc.coreShadow or { 0.006, 0.016, 0.032 }
    local surface = tc and tc.coreSurface or { 0.014, 0.038, 0.072 }
    local raised = tc and tc.coreRaised or { 0.026, 0.070, 0.110 }
    local rim = tc and tc.coreRim or { 0.043, 0.096, 0.150 }
    local blue = tc and tc.coreBlue or { 0.095, 0.360, 0.560 }
    local bgIdle, bgHover, bgActive, bgDown = { shadow[1], shadow[2], shadow[3], 0.92 }, { surface[1], surface[2], surface[3], 0.98 }, { raised[1], raised[2], raised[3], 0.98 }, { raised[1], raised[2], raised[3], 1.00 }
    local brIdle, brHover, brActive = { rim[1], rim[2], rim[3], 0.72 }, { blue[1], blue[2], blue[3], 0.58 }, { blue[1], blue[2], blue[3], 0.70 }
    local bgScratch = { 0, 0, 0, 1 }
    function btn:MSUF2RefreshPreviewPill(active, hover, down)
        active = active == true
        if hover == nil then hover = self._msuf2PreviewPillHover == true end
        if down == nil then down = self._msuf2PreviewPillDown == true end
        self._msuf2PreviewPillActive = active
        local alpha = (self.IsEnabled and not self:IsEnabled()) and 0.42 or 1
        local bg = down and bgDown or (active and bgActive or (hover and bgHover or bgIdle))
        local br = active and brActive or (hover and brHover or brIdle)
        if useSuperellipse and self._msuf2PreviewPillFill then
            if T.SetFillGradient then
                bgScratch[1], bgScratch[2], bgScratch[3], bgScratch[4] = bg[1], bg[2], bg[3], (bg[4] or 1) * alpha
                T.SetFillGradient(self._msuf2PreviewPillFill, bgScratch, 0.12, -0.18)
            else
                self._msuf2PreviewPillFill:SetVertexColor(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
            end
            if self._msuf2PreviewPillEdge then
                self._msuf2PreviewPillEdge:SetVertexColor(min(br[1] * (hover and 1.08 or 1), 1), min(br[2] * (hover and 1.08 or 1), 1), min(br[3] * (hover and 1.08 or 1), 1), (br[4] or 1) * alpha)
            end
        elseif self.SetBackdropColor then
            self:SetBackdropColor(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
            self:SetBackdropBorderColor(br[1], br[2], br[3], (br[4] or 1) * alpha)
        end
        if self[fontField] and self[fontField].SetTextColor then
            self[fontField]:SetTextColor(active and 0.06 or (hover and 0.88 or 0.78), active and 0.95 or (hover and 0.94 or 0.84), active and 1.00 or 0.96, alpha)
        end
    end
    btn:SetScript("OnEnter", function(self)
        self._msuf2PreviewPillHover = true
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, true, self._msuf2PreviewPillDown)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2PreviewPillHover = nil
        self._msuf2PreviewPillDown = nil
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2PreviewPillDown = true
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, self._msuf2PreviewPillHover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2PreviewPillDown = nil
        self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive, self._msuf2PreviewPillHover, false)
    end)
    btn:SetScript("OnEnable", function(self) self:MSUF2RefreshPreviewPill(self._msuf2PreviewPillActive) end)
    btn:SetScript("OnDisable", function(self) self:MSUF2RefreshPreviewPill(false, false, false) end)
    btn:MSUF2RefreshPreviewPill(false, false, false)
    return btn
end
function H.ShowPreviewHandleContext(handle, opts)
    opts = opts or {}
    if not handle then return end
    local M2 = opts.M or M
    local T = opts.T or (M2 and M2.Theme)
    local W = opts.W or (M2 and M2.Widgets)
    local tr = opts.Tr or opts.TR or (M2 and M2.Tr) or F.Identity
    local openSettings = opts.openSettings
    if type(openSettings) ~= "function" then return end
    local popup = H._previewHandleContextPopup
    if not popup then
        if M2 and type(M2.CreateMenuPopupPanel) == "function" then
            popup = M2.CreateMenuPopupPanel(UIParent, { name = "MSUF2PreviewHandleContextMenu", glass = "popup" })
        else
            popup = CreateFrame("Frame", "MSUF2PreviewHandleContextMenu", UIParent, "BackdropTemplate")
            popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            popup:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
            popup:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
        end
        popup:SetSize(176, 76)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:EnableMouse(true)
        local title = T and T.Font and T.Font(popup, "GameFontDisableSmall", "", (T.colors and T.colors.muted) or { 0.72, 0.78, 0.90, 1 }) or popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -8)
        title:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
        title:SetJustifyH("LEFT")
        popup._title = title
        local function MakeButton(label, y)
            local btn = W and W.TopButton and W.TopButton(popup, tr(label), 152, 24) or (T and T.Button and T.Button(popup, tr(label), 152, 24)) or CreateFrame("Button", nil, popup, "BackdropTemplate")
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, y)
            if not btn.GetText then btn:SetText(tr(label)) end
            return btn
        end
        popup._open = MakeButton("Open Settings", -28)
        popup._keep = MakeButton("Keep Selected", -52)
        popup._keep:SetScript("OnClick", function(self)
            local p = self:GetParent()
            if p then p:Hide() end
        end)
        if M2 and type(M2.RegisterMenuChromeControl) == "function" then
            M2.RegisterMenuChromeControl(popup._open, "preview-context.open-settings",
                "Open selected preview element settings", "action", {
                    historyMode = "none",
                    help = "Opens the exact options section for the selected preview element.",
                    command = {
                        kind = "button",
                        historyMode = "none",
                        canExecute = function()
                            return popup.IsShown and popup:IsShown()
                                and popup._handle ~= nil and type(popup._openSettings) == "function"
                        end,
                        set = function()
                            if not (popup.IsShown and popup:IsShown()) then return false end
                            local h, fn = popup._handle, popup._openSettings
                            if h == nil or type(fn) ~= "function" then return false end
                            popup:Hide()
                            return fn(h, "assistant") ~= false
                        end,
                    },
                })
            M2.RegisterMenuChromeControl(popup._keep, "preview-context.keep-selected", "Keep preview element selected", "action", {
                historyMode = "none",
                help = "Closes the preview quick-actions popup without changing the current selection.",
                command = {
                    kind = "button",
                    historyMode = "none",
                    canExecute = function() return popup.IsShown and popup:IsShown() end,
                    set = function()
                        if not (popup.IsShown and popup:IsShown()) then return false end
                        popup:Hide()
                        return true
                    end,
                },
            })
        end
        H._previewHandleContextPopup = popup
    end
    popup._handle = handle
    popup._openSettings = openSettings
    if popup._title and popup._title.SetText then popup._title:SetText(tr(opts.title or (handle._label or handle._previewText or handle._key or "Preview Element"))) end
    popup._open:SetScript("OnClick", function(self)
        local p = self:GetParent()
        local h = p and p._handle
        local fn = p and p._openSettings
        if p then p:Hide() end
        if type(fn) == "function" then fn(h, "context") end
    end)
    if M2 and type(M2.ApplyPopupFramePriority) == "function" then M2.ApplyPopupFramePriority(popup) end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", handle, "BOTTOMRIGHT", 8, -2)
    popup:Show()
    return popup
end
local SETTINGS_ICON_RECTS = {
    { 10, 1, "CENTER", 0, 4, 0.70 }, { 10, 1, "CENTER", 0, 0, 0.70 }, { 10, 1, "CENTER", 0, -4, 0.70 },
    { 3, 3, "CENTER", -3, 4, 1.00 }, { 3, 3, "CENTER", 3, 0, 1.00 }, { 3, 3, "CENTER", -1, -4, 1.00 },
}
local function CreatePreviewSettingsIcon(button)
    if not (button and button.CreateTexture) or button._msuf2PreviewSettingsParts then return end
    local parts = {}
    for i = 1, #SETTINGS_ICON_RECTS do
        local r = SETTINGS_ICON_RECTS[i]
        local tex = button:CreateTexture(nil, "ARTWORK", nil, 6)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetSize(r[1], r[2])
        tex:SetPoint(r[3], button, r[3], r[4], r[5])
        parts[i] = tex
    end
    button._msuf2PreviewSettingsParts = parts
end

local function PaintPreviewSettingsIcon(button, hover)
    local parts = button and button._msuf2PreviewSettingsParts
    local mul = hover and 1.16 or 1
    if parts then
        for i = 1, #parts do
            local alpha = SETTINGS_ICON_RECTS[i][6] or 1
            parts[i]:SetVertexColor(min(0.76 * mul, 1), min(0.94 * mul, 1), 1, hover and 1 or alpha)
        end
    end
end

function H.EnsurePreviewHandleGear(handle, opts)
    opts = opts or {}
    if not handle then return nil end
    local T = opts.T or (M and M.Theme)
    local tr = opts.Tr or opts.TR or (M and M.Tr) or F.Identity
    local gear = handle._msuf2SettingsGear
    if not gear then
        local template = T and T.Template and T.Template() or "BackdropTemplate"
        gear = CreateFrame("Button", nil, handle, template)
        gear:SetSize(18, 18)
        gear:SetPoint("BOTTOMLEFT", handle, "TOPRIGHT", -8, -8)
        if gear.SetHitRectInsets then gear:SetHitRectInsets(-2, -2, -2, -2) end
        if T and T.CreateSuperellipseLayers then
            local fill, edge = T.CreateSuperellipseLayers(gear, "_msuf2PreviewGear", 2, "BACKGROUND", "BORDER")
            gear._fill, gear._edge = fill, edge
        elseif gear.SetBackdrop then
            gear:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
        CreatePreviewSettingsIcon(gear)
        local bg, br = { 0.010, 0.022, 0.040, 0.96 }, { 0.160, 0.560, 0.720, 0.92 }
        local function Paint(self, hover)
            local mul = hover and 1.10 or 1
            if self._fill then
                if T and T.SetFillGradient then T.SetFillGradient(self._fill, bg, 0.12, -0.18) else self._fill:SetVertexColor(bg[1], bg[2], bg[3], bg[4]) end
            elseif self.SetBackdropColor then
                self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            end
            if self._edge then
                self._edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4])
            elseif self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
            end
            PaintPreviewSettingsIcon(self, hover)
        end
        gear:SetScript("OnEnter", function(self)
            Paint(self, true)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tr("Open Settings"), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        gear:SetScript("OnLeave", function(self)
            Paint(self, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        gear:SetScript("OnClick", function(self)
            local h = self._handle
            local fn = self._openSettings
            if type(fn) == "function" then fn(h, "gear") end
        end)
        Paint(gear, false)
        gear:Hide()
        handle._msuf2SettingsGear = gear
    end
    gear._handle = handle
    gear._openSettings = opts.openSettings
    gear:SetShown(opts.shown == true)
    return gear
end
-- Zoom lock glyph, drawn from flat rects like the handle gear so it cannot fall
-- back to a missing texture. "Locked" means the preview keeps the zoom the user
-- dialled in instead of refitting whenever the footprint changes.
local LOCK_ICON_RECTS = {
    body = { 10, 7, 0, -3 },
    postLeft = { 2, 5, -3, 2 },
    postRight = { 2, 5, 3, 2 },
    bow = { 8, 2, 0, 4 },
}
local function CreateZoomLockIcon(button)
    if not (button and button.CreateTexture) or button._msuf2ZoomLockParts then return end
    local parts = {}
    for name, r in pairs(LOCK_ICON_RECTS) do
        local tex = button:CreateTexture(nil, "ARTWORK", nil, 6)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetSize(r[1], r[2])
        tex:SetPoint("CENTER", button, "CENTER", r[3], r[4])
        parts[name] = tex
    end
    button._msuf2ZoomLockParts = parts
end
local function PaintZoomLockIcon(button, locked, hover)
    local parts = button and button._msuf2ZoomLockParts
    if not parts then return end
    local r, g, b = 0.55, 0.62, 0.74
    if locked then r, g, b = 0.30, 0.86, 1.00 end
    if hover then r, g, b = min(r * 1.25, 1), min(g * 1.25, 1), min(b * 1.25, 1) end
    for _, tex in pairs(parts) do tex:SetVertexColor(r, g, b, locked and 1 or 0.82) end
    -- An open shackle reads as "unlocked" at a glance; the closed one is the
    -- only state in which the zoom survives a layer toggle.
    parts.postRight:SetShown(locked)
    parts.bow:ClearAllPoints()
    parts.bow:SetPoint("CENTER", button, "CENTER", locked and 0 or 2, locked and 4 or 5)
end

--- Opt-in zoom lock: pins the current scale so layer toggles stop refitting the
--- canvas. A default lock is resolved only after the renderer has produced its
--- first real Fit scale; it is preview-local and never reads or writes a profile.
function H.EnsureZoomLockButton(box, zoomBar, opts)
    if not (box and zoomBar) then return nil end
    opts = opts or {}
    local tr = opts.Tr or opts.TR or (M and M.Tr) or F.Identity
    local T = opts.T or (M and M.Theme)
    local btn = box.zoomLockButton
    if not btn then
        btn = CreateFrame("Button", nil, zoomBar, (T and T.Template and T.Template()) or "BackdropTemplate")
        btn:SetSize(20, opts.buttonHeight or 20)
        CreateZoomLockIcon(btn)
        if H.StylePreviewPillButton then H.StylePreviewPillButton(btn, T, {}) end
        box.zoomLockButton = btn
    end
    if box._msuf2ZoomLockDefaultInitialized ~= true then
        box._msuf2ZoomLockDefaultInitialized = true
        box._msuf2ZoomLockDefaultEnabled = opts.defaultLocked == true or nil
        box._msuf2ZoomLockDefaultPending = box._msuf2ZoomLockDefaultEnabled
    end
    local function Locked()
        return box._manualZoom ~= nil or box._msuf2ZoomLockDefaultPending == true
    end
    local function Refresh()
        local locked = Locked()
        PaintZoomLockIcon(btn, locked, btn._msuf2PreviewPillHover == true)
        if btn.MSUF2RefreshPreviewPill then btn:MSUF2RefreshPreviewPill(locked) end
    end
    box.RefreshZoomLock = Refresh
    local function SetLocked(locked)
        local setZoom = opts.SetZoom
        if type(setZoom) ~= "function" then return false end
        -- An explicit click owns the state from here on. In particular, an
        -- early Unlock must cancel a not-yet-resolved default lock.
        box._msuf2ZoomLockDefaultPending = nil
        if locked then
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
            setZoom(box, scale, opts.lockReason or "PREVIEW_ZOOM_LOCK")
        else
            setZoom(box, nil, opts.unlockReason or "PREVIEW_ZOOM_UNLOCK")
        end
        Refresh()
        return Locked() == (locked == true)
    end
    btn:SetScript("OnClick", function() SetLocked(not Locked()) end)
    -- The pill styling owns OnEnter/OnLeave through SetScript, so the tooltip
    -- chains behind it. Hook exactly once; a second Ensure call would otherwise
    -- stack duplicate tooltip handlers.
    if not btn._msuf2ZoomLockHooked then
        btn._msuf2ZoomLockHooked = true
        btn:HookScript("OnEnter", function(self)
            if type(box.RefreshZoomLock) == "function" then box.RefreshZoomLock() end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tr("Lock zoom"), 1, 1, 1)
                GameTooltip:AddLine(tr("Locked: the preview keeps this zoom and position when you toggle layers."), 0.82, 0.82, 0.82, true)
                GameTooltip:AddLine(tr("Unlocked: the preview refits itself whenever the frame footprint changes."), 0.55, 0.68, 0.86, true)
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function()
            if type(box.RefreshZoomLock) == "function" then box.RefreshZoomLock() end
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = Locked,
        set = SetLocked,
    }
    Refresh()
    return btn
end
-- Right-click drag moves the preview canvas; empty-space left drag and the
-- middle-button gesture now share the same path. The hint counts real moves
-- (not bare clicks) and retires itself after three; the tally is persisted.
local PREVIEW_MOVE_HINT_TARGET = 3
function H.PreviewMoveHintState()
    if M and type(M.GetPersistentMenuStateTable) == "function" then
        return M.GetPersistentMenuStateTable("previewMoveHintState")
    end
    H._previewMoveHintFallback = H._previewMoveHintFallback or {}
    return H._previewMoveHintFallback
end
function H.PreviewMoveHintRemaining()
    local state = H.PreviewMoveHintState()
    local done = tonumber(state and state.count) or 0
    local remaining = PREVIEW_MOVE_HINT_TARGET - done
    if remaining < 0 then return 0 end
    return remaining
end
function H.NotePreviewCanvasMoved(button)
    if button ~= "LeftButton" and button ~= "RightButton" and button ~= "MiddleButton" then
        return H.PreviewMoveHintRemaining()
    end
    local state = H.PreviewMoveHintState()
    if type(state) ~= "table" then return 0 end
    local done = tonumber(state.count) or 0
    if done >= PREVIEW_MOVE_HINT_TARGET then return 0 end
    state.count = done + 1
    if M and type(M.SavePersistentMenuState) == "function" then M.SavePersistentMenuState() end
    return H.PreviewMoveHintRemaining()
end

-- Every real preview-handle click gets the same short drag demonstration.  The
-- artwork is Blizzard's own tutorial drag cursor; the surrounding mouse shape
-- keeps the gesture readable even when the selected preview element is tiny.
-- This is menu-only work driven by an AnimationGroup, never a runtime ticker or
-- a persistent OnUpdate.
local PREVIEW_DRAG_CUE_ATLAS = "newplayertutorial-drag-cursor"
local function PreviewDragCueEnabled()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    return type(general) ~= "table" or general.previewDragHintAnimationEnabled ~= false
end
local function PreviewDragCueIsNewProfile()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    return type(general) == "table" and general._msufPreviewDragHintExperienced == false
end
function H.HidePreviewMoveCue()
    local cue = H._previewMoveCue
    if not cue then return end
    local anim = cue._motionAnim
    if anim and anim.IsPlaying and anim:IsPlaying() then anim:Stop() end
    cue:Hide()
end
local function CreatePreviewMoveCue()
    if H._previewMoveCue then return H._previewMoveCue end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    local cue = CreateFrame("Frame", "MSUF2PreviewMoveCue", UIParent, "BackdropTemplate")
    cue:SetSize(252, 64)
    cue:SetFrameStrata("TOOLTIP")
    if cue.SetToplevel then cue:SetToplevel(true) end
    if cue.SetClampedToScreen then cue:SetClampedToScreen(true) end
    cue:EnableMouse(false)
    if cue.SetBackdrop then
        cue:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        cue:SetBackdropColor(0.012, 0.020, 0.040, 0.96)
        cue:SetBackdropBorderColor(0.18, 0.64, 0.88, 0.96)
    end

    local motion = CreateFrame("Frame", nil, cue)
    motion:SetSize(72, 46)
    motion:SetPoint("LEFT", cue, "LEFT", 10, 0)
    local mouse = CreateFrame("Frame", nil, motion, "BackdropTemplate")
    mouse:SetSize(24, 34)
    mouse:SetPoint("LEFT", motion, "LEFT", 1, 0)
    if mouse.SetBackdrop then
        mouse:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        mouse:SetBackdropColor(0.08, 0.12, 0.18, 0.98)
        mouse:SetBackdropBorderColor(0.72, 0.86, 0.98, 1)
    end
    local split = mouse:CreateTexture(nil, "ARTWORK")
    split:SetColorTexture(0.72, 0.86, 0.98, 0.82)
    split:SetPoint("TOP", mouse, "TOP", 0, -10)
    split:SetPoint("LEFT", mouse, "LEFT", 2, 0)
    split:SetPoint("RIGHT", mouse, "RIGHT", -2, 0)
    split:SetHeight(1)
    local wheel = mouse:CreateTexture(nil, "ARTWORK")
    wheel:SetColorTexture(0.18, 0.64, 0.88, 1)
    wheel:SetSize(2, 6)
    wheel:SetPoint("TOP", mouse, "TOP", 0, -3)
    local cursor = motion:CreateTexture(nil, "OVERLAY", nil, 2)
    if cursor.SetAtlas then
        cursor:SetAtlas(PREVIEW_DRAG_CUE_ATLAS, true)
    else
        cursor:SetTexture("Interface\\Cursor\\UI-Cursor-Move")
        cursor:SetSize(32, 32)
    end
    cursor:SetPoint("CENTER", mouse, "BOTTOMRIGHT", 5, 2)

    local label = cue:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cue, "LEFT", 90, 0)
    label:SetPoint("RIGHT", cue, "RIGHT", -88, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.82, 0.94, 1, 1)

    local keys = CreateFrame("Frame", nil, cue)
    keys:SetSize(70, 50)
    keys:SetPoint("RIGHT", cue, "RIGHT", -8, 0)
    local function ArrowKey(atlas, x, y)
        local key = CreateFrame("Frame", nil, keys, "BackdropTemplate")
        key:SetSize(20, 20)
        key:SetPoint("BOTTOMLEFT", keys, "BOTTOMLEFT", x, y)
        if key.SetBackdrop then
            key:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            key:SetBackdropColor(0.06, 0.10, 0.16, 0.98)
            key:SetBackdropBorderColor(0.46, 0.66, 0.82, 0.95)
        end
        local arrow = key:CreateTexture(nil, "ARTWORK")
        arrow:SetPoint("CENTER")
        arrow:SetSize(12, 12)
        if arrow.SetAtlas then arrow:SetAtlas(atlas, false) end
        arrow:SetVertexColor(0.82, 0.94, 1, 1)
        return key
    end
    ArrowKey("NPE_ArrowUp", 25, 27)
    ArrowKey("NPE_ArrowLeft", 3, 5)
    ArrowKey("NPE_ArrowDown", 25, 5)
    ArrowKey("NPE_ArrowRight", 47, 5)
    cue._label, cue._keys = label, keys

    if motion.CreateAnimationGroup then
        local group = motion:CreateAnimationGroup()
        local theme = M and M.Theme
        if theme and theme.TrackMenuAnimationGroup then theme.TrackMenuAnimationGroup(group) end
        local offsets = { 20, -20, 20, -20, 20, -20 }
        for i = 1, #offsets do
            local move = group:CreateAnimation("Translation")
            move:SetOrder(i)
            move:SetDuration(i == 1 and 0.32 or 0.26)
            move:SetOffset(offsets[i], 0)
            if move.SetSmoothing then move:SetSmoothing("IN_OUT") end
        end
        group:SetScript("OnFinished", function() cue:Hide() end)
        cue._motionAnim = group
    end
    cue:Hide()
    H._previewMoveCue = cue
    return cue
end
local function PreparePreviewMoveCueOwner(owner)
    if not owner then return end
    local profile = tostring(_G.MSUF_ActiveProfile or "")
    if owner._msuf2PreviewDragCueProfile ~= profile then
        owner._msuf2PreviewDragCueProfile = profile
        owner._msuf2PreviewDragCueShownForOpen = nil
        owner._msuf2PreviewHandleTooltipShownForOpen = nil
    end
    if owner._msuf2PreviewDragCueLifecycleHooked or not owner.HookScript then return end
    owner._msuf2PreviewDragCueLifecycleHooked = true
    owner:HookScript("OnShow", function(self)
        self._msuf2PreviewDragCueShownForOpen = nil
        self._msuf2PreviewHandleTooltipShownForOpen = nil
        self._msuf2PreviewDragCueProfile = tostring(_G.MSUF_ActiveProfile or "")
    end)
end
function H.NotePreviewElementMoved()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if type(general) == "table" then general._msufPreviewDragHintExperienced = true end
    H._previewDragCueSessionShown = true
end
function H.ShouldShowPreviewHandleTooltip(owner)
    PreparePreviewMoveCueOwner(owner)
    if PreviewDragCueIsNewProfile() then
        if owner and owner._msuf2PreviewHandleTooltipShownForOpen == true then return false end
        if owner then owner._msuf2PreviewHandleTooltipShownForOpen = true end
    elseif H._previewHandleTooltipSessionShown == true then
        return false
    end
    H._previewHandleTooltipSessionShown = true
    return true
end
function H.ShowPreviewMoveCue(owner, handle)
    if not PreviewDragCueEnabled() then H.HidePreviewMoveCue(); return false end
    if not handle or handle._locked == true or handle._msufPlaced == false then return false end
    if handle.IsShown and not handle:IsShown() then return false end
    PreparePreviewMoveCueOwner(owner)
    local newProfile = PreviewDragCueIsNewProfile()
    if newProfile then
        if owner and owner._msuf2PreviewDragCueShownForOpen == true then return false end
    elseif H._previewDragCueSessionShown == true then
        return false
    end
    local cue = CreatePreviewMoveCue()
    if not cue then return false end
    local anim = cue._motionAnim
    if anim and anim.IsPlaying and anim:IsPlaying() then anim:Stop() end
    cue:Hide()
    cue:ClearAllPoints()
    cue:SetPoint("BOTTOM", handle, "TOP", 0, 12)
    local tr = (M and M.Tr) or F.Identity
    cue._label:SetText(tr("Drag to move"))
    cue._previewOwner = owner
    cue:Show()
    if anim and anim.Play then anim:Play() end
    if newProfile and owner then
        owner._msuf2PreviewDragCueShownForOpen = true
    else
        H._previewDragCueSessionShown = true
    end
    return true
end
local function PreviewControlsLines(tr)
    tr = tr or F.Identity
    return {
        tr("Drag handles to move."),
        tr("Right-click: quick actions."),
        tr("Arrows nudge. Shift=5, Ctrl=10."),
        tr("Drag background: pan. Ctrl+wheel: zoom."),
        tr("Fit recenters."),
    }
end
function H.ShowPreviewControlsHelp(anchor, opts)
    opts = opts or {}
    local M2 = opts.M or M
    local T = opts.T or (M2 and M2.Theme)
    local W = opts.W or (M2 and M2.Widgets)
    local tr = opts.Tr or opts.TR or (M2 and M2.Tr) or F.Identity
    local popup = H._previewControlsHelpPopup
    if not popup then
        if M2 and type(M2.CreateMenuPopupPanel) == "function" then
            popup = M2.CreateMenuPopupPanel(UIParent, { name = "MSUF2PreviewControlsHelp", glass = "popup" })
        else
            popup = CreateFrame("Frame", "MSUF2PreviewControlsHelp", UIParent, "BackdropTemplate")
            popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            popup:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
            popup:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
        end
        popup:SetSize(328, 188)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:EnableMouse(true)
        popup._title = T and T.Font and T.Font(popup, "GameFontNormalSmall", "", (T.colors and T.colors.accent) or { 0.78, 0.92, 1, 1 }) or popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -12)
        popup._title:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
        popup._title:SetJustifyH("LEFT")
        popup._lines = {}
        for i = 1, 6 do
            local fs = T and T.Font and T.Font(popup, "GameFontDisableSmall", "", (T.colors and T.colors.muted) or { 0.72, 0.78, 0.90, 1 }) or popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            fs:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -32 - ((i - 1) * 20))
            fs:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
            if fs.SetMaxLines then fs:SetMaxLines(1) end
            popup._lines[i] = fs
        end
        local close = W and W.TopButton and W.TopButton(popup, tr("Got it"), 84, 24) or (T and T.Button and T.Button(popup, tr("Got it"), 84, 24)) or CreateFrame("Button", nil, popup, "BackdropTemplate")
        close:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
        if not close.GetText then close:SetText(tr("Got it")) end
        close:SetScript("OnClick", function(self)
            local p = self:GetParent()
            if p then p:Hide() end
        end)
        if M2 and type(M2.RegisterMenuChromeControl) == "function" then
            M2.RegisterMenuChromeControl(close, "preview-controls-help.dismiss", "Got it", "action", {
                historyMode = "none",
                help = "Closes the Preview Controls help popup.",
                command = {
                    kind = "button",
                    historyMode = "none",
                    canExecute = function() return popup.IsShown and popup:IsShown() end,
                    set = function()
                        if not (popup.IsShown and popup:IsShown()) then return false end
                        popup:Hide()
                        return true
                    end,
                },
            })
        end
        popup._close = close
        H._previewControlsHelpPopup = popup
    end
    popup._title:SetText(tr(opts.title or "Preview Controls"))
    -- Callers with a reduced interaction model (e.g. the color-only preview)
    -- can supply their own lines instead of the full editing help.
    local lines = opts.lines or PreviewControlsLines(tr)
    for i = 1, #(popup._lines or {}) do
        local fs = popup._lines[i]
        if fs then fs:SetText(lines[i] and ("- " .. lines[i]) or "") end
    end
    if M2 and type(M2.ApplyPopupFramePriority) == "function" then M2.ApplyPopupFramePriority(popup) end
    popup:ClearAllPoints()
    if anchor and anchor.GetLeft then
        popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup:Show()
    return popup
end
function H.HideTransientPopups()
    local context = H._previewHandleContextPopup
    if context and context.Hide then context:Hide() end
    local help = H._previewControlsHelpPopup
    if help and help.Hide then help:Hide() end
    H.HidePreviewMoveCue()
end
M.HideMenuPreviewPopups = H.HideTransientPopups
function H.EnsurePreviewControlsHint(box, anchor, opts)
    opts = opts or {}
    if not box then return nil end
    local M2 = opts.M or M
    local T = opts.T or (M2 and M2.Theme)
    local tr = opts.Tr or opts.TR or (M2 and M2.Tr) or F.Identity
    local state = M2 and M2.GetPersistentMenuStateTable and M2.GetPersistentMenuStateTable("previewControlsHintState") or nil
    if state and state.seen == true then return nil end
    local parent = anchor or box.canvas or box._stage or box
    if not parent then return nil end
    local hint = box._msuf2PreviewControlsHint
    if not hint then
        local template = T and T.Template and T.Template() or "BackdropTemplate"
        hint = CreateFrame("Frame", nil, parent, template)
        hint:SetSize(288, 48)
        hint:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
        if hint.SetFrameLevel and parent.GetFrameLevel then hint:SetFrameLevel((parent:GetFrameLevel() or 0) + 90) end
        if hint.SetBackdrop then
            hint:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            hint:SetBackdropColor(0.012, 0.020, 0.040, 0.94)
            hint:SetBackdropBorderColor(0.10, 0.32, 0.54, 0.92)
        end
        hint:EnableMouse(true)
        local text = T and T.Font and T.Font(hint, "GameFontDisableSmall", "", (T.colors and T.colors.text) or { 0.86, 0.90, 0.98, 1 }) or hint:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("TOPLEFT", hint, "TOPLEFT", 12, -8)
        text:SetPoint("RIGHT", hint, "RIGHT", -60, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        hint._text = text
        local close = CreateFrame("Button", nil, hint, "BackdropTemplate")
        close:SetSize(44, 24)
        close:SetPoint("RIGHT", hint, "RIGHT", -8, 0)
        close.fs = close.fs or close:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        close.fs:SetPoint("CENTER")
        close.fs:SetText(tr("OK"))
        if T and T.StyleFontString then T.StyleFontString(close.fs, (T.colors and T.colors.text) or { 1, 1, 1, 1 }, 0) end
        if T and H.StylePreviewPillButton then H.StylePreviewPillButton(close, T, { fontField = "fs" }) end
        close:SetScript("OnClick", function(self)
            local p = self:GetParent()
            local s = M2 and M2.GetPersistentMenuStateTable and M2.GetPersistentMenuStateTable("previewControlsHintState") or state
            if s then s.seen = true end
            if p then p:Hide() end
        end)
        hint._close = close
        box._msuf2PreviewControlsHint = hint
    end
    if hint._text then hint._text:SetText(tr("Drag handles to move.")) end
    hint:Show()
    return hint
end
function H.SwitchCompactZoomMode(box, compact, defaultCompactZoom)
    if not box then return false end
    compact = compact == true
    local active = box._msuf2CompactZoomMode
    if active == compact then return false end

    -- Expanding the same preview in place must not replace the scale the user
    -- was just looking at with an older Full/Fit state.  Capture the rendered
    -- Compact scale before the larger canvas changes its auto-fit geometry.
    -- Pan remains mode-local because the two canvases have different bounds.
    local compactZoomToCarry
    if active == true and compact == false and box._msuf2PreserveExpandedZoomOnNextExpand ~= true then
        compactZoomToCarry = tonumber(box._manualZoom)
            or tonumber(box._mockScale)
            or tonumber(box._mockAutoScale)
    end

    local function Store(prefix)
        box[prefix .. "ManualZoom"] = tonumber(box._manualZoom)
        box[prefix .. "PanX"] = tonumber(box._zoomPanX) or 0
        box[prefix .. "PanY"] = tonumber(box._zoomPanY) or 0
        box[prefix .. "DefaultLockPending"] = box._msuf2ZoomLockDefaultPending == true or nil
        box[prefix .. "Initialized"] = true
    end
    local function Restore(prefix, fallbackZoom)
        if box[prefix .. "Initialized"] then
            box._manualZoom = box[prefix .. "ManualZoom"]
            box._zoomPanX = tonumber(box[prefix .. "PanX"]) or 0
            box._zoomPanY = tonumber(box[prefix .. "PanY"]) or 0
            box._msuf2ZoomLockDefaultPending = box[prefix .. "DefaultLockPending"] == true or nil
            return
        end
        box._manualZoom = tonumber(fallbackZoom)
        box._zoomPanX, box._zoomPanY = 0, 0
        box._msuf2ZoomLockDefaultPending = box._manualZoom == nil
            and box._msuf2ZoomLockDefaultEnabled == true or nil
        box[prefix .. "Initialized"] = true
        box[prefix .. "ManualZoom"] = box._manualZoom
        box[prefix .. "PanX"], box[prefix .. "PanY"] = 0, 0
        box[prefix .. "DefaultLockPending"] = box._msuf2ZoomLockDefaultPending
    end

    if active == nil then
        -- Before the first compact transition, the preview owns its normal
        -- expanded zoom state.  Preserve that Fit/manual choice verbatim.
        Store("_msuf2ExpandedZoom")
    else
        Store(active and "_msuf2CompactZoom" or "_msuf2ExpandedZoom")
    end
    Restore(compact and "_msuf2CompactZoom" or "_msuf2ExpandedZoom", compact and defaultCompactZoom or nil)
    if compactZoomToCarry then
        box._manualZoom = compactZoomToCarry
        box._msuf2ZoomLockDefaultPending = nil
    end
    box._msuf2CompactZoomMode = compact
    return true
end

--- Region-union handles are deliberately placed in the stationary Preview
--- canvas so their hit size is independent of the rendered element's scale.
--- When the mock is panned without a full render refresh, move only those
--- absolute canvas anchors by the same delta. Handles anchored directly to the
--- mock already follow it and must not be shifted a second time.
function H.ShiftPreviewPanFollowers(box, dx, dy)
    if not box then return 0 end
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    if dx == 0 and dy == 0 then return 0 end
    local stationaryCanvas, stationaryStage = box.canvas, box._stage
    local shifted, seen = 0, {}
    local function Shift(frame)
        if not (frame and frame._msufPreviewPanFollower == true and frame.GetPoint
            and frame.ClearAllPoints and frame.SetPoint) or seen[frame]
        then
            return
        end
        seen[frame] = true
        local count = (frame.GetNumPoints and frame:GetNumPoints()) or 1
        local points, changed = {}, false
        for i = 1, count do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
            if point then
                local followsStationarySurface = relativeTo == stationaryCanvas or relativeTo == stationaryStage
                if followsStationarySurface then
                    x, y = (tonumber(x) or 0) + dx, (tonumber(y) or 0) + dy
                    changed = true
                end
                points[#points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end
        if not changed then return end
        frame:ClearAllPoints()
        for i = 1, #points do frame:SetPoint(unpack(points[i])) end
        shifted = shifted + 1
    end
    for i = 1, #(box.handles or {}) do Shift(box.handles[i]) end
    Shift(box._msufMenuTextFocusFrame)
    return shifted
end

function H.InstallZoomPan(ZoomPan, opts)
    if type(ZoomPan) ~= "table" then return end
    opts = opts or {}
    local floor = math.floor
    local minZoom = tonumber(opts.minZoom) or 0.35
    local maxZoom = tonumber(opts.maxZoom) or 4.0
    local steps = opts.steps or { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }
    local deps = {}
    local white = "Interface\\Buttons\\WHITE8X8"
    local function PathValue(object, path)
        if not object or not path then return nil end
        if type(path) ~= "table" then return object[path] end
        local value = object
        for i = 1, #path do
            value = value and value[path[i]]
        end
        return value
    end
    local function TR(text)
        local fn = deps.TR
        return (type(fn) == "function" and fn(text)) or text
    end
    local function Round(value)
        return floor((tonumber(value) or 0) + 0.5)
    end
    local function ExactPanNumber(value)
        value = tonumber(value)
        if value == nil or value ~= value or value == math.huge or value == -math.huge or math.abs(value) > 100000 then return nil end
        return Round(value)
    end
    local function SameOffset(left, right)
        return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) < 0.01
    end
    local function PanKey(name)
        return tostring(opts.panPrefix or "_msufPreview") .. name
    end
    local PAN_PANNING, PAN_BOX = PanKey("Panning"), PanKey("PanBox")
    local PAN_CURSOR_X, PAN_CURSOR_Y = PanKey("PanCursorX"), PanKey("PanCursorY")
    local PAN_START_X, PAN_START_Y = PanKey("PanStartX"), PanKey("PanStartY")
    local PAN_BUTTON = PanKey("PanButton")
    ZoomPan.MIN = minZoom
    ZoomPan.MAX = maxZoom
    function ZoomPan.Configure(nextDeps)
        if opts.configureTableOnly then
            if type(nextDeps) == "table" then deps = nextDeps end
        else
            deps = nextDeps or deps or {}
        end
    end
    function ZoomPan.Clamp(value)
        value = tonumber(value) or 1
        if value < minZoom then return minZoom end
        if value > maxZoom then return maxZoom end
        return floor(value * 100 + 0.5) / 100
    end
    function ZoomPan.ResolveDefaultLock(box, fallbackScale)
        if not box or box._msuf2ZoomLockDefaultPending ~= true then return false end
        local initialScale = tonumber(box._manualZoom) or tonumber(fallbackScale)
            or tonumber(box._mockScale) or tonumber(box._mockAutoScale)
        if not initialScale then return false end
        box._manualZoom = ZoomPan.Clamp(initialScale)
        box._msuf2ZoomLockDefaultPending = nil
        return true
    end
    function ZoomPan.UpdateControls(box)
        if not box then return end
        local zoom = box._manualZoom
        local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
        local readout = box[opts.readoutField or "zoomReadout"]
        if readout then
            local pct = floor(scale * 100 + 0.5)
            readout:SetText(zoom and string.format("%d%%", pct) or string.format(opts.translateFitText and TR("Fit %d%%") or "Fit %d%%", pct))
        end
        local fitText = PathValue(box, opts.fitButtonTextPath or { "zoomFitButton", "fs" })
        if fitText then fitText:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1) end
        -- Previews that opted into the zoom lock mirror the same state on it.
        if type(box.RefreshZoomLock) == "function" then box.RefreshZoomLock() end
    end
    function ZoomPan.ApplyPan(box)
        if opts.panMode == "topLeft" then
            if not (box and box._stage and box._mock and box._mock.GetPoint) then return false end
            local x = (tonumber(box._mockBaseOffsetX) or 0) + (tonumber(box._zoomPanX) or 0)
            local y = (tonumber(box._mockBaseOffsetY) or 0) + (tonumber(box._zoomPanY) or 0)
            local oldPoint, oldRelative, oldRelativePoint, oldX, oldY = box._mock:GetPoint(1)
            box._mock:ClearAllPoints()
            box._mock:SetPoint("TOPLEFT", box._stage, "TOPLEFT", x, y)
            if oldPoint == "TOPLEFT" and oldRelative == box._stage and oldRelativePoint == "TOPLEFT" then
                H.ShiftPreviewPanFollowers(box, x - (tonumber(oldX) or 0), y - (tonumber(oldY) or 0))
            end
            local point, relative, relativePoint, actualX, actualY = box._mock:GetPoint(1)
            return point == "TOPLEFT" and relative == box._stage and relativePoint == "TOPLEFT"
                and SameOffset(actualX, x) and SameOffset(actualY, y)
        end
        if not (box and box.canvas and box.mock and box.mock.GetPoint) then return false end
        local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        local expectedX = (tonumber(box._mockBaseOffsetX) or 0) + panX
        local expectedY = (tonumber(box._mockBaseOffsetY) or 0) + panY
        local oldPoint, oldRelative, oldRelativePoint, oldX, oldY = box.mock:GetPoint(1)
        box.mock:ClearAllPoints()
        box.mock:SetPoint("CENTER", box.canvas, "CENTER", expectedX, expectedY)
        if oldPoint == "CENTER" and oldRelative == box.canvas and oldRelativePoint == "CENTER" then
            H.ShiftPreviewPanFollowers(box, expectedX - (tonumber(oldX) or 0), expectedY - (tonumber(oldY) or 0))
        end
        if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
            box.mock.cast:ClearAllPoints()
            box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
        end
        local point, relative, relativePoint, actualX, actualY = box.mock:GetPoint(1)
        return point == "CENTER" and relative == box.canvas and relativePoint == "CENTER"
            and SameOffset(actualX, expectedX) and SameOffset(actualY, expectedY)
    end
    function ZoomPan.GetPan(box)
        if not box then return nil end
        return tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    end
    function ZoomPan.SetPan(box, x, y)
        if not box then return false, "preview-unavailable" end
        x, y = ExactPanNumber(x), ExactPanNumber(y)
        if x == nil or y == nil then return false, "invalid-pan" end
        local beforeX, beforeY = ZoomPan.GetPan(box)
        if beforeX == x and beforeY == y then return true, beforeX, beforeY, beforeX, beforeY end
        box._zoomPanX, box._zoomPanY = x, y
        local appliedOk, applied = pcall(ZoomPan.ApplyPan, box)
        local afterX, afterY = ZoomPan.GetPan(box)
        if appliedOk and applied == true and afterX == x and afterY == y then
            return true, beforeX, beforeY, afterX, afterY
        end
        box._zoomPanX, box._zoomPanY = beforeX, beforeY
        local rollbackOk, rolledBack = pcall(ZoomPan.ApplyPan, box)
        local restoredX, restoredY = ZoomPan.GetPan(box)
        if not rollbackOk or rolledBack ~= true or restoredX ~= beforeX or restoredY ~= beforeY then
            return false, "rollback-failed"
        end
        return false, appliedOk and "pan-readback-mismatch" or "pan-write-failed"
    end
    function ZoomPan.NudgePan(box, dx, dy)
        dx, dy = ExactPanNumber(dx), ExactPanNumber(dy)
        if dx == nil or dy == nil then return false, "invalid-delta" end
        local beforeX, beforeY = ZoomPan.GetPan(box)
        if beforeX == nil or beforeY == nil then return false, "preview-unavailable" end
        return ZoomPan.SetPan(box, beforeX + dx, beforeY + dy)
    end
    function ZoomPan.SetZoom(box, zoom, reason)
        if not box then return end
        -- Any explicit Fit/1:1/step/lock action supersedes the one-shot default.
        box._msuf2ZoomLockDefaultPending = nil
        if zoom == nil or zoom == "fit" then
            box._manualZoom = nil
            box._zoomPanX, box._zoomPanY = 0, 0
        else
            box._manualZoom = ZoomPan.Clamp(zoom)
        end
        ZoomPan.UpdateControls(box)
        reason = reason or opts.defaultReason or "UNIT_PREVIEW_ZOOM"
        if type(opts.refresh) == "function" then
            opts.refresh(box, reason, deps)
        elseif box.Refresh then
            box:Refresh(reason)
        end
    end
    function ZoomPan.Step(box, direction)
        if not box then return end
        local current = ZoomPan.Clamp(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
        local nextZoom = current
        if (tonumber(direction) or 0) > 0 then
            for i = 1, #steps do
                if steps[i] > current + 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        else
            for i = #steps, 1, -1 do
                if steps[i] < current - 0.001 then
                    nextZoom = steps[i]
                    break
                end
            end
        end
        ZoomPan.SetZoom(box, nextZoom, opts.stepReason or "UNIT_PREVIEW_ZOOM_STEP")
    end
    function ZoomPan.Stop(surface)
        if not surface then return end
        local box = surface[PAN_BOX]
        -- Capture the completed gesture before the pan slots are cleared so a
        -- preview can count real moves (button held AND position changed) and
        -- retire its own onboarding hint.
        local button = surface[PAN_BUTTON]
        local startX, startY = surface[PAN_START_X], surface[PAN_START_Y]
        surface[PAN_PANNING], surface[PAN_BOX], surface[PAN_BUTTON] = nil, nil, nil
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = nil, nil
        surface[PAN_START_X], surface[PAN_START_Y] = nil, nil
        surface:SetScript("OnUpdate", nil)
        if box and type(box.OnPreviewCanvasMoved) == "function" and button then
            local moved = (tonumber(box._zoomPanX) or 0) ~= (tonumber(startX) or 0)
                or (tonumber(box._zoomPanY) or 0) ~= (tonumber(startY) or 0)
            if moved then box.OnPreviewCanvasMoved(box, button) end
        end
        local update = deps[opts.updateHintKey or "UpdateHandleHint"]
        if box and type(update) == "function" then update(box, box._selectedHandle) end
    end
    function ZoomPan.Start(surface, box, button, allowPlainLeft)
        if not (surface and box) then return false end
        if surface[PAN_PANNING] then return true end
        local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
        local backgroundLeft = allowPlainLeft == true and button == "LeftButton"
        if not (backgroundLeft or ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
        if not box._manualZoom then
            box._manualZoom = ZoomPan.Clamp(box._mockScale or box._mockAutoScale or 1)
            ZoomPan.UpdateControls(box)
        end
        local cx, cy = GetCursorPosition()
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        surface[PAN_PANNING], surface[PAN_BOX] = true, box
        surface[PAN_BUTTON] = button
        surface[PAN_CURSOR_X], surface[PAN_CURSOR_Y] = (cx or 0) / uiScale, (cy or 0) / uiScale
        surface[PAN_START_X], surface[PAN_START_Y] = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
        local hint = box[opts.hintField or "hint"]
        if hint then hint:SetText(TR("moving preview canvas - release mouse to stop - Fit recenters")) end
        surface:SetScript("OnUpdate", function(self)
            if not self[PAN_PANNING] then return end
            if IsMouseButtonDown and self[PAN_BUTTON] and not IsMouseButtonDown(self[PAN_BUTTON]) then
                ZoomPan.Stop(self)
                return
            end
            local mx, my = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            local nextX = Round((self[PAN_START_X] or 0) + ((mx or 0) / scale - (self[PAN_CURSOR_X] or 0)))
            local nextY = Round((self[PAN_START_Y] or 0) + ((my or 0) / scale - (self[PAN_CURSOR_Y] or 0)))
            if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
                box._zoomPanX, box._zoomPanY = nextX, nextY
                ZoomPan.ApplyPan(box)
            end
        end)
        return true
    end
    function ZoomPan.CreateButton(parent, text, width, tooltip, onClick)
        local T = deps.T
        local template = (opts.themeButton and T and T.Template and T.Template()) or (opts.buttonTemplate or "BackdropTemplate")
        local btn = CreateFrame("Button", nil, parent, template)
        local tex = deps[opts.buttonTextureKey or "TEX_W8"] or white
        btn:SetSize(width or 24, opts.buttonHeight or 20)
        if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
        local useSuperellipse = opts.themeButton and T and T.CreateSuperellipseLayers
        if useSuperellipse then
            local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2PreviewZoom", 2, "BACKGROUND", "BORDER")
            btn._msuf2PreviewZoomFill = fill
            btn._msuf2PreviewZoomEdge = edge
        elseif btn.SetBackdrop then
            btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
            btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
            btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        end
        local fontField = opts.buttonFontField or "fs"
        if opts.themeButton and T and T.Font then
            btn[fontField] = T.Font(btn, "GameFontDisableSmall", text, { 0.78, 0.84, 0.96, 1 })
        elseif not opts.themeButton then
            btn[fontField] = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn[fontField]:SetText(text)
            btn[fontField]:SetTextColor(0.78, 0.84, 0.96, 1)
            if T and T.StyleFontString then T.StyleFontString(btn[fontField], { 0.78, 0.84, 0.96, 1 }, 0) end
        end
        if btn[fontField] then btn[fontField]:SetPoint("CENTER") end
        btn:SetScript("OnClick", onClick)
        local tc = T and T.colors
        local shadow = tc and tc.coreShadow or { 0.006, 0.016, 0.032 }
        local surface = tc and tc.coreSurface or { 0.014, 0.038, 0.072 }
        local raised = tc and tc.coreRaised or { 0.026, 0.070, 0.110 }
        local rim = tc and tc.coreRim or { 0.043, 0.096, 0.150 }
        local blue = tc and tc.coreBlue or { 0.095, 0.360, 0.560 }
        local bgIdle, bgHover, bgDown = { shadow[1], shadow[2], shadow[3], 0.92 }, { surface[1], surface[2], surface[3], 0.98 }, { raised[1], raised[2], raised[3], 0.98 }
        local brIdle, brHover, brDown = { rim[1], rim[2], rim[3], 0.72 }, { blue[1], blue[2], blue[3], 0.58 }, { blue[1], blue[2], blue[3], 0.70 }
        local bgScratch = { 0, 0, 0, 1 }
        local function ApplyButtonVisual(self, hover, down)
            if useSuperellipse then
                local alpha = (self.IsEnabled and not self:IsEnabled()) and 0.42 or 1
                local bg = down and bgDown or (hover and bgHover or bgIdle)
                local br = down and brDown or (hover and brHover or brIdle)
                if self._msuf2PreviewZoomFill then
                    if T.SetFillGradient then
                        bgScratch[1], bgScratch[2], bgScratch[3], bgScratch[4] = bg[1], bg[2], bg[3], (bg[4] or 1) * alpha
                        T.SetFillGradient(self._msuf2PreviewZoomFill, bgScratch, 0.12, -0.18)
                    else
                        self._msuf2PreviewZoomFill:SetVertexColor(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
                    end
                end
                if self._msuf2PreviewZoomEdge then
                    self._msuf2PreviewZoomEdge:SetVertexColor(min(br[1] * (hover and 1.08 or 1), 1), min(br[2] * (hover and 1.08 or 1), 1), min(br[3] * (hover and 1.08 or 1), 1), (br[4] or 1) * alpha)
                end
                if self[fontField] and self[fontField].SetTextColor then
                    self[fontField]:SetTextColor(hover and 0.88 or 0.78, hover and 0.94 or 0.84, 1.00, alpha)
                end
                return
            end
            local bg = hover and bgHover or bgIdle
            local br = hover and brHover or brIdle
            if self.SetBackdropColor then self:SetBackdropColor(bg[1], bg[2], bg[3], hover and 0.98 or 0.88) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(br[1], br[2], br[3], hover and 1 or 0.92) end
        end
        btn:SetScript("OnMouseDown", function(self)
            self._msuf2PreviewZoomDown = true
            ApplyButtonVisual(self, self._msuf2PreviewZoomHover, true)
        end)
        btn:SetScript("OnMouseUp", function(self)
            self._msuf2PreviewZoomDown = nil
            ApplyButtonVisual(self, self._msuf2PreviewZoomHover, false)
        end)
        btn:SetScript("OnEnter", function(self)
            self._msuf2PreviewZoomHover = true
            ApplyButtonVisual(self, true, self._msuf2PreviewZoomDown)
            if GameTooltip and tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(TR(tooltip), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self._msuf2PreviewZoomHover = nil
            self._msuf2PreviewZoomDown = nil
            ApplyButtonVisual(self, false, false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnEnable", function(self) ApplyButtonVisual(self, self._msuf2PreviewZoomHover, self._msuf2PreviewZoomDown) end)
        btn:SetScript("OnDisable", function(self) ApplyButtonVisual(self, false, false) end)
        ApplyButtonVisual(btn, false, false)
        return btn
    end
end

-- Interactive preview children (handles, zoom buttons, drag catchers) sit
-- above the canvas and can become the wheel target themselves. Bind them to
-- the same semantic route so Ctrl+wheel still zooms while an ordinary wheel
-- tick always reaches the page ScrollFrame exactly once.
function H.BindPreviewWheel(frame, box, wheelHandler)
    if not (frame and frame.EnableMouseWheel and frame.SetScript) then return false end
    wheelHandler = wheelHandler or (box and box._msuf2PreviewZoomWheel)
    if type(wheelHandler) ~= "function" then return false end
    frame:EnableMouseWheel(true)
    if frame.SetPropagateMouseWheel then frame:SetPropagateMouseWheel(false) end
    frame:SetScript("OnMouseWheel", wheelHandler)
    return true
end

function H.BuildZoomBar(box, surface, opts)
    if not (box and surface) then return nil end
    opts = opts or {}
    local tr = opts.Tr or F.Identity
    local tex = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local template = opts.template or "BackdropTemplate"
    local stepZoom = opts.StepZoom or F.Noop
    local setZoom = opts.SetZoom or F.Noop
    local panEnabled = type(opts.StartPan) == "function"
    local startPan = opts.StartPan or F.False
    local stopPan = opts.StopPan or F.Noop
    local buttonH = tonumber(opts.buttonHeight) or 20
    local createButton = opts.CreateZoomButton or function(parent, text, width, tooltip, onClick)
        local btn = CreateFrame("Button", nil, parent, template)
        btn:SetSize(width or 24, buttonH)
        btn:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    local prefix = opts.fieldPrefix or ""
    local zoomBar = CreateFrame("Frame", nil, surface, template)
    zoomBar:SetSize(opts.width or (opts.lockButton and 226 or 200), opts.height or 24)
    zoomBar:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -8, -8)
    zoomBar:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1 })
    if opts.flatChrome ~= false and (opts.T or opts.flatChrome == true) then
        zoomBar:SetBackdropColor(0, 0, 0, 0)
        zoomBar:SetBackdropBorderColor(0, 0, 0, 0)
    else
        zoomBar:SetBackdropColor(0.015, 0.018, 0.030, 0.86)
        zoomBar:SetBackdropBorderColor(0.10, 0.14, 0.22, 0.92)
    end
    if zoomBar.SetFrameLevel then zoomBar:SetFrameLevel((surface.GetFrameLevel and surface:GetFrameLevel() or 0) + 80) end
    zoomBar:EnableMouse(true)
    zoomBar:EnableMouseWheel(true)
    if surface.SetPropagateMouseWheel then surface:SetPropagateMouseWheel(false) end
    if zoomBar.SetPropagateMouseWheel then zoomBar:SetPropagateMouseWheel(false) end
    box[prefix .. "zoomBar"] = zoomBar
    local function AddZoomButton(field, text, width, tooltip, onClick, relativeTo, offset)
        local btn = createButton(zoomBar, text, width, tooltip, onClick)
        if relativeTo then
            btn:SetPoint("LEFT", relativeTo, "RIGHT", offset or 3, 0)
        else
            btn:SetPoint("LEFT", zoomBar, "LEFT", offset or 3, 0)
        end
        box[prefix .. field] = btn
        return btn
    end
    zoomBar:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr("Preview zoom"), 1, 1, 1)
            GameTooltip:AddLine(tr("Use the buttons or Ctrl + mouse wheel to zoom."), 0.82, 0.82, 0.82, true)
            if panEnabled then
                GameTooltip:AddLine(tr("Drag empty preview space to move the canvas. Fit recenters it."), 0.55, 0.68, 0.86, true)
            else
                GameTooltip:AddLine(tr("Fit shows the complete preview; 1:1 shows its configured pixel size."), 0.55, 0.68, 0.86, true)
            end
            GameTooltip:AddLine(tr("Use ? for all preview controls."), 0.50, 0.78, 0.92, true)
            GameTooltip:Show()
        end
    end)
    zoomBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    local zoomOut = AddZoomButton("zoomOutButton", "-", 20, "Zoom out", function() stepZoom(box, -1) end)
    local T = opts.T
    local readout
    if opts.themeReadout and T and T.Font then
        readout = T.Font(zoomBar, "GameFontDisableSmall", "", { 0.72, 0.78, 0.90, 1 })
    else
        readout = zoomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        readout:SetTextColor(0.72, 0.78, 0.90, 1)
        if T and T.StyleFontString then T.StyleFontString(readout, { 0.72, 0.78, 0.90, 1 }, 0) end
    end
    readout:SetPoint("LEFT", zoomOut, "RIGHT", 3, 0)
    readout:SetSize(54, buttonH)
    readout:SetJustifyH("CENTER")
    box[prefix .. "zoomReadout"] = readout
    local zoomIn = AddZoomButton("zoomInButton", "+", 20, "Zoom in", function() stepZoom(box, 1) end, readout)
    local fitButton = AddZoomButton("zoomFitButton", "Fit", 30, "Fit preview", function() setZoom(box, nil, opts.fitReason) end, zoomIn)
    local oneButton = AddZoomButton("zoomOneButton", "1:1", 32, "Pixel preview", function() setZoom(box, 1, opts.oneReason) end, fitButton)
    local helpButton = AddZoomButton("zoomHelpButton", "?", 20, "Preview controls", function(self)
        H.ShowPreviewControlsHelp(self, {
            M = opts.M or M, T = opts.T, W = opts.W, Tr = tr,
            title = opts.helpTitle, lines = opts.helpLines,
        })
    end, oneButton)
    if opts.lockButton then
        local lock = H.EnsureZoomLockButton(box, zoomBar, {
            T = opts.T, Tr = tr, SetZoom = setZoom, buttonHeight = buttonH,
            lockReason = opts.lockReason, unlockReason = opts.unlockReason,
            defaultLocked = opts.defaultLocked,
        })
        if lock then lock:SetPoint("LEFT", helpButton, "RIGHT", 3, 0) end
    end
    local function ZoomWheel(self, delta)
        local dir = (delta or 0) > 0 and 1 or -1
        -- Route the event explicitly. Toggling propagation from inside the
        -- wheel handler is timing-dependent in WoW and could swallow the first
        -- normal wheel tick after preview zooming.
        if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
        if IsControlKeyDown and IsControlKeyDown() then
            stepZoom(box, dir)
        else
            local menu = opts.M or M
            local forward = menu and menu.ForwardMenuScrollWheel
            if type(forward) == "function" then
                forward(delta)
            else
                local main = menu and menu.scrollFrame
                local handler = main and main.GetScript and main:GetScript("OnMouseWheel")
                if type(handler) == "function" then handler(main, delta) end
            end
        end
    end
    box._msuf2PreviewZoomWheel = ZoomWheel
    if opts.wheelField then box[opts.wheelField] = ZoomWheel end
    H.BindPreviewWheel(surface, box, ZoomWheel)
    H.BindPreviewWheel(zoomBar, box, ZoomWheel)
    H.BindPreviewWheel(zoomOut, box, ZoomWheel)
    H.BindPreviewWheel(fitButton, box, ZoomWheel)
    H.BindPreviewWheel(oneButton, box, ZoomWheel)
    H.BindPreviewWheel(zoomIn, box, ZoomWheel)
    H.BindPreviewWheel(helpButton, box, ZoomWheel)
    H.BindPreviewWheel(box[prefix .. "zoomLockButton"], box, ZoomWheel)
    local backgroundButton = H.EnsurePreviewBackgroundButton(box, zoomBar, opts)
    H.BindPreviewWheel(backgroundButton, box, ZoomWheel)
    if panEnabled then
        if surface.RegisterForDrag then surface:RegisterForDrag("LeftButton") end
        surface:SetScript("OnMouseDown", function(self, button) startPan(self, box, button, true) end)
        surface:SetScript("OnMouseUp", stopPan)
        surface:SetScript("OnDragStart", function(self, button) startPan(self, box, button, true) end)
        surface:SetScript("OnDragStop", stopPan)
        surface:SetScript("OnHide", stopPan)
    end
    return zoomBar, ZoomWheel
end

-- One logical zoom setting owns the +/-/Fit/1:1 button cluster.  The buttons
-- remain available as explicit actions, while this command supplies natural
-- relative changes ("zoom in", "more", "less") with exact readback.
function H.BuildZoomCommand(box, zoomPan, reason)
    if not (box and type(zoomPan) == "table" and type(zoomPan.SetZoom) == "function") then return nil end
    local minZoom = tonumber(zoomPan.MIN) or 0.35
    local maxZoom = tonumber(zoomPan.MAX) or 4.0
    return {
        kind = "slider",
        historyMode = "none",
        min = floor(minZoom * 100 + 0.5),
        max = floor(maxZoom * 100 + 0.5),
        step = 25,
        percentIsValue = true,
        get = function()
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale)
                or tonumber(box._mockAutoScale) or 1
            return floor(scale * 100 + 0.5)
        end,
        set = function(value)
            value = tonumber(value)
            if not value then return false end
            zoomPan.SetZoom(box, value / 100, reason or "ASSISTANT_PREVIEW_ZOOM")
            local scale = tonumber(box._manualZoom) or tonumber(box._mockScale)
                or tonumber(box._mockAutoScale) or 1
            return floor(scale * 100 + 0.5) == floor(value + 0.5)
        end,
    }
end
function H.BuildPanCommand(box, zoomPan, nudge, metadata)
    if not (box and type(zoomPan) == "table" and type(zoomPan.GetPan) == "function") then return nil end
    metadata = type(metadata) == "table" and metadata or {}
    local function ParseDelta(value)
        if type(value) == "table" then
            return tonumber(value.dx or value.x or value[1]), tonumber(value.dy or value.y or value[2])
        end
        if type(value) == "string" then
            local x, y = value:match("^%s*([%+%-]?%d+%.?%d*)%s*[,;/ ]%s*([%+%-]?%d+%.?%d*)%s*$")
            return tonumber(x), tonumber(y)
        end
        return nil
    end
    local command = {
        kind = "button",
        historyMode = "none",
        skipNavigation = true,
        previewSurface = metadata.previewSurface,
        previewUnitKey = metadata.previewUnitKey,
        interaction = "preview.canvas.pan",
        get = function()
            local x, y = zoomPan.GetPan(box)
            return { x = x, y = y }
        end,
        set = function(value)
            local dx, dy = ParseDelta(value)
            if dx == nil or dy == nil then return false end
            if type(nudge) == "function" then return nudge(dx, dy) end
            if type(zoomPan.NudgePan) ~= "function" then return false end
            return zoomPan.NudgePan(box, dx, dy)
        end,
    }
    return command
end
function H.IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end
function H.KeyDelta(key)
    if key == "LEFT" then return -1, 0 end
    if key == "RIGHT" then return 1, 0 end
    if key == "UP" then return 0, 1 end
    if key == "DOWN" then return 0, -1 end
    return nil, nil
end
function H.NudgeStep(opts)
    opts = opts or {}
    if IsControlKeyDown and IsControlKeyDown() then return tonumber(opts.ctrlStep) or 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return tonumber(opts.shiftStep) or 5 end
    return tonumber(opts.step) or 1
end
function H.ShouldSkipDuplicateNudge(owner, dx, dy, opts)
    if not owner then return false end
    opts = opts or {}
    local now = GetTime and GetTime() or 0
    if now <= 0 then return false end
    local sigKey = opts.sigKey or "_msufLastNudgeSig"
    local atKey = opts.atKey or "_msufLastNudgeAt"
    local sig = tostring(dx or 0) .. ":" .. tostring(dy or 0)
    if owner[sigKey] == sig and (now - (owner[atKey] or 0)) < (tonumber(opts.window) or 0.02) then return true end
    owner[sigKey] = sig
    owner[atKey] = now
    return false
end
local function SetKeyboardPropagate(frame, propagate)
    if frame and frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(propagate == true) end
end
local function InCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end
local function ForEachPreviewKeyboardFrame(owner, callback)
    if not (owner and type(callback) == "function") then return end
    local seen = {}
    local function Visit(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
    Visit(owner)
    local handles = owner.handles
    if type(handles) == "table" then
        for i = 1, #handles do
            Visit(handles[i])
        end
    end
    handles = owner._handleList
    if type(handles) == "table" then
        for i = 1, #handles do
            Visit(handles[i])
        end
    end
end
function H.ReleaseKeyboardCapture(owner)
    ForEachPreviewKeyboardFrame(owner, function(frame)
        SetKeyboardPropagate(frame, true)
    end)
end
function H.FocusKeyboardTarget(owner, handle, defer, opts)
    if not owner then return end
    opts = opts or {}
    local selectedField = opts.selectedField or "_selectedHandle"
    handle = handle or (selectedField and owner[selectedField])
    H.ReleaseKeyboardCapture(owner)
    if InCombatLocked() then return end
    if owner.EnableKeyboard then owner:EnableKeyboard(true) end
    SetKeyboardPropagate(owner, handle and false or true)
    if handle and handle.EnableKeyboard then handle:EnableKeyboard(true) end
    SetKeyboardPropagate(handle, false)
    if handle and handle.SetFocus then
        handle:SetFocus()
    elseif owner.SetFocus then
        owner:SetFocus()
    end
    if defer then
        local selected = handle
        C_Timer.After(0, function()
            if not (owner and owner.IsShown and owner:IsShown()) then return end
            if selected and selected.IsShown and not selected:IsShown() then return end
            if selected and selectedField and owner[selectedField] ~= selected then return end
            H.FocusKeyboardTarget(owner, selected, false, opts)
        end)
    end
end
function H.ArrowKeyDown(self, keyName, opts)
    opts = opts or {}
    local owner = (opts.owner and opts.owner(self)) or (self and self._preview) or self or (opts.active and opts.active())
    if InCombatLocked() then
        H.ReleaseKeyboardCapture(owner)
        SetKeyboardPropagate(self, true)
        return false
    end
    local dx, dy = H.KeyDelta(keyName)
    if not dx then
        SetKeyboardPropagate(self, true)
        SetKeyboardPropagate(owner, true)
        return false
    end
    if H.IsTextInputFocused() then
        H.ReleaseKeyboardCapture(owner)
        SetKeyboardPropagate(self, true)
        return false
    end
    SetKeyboardPropagate(self, false)
    SetKeyboardPropagate(owner, false)
    if opts.nudge and opts.nudge(owner, dx, dy) then
        local selectedField = opts.selectedField or "_selectedHandle"
        local selected = (opts.selected and opts.selected(owner)) or (owner and selectedField and owner[selectedField])
        H.FocusKeyboardTarget(owner, selected, true, opts)
        return true
    end
    SetKeyboardPropagate(self, true)
    SetKeyboardPropagate(owner, true)
    return false
end
function H.RegisterEditModeNudgeTarget(owner, opts)
    local fn = _G.MSUF_EM2_SetPreviewNudgeTarget
    if type(fn) ~= "function" or not owner then return end
    opts = opts or {}
    local targetField = opts.targetField or "_msufPreviewNudgeTarget"
    local selectedField = opts.selectedField or "_selectedHandle"
    local function Selected() return opts.selected and opts.selected(owner) or (selectedField and owner[selectedField]) end
    owner[targetField] = owner[targetField] or {
        frame = owner,
        IsActive = function()
            if InCombatLocked() then return false end
            if not (owner and owner.IsShown and owner:IsShown()) then return false end
            local selected = Selected()
            if opts.canNudge and not opts.canNudge(selected, owner) then return false end
            return selected ~= nil and not H.IsTextInputFocused()
        end,
        Nudge = function(_, dx, dy)
            local ok = opts.nudgeDelta and opts.nudgeDelta(owner, dx, dy)
            if ok then H.FocusKeyboardTarget(owner, Selected(), true, opts) end
            return ok
        end,
    }
    fn(owner[targetField])
end
local PREVIEW_CHROME_FALLBACK = {
    outerBg = { 0.035, 0.067, 0.114, 0.54 },
    outerBorder = { 0.086, 0.149, 0.227, 0.46 },
    canvasBg = { 0.020, 0.039, 0.071, 0.92 },
    canvasBorder = { 0.086, 0.149, 0.227, 0.38 },
    canvasTop = { 0.020, 0.039, 0.071, 0.96 },
    canvasBottom = { 0.027, 0.063, 0.106, 0.90 },
    sidebarBg = { 0.020, 0.039, 0.071, 0.56 },
    sidebarBorder = { 0.086, 0.149, 0.227, 0.32 },
    title = { 0.231, 0.510, 0.965, 1.00 },
    layerHeader = { 0.659, 0.706, 0.780, 0.82 },
    rowBase = { 0.035, 0.067, 0.114, 1.00 },
    rowHover = { 0.055, 0.098, 0.161, 1.00 },
}
local function PreviewChromeColor(source, fallback, alpha)
    source = type(source) == "table" and source or fallback
    return { source[1] or fallback[1], source[2] or fallback[2], source[3] or fallback[3], alpha }
end
function H.PreviewChromePalette(theme)
    local colors = (theme and theme.colors) or {}
    return {
        outerBg = PreviewChromeColor(colors.panel, PREVIEW_CHROME_FALLBACK.outerBg, 0.54),
        outerBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.outerBorder, 0.46),
        canvasBg = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.canvasBg, 0.92),
        canvasBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.canvasBorder, 0.38),
        canvasTop = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.canvasTop, 0.96),
        canvasBottom = PreviewChromeColor(colors.coreInk, PREVIEW_CHROME_FALLBACK.canvasBottom, 0.90),
        sidebarBg = PreviewChromeColor(colors.coreShadow, PREVIEW_CHROME_FALLBACK.sidebarBg, 0.56),
        sidebarBorder = PreviewChromeColor(colors.borderSoft, PREVIEW_CHROME_FALLBACK.sidebarBorder, 0.32),
        -- One controlled blue accent anchors the preview header while the
        -- surrounding card, canvas, and tools remain deliberately quiet.
        title = PreviewChromeColor(colors.accent or colors.coreGlow, PREVIEW_CHROME_FALLBACK.title, 1.00),
        layerHeader = PreviewChromeColor(colors.muted, PREVIEW_CHROME_FALLBACK.layerHeader, 0.82),
        rowBase = PreviewChromeColor(colors.coreSurface or colors.panel, PREVIEW_CHROME_FALLBACK.rowBase, 1.00),
        rowHover = PreviewChromeColor(colors.coreRaised or colors.panel2, PREVIEW_CHROME_FALLBACK.rowHover, 1.00),
    }
end
function H.ApplyPreviewChrome(frame, role, theme, fallback)
    if not frame then return H.PreviewChromePalette(theme) end
    role = role or "outer"
    local palette = H.PreviewChromePalette(theme)
    local bg = role == "canvas" and palette.canvasBg or (role == "sidebar" and palette.sidebarBg or palette.outerBg)
    local border = role == "canvas" and palette.canvasBorder or (role == "sidebar" and palette.sidebarBorder or palette.outerBorder)
    if theme and type(theme.ApplyBackdrop) == "function" then
        theme.ApplyBackdrop(frame, bg, border)
    elseif type(fallback) == "function" then
        fallback(frame, bg, border)
    end
    if role == "outer" and theme and type(theme.ApplyGradient) == "function" then
        theme.ApplyGradient(frame, "card", { key = "_msuf2PreviewCardGradient", alpha = 0.34 })
    elseif role == "canvas" and frame.CreateTexture then
        local gradient = frame._msuf2PreviewCanvasGradient
        if not gradient then
            gradient = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            gradient:SetAllPoints(frame)
            gradient:SetTexture("Interface\\Buttons\\WHITE8X8")
            frame._msuf2PreviewCanvasGradient = gradient
        end
        H.ApplyPreviewBackground(frame, palette, theme)
    end
    return palette
end
local LAYER_BUTTON_FALLBACK_COLOR = { 1, 1, 1 }
local LAYER_BUTTON_SELECTED_BG = { 0.08, 0.34, 0.72, 0.88 }
local function LayerButtonAvailable(owner, key)
    return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
end
local function LayerButtonOn(owner, key)
    return LayerButtonAvailable(owner, key) and not (owner and owner.layerVisibility and owner.layerVisibility[key] == false)
end
local function LayerButtonAvailableFor(owner, key, opts)
    if opts and opts.IsAvailable then return opts.IsAvailable(owner, key) end
    return LayerButtonAvailable(owner, key)
end
local function LayerButtonOnFor(owner, key, opts)
    if opts and opts.IsOn then return opts.IsOn(owner, key) end
    return LayerButtonOn(owner, key)
end
function H.RefreshLayerButton(btn, owner, opts)
    if not btn then return end
    opts = opts or {}
    local available = LayerButtonAvailableFor(owner, btn.key, opts)
    local on = LayerButtonOnFor(owner, btn.key, opts)
    local selected = opts.IsSelected and opts.IsSelected(owner, btn.key) == true
    local c = btn.color or LAYER_BUTTON_FALLBACK_COLOR
    local textOn = opts.textOn or { 0.82, 0.88, 1.00, 0.98 }
    local textOff = opts.textOff or { 0.54, 0.61, 0.72, 0.78 }
    local textDisabled = opts.textDisabled or { 0.42, 0.48, 0.58, 0.62 }
    if btn.off then
        btn.off:SetText(opts.offText or "OFF")
        btn.off:SetShown((opts.showOffText == true) and ((not available) or not on))
    end
    local quiet = opts.quiet == true
    local quietBase = opts.quietBase or PREVIEW_CHROME_FALLBACK.rowBase
    if not available and quiet then
        btn.bg:SetColorTexture(quietBase[1], quietBase[2], quietBase[3], 0.10)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.20)
        btn.fs:SetTextColor(textDisabled[1], textDisabled[2], textDisabled[3], textDisabled[4] or 0.62)
        if btn.off then btn.off:SetTextColor(textDisabled[1], textDisabled[2], textDisabled[3], 0.62) end
    elseif selected and quiet then
        local selectedBg = opts.selectedBg or LAYER_BUTTON_SELECTED_BG
        btn.bg:SetColorTexture(selectedBg[1], selectedBg[2], selectedBg[3], selectedBg[4] or 0.88)
        btn.bar:SetColorTexture(c[1], c[2], c[3], on and 1.00 or 0.38)
        btn.fs:SetTextColor(0.96, 0.98, 1.00, 1.00)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], on and 0 or 0.78) end
    elseif on and quiet then
        btn.bg:SetColorTexture(quietBase[1], quietBase[2], quietBase[3], 0.34)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.76)
        btn.fs:SetTextColor(textOn[1], textOn[2], textOn[3], textOn[4] or 0.96)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], 0.0) end
    elseif quiet then
        btn.bg:SetColorTexture(quietBase[1], quietBase[2], quietBase[3], 0.08)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.26)
        btn.fs:SetTextColor(textOff[1], textOff[2], textOff[3], textOff[4] or 0.74)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], 0.72) end
    elseif not available then
        btn.bg:SetColorTexture(0.010, 0.018, 0.030, 0.32)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.30)
        btn.fs:SetTextColor(textDisabled[1], textDisabled[2], textDisabled[3], textDisabled[4] or 0.62)
        if btn.off then btn.off:SetTextColor(textDisabled[1], textDisabled[2], textDisabled[3], 0.72) end
    elseif selected then
        btn.bg:SetColorTexture(0.08, 0.34, 0.72, 0.88)
        btn.bar:SetColorTexture(c[1], c[2], c[3], on and 1.00 or 0.42)
        btn.fs:SetTextColor(0.96, 0.98, 1.00, 1.00)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], on and 0 or 0.78) end
    elseif on then
        btn.bg:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 0.54)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.94)
        btn.fs:SetTextColor(textOn[1], textOn[2], textOn[3], textOn[4] or 0.98)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], 0.0) end
    else
        btn.bg:SetColorTexture(0.010, 0.018, 0.030, 0.26)
        btn.bar:SetColorTexture(c[1], c[2], c[3], 0.42)
        btn.fs:SetTextColor(textOff[1], textOff[2], textOff[3], textOff[4] or 0.78)
        if btn.off then btn.off:SetTextColor(textOff[1], textOff[2], textOff[3], 0.78) end
    end
end
function H.RefreshSelectedLayerButtons(owner, selectedHandle, buttonsField)
    if not owner then return end
    local selectedKey = selectedHandle and selectedHandle._previewLayerKey or nil
    if owner._msuf2SelectedPreviewLayerKey == selectedKey then return end
    owner._msuf2SelectedPreviewLayerKey = selectedKey
    local buttons = owner[buttonsField or "layerButtons"] or {}
    for i = 1, #buttons do
        local button = buttons[i]
        if button and button.Refresh then button:Refresh()
        elseif button and button.refresh then button:refresh() end
    end
end
--- Chip rows measure themselves so a caller can flow them horizontally; the
--- docked row layout keeps its fixed column width.
local function LayoutLayerChip(btn, h)
    btn.bar:SetSize(7, 7)
    btn.bar:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.fs:ClearAllPoints()
    btn.fs:SetPoint("LEFT", btn.bar, "RIGHT", 6, 0)
    btn.fs:SetJustifyH("LEFT")
    local textWidth = btn.fs.GetStringWidth and btn.fs:GetStringWidth() or 0
    if not textWidth or textWidth <= 0 then textWidth = #tostring(btn.fs:GetText() or btn.key or "") * 6 end
    btn:SetSize(floor(textWidth + 0.5) + 30, h)
end
function H.CreateLayerButton(parent, owner, def, index, sideW, opts)
    if not (parent and def) then return nil end
    opts = opts or {}
    local tr = opts.Tr or F.Identity
    local theme = opts.T or (M and M.Theme)
    local chip = opts.layout == "chip"
    local btn = CreateFrame("Button", nil, parent)
    local h = opts.height or 20
    if not chip then
        btn:SetSize((sideW or 80) - 12, h)
        btn:SetPoint("TOP", parent, "TOP", 0, -((opts.topOffset or 20) + ((index or 1) - 1) * (opts.rowHeight or h)))
    end
    btn:EnableMouse(true)
    btn.key, btn.color, btn.tooltip = def.key, def.color, def.tooltip
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bar = btn:CreateTexture(nil, "ARTWORK")
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if not chip then
        btn.bar:SetSize(3, h - 5)
        btn.bar:SetPoint("LEFT", btn, "LEFT", 3, 0)
        btn.fs:SetPoint("LEFT", btn.bar, "RIGHT", 8, 0)
        btn.fs:SetPoint("RIGHT", btn, "RIGHT", opts.showOffText == true and -24 or -8, 0)
        btn.fs:SetJustifyH("LEFT")
    end
    btn.fs:SetText(tr(def.label))
    if theme and theme.ApplyMenuFont then theme.ApplyMenuFont(btn.fs, 0) end
    if chip then LayoutLayerChip(btn, h) end
    btn.off = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn.off:SetText(opts.offText or "OFF")
    btn.off:SetJustifyH("RIGHT")
    if theme and theme.ApplyMenuFont then theme.ApplyMenuFont(btn.off, 0) end
    function btn:Refresh() H.RefreshLayerButton(self, owner, opts) end
    btn.refresh = btn.Refresh
    btn:SetScript("OnClick", function(self)
        if opts.OnClick then
            opts.OnClick(self, owner)
            return
        end
        if not LayerButtonAvailable(owner, self.key) then return end
        owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
        self:Refresh()
    end)
    -- Layer pills are toggles, not fire-and-forget buttons.  Expose the exact
    -- state transition to RuntimeControlCatalog so Assistant requests such as
    -- "show Guides" and "hide Guides" are idempotent and disabled layers can
    -- fail closed instead of silently inverting another state.
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function()
            return LayerButtonAvailableFor(owner, btn.key, opts)
                and LayerButtonOnFor(owner, btn.key, opts) or false
        end,
        set = function(value)
            if not LayerButtonAvailableFor(owner, btn.key, opts) then return false end
            local desired = value == true
            local current = LayerButtonOnFor(owner, btn.key, opts) and true or false
            if current == desired then return true end
            if opts.OnClick then
                opts.OnClick(btn, owner)
            else
                owner.layerVisibility[btn.key] = desired
                btn:Refresh()
            end
            return (LayerButtonOnFor(owner, btn.key, opts) and true or false) == desired
        end,
    }
    btn:SetScript("OnEnter", function(self)
        local available = LayerButtonAvailableFor(owner, self.key, opts)
        local on = LayerButtonOnFor(owner, self.key, opts)
        local c = self.color or LAYER_BUTTON_FALLBACK_COLOR
        if opts.quiet == true then
            local hover = opts.quietHover or PREVIEW_CHROME_FALLBACK.rowHover
            self.bg:SetColorTexture(hover[1], hover[2], hover[3], available and 0.42 or 0.18)
            self.bar:SetColorTexture(c[1], c[2], c[3], available and 0.90 or 0.36)
        else
            self.bg:SetColorTexture((available and on) and c[1] * 0.18 or 0.026, (available and on) and c[2] * 0.18 or 0.070, (available and on) and c[3] * 0.18 or 0.110, (available and on) and 0.74 or 0.58)
            self.bar:SetColorTexture(c[1], c[2], c[3], available and 1.0 or 0.48)
        end
        self.fs:SetTextColor(0.90, 0.92, 1, 1)
        if opts.OnEnter then
            opts.OnEnter(self, owner, available, on, tr)
        elseif GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr(self.fs:GetText() or self.key), 1, 1, 1)
            if self.tooltip then GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true) end
            if not available and opts.disabledLine then GameTooltip:AddLine(tr(opts.disabledLine), 0.55, 0.68, 0.86, true) end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:Refresh()
        if opts.OnLeave then opts.OnLeave(self, owner) end
    end)
    btn:Refresh()
    return btn
end
--- Flows measured layer chips into `rail`, wrapping when a row is full.
--- Returns the height the rail needs, so callers can let the canvas absorb
--- whatever the chips do not use instead of reserving a fixed strip.
function H.FlowLayerChips(rail, buttons, opts)
    opts = opts or {}
    if not (rail and buttons) then return 0 end
    local padX, padY = opts.padX or 8, opts.padY or 5
    local gapX, gapY = opts.gapX or 5, opts.gapY or 4
    local rowH = opts.rowHeight or 20
    local available = (tonumber(opts.width) or (rail.GetWidth and rail:GetWidth()) or 0) - padX * 2
    if available <= 0 then available = 480 end
    local x, rows = 0, 1
    for i = 1, #buttons do
        local btn = buttons[i]
        -- Hidden layer buttons (a feature the surface does not expose) must not
        -- leave a gap in the flow.
        if btn and (not btn.IsShown or btn:IsShown()) then
            local w = (btn.GetWidth and btn:GetWidth()) or 60
            if x > 0 and (x + w) > available then
                x = 0
                rows = rows + 1
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", rail, "TOPLEFT", padX + x, -(padY + (rows - 1) * (rowH + gapY)))
            x = x + w + gapX
        end
    end
    local height = padY * 2 + rows * rowH + (rows - 1) * gapY
    if rail.SetHeight then rail:SetHeight(height) end
    rail._msuf2ChipRows = rows
    return height
end
local TEXT_FOCUS_SIDES = { "top", "bottom", "left", "right" }
local EDGE_ANCHORS = {
    top = { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    left = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    right = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}
function H.NormalizeTextFocusKind(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end
function H.NormalizeTextFocusSlot(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end
function H.TextFocusColor(kind, colors)
    colors = colors or {}
    if kind == "hp" then return colors.hp or { 0.28, 0.86, 0.45 } end
    if kind == "power" then return colors.power or { 0.95, 0.72, 0.18 } end
    return colors.name or { 0.30, 0.66, 1.00 }
end
function H.EnsureTextFocusFrame(box, parent)
    if not (box and parent) then return nil end
    local f = box._msufMenuTextFocusFrame
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:EnableMouse(false)
        f.fill = f:CreateTexture(nil, "BACKGROUND")
        f.fill:SetAllPoints()
        f.lines = {}
        for i = 1, #TEXT_FOCUS_SIDES do
            local side = TEXT_FOCUS_SIDES[i]
            local line = f:CreateTexture(nil, "OVERLAY")
            line:SetPoint(EDGE_ANCHORS[side][1])
            line:SetPoint(EDGE_ANCHORS[side][2])
            f.lines[side] = line
        end
        box._msufMenuTextFocusFrame = f
    elseif f.SetParent then
        f:SetParent(parent)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then f:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
    return f
end
function H.PaintTextFocusFrame(frame, color, active)
    if not (frame and color) then return end
    local lineAlpha = active and 0.92 or 0.74
    local fillAlpha = active and 0.10 or 0.065
    local thickness = active and 2 or 1
    if frame.fill then frame.fill:SetColorTexture(color[1], color[2], color[3], fillAlpha) end
    if frame.lines then
        frame.lines.top:SetHeight(thickness)
        frame.lines.bottom:SetHeight(thickness)
        frame.lines.left:SetWidth(thickness)
        frame.lines.right:SetWidth(thickness)
        for _, line in pairs(frame.lines) do
            if line then line:SetColorTexture(color[1], color[2], color[3], lineAlpha) end
        end
    end
end
function H.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    opts = opts or {}
    pad = tonumber(pad) or 3
    local min, max = math.min, math.max
    local parentScale = parent.GetEffectiveScale and tonumber(parent:GetEffectiveScale()) or 1
    if not parentScale or parentScale <= 0 then parentScale = 1 end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (pLeft and pBottom) then return false end
    local parentScaledLeft, parentScaledBottom
    if opts.useScaledRect and parent.GetScaledRect then
        parentScaledLeft, parentScaledBottom = parent:GetScaledRect()
    end
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b, scaleRatio
            if parentScaledLeft and parentScaledBottom and region.GetScaledRect then
                local scaledLeft, scaledBottom, scaledWidth, scaledHeight = region:GetScaledRect()
                if scaledLeft and scaledBottom and scaledWidth and scaledHeight then
                    -- GetScaledRect is already the final on-screen rectangle.
                    -- Convert it directly into the unscaled handle parent's
                    -- coordinate space instead of inferring the scaled origin.
                    l = (scaledLeft - parentScaledLeft) / parentScale
                    r = (scaledLeft + scaledWidth - parentScaledLeft) / parentScale
                    b = (scaledBottom - parentScaledBottom) / parentScale
                    t = (scaledBottom + scaledHeight - parentScaledBottom) / parentScale
                    local regionScale = region.GetEffectiveScale and tonumber(region:GetEffectiveScale()) or parentScale
                    if not regionScale or regionScale <= 0 then regionScale = parentScale end
                    scaleRatio = regionScale / parentScale
                end
            end
            if not (l and r and t and b) then
                l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
                scaleRatio = tonumber(opts.coordinateScale)
                if not scaleRatio or scaleRatio <= 0 then
                    local regionScale = region.GetEffectiveScale and tonumber(region:GetEffectiveScale()) or parentScale
                    if not regionScale or regionScale <= 0 then regionScale = parentScale end
                    scaleRatio = regionScale / parentScale
                end
                if l and r and t and b then
                    l, r = l * scaleRatio - pLeft, r * scaleRatio - pLeft
                    t, b = t * scaleRatio - pBottom, b * scaleRatio - pBottom
                end
            end
            if l and r and t and b then
                if opts.fitText then
                    local regionW = r - l
                    if region.GetStringWidth and regionW > 0 then
                        local textW = (tonumber(region:GetStringWidth()) or 0) * scaleRatio
                        if textW > 0 and textW < regionW then
                            local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                            if justify == "RIGHT" then
                                l = r - textW
                            elseif justify == "CENTER" then
                                local cx = (l + r) * 0.5
                                l, r = cx - (textW * 0.5), cx + (textW * 0.5)
                            else
                                r = l + textW
                            end
                        end
                    end
                    local regionH = t - b
                    if region.GetStringHeight and regionH > 0 then
                        local textH = (tonumber(region:GetStringHeight()) or 0) * scaleRatio
                        if textH > 0 and textH < regionH then
                            local cy = (t + b) * 0.5
                            t, b = cy + (textH * 0.5), cy - (textH * 0.5)
                        end
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    if not (left and right and top and bottom) then return false end
    local naturalWidth = right - left + pad * 2
    local naturalHeight = top - bottom + pad * 2
    local handleWidth = max(18, naturalWidth)
    local handleHeight = max(18, naturalHeight)
    handle:ClearAllPoints()
    handle:SetSize(handleWidth, handleHeight)
    -- A minimum hit area must grow equally around the rendered region. Growing
    -- only towards the top/right moves handle:GetCenter() away from the visual
    -- center, which in turn biases the shared X/Y readout at small Fit scales.
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        left - pad - ((handleWidth - naturalWidth) * 0.5),
        bottom - pad - ((handleHeight - naturalHeight) * 0.5))
    handle._msufPreviewPanFollower = true
    handle:Show()
    return true
end
function H.ApplyTextFocus(box, parent, mock, opts)
    opts = opts or {}
    local focus = box and box._msufMenuTextFocus
    local frame = box and box._msufMenuTextFocusFrame
    if not (focus and parent and mock) then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    local regions = opts.Regions and opts.Regions(mock, focus.kind, focus.slot)
    if not regions then
        if frame and frame.Hide then frame:Hide() end
        return
    end
    frame = H.EnsureTextFocusFrame(box, parent)
    if not frame then return end
    local color = (opts.Color and opts.Color(focus.kind)) or H.TextFocusColor(focus.kind, opts.colors)
    H.PaintTextFocusFrame(frame, color, focus.active == true)
    if not (opts.Place and opts.Place(frame, parent, regions, focus.active and 5 or 4, focus.kind, focus.slot)) then frame:Hide() end
end
function H.SnapOff(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end
function H.MaskOwner(mock, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and owner.CreateMaskTexture then return owner end
    if anchor and anchor.CreateMaskTexture then return anchor end
    return mock
end
function H.EnsureRoundedMask(mock, key, anchor, tex, maskStoreKey, maskTexture, snapOff)
    if not (mock and anchor) then return nil end
    local owner = H.MaskOwner(mock, tex, anchor)
    if not (owner and owner.CreateMaskTexture) then return nil end
    maskStoreKey = maskStoreKey or "_msufPreviewRoundedMasks"
    mock[maskStoreKey] = mock[maskStoreKey] or {}
    local store = mock[maskStoreKey]
    local bucket = store[key]
    if type(bucket) ~= "table" or bucket.SetTexture then
        bucket = {}
        store[key] = bucket
    end
    local ownerKey = tex or owner
    local mask = bucket[ownerKey]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "ARTWORK")
        local snap = snapOff or H.SnapOff
        snap(mask)
        bucket[ownerKey] = mask
    end
    if mask._msufPreviewRoundedAnchor ~= anchor or mask._msufPreviewRoundedTexture ~= maskTexture then
        mask._msufPreviewRoundedAnchor = anchor
        mask._msufPreviewRoundedTexture = maskTexture
        mask:ClearAllPoints()
        mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(anchor)
    end
    H.ApplyRoundedMediaSlice(mask, mock._msufPreviewRoundedMediaStrength)
    return mask
end
function H.SetMask(mock, tex, mask, maskedStoreKey)
    if not (mock and tex and tex.AddMaskTexture) then return end
    maskedStoreKey = maskedStoreKey or "_msufPreviewRoundedMasked"
    mock[maskedStoreKey] = mock[maskedStoreKey] or {}
    local store = mock[maskedStoreKey]
    local old = store[tex]
    if old == mask then return end
    if old and tex.RemoveMaskTexture then tex:RemoveMaskTexture(old) end
    store[tex] = nil
    if mask then
        tex:AddMaskTexture(mask)
        store[tex] = mask
    end
end
function H.ClearMasks(mock, maskedStoreKey)
    local store = mock and mock[maskedStoreKey or "_msufPreviewRoundedMasked"]
    if store then
        for tex, mask in pairs(store) do
            if tex and tex.RemoveMaskTexture and mask then tex:RemoveMaskTexture(mask) end
        end
    end
    if mock then mock[maskedStoreKey or "_msufPreviewRoundedMasked"] = nil end
end
local EDGE_LINE_KEYS = { "top", "bottom", "left", "right" }
function H.SetEdgeLinesShown(frame, shown, opts)
    local lines = frame and frame[(opts and opts.linesKey) or "_lines"]
    if type(lines) ~= "table" then return end
    local keys = (opts and opts.keys) or EDGE_LINE_KEYS
    for i = 1, #keys do
        local line = lines[keys[i]]
        if line then
            if shown then line:Show() else line:Hide() end
        end
    end
end
function H.LayoutEdgeLines(frame, edge, opts)
    if not (frame and frame.CreateTexture) then return false end
    opts = opts or {}
    edge = H.ClampEdgeSize(edge, 1, opts.maxEdgeSize or 30)
    if edge <= 0 then H.SetEdgeLinesShown(frame, false, opts); return false end
    local linesKey = opts.linesKey or "_lines"
    local keys = opts.keys or EDGE_LINE_KEYS
    frame[linesKey] = frame[linesKey] or {}
    local lines = frame[linesKey]
    local texture = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local snap = opts.snapOff or H.SnapOff
    for i = 1, #keys do
        local key = keys[i]
        if not lines[key] then
            lines[key] = frame:CreateTexture(nil, opts.layer or "OVERLAY")
            snap(lines[key])
        end
        lines[key]:SetTexture(texture)
    end
    local r, g, b, a = 0, 0, 0, 1
    if type(opts.color) == "function" then r, g, b, a = opts.color(frame) end
    for i = 1, #keys do
        local key, line = keys[i], lines[keys[i]]
        local spec = EDGE_ANCHORS[key]
        line:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
        line:ClearAllPoints()
        line:SetPoint(spec[1], frame, spec[1], 0, 0)
        line:SetPoint(spec[2], frame, spec[2], 0, 0)
        line[spec[3]](line, edge)
    end
    H.SetEdgeLinesShown(frame, true, opts)
    return true
end
function H.ClampEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end
function H.EnsureRoundedVisuals(mock, opts)
    if not (mock and mock.CreateTexture) then return false end
    opts = opts or {}
    local bgKey = opts.bgKey or "roundedBg"
    local edgeKey = opts.edgeKey or "roundedEdge"
    local snap = opts.snapOff or H.SnapOff
    if not mock[bgKey] then
        mock[bgKey] = mock:CreateTexture(nil, opts.bgLayer or "BACKGROUND", nil, opts.bgSubLevel)
        mock[bgKey]:SetTexture(opts.whiteTexture or "Interface\\Buttons\\WHITE8X8")
        snap(mock[bgKey])
    end
    if not mock[edgeKey] then
        mock[edgeKey] = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
        snap(mock[edgeKey])
    end
    if mock[edgeKey]._msufPreviewRoundedEdgeTexture ~= opts.edgeTexture then
        mock[edgeKey]._msufPreviewRoundedEdgeTexture = opts.edgeTexture
        mock[edgeKey]:SetTexture(opts.edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    H.ApplyRoundedMediaSlice(mock[edgeKey], opts.mediaStrength)
    return true
end
function H.ForEachRoundedEdge(mock, opts, fn)
    if not (mock and type(fn) == "function") then return end
    opts = opts or {}
    local edge = mock[opts.edgeKey or "roundedEdge"]
    if edge then fn(edge, 1) end
    local stack = mock[opts.stackKey or "_msufPreviewRoundedEdgeStack"]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        if stack[i] then fn(stack[i], i) end
    end
end
function H.SetRoundedEdgeStackShown(mock, shown, opts)
    opts = opts or {}
    local count = shown and H.ClampEdgeSize(mock and mock[opts.countKey or "_msufPreviewRoundedEdgeCount"], 1, opts.maxEdgeSize or 8) or 0
    H.ForEachRoundedEdge(mock, opts, function(edge, i)
        if edge.SetShown then
            edge:SetShown(i <= count)
        elseif i <= count then
            edge:Show()
        else
            edge:Hide()
        end
    end)
end
function H.SetRoundedEdgeStackAlpha(mock, alpha, opts)
    local clamp = opts and opts.clamp01
    alpha = type(clamp) == "function" and clamp(alpha, 1) or math.max(0, math.min(1, tonumber(alpha) or 1))
    H.ForEachRoundedEdge(mock, opts, function(edge)
        if edge and edge.SetAlpha then edge:SetAlpha(alpha) end
    end)
end
function H.ApplyRoundedEdgeStack(mock, edgeSize, opts)
    if not mock then return false end
    opts = opts or {}
    local count = H.ClampEdgeSize(edgeSize, 0, opts.maxEdgeSize or 8)
    local stackKey = opts.stackKey or "_msufPreviewRoundedEdgeStack"
    local countKey = opts.countKey or "_msufPreviewRoundedEdgeCount"
    local edgeKey = opts.edgeKey or "roundedEdge"
    mock[countKey] = count
    if count <= 0 then
        H.SetRoundedEdgeStackShown(mock, false, opts)
        return false
    end
    mock[stackKey] = mock[stackKey] or {}
    mock[stackKey][1] = mock[edgeKey]
    local snap = opts.snapOff or H.SnapOff
    local edgeTexture = opts.edgeTexture
    local anchor = type(opts.anchor) == "function" and opts.anchor(mock) or opts.anchor or mock
    local r, g, b, a
    if type(opts.baseEdgeColor) == "function" then
        r, g, b, a = opts.baseEdgeColor(mock)
    else
        r, g, b, a = H.BaseEdgeColor()
    end
    for i = 1, count do
        local edge = (i == 1) and mock[edgeKey] or mock[stackKey][i]
        if not edge then
            edge = mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel)
            snap(edge)
            mock[stackKey][i] = edge
        end
        if edge._msufPreviewRoundedEdgeTexture ~= edgeTexture then
            edge._msufPreviewRoundedEdgeTexture = edgeTexture
            edge:SetTexture(edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        H.ApplyRoundedMediaSlice(edge, opts.mediaStrength)
        if edge._msufPreviewRoundedAnchor ~= anchor or edge._msufPreviewRoundedPad ~= i then
            edge._msufPreviewRoundedAnchor = anchor
            edge._msufPreviewRoundedPad = i
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -i, i)
            edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", i, -i)
        end
        if edge._msufPreviewRoundedR ~= r or edge._msufPreviewRoundedG ~= g
            or edge._msufPreviewRoundedB ~= b or edge._msufPreviewRoundedA ~= a then
            edge._msufPreviewRoundedR = r
            edge._msufPreviewRoundedG = g
            edge._msufPreviewRoundedB = b
            edge._msufPreviewRoundedA = a
            edge:SetVertexColor(r, g, b, a)
        end
        edge:Show()
    end
    H.SetRoundedEdgeStackShown(mock, true, opts)
    return true
end
function H.BaseEdgeColor()
    local fn = _G.MSUF_GetBarOutlineColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, 1 end
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0,
               1
    end
    return 0, 0, 0, 1
end

-- Shared ClassPower preview contract. BAR mode only needs its two boundary
-- segments clipped; every interior separator remains square and every non-BAR
-- shape bypasses this helper entirely.
local function BindClassPowerPreviewBoundary(frame, tex, key, maskStoreKey, maskedKey, maskPath, snap, seen)
    if not tex then return end
    local mask = H.EnsureRoundedMask(frame, key, frame, tex, maskStoreKey, maskPath, snap)
    if not mask then return end
    H.SetMask(frame, tex, mask, maskedKey)
    seen[tex] = true
end

function H.ApplyRoundedClassPowerSurface(frame, enabled, fills, backgrounds, count, outline, opts, bgR, bgG, bgB, bgA)
    if not frame then return false end
    opts = opts or {}
    local maskedKey = opts.maskedKey or "_msufCPPreviewRoundedMasked"
    local maskStoreKey = opts.maskStoreKey or "_msufCPPreviewRoundedMasks"
    local stateKey = opts.stateKey or "_msufCPPreviewRoundedState"
    local state = frame[stateKey]
    local roundedBg = frame[opts.bgKey or "_msufCPPreviewRoundedBg"]
    local canApply = enabled and H.ResolveRoundedMedia and H.EnsureRoundedMask and H.SetMask
        and H.EnsureRoundedVisuals and H.ApplyRoundedEdgeStack

    count = math.floor((tonumber(count) or 0) + 0.5)
    if count < 1 then canApply = false end
    if not canApply then
        if state and state.active == false then return false end
        H.ClearMasks(frame, maskedKey)
        H.SetRoundedEdgeStackShown(frame, false, opts)
        if roundedBg then roundedBg:Hide() end
        if not state then
            state = {}
            frame[stateKey] = state
        end
        state.active = false
        return false
    end

    local maskPath, edgePath, strength = H.ResolveRoundedMedia()
    outline = H.ClampEdgeSize(outline, 0, opts.maxEdgeSize or 8)
    local fillFirst = type(fills) == "table" and fills[1] or nil
    local fillLast = type(fills) == "table" and count > 1 and fills[count] or nil
    local bgFirst = type(backgrounds) == "table" and backgrounds[1] or nil
    local bgLast = type(backgrounds) == "table" and count > 1 and backgrounds[count] or nil
    local edgeAnchor = type(opts.anchor) == "function" and opts.anchor(frame) or opts.anchor or frame
    local edgeR, edgeG, edgeB, edgeA
    if type(opts.baseEdgeColor) == "function" then
        edgeR, edgeG, edgeB, edgeA = opts.baseEdgeColor(frame)
    else
        edgeR, edgeG, edgeB, edgeA = H.BaseEdgeColor()
    end
    if state and state.active == true and state.count == count and state.outline == outline
        and state.maskPath == maskPath and state.edgePath == edgePath and state.anchor == edgeAnchor
        and state.fillFirst == fillFirst and state.fillLast == fillLast
        and state.bgFirst == bgFirst and state.bgLast == bgLast and state.roundedBg == roundedBg
        and state.bgR == bgR and state.bgG == bgG and state.bgB == bgB and state.bgA == bgA
        and state.edgeR == edgeR and state.edgeG == edgeG
        and state.edgeB == edgeB and state.edgeA == edgeA then
        return true
    end

    if not state then
        state = {}
        frame[stateKey] = state
    end
    local seen = state.seen
    if not seen then
        seen = {}
        state.seen = seen
    else
        for tex in pairs(seen) do seen[tex] = nil end
    end

    frame._msufPreviewRoundedMediaStrength = strength
    opts.edgeTexture = edgePath
    opts.mediaStrength = strength
    if not H.EnsureRoundedVisuals(frame, opts) then return false end

    roundedBg = frame[opts.bgKey or "_msufCPPreviewRoundedBg"]
    local snap = opts.snapOff or H.SnapOff
    BindClassPowerPreviewBoundary(frame, fillFirst, "fillFirst", maskStoreKey, maskedKey, maskPath, snap, seen)
    BindClassPowerPreviewBoundary(frame, fillLast, "fillLast", maskStoreKey, maskedKey, maskPath, snap, seen)
    BindClassPowerPreviewBoundary(frame, bgFirst, "backgroundFirst", maskStoreKey, maskedKey, maskPath, snap, seen)
    BindClassPowerPreviewBoundary(frame, bgLast, "backgroundLast", maskStoreKey, maskedKey, maskPath, snap, seen)
    if bgR ~= nil and roundedBg then
        if roundedBg._msufCPRoundedAnchor ~= frame then
            roundedBg:ClearAllPoints()
            roundedBg:SetAllPoints(frame)
            roundedBg._msufCPRoundedAnchor = frame
        end
        roundedBg:SetVertexColor(bgR or 0, bgG or 0, bgB or 0, bgA or 0)
        roundedBg:Show()
        BindClassPowerPreviewBoundary(frame, roundedBg, "sharedBackground",
            maskStoreKey, maskedKey, maskPath, snap, seen)
    elseif roundedBg then
        roundedBg:Hide()
    end

    local masked = frame[maskedKey]
    if masked then
        for tex, mask in pairs(masked) do
            if not seen[tex] then
                if tex and tex.RemoveMaskTexture and mask then tex:RemoveMaskTexture(mask) end
                masked[tex] = nil
            end
        end
        if not next(masked) then frame[maskedKey] = nil end
    end

    if outline > 0 then
        H.ApplyRoundedEdgeStack(frame, outline, opts)
    else
        H.SetRoundedEdgeStackShown(frame, false, opts)
    end
    state.active, state.count, state.outline = true, count, outline
    state.maskPath, state.edgePath, state.anchor = maskPath, edgePath, edgeAnchor
    state.fillFirst, state.fillLast = fillFirst, fillLast
    state.bgFirst, state.bgLast, state.roundedBg = bgFirst, bgLast, roundedBg
    state.bgR, state.bgG, state.bgB, state.bgA = bgR, bgG, bgB, bgA
    state.edgeR, state.edgeG, state.edgeB, state.edgeA = edgeR, edgeG, edgeB, edgeA
    return true
end
