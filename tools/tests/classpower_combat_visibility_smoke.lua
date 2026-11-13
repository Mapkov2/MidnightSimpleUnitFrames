-- A native-aura class resource must react to combat without a power event.
local root = assert(arg[1]):gsub("\\", "/")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local h = Harness.New(root, "Mainline", { beforeBoot = function(h)
    MenuWorld.InstallNativeUnitInputs(h.world)
    h.env.C_SpecializationInfo.GetSpecialization = function() return 2 end -- Fury
    h.env.UnitAffectingCombat = function() return false end
    h.env.UnitHasVehicleUI = function() return false end
end })

local bars = h.UF.Config.GetDB().bars
bars.showClassPower = true
bars.classPowerHideOOC = true
local player = h.env.CreateFrame("Frame", nil, h.env.UIParent)
player:SetSize(200, 30)
h.UF.frames.player = player
local refresh = h.core.Require("MSUF_ClassPower_Refresh", "class resource test")
refresh()
assert(h.core.CPBuilders.ClassPowerType() == "WHIRLWIND", "fixture must select the Fury resource")
local container
for _, frame in ipairs(h.widgets.frames) do
    if frame:GetName() == "MSUF_ClassPowerContainer" then container = frame break end
end
assert(container, "Whirlwind container was not built")
assert(container:IsShown(), "class resource controller did not activate")
assert(container:GetAlpha() == 0, "out-of-combat setting did not hide the resource")

h:EnterCombat(function()
    assert(not h.env.InCombatLockdown(), "fixture must dispatch before lockdown")
    assert(container:GetAlpha() == 1, "Whirlwind stayed hidden at combat entry")
    refresh()
    assert(container:GetAlpha() == 1, "same-frame settings refresh hid Whirlwind again")
end)
h:LeaveCombat()
assert(container:GetAlpha() == 0, "Whirlwind stayed visible at combat exit")
print("PASS class resource combat visibility without a power event")
