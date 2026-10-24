--- Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex.lua
--- Complete, pre-normalized search coverage for pages the player never opened.
---
--- Records only ever entered the search index while a page was being built, so a
--- setting on an unvisited page was unreachable. This module decodes the generated
--- inventory in MSUF_Menu2_Search_StaticIndex_Data.lua instead, which needs no page
--- construction at all.
---
--- Cost contract: the generated file is a single string constant, so login pays only
--- its parse. The split into records happens the first time the player actually uses
--- search, and the blob is released afterwards. Label/haystack text is normalized at
--- generation time, so no NormalizeSearchText work happens here beyond the localized
--- label overlay.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Search = M.Search or {}
M.Search = Search

local StaticIndex = Search.StaticIndex or {}
Search.StaticIndex = StaticIndex

local CONTROL_TOKEN_LIMIT = 36
-- Includes the retained source blob, columns and localized strings, after full GC.
-- Fuzzy/query caches belong to IndexQuery and are discarded on menu quiescence.
StaticIndex.HEAP_BUDGET_KIB = 5632
local FIELD = {
    label = 1, kind = 2, hint = 3, labelNorm = 4, searchIdentity = 5,
    hintNorm = 6, haystack = 7, settingKey = 8, actionKey = 9, sectionId = 10,
    prepareKinds = 11, prepareContracts = 12, prepareKind = 14, prepareValue = 15,
}
local PAGE_FIELD = { title = "title", group = "group", titleNorm = "titleNorm", groupNorm = "groupNorm", key = "key", pageKey = "key" }

-- A row is just its numeric ID. All immutable fields live in dense columns;
-- page metadata is shared by page ID. Mutable ranking/fuzzy fields stay on the row.
local function ColumnField(row, key)
    local store, id = getmetatable(row), row[1]
    if key == "controlId" then return StaticIndex.ControlId(row) end
    local column = FIELD[key]
    if column then return store.columns[column][id] end
    local pageField = PAGE_FIELD[key]
    if pageField then return store.pages[store.columns[13][id]][pageField] end
end
function StaticIndex.TargetField(row, key)
    if getmetatable(row) and getmetatable(row)._staticColumns then return ColumnField(row, key) end
    local target = row.exactTarget
    return target and target[key]
end
local function RecordField(row, key)
    if key == "static" then return true end
    if key == "tokenLimit" then return CONTROL_TOKEN_LIMIT end
    if key ~= "exactTarget" then
        -- Target-only fields keep the public row shape they had before columns.
        if (FIELD[key] and FIELD[key] > 7) or key == "controlId" or key == "pageKey" then return nil end
        return ColumnField(row, key)
    end
    local controlId, settingKey, actionKey = ColumnField(row, "controlId"), ColumnField(row, "settingKey"), ColumnField(row, "actionKey")
    if not controlId and not settingKey and not actionKey then return nil end
    local target = { pageKey = ColumnField(row, "key"), label = ColumnField(row, "label"), controlId = controlId }
    for field in pairs(FIELD) do
        if field ~= "kind" and field ~= "hint" and field ~= "labelNorm" and field ~= "searchIdentity"
            and field ~= "hintNorm" and field ~= "haystack" then target[field] = ColumnField(row, field) end
    end
    rawset(row, "exactTarget", target)
    return target
end

local state = {
    records = nil,
    localeKey = nil,
    -- A decode in progress (StaticIndex.Advance): line iterator and records so far.
    decoder = nil,
}

local function Normalize(text)
    local normalize = Search.Text and Search.Text.NormalizeSearchText
    if type(normalize) ~= "function" then return tostring(text or "") end
    return normalize(text)
end

local function Translate(text)
    if type(M.Tr) ~= "function" then return text end
    local translated = M.Tr(text)
    if type(translated) == "string" and translated ~= "" then return translated end
    return text
end

