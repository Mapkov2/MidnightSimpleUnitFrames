-- The Dashboard search card is a search field, the way the Assistant card took a question.
--
--   lua tools/tests/dashboard_search_field_smoke.lua <repo root>
--
-- Pins, through the real home page (MSUF_Menu2_Dashboard.lua):
--
--   1. The card holds an edit box with its own standalone search palette.
--   2. Typing schedules the menu search on that box; programmatic text does not.
--   3. Enter (and the Search button) opens the selected match, otherwise the
--      full results page; an empty field only takes focus; combat keeps the
--      button inert.
--   4. Escape and leaving the page empty the field and close its palette.
--   5. MSUF_Menu2_SearchPalette.lua: a standalone palette leaves the window's
--      navigation palette hook (M.HideNavSearchPalette) alone.
--   6. The card greets by the local time of day (morning, midday, afternoon,
--      evening, night) with the character name, refreshes with the page, falls
--      back to its plain title without a clock or a name, and every locale pack
--      translates the five greetings with exactly one %s.
local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local MENU = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Widget fakes
---------------------------------------------------------------------------
local FakeMT, methods = {}, {}
local fonts, buttons, editBoxes = {}, {}, {}
local function Fake(kind, text, parent)
    return setmetatable({ _kind = kind, _text = text, _parent = parent, _scripts = {}, _hooks = {}, _shown = true }, FakeMT)
end
function methods:CreateTexture() return Fake("texture", nil, self) end
function methods:CreateFontString() return Fake("fontstring", nil, self) end
function methods:SetText(text) self._text = text end
function methods:GetText() return self._text end
function methods:SetScript(name, callback) self._scripts[name] = callback end
function methods:HookScript(name, callback) self._hooks[name] = callback end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:SetShown(shown) self._shown = shown and true or false end
function methods:IsShown() return self._shown end
function methods:SetSize(width, height) self._width, self._height = width, height end
function methods:SetHeight(height) self._height = height end
function methods:GetHeight() return self._height or 12 end
function methods:GetStringHeight() return 12 end
function methods:GetStringWidth() return 60 end
function methods:GetFrameLevel() return 1 end
function methods:SetFocus() self._focused = true end
function methods:ClearFocus() self._focused = false end
FakeMT.__index = function(_, key)
    local method = methods[key]
    if method then return method end
    if type(key) ~= "string" or key:sub(1, 1) == "_" then return nil end
    if key:sub(1, 3) == "Get" then return function() return 0 end end
    return function() return nil end
end
FakeMT.__call = function() return nil end

local function Permissive(target)
    return setmetatable(target, { __index = function() return function() return Fake("any") end end })
