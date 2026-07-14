_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local P = assert(A.Parser, "Assistant parser missing")

local function assertHelpfulClarification(result, label)
    assert(type(result) == "table", label .. ": missing result")
    assert((result.status or result.result) == "ambiguous",
        label .. ": expected an ambiguity clarification, got " .. tostring(result.status or result.result))
    local text = tostring(result.text or "")
    assert(text:find("How many letters", 1, true), label .. ": missing length guidance")
    assert(text:find("which side", 1, true), label .. ": missing direction guidance")
    assert(not text:find("recovered and is still ready", 1, true), label .. ": entered failure recovery")
end

assert(P._registryExactAliasIndex == nil, "exact-alias index was unexpectedly warm before the first prompt")
local submitted = A.Submit("shorten target name")
assertHelpfulClarification(submitted, "cold Submit")
assert(P._registryExactAliasIndex == nil, "cold Submit built the full exact-alias index")

local parsed = P.ParseNameShorteningShortcut("shorten target name", {}, "shorten target name")
assert(parsed and parsed.kind == "answer" and parsed.status == "ambiguous",
    "direct specialist did not return the bounded name-shortening clarification")
assert(P._registryExactAliasIndex == nil, "direct specialist built the full exact-alias index")

local callbackResult
local deferred = A.SubmitDeferred("shorten target name", function(result)
    callbackResult = result
end)
assertHelpfulClarification(deferred, "cold SubmitDeferred")
assertHelpfulClarification(callbackResult, "SubmitDeferred callback")
assert(P._registryExactAliasIndex == nil, "SubmitDeferred built the full exact-alias index")

-- Once an exact generated label has warmed the alias index, overlapping raw
-- and reviewed name-shortening aliases must keep the same full-phrase
-- precedence as a cold request. This previously selected the unsafe raw
-- General field and returned an unsupported answer for a valid Target leaf.
A.StartNewTask()
local warmed = assert(A.Submit("turn on target shorten name show dots"))
assert((warmed.status or warmed.result) ~= "failed", "exact show-dots warm-up failed")
assert(type(P._registryExactAliasIndex) == "table", "exact show-dots command did not warm the alias index")

A.StartNewTask()
local maxChars = assert(A.Submit("set target shorten name max chars to 20"))
local maxStatus = maxChars.status or maxChars.result
assert(maxStatus == "applied" or maxStatus == "unchanged",
    "warm Target max-chars command did not reach its reviewed leaf: " .. tostring(maxChars.text))
assert(maxChars.kind ~= "unsupported", "warm Target max-chars command fell into unsafe raw fallback")
local maxSetting = assert(A.Registry:GetSetting("fontScope.target.shortenNameMaxChars"),
    "reviewed Target name-max leaf is missing")
assert(tonumber(maxSetting.get()) == 20, "warm Target max-chars command did not set the reviewed leaf")

io.write("assistant name-shortening cold-start regression passed\n")
