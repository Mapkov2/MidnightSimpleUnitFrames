-- Exercises the real Search routing rules used by Assistant V2 before lazy
-- page construction for selector-dependent Aura workspaces.

_G = _G or _ENV
local function Normalize(value)
    return tostring(value or ""):lower():gsub("[^%w]+", " "):gsub("%s+", " ")
        :gsub("^%s+", ""):gsub("%s+$", "")
end
local function Tokens(value)
    local out = {}; for word in Normalize(value):gmatch("%S+") do out[#out + 1] = word end; return out
end
local function KeySetFromWords(value)
    local out = {}; for word in tostring(value or ""):gmatch("%S+") do out[word] = true end; return out
end

local M = { Search = {}, gfScope = "party" }
M.Lines = function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
M.KeySetFromWords = KeySetFromWords
M.SetMenuStateValue = function(key, value) M[key] = value end
M.EnsurePersistentMenuState = function() end
M.InvalidatePage = function(key) M.invalidated = key end
M.GetGeneralDB = function() M.general = M.general or {}; return M.general end
M.Search._RoutingContext = {
    M = M,
    NormalizeSearchText = Normalize,
    BuildSearchQueryClauses = function(value) return Normalize(value), {} end,
    BuildSearchTokenList = Tokens,
    SearchEditDistanceWithin = function() return false end,
    SearchCombatLocked = function() return false end,
    ContentWidth = function() return 900 end,
    ContentHeight = function() return 700 end,
    DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } },
    DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } },
    DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } },
}
local namespace = { MSUF2 = M }
-- The routing module binds `local C_Timer = M.MenuTimer or _G.C_Timer` once at
-- load, so the table has to exist before it loads and every later stub must
-- mutate this same table rather than replace _G.C_Timer.
_G.C_Timer = _G.C_Timer or { After = function(_, fn) if type(fn) == "function" then fn() end end }
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua"))(
    "MidnightSimpleUnitFrames", namespace)
local routing = assert(M.Search._RoutingAPI)

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local value = handle:read("*a")
    handle:close()
    return value
