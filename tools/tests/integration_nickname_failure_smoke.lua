-- A failing nickname provider cannot block fallback or escape quarantine on unrelated changes.
local root = assert(arg[1])
local reports, resolver, badCalls, fallbackCalls, combat = {}, nil, 0, 0, false
local env = setmetatable({}, { __index = _G })
env._G = env
env.geterrorhandler = function() return function(message)
    reports[#reports + 1] = message
    if env.reportThrows then error("reporter failed") end
end end
env.issecretvalue = function() return false end
env.UnitName = function(unit) return unit end
env.UnitFullName = function(unit) return unit, "Realm" end
env.InCombatLockdown = function() return combat end
local ns = { ExportPublic = function() end, UFText = { SetDisplayNameResolver = function(fn) resolver = fn end } }
local function Load(path)
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))
    setfenv(chunk, env)("MidnightSimpleUnitFrames", ns)
end
Load("Kernel/MSUF_Boundary.lua")
Load("Integrations/MSUF_Integration_NicknameProviders.lua")
local api = ns.API.Nicknames
if arg[2] ~= "budget" then
local function Bad() badCalls = badCalls + 1; error("foreign resolver failed") end
assert(api.RegisterProvider("broken", Bad, 100))
assert(api.RegisterProvider("fallback", function() fallbackCalls = fallbackCalls + 1; return "Nick" end, 1))
env.reportThrows = true
local ok, value = pcall(resolver, "party1")
assert(ok and value == "Nick", "failing provider/report prevented fallback: " .. tostring(value))
assert(badCalls == 1 and fallbackCalls == 1 and #reports == 1, "failure report/quarantine missing")
assert(resolver("party2") == "Nick" and badCalls == 1, "quarantined provider called again")
assert(api.RegisterProvider("other", function() return nil end, -1))
assert(resolver("party3") == "Nick" and badCalls == 1, "unrelated registration cleared quarantine")
assert(api.NotifyChanged("broken"))
assert(resolver("party3") == "Nick" and badCalls == 1, "notification cleared quarantine")
assert(api.RegisterProvider("broken", Bad, 100))
assert(resolver("party4") == "Nick" and badCalls == 2 and #reports == 2, "same-provider re-registration did not retry")
assert(api.RegisterProvider("broken", function() return "Recovered" end, 100))
assert(resolver("party1") == "Recovered", "replacement provider did not recover")
combat = true
assert(resolver("unknown") == "unknown", "provider invoked for unknown combat identity")
combat = false
end
assert(api.RegisterProvider("budget", function() return "Budget" end, 200))
assert(resolver("party1") == "Budget")
-- Warm lookup and combat paths allocate nothing; these bypass all foreign calls.
local function Measure(unit)
    collectgarbage("collect")
    collectgarbage("stop")
    local instructions = 0
    local function Count() instructions = instructions + 1 end
    local before = collectgarbage("count")
    debug.sethook(Count, "", 1)
    for _ = 1, 100 do resolver(unit) end
    debug.sethook()
    local delta = collectgarbage("count") - before
    collectgarbage("restart")
    return instructions, delta
end
local count, kb = Measure("party1")
local _, kbAgain = Measure("party1")
kb = math.min(kb, kbAgain)
combat = true
local combatCount, combatKB = Measure("party1")
local _, combatKBAgain = Measure("party1")
combatKB = math.min(combatKB, combatKBAgain)
assert(kb == 0 and combatKB == 0, "cached name lookup allocated")
assert(count <= 11508 and combatCount <= 5008, "cached name lookup instruction budget grew")
print(string.format("PASS integration_nickname_failure_smoke warm=%d/100 combat=%d/100 KB=%.3f/%.3f", count, combatCount, kb, combatKB))
