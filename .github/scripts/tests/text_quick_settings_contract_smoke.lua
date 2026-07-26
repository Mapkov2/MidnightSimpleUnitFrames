local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing contract source: " .. path)
    local source = file:read("*a")
    file:close()
    return source
end

local function Has(source, needle)
    return source:find(needle, 1, true) ~= nil
end

local function Require(source, needle, message)
    assert(Has(source, needle), message .. ": " .. needle)
end

local function Count(source, needle)
    local total, cursor = 0, 1
    while true do
        local found = source:find(needle, cursor, true)
        if not found then return total end
        total, cursor = total + 1, found + #needle
    end
end

local popupPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_TextQuickSettings.lua"
local popup = Read(popupPath)
local global = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Global.lua")
local globalFonts = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local unitText = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
local unitSections = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local groupText = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local groupPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
local classPower = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua")
local castbars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
local menuXML = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2.xml")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_AfterUnitPreview.xml")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml")

-- The popup is built only when the card-local entry point is clicked, then
-- reused. The stable marker makes that lifecycle reviewable without coupling
-- this smoke to one particular local factory name.
Require(popup, "TEXT_QUICK_SETTINGS", "quick-settings lifecycle marker is missing")
Require(popup, "W.OpenTextQuickSettings", "quick-settings public entry point is missing")
Require(popup, "M.CreateMenuPopupPanel", "quick settings do not use the MSUF popup surface")
local singleton = popup:match("local%s+([%w_]*[Pp]opup[%w_]*)")
assert(singleton, "quick settings do not retain a local singleton popup")
assert(Has(popup, "if " .. singleton .. " then") or Has(popup, "if not " .. singleton .. " then")
        or Has(popup, singleton .. " = " .. singleton .. " or"),
    "quick settings do not visibly reuse their singleton: " .. singleton)
local factory
for _, candidate in ipairs({ "EnsurePopup", "CreatePopup", "GetPopup" }) do
    if Has(popup, "function " .. candidate) then factory = candidate; break end
end
assert(factory and Count(popup, factory) >= 2,
    "quick settings do not lazily invoke a popup factory from their open path")
Require(menuXML, "MSUF_Menu2_TextQuickSettings.lua", "quick-settings module is not loaded by Menu2")

for _, forbidden in ipairs({
    "OnUpdate", "RegisterEvent", "RegisterUnitEvent", "C_Timer",
    "NewTicker", "NewTimer",
}) do
    assert(not Has(popup, forbidden), "quick settings add recurring menu work: " .. forbidden)
end

-- Only the Text Colors model is shared with the Fonts page. Typography belongs
-- exclusively to the Fonts page and must never leak into an RGB popup.
local adapters = {
    "FontTextColorModeGetFor", "FontTextColorModeSetFor",
}
for _, name in ipairs(adapters) do
    Require(global, name, "global Fonts model does not define/export explicit-scope adapter")
    Require(popup, name, "quick settings bypass the explicit-scope Fonts model")
end

for _, forbidden in ipairs({
    "FontValues", "FontOutlineGetFor", "FontOutlineSetFor", "FontShadowMetricsFor",
    "fontMonochrome", "textBackdrop", "fontTextAlpha", "fontBaselineOffset",
    'W.Segment(popup, "Outline"', 'W.Segment(popup, "Rendering"',
    'W.Segment(popup, "Text shadow"', 'W.Segment(popup, "Text opacity"',
    'W.Dropdown(popup, "Font family', 'W.Dropdown(popup, "Baseline"',
    'W.Dropdown(popup, "Shadow opacity"', 'W.Segment(popup, "Shadow distance"',
}) do
    assert(not Has(popup, forbidden), "Text Colors popup exposes forbidden typography: " .. forbidden)
end

Require(popup, 'Tr("Text Colors")', "contextual popup is not identified as Text Colors only")
Require(popup, "FontTextColorModeGetFor", "contextual text color mode getter is missing")
Require(popup, "FontTextColorModeSetFor", "contextual text color mode setter is missing")
Require(globalFonts, "GP.FontTextColorValuesFor = FontTextColorValuesFor",
    "Fonts page does not export its color-mode preview values")
Require(globalFonts, "swatchColor = function() return ConfiguredFontColorPreview(scope) end",
    "Fonts color-mode values lost their scope-aware default-color preview")
Require(globalFonts, 'getFor(scope, "useGlobalFontColor", true) == false',
    "Fonts default-color preview ignores a local Group font color")
Require(globalFonts, "swatchColor = CurrentHealthGradientPreview",
    "Fonts color-mode values lost their health preview")
Require(popup, "GP.FontTextColorValuesFor(CurrentModeScope(), modeKind)",
    "quick settings do not reuse the Fonts menu color previews")
for _, label in ipairs({
    "Player Name Color", "NPC / Boss Name Color", "Group Name Color",
    "HP Text Color", "Power Text Color",
}) do
    Require(popup, label, "quick settings omit the scope-aware Fonts color label")
end
Require(popup, "CurrentColorModeLabel()",
    "quick settings do not apply the context-specific Fonts color label")
Require(popup, "settings.modeScope or settings.colorScope",
    "quick settings cannot separate the shared font scope from a frame-owned color mode")
