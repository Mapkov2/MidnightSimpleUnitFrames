-- Canonical MSUF keeps its established UF/UFCore identities and globals while
-- consuming the same embedded framework used by generic hosts.
local root = arg and arg[1] or "."
local addonRoot = root .. "/MidnightSimpleUnitFrames/"
local libraryRoot = addonRoot .. "Libs/MSUFUnitFrames/"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local libraryFiles = {
    "init.lua",
    "MSUF_UF_Secrets.lua",
    "MSUF_UF_Apply.lua",
    "MSUF_UF_Metadata.lua",
    "MSUF_UF_Layers.lua",
    "MSUF_UF_Core.lua",
    "MSUF_UF_Runtime.lua",
    "api.lua",
    "finalize.lua",
}

local metadata = {
    MidnightSimpleUnitFrames = {
        ["X-MSUF-UnitFrames"] = "MidnightSimpleUnitFramesUF",
        ["X-MSUF-UnitFrames-Prefix"] = "MSUF",
        ["X-MSUF-UnitFrames-LegacyGlobals"] = "1",
        ["X-MSUF-UFCore"] = "MidnightSimpleUnitFrames",
    },
    ConflictUF = {},
    ConflictGF = {},
    LegacyCollisionHost = {
        ["X-MSUF-UnitFrames"] = "LegacyCollisionGlobal",
        ["X-MSUF-UnitFrames-LegacyGlobals"] = "1",
    },
}
_G.C_AddOns = {
    GetAddOnMetadata = function(addonName, key)
        local values = metadata[addonName]
        return values and values[key] or nil
    end,
}
_G.GetAddOnMetadata = nil
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

local function LoadPath(path, addonName, namespace)
    local chunk, loadError = loadfile(path)
    Check(chunk ~= nil, loadError)
    return chunk(addonName, namespace)
end

local function LoadInit(addonName, namespace)
    return LoadPath(libraryRoot .. "init.lua", addonName, namespace)
end

local function LoadLibrary(addonName, namespace)
    for index = 1, #libraryFiles do
        LoadPath(libraryRoot .. libraryFiles[index], addonName, namespace)
    end
    return namespace.MSUFUnitFrames
end

-- Conflicting legacy aliases are corruption, not a merge opportunity. They
-- must fail before the framework writes any replacement aliases.
do
    local directUF, wrappedUF = {}, {}
    local legacyCore = { UF = wrappedUF }
    local namespace = { UF = directUF, UFCore = legacyCore }
    local ok, loadError = pcall(LoadInit, "ConflictUF", namespace)
    Check(ok == false, "conflicting ns.UF and ns.UFCore.UF were accepted")
    Check(tostring(loadError):find("conflicting ns.UF", 1, true) ~= nil,
        "UF conflict error was not descriptive")
    Check(namespace.UF == directUF and namespace.UFCore == legacyCore
        and legacyCore.UF == wrappedUF and namespace.MSUFUnitFrames == nil,
        "UF conflict partially mutated the legacy namespace")
end

do
    local directGF, wrappedGF = {}, {}
    local legacyCore = { GF = wrappedGF }
    local namespace = { GF = directGF, UFCore = legacyCore }
    local ok, loadError = pcall(LoadInit, "ConflictGF", namespace)
    Check(ok == false, "conflicting ns.GF and ns.UFCore.GF were accepted")
    Check(tostring(loadError):find("conflicting ns.GF", 1, true) ~= nil,
        "GF conflict error was not descriptive")
    Check(namespace.GF == directGF and namespace.UFCore == legacyCore
        and legacyCore.GF == wrappedGF and namespace.MSUFUnitFrames == nil,
        "GF conflict partially mutated the legacy namespace")
end

-- A legacy-global collision must be transactional. In particular, it may not
-- publish the metadata global before discovering that MSUF_UFCore is occupied.
do
    local occupiedCore = {}
    local exportCalls = 0
    local namespace = {
        ExportPublic = function()
            exportCalls = exportCalls + 1
        end,
    }
    _G.MSUF_UFCore = occupiedCore
    _G.LegacyCollisionGlobal = nil
    local ok, loadError = pcall(LoadInit, "LegacyCollisionHost", namespace)
    Check(ok == false, "occupied MSUF_UFCore global was replaced")
    Check(tostring(loadError):find("cannot replace", 1, true) ~= nil,
        "legacy-global collision error was not descriptive")
    Check(_G.MSUF_UFCore == occupiedCore and _G.LegacyCollisionGlobal == nil,
        "legacy-global collision partially published framework globals")
    Check(namespace.MSUFUnitFrames == nil and namespace.UFCore == nil
        and namespace.UF == nil and namespace.GF == nil,
        "legacy-global collision partially initialized the namespace")
    Check(exportCalls == 0, "legacy-global collision called ExportPublic")
end

_G.MSUF = nil
_G.MSUF_NS = nil
_G.MSUF_UFCore = nil
_G.MSUFUnitFrames = nil
_G.MidnightSimpleUnitFramesUF = nil
_G.LegacyCollisionGlobal = nil
_G.MSUF_UnitFrames = nil
_G.MSUF_UnitFramesList = nil
_G.MSUF_UFCore_NotifyConfigChanged = nil

