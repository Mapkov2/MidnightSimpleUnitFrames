_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local function resultStatus(result)
    return result and (result.status or result.result)
end

local function assertDidNotRecover(label, result)
    local status = resultStatus(result)
    local output = tostring(result and result.text or "")
    local detail = A.lastAssistantJobError and (tostring(A.lastAssistantJobError.message or "")
        .. "\n" .. tostring(A.lastAssistantJobError.stack or "")) or ""
    assert(status ~= "failed", label .. ": failed: " .. output .. "\n" .. detail)
    assert(not output:find("couldn't finish a reliable answer", 1, true), label .. ": entered recovery: " .. output)
    assert(not output:find("could not finish a reliable answer", 1, true), label .. ": entered recovery: " .. output)
end

A.StartNewTask()
local shorten = assert(A.SubmitDeferred("shorten target name"))
assertDidNotRecover("shorten target name", shorten)
assert(resultStatus(shorten) == "ambiguous", "shorten target name should ask for length/direction")
assert(tostring(shorten.text):find("How many letters", 1, true), "shorten target name lost its specific clarification")
assert(A.IsBusy() == false, "shorten target name left Assistant busy")

A.StartNewTask()
local layer = assert(Registry:GetSetting("gf_party.nameTextLayer"), "Party Name Text Layer missing")
local initial = tonumber(layer.get()) or 0
local first = assert(A.SubmitDeferred("increase name strata for party"))
assertDidNotRecover("increase name strata for party", first)
assert(resultStatus(first) == "applied" or resultStatus(first) == "unchanged", "first layer request did not execute")
local afterFirst = tonumber(layer.get()) or initial
assert(afterFirst > initial, "first layer request did not increase Party Name Text Layer")

local more = assert(A.SubmitDeferred("more"))
assertDidNotRecover("more after Party Name Text Layer", more)
assert(resultStatus(more) == "applied", "more follow-up did not apply: " .. tostring(more.text))
assert((tonumber(layer.get()) or afterFirst) > afterFirst, "more did not repeat the layer increase")
assert(A.IsBusy() == false, "more follow-up left Assistant busy")

-- Production regression for the reported bar-outline failure. This exercises
-- the public surface (not parser internals), including true deferred slices.
local M = assert(_G.MSUF_NS.MSUF2, "MSUF2 missing")
local P = assert(A.Parser, "Assistant parser missing")
local sharedOutline = assert(Registry:GetSetting("general.barOutlineColor"), "Shared Bar Outline Color missing")
local playerOutline = assert(Registry:GetSetting("barScope.player.barOutlineColor"), "Player Bar Outline Color missing")
local targetOutline = assert(Registry:GetSetting("barScope.target.barOutlineColor"), "Target Bar Outline Color missing")
local partyOutline = assert(Registry:GetSetting("barScope.gf_party.barOutlineColor"), "Party Bar Outline Color missing")
local raidOutline = assert(Registry:GetSetting("barScope.gf_raid.barOutlineColor"), "Raid Bar Outline Color missing")

local function setRGB(setting, r, g, b)
    setting.set({ r = r, g = g, b = b, label = (r == 1 and g == 0 and b == 0) and "red" or "black" })
end

local function assertRGB(label, setting, r, g, b)
    local value = assert(setting.get(), label .. ": color missing")
    local actualR = tonumber(value.r or value[1]) or -1
    local actualG = tonumber(value.g or value[2]) or -1
    local actualB = tonumber(value.b or value[3]) or -1
    assert(math.abs(actualR - r) < 0.0001 and math.abs(actualG - g) < 0.0001 and math.abs(actualB - b) < 0.0001,
        string.format("%s: expected %.3f/%.3f/%.3f, got %.3f/%.3f/%.3f", label, r, g, b, actualR, actualG, actualB))
end

local function prepare(page)
    assert(A.IsBusy() == false, "Assistant unexpectedly busy before test request")
    A.StartNewTask()
    M.activeKey = page or "home"
    A.lastAssistantJobError = nil
    setRGB(sharedOutline, 0, 0, 0)
    setRGB(playerOutline, 0, 0, 0)
    setRGB(targetOutline, 0, 0, 0)
    setRGB(partyOutline, 0, 0, 0)
    setRGB(raidOutline, 0, 0, 0)
end

local function assertAllOutlinesBlack(label)
    assertRGB(label .. " shared", sharedOutline, 0, 0, 0)
    assertRGB(label .. " Player", playerOutline, 0, 0, 0)
    assertRGB(label .. " Target", targetOutline, 0, 0, 0)
    assertRGB(label .. " Party", partyOutline, 0, 0, 0)
    assertRGB(label .. " Raid", raidOutline, 0, 0, 0)
