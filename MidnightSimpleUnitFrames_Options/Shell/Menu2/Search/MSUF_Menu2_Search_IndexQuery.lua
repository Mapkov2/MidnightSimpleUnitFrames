-- Search state, invalidation and shared limits.
--- Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua
--- Cold-path search indexing, query scoring, target routing, and navigation.
---
--- Owns: search registry, background index construction, query matching,
--- route resolution, and anchor scrolling. Result UI rendering lives in
--- MSUF_Menu2_Search_Render.lua; public wrappers live in Search_API.lua.
local MSUF = select(2, ...)
local Parts = {}
MSUF.SearchIndexParts = Parts
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

local T = M.Theme
local W = M.Widgets
local Search = M.Search or {}
M.Search = Search
local SearchData = M.SearchData or {}
local NAV_ITEMS = M.navItems or {}


local byte = string.byte

local SearchText = Search.Text or {}
local ContentWidth, ContentHeight, TrimText, ShortLabel = SearchText.ContentWidth, SearchText.ContentHeight, SearchText.TrimText, SearchText.ShortLabel
local SearchPlaceholderText, SearchBoxHasText = SearchText.SearchPlaceholderText, SearchText.SearchBoxHasText
local RefreshSearchPlaceholder, UpdateSearchPlaceholder = SearchText.RefreshSearchPlaceholder, SearchText.UpdateSearchPlaceholder
local NormalizeSearchText, DisplaySearchText = SearchText.NormalizeSearchText, SearchText.DisplaySearchText
local SearchEffectiveLocale, SearchDisplayText, AddSearchText = SearchText.SearchEffectiveLocale, SearchText.SearchDisplayText, SearchText.AddSearchText
local AddRawSearchText, AddToggleQuestionSearchText = SearchText.AddRawSearchText, SearchText.AddToggleQuestionSearchText
local AddControlQuestionSearchText = SearchText.AddControlQuestionSearchText
local SEARCH_KEYWORDS = SearchText.KEYWORDS or SearchData.KEYWORDS or {}

local MIN_SEARCH_QUERY_LEN = 2
local SEARCH_TEXT_MAX_LEN = 170
local SEARCH_INPUT_DEBOUNCE_SEC = 0.10
local SEARCH_MAX_RESULTS = 24
local SEARCH_VISIBLE_RESULTS = 12
local SEARCH_MIN_RESULT_SCORE = 40
local SEARCH_MAX_RAW_WORDS = 12
local SEARCH_MAX_QUERY_CLAUSES = 8
local SEARCH_MAX_TERMS_PER_CLAUSE = 18
local SEARCH_MAX_RECORD_TOKENS = 90
local SEARCH_CONTROL_MAX_TOKENS = 36
local SEARCH_CONTROL_HAYSTACK_MAX_LEN = 1200
-- Shared empty result, so a combat-gated read never allocates.
local EMPTY_SEARCH_RECORDS = {}
local SEARCH_STATE = {
    records = nil,
    recordsDirty = true,
    -- Bumped by every invalidation; a sliced index build resumes only while
    -- nothing outside its own slices changed it.
    dirtySerial = 0,
    indexing = false,
    indexQueue = nil,
    inputSerial = 0,
    registrySerial = 0,
    aliasTypoKeys = nil,
    aliasTypoCache = {},
    queryClauseCacheNorm = nil,
    queryClauseCacheClauses = nil,
    registry = {},
    registryByPage = {},
    registryRecords = {},
    -- Page-list index of the last id a page move removed (a lookup hint).
    registryMoveAt = nil,
    -- IsSearchableDisplayText answers by source string (bounded).
    searchableText = {},
    searchableTextCount = 0,
    localeKey = nil,
    -- Runtime search providers (M.RegisterSearchProvider) by name, and their
    -- records, built on first use and dropped with the locale caches.
    providers = {},
    providerCache = nil,
    availability = {},
}
M.searchRegistry = SEARCH_STATE.registry

local function MarkSearchIndexDirty()
    SEARCH_STATE.recordsDirty = true
    SEARCH_STATE.recordsReady = false
    SEARCH_STATE.dirtySerial = SEARCH_STATE.dirtySerial + 1
end

local function ClearSearchLocaleCaches()
    if SearchText.ClearLocaleCaches then SearchText.ClearLocaleCaches() end
    SEARCH_STATE.queryClauseCacheNorm = nil
    SEARCH_STATE.queryClauseCacheClauses = nil
    SEARCH_STATE.registryRecords = {}
    SEARCH_STATE.providerCache = nil
    SEARCH_STATE.dirtySerial = SEARCH_STATE.dirtySerial + 1