end
local function Words(value)
    local out = {}
    for word in tostring(value or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end
local function VTPKeys(source, name)
    -- Values may be passed through a presentation-only width normalizer; the
    -- route contract still comes from the same VTP literal on that line.
    local encoded = assert(source:match(name .. '%s*=%s*[^\r\n]-VTP%s*"([^"]+)"'), "missing VTP declaration " .. name)
    local out = {}
    for row in encoded:gmatch("[^|]+") do
        local key = row:match("^([^=]+)=")
        assert(key and key ~= "", "invalid VTP row for " .. name .. ": " .. row)
        out[#out + 1] = key
    end
    return out
end
local function TableValueKeys(source, name)
    local body = assert(source:match("local%s+" .. name .. "%s*=%s*{(.-)\n}"), "missing table declaration " .. name)
    local out = {}
    for key in body:gmatch('value%s*=%s*"([^"]+)"') do out[#out + 1] = key end
    assert(#out > 0, "empty table declaration " .. name)
    return out
end

local auraSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
local groupAuraSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua")
local groupSpecsSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua")
local unitSectionsSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local unitWords = assert(unitSectionsSource:match('UNIT_AURAS_MENU_UNITS%s*=%s*M%.KeySetFromWords%s*"([^"]+)"'))
local declaredUnits = Words(unitWords)
local declaredUnitContainers = VTPKeys(auraSource, "UNIT_AURA_WORKSPACE_TABS")
local declaredUnitNormalTools = VTPKeys(auraSource, "UNIT_AURA_NORMAL_TOOLS")
local declaredUnitCustomTools = VTPKeys(auraSource, "UNIT_AURA_CUSTOM_TOOLS")
-- custom4 is the "Dots on target" container and carries its own tool strip.
local declaredUnitTargetDotTools = VTPKeys(auraSource, "UNIT_AURA_TARGET_DOT_TOOLS")
local declaredGroupScopes = VTPKeys(groupSpecsSource, "SCOPE_VALUES")
local declaredGroupLanes = TableValueKeys(groupAuraSource, "GF_AURA_WORKSPACE_LANES")
local declaredGroupTools = TableValueKeys(groupAuraSource, "GF_AURA_WORKSPACE_TOOLS")
local declaredStyleScopes = VTPKeys(auraSource, "AURA_SCOPE_VALUES")
local declaredUnitStyleContainers = VTPKeys(auraSource, "UNIT_STYLE_CONTAINER_VALUES")
local declaredLaneStyleContainers = VTPKeys(auraSource, "LANE_VALUES")

local unit = assert(routing.SearchRouteForTarget("uf_target", "target debuff blacklist spell id", ""))
assert(unit.tables.unitAuraTabSelection.target == "debuff")
assert(unit.nestedTables.unitAuraToolSelection.target.debuff == "blacklist")

local permanent = assert(routing.SearchRouteForTarget("uf_player", "Player Buff Hide Permanent Auras", ""))
assert(permanent.tables.unitAuraTabSelection.player == "buff")
assert(permanent.nestedTables.unitAuraToolSelection.player.buff == "filters",
    "Hide Permanent Auras routed to Layout instead of Filters")

local custom = assert(routing.SearchRouteForTarget("uf_player", "player custom 2 aura whitelist", ""))
assert(custom.tables.unitAuraTabSelection.player == "custom2")
assert(custom.nestedTables.unitAuraToolSelection.player.custom2 == "whitelist")

local style = assert(routing.SearchRouteForTarget("auras3_styling", "target custom 2 aura style size", ""))
assert(style.state.auraScope == "target")
assert(style.state.auraStyleContainer == "custom2", "Aura Style route lost the selected custom container")

local group = assert(routing.SearchRouteForTarget("gf_auras", "raid debuff dispellable filter", ""))
assert(group.state.gfScope == "raid")
assert(group.tables.gfAuraLaneSelection.raid == "debuff")
assert(group.nestedTables.gfAuraToolSelection.raid.debuff == "filters")

assert(routing.ApplySearchRoute("gf_auras", group) == true)
assert(M.gfScope == "raid" and M.gfAuraLaneSelection.raid == "debuff")
assert(M.gfAuraToolSelection.raid.debuff == "filters" and M.invalidated == "gf_auras")

-- Exhaust every declared selector workspace branch. This is a routing-only
-- contract against a local fake Menu2 state: it never writes MSUF_DB or invokes
-- a real setting/action command.
local unitMatrix, groupMatrix, styleMatrix = 0, 0, 0
local unitToolTerms = {
    layout = "layout size", filters = "filter only mine", blacklist = "blacklist spell id",
    setup = "setup", whitelist = "whitelist", dots = "dots",
}
for _, unitName in ipairs(declaredUnits) do
    for _, container in ipairs(declaredUnitContainers) do
        local customContainer = container:match("^custom%d$") ~= nil
        local tools = declaredUnitNormalTools
        if container == "custom4" then tools = declaredUnitTargetDotTools
        elseif customContainer then tools = declaredUnitCustomTools end
        for _, tool in ipairs(tools) do
            local toolTerm = assert(unitToolTerms[tool], "missing unit tool term " .. tool)
            local query = table.concat({ unitName, container, "aura", toolTerm }, " ")
            local route = assert(routing.SearchRouteForTarget("uf_" .. unitName, query, ""), query)
            assert(route.tables.unitAuraTabSelection[unitName] == container, query)
            assert(route.nestedTables.unitAuraToolSelection[unitName][container] == tool, query)
            unitMatrix = unitMatrix + 1
        end
    end
end

local groupToolTerms = { layout = "layout position", filters = "filter dispellable", blacklist = "blacklist spell id" }
for _, scope in ipairs(declaredGroupScopes) do
    local scopeTerm = scope == "mythicraid" and "mythic raid" or scope
    for _, lane in ipairs(declaredGroupLanes) do
        for _, tool in ipairs(declaredGroupTools) do
            local toolTerm = assert(groupToolTerms[tool], "missing group tool term " .. tool)
            local query = table.concat({ scopeTerm, lane, "aura", toolTerm }, " ")
            local route = assert(routing.SearchRouteForTarget("gf_auras", query, ""), query)
            assert(route.state.gfScope == scope, query)
            assert(route.tables.gfAuraLaneSelection[scope] == lane, query)
            assert(route.nestedTables.gfAuraToolSelection[scope][lane] == tool, query)
            groupMatrix = groupMatrix + 1
        end
    end
end

local unitStyleScope = { player = true, target = true, focus = true, boss = true }
for _, scope in ipairs(declaredStyleScopes) do
    local containers = unitStyleScope[scope] and declaredUnitStyleContainers or declaredLaneStyleContainers
    for _, container in ipairs(containers) do
        local scopeTerm = scope == "raid" and "raid" or scope
        local query = table.concat({ scopeTerm, container, "aura style size" }, " ")
        local route = assert(routing.SearchRouteForTarget("auras3_styling", query, ""), query)
        assert(route.state.auraScope == scope, query)
        assert(route.state.auraStyleContainer == container, query)
        styleMatrix = styleMatrix + 1
    end
end

-- Portrait workspaces must remain reachable in the minimum-width menu. The
-- helper is pure layout math, so load the page module with only its
-- declaration-time dependencies and exercise compact and wide tab layouts.
local portraitNS = { MSUF2 = { Widgets = {}, UnitPage = {} } }
portraitNS.MSUF2.ValueTextList = function() return {} end
portraitNS.MSUF2.KeySetFromWords = function() return {} end
portraitNS.MSUF2.PickDefaults = function() return {}, {}, {}, {}, {} end
portraitNS.MSUF2.Pick = function() end
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"))(
    "MidnightSimpleUnitFrames", portraitNS)
local PortraitLayout = assert(portraitNS.MSUF2.UnitPage.PortraitLayoutForWidth)
local compactLayout = PortraitLayout(434, "general")
assert(compactLayout.height == 340, "compact Portrait General tab has the wrong section height")
assert(compactLayout.cardX + compactLayout.cardW <= 434 and compactLayout.tabW <= 434,
    "compact Portrait tab or card extends outside the scroll content")
local compactGeometry = PortraitLayout(434, "geometry")
assert(compactGeometry.height == 610 and compactGeometry.cardW == compactLayout.cardW,
    "compact Portrait Geometry tab lost its full card or stable width")
local wideLayout = PortraitLayout(1128, "border")
assert(wideLayout.height == 496 and wideLayout.cardW == 620 and wideLayout.tabW == 780,
    "wide Portrait tab layout lost its bounded card or tab width")

for _, row in ipairs({
    { "player portrait render", "general" },
    { "player portrait width override", "geometry" },
    { "player portrait detached anchor point", "placement" },
    { "player portrait border thickness", "border" },
    { "player portrait background", "advanced" },
    { "right", "placement", "player.portraitDetachedPoint" },
    { "flat", "border", "player.portraitBorderArt" },
}) do
    local route = assert(routing.SearchRouteForTarget("uf_player", row[1], row[3] or ""), row[1])
    assert(route.tables.unitPortraitTabSelection.player == row[2],
        row[1] .. " did not route to Portrait tab " .. row[2])
end

-- Exercise real Search routing across a route-driven page rebuild. The exact
-- descriptor must reacquire the new widget, and compact scrolling must reserve
-- room for the floating unit preview instead of hiding the control beneath it.
local function FakeHighlight()
    local highlight = { _msuf2Anim = {} }
    function highlight._msuf2Anim:Stop() end
    function highlight._msuf2Anim:Play() highlight.played = (highlight.played or 0) + 1 end
    function highlight:ClearAllPoints() end
    function highlight:SetPoint(...) self.point = { ... } end
    function highlight:SetSize(w, h) self.width, self.height = w, h end
    function highlight:SetAlpha(value) self.alpha = value end
    function highlight:Show() self.shown = true end
    return highlight
end

local function FakeWrapper(top, width)
    local wrapper = { top = top, width = width, _msuf2SearchHighlight = FakeHighlight() }
    function wrapper:GetTop() return self.top end
    function wrapper:GetWidth() return self.width end
    function wrapper:GetParent() return nil end
    function wrapper:GetChildren() end
    return wrapper
end

local function FakeRegion(parent, top, text, measured)
    local region = { parent = parent, top = top, text = text }
    function region:GetParent() return self.parent end
    function region:GetTop() measured.count = measured.count + 1; return self.top end
    function region:GetObjectType() return "FontString" end
    function region:GetText() return self.text end
    return region
end

local exactNavigationMatrix = 0
for _, row in ipairs({ { 434, 406 }, { 1128, 786 } }) do
    for _, initiallyOpen in ipairs({ false, true }) do
        local callbacks = {}
        _G.C_Timer.After = function(_, fn) callbacks[#callbacks + 1] = fn end
        local staleMeasured, genericMeasured, exactMeasured = { count = 0 }, { count = 0 }, { count = 0 }
        local oldWrapper = FakeWrapper(1000, row[1])
        local newWrapper = FakeWrapper(1000, row[1])
        local staleWidget = FakeRegion(oldWrapper, 500, "Render", staleMeasured)
        local generic = FakeRegion(newWrapper, 800, "Player Portrait Render", genericMeasured)
        local exactWidget = FakeRegion(newWrapper, 100, "Render", exactMeasured)
        function oldWrapper:GetRegions() return nil end
        function newWrapper:GetRegions() return generic end

        local pinnedBox = {}
        function pinnedBox:IsShown() return true end
        function pinnedBox:GetBottom() return 760 end
        function pinnedBox:GetHeight() return 232 end
        local scroll = { value = 0 }
        function scroll:GetHeight() return row[2] end
        function scroll:GetTop() return 1000 end
        function scroll:SetVerticalScroll(value)
            self.value = value
            if value > 64 then self._msuf2PinnedPreviewActiveRecord = { box = pinnedBox }
            else self._msuf2PinnedPreviewActiveRecord = nil end
        end
        M.scrollFrame = scroll
        M.scrollChild = { GetHeight = function() return 1400 end }
        M.accordionState = { ["uf_player:portrait"] = initiallyOpen }
        M.activeKey = "home"
        M.cache = { uf_player = { wrapper = initiallyOpen and newWrapper or oldWrapper } }
        M.invalidated = nil
        local rebuilds = 0
        M.InvalidatePage = function(page) M.invalidated = page end
        M.SelectPage = function(page)
            if M.invalidated == page then
                M.cache[page] = { wrapper = newWrapper }
                M.invalidated = nil
                rebuilds = rebuilds + 1
            end
            M.activeKey = page
            return true
        end
        M.RuntimeControlCatalog = {
            FindBySettingKey = function(settingKey, page)
                assert(settingKey == "player.portraitRender" and page == "uf_player")
                if M.cache.uf_player and M.cache.uf_player.wrapper == newWrapper then
                    return { pageKey = page, settingKey = settingKey }, exactWidget
                end
            end,
        }

        local opened, focused, exact = routing.OpenSearchTarget(
            "uf_player", "Player Portrait Render", "Portrait Render", staleWidget, nil,
            { settingKey = "player.portraitRender" })
        assert(opened == true and focused == true and exact == true, "exact Portrait Render route was not resolved")
        local callbackIndex = 1
        while callbacks[callbackIndex] do
            local fn = callbacks[callbackIndex]
            callbackIndex = callbackIndex + 1
            fn()
            assert(callbackIndex < 30, "exact navigation scheduled an unbounded retry loop")
        end
        assert(rebuilds == (initiallyOpen and 0 or 1), "Portrait route rebuilt the page an unexpected number of times")
        assert(M.accordionState["uf_player:portrait"] == true, "Portrait route did not open its section")
        assert(staleMeasured.count == 0 and genericMeasured.count == 0 and exactMeasured.count > 0,
            "exact navigation measured a stale or fuzzy Portrait label")
        assert(newWrapper._msuf2SearchHighlight.shown == true, "exact Portrait control was not highlighted")
        local visibleTopInset = (newWrapper.top - exactWidget.top) - scroll.value
        assert(visibleTopInset >= 252, "compact exact control remained hidden below the pinned preview")
        assert(visibleTopInset <= row[2], "exact Portrait control was scrolled outside the viewport")
        exactNavigationMatrix = exactNavigationMatrix + 1
    end
end

-- The generated schema can contain a control that exists only after a finite
-- Aura workspace selector changes. Exercise the complete companion -> Menu2
-- API -> Search bridge handoff from the wrong currently-built workspace.
local routedCatalogId = "control:gf_auras/auras/group-workspace/lane/debuff/tool-selector@gf_auras/auras/group-workspace/lane/debuff/tool-selector"
local routedSettingKey = "auras3.target.debuff.blacklist.hidePermanent"
local routedCatalogDescriptor = {
    semanticId = routedCatalogId,
    pageKey = "gf_auras",
    controlPath = "auras/group-workspace/lane/debuff/tool-selector",
    label = "Edit",
    states = "workspace_routed",
}
local routedSettingDescriptor = {
    semanticId = "setting:auras3.target.debuff.blacklist.hidePermanent@uf_target/auras/unit-workspace/lane/debuff/filters/hide-permanent",
    settingKey = routedSettingKey,
    pageKey = "uf_target",
    controlPath = "auras/unit-workspace/lane/debuff/filters/hide-permanent",
    label = "Hide permanent",
    states = "workspace_routed",
}
namespace.Assistant = {
    ControlSchema = {
        GetBySemanticId = function(semanticId)
            if semanticId == routedCatalogId then return routedCatalogDescriptor end
        end,
        GetBySettingKey = function(settingKey)
            return settingKey == routedSettingKey and { routedSettingDescriptor } or {}
        end,
    },
    Registry = {
        GetSetting = function(_, settingKey)
            if settingKey == routedSettingKey then
                return { key = settingKey, label = "Hide permanent", type = "boolean", unit = "target" }
            end
        end,
    },
}

local routeQueries = {}
M.Search.RouteForTarget = function(page, query, fallback)
    routeQueries[#routeQueries + 1] = tostring(query or "")
    return routing.SearchRouteForTarget(page, query, fallback)
end
M.Search.ApplyRoute = routing.ApplySearchRoute
M.Search.OpenTarget = routing.OpenSearchTarget
_G.SlashCmdList = _G.SlashCmdList or {}
_G.C_Timer.After = function(_, fn) fn() end
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_SearchBridge.lua"))(
    "MidnightSimpleUnitFrames", namespace)
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_API.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local stateNavigationMatrix = 0
do
    local events, measured = {}, { count = 0 }
    local oldWrapper, newWrapper = FakeWrapper(1000, 900), FakeWrapper(1000, 900)
    function oldWrapper:GetRegions() return nil end
    function newWrapper:GetRegions() return nil end
    local exactWidget = FakeRegion(newWrapper, 600, "Edit", measured)
    M.gfScope = "party"
    M.gfAuraLaneSelection = { party = "buff" }
    M.gfAuraToolSelection = { party = { buff = "layout" } }
    M.activeKey = "gf_auras"
    M.cache = { gf_auras = { wrapper = oldWrapper } }
    M.invalidated = nil
    M.InvalidatePage = function(page)
        events[#events + 1] = "invalidate:" .. tostring(page)
        M.invalidated = page
        M.cache[page] = nil
    end
    M.SelectPage = function(page)
        events[#events + 1] = "select:" .. tostring(page)
        if M.invalidated == page then
            assert(M.gfAuraLaneSelection.party == "debuff", "group Aura route was not applied before rebuild")
            M.cache[page] = { wrapper = newWrapper }
            M.invalidated = nil
        end
        M.activeKey = page
        return true
    end
    M.Open = function(page)
        events[#events + 1] = "open:" .. tostring(page)
        return M.SelectPage(page)
    end
    M.RuntimeControlCatalog = {
        Resolve = function(semanticId, opts)
            events[#events + 1] = "resolve:" .. tostring(opts and opts.pageKey)
            assert(semanticId == routedCatalogId)
            if M.cache.gf_auras and M.cache.gf_auras.wrapper == newWrapper
                and M.gfAuraLaneSelection.party == "debuff"
            then
                return { pageKey = "gf_auras", label = "Edit", identityLabel = "Edit" }, exactWidget
            end
        end,
    }

    local ok, message = M.OpenExactCatalogControl(routedCatalogId, "Edit", "gf_auras")
    assert(ok == true, tostring(message))
    assert(table.concat(events, "|"):find("invalidate:gf_auras|open:gf_auras|select:gf_auras|resolve:gf_auras", 1, true),
        "catalog navigation did not route/rebuild before resolve: " .. table.concat(events, "|"))
    assert(routeQueries[#routeQueries]:find("auras lane debuff", 1, true),
        "catalog selector-bearing controlPath did not reach Search routing")
    assert(routeQueries[#routeQueries]:find(routedCatalogDescriptor.states, 1, true),
        "catalog finite-state membership did not reach Search routing")
    assert(measured.count > 0 and newWrapper._msuf2SearchHighlight.shown == true,
        "rebuilt catalog widget was not focused")
    stateNavigationMatrix = stateNavigationMatrix + 1
end

do
    local events, measured = {}, { count = 0 }
    local oldWrapper, newWrapper = FakeWrapper(1000, 900), FakeWrapper(1000, 900)
    function oldWrapper:GetRegions() return nil end
    function newWrapper:GetRegions() return nil end
    local exactWidget = FakeRegion(newWrapper, 560, "Hide permanent", measured)
    M.unitAuraTabSelection = { target = "buff" }
    M.unitAuraToolSelection = { target = { buff = "layout" } }
    M.activeKey = "uf_target"
    M.cache = { uf_target = { wrapper = oldWrapper } }
    M.invalidated = nil
    M.InvalidatePage = function(page)
        events[#events + 1] = "invalidate:" .. tostring(page)
        M.invalidated = page
        M.cache[page] = nil
    end
    M.SelectPage = function(page)
        events[#events + 1] = "select:" .. tostring(page)
        if M.invalidated == page then
            assert(M.unitAuraTabSelection.target == "debuff", "unit Aura lane route was not applied before rebuild")
            assert(M.unitAuraToolSelection.target.debuff == "filters", "unit Aura tool route was not applied before rebuild")
            M.cache[page] = { wrapper = newWrapper }
            M.invalidated = nil
        end
        M.activeKey = page
        return true
    end
    M.Open = function(page)
        events[#events + 1] = "open:" .. tostring(page)
        return M.SelectPage(page)
    end
    M.RuntimeControlCatalog = {
        FindBySettingKey = function(settingKey, page)
            events[#events + 1] = "resolve:" .. tostring(page)
            assert(settingKey == routedSettingKey)
            if M.cache.uf_target and M.cache.uf_target.wrapper == newWrapper
                and M.unitAuraTabSelection.target == "debuff"
                and M.unitAuraToolSelection.target.debuff == "filters"
            then
                return { pageKey = "uf_target", settingKey = settingKey,
                    label = "Hide permanent", identityLabel = "Hide permanent" }, exactWidget
            end
        end,
    }

    local ok, message = M.OpenExactSettingControl(routedSettingKey, "Hide permanent", "uf_target")
    assert(ok == true, tostring(message))
    local eventText = table.concat(events, "|")
    assert(eventText:find("invalidate:uf_target|resolve:uf_target|open:uf_target|select:uf_target|resolve:uf_target", 1, true),
        "setting navigation did not route/rebuild before exact reacquisition: " .. eventText)
    assert(routeQueries[#routeQueries]:find("auras lane debuff filters", 1, true),
        "setting selector-bearing controlPath did not reach Search routing")
    assert(routeQueries[#routeQueries]:find(routedSettingDescriptor.states, 1, true),
        "setting finite-state membership did not reach Search routing")
    assert(measured.count > 0 and newWrapper._msuf2SearchHighlight.shown == true,
        "rebuilt setting widget was not focused")
    stateNavigationMatrix = stateNavigationMatrix + 1
end

print(string.format("assistant_search_workspace_route_smoke: ok focused=4 unit_matrix=%d group_matrix=%d style_matrix=%d exact_navigation=%d",
    unitMatrix, groupMatrix, styleMatrix, exactNavigationMatrix)
    .. string.format(" state_navigation=%d", stateNavigationMatrix))
