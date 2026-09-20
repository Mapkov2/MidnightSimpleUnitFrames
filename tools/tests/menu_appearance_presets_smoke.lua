-- Build the real Misc page: all seven appearance choices must survive on every client.
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
local expected = {'classicGlass','midnight','class','ember','jade','violet','custom'}
assert(#choices == #expected, 'appearance dropdown lost its legacy choices')
for i, value in ipairs(expected) do assert(choices[i].value == value, 'missing preset: ' .. value) end
local general = M.GetGeneralDB()
local color = 'cc6633'
general.menuAccentColor = color
for _, material in ipairs({'classicGlass', 'midnight'}) do
    style.set(material)
    assert(style.get() == material and general.menuAppearancePreset == material)
    assert(accent.get() == 'midnight' and general.menuAccentTintSurfaces == false)
    for _, value in ipairs({'class','ember','jade','violet','custom'}) do
        style.set(value)
        assert(style.get() == value and accent.get() == value, 'preset does not select: ' .. value)
        assert(general.menuAppearancePreset == material, 'color choice changed the material')
        assert(general.menuAccentColor == color, 'preset discarded the saved custom color')
    end
end
style.set('invalid')
assert(style.get() == 'custom', 'invalid preset overwrote the selection')
accent.set('jade')
assert(style.get() == 'jade', 'separate accent selector does not update appearance selection')
opacity.set(89)
assert(opacity.get() == 89 and general.menuBackgroundOpacity == 89)
print('PASS ' .. flavor .. ': seven visible appearance presets, both materials, custom color preservation, opacity')
