local path = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_ContextColorPicker.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()

local function Has(needle, message)
    assert(source:find(needle, 1, true), message)
end

Has("local SIMPLE_WIDTH, SIMPLE_HEIGHT = 330, 330", "mock-up-proportioned compact picker dimensions missing")
Has("local ADVANCED_WIDTH, ADVANCED_HEIGHT = 610, 420", "mock-up-proportioned advanced picker dimensions missing")
Has("local PICKER_PAD, PICKER_GAP = 16, 10", "mock-up spacing grid missing")
Has("local LEFT_CARD_WIDTH = 216", "mock-up card split missing")
Has("local PICKER_REFERENCE_SCALE = 0.915", "reference-size correction missing")
Has("local ACTION_SIDE_PAD, ACTION_GAP = 8, 10", "footer action spacing contract missing")
Has("local SIMPLE_MORE_WIDTH, SIMPLE_CANCEL_WIDTH, SIMPLE_DONE_WIDTH = 102, 72, 88",
    "compact footer buttons lost their non-overlapping widths")
Has("self.advancedCard:SetShown(advanced)", "advanced tools are not gated as one progressive section")
Has('self.more:SetText(Tr(advanced and "Back to controls" or "More Options"))',
    "advanced disclosure button does not communicate both states")
Has("self.advanced = false", "picker must always open in the simple state")
Has('self.title:SetText(Tr("MSUF Color Picker") .. (visibleScope ~= "" and (" · " .. visibleScope) or ""))',
    "picker cannot show a compact visible scope tag")
Has("function W.OpenColorContextPicker(contextTitle, owners, contextNote, initialOwner, onFinish, scopeTag)",
    "public color-picker bridge does not carry the visible scope tag")

Has('M.CreateWindowControlButton(panel, "close")', "picker close control does not use the MSUF window style")
assert(not source:find('"maximize"', 1, true), "picker must not expose a maximize title control")
assert(not source:find('"minimize"', 1, true), "picker must not expose a minimize title control")
assert(not source:find("M.CreateWindowControlGroup(panel", 1, true),
    "close-only picker must not build the three-segment title group")
Has('Font(advancedCard, "GameFontNormalSmall", "Palette"', "palette title must live in Advanced")
Has('{ "quick", "Quick" }, { "class", "Class" }, { "recent", "Recent" }, { "saved", "Saved" }',
    "palette tabs are incomplete")
Has('local opacity = OpacityDisplay(wheelCard, 160)', "opacity control is missing from the redesigned picker")
Has('local frame = CreateFrame("Slider", nil, parent)', "opacity control is not a native draggable slider")
Has("frame:SetMinMaxValues(0, 1)", "opacity slider range is not normalized")
Has('opacity:SetScript("OnValueChanged"', "opacity slider is not wired to live changes")
Has("function panel:ApplyOpacity(alpha)", "picker has no alpha-channel apply path")
Has("self.originals[owner] = { r, g, b, OwnerOpacity(owner), OwnerState(owner) }",
    "cancel state does not retain alpha and structural override state")
Has('value[5] ~= nil and type(owner._msuf2RestoreColorState) == "function"',
    "cancel does not restore structural color override state")
assert(not source:find("MSUF color settings are fully opaque RGB colors.", 1, true),
    "picker still describes its opacity control as a non-functional RGB display")
Has('Input(advancedCard, 40, true)', "RGB precision fields must live in Advanced")
Has('Input(advancedCard, 64, false)', "HEX precision field must live in Advanced")
Has('Swatch(advancedCard, 24', "palette swatches must use the compact mock-up grid")
Has('T.ApplyButtonRole(done, "primary")', "Apply Color must be the primary action")
Has('local selector = T.Button(panel, "", SIMPLE_WIDTH - PICKER_PAD * 2, 32)',
    "target selector must reuse the shared MSUF menu-button style")
Has('selectorArrow:SetTexture(T.media.dropdownChevron)',
    "target selector must reuse the shared MSUF dropdown chevron")
Has('W.OpenDropdown(self.selector, values, self.owner, function(owner)',
    "target selector does not use the functional shared MSUF dropdown")
assert(not source:find("local function FlatButton", 1, true),
    "picker still carries a private dropdown-button renderer")
assert(not source:find("local function ContextRow", 1, true),
    "picker still allocates a private dropdown row pool")
Has('local editingLabel = Font(selector, "GameFontHighlightSmall", "Editing"',
    "target selector must keep Editing separate from the target label")
Has('local selectorColor = ColorChip(selector, 14, 14)',
    "target selector must place the color after its separator")
Has('local info = T.Button(panel, "i", 18, 18, { noSearch = true })',
    "context help must live behind the compact MSUF info control")
Has('self.infoButton._msuf2PickerInfoText = detail',
    "picker context help is not routed to the info tooltip")
