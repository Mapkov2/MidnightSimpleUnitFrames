-- Proves that generated-schema persisted writes cross the Assistant Registry
-- transaction boundary exactly once and never fall through to Menu2 callbacks.

_G = _G or _ENV

local function Check(value, message)
    if not value then error("ASSISTANT CONTROL SCHEMA TRANSACTION FAIL: " .. tostring(message), 2) end
end

local columns = {
    "semanticId", "controlId", "familyId", "memberKey", "pageKey", "controlPath",
    "classification", "kind", "settingKey", "actionKey", "navigationKey", "safety",
    "valueKind", "min", "max", "step", "percentIsValue", "confirmRequired",
    "identityStable", "label", "help", "values", "actionFixedArgs", "actionInputArg",
    "actionInputKind", "actionInputDomain", "storageUnit", "displayUnit", "displayScale",
    "states", "contexts",
}

local function Row(values)
    local out = {}
    for i = 1, #columns do out[i] = values[columns[i]] or "" end
    return out
end

local settingWrites, actionRuns, planCalls, catalogCalls = 0, 0, 0, 0
local lastPlacement, lastActionArgs
local settings = {
    ["contract.enabled"] = {
        key = "contract.enabled", type = "boolean", label = "Contract enabled",
        get = function() return false end,
        set = function(value) settingWrites = settingWrites + 1; return value end,
    },
    ["contract.danger"] = {
        key = "contract.danger", type = "boolean", label = "Contract danger", confirmRequired = true,
        get = function() return false end,
        set = function(value) settingWrites = settingWrites + 1; return value end,
    },
    ["contract.placement"] = {
        key = "contract.placement", type = "enum", label = "Contract placement",
        values = { "TOP", "BOTTOM" }, valueLabels = { TOP = "Above", BOTTOM = "Below" },
        get = function() return lastPlacement or "TOP" end,
        set = function(value) settingWrites = settingWrites + 1; lastPlacement = value; return value end,
    },
    ["contract.opacity"] = {
        key = "contract.opacity", type = "number", label = "Contract opacity",
        min = 0, max = 1, step = 0.01, percent = true,
        get = function() return 0.5 end,
        set = function(value) settingWrites = settingWrites + 1; return value end,
    },
}
local actions = {
    ["contract.run"] = {
        key = "contract.run", label = "Run contract", aliasNoArgs = true,
        assistantInputExplicit = true, assistantInput = { kind = "none" },
        run = function(args) actionRuns = actionRuns + 1; lastActionArgs = args; return true end,
    },
    ["contract.preset"] = {
        key = "contract.preset", label = "Apply contract preset",
        assistantInputExplicit = true, assistantInput = { kind = "object" },
        run = function(args) actionRuns = actionRuns + 1; lastActionArgs = args; return true end,
    },
    ["contract.profile"] = {
        key = "contract.profile", label = "Select contract profile",
        assistantInputExplicit = true, assistantInput = { kind = "object" },
        run = function(args) actionRuns = actionRuns + 1; lastActionArgs = args; return true end,
    },
    ["contract.read"] = {
        key = "contract.read", label = "Show contract information", mutability = "readOnly",
        assistantInputExplicit = true, assistantInput = { kind = "none" },
        run = function(args) actionRuns = actionRuns + 1; lastActionArgs = args; return true end,
    },
}

