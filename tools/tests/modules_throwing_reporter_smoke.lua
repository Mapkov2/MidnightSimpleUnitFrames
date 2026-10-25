-- Real module transitions isolate a throwing reporter within the same pass.
local root = assert(arg[1])
local ns = { PublicGlobals = {} }
function ns.ExportPublic(name, value) ns.PublicGlobals[name] = value end
local reports, attempts, fail, desired, following = 0, 0, true, true, 0
local lastReport
local env = setmetatable({}, { __index = _G })
env._G = env
env.geterrorhandler = function() return function(message)
    reports = reports + 1
    lastReport = message
    error("reporter-fault")
end end
for _, name in ipairs({ "MSUF_Boundary.lua", "MSUF_Modules.lua" }) do
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/" .. name))
    setfenv(chunk, env)("test", ns)
end
local function Transition()
    attempts = attempts + 1
    if fail then error("module-fault") end
end
local module = { order = 1, IsEnabled = function() return desired end, Enable = Transition, Disable = Transition }
local nextModule = { order = 2, IsEnabled = function() return desired end,
    Enable = function() following = following + 1 end, Disable = function() following = following + 1 end }
ns.MSUF_RegisterModule("throwing", module)
ns.MSUF_RegisterModule("following", nextModule)
local function Failure(expectedAttempts, expectedFollowing)
    local ok, why = pcall(ns.MSUF_ApplyModules)
    assert(ok, "throwing reporter aborted module pass: " .. tostring(why))
    assert(lastReport:find("module throwing: ", 1, true), lastReport)
    assert(lastReport:find("module-fault", 1, true), lastReport)
    assert(module.__msufSwitchTo == nil, "throwing reporter latched the module lock")
    assert(attempts == expectedAttempts and following == expectedFollowing, "retry/following module was blocked")
    assert(nextModule.__msufEnabled == desired, "following module missed its state in the same pass")
end
Failure(1, 1)
assert(not module.__msufEnabled, "failed enable committed state")
Failure(2, 1) -- The desired state is unchanged: the failed enable must retry.
fail = false
ns.MSUF_ApplyModules()
assert(module.__msufEnabled and attempts == 3, "same module could not retry enable")
fail, desired = true, false
Failure(4, 2)
assert(module.__msufEnabled, "failed disable committed state")
Failure(5, 2) -- An unchanged disable also retries without blocking the next module.
fail = false
ns.MSUF_ApplyModules()
ns.MSUF_ApplyModules()
assert(module.__msufEnabled == false and attempts == 6 and following == 2 and reports == 4, "retry/idempotence failed")
print("PASS module isolation: throwing reporter, same-pass following state, unchanged enable/disable retries")
