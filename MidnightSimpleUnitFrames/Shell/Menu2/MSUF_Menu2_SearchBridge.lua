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
    if searchBox and searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then searchBox._msuf2SearchPlaceholder:SetText(M.Tr("Ask MSUF anything...")) end
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
function Bridge.ScheduleSearchInputQuery(searchBox, query)
    SearchCall("ScheduleInputQuery", searchBox, query)
end
function Bridge.RunSearchInputQuery(query, openPage)
    SearchCall("RunInputQuery", query, openPage)
end
function Bridge.OpenSearchResults(query)
    SearchCall("OpenResults", query)
end
function Bridge.OpenSearchTarget(pageKey, query, fallback, preferredAnchor)
    return SearchCall("OpenTarget", pageKey, query, fallback, preferredAnchor)
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
