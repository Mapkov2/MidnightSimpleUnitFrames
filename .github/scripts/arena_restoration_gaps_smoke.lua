-- Focused Arena restoration coverage for profile payloads, UI scale, and rounded castbars.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Slice(source, startMarker, endMarker)
    local first = assert(source:find(startMarker, 1, true), "missing start marker: " .. startMarker)
    local last = assert(source:find(endMarker, first + #startMarker, true), "missing end marker: " .. endMarker)
    return source:sub(first, last - 1)
end

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
local profiles = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
local payloadKeys = Slice(
    profiles,
    "local MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS",
    "local MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS"
)
local makePayload = Slice(
    profiles,
    "local function MSUF_ProfileIO_MakeWagoPayload",
    "local function MSUF_ProfileIO_MakeWagoSnapshot"
)
local makeSnapshot = Slice(
    profiles,
    "local function MSUF_ProfileIO_MakeWagoSnapshot",
    "local function MSUF_ProfileIO_SelectWagoFullSnapshot"
)
local selectSnapshot = Slice(
    profiles,
    "local function MSUF_ProfileIO_SelectWagoFullSnapshot",
    "local function MSUF_CopyGroupFramePayload"
)
local profileHarness = [[
local MSUF_PROFILEIO_WAGO_SCHEMA = 1
local MSUF_PROFILEIO_WAGO_FULL_KEY = "msuf6"
local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = 600
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
]] .. payloadKeys .. makePayload .. makeSnapshot .. selectSnapshot .. [[
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

local scaleRuntime = Read("MidnightSimpleUnitFrames/Runtime/MSUF_UIScaleRuntime.lua")
local scaleGlobals = Slice(
    scaleRuntime,
    "local MSUF_SCALE_FRAME_GLOBALS",
    "local function IsGroupFrameUnitKey"
)
local scaleCollector = Slice(
    scaleRuntime,
    "local function CollectMsufScaleFrames",
    "local function GetSavedMsufScale"
)
local scaleHarness = [[
local function ForEachCoreFrame() return true end
local function IsGroupFrameScaleEnabled() return true end
]] .. scaleGlobals .. scaleCollector .. [[
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

local roundedCastbars = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRounded.lua")
local roundedWalker = Slice(
    roundedCastbars,
    "local function ForEachCastbar",
    "local function ApplyAll"
)
local roundedApplyAll = Slice(
    roundedCastbars,
    "local function ApplyAll",
    "MSUF.RoundedCastbarsApplyAll = ApplyAll"
)
local roundedHarness = [[
local roundedRuntimeActive = false
local applied, cleared = {}, {}
local function SettingEnabled() return true end
local function ApplyFrame(frame) applied[#applied + 1] = frame end
local function ClearFrame(frame) cleared[#cleared + 1] = frame end
]] .. roundedWalker .. roundedApplyAll .. [[
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

local roundedController = Read("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
local controllerApplyAll = Slice(
    roundedController,
    "local function ApplyAll()",
    "local function ApplyVisualRefreshUnit"
)
assert(controllerApplyAll:find("MSUF.RoundedCastbarsApplyAll", 1, true)
    and controllerApplyAll:find("applyRoundedCastbars(enabled)", 1, true),
    "rounded master ApplyAll no longer delegates its module state to castbars")
local modulesApplied = Slice(
    roundedController,
    'ExportPublic("MSUF_RoundedUF_OnModulesApplied"',
    "if SUPPRESS_NATIVE_OUTLINE then"
)
assert(modulesApplied:find("ApplyAll()", 1, true),
    "rounded module toggle no longer enters the master ApplyAll path")

io.write("arena restoration gaps smoke: ok\n")