local namespace = {
    MSUF2 = {},
    Assistant = {
        ControlSchemaData = {
            version = 2,
            columns = columns,
            contexts = {},
            records = {
                Row({ semanticId="setting:contract.enabled", controlId="control.enabled", pageKey="contract",
                    classification="setting", kind="toggle", settingKey="contract.enabled", safety="direct",
                    valueKind="boolean", identityStable="1", label="Contract enabled", contexts="*" }),
                Row({ semanticId="setting:contract.danger", controlId="control.danger", pageKey="contract",
                    classification="setting", kind="toggle", settingKey="contract.danger", safety="confirm",
                    valueKind="boolean", confirmRequired="1", identityStable="1", label="Contract danger", contexts="*" }),
                Row({ semanticId="setting:contract.placement", controlId="control.placement", pageKey="contract",
                    classification="setting", kind="dropdown", settingKey="contract.placement", safety="direct",
                    valueKind="enum", identityStable="1", label="Contract placement",
                    values="s:TOP\030Above\031s:BOTTOM\030Below", contexts="*" }),
                Row({ semanticId="setting:contract.opacity", controlId="control.opacity", pageKey="contract",
                    classification="setting", kind="slider", settingKey="contract.opacity", safety="direct",
                    valueKind="number", min="0", max="1", step="0.01", identityStable="1",
                    label="Contract opacity", contexts="*" }),
                Row({ semanticId="control:contract.unlinked", controlId="control.unlinked", pageKey="contract",
                    classification="setting", kind="toggle", safety="direct", valueKind="boolean",
                    identityStable="1", label="Unlinked persisted", contexts="*" }),
                Row({ semanticId="control:contract.dynamic", controlId="control.dynamic", pageKey="contract",
                    classification="setting", kind="slider", safety="direct", valueKind="number",
                    min="0", max="10", step="1", identityStable="1", label="Reviewed dynamic", contexts="*" }),
                Row({ semanticId="action:contract.run", controlId="control.run", pageKey="contract",
                    classification="action", kind="button", actionKey="contract.run", safety="direct",
                    valueKind="action", identityStable="1", label="Run contract", contexts="*" }),
                Row({ semanticId="action:contract.preset", controlId="control.preset", pageKey="contract",
                    classification="action", kind="button", actionKey="contract.preset", safety="direct",
                    valueKind="action", identityStable="1", label="Apply 1080p",
                    actionFixedArgs="t1:18:s6:preset=s5:1080p", contexts="*" }),
                Row({ semanticId="action:contract.profile", controlId="control.profile", pageKey="contract",
                    classification="action", kind="button", actionKey="contract.profile", safety="direct",
                    valueKind="action", identityStable="1", label="Select profile",
                    actionInputArg="name", actionInputKind="string", contexts="*" }),
                Row({ semanticId="action:contract.current", controlId="control.current", pageKey="contract",
                    classification="action", kind="button", actionKey="contract.profile", safety="direct",
                    valueKind="action", identityStable="1", label="Select current profile",
                    actionFixedArgs="t1:42:s4:name=t1:28:s7:context=s13:activeProfile", contexts="*" }),
                Row({ semanticId="action:contract.read", controlId="control.read", pageKey="contract",
                    classification="action", kind="button", actionKey="contract.read", safety="readOnly",
                    valueKind="action", identityStable="1", label="Show information", contexts="*" }),
                Row({ semanticId="control:contract.preview", controlId="control.preview", pageKey="contract",
                    classification="ephemeral", kind="toggle", safety="nonStateful", valueKind="boolean",
                    identityStable="1", label="Contract preview", contexts="*" }),
            },
            packs = { enUS = { guided="Open {label} to finish this change.", readOnly="{label} is read-only." } },
        },
        Registry = {
            GetSetting = function(_, key) return settings[key] end,
            RegisterSetting = function(_, spec) settings[spec.key] = settings[spec.key] or spec; return settings[spec.key] end,
            GetAction = function(_, key) return actions[key] end,
        },
        CaptureSnapshot = function() return { dynamicValue = _G.MSUF_NS and _G.MSUF_NS._dynamicValue or 2 } end,
        RestoreSnapshot = function(state) _G.MSUF_NS._dynamicValue = state.dynamicValue; return true end,
        NormalizeAssistantActionInput = function(action, args)
            if type(args) ~= "table" or getmetatable(args) ~= nil then return nil, "expected_object" end
            if action.key == "contract.run" or action.key == "contract.read" then
                if next(args) ~= nil then return nil, "unexpected_field" end
                return {}
            end
            if action.key == "contract.preset" then
                if args.preset ~= "1080p" and args.preset ~= "4k" then return nil, "expected_preset" end
                for key in pairs(args) do if key ~= "preset" then return nil, "unexpected_field" end end
                return { preset = args.preset }
            end
            if action.key == "contract.profile" then
                if type(args.name) ~= "string" or args.name == "" then return nil, "expected_name" end
                for key in pairs(args) do if key ~= "name" then return nil, "unexpected_field" end end
                return { name = args.name }
            end
            return nil, "unknown_action"
        end,
        Parser = {
            RefreshRegistrySettingValues = function() return false end,
            ValueForRegistrySetting = function(setting, text)
                if setting.key == "contract.placement" and tostring(text):find("below", 1, true) then return "BOTTOM" end
                return nil
            end,
            MissingValueResponse = function(matches)
                return { status = "ambiguous", text = "Choose a valid value.", pendingSetting = matches[1].setting.key }
            end,
        },
    },
}
namespace.MSUF2.RuntimeControlCatalog = {
    Resolve = function(semanticId)
        if semanticId == "control:contract.preview" then return { controlId = "control.preview" } end
        if semanticId == "control:contract.dynamic" then
            return {
                controlId = "control.dynamic", assistantDisposition = "dynamic",
                command = {
                    get = function() return namespace._dynamicValue or 2 end,
                    set = function(value) namespace._dynamicValue = value; return true end,
                },
            }
        end
        return { controlId = "unexpected." .. tostring(semanticId) }
    end,
    Read = function(controlId)
        if controlId == "control.dynamic" then return true, namespace._dynamicValue or 2 end
        return nil, "read_unavailable"
    end,
    Execute = function(controlId, value)
        catalogCalls = catalogCalls + 1
        Check(controlId == "control.preview" and type(value) == "boolean",
            "unexpected raw catalog execution for " .. tostring(controlId))
        return true
    end,
}
namespace.Assistant.ExecutePlan = function(plan, opts)
    planCalls = planCalls + 1
    if plan.kind == "changes" then
        local change = assert(plan.changes and plan.changes[1], "missing setting change")
        if change.setting.confirmRequired and not (opts and opts.confirmed) then
            return { status = "confirm", text = "Confirmation required." }
        end
        change.setting.set(change.value)
        return { status = "applied", text = "Applied." }
    end
    if plan.kind == "action" then
        plan.action.run(plan.args)
        return { status = "applied", text = "Ran." }
    end
    error("unexpected plan kind " .. tostring(plan.kind))
