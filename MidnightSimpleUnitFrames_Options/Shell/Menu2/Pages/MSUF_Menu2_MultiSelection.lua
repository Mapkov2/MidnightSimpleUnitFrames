local _, MSUF = ...
local M = MSUF.MSUF2
local picked, deltaX, deltaY = "", "0", "0"
local function SelectionChanged()
    if M.activeKey == "edit_selection" and M.frame and M.frame:IsShown() then M.ProfileWorkbenchUI.Refresh() end
end
function M.BuildMultiSelectionTools(ctx, builder, width)
    local UI = M.ProfileWorkbenchUI
    UI.Editor(ctx, builder, width, function(ctx, builder, width)
    local EM = MSUF.Require("MSUF_EM2", "Shell/Menu2/Pages/MSUF_Menu2_MultiSelection.lua")
    local multi = EM.MultiSelection
    multi.SelectionChanged = SelectionChanged
    local section = builder:CollapsibleSection("workbench_alignment", "Move and align multiple elements", 375, true)
    UI.Button(section, "Open Edit Mode", "multi.open", 20, -22, function()
        if not EM.State.IsActive() then M.ToggleMSUFEditMode() end
        M.ProfileWorkbenchUI.Refresh()
    end)
    UI.Text(section, "Choose elements here or Ctrl-click their movers. Alignment uses the first selected element in the list.", -63, width)
    local values, labels = {}, {}
    for _, item in ipairs(multi.Items()) do
        local selected = multi.selected[item.key]
        values[#values + 1] = { value = item.key, text = (selected and "[+] " or "[–] ") .. M.Tr(item.label), translate = false }
        if selected then labels[#labels + 1] = M.Tr(item.label) end
    end
    UI.Drop(ctx, section, "Elements", "multi.select", values, function() return picked end,
        function(value) picked = value end, 20, -106, width - 40)
    UI.Button(section, "Select / remove element", "multi.toggle", 20, -161, function() if not multi.Toggle(picked) then UI.Result(false) end end, 230)
    UI.Text(section, M.Format("Selected: %s", table.concat(labels, ", ")), -203, width)
    UI.Input(section, "Move X", "multi.x", 20, -242, 110, deltaX, function(value) deltaX = value end)
    UI.Input(section, "Move Y", "multi.y", 146, -242, 110, deltaY, function(value) deltaY = value end)
    UI.Button(section, "Move together", "multi.move", 278, -262,
        function() UI.Result(multi.Apply("move", tonumber(deltaX), tonumber(deltaY))) end)
    local actions = { { "left", "Align left" }, { "right", "Align right" }, { "top", "Align top" }, { "bottom", "Align bottom" },
        { "horizontal", "Equal horizontal gaps" }, { "vertical", "Equal vertical gaps" } }
    for i, action in ipairs(actions) do
        UI.Button(section, action[2], "multi." .. action[1], 20 + ((i - 1) % 3) * ((width - 40) / 3),
            -306 - math.floor((i - 1) / 3) * 34, function() UI.Result(multi.Apply(action[1])) end, (width - 60) / 3)
    end
    end)
end
