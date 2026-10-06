-- The optional Suite tab and its seen marker must not affect MSUF releases.
local root = assert(arg[1], "Classic repository root required")
local buttons, labels = {}, {}
local function Widget()
    local widget = { scripts = {} }
    function widget:SetPoint() end
    function widget:SetWidth() end
    function widget:SetHeight() end
    function widget:SetSize() end
    function widget:SetJustifyH() end
    function widget:SetWordWrap() end
    function widget:SetNonSpaceWrap() end
    function widget:SetSpacing() end
    function widget:SetColorTexture() end
    function widget:GetStringHeight() return 16 end
    function widget:GetHeight() return 16 end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:CreateTexture() return Widget() end
    return widget
end
_G.CreateFrame = function() return Widget() end
_G.MSUFSuite, _G.MSUF_GlobalDB = nil, nil
local theme = {
    colors = { text = { 1, 1, 1 }, title = { 1, 1, 1 }, muted = { 1, 1, 1 },
        accent = { 1, 1, 1 }, accent2 = { 1, 1, 1 }, warning = { 1, 1, 1 } },
    Font = function(_, _, value)
        labels[#labels + 1] = value
        return Widget()
    end,
    Button = function(_, value)
        local button = Widget()
        button.label = value
        buttons[#buttons + 1] = button
        return button
    end,
}
local msuf = { MSUF_FullChangelog = {
    currentVersion = "6.5-beta11", entries = { { version = "6.5-beta11", date = "2026-09-29",
        sections = { { title = "Highlights", bullets = { "MSUF note" } } } } },
} }
local menu = { Theme = theme, Tr = function(value) return value end }
msuf.MSUF2 = menu
function menu.RegisterPage(key, spec) menu.pages = menu.pages or {}; menu.pages[key] = spec end
function menu.SelectPage(key) menu.selectedPage = key; return true end
function menu.InvalidatePage(key) menu.invalidatedPage = key end
function menu.RebuildPageKeepingScroll(key) menu.rebuiltPage = key end
function menu.RefreshSeeNewFeaturesBadge() menu.badgeRefreshes = (menu.badgeRefreshes or 0) + 1 end
-- Bindings publishes the combat block before the changelog page loads.
function menu.BlockCombatAction() return false end
local function Build()
    buttons, labels = {}, {}
    menu.pages.changelog.build({ wrapper = Widget(), width = 760, SetContentHeight = function() end })
end
local function HasButton(label)
    for _, button in ipairs(buttons) do if button.label == label then return button end end
end
local function HasLabel(label)
    for _, value in ipairs(labels) do if value == label then return true end end
end

-- The core's Suite link (Kernel/MSUF_SuiteLink.lua), which the page asks for the Suite changelog.
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua"))("MidnightSimpleUnitFrames", msuf)
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Changelog.lua"))("MidnightSimpleUnitFrames_Options", msuf)
Build()
assert(not HasButton("MSUF Suite"), "Suite tab appears without Suite")
assert(HasLabel("MSUF note"), "MSUF release notes missing")
assert(menu.HasUnseenChangelog(), "new MSUF release not announced")
menu.OpenSeeNewFeatures()
assert(_G.MSUF_GlobalDB.global.seenChangelogVersion == "6.5-beta11", "MSUF seen marker missing")
assert(not menu.HasUnseenChangelog(), "MSUF badge did not clear")

_G.MSUFSuite = { Changelog = { currentVersion = "1.0 Alpha 1", entries = {
    { version = "1.0 Alpha 1", date = "2026-09-25",
        sections = { { title = "Changes", bullets = { "Suite note" } } } },
} } }
assert(menu.HasUnseenChangelog(), "new Suite release not announced")
menu.OpenSeeNewFeatures()
assert(menu.changelogSource == "suite", "unseen Suite release was not selected")
assert(_G.MSUF_GlobalDB.global.seenSuiteChangelogVersion == "1.0 Alpha 1", "Suite seen marker missing")
assert(_G.MSUF_GlobalDB.global.seenChangelogVersion == "6.5-beta11", "Suite changed MSUF seen marker")
Build()
assert(HasButton("MSUF") and HasButton("MSUF Suite"), "both source tabs missing")
assert(HasLabel("Suite note") and not HasLabel("MSUF note"), "Suite tab shows the wrong release")
HasButton("MSUF").scripts.OnClick()
Build()
assert(HasLabel("MSUF note") and not HasLabel("Suite note"), "MSUF tab shows the wrong release")
assert(not menu.HasUnseenChangelog(), "badge did not clear after both histories were read")

_G.MSUFSuite.Changelog.currentVersion = "1.0 Alpha 2"
assert(menu.HasUnseenChangelog(), "a later Suite release is not announced")
menu.BlockCombatAction = function() return true end
assert(not menu.OpenSeeNewFeatures(), "combat blocked page opening succeeded")
assert(_G.MSUF_GlobalDB.global.seenSuiteChangelogVersion == "1.0 Alpha 1", "blocked opening marked Suite seen")
print("changelog_dual_source_smoke: ok")
