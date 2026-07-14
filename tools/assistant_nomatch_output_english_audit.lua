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

local forbidden = {
    "spieler",
    "zeige",
    "zauberleiste",
    "zauberleisten",
    "groesse",
    "kaputt",
    "bitte",
    "hoch",
    "offen",
}

local function assertEnglish(label, output)
    local text = tostring(output or "")
    local lower = text:lower()
    assert(not lower:find("de:", 1, true), label .. " leaked localized marker DE:: " .. text)
    local words = " " .. lower:gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
    for i = 1, #forbidden do
        local needle = " " .. forbidden[i] .. " "
        assert(not words:find(needle, 1, true), label .. " leaked raw or localized text " .. forbidden[i] .. ": " .. text)
    end
end

assert(type(A.ClearNoMatchTelemetry) == "function", "missing no-match clear")
assert(type(A.RecordNoMatch) == "function", "missing no-match recorder")
assert(type(A.NoMatchTelemetryText) == "function", "missing no-match telemetry formatter")
assert(type(A.NoMatchWorklistText) == "function", "missing no-match worklist formatter")

A.ClearNoMatchTelemetry()
A.RecordNoMatch("spieler name zauberleiste groesse kaputt", { status = "failed" }, "router")
A.RecordNoMatch("zeige aura einstellungen bitte", { status = "failed" }, "knowledge")

local telemetry = A.NoMatchTelemetryText(10)
local worklist = A.NoMatchWorklistText(10)
local filtered = A.NoMatchWorklistText(10, "DE Gruppenframes", "DE offen", "DE hoch", "DE zauberleiste")

assert(telemetry:find("phrase #1", 1, true), "telemetry should refer to saved phrases by number")
assert(worklist:find("phrase #1", 1, true), "worklist should refer to saved phrases by number")
assert(filtered:find("custom area", 1, true), "filtered worklist should use a safe owner-filter label")
assert(filtered:find("custom result", 1, true), "filtered worklist should use a safe result-filter label")
assert(filtered:find("custom importance", 1, true), "filtered worklist should use a safe priority-filter label")
assert(filtered:find("custom topic", 1, true), "filtered worklist should use a safe tag-filter label")

assertEnglish("telemetry", telemetry)
assertEnglish("worklist", worklist)
assertEnglish("filtered worklist", filtered)

A.ClearNoMatchTelemetry()

io.write("assistant_nomatch_output_english_audit: ok\n")
