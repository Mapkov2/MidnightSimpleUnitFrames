-- menu_color_picker_fallback_smoke.lua <repoRoot>
--
-- The plain color buttons fall back to Blizzard's shared ColorPickerFrame
-- when the menu's own context picker is unavailable. That path marks the
-- picker with its MSUF owner and hooks the picker's OnHide (review
-- 2026-09-30, F24). The owner must be released once Blizzard's handler is
-- done: a stale owner made the hook commit an MSUF control, and the menu's
-- close hide the picker, when another addon used the picker later. It must
-- not be released inside the hide itself: Classic's Okay and Cancel hide the
-- frame before they call swatchFunc/cancelFunc (upstream/classic_era
-- Interface/AddOns/Blizzard_FrameXML/Classic/ColorPickerFrame.xml), and the
-- cancel needs the owner to restore the old color.
--
-- Boots the real Classic Era core and Options graph. Plain Lua 5.1, repo root.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_color_picker_fallback_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Vanilla")
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
local W = Check(M.Widgets, "Menu2 widgets missing")
world.widgets:ClearTimers() -- Boot work is not this smoke's subject.

-- Blizzard's shared picker, reduced to the Classic Era order of operations:
-- OnColorSelect calls swatchFunc live, Okay/Cancel hide before their callback.
local picker = e.CreateFrame("Frame", "ColorPickerFrame", e.UIParent)
local stubHide = picker.Hide
stubHide(picker)
picker.rgb = { 1, 1, 1 }
function picker:SetColorRGB(r, g, b)
    self.rgb = { r, g, b }
    if self.swatchFunc then self.swatchFunc() end
end
function picker:GetColorRGB() return self.rgb[1], self.rgb[2], self.rgb[3] end
function picker:SetupColorPickerAndShow(info)
    self.swatchFunc, self.cancelFunc = info.swatchFunc, info.cancelFunc
    self.previousValues = { r = info.r, g = info.g, b = info.b }
    self:SetColorRGB(info.r, info.g, info.b)
    self:Show()
end
function picker:Hide()
    local wasShown = self:IsShown()
    stubHide(self)
    local onHide = self:GetScript("OnHide")
    if wasShown and onHide then onHide(self) end
end
function picker:Okay() self:Hide(); self.swatchFunc() end
function picker:Cancel() self:Hide(); if self.cancelFunc then self.cancelFunc(self.previousValues) end end
e.ColorPickerFrame = picker
local contextPicker = W.OpenColorContextPicker
W.OpenColorContextPicker = nil

local section = e.CreateFrame("Frame", nil, e.UIParent)
local button = Check(W.Color(section, "Smoke color"), "W.Color built no button")
local commits = 0
button._msuf2CommitColorInteraction = function() commits = commits + 1 end
button:SetRGB(0.2, 0.4, 0.6)
local function ButtonIs(er, eg, eb)
    local r, g, b = button:GetRGB()
    return math.abs(r - er) < 1e-6 and math.abs(g - eg) < 1e-6 and math.abs(b - eb) < 1e-6
end

-- Another addon opens and closes the shared picker.
local foreign = { swatches = 0, cancels = 0 }
local function ForeignOpen()
    picker:SetupColorPickerAndShow({ r = 0.5, g = 0.5, b = 0.5,
        swatchFunc = function() foreign.swatches = foreign.swatches + 1 end,
        cancelFunc = function() foreign.cancels = foreign.cancels + 1 end })
end
local function CheckForeignUntouched(after)
    local before = commits
    ForeignOpen()
    picker:Okay()
    Check(commits == before, "another addon closing the picker committed the MSUF color after " .. after)
    Check(ButtonIs(0.9, 0.1, 0.1), "another addon's picker recolored the MSUF button after " .. after)
    ForeignOpen()
    Check(W.CloseMenuOwnedColorPicker() == false, "the menu still claims the picker after " .. after)
    Check(picker:IsShown(), "closing the menu hid another addon's picker after " .. after)
    picker:Cancel()
    world.widgets:RunTimers()
end

-- 1. Okay: the color applies and the owner is released afterwards.
button:GetScript("OnClick")(button)
Check(picker:IsShown() and picker._msuf2ColorOwner == button, "the fallback did not open Blizzard's picker for the button")
picker:SetColorRGB(0.9, 0.1, 0.1)
picker:Okay()
Check(ButtonIs(0.9, 0.1, 0.1), "Okay did not apply the picked color")
Check(commits == 1, "the picker's hide did not commit the color change exactly once")
world.widgets:RunTimers()
CheckForeignUntouched("an Okay")
Check(picker._msuf2ColorOwner == nil, "the picker kept its MSUF owner after an Okay")

-- 2. Cancel: the old color comes back although the frame hides first.
button:GetScript("OnClick")(button)
picker:SetColorRGB(0.0, 1.0, 0.0)
Check(ButtonIs(0.0, 1.0, 0.0), "the live color did not reach the button")
picker:Cancel()
Check(ButtonIs(0.9, 0.1, 0.1), "Cancel did not restore the previous color")
world.widgets:RunTimers()
CheckForeignUntouched("a Cancel")
Check(picker._msuf2ColorOwner == nil, "the picker kept its MSUF owner after a Cancel")

-- 3. Reopening in the same frame keeps the new session's owner.
button:GetScript("OnClick")(button)
picker:Okay()
button:GetScript("OnClick")(button)
world.widgets:RunTimers()
Check(picker._msuf2ColorOwner == button and picker:IsShown(), "a reopened picker lost its MSUF owner")
Check(W.CloseMenuOwnedColorPicker() == true and not picker:IsShown(), "closing the menu left its own picker open")
world.widgets:RunTimers()
Check(picker._msuf2ColorOwner == nil, "the menu's close kept the MSUF owner")
W.OpenColorContextPicker = contextPicker

print("menu_color_picker_fallback_smoke: ok (owner kept through Classic Okay/Cancel, released afterwards)")
