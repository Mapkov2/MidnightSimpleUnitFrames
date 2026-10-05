-- Search stays descriptive: exact navigation, no setting execution, bounded cold work.
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Check(value, message) assert(value, "search_navigation_only_smoke: " .. message); return value end
local world = World.New(root, "Mainline")
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.message))
local M = Check(world.core.MSUF2, "missing menu")
local API = Check(M.Search._CoreAPI, "missing search")
Check(API.SubmitAssistantSearchQuery == nil and M.Search.SubmitAssistantQuery == nil,
    "search retains an execution entry point")
Check(M.StartNewAssistantTask == nil and M.RunDashboardDirectAction == nil,
    "dashboard retains virtual execution adapters")
local shown, combat, collected, clicked, built, completed = true, false, 0, 0, 0, 0
M.frame = { IsShown = function() return shown end }
world.env.InCombatLockdown = function() return combat end
world.env.UnitAffectingCombat = function() return false end
M.RegisterPage("zz_navigation", { title = "Navigation lab", build = function() end })
M.RegisterSearchProvider("navigation-lab", function()
    collected = collected + 1
    return { { pageKey = "zz_navigation", kind = "toggle", label = "Navigation proof switch",
        keywords = "qzxnavigation qzxproviderphrase", settingKey = "general.navigationProof" } }
end)
M.frame = nil
Check(#API.SearchPages("qzxnavigation") == 0 and #API.GetSearchRecords() == 0 and collected == 0,
    "search collected or indexed before the menu existed")
Check(API.OpenSearchTarget("zz_navigation", "proof") == false, "search routed before menu creation")
API.BuildSearchPage({}) -- A hidden render must return before reading/building any context widgets.
M.frame = { IsShown = function() return shown end }
local pumped = 0
M.UnitPage.PumpBackgroundSections = function() pumped = pumped + 1 end
M.BuildRuntimeWidgetCommand = function() built = built + 1; error("search built a setter") end
local widget = {
    GetScript = function() return function() clicked = clicked + 1 end end,
    GetParent = function() end,
}
M.RegisterSearchWidget(widget, { pageKey = "zz_navigation", label = "Navigation proof switch",
    kind = "toggle", classification = "setting", keywords = "qzxnavigation",
    controlId = "menu2.zz_navigation.proof", settingKey = "general.navigationProof" })
