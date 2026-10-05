-- profile_names_untranslated_smoke.lua <repoRoot> <flavor>
--
-- Profile and sync-group names are typed by the user, so the menu shows them
-- exactly as typed. A name that happens to be a locale key ("None", "Raid",
-- "Default") must not be translated: under deDE a profile named "None" would
-- read "Keine", the same as the unassigned row of the picker, and "Raid" would
-- read "Überfall".
--
-- Boots the real core and Options graph under deDE (menu_core_world.lua),
-- creates the profiles "None", "Raid" and "Smoke Typed Name", the sync group
-- "Raid" and the variant "Raid", builds the Profiles page and checks:
--   1. the Active profile and new-character pickers: the selected label and
--      every row of the opened list show the raw names, while the unassigned
--      row is still translated;
--   2. the sync-group picker and the member switches show the raw names;
--   3. the active-profile heading and the variant picker show the raw names;
--   4. building the page (also while a variant is being edited) and opening
--      its pickers never hands a name to the translator, so the missing-key
--      diagnostics do not collect the names either;
--   5. search: the member rows carry the raw names, and no Profiles result
--      shows a translated name (a picker's search label is its control name,
--      not the name it currently shows).
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
Check(env.MSUF_CreateProfile("None") and env.MSUF_CreateProfile("Raid") and env.MSUF_CreateProfile("Smoke Typed Name"),
    "profiles were not created")
Check(core.ProfileSync.Replace({ { name = "Raid", members = { Default = true, Raid = true },
    modules = { unitframes = true }, exclude = {} } }), "sync group was not created")
-- Saving a variant re-applies the profile; the harness frames cannot, and the
-- page under test only reads the saved schema.
local applyProfile = core.ProfileRuntime.Apply
core.ProfileRuntime.Apply = function() end
Check(core.ProfileVariants.Replace(env.MSUF_DB, { version = 1, entries = { { name = "Raid", conditions = {}, patch = {} },
    { name = "Smoke Typed Name", conditions = {}, patch = {} } } }), "variants were not created")
core.ProfileRuntime.Apply = applyProfile

-- Every translator request that carries a name, also inside composed text.
-- "None", "Raid" and "Default" are locale keys the page also uses for its own
-- labels and setting names, so the unique name stands in for them here.
local UNIQUE = "Smoke Typed Name"
local lookups = {}
local translate = core.Translate
core.Translate = function(value, ...)
    if type(value) == "string" and value:find(UNIQUE, 1, true) then
        lookups[#lookups + 1] = value .. " <- " .. debug.traceback("", 2):sub(1, 400)
    end
    return translate(value, ...)
end
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
for _, name in ipairs({ "None", "Raid", "Default", "Smoke Typed Name" }) do
    Check(members[name], "no member switch reads the profile name " .. name)
end

-- 3. Active-profile heading (the profile "Default" is active) and variant picker.
local heading
for _, frame in ipairs(frames) do
    for _, region in ipairs(frame.regions or {}) do
        if region._msuf2FontRole == "section" and region.GetText then
            local text = region:GetText()
            Check(text ~= M.Tr("Default"), "the active-profile heading reads " .. tostring(text) .. " for the profile Default")
            if text == "Default" then heading = region end
        end
    end
end
Check(heading, "no heading reads the active profile name Default")
local variant = Check(DropdownTitled("Variant"), "variant picker missing")
Check(variant._msuf2Label:GetText() == "Raid", "variant picker shows " .. tostring(variant._msuf2Label:GetText()))
rows = OpenRows(variant)
Check(rows["Raid"] == "Raid", "variant list shows " .. tostring(rows["Raid"]))
for _, button in ipairs({ active, newChar, group }) do OpenRows(button) end

-- 4. The page while a variant is being edited, then no name reached the translator.
core.ProfileRuntime.Apply = function() end
Check(core.ProfileVariants.BeginRecording(UNIQUE), "variant editing did not start")
M.InvalidatePage("profiles")
Check(mw:Select("home") and mw:Select("profiles"), "Profiles page did not reopen while editing")
core.ProfileRuntime.Apply = applyProfile
Check(#lookups == 0, "a name was handed to the translator:\n" .. table.concat(lookups, "\n"))
for key in pairs(M.missingLocaleKeys or {}) do
    Check(not key:find(UNIQUE, 1, true), "the missing-key diagnostics list a name: " .. key)
end
core.Translate = translate

-- 5. Search rows and results.
local providerMembers = {}
for _, row in ipairs(M.ProfileSearch.Collect()) do
    if type(row.controlId) == "string" and row.controlId:find("sync.member.", 1, true) then providerMembers[row.label] = true end
end
for _, name in ipairs({ "None", "Raid", "Default", "Smoke Typed Name" }) do
    Check(providerMembers[name], "no member search row reads the profile name " .. name)
end
local api = Check(M.Search and M.Search._CoreAPI, "search API missing")
local translated = { [M.Tr("None")] = "None", [M.Tr("Raid")] = "Raid", [M.Tr("Default")] = "Default" }
for _, query in ipairs({ "Raid", "Default", M.Tr("Raid"), M.Tr("Default"), M.Tr("None") }) do
    api.MarkSearchIndexDirty()
    for _, rec in ipairs(api.SearchPages(query)) do
        if rec.key == "profiles" then
            Check(not translated[rec.label], "search for " .. query .. " shows the name " .. tostring(translated[rec.label])
                .. " translated as " .. tostring(rec.label))
        end
    end
end

print("profile_names_untranslated_smoke " .. flavor .. ": OK")
