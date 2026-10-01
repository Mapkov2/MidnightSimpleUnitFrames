-- Headless construction harness for the real Menu2 runtime catalog.
-- It builds every registered page with the same client facts and records any
-- page that failed to build so the search index generator can fail closed.
_G = _G or _ENV
table.unpack = table.unpack or unpack

package.path = ".github/scripts/?.lua;tools/?.lua;tools/MenuTest/?.lua;" .. package.path
require("wow_stubs")

local Auras3Loader = require("auras3_test_loader")
Auras3Loader.Install()
local runtimePorts = assert(loadfile(".github/quality/service_ports.lua"))()
runtimePorts.Install([[MSUF_EnsureCooldownWidthObservers MSUF_UpdateCastbarWidthSourceSync
MSUF_ClearResolvedStatusbarTextureCache
MSUF_ApplyModules MSUF_GF_InvalidateConfCache MSUF_GF_RebuildAll
MSUF_ApplyMsufScale MSUF_TargetSoundDriver_ApplySetting MSUF_NSRTNicknames_ApplySetting
MSUF_EllesmereEditMode_SetEnabled MSUF_Grid2EditMode_SetEnabled MSUF_DetailsEditMode_SetEnabled
MSUF_DominosEditMode_SetEnabled MSUF_DandersEditMode_SetEnabled MSUF_BlizzardEditMode_SetEnabled
MSUF_BlizzardEditMode_ApplyProfileSnapshot MSUF_ClassPower_Apply MSUF_ApplyPowerBarEmbedLayout_All
MSUF_Castbars_OnSettingsChanged MSUF_ApplyAllCastbarsAndSync MSUF_UpdateAllFonts_Immediate
MSUF_RefreshStatusIndicators MSUF_UpdateAllBarTextures MSUF_RefreshAllFrameColors]])
local function Exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function Read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local text = file:read("*a") or ""
    file:close()
    return text
end

local function Dirname(path)
    return tostring(path or ""):gsub("[/\\]+$", ""):match("^(.*)[/\\][^/\\]+$") or "."
end

local function Join(left, right)
    left = tostring(left or ""):gsub("[/\\]+$", "")
    right = tostring(right or ""):gsub("^[/\\]+", "")
    return (left == "" or left == ".") and (left == "." and "./" .. right or right) or left .. "/" .. right
end

local function ResolveRepositoryRoot()
    for _, root in ipairs({ ".", "..", "../.." }) do
        if Exists(Join(root, "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"))
            and Exists(Join(root, "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_Mainline.toc"))
            and Exists(Join(root, "tools/classic-client-matrix.tsv"))
        then
            return root
        end
    end
    error("repository root not found (core, Options and the client matrix are required)")
end

local ROOT = ResolveRepositoryRoot()
local CORE = Join(ROOT, "MidnightSimpleUnitFrames")
local OPTIONS = Join(ROOT, "MidnightSimpleUnitFrames_Options")
local MSUF = assert(_G.MSUF_NS, "WoW stubs did not create MSUF_NS")
local M = assert(MSUF.MSUF2, "WoW stubs did not create MSUF2")
-- The synchronization selector reads actual named profile storage. Reuse the
-- pure shipped accessor rather than introducing a generator-only replacement.
local ProfileSlice = require("msuf_source_slice")
local profilesPath = Join(CORE, "State/MSUF_Profiles.lua")
assert(loadstring(ProfileSlice.Function(Read(profilesPath), "function MSUF_GetAllProfiles", profilesPath)))()
-- The Boss page shares its style and geometry owner with live unit frames.
assert(loadfile(Join(CORE, "UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua")))(
    "MidnightSimpleUnitFrames", MSUF)
_G.SlashCmdList = _G.SlashCmdList or {}
_G.floor, _G.ceil = _G.floor or math.floor, _G.ceil or math.ceil
_G.min, _G.max, _G.abs = _G.min or math.min, _G.max or math.max, _G.abs or math.abs

