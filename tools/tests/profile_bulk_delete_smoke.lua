-- profile_bulk_delete_smoke.lua <repoRoot> <Mainline|Forever>
--
-- The Profiles page deletes several profiles at once (Danger zone > "Delete
-- several profiles", Pages/MSUF_Menu2_ProfileCleanup.lua):
--   * MSUF_DeleteProfiles takes every name through MSUF_DeleteProfile's path:
--     a character bound to a deleted profile moves to Default, the spec slots
--     and the new-character choice naming it clear, Default is refused, and
--     one chat line reports the count instead of one line per profile;
--   * the list offers every profile, locks the active one and Default, names
--     what still uses each profile, "Select unused" picks only profiles nothing
--     uses, and the confirmed delete removes exactly the selection.
-- Builds the real page in a booted client (tools/tests/client_world.lua).
-- Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local w = World.New(root, flavor)
local e, n = w.env, w.core
e.InCombatLockdown = function() return false end
e.UnitAffectingCombat = function() return false end
local LoadFile = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        -- Keep real profile switches, variants and synchronization; frame
        -- renderers are outside this storage/confirmation lifecycle fixture.
        n.ProfileRuntime.Apply = function()
            n.ProfileVariants.ResolveCurrent()
            n.ProfileSync.Activate(); n.ProfileSync.RefreshEvents()
        end
    end
    return LoadFile(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local M = Check(n.MSUF2, "Menu2 did not load")
local methods = w.widgets.Methods
local function Store(key) return function(self, v) self[key] = v end end
local function Get(key) return function(self) return self[key] end end
for name, fn in pairs({ SetChecked = Store("checked"), GetChecked = Get("checked"), SetValueStep = Store("step"),
    SetAutoFocus = function() end, SetNumeric = function() end, SetMaxLetters = function() end, SetTextInsets = function() end,
    ClearFocus = function() end, HasFocus = function() return false end, SetCursorPosition = function() end, HighlightText = function() end,
    SetScrollChild = Store("scrollChild"), GetScrollChild = Get("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
    GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end }) do
    if methods[name] == nil then methods[name] = fn end
end
local chat = {}
e.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    chat[#chat + 1] = table.concat(parts, " ")
end
local function ChatCount(pattern)
    local count = 0
    for _, line in ipairs(chat) do if line:find(pattern, 1, true) then count = count + 1 end end
    return count
end

local charKey = e.MSUF_GetCharKey()
e.MSUF_GlobalDB = { profiles = {}, global = {}, char = {
    [charKey] = { activeProfile = "Default" },
    ["Alt-Realm"] = { activeProfile = "Raid", specProfileMap = { [7] = "Arena", [8] = "Older" } },
} }
e.MSUF_InitProfiles()
for _, name in ipairs({ "Raid", "Arena", "Old", "Older", "NewChars" }) do
    Check(e.MSUF_CopyProfile("Default", name) == true, "harness: profile " .. name .. " was not created")
end
e.MSUF_SetDefaultProfileForNewCharacters("Older")
local profiles = e.MSUF_GlobalDB.profiles

-- Core: one summary line, the same repairs as a single delete, Default refused.
chat = {}
Check(e.MSUF_DeleteProfiles({ "Older", "Default" }) == 1, "MSUF_DeleteProfiles did not delete exactly one profile")
Check(profiles.Older == nil and profiles.Default ~= nil, "the wrong profiles were deleted")
Check(e.MSUF_GlobalDB.char["Alt-Realm"].specProfileMap[8] == nil
    and e.MSUF_GlobalDB.char["Alt-Realm"].specProfileMap[7] == "Arena",
    "a spec slot naming the deleted profile was not cleared, or another slot changed")
Check(e.MSUF_GetDefaultProfileForNewCharacters() == nil, "the new-character choice still names a deleted profile")
Check(ChatCount("Profiles deleted: 1") == 1 and ChatCount("deleted.") == 0,
    "the bulk delete did not report one summary line")
Check(e.MSUF_DeleteProfiles(nil) == 0 and e.MSUF_DeleteProfiles({}) == 0, "an empty request deleted something")
e.MSUF_SetDefaultProfileForNewCharacters("NewChars")

-- The page, the popup and its controls.
M.scrollChild = e.CreateFrame("Frame")
M.GetContentMetrics = function() return 1000, 800 end
local T = M.Theme
local made, popup = {}, nil
local Button = T.Button
T.Button = function(parent, text, ...)
    local button = Button(parent, text, ...)
    made[#made + 1] = { parent = parent, text = text, button = button }
    return button
end
local CreateMenuPopupPanel = M.CreateMenuPopupPanel
M.CreateMenuPopupPanel = function(...)
    popup = CreateMenuPopupPanel(...)
    return popup
end
local prompts = {}
M.ShowPrompt = function(key, spec) prompts[key] = spec end
M.InvalidatePage("profiles")
Check(M.BuildPageEntry("profiles", true), "the Profiles page did not build")
w.widgets:RunTimers(20000)

local function Find(text, parent)
    for _, item in ipairs(made) do
        if item.text == text and (parent == nil or item.parent == parent) then return item.button end
    end
end
local function Click(button) return button._msuf2OnClickHandler(button, "LeftButton") end
local opener = Check(Find("Delete several profiles"), "the danger zone has no Delete several profiles button")
local refreshed = 0
local RequestRefresh = M.RequestRefresh
M.RequestRefresh = function(...)
    refreshed = refreshed + 1
    if RequestRefresh then return RequestRefresh(...) end
end
Click(opener)
Check(popup and popup:IsShown(), "the button did not open the profile list")
local function Rows()
    local out = {}
    for _, item in ipairs(made) do
        local row = item.button
        if item.parent == popup._content and row:IsShown() then out[row._msuf2ProfileName] = row end
    end
    return out
end
local function Usage(row) return row._msuf2Usage:GetText() end
local rows = Rows()
local listed = 0
for _ in pairs(rows) do listed = listed + 1 end
Check(listed == 5, "the list does not show the five stored profiles")
Check(rows.Default._msuf2Locked and Usage(rows.Default) == "Active", "the active Default profile is not locked")
Check(not rows.Raid._msuf2Locked and Usage(rows.Raid) == "Used by 1 character", "Raid does not name its character")
Check(Usage(rows.Arena) == "Spec profile" and Usage(rows.NewChars) == "New-character default"
    and Usage(rows.Old) == "Unused", "a profile's usage is wrong")

local deleteButton = popup._deleteBtn
Click(Check(Find("Select unused", popup), "the popup has no Select unused button"))
rows = Rows()
Check(rows.Old._msuf2Active and not rows.Raid._msuf2Active and not rows.Arena._msuf2Active
    and not rows.NewChars._msuf2Active and not rows.Default._msuf2Active, "Select unused picked a used profile")
Click(rows.Raid)
Click(rows.Default)
Check(rows.Raid._msuf2Active and not rows.Default._msuf2Active, "row clicks did not toggle, or a locked row did")
Check(deleteButton._msuf2Label:GetText() == "Delete selected (2)", "the delete button does not count the selection")

Click(deleteButton)
local prompt = Check(prompts.MSUF2_CONFIRM_DELETE_PROFILES, "deleting did not ask for confirmation")
Check(profiles.Old ~= nil and profiles.Raid ~= nil, "a profile was deleted before the confirmation")
Check(prompt.text:find("Arena", 1, true) == nil and prompt.text:find("Old", 1, true)
    and prompt.text:find("Raid", 1, true), "the confirmation does not name exactly the selection")
chat = {}
prompt.onAccept()
Check(profiles.Old == nil and profiles.Raid == nil and profiles.Arena ~= nil and profiles.NewChars ~= nil
    and profiles.Default ~= nil, "the confirmed delete did not remove exactly the selection")
Check(e.MSUF_GlobalDB.char["Alt-Realm"].activeProfile == "Default", "Raid's character did not move to Default")
Check(ChatCount("Profiles deleted: 2") == 1, "the page delete did not report one summary line")
Check(refreshed > 0, "the page was not refreshed after the delete")
rows = Rows()
listed = 0
for _ in pairs(rows) do listed = listed + 1 end
Check(listed == 3 and deleteButton._msuf2Label:GetText() == "Delete selected (0)",
    "the list did not refresh after the delete")
Click(rows.Arena)
Click(Check(Find("Clear selection", popup), "the popup has no Clear selection button"))
Check(not Rows().Arena._msuf2Active, "Clear selection kept a selected profile")

-- A spec/profile switch can happen while the confirmation is open. The bulk
-- action must preserve the now-active profile, even in the captured selection.
Click(Rows().Arena)
Click(deleteButton)
local pending = Check(prompts.MSUF2_CONFIRM_DELETE_PROFILES, "missing delayed confirmation")
Check(e.MSUF_SwitchProfile("Arena") == true, "could not switch to the selected profile")
local activeProfile = e.MSUF_GlobalDB.profiles.Arena
pending.onAccept()
Check(e.MSUF_ActiveProfile == "Arena" and e.MSUF_GlobalDB.profiles.Arena == activeProfile,
    "a delayed bulk confirmation deleted the profile that became active")
Check(Rows().Arena._msuf2Locked and not Rows().Arena._msuf2Active,
    "the refreshed cleanup list did not lock the newly active profile")
Check(e.MSUF_DeleteProfiles({ false, 17, {} }) == 0 and e.MSUF_GlobalDB.profiles.Arena == activeProfile,
    "an invalid bulk name resolved to the active profile")
-- The separate single-profile action still permits deleting the current one.
Check(e.MSUF_DeleteProfile("Arena") == true and e.MSUF_ActiveProfile == "Default",
    "bulk protection changed the dedicated current-profile delete")

-- A sync target is configured work even without a character/spec binding.
Check(e.MSUF_CopyProfile("Default", "Synced") == true, "could not create sync target")
Check(n.ProfileSync.Replace({ { name = "Cleanup", members = { Default = true, Synced = true },
    modules = { unitframes = true }, exclude = {} } }) == true, "could not configure sync group")
Click(opener)
Check(Usage(Rows().Synced) == "Sync group", "a configured sync target was labeled unused")
Click(Find("Select unused", popup))
Check(not Rows().Synced._msuf2Active, "Select unused selected a configured sync target")
print("profile_bulk_delete_smoke: ok (" .. flavor .. ")")
