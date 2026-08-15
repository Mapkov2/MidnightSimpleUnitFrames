local root = assert(arg[1], "repository root argument missing")

local function LoadFlavor(flavor, classToken, specIndex)
    local namespace = {
        Client = { IsVanilla = flavor == "Vanilla" },
        GF = { SpellIndicators = {} },
        ExportPublic = function(_, value) return value end,
    }
    _G.MSUF_NS = namespace
    _G.UnitClass = function() return classToken, classToken end
    _G.GetSpecialization = function() return specIndex end
    _G.C_Spell = {
        GetSpellName = function(id) return "Spell " .. tostring(id) end,
        GetSpellTexture = function(id) return id + 100000 end,
    }

    local base = root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/Group/MSUF_UF_Group_SpellIndicators_Data_Base.lua"
    local data = root .. "/MidnightSimpleUnitFrames/Game/" .. flavor
        .. "/UnitFrames/Group/MSUF_UF_Group_SpellIndicators_Data.lua"
    assert(loadfile(base))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(data))("MidnightSimpleUnitFrames", namespace)
    return namespace.GF.SpellIndicators
end

local mists = LoadFlavor("Mists", "DRUID", 4)
assert(mists.GetPlayerSpec() == "RestorationDruid", "Mists Restoration spec map missing")
assert(mists.SpellIDs.RestorationDruid.Ironbark == 102342, "Mists Ironbark missing")
assert(mists.SpellIDs.MistweaverMonk.RenewingMist == 119611, "Mists Renewing Mist missing")
assert(mists.SpecInfo.PreservationEvoker == nil, "Retail Evoker leaked into Mists data")
assert(mists.BuildReverseLookup("RestorationShaman")[105284] == "AncestralVigor",
    "Mists reverse indicator lookup missing")

local tbc = LoadFlavor("TBC", "DRUID", 3)
assert(tbc.GetPlayerSpec() == "RestorationDruid", "TBC talent-tab spec map missing")
assert(tbc.SpellIDs.RestorationDruid.Lifebloom == 33763, "TBC Lifebloom missing")
assert(tbc.SpellIDs.DisciplinePriest.PainSuppression == 33206, "TBC Pain Suppression missing")
assert(tbc.SpecInfo.MistweaverMonk == nil and tbc.SpecInfo.PreservationEvoker == nil,
    "later-client class data leaked into TBC")
assert(tbc.ExternalDefensiveAuras.HolyPaladin.BlessingOfProtection == true,
    "TBC external defensive classification missing")

local vanilla = LoadFlavor("Vanilla", "DRUID", nil)
assert(vanilla.GetPlayerSpec() == "ClassicDruid", "Vanilla class fallback map missing")
assert(vanilla.SpellIDs.ClassicDruid.Rejuvenation == 774, "Vanilla Rejuvenation missing")
assert(vanilla.SpellIDs.ClassicPriest.PainSuppression == nil,
    "TBC Priest defensive leaked into Vanilla data")
assert(vanilla.ExternalDefensiveAuras.ClassicPaladin.BlessingOfProtection == true,
    "Vanilla external defensive classification missing")

print("classic group indicator data smoke passed")
