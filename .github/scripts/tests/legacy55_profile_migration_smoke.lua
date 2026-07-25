_G = _G or _ENV

-- Reuse the full profile/defaults harness so this exercises the same exported
-- migration entrypoint used by imports and SavedVariables startup.
dofile("tools/profile_apply_smoke.lua")

local translate = assert(_G.MSUF_ProfileIO_TranslateProfileToCurrent)

local legacyGroupImport = [[
return {
    addon = "MSUF",
    fmt = 2,
    schema = 1,
    kind = "groupframe",
    payload = {
        gf_party = {
            nameMaxChars = 10,
            nameNoEllipsis = true,
        },
        gf_raid = {
            fontOverride = true,
            nameMaxChars = 8,
            nameNoEllipsis = true,
            nameAnchor = "CENTER",
            nameOffsetX = 2,
            nameOffsetY = 13,
        },
    },
}
]]
assert(_G.MSUF_ImportFromString(legacyGroupImport) == true,
    "5.57 Group-only profile import failed")
assert(_G.MSUF_DB.gf_party.nameAnchor == "LEFT"
    and _G.MSUF_DB.gf_party.nameOffsetX == 0
    and _G.MSUF_DB.gf_party.nameOffsetY == 0
    and _G.MSUF_DB.gf_party._msufLegacyNameAnchorToFrame == true
    and _G.MSUF_DB.gf_party.fontOverride == false,
    "5.57 Group-only import received 6.0 name geometry or override semantics: "
        .. tostring(_G.MSUF_DB.gf_party.nameAnchor) .. ","
        .. tostring(_G.MSUF_DB.gf_party.nameOffsetX) .. ","
        .. tostring(_G.MSUF_DB.gf_party.nameOffsetY) .. ","
        .. tostring(_G.MSUF_DB.gf_party.fontOverride))
assert(_G.MSUF_DB.gf_raid.fontOverride == true
    and _G.MSUF_DB.gf_raid.nameAnchor == "CENTER"
    and _G.MSUF_DB.gf_raid.nameOffsetX == 2
    and _G.MSUF_DB.gf_raid.nameOffsetY == 13
    and _G.MSUF_DB.gf_raid._msufLegacyNameAnchorToFrame == true,
    "5.57 explicit Raid name geometry changed during full import: "
        .. tostring(_G.MSUF_DB.gf_raid.fontOverride) .. ","
        .. tostring(_G.MSUF_DB.gf_raid.nameAnchor) .. ","
        .. tostring(_G.MSUF_DB.gf_raid.nameOffsetX) .. ","
        .. tostring(_G.MSUF_DB.gf_raid.nameOffsetY))

