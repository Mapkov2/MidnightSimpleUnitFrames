_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local A = assert(MSUF.Assistant, "Assistant missing")
local M = assert(MSUF.MSUF2, "MSUF2 missing")

local function status(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

local function contains(result, phrase)
    return type(result) == "table" and tostring(result.text or ""):find(phrase, 1, true) ~= nil
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[deepCopy(key, seen)] = deepCopy(item, seen) end
    return copy
end

local function deepEqual(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function firstDiff(left, right, path, seen)
    path = path or "MSUF_DB"
    if type(left) ~= type(right) then return path .. " type " .. type(left) .. " -> " .. type(right) end
    if type(left) ~= "table" then
        if left ~= right then return path .. " " .. tostring(left) .. " -> " .. tostring(right) end
        return nil
    end
    seen = seen or {}
    if seen[left] == right then return nil end
    seen[left] = right
    for key, value in pairs(left) do
        local diff = firstDiff(value, right[key], path .. "." .. tostring(key), seen)
        if diff then return diff end
    end
    for key in pairs(right) do
        if left[key] == nil then return path .. "." .. tostring(key) .. " nil -> " .. tostring(right[key]) end
    end
    return nil
end

local function profileSnapshot()
    local copy = deepCopy(_G.MSUF_DB)
    -- Conversation turns intentionally persist Assistant-only context. The
    -- release contract here is that no MSUF setting/profile owner is written.
    if type(copy) == "table" then copy.assistant = nil end
    return copy
end

local function resetConversation()
    A.pendingConfirmation = nil
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingFlow = nil
    A.lastAssistantPlanningContext = nil
    A.lastAssistantHelpContext = nil
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(ctx) == "table" then for key in pairs(ctx) do ctx[key] = nil end end
end

-- Role advice is persisted as an ordered, read-only plan.
resetConversation()
local profileBefore = profileSnapshot()
local guidance = A.HandleInput("recommend settings for healer")
assert(status(guidance) == "info", "healer guidance was not read-only: " .. tostring(status(guidance)))
assert(contains(guidance, "Role setup guidance"), "healer guidance title missing")
assert(contains(guidance, "Recommended order:"), "healer guidance did not show an ordered plan")
assert(contains(guidance, "1. Open Group Layout"), "healer first plan item is wrong")
assert(type(A.lastAssistantPlanningContext) == "table", "healer plan context was not persisted")
assert(type(A.lastAssistantPlanningContext.items) == "table" and #A.lastAssistantPlanningContext.items == 5,
    "healer plan did not persist five structured items")
local profileAfter = profileSnapshot()
assert(deepEqual(profileBefore, profileAfter), "healer guidance changed profile data: " .. tostring(firstDiff(profileBefore, profileAfter)))

for _, prompt in ipairs({ "which should I do first?", "which one first?" }) do
    local before = profileSnapshot()
    local answer = A.HandleInput(prompt)
    assert(status(answer) == "info", prompt .. " was not read-only: " .. tostring(status(answer)))
    assert(contains(answer, "Start with 1. Open Group Layout"), prompt .. " lost the first plan item")
    assert(contains(answer, "health, text, resource, and range readability"), prompt .. " lost the first-item reason")
    assert(not contains(answer, "resource, stripe"), prompt .. " assigned Debuff Stripe to Group Layout")
    assert(deepEqual(before, profileSnapshot()), prompt .. " changed profile data")
end

local beforeWhy = profileSnapshot()
local why = A.HandleInput("why that recommendation?")
assert(status(why) == "info", "recommendation explanation was not read-only")
assert(contains(why, "I recommend 1. Open Group Layout first because"), "recommendation explanation lost its referent")
assert(contains(why, "I did not change a setting"), "recommendation explanation omitted the no-change contract")
assert(deepEqual(beforeWhy, profileSnapshot()), "recommendation explanation changed profile data")

local beforeOpen = profileSnapshot()
local opened = A.HandleInput("open the first one")
assert(status(opened) == "navigated", "opening the first plan item did not report navigation: " .. tostring(status(opened)) .. " / " .. tostring(opened and opened.text))
assert(M.activeKey == "gf_layout", "opening the first healer item did not navigate to Group Layout: " .. tostring(M.activeKey))
assert(deepEqual(beforeOpen, profileSnapshot()), "opening a plan item changed profile data")

-- Every recommendation family keeps the same structured follow-up contract,
-- not just the generic role path.
local planningFamilies = {
    { prompt = "rogue ui setup", title = "Rogue UI guidance", first = "Open Class Resources" },
    { prompt = "mythic plus ui setup", title = "Content setup guidance", first = "Open Cast Bars" },
    { prompt = "healer mythic plus setup", title = "Combined setup guidance", first = "Open Group Layout" },
}
for _, family in ipairs(planningFamilies) do
    resetConversation()
    local beforeFamily = profileSnapshot()
    local familyPlan = A.HandleInput(family.prompt)
    assert(status(familyPlan) == "info", family.prompt .. " was not read-only")
    assert(contains(familyPlan, family.title), family.prompt .. " returned the wrong guidance family")
    assert(contains(familyPlan, "Recommended order:"), family.prompt .. " did not persist an ordered plan")
    assert(contains(familyPlan, "1. " .. family.first), family.prompt .. " has the wrong first plan item")

    local familyFirst = A.HandleInput("which one first?")
    assert(status(familyFirst) == "info" and contains(familyFirst, "Start with 1. " .. family.first),
        family.prompt .. " lost its first-item follow-up")
    local familyWhy = A.HandleInput("why that recommendation?")
    assert(status(familyWhy) == "info" and contains(familyWhy, "I recommend 1. " .. family.first .. " first because"),
        family.prompt .. " lost its explanation follow-up")
    local familyOpen = A.HandleInput("open the second one")
    assert(status(familyOpen) == "navigated",
        family.prompt .. " could not navigate to its second item: " .. tostring(status(familyOpen)))
    assert(deepEqual(beforeFamily, profileSnapshot()), family.prompt .. " follow-ups changed profile data")
end

-- A current-setting conversation stays attached to the exact numeric control
-- and answers advice/explanation questions without another write.
resetConversation()
local widthSetting = assert(A.Registry:GetSetting("target.width"), "Target Width setting missing")
local widthBefore = widthSetting.get()
local widthChange = A.HandleInput("set target width to 310")
assert(status(widthChange) == "applied", "target-width setup did not apply")
for _, prompt in ipairs({ "is that good?", "what do you recommend?", "why?" }) do
    local beforeAdvice = profileSnapshot()
    local advice = A.HandleInput(prompt)
    assert(status(advice) == "info", prompt .. " was not read-only")
    assert(contains(advice, "Target Width"), prompt .. " lost the exact setting referent")
    assert(contains(advice, "Current value: 310"), prompt .. " did not use current state")
    assert(deepEqual(beforeAdvice, profileSnapshot()), prompt .. " changed profile data")
end
local widthUndo = A.HandleInput("undo")
assert(status(widthUndo) == "applied", "target-width setup could not be reverted")
assert(widthSetting.get() == widthBefore, "target-width conversation did not restore its semantic value")

-- Questions that mention a candidate value are advice/state reads, never
-- implicit permission to write that value.
for _, prompt in ipairs({
    "what is the current target width?",
    "target width current value",
    "tell me the target width",
    "how wide is my target frame?",
    "should I set target width to 300?",
    "would it be better to set target width to 300?",
    "would it be better with target width 300?",
    "would I be better off with target width at 300?",
    "would it be better if target width were 300?",
    "is target width 300?",
    "did I set target width to 300?",
    "soll ich target width auf 300 setzen?",
    "sollte ich target width auf 300 setzen?",
    "darf ich target width auf 300 setzen?",
    "habe ich target width auf 300 gesetzt?",
    "ist target width 300?",
}) do
    local beforeQuestion = profileSnapshot()
    local beforeQuestionValue = widthSetting.get()
    local answer = A.HandleInput(prompt)
    assert(status(answer) == "info", prompt .. " did not produce a read-only answer: " .. tostring(status(answer)))
    assert(contains(answer, "Target Width"), prompt .. " resolved the wrong setting")
    assert(widthSetting.get() == beforeQuestionValue, prompt .. " changed Target Width")
    assert(deepEqual(beforeQuestion, profileSnapshot()), prompt .. " changed profile data")
end

local naturalDecisionQuestions = {
    { "is 300 a good target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width 300 a good value?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would target width 300 be better?", "target.width", "Target Width", "300 is higher than the current value" },
    { "do you recommend target width 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "what target width do you recommend?", "target.width", "Target Width" },
    { "should target width be 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is 300 too wide for target?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is my target frame too wide?", "target.width", "Target Width" },
    { "should target width be 5000?", "target.width", "Target Width", "outside this setting's allowed range" },
    { "is it good to show target name?", "target.showName", "Target Name" },
    { "is it better to show target name?", "target.showName", "Target Name" },
    { "would showing target name be better?", "target.showName", "Target Name" },
    { "do you recommend showing target name?", "target.showName", "Target Name" },
    { "should target name be on?", "target.showName", "Target Name" },
    { "is target name useful?", "target.showName", "Target Name" },
    { "is turning off target name a good idea?", "target.showName", "Target Name" },
    { "would hiding target name be better?", "target.showName", "Target Name" },
    { "do you think 300 is a good target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would you recommend target width 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would you suggest target width 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is 300 a sensible target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is 300 a reasonable target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width 300 sensible?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width 300 reasonable?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would target width 300 be sensible?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would target width 300 be safe?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width better at 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is 300 better for target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width too high at 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "do you think I should show target name?", "target.showName", "Target Name" },
    { "would you recommend showing target name?", "target.showName", "Target Name" },
    { "would you suggest showing target name?", "target.showName", "Target Name" },
    { "is showing target name a good idea?", "target.showName", "Target Name" },
    { "is showing target name sensible?", "target.showName", "Target Name" },
    { "is target name better on?", "target.showName", "Target Name" },
    { "is target name worth enabling?", "target.showName", "Target Name" },
    { "would target name be better on?", "target.showName", "Target Name" },
    { "do I need target name on?", "target.showName", "Target Name" },
    { "do you think target name should be on?", "target.showName", "Target Name" },
    { "is it a good idea to turn on target name?", "target.showName", "Target Name" },
    { "would turning on target name be useful?", "target.showName", "Target Name" },
    { "do you think target width should be 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "do you think I should set target width to 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "do you think target width at 300 is good?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would 300 be better for target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would it be better if I set target width to 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would it be better if target width was 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is it okay to set target width to 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is it fine to set target width to 300?", "target.width", "Target Width", "300 is higher than the current value" },
    { "could 300 work for target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "will 300 be too wide for target?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would 300 be too wide for target?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is 300 too much for target width?", "target.width", "Target Width", "300 is higher than the current value" },
    { "is target width 300 too much?", "target.width", "Target Width", "300 is higher than the current value" },
    { "would it help to show target name?", "target.showName", "Target Name" },
    { "is showing target name okay?", "target.showName", "Target Name" },
    { "should I leave target name on?", "target.showName", "Target Name" },
    { "would target name on be better?", "target.showName", "Target Name" },
    { "is target name on better?", "target.showName", "Target Name" },
    { "do I really need to show target name?", "target.showName", "Target Name" },
    { "would you keep target name on?", "target.showName", "Target Name" },
    { "should we show target name?", "target.showName", "Target Name" },
    { "what if I show target name?", "target.showName", "Target Name" },
    { "how about showing target name?", "target.showName", "Target Name" },
}
for _, case in ipairs(naturalDecisionQuestions) do
    local prompt, settingKey, label, detail = case[1], case[2], case[3], case[4]
    resetConversation()
    local setting = assert(A.Registry:GetSetting(settingKey), settingKey .. " missing")
    local beforeDecision = profileSnapshot()
    local beforeDecisionValue = setting.get()
    local answer = A.HandleInput(prompt)
    assert(status(answer) == "info", prompt .. " was treated as a command: " .. tostring(status(answer)))
    assert(contains(answer, label .. " decision help"), prompt .. " resolved the wrong decision subject")
    if detail then assert(contains(answer, detail), prompt .. " did not answer the proposed value") end
    assert(setting.get() == beforeDecisionValue, prompt .. " changed " .. settingKey)
    assert(deepEqual(beforeDecision, profileSnapshot()), prompt .. " changed profile data")
end

-- The broad question guard must not swallow ordinary or polite commands.
-- Prove both numeric and boolean mutations still reach the deterministic
-- controller, then restore each value through the public undo path.
for _, prompt in ipairs({
    "set target width to 305",
    "could you change target width to 306",
    "would you please change target width to 307",
}) do
    resetConversation()
    local beforeCommand = widthSetting.get()
    local changed = A.HandleInput(prompt)
    assert(status(changed) == "applied", prompt .. " was mistaken for a read-only question")
    assert(widthSetting.get() ~= beforeCommand, prompt .. " did not change Target Width")
    local reverted = A.HandleInput("undo")
    assert(status(reverted) == "applied" and widthSetting.get() == beforeCommand,
        prompt .. " could not be restored through undo")
end

resetConversation()
local targetName = assert(A.Registry:GetSetting("target.showName"), "Target Name setting missing")
local targetNameBefore = targetName.get()
local targetNamePrompt = targetNameBefore and "turn off target name" or "turn on target name"
local targetNameChange = A.HandleInput(targetNamePrompt)
assert(status(targetNameChange) == "applied", targetNamePrompt .. " was mistaken for a question")
assert(targetName.get() ~= targetNameBefore, targetNamePrompt .. " did not change Target Name")
local targetNameUndo = A.HandleInput("undo")
assert(status(targetNameUndo) == "applied" and targetName.get() == targetNameBefore,
    targetNamePrompt .. " could not be restored through undo")

-- Patch/version questions read runtime metadata instead of guessing or
-- pretending that the offline Assistant has live patch knowledge.
resetConversation()
local oldGetBuildInfo = _G.GetBuildInfo
_G.GetBuildInfo = function() return "12.0.1", "70000", "Jul 14 2026" end
local beforeVersion = profileSnapshot()
local version = A.HandleInput("what patch am I on?")
assert(status(version) == "info", "runtime patch question was not read-only")
assert(contains(version, "World of Warcraft client: 12.0.1 (build 70000)"),
    "runtime patch question did not report local build metadata")
assert(contains(version, "does not change MSUF"), "runtime patch answer omitted its read-only boundary")
assert(deepEqual(beforeVersion, profileSnapshot()), "runtime patch question changed profile data")
_G.GetBuildInfo = oldGetBuildInfo

-- Excluded ordinals must resolve the one positive choice deterministically.
local executions = { 0, 0, 0 }
local function action(index)
    local key = "planning_choice_test_" .. tostring(index)
    local contract = { kind = "none", fields = {}, source = "test.planningChoice.v1" }
    assert(type(A.ActionInputs) == "table" and type(A.ActionInputs.Contracts) == "table",
        "Assistant action input contracts were not loaded before the runtime")
    A.ActionInputs.Contracts[key] = contract
    return {
        key = key,
        label = "Planning Choice " .. tostring(index),
        mutability = "ephemeral",
        combatSafe = true,
        assistantInput = contract,
        assistantInputExplicit = true,
        assistantInputSource = contract.source,
        run = function()
            executions[index] = executions[index] + 1
            return true, "Ran planning choice " .. tostring(index) .. "."
        end,
    }
end

local choices = {
    { action = action(1), label = "First planning choice" },
    { action = action(2), label = "Second planning choice" },
    { action = action(3), label = "Third planning choice" },
}

for _, prompt in ipairs({ "not the first, the second", "second not first" }) do
    A.SetPendingChoices(choices)
    local result = A.HandleInput(prompt)
    assert(status(result) == "info" or status(result) == "applied",
        prompt .. " did not execute the positive choice: " .. tostring(status(result)) .. " / " .. tostring(result and result.text))
end
assert(executions[1] == 0 and executions[2] == 2 and executions[3] == 0,
    "excluded ordinal selected the wrong choice: " .. table.concat(executions, ","))

A.SetPendingChoices(choices)
local last = A.HandleInput("last one")
assert(status(last) == "info" or status(last) == "applied", "last one did not execute: " .. tostring(status(last)))
assert(executions[1] == 0 and executions[2] == 2 and executions[3] == 1,
    "last one selected the wrong choice: " .. table.concat(executions, ","))

-- A pure exclusion does not imply a choice when more than one candidate remains.
A.SetPendingChoices(choices)
local ambiguous = A.HandleInput("not the first")
assert(status(ambiguous) == "ambiguous", "pure exclusion should stay ambiguous: " .. tostring(status(ambiguous)))
assert(executions[1] == 0 and executions[2] == 2 and executions[3] == 1,
    "pure exclusion executed a choice: " .. table.concat(executions, ","))

print(string.format(
    "assistant_planning_followup_regression: ok rolePlanItems=5 planningFamilies=%d naturalDecisions=%d commandControls=4 exclusions=3 versionReads=1",
    #planningFamilies,
    #naturalDecisionQuestions
))
