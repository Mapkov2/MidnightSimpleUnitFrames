-- Query, enable and disable faults must be isolated and retryable.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local errors, ns = {}, { PublicGlobals = {} }
function ns.ExportPublic(name, value) ns.PublicGlobals[name] = value end
function ns.Require(name) return assert(ns[name] or ns.PublicGlobals[name], name) end
local env = setmetatable({ _G = false }, { __index = _G })
env._G = env
env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
env.secureexecuterange = function(list, fn)
    for i = 1, #list do
        local ok, err = pcall(fn, i, list[i])
        if not ok then errors[#errors + 1] = err end
    end
end
for _, name in ipairs({ "MSUF_Boundary.lua", "MSUF_Modules.lua" }) do
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/" .. name))
    setfenv(chunk, env)("test", ns)
end
local badQuery, badEnable, badDisable = true, true, true
local queryCount, enableCount, following = 0, 0, 0
local a = { order = 1, IsEnabled = function() queryCount = queryCount + 1 if badQuery then error("query-fault") end return true end,
    Enable = function() enableCount = enableCount + 1 if badEnable then error("enable-fault") end end,
    Disable = function() if badDisable then error("disable-fault") end end }
ns.MSUF_RegisterModule("a", a)
ns.MSUF_RegisterModule("b", { order = 2, Enable = function() following = following + 1 end })
local ok, err = pcall(ns.MSUF_ApplyModules)
assert(ok, "IsEnabled escaped the module boundary: " .. tostring(err))
assert(following == 1 and not a.__msufEnabled and a.__msufSwitchTo == nil, "query failure blocked following module or latched")
badQuery = false
ns.MSUF_ApplyModules()
assert(enableCount == 1 and not a.__msufEnabled, "enable failure committed state")
badEnable = false
ns.MSUF_ApplyModules()
ns.MSUF_ApplyModules()
assert(a.__msufEnabled and enableCount == 2 and following == 1, "retry/idempotence failed")
a.IsEnabled = function() return false end
ns.MSUF_ApplyModules()
assert(a.__msufEnabled and a.__msufSwitchTo == nil, "disable failure committed state or latched")
badDisable = false
ns.MSUF_ApplyModules()
assert(a.__msufEnabled == false and #errors == 3, "disable retry or error reporting failed")
ns.MSUF_RegisterModule("late", { IsEnabled = function() error("late-query-fault") end })
assert(#errors == 4 and following == 1, "late registration escaped")
print("modules_enabled_boundary: PASS")

local nestedQuery, nestedEnable, nestedFollowing = 0, 0, 0
ns.MSUF_Modules, ns.MSUF_ModulesByKey = {}, {}
ns.__MSUF_ModulesApplied, ns.__MSUF_ModulesSorted = false, false
ns.MSUF_RegisterModule("nested-a", { order = 1,
    IsEnabled = function() nestedQuery = nestedQuery + 1 ns.MSUF_ApplyModules() return true end,
    Enable = function() nestedEnable = nestedEnable + 1 ns.MSUF_ApplyModules() end })
ns.MSUF_RegisterModule("nested-b", { order = 2, Enable = function() nestedFollowing = nestedFollowing + 1 end })
ns.MSUF_ApplyModules()
assert(nestedQuery == 1 and nestedEnable == 1 and nestedFollowing == 1, "reentrant query/enable applied twice")
print("modules_enabled_boundary: reentrancy PASS")
