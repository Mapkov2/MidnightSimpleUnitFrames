local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local MW = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = MW.Open(root, flavor, { page = "opt_fonts", clientScriptBindings = true, nativeButtonLifecycle = true })
local M, link = mw.M, mw.core.SuiteLink

local function ReadTooltipControls()
    assert(mw:Select("opt_fonts"), "could not leave Misc")
    M.InvalidatePage("opt_misc")
    assert(mw:Select("opt_misc"), "could not open Misc")
    local entry = assert(M.cache.opt_misc, "Misc did not build")
    assert(not entry._msuf2BuildIncomplete, "Misc stopped building in the tooltip section")
    local section = assert(entry.sections.misc_tooltips, "missing unit frame tooltip section")
    M.Widgets.EnsureSectionContent(section)
    local controls = {}
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame:GetParent() == section and frame._msuf2SearchText then
            controls[frame._msuf2SearchText] = frame
        end
    end
    return controls
end

local function CheckCoreControls(reason)
    local controls = ReadTooltipControls()
    assert(not controls.Skinning, reason .. ": Suite link should be hidden")
    for _, label in ipairs({ "Tooltip source", "Tooltip anchor", "Show unitframe tooltips", "Modifier key" }) do
        assert(controls[label], reason .. ": missing " .. label)
    end
end

CheckCoreControls("Suite absent")
local opened = 0
local api = { version = 1, HasUnitFrameTooltipSettings = function() return true end }
mw.env.MSUFSuite = { API = api }
api.OpenUnitFrameTooltipSettings = function(...)
    assert(select("#", ...) == 0, "the Suite's opener received button script arguments")
    opened = opened + 1
    return true
end
local controls = ReadTooltipControls()
assert(not controls["Tooltip source"], "Core controls should be delegated to the Suite")
local button = assert(controls.Skinning, "missing Suite Skinning link")
assert(opened == 0, "building Misc opened Suite settings")
button:Click("LeftButton", false)
assert(opened == 1, "click did not open Suite tooltip settings exactly once")

api.HasUnitFrameTooltipSettings = function() return false end
button:Click("LeftButton", false)
assert(opened == 1, "a cached link opened Suite tooltip settings after they became unavailable")
CheckCoreControls("Suite tooltip options unavailable")
api.HasUnitFrameTooltipSettings = function() return true end
api.OpenUnitFrameTooltipSettings = nil
assert(link.OpenUnitFrameTooltipSettings() == false, "a missing Suite opener was called")
CheckCoreControls("Suite opener absent")
api.HasUnitFrameTooltipSettings = nil
CheckCoreControls("older Suite API")

print("menu_unit_tooltip_suite_link_smoke " .. flavor .. ": Suite Skinning link and Core fallback passed")
