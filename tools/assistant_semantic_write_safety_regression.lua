_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

-- WoW accepts a UTF-8 BOM on Lua sources, while standalone PUC Lua 5.1 does
-- not. Keep production files byte-for-byte intact and strip only that marker
-- in this disposable test process.
local function TestLoadfile(path)
    local handle, openError = io.open(path, "rb")
    if not handle then return nil, openError end
    local source = handle:read("*a")
    handle:close()
    if source:sub(1, 3) == string.char(239, 187, 191) then source = source:sub(4) end
    return (loadstring or load)(source, "@" .. path)
end
loadfile = TestLoadfile

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant registry missing")
if type(A.AutoCoverage) == "table" and type(A.AutoCoverage.Fill) == "function" then
    A.AutoCoverage.Fill()
end

local function status(result)
    return result and (result.status or result.result)
end

local function resultText(result)
    return tostring(result and result.text or "")
end

local function resetTask()
    if type(A.StartNewTask) == "function" then A.StartNewTask() end
    A.pendingConfirmation = nil
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    if type(A.ClearPendingFlow) == "function" then
        A.ClearPendingFlow()
    else
        A.pendingFlow = nil
    end
    A.undoStack = {}
    A.redoStack = {}
    local context = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(context) == "table" then
        for key in pairs(context) do context[key] = nil end
    end
end

