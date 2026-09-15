-- arena_postbase_integration_smoke.lua
-- Focused contracts for Arena integration in shared systems added after the
-- original Arena feature branch. Run from the repository root with Lua 5.1.

local function Read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local function Slice(source, startMarker, endMarker)
    local first = assert(source:find(startMarker, 1, true), "missing start marker: " .. startMarker)
    local last = assert(source:find(endMarker, first + #startMarker, true), "missing end marker: " .. endMarker)
    return source:sub(first, last - 1)
end

local function Compile(source, name)
    local loader = loadstring or load
    return assert(loader(source, name))
end

local function AssertList(actual, expected, label)
    assert(#actual == #expected, label .. " count mismatch")
    for index = 1, #expected do
        assert(actual[index] == expected[index], label .. " mismatch at " .. index)
    end
end

-- Castbar driver ------------------------------------------------------------
local driver = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarDriver.lua")
local configHelpers = Slice(driver,
    "local function CastbarConfigUnitKey",
    "local function SetCastTargetText")
local configUnitKey, castTargetTextEnabled = Compile(configHelpers .. [[
return CastbarConfigUnitKey, CastTargetTextEnabled
]], "Arena castbar config harness")()

assert(configUnitKey("arena1") == "arena" and configUnitKey("arena3") == "arena",
    "Arena castbars do not collapse to the Arena settings root")
assert(configUnitKey("boss2") == "boss" and configUnitKey("focus") == "focus",
    "shared castbar settings normalization regressed another unit")

_G.MSUF_DB = {
    general = { showArenaCastTargetName = true },
    arena = { showInterrupt = false, showInterruptSource = true },
    boss = { showInterrupt = true, showInterruptSource = true },
}
assert(castTargetTextEnabled({ unit = "arena2", castTargetText = {} }) == true,
    "Arena cast-target text setting is not consumed by the live driver")
_G.MSUF_DB.general.showArenaCastTargetName = false
assert(castTargetTextEnabled({ unit = "arena2", castTargetText = {} }) == false,
    "Arena cast-target text cannot be disabled")

local interruptLabelSource = Slice(driver,
    "function _G.MSUF_Castbar_ResolveInterruptLabel",
    "local function HandleDriverEvent")
_G.UnitNameFromGUID = function(guid) return guid == "arena-guid" and "Arena Kicker" or "Boss Kicker" end
_G.UnitClassFromGUID = nil
_G.SPELL_INTERRUPTED_BY = "Interrupted by %s"
Compile(configHelpers .. interruptLabelSource, "Arena interrupt-label harness")()
assert(_G.MSUF_Castbar_ResolveInterruptLabel("arena-guid", "arena2") == "Interrupted by Arena Kicker",
    "Arena interrupter-source label does not read the Arena settings root")
_G.MSUF_DB.arena.showInterruptSource = false
assert(_G.MSUF_Castbar_ResolveInterruptLabel("arena-guid", "arena2") == "Interrupted",
    "Arena interrupter-source label ignores its disabled setting")
_G.MSUF_DB.arena.showInterruptSource = true

local setInterruptedSource = Slice(driver,
    "function frame:SetInterrupted",
    "function frame:SetSucceeded")
local interruptedFrame = Compile([[
local frame = { unit = "arena3" }
local function CastbarConfigUnitKey(unit)
    if type(unit) ~= "string" then return unit end
    if unit:match("^boss%d+$") then return "boss" end
    if unit:match("^arena%d+$") then return "arena" end
    return unit
end
local function HideChannelHasteMarkers() end
local function ClearFrameOnUpdate() end
local castbarRuntime = {}
local ApplyInterruptValues
local GetTime = function() return 0 end
local C_Timer = { After = function() end }
local function EnsureDriverCallbacks() end
_G.MSUF_CB_ResetStateOnStop = function() end
function frame:Hide() self.hidden = true end
]] .. setInterruptedSource .. [[
return frame
]], "Arena SetInterrupted harness")()
interruptedFrame:SetInterrupted("arena-guid")
assert(interruptedFrame.hidden == true and interruptedFrame.interrupted == nil,
    "arena.showInterrupt=false does not suppress Arena interrupt feedback")

local refreshAllSource = Slice(driver,
    "local function RefreshAllCastTargetTextColors",
    'ExportPublic("MSUF_RefreshAllCastTargetTextColors"')
local refreshAllHarness = [[
local liveVisited, previewVisited = {}, {}
local function RefreshCastTargetText(frame) liveVisited[#liveVisited + 1] = frame end
local function ApplyCastTargetTextColor(frame) previewVisited[#previewVisited + 1] = frame end
]] .. refreshAllSource .. [[
return RefreshAllCastTargetTextColors, liveVisited, previewVisited
]]
local refreshAll, liveVisited, previewVisited =
    Compile(refreshAllHarness, "Arena cast-target color refresh harness")()
-- 3-slot pass: MSUF_MAX_ARENA_FRAMES unset (Mainline fallback 3); slots 4..5
-- are decoys that must stay untouched.
_G.MSUF_MAX_ARENA_FRAMES = nil
local arenaLive, arenaPreview = {}, {}
for index = 1, 3 do
    arenaLive[index] = { castTargetText = {} }
    arenaPreview[index] = { castTargetText = {} }
    _G["MSUF_ArenaCastbar" .. index] = arenaLive[index]
    _G["MSUF_ArenaCastbarPreview" .. index] = arenaPreview[index]
end
for index = 4, 5 do
    _G["MSUF_ArenaCastbar" .. index] = { castTargetText = {} }
    _G["MSUF_ArenaCastbarPreview" .. index] = { castTargetText = {} }
end
_G.MSUF_ArenaCastbars = { arenaLive[1], arenaLive[2], arenaLive[3] }
_G.MSUF_ArenaCastbarPreview = arenaPreview[1]
refreshAll()
AssertList(liveVisited, arenaLive, "Arena live cast-target color refresh")
AssertList(previewVisited, arenaPreview, "Arena preview cast-target color refresh")

-- 5-slot pass: TBC and Mists publish MSUF_MAX_ARENA_FRAMES = 5. The live table
-- has gaps (named globals fill slots 2 and 5); slot 6 is a decoy.
local arenaLive5, arenaPreview5, expectedLive5, expectedPreview5 = {}, {}, {}, {}
for index = 1, 6 do
    arenaLive5[index] = { castTargetText = {} }
    arenaPreview5[index] = { castTargetText = {} }
    _G["MSUF_ArenaCastbar" .. index] = arenaLive5[index]
    _G["MSUF_ArenaCastbarPreview" .. index] = arenaPreview5[index]
    if index <= 5 then
        expectedLive5[index] = arenaLive5[index]
        expectedPreview5[index] = arenaPreview5[index]
    end
end
_G.MSUF_ArenaCastbars = { arenaLive5[1], nil, arenaLive5[3], arenaLive5[4], nil, arenaLive5[6] }
_G.MSUF_ArenaCastbarPreview = arenaPreview5[1]
_G.MSUF_MAX_ARENA_FRAMES = 5
local refreshAll5, liveVisited5, previewVisited5 =
    Compile(refreshAllHarness, "Arena cast-target color refresh 5-slot harness")()
refreshAll5()
AssertList(liveVisited5, expectedLive5, "5-slot Arena live cast-target color refresh")
AssertList(previewVisited5, expectedPreview5, "5-slot Arena preview cast-target color refresh")
_G.MSUF_MAX_ARENA_FRAMES = nil
for index = 4, 6 do
    _G["MSUF_ArenaCastbar" .. index] = nil
    _G["MSUF_ArenaCastbarPreview" .. index] = nil
end
for index = 1, 3 do
    _G["MSUF_ArenaCastbar" .. index] = arenaLive[index]
    _G["MSUF_ArenaCastbarPreview" .. index] = arenaPreview[index]
end
_G.MSUF_ArenaCastbars = { arenaLive[1], arenaLive[2], arenaLive[3] }
_G.MSUF_ArenaCastbarPreview = arenaPreview[1]

-- Global Bars Dispel sensor -------------------------------------------------
local globalBars = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua")
local dispelUnits = assert(globalBars:match("local UNITFRAME_DISPEL_AURA_UNITS = %{[^\n]+%}"),
    "missing UnitFrame Dispel sensor unit declaration")
-- The scope resolver reads the client-supported subset through a cached
-- helper, so the harness has to carry that helper too.
local supportedUnits = Slice(globalBars,
    "local supportedUnitFrameAuraUnits",
    "local function UnitFrameAuraScopeUnits")
local scopeUnits = Slice(globalBars,
    "local function UnitFrameAuraScopeUnits",
    "local function UnitFrameAuraSensorMissingForScope")
local ensureSensors = Slice(globalBars,
    "local function EnsureUnitFrameAuraSensorsForScope",
    "-- Scope rules are shared by all page sections")
local exerciseSensors = Compile([[
local scope, enabled, writes = "arena", {}, {}
local M = { ShowStatusFeedback = function() end }
local MSUF = { MSUF_Auras3 = { MenuModel = {
    UnitEnabled = function(unit) return enabled[unit] == true end,
    SetUnitEnabled = function(unit, value) enabled[unit] = value; writes[#writes + 1] = unit end,
} } }
local function CurrentBarsScope() return scope end
]] .. dispelUnits .. "\n" .. supportedUnits .. scopeUnits .. ensureSensors .. [[
return function(nextScope)
    scope, enabled, writes = nextScope, {}, {}
    EnsureUnitFrameAuraSensorsForScope()
    return writes
end
]], "Arena Dispel sensor harness")()
AssertList(exerciseSensors("arena"), { "arena" }, "Arena-scoped Dispel sensor enable")
AssertList(exerciseSensors("shared"), { "player", "target", "focus", "boss", "arena" },
    "shared Dispel sensor enable")

-- Aura Edit Mode popup ------------------------------------------------------
local auraPopup = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_AuraPopup.lua")
local auraScopeHelpers = Slice(auraPopup,
    "local function IsBoss",
    "local function UnitLabel")
local affectedUnitsSource = Slice(auraPopup,
    "local function AffectedUnits",
    "--- Aura layout offsets remain anchor-local runtime values")
local reapplySource = Slice(auraPopup,
    "local function ReapplyAuras",
    "local function ReadBox")
local affectedUnits, reapplyAuras, refreshRequests, previewRequests = Compile([[
local refreshRequests, previewRequests = {}, {}
local MSUF = { MSUF_Auras3 = {
    RequestScope = function(unit) refreshRequests[#refreshRequests + 1] = unit end,
    RefreshEditPreview = function(unit) previewRequests[#previewRequests + 1] = unit end,
} }
local function SyncMovers() end
]] .. auraScopeHelpers .. affectedUnitsSource .. reapplySource .. [[
return AffectedUnits, ReapplyAuras, refreshRequests, previewRequests
]], "Arena aura popup fan-out harness")()
AssertList(affectedUnits("arena2", { arenaEditTogether = true }),
    { "arena1", "arena2", "arena3" }, "Arena aura edit-together fan-out")
AssertList(affectedUnits("arena2", { arenaEditTogether = false }),
    { "arena2" }, "Arena individual aura edit")
reapplyAuras({ "arena1", "arena2", "arena3" })
AssertList(refreshRequests, { "arena1", "arena2", "arena3" }, "Arena aura runtime refresh")
AssertList(previewRequests, { "arena" }, "Arena aura preview refresh collapse")
assert(auraPopup:find('local scope = AuraScope(unit)', 1, true),
    "Arena custom aura containers do not resolve through their canonical scope")
local ARENA_TOGETHER_LABEL_LINE = 'local arenaTogetherLabel = (tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) > 3'
    .. ' and "Edit Arena 1-5 together" or "Edit Arena 1-3 together"'
assert(auraPopup:find(ARENA_TOGETHER_LABEL_LINE, 1, true),
    "Arena aura edit-together label does not follow the client arena slot count")
assert(auraPopup:find("pf.arenaTogetherBtn = Quick.ToggleAt(pf, arenaTogetherLabel,", 1, true),
    "Arena aura edit-together setting is not visible in the popup")
for _, label in ipairs({ "Edit Arena 1-3 together", "Edit Arena 1-5 together" }) do
    assert(auraPopup:find('"' .. label .. '"', 1, true), "Arena aura popup lost its label: " .. label)
end
local arenaTogetherLabel = Compile(ARENA_TOGETHER_LABEL_LINE .. "\nreturn arenaTogetherLabel",
    "Arena edit-together label harness")
for _, case in ipairs({ { nil, "Edit Arena 1-3 together" }, { 3, "Edit Arena 1-3 together" },
    { 5, "Edit Arena 1-5 together" } }) do
    _G.MSUF_MAX_ARENA_FRAMES = case[1]
    assert(arenaTogetherLabel() == case[2],
        "Arena edit-together label for MSUF_MAX_ARENA_FRAMES=" .. tostring(case[1]) .. " is not " .. case[2])
end
-- 5-slot pass: TBC and Mists fan the aura edit-together write out to arena1-5.
_G.MSUF_MAX_ARENA_FRAMES = 5
AssertList(affectedUnits("arena2", { arenaEditTogether = true }),
    { "arena1", "arena2", "arena3", "arena4", "arena5" }, "5-slot Arena aura edit-together fan-out")
AssertList(affectedUnits("arena4", { arenaEditTogether = false }),
    { "arena4" }, "5-slot Arena individual aura edit")
AssertList(affectedUnits("boss2", { bossEditTogether = true }),
    { "boss1", "boss2", "boss3", "boss4", "boss5" }, "5-slot Arena pass changed the Boss fan-out")
_G.MSUF_MAX_ARENA_FRAMES = 3
AssertList(affectedUnits("arena2", { arenaEditTogether = true }),
    { "arena1", "arena2", "arena3" }, "Mainline Arena aura edit-together fan-out")
_G.MSUF_MAX_ARENA_FRAMES = nil

-- Generic Unit Preview Arena parity ----------------------------------------
local unitPreviewAuras = Read(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
local previewUnitKeySource = Slice(unitPreviewAuras,
    "function Auras.PreviewUnitKey",
    "local function PreviewUnit")
local runtimeUnitSource = Slice(unitPreviewAuras,
    "local function RuntimeUnit",
    "local function LiveApplyReason")
local previewUnitKey, runtimeUnit = Compile([[
local Auras = {}
local function CanonKey(unit) return unit end
]] .. previewUnitKeySource .. runtimeUnitSource .. [[
return Auras.PreviewUnitKey, RuntimeUnit
]], "Arena generic aura-preview key harness")()
assert(previewUnitKey("arena") == "arena", "generic aura preview rejects the Arena scope")
assert(runtimeUnit("arena") == "arena1", "generic aura preview popup does not resolve arena1")

local refreshRuntimeSource = Slice(unitPreviewAuras,
    "local function LiveApplyReason",
    "local function RequestPreviewRefresh")
local refreshRuntime, auraPreviewRefreshes = Compile([[
local Auras = { PreviewUnitKey = function(unit) return unit end }
local refreshes = {}
local MSUF = { MSUF_Auras3 = {
    RefreshUnit = function(unit) refreshes[#refreshes + 1] = unit end,
} }
local function ApplyService() return nil end
local function MenuModel() return nil end
]] .. refreshRuntimeSource .. [[
return RefreshRuntime, refreshes
]], "Arena generic aura-preview refresh harness")()
assert(refreshRuntime("arena", "ARENA_PREVIEW_SMOKE") == true,
    "generic aura preview rejected an Arena runtime refresh")
AssertList(auraPreviewRefreshes, { "arena1", "arena2", "arena3" },
    "generic aura-preview Arena runtime fan-out")
-- 5-slot pass: TBC and Mists refresh arena1-5 from the generic aura preview.
for index = #auraPreviewRefreshes, 1, -1 do auraPreviewRefreshes[index] = nil end
_G.MSUF_MAX_ARENA_FRAMES = 5
assert(refreshRuntime("arena", "ARENA_PREVIEW_SMOKE") == true,
    "generic aura preview rejected a 5-slot Arena runtime refresh")
AssertList(auraPreviewRefreshes, { "arena1", "arena2", "arena3", "arena4", "arena5" },
    "5-slot generic aura-preview Arena runtime fan-out")
_G.MSUF_MAX_ARENA_FRAMES = nil

for _, marker in ipairs({
    'unit == "player" or unit == "target" or unit == "focus" or unit == "boss" or unit == "arena"',
    'unit == "target" or unit == "focus" or unit == "boss" or unit == "arena"',
    'unit ~= "target" and unit ~= "focus" and unit ~= "boss" and unit ~= "arena"',
}) do
    assert(unitPreviewAuras:find(marker, 1, true),
        "generic aura preview lost Arena custom4/target-dot parity: " .. marker)
end
assert(unitPreviewAuras:find('if unit ~= "player" then return nil end', 1, true),
    "Defensive Portrait preview must remain player-only")

local unitPreviewRender = Read(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
assert(unitPreviewRender:find('(key == "arena" and g.showArenaCastTargetName == true)', 1, true),
    "Arena Unit Preview ignores the cast-target-name visibility setting")
assert(unitPreviewRender:find('(key == "arena" and g.showArenaCastTime ~= false)', 1, true),
    "Arena Unit Preview ignores the cast-time visibility setting")

local unitPreviewView = Read(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View_Handles.lua")
local castbarSubOffsetSource = Slice(unitPreviewView,
    "local function CastbarSubOffsetKey",
    "local function MenuHistoryLabel")
local readSubOffsets, writeSubOffsets, subOffsetDB = Compile([[
local g = { arenaCastTimeOffsetX = 4, arenaCastTimeOffsetY = 5 }
local function CanonKey(unit) return unit end
local PreviewCastbar = {}
local function UnitDB() return nil, g, "arena" end
local function RoundOffset(value) return math.floor((tonumber(value) or 0) + 0.5) end
local function RefreshCastbarRuntime() end
]] .. castbarSubOffsetSource .. [[
return ReadCastbarSubOffsets, WriteCastbarSubOffsets, g
]], "Arena Unit Preview castbar-handle harness")()
local timeHandle = { _preview = { key = "arena" }, _fields = {
    suffixX = "TimeOffsetX", suffixY = "TimeOffsetY",
    bossX = "bossCastTimeOffsetX", bossY = "bossCastTimeOffsetY",
    bossBaseX = -2, bossBaseY = 0,
} }
local handleX, handleY, xKey, yKey = readSubOffsets(timeHandle)
assert(handleX == 2 and handleY == 5
    and xKey == "arenaCastTimeOffsetX" and yKey == "arenaCastTimeOffsetY",
    "Arena cast-time handle does not apply its boss-style display base")
assert(writeSubOffsets(timeHandle, 3, 7, "ARENA_PREVIEW_SMOKE") == true,
    "Arena cast-time handle refused a write")
assert(subOffsetDB.arenaCastTimeOffsetX == 5 and subOffsetDB.arenaCastTimeOffsetY == 7,
    "Arena cast-time handle did not remove its display base before persistence")

-- Preview diagnostics -------------------------------------------------------
-- PreviewDiagnostics was removed from the runtime and its load manifests.
io.write("arena post-base integration smoke: ok\n")
