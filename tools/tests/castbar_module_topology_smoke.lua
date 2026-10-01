-- castbar_module_topology_smoke.lua <repoRoot>
--
-- Load-graph and reachability contracts of the castbar modules:
--   * MSUF_CastbarNativeTimer.lua is a dead 12.1 PTR spike: nothing in any
--     addon calls MSUF.CastbarNativeTimer and its setting is never written, so
--     no Classic flavor loads it (tools/classic-flavor-load-exclusions.tsv).
--     Mainline keeps it only to hold Retail's load order. Wiring it up again
--     means loading it again, and this smoke says so.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return source
end

local function Tracked()
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "*.lua" "*.xml"'))
    local files = {}
    for line in pipe:lines() do files[#files + 1] = line end
    pipe:close()
    assert(#files > 100, "git ls-files returned too few addon files")
    return files
end

local NATIVE_TIMER = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarNativeTimer.lua"

-- 1. No caller anywhere.
for _, relative in ipairs(Tracked()) do
    if relative ~= NATIVE_TIMER and relative:match("^MidnightSimpleUnitFrames") then
        local source = Read(root .. "/" .. relative)
        assert(not source:find("CastbarNativeTimer", 1, true) and not source:find("castbarNativeTimer", 1, true),
            relative .. " reaches MSUF.CastbarNativeTimer: load the module on every client again "
            .. "(TOCs and tools/classic-flavor-load-exclusions.tsv) before wiring it")
    end
end

-- 2. No Classic flavor loads it.
for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    for _, path in ipairs(manifest.Paths(root, flavor)) do
        assert(not path:find("MSUF_CastbarNativeTimer.lua", 1, true),
            flavor .. " still loads the dead native-timer spike")
    end
end

print("castbar_module_topology_smoke: ok (native-timer spike unreachable and unloaded on Classic)")
