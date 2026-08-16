local root = assert(arg[1], "repository root argument missing")
local registered
local registrations = 0
local namespace = {
    Client = { IsClassic = true },
    MSUF_Auras3 = {},
    UF = {
        RegisterElement = function(name, element)
            assert(name == "Auras", "unexpected element registration")
            registrations = registrations + 1
            registered = element
        end,
    },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

_G.MSUF_NS = namespace
_G.MSUF = namespace
_G.MSUF_DB = {
    auras3 = {
        enabled = true, showTarget = true,
        shared = {
            showBuffs = true, showDebuffs = true,
            filters = {
                enabled = true,
                buffs = { includeNameplateOnly = true, onlyImportant = true },
                debuffs = { dispellableAny = true, crowdControl = true },
            },
        },
        perUnit = {
            target = {
                overrideBlacklist = true,
                overrideFilters = true,
                filters = {
                    enabled = false,
                    buffs = { hidePermanent = true },
                    debuffs = { hidePermanent = true },
                },
                blacklist = {
                    spells = { [999999] = true },
                    buffs = { spells = { [900010] = true } },
                    debuffs = {
                        spells = { [900020] = true },
                        maxDuration = 36,
                    },
                },
            },
        },
        customContainers = {
            perUnit = {
                target = { items = {
                    [1] = {
                        enabled = true, auraType = "DEBUFF", spellIDs = "900001",
                        placed = {
                            size = 18, spacing = 5, max = 2, perRow = 2,
                            x = 113, y = -47, anchor = "LEFT", growth = "RIGHTUP",
                        },
                        filters = {},
                    },
                } },
            },
        },
    },
}
_G.CreateFrame = function() error("unexpected top-level CreateFrame") end
_G.UnitExists = function() return true end
_G.GetTime = function() return 0 end
_G.InCombatLockdown = function() return false end
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(_, index)
        if index == 1 then return { auraInstanceID = 11 } end
        if index == 2 then return { auraInstanceID = 22 } end
        return nil
    end,
}
_G.AuraUtil = {}
_G.GameTooltip = {}
_G.C_Timer = {}

local classicPath = root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"
local featuresPath = root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Features.lua"
local retailPath = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
assert(loadfile(featuresPath))("MidnightSimpleUnitFrames", namespace)
assert(loadfile(classicPath))("MidnightSimpleUnitFrames", namespace)
assert(loadfile(retailPath))("MidnightSimpleUnitFrames", namespace)

assert(registrations == 1, "Retail aura backend registered after Classic ownership")
assert(namespace.MSUF_Auras3.classicAuraBackend == true, "Classic backend marker missing")
assert(namespace.MSUF_Auras3.nativeAuraBackend == false, "native backend must be disabled on Classic")
assert(registered and registered.events[1] == "UNIT_AURA", "Classic backend must own UNIT_AURA")

local frame = { MSUFUnitKey = "target", MSUFSpec = {} }
assert(frame.unit == nil, "lifecycle smoke precondition failed")
assert(registered.IsEnabled(frame) == true, "target aura element stayed disabled")
assert(frame.unit == "target", "Classic aura lifecycle did not bind MSUFUnitKey")
local buffMetrics = namespace.MSUF_Auras3.BuildAuraLaneMetrics("target", "buff")
local debuffMetrics = namespace.MSUF_Auras3.BuildAuraLaneMetrics("target", "debuff")
local customMetrics = namespace.MSUF_Auras3.BuildAuraLaneMetrics("target", "custom1")
assert(buffMetrics and buffMetrics.enabled == true and buffMetrics.num > 0,
    "Classic target buff lane did not compile")
assert(debuffMetrics and debuffMetrics.enabled == true and debuffMetrics.num > 0,
    "Classic target debuff lane did not compile")
