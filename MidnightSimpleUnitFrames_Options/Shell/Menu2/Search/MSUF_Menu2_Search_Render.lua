--- Search results page rendering. Cold-path UI only; indexing/query/routing stay in Search_IndexQuery.
--- Renders result rows and detail bodies from the prepared render context. Clicking a result
--- delegates to routing; this file should not mutate settings or rebuild the search index.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end

local Search = M.Search or {}
M.Search = Search

local C = Search._RenderContext
if type(C) ~= "table" then return end

M = C.M or M
local W = C.W
local T = C.T
local TrimText = C.TrimText
local SearchCombatLocked = C.SearchCombatLocked
local NormalizeSearchText = C.NormalizeSearchText
local MIN_SEARCH_QUERY_LEN = C.MIN_SEARCH_QUERY_LEN or 2
-- Characters of the normalized query (one Cyrillic or CJK character is one).
local QueryLength = C.QueryLength or function(text) return #NormalizeSearchText(text) end
local SearchPages = C.SearchPages
local SEARCH_STATE = C.SEARCH_STATE or {}
local SEARCH_VISIBLE_RESULTS = C.SEARCH_VISIBLE_RESULTS or 12
local CONTROL_KIND_LABEL = C.CONTROL_KIND_LABEL or {}
local ShortLabel = C.ShortLabel
local OpenSearchTarget = C.OpenSearchTarget
local OpenSearchResults = C.OpenSearchResults
local ContentHeight = C.ContentHeight

if not (W and T and TrimText and SearchCombatLocked and NormalizeSearchText and SearchPages and ShortLabel and OpenSearchTarget and OpenSearchResults and ContentHeight) then return end
local function SearchResultHasDetail(rec)
    if not rec then return false end
    if rec.kind == "faq" or rec.kind == "easteregg" then return rec.answer ~= nil and rec.answer ~= "" end
    return rec.answer ~= nil and rec.answer ~= ""
