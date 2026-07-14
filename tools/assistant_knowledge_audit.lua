_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local addonRoot = "MidnightSimpleUnitFrames/Shell/Menu2/"
if not exists(addonRoot .. "Search/MSUF_Menu2_Search_Data.lua") then
    addonRoot = "Shell/Menu2/"
end
local searchRoot = addonRoot
if not exists(searchRoot .. "Search/MSUF_Menu2_Search_Data.lua") then
    searchRoot = "MidnightSimpleUnitFrames/Menu2/"
    if not exists(searchRoot .. "Search/MSUF_Menu2_Search_Data.lua") then
        searchRoot = "Menu2/"
    end
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = {},
    focus = {},
    pet = {},
    targettarget = {},
    focustarget = {},
    boss = {},
    gf_party = {},
    gf_raid = {},
    gf_mythicraid = {},
}

_G.GetLocale = function() return "enUS" end
_G.InCombatLockdown = function() return false end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = _G.CopyTable(v) end
    return out
end

local unpack = table.unpack or unpack
local M = MSUF.MSUF2
M.activeKey = "home"
M.Tr = function(text) return tostring(text or "") end
M.Format = function(fmt, ...) return string.format(tostring(fmt or ""), ...) end
M.WordList = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end
M.KeySetFromWords = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[word] = true end
    return out
end
M.Pick = function(source, names)
    local values, count = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        values[count] = source and source[name]
    end
    return unpack(values, 1, count)
end
M.PickDefaults = function(source, names)
    local values, count = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        values[count] = (source and source[name]) or {}
    end
    return unpack(values, 1, count)
end

