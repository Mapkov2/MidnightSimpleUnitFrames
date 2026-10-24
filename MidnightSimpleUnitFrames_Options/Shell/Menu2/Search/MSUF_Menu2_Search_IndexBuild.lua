-- Sliced search index construction, query execution and result routing.
local _, MSUF = ...
local Parts = MSUF.SearchIndexParts
local AddPageLocalizedSearchKeywords = Parts.AddPageLocalizedSearchKeywords
local AddRawSearchText = Parts.AddRawSearchText
local AddSearchRecord = Parts.AddSearchRecord
local AddSearchText = Parts.AddSearchText
local AddStaticIndexSearchRecords = Parts.AddStaticIndexSearchRecords
local BuildRegistrySearchRecord = Parts.BuildRegistrySearchRecord
local BuildSearchPageInfos = Parts.BuildSearchPageInfos
local BuildSearchQueryClauses = Parts.BuildSearchQueryClauses
local BuildSearchTokenList = Parts.BuildSearchTokenList
local CONTROL_KIND_LABEL = Parts.CONTROL_KIND_LABEL
local C_Timer = Parts.C_Timer
local CancelSearchBackgroundIndex = Parts.CancelSearchBackgroundIndex
local ClearSearchLocaleCaches = Parts.ClearSearchLocaleCaches
local ClearSearchRegistryPage = Parts.ClearSearchRegistryPage
local ContentHeight = Parts.ContentHeight
local ContentWidth = Parts.ContentWidth
local DASHBOARD_ROUTE_CHANGELOG = Parts.DASHBOARD_ROUTE_CHANGELOG
local DASHBOARD_ROUTE_RECOVERY = Parts.DASHBOARD_ROUTE_RECOVERY
local DASHBOARD_ROUTE_SCALING = Parts.DASHBOARD_ROUTE_SCALING
local EMPTY_SEARCH_RECORDS = Parts.EMPTY_SEARCH_RECORDS
local EnsureSearchLexicon = Parts.EnsureSearchLexicon
local EnsureSearchLocaleFresh = Parts.EnsureSearchLocaleFresh
local IsSearchPageAvailable = Parts.IsSearchPageAvailable
local M = Parts.M
local MIN_SEARCH_QUERY_LEN = Parts.MIN_SEARCH_QUERY_LEN
local MarkSearchIndexDirty = Parts.MarkSearchIndexDirty
local NormalizeSearchText = Parts.NormalizeSearchText
local RefreshSearchPlaceholder = Parts.RefreshSearchPlaceholder
local SEARCH_EASTER_EGGS = Parts.SEARCH_EASTER_EGGS
local SEARCH_FAQ = Parts.SEARCH_FAQ
local SEARCH_INPUT_DEBOUNCE_SEC = Parts.SEARCH_INPUT_DEBOUNCE_SEC
local SEARCH_KEYWORDS = Parts.SEARCH_KEYWORDS
local SEARCH_MAX_RESULTS = Parts.SEARCH_MAX_RESULTS
local SEARCH_MIN_RESULT_SCORE = Parts.SEARCH_MIN_RESULT_SCORE
local SEARCH_STATE = Parts.SEARCH_STATE
local SEARCH_VISIBLE_RESULTS = Parts.SEARCH_VISIBLE_RESULTS
local Search = Parts.Search
local SearchBoxHasText = Parts.SearchBoxHasText
local SearchCharCount = Parts.SearchCharCount
local SearchClauseScore = Parts.SearchClauseScore
local SearchCombatLocked = Parts.SearchCombatLocked
local SearchData = Parts.SearchData
local SearchEditDistanceWithin = Parts.SearchEditDistanceWithin
local SearchGenericLocationBoost = Parts.SearchGenericLocationBoost
local SearchGenericLocationSubjectClauses = Parts.SearchGenericLocationSubjectClauses
local SearchLooksLikeControlQuestion = Parts.SearchLooksLikeControlQuestion
local SearchLooksLikeSupportQuestion = Parts.SearchLooksLikeSupportQuestion
local SearchMenuClosed = Parts.SearchMenuClosed
local SearchNaming = Parts.SearchNaming
local SearchPlaceholderText = Parts.SearchPlaceholderText
local SearchProviders = Parts.SearchProviders
local SearchResultSpecificityBoost = Parts.SearchResultSpecificityBoost
local SearchSupportQuestionBoost = Parts.SearchSupportQuestionBoost
local SearchText = Parts.SearchText
local SearchTokenCharCounts = Parts.SearchTokenCharCounts
local ShortLabel = Parts.ShortLabel
local T = Parts.T
local TrimText = Parts.TrimText
local UpdateSearchPlaceholder = Parts.UpdateSearchPlaceholder
local W = Parts.W
local SearchIndexBuild = { SLICE_MS = 1 }
function SearchIndexBuild.Due(deadline)
    return deadline ~= nil and debugprofilestop() >= deadline
