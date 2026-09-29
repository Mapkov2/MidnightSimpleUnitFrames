local root = assert(arg[1], "repository root required")
local source = root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"
local chunk = assert(loadfile(source))

local ns = { Client = { IsForever = false } }
chunk("MidnightSimpleUnitFrames", ns)
assert(ns.SwingTimer == nil, "other clients must not expose Swing Timer controls")

ns.Client.IsForever = true
local inCombat, ruleBlocked, preset, editActive = false, false, false, false
ns.Client.IsGameRuleActive = function(rule) return rule == "EditModeDisabled" and ruleBlocked end
_G.InCombatLockdown = function() return inCombat end
_G.Enum = {
    EditModeSystem = { SwingTimer = 42 },
    EditModeSwingTimerSystemIndices = { MainHand = 0, OffHand = 1, Ranged = 2 },
    EditModeSwingTimerSetting = {
        Scale = 1, Opacity = 2, Visibility = 3, Width = 4,
        Height = 5, ShowBarTitle = 6, ShowTime = 7,
    },
    EditModeSwingTimerVisibility = { Always = 0, InCombat = 1, Hidden = 2 },
}
local frames = {}
for index = 0, 2 do
    local frame = { values = { [1] = 100, [2] = 100, [3] = 0, [4] = 426, [5] = 30, [6] = 1, [7] = 1 } }
    function frame:GetSettingValue(setting) return self.values[setting] end
    frames[index] = frame
end
_G.SwingTimerMainHandFrame = frames[0]
_G.SwingTimerOffHandFrame = frames[1]
_G.SwingTimerRangedFrame = frames[2]
local saves, changes, selected = 0, 0, nil
_G.EditModeManagerFrame = {
    GetRegisteredSystemFrame = function(_, system, index)
        return system == 42 and frames[index] or nil
    end,
    IsActiveLayoutPreset = function() return preset end,
    IsEditModeActive = function() return editActive end,
    CanEnterEditMode = function() return not ruleBlocked end,
    OnSystemSettingChange = function(_, frame, setting, value)
        changes = changes + 1
        frame.values[setting] = value
    end,
    SaveLayouts = function() saves = saves + 1 end,
    SelectSystem = function(_, frame) selected = frame end,
}
_G.CVarCallbackRegistry = { GetCVarValueBool = function() return _G.testSwingEnabled end }
_G.SetCVar = function(name, value)
    assert(name == "showSwingTimer")
    _G.testSwingEnabled = value == "1"
end
_G.ShowUIPanel = function() editActive = true end
_G.MSUF_BlizzardEditMode_EnsureLayout = function() preset = false; return true end

chunk("MidnightSimpleUnitFrames", ns)
local swing = assert(ns.SwingTimer)
assert(swing.IsAvailable("main") and swing.IsAvailable("off") and swing.IsAvailable("ranged"))
assert(swing.SetEnabled(true) and swing.GetEnabled())
assert(swing.Set("off", "width", 500) and frames[1].values[4] == 500)
assert(changes == 1 and saves == 1 and frames[0].values[4] == 426)
assert(swing.Set("off", "width", 500) and changes == 1 and saves == 1, "unchanged value must not save")
assert(not swing.Set("main", "scale", 201) and not swing.Set("main", "visibility", 9))
assert(swing.Set("ranged", "visibility", 2) and frames[2].values[3] == 2)
assert(swing.Set("main", "title", false) and frames[0].values[6] == 0)
preset = true
assert(swing.Set("main", "height", 40) and not preset, "preset must become an editable layout")
assert(swing.OpenEditMode("ranged") and selected == frames[2])
local priorSaves = saves
assert(swing.Set("main", "opacity", 80) and saves == priorSaves,
    "native Edit Mode must retain its own Save/Discard decision")
inCombat = true
assert(not swing.Set("main", "width", 400) and not swing.OpenEditMode("main"))
inCombat = false; ruleBlocked = true
assert(not swing.SetEnabled(false) and not swing.Set("main", "width", 400))
print("PASS Forever Swing Timer native layout settings")