assert(customMetrics
    and customMetrics.size == 18
    and customMetrics.spacing == 5
    and customMetrics.num == 2
    and customMetrics.x == 113
    and customMetrics.y == -47
    and customMetrics.anchor == "LEFT"
    and customMetrics.growthX == 1
    and customMetrics.growthY == 1,
    "Classic custom preview metrics fell back to the standard buff lane")
assert(customMetrics ~= buffMetrics,
    "Classic custom preview metrics reused the standard buff metrics table")
local targetConfig = namespace.MSUF_Auras3.ResolveUnitFrameConfig("target", frame.MSUFSpec)
assert(targetConfig.lanes.buff.filter == "HELPFUL" and targetConfig.lanes.buff.filterRequirements == nil,
    "Classic buff lane did not cool unsupported Retail filters")
assert(targetConfig.lanes.debuff.filter == "HARMFUL" and targetConfig.lanes.debuff.filterRequirements == nil,
    "Classic debuff lane did not cool unsupported Retail filters")
assert(targetConfig.lanes.buff.blacklist[900010] == true
    and targetConfig.lanes.buff.blacklist[999999] == nil
    and targetConfig.lanes.buff.hidePermanent == true,
    "Classic buff lane did not compile its lane-specific blacklist")
assert(targetConfig.lanes.debuff.blacklist[900020] == true
    and targetConfig.lanes.debuff.hidePermanent == true
    and targetConfig.lanes.debuff.maxDuration == 0,
    "Classic debuff lane did not keep hide-permanent while cooling duration")
assert(_G.MSUF_DB.auras3.shared.filters.buffs.includeNameplateOnly == true
    and _G.MSUF_DB.auras3.shared.filters.buffs.onlyImportant == true
    and _G.MSUF_DB.auras3.shared.filters.debuffs.dispellableAny == true
    and _G.MSUF_DB.auras3.perUnit.target.filters.buffs.hidePermanent == true
    and _G.MSUF_DB.auras3.perUnit.target.filters.debuffs.hidePermanent == true
    and _G.MSUF_DB.auras3.perUnit.target.blacklist.debuffs.maxDuration == 36,
    "Classic compilation mutated portable Retail profile settings")
assert(targetConfig.lanes.buff.sortOrder == 1 and targetConfig.lanes.buff.needsPlayerFlag == true
    and targetConfig.lanes.buff.naturalOrder == false,
    "Classic default aura ordering is not deterministic player/priority-first")
assert(targetConfig and targetConfig.lanes.custom1 and targetConfig.lanes.custom1.includeSpellIDs[900001] == true,
    "Classic custom lane was not integrated into the scan backend")

_G.MSUF_DB.auras3.perUnit.target.blacklist.buffs.hidePermanent = false
namespace.MSUF_Auras3._runtimeConfigGen = (namespace.MSUF_Auras3._runtimeConfigGen or 1) + 1
local explicitFalseConfig = namespace.MSUF_Auras3.ResolveUnitFrameConfig("target", frame.MSUFSpec)
assert(explicitFalseConfig.lanes.buff.hidePermanent == false,
    "Classic explicit blacklist false did not override an inherited legacy rule")

local groupFrame = {
    MSUFUnitKey = "party1",
    MSUFSpec = {
        scope = "group",
        auras = {
            enabled = true,
            showBuffs = true, maxBuffs = 4,
            buffFilter = "HELPFUL|RAID",
            buffHidePermanent = true,
            showDebuffs = true, maxDebuffs = 4,
            debuffFilter = "HARMFUL|PLAYER|RAID",
            debuffHidePermanent = true, debuffMaxDuration = 36,
        },
    },
}
assert(registered.IsEnabled(groupFrame) == true, "Classic group aura lanes did not compile")
local groupConfig = assert(groupFrame._msufA3GroupConfig, "Classic group aura config missing")
assert(groupConfig.lanes.buff.hidePermanent == true,
    "Classic group buff hide-permanent setting was ignored")
assert(groupConfig.lanes.buff.filter == "HELPFUL" and groupConfig.lanes.buff.filterRequirements == nil,
    "Classic group lane did not cool an unsupported native filter")