local function loadAddon(relative)
    local path = addonRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function loadSearch(relative)
    local path = searchRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local searchFiles = {
    "Search/MSUF_Menu2_Search_Data.lua",
    "Search/MSUF_Menu2_Search_Keywords.lua",
    "Search/MSUF_Menu2_Search_QueryAliases.lua",
    "Search/MSUF_Menu2_Search_FAQ.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_01.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_02.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_03.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_04.lua",
    "Search/MSUF_Menu2_Search_Text.lua",
    "Search/MSUF_Menu2_Search_IndexQuery.lua",
    "Search/MSUF_Menu2_Search_API.lua",
}
for _, file in ipairs(searchFiles) do loadSearch(file) end
local runtimeLoaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(runtimeLoaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local Registry = assert(A.Registry, "Assistant registry missing")
local Knowledge = assert(A.Knowledge, "Assistant knowledge missing")
assert(type(Knowledge.Search) == "function", "Knowledge search missing")

local function contains(text, needle)
    return tostring(text or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

local function isAuraItem(item)
    local haystack = table.concat({
        tostring(item.key or ""),
        tostring(item.page or ""),
        tostring(item.frameType or ""),
        tostring(item.category or ""),
    }, " "):lower()
    return haystack:find("aura", 1, true) ~= nil
        or haystack:find("buff", 1, true) ~= nil
        or haystack:find("debuff", 1, true) ~= nil
end

local function isExcludedSetting(setting)
    if isAuraItem(setting) then return true end
    local key = tostring(setting.key or ""):lower()
    local label = tostring(setting.label or ""):lower()
    -- Unit-frame shape is intentionally outside the current Assistant goal.
    if key == "bars.roundedunitframes" or label:find("unitframe shape", 1, true) then return true end
    return false
end

local function isExcludedAction(action)
    if isAuraItem(action) then return true end
    return false
end

local function hasItem(results, key)
    for i = 1, #(results or {}) do
        local item = results[i] and results[i].item
        if item and item.key == key then return true end
    end
    return false
end

local function usefulAnswer(answer)
    if type(answer) ~= "table" then return false end
    local text = tostring(answer.text or "")
    if text == "" then return false end
    if contains(text, "I could not safely match") then return false end
    if contains(text, "Aura commands are intentionally disabled") then return false end
    return true
end

local failures = {}
local counts = { settings = 0, actions = 0, indexed = 0, keySearches = 0, naturalSearches = 0, answers = 0 }

local function addFailure(kind, key, detail)
    failures[#failures + 1] = kind .. " " .. tostring(key or "?") .. ": " .. tostring(detail or "")
end

local index = Knowledge.EnsureIndex()
local indexedKeys = {}
local indexedItems = {}
for _, item in ipairs(index.items or {}) do
    if item and item.key then
        indexedKeys[item.key] = true
        indexedItems[tostring(item.kind or "") .. ":" .. tostring(item.key)] = item
    end
end

local function hasKnownPage(kind, key)
    local item = indexedItems[tostring(kind or "") .. ":" .. tostring(key or "")]
    return item and type(item.page) == "string" and item.page ~= ""
end

local function parseLimit(value, fallback)
    if value == "all" then return 0 end
    return tonumber(value) or fallback
end

local function genericSearchPhrase(text)
    local norm = tostring(text or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return norm == ""
        or norm == "enable"
        or norm == "enabled"
        or norm == "show"
        or norm == "hide"
        or norm == "width"
        or norm == "height"
        or norm == "size"
        or norm == "x offset"
        or norm == "y offset"
        or norm == "color"
        or norm == "background"
        or norm == "opacity"
        or norm == "anchor"
        or norm == "layer"
end

local UNIT_LABELS = {
    player = "Player",
    target = "Target",
    focus = "Focus",
    pet = "Pet",
    targettarget = "Target of Target",
    focustarget = "Focus Target",
    boss = "Boss",
    party = "Party",
    raid = "Raid",
    mythicraid = "Mythic Raid",
    gf_party = "Party",
    gf_raid = "Raid",
    gf_mythicraid = "Mythic Raid",
}

local function settingScopeLabel(setting)
    local unit = tostring(setting and setting.unit or "")
    if UNIT_LABELS[unit] then return UNIT_LABELS[unit] end
    local key = tostring(setting and setting.key or "")
    local scope = key:match("^barScope%.([^%.]+)") or key:match("^fontScope%.([^%.]+)") or key:match("^(gf_[^%.]+)")
    return UNIT_LABELS[scope]
end

local function naturalSettingQuery(setting)
    local key = tostring(setting and setting.key or "")
    for _, alias in ipairs(setting and setting.aliases or {}) do
        alias = tostring(alias or "")
        if alias ~= "" and alias ~= key and not genericSearchPhrase(alias) then return alias end
    end
    local label = tostring(setting and setting.label or key)
    local scope = settingScopeLabel(setting)
    if scope and not contains(label, scope) then return scope .. " " .. label end
    return label
end

local function naturalActionQuery(action)
    for _, alias in ipairs(action and action.aliases or {}) do
        alias = tostring(alias or "")
        if alias ~= "" and not genericSearchPhrase(alias) then return alias end
    end
    return tostring(action and action.label or action and action.key or "")
end

local function pageContextForItem(item)
    local key = tostring(item and item.key or "")
    local frameType = tostring(item and item.frameType or "")
    local unit = tostring(item and item.unit or "")
    local category = tostring(item and item.category or ""):lower()
    if frameType == "unitframe" then
        if unit == "targettarget" then return "uf_targettarget" end
        if unit == "focustarget" then return "uf_focustarget" end
        if unit ~= "" and unit ~= "global" then return "uf_" .. unit end
    end
    if frameType == "group" or key:find("^gf_") then
        local keyLower = key:lower():gsub("%s+", "")
        local attrLower = tostring(item and item.attribute or ""):lower():gsub("%s+", "")
        if category:find("indicator", 1, true) or keyLower:find("icon", 1, true) then return "gf_indicators" end
        if keyLower:find("dispeloverlay", 1, true) or attrLower:find("dispeloverlay", 1, true)
            or keyLower:find("debuffstripe", 1, true) or attrLower:find("debuffstripe", 1, true)
        then
            return "gf_bars"
        end
        return "gf_layout"
    end
    if frameType == "castbar" then return "opt_castbar" end
    if frameType == "classPower" or key:find("classPower", 1, true) then return "classpower" end
    if frameType == "gameplay" or key:find("^gameplay%.") then return "gameplay" end
    if frameType == "profiles" then return "profiles" end
    if frameType == "globalBars" or frameType == "bars" or key:find("^barScope%.") then return "opt_bars" end
    if frameType == "fonts" or key:find("^fontScope%.") then return "opt_fonts" end
    if frameType == "colors" then
        if key:find("classPower", 1, true) then return "classpower" end
        return "opt_colors"
    end
    if frameType == "dashboard" or key:find("^menu%.") then return "home" end
    return "home"
end

local function applyPageContext(item)
    M.activeKey = pageContextForItem(item)
    local unit = tostring(item and item.unit or "")
    if unit == "party" or unit == "raid" or unit == "mythicraid" then M.gfScope = unit end
end

local searchSamples = {}
local function addSearchSample(kind, key, naturalQuery, item)
    if key and key ~= "" then searchSamples[#searchSamples + 1] = { kind = kind, key = key, naturalQuery = naturalQuery, item = item } end
end

local sampleSettingLimit = parseLimit(arg and arg[1], 180)
local settingStride = 1
local allSettings = Registry:AllSettings() or {}
if #allSettings > sampleSettingLimit and sampleSettingLimit > 0 then
    settingStride = math.max(1, math.floor(#allSettings / sampleSettingLimit))
end

for i, setting in ipairs(allSettings) do
    if not isExcludedSetting(setting) then
        counts.settings = counts.settings + 1
        local key = tostring(setting.key or "")
        if key ~= "" and indexedKeys[key] then
            counts.indexed = counts.indexed + 1
        else
            addFailure("setting index", key, tostring(setting.label or ""))
        end
        if key ~= "" and hasKnownPage("setting", key) then
            counts.paged = (counts.paged or 0) + 1
        else
            addFailure("setting page", key, tostring(setting.label or ""))
        end
        if i % settingStride == 0 and (sampleSettingLimit == 0 or #searchSamples < sampleSettingLimit) then
            addSearchSample("setting", key, naturalSettingQuery(setting), setting)
        end
    end
end

for _, action in ipairs(Registry:AllActions() or {}) do
    if not isExcludedAction(action) then
        counts.actions = counts.actions + 1
        local key = tostring(action.key or "")
        if key ~= "" and indexedKeys[key] then
            counts.indexed = counts.indexed + 1
        else
            addFailure("action index", key, tostring(action.label or action.summary or ""))
        end
        local actionKind = action.type == "diagnostic" and "diagnostic" or "action"
        if key ~= "" and hasKnownPage(actionKind, key) then
            counts.paged = (counts.paged or 0) + 1
        else
            addFailure("action page", key, tostring(action.label or action.summary or ""))
        end
        addSearchSample(action.type == "diagnostic" and "diagnostic" or "action", key, naturalActionQuery(action), action)
    end
end

for _, sample in ipairs(searchSamples) do
    applyPageContext(sample.item)
    local results = Knowledge.Search(sample.key, 10, { kind = sample.kind })
    if hasItem(results, sample.key) then
        counts.keySearches = counts.keySearches + 1
    else
        addFailure(sample.kind .. " key search", sample.key, sample.key)
    end
    if sample.naturalQuery and sample.naturalQuery ~= "" then
        results = Knowledge.Search(sample.naturalQuery, 10, { kind = sample.kind })
        if hasItem(results, sample.key) then
            counts.naturalSearches = counts.naturalSearches + 1
        else
            addFailure(sample.kind .. " natural search", sample.key, sample.naturalQuery)
        end
    end
end

local answerProbes = {
    { "where can I change raid frame width", "Group frame layout help" },
    { "where can I hide offline players in raid frames", "Group frame layout help" },
    { "where can I change party health text", "Group Layout" },
    { "where can I change group frame status icons", "Group Status & Indicators help" },
    { "where can I change target health text", "Unit frame text help" },
    { "where can I move target castbar text", "Cast Bar text help" },
    { "where can I change castbar interrupt color", "Cast Bar interrupt color help" },
    { "where can I change combo point colors", "Class Resources help" },
    { "where can I run diagnostics", "Troubleshooting help" },
    { "where can I reset the menu scale", "Dashboard scaling help" },
    { "where can I open edit mode", "Edit Mode help" },
    { "explain raid frame player count scaling", "Group frame scaling breakpoints" },
    { "where is detached power bar offset", "Detached Power Bar help" },
    { "where do I change target powerbar offset", "Power Bar offset help" },
    { "where do I hide healer power bars in raid", "Group role Resource Bar help" },
    { "where is group frame role sorting", "Group role sorting help" },
}

for _, probe in ipairs(answerProbes) do
    local answer = Knowledge.Answer(probe[1], { currentPage = "home" })
    local text = tostring(answer and answer.text or "")
    if usefulAnswer(answer) and contains(text, probe[2]) then
        counts.answers = counts.answers + 1
    else
        addFailure("answer probe", probe[1], probe[2] .. " actual=" .. text:sub(1, 160))
    end
end

if #failures > 0 then
    local maxFailures = tonumber(arg and arg[2]) or tonumber(arg and arg[1]) or 80
    io.stderr:write("assistant_knowledge_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, maxFailures) do
        io.stderr:write(failures[i] .. "\n")
    end
    os.exit(1)
end

io.write(string.format(
    "assistant_knowledge_audit: ok settings=%d actions=%d indexed=%d paged=%d keySearches=%d naturalSearches=%d answers=%d\n",
    counts.settings,
    counts.actions,
    counts.indexed,
    counts.paged or 0,
    counts.keySearches,
    counts.naturalSearches,
    counts.answers
))
