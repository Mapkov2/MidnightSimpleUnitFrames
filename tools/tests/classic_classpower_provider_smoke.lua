local repo = assert(arg[1], "repo root required")

function UnitClass() return "Mage", "MAGE" end
function UnitPower(_, powerType)
    if powerType == 0 then return 99 end
    return 0
end
function GetComboPoints(unit)
    if unit == "vehicle" then return 4 end
    return 3
end
function UnitPowerDisplayMod() return 100 end

local addonName = "MidnightSimpleUnitFrames"
-- A Classic client, so the shared constants carry the Classic power ids and modes.
local namespace = { ExportPublic = function(name, value) _G[name] = value end, Client = { IsClassic = true } }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Constants.lua"))(addonName, namespace)
-- Every provider is built from the shared target-combo module.
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua"))(addonName, namespace)
local K = assert(MSUF_CP_CONST)
local MODE, PT = K.CPK.MODE, K.PT

assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Mists/ClassPower.lua"))(addonName, namespace)
local mists = assert(namespace.CPClient)
assert(mists.Flavor == "Mists")
assert(mists.UnitPower("player", PT.ComboPoints) == 3, "Mists combo points did not use GetComboPoints")
assert(mists.UnitPower("player", PT.Mana) == 99, "Mists native power delegation failed")
assert(mists.UseFrequentPower(PT.ComboPoints, MODE.SEGMENTED) == true)
assert(mists.NeedsTargetChanged(PT.ComboPoints) == true)
assert(mists.AcceptPowerToken(PT.ComboPoints, "ENERGY", "COMBO_POINTS", "ROGUE") == true)
assert(mists.AcceptPowerToken(PT.ComboPoints, "MANA", "COMBO_POINTS", "ROGUE") == false)
assert(mists.UnitPowerDisplayMod(PT.BurningEmbers) == 10,
    "Mists Burning Embers must use the 10-per-ember scale")
assert(mists.UnitPowerDisplayMod(PT.SoulShards) == 100,
    "Mists display modifier did not delegate to the client")
assert(mists.StructuralEvents == nil, "only Mists Warlocks bind extra structural events")

local function resolve(provider, playerClass, spec, primaryPower, formID, spellKnown)
    local handled, powerType, mode, aura = provider.Resolve({
        playerClass = playerClass,
        spec = spec,
        primaryPower = primaryPower,
        formID = formID,
        inVehicle = false,
        vehicleHasCombo = false,
        isPlayerSpell = function() return spellKnown == true end,
    })
    assert(handled == true, "client provider did not own resolution")
    return powerType, mode, aura
end

local powerType, mode, aura = resolve(mists, "MAGE", 1)
assert(powerType == "MISTS_ARCANE_CHARGES" and mode == MODE.AURA_SEGMENTED and aura == true)
powerType, mode = resolve(mists, "PRIEST", 3)
assert(powerType == PT.ShadowOrbs and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "MONK", 2)
assert(powerType == PT.Chi and mode == MODE.SEGMENTED,
    "Mists Mistweaver Chi resolution regressed")
powerType, mode = resolve(mists, "MONK", 3)
assert(powerType == PT.Chi and mode == MODE.SEGMENTED,
    "Mists Windwalker Chi resolution regressed")
powerType, mode = resolve(mists, "WARLOCK", 2)
assert(powerType == PT.DemonicFury and mode == MODE.CONTINUOUS)
-- Blizzard's Mists ShardBar shows embers only once Burning Embers is known.
powerType, mode = resolve(mists, "WARLOCK", 3, nil, nil, true)
assert(powerType == PT.BurningEmbers and mode == MODE.FRACTIONAL)
powerType, mode = resolve(mists, "WARLOCK", 3)
assert(powerType == nil and mode == MODE.NONE, "Burning Embers skipped their spell gate")
powerType, mode = resolve(mists, "WARLOCK", 1, nil, nil, true)
assert(powerType == PT.SoulShards and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "DRUID", 2, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "DRUID", 1, PT.Mana, nil)
assert(powerType == PT.Balance and mode == MODE.SIGNED_CONTINUOUS)
powerType, mode = resolve(mists, "WARRIOR", 1)
assert(powerType == nil and mode == MODE.NONE)
local vehicleHandled, vehiclePower, vehicleMode = mists.Resolve({
    playerClass = "WARRIOR",
    spec = 1,
    inVehicle = true,
    vehicleHasCombo = true,
    isPlayerSpell = function() return false end,
})
assert(vehicleHandled == true and vehiclePower == PT.ComboPoints and vehicleMode == MODE.SEGMENTED)
assert(mists.UnitPower("player", PT.ComboPoints) == 4,
    "Mists vehicle combo points did not read the vehicle unit")
resolve(mists, "ROGUE", 1, PT.Energy)
assert(mists.UnitPower("player", PT.ComboPoints) == 3,
    "Mists combo points stayed on the vehicle after the vehicle route ended")

local tbcNamespace = { ExportPublic = namespace.ExportPublic }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua"))(addonName, tbcNamespace)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/TBC/ClassPower.lua"))(addonName, tbcNamespace)
local tbc = assert(tbcNamespace.CPClient)
assert(tbc.UseFrequentPower(PT.ComboPoints, MODE.SEGMENTED) == true)
assert(tbc.NeedsTargetChanged(PT.ComboPoints) == true)
powerType, mode = resolve(tbc, "ROGUE", nil, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(tbc, "PALADIN", nil, PT.Mana)
assert(powerType == nil and mode == MODE.NONE)

local vanillaNamespace = { ExportPublic = namespace.ExportPublic }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua"))(addonName, vanillaNamespace)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Vanilla/ClassPower.lua"))(addonName, vanillaNamespace)
local vanilla = assert(vanillaNamespace.CPClient)
assert(vanilla.Flavor == "Vanilla")
assert(vanilla.UnitPower("player", PT.ComboPoints) == 3, "Vanilla combo points did not use GetComboPoints")
powerType, mode = resolve(vanilla, "ROGUE", nil, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(vanilla, "PALADIN", nil, PT.Mana)
assert(powerType == nil and mode == MODE.NONE)

-- Forever's GetComboPoints is SecretWhenUnitPowerRestricted: the reader hands a
-- secret on untouched instead of testing it with `or 0`.
do
    local handle = assert(io.open(repo .. "/MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua", "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local read = source:find('local points = GetComboPoints(comboUnit, "target")', 1, true)
    local guard = read and source:find("if issecretvalue and issecretvalue(points) then return points end", read, true)
    local fallback = guard and source:find("return points or 0", guard, true)
    assert(read and guard and fallback and not source:find('GetComboPoints(comboUnit, "target") or 0', 1, true),
        "the combo point reader must test a secret before its `or 0` fallback")
end

print("client ClassPower providers smoke passed")
