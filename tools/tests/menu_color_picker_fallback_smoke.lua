-- menu_color_picker_fallback_smoke.lua <repoRoot> [flavor] [parentColorPickerPath]
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
-- Boots the real core and Options graph of the selected client. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_color_picker_fallback_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, arg[2] or "Vanilla")
-- Optional authentic parent source for the refactor's same-test comparison.
if arg[3] then
    local originalLoad, parentPath = world.LoadFile, arg[3]
    function world:LoadFile(path, addonName, namespace)
        if path:match("/MSUF_Menu2_ColorPicker%.lua$") then path = parentPath end
        return originalLoad(self, path, addonName, namespace)
    end
end
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
local aura = world.core.MSUF_Auras3
local begins, ends, active = 0, 0, nil
function aura.BeginNativeColorInteraction()
    begins = begins + 1
    active = begins
    return active
end
function aura.EndNativeColorInteraction(ticket)
    if ticket and ticket == active then ends = ends + 1; active = nil end
end

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
Check(begins == 1 and ends == 0 and active == 1, "live fallback colour change was not deferred")
picker:Okay()
Check(active == 1, "native colour commit ran before Classic's final swatch callback")
Check(ButtonIs(0.9, 0.1, 0.1), "Okay did not apply the picked color")
Check(commits == 1, "the picker's hide did not commit the color change exactly once")
world.widgets:RunTimers()
Check(ends == 1 and active == nil, "Okay did not commit native visuals once")
CheckForeignUntouched("an Okay")
Check(picker._msuf2ColorOwner == nil, "the picker kept its MSUF owner after an Okay")

-- 2. Cancel: the old color comes back although the frame hides first.
button:GetScript("OnClick")(button)
picker:SetColorRGB(0.0, 1.0, 0.0)
Check(ButtonIs(0.0, 1.0, 0.0), "the live color did not reach the button")
picker:Cancel()
Check(active ~= nil and ends == 1, "Cancel committed before restoring the previous colour")
Check(ButtonIs(0.9, 0.1, 0.1), "Cancel did not restore the previous color")
world.widgets:RunTimers()
Check(ends == 2 and active == nil, "Cancel did not release its native visual transaction")
CheckForeignUntouched("a Cancel")
Check(picker._msuf2ColorOwner == nil, "the picker kept its MSUF owner after a Cancel")

