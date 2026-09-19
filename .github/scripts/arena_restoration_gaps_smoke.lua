-- Focused Arena restoration coverage for profile payloads, UI scale, and rounded castbars.
-- Every slice below ends at its own structural boundary (a function's `end`, a
-- table's `}`), not at a marker naming whatever the shipped file happens to
-- declare next, and the schema constants are read from the file rather than
-- re-declared here, so this harness cannot keep asserting against values
-- production has moved on from.
local Slice = assert(loadfile(".github/scripts/msuf_source_slice.lua"),
    "arena_restoration_gaps_smoke must run with the repository root as the working directory")()
local Read = Slice.Read

local function AssertVisitedExactlyOnce(actual, expected, label)
    local counts = {}
    for index = 1, #actual do
        local frame = actual[index]
        counts[frame] = (counts[frame] or 0) + 1
    end
    assert(#actual == #expected, label .. " visited an unexpected number of frames")
    for index = 1, #expected do
        assert(counts[expected[index]] == 1, label .. " did not visit every Arena frame exactly once")
    end
end

local compile = loadstring or load
local PROFILES = "MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"
local profiles = Read(PROFILES)
-- Reason: the Wago export path is three functions plus the root allowlist that
-- decides which profile roots survive an export, so the harness compiles those
-- four declarations and the schema constants they stamp into the payload.
local payloadKeys = Slice.Table(profiles, "local MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS =", PROFILES)
local makePayload = Slice.Function(profiles, "local function MSUF_ProfileIO_MakeWagoPayload", PROFILES)
local makeSnapshot = Slice.Function(profiles, "local function MSUF_ProfileIO_MakeWagoSnapshot", PROFILES)
local selectSnapshot = Slice.Function(profiles, "local function MSUF_ProfileIO_SelectWagoFullSnapshot", PROFILES)
local constants = table.concat({
    Slice.Constant(profiles, "local MSUF_PROFILEIO_WAGO_SCHEMA =", PROFILES),
    Slice.Constant(profiles, "local MSUF_PROFILEIO_WAGO_FULL_KEY =", PROFILES),
    Slice.Constant(profiles, "local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA =", PROFILES),
}, "\n")
-- Deliberate doubles, not slices: MSUF_DeepCopy reads a runtime limits table
-- off the namespace, and the two Wago normalizers rewrite aura and group data
-- this harness does not build. The contracts below are about which roots reach
-- which payload, so a faithful copy and two no-ops are the right stand-ins.
local profileHarness = constants .. [[

local function MSUF_DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[MSUF_DeepCopy(key, seen)] = MSUF_DeepCopy(child, seen)
    end
    return copy
end
local function MSUF_ProfileIO_NormalizeAurasForWago() end
local function MSUF_ProfileIO_NormalizeGroupFrameForWago() end
]] .. payloadKeys .. "\n" .. makePayload .. "\n" .. makeSnapshot .. "\n" .. selectSnapshot .. [[

return MSUF_ProfileIO_MakeWagoPayload,
    MSUF_ProfileIO_MakeWagoSnapshot,
    MSUF_ProfileIO_SelectWagoFullSnapshot
]]
local makeWagoPayload, makeWagoSnapshot, selectWagoFullSnapshot =
    assert(compile(profileHarness, "Arena profile payload harness"))()

local sentinel = "arena-profile-roundtrip-sentinel"
local profilePayload = {
    arena = { enabled = true, nested = { sentinel = sentinel } },
    player = { enabled = true },
    unsupportedRoot = { sentinel = "must-not-leak" },
}
local compatibilityPayload = makeWagoPayload(profilePayload)
assert(compatibilityPayload.arena.nested.sentinel == sentinel,
    "Wago compatibility payload dropped the Arena profile root")
assert(compatibilityPayload.unsupportedRoot == nil,
    "Wago compatibility payload root allowlist stopped filtering unknown roots")

local wagoSnapshot, transformed = makeWagoSnapshot({
    addon = "MSUF",
    fmt = 2,
    kind = "all",
    profile = "Arena Smoke",
    payload = profilePayload,
})
assert(transformed == true, "full profile did not enter the Wago snapshot path")
assert(wagoSnapshot.payload.arena.nested.sentinel == sentinel,
    "Wago compatibility snapshot dropped the Arena sentinel")
assert(wagoSnapshot.msuf6.payload.arena.nested.sentinel == sentinel,
    "full external snapshot dropped the Arena sentinel")
assert(wagoSnapshot.payload.arena ~= wagoSnapshot.msuf6.payload.arena,
    "compatibility and full Arena payloads unexpectedly share a table")
wagoSnapshot.payload.arena.nested.sentinel = "compatibility-copy-mutated"
local selected = selectWagoFullSnapshot(wagoSnapshot)
assert(selected.payload.arena.nested.sentinel == sentinel,
    "full external profile roundtrip selected the lossy compatibility Arena payload")
local roundtripped = makeWagoSnapshot(selected)
assert(roundtripped.payload.arena.nested.sentinel == sentinel,
    "re-export after full external selection lost the Arena root")

local SCALE_RUNTIME = "MidnightSimpleUnitFrames/Runtime/MSUF_UIScaleRuntime.lua"
local scaleRuntime = Read(SCALE_RUNTIME)
-- Reason: the collector walks the frame-global name list, so the contract needs
-- that list and the walker; the two doubles stand in for the core-frame
-- enumerator and the group-frame gate, neither of which this harness builds.
local scaleGlobals = Slice.Table(scaleRuntime, "local MSUF_SCALE_FRAME_GLOBALS =", SCALE_RUNTIME)
local scaleCollector = Slice.Function(scaleRuntime, "local function CollectMsufScaleFrames", SCALE_RUNTIME)
local scaleHarness = [[
local function ForEachCoreFrame() return true end
local function IsGroupFrameScaleEnabled() return true end
]] .. scaleGlobals .. "\n" .. scaleCollector .. [[

return CollectMsufScaleFrames
]]
local collectScaleFrames = assert(compile(scaleHarness, "Arena UI scale collector harness"))()

local function NewFrame(label)
    return { label = label, SetScale = function() end }
end
local arenaLive = { NewFrame("arena-live-1"), NewFrame("arena-live-2"), NewFrame("arena-live-3") }
local arenaPreview = { NewFrame("arena-preview-1"), NewFrame("arena-preview-2"), NewFrame("arena-preview-3") }
-- 3-slot pass: MSUF_MAX_ARENA_FRAMES unset (Mainline fallback 3). Slots 4..5
-- hold decoy frames that a walker reading past the fallback would collect.
_G.MSUF_MAX_ARENA_FRAMES = nil
_G.MSUF_ArenaCastbars = { arenaLive[1], nil, arenaLive[3], NewFrame("arena-live-decoy-4") }
for index = 1, 3 do
    _G["MSUF_ArenaCastbar" .. index] = arenaLive[index]
    _G["MSUF_ArenaCastbarPreview" .. index] = arenaPreview[index]
end
for index = 4, 5 do
    _G["MSUF_ArenaCastbar" .. index] = NewFrame("arena-live-decoy-" .. index)
    _G["MSUF_ArenaCastbarPreview" .. index] = NewFrame("arena-preview-decoy-" .. index)
end
_G.MSUF_ArenaCastbarPreview = arenaPreview[1]

AssertVisitedExactlyOnce(
    collectScaleFrames(),
    { arenaLive[1], arenaLive[2], arenaLive[3], arenaPreview[1], arenaPreview[2], arenaPreview[3] },
    "UI scale collector"
)

local ROUNDED_CASTBARS = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRounded.lua"
local roundedCastbars = Read(ROUNDED_CASTBARS)
-- Reason: ApplyAll walks every castbar through ForEachCastbar, so the contract
-- is those two functions; the four doubles record which frames they reach.
local roundedWalker = Slice.Function(roundedCastbars, "local function ForEachCastbar", ROUNDED_CASTBARS)
local roundedApplyAll = Slice.Function(roundedCastbars, "local function ApplyAll", ROUNDED_CASTBARS)
local roundedHarness = [[
local roundedRuntimeActive = false
local applied, cleared = {}, {}
local function SettingEnabled() return true end
local function ApplyFrame(frame) applied[#applied + 1] = frame end
local function ClearFrame(frame) cleared[#cleared + 1] = frame end
]] .. roundedWalker .. "\n" .. roundedApplyAll .. [[

return ApplyAll, applied, cleared
]]
local applyAllRoundedCastbars, appliedRounded, clearedRounded =
    assert(compile(roundedHarness, "Arena rounded castbar harness"))()
local expectedArenaFrames = {
    arenaLive[1], arenaLive[2], arenaLive[3],
    arenaPreview[1], arenaPreview[2], arenaPreview[3],
}
applyAllRoundedCastbars(true)
AssertVisitedExactlyOnce(appliedRounded, expectedArenaFrames, "rounded castbar enable")
applyAllRoundedCastbars(false)
AssertVisitedExactlyOnce(clearedRounded, expectedArenaFrames, "rounded castbar disable")

-- 5-slot pass: TBC and Mists publish MSUF_MAX_ARENA_FRAMES = 5. Slot 6 is a
-- decoy. Live slot 4 exists only in the pool table and slots 2 and 5 only as
-- named globals, so both the pool-table loop and the named-global loop must
-- reach slot 5 on their own.
local arenaLive5, arenaPreview5 = {}, {}
for index = 1, 6 do
    arenaLive5[index] = NewFrame("arena5-live-" .. index)
    arenaPreview5[index] = NewFrame("arena5-preview-" .. index)
    _G["MSUF_ArenaCastbar" .. index] = index ~= 4 and arenaLive5[index] or nil
    _G["MSUF_ArenaCastbarPreview" .. index] = arenaPreview5[index]
end
_G.MSUF_ArenaCastbars = { arenaLive5[1], nil, arenaLive5[3], arenaLive5[4], nil, arenaLive5[6] }
_G.MSUF_ArenaCastbarPreview = arenaPreview5[1]
_G.MSUF_MAX_ARENA_FRAMES = 5
local expectedArenaFrames5 = {}
for index = 1, 5 do expectedArenaFrames5[#expectedArenaFrames5 + 1] = arenaLive5[index] end
for index = 1, 5 do expectedArenaFrames5[#expectedArenaFrames5 + 1] = arenaPreview5[index] end

AssertVisitedExactlyOnce(collectScaleFrames(), expectedArenaFrames5, "5-slot UI scale collector")

local applyAllRoundedCastbars5, appliedRounded5, clearedRounded5 =
    assert(compile(roundedHarness, "Arena rounded castbar 5-slot harness"))()
applyAllRoundedCastbars5(true)
AssertVisitedExactlyOnce(appliedRounded5, expectedArenaFrames5, "5-slot rounded castbar enable")
applyAllRoundedCastbars5(false)
AssertVisitedExactlyOnce(clearedRounded5, expectedArenaFrames5, "5-slot rounded castbar disable")

_G.MSUF_MAX_ARENA_FRAMES = nil
_G.MSUF_ArenaCastbars = nil
_G.MSUF_ArenaCastbarPreview = nil
for index = 1, 6 do
    _G["MSUF_ArenaCastbar" .. index] = nil
    _G["MSUF_ArenaCastbarPreview" .. index] = nil
end

local ROUNDED_CONTROLLER = "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"
local roundedController = Read(ROUNDED_CONTROLLER)
-- Reason: both assertions are about one function each -- the rounded master
-- ApplyAll and the exported module-toggle callback -- so each slice is that
-- function, ending at its own `end`.
local controllerApplyAll = Slice.Function(roundedController, "local function ApplyAll", ROUNDED_CONTROLLER)
assert(controllerApplyAll:find("MSUF.RoundedCastbarsApplyAll", 1, true)
    and controllerApplyAll:find("applyRoundedCastbars(enabled)", 1, true),
    "rounded master ApplyAll no longer delegates its module state to castbars")
local modulesApplied = Slice.Function(roundedController,
    'ExportPublic("MSUF_RoundedUF_OnModulesApplied", function', ROUNDED_CONTROLLER)
assert(modulesApplied:find("ApplyAll()", 1, true),
    "rounded module toggle no longer enters the master ApplyAll path")

io.write("arena restoration gaps smoke: ok\n")
