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

-- Retail combo points must repaint on the native power event used by Blizzard's bar.
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local points, charged = 6, nil
local combo = Harness.New(root, "Mainline", { beforeBoot = function(h)
    MenuWorld.InstallNativeUnitInputs(h.world)
    local env = h.env
    local power = env.Enum.PowerType
    env.issecretvalue, env.type, env.tonumber = Secrets.IsSecret, type, tonumber
    env.UnitClass = function() return "Rogue", "ROGUE", 4 end
    env.C_SpecializationInfo.GetSpecialization = function() return 2 end -- Outlaw
    env.UnitPowerType = function() return power.Energy, "ENERGY" end
    env.GetUnitChargedPowerPoints = function() return charged end
    local unitPower, unitPowerMax = env.UnitPower, env.UnitPowerMax
    env.UnitPower = function(unit, powerType, ...)
        if unit == "player" and powerType == power.ComboPoints then return points end
        return unitPower(unit, powerType, ...)
    end
    env.UnitPowerMax = function(unit, powerType)
        if unit == "player" then
            if powerType == power.ComboPoints then return 7 end
            if powerType == power.Energy then return 100 end
        end
        return unitPowerMax(unit, powerType)
    end
end })
local comboDB = combo.UF.Config.GetDB()
local comboBars = comboDB.bars
comboBars.showClassPower = true
comboBars.showChargedComboPoints = true
comboBars.classPowerBgAlpha = 1
local gold, green, black = { 0.76, 0.72, 0.31 }, { 0.46, 0.73, 0.45 }, { 0, 0, 0 }
comboDB.general.classPowerColorOverrides = { COMBO_POINTS = gold, CHARGED = green }
comboDB.general.classPowerBgColorOverrides = { COMBO_POINTS = black }
local comboPlayer = combo.env.CreateFrame("Frame", nil, combo.env.UIParent)
comboPlayer:SetSize(200, 30)
combo.UF.frames.player = comboPlayer
combo.core.Require("MSUF_ClassPower_Refresh", "combo points test")()
combo:EnterCombat()

local slots = {}
for _, frame in ipairs(combo.widgets.frames) do
    local parent = frame:GetParent()
    if frame:GetObjectType() == "StatusBar" and frame:IsShown()
        and parent and parent:GetName() == "MSUF_ClassPowerContainer" then
        slots[#slots + 1] = frame
    end
end
assert(#slots == 7, "expected seven combo point slots, got " .. #slots)
local function CheckComboPoints(expected)
    for index, slot in ipairs(slots) do
        assert(slot:GetValue() == (index <= expected and 1 or 0),
            ("expected %d filled combo points, slot %d painted incorrectly"):format(expected, index))
    end
end

CheckComboPoints(6)
points = 0
combo.world:FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
CheckComboPoints(0)
points = 2
combo.world:FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")
CheckComboPoints(0)
combo.world:FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
CheckComboPoints(2)
print("PASS Retail combo points repaint on the native power event")

local function CheckComboColor(index, fill, background)
    local slot = slots[index]
    local r, g, b = slot:GetStatusBarColor()
    assert(r == fill[1] and g == fill[2] and b == fill[3], "unexpected combo fill on slot " .. index)
    r, g, b = slot._bg:GetVertexColor()
    assert(r == background[1] and g == background[2] and b == background[3],
        "unexpected combo background on slot " .. index)
end
for i = 1, #slots do CheckComboColor(i, gold, black) end
charged = { 1, 4 }
combo.world:FireEvent("UNIT_POWER_POINT_CHARGE", "player")
CheckComboColor(1, green, black)
CheckComboColor(2, gold, black)
-- The ordinary UI still marks an unfilled but publicly charged slot.
CheckComboColor(4, green, { green[1] * 0.45, green[2] * 0.45, green[3] * 0.45 })

points, charged = Secrets.New("number"), Secrets.New("table")
local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Segmented.lua", { strict = true })
combo.world:FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
assert(#stop() == 0, "Combo Points renderer inspected the restricted count")
for i, slot in ipairs(slots) do
    local left, right = slot:GetMinMaxValues()
    assert(left == i - 1 and right == i and rawequal(slot:GetValue(), points), "native combo range/value lost")
    CheckComboColor(i, gold, black)
end

combo.world:FireEvent("UNIT_POWER_POINT_CHARGE", "player")
points, charged = 2, { 2 }
combo.world:FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
CheckComboPoints(2)
CheckComboColor(1, gold, black)
CheckComboColor(2, green, black)

charged = { 1, Secrets.New("number") }
combo.world:FireEvent("UNIT_POWER_POINT_CHARGE", "player")
CheckComboPoints(2)
CheckComboColor(1, green, black)
CheckComboColor(2, gold, black)
print("PASS Retail combo points use public charge colours and clear stale tint on restriction")
