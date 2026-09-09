-- Client gates must survive enabled/imported profiles and apply before allocation.
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local core = "MidnightSimpleUnitFrames/"
local options = "MidnightSimpleUnitFrames_Options/"
for _, flavor in ipairs({ "Vanilla", "TBC", "Mists", "Mainline" }) do
    _G.C_AddOns = { GetAddOnMetadata = function() return flavor end }
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    _G.WOW_PROJECT_ID = ({ Vanilla = 2, TBC = 5, Mists = 19, Mainline = 1 })[flavor]
    local ns = {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MSUF", ns)
    assert(loadfile(core .. "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))("MSUF", ns)
    assert(loadfile(options .. "MSUF_OptionsLOD_Bootstrap.lua"))("Options", {})
    local menu = ns.MSUF2
    local boss = flavor == "Mists" or flavor == "Mainline"
    local arena = flavor ~= "Vanilla"
    assert(ns.UF.IsManagedUnit("boss1") == boss, flavor .. " boss allocation")
    assert(ns.UF.IsManagedUnit("arena1") == arena, flavor .. " arena allocation")
    for _, unit in ipairs(ns.UF.unitOrder) do
        assert(ns.Client.SupportsUnit(unit), flavor .. " contains unsupported managed unit")
    end
    local rows = menu.FilterSupportedUnitValues({{value="player"}, {value="boss"}, {value="arena"}})
    assert(#rows == 1 + (boss and 1 or 0) + (arena and 1 or 0), flavor .. " scope choices")
    assert(menu.SupportsUnitPage("opt_bars", "general.bossTargetOutlineMode") == boss)
    assert(menu.SupportsUnitPage("uf_boss") == boss)
    assert(menu.SupportsUnitPage("uf_arena") == arena)
    local source = read(options .. "Shell/Menu2/Pages/MSUF_Menu2_Unit_Classic.lua")
    source = source:sub(1, assert(source:find("local POWER_UNITS", 1, true)) - 1)
    local pages = assert(loadstring(source .. "\nreturn UNIT_PAGES"))("Options", ns)
    assert((pages.uf_boss ~= nil) == boss, flavor .. " boss page registered")
    assert((pages.uf_arena ~= nil) == arena, flavor .. " arena page registered")
    local tabs = read(options .. "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
    local start = assert(tabs:find("local function BuildTopActions", 1, true))
    local finish = assert(tabs:find("    local scopeOpts =", start, true))
    local order = {"player", "target", "boss", "arena", "focus", "pet", "targettarget", "focustarget"}
    local mapping = {}
    for key, page in pairs(pages) do mapping[page.unit] = key end
    local build = assert(loadstring("local M, UNIT_TAB_ORDER, UNIT_PAGE_FOR_UNIT = ...; local function UnitTopTabLabel(u) return u end; local function UnitTopTabWidth() return 50 end; "
        .. tabs:sub(start, finish - 1) .. " return scopeValues end; return BuildTopActions"))(menu, order, mapping)
    local visible = build({}, {width=720}, "player", "Player")
    assert(#visible == (flavor == "Vanilla" and 4 or flavor == "TBC" and 7 or 8), flavor .. " visible tab count")
    for _, row in ipairs(visible) do assert(ns.Client.SupportsUnit(row.value), "unsupported visible tab "..row.value) end
    local retail = flavor == "Mainline"
    assert(ns.Client.SupportsGroupKind("mythicraid") == retail)
    assert(menu.SupportsFrameScope("gf_mythicraid") == retail)
    assert(menu.SupportsUnitPage("gf_layout", "gf_mythicraid.enabled") == retail)
    local scopes = menu.FilterSupportedUnitValues({{value="party"},{value="raid"},{value="mythicraid"}})
    assert(#scopes == (retail and 3 or 2), flavor .. " mythic selector visible")
    assert(menu.NormalizeGroupScope("mythicraid") == (retail and "mythicraid" or "raid"))
    local groupDB = read(core .. "GroupFrames/MSUF_GroupFrames_DB.lua")
    local body = assert(groupDB:match("function GF.IsMythicRaidContext%(%)(.-)\nend"))
    local mythic = assert(loadstring("local MSUF = ...; local function IsInGroup() return true end; local function IsInRaid() return true end; local function GetRaidDifficultyID() return 16 end; return function() "..body.." end"))(ns)
    assert(mythic() == retail, flavor .. " must not route into a Mythic raid profile")

    for _, unit in ipairs({"Boss", "Arena"}) do
        local s = read(core .. "Castbars/MSUF_" .. unit .. "Castbars.lua")
        local fn = assert(s:match("local function " .. unit .. "CastbarsEnabled%(%)(.-)\nend"))
        _G.MSUF_DB = {general={enableBossCastbar=true,enableArenaCastbar=true}}
        local enabled = assert(loadstring("local MSUF, EnsureDB = ...; return function() " .. fn .. " end"))(ns, function() end)
        assert(enabled() == (unit == "Boss" and boss or unit == "Arena" and arena), flavor .. " castbar gate")
    end
    local s = read(options .. "Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua")
    local fn = assert(s:match("local function AddStaticIndexSearchRecords%(records, covered%)(.-)\nend"))
    local search = {StaticIndex={GetRecords=function() return {
        {key="uf_boss",searchIdentity="boss"}, {key="uf_arena",searchIdentity="arena"}, {key="uf_player",searchIdentity="player"}
    } end}}
    local add = assert(loadstring("local M, Search, InvokeOptional = ...; return function(records, covered) " .. fn .. " end"))(menu, search, pcall)
    local records = {}
    add(records, {})
    assert(#records == #rows, flavor .. " static search leaks unsupported pages")
end
print("classic_unit_availability_smoke: OK (Era, TBC, Mists, Mainline)")
