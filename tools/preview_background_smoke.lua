-- Executable smoke for the shared Menu2 preview background selector.
-- Verifies the Silvermoon default, texture/custom switching, studio fallback,
-- and one shared picker used by Unit, Group, and Class Resources preview canvases.

_G = _G or _ENV

local function Texture(layer, subLevel)
    local texture = { shown = true, layer = layer or "BACKGROUND", subLevel = subLevel or 0 }
    function texture:SetAllPoints() self.allPoints = true end
    function texture:ClearAllPoints() self.point = nil end
    function texture:SetPoint(...) self.point = { ... } end
    function texture:SetSize(width, height) self.width, self.height = width, height end
    function texture:SetTexture(value) self.texture = value end
    function texture:GetTexture() return self.texture end
    function texture:SetVertexColor(...) self.vertex = { ... } end
    function texture:GetVertexColor()
        local color = self.vertex or { 1, 1, 1, 1 }
        return color[1], color[2], color[3], color[4]
    end
    function texture:SetTexCoord(...) self.texCoord = { ... } end
    function texture:GetTexCoord()
        local coords = self.texCoord or { 0, 1, 0, 1 }
        return unpack(coords)
    end
    function texture:SetBlendMode(value) self.blendMode = value end
    function texture:GetBlendMode() return self.blendMode end
    function texture:GetDrawLayer() return self.layer, self.subLevel end
    function texture:GetObjectType() return "Texture" end
    function texture:SetColorTexture(...) self.color = { ... }; self.paint = "solid" end
    function texture:SetGradientAlpha(...) self.gradient = { ... }; self.paint = "gradient" end
    function texture:SetAlpha(value) self.alpha = value end
    function texture:GetAlpha() return self.alpha == nil and 1 or self.alpha end
    function texture:GetWidth() return self.width or (self.allPoints and self.owner and self.owner:GetWidth()) or 0 end
    function texture:GetHeight() return self.height or (self.allPoints and self.owner and self.owner:GetHeight()) or 0 end
    function texture:GetEffectiveScale() return self.scale or 1 end
    function texture:GetLeft() return self.left end
    function texture:GetRight() return self.right or (self.left and self.width and self.left + self.width) end
    function texture:GetBottom() return self.bottom end
    function texture:GetTop() return self.top or (self.bottom and self.height and self.bottom + self.height) end
    function texture:GetScaledRect()
        local left, bottom = self:GetLeft(), self:GetBottom()
        local width, height = self:GetWidth(), self:GetHeight()
        if not (left and bottom and width and height) then return nil end
        local scale = self:GetEffectiveScale()
        return left * scale, bottom * scale, width * scale, height * scale
    end
    function texture:IsShown() return self.shown ~= false end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end

local function FontString()
    local font = {}
    function font:SetPoint(...) self.point = { ... } end
    function font:SetText(value) self.text = value end
    function font:SetTextColor(...) self.color = { ... } end
    return font
end

local function Frame(parent)
    local frame = { parent = parent, scripts = {}, hooks = {}, level = 1 }
    function frame:CreateTexture(_, layer, _, subLevel)
        local texture = Texture(layer, subLevel)
        texture.owner = self
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function frame:CreateFontString() return FontString() end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width or 0 end
    function frame:GetHeight() return self.height or 0 end
    function frame:GetEffectiveScale() return self.scale or 1 end
    function frame:GetLeft() return self.left end
    function frame:GetRight() return self.right or (self.left and self.width and self.left + self.width) end
    function frame:GetBottom() return self.bottom end
    function frame:GetTop() return self.top or (self.bottom and self.height and self.bottom + self.height) end
    function frame:GetScaledRect()
        local left, bottom = self:GetLeft(), self:GetBottom()
        local width, height = self:GetWidth(), self:GetHeight()
        if not (left and bottom and width and height) then return nil end
        local scale = self:GetEffectiveScale()
        return left * scale, bottom * scale, width * scale, height * scale
    end
    function frame:IsVisible() return self.visible ~= false end
    function frame:IsShown() return self.visible ~= false end
    function frame:Show()
        self.visible = true
        if self.hooks.OnShow then self.hooks.OnShow(self) end
    end
    function frame:Hide()
        self.visible = false
        if self.hooks.OnHide then self.hooks.OnHide(self) end
    end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetBackdrop(value) self.backdrop = value end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:GetBackdropColor()
        local color = self.backdropColor or { 0, 0, 0, 0 }
        return color[1], color[2], color[3], color[4]
    end
    function frame:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha == nil and 1 or self.alpha end
    function frame:GetParent() return self.parent end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:GetFrameLevel() return self.level end
    function frame:SetScript(kind, handler) self.scripts[kind] = handler end
    function frame:HookScript(kind, handler)
        local previous = self.hooks[kind]
        if previous then
            self.hooks[kind] = function(...)
                previous(...)
                handler(...)
            end
        else
            self.hooks[kind] = handler
        end
    end
    return frame
