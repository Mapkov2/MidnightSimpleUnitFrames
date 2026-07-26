-- Deterministic, desktop-only crosswalk between the real Menu2 runtime-control
-- catalog, Graphify's extracted setting paths, and the restored V1 Assistant
-- registry.  This script never writes addon state or source files.
--
-- Usage from the repository root:
--   lua tools/assistant_v1_catalog_crosswalk.lua
--   lua tools/assistant_v1_catalog_crosswalk.lua --graphify-inventory
--
-- The default is the standalone live-Graphify audit. It requires the ignored
-- graphify-out/graph.json and proves that its complete setting projection is
-- byte-for-byte equivalent at the contract level to the tracked compact
-- inventory. Clean release/schema gates select --graphify-inventory explicitly.

-- Important truth boundary:
-- RuntimeControlCatalog only contains controls for pages that have actually
-- been built.  This harness builds every registered real Menu2 page with the
-- shared WoW stubs, then inspects Catalog.GetRecords().  Graphify remains the
-- independent source-level setting inventory, including paths that are not a
-- visible Menu2 control.  Generated V1 AutoCoverage entries are reported in a
-- separate bucket and never counted as explicit coverage.

_G = _G or _ENV
table.unpack = table.unpack or unpack

package.path = ".github/scripts/?.lua;tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
local GraphifyInventory = require("assistant_graphify_inventory")

local function ResolveGraphifySource()
    local requested = rawget(_G, "__MSUF_ASSISTANT_GRAPHIFY_SOURCE")
    for i = 1, #(arg or {}) do
        if arg[i] == "--graphify-live" then
            assert(not requested or requested == "live", "conflicting Graphify source modes")
            requested = "live"
        elseif arg[i] == "--graphify-inventory" then
            assert(not requested or requested == "inventory", "conflicting Graphify source modes")
            requested = "inventory"
        end
    end
    requested = requested or "live"
    assert(requested == "live" or requested == "inventory",
        "invalid Graphify source mode: " .. tostring(requested))
    return requested
end

local GRAPHIFY_SOURCE = ResolveGraphifySource()

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
        if Exists(Join(root, "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc"))
            and Exists(Join(root, "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options.toc"))
            and Exists(Join(root, "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc"))
            and Exists(Join(root, "tools/assistant_graphify_inventory_data.lua"))
        then
            return root
        end
    end
    error("repository root not found (core, Assistant companion, and tracked Graphify inventory are required)")
end

local ROOT = ResolveRepositoryRoot()
local dispositionChunk, dispositionError = loadfile(Join(
    ROOT, ".github/scripts/assistant_graphify_setting_dispositions.lua"))
assert(dispositionChunk, "Graphify disposition ledger could not load: " .. tostring(dispositionError))
local GraphifyDispositions = assert(dispositionChunk(), "Graphify disposition ledger returned no contract")
local CORE = Join(ROOT, "MidnightSimpleUnitFrames")
local OPTIONS = Join(ROOT, "MidnightSimpleUnitFrames_Options")
local MSUF = assert(_G.MSUF_NS, "WoW stubs did not create MSUF_NS")
local M = assert(MSUF.MSUF2, "WoW stubs did not create MSUF2")
_G.SlashCmdList = _G.SlashCmdList or {}
_G.floor, _G.ceil = _G.floor or math.floor, _G.ceil or math.ceil
_G.min, _G.max, _G.abs = _G.min or math.min, _G.max or math.max, _G.abs or math.abs

-- AssistantTraining's permissive regions synthesize a no-op method for every
-- unknown member.  Product UI code correctly uses underscore-prefixed members
-- as optional cached data, where an absent member must be nil rather than a
-- function.  Tighten that one behavior for real Menu2 construction.
do
    local patched = setmetatable({}, { __mode = "k" })
    local regionMinMaxValues = setmetatable({}, { __mode = "k" })
    local absentDataMember = {
        Instructions = true, Left = true, Middle = true, Right = true,
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
-- AutoCoverage must audit today's real defaults, not the smaller historical
-- manifest-only shape provided by AssistantTraining stubs.
do
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
    local auraChunk, auraErr = loadfile(auraModelPath)
    assert(auraChunk, auraModelPath .. ": " .. tostring(auraErr))
    local auraOK, auraResult = pcall(auraChunk, "MidnightSimpleUnitFrames", MSUF)
    assert(auraOK, auraModelPath .. ": " .. tostring(auraResult))
    assert(MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.MenuModel) == "table",
        "current Auras3 MenuModel dependency did not load")
end

