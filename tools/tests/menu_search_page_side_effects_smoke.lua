-- menu_search_page_side_effects_smoke.lua <repoRoot> <flavor>
--
-- Search runs on every (debounced) keystroke, so it must never change what the
-- player is looking at (review 2026-09-30, F2 and F7):
--   * the first keystroke and later profile-context changes (a new variant or
--     sync group) keep the Profiles page that is on screen built and shown;
--   * invalidating another page from search never hides the group preview of
--     the page on screen;
--   * the availability predicate receives the record, so a built page's
--     controls for a deleted variant leave the results instead of opening
--     nothing.
--
-- Boots the real core and Options graph of one client (client_world.lua) and
-- opens the real menu window. Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_search_page_side_effects_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor, { locale = "enUS" })
-- Widget surface the real page builders use and the shared stubs leave out.
local widgetMethods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "Normal", "Highlight", "Pushed", "Disabled", "Checked" }) do
    widgetMethods["Set" .. name .. "Texture"] = function(self, path)
        local texture = self["fixture" .. name] or self:CreateTexture()
        texture:SetTexture(path)
        self["fixture" .. name] = texture
    end
    widgetMethods["Get" .. name .. "Texture"] = function(self) return self["fixture" .. name] end
end
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets", "SetMaxLetters",
    "ClearFocus", "SetCursorPosition", "HighlightText" }) do
    widgetMethods[name] = function(self, ...) self["fixture" .. name] = { ... } end
end
widgetMethods.HasFocus = function() return false end
widgetMethods.SetAutoFocus = function(self, value) self.autoFocus = value end
widgetMethods.SetValueStep = function(self, value) self.valueStep = value end
widgetMethods.SetObeyStepOnDrag = function(self, value) self.obeyStep = value end
widgetMethods.SetScrollChild = function(self, child) self.scrollChild = child end
widgetMethods.GetScrollChild = function(self) return self.scrollChild end
widgetMethods.SetVerticalScroll = function(self, value) self.verticalScroll = value end
widgetMethods.GetVerticalScroll = function(self) return self.verticalScroll or 0 end
widgetMethods.GetVerticalScrollRange = function() return 0 end
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, n = world.env, world.core
local M = Check(n.MSUF2, "Menu2 did not load")
local api = Check(M.Search and M.Search._CoreAPI, "search core API missing")
local routing = Check(M.Search._RoutingAPI, "search routing API missing")
local V = Check(n.ProfileVariants, "ProfileVariants did not load")
e.MSUF_EnsureDB(true)
e.MSUF_ActiveProfile = "Default"
e.MSUF_GlobalDB = { profiles = { Default = e.MSUF_DB }, char = {}, global = {} }
n.ProfileRuntime.Apply = function() V.ResolveCurrent() end
M.ApplyService.Flush = function() return true end

Check(M.Open("profiles") ~= false, "the menu did not open on Profiles")
world.widgets:RunTimers(20)
local entry = Check(M.cache and M.cache.profiles, "the Profiles page was not built")
local function ProfilesOnScreen()
    return M.activeKey == "profiles" and M.cache.profiles == entry and entry.wrapper and entry.wrapper:IsShown()
end
Check(ProfilesOnScreen(), "the Profiles page is not on screen after opening it")

---------------------------------------------------------------------------
-- 1. The first keystroke and a context change keep the page on screen
---------------------------------------------------------------------------
Check(#api.SearchPages("cast") > 0, "the first search found nothing")
Check(ProfilesOnScreen(), "the first search keystroke rebuilt (blanked) the Profiles page on screen")
Check(V.Replace(e.MSUF_DB, { version = 1, entries = { { name = "Gone", enabled = false, conditions = {}, patch = {} } } }),
    "the variant was refused")
api.SearchPages("castb")
Check(ProfilesOnScreen(), "a profile-context change during a search blanked the Profiles page on screen")

---------------------------------------------------------------------------
-- 2. A built page's controls for a deleted variant leave the results
---------------------------------------------------------------------------
local goneToken
for _, row in ipairs(M.ProfileSearch.Collect()) do
    if row.help == "Gone" and row.profileSearchToken then goneToken = row.profileSearchToken end
end
Check(goneToken, "the variant has no search token")
-- Select the variant on the real page through search navigation, which owns
-- the rebuild; afterwards the page's live controls carry the variant's token.
local editor
for _, row in ipairs(api.SearchPages("Save conditions")) do
    if row.exactTarget and row.exactTarget.prepareKind == "profileEditor" and row.exactTarget.prepareValue == goneToken then
        editor = row
    end
end
Check(editor, "the variant's editor is not searchable")
Check(routing.OpenSearchTarget(editor.key, "Save conditions", "", nil, editor.route, editor.exactTarget),
    "navigating to the variant's editor failed")
entry = Check(M.cache.profiles, "the Profiles page vanished after navigation")
local function LiveTokenRows()
    local count = 0
    for _, rec in ipairs(api.GetSearchRecords()) do
        local target = rec.exactTarget
        if rec.anchor and target and target.prepareKind == "profileEditor" and target.prepareValue == goneToken then
            count = count + 1
        end
    end
    return count
end
Check(LiveTokenRows() > 0, "the built page registered no control for the selected variant")
-- Deleted outside the page (another profile tool, an import): the page on
-- screen stays built, so only the availability predicate can drop its rows.
Check(V.Replace(e.MSUF_DB, { version = 1, entries = {} }), "the variant could not be deleted")
api.SearchPages("Save conditions")
Check(ProfilesOnScreen(), "deleting the variant during a search blanked the Profiles page")
Check(LiveTokenRows() == 0, "the deleted variant's built controls stayed searchable")
for _, rec in ipairs(api.SearchPages("Save conditions")) do
    local target = rec.exactTarget
    Check(not (target and target.prepareKind == "profileEditor" and target.prepareValue == goneToken),
        "a result still opens the deleted variant's editor")
end

---------------------------------------------------------------------------
-- 3. Invalidating another page keeps the visible page's group preview
---------------------------------------------------------------------------
Check(M.SelectPage("gf_layout") ~= false and M.activeKey == "gf_layout", "the group layout page did not open")
local hides = 0
local box = { _msufGFNativePreviewPageKey = "gf_layout" }
function box:Hide() hides = hides + 1 end
M._gfNativePreviews[#M._gfNativePreviews + 1] = box
Check(M.cache.profiles, "the Profiles page is no longer cached")
-- The cached Profiles page is off screen now, so a context change during a
-- search rebuilds it on its next visit; that must not touch the group preview.
Check(V.Replace(e.MSUF_DB, { version = 1, entries = { { name = "Next", enabled = false, conditions = {}, patch = {} } } }),
    "the second variant was refused")
api.SearchPages("castba")
Check(M.cache.profiles == nil, "the off-screen Profiles page was not marked for a rebuild")
Check(hides == 0, "invalidating the Profiles page hid the visible group page's preview")
M.InvalidatePage("gf_layout")
Check(hides == 1, "invalidating the group page kept its own preview")

print("menu_search_page_side_effects_smoke: " .. flavor .. " ok (Profiles stays on screen across keystrokes and"
    .. " context changes, deleted-variant controls filtered, visible group preview kept)")
