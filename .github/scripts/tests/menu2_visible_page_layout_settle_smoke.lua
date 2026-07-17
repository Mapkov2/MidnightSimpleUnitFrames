local path = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local settle = assert(source:match(
    "local function QueueVisiblePageLayoutSettle%b()%s*(.-)%s*function RebuildActivePageForResize"
), "visible-page layout settle helper missing")

assert(settle:find("entry._msuf2VisibleLayoutSettleQueued", 1, true),
    "visible-page layout settle is not coalesced")
assert(settle:find("for _, body in pairs(entry.sections or {}) do", 1, true)
    and settle:find("section._msuf2RefreshLayout()", 1, true),
    "visible-page layout settle does not refresh accordion header geometry")
assert(settle:find("builder:RelayoutCollapsibles()", 1, true)
    and settle:find("ApplyScrollMetrics()", 1, true),
    "visible-page layout settle does not finish page/scroll geometry")
assert(settle:find("C_Timer.After(0, Settle)", 1, true),
    "visible-page layout settle is not deferred until anchored widths resolve")
assert(not settle:find("OnUpdate", 1, true),
    "visible-page layout settle added recurring runtime work")

local callCount = 0
for _ in source:gmatch("QueueVisiblePageLayoutSettle%(") do callCount = callCount + 1 end
assert(callCount >= 4,
    "visible-page layout settle is not wired to cached selection, new selection, and window show")

io.write("menu2_visible_page_layout_settle_smoke: ok\n")
