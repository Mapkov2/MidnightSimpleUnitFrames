-- Reuse the native health-tick harness with the queue's new source location.
-- The frozen harness identifies its OnUpdate by source path; without this
-- adapter queued cases silently omit the drain and undercount all its work.
-- Same arguments and budgets: <repoRoot> <flavor> [print].
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/tools/tests/health_tick_native_budget_smoke.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local count
source, count = source:gsub(
    'local PREDICTION_SOURCE = "UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"',
    'local PREDICTION_SOURCE = "UnitFrames/Engine/Elements/MSUF_UF_Prediction_Queue.lua"')
assert(count == 1, "native budget harness queue locator changed")
source, count = source:gsub("\nend\nlocal function QueuedFrames", '\n    error("prediction queue driver missing")\nend\nlocal function QueuedFrames')
assert(count == 1, "native budget harness drain changed")
local env = setmetatable({}, { __index = _G })
env.dofile = function(target)
    local result = dofile(target)
    if target == root .. "/tools/tests/health_tick_world.lua" then
        for _, name in ipairs({ "Layout", "Plans", "Queue" }) do
            result.OWNED[#result.OWNED + 1] =
                "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Prediction_" .. name .. ".lua"
        end
    end
    return result
end
local chunk = assert(loadstring(source, "@" .. path))
setfenv(chunk, env)
chunk()
