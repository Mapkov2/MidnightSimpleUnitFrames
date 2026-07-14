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
local writableSettings = count("Generated writable setting cases")
local readOnlySettings = count("Generated read-only getter + fail-closed probes")
local uncoveredSettings = count("Settings without executable/reviewed coverage")
local actions = count("Registry actions loaded")
local conversationalActions = count("Generated conversational action cases")
local reviewedActions = count("Reviewed non-conversational action contracts")
local uncoveredActions = count("Actions without executable/reviewed coverage")
local actionProbes = count("Action explanation probes")

assert(total > 0 and passed == total,
    string.format("V1 training did not pass completely: %d/%d", passed, total))
for _, label in ipairs({
    "Gate failures",
    "Parser/public case failures",
    "Action explanation failures",
    "Runtime transaction smoke failures",
    "Read-only setting contract failures",
    "Non-conversational action contract failures",
    "Coverage inventory contract failures",
    "Assistant file load misses",
}) do
    assert(count(label) == 0, "V1 training reported nonzero " .. label)
end

-- Counts legitimately change when controls are added or raw fallback mirrors
-- are assigned to canonical owners. Enforce conservation instead of blessing a
-- stale magic number: every loaded setting/action must have executable or
-- explicitly reviewed coverage, and every action must receive the
-- ambiguity/safety explanation probe.
assert(settings >= 4500, "V1 registry setting inventory collapsed: " .. settings)
assert(actions >= 171, "V1 registry action inventory collapsed: " .. actions)
assert(uncoveredSettings == 0, "V1 settings remain uncovered: " .. uncoveredSettings)
assert(uncoveredActions == 0, "V1 actions remain uncovered: " .. uncoveredActions)
assert(writableSettings + readOnlySettings == settings,
    string.format("setting coverage conservation failed: %d + %d ~= %d",
        writableSettings, readOnlySettings, settings))
assert(conversationalActions + reviewedActions == actions,
    string.format("action coverage conservation failed: %d + %d ~= %d",
        conversationalActions, reviewedActions, actions))
assert(actionProbes == actions,
    string.format("action explanation parity failed: %d probes for %d actions", actionProbes, actions))
assert(count("Public path smoke cases") >= 9, "public path smoke inventory collapsed")

print(string.format(
    "assistant_v1_training_oracle: ok %d/%d settings=%d (%d writable, %d reviewed read-only) actions=%d (%d conversational, %d reviewed) loadMisses=0",
    passed, total, settings, writableSettings, readOnlySettings, actions, conversationalActions, reviewedActions))
