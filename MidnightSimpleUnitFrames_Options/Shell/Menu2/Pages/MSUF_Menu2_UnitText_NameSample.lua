-- The page supplies sample inputs; runtime text state owns formatting and the sink.
local _, MSUF = ...
local M = MSUF.MSUF2
local Sample = {}
M.UnitNameSample = Sample

function Sample.Paint(value, unit, name, groupAllowed)
    local state = value._msufNameSample
    if not state then
        local color = M.Theme.colors.text
        state = { nameText = value, _msufTextRuntime = {},
            MSUFSpec = { textColor = { r = color[1], g = color[2], b = color[3], a = color[4] or 1 } } }
        value._msufNameSample = state
    end
    local owner = M.UnitPage
    if groupAllowed and owner.ReadStatusBool(unit, "showRaidGroupInName", false) then
        local group = MSUF.UFStatusRuntime.RaidGroupText(owner.ReadText(unit, "raidGroupNameStyle", "PAREN"), 2)
        name = name .. " " .. group
    end
    MSUF.UFText.PaintSampleName(state, name)
end
