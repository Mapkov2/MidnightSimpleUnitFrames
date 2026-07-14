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
    "zeige", "anzeigen", "auflisten", "liste", "aktuell", "aktuelle",
    "verstecke", "verstecken", "ausblenden", "groesse", "ziel",
    "abbrechen", "anwenden", "ausfuehren", "oeffne", "waehle",
}

local rawPhrases = {
    "zeige target aura blacklist",
    "ziel buffs groesse 33",
    "verstecke Rejuvenation auf target auras",
    "target buffs groesse 32",
    "target buff stack text groesse 16",
}

local cases = {
    { input = "set aura editing scope to target", status = "applied", contains = "Aura Editing Scope" },
    { input = "target buffs groesse 32", status = "applied", contains = "Target Buff Icon Size" },
    { input = "target buff stack text groesse 16", status = "applied", contains = "Target Buff Stack Text Size" },
    { input = "move target buffs right 5", status = "applied", contains = "Target Buff X Offset" },
    { input = "blacklist Rejuvenation on target auras", status = "info", contains = "exact SpellID exclusion", readOnly = true },
    { input = "whitelist Rejuvenation on target auras", status = "info", contains = "exact SpellID exclusion", readOnly = true },
    { input = "show current target aura blacklist", status = "failed", contains = "show the hidden-aura list" },
    { input = "clear target aura blacklist", status = "confirmation_needed", contains = "Clear Hidden Aura Spells" },
    { input = "blacklist cooldowns raid buff category", status = "applied", contains = "Hidden Cooldowns" },
    { input = "show raid buff aura blacklist", status = "info", contains = "Raid / Mythic Raid Buffs blacklist" },
    { input = "clear all raid buff category blacklist", status = "confirmation_needed", contains = "Clear Hidden Group Aura Categories" },
    { input = "blacklist Rejuvenation for raid buff blacklist", status = "info", contains = "exact SpellID exclusion", readOnly = true },
    { input = "unblacklist Rejuvenation for raid buff blacklist", status = "info", contains = "exact SpellID exclusion", readOnly = true },
    { input = "show raid buff hidden spells", status = "info", contains = "Suggested fixes:" },
    { input = "apply performance aura preset", status = "confirmation_needed", contains = "Apply Aura Quick Preset" },
    { input = "reset target aura overrides", status = "confirmation_needed", contains = "Reset Aura Scope Overrides" },
    { input = "reset all aura overrides", status = "confirmation_needed", contains = "Reset All Aura Overrides" },
    { input = "reset buff aura style overrides", status = "confirmation_needed", contains = "Reset All Aura Style Overrides" },
    { input = "zeige target aura blacklist", status = "failed", contains = "show the hidden-aura list" },
    { input = "ziel buffs groesse 33", status = "applied", contains = "Target Buff Icon Size" },
    { input = "verstecke Rejuvenation auf target auras", status = "info", contains = "exact SpellID exclusion", readOnly = true },
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
        assert(not lower:find(tostring(phrase):lower(), 1, true), label .. ": output repeated raw phrase " .. phrase .. ": " .. tostring(output))
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

for _, case in ipairs(cases) do
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    A.pendingConfirmation = nil
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingConfirmation = nil
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
    local undoBefore = type(A.undoStack) == "table" and #A.undoStack or 0
    local result = A.Submit(case.input)
    assert(type(result) == "table", case.input .. ": missing result")
    local status = result.status or result.result
    assert(status == case.status, case.input .. ": expected " .. tostring(case.status) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(case.input, result.text or "")
    assert(tostring(result.text or ""):find(case.contains, 1, true), case.input .. ": missing text " .. tostring(case.contains) .. ": " .. tostring(result.text or ""))
    if case.readOnly then
        local undoAfter = type(A.undoStack) == "table" and #A.undoStack or 0
        assert(undoAfter == undoBefore, case.input .. ": read-only aura guidance created an undo entry")
    end
    checkPanel(case.input)
end

io.write("assistant_aura_output_audit: ok cases=" .. tostring(#cases) .. "\n")
