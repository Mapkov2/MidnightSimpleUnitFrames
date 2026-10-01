-- profile_page_guards_smoke.lua <repoRoot> <flavor>
--
-- Guards of the Profiles page editors (Pages/MSUF_Menu2_ProfileVariants.lua and
-- Pages/MSUF_Menu2_ProfileSync.lua), driven through the real page in a booted
-- client (tools/tests/client_world.lua):
--
--   1. A saved variant schema that fails validation is never treated as empty:
--      the page names the error, and Create variant refuses with it instead of
--      replacing the saved variants with a fresh schema holding only the new one.
--   2. The sync exclusion catalog (a walk over every leaf of the profile's base
--      snapshot) is not rebuilt by every page build: it is built on first use and
--      reused until the profile or the menu's data revision changes.
--   3. "Use hotkey variant" follows the saved conditions, not the page's unsaved
--      copy: a hotkey slot chosen but not saved does not activate the variant.
--
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local w = World.New(root, flavor):Boot()
local failure = w:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local e, n = w.env, w.core
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
e.InCombatLockdown = function() return false end
e.MSUF_EnsureDB(true)
e.MSUF_ActiveProfile = "Default"
e.MSUF_GlobalDB = { profiles = { Default = e.MSUF_DB, Other = { general = {}, player = { width = 222 } } }, char = {}, global = {} }
local V, S = n.ProfileVariants, n.ProfileSync
n.ProfileRuntime.Apply = function() V.ResolveCurrent() end

-- Widgets the page builds, by label; the latest build wins.
local W, T = M.Widgets, M.Theme
local inputs, buttons, bindings, texts, feedback = {}, {}, {}, {}, {}
local TextInput, Button, Dropdown, Text = W.TextInput, T.Button, W.Dropdown, W.Text
W.TextInput = function(parent, label, ...)
    local widget = TextInput(parent, label, ...); inputs[label] = widget; return widget
end
T.Button = function(parent, label, ...)
    local widget = Button(parent, label, ...); buttons[label] = widget; return widget
end
W.Dropdown = function(parent, label, ...)
    local widget = Dropdown(parent, label, ...); widget.testLabel = label; return widget
end
W.Text = function(parent, text, ...)
    texts[#texts + 1] = tostring(text)
    return Text(parent, text, ...)
end
for _, kind in ipairs({ "BindDropdownWidget", "BindBoolWidget" }) do
    local original = M[kind]
    M[kind] = function(ctx, widget, get, set, meta)
        if widget.testLabel then bindings[widget.testLabel] = { get = get, set = set, widget = widget } end
        return original(ctx, widget, get, set, meta)
    end
end
local ShowStatusFeedback = M.ShowStatusFeedback
M.ShowStatusFeedback = function(message, kind, ...)
    feedback[#feedback + 1] = { message = tostring(message), kind = kind }
    if ShowStatusFeedback then return ShowStatusFeedback(message, kind, ...) end
end
M.scrollChild = e.CreateFrame("Frame")
M.GetContentMetrics = function() return 900, 800 end

local function Build()
    for key in pairs(buttons) do buttons[key] = nil end
    for i = #texts, 1, -1 do texts[i] = nil end
    M.InvalidatePage("profiles")
    Check(M.BuildPageEntry("profiles", true), "the Profiles page did not build")
    w.widgets:RunTimers(20000)
end
local function Click(label)
    local button = Check(buttons[label], label .. " is missing")
    return Check(button:GetScript("OnClick"), label .. " has no click handler")(button)
end
local function Shown(fragment)
    for _, text in ipairs(texts) do if text:find(fragment, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
-- 1. An invalid saved variant schema is reported and never replaced.
---------------------------------------------------------------------------
local saved = { version = 2, entries = { { name = "Kept", patch = {}, conditions = {} } } }
e.MSUF_DB.profileVariants = saved
Check(V.Validate(saved) == nil, "harness: the version 2 schema must fail validation")
Build()
Check(Shown("cannot be read"), "the page does not say that the saved profile variants cannot be read")
local input = Check(inputs["New variant name"], "the New variant name field is missing")
input:SetText("Fresh")
local before = #feedback
Click("Create variant")
Check(e.MSUF_DB.profileVariants == saved and saved.version == 2 and #saved.entries == 1 and saved.entries[1].name == "Kept",
    "Create variant replaced an unreadable saved schema (the saved variants are gone)")
Check(#feedback > before and feedback[#feedback].kind == "danger", "Create variant gave no error feedback")

---------------------------------------------------------------------------
-- 2. The sync exclusion catalog is built on first use and then reused.
---------------------------------------------------------------------------
e.MSUF_DB.profileVariants = nil
Check(S.Replace({ { name = "Shared", members = { Default = true, Other = true }, modules = { unitframes = true } } }),
    "harness: the sync group was not saved")
local walks = 0
local BaseSnapshot = V.BaseSnapshot
V.BaseSnapshot = function(...)
    local info = debug.getinfo(2, "S")
    if info and info.source:gsub("\\", "/"):find("Pages/MSUF_Menu2_ProfileSync.lua", 1, true) then walks = walks + 1 end
    return BaseSnapshot(...)
end
local function SettingValues()
    local setting = Check(bindings.Setting, "the sync exclusion Setting dropdown is missing")
    local values = setting.widget.values
    return type(values) == "function" and values() or values
end
Build()
local first = walks
Check(first <= 1, "one Profiles page build walked the profile " .. first .. " times")
Check(#SettingValues() > 1, "the sync exclusion catalog offers no setting")
local used = walks
Check(used == 1, "the first use of the exclusion catalog walked the profile " .. used .. " times, expected once")
Build()
SettingValues()
Check(walks == used, "a Profiles page rebuild walked the profile again (" .. walks .. " walks)")
M.MarkMenuDataDirty("profile_page_guards_smoke")
SettingValues()
Check(walks == used + 1, "a recorded menu change did not refresh the exclusion catalog")
V.BaseSnapshot = BaseSnapshot

---------------------------------------------------------------------------
-- 3. "Use hotkey variant" needs a saved hotkey slot.
---------------------------------------------------------------------------
Check(V.Replace(e.MSUF_DB, { version = 1, entries = { { name = "Burst", patch = {} } } }), "harness: the variant was not saved")
Build()
local activation = Check(bindings.Activation, "the Activation dropdown is missing")
activation.set(1)
before = #feedback
Click("Use hotkey variant")
Check(V.GetManual() == nil, "an unsaved hotkey slot activated the variant")
Check(#feedback > before and feedback[#feedback].kind == "danger", "Use hotkey variant gave no feedback for an unsaved slot")
Click("Save conditions")
Check(V.Find(e.MSUF_DB, "Burst").conditions.manual == true, "harness: the hotkey slot was not saved")
Build()
Click("Use hotkey variant")
Check(V.GetManual() == "Burst", "a saved hotkey slot no longer activates the variant")

print("profile_page_guards_smoke: ok (" .. flavor .. ")")
