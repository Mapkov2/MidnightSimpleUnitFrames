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
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "einstellungen", "assistent", "zurueck", "zur\195\188ck", "rueck",
    "nicht", "keine", "abbrechen", "anwenden", "ausfuehren", "ausf\195\188hren",
    "hilfe", "spieler", "ziel", "auren", "profil", "zauberleiste", "menue", "fuer",
}

local rawPhrases = {
    "zeige mir befehle",
    "was kann ich hier aendern",
    "oeffne auren",
    "wo sind castbars",
    "profil import geht nicht",
    "ich sehe ziel frame nicht",
    "auren ueberlappen",
    "text zu klein",
    "was hast du geaendert",
    "profil status",
    "bearbeitungsmodus status",
    "diagnosebericht",
    "fehlerbericht",
    "profile import kaputt",
    "wie chatgpt",
    "was kannst du nicht",
    "target mystery texture color",
    "anchor minimap to cooldownmanager",
    "move target frame sideways",
    "zeige texture",
}

local cases = {
    "zeige mir befehle",
    "spieler name aus",
    "turn off player name and zeige mir befehle",
    "assistant no match telemetry",
    "assistant no match worklist",
    "set target cast bar texture to zeige texture",
    "what can you do",
    "where do i change auras",
    "can you help with wow rotation",
    "hilfe profile",
    "was kann ich hier aendern",
    "oeffne auren",
    "wo sind castbars",
    "warum ist target castbar hidden",
    "profil import geht nicht",
    "ich sehe ziel frame nicht",
    "auren ueberlappen",
    "text zu klein",
    "was hast du geaendert",
    "show tooltips only with ctrl",
    "show tooltips only with shift",
    "assistant support text",
    "show support links",
    "run checks",
    "check profiles",
    "check gameplay",
    "check class resources",
    "check dashboard",
    "open display recovery",
    "edit mode status",
    "enter edit mode",
    "open profile import",
    "export current profile",
    "profil status",
    "bearbeitungsmodus status",
    "diagnosebericht",
    "fehlerbericht",
    "profile import kaputt",
    "assistant help",
    "wie chatgpt",
    "how close are you to chatgpt ingame",
    "what are your limits",
    "was kannst du nicht",
    "what can i change here",
    "open dashboard scaling",
    "menu history undo",
    "menu history redo",
    "reset menu session changes",
}

-- A SharedMedia name is user-owned opaque data, not Assistant-authored prose.
-- Keep the mixed-language value case, but remove only that exact value from
-- the language scan for the mutation and the later last-change report.
local opaqueValuesByInput = {
    ["set target cast bar texture to zeige texture"] = "zeige texture",
    ["was hast du geaendert"] = "zeige texture",
}

local function maskOpaqueValue(input, output)
    output = tostring(output or "")
    for label, value in pairs(opaqueValuesByInput) do
        if input == label or input:sub(1, #label + 1) == label .. " " then
            return (output:gsub(value, "user texture value"))
        end
    end
    return output
end

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(input, output)
    output = maskOpaqueValue(input, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        assert(not haystack:find(needle, 1, true), input .. ": output contains German visible term " .. term .. ": " .. tostring(output))
    end
    local lower = tostring(output or ""):lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(tostring(phrase):lower(), 1, true), input .. ": output repeated raw phrase " .. phrase .. ": " .. tostring(output))
    end
end

local function clearState()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    A.pendingChoices = nil
    A.pendingConfirmation = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingConfirmation = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
end

for _, input in ipairs(cases) do
    clearState()
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    assertEnglishOutput(input, result.text or "")
    assertEnglishOutput(input .. " summary", result.summary or "")
    local panel = A.largeTextPanel
    if type(panel) == "table" then
        assertEnglishOutput(input .. " panel title", panel.title or "")
        assertEnglishOutput(input .. " panel help", panel.help or "")
        assertEnglishOutput(input .. " panel status", panel.status or "")
        assertEnglishOutput(input .. " panel text", panel.text or "")
    end
    clearState()
end

io.write("assistant_output_english_audit: ok cases=" .. tostring(#cases) .. "\n")