end
local function BuildSearchPage(ctx)
    -- Render can lazily refresh stale results when the query changed, but it still calls the
    -- search query layer instead of reconstructing index data here.
    if SearchCombatLocked() or not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local queryReady = QueryLength(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end
    local b = W.PageBuilder(ctx)
    b:Header("Smart Search", query ~= "" and M.Format("Results for \"%s\"", query)
        or "Search enabled features in your own words.", 78)
    local maxVisible = SEARCH_VISIBLE_RESULTS
    local visible = math.min(#results, maxVisible)
    local hasExpandedResult = false
    for i = 1, visible do
        if SearchResultHasDetail(results[i]) then
            hasExpandedResult = true
            break
        end
    end
    local columns = (hasExpandedResult and 1) or (width >= 760 and 2 or 1)
    local gap = 12
    local colW = math.floor((width - 24 - gap * (columns - 1)) / columns)
    local rowH = hasExpandedResult and 62 or 30
    local resultTopY = SEARCH_STATE.indexing and -88 or -70
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * rowH + (SEARCH_STATE.indexing and 18 or 0))
    local sec = b:Section("Best matches", sectionH)
    if query == "" then
        W.Text(sec, "Start typing to search available settings and help.", 14, -44, width - 28, T.colors.muted)
    elseif not queryReady then
        W.Text(sec, M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), 14, -44, width - 28, T.colors.muted)
    elseif M.searchResultsPending then
        W.Text(sec, M.Format("Searching for \"%s\"...", query), 14, -44, width - 28, T.colors.muted)
    elseif #results == 0 then
        W.Text(sec, M.Format("No exact setting found for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, SEARCH_STATE.indexing and "Still indexing menu pages..." or "Try fewer words or a different spelling.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("Best %d match(es). Open one to view its setting or help.", visible), 14, -44, width - 28, T.colors.muted)
        if SEARCH_STATE.indexing then
            W.Text(sec, "Indexing more menu pages in the background.", 14, -62, width - 28, T.colors.dim)
        end
        for i = 1, visible do
            local rec = results[i]
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            local x = 14 + col * (colW + gap)
            local y = resultTopY - row * rowH
            local kind = CONTROL_KIND_LABEL[rec.kind or ""] or (rec.kind == "page" and "Page") or nil
            if kind and type(M.Tr) == "function" then kind = M.Tr(kind) end
            local prefix = rec.hint ~= "" and rec.hint or rec.group
            local text = prefix ~= "" and (ShortLabel(prefix, 42) .. " > " .. ShortLabel(rec.label, 38)) or rec.label
            if kind and rec.kind ~= "text" then text = text .. " [" .. kind .. "]" end
            local btn = T.Button(sec, text, colW, 22)
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            local pageKey = rec.key
            local fallback = rec.anchorFallback or rec.label or rec.title
            local anchor = rec.anchor
            local route = rec.route
            local noOpen = rec.noOpen
            btn:SetScript("OnClick", function()
                if noOpen then
                    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
                    return
                end
                OpenSearchTarget(pageKey, query, fallback, anchor, route, rec.exactTarget)
            end)
            if type(M.RegisterMenuChromeControl) == "function" then
                M.RegisterMenuChromeControl(btn, "search.result." .. tostring(i),
                    (noOpen and "Select search result " or "Open search result ") .. tostring(rec.label or i), "action", {
                        historyMode = "none",
                        help = noOpen and "Selects this informational search result."
                            or "Opens this search result, including its exact options route and anchor.",

                    })
            end
            if SearchResultHasDetail(rec) then
                local answer = (type(M.Tr) == "function" and M.Tr(rec.answer)) or rec.answer
                W.Text(sec, ShortLabel(answer, 132), x + 8, y - 24, colW - 16, T.colors.dim)
                if rec.target and rec.target ~= "" then
                    local target = (type(M.Tr) == "function" and M.Tr(rec.target)) or rec.target
                    W.Text(sec, ShortLabel(target, 112), x + 8, y - 42, colW - 16, T.colors.muted)
                end
            end
        end
        if #results > maxVisible then
            W.Text(sec, M.Format("Showing the best %d matches. Add one more word to narrow it further.", maxVisible), 14, resultTopY - rows * rowH, width - 28, T.colors.dim)
        end
    end
    local quick = b:Section("Search Examples", 206)
    local examples = M.SearchData and M.SearchData.SEARCH_EXAMPLES or {}
    local locale = MSUF.GetEffectiveLocale and MSUF.GetEffectiveLocale() or MSUF.LOCALE or "enUS"
    local candidates = examples[locale] or examples.enUS or { { "Profiles", "profiles" }, { "Castbar", "castbar" }, { "Buffs", "buffs" } }
    -- An example tied to a page shows only where search offers that page;
    -- asking never builds the index before anything was typed.
    local shortcuts = {}
    local IsSearchPageAvailable = Search._CoreAPI.IsSearchPageAvailable
    for _, shortcut in ipairs(candidates) do
        if not shortcut[3] or IsSearchPageAvailable(shortcut[3]) then shortcuts[#shortcuts + 1] = shortcut end
    end
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local searchQuery = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 16 + col * (buttonW + 16), -40 - row * 28)
        btn:SetScript("OnClick", function()
            local bridge = M.SearchBridge
            if bridge and type(bridge.RunSearchQuery) == "function" then
                bridge.RunSearchQuery(searchQuery)
            else
                if M.nav and M.nav.searchBox then
                    M.nav.searchBox._msuf2SearchInternal = true
                    M.nav.searchBox:SetText(searchQuery)
                    M.nav.searchBox._msuf2SearchInternal = nil
                    M.nav.searchBox:ClearFocus()
                end
                OpenSearchResults(searchQuery)
            end
        end)
        if type(M.RegisterMenuChromeControl) == "function" then
            local shortcutToken = tostring(shortcuts[i][1] or i):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", "")
            M.RegisterMenuChromeControl(btn, "search.shortcut." .. (shortcutToken ~= "" and shortcutToken or tostring(i)),
                "Search for " .. tostring(shortcuts[i][1] or searchQuery), "action", {
                    actionKey = "menu_search_query",
                    actionFixedArgs = { query = searchQuery },
                    historyMode = "none",
                    help = "Runs this built-in MSUF support search.",

                })
        end
    end
    ctx:SetContentHeight(math.max(ContentHeight(), math.abs(b.y) + 42))
end
Search._CoreAPI = Search._CoreAPI or {}
Search._CoreAPI.BuildSearchPage = BuildSearchPage
Search._Render = {
    BuildSearchPage = BuildSearchPage,
}
