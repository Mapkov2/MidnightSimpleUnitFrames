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

local function Build(width)
    fonts, buttons, editBoxes, registered, calls = {}, {}, {}, {}, {}
    palette.shown, palette.openResult, paletteArgs, scheduledBox = false, false, nil, nil
    local ctx = { wrapper = Fake("wrapper"), width = width or 760 }
    function ctx:SetContentHeight(height) self.height = height end
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
assert(loadfile(MENU .. "MSUF_Menu2_SearchPalette.lua"))("MidnightSimpleUnitFrames_Options", { MSUF2 = P })
local nav = Check(P.CreateNavSearchPalette({}, {}), "the navigation palette must build")
local navHide = Check(P.HideNavSearchPalette, "the navigation palette must publish its hide hook")
nav.visibleResults = { "stale" }
Check(P.CreateNavSearchPalette({}, {}, true), "a standalone palette must build")
Check(P.HideNavSearchPalette == navHide, "a standalone palette must leave the navigation hook alone")
navHide()
Check(#nav.visibleResults == 0, "the navigation hook must still close the navigation palette")

print("dashboard_search_field_smoke: ok")
