-- Render the real example buttons against the shared page-availability gate.
local root = assert(arg[1], "repository root required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline"):Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local e, M = world.env, world.core.MSUF2
local api = M.Search._CoreAPI
local combat, rendered, collected = false, {}, 0
e.InCombatLockdown = function() return combat end
e.UnitAffectingCombat = function() return false end
M.frame = e.CreateFrame("Frame", nil, e.UIParent)
M.frame:Show()
M.searchQuery, M.searchResultsQuery, M.searchResults = "", "", {}
local register = M.RegisterMenuChromeControl
M.RegisterMenuChromeControl = function(widget, path, ...)
    if path:match("^search%.shortcut%.") then rendered[#rendered + 1] = widget end
    return register(widget, path, ...)
end
local active = { suite_bags = true, suite_cooldownManager = true }
M.RegisterSearchAvailability("example-availability", function(page)
    if active[page] ~= nil then return active[page] end
end)
M.RegisterSearchProvider("example-provider", function() collected = collected + 1; return {} end)
local function Render()
    rendered = {}
    local ctx = { width = 900, wrapper = e.CreateFrame("Frame", nil, M.frame),
        SetContentHeight = function(self, value) self.contentHeight = value end }
    api.BuildSearchPage(ctx)
    return rendered
end
local function CheckExamples(expected)
    local buttons = Render()
    assert(#buttons == expected, "expected " .. expected .. " actual example buttons, got " .. #buttons)
    return buttons
end
local function Has(buttons, label)
    for _, button in ipairs(buttons) do if button:GetText() == label then return true end end
    return false
end
local core = CheckExamples(4)
-- Example gates ask for page availability; opening the search page before
-- anything is typed must not build the index (or collect providers).
assert(M.Search._RenderContext.SEARCH_STATE.records == nil and collected == 0,
    "rendering the empty search page built the search index")
assert(not Has(core, "Bags") and not Has(core, "Cooldowns"), "Core-only examples advertise Suite")
M.RegisterPage("suite_bags", {title="Bags", build=function() end})
M.RegisterPage("suite_cooldownManager", {title="Cooldowns", build=function() end})
api.MarkSearchIndexDirty()
local enabled = CheckExamples(6)
assert(Has(enabled, "Bags") and Has(enabled, "Cooldowns"), "enabled Suite examples are missing")
active.suite_bags = false
M.InvalidateSearchProvider("example-provider")
local partial = CheckExamples(5)
assert(not Has(partial, "Bags") and Has(partial, "Cooldowns"), "partial Suite filter failed")
active.suite_cooldownManager = false
M.InvalidateSearchProvider("example-provider")
CheckExamples(4)
local before = collected
M.frame:Hide()
CheckExamples(0)
M.frame:Show(); combat = true
CheckExamples(0)
combat = false; M.frame = nil
CheckExamples(0)
assert(collected == before, "closed/combat render collected a provider")
print("search_examples_render_smoke: PASS (actual Core/Suite buttons, partial/disabled Suite, hidden/combat gates)")
