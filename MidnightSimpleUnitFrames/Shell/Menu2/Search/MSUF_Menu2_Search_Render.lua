--- Search results page rendering. Cold-path UI only; indexing/query/routing stay in Search_IndexQuery.
--- Renders result rows and detail bodies from the prepared render context. Clicking a result
--- delegates to routing; this file should not mutate settings or rebuild the search index.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

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
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local combatLocked = SearchCombatLocked() and true or false
    local queryReady = not combatLocked and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = combatLocked and {} or SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end
    local b = W.PageBuilder(ctx)
    b:Header("Search", query ~= "" and M.Format("Results for \"%s\"", query) or "Type in the search box on the left.", 78)
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
    local sec = b:Section("Search Results", sectionH)
    if combatLocked then
        W.Text(sec, "Search is paused in combat.", 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "MSUF2 does not build or refresh the search index during combat.", 14, -70, width - 28, T.colors.dim)
    elseif query == "" then
        W.Text(sec, "Start typing to search every MSUF2 menu page.", 14, -44, width - 28, T.colors.muted)
    elseif not queryReady then
        W.Text(sec, M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), 14, -44, width - 28, T.colors.muted)
    elseif M.searchResultsPending then
        W.Text(sec, M.Format("Searching for \"%s\"...", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "Results update after you stop typing for a moment.", 14, -70, width - 28, T.colors.dim)
    elseif #results == 0 then
        W.Text(sec, M.Format("No results for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, SEARCH_STATE.indexing and "Still indexing menu pages..." or "Try a page name like bars, profiles, auras, castbar, colors, group, or target.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("Best %d match(es). Press Enter to open the first match.", visible), 14, -44, width - 28, T.colors.muted)
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
                OpenSearchTarget(pageKey, query, fallback, anchor, route)
            end)
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
    local quick = b:Section("Support Search Examples", 206)
    local shortcutDispel = "dispel border overlay any debuff"
    local shortcutStripe = "where is debuff stripe"
    local shortcutHighlights = "highlight priority dispel aggro target"
    local shortcuts = {}
    for row in ([[
Move Frames=where do I move my unitframe;Background=change my backgrond;Raid Frames=move raid frames;Text Size=make text bigger;Profiles=import profile wago;Castbar=evoker castbar;Buffs=show only my buffs;Blizzard=hide blizzard frames
Range Check=unit frame range check;Level Text=where is level text anchor;Performance=why is msuf lagging;Minimap=where is the minimap icon setting;Rounded=rounded frames ausschalten;Dispel=]] .. shortcutDispel .. [[;Stripe=]] .. shortcutStripe .. [[;Highlights=]] .. shortcutHighlights .. [[
]]):gmatch("[^;]+") do
        local label, query = row:match("^%s*(.-)=(.-)%s*$")
        if label and query then shortcuts[#shortcuts + 1] = { label, query } end
    end
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local searchQuery = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 14 + col * (buttonW + 14), -38 - row * 28)
        btn:SetScript("OnClick", function()
            if M.nav and M.nav.searchBox then
                M.nav.searchBox._msuf2SearchInternal = true
                M.nav.searchBox:SetText(searchQuery)
                M.nav.searchBox._msuf2SearchInternal = nil
                M.nav.searchBox:ClearFocus()
            end
            OpenSearchResults(searchQuery)
        end)
    end
    ctx:SetContentHeight(math.max(ContentHeight(), math.abs(b.y) + 42))
end
Search._CoreAPI = Search._CoreAPI or {}
Search._CoreAPI.BuildSearchPage = BuildSearchPage
Search._Render = {
    BuildSearchPage = BuildSearchPage,
}
