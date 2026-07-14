_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")
local P = assert(A.Parser, "Assistant parser missing")
assert(type(P.ValueDisplay) == "function", "Parser ValueDisplay missing")

local bannedTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "zurueck", "zur\195\188ck", "rueck", "rueckgaengig", "abbrechen",
    "anwenden", "ausfuehren", "ausf\195\188hren", "hilfe", "spieler", "ziel",
    "auren", "profil", "zauberleiste", "menue", "fuer", "loeschen", "l\195\182schen",
    "kopiere", "verschiebe", "groesse", "gr\195\182sse", "hoehe", "h\195\182he",
    "breite", "einstellungen", "assistent", "nicht", "keine",
}

local function normalizeWords(text)
    text = tostring(text or ""):lower():gsub("[^%w_]+", " "):gsub("%s+", " ")
    return " " .. text .. " "
end

local failures = {}

local function addFailure(key, field, value)
    failures[#failures + 1] = tostring(key or "?") .. " | " .. tostring(field or "value") .. " | " .. tostring(value or "")
end

local function checkEnglish(key, field, value)
    value = tostring(value or "")
    if value == "" then return end
    local haystack = normalizeWords(value)
    for _, term in ipairs(bannedTerms) do
        if haystack:find(" " .. tostring(term):lower() .. " ", 1, true) then
            addFailure(key, field .. " German visible term " .. tostring(term), value)
        end
    end
end

local function addValue(values, seen, value)
    local key = type(value) .. ":" .. tostring(value)
    if type(value) == "table" then key = key .. ":" .. tostring(value.label or "") end
    if seen[key] then return end
    seen[key] = true
    values[#values + 1] = value
end

local function collectValues(setting)
    local values, seen = {}, {}
    if type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then addValue(values, seen, value) end
    end
    if setting.default ~= nil then addValue(values, seen, setting.default) end
    if type(setting.values) == "table" then
        for _, value in ipairs(setting.values) do addValue(values, seen, value) end
        for value in pairs(setting.values) do
            if type(value) ~= "number" then addValue(values, seen, value) end
        end
    end
    if type(setting.displayValues) == "table" then
        for value in pairs(setting.displayValues) do addValue(values, seen, value) end
    end
    return values
end

local settingCount, valueCount = 0, 0
for _, setting in ipairs(Registry:AllSettings() or {}) do
    settingCount = settingCount + 1
    local key = tostring(setting and setting.key or "")
    for _, value in ipairs(collectValues(setting)) do
        valueCount = valueCount + 1
        local ok, label = pcall(P.ValueDisplay, setting, value)
        if ok then
            checkEnglish(key, "valueDisplay", label)
            if type(A.DisplaySettingValueLabel) == "function" then
                local okDisplay, fullLabel = pcall(A.DisplaySettingValueLabel, setting, label, "Option")
                if okDisplay then checkEnglish(key, "settingValueLabel", fullLabel) end
            end
        else
            addFailure(key, "ValueDisplay error", label)
        end
    end
end

local menuLocale = Registry:GetSetting("general.menuLocale")
assert(type(menuLocale) == "table", "general.menuLocale setting missing")
local expectedLocaleLabels = {
    auto = "Automatic",
    enUS = "English (US)",
    enGB = "English (UK)",
    deDE = "German (deDE)",
    esES = "Spanish (EU)",
    esMX = "Spanish (MX)",
    frFR = "French",
    itIT = "Italian",
    ptBR = "Portuguese (BR)",
    ruRU = "Russian",
    koKR = "Korean",
    zhCN = "Chinese (Simplified)",
    zhTW = "Chinese (Traditional)",
}
for value, expected in pairs(expectedLocaleLabels) do
    local ok, label = pcall(P.ValueDisplay, menuLocale, value)
    if not ok then
        addFailure("general.menuLocale", "ValueDisplay error", label)
    elseif label ~= expected then
        addFailure("general.menuLocale", "locale label " .. tostring(value), "expected " .. expected .. ", got " .. tostring(label))
    end
end

if #failures > 0 then
    io.stderr:write("assistant_value_display_english_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, 120) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_value_display_english_audit: ok settings=" .. tostring(settingCount)
    .. " values=" .. tostring(valueCount)
    .. "\n")
