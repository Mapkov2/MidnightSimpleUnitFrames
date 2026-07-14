_G = _G or _ENV

local function Check(value, message)
    if not value then error("ASSISTANT CONTROL SCHEMA RETRIEVAL FAIL: " .. tostring(message), 2) end
end

local function Normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("Ã¤", "ae"):gsub("Ã¶", "oe"):gsub("Ã¼", "ue"):gsub("ÃŸ", "ss")
    return (value:gsub("[^%w]+", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function SplitMembership(value)
    local out = {}
    for item in tostring(value or ""):gmatch("[^,]+") do out[#out + 1] = item end
    return out
end

dofile("tools/assistant_dashboard_smoke.lua")

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local Menu = assert(MSUF.MSUF2, "Menu2 namespace missing")
local Assistant = assert(MSUF.Assistant, "Assistant namespace missing")
local Schema = assert(Assistant.ControlSchema, "Assistant.ControlSchema missing")
local Data = assert(Assistant.ControlSchemaData, "generated control schema data missing")

Check(Data.version == 3, "reviewed schema version")
Check(#(Data.contexts or {}) == 40, "reviewed 40 class/spec contexts")
Check(#(Data.collectionStates or {}) == 138, "reviewed 138-state finite UI matrix")
Check(Data.collectionUnionControls == 2725 and #(Data.records or {}) == 2725,
    "reviewed 2725-control exhaustive union")

local columns, contextIds, stateCounts = {}, {}, {}
for i = 1, #Data.columns do columns[Data.columns[i]] = i end
for _, required in ipairs({ "semanticId", "label", "pageKey", "controlPath", "states", "contexts" }) do
    Check(columns[required] ~= nil, "missing generated column " .. required)
end
for i = 1, #Data.contexts do
    local contextId = Data.contexts[i][1]
    Check(type(contextId) == "string" and contextId ~= "" and not contextIds[contextId],
        "invalid or duplicate context at " .. tostring(i))
    contextIds[contextId] = true
end
for i = 1, #Data.collectionStates do
    local stateId, count = Data.collectionStates[i][1], Data.collectionStates[i][2]
    Check(type(stateId) == "string" and stateId ~= "" and stateCounts[stateId] == nil,
        "invalid or duplicate finite state at " .. tostring(i))
    Check(type(count) == "number" and count > 0, "empty finite state " .. tostring(stateId))
    stateCounts[stateId] = count
end
Check(stateCounts.base ~= nil, "base finite state missing")

local function RowValue(row, name)
    return row[columns[name]]
end

local function StateContains(row, stateId)
    local membership = tostring(RowValue(row, "states") or "")
    if membership == "*" then return true end
    return ("," .. membership .. ","):find("," .. stateId .. ",", 1, true) ~= nil
end

local semanticIds, canonicalIdentities, labelGroups = {}, {}, {}
local observedStateCounts = {}
local observedContextCounts = {}
for stateId in pairs(stateCounts) do observedStateCounts[stateId] = 0 end
for contextId in pairs(contextIds) do observedContextCounts[contextId] = 0 end
for i = 1, #Data.records do
    local row = Data.records[i]
    local semanticId = tostring(RowValue(row, "semanticId") or "")
    local label = tostring(RowValue(row, "label") or "")
    local pageKey = tostring(RowValue(row, "pageKey") or "")
    local controlPath = tostring(RowValue(row, "controlPath") or "")
    Check(semanticId ~= "" and not semanticIds[semanticId], "missing or duplicate semantic ID at row " .. i)
    Check(label ~= "", "control has no searchable label: " .. semanticId)
    Check(pageKey ~= "", "control has no page identity: " .. semanticId)
    Check(controlPath ~= "", "control has no path identity: " .. semanticId)
    local contextMembership = tostring(RowValue(row, "contexts") or "")
    if contextMembership == "*" then
        for contextId in pairs(observedContextCounts) do
            observedContextCounts[contextId] = observedContextCounts[contextId] + 1
        end
    else
        local seenContexts = {}
        for _, contextId in ipairs(SplitMembership(contextMembership)) do
            Check(contextIds[contextId] and not seenContexts[contextId],
                "unknown or duplicate context " .. tostring(contextId) .. " for " .. semanticId)
            seenContexts[contextId] = true
            observedContextCounts[contextId] = observedContextCounts[contextId] + 1
        end
        Check(next(seenContexts) ~= nil, "empty context membership: " .. semanticId)
    end
    semanticIds[semanticId] = true

    local identity = table.concat({ Normalize(label), Normalize(pageKey), Normalize(controlPath) }, "\031")
    Check(not canonicalIdentities[identity], "canonical label/page/path collision: " .. semanticId
        .. " and " .. tostring(canonicalIdentities[identity]))
    canonicalIdentities[identity] = semanticId

    local normalizedLabel = Normalize(label)
    labelGroups[normalizedLabel] = labelGroups[normalizedLabel] or {}
    labelGroups[normalizedLabel][#labelGroups[normalizedLabel] + 1] = row

    local memberships = SplitMembership(RowValue(row, "states"))
    Check(RowValue(row, "states") == "*" or #memberships > 0, "empty state membership: " .. semanticId)
    if RowValue(row, "states") == "*" then
        for stateId in pairs(observedStateCounts) do observedStateCounts[stateId] = observedStateCounts[stateId] + 1 end
    else
        local seen = {}
        for _, stateId in ipairs(memberships) do
            Check(stateCounts[stateId] ~= nil and not seen[stateId], "unknown or duplicate state " .. stateId
                .. " for " .. semanticId)
            seen[stateId] = true
            observedStateCounts[stateId] = observedStateCounts[stateId] + 1
        end
    end
end
local controlsPerContext
for contextId, count in pairs(observedContextCounts) do
    controlsPerContext = controlsPerContext or count
    Check(count == controlsPerContext,
        string.format("cross-context control-count drift for %s: expected %d, got %d",
            contextId, controlsPerContext, count))
end
for stateId, expected in pairs(stateCounts) do
    Check(observedStateCounts[stateId] == expected,
        string.format("state membership drift for %s: expected %d, got %d",
            stateId, expected, observedStateCounts[stateId] or 0))
end

-- Exhaustive representative retrieval. Class/spec-specific action identities
-- use one context in which the row exists; global identities use Mage Arcane.
-- This exercises every immutable identity without multiplying the gate into
-- one full-index scan for every context/state combination.
local retrievalStarted = os.clock()
local canonicalUnique, fuzzyTop, safeMargins = 0, 0, 0
for i = 1, #Data.records do
    local row = Data.records[i]
    local semanticId = RowValue(row, "semanticId")
    local memberships = SplitMembership(RowValue(row, "states"))
    local stateId = RowValue(row, "states") == "*" and "base" or memberships[1]
    local contextMembership = tostring(RowValue(row, "contexts") or "")
    local representativeContext = contextMembership == "*" and "MAGE-62"
        or SplitMembership(contextMembership)[1]
    Check(contextIds[representativeContext], "representative context selection failed for " .. semanticId)
    Check(StateContains(row, stateId), "representative state selection failed for " .. semanticId)

    local label, pageKey, controlPath = RowValue(row, "label"), RowValue(row, "pageKey"), RowValue(row, "controlPath")
    local exact, exactStatus = Schema.FindCanonical(label, {
        pageKey = pageKey, controlPath = controlPath, contextId = representativeContext, stateId = stateId,
    })
    Check(exactStatus == "unique" and #exact == 1 and exact[1].semanticId == semanticId,
        "canonical lookup is not uniquely retrievable: " .. semanticId .. " (" .. tostring(exactStatus) .. ")")
    Check(exact[1]._canonicalStatus == "unique" and exact[1]._collisionCount == 1,
        "canonical lookup hid collision metadata: " .. semanticId)
    canonicalUnique = canonicalUnique + 1

    local query = Schema.CanonicalQuery({ label = label, pageKey = pageKey, controlPath = controlPath })
    local results = Schema.Find(query, { limit = 20, contextId = representativeContext, stateId = stateId })
    Check(results[1] and results[1].semanticId == semanticId,
        "canonical search did not rank exact identity first: " .. semanticId)
    fuzzyTop = fuzzyTop + 1
    local margin = results[2] and ((results[1]._score or 0) - (results[2]._score or 0)) or math.huge
    Check(margin >= 6, "canonical search lacks deterministic confidence margin: " .. semanticId
        .. " (" .. tostring(margin) .. ")")
    safeMargins = safeMargins + 1
end
local retrievalElapsed = os.clock() - retrievalStarted

-- Duplicate human labels are normal (for example the same Status Indicator
-- control on seven unit pages). A bare label is not enough authority to pick a
-- winner. The exact reviewed collision inventory is locked here; each group
-- must either return no usable token result or remain below the mutation/
-- navigation confidence margin, and the conversation facade must not open it.
local collisionGroups, collisionRows, maxCollision = 0, 0, 0
for _, group in pairs(labelGroups) do
    if #group > 1 then
        collisionGroups = collisionGroups + 1
        collisionRows = collisionRows + #group
        if #group > maxCollision then maxCollision = #group end
    end
end
Check(collisionGroups == 250 and collisionRows == 2169 and maxCollision == 57,
    string.format("reviewed label-collision inventory drift: groups=%d rows=%d max=%d",
        collisionGroups, collisionRows, maxCollision))

local originalOpenSetting = Menu.OpenExactSettingControl
local originalOpenCatalog = Menu.OpenExactCatalogControl
local originalCatalog = Menu.RuntimeControlCatalog
local openedSemanticId, catalogExecutions = nil, 0
Menu.OpenExactSettingControl = function(settingKey, label, pageKey)
    openedSemanticId = "setting:" .. tostring(settingKey)
    return true, "Opened exact setting control."
end
Menu.OpenExactCatalogControl = function(semanticId)
    openedSemanticId = semanticId
    return true, "Opened exact catalog control."
end
Menu.RuntimeControlCatalog = {
    Resolve = function(semanticId) return { controlId = "live." .. tostring(semanticId) }, {}, {} end,
    Read = function() return true, false end,
    Execute = function()
        catalogExecutions = catalogExecutions + 1
        return true
    end,
}

local ambiguousGroupsChecked = 0
for normalizedLabel, group in pairs(labelGroups) do
    if #group > 1 then
        local label = RowValue(group[1], "label")
        local results = Schema.Find(label, { limit = 20, contextId = "MAGE-62" })
        if #results >= 2 then
            local margin = (results[1]._score or 0) - (results[2]._score or 0)
            Check(margin < 6, "bare duplicate label became overconfident: " .. normalizedLabel
                .. " (margin " .. tostring(margin) .. ")")
        else
            -- Empty search results are acceptable only for labels made solely
            -- from intentionally ignored command/numeric tokens. One result
            -- would be an optimistic, collision-hiding winner.
            Check(#results == 0, "bare duplicate label returned one optimistic winner: " .. normalizedLabel)
        end
        openedSemanticId = nil
        local beforeExecutions = catalogExecutions
        local response = Schema.TryConversation("take me to " .. label)
        Check(openedSemanticId == nil and catalogExecutions == beforeExecutions,
            "ambiguous label navigation opened or executed a control: " .. normalizedLabel)
        Check(not response or (response.status ~= "navigated" and response.status ~= "applied"),
            "ambiguous label navigation reported success: " .. normalizedLabel)
        ambiguousGroupsChecked = ambiguousGroupsChecked + 1
    end
end
Check(ambiguousGroupsChecked == collisionGroups, "not every label collision was exercised")

-- Exact, reviewed test/preview mode inventory. This is an identity ledger, not
-- a minimum count: any new false positive or missing mode fails the gate.
local expectedModes = {
    ["action:class_power_preview_animate"] = true,
    ["action:preview_castbar"] = true,
    ["action:preview_group_status_icon"] = true,
    ["action:preview_player_totems"] = true,
    ["action:preview_unit_status_indicator"] = true,
    ["action:set_castbar_test_mode"] = true,
    ["action:toggle_absorb_bar_test"] = true,
    ["action:assistant.action.editMode.bossPreview"] = true,
    ["action:assistant.action.editMode.auras"] = true,
    ["action:assistant.action.editMode.groupPreview"] = true,
    ["action:assistant.action.editMode.preview"] = true,
    ["action:toggle_highlight_border_test"] = true,
    ["control:gameplay/gameplay/advanced/totem/frame/preview@gameplay/gameplay/advanced/totem/frame/preview"] = true,
    ["control:gf_auras/group/auras/spell/preview_all@gf_auras/group/auras/spell/preview_all"] = true,
    ["control:gf_indicators/group/indicators/status/preview/current@gf_indicators/group/indicators/status/preview/current"] = true,
    ["control:gf_indicators/group/indicators/status/advanced/preview/current@gf_indicators/group/indicators/status/advanced/preview/current"] = true,
    ["control:gf_indicators/group/indicators/status/advanced/preview/all@gf_indicators/group/indicators/status/advanced/preview/all"] = true,
    ["control:gf_indicators/group/indicators/status/preview/all@gf_indicators/group/indicators/status/preview/all"] = true,
    ["control:opt_bars/opt/bars/global/highlight/preview/aggro@opt_bars/opt/bars/global/highlight/preview/aggro"] = true,
    ["control:opt_bars/opt/bars/global/highlight/preview/boss/target@opt_bars/opt/bars/global/highlight/preview/boss/target"] = true,
    ["control:opt_bars/opt/bars/global/highlight/preview/dispel@opt_bars/opt/bars/global/highlight/preview/dispel"] = true,
    ["control:opt_bars/opt/bars/global/absorb/preview/test@opt_bars/opt/bars/global/absorb/preview/test"] = true,
    ["control:opt_bars/opt/bars/global/highlight/preview/purge@opt_bars/opt/bars/global/highlight/preview/purge"] = true,
    ["control:opt_castbar/opt/castbar/global/focus/kick/preview@opt_castbar/opt/castbar/global/focus/kick/preview"] = true,
}
local unitModeSuffixes = {
    "unit/status/preview/advanced/current",
    "unit/status/preview/advanced/all",
    "unit/status/preview/msuf2_status_adv_test",
    "unit/status/preview/basic/current",
    "unit/status/preview/basic/all",
    "unit/status/preview/msuf2_status_test",
}
for _, pageKey in ipairs({ "uf_boss", "uf_focus", "uf_focustarget", "uf_pet", "uf_player", "uf_target", "uf_targettarget" }) do
    for _, suffix in ipairs(unitModeSuffixes) do
        local semanticId = "control:" .. pageKey .. "/" .. suffix .. "@" .. pageKey .. "/" .. suffix
        expectedModes[semanticId] = true
    end
end

local modes = Schema.ListModes({ contextId = "MAGE-62" })
Check(#modes == 66, "reviewed test/preview mode count")
local seenModes, actionRuns, controlNavigations = {}, 0, 0
local originalActionRuns = {}
for i = 1, #modes do
    local mode = modes[i]
    local identity = mode.source == "action" and ("action:" .. tostring(mode.actionKey)) or tostring(mode.semanticId)
    Check(expectedModes[identity] == true, "unreviewed test/preview mode " .. identity)
    Check(not seenModes[identity], "duplicate test/preview mode " .. identity)
    Check(mode.label ~= "Highlight area", "workspace selector leaked into test/preview inventory")
    seenModes[identity] = true
    if mode.source == "action" then
        local action = assert(Assistant.Registry:GetAction(mode.actionKey), "mode action " .. tostring(mode.actionKey))
        originalActionRuns[action] = action.run
        action.run = function(...)
            actionRuns = actionRuns + 1
            return originalActionRuns[action](...)
        end
    end
end
for identity in pairs(expectedModes) do Check(seenModes[identity], "missing test/preview mode " .. identity) end

for i = 1, #modes do
    local mode = modes[i]
    openedSemanticId, catalogExecutions = nil, 0
    if mode.source == "control" then
        local response = Schema.TryConversation("take me to " .. Schema.CanonicalQuery(mode))
        Check(response and response.status == "navigated", "mode navigation did not navigate: " .. mode.semanticId)
        Check(openedSemanticId == mode.semanticId, "mode navigation focused wrong control: " .. mode.semanticId)
        Check(catalogExecutions == 0 and actionRuns == 0, "mode navigation executed transient UI: " .. mode.semanticId)
        controlNavigations = controlNavigations + 1
    else
        local beforeRuns = actionRuns
        local response = Schema.TryConversation("take me to " .. tostring(mode.label))
        Check(actionRuns == beforeRuns and catalogExecutions == 0,
            "explicit action-mode navigation executed " .. tostring(mode.actionKey))
        Check(not response or response.status ~= "applied",
            "explicit action-mode navigation reported execution for " .. tostring(mode.actionKey))
    end
end
Check(controlNavigations == 54 and actionRuns == 0, "reviewed mode navigation totals")

for action, run in pairs(originalActionRuns) do action.run = run end
Menu.OpenExactSettingControl = originalOpenSetting
Menu.OpenExactCatalogControl = originalOpenCatalog
Menu.RuntimeControlCatalog = originalCatalog

print(string.format(
    "assistant_control_schema_retrieval_audit: ok contexts=40 states=138 controls=%d canonical_unique=%d fuzzy_top=%d safe_margins=%d label_collision_groups=%d ambiguous_checked=%d modes=%d mode_navigation=%d elapsed=%.3fs",
    #Data.records, canonicalUnique, fuzzyTop, safeMargins, collisionGroups, ambiguousGroupsChecked,
    #modes, controlNavigations, retrievalElapsed))
