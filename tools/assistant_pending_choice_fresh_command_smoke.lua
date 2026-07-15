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
local registry = assert(A.Registry, "Assistant Registry missing")
local targetName = assert(registry:GetSetting("target.showName"), "target.showName setting missing")
local targetPower = assert(registry:GetSetting("target.showPower"), "target.showPower setting missing")
local mythicDebuffFilter = assert(registry:GetSetting("gf_mythicraid.auras.debuff.filterToken"),
    "mythic raid debuff filter setting missing")

targetName.set(false)
targetPower.set(true)

-- The dashboard fixture intentionally leaves a real page open. This setup is
-- testing a scope-free choice, so remove both visible-page and remembered
-- conversational scope before asking the deliberately terse first question.
local oldActiveKey, oldGfScope = M.activeKey, M.gfScope
M.activeKey, M.gfScope = nil, nil
local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
if type(ctx) == "table" then for key in pairs(ctx) do ctx[key] = nil end end

local first = assert(A.Submit("show name"), "ambiguous setup command returned no result")
assert((first.status or first.result) == "ambiguous", "'show name' must create a pending choice")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices > 1, "pending name choices missing")

local filterBefore = mythicDebuffFilter.get()
local second = assert(A.Submit("show important debuffs"), "fresh planning command returned no result")
assert((second.status or second.result) == "info", "fresh planning command was not fail-closed info")
assert(tostring(second.text or ""):find("Aura filter planning", 1, true),
    "fresh planning command did not replace the stale choice with Aura filter planning")
assert(mythicDebuffFilter.get() == filterBefore,
    "fresh planning command leaked into page context and changed Mythic Raid Debuff Filter")
assert(targetName.get() == false, "fresh planning command leaked into the pending choice and enabled Target Name")
assert(A.pendingChoices == nil, "stale pending choices survived the fresh planning command")
assert(A.pendingCandidates == nil, "stale pending candidates survived the fresh planning command")

local third = assert(A.Submit("turn off target power"), "fresh setting command returned no result")
assert((third.status or third.result) == "applied", "fresh setting command was not applied")
assert(targetName.get() == false, "fresh setting command leaked into the old pending choice and enabled Target Name")
local thirdText = tostring(third.text or "")
assert(thirdText:find("Target Power", 1, true), "fresh command was not routed as a Target Power command: " .. thirdText)
assert(not thirdText:find("Target Name", 1, true), "fresh command applied the stale Target Name choice: " .. thirdText)
assert(A.pendingChoices == nil, "stale pending choices survived the fresh command")
assert(A.pendingCandidates == nil, "stale pending candidates survived the fresh command")

local undone = assert(A.Submit("undo"), "undo returned no result")
assert((undone.status or undone.result) == "applied", "undo did not apply")
assert(targetName.get() == false, "undo changed unrelated Target Name state")
assert(targetPower.get() == true, "fresh command or undo unexpectedly changed the Target Power visibility toggle")

-- A new ecosystem question must replace an unrelated stale setting choice.
-- This is the exact wording from the reported Assistant misroute.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
M.activeKey, M.gfScope = nil, nil
ctx = type(A.GetContext) == "function" and A.GetContext() or nil
if type(ctx) == "table" then for key in pairs(ctx) do ctx[key] = nil end end
local addonChoice = assert(A.Submit("show name"), "addon regression setup returned no result")
assert((addonChoice.status or addonChoice.result) == "ambiguous", "addon regression did not create a stale setting choice")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices > 1, "addon regression pending choice missing")
local addonTargetNameBefore, addonTargetPowerBefore = targetName.get(), targetPower.get()
local addonReply = assert(A.Submit("what other addons work well with msuf?"), "addon companion question returned no result")
local addonText = tostring(addonReply.text or "")
assert((addonReply.status or addonReply.result) == "info", "addon companion question was not read-only info")
assert(addonText:find("Addons that pair well with MSUF", 1, true), "addon companion heading missing: " .. addonText)
assert(addonText:find("Clique", 1, true) and addonText:find("BetterFriendList", 1, true)
    and addonText:find("Enhance QoL (EQoL)", 1, true), "addon companion answer is incomplete: " .. addonText)
assert(not addonText:find("I found this in MSUF", 1, true)
    and not addonText:find("I found these MSUF matches", 1, true), "addon question fell through to setting search")
