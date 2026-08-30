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
local allowFrameCreation = false
local function MakeFrame(parent)
    local widget = { parent = parent }
    function widget:SetAllPoints() self.allPoints = true end
    function widget:SetParent(value) self.parent = value end
    function widget:Hide() self.hidden = true end
    return widget
end
_G.CreateFrame = function(_, _, parent)
    if not allowFrameCreation then error("unexpected top-level CreateFrame") end
    return MakeFrame(parent)
end
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

-- The shared Edit Mode preview hides the rendered lane and forwards clicks
-- from its live buttons into the draggable overlay. Classic owns custom lane
-- frames, so it must expose the same small lane-enumeration contract as the
-- Retail native Aura containers.
allowFrameCreation = true
local renderFrame = MakeFrame()
renderFrame.MSUFUnitKey = "target"
renderFrame.MSUFSpec = {}
registered.Create(renderFrame)
local nativeBuffLane = assert(renderFrame.Auras and renderFrame.Auras.Buffs,
    "Classic buff lane frame was not created")
local nativeDebuffLane = assert(renderFrame.Auras and renderFrame.Auras.Debuffs,
    "Classic debuff lane frame was not created")
assert(nativeBuffLane._msufA3NativeLane == "buff"
    and nativeDebuffLane._msufA3NativeLane == "debuff",
    "Classic lanes do not identify themselves to the shared Edit Mode input bridge")
local buffLaneConfig = assert(nativeBuffLane._msufA3NativeLaneConfig,
    "Classic buff lane does not expose its renderer config")
buffLaneConfig[1] = { marker = "button" }
buffLaneConfig.createdButtons = 1
assert(nativeBuffLane:GetAuraFrameCount() == 1
    and nativeBuffLane:GetAuraFrame(1) == buffLaneConfig[1],
    "Classic lane enumeration does not expose rendered buttons to Edit Mode")

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
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Menu_Compat.lua"))(
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

