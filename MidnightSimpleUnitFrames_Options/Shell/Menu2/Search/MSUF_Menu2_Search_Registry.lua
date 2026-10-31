-- Search widget registration and runtime record construction.
local _, MSUF = ...
local Parts = MSUF.SearchIndexParts
local AddControlQuestionSearchText = Parts.AddControlQuestionSearchText
local AddRawSearchText = Parts.AddRawSearchText
local AddSearchText = Parts.AddSearchText
local AddToggleQuestionSearchText = Parts.AddToggleQuestionSearchText
local DisplaySearchText = Parts.DisplaySearchText
local EnsureSearchLocaleFresh = Parts.EnsureSearchLocaleFresh
local M = Parts.M
local MarkSearchIndexDirty = Parts.MarkSearchIndexDirty
local NAV_ITEMS = Parts.NAV_ITEMS
local NormalizeSearchText = Parts.NormalizeSearchText
local SEARCH_CONTROL_HAYSTACK_MAX_LEN = Parts.SEARCH_CONTROL_HAYSTACK_MAX_LEN
local SEARCH_CONTROL_MAX_TOKENS = Parts.SEARCH_CONTROL_MAX_TOKENS
local SEARCH_KEYWORDS = Parts.SEARCH_KEYWORDS
local SEARCH_MAX_RECORD_TOKENS = Parts.SEARCH_MAX_RECORD_TOKENS
local SEARCH_NOISE_TEXT = Parts.SEARCH_NOISE_TEXT
local SEARCH_STATE = Parts.SEARCH_STATE
local SEARCH_TEXT_MAX_LEN = Parts.SEARCH_TEXT_MAX_LEN
local Search = Parts.Search
local SearchDisplayText = Parts.SearchDisplayText
local SearchEffectiveLocale = Parts.SearchEffectiveLocale
local SearchText = Parts.SearchText
-- Pure in its text (both text caches and the noise list are static), and
-- labels repeat across the shared unit/group pages and every re-registration,
-- so string answers are memoized.
local function IsSearchableDisplayText(text)
    local known = SEARCH_STATE.searchableText[text]
    if known ~= nil then return known end
    local display = DisplaySearchText(text)
    local searchable = false
    if display ~= "" and #display <= SEARCH_TEXT_MAX_LEN then
        local normalized = NormalizeSearchText(display)
        searchable = normalized ~= "" and not SEARCH_NOISE_TEXT[normalized] and #normalized >= 2
    end
    if type(text) == "string" and #text <= 256 then
        if SEARCH_STATE.searchableTextCount >= 4096 then
            SEARCH_STATE.searchableText, SEARCH_STATE.searchableTextCount = {}, 0
        end
        SEARCH_STATE.searchableText[text] = searchable
        SEARCH_STATE.searchableTextCount = SEARCH_STATE.searchableTextCount + 1
    end
    return searchable
end

local function FontStringText(region)
    if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return nil end
    local raw = region._msuf2SearchText
    local text = raw
    if text == nil and region.GetText then text = region:GetText() end
    text = DisplaySearchText(text)
    if text == "" then return nil end
    return text
end

local function SearchValueText(item)
    if type(item) == "table" then
        return item.text or item.label or item.name or item.title or item.value or item.key
    end
    return item
end

local function AddValuesSearchText(parts, values)
    if type(values) == "function" then
        local resolved = values()

        values = resolved
    end
    if type(values) ~= "table" then return end
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        AddSearchText(parts, SearchValueText(item))
        if type(item) == "table" then
            AddSearchText(parts, item.tooltip)
            AddSearchText(parts, item.desc or item.description)
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            AddSearchText(parts, key)
            AddSearchText(parts, SearchValueText(item))
            if type(item) == "table" then
                AddSearchText(parts, item.tooltip)
                AddSearchText(parts, item.desc or item.description)
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
end