-- Load the real Menu2 product modules in their shipped XML order.  No catalog
-- records are invented by this audit.
local MENU_XML = {
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

-- Load the complete V1 LoD companion into a distinct private table, just like
-- the live companion addon.  Fill AutoCoverage before pages are built: page UI
-- caches are not SavedVariables and must never change the registry baseline.
local loadedAssistant, private = Loader.LoadAssistantRuntime(MSUF, {
    root = ROOT,
    includeDashboard = true,
    includeDialogLocale = true,
    useCompanionPrivate = true,
})
local runtimeEntries = Loader.ReadRuntimeEntries(ROOT)
assert(#loadedAssistant == #runtimeEntries and private ~= MSUF, "V1 LoD companion load contract failed")
local A = assert(MSUF.Assistant, "V1 Assistant namespace missing")
local Registry = assert(A.Registry, "V1 Assistant registry missing")
local explicitSettingCount = #Registry:AllSettings()
local autoAdded = assert(A.AutoCoverage and A.AutoCoverage.Fill, "V1 AutoCoverage API missing")()

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

local function HasExecutableSettingContract(setting)
    return type(setting) == "table"
        and type(setting.get) == "function"
        and type(setting.set) == "function"
        and type(setting.apply) == "function"
end

local function AddIndex(index, path, setting)
    path = tostring(path or "")
    if path == "" then return end
    local bucket = index[path]
    if not bucket then bucket = {}; index[path] = bucket end
    for i = 1, #bucket do if bucket[i] == setting then return end end
    bucket[#bucket + 1] = setting
end

local explicitExact, generatedExact = {}, {}
local explicitIndex, generatedIndex = {}, {}
local settings = Registry:AllSettings()
for i = 1, #settings do
    local setting = settings[i]
    local index = setting.generated == true and generatedIndex or explicitIndex
    local exact = setting.generated == true and generatedExact or explicitExact
    AddIndex(exact, setting.key, setting)
    AddIndex(index, setting.key, setting)
    local keyScope = tostring(setting.key or ""):match("^([^%.]+)%.")
    local dbPath = tostring(setting.dbPath or "")
    if dbPath ~= "" then
        -- dbPath is normally relative to the key's root table.  Only exact,
        -- deterministic composites are indexed; labels/aliases are never used
        -- as proof of backing-setting identity.
        if keyScope then AddIndex(index, keyScope .. "." .. dbPath, setting) end
        local unit = tostring(setting.unit or "")
        if unit ~= "" then AddIndex(index, unit .. "." .. dbPath, setting) end
    end
end

local inventoryPath = Join(ROOT, "tools/assistant_graphify_inventory_data.lua")
local trackedGraphInventory = GraphifyInventory.Load(inventoryPath)
local selectedGraphInventory = trackedGraphInventory
if GRAPHIFY_SOURCE == "live" then
    local graphPath = Join(ROOT, "graphify-out/graph.json")
    assert(Exists(graphPath),
        "live Graphify audit requires graphify-out/graph.json; clean gates must select --graphify-inventory")
    local liveGraphInventory = GraphifyInventory.ParseGraph(graphPath)
    local current, drift = GraphifyInventory.Compare(trackedGraphInventory, liveGraphInventory)
    assert(current, "tracked Graphify setting inventory is stale: " .. tostring(drift)
        .. "; review the live graph, then run tools/generate_assistant_graphify_inventory.lua")
    selectedGraphInventory = liveGraphInventory
end

local graphPaths, graphTierByPath, graphEvidenceByPath =
    GraphifyInventory.ToCrosswalkMaps(selectedGraphInventory)
local graphPathCount = #graphPaths

local function GraphTier(path)
    return graphTierByPath[path] or "unclassified"
end

local function FoldedIndex(index)
    local folded = {}
    for key, rows in pairs(index) do
        for i = 1, #rows do AddIndex(folded, tostring(key):lower(), rows[i]) end
    end
    return folded
end
local explicitFolded, generatedFolded = FoldedIndex(explicitExact), FoldedIndex(generatedExact)

-- Source-verified semantic aliases where Graphify captured a runtime member or
-- shorthand rather than the registry's canonical backing-setting key.  These
-- stay in their own evidence bucket and are never presented as exact matches.
local HEURISTIC_SETTING_LINKS = {
    ["player.PowerBar"] = "player.showPowerBar",
    ["target.text"] = "general.castbarTargetShowSpellName",
    ["player.fontBaselineOffset"] = "fontScope.player.fontBaselineOffset",
    ["player.outline"] = "fontScope.player.outline",
    ["player.name"] = "player.showName",
}

local graphCrosswalk = {
    explicit = {}, generated = {}, explicitCasefold = {}, generatedCasefold = {}, missing = {},
    heuristic = {}, explicitAmbiguous = {}, generatedAmbiguous = {}, byTier = {},
}
local function TierStats(tier)
    local stats = graphCrosswalk.byTier[tier]
    if not stats then
        stats = { total = 0, explicit = 0, generated = 0, casefold = 0, heuristic = 0, missing = 0, ambiguous = 0 }
        graphCrosswalk.byTier[tier] = stats
    end
    return stats
end
local function ExecutableRows(rows)
    local out = {}
    for i = 1, #(rows or {}) do if HasExecutableSettingContract(rows[i]) then out[#out + 1] = rows[i] end end
    return out
end
for i = 1, graphPathCount do
    local path = graphPaths[i]
    local tier, stats = GraphTier(path), TierStats(GraphTier(path))
    stats.total = stats.total + 1
    local explicit = ExecutableRows(explicitExact[path])
    local generated = ExecutableRows(generatedExact[path])
    if #explicit == 1 then
        stats.explicit = stats.explicit + 1
        graphCrosswalk.explicit[#graphCrosswalk.explicit + 1] = { path = path, setting = explicit[1], tier = tier }
    elseif #explicit > 1 then
        stats.ambiguous = stats.ambiguous + 1
        graphCrosswalk.explicitAmbiguous[#graphCrosswalk.explicitAmbiguous + 1] = { path = path, settings = explicit, tier = tier }
    elseif #generated == 1 then
        stats.generated = stats.generated + 1
        graphCrosswalk.generated[#graphCrosswalk.generated + 1] = { path = path, setting = generated[1], tier = tier }
    elseif #generated > 1 then
        stats.ambiguous = stats.ambiguous + 1
        graphCrosswalk.generatedAmbiguous[#graphCrosswalk.generatedAmbiguous + 1] = { path = path, settings = generated, tier = tier }
    else
        local foldedExplicit = ExecutableRows(explicitFolded[path:lower()])
        local foldedGenerated = ExecutableRows(generatedFolded[path:lower()])
        if #foldedExplicit == 1 then
            stats.casefold = stats.casefold + 1
            graphCrosswalk.explicitCasefold[#graphCrosswalk.explicitCasefold + 1] = { path = path, setting = foldedExplicit[1], tier = tier }
        elseif #foldedGenerated == 1 then
            stats.casefold = stats.casefold + 1
            graphCrosswalk.generatedCasefold[#graphCrosswalk.generatedCasefold + 1] = { path = path, setting = foldedGenerated[1], tier = tier }
        else
            local mappedKey = HEURISTIC_SETTING_LINKS[path]
            local mapped = mappedKey and ExecutableRows(explicitExact[mappedKey]) or {}
            if #mapped == 1 then
                stats.heuristic = stats.heuristic + 1
                graphCrosswalk.heuristic[#graphCrosswalk.heuristic + 1] = {
                    path = path, setting = mapped[1], tier = tier, mappedKey = mappedKey,
                }
            else
                stats.missing = stats.missing + 1
                graphCrosswalk.missing[#graphCrosswalk.missing + 1] = { path = path, tier = tier }
            end
        end
    end
end

-- Graphify's raw unmatched nodes are not release gaps merely because they do
-- not look like a Registry key: callable APIs, transient frame fields, legacy
-- import aliases, aggregate tables, and action sentinels are all setting-shaped
-- in source.  They still require a path-by-path reviewed disposition.  The
-- ledger is exact (no prefix can bless a newly extracted path), verifies source
-- evidence, and validates every named canonical setting/action owner.
local graphDispositionReview = GraphifyDispositions.ValidateGraphCandidates(
    graphCrosswalk.missing,
    {
        evidenceByPath = graphEvidenceByPath,
        hasExecutableSetting = function(key)
            local rows = ExecutableRows(explicitExact[key])
            return #rows == 1
        end,
        hasExecutableAction = function(key)
            local action = Registry:GetAction(key)
            return type(action) == "table" and type(action.run) == "function"
        end,
    })

-- Crosswalk every real, currently built state-changing catalog control.  An
-- exact settingKey/actionKey is the only accepted V1 linkage.  A direct Menu2
-- closure proves that Menu2 itself can execute the control; it does not prove
-- V1 natural-language routing, so it is reported separately.
local catalogRecords = Catalog.GetRecords()
local catalogCoverage = assert(Catalog.GetCoverageReport, "RuntimeControlCatalog.GetCoverageReport is missing")()
local catalogRecordById = {}
for i = 1, #catalogRecords do catalogRecordById[catalogRecords[i].controlId] = catalogRecords[i] end
local layerContract = { total = 0, failures = {}, infoHooks = 0, infoHookMismatches = {} }
local function IsNumericLayerControl(record)
    if tostring(record and record.kind or "") ~= "slider" then return false end
    local label = tostring(record.label or ""):lower()
    if label:find("%f[%a]layer%f[^%a]") or label == "frame level" then return true end
    local key = tostring(record.settingKey or ""):lower()
    local leaf = key:match("([%w_]+)$") or ""
    return leaf == "layer"
        or (leaf:sub(-5) == "layer" and leaf:sub(-6) ~= "player")
        or leaf:sub(-16) == "frameleveloffset"
end
local function ReceivesLayerInfoHook(record)
    if tostring(record and record.kind or "") ~= "slider" then return false end
    local command = record.command or {}
    if tonumber(command.min) ~= 0 or tonumber(command.max) ~= 30 then return false end
    local label = tostring(record.label or ""):lower()
    return label:find("layer", 1, true) ~= nil or label == "frame level" or label == "frame layer"
end
for i = 1, #catalogRecords do
    local record = catalogRecords[i]
    local numericLayer = IsNumericLayerControl(record)
    local infoHook = ReceivesLayerInfoHook(record)
    if infoHook then layerContract.infoHooks = layerContract.infoHooks + 1 end
    if numericLayer ~= infoHook then
        layerContract.infoHookMismatches[#layerContract.infoHookMismatches + 1] = record
    end
    if numericLayer then
        layerContract.total = layerContract.total + 1
        local command = record.command or {}
        if tonumber(command.min) ~= 0 or tonumber(command.max) ~= 30 or tonumber(command.step) ~= 1 then
            layerContract.failures[#layerContract.failures + 1] = record
        end
    end
end
local catalogRuntimeUnresolvedByPage = {}
local catalogSemanticGapBuckets = {}
local function AddSemanticGapBucket(bucket)
    catalogSemanticGapBuckets[bucket] = (catalogSemanticGapBuckets[bucket] or 0) + 1
end
for i = 1, #(catalogCoverage.unresolvedTargets or {}) do
    local row = catalogCoverage.unresolvedTargets[i]
    local page = tostring(row.pageKey or "unknown")
    catalogRuntimeUnresolvedByPage[page] = (catalogRuntimeUnresolvedByPage[page] or 0) + 1
    local record = catalogRecordById[row.controlId] or {}
    if row.suggestedDisposition == "dynamic" then
        AddSemanticGapBucket("dynamic_review_candidate")
    elseif row.suggestedDisposition == "duplicate" then
        AddSemanticGapBucket("duplicate_review_candidate")
    elseif row.suggestedDisposition == "compound" then
        AddSemanticGapBucket("compound_review_candidate")
    elseif record.classification == "setting" then
        local path = tostring(record.controlPath or ""):lower()
        if path:find("/preview/", 1, true) then
            AddSemanticGapBucket("preview_state_needs_reclassification")
        elseif record.kind == "button" then
            AddSemanticGapBucket("setting_button_needs_compound_review")
        else
            AddSemanticGapBucket("scalar_setting_missing_key")
        end
    elseif record.classification == "action" then
        AddSemanticGapBucket("action_missing_key")
    else
        AddSemanticGapBucket("other_unmapped")
    end
end
local catalogCrosswalk = {
    total = #catalogRecords,
    stateChanging = 0,
    byClassification = {}, byKind = {}, byPage = {},
    blankTargetKey = 0, nonblankTargetKey = 0, nonblankUnresolvedTarget = 0,
    directMenuExecutable = {},
    explicitV1Setting = {}, generatedV1Setting = {}, explicitV1Action = {},
    noExplicitV1Link = {}, invalidCapability = {},
}
for i = 1, #catalogRecords do
    local public = catalogRecords[i]
    local command = public.command or {}
    local stateChanging = public.classification == "setting"
        or public.classification == "action"
        or public.classification == "ephemeral" and command.hasSet == true
    if stateChanging then
        catalogCrosswalk.stateChanging = catalogCrosswalk.stateChanging + 1
        local classification = tostring(public.classification or "unknown")
        local kind = tostring(public.kind or "unknown")
        local page = tostring(public.pageKey or "unknown")
        catalogCrosswalk.byClassification[classification] = (catalogCrosswalk.byClassification[classification] or 0) + 1
        catalogCrosswalk.byKind[kind] = (catalogCrosswalk.byKind[kind] or 0) + 1
        catalogCrosswalk.byPage[page] = (catalogCrosswalk.byPage[page] or 0) + 1
        local targetKey = public.classification == "setting" and public.settingKey
            or public.classification == "action" and public.actionKey or nil
        if targetKey and tostring(targetKey) ~= "" then
            catalogCrosswalk.nonblankTargetKey = catalogCrosswalk.nonblankTargetKey + 1
        else
            catalogCrosswalk.blankTargetKey = catalogCrosswalk.blankTargetKey + 1
        end
        local complete = command.hasSet == true
            and (public.classification ~= "setting" or command.hasGet == true)
        if not complete then
            catalogCrosswalk.invalidCapability[#catalogCrosswalk.invalidCapability + 1] = public
        elseif public.classification == "setting" and public.settingKey then
            local explicit = explicitIndex[public.settingKey] or {}
            local generated = generatedIndex[public.settingKey] or {}
            local found
            for j = 1, #explicit do if HasExecutableSettingContract(explicit[j]) then found = explicit[j]; break end end
            if found then
                catalogCrosswalk.explicitV1Setting[#catalogCrosswalk.explicitV1Setting + 1] = { control = public, setting = found }
            else
                for j = 1, #generated do if HasExecutableSettingContract(generated[j]) then found = generated[j]; break end end
                if found then
                    catalogCrosswalk.generatedV1Setting[#catalogCrosswalk.generatedV1Setting + 1] = { control = public, setting = found }
                else
                    catalogCrosswalk.nonblankUnresolvedTarget = catalogCrosswalk.nonblankUnresolvedTarget + 1
                    catalogCrosswalk.noExplicitV1Link[#catalogCrosswalk.noExplicitV1Link + 1] = public
                end
            end
        elseif public.classification == "action" and public.actionKey
            and Registry:GetAction(public.actionKey) ~= nil
        then
            local action = Registry:GetAction(public.actionKey)
            if type(action.run) == "function" then
                catalogCrosswalk.explicitV1Action[#catalogCrosswalk.explicitV1Action + 1] = { control = public, action = action }
            else
                catalogCrosswalk.nonblankUnresolvedTarget = catalogCrosswalk.nonblankUnresolvedTarget + 1
                catalogCrosswalk.noExplicitV1Link[#catalogCrosswalk.noExplicitV1Link + 1] = public
            end
        elseif command.hasSet == true then
            catalogCrosswalk.directMenuExecutable[#catalogCrosswalk.directMenuExecutable + 1] = public
            catalogCrosswalk.noExplicitV1Link[#catalogCrosswalk.noExplicitV1Link + 1] = public
        else
            catalogCrosswalk.noExplicitV1Link[#catalogCrosswalk.noExplicitV1Link + 1] = public
        end
    end
end
catalogCrosswalk.nonblankUnresolvedTarget = math.max(0,
    catalogCrosswalk.nonblankTargetKey
        - #catalogCrosswalk.explicitV1Setting
        - #catalogCrosswalk.generatedV1Setting
        - #catalogCrosswalk.explicitV1Action)

local function Percent(part, total)
    if total == 0 then return 0 end
    return math.floor((part * 10000 / total) + 0.5) / 100
end

local function FormatCounts(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do out[#out + 1] = tostring(keys[i]) .. ":" .. tostring(map[keys[i]]) end
    return table.concat(out, ",")
end

local unitGroupPageSet = {
    uf_player = true, uf_target = true, uf_targettarget = true, uf_focustarget = true,
    uf_focus = true, uf_pet = true, uf_boss = true,
    gf_layout = true, gf_bars = true, gf_indicators = true, gf_auras = true, gf_priority = true,
}
local unitGroupContractGaps, unitGroupRegistryMissing = 0, 0
for page, count in pairs(catalogRuntimeUnresolvedByPage) do
    if unitGroupPageSet[page] then unitGroupContractGaps = unitGroupContractGaps + count end
end

local unitGroupReverse = {
    total = 0, explicit = 0, dynamic = 0, compound = 0, duplicate = 0,
    semanticUnreviewed = 0, missing = 0, wrongPage = 0, buildFailures = 0, failures = {},
}
local searchRouting = M.Search and M.Search._RoutingAPI
local function PrepareUnitGroupSettingPage(setting, page)
    if not (searchRouting and type(searchRouting.SearchRouteForTarget) == "function"
        and type(searchRouting.ApplySearchRoute) == "function")
    then
        return true
    end
    local query = tostring(setting and setting.label or setting and setting.attribute or setting and setting.key or "")
    -- OpenExactSettingControl supplies the display label as both query and
    -- fallback; keep this audit on that production route instead of leaking a
    -- dotted Registry key into the human-language selector heuristics.
    local route = searchRouting.SearchRouteForTarget(page, query, query)
    local changed = searchRouting.ApplySearchRoute(page, route)
    if changed or not (M.cache and M.cache[page]) then
        local ok, err = pcall(M.BuildPageEntry, page, true)
        if not ok then return false, tostring(err) end
    end
    return true
end
for i = 1, #settings do
    local setting = settings[i]
    local page = tostring(setting and setting.page or "")
    if unitGroupPageSet[page] then
        unitGroupReverse.total = unitGroupReverse.total + 1
        local built, buildError = PrepareUnitGroupSettingPage(setting, page)
        if not built then
            unitGroupReverse.buildFailures = unitGroupReverse.buildFailures + 1
            unitGroupReverse.failures[#unitGroupReverse.failures + 1] = {
                key = setting.key, page = page, reason = "page_build_failed:" .. tostring(buildError), setting = setting,
            }
        end
        local record, _, source = Catalog.FindBySettingKey(setting.key, page, setting)
        if not record then
            unitGroupReverse.missing = unitGroupReverse.missing + 1
            unitGroupReverse.failures[#unitGroupReverse.failures + 1] = {
                key = setting.key, page = page, reason = source or "missing", setting = setting,
            }
        elseif record.pageKey ~= page then
            unitGroupReverse.wrongPage = unitGroupReverse.wrongPage + 1
            unitGroupReverse.failures[#unitGroupReverse.failures + 1] = {
                key = setting.key, page = page, reason = "wrong_page:" .. tostring(record.pageKey), setting = setting,
            }
        elseif source == "explicit" then
            unitGroupReverse.explicit = unitGroupReverse.explicit + 1
        elseif (source == "reviewed_dynamic_key" or source == "reviewed_dynamic_pattern")
            and tostring(record.assistantDisposition or "") == "dynamic"
        then
            unitGroupReverse.dynamic = unitGroupReverse.dynamic + 1
        else
            local disposition = tostring(record.assistantDisposition or "")
            if disposition == "compound" then
                unitGroupReverse.compound = unitGroupReverse.compound + 1
            elseif disposition == "duplicate" then
                unitGroupReverse.duplicate = unitGroupReverse.duplicate + 1
            else
                unitGroupReverse.semanticUnreviewed = unitGroupReverse.semanticUnreviewed + 1
                unitGroupReverse.failures[#unitGroupReverse.failures + 1] = {
                    key = setting.key, page = page, reason = source or "semantic_unreviewed", setting = setting,
                }
            end
        end
    end
end
for i = 1, #(catalogCoverage.registryMissingTargets or {}) do
    if unitGroupPageSet[tostring(catalogCoverage.registryMissingTargets[i].pageKey or "")] then
        unitGroupRegistryMissing = unitGroupRegistryMissing + 1
    end
end

local verbose = false
local unitGroupOnly = false
local globalGaps = false
local globalGapPage
for i = 1, #(arg or {}) do
    if arg[i] == "--verbose" or arg[i] == "-v" then verbose = true end
    if arg[i] == "--unit-group-only" then unitGroupOnly = true end
    if arg[i] == "--global-gaps" then globalGaps = true end
    globalGapPage = globalGapPage or tostring(arg[i] or ""):match("^%-%-page=(.+)$")
end

local GLOBAL_GAP_PAGES = {
    classpower = true, gameplay = true, home = true, menu_chrome = true, modules = true,
    opt_bars = true, opt_castbar = true, opt_colors = true, opt_fonts = true,
    opt_misc = true, profiles = true,
}

local globalReverse = {
    total = 0, explicit = 0, dynamic = 0, compound = 0, duplicate = 0,
    reviewedAlias = 0, standalone = 0, invalidStandalone = 0,
    standaloneGenerated = 0, standaloneExplicit = 0, generatedTotal = 0, generatedRouted = 0,
    semanticUnreviewed = 0, missing = 0, wrongPage = 0,
    failures = {}, failureByPage = {}, totalByPage = {},
}
if type(A.ResolveMenuPageForSetting) == "function" then
    for i = 1, #settings do
        local setting = settings[i]
        local page = A.ResolveMenuPageForSetting(setting)
        if GLOBAL_GAP_PAGES[page] then
            globalReverse.total = globalReverse.total + 1
            if setting.generated == true then globalReverse.generatedTotal = globalReverse.generatedTotal + 1 end
            globalReverse.totalByPage[page] = (globalReverse.totalByPage[page] or 0) + 1
            local record, _, source = Catalog.FindBySettingKey(setting.key, page, setting)
            if record and setting.generated == true then
                globalReverse.generatedRouted = globalReverse.generatedRouted + 1
            end
            if not record and source == "reviewed_standalone"
                and setting.menuControlDisposition == "standalone"
                and tostring(setting.menuControlDispositionReason or "") ~= ""
                and tostring(setting.menuControlDispositionEvidence or "") ~= ""
            then
                globalReverse.standalone = globalReverse.standalone + 1
                if setting.generated == true then
                    globalReverse.standaloneGenerated = globalReverse.standaloneGenerated + 1
                else
                    globalReverse.standaloneExplicit = globalReverse.standaloneExplicit + 1
                end
            elseif not record and setting.menuControlDisposition == "standalone" then
                globalReverse.invalidStandalone = globalReverse.invalidStandalone + 1
                globalReverse.failures[#globalReverse.failures + 1] = {
                    key = setting.key, page = page, reason = "invalid_standalone_contract", setting = setting,
                }
            elseif not record then
                globalReverse.missing = globalReverse.missing + 1
                globalReverse.failures[#globalReverse.failures + 1] = {
                    key = setting.key, page = page, reason = source or "missing", setting = setting,
                }
            elseif record.pageKey ~= page then
                globalReverse.wrongPage = globalReverse.wrongPage + 1
                globalReverse.failures[#globalReverse.failures + 1] = {
                    key = setting.key, page = page, reason = "wrong_page:" .. tostring(record.pageKey), setting = setting,
                }
            elseif source == "explicit" then
                globalReverse.explicit = globalReverse.explicit + 1
            elseif (source == "reviewed_dynamic_key" or source == "reviewed_dynamic_pattern")
                and tostring(record.assistantDisposition or "") == "dynamic"
            then
                globalReverse.dynamic = globalReverse.dynamic + 1
            elseif source == "reviewed_duplicate_alias" then
                globalReverse.duplicate = globalReverse.duplicate + 1
            elseif source == "reviewed_descriptor_alias" then
                globalReverse.reviewedAlias = globalReverse.reviewedAlias + 1
            elseif source == "semantic_descriptor" and record.assistantDisposition == "compound" then
                globalReverse.compound = globalReverse.compound + 1
            elseif source == "semantic_descriptor" and record.assistantDisposition == "duplicate" then
                globalReverse.duplicate = globalReverse.duplicate + 1
            else
                globalReverse.semanticUnreviewed = globalReverse.semanticUnreviewed + 1
                globalReverse.failures[#globalReverse.failures + 1] = {
                    key = setting.key, page = page, reason = source or "semantic_unreviewed", setting = setting,
                }
            end
            if #globalReverse.failures > 0 then
                local last = globalReverse.failures[#globalReverse.failures]
                if last.key == setting.key and last.page == page then
                    globalReverse.failureByPage[page] = (globalReverse.failureByPage[page] or 0) + 1
                end
            end
        end
    end
end

-- `general.barMode` is edited on Advanced Colors even though its runtime
-- domain is bars.  Keep this explicit cross-domain owner under a concrete
-- reverse-lookup regression: a semantic opt_bars fallback previously focused
-- the unrelated Absorb Anchor Mode control.
local barModeSetting = assert(Registry:GetSetting("general.barMode"),
    "general.barMode Registry setting is missing")
local barModePage = A.ResolveMenuPageForSetting(barModeSetting)
assert(barModePage == "opt_colors",
    "general.barMode must resolve to its real Advanced Colors owner")
local barModeControl, _, barModeSource = Catalog.FindBySettingKey(
    "general.barMode", barModePage, barModeSetting)
assert(barModeControl and barModeControl.pageKey == "opt_colors"
        and barModeControl.settingKey == "general.barMode"
        and barModeSource == "explicit",
    "general.barMode reverse lookup did not resolve its exact Advanced Colors control")

-- Global Bars exposes one outline-color swatch whose target follows the
-- explicit Bars scope. Shared must remain a reviewed finite route instead of
-- falling through to the duplicate Global Colors row, while scoped keys use
-- the narrow barScope pattern declared by that same live control.
local sharedOutlineSetting = assert(Registry:GetSetting("general.barOutlineColor"),
    "general.barOutlineColor Registry setting is missing")
local sharedOutlineControl, _, sharedOutlineSource = Catalog.FindBySettingKey(
    "general.barOutlineColor", "opt_bars", sharedOutlineSetting)
assert(sharedOutlineControl
        and sharedOutlineControl.controlId == "menu2.opt.bars.global.outline.color"
        and sharedOutlineSource == "reviewed_dynamic_key",
    "Global Bars outline color must route Shared to general.barOutlineColor")
local playerOutlineSetting = assert(Registry:GetSetting("barScope.player.barOutlineColor"),
    "barScope.player.barOutlineColor Registry setting is missing")
local playerOutlineControl, _, playerOutlineSource = Catalog.FindBySettingKey(
    "barScope.player.barOutlineColor", "opt_bars", playerOutlineSetting)
assert(playerOutlineControl
        and playerOutlineControl.controlId == sharedOutlineControl.controlId
        and playerOutlineSource == "reviewed_dynamic_pattern",
    "Global Bars outline color must route explicit scopes through the barScope pattern")

local requiredCatalogActions = {
    ["dashboard.globalUiScale.apply"] = "ephemeral",
    ["dashboard.globalUiScale.revertPending"] = "ephemeral",
    ["dashboard.globalUiScale.disable"] = "savedState",
    ["dashboard.msufFrameScale.apply"] = "ephemeral",
    ["dashboard.msufFrameScale.revertPending"] = "ephemeral",
    ["dashboard.menuScale.apply"] = "ephemeral",
    ["dashboard.menuScale.revertPending"] = "ephemeral",
    ["first_load.personalize"] = "savedState",
    ["first_load.import_profile"] = "savedState",
    ["first_load.use_defaults"] = "savedState",
    ["first_load.whats_new"] = "savedState",
    ["first_load.not_now"] = "savedState",
    ["first_load.full_settings"] = "savedState",
}
local catalogActionKeys = {}
for i = 1, #catalogRecords do
    local key = tostring(catalogRecords[i].actionKey or "")
    if key ~= "" then catalogActionKeys[key] = true end
end
local actionAudit = { total = 0, invalid = 0, missingRequired = 0, failures = {} }
local seenActionKeys = {}
local actions = Registry:AllActions()
for i = 1, #actions do
    local action = actions[i]
    local key = type(action) == "table" and tostring(action.key or "") or ""
    actionAudit.total = actionAudit.total + 1
    local reason
    if key == "" then reason = "missing_key"
    elseif seenActionKeys[key] then reason = "duplicate_key"
    elseif Registry:GetAction(key) ~= action then reason = "lookup_identity_mismatch"
    elseif type(action.run) ~= "function" then reason = "missing_run"
    elseif action.actionPolicyExplicit ~= true or action.actionPolicyError ~= nil then reason = "invalid_action_policy" end
    if key ~= "" then seenActionKeys[key] = true end
    if reason then
        actionAudit.invalid = actionAudit.invalid + 1
        actionAudit.failures[#actionAudit.failures + 1] = { key = key, reason = reason }
    end
end
for key, mutability in pairs(requiredCatalogActions) do
    local action = Registry:GetAction(key)
    local valid = action and action.mutability == mutability and catalogActionKeys[key] == true
    if key:find("^first_load%.") then
        valid = valid and action.transactionAdapter == "onboardingFirstLoad"
            and action.snapshotCoverage == "complete"
    end
    if not valid then
        actionAudit.missingRequired = actionAudit.missingRequired + 1
        actionAudit.failures[#actionAudit.failures + 1] = { key = key, reason = "required_catalog_action_contract" }
    end
end

local globalSettingProposals = {}
if globalGaps and type(A.ResolveMenuPageForSetting) == "function" then
    local unresolvedIds = {}
    for i = 1, #(catalogCoverage.unresolvedTargets or {}) do
        unresolvedIds[catalogCoverage.unresolvedTargets[i].controlId] = true
    end
    for i = 1, #settings do
        local setting = settings[i]
        local page = A.ResolveMenuPageForSetting(setting)
        if GLOBAL_GAP_PAGES[page] and (not globalGapPage or page == globalGapPage) then
            local record, _, source = Catalog.FindBySettingKey(setting.key, page, setting)
            if record and unresolvedIds[record.controlId] then
                local rows = globalSettingProposals[record.controlId]
                if not rows then rows = {}; globalSettingProposals[record.controlId] = rows end
                rows[#rows + 1] = { setting = setting, record = record, source = source }
            end
        end
    end
end

print("ASSISTANT V1 / GRAPHIFY / RUNTIME CATALOG CROSSWALK")
print(string.format("menuModules=%d pagesRegistered=%d pageBuildFailures=%d", loadedMenuFiles, #pageKeys, #pageBuildFailures))
print(string.format("assistantScripts=%d settings=%d explicit=%d generated=%d actions=%d autoAdded=%d",
    #loadedAssistant, #settings, explicitSettingCount, #settings - explicitSettingCount, #Registry:AllActions(), autoAdded))
print(string.format("graphifySource=%s trackedInventory=%d", GRAPHIFY_SOURCE, trackedGraphInventory.recordCount))
print(string.format("graphifySettings=%d exactExplicitReadWriteApplyContract=%d (%.2f%%) exactGeneratedFallback=%d sourceVerifiedHeuristic=%d casefoldExplicit=%d casefoldGenerated=%d unresolvedRawCandidates=%d ambiguous=%d",
    graphPathCount, #graphCrosswalk.explicit, Percent(#graphCrosswalk.explicit, graphPathCount),
    #graphCrosswalk.generated, #graphCrosswalk.heuristic, #graphCrosswalk.explicitCasefold,
    #graphCrosswalk.generatedCasefold, #graphCrosswalk.missing,
    #graphCrosswalk.explicitAmbiguous + #graphCrosswalk.generatedAmbiguous))
print(string.format("graphifyDispositionGate=candidates:%d,classified:%d,reviewed:%d,unclassified:%d,stale:%d,missingEvidence:%d,invalidOwners:%d,categories:%s,pass:%s",
    graphDispositionReview.candidateCount, graphDispositionReview.classifiedCount,
    graphDispositionReview.reviewedCount, #graphDispositionReview.unclassified,
    #graphDispositionReview.stale, #graphDispositionReview.missingEvidence,
    #graphDispositionReview.invalidOwners, FormatCounts(graphDispositionReview.byCategory),
    tostring(graphDispositionReview.pass == true)))
for _, tier in ipairs({ "core_read_write", "core_reference_only", "assistant_only", "unclassified" }) do
    local stats = graphCrosswalk.byTier[tier]
    if stats and stats.total > 0 then
        print(string.format("graphTier.%s=total:%d,explicit:%d,generated:%d,heuristic:%d,casefold:%d,unresolved:%d,ambiguous:%d",
            tier, stats.total, stats.explicit, stats.generated, stats.heuristic, stats.casefold, stats.missing, stats.ambiguous))
    end
end
print(string.format("runtimeCatalogRecords=%d stateChanging=%d explicitV1Settings=%d generatedV1Settings=%d explicitV1Actions=%d catalogCommandBackedNoV1Link=%d noExplicitV1Link=%d invalidCapability=%d",
    catalogCrosswalk.total, catalogCrosswalk.stateChanging,
    #catalogCrosswalk.explicitV1Setting, #catalogCrosswalk.generatedV1Setting,
    #catalogCrosswalk.explicitV1Action, #catalogCrosswalk.directMenuExecutable,
    #catalogCrosswalk.noExplicitV1Link, #catalogCrosswalk.invalidCapability))
print(string.format("catalogLayerContract=controls:%d,invalid:%d,greenInfoHooks:%d,hookMismatches:%d,range:0-30,step:1",
    layerContract.total, #layerContract.failures, layerContract.infoHooks, #layerContract.infoHookMismatches))
print(string.format("catalogRuntimeValidation=persisted:%d,resolvedTargets:%d,reviewedDispositions:%d,unresolvedTargets:%d,registryValidated:%d,registryMissing:%d,invalidCapabilities:%d,assistantContractComplete:%s",
    tonumber(catalogCoverage.persistedControls) or 0,
    tonumber(catalogCoverage.resolvedTargets) or 0,
    tonumber(catalogCoverage.reviewedDispositionCount) or 0,
    tonumber(catalogCoverage.unresolvedTargetCount) or 0,
    tonumber(catalogCoverage.registryValidatedTargetCount) or 0,
    tonumber(catalogCoverage.registryMissingTargetCount) or 0,
    tonumber(catalogCoverage.invalidCapabilityCount) or 0,
    tostring(catalogCoverage.assistantContractComplete == true)))
print(string.format("catalogDynamicRoutes=controls:%d,keys:%d,patterns:%d,invalid:%d unknown:%d,collisions:%d,unstableIds:%d shellComplete:%s catalogComplete:%s",
    tonumber(catalogCoverage.reviewedDynamicRouteControlCount) or 0,
    tonumber(catalogCoverage.reviewedDynamicRouteKeyCount) or 0,
    tonumber(catalogCoverage.reviewedDynamicRoutePatternCount) or 0,
    tonumber(catalogCoverage.invalidAssistantRouteCount) or 0,
    tonumber(catalogCoverage.byClassification and catalogCoverage.byClassification.unknown) or 0,
    tonumber(catalogCoverage.collisions) or 0,
    tonumber(catalogCoverage.unstableIds) or 0,
    tostring(catalogCoverage.shellContractComplete == true),
    tostring(catalogCoverage.catalogComplete == true)))
print("catalogRuntimeUnresolvedByPage=" .. FormatCounts(catalogRuntimeUnresolvedByPage))
print(string.format("catalogUnitGroupContractGaps=%d registryMissing=%d",
    unitGroupContractGaps, unitGroupRegistryMissing))
print(string.format("catalogUnitGroupReverse=total:%d,explicit:%d,dynamic:%d,compound:%d,duplicate:%d,unreviewed:%d,missing:%d,wrongPage:%d,buildFailures:%d",
    unitGroupReverse.total, unitGroupReverse.explicit, unitGroupReverse.dynamic,
    unitGroupReverse.compound, unitGroupReverse.duplicate, unitGroupReverse.semanticUnreviewed,
    unitGroupReverse.missing, unitGroupReverse.wrongPage, unitGroupReverse.buildFailures))
print(string.format("catalogGlobalReverse=total:%d,explicit:%d,dynamic:%d,compound:%d,duplicate:%d,reviewedAlias:%d,standalone:%d,invalidStandalone:%d,unreviewed:%d,missing:%d,wrongPage:%d",
    globalReverse.total, globalReverse.explicit, globalReverse.dynamic, globalReverse.compound,
    globalReverse.duplicate, globalReverse.reviewedAlias, globalReverse.standalone, globalReverse.invalidStandalone,
    globalReverse.semanticUnreviewed,
    globalReverse.missing, globalReverse.wrongPage))
print(string.format("catalogGlobalStandalone=generated:%d,explicit:%d,generatedRouted:%d,generatedTotal:%d",
    globalReverse.standaloneGenerated, globalReverse.standaloneExplicit,
    globalReverse.generatedRouted, globalReverse.generatedTotal))
print("catalogGlobalReverseTotalByPage=" .. FormatCounts(globalReverse.totalByPage))
print("catalogGlobalReverseFailuresByPage=" .. FormatCounts(globalReverse.failureByPage))
print(string.format("catalogActionParity=total:%d,invalid:%d,missingRequired:%d",
    actionAudit.total, actionAudit.invalid, actionAudit.missingRequired))
print("catalogSemanticGapBuckets=" .. FormatCounts(catalogSemanticGapBuckets))
print(string.format("catalogTargetKeys=blank:%d,nonblank:%d,nonblankUnresolved:%d",
    catalogCrosswalk.blankTargetKey, catalogCrosswalk.nonblankTargetKey, catalogCrosswalk.nonblankUnresolvedTarget))
print("catalogStateChangingByClassification=" .. FormatCounts(catalogCrosswalk.byClassification))
print("catalogStateChangingByKind=" .. FormatCounts(catalogCrosswalk.byKind))
print("catalogStateChangingByPage=" .. FormatCounts(catalogCrosswalk.byPage))
print("runtimeScope=desktop WoW stubs (enUS, Mage/default profile); conditional live/class/spec controls still require a live catalog export.")
print("verdict=Runtime catalog targets, Registry policies, shell controls, and reviewed page-local reverse routes are enforced by strict release assertions.")

if globalGaps then
    for i = 1, #(catalogCoverage.unresolvedTargets or {}) do
        local row = catalogCoverage.unresolvedTargets[i]
        if GLOBAL_GAP_PAGES[row.pageKey] and (not globalGapPage or row.pageKey == globalGapPage) then
            local record = catalogRecordById[row.controlId] or {}
            print(table.concat({
                "GLOBAL_CATALOG_GAP", tostring(row.pageKey or ""), tostring(row.controlId or ""),
                tostring(record.classification or ""), tostring(record.kind or ""),
                tostring(record.controlPath or ""), tostring(record.label or ""),
                tostring(row.suggestedDisposition or ""),
            }, "\t"))
        end
    end
    local proposalIds = {}
    for controlId in pairs(globalSettingProposals) do proposalIds[#proposalIds + 1] = controlId end
    table.sort(proposalIds)
    for i = 1, #proposalIds do
        local controlId = proposalIds[i]
        local rows = globalSettingProposals[controlId]
        local first = rows[1]
        if #rows == 1 then
            print(table.concat({
                "GLOBAL_SETTING_PROPOSAL", tostring(first.record.pageKey or ""), controlId,
                tostring(first.record.controlPath or ""), tostring(first.setting.key or ""), tostring(first.source or ""),
            }, "\t"))
        else
            local keys = {}
            for j = 1, #rows do keys[#keys + 1] = tostring(rows[j].setting.key or "") end
            table.sort(keys)
            print(table.concat({
                "GLOBAL_SETTING_AMBIGUOUS", tostring(first.record.pageKey or ""), controlId,
                tostring(first.record.controlPath or ""), table.concat(keys, ","),
            }, "\t"))
        end
    end
end

for i = 1, #pageBuildFailures do
    local failure = pageBuildFailures[i]
    print(string.format("PAGE_BUILD_FAILURE\t%s\t%s", failure.key, failure.error:gsub("[\r\n\t]+", " ")))
end
if verbose then
    for i = 1, #graphDispositionReview.unclassified do
        print("GRAPHIFY_UNCLASSIFIED_DISPOSITION\t" .. tostring(graphDispositionReview.unclassified[i]))
    end
    for i = 1, #graphDispositionReview.stale do
        print("GRAPHIFY_STALE_DISPOSITION\t" .. tostring(graphDispositionReview.stale[i]))
    end
    for i = 1, #graphDispositionReview.missingEvidence do
        print("GRAPHIFY_MISSING_EVIDENCE\t" .. tostring(graphDispositionReview.missingEvidence[i]))
    end
    for i = 1, #graphDispositionReview.invalidOwners do
        print("GRAPHIFY_INVALID_OWNER\t" .. tostring(graphDispositionReview.invalidOwners[i]))
    end
    for i = 1, #catalogRecords do
        local row = catalogRecords[i]
        if row.classification == "unknown" or row.collision == true or row.identityStable ~= true then
            print(string.format("CATALOG_IDENTITY_DIAGNOSTIC\t%s\t%s\t%s\t%s\tunknown=%s\tcollision=%s\tstable=%s\tidSource=%s\tpath=%s\tlabel=%s",
                tostring(row.controlId or ""), tostring(row.pageKey or ""),
                tostring(row.classification or ""), tostring(row.kind or ""),
                tostring(row.classification == "unknown"), tostring(row.collision == true),
                tostring(row.identityStable == true), tostring(row.idSource or ""),
                tostring(row.controlPath or ""), tostring(row.label or "")))
        end
    end
    for i = 1, #(catalogCoverage.invalidCapabilities or {}) do
        local row = catalogCoverage.invalidCapabilities[i]
        print(string.format("CATALOG_INVALID_CAPABILITY\t%s\t%s\t%s\t%s\t%s",
            tostring(row.controlId or ""), tostring(row.pageKey or ""),
            tostring(row.classification or ""), tostring(row.kind or ""),
            tostring(row.reason or "")))
    end
    for i = 1, #(catalogCoverage.registryMissingTargets or {}) do
        local row = catalogCoverage.registryMissingTargets[i]
        print(string.format("CATALOG_REGISTRY_MISSING\t%s\t%s\t%s\t%s",
            tostring(row.controlId or ""), tostring(row.pageKey or ""),
            tostring(row.classification or ""), tostring(row.targetKey or "")))
    end
    for i = 1, #unitGroupReverse.failures do
        local row = unitGroupReverse.failures[i]
        local descriptor = row.setting or {}
        print(string.format("CATALOG_UNIT_GROUP_REVERSE_FAILURE\t%s\t%s\t%s\tgenerated=%s\tdbPath=%s\tattribute=%s\ttype=%s\tlabel=%s\tunit=%s",
            tostring(row.key or ""), tostring(row.page or ""), tostring(row.reason or ""),
            tostring(descriptor.generated == true), tostring(descriptor.dbPath or ""),
            tostring(descriptor.attribute or ""), tostring(descriptor.type or ""),
            tostring(descriptor.label or ""), tostring(descriptor.unit or "")))
    end
    for i = 1, #globalReverse.failures do
        local row = globalReverse.failures[i]
        local descriptor = row.setting or {}
        print(string.format("CATALOG_GLOBAL_REVERSE_FAILURE\t%s\t%s\t%s\tgenerated=%s\tdbPath=%s\tattribute=%s\ttype=%s\tlabel=%s\tframeType=%s\tcategory=%s",
            tostring(row.key or ""), tostring(row.page or ""), tostring(row.reason or ""),
            tostring(descriptor.generated == true), tostring(descriptor.dbPath or ""),
            tostring(descriptor.attribute or ""), tostring(descriptor.type or ""),
            tostring(descriptor.label or ""), tostring(descriptor.frameType or ""),
            tostring(descriptor.category or "")))
    end
    for i = 1, #actionAudit.failures do
        local row = actionAudit.failures[i]
        print(string.format("CATALOG_ACTION_PARITY_FAILURE\t%s\t%s", tostring(row.key or ""), tostring(row.reason or "")))
    end
    for i = 1, #graphCrosswalk.explicit do
        local row = graphCrosswalk.explicit[i]
        print(string.format("GRAPHIFY_EXPLICIT\t%s\t%s\t%s", row.path, tostring(row.setting.key), row.tier))
    end
    for i = 1, #graphCrosswalk.generated do
        local row = graphCrosswalk.generated[i]
        print(string.format("GRAPHIFY_GENERATED_ONLY\t%s\t%s\t%s", row.path, tostring(row.setting.key), row.tier))
    end
    for i = 1, #graphCrosswalk.explicitCasefold do
        local row = graphCrosswalk.explicitCasefold[i]
        print(string.format("GRAPHIFY_CASEFOLD_EXPLICIT\t%s\t%s\t%s", row.path, tostring(row.setting.key), row.tier))
    end
    for i = 1, #graphCrosswalk.generatedCasefold do
        local row = graphCrosswalk.generatedCasefold[i]
        print(string.format("GRAPHIFY_CASEFOLD_GENERATED\t%s\t%s\t%s", row.path, tostring(row.setting.key), row.tier))
    end
    for i = 1, #graphCrosswalk.heuristic do
        local row = graphCrosswalk.heuristic[i]
        print(string.format("GRAPHIFY_SOURCE_VERIFIED_HEURISTIC\t%s\t%s\t%s", row.path, row.mappedKey, row.tier))
    end
    for i = 1, #graphCrosswalk.missing do
        local row = graphCrosswalk.missing[i]
        local disposition = GraphifyDispositions.ClassifyGraphCandidate(row.path, row.tier) or {}
        local evidence = graphEvidenceByPath[row.path] or {}
        local owner = disposition.ownerSetting and ("setting:" .. tostring(disposition.ownerSetting))
            or disposition.ownerAction and ("action:" .. tostring(disposition.ownerAction)) or "reviewed:no-independent-owner"
        print(string.format("GRAPHIFY_REVIEWED_DISPOSITION\t%s\t%s\t%s\t%s\t%s:%s",
            row.path, row.tier, tostring(disposition.category or "unclassified"), owner,
            tostring(evidence.sourceFile or ""), tostring(evidence.sourceLocation or "")))
    end
    for i = 1, #catalogCrosswalk.noExplicitV1Link do
        local row = catalogCrosswalk.noExplicitV1Link[i]
        print(table.concat({
            "CATALOG_NO_EXPLICIT_V1_LINK",
            tostring(row.controlId or ""), tostring(row.pageKey or ""),
            tostring(row.classification or ""), tostring(row.kind or ""),
            tostring(row.settingKey or row.actionKey or ""), tostring(row.label or ""),
        }, "\t"))
    end
    for i = 1, #(catalogCoverage.unresolvedTargets or {}) do
        local row = catalogCoverage.unresolvedTargets[i]
        print(table.concat({
            "CATALOG_RUNTIME_UNRESOLVED",
            tostring(row.controlId or ""), tostring(row.pageKey or ""),
            tostring(row.classification or ""), tostring(row.targetKey or ""),
        }, "\t"))
    end
end

-- This script is part of the release gate: diagnostics remain visible above,
-- while an incomplete runtime catalog is a hard failure below.
assert(#settings == explicitSettingCount + autoAdded, "V1 AutoCoverage/registry count is internally inconsistent")
assert(graphDispositionReview.pass == true, string.format(
    "Graphify raw-candidate disposition gate failed: unclassified=%d stale=%d missingEvidence=%d invalidOwners=%d (%s)",
    #graphDispositionReview.unclassified, #graphDispositionReview.stale,
    #graphDispositionReview.missingEvidence, #graphDispositionReview.invalidOwners,
    table.concat(graphDispositionReview.invalidOwners, ", ")))
assert(tonumber(catalogCoverage.total) == #catalogRecords, "catalog public records/coverage report drifted")
local layerContractFailureIds = {}
for i = 1, #layerContract.failures do
    layerContractFailureIds[i] = tostring(layerContract.failures[i].controlId or "unknown")
end
assert(layerContract.total > 0, "RuntimeControlCatalog did not discover any numeric MSUF Layer controls")
assert(#layerContract.failures == 0,
    "numeric MSUF Layer control escaped the 0..30/step 1 contract: " .. table.concat(layerContractFailureIds, ", "))
local layerInfoHookMismatchIds = {}
for i = 1, #layerContract.infoHookMismatches do
    layerInfoHookMismatchIds[i] = tostring(layerContract.infoHookMismatches[i].controlId or "unknown")
end
assert(#layerContract.infoHookMismatches == 0,
    "numeric MSUF Layer controls and shared three-dot shortcuts diverged: " .. table.concat(layerInfoHookMismatchIds, ", "))
assert(tonumber(catalogCoverage.invalidCapabilityCount) == 0,
    "RuntimeControlCatalog contains a setting/action with an invalid executable capability")
assert(catalogCoverage.catalogComplete == true,
    "RuntimeControlCatalog coverage is incomplete; inspect catalogRuntimeValidation/catalogDynamicRoutes above")
assert(unitGroupContractGaps == 0, "Unit/Group RuntimeControlCatalog contract gaps remain")
assert(unitGroupRegistryMissing == 0, "Unit/Group catalog key is missing from the Assistant registry")
assert(unitGroupReverse.buildFailures == 0, "Unit/Group reverse-parity page build failed")
assert(unitGroupReverse.wrongPage == 0, "Unit/Group Registry setting resolved through a cross-page fallback")
assert(unitGroupReverse.explicit + unitGroupReverse.dynamic == unitGroupReverse.total,
    "Unit/Group Registry setting lacks an exact page control or reviewed dynamic generic")
if not unitGroupOnly then
    assert(actionAudit.invalid == 0, "V1 action registry contract is invalid")
    assert(actionAudit.missingRequired == 0,
        "required Dashboard/FirstLoad action is missing from Registry or runtime catalog")
    assert(globalReverse.invalidStandalone == 0,
        "Global Registry setting has an invalid standalone menu-control contract")
    -- The explicit standalone inventory includes the three channel-tick
    -- controllers, minimap position, three compatibility-only legacy shadow
    -- presets, and four contextual-only aura colors; these are intentionally
    -- controller-owned settings without a scalar Menu2 widget (23 + 11).
    -- The three raw Bar Outline RGB channels are now claimed by the canonical
    -- composite color controller instead of counted as generated standalones.
    assert(globalReverse.standaloneGenerated == 148 and globalReverse.standaloneExplicit == 34,
        "reviewed Global standalone split changed; classify new generated or explicit no-widget settings")
    assert(globalReverse.generatedTotal
            == globalReverse.standaloneGenerated + globalReverse.generatedRouted,
        "generated Global setting bypassed both visible routing and reviewed standalone fallback")
    assert(globalReverse.wrongPage == 0,
        "Global Registry setting resolved through a cross-page fallback")
    assert(globalReverse.explicit + globalReverse.dynamic + globalReverse.compound
            + globalReverse.duplicate + globalReverse.reviewedAlias + globalReverse.standalone
            == globalReverse.total,
        "Global Registry setting lacks an exact control, reviewed dynamic route, or evidence-backed standalone disposition")
end
if #pageBuildFailures > 0 then os.exit(2) end
