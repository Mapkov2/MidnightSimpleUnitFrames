-- menu_color_picker_class_names_smoke.lua <repoRoot>
--
-- The class colour swatches beside Blizzard's colour picker (the fallback
-- the colour buttons use without the menu's own picker) titled their
-- tooltips with the raw class token ("WARRIOR") on every client language
-- (bh2 R-C7-08). They now use the client's LOCALIZED_CLASS_NAMES_MALE
-- (Blizzard_FrameXMLBase Constants.lua on every branch); a class the client
-- does not have keeps the English name.
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

print("menu_color_picker_class_names_smoke: ok (class swatch tooltips use the client's class names)")
