-- Regression: a clean inactive Guided Tour must not build its chrome or scan
-- cached page sections on ordinary Menu2 page selections/refreshes. Cleanup
-- still runs exactly once after an active tour owned visual state.
local root = arg and arg[1] or "."

local state = { status = "paused" }
local tour = {}
function tour:IsActive()
    return self == tour and state.status == "active"
end

local pinnedRefreshes = 0
local labelReads = 0
local body = {}
local outer = {
    SetAlpha = function() end,
}
body._msuf2CollapsibleEntry = {
    outer = outer,
    body = body,
    label = {
        GetText = function()
            labelReads = labelReads + 1
            return "Frame basics"
        end,
    },
    guidedOrder = 1,
}

local runtime = { previewInlineMode = false }
local M = {
    _guidedTourRuntime = runtime,
    cache = { home = { sections = { frame_basics = body } } },
    RefreshPinnedPreviews = function()
        pinnedRefreshes = pinnedRefreshes + 1
    end,
}
local MSUF = { MSUF2 = M, GuidedTour6 = tour }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local frame, status, host = {}, {}, {}
local anchorMutations, scrollbarRefreshes = 0, 0
local scroll = {
    ClearAllPoints = function() anchorMutations = anchorMutations + 1 end,
    SetPoint = function() anchorMutations = anchorMutations + 1 end,
    _msuf2RefreshScrollBar = function() scrollbarRefreshes = scrollbarRefreshes + 1 end,
}

assert(M.InstallGuidedTourChrome(frame, status, host, scroll) == nil,
    "inactive tour eagerly created its hidden chrome")
assert(runtime.chrome == nil, "inactive tour retained a chrome frame")
assert(runtime.chromeFrame == frame and runtime.chromeStatus == status
    and runtime.chromeHost == host and runtime.chromeScroll == scroll,
    "lazy chrome installation did not retain its construction handles")

assert(M.GuidedTourOnPageSelected("home") == false, "inactive page selection entered the tour")
assert(M.GuidedTourOnPageSelected("home") == false, "repeated inactive page selection entered the tour")
assert(M.RefreshGuidedTourChrome("WINDOW_SHOW") == false, "inactive refresh reported active chrome")
assert(labelReads == 0, "clean inactive tour scanned cached sections")
assert(pinnedRefreshes == 0, "clean inactive tour refreshed pinned previews")
assert(anchorMutations == 0 and scrollbarRefreshes == 0,
    "clean inactive tour mutated the scroll frame")

local hides = 0
runtime.chrome = {
    frame = frame,
    status = status,
    host = host,
    scroll = scroll,
    Hide = function() hides = hides + 1 end,
}
runtime.tourVisualsDirty = true
assert(M.RefreshGuidedTourChrome("COMPLETE") == false, "inactive transition cleanup reported active chrome")
assert(labelReads > 0, "active-to-inactive transition skipped section cleanup")
assert(hides == 1 and anchorMutations == 3 and scrollbarRefreshes == 1,
    "active-to-inactive transition did not restore chrome and scroll ownership exactly once")
local readsAfterCleanup = labelReads
assert(M.RefreshGuidedTourChrome("WINDOW_SHOW") == false, "clean post-tour refresh reported active chrome")
assert(labelReads == readsAfterCleanup and hides == 1
    and anchorMutations == 3 and scrollbarRefreshes == 1,
    "post-tour cleanup repeated after the visual state was already clean")

print("PASS guided tour inactive performance: lazy chrome and one-shot visual cleanup")
