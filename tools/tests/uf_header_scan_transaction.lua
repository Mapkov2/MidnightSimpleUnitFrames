-- Real header walk and event-batch helpers; deterministic aura nesting and faults.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local core = Read(arg[3] or root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua"
local source = Read(arg[2] or path)
local first = assert(source:find("local function ScanOneChild(", 1, true))
local last = assert(source:find("\nfunction GF.ForEachFrame(", first, true))
local batchFirst = assert(core:find("function UF.BeginEventRegistrationBatch(", 1, true))
local batchLast = assert(core:find("\nMSUF.UnitFrames = UF", batchFirst, true))
local cases = 0
for _, phase in ipairs({ "walk", "children", "hook", "pixel", "unit", "suspend", "apply", "aura-end", "driver", "none" }) do
    for _, held in ipairs({ "nil", "false", "true" }) do
        for _, throws in ipairs({ false, true }) do
            if held ~= "true" or phase ~= "driver" then
                local old = held == "true" and true or nil
                if held == "false" then old = false end
                local failure, reports, begins, ends, syncs = phase, 0, 0, 0, 0
                local depth, initialDepth = held == "true" and 2 or 0, held == "true" and 2 or 0
                local UF, GF = { _msufApplyingSpec = old }, {}
                local function Fail(at)
                    if failure == at then error("injected " .. at) end
                end
                local function Restored()
                    assert(begins == ends, phase .. ": aura begin/end calls are unbalanced (" .. begins .. "/" .. ends .. ")")
                    assert(UF._msufApplyingSpec == old, phase .. ": global apply flag leaked (" .. held .. ")")
                    assert(depth == initialDepth, phase .. ": aura topology batch leaked")
                end
                local child = { GetAttribute = function() Fail("unit"); return failure ~= "suspend" and "party1" or nil end }
                local header = { GetChildren = function() Fail("children"); return child, child end }
                GF.ForEachHeader = function(_, visit) Fail("walk"); visit(header); visit(header) end
                GF.ApplyButton = function() Fail("apply"); return true end
                UF.SyncRuntimeDriver = function() Fail("driver"); syncs = syncs + 1 end
                local ns = { ExportPublic = function() end, MSUF_Auras3 = {
                    BeginTopologyBatch = function() depth = depth + 1; begins = begins + 1 end,
                    EndTopologyBatch = function() depth = depth - 1; ends = ends + 1; Fail("aura-end") end,
                } }
                local env = setmetatable({ UF = UF, GF = GF, MSUF = ns,
                    InstallChildAttrHook = function() Fail("hook") end,
                    PixelLayoutRegion = function() Fail("pixel") end,
                    IsUnitToken = function(unit) return type(unit) == "string" end,
                    SuspendUnitBinding = function() Fail("suspend") end,
                    geterrorhandler = function() return function()
                        Restored()
                        reports = reports + 1
                        if throws then error("injected reporter") end
                    end end,
                }, { __index = _G })
                env._G = env
                local boundary = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
                setfenv(boundary, env)
                boundary("test", ns)
                for _, body in ipairs({ core:sub(batchFirst, batchLast - 1), source:sub(first, last - 1) }) do
                    local chunk = assert(loadstring(body, "@" .. path))
                    setfenv(chunk, env)
                    chunk()
                end
                local ok, found = pcall(GF.ScanHeader, "party", "party")
                Restored()
                if phase == "none" then
                    assert(ok and found == true and reports == 0, "successful scan lost its found result")
                elseif throws then
                    assert(not ok and tostring(found):find("injected reporter", 1, true), "reporter raise was hidden")
                else
                    assert(ok and found == false and reports == 1, "failed scan did not return false/report once")
                end
                failure = nil
                assert(GF.ScanHeader("party", "party"), "failed scan prevented the next scan")
                Restored()
                -- Legacy single-header fallback and clients with no aura provider.
                GF.ForEachHeader, GF.headers, ns.MSUF_Auras3 = nil, { party = header }, nil
                assert(GF.ScanHeader("party", "party"), "single-header/no-aura scan changed")
                assert(not GF.ScanHeader("missing", "party"), "empty scan reported a child")
                Restored()
                local expectedSyncs = (phase == "aura-end" or phase == "driver") and 3 or 4
                assert(syncs == (old == true and 0 or expectedSyncs), "scan runtime-driver sync count changed")
                -- Reentrant scans must close only their own aura and registration batches.
                local entered = false
                ns.MSUF_Auras3 = {
                    BeginTopologyBatch = function() depth = depth + 1; begins = begins + 1 end,
                    EndTopologyBatch = function() depth = depth - 1; ends = ends + 1 end,
                }
                GF.ApplyButton = function()
                    if not entered then
                        entered = true
                        assert(GF.ScanHeader("party", "party"))
                        assert(UF._msufApplyingSpec == true and depth == initialDepth + 1,
                            "inner scan cleared the outer transaction")
                    end
                    return true
                end
                assert(GF.ScanHeader("party", "party"))
                Restored()
                assert(syncs == (old == true and 0 or expectedSyncs + 1), "nested scan synced the driver prematurely")
                cases = cases + 1
            end
        end
    end
end
print("PASS uf_header_scan_transaction: " .. cases .. " failure/nesting/reporter cases; retry and client fallback")
