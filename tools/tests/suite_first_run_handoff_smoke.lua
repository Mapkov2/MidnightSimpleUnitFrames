-- MSUF Suite awareness in MSUF's own menu: first-run hand-off and Dashboard card.
--
--   lua tools/tests/suite_first_run_handoff_smoke.lua <repo root>
--
-- MSUF's first run (the one-time welcome and the Quick Setup it starts) and the
-- optional MSUF Suite installer are two separate flows. The Suite holds its
-- installer at login while MSUF.FirstLoad6:IsFirstRunPending() is true, and the
-- lifecycle hands off to MSUFSuite.Installer.MaybeShow() once that first run
-- resolves. This smoke pins:
--
--   1. The core lifecycle (State/MSUF_FirstLoad.lua): which states are pending,
--      every resolution route handing off exactly once per session and one
--      frame later, the import route and a resumed Quick Setup keeping the
--      Suite waiting, WoW Forever never waiting or handing off, and every
--      missing or malformed Suite surface staying inert.
--   2. The menu accessor M.IsFirstRunPending (MSUF_Menu2_FirstLoad.lua).
--   3. The Dashboard Suite card (MSUF_Menu2_Dashboard.lua), built through the
--      real home page: absent without a Suite overview, its buttons only when
--      the overview asks for them, and each button's effect.
--   4. The guided setup final page offering the Suite page only behind the
--      same overview helpers.
local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local CORE_FIRST_LOAD = root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"
local MENU = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Suite and timer stubs
---------------------------------------------------------------------------
local maybeShowCalls = 0
local timers = {}
local function InstallSuite(kind)
    if kind == "absent" then
        _G.MSUFSuite = nil
    elseif kind == "string" then
        _G.MSUFSuite = "not a table"
    elseif kind == "no-installer" then
        _G.MSUFSuite = {}
    elseif kind == "installer-string" then
        _G.MSUFSuite = { Installer = "not a table" }
    elseif kind == "no-maybe-show" then
        _G.MSUFSuite = { Installer = { MaybeShow = true } }
    else
        _G.MSUFSuite = { Installer = { MaybeShow = function() maybeShowCalls = maybeShowCalls + 1 end } }
    end
end
local function InstallTimer()
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
end
local function Flush()
    local queued = timers
    timers = {}
    for i = 1, #queued do queued[i]() end
end

---------------------------------------------------------------------------
-- 1. Core lifecycle
---------------------------------------------------------------------------
local SHOWS = { SupportsOnboardingScenes = true }
local RETIRED = { SupportsOnboardingScenes = false }

local function LoadLifecycle(client, savedVariables)
    _G.MSUF, _G.MSUF_NS = nil, nil
    _G.MSUF_DB, _G.MSUF_ActiveProfile = nil, nil
    _G.MSUF_GlobalDB = savedVariables
    local namespace = { Client = client }
    assert(loadfile(CORE_FIRST_LOAD))("MidnightSimpleUnitFrames", namespace)
    maybeShowCalls, timers = 0, {}
    return namespace.FirstLoad6, namespace
end

local function SavedState(status, step)
    return { global = { firstLoad6 = {
        schema = 1, revision = 1, installKind = "fresh", status = status, step = step,
        firstSeenVersion = "6.5", installReason = "no_saved_variables",
    } } }
end

InstallSuite("present")
InstallTimer()

