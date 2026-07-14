_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = {},
    focus = {},
    pet = {},
    targettarget = {},
    focustarget = {},
    boss = {},
    gf_party = {},
    gf_raid = {},
    gf_mythicraid = {},
    auras3 = { shared = { showInEditMode = true } },
}
_G.MSUF_GlobalDB = { global = {} }
_G.GetLocale = function() return "enUS" end
_G.GetServerTime = function() return 123456 end

local combat = false
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function(unit) return unit == "player" and combat or false end

local runtimeLoaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(runtimeLoaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.RecordNoMatch) == "function", "RecordNoMatch missing")
assert(type(A.GetNoMatchReview) == "function", "GetNoMatchReview missing")
assert(type(A.NoMatchTelemetryText) == "function", "NoMatchTelemetryText missing")
assert(type(A.NoMatchWorklistText) == "function", "NoMatchWorklistText missing")
assert(type(A.ClearNoMatchTelemetry) == "function", "ClearNoMatchTelemetry missing")
A.GetContext = A.GetContext or function() return {} end

local function contains(text, needle, plain)
    return tostring(text or ""):find(tostring(needle or ""), 1, plain ~= false) ~= nil
end

local function record(text, times)
    local last
    for _ = 1, times or 1 do
        last = A.RecordNoMatch(text, { status = "failed" }, "audit")
        assert(type(last) == "table", "RecordNoMatch failed for " .. tostring(text))
    end
    return last
end

combat = true
local blocked = A.RecordNoMatch("combat should not write telemetry", { status = "failed" }, "audit")
assert(blocked == nil, "RecordNoMatch wrote telemetry while combat locked")
assert(_G.MSUF_GlobalDB.global.assistantNoMatch == nil, "NoMatch store was created in combat")
combat = false

local registryMiss = record("target mystery texture color", 5)
local anchorMiss = record("anchor minimap to cooldownmanager", 2)
local geometryMiss = record("move target frame sideways", 2)
local resolvedAuraMiss = record("set aura editing scope to target", 1)
local genericMiss = record("flibbertigibbet", 1)

assert(registryMiss.count == 5, "registry-like miss did not aggregate count")
assert(registryMiss.owner == "registry-alias", "registry-like miss owner mismatch: " .. tostring(registryMiss.owner))
assert(registryMiss.priority == "high", "registry-like miss was not high priority")
assert(contains(registryMiss.tags, "media"), "registry-like miss missing media tag")
assert(contains(registryMiss.tags, "setting"), "registry-like miss missing setting tag")
assert(contains(registryMiss.registryCandidates, "barScope.target.", true), "registry-like miss missing concrete registry candidates")
assert(contains(registryMiss.learningPlan, "add a setting alias or clearer setting wording", true), "registry-like miss missing registry learning plan")

assert(anchorMiss.owner == "anchor-intent", "anchor miss owner mismatch")
assert(anchorMiss.priority == "medium", "anchor miss was not medium priority")
assert(contains(anchorMiss.tags, "anchor"), "anchor miss missing anchor tag")
assert(contains(anchorMiss.learningPlan, "add anchor wording", true), "anchor miss missing anchor learning plan")

assert(contains(geometryMiss.tags, "geometry"), "geometry miss missing geometry tag")
assert(genericMiss.owner == "parser-or-help", "generic miss owner mismatch")
assert(genericMiss.tags == "uncategorized", "generic miss should stay uncategorized")

assert(resolvedAuraMiss.resolution == "resolved", "resolved historical miss did not resolve")
assert(resolvedAuraMiss.resolvedBy == "menu.auraScope", "resolved historical miss has wrong resolver: " .. tostring(resolvedAuraMiss.resolvedBy))
assert(contains(resolvedAuraMiss.learningPlan, "Aura", true), "Aura miss missing Aura learning plan")

local telemetryText = A.NoMatchTelemetryText(12)
assert(contains(telemetryText, "Assistant wording to improve:", true), "telemetry text missing title")
assert(contains(telemetryText, "How to improve them:", true), "telemetry text missing learning hints")
assert(contains(telemetryText, "Phrases to improve:", true), "telemetry text missing review candidates")
assert(not contains(telemetryText, "target mystery texture color", true), "telemetry text repeated raw registry phrase")
assert(contains(telemetryText, "[high] phrase #", true), "telemetry text missing sanitized high priority")
assert(contains(telemetryText, "result: resolved", true), "telemetry text missing resolved state")
assert(contains(telemetryText, "now handled by: menu.auraScope", true), "telemetry text missing resolver")

local worklistText = A.NoMatchWorklistText(20)
assert(contains(worklistText, "Assistant wording to improve:", true), "worklist text missing title")
assert(contains(worklistText, "Phrases to improve:", true), "worklist text missing priority queue")
assert(contains(worklistText, "Improvement plan:", true), "worklist text missing alias plan")
assert(contains(worklistText, "Start with high and medium phrases first.", true), "worklist text missing TSV section")
assert(contains(worklistText, "best improvement", true), "worklist TSV header incomplete")
if not contains(worklistText, "[high] phrase #", true) then
    io.stderr:write(worklistText .. "\n")
    assert(false, "worklist did not prioritize repeated registry miss with a sanitized phrase reference")
end

local registryReview = A.GetNoMatchReview(20, "registry-alias")
assert(registryReview.total >= 1, "registry review filter returned no entries")
assert(registryReview.items[1] and registryReview.items[1].text == "target mystery texture color", "registry review filter picked wrong item")
local anchorReview = A.GetNoMatchReview(20, "anchor-intent")
assert(anchorReview.total >= 1 and anchorReview.items[1].text == "anchor minimap to cooldownmanager", "anchor review filter failed")
local highReview = A.GetNoMatchReview(20, nil, nil, "high")
assert(highReview.total >= 1 and highReview.items[1].text == "target mystery texture color", "high priority review filter failed")
local mediumReview = A.GetNoMatchReview(20, nil, nil, "medium")
assert(mediumReview.total >= 1 and mediumReview.items[1].text == "anchor minimap to cooldownmanager", "medium priority review filter failed")
local geometryReview = A.GetNoMatchReview(20, nil, nil, nil, "geometry")
local foundGeometry = false
for _, item in ipairs(geometryReview.items or {}) do
    if item.text == "move target frame sideways" then foundGeometry = true end
    assert(item.text ~= "anchor minimap to cooldownmanager", "geometry tag review included anchor-only miss")
end
assert(foundGeometry, "geometry tag review did not include geometry miss")
local resolvedReview = A.GetNoMatchReview(20, nil, "resolved")
assert(resolvedReview.total >= 1 and resolvedReview.items[1].text == "set aura editing scope to target", "resolved review filter failed")
local unresolvedReview = A.GetNoMatchReview(20, nil, "unresolved")
for _, item in ipairs(unresolvedReview.items or {}) do
    assert(item.text ~= "set aura editing scope to target", "unresolved review included resolved miss")
end

local cleared = A.ClearNoMatchTelemetry()
assert(cleared == 11, "clear returned wrong telemetry count: " .. tostring(cleared))
assert(contains(A.NoMatchTelemetryText(5), "I haven't missed any Assistant requests yet.", true), "telemetry clear did not empty report")

io.write(string.format(
    "assistant_nomatch_learning_audit: ok total=%d registry=%d anchor=%d resolved=%d\n",
    cleared,
    #(registryReview.items or {}),
    #(anchorReview.items or {}),
    #(resolvedReview.items or {})
))
