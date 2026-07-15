_G = _G or _ENV

-- Reuse the full profile/defaults harness so this exercises the same exported
-- migration entrypoint used by imports and SavedVariables startup.
dofile("tools/profile_apply_smoke.lua")

local translate = assert(_G.MSUF_ProfileIO_TranslateProfileToCurrent)

local function legacyFixture()
    return {
        general = {
            statusIconsUseMidnightStyle = false,
            restedStateIndicatorSymbol = "rested_moonzzz",
            castbarPlayerBarWidth = 288,
            castbarPlayerBarHeight = 10,
            castbarPlayerOffsetX = 0,
            castbarPlayerOffsetY = -38,
            castbarTargetBarWidth = 223,
            castbarTargetBarHeight = 18,
            castbarTargetOffsetX = 0,
            castbarTargetOffsetY = -58,
            castbarFocusBarWidth = 222,
            castbarFocusBarHeight = 18,
            castbarFocusOffsetX = 1,
            castbarFocusOffsetY = -58,
            bossCastbarWidth = 248,
            bossCastbarHeight = 18,
            bossCastbarOffsetX = 1,
            bossCastbarOffsetY = -49,
        },
        bars = { barOutlineStrata = "AUTO" },
        player = {
            width = 242,
            height = 30,
            showPower = false,
            showCombatStateIndicator = true,
            showRestingIndicator = true,
            showIncomingResIndicator = true,
            combatStateIndicatorSize = 30,
            combatStateIndicatorOffsetX = 104,
            combatStateIndicatorOffsetY = 3,
            restedStateIndicatorSize = 30,
            restedStateIndicatorOffsetX = -12,
            restedStateIndicatorOffsetY = 26,
            restedStateIndicatorSymbol = "DEFAULT",
            incomingResIndicatorSize = 30,
            incomingResIndicatorOffsetX = -115,
            incomingResIndicatorOffsetY = 1,
            incomingResIndicatorSymbol = "DEFAULT",
        },
        target = {
            width = 242,
            height = 30,
            showPower = false,
            hlOverride = true,
            barOutlineStrata = "AUTO",
            nameTextLayer = 5,
            hpTextLayer = 5,
            powerTextLayer = 2,
            showCombatStateIndicator = true,
            combatStateIndicatorSize = 30,
            combatStateIndicatorOffsetX = 104,
            combatStateIndicatorOffsetY = 0,
            incomingResIndicatorSize = 30,
            incomingResIndicatorOffsetX = -114,
            powerBarDetached = true,
            detachedPowerBarWidth = 80,
            detachedPowerBarHeight = 4,
            detachedPowerBarOffsetX = 116,
            detachedPowerBarOffsetY = 2,
        },
        focus = { showPower = false },
        targettarget = { showPower = false },
        focustarget = { showPower = false },
        pet = { showPower = true },
        boss = { width = 185, height = 32, showPower = true },
        gf_party = { hlOverride = true, barOutlineStrata = "AUTO" },
        auras2 = {
            shared = {
                offsetX = 0,
                offsetY = 0,
                iconSize = 26,
                buffGrowth = "RIGHT",
                debuffGrowth = "RIGHT",
                rowWrap = "DOWN",
                maxBuffs = 12,
                maxDebuffs = 12,
            },
            perUnit = {
                player = {
                    overrideLayout = true,
                    overrideSharedLayout = true,
                    layout = {
                        offsetX = 303,
                        offsetY = -37,
                        debuffGroupOffsetX = -305,
                        debuffGroupOffsetY = 10,
                        debuffGroupIconSize = 25,
                    },
                    layoutShared = { debuffGrowth = "LEFT", debuffRowWrap = "UP" },
                },
                target = {
                    overrideLayout = true,
                    overrideSharedLayout = true,
                    layout = {
                        offsetX = 1,
                        offsetY = -8,
                        buffGroupOffsetX = -2,
                        buffGroupOffsetY = -98,
                        buffGroupIconSize = 34,
                    },
                    layoutShared = { buffGrowth = "RIGHT", buffRowWrap = "DOWN" },
                },
                boss1 = {
                    overrideLayout = true,
                    overrideSharedLayout = true,
                    layout = {
                        offsetX = 3,
                        offsetY = -9,
                        debuffGroupOffsetX = -12,
                        debuffGroupOffsetY = -24,
                        debuffGroupIconSize = 35,
                    },
                    layoutShared = { debuffGrowth = "LEFT", debuffRowWrap = "DOWN" },
                },
            },
        },
    }
