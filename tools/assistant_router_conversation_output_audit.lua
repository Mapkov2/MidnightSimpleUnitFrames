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
    "zeige", "anzeigen", "oeffne", "waehle", "assistent", "zurueck",
    "rueck", "nicht", "keine", "abbrechen", "anwenden", "ausfuehren",
    "loeschen", "kopiere", "verschiebe", "groesse", "kaputt", "befehle",
    "hilfe", "kannst", "erzaehl",
}

local rawPhrases = {
    "was kannst du alles",
    "was kann msuf assistant",
    "wie chatgpt",
    "was kannst du nicht",
    "rede ueber msuf",
    "kannst du mit wow helfen",
    "welche befehle gibt es",
    "warum ist mein interface kaputt",
    "zeige mir support links",
    "oeffne changelog",
    "erzaehl mir was zu auras",
}

local bannedPhrases = {
    "Blizzard Unit Frames - Dashboard",
    "Boss Cast Bar - Boss",
    "Add Color to Empowered Stages - Opt castbar",
}

local cases = {
    { input = "was kannst du alles", status = "info", contains = "MSUF Assistant: what I can do" },
    { input = "was kann msuf assistant", status = "info", contains = "MSUF Assistant: what I can do" },
    { input = "wie chatgpt", status = "info", contains = "Yes—for MSUF and WoW UI setup" },
    { input = "how close are you to chatgpt ingame", status = "info", contains = "I run locally inside MSUF" },
    { input = "what are your limits", status = "info", contains = "MSUF Assistant limits" },
    { input = "was kannst du nicht", status = "info", contains = "MSUF Assistant limits" },
    { input = "rede ueber msuf", status = "info", contains = "I work best with MSUF" },
    { input = "kannst du mit wow helfen", status = "info", contains = "Wowhead" },
    { input = "welche befehle gibt es", status = "info", contains = "MSUF Assistant: what I can do" },
    { input = "hilfe profile", status = "info", contains = "Profiles help" },
    { input = "wo aendere ich castbars", status = "info", contains = "Cast Bars help" },
    { input = "warum ist mein interface kaputt", status = "info", contains = "Troubleshooting help" },
    { input = "zeige mir support links", status = "navigated", contains = "MSUF support links:" },
    { input = "oeffne changelog", status = "navigated", contains = "Opened Dashboard changelog" },
    { input = "open changelog", status = "navigated", contains = "Opened Dashboard changelog" },
    { input = "erzaehl mir was zu auras", status = "info", contains = "Auras are in the MSUF Auras pages" },
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
    for _, phrase in ipairs(bannedPhrases) do
        assert(not tostring(output or ""):find(phrase, 1, true), label .. ": output contains bad search fallback phrase " .. phrase .. ": " .. tostring(output))
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
    assert(tostring(result.text or ""):find(case.contains, 1, true), case.input .. ": missing text " .. tostring(case.contains) .. ": " .. tostring(result.text or ""))
    checkPanel(case.input)
end

local savedLocationShortcut = A.RouterTryRegistrySettingLocationShortcut
A.RouterTryRegistrySettingLocationShortcut = function() return nil end
local coldInline = assert(A.RouterTryTargetTargetInlineNameShortcut(
    "where can I show the target of target name on the target frame?",
    function() return nil end
), "cold Target-of-Target inline lookup lost its deterministic fallback")
A.RouterTryRegistrySettingLocationShortcut = savedLocationShortcut
assert((coldInline.status or coldInline.result) == "info", "cold inline fallback was not read-only")
assert(tostring(coldInline.text):find("Target Target Inline Text setting location", 1, true),
    "cold inline fallback routed to generic visibility troubleshooting")
assert(tostring(coldInline.text):find("I did not change it", 1, true),
    "cold inline fallback did not confirm that it was read-only")

io.write("assistant_router_conversation_output_audit: ok cases=" .. tostring(#cases) .. "\n")
