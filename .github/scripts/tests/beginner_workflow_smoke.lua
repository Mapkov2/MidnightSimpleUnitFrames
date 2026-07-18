-- Regression contract for the beginner-first Menu2 workflow. The search field
-- keeps the active page visible, shows an in-place result palette, and only
-- offers the Assistant as an explicit secondary path when settings do not fit.
local root = arg and arg[1] or "."

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Contains(source, value, message)
    assert(source:find(value, 1, true), message or ("missing contract: " .. value))
end

local nav = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_NavRail.lua")
local bridge = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_SearchBridge.lua")
local search = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua")
local searchAPI = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_API.lua")
local searchRender = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_Render.lua")
local searchPalette = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_SearchPalette.lua")
local menuXML = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2.xml")
local searchText = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_Text.lua")
local guided = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_GuidedTour.lua")
local firstLoad = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_FirstLoad.lua")
local dashboard = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Dashboard.lua")
local editMode = Read("MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_HUD.lua")

Contains(searchText, 'M.Tr("Ask MSUF anything...")', "smart search lost its unified prompt")
Contains(nav, "ScheduleSearchInputQuery(searchBox, query, false", "typing once again replaces the active page")
Contains(nav, "searchPalette:OpenSelected(query)", "Enter no longer opens the selected in-place result")
Contains(nav, "ShouldUseAssistantForQuery(query, results) and SubmitAssistantQuery(query)",
    "zero-result questions no longer fall back to the Assistant")
assert(not nav:find("_assistantEngaged", 1, true), "search behavior still depends on a hidden Assistant mode")
Contains(menuXML, 'MSUF_Menu2_SearchPalette.lua', "the in-place palette is not loaded")
Contains(searchPalette, '"Best matches"', "the search palette lost its result context")
Contains(searchPalette, '"More"', "the full results page is no longer available as a secondary path")
Contains(searchPalette, "bridge.OpenSearchTarget", "palette results no longer use exact search routing")
Contains(search, "rec.exactTarget = {", "indexed controls no longer retain their exact setting target")
Contains(searchRender, "rec.exactTarget", "the full result page no longer preserves exact control routing")
Contains(searchPalette, "MAX_VISIBLE_RESULTS = 6", "the palette no longer bounds rendered suggestions")
Contains(searchPalette, "if self.frame then return self.frame end", "the palette is no longer created lazily")
assert(not searchPalette:find('SetScript("OnUpdate"', 1, true), "the search palette added an idle OnUpdate hotpath")
Contains(searchPalette, "frame:IsMouseOver()", "focus loss can hide the palette before a result click")
Contains(searchPalette, 'row:RegisterForClicks("LeftButtonUp")', "palette rows do not explicitly accept mouse clicks")
Contains(searchPalette, "M.ApplyMenuPopupFramePriority(palette)", "palette hit testing no longer follows Menu2 popup priority")
Contains(searchPalette, 'clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")', "click-away handling is not event-driven")
Contains(searchPalette, 'clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")', "hidden palettes retain a global mouse listener")
assert(not nav:find("searchPalette:IsMouseOver()", 1, true),
    "edit-box focus loss can still close the palette before a result receives mouse-up")
Contains(nav, 'SetScript("OnArrowPressed"', "keyboard result selection is missing")
Contains(search, 'M.searchPaletteActive == true', "lazy hidden-page indexing stops when the palette is open")
Contains(search, 'rec.key == activeKey', "results on the current page are no longer ranked first")
Contains(search, 'normalized:find("can you", 1, true)', "English change requests do not promote to the Assistant")
Contains(search, 'normalized:find("kannst du", 1, true)', "German change requests do not promote to the Assistant")
Contains(search, 'M.SelectPage("home")', "promoted questions do not reveal the Assistant answer")
Contains(searchAPI, "Search.ShouldUseAssistantForQuery", "smart routing is not public")
Contains(bridge, "function Bridge.SubmitAssistantQuery", "navigation cannot submit a promoted query")
Contains(searchRender, '"Ask MSUF about this"', "result pages no longer offer the Assistant")

Contains(guided, "local QUICK_STAGE_CONTROL_LIMITS", "Quick Setup route is missing")
Contains(guided, 'value = "quick"', "users cannot choose Quick Setup")
Contains(firstLoad, 'mode = "quick"', "first load does not start with Quick Setup")
Contains(dashboard, 'mode = "quick"', "Dashboard does not start with Quick Setup")
Contains(dashboard, "MSUF.Assistant.BuildDashboardCard(hero, mainW, heroH)",
    "Dashboard does not open the Assistant directly")