-- MenuTest's permissive regions synthesize a no-op method for every
-- unknown member.  Product UI code correctly uses underscore-prefixed members
-- as optional cached data, where an absent member must be nil rather than a
-- function.  Tighten that one behavior for real Menu2 construction.
do
    local patched = setmetatable({}, { __mode = "k" })
    local regionMinMaxValues = setmetatable({}, { __mode = "k" })
    local absentDataMember = {
        Instructions = true, Left = true, Middle = true, Mid = true, Right = true,
        Text = true, Low = true, High = true,
    }
    local function PatchRegion(region)
        local mt = region and getmetatable(region)
        if not mt or patched[mt] or type(mt.__index) ~= "function" then return region end
        patched[mt] = true
        local oldIndex = mt.__index
        mt.__index = function(object, key)
            if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
            if type(key) == "string" and key:match("^[a-z]") then return nil end
            if absentDataMember[key] then return nil end
            if key == "GetFrameLevel" or key == "GetScale" or key == "GetEffectiveScale"
                or key == "GetAlpha" or key == "GetValue" or key == "GetVerticalScroll"
                or key == "GetStringHeight" or key == "GetStringWidth"
            then
                return function() return 1 end
            end
            if key == "GetLeft" or key == "GetBottom" then return function() return 0 end end
            if key == "GetRight" or key == "GetTop" then return function() return 100 end end
            if key == "GetCenter" then return function() return 50, 50 end end
            if key == "SetMinMaxValues" then
                return function(self, minValue, maxValue)
                    regionMinMaxValues[self] = { minValue, maxValue }
                end
            end
            if key == "GetMinMaxValues" then
                return function(self)
                    local values = regionMinMaxValues[self]
                    if values then return values[1], values[2] end
                    return 0, 100
                end
            end
            if key == "GetText" then return function() return "" end end
            if key == "GetChecked" then return function() return false end end
            local value = oldIndex(object, key)
            if key == "CreateTexture" or key == "CreateFontString" then
                return function(self, ...)
                    return PatchRegion(value(self, ...))
                end
            end
            return value
        end
        return region
    end
    PatchRegion(_G.UIParent)
    local CreateFrameStub = _G.CreateFrame
    _G.CreateFrame = function(...) return PatchRegion(CreateFrameStub(...)) end
end