local patched = {}
local function patchSetting(key, initial)
    local setting = assert(Registry:GetSetting(key), "missing setting " .. key)
    local original = { get = setting.get, set = setting.set, apply = setting.apply }
    local box = { value = initial, writes = 0, values = {} }
    setting.get = function() return box.value end
    setting.set = function(value)
        box.writes = box.writes + 1
        box.values[#box.values + 1] = value
        box.value = value
    end
    setting.apply = function() return true end
    patched[#patched + 1] = { setting = setting, original = original }
    return box
end

local function resetBox(box, value)
    box.value = value
    box.writes = 0
    box.values = {}
end

local function submit(prompt)
    local result = assert(A.Submit(prompt), prompt .. ": no Assistant result")
    assert(status(result) ~= "failed", prompt .. ": failed: " .. resultText(result))
    return result
end

local function assertNoWrite(prompt, box, initial)
    resetTask()
    resetBox(box, initial)
    local result = submit(prompt)
    assert(box.value == initial,
        prompt .. ": changed value from " .. tostring(initial) .. " to " .. tostring(box.value)
            .. "; status=" .. tostring(status(result)) .. " text=" .. resultText(result))
    assert(box.writes == 0,
        prompt .. ": invoked the setting setter " .. tostring(box.writes) .. " time(s)")
    assert(#A.undoStack == 0, prompt .. ": created an undoable mutation")
    return result
end

local targetWidth = patchSetting("target.width", 275)
local targetNameX = patchSetting("target.nameOffsetX", 0)
local targetNameY = patchSetting("target.nameOffsetY", 0)
local targetPortrait = patchSetting("target.portraitSizeOverride", 40)
local targetPortraitMode = patchSetting("target.portraitMode", "RIGHT")
local playerPortrait = patchSetting("player.portraitSizeOverride", 52)
local targetNameSize = patchSetting("target.nameFontSize", 12)
local targetHealthSize = patchSetting("target.hpFontSize", 20)
local targetBuffs = patchSetting("auras3.target.buff.visible", true)
local targetDebuffs = patchSetting("auras3.target.debuff.visible", true)
local sharedBuffs = patchSetting("auras3.shared.showBuffs", false)
local targetPowerText = patchSetting("target.showPowerText", false)
local targetPowerBar = patchSetting("target.showPowerBar", true)
local globalTargetPowerBar = patchSetting("bars.showTargetPowerBar", true)
local targetCastbarX = patchSetting("general.castbarTargetOffsetX", 11)
local targetCastbarY = patchSetting("general.castbarTargetOffsetY", -7)
local targetCastbarIconX = patchSetting("general.castbarTargetIconOffsetX", 3)
local targetCastbarIconY = patchSetting("general.castbarTargetIconOffsetY", -2)

local cases = 0
local function counted()
    cases = cases + 1
end

-- A visible Aura Style reset action must win over the similarly worded
-- generated show-buffs setting. The destructive reset remains confirmation
-- gated and must not write an unrelated lane-visibility control.
resetTask()
resetBox(sharedBuffs, false)
local auraStyleReset = submit("reset buff aura style overrides")
assert(status(auraStyleReset) == "confirmation_needed",
    "Aura Style reset did not route to its confirmation-gated action: "
        .. tostring(status(auraStyleReset)) .. " text=" .. resultText(auraStyleReset))
assert(sharedBuffs.value == false and sharedBuffs.writes == 0,
    "Aura Style reset mutated the shared show-buffs setting")
assert(type(A.pendingConfirmation) == "table",
    "Aura Style reset did not retain a pending confirmation")
counted()

-- Fully scoped clauses inherit the explicit setting verb and are committed by
-- one ExecutePlan call. Neither valid clause may be silently dropped.
resetTask()
resetBox(targetWidth, 275)
resetBox(targetPortraitMode, "RIGHT")
local mixedCompound = submit("set target width to 300 and target portrait position to left")
assert(status(mixedCompound) == "applied" or status(mixedCompound) == "unchanged",
    "mixed compound setting request did not execute: " .. resultText(mixedCompound))
assert(targetWidth.value == 300 and targetPortraitMode.value == "LEFT",
    "mixed compound setting request dropped a clause: width=" .. tostring(targetWidth.value)
        .. " portrait=" .. tostring(targetPortraitMode.value) .. " text=" .. resultText(mixedCompound))
assert(targetWidth.writes == 1 and targetPortraitMode.writes == 1,
    "mixed compound setting request did not write each exact control once")
assert(#A.undoStack == 1, "mixed compound setting request was not one atomic undo transaction")
counted()

-- If any explicit clause cannot be planned, no earlier clause may commit and
-- the response must state that the complete request was left unchanged.
resetTask()
resetBox(targetWidth, 275)
local invalidCompound = submit("set target width to 300 and set nonexistent foo to 7")
assert(status(invalidCompound) == "ambiguous",
    "invalid compound request did not fail closed: " .. tostring(status(invalidCompound)))
assert(targetWidth.value == 275 and targetWidth.writes == 0 and #A.undoStack == 0,
    "invalid compound request partially committed its first clause")
assert(resultText(invalidCompound):find("kept MSUF unchanged", 1, true),
    "invalid compound response did not honestly report zero mutation")
counted()

-- Complete visible labels inside questions, counterfactuals, and preview
-- requests must never be reinterpreted as permission to write the control.
local readonly = assertNoWrite("what is Target Width set to", targetWidth, 275)
assert(status(readonly) == "info" or status(readonly) == "ambiguous",
    "exact-label question was not read-only: " .. tostring(status(readonly)))
counted()

local counterfactual = assertNoWrite("if Target Width were 300 would it be too wide", targetWidth, 275)
assert(status(counterfactual) == "info" or status(counterfactual) == "ambiguous",
    "exact-label counterfactual was treated as a command: " .. tostring(status(counterfactual)))
counted()

local preview = assertNoWrite("preview Target Width at 300 without applying it", targetWidth, 275)
assert(status(preview) == "info" or status(preview) == "ambiguous" or status(preview) == "navigated",
    "exact-label preview was treated as a saved-setting command: " .. tostring(status(preview)))
counted()

-- Each direction owns its adjacent amount. The common plain phrase "target
-- name" must receive the same guarded routing as the more formal "name text".
resetTask()
resetBox(targetNameX, 0)
resetBox(targetNameY, 0)
local diagonal = submit("move target name up 5 and right 10")
assert(status(diagonal) == "applied" or status(diagonal) == "unchanged", resultText(diagonal))
assert(targetNameX.value == 10 and targetNameY.value == 5,
    "direction-specific amounts crossed: x=" .. tostring(targetNameX.value)
        .. " y=" .. tostring(targetNameY.value) .. " text=" .. resultText(diagonal))
assert(targetNameX.writes == 1 and targetNameY.writes == 1,
    "diagonal command did not write exactly the two intended axes")
counted()

resetTask()
resetBox(targetNameX, 0)
resetBox(targetNameY, 0)
local reverseDiagonal = submit("move target name 10 right and 5 up")
assert(status(reverseDiagonal) == "applied" or status(reverseDiagonal) == "unchanged", resultText(reverseDiagonal))
assert(targetNameX.value == 10 and targetNameY.value == 5,
    "reversed direction order crossed amounts: x=" .. tostring(targetNameX.value)
        .. " y=" .. tostring(targetNameY.value) .. " text=" .. resultText(reverseDiagonal))
counted()

resetTask()
resetBox(targetNameX, 7)
resetBox(targetNameY, -3)
local verticalConflict = submit("move target name up and down")
assert(status(verticalConflict) == "ambiguous" or status(verticalConflict) == "info",
    "same-axis vertical conflict was not clarified: " .. tostring(status(verticalConflict)))
assert(targetNameX.value == 7 and targetNameY.value == -3
        and targetNameX.writes == 0 and targetNameY.writes == 0,
    "same-axis vertical conflict wrote a name offset: x=" .. tostring(targetNameX.value)
        .. " y=" .. tostring(targetNameY.value))
assert(#A.undoStack == 0, "same-axis vertical conflict created undo state")
counted()

resetTask()
resetBox(targetNameX, 7)
resetBox(targetNameY, -3)
local horizontalConflict = submit("move target name 5 left and 10 right")
assert(status(horizontalConflict) == "ambiguous" or status(horizontalConflict) == "info",
    "same-axis horizontal conflict was not clarified: " .. tostring(status(horizontalConflict)))
assert(targetNameX.value == 7 and targetNameY.value == -3
        and targetNameX.writes == 0 and targetNameY.writes == 0,
    "same-axis horizontal conflict wrote a name offset: x=" .. tostring(targetNameX.value)
        .. " y=" .. tostring(targetNameY.value))
assert(#A.undoStack == 0, "same-axis horizontal conflict created undo state")
counted()

resetTask()
resetBox(targetCastbarX, 11)
resetBox(targetCastbarY, -7)
resetBox(targetCastbarIconX, 3)
resetBox(targetCastbarIconY, -2)
local castbarConflict = submit("move target castbar icon left and right")
assert(status(castbarConflict) == "ambiguous" or status(castbarConflict) == "info",
    "castbar same-axis conflict was not clarified: " .. tostring(status(castbarConflict))
        .. " text=" .. resultText(castbarConflict))
assert(targetCastbarX.value == 11 and targetCastbarY.value == -7
        and targetCastbarIconX.value == 3 and targetCastbarIconY.value == -2,
    "castbar conflict moved a root/icon offset: root=" .. tostring(targetCastbarX.value)
        .. "/" .. tostring(targetCastbarY.value) .. " icon=" .. tostring(targetCastbarIconX.value)
        .. "/" .. tostring(targetCastbarIconY.value))
assert(targetCastbarX.writes == 0 and targetCastbarY.writes == 0
        and targetCastbarIconX.writes == 0 and targetCastbarIconY.writes == 0,
    "castbar conflict invoked a root/icon offset setter")
assert(#A.undoStack == 0, "castbar same-axis conflict created undo state")
local castbarConflictText = resultText(castbarConflict):lower()
local asksDirection = castbarConflictText:find("pick one", 1, true)
    or castbarConflictText:find("which direction", 1, true)
    or castbarConflictText:find("choose a direction", 1, true)
    or castbarConflictText:find("say left", 1, true)
if asksDirection then
    local flow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
        and A.Workflow.PendingFlow() or A.pendingFlow
    assert(type(flow) == "table" and flow.kind == "settingMovement",
        "castbar direction prompt did not retain an exact settingMovement flow")
    assert(flow.xKey == "general.castbarTargetIconOffsetX"
            and flow.yKey == "general.castbarTargetIconOffsetY",
        "castbar direction prompt retained the wrong movement controls: "
            .. tostring(flow.xKey) .. "/" .. tostring(flow.yKey))
end
counted()

resetTask()
resetBox(targetCastbarX, 11)
resetBox(targetCastbarY, -7)
local castbarRootConflict = submit("move target castbar left and right")
assert(status(castbarRootConflict) == "ambiguous" or status(castbarRootConflict) == "info",
    "root castbar same-axis conflict was not clarified: " .. tostring(status(castbarRootConflict))
        .. " text=" .. resultText(castbarRootConflict))
assert(targetCastbarX.value == 11 and targetCastbarY.value == -7
        and targetCastbarX.writes == 0 and targetCastbarY.writes == 0,
    "root castbar conflict moved an offset: " .. tostring(targetCastbarX.value)
        .. "/" .. tostring(targetCastbarY.value))
assert(#A.undoStack == 0, "root castbar conflict created undo state")
counted()

resetTask()
resetBox(targetCastbarX, 11)
resetBox(targetCastbarY, -7)
local castbarRootAmounts = submit("move target castbar right 5 10")
assert(status(castbarRootAmounts) == "ambiguous" or status(castbarRootAmounts) == "info",
    "root castbar multi-amount request was not clarified: " .. tostring(status(castbarRootAmounts))
        .. " text=" .. resultText(castbarRootAmounts))
assert(targetCastbarX.value == 11 and targetCastbarY.value == -7
        and targetCastbarX.writes == 0 and targetCastbarY.writes == 0,
    "root castbar multi-amount request moved an offset: " .. tostring(targetCastbarX.value)
        .. "/" .. tostring(targetCastbarY.value))
assert(#A.undoStack == 0, "root castbar multi-amount request created undo state")
counted()

resetTask()
resetBox(targetCastbarX, 11)
resetBox(targetCastbarY, -7)
local castbarRootDiagonal = submit("move target castbar up 5 and right 10")
if status(castbarRootDiagonal) == "applied" or status(castbarRootDiagonal) == "unchanged" then
    assert(targetCastbarX.value == 21 and targetCastbarY.value == -2,
        "root castbar diagonal crossed or dropped an axis: " .. tostring(targetCastbarX.value)
            .. "/" .. tostring(targetCastbarY.value) .. " text=" .. resultText(castbarRootDiagonal))
    assert(targetCastbarX.writes == 1 and targetCastbarY.writes == 1,
        "root castbar diagonal did not write exactly its two intended axes")
else
    assert(status(castbarRootDiagonal) == "ambiguous" or status(castbarRootDiagonal) == "info",
        "root castbar diagonal was neither exact nor safely clarified: " .. resultText(castbarRootDiagonal))
    assert(targetCastbarX.value == 11 and targetCastbarY.value == -7
            and targetCastbarX.writes == 0 and targetCastbarY.writes == 0,
        "root castbar diagonal partially wrote an offset")
    assert(#A.undoStack == 0, "root castbar diagonal clarification created undo state")
end
counted()

-- Comparative requests may derive the subject value from a reference, but the
-- reference control itself is read-only.
resetTask()
resetBox(targetPortrait, 40)
resetBox(playerPortrait, 52)
local portraitComparison = submit("make target portrait bigger than player portrait")
if status(portraitComparison) == "applied" or status(portraitComparison) == "unchanged" then
    assert(targetPortrait.value > playerPortrait.value,
        "comparative portrait did not make the subject larger than its reference: target="
            .. tostring(targetPortrait.value) .. " player=" .. tostring(playerPortrait.value))
    assert(targetPortrait.writes == 1, "comparative portrait did not write exactly one subject control")
else
    assert(status(portraitComparison) == "ambiguous" or status(portraitComparison) == "info",
        "comparative portrait was neither safely applied nor clarified: " .. resultText(portraitComparison))
    assert(targetPortrait.value == 40 and targetPortrait.writes == 0,
        "comparative portrait clarification wrote the subject before receiving an amount")
    local flow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
        and A.Workflow.PendingFlow() or A.pendingFlow
    assert(type(flow) == "table" and flow.kind == "settingValue"
            and flow.settingKey == "target.portraitSizeOverride",
        "comparative portrait did not retain exactly its subject for clarification")
end
assert(playerPortrait.value == 52 and playerPortrait.writes == 0,
    "comparative portrait mutated the Player reference control")
counted()

resetTask()
resetBox(targetNameSize, 12)
resetBox(targetHealthSize, 20)
local textComparison = submit("make target name text bigger than target health text")
if status(textComparison) == "applied" or status(textComparison) == "unchanged" then
    assert(targetNameSize.value > targetHealthSize.value,
        "comparative text request did not make Name larger than Health: name="
            .. tostring(targetNameSize.value) .. " health=" .. tostring(targetHealthSize.value))
    assert(targetNameSize.writes == 1, "comparative text request did not write exactly one subject control")
else
    assert(status(textComparison) == "ambiguous" or status(textComparison) == "info",
        "comparative text request was neither safely applied nor clarified: " .. resultText(textComparison))
    assert(targetNameSize.value == 12 and targetNameSize.writes == 0,
        "comparative text clarification wrote the subject before receiving an amount")
    local flow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
        and A.Workflow.PendingFlow() or A.pendingFlow
    assert(type(flow) == "table" and flow.kind == "settingValue"
            and flow.settingKey == "target.nameFontSize",
        "comparative text request did not retain exactly its Name subject")
end
assert(targetHealthSize.value == 20 and targetHealthSize.writes == 0,
    "comparative text request mutated the Health reference control")
counted()

-- "Keep" retains the second control; "but don't" is a second explicit
-- negative clause and must target the frame-local Power Bar, not its unrelated
-- generated/global fallback.
resetTask()
resetBox(targetBuffs, true)
resetBox(targetDebuffs, true)
local keep = submit("hide target buffs but keep target debuffs")
assert(status(keep) == "applied" or status(keep) == "unchanged", resultText(keep))
assert(targetBuffs.value == false, "keep compound did not hide Target Buffs: buffs="
    .. tostring(targetBuffs.value) .. " debuffs=" .. tostring(targetDebuffs.value)
    .. " text=" .. resultText(keep))
assert(targetDebuffs.value == true, "keep compound changed retained Target Debuffs: buffs="
    .. tostring(targetBuffs.value) .. " debuffs=" .. tostring(targetDebuffs.value)
    .. " writes=" .. tostring(targetBuffs.writes) .. "/" .. tostring(targetDebuffs.writes)
    .. " text=" .. resultText(keep))
assert(targetBuffs.writes == 1 and targetDebuffs.writes == 0,
    "keep compound wrote the retained control or missed the requested control")
counted()

resetTask()
resetBox(targetPowerText, false)
resetBox(targetPowerBar, true)
resetBox(globalTargetPowerBar, true)
local dont = submit("show target power text but don't show target power bar")
assert(status(dont) == "applied" or status(dont) == "unchanged", resultText(dont))
assert(targetPowerText.value == true, "don't compound did not show frame-local Target Power Text")
assert(targetPowerBar.value == false, "don't compound did not hide frame-local Target Power Bar")
assert(targetPowerText.writes == 1 and targetPowerBar.writes == 1,
    "don't compound did not write exactly its two intended controls")
assert(globalTargetPowerBar.value == true and globalTargetPowerBar.writes == 0,
    "don't compound mutated the unrelated global Target Power Bar fallback")
counted()

-- Broad optimization language is planning, not permission to guess a slider.
-- If the reply asks for a number anyway, that prompt is safe only when the
-- conversation retained one concrete numeric setting that can consume it.
resetTask()
local broadWriteCount, broadWriteKeys = 0, {}
local broadWrappers = {}
for _, setting in ipairs(Registry:AllSettings() or {}) do
    if type(setting) == "table" and type(setting.set) == "function" then
        local ownedSetting, originalSet = setting, setting.set
        broadWrappers[#broadWrappers + 1] = { setting = ownedSetting, set = originalSet }
        ownedSetting.set = function(value)
            broadWriteCount = broadWriteCount + 1
            broadWriteKeys[#broadWriteKeys + 1] = tostring(ownedSetting.key)
            return originalSet(value)
        end
    end
end
local optimize = submit("optimize party frames")
for i = #broadWrappers, 1, -1 do
    broadWrappers[i].setting.set = broadWrappers[i].set
end
assert(broadWriteCount == 0,
    "broad optimization request wrote setting(s): " .. table.concat(broadWriteKeys, ", ")
        .. " text=" .. resultText(optimize))
assert(#A.undoStack == 0, "broad optimization request created undo state")
local optimizeText = resultText(optimize):lower()
local asksForNumber = optimizeText:find("what value", 1, true)
    or optimizeText:find("choose a number", 1, true)
    or optimizeText:find("use a number", 1, true)
    or optimizeText:find("give me its number", 1, true)
    or optimizeText:find("tell me the value", 1, true)
if asksForNumber then
    local targets = {}
    local function retainTarget(key)
        key = tostring(key or "")
        local setting = key ~= "" and Registry:GetSetting(key) or nil
        if setting and setting.type == "number" then targets[key] = true end
    end
    local flow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
        and A.Workflow.PendingFlow() or A.pendingFlow
    if type(flow) == "table" and flow.kind == "settingValue" then retainTarget(flow.settingKey) end
    local selected = A.pendingSelectedResult
    if type(selected) == "table" then
        retainTarget(selected.settingKey or selected.key
            or (selected.setting and selected.setting.key)
            or (selected.item and selected.item.setting and selected.item.setting.key))
    end
    local count, retainedKey = 0, nil
    for key in pairs(targets) do count, retainedKey = count + 1, key end
    assert(count == 1,
        "numeric optimization prompt retained " .. tostring(count)
            .. " value-capable settings instead of exactly one: " .. resultText(optimize))
    assert(retainedKey ~= nil, "numeric optimization prompt lost its retained setting key")
else
    assert(status(optimize) == "info" or status(optimize) == "ambiguous",
        "broad optimization was neither read-only planning nor a retained numeric clarification: "
            .. tostring(status(optimize)) .. " text=" .. resultText(optimize))
end
counted()

-- An invalid explicit value may ask for a number only when it retains the
-- unique setting identity. A bare numeric follow-up must then apply to that
-- setting rather than becoming a search-result ordinal.
resetTask()
resetBox(targetWidth, 275)
local invalid = submit("set Target Width to Player Width")
assert(status(invalid) == "ambiguous", "invalid exact value did not ask for clarification: " .. resultText(invalid))
local flow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
    and A.Workflow.PendingFlow() or A.pendingFlow
assert(type(flow) == "table" and flow.kind == "settingValue",
    "invalid exact value did not retain a settingValue flow")
assert(flow.settingKey == "target.width",
    "invalid exact value retained the wrong control: " .. tostring(flow.settingKey))
assert(targetWidth.value == 275 and targetWidth.writes == 0 and #A.undoStack == 0,
    "invalid exact value wrote Target Width before clarification")
local followup = submit("300")
assert(status(followup) == "applied" or status(followup) == "unchanged", resultText(followup))
assert(targetWidth.value == 300 and targetWidth.writes == 1,
    "numeric follow-up did not apply to retained Target Width: " .. resultText(followup))
local remainingFlow = type(A.Workflow) == "table" and type(A.Workflow.PendingFlow) == "function"
    and A.Workflow.PendingFlow() or A.pendingFlow
assert(remainingFlow == nil, "settingValue flow survived its successful numeric follow-up")
counted()

for i = #patched, 1, -1 do
    local record = patched[i]
    record.setting.get = record.original.get
    record.setting.set = record.original.set
    record.setting.apply = record.original.apply
end

io.write("assistant_semantic_write_safety_regression: ok cases=" .. tostring(cases) .. "\n")
