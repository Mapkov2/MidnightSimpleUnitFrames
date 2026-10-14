-- GF fallback arithmetic uses the live engine owners; native APIs keep priority.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, "Mainline")
local native = {}
world.env.AbbreviateNumbers = tostring
world.env.BreakUpLargeNumbers = tostring
world.env.UnitHealthPercent = function() return native.percent end
world.env.UnitPowerPercent = function() return native.percent end
world.env.UnitHealthMissing = function() return native.missing end
world:Boot()
assert(not world:FirstFailure(), "client graph failed to boot")
local Text, GF = world.core.UFText, world.core.GF
assert(type(Text.PercentFromValues) == "function" and type(Text.MissingHealthFromValues) == "function",
    "the live engine math owners must be shared with return-value callers")
local percentOwner, missingOwner = Text.PercentFromValues, Text.MissingHealthFromValues
-- Identity checks traverse the actual runtime closures, not source-text pins.
local function Owner(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    local index = 1
    while true do
        local key, value = debug.getupvalue(fn, index)
        if not key then return nil end
        if key == name then return value end
        if type(value) == "function" then
            local found = Owner(value, name, seen)
            if found then return found end
        end
        index = index + 1
    end
end
assert(Owner(Text.UpdateHealth, "PercentFromValues") == percentOwner, "health runtime has a separate ratio owner")
assert(Owner(Text.UpdatePower, "PercentFromValues") == percentOwner, "power runtime has a separate ratio owner")
assert(Owner(Text.UpdateHealth, "MissingHealthFromValues") == missingOwner, "health runtime has a separate deficit owner")
local truncateOwner = Text.TruncateName
assert(Owner(Text.UpdateName, "TruncateName") == truncateOwner, "name runtime has a separate UTF-8 owner")
local percentCalls, missingCalls = 0, 0
Text.PercentFromValues = function(...)
    percentCalls = percentCalls + 1
    return percentOwner(...)
end
Text.MissingHealthFromValues = function(...)
    missingCalls = missingCalls + 1
    return missingOwner(...)
end
assert(GF.FormatHealthText("PERCENT", 750, 1000, "/", false, nil, false, true) == "75%")
assert(GF.FormatPowerText("PERCENT", 30, 120, "/", nil, false) == "25%")
assert(GF.FormatHealthText("DEFICIT", 750, 1000, "/", false, nil, false, true) == "-250")
assert(GF.FormatPowerText("DEFICIT", 30, 120, "/", nil, false) == "-90")
assert(percentCalls == 2 and missingCalls == 2, "GF fallbacks bypassed the shared engine math owners")
native.percent, native.missing = 60, 8
assert(GF.FormatHealthText("PERCENT", 750, 1000, "/", false, "party1", false, true) == "60%")
assert(GF.FormatPowerText("PERCENT", 30, 120, "/", "party1", false) == "60%")
assert(GF.FormatHealthText("DEFICIT", 750, 1000, "/", false, "party1", false, true) == "-8")
assert(percentCalls == 2 and missingCalls == 2, "native values lost their original priority")
local valueOwner, percentValueOwner = Text.FormatValue, Text.FormatPercentValue
local valueCalls, percentValueCalls = 0, 0
Text.FormatValue = function(...)
    valueCalls = valueCalls + 1
    return valueOwner(...)
end
Text.FormatPercentValue = function(...)
    percentValueCalls = percentValueCalls + 1
    return percentValueOwner(...)
end
local healthOwner, powerOwner = Text.FormatHealthString, Text.FormatPowerString
local healthCalls, powerCalls, nameCalls = 0, 0, 0
Text.FormatHealthString = function(...)
    healthCalls = healthCalls + 1
    return healthOwner(...)
end
Text.FormatPowerString = function(...)
    powerCalls = powerCalls + 1
    return powerOwner(...)
end
Text.TruncateName = function(...)
    nameCalls = nameCalls + 1
    return truncateOwner(...)
end
assert(GF.FormatHealthText("CURRENT", 750, 1000, nil, false, nil, false, true) == "750")
assert(GF.FormatPowerText("CURRENT", 30, 120) == "30")
assert(GF.TruncateName("abcdef", 3, false, "RIGHT") == "abc..")
assert(healthCalls == 1 and powerCalls == 1 and nameCalls == 1, "GF bypassed an actual format/name owner")
assert(valueCalls == 4, "group health/power bypassed the actual scalar value owner")
assert(GF.FormatHealthText("PERCENT", 750, 1000, nil, false, "party1", false, true) == "60%")
assert(valueCalls == 6 and percentValueCalls == 1, "group percent bypassed the actual scalar percent owner")
Text.FormatValue, Text.FormatPercentValue = valueOwner, percentValueOwner
Text.FormatHealthString, Text.FormatPowerString, Text.TruncateName = healthOwner, powerOwner, truncateOwner
Text.PercentFromValues, Text.MissingHealthFromValues = percentOwner, missingOwner
-- Baseline Runtime-owner ceilings include rejected input branches, not just native live writers.
local boundaryPairs = { {750, 1000}, {1001, 1000}, {-1, 100}, {1, -1}, {}, {"750", "1000"},
    {false, 100}, {math.huge, 100}, {750, math.huge}, {0 / 0, 100} }
local percentLimits = {38, 38, 38, 37, 20, 20, 20, 23, 36, 21}
local missingLimits = {38, 38, 38, 38, 20, 20, 20, 23, 36, 21}
local function OwnerCost(fn, a, b)
    local instructions = 0
    local source = debug.getinfo(fn, "S").source
    debug.sethook(function()
        if debug.getinfo(2, "S").source == source then instructions = instructions + 1 end
    end, "", 1)
    fn(a, b)
    debug.sethook()
    return instructions
end
for index, pair in ipairs(boundaryPairs) do
    assert(OwnerCost(percentOwner, pair[1], pair[2]) <= percentLimits[index], "live ratio owner instruction regression")
    assert(OwnerCost(missingOwner, pair[1], pair[2]) <= missingLimits[index], "live deficit owner instruction regression")
end
world.core.UFText = nil
local path = root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Text.lua"
local chunk = assert(loadfile(path))
setfenv(chunk, world.env)
local ok, problem = pcall(chunk, "MidnightSimpleUnitFrames", world.core)
world.core.UFText = Text
assert(not ok and tostring(problem):find("UFText", 1, true) and tostring(problem):find("GroupFrames/", 1, true),
    "missing namespace provider must raise a named load-time dependency error")
print("group_text_math_owner_smoke: ok (shared fallback owners, native priority, named readiness)")
