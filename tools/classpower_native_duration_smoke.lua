local root = (... and ... ~= "" and ...) or "."

_G.MSUF_NS = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Modes.lua"))()
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Core.lua"))()

local EnumStub = {
    StatusBarInterpolation = { Immediate = 1 },
    StatusBarTimerDirection = { ElapsedTime = 2, RemainingTime = 3 },
    DurationTextBindingProperty = { RemainingDuration = 4 },
    NumericRuleFormatRounding = { Nearest = 5 },
}

local durationCreates = 0
local function NewDuration()
    durationCreates = durationCreates + 1
    local duration = { resetCount = 0 }
    function duration:SetTimeFromStart(startTime, total)
        self.startTime, self.total, self.endTime = startTime, total, startTime + total
        self.from = "start"
    end
    function duration:SetTimeFromEnd(endTime, total)
        self.endTime, self.total, self.startTime = endTime, total, endTime - total
        self.from = "end"
    end
    function duration:GetEndTime()
        return self.endTime
    end
    function duration:Reset()
        self.resetCount = self.resetCount + 1
    end
    return duration
end

local bindingCreates = 0
local function NewBinding()
    bindingCreates = bindingCreates + 1
    local binding = { enabled = false }
    function binding:SetFontString(fontString) self.fontString = fontString end
    function binding:SetUpdateInterval(interval) self.interval = interval end
    function binding:SetExpiredText(text) self.expiredText = text end
    function binding:SetZeroDurationText(text) self.zeroText = text end
    function binding:SetTextFormat(format, components)
        self.format, self.components = format, components
    end
    function binding:SetDuration(duration)
        self.duration = duration
        self.durationCalls = (self.durationCalls or 0) + 1
    end
    function binding:Enable() self.enabled = true end
    function binding:Disable() self.enabled = false end
    return binding
end

local DurationUtilStub = {
    CreateDuration = NewDuration,
    CreateDurationTextBinding = NewBinding,
}

local StringUtilStub = {
    CreateNumericRuleFormatter = function()
        local formatter = {}
        function formatter:SetBreakpoints(breakpoints) self.breakpoints = breakpoints end
        return formatter
    end,
}

local function NewFontString()
    return {
        shown = false,
        SetText = function(self, text) self.text = text end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetPoint = function() end,
        SetJustifyH = function() end,
        SetJustifyV = function() end,
        SetFontObject = function() end,
        SetTextColor = function() end,
        SetShadowColor = function() end,
        SetShadowOffset = function() end,
    }
end

local function NewBar()
    return {
        SetValue = function(self, value) self.value = value end,
        SetMinMaxValues = function(self, lo, hi) self.lo, self.hi = lo, hi end,
        SetAlpha = function() end,
        SetShown = function() end,
        SetStatusBarColor = function() end,
        SetTimerDuration = function(self, duration, interpolation, direction)
            self.timerCalls = (self.timerCalls or 0) + 1
            self.timerDuration = duration
            self.timerInterpolation = interpolation
            self.timerDirection = direction
        end,
        _bg = { SetVertexColor = function() end },
    }
end

local visual = {
    version = 1,
    baseR = 1, baseG = 1, baseB = 1,
    bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.3,
    filledAlpha = 1, emptyAlpha = 0.3,
    runeShowTime = true,
    timerShowText = true,
}

-- BUILD: bars remain preallocated, but both main and Rune text are truly lazy.
local fontStringCreates = 0
local function NewTexture()
    return {
        SetAllPoints = function() end,
        SetTexture = function() end,
        SetVertexColor = function() end,
        Hide = function() end,
    }
end
local function CreateFrameStub()
    local frame = {
        level = 1,
        SetStatusBarTexture = function() end,
        SetMinMaxValues = function() end,
        SetValue = function() end,
        Hide = function() end,
        SetFrameLevel = function(self, level) self.level = level end,
        GetFrameLevel = function(self) return self.level end,
        SetAllPoints = function() end,
        CreateTexture = function() return NewTexture() end,
        CreateFontString = function()
            fontStringCreates = fontStringCreates + 1
            return NewFontString()
        end,
    }
    return frame
end
local buildCP = { bars = {}, ticks = {}, maxBars = 0 }
local build = assert(_G.MSUF_CP_CORE_BUILDERS.BUILD)({
    CP = buildCP,
    _cpDB = { bars = {} },
    CreateFrame = CreateFrameStub,
    CP_ResolveTexture = function() return "white" end,
})
build.CP_Create(CreateFrameStub())
assert(buildCP.maxBars == 8 and fontStringCreates == 0,
    "ClassPower construction must not eagerly create main or Rune FontStrings")
local firstRuneText, runeTextCreated = build.CP_EnsureRuneText(buildCP.bars[1])
assert(firstRuneText and runeTextCreated and fontStringCreates == 1,
    "first used Rune bar must lazily create exactly one FontString")
