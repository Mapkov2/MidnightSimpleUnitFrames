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
local function ExactSettingDescriptor(exactTarget)
    if type(exactTarget) ~= "table" then return exactTarget end
    local settingKey = tostring(exactTarget.settingKey or "")
    if settingKey == "" then return exactTarget end
    -- The Assistant companion is load-on-demand.  Read only its already-loaded
    -- descriptor at the moment the user asks to open a setting; Menu2 never
    -- loads the companion and retains none of its registry tables.
    local assistant = MSUF.Assistant
    local registry = assistant and assistant.Registry
    local setting = registry and type(registry.GetSetting) == "function" and registry:GetSetting(settingKey) or nil
    if type(setting) ~= "table" then return exactTarget end
    local descriptor = {}
    for key, value in pairs(exactTarget) do descriptor[key] = value end
    local fields = { "attribute", "dbPath", "type", "label", "category", "unit", "frameType" }
    for i = 1, #fields do
        local key = fields[i]
        if descriptor[key] == nil then descriptor[key] = setting[key] end
    end
    return descriptor
end
function Bridge.OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route, exactTarget)
    return SearchCall("OpenTarget", pageKey, query, fallback, preferredAnchor, route, ExactSettingDescriptor(exactTarget))
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