end

local trackedOutlines = {
    { name = "shared", setting = sharedOutline },
    { name = "Player", setting = playerOutline },
    { name = "Target", setting = targetOutline },
    { name = "Party", setting = partyOutline },
    { name = "Raid", setting = raidOutline },
}

local function instrumentOutlineWrites()
    local counts, originals = {}, {}
    for i = 1, #trackedOutlines do
        local entry = trackedOutlines[i]
        counts[i] = 0
        originals[i] = entry.setting.set
        entry.setting.set = function(...)
            counts[i] = counts[i] + 1
            return originals[i](...)
        end
    end
    return function()
        for i = 1, #trackedOutlines do trackedOutlines[i].setting.set = originals[i] end
    end, function(label)
        for i = 1, #trackedOutlines do
            assert(counts[i] == 0,
                label .. ": unexpectedly called the " .. trackedOutlines[i].name .. " outline setter "
                    .. tostring(counts[i]) .. " time(s)")
        end
    end
end

local syncPages = { "home", "opt_bars", "opt_colors", "gf_layout", "uf_player" }
for i = 1, #syncPages do
    local page = syncPages[i]
    prepare(page)
    local result = assert(A.Submit("make the outline color for bars red"))
    assertDidNotRecover("sync shared bar outline on " .. page, result)
    assert(resultStatus(result) == "applied", "sync shared request did not apply on " .. page .. ": " .. tostring(result.text))
    assertRGB("sync shared request on " .. page, sharedOutline, 1, 0, 0)
end

local positivePrompts = {
    "change the outline color of the bars to red",
    "change the color of the bar outlines to red",
    "please make the bar outlines red",
    "can you make the outline color for bars red",
    "could you please change the bar outline color to red",
    "would you set bar outlines red",
    "i want red outlines around my bars",
    "bar outline red",
    "red bar outlines",
    "turn the bar outlines red",
    "give the bars red outlines",
    "set red as the bar outline color",
    "for bar outlines use red",
    "bar outline color = red",
    "set the bar outline color rgb 255 0 0",
    "make the oultine colro for bars red",
    "mach die Konturfarbe der Balken rot",
    "setze die Konturfarbe der Leisten rot",
    "mache die Konturfarbe der Balken rot",
    "mach die Balkenkontur rot",
    "rote Balkenkontur",
}
for i = 1, #positivePrompts do
    local prompt = positivePrompts[i]
    prepare("home")
    local result = assert(A.Submit(prompt))
    assertDidNotRecover("positive bar outline: " .. prompt, result)
    assert(resultStatus(result) == "applied", "positive bar outline did not apply: " .. prompt .. " -> " .. tostring(result.text))
    assertRGB("positive bar outline: " .. prompt, sharedOutline, 1, 0, 0)
end

local noWritePrompts = {
    "the bar outline is red",
    "I like red bar outlines",
    "is the bar outline red?",
    "I don't want red bar outlines",
    "do not make the bar outlines red",
    "don't change the bar outline to red",
    "never set bar outlines red",
    "make the bar outline not red",
    "make bar outlines anything but red",
    "I want to know whether red bar outlines are possible",
    "should I make bar outlines red",
    "do you want red bar outlines",
    "say make bar outlines red",
    "the example command is make bar outlines red",
    "when I say make bar outlines red do nothing",
    "make bar outlines red or blue",
    "make bar outlines #ff0000 or #0000ff",
    "make bar outlines #ff0000/#0000ff",
    "make bar outlines #ff0000, #0000ff",
    "make bar outlines rgb 255 0 0, rgb 0 0 255",
    "make bar outlines 255,0,0, 0,0,255",
    "make bar outlines #ff0000 instead of #0000ff",
    "make bar outlines red instead of #0000ff",
    "make bar outlines #ff0000 instead of blue",
    "make player or target bar outlines red",
    "make bar outlines red or leave unchanged",
    "if bar outlines are blue make them red",
    "set bar outline color red and thickness 2",
    "set general bar outline color red channel to 20",
    "set bars class power outline color red channel to 20",
    "set class power bar outline color red",
}
for i = 1, #noWritePrompts do
    local prompt = noWritePrompts[i]
    prepare("home")
    local restoreWrites, assertNoWrites = instrumentOutlineWrites()
    local result = assert(A.Submit(prompt))
    restoreWrites()
    assertDidNotRecover("no-write bar outline: " .. prompt, result)
    assert(resultStatus(result) ~= "applied" and resultStatus(result) ~= "unchanged",
        "unsafe request was treated as a mutation: " .. prompt .. " -> " .. tostring(result.text))
    assertAllOutlinesBlack("no-write bar outline: " .. prompt)
    assertNoWrites("no-write bar outline: " .. prompt)
