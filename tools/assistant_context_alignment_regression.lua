_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local function clearContext()
    local ctx = assert(A.GetContext(), "Assistant context missing")
    for key in pairs(ctx) do ctx[key] = nil end
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    if type(A.SetPendingResults) == "function" then A.SetPendingResults(nil) end
end

local function numberValue(key)
    local setting = assert(Registry:GetSetting(key), "Missing setting " .. tostring(key))
    return tonumber(setting.get())
end

clearContext()
assert((A.Submit("set target power text y offset to 7") or {}).status == "applied")
assert((A.Submit("more") or {}).status == "applied")
local offsetBeforeSubjectSwitch = numberValue("target.powerOffsetY")
local layerBeforeSubjectSwitch = numberValue("target.powerTextLayer")
local layerResult = assert(A.Submit("increase strata of power text"), "Missing text strata result")
assert(layerResult.status == "applied", tostring(layerResult.text))
assert(numberValue("target.powerOffsetY") == offsetBeforeSubjectSwitch, "Text strata command changed the previous Y offset")
assert(numberValue("target.powerTextLayer") == layerBeforeSubjectSwitch + 1, "Text strata command did not change Power Text Layer")

assert((A.Submit("set target power text y offset to 10") or {}).status == "applied")
local strataOffsetBefore = numberValue("target.powerOffsetY")
local strataLayerBefore = numberValue("target.powerTextLayer")
local terseStrata = assert(A.Submit("increase now strata"), "Missing terse strata follow-up")
assert(terseStrata.status == "applied", tostring(terseStrata.text))
assert(numberValue("target.powerOffsetY") == strataOffsetBefore, "Terse strata follow-up reused the previous Y offset")
assert(numberValue("target.powerTextLayer") == strataLayerBefore + 1, "Terse strata follow-up did not change Power Text Layer")

local layerBeforeMore = numberValue("target.powerTextLayer")
assert((A.Submit("more") or {}).status == "applied")
assert(numberValue("target.powerTextLayer") == layerBeforeMore + 1, "More did not continue Power Text Layer")
local rootYBeforeTextMove = numberValue("target.offsetY")
local powerYBeforeTextMove = numberValue("target.powerOffsetY")
local textMove = assert(A.Submit("now move the text down"), "Missing text movement after strata")
assert(textMove.status == "applied", tostring(textMove.text))
assert(numberValue("target.offsetY") == rootYBeforeTextMove, "Text movement after strata changed the Unit Frame root Y position")
assert(numberValue("target.powerOffsetY") == powerYBeforeTextMove - 10, "Text movement after strata did not change Power Text Y Offset")