assert(build.CP_EnsureRuneText(buildCP.bars[1]) == firstRuneText and fontStringCreates == 1,
    "Rune FontString must be reusable")
local mainText, mainTextCreated = build.CP_EnsureMainText()
assert(mainText and mainTextCreated and fontStringCreates == 2,
    "main ClassPower text must be lazy")
assert(build.CP_EnsureMainText() == mainText and fontStringCreates == 2,
    "main ClassPower text must be reusable")

-- Essence: native elapsed timer, stable-signature suppression, and rate resync.
local essenceNow, essencePartial, essenceRate, essenceCurrent = 100, 500, 0.2, 2
local essenceBars = {}
for i = 1, 5 do essenceBars[i] = NewBar() end
local essenceCP = { bars = essenceBars }
local essence = assert(_G.MSUF_CP_MODE_BUILDERS.SEGMENTED)({
    CP = essenceCP,
    PT = { Essence = 19 },
    PLAYER_CLASS = "EVOKER",
    UnitPower = function() return essenceCurrent end,
    UnitPartialPower = function() return essencePartial end,
    GetPowerRegenForPowerType = function() return essenceRate end,
    GetTime = function() return essenceNow end,
    NotSecret = function(value) return type(value) == "number" end,
    CP_CheckAutoHide = function() end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
    C_DurationUtil = DurationUtilStub,
    C_StringUtil = StringUtilStub,
    Enum = EnumStub,
})
essence.Update(19, 5)
local essenceDuration = assert(essenceBars[3].timerDuration, "Essence must bind a native duration")
assert(essenceDuration.startTime == 97.5 and essenceDuration.total == 5,
    "Essence native duration must preserve partial progress and regen rate")
assert(essenceBars[3].timerDirection == EnumStub.StatusBarTimerDirection.ElapsedTime,
    "Essence must fill in elapsed-time direction")
assert(essenceCP.essenceOUAAny == false and essence.RuntimeTick(1) == false,
    "native Essence must not retain the Lua runtime tick")
local firstEssenceTimerCalls = essenceBars[3].timerCalls
essenceNow, essencePartial = 100.1, 520
essence.Update(19, 5)
assert(essenceBars[3].timerCalls == firstEssenceTimerCalls,
    "small frequent-event drift must not rebind the native Essence timer")
essenceRate = 0.25
essence.Update(19, 5)
assert(essenceBars[3].timerCalls == firstEssenceTimerCalls + 1 and essenceDuration.total == 4,
    "Essence regen-rate changes must resync the native duration")
essenceBars[3]._msufEssenceValue = 1
essenceBars[3]._msufEssenceValueVersion = 0
essenceCurrent = 3
essence.Update(19, 5)
assert(essenceBars[3].value == 1 and essenceDuration.resetCount == 1,
    "leaving native Essence must invalidate Lua value stamps before the ready write")

-- Runes: duration and text binding are lazy and reusable; no central tick.
local runeNow, runeReady = 100, false
local runeBar = NewBar()
local runeCP = { bars = { runeBar }, ticks = {}, maxBars = 1 }
local runeTextCreates, fontApplies = 0, 0
local rune = assert(_G.MSUF_CP_MODE_BUILDERS.RUNE)({
    CP = runeCP,
    _cpDB = { bars = {} },
    GetTime = function() return runeNow end,
    GetRuneCooldown = function() return 95, 10, runeReady end,
    UnitHasVehicleUI = function() return false end,
    CP_CheckAutoHide = function() end,
    CP_ApplyRuneSortOrder = function() end,
    GetRuneMap = function() return { 1 } end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
    EnsureRuneText = function(bar)
        if bar._runeText then return bar._runeText, false end
        runeTextCreates = runeTextCreates + 1
        bar._runeText = NewFontString()
        return bar._runeText, true
    end,
    ApplyFont = function() fontApplies = fontApplies + 1 end,
    C_DurationUtil = DurationUtilStub,
    C_StringUtil = StringUtilStub,
    Enum = EnumStub,
})
rune.Update(5, 1)
local runeDuration = assert(runeBar.timerDuration, "Rune must bind a native duration")
assert(runeDuration.startTime == 95 and runeDuration.total == 10,
    "Rune duration must use GetRuneCooldown start and total")
assert(runeBar.timerDirection == EnumStub.StatusBarTimerDirection.ElapsedTime,
    "Rune must fill in elapsed-time direction")
assert(runeTextCreates == 1 and fontApplies == 1 and bindingCreates >= 1,
    "Rune text and binding must be created only for an actually recharging rune")
assert(runeCP.runeOUAAny == false and runeCP.runeNativeAny == true and rune.RuntimeTick(1) == false,
    "native Runes must not retain the Lua runtime tick")
