local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry

local K = A.Knowledge or {}
A.Knowledge = K

-- Lightweight knowledge search for Assistant help/support answers.
-- It indexes registry metadata and curated snippets so the assistant can explain features
-- without reading live frame state or mutating settings.
local MAX_RESULTS = 6
local INDEX_VERSION = 3
local SEARCH_CACHE_LIMIT = 32
local SEARCH_TEXT_LIMIT = 360
local DISCORD_INVITE = "https://discord.gg/2Gf9b2Wprz"

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    text = tostring(text or ""):lower()
    text = text:gsub("\195\164", "ae")
    text = text:gsub("\195\182", "oe")
    text = text:gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    text = Trim(text)
    text = text:gsub("target%s+of%s+target", "targettarget")
    text = text:gsub("target%s+target", "targettarget")
    text = text:gsub("focus%s+target", "focustarget")
    text = text:gsub("cast%s+bar", "castbar")
    text = text:gsub("power%s+bar", "powerbar")
    text = text:gsub("health%s+bar", "healthbar")
    text = text:gsub("unit%s+frames", "unitframes")
    return text
end

local function AddUnique(list, seen, value)
    value = Trim(value)
    if value == "" then return end
    local norm = Normalize(value)
    if norm == "" or seen[norm] then return end
    seen[norm] = true
    list[#list + 1] = value
end

local function AddSearchSnippet(list, seen, value)
    value = Trim(value)
    if value == "" then return end
    if #value > SEARCH_TEXT_LIMIT then value = value:sub(1, SEARCH_TEXT_LIMIT) end
    AddUnique(list, seen, value)
end

local function AddMany(list, seen, values)
    if type(values) == "string" then
        if values:find("|", 1, true) then
            for value in values:gmatch("[^|]+") do AddUnique(list, seen, value) end
        else
            AddUnique(list, seen, values)
        end
        return
    end
    if type(values) ~= "table" then return end
    for i = 1, #values do AddUnique(list, seen, values[i]) end
end

local function SplitTokens(text)
    local out, seen = {}, {}
    local norm = Normalize(text)
    for token in norm:gmatch("%S+") do
        if #token >= 2 and not seen[token] then
            seen[token] = true
            out[#out + 1] = token
        end
    end
    return out
end

local function StringContainsPhrase(haystack, phrase)
    phrase = Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. haystack .. " "):find(" " .. phrase .. " ", 1, true) ~= nil or haystack:find(phrase, 1, true) ~= nil
end

local function CurrentPageKey()
    return type(M.activeKey) == "string" and M.activeKey or "home"
end

local PAGE_TO_UNIT = {
    uf_player = "player",
    uf_target = "target",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_boss = "boss",
}

local PAGE_FRAME_TYPES = {
    opt_castbar = { castbar = true },
    opt_bars = { bars = true, globalBars = true },
    opt_colors = { colors = true, bars = true, fonts = true, castbar = true, classPower = true, gameplay = true },
    opt_fonts = { fonts = true },
    opt_misc = { misc = true, dashboard = true },
    classpower = { classPower = true },
    gameplay = { gameplay = true },
    profiles = { profiles = true },
    gf_layout = { group = true },
    gf_bars = { group = true },
    gf_indicators = { group = true },
    gf_auras = { groupAura = true, group = true },
    auras3 = { aura = true },
    auras3_buffs = { aura = true },
    auras3_debuffs = { aura = true },
    auras3_styling = { aura = true },
    auras3_filters = { aura = true },
}

local PAGE_CATEGORY_TERMS = {
    opt_castbar = { "castbar" },
    opt_bars = { "bars", "bar", "outline", "border", "texture", "gradient", "background" },
    opt_colors = { "colors", "colour", "color", "palette" },
    opt_fonts = { "fonts", "font", "text" },
    opt_misc = { "misc", "dashboard", "minimap", "tooltip" },
    classpower = { "class resource", "class power", "resource" },
    gameplay = { "gameplay", "combat timer", "target sound", "totem" },
    profiles = { "profile", "profiles" },
    gf_layout = { "group", "layout", "party", "raid", "mythic" },
    gf_bars = { "group", "health", "text", "bars" },
    gf_indicators = { "indicator", "status", "corner" },
    gf_auras = { "group aura", "aura" },
}

local function SettingPageBoost(setting, pageKey)
    if type(setting) ~= "table" then return 0 end
    pageKey = pageKey or CurrentPageKey()
    local unit = PAGE_TO_UNIT[pageKey]
    if unit and setting.unit == unit then return 520 end
    local types = PAGE_FRAME_TYPES[pageKey]
    if types and types[setting.frameType] then return 360 end
    local category = setting._msufAssistantCategoryNorm
    if category == nil then
        category = Normalize(setting.category or "")
        setting._msufAssistantCategoryNorm = category
    end
    local terms = PAGE_CATEGORY_TERMS[pageKey]
    if type(terms) == "table" then
        for i = 1, #terms do
            if StringContainsPhrase(category, terms[i]) then return 250 end
        end
    end
    return 0
end
K.SettingPageBoost = SettingPageBoost

local function PageLabel(pageKey)
    if pageKey and M.pages and M.pages[pageKey] and M.pages[pageKey].title then return tostring(M.pages[pageKey].title) end
    if type(M.navItems) == "table" then
        for i = 1, #M.navItems do
            local item = M.navItems[i]
            if item.key == pageKey then return tostring(item.label or pageKey) end
        end
    end
    return tostring(pageKey or "Dashboard")
end

local function SettingLikelyPage(setting)
    if type(setting) ~= "table" then return nil end
    if setting.unit then
        for key, unit in pairs(PAGE_TO_UNIT) do if unit == setting.unit then return key end end
    end
    local ft = setting.frameType
    if ft == "castbar" then return "opt_castbar" end
    if ft == "fonts" then return "opt_fonts" end
    if ft == "bars" or ft == "globalBars" then return "opt_bars" end
    if ft == "classPower" then return "classpower" end
    if ft == "gameplay" then return "gameplay" end
    if ft == "group" then return "gf_bars" end
    if ft == "groupAura" then return "gf_auras" end
    if ft == "aura" then return "auras3_styling" end
    local cat = Normalize(setting.category or "")
    if cat:find("castbar", 1, true) then return "opt_castbar" end
    if cat:find("font", 1, true) then return "opt_fonts" end
    if cat:find("color", 1, true) or cat:find("colour", 1, true) then return "opt_colors" end
    if cat:find("profile", 1, true) then return "profiles" end
    return nil
end

local function ActionLikelyPage(action)
    if type(action) ~= "table" then return nil end
    local key = tostring(action.key or "")
    local typ = tostring(action.type or "")
    if key:find("profile", 1, true) or typ == "profile" then return "profiles" end
    if key:find("edit", 1, true) then return "home" end
    if typ == "navigation" then return "home" end
    if typ == "diagnostic" then return "home" end
    return nil
end

local function SearchKeywordList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        if type(list) == "table" then
            for j = 1, #list do out[#out + 1] = list[j] end
        elseif type(list) == "string" then
            if list:find("|", 1, true) then
                for keyword in list:gmatch("[^|]+") do out[#out + 1] = keyword end
            else
                out[#out + 1] = list
            end
        elseif list ~= nil then
            out[#out + 1] = tostring(list)
        end
    end
    return out
end

local function FaqEnvironment()
    local Data = M.SearchData or {}
    local env = { SearchKeywordList = SearchKeywordList }
    local names = {
        "DISPEL_DEBUFF_KEYWORDS", "HIGHLIGHT_BORDER_KEYWORDS", "DISPEL_OVERLAY_KEYWORDS",
        "DEBUFF_STRIPE_KEYWORDS", "BLIZZARD_DISPEL_KEYWORDS", "UNIT_AURA_DISPEL_KEYWORDS",
        "DASHBOARD_RECOVERY_KEYWORDS", "DASHBOARD_DISCORD_KEYWORDS", "DASHBOARD_SUPPORT_KEYWORDS",
        "DASHBOARD_WAGO_KEYWORDS", "DASHBOARD_SCALING_KEYWORDS", "DASHBOARD_CHANGELOG_KEYWORDS",
    }
    for i = 1, #names do
        local value = Data[names[i]]
        env["SEARCH_" .. names[i]] = value
        env[names[i]] = value
    end
    env.DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } }
    env.DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } }
    env.DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } }
    return env
