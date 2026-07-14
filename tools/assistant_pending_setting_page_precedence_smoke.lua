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

assertPage("gf_bars", {
    key = "gf_party.dispelOverlayAlpha",
    attribute = "dispelOverlayAlpha",
    frameType = "group",
}, "group dispel overlay routes to group bars")

assertPage("gf_bars", {
    key = "gf_raid.debuffStripeEnabled",
    attribute = "debuffStripeEnabled",
    frameType = "group",
}, "group debuff stripe routes to group bars")

assertPage("gf_indicators", {
    key = "gf_party.roleIconEnabled",
    attribute = "roleIconEnabled",
    frameType = "group",
}, "group indicator routing still takes precedence")

assertPage("gf_layout", {
    key = "gf_party.width",
    attribute = "width",
    frameType = "group",
}, "ordinary group layout routing remains unchanged")

print("assistant_pending_setting_page_precedence_smoke: ok")
