-- Regression coverage for Power -> PowerText metadata handoff and fallbacks.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end

local apiType, apiToken = 0, "MANA"
local apiPower, apiMax, apiPercent = 40, 100, 40
local calls = { power = 0, max = 0, percent = 0, powerType = 0, color = 0 }

local function ResetCalls()
    for key in pairs(calls) do calls[key] = 0 end
end

local elements = {}
local UF = {
    RegisterElement = function(name, element) elements[name] = element end,
    FreshUnitState = function() return nil end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}

local Text = {
    UnitHealth = function() return 100 end,
    UnitHealthMax = function() return 100 end,
    UnitPower = function(_, powerType)
        calls.power = calls.power + 1
        calls.lastPowerType = powerType
        return apiPower
    end,
    UnitPowerMax = function(_, powerType)
        calls.max = calls.max + 1
        calls.lastMaxType = powerType
        return apiMax
    end,
    UnitPowerType = function()
        calls.powerType = calls.powerType + 1
        return apiType, apiToken
    end,
    UnitName = function() return "Unit" end,
    UnitHealthPercent = function() return 100 end,
    UnitPowerPercent = function() return apiPercent end,
    HealthPercent = function() return 100 end,
    PowerPercent = function()
        calls.percent = calls.percent + 1
        return apiPercent
    end,
    GetTime = function() return 0 end,
    PowerColor = function(_, _, powerType, powerToken, known)
        calls.color = calls.color + 1
        calls.colorType, calls.colorToken, calls.colorKnown = powerType, powerToken, known
        return 0.2, 0.4, 1
    end,
    SetPowerTextColor = function() calls.colorWrites = (calls.colorWrites or 0) + 1 end,
    SetShownCached = function() end,
    SetTextCached = function() end,
    SetNameTextColor = function() end,
    NameTextColor = function() return 1, 1, 1 end,
    SetInlineTextColor = function() end,
    InlineTextColor = function() return 1, 1, 1 end,
    UpdateHealthTextColor = function() end,
    ResolveHealthTextModes = function() return "NONE", "NONE", "NONE" end,
    EMPTY_EVENTS = {},
    POWER_EVENTS = {},
    POWER_EVENTS_FREQUENT = {},
}

local function RecordText(_, _, cur, maxValue, _, _, _, rt, pct, pctKnown)
    rt.testWrites = (rt.testWrites or 0) + 1
    rt.testCur, rt.testMax, rt.testPct, rt.testPctKnown = cur, maxValue, pct, pctKnown
end
Text.UpdateTextSlots = RecordText
Text.UpdateTextSlotsPlain = RecordText
Text.UpdateTextSlotsSecret = RecordText

