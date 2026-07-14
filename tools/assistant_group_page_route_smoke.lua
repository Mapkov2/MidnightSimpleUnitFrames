-- Runtime regression for the consolidated Group Layout and Dispel Overlay pages.
_G = _G or _ENV

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local MSUF = { MSUF2 = {} }
local M = MSUF.MSUF2
MSUF.ExportPublic = function(name, value)
    _G[name] = value
    return value
end
_G.MSUF_NS, _G.MSUF2 = MSUF, M
_G.MSUF_EM2 = {
    Focus = {},
    Util = {
        NormalizeFocusKey = function(value) return tostring(value or ""):lower() end,
        NormalizeFocusComponent = function(value) return tostring(value or ""):lower() end,
        NormalizeFocusSlot = function(value) return value end,
        UnitPageKey = function() return false end,
        UnitSectionForComponent = function(value) return value end,
    },
}
_G.GetTime = function() return 123 end
_G.C_Timer = { After = function() end }

assert(loadfile("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Focus.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(type(_G.MSUF_EM2_SetFocusSelection) == "function", "Edit Mode focus bridge did not load")

local cases = {
    { "layout", "gf_layout", "layout_advanced" },
    { "bars", "gf_layout", "general" },
    { "hp", "gf_layout", "text" },
    { "power", "gf_layout", "power" },
    { "name", "gf_layout", "text" },
    { "text", "gf_layout", "text" },
    { "range", "gf_layout", "range" },
    { "alpha", "gf_layout", "transparency" },
    { "dispel", "gf_bars", "dispel" },
    { "stripe", "gf_bars", "dstripe" },
    { "dstripe", "gf_bars", "dstripe" },
    { "auras", "gf_auras", "buffs" },
    { "status", "gf_indicators", "sicons" },
}

for i = 1, #cases do
    local row = cases[i]
    assert(_G.MSUF_EM2_SetFocusSelection("gf_party", row[1], nil, {
        source = "assistant-group-page-route-smoke",
        menuFocus = true,
    }) == true, row[1] .. " focus selection failed")
    local selection = assert(M.editModeSelection, row[1] .. " produced no Menu2 selection")
    assert(selection.pageKey == row[2],
        string.format("%s opened %s instead of %s", row[1], tostring(selection.pageKey), row[2]))
    assert(selection.sectionId == row[3],
        string.format("%s focused %s instead of %s", row[1], tostring(selection.sectionId), row[3]))
end

local popupSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua")
assert(popupSource:find('gf_bars = "dispel"', 1, true),
    "Group quick popup does not classify Dispel Overlay explicitly")
assert(popupSource:find('{ "Dispel Overlay", 96, 104, "gf_bars", "dispel" }', 1, true),
    "Group quick popup has no Dispel Overlay destination")
assert(not popupSource:find('{ "Health & Text", 96, 104, "gf_bars"', 1, true),
    "Group quick popup still routes Health & Text to Dispel Overlay")

print(string.format("assistant_group_page_route_smoke: ok editmode=%d popup_split=true", #cases))