Require(popup, "settings.colorModeValues", "quick settings omit custom color-mode preview values")
Require(popup, "settings.getColorMode", "quick settings omit custom color-mode synchronization getter")
Require(popup, "settings.setColorMode", "quick settings omit custom color-mode synchronization setter")
Require(popup, "CurrentCapabilities", "quick settings omit runtime capability filtering")
Require(popup, "activeSettings and activeSettings.colorNote",
    "direct text color pickers cannot disclose a shared or global color scope")
Require(popup, "activeSettings and activeSettings.colorScopeTag",
    "direct text color pickers cannot forward a compact visible scope tag")
Require(popup, "local colorsVisible = colorsAllowed and targetCount > 0",
    "quick settings leave an irrelevant zero-color action visible")
Require(popup, "self:SetHeight(-y + (colorsVisible and 40 or 16))",
    "Text Colors popup does not shrink around its color-only controls")
Require(popup, "local modeScope = CurrentModeScope()",
    "quick settings do not derive color-mode enablement from its owning scope")
Require(popup, "HasCustomColorMode() or modeOverride",
    "independent custom color modes are incorrectly gated by a font override")
local enablePass = assert(popup:find("SetEnabled(self.colorMode", 1, true),
    "scope-aware color-mode enable pass is missing")
local accentPass = assert(popup:find("self.colorMode._msuf2Title:SetTextColor", enablePass, true),
    "Color mode is not highlighted after enabled-state styling")
assert(accentPass > enablePass, "Color mode highlight is overwritten by enabled-state styling")
Require(popup, "if modeVisible and self.colorMode._msuf2Title",
    "an inherited but visible color mode loses its requested highlight")
assert(Has(popup, "OpenContextColors") or Has(popup, "OpenColorContextPicker"),
    "quick settings do not hand the Colors action to the existing color picker")
local directAt = assert(popup:find("if not ColorModeVisible() then", 1, true),
    "text without a meaningful mode does not bypass the intermediate popup")
local directPickerAt = assert(popup:find("OpenResolvedTextColors(anchor, activeOptions, ResolveTextColorTargets())", directAt, true),
    "single-purpose text does not open its exact color picker directly")
local popupFactoryAt = assert(popup:find("local popup = EnsurePopup()", directPickerAt, true),
    "color-mode popup is not lazy behind the direct-picker branch")
assert(directPickerAt < popupFactoryAt,
    "spell/aura/status colors construct the intermediate color-mode popup")
Require(castbars, 'colorReferences = { "cast.text" }',
    "Cast Spell Text does not retain its one exact direct-picker target")
Require(popup, "local targets = { DefaultFontTarget(scope, group) }",
    "native text palettes omit their relevant default font color")
Require(popup, "targets[#targets + 1] = NPCColorTarget",
    "NPC name palettes omit their relevant reaction color")
Require(popup, "targets[#targets + 1] = ClassColorTarget",
    "native name/HP palettes omit their relevant class color")
Require(popup, "targets[#targets + 1] = PowerColorTarget",
    "power palettes omit their relevant resource color")
Require(popup, 'Tr(" relevant colors")',
    "quick settings still describe a relevant palette as only the active color")
Require(popup, "textSettings", "quick settings do not consume the contextual descriptor")
Require(popup, 'M.InvalidatePage("opt_fonts")', "quick settings do not invalidate Fonts after synchronizing its scope")

-- The tiny RGB entry remains click-only. Text cards route to the font/color
-- popup; ordinary color-only cards can continue to open the color picker.
Require(widgets, "options.textSettings", "card shortcut does not detect text quick-settings context")
Require(widgets, "W.OpenTextQuickSettings", "card shortcut does not route text contexts to the popup")

Require(unitText, "textSettings = {", "Unit Text cards do not provide quick-settings descriptors")
Require(unitText, "scope = unit", "Unit Text descriptor does not carry its explicit scope")
Require(unitText, "unit = unit", "Unit Text descriptor does not carry its preview unit")
Require(unitText, 'kind = "name"', "Unit Name card does not identify its contextual kind")
Require(unitText, "kind = kind", "Unit HP/Power cards do not identify their contextual kind")

Require(groupText, "textSettings = {", "Group Text cards do not provide quick-settings descriptors")
Require(groupText, "scope = function() return CurrentScope() end", "Group Text descriptor is not scope-live")
Require(groupText, "group = true", "Group Text descriptor does not identify group-frame semantics")
Require(groupText, 'kind = "name"', "Group Name card does not identify its contextual kind")
Require(groupText, "kind = kind", "Group HP/Power cards do not identify their contextual kind")
Require(popup, "W.CloseTextQuickSettings", "quick settings do not expose a scope-change close path")
Require(groupPage, "W.CloseTextQuickSettings()", "Group scope changes leave quick settings stale")

Require(classPower, 'scope = "shared"', "Extra HP text does not reuse the shared font face")
Require(classPower, 'modeScope = "player"', "Extra HP text color mode is not synchronized with Player Fonts")
Require(classPower, "colorMode = mirror", "Extra HP local mode does not hide its irrelevant color-mode control")
Require(classPower, "colors = mirror", "Extra HP local mode does not hide its irrelevant Colors action")
Require(unitSections, "colorModeValues = ToTInlineColorOptions",
    "Inline Text popup does not reuse its menu color-mode dropdown values")
Require(unitSections, "getColorMode = function()", "Inline Text popup does not read the live menu color mode")
Require(unitSections, "setColorMode = function(value)", "Inline Text popup does not write the live menu color mode")

print("text_quick_settings_contract_smoke: ok")
