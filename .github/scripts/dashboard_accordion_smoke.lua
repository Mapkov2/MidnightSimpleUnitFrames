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
local finish = assert(source:find("\nlocal function StartGuidedSetupFromDashboard", 1, true))
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
print("dashboard_accordion_smoke: bundled notes, initial open/closed, toggle, hover and shared rim passed")