-- The Classic compiler accepts portable hidePermanent values from the filter
-- tree, while the shared menu model owns the blacklist controls.  Exercise the
-- Classic-only compatibility seam against the real compiler and menu model so
-- reads and first-write copy-on-write cannot silently diverge again.
do
    _G.MSUF_DB.auras3 = {
        enabled = true,
        showPlayer = true,
        showTarget = true,
        showFocus = true,
        showBoss = true,
        shared = {},
        perUnit = {
            target = {
                overrideBlacklist = true,
                filters = {
                    enabled = false,
                    buffs = { hidePermanent = true },
                    debuffs = { hidePermanent = true },
                },
                blacklist = {
                    spells = { [700001] = true },
                    buffs = { spells = { [700002] = true } },
                    debuffs = { spells = { [700003] = true } },
                },
            },
        },
    }

    local A3 = namespace.MSUF_Auras3
    local Model = assert(A3.MenuModel, "shared Aura menu model missing")
    assert(A3.__classicAuraMenuCompatLoaded == true,
        "Classic Aura menu compatibility did not install")

    local auras = _G.MSUF_DB.auras3
    local target = auras.perUnit.target
    local originalBlacklist = target.blacklist
    local originalBuffLane = target.blacklist.buffs
    local originalDebuffLane = target.blacklist.debuffs
    local runtime = assert(A3.ResolveUnitFrameConfig("target", {}),
        "Classic target config missing")
    assert(runtime.lanes.buff.hidePermanent == true
        and runtime.lanes.debuff.hidePermanent == true,
        "Classic compiler lost portable per-lane Hide Permanent filters")
    assert(Model.ReadBlacklistHidePermanent("target", "buff") == true
        and Model.ReadBlacklistHidePermanent("target", "debuff") == true,
        "Classic menu does not read the compiler-effective portable filters")
    assert(target.overrideBlacklist == true
        and target.blacklist == originalBlacklist
        and target.blacklist.buffs == originalBuffLane
        and target.blacklist.debuffs == originalDebuffLane
        and target.blacklist.buffs.hidePermanent == nil
        and target.blacklist.debuffs.hidePermanent == nil,
        "Classic menu read mutated the saved blacklist owner")

    target.blacklist.debuffs = nil
    assert(Model.ReadBlacklistHidePermanent("target", "debuff") == true
        and target.blacklist.debuffs == nil,
        "Classic portable-filter read recreated a missing blacklist lane")
    target.blacklist.debuffs = originalDebuffLane

    target.blacklist.buffs.hidePermanent = false
    assert(Model.ReadBlacklistHidePermanent("target", "buff") == false,
        "explicit Classic blacklist false did not override the portable filter")
    target.blacklist.buffs.hidePermanent = nil
    target.filters.buffs.hidePermanent = nil
    target.filters.debuffs.hidePermanent = nil
    target.filters.hidePermanent = true
    assert(Model.ReadBlacklistHidePermanent("target", "buff") == true,
        "legacy root Hide Permanent no longer applies to Classic Buffs")
    assert(Model.ReadBlacklistHidePermanent("target", "debuff") == false,
        "legacy root Hide Permanent leaked into Classic Debuffs")

    local sharedBlacklist = {
        spells = { [710001] = true },
        buffs = {
            spells = { [710002] = true },
            maxDuration = 71,
        },
        debuffs = {
            spells = { [710003] = true },
            hidePermanent = true,
            maxDuration = 37,
        },
    }
    auras.shared.blacklist = sharedBlacklist
    target.overrideBlacklist = false
    target.blacklist = { dormant = true }
    target.filters.hidePermanent = false
    local dormantBlacklist = target.blacklist
    assert(Model.ReadBlacklistHidePermanent("target", "debuff") == true,
        "Classic menu did not read the effective Shared blacklist")
    assert(target.overrideBlacklist == false and target.blacklist == dormantBlacklist,
        "Classic Shared-blacklist read created a local override")

    assert(Model.WriteBlacklistHidePermanent("target", "debuff", false) == true,
        "Classic Hide Permanent write did not report its change")
    assert(target.overrideBlacklist == true
        and target.blacklist ~= sharedBlacklist
        and target.blacklist.spells[710001] == true
        and target.blacklist.buffs.spells[710002] == true
        and target.blacklist.buffs.maxDuration == 71
        and target.blacklist.debuffs.spells[710003] == true
        and target.blacklist.debuffs.maxDuration == 37
        and target.blacklist.debuffs.hidePermanent == false,
        "Classic first edit did not copy the complete effective Shared blacklist")
    assert(sharedBlacklist.debuffs.hidePermanent == true
        and sharedBlacklist.buffs.maxDuration == 71,
        "Classic first edit mutated the Shared blacklist")
    local disabledRuntime = assert(A3.ResolveUnitFrameConfig("target", {}),
        "Classic target config missing after explicit false")
    assert(disabledRuntime.lanes.debuff.hidePermanent == false,
        "Classic compiler ignored the explicit false written by the menu")

    for i = 1, 5 do
        auras.perUnit["boss" .. i] = {
            overrideBlacklist = false,
            blacklist = { dormant = i },
            filters = { buffs = {}, debuffs = {} },
        }
    end
    assert(Model.WriteBlacklistHidePermanent("boss", "buff", true) == true,
        "Classic Boss Hide Permanent write did not report its change")
    for i = 1, 5 do
        local boss = auras.perUnit["boss" .. i]
        assert(boss.overrideBlacklist == true
            and boss.blacklist ~= sharedBlacklist
            and boss.blacklist.spells[710001] == true
            and boss.blacklist.debuffs.maxDuration == 37
            and boss.blacklist.buffs.hidePermanent == true,
            "Classic Boss Hide Permanent did not preserve/fan out owner " .. i)
    end

    for i = 1, 3 do
        auras.perUnit["arena" .. i] = {
            overrideBlacklist = false,
            blacklist = { dormant = i },
            filters = {
                buffs = { hidePermanent = i == 1 },
                debuffs = {},
            },
        }
    end
    assert(Model.ReadBlacklistHidePermanent("arena", "buff") == true,
        "Classic Arena menu did not read arena1 portable Hide Permanent")
    assert(Model.WriteBlacklistHidePermanent("arena", "debuff", false) == true,
        "Classic Arena Hide Permanent write did not report its change")
    assert(auras.perUnit.player == nil,
        "Classic Arena Hide Permanent write incorrectly prepared Player")
    for i = 1, 3 do
        local arena = auras.perUnit["arena" .. i]
        assert(arena.overrideBlacklist == true
            and arena.blacklist ~= sharedBlacklist
            and arena.blacklist.spells[710001] == true
            and arena.blacklist.buffs.maxDuration == 71
            and arena.blacklist.debuffs.hidePermanent == false,
            "Classic Arena Hide Permanent did not preserve/fan out owner " .. i)
    end

    local function Read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local sharedMenuPath = "..\\..\\Auras3\\MSUF_Auras3_Menu_Model.lua"
    local compatPath = "..\\Classic\\Auras\\MSUF_Auras3_Menu_Compat.lua"
    for _, flavor in ipairs({ "Vanilla", "Mists", "TBC" }) do
        local xml = Read(root .. "/MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml")
        local sharedAt = assert(xml:find(sharedMenuPath, 1, true),
            flavor .. " shared menu load missing")
        local compatAt = assert(xml:find(compatPath, 1, true),
            flavor .. " Classic menu compat load missing")
        assert(compatAt > sharedAt,
            flavor .. " Classic menu compat loads before the shared model")
    end
    local retailXml = Read(root
        .. "/MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
    assert(not retailXml:find("MSUF_Auras3_Menu_Compat.lua", 1, true),
        "Retail load graph entered the Classic Aura menu compatibility")
end

print("classic aura backend smoke passed")