end

local deicticPrompts = {
    "make the bar outline red here",
    "make this page's bar outline red",
    "make this frame's bar outline red",
    "make the current frame bar outline red",
    "make the selected frame bar outline red",
}
for _, page in ipairs({ "uf_player", "uf_target", "home" }) do
    for i = 1, #deicticPrompts do
        local prompt = deicticPrompts[i]
        prepare(page)
        local restoreWrites, assertNoWrites = instrumentOutlineWrites()
        local result = assert(A.Submit(prompt))
        restoreWrites()
        assertDidNotRecover("deictic bar outline on " .. page, result)
        assert(resultStatus(result) ~= "applied" and resultStatus(result) ~= "unchanged",
            "deictic scope silently mutated on " .. page .. ": " .. prompt)
        assertRGB("deictic shared scope on " .. page, sharedOutline, 0, 0, 0)
        assertRGB("deictic player scope on " .. page, playerOutline, 0, 0, 0)
        assertRGB("deictic target scope on " .. page, targetOutline, 0, 0, 0)
        assertNoWrites("deictic bar outline on " .. page .. ": " .. prompt)
    end
end

prepare("home")
setRGB(partyOutline, 0, 0, 0)
setRGB(raidOutline, 0, 0, 0)
local groupChoice = assert(A.Submit("make group bar outlines red"))
assert(resultStatus(groupChoice) == "ambiguous", "bare group did not ask Party/Raid: " .. tostring(groupChoice.text))
assert(#(A.pendingChoices or {}) == 2, "bare group did not retain exactly two choices")
assert(A.pendingChoices[1].value and A.pendingChoices[1].value.r == 1,
    "bare group choice lost requested red value")
local groupSelected = assert(A.Submit("1"))
assert(resultStatus(groupSelected) == "applied", "bare group selection did not apply retained color")
assertRGB("selected Party outline", partyOutline, 1, 0, 0)
assertRGB("unselected Raid outline", raidOutline, 0, 0, 0)
assertRGB("bare group shared outline", sharedOutline, 0, 0, 0)

prepare("home")
setRGB(partyOutline, 0, 0, 0)
setRGB(raidOutline, 0, 0, 0)
local germanGroupChoice = assert(A.Submit("mach die Konturfarbe der Gruppe rot"))
assert(resultStatus(germanGroupChoice) == "ambiguous" and #(A.pendingChoices or {}) == 2,
    "German Gruppe did not retain Party/Raid choices: " .. tostring(germanGroupChoice.text))

prepare("home")
setRGB(playerOutline, 0, 0, 0)
local germanPlayer = assert(A.Submit("mach die Konturfarbe des Spielers rot"))
assert(resultStatus(germanPlayer) == "applied", "German Spieler scope did not apply: " .. tostring(germanPlayer.text))
assertRGB("German Player outline", playerOutline, 1, 0, 0)
assertRGB("German Player shared outline", sharedOutline, 0, 0, 0)

prepare("home")
setRGB(playerOutline, 0, 0, 0)
setRGB(targetOutline, 0, 0, 0)
local multiScope = assert(A.Submit("make player and target bar outlines red"))
assert(resultStatus(multiScope) == "ambiguous" and #(A.pendingChoices or {}) == 2,
    "explicit multi-scope request did not preserve structured choices")
assert(A.pendingChoices[2].value and A.pendingChoices[2].value.r == 1,
    "explicit multi-scope choice lost requested red value")
local targetSelected = assert(A.Submit("2"))
assert(resultStatus(targetSelected) == "applied", "multi-scope selection did not apply")
assertRGB("selected Target outline", targetOutline, 1, 0, 0)
assertRGB("unselected Player outline", playerOutline, 0, 0, 0)

-- Purpose text must follow the declared control type before broad label words.
local purpose = assert(A.RouterPrivate and A.RouterPrivate.RegistrySettingPurpose, "RegistrySettingPurpose missing")
local colorPurpose = purpose({ setting = sharedOutline }):lower()
assert(colorPurpose:find("color", 1, true) and not colorPurpose:find("thick", 1, true),
    "color purpose was confused with outline thickness: " .. colorPurpose)
local booleanPurpose = purpose({ setting = assert(Registry:GetSetting("player.powerBarBorderEnabled")) }):lower()
assert(booleanPurpose:find("on or off", 1, true) and not booleanPurpose:find("style", 1, true),
    "boolean border purpose was confused with border style: " .. booleanPurpose)
local enumPurpose = purpose({ setting = assert(Registry:GetSetting("fontScope.shared.outline")) }):lower()
assert(enumPurpose:find("chooses", 1, true) and not enumPurpose:find("thick", 1, true),
    "enum outline purpose was confused with outline thickness: " .. enumPurpose)
local numberPurpose = purpose({ setting = assert(Registry:GetSetting("gf_party.groupBorderA")) }):lower()
assert(numberPurpose:find("opacity", 1, true) and not numberPurpose:find("style", 1, true),
    "numeric border opacity purpose was confused with border style: " .. numberPurpose)

prepare("home")
local search = assert(A.Submit("search bar outline color"))
local sharedResultIndex
for i = 1, #(search.searchResults or {}) do
    if search.searchResults[i].settingKey == "general.barOutlineColor" then sharedResultIndex = i; break end
end
assert(sharedResultIndex, "public search did not return shared Bar Outline Color")
local why = assert(A.Submit("why result " .. tostring(sharedResultIndex)))
local whyText = tostring(why.text):lower()
assert(whyText:find("color", 1, true) and not whyText:find("thick", 1, true),
    "public explanation confused Bar Outline Color with thickness: " .. whyText)

-- Install a deterministic next-frame queue so SubmitDeferred must return
-- queued and the real job coroutine/yield trampoline is exercised.
local oldTimer = _G.C_Timer and _G.C_Timer.NewTimer
local oldPreciseTime = _G.GetTimePreciseSec
local oldBudget = A.jobBudgetMs
local oldMaxSteps = A.jobMaxStepsPerFrame
_G.C_Timer = _G.C_Timer or {}
local timerQueue, timerHead = {}, 1
_G.C_Timer.NewTimer = function(_, callback)
    local token = { cancelled = false }
    timerQueue[#timerQueue + 1] = function() if not token.cancelled then callback() end end
    return { Cancel = function() token.cancelled = true end }
end
local fakeClock = 0
_G.GetTimePreciseSec = function()
    fakeClock = fakeClock + 0.00025
    return fakeClock
end
A.jobBudgetMs = 0.1
A.jobMaxStepsPerFrame = 4

local function resetTimerQueue()
    local drained = 0
    while timerHead <= #timerQueue and drained < 1000 do
        local callback = timerQueue[timerHead]
        timerHead = timerHead + 1
        drained = drained + 1
        callback()
    end
    assert(timerHead > #timerQueue, "timer queue could not drain before reset")
    timerQueue, timerHead = {}, 1
end

local function pumpUntil(done, label, limit)
    local ticks = 0
    limit = limit or 20000
    while not done() and timerHead <= #timerQueue and ticks < limit do
        local callback = timerQueue[timerHead]
        timerHead = timerHead + 1
        ticks = ticks + 1
        callback()
    end
    assert(done(), label .. ": deferred callback did not complete after " .. tostring(ticks) .. " ticks")
    assert(A.IsBusy() == false, label .. ": Assistant stayed busy")
    return ticks
end

local settings = Registry:AllSettings()
local asyncPages = { "home", "opt_bars", "opt_colors", "gf_layout", "uf_player" }
for _, phase in ipairs({ "cold", "warm" }) do
    if phase == "cold" then
        P._registryExactAliasSettings = nil
        P._registryExactAliasCount = nil
        P._registryExactAliasIndex = nil
        P._registryExactAliasLookupCache = nil
        P._exactColorSettingIndexSettings = nil
        P._exactColorSettingIndexCount = nil
        P._exactColorSettingIndex = nil
    else
        assert(P._EnsureRegistryExactAliasIndex(settings), "could not warm exact-alias index")
        assert(P._EnsureExactColorSettingIndex(settings), "could not warm exact-color index")
    end
    for i = 1, #asyncPages do
        local page = asyncPages[i]
        prepare(page)
        resetTimerQueue()
        local callbackCount, completed = 0, nil
        local queued = assert(A.SubmitDeferred("make the outline color for bars red", function(result)
            callbackCount = callbackCount + 1
            completed = result
        end))
        assert(resultStatus(queued) == "queued" and callbackCount == 0,
            phase .. " deferred request did not enter the real queue on " .. page)
        pumpUntil(function() return completed ~= nil end, phase .. " deferred request on " .. page)
        assert(callbackCount == 1 and resultStatus(completed) == "applied",
            phase .. " deferred request did not apply exactly once on " .. page .. ": " .. tostring(completed and completed.text))
        assertDidNotRecover(phase .. " deferred request on " .. page, completed)
        assertRGB(phase .. " deferred shared request on " .. page, sharedOutline, 1, 0, 0)
    end
end

-- Safety must use the same genuinely queued lane as successful mutations;
-- otherwise an immediate-path guard could hide a deferred-path regression.
for _, prompt in ipairs({
    "do not make the bar outlines red",
    "make bar outlines #ff0000 or #0000ff",
    "set bar outline color red and thickness 2",
    "set general bar outline color red channel to 20",
    "set bars class power outline color red channel to 20",
    "set class power bar outline color red",
}) do
    prepare("uf_player")
    resetTimerQueue()
    local restoreWrites, assertNoWrites = instrumentOutlineWrites()
    local callbackCount, completed = 0, nil
    local queued = assert(A.SubmitDeferred(prompt, function(result)
        callbackCount = callbackCount + 1
        completed = result
    end))
    assert(resultStatus(queued) == "queued" and callbackCount == 0,
        "queued safety request bypassed the real queue: " .. prompt)
    pumpUntil(function() return completed ~= nil end, "queued safety request: " .. prompt)
    restoreWrites()
    assert(callbackCount == 1, "queued safety callback did not complete exactly once: " .. prompt)
    assertDidNotRecover("queued safety request: " .. prompt, completed)
    assert(resultStatus(completed) ~= "applied" and resultStatus(completed) ~= "unchanged",
        "queued safety request mutated: " .. prompt .. " -> " .. tostring(completed and completed.text))
    assertAllOutlinesBlack("queued safety request: " .. prompt)
    assertNoWrites("queued safety request: " .. prompt)
end

-- Misspelling forces the full fuzzy registry fallback. A tiny budget makes
-- that scan yield many times, proving there is no Lua 5.1 yield-through-pcall.
prepare("home")
resetTimerQueue()
P._registryExactAliasSettings = nil
P._registryExactAliasCount = nil
P._registryExactAliasIndex = nil
P._registryExactAliasLookupCache = nil
local typoResult
local typoQueued = assert(A.SubmitDeferred("make the bar outlin color red", function(result) typoResult = result end))
assert(resultStatus(typoQueued) == "queued", "fuzzy typo request bypassed the deferred queue")
local typoTicks = pumpUntil(function() return typoResult ~= nil end, "yielding fuzzy typo", 30000)
assert(typoTicks > 1, "fuzzy typo did not exercise a yielded job")
assert(resultStatus(typoResult) == "applied", "yielding fuzzy typo did not apply: " .. tostring(typoResult and typoResult.text))
assertDidNotRecover("yielding fuzzy typo", typoResult)
assertRGB("yielding fuzzy typo", sharedOutline, 1, 0, 0)
assert(P._allowFuzzyAliasMatch ~= true and not P.FuzzyAliasMatchEnabled(), "fuzzy matcher leaked after successful yielded scan")

-- A worker failure after an actual yield must also restore the fuzzy scope and
-- finish the public job exactly once instead of poisoning later requests.
prepare("home")
resetTimerQueue()
P._registryExactAliasSettings = nil
P._registryExactAliasCount = nil
P._registryExactAliasIndex = nil
P._registryExactAliasLookupCache = nil
local originalAliasCandidates = P.ParseRegistryAliasCandidates
local previousSharedFuzzy = P._allowFuzzyAliasMatch
P.ParseRegistryAliasCandidates = function(...)
    if P.FuzzyAliasMatchEnabled() then
        A.MaybeYield(true)
        error("synthetic yielded fuzzy failure")
    end
    return originalAliasCandidates(...)
end
local failedResult, failedCallbackCount = nil, 0
local failedQueued = assert(A.SubmitDeferred("make the bar outlin color red", function(result)
    failedCallbackCount = failedCallbackCount + 1
    failedResult = result
end))
assert(resultStatus(failedQueued) == "queued", "synthetic fuzzy failure bypassed the queue")
pumpUntil(function() return failedResult ~= nil end, "synthetic yielded fuzzy failure", 30000)
P.ParseRegistryAliasCandidates = originalAliasCandidates
assert(failedCallbackCount == 1 and resultStatus(failedResult) == "failed",
    "synthetic yielded fuzzy failure was not reported exactly once")
assert(P._allowFuzzyAliasMatch == previousSharedFuzzy and not P.FuzzyAliasMatchEnabled(),
    "fuzzy matcher leaked after yielded worker failure")
assertRGB("synthetic yielded fuzzy failure rollback", sharedOutline, 0, 0, 0)

_G.C_Timer.NewTimer = oldTimer
_G.GetTimePreciseSec = oldPreciseTime
A.jobBudgetMs = oldBudget
A.jobMaxStepsPerFrame = oldMaxSteps

print("assistant_reported_crash_regression: ok")