end

local fresh = legacyFixture()
local _, changed = translate(fresh, { source = "legacy_import", markProfile = true })
assert(changed == true, "fresh 5.5 profile was not migrated")
assert(fresh.auras2 == nil and fresh.auras3._msufAuras3LegacyGeometry_v3 == true,
    "Aura2 payload did not reach geometry v3")
assert(fresh.target.detachedPowerBarAnchorMode == "LEGACY_TOPLEFT",
    "detached power did not retain 5.5 left-edge semantics")
assert(fresh.bars.barOutlineStrata == "BACKGROUND"
    and fresh.target.barOutlineStrata == "BACKGROUND"
    and fresh.gf_party.barOutlineStrata == "BACKGROUND"
    and fresh._msufLegacy55FrameOutlineBackground_v1 == true,
    "5.5 frame outline strata was not pinned to BACKGROUND")
assert(fresh.target.detachedPowerBarOffsetX == 116 and fresh.target.detachedPowerBarOffsetY == 2
    and fresh.target.detachedPowerBarWidth == 80 and fresh.target.detachedPowerBarHeight == 4,
    "detached power dimensions or offsets changed during migration")
assert(fresh.target.nameTextLayer == 5 and fresh.target.hpTextLayer == 5
    and fresh.target.powerTextLayer == 2,
    "unit text layer values changed during migration")
assert(fresh.player.showPowerText == false
    and fresh.target.showPowerText == false
    and fresh.focus.showPowerText == false
    and fresh.targettarget.showPowerText == false
    and fresh.focustarget.showPowerText == false
    and fresh.pet.showPowerText == true
    and fresh.boss.showPowerText == true
    and fresh._msufLegacy55PowerTextVisibility_v1 == true,
    "5.5 Power Text on/off state was not copied from showPower")
assert(fresh.general.statusIconsUseMidnightStyle == false
    and fresh.general.restedStateIndicatorSymbol == "rested_moonzzz"
    and fresh.player.combatStateIndicatorSize == 30
    and fresh.player.combatStateIndicatorOffsetX == 104
    and fresh.player.combatStateIndicatorOffsetY == 3
    and fresh.player.restedStateIndicatorSymbol == "DEFAULT"
    and fresh.player.restedStateIndicatorOffsetX == -12
    and fresh.player.restedStateIndicatorOffsetY == 26
    and fresh.player.incomingResIndicatorSymbol == "DEFAULT"
    and fresh.player.incomingResIndicatorOffsetX == -115
    and fresh.player.incomingResIndicatorOffsetY == 1
    and fresh.target.combatStateIndicatorOffsetX == 104
    and fresh.target.combatStateIndicatorOffsetY == 0
    and fresh.target.incomingResIndicatorOffsetX == -114,
    "5.5 status symbol, style, size, or position changed during migration")
assert(fresh.general.castbarPlayerBarWidth == 288
    and fresh.general.castbarPlayerBarHeight == 10
    and fresh.general.castbarPlayerOffsetX == 0
    and fresh.general.castbarPlayerOffsetY == -38
    and fresh.general.castbarTargetBarWidth == 223
    and fresh.general.castbarTargetBarHeight == 18
    and fresh.general.castbarTargetOffsetX == 0
    and fresh.general.castbarTargetOffsetY == -58
    and fresh.general.castbarFocusBarWidth == 222
    and fresh.general.castbarFocusBarHeight == 18
    and fresh.general.castbarFocusOffsetX == 1
    and fresh.general.castbarFocusOffsetY == -58
    and fresh.general.bossCastbarWidth == 248
    and fresh.general.bossCastbarHeight == 18
    and fresh.general.bossCastbarOffsetX == 1
    and fresh.general.bossCastbarOffsetY == -49,
    "5.5 castbar size or position changed during profile migration")

