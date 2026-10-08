local root, flavor, mode = assert(arg[1]), arg[2] or "Mainline", arg[3] or "routes"
local file, baseline = os.getenv("BH3_FILE"), os.getenv("BH3_BASELINE")
if file and baseline then
    local original = loadfile
    loadfile = function(path)
        if path:gsub("\\", "/") == root .. "/" .. file then path = baseline .. "/" .. file end
        return original(path)
    end
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local restrictedBoolean = false
local mw = World.Open(root, flavor, { beforeCore = function(w)
    if mode == "raid" then w.env.issecretvalue = function(v) return restrictedBoolean and v == true end end
end })
local E, env = mw.env.MSUF_EM2, mw.env
if mode == "routes" then
    for _, item in ipairs({
        { "castbar_target", "target", "castbar", "castbar" },
        { "castbar_boss", "boss", "castbar", "castbar" },
        { "power_focus", "focus", "resource", "power_bar" },
    }) do
        E.Registry.Register({ key = item[1], popupType = item[3], resourceKind = item[3] == "resource" and "power" or nil,
            castbarUnit = item[3] == "castbar" and item[2] or nil,
            resourceUnit = item[3] == "resource" and item[2] or nil, getFrame = function() return env.UIParent end })
        E.Focus.SetSelection(item[1])
        E.Focus.OpenFullSettings()
        local request = assert(env.MSUF_EM2_MenuFocusRequest)
        assert(request.pageKey == "uf_" .. item[2], item[1] .. " routed to " .. tostring(request.pageKey))
        assert(request.sectionId == item[4], item[1] .. " routed to " .. tostring(request.sectionId))
    end
elseif mode == "selection" then
    local popup = env.CreateFrame("Frame"); popup:Show()
    E.AuraPopup.IsOpen = function() return popup:IsShown() end
    E.AuraPopup.Close = function() popup:Hide() end
    env.MSUF_EM2_ActiveAuraGroup, env.MSUF_EM2_ActiveAuraUnit = "buff", "player"
    E.State.SetUnitKey("castbar_target")
    assert(not popup:IsShown() and env.MSUF_EM2_ActiveAuraGroup == nil and env.MSUF_EM2_ActiveAuraUnit == nil,
        "selecting another mover retained the aura nudge target")
elseif mode == "picker" then
    for _, unit in ipairs({ "player", "target", "focus" }) do
        E.Registry.Register({ key = "power_" .. unit, label = "Detached power bar", popupType = "resource",
            resourceKind = "power", resourceUnit = unit, getFrame = function() return env.UIParent end })
    end
    E.HUDDock.contextBtn = env.CreateFrame("Button", nil, env.UIParent)
    E.HUD.ToggleFramePicker()
    local picker = assert(E.HUDDock.framePicker)
    local count, labels = 0, {}
    for _, row in ipairs(picker._rows) do
        if row._msufKey and row._msufKey:match("^power_") then
            local text = row._fs:GetText()
            assert(not labels[text], "detached power picker labels are ambiguous")
            labels[text] = true; count = count + 1
        end
    end
    assert(count == 3, "detached power picker rows missing")
elseif mode == "raid" then
    env.IsInRaid = function() return true end
    env.UnitInRaid = function() return 1 end
    env.GetRaidRosterInfo = function(index) if index == 1 then return "Player", 0, 4 end end
    env.UnitIsUnit = function() return true end
    assert(mw.core.UFPreview.LiveRaidSubgroup() == 4, "ordinary player subgroup changed")
    restrictedBoolean = true
    assert(mw.core.UFPreview.LiveRaidSubgroup() == nil, "restricted comparison result reached a truth test")
    restrictedBoolean = false
    env.UnitIsUnit = function() return false end
    assert(mw.core.UFPreview.LiveRaidSubgroup() == nil, "a different unit's subgroup was returned")
else error(mode) end
print("Edit Mode selection " .. mode .. ": PASS")
