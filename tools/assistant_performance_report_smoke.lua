_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close() return true end
    return false
end

_G.date = _G.date or os.date
_G.debugprofilestop = function() error("Assistant called debugprofilestop") end
_G.Enum = {
    AddOnProfilerMetric = setmetatable({}, {
        __index = function() error("Assistant read AddOnProfilerMetric") end,
    }),
}
_G.C_AddOnProfiler = setmetatable({}, {
    __index = function(_, key) error("Assistant accessed C_AddOnProfiler." .. tostring(key)) end,
})

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { general = {}, bars = {}, gameplay = {} }

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local assistantRoot = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/"
for _, file in ipairs({ "MSUF_Assistant.lua", "MSUF_AssistantAudit.lua" }) do
    local chunk, err = loadfile(assistantRoot .. file)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames_Assistant", MSUF)
end

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local Audit = assert(A.CoverageAudit, "Assistant coverage audit missing")

for _, api in ipairs({
    "RecordPerfSample", "RecordSlowPerfSample", "GetLastPerfSample", "GetLastSlowPerfSample",
    "GetPerfTrace", "ClearPerfTrace", "PerformanceWarmupStatusText",
}) do
    assert(A[api] == nil, "removed built-in profiler API returned: " .. api)
end
assert(A._perfTrace == nil and A.lastAssistantPerf == nil and A.lastSlowAssistantPerf == nil,
    "removed built-in profiler state returned")
assert(Audit.BuildPerformanceReport == nil, "removed performance report returned")

local requiredCases = {
    runtime_core_load = false,
    interactive_read_only = false,
    idle_assistant_shutdown = false,
}
for i = 1, #(Audit.AcceptanceSmokeCases or {}) do
    local id = Audit.AcceptanceSmokeCases[i].id
    if requiredCases[id] ~= nil then requiredCases[id] = true end
    assert(id ~= "interactive_latency", "removed profiler acceptance case returned")
end
for id, found in pairs(requiredCases) do assert(found, "missing acceptance case: " .. id) end

print("assistant_performance_report_smoke: ok no-built-in-profiler acceptanceCases=3")
