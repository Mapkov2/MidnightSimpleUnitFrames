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
local R = assert(A.RouterPrivate, "Assistant Router private API missing")

do
    local failed = { status = "failed", result = "failed" }
    assert(R.AsReadOnlyResult(failed) == failed and failed.status == "failed", "read-only normalization swallowed a failure")
    assert(R.AsNavigationResult(failed) == failed and failed.status == "failed", "navigation normalization swallowed a failure")
    local ambiguous = { status = "ambiguous", result = "ambiguous" }
    assert(R.AsReadOnlyResult(ambiguous) == ambiguous and ambiguous.status == "ambiguous", "read-only normalization swallowed ambiguity")
end

local readOnlyCases = {
    "where is target health color scheme",
    "explain target health color scheme",
    "what is target health color scheme set to",
    "where can i change raid spacing",
    "where can i change target buff icon size",
    "where is target castbar icon",
    "where is target power text",
    "where is raid ready check size",
    "where is combat timer size",
    "where can i move target frame",
    "why is target castbar hidden",
    "why are party frames hidden",
    "run diagnostics",
    "diagnostik",
    "check profiles",
    "diagnose raid frames",
    "edit mode status",
    "profil status",
    "edit mode help",
    "assistant support text",
    "assistant no match telemetry",
    "copy discord link",
}

local navigationCases = {
    "where is class resource width",
    "where is aura filters",
    "open aura filters",
    "open changelog",
    "open profile import",
    "support links",
    "zeige mir support links",
    "oeffne changelog",
}

local mutationCases = {
    "set target width to 301",
    "turn on target name",
}

local function clearConversationState()
    if type(A.RouterClearPendingResultsForRoute) == "function" then A.RouterClearPendingResultsForRoute() end
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    A.pendingSelectedResult = nil
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.lastMentionedUnit = nil
        ctx.lastMentionedCategory = nil
    end
end

local function statusOf(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

local function submitExpect(input, expected)
    clearConversationState()
    local db = type(A.EnsureDB) == "function" and A.EnsureDB() or {}
    local successCountBefore = tonumber(db.powerUserSupportSuccessCount) or 0
    local undoBefore = type(A.undoStack) == "table" and #A.undoStack or 0
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = statusOf(result)
    assert(status == expected, input .. ": expected " .. expected .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assert(result.status == result.result, input .. ": status/result disagree: " .. tostring(result.status) .. "/" .. tostring(result.result))

    if expected ~= "applied" and expected ~= "changed" then
        local successCountAfter = tonumber(db.powerUserSupportSuccessCount) or 0
        local undoAfter = type(A.undoStack) == "table" and #A.undoStack or 0
        assert(successCountAfter == successCountBefore, input .. ": read-only/navigation result incremented mutation telemetry")
        assert(undoAfter == undoBefore, input .. ": read-only/navigation result added an Undo entry")
    end
end

for _, input in ipairs(readOnlyCases) do submitExpect(input, "info") end
for _, input in ipairs(navigationCases) do submitExpect(input, "navigated") end
for _, input in ipairs(mutationCases) do submitExpect(input, "applied") end

io.write("assistant_status_semantics_audit: ok readOnly=" .. tostring(#readOnlyCases)
    .. " navigation=" .. tostring(#navigationCases)
    .. " mutation=" .. tostring(#mutationCases) .. "\n")
