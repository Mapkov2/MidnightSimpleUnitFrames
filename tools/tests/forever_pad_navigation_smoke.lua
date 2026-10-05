-- WoW Forever Gamepad UI: MSUF and Suite windows use MSUF's own pad navigation
-- (Game/Forever/PadNavigation.lua with PadKeyboard, PadPrompts and PadEditMode).
-- Registering an addon window with Blizzard's frame controls manager tainted the
-- gamepad input state (spellbook casts and SetPreferredGamepadInteractTarget were
-- blocked until a reload), and SmartNavigation rescanned the window on every
-- CreateFrame below it, which froze the client while a menu page was built.
--
-- Usage: lua tools/tests/forever_pad_navigation_smoke.lua <repoRoot>
local root = assert(arg[1], "repository root required"):gsub("[/\\]$", "")
local FOREVER = "MidnightSimpleUnitFrames/Game/Forever/"
local MODULES = { "PadNavigation.lua", "PadKeyboard.lua", "PadPrompts.lua", "PadEditMode.lua" }

local function Read(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing " .. rel)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local function Code(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return table.concat(lines, "\n")
end

-- 1. No addon code touches Blizzard's gamepad focus manager or binding stack.
local FILES = {
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Dropdowns.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua",
}
for index = 1, #MODULES do FILES[#FILES + 1] = FOREVER .. MODULES[index] end
for index = 1, #FILES do
    local code = Code(Read(FILES[index]))
    assert(not code:find("FrameControlsManager", 1, true) and not code:find("GamepadMode", 1, true),
        FILES[index] .. " calls Blizzard's gamepad frame controls manager")
end
local windowCode = Code(Read(FILES[1]))
assert(windowCode:find("PADLSHOULDER = function() PressHistoryButton(M.pageHistoryBackButton) end", 1, true)
    and windowCode:find("PADRSHOULDER = function() PressHistoryButton(M.pageHistoryForwardButton) end", 1, true)
    and windowCode:find("PADBACK = JumpNavigationContent,", 1, true),
    "LB/RB must press the menu's Back/Forward page buttons and View must jump between navigation and page")
assert(windowCode:find("searchField = function() return M.nav and M.nav.searchBox end,", 1, true)
    and windowCode:find("undo = function() return M.Undo() == true end,", 1, true)
    and windowCode:find("redo = function() return M.Redo() == true end,", 1, true),
    "Y must open the menu's search and LT + LB/RB must undo/redo through the menu's history")
assert(Code(Read(FILES[2])):find("    dropdownScroll._msuf2ScrollTo = SmoothDropdownScrollTo\n", 1, true),
    "the dropdown list must let the pad glide it with its own smooth scroll")
assert(Code(Read(FILES[3])):find(
    "if navigation and frame.GetParent and frame:GetParent() == UIParent then navigation.Track(frame) end", 1, true),
    "menu popups on UIParent must take the pad when they show")
assert(Code(Read("MidnightSimpleUnitFrames/Shell/UI/MSUF_EditPopupUI.lua")):find(
    "if btn:IsMouseOver() or self:IsMouseOver() or self._msufPadHeld then", 1, true),
    "Edit Mode dropdown lists must stay open while the pad holds them")
assert(Code(Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_HUD_Picker.lua")):find(
    "if self._msufPadHeld or (owner and owner:IsMouseOver()) or self:IsMouseOver() then", 1, true),
    "the Edit Mode toolbar's frame list must stay open while the pad holds it")
local nudgeCode = Code(Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Layout_Nudge.lua"))
assert(nudgeCode:find("function Nudge.By(dx, dy)\n    return NudgeTarget(dx, dy, true)\nend", 1, true),
    "Edit Mode must export an exact nudge for the right stick")
assert(nudgeCode:find("function Nudge.AuraBy(unitKey, auraGroup, dx, dy)", 1, true)
    and nudgeCode:find("        return NudgeAuraGroup(db, auraGroup, unitKey, ndx, ndy)\n", 1, true),
    "Edit Mode must nudge an aura group without its popup, through the arrow keys' aura path")
assert(Code(Read("MidnightSimpleUnitFrames/Shell/MSUF_GameMenu.lua")):find(
    "if gameMenu and not ForeverGamepadUI() then", 1, true),
    "the game menu entry must not hide Blizzard's game menu from addon code under the Gamepad UI")
-- Only WoW Forever (game type camelot) loads them; Retail never parses them.
local CAMELOT = " [AllowLoadGameType camelot]\n"
assert(Read("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"):find(
    "Game\\Forever\\SwingTimer.lua\nGame\\Forever\\PadNavigation.lua" .. CAMELOT
    .. "Game\\Forever\\PadKeyboard.lua" .. CAMELOT .. "Game\\Forever\\PadPrompts.lua" .. CAMELOT
    .. "Game\\Forever\\PadEditMode.lua" .. CAMELOT, 1, true),
    "the Mainline TOC must load the pad navigation files in order after SwingTimer.lua, on WoW Forever only")
-- Every hint label exists in every locale pack but the enUS base.
local LABELS = {
    "Select", "Type text", "Adjust", "Done moving", "Move 1 px", "Previous / next element", "Switch window",
    "Scroll", "Tooltips", "Previous / next page", "Navigation / content", "Leave Edit Mode", "Type key", "Space",
    "Move cursor", "Confirm", "Close", "Back", "Move", "Delete",
    "Pick a frame with the D-pad, then press A to anchor it. B cancels.", "Toolbar / elements", "Open settings",
    "Menu", "Type a value", "Undo / redo", "Find a setting",
}
for _, locale in ipairs({ "deDE", "enGB", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local pack = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
    for index = 1, #LABELS do
        assert(pack:find('L["' .. LABELS[index] .. '"] = "', 1, true), locale .. " lacks the hint " .. LABELS[index])
    end
end

-- 2. Headless frames: a parent tree, single-anchor layout and recorded input state.
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
issecretvalue = function(value) return value == SECRET end
local POINTS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local createdWithParent, focus, created = 0, nil, {}
local Frame = {}
Frame.__index = Frame

local atlases, regions = {}, {}
local function Region()
    local region = { shown = true }
    regions[#regions + 1] = region
    local function Noop() end
    for _, name in ipairs({ "SetColorTexture", "SetAllPoints", "SetSize", "SetWidth", "SetHeight", "SetPoint",
        "ClearAllPoints", "SetVertexColor", "SetJustifyH" }) do region[name] = Noop end
    function region.SetAtlas(self, atlas) atlases[atlas] = true; self.atlas = atlas end
    function region.SetTexCoord(self, left) self.texLeft = left end
    function region.SetText(self, text) self.text = text end
    function region.GetStringWidth(self) return #(self.text or "") * 6 end
    function region.Show(self) self.shown = true end
    function region.Hide(self) self.shown = false end
    function region.SetShown(self, shown) self.shown = shown and true or false end
    return region
end

local function AnimationGroup()
    local group = {}
    local function Noop() end
    group.SetLooping, group.Play = Noop, Noop
    function group.CreateAnimation()
        return { SetOffset = Noop, SetDuration = Noop, SetOrder = Noop, SetSmoothing = Noop }
    end
    return group
end

local function NewFrame(kind)
    return setmetatable({ kind = kind or "Frame", shown = true, children = {}, scripts = {}, points = {},
        width = 0, height = 0, mouse = kind == "Button" or kind == "EditBox", alpha = 1, enabled = true }, Frame)
end
function Frame:SetParent(parent)
    if self.parent then
        for index = #self.parent.children, 1, -1 do
            if self.parent.children[index] == self then table.remove(self.parent.children, index) end
        end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Frame:GetParent() return self.parent end
function Frame:GetName() return self.name end
function Frame:IsForbidden() return false end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetNumChildren() return #self.children end
function Frame:IsObjectType(kind) return self.kind == kind end
function Frame:Show() if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end
    for index = 1, #(self.showHooks or {}) do self.showHooks[index](self) end end end
function Frame:Hide()
    if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
        for index = 1, #(self.hideHooks or {}) do self.hideHooks[index](self) end
    end
end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
function Frame:SetScript(name, handler) self.scripts[name] = handler end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HasScript() return true end
function Frame:HookScript(name, handler)
    local key = name == "OnShow" and "showHooks" or (name == "OnHide" and "hideHooks")
    assert(key, "only OnShow/OnHide are hooked")
    self[key] = self[key] or {}
    self[key][#self[key] + 1] = handler
end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) ~= "table" then relative, relativePoint, x, y = self.parent, point, relative, relativePoint end
    self.points[#self.points + 1] = { point, relative or self.parent, relativePoint or point, x or 0, y or 0 }
end
function Frame:GetRect()
    if self.rect then return unpack(self.rect) end
    local anchor = self.points[1]
    if not anchor then return nil end
    local l, b, w, h = anchor[2]:GetRect()
    if not l then return nil end
    local from, to = POINTS[anchor[3]], POINTS[anchor[1]]
    local x, y = l + from[1] * w + anchor[4], b + from[2] * h + anchor[5]
    return x - to[1] * self.width, y - to[2] * self.height, self.width, self.height
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetEffectiveAlpha() return self.alpha end
function Frame:EnableMouse(enabled) self.mouse = enabled end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:IsEnabled() return self.enabled end
function Frame:SetFrameStrata() end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:SetClampedToScreen() end
function Frame:EnableGamePadButton(enabled) self.padButtons = enabled end
function Frame:EnableGamePadStick(enabled) self.padStick = enabled end
function Frame:RegisterEvent() end
function Frame:UnregisterEvent() end
function Frame:CreateTexture() return Region() end
function Frame:CreateFontString() return Region() end
function Frame:CreateAnimationGroup() return AnimationGroup() end
function Frame:MouseDown(button) self.pressed = button end
function Frame:MouseUp(button)
    if self.pressed == button and self.scripts.OnClick then self.scripts.OnClick(self, button) end
    self.pressed = nil
end
function Frame:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button) end end
-- Edit boxes
function Frame:GetText() return self.textValue or "" end
function Frame:SetText(text) self.textValue = text; self.cursor = #text; self.scripts.OnTextChanged(self, false) end
function Frame:Insert(text)
    local value, cursor = self:GetText(), self.cursor or #self:GetText()
    self.textValue = value:sub(1, cursor) .. text .. value:sub(cursor + 1)
    self.cursor = cursor + #text
    self.scripts.OnTextChanged(self, false)
end
function Frame:GetCursorPosition() return self.cursor or 0 end
function Frame:SetCursorPosition(position) self.cursor = position end
function Frame:SetFocus() focus = self end
function Frame:ClearFocus() if focus == self then focus = nil end end
function Frame:HasFocus() return focus == self end
function Frame:IsNumeric() return false end
-- Scroll frames
function Frame:GetVerticalScrollRange() return self.range or 0 end
function Frame:GetVerticalScroll() return self.offset or 0 end
function Frame:SetVerticalScroll(offset) self.offset = offset end

CreateFrame = function(kind, _, parent)
    if parent ~= nil then createdWithParent = createdWithParent + 1 end
    local frame = NewFrame(kind)
    created[#created + 1] = frame
    if parent then frame:SetParent(parent) end
    return frame
end
UIParent = NewFrame("Frame")
UIParent.rect = { 0, 0, 1920, 1080 }
GetCurrentKeyBoardFocus = function() return focus end
-- An English client with a German MSUF menu: the keyboard follows the menu.
GetLocale = function() return "enUS" end
ExecuteFrameScript = function(frame, name, ...)
    local handler = frame.scripts[name]
    if handler then handler(frame, ...) end
end
InCombatLockdown = function() return false end
GetCVarBool = function() return false end
local tooltipOwner
GameTooltip = {
    IsOwned = function(_, frame) return tooltipOwner == frame end,
    Hide = function() tooltipOwner = nil end,
}
local padUI = true
InputUtil = { IsGamepadUIEnabled = function() return padUI end }
local blizzardPanelFocused = false
SmartNavigation = setmetatable({ IsShown = function() return blizzardPanelFocused end }, {
    __newindex = function() error("pad navigation wrote to SmartNavigation") end })
GamepadMode = setmetatable({}, { __index = function(_, key) error("pad navigation used GamepadMode." .. key) end })
local vibrations, rumbles, stopped = 0, {}, 0
local function NativeStop() stopped = stopped + 1 end
C_GamePad = {
    SetVibration = function(motor, intensity) vibrations = vibrations + 1; rumbles[#rumbles + 1] = motor .. ":" .. intensity end,
    StopVibration = NativeStop,
}
local tickers, timers, now = {}, {}, 100
GetTime = function() return now end
C_Timer = {
    NewTicker = function(_, callback)
        local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
        tickers[#tickers + 1] = ticker
        return ticker
    end,
    After = function(seconds, callback)
        -- The client rejects a C function here ("Usage: C_Timer.After(seconds, callback)").
        assert(type(seconds) == "number" and type(callback) == "function" and callback ~= NativeStop,
            "C_Timer.After needs a Lua callback")
        timers[#timers + 1] = callback
    end,
}
InputIconTextureSetUtility = { GetActiveInputIconButtonTextures = function(key) return { "atlas-" .. key } end }
-- A has one of Blizzard's large 76x75 prompt atlases; the client lacks R3's.
C_Texture = { GetAtlasInfo = function(atlas)
    if atlas == "atlas-PADRSTICK" then return nil end
    return atlas == "atlas-PAD1" and { width = 76, height = 75 } or { width = 64, height = 64 }
end }

-- The German menu language with the German pack's translation of the keyboard's Done.
local germanDone = assert(Read("MidnightSimpleUnitFrames/Locales/deDE.lua"):match("\nL%[\"Done\"%] = \"([^\"]+)\""),
    "the German pack lacks Done")
local MSUF = { Client = { IsForever = true }, GetEffectiveLocale = function() return "deDE" end,
    L = { ["Done"] = germanDone } }
for index = 1, #MODULES do
    assert(loadfile(root .. "/" .. FOREVER .. MODULES[index]))("MidnightSimpleUnitFrames", MSUF)
end
local Nav = assert(MSUF.PadNavigation and _G.MSUF_PadNavigation == MSUF.PadNavigation, "navigation not exported")
and MSUF.PadNavigation
assert(Nav.Keyboard and Nav.Prompts, "keyboard and button hints did not register")
local prompts
local showPrompts = Nav.Prompts.Show
Nav.Prompts.Show = function(list, anchor, moving)
    prompts = { moving = moving }
    for index = 1, #list - 1, 2 do prompts[list[index + 1]] = list[index] end
    return showPrompts(list, anchor, moving)
end
local events
for _, frame in ipairs(created) do if frame.scripts.OnEvent then events = frame end end
assert(events and events.parent == nil, "no unparented event frame")
assert(#tickers == 0, "the poll ticker started before login")
events.scripts.OnEvent(events, "PLAYER_LOGIN")
assert(#tickers == 1, "the poll ticker did not start at login")

-- A window with a 2x2 grid of buttons, a numeric edit box and a slider.
local window = NewFrame("Frame")
window:SetParent(UIParent)
window.rect = { 100, 100, 600, 500 }
local clicks = {}
local function Control(kind, l, b)
    local control = NewFrame(kind)
    control:SetParent(window)
    control.rect = { l, b, 80, 24 }
    control.scripts.OnClick = function(self, button) clicks[#clicks + 1] = { self, button } end
    return control
end
local topLeft, topRight = Control("Button", 120, 500), Control("Button", 300, 500)
local bottomLeft, bottomRight = Control("Button", 120, 400), Control("Button", 300, 400)
local edit = Control("EditBox", 120, 300)
edit.textValue, edit.cursor = "12", 2
local typed = {}
edit.scripts.OnTextChanged = function(self, userInput) typed[#typed + 1] = { self:GetText(), userInput } end
local entered = 0
edit.scripts.OnEnterPressed = function(self) entered = entered + 1; self:ClearFocus() end
local slider = Control("Slider", 300, 300)
slider.value, slider.scripts.OnClick, slider.mouse = 5, nil, true
function slider:GetValue() return self.value end
function slider:SetValue(value) self.value = value end
function slider:GetValueStep() return 1 end
function slider:GetMinMaxValues() return 0, 6 end
local hidden = Control("Button", 120, 200)
hidden:Hide()
local secret = Control("Button", 300, 200)
secret.rect = { SECRET, 200, 80, 24 }
topLeft.scripts.OnEnter = function(self) tooltipOwner = self end

local closed, lb, rb = 0, 0, 0
Nav.Attach(window, function(frame) closed = closed + 1; frame:Hide() end, {
    PADLSHOULDER = function() lb = lb + 1 end, PADRSHOULDER = function() rb = rb + 1 end,
}, { hints = { "PADLSHOULDER/PADRSHOULDER", "Previous / next page" } })
local before = createdWithParent
Nav.Activate(window)
assert(createdWithParent == before, "pad navigation passed a parent to CreateFrame (SmartNavigation hook)")
assert(Nav.IsCapturing() and Nav.GetSelection() == topLeft, "the window did not take the pad on its top-left control")
assert(prompts and prompts.Select == "PAD1" and prompts.Close == "PAD2" and prompts["Previous / next page"]
    == "PADLSHOULDER/PADRSHOULDER" and prompts.Tooltips == "PADRSTICK",
    "the button hints did not describe the window")
assert(atlases["atlas-PAD1"] and atlases["atlas-PADLSHOULDER"] and atlases["atlas-SLASH"],
    "the button hints did not use the controller's icons")
local function ShownRegion(test)
    for index = 1, #regions do
        if regions[index].shown and test(regions[index]) then return regions[index] end
    end
end
assert(ShownRegion(function(region) return region.atlas == "atlas-PAD1" and region.texLeft == 0.015 end)
    and ShownRegion(function(region) return region.atlas == "atlas-PAD2" and region.texLeft == 0 end),
    "a large prompt atlas must be laid out like Blizzard's InputIconTextureMixin")
assert(not atlases["atlas-PADRSTICK"] and ShownRegion(function(region) return region.text == "R3" end),
    "a button whose atlas the client lacks must show as text, not an empty gap")
local hintBar, selectionRing
for _, frame in ipairs(created) do
    if frame.level == Nav.Kit.RING_LEVEL - 50 then hintBar = frame end
    if frame.level == Nav.Kit.RING_LEVEL then selectionRing = frame end
end
assert(Nav.Kit.RING_LEVEL > 1500 and hintBar and selectionRing,
    "the ring and the hints must sit above the Edit Mode toolbar and its lists (TOOLTIP 1200-1500)")
local function HintPoint() return hintBar.points[1][1], hintBar.points[1][2], hintBar.points[1][3] end
local point, relative, relativePoint = HintPoint()
assert(point == "TOP" and relative == window and relativePoint == "BOTTOM", "the hints did not sit under the window")
local input
for _, child in ipairs(UIParent.children) do
    if child.scripts.OnGamePadButtonDown then input = child end
end
assert(input and input.padButtons == true and input:IsShown(), "no pad input frame")
local function Press(button)
    input.scripts.OnGamePadButtonDown(input, button)
    input.scripts.OnGamePadButtonUp(input, button)
end

-- Tooltips: the right stick press hides them and brings them back.
assert(tooltipOwner == topLeft, "the selection did not show its tooltip")
Press("PADRSTICK")
assert(tooltipOwner == nil, "R3 did not hide the tooltip")
Press("PADRSTICK")
assert(tooltipOwner == topLeft, "R3 did not show the tooltip again")

Press("PADDRIGHT")
assert(Nav.GetSelection() == topRight, "right did not move to the next column")
Press("PADDDOWN")
assert(Nav.GetSelection() == bottomRight, "down did not keep the column")
Press("PADDLEFT")
assert(Nav.GetSelection() == bottomLeft, "left did not move back")
local bumps = vibrations
Press("PADDLEFT")
assert(Nav.GetSelection() == bottomLeft and vibrations == bumps + 1 and rumbles[#rumbles] == "High:0.45",
    "an edge press did not give the strong rumble")
now = now + 1
timers[#timers]()
assert(stopped > 0, "the rumble was not stopped")
Press("PADDRIGHT")
assert(rumbles[#rumbles] == "Low:0.12", "a step did not give the light tick")
Press("PADDLEFT")
Press("PAD1")
assert(#clicks == 1 and clicks[1][1] == bottomLeft and clicks[1][2] == "LeftButton", "A did not click the selection")
Press("PAD3")
assert(#clicks == 2 and clicks[2][2] == "RightButton", "X did not right-click the selection")
Press("PADLSHOULDER"); Press("PADRSHOULDER")
assert(lb == 1 and rb == 1, "window shoulder actions did not run")
local pressesBeforeY = vibrations
Press("PAD4")
assert(vibrations == pressesBeforeY + 1 and not prompts.moving and #clicks == 2,
    "Y on a control that cannot move must only rumble, never click it")

-- Hidden and secret-geometry controls are never selected.
Press("PADDDOWN"); Press("PADDRIGHT")
assert(Nav.GetSelection() == slider and prompts.Adjust == "DIRPADHORIZONTAL", "down/right did not reach the slider")
Press("PADDDOWN")
assert(Nav.GetSelection() == slider, "a hidden or secret-geometry control was selected")
Press("PADDLEFT")
assert(slider.value == 4, "left on a slider must step its value")
Press("PADDRIGHT"); Press("PADDRIGHT"); Press("PADDRIGHT")
assert(slider.value == 6, "the slider step must clamp to its range")
-- Held, a slider with room steps faster; a single press steps by one again.
function slider:GetMinMaxValues() return 0, 1000 end
slider.value = 100
input.scripts.OnGamePadButtonDown(input, "PADDRIGHT")
for _ = 1, 40 do input.scripts.OnUpdate(input, 0.05) end
input.scripts.OnGamePadButtonUp(input, "PADDRIGHT")
assert(slider.value - 100 > 45, "holding right did not speed the slider up")
local heldValue = slider.value
Press("PADDRIGHT")
assert(slider.value == heldValue + 1, "a single press after a hold must step by one again")
function slider:GetMinMaxValues() return 0, 6 end
slider.value = 6
-- A on a Menu2 slider types its exact value into its value box (W.Slider's editBox).
local valueBox = NewFrame("EditBox")
valueBox:SetParent(slider)
valueBox.rect, valueBox.mouse, valueBox.textValue = { 390, 300, 40, 20 }, false, "6"
valueBox.scripts.OnTextChanged = function() end
valueBox.scripts.OnEnterPressed = function(self) slider.value = tonumber(self:GetText()); self:ClearFocus() end
slider.editBox = valueBox
tickers[1].callback()
assert(prompts["Type a value"] == "PAD1", "a slider with a value box did not offer A for an exact value")
Press("PAD1")
assert(focus == valueBox and Nav.GetSelection().label.text == "7", "A did not open the number pad on the slider's value box")
Press("PAD1")
Press("PADFORWARD")
assert(slider.value == 67 and focus == nil and Nav.GetSelection() == slider, "the typed value did not reach the slider")
slider.value, slider.editBox = 6, nil
valueBox:Hide()

-- A Blizzard panel holding SmartNavigation, combat, or the Gamepad UI off give the pad back.
blizzardPanelFocused = true
tickers[1].callback()
assert(not Nav.IsCapturing() and input.padButtons == false, "the pad was kept while a Blizzard panel had focus")
blizzardPanelFocused = false
tickers[1].callback()
assert(Nav.IsCapturing() and Nav.GetSelection() == slider, "the pad did not come back to its selection")
events.scripts.OnEvent(events, "PLAYER_REGEN_DISABLED")
assert(not Nav.IsCapturing() and input.padButtons == false, "the pad was kept in combat")
events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
assert(Nav.IsCapturing() and input.padButtons == true, "the pad did not come back after combat")
padUI = false
tickers[1].callback()
assert(not Nav.IsCapturing(), "the pad was kept with the Gamepad UI off")
padUI = true
tickers[1].callback()
assert(Nav.IsCapturing(), "the pad did not come back with the Gamepad UI on")

-- On-screen keyboard: A on an edit box, number pad for a number, typed text
-- reports userInput, X deletes, Start confirms through OnEnterPressed.
Press("PADDUP"); Press("PADDLEFT"); Press("PADDDOWN")
assert(Nav.GetSelection() == edit and prompts["Type text"] == "PAD1", "up/left/down did not reach the edit box")
Press("PAD1")
assert(focus == edit, "the edit box did not take focus")
local keyboard = Nav.GetSelection() and Nav.GetSelection():GetParent()
assert(keyboard and keyboard ~= window and keyboard:IsShown() and Nav.GetSelection().label, "the keyboard did not open")
assert(Nav.GetSelection().label.text == "7", "a number field must open the number pad on 7")
assert(prompts["Type key"] == "PAD1" and prompts.Delete == "PAD3" and prompts.Confirm == "PADFORWARD",
    "the keyboard hints were not shown")
-- The word keys speak the menu language (German here); symbols stay symbols.
local captions = {}
for _, key in ipairs(keyboard.children) do
    if key.padAction and key.label then captions[key.padAction .. ":" .. key.padLayout] = key.label.text end
end
assert(captions["done:number"] == germanDone and captions["done:text"] == germanDone
    and captions["layout:text:number"] == "ABC" and captions["shift:text"] == "Aa" and captions["layout:number:text"] == "123",
    "the keyboard's word keys were not in the menu language")
-- Done is translated by the locale packs, never by a table in the keyboard.
local keyboardCode = Code(Read(FOREVER .. "PadKeyboard.lua"))
local _, inlineDone = keyboardCode:gsub('done = "', "")
assert(inlineDone == 1 and keyboardCode:find('L["Done"]', 1, true),
    "the keyboard's Done caption must come from MSUF.L, not from captions translated inside PadKeyboard.lua")
Press("PAD1")
assert(edit:GetText() == "127" and typed[#typed][2] == true, "the key was not typed as user input")
Press("PAD3")
assert(edit:GetText() == "12", "X did not delete backwards")
Press("PAD2")
assert(not keyboard:IsShown() and Nav.GetSelection() == edit, "B did not close the keyboard back onto the field")
assert(focus == nil and window:IsShown(), "B on the keyboard must end editing like a click elsewhere")
Press("PAD1")
Press("PADFORWARD")
assert(entered == 1 and not keyboard:IsShown(), "Start did not confirm through OnEnterPressed")
-- The German letter page (QWERTZ), one capital at a time like a phone.
edit.textValue, edit.cursor = "", 0
Press("PAD1")
assert(Nav.GetSelection().label.text == "1", "a text field must open the letter page")
Press("PADDDOWN"); Press("PADDRIGHT"); Press("PADDRIGHT"); Press("PADDRIGHT"); Press("PADDRIGHT"); Press("PADDRIGHT")
assert(Nav.GetSelection().label.text == "z", "the German menu language must give the QWERTZ page")
Press("PADDDOWN"); Press("PADDDOWN"); Press("PADDDOWN")
for _ = 1, 6 do Press("PADDLEFT") end
assert(Nav.GetSelection().padAction == "shift", "the bottom row did not start with the shift key")
Press("PAD1")
Press("PADDUP")
assert(Nav.GetSelection().label.text == "Y", "shift did not show capitals")
Press("PAD1")
assert(edit:GetText() == "Y" and Nav.GetSelection().label.text == "y", "shift must type one capital, then lower case")
Press("PAD2")
assert(focus == nil and not keyboard:IsShown(), "B did not close the keyboard")
-- A field with its own match list (the search fields: Up/Down through
-- OnArrowPressed): while typing, the right stick walks that list, one step at
-- once on a flick and repeating while held, with a light tick per step.
local listKeys = {}
edit.scripts.OnArrowPressed = function(_, key) listKeys[#listKeys + 1] = key end
Press("PAD1")
assert(keyboard:IsShown() and prompts.Scroll == "PADRSTICKAXIS" and prompts.Select == "PADRSTICK"
    and input.padStick == true, "the keyboard did not offer the right stick for the field's list")
local ticks = #rumbles
input.scripts.OnGamePadStick(input, "Right", 0, -1)
input.scripts.OnUpdate(input, 0.01)
assert(listKeys[1] == "DOWN" and #listKeys == 1 and rumbles[#rumbles] == "Low:0.12" and #rumbles > ticks,
    "a flick down did not move one match down at once")
for _ = 1, 30 do input.scripts.OnUpdate(input, 0.02) end
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(#listKeys >= 3 and #listKeys <= 8, "holding the stick did not repeat at a readable rate")
input.scripts.OnGamePadStick(input, "Right", 0, 1)
input.scripts.OnUpdate(input, 0.01)
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(listKeys[#listKeys] == "UP", "a flick up did not move one match up")
-- A press on the same stick opens the picked match the way Enter does.
Press("PADRSTICK")
assert(entered == 2 and not keyboard:IsShown() and focus == nil, "R3 did not open the picked match")
edit.scripts.OnArrowPressed = nil

-- Y where nothing moves opens the window's search field with the keyboard.
Nav.Attach(window, nil, nil, { hints = { "PADLSHOULDER/PADRSHOULDER", "Previous / next page" },
    searchField = function() return edit end })
assert(Nav.SelectControl(topRight) and prompts["Find a setting"] == "PAD4", "the window did not offer Y for its search")
Press("PAD4")
assert(focus == edit and keyboard:IsShown() and Nav.GetSelection():GetParent() == keyboard,
    "Y did not open the search field with the keyboard")
Press("PAD2")
assert(not keyboard:IsShown() and Nav.GetSelection() == edit, "B did not close the search keyboard onto its field")
Nav.Attach(window, nil, nil, { hints = { "PADLSHOULDER/PADRSHOULDER", "Previous / next page" } })

-- Right stick: a control's own _msufPadNudge moves it; the left stick stays the game's.
local moved = { 0, 0 }
topLeft._msufPadNudge = function(_, dx, dy) moved[1], moved[2] = moved[1] + dx, moved[2] + dy end
Press("PADDUP"); Press("PADDUP"); Press("PADDUP"); Press("PADDLEFT")
assert(Nav.GetSelection() == topLeft and input.padStick == true and prompts.Move == "PAD4",
    "a movable control did not take the right stick")
assert(input.scripts.OnGamePadStick(input, "Movement", 1, 0) == true, "the left stick must stay with the game")
assert(input.scripts.OnGamePadStick(input, "Right", 1, -1) == false, "the right stick (\"Right\") was not consumed")
input.scripts.OnUpdate(input, 0.5)
assert(moved[1] > 0 and moved[2] < 0, "the right stick did not nudge the control")
input.scripts.OnGamePadStick(input, "Right", 0, 0)
-- Y: move mode, the D-pad nudges by 1 px and B leaves it.
Press("PAD4")
assert(prompts.moving and prompts["Move 1 px"] == "DIRPAD", "Y did not start moving")
local beforeX = moved[1]
Press("PADDRIGHT")
assert(moved[1] == beforeX + 1 and Nav.GetSelection() == topLeft, "the D-pad did not nudge by 1 px while moving")
Press("PAD2")
assert(not prompts.moving and window:IsShown(), "B did not leave move mode first")
Press("PADDRIGHT")
assert(Nav.GetSelection() == topRight and input.padStick == false, "the right stick stayed captured without a nudge")
-- A press on another control ends a field's editing, like a mouse click does.
edit:SetFocus()
Press("PAD1")
assert(focus == nil, "A on a button left another field focused")

-- Right stick scrolls a page when nothing can move.
local scroll = NewFrame("ScrollFrame")
scroll:SetParent(window)
scroll.rect, scroll.range, scroll.offset = { 110, 110, 500, 150 }, 300, 100
local inScroll = NewFrame("Button")
inScroll:SetParent(scroll)
inScroll.rect = { 130, 200, 80, 24 }
Press("PADDDOWN"); Press("PADDDOWN"); Press("PADDDOWN")
assert(Nav.GetSelection() == inScroll and input.padStick == true and prompts.Scroll == "PADRSTICKAXIS",
    "a control in a scroll frame did not offer stick scrolling")
input.scripts.OnGamePadStick(input, "Right", 0, -1)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(scroll.offset > 140 and scroll.offset < 150, "the right stick did not scroll down at its starting rate")
-- Menu2's dropdown list glides like its mouse wheel (_msuf2ScrollTo): the
-- stick and the D-pad aim it from where its animation lands, never jump.
local glides = {}
scroll._msuf2ScrollTo = function(offset)
    glides[#glides + 1] = offset
    scroll._msuf2SmoothScrollTarget = offset
end
local visible = scroll.offset
input.scripts.OnGamePadStick(input, "Right", 0, -1)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(#glides == 2 and scroll.offset == visible and glides[1] > visible and glides[2] > glides[1],
    "the stick did not glide the list from its animation goal")
local below = NewFrame("Button")
below:SetParent(scroll)
below.rect = { 130, -100, 80, 24 }
Press("PADDDOWN")
assert(Nav.GetSelection() == below and glides[#glides] > glides[2] and scroll.offset == visible,
    "the D-pad did not glide the list to the next row")
scroll._msuf2ScrollTo, scroll._msuf2SmoothScrollTarget = nil, nil
scroll:Hide()

-- A preview handle moves through its arrow keys; LB/RB pick the next element.
local window2 = NewFrame("Frame")
window2:SetParent(UIParent)
window2.rect = { 100, 100, 400, 300 }
local box = NewFrame("Frame")
box:SetParent(window2)
box.rect = { 120, 120, 300, 200 }
local handle = NewFrame("Button")
handle:SetParent(box)
handle.rect = { 200, 200, 40, 20 }
local other = NewFrame("Button")
other:SetParent(box)
other.rect = { 300, 200, 40, 20 }
local arrows = {}
handle.scripts.OnKeyDown = function(_, key) arrows[#arrows + 1] = key end
other.scripts.OnKeyDown = handle.scripts.OnKeyDown
local cycled
MSUF2 = { PreviewSelectionBar = { CycleHandle = function(owner, backwards)
    cycled = backwards
    owner._selectedHandle = owner._selectedHandle == handle and other or handle
end } }
box._msuf2SelectionBar = false
box._msuf2SelectionDeps = { HandleList = function() return { handle, other } end }
handle.scripts.OnClick = function() box._selectedHandle = handle end
Nav.Activate(window2)
assert(Nav.GetSelection() == handle and input.padStick == false, "an unselected preview handle took the stick")
Press("PAD4")
assert(box._selectedHandle == handle and prompts.moving, "Y did not select the preview handle and start moving")
Press("PAD4")
assert(input.padStick == true, "the selected preview handle did not take the stick")
input.scripts.OnGamePadStick(input, "Camera", 1, 1)
for _ = 1, 10 do input.scripts.OnUpdate(input, 0.01) end
assert(#arrows >= 1 and #arrows <= 6 and arrows[1] == "RIGHT" and arrows[2] == "UP",
    "the stick did not press the handle's arrow keys at the guarded rate")
input.scripts.OnGamePadStick(input, "Camera", 0, 0)
Press("PAD4")
Press("PADRSHOULDER")
assert(cycled == false and Nav.GetSelection() == other and prompts.moving, "RB did not pick the next element")
Press("PAD4")
assert(not prompts.moving, "Y did not stop moving")
-- Without arrow keys the stick presses the selection bar's +/- buttons.
handle.scripts.OnKeyDown = nil
box._selectedHandle = handle
assert(Nav.SelectControl(handle), "SelectControl did not select a usable control")
local steps = {}
local function Step(name) local b = NewFrame("Button"); b.scripts.OnClick = function() steps[#steps + 1] = name end; return b end
box._msuf2SelectionBar = {
    axisX = { plusButton = Step("x+"), minusButton = Step("x-") },
    axisY = { plusButton = Step("y+"), minusButton = Step("y-") },
}
input.scripts.OnGamePadStick(input, "Right", -1, -1)
for _ = 1, 10 do input.scripts.OnUpdate(input, 0.01) end
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(steps[1] == "x-" and steps[2] == "y-" and #steps <= 6, "the stick did not press the selection bar's buttons")
assert(Nav.IsSelectionIn(box) and Nav.SelectFirstIn(box) and Nav.GetSelection() == handle,
    "SelectFirstIn did not pick the first control of a frame")
-- Anywhere in the preview box (a layer chip, the bar's X/Y fields) the stick
-- moves the preview's selected element, like Edit Mode; Y never clicks a chip.
local chip = NewFrame("Button")
chip:SetParent(box)
chip.rect = { 200, 130, 60, 20 }
local chipClicks = 0
chip.scripts.OnClick = function() chipClicks = chipClicks + 1 end
handle.scripts.OnKeyDown = function(_, key) arrows[#arrows + 1] = key end
box._selectedHandle = handle
assert(Nav.SelectControl(chip) and input.padStick == true and prompts.Move == "PAD4",
    "a layer chip did not move the preview's selected element")
local arrowCount = #arrows
input.scripts.OnGamePadStick(input, "Right", 1, 0)
for _ = 1, 10 do input.scripts.OnUpdate(input, 0.01) end
input.scripts.OnGamePadStick(input, "Right", 0, 0)
assert(#arrows > arrowCount and arrows[#arrows] == "RIGHT" and Nav.GetSelection() == chip,
    "the stick on a chip did not press the selected handle's arrow keys")
Press("PAD4")
assert(prompts.moving and chipClicks == 0, "Y on a chip must move the selected element, never click the chip")
Press("PADDLEFT")
assert(arrows[#arrows] == "LEFT" and Nav.GetSelection() == chip, "the D-pad did not nudge the element by 1 px")
Press("PAD4")
box._selectedHandle = nil
Press("PAD4")
assert(chipClicks == 0 and not prompts.moving and input.padStick == false,
    "Y on a chip without a selected element must not click the chip")
-- An aura icon forwards its clicks to its element's handle: Y selects that handle.
chip._msufDragProxyHandle = other
other.scripts.OnClick = function() box._selectedHandle = other end
Press("PAD4")
assert(box._selectedHandle == other and prompts.moving and chipClicks == 0,
    "Y on an aura icon did not select its element's handle")
Press("PAD4")
chip._msufDragProxyHandle = nil
window2:Hide()
tickers[1].callback()
assert(Nav.GetSelection() ~= handle, "a hidden window without Attach was not dropped by the poll")

-- A menu popup on UIParent tracked by Track takes the pad when it shows; B uses its own Finish.
local popup = NewFrame("Frame")
popup:SetParent(UIParent)
popup.rect = { 700, 20, 200, 150 }
popup:Hide()
local popupButton = NewFrame("Button")
popupButton:SetParent(popup)
popupButton.rect = { 720, 100, 80, 24 }
local finished
function popup:Finish(keep) finished = keep; self:Hide() end
Nav.Track(popup)
popup:Show()
assert(Nav.GetSelection() == popupButton, "a tracked popup did not take the pad when it showed")
point, relative, relativePoint = HintPoint()
assert(point == "BOTTOM" and relative == popup and relativePoint == "TOP",
    "the hints did not move above a window at the screen's bottom edge")
Press("PAD2")
assert(finished == true and not popup:IsShown() and Nav.GetSelection() ~= popupButton, "B did not finish the popup")
-- LB/RB jump a page in a scrolling list (a dropdown) and bring it into view.
local listFrame = NewFrame("Frame")
listFrame:SetParent(UIParent)
listFrame.rect = { 1000, 290, 200, 140 }
local listScroll = NewFrame("ScrollFrame")
listScroll:SetParent(listFrame)
listScroll.rect, listScroll.range, listScroll.offset = { 1000, 300, 200, 120 }, 400, 0
local listRows = {}
for index = 1, 20 do
    local row = NewFrame("Button")
    row:SetParent(listScroll)
    row.rect = { 1005, 400 - (index - 1) * 24, 190, 24 }
    listRows[index] = row
end
Nav.Attach(listFrame)
Nav.Activate(listFrame, listRows[1])
assert(Nav.GetSelection() == listRows[1] and prompts["Previous / next page"] == "PADLSHOULDER/PADRSHOULDER",
    "a scrolling list did not offer LB/RB page jumps")
Press("PADRSHOULDER")
assert(Nav.GetSelection() == listRows[6] and listScroll.offset > 0, "RB did not jump a page down the list")
Press("PADLSHOULDER")
assert(Nav.GetSelection() == listRows[1], "LB did not jump a page back up")
Press("PADLSHOULDER")
assert(Nav.GetSelection() == listRows[1] and rumbles[#rumbles] == "High:0.45", "LB at the top of the list must only rumble")
listFrame:Hide()

window:Hide()
-- Anchor picker: the pad walks named frames, LB/RB step through stacked ones,
-- A anchors through the picker's own checks, B cancels.
local function Named(name, parent, l, b, w, h)
    local frame = NewFrame("Frame")
    frame:SetParent(parent)
    frame.name, frame.rect = name, { l, b, w, h }
    return frame
end
local leftBar = Named("LeftBar", UIParent, 100, 500, 200, 40)
local rightBar = Named("RightBar", UIParent, 1500, 600, 200, 40)
local centerBox = Named("CenterBox", UIParent, 860, 440, 200, 200)
local innerBox = Named("InnerBox", centerBox, 910, 490, 100, 100)
Named("UnitButton", UIParent, 1500, 850, 100, 40).unitToken = "player"
local overlay = NewFrame("Frame")
overlay:SetParent(UIParent)
overlay.name, overlay.rect = "MSUF_AnchorPickerOverlay", { 0, 0, 1920, 1080 }
overlay._highlight = NewFrame("Frame")
overlay._highlight:SetParent(overlay)
overlay._hover, overlay._sub, overlay._ctrlHint = Region(), Region(), Region()
overlay._lHoverFmt, overlay._lTargetNotAllowed = "Hover: %s", "not allowed"
local picked
overlay._onPick = function(name) picked = name end
overlay._isCandidateAllowed = function(_, name) return name ~= "LeftBar" end
overlay:Hide()
MSUF_AnchorPickerOverlay = overlay
overlay:Show()
overlay.scripts.OnUpdate = function() overlay._hover.text = "mouse hover" end
tickers[1].callback()
assert(overlay.scripts.OnUpdate == nil, "the picker's mouse hover loop kept running while the pad picks")
assert(overlay._msufPadHeld and overlay._hover.text == "Hover: InnerBox"
    and overlay._sub.text == "Pick a frame with the D-pad, then press A to anchor it. B cancels."
    and prompts.Select == "PAD1", "the picker did not start on the frame nearest the centre")
Press("PADRSHOULDER")
assert(overlay._hover.text == "Hover: CenterBox", "RB did not step to the larger frame at the same spot")
Press("PADDLEFT")
assert(overlay._hover.text == "Hover: LeftBar", "left did not reach the next frame")
Press("PAD1")
assert(picked == nil and overlay:IsShown() and overlay._sub.text == "not allowed", "a disallowed target was anchored")
Press("PADDRIGHT"); Press("PADDRIGHT")
assert(overlay._hover.text == "Hover: RightBar", "right did not walk across the screen")
Press("PADDUP")
assert(overlay._hover.text == "Hover: RightBar", "a unit button must never be a candidate")
Press("PAD1")
assert(picked == "RightBar" and not overlay:IsShown(), "A did not anchor to the chosen frame")
leftBar:Hide(); rightBar:Hide(); centerBox:Hide()

-- Edit Mode: the mover layer, its HUD and its popups are taken over by name.
local exits, selections, nudges = {}, {}, {}
local stateKey = "player"
local moverParent = NewFrame("Frame")
moverParent:SetParent(UIParent)
moverParent.rect = { 0, 0, 1920, 1080 }
MSUF_EM2 = {
    State = {
        IsActive = function() return moverParent:IsShown() end,
        GetUnitKey = function() return stateKey end,
        SetUnitKey = function(key) stateKey = key end,
        Exit = function(source) exits[#exits + 1] = source; moverParent:Hide() end,
    },
    Focus = { SetSelection = function(key, _, _, opts) selections[#selections + 1] = key .. ":" .. opts.source end },
    Nudge = {
        By = function(dx, dy) nudges[#nudges + 1] = { stateKey, dx, dy } end,
        AuraBy = function(unit, kind, dx, dy) nudges[#nudges + 1] = { unit .. ":" .. kind, dx, dy } end,
    },
}
local function Child(kind, parent, l, b, w, h)
    local frame = NewFrame(kind)
    frame:SetParent(parent)
    frame.rect = { l, b, w, h }
    return frame
end
local playerMover = Child("Button", moverParent, 200, 600, 100, 30)
local targetMover = Child("Button", moverParent, 600, 600, 100, 30)
playerMover._barKey, targetMover._barKey = "player", "target"
local hud = Child("Frame", UIParent, 800, 1000, 300, 40)
local doneButton = Child("Button", hud, 1000, 1005, 60, 24)
MSUF_EM2.Movers = { Get = function(key) return key == "player" and playerMover or nil end }
local emPopup = Child("Frame", UIParent, 300, 300, 300, 200)
emPopup:Hide()
local xBox = Child("EditBox", emPopup, 320, 450, 60, 20)
xBox.textValue, xBox.scripts.OnTextChanged = "-12", function() end
targetMover.scripts.OnClick = function(self) stateKey = self._barKey; emPopup:Show() end
local menuWindow = Child("Frame", UIParent, 1300, 200, 400, 600)
local menuButton = Child("Button", menuWindow, 1320, 700, 80, 24)
local minimizedBar = Child("Frame", UIParent, 16, 16, 286, 32)
minimizedBar:Hide()
MSUF2.frame, MSUF2.minimizedBar = menuWindow, minimizedBar
function MSUF2.MinimizeSlashMenuWindow()
    menuWindow._msuf2Minimized = true
    minimizedBar:Show()
    menuWindow:Hide()
    return true
end
function MSUF2.RestoreMinimizedSlashMenu()
    minimizedBar:Hide()
    menuWindow._msuf2Minimized = nil
    menuWindow:Show()
end
function MSUF2.ResumeForeverPadNavigation() Nav.Activate(menuWindow) end
MSUF.MSUF2 = MSUF2
Nav.Activate(menuWindow)
assert(Nav.GetSelection() == menuButton, "the menu window did not take the pad")
MSUF_EM2_MoverParent, MSUF_EM2_HUD, MSUF_EM2_UnitPopup = moverParent, hud, emPopup
tickers[1].callback()
assert(Nav.IsCapturing() and Nav.GetSelection() == playerMover, "Edit Mode did not start on its selected element")
assert(not menuWindow:IsShown() and minimizedBar:IsShown() and prompts["Switch window"] == nil,
    "the menu must wait on its title bar while the pad runs Edit Mode")
assert(prompts.Menu == "PADFORWARD", "the Edit Mode hints must offer Start for the menu")
assert(prompts["Leave Edit Mode"] == "PAD2" and prompts["Open settings"] == "PAD1"
    and prompts["Toolbar / elements"] == "PADBACK" and prompts["Previous / next element"] == "PADLSHOULDER/PADRSHOULDER",
    "the Edit Mode hints must name settings, the toolbar jump, element steps and leaving")
point, relative, relativePoint = HintPoint()
assert(point == "TOP" and relative == hud and relativePoint == "BOTTOM",
    "the Edit Mode hints must sit beside the toolbar, not at the screen's edge")
Press("PADBACK")
assert(Nav.GetSelection() == doneButton and prompts.Select == "PAD1", "View did not jump to the toolbar")
assert(input.padStick == false, "a HUD button that cannot move took the right stick")
Press("PADBACK")
assert(Nav.GetSelection() == playerMover, "View did not jump back to the element it left")
Press("PADBACK")
Press("PADDDOWN")
assert(Nav.GetSelection() == targetMover, "down from the HUD did not reach the nearest mover")
Press("PADLSHOULDER")
assert(Nav.GetSelection() == playerMover and not prompts.moving, "LB did not step to the previous element")
Press("PADRSHOULDER")
assert(Nav.GetSelection() == targetMover, "RB did not step to the next element")
-- LT held with LB/RB undoes and redoes Edit Mode changes in place; LT alone
-- still switches windows, on its release.
local undos, redos = 0, 0
MSUF_EM2.Undo = {
    DoUndo = function() undos = undos + 1; return true end,
    DoRedo = function() redos = redos + 1; return true end,
}
assert(prompts["Undo / redo"] == "PADLTRIGGER+PADLSHOULDER/PADRSHOULDER" and atlases["atlas-PLUS"],
    "the Edit Mode hints must offer LT + LB/RB for undo and redo")
local beforeUndo = Nav.GetSelection()
input.scripts.OnGamePadButtonDown(input, "PADLTRIGGER")
Press("PADLSHOULDER")
Press("PADRSHOULDER")
input.scripts.OnGamePadButtonUp(input, "PADLTRIGGER")
assert(undos == 1 and redos == 1 and Nav.GetSelection() == beforeUndo and rumbles[#rumbles] == "High:0.25",
    "LT + LB/RB did not undo and redo in place")
-- LT released while a Blizzard panel holds the pad never reaches the pad's
-- button-up; back in Edit Mode a plain LB/RB steps instead of undo/redo.
input.scripts.OnGamePadButtonDown(input, "PADLTRIGGER")
blizzardPanelFocused = true
tickers[1].callback()
assert(not Nav.IsCapturing(), "a Blizzard panel did not take the pad from Edit Mode")
blizzardPanelFocused = false
tickers[1].callback()
assert(Nav.IsCapturing() and Nav.GetSelection() == beforeUndo, "the pad did not come back to Edit Mode")
Press("PADLSHOULDER")
assert(undos == 1 and Nav.GetSelection() == playerMover,
    "a trigger released while the pad was away stayed held: plain LB ran undo instead of stepping")
Press("PADRSHOULDER")
assert(redos == 1 and Nav.GetSelection() == targetMover,
    "a trigger released while the pad was away stayed held: plain RB ran redo instead of stepping")
-- An aura group (Auras3 Edit Mode preview) moves through Edit Mode's aura
-- nudge without its popup; the unit frame under it stays put.
local auraGroup = Child("Frame", UIParent, 640, 660, 120, 30)
auraGroup._msufA3Unit, auraGroup._msufA3MoverKind = "target", "debuff"
auraGroup.scripts.OnMouseDown, auraGroup.mouse = function() end, true
MSUF.MSUF_Auras3 = { EditMode = { groups = { target = { debuff = auraGroup } } } }
Press("PADDUP")
assert(Nav.GetSelection() == auraGroup and prompts["Open settings"] == "PAD1" and prompts.Move == "PAD4",
    "up from a mover did not reach its aura group as a movable element")
local auraNudges = #nudges
Press("PAD4")
Press("PADDRIGHT")
assert(#nudges == auraNudges + 1 and nudges[#nudges][1] == "target:debuff" and nudges[#nudges][2] == 1
    and stateKey == "player", "the D-pad did not nudge the aura group by 1 px")
Press("PAD4")
input.scripts.OnGamePadStick(input, "Camera", 0, 1)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnGamePadStick(input, "Camera", 0, 0)
assert(nudges[#nudges][1] == "target:debuff" and nudges[#nudges][3] > 0, "the stick did not move the aura group")
auraGroup:Hide()
MSUF.MSUF_Auras3 = nil
assert(Nav.SelectControl(targetMover), "the mover could not be selected again")
for index = #nudges, 1, -1 do nudges[index] = nil end
-- The toolbar's frame list has no name and closes on mouse-out; the pad holds it.
local framePicker = Child("Frame", UIParent, 820, 800, 190, 120)
framePicker:Hide()
local pickedKey
local pickerRow = Child("Button", framePicker, 823, 890, 184, 24)
pickerRow.scripts.OnClick = function() pickedKey = "target"; framePicker:Hide() end
MSUF_EM2.HUDDock = { framePicker = framePicker }
framePicker:Show()
tickers[1].callback()
assert(Nav.GetSelection() == pickerRow and framePicker._msufPadHeld == true,
    "the toolbar's frame list did not take the pad or was not marked held")
Press("PAD1")
assert(pickedKey == "target" and Nav.GetSelection() == targetMover, "A did not pick from the toolbar's frame list")
local positionPopup = Child("Frame", UIParent, 820, 600, 356, 326)
local dockTop = Child("Button", positionPopup, 900, 850, 60, 24)
MSUF_EM2_HUD_PositionPopup = positionPopup
tickers[1].callback()
assert(Nav.GetSelection() == dockTop, "the toolbar's position popup did not take the pad")
Press("PAD2")
assert(not positionPopup:IsShown() and Nav.GetSelection() == targetMover, "B did not close the position popup")
-- Start brings the menu back; LT/RT bring the next open MSUF window to the front and back again.
Press("PADFORWARD")
assert(menuWindow:IsShown() and not minimizedBar:IsShown() and Nav.GetSelection() == menuButton
    and prompts["Switch window"] == "PADLTRIGGER/PADRTRIGGER", "Start did not bring the menu back")
Press("PADRTRIGGER")
assert(Nav.GetSelection() == targetMover, "RT did not return to Edit Mode on its last selection")
Press("PADLTRIGGER")
assert(Nav.GetSelection() == menuButton, "LT did not bring the menu window back")
Press("PADRTRIGGER")
assert(Nav.GetSelection() == targetMover, "RT did not cycle back to Edit Mode")
assert(input.padStick == true, "a mover did not take the right stick")
input.scripts.OnGamePadStick(input, "Camera", 1, 0)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnGamePadStick(input, "Camera", 0, 0)
assert(selections[1] == "target:gamepad" and stateKey == "target" and nudges[1]
    and nudges[1][1] == "target" and nudges[1][2] > 0 and nudges[1][3] == 0,
    "the stick did not select the mover and nudge it through Edit Mode")
-- Y on a mover: the D-pad nudges by 1 px and LB/RB step to the next mover.
Press("PAD4")
Press("PADDUP")
assert(nudges[2] and nudges[2][2] == 0 and nudges[2][3] == 1, "the D-pad did not nudge the mover by 1 px")
Press("PADLSHOULDER")
assert(Nav.GetSelection() == playerMover and prompts.moving, "LB did not step to the previous mover")
Press("PADRSHOULDER")
assert(Nav.GetSelection() == targetMover, "RB did not step to the next mover")
Press("PAD2")
assert(not prompts.moving and moverParent:IsShown(), "B did not leave move mode before Edit Mode")
Press("PAD1")
assert(emPopup:IsShown() and Nav.GetSelection() == xBox, "A on a mover did not hand the pad to its popup")
input.scripts.OnGamePadStick(input, "Camera", 0, -1)
input.scripts.OnUpdate(input, 0.1)
input.scripts.OnGamePadStick(input, "Camera", 0, 0)
assert(nudges[3] and nudges[3][1] == "target" and nudges[3][3] < 0, "the stick did not nudge the popup's element")
-- A popup dropdown (Quick.MenuButtonAt) opens its list on UIParent: the list
-- takes the pad and is marked held so its hover-close leaves it open.
local dropButton = Child("Button", emPopup, 320, 380, 120, 24)
local list = Child("Frame", UIParent, 320, 250, 120, 120)
list:Hide()
local choice = Child("Button", list, 324, 330, 110, 20)
local chosen = 0
choice.scripts.OnClick = function() chosen = chosen + 1; list:Hide() end
dropButton._menu = list
dropButton.scripts.OnClick = function() list:Show() end
Press("PADDDOWN")
assert(Nav.GetSelection() == dropButton, "down did not reach the popup dropdown")
Press("PAD1")
assert(list:IsShown() and list._msufPadHeld == true and Nav.GetSelection() == choice,
    "the dropdown list did not take the pad or was not marked held")
Press("PAD2")
assert(not list:IsShown() and list._msufPadHeld == nil and Nav.GetSelection() == dropButton,
    "B did not close the dropdown list back onto its button")
Press("PAD1"); Press("PAD1")
assert(chosen == 1 and not list:IsShown() and Nav.GetSelection() == dropButton, "A did not pick the list row")
Press("PAD2")
assert(not emPopup:IsShown() and Nav.GetSelection() == targetMover, "B did not close the popup back onto its mover")
Press("PAD2")
assert(exits[1] == "hud_exit" and Nav.GetSelection() == menuButton,
    "B did not leave Edit Mode like the HUD's Done and return to the open menu")
-- Edit Mode started again from the menu: the menu comes back when it ends.
moverParent:Show()
tickers[1].callback()
assert(Nav.GetSelection() == playerMover and not menuWindow:IsShown() and minimizedBar:IsShown(),
    "the menu did not wait on its title bar for the second Edit Mode")
Press("PAD2")
local pending = timers
timers = {}
for index = 1, #pending do pending[index]() end
assert(exits[2] == "hud_exit" and menuWindow:IsShown() and not minimizedBar:IsShown()
    and Nav.GetSelection() == menuButton, "the menu did not come back when Edit Mode ended")
menuWindow:Hide()
tickers[1].callback()
assert(not Nav.IsCapturing(), "the pad was kept after every MSUF window closed")

-- B closes an attached window and the pad goes back to the game.
window:Show()
Nav.Activate(window)
Press("PAD2")
assert(closed == 1 and not window:IsShown() and not Nav.IsCapturing() and input.padButtons == false,
    "B did not close the window and release the pad")
print("Forever pad navigation: no Blizzard focus manager, hints, D-pad, A/X/B/Y, shoulders, triggers, sliders, "
    .. "keyboard layouts, stick nudge and scroll, tooltips, previews, popups, Edit Mode and release passed")
