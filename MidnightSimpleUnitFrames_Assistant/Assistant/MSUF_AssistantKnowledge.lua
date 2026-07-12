--- Shell/Menu2/Assistant/MSUF_AssistantKnowledge.lua
--- Lightweight knowledge search for Assistant help/support answers.
---
--- Indexes registry metadata and curated snippets so help replies do not need
--- to read live frame state or mutate options.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry

local K = A.Knowledge or {}
A.Knowledge = K

local MAX_RESULTS = 6
local INDEX_VERSION = 9
local SEARCH_CACHE_LIMIT = 32
local SEARCH_TEXT_LIMIT = 360
local KNOWLEDGE_COMBINED_ALIAS_LIMIT = 2
local KNOWLEDGE_VALUE_ALIAS_LIMIT = 4
local DISCORD_INVITE = "https://discord.gg/2Gf9b2Wprz"

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    if type(A.Normalize) == "function" then
        text = A.Normalize(text)
    else
        text = tostring(text or ""):lower()
        text = text:gsub("\195\164", "ae")
        text = text:gsub("\195\182", "oe")
        text = text:gsub("\195\188", "ue")
        text = text:gsub("\195\159", "ss")
        text = text:gsub("[,;:!?%(%)]", " ")
        text = text:gsub("%s+", " ")
        text = Trim(text)
    end
    text = text:gsub("target%s+of%s+target", "targettarget")
    text = text:gsub("target%s+target", "targettarget")
    text = text:gsub("focus%s+target", "focustarget")
    text = text:gsub("cast%s+bar", "castbar")
    text = text:gsub("power%s+bar", "powerbar")
    text = text:gsub("health%s+bar", "healthbar")
    text = text:gsub("unit%s+frames", "unitframes")
    return text
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
    home = { dashboard = true },
    opt_castbar = { castbar = true },
    opt_bars = { bars = true, globalBars = true },
    opt_colors = { colors = true, bars = true, fonts = true, castbar = true, classPower = true, gameplay = true },
    opt_fonts = { fonts = true },
    opt_misc = { misc = true },
    modules = { modules = true },
    classpower = { classPower = true, classPowerPlayerHP = true, detachedPowerBar = true, altMana = true },
    gameplay = { gameplay = true, combatTimer = true, combatState = true, playerTotems = true, combatCrosshair = true },
    profiles = { profiles = true },
    gf_layout = { group = true },
    gf_bars = { group = true },
    gf_indicators = { group = true },
    gf_auras = { groupAura = true, group = true },
    auras3 = { aura = true },
    auras3_buffs = { aura = true },
    auras3_debuffs = { aura = true },
    auras3_custom = { aura = true },
    auras3_styling = { aura = true },
    auras3_filters = { aura = true },
}