end

--- Runtime search providers. An optional companion addon owns pages this layer
--- has no static rows for; it registers one function that returns plain rows
--- (M.RegisterSearchProvider). The rows become records shaped like the static
--- index records the first time the index is built after a registration or a
--- menu language change, and every later rebuild reuses them. No provider, no
--- work: nothing here runs per query, and the index build skips it entirely.
---
--- Row fields; a row with a wrong type or an unknown page is skipped:
---   pageKey     required, a page registered through M.RegisterPage
---   kind        "page", "faq", "section", "toggle", "dropdown", "segment",
---               "slider", "color", "button", "textinput" or "control" (default)
---   label       required except on page rows: translated display text
---   section     section title; the breadcrumb is "<nav group> > <page> > <section>"
---   hint        whole breadcrumb replacing the default
---   keywords    extra search words: a list of strings or one "a|b|c" string
---   help        searchable text, shown as the result's answer
---   settingKey  exact target: the control registered with this setting key
---   controlId   exact runtime control ID; also locates actions without running them
---   sectionId   accordion (b:CollapsibleSection id) opened on the way there
---   anchorText  page words that steer the route (sections, selections) when
---               there is no exact control; search never scrolls to text
--- A page row adds its keywords to the page's own record, help becomes the
--- page's answer and hint its breadcrumb. A faq row is a question (label) with
--- its answer (help) that opens pageKey, ranked like the built-in FAQ.
--- Page words reach a provider record through its breadcrumb and haystack but
--- never as a title match, so a query naming a page still ranks that page first.
function SearchIndexBuild.New()
    local pageInfos, pageInfoByKey = BuildSearchPageInfos()
    SEARCH_STATE.pageNames = SearchNaming.BuildPageNames(pageInfos)
    return { phase = 1, index = 1, records = {}, seenRecords = {}, covered = {},
        pageInfos = pageInfos, pageInfoByKey = pageInfoByKey, registryPageInfos = {} }
end

