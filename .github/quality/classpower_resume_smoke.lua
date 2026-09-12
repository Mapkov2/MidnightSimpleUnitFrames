-- Load the entire module without building any page or frame: the window calls
-- its lifecycle API on Home, before the lazy Class Resources preview exists.
local M = { Widgets = {}, Theme = {}, Fallbacks = { False = function() return false end }, cache = {} }
local timers = {}
_G.C_Timer = { After = function(delay, fn)
    assert(delay > 0)
    timers[#timers + 1] = fn
end }
M.MenuTimer = _G.C_Timer
local ns = { MSUF2 = M, ExportPublic = function(name, value) _G[name] = value end }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))("MSUF", ns)
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua"))("MSUF", ns)
local resume = assert(M.ResumeClassPowerPreview, "resume API is missing before the first preview build")
assert(resume("WINDOW_SHOW", "home") == false)
assert(resume("SELECT_PAGE", "classpower") == false)

local shown, refreshes, hostShown = false, 0, true
local box = { _msufCPPreviewPageKey = "classpower" }
function box:IsShown() return shown end
function box:Show() shown = true end
function box:_msufCPPreviewHostShown() return hostShown end
function box:Refresh() refreshes = refreshes + 1 end
M.cache.classpower = { classPowerPreview = box }
assert(resume("SELECT_CACHED", "home") == false and not shown)
hostShown = false
assert(resume("WINDOW_SHOW", "classpower") == false and not shown)
hostShown = true
assert(resume("SELECT_CACHED", "classpower") == true and shown)
assert(M.ClassPowerStackPreview.active == box)
assert(#timers == 1, "resume did not queue the preview refresh")
timers[1]()
assert(refreshes == 1, "resumed preview did not refresh")
local marker = {}
box._msufCPPreviewHostShown = function() error(marker) end
local ok, failure = pcall(resume, "WINDOW_SHOW", "classpower")
assert(not ok and failure == marker, "resume swallowed a real callback error")
M.cache.classpower = nil
shown = false
assert(resume("WINDOW_SHOW", "classpower") == false and not shown,
    "invalidated page resumed an obsolete preview")
print("PASS Class Resources resume: API before lazy build, exact page owner, hidden and invalidated pages")