local MSUF = {
    UF = UF,
    UFText = Text,
    Secrets = { UnitMissing = function() return false end },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local function NewRuntime(mode, colorByType)
    return {
        powerSlotCount = 1,
        powerSlots = { {} },
        powerPlain = true,
        powerNeedsCurrent = mode == "CURRENT",
        powerNeedsMax = mode == "MAX",
        powerNeedsPercent = mode == "PERCENT",
        powerDispatchKeyMode = mode == "CURRENT" and 1 or (mode == "MAX" and 2 or 4),
        powerColorByType = colorByType == true,
        powerRefreshTypeOnTick = colorByType == true,
        textColorR = 1,
        textColorG = 1,
        textColorB = 1,
        textColorA = 1,
    }
end

local function NewFrame(rt, unit, known)
    local state = {
        unit = unit or "target",
        _msufTextRuntime = rt,
        _msufTextPowerNeedsType = rt.powerNeedsMax or rt.powerNeedsPercent or rt.powerColorByType or nil,
        _msufPowerTextColorInitialized = true,
        _msufPowerTextColorType = rt.powerColorByType and 0 or false,
        _msufPowerTextColorToken = rt.powerColorByType and "MANA" or nil,
    }
    if known ~= false then
        state._msufTextPowerType = 0
        state._msufTextPowerToken = "MANA"
        state._msufTextPowerTypeKnown = true
        state._msufTextPowerTypeUnit = state.unit
    end
    local writes = {}
    local frame = setmetatable({}, {
        __index = state,
        __newindex = function(_, key, value)
            writes[key] = (writes[key] or 0) + 1
            state[key] = value
        end,
    })
    return frame, state, writes
end

local function CacheWrites(writes)
    return (writes._msufTextPowerType or 0)
        + (writes._msufTextPowerToken or 0)
        + (writes._msufTextPowerTypeKnown or 0)
        + (writes._msufTextPowerTypeUnit or 0)
end

-- CURRENT: a bar-fed value tick explicitly reports unchanged metadata. The
-- text runtime must consume the value without reseeding type or a missing max.
local currentRT = NewRuntime("CURRENT", false)
local current, currentState, currentWrites = NewFrame(currentRT)
ResetCalls()
Text.UpdatePower(current, "UNIT_POWER_UPDATE", "target", 41, nil, 0, "MANA", false)
Check(CacheWrites(currentWrites) == 0, "steady CURRENT tick rewrote unchanged power metadata")
Check((currentWrites._msufTextPowerMax or 0) == 0 and (currentWrites._msufTextPowerMaxUnit or 0) == 0,
    "nil CURRENT max entered the max seed")
Check(calls.powerType == 0 and calls.power == 0 and calls.max == 0,
    "bar-fed CURRENT tick performed fallback API reads")
Check(currentRT.testWrites == 1 and currentRT.testCur == 41,
    "CURRENT text lost the shared power value")

-- PERCENT: the bar-owned dispatch percent and unchanged metadata remain a
-- zero-read path even though current/max are intentionally absent.
local percentRT = NewRuntime("PERCENT", false)
percentRT._dispatchPowerPercent, percentRT._dispatchPowerPercentReady = 55, true
local percent, _, percentWrites = NewFrame(percentRT)
ResetCalls()
Text.UpdatePower(percent, "UNIT_POWER_FREQUENT", "target", nil, nil, 0, "MANA", false)
Check(CacheWrites(percentWrites) == 0, "steady PERCENT tick rewrote unchanged power metadata")
Check((percentWrites._msufTextPowerMax or 0) == 0 and calls.percent == 0,
    "PERCENT dispatch reread max/percent instead of consuming the shared value")
Check(percentRT.testWrites == 1 and percentRT.testPct == 55 and percentRT.testPctKnown == true,
    "PERCENT text lost the bar-owned dispatch percent")

-- MAX with no bar payload is intentionally a text-owned fallback. Nil metadata
-- must not suppress the first UnitPowerType/UnitPowerMax read.
local maxRT = NewRuntime("MAX", false)
local maxFrame, maxState = NewFrame(maxRT, "target", false)
ResetCalls()
apiType, apiToken, apiMax = 0, "MANA", 120
Text.UpdatePower(maxFrame, "UNIT_MAXPOWER", "target", nil, nil, nil, nil, nil)
Check(calls.powerType == 1 and calls.max == 1 and calls.lastMaxType == 0,
    "text-only MAX failed to resolve type/max")
Check(maxRT.testWrites == 1 and maxRT.testMax == 120
    and maxState._msufTextPowerMax == 120 and maxState._msufTextPowerMaxUnit == "target",
    "text-only MAX did not seed/render its fallback max")

-- UNIT_DISPLAYPOWER is never eligible for the value-tick shortcut. It must
-- refresh and recolor even when the caller can pass the new metadata directly.
local colorRT = NewRuntime("CURRENT", true)
local colorFrame, colorState, colorWrites = NewFrame(colorRT)
ResetCalls()
Text.UpdatePower(colorFrame, "UNIT_DISPLAYPOWER", "target", 35, nil, 1, "RAGE", true)
Check(colorState._msufTextPowerType == 1 and colorState._msufTextPowerToken == "RAGE"
    and CacheWrites(colorWrites) == 4,
    "UNIT_DISPLAYPOWER did not replace cached type/token")
Check(calls.color == 1 and calls.colorType == 1 and calls.colorToken == "RAGE" and calls.colorKnown == true,
    "UNIT_DISPLAYPOWER did not recolor from the new known type")

-- A differing type on a value tick must also defeat the shortcut. This keeps
-- the path correct if a provider reports a metadata change before displaypower.
local changeRT = NewRuntime("CURRENT", true)
local changeFrame, changeState, changeWrites = NewFrame(changeRT)
ResetCalls()
Text.UpdatePower(changeFrame, "UNIT_POWER_UPDATE", "target", 30, nil, 1, "RAGE", false)
Check(changeState._msufTextPowerType == 1 and changeState._msufTextPowerToken == "RAGE"
    and CacheWrites(changeWrites) == 4 and calls.color == 1,
    "value-tick type change was incorrectly treated as unchanged")

-- Text-only/bar-missing value updates carry nil powerMetaChanged. They must
-- retain the API fallback rather than inheriting the bar-fed shortcut.
local missingRT = NewRuntime("CURRENT", true)
local missingFrame = NewFrame(missingRT, "target", false)
ResetCalls()
apiType, apiToken, apiPower = 2, "FOCUS", 66
Text.UpdatePower(missingFrame, "UNIT_POWER_UPDATE", "target", nil, nil, nil, nil, nil)
Check(calls.powerType == 1 and calls.power == 1 and calls.lastPowerType == 2,
    "bar-missing CURRENT skipped its metadata/value fallback")
Check(missingRT.testWrites == 1 and missingRT.testCur == 66 and calls.color == 1,
    "bar-missing CURRENT failed to render/recolor")

-- Identity events clear token-scoped state before reseeding, even if their
-- metadata flag happens to be false.
local identityRT = NewRuntime("CURRENT", false)
local identityFrame, identityState = NewFrame(identityRT, "target")
ResetCalls()
Text.UpdatePower(identityFrame, "MSUF_UNIT_IDENTITY", "focus", 25, nil, 1, "RAGE", false)
Check(identityState._msufTextPowerTypeUnit == "focus"
    and identityState._msufTextPowerType == 1 and identityState._msufTextPowerToken == "RAGE",
    "identity update reused metadata from the previous unit")

-- Secret metadata is unknown and must never enter equality/cache decisions.
-- A secret max still clears the plain max cache through the guarded seed path.
local secretRT = NewRuntime("CURRENT", false)
local secretFrame, secretState, secretWrites = NewFrame(secretRT)
secretState._msufTextPowerMax, secretState._msufTextPowerMaxUnit = 100, "target"
ResetCalls()
Text.UpdatePower(secretFrame, "UNIT_POWER_UPDATE", "target", 20, SECRET, SECRET, SECRET, false)
Check(secretState._msufTextPowerType == 0 and secretState._msufTextPowerToken == "MANA"
    and CacheWrites(secretWrites) == 0,
    "secret type/token mutated the plain metadata cache")
Check(secretState._msufTextPowerMax == nil and secretState._msufTextPowerMaxUnit == nil,
    "secret max remained in the plain max cache")

print("PASS power text metadata hotpath: CURRENT/MAX/PERCENT, fallbacks, colors, identity, secrets")
