_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS.Assistant)
local parser = assert(A.Parser)
assert(parser._registryExactAliasIndex == nil, "exact-alias index unexpectedly warm before first request")

local started = os.clock()
local result = assert(A.SubmitDeferred("set hp color text"))
local elapsedMs = (os.clock() - started) * 1000

assert(result.status == "ambiguous", "bare HP text color request did not ask for a mode")
assert(A.IsBusy() == false, "bare HP text color clarification left the Assistant busy")
assert(parser._registryExactAliasIndex == nil, "bare HP text color request built the full exact-alias index")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices == 2, "HP text color clarification must offer exactly two choices")

local selected = assert(A.SubmitDeferred("single color"))
assert(selected.status == "applied" or selected.status == "unchanged", "single-color follow-up did not execute")

print(string.format("assistant_hp_text_color_coldpath_smoke: ok %.2fms choices=2 index=cold", elapsedMs))
