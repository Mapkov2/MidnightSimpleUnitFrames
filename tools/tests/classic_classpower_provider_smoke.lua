local repo = assert(arg[1], "repo root required")

function UnitClass() return "Mage", "MAGE" end
function UnitPower(_, powerType)
    if powerType == 0 then return 99 end
    return 0
end
function GetComboPoints() return 3 end

local addonName = "MidnightSimpleUnitFrames"
local namespace = {}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/ClassPower/MSUF_CP_Constants.lua"))(addonName, namespace)
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
assert(powerType == PT.Chi and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "WARLOCK", 2)
assert(powerType == PT.DemonicFury and mode == MODE.CONTINUOUS)
powerType, mode = resolve(mists, "WARLOCK", 3)
assert(powerType == PT.BurningEmbers and mode == MODE.FRACTIONAL)
powerType, mode = resolve(mists, "WARLOCK", 1, nil, nil, true)
assert(powerType == PT.SoulShards and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "DRUID", 2, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(mists, "DRUID", 1, PT.Mana, nil)
assert(powerType == PT.Balance and mode == MODE.SIGNED_CONTINUOUS)
powerType, mode = resolve(mists, "WARRIOR", 1)
assert(powerType == nil and mode == MODE.NONE)

local tbcNamespace = {}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/TBC/ClassPower.lua"))(addonName, tbcNamespace)
local tbc = assert(tbcNamespace.CPClient)
assert(tbc.UseFrequentPower(PT.ComboPoints, MODE.SEGMENTED) == true)
assert(tbc.NeedsTargetChanged(PT.ComboPoints) == true)
powerType, mode = resolve(tbc, "ROGUE", nil, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(tbc, "PALADIN", nil, PT.Mana)
assert(powerType == nil and mode == MODE.NONE)

local vanillaNamespace = {}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Vanilla/ClassPower.lua"))(addonName, vanillaNamespace)
local vanilla = assert(vanillaNamespace.CPClient)
assert(vanilla.Flavor == "Vanilla")
assert(vanilla.UnitPower("player", PT.ComboPoints) == 3, "Vanilla combo points did not use GetComboPoints")
powerType, mode = resolve(vanilla, "ROGUE", nil, PT.Energy)
assert(powerType == PT.ComboPoints and mode == MODE.SEGMENTED)
powerType, mode = resolve(vanilla, "PALADIN", nil, PT.Mana)
assert(powerType == nil and mode == MODE.NONE)

print("client ClassPower providers smoke passed")
