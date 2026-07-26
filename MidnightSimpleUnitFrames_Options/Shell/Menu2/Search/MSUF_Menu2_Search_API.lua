--- Search public API wiring and page registration.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local M = MSUF.MSUF2 or _G.MSUF2
if not M then return end

local Search = M.Search or {}
M.Search = Search

local API = Search._CoreAPI
if type(API) ~= "table" then return end

Search.SearchPlaceholderText = API.SearchPlaceholderText
Search.SearchBoxHasText = API.SearchBoxHasText
Search.RefreshSearchPlaceholder = API.RefreshSearchPlaceholder
Search.UpdateSearchPlaceholder = API.UpdateSearchPlaceholder
Search.MarkIndexDirty = API.MarkSearchIndexDirty
Search.CancelBackgroundIndex = API.CancelSearchBackgroundIndex
Search.ClearRegistryPage = API.ClearSearchRegistryPage
Search.BumpInputSerial = API.BumpSearchInputSerial
Search.RefreshResultsPage = API.RefreshSearchResultsPage
Search.ScheduleInputQuery = API.ScheduleSearchInputQuery
Search.RunInputQuery = API.RunSearchInputQuery
Search.OpenResults = API.OpenSearchResults
Search.ShouldUseAssistantForQuery = API.ShouldUseAssistantForQuery
Search.SubmitAssistantQuery = API.SubmitAssistantSearchQuery
Search.OpenTarget = API.OpenSearchTarget
Search.SearchPages = API.SearchPages
Search.GetFAQRecords = API.GetFAQRecords
Search.TrimText = API.TrimText
Search.ShortLabel = API.ShortLabel
local Routing = Search._RoutingAPI
if type(Routing) == "table" then
    Search.RouteForTarget = Routing.SearchRouteForTarget
    Search.ApplyRoute = Routing.ApplySearchRoute
end

if type(M.RegisterPage) == "function" and type(API.BuildSearchPage) == "function" then
    M.RegisterPage("search", { title = "Search", build = API.BuildSearchPage, version = 1 })
end