local function legacyFixture()
    return {
        shortenNames = true,
        general = {
            hpTextMode = "CURPERCENT",
            powerTextMode = "PERCENT",
            hpTextSeparator = "|",
            powerTextSeparator = "|",
            shortenNameMaxChars = 15,
            shortenNameClipSide = "RIGHT",
            shortenNameShowDots = true,
            rangeFadePortrait = false,
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
            anchorMyPoint = "TOPLEFT",
            anchorRelPoint = "BOTTOMRIGHT",
            anchorFrameName = "UIParent",
            offsetX = -333.25,
            offsetY = 77.5,
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
            nameOffsetX = 4,
            nameOffsetY = -12,
            hpOffsetX = -4,
            hpOffsetY = -12,
            hpTextAnchor = "RIGHT",
            powerOffsetX = 0,
            powerOffsetY = -8,
            powerTextAnchor = "CENTER",
            showPower = false,
            hlOverride = true,
            barOutlineStrata = "AUTO",
            nameTextLayer = 5,
            groupNumberLayer = 29,
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
        targettarget = {
            showPower = false,
            nameOffsetX = 4,
            nameOffsetY = -8,
            hpOffsetX = -4,
            hpOffsetY = -8,
            hpTextAnchor = "RIGHT",
            powerOffsetX = -4,
            powerOffsetY = 4,
            powerTextAnchor = "RIGHT",
        },
        focustarget = { showPower = false },
        pet = { showPower = true },
        boss = { width = 185, height = 32, showPower = true },
        gf_party = {
            hlOverride = true,
            barOutlineStrata = "AUTO",
            raidGroupNameLayer = 28,
            nameMaxChars = 10,
            nameNoEllipsis = true,
        },
        gf_raid = {
            fontOverride = true,
            nameMaxChars = 8,
            nameNoEllipsis = true,
            nameAnchor = "CENTER",
            nameOffsetX = 2,
            nameOffsetY = 13,
            hpOffsetX = -3,
            hpOffsetY = 4,
            powerOffsetX = 5,
            powerOffsetY = -6,
        },
        gf_mythicraid = {
            nameAnchor = "RIGHT",
            nameOffsetX = -7,
            nameOffsetY = 9,
        },
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
assert(fresh.player.point == "TOPLEFT" and fresh.player.relativePoint == "BOTTOMRIGHT"
    and fresh.player.anchorFrameName == "UIParent"
    and fresh.player.offsetX == -333.25 and fresh.player.offsetY == 77.5,
    "5.57 unit-frame anchor or screen position changed during migration")
assert(fresh.target.nameOffsetX == 4 and fresh.target.nameOffsetY == -12
    and fresh.target.hpOffsetX == -4 and fresh.target.hpOffsetY == -12
    and fresh.target.powerOffsetX == 0 and fresh.target.powerOffsetY == -8
    and fresh.targettarget.nameOffsetX == 4 and fresh.targettarget.nameOffsetY == -8
    and fresh.targettarget.hpOffsetX == -4 and fresh.targettarget.hpOffsetY == -8
    and fresh.targettarget.powerOffsetX == -4 and fresh.targettarget.powerOffsetY == 4,
    "5.57 Target-family text X/Y offsets changed during migration")
for _, unit in ipairs({ "target", "targettarget" }) do
    local text = fresh[unit]
    assert(text.textLeft == "NONE" and text.textCenter == "NONE" and text.textRight == "CURPERCENT"
        and text.powerTextLeft == "NONE" and text.powerTextCenter == "NONE" and text.powerTextRight == "PERCENT"
        and text.hpTextSeparator == "|" and text.powerTextSeparator == "|",
        "5.57 Target-family text slots were not materialized for " .. unit)
end
assert(fresh._msufLegacy55UnitTextSlots_v1 == true,
    "5.57 per-unit text migration marker was not persisted")
assert(fresh.gf_party.nameAnchor == "LEFT"
    and fresh.gf_party.nameOffsetX == 0 and fresh.gf_party.nameOffsetY == 0
    and fresh.gf_party.hpOffsetX == 0 and fresh.gf_party.hpOffsetY == 0
    and fresh.gf_party.powerOffsetX == 0 and fresh.gf_party.powerOffsetY == 0,
    "missing 5.57 Group text coordinates did not retain their legacy defaults")
assert(fresh.gf_raid.nameAnchor == "CENTER"
    and fresh.gf_raid.nameOffsetX == 2 and fresh.gf_raid.nameOffsetY == 13
    and fresh.gf_raid.hpOffsetX == -3 and fresh.gf_raid.hpOffsetY == 4
    and fresh.gf_raid.powerOffsetX == 5 and fresh.gf_raid.powerOffsetY == -6
    and fresh.gf_mythicraid.nameAnchor == "RIGHT"
    and fresh.gf_mythicraid.nameOffsetX == -7 and fresh.gf_mythicraid.nameOffsetY == 9,
    "explicit 5.57 Party/Raid text coordinates were overwritten")
assert(fresh._msufLegacy55GroupTextGeometry_v1 == true,
    "5.57 Group text geometry migration marker was not persisted")
assert(fresh._msufLegacy55GroupNameAnchorRoot_v1 == true
    and fresh.gf_party._msufLegacyNameAnchorToFrame == true
    and fresh.gf_raid._msufLegacyNameAnchorToFrame == true
    and fresh.gf_mythicraid._msufLegacyNameAnchorToFrame == true,
    "5.57 Group name anchor root was not preserved")
assert(fresh.gf_party.fontOverride == false
    and fresh.gf_party.nameMaxChars == 10 and fresh.gf_party.nameNoEllipsis == true,
    "dormant 5.57 Group shortening values incorrectly enabled a local font override")
assert(fresh.gf_raid.fontOverride == true,
    "explicit 5.57 Group font override was lost")
assert(fresh.player.rangeFadeLayerMode == "health"
    and fresh.target.rangeFadeLayerMode == "health"
    and fresh.boss.rangeFadeLayerMode == "health",
    "5.57 keep-portrait-visible range fade was not mapped to the closest 6.0 mode")
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
assert(fresh.target.raidGroupNameLayer == 29 and fresh.gf_party.groupNumberLayer == 28,
    "raid-group/group-number layer compatibility aliases were not migrated")
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
assert(targetBuff.buffLayer == 30 and targetBuff.buffStrata == "AUTO"
    and playerDebuff.debuffLayer == 30 and playerDebuff.debuffStrata == "AUTO",
    "legacy Aura2 z-order did not adopt the relational AUTO-strata layer model")
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
assert(repaired == true and storedV2._msufProfileNormalizationRevision == 12,
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
assert(repairedV3 == true and storedV3._msufProfileNormalizationRevision == 12
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

-- Real 5.57 profiles retain buffOffsetY = 30 even though Aura2 v11f no longer
-- used that retired field for container placement. Only offsetX/Y plus the
-- explicit buff/debuffGroupOffset fields contributed to the visible position.
-- This distilled fixture mirrors the attached 5.57 export.
local function legacy557AuraPositionFixture()
    return {
        player = { width = 275, height = 40 },
        target = { width = 276, height = 40 },
        focus = { width = 216, height = 30 },
        boss = { width = 264, height = 35 },
        auras2 = {
            shared = {
                _msufA2_migrated_v11f = true,
                offsetX = 0,
                offsetY = 6,
                buffOffsetY = 30,
                iconSize = 26,
                growth = "RIGHT",
                rowWrap = "DOWN",
            },
            perUnit = {
                target = { overrideLayout = true, layout = { offsetX = -1, offsetY = 0, iconSize = 26 } },
                focus = { overrideLayout = true, layout = { offsetX = 0, offsetY = -1, iconSize = 26 } },
                boss1 = { overrideLayout = true, layout = { offsetX = 0, offsetY = 0, iconSize = 26 } },
            },
        },
    }
end

local function assertLegacy557AuraPositions(profile, label)
    local expected = {
        player = { 0, 32 },
        target = { -1, 26 },
        focus = { 0, 25 },
        boss1 = { 0, 26 },
    }
    for unit, position in pairs(expected) do
        local layout = assert(profile.auras3.perUnit[unit].layout, label .. ": missing " .. unit .. " layout")
        assert(layout.buffAnchor == "TOPLEFT" and layout.debuffAnchor == "TOPLEFT"
            and layout.buffGroupOffsetX == position[1] and layout.debuffGroupOffsetX == position[1]
            and layout.buffGroupOffsetY == position[2] and layout.debuffGroupOffsetY == position[2],
            label .. ": 5.57 " .. unit .. " aura position changed")
    end
end

local attachedImport = legacy557AuraPositionFixture()
translate(attachedImport, { source = "legacy_import", markProfile = true })
assertLegacy557AuraPositions(attachedImport, "profile import")

-- SavedVariables run through Defaults before Profiles. Exercise that exact
-- two-stage startup path as well, because Defaults owns the first Aura2 copy.
local attachedSavedVariables = legacy557AuraPositionFixture()
assert(_G.MSUF_NormalizeProfileTo60Defaults, "defaults migration entrypoint missing")
_G.MSUF_NormalizeProfileTo60Defaults(attachedSavedVariables)
translate(attachedSavedVariables, { source = "profiles", markProfile = true })
assertLegacy557AuraPositions(attachedSavedVariables, "SavedVariables load")

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
    gf_party = {
        nameMaxChars = 10,
        nameNoEllipsis = true,
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
assert(native60._msufLegacy55UnitTextSlots_v1 == nil,
    "native 6.0 profile was incorrectly routed through legacy text migration")
assert(native60._msufLegacy55GroupTextGeometry_v1 == nil,
    "native 6.0 profile was incorrectly routed through legacy Group text migration")
assert(native60._msufLegacy55GroupNameAnchorRoot_v1 == nil
    and native60.gf_party._msufLegacyNameAnchorToFrame == nil,
    "native 6.0 profile was incorrectly assigned legacy Group name anchoring")
assert(native60.gf_party.fontOverride == true,
    "native 6.0 scoped Group text values no longer infer their font override")

local explicitLegacyText = {
    general = { hpTextMode = "CURPERCENT", powerTextMode = "PERCENT" },
    target = {
        textLeft = "CURRENT",
        textCenter = "PERCENT",
        textRight = "NONE",
        powerTextLeft = "PERCENT",
        powerTextCenter = "NONE",
        powerTextRight = "CURRENT",
    },
}
translate(explicitLegacyText, { source = "snapshot_import", schema = 1, markProfile = true })
assert(explicitLegacyText.target.textLeft == "CURRENT"
    and explicitLegacyText.target.textCenter == "PERCENT"
    and explicitLegacyText.target.textRight == "NONE"
    and explicitLegacyText.target.powerTextLeft == "PERCENT"
    and explicitLegacyText.target.powerTextCenter == "NONE"
    and explicitLegacyText.target.powerTextRight == "CURRENT",
    "explicit 5.57 text-slot choices were overwritten")

-- MSUF 5.57 category snapshots use outer schema 1. A Group-only snapshot has
-- no Aura2 root, so its schema must still route it through legacy visual
-- compatibility before the selected roots are applied to the active profile.
local legacyGroupSnapshot = {
    gf_party = { hlOverride = true, barOutlineStrata = "AUTO" },
}
translate(legacyGroupSnapshot, {
    source = "snapshot_import",
    schema = 1,
    markProfile = false,
    createGeneral = false,
    normalizePositions = false,
})
assert(legacyGroupSnapshot.gf_party.barOutlineStrata == "BACKGROUND",
    "5.57 schema-1 Group-only snapshot bypassed legacy compatibility")
assert(legacyGroupSnapshot.gf_party.nameAnchor == "LEFT"
    and legacyGroupSnapshot.gf_party.nameOffsetX == 0
    and legacyGroupSnapshot.gf_party.nameOffsetY == 0
    and legacyGroupSnapshot.gf_party._msufLegacyNameAnchorToFrame == true,
    "5.57 Group-only snapshot received 6.0 Group name defaults")

-- The 5.57 Group Frame DB migrated these flat fields through
-- GF.MigrateAuraConfig. 6.0 must retain that loader for SavedVariables and
-- partial imports, including explicit disabled states and placement controls.
local previousDB = _G.MSUF_DB
_G.MSUF_DB = {
    general = {},
    gf_party = {
        enabled = true,
        aurasEnabled = false,
        auraMaxIcons = 7,
        auraIconSize = 23,
        auraAnchor = "TOPRIGHT",
        auraGrowthX = "LEFT",
        auraGrowthY = "UP",
        auraSpacing = 3,
        auraPerRow = 5,
        privateAurasEnabled = false,
        privateAuraMax = 2,
        privateAuraSize = 19,
        privateAuraAnchor = "BOTTOMLEFT",
        privateAuraX = 6,
        privateAuraY = -4,
        privateAuraCountdown = false,
    },
    gf_raid = {},
    gf_mythicraid = {},
}
dofile("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
assert(_G.MSUF_GF_EnsureDB, "6.0 Group Frame DB loader missing")
_G.MSUF_GF_EnsureDB()
local migratedGroup = _G.MSUF_DB.gf_party
local migratedAuras = assert(migratedGroup.auras, "5.57 flat Group auras were not materialized")
local migratedBuff = assert(migratedAuras.buff, "5.57 Group buff lane missing")
assert(migratedAuras.enabled == false and migratedBuff.enabled == false
    and migratedBuff.anchor == "TOPRIGHT" and migratedBuff.growth == "LEFTUP"
    and migratedBuff.size == 23 and migratedBuff.max == 7
    and migratedBuff.perRow == 5 and migratedBuff.spacing == 3,
    "5.57 Group aura visibility, placement, size, count, growth, or spacing changed")
local migratedPrivate = assert(migratedGroup.privateAuras, "5.57 private aura config missing")
assert(migratedPrivate.enabled == false and migratedPrivate.max == 2
    and migratedPrivate.size == 19 and migratedPrivate.anchor == "BOTTOMLEFT"
    and migratedPrivate.x == 6 and migratedPrivate.y == -4
    and migratedPrivate.showCountdown == false,
    "5.57 private aura settings changed during migration")
assert(migratedGroup.aurasEnabled == nil and migratedGroup.auraAnchor == nil
    and migratedGroup.privateAurasEnabled == nil and migratedGroup._auraMigV2 == true,
    "5.57 flat Group aura keys were not retired after lossless migration")
_G.MSUF_DB = previousDB

io.write("legacy55_profile_migration_smoke: ok\n")
