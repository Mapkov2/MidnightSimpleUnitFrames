-- Exercise the release-notes branch, which is absent from the catalog fixture.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local harness = Read("tools/assistant_v1_catalog_crosswalk.lua")
local cut = assert(harness:find("\nlocal pageBuildFailures = {}", 1, true))
local M = assert(loadstring(harness:sub(1, cut - 1) .. "\nreturn M"))()
local namespace = _G.MSUF_NS
assert(loadfile("MidnightSimpleUnitFrames/State/MSUF_Changelog.lua"))("MidnightSimpleUnitFrames", namespace)
assert(namespace.MSUF_Changelog.entries[1], "bundled release notes missing")

local created = {}
local createFrame = _G.CreateFrame
_G.CreateFrame = function(kind, ...)
    local frame = createFrame(kind, ...)
    function frame:GetScript(event) return self._scripts[event] end
    created[#created + 1] = frame
    return frame
end
local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Dashboard.lua")
local finish = assert(source:find("\n-- The home page is assembled by Dashboard.Build", 1, true))
local build = assert(loadstring(source:sub(1, finish - 1) .. "\nreturn BuildDashboardChangelog"))(
    "MidnightSimpleUnitFrames_Options", namespace)
for _, initiallyOpen in ipairs({false, true}) do
    M.dashboardChangelogOpen = initiallyOpen
    local before = #created
    local toggles = 0
    build(_G.UIParent, 600, {onToggle = function() toggles = toggles + 1 end})
    local header = assert(created[before + 1])
    assert(#header._msuf2AccordionBorder == 4, "shared accordion rim missing")
    assert(M.dashboardChangelogOpen == initiallyOpen)
    for i = 1, 2 do
        header:GetScript("OnEnter")(header)
        header:GetScript("OnLeave")(header)
        header:GetScript("OnClick")(header)
        assert(M.dashboardChangelogOpen == (i == 1 and not initiallyOpen or i == 2 and initiallyOpen),
            "release notes did not toggle")
    end
    assert(toggles == 2)
end
-- The dashboard and settings pages share this highlight setter. A pale Modern
-- accent must remain readable at both ends without altering stock blue.
local function NewHighlight(fromColor, toColor)
    local header = _G.CreateFrame("Button", nil, _G.UIParent)
    header:SetSize(200, 32)
    return M.Widgets.CreateAccordionOpenHighlight(header, fromColor, toColor)
end
local blue = NewHighlight({ 0.231, 0.510, 0.965, 0.62 }, { 0.141, 0.365, 0.741, 0.56 })
assert(blue._msuf2FromR == 0.231 and blue._msuf2FromG == 0.510 and blue._msuf2FromB == 0.965
    and blue._msuf2ToR == 0.141 and blue._msuf2ToG == 0.365 and blue._msuf2ToB == 0.741,
    "readable Midnight blue was changed")
local pale = NewHighlight({ 0.94, 0.94, 0.94, 0.62 }, { 0.82, 0.82, 0.82, 0.56 })
assert(pale._msuf2FromR < 0.94 and pale._msuf2ToR < 0.82,
    "pale Modern accent was not darkened at both ends")
local function Luminance(r, g, b)
    local function Linearize(value)
        return value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * Linearize(r) + 0.7152 * Linearize(g) + 0.0722 * Linearize(b)
end
local theme = M.Theme.colors
local titleL = Luminance(theme.text[1], theme.text[2], theme.text[3])
for _, color in ipairs({ pale._msuf2SafeFromColor, pale._msuf2SafeToColor }) do
    local alpha = color[4]
    local backdrop = theme.panel2
    local surfaceL = Luminance(
        color[1] * alpha + backdrop[1] * (1 - alpha),
        color[2] * alpha + backdrop[2] * (1 - alpha),
        color[3] * alpha + backdrop[3] * (1 - alpha))
    assert((titleL + 0.05) / (surfaceL + 0.05) >= 5.5,
        "pale accordion title misses its contrast target")
end
print("dashboard_accordion_smoke: bundled notes, initial open/closed, toggle, hover and shared rim passed")