Has('info:RegisterForClicks("LeftButtonUp")',
    "picker info control does not explicitly accept clicks")
Has('info:SetScript("OnClick", function(self)',
    "picker info control has no click-toggle behavior")
Has('self._msuf2PickerInfoPinned = not self._msuf2PickerInfoPinned',
    "picker info tooltip cannot be pinned and closed by click")
Has("button:SetFrameLevel(level + 1)",
    "picker info control is still below the draggable title overlay")
Has("RaisePickerInfo(self)",
    "picker info mouse priority is not restored after popup priority changes")
assert(not source:find('self.note:SetText(context .. "  -  " .. detail)', 1, true),
    "picker still renders the long context note inline where it can overlap the selector")
Has("RefreshPickerFonts(self)",
    "cached picker does not refresh Expressway/custom menu fonts when it opens")
Has('type(T.RefreshMenuFonts) == "function"',
    "picker font refresh does not use the shared safe MSUF typography path")
Has("self:SetScale(PickerMenuScale())", "picker must follow the effective MSUF menu scale")
Has('local original = ColorField(panel, 144, 22)', "Original preview must use the flat mock-up field")
Has('local current = ColorField(panel, 144, 22)', "Current preview must use the flat mock-up field")
Has('fill.L:SetWidth(4)', "preview fields must use the low-radius mock-up caps")
Has('local tab = T.Button(advancedCard, Tr(spec[2]), 78, 20)',
    "palette tabs must reuse the shared MSUF menu-button style")
Has('local more = T.Button(actionBar, Tr("Advanced"), 110, 26)',
    "Back/More action must reuse the shared MSUF menu-button style")
Has('local cancel = T.Button(actionBar, Tr("Cancel"), 98, 26)',
    "Cancel action must reuse the shared MSUF menu-button style")
Has('local done = T.Button(actionBar, Tr("Apply Color"), 94, 26)',
    "Apply action must reuse the shared MSUF menu-button style")
Has('self.more:SetSize(advanced and ADVANCED_MORE_WIDTH or SIMPLE_MORE_WIDTH, 26)',
    "More/Back action does not switch to its compact width")
Has('self.cancel:SetSize(advanced and ADVANCED_CANCEL_WIDTH or SIMPLE_CANCEL_WIDTH, 26)',
    "Cancel action does not switch to its compact width")
Has('self.done:SetSize(advanced and ADVANCED_DONE_WIDTH or SIMPLE_DONE_WIDTH, 26)',
    "Apply action does not switch to its compact width")
Has('self.cancel:ClearAllPoints(); self.cancel:SetPoint("RIGHT", self.done, "LEFT", -ACTION_GAP, 0)',
    "footer actions do not preserve their gap after resizing")
Has('local copy = T.Button(advancedCard, Tr("Copy"), 54, 22)',
    "Copy action must reuse the shared MSUF menu-button style")
Has('local save = T.Button(advancedCard, Tr("Save"), 54, 22)',
    "Save action must reuse the shared MSUF menu-button style")
Has('valueThumb:SetAlpha(0.001)', "native side-arrow value thumb must be replaced")
Has('valueHandle:SetSize(31, 6)', "brightness slider must use the mock-up handle")
Has('AddFlatButtonIcon(copy, "copy")', "Copy action icon missing")
Has('AddFlatButtonIcon(save, "save")', "Save action icon missing")
Has("function panel:ClampPosition()", "picker must re-clamp after compact/advanced resizing")
Has('local inputY = -193', "precision controls must share the compact mock-up row")
Has('local checkerCount = max(1, math.ceil(innerWidth / checkerWidth) + 1)',
    "opacity preview must cover its clipped checkerboard host")
Has("local checkerScale = 0.75", "opacity checker cells must match the reference density")
Has('checker:SetAtlas("colorpicker-checkerboard", true)',
    "opacity preview must preserve Blizzard's native checker size")
Has("checkerHost:SetClipsChildren(true)", "native checker tiles must be clipped to the opacity field")
Has("panel.paletteLookups = { quick = {}, class = {}, recent = {}, saved = {} }",
    "palette selection must use constant-time color lookups")
Has("if not self._advancedChildLayout then", "advanced child geometry must be laid out only once")
Has("local function CreateCircularSwatchParts", "palette swatches must use the low-region circular renderer")
Has('edgeMask:SetAllPoints(edge); edgeMask:SetAtlas("CircleMask")',
    "palette edge must use Blizzard's scalable circular mask")
Has('fillMask:SetAllPoints(fill); fillMask:SetAtlas("CircleMask")',
    "palette fill must have its own correctly scaled circular mask")
