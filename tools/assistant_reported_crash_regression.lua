_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local function resultStatus(result)
    return result and (result.status or result.result)
end

local function assertDidNotRecover(label, result)
    local status = resultStatus(result)
    local output = tostring(result and result.text or "")
    local detail = A.lastAssistantJobError and (tostring(A.lastAssistantJobError.message or "")
        .. "\n" .. tostring(A.lastAssistantJobError.stack or "")) or ""
    assert(status ~= "failed", label .. ": failed: " .. output .. "\n" .. detail)
    assert(not output:find("couldn't finish a reliable answer", 1, true), label .. ": entered recovery: " .. output)
    assert(not output:find("could not finish a reliable answer", 1, true), label .. ": entered recovery: " .. output)
end

A.StartNewTask()
local shorten = assert(A.SubmitDeferred("shorten target name"))
assertDidNotRecover("shorten target name", shorten)
assert(resultStatus(shorten) == "ambiguous", "shorten target name should ask for length/direction")
assert(tostring(shorten.text):find("How many letters", 1, true), "shorten target name lost its specific clarification")
assert(A.IsBusy() == false, "shorten target name left Assistant busy")

A.StartNewTask()
local layer = assert(Registry:GetSetting("gf_party.nameTextLayer"), "Party Name Text Layer missing")
local initial = tonumber(layer.get()) or 0
local first = assert(A.SubmitDeferred("increase name strata for party"))
assertDidNotRecover("increase name strata for party", first)
assert(resultStatus(first) == "applied" or resultStatus(first) == "unchanged", "first layer request did not execute")
local afterFirst = tonumber(layer.get()) or initial
assert(afterFirst > initial, "first layer request did not increase Party Name Text Layer")

local more = assert(A.SubmitDeferred("more"))
assertDidNotRecover("more after Party Name Text Layer", more)
assert(resultStatus(more) == "applied", "more follow-up did not apply: " .. tostring(more.text))
assert((tonumber(layer.get()) or afterFirst) > afterFirst, "more did not repeat the layer increase")
assert(A.IsBusy() == false, "more follow-up left Assistant busy")

print("assistant_reported_crash_regression: ok")
