-- Execute the real cold apply/scheduler bodies with a deterministic native timer queue.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local start = assert(source:find("local function FlushLateAnchorReanchor(forcePosition)", 1, true))
local finish = assert(source:find('\nExportPublic("MSUF_ScheduleLateAnchorReanchor",', start, true))
local timers, exports, calls, errors = {}, {}, 0, {}
local ns = { UF = {} }
function ns.ExportPublic(name, value) exports[name] = value end
function ns.Optional(name) return exports[name] end
local combat, fail, requestInside, group = false, false, false, false
local schedule
local function Apply()
    calls = calls + 1
    if requestInside then schedule(true) end
    if fail then error("late anchor apply failure") end
end
local env = setmetatable({
    MSUF = ns, UF = ns.UF, ExportPublic = ns.ExportPublic,
    Factory = { Apply = Apply, ForceReanchor = Apply }, MSUF_DB = {},
    InCombat = function() return combat end,
    DeferLateAnchorReanchorForCombat = function() return false end,
    HasGroupLateAnchorConfig = function() return group end,
    Dep = function() return function() end end,
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end },
    geterrorhandler = function() return function(why) errors[#errors + 1] = why end end,
}, { __index = _G })
env._G = env
local boundary = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
setfenv(boundary, env)
boundary("MSUF", ns)
local chunk = assert(loadstring("local ScheduleLateAnchorReanchor\n" .. source:sub(start, finish - 1)
    .. "\nreturn ScheduleLateAnchorReanchor", "@" .. path))
setfenv(chunk, env)
schedule = chunk()
local function Tick()
    local timer = assert(table.remove(timers, 1), "missing scheduled late-anchor job")
    return pcall(timer[2])
end

assert(schedule() and #timers == 1)
assert(not schedule(true) and #timers == 1, "pending requests did not coalesce")
fail = true
local ok, why = Tick()
assert((not ok and why:find("late anchor apply failure", 1, true))
    or (#errors == 1 and errors[1]:find("late anchor apply failure", 1, true)), "apply error was hidden")
local state = assert(exports.MSUF_LateAnchorReanchorState)
assert(state.flushing ~= true, "failed apply permanently retained the flushing latch")
fail = false
assert(schedule() and #timers == 1, "request after failed apply scheduled zero jobs")
assert(Tick() and state.flushing ~= true and not state.pending)

-- Reentrant missing-anchor requests retain their bounded, force-upgrading retry series.
calls = 0
requestInside = true
assert(schedule())
local delays = { 0, 0.05, 0.15, 0.35, 0.75, 1.5 }
for index = 1, #delays do
    assert(#timers == 1 and timers[1][1] == delays[index], "retry delay/queue bound changed")
    assert(Tick())
end
assert(calls == #delays and #timers == 0 and not state.pending and not state.flushing,
    "reentrant apply escaped its bounded retry series")
calls = 0
fail = true
local errorsBefore = #errors
assert(schedule())
for index = 1, #delays do
    assert(#timers == 1 and timers[1][1] == delays[index])
    local ran, message = Tick()
    assert(ran or message:find("late anchor apply failure", 1, true))
    assert(not state.flushing, "reentrant failed apply retained its latch")
end
assert(calls == #delays and #timers == 0 and #errors == errorsBefore + #delays,
    "reentrant error lost its bounded retry or diagnostic")
fail = false
requestInside = false
assert(schedule() and Tick(), "fresh request after exhausted retry series failed")

-- Errors in later cold-apply stages use the same recovery boundary.
group = true
ns.GF = { RefreshHeaderLayout = function() error("late group apply failure") end }
assert(schedule() and Tick() and not state.flushing)
assert(errors[#errors]:find("late group apply failure", 1, true))
group = false
env.Dep = function() return function() error("late classpower apply failure") end end
assert(schedule() and Tick() and not state.flushing)
assert(errors[#errors]:find("late classpower apply failure", 1, true))
env.Dep = function() return function() end end
assert(schedule() and Tick(), "request after later-stage error failed")
combat = true
assert(not schedule() and #timers == 0, "combat request applied immediately")
print("PASS uf_late_anchor_writer_recovery")
