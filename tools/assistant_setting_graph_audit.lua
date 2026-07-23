_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)

local dashboardSmoke = "tools/assistant_dashboard_smoke.lua"
if not exists(dashboardSmoke) then dashboardSmoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(dashboardSmoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local G = assert(A.SettingGraph, "Assistant setting graph missing")
local D = assert(A.SettingGraphData, "Assistant setting graph data missing")

assert(G.IsBuilt() == false, "graph performed eager work during addon/menu script loading")
local started = os.clock()
local report, reportError = G.GetCoverageReport()
assert(report, reportError)
local buildMs = (os.clock() - started) * 1000

assert(report.settings >= 4000, "registry coverage baseline unexpectedly shrank")
assert(report.edges >= 4000 and report.edges <= 10000, "edge count is outside the reviewed performance envelope")
assert(report.coveragePercent >= 70, "related-setting coverage fell below 70 percent")
-- The Beta 26 AutoCoverage manifest intentionally adds persisted scalar
-- fallbacks that are page-related but do not invent feature-specific edges.
assert(report.specificCoveragePercent >= 67, "evidence-backed specific relationship coverage fell below 67 percent")
assert((report.pageResolvableCoveragePercent or 0) >= 99, "page-resolvable relationship coverage fell below 99 percent")
assert(report.pageResolvableClassifiedSettings == report.pageResolvableSettings,
    "not every page-resolvable setting is related or explicitly intentional-standalone")
assert((report.pageResolvableClassificationPercent or 0) == 100,
    "page-resolvable setting classification is not 100 percent")
assert(report.userFacingClassifiedSettings == report.userFacingSettings,
    "not every user-facing setting is related or explicitly intentional-standalone")
assert((report.userFacingClassificationPercent or 0) == 100,
    "user-facing setting classification is not 100 percent")
assert(#(report.unclassifiedStandalonePageResolvableSettings or {}) == 0,
    "page-resolvable settings remain unclassified")
assert(#report.unresolved == 0, "graph contains unresolved relation endpoints")
for _, kind in ipairs({ "enablement", "visibility", "availability", "requires", "inheritance", "override", "conflict", "association" }) do
    assert((report.byKind[kind] or 0) > 0, "missing relation kind: " .. kind)
end
assert(buildMs <= 250, ("cold graph build exceeded 250 ms: %.2f ms"):format(buildMs))

local validation, validationError = G.Validate()
assert(validation, validationError)
assert(validation.ok, "graph validation failed: " .. table.concat(validation.errors or {}, "; "))
assert(#validation.cycles == 0, "dependency graph contains cycles")

local intentional = report.intentionalStandalonePageResolvableSettings or {}
assert(#intentional == 1, "reviewed intentional-standalone setting count changed")
local specStandalone = intentional[1]
assert(specStandalone.key == "profiles.specAutoSwitch", "unexpected intentional-standalone setting")
assert(specStandalone.classification == "intentional-standalone-with-action-dependency",
    "spec auto-switch standalone classification changed")
assert(type(specStandalone.reason) == "string" and specStandalone.reason ~= "",
    "spec auto-switch standalone classification has no reason")
assert(type(specStandalone.evidence) == "string" and specStandalone.evidence ~= "",
    "spec auto-switch standalone classification has no evidence")
local expectedActions = { clear_spec_profile = true, set_spec_profile = true }
assert(type(specStandalone.actionKeys) == "table" and #specStandalone.actionKeys == 2,
    "spec auto-switch action dependencies changed")
for _, actionKey in ipairs(specStandalone.actionKeys) do
    assert(expectedActions[actionKey], "unexpected spec auto-switch action dependency: " .. tostring(actionKey))
    assert(A.Registry:GetAction(actionKey), "missing spec auto-switch action dependency: " .. tostring(actionKey))
    expectedActions[actionKey] = nil
end
assert(next(expectedActions) == nil, "spec auto-switch action dependency coverage is incomplete")

-- Every generated relation must be evidence-backed and use a reviewed kind.
for _, edge in ipairs((G._state and G._state.edges) or {}) do
    assert(D.relationKinds[edge.kind], "unreviewed relation kind: " .. tostring(edge.kind))
    assert(type(edge.evidence) == "string" and edge.evidence ~= "", "relation lacks evidence: " .. tostring(edge.ruleId))
    assert(type(edge.reason) == "string" and edge.reason ~= "", "relation lacks human explanation: " .. tostring(edge.ruleId))
end

local function checkEvidence(rules, label)
    for index, rule in ipairs(rules or {}) do
        assert(type(rule.id) == "string" and rule.id ~= "", label .. " rule " .. index .. " has no stable id")
        assert(type(rule.evidence) == "string" and rule.evidence ~= "", label .. " rule " .. tostring(rule.id) .. " has no evidence")
    end
end
checkEvidence(D.scopeRootRules, "scope root")
checkEvidence(D.patternGateRules, "pattern gate")
checkEvidence(D.scopedFieldGateRules, "scoped field gate")
checkEvidence(D.prefixGateRules, "prefix gate")
checkEvidence(D.featureGateRules, "feature gate")
checkEvidence(D.requiresEdges, "requires")
checkEvidence(D.scopedAssociationRules, "scoped association")
checkEvidence(D.scopedInheritanceRules, "scoped inheritance")
checkEvidence(D.conflictProviders, "conflict provider")

for key, record in pairs(D.intentionalStandaloneSettings or {}) do
    assert(type(record) == "table", "intentional standalone " .. tostring(key) .. " is not a record")
    assert(type(record.classification) == "string" and record.classification ~= "",
        "intentional standalone " .. tostring(key) .. " has no classification")
    assert(type(record.reason) == "string" and record.reason ~= "",
        "intentional standalone " .. tostring(key) .. " has no reason")
    assert(type(record.evidence) == "string" and record.evidence ~= "",
        "intentional standalone " .. tostring(key) .. " has no evidence")
    assert(type(record.actionKeys) == "table" and #record.actionKeys > 0,
        "intentional standalone " .. tostring(key) .. " has no action dependency")
end

-- Rebuilding the same registry must produce exactly the same graph summary.
local function signature(value)
    local parts = {
        tostring(value.settings), tostring(value.relatedSettings), tostring(value.edges),
        tostring(#(value.unresolved or {})), tostring(value.pageResolvableClassifiedSettings),
        tostring(#(value.intentionalStandalonePageResolvableSettings or {})),
        tostring(#(value.unclassifiedStandalonePageResolvableSettings or {})),
    }
    local kinds = {}
    for kind, count in pairs(value.byKind or {}) do kinds[#kinds + 1] = kind .. "=" .. tostring(count) end
    table.sort(kinds)
    parts[#parts + 1] = table.concat(kinds, ",")
    local hits = {}
    for rule, count in pairs(value.ruleHits or {}) do hits[#hits + 1] = rule .. "=" .. tostring(count) end
    table.sort(hits)
    parts[#parts + 1] = table.concat(hits, ",")
    return table.concat(parts, "|")
end
local firstSignature = signature(report)
local function edgeSignature()
    local values = {}
    for _, edge in ipairs((G._state and G._state.edges) or {}) do
        values[#values + 1] = table.concat({ tostring(edge.kind), tostring(edge.from), tostring(edge.to), tostring(edge.ruleId) }, "\031")
    end
    table.sort(values)
    return table.concat(values, "\030")
end
local directEdges = edgeSignature()
G.Invalidate()
local rebuilt, rebuiltError = G.GetCoverageReport()
assert(rebuilt, rebuiltError)
assert(signature(rebuilt) == firstSignature, "graph summary changed across deterministic rebuild")
assert(edgeSignature() == directEdges, "direct graph edge identities changed across deterministic rebuild")

-- Querying a narrow Aura domain, then base, then full coverage must converge
-- to exactly the same graph as a direct complete build.
G.Invalidate()
assert(G.GetNode("auras3.target.buff.visible"))
assert(G.GetNode("player.nameFontSize"))
local lazyReport, lazyError = G.GetCoverageReport()
assert(lazyReport, lazyError)
assert(signature(lazyReport) == firstSignature, "lazy graph path produced a different summary")
assert(edgeSignature() == directEdges, "lazy graph path produced different edge identities")

-- Static zero-background-work gate.  The graph may only run synchronously in
-- response to an explicit API call and must never install a WoW callback.
local assistantRoot = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/"
local graphSource = assert(io.open(assistantRoot .. "MSUF_AssistantSettingGraph.lua", "r")):read("*a")
local backgroundTokens = {
    "CreateFrame", "SetScript", "RegisterEvent", "OnUpdate", "C_Timer", "NewTicker",
    "ScheduleOnce", "hooksecurefunc", "PLAYER_REGEN", "ADDON_LOADED",
}
for _, token in ipairs(backgroundTokens) do
    assert(not graphSource:find(token, 1, true), "graph installs or references forbidden background work: " .. token)
end
assert(graphSource:find("IsCombatBlocked", 1, true), "graph has no combat fail-closed guard")

local runtimeEntries = RuntimeManifest.ReadRuntimeEntries()
local dataAt, graphAt
for index, entry in ipairs(runtimeEntries) do
    if entry.relative == "Assistant/MSUF_AssistantSettingGraph_Data.lua" then dataAt = index end
    if entry.relative == "Assistant/MSUF_AssistantSettingGraph.lua" then graphAt = index end
end
assert(dataAt, "graph data load line missing")
assert(graphAt, "graph engine load line missing")
assert(dataAt < graphAt, "graph data must load before graph engine")

io.write(("assistant_setting_graph_audit: ok settings=%d related=%d edges=%d coverage=%.2f%% page_classified=%d/%d intentional_standalone=%d build=%.2fms\n")
    :format(report.settings, report.relatedSettings, report.edges, report.coveragePercent,
        report.pageResolvableClassifiedSettings, report.pageResolvableSettings,
        #intentional, buildMs))
