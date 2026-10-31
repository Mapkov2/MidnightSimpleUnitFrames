local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end }, arg[3])
local M, W = mw.M, mw.core.ProfileWorkbench
local checks, failures = 0, {}
local function Check(ok, why)
    checks = checks + 1
    if not ok then failures[#failures + 1] = why end
end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local cases = {
    { "version.save", "Save restore point", "workbench_versions", "profiles" },
    { "review.prepare", "Review changes", "workbench_review", "profiles" },
    { "inspector.select", "Changed from factory defaults", "workbench_inspector", "profiles" },
    { "display.variant", "Profile variant", "workbench_display", "profiles" },
    { "accessibility.review", "Review accessibility changes", "workbench_accessibility", "opt_colors" },
    { "multi.left", "Align left", "workbench_alignment", "edit_selection" },
}
local api, called = M.Search._CoreAPI
local open = api.OpenSearchTarget
api.OpenSearchTarget = function(...)
    called = { open(...) }
    return unpack(called)
end
local points = #W.Points()
for _, item in ipairs(cases) do
    local record = { pageKey = "profile_tools", label = item[2], sectionId = item[3],
        controlId = M.ControlMeta("profile_tools", "profiles", item[1], "action").controlId }
    local expected = {}
    for key, value in pairs(record) do expected[key] = value end
    for pass = 1, 2 do
        assert(mw:Select("home"))
        Settle()
        called = nil
        api.OpenSearchTarget(record.pageKey, record.label, nil, nil, nil, record)
        Settle()
        local name = item[1] .. " pass" .. pass
        Check(called and called[1], name .. " failed to navigate")
        Check(M.activeKey == item[4], name .. " opened " .. tostring(M.activeKey) .. " instead of " .. item[4])
        Check(called and called[2] and called[3], name .. " did not focus exact moved control")
        for key, value in pairs(expected) do Check(record[key] == value, name .. " mutated target " .. key) end
        Check(#W.Points() == points, name .. " executed an action while navigating")
    end
end
for _, item in ipairs(M.navItems or {}) do Check(item.key ~= "profile_tools", "obsolete workbench remains in navigation") end
Check(not M.PageHasReset("edit_selection"), "Alignment unexpectedly offers a profile reset")
for _, failure in ipairs(failures) do print("FAIL", failure) end
assert(#failures == 0, tostring(#failures) .. " legacy ownership checks failed")
print("legacy_owner_probe: " .. flavor .. " passed " .. checks .. " checks")