--- Page titles and nav group headers are localized, so they are resolved here rather
--- than baked. There are only a few dozen pages, unlike the ~1.7k control rows.
local function BuildPageInfo()
    local info = {}
    local function Ensure(pageKey)
        local entry = info[pageKey]
        if not entry then
            local spec = M.pages and M.pages[pageKey]
            local title = Translate((spec and spec.title) or pageKey)
            entry = {
                title = title,
                titleNorm = Normalize(title),
                group = "",
                groupNorm = "",
            }
            info[pageKey] = entry
        end
        return entry
    end

    local groupLabels = {}
    local navItems = M.navItems or {}
    for i = 1, #navItems do
        local item = navItems[i]
        if type(item) == "table" then
            if item.header then groupLabels[item.id or item.header] = item.header end
            if item.title then groupLabels[item.id or item.title] = item.title end
        end
    end
    for i = 1, #navItems do
        local item = navItems[i]
        if type(item) == "table" and type(item.key) == "string" and item.key ~= "" then
            local entry = Ensure(item.key)
            local group = item.group and groupLabels[item.group]
            if group then
                entry.group = Translate(group)
                entry.groupNorm = Normalize(entry.group)
            end
        end
    end
    return info, Ensure
end

--- The baked breadcrumb is English. Each segment the locale knows is shown
--- translated, and since the hint joins the haystack, a section is then found by
--- its translated name too (the baked haystack keeps the English one). These are
--- path segments, not locale keys, so the lookup skips M.Tr's key tracking.
local function TranslateHint(hint, cache)
    local cached = cache[hint]
    if cached then return cached end
    local parts, changed = {}, false
    for segment in hint:gmatch("[^>]+") do
        local text = segment:match("^%s*(.-)%s*$")
        local localized = MSUF.Translate(text)
        if localized ~= "" and localized ~= text then changed = true else localized = text end
        parts[#parts + 1] = localized
    end
    cached = changed and table.concat(parts, " > ") or hint
    cache[hint] = cached
    return cached
end

-- Every "%XX" escape (either hex case) to its byte: a lookup instead of a
-- callback per escape.
local HEX_ESCAPE_BYTES = {}
do
    local digits = "0123456789abcdefABCDEF"
    for i = 1, #digits do
        for j = 1, #digits do
            local pair = digits:sub(i, i) .. digits:sub(j, j)
            HEX_ESCAPE_BYTES[pair] = string.char(tonumber(pair, 16))
        end
    end
end

local function DecodeIdentityPart(value)
    return value and value:gsub("%%(%x%x)", HEX_ESCAPE_BYTES)
end

local function ValidEncodedControl(value)
    if not value or value == "" or value:find("[^%w_%%%.:/%-]") then return false end
    local offset = 1
    while true do
        local first = value:find("%", offset, true)
        if not first then return true end
        local decoded = HEX_ESCAPE_BYTES[value:sub(first + 1, first + 2)]
        if not decoded or decoded:find("[^%w_%.:/%-]") then return false end
        offset = first + 3
    end
end

-- Control IDs are needed only for navigation. Keep the encoded identity once;
-- thousands of decoded duplicate ID strings need not live beside the source.
function StaticIndex.ControlId(row)
    local store, id = getmetatable(row), row[1]
    if not store.columns[16][id] then return nil end
    local encoded = store.columns[5][id]:match("^id\031[^\031]+\031([^\031]+)$")
    return DecodeIdentityPart(encoded)
end

-- Contracts carry exact view identities. A multi-view selector without one
-- matching setting is deliberately ambiguous and must not guess a destination.
-- Every kind a contract names is a view: the generator proves each kind and
-- value against the control's own prepare hook (a kind without a hook fails
-- the build), and Catalog.ResolveExactTarget re-checks the hook at run time.
-- So the contract is the whole list. A hand-kept list left the portrait tabs,
-- texture layer views and the Bars scope without a prepareKind, and the tab
-- switch never ran for them.
-- A control whose setting key depends on the selected view has none of its own
-- (the texture layer slot controls, the Bars scope controls). When its contract
-- names exactly one view, that view's setting is the control's key: the third
-- result, which the prepare hook compares against the target's settingKey. Rank
-- 3 is the control's own key, 2 a wildcard, 1 that key-less single view.
local function ConsiderPreparation(kind, value, score, ambiguous, picked, k, v, setting, settingKey)
    local hasKey = settingKey ~= nil and settingKey ~= ""
    local rank = hasKey and setting == settingKey and 3
        or (setting == "*" or setting == true) and 2
        or (not hasKey and type(setting) == "string") and 1 or 0
    if rank > score then return k, v, rank, false, setting end
    if rank > 0 and rank == score and (kind ~= k or value ~= v) then ambiguous = true end
    return kind, value, score, ambiguous, picked