end

local function AddIndexItem(index, item)
    item.label = Trim(item.label or item.key or item.kind or "")
    if item.label == "" then return end
    item.aliases = type(item.aliases) == "table" and item.aliases or {}
    local textParts, seen = {}, {}
    AddUnique(textParts, seen, item.key)
    AddUnique(textParts, seen, item.label)
    AddUnique(textParts, seen, item.category)
    AddUnique(textParts, seen, item.pageLabel)
    AddSearchSnippet(textParts, seen, item.description)
    AddSearchSnippet(textParts, seen, item.answer)
    AddUnique(textParts, seen, item.target)
    AddUnique(textParts, seen, item.controlType)
    AddMany(textParts, seen, item.aliases)
    AddMany(textParts, seen, item.keywords)
    item.haystack = Normalize(table.concat(textParts, " "))
    item.keyNorm = Normalize(item.key)
    item.labelNorm = Normalize(item.label)
    item.aliasNorms = {}
    for i = 1, #item.aliases do
        local aliasNorm = Normalize(item.aliases[i])
        if aliasNorm ~= "" then item.aliasNorms[#item.aliasNorms + 1] = aliasNorm end
    end
    item.tokens = SplitTokens(item.haystack)
    index.items[#index.items + 1] = item
end

local function BuildIndex()
    local index = {
        version = INDEX_VERSION,
        items = {},
        byKind = {},
        built = true,
    }
    if Registry and type(Registry.AllSettings) == "function" then
        local settings = Registry:AllSettings() or {}
        for i = 1, #settings do
            if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local setting = settings[i]
            local page = SettingLikelyPage(setting)
            AddIndexItem(index, {
                kind = "setting",
                key = setting.key,
                label = setting.label or setting.key,
                category = setting.category,
                aliases = setting.aliases,
                page = page,
                pageLabel = PageLabel(page),
                controlType = setting.type,
                description = setting.description or setting.summary,
                setting = setting,
                canApply = true,
                canOpen = page ~= nil,
                canExplain = true,
            })
        end
    end
    if Registry and type(Registry.AllActions) == "function" then
        local actions = Registry:AllActions() or {}
        for i = 1, #actions do
            if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local action = actions[i]
            local page = ActionLikelyPage(action)
            AddIndexItem(index, {
                kind = action.type == "diagnostic" and "diagnostic" or "action",
                key = action.key,
                label = action.label or action.key,
                category = action.category or action.type,
                aliases = action.aliases,
                page = page,
                pageLabel = PageLabel(page),
                controlType = action.type,
                description = action.description or action.summary,
                action = action,
                canApply = true,
                canOpen = page ~= nil,
                canExplain = true,
            })
        end
    end
    if type(M.navItems) == "table" then
        local Data = M.SearchData or {}
        for i = 1, #M.navItems do
            if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local nav = M.navItems[i]
            if nav.key then
                local aliases = {}
                if type(M.ALIASES) == "table" then
                    for alias, key in pairs(M.ALIASES) do
                        if key == nav.key then aliases[#aliases + 1] = alias end
                    end
                end
                AddMany(aliases, {}, Data.KEYWORDS and Data.KEYWORDS[nav.key])
                AddIndexItem(index, {
                    kind = "page",
                    key = nav.key,
                    label = nav.label or nav.key,
                    page = nav.key,
                    pageLabel = nav.label or nav.key,
                    aliases = aliases,
                    keywords = Data.KEYWORDS and Data.KEYWORDS[nav.key],
                    category = nav.group,
                    description = "Dashboard page.",
                    canOpen = true,
                    canExplain = true,
                })
            end
        end
    end
    local Data = M.SearchData or {}
    if type(Data.BuildFAQ) == "function" then
        local rows = Data.BuildFAQ(FaqEnvironment()) or {}
        for i = 1, #rows do
            if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local row = rows[i]
            if type(row) == "table" then
                AddIndexItem(index, {
                    kind = "faq",
                    key = "faq." .. tostring(i),
                    label = row.label,
                    page = row.pageKey,
                    pageLabel = PageLabel(row.pageKey),
                    aliases = row.keywords,
                    keywords = row.keywords,
                    answer = row.answer,
                    target = row.target,
                    description = row.answer,
                    route = row.route,
                    anchorText = row.anchorText,
                    priority = tonumber(row.priority) or 0,
                    canOpen = row.pageKey ~= nil,
                    canExplain = true,
                })
            end
        end
    end
    for i = 1, #index.items do
        if i % 32 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = index.items[i]
        index.byKind[item.kind] = index.byKind[item.kind] or {}
        index.byKind[item.kind][#index.byKind[item.kind] + 1] = item
    end
    return index
end

function K.MarkDirty()
    K.index = nil
    K.searchCache = nil
    K.searchCacheOrder = nil
end

function K.EnsureIndex()
    if type(K.index) == "table" and K.index.version == INDEX_VERSION then return K.index end
    K.index = BuildIndex()
    return K.index
end

local LOCATION_TERMS = {
    "where", "where is", "where are", "find", "search", "open", "go to", "show me", "wo", "wo ist", "finde", "suche", "oeffne",
}
local HELP_TERMS = {
    "help", "hilfe", "what is", "what are", "what can", "how", "how do", "why", "explain", "erklaere", "warum", "wie",
}

local function ContainsAny(text, list)
    for i = 1, #(list or {}) do
        if StringContainsPhrase(text, list[i]) then return true end
    end
    return false
end

local function QueryIntent(text)
    local norm = Normalize(text)
    if ContainsAny(norm, LOCATION_TERMS) then return "location" end
    if ContainsAny(norm, HELP_TERMS) then return "help" end
    return "search"
end

local QUERY_PREFIXES = {
    "where do i turn off ", "where can i turn off ", "where do i turn on ", "where can i turn on ",
    "where do i hide ", "where can i hide ", "where do i show ", "where can i show ",
    "where do i change ", "where can i change ", "where do i set ", "where can i set ",
    "where do i configure ", "where can i configure ",
    "where do i ", "where can i ", "where to ",
    "where is ", "where are ", "where ", "search for ", "search ", "find ", "show me ",
    "faq ", "explain ", "what is ", "what are ", "what can ", "how do ", "how ",
    "wo ist ", "wo ", "suche nach ", "suche ", "finde ", "zeige mir ",
    "erklaere ", "hilfe zu ", "hilfe fuer ", "hilfe fur ",
}

local function SearchQueryText(query)
    local norm = Normalize(query)
    for i = 1, #QUERY_PREFIXES do
        local prefix = QUERY_PREFIXES[i]
        if norm:sub(1, #prefix) == prefix then
            return Trim(norm:sub(#prefix + 1))
        end
    end
    return norm
end

local function ExpandQueryText(query)
    local Data = M.SearchData or {}
    local aliases = Data.QUERY_ALIASES
    if type(aliases) ~= "table" then return query end
    local norm = Normalize(query)
    local parts = { tostring(query or "") }
    local added = 0
    for token in norm:gmatch("%S+") do
        local list = aliases[token]
        if type(list) == "table" then
            for i = 1, #list do
                parts[#parts + 1] = tostring(list[i])
                added = added + 1
                if added >= 18 then return table.concat(parts, " ") end
            end
        end
    end
    return table.concat(parts, " ")
end

local function RememberCache(cache, order, key, value, limit)
    if not cache[key] then order[#order + 1] = key end
    cache[key] = value
    while #order > limit do
        local oldKey = table.remove(order, 1)
        cache[oldKey] = nil
    end
end

local function CopySearchResults(results)
    local out = {}
    for i = 1, #(results or {}) do
        local item = results[i]
        out[i] = { item = item.item, score = item.score }
    end
    return out
end

local function TokenScore(item, queryTokens, queryNorm, intent, pageKey, exactQueryNorm)
    if not item or item.haystack == "" then return 0 end
    local score = 0
    local matched = false
    local keyNorm = item.keyNorm or Normalize(item.key or "")
    local labelNorm = item.labelNorm or Normalize(item.label or "")
    local exactNorm = exactQueryNorm or queryNorm
    if keyNorm ~= "" and keyNorm == exactNorm then score = score + 1800; matched = true end
    if labelNorm == queryNorm then score = score + 600; matched = true end
    if exactNorm ~= queryNorm and labelNorm == exactNorm then score = score + 600; matched = true end
    if labelNorm:find(queryNorm, 1, true) then score = score + 280; matched = true end
    if exactNorm ~= queryNorm and labelNorm:find(exactNorm, 1, true) then score = score + 280; matched = true end
    for i = 1, #(item.aliasNorms or {}) do
        local aliasNorm = item.aliasNorms[i]
        if aliasNorm == queryNorm or aliasNorm == exactNorm then
            score = score + 760
            matched = true
            break
        elseif aliasNorm:find(queryNorm, 1, true) or (exactNorm ~= queryNorm and aliasNorm:find(exactNorm, 1, true)) then
            score = score + 320
            matched = true
            break
        end
    end
    if item.haystack:find(queryNorm, 1, true) then score = score + 180; matched = true end
    if exactNorm ~= queryNorm and item.haystack:find(exactNorm, 1, true) then score = score + 180; matched = true end
    for i = 1, #queryTokens do
        local token = queryTokens[i]
        if item.haystack:find(token, 1, true) then
            score = score + 70 + math.min(#token * 3, 30)
            matched = true
        else
            score = score - 25
        end
    end
    if not matched then return 0 end
    if item.kind == "faq" then score = score + 80 + math.min(tonumber(item.priority) or 0, 300) end
    if item.kind == "setting" then score = score + 90 end
    if item.kind == "page" then score = score + 65 end
    if item.kind == "diagnostic" then score = score + 70 end
    if intent == "location" then
        if item.kind == "setting" or item.kind == "page" or item.kind == "action" or item.kind == "diagnostic" then score = score + 260 end
        if item.kind == "faq" then score = score - 260 end
    elseif intent == "help" then
        if item.kind == "faq" then score = score + 120 end
    end
    score = score + SettingPageBoost(item.setting, pageKey)
    return score
end

local function ResultBefore(a, b)
    if not b then return true end
    if a.score ~= b.score then return a.score > b.score end
    return tostring(a.item.label or "") < tostring(b.item.label or "")
end

local function InsertTopResult(results, entry, limit)
    local pos = #results + 1
    while pos > 1 and ResultBefore(entry, results[pos - 1]) do
        pos = pos - 1
    end
    table.insert(results, pos, entry)
    if #results > limit then table.remove(results) end
end

function K.Search(query, limit, opts)
    opts = opts or {}
    local index = K.EnsureIndex()
    local pageKey = CurrentPageKey()
    local intent = QueryIntent(query)
    local cleanedQuery = SearchQueryText(query)
    local exactNorm = Normalize(cleanedQuery ~= "" and cleanedQuery or query)
    local expandedQuery = ExpandQueryText(cleanedQuery ~= "" and cleanedQuery or query)
    local norm = Normalize(expandedQuery)
    local queryTokens = SplitTokens(norm)
    if norm == "" or #queryTokens == 0 then return {} end
    limit = tonumber(limit) or MAX_RESULTS
    local cacheKey = tostring(pageKey) .. "\031" .. tostring(opts.kind or "") .. "\031" .. tostring(limit) .. "\031" .. norm
    if type(K.searchCache) == "table" and K.searchCache[cacheKey] then
        return CopySearchResults(K.searchCache[cacheKey])
    end
    local results = {}
    for i = 1, #(index.items or {}) do
        if i % 32 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = index.items[i]
        local score = TokenScore(item, queryTokens, norm, intent, pageKey, exactNorm)
        if opts.kind and item.kind ~= opts.kind then score = 0 end
        if score > 0 then
            InsertTopResult(results, { item = item, score = score }, limit)
        end
    end
    local out = {}
    for i = 1, #results do out[i] = results[i] end
    K.searchCache = K.searchCache or {}
    K.searchCacheOrder = K.searchCacheOrder or {}
    RememberCache(K.searchCache, K.searchCacheOrder, cacheKey, out, SEARCH_CACHE_LIMIT)
    return out
end

local function OpenPageText(item)
    if item and item.page and item.page ~= "" then
        return "Try: open " .. tostring(item.pageLabel or item.page) .. "."
    end
    return nil
end

local function ExampleCommand(item)
    if not item then return nil end
    if item.kind == "setting" and item.setting then
        local setting = item.setting
        if setting.type == "boolean" then return "Try: turn on " .. tostring(setting.label or item.label) .. "." end
        if setting.type == "number" then return "Try: set " .. tostring(setting.label or item.label) .. " to " .. tostring(setting.default or setting.min or 1) .. "." end
        if setting.type == "enum" then return "Try: set " .. tostring(setting.label or item.label) .. " to one of its dropdown values." end
        if setting.type == "color" then return "Try: set " .. tostring(setting.label or item.label) .. " to red." end
    end
    if item.kind == "action" then return "Try: " .. tostring(item.label or item.key) .. "." end
    return nil
end

local function FormatResultLine(rank, item)
    local prefix = tostring(rank) .. ". "
    local label = tostring(item.label or item.key or "Result")
    local page = item.pageLabel and item.pageLabel ~= "" and (" — " .. tostring(item.pageLabel)) or ""
    local kind = item.kind and (" [" .. tostring(item.kind) .. "]") or ""
    return prefix .. label .. page .. kind
end


local PAGE_HELP = {
    home = {
        title = "MSUF Assistant",
        lines = {
            "Ask me to change settings, open pages, export/import profiles, run diagnostics, or explain MSUF features.",
            "Examples: hide player name; move target 20 right; set castbar text color red; export current profile; why is target castbar hidden?",
        },
        actions = { "Open Player", "Open Castbars", "Profile Help", "Edit Mode Help" },
    },
    uf_player = {
        title = "Player frame help",
        lines = {
            "You can change Player frame visibility, size, position, text, portrait, border/outline, alpha, raid marker, and range fade controls.",
            "Examples: hide player name; set player width 300; set alpha 50; turn portrait border off; set player border color red.",
        },
        actions = { "Open Player Settings", "Do same for Target", "Undo" },
    },
    uf_target = {
        title = "Target frame help",
        lines = {
            "You can change Target frame size, position, text, portrait, border/outline, alpha, range fade, raid marker, and castbar-related controls.",
            "Examples: hide target name; move target 20 right; set target portrait border color gold; why is target castbar hidden?",
        },
        actions = { "Open Target", "Open Castbars", "Target Castbar Help" },
    },
    uf_focus = { title = "Focus frame help", lines = { "You can change Focus frame visibility, size, position, text, portrait, alpha, border/outline, and focus castbar controls.", "Examples: hide focus power text; move focus 10 left; set focus portrait size 40." }, actions = { "Open Focus", "Open Castbars" } },
    uf_pet = { title = "Pet frame help", lines = { "You can change Pet frame visibility, name/HP/power text, size, position, portrait, border/outline, and alpha controls." }, actions = { "Open Pet" } },
    uf_boss = { title = "Boss Frames help", lines = { "You can change Boss frame visibility, size, position, name/HP/power text, raid marker/range fade, and boss castbar settings." }, actions = { "Open Boss Frames", "Open Castbars" } },
    opt_castbar = {
        title = "Castbars help",
        lines = {
            "You can change player, target, focus, and boss castbar visibility, size, position, icons, text, colors, textures, and related detail controls where they exist.",
            "Examples: disable target castbar; set target castbar height 18; turn off target castbar icon; set castbar text color red.",
        },
        actions = { "Enable Target Castbar", "Open Colors", "Reset Castbar Text Color" },
    },
    opt_bars = { title = "Bars help", lines = { "You can change bar textures, background/foreground behavior, gradients, outlines, rounded frames, absorb bars, and highlight border settings.", "Examples: set bar texture to Smooth; set bar outline color red; enable class colored background." }, actions = { "Open Bars", "Open Colors" } },
    opt_colors = { title = "Colors help", lines = { "You can change global, frame, bar, castbar, class resource, portrait, and highlight colors registered by the Assistant.", "Examples: set global font color white; set castbar text color red; change player border color blue." }, actions = { "Open Colors", "Reset Color" } },
    opt_fonts = { title = "Fonts help", lines = { "You can change global fonts, font sizes, font overrides, and related text styling controls where they exist.", "Examples: set global font to Friz Quadrata; set player name font size 14." }, actions = { "Open Fonts" } },
    profiles = {
        title = "Profiles help",
        lines = {
            "You can summarize, export, import, create, copy, switch, delete, reset, and assign profiles to specs where shared helpers exist.",
            "Examples: export current profile; import profile; copy current profile to Raid; switch profile Healer; enable spec auto-switch.",
        },
        actions = { "Export Current Profile", "Import Profile", "Create Profile" },
    },
    auras3 = { title = "Aura Style help", lines = { "You can change registered Aura and Group Aura controls such as visibility, icon size, count, per-row layout, growth, offsets, cooldown text, stack text, filters, blacklist, and quick presets.", "Examples: set target buff icon size to 30; turn on shared buff raid filter; apply clean aura preset." }, actions = { "Open Auras", "Open Aura Filters" } },
    auras3_buffs = { title = "Aura Buffs help", lines = { "You can change registered buff controls for unit and group frames, including icon size, max buffs, layout, stack text, cooldown text, and filters.", "Examples: set player buff max to 8; set party buff icon size to 24; turn on target buff player filter." }, actions = { "Open Aura Buffs" } },
    auras3_debuffs = { title = "Aura Debuffs help", lines = { "You can change registered debuff controls for unit and group frames, including icon size, max debuffs, layout, cooldown text, and debuff filters.", "Examples: set focus debuff icon size to 28; turn on shared debuff raid filter." }, actions = { "Open Aura Debuffs" } },
    auras3_filters = { title = "Aura Filters help", lines = { "You can change registered Aura filter toggles, prepared blacklist entries, public group-aura category blacklists, Aura quick presets, and Group Aura copy through Group Copy categories.", "Examples: blacklist spell 12345 for player auras; show raid buff category blacklist; apply performance aura preset; copy raid auras to party." }, actions = { "Open Aura Filters" } },
    gf_layout = { title = "Group Layout help", lines = { "You can change group frame layout, spacing, growth, anchoring, reverse health fill, scaling breakpoints, party/raid/mythic raid controls, and visibility settings.", "Examples: 'set raid scale for 20 players to 80', 'make raid frames fill backwards', 'move raid frame closer to player', or 'set party growth direction to down'." }, actions = { "Open Group Layout" } },
    gf_bars = { title = "Group Health & Text help", lines = { "You can change group health/text controls, text slots/selectors, bar sizes, colors, and layout-related settings where registered." }, actions = { "Open Group Health & Text" } },
    gf_indicators = { title = "Group Indicators help", lines = { "You can change group status indicators, role/ready/summon icons, corner indicators, and related editor selectors where registered." }, actions = { "Open Group Indicators" } },
    classpower = { title = "Class Resources help", lines = { "You can change class resource mode, size, position, colors, and gameplay-specific class resource controls where registered." }, actions = { "Open Class Resources" } },
    gameplay = { title = "Gameplay help", lines = { "You can change gameplay helpers such as combat timer, sounds, totem/statue frame behavior, and related registered controls." }, actions = { "Open Gameplay" } },
}

local SCOPED_HELP_ALIASES = {
    { terms = { "player help", "help player", "help for player", "help for player frame", "player frame help", "spieler hilfe" }, page = "uf_player" },
    { terms = { "target help", "help target", "help for target", "help for target frame", "target frame help", "ziel hilfe" }, page = "uf_target" },
    { terms = { "focus help", "help focus", "focus frame help" }, page = "uf_focus" },
    { terms = { "pet help", "help pet", "pet frame help" }, page = "uf_pet" },
    { terms = { "boss help", "boss frames help", "help boss frames" }, page = "uf_boss" },
    { terms = { "castbar help", "castbars help", "help castbar", "target castbar help", "zauberleiste hilfe" }, page = "opt_castbar" },
    { terms = { "bar help", "bars help", "help bar", "help bars", "texture help", "help texture" }, page = "opt_bars" },
    { terms = { "color help", "colors help", "help color", "help colors", "farbe hilfe", "farben hilfe" }, page = "opt_colors" },
    { terms = { "font help", "fonts help", "help font", "help fonts", "schrift hilfe" }, page = "opt_fonts" },
    { terms = { "profile help", "profiles help", "help profile", "help profiles", "profil hilfe", "how do profiles work" }, page = "profiles" },
    { terms = { "aura help", "auras help", "buff help", "debuff help" }, page = "auras3_styling" },
    { terms = { "edit mode help", "editmode help", "help edit mode" }, page = "home", special = "editmode" },
    { terms = { "group help", "group frames help", "help group", "help group frames", "party help", "help party", "raid help", "help raid" }, page = "gf_layout" },
    { terms = { "indicator help", "help indicator", "group indicator help", "help group indicator", "corner indicator help", "help corner indicator" }, page = "gf_indicators" },
    { terms = { "class resource help", "help class resource", "class power help", "help class power" }, page = "classpower" },
    { terms = { "gameplay help", "help gameplay" }, page = "gameplay" },
}

local function JoinLines(lines)
    local out = {}
    for i = 1, #(lines or {}) do
        if lines[i] and lines[i] ~= "" then out[#out + 1] = tostring(lines[i]) end
    end
    return table.concat(out, "\n")
end

local function ActionLine(actions)
    if type(actions) ~= "table" or #actions == 0 then return nil end
    return "Actions: " .. table.concat(actions, " | ")
end

local function CountRegisteredForPage(page)
    local index = K.EnsureIndex()
    local settings, actions = 0, 0
    for i = 1, #(index.items or {}) do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = index.items[i]
        if item.page == page then
            if item.kind == "setting" then settings = settings + 1 end
            if item.kind == "action" or item.kind == "diagnostic" then actions = actions + 1 end
        end
    end
    return settings, actions
end

local function PageHelp(page, titleOverride)
    page = page or CurrentPageKey()
    local spec = PAGE_HELP[page] or PAGE_HELP.home
    local settings, actions = CountRegisteredForPage(page)
    local lines = {}
    lines[#lines + 1] = tostring(titleOverride or spec.title or PageLabel(page))
    for i = 1, #(spec.lines or {}) do lines[#lines + 1] = spec.lines[i] end
    if settings > 0 or actions > 0 then
        lines[#lines + 1] = "Registered here: " .. tostring(settings) .. " settings, " .. tostring(actions) .. " actions/diagnostics."
    end
    local action = ActionLine(spec.actions)
    if action then lines[#lines + 1] = action end
    return { text = JoinLines(lines), status = "applied", summary = "Assistant page help" }
end

local function GeneralHelp()
    local counts = K.Summary()
    local lines = {
        "MSUF Assistant can search, explain, navigate, diagnose, and change registered MSUF settings from one input.",
        "Try: hide player name; set player width 300; border color red on the current page; open castbars; export current profile; why is target castbar hidden?",
        "Knowledge index: " .. tostring(counts.setting or 0) .. " settings, " .. tostring((counts.action or 0) + (counts.diagnostic or 0)) .. " actions/diagnostics, " .. tostring(counts.faq or 0) .. " FAQ/help rows, " .. tostring(counts.page or 0) .. " pages.",
        "Actions: Open Player | Open Castbars | Profile Help | What can I change here?",
    }
    return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant general help" }
end

local CHANGELOG_TERMS = {
    "changelog", "change log", "release notes", "patch notes", "build notes", "version notes",
    "latest changes", "what changed", "what is new", "whats new",
    "aenderungen", "anderungen", "neuerungen", "was ist neu", "was hat sich geaendert",
    "versionshinweise", "patchnotizen",
}

local CHANGELOG_QUESTION_TERMS = {
    "what", "explain", "summary", "summarize", "show me", "latest", "release", "notes",
    "was", "wie", "erklaere", "erklaer", "zusammenfassung", "neu",
}

local CHANGELOG_OPEN_TERMS = {
    "open changelog", "close changelog", "toggle changelog",
    "open change log", "close change log", "toggle change log",
    "open release notes", "close release notes", "toggle release notes",
    "oeffne changelog", "changelog oeffnen",
}

local CHANGELOG_IGNORE_TOKENS = {
    ["what"] = true, ["changed"] = true, ["change"] = true, ["changes"] = true,
    ["new"] = true, ["latest"] = true, ["release"] = true, ["releases"] = true,
    ["note"] = true, ["notes"] = true, ["patch"] = true, ["build"] = true,
    ["version"] = true, ["versions"] = true, ["preview"] = true, ["alpha"] = true,
    ["beta"] = true, ["changelog"] = true, ["from"] = true, ["since"] = true,
    ["current"] = true, ["previous"] = true, ["between"] = true, ["about"] = true,
    ["with"] = true, ["for"] = true, ["the"] = true, ["and"] = true, ["in"] = true,
    ["was"] = true, ["ist"] = true, ["neu"] = true, ["sich"] = true,
    ["geaendert"] = true, ["aenderungen"] = true, ["anderungen"] = true,
    ["neuerungen"] = true, ["versionshinweise"] = true, ["patchnotizen"] = true,
    ["zu"] = true, ["zum"] = true, ["zur"] = true, ["ueber"] = true, ["und"] = true,
}

local function ChangelogData()
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" then return nil end
    if type(data.entries) ~= "table" or #data.entries == 0 then return nil end
    return data
end

local function LooksLikeChangelogQuestion(query)
    local norm = Normalize(query)
    if norm == "" then return false end
    if ContainsAny(norm, CHANGELOG_OPEN_TERMS) then return false end
    local hasChangelogTerm = ContainsAny(norm, CHANGELOG_TERMS)
    if hasChangelogTerm and ContainsAny(norm, CHANGELOG_QUESTION_TERMS) then return true end
    if ContainsAny(norm, { "latest changes", "release notes", "patch notes", "build notes", "version notes", "was ist neu", "was hat sich geaendert" }) then return true end
    if ContainsAny(norm, { "what changed", "what is new", "whats new" })
        and (norm:find("%d+%.%d+") or ContainsAny(norm, {
            "release", "version", "preview", "alpha", "beta", "patch", "build", "changelog",
            "menu2", "edit mode", "editmode", "assistant", "dashboard", "search", "runtime",
            "unit frame", "unitframes", "group frame", "group frames",
        })) then
        return true
    end
    return false
end
K.LooksLikeChangelogQuestion = LooksLikeChangelogQuestion

local function ChangelogEntryMatches(entry, queryNorm, compactQuery)
    local version = Normalize(entry and entry.version or "")
    if version == "" then return false end
    if StringContainsPhrase(queryNorm, version) then return true end
    local compactVersion = version:gsub("%s+", "")
    if compactVersion ~= "" and compactQuery:find(compactVersion, 1, true) then return true end
    local channel, number = version:match("(preview)%s+(%d+)")
    if not channel then channel, number = version:match("(alpha)%s+(%d+)") end
    if not channel then channel, number = version:match("(beta)%s+(%d+)") end
    if channel and number and ContainsAny(queryNorm, { channel .. " " .. number, channel .. number }) then return true end
    return false
end

local function ChangelogEntryForQuery(data, query)
    local entries = data and data.entries or {}
    local norm = Normalize(query)
    local compact = norm:gsub("%s+", "")
    for i = 1, #entries do
        if ChangelogEntryMatches(entries[i], norm, compact) then return entries[i] end
    end
    if ContainsAny(norm, { "previous release", "previous version", "last release", "letzte version", "vorherige version" }) and entries[2] then
        return entries[2]
    end
    return entries[1]
end

local function ChangelogMeaningTokens(query)
    local out = {}
    local seen = {}
    local norm = Normalize(query)
    for token in norm:gmatch("%S+") do
        if #token >= 3 and token:find("%a") and not CHANGELOG_IGNORE_TOKENS[token] and not seen[token] then
            seen[token] = true
            out[#out + 1] = token
        end
    end
    return out
end

local function ChangelogSectionHaystack(section)
    local parts = { tostring(section and section.title or "") }
    local bullets = section and section.bullets
    if type(bullets) == "table" then
        for i = 1, #bullets do parts[#parts + 1] = tostring(bullets[i] or "") end
    end
    return Normalize(table.concat(parts, " "))
end

local function ChangelogSectionsForQuery(entry, query)
    local sections = type(entry and entry.sections) == "table" and entry.sections or {}
    local tokens = ChangelogMeaningTokens(query)
    if #tokens == 0 then return sections, false end
    local matched = {}
    for i = 1, #sections do
        local haystack = ChangelogSectionHaystack(sections[i])
        for t = 1, #tokens do
            if haystack:find(tokens[t], 1, true) then
                matched[#matched + 1] = sections[i]
                break
            end
        end
    end
    if #matched > 0 then return matched, true end
    return sections, false
end

local function ChangelogAnswer(query)
    if not LooksLikeChangelogQuestion(query) then return nil end
    local data = ChangelogData()
    if not data then
        return {
            text = "No bundled MSUF changelog data is loaded. Try: open changelog.",
            status = "info",
            summary = "Assistant changelog answer",
        }
    end

    local entry = ChangelogEntryForQuery(data, query)
    if type(entry) ~= "table" then return nil end
    local sections, filtered = ChangelogSectionsForQuery(entry, query)
    local lines = {}
    local title = "Changelog: " .. tostring(entry.version or data.currentVersion or "MSUF")
    if entry.date then title = title .. " (" .. tostring(entry.date) .. ")" end
    lines[#lines + 1] = title
    if data.rangeLabel and data.rangeLabel ~= "" then lines[#lines + 1] = "Bundled range: " .. tostring(data.rangeLabel) end
    if filtered then lines[#lines + 1] = "Matched release-note sections for your question." end

    local maxSections = filtered and 5 or 4
    local maxBullets = filtered and 4 or 2
    local visibleSections = math.min(#sections, maxSections)
    for i = 1, visibleSections do
        local section = sections[i]
        lines[#lines + 1] = tostring(section.title or "Changes") .. ":"
        local bullets = type(section.bullets) == "table" and section.bullets or {}
        local visibleBullets = math.min(#bullets, maxBullets)
        for b = 1, visibleBullets do lines[#lines + 1] = "- " .. tostring(bullets[b]) end
        if #bullets > visibleBullets then lines[#lines + 1] = "- ... " .. tostring(#bullets - visibleBullets) .. " more." end
    end
    if #sections > visibleSections then lines[#lines + 1] = "... " .. tostring(#sections - visibleSections) .. " more sections in the Dashboard changelog." end
    lines[#lines + 1] = "Actions: Open Changelog | Search release notes"
    return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant changelog answer" }
end

local KNOWLEDGE_INTENT_TERMS = {
    "explain", "what is", "what does", "what are", "where", "where is", "where do", "where can",
    "how", "how do", "how can", "help", "change", "make", "set", "move", "open", "find",
}

local GROUP_FRAME_SCOPE_TERMS = {
    "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames",
    "mythic raid frame", "mythic raid frames", "group", "party", "raid", "mythic raid",
}

local GROUP_LAYOUT_HELP_TERMS = {
    "width", "height", "size", "wider", "narrower", "taller", "shorter",
    "spacing", "space", "gap", "growth", "grow", "direction", "column", "columns",
    "offline", "hide offline", "show offline", "range fade", "range check", "out of range",
}

local GROUP_HEALTH_TEXT_HELP_TERMS = {
    "health text", "hp text", "power text", "mana text", "health bar", "power bar", "bar color",
    "health color", "power color", "text slot", "text slots", "font size", "range fade", "range check",
    "out of range", "dispel overlay", "debuff stripe",
}

local GROUP_INDICATOR_HELP_TERMS = {
    "indicator", "indicators", "status icon", "status icons", "spell indicator", "spell indicators",
    "corner indicator", "corner indicators", "ready check", "role icon", "leader icon", "assist icon",
    "leader", "assist", "raid marker", "target marker", "resurrection", "resurrection icon", "resurrect",
    "resurrect icon", "incoming res", "incoming resurrection", "rez icon", "summon", "summon icon",
    "phase icon", "phasing icon", "pvp icon", "pvp flag", "war mode", "threat", "aggro", "dispel",
}

local UNIT_FRAME_SCOPE_TERMS = {
    "player", "target", "focus", "pet", "target of target", "targettarget", "focus target", "focustarget",
    "boss", "unit frame", "unit frames", "unitframe", "unitframes",
}

local UNIT_TEXT_HELP_TERMS = {
    "health text", "hp text", "power text", "mana text", "name text", "level text", "status text",
    "text slot", "text slots", "left text", "right text", "font size", "text offset", "text anchor",
}

local CASTBAR_TEXT_HELP_TERMS = {
    "castbar text", "cast bar text", "spell text", "timer text", "cast text", "castbar timer",
    "castbar name", "castbar font", "castbar text offset", "castbar text position",
}

local CLASS_RESOURCE_HELP_TERMS = {
    "class resource", "class resources", "class power", "class powers", "combo point", "combo points",
    "holy power", "chi", "soul shard", "rune", "runes", "arcane charge", "arcane charges",
}

local function DirectHelpAnswer(query, opts)
    local norm = Normalize(query)
    if norm == "help" or norm == "hilfe" or norm == "show commands" or norm == "commands" or norm == "what can you do" or norm == "what can you do?" then
        return GeneralHelp()
    end
    if norm == "what can i change here" or norm == "what can i change here?" or norm == "help here" or norm == "current page help" or norm == "this page help" then
        return PageHelp((opts and opts.currentPage) or CurrentPageKey(), "Current page help")
    end
    if ContainsAny(norm, { "undo", "redo" })
        and ContainsAny(norm, { "explain", "what is", "what does", "how do", "how can", "help" })
    then
        return {
            text = "Undo and redo help\nUndo reverts the last Assistant-applied setting change. Redo reapplies the last reverted Assistant change.\nExamples: undo; redo; what did you change?\nActions: Undo | Redo",
            status = "applied",
            summary = "Assistant undo help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_INDICATOR_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group Indicators help\nGroup frame indicators live on Group Frames > Indicators. You can change ready-check, role, leader/assist, raid-marker, summon, resurrection, phase, PvP/War Mode, threat/aggro, dispel, spell, and corner indicators where registered.\nExamples: show raid ready check icon; hide raid summon icon; move raid phase icon right; set party ready check size to 18; open group indicators.\nActions: Open Group Indicators",
            status = "applied",
            summary = "Assistant group indicators help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_HEALTH_TEXT_HELP_TERMS)
        and not ContainsAny(norm, { "role power", "healer power", "healer power bar", "tank power", "tank power bar", "dps power", "dps power bar", "damager power", "damager power bar" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group Health & Text help\nGroup health, power, role power, text slots, text font sizes, bar colors, range fade, dispel overlay, and debuff stripe controls live on Group Frames > Health & Text where registered.\nExamples: change party health text; hide healer power bars in raid frames; set raid range fade to 40; open group health and text.\nActions: Open Group Health & Text",
            status = "applied",
            summary = "Assistant group health text help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_LAYOUT_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group frame layout help\nGroup frame sizing, spacing, growth direction, anchoring, range fade, offline behavior, and raid-size scaling live across Group Layout and Group Health & Text.\nExamples: set raid width to 140; make party frames taller; set raid growth direction to down; hide offline players in raid frames; set raid range fade to 40.\nActions: Open Group Layout | Open Group Health & Text",
            status = "applied",
            summary = "Assistant group layout help",
        }
    end
    if ContainsAny(norm, UNIT_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, UNIT_TEXT_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Unit frame text help\nPlayer, Target, Focus, Pet, Target of Target, Focus Target, and Boss pages expose registered name, health, power, level, status, font-size, anchor, slot, and offset text controls where that unit supports them.\nExamples: move target HP text left; set target power text to percent; make player name text bigger; open target text selector.\nActions: Open Player | Open Target | Open Boss Frames",
            status = "applied",
            summary = "Assistant unit text help",
        }
    end
    if ContainsAny(norm, { "castbar", "cast bar" })
        and ContainsAny(norm, CASTBAR_TEXT_HELP_TERMS)
        and not ContainsAny(norm, { "texture", "textures", "bar texture", "castbar texture", "cast bar texture" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Castbar text help\nCastbar text controls live on Castbars. The Assistant can change registered castbar text size, X/Y offsets, visibility, and related castbar detail controls where exposed.\nExamples: move target castbar text left; set focus castbar text size to 14; make boss castbar text bigger.\nActions: Open Castbars",
            status = "applied",
            summary = "Assistant castbar text help",
        }
    end
    if ContainsAny(norm, { "interrupt color", "interruptible color", "uninterruptible color", "castbar interrupt color", "cast bar interrupt color" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Castbar interrupt color help\nInterruptible and uninterruptible cast colors are Castbar color controls. They are separate from the Interrupt Ready indicator, which shows whether your interrupt is available.\nExamples: set interruptible cast color to blue; set uninterruptible cast color to red; explain kick ready indicator.\nActions: Open Castbars",
            status = "applied",
            summary = "Assistant castbar interrupt color help",
        }
    end
    if ContainsAny(norm, CLASS_RESOURCE_HELP_TERMS)
        and ContainsAny(norm, { "width", "height", "size", "wider", "taller", "gap", "spacing", "color", "colors", "anchor", "position", "placement", "style", "mode", "fill", "reverse", "direction", "backwards" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Class Resources help\nClass Resources controls cover visibility, size, width/height, gap, placement, anchor, style, fill direction, and token colors such as Combo Points where registered.\nExamples: make class resources wider; make class resource fill backwards; make class resource fill normal direction; set combo point color to red; move class resources above player.\nActions: Open Class Resources | Open Colors",
            status = "applied",
            summary = "Assistant class resources help",
        }
    end
    if ContainsAny(norm, { "diagnostic", "diagnostics", "debug report", "debug", "health check", "repair", "check broken", "run checks" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Diagnostics help\nAssistant diagnostics can summarize registered settings, find profile/setup problems, produce debug text, and guide safe repair actions where registered.\nExamples: run diagnostics; assistant debug report; fix broken profile mappings; open display recovery.\nActions: Run Diagnostics | Open Display & Recovery",
            status = "applied",
            summary = "Assistant diagnostics help",
        }
    end
    if not ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, { "menu scale", "ui scale", "msuf frame scale", "msuf frames scale", "dashboard scale", "dashboard scaling", "options scale", "menu bigger", "menu smaller" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Dashboard scaling help\nDashboard scaling controls live on the Dashboard under Scaling. They cover UI scale, Menu scale, and MSUF frame scale, with apply/revert behavior handled by the Dashboard controls.\nExamples: open dashboard scaling; make menu bigger; set MSUF frame scale to 100.\nActions: Open Dashboard Scaling",
            status = "applied",
            summary = "Assistant dashboard scaling help",
        }
    end
    if ContainsAny(norm, { "edit mode", "editmode", "frame edit mode", "anchor picker", "move frames mode" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Edit Mode help\nUse MSUF Edit Mode to move frames visually, open the anchor picker, or reset the currently edited position. The Assistant can enter, exit, toggle, and check Edit Mode.\nExamples: enter MSUF edit mode; open anchor picker; exit edit mode; am I in edit mode?\nActions: Enter Edit Mode | Open Edit Mode Anchor Picker | Exit Edit Mode",
            status = "applied",
            summary = "Assistant Edit Mode help",
        }
    end
    if (ContainsAny(norm, { "raid scaling", "raid scale", "frame scaling", "scale at", "scaling breakpoint", "scaling breakpoints", "player count scaling", "player-count scaling", "raid frame player count" })
            or (ContainsAny(norm, { "raid", "raid frame", "raid frames" })
                and ContainsAny(norm, { "players", "player count", "10 players", "20 players", "25 players", "26 players", "10m", "20m", "25m", "mythic size" })
                and ContainsAny(norm, { "scale", "scaling", "smaller", "bigger", "larger", "increase", "decrease" })))
        and ContainsAny(norm, { "explain", "what is", "what does", "how", "where", "where do", "where can", "change", "make", "help", "mean", "breakpoint", "players", "raid size" })
    then
        return {
            text = "Group frame scaling breakpoints\nRaid scaling can use player-count breakpoints: 1-10, 11-20, 21-25, and 26+ players. MSUF applies the matching scale for the current raid size when Group Layout scaling is enabled.\nExamples: set raid scale for 20 players to 80; scale raid for 10m to 95; increase raid scale for 20m by 5.\nActions: Open Group Layout",
            status = "applied",
            summary = "Assistant group scaling help",
        }
    end
    if ContainsAny(norm, { "detached power", "detached power bar", "detached mana", "power bar detached" })
        and ContainsAny(norm, { "explain", "what is", "what does", "how", "where", "offset", "position", "help" })
    then
        return {
            text = "Detached Power Bar help\nPer-unit detached Power Bar options live on each unit page under Power Bar. The detached X/Y offsets move the separated bar only after that unit's Power Bar is detached.\nExamples: detach target power bar; move target powerbar left; set target powerbar x offset to 12; attach target power bar.\nActions: Open Player | Open Target | Open Class Resources",
            status = "applied",
            summary = "Assistant detached power help",
        }
    end
    if ContainsAny(norm, { "powerbar offset", "power bar offset", "powerbar x", "powerbar y", "power bar x", "power bar y", "powerbar position", "power bar position" })
        and ContainsAny(norm, { "where", "where do", "where can", "change", "set", "move", "offset", "position", "help", "explain" })
    then
        return {
            text = "Power Bar offset help\nNormal Power text offsets live on each unit page under Text/Power text. If you mean the separated bar itself, first detach that unit's Power Bar, then use Detached Power Bar X/Y Offset.\nExamples: move target power text left; detach target power bar; move target powerbar left; set target powerbar x offset to 12.\nActions: Open Player | Open Target",
            status = "applied",
            summary = "Assistant power bar offset help",
        }
    end
    if ContainsAny(norm, { "role power", "healer power", "healer power bar", "tank power", "tank power bar", "dps power", "dps power bar", "damager power", "damager power bar" })
        and ContainsAny(norm, { "where", "help", "how", "show", "hide", "turn on", "turn off", "enable", "disable" })
    then
        return {
            text = "Group role Power Bar help\nGroup Frames can show or hide Power Bars by role through the registered Tank, Healer, and DPS Power controls.\nRelevant settings: Party Show Tank Power, Party Show Healer Power, Party Show DPS Power, Raid Show Tank Power, Raid Show Healer Power, Raid Show DPS Power.\nExamples: hide healer power bars in raid frames; show tank power in party frames; hide dps power in raid frames.\nActions: Open Group Health & Text",
            status = "applied",
            summary = "Assistant group role power help",
        }
    end
    if ContainsAny(norm, { "cooldown manager", "cooldownmanager", "essential cooldown", "essential cooldowns", "cdm" })
        and ContainsAny(norm, { "anchor", "anchoring", "attach", "where", "help", "explain", "how" })
    then
        return {
            text = "Cooldown Manager anchoring help\nUnitframes can anchor to the Essential Cooldown Viewer through their anchor target setting. Group frames use a custom anchor frame, and Class Resources have their own Essential Cooldowns anchor toggle.\nExamples: anchor unitframes to cooldownmanager; put player and target near cooldownmanager; put raid frames near cooldownmanager; anchor class resources to essential cooldownmanager.\nActions: Open Player | Open Group Layout | Open Class Resources",
            status = "applied",
            summary = "Assistant cooldown manager anchor help",
        }
    end
    if ContainsAny(norm, { "interrupt ready", "kick ready", "ready interrupt", "ready kick" })
        and ContainsAny(norm, { "explain", "what is", "what does", "where", "where is", "where do", "help", "mean", "indicator", "icon", "border" })
    then
        return {
            text = "Interrupt Ready Indicator help\nInterrupt Ready is a Castbar helper that can show whether your interrupt is ready on Target, Focus, or Boss castbars. Its style, anchor, size, auto-size, offsets, and ready/not-ready colors are registered Castbar controls.\nExamples: show kick ready on target; put kick ready indicator left; move kick ready indicator down 3; make kick ready icon bigger.\nActions: Open Castbars",
            status = "applied",
            summary = "Assistant interrupt ready help",
        }
    end
    if ContainsAny(norm, { "focus kick", "focus kick tracker", "focus kick icon", "focus interrupt tracker", "focus interrupt icon" })
        and ContainsAny(norm, { "explain", "what is", "what does", "where", "where is", "where do", "help", "tracker", "icon", "position", "size" })
    then
        return {
            text = "Focus Kick Tracker help\nFocus Kick is the Castbar Focus Interrupt Tracker. It has registered controls for visibility, preview, width, height, text size, and X/Y offsets.\nExamples: show focus kick tracker; move focus kick tracker left 10; make focus kick tracker bigger; reset focus kick position.\nActions: Open Castbars",
            status = "applied",
            summary = "Assistant focus kick help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, { "reverse fill", "reverse health fill", "fill backwards", "backwards fill", "right to left fill", "fill direction", "normal direction" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group reverse fill help\nGroup Frame Reverse Health Fill lives on Group Layout for Party, Raid, and Mythic Raid. It flips health fill direction; normal direction turns Reverse Health Fill off.\nExamples: make raid frames fill backwards; make party frames fill normal direction; turn off raid reverse fill.\nActions: Open Group Layout",
            status = "applied",
            summary = "Assistant group reverse fill help",
        }
    end
    if ContainsAny(norm, { "castbar fill", "cast bar fill", "fill direction", "castbar direction", "cast bar direction", "left to right fill", "right to left fill", "opposite fill", "reverse fill", "backwards fill", "normal direction" })
        and ContainsAny(norm, { "castbar", "cast bar" })
        and ContainsAny(norm, { "fill", "direction", "left to right", "right to left", "opposite", "reverse", "backwards", "normal", "where", "explain", "what", "help" })
    then
        return {
            text = "Castbar fill direction help\nCastbar Fill Direction controls the shared direction for cast progress. Target can also use the opposite fill direction through its Target Opposite Direction option.\nExamples: make castbar fill left to right; make castbar fill backwards; make target castbar fill opposite; make target castbar use normal direction.\nActions: Open Castbars",
            status = "applied",
            summary = "Assistant castbar fill help",
        }
    end
    if ContainsAny(norm, { "combat timer" })
        and ContainsAny(norm, { "lock", "locked", "unlock", "click through", "click-through", "clickable", "where", "what", "explain", "help" })
    then
        return {
            text = "Combat Timer controls help\nCombat Timer lives on the Gameplay page. You can enable it, set its anchor, move it, resize its text, lock its position, or make it click-through. Click-through means the timer ignores mouse clicks; clickable turns click-through off.\nExamples: lock combat timer; unlock combat timer; make combat timer click through; make combat timer clickable; move combat timer up 10.\nActions: Open Gameplay",
            status = "applied",
            summary = "Assistant combat timer help",
        }
    end
    if ContainsAny(norm, { "totem icon", "totem icons", "totem frame", "totems", "statue frame" })
        and ContainsAny(norm, { "where", "where can", "where do", "make", "bigger", "smaller", "size", "move", "offset", "position", "help", "explain" })
    then
        return {
            text = "Totem Frame controls help\nTotem/Statue frame controls live on Gameplay. The Assistant can enable the frame, resize the icons, move the frame by X/Y offset, change its anchor points, preview it, or reset its layout.\nExamples: show totem frame; make totem icons bigger; move totem icons right 6; set totem frame to anchor to bottom left.\nActions: Open Gameplay",
            status = "applied",
            summary = "Assistant totem frame help",
        }
    end
    if ContainsAny(norm, { "first dance", "first dance tracker", "first dancer" })
        and ContainsAny(norm, { "explain", "what is", "what does", "where", "where is", "where do", "help", "tracker", "icon", "ready" })
    then
        return {
            text = "First Dance Tracker help\nFirst Dance is a Gameplay tracker for the Rogue First Dance buff. Registered controls include visibility, lock, click-through, icon mode, ready visibility, size, and X/Y offsets.\nExamples: show first dance; move first dance icon right 5; set first dance icon size to 40; hide first dance ready.\nActions: Open Gameplay",
            status = "applied",
            summary = "Assistant first dance help",
        }
    end
    if ContainsAny(norm, { "role sorting", "role sort", "sort by role", "group role sorting", "group frame role sorting", "party role sort", "raid role sort" })
        and ContainsAny(norm, { "where", "where is", "where do", "what", "explain", "help", "sorting", "sort" })
    then
        return {
            text = "Group role sorting help\nGroup Frame sorting lives on Group Layout. MSUF can sort party/raid groups by the registered sort controls where the current group scope supports them.\nExamples: set raid sort to role; set party sort to group; put player first in role.\nActions: Open Group Layout",
            status = "applied",
            summary = "Assistant group role sorting help",
        }
    end
    if ContainsAny(norm, { "what can i change", "what settings can i change", "what can i do" })
        and ContainsAny(norm, { "raid frame", "raid frames", "party frame", "party frames", "group frame", "group frames" })
    then
        return PageHelp("gf_layout")
    end
    for i = 1, #SCOPED_HELP_ALIASES do
        local spec = SCOPED_HELP_ALIASES[i]
        if ContainsAny(norm, spec.terms) then
            if spec.special == "editmode" then
                return {
                    text = "Edit Mode help\nUse the Assistant to enter, exit, toggle, cancel, or check MSUF Edit Mode.\nExamples: enter MSUF edit mode; exit edit mode; toggle edit mode; am I in edit mode?\nActions: Enter Edit Mode | Exit Edit Mode | Edit Mode Status",
                    status = "applied",
                    summary = "Assistant Edit Mode help",
                }
            end
            return PageHelp(spec.page)
        end
    end
    return nil
end

local function ActionableHint(item)
    if not item then return nil end
    local actions = {}
    if item.canOpen and item.page and item.pageLabel then actions[#actions + 1] = "Open " .. tostring(item.pageLabel) end
    if item.kind == "setting" then
        actions[#actions + 1] = "Explain"
        local example = ExampleCommand(item)
        if example then actions[#actions + 1] = example:gsub("^Try:%s*", "") end
    elseif item.kind == "faq" then
        actions[#actions + 1] = "Related Settings"
    elseif item.kind == "page" then
        actions[#actions + 1] = "Show page help"
    elseif item.kind == "action" or item.kind == "diagnostic" then
        actions[#actions + 1] = "Run/ask this"
    end
    return ActionLine(actions)
end

function K.Answer(query, opts)
    opts = opts or {}
    local changelog = ChangelogAnswer(query)
    if changelog then return changelog end

    local direct = DirectHelpAnswer(query, opts)
    if direct then return direct end

    local results = K.Search(query, MAX_RESULTS, opts)
    if #results == 0 then return nil end
    local intent = QueryIntent(query)
    local topResult = results[1]
    local top = topResult.item

    if intent == "help" and top.kind == "faq" and top.answer and top.answer ~= "" then
        local lines = { tostring(top.answer) }
        if top.target and top.target ~= "" then lines[#lines + 1] = "Target: " .. tostring(top.target) end
        local openText = OpenPageText(top)
        if openText then lines[#lines + 1] = openText end
        local action = ActionableHint(top)
        if action then lines[#lines + 1] = action end
        return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant FAQ answer" }
    end

    if intent == "location" then
        local lines = { "I found this in MSUF:" }
        for i = 1, math.min(#results, 4) do lines[#lines + 1] = FormatResultLine(i, results[i].item) end
        local openText = OpenPageText(top)
        if openText then lines[#lines + 1] = openText end
        local example = ExampleCommand(top)
        if example then lines[#lines + 1] = example end
        local action = ActionableHint(top)
        if action then lines[#lines + 1] = action end
        return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant search result" }
    end

    if top.kind == "faq" and top.answer and top.answer ~= "" and (intent == "help" or (topResult.score or 0) > 650) then
        local lines = { tostring(top.answer) }
        if top.target and top.target ~= "" then lines[#lines + 1] = "Target: " .. tostring(top.target) end
        local openText = OpenPageText(top)
        if openText then lines[#lines + 1] = openText end
        local action = ActionableHint(top)
        if action then lines[#lines + 1] = action end
        return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant FAQ answer" }
    end

    local lines = { "I found these MSUF matches:" }
    for i = 1, math.min(#results, 5) do lines[#lines + 1] = FormatResultLine(i, results[i].item) end
    lines[#lines + 1] = "You can ask me to open a page, explain a result, or apply a setting directly."
    local example = ExampleCommand(top)
    if example then lines[#lines + 1] = example end
    local action = ActionableHint(top)
    if action then lines[#lines + 1] = action end
    return { text = table.concat(lines, "\n"), status = "applied", summary = "Assistant knowledge result" }
end

function K.NoMatch(query)
    local text = Trim(query)
    local suffix = text ~= "" and (": " .. text) or "."
    return {
        text = "I could not safely match that MSUF command" .. suffix .. "\nI will not guess at settings. Try the frame or page plus the exact control, for example 'set target castbar height to 20' or 'turn on party dead background'. Aura controls are skipped until their backend is ready.\nIf that wording should work, send the exact text in Discord: " .. DISCORD_INVITE,
        status = "info",
        summary = "Assistant knowledge no match",
    }
end

function K.Summary()
    local index = K.EnsureIndex()
    local counts = {}
    for i = 1, #(index.items or {}) do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local kind = index.items[i].kind or "unknown"
        counts[kind] = (counts[kind] or 0) + 1
    end
    return counts
end