local runeTimerCalls = runeBar.timerCalls
rune.Update(5, 1)
assert(runeBar.timerCalls == runeTimerCalls and runeTextCreates == 1,
    "unchanged Rune state must reuse its duration, binding, and FontString")
runeReady = true
rune.Update(5, 1)
assert(runeDuration.resetCount == 1 and runeBar._runeText.shown == false,
    "ready Rune must reset native state and hide its duration text")

-- Ebon Might: fixed 20-second bar scale, real aura duration for text.
local timerNow = 10
local aura = { auraInstanceID = 77, expirationTime = 30 }
local sourceDuration = NewDuration()
sourceDuration:SetTimeFromEnd(30, 12)
local timerBar = NewBar()
local timerCP = { bars = { timerBar }, ticks = {}, maxBars = 1, visible = true, renderMode = 8, powerType = "EBON_MIGHT" }
local timerText = NewFontString()
local timerTextCreates = 0
local timer = assert(_G.MSUF_CP_MODE_BUILDERS.TIMER)({
    CP = timerCP,
    GetTrackedPlayerAura = function() return aura end,
    C_UnitAuras = { GetAuraDuration = function(unit, auraInstanceID)
        assert(unit == "player" and auraInstanceID == 77)
        return sourceDuration
    end },
    NotSecret = function(value) return type(value) == "number" end,
    GetTime = function() return timerNow end,
    EBON = { SPELL_ID = 395296, MAX_DURATION = 20 },
    CPK = { MODE = { TIMER_BAR = 8 } },
    CP_CheckAutoHide = function() end,
    GetFilledAlpha = function() return 1 end,
    GetEmptyAlpha = function() return 0.3 end,
    GetVisual = function() return visual end,
    EnsureMainText = function()
        if timerCP.text then return timerCP.text, false end
        timerTextCreates = timerTextCreates + 1
        timerCP.text = timerText
        return timerText, true
    end,
    ApplyFont = function() end,
    C_DurationUtil = DurationUtilStub,
    C_StringUtil = StringUtilStub,
    Enum = EnumStub,
})
assert(timer.Update("EBON_MIGHT", 1) == false,
    "native Ebon Might must not request the fallback tick")
local displayDuration = assert(timerBar.timerDuration, "Ebon Might must bind a native bar duration")
assert(displayDuration.endTime == 30 and displayDuration.total == 20,
    "Ebon bar must retain the fixed 20-second visual scale")
assert(timerBar.timerDirection == EnumStub.StatusBarTimerDirection.RemainingTime,
    "Ebon bar must drain in remaining-time direction")
local timerBinding = assert(timerCP._msufCPTimerBinding, "Ebon text must use a native binding")
assert(timerBinding.duration == displayDuration and timerBinding.format == "{}s" and timerTextCreates == 1,
    "Ebon text must bind the stable display duration with the aura's exact end time")
local ebonTimerCalls, ebonBindingCalls = timerBar.timerCalls, timerBinding.durationCalls
timer.Update("EBON_MIGHT", 1)
assert(timerBar.timerCalls == ebonTimerCalls and timerBinding.durationCalls == ebonBindingCalls,
    "unchanged Ebon state must not reapply native bar or text bindings")
sourceDuration:SetTimeFromEnd(35, 25)
aura.expirationTime = 35
timer.Update("EBON_MIGHT", 1)
assert(displayDuration.endTime == 35 and displayDuration.total == 20
    and timerBinding.duration == displayDuration
    and timerBar.timerCalls == ebonTimerCalls
    and timerBinding.durationCalls == ebonBindingCalls,
    "Ebon extensions must mutate the bound duration without rebinding the bar or text")
local secretExpiration = {}
aura.expirationTime = secretExpiration
sourceDuration:SetTimeFromEnd(40, 25)
timer.Update("EBON_MIGHT", 1)
assert(timerCP.timerNativeActive == true and displayDuration.endTime == 40,
    "secret Ebon expiration must stay on the native aura-duration path")
assert(timerBar.timerCalls == ebonTimerCalls and timerBinding.durationCalls == ebonBindingCalls,
    "secret Ebon refreshes must not restart native bar or text bindings")

-- A prior degraded/manual text must not survive when native timing recovers
-- while timer text is disabled, even if no native binding was created yet.
timerCP._msufCPTimerBinding = nil
timerCP._msufCPTimerBindingActive = false
timerText:SetText("stale fallback")
timerText:Show()
visual.timerShowText = false
sourceDuration:SetTimeFromEnd(45, 25)
timer.Update("EBON_MIGHT", 1)
assert(timerText.shown == false and timerText.text == "" and timerText._msufCPShown == false,
    "native no-text mode must clear stale degraded timer text without requiring a binding")
visual.timerShowText = true

print("classpower native duration smoke: ok")
