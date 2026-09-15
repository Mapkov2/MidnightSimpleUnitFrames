local root = assert(arg[1], "repository root argument missing")

-- apiIndex: what the client's specialization API answers.
-- points: pointsSpent per talent tab; tabInfoShape selects how the client reports it:
--   "c"      C_SpecializationInfo.GetSpecializationInfo, pointsSpent is the 7th return
--   "shim"   GetTalentTabInfo deprecation shim (specId, name, description, icon, pointsSpent)
--   "legacy" GetTalentTabInfo (name, texture, pointsSpent)
-- client: optional ns.Client override; flavor then only picks the data file.
local function LoadFlavor(flavor, classToken, apiIndex, points, tabInfoShape, client)
    local namespace = {
        Client = client or {
            IsMists = flavor == "Mists",
            IsTBC = flavor == "TBC",
            IsVanilla = flavor == "Vanilla",
            IsSupported = true,
        },
        GF = { SpellIndicators = {} },
        ExportPublic = function(_, value) return value end,
    }
    _G.MSUF_NS = namespace
    _G.UnitClass = function() return classToken, classToken end
    _G.GetSpecialization = nil
    _G.C_SpecializationInfo = nil
    _G.GetNumTalentTabs = nil
    _G.GetTalentTabInfo = nil
    if flavor == "Mists" then
        _G.GetSpecialization = function() return apiIndex end
    else
        -- Vanilla/TBC ship no global GetSpecialization; the namespaced API exists.
        _G.GetNumTalentTabs = function() return 3 end
        local specInfo = {
            GetSpecialization = function() return apiIndex end,
        }
        _G.C_SpecializationInfo = specInfo
        local tabPoints = points or {}
        if tabInfoShape == "c" then
            specInfo.GetSpecializationInfo = function(tab)
                return 100 + tab, "Tree " .. tab, "Description", 1000 + tab, "DAMAGER", "Stat", tabPoints[tab]
            end
        elseif tabInfoShape == "shim" then
            _G.GetTalentTabInfo = function(tab)
                return 100 + tab, "Tree " .. tab, "Description", 1000 + tab, tabPoints[tab]
            end
        elseif tabInfoShape == "legacy" then
            _G.GetTalentTabInfo = function(tab)
                return "Tree " .. tab, "Interface\\Icons\\Tree" .. tab, tabPoints[tab]
            end
        end
    end
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

-- Vanilla keys one combined set per class: a talent-tree index from the API must not leak in.
for _, apiIndex in ipairs({ 1, 3 }) do
    local era = LoadFlavor("Vanilla", "DRUID", apiIndex)
    assert(era.GetPlayerSpec() == "ClassicDruid",
        "Vanilla spec must ignore specialization API index " .. apiIndex)
end

-- TBC falls back to the dominant talent tree whenever the API index is unmapped or nil.
local tbcCases = {
    { apiIndex = 0, shape = "c", points = { 5, 0, 41 } },
    { apiIndex = nil, shape = "c", points = { 0, 0, 31 } },
    { apiIndex = nil, shape = "shim", points = { 0, 0, 21 } },
    { apiIndex = nil, shape = "legacy", points = { 0, 0, 11 } },
}
for _, case in ipairs(tbcCases) do
    local talents = LoadFlavor("TBC", "DRUID", case.apiIndex, case.points, case.shape)
    assert(talents.GetPlayerSpec() == "RestorationDruid",
        "TBC dominant talent tree not resolved for api " .. tostring(case.apiIndex)
            .. " shape " .. case.shape)
end

local unmappedPriest = LoadFlavor("TBC", "PRIEST", 7, { 30, 1, 0 }, "c")
assert(unmappedPriest.GetPlayerSpec() == "DisciplinePriest",
    "TBC unmapped API index must fall back to the dominant talent tree")
local mappedPriest = LoadFlavor("TBC", "PRIEST", 2, { 30, 1, 0 }, "c")
assert(mappedPriest.GetPlayerSpec() == "HolyPriest",
    "TBC mapped API index must win over the dominant talent tree")

-- Vanilla Shaman ships the ElvUI Classic aura-watch baseline.
local shaman = LoadFlavor("Vanilla", "SHAMAN", nil)
assert(shaman.GetPlayerSpec() == "ClassicShaman", "Vanilla Shaman class fallback map missing")
assert(shaman.SpellIDs.ClassicShaman.HealingWay == 29203, "Vanilla Healing Way missing")
assert(shaman.SpellIDs.ClassicShaman.AncestralFortitude == 16237, "Vanilla Ancestral Fortitude missing")
assert(#shaman.TrackableAuras.ClassicShaman == 2, "Vanilla Shaman must expose two trackable auras")
local shamanDefaults = shaman.SpecDefaults.ClassicShaman
assert(shamanDefaults.HealingWay and shamanDefaults.HealingWay.placed.anchor == "TOPLEFT",
    "Vanilla Healing Way factory placement missing")
assert(shamanDefaults.AncestralFortitude and shamanDefaults.AncestralFortitude.placed.anchor == "TOPRIGHT",
    "Vanilla Ancestral Fortitude factory placement missing")

-- No registered Vanilla spec may be empty, and every trackable aura must
-- resolve to a spell ID and a factory placement.
local vanillaSpecCount = 0
for specKey, info in pairs(vanilla.SpecInfo) do
    vanillaSpecCount = vanillaSpecCount + 1
    local trackables = vanilla.TrackableAuras[specKey]
    assert(type(trackables) == "table" and #trackables >= 1,
        "Vanilla spec " .. specKey .. " (" .. tostring(info.class) .. ") has no trackable aura")
    for _, aura in ipairs(trackables) do
        assert(type((vanilla.SpellIDs[specKey] or {})[aura.name]) == "number",
            "Vanilla " .. specKey .. " trackable " .. aura.name .. " has no spell ID")
        assert(type((vanilla.SpecDefaults[specKey] or {})[aura.name]) == "table",
            "Vanilla " .. specKey .. " trackable " .. aura.name .. " has no factory default")
    end
end
assert(vanillaSpecCount >= 4, "Vanilla spell-indicator spec registry shrank")

-- An unplaced client (IsSupported false) cannot trust a specialization index:
-- whatever the API answers, it resolves the class-wide index-0 set.
local unplacedCases = { { apiIndex = nil }, { apiIndex = 1 }, { apiIndex = 3 } }
for _, case in ipairs(unplacedCases) do
    local unplaced = LoadFlavor("Vanilla", "DRUID", case.apiIndex, nil, nil, { IsSupported = false })
    assert(unplaced.GetPlayerSpec() == "ClassicDruid",
        "unplaced client must resolve spec index 0 for api " .. tostring(case.apiIndex))
end

print("classic group indicator data smoke passed")
