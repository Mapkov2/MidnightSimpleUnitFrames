-- profile_none_name_smoke.lua <repoRoot> <Mainline|Forever>
--
-- "None" is a valid profile name (create and copy accept it). The Profiles
-- page lists an unassigned row next to every real profile in its two pickers
-- that may stay empty: a specialization's (WoW Forever: a talent group's)
-- profile, and the starting profile for new characters. That row has its own
-- value, so a real profile named "None" can be picked in both and the
-- unassigned row still clears. Behind the page, MSUF_SetSpecProfile clears for
-- "None" only while no real profile owns the name, the contract
-- MSUF_SetDefaultProfileForNewCharacters already has. Older builds stored the
-- unassigned row as the name "None"; while no profile has that name,
-- initialization clears those values, so a "None" profile made later is not
-- picked up by them.
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
-- Two specialization slots: Blizzard's two talent groups on WoW Forever,
-- specializations from the global API everywhere else.
local SLOTS = flavor == "Forever" and { 1, 2 } or { 65, 66 }
if flavor == "Forever" then
    e.DUAL_SPEC_PRIMARY, e.DUAL_SPEC_SECONDARY = "Primary", "Secondary"
    e.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end }
else
    e.GetNumSpecializations = function() return 2 end
    e.GetSpecialization = function() return 1 end
    e.GetSpecializationInfo = function(index)
        if index == 1 then return 65, "Holy" elseif index == 2 then return 66, "Protection" end
    end
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
e.print = function() end
-- Saved data of older builds, which stored the unassigned row as the name
-- "None": with no profile of that name, initialization clears it for every
-- character and the new-character choice.
local charKey = e.MSUF_GetCharKey()
e.MSUF_GlobalDB = { profiles = {}, global = { defaultProfileForNewChars = "None" }, char = {
    [charKey] = { activeProfile = "Default", specProfileMap = { [SLOTS[1]] = "None" } },
    ["Alt-Realm"] = { activeProfile = "Default", specProfileMap = { [7] = "None", [8] = "Default" } },
} }
e.MSUF_InitProfiles()
Check(e.MSUF_GetSpecProfile(SLOTS[1]) == nil and e.MSUF_GlobalDB.char["Alt-Realm"].specProfileMap[7] == nil
    and e.MSUF_GlobalDB.char["Alt-Realm"].specProfileMap[8] == "Default"
    and e.MSUF_GetDefaultProfileForNewCharacters() == nil,
    "a stored \"None\" from an older build was not cleared at initialization")
Check(e.MSUF_CopyProfile("Default", "None") == true and e.MSUF_CopyProfile("Default", "Raid") == true,
    "harness: the profiles None and Raid were not created")

-- The page's pickers with the bindings behind them, by label.
local W = M.Widgets
local pickers = {}
local Dropdown = W.Dropdown
W.Dropdown = function(parent, label, ...)
    local widget = Dropdown(parent, label, ...); widget.testLabel = label; return widget
end
local BindDropdownWidget = M.BindDropdownWidget
M.BindDropdownWidget = function(ctx, widget, get, set, meta)
    if widget.testLabel then
        pickers[widget.testLabel] = pickers[widget.testLabel] or {}
        table.insert(pickers[widget.testLabel], { get = get, set = set, widget = widget })
    end
    return BindDropdownWidget(ctx, widget, get, set, meta)
end
-- The section badges and the refreshes that paint them.
local refreshes, badges = {}, {}
local TrackCollapsibleRefresh = M.TrackCollapsibleRefresh
M.TrackCollapsibleRefresh = function(ctx, section, refresh)
    refreshes[#refreshes + 1] = refresh
    return TrackCollapsibleRefresh(ctx, section, refresh)
end
local SetCollapsibleBadges = W.SetCollapsibleBadges
W.SetCollapsibleBadges = function(section, list)
    for _, badge in ipairs(list or {}) do badges[#badges + 1] = tostring(badge.text) end
    if SetCollapsibleBadges then return SetCollapsibleBadges(section, list) end
end
M.scrollChild = e.CreateFrame("Frame")
M.GetContentMetrics = function() return 1000, 800 end
M.InvalidatePage("profiles")
Check(M.BuildPageEntry("profiles", true), "the Profiles page did not build")
w.widgets:RunTimers(20000)

-- Each picker offers the unassigned row and the real "None" profile as two
-- different values.
local function Rows(picker)
    local values = picker.widget.values
    values = type(values) == "function" and values() or values
    local unassigned, named = {}, {}
    for _, row in ipairs(values) do
        if row.value == "None" then named[#named + 1] = row
        elseif row.text == "None" then unassigned[#unassigned + 1] = row end
    end
    Check(#unassigned == 1 and #named == 1, "a picker does not list the unassigned row and the None profile apart")
    return unassigned[1].value
end
local function Picker(label, index)
    local list = Check(pickers[label], "the " .. label .. " picker is missing")
    return Check(list[index], "the " .. label .. " picker " .. index .. " is missing")
end

-- Specialization pickers.
for index, slot in ipairs(SLOTS) do
    local picker = Picker("Profile", index)
    local unassigned = Rows(picker)
    picker.set("Raid")
    Check(e.MSUF_GetSpecProfile(slot) == "Raid", "slot " .. slot .. " did not take Raid")
    picker.set("None")
    Check(e.MSUF_GetSpecProfile(slot) == "None" and picker.get() == "None",
        "slot " .. slot .. " did not take the profile named None")
    picker.set(unassigned)
    Check(e.MSUF_GetSpecProfile(slot) == nil and picker.get() == unassigned,
        "the unassigned row did not clear slot " .. slot)
end
-- The section badge counts a slot bound to the None profile as assigned.
Picker("Profile", 1).set("None")
Picker("Profile", 2).set("Raid")
badges = {}
for i = 1, #refreshes do refreshes[i]() end
local counted = false
for i = 1, #badges do if badges[i] == "2 / 2 assigned" then counted = true end end
Check(counted, "the specialization badge did not count the None profile: " .. table.concat(badges, ", "))
Picker("Profile", 2).set(Rows(Picker("Profile", 2)))

-- The new-character picker.
local newChar = Picker("Default profile", 1)
local unassigned = Rows(newChar)
newChar.set("None")
Check(e.MSUF_GetDefaultProfileForNewCharacters() == "None" and newChar.get() == "None",
    "new characters did not take the profile named None")
newChar.set(unassigned)
Check(e.MSUF_GetDefaultProfileForNewCharacters() == nil and newChar.get() == unassigned,
    "the unassigned row did not clear the new-character profile")

-- Without a real "None" profile, "None" from any caller still clears.
e.MSUF_SetSpecProfile(SLOTS[1], "Raid")
Check(e.MSUF_DeleteProfile("None") == true, "harness: the None profile was not deleted")
e.MSUF_SetSpecProfile(SLOTS[1], "None")
Check(e.MSUF_GetSpecProfile(SLOTS[1]) == nil, "\"None\" without a real None profile no longer clears a slot")

-- Once a real "None" profile exists, a stored "None" is that profile.
Check(e.MSUF_CopyProfile("Default", "None") == true, "harness: the None profile was not created again")
e.MSUF_SetSpecProfile(SLOTS[1], "None")
Check(e.MSUF_SetDefaultProfileForNewCharacters("None") == true, "harness: new characters did not take None")
e.MSUF_InitProfiles()
Check(e.MSUF_GetSpecProfile(SLOTS[1]) == "None" and e.MSUF_GetDefaultProfileForNewCharacters() == "None",
    "initialization cleared an assignment of the real None profile")

print("profile_none_name_smoke: ok (" .. flavor .. ")")
