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

local MAX_RESULTS = 6
local INDEX_VERSION = 3

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower()
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    return Trim(text)
end

local function AddUnique(list, seen, value)
    value = Trim(value)
    if value == "" then return end
    local norm = Normalize(value)
    if norm == "" or seen[norm] then return end
    seen[norm] = true
    list[#list + 1] = value
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
    local category = Normalize(setting.category or "")
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
    if ft == "aura" then return "auras3" end
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
    AddUnique(textParts, seen, item.label)
    AddUnique(textParts, seen, item.category)
    AddUnique(textParts, seen, item.pageLabel)
    AddUnique(textParts, seen, item.description)
    AddUnique(textParts, seen, item.answer)
    AddUnique(textParts, seen, item.target)
    AddUnique(textParts, seen, item.controlType)
    AddMany(textParts, seen, item.aliases)
    AddMany(textParts, seen, item.keywords)
    item.haystack = Normalize(table.concat(textParts, " "))
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
        local item = index.items[i]
        index.byKind[item.kind] = index.byKind[item.kind] or {}
        index.byKind[item.kind][#index.byKind[item.kind] + 1] = item
    end
    return index
end

function K.MarkDirty()
    K.index = nil
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

local function TokenScore(item, queryTokens, queryNorm, intent)
    if not item or item.haystack == "" then return 0 end
    local score = 0
    local matched = false
    if item.label and Normalize(item.label) == queryNorm then score = score + 600; matched = true end
    if item.label and Normalize(item.label):find(queryNorm, 1, true) then score = score + 280; matched = true end
    if item.haystack:find(queryNorm, 1, true) then score = score + 180; matched = true end
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
    score = score + SettingPageBoost(item.setting, CurrentPageKey())
    return score
end

function K.Search(query, limit, opts)
    opts = opts or {}
    local index = K.EnsureIndex()
    local intent = QueryIntent(query)
    local cleanedQuery = SearchQueryText(query)
    local expandedQuery = ExpandQueryText(cleanedQuery ~= "" and cleanedQuery or query)
    local norm = Normalize(expandedQuery)
    local queryTokens = SplitTokens(norm)
    if norm == "" or #queryTokens == 0 then return {} end
    limit = tonumber(limit) or MAX_RESULTS
    local results = {}
    for i = 1, #(index.items or {}) do
        local item = index.items[i]
        local score = TokenScore(item, queryTokens, norm, intent)
        if opts.kind and item.kind ~= opts.kind then score = 0 end
        if score > 0 then
            results[#results + 1] = { item = item, score = score }
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.item.label or "") < tostring(b.item.label or "")
    end)
    local out = {}
    for i = 1, math.min(#results, limit) do out[i] = results[i] end
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
    auras3 = { title = "Aura help", lines = { "Aura controls are reachable through Assistant where registered. Some whitelist/filter operations may still be TODO until shared helpers exist.", "Examples: open aura filters; aura help; why are my buffs hidden?" }, actions = { "Open Buffs", "Open Aura Filters" } },
    auras3_debuffs = { title = "Debuffs help", lines = { "Debuff controls are handled through the Aura pages and registered Assistant entries where safe." }, actions = { "Open Debuffs", "Open Aura Filters" } },
    auras3_filters = { title = "Aura Filters help", lines = { "Aura filter/search/help content is available through the Assistant. Some deeper whitelist operations may be TODO until shared helpers exist." }, actions = { "Open Aura Filters" } },
    gf_layout = { title = "Group Layout help", lines = { "You can change group frame layout, spacing, growth, party/raid/mythic raid controls, and visibility settings." }, actions = { "Open Group Layout" } },
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
    { terms = { "bar help", "bars help", "texture help" }, page = "opt_bars" },
    { terms = { "color help", "colors help", "farbe hilfe", "farben hilfe" }, page = "opt_colors" },
    { terms = { "font help", "fonts help", "schrift hilfe" }, page = "opt_fonts" },
    { terms = { "profile help", "profiles help", "profil hilfe", "how do profiles work" }, page = "profiles" },
    { terms = { "aura help", "auras help", "buff help", "debuff help" }, page = "auras3" },
    { terms = { "edit mode help", "editmode help", "help edit mode" }, page = "home", special = "editmode" },
    { terms = { "group help", "group frames help", "party help", "raid help" }, page = "gf_layout" },
    { terms = { "indicator help", "group indicator help", "corner indicator help" }, page = "gf_indicators" },
    { terms = { "class resource help", "class power help" }, page = "classpower" },
    { terms = { "gameplay help" }, page = "gameplay" },
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

local function DirectHelpAnswer(query, opts)
    local norm = Normalize(query)
    if norm == "help" or norm == "hilfe" or norm == "show commands" or norm == "commands" or norm == "what can you do" or norm == "what can you do?" then
        return GeneralHelp()
    end
    if norm == "what can i change here" or norm == "what can i change here?" or norm == "help here" or norm == "current page help" or norm == "this page help" then
        return PageHelp((opts and opts.currentPage) or CurrentPageKey(), "Current page help")
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
        text = "I could not find a matching MSUF setting, page, action, diagnostic, or FAQ" .. suffix .. "\nTry: describe the page or setting name, ask 'what can I change here', or ask for general help.",
        status = "failed",
        summary = "Assistant knowledge no match",
    }
end

function K.Summary()
    local index = K.EnsureIndex()
    local counts = {}
    for i = 1, #(index.items or {}) do
        local kind = index.items[i].kind or "unknown"
        counts[kind] = (counts[kind] or 0) + 1
    end
    return counts
end
