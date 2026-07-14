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
}

local rawPhrases = {
    "spieler name aus",
    "fokus name aus",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(label, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        assert(not haystack:find(" " .. term .. " ", 1, true), label .. ": output contains German visible term " .. term .. ": " .. tostring(output))
    end
    local lower = tostring(output or ""):lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(phrase, 1, true), label .. ": output repeated raw phrase " .. phrase .. ": " .. tostring(output))
    end
end

local function submit(input, expectedStatus, contains)
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = result.status or result.result
    assert(status == expectedStatus, input .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(input, result.text or "")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), input .. ": missing text " .. tostring(contains) .. ": " .. tostring(result.text or ""))
    end
    return result
end

A.undoStack = {}
A.redoStack = {}
if type(A.ClearHistory) == "function" then A.ClearHistory() end
_G.MSUF_DB.player.showName = true
_G.MSUF_DB.focus.showName = true

submit("undo", "failed", "no Assistant change")
submit("spieler name aus", "applied", "I changed Player Name")
submit("undo", "applied", "Reverted")
submit("redo", "applied", "Reapplied")
submit("undo", "applied", "Reverted")
submit("fokus name aus", "applied", "I changed Focus Name")

local history = type(A.GetHistory) == "function" and A.GetHistory() or {}
local assistantRows = 0
for i = 1, #history do
    local item = history[i]
    if item and item.role ~= "user" then
        assistantRows = assistantRows + 1
        assertEnglishOutput("assistant history #" .. tostring(i), item.text or "")
    end
end
assert(assistantRows >= 6, "assistant history did not capture undo/redo outputs")

io.write("assistant_undo_output_audit: ok assistantRows=" .. tostring(assistantRows) .. "\n")