_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local A = assert(MSUF.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")
local Knowledge = assert(A.Knowledge, "Assistant knowledge missing")
assert(type(Knowledge.Search) == "function", "Knowledge search missing")

local bannedTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "zurueck", "zur\195\188ck", "rueck", "rueckgaengig", "abbrechen",
    "anwenden", "ausfuehren", "ausf\195\188hren", "hilfe", "spieler", "ziel",
    "auren", "profil", "zauberleiste", "menue", "fuer", "loeschen", "l\195\182schen",
    "kopiere", "verschiebe", "groesse", "gr\195\182sse", "hoehe", "h\195\182he",
    "breite", "einstellungen", "assistent", "nicht", "keine",
}

local internalLabelTerms = {
    "auras3", "gf_", "uf_", "classpower", "opt_castbar", "opt_bars",
    "opt_colors", "opt_fonts", "opt_misc", "targettarget", "focustarget",
}

local visibleFields = {
    "category", "description", "summary", "target", "tooltip", "valueLabel", "confirmText",
}

local failures = {}

local function addFailure(kind, key, detail, value)
    failures[#failures + 1] = table.concat({
        tostring(kind or "item"),
        tostring(key or "?"),
        tostring(detail or "failed"),
        tostring(value or ""),
    }, " | ")
end

local function normalizeWords(text)
    text = tostring(text or ""):lower():gsub("[^%w_]+", " "):gsub("%s+", " ")
    return " " .. text .. " "
end

