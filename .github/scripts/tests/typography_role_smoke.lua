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
local standard = 'Fonts\\FRIZQT__.TTF'
local custom = 'Interface\\AddOns\\SharedMedia_Custom\\My Font.ttf'

AssertEqual(UI.FontSize('supporting'), 11, 'supporting size')
AssertEqual(UI.FontSize('control'), 13, 'control size')
AssertEqual(UI.FontSize('accordion'), 15, 'accordion size')
AssertEqual(UI.FontSize('section'), 15, 'section size')
AssertEqual(UI.ResolveRoleFontPath(regular, 'accordion'), regular, 'accordion regular weight')
AssertEqual(UI.ResolveRoleFontPath(standard, 'accordion'), standard, 'accordion standard font preservation')
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

-- A SetFont success with provisional live metrics must stay pending without
-- retrying from ordinary unit events. The coordinator's next epoch owns the
-- second real SetFont; once settled, the tuple cache returns to zero work.
local previousMarkFontFailed = _G.MSUF_MarkFontApplyFailed
local previousFontEpoch = _G.MSUF_FontApplyEpoch
_G.MSUF_FontApplyEpoch = 100
local markedFontFailures = 0
_G.MSUF_MarkFontApplyFailed = function()
    markedFontFailures = markedFontFailures + 1
end
spec.font = regular
local coldUnit = FontString()
coldUnit.setCalls, coldUnit.getCalls = 0, 0
function coldUnit:GetFont()
    self.getCalls = self.getCalls + 1
    return self.font, self.size, self.flags
end
function coldUnit:SetFont(font, size, flags)
    self.setCalls = self.setCalls + 1
    self.font, self.flags = font, flags
    self.size = self.setCalls == 1 and (size + 1) or size
    return true
end
AssertEqual(SetUnitFont(coldUnit, spec, 14, 'name'), false, 'cold unit provisional metrics')
AssertEqual(coldUnit._msufFontPending, true, 'cold unit pending marker')
AssertEqual(coldUnit._msufFont, semibold, 'cold unit bounded-attempt tuple cache')
AssertEqual(coldUnit._msufFontAttemptEpoch, 100, 'cold unit attempt epoch')
AssertEqual(coldUnit._msufFontEpoch, nil, 'cold unit success epoch')
AssertEqual(markedFontFailures, 1, 'cold unit failure signal')
local pendingSetCalls, pendingGetCalls = coldUnit.setCalls, coldUnit.getCalls
AssertEqual(SetUnitFont(coldUnit, spec, 14, 'name'), false, 'cold unit same-epoch pending result')
AssertEqual(coldUnit.setCalls, pendingSetCalls, 'cold unit same-epoch SetFont calls')
AssertEqual(coldUnit.getCalls, pendingGetCalls, 'cold unit same-epoch GetFont calls')
_G.MSUF_FontApplyEpoch = 101
AssertEqual(SetUnitFont(coldUnit, spec, 14, 'name'), true, 'cold unit retry')
AssertEqual(coldUnit.font, semibold, 'cold unit retry path')
AssertEqual(coldUnit.size, 14, 'cold unit retry size')
AssertEqual(coldUnit._msufFontPending, nil, 'cold unit pending cleared')
AssertEqual(coldUnit._msufFontEpoch, 101, 'cold unit settled epoch')
local settledUnitSetCalls, settledUnitGetCalls = coldUnit.setCalls, coldUnit.getCalls
AssertEqual(SetUnitFont(coldUnit, spec, 14, 'name'), true, 'cold unit settled fast path')
AssertEqual(coldUnit.setCalls, settledUnitSetCalls, 'cold unit settled SetFont calls')
AssertEqual(coldUnit.getCalls, settledUnitGetCalls, 'cold unit settled GetFont calls')
_G.MSUF_MarkFontApplyFailed = previousMarkFontFailed
_G.MSUF_FontApplyEpoch = previousFontEpoch

local layoutFile = assert(io.open('MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua', 'rb'))
local layoutSource = layoutFile:read('*a')
layoutFile:close()
local _, epochGuardCount = layoutSource:gsub('and frame%._msufTextFontAttemptEpoch == fontEpoch', '')
AssertEqual(epochGuardCount, 2, 'text layout epoch fast-path guards')
assert(layoutSource:find('if frame._msufTextFontAttemptEpoch ~= fontEpoch then', 1, true),
    'text layout epoch invalidation missing')
assert(layoutSource:find('frame._msufTextFontPending = fontsReady and nil or true', 1, true),
    'text layout pending result assignment missing')

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
local previousCreateFrame = _G.CreateFrame
local previousResolveSafeFontPath = _G.MSUF_ResolveSafeFontPath
local safeFontResolveCalls = 0
_G.MSUF_ResolveSafeFontPath = function(path)
    safeFontResolveCalls = safeFontResolveCalls + 1
    return path
end
_G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript() end
    function frame:UnregisterAllEvents() end
    return frame
end
assert(loadfile('MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua'))(
    'MidnightSimpleUnitFrames', root)
assert(loadfile('MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Theme.lua'))(
    'MidnightSimpleUnitFrames', root)
_G.CreateFrame = previousCreateFrame

_G.MSUF_DB.general.menuFontKey = regular
M.Theme.ClearMenuFontCache()
local cacheA, cacheB = FontString(), FontString()
local resolveStart = safeFontResolveCalls
M.Theme.StyleFontString(cacheA, nil, 0, 'body')
M.Theme.StyleFontString(cacheB, nil, 0, 'body')
AssertEqual(safeFontResolveCalls - resolveStart, 1, 'same menu font tuple resolves once')
M.Theme.RefreshMenuFonts(cacheB, true, true)
AssertEqual(safeFontResolveCalls - resolveStart, 1, 'visible font settle preserves resolved path cache')
M.Theme.ClearMenuFontCache()
M.Theme.StyleFontString(FontString(), nil, 0, 'body')
AssertEqual(safeFontResolveCalls - resolveStart, 2, 'explicit font cache clear re-resolves')

local accordionTitle = FontString()
M.Theme.StyleFontString(accordionTitle, nil, 0, 'accordion')
AssertEqual(accordionTitle.font, regular, 'configured accordion font face')
AssertEqual(accordionTitle.size, 15, 'configured accordion font size')
local widgetsFile = assert(io.open('MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua', 'rb'))
local widgetsSource = widgetsFile:read('*a')
widgetsFile:close()
assert(widgetsSource:find('T.Font(header, "GameFontNormal", Tr(title or ""), T.colors.text, "accordion")', 1, true),
    'collapsible title must use the cold-start-safe accordion role')

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

_G.MSUF_ResolveSafeFontPath = previousResolveSafeFontPath

print('typography_role_smoke: ok')
