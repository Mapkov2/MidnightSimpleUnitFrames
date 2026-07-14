_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local suppliedAddonRoot = select(1, ...)
local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local assistantRoot = RuntimeManifest.ResolveCompanionRoot(suppliedAddonRoot) .. "/Assistant/"

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { transaction = { actionValue = 1 } }
_G.MSUF_GlobalDB = { global = {} }
_G.GetTime = function() return os.clock() end
_G.GetServerTime = function() return 123456 end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.MSUF_ScheduleOnce = function(_, fn) if type(fn) == "function" then fn() end end
_G.C_Timer = { After = function(_, fn) if type(fn) == "function" then fn() end end }
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(kind, fn) if kind == "OnEvent" then self.onEvent = fn end end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end

local broadApplyCount = 0
local flushShouldFail = false
local M = MSUF.MSUF2
M.EnsureDB = function() return _G.MSUF_DB end
M.RequestGeneralApply = function()
    broadApplyCount = broadApplyCount + 1
    return true
end
M.ApplyService = {
    Flush = function()
        if flushShouldFail then error("flush failure") end
    end,
}

local function loadAssistant(name)
    local chunk, err = loadfile(assistantRoot .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadAssistant("MSUF_AssistantHistory.lua")
loadAssistant("MSUF_AssistantUndo.lua")
loadAssistant("MSUF_AssistantRegistry_ActionInputs.lua")
loadAssistant("MSUF_Assistant.lua")

local A = assert(MSUF.Assistant, "Assistant missing")
assert(type(A.ExecutePlan) == "function", "ExecutePlan missing")
assert(type(A.RestoreSnapshot) == "function", "RestoreSnapshot missing")

local values = { first = 1, second = 2, normalized = 4 }
local settings = {}
local applyFailure = false
local secondSetFailure = false
local verificationMismatch = false
local settingSetCalls = {}

local function makeSetting(key)
    local setting = {
        key = "transaction." .. key,
        label = "Transaction " .. key,
        category = "Transaction",
        type = "number",
        min = 0,
        max = 100,
        step = 1,
    }
    setting.get = function() return values[key] end
    setting.set = function(value)
        settingSetCalls[key] = (settingSetCalls[key] or 0) + 1
        if key == "second" and secondSetFailure and value ~= 2 then error("second setter failure") end
        if key == "first" and verificationMismatch and value ~= 1 then
            values[key] = value + 1
            verificationMismatch = false
            return
        end
        values[key] = value
    end
    setting.apply = function()
        if applyFailure then error("apply failure") end
    end
    settings[setting.key] = setting
    return setting
end

local first = makeSetting("first")
local second = makeSetting("second")
local normalized = makeSetting("normalized")
normalized.normalizesValue = true
normalized.set = function(value)
    if value == 4 then values.normalized = 4 else values.normalized = math.floor(value / 2) * 2 end
end

A.Registry = {
    GetSetting = function(_, key) return settings[key] end,
    RegisterSetting = function(_, spec)
        settings[spec.key] = settings[spec.key] or spec
        return settings[spec.key]
    end,
}

local function resetRuntime()
    values.first = 1
    values.second = 2
    values.normalized = 4
    secondSetFailure = false
    applyFailure = false
    verificationMismatch = false
    flushShouldFail = false
    A.undoStack = {}
    A.redoStack = {}
    A.lastAssistantTransactionError = nil
    for key in pairs(settingSetCalls) do settingSetCalls[key] = nil end
    if type(A.GetContext) == "function" then
        local ctx = A.GetContext()
        for key in pairs(ctx) do ctx[key] = nil end
    end
end

local function changePlan(entries)
    return { kind = "changes", label = "Transaction smoke", summary = "Transaction smoke", changes = entries }
end

local function status(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

-- A later setter failure must restore an earlier successful write and must not create undo state.
resetRuntime()
secondSetFailure = true
local result = A.ExecutePlan(changePlan({
    { setting = first, value = 10 },
    { setting = second, value = 20 },
}))
assert(status(result) == "failed", "setter failure was not reported")
assert(values.first == 1 and values.second == 2, "setter failure left a partial state")
assert(#A.undoStack == 0, "failed transaction created undo state")

-- A setter that stores an unexpected value must fail verification and rollback.
resetRuntime()
verificationMismatch = true
result = A.ExecutePlan(changePlan({ { setting = first, value = 10 } }))
assert(status(result) == "failed", "verification mismatch was not reported")
assert(values.first == 1, "verification mismatch was not rolled back")
assert(#A.undoStack == 0, "verification mismatch created undo state")

-- Apply and Flush failures happen after writes and therefore exercise post-write rollback.
resetRuntime()
applyFailure = true
result = A.ExecutePlan(changePlan({
    { setting = first, value = 10 },
    { setting = second, value = 20 },
}))
assert(status(result) == "failed", "apply failure was not reported")
assert(values.first == 1 and values.second == 2, "apply failure left a partial state")
assert(#A.undoStack == 0, "apply failure created undo state")

resetRuntime()
flushShouldFail = true
result = A.ExecutePlan(changePlan({ { setting = first, value = 10 } }))
assert(status(result) == "failed", "flush failure was not reported")
assert(values.first == 1, "flush failure was not rolled back")
assert(#A.undoStack == 0, "flush failure created undo state")

-- A committed transaction is verifiable and produces one undo bundle only after Apply succeeds.
resetRuntime()
result = A.ExecutePlan(changePlan({
    { setting = first, value = 10 },
    { setting = second, value = 20 },
}))
assert(status(result) == "applied", "successful transaction did not commit")
assert(values.first == 10 and values.second == 20, "successful transaction stored wrong values")
assert(#A.undoStack == 1, "successful transaction did not create exactly one undo bundle")
applyFailure = true
local undoOk = A.UndoLast()
assert(undoOk == false, "failing undo was reported as successful")
assert(values.first == 10 and values.second == 20, "failing undo left a partial state")
assert(#A.undoStack == 1 and #A.redoStack == 0, "failing undo lost or moved its bundle")
applyFailure = false
undoOk = A.UndoLast()
assert(undoOk == true, "transaction undo failed")
assert(values.first == 1 and values.second == 2, "transaction undo restored wrong values")

-- No-op is successful but never counted as a mutation and never creates undo state.
resetRuntime()
result = A.ExecutePlan(changePlan({ { setting = first, value = 1 } }))
assert(status(result) == "unchanged", "no-op did not use unchanged status")
assert(#A.undoStack == 0, "no-op created undo state")

-- Explicitly declared normalization is accepted, stored and undoable.
resetRuntime()
result = A.ExecutePlan(changePlan({ { setting = normalized, value = 9 } }))
assert(status(result) == "applied", "normalized setting did not commit")
assert(values.normalized == 8, "normalized setting stored wrong normalized value")
assert(#A.undoStack == 1, "normalized setting did not create undo state")
undoOk = A.UndoLast()
assert(undoOk == true and values.normalized == 4, "normalized setting undo failed")

resetRuntime()
values.normalized = 8
result = A.ExecutePlan(changePlan({ { setting = normalized, value = 9 } }))
assert(status(result) == "unchanged", "normalized no-op was not treated as unchanged")
assert(values.normalized == 8 and #A.undoStack == 0, "normalized no-op created state or undo changes")

-- The central transaction boundary accepts only native typed values. Parser
-- coercion must be complete before ExecutePlan, and all values must validate
-- before the first setter in a compound plan runs.
assert(type(A.NormalizeRegistrySettingValue) == "function", "typed registry value normalizer missing")
local ok, normalizedValue = A.NormalizeRegistrySettingValue({ type = "boolean" }, false)
assert(ok == true and normalizedValue == false, "false boolean was not preserved exactly")
ok = A.NormalizeRegistrySettingValue({ type = "boolean" }, 0)
assert(ok == false, "numeric boolean coercion was accepted")

local typedValues = {
    boolean = true,
    number = 5,
    enum = "alpha",
    closed = "one",
    free = "before",
    color = { r = 0.1, g = 0.2, b = 0.3 },
}
local domainRefreshes = { enum = 0, closed = 0 }

local function typedSetting(key, settingType, extra)
    local setting = {
        key = "transaction.typed." .. key,
        label = "Typed " .. key,
        category = "Transaction",
        type = settingType,
    }
    for field, value in pairs(extra or {}) do setting[field] = value end
    setting.get = function() return typedValues[key] end
    setting.set = function(value)
        settingSetCalls["typed." .. key] = (settingSetCalls["typed." .. key] or 0) + 1
        typedValues[key] = value
    end
    settings[setting.key] = setting
    return setting
end

local typedNumber = typedSetting("number", "number", { min = 0, max = 20, step = 5 })
local typedBoolean = typedSetting("boolean", "boolean")
local typedEnum = typedSetting("enum", "enum", {
    values = { "stale" },
    refreshValues = function()
        domainRefreshes.enum = domainRefreshes.enum + 1
        return { "alpha", "beta" }, { alpha = "Alpha", beta = "Beta" }
    end,
})
local typedClosed = typedSetting("closed", "string", {
    closedValues = true,
    values = { "stale" },
    refreshValues = function()
        domainRefreshes.closed = domainRefreshes.closed + 1
        return { "one", "two" }
    end,
})
local typedFree = typedSetting("free", "string")
local typedColor = typedSetting("color", "color", {
    sameValue = function(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end,
})

resetRuntime()
result = A.ExecutePlan(changePlan({
    { setting = first, value = 10 },
    { setting = typedColor, value = { r = -5 / 255, g = 300 / 255, b = 0 } },
}))
assert(status(result) == "failed", "out-of-range color was accepted")
assert(values.first == 1 and typedValues.color.r == 0.1, "invalid second change left partial state")
assert((settingSetCalls.first or 0) == 0 and (settingSetCalls["typed.color"] or 0) == 0,
    "a setter ran before compound typed preflight completed")
assert(A.lastAssistantTransactionError and A.lastAssistantTransactionError.phase == "preflight.value",
    "invalid compound value did not fail in typed preflight")

local invalidCases = {
    { setting = typedBoolean, value = "false", name = "coerced boolean" },
    { setting = typedNumber, value = math.huge, name = "infinite number" },
    { setting = typedNumber, value = 0 / 0, name = "NaN number" },
    { setting = typedEnum, value = "gamma", name = "unknown enum" },
    { setting = typedClosed, value = "three", name = "unknown closed string" },
    { setting = typedFree, value = 42, name = "non-string free value" },
    { setting = typedColor, value = { r = 0, g = 0 / 0, b = 1 }, name = "non-finite color" },
    { setting = typedColor, value = { r = 0, g = 0, b = 1, a = 2 }, name = "out-of-range alpha" },
}
for i = 1, #invalidCases do
    resetRuntime()
    local case = invalidCases[i]
    result = A.ExecutePlan(changePlan({ { setting = case.setting, value = case.value } }))
    assert(status(result) == "failed", case.name .. " was accepted")
    assert(next(settingSetCalls) == nil, case.name .. " reached a setter")
end
assert(domainRefreshes.enum > 0 and domainRefreshes.closed > 0,
    "closed setting domains were not refreshed before validation")

resetRuntime()
typedValues.boolean = true
result = A.ExecutePlan(changePlan({ { setting = typedBoolean, value = false } }))
assert(status(result) == "applied" and typedValues.boolean == false, "native false boolean did not apply")

resetRuntime()
typedValues.number = 5
result = A.ExecutePlan(changePlan({ { setting = typedNumber, value = 12 } }))
assert(status(result) == "applied" and typedValues.number == 10,
    "bounded step normalization did not produce the deterministic value")

resetRuntime()
typedValues.enum = "alpha"
result = A.ExecutePlan(changePlan({ { setting = typedEnum, value = "beta" } }))
assert(status(result) == "applied" and typedValues.enum == "beta", "refreshed enum value did not apply")

resetRuntime()
typedValues.closed = "one"
result = A.ExecutePlan(changePlan({ { setting = typedClosed, value = "two" } }))
assert(status(result) == "applied" and typedValues.closed == "two", "refreshed closed string did not apply")

resetRuntime()
typedValues.free = "before"
result = A.ExecutePlan(changePlan({ { setting = typedFree, value = "  exact free text  " } }))
assert(status(result) == "applied" and typedValues.free == "  exact free text  ", "free string was not preserved exactly")

resetRuntime()
typedValues.color = { r = 0.1, g = 0.2, b = 0.3 }
result = A.ExecutePlan(changePlan({ { setting = typedColor, value = { r = 0.8, g = 0.7, b = 0.6, a = 1 } } }))
assert(status(result) == "applied" and typedValues.color.r == 0.8 and typedValues.color.a == 1,
    "valid finite RGBA value did not apply")

-- Multiple operations on one setting collapse to one original-to-final undo delta.
resetRuntime()
result = A.ExecutePlan(changePlan({
    { setting = first, value = 10 },
    { setting = first, value = 20 },
}))
assert(status(result) == "applied" and values.first == 20, "duplicate-setting transaction did not reach final value")
assert(#A.undoStack == 1 and #A.undoStack[1].changes == 1, "duplicate-setting transaction did not collapse its undo delta")
undoOk = A.UndoLast()
assert(undoOk == true and values.first == 1, "duplicate-setting undo did not restore original value")
local redoOk = A.RedoLast()
assert(redoOk == true and values.first == 20, "duplicate-setting redo did not restore final value")

-- Snapshot-declared actions rollback DB mutations when their runner throws.
resetRuntime()
_G.MSUF_DB.transaction.actionValue = 1
assert(A.ActionInputs and A.ActionInputs.Contracts, "action input contracts did not load")
A.ActionInputs.Contracts["transaction.action"] = {
    kind = "none", fields = {}, source = A.ActionInputs.Source,
}
local action = {
    key = "transaction.action",
    label = "Transaction action",
    mutability = "savedState",
    -- Execution must resolve the authoritative contract by key. A copied or
    -- forged action table is not allowed to supply its own input schema.
    assistantInputExplicit = false,
    assistantInput = { kind = "object", fields = { forged = { type = "boolean" } } },
    captureSnapshot = true,
    run = function()
        _G.MSUF_DB.transaction.actionValue = 99
        error("action failure")
    end,
}
local rejectedRunCount = 0
local transactionRun = action.run
action.run = function()
    rejectedRunCount = rejectedRunCount + 1
    return true
end
result = A.ExecutePlan({
    kind = "action", action = action, args = { forged = true }, summary = "Forged action input contract",
})
assert(status(result) == "failed" and rejectedRunCount == 0,
    "ExecuteAction trusted forged action-table input metadata")
action.run = transactionRun

result = A.ExecutePlan({ kind = "action", action = action, summary = "Transaction action" })
assert(status(result) == "failed", "throwing action was not reported")
assert(_G.MSUF_DB.transaction.actionValue == 1, "throwing action did not restore its snapshot")
assert(#A.undoStack == 0, "throwing action created undo state")
assert(broadApplyCount > 0, "action rollback did not request a runtime refresh")

_G.MSUF_DB.transaction.actionValue = 1
action.run = function()
    _G.MSUF_DB.transaction.actionValue = 77
    return false, "action rejected after a partial write"
end
result = A.ExecutePlan({ kind = "action", action = action, summary = "Transaction action" })
assert(status(result) == "failed", "false-returning action was not reported")
assert(_G.MSUF_DB.transaction.actionValue == 1, "false-returning action did not restore its snapshot")
assert(#A.undoStack == 0, "false-returning action created undo state")

-- A guard that explicitly proves it made no mutation keeps its actionable
-- failure text and does not perform a misleading or unnecessary rollback.
local broadApplyBeforeGuard = broadApplyCount
action.run = function()
    return false, "Open the owning page first so I can run that task.", {
        noMutation = true,
        userFacingFailure = true,
    }
end
result = A.ExecutePlan({ kind = "action", action = action, summary = "Transaction action" })
assert(status(result) == "failed", "no-mutation guard was not reported")
assert(result.text == "Open the owning page first so I can run that task.", "no-mutation guard lost its guidance")
assert(_G.MSUF_DB.transaction.actionValue == 1, "no-mutation guard changed owner state")
assert(#A.undoStack == 0, "no-mutation guard created undo state")
assert(broadApplyCount == broadApplyBeforeGuard, "no-mutation guard performed an unnecessary rollback refresh")

-- Reviewed Menu2 dynamic/compound scalar controls are promoted through a
-- lazily registered transaction setting. They must never fall through to the
-- raw catalog Execute callback, and their full profile state must undo/redo.
resetRuntime()
_G.MSUF_DB.transaction.dynamicValue = 2
_G.MSUF_DB.transaction.compoundValue = 3
_G.MSUF_DB.transaction.compoundMirror = 77
local schemaColumns = {
    "semanticId", "controlId", "familyId", "memberKey", "pageKey", "controlPath",
    "classification", "kind", "settingKey", "actionKey", "navigationKey", "safety",
    "valueKind", "min", "max", "step", "percentIsValue", "confirmRequired",
    "identityStable", "label", "help", "values", "actionFixedArgs", "actionInputArg",
    "actionInputKind", "actionInputDomain", "storageUnit", "displayUnit", "displayScale",
    "states", "contexts",
}
local function SchemaRow(semanticId, controlId, label)
    return {
        semanticId, controlId, "", "", "test", "test/" .. controlId,
        "setting", "slider", "", "", "", "direct", "number", "0", "10", "1",
        "0", "0", "1", label, "Transaction-backed catalog setting.", "",
        "", "", "", "", "", "", "", "base", "*",
    }
end
A.ControlSchemaData = {
    version = 3, columns = schemaColumns, contexts = {},
    records = {
        SchemaRow("control:test.dynamic", "test.dynamic", "Dynamic value"),
        SchemaRow("control:test.compound", "test.compound", "Compound value"),
    },
    packs = { enUS = { guided = "Open {label}.", readOnly = "{label} is read-only." } },
}
local rawCatalogExecutions = 0
local catalogRecords = {
    ["control:test.dynamic"] = {
        controlId = "test.dynamic", assistantDisposition = "dynamic",
        command = {
            get = function() return _G.MSUF_DB.transaction.dynamicValue end,
            set = function(value) _G.MSUF_DB.transaction.dynamicValue = value; return true end,
        },
    },
    ["control:test.compound"] = {
        controlId = "test.compound", assistantDisposition = "compound",
        command = {
            get = function() return _G.MSUF_DB.transaction.compoundValue end,
            set = function(value)
                _G.MSUF_DB.transaction.compoundValue = value
                _G.MSUF_DB.transaction.compoundMirror = value * 2
                return true
            end,
        },
    },
}
M.RuntimeControlCatalog = {
    Resolve = function(semanticId) return catalogRecords[semanticId] end,
    Read = function(controlId)
        for _, record in pairs(catalogRecords) do
            if record.controlId == controlId then return true, record.command.get() end
        end
        return nil, "missing"
    end,
    Execute = function() rawCatalogExecutions = rawCatalogExecutions + 1; return true end,
}
loadAssistant("MSUF_AssistantControlSchema.lua")
local Schema = assert(A.ControlSchema, "ControlSchema did not load for catalog transaction test")

local schemaOk, schemaResult = Schema.Execute("control:test.dynamic", 7)
assert(schemaOk == true and status(schemaResult) == "applied"
    and _G.MSUF_DB.transaction.dynamicValue == 7 and rawCatalogExecutions == 0,
    "reviewed dynamic catalog setting bypassed the transaction plan")
assert(A.UndoLast() == true and _G.MSUF_DB.transaction.dynamicValue == 2,
    "dynamic catalog setting undo failed")
assert(A.RedoLast() == true and _G.MSUF_DB.transaction.dynamicValue == 7,
    "dynamic catalog setting redo failed")

resetRuntime()
_G.MSUF_DB.transaction.compoundValue = 3
_G.MSUF_DB.transaction.compoundMirror = 77
schemaOk, schemaResult = Schema.Execute("control:test.compound", 6)
assert(schemaOk == true and status(schemaResult) == "applied"
    and _G.MSUF_DB.transaction.compoundValue == 6 and _G.MSUF_DB.transaction.compoundMirror == 12,
    "compound catalog setting did not apply atomically")
assert(A.UndoLast() == true and _G.MSUF_DB.transaction.compoundValue == 3
    and _G.MSUF_DB.transaction.compoundMirror == 77,
    "compound catalog setting undo lost its non-projected mirror state")
assert(A.RedoLast() == true and _G.MSUF_DB.transaction.compoundValue == 6
    and _G.MSUF_DB.transaction.compoundMirror == 12,
    "compound catalog setting redo lost its transaction state")
local compoundBefore = _G.MSUF_DB.transaction.compoundValue
schemaOk, schemaResult = Schema.Execute("control:test.compound", "6")
assert(schemaOk == false and schemaResult == "invalid_value"
    and _G.MSUF_DB.transaction.compoundValue == compoundBefore,
    "malformed catalog setting value reached its command")

print("assistant_transaction_smoke: ok")
