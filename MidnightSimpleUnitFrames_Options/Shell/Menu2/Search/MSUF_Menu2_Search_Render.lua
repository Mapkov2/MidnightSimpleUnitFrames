--- Search results page rendering. Cold-path UI only; indexing/query/routing stay in Search_IndexQuery.
--- Renders result rows and detail bodies from the prepared render context. Clicking a result
--- delegates to routing; this file should not mutate settings or rebuild the search index.
---
--- The page is built once per cached page entry and every query repaints it in
--- place. WoW never frees a frame, so rebuilding the page for each query left the
--- previous page's whole tree behind (about 170 frames and regions per query).
--- Result rows and example buttons come from pools that only grow to their
--- visible maximum, the way SearchPalette keeps its rows.
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

if not (W and T and TrimText and SearchCombatLocked and NormalizeSearchText and SearchPages and ShortLabel and OpenSearchTarget and OpenSearchResults
    and ContentHeight) then return end

local HEADER_HEIGHT = 78
local EXAMPLES_HEIGHT = 206
local SECTION_GAP = 12
local RESULT_GAP = 12
local EXAMPLE_COLUMNS = 3
local EMPTY_SUBTITLE = "Search enabled features in your own words."
-- One table for the whole session: example buttons are pooled per example entry.
local DEFAULT_EXAMPLES = { { "Profiles", "profiles" }, { "Castbar", "castbar" }, { "Buffs", "buffs" } }
-- Counts paints, so ShowSearchPage repaints only when selecting the page did not.
local paintCount = 0

local function SearchResultHasDetail(rec)
    if not rec then return false end
    if rec.kind == "faq" or rec.kind == "easteregg" then return rec.answer ~= nil and rec.answer ~= "" end
    return rec.answer ~= nil and rec.answer ~= ""
end
local function MenuShown()
    return M.frame and M.frame.IsShown and M.frame:IsShown()
end
-- Pooled text carries the same search metadata a fresh W.Text would. English
-- source text is translated by the font string's own setter; composed or
-- formatted text is translated already and is shown as it is.
local function SetPooledText(fs, text, translated)
    fs._msuf2SearchText = text
    if translated then T.SetTranslatedText(fs, text) else fs:SetText(text) end
end
local function PlaceText(fs, x, y, width)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
end
local function PooledText(owner, key, parent, color)
    local fs = owner[key]
    if not fs then
        fs = W.Text(parent, "", 0, 0, 100, color)
        owner[key] = fs
    end
    return fs
end
local function HideField(owner, key)
    local region = owner[key]
    if region then region:Hide() end
end

local function OpenResultRow(row)
    if row.noOpen then
        if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
        return
    end
    OpenSearchTarget(row.pageKey, row.query, row.fallback, row.anchor, row.route, row.rec and row.rec.exactTarget)
end
local function EnsureResultRow(view, index)
    local row = view.rows[index]
    if row then return row end
    row = { button = T.Button(view.results, "", 100, 22) }
    row.button:SetScript("OnClick", function() OpenResultRow(row) end)
    view.rows[index] = row
    return row
end
local function ResultRowText(rec)
    local kind = CONTROL_KIND_LABEL[rec.kind or ""] or (rec.kind == "page" and "Page") or nil
    if kind then kind = M.Tr(kind) end
    local prefix = rec.hint ~= "" and rec.hint or rec.group
    local text = prefix ~= "" and (ShortLabel(prefix, 42) .. " > " .. ShortLabel(rec.label, 38)) or rec.label
    if kind and rec.kind ~= "text" then text = text .. " [" .. kind .. "]" end
    return text
end
local function RegisterResultRow(row, index)
    local noOpen = row.noOpen
    local label = M.Format(noOpen and "Select search result %s" or "Open search result %s", tostring(row.rec.label or index))
    if row.chromeLabel == label then return end
    row.chromeLabel = label
    M.RegisterMenuChromeControl(row.button, "search.result." .. tostring(index), label, "action", {
        historyMode = "none",
        help = noOpen and "Selects this informational search result."
            or "Opens this search result, including its exact options route and anchor.",
    })
end
local function PaintResultRow(view, index, rec, query, x, y, width)
    local row = EnsureResultRow(view, index)
    local button = row.button
    local text = ResultRowText(rec)
    -- The label's own setter translates it, exactly as a new button's label did.
    button._msuf2SearchText = text
    button._msuf2Label._msuf2SearchText = text
    button._msuf2Label:SetText(text)
    button:SetWidth(width)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", view.results, "TOPLEFT", x, y)
    button:Show()
    row.rec, row.query, row.pageKey = rec, query, rec.key
    row.fallback = rec.anchorFallback or rec.label or rec.title
    row.anchor, row.route, row.noOpen = rec.anchor, rec.route, rec.noOpen
    RegisterResultRow(row, index)
    if not SearchResultHasDetail(rec) then
        HideField(row, "answer")
        HideField(row, "target")
        return
    end
    local answer = PooledText(row, "answer", view.results, T.colors.dim)
    PlaceText(answer, x + 8, y - 24, width - 16)
    SetPooledText(answer, ShortLabel(M.Tr(rec.answer), 132), true)
    answer:Show()
    if rec.target and rec.target ~= "" then
        local target = PooledText(row, "target", view.results, T.colors.muted)
        PlaceText(target, x + 8, y - 42, width - 16)
        SetPooledText(target, ShortLabel(M.Tr(rec.target), 112), true)
        target:Show()
    else
        HideField(row, "target")
    end
