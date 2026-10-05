-- group_editmode_labels_locale_smoke.lua <repoRoot>
--
-- Group Edit Mode text (MSUF_UF_Group_EM2.lua) and the Priority pin list:
--   * the mover labels ("Group: Party", ...) and the Party/Raid/Mythic Raid popup
--     titles were in no language pack, so every client showed them in English;
--   * the mover label painted the English key itself, untranslated;
--   * the extra-block movers registered "Group: Party: Pet frames", an English key
--     concatenated with a translated piece, through the public Edit Mode API,
--     which shows labels as given;
--   * the Priority pin view answered "Unknown" for a pin without a name, which
--     shadowed the Priority page's translated "Unknown player";
--   * the Edit Mode HUD's Groups button painted its fallback label and its
--     tooltip ("Toggle Group Frames preview") as English literals.
-- Contract: every such key is translated in every non-English pack, painted
-- through Translate, composed from translated pieces with a translated format,
-- and the pin view leaves an unknown name to the page.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local EM2_PATH = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua"
local PRIORITY_PATH = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Priority.lua"
local em2 = Slice.Read(EM2_PATH)

-- The keys this file shows: the LABELS table, the popup titles, the extra blocks.
local keys, seen = {}, {}
local function Add(key) if not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
local labels = assert(em2:match("\nlocal LABELS = (%b{})"), "LABELS moved")
for key in labels:gmatch('=%s*"([^"]+)"') do Add(key) end
local popup = Slice.Function(em2, "local function BuildGFPopup", EM2_PATH)
local titleLine = assert(popup:match("local title = ([^\n]+)"), "popup title moved")
for key in titleLine:gmatch('"([^"]+)"') do if key:find(" ", 1, true) then Add(key) end end -- not the mode ids
local blocks = assert(em2:match("\nlocal ADDITIONAL_BLOCK_NAMES = (%b{})"), "ADDITIONAL_BLOCK_NAMES moved")
for key in blocks:gmatch('=%s*"([^"]+)"') do Add(key) end
Add("%s: %s")
Add("Group frame")
Add("Unknown player")
Add("Groups")
Add("Toggle Group Frames preview")
Check(#keys >= 15, "expected the Edit Mode label keys, found " .. #keys)

for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local world = World.New(root, "Mainline", { locale = locale }):Boot()
    world.core.FinalizeLocale()
    Check(world.core.LOCALE == locale, locale .. " was not selected")
    for _, key in ipairs(keys) do
        local value = rawget(world.core.L, key)
        Check(type(value) == "string" and value ~= "", locale .. " has no translation of '" .. key .. "'")
        if key ~= "%s: %s" then
            Check(value ~= key, locale .. " leaves '" .. key .. "' in English")
        end
    end
    Check(select(2, world.core.L["%s: %s"]:gsub("%%s", "")) == 2, locale .. " changed the placeholders of '%s: %s'")
end

-- Painted through Translate; composed from translated pieces.
Check(em2:find('fs:SetText(Translate(LABELS[kind]', 1, true), "the mover label paints the English key")
local movers = Slice.Function(em2, "local function RegisterAdditionalMovers", EM2_PATH)
Check(not movers:find('LABELS[kind] .. ', 1, true), "an extra-block label concatenates the English key")
Check(movers:find('string.format(Translate("%s: %s"), Translate(LABELS[kind])', 1, true)
    and movers:find('group = Translate(LABELS[kind])', 1, true),
    "extra-block labels are not composed from translated pieces with a translated format")

-- The file paints no English literal: every SetText goes through Translate.
for literal in em2:gmatch(':SetText%(%s*"([^"]*)"') do
    Check(false, "MSUF_UF_Group_EM2.lua paints the English literal '" .. literal .. "'")
end
Check(em2:find('GameTooltip:SetText(Translate("Toggle Group Frames preview")', 1, true),
    "the Groups button tooltip is not translated")

-- The Priority pin view leaves an unknown name to the page.
local priority = Slice.Read(PRIORITY_PATH)
local view = Slice.Function(priority, "local function FillPriorityPinView", PRIORITY_PATH)
Check(not view:find('"Unknown"', 1, true), "the Priority pin view answers an English \"Unknown\"")
local page = Slice.Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua")
Check(page:find('entry.name or Tr("Unknown player")', 1, true), "the Priority page lost its translated fallback")

print(string.format("group_editmode_labels_locale_smoke: ok (%d keys in 10 translated packs)", #keys))
