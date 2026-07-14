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
A.GetContext = A.GetContext or function() return {} end

local function norm(text)
    return tostring(text or ""):lower()
end

local function containsAura(action)
    local haystack = table.concat({
        norm(action.key),
        norm(action.page),
        norm(action.frameType),
        norm(action.category),
        norm(action.label),
    }, " ")
    return haystack:find("aura", 1, true) ~= nil
        or haystack:find("buff", 1, true) ~= nil
        or haystack:find("debuff", 1, true) ~= nil
end

local function usefulPhrase(text)
    text = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local normalized = norm(text)
    if normalized == "start"
        or normalized == "open"
        or normalized == "reset"
        or normalized == "clear"
        or normalized == "toggle"
        or normalized == "status"
    then
        return nil
    end
    return text
end

local function parsedHasAction(parsed, key)
    if type(parsed) ~= "table" then return false end
    if parsed.action and parsed.action.key == key then return true end
    for _, choice in ipairs(parsed.choices or {}) do
        if choice.action and choice.action.key == key then return true end
    end
    return false
end

local function genuineInputClarification(parsed, phrase, key)
    if type(parsed) ~= "table" or parsed.actionInputClarification ~= true
        or parsed.kind ~= "answer" or parsed.action ~= nil then
        return false
    end
    local guard = A.ActionInputParseGuard
    local rawParse = guard and guard.RawParse
    if type(rawParse) ~= "function" then return false end
    local raw = rawParse(phrase)
    if type(raw) ~= "table" then return false end
    if raw.actionInputClarification == true and raw.kind == "answer" then return true end
    if raw.action and raw.action.key == key then
        local normalized = A.NormalizeAssistantActionInput(key, raw.args or {})
        return type(normalized) ~= "table"
    end
    return false
end

local failures = {}
local checked, direct, choices, clarifications = 0, 0, 0, 0

for _, action in ipairs(Registry:AllActions() or {}) do
    if not containsAura(action) then
        checked = checked + 1
        local phrases, seen = {}, {}
        local function add(text)
            text = usefulPhrase(text)
            local key = norm(text)
            if text and not seen[key] then
                seen[key] = true
                phrases[#phrases + 1] = text
            end
        end
        for _, alias in ipairs(action.aliases or {}) do add(alias) end
        add(action.label)
        add(action.key)

        local ok, last = false, "no usable phrase"
        for _, phrase in ipairs(phrases) do
            local parsed = A.Parse(phrase)
            last = tostring(phrase) .. " => " .. tostring(parsed and parsed.kind)
                .. " " .. tostring(parsed and parsed.text or parsed and parsed.action and parsed.action.key or "")
            if parsedHasAction(parsed, action.key) then
                ok = true
                if parsed and parsed.action and parsed.action.key == action.key then
                    direct = direct + 1
                else
                    choices = choices + 1
                end
                break
            elseif genuineInputClarification(parsed, phrase, action.key) then
                ok = true
                clarifications = clarifications + 1
                break
            end
        end
        if not ok then
            failures[#failures + 1] = tostring(action.key) .. " [" .. tostring(action.label or "") .. "] " .. last
        end
    end
end

if #failures > 0 then
    print("assistant_action_parse_audit: failed checked=" .. tostring(checked) .. " failures=" .. tostring(#failures))
    for i = 1, math.min(#failures, 80) do print(failures[i]) end
    os.exit(1)
end

print("assistant_action_parse_audit: ok checked=" .. tostring(checked) .. " direct=" .. tostring(direct)
    .. " choices=" .. tostring(choices) .. " clarifications=" .. tostring(clarifications))