end

_G.CreateFrame = function(_, _, parent) return Frame(parent) end
_G.C_Timer = {}

local selected
local dropdown
local picker
local M
local menuHost = Frame()
local menuScroll = Frame(menuHost)
M = {
    frame = Frame(),
    Fallbacks = {},
    SetMenuStateValue = function(field, value)
        M[field] = value
        if field == "previewBackground" then selected = value end
    end,
    Widgets = {
        OpenDropdown = function(owner, values, current, onSelect)
            dropdown = { owner = owner, values = values, current = current, onSelect = onSelect }
            return true
        end,
        OpenColorContextPicker = function(title, owners, note, initialOwner, onFinish)
            picker = { title = title, owners = owners, note = note, owner = initialOwner, onFinish = onFinish }
            return picker
        end,
    },
}
M.frame.host = menuHost
M.scrollFrame = menuScroll
M.frame.left, M.frame.bottom = 0, 0
M.frame:SetSize(1000, 800)
menuHost.left, menuHost.bottom = 100, 50
menuHost:SetSize(850, 700)
menuScroll.left, menuScroll.bottom = 100, 50
menuScroll:SetSize(850, 700)
M.frame:SetBackdropColor(0.01, 0.02, 0.04, 1)
menuHost:SetBackdropColor(0.02, 0.04, 0.08, 1)
M.frame._msuf2MaterialGradient = Texture()
menuHost._msuf2MaterialGradient = Texture()
local function ConfigureMaterialGradient(texture, left, bottom, width, height)
    texture.texture = "Interface\\Buttons\\WHITE8X8"
    texture.left, texture.bottom = left, bottom
    texture.width, texture.height = width, height
    texture._msuf2TextureMode = "gradient"
    texture._msuf2GradientOrientation = "VERTICAL"
    texture._msuf2GradientFR, texture._msuf2GradientFG = 0.10, 0.14
    texture._msuf2GradientFB, texture._msuf2GradientFA = 0.24, 0.80
    texture._msuf2GradientTR, texture._msuf2GradientTG = 0.02, 0.04
    texture._msuf2GradientTB, texture._msuf2GradientTA = 0.08, 0.45
end
ConfigureMaterialGradient(M.frame._msuf2MaterialGradient, 0, 0, 1000, 800)
ConfigureMaterialGradient(menuHost._msuf2MaterialGradient, 100, 50, 850, 700)
M.frame._msuf2PanelAsset = { C = Texture() }
menuHost._msuf2PanelAsset = { C = Texture() }
menuHost._msuf2AtmosphereTextures = { Texture(), Texture() }
M.frame._msuf2PanelAsset.C.texture = "panel-shell"
M.frame._msuf2PanelAsset.C.left, M.frame._msuf2PanelAsset.C.bottom = 0, 0
M.frame._msuf2PanelAsset.C.width, M.frame._msuf2PanelAsset.C.height = 1000, 800
menuHost._msuf2PanelAsset.C.texture = "panel-host"
menuHost._msuf2PanelAsset.C.left, menuHost._msuf2PanelAsset.C.bottom = 100, 50
menuHost._msuf2PanelAsset.C.width, menuHost._msuf2PanelAsset.C.height = 850, 700
for i = 1, #menuHost._msuf2AtmosphereTextures do
    local texture = menuHost._msuf2AtmosphereTextures[i]
    texture.texture = "atmosphere-" .. i
    texture.left, texture.bottom = 100, 50
    texture.width, texture.height = 850, 700
end
local MSUF = { MSUF2 = M }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local H = assert(M.PreviewHelpers)
local key = H.GetPreviewBackground()
assert(key == "silvermoon", "silvermoon must be the default")
for _, name in ipairs({ "bright_stone.png", "city_scene.png", "dark_stone.png", "silvermoon.png" }) do
    local asset = assert(io.open("MidnightSimpleUnitFrames_Options/Media/PreviewBackgrounds/" .. name, "rb"),
        "missing preview background asset: " .. name)
    asset:close()
end

local theme = {
    colors = {
        coreShadow = { 0.02, 0.03, 0.05, 1 },
        coreInk = { 0.03, 0.06, 0.10, 1 },
        borderSoft = { 0.10, 0.20, 0.30, 1 },
        panel = { 0.03, 0.06, 0.10, 1 },
    },
    ApplyBackdrop = function(frame, bg, border)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end,
}
local section = Frame(M.frame.host)
local outer = Frame(section)
local canvas = Frame(outer)
canvas.left, canvas.bottom = 250, 250
canvas:SetSize(600, 180)
H.ApplyPreviewChrome(outer, "outer", theme)
H.ApplyPreviewChrome(canvas, "canvas", theme)
assert(canvas._msuf2PreviewCanvasImage and canvas._msuf2PreviewCanvasImage.shown, "default image missing")
assert(canvas._msuf2PreviewCanvasImage.texture:match("silvermoon%.png$"), "wrong default texture")
assert(canvas._msuf2PreviewCanvasImage.texCoord[3] > 0, "wide canvas texture must crop instead of stretch")
assert(canvas.backdropColor[4] == 0, "silvermoon image backdrop must be transparent")
assert(canvas._msuf2PreviewCanvasGradient.color[4] == 0, "silvermoon image must not have a dark overlay")

