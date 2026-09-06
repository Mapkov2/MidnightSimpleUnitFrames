-- Group Spell Icons composition and unused-style work. Optional frozen baseline:
-- lua this.lua <repository-root> <baseline-source-root>.
local root = arg and arg[1] or "."
local baselineRoot = arg and arg[2]
local file = "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_GroupConfig.lua"
local checks = 0
local function Check(value, message) checks = checks + 1; assert(value, message) end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Upvalue(fn, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        assert(name, "missing private compiler seam " .. wanted)
        if name == wanted then return value end
        index = index + 1
    end
end
local function Load(sourceRoot)
    local ns, counts = {}, { db = 0, styles = 0, slots = 0 }
    assert(loadfile(sourceRoot .. file))("MidnightSimpleUnitFrames", ns)
    local state = { SpellIndicators = { CompileSlots = function(unit, source, style)
        counts.slots = counts.slots + 1
        if not (type(source) == "table" and source.enabled == true and type(source.items) == "table") then return nil end
        return { enabled = true, unit = unit, source = source, style = style }
    end } }
    local dependencies = {
        Clamp01 = function(value, fallback) return value or fallback end,
        ClampNumber = function(value, fallback) return value or fallback end,
        CompileDispelSensor = function() end,
        CompileGroupLane = function() end,
        EnsureDB = function() counts.db = counts.db + 1; return {}, {} end,
        IsGroupFrame = function() return true end,
        NormalizeDurationBarDirection = function(value, fallback) return value or fallback end,
        NormalizeDurationBarDisplay = function(value, fallback) return value or fallback end,
        NormalizeDurationBarPosition = function(value, fallback) return value or fallback end,
        Shape = { Resolve = function() return "RECTANGLE", "RECTANGLE" end, SharedValue = function() end },
        SharedIconStyle = function() counts.styles = counts.styles + 1; return { signature = "buff" } end,
    }
    for _, owner in ipairs({ "Platform", "DispelConfig", "LaneConfig", "ConfigValues", "Appearance" }) do
        dependencies[owner] = dependencies
    end
    local api = ns.Auras3RuntimeFactories.GroupConfig("MidnightSimpleUnitFrames", ns, state, {}, function() end, dependencies)
    return { api = api, counts = counts, build = Upvalue(api.ResolveGroupFrameConfig, "BuildGroupSpellIndicatorSource") }
end
local candidate = Load(root)
local baseline = baselineRoot and Load(baselineRoot)
local first, disabled, last, corner = { spellID = 123 }, { enabled = false }, { spellID = 456 }, { spellID = 789 }
local spellSource = { enabled = true, items = { first, disabled, last }, layer = 4, iconZoom = 125, strata = "HIGH" }
Check(candidate.build(spellSource) == spellSource, "spell-only owner lost original source or item indices")
Check(candidate.build(spellSource, { enabled = true, customSlots = { disabled } }) == spellSource,
    "disabled corners forced a merged list")
local merged = candidate.build(spellSource, { enabled = true, customSlots = { disabled, corner }, layer = 8 })
Check(merged ~= spellSource and #merged.items == 3 and merged.items[1] == first
    and merged.items[2] == last and merged.items[3] == corner, "merged order or item identity changed")
Check(merged.layer == 4 and merged.iconZoom == 125 and merged.strata == "HIGH", "merged appearance precedence changed")
Check(spellSource.items[2] == disabled and #spellSource.items == 3, "source items were modified")
Check(candidate.build(nil, { enabled = true, customSlots = { disabled, false } }) == nil,
    "empty owner stopped returning nil")

if baseline then
    local sources = {
        false, 7, "invalid", {}, { enabled = false, items = { first }, customSlots = { corner } },
        { enabled = true }, { enabled = true, items = false, customSlots = "invalid" },
        { enabled = true, items = {}, customSlots = {} },
        { enabled = true, items = { disabled, false, 7 }, customSlots = { false, disabled } },
        { enabled = true, items = { first }, customSlots = { corner } },
        { enabled = true, items = { false, first, disabled, last }, customSlots = { disabled, corner }, layer = 3 },
        { enabled = true, items = { {} }, customSlots = { {} }, layer = false, iconZoom = 0, strata = false },
        spellSource,
    }
    for a = 0, #sources do
        for b = 0, #sources do
            local spells, corners = sources[a], sources[b]
            local expected, actual = baseline.build(spells, corners), candidate.build(spells, corners)
            Check(Same(actual, expected), "combined source differs from frozen behavior")
            if expected == spells then Check(actual == spells, "source identity changed") end
            if actual and actual ~= spells then
                for i, item in ipairs(actual.items) do Check(item == expected.items[i], "merged item identity changed") end
            end
        end
    end

    -- Exercise the real GroupConfig setup, not only the list helper. The bounded
    -- slot stand-in keeps the native CompileSlots nil-source early-return contract.
    local cases = {
        { unit = "party1" }, { unit = "party1", spells = { enabled = false, items = { first } } },
        { unit = "party1", spells = spellSource },
        { unit = "party1", corners = { enabled = true, customSlots = { corner } } },
        { unit = "", spells = spellSource }, { unit = false, spells = spellSource },
    }
    for _, case in ipairs(cases) do
        local function Resolve(owner)
            return owner.api.ResolveGroupFrameConfig({ _msufGFKind = "party", MSUFUnitKey = case.unit,
                MSUFSpec = { spellIndicators = case.spells, cornerIndicators = case.corners } })
        end
        local expected, actual = Resolve(baseline), Resolve(candidate)
        Check(Same(actual.spellIndicators, expected.spellIndicators) and actual.enabled == expected.enabled,
            "skipping unused style changed the resulting group owner")
    end
    Check(baseline.counts.styles == 6 and candidate.counts.styles == 2, "unused styles were still compiled")
    Check(baseline.counts.slots == 4 and candidate.counts.slots == 2, "nil-source slots still invoked")
    print("GROUP INDICATOR WORK (6 setup cases): style compiles 6 -> 2; CompileSlots calls 4 -> 2")
    local items = {}
    for i = 1, 64 do items[i] = { spellID = i } end
    local source = { enabled = true, items = items }
    local function Sample(owner)
        collectgarbage("collect"); collectgarbage("stop")
        local start = collectgarbage("count")
        for _ = 1, 1000 do owner.build(source) end
        local allocated = collectgarbage("count") - start
        collectgarbage("restart"); collectgarbage("collect")
        return allocated
    end
    local oldKB, newKB = Sample(baseline), Sample(candidate)
    Check(newKB < oldKB, "spell-only composition still allocates its discarded list")
    print(string.format("GROUP INDICATOR ALLOCATION (1000 spell-only builds, 64 items): %.2f -> %.2f KiB", oldKB, newKB))
end
print("PASS Auras3 group indicator compile: " .. checks .. " semantic, ownership and bounded work checks")