local PAGE_CATEGORY_TERMS = {
    home = { "dashboard", "scaling", "scale" },
    opt_castbar = { "castbar" },
    opt_bars = { "bars", "bar", "outline", "border", "texture", "gradient", "background" },
    opt_colors = { "colors", "colour", "color", "palette" },
    opt_fonts = { "fonts", "font", "text" },
    opt_misc = { "misc", "dashboard", "minimap", "tooltip" },
    modules = { "modules", "module", "style module", "msuf style", "dropdown style" },
    classpower = { "class resource", "class power", "resource", "detached power", "alternative mana", "player hp" },
    gameplay = { "gameplay", "combat timer", "combat enter", "combat leave", "combat state", "target sound", "totem", "crosshair" },
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

local function DisplayFallbackLabel(value, fallback)
    local label = tostring(value or "")
    if label == "" then return fallback or "" end
    if type(A.HumanizeDisplayKey) == "function" then return A.HumanizeDisplayKey(label) end
    label = label:gsub("^uf_", ""):gsub("^gf_", "")
    label = label:gsub("[_%.]", " ")
    label = label:gsub("(%l)(%u)", "%1 %2")
    label = label:gsub("(%u)(%u%l)", "%1 %2")
    if label:find("%u") and not label:find("%l") then label = label:lower() end
    label = label:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then return fallback or "" end
    local out = label:gsub("^%l", string.upper)
    return out
end

local PAGE_LABEL_OVERRIDES = {
    home = "Dashboard",
    profiles = "Profiles",
    gameplay = "Gameplay",
    classpower = "Class Resources",
    modules = "Modules",
    search = "Search",

    opt_castbar = "Cast Bars",
    opt_bars = "Bars",
    opt_colors = "Colors",
    opt_fonts = "Fonts",
    opt_misc = "Miscellaneous",

    gf_layout = "Group Layout",
    gf_bars = "Group Health & Text",
    gf_indicators = "Group Status & Indicators",
    gf_auras = "Group Auras",

    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_custom = "Custom Auras",
    auras3_filters = "Aura Filters",
    auras3_styling = "Aura Style",

    uf_player = "Player",
    uf_target = "Target",
    uf_focus = "Focus",
    uf_pet = "Pet",
    uf_boss = "Boss",
    uf_targettarget = "Target of Target",
    uf_focustarget = "Focus Target",
}
local function PageLabel(pageKey)
    if not pageKey or tostring(pageKey) == "" then return "Assistant" end
    if pageKey and A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(pageKey, "MSUF page") end
    if pageKey and PAGE_LABEL_OVERRIDES[pageKey] then return PAGE_LABEL_OVERRIDES[pageKey] end
    return "MSUF page"
end

local function ItemPageLabel(item)
    if type(item) ~= "table" then return nil end
    if item.page and tostring(item.page) ~= "" then return PageLabel(item.page) end
    if item.kind == "page" and item.key and tostring(item.key) ~= "" then return PageLabel(item.key) end
    if item.kind == "action" or item.kind == "diagnostic" then return "Assistant" end
    return nil
end

local GROUP_LAYOUT_ATTRS = {
    enabled = true,
    showPlayer = true,
    showSolo = true,
    clickCast = true,
    clickCastEnabled = true,
    blizzardFallbackMode = true,
    hideInClientScene = true,
    hideOfflineEnabled = true,
    hideOfflineInCombat = true,
    hideOfflineDelay = true,
    smoothFill = true,
    reverseFill = true,
    groupBackdropColor = true,
    bgColor = true,
    width = true,
    height = true,
    offsetX = true,
    offsetY = true,
    spacing = true,
    unitsPerColumn = true,
    maxColumns = true,
    preserveRaidGroups = true,
    growth = true,
    sortMode = true,
    sortByRole = true,
    playerFirstInRole = true,
    roleOrder = true,
    frameScaleMode = true,
    frameScaleEnabled = true,
    frameScaleManual = true,
    scaleAt10 = true,
    scaleAt20 = true,
    scaleAt25 = true,
    scaleOver25 = true,
    anchorToFrame = true,
    customAnchorFrame = true,
    anchorPoint = true,
}

local GROUP_INDICATOR_KEY_PARTS = {
    "roleicon", "leadericon", "assisticon", "raidmarker", "readycheck",
    "summonicon", "summonanchor", "summonx", "summony", "summonlayer",
    "resurrecticon", "resurrectanchor", "resurrectx", "resurrecty", "resurrectlayer",
    "phaseicon", "pvpicon", "warmode", "threaticon", "aggroicon",
    "spellindicator", "spellindicators", "cornerindicator", "cornerindicators",
    "targetedspell", "targetedspells",
}

local function GroupSettingLikelyPage(setting)
    local attr = tostring(setting and setting.attribute or "")
    local key = Normalize(setting and setting.key or "")
    local attrNorm = Normalize(attr):gsub("%s+", "")
    for i = 1, #GROUP_INDICATOR_KEY_PARTS do
        local part = GROUP_INDICATOR_KEY_PARTS[i]
        if attrNorm:find(part, 1, true) or key:find(part, 1, true) then return "gf_indicators" end
    end
    if GROUP_LAYOUT_ATTRS[attr] then return "gf_layout" end
    local suffix = tostring(setting and setting.key or ""):match("%.([^%.]+)$")
    if suffix and GROUP_LAYOUT_ATTRS[suffix] then return "gf_layout" end
    return "gf_bars"
end

local function SettingLikelyPage(setting)
    if type(setting) ~= "table" then return nil end
    if type(setting.page) == "string" and setting.page ~= "" then return setting.page end
    if setting.unit then
        for key, unit in pairs(PAGE_TO_UNIT) do if unit == setting.unit then return key end end
    end
    local ft = setting.frameType
    if ft == "dashboard" then return "home" end
    if ft == "misc" then return "opt_misc" end
    if ft == "castbar" then return "opt_castbar" end
    if ft == "fonts" then return "opt_fonts" end
    if ft == "bars" or ft == "globalBars" then return "opt_bars" end
    if ft == "classPower" or ft == "classPowerPlayerHP" or ft == "detachedPowerBar" or ft == "altMana" then return "classpower" end
    if ft == "gameplay" or ft == "combatTimer" or ft == "combatState" or ft == "playerTotems" or ft == "combatCrosshair" then return "gameplay" end
    if ft == "modules" then return "modules" end
    if ft == "group" then return GroupSettingLikelyPage(setting) end
    if ft == "groupAura" then return "gf_auras" end
    if ft == "aura" then return "auras3_styling" end
    local cat = Normalize(setting.category or "")
    if ft == "unitframe" and tostring(setting.unit or "") == "global" and cat:find("status icon", 1, true) then return "uf_player" end
    if cat:find("dashboard", 1, true) then return "home" end
    if cat:find("misc", 1, true) then return "opt_misc" end
    if cat:find("class resource", 1, true) or cat:find("class power", 1, true) then return "classpower" end
    if cat:find("gameplay", 1, true) then return "gameplay" end
    if cat:find("castbar", 1, true) then return "opt_castbar" end
    if cat:find("font", 1, true) then return "opt_fonts" end
    if cat:find("color", 1, true) or cat:find("colour", 1, true) then return "opt_colors" end
    if cat:find("profile", 1, true) then return "profiles" end
    return nil
end
K.ResolveSettingPage = SettingLikelyPage
A.ResolveMenuPageForSetting = SettingLikelyPage

local function ActionLikelyPage(action)
    if type(action) ~= "table" then return nil end
    if type(action.page) == "string" and action.page ~= "" then return action.page end
    if type(action.pageKey) == "string" and action.pageKey ~= "" then return action.pageKey end
    local key = tostring(action.key or "")
    local typ = tostring(action.type or "")
    if key:find("aura_group", 1, true) or key:find("group_aura", 1, true) then return "gf_auras" end
    if key:find("aura_blacklist", 1, true) or key:find("aura_group_category_blacklist", 1, true) then return "auras3_filters" end
    if key:find("aura", 1, true) then return "auras3" end
    if key:find("group_status", 1, true) or key:find("group_corner", 1, true) then return "gf_indicators" end
    if key == "copy_group" or key:find("group_custom_anchor", 1, true) then return "gf_layout" end
    if key:find("class_power", 1, true) or typ == "classPower" then return "classpower" end
    if key:find("castbar", 1, true) or key:find("kick", 1, true) then return "opt_castbar" end
    if key:find("totem", 1, true) or key:find("crosshair", 1, true) or typ == "gameplay" then return "gameplay" end
    if key:find("global_scale", 1, true) then return "home" end
    if key:find("font", 1, true) or typ == "fonts" then return "opt_fonts" end
    if typ == "globalBars" then return "opt_bars" end
    if key:find("unit_status", 1, true) then return "uf_player" end
    if key:find("unit", 1, true) then return "uf_player" end
    if typ == "history" or typ == "support" or typ == "setup" then return "home" end
    if typ == "color" or key:find("color", 1, true) then return "opt_colors" end
    if key:find("profile", 1, true) or typ == "profile" then return "profiles" end
    if key:find("edit", 1, true) then return "home" end
    if typ == "navigation" then return "home" end
    if typ == "diagnostic" then return "home" end
    if typ == "preview" or typ == "preset" or typ == "copy" or typ == "reset" then return "home" end
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

local function AddIndexText(textParts, textSeen, value, limit, alreadyNormalized)
    value = tostring(value or "")
    if value == "" then return nil end
    if limit and #value > limit then value = value:sub(1, limit) end
    local norm = alreadyNormalized and value or Normalize(value)
    if norm == "" then return nil end
    if not textSeen[norm] then
        textSeen[norm] = true
        textParts[#textParts + 1] = norm
    end
    return norm
end

local function AddIndexTextMany(textParts, textSeen, values)
    if type(values) == "string" then
        if values:find("|", 1, true) then
            for value in values:gmatch("[^|]+") do AddIndexText(textParts, textSeen, value) end
        else
            AddIndexText(textParts, textSeen, values)
        end
    elseif type(values) == "table" then
        for i = 1, #values do AddIndexText(textParts, textSeen, values[i]) end
    end
end

local function AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, value)
    local norm = Normalize(value)
    if norm == "" or aliasSeen[norm] then return false end
    aliasSeen[norm] = true
    item.aliasNorms[#item.aliasNorms + 1] = norm
    AddIndexText(textParts, textSeen, norm, nil, true)
    return true
end

local function AddIndexItem(index, item)
    local label = Trim(item.label)
    if label == "" then label = DisplayFallbackLabel(item.key or item.kind, "") end
    item.label = Trim(label)
    if item.label == "" then return end
    item.aliases = type(item.aliases) == "table" and item.aliases or {}
    local textParts, textSeen = {}, {}
    item.keyNorm = AddIndexText(textParts, textSeen, item.key)
    item.labelNorm = AddIndexText(textParts, textSeen, item.label)
    AddIndexText(textParts, textSeen, item.category)
    AddIndexText(textParts, textSeen, item.pageLabel)
    AddIndexText(textParts, textSeen, item.description, SEARCH_TEXT_LIMIT)
    AddIndexText(textParts, textSeen, item.answer, SEARCH_TEXT_LIMIT)
    AddIndexText(textParts, textSeen, item.target)
    AddIndexText(textParts, textSeen, item.controlType)

    item.aliasNorms = {}
    local aliasSeen, combinedCount = {}, 0
    local exactAliases = type(item.exactAliases) == "table" and item.exactAliases or {}
    -- Exact one-word aliases are rare and semantically important because the
    -- normal alias matcher deliberately requires at least two tokens.
    for i = 1, #exactAliases do
        local raw = tostring(exactAliases[i] or "")
        if raw ~= "" and not raw:find("%s")
            and AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, raw) then
            combinedCount = combinedCount + 1
        end
    end
    for i = 1, #item.aliases do
        if combinedCount >= KNOWLEDGE_COMBINED_ALIAS_LIMIT then break end
        if AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, item.aliases[i]) then
            combinedCount = combinedCount + 1
        end
    end
    if combinedCount < KNOWLEDGE_COMBINED_ALIAS_LIMIT then
        for i = 1, #exactAliases do
            if combinedCount >= KNOWLEDGE_COMBINED_ALIAS_LIMIT then break end
            if AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, exactAliases[i]) then
                combinedCount = combinedCount + 1
            end
        end
    end
    local valueAliases = type(item.valueAliases) == "table" and item.valueAliases or {}
    local valueCount = 0
    for key in pairs(valueAliases) do
        valueCount = valueCount + 1
        if valueCount > KNOWLEDGE_VALUE_ALIAS_LIMIT then break end
        AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, key)
    end
    local booleanAliases = type(item.booleanAliases) == "table" and item.booleanAliases or {}
    local boolCount = 0
    for key in pairs(booleanAliases) do
        boolCount = boolCount + 1
        if boolCount > KNOWLEDGE_VALUE_ALIAS_LIMIT then break end
        AddIndexAliasNorm(item, textParts, textSeen, aliasSeen, key)
    end
    AddIndexTextMany(textParts, textSeen, item.keywords)
    item.haystack = table.concat(textParts, " ")
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
                label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or (setting.label or "MSUF option"),
                category = setting.category,
                aliases = setting.aliases,
                exactAliases = setting.exactAliases,
                valueAliases = setting.valueAliases,
                booleanAliases = setting.booleanAliases,
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
                label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(action) or (action.label or "Assistant task"),
                category = action.category or action.type,
                aliases = action.aliases,
                exactAliases = action.exactAliases,
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
                local navLabel = PageLabel(nav.key)
                local aliases = {}
                if type(M.ALIASES) == "table" then
                    for alias, key in pairs(M.ALIASES) do
                        if key == nav.key then aliases[#aliases + 1] = alias end
                    end
                end
                AddIndexItem(index, {
                    kind = "page",
                    key = nav.key,
                    label = navLabel,
                    page = nav.key,
                    pageLabel = navLabel,
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
    K.summaryCache = nil
end

function K.EnsureIndex()
    if type(K.index) == "table" and K.index.version == INDEX_VERSION then return K.index end
    K.index = BuildIndex()
    return K.index
end

-- Building the knowledge index walks every registry setting through Normalize
-- (many seconds of CPU). Inside a job coroutine that work yields in slices;
-- on the main thread it would freeze the client until the script-ran-too-long
-- watchdog kills it. Query paths therefore only build when it is safe to do
-- so, and otherwise queue a low-priority background build and report "cold".
local function CanBuildIndexNow()
    if type(K.index) == "table" and K.index.version == INDEX_VERSION then return true end
    if type(coroutine) == "table" and type(coroutine.running) == "function" then
        local co, isMain = coroutine.running()
        if co and not isMain then return true end
    end
    return false
end

local function QueueBackgroundIndexBuild()
    if K._indexBuildQueued then return end
    if type(A.StartJob) ~= "function" or type(A.CoroutineStep) ~= "function" then return end
    K._indexBuildQueued = true
    A.StartJob("assistant.knowledge.index", {
        A.CoroutineStep(function() K.EnsureIndex() end),
    }, function()
        K._indexBuildQueued = nil
    end, { lowPriority = true })
end

function K.EnsureIndexIfSafe()
    if CanBuildIndexNow() then return K.EnsureIndex() end
    QueueBackgroundIndexBuild()
    return nil
end

local LOCATION_TERMS = {
    "where", "where is", "where are", "find", "search", "open", "go to", "show me", "wo", "wo ist", "finde", "suche", "oeffne",
}
local HELP_TERMS = {
    "help", "hilfe", "what is", "what are", "what can", "how", "how do", "why", "explain",
    "erklaere", "warum", "wie", "was ist", "was sind", "was kann", "was kannst",
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

local ACTION_QUERY_WORDS = {
    action = true,
    actions = true,
    task = true,
    tasks = true,
    run = true,
    execute = true,
    diagnostic = true,
    diagnostics = true,
}

local function HasQueryWord(text, word)
    text = tostring(text or "")
    word = tostring(word or "")
    return word ~= "" and (" " .. text .. " "):find(" " .. word .. " ", 1, true) ~= nil
end

local function HasActionQueryHint(queryNorm, exactNorm)
    for word in pairs(ACTION_QUERY_WORDS) do
        if HasQueryWord(queryNorm, word) or HasQueryWord(exactNorm, word) then return true end
    end
    return false
end

local QUERY_SCOPE_ORDER = {
    { unit = "mythicraid", terms = { "mythic raid", "mythicraid" } },
    { unit = "targettarget", terms = { "targettarget" } },
    { unit = "focustarget", terms = { "focustarget" } },
    { unit = "party", terms = { "party", "party frame", "party frames" } },
    { unit = "raid", terms = { "raid", "raid frame", "raid frames" } },
    { unit = "player", terms = { "player" } },
    { unit = "target", terms = { "target" } },
    { unit = "focus", terms = { "focus" } },
    { unit = "pet", terms = { "pet" } },
    { unit = "boss", terms = { "boss" } },
}

local GROUP_QUERY_UNITS = { party = true, raid = true, mythicraid = true }
local UNIT_QUERY_UNITS = {
    player = true, target = true, focus = true, pet = true, boss = true,
    targettarget = true, focustarget = true,
}

local FOCUS_KICK_FEATURE_TERMS = {
    "focus kick tracker", "focus kick icon", "focus interrupt tracker", "focus interrupt icon",
    "fokus kick tracker", "fokus kick anzeige", "fokus interrupt tracker", "fokus interrupt anzeige",
}

local function QueryStartsWithScope(norm, term)
    norm = tostring(norm or "")
    term = Normalize(term)
    return term ~= "" and (norm == term or norm:sub(1, #term + 1) == term .. " ")
end

local function RequestedSearchUnit(queryNorm, exactNorm)
    local exact = Normalize(exactNorm or "")
    local norm = Normalize(queryNorm or "")
    -- "Focus" is part of this feature's proper name, not a request to search
    -- every setting owned by the Focus unit-frame page.
    if ContainsAny(exact, FOCUS_KICK_FEATURE_TERMS) or ContainsAny(norm, FOCUS_KICK_FEATURE_TERMS) then return nil end
    for i = 1, #QUERY_SCOPE_ORDER do
        local info = QUERY_SCOPE_ORDER[i]
        for j = 1, #(info.terms or {}) do
            if QueryStartsWithScope(exact, info.terms[j]) or QueryStartsWithScope(norm, info.terms[j]) then
                return info.unit
            end
        end
    end
    if StringContainsPhrase(exact, "mythic raid frame") or StringContainsPhrase(exact, "mythic raid frames")
        or StringContainsPhrase(norm, "mythic raid frame") or StringContainsPhrase(norm, "mythic raid frames") then
        return "mythicraid"
    end
    if StringContainsPhrase(exact, "party frame") or StringContainsPhrase(exact, "party frames")
        or StringContainsPhrase(norm, "party frame") or StringContainsPhrase(norm, "party frames") then
        return "party"
    end
    if StringContainsPhrase(exact, "raid frame") or StringContainsPhrase(exact, "raid frames")
        or StringContainsPhrase(norm, "raid frame") or StringContainsPhrase(norm, "raid frames") then
        return "raid"
    end
    if StringContainsPhrase(exact, "group frame") or StringContainsPhrase(exact, "group frames")
        or StringContainsPhrase(norm, "group frame") or StringContainsPhrase(norm, "group frames") then
        if StringContainsPhrase(exact, "mythic raid") or StringContainsPhrase(norm, "mythic raid") then return "mythicraid" end
        if StringContainsPhrase(exact, "party") or StringContainsPhrase(norm, "party") then return "party" end
        if StringContainsPhrase(exact, "raid") or StringContainsPhrase(norm, "raid") then return "raid" end
    end
    return nil
end

local function SearchScopeScore(item, queryNorm, exactNorm)
    local setting = item and item.setting
    if type(setting) ~= "table" then return 0 end
    local requested = RequestedSearchUnit(queryNorm, exactNorm)
    if not requested then return 0 end
    local unit = tostring(setting.unit or "")
    if unit == requested then return 430 end
    if GROUP_QUERY_UNITS[requested] then
        if GROUP_QUERY_UNITS[unit] then return -260 end
        if UNIT_QUERY_UNITS[unit] then return -180 end
    elseif UNIT_QUERY_UNITS[requested] then
        if UNIT_QUERY_UNITS[unit] then return -180 end
        if GROUP_QUERY_UNITS[unit] then return -160 end
    end
    return 0
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
    "was ist ", "was sind ", "was kann ", "was kannst ", "wie kann ",
}

local function SearchQueryText(query)
    local norm = Normalize(query)
    local candidates = { norm }
    local actionText = A.Parser and A.Parser.ActionableText
    if type(actionText) == "function" then
        local actionable = actionText(norm)
        if actionable ~= "" and actionable ~= norm then candidates[#candidates + 1] = actionable end
    end
    for c = 1, #candidates do
        local candidate = candidates[c]
        for i = 1, #QUERY_PREFIXES do
            local prefix = QUERY_PREFIXES[i]
            if candidate:sub(1, #prefix) == prefix then
                return Trim(candidate:sub(#prefix + 1))
            end
        end
    end
    return candidates[#candidates] or norm
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
    if HasActionQueryHint(queryNorm, exactNorm) then
        if item.kind == "action" or item.kind == "diagnostic" then
            score = score + 460
        elseif item.kind == "setting" then
            score = score - 180
        elseif item.kind == "faq" then
            score = score - 120
        elseif item.kind == "page" then
            score = score - 60
        end
    end
    if intent == "location" then
        if item.kind == "setting" or item.kind == "page" or item.kind == "action" or item.kind == "diagnostic" then score = score + 260 end
        if item.kind == "faq" then score = score - 260 end
    elseif intent == "help" then
        if item.kind == "faq" then score = score + 120 end
    end
    score = score + SearchScopeScore(item, queryNorm, exactNorm)
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
    local index = K.EnsureIndexIfSafe()
    -- Contract: a result array means the index was ready; nil means the index
    -- is still cold and its cooperative background build has been requested.
    -- Callers must not treat the cold sentinel as an empty search result.
    if not index then return nil end
    local pageKey = opts.ignoreCurrentPage and "home" or CurrentPageKey()
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
        return "Ask me to open " .. tostring(ItemPageLabel(item) or "MSUF page") .. "."
    end
    return nil
end

local function ExampleCommand(item)
    if not item then return nil end
    if item.kind == "setting" and item.setting then
        local setting = item.setting
        local label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or item.label or "that option")
        if setting.type == "boolean" then return "Example: turn on " .. label .. "." end
        if setting.type == "number" then return "Example: set " .. label .. " to " .. tostring(setting.default or setting.min or 1) .. "." end
        if setting.type == "enum" then return "Example: set " .. label .. " to one of its listed choices." end
        if setting.type == "color" then return "Example: set " .. label .. " to red." end
    end
    if item.kind == "action" then return "Example: " .. tostring(item.label or "that task") .. "." end
    return nil
end

local function FormatResultLine(rank, item)
    local prefix = tostring(rank) .. ". "
    local label = tostring(item.label or DisplayFallbackLabel(item.key, "Result"))
    local pageLabel = ItemPageLabel(item)
    local page = pageLabel and pageLabel ~= "" and (" - " .. tostring(pageLabel)) or ""
    local kind = item.kind and (" [" .. tostring(item.kind) .. "]") or ""
    return prefix .. label .. page .. kind
end

local function ResultFollowups(results, limit)
    local out = {}
    limit = math.min(tonumber(limit) or 5, #(results or {}))
    for i = 1, limit do
        local item = results[i] and results[i].item
        if item then
            out[#out + 1] = {
                kind = item.kind,
                key = item.key,
                label = item.label,
                page = item.page,
                pageLabel = ItemPageLabel(item),
                category = item.category,
                description = item.description,
                answer = item.answer,
                target = item.target,
                controlType = item.controlType,
                settingKey = item.setting and item.setting.key,
                actionKey = item.action and item.action.key,
                canOpen = item.canOpen,
                canExplain = item.canExplain,
            }
        end
    end
    return out
end


local PAGE_HELP = {
    home = {
        title = "MSUF Assistant",
        lines = {
            "Ask me to change MSUF options, open pages, export/import profiles, run checks, or explain MSUF features.",
            "Examples: hide player name; move target 20 right; set cast bar text color red; export current profile; why is target cast bar hidden?",
        },
        actions = { "Open Player", "Open Cast Bars", "Profile Help", "Edit Mode Help" },
    },
    uf_player = {
        title = "Player frame help",
        lines = {
            "You can change Player frame visibility, size, position, text, portrait, border/outline, alpha, raid marker, and range fade options.",
            "Examples: hide player name; set player width 300; set alpha 50; turn portrait border off; set player border color red.",
        },
        actions = { "Open Player Settings", "Do same for Target", "Undo" },
    },
    uf_target = {
        title = "Target frame help",
        lines = {
            "You can change Target frame size, position, text, portrait, border/outline, alpha, range fade, raid marker, and cast bar options.",
            "Examples: hide target name; move target 20 right; set target portrait border color gold; why is target cast bar hidden?",
        },
        actions = { "Open Target", "Open Cast Bars", "Target Cast Bar Help" },
    },
    uf_focus = { title = "Focus frame help", lines = { "You can change Focus frame visibility, size, position, text, portrait, alpha, border/outline, and focus cast bar options.", "Examples: hide focus power text; move focus 10 left; set focus portrait size 40." }, actions = { "Open Focus", "Open Cast Bars" } },
    uf_pet = { title = "Pet frame help", lines = { "You can change Pet frame visibility, name/HP/power text, size, position, portrait, border/outline, and alpha options." }, actions = { "Open Pet" } },
    uf_targettarget = {
        title = "Target of Target help",
        lines = {
            "You can change Target of Target frame visibility, size, position, health/text, cast bar, range fade, colors, and related status options.",
            "Examples: show target of target; set target of target width to 160; make target of target width smaller; open target of target.",
        },
        actions = { "Open Target of Target" },
    },
    uf_focustarget = {
        title = "Focus Target help",
        lines = {
            "You can change Focus Target frame visibility, size, position, health/text, cast bar, range fade, colors, and related status options.",
            "Examples: show focus target; set focus target width to 180; make focus target height smaller; open focus target.",
        },
        actions = { "Open Focus Target" },
    },
    uf_boss = { title = "Boss Frames help", lines = { "You can change Boss frame visibility, size, position, name/HP/power text, raid marker/range fade, and boss cast bar options." }, actions = { "Open Boss Frames", "Open Cast Bars" } },
    opt_castbar = {
        title = "Cast Bars help",
        lines = {
            "You can change Player, Target, Focus, and Boss cast bar visibility, size, position, icons, text, colors, textures, and the detail options shown in the MSUF menu.",
            "Examples: disable target cast bar; set target cast bar height 18; turn off target cast bar icon; set cast bar text color red.",
            "Cast bar source examples: use MSUF player cast bar; use Blizzard player cast bar; hide target cast bar; use MSUF focus cast bar.",
        },
        actions = { "Enable Target Cast Bar", "Open Colors", "Reset Cast Bar Text Color" },
    },
    opt_bars = {
        title = "Bars help",
        lines = {
            "You can change bar textures, background/foreground behavior, gradients, outlines, rounded frames, absorb bars, aggro role filtering, and highlight border options.",
            "Examples: set bar texture to amooth; set bar outline color red; enable class colored background; set raid aggro shows for non tanks; show absorb bar preview.",
            "Preview requests can test aggro borders, dispel borders, absorb bars, and other bar previews.",
        },
        actions = { "Open Bars", "Open Colors" },
    },
    opt_colors = { title = "Colors help", lines = { "You can change global, frame, bar, cast bar, class resource, aura, portrait, and highlight colors that MSUF lets the Assistant edit.", "Examples: set global font color white; set aura cooldown warning color yellow; change player border color blue." }, actions = { "Open Colors", "Reset Color" } },
    opt_fonts = { title = "Fonts help", lines = { "You can change global fonts, font sizes, section-specific font styles, and related text styling options.", "Examples: set global font to Friz Quadrata; set player name font size 14." }, actions = { "Open Fonts" } },
    opt_misc = { title = "Miscellaneous help", lines = { "You can change menu language, menu snapping, reduced motion, welcome/version messages, minimap icon, target sounds, Blizzard unit frame handling, and unit frame tooltip behavior.", "Examples: set menu language to German; show minimap icon; use MSUF tooltips; show tooltips only with ALT; disable Blizzard unit frames." }, actions = { "Open Miscellaneous" } },
    modules = { title = "Modules help", lines = { "You can change optional MSUF style modules such as the MSUF Style module and menu choice style.", "Examples: enable MSUF Style; turn off midnight style; set menu choice style to old; open modules." }, actions = { "Open Modules" } },
    profiles = {
        title = "Profiles help",
        lines = {
            "You can summarize, export, import, create, copy, switch, delete, reset, and assign profiles to specs where the Profiles page offers those actions.",
            "Examples: export current profile; import profile; copy current profile to Raid; switch profile Healer; enable spec auto-switch.",
            "Wago is a community site often used for WoW addon import strings. Export an MSUF profile string first, then paste it on Wago if you want a web backup or want to share the profile with someone else.",
            "Safety: I ask before importing, deleting, resetting, or copying profiles. For imports, you can export or copy the current profile first.",
        },
        actions = { "Export Current Profile", "Copy Wago Profiles Link", "Import Profile" },
    },
    auras3 = { title = "Auras help", lines = { "Aura content lives on the frame it affects. Open a UnitFrame > Auras for Buffs, Debuffs, and Custom 1–3; use Group Frames > Auras for Party/Raid filters, lists, and layout.", "To change which icons appear, name the frame and Buff or Debuff lane. 'No timer' means a permanent/no-duration aura and maps to Hide Permanent; exact SpellID lists hide individual auras where Blizzard permits identity filtering.", "Cooldown text, swipe, stack text, duration bars, colors, size, and growth change how shown auras look, not which auras pass the filter." }, actions = { "Open Target", "Open Player", "Open Group Auras" } },
    auras3_styling = { title = "Aura Style help", lines = { "You can change aura basics, borders, cooldown text, stack text, duration bars, and related rendering details. Aura timer, stack, highlight, and pandemic colors live in Colors > Auras.", "These are presentation controls. To hide auras with no timer, use Hide Permanent in that frame's Buff or Debuff filters instead.", "Examples: set aura cooldown text size to 14; move target buff stack text right 3; set target duration bar fill mode to elapsed." }, actions = { "Open Aura Style", "Open Colors" } },
    auras3_buffs = { title = "Aura Buffs help", lines = { "Open the affected UnitFrame > Auras > Buffs for its icon layout, Blizzard filters, SpellID blacklist, and preview.", "Party/Raid content lives in Group Frames > Auras; scope-aware styling remains under Appearance > Auras." }, actions = { "Open Target", "Open Player", "Open Group Auras" } },
    auras3_debuffs = { title = "Aura Debuffs help", lines = { "Open the affected UnitFrame > Auras > Debuffs for dispellable rules, blacklist, layout, and preview.", "Party/Raid content lives in Group Frames > Auras; scope-aware styling remains under Appearance > Auras." }, actions = { "Open Target", "Open Focus", "Open Group Auras" } },
    auras3_custom = { title = "Custom Auras help", lines = { "Every supported UnitFrame has Custom 1, Custom 2, and Custom 3 under its Auras section for setup, whitelist, filters, and layout.", "Icon styling and Secret-safe Full-Frame effects are scope-aware under Appearance > Auras; choose Player, Target, Focus, or Boss and then Custom 1-3." }, actions = { "Open Aura Style", "Open Target", "Open Player" } },
    auras3_filters = { title = "Aura Filter help", lines = { "There is no standalone Aura Filters page anymore. Filters and Black-/Whitelists live directly beside the Buff, Debuff, or Custom container they affect.", "Start with scope and lane: Player/Target/Focus/Boss Buffs or Debuffs, or Party/Raid Buffs or Debuffs. Unit filter toggles inherit from Shared unless that unit uses custom rules; group lanes use their own filter token.", "Hide Permanent removes every no-duration aura in that lane. Exact SpellID blacklists remove one spell where Blizzard permits identity filtering; group category blacklists expand to the same live exact-SpellID exclusions. Timer text, swipe, and duration bars are style only." }, actions = { "Open Target", "Open Group Auras" } },
    gf_layout = { title = "Group Layout help", lines = { "You can change group frame layout, spacing, growth, anchoring, reverse health fill, scaling breakpoints, party/raid/mythic raid options, Blizzard fallback behavior, and visibility options.", "Examples: 'set raid scale for 20 players to 80', 'make raid frames fill backwards', 'move raid frame closer to player', 'set party growth direction to down', or 'show Blizzard party frames when Party is disabled'." }, actions = { "Open Group Layout" } },
    gf_bars = {
        title = "Group Health & Text help",
        lines = {
            "You can change Party, Raid, and Mythic Raid health, power, role power, text slots, text font sizes, range fade, dispel overlay, debuff stripe layout, and related group bar options. Group-frame colors live in Colors > Group Frame Colors.",
            "Examples: set raid health text size to 14; hide healer power bars in raid frames; set party range fade to 45; open group colors.",
        },
        actions = { "Open Group Health & Text", "Open Colors" },
    },
    gf_indicators = {
        title = "Group Status & Indicators help",
        lines = {
            "You can change group status indicators, role/ready/summon icons, targeted spell indicators, corner indicators, and related editor choices available in MSUF.",
            "Examples: show party targeted spell indicators; set targeted spell icon size to 28; show raid ready check icon; move raid phase icon right.",
        },
        actions = { "Open Group Status & Indicators" },
    },
    gf_auras = { title = "Group Auras help", lines = { "Party, Raid, and Mythic Raid Buff/Debuff content is configured here: visibility, layout, preview, native filter tokens, Hide Permanent, and live category/SpellID blacklists.", "Choose Party or Raid and then Buffs or Debuffs before changing content. Spell Indicators remain here; cooldown, stack, and duration-bar styling is scope-aware under Appearance > Auras and does not decide which auras appear." }, actions = { "Open Group Auras" } },
    classpower = { title = "Class Resources help", lines = { "You can change class resource mode, size, position, colors, and gameplay-specific class resource options available in MSUF." }, actions = { "Open Class Resources" } },
    gameplay = { title = "Gameplay help", lines = { "You can change gameplay features such as combat timer, sounds, totem/statue frame behavior, and related options." }, actions = { "Open Gameplay" } },
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
    { terms = { "profile help", "profiles help", "help profile", "help profiles", "wago help", "what is wago", "wago profiles help", "profile sharing help", "profil hilfe", "profile hilfe", "hilfe profile", "hilfe profil", "wie funktionieren profile", "how do profiles work" }, page = "profiles" },
    { terms = { "misc help", "miscellaneous help", "help misc", "help miscellaneous", "tooltip help", "tooltips help", "minimap help", "sprache hilfe", "tooltip hilfe", "misc hilfe", "menue sprache hilfe", "blizzard frames hilfe" }, page = "opt_misc" },
    { terms = { "modules help", "module help", "help modules", "help module", "style module help", "msuf style help", "module hilfe", "stil modul hilfe", "module hilfe", "msuf stil hilfe", "dropdown stil hilfe" }, page = "modules" },
    { terms = { "aura style help", "aura styling help", "help aura style", "help aura styling" }, page = "auras3_styling" },
    { terms = { "aura help", "auras help", "buff help", "debuff help" }, page = "auras3" },
    { terms = { "edit mode help", "editmode help", "help edit mode", "bearbeitungsmodus hilfe", "hilfe bearbeitungsmodus", "editmodus hilfe" }, page = "home", special = "editmode" },
    { terms = { "group help", "group frames help", "help group", "help group frames", "party help", "help party", "raid help", "help raid" }, page = "gf_layout" },
    { terms = { "group text help", "group health help", "group health and text help", "help group text", "help group health", "help group health and text", "party text help", "raid text help", "party health help", "raid health help" }, page = "gf_bars" },
    { terms = { "indicator help", "help indicator", "group indicator help", "help group indicator", "corner indicator help", "help corner indicator", "targeted spell help", "targeted spells help", "targeted spell indicator help" }, page = "gf_indicators" },
    { terms = { "group aura help", "group auras help", "help group aura", "help group auras", "party aura help", "raid aura help", "mythic raid aura help" }, page = "gf_auras" },
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
    return "You can also ask: " .. table.concat(actions, " | ")
end

local function FirstLine(text)
    text = tostring(text or "")
    for line in text:gmatch("[^\n]+") do
        line = Trim(line)
        if line ~= "" then return line end
    end
    return nil
end

local function ExtractPrefixedLine(text, prefixes)
    text = tostring(text or "")
    for line in text:gmatch("[^\n]+") do
        line = Trim(line)
        for i = 1, #prefixes do
            local prefix = prefixes[i]
            if line:sub(1, #prefix) == prefix then
                return Trim(line:sub(#prefix + 1))
            end
        end
    end
    return nil
end

local function RememberKnowledgeHelpContext(result)
    if type(result) ~= "table" or type(result.text) ~= "string" or result.searchResults then return result end
    local title = FirstLine(result.text)
    if not title or title == "" then return result end

    local examples = ExtractPrefixedLine(result.text, { "Examples:" })
    local actions = ExtractPrefixedLine(result.text, { "You can ask:", "You can also ask:" })
    if (not examples or examples == "") and (not actions or actions == "") then return result end

    A.lastAssistantHelpContext = {
        kind = "knowledge",
        title = title,
        examples = examples and examples ~= "" and examples or tostring(actions or ""),
        actions = actions and actions ~= "" and actions or "",
        clarification = "Name the exact MSUF frame, page, or option before I change anything from this help topic, so I do not guess wrong.",
        nextStep = "Start by opening the matching page or using one of the examples. If you want me to change a setting, name the exact MSUF frame and option.",
    }
    return result
end

local function CountRegisteredForPage(page)
    local index = K.EnsureIndexIfSafe()
    if not index then return 0, 0 end
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
        lines[#lines + 1] = "On this page I can handle " .. tostring(settings) .. " options and " .. tostring(actions) .. " guided tasks or checks."
    end
    local action = ActionLine(spec.actions)
    if action then lines[#lines + 1] = action end
    return { text = JoinLines(lines), status = "info", summary = "Assistant page help" }
end

local WHAT_CAN_PAGE_HELP_INTENTS = {
    "show me", "show me options", "list", "list options", "explain where",
    "help me find", "help me locate", "can you help me find", "can you help me locate",
    "i want to change", "i want to adjust", "i want to configure", "i want to manage",
    "i need to change", "i need to adjust", "i need to configure", "i need to manage",
    "i am trying to change", "i am trying to adjust", "i am trying to configure", "i am trying to manage",
    "i'm trying to change", "i'm trying to adjust", "i'm trying to configure", "i'm trying to manage",
    "im trying to change", "im trying to adjust", "im trying to configure", "im trying to manage",
    "i am looking for", "i'm looking for", "im looking for", "i need help with",
    "what can i change", "what settings can i change", "what options can i change",
    "what can i do", "what can you change", "what can you do in",
    "how do i change", "how can i change", "how do i configure", "how can i configure",
    "how do i adjust", "how can i adjust", "how do i set", "how can i set",
    "where should i go", "where should i go to", "where should i go for",
    "where do i manage", "where can i manage", "where do i edit", "where can i edit",
    "where are", "where can i change", "where do i change", "where can i adjust", "where do i adjust",
    "where can i configure", "where do i configure", "which page has", "which page contains",
    "which menu has", "which menu contains", "what page has", "what menu has",
    "what controls", "what option changes", "what setting controls", "tell me where", "tell me where to",
    "was kann ich aendern", "was kann ich einstellen", "was kann ich hier aendern",
}

local function LooksLikeWhatCanPageHelpIntent(norm)
    if ContainsAny(norm, WHAT_CAN_PAGE_HELP_INTENTS) then return true end
    return ContainsAny(norm, { "i want", "i need" })
        and ContainsAny(norm, { "option", "options", "where", "find", "locate", "page", "menu" })
end

local WHAT_CAN_UNIT_FRAME_SCOPE_TERMS = {
    "player", "target", "focus", "pet", "target of target", "targettarget", "focus target", "focustarget",
    "boss", "unit frame", "unit frames", "unitframe", "unitframes",
}

local WHAT_CAN_UNIT_TEXT_TERMS = {
    "health text", "hp text", "power text", "mana text", "name text", "level text", "status text",
    "text slot", "text slots", "left text", "right text", "font size", "text offset", "text anchor",
}

local WHAT_CAN_GROUP_FRAME_SCOPE_TERMS = {
    "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames",
    "mythic raid frame", "mythic raid frames", "group", "party", "raid", "mythic raid",
}

local WHAT_CAN_GROUP_LAYOUT_TERMS = {
    "width", "height", "size", "wider", "narrower", "taller", "shorter",
    "spacing", "space", "gap", "growth", "grow", "direction", "column", "columns",
    "offline", "hide offline", "show offline", "range fade", "range check", "out of range",
}

local WHAT_CAN_DIRECT_HELP_TERMS = {
    "interrupt color", "interruptible color", "uninterruptible color", "castbar interrupt color", "cast bar interrupt color",
    "powerbar offset", "power bar offset", "powerbar x", "powerbar y", "power bar x", "power bar y",
    "powerbar position", "power bar position",
}

local WHAT_CAN_PAGE_HELP_TARGETS = {
    { page = "gf_bars", terms = { "group health and text", "group health", "group text", "party health", "party text", "raid health", "raid text", "mythic raid health", "mythic raid text" } },
    { page = "gf_indicators", terms = { "group status and indicators", "group indicators", "group indicator", "party indicator", "party indicators", "raid indicator", "raid indicators", "corner indicator", "corner indicators", "targeted spell", "targeted spells", "targeted spell indicator", "targeted spell indicators", "status icon", "status icons", "ready check", "raid marker", "role icon" } },
    { page = "gf_auras", terms = { "group aura", "group auras", "party aura", "party auras", "raid aura", "raid auras", "mythic raid aura", "mythic raid auras", "group buff", "group buffs", "group debuff", "group debuffs" } },
    { page = "gf_layout", terms = { "group layout", "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames", "mythic raid frame", "mythic raid frames", "party layout", "raid layout" } },
    { page = "auras3_filters", terms = { "aura filter", "aura filters", "hidden aura", "hidden auras", "blacklist", "whitelist", "ignore list" } },
    { page = "auras3_styling", terms = { "aura style", "aura styling", "aura cooldown text", "aura stack text", "cooldown text", "stack text" } },
    { page = "auras3_debuffs", terms = { "target debuff", "target debuffs", "player debuff", "player debuffs", "focus debuff", "focus debuffs", "unit debuff", "unit debuffs", "debuff", "debuffs" } },
    { page = "auras3_buffs", terms = { "target buff", "target buffs", "player buff", "player buffs", "focus buff", "focus buffs", "unit buff", "unit buffs", "buff", "buffs" } },
    { page = "auras3", terms = { "aura", "auras" } },
    { page = "opt_castbar", terms = { "cast bar", "cast bars", "castbar", "castbars", "target cast", "focus cast", "boss cast" } },
    { page = "classpower", terms = { "class resource", "class resources", "class power", "class powers", "combo point", "combo points", "holy power" } },
    { page = "profiles", terms = { "profile", "profiles", "profile import", "profile export", "spec profile", "spec profiles" } },
    { page = "gameplay", terms = { "gameplay", "combat timer", "combat crosshair", "totem", "totems", "totem frame" } },
    { page = "opt_colors", terms = { "color", "colors", "class colors", "bar colors", "font color", "aura colors", "aura timer colors" } },
    { page = "opt_fonts", terms = { "font", "fonts", "font outline", "font shadow" } },
    { page = "opt_bars", terms = { "bar texture", "bar textures", "health bar", "power bar", "bars", "bar", "absorb bar", "dispel overlay", "rounded bars", "aggro role filter", "aggro shows for", "highlight priority", "custom highlight priority" } },
    { page = "opt_misc", terms = { "misc", "miscellaneous", "tooltip", "tooltips", "minimap", "menu language", "blizzard frames" } },
    { page = "modules", terms = { "module", "modules", "style module", "msuf style", "dropdown style" } },
    { page = "uf_targettarget", terms = { "target of target", "targettarget" } },
    { page = "uf_focustarget", terms = { "focus target", "focustarget" } },
    { page = "uf_boss", terms = { "boss frame", "boss frames", "boss" } },
    { page = "uf_player", terms = { "player frame", "player", "self frame" } },
    { page = "uf_target", terms = { "target frame", "target" } },
    { page = "uf_focus", terms = { "focus frame", "focus" } },
    { page = "uf_pet", terms = { "pet frame", "pet" } },
}

local function TryWhatCanPageHelp(norm)
    if not LooksLikeWhatCanPageHelpIntent(norm) then return nil end
    if ContainsAny(norm, WHAT_CAN_UNIT_FRAME_SCOPE_TERMS) and ContainsAny(norm, WHAT_CAN_UNIT_TEXT_TERMS) then return nil end
    if ContainsAny(norm, WHAT_CAN_GROUP_FRAME_SCOPE_TERMS) and ContainsAny(norm, WHAT_CAN_GROUP_LAYOUT_TERMS) then return nil end
    if ContainsAny(norm, WHAT_CAN_DIRECT_HELP_TERMS) then return nil end
    for i = 1, #WHAT_CAN_PAGE_HELP_TARGETS do
        local spec = WHAT_CAN_PAGE_HELP_TARGETS[i]
        if ContainsAny(norm, spec.terms) then
            return PageHelp(spec.page)
        end
    end
    return nil
end

local function CapabilityHelp(german)
    local counts = K.Summary()
    -- Cold knowledge index on the main thread: decline so the deferred job
    -- path (which can build the index in yielding slices) answers instead.
    if not counts then return nil end
    local settingCount = tostring(counts.setting or 0)
    local actionCount = tostring((counts.action or 0) + (counts.diagnostic or 0))
    local lines = {
        "MSUF Assistant: what I can do",
        "I'm the local in-game assistant for MSUF. I use MSUF's menu data on your client, so I don't call an external ChatGPT service.",
        "I can find and explain MSUF options, open their pages and controls, import/export profiles, run checks, use undo/redo, and change safe MSUF options.",
        "I can handle " .. settingCount .. " MSUF options plus " .. actionCount .. " guided tasks or checks across unit frames, group frames, cast bars, auras, class resources, gameplay, profiles, diagnostics, and Edit Mode.",
        "I can explain prerequisites, visibility gates, inheritance, overrides, conflicts, and nearby controls. If a request could match several settings, I show choices instead of guessing.",
        "Examples: hide player name; set target cast bar height to 18; list all target settings; where do I change auras; export current profile; why is target cast bar hidden?",
        "I can answer WoW questions near UI setup. For current class, talent, or patch guides I point to current external guides because MSUF runs offline.",
        "Performance: the full Assistant loads only after you use it, owns no passive combat events or tickers, and pauses/cancels scheduled work when the MSUF menu closes.",
        "You can ask: Open Player | Open Cast Bars | Profile Help | What can I change here?",
    }
    return { text = table.concat(lines, "\n"), status = "info", summary = "Assistant capabilities" }
end
K.CapabilityHelp = CapabilityHelp

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
            text = "Open the changelog to view bundled MSUF release notes.",
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
    if filtered then lines[#lines + 1] = "I found release-note sections that match your question." end

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
    lines[#lines + 1] = "You can ask: Open Changelog | Search release notes"
    return { text = table.concat(lines, "\n"), status = "info", summary = "Assistant changelog answer" }
end

local KNOWLEDGE_INTENT_TERMS = {
    "explain", "what is", "what does", "what are", "where", "where is", "where do", "where can",
    "what controls", "what option", "what setting",
    "how", "how do", "how can", "help", "change", "make", "set", "move", "open", "find",
    "list", "option", "options", "show me", "explain where",
    "wo", "wo ist", "wo sind", "wo kann", "wo aendere", "wo aendern", "wo finde",
    "hilfe", "erklaere", "erklaer", "was ist", "was sind", "wie", "wie kann",
    "aendere", "aendern", "setze", "stelle", "verschiebe", "oeffne", "finde",
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
    "targeted spell", "targeted spells", "targeted spell indicator", "targeted spell indicators",
    "enemy targeted spell", "enemy targeted spells", "nameplate cast tracker",
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
    "essence", "essences", "soul fragment", "soul fragments", "maelstrom weapon", "maelstorm weapon",
    "whirlwind", "tip of the spear", "icicle", "icicles",
    "klassenressource", "klassenressourcen", "klassenleiste", "ressourcenleiste",
    "kombopunkt", "kombopunkte", "heilige kraft", "seelensplitter", "runen", "essenz", "essenzen",
    "seelenfragment", "seelenfragmente", "mahlstrom waffe", "wirbelwind", "speerspitze", "eiskristalle",
}

local CONCEPT_HELP_INTENT_TERMS = {
    "what", "what is", "what are", "what does", "can msuf", "does msuf",
    "help", "explain", "mean", "where", "where is", "where do", "where can",
    "how", "how do", "how can",
}

local function HasConceptHelpIntent(norm)
    return ContainsAny(norm, CONCEPT_HELP_INTENT_TERMS)
end

local function HasConceptDefinitionIntent(norm)
    norm = Normalize(norm)
    if norm == "" then return false end
    if norm:match("^what%s+is%s+") or norm:match("^what%s+are%s+") or norm:match("^what%s+does%s+") then return true end
    if norm:match("^explain%s+") or norm:match("^describe%s+") then return true end
    if norm:match("%smean$") or norm:find(" mean ", 1, true) or norm:find(" means ", 1, true) then return true end
    if norm:match("^[%w%s%-]+%s+help$") then return true end
    return false
end

local function DirectHelpAnswer(query, opts)
    local norm = Normalize(query)
    if norm == "help" or norm == "show commands" or norm == "commands" or norm == "what can you do"
        or norm == "what can i ask" or norm == "what can i ask you" or norm == "what can the assistant do"
        or norm == "what can msuf assistant do" or norm == "what can msuf do" or norm == "assistant help"
    then
        return CapabilityHelp(false)
    end
    if norm == "hilfe" or norm == "befehle" or norm == "was kannst du" or norm == "was kannst du alles"
        or norm == "was kann der assistant" or norm == "was kann der assistent" or norm == "was kann msuf assistant"
        or norm == "was kann msuf assistent" or norm == "was kann ich fragen" or norm == "zeig mir befehle"
        or norm == "assistant hilfe" or norm == "assistent hilfe"
    then
        return CapabilityHelp(false)
    end
    if norm == "what can i change here" or norm == "what can i change here?" or norm == "help here" or norm == "current page help" or norm == "this page help" then
        return PageHelp((opts and opts.currentPage) or CurrentPageKey(), "Current page help")
    end
    if norm == "was kann ich hier aendern" or norm == "hilfe hier" or norm == "hilfe fuer diese seite" or norm == "diese seite hilfe" then
        return PageHelp((opts and opts.currentPage) or CurrentPageKey(), "Current page help")
    end
    local pageHelp = TryWhatCanPageHelp(norm)
    if pageHelp then return pageHelp end
    if ContainsAny(norm, { "gcd", "global cooldown", "global cool down" })
        and ContainsAny(norm, { "what", "what is", "what does", "help", "explain", "mean" })
    then
        return {
            text = "Global cooldown help\nThe global cooldown, or GCD, is the short shared cooldown WoW triggers after most abilities. MSUF does not change the GCD, but it can make related UI easier to read through cast bars, aura cooldown text, class resources, and action-adjacent frame visibility.\nExamples: make aura cooldown text bigger; open cast bars; open class resources; show combat timer.\nYou can ask: Open Cast Bars | Open Aura Style | Open Class Resources",
            status = "applied",
            summary = "Assistant global cooldown help",
        }
    end
    if ContainsAny(norm, { "nameplate", "nameplates", "enemy nameplate", "enemy nameplates" })
        and ContainsAny(norm, { "what", "what are", "can msuf", "change", "help", "explain", "enemy", "where" })
    then
        return {
            text = "Nameplates help\nNameplates are the floating bars above units in the 3D world. MSUF focuses on unit frames, group frames, cast bars, auras, class resources, and gameplay helpers; it does not replace Blizzard nameplates. For enemy nameplate behavior, use Blizzard nameplate settings or a nameplate addon. In MSUF, I can still help with Target, Focus, Boss frames, enemy NPC colors, cast bars, and aura visibility.\nExamples: open target; open boss frames; set enemy NPC color red; make target cast bar bigger.\nYou can ask: Open Target | Open Boss Frames | Open Colors",
            status = "applied",
            summary = "Assistant nameplates help",
        }
    end
    if ContainsAny(norm, { "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames", "mythic raid frame", "mythic raid frames" })
        and not ContainsAny(norm, GROUP_LAYOUT_HELP_TERMS)
        and not ContainsAny(norm, GROUP_HEALTH_TEXT_HELP_TERMS)
        and not ContainsAny(norm, GROUP_INDICATOR_HELP_TERMS)
        and not ContainsAny(norm, { "scaling", "scale", "player count", "role sorting", "role sort", "sort by role" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Party and raid frame help\nParty, Raid, and Mythic Raid frames are group frames: they show members of your group so you can track health, range, buffs, debuffs, role icons, ready checks, and other group status. In MSUF, their layout lives mainly in Group Layout, while health/text, indicators, and auras have their own group-frame pages.\nExamples: open group layout; make raid frames wider; set raid range fade to 40; show party ready check icon.\nYou can ask: Open Group Layout | Open Group Health & Text | Open Group Status & Indicators | Open Group Auras",
            status = "applied",
            summary = "Assistant group frames help",
        }
    end
    if ContainsAny(norm, { "boss frame", "boss frames", "boss unit frame", "boss unit frames" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Boss Frames help\nBoss frames show active boss units, usually in dungeon, raid, and encounter UI. In MSUF, Boss Frames can have their own visibility, size, position, text, auras, raid markers, range fade, and boss cast bar options.\nExamples: open boss frames; show boss frames; make boss frames wider; set boss cast bar height to 20.\nYou can ask: Open Boss Frames | Open Cast Bars",
            status = "applied",
            summary = "Assistant boss frames help",
        }
    end
    if ContainsAny(norm, { "unit frame", "unit frames", "unitframe", "unitframes", "player frame", "target frame", "focus frame", "pet frame" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Unit Frames help\nUnit frames are the UI frames for important units such as Player, Target, Focus, Pet, Boss, Target of Target, and Focus Target. MSUF can configure their visibility, size, position, health and power bars, text, portraits, auras, cast bars, range fade, colors, and related status options.\nExamples: open player; open target; set target width to 240; hide player name; why is target frame hidden?\nYou can ask: Open Player | Open Target | Open Focus | Open Boss Frames",
            status = "applied",
            summary = "Assistant unit frames help",
        }
    end
    if ContainsAny(norm, { "group aura", "group auras", "party aura", "party auras", "raid aura", "raid auras", "mythic raid aura", "mythic raid auras", "group buff", "group buffs", "group debuff", "group debuffs" })
        and HasConceptHelpIntent(norm)
    then
        return PageHelp("gf_auras")
    end
    if ContainsAny(norm, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "buffs and debuffs", "buff and debuff" })
        and not ContainsAny(norm, { "dispel", "dispels", "dispellable", "debuff dispel" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Auras, buffs, and debuffs help\nAura content lives directly on the frame it affects. Open Player, Target, Focus, or Boss Frames > Auras for Buffs, Debuffs, and Custom 1–3. Party/Raid filters and lists live in Group Frames > Auras. For content changes, name the frame and Buff or Debuff lane: broad filters select aura groups, Hide Permanent handles auras with no timer, and exact SpellID lists hide individual auras where Blizzard permits identity filtering. Cooldown/stack text, swipe, duration bars, colors, size, and growth are presentation only.\nExamples: hide player buffs with no timer; show only dispellable raid debuffs; list target buff blacklist; set target buff icon size to 30.\nYou can ask: Open Target | Open Player | Open Boss Frames | Open Group Auras | Open Aura Style",
            status = "applied",
            summary = "Assistant auras help",
        }
    end
    if ContainsAny(norm, { "health bar", "health bars", "hp bar", "hp bars", "life bar", "life bars" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Health Bar help\nA health bar shows how much health a unit has. MSUF can change health bar size, opacity, texture, color behavior, gradients, absorb overlays, incoming-heal overlays, text, and group-frame health layout options.\nExamples: set player height to 40; set raid health text size to 14; turn on heal prediction overlay; set health bar texture to Smooth.\nYou can ask: Open Player | Open Group Health & Text | Open Bars",
            status = "applied",
            summary = "Assistant health bar help",
        }
    end
    if ContainsAny(norm, { "power bar", "power bars", "mana bar", "mana bars", "energy bar", "rage bar", "resource bar", "resource bars" })
        and not ContainsAny(norm, {
            "detached", "detach", "powerbar offset", "power bar offset", "powerbar x", "powerbar y",
            "power bar x", "power bar y", "offset", "role power", "healer power", "tank power",
            "dps power", "damager power",
        })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Power Bar help\nA power bar shows a unit resource such as mana, energy, rage, focus, runic power, or a similar class resource. MSUF can change unit power bars, detached power bars, power text, role power in group frames, and class-resource/player-power options.\nExamples: detach target power bar; hide healer power bars in raid frames; set mana power bar color blue; open class resources.\nYou can ask: Open Player | Open Group Health & Text | Open Class Resources | Open Colors",
            status = "applied",
            summary = "Assistant power bar help",
        }
    end
    if ContainsAny(norm, { "ready check", "ready checks", "readycheck", "ready-check" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Ready Check help\nA ready check lets the group confirm who is ready before a pull. MSUF can show ready-check icons on Party, Raid, and Mythic Raid frames through Group Status & Indicators, including size, anchor, layer, and offset options.\nExamples: show raid ready check icon; set party ready check size to 18; move raid ready check icon right 4.\nYou can ask: Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant ready check help",
        }
    end
    if ContainsAny(norm, { "raid marker", "raid markers", "target marker", "target markers", "world marker", "skull marker" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Raid Marker help\nRaid markers are target icons such as skull, cross, square, and moon. MSUF can display raid-marker indicators on unit frames and group frames and can help with their size, anchor, layer, and offsets where the menu exposes those controls.\nExamples: show raid marker on target; set raid marker size to 18; move raid marker icon up.\nYou can ask: Open Player | Open Target | Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant raid marker help",
        }
    end
    if ContainsAny(norm, { "absorb", "absorbs", "absorb bar", "absorb bars", "shield", "shields", "shield bar", "shield bars" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Absorb and shield help\nAbsorbs are shield effects that prevent incoming damage. MSUF can show absorb information through absorb bars, absorb overlays, colors, anchor choices, and preview/test helpers depending on the frame area.\nExamples: show absorb bar preview; set absorb bar color blue; set absorb bar anchor right; open bars.\nYou can ask: Open Bars | Open Colors",
            status = "applied",
            summary = "Assistant absorb help",
        }
    end
    if ContainsAny(norm, { "incoming heal", "incoming heals", "heal prediction", "healing prediction", "predicted heal", "predicted heals" })
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Incoming Heal and Heal Prediction help\nIncoming heals are heals that are already being cast or predicted. MSUF can show them with heal prediction overlays and related bar options, so healers can see health plus expected healing.\nExamples: turn on heal prediction overlay; set heal prediction anchor right; open bars; open group health and text.\nYou can ask: Open Bars | Open Group Health & Text",
            status = "applied",
            summary = "Assistant heal prediction help",
        }
    end
    if ContainsAny(norm, CLASS_RESOURCE_HELP_TERMS)
        and HasConceptHelpIntent(norm)
    then
        return {
            text = "Class Resources help\nClass resources are class-specific combat resources such as Rogue/Feral Combo Points, Paladin Holy Power, Warlock Soul Shards, Monk Chi, Death Knight Runes, Evoker Essence, Arcane Charges, Vengeance Soul Fragments, Maelstrom Weapon, Whirlwind, Tip of the Spear, and Icicles. MSUF can color each discrete slot independently, use the resource color/ramp, and switch the entire display to a separate color at the dynamic maximum. You can name the resource, class/spec, slot number, or ordinal naturally.\nExamples: set Evoker essence 3 blue; make the second DK rune red; set full Warlock shards purple; disable max rune color; reset Maelstrom Weapon slot colors.\nYou can ask: Open Class Resources | Open Colors",
            status = "applied",
            summary = "Assistant class resources help",
        }
    end
    if ContainsAny(norm, { "alpha", "opacity", "transparent", "transparency", "fade", "faded" })
        and not ContainsAny(norm, { "range fade", "range check", "out of range", "in range", "melee range" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Alpha and opacity help\nAlpha and opacity both describe transparency. Lower opacity makes a frame, bar, text, or aura more see-through; higher opacity makes it more solid. MSUF uses these options for frame alpha, bar/background alpha, range fade, aura fading, and some highlight overlays.\nExamples: set player alpha to 80; set raid range fade to 40; make party frames less transparent; open bars.\nYou can ask: Open Bars | Open Group Health & Text | Open Player",
            status = "applied",
            summary = "Assistant alpha opacity help",
        }
    end
    if ContainsAny(norm, { "anchor", "anchors", "anchoring", "anchor point", "anchor points", "attach point", "attach points" })
        and not ContainsAny(norm, { "cooldown manager", "cooldownmanager", "essential cooldown", "combat timer", "totem", "statue", "interrupt ready", "kick ready" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Anchoring help\nAn anchor tells MSUF what a frame is attached to and which point is used, such as TOPLEFT, CENTER, or BOTTOMRIGHT. Anchors plus X/Y offsets control where frames, icons, indicators, text, and helper widgets appear.\nExamples: anchor raid frames to player; set target anchor point to center; move raid ready check icon right 4; open group layout.\nYou can ask: Open Group Layout | Open Player | Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant anchoring help",
        }
    end
    if ContainsAny(norm, { "x offset", "y offset", "offset", "offsets", "position offset", "horizontal offset", "vertical offset" })
        and not ContainsAny(norm, { "powerbar offset", "power bar offset", "detached power", "castbar text", "cast bar text" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Offset help\nOffsets move something away from its anchor. X Offset moves left or right; Y Offset moves up or down. MSUF uses offsets for unit frames, group frames, text, cast bars, icons, indicators, auras, and gameplay helpers.\nExamples: move target 20 right; move raid ready check icon up 4; set target buff x offset to 6; open edit mode.\nYou can ask: Enter Edit Mode | Open Player | Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant offset help",
        }
    end
    if ContainsAny(norm, { "scale", "scaling", "ui scale", "menu scale", "frame scale", "raid scale" })
        and not ContainsAny(norm, { "player count", "10 players", "20 players", "25 players", "26 players", "breakpoint", "breakpoints" })
        and not ContainsAny(norm, { "menu scale", "ui scale", "msuf frame scale", "msuf frames scale", "dashboard scale", "dashboard scaling", "options scale", "menu bigger", "menu smaller" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Scale help\nScale changes the rendered size of UI elements without always changing their saved width or height. MSUF has menu scale, frame scale, and group-frame scaling options, while some areas use direct width, height, font size, or icon size instead.\nExamples: set menu scale to 110; set raid scale for 20 players to 80; make target frame wider; open group layout.\nYou can ask: Open Dashboard | Open Group Layout | Open Player",
            status = "applied",
            summary = "Assistant scale help",
        }
    end
    if ContainsAny(norm, { "texture", "textures", "bar texture", "castbar texture", "cast bar texture", "foreground texture", "background texture" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Texture help\nA texture is the visual fill style used by bars, such as health bars, power bars, cast bars, absorb bars, and some background bars. MSUF can use shared bar textures or specific foreground/background textures where the menu exposes them.\nExamples: set bar texture to Smooth; set cast bar texture to Blizzard; set detached power bar texture to Smooth; open bars.\nYou can ask: Open Bars | Open Cast Bars | Open Class Resources",
            status = "applied",
            summary = "Assistant texture help",
        }
    end
    if ContainsAny(norm, { "font", "fonts", "font outline", "outline", "monochrome", "font shadow", "text shadow", "shadow strength" })
        and not ContainsAny(norm, { "font help", "fonts help", "help font", "help fonts" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Font rendering help\nFont options control how text is drawn. Size changes readability, outline makes letters stand out, monochrome changes the render style, and shadow options add contrast behind text. MSUF has shared font options plus text-specific font settings.\nExamples: set global font size to 14; set shared font outline to thick; set player name font size to 16; open fonts.\nYou can ask: Open Fonts | Open Player | Open Group Health & Text",
            status = "applied",
            summary = "Assistant font rendering help",
        }
    end
    if ContainsAny(norm, { "cooldown swipe", "cooldown text", "aura cooldown", "cooldown number", "cooldown numbers", "cooldown timer" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Cooldown display help\nCooldown swipe is the radial overlay that shows time remaining on an icon. Cooldown text is the number shown on top of the icon. MSUF can configure aura cooldown swipe, cooldown text size, offsets, and related aura styling options.\nExamples: turn on target buff cooldown swipe; set aura cooldown text size to 14; move target buff cooldown text up; open aura style.\nYou can ask: Open Aura Style | Open Auras",
            status = "applied",
            summary = "Assistant cooldown display help",
        }
    end
    if ContainsAny(norm, { "stack", "stacks", "stack count", "stack text", "aura stack", "aura stacks" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Aura stack help\nA stack count shows how many times the same aura is applied. MSUF can control aura stack text visibility, size, X/Y offsets, and styling where the aura page exposes those options.\nExamples: set target buff stack text size to 14; move target debuff stack text right 3; open aura style.\nYou can ask: Open Aura Style | Open Auras",
            status = "applied",
            summary = "Assistant aura stack help",
        }
    end
    if ContainsAny(norm, { "growth direction", "grow direction", "growth", "per row", "columns", "column layout", "layout direction" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Growth direction help\nGrowth direction controls where new frames or icons are added: left, right, up, down, or into columns depending on the MSUF area. It matters for group frame layout and aura icon layout.\nExamples: set party growth direction to down; set target buffs per row to 8; make raid frames grow right; open group layout.\nYou can ask: Open Group Layout | Open Auras",
            status = "applied",
            summary = "Assistant growth direction help",
        }
    end
    if ContainsAny(norm, { "click through", "click-through", "clickable", "lock", "locked", "unlock", "unlocked" })
        and not ContainsAny(norm, { "combat lockdown", "lockdown", "in combat lockdown", "combat protected", "combat restriction", "protected action" })
        and HasConceptDefinitionIntent(norm)
    then
        return {
            text = "Click-through and lock help\nLocked means a widget should not be moved accidentally. Click-through means the widget ignores mouse clicks so you can click the game world or frames behind it. MSUF uses these ideas for gameplay helpers and movable UI elements.\nExamples: lock combat timer; make combat timer click through; open gameplay.\nYou can ask: Open Gameplay | Enter Edit Mode",
            status = "applied",
            summary = "Assistant click-through lock help",
        }
    end
    if ContainsAny(norm, { "focus target", "focustarget" })
        and ContainsAny(norm, { "what", "what is", "what does", "help", "explain", "where" })
    then
        return {
            text = "Focus Target help\nFocus Target is the unit your Focus is targeting. In MSUF, Focus Target has its own unit-frame page, so you can configure visibility, size, health, text, cast bar, range fade, colors, and position separately from Focus.\nExamples: open focus target; show focus target frame; set focus target width to 180; make focus target height smaller.\nYou can ask: Open Focus Target",
            status = "applied",
            summary = "Assistant focus target help",
        }
    end
    if ContainsAny(norm, { "target of target", "targettarget" })
        and ContainsAny(norm, { "what", "what is", "what does", "help", "explain", "where" })
    then
        return {
            text = "Target of Target help\nTarget of Target shows what your current target is targeting. It is useful for tanks, assist targeting, and checking whether an enemy is targeting you or another player. In MSUF, it has its own page for visibility, size, text, cast bar, range fade, colors, and position.\nExamples: open target of target; show target of target; set target of target width to 160; make target of target width smaller.\nYou can ask: Open Target of Target",
            status = "applied",
            summary = "Assistant target of target help",
        }
    end
    if ContainsAny(norm, { "interrupt", "interrupts", "kick", "kicks", "interrupting", "kick tracker" })
        and not ContainsAny(norm, { "interrupt color", "interruptible color", "uninterruptible color", "castbar interrupt color", "cast bar interrupt color" })
        and ContainsAny(norm, { "help", "how", "how do", "make", "easier", "see", "what", "explain", "where" })
    then
        return {
            text = "Interrupt help\nMSUF can make interrupts easier to read through Cast Bar options: Interrupt Ready indicators, Focus Kick Tracker, cast bar colors, interrupt shake, and Target/Focus/Boss cast bar visibility. It cannot decide when to interrupt, but it can make the relevant frame feedback clearer.\nExamples: show kick ready on target; show focus kick tracker; turn on shake on interrupt; set uninterruptible cast color red.\nYou can ask: Open Cast Bars | Explain Interrupt Ready",
            status = "applied",
            summary = "Assistant interrupt help",
        }
    end
    if ContainsAny(norm, { "mouseover healing", "mouse over healing", "mouseover heal", "mouse over heal", "click casting", "click-casting", "click cast", "clickcast" })
        and ContainsAny(norm, { "help", "what", "what is", "how", "where", "enable", "show", "explain" })
    then
        return {
            text = "Mouseover and click casting help\nFor healing UI, MSUF can enable Click Casting on Party, Raid, and Mythic Raid frames and can improve mouseover readability with hover highlights, range fade, dispel visibility, and clear group health text. Spell bindings themselves come from WoW's click-cast/keybind system or a click-casting addon.\nExamples: turn on raid click casting; turn on party click casting; set raid range fade to 40; open group layout.\nYou can ask: Open Group Layout | Open Group Health & Text | Open Colors",
            status = "applied",
            summary = "Assistant mouseover healing help",
        }
    end
    if ContainsAny(norm, { "range check", "range fade", "out of range", "in range", "melee range" })
        and ContainsAny(norm, { "help", "what", "what is", "what does", "how", "where", "explain", "range" })
    then
        return {
            text = "Range check help\nMSUF can show range through unit-frame and group-frame Range Fade options, and Gameplay has Combat Crosshair range feedback through the melee range spell. Range Fade makes frames more transparent when the unit is out of range.\nExamples: set raid range fade to 40; turn on target range fade; show combat crosshair; set crosshair melee spell 100780.\nYou can ask: Open Group Health & Text | Open Target | Open Gameplay",
            status = "applied",
            summary = "Assistant range check help",
        }
    end
    if ContainsAny(norm, { "dispel", "dispels", "dispellable", "dispellable debuff", "dispellable debuffs", "debuff dispel" })
        and ContainsAny(norm, { "help", "what", "what is", "what does", "how", "where", "explain", "debuff" })
    then
        return {
            text = "Dispel help\nMSUF has separate dispel features. Party/Raid/Mythic Raid use Group Frames > Health & Text > Dispel Overlay. Player/Target/Focus/Boss use Bars > UnitFrame Dispel Overlay and the global/scoped Dispel Border. Aura Filters decide which dispellable debuffs are shown as icons. UnitFrame Dispel Border/Overlay need at least one UnitFrame aura container enabled.\nExamples: turn on party dispel overlay; set raid dispel overlay to max; set target dispel overlay opacity to 80; set dispel border detects to dispellable by me; show only dispellable raid debuffs.\nYou can ask: Open Group Health & Text | Open Bars | Open Aura Filters",
            status = "applied",
            summary = "Assistant dispel help",
        }
    end
    if ContainsAny(norm, { "threat", "aggro", "threat border", "aggro border" })
        and ContainsAny(norm, { "help", "what", "what is", "what does", "how", "where", "explain" })
    then
        return {
            text = "Threat and aggro help\nThreat is how enemies decide whom to attack; aggro means a unit currently has enemy attention. MSUF can highlight this with Aggro Border options, aggro role filters, threat/status indicators, group status and indicators, and colors.\nExamples: turn on aggro border; set raid aggro shows for non tanks; test aggro border; set aggro border color red.\nYou can ask: Open Bars | Open Colors | Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant threat help",
        }
    end
    if ContainsAny(norm, { "targeted spell", "targeted spells", "targeted spell indicator", "targeted spell indicators", "enemy targeted spell", "enemy targeted spells", "nameplate cast tracker" })
        and ContainsAny(norm, { "help", "what", "what is", "what are", "what does", "how", "where", "explain", "mean", "change", "set", "show", "open" })
    then
        return {
            text = "Targeted Spell Indicators help\nParty Targeted Spell Indicators show enemy nameplate casts that are targeting party members. They are party-only and live in Group Frames > Status & Indicators.\nExamples: show party targeted spell indicators; set targeted spell icon size to 28; set targeted spell mode to always; move targeted spells up 4.\nYou can ask: Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant targeted spell indicator help",
        }
    end
    if ContainsAny(norm, { "combat lockdown", "lockdown", "in combat lockdown", "combat protected", "combat restriction", "protected action" })
        and ContainsAny(norm, { "help", "what", "what is", "what does", "how", "why", "explain" })
    then
        return {
            text = "Combat lockdown help\nWoW blocks protected UI changes while you are in combat. MSUF can still answer questions, but some frame movement, layout, secure-click, and protected frame changes may wait until combat ends. If an action is delayed, leave combat and let MSUF apply or retry it.\nExamples: enter edit mode out of combat; move frames after combat; run checks; open display recovery.\nYou can ask: Run Checks | Open Display & Recovery",
            status = "applied",
            summary = "Assistant combat lockdown help",
        }
    end
    if ContainsAny(norm, { "undo", "redo" })
        and ContainsAny(norm, { "explain", "what is", "what does", "how do", "how can", "help" })
    then
        return {
            text = "Undo and redo help\nUndo reverts the last change I made. Redo reapplies the last reverted Assistant change.\nExamples: undo; redo; what did you change?\nYou can ask: Undo | Redo",
            status = "applied",
            summary = "Assistant undo help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_INDICATOR_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group Status & Indicators help\nIn Group Frames > Status & Indicators, I can help with ready-check, role, leader/assist, raid-marker, summon, resurrection, phase, PvP/War Mode, threat/aggro, dispel, targeted spell, and corner indicators. Spell Indicators are in Group Frames > Auras.\nExamples: show party targeted spell indicators; show raid ready check icon; hide raid summon icon; move raid phase icon right; set party ready check size to 18.\nYou can ask: Open Group Status & Indicators",
            status = "applied",
            summary = "Assistant group status and indicators help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_HEALTH_TEXT_HELP_TERMS)
        and not ContainsAny(norm, { "role power", "healer power", "healer power bar", "tank power", "tank power bar", "dps power", "dps power bar", "damager power", "damager power bar" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group Health & Text help\nIn Group Frames > Health & Text, I can help with group health, power, role power, text slots, text font sizes, range fade, dispel overlay, and debuff stripe layout options. Group-frame colors live in Colors > Group Frame Colors.\nExamples: change party health text; hide healer power bars in raid frames; set raid range fade to 40; open group health and text.\nYou can ask: Open Group Health & Text | Open Colors",
            status = "applied",
            summary = "Assistant group health text help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, GROUP_LAYOUT_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group frame layout help\nGroup frame sizing, spacing, growth direction, anchoring, range fade, offline behavior, and raid-size scaling live across Group Layout and Group Health & Text.\nExamples: set raid width to 140; make party frames taller; set raid growth direction to down; hide offline players in raid frames; set raid range fade to 40.\nYou can ask: Open Group Layout | Open Group Health & Text",
            status = "applied",
            summary = "Assistant group layout help",
        }
    end
    if ContainsAny(norm, UNIT_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, UNIT_TEXT_HELP_TERMS)
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Unit frame text help\nPlayer, Target, Focus, Pet, Target of Target, Focus Target, and Boss pages offer name, health, power, level, status, font-size, anchor, slot, and offset text options when that unit supports them.\nExamples: move target HP text left; set target power text to percent; make player name text bigger; open target text options.\nYou can ask: Open Player | Open Target | Open Boss Frames",
            status = "applied",
            summary = "Assistant unit text help",
        }
    end
    if ContainsAny(norm, { "castbar", "castbars", "cast bar", "cast bars", "zauberleiste", "zauberleisten" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
        and not ContainsAny(norm, CASTBAR_TEXT_HELP_TERMS)
        and not ContainsAny(norm, { "interrupt", "interruptible", "uninterruptible", "kick", "focus kick" })
    then
        return {
            text = "Cast Bars help\nIn Cast Bars, I can help with Player, Target, Focus, and Boss cast bars: visibility, size, position, fill direction, textures, text, interrupt-ready indicators, cast colors, and preview options.\nExamples: open cast bars; set target cast bar height to 24; move focus cast bar down; make boss cast bars wider; change cast bar texture.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant cast bars help",
        }
    end
    if ContainsAny(norm, { "castbar", "castbars", "cast bar", "cast bars" })
        and ContainsAny(norm, CASTBAR_TEXT_HELP_TERMS)
        and not ContainsAny(norm, { "texture", "textures", "bar texture", "castbar texture", "cast bar texture" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Cast Bar text help\nIn Cast Bars, I can help with cast bar text size, X/Y offsets, visibility, and related cast bar details.\nExamples: move target cast bar text left; set focus cast bar text size to 14; make boss cast bar text bigger.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant cast bar text help",
        }
    end
    if ContainsAny(norm, { "interrupt color", "interruptible color", "uninterruptible color", "castbar interrupt color", "cast bar interrupt color" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Cast Bar interrupt color help\nInterruptible and uninterruptible cast colors are Cast Bar color options. They are separate from the Interrupt Ready indicator, which shows whether your interrupt is ready.\nExamples: set interruptible cast color to blue; set uninterruptible cast color to red; explain kick ready indicator.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant cast bar interrupt color help",
        }
    end
    if ContainsAny(norm, CLASS_RESOURCE_HELP_TERMS)
        and ContainsAny(norm, { "width", "height", "size", "wider", "taller", "gap", "spacing", "color", "colors", "anchor", "position", "placement", "style", "mode", "fill", "reverse", "direction", "backwards", "breite", "hoehe", "groesse", "abstand", "farbe", "farben", "anker", "platzierung", "stil", "fuellrichtung", "rueckwaerts" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Class Resources help\nClass Resources covers visibility, size, width/height, gap, placement, anchor, style, fill direction, per-resource, per-slot, and full-at-maximum colors, the managed Player Power bar, the second Player HP bar, and alternative mana. Color requests understand resource names, class/spec names, common short forms, and ordinals.\nExamples: make class resources wider; set essence 3 cyan; make first paladin point gold; set full frost icicles blue; use a ramp for chi; disable full rune color.\nYou can ask: Open Class Resources | Open Colors",
            status = "applied",
            summary = "Assistant class resources help",
        }
    end
    if ContainsAny(norm, { "diagnostic", "diagnostics", "debug report", "debug", "health check", "repair", "check broken", "run checks", "diagnostik", "diagnosebericht", "fehlerbericht", "fehlersuche" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Troubleshooting help\nI can summarize MSUF options, find profile/setup problems, inspect visibility issues, build support text, and guide the fixes MSUF can run.\nExamples: run checks; assistant support text; check profile problems; why are target buffs hidden; fix broken profile links; open display recovery.\nYou can ask: Run Checks | Open Display & Recovery",
            status = "applied",
            summary = "Assistant troubleshooting help",
        }
    end
    if not ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, { "menu scale", "ui scale", "msuf frame scale", "msuf frames scale", "dashboard scale", "dashboard scaling", "options scale", "menu bigger", "menu smaller" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Dashboard scaling help\nIn Dashboard > Scaling, I can help with UI scale, Menu scale, and MSUF frame scale. The Dashboard also handles applying or reverting those scale changes.\nExamples: open dashboard scaling; make menu bigger; set MSUF frame scale to 100.\nYou can ask: Open Dashboard Scaling",
            status = "applied",
            summary = "Assistant dashboard scaling help",
        }
    end
    if ContainsAny(norm, { "display recovery", "display and recovery", "recovery tools", "dashboard recovery", "factory reset", "print help" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Display & Recovery help\nOn the Dashboard, Display & Recovery contains recovery tools such as Print Help, Discord/support links, and Factory Reset staging. Use it when the menu or profile state looks broken and you need a safe recovery path.\nExamples: open display recovery; print help; factory reset all; copy support link.\nYou can ask: Open Display & Recovery | Run Checks",
            status = "applied",
            summary = "Assistant display recovery help",
        }
    end
    if ContainsAny(norm, { "edit mode", "editmode", "frame edit mode", "anchor picker", "move frames mode", "bearbeitungsmodus", "editmodus", "anker picker", "rahmen verschieben" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Edit Mode help\nIn MSUF Edit Mode, I can help you move frames visually, show previews/grid/snap, open the anchor picker, undo/redo Edit Mode position changes, or reset the active edit position. I can enter, exit, cancel, toggle, and check Edit Mode.\nExamples: enter MSUF edit mode; turn on edit mode grid; set edit mode grid spacing to 24; turn off edit mode previews; open anchor picker; exit edit mode; am I in edit mode?\nYou can ask: Enter Edit Mode | Open Edit Mode Anchor Picker | Exit Edit Mode",
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
            text = "Group frame scaling breakpoints\nRaid scaling can use player-count breakpoints: 1-10, 11-20, 21-25, and 26+ players. MSUF applies the matching scale for the current raid size when Group Layout scaling is enabled.\nExamples: set raid scale for 20 players to 80; scale raid for 10m to 95; increase raid scale for 20m by 5.\nYou can ask: Open Group Layout",
            status = "applied",
            summary = "Assistant group scaling help",
        }
    end
    if ContainsAny(norm, { "detached power", "detached power bar", "detached mana", "power bar detached", "detached player power", "class resources player power", "class resource player power", "abgekoppelte energie", "spieler energieleiste" })
        and ContainsAny(norm, { "explain", "what is", "what does", "how", "where", "offset", "position", "help", "erklaeren", "erklaer", "wo", "hilfe", "versatz" })
    then
        return {
            text = "Detached Power Bar help\nEach unit page has Power Bar options for that unit's detached Power Bar. On Class Resources, the Player Power Bar section manages the Player detached power bar plus sync and Class Resources anchoring options.\nExamples: detach target power bar; move target power bar left; class resources player power height 8; sync class resources player power width; anchor class resources player power to class resource.\nYou can ask: Open Player | Open Target | Open Class Resources",
            status = "applied",
            summary = "Assistant detached power help",
        }
    end
    if ContainsAny(norm, { "powerbar offset", "power bar offset", "powerbar x", "powerbar y", "power bar x", "power bar y", "powerbar position", "power bar position" })
        and ContainsAny(norm, { "where", "where do", "where can", "change", "set", "move", "offset", "position", "help", "explain" })
    then
        return {
            text = "Power Bar offset help\nNormal Power text offsets live under each unit page's Text/Power text section. If you mean the separated bar itself, first detach that unit's Power Bar, then change Detached Power Bar X/Y Offset.\nExamples: move target power text left; detach target power bar; move target power bar left; set target power bar x offset to 12.\nYou can ask: Open Player | Open Target",
            status = "applied",
            summary = "Assistant power bar offset help",
        }
    end
    if ContainsAny(norm, { "role power", "healer power", "healer power bar", "tank power", "tank power bar", "dps power", "dps power bar", "damager power", "damager power bar" })
        and ContainsAny(norm, { "where", "help", "how", "show", "hide", "turn on", "turn off", "enable", "disable" })
    then
        return {
            text = "Group role Power Bar help\nGroup Frames can show or hide Power Bars by role through the Tank, Healer, and DPS Power options.\nExamples: hide healer power bars in raid frames; show tank power in party frames; hide dps power in raid frames.\nYou can ask: Open Group Health & Text",
            status = "applied",
            summary = "Assistant group role power help",
        }
    end
    if ContainsAny(norm, { "cooldown manager", "cooldownmanager", "essential cooldown", "essential cooldowns", "cdm" })
        and ContainsAny(norm, { "anchor", "anchoring", "attach", "where", "help", "explain", "how" })
    then
        return {
            text = "Cooldown Manager anchoring help\nUnit frames can anchor to the Essential Cooldown Viewer through their anchor target option. Group frames use a custom anchor frame, and Class Resources have their own Essential Cooldowns anchor toggle.\nExamples: anchor unit frames to Cooldown Manager; put player and target near Cooldown Manager; put raid frames near Cooldown Manager; anchor class resources to Essential Cooldown Manager.\nYou can ask: Open Player | Open Group Layout | Open Class Resources",
            status = "applied",
            summary = "Assistant cooldown manager anchor help",
        }
    end
    if ContainsAny(norm, { "interrupt ready", "kick ready", "ready interrupt", "ready kick", "interrupt bereit", "kick bereit", "unterbrechung bereit" })
        and ContainsAny(norm, { "explain", "what is", "what does", "where", "where is", "where do", "help", "mean", "indicator", "icon", "border" })
    then
        return {
            text = "Interrupt Ready Indicator help\nInterrupt Ready can show whether your interrupt is ready on Target, Focus, or Boss cast bars. Its style, anchor, size, auto-size, offsets, and ready/not-ready colors are Cast Bar options.\nExamples: show kick ready on target; put kick ready indicator left; move interrupt ready down by 3; make kick ready icon bigger.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant interrupt ready help",
        }
    end
    if ContainsAny(norm, { "focus kick", "focus kick tracker", "focus kick icon", "focus interrupt tracker", "focus interrupt icon", "fokus kick", "fokus kick tracker", "fokus kick anzeige", "fokus interrupt tracker" })
        and ContainsAny(norm, { "explain", "what is", "what does", "where", "where is", "where do", "help", "tracker", "icon", "position", "size" })
    then
        return {
            text = "Focus Kick Tracker help\nFocus Kick is the Cast Bar Focus Interrupt Tracker. It has options for visibility, preview, width, height, text size, and X/Y offsets.\nExamples: show focus kick tracker; move focus kick tracker left 10; make focus kick tracker bigger; reset focus kick position.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant focus kick help",
        }
    end
    if ContainsAny(norm, GROUP_FRAME_SCOPE_TERMS)
        and ContainsAny(norm, { "reverse fill", "reverse health fill", "fill backwards", "backwards fill", "right to left fill", "fill direction", "normal direction" })
        and ContainsAny(norm, KNOWLEDGE_INTENT_TERMS)
    then
        return {
            text = "Group reverse fill help\nIn Group Layout, Party, Raid, and Mythic Raid each have a Reverse Health Fill option. It flips health fill direction; normal direction turns Reverse Health Fill off.\nExamples: make raid frames fill backwards; make party frames fill normal direction; turn off raid reverse fill.\nYou can ask: Open Group Layout",
            status = "applied",
            summary = "Assistant group reverse fill help",
        }
    end
    if ContainsAny(norm, { "castbar fill", "cast bar fill", "fill direction", "castbar direction", "cast bar direction", "left to right fill", "right to left fill", "opposite fill", "reverse fill", "backwards fill", "normal direction" })
        and ContainsAny(norm, { "castbar", "cast bar" })
        and ContainsAny(norm, { "fill", "direction", "left to right", "right to left", "opposite", "reverse", "backwards", "normal", "where", "explain", "what", "help" })
    then
        return {
            text = "Cast Bar fill direction help\nCast Bar Fill Direction sets the default direction for cast progress. Target can also use the opposite fill direction through its Target Opposite Direction option.\nExamples: make cast bar fill left to right; make cast bar fill backwards; make target cast bar fill opposite; make target cast bar use normal direction.\nYou can ask: Open Cast Bars",
            status = "applied",
            summary = "Assistant cast bar fill help",
        }
    end
    if ContainsAny(norm, { "combat timer" })
        and ContainsAny(norm, { "lock", "locked", "unlock", "click through", "click-through", "clickable", "where", "what", "explain", "help" })
    then
        return {
            text = "Combat Timer help\nIn Gameplay, I can help with Combat Timer options. You can enable it, set its anchor, move it, resize its text, lock its position, or make it click-through. Click-through means the timer ignores mouse clicks; clickable turns click-through off.\nExamples: lock combat timer; unlock combat timer; make combat timer click through; make combat timer clickable; move combat timer up 10.\nYou can ask: Open Gameplay",
            status = "applied",
            summary = "Assistant combat timer help",
        }
    end
    if ContainsAny(norm, { "totem icon", "totem icons", "totem frame", "totems", "statue frame", "totem rahmen", "totemrahmen", "statuen rahmen", "statuenrahmen" })
        and ContainsAny(norm, { "where", "where can", "where do", "make", "bigger", "smaller", "size", "move", "offset", "position", "help", "explain", "wo", "hilfe", "erklaeren", "erklaer", "groesse", "groesser", "kleiner", "verschieben", "verschiebe", "versatz" })
    then
        return {
            text = "Totem Frame help\nIn Gameplay, I can help with Totem/Statue frame options. I can enable the frame, resize the icons, move the frame by X/Y offset, change its anchor points, preview it, or reset its layout.\nExamples: show totem frame; make totem icons bigger; move totem icons right 6; set totem frame to anchor to bottom left; preview totem frame; reset totem frame.\nYou can ask: Open Gameplay",
            status = "applied",
            summary = "Assistant totem frame help",
        }
    end
    if ContainsAny(norm, { "combat crosshair", "crosshair", "melee range crosshair", "melee range spell", "fadenkreuz" })
        and ContainsAny(norm, { "where", "where can", "where do", "what", "what is", "what does", "help", "explain", "size", "thickness", "spell", "range", "color", "wo", "hilfe", "erklaeren", "erklaer", "groesse", "dicke", "farbe" })
    then
        return {
            text = "Combat Crosshair help\nIn Gameplay, I can help with Combat Crosshair options. You can enable it, set size and thickness, configure in-range/out-of-range colors, and set the melee range spell used for range checks.\nExamples: show combat crosshair; make combat crosshair thicker; set crosshair size to 60; set crosshair melee spell 100780.\nYou can ask: Open Gameplay",
            status = "applied",
            summary = "Assistant combat crosshair help",
        }
    end
    if ContainsAny(norm, { "role sorting", "role sort", "sort by role", "group role sorting", "group frame role sorting", "party role sort", "raid role sort" })
        and ContainsAny(norm, { "where", "where is", "where do", "what", "explain", "help", "sorting", "sort" })
    then
        return {
            text = "Group role sorting help\nIn Group Layout, I can help with group frame sorting. MSUF can sort party/raid groups with the sort options for that group target.\nExamples: set raid sort to role; set party sort to group; put player first in role.\nYou can ask: Open Group Layout",
            status = "applied",
            summary = "Assistant group role sorting help",
        }
    end
    if ContainsAny(norm, { "what can i change", "what settings can i change", "what can i do" })
        and ContainsAny(norm, { "raid frame", "raid frames", "party frame", "party frames", "group frame", "group frames" })
    then
        return PageHelp("gf_layout")
    end
    if ContainsAny(norm, { "what can i change", "what settings can i change", "what can i do" })
        and ContainsAny(norm, { "group health", "group text", "group health and text", "party health", "party text", "raid health", "raid text", "mythic raid health", "mythic raid text" })
    then
        return PageHelp("gf_bars")
    end
    if ContainsAny(norm, { "what can i change", "what settings can i change", "what can i do" })
        and ContainsAny(norm, { "group aura", "group auras", "party aura", "party auras", "raid aura", "raid auras", "group buff", "group buffs", "group debuff", "group debuffs" })
    then
        return PageHelp("gf_auras")
    end
    if ContainsAny(norm, { "what can i change", "what settings can i change", "what can i do" })
        and ContainsAny(norm, { "module", "modules", "style module", "msuf style", "dropdown style" })
    then
        return PageHelp("modules")
    end
    for i = 1, #SCOPED_HELP_ALIASES do
        local spec = SCOPED_HELP_ALIASES[i]
        if ContainsAny(norm, spec.terms) then
            if spec.special == "editmode" then
                return {
                    text = "Edit Mode help\nI can enter, exit, toggle, cancel, check whether Edit Mode is active, change grid/snap/preview options, open the anchor picker, or undo/redo Edit Mode position changes.\nExamples: enter MSUF edit mode; turn on edit mode grid; turn off edit mode previews; toggle edit mode; am I in edit mode?\nYou can ask: Enter Edit Mode | Exit Edit Mode | Edit Mode Status",
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
    if item.canOpen and item.page then actions[#actions + 1] = "Open " .. tostring(ItemPageLabel(item) or "MSUF page") end
    if item.kind == "setting" then
        actions[#actions + 1] = "Explain"
        local example = ExampleCommand(item)
        if example then actions[#actions + 1] = example:gsub("^%a+:%s*", "") end
    elseif item.kind == "faq" then
        actions[#actions + 1] = "Related Options"
    elseif item.kind == "page" then
        actions[#actions + 1] = "Show page help"
    elseif item.kind == "action" or item.kind == "diagnostic" then
        actions[#actions + 1] = "Run/ask this"
    end
    return ActionLine(actions)
end

-- Knowledge is read-only. Keep this normalization at the public boundary so
-- every existing and future direct-help branch has the same truthful status,
-- including branches that still construct their internal table as "applied".
local function AsReadOnlyKnowledgeResult(result)
    if type(result) ~= "table" then return result end
    if result.status == "applied" then result.status = "info" end
    if result.result == "applied" then result.result = "info" end
    return result
end

function K.Answer(query, opts)
    opts = opts or {}
    if opts.forceSearch ~= true then
        local changelog = ChangelogAnswer(query)
        if changelog then return AsReadOnlyKnowledgeResult(changelog) end

        local direct = DirectHelpAnswer(query, opts)
        if direct then return AsReadOnlyKnowledgeResult(RememberKnowledgeHelpContext(direct)) end
    end

    local results = K.Search(query, MAX_RESULTS, opts)
    -- Search deliberately returns nil while the index is cold. Propagate that
    -- sentinel so the router/deferred job path can continue safely instead of
    -- indexing a nil value or claiming that no match exists.
    if type(results) ~= "table" then return nil end
    if #results == 0 then return nil end
    local intent = opts.forceSearch == true and "location" or QueryIntent(query)
    local topResult = results[1]
    local top = topResult.item

    if intent == "help" and top.kind == "faq" and top.answer and top.answer ~= "" then
        local lines = { tostring(top.answer) }
        if top.target and top.target ~= "" then lines[#lines + 1] = "Target: " .. tostring(top.target) end
        local openText = OpenPageText(top)
        if openText then lines[#lines + 1] = openText end
        local action = ActionableHint(top)
        if action then lines[#lines + 1] = action end
        return AsReadOnlyKnowledgeResult(RememberKnowledgeHelpContext({ text = table.concat(lines, "\n"), status = "info", summary = "Assistant FAQ answer" }))
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
        return { text = table.concat(lines, "\n"), status = "info", summary = "Assistant search result", searchResults = ResultFollowups(results, 4) }
    end

    if top.kind == "faq" and top.answer and top.answer ~= "" and (intent == "help" or (topResult.score or 0) > 650) then
        local lines = { tostring(top.answer) }
        if top.target and top.target ~= "" then lines[#lines + 1] = "Target: " .. tostring(top.target) end
        local openText = OpenPageText(top)
        if openText then lines[#lines + 1] = openText end
        local action = ActionableHint(top)
        if action then lines[#lines + 1] = action end
        return AsReadOnlyKnowledgeResult(RememberKnowledgeHelpContext({ text = table.concat(lines, "\n"), status = "info", summary = "Assistant FAQ answer" }))
    end

    local lines = { "I found these MSUF matches:" }
    for i = 1, math.min(#results, 5) do lines[#lines + 1] = FormatResultLine(i, results[i].item) end
    lines[#lines + 1] = "You can ask me to open a page, explain a result, or change an option directly."
    local example = ExampleCommand(top)
    if example then lines[#lines + 1] = example end
    local action = ActionableHint(top)
    if action then lines[#lines + 1] = action end
    return { text = table.concat(lines, "\n"), status = "info", summary = "Assistant knowledge result", searchResults = ResultFollowups(results, 5) }
end

local NO_MATCH_SEARCH_SIGNAL_TERMS = {
    "msuf", "menu", "setting", "settings", "option", "options", "page", "where", "help", "explain", "find", "search",
    "player", "target", "focus", "pet", "boss", "party", "raid", "mythic", "frame", "frames", "unitframe", "group",
    "health", "hp", "power", "mana", "name", "text", "font", "bar", "bars", "texture", "color", "colour",
    "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar",
    "width", "height", "size", "scale", "alpha", "opacity", "anchor", "position", "offset", "spacing", "gap",
    "border", "portrait", "indicator", "status", "cooldown", "stack", "filter", "profile", "copy", "reset",
    "gameplay", "crosshair", "totem", "class power", "class resource", "resource",
}

local NO_MATCH_SEARCH_LOW_SIGNAL_TOKENS = {
    a = true, an = true, the = true, to = true, of = true, on = true, ["in"] = true, ["for"] = true, with = true,
    make = true, set = true, change = true, turn = true, ["do"] = true, please = true, pls = true,
    can = true, could = true, would = true, will = true, you = true, i = true, want = true, need = true,
    vague = true, thing = true, stuff = true, something = true, anything = true,
}

local function ShouldSearchNoMatchCandidates(query)
    local cleaned = SearchQueryText(query)
    local norm = Normalize(cleaned ~= "" and cleaned or query)
    if norm == "" then return false end
    if ContainsAny(norm, NO_MATCH_SEARCH_SIGNAL_TERMS) then return true end
    local meaningful = 0
    for token in norm:gmatch("%S+") do
        if #token >= 3 and not NO_MATCH_SEARCH_LOW_SIGNAL_TOKENS[token] then
            meaningful = meaningful + 1
            if meaningful >= 4 then return true end
        end
    end
    return false
end

function K.NoMatch(query)
    local results
    if ShouldSearchNoMatchCandidates(query) then
        results = K.Search(query, 3, { ignoreCurrentPage = true })
    end
    if type(results) == "table" and #results > 0 and (tonumber(results[1].score) or 0) >= 360 then
        local lines = {
            "I'm not sure which MSUF request you mean yet, so I did not change anything.",
            "Closest MSUF matches I found:",
        }
        for i = 1, math.min(#results, 3) do
            lines[#lines + 1] = FormatResultLine(i, results[i].item)
        end
        local top = results[1] and results[1].item
        local example = ExampleCommand(top)
        if example then lines[#lines + 1] = example end
        lines[#lines + 1] = "You can ask me to open a result, explain it, or give a more specific frame/page plus value."
        return {
            text = table.concat(lines, "\n"),
            status = "info",
            summary = "Assistant help fallback with close matches",
            searchResults = ResultFollowups(results, 3),
        }
    end
    return {
        text = "I'm not sure which MSUF request you mean yet.\nI can help once I can match the request to an MSUF menu option. Include the frame or page plus the option, for example 'set target cast bar height to 20' or 'turn on party dead background'. For aura requests, I change aura options that exist in the MSUF menu.\nIf that wording should work, share the exact text in Discord: " .. DISCORD_INVITE,
        status = "info",
        summary = "Assistant help fallback",
    }
end

function K.Summary()
    local index = K.EnsureIndexIfSafe()
    if not index then return nil end
    if type(K.summaryCache) == "table" and K.summaryCacheIndex == index then return K.summaryCache end
    local counts = {}
    for i = 1, #(index.items or {}) do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local kind = index.items[i].kind or "unknown"
        counts[kind] = (counts[kind] or 0) + 1
    end
    K.summaryCache = counts
    K.summaryCacheIndex = index
    return counts
end
