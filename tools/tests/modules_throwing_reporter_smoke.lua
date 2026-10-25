-- Real module transitions must release their reentrancy lock before reporting.
local root = assert(arg[1])
local ns = { PublicGlobals = {} }
function ns.ExportPublic(name, value) ns.PublicGlobals[name] = value end
local reports, fail, desired, following = 0, true, true, 0
local env = setmetatable({}, { __index = _G })
env._G = env
env.geterrorhandler = function() return function(message)
    reports = reports + 1
    assert(message:find("module-fault", 1, true), message)
    error("reporter-fault")
end end
for _, name in ipairs({ "MSUF_Boundary.lua", "MSUF_Modules.lua" }) do
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/" .. name))
    setfenv(chunk, env)("test", ns)
end
local module = { order = 1,
    IsEnabled = function() return desired end,
    Enable = function() if fail then error("module-fault") end end,
    Disable = function() if fail then error("module-fault") end end }
ns.MSUF_RegisterModule("throwing", module)
ns.MSUF_RegisterModule("following", { order = 2, Enable = function() following = following + 1 end })
local function Failure()
    local ok, why = pcall(ns.MSUF_ApplyModules)
    assert(not ok and tostring(why):find("reporter-fault", 1, true), "reporter did not throw")
    assert(module.__msufSwitchTo == nil, "throwing reporter latched the module lock")
end
Failure()
assert(not module.__msufEnabled, "failed enable committed state")
-- Keep the failed module disabled while the next independent module runs.
desired = false
ns.MSUF_ApplyModules()
assert(following == 1, "following module was blocked")
fail, desired = false, true
ns.MSUF_ApplyModules()
assert(module.__msufEnabled, "same module could not retry enable")
fail, desired = true, false
Failure()
assert(module.__msufEnabled, "failed disable committed state")
fail = false
ns.MSUF_ApplyModules()
assert(module.__msufEnabled == false and following == 1 and reports == 2, "retry/idempotence failed")
print("PASS module lock: throwing reporter, following module, enable/disable retries")
