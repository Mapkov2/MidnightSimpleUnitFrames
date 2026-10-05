-- resource_mark_value_range_smoke.lua <repoRoot> <flavor>
--
-- Class Resources > Resource marks and thresholds: the "Resource value"
-- slider spanned 0-10,000,000 in both value modes. A percent mark is placed at
-- value / 100 (ClassPower/MSUF_CP_ResourceMarks.lua), so one pixel of drag
-- moved it by tens of thousands of percent, and a stored percent above 100
-- is a mark that never shows. The slider now spans 0-100 for a percent mark
-- and keeps the wide range for an absolute one, follows the selected mark,
-- and every write keeps the value inside the range of its mode.
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
-- Absolute: the wide range of raw power values.
Set(mode, "ABSOLUTE")
Check(Max() == 10000000, "an absolute mark's value slider spans 0-" .. tostring(Max()))
Set(value, 3000)
Check(Rule(1).value == 3000, "an absolute mark lost its value: " .. tostring(Rule(1).value))
-- Back to percent: the stored value comes back into range.
Set(mode, "PERCENT")
Check(Max() == 100 and Rule(1).value == 100, "switching to percent kept " .. tostring(Rule(1).value)
    .. " on a 0-" .. tostring(Max()) .. " slider")
-- The range follows the selected mark.
Set(mode, "ABSOLUTE")
add:Click("LeftButton")
mw:RunTimers()
Check(Rule(2) and Max() == 100, "the new percent mark kept the absolute range")
Set(picker, 1)
Check(Max() == 10000000, "selecting the absolute mark kept the percent range")
-- The width slider keeps its own range.
Check(select(2, Control("width"):GetMinMaxValues()) == 20, "the mark width range changed")

print("resource_mark_value_range_smoke " .. flavor .. ": OK")
