-- Runtime integration regressions through the actual client harness and providers.
local root = assert(arg[1], "repo root required")
local here = arg[0]:gsub("\\", "/"):match("^(.*)/") or "."
local cases = { "cast_a1", "cast_a2", "cast_a3", "cast_a4", "cast_a5" }
local failed = 0
for _, name in ipairs(cases) do
    local chunk = assert(loadfile(here .. "/bh3_runtime_cases/" .. name .. ".lua"))
    local env = setmetatable({arg={root,arg[2]}}, {__index=_G})
    env._G = env
    env.loadfile = function(path)
        local fn, why = loadfile(path)
        if fn then setfenv(fn, env) end
        return fn, why
    end
    env.dofile = function(path) return assert(env.loadfile(path))() end
    setfenv(chunk, env)
    local ok, message = pcall(chunk)
    if ok then print("PASS " .. name)
    else failed=failed+1; print("FAIL " .. name .. ": " .. tostring(message)) end
end
assert(failed == 0, failed .. " runtime integration cases failed")