-- Exact setting lookup must not revive the old descriptor/label inference.
local catalog = M.RuntimeControlCatalog
local _, exactWidget = catalog.FindBySettingKey("general.navigationProof", "zz_navigation")
Check(exactWidget == widget, "registered setting identity no longer resolves")
local absent = catalog.FindBySettingKey("general.unregisteredProof", "zz_navigation", {
    label = "Navigation proof switch", attribute = "navigationProof", type = "boolean",
})
Check(absent == nil, "unregistered setting resolved by descriptor text")
-- Dictionary spellings and input use the same accent fold. Multiple natural
-- aliases that fold to one key retain both meanings; unknown qualifiers remain.
M.SearchData.STOP_WORDS["déjà"] = true
M.SearchData.QUERY_ALIASES["réglées"] = { "qzxnavigation" }
M.SearchData.QUERY_ALIASES["règlées"] = { "qzxsecondmeaning" }
local results = API.SearchPages("qzxnavigation")
Check(#results > 0 and built == 0 and clicked == 0 and pumped == 0, "query executed a setter or pumped lazy UI builds")
for _, row in ipairs(results) do Check(row.command == nil, "result exposes a setter") end
Check(#API.SearchPages("réglées déjà") > 0, "accented alias/grammar keys missed their normalized input")
local _, foldedClauses = M.Search._RoutingContext.BuildSearchQueryClauses("réglées")
local meanings = {}
for _, term in ipairs(foldedClauses[1].terms) do meanings[term] = true end
Check(meanings.qzxnavigation and meanings.qzxsecondmeaning, "normalized-equivalent aliases lost a meaning")
Check(#API.SearchPages("qzxnavigation zqxunrecognized") == 0, "unknown qualifier was silently ignored")
Check(#API.SearchPages("zqxunrecognized") == 0, "random text returned unrelated results")

local providerMatch
for _, row in ipairs(API.SearchPages("qzxproviderphrase")) do
    if row.exactTarget and row.exactTarget.controlId == "menu2.zz_navigation.proof" then providerMatch = row end
end
Check(providerMatch and providerMatch.anchor == widget, "live record lost provider-only query words or exact anchor")
M.RegisterSearchProvider("navigation-lab", function() collected = collected + 1; return {} end)
for _, row in ipairs(API.SearchPages("qzxproviderphrase")) do
    Check(not (row.exactTarget and row.exactTarget.controlId == "menu2.zz_navigation.proof"),
        "cached live record retained removed provider words")
end

-- Context signatures must follow direct record builds as well as queries;
-- otherwise an off -> on -> off cycle can match an obsolete signature.
local contextEnabled, contextLast = false, nil
M.RegisterSearchProvider("context-lab", function()
    if not contextEnabled then return {} end
    return {{pageKey="zz_navigation", kind="toggle", label="Context proof", controlId="menu2.zz_navigation.context"}}
end, function()
    local changed = contextLast ~= contextEnabled
    contextLast = contextEnabled
    return changed
end)
local function ContextPresent()
    for _, row in ipairs(API.GetSearchRecords()) do
        if row.exactTarget and row.exactTarget.controlId == "menu2.zz_navigation.context" then return true end
    end
    return false
end
Check(not ContextPresent(), "off context initially indexed")
contextEnabled = true
M.InvalidateSearchProvider("context-lab")
Check(ContextPresent(), "direct record build lost enabled context")
contextEnabled = false
Check(not ContextPresent(), "direct record build retained stale context signature")
-- Native characters count as characters, including a one-syllable Korean
-- replacement and Cyrillic deletion; the ASCII/transliteration path remains.
local typoCases = {
    { "Größenänderung", "Groessenaenderng" },
    { "здоровье", "здорове" },
    { "체력", "채력" },
    { "护盾", "护吨" },
}
M.RegisterSearchProvider("native-typos", function()
    local rows = {}
    for index, case in ipairs(typoCases) do
        rows[index] = { pageKey = "zz_navigation", kind = "toggle", label = case[1],
            controlId = "menu2.zz_navigation.native." .. index }
    end
    return rows
end)
for index, case in ipairs(typoCases) do
    local found
    for _, row in ipairs(API.SearchPages(case[2])) do
        if row.exactTarget and row.exactTarget.controlId == "menu2.zz_navigation.native." .. index then found = true end
    end
    Check(found, "native typo failed: " .. case[2])
end
local before = collected
shown = false
M.InvalidateSearchProvider("navigation-lab")
Check(#API.SearchPages("qzxnavigation") == 0 and collected == before, "closed menu collected/query results")
shown = true
combat = true
Check(#API.SearchPages("qzxnavigation") == 0 and collected == before, "combat collected/query results")
local invalidations = 0
local oldInvalidate = M.InvalidatePage
M.InvalidatePage = function() invalidations = invalidations + 1 end
API.OpenSearchResults("qzxnavigation")
Check(invalidations == 0, "combat rebuilt search UI")
combat = false
local db = M.GetGeneralDB()
local stored = db.msufUiScale
M.Search.ApplyRoute("opt_bars", { general = { msufUiScale = 1.73 } })
Check(db.msufUiScale == stored, "navigation changed a feature value")
M.InvalidatePage = oldInvalidate
-- The debounce callback crosses combat and menu-close boundaries without work.
API.ScheduleSearchInputQuery(nil, "qzxnavigation", false, function() completed = completed + 1 end)
Check(M.MenuRuntime:PendingTaskCount() > 0, "debounce did not schedule work")
combat = true
world.widgets:RunTimers(10000)
Check(completed == 0 and collected == before, "pending query ran after combat began")
API.CancelSearchBackgroundIndex()
Check(M.searchResultsPending == nil, "cancel retained pending work")
combat = false
API.ScheduleSearchInputQuery(nil, "qzxnavigation", false, function() completed = completed + 1 end)
shown = false
world.widgets:RunTimers(10000)
Check(completed == 0 and collected == before, "pending query ran after menu closed")
Check(clicked == 0 and built == 0, "search invoked a control")

-- Declared sections resolve without inspecting label text; stale controls and
-- page-only FAQ rows never fall back to a similar-looking widget.
shown = true
local oldSelect, oldCatalog = M.SelectPage, M.RuntimeControlCatalog
local wrapper = { GetTop = function() end, GetRegions = function() error("routing scanned visible labels") end }
local section = { GetTop = function() end, GetParent = function() return wrapper end }
local revealed, opened = 0, 0
section._msuf2CollapsibleEntry = { open = false, header = { Click = function() opened = opened + 1 end } }
M.cache.zz_navigation = { wrapper = wrapper, sections = { declared = section },
    _msuf2ResolveMissingSection = function(id)
        if id == "virtual" then revealed = revealed + 1; return section end
    end }
M.SelectPage = function(key) M.activeKey = key; return true end
M.RuntimeControlCatalog = {
    ResolveExactTarget = function() return nil end,
    FindBySettingKey = function() return nil end,
}
local selected, anchored, exact = M.Search.OpenTarget("zz_navigation", "similar text", "similar text", nil, {},
    { sectionId = "declared" })
Check(selected and anchored and exact, "declared section did not resolve directly")
selected, anchored, exact = M.Search.OpenTarget("zz_navigation", "similar text", "similar text", nil, {},
    { sectionId = "virtual" })
Check(selected and anchored and exact and revealed > 0, "virtual section did not use its exact resolver")
selected, anchored = M.Search.OpenTarget("zz_navigation", "similar text", "similar text", section, {},
    { controlId = "menu2.zz_navigation.stale", sectionId = "declared" })
Check(selected and not anchored, "stale control fell back to section/preferred anchor")
selected, anchored = M.Search.OpenTarget("zz_navigation", "similar text", "similar text", section, {},
    { sectionId = "stale" })
Check(selected and not anchored, "stale section fell back to visible text")
selected, anchored = M.Search.OpenTarget("zz_navigation", "similar text", "similar text", section, {})
Check(selected and not anchored, "page-only FAQ searched for an arbitrary anchor")
world.widgets:RunTimers(10000)
Check(opened > 0, "exact section navigation did not open its own accordion")
M.SelectPage, M.RuntimeControlCatalog = oldSelect, oldCatalog

-- Words a companion adds after the first query apply to the next one: a new
-- alias key, a new stop word, and terms added to an existing key through
-- M.InvalidateSearchLexicon (the lexicon used to be folded once per session).
shown, combat = true, false
Check(#API.SearchPages("qzxlateword") == 0, "late alias word matched before it was added")
M.SearchData.QUERY_ALIASES["qzxlateword"] = { "qzxnavigation" }
Check(#API.SearchPages("qzxlateword") > 0, "an alias key added after the first query was ignored")
Check(#API.SearchPages("qzxnavigation qzxlatestop") == 0, "late stop word ignored before it was added")
M.SearchData.STOP_WORDS["qzxlatestop"] = true
Check(#API.SearchPages("qzxnavigation qzxlatestop") > 0, "a stop word added after the first query was ignored")
Check(#API.SearchPages("qzxpostload") == 0, "late alias term matched before it was added")
M.SearchData.QUERY_ALIASES["qzxpostload"] = { "qzxnothing" }
table.insert(M.SearchData.QUERY_ALIASES["qzxpostload"], "qzxnavigation")
M.InvalidateSearchLexicon()
Check(#API.SearchPages("qzxpostload") > 0, "terms added to an existing alias key were ignored")

-- A widget registered again with only its search prepare contract or its
-- confirmation flag changed refreshes its registry entry: the exact target
-- then prepares the tab the control is on now, not the previous one.
do
    local prepared = { GetScript = function() end, GetParent = function() end }
    local function Register(tab, confirm)
        M.RegisterSearchWidget(prepared, { pageKey = "zz_navigation", label = "Prepared proof slider", kind = "slider",
            classification = "setting", keywords = "qzxprepared", controlId = "menu2.zz_navigation.prepared",
            settingKey = "general.preparedProof", searchPrepareKind = "groupSizingTab", searchPrepareValue = tab,
            confirmRequired = confirm })
    end
    local function Target()
        for _, row in ipairs(API.SearchPages("qzxprepared")) do
            local target = row.exactTarget
            if target and target.controlId == "menu2.zz_navigation.prepared" then return target end
        end
    end
    local function Entry()
        return M.Search._RenderContext.SEARCH_STATE.registry[prepared._msuf2SearchRegistryId]
    end
    Register("tier10")
    local target = Target()
    Check(target and target.prepareValue == "tier10", "the prepared proof row is missing")
    Register("tier20")
    target = Target()
    Check(target and target.prepareValue == "tier20", "a re-registration with a new prepare value kept "
        .. tostring(target and target.prepareValue))
    Register("tier20", true)
    Check(Entry() and Entry().confirmRequired == true, "a re-registration that now asks for confirmation kept the old flag")
end

print("search_navigation_only_smoke: ok (no setters; combat/close discard work; route feature write rejected; exact sections; stale targets fail closed; late lexicon words apply;"
    .. " re-registrations refresh prepare contracts)")
