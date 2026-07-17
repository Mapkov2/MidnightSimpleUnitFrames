-- Focused integration smoke for !UUF_ routing in Foundation/MSUF_Profiles.lua.
--
-- The native UUF converter has its own schema/wire-format smoke. This harness
-- stubs only that converter boundary and loads the real profile module so it can
-- verify dispatch order, transactional failure behavior, and stable DB refs.
--
-- Run from the repository root:
--   lua tools/uuf_profile_integration_smoke.lua

local scriptPath = (arg and arg[0] or ""):gsub("\\", "/")
local scriptDir = scriptPath:match("^(.*[/])") or ""
local repoRoot = scriptDir:gsub("tools/$", "")
if repoRoot == "" then repoRoot = "." end

local profileSource = repoRoot .. "/MidnightSimpleUnitFrames/Foundation/MSUF_Profiles.lua"

local passed, failed = 0, 0
local failures = {}

local function Check(name, condition, detail)
    if condition then
        passed = passed + 1
        return
    end

    failed = failed + 1
    failures[#failures + 1] = name .. (detail and (": " .. tostring(detail)) or "")
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function DeepEqual(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end

    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right

    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local counts = {}
local events = {}
local printed = {}
local uufLoaded = false
local importerMode = "success"
local capturedBase
local capturedInput
local requestedAddon

local convertedTemplate = {
    converterMarker = "native-uuf-converter",
    nested = { translated = true, value = 57 },
}

local function Bump(name)
    counts[name] = (counts[name] or 0) + 1
end

local function Event(name)
    events[#events + 1] = name
end

local function ResetInstrumentation()
    counts = {}
    events = {}
    printed = {}
    capturedBase = nil
    capturedInput = nil
    requestedAddon = nil
end

local mutationGlobals = {
    MSUF_EnsureDB = "ensureDB",
    MSUF_NormalizePortraitRenderDB = "normalize",
    MSUF_MigrateDispelPriorityProfile = "migrate",
    MSUF_ApplyAllSettings = "applyAll",
    MSUF_ApplyAllSettings_Immediate = "applyImmediate",
    MSUF_UFCore_NotifyConfigChanged = "notify",
    MSUF_ApplyModules = "applyModules",
    MSUF_ClassPower_Refresh = "classPower",
    MSUF_ClassPower_RefreshTextures = "textures",
    MSUF_ClassPower_RefreshCDMWidthBindings = "widthBindings",
    MSUF_ApplyPowerBarEmbedLayout_All = "embedLayout",
    MSUF_Portraits_ForceRefresh = "portrait",
    MSUF_PortraitDecoration_RefreshAll = "portraitDecoration",
    MSUF_GF_EnsureDB = "gfEnsure",
    MSUF_GF_InvalidateConfCache = "gfInvalidate",
    MSUF_GF_RebuildAll = "gfRebuild",
    MSUF_Auras2_RefreshAll = "auraRefresh",
    MSUF_Auras2_ApplyFontsFromGlobal = "auraFonts",
    MSUF_UpdateTargetAuras = "targetAuras",
    MSUF_RefreshAllUnitAlphas = "alphaRefresh",
}

local function MutationCallCount()
    local total = 0
    for _, counterName in pairs(mutationGlobals) do
        total = total + (counts[counterName] or 0)
    end
    return total
end

local ns = {}
_G.MSUF_NS = ns
_G.CopyTable = DeepCopy
_G.InCombatLockdown = function() return false end
_G.GetRealmName = function() return "SmokeRealm" end
_G.UnitName = function() return "SmokeCharacter" end
_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
    }
end

_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

_G.MSUF_TryDecodeCompactString = function()
    Bump("compactDecode")
    Event("compact")
    return nil
end

local nativeLoadstring = _G.loadstring
_G.loadstring = function(...)
    Bump("legacyDecode")
    Event("legacy")
    if nativeLoadstring then return nativeLoadstring(...) end
    return nil, "loadstring unavailable in smoke runtime"
end

for globalName, counterName in pairs(mutationGlobals) do
    _G[globalName] = function()
        Bump(counterName)
        Event(counterName)
    end
end

local importer = {}

function importer.ConvertString(value, baseProfile)
    Bump("convert")
    Event("convert")
    capturedInput = value
    capturedBase = baseProfile

    if importerMode == "return-failure" then
        return nil, "deliberate conversion failure"
    end
    if importerMode == "throw" then
        error("deliberate converter exception")
    end

    return DeepCopy(convertedTemplate), { translated = 2, skipped = 0 }
end

function importer.PrintReport()
    Bump("report")
    Event("report")
end

_G.C_AddOns = {
    IsAddOnLoaded = function(addon)
        Bump("loadedCheck")
        Check("loaded status queries UnhaltedUnitFrames", addon == "UnhaltedUnitFrames", addon)
        return uufLoaded
    end,
    LoadAddOn = function(addon)
        Bump("loadAddon")
        Event("loadAddon")
        requestedAddon = addon
        ns.MSUF_UUFImport = importer
        return true
    end,
}

local profileChunk, loadError = loadfile(profileSource)
assert(profileChunk, loadError)
profileChunk("MidnightSimpleUnitFrames", ns)

local ImportActive = assert(_G.MSUF_Profiles_ImportFromString)
local ImportLegacy = assert(_G.MSUF_Profiles_ImportLegacyFromString)
local ImportExternal = assert(_G.MSUF_Profiles_ImportExternal)

local function FreshProfiles()
    local active = {
        marker = "active-original",
        player = { width = 317, height = 81 },
        general = { font = "ActiveFont" },
    }
    local other = {
        marker = "other-original",
        target = { width = 249, height = 63 },
        general = { font = "OtherFont" },
    }

    _G.MSUF_ActiveProfile = "Active"
    _G.MSUF_DB = active
    _G.MSUF_GlobalDB = {
        profiles = { Active = active, Other = other },
        char = { sentinel = "unchanged" },
    }
    return active, other
end

-- Loaded UUF must block every route that can replace the active profile before
-- the converter, a generic decoder, or any DB/runtime mutator is reached.
local blockedEntrypoints = {
    {
        name = "active standard import",
        call = function() return ImportActive("!UUF_blocked_standard") end,
    },
    {
        name = "active legacy import",
        call = function() return ImportLegacy("!UUF_blocked_legacy") end,
    },
    {
        name = "external active-profile import",
        call = function() return ImportExternal("!UUF_blocked_external", "Active") end,
        expectsError = true,
    },
}

for _, scenario in ipairs(blockedEntrypoints) do
    local active = FreshProfiles()
    local globalSnapshot = DeepCopy(_G.MSUF_GlobalDB)
    ResetInstrumentation()
    ns.MSUF_UUFImport = nil
    uufLoaded = true
    importerMode = "success"

    local result, why = scenario.call()

    Check(scenario.name .. " returns false", result == false, result)
    if scenario.expectsError then
        Check(
            scenario.name .. " returns block reason",
            type(why) == "string" and why:find("UUF import blocked", 1, true) ~= nil,
            why
        )
    end
    Check(scenario.name .. " preserves complete DB state", DeepEqual(_G.MSUF_GlobalDB, globalSnapshot))
    Check(
        scenario.name .. " preserves active table reference",
        _G.MSUF_DB == active and _G.MSUF_GlobalDB.profiles.Active == active
    )
    Check(scenario.name .. " never loads converter addon", (counts.loadAddon or 0) == 0)
    Check(scenario.name .. " never invokes converter", (counts.convert or 0) == 0)
    Check(scenario.name .. " never enters compact decoder", (counts.compactDecode or 0) == 0)
    Check(scenario.name .. " never enters legacy decoder", (counts.legacyDecode or 0) == 0)
    Check(
        scenario.name .. " performs zero DB/runtime mutation calls",
        MutationCallCount() == 0,
        MutationCallCount()
    )
end

-- With UUF inactive, an external import must load the dedicated companion and
-- apply only the table returned by its native converter.
do
    local active, other = FreshProfiles()
    local activeSnapshot = DeepCopy(active)
    ResetInstrumentation()
    ns.MSUF_UUFImport = nil
    uufLoaded = false
    importerMode = "success"

    local result, why = ImportExternal("!UUF_external_native_success", "Other")

    Check("inactive external import succeeds", result == true, why)
    Check("inactive external import loads LoD converter exactly once", (counts.loadAddon or 0) == 1, counts.loadAddon)
    Check(
        "inactive external import loads the dedicated converter addon",
        requestedAddon == "MidnightSimpleUnitFrames_UUFImporter",
        requestedAddon
    )
    Check("inactive external import calls native converter exactly once", (counts.convert or 0) == 1, counts.convert)
    Check("inactive external import passes original UUF string", capturedInput == "!UUF_external_native_success", capturedInput)
    Check("inactive external import passes target profile as converter base", capturedBase == other)
    Check("inactive external import bypasses compact decoder", (counts.compactDecode or 0) == 0)
    Check("inactive external import bypasses legacy decoder", (counts.legacyDecode or 0) == 0)
    Check("inactive external import preserves target profile reference", _G.MSUF_GlobalDB.profiles.Other == other)
    Check(
        "inactive external import stores converter output",
        other.converterMarker == "native-uuf-converter"
            and other.nested and other.nested.translated == true
            and other.marker == nil
    )
    Check(
        "inactive external import leaves active profile untouched",
        _G.MSUF_DB == active and DeepEqual(active, activeSnapshot)
    )
    Check(
        "converter completes before profile normalization",
        events[1] == "loadAddon" and events[2] == "convert"
            and events[3] == "normalize" and events[4] == "migrate",
        table.concat(events, ",")
    )
    Check("successful external import emits converter report", (counts.report or 0) == 1, counts.report)
end

local function RunFailureScenario(label, targetKey, mode)
    local active, other = FreshProfiles()
    local activeSnapshot = DeepCopy(active)
    local otherSnapshot = DeepCopy(other)
    local globalSnapshot = DeepCopy(_G.MSUF_GlobalDB)
    ResetInstrumentation()
    ns.MSUF_UUFImport = nil
    uufLoaded = false
    importerMode = mode

    local result, why = ImportExternal("!UUF_external_failure", targetKey)

    Check(label .. " returns false", result == false, result)
    Check(
        label .. " returns UUF error",
        type(why) == "string" and why:find("UUF import failed", 1, true) ~= nil,
        why
    )
    Check(label .. " invokes converter exactly once", (counts.convert or 0) == 1, counts.convert)
    Check(label .. " preserves complete global DB", DeepEqual(_G.MSUF_GlobalDB, globalSnapshot))
    Check(
        label .. " preserves active reference and content",
        _G.MSUF_DB == active
            and _G.MSUF_GlobalDB.profiles.Active == active
            and DeepEqual(active, activeSnapshot)
    )
    Check(
        label .. " preserves other reference and content",
        _G.MSUF_GlobalDB.profiles.Other == other and DeepEqual(other, otherSnapshot)
    )
    Check(label .. " performs zero DB/runtime mutation calls", MutationCallCount() == 0, MutationCallCount())
    Check(label .. " does not print success report", (counts.report or 0) == 0, counts.report)
    Check(
        label .. " never enters generic decoders",
        (counts.compactDecode or 0) == 0 and (counts.legacyDecode or 0) == 0
    )
end

-- Both a normal converter rejection and a thrown converter exception must be
-- fully transactional, for non-active and active destinations respectively.
RunFailureScenario("returned failure on non-active profile", "Other", "return-failure")
RunFailureScenario("thrown failure on active profile", "Active", "throw")

io.write(string.format(
    "uuf_profile_integration_smoke: %d/%d checks passed\n",
    passed,
    passed + failed
))

if failed > 0 then
    for _, message in ipairs(failures) do
        io.write("FAIL: " .. message .. "\n")
    end
    os.exit(1)
end
