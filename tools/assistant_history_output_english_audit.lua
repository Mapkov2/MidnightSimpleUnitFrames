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

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
    "bearbeitungsmodus", "diagnosebericht", "fehlerbericht", "spieler",
    "ziel", "zauberleiste", "auren", "profil",
}

local rawPhrases = {
    "zeige mir befehle",
    "spieler name aus",
    "bearbeitungsmodus status",
    "diagnosebericht",
    "fehlerbericht",
    "target mystery texture color",
    "anchor minimap to cooldownmanager",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglish(label, output)
    local text = tostring(output or "")
    local haystack = normalizedWords(text)
    for _, term in ipairs(germanTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        assert(not haystack:find(needle, 1, true), label .. ": visible German term " .. tostring(term) .. ": " .. text)
    end
    local lower = text:lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(tostring(phrase):lower(), 1, true), label .. ": repeated raw phrase " .. tostring(phrase) .. ": " .. text)
    end
end

local function clearPending()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    A.pendingChoices = nil
    A.pendingConfirmation = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingFlow = nil
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingConfirmation = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingFlow = nil
    end
end

local function clearHistory()
    if type(A.ClearHistory) == "function" then A.ClearHistory() end
end

local function assertAssistantHistory(label, minAssistantRows)
    local history = type(A.GetHistory) == "function" and A.GetHistory() or {}
    assert(type(history) == "table", label .. ": history missing")
    local assistantRows = 0
    for i = 1, #history do
        local item = history[i]
        if type(item) == "table" and item.role ~= "user" then
            assistantRows = assistantRows + 1
            assertEnglish(label .. " history #" .. tostring(i), item.text or "")
            assertEnglish(label .. " history summary #" .. tostring(i), item.actionSummary or "")
            assertEnglish(label .. " history status #" .. tostring(i), item.status or "")
        end
    end
    assert(assistantRows >= (minAssistantRows or 1), label .. ": expected assistant history rows, got " .. tostring(assistantRows))
    return assistantRows
end

local function submit(label, input, expectedStatus, contains)
    clearPending()
    clearHistory()
    local result = A.Submit(input)
    assert(type(result) == "table", label .. ": missing result")
    local status = result.status or result.result
    if expectedStatus then
        assert(status == expectedStatus, label .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    end
    assertEnglish(label .. " result", result.text or "")
    assertEnglish(label .. " summary", result.summary or "")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), label .. ": missing " .. tostring(contains) .. ": " .. tostring(result.text or ""))
    end
    assertAssistantHistory(label, 1)
    return result
end

_G.MSUF_DB.player.showName = true
submit("German command history", "spieler name aus", "applied", "I changed Player Name")
submit("German help no-match history", "zeige mir befehle", "info", "I'm not sure which MSUF request you mean yet.")
submit("German edit mode status history", "bearbeitungsmodus status", "info", "MSUF Edit Mode")
submit("German diagnostics history", "diagnosebericht", "info", "MSUF Assistant details")
_G.MSUF_DB.target.showName = true
_G.MSUF_DB.focus.showName = true
submit("English batch history", "turn off target name and turn off focus name", "applied", "Done. I handled 2 requests")

clearPending()
clearHistory()
if type(A.ClearNoMatchTelemetry) == "function" then A.ClearNoMatchTelemetry() end
for i = 1, 4 do A.RecordNoMatch("target mystery texture color", { status = "failed" }, "history-audit") end
for i = 1, 2 do A.RecordNoMatch("anchor minimap to cooldownmanager", { status = "failed" }, "history-audit") end
submit("No-match telemetry history", "assistant no match telemetry", "info", "Assistant wording to improve:")
if type(A.ClearNoMatchTelemetry) == "function" then A.ClearNoMatchTelemetry() end

clearPending()
clearHistory()
_G.MSUF_DB.pet.showName = true
local deferred = A.SubmitDeferred("turn off pet name")
if deferred and (deferred.status or deferred.result) == "queued" then
    local guard = 0
    while A.IsBusy and A.IsBusy() and guard < 20 do
        guard = guard + 1
        if type(A._RunJobPump) == "function" then A._RunJobPump() else break end
    end
end
assertAssistantHistory("Deferred history", 1)

io.write("assistant_history_output_english_audit: ok\n")
