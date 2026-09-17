-- WoW Forever group frames smoke.
--
--   lua tools/tests/forever_group_frames_smoke.lua <repo root>
--
-- WoW Forever loads the Mainline group engine, but its game data is Classic Era
-- with ranks: nine classes with one specialization each, no global
-- GetSpecialization (Blizzard_DeprecatedSpecialization is classic/standard
-- only), roles set only by hand, and Classic 10/20/40-player raid difficulties.
--
-- Forever (MSUF.Client.IsForever == true):
--   * UnitFrames/Engine/Group/MSUF_UF_Group_SpellIndicators_Data.lua resolves a
--     class-wide spec ("Classic<Class>", index 0) without any specialization API,
--     lists only the verified 1.60.1.69876 aura IDs with every trainer rank, and
--     compiles them into native includeSpellIDs slots.
--   * GroupFrames/MSUF_GroupFrames_DB.lua shows an unassigned member's power bar
--     whenever the scope shows power for any role, and files every raid instance
--     under the "normal" raid layout.
-- Retail (no Client, or IsForever false) keeps the Retail spec map, data, power
-- role filter and raid situations unchanged.
local root = assert(arg[1], "repository root argument missing")
local core = root .. "/MidnightSimpleUnitFrames/"

local FOREVER = { IsForever = true, IsRetail = true, IsClassic = false }
local RETAIL = { IsForever = false, IsRetail = true, IsClassic = false }

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function LoadSpellIndicators(client, classToken, specIndex)
    _G.MSUF_GF_SpellIndicators = nil
    _G.MSUF_GF_CopySpellConfig = nil
    _G.MSUF_NormalizeFrameStrata = function(value, fallback) return value or fallback end
    _G.UnitClass = function() return classToken, classToken end
    _G.GetSpecialization = specIndex and function() return specIndex end or nil
    _G.GetSpecializationInfo = nil
    _G.C_SpecializationInfo = nil
    _G.C_Spell = {
        GetSpellName = function(id) return "Spell " .. tostring(id) end,
        GetSpellTexture = function(id) return 100000 + id end,
    }
    local namespace = {
        Client = client,
        GF = {},
        ExportPublic = function(name, value) _G[name] = value; return value end,
    }
    for _, path in ipairs({
        "UnitFrames/Engine/Group/MSUF_UF_Group_SpellIndicators_Data.lua",
        "UnitFrames/Engine/Group/MSUF_UF_Group_SpellRegistry.lua",
        "UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua",
    }) do
        assert(loadfile(core .. path))("MidnightSimpleUnitFrames", namespace)
    end
    return namespace.GF, namespace.GF.SpellIndicators
end

local function IdSet(si, specKey, auraName)
    local set, count = {}, 0
    local base = si.SpellIDs[specKey] and si.SpellIDs[specKey][auraName]
    if base then set[base], count = true, count + 1 end
    for id, name in pairs(si.AltSpellIDs[specKey] or {}) do
        if name == auraName then set[id], count = true, count + 1 end
    end
    return set, count
end

-- Verified against wago.tools DB2 build 1.60.1.69876 (SpellName, SpellEffect
-- APPLY_AURA, SkillLineAbility class line). First ID is the SpellIDs entry.
local FOREVER_AURAS = {
    ClassicDruid = {
        Rejuvenation = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
        Regrowth = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
    },
    ClassicShaman = {
        AncestralFortitude = { 16177 },
    },
    ClassicPriest = {
        PowerWordShield = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
        Renew = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },
        PowerInfusion = { 10060 },
    },
    ClassicPaladin = {
        BlessingOfProtection = { 1022, 5599, 10278 },
        BlessingOfSacrifice = { 6940, 20729 },
        BlessingOfFreedom = { 1044 },
    },
}

