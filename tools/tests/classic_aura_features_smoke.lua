local root = assert(arg[1], "repository root argument missing")
local A3 = {
    PlayerDefensiveData = {
        ROGUE = { { 5277, "Evasion" }, { 31224, "Cloak of Shadows" } },
        DRUID = { { 22812, "Barkskin" } },
    },
    TargetDotData = {
        ROGUE = { { 703, "Garrote" }, { 1943, "Rupture" } },
    },
}
function A3.AddAuraSpellIDAndAliases(out, spellID) out[spellID] = true end

local namespace = { Client = { IsClassic = true }, MSUF_Auras3 = A3 }
_G.MSUF_NS = namespace
_G.UnitClass = function() return "Rogue", "ROGUE" end
_G.C_Spell = {
    GetSpellName = function(spellID)
        local names = {
            [5277] = "Evasion", [31224] = "Cloak of Shadows",
            [703] = "Garrote", [1943] = "Rupture", [999001] = "Test Aura",
        }
        return names[spellID]
    end,
    IsSpellImportant = function(spellID) return spellID == 999001 end,
    IsExternalDefensive = function(spellID) return spellID == 900100 end,
}

local path = root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", namespace)
local features = assert(A3.ClassicFeatures, "Classic feature compiler did not load")

local auras = {
    customContainers = {
        perUnit = {
            player = { items = {
                [4] = {
                    enabled = true, playerDefensives = true, portraitIcon = true,
                    disabledPredefinedSpellIDs = { [31224] = true },
                    spellIDs = "999001",
                    placed = { size = 24, max = 8, perRow = 4 },
                    filters = {},
                },
            } },
            target = { items = {
                [1] = {
                    enabled = true, auraType = "BUFF", spellIDs = "999001",
                    placed = { size = 20, max = 2, perRow = 2 },
                    filters = {
                        enabled = false, raid = true, onlyImportant = true,
                        hidePermanent = true, maxDuration = 500,
                    },
                },
                [4] = {
                    enabled = true, targetDots = true, auraType = "DEBUFF",
                    spellIDs = "703, 999001", customSpellIDs = { [999001] = true },
                    placed = {
                        size = 22, max = 4, perRow = 2,
                        debuffTypeBorderMode = "SYMBOL", cooldownDecimalSeconds = 8,
                    },
                    filters = { onlyMine = true },
                },
            } },
        },
    },
}