end
local T = Permissive({
    colors = setmetatable({}, { __index = function(colors, name)
        local color = { 0.5, 0.5, 0.5, 1 }
        rawset(colors, name, color)
        return color
    end }),
    media = setmetatable({}, { __index = function() return "media" end }),
})
function T.Font(parent, _, text)
    local fs = Fake("fontstring", text, parent)
    fonts[#fonts + 1] = fs
    return fs
end
function T.SetTranslatedText(fs, text) fs._text = text end
function T.Button(parent, text)
    local button = Fake("button", text, parent)
    buttons[#buttons + 1] = button
    return button
end
function T.Panel(parent) return Fake("panel", nil, parent) end
function T.SkinEditBox(editBox) editBox._msuf2PaintEditBox = function(self, focused) self._painted = focused end end
local W = Permissive({})
function W.Text(parent, text) return T.Font(parent, nil, text) end

---------------------------------------------------------------------------
-- Search bridge and palette recorders
---------------------------------------------------------------------------
local calls = {}
local function Record(...) calls[#calls + 1] = table.concat({ ... }, "|") end
local function Has(entry)
    for i = 1, #calls do if calls[i] == entry then return true end end
    return false
end
local scheduledBox
local palette = { shown = false, openResult = false }
function palette:Refresh(query, pending) Record("refresh", query, tostring(pending)); self.shown = query ~= "" end
function palette:OpenSelected(query) Record("open", query); return self.openResult end
function palette:Hide() Record("hide"); self.shown = false end
function palette:IsShown() return self.shown end
function palette:MoveSelection(delta) Record("move", tostring(delta)) end
local paletteArgs

local registered, combat = {}, false
local M = {
    Theme = T,
    Widgets = W,
    pages = {},
    Tr = function(text) return text end,
    Format = function(text, ...) return string.format(text, ...) end,
    NormalizeControlPath = function(path) return tostring(path) end,
    RegisterSearchWidget = function(_, payload) registered[payload.controlId] = payload end,
    TrackRefresh = function() end,
    SetMenuStateValue = function() end,
    GetGeneralDB = function() return {} end,
    RefreshDashboardEditModeButton = function() end,
    SelectPage = function() return true end,
    IsConfigCombatLocked = function() return combat end,
    BuildUpgradeHighlightDashboardScene = function() return false end,
    BuildFirstLoadDashboardScene = function() return false end,
    TrimText = function(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end,
    SearchBridge = {
        UpdateSearchPlaceholder = function() end,
        ScheduleSearchInputQuery = function(box, query, openPage)
            scheduledBox = box
            Record("schedule", query, tostring(openPage))
        end,
        RunSearchInputQuery = function(query, openPage) Record("run", query, tostring(openPage)) end,
        -- Opens the results page and shows the query in the navigation search.
        RunSearchQuery = function(query) Record("results", query) end,
        BumpSearchInputSerial = function() Record("bump") end,
    },
    CreateNavSearchPalette = function(parent, box, standalone)
        paletteArgs = { parent = parent, box = box, standalone = standalone }
        return palette
    end,
}
M.RegisterPage = function(key, spec) M.pages[key] = spec end
_G.CreateFrame = function(kind, _, parent, template)
    local frame = Fake(kind, nil, parent)
    frame._template = template
    if kind == "EditBox" then editBoxes[#editBoxes + 1] = frame end
    return frame
end
_G.MSUFSuite = nil
-- The core's Suite link (Kernel/MSUF_SuiteLink.lua), which the Suite card asks.
local dashboardNamespace = { MSUF2 = M }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua"))("MidnightSimpleUnitFrames", dashboardNamespace)
assert(loadfile(MENU .. "MSUF_Menu2_Dashboard.lua"))("MidnightSimpleUnitFrames_Options", dashboardNamespace)
local buildHome = Check(M.pages.home and M.pages.home.build, "the Dashboard must register the home page")

local lastCtx
local function Build(width)
    fonts, buttons, editBoxes, registered, calls = {}, {}, {}, {}, {}
    palette.shown, palette.openResult, paletteArgs, scheduledBox = false, false, nil, nil
    local ctx = { wrapper = Fake("wrapper"), width = width or 760, entry = {}, refreshers = {} }
    lastCtx = ctx
    function ctx:SetContentHeight(height) self.height = height end
    function ctx:AddRefresher(fn) self.refreshers[#self.refreshers + 1] = fn end
    buildHome(ctx)
end
local function FindFont(text)
    for i = 1, #fonts do if fonts[i]._text == text then return fonts[i] end end
end
local function FindButton(text)
    for i = 1, #buttons do if buttons[i]._text == text then return buttons[i] end end
end
local function Type(box, text)
    box._text = text
    box._scripts.OnTextChanged(box, true)
end

---------------------------------------------------------------------------
-- 1. The card holds the field
---------------------------------------------------------------------------
Build()
local title = Check(FindFont("Find settings and help"), "the search card must keep its title")
local hero = title._parent
Check(#editBoxes == 1, "the Dashboard must build exactly one search field")
local input = editBoxes[1]
Check(input._parent == hero, "the search field must sit in the search card")
Check(input._template == "InputBoxScriptTemplate", "the search field must keep the keyboard scripts without native art")
Check(input._msuf2SearchPlaceholder, "the search field must carry the shared search placeholder")
Check(input._painted == false, "the rounded field surface must be painted once it exists")
Check(paletteArgs and paletteArgs.parent == hero and paletteArgs.box == input,
    "the field must own a search palette anchored to it")
Check(paletteArgs.standalone == true, "the field's palette must not take over the navigation palette hook")
local search = Check(FindButton("Search"), "the card must keep its Search button next to the field")
Check(search._parent == hero, "the Search button must sit in the search card")
local meta = registered["menu2.home.dashboard.search.open"]
Check(meta and meta.classification == "navigation" and meta.navigationKey == "search",
    "the Search button must keep its registered navigation identity")

---------------------------------------------------------------------------
-- 2. Typing searches; programmatic text does not
---------------------------------------------------------------------------
Type(input, "raid auras")
Check(scheduledBox == input and Has("schedule|raid auras|false"), "typing must schedule the menu search on the field")
Check(Has("refresh|raid auras|false"), "typing must refresh the field's palette")
calls = {}
input._text = "set by code"
input._scripts.OnTextChanged(input, false)
Check(#calls == 0, "text set by code must not start a search")
calls = {}
input._scripts.OnArrowPressed(input, "DOWN")
input._scripts.OnArrowPressed(input, "UP")
input._scripts.OnArrowPressed(input, "LEFT")
Check(calls[1] == "move|1" and calls[2] == "move|-1" and #calls == 2, "Up and Down must move the palette selection only")

---------------------------------------------------------------------------
-- 3. Enter and the Search button
---------------------------------------------------------------------------
calls = {}
input._text = "  "
input._focused = false
input._scripts.OnEnterPressed(input)
Check(input._focused == true and #calls == 0, "Enter on an empty field must only focus it")

calls = {}
input._text = "party width"
palette.openResult = true
input._scripts.OnEnterPressed(input)
Check(Has("run|party width|false") and Has("open|party width"), "Enter must run the query and open the selected match")
Check(not Has("results|party width") and not Has("run|party width|true"),
    "an opened match must not also open the results page")

calls = {}
palette.openResult = false
input._focused = true
input._scripts.OnEnterPressed(input)
Check(Has("hide") and Has("results|party width") and input._focused == false,
    "without a selected match Enter must close the palette and hand the query to the results page")

calls = {}
search._scripts.OnClick(search)
Check(Has("results|party width"), "the Search button must submit like Enter")
calls = {}
combat = true
search._scripts.OnClick(search)
Check(#calls == 0, "the Search button must stay inert in combat")
combat = false

---------------------------------------------------------------------------
-- 4. Escape and leaving the page
---------------------------------------------------------------------------
calls = {}
palette.shown, input._focused = true, true
input._scripts.OnEscapePressed(input)
Check(input._text == "" and Has("hide") and input._focused == false, "Escape must empty the field and close its palette")

calls = {}
input._text, palette.shown = "castbar", true
hero._hooks.OnHide(hero)
Check(input._text == "" and Has("hide"), "leaving the Dashboard must empty the field and close its palette")
calls = {}
hero._hooks.OnHide(hero)
Check(#calls == 0, "leaving the Dashboard must not cancel a search the palette is not showing")

-- A narrow Dashboard still gets a usable field.
Build(300)
Check(#editBoxes == 1 and (editBoxes[1]._width or 0) >= 120, "a narrow Dashboard must keep a usable field")

---------------------------------------------------------------------------
-- 5. The real palette keeps the navigation hook
---------------------------------------------------------------------------
local P = { Theme = T, TrimText = M.TrimText, Tr = M.Tr }
assert(loadfile(arg[2] or (MENU .. "MSUF_Menu2_SearchPalette.lua")))("MidnightSimpleUnitFrames_Options", { MSUF2 = P })
local nav = Check(P.CreateNavSearchPalette({}, {}), "the navigation palette must build")
local navHide = Check(P.HideNavSearchPalette, "the navigation palette must publish its hide hook")
nav.visibleResults = { "stale" }
Check(P.CreateNavSearchPalette({}, {}, true), "a standalone palette must build")
Check(P.HideNavSearchPalette == navHide, "a standalone palette must leave the navigation hook alone")
navHide()
Check(#nav.visibleResults == 0, "the navigation hook must still close the navigation palette")

-- Exercise the real palette's lazy construction, captured owners and retained callbacks.
do
    local previous = {}
    local function Override(name, fn) previous[name] = methods[name] or false; methods[name] = fn end
    Override("SetPoint", function(self, ...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end)
    Override("SetWidth", function(self, width) self._width = width end)
    Override("IsMouseOver", function(self) return self._over == true end)
    Override("RegisterEvent", function(self, event) self._event = event end)
    Override("UnregisterEvent", function(self, event) if self._event == event then self._event = nil end end)
    Override("Show", function(self)
        local changed = not self._shown
        self._shown = true
        if changed and self._hooks.OnShow then self._hooks.OnShow(self) end
    end)
    Override("Hide", function(self)
        local changed = self._shown
        self._shown = false
        if changed and self._hooks.OnHide then self._hooks.OnHide(self) end
    end)
    Override("SetShown", function(self, shown) if shown then self:Show() else self:Hide() end end)
    local parent, box = Fake("owner"), Fake("editbox", "  raid  ")
    local controller = P.CreateNavSearchPalette(parent, box)
    Check(controller.frame == nil, "constructing a controller must not build its popup")
    local replacementBox = Fake("editbox", "replacement")
    controller.parent, controller.searchBox = Fake("changed owner"), replacementBox
    replacementBox._focused = true
    local locked, canceled, opened, runs, bumps = false, 0, {}, {}, 0
    P.IsConfigCombatLocked = function() return locked end
    P.ApplyMenuPopupFramePriority = function(frame) frame._priorityApplied = true end
    P.SearchBridge = { CancelSearchBackgroundIndex = function() canceled = canceled + 1 end }
    P.searchResultsQuery = "raid"
    P.searchResults = {
        { key = "group", label = "Raid width", kind = "slider", hint = "Group > Bars",
          anchorFallback = "width", anchor = "raid.width", route = "group", exactTarget = "width" },
        { key = "help", label = "Help", kind = "faq", noOpen = true },
    }
    Check(controller:Refresh("  raid  ", false), "two-character queries must open the real palette")
    local frame, rows, clickOff = controller.frame, controller.rows, controller.clickOff
    Check(frame._parent == parent and frame._points[1][2] == box,
        "lazy construction must retain the original parent and search box, not mutable controller fields")
    Check(frame._width == 432 and frame:GetHeight() == 162 and #rows == 6 and frame._priorityApplied,
        "palette width, result capacity, height and popup priority must stay exact")
    Check(clickOff._event == "GLOBAL_MOUSE_DOWN", "show must register outside-click handling")
    Check(rows[1]._msuf2PaletteLabel:GetText() == "Raid width"
        and rows[1]._msuf2PaletteKind:GetText() == "Slider"
        and rows[1]._msuf2PaletteBreadcrumb:GetText() == "Group > Bars",
        "result title, kind and breadcrumb must render through the real palette")
    Check(rows[1]:IsShown() and rows[2]:IsShown() and not rows[3]:IsShown(), "only available results may show")
    Check(controller:MoveSelection(-1) and controller.selectedIndex == 2, "Up must wrap to the last result")
    Check(controller:MoveSelection(1) and controller.selectedIndex == 1, "Down must wrap to the first result")
    rows[2]._scripts.OnEnter(rows[2])
    Check(controller.selectedIndex == 2 and rows[2]._msuf2PaletteHovered, "hover must select its own row")
    rows[2]._scripts.OnLeave(rows[2])
    Check(rows[2]._msuf2PaletteHovered == nil, "leave must clear hover state")
    Check(controller:OpenSelected("raid") and not controller:IsShown() and #opened == 0,
        "noOpen records must consume Enter without routing")
    Check(clickOff._event == nil and #controller.visibleResults == 0 and controller.selectedIndex == 1,
        "hide must clear results, selection and outside-click subscription")
    -- The bridge may be replaced after both controller and popup were created.
    P.SearchBridge = {
        CancelSearchBackgroundIndex = function() canceled = canceled + 1 end,
        OpenSearchTarget = function(...) opened[#opened + 1] = { ... } end,
        BumpSearchInputSerial = function() bumps = bumps + 1 end,
        RunSearchInputQuery = function(...) runs[#runs + 1] = { ... } end,
    }
    controller:Refresh("raid", false)
    rows[1]._scripts.OnClick(rows[1])
    local target = opened[1]
    Check(target and target[1] == "group" and target[2] == "raid" and target[3] == "width"
        and target[4] == "raid.width" and target[5] == "group" and target[6] == "width",
        "retained row callbacks must use the original input and the current bridge with exact routing fields")
    Check(replacementBox._focused == false, "OpenResult must still clear the current controller field's focus")
    controller:Refresh("raid", false)
    box._over = true
    clickOff._scripts.OnEvent(clickOff)
    Check(controller:IsShown(), "clicks over the original edit box must keep the popup alive")
    box._over, frame._over = false, true
    clickOff._scripts.OnEvent(clickOff)
    Check(controller:IsShown(), "clicks inside the popup must remain alive until mouse-up")
    frame._over = false
    clickOff._scripts.OnEvent(clickOff)
    Check(not controller:IsShown(), "outside clicks must close the popup")
    controller:Refresh("raid", false)
    controller.moreResults._scripts.OnClick(controller.moreResults)
    Check(bumps == 1 and #runs == 1 and runs[1][1] == "raid" and runs[1][2] == true,
        "More must use the original input and current bridge to open the full results page")
    P.searchResultsQuery = "other"
    controller:Refresh("raid", true)
    Check(#controller.visibleResults == 0 and controller.status:GetText() == "Searching settings..."
        and controller.status:IsShown() and not controller.moreResults:IsShown(), "pending queries must hide stale results")
    controller:Refresh("raid", false)
    Check(controller.status:GetText() == "No exact setting found." and controller.moreResults:IsShown(),
        "completed empty queries must show their empty status and More")
    locked = true
    Check(not controller:Refresh("raid", false) and not controller:IsShown(), "combat must refuse the palette")
    locked = false
    Check(not controller:Refresh("r", false), "short queries must hide the palette")
    P.frame = Fake("window")
    P.frame:Hide()
    Check(not controller:Refresh("raid", false), "a closed menu must refuse the palette")
    P.frame:Show()
    P.searchResultsQuery = "raid"
    local hideNav = P.HideNavSearchPalette
    local second = P.CreateNavSearchPalette(Fake("second owner"), Fake("editbox", "raid"), true)
    Check(second:Refresh("raid", false) and second.frame._parent == P.frame,
        "a standalone popup must prefer the current menu window when present")
    Check(P.HideNavSearchPalette == hideNav and second.frame ~= frame and second.rows[1] ~= rows[1],
        "controllers must keep separate frames and rows without replacing the navigation hook")
    controller:Refresh("raid", false)
    rows[2]._scripts.OnEnter(rows[2])
    Check(controller.selectedIndex == 2 and second.selectedIndex == 1, "retained callbacks must not cross controller owners")
    local fontCount, buttonCount = #fonts, #buttons
    for _ = 1, 20 do controller:Hide(); controller:Refresh("raid", false) end
    Check(controller.frame == frame and controller.rows == rows and #fonts == fontCount and #buttons == buttonCount,
        "warm reopen must reuse the existing popup, rows, fonts and footer")
    Check(canceled > 0, "hide must cancel background indexing through the late bridge")
    for name, fn in pairs(previous) do methods[name] = fn or nil end
end

---------------------------------------------------------------------------
-- 6. Time-of-day greeting
---------------------------------------------------------------------------
local clock = "07"
_G.date = function(pattern)
    Check(pattern == "%H", "the greeting must read only the local hour")
    return clock
end
M.PlayerDisplayName = function() return "Mapko" end
local expected = {
    [0] = "Up late, Mapko?", [4] = "Up late, Mapko?", [5] = "Good morning, Mapko", [11] = "Good morning, Mapko",
    [12] = "Good day, Mapko", [13] = "Good day, Mapko", [14] = "Good afternoon, Mapko", [17] = "Good afternoon, Mapko",
    [18] = "Good evening, Mapko", [21] = "Good evening, Mapko", [22] = "Up late, Mapko?", [23] = "Up late, Mapko?",
}
for hour, text in pairs(expected) do
    clock = string.format("%02d", hour)
    Build()
    Check(FindFont(text), ("hour %02d must greet with %q"):format(hour, text))
end
clock = "09"
Build()
local greetingTitle = Check(FindFont("Good morning, Mapko"), "the morning greeting must title the search card")
clock = "19"
for _, refresh in ipairs(lastCtx.refreshers) do refresh() end
Check(greetingTitle._text == "Good evening, Mapko", "a page refresh must move the greeting to the current time of day")
_G.date = nil
Build()
Check(FindFont("Find settings and help"), "without a clock the card must keep its plain title")
M.PlayerDisplayName = nil

local GREETINGS = { "Good morning, %s", "Good day, %s", "Good afternoon, %s", "Good evening, %s", "Up late, %s?" }
for _, locale in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    for _, key in ipairs(GREETINGS) do
        local escaped = key:gsub("[%%%.%-%+%*%?%[%]%^%$%(%)]", "%%%0")
        local value = text:match('L%["' .. escaped .. '"%]%s*=%s*"([^"\r\n]*)"')
        Check(value, locale .. " lacks the search greeting " .. key)
        local _, count = value:gsub("%%s", "")
        Check(count == 1 and not value:find("%%[^s]"), locale .. " " .. key .. " needs exactly one %s: " .. value)
        if locale ~= "enUS" and locale ~= "enGB" then
            Check(value ~= key, locale .. " leaves the search greeting " .. key .. " untranslated")
        end
    end
end

print("dashboard_search_field_smoke: ok")