local firstLoad = LoadLifecycle(SHOWS, nil)
Check(type(firstLoad.IsFirstRunPending) == "function", "FirstLoad6:IsFirstRunPending is the Suite's login accessor")
Check(firstLoad:IsFirstRunPending() == true, "a fresh install is a pending first run")
firstLoad:Start("guided_tour")
Flush()
Check(maybeShowCalls == 0, "starting Quick Setup must not open the Suite installer over it")
Check(firstLoad:IsFirstRunPending() == true, "a running Quick Setup keeps the first run pending")
firstLoad:Complete("guided_tour")
Check(maybeShowCalls == 0, "the hand-off runs one frame later, never inside the MSUF action")
Check(#timers == 1, "finishing Quick Setup must queue exactly one hand-off")
Flush()
Check(maybeShowCalls == 1, "finishing Quick Setup hands off to the Suite installer")
Check(firstLoad:IsFirstRunPending() == false, "a completed first run is no longer pending")
firstLoad:Dismiss("full_settings")
firstLoad:Complete("defaults")
firstLoad:DeferForSession("not_now")
Flush()
Check(maybeShowCalls == 1, "the hand-off fires once per session")

-- Every route the welcome scene offers resolves the first run.
local ROUTES = {
    { "Complete", "defaults" },
    { "Complete", "current_profile" },
    { "Complete", "personalize_fallback" },
    { "DeferForSession", "not_now" },
    { "DeferForSession", "changelog" },
    { "Dismiss", "full_settings" },
}
for i = 1, #ROUTES do
    local method, step = ROUTES[i][1], ROUTES[i][2]
    firstLoad = LoadLifecycle(SHOWS, nil)
    firstLoad[method](firstLoad, step)
    Flush()
    Check(maybeShowCalls == 1, method .. "(" .. step .. ") must hand off to the Suite installer once")
    Check(firstLoad:IsFirstRunPending() == false, method .. "(" .. step .. ") must resolve the first run")
end

-- An Assistant undo can restore the saved status to "pending" after "Not now";
-- the welcome stays hidden for that session, and so does the Suite's wait.
firstLoad = LoadLifecycle(SHOWS, nil)
firstLoad:DeferForSession("not_now")
firstLoad:GetState().status = "pending"
Check(firstLoad:ShouldShowDashboard() == false, "the session deferral must keep the welcome hidden")
Check(firstLoad:IsFirstRunPending() == false, "the session deferral must not hold the Suite either")

-- "Not now" hands off; a Quick Setup started later in that session does not
-- hand off a second time when it finishes.
firstLoad = LoadLifecycle(SHOWS, nil)
firstLoad:DeferForSession("not_now")
firstLoad:Start("guided_tour")
firstLoad:Complete("guided_tour")
Flush()
Check(maybeShowCalls == 1, "a later Quick Setup in the same session must not hand off again")

-- The import route keeps the Suite waiting until the import succeeds.
firstLoad = LoadLifecycle(SHOWS, nil)
firstLoad:Start("import")
Flush()
Check(maybeShowCalls == 0, "opening the profile import must not open the Suite installer over it")
Check(firstLoad:IsFirstRunPending() == true, "an open import route keeps the first run pending this session")
firstLoad:CompleteProfileImport("import")
Flush()
Check(maybeShowCalls == 1, "a successful import hands off to the Suite installer")
Check(firstLoad:IsFirstRunPending() == false, "a successful import resolves the first run")

-- A cancelled import leaves the welcome retired; the next login must not keep
-- the Suite waiting for a hand-off that can no longer come.
firstLoad = LoadLifecycle(SHOWS, SavedState("active", "import"))
Check(firstLoad:IsFirstRunPending() == false, "a cancelled import from an earlier session must not hold the Suite")

-- A Quick Setup resumed after a reload still owns the screen, and finishing it
-- in the new session still hands off.
firstLoad = LoadLifecycle(SHOWS, SavedState("active", "guided_tour"))
Check(firstLoad:IsFirstRunPending() == true, "a resumed Quick Setup keeps the Suite waiting at login")
firstLoad:Complete("guided_tour")
Flush()
Check(maybeShowCalls == 1, "finishing a resumed Quick Setup hands off")

-- Terminal and deferred states from an earlier session are not pending.
for _, status in ipairs({ "completed", "dismissed", "later" }) do
    firstLoad = LoadLifecycle(SHOWS, SavedState(status, "defaults"))
    Check(firstLoad:IsFirstRunPending() == false, status .. " must not hold the Suite installer")
    firstLoad:Complete("defaults")
    Flush()
    Check(maybeShowCalls == 0, status .. " must never hand off")
end

-- WoW Forever retires the onboarding scenes, so its Suite keeps its own login
-- path: nothing is pending and nothing is handed off.
firstLoad = LoadLifecycle(RETIRED, nil)
Check(firstLoad:IsFirstRunPending() == false, "WoW Forever must never hold the Suite installer")
firstLoad:Start("guided_tour")
Check(firstLoad:IsFirstRunPending() == false, "a Forever Quick Setup must not hold the Suite installer")
firstLoad:Complete("guided_tour")
Flush()
Check(maybeShowCalls == 0, "WoW Forever must never hand off")
-- `/msuf firstload` still previews the scene there, and the preview re-arms.
firstLoad:Reset("fresh")
Check(firstLoad:IsFirstRunPending() == true, "the /msuf firstload preview is a pending first run")
firstLoad:Complete("defaults")
Flush()
Check(maybeShowCalls == 1, "resolving the preview hands off")
firstLoad:Reset("upgrade")
firstLoad:Dismiss("full_settings")
Flush()
Check(maybeShowCalls == 2, "each /msuf firstload preview re-arms the hand-off")

-- Retail carries no client table; the gate fails open like the welcome scene.
firstLoad = LoadLifecycle(nil, nil)
Check(firstLoad:IsFirstRunPending() == true, "without a client table the first run stays pending")

-- Missing, older or malformed Suites are inert.
for _, kind in ipairs({ "absent", "string", "no-installer", "installer-string", "no-maybe-show" }) do
    InstallSuite(kind)
    firstLoad = LoadLifecycle(SHOWS, nil)
    firstLoad:Complete("defaults")
    Flush()
    Check(maybeShowCalls == 0, "a " .. kind .. " Suite must not be called")
end

-- Without C_Timer the hand-off still runs, directly.
InstallSuite("present")
_G.C_Timer = nil
firstLoad = LoadLifecycle(SHOWS, nil)
firstLoad:Complete("defaults")
Check(maybeShowCalls == 1, "without C_Timer the hand-off runs directly")
InstallTimer()

---------------------------------------------------------------------------
-- 2. Menu accessor
---------------------------------------------------------------------------
local function LoadMenuFirstLoad(lifecycle)
    local M = { Tr = function(text) return text end, Widgets = {} }
    local namespace = { MSUF2 = M, FirstLoad6 = lifecycle }
    assert(loadfile(MENU .. "MSUF_Menu2_FirstLoad.lua"))("MidnightSimpleUnitFrames_Options", namespace)
    return M
end
firstLoad = LoadLifecycle(SHOWS, nil)
local menu = LoadMenuFirstLoad(firstLoad)
Check(type(menu.IsFirstRunPending) == "function", "M.IsFirstRunPending must be exported")
Check(menu.IsFirstRunPending() == true, "M.IsFirstRunPending must mirror a pending first run")
firstLoad:Complete("defaults")
Check(menu.IsFirstRunPending() == false, "M.IsFirstRunPending must mirror a resolved first run")
Check(LoadMenuFirstLoad(nil).IsFirstRunPending() == false, "without a lifecycle nothing is pending")
Check(LoadMenuFirstLoad({}).IsFirstRunPending() == false, "an older lifecycle without the accessor is not pending")

---------------------------------------------------------------------------
-- 3. Dashboard Suite card through the real home page
---------------------------------------------------------------------------
local FakeMT, methods = {}, {}
local fonts, buttons = {}, {}
local function Fake(kind, text, parent)
    return setmetatable({ _kind = kind, _text = text, _parent = parent, _scripts = {}, _shown = true }, FakeMT)
end
function methods:CreateTexture() return Fake("texture", nil, self) end
function methods:CreateFontString()
    local fs = Fake("fontstring", nil, self)
    fonts[#fonts + 1] = fs
    return fs
end
function methods:SetText(text) self._text = text end
function methods:GetText() return self._text end
function methods:SetScript(name, callback) self._scripts[name] = callback end
function methods:HookScript(name, callback) self._scripts[name] = callback end
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
FakeMT.__index = function(_, key)
    local method = methods[key]
    if method then return method end
    -- Private fields read as absent; any other widget method is a no-op.
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
function T.Button(parent, text)
    local button = Fake("button", text, parent)
    buttons[#buttons + 1] = button
    return button
end
function T.Panel(parent) return Fake("panel", nil, parent) end
local W = Permissive({})
function W.Text(parent, text) return T.Font(parent, nil, text) end

local selected, registered, refreshers, feedback = {}, {}, {}, {}
local hidden, combat = 0, false
local M = {
    Theme = T,
    Widgets = W,
    pages = {},
    Tr = function(text) return text end,
    Format = function(text, ...) return string.format(text, ...) end,
    NormalizeControlPath = function(path) return tostring(path) end,
    RegisterSearchWidget = function(_, payload) registered[payload.controlId] = payload end,
    TrackRefresh = function(_, refresh) refreshers[#refreshers + 1] = refresh end,
    SetMenuStateValue = function() end,
    GetGeneralDB = function() return {} end,
    RefreshDashboardEditModeButton = function() end,
    SelectPage = function(key) selected[#selected + 1] = key; return true end,
    BlockCombatAction = function() return combat end,
    HideSlashMenuAndMinibar = function() hidden = hidden + 1 end,
    ShowStatusFeedback = function(text) feedback[#feedback + 1] = text end,
}
M.RegisterPage = function(key, spec) M.pages[key] = spec end
_G.CreateFrame = function(kind) return Fake(kind) end
assert(loadfile(MENU .. "MSUF_Menu2_Dashboard.lua"))("MidnightSimpleUnitFrames_Options", { MSUF2 = M })
local buildHome = Check(M.pages.home and M.pages.home.build, "the Dashboard must register the home page")

local openCalls, openResult = 0, true
local function Overview(fields)
    _G.MSUFSuite = {
        GetOverview = function() return fields end,
        Installer = { Open = function() openCalls = openCalls + 1; return openResult end },
    }
end
local function Build()
    fonts, buttons, registered, refreshers, selected, feedback = {}, {}, {}, {}, {}, {}
    hidden, openCalls = 0, 0
    local ctx = { wrapper = Fake("wrapper"), width = 760 }
    function ctx:SetContentHeight(height) self.height = height end
    buildHome(ctx)
    return ctx.height
end
local function FindFont(text)
    for i = 1, #fonts do if fonts[i]._text == text then return fonts[i] end end
end
local function FindButton(text)
    for i = 1, #buttons do if buttons[i]._text == text then return buttons[i] end end
end
local function Click(button) button._scripts.OnClick(button) end
local ABOUT = "Optional modules beyond unit frames: action bars, bags, chat, minimap and more."
local OPEN_ID, SETUP_ID = "menu2.home.dashboard.suite.open_modules", "menu2.home.dashboard.suite.setup"

-- No Suite, an older Suite and malformed answers build the unchanged Dashboard.
_G.MSUFSuite = nil
local plainHeight = Build()
Check(type(plainHeight) == "number" and plainHeight > 0, "the home page must report its content height")
local ABSENT = {
    { "absent", nil },
    { "string", "not a table" },
    { "older Suite", {} },
    { "GetOverview not a function", { GetOverview = 42 } },
    { "overview not a table", { GetOverview = function() return "ready" end } },
    { "overview nil", { GetOverview = function() return nil end } },
}
for i = 1, #ABSENT do
    _G.MSUFSuite = ABSENT[i][2]
    Check(Build() == plainHeight, ABSENT[i][1] .. ": the Dashboard layout must not change")
    Check(not FindFont("MSUF SUITE") and not FindFont(ABOUT), ABSENT[i][1] .. ": no Suite card without an overview")
    Check(not registered[OPEN_ID] and not registered[SETUP_ID], ABSENT[i][1] .. ": no Suite controls without an overview")
end

-- A Suite that still needs setup and has its module page registered.
M.pages.suite_modules = { title = "Suite Modules" }
Overview({ version = "1.4.0", total = 12, enabled = 5, pageKey = "suite_modules", needsSetup = true })
local suiteHeight = Build()
local kicker = Check(FindFont("MSUF SUITE"), "the Suite card must show its kicker")
local card = kicker._parent
Check(suiteHeight == plainHeight + 10 + card._height,
    "the Suite card must sit between the Assistant hero and the collapsed cards, pushing them down by its height")
Check(FindFont("MSUF Suite v1.4.0"), "the Suite card must show the Suite version")
local status = Check(FindFont("5 of 12 modules on"), "the Suite card must show how many modules are on")
Check(FindFont(ABOUT), "the Suite card must explain what the Suite is in one line")
local open = Check(FindButton("Open Suite Modules"), "a registered module page must be offered")
local setup = Check(FindButton("Set up Suite"), "a Suite that needs setup must offer it")
Check(registered[OPEN_ID] and registered[OPEN_ID].classification == "navigation"
    and registered[OPEN_ID].navigationKey == "suite_modules", "Open Suite Modules must register as navigation to the page")
Check(registered[SETUP_ID], "Set up Suite must register like the other Dashboard buttons")

Click(open)
Check(selected[1] == "suite_modules", "Open Suite Modules must select the Suite's module page")
Click(setup)
Check(openCalls == 1 and hidden == 1, "Set up Suite must open the installer and let the menu step aside")
openResult = false
Click(setup)
Check(openCalls == 2 and hidden == 1 and feedback[1] == "Suite setup unavailable",
    "a refused setup must keep the menu open and say so")
openResult = true
combat = true
Click(open)
Click(setup)
Check(#selected == 1 and openCalls == 2, "both buttons must stay inert in combat")
combat = false

-- The card follows the live overview on refresh.
Overview({ version = "1.4.0", total = 12, enabled = 7, pageKey = "suite_modules", needsSetup = false })
for i = 1, #refreshers do refreshers[i]() end
Check(status._text == "7 of 12 modules on", "a refresh must follow the live module count")
Check(setup._shown == false, "a refresh must hide Set up Suite once the Suite is set up")

-- Each button appears only when the overview asks for it.
Overview({ version = "1.4.0", total = 12, enabled = 5, pageKey = "suite_modules", needsSetup = false })
Build()
Check(FindButton("Open Suite Modules") and not FindButton("Set up Suite"), "no setup button once the Suite is set up")
Overview({ version = "1.4.0", total = 12, enabled = 5, pageKey = nil, needsSetup = true })
Build()
Check(FindButton("Set up Suite") and not FindButton("Open Suite Modules"), "no module button without a page key")
Overview({ version = "1.4.0", total = 12, enabled = 5, pageKey = "suite_missing", needsSetup = false })
Build()
Check(FindFont("MSUF SUITE") and not FindButton("Open Suite Modules"), "no module button for a page this menu lacks")
Overview({ total = 3, enabled = 3 })
Build()
Check(FindFont("MSUF Suite") and FindFont("3 of 3 modules on"), "a Suite without a version still gets a plain title")

-- Narrow menus move both buttons below the text and grow the card.
Overview({ version = "1.4.0", total = 12, enabled = 5, pageKey = "suite_modules", needsSetup = true })
fonts, buttons = {}, {}
local narrow = { wrapper = Fake("wrapper"), width = 330 }
function narrow:SetContentHeight(height) self.height = height end
buildHome(narrow)
Check(FindFont("MSUF SUITE")._parent._height > 100, "a narrow Suite card must grow to hold its stacked buttons")

---------------------------------------------------------------------------
-- 4. Guided setup final page
---------------------------------------------------------------------------
local function Read(path)
    local handle = assert(io.open(path, "rb"), "missing file " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end
local tour = Read(MENU .. "MSUF_Menu2_GuidedTour.lua")
local finalPage = Check(tour:match("\nlocal function BuildFinalReviewPage%(.-\nend\n"),
    "the guided setup final page must still exist")
Check(finalPage:find("M.GetSuiteOverview()", 1, true) and finalPage:find("M.GetSuiteModulesPageKey(suiteOverview)", 1, true),
    "the final page must offer the Suite only behind the Dashboard's overview helpers")
Check(finalPage:find("if suitePage then", 1, true) and finalPage:find("M.SelectPage(suitePage)", 1, true),
    "the final page's Suite button must exist only with a registered page and select it")
Check(finalPage:find('"open_suite_modules"', 1, true), "the final page's Suite button must register for search")

print("suite_first_run_handoff_smoke: ok")
