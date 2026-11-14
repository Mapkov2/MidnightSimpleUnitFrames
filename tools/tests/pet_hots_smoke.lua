-- Exercise the shipped Pet HoT compilers and the group pet binding on each client.
local root, flavor = assert(arg[1]), assert(arg[2])
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, flavor):Boot()
local failure = world:FirstFailure()
assert(not failure, failure and (failure.file .. ": " .. failure.message))
world:LoadSavedVariables("MidnightSimpleUnitFrames")

local core = world.core
local aura = core.MSUF_Auras3
aura.EnsureDB()
local pet = world.env.MSUF_DB.pet
assert(not aura.ResolveUnitFrameConfig("pet").lanes.petHoTs, "HoTs must default off")

local function ResolveOwn(onlyMine)
    pet.petHoTsEnabled, pet.petHoTsOnlyMine = true, onlyMine
    aura.InvalidateUnitRuntimeConfig("pet")
    return assert(aura.ResolveUnitFrameConfig("pet").lanes.petHoTs)
end

local function CheckLane(lane, unit, onlyMine)
    assert(lane.unit == unit and lane.showCooldownText and lane.showCooldownSwipe)
    local ids = lane.includeSpellIDs or lane.candidateFilters.includeSpellIDs
    assert(ids[136] and ids[774] and ids[139], "missing baseline pet heals")
    assert(not ids[17] and not ids[1459], "unrelated buffs passed the HoT catalog")
    if core.Client.IsClassic then
        assert(lane.onlyMine == onlyMine and lane.harmful == false and lane.hidePermanent)
    else
        assert(lane.nativeFilter == (onlyMine and "HELPFUL|PLAYER" or "HELPFUL"))
    end
end

CheckLane(ResolveOwn(false), "pet", false)
CheckLane(ResolveOwn(true), "pet", true)
pet.petHoTsEnabled = false
aura.InvalidateUnitRuntimeConfig("pet")
assert(not aura.ResolveUnitFrameConfig("pet").lanes.petHoTs, "HoT lane survived disabling")

local compiler = core.Client.IsClassic and aura.ClassicFeatures or aura.Runtime.CustomConfig
local size, limit, reserved = aura.GetGroupPetHoTGeometry(100, 24)
assert(size >= 8 and limit > 1 and reserved < 100)
local frame = {}
local party = aura.ResolveGroupPetHoTConfig(frame, "partypet1", true, size, limit, compiler.CompilePetHoTs)
CheckLane(party.lanes.petHoTs, "partypet1", true)
assert(aura.ResolveGroupPetHoTConfig(frame, "partypet1", true, size, limit, compiler.CompilePetHoTs) == party)
local raid = aura.ResolveGroupPetHoTConfig(frame, "raidpet15", false, size, limit, compiler.CompilePetHoTs)
assert(raid ~= party)
CheckLane(raid.lanes.petHoTs, "raidpet15", false)
-- Secure header children call the same binding when the unit attribute
-- changes, including when a previously visible row is recycled.
local host = world.env.CreateFrame("Frame")
host._msufAdditionalKind, host._msufAdditionalPrefix = "party", "pets"
host._msufPetHoTSize, host._msufPetHoTLimit = size, limit
host._msufPetHoTReservedWidth = reserved
local button = world.env.CreateFrame("Button", nil, host)
button.Health = world.env.CreateFrame("StatusBar", nil, button)
button.Name = button.Health:CreateFontString()
local configure = aura.ConfigureGroupPetHoTs
local calls = {}
aura.ConfigureGroupPetHoTs = function(self, unit, _, _, _, identityChanged)
    calls[#calls + 1] = { unit = unit, identityChanged = identityChanged }
    self._msufPetHoTConfig = unit and true or nil
end
core.GF.AdditionalUnitOnLoad(button)
button:GetScript("OnAttributeChanged")(button, "unit", "partypet1")
assert(button.events.UNIT_PET and (button.events.UNIT_AURA == true) == core.Client.IsClassic)
assert(calls[#calls].unit == "partypet1")
button:GetScript("OnEvent")(button, "UNIT_PET", "party1")
assert(calls[#calls].unit == "partypet1" and calls[#calls].identityChanged == true)
button:GetScript("OnAttributeChanged")(button, "unit", "raidpet1")
assert(calls[#calls].unit == "raidpet1")
button:GetScript("OnAttributeChanged")(button, "unit", nil)
assert(calls[#calls].unit == nil and not button.events.UNIT_PET and not button.events.UNIT_AURA)
aura.ConfigureGroupPetHoTs = configure
print("Pet HoT scope, filtering, duration and group rebinding passed for " .. flavor)
