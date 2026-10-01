-- Variant context events are cheap and precise (review F7).
-- * Only the conditions the entries use subscribe: a specialization-only
--   setup listens to no zone or roster event.
-- * A context event that leaves the set of matching entries unchanged runs no
--   profile apply, even when the location itself changed.
-- * Dispatching a context event allocates nothing.
-- Usage: lua tools/tests/profile_variants_context_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local NS = { Client = { SupportsEvent = function() return true end } }
local location, spec, group = "none", 63, false
function InCombatLockdown() return false end
function IsInInstance() return location ~= "none", location end
function IsInGroup() return group end
function MSUF_GetPlayerSpecID() return spec end
local frames = {}
function CreateFrame()
    local f = { events = {} }
    function f:SetScript(_, fn) self.event = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = f
    return f
end
for _, file in ipairs({ "MSUF_ProfileFields", "MSUF_ProfileVariants", "MSUF_ProfileVariantsRuntime" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/" .. file .. ".lua"))("MSUF", NS)
end
local V = NS.ProfileVariants
local applies = 0
NS.ProfileRuntime = { Apply = function() applies = applies + 1; V.ResolveCurrent() end }
MSUF_DB = { general = {}, player = { width = 120 } }

-- Specialization-only variant: no zone or roster subscription.
assert(V.Replace(MSUF_DB, { version = 1, entries = {
    { name = "Holy", conditions = { specs = { ["65"] = true } }, patch = { { path = { "player", "width" }, value = 180 } } },
} }))
local driver = assert(frames[1], "no event driver")
assert(driver.events.PLAYER_SPECIALIZATION_CHANGED and driver.events.PLAYER_LOGOUT, "specialization events missing")
assert(not driver.events.GROUP_ROSTER_UPDATE and not driver.events.ZONE_CHANGED_NEW_AREA,
    "a specialization-only variant subscribed to zone or roster events")
spec = 65
driver.event(driver, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(MSUF_DB.player.width == 180, "the specialization variant did not apply")
local before = applies
driver.event(driver, "PLAYER_ENTERING_WORLD")
assert(applies == before, "an unchanged specialization re-applied the profile")

-- Location variant plus specialization variant: moving between two places
-- that match the same entries runs no apply.
assert(V.Replace(MSUF_DB, { version = 1, entries = {
    { name = "Holy", conditions = { specs = { ["65"] = true } }, patch = { { path = { "player", "width" }, value = 180 } } },
    { name = "Dungeon", conditions = { context = "party" }, patch = { { path = { "player", "height" }, value = 50 } } },
} }))
assert(driver.events.GROUP_ROSTER_UPDATE and driver.events.ZONE_CHANGED_NEW_AREA, "location events missing")
before = applies
group = true
driver.event(driver, "GROUP_ROSTER_UPDATE")
location = "raid"
driver.event(driver, "ZONE_CHANGED_NEW_AREA")
assert(applies == before, "solo -> world -> raid re-applied although no matching entry changed")
location = "party"
driver.event(driver, "ZONE_CHANGED_NEW_AREA")
assert(applies == before + 1 and MSUF_DB.player.height == 50, "entering a dungeon did not apply its variant")

-- No allocation per context event.
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 2000 do driver.event(driver, "GROUP_ROSTER_UPDATE") end
local grown = collectgarbage("count") - kb
collectgarbage("restart")
assert(grown < 1, string.format("2000 context events allocated %.1f KB", grown))
print(string.format("profile_variants_context_smoke: OK (2000 events, %.2f KB)", grown))
