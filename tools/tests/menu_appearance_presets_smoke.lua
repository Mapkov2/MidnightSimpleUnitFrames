-- Exercise the real Misc dropdown with and without an available external skin.
local root, flavor = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(root .. '/tools/tests/client_world.lua'))()
local world = World.New(root, flavor):Boot()
local failure = world:FirstFailure()
assert(not failure, failure and tostring(failure.message))
local M = world.core.MSUF2
-- Native widget methods not provided by the shared offline stubs.
local createFrame = world.env.CreateFrame
world.env.CreateFrame = function(kind, ...)
    local frame = createFrame(kind, ...)
    if kind == 'CheckButton' then
        frame.SetChecked = function(self, value) self.checked = value end
        frame.GetChecked = function(self) return self.checked end
    elseif kind == 'Slider' then
        frame.SetValueStep = function(self, step) self.step = step end
        frame:SetValue(0)
    elseif kind == 'EditBox' then
        for _, name in ipairs({'SetAutoFocus','SetNumeric','SetTextInsets','SetMaxLetters','ClearFocus','SetCursorPosition','HighlightText'}) do
            frame[name] = function() end
        end
        frame.HasFocus = function() return false end
    end
    return frame
end
local bound = {}
for _, name in ipairs({'BindDropdown', 'BindSlider'}) do
    local original = M[name]
    M[name] = function(ctx, widget, get, set, meta)
        if meta and meta.settingKey then bound[meta.settingKey] = {widget=widget, get=get, set=set} end
        return original(ctx, widget, get, set, meta)
    end