local playerLanes, playerOrder = features.CompileUnitLanes(auras, "player", {
    portrait = { enabled = true, width = 36, height = 40 },
}, 5)
assert(#playerOrder == 1 and playerOrder[1] == "defensivePortrait", "defensive portrait lane did not compile")
local defensive = playerLanes.defensivePortrait
assert(defensive.includeSpellIDs[5277] == true, "player class defensive missing")
assert(defensive.includeSpellIDs[31224] ~= true, "disabled predefined defensive remained active")
assert(defensive.includeSpellIDs[999001] == true, "custom defensive missing")
assert(defensive.anchorTarget == "portrait" and defensive.buttonWidth == 36 and defensive.buttonHeight == 40,
    "defensive portrait geometry did not follow portrait")
assert(defensive.padding == 0, "portrait aura lane inherited standalone lane padding")

local targetLanes, targetOrder = features.CompileUnitLanes(auras, "target", {}, 5)
assert(#targetOrder == 2, "target custom lanes did not compile")
assert(targetLanes.custom1.includeSpellIDs[999001] == true, "normal custom lane spell missing")
assert(targetLanes.custom1.filterRequirements == nil and targetLanes.custom1.onlyImportant == false
    and targetLanes.custom1.raid == false,
    "disabled custom filter master still applied token filters")
assert(targetLanes.custom1.hidePermanent == true and targetLanes.custom1.maxDuration == 0,
    "Classic custom lane did not keep hide-permanent while cooling the duration filter")
assert(targetLanes.custom4.includeSpellIDs[703] == true, "known target DoT missing")
assert(targetLanes.custom4.includeSpellIDs[999001] == true, "explicit custom target DoT missing")
assert(targetLanes.custom4.onlyMine == true,
    "Classic target-DoT lane did not retain its player-cast contract")
assert(targetLanes.custom4.showDispelTypeBorder == true
    and targetLanes.custom4.showDispelTypeSymbol == true
    and targetLanes.custom4.cooldownDecimalSeconds == 8,
    "Classic custom aura appearance settings did not compile")
assert(targetLanes.custom1.padding == 5
    and targetLanes.custom1.width == targetLanes.custom1.cols * targetLanes.custom1.buttonWidth
        + math.max(targetLanes.custom1.cols - 1, 0) * targetLanes.custom1.spacing + 10,
    "Classic custom aura lane did not inherit shared lane padding")

local filterCalls = 0
local matched = features.MatchAura(targetLanes.custom4, "target", {
    spellId = 700000, name = "Garrote", duration = 12, auraInstanceID = 3, isPlayerAura = true,
}, function() filterCalls = filterCalls + 1; return false end)
assert(matched == true and filterCalls == 0, "Classic spell-name alias matching failed")

local rawPlan = features.CompileRawFilter(
    "HARMFUL|DISPELLABLE|IMPORTANT|!PLAYER|INCLUDE_NAME_PLATE_ONLY", false)
assert(rawPlan.scanFilter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY",
    "unsupported Classic tokens leaked into the scan filter")
assert(rawPlan.needsPlayerFlag == true and rawPlan.hasRequirements == true,
    "raw Classic filter requirements were not compiled")
assert(features.MatchFilterRequirements(rawPlan, "target", {
    spellId = 999001, auraInstanceID = 7, dispelName = "Magic", isPlayerAura = false,
}, function() error("raw filter unexpectedly called a native predicate") end) == true,
    "Classic IMPORTANT/DISPELLABLE/!PLAYER predicates did not match")
assert(features.MatchFilterRequirements(rawPlan, "target", {
    spellId = 999001, auraInstanceID = 7, dispelName = "Magic", isPlayerAura = true,
}, function() return true end) == false, "Classic !PLAYER predicate accepted a player aura")

local externalPlan = features.CompileRawFilter("HELPFUL|EXTERNAL_DEFENSIVE", true)
assert(externalPlan.scanFilter == "HELPFUL" and externalPlan.requirements.externalDefensive == true,
    "Classic External Defensive plan did not keep a helpful base scan")
assert(features.MatchFilterRequirements(externalPlan, "party1", {
    spellId = 900100, auraInstanceID = 8,
}, function() error("documented external predicate unexpectedly fell back to a token scan") end) == true,
    "Classic External Defensive plan rejected a classified defensive")
assert(features.MatchFilterRequirements(externalPlan, "party1", {
    spellId = 54861, auraInstanceID = 9,
}, function() return true end) == false,
    "Classic External Defensive plan accepted Nitro Boosts")

local nonExternalPlan = features.CompileRawFilter("HELPFUL|!EXTERNAL_DEFENSIVE", true)
assert(nonExternalPlan.scanFilter == "HELPFUL" and nonExternalPlan.requirements.notExternalDefensive == true,
    "Classic normal Buff plan lost the External Defensive exclusion")
assert(features.MatchFilterRequirements(nonExternalPlan, "party1", {
    spellId = 54861, auraInstanceID = 10,
}, function() return false end) == true,
    "Classic normal Buff plan rejected a regular helpful aura")
assert(features.MatchFilterRequirements(nonExternalPlan, "party1", {
    spellId = 900100, auraInstanceID = 11,
}, function() return false end) == false,
    "Classic normal Buff plan retained an External Defensive")

local dormantSettings = {
    includeNameplateOnly = true, raid = true, externalDefensive = true,
}
local settingsPlan = features.CompileSettingsFilter(dormantSettings, true)
assert(settingsPlan.scanFilter == "HELPFUL" and settingsPlan.requirements == nil,
    "Classic runtime did not cool unsupported Retail filter settings")
assert(dormantSettings.includeNameplateOnly == true and dormantSettings.raid == true
    and dormantSettings.externalDefensive == true,
    "Classic filter compilation mutated portable Retail profile values")
local onlyMinePlan = features.CompileSettingsFilter({ onlyMine = true, raid = true }, true)
assert(onlyMinePlan.scanFilter == "HELPFUL|PLAYER" and onlyMinePlan.requirements.player == true
    and onlyMinePlan.nativePlayerFilter == true
    and onlyMinePlan.requirements.raid ~= true,
    "Classic Only Mine plan did not compile the native player filter")
local disabledPlan = features.CompileSettingsFilter({ enabled = false, raid = true, onlyImportant = true }, true)
assert(disabledPlan.hasRequirements == false and disabledPlan.scanFilter == "HELPFUL",
    "Classic disabled filter plan retained active requirements")

local groupFrame = {
    MSUFSpec = {
        spellIndicators = {
            enabled = true,
            items = {
                { enabled = true, display = "Test", includeSpellIDs = { [999001] = true },
                    placed = { type = "icon", size = 16, anchor = "TOPLEFT" } },
            },
        },
    },
}
local groupLanes, groupOrder = features.CompileGroupIndicatorLanes(groupFrame, "party1")
assert(#groupOrder == 1 and groupLanes[groupOrder[1]].max == 1, "group spell indicator lane did not compile")

print("classic aura feature compiler smoke passed")