end
local function TrackPreparationAlias(aliasKey, ambiguous, setting)
    if type(setting) ~= "string" or setting == "*" then return aliasKey, ambiguous end
    if aliasKey and aliasKey ~= setting then ambiguous = true end
    return setting, ambiguous
end
function Search.ResolveExactPreparation(contracts, settingKey)
    local kind, value, score, ambiguous, picked = nil, nil, 0, false, nil
    local aliasKey, aliasAmbiguous
    if type(contracts) == "string" then
        for k, v, setting in contracts:gmatch("([^|=]+)=([^|=]+)=([^|]+)") do
            aliasKey, aliasAmbiguous = TrackPreparationAlias(aliasKey, aliasAmbiguous, setting)
            kind, value, score, ambiguous, picked =
                ConsiderPreparation(kind, value, score, ambiguous, picked, k, v, setting, settingKey)
        end
    elseif type(contracts) == "table" then
        for k, values in pairs(contracts) do
            for v, setting in pairs(values) do
                aliasKey, aliasAmbiguous = TrackPreparationAlias(aliasKey, aliasAmbiguous, setting)
                kind, value, score, ambiguous, picked =
                    ConsiderPreparation(kind, value, score, ambiguous, picked, k, v, setting, settingKey)
            end
        end
    end
    if not ambiguous then
        if picked == "*" or picked == true then
            picked = not aliasAmbiguous and aliasKey or nil
        end
        return kind, value, picked
    end
end

local function DecodeLine(decoder, line)
    local EnsurePage, records, hintCache = decoder.EnsurePage, decoder.records, decoder.hintCache
    local pageKey, label, kind, settingKey, actionKey, hint, labelNorm, searchIdentity,
        exactSectionId, exactTargetKinds, exactTargetContracts, haystack =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if pageKey and pageKey ~= "" then
        -- The compact extension keeps the twelve TSV columns and accepts older
        -- blobs too. Both pieces are already normalized by the generator.
        local base, metadataNorm = haystack:match("^(.-)|(.*)$")
        if base then haystack = metadataNorm ~= "" and (base .. " " .. metadataNorm) or base end
        local encodedPage, encodedControl = searchIdentity:match("^id\031([^\031]+)\031([^\031]+)$")
        local hasControlId = DecodeIdentityPart(encodedPage) == pageKey and ValidEncodedControl(encodedControl)
        local page = EnsurePage(pageKey)
        local displayLabel = Translate(label)
        -- The baked text is English. A localized label is added on top instead of
        -- replacing it, so a player can find a setting by either wording.
        if displayLabel ~= label then
            local localizedNorm = Normalize(displayLabel)
            if localizedNorm ~= "" and localizedNorm ~= labelNorm then
                labelNorm = localizedNorm
                haystack = haystack .. " " .. localizedNorm
            end
        end
        local displayHint, localizedHint = hint, hint
        if displayHint ~= "" then
            localizedHint = TranslateHint(hint, hintCache)
            displayHint = page.title .. " > " .. localizedHint
        else
            displayHint = page.title
        end
        local hintNorm = Normalize(displayHint)
        -- A translated breadcrumb keeps its English words for scoring as well.
        if localizedHint ~= hint then hintNorm = hintNorm .. " " .. Normalize(hint) end
        -- The clause scorer gates on the haystack before it inspects the page
        -- title, so page/group words have to be present here too.
        if page.groupNorm ~= "" then
            haystack = haystack .. " " .. hintNorm .. " " .. page.groupNorm
        else
            haystack = haystack .. " " .. hintNorm
        end

        local prepareKind, prepareValue, declaredSetting = Search.ResolveExactPreparation(exactTargetContracts, settingKey)
        if settingKey == "" then settingKey = declaredSetting or "" end
        local count = decoder.count + 1
        decoder.count = count
        local pageId = decoder.pageIds[pageKey]
        if not pageId then
            pageId = #decoder.pages + 1
            decoder.pageIds[pageKey] = pageId
            page.key = pageKey
            decoder.pages[pageId] = page
        end
        local columns = decoder.columns
        columns[1][count], columns[2][count] = displayLabel, kind ~= "" and kind or "control"
        columns[3][count], columns[4][count] = displayHint, labelNorm
        columns[5][count], columns[6][count], columns[7][count] = searchIdentity, hintNorm, haystack
        columns[8][count] = settingKey ~= "" and settingKey or nil
        columns[9][count] = actionKey ~= "" and actionKey or nil
        columns[10][count] = exactSectionId ~= "" and exactSectionId or nil
        columns[11][count] = exactTargetKinds ~= "" and exactTargetKinds or nil
        columns[12][count] = exactTargetContracts ~= "" and exactTargetContracts or nil
        columns[13][count], columns[14][count], columns[15][count] = pageId, prepareKind, prepareValue
        columns[16][count] = hasControlId
        records[count] = setmetatable({ count }, decoder.rowMeta)
    end