assert(not dashboard:find('title = "Move frames"', 1, true), "redundant Dashboard task tiles returned")
Contains(editMode, "local advancedHUD", "Edit Mode has no beginner/advanced split")
Contains(editMode, 'MakeBtn(hudFrame, "EM_TOUR_DONE"', "Edit Mode exit is not outcome-labelled")
Contains(editMode, 'MakeBtn(hudFrame, "Discard"', "Edit Mode discard action is ambiguous")

-- Exercise the real routing predicate as a pure cold-path contract. This keeps
-- short setting keywords direct while natural requests hand off to Assistant.
local function Words(source, names, fallback)
    local values = {}
    for name in tostring(names or ""):gmatch("[A-Za-z0-9_]+") do
        values[#values + 1] = source[name] == nil and fallback or source[name]
    end
    return unpack(values)
end
local function Normalize(value)
    return tostring(value or ""):lower():gsub("[^%w]+", " "):gsub("%s+", " ")
        :gsub("^%s+", ""):gsub("%s+$", "")
end
local searchTextAPI = {
    ContentWidth = function() return 900 end,
    ContentHeight = function() return 700 end,
    TrimText = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end,
    ShortLabel = function(value) return tostring(value or "") end,
    SearchPlaceholderText = function() return "" end,
    SearchBoxHasText = function() return false end,
    RefreshSearchPlaceholder = function() end,
    UpdateSearchPlaceholder = function() end,
    NormalizeSearchText = Normalize,
    DisplaySearchText = tostring,
    SearchEffectiveLocale = function() return "enUS" end,
    SearchDisplayText = tostring,
    AddSearchText = function() end,
    AddRawSearchText = function() end,
    AddToggleQuestionSearchText = function() end,
    AddControlQuestionSearchText = function() end,
}
local searchM
searchM = {
    Search = { Text = searchTextAPI }, SearchData = {}, navItems = {}, Theme = {}, Widgets = {},
    Pick = function(source, names) return Words(source, names, nil) end,
    PickDefaults = function(source, names) return Words(source, names, {}) end,
    KeySetFromWords = function(value)
        local out = {}; for word in tostring(value or ""):gmatch("%S+") do out[word] = true end; return out
    end,
    SetMenuStateValue = function(key, value) searchM[key] = value end,
    InvalidatePage = function(key) searchM.invalidatedPage = key end,
    SelectPage = function(key) searchM.selectedPage = key end,
}
local submittedQuery, refreshReason
local searchNamespace = {
    MSUF2 = searchM,
    Assistant = {
        SubmitExplicitQuery = function(query, reason)
            submittedQuery = { query = query, reason = reason }
            return true, { status = "ok" }
        end,
        RequestRefreshUI = function(reason) refreshReason = reason end,
    },
}
_G.C_Timer = _G.C_Timer or { After = function(_, callback) callback() end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"))(
    "MidnightSimpleUnitFrames", searchNamespace)
local preferAssistant = assert(searchM.Search._CoreAPI.ShouldUseAssistantForQuery)
assert(preferAssistant("raid auras", { {} }) == false, "short setting keywords no longer stay direct")
assert(preferAssistant("can you change my player width", { {} }) == true,
    "English change request did not promote to Assistant")
assert(preferAssistant("kannst du meine frames verschieben", { {} }) == true,
    "German change request did not promote to Assistant")
assert(preferAssistant("where can I move raid frames?", { {} }) == true,
    "natural-language question did not promote to Assistant")
assert(preferAssistant("unmatchedsetting", {}) == true, "zero-result query did not fall back to Assistant")
assert(searchM.Search._CoreAPI.SubmitAssistantSearchQuery("can you change my player width") == true,
    "promoted search request was not submitted")
assert(submittedQuery and submittedQuery.query == "can you change my player width"
    and submittedQuery.reason == "assistant-search", "promoted query lost its text or source")
assert(searchM.invalidatedPage == "home" and searchM.selectedPage == "home",
    "Assistant answer was not revealed on the Dashboard")
assert(refreshReason == "assistant.search", "Assistant result did not request a UI refresh")

print("PASS beginner workflow: in-place search, Quick Setup, Assistant fallback, and simple Edit Mode")
