local path = (arg and arg[1]) or "tools/AssistantTraining/out/report.md"
local handle = assert(io.open(path, "rb"), "missing full-training report: " .. path)
local report = handle:read("*a") or ""
handle:close()

local function count(label)
    local actual = report:match("%- " .. label:gsub("([^%w])", "%%%1") .. ": (%d+)")
    return assert(tonumber(actual), "V1 training report omitted " .. label)
end

local total = count("Total gate checks")
local passed = count("Passed")
local settings = count("Registry settings loaded")
local generatedSettings = count("Generated setting cases")
local ungeneratedSettings = count("Settings without generated case")
local actions = count("Registry actions loaded")
local generatedActions = count("Generated action cases")
local ungeneratedActions = count("Actions without generated case")
local actionProbes = count("Action explanation probes")

assert(total > 0 and passed == total,
    string.format("V1 training did not pass completely: %d/%d", passed, total))
for _, label in ipairs({
    "Gate failures",
    "Parser/public case failures",
    "Action explanation failures",
    "Runtime transaction smoke failures",
    "Assistant file load misses",
}) do
    assert(count(label) == 0, "V1 training reported nonzero " .. label)
end

-- Counts legitimately change when controls are added or raw fallback mirrors
-- are assigned to canonical owners. Enforce conservation instead of blessing a
-- stale magic number: every loaded setting/action must be either generated as
-- a case or explicitly reported as lacking a generated case, and every action
-- must receive the ambiguity/safety explanation probe.
assert(settings >= 4500, "V1 registry setting inventory collapsed: " .. settings)
assert(actions >= 171, "V1 registry action inventory collapsed: " .. actions)
assert(generatedSettings + ungeneratedSettings == settings,
    string.format("setting case conservation failed: %d + %d ~= %d",
        generatedSettings, ungeneratedSettings, settings))
assert(generatedActions + ungeneratedActions == actions,
    string.format("action case conservation failed: %d + %d ~= %d",
        generatedActions, ungeneratedActions, actions))
assert(actionProbes == actions,
    string.format("action explanation parity failed: %d probes for %d actions", actionProbes, actions))
assert(count("Public path smoke cases") >= 9, "public path smoke inventory collapsed")

print(string.format(
    "assistant_v1_training_oracle: ok %d/%d settings=%d (%d generated, %d classified) actions=%d loadMisses=0",
    passed, total, settings, generatedSettings, ungeneratedSettings, actions))