assert(not source:find('SetScript("OnUpdate"', 1, true), "picker redesign must not add recurring OnUpdate work")
assert(not source:find("colorBands", 1, true), "opacity preview recreated the old multi-texture gradient")

local compactActionWidth = 102 + 72 + 88 + 2 * 10
local compactActionSpace = 330 - 2 * 16 - 2 * 8
assert(compactActionWidth <= compactActionSpace,
    "compact footer actions exceed their available width")

local swatchStart = assert(source:find("local function Swatch", 1, true))
local swatchEnd = assert(source:find("local function ApplyOwner", swatchStart, true))
local swatchSource = source:sub(swatchStart, swatchEnd - 1)
assert(not swatchSource:find("CreateTrueColorPill", 1, true),
    "palette swatches still allocate multi-part pill regions")

local applyStart = assert(source:find("function panel:Apply", 1, true))
local applyEnd = assert(source:find("function panel:Finish", applyStart, true))
local applySource = source:sub(applyStart, applyEnd - 1)
assert(applySource:find("self:RefreshColorReadout", 1, true), "color drag lost its direct readout refresh")
assert(not applySource:find("self:Refresh()", 1, true), "color drag still triggers the full picker refresh")
assert(not applySource:find("RefreshPalettes", 1, true), "color drag still scans palette controls")
assert(not applySource:find("RefreshRows", 1, true), "color drag still scans context rows")

local controlsPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_WindowControls.lua"
local controlsHandle = assert(io.open(controlsPath, "rb"))
local controlsSource = controlsHandle:read("*a")
controlsHandle:close()
assert(controlsSource:find("local WINDOW_CONTROL_LEVEL_OFFSET = 16", 1, true),
    "window controls must stay below Menu2 popup priority")
assert(not controlsSource:find("baseLevel + 140", 1, true),
    "window controls can still punch through modal popups")

local widgetsPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua"
local widgetsHandle = assert(io.open(widgetsPath, "rb"))
local widgetsSource = widgetsHandle:read("*a")
widgetsHandle:close()
assert(widgetsSource:find("while contextEntry.ancestorEntry do contextEntry = contextEntry.ancestorEntry end", 1, true),
    "color controls do not resolve their shared contextual owner group")
assert(widgetsSource:find("colorControl._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners", 1, true),
    "color controls do not expose their functional target list")

local dropdownsPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Dropdowns.lua"
local dropdownsHandle = assert(io.open(dropdownsPath, "rb"))
local dropdownsSource = dropdownsHandle:read("*a")
dropdownsHandle:close()
assert(dropdownsSource:find("local function RefreshDropdownMenuFonts()", 1, true),
    "cached picker dropdown cannot refresh Expressway/custom menu fonts")
assert(dropdownsSource:find("RefreshDropdownMenuFonts()", dropdownsSource:find("local function OpenDropdown", 1, true), true),
    "shared picker dropdown does not refresh its current MSUF menu font when opened")
local dropdownFontStart = assert(dropdownsSource:find("local function RefreshDropdownMenuFonts", 1, true))
local dropdownFontEnd = assert(dropdownsSource:find("local function DropdownItemValue", dropdownFontStart, true))
local dropdownFontSource = dropdownsSource:sub(dropdownFontStart, dropdownFontEnd - 1)
assert(not dropdownFontSource:find('SetScript("OnUpdate"', 1, true),
    "dropdown font synchronization added recurring menu work")

local bindingsPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua"
local bindingsHandle = assert(io.open(bindingsPath, "rb"))
local bindingsSource = bindingsHandle:read("*a")
bindingsHandle:close()
assert(bindingsSource:find("colorButton._msuf2GetColorOpacity = function()", 1, true),
    "bound RGBA colors do not expose their alpha channel to the picker")
assert(bindingsSource:find("setRGB(r, g, b, nextAlpha)", 1, true),
    "bound color changes do not preserve or write alpha")

local colorsPath = "MidnightSimpleUnitFrames/Runtime/MSUF_Colors.lua"
local colorsHandle = assert(io.open(colorsPath, "rb"))
local colorsSource = colorsHandle:read("*a")
colorsHandle:close()
assert(colorsSource:find('GetClassBarBgColor() return _getRGBA("classBarBgR", "classBarBgG", "classBarBgB", "classBarBgA"', 1, true),
    "bar background tint API is still RGB-only")
assert(colorsSource:find('_getRGBA("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", "powerBarBgColorA"', 1, true),
    "power background color API is still RGB-only")

local openStart = assert(source:find("function panel:Open", 1, true))
local openEnd = assert(source:find("panel:SetScript(\"OnKeyDown\"", openStart, true))
local openSource = source:sub(openStart, openEnd - 1)
assert(openSource:find("self.advanced = false", 1, true), "Open must reset Advanced before layout")

print("context color picker progressive disclosure smoke: ok")
