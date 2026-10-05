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
-- On the Class resource bar with "Any power type" the power is the one that
-- bar shows, picked by the class resource controller's own resolver: a Death
-- Knight's bar shows six runes (0-6), not Runic Power (0-100), and a Mists
-- Shadow Priest's shows three Shadow Orbs, a power the mark list does not
-- name. A class without a class resource bar falls back to 0-100.
--
-- Boots the real core and Options graph (menu_core_world.lua) once per class,
-- opens the marks section and drives its real controls through their command
-- actions. Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("resource_mark_value_range_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Enum.PowerType as every client branch documents it
-- (Blizzard_APIDocumentationGenerated/PowerTypeConstantsDocumentation.lua).
local POWER_TYPE = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6,
    SoulShards = 7, LunarPower = 8, HolyPower = 9, Alternate = 10, Maelstrom = 11, Chi = 12, Insanity = 13,
    BurningEmbers = 14, DemonicFury = 15, ArcaneCharges = 16, Fury = 17, Pain = 18, Essence = 19,
    RuneBlood = 20, RuneFrost = 21, RuneUnholy = 22, AlternateQuest = 23, AlternateEncounter = 24,
    AlternateMount = 25, Balance = 26, Happiness = 27, ShadowOrbs = 28, RuneChromatic = 29 }

-- One character: its class, specialization, Player bar power and power maxima
-- are in place before the core loads, as on a real login.
local function Open(character)
    local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = function(world)
        local env = world.env
        rawset(env.Enum, "PowerType", POWER_TYPE)
        env.UnitClass = function() return character.name, character.class, character.classID end
        env.UnitHasVehicleUI = function() return false end
        env.UnitPowerType = function() return character.power, character.token end
        env.UnitPowerMax = function(unit, power) return unit == "player" and character.maxima[power] or 0 end
        local spec = function() return character.spec end
        env.GetSpecialization = spec
        env.C_SpecializationInfo = { GetSpecialization = spec }
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
    local t = { mw = mw, env = env }
    function t.Control(path)
        local id = "menu2.classpower.advanced.resource.extras.marks." .. path
        for _, widget in ipairs(mw.world.widgets.frames) do
            local meta = widget._msuf2SearchMeta
            if meta and meta.controlId == id then return widget end
        end
        error("resource_mark_value_range_smoke " .. flavor .. ": control missing: " .. id)
    end
    function t.Rule(i) return env.MSUF_DB.bars.resourceMarks[i] end
    function t.Max()
        local _, maximum = t.Control("value"):GetMinMaxValues()
        return maximum
    end
    function t.Set(path, v)
        t.Control(path)._msuf2CommandAction.set(v)
        mw:RunTimers()
    end
    function t.Add()
        t.Control("add"):Click("LeftButton")
        mw:RunTimers()
    end
    return t
end

-- A rogue: Energy on the Player bar, five combo points, no mana.
local rogue = Open({ name = "Rogue", class = "ROGUE", classID = 4, spec = 1, power = 3, token = "ENERGY",
    maxima = { [3] = 100, [4] = 5 } })
local Set, Max, Rule = rogue.Set, rogue.Max, rogue.Rule
-- A new mark is a percent mark.
rogue.Add()
Check(Rule(1) and Rule(1).mode == "PERCENT", "precondition: Add resource mark did not add a percent mark")
Check(Max() == 100, "a percent mark's value slider spans 0-" .. tostring(Max()))
Set("value", 4000000)
Check(Rule(1).value == 100, "a percent mark stored " .. tostring(Rule(1).value))
-- Absolute on the Player bar: it shows Energy, so the slider spans its maximum.
Set("mode", "ABSOLUTE")
Check(Max() == 100 and Rule(1).value == 100, "an absolute Energy mark spans 0-" .. tostring(Max())
    .. " with the value " .. tostring(Rule(1).value))
Set("value", 3)
-- The reported case: combo points on the class resource bar span 0-5.
Set("target", "CLASS")
Check(Max() == 5, "an absolute class resource mark spans 0-" .. tostring(Max()))
Set("resource", "COMBO_POINTS")
Check(Max() == 5, "an absolute combo point mark spans 0-" .. tostring(Max()))
Check(Rule(1).value == 3, "an absolute mark lost its value: " .. tostring(Rule(1).value))
-- A value above the maximum is kept, and the range widens to show it.
Set("value", 8)
Check(Rule(1).value == 8, "an absolute value above the maximum was cut to " .. tostring(Rule(1).value))
Set("select", 1)
Check(Max() == 8 and rogue.Control("value"):GetValue() == 8 and Rule(1).value == 8, "a refresh cut the value 8 to "
    .. tostring(Rule(1).value) .. " or left it off a 0-" .. tostring(Max()) .. " slider")