assert(H.SetPreviewBackground("bright_stone") == true and selected == "bright_stone", "bright selection failed")
assert(canvas._msuf2PreviewCanvasImage.texture:match("bright_stone%.png$"), "bright texture did not hot-swap")

assert(H.SetPreviewBackground("city_scene") == true and selected == "city_scene", "city selection failed")
assert(canvas._msuf2PreviewCanvasImage.texture:match("city_scene%.png$"), "city texture did not hot-swap")
assert(canvas.backdropColor[4] == 0, "city image backdrop must remain transparent")
assert(canvas._msuf2PreviewCanvasGradient.color[4] == 0, "city image must not have a dark overlay")

assert(H.SetPreviewBackground("dark_stone") == true, "dark selection failed")
assert(canvas._msuf2PreviewCanvasImage.texture:match("dark_stone%.png$"), "dark texture did not hot-swap")
assert(H.SetPreviewBackground("unknown") == false, "unknown background must fail closed")

assert(H.SetPreviewBackground("studio") == true, "studio selection failed")
assert(canvas._msuf2PreviewCanvasImage.shown == false, "studio must hide the scene image")
assert(canvas.backdropColor[4] == 0.92, "studio must restore the original canvas backdrop")
assert(canvas._msuf2PreviewCanvasGradient.paint == "gradient", "studio gradient was not restored")

assert(H.SetPreviewBackground("custom") == true, "custom selection failed")
assert(canvas._msuf2PreviewCanvasImage.shown == false, "custom color must hide the scene image")
assert(canvas.backdropColor[1] == 0.08 and canvas.backdropColor[2] == 0.12 and canvas.backdropColor[3] == 0.18,
    "custom default color mismatch")
assert(canvas._msuf2PreviewCanvasGradient.color[4] == 0, "custom color must not retain the studio gradient")

local box, zoomBar = Frame(section), Frame()
box.canvas = canvas
local button = assert(H.EnsurePreviewBackgroundButton(box, zoomBar, {}))
assert(box.previewBackgroundButton == button, "shared picker was not attached to the preview")
assert(zoomBar._msuf2PreviewBackgroundButton == button,
    "zoom bar must expose its background selector for paint-surface frame leveling")
assert(button.point[1] == "TOPRIGHT" and button.point[2] == zoomBar and button.point[3] == "BOTTOMRIGHT",
    "picker must stay below the zoom bar and clear animation/role controls")
button.scripts.OnClick(button)
assert(dropdown and #dropdown.values == 6 and dropdown.current == "custom", "picker dropdown mismatch")
assert(dropdown.values[4].value == "silvermoon" and dropdown.values[4].texture,
    "silvermoon must be the fourth choice")
assert(dropdown.values[5].value == "custom" and dropdown.values[5].swatchColor, "custom must be the fifth choice")
assert(dropdown.values[6].value == "studio", "studio must remain available after the custom color")
assert(button._msuf2DropdownPreferredWidth == 260 and button._msuf2DropdownClampFrame,
    "background dropdown must use its compact clamped layout")
dropdown.onSelect("custom")
assert(picker and picker.owner == picker.owners[1], "custom selection must open the MSUF color picker")
picker.owner:SetRGB(0.31, 0.42, 0.53)
picker.owner._msuf2OnColorChanged(0.31, 0.42, 0.53)
picker.onFinish(false)
assert(canvas.backdropColor[1] == 0.31 and canvas.backdropColor[2] == 0.42 and canvas.backdropColor[3] == 0.53,
    "custom color must update the preview live")
dropdown.onSelect("bright_stone")
assert(M.previewBackground == "bright_stone", "picker did not persist selection")
assert(canvas._msuf2PreviewCanvasImage.shown == true, "picker did not refresh registered canvases")
assert(canvas.backdropColor[4] == 0, "switching back to an image must remove the studio backdrop")
assert(M.frame.backdropColor[4] == 1 and menuHost.backdropColor[4] == 1,
    "background switching must leave the window and host backdrops untouched")
assert(menuHost._msuf2AtmosphereTextures[1]:GetAlpha() == 1
        and menuHost._msuf2AtmosphereTextures[2]:GetAlpha() == 1,
    "background switching must leave the host atmosphere untouched")

local stateSource = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_State.lua", "rb")):read("*a")
assert(stateSource:find('previewBackground%s*=%s*"silvermoon"'), "persistent silvermoon default missing")
assert(stateSource:find("previewBackgroundCustomR%s*=%s*0%.08"), "persistent custom color missing")
print("PREVIEW BACKGROUND SMOKE PASS - silvermoon/custom/studio/hot-swap/persistence")
