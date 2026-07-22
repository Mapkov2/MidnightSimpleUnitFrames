local root = (... and ... ~= "" and ...) or "."

_G.MSUF_NS = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Modes.lua"))()

local smoothToken = 73
local value, maxValue = 41, 100
local calls = {}
local bar = {
    SetValue = function(_, v, interp)
        calls[#calls + 1] = { value = v, interp = interp }
    end,
    SetMinMaxValues = function() end,
    SetAlpha = function() end,
    SetShown = function() end,
    SetStatusBarColor = function() end,
    _bg = { SetVertexColor = function() end },
}
local visual = {
    smoothInterp = smoothToken,
    filledAlpha = 1,
    emptyAlpha = 0.3,
    baseR = 1, baseG = 1, baseB = 1,
    bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.3,
    version = 1,
}
local cp = { bars = { bar }, ticks = {}, maxBars = 1, renderMode = 6 }
local continuous = assert(_G.MSUF_CP_MODE_BUILDERS.CONTINUOUS)({
    CP = cp,
    UnitPower = function() return value end,
    UnitPowerMax = function() return maxValue end,
    NotSecret = function(v) return type(v) == "number" end,
    CP_CheckAutoHide = function() end,
    GetFilledAlpha = function() return 1 end,
    GetVisual = function() return visual end,
})

continuous.Update(11, 1)
assert(calls[#calls].value == value and calls[#calls].interp == smoothToken,
    "continuous ClassPower must use native interpolation")
visual.smoothInterp = nil
value = 42
continuous.Update(11, 1)
assert(calls[#calls].value == value and calls[#calls].interp == nil,
    "continuous ClassPower must support immediate fill")

local secretPower = {}
local secretRanges = {}
local secretBars = {}
for i = 1, 2 do
    secretBars[i] = {
        SetValue = function(_, v, interp)
            assert(v == secretPower and interp == nil,
                "secret segmented power must use immediate native StatusBar writes")
        end,
        SetMinMaxValues = function(_, lo, hi)
            secretRanges[i] = { lo, hi }
        end,
        SetAlpha = function() end,
    }
end
local segmented = assert(_G.MSUF_CP_MODE_BUILDERS.SEGMENTED)({
    CP = { bars = secretBars },
    PT = { Essence = 19 },
    PLAYER_CLASS = "ROGUE",
    UnitPower = function() return secretPower end,
    NotSecret = function(v) return v ~= secretPower end,
    GetVisual = function() return { smoothInterp = smoothToken, filledAlpha = 1 } end,
})
segmented.Update(4, 2)
assert(secretRanges[1][1] == 0 and secretRanges[1][2] == 1
    and secretRanges[2][1] == 1 and secretRanges[2][2] == 2,
    "secret segmented power must use per-pip C-side ranges")

local fractionalRange
local fractionalBar = {
    SetValue = function(_, v, interp)
        assert(v == secretPower and interp == nil,
            "secret fractional power must use immediate native StatusBar writes")
    end,
    SetMinMaxValues = function(_, lo, hi) fractionalRange = { lo, hi } end,
    SetAlpha = function() end,
}
local fractional = assert(_G.MSUF_CP_MODE_BUILDERS.FRACTIONAL)({
    CP = { bars = { fractionalBar } },
    UnitPower = function() return secretPower end,
    UnitPowerDisplayMod = function() return 100 end,
    NotSecret = function(v) return v ~= secretPower end,
    GetVisual = function() return { smoothInterp = smoothToken, filledAlpha = 1 } end,
})
fractional.Update(7, 1)
assert(fractionalRange[1] == 0 and fractionalRange[2] == 100,
    "secret fractional power must use display-mod C-side ranges")

local essenceNow = 100
local essenceBars = {}
for i = 1, 5 do
    essenceBars[i] = {
        SetValue = function(self, v) self.value = v end,
        SetAlpha = function() end,
        SetStatusBarColor = function() end,
        _bg = { SetVertexColor = function() end },
    }
end
local essenceCP = { bars = essenceBars }
local essence = assert(_G.MSUF_CP_MODE_BUILDERS.SEGMENTED)({
    CP = essenceCP,
    PT = { Essence = 19 },
    PLAYER_CLASS = "EVOKER",
    UnitPower = function() return 2 end,
    UnitPartialPower = function() return 500 end,
    GetPowerRegenForPowerType = function() return 0.2 end,
    GetTime = function() return essenceNow end,
    NotSecret = function(v) return type(v) == "number" end,
    CP_CheckAutoHide = function() end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
essence.Update(19, 5)
assert(math.abs((essenceBars[3].value or 0) - 0.5) < 0.001,
    "Essence must initialize recharge from UnitPartialPower")
assert(essenceCP.essenceOUAAny == true, "partial Essence must start the central tick")
essenceNow = 101.25
assert(essence.RuntimeTick(1.25) == true and math.abs((essenceBars[3].value or 0) - 0.75) < 0.001,
    "Essence must visibly advance between power events")
essenceNow = 102.5
assert(essence.RuntimeTick(2.5) == false and essenceCP.essenceOUAAny == false,
    "completed Essence recharge must stop the central tick without another event")

local icicleBars = {}
for i = 1, 5 do
    icicleBars[i] = {
        SetValue = function(self, v) self.value = v end,
        SetMinMaxValues = function() end,
        SetAlpha = function() end,
        SetStatusBarColor = function() end,
        _bg = { SetVertexColor = function() end },
    }
end
local icicleAutoHideCur, icicleAutoHideMax
local aura = assert(_G.MSUF_CP_MODE_BUILDERS.AURA)({
    CP = { bars = icicleBars },
    _cpDB = {},
    CPK = { SPELL = { ICICLES = 205473 } },
    WW = { GetStacks = function() return 0 end },
    C_Spell = {},
    GetTrackedPlayerAura = function(spellID)
        assert(spellID == 205473, "Icicles must use the configured watched aura")
        return { applications = 3 }
    end,
    NotSecret = function(v) return type(v) == "number" end,
    CP_CheckAutoHide = function(cur, maxPower)
        icicleAutoHideCur, icicleAutoHideMax = cur, maxPower
    end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
aura.UpdateSegmented("ICICLES", 5)
for i = 1, 5 do
    assert(icicleBars[i].value == (i <= 3 and 1 or 0),
        "Icicles must fill exactly the aura stack count")
end
assert(icicleAutoHideCur == 3 and icicleAutoHideMax == 5,
    "Icicles auto-hide state must use the five-stack resource maximum")

local secretIcicleApplications = {}
local nativeIcicleCP = { bars = icicleBars, icicleNativeText = {} }
local nativeAura = assert(_G.MSUF_CP_MODE_BUILDERS.AURA)({
    CP = nativeIcicleCP,
    _cpDB = {},
    CPK = { SPELL = { ICICLES = 205473 } },
    WW = { GetStacks = function() return 0 end },
    C_Spell = {},
    GetTrackedPlayerAura = function() return { applications = secretIcicleApplications } end,
    NotSecret = function(v) return v ~= secretIcicleApplications end,
    CP_CheckAutoHide = function(cur) icicleAutoHideCur = cur end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
icicleAutoHideCur = "unset"
nativeAura.UpdateSegmented("ICICLES", 5)
assert(icicleAutoHideCur == nil,
    "native Icicles sensor must retain parent visibility for secret stack counts")

local runeNow = 100
local runeTextValue
local runeBar = {
    SetValue = function(self, v) self.value = v end,
    SetMinMaxValues = function() end,
    SetAlpha = function() end,
    SetShown = function() end,
    SetStatusBarColor = function() end,
    _bg = { SetVertexColor = function() end },
    _runeText = {
        SetText = function(_, value) runeTextValue = value end,
        Show = function() end,
        Hide = function() end,
    },
}
local runeCP = { bars = { runeBar }, ticks = {}, maxBars = 1 }
local rune = assert(_G.MSUF_CP_MODE_BUILDERS.RUNE)({
    CP = runeCP,
    _cpDB = { bars = {} },
    GetTime = function() return runeNow end,
    GetRuneCooldown = function() return 95, 10, false end,
    UnitHasVehicleUI = function() return false end,
    CP_CheckAutoHide = function() end,
    CP_ApplyRuneSortOrder = function() end,
    GetRuneMap = function() return { 1 } end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
rune.Update(5, 1)
assert(runeCP.runeOUAAny == true, "recharging rune must start the central tick")
runeNow = 102.5
assert(rune.RuntimeTick(2.5) == true and runeTextValue == "2.5",
    "rune countdown text must advance between RUNE_POWER_UPDATE events")
runeNow = 105
assert(rune.RuntimeTick(5) == false and runeCP.runeOUAAny == false,
    "completed rune recharge must stop the central tick without another event")

local timerNow, timerExpiration = 10, 11
local timerBar = {
    SetValue = function(self, v) self.value = v end,
    SetMinMaxValues = function() end,
    SetAlpha = function() end,
    SetShown = function() end,
    SetStatusBarColor = function() end,
    _bg = { SetVertexColor = function() end },
}
local timerCP = { bars = { timerBar }, ticks = {}, maxBars = 1, visible = true, renderMode = 8, powerType = "EBON_MIGHT" }
local timer = assert(_G.MSUF_CP_MODE_BUILDERS.TIMER)({
    CP = timerCP,
    GetTrackedPlayerAura = function() return { expirationTime = timerExpiration } end,
    NotSecret = function(v) return type(v) == "number" end,
    GetTime = function() return timerNow end,
    EBON = { SPELL_ID = 395296, MAX_DURATION = 20 },
    CPK = { MODE = { TIMER_BAR = 8 } },
    CP_CheckAutoHide = function() end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
assert(timer.Update("EBON_MIGHT", 1) == true, "active Ebon Might must start its timer tick")
timer.SetOnUpdate(true)
assert(timer.RuntimeTick(0.03) == true, "Ebon Might must retain sub-frame timer progress")
timer.SetOnUpdate(true)
timerNow = 12
assert(timer.RuntimeTick(0.02) == false and timerCP.tbOUA == false,
    "expired Ebon Might must stop the central tick without another aura event")

local staggerColor
local staggerValue = 30
local staggerBar = {
    SetValue = function() end,
    SetMinMaxValues = function() end,
    SetAlpha = function() end,
    SetShown = function() end,
    SetStatusBarColor = function(_, r, g, b) staggerColor = { r, g, b } end,
    _bg = { SetVertexColor = function() end },
}
local staggerCP = { bars = { staggerBar }, ticks = {}, maxBars = 1, renderMode = 9, visible = true, powerType = "STAGGER" }
local stagger = assert(_G.MSUF_CP_MODE_BUILDERS.STAGGER)({
    CP = staggerCP,
    CPK = { MODE = { STAGGER = 9 } },
    _cpDB = {},
    NotSecret = function(v) return type(v) == "number" end,
    UnitStagger = function() return staggerValue end,
    UnitHealthMax = function() return 100 end,
    CP_CheckAutoHide = function() end,
    STAGGER_CONST = {
        YELLOW_TRANSITION = 0.3,
        RED_TRANSITION = 0.6,
        COLOR_DEFAULTS = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
    },
    GetFilledAlpha = function() return 1 end,
    GetVisual = function() return visual end,
})
assert(stagger.Update("STAGGER", 1) == true, "active Stagger must start the central tick")
assert(staggerColor and staggerColor[1] == 1 and staggerColor[2] == 1 and staggerColor[3] == 0,
    "Stagger must enter yellow at Blizzard's inclusive 30 percent boundary")
staggerValue = 0
assert(stagger.RuntimeTick() == false, "cleared Stagger must stop the central tick")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_AltMana.lua"))()
local altCurrent, altMax = 60, 120
local altCalls = { value = 0, range = 0 }
local altBar = {
    SetValue = function(_, v, interp)
        altCalls.value = altCalls.value + 1
        altCalls.lastValue, altCalls.valueInterp = v, interp
    end,
    SetMinMaxValues = function(_, lo, hi, interp)
        altCalls.range = altCalls.range + 1
        altCalls.lo, altCalls.hi, altCalls.rangeInterp = lo, hi, interp
    end,
}
local am = { bar = altBar }
local cpDB = { altManaSmooth = true, bars = {} }
local alt = assert(_G.MSUF_CP_CORE_BUILDERS.ALT_MANA)({
    AM = am,
    _cpDB = cpDB,
    PT = { Mana = 0 },
    PLAYER_CLASS = "DRUID",
    NotSecret = function(v) return type(v) == "number" end,
    UnitPower = function() return altCurrent end,
    UnitPowerMax = function() return altMax end,
    Enum = { StatusBarInterpolation = { ExponentialEaseOut = smoothToken } },
    tonumber = tonumber,
})

alt.AM_UpdateValue()
assert(altCalls.valueInterp == smoothToken and altCalls.rangeInterp == smoothToken,
    "Alternative Mana must use native interpolation")
local oldValueCalls, oldRangeCalls = altCalls.value, altCalls.range
alt.AM_UpdateValue()
assert(altCalls.value == oldValueCalls and altCalls.range == oldRangeCalls,
    "Alternative Mana must suppress duplicate non-secret StatusBar writes")

local secretAltCurrent, secretAltMax = {}, {}
altCurrent, altMax = secretAltCurrent, secretAltMax
alt.AM_UpdateValue()
assert(altCalls.lastValue == secretAltCurrent and altCalls.hi == secretAltMax,
    "secret Alternative Mana values must still reach the native StatusBar")
assert(altCalls.valueInterp == nil and altCalls.rangeInterp == nil,
    "secret Alternative Mana value/range writes must be immediate")
assert(am._currentValue == nil and am._maxValue == nil,
    "secret Alternative Mana values must not enter comparison caches")

cpDB.altManaSmooth = false
altCurrent, altMax = 61, 120
alt.AM_UpdateValue()
assert(altCalls.lastValue == 61 and altCalls.valueInterp == nil,
    "Alternative Mana must support immediate fill")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua"))()
local secretHP, secretMaxHP = {}, {}
local playerHPValue, playerHPMax = secretHP, secretMaxHP
local playerHPCalls = {}
local playerHPBar = {
    _msufSmoothInterp = smoothToken,
    _msufInterpolating = true,
    SetMinMaxValues = function(_, lo, hi)
        playerHPCalls.lo, playerHPCalls.hi = lo, hi
    end,
    SetValue = function(_, value, interp)
        playerHPCalls.value, playerHPCalls.interp = value, interp
    end,
    SetStatusBarColor = function() end,
}
local playerHPState = {
    visible = true,
    bar = playerHPBar,
    _colorMode = "DARK",
}
_G.issecretvalue = function(value)
    return value == secretHP or value == secretMaxHP
end
local playerHP = assert(_G.MSUF_CP_CORE_BUILDERS.PLAYER_HP)({
    PHP = playerHPState,
    CP = {},
    _cpDB = { bars = {} },
    UnitHealth = function() return playerHPValue end,
    UnitHealthMax = function() return playerHPMax end,
    UnitClass = function() return nil, nil end,
    RAID_CLASS_COLORS = {},
    GetPlayerFrame = function() return nil end,
})

playerHP.Update("UNIT_HEALTH")
assert(playerHPCalls.value == secretHP and playerHPCalls.hi == secretMaxHP,
    "secret Player HP values must still reach the native StatusBar fallback")
assert(playerHPCalls.interp == nil and playerHPBar._msufInterpolating == nil,
    "secret Player HP fallback must cancel interpolation and write immediately")
assert(playerHPState._hp == nil and playerHPState._maxHP == nil,
    "secret Player HP values must not enter comparison caches")

playerHPValue, playerHPMax = 62, 100
playerHP.Update("UNIT_HEALTH")
assert(playerHPCalls.value == 62 and playerHPCalls.interp == smoothToken
    and playerHPBar._msufInterpolating == true,
    "ordinary Player HP fallback lost configured smooth interpolation")

print("classpower smooth runtime smoke: ok")