local seedElement = { Apply = function() end }
local seedObject = {}
local seedFrame = {}
local legacyUF = {
    Elements = { SeedElement = seedElement },
    elements = { SeedElement = seedElement },
    elementTraits = { SeedElement = { apply = true } },
    elementOrder = { "SeedElement" },
    attachedFrameList = { seedObject },
    frameList = { seedFrame },
    frames = { player = seedFrame },
}
local legacyGF = { marker = "legacy-gf" }
local legacyAPISeed = {}
local legacyCore = {
    UF = legacyUF,
    GF = legacyGF,
    embedTarget = "stale-target",
    marker = "legacy-core",
    legacyAPI = { SeedLegacyAPI = legacyAPISeed },
}
local namespace = {
    UF = legacyUF,
    GF = legacyGF,
    UFCore = legacyCore,
}

LoadPath(addonRoot .. "Kernel/MSUF_Bootstrap.lua", "MidnightSimpleUnitFrames", namespace)
Check(_G.MSUF == namespace and _G.MSUF_NS == namespace,
    "bootstrap did not establish the canonical MSUF namespace")
Check(namespace.UF == legacyUF and namespace.GF == legacyGF
    and namespace.UFCore == legacyCore,
    "bootstrap replaced a legacy unit-frame identity")

_G.MSUF_UFCore = legacyCore
local framework = LoadLibrary("MidnightSimpleUnitFrames", namespace)
Check(framework == legacyCore, "embedded framework replaced MSUF.UFCore identity")
Check(namespace.MSUFUnitFrames == legacyCore and namespace.UFCore == legacyCore,
    "new and legacy framework paths do not share one object")
Check(namespace.UF == legacyUF and framework.UF == legacyUF
    and framework.Runtime == legacyUF,
    "embedded framework replaced MSUF.UF identity")
Check(namespace.GF == legacyGF and framework.GF == legacyGF,
    "embedded framework replaced MSUF.GF identity")
Check(legacyUF.Framework == framework, "legacy UF runtime has no framework back-reference")
Check(framework.elements == legacyUF.elements,
    "framework elements are not the legacy element registry")
Check(framework.objects == legacyUF.attachedFrameList,
    "framework objects are not the legacy attached-frame registry")
Check(legacyUF.elements.SeedElement == seedElement
    and legacyUF.Elements.SeedElement == seedElement
    and legacyUF.attachedFrameList[1] == seedObject,
    "pre-existing legacy runtime state was lost")
Check(framework.legacyAPI.SeedLegacyAPI == legacyAPISeed,
    "pre-existing UFCore legacy API table was replaced")

Check(framework.addonName == "MidnightSimpleUnitFrames"
    and framework.globalName == "MidnightSimpleUnitFramesUF"
    and framework.embedTarget == "MidnightSimpleUnitFrames"
    and framework.embedded == true,
    "canonical framework metadata is not legacy-compatible")
Check(framework.Private == nil, "canonical finalize exposed private framework state")
Check(_G.MidnightSimpleUnitFramesUF == framework, "canonical metadata global is missing")
Check(_G.MSUF_UFCore == framework, "legacy MSUF_UFCore global is missing")
Check(namespace.Public.UFCore == framework
    and namespace.PublicGlobals.MSUF_UFCore == framework,
    "bootstrap public registry does not expose the legacy UFCore")
Check(namespace.Compat.LegacyGlobals.MSUF_UFCore == true,
    "bootstrap did not record the legacy UFCore global")

Check(_G.MSUF_UnitFrames == legacyUF.frames,
    "legacy MSUF_UnitFrames global does not use the preserved frame registry")
Check(_G.MSUF_UnitFramesList == legacyUF.frameList,
    "legacy MSUF_UnitFramesList global does not use the preserved frame list")
Check(type(_G.MSUF_UFCore_NotifyConfigChanged) == "function"
    and _G.MSUF_UFCore_NotifyConfigChanged == legacyUF.NotifyConfigChanged,
    "legacy UFCore runtime function global is missing")
Check(framework.legacyAPI.MSUF_UFCore_NotifyConfigChanged
    == _G.MSUF_UFCore_NotifyConfigChanged,
    "framework legacy API and global runtime function diverged")

local oldPathElement = { Apply = function() end }
local newPathElement = { Apply = function() end }
Check(legacyUF.RegisterElement("LegacyPath", oldPathElement) == true,
    "legacy MSUF.UF.RegisterElement rejected a valid element")
framework:RegisterElement("FrameworkPath", newPathElement)
Check(framework.elements.LegacyPath == oldPathElement
    and legacyUF.Elements.LegacyPath == oldPathElement,
    "legacy registration did not reach the framework registry")
Check(legacyUF.elements.FrameworkPath == newPathElement
    and legacyUF.Elements.FrameworkPath == newPathElement,
    "framework registration did not reach the legacy registries")

print("PASS unitframes legacy compatibility: identities, aliases, globals, embedTarget, transactional failures")