local FOREVER_CLASSES = {
    { "WARRIOR", "ClassicWarrior", 1491, false },
    { "PALADIN", "ClassicPaladin", 1486, true },
    { "PRIEST", "ClassicPriest", 1487, true },
    { "SHAMAN", "ClassicShaman", 1489, true },
    { "DRUID", "ClassicDruid", 1484, true },
    { "ROGUE", "ClassicRogue", 1488, false },
    { "MAGE", "ClassicMage", 1482, false },
    { "WARLOCK", "ClassicWarlock", 1490, false },
    { "HUNTER", "ClassicHunter", 1485, false },
}

-- IDs that must never reach Forever: Era-only Healing Way / Ancestral Fortitude
-- ranks absent from 69876, and Retail-only healer auras.
local NOT_ON_FOREVER = { 29203, 16236, 16237, 33763, 61295, 53563, 41635, 194384, 383648, 425268 }

---------------------------------------------------------------------------
-- Forever spell-indicator data model
---------------------------------------------------------------------------
do
    local _, si = LoadSpellIndicators(FOREVER, "DRUID", nil)
    local specCount = 0
    for _ in pairs(si.SpecInfo) do specCount = specCount + 1 end
    Check(specCount == #FOREVER_CLASSES + 1, "Forever SpecInfo must hold the nine classes plus All Specs, got " .. specCount)
    Check(si.SpecInfo[si.ALL_SPECS_KEY] and si.SpecInfo[si.ALL_SPECS_KEY].universal == true,
        "Forever lost the shared Multi-Spec workspace")
    for _, retailKey in ipairs({ "RestorationDruid", "HolyPaladin", "DisciplinePriest", "PreservationEvoker", "MistweaverMonk" }) do
        Check(si.SpecInfo[retailKey] == nil and si.SpellIDs[retailKey] == nil and si.SpecDefaults[retailKey] == nil,
            "Retail spec leaked into Forever data: " .. retailKey)
    end
    for _, row in ipairs(FOREVER_CLASSES) do
        local classToken, specKey, specID, builtIn = row[1], row[2], row[3], row[4]
        local info = si.SpecInfo[specKey]
        Check(info and info.class == classToken and info.specID == specID,
            "Forever class spec missing or wrong: " .. specKey)
        Check((info.customOnly == true) == (not builtIn), "Forever built-in flag wrong for " .. specKey)
        local _, classSi = LoadSpellIndicators(FOREVER, classToken, nil)
        Check(classSi.GetPlayerSpec() == specKey, "Forever class-wide spec not resolved for " .. classToken)
        -- A specialization index from any API must not change the class-wide key.
        local _, indexedSi = LoadSpellIndicators(FOREVER, classToken, 3)
        Check(indexedSi.GetPlayerSpec() == specKey, "Forever spec must ignore a specialization index for " .. classToken)
    end

    for specKey, auras in pairs(FOREVER_AURAS) do
        local trackables = si.TrackableAuras[specKey]
        Check(type(trackables) == "table", "Forever trackables missing for " .. specKey)
        local expectedCount = 0
        for auraName, ids in pairs(auras) do
            expectedCount = expectedCount + 1
            Check(si.SpellIDs[specKey][auraName] == ids[1], "Forever base aura ID wrong: " .. specKey .. "." .. auraName)
            local set, count = IdSet(si, specKey, auraName)
            Check(count == #ids, "Forever rank count wrong for " .. specKey .. "." .. auraName .. ": " .. count)
            for _, id in ipairs(ids) do
                Check(set[id], "Forever rank missing: " .. specKey .. "." .. auraName .. " " .. id)
            end
            Check(type(si.SpecDefaults[specKey][auraName]) == "table", "Forever factory default missing: " .. auraName)
        end
        Check(#trackables == expectedCount, "Forever trackable count wrong for " .. specKey)
        for _, aura in ipairs(trackables) do
            Check(auras[aura.name] ~= nil and aura.secret == nil, "unexpected Forever trackable " .. specKey .. "." .. tostring(aura.name))
        end
        for auraName in pairs(si.SpecDefaults[specKey]) do
            Check(auras[auraName] ~= nil, "Forever default without trackable: " .. specKey .. "." .. auraName)
        end
        for _, name in pairs(si.AltSpellIDs[specKey] or {}) do
            Check(auras[name] ~= nil, "Forever rank maps to an unknown aura: " .. specKey .. "." .. tostring(name))
        end
    end
    for specKey in pairs(si.SpellIDs) do Check(FOREVER_AURAS[specKey], "unexpected Forever SpellIDs spec " .. specKey) end
    for specKey in pairs(si.SpecDefaults) do Check(FOREVER_AURAS[specKey], "unexpected Forever SpecDefaults spec " .. specKey) end

    local everyID = {}
    for _, registry in ipairs({ si.SpellIDs, si.SecretSpellIDs }) do
        for _, ids in pairs(registry) do
            for _, id in pairs(ids) do everyID[id] = true end
        end
    end
    for _, alts in pairs(si.AltSpellIDs) do
        for id in pairs(alts) do everyID[id] = true end
    end
    for _, id in ipairs(NOT_ON_FOREVER) do
        Check(not everyID[id], "ID absent from Forever 1.60.1.69876 shipped in Forever data: " .. id)
    end
    Check(si.SpellIDs.ClassicShaman.HealingWay == nil, "Healing Way buff does not exist on Forever")
    Check(next(si.ExternalDefensiveAuras) == nil, "Forever must not depend on EXTERNAL_DEFENSIVE classification")
    Check(next(si.SecretSpellIDs) == nil and next(si.SecretAuraInfo) == nil, "Retail secret aura data leaked into Forever")
    Check(next(si.IconTextures) == nil, "Forever icons must come from C_Spell.GetSpellTexture")
    Check(next(si.AuraSpellIDAliases) == nil and si.CustomAuraAliases == si.AuraSpellIDAliases,
        "Retail custom aura aliases leaked into Forever")
    Check(next(si.SelfOnlySpellIDs) == nil and next(si.LinkedAuraRules) == nil, "Retail linked aura rules leaked into Forever")
    Check(si.GetAuraIcon("ClassicPriest", "Renew") == 100139, "Forever aura icon must come from the client spell texture")
    local reverse = si.BuildReverseLookup("ClassicDruid")
    Check(reverse[25299] == "Rejuvenation" and reverse[9858] == "Regrowth", "Forever reverse rank lookup missing")
end

---------------------------------------------------------------------------
-- Forever compile: auto spec -> native exact-ID slots with every rank
---------------------------------------------------------------------------
do
    local gf, si = LoadSpellIndicators(FOREVER, "DRUID", nil)
    local compiled = gf.CompileSpellIndicators({ spellIndicators = { enabled = true, spec = "auto", specs = {} } })
    Check(compiled.enabled == true and compiled.activeSpec == "ClassicDruid", "Forever auto spec did not compile ClassicDruid")
    Check(#compiled.items == 2, "Forever druid should compile two built-in indicators, got " .. #compiled.items)
    for _, item in ipairs(compiled.items) do
        local expected = FOREVER_AURAS.ClassicDruid[item.auraName]
        Check(expected and #item.spellIDs == #expected, "Forever compiled rank list wrong for " .. tostring(item.auraName))
        for _, id in ipairs(expected) do
            Check(item.includeSpellIDs[id] == true, "Forever compiled include hash lacks rank " .. id)
        end
        Check(item.nativeFilter == nil and item.externalDefensive == false, "Forever built-in must use plain exact-ID matching")
    end

    local paladinGF = LoadSpellIndicators(FOREVER, "PALADIN", nil)
    local paladin = paladinGF.CompileSpellIndicators({ spellIndicators = { enabled = true, spec = "auto", specs = {} } })
    Check(#paladin.items == 3, "Forever paladin should compile three blessings")
    for _, item in ipairs(paladin.items) do
        Check(item.nativeFilter == nil and item.frame ~= nil, "Forever blessing must be an exact-ID frame effect")
    end

    local warriorGF = LoadSpellIndicators(FOREVER, "WARRIOR", nil)
    local warrior = warriorGF.CompileSpellIndicators({ spellIndicators = { enabled = true, spec = "auto", specs = {} } })
    Check(warrior.activeSpec == "ClassicWarrior" and #warrior.items == 0, "Forever DPS class must resolve with no built-ins")
    local custom = warriorGF.CompileSpellIndicators({ spellIndicators = { enabled = true, spec = "auto", specs = {
        ClassicWarrior = { ["2687"] = { enabled = true, custom = true, placed = { type = "icon", anchor = "TOPLEFT" } } },
    } } })
    Check(#custom.items == 1 and custom.items[1].includeSpellIDs[2687] == true, "Forever DPS class custom aura did not compile")
    -- The druid module's cached key must follow the class UnitClass now reports.
    Check(si.GetPlayerSpec() == "ClassicWarrior", "Forever spec cache must follow the player class")
    _G.UnitClass = function() return "DRUID", "DRUID" end
    Check(si.GetPlayerSpec() == "ClassicDruid", "Forever spec cache must re-resolve after a class change")
end

---------------------------------------------------------------------------
-- Retail spell-indicator data unchanged
---------------------------------------------------------------------------
for _, client in ipairs({ false, RETAIL }) do
    local label = client and "IsForever=false" or "no Client"
    local gf, si = LoadSpellIndicators(client or nil, "DRUID", 4)
    Check(si.GetPlayerSpec() == "RestorationDruid", label .. ": Retail spec map changed")
    Check(si.SpecInfo.ClassicDruid == nil, label .. ": Forever data leaked into Retail")
    Check(si.SpellIDs.RestorationDruid.Lifebloom == 33763, label .. ": Retail Lifebloom changed")
    Check(si.IconTextures.Rejuvenation == 136081, label .. ": Retail icon table changed")
    Check(si.ExternalDefensiveAuras.HolyPaladin.BlessingOfProtection == true, label .. ": Retail external classification changed")
    Check(si.AltSpellIDs.RestorationShaman[974] == "EarthShield", label .. ": Retail alt IDs changed")
    local compiled = gf.CompileSpellIndicators({ spellIndicators = { enabled = true, spec = "auto", specs = {} } })
    Check(compiled.activeSpec == "RestorationDruid" and #compiled.items == 8, label .. ": Retail compile changed")
    local _, noSpec = LoadSpellIndicators(client or nil, "DRUID", nil)
    Check(noSpec.GetPlayerSpec() == nil, label .. ": Retail spec without GetSpecialization must stay nil")
end

---------------------------------------------------------------------------
-- Group DB: power bars for unassigned roles, raid layout situation
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local ROLES = { party1 = "NONE", party2 = "HEALER", party3 = "DAMAGER", party4 = SECRET, party5 = "TANK" }
local instance = { "", "none", 0 }

local function LoadGroupDB(client)
    _G.issecretvalue = function(value) return value == SECRET end
    _G.UnitGroupRolesAssigned = function(unit) return ROLES[unit] or "NONE" end
    _G.GetInstanceInfo = function() return instance[1], instance[2], instance[3] end
    local namespace = { Client = client, ExportPublic = function(_, value) return value end }
    assert(loadfile(core .. "GroupFrames/MSUF_GroupFrames_DB.lua"))("MidnightSimpleUnitFrames", namespace)
    local gf = namespace.GF
    gf.GetScaledPowerHeight = function() return 6 end
    return gf
end

local function PowerShown(gf, unit, conf, role)
    return gf.ShouldShowPowerBarForUnit("party", unit, conf) == true,
        gf.GetEffectivePowerHeight("party", unit, role, conf) > 0
end

local function Situation(gf, instanceType, difficultyID)
    instance[2], instance[3] = instanceType, difficultyID
    return gf.DetectRaidSituation()
end

do
    local defaults = { powerShowTank = true, powerShowHealer = true, powerShowDamager = false, powerHeight = 6 }
    local allOff = { powerShowTank = false, powerShowHealer = false, powerShowDamager = false, powerHeight = 6 }
    local disabled = { powerBarEnabled = false, powerShowTank = true, powerShowHealer = true, powerShowDamager = true }

    local forever = LoadGroupDB(FOREVER)
    -- Unassigned member: shown by default, through both entry points, even when
    -- the caller already normalized the role to DAMAGER (the Status element).
    local byUnit, byHeight = PowerShown(forever, "party1", defaults, "DAMAGER")
    Check(byUnit and byHeight, "Forever: unassigned member's power bar must show by default")
    byUnit, byHeight = PowerShown(forever, "party1", allOff, nil)
    Check(not byUnit and not byHeight, "Forever: unassigned member must hide when every role hides power")
    Check(forever.ShouldShowPowerBarForRole("party", nil, disabled, "party1") == false,
        "Forever: a disabled power bar must stay hidden")
    byUnit, byHeight = PowerShown(forever, "party2", defaults, nil)
    Check(byUnit and byHeight, "Forever: healer power must show")
    byUnit, byHeight = PowerShown(forever, "party3", defaults, nil)
    Check(not byUnit and not byHeight, "Forever: an assigned DPS keeps the DPS power toggle")
    byUnit, byHeight = PowerShown(forever, "party4", defaults, nil)
    Check(not byUnit and not byHeight, "Forever: a secret role keeps the DAMAGER fallback")
    Check(forever.ShouldShowPowerBarForRole("party", "DAMAGER", defaults) == false,
        "Forever: a role-only preview query keeps the role filter")
    Check(forever.NormalizeGroupRole("NONE") == "DAMAGER", "Forever: role normalization must not change")

    Check(Situation(forever, "raid", 9) == "normal", "Forever: 40-player raid must use the raid layout")
    Check(Situation(forever, "raid", 148) == "normal", "Forever: 20-player raid must use the raid layout")
    Check(Situation(forever, "raid", 242) == "normal", "Forever: RaidClassic20Normal must use the raid layout")
    Check(Situation(forever, "raid", 243) == "normal", "Forever: RaidClassic10Normal must use the raid layout")
    Check(Situation(forever, "raid", 186) == "normal", "Forever: 40-player raid (186) must use the raid layout")
    Check(Situation(forever, "none", 0) == "openworld", "Forever: open world must stay openworld")
    Check(Situation(forever, "party", 1) == "normal", "Forever: normal dungeon mapping must not change")

    for _, client in ipairs({ false, RETAIL }) do
        local label = client and "IsForever=false" or "no Client"
        local retail = LoadGroupDB(client or nil)
        byUnit, byHeight = PowerShown(retail, "party1", defaults, "DAMAGER")
        Check(not byUnit and not byHeight, label .. ": unassigned role must keep the Retail DAMAGER fallback")
        byUnit, byHeight = PowerShown(retail, "party2", defaults, nil)
        Check(byUnit and byHeight, label .. ": Retail healer power must show")
        byUnit, byHeight = PowerShown(retail, "party5", allOff, nil)
        Check(not byUnit and not byHeight, label .. ": Retail tank toggle must apply")
        Check(Situation(retail, "raid", 9) == "openworld", label .. ": Retail legacy 40-player raid situation changed")
        Check(Situation(retail, "raid", 16) == "mythic", label .. ": Retail mythic raid situation changed")
        Check(Situation(retail, "raid", 14) == "normal", label .. ": Retail normal raid situation changed")
        Check(Situation(retail, "none", 0) == "openworld", label .. ": Retail open world situation changed")
    end
end

print("forever_group_frames_smoke: ok")
