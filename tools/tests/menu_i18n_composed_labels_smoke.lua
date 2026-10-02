-- menu_i18n_composed_labels_smoke.lua <repoRoot>
--
-- Review R7 P3 and R6 addendum 4: menu and Edit Mode labels that were
-- composed from English parts ("Debuff" .. " Filters", label .. " Whitelist",
-- "Module import failed: " .. reason, HelpText("Grid") .. " " .. value .. "px")
-- are keys in no language pack, so every client language showed them in
-- English, and the word order of the concatenation was fixed. Each site now
-- names one whole key or one format key with its arguments:
--   1. none of the composed forms is left at the reviewed sites;
--   2. every key those sites use exists in all twelve packs, every translated
--      pack has its own text for it, and a format key keeps the key's
--      placeholders in the same order (string.format would fail otherwise);
--   3. pages pass raw keys to widgets that translate (no second lookup) and
--      the aura model headers are no longer marked untranslatable.
--
-- Plain Lua 5.1 with the repo root as argument.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Fail(message) failures[#failures + 1] = message end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local PAGES = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local EDIT = "MidnightSimpleUnitFrames/Shell/EditMode/"
local MODEL = "MidnightSimpleUnitFrames/Auras3/MenuModel/"

---------------------------------------------------------------------------
-- 1. No composed label at the reviewed sites
---------------------------------------------------------------------------
local FORBIDDEN = {
    { PAGES .. "MSUF_Menu2_Auras.lua", '"Buff"%) %.%. " Filters"', "unit aura Filters title" },
    { PAGES .. "MSUF_Menu2_Auras.lua", 'laneTitle %.%. " Blacklist"', "unit aura Blacklist title" },
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", 'laneTitle %.%. " Filters"', "group aura Filters title" },
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", 'laneTitle %.%. " Blacklist"', "group aura Blacklist title" },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", 'containerLabel %.%. " Whitelist"', "custom Whitelist title" },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", 'containerLabel %.%. " Filters"', "custom Filters title" },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", 'containerLabel %.%. " Setup"', "custom Setup title" },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", '"Display: " %.%.', "custom DoT display line" },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", 'Tr%(containerLabel%)%)', "custom Layout title translated twice" },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", '"Module import failed: " %.%.', "module import failure" },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", '"Suite import failed: " %.%.', "Suite import failure" },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", '"Export failed: " %.%.', "export failure" },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", 'PrintProfileMessage%([^\n]-M%.Format%(', "profile message formatted before it is translated" },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", 'PrintProfileMessage%([^\n]-M%.Tr%(', "profile message translated twice" },
    { EDIT .. "MSUF_EditMode_Blizzard.lua", 'not editable %(" %.%.', "Blizzard layout failure print" },
    { EDIT .. "MSUF_EditMode_HUD.lua", 'HelpText%("EM_ANCHOR_SET"%) %.%.', "anchor status" },
    { EDIT .. "MSUF_EditMode_HUD.lua", 'HelpText%("BG"%) %.%.', "grid background readout" },
    { EDIT .. "MSUF_EditMode_HUD.lua", 'HelpText%("Grid"%) %.%.', "grid step readout" },
    { EDIT .. "MSUF_EditMode_HUD_Picker.lua", 'HelpText%("Selected"%) %.%.', "picker selection status" },
    { MENU .. "MSUF_Menu2_Window.lua", 'L_PROFILE %.%.', "status bar profile" },
    { MENU .. "MSUF_Menu2_GuidedTour.lua", 'text = Tr%("Follow Blizzard', "tour segment option translated twice" },
    { MENU .. "MSUF_Menu2_GuidedTour.lua", 'W%.Segment%(decisionCard, Tr%(', "tour segment label translated twice" },
    { MODEL .. "MSUF_Auras3_Menu_CustomSpells.lua", 'header = true, disabled = true, translate = false', "class header" },
    { MODEL .. "MSUF_Auras3_Menu_Presets.lua", 'text = category, header = true, disabled = true, translate = false', "preset category header" },
}
local sources = {}
for _, rule in ipairs(FORBIDDEN) do
    local path, pattern, label = rule[1], rule[2], rule[3]
    sources[path] = sources[path] or Read(path)
    if sources[path]:find(pattern) then Fail(label .. " is still composed or translated twice in " .. path) end
end