end
M.scrollChild = world.env.CreateFrame('Frame')
M.GetContentMetrics = function() return 900, 800 end
M.BuildPageEntry('opt_misc', true)
local style = assert(bound['general.menuAppearancePreset'], 'appearance dropdown missing')
local accent = assert(bound['general.menuAccent'], 'accent dropdown missing')
local opacity = assert(bound['general.menuBackgroundOpacity'], 'background slider missing')
local choices = type(style.widget.values) == 'function' and style.widget.values() or style.widget.values
local expected = {'classicGlass','midnight','midnightDark','class','ember','jade','violet','custom'}
assert(#choices == #expected, 'appearance dropdown lost its legacy choices')
for i, value in ipairs(expected) do assert(choices[i].value == value, 'missing preset: ' .. value) end
local general = M.GetGeneralDB()
local color = 'cc6633'
general.menuAccentColor = color
local suiteLook, moduleTexture = 'cleanModern', 'Custom texture'
local skinLook = 'cleanModern'
world.env.MapkoSkin = { addonName = 'MSUF_Suite_Skin', Theme = {
    ApplyLook = function(look)
        skinLook, suiteLook, moduleTexture = look, look, 'Preset texture'
        return true
    end,
} }
local function CheckSuite()
    assert(skinLook == 'cleanModern', 'MSUF menu preset changed the global skin')
    assert(suiteLook == 'cleanModern' and moduleTexture == 'Custom texture',
        'MSUF menu preset overwrote Suite module appearance')
end

style.set('classicGlass')
CheckSuite()

-- The current provider is shown as its own choice so a client can select
-- even its default material while MapkoSkin is drawing the menu.
local bridge = {}
local events, onEvent = {}, nil
local client = { ReleaseAll = function() end }
local api = {
    RegisterAddon = function(_, name)
        assert(name == 'MidnightSimpleUnitFrames', 'skin is registered outside MSUF')
        return client
    end,
    IsEnabled = function() return true end,
    GetAppearanceSnapshot = function() return {} end,
}
world.env.MapkoSkin.GetAPI = function() return api end
local env = setmetatable({
    MapkoSkin = world.env.MapkoSkin,
    CreateFrame = function()
        return {
            RegisterEvent = function(_, event) events[event] = true end,
            UnregisterEvent = function(_, event) events[event] = nil end,
            SetScript = function(_, _, callback) onEvent = callback end,
        }
    end,
    InCombatLockdown = function() return false end,
    hooksecurefunc = function() end,
}, { __index = _G })
env._G = env
setfenv(assert(loadfile(root .. '/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua')), env)('', bridge)
env.MSUF_DB = { general = general }
if events.PLAYER_LOGIN then onEvent(nil, 'PLAYER_LOGIN') end
local skin = assert(bridge.MenuSkin)
assert(skin.IsAvailable() and not skin.IsActive(), 'reloading with the native choice activated the external skin')
world.core.MenuSkin = skin
general.mapkoSkinMenus = true
skin.Refresh()
assert(skin.IsActive(), 'MSUF skin switch did not restore external ownership')
assert(style.get() == 'mapkoSkin', 'dropdown reports a native look while the provider owns the menu')
local withSkin = style.widget.values()
assert(#withSkin == #expected + 1 and withSkin[#withSkin].value == 'mapkoSkin',
    'the available provider has no appearance choice')
for _, material in ipairs({'classicGlass', 'midnight', 'midnightDark'}) do
    style.widget._msuf2OnValueChanged(material)
    assert(style.get() == material and general.menuAppearancePreset == material)
    CheckSuite()
    assert(general.mapkoSkinMenus == false, 'MSUF material left the menu under external skin ownership')
    assert(accent.get() == 'midnight' and general.menuAccentTintSurfaces == false)
    for _, value in ipairs({'class','ember','jade','violet','custom'}) do
        style.set(value)
        assert(style.get() == value and accent.get() == value, 'preset does not select: ' .. value)
        assert(general.menuAppearancePreset == material, 'color choice changed the material')
        assert(general.menuAccentColor == color, 'preset discarded the saved custom color')
        CheckSuite()
    end
end
style.set('invalid')
assert(style.get() == 'custom', 'invalid preset overwrote the selection')
accent.set('jade')
assert(style.get() == 'jade', 'separate accent selector does not update appearance selection')
style.set('mapkoSkin')
assert(style.get() == 'mapkoSkin' and general.mapkoSkinMenus == true)
assert(general.menuAppearancePreset == 'midnightDark' and general.menuAccent == 'jade',
    'choosing the external renderer discarded the saved native look')
CheckSuite()
style.set('violet')
assert(style.get() == 'violet' and general.mapkoSkinMenus == false,
    'a menu accent could not take ownership from the external renderer')
CheckSuite()
opacity.set(89)
assert(opacity.get() == 89 and general.menuBackgroundOpacity == 89)
print('PASS ' .. flavor .. ': menu-only materials and accents, renderer ownership, custom color preservation, opacity')

-- Classic Glass uses one contained hit rectangle per caption glyph.
do
    local source = arg[3] or root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_WindowControls.lua"
    local ok, err = world:LoadFile(source, "MidnightSimpleUnitFrames_Options", world.core)
    assert(ok, err)
    local theme = M.Theme
    theme.classicAtlas = true
    world.core.MenuSkin = nil
    local parent = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    local group = M.CreateWindowControlGroup(parent, 3)
    local minimize = M.CreateWindowControlButton(group, "minimize", nil, nil, 1)
    local maximize = M.CreateWindowControlButton(group, "maximize", nil, nil, 2)
    local close = M.CreateWindowControlButton(group, "close", nil, nil, 3)
    assert(not group._msuf2ControlGroupBase and not close._msuf2ControlIcon, "caption still uses the overscanning bitmap")
    local dash = assert(minimize._msuf2CaptionGlyphs, "minimize still uses the failing Line path")
    local square = assert(maximize._msuf2CaptionGlyphs, "maximize still uses the failing Line path")
    local cross = assert(close._msuf2CaptionGlyphs, "close still uses the failing Line path")
    assert(#dash == 1 and #square == 4 and #cross == 1)
    assert(group:GetWidth() == minimize:GetWidth() + maximize:GetWidth() + close:GetWidth(),
        "caption hit rectangles do not fill the strip")
    local pixel = world.core.Require("MSUF_GetPhysicalPixelSize")(maximize, 1)
    assert(dash[1]:GetWidth() > pixel and dash[1]:GetHeight() == pixel, "minimize bar is not one physical pixel high")
    assert(square[1]:GetHeight() == pixel and square[3]:GetHeight() == pixel,
        "maximize needs two visible horizontal bars")
    assert(square[2]:GetWidth() == pixel and square[4]:GetWidth() == pixel,
        "maximize needs two visible vertical bars")
    assert(cross[1]:GetWidth() >= pixel and cross[1]:GetHeight() >= pixel, "close icon has an empty rectangle")
    maximize:SetWindowControlIcon("restore")
    assert(square[8]:IsShown(), "maximized window has no overlapping restore glyph")
    maximize:SetWindowControlIcon("maximize")
    assert(not square[8]:IsShown(), "restore glyph leaked into maximize state")

    -- A UIParent scale change (Global UI Scale, Blizzard's UI scale, profile
    -- switch) bypasses the menu-scale path. Bars sized for the old scale drop
    -- below one device pixel and the rounded layout erases some of them.
    local UIParent = world.env.UIParent
    local oldScale = UIParent:GetScale()
    UIParent:SetScale((oldScale or 1) * 0.6)
    local shrunk = world.core.Require("MSUF_GetPhysicalPixelSize")(maximize, 1)
    assert(shrunk ~= pixel and square[1]:GetHeight() == pixel, "fixture did not change the effective scale")
    local probe = assert(group._msuf2CaptionScaleProbe, "caption glyphs never relayout on a UI scale change")
    probe:GetScript("OnSizeChanged")(probe)
    assert(dash[1]:GetHeight() == shrunk and square[1]:GetHeight() == shrunk and square[3]:GetHeight() == shrunk,
        "horizontal caption bars kept the stale pixel after a UI scale change")
    assert(square[2]:GetWidth() == shrunk and square[4]:GetWidth() == shrunk,
        "vertical caption bars kept the stale pixel after a UI scale change")
    UIParent:SetScale(oldScale)
    assert(probe:IsEventRegistered("DISPLAY_SIZE_CHANGED"), "caption has no display-size listener")
    probe:GetScript("OnEvent")(probe, "DISPLAY_SIZE_CHANGED")
    assert(dash[1]:GetHeight() == pixel and square[1]:GetHeight() == pixel,
        "caption bars kept the stale pixel after a display size change")
end
