--- Devourer Demon Hunter class power segmentation.
--- Blizzard's own bar (DemonHunterSoulFragmentsBar:GetCurrentMinMaxPower) exposes
--- an integer maximum - the collapsing star cost inside Void Metamorphosis, Dark
--- Heart's max cumulative applications outside it - so MSUF renders pips and the
--- Separator / Pip gap sliders apply. Whenever that count is secret, missing, or
--- degenerate the bar must fall back to the normalized single-bar rendering that
--- shipped before, which is what keeps older clients working unchanged.

local root = (... and ... ~= "" and ...) or "."

_G.MSUF_NS = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Constants.lua"))()
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Modes.lua"))()
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Core.lua"))()

local CPConst = assert(_G.MSUF_CP_CONST, "ClassPower constants must export MSUF_CP_CONST")
local CPK = assert(CPConst.CPK, "constants must expose CPK")
local DARK_HEART = assert(CPK.SPELL.DARK_HEART)
local WHISPERS = assert(CPK.SPELL.SILENCE_THE_WHISPERS)
local VOID_META = assert(CPK.SPELL.VOID_METAMORPHOSIS)

--- Secret values are modelled as tables: they are readable as values but must
--- never be compared or used as arithmetic operands.
local function NotSecret(value) return type(value) == "number" end

-- RESOLVER: the shared segment-count contract.
local resolve = assert(CPConst.ResolveDevourerSegments,
    "constants must expose ResolveDevourerSegments for the runtime and the full refresh")

local darkHeartMaxCalls, collapsingStarCalls = 0, 0
local darkHeartMax, collapsingStarCost = 5, 4
_G.C_Spell = {
    GetSpellMaxCumulativeAuraApplications = function(spellID)
        assert(spellID == DARK_HEART, "Dark Heart max must be queried for the Dark Heart spell")
        darkHeartMaxCalls = darkHeartMaxCalls + 1
        return darkHeartMax
    end,
}
_G.GetCollapsingStarCost = function()
    collapsingStarCalls = collapsingStarCalls + 1
    return collapsingStarCost
end

assert(resolve(false, NotSecret) == 5,
    "outside Void Metamorphosis the segment count is Dark Heart's max cumulative applications")
assert(resolve(true, NotSecret) == 4,
    "inside Void Metamorphosis the segment count is the collapsing star cost")

darkHeartMax = { secret = true }
assert(resolve(false, NotSecret) == 1, "a secret max must degrade to the single-bar rendering")
darkHeartMax = nil
assert(resolve(false, NotSecret) == 1, "a missing max must degrade to the single-bar rendering")
darkHeartMax = 1
assert(resolve(false, NotSecret) == 1, "a one-stack max is not a pip row")
darkHeartMax = 12
assert(resolve(false, NotSecret) == CPConst.MAX_CLASS_POWER,
    "the segment count must stay inside the preallocated ClassPower bar budget")
darkHeartMax = 5

local realCSpell, realCollapsing = _G.C_Spell, _G.GetCollapsingStarCost
_G.C_Spell = nil
_G.GetCollapsingStarCost = nil
assert(resolve(false, NotSecret) == 1 and resolve(true, NotSecret) == 1,
    "clients without the Devourer APIs must keep the single-bar rendering")
_G.C_Spell, _G.GetCollapsingStarCost = realCSpell, realCollapsing

-- RENDER: pips when the layout resolved a segment count, single bar otherwise.
local function NewBar()
    local bar = { _bg = { SetVertexColor = function() end } }
    function bar:SetMinMaxValues(lo, hi) self.lo, self.hi = lo, hi end
    function bar:SetValue(value) self.value = value end
    function bar:SetAlpha(alpha) self.alpha = alpha end
    function bar:SetStatusBarColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    function bar:SetShown(shown) self.shown = shown end
    return bar
end

local bars, ticks = {}, {}
for i = 1, 8 do bars[i] = NewBar() end
for i = 1, 7 do
    ticks[i] = { SetShown = function(self, shown) self.shown = shown end }
end
local text = {
    SetText = function(self, value) self.text = value end,
    SetShown = function(self, shown) self.shown = shown end,
}
local CP = { bars = bars, ticks = ticks, maxBars = 8, text = text, renderMode = CPK.MODE.AURA_SINGLE }

