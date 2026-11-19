-- menu_font_flags_colorfield_smoke.lua <root> <client>
-- Multi-value results must survive guarded calls. `a and obj:Get()` keeps only
-- the first result, which dropped font outline flags, the template font size
-- and the color picker's rounded border layer.
local root, client = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, client):Boot()
assert(world:FirstFailure() == nil, "MSUF did not boot")
local UI = assert(world.core.UI, "MSUF.UI missing")

-- A FontString with real GetFont/SetFont semantics (three results).
local function FontString(path, size, flags)
    local fs = { path = path, size = size, flags = flags }
    function fs:GetFont() return self.path, self.size, self.flags end
    function fs:SetFont(p, s, f) self.path, self.size, self.flags = p, s, f return true end
    function fs:SetText() end
    function fs:SetTextColor() end
    function fs:SetShadowColor() end
    function fs:SetShadowOffset() end
    return fs
end

local fs = FontString("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
UI.ApplyFontSize(fs, 14)
assert(fs.flags == "OUTLINE", "ApplyFontSize dropped the current outline: " .. tostring(fs.flags))
fs = FontString("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
UI.ApplyFontRole(fs, "body")
assert(fs.flags == "THICKOUTLINE", "ApplyFontRole dropped the current outline: " .. tostring(fs.flags))

-- Without a Menu2 theme, UI.Font keeps the size its template brings.
local created
local parent = world.env.CreateFrame("Frame", nil, world.env.UIParent)
parent.CreateFontString = function()
    created = FontString("Fonts\\FRIZQT__.TTF", 18, "")
    return created
end
local theme = UI.GetMenu2Theme
UI.GetMenu2Theme = function() return nil end
UI.Font(parent, "GameFontNormalLarge", "x")
UI.GetMenu2Theme = theme
assert(created.size == UI.NormalizeFontSize(18), "UI.Font replaced the template size 18 with " .. tostring(created.size))

-- The color picker field uses the theme's rounded layers when they exist.
local M = world.core.MSUF2
if M and M.Theme and M.Theme.CreateSuperellipseLayers then
    local path = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ContextColorPicker.lua"
    local source = World.Read(path)
    local exposed
    source, exposed = source:gsub("\nlocal function RefreshSwatchVisual",
        "\nMSUF.MSUF2._SmokeColorField = ColorField\nlocal function RefreshSwatchVisual", 1)
    assert(exposed == 1, "ColorField anchor moved; update this smoke")
    local ok, err = world:LoadFile(path, "MidnightSimpleUnitFrames_Options", world.core, source)
    assert(ok, err)
    local ColorField = assert(M._SmokeColorField, "ColorField not exposed")
    M._SmokeColorField = nil
    local field = ColorField(world.env.CreateFrame("Frame", nil, world.env.UIParent), 144, 22)
    assert(field.fill and field.fill == field._msuf2PickerFieldFill, "color field painted a square fallback fill")
    assert(field.edge and field.edge == field._msuf2PickerFieldBorder, "color field painted a square fallback border")
end

print("menu font flags and color field (" .. client .. "): ok")
