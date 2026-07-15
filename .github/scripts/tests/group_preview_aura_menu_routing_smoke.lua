local root = arg and arg[1] or "."
local path = root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"

local selectedPage
local invalidatedPage
local selectedWithStaleCache
local M = {
    activeKey = "gf_layout",
    cache = {},
    gfScope = "party",
    gfAuraLaneSelection = { party = "buff" },
    GroupPreviewSpecs = {
        SECTION_PAGE = {
            buffs = "gf_auras",
            debuffs = "gf_auras",
            externals = "gf_auras",
        },
        PAGE_FOCUS = { gf_auras = "buffs" },
        AURA_GROWTH_TABLE = { RIGHTDOWN = {} },
    },
    Fallbacks = {},
}

function M.PickDefaults(source, words)
    local values = {}
    for key in tostring(words or ""):gmatch("%S+") do
        values[#values + 1] = source[key] or {}
    end
    return unpack(values)
end

function M.SetMenuStateValue(field, value)
    M[field] = value
end

function M.InvalidatePage(pageKey)
    invalidatedPage = pageKey
    M.cache[pageKey] = nil
end

function M.SelectPage(pageKey)
    selectedPage = pageKey
    selectedWithStaleCache = M.cache[pageKey] ~= nil
    M.activeKey = pageKey
    return true
end

local MSUF = {
    MSUF2 = M,
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
assert(type(M.GroupPreview) == "table" and type(M.GroupPreview.OpenSection) == "function",
    "group preview settings router was not exported")

local function OpenFromInactiveCachedPage(sectionKey, previousLane, expectedLane)
    selectedPage = nil
    invalidatedPage = nil
    selectedWithStaleCache = nil
    M.activeKey = "gf_layout"
    M.cache.gf_auras = { builtForLane = previousLane }
    M.gfAuraLaneSelection.party = previousLane

    assert(M.GroupPreview.OpenSection(sectionKey) == true, sectionKey .. " route failed")
    assert(M.gfAuraLaneSelection.party == expectedLane,
        sectionKey .. " did not select the expected Group Auras lane")
    assert(invalidatedPage == "gf_auras",
        sectionKey .. " did not invalidate the inactive cached Group Auras page")
    assert(selectedPage == "gf_auras", sectionKey .. " did not open Group Frames > Auras")
    assert(selectedWithStaleCache == false,
        sectionKey .. " selected Group Auras before discarding its stale lane content")
end

OpenFromInactiveCachedPage("debuffs", "buff", "debuff")
OpenFromInactiveCachedPage("externals", "debuff", "externals")

invalidatedPage = nil
M.activeKey = "gf_layout"
M.cache.gf_auras = { builtForLane = "externals" }
M.gfAuraLaneSelection.party = "externals"
assert(M.GroupPreview.OpenSection("externals") == true, "same-lane external route failed")
assert(invalidatedPage == nil, "same-lane route rebuilt an already correct Group Auras page")

print("group preview aura menu routing smoke: ok")
