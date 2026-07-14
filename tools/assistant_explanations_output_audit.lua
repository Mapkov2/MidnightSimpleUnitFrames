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
local M = assert(_G.MSUF2 or (_G.MSUF_NS and _G.MSUF_NS.MSUF2), "MSUF menu namespace missing after dashboard smoke")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
}

local rawPhrases = {
    "warum sind target buffs versteckt",
    "diagnostik",
    "zeige mir support links",
}

local cases = {
    { input = "run checks", status = "info", contains = "MSUF Assistant details" },
    { input = "assistant support text", status = "info", contains = "MSUF Assistant details" },
    { input = "diagnostik", status = "info", contains = "MSUF Assistant details" },
    { input = "check profile problems", status = "info", contains = "Profile check:" },
    { input = "warum sind target buffs versteckt", status = "info", contains = "Target aura check:" },
    { input = "why is target castbar hidden", status = "info", contains = "Target cast bar" },
    { input = "why are party frames hidden", status = "info", contains = "Party" },
    { input = "edit mode help", status = "info", contains = "Assistant help for Edit Mode" },
    { input = "open display recovery", status = "navigated", contains = "Opened Dashboard recovery tools" },
    { input = "support links", status = "navigated", contains = "MSUF support links:" },
    { input = "copy discord link", status = "info", contains = "Discord link is ready to copy" },
    { input = "open profile import", status = "navigated", contains = "Add your MSUF profile string below" },
    { input = "what active target debuff filters do I have", status = "info", contains = "Target Debuff filters" },
    { input = "what does dispellable filter do", status = "info", contains = "Aura filter explanation" },
    { input = "is player buff raid filter on", status = "info", contains = "Raid filter is inactive" },
    { input = "explain party buff filters", status = "info", contains = "Party Buff group aura filter" },
    { input = "what is a good filter for raid?", status = "info", contains = "Raid aura filter recommendation" },
}

-- Registered action labels can legitimately contain diagnostic words. These
-- exact explanation prompts must resolve to the action-description answer,
-- never to a runnable diagnostic/action plan.
local actionExplanationCases = {
    { input = "explain Allow Hidden Aura Spell", label = "Allow Hidden Aura Spell" },
    { input = "explain Show Hidden Group Aura Categories", label = "Show Hidden Group Aura Categories" },
    { input = "explain Clear Broken Spec Profile Links", label = "Clear Broken Spec Profile Links" },
}

for _, case in ipairs(actionExplanationCases) do
    local parsed = A.Parse(case.input, {})
    assert(type(parsed) == "table", case.input .. ": missing parser result")
    assert(parsed.kind == "answer", case.input .. ": expected a non-executable answer, got " .. tostring(parsed.kind))
    assert(parsed.action == nil and not (type(parsed.changes) == "table" and #parsed.changes > 0),
        case.input .. ": explanation returned an executable plan")
    assert(tostring(parsed.text or ""):find(case.label, 1, true),
        case.input .. ": explanation omitted the exact action label: " .. tostring(parsed.text or ""))
    assert(tostring(parsed.text or ""):find("I did not run it from this explanation question.", 1, true),
        case.input .. ": explanation omitted the no-execution guarantee: " .. tostring(parsed.text or ""))
end

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

local function checkPanel(label)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
end

local function clearConversationState()
    if type(A.RouterClearPendingResultsForRoute) == "function" then A.RouterClearPendingResultsForRoute() end
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    A.pendingSelectedResult = nil
    A.lastAssistantHelpContext = nil
    A.lastAssistantPlanningContext = nil
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(ctx) == "table" then for key in pairs(ctx) do ctx[key] = nil end end
end

for _, case in ipairs(cases) do
    clearConversationState()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    local result = A.Submit(case.input)
    assert(type(result) == "table", case.input .. ": missing result")
    local status = result.status or result.result
    assert(status == case.status, case.input .. ": expected " .. tostring(case.status) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(case.input, result.text or "")
    if case.contains then
        assert(tostring(result.text or ""):find(case.contains, 1, true), case.input .. ": missing text " .. case.contains .. ": " .. tostring(result.text or ""))
    end
    checkPanel(case.input)
end

local oldGetLocale = _G.GetLocale
_G.GetLocale = function() return "deDE" end
if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
A.pendingChoices = nil
A.pendingResults = nil
A.pendingSelectedResult = nil
local localeResult = A.Submit("assistant support text")
_G.GetLocale = oldGetLocale
assert(type(localeResult) == "table", "support text locale label: missing result")
assertEnglishOutput("support text locale label", localeResult.text or "")
assert(tostring(localeResult.text or ""):find("Locale: German (deDE)", 1, true), "support text locale label: missing English locale label: " .. tostring(localeResult.text or ""))
assert(not tostring(localeResult.text or ""):find("Locale: deDE", 1, true), "support text locale label: leaked raw locale code: " .. tostring(localeResult.text or ""))
checkPanel("support text locale label")

local pageCases = {
    { page = "uf_target", input = "explain this page", contains = "Assistant help for Target:" },
    { page = "opt_castbar", input = "what can i do on this page", contains = "Assistant help for Cast Bars:" },
    { page = "classpower", input = "how can i configure this page", contains = "Assistant help for Class Resources:" },
    { page = "profiles", input = "show me commands for this page", contains = "Assistant help for Profiles:" },
}

local oldPage = M.activeKey
for _, case in ipairs(pageCases) do
    clearConversationState()
    M.activeKey = case.page
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    local result = A.Submit(case.input)
    assert(type(result) == "table", case.input .. ": missing page help result")
    local status = result.status or result.result
    assert(status == "info", case.input .. ": expected info, got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(case.input, result.text or "")
    assert(tostring(result.text or ""):find(case.contains, 1, true), case.input .. ": missing page help text " .. case.contains .. ": " .. tostring(result.text or ""))
    checkPanel(case.input)
end
M.activeKey = oldPage

io.write("assistant_explanations_output_audit: ok cases=" .. tostring(#cases + #pageCases + #actionExplanationCases + 1) .. "\n")
