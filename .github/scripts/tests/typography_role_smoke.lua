local function AssertEqual(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %q, got %q'):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local root = {}
assert(loadfile('MidnightSimpleUnitFrames/Shell/UI/MSUF_Widgets.lua'))('MidnightSimpleUnitFrames', root)
local UI = assert(root.UI, 'shared UI missing')

local regular = 'Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf'
local semibold = 'Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf'
local custom = 'Interface\\AddOns\\SharedMedia_Custom\\My Font.ttf'

AssertEqual(UI.FontSize('supporting'), 11, 'supporting size')
AssertEqual(UI.FontSize('control'), 13, 'control size')
AssertEqual(UI.FontSize('section'), 15, 'section size')
AssertEqual(UI.ResolveRoleFontPath(regular, 'section'), semibold, 'section weight')
AssertEqual(UI.ResolveRoleFontPath(regular, 'control'), regular, 'control weight')
AssertEqual(UI.ResolveRoleFontPath(custom, 'section'), custom, 'custom font preservation')

local function FontString()
    local fs = { font = 'Fonts\\FRIZQT__.TTF', size = 12, flags = '' }
    function fs:GetFont() return self.font, self.size, self.flags end
    function fs:SetFont(font, size, flags)
        self.font, self.size, self.flags = font, size, flags
        return true
    end
    function fs:SetTextColor() end
    function fs:SetShadowColor() end
    function fs:SetShadowOffset() end
    return fs
end

_G.MSUF_DB = { general = { menuFontKey = regular } }
local menuHeading = FontString()
UI.ApplyFontRole(menuHeading, 'heading', menuHeading.font, '')
AssertEqual(menuHeading.font, semibold, 'configured heading font')
AssertEqual(menuHeading.size, 17, 'configured heading size')

_G.MSUF_DB.general.menuFontKey = custom
local customHeading = FontString()
UI.ApplyFontRole(customHeading, 'heading', customHeading.font, '')
AssertEqual(customHeading.font, custom, 'configured custom heading font')

local common = {
    UF = {},
    type = type,
    tonumber = tonumber,
    format = string.format,
    abs = math.abs,
    floor = math.floor,
    max = math.max,
}
local unitRoot = { UFBarTextCommon = common, Secrets = {} }
assert(loadfile('MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua'))(
    'MidnightSimpleUnitFrames', unitRoot)
local SetUnitFont = assert(unitRoot.UFText and unitRoot.UFText.SetFont, 'unit font setter missing')

local spec = {
    font = regular,
    fontFlags = 'OUTLINE',
    fontShadow = false,
    textColor = { r = 1, g = 1, b = 1, a = 1 },
}
local name = FontString()
SetUnitFont(name, spec, 14, 'name')
AssertEqual(name.font, semibold, 'unit name weight')

local compactHealth = FontString()
SetUnitFont(compactHealth, spec, 10, 'health')
AssertEqual(compactHealth.font, semibold, 'compact health weight')

local largeHealth = FontString()
SetUnitFont(largeHealth, spec, 11, 'health')
AssertEqual(largeHealth.font, regular, 'large health weight')

local customName = FontString()
spec.font = custom
SetUnitFont(customName, spec, 10, 'name')
AssertEqual(customName.font, custom, 'custom unit font preservation')

print('typography_role_smoke: ok')
