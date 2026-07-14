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
    "gruppenlayout", "sonderbereich", "offen", "geheimer",
}

local rawPhrases = {
    "assistant current step",
    "bearbeitungsmodus status",
    "anker picker status",
    "assistant.submit",
    "assistant.job.step",
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

local function checkPanel(label, keepPanel)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
    if not keepPanel then
        if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    end
end

local function submit(input, expectedStatus, contains, keepPanel)
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = result.status or result.result
    assert(status == expectedStatus, input .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(input, result.text or "")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), input .. ": missing text " .. tostring(contains) .. ": " .. tostring(result.text or ""))
    end
    checkPanel(input, keepPanel)
    return result
end

if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
submit("assistant current step", "info", "Current Assistant step:")
submit("open profile import", "navigated", "Add your MSUF profile string below", true)
submit("close assistant panel", "navigated", "Closed the Assistant import panel")
submit("back", "failed", "go back")
submit("forward", "failed", "go forward")
submit("enter edit mode", "failed", "MSUF Edit Mode controls")
submit("bearbeitungsmodus status", "info", "MSUF Edit Mode")
submit("why cant i exit edit mode", "info", "MSUF Edit Mode")
submit("cancel edit mode", "confirmation_needed", "Answer with 'yes'")
submit("cancel", "applied", "Cancelled.")
submit("open anchor picker", "navigated", "Anchor picker")
submit("anker picker status", "info", "custom anchor picker")
submit("cancel custom anchor picker", "failed", "custom anchor picker")
submit("start player custom anchor picker", "navigated", "custom anchor")

local M = assert(_G.MSUF2, "Menu missing after dashboard smoke")
if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() else A.pendingFlow = nil end
A.pendingChoices = nil
A.pendingConfirmation = nil
M.activeKey = "gf_layout"
local directStatus = A.Workflow.StatusText()
assertEnglishOutput("direct support status", directStatus)
assert(not directStatus:find("assistant.submit", 1, true), "direct support status exposed an internal response label: " .. tostring(directStatus))
assert(not directStatus:find("assistant.job.step", 1, true), "direct support status exposed an internal job label: " .. tostring(directStatus))
submit("show MSUF status", "info", "Active page: Group Layout")
submit("show assistant status", "info", "Active page: Group Layout")

M.activeKey = "gruppenlayout"
A.pendingFlow = { kind = "unknownGermanFlow", label = "Gruppenlayout offen" }
local context = A.GetContext and A.GetContext() or nil
if type(context) == "table" then context.pendingFlow = A.pendingFlow end
submit("assistant current step", "info", "Guided step: guided step")
submit("cancel workflow", "applied", "Cancelled guided step.")

M.activeKey = "sonderbereich"
A.pendingFlow = { kind = "unknownGermanFlow", label = "Geheimer Sonderbereich offen" }
context = A.GetContext and A.GetContext() or nil
if type(context) == "table" then context.pendingFlow = A.pendingFlow end
submit("diagnose dashboard setup", "info", "Dashboard setup check:")

io.write("assistant_workflow_output_audit: ok cases=18\n")
