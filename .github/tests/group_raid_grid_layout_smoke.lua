-- Focused geometry regression for the Group Frames Raid grid control card.

local path = "MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_GroupLayout.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

assert(source:find('CollapsibleSection("layout", "Layout", 460', 1, true),
    "Group layout section is too short for the expanded Raid grid card")
assert(source:find('W.ControlCard(layout, "Raid grid", "Column behavior for raid-like scopes.", layoutLeftX, -244, layoutLeftW, 188)', 1, true),
    "Raid grid card lost its non-clipping height")
assert(source:find('W.ToggleAt(gridCard, "Preserve raid groups", 16, -166', 1, true),
    "Preserve raid groups overlaps the Max columns slider")

print("group_raid_grid_layout_smoke: ok")