end

local function EnsureSearchLocaleFresh()
    -- SearchEffectiveLocale returns MSUF.LOCALE whenever it is a non-empty
    -- string, and a stored key is always one, so a match needs no call.
    if SEARCH_STATE.localeKey ~= nil and MSUF.LOCALE == SEARCH_STATE.localeKey then return end
    local localeKey = SearchEffectiveLocale()
    if SEARCH_STATE.localeKey == localeKey then return end
    SEARCH_STATE.localeKey = localeKey
    ClearSearchLocaleCaches()
    MarkSearchIndexDirty()
end

local function SearchCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function SearchMenuClosed()
    return not (M.frame and M.frame.IsShown and M.frame:IsShown())
end

local function CancelSearchBackgroundIndex()
    if SEARCH_STATE.sliceTask then SEARCH_STATE.sliceTask:Cancel() end
    SEARCH_STATE.sliceTask = nil
    if SEARCH_STATE.request then SEARCH_STATE.request.job = nil end
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    -- A search cut off before it ran left an empty list labelled with its query.
    -- Forget the label, so the next paint searches again instead of showing
    -- "no match" for a query nobody answered.
    if M.searchResultsPending then M.searchResultsQuery = nil end
    M.searchResultsPending = nil
    SEARCH_STATE.indexing = false
    SEARCH_STATE.indexQueue = nil
    SEARCH_STATE.request, SEARCH_STATE.sliceQueued, SEARCH_STATE.readyCallbacks = nil, nil, nil
end

local SEARCH_NOISE_TEXT, SEARCH_STOP_WORDS = SearchData.NOISE_TEXT or {}, SearchData.STOP_WORDS or {}
local SEARCH_QUERY_SOFT_STOP_WORDS, SEARCH_QUERY_ALIASES = SearchData.QUERY_SOFT_STOP_WORDS or {}, SearchData.QUERY_ALIASES or {}
local SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS = SearchData.DISPEL_DEBUFF_KEYWORDS or {}, SearchData.HIGHLIGHT_BORDER_KEYWORDS or {}
local SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS = SearchData.DISPEL_OVERLAY_KEYWORDS or {}, SearchData.DEBUFF_STRIPE_KEYWORDS or {}
local SEARCH_BLIZZARD_DISPEL_KEYWORDS = SearchData.BLIZZARD_DISPEL_KEYWORDS or {}
local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = SearchData.UNIT_AURA_DISPEL_KEYWORDS or {}
local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = SearchData.DASHBOARD_RECOVERY_KEYWORDS or {}
local SEARCH_DASHBOARD_DISCORD_KEYWORDS = SearchData.DASHBOARD_DISCORD_KEYWORDS or {}
local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = SearchData.DASHBOARD_SUPPORT_KEYWORDS or {}
local SEARCH_DASHBOARD_WAGO_KEYWORDS = SearchData.DASHBOARD_WAGO_KEYWORDS or {}
local SEARCH_DASHBOARD_SCALING_KEYWORDS = SearchData.DASHBOARD_SCALING_KEYWORDS or {}
local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS, CONTROL_KIND_LABEL = SearchData.DASHBOARD_CHANGELOG_KEYWORDS or {}, SearchData.CONTROL_KIND_LABEL or {}


