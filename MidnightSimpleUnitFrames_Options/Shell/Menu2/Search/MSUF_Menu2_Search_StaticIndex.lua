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

-- Contracts carry exact view identities. A multi-view selector without one
-- matching setting is deliberately ambiguous and must not guess a destination.
local PREPARE_KINDS = { groupSizingTab = true, groupScope = true, groupAuraWorkspace = true,
    unitAuraWorkspace = true, unitAlphaTab = true }
local function ConsiderPreparation(kind, value, score, ambiguous, k, v, setting, settingKey)
    if not PREPARE_KINDS[k] then return kind, value, score, ambiguous end
    local rank = settingKey and settingKey ~= "" and setting == settingKey and 2
        or (setting == "*" or setting == true) and 1 or 0
    if rank > score then return k, v, rank, false end
    if rank > 0 and rank == score and (kind ~= k or value ~= v) then ambiguous = true end
    return kind, value, score, ambiguous
end
function Search.ResolveExactPreparation(contracts, settingKey)
    local kind, value, score, ambiguous = nil, nil, 0, false
    if type(contracts) == "string" then
        for k, v, setting in contracts:gmatch("([^|=]+)=([^|=]+)=([^|]+)") do
            kind, value, score, ambiguous = ConsiderPreparation(kind, value, score, ambiguous, k, v, setting, settingKey)
        end
    elseif type(contracts) == "table" then
        for k, values in pairs(contracts) do
            for v, setting in pairs(values) do
                kind, value, score, ambiguous = ConsiderPreparation(kind, value, score, ambiguous, k, v, setting, settingKey)
            end
        end
    end
    if not ambiguous then return kind, value end
end

local function DecodeLine(decoder, line)
    local EnsurePage, records, hintCache = decoder.EnsurePage, decoder.records, decoder.hintCache
    local pageKey, label, kind, settingKey, actionKey, hint, labelNorm, searchIdentity,
        exactSectionId, exactTargetKinds, exactTargetContracts, haystack =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if pageKey and pageKey ~= "" then
        local encodedPage, encodedControl = searchIdentity:match("^id\031([^\031]+)\031([^\031]+)$")
        local controlId = DecodeIdentityPart(encodedControl)
        if DecodeIdentityPart(encodedPage) ~= pageKey or not controlId
            or not controlId:match("^[%w_%.:/%-]+$") then controlId = nil end
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

        local prepareKind, prepareValue = Search.ResolveExactPreparation(exactTargetContracts, settingKey)
        local count = decoder.count + 1
        decoder.count = count
        records[count] = {
            key = pageKey,
            label = displayLabel,
            kind = kind ~= "" and kind or "control",
            hint = displayHint,
            title = page.title,
            group = page.group,
            labelNorm = labelNorm,
            searchIdentity = searchIdentity,
            titleNorm = page.titleNorm,
            groupNorm = page.groupNorm,
            hintNorm = hintNorm,
            haystack = haystack,
            tokenLimit = CONTROL_TOKEN_LIMIT,
            static = true,
            exactTarget = (controlId or settingKey ~= "" or actionKey ~= "") and {
                controlId = controlId,
                pageKey = pageKey,
                settingKey = settingKey ~= "" and settingKey or nil,
                actionKey = actionKey ~= "" and actionKey or nil,
                sectionId = exactSectionId ~= "" and exactSectionId or nil,
                prepareKind = prepareKind,
                prepareValue = prepareValue,
                prepareKinds = exactTargetKinds ~= "" and exactTargetKinds or nil,
                prepareContracts = exactTargetContracts ~= "" and exactTargetContracts or nil,
                label = displayLabel,
            } or nil,
        }
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
        decoder = { lines = blob:gmatch("[^\n]+"), records = {}, count = 0, hintCache = {}, EnsurePage = EnsurePage }
        state.decoder = decoder
    end
    for line in decoder.lines do
        DecodeLine(decoder, line)
        if deadline and debugprofilestop() >= deadline then return nil end
    end
    state.decoder = nil
    -- The decoded records own their own substrings now, so the source blob can go.
    Search.StaticIndexBlob = nil
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
    if not state.records then
        if CombatLocked() then return EMPTY end
        state.records = Decode()
        state.localeKey = LocaleKey()
    end
    return state.records
end

--- Decodes until the deadline (debugprofilestop milliseconds): true once
--- GetRecords has its records without further work. The sliced search index
--- build calls it; GetRecords finishes whatever a slice left.
function StaticIndex.Advance(deadline)
    if not state.records then
        if CombatLocked() then return false end
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
    if type(Search.StaticIndexBlob) == "string" then state.records, state.decoder = nil, nil end
    state.localeKey = nil
end