-- 3. Reopening in the same frame keeps the new session's owner.
button:GetScript("OnClick")(button)
picker:Okay()
button:GetScript("OnClick")(button)
world.widgets:RunTimers()
Check(picker._msuf2ColorOwner == button and picker:IsShown(), "a reopened picker lost its MSUF owner")
Check(active == begins, "an old hide callback committed a reopened native visual transaction")
Check(W.CloseMenuOwnedColorPicker() == true and not picker:IsShown(), "closing the menu left its own picker open")
world.widgets:RunTimers()
Check(picker._msuf2ColorOwner == nil, "the menu's close kept the MSUF owner")
-- 4. Precision editor inputs retain geometry, callbacks, saved colours and owner routing.
do
    function widgetMethods:SetFocus() self.fixtureFocused = true end
    function widgetMethods:ClearFocus() self.fixtureFocused = false end
    function widgetMethods:HasFocus() return self.fixtureFocused == true end
    button:SetRGB(0.2, 0.4, 0.6)
    button:GetScript("OnClick")(button)
    local plus
    for _, frame in ipairs(world.widgets.frames) do
        if rawget(frame, "_msuf2RGB") then plus = frame; break end
    end
    Check(plus and plus:IsShown(), "native picker must open the precision editor")
    local fields, hex = plus._msuf2RGB, plus._msuf2Hex
    Check(#fields == 3 and hex and hex:GetWidth() == 118 and hex:GetHeight() == 22, "RGB/HEX fields lost geometry")
    for i = 1, 3 do
        local point, parent, _, x, y = fields[i]:GetPoint()
        Check(fields[i]:GetWidth() == 58 and fields[i]:GetHeight() == 22 and point == "TOPLEFT"
            and parent == plus and x == 52 + (i - 1) * 66 and y == -104, "RGB field anchor changed")
    end
    Check(tonumber(fields[1]:GetText()) == 51 and tonumber(fields[2]:GetText()) == 102
        and tonumber(fields[3]:GetText()) == 153 and hex:GetText() == "#336699", "initial RGB/HEX text is wrong")
    local function Input(field, text, script, user)
        field:SetText(text)
        field:GetScript(script)(field, user)
    end
    Input(fields[1], "300", "OnEnterPressed")
    Check(ButtonIs(1, 0.4, 0.6), "RGB input must clamp the selected component above255")
    Input(fields[2], "-10", "OnEnterPressed")
    Check(ButtonIs(1, 0, 0.6), "RGB input must clamp the selected component below0")
    Input(fields[3], "not a number", "OnEnterPressed")
    Check(ButtonIs(1, 0, 0.6), "invalid RGB input must keep the current component")
    Input(fields[3], "128", "OnTextChanged", false)
    Check(ButtonIs(1, 0, 0.6), "programmatic RGB text must not apply")
    Input(fields[3], "128", "OnTextChanged", true)
    Check(ButtonIs(1, 0, 128 / 255), "user RGB text must apply to its own component")
    Input(hex, "#12ab34", "OnTextChanged", true)
    Check(ButtonIs(18 / 255, 171 / 255, 52 / 255), "complete HEX live input must apply all components")
    Input(hex, "#12", "OnTextChanged", true)
    Check(ButtonIs(18 / 255, 171 / 255, 52 / 255), "incomplete HEX text must not apply")
    hex:GetScript("OnEnterPressed")(hex)
    Check(hex:GetText() == "#12AB34", "invalid HEX Enter must restore the current value")
    hex:SetFocus()
    hex:SetText("draft")
    picker:SetColorRGB(0.5, 0.25, 0.75)
    Check(hex:GetText() == "draft", "refresh must retain a focused edit")
    hex:GetScript("OnEscapePressed")(hex)
    Check(not hex:HasFocus() and hex:GetText() == "#8040BF", "Escape must clear focus and restore current HEX")
    local copy, save
    for _, frame in ipairs(world.widgets.frames) do
        if frame:GetParent() == plus and frame._msuf2SearchText == "Copy" then copy = frame end
        if frame:GetParent() == plus and frame._msuf2SearchText == "Save" then save = frame end
    end
    Check(copy and save and save._msuf2HistoryCheckpoint == true, "Copy and history-aware Save must exist")
    copy:GetScript("OnClick")(copy)
    Check(hex:HasFocus() and hex.fixtureHighlightText, "Copy must focus and highlight HEX")
    hex:ClearFocus()
    local store = M.EnsureDB().menu2ColorPicker
    local savedCount = #store.saved
    save:GetScript("OnClick")(save)
    Check(#store.saved == savedCount + 1 and store.saved[#store.saved] == "#8040BF", "Save must store current picker colour")
    save:GetScript("OnClick")(save)
    Check(#store.saved == savedCount + 1, "Save must deduplicate colours")
    store.saved = {}
    for i = 1, 27 do store.saved[i] = string.format("#%06X", i) end
    save:GetScript("OnClick")(save)
    Check(#store.saved == 27 and store.saved[27] == "#00001B", "Save must retain the27-colour cap")
    plus:RefreshPalettes()
    local first = plus._msuf2SavedButtons[1]
    first:GetScript("OnClick")(first, "RightButton")
    Check(#store.saved == 26 and store.saved[1] == "#000002", "saved colour removal must retain its row index")
    first:GetScript("OnClick")(first, "LeftButton")
    Check(ButtonIs(0, 0, 2 / 255), "saved colour click must apply the refreshed row value")
    picker:Cancel()
    world.widgets:RunTimers()
    Check(ButtonIs(0.2, 0.4, 0.6), "precision edits must still cancel back to the original owner colour")
    local frameCount = #world.widgets.frames
    for _ = 1, 5 do
        button:GetScript("OnClick")(button)
        Check(plus._msuf2RGB == fields and plus._msuf2Hex == hex, "reopen must retain the same inputs")
        picker:Cancel()
        world.widgets:RunTimers()
    end
    Check(#world.widgets.frames == frameCount, "warm reopen must not rebuild precision editor frames")
end
W.OpenColorContextPicker = contextPicker

print("menu_color_picker_fallback_smoke: ok (owner kept through Classic Okay/Cancel, released afterwards)")