-- Seed the current shipped SavedVariables schema before loading the companion.
-- The catalog must index today's real defaults, not the smaller historical
-- manifest-only shape provided by MenuTest stubs.
do
    -- State/MSUF_StateHelpers.lua loads right before Defaults in the shipped TOC.
    local helpersPath = Join(CORE, "State/MSUF_StateHelpers.lua")
    local helpersChunk, helpersErr = loadfile(helpersPath)
    assert(helpersChunk, helpersPath .. ": " .. tostring(helpersErr))
    local helpersOK, helpersResult = pcall(helpersChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(helpersOK, helpersPath .. ": " .. tostring(helpersResult))
    local defaultsPath = Join(CORE, "State/MSUF_Defaults.lua")
    local chunk, err = loadfile(defaultsPath)
    assert(chunk, defaultsPath .. ": " .. tostring(err))
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
    assert(ok, defaultsPath .. ": " .. tostring(result))
    assert(type(_G.MSUF_EnsureDB) == "function", "current product MSUF_EnsureDB API did not load")
    local seeded, seedResult = pcall(_G.MSUF_EnsureDB, true)
    assert(seeded and type(seedResult) == "table", "current product defaults failed to seed: " .. tostring(seedResult))

    local groupDefaultsPath = Join(CORE, "GroupFrames/MSUF_GroupFrames_DB.lua")
    local groupChunk, groupErr = loadfile(groupDefaultsPath)
    assert(groupChunk, groupDefaultsPath .. ": " .. tostring(groupErr))
    local groupOK, groupResult = pcall(groupChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(groupOK, groupDefaultsPath .. ": " .. tostring(groupResult))
    -- The rest of the group DB, split by cohesion; it loads before the migrations.
    for _, part in ipairs({ "Geometry", "Text", "Textures" }) do
        local partPath = Join(CORE, "GroupFrames/MSUF_GroupFrames_DB_" .. part .. ".lua")
        local partChunk, partErr = loadfile(partPath)
        assert(partChunk, partPath .. ": " .. tostring(partErr))
        local partOK, partResult = pcall(partChunk, "MidnightSimpleUnitFrames", MSUF)
        assert(partOK, partPath .. ": " .. tostring(partResult))
    end
    local groupMigrationsPath = Join(CORE, "GroupFrames/MSUF_GroupFrames_DB_Migrations.lua")
    local groupMigrationsChunk, groupMigrationsErr = loadfile(groupMigrationsPath)
    assert(groupMigrationsChunk, groupMigrationsPath .. ": " .. tostring(groupMigrationsErr))
    local groupMigrationsOK, groupMigrationsResult = pcall(groupMigrationsChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(groupMigrationsOK, groupMigrationsPath .. ": " .. tostring(groupMigrationsResult))
    assert(MSUF.GF and type(MSUF.GF.EnsureDB) == "function", "current GroupFrames EnsureDB API did not load")
    local groupSeeded, groupSeedResult = pcall(MSUF.GF.EnsureDB)
    assert(groupSeeded, "current GroupFrames defaults failed to seed: " .. tostring(groupSeedResult))
    assert(type(_G.MSUF_DB.gf_party) == "table" and type(_G.MSUF_DB.gf_raid) == "table"
        and type(_G.MSUF_DB.gf_mythicraid) == "table", "current GroupFrames defaults did not create all scopes")

    -- Unit and Group pages embed the real Auras3 workspace.  Its cold-path
    -- model is loaded before Menu2 in the shipped addon, so reproduce that
    -- dependency here instead of silently auditing pages with the Aura section
    -- absent.
    local auraModelPath = Join(CORE, "Auras3/MSUF_Auras3_Menu_Model.lua")
    local auraChunk, auraErr = Auras3Loader.LoadFile(auraModelPath)
    assert(auraChunk, auraModelPath .. ": " .. tostring(auraErr))
    local auraOK, auraResult = pcall(auraChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(auraOK, auraModelPath .. ": " .. tostring(auraResult))
    assert(MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.MenuModel) == "table",
        "current Auras3 MenuModel dependency did not load")

    -- Menu2 reaches the shared protected-call boundary through the main addon,
    -- which loads it right after Bootstrap; reproduce that dependency too.
    local boundaryPath = Join(CORE, "Kernel/MSUF_Boundary.lua")
    local boundaryChunk, boundaryErr = loadfile(boundaryPath)
    assert(boundaryChunk, boundaryPath .. ": " .. tostring(boundaryErr))
    local boundaryOK, boundaryResult = pcall(boundaryChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(boundaryOK, boundaryPath .. ": " .. tostring(boundaryResult))
    assert(type(MSUF.ReportError) == "function", "current validation reporter did not load")
end

-- Load the real Menu2 product modules in their shipped XML order.  No catalog
-- records are invented by this audit.  A caller that audits a non-Mainline client
-- publishes that flavor's manifest list (read from its Options TOC) first; with no
-- list this stays the Mainline order it always was.
local MENU_XML = rawget(_G, "__MSUF_MENU2_XML_MANIFEST") or {
    "Shell/Menu2/MSUF_Menu2.xml",
    "Shell/Menu2/Search/MSUF_Menu2_Search.xml",
    "Shell/Menu2/MSUF_Menu2_AfterSearch.xml",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview.xml",
    "Shell/Menu2/MSUF_Menu2_AfterUnitPreview.xml",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview.xml",
    "Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml",
}

local loadedMenuFiles = 0
for _, relativeXml in ipairs(MENU_XML) do
    local xmlPath = Join(OPTIONS, relativeXml)
    local xmlDir = Dirname(xmlPath)
    for relativeLua in Read(xmlPath):gmatch('<Script%s+file="([^"]+)"') do
        local path = Join(xmlDir, relativeLua:gsub("\\", "/"))
        local chunk, err = loadfile(path)
        assert(chunk, path .. ": " .. tostring(err))
        local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
        assert(ok, path .. ": " .. tostring(result))
        loadedMenuFiles = loadedMenuFiles + 1
    end
end

local Catalog = assert(M.RuntimeControlCatalog, "real RuntimeControlCatalog did not load")
assert(type(Catalog.GetRecords) == "function", "RuntimeControlCatalog.GetRecords is missing")

-- Build every registered page through the product's real cold-path entry
-- point.  A tiny scroll host avoids constructing decorative window chrome;
-- page widgets, bindings, commands, and catalog registrations remain the real
-- product implementations.
assert(type(M.BuildPageEntry) == "function",
    "real Menu2 page builder API did not load")
M.cache = {}
M.scrollChild = _G.CreateFrame("Frame", "MSUFCatalogAuditScrollChild", _G.UIParent)
M.scrollFrame = nil

local pageBuildFailures = {}
local pageKeys = {}
for key, spec in pairs(M.pages or {}) do
    if type(key) == "string" and type(spec) == "table" and type(spec.build) == "function" then
        pageKeys[#pageKeys + 1] = key
    end
end
table.sort(pageKeys)
-- The product deliberately slices hidden lazy-section builds through timers.
-- This desktop audit needs the completed catalog before it can crosswalk any
-- setting, so run only its construction timers synchronously and restore the
-- shared stub immediately afterwards.
local originalTimerAfter = _G.C_Timer and _G.C_Timer.After
local menuTimer = M.MenuTimer
local originalMenuTimerAfter = menuTimer and menuTimer.After
local originalMenuTimerNewTimer = menuTimer and menuTimer.NewTimer
if _G.C_Timer then
    _G.C_Timer.After = function(_, callback)
        if type(callback) == "function" then callback() end
    end
end
if menuTimer then
    menuTimer.After = function(_, callback)
        if type(callback) == "function" then callback() end
    end
    menuTimer.NewTimer = function(_, callback)
        if type(callback) == "function" then callback() end
        return { Cancel = function() end }
    end
end
for i = 1, #pageKeys do
    local key = pageKeys[i]
    local ok, err = pcall(M.BuildPageEntry, key, true)
    if not ok then pageBuildFailures[#pageBuildFailures + 1] = { key = key, error = tostring(err) } end
end
if _G.C_Timer then _G.C_Timer.After = originalTimerAfter end
if menuTimer then
    menuTimer.After = originalMenuTimerAfter
    menuTimer.NewTimer = originalMenuTimerNewTimer
end

-- Build the real menu shell too. Page builders alone cannot instantiate the
-- window controls covered by REQUIRED_SHELL_CONTRACT, and accepting a catalog
-- without them would let a cold conditional control disappear from parity.
local shellOK, shellError = pcall(M.Open, "home")
if shellOK and M.frame and type(M.MinimizeSlashMenuWindow) == "function" then
    shellOK, shellError = pcall(M.MinimizeSlashMenuWindow, M.frame)
end
if shellOK and M.frame and type(M.RestoreSlashMenuWindow) == "function" then
    shellOK, shellError = pcall(M.RestoreSlashMenuWindow, M.frame)
end
if not shellOK then
    pageBuildFailures[#pageBuildFailures + 1] = { key = "menu_chrome", error = tostring(shellError) }
end

return { menu = M, catalog = Catalog, pageBuildFailures = pageBuildFailures }
