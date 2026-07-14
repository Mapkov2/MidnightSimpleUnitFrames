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
local K = assert(A.Knowledge, "Assistant Knowledge missing after dashboard smoke")

-- dashboard_smoke intentionally exercises live Assistant requests and may
-- therefore have warmed knowledge. Reset it so this audit owns a deterministic
-- cold boundary instead of depending on which explicit prompt ran earlier.
K.MarkDirty()
assert(K.CapabilityHelp(false) == nil, "cold CapabilityHelp must return its nil sentinel")
local capability = assert(A.RouterPrivate and A.RouterPrivate.AssistantCapabilityReply
    and A.RouterPrivate.AssistantCapabilityReply(), "cold capability fallback returned no result")
assert((capability.status or capability.result) == "info", "cold capability fallback must be read-only info")
assert(tostring(capability.text or ""):find("MSUF Assistant: what I can do", 1, true),
    "cold capability fallback did not explain the Assistant")

-- Search uses nil as a deliberate cold sentinel even when this audit's eager
-- timer stub finishes the queued background build before Search returns.
K.MarkDirty()
local coldSearch = K.Search("target name", 3, { kind = "setting" })
assert(coldSearch == nil, "cold Knowledge.Search must return its nil sentinel")

K.MarkDirty()
local answerOk, coldAnswer = pcall(K.Answer, "search target name", { forceSearch = true })
assert(answerOk, "cold Knowledge.Answer raised an error: " .. tostring(coldAnswer))
assert(coldAnswer == nil, "cold Knowledge.Answer must propagate the Search sentinel")

-- The public synchronous path must turn that cold sentinel into a safe router
-- response rather than indexing nil or pretending that a change was applied.
K.MarkDirty()
local directOk, direct = pcall(A.Submit, "search target name")
assert(directOk, "cold synchronous Submit raised an error: " .. tostring(direct))
assert(type(direct) == "table", "cold synchronous Submit returned no result")
assert((direct.status or direct.result) == "info", "cold synchronous knowledge Submit must be info")

-- In the dashboard path the query itself runs inside the yielding assistant
-- job, so it may cooperatively build the index and answer on that same job.
K.MarkDirty()
local deferredCallback
local deferred = A.SubmitDeferred("search target name", function(result)
    deferredCallback = result
end)
assert(type(deferred) == "table", "cold deferred Submit returned no result")
assert(type(deferredCallback) == "table", "cold deferred Submit did not complete in the dashboard smoke scheduler")
assert((deferredCallback.status or deferredCallback.result) == "info", "deferred knowledge answer must be info")

local directHelp = assert(K.Answer("what is global cooldown"), "direct Knowledge help returned no result")
assert((directHelp.status or directHelp.result) == "info", "direct Knowledge help must be read-only info")

assert(K.EnsureIndex(), "explicit warm Knowledge index build failed")
local counts = assert(K.Summary(), "warm Knowledge summary returned no counts")
assert((counts.setting or 0) == (counts.directSetting or 0) + (counts.guidedSetting or 0),
    "capability setting classes do not partition the indexed registry")
assert((counts.directSetting or 0) > 0, "capability summary found no reviewed direct-write settings")
assert((counts.guidedSetting or 0) > 0, "capability summary found no guidance/read-only fallbacks")
local warmCapability = assert(K.CapabilityHelp(false), "warm CapabilityHelp returned no result")
local capabilityText = tostring(warmCapability.text or "")
assert(capabilityText:find("reviewed direct%-write contracts"),
    "capability help does not distinguish reviewed mutation coverage")
assert(capabilityText:find("guidance/read%-only fallbacks"),
    "capability help does not disclose non-writable registry fallbacks")
assert(not capabilityText:find("I can handle %d+ MSUF options"),
    "capability help still overclaims every indexed option as directly handled")

io.write("assistant_knowledge_cold_audit: ok\n")