local playerDebuff = fresh.auras3.perUnit.player.layout
assert(playerDebuff.debuffAnchor == "BOTTOMRIGHT"
    and playerDebuff.debuffGroupOffsetX == -244 and playerDebuff.debuffGroupOffsetY == 3,
    "LEFT/UP player debuff first-icon rectangle moved")
local targetBuff = fresh.auras3.perUnit.target.layout
assert(targetBuff.buffAnchor == "TOPLEFT"
    and targetBuff.buffGroupOffsetX == -1 and targetBuff.buffGroupOffsetY == -72,
    "RIGHT/DOWN target buff first-icon rectangle moved")
local bossDebuff = fresh.auras3.perUnit.boss1.layout
assert(bossDebuff.debuffAnchor == "TOPRIGHT"
    and bossDebuff.debuffGroupOffsetX == -194 and bossDebuff.debuffGroupOffsetY == 2,
    "LEFT/DOWN boss debuff first-icon rectangle moved")
assert(targetBuff.buffLayer == 30 and targetBuff.buffStrata == "MEDIUM"
    and playerDebuff.debuffLayer == 30 and playerDebuff.debuffStrata == "MEDIUM",
    "legacy Aura2 z-order was not retained above unit text")
for _, unit in ipairs({ "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }) do
    assert(type(fresh.auras3.perUnit[unit]) == "table"
        and fresh.auras3.perUnit[unit].overrideLayout == true,
        "shared Aura2 geometry was not materialized for " .. unit)
end

local _, changedAgain = translate(fresh, {
    source = "profiles",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(changedAgain == false, "5.5 migration was not idempotent")

-- Profiles that already passed through the broken v2 migration must be
-- repaired in place during startup, without requiring a new import.
local storedV2 = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 1,
    general = {},
    target = {
        width = 242,
        height = 30,
        powerBarDetached = true,
        detachedPowerBarWidth = 80,
        detachedPowerBarOffsetX = 116,
        detachedPowerBarOffsetY = 2,
    },
    auras3 = {
        _msufAuras3TranslatedFromLegacyAuras2 = true,
        _msufAuras3LegacyGeometry_v1 = true,
        _msufAuras3LegacyGeometry_v2 = true,
        shared = { buffGrowth = "RIGHT", buffRowWrap = "DOWN", buffGroupIconSize = 34 },
        perUnit = {
            target = {
                overrideLayout = true,
                overrideSharedLayout = true,
                layout = { buffAnchor = "BOTTOMLEFT", buffGroupOffsetX = -1, buffGroupOffsetY = -76, buffGroupIconSize = 34 },
                layoutShared = { buffGrowth = "RIGHT", buffRowWrap = "DOWN" },
            },
        },
    },
}
local _, repaired = translate(storedV2, {
    source = "profiles",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(repaired == true and storedV2._msufProfileNormalizationRevision == 4,
    "stored v2 SavedVariables did not re-enter migration")
assert(storedV2.auras3._msufAuras3LegacyGeometry_v3 == true
    and storedV2.auras3.perUnit.target.layout.buffAnchor == "TOPLEFT"
    and storedV2.auras3.perUnit.target.layout.buffGroupOffsetY == -72,
    "stored v2 Aura geometry was not repaired")
assert(storedV2.target.detachedPowerBarAnchorMode == "LEGACY_TOPLEFT",
    "stored v2 detached power geometry was not repaired")
assert(storedV2.bars.barOutlineStrata == "BACKGROUND"
    and storedV2.target.barOutlineStrata == "BACKGROUND",
    "stored v2 frame outline strata was not repaired")

-- Profiles already upgraded by geometry v3 before the fixed-outline rule was
-- introduced must re-enter once even if their geometry no longer needs work.
local storedV3 = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 3,
    general = {},
    bars = { barOutlineStrata = "AUTO" },
    player = { showPower = false, showPowerText = true },
    target = { hlOverride = true, barOutlineStrata = "AUTO", showPower = false, showPowerText = true },
    focus = { showPower = true, showPowerText = false },
    targettarget = { showPower = true, showPowerText = false },
    focustarget = { showPower = true, showPowerText = false },
    pet = { showPower = false, showPowerText = true },
    boss = { showPower = false, showPowerText = true },
    auras3 = {
        _msufAuras3TranslatedFromLegacyAuras2 = true,
        _msufAuras3LegacyGeometry_v3 = true,
        shared = {},
        perUnit = {},
    },
}
local _, repairedV3 = translate(storedV3, {
    source = "profiles",
    markProfile = true,
    trustNormalizationMarker = true,
})
assert(repairedV3 == true and storedV3._msufProfileNormalizationRevision == 4
    and storedV3.bars.barOutlineStrata == "BACKGROUND"
    and storedV3.target.barOutlineStrata == "BACKGROUND"
    and storedV3._msufLegacy55FrameOutlineBackground_v1 == true,
    "stored geometry-v3 profile did not receive fixed BACKGROUND outline strata")
for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
    assert(storedV3[unit].showPowerText == (storedV3[unit].showPower ~= false),
        "stored 5.5 Power Text visibility was not repaired for " .. unit)
end
assert(storedV3._msufLegacy55PowerTextVisibility_v1 == true,
    "stored 5.5 Power Text repair marker was not persisted")

-- Cover every legacy growth/wrap branch by comparing the migrated first-icon
-- rectangle in frame coordinates with Aura2's original rectangle.
for _, growth in ipairs({ "RIGHT", "LEFT", "UP", "DOWN" }) do
    for _, wrap in ipairs({ "UP", "DOWN" }) do
        local profile = {
            general = {},
            target = { width = 200, height = 40 },
            auras2 = {
                shared = { buffGrowth = growth, buffRowWrap = wrap, buffGroupIconSize = 20 },
                perUnit = {
                    target = {
                        overrideLayout = true,
                        layout = {
                            offsetX = 7,
                            offsetY = -11,
                            buffGroupOffsetX = 3,
                            buffGroupOffsetY = -5,
                            buffGroupIconSize = 20,
                        },
                    },
                },
            },
        }
        translate(profile, { source = "legacy_import", markProfile = true })
        local lane = profile.auras3.perUnit.target.layout
        local anchor = lane.buffAnchor
        local anchorX = lane.buffGroupOffsetX + (anchor:find("RIGHT", 1, true) and 200 or 0)
        local anchorY = lane.buffGroupOffsetY + (anchor:find("TOP", 1, true) and 40 or 0)
        local actualLeft = anchorX - (anchor:find("RIGHT", 1, true) and 20 or 0)
        local actualBottom = anchorY - (anchor:find("TOP", 1, true) and 20 or 0)
        local legacyOriginX, legacyOriginY = 10, 24
        local expectedLeft = legacyOriginX - (growth == "LEFT" and 20 or 0)
        local expectedBottom = legacyOriginY - (growth == "DOWN" and 20 or 0)
        assert(actualLeft == expectedLeft and actualBottom == expectedBottom,
            growth .. "/" .. wrap .. " first-icon rectangle moved")
    end
end

local native60 = {
    _msufProfileSchema = 600,
    _msufProfileNormalizationRevision = 1,
    general = {},
    bars = { barOutlineStrata = "AUTO" },
    target = {
        powerBarDetached = true,
        detachedPowerBarOffsetX = 12,
        showPower = false,
        showPowerText = true,
    },
}
translate(native60, { source = "profiles", markProfile = true, trustNormalizationMarker = true })
assert(native60.target.detachedPowerBarAnchorMode == nil,
    "native 6.0 profile was incorrectly changed to legacy detached anchoring")
assert(native60.bars.barOutlineStrata == "AUTO"
    and native60._msufLegacy55FrameOutlineBackground_v1 == nil,
    "native 6.0 frame outline strata was incorrectly changed")
assert(native60.target.showPowerText == true
    and native60._msufLegacy55PowerTextVisibility_v1 == nil,
    "native 6.0 split Power Text visibility was incorrectly changed")

io.write("legacy55_profile_migration_smoke: ok\n")
