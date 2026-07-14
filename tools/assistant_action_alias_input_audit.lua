_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {}, bars = {}, gameplay = {}, player = {}, target = {}, focus = {}, pet = {},
    targettarget = {}, focustarget = {}, boss = {}, gf_party = {}, gf_raid = {}, gf_mythicraid = {},
}
_G.GetLocale = function() return "enUS" end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local Registry = assert(A.Registry, "Assistant registry missing")
A.GetContext = A.GetContext or function() return {} end

local function Trim(value)
    return tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local phraseCount, validExecutable, clarificationCount, nonExecutable = 0, 0, 0, 0
local parseErrors, invalidPlans = {}, {}

local function AuditActionPlan(plan, phrase, origin, lane)
    if type(plan) ~= "table" then return end
    local action = plan.action
    local key = type(action) == "table" and action.key or plan.actionKey
    if type(key) ~= "string" or key == "" then return end
    local normalized, err = A.NormalizeAssistantActionInput(key, plan.args or {})
    if type(normalized) ~= "table" then
        invalidPlans[#invalidPlans + 1] = table.concat({
            tostring(origin), string.format("%q", phrase), tostring(lane), tostring(key), tostring(err),
        }, " :: ")
        return
    end
    validExecutable = validExecutable + 1
end

for _, origin in ipairs(Registry:AllActions() or {}) do
    local phrases, seen = {}, {}
    local function Add(value)
        value = Trim(value)
        local folded = value:lower()
        if value ~= "" and not seen[folded] then
            seen[folded] = true
            phrases[#phrases + 1] = value
        end
    end
    for _, alias in ipairs(origin.aliases or {}) do Add(alias) end
    Add(origin.label)
    Add(origin.key)

    for _, phrase in ipairs(phrases) do
        phraseCount = phraseCount + 1
        local ok, parsed = pcall(A.Parse, phrase)
        if not ok then
            parseErrors[#parseErrors + 1] = tostring(origin.key) .. " :: " .. string.format("%q", phrase) .. " :: " .. tostring(parsed)
        elseif type(parsed) == "table" then
            if parsed.actionInputClarification == true then clarificationCount = clarificationCount + 1 end
            local before = validExecutable
            if parsed.kind == "action" then AuditActionPlan(parsed, phrase, origin.key, "direct") end
            for i, choice in ipairs(parsed.choices or {}) do
                if type(choice) == "table" and (choice.action ~= nil or choice.actionKey ~= nil or choice.kind == "action") then
                    AuditActionPlan(choice, phrase, origin.key, "choice" .. tostring(i))
                end
            end
            if before == validExecutable and parsed.actionInputClarification ~= true then
                nonExecutable = nonExecutable + 1
            end
        end
    end
end

local clearAnchor = A.Parse("clear custom anchor")
assert(type(clearAnchor) == "table" and clearAnchor.kind == "answer"
    and clearAnchor.status == "ambiguous" and clearAnchor.actionInputClarification == true
    and clearAnchor.action == nil,
    "clear custom anchor did not become a non-executable clarification")

local exactIncomplete = A.Parse("copy_profile")
assert(type(exactIncomplete) == "table" and exactIncomplete.kind == "answer"
    and exactIncomplete.status == "ambiguous" and exactIncomplete.actionInputClarification == true
    and exactIncomplete.action == nil,
    "an incomplete exact action key escaped as an executable plan")

if #parseErrors > 0 or #invalidPlans > 0 then
    print("assistant_action_alias_input_audit: failed phrases=" .. tostring(phraseCount)
        .. " parserErrors=" .. tostring(#parseErrors) .. " executableInvalid=" .. tostring(#invalidPlans))
    for i = 1, math.min(#parseErrors, 40) do print("parser error: " .. parseErrors[i]) end
    for i = 1, math.min(#invalidPlans, 80) do print("invalid plan: " .. invalidPlans[i]) end
    os.exit(1)
end

assert(validExecutable > 0, "alias sweep did not find any executable action plans")
assert(clarificationCount > 0, "alias sweep did not exercise action-input clarifications")

print("assistant_action_alias_input_audit: ok phrases=" .. tostring(phraseCount)
    .. " executableValid=" .. tostring(validExecutable)
    .. " executableInvalid=0 clarifications=" .. tostring(clarificationCount)
    .. " otherNonExecutable=" .. tostring(nonExecutable))
