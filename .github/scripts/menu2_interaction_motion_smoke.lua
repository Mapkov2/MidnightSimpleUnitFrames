local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local collapsible = assert(widgets:match(
    "function b:CollapsibleSection%b()%s*(.-)%s*function b:Header"
), "accordion builder missing")

local setImmediate = assert(collapsible:find("local function SetSectionOpenImmediate", 1, true),
    "accordion immediate state setter missing")
local clickHandler = assert(collapsible:find('header:SetScript("OnClick"', 1, true),
    "accordion click handler missing")
assert(setImmediate < clickHandler
    and collapsible:find("entry.SetOpenImmediate = SetSectionOpenImmediate", 1, true)
    and collapsible:find("SetSectionOpenImmediate(nextOpen)", 1, true),
    "accordion click and command paths do not share the immediate setter")
assert(collapsible:find("T.StopMotion(body)", 1, true),
    "accordion immediate setter does not cancel stale body motion")
assert(not collapsible:find("if entry._msuf2MotionActive then return end", 1, true)
    and not collapsible:find('T.PlayMotion(body, "accordionIn"', 1, true)
    and not collapsible:find('T.PlayMotion(body, "accordionOut"', 1, true)
    and not collapsible:find("SettleOpenedLayout", 1, true),
    "accordion clicks still fade, defer, or reject input while motion is active")
local tokens = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua")
assert(not tokens:find("accordionIn", 1, true) and not tokens:find("accordionOut", 1, true),
    "retired accordion alpha-motion tokens are still configured")
assert(widgets:find("T.ApplyCollapseVisual(entry.arrow, entry.hint, open)", 1, true)
    and widgets:find("NotifyCollapsibleSectionState(entry, open)", 1, true),
    "immediate accordion relayout no longer updates disclosure visuals and observers")

local theme = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
local navPaint = assert(theme:match(
    "local function PaintNavPillGlowArt%b()%s*(.-)%s*local function SetNavPillArt"
), "navigation pill paint helper missing")
assert(navPaint:find("StopNavPillGlowPulse(art)", 1, true)
    and not theme:find("StartNavPillGlowPulse", 1, true),
    "active page navigation still reads as an animated transition")

local window = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua")
local selectPage = assert(window:match(
    "function M.SelectPage%b()%s*(.-)%s*local function RestorePageScroll"
), "page selection function missing")
assert(not selectPage:find("PlayMotion", 1, true),
    "page selection gained a content transition instead of committing directly")
assert(not tokens:find("contentIn", 1, true) and not tokens:find("contentOut", 1, true),
    "retired page-content alpha-motion tokens are still configured")
assert(not window:find("_msuf2DiscoveryPulse", 1, true)
    and not window:find("PAGE_HISTORY_DISCOVERY_USES", 1, true)
    and not window:find("pageHistoryBackUses", 1, true),
    "page navigation still contains the retired Back discovery pulse")

local settle = assert(window:match(
    "local function QueueVisiblePageLayoutSettle%b()%s*(.-)%s*function RebuildActivePageForResize"
), "visible-page layout settle helper missing")
assert(settle:find("C_Timer.After(0, Settle)", 1, true),
    "required first-open text/layout settle was removed with interaction motion")

-- Class Resources coalesces preview movement through MenuRuntime. Lifecycle
-- teardown may cancel that task; the next request must replace the inactive
-- task so resource selection, X/Y sliders, and mouse drag can repaint again.
local support = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua")
assert(support:find('return Runtime:Schedule(delay, callback, "C_Timer.After")', 1, true),
    "MenuTimer.After does not return its cancellable MenuRuntime task")

local classPowerPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua")
classPowerPreview = classPowerPreview:gsub("\r\n", "\n")
local requestBody = assert(classPowerPreview:match(
    "(local function RequestClassPowerPreviewRefresh%b()%s*.-)%s*local function SetPreviewSummary"
), "Class Resources preview refresh function missing")
local pending = {}
local menuTimer = {}
function menuTimer.After(_, callback)
    local task = { active = true, callback = callback }
    pending[#pending + 1] = task
    return task
end
local previewEnv = setmetatable({
    M = { MenuTimer = menuTimer },
    C_Timer = menuTimer,
    CP_PREVIEW_REFRESH_DELAY = 0.05,
    tonumber = tonumber,
    type = type,
}, { __index = _G })
local requestChunk = assert(loadstring(requestBody .. "\nreturn RequestClassPowerPreviewRefresh"))
setfenv(requestChunk, previewEnv)
local RequestClassPowerPreviewRefresh = requestChunk()
local refreshReasons = {}
local previewBox = {}
function previewBox:IsShown() return true end
function previewBox:_msufCPPreviewHostShown() return true end
function previewBox:Refresh(reason) refreshReasons[#refreshReasons + 1] = reason end

RequestClassPowerPreviewRefresh(previewBox, "FIRST")
assert(#pending == 1 and previewBox._msufCPRefreshQueued == pending[1],
    "Class Resources preview did not retain its cancellable refresh task")
pending[1].active = false
RequestClassPowerPreviewRefresh(previewBox, "AFTER_RESUME")
assert(#pending == 2 and previewBox._msufCPRefreshQueued == pending[2],
    "cancelled Class Resources preview refresh still blocks a later request")
pending[2].active = false
pending[2].callback()
assert(#refreshReasons == 1 and refreshReasons[1] == "AFTER_RESUME",
    "recovered Class Resources preview did not repaint the newest state")
assert(previewBox._msufCPRefreshQueued == nil and previewBox._msufCPRefreshReason == nil,
    "completed Class Resources preview refresh left stale queue state")

io.write("menu2_interaction_motion_smoke: ok\n")