---------------------------------------------------------------------------
-- 2. Every key exists in all packs with matching placeholders
---------------------------------------------------------------------------
local KEYS = {
    "Buff Filters", "Debuff Filters", "Buff Blacklist", "Debuff Blacklist",
    "%s Whitelist", "%s Filters", "%s Setup", "%s Layout", "Custom %d",
    "Display: portrait position", "Display: normal DoT lane",
    "Export failed: %s", "Module import failed: %s", "Suite import failed: %s",
    "MSUF Edit Mode: Blizzard layout is not editable (%s)",
    "Anchor set: %s", "BG %d%%", "Grid %dpx", "Selected %s", "Profile: %s",
    "Support", "Utility", "Other", "Raid", "Healer",
    "Death Knight", "Demon Hunter", "Druid", "Evoker", "Hunter", "Mage", "Monk",
    "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior",
}
-- Keys this change added: a translated pack must give each its own text.
-- (Existing keys such as "Paladin" or "Raid" are the same word in some languages.)
local ADDED = {}
for i = 1, 23 do ADDED[KEYS[i]] = true end
ADDED["%s Layout"] = nil
-- Every key each changed site uses must be among KEYS.
local SITE_KEYS = {
    { PAGES .. "MSUF_Menu2_Auras.lua", { "Buff Filters", "Debuff Filters", "Buff Blacklist", "Debuff Blacklist" } },
    { PAGES .. "MSUF_Menu2_Auras_Group.lua", { "Buff Filters", "Debuff Filters", "Buff Blacklist", "Debuff Blacklist" } },
    { PAGES .. "MSUF_Menu2_Auras_CustomWorkspace.lua", { "%s Whitelist", "%s Filters", "%s Setup", "%s Layout", "Custom %d",
        "Display: portrait position", "Display: normal DoT lane" } },
    { PAGES .. "MSUF_Menu2_AdvancedProfiles.lua", { "Export failed: %s", "Module import failed: %s", "Suite import failed: %s" } },
    { EDIT .. "MSUF_EditMode_Blizzard.lua", { "MSUF Edit Mode: Blizzard layout is not editable (%s)" } },
    { EDIT .. "MSUF_EditMode_HUD.lua", { "Anchor set: %s", "BG %d%%", "Grid %dpx" } },
    { EDIT .. "MSUF_EditMode_HUD_Picker.lua", { "Selected %s" } },
    { MENU .. "MSUF_Menu2_Window.lua", { "Profile: %s" } },
}
for _, entry in ipairs(SITE_KEYS) do
    local text = sources[entry[1]] or Read(entry[1])
    for _, key in ipairs(entry[2]) do
        if not text:find('"' .. key .. '"', 1, true) then Fail(entry[1] .. " no longer uses the key " .. key) end
    end
end

local PACKS = { "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local ENGLISH = { enUS = true, enGB = true }
local function LoadPack(locale)
    _G.GetLocale = function() return locale end
    local namespace = {}
    _G.MSUF_NS, _G.MSUF, _G.MSUF_L = namespace, namespace, nil
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua"))("MidnightSimpleUnitFrames", namespace)
    if namespace.FinalizeLocale then namespace.FinalizeLocale() end
    return _G.MSUF_L or namespace.L or {}
end
local function Placeholders(text)
    local list = {}
    for spec in text:gmatch("%%([%%sd])") do
        if spec ~= "%" then list[#list + 1] = spec end
    end
    return table.concat(list, ",")
end
for _, locale in ipairs(PACKS) do
    local L = LoadPack(locale)
    for _, key in ipairs(KEYS) do
        local value = rawget(L, key)
        if type(value) ~= "string" or value == "" then
            Fail(locale .. " has no text for " .. key)
        else
            if not ENGLISH[locale] and value == key and ADDED[key] then
                Fail(locale .. " shows " .. key .. " in English")
            end
            if Placeholders(value) ~= Placeholders(key) then
                Fail(locale .. " changes the placeholders of " .. key .. ": " .. value)
            end
            local ok = (function()
                local args = {}
                for spec in Placeholders(key):gmatch("[sd]") do args[#args + 1] = spec == "d" and 1 or "x" end
                return (loadstring("return string.format(...)"))(value, unpack(args)) ~= nil
            end)()
            if not ok then Fail(locale .. " cannot format " .. key) end
        end
    end
end

if #failures > 0 then
    error("menu_i18n_composed_labels_smoke: " .. #failures .. " problem(s):\n  " .. table.concat(failures, "\n  "))
end
print(string.format("menu_i18n_composed_labels_smoke: ok (%d reviewed sites, %d keys in %d packs)",
    #FORBIDDEN, #KEYS, #PACKS))
