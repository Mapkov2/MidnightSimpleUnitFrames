-- resource_mark_value_range_smoke.lua <repoRoot> <flavor>
--
-- Class Resources > Resource marks and thresholds: the "Resource value"
-- slider spanned 0-10,000,000 in both value modes. A percent mark is placed at
-- value / 100 (ClassPower/MSUF_CP_ResourceMarks.lua), so one pixel of drag
-- moved it by tens of thousands of percent, and a stored percent above 100
-- is a mark that never shows. The slider now spans 0-100 for a percent mark.
-- An absolute mark is placed at value / UnitPowerMax of the power it sits on
-- and shows only up to that maximum, so its slider spans the character's
-- maximum of that power (five combo points: 0-5, not 0-10,000,000), falls
-- back to 0-100 when the maximum cannot be read, and widens to a saved value
-- above the maximum instead of cutting it. The range follows the selected
-- mark, its mode, bar and power, and every write keeps the value inside the
-- range of its mode.
--
-- Boots the real core and Options graph (menu_core_world.lua), opens the
-- marks section and drives its real controls through their command actions.
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("resource_mark_value_range_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = function(world)
    -- Same harness gap as classpower_workspace_smoke: keep centers numeric.
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, env = mw.M, mw.env
Check(mw:Select("classpower"), "Class Resources page did not open")
local ui = Check(M.ClassPowerWorkspace.current, "resource workspace missing")
ui:Select("extras")
mw:RunTimers()
for _, entry in ipairs(ui.entries.extras) do entry.SetOpenImmediate(true) end
mw:RunTimers()

local function Control(path)
    local id = "menu2.classpower.advanced.resource.extras.marks." .. path
    for _, widget in ipairs(mw.world.widgets.frames) do
        local meta = widget._msuf2SearchMeta
        if meta and meta.controlId == id then return widget end
    end
    error("resource_mark_value_range_smoke " .. flavor .. ": control missing: " .. id)
end
local add, value, mode, picker = Control("add"), Control("value"), Control("mode"), Control("select")
local target, resource = Control("target"), Control("resource")
-- A rogue: Energy on the Player bar, five combo points, no mana. The power
-- type values are the client's (PowerTypeConstantsDocumentation.lua); the
-- harness Enum is a stub that ignores plain writes.
rawset(env.Enum, "PowerType", { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6,
    SoulShards = 7, LunarPower = 8, HolyPower = 9, Maelstrom = 11, Chi = 12, Insanity = 13, ArcaneCharges = 16, Essence = 19 })
local MAXIMA = { [3] = 100, [4] = 5 }
env.UnitPowerMax = function(unit, power) return unit == "player" and MAXIMA[power] or 0 end
env.UnitPowerType = function() return 3, "ENERGY" end
local function Rule(i) return env.MSUF_DB.bars.resourceMarks[i] end
local function Max()
    local _, maximum = value:GetMinMaxValues()
    return maximum
end
local function Set(widget, v)
    widget._msuf2CommandAction.set(v)
    mw:RunTimers()
end

-- A new mark is a percent mark.
add:Click("LeftButton")
mw:RunTimers()
Check(Rule(1) and Rule(1).mode == "PERCENT", "precondition: Add resource mark did not add a percent mark")
Check(Max() == 100, "a percent mark's value slider spans 0-" .. tostring(Max()))
Set(value, 4000000)
Check(Rule(1).value == 100, "a percent mark stored " .. tostring(Rule(1).value))
-- Absolute on the Player bar: it shows Energy, so the slider spans its maximum.
Set(mode, "ABSOLUTE")
Check(Max() == 100 and Rule(1).value == 100, "an absolute Energy mark spans 0-" .. tostring(Max())
    .. " with the value " .. tostring(Rule(1).value))
Set(value, 3)
-- The reported case: combo points on the class resource bar span 0-5.
Set(target, "CLASS")
Check(Max() == 5, "an absolute class resource mark spans 0-" .. tostring(Max()))
Set(resource, "COMBO_POINTS")
Check(Max() == 5, "an absolute combo point mark spans 0-" .. tostring(Max()))
Check(Rule(1).value == 3, "an absolute mark lost its value: " .. tostring(Rule(1).value))
-- A value above the maximum is kept, and the range widens to show it.
Set(value, 8)
Check(Rule(1).value == 8, "an absolute value above the maximum was cut to " .. tostring(Rule(1).value))
Set(picker, 1)
Check(Max() == 8 and value:GetValue() == 8 and Rule(1).value == 8, "a refresh cut the value 8 to "
    .. tostring(Rule(1).value) .. " or left it off a 0-" .. tostring(Max()) .. " slider")
-- So is a saved one: the same refresh runs when the page opens.
Rule(1).value = 40000
Set(picker, 1)
Check(Max() == 40000 and Rule(1).value == 40000, "the saved value 40000 became " .. tostring(Rule(1).value)
    .. " on a 0-" .. tostring(Max()) .. " slider")
Set(value, 3)
-- A power this character does not have: 0-100.
Set(resource, "MANA")
Check(Max() == 100, "an absolute mark on a power without a maximum spans 0-" .. tostring(Max()))
Set(resource, "COMBO_POINTS")
Check(Max() == 5, "the range did not follow the power: 0-" .. tostring(Max()))
-- Back to percent: the stored value comes back into range.
Set(value, 3000)
Set(mode, "PERCENT")
Check(Max() == 100 and Rule(1).value == 100, "switching to percent kept " .. tostring(Rule(1).value)
    .. " on a 0-" .. tostring(Max()) .. " slider")
-- The range follows the selected mark.
Set(mode, "ABSOLUTE")
Set(value, 3)
add:Click("LeftButton")
mw:RunTimers()
Check(Rule(2) and Max() == 100, "the new percent mark kept the absolute range")
Set(picker, 1)
Check(Max() == 5, "selecting the absolute combo point mark kept the range 0-" .. tostring(Max()))
-- The width slider keeps its own range.
Check(select(2, Control("width"):GetMinMaxValues()) == 20, "the mark width range changed")

print("resource_mark_value_range_smoke " .. flavor .. ": OK")