end

_G.MSUF_NS = namespace
local chunk, loadError = loadfile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema.lua")
Check(chunk, loadError)
chunk("MidnightSimpleUnitFrames_Assistant", namespace)
local Schema = assert(namespace.Assistant.ControlSchema, "schema did not load")

local function CanonicalTable(rows)
    local encoded = { "t" .. tostring(#rows) .. ":" }
    for i = 1, #rows do
        encoded[#encoded + 1] = tostring(#rows[i]) .. ":" .. rows[i]
    end
    return table.concat(encoded)
end

local nestedCanonical = CanonicalTable({ "s7:enabled=b1", "s5:count=n2" })
local canonicalFixture = CanonicalTable({
    "s6:preset=s5:1080p",
    "n2=s3:two",
    "s6:nested=" .. nestedCanonical,
    "s3:a=b=s3:x=y",
})
local decodedFixture, decodeError = Schema.DecodeCanonicalData(canonicalFixture)
Check(type(decodedFixture) == "table" and decodeError == nil
    and decodedFixture.preset == "1080p" and decodedFixture[2] == "two"
    and decodedFixture.nested.enabled == true and decodedFixture.nested.count == 2
    and decodedFixture["a=b"] == "x=y",
    "canonical fixed-action data did not round-trip nested/typed values")
local malformedValue, malformedError = Schema.DecodeCanonicalData("s9:short")
Check(malformedValue == nil and malformedError == "truncated_string",
    "truncated canonical data was not rejected deterministically")
local duplicateRow = "s3:key=s3:one"
local duplicateCanonical = CanonicalTable({ duplicateRow, duplicateRow })
malformedValue, malformedError = Schema.DecodeCanonicalData(duplicateCanonical)
Check(malformedValue == nil and malformedError == "duplicate_table_key",
    "duplicate canonical table keys were not rejected")

local ok, result = Schema.Execute("setting:contract.enabled", true)
Check(ok == true and result.status == "applied" and planCalls == 1 and settingWrites == 1 and catalogCalls == 0,
    "Registry setting did not execute as one Assistant plan")

ok, result = Schema.Execute("control:contract.unlinked", true)
Check(ok == false and result == "unreviewed_catalog_setting" and planCalls == 1
    and settingWrites == 1 and catalogCalls == 0,
    "unreviewed persisted control crossed the transaction boundary")

ok, result = Schema.Execute("setting:contract.danger", true)
Check(ok == true and result.status == "confirm" and planCalls == 2 and settingWrites == 1 and catalogCalls == 0,
    "unconfirmed setting wrote before confirmation")
ok, result = Schema.Execute("setting:contract.danger", true, { confirmed = true })
Check(ok == true and result.status == "applied" and planCalls == 3 and settingWrites == 2 and catalogCalls == 0,
    "confirmed setting did not use the transaction boundary")

ok, result = Schema.Execute("action:contract.run", nil)
Check(ok == true and result.status == "applied" and planCalls == 4 and actionRuns == 1 and catalogCalls == 0,
    "Registry action did not execute as one Assistant plan")
ok, result = Schema.Execute("action:contract.run", nil, { args = { preset = "redirect" } })
Check(ok == false and result == "immutable_action_args" and planCalls == 4 and actionRuns == 1 and catalogCalls == 0,
    "argument-free semantic action accepted redirecting caller arguments")
ok, result = Schema.Execute("action:contract.preset", nil, { args = { preset = "4k" } })
Check(ok == false and result == "immutable_action_args" and planCalls == 4 and actionRuns == 1 and catalogCalls == 0,
    "fixed semantic action accepted redirecting caller arguments")
ok, result = Schema.Execute("action:contract.preset", nil)
Check(ok == true and result.status == "applied" and planCalls == 5 and actionRuns == 2
    and lastActionArgs.preset == "1080p" and catalogCalls == 0,
    "immutable per-control preset did not execute its exact argument")
local actionPlansBefore, actionRunsBefore = planCalls, actionRuns
ok, result = Schema.Execute("action:contract.preset", "4k")
Check(ok == false and result == "unexpected_action_input" and planCalls == actionPlansBefore
    and actionRuns == actionRunsBefore,
    "fixed semantic action accepted an uncontracted direct value")
ok, result = Schema.Execute("action:contract.profile", "Raid Main")
Check(ok == true and result.status == "applied" and planCalls == actionPlansBefore + 1
    and actionRuns == actionRunsBefore + 1 and lastActionArgs.name == "Raid Main",
    "typed per-control action input did not execute through one plan")
actionPlansBefore, actionRunsBefore = planCalls, actionRuns
ok, result = Schema.Execute("action:contract.profile", nil)
Check(ok == false and result == "missing_action_input" and planCalls == actionPlansBefore
    and actionRuns == actionRunsBefore,
    "missing typed action input reached the plan")
ok, result = Schema.Execute("action:contract.profile", 42)
Check(ok == false and result == "invalid_action_input" and planCalls == actionPlansBefore
    and actionRuns == actionRunsBefore,
    "malformed typed action input reached the plan")
_G.MSUF_ActiveProfile = "Current Profile"
ok, result = Schema.Execute("action:contract.current", nil)
Check(ok == true and result.status == "applied" and planCalls == actionPlansBefore + 1
    and actionRuns == actionRunsBefore + 1 and lastActionArgs.name == "Current Profile",
    "active-profile context marker did not resolve deterministically")
_G.MSUF_ActiveProfile = nil
actionPlansBefore, actionRunsBefore = planCalls, actionRuns
ok, result = Schema.Execute("action:contract.current", nil)
Check(ok == false and result == "active_profile_unavailable" and planCalls == actionPlansBefore
    and actionRuns == actionRunsBefore,
    "missing action context reached the plan")
ok, result = Schema.Execute("action:contract.read", nil)
Check(ok == true and result.status == "applied" and planCalls == actionPlansBefore + 1
    and actionRuns == actionRunsBefore + 1,
    "explicit read-only informational action was blocked")

ok, result = Schema.Execute("control:contract.preview", true)
Check(ok == true and catalogCalls == 1 and planCalls == actionPlansBefore + 1,
    "ephemeral nonStateful control did not use its bounded catalog callback")

local opacityDescriptor = assert(Schema.GetBySemanticId("setting:contract.opacity"), "percent descriptor missing")
Check(opacityDescriptor.storageUnit == "fraction" and opacityDescriptor.displayUnit == "percent"
    and opacityDescriptor.displayScale == 100,
    "percent setting did not expose its direct API unit contract")
ok, result = Schema.Execute("setting:contract.opacity", 50, { inputUnit = "percent" })
Check(ok == true and result.status == "applied" and planCalls == actionPlansBefore + 2 and settingWrites == 3,
    "display percent was not explicitly converted before transaction execution")
ok, result = Schema.Execute("setting:contract.opacity", 0.5, { inputUnit = "native" })
Check(ok == true and result.status == "applied" and planCalls == actionPlansBefore + 3 and settingWrites == 4,
    "native fractional percent value did not execute")
local catalogPlansBefore, rawCallsBefore = planCalls, catalogCalls
ok, result = Schema.Execute("control:contract.dynamic", 7)
Check(ok == true and result.status == "applied" and planCalls == catalogPlansBefore + 1
    and namespace._dynamicValue == 7 and catalogCalls == rawCallsBefore,
    "reviewed dynamic catalog setting did not execute through one Assistant plan")
local plansBeforeBadUnit, writesBeforeBadUnit = planCalls, settingWrites
ok, result = Schema.Execute("setting:contract.opacity", 50, { inputUnit = "pixels" })
Check(ok == false and result == "invalid_input_unit" and planCalls == plansBeforeBadUnit
    and settingWrites == writesBeforeBadUnit,
    "unknown direct API unit reached the transaction plan")

local validValue, normalizedValue = Schema.NormalizeSettingValue({ type="boolean" }, "false")
Check(validValue == false and normalizedValue == "expected_boolean", "string boolean was truthily accepted")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="number", min=0, max=1, step=0.05 }, 0.38)
Check(validValue == true and math.abs(normalizedValue - 0.40) < 0.0001, "number was not deterministically stepped")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="number", min=0, max=1, step=0.05 }, 8)
Check(validValue == true and normalizedValue == 1, "number was not clamped to its Registry range")
validValue, normalizedValue = Schema.NormalizeSettingValue(settings["contract.placement"], "below")
Check(validValue == true and normalizedValue == "BOTTOM", "enum label did not canonicalize")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="string", values={"ONE", "TWO"}, closedValues=true }, "three")
Check(validValue == false and normalizedValue == "expected_choice", "closed string accepted an unknown choice")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="string" }, "Free text")
Check(validValue == true and normalizedValue == "Free text", "free string was not preserved")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="color" }, { r=0.2, g=0.4, b=0.6 })
Check(validValue == true and normalizedValue.r == 0.2 and normalizedValue.a == 1, "valid color did not normalize")
validValue, normalizedValue = Schema.NormalizeSettingValue({ type="color" }, { r=2, g=0.4, b=0.6 })
Check(validValue == false and normalizedValue == "expected_color", "out-of-range color was accepted")

