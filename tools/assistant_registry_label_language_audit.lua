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

local banned = {
    "zeige", "anzeigen", "oeffne", "waehle", "zurueck", "rueckgaengig",
    "abbrechen", "anwenden", "ausfuehren", "einstellung", "einstellungen",
    "assistent", "nicht", "keine", "bitte", "loeschen", "kopiere",
    "verschiebe", "groesse", "ausserhalb", "kampf",
}

local function normalize(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("%s+", " ")
    return " " .. text .. " "
end

local failures = {}
local checked = 0

local function checkText(source, text)
    text = tostring(text or "")
    if text == "" then return end
    checked = checked + 1
    local hay = normalize(text)
    for _, term in ipairs(banned) do
        if hay:find(" " .. term .. " ", 1, true) then
            failures[#failures + 1] = source .. ": " .. term .. " in " .. text
        end
    end
end

if type(A.DisplayEnumLabel) == "function" then
    local enumCases = {
        { "DE Gruppenlayout", "group_layout" },
        { "ES Diseno de grupo", "group_layout" },
        { "FR Cadres de groupe", "group_layout" },
    }
    for i = 1, #enumCases do
        local rawLabel, value = enumCases[i][1], enumCases[i][2]
        local enumLabel = A.DisplayEnumLabel(rawLabel, value)
        checkText("enum localized fallback", enumLabel)
        local lower = tostring(enumLabel or ""):lower()
        if tostring(enumLabel or ""):find("DE", 1, true)
            or lower:find("gruppen", 1, true)
            or lower:find("grupo", 1, true)
            or lower:find("diseno", 1, true)
            or lower:find("cadres", 1, true)
            or lower:find("groupe", 1, true)
        then
            failures[#failures + 1] = "enum localized fallback leaked localized label: " .. tostring(enumLabel or "")
        end
        if lower ~= "group layout" then
            failures[#failures + 1] = "enum localized fallback should use the enum key, got: " .. tostring(enumLabel or "")
        end
    end
    local englishEnumLabel = A.DisplayEnumLabel("Application Mode", "applicationMode")
    checkText("enum english label preserved", englishEnumLabel)
    if tostring(englishEnumLabel or "") ~= "Application Mode" then
        failures[#failures + 1] = "enum english label should be preserved, got: " .. tostring(englishEnumLabel or "")
    end
end

if type(A.DisplaySettingLabel) == "function" then
    local settingLabel = A.DisplaySettingLabel({ key = "player.showName", label = "DE Zauberleisten" })
    checkText("setting localized fallback", settingLabel)
    if tostring(settingLabel or ""):find("DE", 1, true) or tostring(settingLabel or ""):lower():find("zauber", 1, true) then
        failures[#failures + 1] = "setting localized fallback leaked localized label: " .. tostring(settingLabel or "")
    end
    if tostring(settingLabel or "") ~= "Player Show Name" then
        failures[#failures + 1] = "setting localized fallback should use the setting key, got: " .. tostring(settingLabel or "")
    end
    local englishSettingLabel = A.DisplaySettingLabel({ key = "general.applicationMode", label = "Application Mode" })
    checkText("setting english label preserved", englishSettingLabel)
    if tostring(englishSettingLabel or "") ~= "Application Mode" then
        failures[#failures + 1] = "setting english label should be preserved, got: " .. tostring(englishSettingLabel or "")
    end
end

if type(A.DisplayActionLabel) == "function" then
    local actionLabel = A.DisplayActionLabel({ key = "assistant_scope_help", label = "FR Cadres de groupe" })
    checkText("action localized fallback", actionLabel)
    local lower = tostring(actionLabel or ""):lower()
    if lower:find("cadres", 1, true) or lower:find("groupe", 1, true) then
        failures[#failures + 1] = "action localized fallback leaked localized label: " .. tostring(actionLabel or "")
    end
    if tostring(actionLabel or ""):lower() ~= "assistant scope help" then
        failures[#failures + 1] = "action localized fallback should use the action key, got: " .. tostring(actionLabel or "")
    end
    local englishActionLabel = A.DisplayActionLabel({ key = "assistant_apply_profile", label = "Apply Profile" })
    checkText("action english label preserved", englishActionLabel)
    if tostring(englishActionLabel or "") ~= "Apply Profile" then
        failures[#failures + 1] = "action english label should be preserved, got: " .. tostring(englishActionLabel or "")
    end
end

local settings = type(Registry.AllSettings) == "function" and Registry:AllSettings() or Registry.settings or {}
for i = 1, #settings do
    local setting = settings[i]
    local key = tostring(setting and setting.key or ("setting#" .. tostring(i)))
    if type(A.DisplaySettingLabel) == "function" then
        checkText("setting display label " .. key, A.DisplaySettingLabel(setting))
    end
    checkText("setting raw label " .. key, setting and setting.label)
    if setting and type(setting.displayValues) == "table" then
        for value, label in pairs(setting.displayValues) do
            checkText("setting displayValues " .. key .. "=" .. tostring(value), label)
        end
    end
    if setting and type(setting.values) == "table" then
        for j = 1, #setting.values do
            local value = setting.values[j]
            local label
            if A.Parser and type(A.Parser.ValueDisplay) == "function" then
                label = A.Parser.ValueDisplay(setting, value)
            elseif type(A.HumanizeDisplayKey) == "function" then
                label = A.HumanizeDisplayKey(value)
            else
                label = tostring(value)
            end
            checkText("setting value display " .. key .. "=" .. tostring(value), label)
            if type(A.DisplaySettingValueLabel) == "function" then
                checkText("setting value label " .. key .. "=" .. tostring(value), A.DisplaySettingValueLabel(setting, label))
            end
        end
    end
end

local actions = type(Registry.AllActions) == "function" and Registry:AllActions() or Registry.actions or {}
for i = 1, #actions do
    local action = actions[i]
    local key = tostring(action and action.key or ("action#" .. tostring(i)))
    if type(A.DisplayActionLabel) == "function" then
        checkText("action display label " .. key, A.DisplayActionLabel(action))
    end
    checkText("action raw label " .. key, action and action.label)
    checkText("action summary " .. key, action and action.summary)
    checkText("action description " .. key, action and action.description)
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write(failures[i], "\n") end
    error("assistant_registry_label_language_audit failed")
end

io.write("assistant_registry_label_language_audit: ok checked=" .. tostring(checked) .. " settings=" .. tostring(#settings) .. " actions=" .. tostring(#actions) .. "\n")
