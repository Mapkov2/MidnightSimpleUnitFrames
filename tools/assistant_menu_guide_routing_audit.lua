-- Full headless audit for Assistant "open ..." and "show me where ..." routing.
-- It keeps the Assistant registry, guided setup data, parser page targets, and
-- the current Menu2 page model on one deterministic contract.

_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")
local dispositionChunk, dispositionError = loadfile(
    ".github/scripts/assistant_graphify_setting_dispositions.lua")
assert(dispositionChunk, "Assistant disposition ledger could not load: " .. tostring(dispositionError))
local CoverageDispositions = assert(dispositionChunk(), "Assistant disposition ledger returned no contract")

local loaded = Loader.LoadAssistantRuntime(_G.MSUF_NS, {
    includeDashboard = false,
    includeDialogLocale = false,
    useCompanionPrivate = true,
})

local MSUF = assert(_G.MSUF_NS)
local A = assert(MSUF.Assistant)
local M = assert(MSUF.MSUF2)
assert(A.AutoCoverage and A.AutoCoverage.Fill)
A.AutoCoverage.Fill()

assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Navigation.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local failures = {}
local function Check(value, message)
    if not value then failures[#failures + 1] = tostring(message) end
end

local breadcrumbContracts = {
    { "profiles", "Features > Profiles" },
    { "modules", "Features > Profiles > Modules" },
    { "uf_target", "Frames > Unitframes > Target" },
    { "gf_indicators", "Frames > Party/Raid Frames > Status & Indicators" },
    { "gf_auras", "Frames > Party/Raid Frames > Auras" },
    { "gf_priority", "Frames > Party/Raid Frames > Priority" },
    { "auras3_styling", "Appearance > Auras" },
    { "auras3_buffs", "Appearance > Auras > Buffs" },
    { "opt_misc", "Appearance > Miscellaneous" },
}
for i = 1, #breadcrumbContracts do
    local row = breadcrumbContracts[i]
    Check(type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(row[1]) == row[2],
        string.format("Current menu breadcrumb drift for %s: expected '%s', got '%s'",
            row[1], row[2], tostring(type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(row[1]) or nil)))
end

local actualPages = {
    home = true, search = true, guided_setup = true,
    uf_player = true, uf_target = true, uf_focus = true, uf_pet = true,
    uf_boss = true, uf_targettarget = true, uf_focustarget = true,
    gf_layout = true, gf_bars = true, gf_indicators = true, gf_auras = true, gf_priority = true,
    opt_bars = true, opt_castbar = true, opt_colors = true, opt_fonts = true, opt_misc = true,
    auras3_styling = true, auras3_buffs = true, auras3_debuffs = true,
    auras3_custom = true, auras3_filters = true,
    classpower = true, gameplay = true, profiles = true, modules = true,
}
local legacyRoutedPages = { auras3 = true }

local navPages = 0
for i = 1, #(M.navItems or {}) do
    local item = M.navItems[i]
    if item.key then
        navPages = navPages + 1
        Check(actualPages[item.key], "Menu navigation references an unregistered page: " .. tostring(item.key))
    end
end

-- Every literal Assistant page declaration must either be a real Menu2 page
-- or the one intentional legacy Aura entry that open_page reroutes.
local literalPages = {}
local function CollectLiteralPages(source, fieldName)
    local pattern = "%f[%a]" .. fieldName .. "%s*=%s*\"([%w_]+)\"()"
    for page, afterQuote in source:gmatch(pattern) do
        local lineTail = source:sub(afterQuote):match("^([^\r\n]*)") or ""
        -- A quoted prefix followed by concatenation is not a complete page.
        if not lineTail:match("^%s*%.%.") then literalPages[page] = true end
    end
end
for i = 1, #loaded do
    local relative = tostring(loaded[i] or "")
    local handle = io.open("MidnightSimpleUnitFrames_Assistant/" .. relative, "rb")
    if handle then
        local source = handle:read("*a")
        handle:close()
        CollectLiteralPages(source, "page")
        CollectLiteralPages(source, "pageKey")
    end
end
for page in pairs(literalPages) do
    Check(actualPages[page] or legacyRoutedPages[page], "Assistant source declares an unknown Menu2 page: " .. page)
end

local Registry = assert(A.Registry)
local settings = Registry:AllSettings()
local index = assert(A.Knowledge and A.Knowledge.EnsureIndex)()
local R = assert(A.RouterPrivate)
local itemBySettingKey = {}
for i = 1, #index.items do
    local item = index.items[i]
    if item.kind == "setting" and item.setting then itemBySettingKey[item.setting.key] = item end
end

local mappedSettings, internalUnmapped, locationFollowups = 0, 0, 0
local internalUnmappedSettings = {}
local context = assert(A.GetContext and A.GetContext())
for i = 1, #settings do
    local setting = settings[i]
    local item = itemBySettingKey[setting.key]
    Check(item ~= nil, "Knowledge index omitted setting: " .. tostring(setting.key))
    if item then
        local knowledgePage = item.page
        local followupPage = R.FallbackPageForSetting(setting)
        Check(knowledgePage == followupPage, string.format(
            "Setting page drift for %s: search=%s followup=%s",
            tostring(setting.key), tostring(knowledgePage), tostring(followupPage)))
        if knowledgePage then
            mappedSettings = mappedSettings + 1
            Check(actualPages[knowledgePage], "Setting resolves to a non-current Menu2 page: "
                .. tostring(setting.key) .. " -> " .. tostring(knowledgePage))
            context.lastSetting = setting.key
            local location = R.LastChangedSettingItem()
            Check(location and location.page == knowledgePage, "Last-change 'show me where' drift for "
                .. tostring(setting.key) .. ": " .. tostring(location and location.page)
                .. " vs " .. tostring(knowledgePage))
            locationFollowups = locationFollowups + 1
        else
            internalUnmapped = internalUnmapped + 1
            internalUnmappedSettings[#internalUnmappedSettings + 1] = setting
        end
    end
end

local generatedNoMenuReview = CoverageDispositions.ValidateGeneratedNoMenuSettings(
    internalUnmappedSettings,
    {
        hasExecutableSetting = function(key)
            local setting = Registry:GetSetting(key)
            return type(setting) == "table"
                and type(setting.get) == "function"
                and type(setting.set) == "function"
                and type(setting.apply) == "function"
        end,
    })
for _, key in ipairs(generatedNoMenuReview.unclassified or {}) do
    print("GENERATED_NOMENU_UNCLASSIFIED	" .. tostring(key))
end
Check(generatedNoMenuReview.pass == true, string.format(
    "Generated no-Menu disposition gate failed: unclassified=%d stale=%d invalidEvidence=%d invalidOwners=%d staleKeys=%s",
    #generatedNoMenuReview.unclassified, #generatedNoMenuReview.stale,
    #generatedNoMenuReview.invalidEvidence, #generatedNoMenuReview.invalidOwners,
    table.concat(generatedNoMenuReview.stale, ",")))

local verboseUnmapped = false
for i = 1, #(arg or {}) do
    if arg[i] == "--verbose-unmapped" then verboseUnmapped = true end
end
if verboseUnmapped then
    table.sort(internalUnmappedSettings, function(left, right)
        return tostring(left and left.key or "") < tostring(right and right.key or "")
    end)
    for i = 1, #internalUnmappedSettings do
        local setting = internalUnmappedSettings[i]
        local disposition = CoverageDispositions.ClassifyGeneratedNoMenuSetting(setting) or {}
        local owner = disposition.ownerSetting and ("setting:" .. tostring(disposition.ownerSetting))
            or "reviewed:no-independent-owner"
        print(string.format("ASSISTANT_GENERATED_NO_MENU\t%s\tdisposition=%s\towner=%s\tdbPath=%s\ttype=%s\tcategory=%s",
            tostring(setting.key or ""), tostring(disposition.category or "unclassified"), owner,
            tostring(setting.dbPath or ""), tostring(setting.type or ""),
            tostring(setting.category or "")))
    end
end

local guideCount, guideStepCount = 0, 0
local guides = A.DiagnosticsRegistryData and A.DiagnosticsRegistryData.GUIDED_SETUP_GUIDES or {}
for guideKey, guide in pairs(guides) do
    guideCount = guideCount + 1
    for i = 1, #(guide.steps or {}) do
        local step = guide.steps[i]
        guideStepCount = guideStepCount + 1
        Check(actualPages[step.page], "Guided setup step points at an old page: "
            .. tostring(guideKey) .. "/" .. tostring(step.key) .. " -> " .. tostring(step.page))
    end
end

-- The removed Assistant text wizard intentionally has no guide rows. The
-- release surface is the native Menu2 tour, so audit its real stage catalog
-- instead of accepting guides=0/steps=0 as a green result.
local guidedTourPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"
local guidedTourFile = assert(io.open(guidedTourPath, "rb"), "native guided-tour source is missing")
local guidedTourSource = guidedTourFile:read("*a") or ""
guidedTourFile:close()
local stageBlock = guidedTourSource:match("local STAGES%s*=%s*{(.-)\n}\r?\n\r?\nlocal LEGACY_STAGE_TARGET")
Check(stageBlock ~= nil, "Native guided-tour stage catalog could not be parsed")
local nativeStageIds = {}
local nativeStages = 0
local stageCatalogChunk, stageCatalogError = loadstring(
    "return {" .. tostring(stageBlock or "") .. "}", "@assistant_guided_tour_stage_catalog")
Check(stageCatalogChunk ~= nil, "Native guided-tour stage catalog is not data-only Lua: "
    .. tostring(stageCatalogError))
local nativeStageCatalog = stageCatalogChunk and stageCatalogChunk() or {}
Check(type(nativeStageCatalog) == "table", "Native guided-tour stage catalog did not return a table")
nativeStages = #nativeStageCatalog
for i = 1, nativeStages do
    local row = nativeStageCatalog[i]
    local stageId = type(row) == "table" and tostring(row.id or "") or ""
    local page = type(row) == "table" and tostring(row.pageKey or "") or ""
    Check(stageId ~= "", "Native guided-tour stage " .. tostring(i) .. " has no stable id")
    Check(page ~= "", "Native guided-tour stage " .. tostring(stageId ~= "" and stageId or i)
        .. " has no pageKey")
    if stageId ~= "" then
        Check(not nativeStageIds[stageId], "Duplicate native guided-tour stage: " .. tostring(stageId))
        nativeStageIds[stageId] = true
    end
    if page ~= "" then
        Check(actualPages[page], "Native guided-tour stage points at an old page: "
            .. tostring(stageId) .. " -> " .. tostring(page))
    end
end
-- Thirty-nine reviewed native stages are the production baseline since the
-- Beta 29 tour refresh retargeted the 6.0 upgrade tour at 5.76 upgraders.
-- Derive the live count from STAGES so additions do not require an unrelated
-- audit update, while an accidental catalog collapse still fails closed.
Check(nativeStages >= 39, "Native guided-tour stage matrix collapsed below the 39-stage baseline: got "
    .. tostring(nativeStages))
Check(guidedTourSource:find("M.guidedTourStageCount = #STAGES", 1, true) ~= nil,
    "Native guided-tour runtime count is no longer derived from STAGES")
if nativeStages > 0 then
    guideCount = guideCount + 1
    guideStepCount = guideStepCount + nativeStages
end

local parserTargets = {
    { "open dashboard", "home" },
    { "open search", "search" },
    { "open player", "uf_player" }, { "open target", "uf_target" },
    { "open focus", "uf_focus" }, { "open pet", "uf_pet" }, { "open boss", "uf_boss" },
    { "open target of target", "uf_targettarget" }, { "open focus target", "uf_focustarget" },
    { "open group layout", "gf_layout" }, { "open group health and text", "gf_layout" },
    { "open group effects", "gf_bars" },
    { "open group dispel overlay", "gf_bars" },
    { "open group status and indicators", "gf_indicators" }, { "open group auras", "gf_auras" },
    { "open priority frames", "gf_priority" }, { "open pinned frames", "gf_priority" },
    { "open bars", "opt_bars" }, { "open cast bars", "opt_castbar" },
    { "open colors", "opt_colors" }, { "open fonts", "opt_fonts" },
    { "open miscellaneous", "opt_misc" }, { "open class resources", "classpower" },
    { "open gameplay", "gameplay" }, { "open profiles", "profiles" },
    { "open modules", "modules" },
    { "open aura style", "auras3_styling" }, { "open aura filters", "auras3_filters" },
    { "open custom auras", "auras3_custom" },
    { "open target buffs", "auras3_buffs" }, { "open focus debuffs", "auras3_debuffs" },
}
for i = 1, #parserTargets do
    local row = parserTargets[i]
    local plan = A.Parse(row[1])
    Check(plan and plan.kind == "action" and plan.action and plan.action.key == "open_page",
        "Parser did not create open_page for: " .. row[1])
    Check(plan and plan.args and plan.args.page == row[2], string.format(
        "Parser page drift for '%s': expected %s, got %s",
        row[1], row[2], tostring(plan and plan.args and plan.args.page)))
end

-- Exercise the legacy Aura page bridge through the real open_page action.
-- This catches both wrong unit/scope selection and nil route components.
local auraRoutes = {
    { "open auras", "auras3_styling" },
    { "open aura filters", "uf_player" },
    { "open target buffs", "uf_target" },
    { "open focus debuffs", "uf_focus" },
    { "open boss aura filters", "uf_boss" },
    { "open raid aura filters", "gf_auras" },
    { "open group auras", "gf_auras" },
}
M.SearchBridge = {
    OpenSearchTarget = function(page, query)
        M.activeKey = page
        M._auditLastQuery = query
    end,
}
M.Open = function(page) M.activeKey = page; return true end
M.SelectPage = M.Open
for i = 1, #auraRoutes do
    local row = auraRoutes[i]
    M.activeKey = "home"
    M._auditLastQuery = nil
    local plan = A.Parse(row[1])
    local ok, message = plan and plan.action and plan.action.run(plan.args)
    Check(ok == true, "Aura menu route failed for '" .. row[1] .. "': " .. tostring(message))
    Check(M.activeKey == row[2], string.format(
        "Aura menu route drift for '%s': expected %s, got %s",
        row[1], row[2], tostring(M.activeKey)))
end

local classPowerSource = assert(io.open(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua", "rb"))
local classPowerText = classPowerSource:read("*a")
classPowerSource:close()
Check(classPowerText:find('Meta("layout.independent_powerbar_shape", "setting", { settingKey = "player.detachedPowerBarShape" })', 1, true),
    "Independent Player power shape lacks an exact Class Resources control link")
local detachedShape = Registry:GetSetting("player.detachedPowerBarShape")
Check(detachedShape and A.ResolveMenuPageForSetting(detachedShape) == "classpower",
    "Independent Player power shape does not resolve to its new Class Resources control")

-- The late-bound Search bridge must preserve the opened/focused result, and
-- the exact-control facade must not report success when no matching anchor was
-- found after a menu move.
local bridgeNS = { MSUF2 = { Search = {
    OpenTarget = function() return true, true end,
} } }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_SearchBridge.lua"))(
    "MidnightSimpleUnitFrames", bridgeNS)
local bridgeCalled, bridgeOpened, bridgeFocused = bridgeNS.MSUF2.SearchBridge.OpenSearchTarget(
    "opt_misc", "MSUF Menu Font", "MSUF Menu Font")
Check(bridgeCalled == true and bridgeOpened == true and bridgeFocused == true,
    "Search bridge discarded the exact target result")

local apiM
apiM = {
    BlockCombatAction = function() return false end,
    Open = function(page) apiM.openedPage = page; return true end,
    SelectPage = function(page) apiM.openedPage = page; return true end,
    RuntimeControlCatalog = {
        FindBySettingKey = function()
            return { pageKey = "opt_misc", label = "MSUF Menu Font", identityLabel = "MSUF Menu Font" }, {}
        end,
    },
    SearchBridge = {
        OpenSearchTarget = function() return true, true, true end,
    },
    GetMenuBreadcrumb = function(page)
        return page == "opt_misc" and "Appearance > Miscellaneous" or page
    end,
}
local apiNS = {
    MSUF2 = apiM,
    ExportPublic = function(_, value) return value end,
}
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_API.lua"))(
    "MidnightSimpleUnitFrames", apiNS)
local exactOpened, exactMessage = apiM.OpenExactSettingControl("general.menuFontKey", "MSUF Menu Font", "opt_misc")
Check(exactOpened == true and apiM.openedPage == "opt_misc",
    "Exact setting control did not open its catalog-owned page")
Check(tostring(exactMessage):find("Appearance > Miscellaneous > MSUF Menu Font", 1, true) ~= nil,
    "Exact setting direction did not use the current visible menu breadcrumb: " .. tostring(exactMessage))
apiM.SearchBridge.OpenSearchTarget = function() return true, true, false end
local falseSuccess = apiM.OpenExactSettingControl("general.menuFontKey", "MSUF Menu Font", "opt_misc")
Check(falseSuccess == false, "Exact setting control reported success without a matching menu anchor")

if #failures > 0 then
    for i = 1, #failures do io.stderr:write("ASSISTANT MENU GUIDE AUDIT FAIL: " .. failures[i] .. "\n") end
    os.exit(1)
end

print(string.format(
    "assistant_menu_guide_routing_audit: ok nav=%d breadcrumbs=%d literals=%d settings=%d mapped=%d internal_unmapped=%d location_followups=%d guides=%d steps=%d parser_targets=%d aura_routes=%d",
    navPages, #breadcrumbContracts, (function() local n = 0; for _ in pairs(literalPages) do n = n + 1 end; return n end)(),
    #settings, mappedSettings, internalUnmapped, locationFollowups,
    guideCount, guideStepCount, #parserTargets, #auraRoutes))
do
    local categories = {}
    for category, count in pairs(generatedNoMenuReview.byCategory or {}) do
        categories[#categories + 1] = tostring(category) .. ":" .. tostring(count)
    end
    table.sort(categories)
    print(string.format(
        "assistant_generated_no_menu_disposition_gate: candidates=%d classified=%d reviewed=%d unclassified=%d stale=%d invalidEvidence=%d invalidOwners=%d categories=%s pass=%s",
        generatedNoMenuReview.candidateCount, generatedNoMenuReview.classifiedCount,
        generatedNoMenuReview.reviewedCount, #generatedNoMenuReview.unclassified,
        #generatedNoMenuReview.stale, #generatedNoMenuReview.invalidEvidence,
        #generatedNoMenuReview.invalidOwners, table.concat(categories, ","),
        tostring(generatedNoMenuReview.pass == true)))
end