-- So is a saved one: the same refresh runs when the page opens.
Rule(1).value = 40000
Set("select", 1)
Check(Max() == 40000 and Rule(1).value == 40000, "the saved value 40000 became " .. tostring(Rule(1).value)
    .. " on a 0-" .. tostring(Max()) .. " slider")
Set("value", 3)
-- A power this character does not have: 0-100.
Set("resource", "MANA")
Check(Max() == 100, "an absolute mark on a power without a maximum spans 0-" .. tostring(Max()))
Set("resource", "COMBO_POINTS")
Check(Max() == 5, "the range did not follow the power: 0-" .. tostring(Max()))
-- Back to percent: the stored value comes back into range.
Set("value", 3000)
Set("mode", "PERCENT")
Check(Max() == 100 and Rule(1).value == 100, "switching to percent kept " .. tostring(Rule(1).value)
    .. " on a 0-" .. tostring(Max()) .. " slider")
-- The range follows the selected mark.
Set("mode", "ABSOLUTE")
Set("value", 3)
rogue.Add()
Check(Rule(2) and Max() == 100, "the new percent mark kept the absolute range")
Set("select", 1)
Check(Max() == 5, "selecting the absolute combo point mark kept the range 0-" .. tostring(Max()))
-- The width slider keeps its own range.
Check(select(2, rogue.Control("width"):GetMinMaxValues()) == 20, "the mark width range changed")

-- An absolute "Any power type" mark on the Class resource bar, as a character
-- saved it; the page shows its range and must keep the value.
local function ClassMark(t, value)
    t.Add()
    t.Set("mode", "ABSOLUTE")
    t.Set("value", value)
    t.Set("target", "CLASS")
    t.Set("resource", "ALL")
    return t.Rule(1)
end

if flavor == "Mists" or flavor == "Mainline" then
    -- The reported case: a Death Knight's class resource bar shows six runes
    -- (Game/Mists/ClassPower.lua, ClassPower/MSUF_CP_Controller_Config.lua),
    -- while the Player bar and the largest listed class power are Runic Power.
    local dk = Open({ name = "Death Knight", class = "DEATHKNIGHT", classID = 6, spec = 1, power = 6,
        token = "RUNIC_POWER", maxima = { [5] = 6, [6] = 100 } })
    local rule = ClassMark(dk, 3)
    Check(dk.Max() == 6, "a Death Knight's absolute class resource mark spans 0-" .. tostring(dk.Max())
        .. ", not the six runes its bar shows")
    Check(rule.value == 3 and dk.Control("value"):GetValue() == 3, "the rune mark lost its value 3: "
        .. tostring(rule.value))
    -- The Player bar keeps Runic Power.
    dk.Set("target", "PLAYER")
    Check(dk.Max() == 100, "a Death Knight's Player bar mark spans 0-" .. tostring(dk.Max()))
    dk.Set("target", "CLASS")
    Check(dk.Max() == 6 and rule.value == 3, "the range did not return to the six runes: 0-" .. tostring(dk.Max()))
else
    -- No class resource bar for a warrior: nothing to read, so 0-100.
    local warrior = Open({ name = "Warrior", class = "WARRIOR", classID = 1, spec = 1, power = 1, token = "RAGE",
        maxima = { [1] = 100 } })
    local rule = ClassMark(warrior, 3)
    Check(warrior.Max() == 100 and rule.value == 3, "a warrior's absolute class resource mark spans 0-"
        .. tostring(warrior.Max()) .. " with the value " .. tostring(rule.value))
end

if flavor == "Mists" then
    -- A Shadow Priest's class resource bar shows three Shadow Orbs, a power
    -- the mark's power list does not name.
    local priest = Open({ name = "Priest", class = "PRIEST", classID = 5, spec = 3, power = 0, token = "MANA",
        maxima = { [0] = 100000, [28] = 3 } })
    local rule = ClassMark(priest, 2)
    Check(priest.Max() == 3 and rule.value == 2, "a Shadow Priest's absolute class resource mark spans 0-"
        .. tostring(priest.Max()) .. " with the value " .. tostring(rule.value) .. ", not the three orbs its bar shows")
end

print("resource_mark_value_range_smoke " .. flavor .. ": OK")
