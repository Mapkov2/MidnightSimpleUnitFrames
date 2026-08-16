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
}

local function Normalize(text)
    local normalize = Search.Text and Search.Text.NormalizeSearchText
    if type(normalize) ~= "function" then return tostring(text or "") end
    return normalize(text)
end

local InvokeStaticProvider = M.InvokeBoundary or pcall

local function Translate(text)
    if type(M.Tr) ~= "function" then return text end
    local ok, translated = InvokeStaticProvider(M.Tr, text)
    if ok and type(translated) == "string" and translated ~= "" then return translated end
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

local function Decode()
    local blob = Search.StaticIndexBlob
    if type(blob) ~= "string" or blob == "" then return {} end

    local _, EnsurePage = BuildPageInfo()
    local records, count = {}, 0

    for line in blob:gmatch("[^\n]+") do
        local pageKey, label, kind, settingKey, actionKey, hint, labelNorm, searchIdentity,
            exactSectionId, exactTargetKinds, exactTargetContracts, haystack =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if pageKey and pageKey ~= "" then
            local page = EnsurePage(pageKey)
            local displayLabel = Translate(label)
            -- The baked text is English. The localized label becomes the
            -- primary scoring label and the English wording stays scorable as
            -- labelNormAlt, so community terminology (Wago/Discord guides)
            -- keeps its full label bonuses on localized clients.
            local labelNormAlt
            if displayLabel ~= label then
                local localizedNorm = Normalize(displayLabel)
                if localizedNorm ~= "" and localizedNorm ~= labelNorm then
                    labelNormAlt = labelNorm
                    labelNorm = localizedNorm
                    haystack = haystack .. " " .. localizedNorm
                end
            end
            local displayHint = hint
            if displayHint ~= "" then
                -- Best-effort per-segment translation of the baked English
                -- section path ("Buff > Filters"), so breadcrumbs stop reading
                -- half localized, half English.
                local translated = {}
                for segment in displayHint:gmatch("[^>]+") do
                    segment = segment:gsub("^%s+", ""):gsub("%s+$", "")
                    if segment ~= "" then translated[#translated + 1] = Translate(segment) end
                end
                if #translated > 0 then displayHint = table.concat(translated, " > ") end
                displayHint = page.title .. " > " .. displayHint
            else
                displayHint = page.title
            end
            local hintNorm = Normalize(displayHint)
            -- The clause scorer gates on the haystack before it inspects the page
            -- title, so page/group words have to be present here too.
            haystack = haystack .. " " .. hintNorm
            if page.groupNorm ~= "" then haystack = haystack .. " " .. page.groupNorm end

            count = count + 1
            records[count] = {
                key = pageKey,
                label = displayLabel,
                kind = kind ~= "" and kind or "control",
                hint = displayHint,
                title = page.title,
                group = page.group,
                labelNorm = labelNorm,
                labelNormAlt = labelNormAlt,
                searchIdentity = searchIdentity,
                titleNorm = page.titleNorm,
                groupNorm = page.groupNorm,
                hintNorm = hintNorm,
                haystack = haystack,
                tokenLimit = CONTROL_TOKEN_LIMIT,
                static = true,
                exactTarget = (settingKey ~= "" or actionKey ~= "") and {
                    pageKey = pageKey,
                    settingKey = settingKey ~= "" and settingKey or nil,
                    actionKey = actionKey ~= "" and actionKey or nil,
                    sectionId = exactSectionId ~= "" and exactSectionId or nil,
                    prepareKinds = exactTargetKinds ~= "" and exactTargetKinds or nil,
                    prepareContracts = exactTargetContracts ~= "" and exactTargetContracts or nil,
                    label = displayLabel,
                } or nil,
            }
        end
    end

    -- The blob is deliberately retained: a menu-language change without a
    -- reload rebuilds the decoded records from it (see GetRecords), which was
    -- impossible while the blob was released after the first decode.
    return records
end

local function LocaleKey()
    local effective = Search.Text and Search.Text.SearchEffectiveLocale
    if type(effective) == "function" then
        local ok, key = InvokeStaticProvider(effective)
        if ok and key then return key end
    end
    return "?"
end

local EMPTY = {}

local function CombatLocked()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

--- Returns the decoded static records, building them on first use.
--- A menu-language change without a reload ("Not now" on the reload prompt)
--- invalidates the decoded set: the locale key is compared on every call and
--- a mismatch re-decodes from the retained blob, so labels can never stay in
--- the previous session language.
---
--- The decode is the only non-trivial cost this module has, so it never runs
--- in combat. Callers are already gated; this is the backstop that keeps a stray
--- entry point from spending it at the worst possible moment.
function StaticIndex.GetRecords()
    if state.records and state.localeKey ~= LocaleKey() then
        state.records = nil
    end
    if not state.records then
        if CombatLocked() then return EMPTY end
        state.records = Decode()
        state.localeKey = LocaleKey()
    end
    return state.records
end

--- True once the blob has been decoded, so callers can avoid forcing the cost.
function StaticIndex.IsDecoded()
    return state.records ~= nil
end

function StaticIndex.ClearCache()
    state.records = nil
    state.localeKey = nil
end
