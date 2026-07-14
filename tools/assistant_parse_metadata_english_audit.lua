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
assert(type(A.Parse) == "function", "Assistant parser missing")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "einstellungen", "assistent", "zurueck", "zur\195\188ck", "rueck",
    "nicht", "keine", "abbrechen", "anwenden", "ausfuehren", "ausf\195\188hren",
    "hilfe", "spieler", "ziel", "auren", "profil", "zauberleiste", "menue", "fuer",
    "groesse", "gr\195\182sse",
}

local rawPhrases = {
    "spieler name aus",
    "ziel buffs groesse",
    "zeige target aura blacklist",
    "bearbeitungsmodus status",
    "profil status",
    "diagnosebericht",
    "zeige mir support links",
    "kopiere discord link",
}

local cases = {
    "spieler name aus",
    "ziel buffs groesse 33",
    "target buffs groesse 32",
    "zeige target aura blacklist",
    "bearbeitungsmodus status",
    "profil status",
    "diagnosebericht",
    "fehlerbericht",
    "zeige mir support links",
    "kopiere discord link",
    "open profile import",
    "export current profile",
    "check gameplay",
    "check class resources",
    "check dashboard",
    "edit mode help",
    "open display recovery",
    "turn off player name",
    "set target cast bar texture to Solid",
    "set raid buff filter to raid",
    "set class resources width to essential cooldowns",
    "reset target aura scope",
    "apply performance aura preset",
}

local visibleKeys = {
    label = true,
    summary = true,
    valueLabel = true,
    confirmText = true,
    text = true,
    title = true,
    help = true,
    status = true,
    description = true,
}

local ignoredKeys = {
    raw = true,
    normalized = true,
    input = true,
    key = true,
    value = true,
    unit = true,
    page = true,
    frameType = true,
    attribute = true,
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local failures = {}

local function checkString(path, value)
    value = tostring(value or "")
    if value == "" then return end
    local haystack = normalizedWords(value)
    for _, term in ipairs(germanTerms) do
        assert(not haystack:find(" " .. tostring(term):lower() .. " ", 1, true), path .. ": visible parser metadata contains German term " .. term .. ": " .. value)
    end
    local lower = value:lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(tostring(phrase):lower(), 1, true), path .. ": visible parser metadata repeats raw phrase " .. phrase .. ": " .. value)
    end
end

local function scan(value, path, depth, seen)
    if depth > 8 then return end
    local valueType = type(value)
    if valueType ~= "table" then return end
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        local keyText = tostring(key or "")
        local childPath = path .. "." .. keyText
        if type(child) == "string" then
            if visibleKeys[keyText] then
                local ok, err = pcall(checkString, childPath, child)
                if not ok then failures[#failures + 1] = err end
            end
        elseif type(child) == "table" and not ignoredKeys[keyText] then
            scan(child, childPath, depth + 1, seen)
        end
    end
end

local checked = 0
for _, input in ipairs(cases) do
    local parsed = A.Parse(input)
    assert(type(parsed) == "table", input .. ": parser returned no plan")
    local kind = tostring(parsed.kind or "")
    assert(kind ~= "" and kind ~= "unknown", input .. ": parser returned unknown plan")
    checked = checked + 1
    scan(parsed, input, 0, {})
end

if #failures > 0 then
    io.stderr:write("assistant_parse_metadata_english_audit failures: " .. tostring(#failures) .. "\n")
    for i = 1, math.min(#failures, 120) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_parse_metadata_english_audit: ok cases=" .. tostring(checked) .. "\n")
