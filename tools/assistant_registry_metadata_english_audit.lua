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
local M = assert(MSUF.MSUF2, "Menu namespace missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")

local bannedTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "zurueck", "zur\195\188ck", "rueck", "rueckgaengig", "abbrechen",
    "anwenden", "ausfuehren", "ausf\195\188hren", "hilfe", "spieler", "ziel",
    "auren", "profil", "zauberleiste", "menue", "fuer", "loeschen", "l\195\182schen",
    "kopiere", "verschiebe", "groesse", "gr\195\182sse", "hoehe", "h\195\182he",
    "breite", "einstellungen", "assistent", "nicht", "keine",
}

local internalLabelTerms = {
    "auras3", "classpower", "opt_castbar", "opt_bars", "opt_colors", "opt_fonts",
    "opt_misc", "gf_", "uf_", "targettarget", "focustarget",
}

local function normalizeWords(text)
    text = tostring(text or ""):lower():gsub("[^%w_]+", " "):gsub("%s+", " ")
    return " " .. text .. " "
end

local failures = {}

local function addFailure(kind, key, field, detail, value)
    failures[#failures + 1] = table.concat({
        tostring(kind or "item"),
        tostring(key or "?"),
        tostring(field or "?"),
        tostring(detail or "failed"),
        tostring(value or ""),
    }, " | ")
end

local function checkEnglish(kind, key, field, value)
    value = tostring(value or "")
    if value == "" then return end
    local haystack = normalizeWords(value)
    for _, term in ipairs(bannedTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        if haystack:find(needle, 1, true) then
            addFailure(kind, key, field, "German visible term: " .. term, value)
        end
    end
end

local function checkDisplayLabel(kind, key, field, value)
    value = tostring(value or "")
    if value == "" then
        addFailure(kind, key, field, "empty visible label", value)
        return
    end
    checkEnglish(kind, key, field, value)
    local lower = value:lower()
    for _, term in ipairs(internalLabelTerms) do
        if lower:find(term, 1, true) then
            addFailure(kind, key, field, "internal label token: " .. term, value)
        end
    end
end

local settingCount, actionCount, pageCount = 0, 0, 0
local visibleFields = { "category", "description", "summary", "target", "tooltip", "valueLabel", "confirmText" }
local knownPageKeys = {
    "home", "profiles", "gameplay", "classpower", "modules", "search",
    "opt_castbar", "opt_bars", "opt_colors", "opt_fonts", "opt_misc",
    "gf_layout", "gf_bars", "gf_indicators", "gf_auras",
    "auras3", "auras3_buffs", "auras3_debuffs", "auras3_filters", "auras3_styling",
    "uf_player", "uf_target", "uf_focus", "uf_pet", "uf_boss", "uf_targettarget", "uf_focustarget",
}

for _, setting in ipairs(Registry:AllSettings() or {}) do
    settingCount = settingCount + 1
    local key = tostring(setting and setting.key or "")
    checkDisplayLabel("setting", key, "label", setting and setting.label)
    if type(A.DisplaySettingLabel) == "function" then
        checkDisplayLabel("setting", key, "displayLabel", A.DisplaySettingLabel(setting))
    end
    for _, field in ipairs(visibleFields) do
        checkEnglish("setting", key, field, setting and setting[field])
    end
end

for _, action in ipairs(Registry:AllActions() or {}) do
    actionCount = actionCount + 1
    local key = tostring(action and action.key or "")
    checkDisplayLabel("action", key, "label", action and action.label)
    if type(A.DisplayActionLabel) == "function" then
        checkDisplayLabel("action", key, "displayLabel", A.DisplayActionLabel(action))
    end
    for _, field in ipairs(visibleFields) do
        checkEnglish("action", key, field, action and action[field])
    end
end

local seenPages = {}
for _, item in ipairs(M.navItems or {}) do
    if item and item.key then
        pageCount = pageCount + 1
        seenPages[item.key] = true
        checkDisplayLabel("page", item.key, "navLabel", item.label)
        if type(A.DisplayPageLabel) == "function" then
            checkDisplayLabel("page", item.key, "displayLabel", A.DisplayPageLabel(item.key, "MSUF page"))
        end
    end
end

for _, pageKey in ipairs(knownPageKeys) do
    if not seenPages[pageKey] then
        pageCount = pageCount + 1
        if type(A.DisplayPageLabel) == "function" then
            checkDisplayLabel("page", pageKey, "displayLabel", A.DisplayPageLabel(pageKey, "MSUF page"))
        else
            addFailure("page", pageKey, "displayLabel", "A.DisplayPageLabel missing", "")
        end
    end
end

if #failures > 0 then
    io.stderr:write("assistant_registry_metadata_english_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, 120) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_registry_metadata_english_audit: ok settings=" .. tostring(settingCount)
    .. " actions=" .. tostring(actionCount)
    .. " pages=" .. tostring(pageCount)
    .. "\n")