assert(addonReply.searchResults == nil, "addon companion answer returned setting-search follow-ups")
assert(A.pendingChoices == nil and A.pendingCandidates == nil, "stale setting choice survived addon companion question")
assert(A.pendingResults == nil and A.pendingSelectedResult == nil, "addon companion answer created pending search state")
assert(targetName.get() == addonTargetNameBefore and targetPower.get() == addonTargetPowerBefore,
    "addon companion question changed a gameplay setting")
assert(#A.undoStack == 0, "addon companion question created an undoable mutation")

local function assertAddonTopicSwitch(result, label, expectedHeading, expectNotice)
    result = assert(result, label .. ": addon topic switch returned no result")
    local text = tostring(result.text or "")
    assert((result.status or result.result) == "info", label .. ": addon topic switch was not read-only info")
    assert(text:find(expectedHeading, 1, true), label .. ": expected addon guidance heading missing: " .. text)
    assert(not text:find("I found this in MSUF", 1, true)
        and not text:find("I found these MSUF matches", 1, true), label .. ": addon topic fell through to setting search")
    assert(result.searchResults == nil, label .. ": addon topic returned setting-search follow-ups")
    assert((text:find("I cleared the previous pending choice or change because you started a new topic.", 1, true) ~= nil)
        == expectNotice, label .. ": pending-state notice did not match the actual state")
    assert(A.pendingConfirmation == nil, label .. ": pending confirmation survived the topic switch")
    assert(A.pendingChoices == nil and A.pendingCandidates == nil, label .. ": pending choice survived the topic switch")
    assert(A.pendingFlow == nil, label .. ": pending flow survived the topic switch")
    assert(A.pendingResults == nil and A.pendingSelectedResult == nil, label .. ": pending result survived the topic switch")
    assert(A.lastAssistantHelpContext == nil and A.lastAssistantPlanningContext == nil,
        label .. ": stale help/planning context survived the topic switch")
end

-- A plain coexistence/install statement is context, not a new addon-help
-- request. It must not take the early topic-switch lane or clear a confirmation.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
local statementFilterBefore = mythicDebuffFilter.get()
local statementConfirmation = assert(A.Submit("apply performance aura preset"), "statement boundary setup returned no result")
assert((statementConfirmation.status or statementConfirmation.result) == "confirmation_needed",
    "statement boundary setup did not require confirmation")
assert(A.pendingConfirmation ~= nil, "statement boundary setup left no pending confirmation")
assert(not A.Knowledge.LooksLikeComplementaryAddonQuestion("I use WeakAuras with MSUF."),
    "plain addon coexistence statement was classified as an addon-help request")
local statementReply = assert(A.Submit("I use WeakAuras with MSUF."), "statement boundary returned no result")
local statementText = tostring(statementReply.text or "")
assert((statementReply.status or statementReply.result) == "confirmation_needed",
    "plain addon statement escaped the existing confirmation")
assert(A.pendingConfirmation ~= nil, "plain addon statement cleared the existing confirmation")
assert(not statementText:find("Addons that pair well with MSUF", 1, true)
    and not statementText:find("Addon overlap and compatibility with MSUF", 1, true)
    and not statementText:find("Addon compatibility note", 1, true)
    and not statementText:find("I cleared the previous pending choice or change because you started a new topic.", 1, true),
    "plain addon statement took the early addon topic-switch lane: " .. statementText)
assert(mythicDebuffFilter.get() == statementFilterBefore, "plain addon statement applied the pending Aura preset")
assert(#A.undoStack == 0, "plain addon statement created an undoable mutation")

-- An explicit unsafe change confirmation must not consume a natural addon
-- question as approval. The topic switch cancels the unconfirmed operation.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
local presetFilterBefore = mythicDebuffFilter.get()
local presetConfirmation = assert(A.Submit("apply performance aura preset"), "preset confirmation setup returned no result")
assert((presetConfirmation.status or presetConfirmation.result) == "confirmation_needed",
    "preset confirmation setup did not require confirmation")
assert(A.pendingConfirmation ~= nil, "preset confirmation setup left no pending confirmation")
assertAddonTopicSwitch(
    A.Submit("Which EQoL settings overlap with MSUF?"),
    "confirmation topic switch",
    "Addon overlap and compatibility with MSUF",
    true
)
assert(mythicDebuffFilter.get() == presetFilterBefore, "addon topic switch applied the unconfirmed Aura preset")
assert(#A.undoStack == 0, "confirmation topic switch created an undoable mutation")

-- Free-form profile workflows are especially sensitive: without this early
-- route the question can become the destination profile name.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
local profileCountBefore = 0
for _ in pairs((_G.MSUF_DB and _G.MSUF_DB.profiles) or {}) do profileCountBefore = profileCountBefore + 1 end
local profileCopy = assert(A.Submit("copy from profile Default"), "profile-copy flow setup returned no result")
assert(type(A.pendingFlow) == "table", "profile-copy setup did not create a pending destination flow: " .. tostring(profileCopy.text))
assertAddonTopicSwitch(
    A.Submit("Which addons work well with MidnightSimpleUnitFrames?"),
    "profile-copy topic switch",
    "Addons that pair well with MSUF",
    true
)
local profileCountAfter = 0
for _ in pairs((_G.MSUF_DB and _G.MSUF_DB.profiles) or {}) do profileCountAfter = profileCountAfter + 1 end
assert(profileCountAfter == profileCountBefore, "addon question was used as a profile-copy destination")
assert(#A.undoStack == 0, "profile-copy topic switch created an undoable mutation")

-- Starting this read-only topic with no pending operation must not close an
-- unrelated large-text panel. It should still replace stale help context.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
local oldLargeTextPanel = A.largeTextPanel
local panelCloseCount = 0
A.largeTextPanel = { Hide = function() panelCloseCount = panelCloseCount + 1 end }
A.lastAssistantHelpContext = { title = "stale help" }
A.lastAssistantPlanningContext = { title = "stale plan" }
assertAddonTopicSwitch(
    A.Submit("what other addons work well with msuf?"),
    "clean topic switch",
    "Addons that pair well with MSUF",
    false
)
assert(panelCloseCount == 0, "clean addon question closed an unrelated large-text panel")
A.largeTextPanel = oldLargeTextPanel

-- Reproduce the command-surface planning prefix with the group-Aura context
-- retained by its earlier anchor change. That stale lastUnit/lastSetting used
-- to let the immediate Aura lane interpret "important" as a concrete Mythic
-- Raid filter value. Every prompt below must remain planning-only, including
-- the final exact phrase from the full command-surface audit.
A.StartNewTask()
A.undoStack, A.redoStack = {}, {}
M.activeKey, M.gfScope = "home", "party"
ctx = type(A.GetContext) == "function" and A.GetContext() or nil
assert(type(ctx) == "table", "Assistant context missing for sequenced planning regression")
ctx.lastAction = "change"
ctx.lastActionUndoable = true
ctx.lastActionLabel = "Change Aura layout"
ctx.lastSetting = "gf_mythicraid.auras.buff.anchor"
ctx.lastValue = "BOTTOMLEFT"
ctx.lastDirection = "left"
ctx.lastFrameType = "groupAura"
ctx.lastUnit = "mythicraid"
ctx.lastCategory = "Mythic Raid / Group Auras"
ctx.lastMentionedUnit = "party"
ctx.lastMentionedCategory = "Party / Group Auras"
ctx.lastSubjectTurn = 84
ctx.lastMentionedTurn = 84
ctx.turnSerial, ctx.lastTurnSerial = 149, 149

local sequencedPlanning = {
    { "can you diagnose my ui", "Diagnostic planning" },
    { "make this less cluttered", "Clutter planning" },
    { "hide useless buffs", "Aura filter planning" },
    { "show important debuffs", "Aura filter planning" },
}
filterBefore = mythicDebuffFilter.get()
for i = 1, #sequencedPlanning do
    local prompt, heading = sequencedPlanning[i][1], sequencedPlanning[i][2]
    local result = assert(A.Submit(prompt), prompt .. ": sequenced planning result missing")
    assert((result.status or result.result) == "info", prompt .. ": sequenced planning was not read-only info")
    assert(tostring(result.text or ""):find(heading, 1, true),
        prompt .. ": expected " .. heading .. ", got: " .. tostring(result.text or ""))
end
assert(mythicDebuffFilter.get() == filterBefore,
    "sequenced broad planning changed the retained Mythic Raid Debuff Filter")
assert(#A.undoStack == 0, "sequenced broad planning created an undoable mutation")

M.activeKey, M.gfScope = oldActiveKey, oldGfScope

print("assistant_pending_choice_fresh_command_smoke: ok")