end
local function HideResultRows(view, first)
    for i = first, #view.rows do
        local row = view.rows[i]
        row.button:Hide()
        row.rec = nil
        HideField(row, "answer")
        HideField(row, "target")
    end
end

-- The status lines above the result rows, for every page state.
local function PaintStatus(view, query, queryReady, results, visible, width)
    local first, firstTranslated, second, secondY
    if query == "" then
        first = "Start typing to search available settings and help."
    elseif not queryReady then
        first, firstTranslated = M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), true
    elseif M.searchResultsPending then
        first, firstTranslated = M.Format("Searching for \"%s\"...", query), true
    elseif #results == 0 then
        first, firstTranslated = M.Format("No exact setting found for \"%s\".", query), true
        second = SEARCH_STATE.indexing and "Still indexing menu pages..." or "Try fewer words or a different spelling."
        secondY = -70
    else
        first, firstTranslated = M.Format("Best %d match(es). Open one to view its setting or help.", visible), true
        if SEARCH_STATE.indexing then second, secondY = "Indexing more menu pages in the background.", -62 end
    end
    local status = PooledText(view, "status", view.results, T.colors.muted)
    PlaceText(status, 14, -44, width - 28)
    SetPooledText(status, first, firstTranslated)
    status:Show()
    if second then
        local detail = PooledText(view, "statusDetail", view.results, T.colors.dim)
        PlaceText(detail, 14, secondY, width - 28)
        SetPooledText(detail, second)
        detail:Show()
    else
        HideField(view, "statusDetail")
    end
    -- Rows exist only for a ready query with results.
    return not (query == "" or not queryReady or M.searchResultsPending or #results == 0)
end

local function PaintHeader(view, query)
    local subtitle = view.header.subtitle
    if not subtitle then return end
    local text, translated = EMPTY_SUBTITLE, false
    if query ~= "" then text, translated = M.Format("Results for \"%s\"", query), true end
    view.subtitleText = text
    SetPooledText(subtitle, text, translated)
    local help = subtitle._msuf2HelpTarget
    if help then help:SetShown(not subtitle.IsTruncated or subtitle:IsTruncated()) end
end

local function RunExampleQuery(searchQuery)
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
end
local function CreateExampleButton(view, shortcut, slot, width)
    local searchQuery = shortcut[2]
    local button = T.Button(view.examples, shortcut[1], width, 22)
    button:SetScript("OnClick", function() RunExampleQuery(searchQuery) end)
    local shortcutToken = tostring(shortcut[1] or slot):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", "")
    M.RegisterMenuChromeControl(button, "search.shortcut." .. (shortcutToken ~= "" and shortcutToken or tostring(slot)),
        M.Format("Search for %s", M.Tr(shortcut[1] or searchQuery)), "action", {
            actionKey = "menu_search_query",
            actionFixedArgs = { query = searchQuery },
            historyMode = "none",
            help = "Runs this built-in MSUF support search.",
        })
    view.exampleButtons[shortcut] = button
    return button
end
-- An example tied to a page shows only where search offers that page;
-- asking never builds the index before anything was typed.
local function PaintExamples(view, width)
    local examples = M.SearchData and M.SearchData.SEARCH_EXAMPLES or {}
    local locale = MSUF.GetEffectiveLocale and MSUF.GetEffectiveLocale() or MSUF.LOCALE or "enUS"
    local candidates = examples[locale] or examples.enUS or DEFAULT_EXAMPLES
    if view.exampleCandidates ~= candidates then
        for _, button in pairs(view.exampleButtons) do button:Hide() end
        view.exampleCandidates = candidates
    end
    local IsSearchPageAvailable = Search._CoreAPI.IsSearchPageAvailable
    local buttonW = math.floor((width - 56) / EXAMPLE_COLUMNS)
    local shown = 0
    for _, shortcut in ipairs(candidates) do
        local button = view.exampleButtons[shortcut]
        if not shortcut[3] or IsSearchPageAvailable(shortcut[3]) then
            shown = shown + 1
            button = button or CreateExampleButton(view, shortcut, shown, buttonW)
            local col = (shown - 1) % EXAMPLE_COLUMNS
            local row = math.floor((shown - 1) / EXAMPLE_COLUMNS)
            button:SetWidth(buttonW)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", view.examples, "TOPLEFT", 16 + col * (buttonW + 16), -40 - row * 28)
            button:Show()
        elseif button then
            button:Hide()
        end
    end
end

local function BuildSkeleton(view)
    local b = W.PageBuilder(view.ctx)
    view.builder = b
    view.header = b:Header("Smart Search", EMPTY_SUBTITLE, HEADER_HEIGHT)
    view.resultsY = b.y
    view.results = b:Section("Best matches", 160)
    view.examples = b:Section("Search Examples", EXAMPLES_HEIGHT)
    view.rows, view.exampleButtons = {}, {}
    local help = view.header.subtitle and view.header.subtitle._msuf2HelpTarget
    if help and M.AddTooltip then
        M.AddTooltip(help, "Smart Search", function() return view.subtitleText end)
    end
end

--- Paints the page for the current query. Builds the frame tree on the first
--- paint that may build (never in combat or while the menu is hidden); every
--- later paint re-texts, re-places, shows and hides the pooled regions only.
local function PaintSearchPage(view)
    -- Render can lazily refresh stale results when the query changed, but it still calls the
    -- search query layer instead of reconstructing index data here.
    if SearchCombatLocked() or not MenuShown() then return false end
    local width = view.ctx.width
    local query = TrimText(M.searchQuery or "")
    local queryReady = QueryLength(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end
    if not view.header then BuildSkeleton(view) end
    paintCount = paintCount + 1
    PaintHeader(view, query)
    local visible = math.min(#results, SEARCH_VISIBLE_RESULTS)
    local hasExpandedResult = false
    for i = 1, visible do
        if SearchResultHasDetail(results[i]) then
            hasExpandedResult = true
            break
        end
    end
    local columns = (hasExpandedResult and 1) or (width >= 760 and 2 or 1)
    local colW = math.floor((width - 24 - RESULT_GAP * (columns - 1)) / columns)
    local rowH = hasExpandedResult and 62 or 30
    local resultTopY = SEARCH_STATE.indexing and -88 or -70
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * rowH + (SEARCH_STATE.indexing and 18 or 0))
    view.results:SetHeight(sectionH)
    local painted = 0
    if PaintStatus(view, query, queryReady, results, visible, width) then
        for i = 1, visible do
            local x = 14 + ((i - 1) % columns) * (colW + RESULT_GAP)
            local y = resultTopY - math.floor((i - 1) / columns) * rowH
            PaintResultRow(view, i, results[i], query, x, y, colW)
        end
        painted = visible
    end
    HideResultRows(view, painted + 1)
    if painted > 0 and #results > SEARCH_VISIBLE_RESULTS then
        local more = PooledText(view, "more", view.results, T.colors.dim)
        PlaceText(more, 14, resultTopY - rows * rowH, width - 28)
        SetPooledText(more, M.Format("Showing the best %d matches. Add one more word to narrow it further.",
            SEARCH_VISIBLE_RESULTS), true)
        more:Show()
    else
        HideField(view, "more")
    end
    local examplesY = view.resultsY - sectionH - SECTION_GAP
    view.examples:ClearAllPoints()
    view.examples:SetPoint("TOPLEFT", view.builder.parent, "TOPLEFT", view.builder.x, examplesY)
    PaintExamples(view, width)
    local bottomY = examplesY - EXAMPLES_HEIGHT - SECTION_GAP
    view.ctx:SetContentHeight(math.max(ContentHeight(), math.abs(bottomY) + 42))
    return true
end

local function BuildSearchPage(ctx)
    local view = { ctx = ctx }
    if ctx.entry then ctx.entry._msuf2SearchView = view end
    -- Repaint when the page is shown again (history, reopening the menu) and
    -- when its entry is refreshed after a data change (undo, redo, reset).
    if ctx.wrapper and ctx.wrapper.HookScript then
        ctx.wrapper:HookScript("OnShow", function() PaintSearchPage(view) end)
    end
    M.AddRefresher(ctx, function() PaintSearchPage(view) end)
    PaintSearchPage(view)
end

local function ResetPageScroll()
    local scroll = M.scrollFrame
    if not scroll then return end
    if scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(0)
    elseif scroll._msuf2RefreshScrollBar then
        scroll:_msuf2RefreshScrollBar()
    end
end
--- Shows the results page for the current query. Selecting the page builds it
--- once; when it was on screen already, the page repaints in place and the
--- reader lands at the top of the fresh result list.
local function ShowSearchPage()
    local wasActive = M.activeKey == "search"
    local before = paintCount
    if M.SelectPage("search") == false then return false end
    local entry = M.cache and M.cache.search
    local view = entry and entry._msuf2SearchView
    if view and paintCount == before then PaintSearchPage(view) end
    if wasActive then ResetPageScroll() end
    return true
end

Search._CoreAPI = Search._CoreAPI or {}
Search._CoreAPI.BuildSearchPage = BuildSearchPage
Search._Render = {
    BuildSearchPage = BuildSearchPage,
    ShowSearchPage = ShowSearchPage,
}
