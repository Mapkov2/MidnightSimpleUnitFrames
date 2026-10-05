-- profile_names_untranslated_smoke.lua <repoRoot> <flavor>
--
-- Profile and sync-group names are typed by the user, so the menu shows them
-- exactly as typed. A name that happens to be a locale key ("None", "Raid",
-- "Default") must not be translated: under deDE a profile named "None" would
-- read "Keine", the same as the unassigned row of the picker, and "Raid" would
-- read "Überfall".
--
-- Boots the real core and Options graph under deDE (menu_core_world.lua),
-- creates the profiles "None" and "Raid" and the sync group "Raid", builds
-- the Profiles page and checks:
--   1. the Active profile and new-character pickers: the selected label and
--      every row of the opened list show the raw names, while the unassigned
--      row is still translated;
--   2. the sync-group picker and the member switches show the raw names.
--
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("profile_names_untranslated_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home", locale = "deDE", beforeOptions = function(world)
    Check(world.core.FinalizeLocale() == "deDE", "the deDE pack was not selected")
end })
local M, env, core = mw.M, mw.env, mw.core
local F = core.ProfileFields
-- The harness cannot decode the embedded factory string; the booted profile
-- is what a new profile starts from.
local factory = F.CopySnapshot(env.MSUF_DB)
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
-- Preconditions: these names are keys the deDE pack translates.
Check(M.Tr("None") ~= "None" and M.Tr("Raid") ~= "Raid" and M.Tr("Default") ~= "Default",
    "precondition: deDE no longer translates None, Raid and Default")
Check(env.MSUF_CreateProfile("None") and env.MSUF_CreateProfile("Raid"), "profiles were not created")
Check(core.ProfileSync.Replace({ { name = "Raid", members = { Default = true, Raid = true },
    modules = { unitframes = true }, exclude = {} } }), "sync group was not created")
Check(mw:Select("profiles"), "Profiles page did not open")

local frames = mw.world.widgets.frames
local function DropdownTitled(label)
    for _, widget in ipairs(frames) do
        if widget._msuf2ControlKind == "dropdown" and widget._msuf2Title
            and widget._msuf2Title._msuf2SearchText == label then return widget end
    end
end
local function OpenRows(button)
    button:Click("LeftButton")
    local rows = {}
    for _, row in ipairs(frames) do
        if row._msuf2Owner == button and row:IsShown() and row._msuf2Text then
            rows[row._msuf2Value] = row._msuf2Text:GetText()
        end
    end
    return rows
end

-- 1. Profile pickers.
local active = Check(DropdownTitled("Active profile"), "Active profile picker missing")
for _, name in ipairs({ "None", "Raid", "Default" }) do
    active:SetValue(name)
    Check(active._msuf2Label:GetText() == name,
        "Active profile shows " .. tostring(active._msuf2Label:GetText()) .. " for the profile " .. name)
end
local rows = OpenRows(active)
for _, name in ipairs({ "None", "Raid", "Default" }) do
    Check(rows[name] == name, "Active profile list shows " .. tostring(rows[name]) .. " for the profile " .. name)
end
local newChar = Check(DropdownTitled("Default profile"), "new-character picker missing")
rows = OpenRows(newChar)
Check(rows[""] == M.Tr("None"), "the unassigned row is no longer translated: " .. tostring(rows[""]))
Check(rows["None"] == "None", "a profile named None reads " .. tostring(rows["None"]) .. " like the unassigned row")
newChar:SetValue("None")
Check(newChar._msuf2Label:GetText() == "None", "new-character picker shows " .. tostring(newChar._msuf2Label:GetText()))

-- 2. Sync group picker and member switches.
local group = Check(DropdownTitled("Sync group"), "sync-group picker missing")
Check(group._msuf2Label:GetText() == "Raid", "sync group shows " .. tostring(group._msuf2Label:GetText()))
rows = OpenRows(group)
Check(rows["Raid"] == "Raid", "sync-group list shows " .. tostring(rows["Raid"]))
local members = {}
for _, widget in ipairs(frames) do
    local meta = widget._msuf2SearchMeta
    if meta and type(meta.controlId) == "string" and meta.controlId:find("sync%.member%.") and widget._msuf2Label then
        members[widget._msuf2Label:GetText()] = true
    end
end
for _, name in ipairs({ "None", "Raid", "Default" }) do
    Check(members[name], "no member switch reads the profile name " .. name)
end

print("profile_names_untranslated_smoke " .. flavor .. ": OK")
