_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local pageFor = assert(A._PendingResultRelatedPageForItem, "pending result page helper missing")

local function assertPage(expected, setting, label)
    local actual = pageFor({ setting = setting })
    assert(actual == expected, string.format("%s: expected %s, got %s", label, expected, tostring(actual)))
end

assertPage("opt_colors", {
    page = "opt_colors",
    frameType = "classPower",
    category = "Class Resources / Preview",
}, "explicit page beats classPower runtime owner")

assertPage("profiles", {
    page = "profiles",
    frameType = "group",
    unit = "target",
    category = "Colors / Class Power",
}, "explicit page beats every inferred route")

assertPage("opt_colors", {
    frameType = "classPower",
    category = "Colors / Class Power / Combo Points",
}, "color category beats classPower runtime owner")

assertPage("classpower", {
    frameType = "classPower",
    category = "Class Resources / Layout",
}, "ordinary classPower setting stays on classpower")

print("assistant_pending_setting_page_precedence_smoke: ok")
