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
function Bridge.ScheduleSearchInputQuery(searchBox, query, openPage, onComplete)
    SearchCall("ScheduleInputQuery", searchBox, query, openPage, onComplete)
end
function Bridge.RunSearchInputQuery(query, openPage)
    SearchCall("RunInputQuery", query, openPage)
end
function Bridge.OpenSearchResults(query)
    return SearchCall("OpenResults", query)
end
function Bridge.ShouldUseAssistantForQuery(query, results)
    local called, preferred = SearchCall("ShouldUseAssistantForQuery", query, results)
    return called and preferred == true
end
function Bridge.SubmitAssistantQuery(query)
    local called, submitted = SearchCall("SubmitAssistantQuery", query)
    return called and submitted == true
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
local function CopyFields(target, source, overwrite)
    if type(source) ~= "table" then return target end
    for key, value in pairs(source) do
        if overwrite or target[key] == nil then target[key] = value end
    end
    return target
end

local function GeneratedControlDescriptor(pageKey, exactTarget)
    if type(exactTarget) ~= "table" then return nil end
    -- The Assistant companion is load-on-demand. Read only its already-loaded
    -- generated descriptor; Menu2 never loads or retains companion data.
    local assistant = MSUF.Assistant
    local schema = assistant and assistant.ControlSchema
    if type(schema) ~= "table" then return nil end

    local semanticId = tostring(exactTarget.semanticId or "")
    if semanticId ~= "" and type(schema.GetBySemanticId) == "function" then
        return schema.GetBySemanticId(semanticId)
    end

    local settingKey = tostring(exactTarget.settingKey or "")
    if settingKey == "" or type(schema.GetBySettingKey) ~= "function" then return nil end
    local rows = schema.GetBySettingKey(settingKey)
    if type(rows) ~= "table" then return nil end
    local fallback
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            fallback = fallback or row
            if tostring(row.pageKey or "") == tostring(pageKey or "") then return row end
        end
    end
    return fallback
end

local function ExactTargetDescriptor(pageKey, exactTarget)
    if type(exactTarget) ~= "table" then return exactTarget end
    local descriptor = {}
    CopyFields(descriptor, GeneratedControlDescriptor(pageKey, exactTarget), true)
    CopyFields(descriptor, exactTarget, true)
    if descriptor.pageKey == nil then descriptor.pageKey = pageKey end

    local settingKey = tostring(descriptor.settingKey or "")
    local assistant = MSUF.Assistant
    local registry = assistant and assistant.Registry
    local setting = settingKey ~= "" and registry and type(registry.GetSetting) == "function"
        and registry:GetSetting(settingKey) or nil
    if type(setting) == "table" then
        local fields = { "attribute", "dbPath", "type", "label", "category", "unit", "frameType" }
        for i = 1, #fields do
            local key = fields[i]
            if descriptor[key] == nil then descriptor[key] = setting[key] end
        end
    end
    return descriptor
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

function Bridge.PrepareSearchTarget(pageKey, query, fallback, exactTarget)
    local descriptor = ExactTargetDescriptor(pageKey, exactTarget)
    local routeQuery, pathOwned = ExactRouteQuery(query, fallback, descriptor)
    local called, route = SearchCall("RouteForTarget", pageKey, routeQuery,
        pathOwned and "" or fallback)
    if not called then return false, nil, descriptor end
    local applyCalled, changed = SearchCall("ApplyRoute", pageKey, route)
    if not applyCalled then return false, route, descriptor end
    return true, route, descriptor, changed == true
end
function Bridge.OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route, exactTarget)
    exactTarget = ExactTargetDescriptor(pageKey, exactTarget)
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
