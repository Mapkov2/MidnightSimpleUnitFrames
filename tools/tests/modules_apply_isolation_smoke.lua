-- A module whose Enable raises is neither recorded as enabled nor allowed to
-- stop the remaining modules (review F28). The registry marked a module
-- enabled before Enable ran, so a failed Enable was never retried, and the
-- raise aborted the whole apply pass. The stub mirrors the client function:
-- errors are reported, the iteration continues.
-- Usage: lua tools/tests/modules_apply_isolation_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local reported = {}
function secureexecuterange(tbl, fn, ...)
    local key, value = next(tbl)
    while key ~= nil do
        local ok, err = pcall(fn, key, value, ...)
        if not ok then reported[#reported + 1] = tostring(err) end
        key, value = next(tbl, key)
    end
end
local ns = { ExportPublic = function(name, value) _G[name] = value end }
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MidnightSimpleUnitFrames", ns)
local broken, enabled = true, {}
ns.MSUF_RegisterModule("A", { order = 1, Enable = function() if broken then error("module A failed to enable") end enabled.A = true end })
ns.MSUF_RegisterModule("B", { order = 2, Enable = function() enabled.B = true end })
ns.MSUF_RegisterModule("C", { order = 3, Enable = function() enabled.C = true end,
    Disable = function() enabled.C = nil end, IsEnabled = function() return not enabled.turnOffC end })
ns.MSUF_ApplyModules()
assert(enabled.B and enabled.C, "a raising module stopped the remaining modules")
assert(#reported == 1 and reported[1]:find("module A failed", 1, true), "the module error was not reported")
assert(not ns.MSUF_ModulesByKey.A.__msufEnabled, "a module whose Enable raised was recorded as enabled")
broken = false
ns.MSUF_ApplyModules()
assert(enabled.A and ns.MSUF_ModulesByKey.A.__msufEnabled, "the failed module was not retried")
enabled.turnOffC = true
ns.MSUF_ApplyModules()
assert(enabled.C == nil and not ns.MSUF_ModulesByKey.C.__msufEnabled, "disable no longer works")
print("modules_apply_isolation_smoke: OK")