local hpX, hpY = numberValue("target.hpOffsetX"), numberValue("target.hpOffsetY")
local copyPlan = assert(A.Parse("move target power text to position of hp text"), "Missing text-position copy plan")
assert(copyPlan.kind == "changes" and #copyPlan.changes == 2, tostring(copyPlan.text))
assert(copyPlan.changes[1].setting.key == "target.powerOffsetX" and copyPlan.changes[1].value == hpX, "Power Text X did not copy HP Text X")
assert(copyPlan.changes[2].setting.key == "target.powerOffsetY" and copyPlan.changes[2].value == hpY, "Power Text Y did not copy HP Text Y")

assert((A.Submit("set target power text y offset to 300") or {}).status == "applied")
local jokeOne = assert(A.Submit("tell me a joke"), "Missing first joke")
local offsetBeforeJokeFollowup = numberValue("target.powerOffsetY")
local jokeTwo = assert(A.Submit("another one"), "Missing joke follow-up")
assert(jokeOne.status == "info" and jokeTwo.status == "info", "Joke conversation did not stay read-only")
assert(jokeOne.text ~= jokeTwo.text, "Joke follow-up did not advance to another joke")
assert(numberValue("target.powerOffsetY") == offsetBeforeJokeFollowup, "Joke follow-up reused mutation context")

-- Stale search/workflow state introduced after the joke must not outrank its
-- directly adjacent conversational follow-up.
A.SetPendingResults(nil)
local jokeThree = assert(A.Submit("tell me a joke"), "Missing joke before stale pending results")
assert(A.SetPendingResults({ { kind = "setting", settingKey = "target.powerOffsetY", label = "Target Power Text Y Offset" } }))
local jokeFour = assert(A.Submit("another one"), "Missing joke follow-up with stale pending results")
assert(jokeThree.status == "info" and jokeFour.status == "info", "Pending results blocked adjacent joke context")
assert(jokeThree.text ~= jokeFour.text, "Pending-state joke follow-up did not advance")
assert(numberValue("target.powerOffsetY") == offsetBeforeJokeFollowup, "Pending-state joke follow-up changed the previous slider")

-- The real Dashboard submits through SubmitDeferred. One user message must be
-- exactly one conversational turn, including immediate social replies and a
-- multi-command batch.
local function submitDeferredResult(text)
    local completed
    local immediate = A.SubmitDeferred(text, function(result) completed = result end)
    return completed or immediate
end
clearContext()
local deferredJokeOne = assert(submitDeferredResult("tell me a joke"), "Missing deferred joke")
assert(tonumber(A.GetContext().turnSerial) == 1, "Deferred immediate reply did not advance one turn")
local deferredJokeTwo = assert(submitDeferredResult("another one"), "Missing deferred joke follow-up")
assert(tonumber(A.GetContext().turnSerial) == 2, "Deferred follow-up did not advance exactly one turn")
assert(deferredJokeOne.text ~= deferredJokeTwo.text, "Deferred adjacent joke context was lost")
for index, social in ipairs({ "hello", "thanks", "hi", "thank you" }) do
    assert(submitDeferredResult(social), "Missing deferred social reply")
    assert(tonumber(A.GetContext().turnSerial) == index + 2, "Deferred social message did not age context exactly once")
end
local playerNameSetting = assert(Registry:GetSetting("player.showName"))
local targetNameSetting = assert(Registry:GetSetting("target.showName"))
local oldPlayerName, oldTargetName = playerNameSetting.get(), targetNameSetting.get()
local beforeDeferredBatchTurn = tonumber(A.GetContext().turnSerial) or 0
assert(submitDeferredResult("turn off player name and turn off target name"), "Missing deferred batch result")
assert(tonumber(A.GetContext().turnSerial) == beforeDeferredBatchTurn + 1, "One deferred batch counted as multiple turns")
playerNameSetting.set(oldPlayerName)
targetNameSetting.set(oldTargetName)

clearContext()
local essenceQuestion = assert(A.Submit("can you color the essences of my evoker?"), "Missing Essence clarification")
assert(essenceQuestion.status == "info", tostring(essenceQuestion.text))
assert(tostring(essenceQuestion.text):find("Evoker Essence color", 1, true), "Essence request did not route to class-resource colors")
assert(not tostring(essenceQuestion.text):find("Castbar", 1, true), "Essence request incorrectly routed to Castbar")

local essencePlan = assert(A.Parse("set all evoker essences cyan"), "Missing all-Essence color plan")
assert(essencePlan.kind == "changes" and #essencePlan.changes == 6, "All-Essence command must cover six slots")
for slot = 1, 6 do
    local expected = "general.classPowerColorOverrides.ESSENCE_" .. tostring(slot)
    assert(essencePlan.changes[slot].setting.key == expected, "Wrong Essence slot setting: " .. tostring(essencePlan.changes[slot].setting.key))
end

clearContext()
local auraChoice = assert(A.Submit("Can you blacklist all buffs on player frame with no timer?"), "Missing Aura filter choice reply")
assert(auraChoice.status == "ambiguous", tostring(auraChoice.text))
assert(type(A.pendingChoices) == "table" and #A.pendingChoices == 2, "No-duration Aura question did not create executable choices")
assert(tostring(auraChoice.text):find("Hide Permanent Auras control", 1, true), "No-duration Aura question did not explain the real control")
assert(tostring(auraChoice.text):find("live buff filter", 1, true), "Aura question did not offer live filter choices")
assert(tostring(auraChoice.text):find("specific spell", 1, true), "Aura question did not distinguish the SpellID blacklist")

local permanentPlan = assert(A.Parse("hide buffs with no timer on player frame"), "Missing no-duration Aura plan")
assert(permanentPlan.kind == "changes", tostring(permanentPlan.text))
assert(permanentPlan.changes[1].setting.key == "auras3.player.buff.blacklist.hidePermanent", "No-duration Aura command targeted the wrong control")
assert(permanentPlan.changes[1].value == true, "No-duration Aura command did not enable Hide Permanent Auras")

-- Contextual exact-control navigation must resolve the last real setting, ask
-- before navigating for a location question, and navigate directly for an
-- explicit follow-up. The core bridge owns page construction and highlighting;
-- this spy verifies the LoD Assistant passes the stable setting identity.
clearContext()
local openedControl
_G.MSUF_OpenExactSettingControl = function(settingKey, label, page)
    openedControl = { settingKey = settingKey, label = label, page = page }
    return true, "Opened " .. tostring(label) .. " and focused its exact control."
end
assert((A.Submit("set target power text y offset to 10") or {}).status == "applied")
local locationOnly = assert(A.Submit("where is that exact slider?"), "Missing exact-slider location reply")
assert(locationOnly.status == "info", tostring(locationOnly.text))
assert(openedControl == nil, "Read-only location question navigated without consent")
assert(tostring(locationOnly.text):find("open and focus that exact number control", 1, true), "Location reply did not offer the exact number control")
local consentedOpen = assert(A.Submit("open it"), "Missing consented exact-control navigation")
assert(consentedOpen.status == "applied" or consentedOpen.status == "info" or consentedOpen.status == "navigated", tostring(consentedOpen.text))
assert(openedControl and openedControl.settingKey == "target.powerOffsetY", "Open-it follow-up lost the exact setting identity")
assert(openedControl.page == "uf_target", "Exact slider navigation used the wrong page")

A.SetPendingResults(nil)
openedControl = nil
assert((A.Submit("set target power text y offset to 20") or {}).status == "applied")
local directOpen = assert(A.Submit("move to that exact slider"), "Missing direct exact-slider navigation")
assert(directOpen.status == "applied" or directOpen.status == "info" or directOpen.status == "navigated", tostring(directOpen.text))
assert(openedControl and openedControl.settingKey == "target.powerOffsetY", "Move-to-slider follow-up was misaligned as frame movement")

A.SetPendingResults(nil)
openedControl = nil
local dropdownChange = assert(A.Submit("set player portrait position to left"), "Missing dropdown change")
assert(dropdownChange.status == "applied" or dropdownChange.status == "unchanged", tostring(dropdownChange.text))
local dropdownOpen = assert(A.Submit("open that exact dropdown"), "Missing exact-dropdown navigation")
assert(dropdownOpen.status == "navigated", tostring(dropdownOpen.text))
assert(openedControl and openedControl.settingKey == "player.portraitMode", "Dropdown follow-up lost its exact setting identity")

clearContext()
openedControl = nil
local directWidthOpen = assert(A.Submit("take me to target width"), "Missing direct width navigation")
assert(directWidthOpen.status == "navigated", tostring(directWidthOpen.text))
assert(openedControl and openedControl.settingKey == "target.width", "Direct width navigation asked for a value or opened only the page")
clearContext()
openedControl = nil
local directPortraitOpen = assert(A.Submit("show me target portrait position dropdown"), "Missing direct portrait dropdown navigation")
assert(directPortraitOpen.status == "navigated", tostring(directPortraitOpen.text))
assert(openedControl and openedControl.settingKey == "target.portraitMode", "Portrait dropdown navigation was mistaken for frame X/Y position")

-- A value token inside explicit navigation identifies the exact typed control;
-- it is not permission to apply that value. Reuse the parser's stable setting
-- identity while preserving every setting value and prerequisite gate.
clearContext()
openedControl = nil
local targetPortraitSetting = assert(Registry:GetSetting("target.portraitMode"))
local oldTargetPortrait = targetPortraitSetting.get()
local valuedPortraitOpen = assert(A.Submit("direct me to target portrait position left"), "Missing value-bearing portrait navigation")
assert(valuedPortraitOpen.status == "navigated", tostring(valuedPortraitOpen.text))
assert(openedControl and openedControl.settingKey == "target.portraitMode", "Value-bearing portrait navigation opened the wrong control")
assert(targetPortraitSetting.get() == oldTargetPortrait, "Value-bearing portrait navigation changed the enum")

clearContext()
openedControl = nil
local raidFilter = assert(Registry:GetSetting("gf_raid.auras.debuff.filterToken"))
local raidAuraGate = assert(Registry:GetSetting("gf_raid.auras.enabled"))
local raidDebuffGate = assert(Registry:GetSetting("gf_raid.auras.debuff.enabled"))
local oldRaidFilter = raidFilter.get()
local oldRaidAuraGate = raidAuraGate.get()
local oldRaidDebuffGate = raidDebuffGate.get()
local valuedFilterOpen = assert(A.Submit("direct me to raid debuff dispellable filter"), "Missing value-bearing filter navigation")
assert(valuedFilterOpen.status == "navigated", tostring(valuedFilterOpen.text))
assert(openedControl and openedControl.settingKey == "gf_raid.auras.debuff.filterToken", "Value-bearing filter navigation opened the wrong control")
assert(raidFilter.get() == oldRaidFilter, "Value-bearing filter navigation changed the enum")
assert(raidAuraGate.get() == oldRaidAuraGate and raidDebuffGate.get() == oldRaidDebuffGate,
    "Value-bearing filter navigation changed prerequisite gates")

clearContext()
openedControl = nil
local widthLocation = assert(A.Submit("where is target width?"), "Missing singular width location")
assert(widthLocation.status == "info" and type(widthLocation.searchResults) == "table", tostring(widthLocation.text))
local widthOpenFollowup = assert(A.Submit("open it"), "Missing width open-it follow-up")
assert(widthOpenFollowup.status == "navigated", tostring(widthOpenFollowup.text))
assert(openedControl and openedControl.settingKey == "target.width", "Singular location reply did not preserve its exact referent")

clearContext()
local fullTour = assert(A.Submit("show me around MSUF"), "Missing full MSUF tour")
local fullTourText = tostring(fullTour.text or ""):lower()
assert(fullTourText:find("guided setup", 1, true) and fullTourText:find("which frame", 1, true) == nil,
    "Full tour fell into generic ambiguity")
clearContext()
local auraTour = assert(A.Submit("guide me through auras"), "Missing Aura guide")
local auraTourText = tostring(auraTour.text or ""):lower()
assert(auraTourText:find("guided setup", 1, true) and auraTourText:find("which frame", 1, true) == nil,
    "Aura guide started the generic frame-size guide")
clearContext()
local colorTour = assert(A.Submit("walk me through colors"), "Missing Colors guide")
local colorTourText = tostring(colorTour.text or ""):lower()
assert(colorTourText:find("guided setup", 1, true) and colorTourText:find("which frame", 1, true) == nil,
    "Colors guide started the generic frame-size guide")

clearContext()
local rootRelations = assert(A.Submit("what settings depend on target frame enabled?"), "Missing target-root relationships")
assert(rootRelations.status == "info" and tostring(rootRelations.text):find("Target Frame Enabled relationships", 1, true), "Relationship question selected the wrong Target setting")
assert(tostring(rootRelations.text):find("Can affect:", 1, true), "Target root relationship answer omitted dependents")

-- Relationship ambiguity is actionable only on the adjacent turn. A social
-- topic switch expires it, while an immediate number explains the selected
-- setting without mutating anything.
clearContext()
local groupRelationChoice = assert(A.Submit("what depends on group frames"), "Missing group relationship choices")
assert(groupRelationChoice.status == "ambiguous", tostring(groupRelationChoice.text))
local chosenGroupRelation = assert(A.Submit("2"), "Missing adjacent relationship choice")
assert(chosenGroupRelation.status == "info" and tostring(chosenGroupRelation.text):find("Raid Frames Enabled relationships", 1, true),
    "Adjacent relationship number did not explain Raid Frames")
clearContext()
assert((A.Submit("what depends on group frames") or {}).status == "ambiguous")
assert((A.Submit("hello") or {}).status == "info")
local staleRelationshipChoice = assert(A.Submit("1"), "Missing expired relationship-choice reply")
assert(not tostring(staleRelationshipChoice.text):find("Party Frames Enabled relationships", 1, true),
    "A stale relationship number survived a topic switch")

-- Paginated relationship results use page-local numbers, matching the pending
-- result resolver. Page 2 line 7 must open the setting shown on line 7, not
-- the globally numbered item 7 from page 1.
clearContext()
openedControl = nil
assert((A.Submit("what depends on target frame enabled") or {}).status == "info")
local moreRelations = assert(A.Submit("more related settings"), "Missing relationship page 2")
assert(tostring(moreRelations.text):find("7%-14 of %d+"), tostring(moreRelations.text))
assert(tostring(moreRelations.text):find("\n1. ", 1, true),
    "Relationship page did not restart selectable numbering at 1")
assert(tostring(moreRelations.text):find("\n7. ", 1, true),
    "Relationship page did not expose page-local option 7")
local expectedRelationshipKey = A.pendingResults and A.pendingResults[7] and A.pendingResults[7].settingKey
assert(type(expectedRelationshipKey) == "string" and expectedRelationshipKey ~= "",
    "Relationship page-local option 7 did not preserve an exact setting identity")
local openedRelation = assert(A.Submit("7"), "Missing relationship result navigation")
assert(openedRelation.status == "navigated", tostring(openedRelation.text))
assert(openedControl and openedControl.settingKey == expectedRelationshipKey,
    "Relationship page option 7 opened a different setting")

-- Named aura icons/spells and advice questions are read-only unless the user
-- gives an executable, supported setting command. They must never disable the
-- surrounding frame or flip the exact option being discussed.
clearContext()
local playerEnabled = assert(Registry:GetSetting("player.enabled"))
local playerEnabledBefore = playerEnabled.get()
local namedSpell = assert(A.Submit("hide Power Word Shield on player frame"), "Missing named-spell clarification")
assert(namedSpell.status == "info", tostring(namedSpell.text))
assert(playerEnabled.get() == playerEnabledBefore, "Named aura spell disabled the Player frame")
local bossSwipe = assert(Registry:GetSetting("auras3.boss.buff.showCooldownSwipe"))
local bossSwipeBefore = bossSwipe.get()
local decisionReply = assert(A.Submit("should I turn off Boss Buff Show Cooldown Swipe?"), "Missing decision guidance")
assert(decisionReply.status == "info", tostring(decisionReply.text))
assert(bossSwipe.get() == bossSwipeBefore, "Decision question changed Boss Buff Show Cooldown Swipe")

clearContext()
local targetBrowser = assert(A.Submit("list all target settings"), "Missing Target setting browser")
local targetBrowserTotal = tonumber(tostring(targetBrowser.text):match("1%-8 of (%d+)"))
assert(targetBrowser.status == "info" and targetBrowserTotal and targetBrowserTotal >= 300, "Target browser did not paginate its full setting list")
assert(type(targetBrowser.searchResults) == "table" and #targetBrowser.searchResults == 8, "Target browser did not expose selectable controls")
local nextTargetSettings = assert(A.Submit("next settings"), "Missing next setting page")
assert(tostring(nextTargetSettings.text):find("9%-16 of " .. tostring(targetBrowserTotal)), "Setting browser did not advance one page")

-- A no-duration request may omit the scope when the immediately preceding
-- context already identifies a unit Aura lane. It must not fall through to a
-- generic filter-off interpretation.
clearContext()
A.SetContextValue("lastSetting", "auras3.player.buff.offsetY")
A.SetContextValue("lastUnit", "player")
local contextualPermanent = assert(A.Parse("now filter all buffs that have no timer out"), "Missing contextual no-duration plan")
assert(contextualPermanent.kind == "changes", tostring(contextualPermanent.text))
assert(contextualPermanent.changes[1].setting.key == "auras3.player.buff.blacklist.hidePermanent",
    "Contextual no-duration request targeted the wrong filter")
assert(contextualPermanent.changes[1].value == true, "'filter ... out' was misread as turning the filter off")

-- Every individual live unit filter transaction must make that scope own its
-- rules and enable the master gate. Keep all three values in one undoable plan.
local own = assert(Registry:GetSetting("auras3.player.useSharedRules"))
local gate = assert(Registry:GetSetting("auras3.player.filtersEnabled"))
local token = assert(Registry:GetSetting("auras3.player.buff.filter.raid"))
local originals = {
    ownGet = own.get, ownSet = own.set, ownApply = own.apply,
    gateGet = gate.get, gateSet = gate.set, gateApply = gate.apply,
    tokenGet = token.get, tokenSet = token.set, tokenApply = token.apply,
}
local filterState = { own = true, gate = false, token = false }
own.get = function() return filterState.own end
own.set = function(value) filterState.own = value end
own.apply = function() return true end
gate.get = function() return filterState.gate end
gate.set = function(value) filterState.gate = value end
gate.apply = function() return true end
token.get = function() return filterState.token end
token.set = function(value) filterState.token = value end
token.apply = function() return true end
local expandedFilter = assert(A.ExecutePlan({
    kind = "changes",
    changes = { { setting = token, value = true } },
    label = "Player Buff Raid Filter",
}), "Missing expanded filter result")
assert(expandedFilter.status == "applied", tostring(expandedFilter.text))
assert(filterState.own == false and filterState.gate == true and filterState.token == true,
    "Individual filter did not enable Own filters and the master gate")
own.get, own.set, own.apply = originals.ownGet, originals.ownSet, originals.ownApply
gate.get, gate.set, gate.apply = originals.gateGet, originals.gateSet, originals.gateApply
token.get, token.set, token.apply = originals.tokenGet, originals.tokenSet, originals.tokenApply

-- Removed standalone Aura pages must route into the owning native workspace.
clearContext()
A.SetContextValue("lastSetting", "auras3.player.buff.blacklist.hidePermanent")
A.SetContextValue("lastUnit", "player")
local menu = assert(_G.MSUF_NS.MSUF2)
local oldOpen, oldBridge, oldActive = menu.Open, menu.SearchBridge, menu.activeKey
local routedPage, routedQuery
menu.Open = function(page) menu.activeKey = page return true end
menu.SearchBridge = { OpenSearchTarget = function(page, query) routedPage, routedQuery = page, query; menu.activeKey = page end }
local openPage = assert(Registry:GetAction("open_page"))
local legacyRoute = assert(A.ExecutePlan({ kind = "action", action = openPage,
    args = { page = "auras3_filters", label = "Aura Filters" } }), "Missing legacy Aura route result")
assert(legacyRoute.status == "navigated", tostring(legacyRoute.text))
assert(routedPage == "uf_player", "Legacy Aura Filters route opened a removed page: " .. tostring(routedPage))
assert(tostring(routedQuery):find("buff", 1, true) and tostring(routedQuery):find("filters", 1, true),
    "Legacy Aura Filters route lost its lane/tool selector context")
menu.Open, menu.SearchBridge, menu.activeKey = oldOpen, oldBridge, oldActive

-- Exact live report: the clarification is followed by a typo-heavy executable
-- sentence. It must reach the real setting transaction, not the legacy
-- blacklist-spell conversational fallback.
clearContext()
local permanentSetting = assert(Registry:GetSetting("auras3.player.buff.blacklist.hidePermanent"))
local permanentOriginal = { get = permanentSetting.get, set = permanentSetting.set, apply = permanentSetting.apply }
local permanentValue = false
permanentSetting.get = function() return permanentValue end
permanentSetting.set = function(value) permanentValue = value == true end
permanentSetting.apply = function() return true end
local permanentQuestion = assert(A.Submit("hide permanent auras"), "Missing permanent-aura clarification")
assert(permanentQuestion.status == "ambiguous", tostring(permanentQuestion.text))
local permanentExecution = assert(A.Submit("Hide permanant buffs frames for player"), "Missing typo-tolerant permanent-aura execution")
assert(permanentExecution.status == "applied", tostring(permanentExecution.text))
assert(permanentValue == true, "Typo-tolerant permanent-aura follow-up did not execute the setting")
permanentSetting.get, permanentSetting.set, permanentSetting.apply = permanentOriginal.get, permanentOriginal.set, permanentOriginal.apply

clearContext()
local hpModeChoice = assert(A.Parse("Set HP color text"), "Missing HP text color-mode choice")
-- The mode enum is DEFAULT, CLASS, HEALTH (Class colouring was added after the
-- original two-mode fixture), so a bare command offers all three modes.
assert(hpModeChoice.kind == "ambiguous" and #hpModeChoice.choices == 3, "Bare HP text color command did not offer every mode")
assert(hpModeChoice.choices[1].value == "DEFAULT" and hpModeChoice.choices[2].value == "CLASS"
    and hpModeChoice.choices[3].value == "HEALTH",
    "HP text color-mode choices are not Single Color, Class, then Health Gradient")
local hpSingle = assert(A.Parse("change HP text from gradiant to single color"), "Missing single-color HP text plan")
assert(hpSingle.kind == "changes", tostring(hpSingle.text))
assert(hpSingle.changes[#hpSingle.changes].setting.key == "fontScope.shared.colorHealthTextByHealth",
    "Single-color HP text command targeted the wrong setting")
assert(hpSingle.changes[#hpSingle.changes].value == "DEFAULT", "Single-color HP text command did not disable Health Gradient")

-- Warm exact-alias indexes used to outrank explicit preview actions and
-- compound pronoun commands.  Reproduce the warm state before checking the
-- exact user-facing phrases from the Assistant panel.
A.Parse("set player width to 200")
local bossPreview = assert(A.Submit("show boss frame preview"), "Missing Boss preview result")
assert(not tostring(bossPreview.text):find("Boss Frame Enabled", 1, true),
    "Warm exact-alias cache changed Boss preview into Boss Frame Enabled")
assert(tostring(bossPreview.text):find("preview", 1, true), "Boss preview command lost preview action context")

local timerEnabled = assert(Registry:GetSetting("gameplay.enableCombatTimer"))
local timerAnchor = assert(Registry:GetSetting("gameplay.combatTimerAnchor"))
local compoundTimer = assert(A.Submit("turn on combat timer and anchor it to player frame"), "Missing compound Combat Timer result")
assert(compoundTimer.status == "applied" or compoundTimer.status == "unchanged", tostring(compoundTimer.text))
assert(timerEnabled.get() == true, "Compound Combat Timer command did not enable the timer")
assert(timerAnchor.get() == "player", "Compound Combat Timer command targeted Player Frame Enabled instead of its anchor")

local portraitPosition = assert(A.Submit("set target portrait position to right"), "Missing portrait-position result")
assert(portraitPosition.status == "applied" or portraitPosition.status == "unchanged", tostring(portraitPosition.text))
local portraitRender = assert(A.Submit("change it to 2d"), "Missing conversational portrait-render follow-up")
assert(portraitRender.status == "applied" or portraitRender.status == "unchanged", tostring(portraitRender.text))
assert(Registry:GetSetting("target.portraitRender").get() == "2D", "Portrait follow-up did not select 2D render")
assert(tostring(portraitRender.text):find("Portrait Render", 1, true), "Portrait follow-up stayed on Portrait Position")

-- Live color questions should be answered from the visible unit state without
-- a registry scan or a write.  A neutral target with one harmful aura is the
-- screenshot case: the health fill is a reaction color, while the debuff is a
-- separate aura signal.
local oldUnitExists, oldUnitIsPlayer, oldUnitReaction = _G.UnitExists, _G.UnitIsPlayer, _G.UnitReaction
local oldAuras, oldFrame = _G.C_UnitAuras, _G.MSUF_target
_G.UnitExists = function(unit) return unit == "target" end
_G.UnitIsPlayer = function() return false end
_G.UnitReaction = function() return 4 end
_G.C_UnitAuras = { GetAuraDataByIndex = function(_, index) return index == 1 and { name = "Test Debuff" } or nil end }
_G.MSUF_target = {
    MSUFSpec = { health = { mode = "class", npcColorMode = "reaction" } },
    hpBar = { GetStatusBarColor = function() return 1, 0.5, 0 end },
}
local targetDebuffVisible = assert(Registry:GetSetting("auras3.target.debuff.visible"))
local targetDebuffVisibleBefore = targetDebuffVisible.get()
local diagnosticColorCases = {
    {
        text = "my target has a debuff and the frame is orange",
        contains = { "neutral reaction color", "1 readable debuff" },
    },
    {
        text = "target color changed because of a debuff",
        contains = { "neutral reaction color", "1 readable debuff" },
    },
    {
        text = "why did my party frame turn blue",
        contains = { "Party frame color guide", "Magic-dispel overlay" },
    },
    {
        text = "what do the different frame colors mean",
        contains = { "MSUF frame color guide", "health fill", "dispel/debuff" },
    },
}
for i = 1, #diagnosticColorCases do
    clearContext()
    local case = diagnosticColorCases[i]
    local reply = assert(A.Submit(case.text), "Missing descriptive color explanation: " .. case.text)
    assert(reply.status == "info", case.text .. ": " .. tostring(reply.text))
    for j = 1, #case.contains do
        assert(tostring(reply.text):find(case.contains[j], 1, true),
            case.text .. ": missing color-guide text " .. case.contains[j] .. ": " .. tostring(reply.text))
    end
    assert(not tostring(reply.text):find("I found these MSUF matches", 1, true),
        case.text .. ": fell through to irrelevant fuzzy search")
    assert(not tostring(reply.text):find("Done. I changed", 1, true),
        case.text .. ": descriptive color wording became a mutation")
    assert(targetDebuffVisible.get() == targetDebuffVisibleBefore,
        case.text .. ": descriptive color wording changed Target Debuffs")
end

-- Diagnostic ownership must not swallow an explicit color-setting mutation.
clearContext()
local targetOutlineColor = assert(Registry:GetSetting("barScope.target.barOutlineColor"))
local targetOutlineColorBefore = targetOutlineColor.get()
local explicitColor = assert(A.Submit("set Target Bar Outline Color to red"), "Missing explicit color mutation")
assert(explicitColor.status == "applied" or explicitColor.status == "unchanged", tostring(explicitColor.text))
assert(not tostring(explicitColor.text):find("frame color guide", 1, true), "Explicit color mutation was treated as an explanation")
targetOutlineColor.set(targetOutlineColorBefore)

local colorReply = assert(A.RouterPrivate.TryLiveUnitColorExplanation("why is my target orange?"), "Missing live color explanation")
assert(colorReply.status == "info", tostring(colorReply.text))
assert(tostring(colorReply.text):find("neutral reaction color", 1, true), "Live color explanation missed neutral reaction state")
assert(tostring(colorReply.text):find("1 readable debuff", 1, true), "Live color explanation missed the target debuff")
assert(tostring(colorReply.text):find("do not recolor the health fill", 1, true), "Live color explanation conflated debuffs with health color")
_G.UnitExists, _G.UnitIsPlayer, _G.UnitReaction = oldUnitExists, oldUnitIsPlayer, oldUnitReaction
_G.C_UnitAuras, _G.MSUF_target = oldAuras, oldFrame

-- A live highlight border already knows its winning runtime source. Prefer it
-- over health reaction color and do not rescan the Aura list.
local auraReads = 0
_G.UnitExists = function(unit) return unit == "target" end
_G.UnitIsPlayer = function() return false end
_G.UnitReaction = function() return 4 end
_G.C_UnitAuras = { GetAuraDataByIndex = function() auraReads = auraReads + 1 return nil end }
_G.MSUF_target = {
    MSUFSpec = { health = { mode = "class", npcColorMode = "reaction" }, border = { dispel = true } },
    _msufA3DispelActive = true,
    _msufA3DispelR = 1,
    _msufA3DispelG = 0.5,
    _msufA3DispelB = 0,
    _msufA3DispelA = 1,
    hpBar = { GetStatusBarColor = function() return 1, 0.5, 0 end },
}
local borderReply = assert(A.RouterPrivate.TryLiveUnitColorExplanation("what does the orange target border mean?"), "Missing border color explanation")
assert(tostring(borderReply.text):find("dispel/debuff highlight border", 1, true), "Active dispel border was explained as a health fill")
assert(not tostring(borderReply.text):find("neutral reaction color", 1, true), "Border explanation fell back to reaction color")
assert(auraReads == 0, "Border explanation rescanned Auras despite an active runtime source")
_G.UnitExists, _G.UnitIsPlayer, _G.UnitReaction = oldUnitExists, oldUnitIsPlayer, oldUnitReaction
_G.C_UnitAuras, _G.MSUF_target = oldAuras, oldFrame

-- Unconstrained AutoCoverage values remain searchable/explainable but must not
-- accept arbitrary writes until reviewed bounds or allowed values exist.
local runeSort = assert(Registry:GetSetting("bars.runeSortOrder"))
local runeSortBefore = runeSort.get()
local unsafeString = assert(A.Submit("set bars rune sort order to BANANA"), "Missing generated-string safety reply")
assert(unsafeString.status == "info" and tostring(unsafeString.text):find("not safe for automatic writes", 1, true), "Generated enum-like string was not blocked")
assert(runeSort.get() == runeSortBefore, "Generated enum-like string accepted an invalid value")

-- Low-confidence context must become a real numbered choice. Recent explicit
-- context remains conversational; stale pronouns require confirmation.
clearContext()
local broadTextSize = assert(A.Submit("make target text bigger"), "Missing broad text-size choices")
assert(broadTextSize.status == "ambiguous", tostring(broadTextSize.text))
assert(tostring(broadTextSize.text):find("Target Name Font Size", 1, true), "Broad target text size missed Name Font Size")
assert(tostring(broadTextSize.text):find("Target HP Font Size", 1, true), "Broad target text size missed HP Font Size")
assert(tostring(broadTextSize.text):find("Target Power Font Size", 1, true), "Broad target text size missed Power Font Size")
assert(not tostring(broadTextSize.text):find("X Offset", 1, true), "Broad target text size offered an unrelated X offset")
clearContext()

local targetEnabled = assert(Registry:GetSetting("target.enabled"))
local originalTargetEnabled = { get = targetEnabled.get, set = targetEnabled.set, apply = targetEnabled.apply }
local targetEnabledValue = true
targetEnabled.get = function() return targetEnabledValue end
targetEnabled.set = function(value) targetEnabledValue = value == true end
targetEnabled.apply = function() return true end
local staleCtx = A.GetContext()
staleCtx.lastSetting = "target.enabled"
staleCtx.lastUnit = "target"
staleCtx.lastSubjectTurn = 1
staleCtx.turnSerial = 10
staleCtx.lastTurnSerial = 10
local staleToggle = assert(A.Submit("turn it off"), "Missing stale-context choice")
assert(staleToggle.status == "ambiguous", tostring(staleToggle.text))
assert(targetEnabledValue == true, "Stale pronoun changed Target Frame without confirmation")
assert(tostring(staleToggle.text):find("Target Frame Enabled", 1, true), "Stale-context choices omitted the earlier topic")
local selectedStaleToggle = assert(A.Submit("1"), "Missing stale-context selection result")
assert(selectedStaleToggle.status == "applied", tostring(selectedStaleToggle.text))
assert(targetEnabledValue == false, "Selecting the explicit stale-context option did not apply it")
targetEnabled.get, targetEnabled.set, targetEnabled.apply = originalTargetEnabled.get, originalTargetEnabled.set, originalTargetEnabled.apply

-- A terse text follow-up names the text object but not the frame that owns it.
-- Without the remembered subject the request reached the fuzzy search, which
-- resolved "power text" to the unrelated Class Resource Text.
clearContext()
assert((A.Submit("detach player power bar") or {}).status == "applied")
local playerPowerYBefore = numberValue("player.powerOffsetY")
local classPowerYBefore = numberValue("bars.classPowerTextOffsetY")
local tersePowerText = assert(A.Submit("move now power text up"), "Missing terse power-text follow-up")
assert(tersePowerText.status == "applied", tostring(tersePowerText.text))
assert(numberValue("player.powerOffsetY") == playerPowerYBefore + 10,
    "Terse power-text follow-up did not move Player Power Text Y Offset")
assert(numberValue("bars.classPowerTextOffsetY") == classPowerYBefore,
    "Terse power-text follow-up leaked onto Class Resource Text Offset Y")

-- An explicit frame in the sentence must still outrank the remembered one.
local targetPowerYBefore = numberValue("target.powerOffsetY")
assert((A.Submit("move target power text up") or {}).status == "applied")
assert(numberValue("target.powerOffsetY") == targetPowerYBefore + 10,
    "Named unit lost to the remembered conversation scope")

-- The same terse sentence with no remembered subject must not invent a frame.
clearContext()
local unprimedPlayerPowerY = numberValue("player.powerOffsetY")
A.Submit("move now power text up")
assert(numberValue("player.powerOffsetY") == unprimedPlayerPowerY,
    "Contextless terse follow-up silently picked the Player frame")

-- Health Text has X/Y offsets but no anchor at all. A pronoun anchor follow-up
-- must say so and point at the real controls instead of refusing with a vague
-- "name the exact object", and it must not touch the retained offsets.
clearContext()
assert((A.Submit("move player hp text left 10") or {}).status == "applied")
local hpXBefore = numberValue("player.hpOffsetX")
local hpAnchorFollowup = assert(A.Submit("anchor it to the left"), "Missing hp-text anchor follow-up")
assert(hpAnchorFollowup.status == "ambiguous", tostring(hpAnchorFollowup.text))
assert(tostring(hpAnchorFollowup.text):find("has no anchor control", 1, true),
    "HP text anchor follow-up did not name the missing control: " .. tostring(hpAnchorFollowup.text))
assert(tostring(hpAnchorFollowup.text):find("Player HP Text X Offset", 1, true),
    "HP text anchor follow-up did not offer the real position controls")
assert(numberValue("player.hpOffsetX") == hpXBefore, "HP text anchor follow-up changed the retained offset")

-- Name Text does own an anchor, so the identical follow-up must still apply it.
clearContext()
local nameAnchor = assert(Registry:GetSetting("player.nameTextAnchor"))
nameAnchor.set("CENTER")
assert((A.Submit("move player name text left 10") or {}).status == "applied")
local nameAnchorFollowup = assert(A.Submit("anchor it to the left"), "Missing name-text anchor follow-up")
assert(nameAnchorFollowup.status == "applied" or nameAnchorFollowup.status == "unchanged",
    tostring(nameAnchorFollowup.text))
assert(tostring(nameAnchor.get()) == "LEFT", "Name text anchor follow-up stopped applying the anchor")

io.write("assistant_context_alignment_regression: ok\n")