end

--- Decodes the blob, or with a deadline as much of it as fits: returns the
--- records once every line is done, nil while lines remain (state.decoder keeps
--- the place). Line order and record contents do not depend on the slicing.
local function Decode(deadline)
    local decoder = state.decoder
    if not decoder then
        local blob = Search.StaticIndexBlob
        if type(blob) ~= "string" or blob == "" then return {} end
        local _, EnsurePage = BuildPageInfo()
        local columns, pages = {}, {}
        for i = 1, 16 do columns[i] = {} end
        decoder = { lines = blob:gmatch("[^\n]+"), records = {}, count = 0, hintCache = {}, EnsurePage = EnsurePage,
            columns = columns, pages = pages, pageIds = {} }
        decoder.rowMeta = { __index = RecordField, columns = columns, pages = pages, _staticColumns = true }
        state.decoder = decoder
    end
    for line in decoder.lines do
        DecodeLine(decoder, line)
        if deadline and debugprofilestop() >= deadline then return nil end
    end
    state.decoder = nil
    -- Keep the compact source for a sliced rebuild after menu-close cache release.
    return decoder.records
end

local function LocaleKey()
    local effective = Search.Text and Search.Text.SearchEffectiveLocale
    if type(effective) == "function" then
        local key = effective()
        if key then return key end
    end
    return "?"
end

local EMPTY = {}

local function CombatLocked()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

--- Returns the decoded static records, building them on first use.
--- Menu language changes force a reload (see M.ApplyLocaleSelection), so the decoded set
--- cannot go stale within a session and is built exactly once.
---
--- The first decode is the only non-trivial cost this module has, so it never runs
--- in combat. Callers are already gated; this is the backstop that keeps a stray
--- entry point from spending it at the worst possible moment.
function StaticIndex.GetRecords()
    return state.records or EMPTY
end

--- Decodes until the deadline (debugprofilestop milliseconds): true once
--- GetRecords has its records without further work. Every reader uses this sliced build.
function StaticIndex.Advance(deadline)
    if not state.records then
        if CombatLocked() then return false end
        local now = debugprofilestop()
        deadline = math.min(deadline or (now + 1), now + 1)
        local records = Decode(deadline)
        if not records then return false end
        state.records = records
        state.localeKey = LocaleKey()
    end
    return true
end

--- True once the blob has been decoded, so callers can avoid forcing the cost.
function StaticIndex.IsDecoded()
    return state.records ~= nil
end

function StaticIndex.ClearCache()
    state.records, state.decoder = nil, nil
    state.localeKey = nil
end