Parts.AddControlQuestionSearchText = AddControlQuestionSearchText
Parts.AddRawSearchText = AddRawSearchText
Parts.AddSearchText = AddSearchText
Parts.AddToggleQuestionSearchText = AddToggleQuestionSearchText
Parts.CONTROL_KIND_LABEL = CONTROL_KIND_LABEL
Parts.C_Timer = C_Timer
Parts.CancelSearchBackgroundIndex = CancelSearchBackgroundIndex
Parts.ClearSearchLocaleCaches = ClearSearchLocaleCaches
Parts.ContentHeight = ContentHeight
Parts.ContentWidth = ContentWidth
Parts.DisplaySearchText = DisplaySearchText
Parts.EMPTY_SEARCH_RECORDS = EMPTY_SEARCH_RECORDS
Parts.EnsureSearchLocaleFresh = EnsureSearchLocaleFresh
Parts.M = M
Parts.MIN_SEARCH_QUERY_LEN = MIN_SEARCH_QUERY_LEN
Parts.MarkSearchIndexDirty = MarkSearchIndexDirty
Parts.NAV_ITEMS = NAV_ITEMS
Parts.NormalizeSearchText = NormalizeSearchText
Parts.RefreshSearchPlaceholder = RefreshSearchPlaceholder
Parts.SEARCH_BLIZZARD_DISPEL_KEYWORDS = SEARCH_BLIZZARD_DISPEL_KEYWORDS
Parts.SEARCH_CONTROL_HAYSTACK_MAX_LEN = SEARCH_CONTROL_HAYSTACK_MAX_LEN
Parts.SEARCH_CONTROL_MAX_TOKENS = SEARCH_CONTROL_MAX_TOKENS
Parts.SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = SEARCH_DASHBOARD_CHANGELOG_KEYWORDS
Parts.SEARCH_DASHBOARD_DISCORD_KEYWORDS = SEARCH_DASHBOARD_DISCORD_KEYWORDS
Parts.SEARCH_DASHBOARD_RECOVERY_KEYWORDS = SEARCH_DASHBOARD_RECOVERY_KEYWORDS
Parts.SEARCH_DASHBOARD_SCALING_KEYWORDS = SEARCH_DASHBOARD_SCALING_KEYWORDS
Parts.SEARCH_DASHBOARD_SUPPORT_KEYWORDS = SEARCH_DASHBOARD_SUPPORT_KEYWORDS
Parts.SEARCH_DASHBOARD_WAGO_KEYWORDS = SEARCH_DASHBOARD_WAGO_KEYWORDS
Parts.SEARCH_DEBUFF_STRIPE_KEYWORDS = SEARCH_DEBUFF_STRIPE_KEYWORDS
Parts.SEARCH_DISPEL_DEBUFF_KEYWORDS = SEARCH_DISPEL_DEBUFF_KEYWORDS
Parts.SEARCH_DISPEL_OVERLAY_KEYWORDS = SEARCH_DISPEL_OVERLAY_KEYWORDS
Parts.SEARCH_HIGHLIGHT_BORDER_KEYWORDS = SEARCH_HIGHLIGHT_BORDER_KEYWORDS
Parts.SEARCH_INPUT_DEBOUNCE_SEC = SEARCH_INPUT_DEBOUNCE_SEC
Parts.SEARCH_KEYWORDS = SEARCH_KEYWORDS
Parts.SEARCH_MAX_QUERY_CLAUSES = SEARCH_MAX_QUERY_CLAUSES
Parts.SEARCH_MAX_RAW_WORDS = SEARCH_MAX_RAW_WORDS
Parts.SEARCH_MAX_RECORD_TOKENS = SEARCH_MAX_RECORD_TOKENS
Parts.SEARCH_MAX_RESULTS = SEARCH_MAX_RESULTS
Parts.SEARCH_MAX_TERMS_PER_CLAUSE = SEARCH_MAX_TERMS_PER_CLAUSE
Parts.SEARCH_MIN_RESULT_SCORE = SEARCH_MIN_RESULT_SCORE
Parts.SEARCH_NOISE_TEXT = SEARCH_NOISE_TEXT
Parts.SEARCH_QUERY_ALIASES = SEARCH_QUERY_ALIASES
Parts.SEARCH_QUERY_SOFT_STOP_WORDS = SEARCH_QUERY_SOFT_STOP_WORDS
Parts.SEARCH_STATE = SEARCH_STATE
Parts.SEARCH_STOP_WORDS = SEARCH_STOP_WORDS
Parts.SEARCH_TEXT_MAX_LEN = SEARCH_TEXT_MAX_LEN
Parts.SEARCH_UNIT_AURA_DISPEL_KEYWORDS = SEARCH_UNIT_AURA_DISPEL_KEYWORDS
Parts.SEARCH_VISIBLE_RESULTS = SEARCH_VISIBLE_RESULTS
Parts.Search = Search
Parts.SearchBoxHasText = SearchBoxHasText
Parts.SearchCombatLocked = SearchCombatLocked
Parts.SearchData = SearchData
Parts.SearchDisplayText = SearchDisplayText
Parts.SearchEffectiveLocale = SearchEffectiveLocale
Parts.SearchMenuClosed = SearchMenuClosed
Parts.SearchPlaceholderText = SearchPlaceholderText
Parts.SearchText = SearchText
Parts.ShortLabel = ShortLabel
Parts.T = T
Parts.TrimText = TrimText
Parts.UpdateSearchPlaceholder = UpdateSearchPlaceholder
Parts.W = W
Parts.byte = byte
