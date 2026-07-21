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

local popupPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_TextQuickSettings.lua"
local popup = Read(popupPath)
local global = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Global.lua")
local globalFonts = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
local widgets = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local unitText = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
local unitSections = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local groupText = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local groupPage = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
local classPower = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua")
local menuXML = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2.xml")
    .. Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_AfterUnitPreview.xml")
    .. Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml")

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

-- These explicit-scope adapters are the shared source of truth for the Fonts
-- page and the contextual popup. Their exact UI composition can change while
-- bidirectional synchronization remains contractual.
local adapters = {
    "FontScopeGetFor", "FontScopeSetFor",
    "FontOutlineGetFor", "FontOutlineSetFor",
    "FontShadowMetricsFor",
    "FontTextColorModeGetFor", "FontTextColorModeSetFor",
}
for _, name in ipairs(adapters) do
    Require(global, name, "global Fonts model does not define/export explicit-scope adapter")
    Require(popup, name, "quick settings bypass the explicit-scope Fonts model")
end

-- Relevant controls mirrored from Fonts. Prefer stable DB/model identifiers
-- over translated labels so localization changes do not weaken this contract.
local fontContracts = {
    { "FontValues", "font family" },
    { "FontOutlineGetFor", "outline" },
    { "fontMonochrome", "rendering" },
    { "textBackdrop", "shadow" },
    { "fontTextAlpha", "text opacity" },
    { "fontBaselineOffset", "baseline" },
}
for _, contract in ipairs(fontContracts) do
    Require(popup, contract[1], "quick settings omit Fonts option " .. contract[2])
end

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
Require(popup, "settings.modeScope or settings.colorScope",
    "quick settings cannot separate the shared font scope from a frame-owned color mode")
Require(popup, "settings.colorModeValues", "quick settings omit custom color-mode preview values")
Require(popup, "settings.getColorMode", "quick settings omit custom color-mode synchronization getter")
Require(popup, "settings.setColorMode", "quick settings omit custom color-mode synchronization setter")
Require(popup, "CurrentCapabilities", "quick settings omit runtime capability filtering")
Require(popup, 'HasCapability("baseline", true)',
    "quick settings cannot hide unsupported baseline controls")
Require(popup, "local colorsVisible = colorsAllowed and targetCount > 0",
    "quick settings leave an irrelevant zero-color action visible")
Require(popup, "self:SetHeight(max(214, -y + (colorsVisible and 40 or 16)))",
    "quick settings do not shrink around their relevant controls")
Require(popup, "local modeScope = CurrentModeScope()",
    "quick settings do not derive color-mode enablement from its owning scope")
Require(popup, "HasCustomColorMode() or modeOverride",
    "independent custom color modes are incorrectly gated by a font override")
local enablePass = assert(popup:find("for i = 1, #scopedControls do SetEnabled", 1, true),
    "quick-settings scoped enable pass is missing")
local accentPass = assert(popup:find("self.colorMode._msuf2Title:SetTextColor", enablePass, true),
    "Color mode is not highlighted after enabled-state styling")
assert(accentPass > enablePass, "Color mode highlight is overwritten by enabled-state styling")
assert(Has(popup, "OpenContextColors") or Has(popup, "OpenColorContextPicker"),
    "quick settings do not hand the Colors action to the existing color picker")
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
