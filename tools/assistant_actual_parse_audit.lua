_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = {},
    focus = {},
    pet = {},
    targettarget = {},
    focustarget = {},
    boss = {},
    gf_party = {},
    gf_raid = {},
    gf_mythicraid = {},
}
_G.GetLocale = function() return "enUS" end

local runtimeLoaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(runtimeLoaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local Registry = assert(A.Registry, "Assistant registry missing")
local P = assert(A.Parser, "Assistant parser missing")
local M = MSUF.MSUF2 or _G.MSUF2 or {}
A.GetContext = A.GetContext or function() return {} end

local function normalize(text)
    return (P.Normalize and P.Normalize(text)) or tostring(text or ""):lower()
end

local function trim(text)
    return tostring(text or ""):gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function containsAura(setting)
    local haystack = table.concat({
        tostring(setting.key or ""),
        tostring(setting.page or ""),
        tostring(setting.frameType or ""),
        tostring(setting.category or ""),
        tostring(setting.label or ""),
    }, " "):lower()
    return haystack:find("aura", 1, true) ~= nil
        or haystack:find("buff", 1, true) ~= nil
        or haystack:find("debuff", 1, true) ~= nil
end

local function excluded(setting)
    if type(setting) ~= "table" then return true end
    if containsAura(setting) then return true end
    local key = tostring(setting.key or ""):lower()
    local attr = tostring(setting.attribute or ""):lower()
    local label = tostring(setting.label or ""):lower()
    if key == "bars.roundedunitframes" or key:find("shape", 1, true) or key:find("rounded", 1, true) then return true end
    if attr:find("shape", 1, true) or attr:find("rounded", 1, true) then return true end
    if label:find("unitframe shape", 1, true) then return true end
    return false
end

local function inScope(setting, mode)
    mode = tostring(mode or "all")
    if mode == "all" or mode == "" then return true end
    local key = tostring(setting.key or "")
    local frameType = tostring(setting.frameType or "")
    local page = tostring(setting.page or "")
    if mode == "group" then
        return frameType == "group" or key:find("^gf_") ~= nil or page:find("^gf_") ~= nil
    end
    if mode == "unit" then
        return frameType == "unitframe"
    end
    if mode == "castbar" then
        return frameType == "castbar"
    end
    if mode == "classpower" then
        return frameType == "classPower" or key:find("classPower", 1, true) ~= nil
    end
    if mode == "gameplay" then
        return key:find("^gameplay%.") ~= nil or frameType == "gameplay"
    end
    return true
end

local function pageContextForSetting(setting)
    local key = tostring(setting and setting.key or "")
    local frameType = tostring(setting and setting.frameType or "")
    local unit = tostring(setting and setting.unit or "")
    local category = tostring(setting and setting.category or ""):lower()
    if frameType == "unitframe" then
        if unit == "targettarget" then return "uf_targettarget" end
        if unit == "focustarget" then return "uf_focustarget" end
        if unit ~= "" and unit ~= "global" then return "uf_" .. unit end
    end
    if frameType == "group" or key:find("^gf_") then
        if category:find("indicator", 1, true) or key:lower():find("icon", 1, true) then return "gf_indicators" end
        if category:find("text", 1, true) or key:lower():find("texture", 1, true) or key:lower():find("bar", 1, true) then return "gf_bars" end
        return "gf_layout"
    end
    if frameType == "castbar" then return "opt_castbar" end
    if frameType == "classPower" or key:find("classPower", 1, true) then return "classpower" end
    if frameType == "gameplay" or key:find("^gameplay%.") then return "gameplay" end
    if frameType == "profiles" then return "profiles" end
    if frameType == "globalBars" or frameType == "bars" or key:find("^barScope%.") then return "opt_bars" end
    if frameType == "fonts" or key:find("^fontScope%.") then return "opt_fonts" end
    if frameType == "colors" then
        if key:find("classPower", 1, true) then return "classpower" end
        return "opt_colors"
    end
    return "home"
end

local function applyPageContext(setting)
    M.activeKey = pageContextForSetting(setting)
    local unit = tostring(setting and setting.unit or "")
    if unit == "party" or unit == "raid" or unit == "mythicraid" then
        M.gfScope = unit
    end
end

local function valueText(setting)
    if setting.type == "boolean" then return nil end
    if setting.type == "color" then return "red" end
    local key = tostring(setting.key or ""):lower()
    local label = tostring(setting.label or ""):lower()
    if setting.type == "number" then
        if setting.percent then return "50" end
        local minValue, maxValue = tonumber(setting.min), tonumber(setting.max)
        if minValue and maxValue then return tostring(math.floor((minValue + maxValue) / 2)) end
        return "1"
    end
    if setting.type == "enum" then
        for _, value in ipairs(setting.values or {}) do
            local text = tostring(value or "")
            if text ~= "" and text ~= "__CUSTOM__" then return text end
        end
        for alias in pairs(setting.valueAliases or {}) do return tostring(alias) end
        return "on"
    end
    if setting.type == "string" then
        if key:find("texture", 1, true) or label:find("texture", 1, true) then return "Solid" end
        if key:find("font", 1, true) or label:find("font", 1, true) then return "Friz Quadrata TT" end
        if tostring(setting.mediaType or "") ~= "" then return "Solid" end
        return "audit value"
    end
    return "audit value"
end

local GENERIC_PHRASES = {
    ["enable"] = true,
    ["enabled"] = true,
    ["show"] = true,
    ["hide"] = true,
    ["size"] = true,
    ["width"] = true,
    ["height"] = true,
    ["x offset"] = true,
    ["y offset"] = true,
    ["color"] = true,
    ["background"] = true,
    ["reset"] = true,
}

local function usefulPhrase(text)
    local phrase = trim(text)
    if phrase == "" then return false end
    local norm = normalize(phrase)
    if GENERIC_PHRASES[norm] then return false end
    local words = 0
    for _ in norm:gmatch("%S+") do words = words + 1 end
    return words >= 2 or norm:find("%.", 1, true) ~= nil
end

local function commandFor(setting, phrase)
    local value = valueText(setting)
    if setting.type == "boolean" then return "turn on " .. phrase end
    return "set " .. phrase .. " to " .. tostring(value)
end

local function resultContains(parsed, key)
    if type(parsed) ~= "table" then return false end
    if key == "general.customFontColor"
        and parsed.kind == "action"
        and parsed.action
        and parsed.action.key == "set_global_font_color"
    then
        return true
    end
    for _, change in ipairs(parsed.changes or {}) do
        if change.setting and change.setting.key == key then return true end
    end
    for _, choice in ipairs(parsed.choices or {}) do
        if choice.setting and choice.setting.key == key then return true end
    end
    return false
end

local function choiceSummary(parsed)
    local out = {}
    for _, choice in ipairs(parsed and parsed.choices or {}) do
        local setting = choice.setting
        local action = choice.action
        if setting and setting.key then
            out[#out + 1] = tostring(setting.key)
        elseif action and action.key then
            out[#out + 1] = tostring(action.key)
        end
    end
    return table.concat(out, ",")
end

local function candidatePhrases(setting)
    local out, seen = {}, {}
    local function add(text)
        text = trim(text)
        local norm = normalize(text)
        if usefulPhrase(text) and not seen[norm] then
            seen[norm] = true
            out[#out + 1] = text
        end
    end
    add(setting.label)
    for _, alias in ipairs(setting.aliases or {}) do add(alias) end
    add(setting.key)
    return out
end

local buckets = {}
local function bucketKey(setting)
    return table.concat({
        tostring(setting.frameType or "unknown"),
        tostring(setting.type or "unknown"),
        tostring(setting.page or ""),
    }, "\031")
end

local scopeMode = arg and arg[2] or "all"
local showDetails = arg and (arg[3] == "details" or arg[3] == "verbose" or arg[3] == "ambiguous")
for _, setting in ipairs(Registry:AllSettings() or {}) do
    if not excluded(setting) and inScope(setting, scopeMode) then
        local key = bucketKey(setting)
        buckets[key] = buckets[key] or {}
        buckets[key][#buckets[key] + 1] = setting
    end
end

local bucketKeys = {}
for key in pairs(buckets) do bucketKeys[#bucketKeys + 1] = key end
table.sort(bucketKeys)

local sampleLimit = arg and arg[1] == "all" and 0 or (tonumber(arg and arg[1]) or 320)
local samples = {}
local function addSample(setting)
    if setting and (sampleLimit == 0 or #samples < sampleLimit) then samples[#samples + 1] = setting end
end

local round = 1
while sampleLimit == 0 or #samples < sampleLimit do
    local added = 0
    for _, key in ipairs(bucketKeys) do
        local bucket = buckets[key]
        if bucket and bucket[round] then
            addSample(bucket[round])
            added = added + 1
            if sampleLimit ~= 0 and #samples >= sampleLimit then break end
        end
    end
    if added == 0 then break end
    round = round + 1
end

local failures = {}
local ambiguousDetails = {}
local accepted = { changes = 0, ambiguous = 0 }
local started = os.clock()

for _, setting in ipairs(samples) do
    applyPageContext(setting)
    local key = tostring(setting.key or "")
    local ok = false
    local lastKind, lastText = "nil", ""
    for _, phrase in ipairs(candidatePhrases(setting)) do
        local command = commandFor(setting, phrase)
        local parsed = A.Parse(command)
        lastKind = tostring(parsed and parsed.kind)
        lastText = tostring(parsed and parsed.text or "")
        if resultContains(parsed, key) then
            ok = true
            if parsed.kind == "changes" then accepted.changes = accepted.changes + 1
            elseif parsed.kind == "ambiguous" then
                accepted.ambiguous = accepted.ambiguous + 1
                ambiguousDetails[#ambiguousDetails + 1] = table.concat({
                    key,
                    tostring(setting.label or ""),
                    command,
                    choiceSummary(parsed),
                }, "\t")
            end
            break
        end
    end
    if not ok then
        failures[#failures + 1] = key .. " [" .. tostring(setting.label or "") .. "] lastKind=" .. lastKind .. " " .. lastText:gsub("\n", " "):sub(1, 140)
    end
end

if #failures > 0 then
    io.stderr:write("assistant_actual_parse_audit failures: " .. tostring(#failures) .. " / " .. tostring(#samples) .. "\n")
    for i = 1, math.min(#failures, 100) do io.stderr:write(failures[i] .. "\n") end
    os.exit(1)
end

local elapsedMs = (os.clock() - started) * 1000
io.write(string.format(
    "assistant_actual_parse_audit: ok scope=%s samples=%d changes=%d ambiguous=%d elapsedMs=%.1f\n",
    tostring(scopeMode),
    #samples,
    accepted.changes,
    accepted.ambiguous,
    elapsedMs
))
if showDetails and #ambiguousDetails > 0 then
    io.write("ambiguous details:\n")
    for i = 1, #ambiguousDetails do
        io.write(ambiguousDetails[i] .. "\n")
    end
end
