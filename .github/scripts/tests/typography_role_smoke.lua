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

-- Menu2 must survive the real-client edge where the first custom semibold
-- SetFont call returns without making that face renderable. The visible-page
-- settle retries once; until then the inherited font must remain readable.
local M = {}
root.MSUF2 = M
function M.Lines(text)
    return tostring(text or ''):gmatch('[^\r\n]+')
end
function M.WordList(text)
    local out = {}
    for word in tostring(text or ''):gmatch('%S+') do out[word] = true end
    return out
end
function M.AssignNamedValues(target, names, ...)
    local values, index = { ... }, 0
    for name in tostring(names or ''):gmatch('%S+') do
        index = index + 1
        target[name] = values[index]
    end
end
assert(loadfile('MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua'))(
    'MidnightSimpleUnitFrames', root)
assert(loadfile('MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Theme.lua'))(
    'MidnightSimpleUnitFrames', root)

local inherited = 'Fonts\\FRIZQT__.TTF'
_G.MSUF_DB.general.menuFontKey = regular
local cold = FontString()
cold.font, cold.size, cold.flags = inherited, 12, ''
cold._msuf2FontOriginal = { font = inherited, size = 12, flags = '' }
cold._msuf2FontRole = 'section'
cold.text, cold.stringWidth, cold.semiboldAttempts = 'Frame Basics', 96, 0
function cold:GetText() return self.text end
function cold:GetStringWidth() return self.stringWidth end
function cold:SetFont(font, size, flags)
    if font == semibold then
        self.semiboldAttempts = self.semiboldAttempts + 1
        if self.semiboldAttempts == 1 then return true end -- accepted, but not actually applied
    end
    self.font, self.size, self.flags = font, size, flags
    self.stringWidth = 96
    return true
end

M.Theme.RefreshMenuFonts(cold, true)
AssertEqual(cold.font, inherited, 'cold semibold fallback font')
AssertEqual(cold.semiboldAttempts, 1, 'cold semibold first attempt')
M.Theme.RefreshMenuFonts(cold, true)
AssertEqual(cold.font, semibold, 'visible settle semibold retry')
AssertEqual(cold.size, 15, 'visible settle section size')
local attemptsAfterSuccess = cold.semiboldAttempts
M.Theme.RefreshMenuFonts(cold)
AssertEqual(cold.semiboldAttempts, attemptsAfterSuccess, 'cached font refresh')

local blank = FontString()
blank.font, blank.size, blank.flags = inherited, 12, ''
blank._msuf2FontOriginal = { font = inherited, size = 12, flags = '' }
blank._msuf2FontRole = 'section'
blank.text, blank.stringWidth = 'Auras', 80
function blank:GetText() return self.text end
function blank:GetStringWidth() return self.stringWidth end
function blank:SetFont(font, size, flags)
    self.font, self.size, self.flags = font, size, flags
    self.stringWidth = font == semibold and 0 or 80
    return true
end
M.Theme.RefreshMenuFonts(blank, true)
AssertEqual(blank.font, inherited, 'zero-width semibold fallback font')
AssertEqual(blank.stringWidth, 80, 'zero-width semibold fallback metrics')

print('typography_role_smoke: ok')
