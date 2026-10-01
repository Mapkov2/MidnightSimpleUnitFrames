--- Menu2 search bridge.
---
--- The search implementation loads after the window shell, so shell code must
--- call it through late-bound wrappers. Keeping those wrappers here prevents
--- the window builder from owning search module internals.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Bridge = M.SearchBridge or {}
M.SearchBridge = Bridge
local function SearchAPI()
    return M.Search
end
local function SearchCall(name, ...)
    local api = SearchAPI()
    local fn = api and api[name]
    if type(fn) == "function" then return true, fn(...) end
end
function Bridge.UpdateSearchPlaceholder(searchBox)
    local called = SearchCall("UpdateSearchPlaceholder", searchBox)
    if called then return end
    if searchBox and searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then searchBox._msuf2SearchPlaceholder:SetText(M.Tr("Search settings...")) end
end
function Bridge.MarkSearchIndexDirty()
    SearchCall("MarkIndexDirty")
end
function Bridge.CancelSearchBackgroundIndex()
    SearchCall("CancelBackgroundIndex")
end
function Bridge.RefreshSearchResultsPage()
    SearchCall("RefreshResultsPage")
end
function Bridge.ScheduleSearchInputQuery(searchBox, query, openPage, onComplete)
    SearchCall("ScheduleInputQuery", searchBox, query, openPage, onComplete)
end
function Bridge.RunSearchInputQuery(query, openPage)
    SearchCall("RunInputQuery", query, openPage)
end
function Bridge.OpenSearchResults(query)
    return SearchCall("OpenResults", query)
end
function Bridge.RunSearchQuery(query)
    query = tostring(query or "")
    local searchBox = M.nav and M.nav.searchBox
    if searchBox and type(searchBox.SetText) == "function" then
        searchBox._msuf2SearchInternal = true
        searchBox:SetText(query)
        searchBox._msuf2SearchInternal = nil
        if type(searchBox.ClearFocus) == "function" then searchBox:ClearFocus() end
    end
    local called, result = SearchCall("OpenResults", query)
    if not called then return false, "Menu search is not available in this build." end
    if result == false then return false, "Menu search could not open that query." end
    return true, query
end
local function ExactRouteQuery(query, fallback, descriptor)
    if type(descriptor) ~= "table" then return query, false end
    -- controlPath is the stable selector-bearing identity (for example,
    -- .../lane/debuff/filters/...). `states` records which finite schema
    -- capture exposed the row, while the path supplies the concrete route.
    -- Do not mix legacy setting keys into this route: a historical key can say
    -- "blacklist" while the current control actually lives under Filters.
    local controlPath = tostring(descriptor.controlPath or "")
    if controlPath ~= "" then
        local workspace, lane, tool = controlPath:match("^auras/([^/]+)/lane/([^/]+)/([^/]+)")
        if (workspace == "unit-workspace" or workspace == "group-workspace") and lane ~= "" then
            -- The page key already identifies Unit vs Group. Omitting the
            -- workspace token is intentional: "group-workspace" would be read
            -- as Party scope and silently move a Raid user to Party.
            local selectorRoute = { "auras", "lane", lane }
            -- A lane's tool selector exists independently of the selected tool;
            -- all other rows name the concrete tool in the next path segment.
            if tool ~= "tool-selector" then selectorRoute[#selectorRoute + 1] = tool end
            selectorRoute[#selectorRoute + 1] = tostring(descriptor.states or "")
            return table.concat(selectorRoute, " "), true
        end
        return table.concat({ controlPath, tostring(descriptor.label or ""),
            tostring(descriptor.states or "") }, " "), true
    end
    return table.concat({
        tostring(query or ""), tostring(fallback or ""), tostring(descriptor.label or ""),
        tostring(descriptor.help or ""), tostring(descriptor.states or ""),
    }, " "), false
end

-- The route an exact target opens with, not yet applied: OpenSearchTarget
-- applies it once, right before it selects the page.
function Bridge.RouteForExactTarget(pageKey, query, fallback, exactTarget)
    local routeQuery, pathOwned = ExactRouteQuery(query, fallback, exactTarget)
    local called, route = SearchCall("RouteForTarget", pageKey, routeQuery, pathOwned and "" or fallback)
    return called and route or nil
end
function Bridge.PrepareSearchTarget(pageKey, query, fallback, exactTarget)
    local descriptor = exactTarget
    local routeQuery, pathOwned = ExactRouteQuery(query, fallback, descriptor)
    local called, route = SearchCall("RouteForTarget", pageKey, routeQuery,
        pathOwned and "" or fallback)
    if not called then return false, nil, descriptor end
    local applyCalled, changed = SearchCall("ApplyRoute", pageKey, route)
    if not applyCalled then return false, route, descriptor end
    return true, route, descriptor, changed == true
end
function Bridge.OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route, exactTarget)
    if route == nil and type(exactTarget) == "table" then
        local routeQuery, pathOwned = ExactRouteQuery(query, fallback, exactTarget)
        local called, exactRoute = SearchCall("RouteForTarget", pageKey, routeQuery,
            pathOwned and "" or fallback)
        if called then route = exactRoute end
    end
    return SearchCall("OpenTarget", pageKey, query, fallback, preferredAnchor, route, exactTarget)
end
function Bridge.BumpSearchInputSerial()
    SearchCall("BumpInputSerial")
end
function Bridge.ClearSearchRegistryPage(pageKey)
    SearchCall("ClearRegistryPage", pageKey)
end
function Bridge.CurrentMenuLocaleKey()
    if type(MSUF.GetEffectiveLocale) == "function" then
        local locale = MSUF.GetEffectiveLocale()
        if locale then return tostring(locale) end
    end
    if MSUF.LOCALE then return tostring(MSUF.LOCALE) end
    if type(_G.GetLocale) == "function" then return tostring(_G.GetLocale()) end
    return ""
end
