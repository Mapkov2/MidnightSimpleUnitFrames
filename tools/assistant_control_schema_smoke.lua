_G = _G or _ENV

local function Check(value, message)
    if not value then error("ASSISTANT CONTROL SCHEMA FAIL: " .. tostring(message), 2) end
end

dofile("tools/assistant_dashboard_smoke.lua")
local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant namespace missing")
local Schema = assert(A.ControlSchema, "Assistant.ControlSchema missing")
local Data = assert(A.ControlSchemaData, "generated schema data missing")

local contextIds, columns = {}, {}
for i = 1, #Data.contexts do
    local id = Data.contexts[i][1]
    Check(not contextIds[id], "duplicate context " .. tostring(id))
    contextIds[id] = true
end
Check(contextIds["DEMONHUNTER-1480"] and contextIds["DRUID-105"] and contextIds["EVOKER-1473"], "modern and four-spec contexts")
local expectedStateIds = { "base" }
local function AddState(stateId) expectedStateIds[#expectedStateIds + 1] = stateId end
local units = { "player", "target", "focus", "boss" }
local normalTools = { "layout", "filters", "blacklist" }
local customTools = { "setup", "layout", "filters", "whitelist" }
for _, unit in ipairs(units) do
    for _, container in ipairs({ "buff", "debuff" }) do
        for _, tool in ipairs(normalTools) do AddState("unit_" .. unit .. "_" .. container .. "_" .. tool) end
    end
    for index = 1, 3 do
        for _, tool in ipairs(customTools) do AddState("unit_" .. unit .. "_custom" .. index .. "_" .. tool) end
    end
    AddState("unit_" .. unit .. "_custom1_filters_debuff")
end
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    for _, lane in ipairs({ "buff", "debuff" }) do
        for _, tool in ipairs(normalTools) do AddState("gf_" .. scope .. "_" .. lane .. "_" .. tool) end
    end
    AddState("gf_" .. scope .. "_externals_layout")
end
for _, scope in ipairs({ "shared", "player", "target", "focus", "boss", "party", "raid" }) do
    local containers = (scope == "player" or scope == "target" or scope == "focus" or scope == "boss")
        and { "buff", "debuff", "custom1", "custom2", "custom3" } or { "buff", "debuff" }
    for _, container in ipairs(containers) do AddState("style_" .. scope .. "_" .. container) end
end
for _, scope in ipairs({ "shared", "player", "target", "focus", "boss", "party", "raid" }) do
    for _, lane in ipairs({ "buff", "debuff" }) do AddState("compat_" .. lane .. "_" .. scope) end
end
Check(#expectedStateIds == 138, "finite state-matrix test definition")

local collectionStates, stateOrder = {}, {}
for i = 1, #(Data.collectionStates or {}) do
    local stateId, count = Data.collectionStates[i][1], Data.collectionStates[i][2]
    Check(not collectionStates[stateId], "duplicate collection state " .. tostring(stateId))
    Check(stateId == expectedStateIds[i], "collection state order at " .. tostring(i))
    Check(type(count) == "number" and count > 0, "empty collection state " .. tostring(stateId))
    collectionStates[stateId] = count
    stateOrder[stateId] = i
end
Check(#(Data.collectionStates or {}) == #expectedStateIds, "complete 138-state inventory")
Check(collectionStates.base == 2073, "reviewed complete-catalog baseline")
Check(Data.collectionUnionControls == 2748 and #Data.records == Data.collectionUnionControls,
    "reviewed exhaustive finite-state control union")
for i = 1, #Data.columns do columns[Data.columns[i]] = i end
for _, column in ipairs({ "actionFixedArgs", "actionInputArg", "actionInputKind", "actionInputDomain",
    "storageUnit", "displayUnit", "displayScale", "states", "contexts" }) do
    Check(columns[column] ~= nil, "missing extensible schema column " .. column)
end
local semanticIds = {}
local allowedSafety = { direct=true, confirm=true, guided=true, readOnly=true, nonStateful=true }
local allowedValueKinds = {
    toggle = { boolean=true }, slider = { number=true }, dropdown = { enum=true }, segment = { enum=true },
    color = { color=true }, textinput = { string=true }, button = { action=true, text=true, boolean=true, enum=true },
    drag = { position=true }, dragrow = { enum=true },
}
local sawFallbackLocation, sawFallbackRange, sawFallbackChoices, sawDynamicChoices, sawPercentDomain
local observedMembershipStates = {}
local function StatePage(stateId)
    if stateId == "base" then return nil end
    local unit = stateId:match("^unit_(player)_") or stateId:match("^unit_(target)_")
        or stateId:match("^unit_(focus)_") or stateId:match("^unit_(boss)_")
    if unit then return "uf_" .. unit end
    if stateId:match("^gf_") then return "gf_auras" end
    if stateId:match("^style_") then return "auras3_styling" end
    if stateId:match("^compat_buff_") then return "auras3_buffs" end
    if stateId:match("^compat_debuff_") then return "auras3_debuffs" end
    return false
end
for i = 1, #Data.records do
    local row = Data.records[i]
    local semanticId = row[columns.semanticId]
    Check(not semanticIds[semanticId], "duplicate semantic ID " .. tostring(semanticId))
    semanticIds[semanticId] = true
    local classification, safety = row[columns.classification], row[columns.safety]
    Check(allowedSafety[safety], "invalid safety policy for " .. tostring(semanticId))
    Check(safety ~= "guided", "release schema retains an unowned guided control " .. tostring(semanticId))
    Check(classification ~= "setting" or safety ~= "readOnly",
        "release schema retains a read-only setting " .. tostring(semanticId))
    Check(row[columns.identityStable] == "1", "unstable generated identity " .. tostring(semanticId))
    local kind, valueKind = row[columns.kind], row[columns.valueKind]
    Check(valueKind ~= nil and valueKind ~= "", "missing value kind for " .. tostring(semanticId))
    Check(not allowedValueKinds[kind] or allowedValueKinds[kind][valueKind],
        "invalid " .. tostring(kind) .. " value kind " .. tostring(valueKind) .. " for " .. tostring(semanticId))
    if kind == "button" and (valueKind == "boolean" or valueKind == "enum") then
        Check(classification == "setting",
            "only a setting-backed shortcut button may expose a scalar value: " .. tostring(semanticId))
    end
    local help = row[columns.help]
    Check(help ~= nil and help ~= "", "missing semantic help for " .. tostring(semanticId))
    sawFallbackLocation = sawFallbackLocation or help:find("Available on the ", 1, true) ~= nil
    sawFallbackRange = sawFallbackRange or help:find("Allowed range: ", 1, true) ~= nil
    sawFallbackChoices = sawFallbackChoices or help:find("Available choices: ", 1, true) ~= nil
    sawDynamicChoices = sawDynamicChoices or help:find("Choices load from the current MSUF context.", 1, true) ~= nil
    sawPercentDomain = sawPercentDomain or (row[columns.storageUnit] == "fraction"
        and row[columns.displayUnit] == "percent" and row[columns.displayScale] == "100")
    local states = row[columns.states]
    local previousOrder = 0
    if states == "*" then
        for _, stateId in ipairs(expectedStateIds) do observedMembershipStates[stateId] = true end
    else
        Check(type(states) == "string" and states ~= "", "empty state membership for " .. tostring(semanticId))
        local localSeen = {}
        for stateId in states:gmatch("[^,]+") do
            Check(stateOrder[stateId] ~= nil, "unknown finite state " .. stateId .. " for " .. tostring(semanticId))
            Check(not localSeen[stateId], "duplicate finite state " .. stateId .. " for " .. tostring(semanticId))
            Check(stateOrder[stateId] > previousOrder, "non-deterministic state order for " .. tostring(semanticId))
            local ownerPage = StatePage(stateId)
            Check(ownerPage ~= false, "unclassified finite state " .. tostring(stateId))
            Check(not ownerPage or ownerPage == row[columns.pageKey],
                "page-local state leak for " .. tostring(semanticId) .. " in " .. tostring(stateId))
            localSeen[stateId], observedMembershipStates[stateId] = true, true
            previousOrder = stateOrder[stateId]
        end
    end
    local contexts = row[columns.contexts]
    if contexts ~= "*" then
        for contextId in tostring(contexts):gmatch("[^,]+") do Check(contextIds[contextId], "unknown row context " .. contextId) end
    end
end
Check(sawFallbackLocation and sawFallbackRange and sawFallbackChoices and sawDynamicChoices,
    "generated schema is missing deterministic location, bounds, enum, or dynamic-choice help")
Check(sawPercentDomain, "generated schema is missing explicit percent storage/display metadata")
for _, stateId in ipairs(expectedStateIds) do
    Check(observedMembershipStates[stateId], "finite state absent from all record memberships: " .. stateId)
end

local function FunctionFree(value, seen)
    if type(value) == "function" then return false end
    if type(value) ~= "table" then return true end
    seen = seen or {}
    if seen[value] then return true end
    seen[value] = true
    for key, child in pairs(value) do
        if not FunctionFree(key, seen) or not FunctionFree(child, seen) then return false end
    end
    return true
end
Check(FunctionFree(Data), "generated schema data must remain function-free")

local before = Schema.Stats()
Check(before.version == 3, "schema version must be 3")
Check(before.contexts == 40, "all 40 class/spec contexts must be present")
Check(before.records == 2748, "public control inventory must equal the reviewed exhaustive finite-state union")
Check(before.indexed == false, "schema index must remain lazy")

local coldStart = os.clock()
local ready = Schema.Find("where is Ready Check Icon", { limit = 4, contextId = "MAGE-62" })
local coldElapsed = os.clock() - coldStart
Check(#ready > 0 and (tostring(ready[1].matchedValue):lower() .. " " .. tostring(ready[1].label):lower()):find("ready", 1, true), "Ready Check Icon precision")
Check(Schema.Stats().indexed == true, "first query must build the lazy index")
Check(coldElapsed <= 0.050, string.format("cold schema query exceeded 50ms: %.3fms", coldElapsed * 1000))

local hotStart = os.clock()
local readyAgain = Schema.Find("where is Ready Check Icon", { limit = 4, contextId = "MAGE-62" })
local hotElapsed = os.clock() - hotStart
Check(#readyAgain > 0 and readyAgain[1].semanticId == ready[1].semanticId, "bounded query cache drift")
Check(hotElapsed <= 0.005, string.format("hot schema query exceeded 5ms: %.3fms", hotElapsed * 1000))

local prompts = {
    { text = "where is the PvP icon", needle = "pvp" },
    { text = "where are Target Buffs", needle = "buff" },
    { text = "where are Target Debuffs", needle = "debuff" },
}
for i = 1, #prompts do
    local row = prompts[i]
    local results = Schema.Find(row.text, { limit = 4, contextId = "MAGE-62" })
    local top = results[1]
    Check(top and (tostring(top.matchedValue):lower() .. " " .. tostring(top.label):lower() .. " " .. tostring(top.controlPath):lower()):find(row.needle, 1, true), row.text .. " precision")
end

local targetRows = Schema.GetBySettingKey("target.enabled")
Check(type(targetRows) == "table", "GetBySettingKey must return a list")
local unknown, reason = Schema.Resolve("setting:does.not.exist")
Check(unknown == false and reason == "unknown_control", "unknown semantic IDs must fail closed")

local modes = Schema.ListModes({ contextId = "MAGE-62" })
Check(type(modes) == "table" and #modes == 66, "reviewed test and preview mode inventory")
local expectedModeActions = {
    class_power_preview_animate=true, preview_castbar=true, preview_group_status_icon=true,
    preview_player_totems=true, preview_unit_status_indicator=true, set_castbar_test_mode=true,
    toggle_absorb_bar_test=true, ["assistant.action.editMode.bossPreview"]=true,
    ["assistant.action.editMode.auras"]=true, ["assistant.action.editMode.groupPreview"]=true,
    ["assistant.action.editMode.preview"]=true, toggle_highlight_border_test=true,
}
local expectedControlPages = {
    gameplay=1, gf_auras=1, gf_indicators=4, opt_bars=5, opt_castbar=1,
    uf_boss=6, uf_focus=6, uf_focustarget=6, uf_pet=6, uf_player=6,
    uf_target=6, uf_targettarget=6,
}
local seenModeActions, seenControlPages, foundPredictionMode = {}, {}, nil
for i = 1, #modes do
    local mode = modes[i]
    Check(mode.label ~= "Highlight area", "workspace selector must not be classified as an executable preview mode")
    if mode.source == "action" then
        Check(expectedModeActions[mode.actionKey] == true, "unreviewed mode action " .. tostring(mode.actionKey))
        Check(not seenModeActions[mode.actionKey], "duplicate mode action " .. tostring(mode.actionKey))
        seenModeActions[mode.actionKey] = true
    else
        Check(expectedControlPages[mode.pageKey] ~= nil,
            "unreviewed mode control page " .. tostring(mode.pageKey) .. " for " .. tostring(mode.semanticId))
        seenControlPages[mode.pageKey] = (seenControlPages[mode.pageKey] or 0) + 1
    end
    if tostring(mode.label):lower():find("prediction bars", 1, true) then foundPredictionMode = true end
end
for actionKey in pairs(expectedModeActions) do Check(seenModeActions[actionKey], "missing mode action " .. actionKey) end
for pageKey, expected in pairs(expectedControlPages) do
    Check(seenControlPages[pageKey] == expected,
        string.format("mode inventory drift on %s: expected %d, got %d", pageKey, expected, seenControlPages[pageKey] or 0))
end
Check(foundPredictionMode, "prediction bar test must be launchable")

local Menu = assert(_G.MSUF_NS.MSUF2, "Menu2 namespace missing")
local originalCatalog = Menu.RuntimeControlCatalog
local originalOpenExactCatalogControl = Menu.OpenExactCatalogControl
local openedSemanticId, executedControlId, executedValue
Menu.OpenExactCatalogControl = function(semanticId)
    openedSemanticId = semanticId
    return true, "Opened exact generated control."
end
Menu.RuntimeControlCatalog = {
    Resolve = function(semanticId)
        return { controlId = "live." .. tostring(semanticId) }, {}, {}
    end,
    Read = function() return true, false end,
    Execute = function(controlId, value)
        executedControlId, executedValue = controlId, value
        return true
    end,
}
local locationResult = Schema.TryConversation("direct me to Ready Check Icon")
Check(locationResult and locationResult.status == "navigated" and openedSemanticId,
    "location requests must open and focus exact generated controls with canonical navigation status")
openedSemanticId, executedControlId, executedValue = nil, nil, nil
local launchResult = Schema.TryConversation("start test prediction bars")
Check(launchResult and launchResult.status == "applied", "natural test-mode launch must use canonical mutation status")
Check(openedSemanticId and executedControlId and executedValue == true, "test-mode launch must open, focus, and execute the exact toggle")
openedSemanticId, executedControlId, executedValue = nil, nil, nil
local modeNavigation = Schema.TryConversation("take me to test prediction bars")
Check(modeNavigation and modeNavigation.status == "navigated" and openedSemanticId and executedControlId == nil,
    "explicit test-mode navigation must focus the control without executing it")
openedSemanticId, executedControlId, executedValue = nil, nil, nil
local stopResult = Schema.TryConversation("stop test prediction bars")
Check(stopResult and stopResult.status == "applied" and openedSemanticId and executedControlId and executedValue == false,
    "natural test-mode stop must focus and disable the exact toggle")
openedSemanticId, executedControlId, executedValue = nil, nil, nil
local toggleResult = Schema.TryConversation("toggle test prediction bars")
Check(toggleResult and toggleResult.status == "applied" and openedSemanticId and executedControlId and executedValue == true,
    "natural test-mode toggle must read and invert the exact toggle")
Menu.RuntimeControlCatalog = originalCatalog
Menu.OpenExactCatalogControl = originalOpenExactCatalogControl

local castbarTest = assert(A.Registry:GetAction("set_castbar_test_mode"), "castbar test-mode action")
local originalEditModeSet = A.Workflow.EditMode.Set
local originalTargetTest = _G.MSUF_SetTargetCastbarTestMode
local enteredEditMode, castbarEnabled, castbarTransient
A.Workflow.EditMode.Set = function(value, unit)
    enteredEditMode = value == true and unit == "target"
    return true
end
_G.MSUF_SetTargetCastbarTestMode = function(value, transient)
    castbarEnabled, castbarTransient = value, transient
end
local castbarOk = castbarTest.run({ unit = "target", value = true })
Check(castbarOk == true and enteredEditMode and castbarEnabled == true and castbarTransient == true,
    "target castbar test must enter Edit Mode and launch transiently")
local parsedGermanStop = A.Parse("stoppe ziel zauberleisten testmodus")
Check(parsedGermanStop and parsedGermanStop.action == castbarTest and parsedGermanStop.args.unit == "target"
    and parsedGermanStop.args.value == false, "German castbar test stop intent")
A.Workflow.EditMode.Set = originalEditModeSet
_G.MSUF_SetTargetCastbarTestMode = originalTargetTest

Check(Schema.RegisterPack("zzZZ", { found = "ZZ {label}" }) == true, "locale pack registration")
Check(Schema.Render("found", { label = "Control" }, "zzZZ") == "ZZ Control", "locale pack render")
Check(Schema.Render("found", { label = "Control" }, "xxXX") == "I found Control.", "locale fallback")

print(string.format("assistant_control_schema_smoke: ok (%d contexts, %d controls, cold=%.3fms, hot=%.3fms)",
    before.contexts, before.records, coldElapsed * 1000, hotElapsed * 1000))
