-- Colors must explain a saved transparent background without changing it.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, locale = arg[2] or "Mainline", arg[3] or "enUS"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", locale = locale, clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world) MW.InstallNativeUnitInputs(world) end,
    beforeOptions = function(world) assert(world.core.FinalizeLocale() == locale) end })
local M, core = mw.M, mw.core
local title = "Background opacity is set to 0%."
local message = "Background opacity is set to 0%.\nColor changes are invisible. Increase Opacity under More Options in the tint color picker."
local checks = 0
local function Check(ok, why)
    checks = checks + 1
    assert(ok, "background_opacity_warning " .. flavor .. ": " .. why)
end
local function Settle()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(1000)
    end
    M.Theme.StopAllMenuAnimations()
end
local g = M.EnsureDB().general
g.classBarBgR, g.classBarBgG, g.classBarBgB, g.classBarBgA = 0, 0, 0, 0
M.EnsureDB().player.hpBgAlpha = 0.8
Check(mw:Select("opt_colors") ~= false, "Colors did not open")
Settle()
local section = assert(M.cache.opt_colors.sections.colors_background)
local entry = assert(section._msuf2CollapsibleEntry)
local notice
for _, region in ipairs({ section:GetRegions() }) do
    if region.GetText and region:GetText() == M.Tr(message) then notice = region end
end
Check(notice ~= nil, "zero-opacity warning is absent")
Check(notice:IsShown(), "transparent profile hides warning")
Check(entry._msuf2UXSummary and entry._msuf2UXSummary:GetText() == M.Tr(title), "collapsed header lacks warning")
Check(g.classBarBgA == 0, "warning changed saved transparency")
if locale ~= "enUS" and locale ~= "enGB" then Check(M.Tr(message) ~= message, "warning was not translated") end
Check(M.Tr(message):find(M.Tr("More Options"), 1, true), "warning omits the opacity control route")
local sectionWidth = section._msuf2Width or 720
Check(notice:GetWidth() <= sectionWidth - 24, "warning overflows section")
local tint, reset
for _, control in ipairs(M.cache.opt_colors.searchWidgets) do
    local record = control._msuf2RuntimeControlRecord
    if control._msuf2ColorLabel == "Bar background tint" then tint = control end
    if record and record.controlId:match("background%.reset%.to%.black$") then reset = control end
end
Check(tint and reset, "background controls missing")
local function Visible(expected, why)
    Check(notice:IsShown() == expected, why)
    Check((entry._msuf2UXSummary ~= nil) == expected, why .. " (header)")
end
local previewPanel
for _, child in ipairs({ section:GetChildren() }) do
    if child:GetHeight() == 66 then previewPanel = child end
end
Check(previewPanel ~= nil, "inline preview panel missing")
local isVisible = previewPanel.IsVisible
previewPanel.IsVisible = function() return false end
g.classBarBgA = 1
M.Refresh()
Settle()
Visible(false, "hidden preview kept stale zero-opacity warning")
g.classBarBgA = 0
M.Refresh()
Settle()
Visible(true, "hidden preview prevented zero-opacity warning")
previewPanel.IsVisible = isVisible
M.Widgets.FocusCollapsibleSection(section, { persist = false, flash = false })
Settle()
Visible(true, "opening section lost warning")
M.SyncExternalHistoryState()
tint._msuf2OnColorChanged(0.7, 0.2, 0.4)
Settle()
Visible(true, "RGB-only edit hid transparent state")
tint._msuf2OnColorChanged(0.7, 0.2, 0.4, 1)
Settle()
Visible(false, "opacity edit did not clear warning")
Check(M.Undo(), "opacity edit cannot Undo")
Settle()
Visible(true, "Undo did not restore warning")
Check(M.Redo(), "opacity edit cannot Redo")
Settle()
Visible(false, "Redo did not clear warning")
local summary = entry._msuf2UXSummary
for _, value in ipairs({ 0, 0.001, 0.5, 1 }) do
    core._colorsAPI.SetClassBarBgColor(0, 0, 0, value)
    M.Refresh()
    Settle()
    Visible(value == 0, "incorrect warning for alpha " .. value)
    if value == 0 then summary = entry._msuf2UXSummary end
end
core._colorsAPI.SetClassBarBgColor(0, 0, 0, 0)
M.Refresh()
Settle()
Check(entry._msuf2UXSummary == summary, "warning recreated its header text")
MW.FireScript(reset, "OnClick", "LeftButton")
Settle()
Visible(false, "Reset to black retained warning")
g = M.EnsureDB().general
g.classBarBgA = nil
M.Refresh()
Settle()
Visible(false, "inherited opacity falsely warns")
local restored = core.ProfileFields.CopySnapshot(g)
restored.classBarBgA = 0
M.EnsureDB().general = restored
M.Refresh()
Settle()
Visible(true, "profile/general replacement retained old warning state")
M.HideSlashMenuAndMinibar(mw.win)
Settle()
M.Open("opt_colors")
Settle()
local live = M.cache.opt_colors.sections.colors_background
local reopened = live._msuf2CollapsibleEntry._msuf2UXSummary
Check(reopened and reopened:GetText() == M.Tr(title), "reopen lost warning")
Check(#mw.world.reported == 0, "menu reported errors")
print("menu_background_opacity_warning: " .. checks .. " checks pass (" .. flavor .. ", " .. locale .. ")")
