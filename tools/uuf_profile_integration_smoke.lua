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
local statusSource = repoRoot .. "/MidnightSimpleUnitFrames/Core/MSUF_StatusIndicators.lua"
local previewSource = repoRoot .. "/MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_UnitPreview.lua"
local castbarStubSource = repoRoot .. "/MidnightSimpleUnitFrames/Core/MSUF_Castbars_LoDStub.lua"
local menuBindingsSource = repoRoot .. "/MidnightSimpleUnitFrames/Menu2/MSUF_Menu2_Bindings.lua"

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
local inCombat = false

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
    MSUF_Castbars_InvalidateSettingsCache = "castbarCacheInvalidate",
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
    MSUF_RefreshStatusIndicators = "statusRefresh",
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
_G.InCombatLockdown = function() return inCombat end
_G.GetRealmName = function() return "SmokeRealm" end
_G.UnitName = function() return "SmokeCharacter" end
_G.CreateFrame = function()
    return {
        SetScript = function(self, event, callback) self[event] = callback end,
        RegisterEvent = function(self, event) self.registeredEvent = event end,
        UnregisterEvent = function(self, event)
            if self.registeredEvent == event then self.registeredEvent = nil end
        end,
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
local NormalizeAnchorAliases = assert(_G.MSUF_ProfileIO_NormalizeAnchorAliases)

do
    local profile = {
        general = { anchorName = "UI_Parent" },
        pet = { anchorFrameName = "UI_Parent", anchorToUnitframe = "GLOBAL" },
    }
    Check("UI_Parent alias normalization reports a repair", NormalizeAnchorAliases(profile) == true)
    Check("UI_Parent aliases normalize to UIParent",
        profile.general.anchorName == "UIParent" and profile.pet.anchorFrameName == "UIParent")
    Check("anchor alias normalization is idempotent", NormalizeAnchorAliases(profile) == false)
end

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

local function EventIndex(name)
    for index, eventName in ipairs(events) do
        if eventName == name then return index end
    end
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

-- A successful UUF replacement of the active profile must synchronously drop
-- and rebuild status-icon geometry after the normal profile runtime apply.
local activeSuccessEntrypoints = {
    {
        name = "active standard import",
        call = function() return ImportActive("!UUF_active_standard_success") end,
    },
    {
        name = "external active-profile import",
        call = function() return ImportExternal("!UUF_active_external_success", "Active") end,
    },
}

for _, scenario in ipairs(activeSuccessEntrypoints) do
    local active = FreshProfiles()
    ResetInstrumentation()
    ns.MSUF_UUFImport = nil
    uufLoaded = false
    importerMode = "success"

    local result, why = scenario.call()

    Check(scenario.name .. " succeeds", result == true, why)
    Check(scenario.name .. " loads LoD converter exactly once", (counts.loadAddon or 0) == 1, counts.loadAddon)
    Check(scenario.name .. " invokes native converter exactly once", (counts.convert or 0) == 1, counts.convert)
    Check(scenario.name .. " passes active table as converter base", capturedBase == active)
    Check(
        scenario.name .. " preserves active table reference",
        _G.MSUF_DB == active and _G.MSUF_GlobalDB.profiles.Active == active
    )
    Check(
        scenario.name .. " stores converter output",
        active.converterMarker == "native-uuf-converter"
            and active.nested and active.nested.translated == true
            and active.marker == nil
    )
    Check(scenario.name .. " refreshes status-icon runtime exactly once", (counts.statusRefresh or 0) == 1, counts.statusRefresh)
    Check(
        scenario.name .. " invalidates castbar settings cache before runtime apply",
        (counts.castbarCacheInvalidate or 0) == 1,
        counts.castbarCacheInvalidate
    )
    Check(scenario.name .. " emits converter report exactly once", (counts.report or 0) == 1, counts.report)
    Check(
        scenario.name .. " refreshes status icons after core notify and before report",
        EventIndex("notify") and EventIndex("statusRefresh") and EventIndex("report")
            and EventIndex("notify") < EventIndex("statusRefresh")
            and EventIndex("statusRefresh") < EventIndex("report"),
        table.concat(events, ",")
    )
    Check(
        scenario.name .. " bypasses generic decoders",
        (counts.compactDecode or 0) == 0 and (counts.legacyDecode or 0) == 0
    )
end

-- Combat keeps the same UUF-only refresh request attached to the existing
-- deferred profile apply instead of touching live frame geometry immediately.
do
    FreshProfiles()
    ResetInstrumentation()
    ns.MSUF_UUFImport = nil
    uufLoaded = false
    importerMode = "success"
    inCombat = true

    local result = ImportActive("!UUF_active_combat_success")
    local pending = _G.MSUF_ProfileIO_PendingPostProfileRuntimeApply
    local deferFrame = _G.MSUF_ProfileIO_PostProfileDeferFrame

    Check("combat UUF import stores successful profile conversion", result == true)
    Check("combat UUF import invalidates castbar cache before deferral", (counts.castbarCacheInvalidate or 0) == 1, counts.castbarCacheInvalidate)
    Check("combat UUF import does not refresh protected runtime immediately", (counts.statusRefresh or 0) == 0)
    Check("combat UUF import preserves pending status refresh", pending and pending.refreshStatus == true)
    Check("combat UUF import registers deferred runtime apply", deferFrame and deferFrame.registeredEvent == "PLAYER_REGEN_ENABLED")

    inCombat = false
    assert(deferFrame and type(deferFrame.OnEvent) == "function")
    deferFrame:OnEvent("PLAYER_REGEN_ENABLED")
    Check("deferred UUF apply does not broaden cache invalidation", (counts.castbarCacheInvalidate or 0) == 1, counts.castbarCacheInvalidate)
    Check("deferred UUF apply refreshes status icons after combat", (counts.statusRefresh or 0) == 1, counts.statusRefresh)
    Check("deferred UUF apply consumes pending request", _G.MSUF_ProfileIO_PendingPostProfileRuntimeApply == nil)
end

-- Native MSUF full imports retain the established runtime path while dropping
-- castbar caches once before their same-root replacement.
do
    local active = FreshProfiles()
    ResetInstrumentation()
    local decodeCompact = _G.MSUF_TryDecodeCompactString
    local importedProfile = DeepCopy(convertedTemplate)
    importedProfile.general = { anchorName = "UI_Parent" }
    importedProfile.pet = { anchorFrameName = "UI_Parent", anchorToUnitframe = "GLOBAL" }
    _G.MSUF_TryDecodeCompactString = function()
        return { addon = "MSUF", fmt = 2, kind = "all", payload = importedProfile }
    end

    local result = ImportActive("MSUF3:native_profile_smoke")
    _G.MSUF_TryDecodeCompactString = decodeCompact

    Check("native MSUF import still succeeds", result == true)
    Check("native MSUF full import invalidates castbar cache once", (counts.castbarCacheInvalidate or 0) == 1, counts.castbarCacheInvalidate)
    Check("native MSUF import repairs the UI_Parent alias",
        active.general and active.general.anchorName == "UIParent"
            and active.pet and active.pet.anchorFrameName == "UIParent")
    Check("native MSUF import does not request UUF status refresh", (counts.statusRefresh or 0) == 0, counts.statusRefresh)
    Check("native MSUF import does not load UUF converter", (counts.loadAddon or 0) == 0, counts.loadAddon)
end

-- Partial snapshots invalidate only when they can change castbar enable data.
for _, scenario in ipairs({
    {
        name = "native castbar snapshot",
        kind = "castbar",
        payload = { general = { enablePlayerCastbar = true } },
        expectedInvalidations = 1,
    },
    {
        name = "native colors snapshot",
        kind = "colors",
        payload = { general = { castbarInterruptibleR = 0.25 } },
        expectedInvalidations = 0,
    },
}) do
    FreshProfiles()
    ResetInstrumentation()
    local decodeCompact = _G.MSUF_TryDecodeCompactString
    _G.MSUF_TryDecodeCompactString = function()
        return { addon = "MSUF", fmt = 2, kind = scenario.kind, payload = scenario.payload }
    end

    local result = ImportActive("MSUF3:" .. scenario.name)
    _G.MSUF_TryDecodeCompactString = decodeCompact

    Check(scenario.name .. " still succeeds", result == true)
    Check(
        scenario.name .. " uses scoped castbar invalidation",
        (counts.castbarCacheInvalidate or 0) == scenario.expectedInvalidations,
        counts.castbarCacheInvalidate
    )
end

-- External native MSUF imports invalidate only when they replace the active
-- same-root profile; inactive destination profiles cannot affect runtime caches.
do
    local active = FreshProfiles()
    ResetInstrumentation()
    local decodeCompact = _G.MSUF_TryDecodeCompactString
    local importedProfile = DeepCopy(convertedTemplate)
    importedProfile.general = { font = "ExternalNativeFont" }
    _G.MSUF_TryDecodeCompactString = function()
        return { addon = "MSUF", fmt = 2, kind = "all", payload = importedProfile }
    end

    local result, why = ImportExternal("MSUF3:native_external_active_smoke", "Active")
    _G.MSUF_TryDecodeCompactString = decodeCompact

    Check("external native MSUF active import still succeeds", result == true, why)
    Check("external native MSUF active import preserves profile root", _G.MSUF_DB == active)
    Check(
        "external native MSUF active import stores payload",
        active.converterMarker == "native-uuf-converter"
            and active.general and active.general.font == "ExternalNativeFont"
    )
    Check(
        "external native MSUF active import invalidates castbar cache once",
        (counts.castbarCacheInvalidate or 0) == 1,
        counts.castbarCacheInvalidate
    )
    Check("external native MSUF active import bypasses UUF converter", (counts.convert or 0) == 0, counts.convert)
end

do
    local active, other = FreshProfiles()
    local activeSnapshot = DeepCopy(active)
    ResetInstrumentation()
    local decodeCompact = _G.MSUF_TryDecodeCompactString
    _G.MSUF_TryDecodeCompactString = function()
        return { addon = "MSUF", fmt = 2, kind = "all", payload = { general = { font = "InactiveNativeFont" } } }
    end

    local result, why = ImportExternal("MSUF3:native_external_inactive_smoke", "Other")
    _G.MSUF_TryDecodeCompactString = decodeCompact

    Check("external native MSUF inactive import still succeeds", result == true, why)
    Check("external native MSUF inactive import preserves target root", _G.MSUF_GlobalDB.profiles.Other == other)
    Check("external native MSUF inactive import stores payload", other.general and other.general.font == "InactiveNativeFont")
    Check("external native MSUF inactive import leaves active profile untouched", DeepEqual(active, activeSnapshot))
    Check(
        "external native MSUF inactive import bypasses runtime cache invalidation",
        (counts.castbarCacheInvalidate or 0) == 0,
        counts.castbarCacheInvalidate
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
    Check("inactive external import does not refresh active status icons", (counts.statusRefresh or 0) == 0, counts.statusRefresh)
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

-- The public refresh used by the UUF import must replace stale custom status-
-- icon geometry and immediately apply the imported UUF size to the live frame.
do
    local function Region()
        return {
            SetText = function(self, value) self.text = value end,
            SetSize = function(self, width, height) self.width, self.height = width, height end,
            ClearAllPoints = function(self) self.point = nil end,
            SetPoint = function(self, ...) self.point = { ... } end,
            SetTexture = function(self, value) self.texture = value end,
            GetTexture = function(self) return self.texture end,
            SetTexCoord = function(self, ...) self.texCoord = { ... } end,
            SetAlpha = function(self, value) self.alpha = value end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
        }
    end

    local staleIconCache = { showRest = true, restSize = 16, restSymbol = "rested_moonzzz" }
    local restingIcon = Region()
    local statusFrame = {
        unit = "player",
        _msufIsPlayer = true,
        _msufStatusConf = { stale = true },
        _msufStatusIconsConf = staleIconCache,
        statusIndicatorText = Region(),
        restingIndicatorIcon = restingIcon,
    }
    _G.MSUF_DB = {
        general = { stateIconsTestMode = true },
        player = {
            statusTextEnabled = false,
            showRestingIndicator = true,
            restedStateIndicatorSize = 32,
            restedStateIndicatorAnchor = "TOPLEFT",
            restedStateIndicatorOffsetX = 1,
            restedStateIndicatorOffsetY = 10,
            restedStateIndicatorSymbol = "rested_moonzzzz",
        },
    }
    _G.MSUF_UnitFrames = { player = statusFrame }

    local statusChunk, statusLoadError = loadfile(statusSource)
    assert(statusChunk, statusLoadError)
    statusChunk("MidnightSimpleUnitFrames", ns)
    assert(type(_G.MSUF_RefreshStatusIndicators) == "function")
    _G.MSUF_RefreshStatusIndicators()

    Check("UUF refresh discards stale custom-icon cache", statusFrame._msufStatusIconsConf ~= staleIconCache)
    Check("UUF refresh rebuilds doubled custom-icon size", statusFrame._msufStatusIconsConf.restSize == 32)
    Check("UUF refresh applies doubled custom-icon width", restingIcon.width == 32, restingIcon.width)
    Check("UUF refresh applies doubled custom-icon height", restingIcon.height == 32, restingIcon.height)
    Check(
        "UUF refresh applies selected custom status symbol",
        type(restingIcon.texture) == "string" and restingIcon.texture:find("rested_moonzzzz", 1, true) ~= nil,
        restingIcon.texture
    )
end

-- UUF can legitimately import edge and side anchors, not just corners. Load
-- the real preview helpers from source and prove their geometry matches the
-- corresponding 5.72 runtime helpers for every supported anchor.
do
    local handle, openError = io.open(previewSource, "rb")
    assert(handle, openError)
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()

    local function LoadPreviewHelper(name, nextName, parameters)
        local pattern = "local function " .. name .. "%b()%s*(.-)\nend\n\nlocal function " .. nextName
        local body = source:match(pattern)
        assert(body, "unable to extract preview helper " .. name)
        local chunk, chunkError = loadstring("return function(" .. parameters .. ")\n" .. body .. "\nend")
        assert(chunk, chunkError)
        return chunk()
    end

    local resolve = LoadPreviewHelper("ResolveRuntimeIconLayoutAnchor", "PositionRuntimeLayoutIconPreview", "anchor, allowCenter")
    local position = LoadPreviewHelper("PositionStatusCornerPreview", "PositionSameAnchorPreview", "frame, anchor, x, y, target, pad")
    local anchors = {
        TOPLEFT = { "LEFT", "TOPLEFT", 5, 3 },
        TOP = { "TOP", "TOP", 3, 3 },
        TOPRIGHT = { "RIGHT", "TOPRIGHT", 1, 3 },
        LEFT = { "LEFT", "LEFT", 5, 5 },
        CENTER = { "CENTER", "CENTER", 3, 5 },
        RIGHT = { "RIGHT", "RIGHT", 1, 5 },
        BOTTOMLEFT = { "LEFT", "BOTTOMLEFT", 5, 7 },
        BOTTOM = { "BOTTOM", "BOTTOM", 3, 7 },
        BOTTOMRIGHT = { "RIGHT", "BOTTOMRIGHT", 1, 7 },
    }

    for anchor, expected in pairs(anchors) do
        local point, relativePoint = resolve(anchor, false)
        Check("UUF preview layout resolves " .. anchor, point == expected[1] and relativePoint == expected[2], point .. "/" .. relativePoint)

        local target = {}
        local placed
        local frame = {
            ClearAllPoints = function() end,
            SetPoint = function(_, ...)
                placed = { ... }
            end,
        }
        position(frame, anchor, 3, 5, target, 2)
        Check(
            "UUF status preview positions " .. anchor,
            placed and placed[1] == anchor and placed[2] == target and placed[3] == anchor
                and placed[4] == expected[3] and placed[5] == expected[4],
            placed and table.concat({ tostring(placed[1]), tostring(placed[3]), tostring(placed[4]), tostring(placed[5]) }, "/")
        )
    end
end

-- The castbar stub keeps two caches for its event hotpath. Exercise the real
-- stub and the real Menu2 mutation path so same-root imports and leaf toggles
-- cannot leave the runtime helper on an old enable value.
do
    local function General(playerEnabled)
        return {
            enablePlayerCastbar = playerEnabled and true or false,
            enableTargetCastbar = false,
            enableFocusCastbar = false,
            enableBossCastbar = false,
        }
    end

    local castbarsLoaded = false
    local loadRequests = 0
    _G.C_AddOns = {
        IsAddOnLoaded = function(addon)
            return addon == "MidnightSimpleUnitFrames_Castbars" and castbarsLoaded
        end,
        LoadAddOn = function(addon)
            if addon == "MidnightSimpleUnitFrames_Castbars" then
                loadRequests = loadRequests + 1
                castbarsLoaded = true
                return true
            end
            return false
        end,
    }
    _G.C_Timer = { After = function(_, callback) callback() end }
    _G.MSUF_ScheduleOnce = nil
    _G.MSUF_RegisterModule = nil
    _G.MSUF_IsCastbarEnabledForUnit = nil
    _G.MSUF_AreAnyCastbarsEnabled = nil
    _G.MSUF_Castbars_OnSettingsChanged = nil
    _G.MSUF_Castbars_InvalidateSettingsCache = nil
    _G.MSUF_EnsureCastbarsLoaded = nil
    _G.MSUF_Castbars_ForceHideAll = nil
    _G.MSUF_DB = {
        general = General(false),
        boss = { enabled = true },
        focus = { enabled = true },
    }
    _G.MSUF_EnsureDB = function()
        _G.MSUF_DB = _G.MSUF_DB or {}
        _G.MSUF_DB.general = _G.MSUF_DB.general or General(false)
    end

    local stubChunk, stubError = loadfile(castbarStubSource)
    assert(stubChunk, stubError)
    stubChunk("MidnightSimpleUnitFrames", {})

    local isEnabled = assert(_G.MSUF_IsCastbarEnabledForUnit)
    local areAnyEnabled = assert(_G.MSUF_AreAnyCastbarsEnabled)
    local invalidate = assert(_G.MSUF_Castbars_InvalidateSettingsCache)

    Check("castbar cache fixture starts with player false", isEnabled("player") == false)
    Check("castbar cache fixture starts with aggregate false", areAnyEnabled() == false)

    local stableRoot = _G.MSUF_DB
    _G.MSUF_DB.general = General(true)
    invalidate()
    Check("castbar cache invalidation preserves profile root", _G.MSUF_DB == stableRoot)
    Check("castbar cache observes replaced general table", areAnyEnabled() == true)
    Check("player enable cache observes replaced general table", isEnabled("player") == true)

    _G.MSUF_DB.general.enablePlayerCastbar = false
    invalidate()
    Check("castbar cache observes same-table false mutation", areAnyEnabled() == false)
    Check("player enable cache observes same-table false mutation", isEnabled("player") == false)

    castbarsLoaded = false
    loadRequests = 0
    local visualRefreshes = 0
    local invalidationCalls = 0
    local settingsChangeCalls = 0
    local realInvalidate = assert(_G.MSUF_Castbars_InvalidateSettingsCache)
    local realOnSettingsChanged = assert(_G.MSUF_Castbars_OnSettingsChanged)
    _G.MSUF_Castbars_InvalidateSettingsCache = function(...)
        invalidationCalls = invalidationCalls + 1
        return realInvalidate(...)
    end
    _G.MSUF_Castbars_OnSettingsChanged = function(...)
        settingsChangeCalls = settingsChangeCalls + 1
        return realOnSettingsChanged(...)
    end
    _G.MSUF_UpdateCastbarVisuals = function() visualRefreshes = visualRefreshes + 1 end
    _G.MSUF2 = nil

    local bindingsChunk, bindingsError = loadfile(menuBindingsSource)
    assert(bindingsChunk, bindingsError)
    local menuNS = {}
    bindingsChunk("MidnightSimpleUnitFrames", menuNS)
    local menu = assert(menuNS.MSUF2)

    local changed = menu.SetGeneralValue(
        "enablePlayerCastbar",
        true,
        "CASTBAR_CACHE_SMOKE",
        { castbar = true, preview = false, applyAll = false, notify = false }
    )
    Check("Menu2 player castbar enable reports a change", changed == true)
    Check("Menu2 player castbar enable stores true", _G.MSUF_DB.general.enablePlayerCastbar == true)
    Check("Menu2 player castbar enable refreshes helper", isEnabled("player") == true)
    Check("Menu2 player castbar enable refreshes aggregate", areAnyEnabled() == true)
    Check("Menu2 player castbar enable requests LoD", loadRequests == 1, loadRequests)
    Check("Menu2 player castbar enable refreshes visuals", visualRefreshes == 1, visualRefreshes)
    Check("Menu2 player castbar enable invalidates exactly once", invalidationCalls == 1, invalidationCalls)
    Check("Menu2 player castbar enable applies settings exactly once", settingsChangeCalls == 1, settingsChangeCalls)

    menu.SetGeneralValue(
        "enablePlayerCastbar",
        false,
        "CASTBAR_CACHE_SMOKE",
        { castbar = true, preview = false, applyAll = false, notify = false }
    )
    Check("Menu2 player castbar disable stores false", _G.MSUF_DB.general.enablePlayerCastbar == false)
    Check("Menu2 player castbar disable refreshes helper", isEnabled("player") == false)
    Check("Menu2 player castbar disable refreshes aggregate", areAnyEnabled() == false)
    Check("Menu2 player castbar disable refreshes visuals", visualRefreshes == 2, visualRefreshes)
    Check("Menu2 player castbar disable invalidates exactly once", invalidationCalls == 2, invalidationCalls)
    Check("Menu2 player castbar disable applies settings exactly once", settingsChangeCalls == 2, settingsChangeCalls)

    menu.SetGeneralValue(
        "showPlayerCastTime",
        false,
        "CASTBAR_STYLE_SCOPE_SMOKE",
        { castbar = true, preview = false, applyAll = false, notify = false }
    )
    Check("Menu2 castbar style change retains visual refresh", visualRefreshes == 3, visualRefreshes)
    Check("Menu2 castbar style change bypasses enable invalidation", invalidationCalls == 2, invalidationCalls)
    Check("Menu2 castbar style change bypasses settings transition", settingsChangeCalls == 2, settingsChangeCalls)
end

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