local function SearchHint(pageInfo, anchor)
    local parent = anchor and anchor.GetParent and anchor:GetParent()
    -- The breadcrumb depends on the page info and the parent chain only. A build
    -- shares one page info across a page's controls (BuildRegistrySearchRecord),
    -- and that info remembers the breadcrumb per parent frame for its siblings.
    local memo = parent and pageInfo._msuf2SearchHintMemo
    if memo and memo[parent] then return memo[parent] end
    local parts, seen = {}, {}
    local function Add(text)
        text = SearchDisplayText(text)
        local norm = NormalizeSearchText(text)
        if norm ~= "" and not seen[norm] then
            seen[norm] = true
            parts[#parts + 1] = text
        end
    end
    Add(pageInfo.group)
    Add(pageInfo.label or pageInfo.title)
    local sections, sectionSeen = {}, {}
    local chainStart = parent
    local pageNorm = NormalizeSearchText(pageInfo.title or pageInfo.label or "")
    while parent do
        local title
        local entry = parent._msuf2CollapsibleEntry
        if entry and entry.label then
            local text = FontStringText(entry.label)
            if IsSearchableDisplayText(text) then title = text end
        end
        if not title and parent.title then
            local text = FontStringText(parent.title)
            if IsSearchableDisplayText(text) then title = text end
        end
        if not title and IsSearchableDisplayText(parent._msuf2SearchTitle) then
            title = DisplaySearchText(parent._msuf2SearchTitle)
        end
        local norm = NormalizeSearchText(title or "")
        if norm ~= "" and norm ~= pageNorm and not sectionSeen[norm] then
            sectionSeen[norm] = true
            table.insert(sections, 1, title)
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    for i = 1, #sections do Add(sections[i]) end
    local hint = table.concat(parts, " > ")
    if memo then memo[chainStart] = hint end
    return hint
end

local function BuildSearchPageInfos()
    local groupLabels, navInfo = {}, {}
    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.header then groupLabels[item.id or item.header] = item.header end
        if item.title then groupLabels[item.id or item.title] = item.title end
    end

    local infos, seen = {}, {}
    local function AddPageInfo(key, label, group)
        if not key or key == "search" or seen[key] then return end
        seen[key] = true
        local spec = M.pages[key]
        local info = {
            key = key,
            label = M.Tr(label or (spec and spec.title) or key),
            group = group and M.Tr(group) or "",
            title = M.Tr((spec and spec.title) or label or key),
        }
        infos[#infos + 1] = info
        navInfo[key] = info
    end

    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.key then
            AddPageInfo(item.key, item.label, item.group and groupLabels[item.group] or nil)
        end
    end
    for i = 1, #(M.pageOrder or {}) do
        local key = M.pageOrder[i]
        local spec = M.pages[key]
        AddPageInfo(key, spec and spec.title or key, nil)
    end
    return infos, navInfo
end

local function BuildSearchPageInfoForKey(pageKey)
    local spec = M.pages and M.pages[pageKey]
    local title = (spec and spec.title) or pageKey or ""
    return {
        key = pageKey,
        label = M.Tr(title),
        group = "",
        title = M.Tr(title),
    }
end

local function ClearSearchRegistryPage(pageKey)
    if not pageKey then return end
    if type(M.ClearRuntimeControlsForPage) == "function" then
        M.ClearRuntimeControlsForPage(pageKey)
    end
    local ids = SEARCH_STATE.registryByPage[pageKey]
    if ids then
        for i = 1, #ids do
            SEARCH_STATE.registry[ids[i]] = nil
            SEARCH_STATE.registryRecords[ids[i]] = nil
        end
        SEARCH_STATE.registryByPage[pageKey] = nil
        MarkSearchIndexDirty()
    end
end

local function CopyStaticSearchValues(values)
    if type(values) == "function" then
        local resolved = values()

        values = resolved
    end
    if type(values) ~= "table" then return nil end
    local out, count = {}, 0
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        local text = SearchValueText(item)
        if text ~= nil then
            count = count + 1
            out[count] = text
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            count = count + 1
            out[count] = key
            local text = SearchValueText(item)
            if text ~= nil then
                count = count + 1
                out[count] = text
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
    return count > 0 and out or nil
end

-- Registration keeps a compact snapshot. Search-only fields are projected
-- from it on demand; mutable metadata and value providers retain their exact
-- registration-time semantics. Fully normalized search rows remain lazy.
local REGISTRY_METADATA_FIELDS = {
    values = 1, identityLabel = 2, identityKey = 3, controlPath = 4, sectionId = 5,
    classification = 6, searchPrepareKind = 7, searchPrepareValue = 8,
    ephemeral = 9, settingKey = 10, actionKey = 11, actionFixedArgs = 12,
    actionInputArg = 13, navigationKey = 14, confirmRequired = 15, keywords = 16, help = 17,
    controlId = 18, _rawValues = 19,
}
local REGISTRY_ENTRY_META = {
    __index = function(entry, key)
        local slot = REGISTRY_METADATA_FIELDS[key]
        if slot then return entry._metadata[slot] end
    end,
    __newindex = function(entry, key, value)
        local slot = REGISTRY_METADATA_FIELDS[key]
        if slot then entry._metadata[slot] = value else rawset(entry, key, value) end
    end,
}
local BuildRegistrySearchRecord
function M.RefreshSearchControlIdentity(widget, record)
    local id = widget._msuf2SearchRegistryId
    local entry = id and SEARCH_STATE.registry[id]
    if not entry then return end
    local data = entry._metadata
    data[18], data[3], data[4] = record.controlId, record.identityKey, record.controlPath
    data[10], data[11], data[6] = record.settingKey, record.actionKey, record.classification
    SEARCH_STATE.registryRecords[id] = nil
    MarkSearchIndexDirty()
end
local runtimeControlMetaScratch = {}
local runtimeControlMetaScratchBusy = false

local function RegisterSearchRuntimeControl(widget, meta, pageKey, kind, label, rawLabel, help)
    if type(M.RegisterRuntimeControl) ~= "function" then return nil end
    local payload = runtimeControlMetaScratchBusy and {} or runtimeControlMetaScratch
    payload.searchIndexed = meta.searchIndexed == true
    payload.controlId = meta.controlId
    payload.identityKey = meta.identityKey
    payload.controlPath = meta.controlPath
    payload.pageKey = pageKey
    payload.kind = kind
    payload.label = label
    payload.identityLabel = meta.identityLabel or widget._msuf2SearchText or rawLabel
    payload.settingKey = meta.settingKey
    payload.sectionId = meta.sectionId
    payload.searchPrepareKind = meta.searchPrepareKind
    payload.searchPrepareValue = meta.searchPrepareValue
    payload.actionKey = meta.actionKey
    payload.actionFixedArgs = meta.actionFixedArgs
    payload.actionInputArg = meta.actionInputArg
    payload.navigationKey = meta.navigationKey
    payload.classification = meta.classification or meta.controlType
    payload.ephemeral = meta.ephemeral
    payload.help = help
    local wasBusy = runtimeControlMetaScratchBusy
    runtimeControlMetaScratchBusy = true
    local result = M.RegisterRuntimeControl(widget, payload, "search")
    runtimeControlMetaScratchBusy = wasBusy
    return result or nil
end

function M.UnregisterSearchWidget(widget)
    if not widget then return false end
    local id, pageKey = widget._msuf2SearchRegistryId, widget._msuf2SearchRegistryPage
    if not id then return false end
    SEARCH_STATE.registry[id] = nil
    SEARCH_STATE.registryRecords[id] = nil
    local pageIds = pageKey and SEARCH_STATE.registryByPage[pageKey]
    if pageIds then
        for i = #pageIds, 1, -1 do
            if pageIds[i] == id then table.remove(pageIds, i) end
        end
        if #pageIds == 0 then SEARCH_STATE.registryByPage[pageKey] = nil end
    end
    widget._msuf2SearchRegistryId = nil
    widget._msuf2SearchRegistryPage = nil
    MarkSearchIndexDirty()
    return true
end

--- Help written for search becomes the hover tooltip of a setting or action
--- that has none. Nothing is generated: a page tooltip always wins (AddTooltip
--- stamps the widget), `meta.helpTooltip = false` opts out, and help that only
--- restates the label stays silent (it needs 20+ characters and two words that
--- are neither in the label nor filler). Build time only, once per widget.
function M.WireSearchHelpTooltip(widget, meta, classification, help, rawLabel)
    if meta.helpTooltip == false or meta.ephemeral or type(help) ~= "string" or #help < 20 then return false end
    if classification ~= "setting" and classification ~= "action" then
        -- Unclassified page controls still qualify; chrome (ephemeral,
        -- navigation) and non-controls (sections, previews) never do.
        local kind = widget._msuf2ControlKind
        if classification ~= nil or not (kind == "toggle" or kind == "slider" or kind == "dropdown"
            or kind == "segment" or kind == "textinput" or kind == "color" or kind == "button") then
            return false
        end
    end
    if type(M.AddTooltip) ~= "function" or widget._msuf2HelpTooltipChecked == help then return false end
    widget._msuf2HelpTooltipChecked = help
    local labelFont = widget._msuf2Title or widget._msuf2Label
    local title = (labelFont and labelFont._msuf2SearchText) or rawLabel
    if type(title) ~= "string" or title == "" then title = nil end
    local stop = M._searchHelpTooltipStopWords
    if not stop then
        stop = {}
        for word in ("the a an this that these those of for to in on with and or is are be it its by as at from"
            .. " enable enables enabled disable disables disabled set sets setting settings change changes"
            .. " choose chooses select selects selected toggle toggles show shows hide hides use uses used"
            .. " turn turns adjust adjusts control controls option options value values when if"):gmatch("%S+") do
            stop[word] = true
        end
        M._searchHelpTooltipStopWords = stop
    end
    local labelWords = M._searchHelpTooltipLabelWords
    if not labelWords then
        labelWords = {}
        M._searchHelpTooltipLabelWords = labelWords
    end
    for word in pairs(labelWords) do labelWords[word] = nil end
    for word in (title or ""):lower():gmatch("%w+") do labelWords[word] = true end
    local informative = 0
    for word in help:lower():gmatch("%w+") do
        if not labelWords[word] and not stop[word] then
            informative = informative + 1
            if informative >= 2 then break end
        end
    end
    if informative < 2 then return false end
    M.AddTooltip(widget, title, help, {
        hook = true, labelHit = true, autoHelp = true,
        enabled = function() return widget._msuf2TooltipWired == "auto" end,
    })
    M.searchHelpTooltipCount = (M.searchHelpTooltipCount or 0) + 1
    return true
end

function M.RegisterSearchWidget(widget, meta)
    if not widget or type(meta) ~= "table" then return end
    if widget._msuf2ControlPartOf ~= nil then
        if type(M.UnregisterSearchWidget) == "function" then M.UnregisterSearchWidget(widget) end
        return
    end
    EnsureSearchLocaleFresh()
    M.DeclareExactSearchPreparation(widget, meta)
    local pageKey = meta.pageKey or M.PageKeyForWidget(widget) or M.activeKey
    if type(pageKey) ~= "string" or pageKey == "" or pageKey == "search" then return end

    local pageEntry = M.cache and M.cache[pageKey]
    if pageEntry and widget._msuf2SearchOwnerEntry ~= pageEntry then
        pageEntry.searchWidgets = pageEntry.searchWidgets or {}
        pageEntry.searchWidgets[#pageEntry.searchWidgets + 1] = widget
        widget._msuf2SearchOwnerEntry = pageEntry
    end

    local rawLabel = meta.label or meta.title or meta.text or widget._msuf2SearchText or widget._msuf2SearchTitle
    local label = DisplaySearchText(rawLabel)
    if not IsSearchableDisplayText(label) then return end
    local kind = meta.kind or widget._msuf2ControlKind or "control"
    local anchor = meta.anchor or widget._msuf2Title or widget._msuf2Label or widget
    local rawValues = meta.values or widget.values
    local keywords = meta.keywords
    local help = meta.help or meta.description
    local catalogId
    local catalogClass = meta.classification or meta.controlType
    local catalogInteractive = meta.catalog ~= false and (meta.controlId ~= nil or meta.settingKey ~= nil
        or catalogClass == "setting" or catalogClass == "action"
        or catalogClass == "navigation" or catalogClass == "ephemeral")
    -- Only explicitly identified controls join the exact navigation catalog.
    if catalogInteractive then
        catalogId = RegisterSearchRuntimeControl(widget, meta, pageKey, kind, label, rawLabel, help)
    end
    if help and widget._msuf2TooltipWired == nil then M.WireSearchHelpTooltip(widget, meta, catalogClass, help, rawLabel) end

    local id = widget._msuf2SearchRegistryId
    local previousPageKey = widget._msuf2SearchRegistryPage
    local movedEntry
    if id and previousPageKey and previousPageKey ~= pageKey then
        movedEntry = SEARCH_STATE.registry[id]
        SEARCH_STATE.registry[id] = nil
        SEARCH_STATE.registryRecords[id] = nil
        local previousPageIds = SEARCH_STATE.registryByPage[previousPageKey]
        if previousPageIds then
            -- An id is listed once (each new id gets a fresh serial and joins
            -- one page list). A shared unit/group page moves its widgets as one
            -- run of that list, so the last removal's index finds the next id.
            local at = SEARCH_STATE.registryMoveAt
            if not at or previousPageIds[at] ~= id then
                at = nil
                for i = 1, #previousPageIds do
                    if previousPageIds[i] == id then
                        at = i
                        break
                    end
                end
            end
            if at then
                table.remove(previousPageIds, at)
                SEARCH_STATE.registryMoveAt = at
            end
            if #previousPageIds == 0 then SEARCH_STATE.registryByPage[previousPageKey] = nil end
        end
        widget._msuf2SearchRegistryId = nil
        widget._msuf2SearchRegistryPage = nil
        id = nil
        MarkSearchIndexDirty()
    end
    if not id or widget._msuf2SearchRegistryPage ~= pageKey or not SEARCH_STATE.registry[id] then
        SEARCH_STATE.registrySerial = SEARCH_STATE.registrySerial + 1
        id = pageKey .. ":" .. tostring(SEARCH_STATE.registrySerial)
        widget._msuf2SearchRegistryId = id
        widget._msuf2SearchRegistryPage = pageKey
        SEARCH_STATE.registryByPage[pageKey] = SEARCH_STATE.registryByPage[pageKey] or {}
        SEARCH_STATE.registryByPage[pageKey][#SEARCH_STATE.registryByPage[pageKey] + 1] = id
    end

    local previous = SEARCH_STATE.registry[id]
    if previous then
        local previousData = previous._metadata
        if previous.widget == widget
            and previous.pageKey == pageKey
            and previous.label == label
            and previous.kind == kind
            and previous.anchor == anchor
            and previousData[18] == catalogId
            and previousData[2] == (meta.identityLabel or widget._msuf2SearchText or rawLabel)
            and previousData[3] == meta.identityKey
            and previousData[4] == meta.controlPath
            and previousData[5] == meta.sectionId
            and previousData[6] == (meta.classification or meta.controlType)
            and previousData[9] == meta.ephemeral
            and previousData[10] == meta.settingKey
            and previousData[11] == meta.actionKey
            and previousData[12] == meta.actionFixedArgs
            and previousData[13] == meta.actionInputArg
            and previousData[14] == meta.navigationKey
            and previousData[16] == keywords
            and previousData[17] == help
            and previousData[19] == rawValues
            and (rawValues == nil or type(rawValues) ~= "function")
        then
            return
        end
    end

    widget._msuf2SearchMeta = meta
    local values = CopyStaticSearchValues(rawValues)
    local entry = previous or movedEntry
    local data = entry and entry._metadata
    if data then
        entry.id, entry.widget, entry.pageKey, entry.label, entry.kind, entry.anchor = id, widget, pageKey, label, kind, anchor
        data[18], data[19] = catalogId, rawValues
        data[1], data[2] = values, meta.identityLabel or widget._msuf2SearchText or rawLabel
        data[3], data[4], data[5] = meta.identityKey, meta.controlPath, meta.sectionId
        data[6] = meta.classification or meta.controlType
        data[7], data[8] = meta.searchPrepareKind, meta.searchPrepareValue
        data[9], data[10], data[11] = meta.ephemeral, meta.settingKey, meta.actionKey
        data[12], data[13] = meta.actionFixedArgs, meta.actionInputArg
        data[14], data[15], data[16], data[17] = meta.navigationKey, meta.confirmRequired, keywords, help
    else
        data = { values, meta.identityLabel or widget._msuf2SearchText or rawLabel,
            meta.identityKey, meta.controlPath, meta.sectionId, meta.classification or meta.controlType,
            meta.searchPrepareKind, meta.searchPrepareValue, meta.ephemeral, meta.settingKey, meta.actionKey,
            meta.actionFixedArgs, meta.actionInputArg, meta.navigationKey, meta.confirmRequired, keywords, help, catalogId, rawValues }
        entry = setmetatable({ id = id, widget = widget, pageKey = pageKey, label = label, kind = kind, anchor = anchor,
            _metadata = data }, REGISTRY_ENTRY_META)
    end
    SEARCH_STATE.registry[id] = entry
    SEARCH_STATE.registryRecords[id] = nil
    MarkSearchIndexDirty()
end

local function AddSearchRecord(records, seenRecords, pageInfo, label, anchor, kind, extraParts, literalLabel)
    if M.SupportsUnitPage and not M.SupportsUnitPage(pageInfo.key) then return end
    label = DisplaySearchText(label)
    if not IsSearchableDisplayText(label) then return end

    kind = kind or "text"
    local displayLabel = literalLabel and label or SearchDisplayText(label)
    if displayLabel == "" then displayLabel = label end
    local displayHint = SearchHint(pageInfo, anchor)
    local hint = (kind == "faq") and "" or displayHint
    local parts = {}
    AddSearchText(parts, label)
    if kind ~= "faq" then
        AddSearchText(parts, hint)
        AddSearchText(parts, pageInfo.label)
        AddSearchText(parts, pageInfo.group)
        AddSearchText(parts, pageInfo.title)
    end
    if kind == "page" then
        AddRawSearchText(parts, SEARCH_KEYWORDS[pageInfo.key])
    end
    if kind == "toggle" then
        AddToggleQuestionSearchText(parts, label)
    end
    if extraParts then
        for i = 1, #extraParts do AddSearchText(parts, extraParts[i]) end
    end

    local idLabelNorm = NormalizeSearchText(label)
    local idHintNorm = NormalizeSearchText(hint)
    local recordId = tostring(pageInfo.key or "") .. "\031"
        .. tostring(kind or "") .. "\031"
        .. tostring(anchor or "") .. "\031"
        .. idLabelNorm .. "\031" .. idHintNorm
    if seenRecords and seenRecords[recordId] then return end
    if seenRecords then seenRecords[recordId] = true end

    displayHint = DisplaySearchText(displayHint)
    local displayGroup, displayTitle, titleNorm, groupNorm = "", "", "", ""
    if kind ~= "faq" then
        local groupSource = pageInfo.group or ""
        local titleSource = pageInfo.title or pageInfo.label or ""
        local localeKey = SEARCH_STATE.localeKey or SearchEffectiveLocale()
        local cached = pageInfo._msuf2SearchPageTextCache
        if not cached
            or cached.localeKey ~= localeKey
            or cached.groupSource ~= groupSource
            or cached.titleSource ~= titleSource
        then
            displayGroup = SearchDisplayText(groupSource)
            displayTitle = SearchDisplayText(titleSource)
            cached = {
                localeKey = localeKey,
                groupSource = groupSource,
                titleSource = titleSource,
                displayGroup = displayGroup,
                displayTitle = displayTitle,
                groupNorm = NormalizeSearchText(displayGroup),
                titleNorm = NormalizeSearchText(displayTitle),
            }
            pageInfo._msuf2SearchPageTextCache = cached
        else
            displayGroup, displayTitle = cached.displayGroup, cached.displayTitle
        end
        groupNorm, titleNorm = cached.groupNorm, cached.titleNorm
    end
    local labelNorm = displayLabel == label and idLabelNorm or NormalizeSearchText(displayLabel)
    local hintNorm = (kind == "faq") and "" or (displayHint == hint and idHintNorm or NormalizeSearchText(displayHint))
    local haystackText = table.concat(parts, " ")
    if kind ~= "faq" and kind ~= "page" and #haystackText > SEARCH_CONTROL_HAYSTACK_MAX_LEN then
        haystackText = SearchText.Utf8BytePrefix(haystackText, SEARCH_CONTROL_HAYSTACK_MAX_LEN)
    end
    local haystackNorm = NormalizeSearchText(haystackText)
    local record = {
        key = pageInfo.key,
        label = displayLabel,
        group = displayGroup,
        title = displayTitle,
        hint = displayHint,
        kind = kind,
        anchor = anchor,
        labelNorm = labelNorm,
        sourceLabelNorm = labelNorm ~= idLabelNorm and idLabelNorm or nil,
        groupNorm = groupNorm,
        titleNorm = titleNorm,
        hintNorm = hintNorm,
        haystack = haystackNorm,
        tokenLimit = (kind ~= "faq" and kind ~= "page")
            and SEARCH_CONTROL_MAX_TOKENS
            or SEARCH_MAX_RECORD_TOKENS,
        order = records and #records + 1 or 1,
    }
    if records then records[#records + 1] = record end
    return record
end

local function SearchIdentityComponent(value)
    local text = tostring(value or "")
    if not text:find("[%%\031%.]") then return text end
    -- Search identities are baked into a Lua long-string. Escape the separator
    -- and dotted catalog IDs so code analyzers cannot mistake this derived
    -- routing key for a SavedVariables setting path.
    text = text:gsub("%%", "%%25")
    text = text:gsub("\031", "%%1F")
    text = text:gsub("%.", "%%2E")
    return text
end

local function CatalogSearchIdentity(kind, pageKey, ...)
    local parts = { kind, SearchIdentityComponent(pageKey) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = SearchIdentityComponent(select(i, ...))
    end
    return table.concat(parts, "\031")
end

BuildRegistrySearchRecord = function(entry, pageInfos)
    if type(entry) ~= "table" then return nil end
    local data = entry._metadata
    local widget = entry.widget
    local catalog = M.RuntimeControlCatalog.GetForWidget(widget)
    if catalog then
        data[18], data[3], data[4] = catalog.controlId, catalog.identityKey, catalog.controlPath
        data[10], data[11] = catalog.settingKey, catalog.actionKey
    end
    local setting, keywords = data[10], data[16]
    local prepareKind, prepareValue = data[7], data[8]
    local declaredSetting
    if widget then
        local kind, value
        kind, value, declaredSetting = Search.ResolveExactPreparation(widget._msuf2ExactTargetContracts, setting)
        if not prepareKind then prepareKind, prepareValue = kind, value end
        if kind ~= prepareKind or value ~= prepareValue then declaredSetting = nil end
    end
    if not M.SupportsSearchTarget(entry.pageKey, setting, prepareKind, prepareValue) then return nil end
    -- One build shares a page's info (and the page text cache AddSearchRecord
    -- keeps on it) across that page's controls.
    local info = pageInfos and pageInfos[entry.pageKey]
    if not info then
        info = BuildSearchPageInfoForKey(entry.pageKey)
        if pageInfos and entry.pageKey ~= nil then
            info._msuf2SearchHintMemo = {}
            pageInfos[entry.pageKey] = info
        end
    end
    local extra = {}
    AddValuesSearchText(extra, data[1])
    if type(keywords) == "string" then
        AddSearchText(extra, keywords)
    elseif type(keywords) == "table" then
        for i = 1, #keywords do AddSearchText(extra, keywords[i]) end
    end
    AddControlQuestionSearchText(extra, entry.label, entry.kind, data[1])
    AddSearchText(extra, data[17])
    local rec = AddSearchRecord(nil, nil, info, entry.label, entry.anchor, entry.kind or "control", extra,
        widget and widget._msuf2LiteralSearchLabel)
    if rec then
        rec.controlId, rec.controlPath, rec.actionKey = data[18], data[4], data[11]
        rec.sectionId = data[5]
        -- Unbound headings and section actions still have an exact accordion
        -- owner. Its marker is set after construction-time search registration.
        local parent = entry.widget
        while parent and not rec.sectionId do
            local section = parent._msuf2CollapsibleEntry
            rec.sectionId = parent._msuf2SectionId or (section and section.sectionId)
            parent = parent.GetParent and parent:GetParent() or nil
        end
        local controlId = tostring(data[18] or "")
        local controlPath = tostring(data[4] or "")
        local settingKey = tostring(setting or "")
        local actionKey = tostring(data[11] or "")
        if controlId ~= "" then
            rec.searchIdentity = CatalogSearchIdentity("id", entry.pageKey, controlId)
        elseif controlPath ~= "" then
            rec.searchIdentity = CatalogSearchIdentity("path", entry.pageKey, controlPath)
        elseif settingKey ~= "" then
            rec.searchIdentity = CatalogSearchIdentity("setting", entry.pageKey, settingKey)
        elseif actionKey ~= "" then
            rec.searchIdentity = CatalogSearchIdentity(
                "action", entry.pageKey, actionKey, rec.labelNorm or "", rec.hint or "")
        else
            rec.searchIdentity = CatalogSearchIdentity(
                "display", entry.pageKey, rec.kind or "", rec.labelNorm or "", rec.hint or "")
        end
        rec.answer = data[17]
        if controlId ~= "" or settingKey ~= "" then
            rec.exactTarget = {
                pageKey = entry.pageKey,
                settingKey = (setting ~= nil and setting ~= "") and setting or declaredSetting,
                controlId = data[18],
                sectionId = rec.sectionId,
                identityKey = data[3],
                controlPath = data[4],
                label = entry.label,
                prepareKind = prepareKind, prepareValue = prepareValue,
            }
        end

    end
    return rec
end

--- One static index file serves several clients: Midnight and WoW Forever share one,
--- Classic Era, TBC and Mists the other, and each keeps every row any of its clients
--- builds. A row for a control only some of them have is tied here, by its search
--- identity, to the MSUF.Client capability that decides the control; every other
--- client drops it. The client is read once, on the first static record pass.

Parts.AddSearchRecord = AddSearchRecord
Parts.BuildRegistrySearchRecord = BuildRegistrySearchRecord
Parts.BuildSearchPageInfoForKey = BuildSearchPageInfoForKey
Parts.BuildSearchPageInfos = BuildSearchPageInfos
Parts.CatalogSearchIdentity = CatalogSearchIdentity
Parts.ClearSearchRegistryPage = ClearSearchRegistryPage
Parts.IsSearchableDisplayText = IsSearchableDisplayText
