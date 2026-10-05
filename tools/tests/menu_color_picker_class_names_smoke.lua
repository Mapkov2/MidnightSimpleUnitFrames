-- menu_color_picker_class_names_smoke.lua <repoRoot>
--
-- The class colour swatches titled their tooltips with the raw class token
-- ("WARRIOR") on every client language (bh2 R-C7-08), in both pickers a
-- colour button opens: the menu's own picker (the normal path) and the
-- swatches beside Blizzard's colour picker (the fallback without it). Both
-- now use the client's LOCALIZED_CLASS_NAMES_MALE (Blizzard_FrameXMLBase
-- Constants.lua on every branch); a class the client does not have keeps
-- its earlier title. The stored colours stay keyed by the class token.
--
-- Boots the real Classic Era core and Options graph on a German client.
-- Plain Lua 5.1, repo root.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_color_picker_class_names_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Vanilla", { locale = "deDE" })
-- Edit box surface the picker's side panel uses and the shared stubs leave out.
local widgetMethods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetNumeric", "ClearFocus",
    "SetCursorPosition", "HighlightText", "EnableKeyboard" }) do
    widgetMethods[name] = widgetMethods[name] or function(self, ...) self["fixture" .. name] = { ... } end
end
widgetMethods.HasFocus = widgetMethods.HasFocus or function() return false end
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, M = world.env, world.core.MSUF2
local W = Check(M and M.Widgets, "Menu2 widgets missing")
world.widgets:ClearTimers()

-- The client's class names (Classic Era has no Death Knight, Monk, Demon
-- Hunter or Evoker).
e.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "J\195\164ger", ROGUE = "Schurke",
    PRIEST = "Priester", SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", DRUID = "Druide" }

-- Blizzard's shared picker, reduced to what the fallback opens.
local picker = e.CreateFrame("Frame", "ColorPickerFrame", e.UIParent)
picker.rgb = { 1, 1, 1 }
function picker:SetColorRGB(r, g, b) self.rgb = { r, g, b } end
function picker:GetColorRGB() return self.rgb[1], self.rgb[2], self.rgb[3] end
function picker:SetupColorPickerAndShow(info)
    self.swatchFunc, self.cancelFunc = info.swatchFunc, info.cancelFunc
    self:SetColorRGB(info.r, info.g, info.b)
    self:Show()
end
e.ColorPickerFrame = picker

local titles = {}
local addTooltip = M.AddTooltip
M.AddTooltip = function(widget, title, ...)
    if widget and widget._msuf2Token then titles[widget._msuf2Token] = title end
    return addTooltip(widget, title, ...)
end
local contextPicker = W.OpenColorContextPicker
W.OpenColorContextPicker = nil
local button = Check(W.Color(e.CreateFrame("Frame", nil, e.UIParent), "Smoke color"), "W.Color built no button")
button:GetScript("OnClick")(button)
W.OpenColorContextPicker, M.AddTooltip = contextPicker, addTooltip

Check(titles.WARRIOR == "Krieger" and titles.ROGUE == "Schurke",
    "the class swatch tooltips show " .. tostring(titles.WARRIOR) .. " instead of the client's class name")
Check(titles.DEATHKNIGHT == "Death Knight" and titles.EVOKER == "EVOKER",
    "a class the client does not have lost its fallback name: " .. tostring(titles.DEATHKNIGHT))

-- The normal path: the menu's own colour picker, opened by a real colour
-- button of the Colors page (menu_core_world.lua gives the picker the
-- widget surface it builds with).
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, "Vanilla", { locale = "deDE", page = "opt_colors" })
local methods = mw.world.widgets.Methods
function methods:SetColorWheelTexture(value) self.wheelTexture = value end
function methods:SetColorValueTexture(value) self.valueTexture = value end
function methods:SetColorWheelThumbTexture(value) self.wheelThumb = self:CreateTexture(); self.wheelThumb:SetTexture(value) end
function methods:SetColorValueThumbTexture(value) self.valueThumb = self:CreateTexture(); self.valueThumb:SetTexture(value) end
function methods:GetColorWheelThumbTexture() return self.wheelThumb end
function methods:GetColorValueThumbTexture() return self.valueThumb end
function methods:SetColorRGB(r, g, b)
    self.rgb = { r, g, b }
    local fn = self:GetScript("OnColorSelect")
    if fn then fn(self, r, g, b) end
end
function methods:GetColorRGB() return unpack(self.rgb or { 1, 1, 1 }) end
mw.env.LOCALIZED_CLASS_NAMES_MALE = e.LOCALIZED_CLASS_NAMES_MALE
local MM = mw.M
local normal, menuAddTooltip = {}, MM.AddTooltip
MM.AddTooltip = function(widget, title, ...)
    if widget and widget.token then normal[widget.token] = title end
    return menuAddTooltip(widget, title, ...)
end
local owner
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2ColorLabel == "Unified bar color" then owner = frame; break end
end
Check(owner, "the Colors page built no Unified bar color button")
local openMenuPicker, opened = MM.Widgets.OpenColorContextPicker, nil
MM.Widgets.OpenColorContextPicker = function(...)
    opened = openMenuPicker(...)
    return opened
end
owner:GetScript("OnClick")(owner)
MM.Widgets.OpenColorContextPicker, MM.AddTooltip = openMenuPicker, menuAddTooltip
Check(opened and opened:IsShown(), "the menu colour picker did not open")
Check(normal.WARRIOR == "Krieger" and normal.HUNTER == "J\195\164ger" and normal.DRUID == "Druide",
    "the menu colour picker's class swatches show " .. tostring(normal.WARRIOR) .. " instead of the client's class name")
Check(normal.EVOKER == "EVOKER", "a class the client does not have lost its title: " .. tostring(normal.EVOKER))
opened:Finish(true)

print("menu_color_picker_class_names_smoke: ok (class swatch tooltips use the client's class names in both pickers)")
