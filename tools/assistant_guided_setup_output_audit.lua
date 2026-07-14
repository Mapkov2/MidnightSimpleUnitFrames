_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")

local nativeActive, startCalls, resumeCalls = false, 0, 0
_G.MSUF_GuidedTour6 = {
    IsActive = function() return nativeActive end,
}
_G.MSUF_StartGuidedTour = function(opts)
    assert(type(opts) == "table" and tostring(opts.source or ""):find("assistant", 1, true), "native start missing Assistant source")
    nativeActive = true
    startCalls = startCalls + 1
    return true
end
_G.MSUF_ResumeGuidedTour = function()
    assert(nativeActive, "native resume called without an active tour")
    resumeCalls = resumeCalls + 1
    return true
end

local cases = 0
local function submit(input, expected)
    local parsed = A.Parse(input)
    if parsed and parsed.kind == "action" and parsed.action
        and (parsed.action.key == "guided_setup" or parsed.action.key == "guided_setup_step")
    then
        assert(next(parsed.args or {}) == nil,
            input .. ": native guided tour retained obsolete text-wizard arguments")
    end
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = result.status or result.result
    assert(status == "info" or status == "navigated" or status == "applied" or status == "unchanged",
        input .. ": expected native-tour result, got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assert(tostring(result.text or ""):find(expected, 1, true), input .. ": missing " .. expected .. ": " .. tostring(result.text or ""))
    assert(not tostring(result.text or ""):find("Goal:", 1, true), input .. ": legacy text wizard still visible")
    assert(not tostring(result.text or ""):find("Examples:", 1, true), input .. ": legacy text wizard examples still visible")
    local ctx = A.GetContext and A.GetContext()
    assert(not (type(ctx) == "table" and type(ctx.guidedSetup) == "table"), input .. ": legacy guidedSetup context recreated")
    cases = cases + 1
    return result
end

submit("start guided setup", "Opened the native MSUF guided setup")
assert(startCalls == 1 and resumeCalls == 0, "guided setup did not start the native tour exactly once")

submit("show setup", "Resumed the native MSUF guided setup")
assert(startCalls == 1 and resumeCalls == 1, "show setup must resume without resetting progress")

for _, input in ipairs({ "next setup step", "back setup step", "skip setup step", "cancel setup" }) do
    local parsed = A.Parse(input)
    assert(not (parsed and parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"),
        input .. ": legacy text-step command still routed")
end

nativeActive = false
submit("castbar setup guide", "Opened the native MSUF guided setup")
nativeActive = false
submit("profile setup guide", "Opened the native MSUF guided setup")
nativeActive = false
submit("help me setup group frames", "Opened the native MSUF guided setup")
nativeActive = false
submit("profil setup guide", "Opened the native MSUF guided setup")
nativeActive = false
submit("give me a checklist", "Opened the native MSUF guided setup")

assert(startCalls == 6, "all setup entry phrases must use the native tour")
io.write("assistant_guided_setup_output_audit: ok cases=" .. tostring(cases) .. " starts=" .. tostring(startCalls) .. " resumes=" .. tostring(resumeCalls) .. "\n")
