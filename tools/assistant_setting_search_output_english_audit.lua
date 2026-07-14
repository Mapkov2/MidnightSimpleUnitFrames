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
local Registry = assert(A.Registry, "Assistant registry missing")
local Knowledge = assert(A.Knowledge, "Assistant knowledge missing")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "einstellungen", "assistent", "zurueck", "zur\195\188ck", "rueck",
    "nicht", "keine", "abbrechen", "anwenden", "ausfuehren", "ausf\195\188hren",
    "hilfe", "spieler", "ziel", "auren", "profil", "zauberleiste", "menue", "fuer",
    "loeschen", "kopiere", "verschiebe", "groesse", "hoehe", "breite",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(label, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        assert(not haystack:find(needle, 1, true), label .. ": output contains German visible term " .. term .. ": " .. tostring(output))
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

local function checkPanel(label)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
end

local function checkResult(label, result)
    assert(type(result) == "table", label .. ": missing result")
    assertEnglishOutput(label, result.text or "")
    assertEnglishOutput(label .. " summary", result.summary or "")
    checkPanel(label)
    return tostring(result.text or "")
end

local function domainKey(setting)
    local key = tostring(setting and setting.key or "")
    return key:match("^([^%.]+)") or "unknown"
end

local function addUniqueSample(samples, seen, setting)
    local key = tostring(setting and setting.key or "")
    if key == "" or seen[key] then return end
    seen[key] = true
    samples[#samples + 1] = setting
end

local function sampledSettings(limit)
    local all = Registry:AllSettings() or {}
    local byDomain, domains = {}, {}
    for _, setting in ipairs(all) do
        local domain = domainKey(setting)
        if not byDomain[domain] then
            byDomain[domain] = {}
            domains[#domains + 1] = domain
        end
        byDomain[domain][#byDomain[domain] + 1] = setting
    end
    table.sort(domains)

    local samples, seen = {}, {}
    for _, domain in ipairs(domains) do
        local list = byDomain[domain]
        addUniqueSample(samples, seen, list[1])
        addUniqueSample(samples, seen, list[math.max(1, math.floor(#list / 2))])
        addUniqueSample(samples, seen, list[#list])
    end

    limit = tonumber(limit) or 48
    if #samples >= limit then
        local trimmed = {}
        for i = 1, limit do trimmed[i] = samples[i] end
        return trimmed
    end

    local stride = math.max(1, math.floor(#all / math.max(1, limit - #samples)))
    for i = 1, #all, stride do
        addUniqueSample(samples, seen, all[i])
        if #samples >= limit then break end
    end
    return samples
end

local function submit(label, text)
    local ok, result = pcall(A.Submit, text)
    if not ok then error(label .. ": submit error: " .. tostring(result)) end
    return checkResult(label, result)
end

local samples = sampledSettings(arg and tonumber(arg[1]) or 48)
local followupLimit = math.min(#samples, arg and tonumber(arg[2]) or 16)
local searchCount, explainCount, followupCount, coverageCount = 0, 0, 0, 0

local function assertKnowledgeIndexCoversRegistry()
    assert(type(Knowledge.EnsureIndex) == "function", "Knowledge index API missing")
    local index = Knowledge.EnsureIndex()
    local seen = {}
    for _, item in ipairs((index and index.items) or {}) do
        if item and item.kind and item.key then
            seen[tostring(item.kind) .. ":" .. tostring(item.key)] = true
        end
    end
    local missingSettings, missingActions = {}, {}
    for _, setting in ipairs(Registry:AllSettings() or {}) do
        local key = tostring(setting and setting.key or "")
        if key ~= "" and not seen["setting:" .. key] then missingSettings[#missingSettings + 1] = key end
    end
    for _, action in ipairs(Registry:AllActions() or {}) do
        local key = tostring(action and action.key or "")
        local kind = action and action.type == "diagnostic" and "diagnostic" or "action"
        if key ~= "" and not seen[kind .. ":" .. key] then missingActions[#missingActions + 1] = key end
    end
    assert(#missingSettings == 0, "Knowledge index missing settings: " .. table.concat(missingSettings, ", "))
    assert(#missingActions == 0, "Knowledge index missing actions: " .. table.concat(missingActions, ", "))
end

assertKnowledgeIndexCoversRegistry()

for i, setting in ipairs(samples) do
    clearState()
    local key = tostring(setting.key or "")
    local label = tostring(setting.label or key)
    local query = key ~= "" and key or label

    local searchText = submit("setting search " .. key, "search " .. query)
    assert(searchText:find("MSUF", 1, true), "setting search " .. key .. ": search response did not look like an MSUF result: " .. searchText)
    searchCount = searchCount + 1

    local explainText = submit("setting explain " .. key, "explain result 1")
    assert(explainText:find("Result 1:", 1, true), "setting explain " .. key .. ": missing result explanation: " .. explainText)
    explainCount = explainCount + 1

    if i <= followupLimit then
        submit("setting current value " .. key, "current value")
        submit("setting simple explain " .. key, "simpler")
        submit("setting why " .. key, "why this option")
        submit("setting related " .. key, "related options")
        followupCount = followupCount + 4
    end
    clearState()
end

local coverageProbes = {
    { "coverage combat timer page", "search combat timer anchor", "Combat Timer Anchor - Gameplay" },
    { "coverage class resources player hp page", "search class resources player hp height", "Class Resources Player HP Height - Class Resources" },
    { "coverage alternative mana page", "search alternative mana height", "Alternative Mana Height - Class Resources" },
    { "coverage detached power page", "search detached power bar texture", "Detached Power Bar Foreground Texture - Class Resources" },
    { "coverage dashboard scaling page", "search menu scale", "MSUF Menu Scale - Dashboard" },
    { "coverage unit status page", "search status icons midnight style", "Status Icons Use Midnight Style - Player" },
    { "coverage totem page", "search totem frame icon size", "Totem Frame Icon Size - Gameplay" },
    { "coverage crosshair page", "search combat crosshair thickness", "Combat Crosshair Thickness - Gameplay" },
}

for _, probe in ipairs(coverageProbes) do
    clearState()
    local text = submit(probe[1], probe[2])
    assert(text:find(probe[3], 1, true), probe[1] .. ": missing expected page result " .. probe[3] .. ": " .. text)
    coverageCount = coverageCount + 1
end
clearState()

io.write("assistant_setting_search_output_english_audit: ok samples=" .. tostring(#samples)
    .. " searches=" .. tostring(searchCount)
    .. " explains=" .. tostring(explainCount)
    .. " followups=" .. tostring(followupCount)
    .. " coverage=" .. tostring(coverageCount)
    .. "\n")
