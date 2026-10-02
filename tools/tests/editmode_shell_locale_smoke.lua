-- Review F16: Edit Mode shell strings exist in all twelve locale packs and are
-- translated in the ten non-English ones, including the arena-together label
-- picked by a conditional expression (scanners miss it) and the external
-- popup's settings button, which used to concatenate untranslatable pieces.
-- Quality program A-C6 (C6.4, C6.5): the HUD settings tip and provider anchor
-- label, the Edit Mode history labels and the Classic route to Blizzard's Edit
-- Mode are format strings over translated pieces, never English concatenation.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local KEYS = {
    "Edit Arena 1-3 together", "Edit Arena 1-5 together", "Sync class", "Anchor class", "Text on bar",
    "No selection", "Opened settings", "Settings unavailable", "Preview animation unavailable",
    "Open %s settings",
    "Choose %s in the game menu", "%s settings", "%s Anchor", "%s %s: %s", "%s %s",
    "Unit frame", "General layout", "Group frame", "Move", "Nudge", "Set", "Change",
}
-- Pure format strings: every pack keeps the same placeholders.
local IDENTITY = { ["%s %s: %s"] = true, ["%s %s"] = true }
local ENGLISH = { enUS = true, enGB = true }
local PACKS = { "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function Value(source, key)
    local prefix = 'L["' .. key .. '"] = "'
    local start = source:find(prefix, 1, true)
    if not start then return nil end
    local first = start + #prefix
    local last = source:find('"', first, true)
    return last and source:sub(first, last - 1) or nil
end

for _, pack in ipairs(PACKS) do
    local source = Read("MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua")
    for _, key in ipairs(KEYS) do
        local value = Value(source, key)
        if Check(value ~= nil, pack .. ": missing " .. key) and not ENGLISH[pack] and not IDENTITY[key] then
            Check(value ~= key, pack .. ": " .. key .. " is not translated")
        end
        if value and key:find("%s", 1, true) then
            local _, want = key:gsub("%%s", "")
            local _, count = value:gsub("%%s", "")
            Check(count == want, pack .. ": " .. key .. " must keep exactly " .. want .. " %s")
        end
    end
end

local aura = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_AuraPopup.lua")
Check(aura:find('"Edit Arena 1-3 together"', 1, true) and aura:find('"Edit Arena 1-5 together"', 1, true),
    "AuraPopup no longer names both arena-together labels; update this smoke")
local external = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalPopup.lua")
Check(external:find('Tr("Open %s settings")', 1, true) ~= nil,
    "the external popup settings button does not translate its label")
Check(not external:find('"Open " ..', 1, true), "the external popup still concatenates its settings label")
-- The toolbar files in their MSUF_EditMode.xml order.
local hudFiles = {}
for _, name in ipairs({ "HUD_Kit", "HUD_Selection", "HUD_Dock", "HUD_Picker", "HUD" }) do
    hudFiles[#hudFiles + 1] = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_" .. name .. ".lua")
end
local hud = table.concat(hudFiles, "\n")
Check(hud:find('string.format(HelpText("%s settings"), selectedCfg.label or key)', 1, true)
    and not hud:find('.. " settings")', 1, true), "the HUD settings tip concatenates its label")
Check(hud:find('string.format(HelpText("%s Anchor"), providerLabel)', 1, true)
    and not hud:find('" Anchor")', 1, true), "the HUD cooldown button concatenates its provider anchor label")
local blizzard = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua")
Check(blizzard:find('translate("Choose %s in the game menu")', 1, true) ~= nil,
    "the Classic route to Blizzard's Edit Mode does not translate its hint")

if #failures > 0 then
    error("editmode_shell_locale_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_shell_locale_smoke: ok (" .. #KEYS .. " keys in 12 packs)")