local invalidPlans, invalidWrites = planCalls, settingWrites
ok, result = Schema.Execute("setting:contract.enabled", "false")
Check(ok == false and result == "invalid_value" and planCalls == invalidPlans and settingWrites == invalidWrites,
    "invalid direct value reached the transaction plan")

local conversation = Schema.TryConversation("change Contract placement to below")
Check(conversation and conversation.status == "applied" and lastPlacement == "BOTTOM"
    and planCalls == invalidPlans + 1 and catalogCalls == 1,
    "typed enum conversation did not use one Registry plan")
invalidPlans, invalidWrites = planCalls, settingWrites
conversation = Schema.TryConversation("change Contract placement to nowhere")
Check(conversation and conversation.status == "ambiguous" and planCalls == invalidPlans
    and settingWrites == invalidWrites and catalogCalls == 1,
    "invalid conversational enum did not fail without a write: status="
        .. tostring(conversation and conversation.status) .. " plans=" .. tostring(planCalls)
        .. " writes=" .. tostring(settingWrites) .. " raw=" .. tostring(catalogCalls))

local originalExecutePlan = namespace.Assistant.ExecutePlan
namespace.Assistant.ExecutePlan = function()
    return { status = "failed", text = "Deliberate transaction failure." }
end
invalidWrites = settingWrites
ok, result = Schema.Execute("setting:contract.enabled", true)
Check(ok == false and type(result) == "table" and result.status == "failed"
    and settingWrites == invalidWrites and catalogCalls == 1,
    "failed Assistant plan was reported as a successful schema execution")
namespace.Assistant.ExecutePlan = originalExecutePlan

namespace.Assistant.ExecutePlan = function(plan)
    if plan.kind == "action" then return { status = "navigated", text = "Opened." } end
    return { status = "failed" }
end
ok, result = Schema.Execute("action:contract.run", nil)
Check(ok == true and result.status == "navigated", "successful navigation action was reported as failed")
namespace.Assistant.ExecutePlan = function(plan)
    if plan.kind == "action" then return { status = "info", text = "Shown." } end
    return { status = "failed" }
end
ok, result = Schema.Execute("action:contract.run", nil)
Check(ok == true and result.status == "info", "successful informational action was reported as failed")
namespace.Assistant.ExecutePlan = function(plan)
    if plan.kind == "action" then return { status = "info", _readOnlyGuard = true, text = "Guarded." } end
    return { status = "failed" }
end
ok, result = Schema.Execute("action:contract.run", nil)
Check(ok == false and result._readOnlyGuard == true, "read-only guard was accepted as action execution")
namespace.Assistant.ExecutePlan = originalExecutePlan

print(string.format("assistant_control_schema_transaction_regression: ok plans=%d persistedWrites=%d rawEphemeral=%d",
    planCalls, settingWrites + actionRuns, catalogCalls))