--- Each phase returns true when it is complete; false keeps job.index for the
--- next slice. Without a deadline every phase runs to its end.
SearchIndexBuild.PHASES = {
    -- Providers first: their page rows add to the page records.
    function(job, deadline)
        job.provided = next(SEARCH_STATE.providers) ~= nil and SearchProviders.Collect(job.pageInfoByKey, job, deadline) or nil
        return job.collect == nil
    end,
    function(job, deadline)
        local records, seenRecords, provided = job.records, job.seenRecords, job.provided
        for i = job.index, #job.pageInfos do
            local info = job.pageInfos[i]
            local pageParts = {}
            AddSearchText(pageParts, info.group)
            AddSearchText(pageParts, info.title)
            AddRawSearchText(pageParts, SEARCH_KEYWORDS[info.key])
            AddPageLocalizedSearchKeywords(pageParts, info.key)
            local extra = provided and provided.pages[info.key]
            for k = 1, #(extra and extra.parts or EMPTY_SEARCH_RECORDS) do pageParts[#pageParts + 1] = extra.parts[k] end
            local rec = AddSearchRecord(records, seenRecords, info, info.label or info.title or info.key, nil, "page", pageParts)
            if rec and extra then
                rec.answer = extra.answer
                if extra.hint then rec.hint, rec.hintNorm = extra.hint, NormalizeSearchText(extra.hint) end
            end
            if deadline and SearchIndexBuild.Due(deadline) then
                job.index = i + 1
                return false
            end
        end
        return true
    end,
    -- Live widgets, in the registry's own iteration order.
    function(job, deadline)
        local entries = job.entries
        if not entries then
            entries = {}
            for _, entry in pairs(SEARCH_STATE.registry) do entries[#entries + 1] = entry end
            job.entries = entries
        end
        local records, covered = job.records, job.covered
        for i = job.index, #entries do
            local entry = entries[i]
            local rec = SEARCH_STATE.registryRecords[entry.id]
            if not rec and BuildRegistrySearchRecord then
                rec = BuildRegistrySearchRecord(entry, job.registryPageInfos)
                SEARCH_STATE.registryRecords[entry.id] = rec
            end
            if rec then
                rec.order = #records + 1
                records[#records + 1] = rec
                covered[rec.searchIdentity] = true
            end
            if deadline and SearchIndexBuild.Due(deadline) then
                job.index = i + 1
                return false
            end
        end
        job.registryPageInfos = nil
        return true
    end,
    -- The static decode is sliced; the row loop is one short step.
    function(job, deadline)
        local staticIndex = Search.StaticIndex
        if deadline and staticIndex and staticIndex.Advance and not staticIndex.Advance(deadline) then return false end
        return AddStaticIndexSearchRecords(job, deadline)
    end,
    function(job)
        if job.provided then SearchProviders.Append(job.records, job.provided) end
        return true
    end,
    function(job, deadline)
        local records, seenRecords = job.records, job.seenRecords
        for i = job.index, #SEARCH_FAQ do
            local faq = SEARCH_FAQ[i]
            local pageKey = faq.pageKey or "home"
            local info = job.pageInfoByKey[pageKey] or { key = pageKey, label = "FAQ", title = "FAQ", group = "" }
            local extra = { faq.answer, faq.target, faq.anchorText }
            for k = 1, #(faq.keywords or {}) do extra[#extra + 1] = faq.keywords[k] end
            local rec = AddSearchRecord(records, seenRecords, info, faq.label, nil, "faq", extra)
            if rec then
                rec.answer = faq.answer
                rec.target = faq.target
                rec.anchorFallback = faq.anchorText or faq.label
                rec.route = faq.route
                rec.priority = tonumber(faq.priority) or 0
                rec.faq = true
            end
            if deadline and SearchIndexBuild.Due(deadline) then
                job.index = i + 1
                return false
            end
        end
        return true
    end,
    function(job)
        for i = 1, #SEARCH_EASTER_EGGS do
            local egg = SEARCH_EASTER_EGGS[i]
            local info = { key = "search", label = "", title = "", group = "" }
            -- Found by its name only: its answer text holds ordinary words ("spells", "bind"),
            -- and with its priority it would push every real result below the curation floor.
            local rec = AddSearchRecord(job.records, job.seenRecords, info, egg.name, nil, "easteregg", { egg.name })
            if rec then
                rec.answer = egg.result
                rec.noOpen = true
                rec.priority = 1200
                rec.easterEgg = true
            end
        end
        return true
    end,
    function(job, deadline)
        return SearchProviders.FilterAvailable(job.records, job, deadline)
    end,
}

--- Runs phases until the job is done (true) or the deadline passes (false).
function SearchIndexBuild.Step(job, deadline)
    local phases = SearchIndexBuild.PHASES
    while job.phase <= #phases do
        if not phases[job.phase](job, deadline) then return false end
        job.phase, job.index = job.phase + 1, 1
        if job.phase <= #phases and SearchIndexBuild.Due(deadline) then return false end
    end
    return true
end

local SearchPages, SetSearchResults, RunSearchInputQuery, ScheduleSearchInputQuery

local function RefreshSearchResultsPage()
    if M.activeKey ~= "search" or SearchMenuClosed() then return end
    -- SearchPages already returns nothing in combat, but the refresh below still
    -- invalidated and rebuilt the search page. Stop before any of that runs.
    if SearchCombatLocked() then return end
    local query = TrimText(M.searchQuery or "")
    if query == "" or SearchText.QueryLength(query) < MIN_SEARCH_QUERY_LEN then return end
    SetSearchResults(SearchPages(query), query)
    -- The results page repaints in place (Search_Render); it is never rebuilt.
    Search._Render.ShowSearchPage()
end

-- The background indexer used to build every unvisited page just to register its
-- widgets. The generated static index supersedes it, so search no longer has any
-- path that constructs frames, runs on a timer, or touches the DB per query.
-- CancelSearchBackgroundIndex stays: menu chrome still calls it on close/hide.

local function RefreshProviderContexts()
    for _, provider in pairs(SEARCH_STATE.providers) do
        if provider.contextChanged and provider.contextChanged() == true then
            SEARCH_STATE.providerCache = nil
            MarkSearchIndexDirty()
        end
    end
end

local function GetSearchRecords()
    -- Combat does no search work at all. Everything below this line either builds
    -- UI (the deferred section pump) or rebuilds/decodes the index, so the gate has
    -- to sit above it rather than relying on every caller checking first.
    if SearchCombatLocked() or SearchMenuClosed() then return EMPTY_SEARCH_RECORDS end
    EnsureSearchLocaleFresh()
    RefreshProviderContexts()
    -- Lexicon invalidation clears recordsReady before any subsequent query.
    if not SEARCH_STATE.records or SEARCH_STATE.recordsDirty or not SEARCH_STATE.recordsReady then
        SearchIndexBuild.Queue()
        return EMPTY_SEARCH_RECORDS
    end
    return SEARCH_STATE.records
end

--- Fuzzy matching tokenizes a record on its first fuzzy probe; the first query
--- after a build probes nearly every record. The sliced path does that work
--- ahead, exactly as SearchFuzzyTokenMatch would, so that query runs at
--- keystroke cost.
function SearchIndexBuild.WarmTokens(job, deadline)
    local generation = SEARCH_STATE.lexiconGeneration
    local records = job.records
    for i = job.index, #records do
        local rec = records[i]
        if not rec.tokens or rec.tokensLexicon ~= generation then
            rec.tokens, rec.tokensLexicon = BuildSearchTokenList(rec.haystack or "", rec.tokenLimit), generation
        end
        SearchTokenCharCounts(rec, rec.tokens)
        if deadline and SearchIndexBuild.Due(deadline) then
            job.index = i + 1
            return false
        end
    end
    job.warm = generation
    return true
end

--- One slice for the debounced input path, from a menu task only (never in
--- combat; quiescing the menu drops the job): true once the records are current
--- and warm, false when the next frame has to continue.
function SearchIndexBuild.Advance(deadline)
    EnsureSearchLocaleFresh()
    local job = SEARCH_STATE.indexQueue
    if job and job.serial ~= SEARCH_STATE.dirtySerial then job = nil end
    -- Provider contexts are asked when a job starts and again before its records
    -- are installed; a change in between restarts the job (see below).
    if not job then
        RefreshProviderContexts()
        job = SEARCH_STATE.indexQueue
        if job and job.serial ~= SEARCH_STATE.dirtySerial then job = nil end
    end
    deadline = deadline or (debugprofilestop() + SearchIndexBuild.SLICE_MS)
    if not SEARCH_STATE.records or SEARCH_STATE.recordsDirty then
        if not (job and job.phase <= #SearchIndexBuild.PHASES) then job = SearchIndexBuild.New() end
        SEARCH_STATE.indexQueue = job
        if not SearchIndexBuild.Step(job, deadline) then
            job.serial = SEARCH_STATE.dirtySerial
            return false
        end
        local serial = SEARCH_STATE.dirtySerial
        RefreshProviderContexts()
        if SEARCH_STATE.dirtySerial ~= serial then
            SEARCH_STATE.indexQueue = nil
            return false
        end
        SEARCH_STATE.records, SEARCH_STATE.recordsDirty = job.records, false
    elseif not job or job.records ~= SEARCH_STATE.records then
        job = { records = SEARCH_STATE.records, index = 1, phase = #SearchIndexBuild.PHASES + 1 }
        SEARCH_STATE.indexQueue = job
    end
    if SearchIndexBuild.Due(deadline) or not EnsureSearchLexicon(deadline)
        or not SearchData.AdvanceNaturalQueryLexicon(deadline) then
        job.serial = SEARCH_STATE.dirtySerial
        return false
    end
    if job.warm ~= SEARCH_STATE.lexiconGeneration and not SearchIndexBuild.WarmTokens(job, deadline) then
        job.serial = SEARCH_STATE.dirtySerial
        return false
    end
    job.serial = SEARCH_STATE.dirtySerial
    SEARCH_STATE.recordsReady = true
    return true
end

function SearchIndexBuild.Pump()
    SEARCH_STATE.sliceTask = nil
    SEARCH_STATE.sliceQueued = nil
    if SearchCombatLocked() or SearchMenuClosed() then CancelSearchBackgroundIndex() return end
    local deadline = debugprofilestop() + SearchIndexBuild.SLICE_MS
    if not SearchIndexBuild.Advance(deadline) then SearchIndexBuild.Queue() return end
    local callbacks = SEARCH_STATE.readyCallbacks
    SEARCH_STATE.readyCallbacks = nil
    for i = 1, #(callbacks or EMPTY_SEARCH_RECORDS) do callbacks[i]() end
    local request = SEARCH_STATE.request
    if not request or not request.debounced or request.serial ~= SEARCH_STATE.inputSerial then return end
    if request.box and TrimText(request.box:GetText() or "") ~= request.query then return end
    if SearchIndexBuild.Due(deadline) then SearchIndexBuild.Queue() return end
    local queryJob = request.job
    if queryJob and (queryJob.serial ~= SEARCH_STATE.dirtySerial or queryJob.records ~= SEARCH_STATE.records
        or queryJob.lexicon ~= SEARCH_STATE.lexiconGeneration) then request.job = nil end
    request.job = request.job or { index = 1, results = {}, fuzzy = {}, serial = SEARCH_STATE.dirtySerial,
        records = SEARCH_STATE.records, lexicon = SEARCH_STATE.lexiconGeneration, sourcePage = request.sourcePage }
    local results = SearchPages(request.query, request.job, deadline)
    if not results then SearchIndexBuild.Queue() return end
    SEARCH_STATE.request = nil
    M.searchQuery, M.searchResultsPending = request.query, nil
    SetSearchResults(results, request.query)
    request.job = nil
    if request.openPage or M.activeKey == "search" then Search._Render.ShowSearchPage() end
    if request.onComplete then request.onComplete(request.query) end
end
function SearchIndexBuild.Queue()
    if SEARCH_STATE.sliceQueued then return end
    SEARCH_STATE.sliceQueued = true
    SEARCH_STATE.sliceTask = C_Timer.After(0, SearchIndexBuild.Pump)
end

local function CurateSearchResults(results, supportQuestion)
    -- An exact query target is pinned on top by its bonus; the floor comes
    -- from the best other result, so that bonus never empties the list.
    local topScore = 0
    for i = 1, #results do
        if not results[i].exactQueryHit then
            topScore = tonumber(results[i].score) or 0
            break
        end
    end
    local floorScore = SEARCH_MIN_RESULT_SCORE
    if topScore >= 600 then
        floorScore = math.max(floorScore, topScore * (supportQuestion and 0.70 or 0.42))
    elseif topScore >= 300 then
        floorScore = math.max(floorScore, topScore * 0.30)
    end

    local function SpecificControlMatch(rec)
        local clauseCount = tonumber(rec and rec.queryClauseCount) or 0
        if clauseCount < 2 then return false end
        if rec.kind == "page" or rec.kind == "faq" or rec.kind == "easteregg" then return false end
        return (tonumber(rec.missedClauses) or 0) == 0 and (tonumber(rec.matchedClauses) or 0) == clauseCount
    end

    local curated = {}
    for i = 1, #results do
        local rec = results[i]
        if rec and (rec.exactQueryHit or (tonumber(rec.score) or 0) >= floorScore or SpecificControlMatch(rec)) then
            curated[#curated + 1] = rec
            if #curated >= SEARCH_MAX_RESULTS then break end
        end
    end
    return curated
end

local exactQueryTargets
local function ExactQueryTarget(normalized)
    if not exactQueryTargets then
        exactQueryTargets = {}
        for phrase, target in pairs(SearchData.CONTROL_QUERY_TARGETS or {}) do
            exactQueryTargets[NormalizeSearchText(phrase)] = target
        end
    end
    return exactQueryTargets[normalized] or SearchData.NaturalQueryTarget(normalized)
end
local function MatchesExactQueryTarget(rec, target)
    if not target then return false end
    if target.pageKey and rec.key ~= target.pageKey then return false end
    if target.pageKey and not target.controlSuffix then return rec.kind == "page" end
    local field = Search.StaticIndex.TargetField
    if target.settingKey then return field(rec, "settingKey") == target.settingKey end
    if target.settingSuffix then
        local key = tostring(field(rec, "settingKey") or "")
        return key:sub(-#target.settingSuffix) == target.settingSuffix
    end
    local id = tostring(field(rec, "controlId") or "")
    return (target.pageKey or rec.key == "profiles") and target.controlSuffix and id:find(target.controlSuffix, 1, true) ~= nil
end

function SearchIndexBuild.QueryContext(query)
    -- Raw setting keys ("gf_party.hpTextMode") reach search from exports and
    -- support references. The baked index is pre-normalized without camelCase
    -- tokens, and the scope prefix names the provider rather than the control,
    -- so its tokens ("party") never appear in a page haystack. Drop the prefix
    -- and split the remaining camelCase into words. Only single-token queries
    -- shaped like a key are touched; typed text never is.
    if not query:find("%s") and ((query:find("^[a-z]") and query:find("%l%u")) or query:find("%.")) then
        local stripped = query:gsub("^[%w_]+%.", "")
        if stripped ~= "" then query = stripped end
        query = query:gsub("(%l)(%u)", "%1 %2")
    end
    local normalized, clauses = BuildSearchQueryClauses(query)
    if #clauses == 0 then return { empty = true } end
    if SearchCharCount(normalized) < MIN_SEARCH_QUERY_LEN then return { empty = true } end

    local exactQueryTarget = ExactQueryTarget(normalized)
    local supportQuestion = SearchLooksLikeSupportQuestion(query, normalized)
    local genericLocationSubject, genericLocationClauses = SearchGenericLocationSubjectClauses(query, normalized)
    local genericLocationQuestion = genericLocationSubject ~= nil and genericLocationClauses ~= nil
    local controlQuestion = SearchLooksLikeControlQuestion(query, normalized) or genericLocationQuestion
    local profileTransferQuestion = normalized:find("import", 1, true)
        or normalized:find("export", 1, true)
        or normalized:find("profile string", 1, true)
    local wagoBrowseQuestion = (normalized:find("wago", 1, true) and normalized:find("profile", 1, true))
        or normalized:find("browse wago", 1, true)
        or normalized:find("wago hub", 1, true)
    if profileTransferQuestion then wagoBrowseQuestion = false end
    local requiredMatches = #clauses
    if supportQuestion and #clauses > 3 then
        requiredMatches = math.max(2, math.ceil(#clauses * 0.55))
    end
    return { normalized = normalized, clauses = clauses, exactQueryTarget = exactQueryTarget,
        supportQuestion = supportQuestion, genericLocationClauses = genericLocationClauses,
        genericLocationQuestion = genericLocationQuestion, controlQuestion = controlQuestion,
        profileTransferQuestion = profileTransferQuestion, wagoBrowseQuestion = wagoBrowseQuestion,
        requiredMatches = requiredMatches }
end

function SearchPages(query, job, deadline)
    query = TrimText(query)
    if SearchCombatLocked() or SearchMenuClosed() then
        CancelSearchBackgroundIndex()
        return EMPTY_SEARCH_RECORDS
    end
    if SearchText.QueryLength(query) < MIN_SEARCH_QUERY_LEN then return EMPTY_SEARCH_RECORDS end
    local records = GetSearchRecords()
    if SEARCH_STATE.recordsDirty or not SEARCH_STATE.records or not SEARCH_STATE.recordsReady then
        if not SEARCH_STATE.request then ScheduleSearchInputQuery(nil, query, false) end
        if job then return nil end
        return EMPTY_SEARCH_RECORDS
    end
    local context = job and job.context
    if not context then
        context = SearchIndexBuild.QueryContext(query)
        if job then job.context = context return nil end
    end
    if context.empty then return EMPTY_SEARCH_RECORDS end
    local normalized, clauses, exactQueryTarget = context.normalized, context.clauses, context.exactQueryTarget
    local supportQuestion, genericLocationClauses = context.supportQuestion, context.genericLocationClauses
    local genericLocationQuestion, controlQuestion = context.genericLocationQuestion, context.controlQuestion
    local profileTransferQuestion, wagoBrowseQuestion = context.profileTransferQuestion, context.wagoBrowseQuestion
    local requiredMatches = context.requiredMatches
    local results = job and job.results or {}
    local namedPageKey = SearchNaming.Page(normalized)
    local fuzzyDistanceCache = job and job.fuzzy or {}
    -- The page the user searched from ranks first. While results show, the
    -- active page is the search page itself and that page is searchReturnKey.
    local currentPageKey = job and job.sourcePage or (M.activeKey == "search" and M.searchReturnKey or M.activeKey)
    if currentPageKey == "home" or currentPageKey == "search" then currentPageKey = nil end
    for i = job and job.index or 1, #records do
        local rec = records[i]
        local score = 0
        local matched = true
        local matchedClauses = 0
        local missedClauses = 0
        for c = 1, #clauses do
            local ok, clauseScore = SearchClauseScore(rec, clauses[c], fuzzyDistanceCache)
            if not ok then
                missedClauses = missedClauses + 1
                if requiredMatches == #clauses or (#clauses - missedClauses) < requiredMatches then
                    matched = false
                    break
                end
            else
                matchedClauses = matchedClauses + 1
                score = score + clauseScore
            end
        end
        local exactQueryHit = MatchesExactQueryTarget(rec, exactQueryTarget)
        if exactQueryHit then
            matched, matchedClauses, missedClauses = true, #clauses, 0
            score = score + 5000
        elseif not matched and rec.labelNorm == normalized then
            -- Typing a record's exact shown name always finds it, whatever the
            -- clause parser made of its words ("interrupt is ready", "Where are ...?").
            matched, matchedClauses, missedClauses = true, #clauses, 0
        end
        if matched and matchedClauses >= requiredMatches then
            if rec.labelNorm == normalized or rec.titleNorm == normalized then
                -- SearchClauseScore pays an exact/prefix label bonus per clause, so a
                -- short label that nails one clause accumulates more than a record
                -- whose entire label is the query. "Status indicator size" lost every
                -- slot to sliders simply labelled "Size" on the same page. A whole
                -- label match has to scale with the clause count to stay ahead.
                score = score + 260 + 220 * #clauses
            end
            if rec.labelNorm:find(normalized, 1, true) == 1 then score = score + 130 end
            local labelNamed = rec.labelNorm == normalized or SearchNaming.Label(rec, normalized)
            if labelNamed and rec.labelNorm ~= normalized then score = score + 260 + 120 * #clauses end
            if rec.haystack and rec.haystack:find(normalized, 1, true) then score = score + 80 end
            if rec.kind == "section" then score = score + 70 end
            if rec.kind == "faq" then score = score + 55 end
            if supportQuestion and not genericLocationQuestion then score = score + SearchSupportQuestionBoost(rec, clauses) end
            if genericLocationQuestion then score = score + SearchGenericLocationBoost(rec, genericLocationClauses, matchedClauses, missedClauses) end
            score = score + SearchResultSpecificityBoost(rec, clauses)
            if missedClauses > 0 then score = score - (missedClauses * 60) end
            if rec.kind ~= "page" then score = score + 45 end
            if currentPageKey and rec.key == currentPageKey then score = score + 120 end
            if namedPageKey and rec.key == namedPageKey then score = score + 150 end
            if rec.kind == "slider" or rec.kind == "dropdown" or rec.kind == "toggle" then score = score + 25 end
            -- A record whose exact name was typed (a section, an FAQ question) keeps up with
            -- the controls this boost lifts, however few clauses its words left.
            if controlQuestion and (rec.labelNorm == normalized
                or ((rec.kind == "toggle" or rec.kind == "dropdown" or rec.kind == "slider" or rec.kind == "segment"
                    or rec.kind == "textinput" or rec.kind == "color" or (rec.kind == "button" and labelNamed))
                and #clauses >= 2 and missedClauses == 0 and matchedClauses == #clauses)) then
                score = score + 1300
            end
            if rec.priority then score = score + rec.priority end
            if profileTransferQuestion then
                if rec.key == "profiles" then score = score + 520 end
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score - 520 end
            elseif wagoBrowseQuestion then
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score + 720 end
                if rec.key == "profiles" and rec.kind == "page" then score = score - 180 end
            end
            rec.score = score
            rec.exactQueryHit = exactQueryHit
            rec.matchedClauses = matchedClauses
            rec.missedClauses = missedClauses
            rec.queryClauseCount = #clauses
            results[#results + 1] = rec
        end
        if deadline and SearchIndexBuild.Due(deadline) then job.index = i + 1 return nil end
    end
    if job and not job.sortReady then job.sortReady, job.index = true, #records + 1 return nil end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.hint or "") ~= (b.hint or "") then return tostring(a.hint or "") < tostring(b.hint or "") end
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
        return tostring(a.label) < tostring(b.label)
    end)
    return CurateSearchResults(results, supportQuestion and not genericLocationQuestion)
end

SetSearchResults = function(results, query)
    M.searchResults = results or {}
    M.searchResultsQuery = query or ""
end

local function ShowSearchPageForQuery(query)
    query = TrimText(query)
    if query ~= "" and M.activeKey ~= "search" then
        M.searchReturnKey = M.activeKey or M.searchReturnKey or "home"
    end
    if query ~= "" then
        Search._Render.ShowSearchPage()
    elseif M.activeKey == "search" then
        M.SelectPage(M.searchReturnKey or "home")
    end
end

RunSearchInputQuery = function(query, openPage)
    if SearchCombatLocked() or SearchMenuClosed() then
        CancelSearchBackgroundIndex()
        return
    end
    query = TrimText(query)
    M.searchQuery = query
    M.searchResultsPending = nil

    if query == "" then
        SetSearchResults(nil, "")
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    if SearchText.QueryLength(query) < MIN_SEARCH_QUERY_LEN then
        SetSearchResults(nil, query)
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    ScheduleSearchInputQuery(nil, query, openPage)
end

ScheduleSearchInputQuery = function(searchBox, query, openPage, onComplete)
    if SearchCombatLocked() or SearchMenuClosed() then
        CancelSearchBackgroundIndex()
        return
    end
    query = TrimText(query)
    openPage = openPage == true
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    local serial = SEARCH_STATE.inputSerial

    M.searchQuery = query

    if query == "" or SearchCombatLocked() or SearchText.QueryLength(query) < MIN_SEARCH_QUERY_LEN then
        RunSearchInputQuery(query, openPage)
        if type(onComplete) == "function" then onComplete(query) end
        return
    end

    local sourcePage = M.activeKey == "search" and M.searchReturnKey or M.activeKey
    M.searchResultsPending = true
    M.searchResults = {}
    M.searchResultsQuery = query
    if openPage and M.activeKey ~= "search" then
        M.searchResults = {}
        ShowSearchPageForQuery(query)
    end

    local request = { serial = serial, query = query, openPage = openPage, box = searchBox, onComplete = onComplete, sourcePage = sourcePage }
    SEARCH_STATE.request = request
    SearchIndexBuild.Queue()
    C_Timer.After(SEARCH_INPUT_DEBOUNCE_SEC, function()
        if SEARCH_STATE.request ~= request or serial ~= SEARCH_STATE.inputSerial then return end
        request.debounced = true
        SearchIndexBuild.Queue()
    end)
end

local function OpenSearchResults(query)
    ScheduleSearchInputQuery(nil, query, true)
end

Search._RoutingContext = {
    M = M,
    NormalizeSearchText = NormalizeSearchText,
    BuildSearchQueryClauses = BuildSearchQueryClauses,
    BuildSearchTokenList = BuildSearchTokenList,
    SearchEditDistanceWithin = SearchEditDistanceWithin,
    SearchCombatLocked = SearchCombatLocked,
    ContentWidth = ContentWidth,
    ContentHeight = ContentHeight,
    DASHBOARD_ROUTE_RECOVERY = DASHBOARD_ROUTE_RECOVERY,
    DASHBOARD_ROUTE_SCALING = DASHBOARD_ROUTE_SCALING,
    DASHBOARD_ROUTE_CHANGELOG = DASHBOARD_ROUTE_CHANGELOG,
}

local function OpenSearchTarget(...)
    local routing = Search._RoutingAPI
    if routing and routing.OpenSearchTarget then return routing.OpenSearchTarget(...) end
end

Search._RenderContext = {
    M = M,
    W = W,
    T = T,
    TrimText = TrimText,
    SearchCombatLocked = SearchCombatLocked,
    NormalizeSearchText = NormalizeSearchText,
    MIN_SEARCH_QUERY_LEN = MIN_SEARCH_QUERY_LEN,
    QueryLength = SearchText.QueryLength,
    SearchPages = SearchPages,
    SEARCH_STATE = SEARCH_STATE,
    SEARCH_VISIBLE_RESULTS = SEARCH_VISIBLE_RESULTS,
    CONTROL_KIND_LABEL = CONTROL_KIND_LABEL,
    ShortLabel = ShortLabel,
    OpenSearchTarget = OpenSearchTarget,
    OpenSearchResults = OpenSearchResults,
    ContentHeight = ContentHeight,
}

Search._CoreAPI = {
    BumpSearchInputSerial = function()
        SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    end,
    CancelSearchBackgroundIndex = CancelSearchBackgroundIndex,
    ClearSearchLocaleCaches = ClearSearchLocaleCaches,
    ClearSearchRegistryPage = ClearSearchRegistryPage,
    MarkSearchIndexDirty = MarkSearchIndexDirty,
    OpenSearchResults = OpenSearchResults,
    OpenSearchTarget = OpenSearchTarget,
    RefreshSearchResultsPage = RefreshSearchResultsPage,
    RefreshSearchPlaceholder = RefreshSearchPlaceholder,
    RunSearchInputQuery = RunSearchInputQuery,
    ScheduleSearchInputQuery = ScheduleSearchInputQuery,
    SearchBoxHasText = SearchBoxHasText,
    SearchPages = SearchPages,
    GetSearchRecords = GetSearchRecords,
    WhenIndexReady = function(callback)
        if SearchCombatLocked() or SearchMenuClosed() then return false end
        if SEARCH_STATE.recordsReady and not SEARCH_STATE.recordsDirty then callback() return true end
        local callbacks = SEARCH_STATE.readyCallbacks or {}
        SEARCH_STATE.readyCallbacks = callbacks
        callbacks[#callbacks + 1] = callback
        SearchIndexBuild.Queue()
        return true
    end,
    IsSearchPageAvailable = IsSearchPageAvailable,
    GetFAQRecords = function() return SEARCH_FAQ end,
    GetSearchProviderCache = function() return SEARCH_STATE.providerCache end,
    SearchPlaceholderText = SearchPlaceholderText,
    ShortLabel = ShortLabel,
    TrimText = TrimText,
    UpdateSearchPlaceholder = UpdateSearchPlaceholder,
}
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF2_Menu2_Search", function()
        SEARCH_STATE.localeKey = nil
        ClearSearchLocaleCaches()
        CancelSearchBackgroundIndex()
        MarkSearchIndexDirty()
        if M.activeKey == "search" then RefreshSearchResultsPage() end
    end)
end

M.MenuRuntime:SetQuiesceSettler("search-cache", function()
    CancelSearchBackgroundIndex()
    ClearSearchLocaleCaches()
    SEARCH_STATE.records, SEARCH_STATE.pageNames = nil, nil
    SEARCH_STATE.searchableText, SEARCH_STATE.searchableTextCount = {}, 0
    SEARCH_STATE.aliasTypoCache, SEARCH_STATE.aliasTypoCount = {}, 0
    SEARCH_STATE.aliasTypoKeys, SEARCH_STATE.aliasTypoKeyLengths = nil, nil
    M.searchResults, M.searchResultsQuery = nil, nil
    SearchProviders.ReleaseStaticRows()
    SearchText.ReleaseQueryCaches()
    SEARCH_STATE.multiWordAliases, SEARCH_STATE.queryCompounds = nil, nil
    SearchData.ClearNaturalQueryCache()
    Search.StaticIndex.ClearCache()
    if Search._Render then Search._Render.ReleaseResults() end
    MarkSearchIndexDirty()
end)

Parts.SearchIndexBuild = SearchIndexBuild

-- Complete forward bindings once; gameplay closures keep direct local calls.
Parts.Bind3()
MSUF.SearchIndexParts = nil
