-- Execute the real replay with a throwing client error reporter.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"
local file = assert(io.open(arg[2] or path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local first = assert(source:find("local function FlushLateAnchorReanchor(forcePosition)", 1, true))
local last = assert(source:find('\nExportPublic("MSUF_ScheduleLateAnchorReanchor",', first, true))
local cases = 0
for _, phase in ipairs({ "apply", "classpower", "group" }) do
    for _, reentrant in ipairs({ false, true }) do
        local jobs, exports, failure, reports, schedule = {}, {}, phase, 0
        local ns = { UF = {} }
        ns.ExportPublic = function(name, value) exports[name] = value end
        ns.Optional = function(name) return exports[name] end
        local function Fail(at)
            if failure == at then error("injected " .. at) end
        end
        local function Apply()
            if reentrant and failure then schedule(true) end
            Fail("apply")
        end
        ns.GF = { RefreshHeaderLayout = function() Fail("group") end }
        local env = setmetatable({ MSUF = ns, UF = ns.UF, ExportPublic = ns.ExportPublic,
            Factory = { Apply = Apply, ForceReanchor = Apply }, MSUF_DB = {},
            InCombat = function() return false end,
            HasGroupLateAnchorConfig = function() return true end,
            Dep = function() return function() Fail("classpower") end end,
            C_Timer = { After = function(delay, callback) jobs[#jobs + 1] = { delay, callback } end },
            geterrorhandler = function() return function(why)
                assert(not exports.MSUF_LateAnchorReanchorState.flushing, "reporter observed the replay latch")
                assert(why:find("injected " .. phase, 1, true), "original failure diagnostic was lost")
                reports = reports + 1
                error("injected reporter")
            end end,
        }, { __index = _G })
        env._G = env
        local boundary = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
        setfenv(boundary, env)
        boundary("test", ns)
        local chunk = assert(loadstring("local ScheduleLateAnchorReanchor\n" .. source:sub(first, last - 1)
            .. "\nreturn ScheduleLateAnchorReanchor", "@" .. path))
        setfenv(chunk, env)
        schedule = chunk()
        assert(schedule() and #jobs == 1)
        local job = table.remove(jobs, 1)
        local ok, why = pcall(job[2])
        assert(reports == 1, "replay did not reach the reporter after restoring its latch")
        assert(not ok and tostring(why):find("injected reporter", 1, true), "reporter raise was hidden")
        local state = exports.MSUF_LateAnchorReanchorState
        assert(not state.flushing and not state.pending, "throwing reporter retained a replay latch")
        failure = nil
        assert(schedule() and #jobs == 1, "fresh request after reporter error scheduled zero jobs")
        assert(pcall(table.remove(jobs, 1)[2]) and not state.flushing and not state.pending and #jobs == 0)
        cases = cases + 1
    end
end
print("PASS uf_late_anchor_reporter_transaction: " .. cases .. " reporter failures and fresh requests")