local autoHideCur, autoHideMax
local auras = {}
--- Outside Void Metamorphosis that aura is absent, so every lookup of it is a
--- cache miss and a real GetPlayerAuraBySpellID call in the live client. The
--- render and the segment count must therefore share one resolution per event.
local auraLookups = 0
local function LookupAura(spellID)
    auraLookups = auraLookups + 1
    return auras[spellID]
end
local visual = {
    version = 1,
    colorByType = true,
    showText = true,
    bgAlpha = 0.3,
    filledAlpha = 1,
    emptyAlpha = 0.3,
}
local aura = assert(_G.MSUF_CP_MODE_BUILDERS.AURA)({
    CP = CP,
    _cpDB = { bars = {} },
    CPK = CPK,
    TIP = CPConst.TIP,
    WW = { MAX_STACKS = 4, GetStacks = function() return 0 end },
    C_Spell = _G.C_Spell,
    C_UnitAuras = {},
    GetTrackedPlayerAura = LookupAura,
    GetTime = function() return 100 end,
    NotSecret = NotSecret,
    ResolveClassPowerBgColor = function() return 0, 0, 0 end,
    ResolveMWAbove5Color = function() return 1, 0.5, 0 end,
    CP_CheckAutoHide = function(cur, max) autoHideCur, autoHideMax = cur, max end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
})
local UpdateSingle = assert(aura.UpdateSingle, "the aura mode must expose UpdateSingle")

-- Outside Void Metamorphosis: 3 of 5 Dark Heart stacks light up 3 pips.
auras[DARK_HEART] = { applications = 3 }
local darkHeartMaxCallsBefore = darkHeartMaxCalls
UpdateSingle("SOUL_FRAGMENTS", 5)
for i = 1, 3 do
    assert(bars[i].value == 1 and bars[i].alpha == 1,
        "filled Devourer pips must use the full value and filled alpha")
end
for i = 4, 5 do
    assert(bars[i].value == 0 and bars[i].alpha == 0.3,
        "empty Devourer pips must use the empty alpha")
end
assert(autoHideCur == 3 and autoHideMax == 5,
    "auto-hide must see real stacks against the real segment count")
assert(text.text == 3 and text.shown == true, "resource text must keep showing the raw stack count")
assert(darkHeartMaxCalls == darkHeartMaxCallsBefore,
    "segmented rendering must not re-query the normalization divisor it no longer needs")

-- Inside Void Metamorphosis: Silence the Whispers stacks against the star cost.
auras[VOID_META] = { applications = 1 }
auras[WHISPERS] = { applications = 2 }
local collapsingStarCallsBefore = collapsingStarCalls
UpdateSingle("SOUL_FRAGMENTS", 4)
assert(bars[1].value == 1 and bars[2].value == 1 and bars[3].value == 0 and bars[4].value == 0,
    "Void Metamorphosis pips must follow Silence the Whispers stacks")
assert(autoHideCur == 2 and autoHideMax == 4, "meta auto-hide must use the collapsing star segment count")
assert(collapsingStarCalls == collapsingStarCallsBefore,
    "segmented meta rendering must not re-query the collapsing star cost")

-- Fallback: an unresolved count keeps the pre-existing normalized single bar.
auras[VOID_META], auras[WHISPERS] = nil, nil
for i = 1, 8 do
    bars[i].value, bars[i].alpha, bars[i].shown = nil, nil, nil
    bars[i]._msufCPAlpha, bars[i]._msufCPShown = nil, nil
end
for i = 1, 7 do ticks[i].shown, ticks[i]._msufCPShown = nil, nil end
UpdateSingle("SOUL_FRAGMENTS", 1)
assert(bars[1].value == 3 / 5,
    "the single-bar fallback must normalize stacks against the readable maximum")
assert(autoHideCur == 1 and autoHideMax == 1, "the single bar keeps its binary auto-hide contract")
for i = 2, 8 do
    assert(bars[i].shown == false, "leaving pip rendering must hide the unused bars")
end
for i = 1, 7 do
    assert(ticks[i].shown == false, "the single bar must not leave pip separators behind")
end

-- Secret stacks must not be compared or divided.
auras[DARK_HEART] = { applications = { secret = true } }
UpdateSingle("SOUL_FRAGMENTS", 5)
assert(autoHideCur == 0 and autoHideMax == 5, "secret stacks must render as an empty pip row")
assert(text.shown == false, "secret stacks must not print a resource value")

