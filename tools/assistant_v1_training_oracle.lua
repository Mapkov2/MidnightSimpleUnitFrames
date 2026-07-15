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
local autoCoverageFallbacks = count("AutoCoverage fallbacks filled")
local writableSettings = count("Generated writable setting cases")
local readOnlySettings = count("Generated read-only getter + fail-closed probes")
local uncoveredSettings = count("Settings without executable/reviewed coverage")
local actions = count("Registry actions loaded")
local conversationalActions = count("Generated conversational action cases")
local reviewedActions = count("Reviewed non-conversational action contracts")
local uncoveredActions = count("Actions without executable/reviewed coverage")
local actionProbes = count("Action explanation probes")

-- A report can be internally perfect and still describe an older Registry.
-- Rebuild the same headless runtime inventory used by AssistantTraining and
-- compare it directly before accepting any stored snapshot. This deliberately
-- avoids branch-sensitive magic counts while failing closed when a setting or
-- action is added without rerunning the complete training harness.
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")
Loader.AssertRegistryInventoryFingerprintContract()
Loader.LoadAssistantRuntime(_G.MSUF_NS, {
    includeDashboard = false,
    includeDialogLocale = false,
})
local liveAssistant = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant,
    "live Assistant runtime did not load for training freshness")
local liveAutoCoverage = assert(liveAssistant.AutoCoverage,
    "live AutoCoverage table is unavailable for training freshness")
assert(type(liveAutoCoverage.Fill) == "function",
    "live AutoCoverage fill is unavailable for training freshness")
local liveAutoCoverageFallbacks = tonumber(liveAutoCoverage.Fill()) or 0
local liveRegistry = assert(liveAssistant.Registry, "live Registry is unavailable for training freshness")
local liveSettings = #(assert(liveRegistry.AllSettings and liveRegistry:AllSettings(),
    "live Registry settings inventory is unavailable"))
local liveActions = #(assert(liveRegistry.AllActions and liveRegistry:AllActions(),
    "live Registry actions inventory is unavailable"))

assert(settings == liveSettings,
    string.format("V1 training report is stale: report settings=%d live settings=%d; rerun the complete training harness",
        settings, liveSettings))
assert(actions == liveActions,
    string.format("V1 training report is stale: report actions=%d live actions=%d; rerun the complete training harness",
        actions, liveActions))
assert(autoCoverageFallbacks == liveAutoCoverageFallbacks,
    string.format("V1 training report is stale: report AutoCoverage=%d live AutoCoverage=%d; rerun the complete training harness",
        autoCoverageFallbacks, liveAutoCoverageFallbacks))
local reportKeyFingerprint = assert(report:match("%- Registry key fingerprint: ([%w%-]+)"),
    "V1 training report omitted Registry key fingerprint; rerun the complete training harness")
local liveKeyFingerprint = Loader.RegistryInventoryFingerprint(liveRegistry)
assert(reportKeyFingerprint == liveKeyFingerprint,
    string.format("V1 training report is stale: report Registry fingerprint=%s live fingerprint=%s; rerun the complete training harness",
        reportKeyFingerprint, liveKeyFingerprint))

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
    "assistant_v1_training_oracle: ok %d/%d settings=%d (%d writable, %d reviewed read-only) actions=%d (%d conversational, %d reviewed) fingerprint=%s loadMisses=0",
    passed, total, settings, writableSettings, readOnlySettings, actions, conversationalActions, reviewedActions,
    reportKeyFingerprint))
