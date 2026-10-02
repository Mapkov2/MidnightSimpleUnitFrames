-- classpower_paint_stamps_smoke.lua <repoRoot>
--
-- The ClassPower painters skip a widget write when the widget's _msufCP*
-- stamp already holds the value (MSUF_CP_Modes.lua stamp helpers). A writer
-- that paints the same widgets without those helpers must leave the stamps
-- truthful, or the next mode on the same bar skips a write it needs:
--   * Ironfur (Guardian Bear) paints pip 1 and the count text directly;
--     after Bear -> Cat the combo points must repaint pip 1 and the text.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function SameColor(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function DisplayPower(t, primary)
    t.S.primary = primary
    t.env:AdvanceTime(1)
    World.Dispatcher(t, "UNIT_DISPLAYPOWER", "player", "ENERGY")()
    t.env:RunTimers()
end

-- Ironfur: Cat (combo points) -> Bear (Ironfur) -> Cat.
do
    local t = World.Start(repo, "Mainline", "DRUID", 3, PT.ENERGY,
        { showGuardianIronfur = true, classPowerShowText = true })
    local CP = t.CP
    Check(CP.visible and CP.powerType == PT.COMBO, "Guardian in Cat form did not route combo points")
    local bar, text = CP.bars[1], CP.text
    local comboColor = { bar.color[1], bar.color[2], bar.color[3] }
    Check(bar.alpha == 1 and text and text.shown and text.text == 3, "Cat form did not paint 3 combo points")

    DisplayPower(t, PT.RAGE)
    Check(CP.powerType == "IRONFUR", "Guardian in Bear form did not route Ironfur")
    Check(not SameColor(bar.color, comboColor) and bar.alpha ~= 1 and text.shown == false,
        "Ironfur did not paint pip 1 and hide the count")

    DisplayPower(t, PT.ENERGY)
    Check(CP.powerType == PT.COMBO, "Guardian back in Cat form did not route combo points")
    Check(SameColor(bar.color, comboColor), "pip 1 kept the Ironfur colour after Bear -> Cat")
    Check(bar.alpha == 1, "pip 1 kept the Ironfur alpha after Bear -> Cat")
    Check(bar.value == 1, "pip 1 kept the Ironfur fill after Bear -> Cat")
    Check(text.shown == true and text.text == 3, "the combo count stayed hidden or stale after Bear -> Cat")
end

if #failures > 0 then
    error("classpower_paint_stamps_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_paint_stamps_smoke: ok (Ironfur)")
