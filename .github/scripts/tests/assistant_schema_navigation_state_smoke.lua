-- Regression: exact generated-schema navigation must apply a finite selector
-- route before the owning Menu2 page is lazily rebuilt and catalog-resolved.

_G = _G or _ENV
_G.SlashCmdList = _G.SlashCmdList or {}

local semanticId = "control:gf_auras/auras/group-workspace/lane/debuff/tool-selector@gf_auras/auras/group-workspace/lane/debuff/tool-selector"
local descriptor = {
    semanticId = semanticId,
    pageKey = "gf_auras",
    controlPath = "auras/group-workspace/lane/debuff/tool-selector",
    label = "Edit",
    states = "workspace_routed",
}

local events = {}
local function Event(value) events[#events + 1] = value end

local oldWrapper, rebuiltWrapper = {}, {}
local exactWidget = { parent = rebuiltWrapper }
local M = {
    activeKey = "gf_auras",
    gfAuraLane = "buff",
    cache = { gf_auras = { wrapper = oldWrapper } },
}
local namespace = {
    MSUF2 = M,
    Assistant = {
        ControlSchema = {
            GetBySemanticId = function(id)
                assert(id == semanticId, "unexpected generated semantic id")
                return descriptor
            end,
        },
    },
    ExportPublic = function(_, value) return value end,
}

M.BlockCombatAction = function() return false end
M.InvalidatePage = function(page)
    Event("invalidate")
    assert(page == "gf_auras")
    M.cache[page] = nil
    M.invalidated = page
end
M.SelectPage = function(page)
    Event("select")
    assert(page == "gf_auras")
    if M.invalidated == page then
        Event("build")
        assert(M.gfAuraLane == "debuff", "page rebuilt before selector route was applied")
        M.cache[page] = { wrapper = rebuiltWrapper }
        M.invalidated = nil
    end
    M.activeKey = page
    return true
end
M.Open = function(page)
    Event("open")
    return M.SelectPage(page)
end

M.Search = {
    RouteForTarget = function(page, query)
        Event("route")
        assert(page == "gf_auras")
        assert(tostring(query):find("auras lane debuff", 1, true),
            "generated selector-bearing controlPath did not reach Search routing")
        assert(tostring(query):find(descriptor.states, 1, true),
            "generated finite-state membership did not reach Search routing")
        return { lane = "debuff" }
    end,
    ApplyRoute = function(page, route)
        Event("apply")
        assert(page == "gf_auras" and route.lane == "debuff")
        if M.gfAuraLane ~= route.lane then
            M.gfAuraLane = route.lane
            M.InvalidatePage(page)
            return true
        end
        return false
    end,
    OpenTarget = function(page, _, _, preferredAnchor, route, exactTarget)
        Event("target")
        assert(page == "gf_auras" and route.lane == "debuff")
        assert(preferredAnchor == exactWidget, "rebuilt exact widget was not handed to Search")
        assert(exactTarget.semanticId == semanticId)
        assert(exactTarget.controlPath == descriptor.controlPath)
        assert(exactTarget.states == descriptor.states)
        M.SelectPage(page)
        return true, true, true
    end,
}

M.RuntimeControlCatalog = {
    Resolve = function(id, opts)
        Event("resolve")
        assert(id == semanticId and opts.pageKey == "gf_auras")
        if M.cache.gf_auras and M.cache.gf_auras.wrapper == rebuiltWrapper
            and M.gfAuraLane == "debuff"
        then
            return { pageKey = "gf_auras", label = "Edit", identityLabel = "Edit" }, exactWidget
        end
    end,
}

assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_SearchBridge.lua"))(
    "MidnightSimpleUnitFrames", namespace)
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_API.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local ok, message = M.OpenExactCatalogControl(semanticId, "Edit", "gf_auras")
assert(ok == true, tostring(message))
local order = table.concat(events, "|")
assert(order == "route|apply|invalidate|open|select|build|resolve|target|select",
    "unexpected route/rebuild/resolve order: " .. order)

print("assistant_schema_navigation_state_smoke: ok " .. order)
