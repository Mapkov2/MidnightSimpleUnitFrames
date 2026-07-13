-- Standalone regression for the cached Power-bar visibility hotpath.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function() return false end

local elements = {}
local percentReads = 0
local UF = {
    RegisterElement = function(name, element) elements[name] = element end,
}
local common = {
    UF = UF,
    UnitPower = function() return 50 end,
    UnitPowerMax = function() return 100 end,
    UnitPowerType = function() return 0, "MANA" end,
    UnitPowerPercent = function()
        percentReads = percentReads + 1
        return 50
    end,
    PowerBarColor = { MANA = { r = 0, g = 0.4, b = 1 } },
    SCALE_100 = {},
    WHITE = "white",
}
local addon = { UF = UF, UFBarTextCommon = common }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))
    ("MidnightSimpleUnitFrames", addon)

local isShownCalls = 0
local bar = {
    _msufShown = true,
    _msufPowerType = 0,
    _msufPowerToken = "MANA",
    _msufPowerTypeKnown = true,
    _msufPowerTypeUnit = "target",
    IsShown = function()
        isShownCalls = isShownCalls + 1
        return true
    end,
    SetMinMaxValues = function(self, _, maximum) self.maximum = maximum end,
    SetValue = function(self, value) self.value = value end,
}
local frame = {
    unit = "target",
    targetPowerBar = bar,
    MSUFSpec = { power = { enabled = true, mode = "power" } },
}
local update = elements.Power.SelectUpdate(frame)

update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 1 and bar.value == 50, "visible cached bar did not update")
Check(isShownCalls == 0, "steady Power update called native IsShown")

bar._msufShown = false
update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 1, "cached hidden Power bar performed value work")
Check(isShownCalls == 0, "hidden Power bar called native IsShown")

bar._msufShown = nil
update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 2 and isShownCalls == 1,
    "uncached pre-Apply bar lost its native visibility fallback")

print("Power bar visibility hotpath smoke passed (cached show/hide + legacy fallback)")
