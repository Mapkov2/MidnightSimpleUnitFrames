-- Menu2 navigation rail: availability with a reason, hidden rows, foldable
-- group titles and a window title that is the rail breadcrumb.
--
-- The rail is built for real on a booted client world. Two Suite-shaped rows
-- are inserted the way the Suite does it (in place, by group id): one module
-- that is switched off (dimmed, "Off" badge, reason tooltip) and one whose
-- addon is not installed (hidden, its group title with it).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Boot(flavor, locale)
    local world = World.New(root, flavor, { locale = locale }):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file)
        .. ": " .. tostring(failure and failure.message))
    -- The rail search box and list are an EditBox and a ScrollFrame; the shared
    -- stubs only carry the frame surface.
    local methods = world.widgets.Methods
    local function Add(name, fn) if methods[name] == nil then methods[name] = fn end end
    local noop = function() end
    for _, name in ipairs({ "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetGradientAlpha",
        "SetRoundLayoutToNearestPixel", "SetFocus", "ClearFocus", "HighlightText",
        "SetThickness", "SetStartPoint", "SetEndPoint" }) do
        Add(name, noop)
    end
    Add("HasFocus", function() return false end)
    Add("SetScrollChild", function(self, child) self.scrollChild = child end)
    Add("GetScrollChild", function(self) return self.scrollChild end)
    Add("SetVerticalScroll", function(self, offset) self.verticalScroll = offset end)
    Add("GetVerticalScroll", function(self) return self.verticalScroll or 0 end)
    -- Native templates supply a font; the generic offline frame stubs do not.
    local createFontString = methods.CreateFontString
    methods.CreateFontString = function(self, ...)
        local label = createFontString(self, ...)
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        return label
    end
    local env = world.env
    local tip = { lines = {} }
    env.GameTooltip = {
        SetOwner = function() tip.title, tip.lines = nil, {} end,
        SetText = function(_, text) tip.title = text end,
        AddLine = function(_, text) tip.lines[#tip.lines + 1] = text end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
    }
    return world, env, assert(env.MSUF2, flavor .. ": Menu2 namespace missing"), tip
end

local function Last(frame, pointName)
    local found
    for _, point in ipairs(frame.points) do
        if point.point == pointName then found = point end
    end
    return found
end
local function Y(frame)
    local point = assert(Last(frame, "TOPLEFT"), "frame has no TOPLEFT point")
    return point.y
end
local function Hover(frame, tip)
    tip.title, tip.lines, tip.shown = nil, {}, false
    local enter = frame:GetScript("OnEnter")
    if enter then enter(frame) end
    local leave = frame:GetScript("OnLeave")
    if leave then leave(frame) end
    return tip.title, tip.lines[1]
end
local function InsertAfterTitle(items, groupId, row)
    for index, item in ipairs(items) do
        if item.title and item.id == groupId then
            table.insert(items, index + 1, row)
            return
        end
    end
    error("navigation group " .. groupId .. " missing")
end
local function TitleRow(M, id)
    local text = assert(M.navTitles[id], "no title for " .. id)
    return assert(text:GetParent(), "title " .. id .. " has no row")
end

local function RailFlavor(flavor)
    local world, env, M, tip = Boot(flavor)
    local suite = { dimOk = false, dimReason = "Disabled in Blizzard's AddOns list: MSUF_Suite_Nameplates", hide = true }
    InsertAfterTitle(M.navItems, "combat", { key = "smoke_dimmed", label = "Nameplates", group = "combat",
        availability = function() return suite.dimOk, suite.dimReason end })
    InsertAfterTitle(M.navItems, "interface", { key = "smoke_hidden", label = "Action Bars", group = "interface",
        availability = function() return false, "Install MSUF_Suite_ActionBars to use this module", suite.hide end })
    M.navPrimaryForKey.smoke_dimmed, M.navPrimaryForKey.smoke_hidden = "smoke_dimmed", "smoke_hidden"

    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(200, 600)
    M.BuildNavRail(parent)
    local buttons = M.navButtons

    -- Real root and child rows use the HD atlas with a readable label gap.
    for _, key in ipairs({ "home", "uf_player", "opt_fonts", "opt_colors", "classpower", "gameplay" }) do
        local button = assert(buttons[key])
        local icon, label = assert(button._msuf2NavIcon), button._msuf2Label
        assert(icon:GetTexture() == M.Theme.media.navIcons and not icon._msuf2GlyphParts,
            flavor .. ": " .. key .. " bypasses the shared HD artwork")
        assert(icon:GetWidth() == 20 and icon:GetHeight() == 20, "navigation icon size")
        assert(Last(label, "LEFT").x - Last(icon, "LEFT").x - icon:GetWidth() >= 8,
            flavor .. ": " .. key .. " text overlaps its icon")
        local _, size, flags = label:GetFont()
        assert(size == 14 and flags == "", flavor .. ": " .. key .. " navigation font: " .. tostring(size) .. "/" .. tostring(flags) .. "/" .. tostring(label._msuf2FontRole))
        assert(label.shadowColor[4] == 0 and label.shadowOffset[1] == 0 and label.shadowOffset[2] == 0,
            "navigation label has a blurred shadow")
        local count = #button.regions
        M.Theme.AttachNavIcon(button, key, button._msuf2NavIconIsChild, true)
        assert(#button.regions == count and button._msuf2NavIcon == icon, "refresh allocates another icon")
        M.Theme.SetNavIconVisible(button, false)
        assert(not icon:IsShown() and Last(label, "LEFT").x == 12, "hidden icons leave a blank column")
        M.Theme.SetNavIconVisible(button, true)
        assert(icon:IsShown() and Last(label, "LEFT").x == 38, "restored icons lost label spacing")
    end

    -- Dimmed: reason tooltip plus a non-color "Off" cue that the label stops short of.
    local dimmed = assert(buttons.smoke_dimmed, flavor .. ": dimmed row missing")
    assert(dimmed:IsShown() and dimmed:GetAlpha() == 0.4, flavor .. ": switched-off module is not dimmed")
    local badge = assert(dimmed._msuf2NavOffBadge, flavor .. ": dimmed row has no Off badge")
    assert(badge:IsShown() and badge:GetText() == M.Tr("Off"), flavor .. ": Off badge not shown")
    assert(Last(dimmed._msuf2Label, "RIGHT").x < -8, flavor .. ": label runs under the Off badge")
    M.RefreshNavIconVisibility()
    assert(Last(dimmed._msuf2Label, "RIGHT").x < -8, flavor .. ": icon relayout put the label under the Off badge")
    local tipTitle, tipBody = Hover(dimmed, tip)
    assert(tipTitle == "Nameplates" and tipBody == suite.dimReason,
        flavor .. ": dimmed row tooltip lost its reason: " .. tostring(tipTitle) .. " / " .. tostring(tipBody))
    suite.dimReason = nil
    M.RefreshNavAvailability()
    assert(select(2, Hover(dimmed, tip)) == "Unavailable", flavor .. ": reasonless off row has no tooltip body")
    suite.dimOk = true
    M.RefreshNavAvailability()
    assert(dimmed:GetAlpha() == 1 and not badge:IsShown(), flavor .. ": available module still dimmed")
    assert(Last(dimmed._msuf2Label, "RIGHT").x == -8, flavor .. ": label inset kept after the module came back")
    assert(Hover(dimmed, tip) == nil, flavor .. ": available row still explains itself")
    M.RefreshNavIconVisibility()
    assert(dimmed:GetAlpha() == 1, flavor .. ": icon refresh changed an available row")

    -- Changing Frame Basics (including undo/profile refresh) repaints the
    -- rail in the same refresh pass, without selecting another page.
    local refreshEntry = { refreshers = { function() suite.dimOk = false end } }
    M.RunEntryRefreshers(refreshEntry, { force = true })
    assert(dimmed:GetAlpha() == 0.4 and badge:IsShown(), flavor .. ": page refresh left the rail active")
    refreshEntry.refreshers[1] = function() suite.dimOk = true end
    M.RunEntryRefreshers(refreshEntry, { force = true })
    assert(dimmed:GetAlpha() == 1 and not badge:IsShown(), flavor .. ": page refresh left the rail grey")

    -- A clipped translated/custom-font label remains fully readable on hover.
    local oldTruncated = world.widgets.Methods.IsTruncated
    world.widgets.Methods.IsTruncated = function() return true end
    assert(Hover(buttons.home, tip) == "Dashboard", "clipped navigation label has no full title")
    world.widgets.Methods.IsTruncated = function() return false end
    assert(Hover(buttons.home, tip) == nil, "fitting label adds a redundant tooltip")
    world.widgets.Methods.IsTruncated = oldTruncated

    -- Hidden: out of the rail, its now-empty group title too, and the gap closes.
    local hidden = assert(buttons.smoke_hidden, flavor .. ": hidden row must stay in M.navButtons")
    local interfaceRow, styleRow = TitleRow(M, "interface"), TitleRow(M, "style")
    assert(not hidden:IsShown(), flavor .. ": row of a missing addon is shown")
    assert(not interfaceRow:IsShown(), flavor .. ": group title without visible pages is shown")
    local styleHiddenY = Y(styleRow)
    suite.hide = false
    assert(M.RefreshNavAvailability() == true, flavor .. ": unhiding a row did not relayout")
    assert(hidden:IsShown() and interfaceRow:IsShown(), flavor .. ": unhidden row or its title missing")
    assert(styleHiddenY - Y(styleRow) == 56, flavor .. ": hidden group left a gap of "
        .. tostring(56 - (styleHiddenY - Y(styleRow))))
    suite.hide = true
    M.RefreshNavAvailability()
    assert(Y(styleRow) == styleHiddenY and not interfaceRow:IsShown(), flavor .. ": re-hiding did not close the gap")

    -- Navigation into and titles for a hidden page still work.
    M.frame = { title = parent:CreateFontString() }
    M.UpdateNav("home")
    M.UpdateNav("smoke_hidden")
    M.SetTitle("smoke_hidden")
    local hiddenTitle = world.client.isForever and M.Tr("MSUF (Forever Version)") or "Interface > Action Bars"
    assert(M.frame.title:GetText() == hiddenTitle, flavor .. ": hidden page title: " .. tostring(M.frame.title:GetText()))
    assert(not hidden:IsShown(), flavor .. ": navigating to a hidden page showed its row")
    M.UpdateNav("home")

    -- Folding: title click, caret and tooltip cue, persisted per character.
    local framesRow, combatRow = TitleRow(M, "frames"), TitleRow(M, "combat")
    local combatOpenY = Y(combatRow)
    local listScroll = parent._msuf2NavListScroll
    local list = parent._msuf2NavList
    listScroll:SetHeight(100)
    parent:_msuf2NavReflow()
    local openHeight = list:GetHeight()
    assert(Hover(framesRow, tip) == "Collapse", flavor .. ": open group title tooltip")
    assert(framesRow._msuf2NavArrow.rotation == math.pi * 0.5, flavor .. ": open caret")
    assert(framesRow:GetScript("OnClick"), flavor .. ": group title is not clickable")(framesRow)
    assert(M.navHeaderState.frames == false, flavor .. ": title click did not fold the group")
    local charKey = env.MSUF_GetCharKey()
    assert(env.MSUF_GlobalDB.char[charKey].menu2State.navHeaderState.frames == false,
        flavor .. ": folded group is not persisted")
    for _, key in ipairs({ "uf_player", "gf_layout", "opt_bars", "opt_castbar", "auras3_styling", "classpower" }) do
        assert(not buttons[key]:IsShown(), flavor .. ": " .. key .. " shown in a folded group")
    end
    assert(framesRow:IsShown(), flavor .. ": folded group lost its title")
    assert(framesRow._msuf2NavArrow.rotation == 0, flavor .. ": folded caret")
    assert(Hover(framesRow, tip) == "Expand", flavor .. ": folded group title tooltip")
    assert(combatOpenY - Y(combatRow) == -6 * 28, flavor .. ": folding did not pull the next group up")
    assert(list:GetHeight() == openHeight - 6 * 28, flavor .. ": rail height ignores the folded group")

    -- The Undo/Redo block stays right below the last visible row.
    local generalRow = TitleRow(M, "general")
    local history = M.historyControls
    M.SetNavGroupOpen("general", false)
    assert(history:IsShown() and Y(history) == Y(generalRow) - 22,
        flavor .. ": history block did not follow the folded General group")
    M.SetNavGroupOpen("general", true)
    assert(Y(history) == Y(buttons.profiles) - 30, flavor .. ": history block left profiles")

    -- Landing inside a folded group opens it; the lookup goes through the rail
    -- key, so a workspace tab (uf_target) opens Frames too.
    M.UpdateNav("uf_target")
    assert(M.navHeaderState.frames == true and buttons.uf_player:IsShown(),
        flavor .. ": navigation into a folded group did not reveal the active row")
    assert(buttons.uf_player._msuf2Active == true, flavor .. ": workspace tab did not mark its rail row")
    M.SetNavGroupOpen("frames", false)
    M.UpdateNav("uf_target")
    assert(M.navHeaderState.frames == false, flavor .. ": rebuilding the same page reopened a folded group")
    M.UpdateNav("opt_fonts")
    M.UpdateNav("opt_castbar")
    assert(M.navHeaderState.frames == true, flavor .. ": selecting a page in a folded group kept it folded")

    -- Window title: the breadcrumb the rail and search use.
    local expected = {
        opt_castbar = "Frames > Cast Bars",
        uf_target = "Frames > Unitframes > Target",
        gf_bars = "Frames > Party/Raid Frames > Dispel Overlay",
        auras3_styling = "Frames > Auras",
        opt_fonts = "Style > Fonts",
        home = "Dashboard",
    }
    local forever = M.Tr("MSUF (Forever Version)")
    for key, title in pairs(expected) do
        M.SetTitle(key)
        local want = world.client.isForever and forever or title
        assert(M.frame.title:GetText() == want,
            flavor .. ": " .. key .. " title " .. tostring(M.frame.title:GetText()) .. ", want " .. want)
    end
    M.SetTitle("opt_castbar")
    assert(world.client.isForever or M.frame.title:GetText():find(" > " .. buttons.opt_castbar:GetText(), 1, true),
        flavor .. ": title and rail label disagree")
    -- Minimizing copies the current title (MSUF_Menu2_Window.lua); a page change
    -- behind the bar has to carry over.
    M.minimizedBar = { title = parent:CreateFontString() }
    M.minimizedBar.title:SetText(M.frame.title:GetText())
    M.frame._msuf2Minimized = true
    M.SetTitle("gameplay")
    assert(M.minimizedBar.title:GetText() == M.frame.title:GetText()
        and (world.client.isForever or M.frame.title:GetText() == "General > Gameplay"),
        flavor .. ": minimized bar title did not follow the page")
    return world
end

local function LocalizedTitle()
    local world, env, M = Boot("Mainline", "deDE")
    -- The client runs this on ADDON_LOADED; the offline world never fires it.
    assert(world.core.FinalizeLocale() == "deDE", "deDE: language pack not selected")
    -- A theme font string translates on SetText; the joined title must not be
    -- looked up (and logged as missing) as a locale key of its own.
    M.frame = { title = M.Theme.Font(env.CreateFrame("Frame"), "GameFontDisableSmall", "MSUF") }
    M.SetTitle("uf_target")
    local want = M.Tr("Frames") .. " > " .. M.Tr("Unitframes") .. " > " .. M.Tr("Target")
    assert(M.Tr("Target") ~= "Target", "deDE: expected a translated Target label")
    assert(M.frame.title:GetText() == want, "deDE: breadcrumb title not translated per part: "
        .. tostring(M.frame.title:GetText()))
    assert(not (M.missingLocaleKeys or {})[want], "deDE: the joined title was translated as one locale key")
    InsertAfterTitle(M.navItems, "combat", { key = "smoke_dimmed", label = "Nameplates", group = "combat",
        availability = function() return false end })
    M.BuildNavRail(env.CreateFrame("Frame", nil, env.UIParent))
    local badge = assert(M.navButtons.smoke_dimmed._msuf2NavOffBadge, "deDE: dimmed row has no Off badge")
    assert(M.Tr("Off") ~= "Off" and badge:GetText() == M.Tr("Off"), "deDE: Off badge not translated: " .. tostring(badge:GetText()))
end

local function SkinnedSelection()
    local world, env, M = Boot("Mainline")
    local skin = assert(world.core.MenuSkin, "MenuSkin bridge missing")
    local originalButton = skin.Button
    skin.Button = function() return true end

    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    M.BuildNavRail(parent)
    M.UpdateNav("uf_target")
    local nav = assert(M.navButtons.uf_player, "Unitframes nav row missing")
    local navCue = assert(nav._msuf2SkinnedSelectionCue, "selected skinned nav has no cue")
    assert(nav._msuf2Active and navCue.wash:IsShown() and navCue.line:IsShown(),
        "selected Unitframes nav cue is hidden")
    M.UpdateNav("home")
    assert(not navCue.wash:IsShown() and not navCue.line:IsShown(), "old nav selection cue remains visible")

    local selected = "target"
    local section = env.CreateFrame("Frame", nil, parent)
    section:SetSize(280, 80)
    local bar = M.Widgets.ScopeOverrideBar({ width = 280, refreshers = {} }, section, {
        width = 280, label = "", labelWidth = 0, startX = 12,
        values = { { value = "player", text = "Player" }, { value = "target", text = "Target" } },
        getValue = function() return selected end,
        setValue = function(value) selected = value end,
    })
    local player, target = bar.buttons[1], bar.buttons[2]
    local targetCue = assert(target._msuf2SkinnedSelectionCue, "selected skinned Target tab has no cue")
    assert(target._msuf2SegmentChoice and target._msuf2Active and targetCue.wash:IsShown()
        and targetCue.line:IsShown(), "selected Target tab cue is hidden")
    selected = "player"
    bar:Refresh()
    assert(not targetCue.wash:IsShown() and not targetCue.line:IsShown(), "old Target tab cue remains visible")
    assert(player._msuf2Active and player._msuf2SkinnedSelectionCue.wash:IsShown(),
        "new Player tab cue is hidden")

    skin.Button = function() return false end
    player:RefreshVisual()
    assert(not player._msuf2SkinnedSelectionCue.wash:IsShown(), "skin switch left a stale cue")
    skin.Button = originalButton
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "Forever" }) do RailFlavor(flavor) end
LocalizedTitle()
SkinnedSelection()
print("menu2_nav_rail_groups_smoke: ok (3 clients, off reason, hidden rows, folding, breadcrumb title, skinned selection)")
