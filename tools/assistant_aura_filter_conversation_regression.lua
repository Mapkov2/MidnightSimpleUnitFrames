_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local P = assert(A.Parser, "Assistant parser missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local checks = 0
local failures = {}
local patched = {}

local function status(result)
    return result and (result.status or result.result)
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function runCase(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        checks = checks + 1
    else
        failures[#failures + 1] = label .. ": " .. tostring(err)
    end
end

local function fakeSetting(key, initial)
    local setting = assert(Registry:GetSetting(key), "missing setting " .. tostring(key))
    patched[#patched + 1] = {
        setting = setting,
        get = setting.get,
        set = setting.set,
        apply = setting.apply,
    }
    local box = { value = initial }
    setting.get = function() return box.value end
    setting.set = function(value) box.value = value end
    setting.apply = function() return true end
    return box
end

local state = {
    playerHidePermanent = fakeSetting("auras3.player.buff.blacklist.hidePermanent", false),
    playerBuffVisible = fakeSetting("auras3.player.buff.visible", true),
    targetBuffVisible = fakeSetting("auras3.target.buff.visible", true),
    playerFiltersEnabled = fakeSetting("auras3.player.filtersEnabled", false),
    playerUseSharedRules = fakeSetting("auras3.player.useSharedRules", true),
    targetFiltersEnabled = fakeSetting("auras3.target.filtersEnabled", false),
    targetUseSharedRules = fakeSetting("auras3.target.useSharedRules", true),
}

local unitFilterKeys = {
    "auras3.target.buff.filter.onlyMine",
    "auras3.target.buff.filter.raid",
    "auras3.target.buff.filter.raidInCombat",
    "auras3.target.buff.filter.includeNameplateOnly",
    "auras3.target.buff.filter.cancelable",
    "auras3.target.buff.filter.notCancelable",
    "auras3.target.buff.filter.externalDefensive",
    "auras3.target.buff.filter.bigDefensive",
    "auras3.target.debuff.filter.onlyMine",
    "auras3.target.debuff.filter.raid",
    "auras3.target.debuff.filter.raidInCombat",
    "auras3.target.debuff.filter.includeNameplateOnly",
    "auras3.target.debuff.filter.includeDispellable",
    "auras3.target.debuff.filter.crowdControl",
    "auras3.target.debuff.filter.exclusive",
}
for i = 1, #unitFilterKeys do
    local key = unitFilterKeys[i]
    state[key] = fakeSetting(key, key:find("%.exclusive$", 1, false) and "none" or false)
end

local groupScopes = { "party", "raid", "mythicraid" }
for i = 1, #groupScopes do
    local scope = groupScopes[i]
    state["gf_" .. scope .. ".auras.enabled"] = fakeSetting("gf_" .. scope .. ".auras.enabled", false)
    state["gf_" .. scope .. ".auras.buff.enabled"] = fakeSetting("gf_" .. scope .. ".auras.buff.enabled", false)
    state["gf_" .. scope .. ".auras.debuff.enabled"] = fakeSetting("gf_" .. scope .. ".auras.debuff.enabled", false)
    state["gf_" .. scope .. ".auras.buff.filterToken"] = fakeSetting("gf_" .. scope .. ".auras.buff.filterToken", "ALL")
    state["gf_" .. scope .. ".auras.debuff.filterToken"] = fakeSetting("gf_" .. scope .. ".auras.debuff.filterToken", "ALL")
end

local function restoreSettings()
    for i = #patched, 1, -1 do
        local item = patched[i]
        item.setting.get = item.get
        item.setting.set = item.set
        item.setting.apply = item.apply
    end
end

local function resetTask()
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
end

local function assertDidNotRecover(result, label)
    local output = tostring(result and result.text or "")
    local detail = A.lastAssistantJobError and (tostring(A.lastAssistantJobError.message or "")
        .. "\n" .. tostring(A.lastAssistantJobError.stack or "")) or ""
    local transaction = A.lastAssistantTransactionError
    if type(transaction) == "table" then
        detail = detail .. "\ntransaction=" .. tostring(transaction.phase) .. ":"
            .. tostring(transaction.target) .. ":" .. tostring(transaction.error)
    end
    assert(status(result) ~= "failed", label .. " failed: " .. output .. "\n" .. detail)
    assert(not output:find("couldn't finish a reliable answer", 1, true), label .. " entered recovery")
    assert(not output:find("could not finish a reliable answer", 1, true), label .. " entered recovery")
    assert(A.IsBusy() == false, label .. " left the Assistant busy")
end

local function changeKey(change)
    return tostring(change and change.setting and change.setting.key or change and change.key or "")
end

local function findChange(container, key, value)
    local changes = container and container.changes or {}
    for i = 1, #changes do
        if changeKey(changes[i]) == key and (value == nil or changes[i].value == value) then
            return changes[i]
        end
    end
    return nil
end

local function findChoiceChange(plan, key, value)
    local choices = plan and plan.choices or {}
    for i = 1, #choices do
        if findChange(choices[i], key, value) then return choices[i], i end
        if choices[i].setting and tostring(choices[i].setting.key or "") == key
            and (value == nil or choices[i].value == value)
        then
            return choices[i], i
        end
    end
    return nil
end

local function assertExactChange(plan, key, value, label)
    assert(type(plan) == "table", label .. ": missing plan")
    assert(plan.kind == "changes", label .. ": expected changes, got " .. tostring(plan.kind)
        .. " (" .. tostring(plan.text) .. ")")
    local change = assert(findChange(plan, key), label .. ": missing " .. key)
    assert(change.value == value, label .. ": " .. key .. " was " .. tostring(change.value)
        .. ", expected " .. tostring(value))
    return change
end

local function assertNoGateOrLaneChange(plan, label)
    for i = 1, #(plan and plan.changes or {}) do
        local key = changeKey(plan.changes[i])
        assert(not key:find("%.visible$", 1, false), label .. ": changed lane visibility via " .. key)
        assert(not key:find("%.enabled$", 1, false), label .. ": changed an aura lane/root gate via " .. key)
        assert(not key:find("filtersEnabled", 1, true), label .. ": changed the live-filter gate via " .. key)
    end
end

local function assertDurationPlan(prompt, expected)
    resetTask()
    local plan = A.Parse(prompt)
    assertExactChange(plan, "auras3.player.buff.blacklist.hidePermanent", expected, prompt)
    assertNoGateOrLaneChange(plan, prompt)
end

local function assertGuidedUnsupported(prompt)
    resetTask()
    local plan = A.Parse(prompt)
    assert(type(plan) == "table", prompt .. ": missing response")
    assert(plan.kind ~= "changes", prompt .. ": unsupported inverse mutated a setting")
    local responseStatus = tostring(plan.status or plan.result or "")
    assert(plan.kind == "answer" or plan.kind == "unsupported" or plan.kind == "ambiguous",
        prompt .. ": expected human guidance, got " .. tostring(plan.kind) .. "/" .. responseStatus)
    local text = lower(plan.text)
    assert(text:find("permanent", 1, true) or text:find("no%-duration") or text:find("no duration", 1, true),
        prompt .. ": guidance did not explain the permanent-aura control")
    assert(text:find("timed", 1, true) or text:find("timer", 1, true) or text:find("duration", 1, true),
        prompt .. ": guidance did not explain the unsupported inverse")
end

-- These two requests must be the first Submit calls in the process. Besides
-- reproducing the screenshots, this proves the bounded Aura specialist does
-- not build the full exact-alias catalog on either a cold or warm request.
runCase("cold first screenshot, undo, and redo", function()
    assert(P._registryExactAliasIndex == nil, "exact-alias index was warm before the first request")
    resetTask()
    state.playerHidePermanent.value = false
    state.playerBuffVisible.value = true
    state.playerFiltersEnabled.value = false
    local started = os.clock()
    local result = assert(A.Submit("do not show player buffs that have no timer"))
    _G.__MSUF_AURA_FILTER_COLD_MS = (os.clock() - started) * 1000
    assertDidNotRecover(result, "cold screenshot request")
    assert(status(result) == "applied", "cold screenshot request did not apply: " .. tostring(result.text))
    assert(state.playerHidePermanent.value == true, "cold request did not hide permanent Player Buffs")
    assert(state.playerBuffVisible.value == true, "cold request disabled the Player Buff lane")
    assert(state.playerFiltersEnabled.value == false, "cold request changed Player Filters Enabled")
    assert(P._registryExactAliasIndex == nil, "cold Aura request built the full exact-alias index")
    local text = lower(result.text)
    assert(text:find("permanent", 1, true) or text:find("no timer", 1, true)
        or text:find("no%-duration") or text:find("expiration", 1, true),
        "cold success text did not describe the human request")
    assert(not text:find("player buffs from enabled to disabled", 1, true), "cold output reported the old lane regression")
    assert(not text:find("filter master enabled", 1, true),
        "cold output falsely claimed the unchanged, disabled filter master was enabled")

    assert(A.UndoLast() == true, "undo failed")
    assert(state.playerHidePermanent.value == false, "undo did not restore Hide Permanent")
    assert(state.playerBuffVisible.value == true, "undo changed Player Buff visibility")
    assert(state.playerFiltersEnabled.value == false, "undo changed Player Filters Enabled")
    assert(A.RedoLast() == true, "redo failed")
    assert(state.playerHidePermanent.value == true, "redo did not restore Hide Permanent")
    assert(state.playerBuffVisible.value == true, "redo changed Player Buff visibility")
    assert(state.playerFiltersEnabled.value == false, "redo changed Player Filters Enabled")
end)

runCase("warm second screenshot", function()
    resetTask()
    state.playerHidePermanent.value = false
    state.playerBuffVisible.value = true
    state.playerFiltersEnabled.value = true
    local started = os.clock()
    local result = assert(A.Submit("filter player buffs do not show buffs with no timer"))
    _G.__MSUF_AURA_FILTER_WARM_MS = (os.clock() - started) * 1000
    assertDidNotRecover(result, "warm screenshot request")
    assert(status(result) == "applied", "warm screenshot request did not apply: " .. tostring(result.text))
    assert(state.playerHidePermanent.value == true, "warm request did not hide permanent Player Buffs")
    assert(state.playerBuffVisible.value == true, "warm request disabled the Player Buff lane")
    assert(state.playerFiltersEnabled.value == true, "warm request disabled Player Filters Enabled")
    assert(P._registryExactAliasIndex == nil, "warm Aura request built the full exact-alias index")
    assert(not lower(result.text):find("filters enabled from enabled to disabled", 1, true),
        "warm output reported the old filter-gate regression")
end)

local explicitHideRefusals = {
    "do not hide player buffs with no duration",
    "never hide player buffs with no duration",
}
for i = 1, #explicitHideRefusals do
    local prompt = explicitHideRefusals[i]
    runCase("explicit hide refusal stays read-only: " .. prompt, function()
        resetTask()
        state.playerHidePermanent.value = i == 1
        state.playerBuffVisible.value = true
        state.playerFiltersEnabled.value = false
        local before = state.playerHidePermanent.value
        local result = assert(A.Submit(prompt))
        assertDidNotRecover(result, prompt)
        assert(status(result) == "info", prompt .. ": refusal was not acknowledged as read-only")
        assert(state.playerHidePermanent.value == before, prompt .. ": changed Hide Permanent despite the refusal")
        assert(state.playerBuffVisible.value == true, prompt .. ": changed Player Buff lane visibility")
        assert(state.playerFiltersEnabled.value == false, prompt .. ": changed Player Filters Enabled")
        local text = lower(result.text)
        assert(text:find("unchanged", 1, true) or text:find("did not", 1, true)
            or text:find("kept", 1, true), prompt .. ": response did not explain that nothing changed")
    end)
end

local hidePermanentPrompts = {
    "hide permanent player buffs",
    "hide player buffs without a duration",
    "hide player buffs with no duration",
    "hide player buffs without a timer",
    "hide untimed player buffs",
    "don't show buffs without timers on the player frame",
    "exclude permanent player buffs",
    "filter out permanent player buffs",
    "only show timed player buffs",
    "show only buffs with a timer on player",
    "only let timed player buffs through",
    "only display player buffs that expire",
}
for i = 1, #hidePermanentPrompts do
    local prompt = hidePermanentPrompts[i]
    runCase("duration hide polarity: " .. prompt, function() assertDurationPlan(prompt, true) end)
end

local allowPermanentPrompts = {
    "show permanent player buffs",
    "show player buffs with no timer",
    "show player buffs regardless of duration",
    "let player buffs without timers show again",
    "don't hide permanent player buffs",
    "turn off hide permanent for player buffs",
}
for i = 1, #allowPermanentPrompts do
    local prompt = allowPermanentPrompts[i]
    runCase("duration allow polarity: " .. prompt, function() assertDurationPlan(prompt, false) end)
end

local unsupportedDurationPrompts = {
    "hide timed player buffs",
    "hide player buffs that do have a timer",
    "only show permanent player buffs",
    "show permanent buffs only on player",
}
for i = 1, #unsupportedDurationPrompts do
    local prompt = unsupportedDurationPrompts[i]
    runCase("duration unsupported inverse: " .. prompt, function() assertGuidedUnsupported(prompt) end)
end

runCase("shared permanent filter redirects to real frame choices", function()
    resetTask()
    local plan = assert(A.Parse("hide permanent shared buffs"))
    assert(plan.kind == "ambiguous", "nonexistent Shared Hide Permanent was not clarified")
    assert(findChoiceChange(plan, "auras3.player.buff.blacklist.hidePermanent", true),
        "Shared Hide Permanent clarification omitted Player Buffs")
    assert(findChoiceChange(plan, "gf_raid.auras.buff.blacklist.hidePermanent", true),
        "Shared Hide Permanent clarification omitted Raid Buffs")
    assert(not findChange(plan, "auras3.shared.buff.blacklist.hidePermanent"),
        "Shared Hide Permanent invented a nonexistent setting")
end)

runCase("lane and filter-gate requests stay distinct", function()
    resetTask()
    local lane = A.Parse("hide player buffs")
    assertExactChange(lane, "auras3.player.buff.visible", false, "hide player buffs")
    assert(not findChange(lane, "auras3.player.filtersEnabled"), "lane request also changed filter gate")
    assert(not findChange(lane, "auras3.player.buff.blacklist.hidePermanent"), "lane request also changed Hide Permanent")

    resetTask()
    local gate = A.Parse("turn off player buff filters")
    assertExactChange(gate, "auras3.player.filtersEnabled", false, "turn off player buff filters")
    assert(not findChange(gate, "auras3.player.buff.visible"), "filter-gate request also changed lane visibility")
    assert(not findChange(gate, "auras3.player.buff.blacklist.hidePermanent"), "filter-gate request changed Hide Permanent")

    resetTask()
    assertExactChange(A.Parse("enable filters for target"), "auras3.target.filtersEnabled", true,
        "enable filters for target")
    resetTask()
    assertExactChange(A.Parse("disable filters for target"), "auras3.target.filtersEnabled", false,
        "disable filters for target")

    resetTask()
    assertExactChange(A.Parse("use shared aura filters on target"), "auras3.target.overrideFilters", false,
        "use shared aura filters on target")
    resetTask()
    assertExactChange(A.Parse("use custom aura filters on target"), "auras3.target.overrideFilters", true,
        "use custom aura filters on target")

    resetTask()
    local statusPlan = A.Parse("what filters are active on target buffs")
    assert(statusPlan and statusPlan.kind == "answer" and (statusPlan.status == "info" or statusPlan.result == "info"),
        "active-filter question was not kept read-only")
    assert(lower(statusPlan.text):find("active", 1, true) or lower(statusPlan.text):find("current", 1, true),
        "active-filter answer did not describe the current state")
end)

runCase("show-all wording clarifies visibility versus clearing filters", function()
    resetTask()
    state.targetBuffVisible.value = false
    state["auras3.target.buff.filter.onlyMine"].value = true
    local question = assert(A.Submit("show all target buffs"))
    assert(status(question) == "ambiguous", "show-all wording guessed between lane visibility and filter clearing")
    assert(type(A.pendingChoices) == "table" and #A.pendingChoices == 2,
        "show-all clarification did not offer both executable meanings")
    local applied = assert(A.Submit("show every allowed target buffs — enable lane and clear live/permanent filters"))
    assertDidNotRecover(applied, "show-all displayed choice")
    assert(status(applied) == "applied" or status(applied) == "unchanged",
        "show-all displayed choice did not execute")
    assert(state.targetBuffVisible.value == true, "show-all choice did not enable Target Buffs")
    assert(state["auras3.target.buff.filter.onlyMine"].value == false,
        "show-all clear choice did not clear Target Buff Player Filter")
end)

local unitDirectCases = {
    { "only show my target buffs", "auras3.target.buff.filter.onlyMine", true },
    { "only let my target buffs through", "auras3.target.buff.filter.onlyMine", true },
    { "show target buffs cast by me", "auras3.target.buff.filter.onlyMine", true },
    { "exclude buffs from other players on target", "auras3.target.buff.filter.onlyMine", true },
    { "include buffs from everyone on target", "auras3.target.buff.filter.onlyMine", false },
    { "stop filtering target buffs to mine", "auras3.target.buff.filter.onlyMine", false },
    { "include raid-relevant target debuffs", "auras3.target.debuff.filter.raid", true },
    { "only show raid target debuffs", "auras3.target.debuff.filter.raid", true },
    { "turn off the raid filter for target debuffs", "auras3.target.debuff.filter.raid", false },
    { "include debuffs I can dispel on target", "auras3.target.debuff.filter.includeDispellable", true },
    { "turn off the dispellable filter for target debuffs", "auras3.target.debuff.filter.includeDispellable", false },
    { "include crowd control on target debuffs", "auras3.target.debuff.filter.crowdControl", true },
    { "turn off the crowd control filter for target debuffs", "auras3.target.debuff.filter.crowdControl", false },
    { "show target buffs that can be cancelled", "auras3.target.buff.filter.cancelable", true },
    { "turn off the cancelable filter for target buffs", "auras3.target.buff.filter.cancelable", false },
    { "show target buffs that cannot be cancelled", "auras3.target.buff.filter.notCancelable", true },
    { "only show non-cancelable player buffs", "auras3.player.buff.filter.notCancelable", true },
    { "only show boss debuffs on target", "auras3.target.debuff.filter.raid", true },
    { "show major defensive cooldowns on target", "auras3.target.buff.filter.bigDefensive", true },
    { "only show big defensives on target", "auras3.target.buff.filter.bigDefensive", true },
    { "show external defensive buffs on target", "auras3.target.buff.filter.externalDefensive", true },
    { "include nameplate-only target debuffs", "auras3.target.debuff.filter.includeNameplateOnly", true },
    { "only show raid buffs on player in combat", "auras3.player.buff.filter.raidInCombat", true },
}
for i = 1, #unitDirectCases do
    local spec = unitDirectCases[i]
    runCase("unit caster/category: " .. spec[1], function()
        resetTask()
        local plan = A.Parse(spec[1])
        if plan and plan.kind == "ambiguous" then
            assert(findChoiceChange(plan, spec[2], spec[3]), spec[1] .. ": choices did not contain " .. spec[2])
        else
            assertExactChange(plan, spec[2], spec[3], spec[1])
        end
        local wrongLane = spec[1]:find("debuff", 1, true) and "auras3.target.debuff.visible" or "auras3.target.buff.visible"
        assert(not findChange(plan, wrongLane), spec[1] .. ": changed lane visibility instead of its filter")
    end)
end

local unsupportedCategoryInversePrompts = {
    "exclude raid-relevant target debuffs",
    "exclude debuffs I can dispel on target",
    "exclude crowd control from target debuffs",
    "hide target buffs that can be cancelled",
}
for i = 1, #unsupportedCategoryInversePrompts do
    local prompt = unsupportedCategoryInversePrompts[i]
    runCase("unit category unsupported inverse: " .. prompt, function()
        resetTask()
        local plan = A.Parse(prompt)
        assert(plan and plan.kind ~= "changes", prompt .. ": exclusion was mistaken for disabling a positive filter")
        local text = lower(plan and plan.text)
        assert(text:find("include", 1, true) or text:find("narrow", 1, true)
            or text:find("does not hide", 1, true) or text:find("cannot", 1, true),
            prompt .. ": response did not explain the include-filter limitation")
    end)
end

runCase("unsupported not-mine inverse is guided", function()
    resetTask()
    local plan = A.Parse("show target buffs not cast by me")
    assert(plan and plan.kind ~= "changes", "not-mine inverse changed a supported filter with the wrong polarity")
    local text = lower(plan and plan.text)
    assert(text:find("not cast", 1, true) or text:find("other player", 1, true)
        or text:find("only your", 1, true) or text:find("cast by you", 1, true)
        or text:find("everyone except me", 1, true),
        "not-mine inverse did not explain the available caster filter")
end)

runCase("generic defensives offer guided category choices", function()
    resetTask()
    local plan = A.Parse("show defensives from other players on target")
    assert(plan and plan.kind == "ambiguous", "generic defensives should ask which defensive category")
    assert(findChoiceChange(plan, "auras3.target.buff.filter.externalDefensive", true),
        "generic defensive choices omitted External Defensive")
    assert(findChoiceChange(plan, "auras3.target.buff.filter.bigDefensive", true),
        "generic defensive choices omitted Big Defensive")
end)

local groupCases = {
    { "set party buff filter to Player", "gf_party.auras.buff.filterToken", "Player" },
    { "set raid buff filter to Player", "gf_raid.auras.buff.filterToken", "Player" },
    { "set mythic raid buff filter to Player", "gf_mythicraid.auras.buff.filterToken", "Player" },
    { "set party debuff filter to Raid", "gf_party.auras.debuff.filterToken", "Raid" },
    { "set raid debuff filter to Dispellable", "gf_raid.auras.debuff.filterToken", "RAID_PLAYER_DISPELLABLE" },
    { "set mythic raid debuff filter to Dispellable", "gf_mythicraid.auras.debuff.filterToken", "RAID_PLAYER_DISPELLABLE" },
    { "show only my party buffs", "gf_party.auras.buff.filterToken", "Player" },
    { "show only my raid buffs", "gf_raid.auras.buff.filterToken", "Player" },
    { "show only crowd control raid debuffs", "gf_raid.auras.debuff.filterToken", "CROWD_CONTROL" },
    { "show only externals on raid buffs", "gf_raid.auras.buff.filterToken", "ExternalDefensive" },
    { "show only my externals on raid buffs", "gf_raid.auras.buff.filterToken", "ExternalDefensivePlayer" },
    { "show all raid debuffs", "gf_raid.auras.debuff.filterToken", "ALL" },
    { "clear the raid debuff filter", "gf_raid.auras.debuff.filterToken", "ALL" },
}
for i = 1, #groupCases do
    local spec = groupCases[i]
    runCase("group scope/value collision: " .. spec[1], function()
        resetTask()
        local plan = A.Parse(spec[1])
        assertExactChange(plan, spec[2], spec[3], spec[1])
        for j = 1, #groupScopes do
            local scope = groupScopes[j]
            local lane = spec[2]:find("%.debuff%.") and "debuff" or "buff"
            local candidate = "gf_" .. scope .. ".auras." .. lane .. ".filterToken"
            if candidate ~= spec[2] then
                assert(not findChange(plan, candidate), spec[1] .. ": leaked into " .. candidate)
            end
        end
        assert(not findChange(plan, "auras3.player.buff.filter.onlyMine"),
            spec[1] .. ": confused the Player dropdown value with the Player frame")
    end)
end

runCase("explicit only-filter request replaces other lane filters", function()
    resetTask()
    state["auras3.target.debuff.filter.includeDispellable"].value = false
    state["auras3.target.debuff.filter.crowdControl"].value = true
    state.targetFiltersEnabled.value = false
    local result = assert(A.Submit("only show dispellable target debuffs"))
    assertDidNotRecover(result, "only-filter replacement")
    assert(status(result) == "applied" or status(result) == "unchanged", "explicit only-filter request did not execute")
    assert(state["auras3.target.debuff.filter.includeDispellable"].value == true, "only-filter request did not enable Dispellable")
    assert(state["auras3.target.debuff.filter.crowdControl"].value == false, "only-filter request did not clear Crowd Control")
    assert(state.targetFiltersEnabled.value == true, "only-filter request did not enable its master gate")
    assert(not lower(result.text):find("target debuffs from disabled to enabled", 1, true),
        "only-filter response reported a lane-visibility change")
end)

runCase("missing scope is a guided executable conversation", function()
    resetTask()
    state["auras3.target.debuff.filter.includeDispellable"].value = false
    state["auras3.target.debuff.filter.crowdControl"].value = true
    local first = assert(A.Submit("only show dispellable debuffs"))
    assert(status(first) == "ambiguous", "missing scope did not ask a question")
    assert(type(A.pendingChoices) == "table" and #A.pendingChoices >= 2,
        "missing-scope guidance did not expose executable scope choices")
    local scoped = assert(A.Submit("target"))
    assertDidNotRecover(scoped, "target scope reply")
    if status(scoped) == "ambiguous" then
        assert(type(A.pendingChoices) == "table" and #A.pendingChoices >= 2,
            "target scope reply did not continue to executable filter choices")
        scoped = assert(A.Submit("1"))
        assertDidNotRecover(scoped, "target scope numbered reply")
    end
    assert(status(scoped) == "applied" or status(scoped) == "unchanged", "guided target sequence did not execute")
    assert(state["auras3.target.debuff.filter.includeDispellable"].value == true,
        "guided target sequence did not enable Dispellable")
end)

runCase("guided filter choices execute a numbered reply", function()
    resetTask()
    state["auras3.target.buff.filter.onlyMine"].value = false
    local help = assert(A.Submit("help me filter target buffs"))
    assert(status(help) == "ambiguous", "scoped filter help did not present executable choices")
    assert(type(A.pendingChoices) == "table" and #A.pendingChoices >= 4,
        "scoped filter help choices were not stored")
    local second = assert(A.Submit("2"))
    assertDidNotRecover(second, "numbered filter choice")
    assert(status(second) == "applied" or status(second) == "unchanged", "numbered filter choice did not execute")
    assert(state["auras3.target.buff.filter.onlyMine"].value == true,
        "second guided choice did not select only auras applied by me")
end)

runCase("help then natural timed reply is executable", function()
    resetTask()
    state.playerHidePermanent.value = false
    state.playerBuffVisible.value = true
    state.playerFiltersEnabled.value = false
    local help = assert(A.Submit("help me filter player buffs"))
    assert(status(help) == "info" or status(help) == "ambiguous", "filter help did not answer")
    local helpText = lower(help.text)
    assert(helpText:find("player", 1, true) and helpText:find("buff", 1, true), "help lost the requested scope/lane")
    assert(helpText:find("permanent", 1, true) or helpText:find("timer", 1, true)
        or helpText:find("timed", 1, true) or helpText:find("expiration", 1, true),
        "help did not offer the relevant duration filter")
    local timed = assert(A.Submit("only timed ones"))
    assertDidNotRecover(timed, "only timed ones follow-up")
    assert(status(timed) == "applied" or status(timed) == "unchanged", "timed follow-up was not executable")
    assert(state.playerHidePermanent.value == true, "timed follow-up did not hide permanent Player Buffs")
    assert(state.playerBuffVisible.value == true, "timed follow-up disabled Player Buff visibility")
    assert(state.playerFiltersEnabled.value == false, "timed follow-up changed the unrelated live-filter gate")
end)

runCase("overview supports a guided dispellable follow-up", function()
    resetTask()
    state["auras3.target.debuff.filter.includeDispellable"].value = false
    local overview = assert(A.Submit("what aura filters are available"))
    assert(status(overview) == "info" or status(overview) == "ambiguous", "filter overview did not answer")
    local overviewText = lower(overview.text)
    assert(overviewText:find("dispellable", 1, true), "overview omitted Dispellable")
    assert(overviewText:find("player", 1, true) or overviewText:find("mine", 1, true),
        "overview omitted caster filtering")
    local nextResult = assert(A.Submit("dispellable debuffs"))
    assert(status(nextResult) == "ambiguous", "dispellable follow-up should ask for a scope")
    nextResult = assert(A.Submit("target"))
    assertDidNotRecover(nextResult, "overview target follow-up")
    if status(nextResult) == "ambiguous" then
        nextResult = assert(A.Submit("keep my other filters"))
        assertDidNotRecover(nextResult, "overview keep-filter reply")
    end
    assert(status(nextResult) == "applied" or status(nextResult) == "unchanged",
        "overview conversation never reached an executable filter")
    assert(state["auras3.target.debuff.filter.includeDispellable"].value == true,
        "overview conversation did not enable Target Dispellable")
end)

runCase("question-shaped no-timer request offers executable choices", function()
    resetTask()
    state.playerHidePermanent.value = false
    local question = assert(A.Submit("what filter can hide player buffs with no timer"))
    assert(status(question) == "ambiguous", "no-timer question did not offer a choice")
    assert(type(A.pendingChoices) == "table" and #A.pendingChoices == 2,
        "no-timer question did not store the two permanent-aura choices")
    local applied = assert(A.Submit("hide no-expiration buffs"))
    assertDidNotRecover(applied, "no-timer question choice")
    assert(status(applied) == "applied" or status(applied) == "unchanged",
        "no-timer question choice did not execute")
    assert(state.playerHidePermanent.value == true,
        "no-timer question choice did not enable Player Buff Hide Permanent")
end)

runCase("overview accepts a bare filter goal then a natural scope reply", function()
    resetTask()
    state["auras3.target.debuff.filter.includeDispellable"].value = false
    local overview = assert(A.Submit("what aura filters are available"))
    assert(status(overview) == "info" or status(overview) == "ambiguous", "overview did not answer")
    local goal = assert(A.Submit("dispellable"))
    assert(status(goal) == "ambiguous", "bare filter goal did not ask for a frame")
    assert(type(A.pendingChoices) == "table" and #A.pendingChoices >= 2,
        "bare filter goal did not create executable scope choices")
    local applied = assert(A.Submit("target debuffs"))
    assertDidNotRecover(applied, "bare filter goal scope reply")
    assert(status(applied) == "applied" or status(applied) == "unchanged",
        "bare filter goal scope reply did not execute")
    assert(state["auras3.target.debuff.filter.includeDispellable"].value == true,
        "bare filter goal sequence changed lane visibility instead of Dispellable")
end)

restoreSettings()

if #failures > 0 then
    io.stderr:write("assistant_aura_filter_conversation_regression: " .. tostring(#failures)
        .. " failed, " .. tostring(checks) .. " passed\n")
    for i = 1, #failures do io.stderr:write(tostring(i) .. ". " .. failures[i] .. "\n") end
    error("assistant aura-filter conversation regression failed")
end

print(string.format(
    "assistant_aura_filter_conversation_regression: ok checks=%d cold=%.2fms warm=%.2fms alias_index=cold",
    checks,
    tonumber(_G.__MSUF_AURA_FILTER_COLD_MS) or -1,
    tonumber(_G.__MSUF_AURA_FILTER_WARM_MS) or -1
))
