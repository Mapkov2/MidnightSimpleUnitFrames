_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local M = assert(MSUF.MSUF2, "Menu namespace missing")
local A = assert(MSUF.Assistant, "Assistant missing")
local K = assert(A.Knowledge, "Assistant knowledge missing")

local searchRoot = "MidnightSimpleUnitFrames/Shell/Menu2/Search/"
if not exists(searchRoot .. "MSUF_Menu2_Search_Data.lua") then searchRoot = "Shell/Menu2/Search/" end

local menuRoot = "MidnightSimpleUnitFrames/Shell/Menu2/"
if not exists(menuRoot .. "MSUF_Menu2_Navigation.lua") then menuRoot = "Shell/Menu2/" end

local function loadMenu(name)
    local chunk, err = loadfile(menuRoot .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function loadSearch(name)
    local chunk, err = loadfile(searchRoot .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadMenu("MSUF_Menu2_Navigation.lua")

for _, file in ipairs({
    "MSUF_Menu2_Search_Data.lua",
    "MSUF_Menu2_Search_Keywords.lua",
    "MSUF_Menu2_Search_QueryAliases.lua",
    "MSUF_Menu2_Search_FAQ.lua",
    "MSUF_Menu2_Search_FAQ_Catalog_01.lua",
    "MSUF_Menu2_Search_FAQ_Catalog_02.lua",
    "MSUF_Menu2_Search_FAQ_Catalog_03.lua",
    "MSUF_Menu2_Search_FAQ_Catalog_04.lua",
}) do
    loadSearch(file)
end

if K.MarkDirty then K.MarkDirty() end

local Data = assert(M.SearchData, "Search data missing")

local function searchKeywordList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "table" then
            for j = 1, #value do out[#out + 1] = value[j] end
        elseif type(value) == "string" and value:find("|", 1, true) then
            for part in value:gmatch("[^|]+") do out[#out + 1] = part end
        elseif value ~= nil then
            out[#out + 1] = tostring(value)
        end
    end
    return out
end

local faqEnv = {
    SearchKeywordList = searchKeywordList,
    DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } },
    DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } },
    DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } },
    SEARCH_DISPEL_DEBUFF_KEYWORDS = Data.DISPEL_DEBUFF_KEYWORDS or {},
    SEARCH_HIGHLIGHT_BORDER_KEYWORDS = Data.HIGHLIGHT_BORDER_KEYWORDS or {},
    SEARCH_DISPEL_OVERLAY_KEYWORDS = Data.DISPEL_OVERLAY_KEYWORDS or {},
    SEARCH_DEBUFF_STRIPE_KEYWORDS = Data.DEBUFF_STRIPE_KEYWORDS or {},
    SEARCH_BLIZZARD_DISPEL_KEYWORDS = Data.BLIZZARD_DISPEL_KEYWORDS or {},
    SEARCH_UNIT_AURA_DISPEL_KEYWORDS = Data.UNIT_AURA_DISPEL_KEYWORDS or {},
    SEARCH_DASHBOARD_RECOVERY_KEYWORDS = Data.DASHBOARD_RECOVERY_KEYWORDS or {},
    SEARCH_DASHBOARD_DISCORD_KEYWORDS = Data.DASHBOARD_DISCORD_KEYWORDS or {},
    SEARCH_DASHBOARD_SUPPORT_KEYWORDS = Data.DASHBOARD_SUPPORT_KEYWORDS or {},
    SEARCH_DASHBOARD_WAGO_KEYWORDS = Data.DASHBOARD_WAGO_KEYWORDS or {},
    SEARCH_DASHBOARD_SCALING_KEYWORDS = Data.DASHBOARD_SCALING_KEYWORDS or {},
    SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = Data.DASHBOARD_CHANGELOG_KEYWORDS or {},
}

local faqRows = assert(Data.BuildFAQ, "FAQ builder missing")(faqEnv)
local index = K.EnsureIndex()
local faqItems = {}
local pageItems = {}
for _, item in ipairs(index.items or {}) do
    if item.kind == "faq" then faqItems[#faqItems + 1] = item end
    if item.kind == "page" then pageItems[item.key] = item end
end

local navPageKeys = {}
for _, nav in ipairs(M.navItems or {}) do
    if type(nav) == "table" and type(nav.key) == "string" and nav.key ~= "" then
        navPageKeys[nav.key] = true
    end
end
for pageKey in pairs(M.navPrimaryForKey or {}) do navPageKeys[pageKey] = true end
navPageKeys.search = true
navPageKeys.guided_setup = true

local failures = {}
local function fail(kind, detail)
    failures[#failures + 1] = tostring(kind) .. ": " .. tostring(detail or "")
end

local function matchingFaq(row)
    for _, item in ipairs(faqItems) do
        if tostring(item.label or "") == tostring(row.label or "")
            and tostring(item.page or "") == tostring(row.pageKey or "") then
            return item
        end
    end
end

for _, row in ipairs(faqRows or {}) do
    local item = matchingFaq(row)
    if not item then
        fail("faq indexed", tostring(row.label or "?") .. " / " .. tostring(row.pageKey or "?"))
    else
        if type(item.page) ~= "string" or item.page == "" then
            fail("faq page", tostring(row.label or "?"))
        end
    end
end

local checkedPages = 0
for pageKey in pairs(navPageKeys) do
    checkedPages = checkedPages + 1
    if not pageItems[pageKey] then
        fail("canonical page indexed", pageKey)
    else
        local label = type(M.GetMenuPageLabel) == "function" and M.GetMenuPageLabel(pageKey)
            or (type(A.DisplayPageLabel) == "function" and A.DisplayPageLabel(pageKey, pageKey) or pageKey)
        local results = K.Search(label, 20, { kind = "page" })
        local found = false
        for _, result in ipairs(results or {}) do
            if result.item and result.item.kind == "page" and result.item.key == pageKey then
                found = true
                break
            end
        end
        if not found then fail("page label search", pageKey .. " via " .. tostring(label or "")) end
    end
end
if checkedPages ~= 28 then fail("canonical page count", "expected 28, got " .. tostring(checkedPages)) end

local keywordProbes = {
    { page = "gameplay", query = "combat timer" },
    { page = "gameplay", query = "totem frame" },
    { page = "gameplay", query = "combat crosshair" },
    { page = "home", query = "display recovery" },
    { page = "classpower", query = "detached power bar" },
    { page = "classpower", query = "alternative mana" },
    { page = "uf_target", query = "target frame" },
    { page = "gf_auras", query = "group auras" },
    { page = "auras3_filters", query = "aura filters" },
    { page = "auras3_custom", query = "custom auras" },
    { page = "modules", query = "modules" },
    { page = "search", query = "search" },
    { page = "guided_setup", query = "guided setup" },
}

for _, probe in ipairs(keywordProbes) do
    local results = K.Search(probe.query, 12, { kind = "page" })
    local found = false
    for _, result in ipairs(results or {}) do
        if result.item and result.item.kind == "page" and result.item.key == probe.page then
            found = true
            break
        end
    end
    if not found then fail("page keyword probe", tostring(probe.page) .. " via " .. tostring(probe.query)) end
end

if #failures > 0 then
    io.stderr:write("assistant_menu_search_coverage_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, 80) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_menu_search_coverage_audit: ok faq=" .. tostring(#faqRows)
    .. " pages=" .. tostring(checkedPages)
    .. "\n")
io.flush()
os.exit(0, true)
