-- A 20-member name burst keeps the HEAD 71bb0f03 instruction limits, with no headroom.
-- Measured with the same real group-header world, on Lua 5.1 (32-bit).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
-- 2026-10-13: Mainline OOC 248 -> 249. The harness delivers each event to every frame in Lua, so the
-- EllesmereUI login watcher frame (one more frame) costs 11 instructions per event here only; the client
-- delivers UNIT_NAME_UPDATE only to registered frames, so in game the burst cost is unchanged.
local limits = assert(({ Mainline = { 249, 250 }, Vanilla = { 249, 250 } })[flavor])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, flavor)
local GF = h.GF
GF.EnsureDB()
GF.GetConf("raid").enabled = true
GF.RefreshHeaderLayout()
h:SetRaid(20)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local compiles, lifecycles = 0, 0
local compile, refresh = GF.CompileSpec, h.UF.RefreshGroupFrameState
GF.CompileSpec = function(...)
    compiles = compiles + 1
    return compile(...)
end
h.UF.RefreshGroupFrameState = function(...)
    lifecycles = lifecycles + 1
    return refresh(...)
end
local function Burst()
    for i = 1, 20 do h:Event("UNIT_NAME_UPDATE", "raid" .. i) end
    h:RunTimers()
end
local function Measure(label, limit)
    local ticks = 0
    collectgarbage("collect")
    collectgarbage("stop")
    compiles, lifecycles = 0, 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1000)
    Burst()
    debug.sethook()
    collectgarbage("restart")
    assert(ticks <= limit, string.format("%s %s: %dk instructions exceeds HEAD %dk", flavor, label, ticks, limit))
    assert(compiles == 0 and lifecycles == 0, label .. " compiled overlays or ran full group lifecycles")
    return ticks
end
Burst()
local ooc = Measure("OOC name burst", limits[1])
h:EnterCombat()
local combat = Measure("combat name burst", limits[2])
h:LeaveCombat()
assert(#h.violations == 0, tostring(h.violations[1]))
print(string.format("group_name_update_budget_smoke: ok (%s: 20 members, OOC %dk, combat %dk, HEAD limits unchanged)",
    flavor, ooc, combat))
