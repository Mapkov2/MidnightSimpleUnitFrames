local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Backgrounds.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local CP = M.ClassPowerPreview
local FlatBackdrop = H._Shared.FlatBackdrop

local PREVIEW_BACKGROUND_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\PreviewBackgrounds\\"
-- Onboarding tour screenshots. They live beside the preview backgrounds in the
-- Options companion and deliberately stay out of `T.media`: theme media must
-- resolve against the core addon (options_lod_namespace_media_smoke). Every
-- entry is authored 2:1 so a tour card can size it from its width alone.
local TOUR_PREVIEW_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\Tour\\"
H.TourPreviews = {
    rounded_frames = { texture = TOUR_PREVIEW_MEDIA .. "rounded_frames.png", aspect = 2 },
}

local PREVIEW_BACKGROUND_DEFAULT = MSUF.Client.IsRetail == true and "silvermoon" or "studio"
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
-- Every scene also ships as BLP, the client's own texture format. The WoW
-- Forever beta client leaves the PNG scenes black, so it starts from the BLP
-- files. Every other client keeps the PNG and swaps to the BLP only when
-- SetTexture reports that the PNG could not be loaded; that is checked once,
-- on the first use, so the dropdown thumbnails follow the same choice.
local PREVIEW_BACKGROUND_NATIVE_FIRST = MSUF.Client.IsForever == true
for i = 1, #PREVIEW_BACKGROUND_SPECS do
    local spec = PREVIEW_BACKGROUND_SPECS[i]
    if spec.texture then
        local native = spec.texture:gsub("%.png$", ".blp")
        if PREVIEW_BACKGROUND_NATIVE_FIRST then
            spec.texture, spec.fallbackTexture = native, spec.texture
        else
            spec.fallbackTexture = native
        end
    end
end
local previewBackgroundTexturesResolved = false
local function ResolvePreviewBackgroundTextures(region)
    if previewBackgroundTexturesResolved or not (region and region.SetTexture) then return end
    previewBackgroundTexturesResolved = true
    for i = 1, #PREVIEW_BACKGROUND_SPECS do
        local spec = PREVIEW_BACKGROUND_SPECS[i]
        if spec.texture and spec.fallbackTexture and region:SetTexture(spec.texture) == false then
            spec.texture, spec.fallbackTexture = spec.fallbackTexture, nil
        end
    end
end
local PREVIEW_BACKGROUND_CANVASES = setmetatable({}, { __mode = "k" })
local PREVIEW_BACKGROUND_BUTTONS = setmetatable({}, { __mode = "k" })
local function PreviewBackgroundText(text)
    local tr = M.TranslateText
    return tr(text)
end
local function PreviewBackgroundSpec()
    local key = tostring(M.previewBackground or PREVIEW_BACKGROUND_DEFAULT)
    return PREVIEW_BACKGROUND_BY_KEY[key] or PREVIEW_BACKGROUND_BY_KEY[PREVIEW_BACKGROUND_DEFAULT]
end
local ClampPreviewColor = MSUF.UF.Clamp01
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
    local preview = button._msuf2PreviewBackgroundTexture
    ResolvePreviewBackgroundTextures(preview)
    local spec = PreviewBackgroundSpec()
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
        image = PixelLayoutRegion(frame:CreateTexture(nil, "BACKGROUND", nil, -8))
        image:SetAllPoints(frame)
        frame._msuf2PreviewCanvasImage = image
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function(self) CropPreviewBackground(self) end)
        end
    end
    local gradient = frame._msuf2PreviewCanvasGradient
    ResolvePreviewBackgroundTextures(image)
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
    M.SetMenuStateValue("previewBackground", spec.key)
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
    local state = M.EnsurePersistentMenuState() or nil
    if type(state) == "table" then
        state.previewBackgroundCustomR = M.previewBackgroundCustomR
        state.previewBackgroundCustomG = M.previewBackgroundCustomG
        state.previewBackgroundCustomB = M.previewBackgroundCustomB
        return
    end
    local persist = M.SetMenuStateValue
    persist("previewBackgroundCustomR", M.previewBackgroundCustomR)
    persist("previewBackgroundCustomG", M.previewBackgroundCustomG)
    persist("previewBackgroundCustomB", M.previewBackgroundCustomB)
end
function H.OpenPreviewBackgroundColorPicker()
    local widgets = M.Widgets
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
    local button = PixelLayoutRegion(CreateFrame("Button", nil, zoomBar, "BackdropTemplate"))
    button:SetSize(46, 20)
    zoomBar._msuf2PreviewBackgroundButton = button
    button._msuf2DropdownPreferredWidth = 260
    button._msuf2DropdownClampFrame = M.frame or UIParent
    -- Keep the selector on its own row: Unit, Group, and Class Resources all
    -- place animation/role controls immediately to the left of the zoom bar.
    button:SetPoint("TOPRIGHT", zoomBar, "BOTTOMRIGHT", 0, -4)
    if button.SetBackdrop then
        FlatBackdrop(button, { 0.010, 0.018, 0.030, 0.96 }, { 0.18, 0.28, 0.42, 0.92 }, CP.WHITE8)
    end
    local preview = PixelLayoutRegion(button:CreateTexture(nil, "ARTWORK"))
    preview:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    preview:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -12, 2)
    button._msuf2PreviewBackgroundTexture = preview
    local arrow = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY"))
    arrow:SetPoint("RIGHT", button, "RIGHT", -3, 0)
    arrow:SetSize(8, 8)
    arrow:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_dropdown_chevron_down.tga")
    arrow:SetVertexColor(0.86, 0.92, 1.00, 1)
    button._msuf2PreviewBackgroundArrow = arrow
    button:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.32, 0.66, 0.96, 1) end
        if GameTooltip then
            local spec = self._msuf2PreviewBackgroundSpec or PreviewBackgroundSpec()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(PreviewBackgroundText("Preview background"), 1, 1, 1)
            GameTooltip:AddLine(PreviewBackgroundText(spec.label), 0.62, 0.84, 1.00)
            GameTooltip:AddLine(PreviewBackgroundText(
                "Choose a background to check frame readability on bright and dark game surfaces."), 0.80, 0.86, 1.00, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.18, 0.28, 0.42, 0.92) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        local widgets = M.Widgets
        if widgets.OpenDropdown then
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