-- RUNTIME: the aura event must not pay for the segment count it rarely needs.
auras[DARK_HEART] = { applications = 3 }
CP.visible, CP.isAuraPower, CP.powerType, CP.currentMax = true, true, "SOUL_FRAGMENTS", 5
CP.dhInMeta, CP._dhSegCount, CP._dhSegMeta = nil, nil, nil

local layoutCalls, ensureCalls, updateCalls = 0, 0, 0
local runtime = assert(_G.MSUF_CP_FEATURE_BUILDERS.RUNTIME)({
    CP = CP,
    AM = { visible = false },
    _cpDB = { bars = { classPowerHeight = 6 } },
    CPK = CPK,
    CPConst = CPConst,
    POWER_TYPE_TOKENS = CPConst.POWER_TYPE_TOKENS,
    NotSecret = NotSecret,
    C_Spell = _G.C_Spell,
    tonumber = tonumber,
    math_floor = math.floor,
    GetTrackedPlayerAura = LookupAura,
    GetPlayerFrame = function() return {} end,
    CP_EnsureBars = function() ensureCalls = ensureCalls + 1 end,
    CP_Layout = function(_pf, maxPower)
        layoutCalls = layoutCalls + 1
        CP.currentMax = maxPower
    end,
    RefreshChargedPoints = function() end,
    RunActiveUpdate = function(powerType, maxP)
        updateCalls = updateCalls + 1
        UpdateSingle(powerType, maxP)
    end,
})
local OnAuraUpdate = assert(runtime.OnAuraUpdate, "runtime must expose OnAuraUpdate")

-- First event: resolves and memoizes; still exactly one value update, no relayout.
local maxCallsBefore = darkHeartMaxCalls
auraLookups, updateCalls, layoutCalls = 0, 0, 0
OnAuraUpdate("player")
assert(updateCalls == 1 and layoutCalls == 0,
    "a steady-state aura event must be one value update and no relayout")
assert(auraLookups == 2,
    "the render and the segment count must share one meta resolution: "
    .. tostring(auraLookups) .. " aura lookups")
assert(darkHeartMaxCalls == maxCallsBefore + 1, "the static maximum is read once")

-- Second event: the memo must absorb it completely.
auraLookups, updateCalls, layoutCalls = 0, 0, 0
OnAuraUpdate("player")
assert(updateCalls == 1 and layoutCalls == 0 and auraLookups == 2,
    "repeat events must not add work")
assert(darkHeartMaxCalls == maxCallsBefore + 1,
    "the out-of-meta maximum is a static spell value and must not be re-queried per event")

-- Entering Void Metamorphosis is the one trigger that may relayout.
auras[VOID_META] = { applications = 1 }
auras[WHISPERS] = { applications = 2 }
collapsingStarCost = 4
local starCallsBefore = collapsingStarCalls
layoutCalls, ensureCalls = 0, 0
OnAuraUpdate("player")
assert(layoutCalls == 1 and ensureCalls == 1 and CP.currentMax == 4,
    "entering meta must relayout once to the collapsing star segment count")
assert(collapsingStarCalls == starCallsBefore + 1, "the star cost is read once for that transition")

-- Staying in meta re-reads the cost (it can change) but must not relayout again.
layoutCalls = 0
OnAuraUpdate("player")
assert(layoutCalls == 0 and CP.currentMax == 4, "an unchanged cost must not relayout")
assert(collapsingStarCalls == starCallsBefore + 2,
    "the collapsing star cost must stay live because it can change during meta")

-- A cost change inside meta reaches the layout.
collapsingStarCost = 3
layoutCalls = 0
OnAuraUpdate("player")
assert(layoutCalls == 1 and CP.currentMax == 3, "a changed star cost must resegment the bar")

-- Leaving meta returns to the Dark Heart count and re-arms the memo.
auras[VOID_META], auras[WHISPERS] = nil, nil
layoutCalls = 0
OnAuraUpdate("player")
assert(layoutCalls == 1 and CP.currentMax == 5, "leaving meta must restore the Dark Heart count")
local maxCallsAfterExit = darkHeartMaxCalls
layoutCalls = 0
OnAuraUpdate("player")
assert(layoutCalls == 0 and darkHeartMaxCalls == maxCallsAfterExit,
    "the out-of-meta memo must re-arm after the transition")

print("classpower devourer pips smoke: ok")
