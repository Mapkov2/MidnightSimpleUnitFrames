-- Group aura descriptors belong to Auras3, keyed by immutable base specs.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local namespace = { Auras3RuntimeFactories = {} }
local A3 = { _runtimeConfigGen = 1, GetNativeVisualSignature = function() return "content-A" end,
    SpellIndicators = {} }
local count = 0
local function CompileLane(unit)
    count = count + 1
    return { unit = unit, enabled = true }
end
local function StubTable(values)
    return setmetatable(values or {}, { __index = function() return function() end end })
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_GroupConfig.lua"))("MSUF", namespace)
local GroupConfig = namespace.Auras3RuntimeFactories.GroupConfig("MSUF", namespace, A3, {}, function() end, {
    Platform = StubTable(), Appearance = StubTable(), DispelConfig = StubTable(),
    LaneConfig = { CompileGroupLane = CompileLane },
    ConfigValues = StubTable({ EnsureDB = function() return {}, {} end, IsGroupFrame = function() return true end }),
})
local source = {}
local base = { auras = source }
local function Frame(specBase, unit, preview)
    return { MSUFSpec = { auras = source }, _msufGFSpecBase = specBase, MSUFUnitKey = unit,
        _msufGFKind = "raid", _msufGFIsPreviewFrame = preview }
end
local first, second = Frame(base, "player", true), Frame(base, "player", true)
local config = GroupConfig.FrameAuraConfig(first)
assert(GroupConfig.FrameAuraConfig(second) == config, "base-spec overlays must share immutable aura descriptors")
assert(count == 4, "one descriptor compilation per base/unit/kind/gate")
assert(next(base) == "auras" and next(base, "auras") == nil, "Auras3 must not write into group base specs")
assert(next(first.MSUFSpec) == "auras" and next(first.MSUFSpec, "auras") == nil, "Auras3 must not write into overlays")
assert(GroupConfig.FrameAuraConfig(Frame(base, "raid1", false)) ~= config, "live unit/gate separation")
assert(GroupConfig.FrameAuraConfig(Frame({}, "player", true)) ~= config, "different base identity must not share")
A3.InvalidateGroupRuntimeConfig("raid")
local revised = GroupConfig.FrameAuraConfig(first)
assert(revised ~= config, "scope revision expires descriptors")
assert(GroupConfig.FrameAuraConfig(second) == revised, "scope revision remains shared")
local resolve
for index = 1, 30 do
    local name, value = debug.getupvalue(GroupConfig.FrameAuraConfig, index)
    if name == "ResolveGroupFrameConfig" then resolve = value end
end
local cache
for index = 1, 40 do
    local name, value = debug.getupvalue(assert(resolve), index)
    if name == "sharedConfigBySpec" then cache = value end
end
assert(cache and getmetatable(cache).__mode == "k", "base-spec cache must use weak keys")
local entries = 0
for _ in pairs(cache) do entries = entries + 1 end
first, second, base = nil, nil, nil
collectgarbage("collect")
assert(next(cache) == nil, "retired bases must not be retained by cache values")
assert(entries > 0, "weak cache was exercised")
print("auras3_group_cache_ownership_smoke: ok (sharing, isolation, revisions, weak lifetime)")