local function checkEnglish(kind, key, field, value)
    value = tostring(value or "")
    if value == "" then return end
    local haystack = normalizeWords(value)
    for _, term in ipairs(bannedTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        if haystack:find(needle, 1, true) then
            addFailure(kind, key, field .. " German visible term: " .. term, value)
        end
    end
end

local function checkDisplayLabel(kind, key, field, value)
    value = tostring(value or "")
    if value == "" then
        addFailure(kind, key, field .. " empty visible label", value)
        return
    end
    checkEnglish(kind, key, field, value)
    local lower = value:lower()
    for _, term in ipairs(internalLabelTerms) do
        if lower:find(term, 1, true) then
            addFailure(kind, key, field .. " internal label token: " .. term, value)
        end
    end
end

local function joinedItemText(item)
    return table.concat({
        tostring(item and item.key or ""),
        tostring(item and item.page or ""),
        tostring(item and item.frameType or ""),
        tostring(item and item.category or ""),
        tostring(item and item.label or ""),
        tostring(item and item.description or ""),
        tostring(item and item.summary or ""),
        tostring(item and item.target or ""),
        tostring(item and item.attribute or ""),
        tostring(item and item.unit or ""),
    }, " "):lower()
end

local function isAuraItem(item)
    if type(item) ~= "table" then return false end
    local key = tostring(item.key or ""):lower()
    if key:find("^auras3%.") or key:find("^gf_[^%.]+%.auras%.") or key:find("^aura_") then return true end
    if tostring(item.frameType or ""):lower() == "aura" then return true end
    local haystack = joinedItemText(item)
    return haystack:find("aura", 1, true) ~= nil
        or haystack:find("buff", 1, true) ~= nil
        or haystack:find("debuff", 1, true) ~= nil
end

local function actionIndexKind(action)
    return action and action.type == "diagnostic" and "diagnostic" or "action"
end

local function indexedKey(kind, key)
    return tostring(kind or "") .. ":" .. tostring(key or "")
end

local function hasResult(results, expectedKeys)
    local expected = {}
    for _, key in ipairs(expectedKeys or {}) do expected[tostring(key)] = true end
    for _, result in ipairs(results or {}) do
        local item = result and result.item
        if item and expected[tostring(item.key)] then return true end
    end
    return false
end

local function resultSummary(results)
    local lines = {}
    for i = 1, math.min(#(results or {}), 6) do
        local item = results[i] and results[i].item
        lines[#lines + 1] = tostring(i) .. ":" .. tostring(item and item.key or "?")
    end
    return table.concat(lines, ", ")
end

local counts = {
    settings = 0,
    actions = 0,
    indexed = 0,
    paged = 0,
    fixedSearches = 0,
    sampledKeySearches = 0,
    sampledNaturalSearches = 0,
}

local index = Knowledge.EnsureIndex()
local indexedItems = {}
for _, item in ipairs(index.items or {}) do
    if item and item.key then indexedItems[indexedKey(item.kind, item.key)] = item end
end

local auraSettings, auraActions = {}, {}
for _, setting in ipairs(Registry:AllSettings() or {}) do
    if isAuraItem(setting) then
        auraSettings[#auraSettings + 1] = setting
        counts.settings = counts.settings + 1
    end
end
for _, action in ipairs(Registry:AllActions() or {}) do
    if isAuraItem(action) then
        auraActions[#auraActions + 1] = action
        counts.actions = counts.actions + 1
    end
end

local function checkRegistryItem(kind, item)
    local key = tostring(item and item.key or "")
    local display
    if kind == "setting" and type(A.DisplaySettingLabel) == "function" then
        display = A.DisplaySettingLabel(item)
    elseif kind == "action" and type(A.DisplayActionLabel) == "function" then
        display = A.DisplayActionLabel(item)
    end
    checkDisplayLabel(kind, key, "label", item and item.label)
    checkDisplayLabel(kind, key, "displayLabel", display or (item and item.label))
    for _, field in ipairs(visibleFields) do checkEnglish(kind, key, field, item and item[field]) end
end

for _, setting in ipairs(auraSettings) do
    checkRegistryItem("setting", setting)
    local indexed = indexedItems[indexedKey("setting", setting.key)]
    if not indexed then
        addFailure("setting", setting.key, "missing from Knowledge index", "")
    else
        counts.indexed = counts.indexed + 1
        if type(indexed.page) == "string" and indexed.page ~= "" then
            counts.paged = counts.paged + 1
        else
            addFailure("setting", setting.key, "missing Knowledge page", tostring(indexed.page))
        end
        checkDisplayLabel("settingIndex", setting.key, "label", indexed.label)
        checkDisplayLabel("settingIndex", setting.key, "pageLabel", indexed.pageLabel)
    end
end

for _, action in ipairs(auraActions) do
    checkRegistryItem("action", action)
    local kind = actionIndexKind(action)
    local indexed = indexedItems[indexedKey(kind, action.key)]
    if not indexed then
        addFailure("action", action.key, "missing from Knowledge index", "")
    else
        counts.indexed = counts.indexed + 1
        if type(indexed.page) == "string" and indexed.page ~= "" then
            counts.paged = counts.paged + 1
        else
            addFailure("action", action.key, "missing Knowledge page", tostring(indexed.page))
        end
        checkDisplayLabel("actionIndex", action.key, "label", indexed.label)
        checkDisplayLabel("actionIndex", action.key, "pageLabel", indexed.pageLabel)
    end
end

local fixedSearchCases = {
    { "search target buff icon size", { "auras3.target.buff.size" } },
    { "find target debuff growth", { "auras3.target.debuff.growth" } },
    { "search shared cooldown text size", { "auras3.shared.cooldownTextSize" } },
    { "search shared buff cooldown text size", { "auras3.shared.buff.cooldownTextSize" } },
    { "search target buff stack text size", { "auras3.target.buff.stackTextSize" } },
    { "search aura editing scope", { "menu.auraScope", "set_aura_edit_scope" } },
    { "find hidden aura preset", { "menu.auraBlacklistPreset", "aura_blacklist_add_preset" } },
    { "search player aura filter only mine", { "auras3.player.buff.filter.onlyMine", "auras3.player.debuff.filter.onlyMine" } },
    { "search raid buff icon size", { "gf_raid.auras.buff.size" } },
    { "search raid debuff hidden category", { "gf_raid.auras.debuff.blacklistCats.COOLDOWNS", "gf_raid.auras.debuff.blacklistCats.AUGMENTATION_EVOKER" } },
    { "search show hidden aura spells", { "aura_blacklist_summary", "aura_group_blacklist_summary" } },
    { "search apply aura quick preset", { "apply_aura_quick_preset" } },
    { "search boss debuff max icons", { "auras3.boss.debuff.max" } },
    { "search party buff per row", { "gf_party.auras.buff.perRow" } },
    { "search group aura blacklist", { "aura_group_blacklist_add_preset", "aura_group_blacklist_summary", "aura_group_blacklist_clear_spells" } },
}

local function checkSearch(kind, query, expectedKeys, countField, limit)
    local results = Knowledge.Search(query, limit or 12) or {}
    counts[countField] = counts[countField] + 1
    if not hasResult(results, expectedKeys) then
        addFailure(kind, query, "search did not return expected key", resultSummary(results))
    end
    for i = 1, math.min(#results, 5) do
        local item = results[i] and results[i].item
        if item then
            checkDisplayLabel(kind .. "Result", tostring(item.key), "label", item.label)
            if item.pageLabel then checkDisplayLabel(kind .. "Result", tostring(item.key), "pageLabel", item.pageLabel) end
        end
    end
end

for _, case in ipairs(fixedSearchCases) do
    checkSearch("fixedSearch", case[1], case[2], "fixedSearches", 12)
end

local function sortedCopy(items)
    local out = {}
    for i = 1, #items do out[i] = items[i] end
    table.sort(out, function(a, b) return tostring(a.key or "") < tostring(b.key or "") end)
    return out
end

local function sampleItems(items, maxCount)
    items = sortedCopy(items)
    maxCount = tonumber(maxCount) or 0
    if maxCount <= 0 or #items <= maxCount then return items end
    local out, used = {}, {}
    local function add(item)
        if item and not used[item.key] then
            out[#out + 1] = item
            used[item.key] = true
        end
    end
    add(items[1])
    add(items[#items])
    local stride = math.max(1, math.floor(#items / maxCount))
    local pos = 1
    while #out < maxCount and pos <= #items do
        add(items[pos])
        pos = pos + stride
    end
    pos = 1
    while #out < maxCount and pos <= #items do
        add(items[pos])
        pos = pos + 1
    end
    return out
end

local function naturalSettingQuery(setting)
    local label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or "")
    local category = tostring(setting.category or "")
    if category ~= "" then return "search " .. label .. " " .. category end
    return "search " .. label
end

local function naturalActionQuery(action)
    local label = type(A.DisplayActionLabel) == "function" and A.DisplayActionLabel(action) or tostring(action.label or "")
    return "search " .. label
end

local sampleSettingLimit = tonumber(os.getenv("MSUF_AURA_AUDIT_SETTING_SEARCH_LIMIT") or "") or 80
local sampleActionLimit = tonumber(os.getenv("MSUF_AURA_AUDIT_ACTION_SEARCH_LIMIT") or "") or 32

for _, setting in ipairs(sampleItems(auraSettings, sampleSettingLimit)) do
    checkSearch("sampledSettingKeySearch", tostring(setting.key), { setting.key }, "sampledKeySearches", 16)
    checkSearch("sampledSettingNaturalSearch", naturalSettingQuery(setting), { setting.key }, "sampledNaturalSearches", 20)
end

for _, action in ipairs(sampleItems(auraActions, sampleActionLimit)) do
    checkSearch("sampledActionKeySearch", tostring(action.key), { action.key }, "sampledKeySearches", 16)
    checkSearch("sampledActionNaturalSearch", naturalActionQuery(action), { action.key }, "sampledNaturalSearches", 20)
end

if #failures > 0 then
    io.stderr:write("assistant_aura_registry_coverage_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, 160) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_aura_registry_coverage_audit: ok settings=" .. tostring(counts.settings)
    .. " actions=" .. tostring(counts.actions)
    .. " indexed=" .. tostring(counts.indexed)
    .. " paged=" .. tostring(counts.paged)
    .. " fixedSearches=" .. tostring(counts.fixedSearches)
    .. " sampledKeySearches=" .. tostring(counts.sampledKeySearches)
    .. " sampledNaturalSearches=" .. tostring(counts.sampledNaturalSearches)
    .. "\n")
