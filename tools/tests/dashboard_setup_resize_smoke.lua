-- Resize the real cached Dashboard, then exercise the first-run and installer routes.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true, locale = arg[3] })
local M, core = mw.M, mw.core
local width, installed, needsSetup, installerCalls = 1480, true, true, 0
M.GetContentMetrics = function() return width, 900 end
M.Theme.ReducedMotionEnabled = function() return true end
core.UpgradeHighlights.ShouldShow = function() return false end
core.SuiteLink.GetOverview = function()
    if installed then return { version = "0.1.12-alpha", total = 10, enabled = 2, needsSetup = needsSetup, pageKey = "opt_misc" } end
end
core.SuiteLink.CanOpenInstaller = function() return installed end
core.SuiteLink.OpenInstaller = function()
    installerCalls = installerCalls + 1
    return true
end

local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function SelectHome(invalidate)
    if invalidate then M.InvalidatePage("home") end
    -- The native window's OnSizeChanged updates the active wrapper first.
    M.ApplyScrollMetrics()
    assert(M.SelectPage("home"))
    Settle()
    return M.cache.home
end
local function Find(parent, predicate)
    for _, child in ipairs({ parent:GetChildren() }) do
        if predicate(child) then return child end
        local match = Find(child, predicate)
        if match then return match end
    end
end
local function Button(label)
    label = M.Tr(label)
    return Find(M.cache[M.activeKey].wrapper, function(child)
        if child:GetObjectType() ~= "Button" or not child:IsShown() then return false end
        if child.GetText and child:GetText() == label then return true end
        for _, region in ipairs({ child:GetRegions() }) do
            if region:GetObjectType() == "FontString" and region:GetText() == label then return true end
        end
        return false
    end)
end
local function HorizontalFraction(point)
    if point:find("LEFT") then return 0 end
    if point:find("RIGHT") then return 1 end
    return 0.5
end
local function Span(frame, parentWidth)
    local left, right
    local parent = frame:GetParent()
    for i = 1, frame:GetNumPoints() do
        local point, relative, anchor, x = frame:GetPoint(i)
        assert(relative == parent, "fixture expects direct-parent anchors")
        local position = HorizontalFraction(anchor) * parentWidth + x
        local side = HorizontalFraction(point)
        if side == 0 then left = position
        elseif side == 1 then right = position
        else left = position - frame:GetWidth() / 2 end
    end
    left = left or right - frame:GetWidth()
    return left, right or left + frame:GetWidth()
end
local function CheckButton(label, inset)
    local button = assert(Button(label), "missing " .. label)
    local card = button:GetParent()
    local cardLeft, cardRight = Span(card, width - 12)
    assert(cardLeft == 12 and cardRight == width - 32, label .. " card drifted")
    local cardWidth = cardRight - cardLeft
    local left, right = Span(button, cardWidth)
    assert(left >= 12 and right <= cardWidth - 12, label .. " clipped after resizing")
    if inset then assert(right == cardWidth - inset, label .. " lost right alignment") end
    return left, right, select(5, button:GetPoint()), card
end
local function CheckSearch()
    local searchX, _, _, hero = CheckButton("Search", 22)
    local field = assert(Find(hero, function(child) return child:GetObjectType() == "EditBox" end))
    local left, right = Span(field, width - 44)
    assert(left == 22 and right + 10 == searchX, "search input and submit must resize together")
end

local function CheckChangelog()
    local card = M.cache.home.wrapper._msuf2DashboardState.cards.dashboardChangelogOpen.frame
    local scroll = assert(Find(card, function(child) return child:GetObjectType() == "ScrollFrame" end))
    assert(scroll:GetScrollChild():GetWidth() == width - 104, "release notes retained a stale width")
end

local function CheckScaling()
    local card = M.cache.home.wrapper._msuf2DashboardState.cards.dashboardScalingOpen.frame
    local cardWidth = width - 44
    local count = 0
    for _, column in ipairs({ card:GetChildren() }) do
        local apply = Find(column, function(child)
            return child:GetObjectType() == "Button" and child.GetText and child:GetText() == M.Tr("Apply")
        end)
        if apply then
            local columnLeft, columnRight = Span(column, cardWidth)
            local _, applyRight = Span(apply, columnRight - columnLeft)
            assert(columnLeft + applyRight <= cardWidth - 12, "Scaling column clipped after wrapper presize")
            assert(columnRight <= cardWidth - 12, "Scaling slider would overrun the card")
            count = count + 1
        end
    end
    assert(count == 3, "fixture missed the three scaling columns")