assert(groupConfig.lanes.debuff.filter == "HARMFUL|PLAYER"
    and groupConfig.lanes.debuff.filterRequirements.player == true
    and groupConfig.lanes.debuff.nativePlayerFilter == true,
    "Classic group Only Mine filter did not compile")
assert(groupConfig.lanes.debuff.hidePermanent == true
    and groupConfig.lanes.debuff.maxDuration == 0,
    "Classic group lane did not keep hide-permanent while cooling duration")
assert(groupFrame.MSUFSpec.auras.debuffMaxDuration == 36
    and groupFrame.MSUFSpec.auras.buffFilter == "HELPFUL|RAID"
    and groupFrame.MSUFSpec.auras.debuffFilter == "HARMFUL|PLAYER|RAID",
    "Classic group compilation mutated portable profile values")
assert(namespace.MSUF_Auras3._ClassicAuraIndexByInstanceID("target", 22, "HARMFUL") == 2,
    "Classic tooltip fallback did not resolve the filtered aura index")

-- Exercise the real Group SavedVariables -> compiled Group spec -> Classic
-- backend bridge.  The focused menu/backend smokes above intentionally use
-- flattened fixtures; without this integration check the two halves can each
-- pass while live Group Frames silently lose their filters.
_G.wipe = _G.wipe or function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.MSUF_DB.gf_party = {
    auras = {
        enabled = true,
        buff = {
            enabled = true, filterToken = "Player",
            blacklist = { hidePermanent = true, spells = {} },
        },
        debuff = {
            enabled = true, filterToken = "Player",
            blacklist = { hidePermanent = true, spells = {} },
        },
        externals = { enabled = true, max = 2, autoBlacklistBuffs = true },
    },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))(
    "MidnightSimpleUnitFrames", namespace)
namespace.GF = namespace.GF or {}
namespace.GF.GetConf = function() return _G.MSUF_DB.gf_party end
namespace.GF.GetScaledFrameMetrics = function() return 80, 32 end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", namespace)
local compiledGroupSpec = namespace.GF.CompileSpec("party")
assert(compiledGroupSpec.auras.buffFilter == "HELPFUL|PLAYER|!EXTERNAL_DEFENSIVE"
    and compiledGroupSpec.auras.buffHidePermanent == true,
    "Classic Group buff settings were lost before the Aura backend")
assert(compiledGroupSpec.auras.debuffFilter == "HARMFUL|PLAYER"
    and compiledGroupSpec.auras.debuffHidePermanent == true,
    "Classic Group debuff settings were lost before the Aura backend")
local integratedGroupFrame = {
    MSUFUnitKey = "party1",
    MSUFSpec = compiledGroupSpec,
}
assert(registered.IsEnabled(integratedGroupFrame) == true,
    "Classic integrated Group aura config did not enable")
local integratedGroupConfig = assert(integratedGroupFrame._msufA3GroupConfig,
    "Classic integrated Group aura backend config missing")
assert(integratedGroupConfig.lanes.buff.hidePermanent == true
    and integratedGroupConfig.lanes.buff.filter == "HELPFUL|PLAYER"
    and integratedGroupConfig.lanes.buff.filterRequirements.player == true
    and integratedGroupConfig.lanes.buff.filterRequirements.notExternalDefensive == true,
    "Classic integrated Group buff filters did not reach the renderer")
assert(integratedGroupConfig.lanes.debuff.hidePermanent == true
    and integratedGroupConfig.lanes.debuff.filter == "HARMFUL|PLAYER",
    "Classic integrated Group debuff filters did not reach the renderer")
assert(integratedGroupConfig.lanes.external.filter == "HELPFUL"
    and integratedGroupConfig.lanes.external.filterRequirements.externalDefensive == true,
    "Classic integrated External Defensive lane did not keep its helpful classification")

print("classic aura backend smoke passed")
