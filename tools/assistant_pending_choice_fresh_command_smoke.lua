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
local registry = assert(A.Registry, "Assistant Registry missing")
local targetName = assert(registry:GetSetting("target.showName"), "target.showName setting missing")
local targetPower = assert(registry:GetSetting("target.showPower"), "target.showPower setting missing")

targetName.set(false)
targetPower.set(true)

local first = assert(A.Submit("show name"), "ambiguous setup command returned no result")
assert((first.status or first.result) == "ambiguous", "'show name' must create a pending choice")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices > 1, "pending name choices missing")

local second = assert(A.Submit("turn off target power"), "fresh command returned no result")
assert((second.status or second.result) == "applied", "fresh command was not applied")
assert(targetName.get() == false, "fresh command leaked into the pending choice and enabled Target Name")
local secondText = tostring(second.text or "")
assert(secondText:find("Target Power", 1, true), "fresh command was not routed as a Target Power command: " .. secondText)
assert(not secondText:find("Target Name", 1, true), "fresh command applied the stale Target Name choice: " .. secondText)
assert(A.pendingChoices == nil, "stale pending choices survived the fresh command")
assert(A.pendingCandidates == nil, "stale pending candidates survived the fresh command")

local undone = assert(A.Submit("undo"), "undo returned no result")
assert((undone.status or undone.result) == "applied", "undo did not apply")
assert(targetName.get() == false, "undo changed unrelated Target Name state")
assert(targetPower.get() == true, "fresh command or undo unexpectedly changed the Target Power visibility toggle")

print("assistant_pending_choice_fresh_command_smoke: ok")
