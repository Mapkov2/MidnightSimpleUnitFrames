-- castbar_module_topology_smoke.lua <repoRoot>
--
-- Load-graph and reachability contracts of the castbar modules:
--   * MSUF_CastbarNativeTimer.lua was a dead 12.1 PTR spike (nothing called
--     MSUF.CastbarNativeTimer and its setting was never written) and is gone:
--     the file stays deleted and no addon file may reach it again. Runtime
--     owns native castbar timing.
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

-- 1. The file is gone and nothing reaches it.
for _, relative in ipairs(Tracked()) do
    assert(relative ~= NATIVE_TIMER, "the dead native-timer spike is tracked again: " .. relative)
    if relative:match("^MidnightSimpleUnitFrames") then
        local source = Read(root .. "/" .. relative)
        assert(not source:find("CastbarNativeTimer", 1, true) and not source:find("castbarNativeTimer", 1, true),
            relative .. " reaches MSUF.CastbarNativeTimer, which no longer exists")
    end
end

-- 2. No client loads it.
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
    for _, path in ipairs(manifest.Paths(root, flavor)) do
        assert(not path:find("MSUF_CastbarNativeTimer.lua", 1, true),
            flavor .. " still loads the dead native-timer spike")
    end
end

print("castbar_module_topology_smoke: ok (native-timer spike removed and unreferenced)")