end

core.FirstLoad6:Dismiss("test_dashboard")
M.SetMenuStateValue("dashboardScalingOpen", true)
M.SetMenuStateValue("dashboardChangelogOpen", true)
local wide = SelectHome(true)
width = 1040
assert(SelectHome() == wide, "same width class must retain its Dashboard")
CheckSearch()
CheckScaling()
CheckChangelog()
local _, quickRight, quickY = CheckButton("Start Quick Setup")
local suiteLeft, _, suiteY = CheckButton("MSUF Suite Setup")
assert(quickRight + 8 == suiteLeft and quickY == suiteY, "Suite Setup must sit next to Quick Setup")
CheckButton("Wago Profiles", 16)
CheckButton("Open Suite Modules", 16)
needsSetup = false
M.MarkMenuDataDirty("suite-completed")
SelectHome()
CheckButton("Redo Suite Setup")
Button("Redo Suite Setup"):Click()
assert(installerCalls == 1 and not mw.win:IsShown(), "Redo did not open the installer and hide the menu")
assert(M.Open("home"))
Settle()

for _, nextWidth in ipairs({ 830, 630, 540, 428, 1040 }) do
    width = nextWidth
    SelectHome()
    CheckSearch()
    CheckScaling()
    CheckChangelog()
    local _, quickEdge, actionY = CheckButton("Start Quick Setup")
    local setupLeft, _, setupY = CheckButton("Redo Suite Setup")
    local _, _, wagoY = CheckButton("Wago Profiles")
    assert(quickEdge + 8 == setupLeft and setupY == actionY, "setup buttons lost their row")
    assert((wagoY < actionY) == (nextWidth - 44 < 560), "Wago wrapped at the wrong width")
    CheckButton("Open Suite Modules")
end
assert(M.cache.home == wide, "returning to a width class did not reuse its Dashboard")

installed = false
SelectHome(true)
assert(not Button("MSUF Suite Setup") and not Button("Redo Suite Setup"), "Suite setup appeared without Suite")
core.FirstLoad6:Reset("fresh")
SelectHome(true)
local skip = assert(Button("Skip Guided Setup"), "first-run Skip button missing")
local prompt
M.ShowPrompt = function(_, spec) prompt = spec end
skip:Click()
assert(prompt and prompt.showAlert and core.FirstLoad6:GetState().status == "pending", "Skip must ask before writing")
assert(prompt.text == M.Tr("Skip Guided Setup? You can start it again from the Dashboard at any time."),
    "warning must explain how to restart")
prompt.onAccept()
assert(core.FirstLoad6:GetState().status == "dismissed", "confirmed Skip did not dismiss first run")
assert(M.activeKey == "home" and not Button("Skip Guided Setup"), "confirmed Skip kept the welcome page")
assert(not core.GuidedTour6:IsActive(), "Skip started the guided tour")
assert(not core.FirstLoad6:ShouldShowDashboard(), "welcome can still return after Skip")

for attempt = 1, 2 do
    if attempt == 2 then
        core.FirstLoad6:Reset("fresh")
        SelectHome(true)
    end
    assert(Button("Start Quick Setup"), "Quick Setup launcher missing"):Click()
    assert(M.activeKey == "guided_setup" and core.GuidedTour6:IsActive(), "Quick Setup could not restart")
    prompt = nil
    assert(Button("Skip Guided Setup"), "guided route Skip button missing"):Click()
    assert(prompt and core.GuidedTour6:IsActive(), "route Skip dismissed without confirmation")
    prompt.onAccept()
    assert(M.activeKey == "home" and core.GuidedTour6:GetState().status == "dismissed", "route Skip did not exit")
    assert(core.FirstLoad6:GetState().status == "dismissed", "route Skip did not close first-run onboarding")
    assert(Button("Start Quick Setup"), "Quick Setup missing after Skip")
end
core.GuidedTour6:Complete()
M.MarkMenuDataDirty("guided-complete")
SelectHome()
prompt = nil
assert(Button("Start Quick Setup"), "Quick Setup missing after completion"):Click()
assert(prompt and not core.GuidedTour6:IsActive(), "completed setup must confirm a restart")
prompt.onAccept()
assert(M.activeKey == "guided_setup" and core.GuidedTour6:IsActive(), "completed tour could not restart")
print("PASS Dashboard width, first-run Skip and Suite Setup (" .. flavor .. ")")
