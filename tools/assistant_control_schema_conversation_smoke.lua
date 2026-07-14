-- Focused contract for the generated ControlSchema conversational fallback.
-- The inventory is synthetic so every value kind, safety policy, and near
-- match remains deterministic even when the generated workspace union changes.

_G = _G or _ENV

local function Check(value, message)
    if not value then error("ASSISTANT CONTROL SCHEMA CONVERSATION FAIL: " .. tostring(message), 2) end
end

do
    local handle = assert(io.open("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Registry.lua", "rb"))
    local source = handle:read("*a") or ""
    handle:close()
    Check(source:find("P.ValueForRegistrySetting = ValueForRegistrySetting", 1, true),
        "production Registry value parser is not exported")
end

local columns = {
    "semanticId", "controlId", "familyId", "memberKey", "pageKey", "controlPath",
    "classification", "kind", "settingKey", "actionKey", "navigationKey", "safety",
    "valueKind", "min", "max", "step", "percentIsValue", "confirmRequired",
    "identityStable", "label", "help", "values", "states", "contexts",
}

local function Row(values)
    local out = {}
    for i = 1, #columns do
        local value = values[columns[i]]
        out[i] = value == nil and "" or value
    end
    return out
end

local records = {}
local function Add(values)
    values.pageKey = values.pageKey or "conversation_lab"
    values.controlId = values.controlId or values.semanticId
    values.controlPath = values.controlPath or ("conversation/lab/" .. tostring(values.controlId))
    values.classification = values.classification or "setting"
    values.safety = values.safety or "direct"
    values.identityStable = "1"
    values.states = "*"
    values.contexts = "*"
    records[#records + 1] = Row(values)
end

Add({ semanticId="setting:lab.enabled", settingKey="lab.enabled", kind="toggle", valueKind="boolean",
    label="Alpha Sentinel Primary Toggle", help="The exact primary Alpha Sentinel switch." })
Add({ semanticId="setting:lab.enabled.decoy", settingKey="lab.enabled.decoy", kind="toggle", valueKind="boolean",
    label="Alpha Sentinel Secondary Toggle", help="A deliberately close control that must never be changed by a primary request." })
Add({ semanticId="setting:lab.width", settingKey="lab.width", kind="slider", valueKind="number",
    min="0", max="100", step="5", label="Gamma Width Slider", help="Allowed range 0 to 100 in steps of 5." })
Add({ semanticId="setting:lab.opacity", settingKey="lab.opacity", kind="slider", valueKind="number",
    min="0", max="1", step="0.05", percentIsValue="0", label="Delta Opacity Ratio",
    help="Opacity is stored as a zero-to-one ratio." })
Add({ semanticId="setting:lab.scale", settingKey="lab.scale", kind="slider", valueKind="number",
    min="30", max="150", step="5", percentIsValue="1", label="Epsilon Scale Percent",
    help="Scale is stored as a whole percentage." })
Add({ semanticId="setting:lab.layout", settingKey="lab.layout", kind="dropdown", valueKind="enum",
    label="Zeta Layout Mode", help="Choose Compact or Roomy.",
    values="s:COMPACT\030Compact\031s:SPACIOUS\030Roomy" })
Add({ semanticId="setting:lab.color", settingKey="lab.color", kind="color", valueKind="color",
    label="Eta Accent Color", help="Choose the exact accent RGB color." })
Add({ semanticId="setting:lab.text", settingKey="lab.text", kind="textinput", valueKind="string",
    label="Theta Label Text", help="Set an arbitrary label while preserving its spelling and spaces." })
Add({ semanticId="action:lab.batch", actionKey="lab.batch", classification="action", kind="button", valueKind="action",
    label="Iota Target Batch Action", help="Run the Target batch action with a numeric count." })
Add({ semanticId="action:lab.profile", actionKey="lab.profile", classification="action", kind="button", valueKind="text",
    label="Omicron Profile Action", help="Create a profile with the supplied text name." })
Add({ semanticId="setting:lab.danger", settingKey="lab.danger", kind="toggle", valueKind="boolean",
    safety="confirm", confirmRequired="1", label="Kappa Destructive Toggle",
    help="This setting requires confirmation." })
Add({ semanticId="setting:lab.guided", settingKey="lab.guided", kind="toggle", valueKind="boolean",
    safety="guided", label="Lambda Guided Toggle", help="This control must be changed in the menu." })
Add({ semanticId="setting:lab.readonly", settingKey="lab.readonly", kind="toggle", valueKind="boolean",
    safety="readOnly", label="Mu Read Only Toggle", help="This control is available for inspection only." })
Add({ semanticId="setting:lab.twin.one", settingKey="lab.twin.one", kind="toggle", valueKind="boolean",
    label="Nu Twin Beacon", help="First intentionally ambiguous Twin Beacon control." })
Add({ semanticId="setting:lab.twin.two", settingKey="lab.twin.two", kind="toggle", valueKind="boolean",
    label="Nu Twin Beacon", help="Second intentionally ambiguous Twin Beacon control." })
Add({ semanticId="control:lab.preview.scale", classification="ephemeral", kind="slider", valueKind="number",
    safety="nonStateful", min="30", max="150", step="5", percentIsValue="1",
    label="Rho Preview Scale Percent", help="A transient preview whose value is a whole percentage." })
Add({ semanticId="control:lab.preview.opacity", classification="ephemeral", kind="slider", valueKind="number",
    safety="nonStateful", min="0", max="1", step="0.05", percentIsValue="0",
    label="Sigma Preview Opacity Ratio", help="A transient preview whose percentage is stored as a ratio." })
Add({ semanticId="control:lab.drag", classification="setting", kind="drag", valueKind="position",
    safety="guided", label="Tau Drag Position", help="Structured drag positions are menu-guided." })
Add({ semanticId="control:lab.reorder", classification="setting", kind="dragrow", valueKind="reorder",
    safety="readOnly", label="Upsilon Reorder Row", help="Structured row ordering is inspection-only." })

local settingWrites, planCalls, actionRuns, catalogWrites = 0, 0, 0, 0
local writeCounts, lastPlan, lastCatalog, lastValueParserCall = {}, nil, nil, nil

local function Setting(key, settingType, options)
    options = options or {}
    local current = options.default
    local setting = {
        key = key,
        label = options.label or key,
        type = settingType,
        min = options.min,
        max = options.max,
        step = options.step,
        percent = options.percent,
        percentIsValue = options.percentIsValue,
        confirmRequired = options.confirmRequired,
        values = options.values,
        valueLabels = options.valueLabels,
        valueAliases = options.valueAliases,
        closedValues = options.closedValues,
    }
    setting.get = function() return current end
    setting.set = function(value)
        current = value
        settingWrites = settingWrites + 1
        writeCounts[key] = (writeCounts[key] or 0) + 1
        return true
    end
    return setting
end

local settings = {
    ["lab.enabled"] = Setting("lab.enabled", "boolean", { default=false }),
    ["lab.enabled.decoy"] = Setting("lab.enabled.decoy", "boolean", { default=false }),
    ["lab.width"] = Setting("lab.width", "number", { default=50, min=0, max=100, step=5 }),
    ["lab.opacity"] = Setting("lab.opacity", "number", { default=1, min=0, max=1, step=0.05, percent=true }),
    ["lab.scale"] = Setting("lab.scale", "number", { default=100, min=30, max=150, step=5, percentIsValue=true }),
    ["lab.layout"] = Setting("lab.layout", "enum", { default="COMPACT", values={"COMPACT", "SPACIOUS"},
        valueLabels={ COMPACT="Compact", SPACIOUS="Roomy" }, valueAliases={ roomy="SPACIOUS" } }),
    ["lab.color"] = Setting("lab.color", "color", { default={ r=1, g=1, b=1 } }),
    ["lab.text"] = Setting("lab.text", "string", { default="" }),
    ["lab.danger"] = Setting("lab.danger", "boolean", { default=false, confirmRequired=true }),
    ["lab.guided"] = Setting("lab.guided", "boolean", { default=false }),
    ["lab.readonly"] = Setting("lab.readonly", "boolean", { default=false }),
    ["lab.twin.one"] = Setting("lab.twin.one", "boolean", { default=false }),
    ["lab.twin.two"] = Setting("lab.twin.two", "boolean", { default=false }),
}

local function Normalize(value)
    value = tostring(value or ""):lower():gsub("[^%w]+", " "):gsub("%s+", " ")
    return (value:gsub("^ ", ""):gsub(" $", ""))
end

local function LastNumber(value)
    local found
    for numberText in tostring(value or ""):gmatch("[-+]?%d+%.?%d*") do found = tonumber(numberText) end
    return found
end

local Parser = {}
Parser.RefreshRegistrySettingValues = function() return false end
Parser.ValueForRegistrySetting = function(setting, text, raw)
    lastValueParserCall = { setting=setting, text=text, raw=raw }
    local normalized = " " .. Normalize(text) .. " "
    if setting.type == "boolean" then
        if normalized:find(" disable ", 1, true) or normalized:find(" off ", 1, true)
            or normalized:find(" hide ", 1, true) then return false end
        if normalized:find(" enable ", 1, true) or normalized:find(" on ", 1, true)
            or normalized:find(" show ", 1, true) then return true end
        return nil
    end
    if setting.type == "number" then
        local value = LastNumber(raw or text)
        if value and setting.percent == true and tostring(raw or text):find("%%") and value > 1 then value = value / 100 end
        return value
    end
    if setting.type == "enum" then
        local hay = Normalize(raw or text)
        for alias, value in pairs(setting.valueAliases or {}) do
            if hay:find(Normalize(alias), 1, true) then return value end
        end
        for i = 1, #(setting.values or {}) do
            local value = setting.values[i]
            local label = setting.valueLabels and setting.valueLabels[value]
            if hay:find(Normalize(value), 1, true) or (label and hay:find(Normalize(label), 1, true)) then return value end
        end
        return nil
    end
    if setting.type == "string" then
        local rawText = tostring(raw or "")
        local quoted = rawText:match('"([^"]*)"') or rawText:match("'([^']*)'")
        if quoted ~= nil then return quoted end
        return rawText:match("[Tt][Oo]%s+(.+)$") or rawText:match("=%s*(.+)$")
    end
    if setting.type == "color" then
        local hex = tostring(raw or ""):match("#(%x%x%x%x%x%x)")
        if not hex then return nil end
        return {
            r = tonumber(hex:sub(1, 2), 16) / 255,
            g = tonumber(hex:sub(3, 4), 16) / 255,
            b = tonumber(hex:sub(5, 6), 16) / 255,
            label = "#" .. hex:upper(),
        }
    end
    return nil
end
Parser.MissingValueResponse = function(matches)
    return {
        status = "ambiguous",
        text = "Choose a valid value for " .. tostring(matches[1].setting.label or matches[1].setting.key) .. ".",
        pendingSetting = matches[1].setting.key,
    }
end
Parser.EnumValueForText = function(setting, text) return Parser.ValueForRegistrySetting(setting, text, text) end
Parser.StringValueForText = function(setting, text, raw) return Parser.ValueForRegistrySetting(setting, text, raw) end
Parser.ExtractColor = function(raw, text)
    local value = Parser.ValueForRegistrySetting({ type="color", key="descriptor.color" }, text, raw)
    if value then return value.r, value.g, value.b, value.label end
end
Parser.DetectBoolean = function(text)
    return Parser.ValueForRegistrySetting({ type="boolean", key="descriptor.boolean" }, text, text)
end
Parser.FirstNumber = LastNumber

local actionArgumentCalls = 0
local actions = {}
actions["lab.batch"] = {
        key = "lab.batch", label = "Iota Target Batch Action",
        assistantInputExplicit = true, assistantInput = { kind = "object" },
        parseAliasArgs = function(normalized, raw, action)
            actionArgumentCalls = actionArgumentCalls + 1
            Check(action == actions["lab.batch"], "batch parseAliasArgs action argument")
            Check(normalized == Normalize(raw), "batch parseAliasArgs normalized/raw contract")
            local count = LastNumber(raw)
            if not count then return false end
            return { unit="target", count=count }, { summary="Run a deterministic Target batch." }
        end,
        run = function(args)
            actionRuns = actionRuns + 1
            Check(args.unit == "target" and args.count == 3, "batch action received wrong parsed args")
            return true
        end,
    }
actions["lab.profile"] = {
        key = "lab.profile", label = "Omicron Profile Action",
        assistantInputExplicit = true, assistantInput = { kind = "object" },
        parseAliasArgs = function(normalized, raw, action)
            actionArgumentCalls = actionArgumentCalls + 1
            Check(action == actions["lab.profile"] and normalized == Normalize(raw), "text action parseAliasArgs contract")
            local name = tostring(raw or ""):match('"([^"]+)"')
            if not name then return false end
            return { name=name }
        end,
        run = function(args)
            actionRuns = actionRuns + 1
            Check(args.name == "Raid Main", "text action lost case or spaces")
            return true
        end,
    }

local opened = {}
local namespace = {
    MSUF2 = {},
    Assistant = {
        ControlSchemaData = {
            version = 3,
            columns = columns,
            contexts = {},
            records = records,
            packs = { enUS = {
                guided = "Open {label} to finish this change.",
                readOnly = "{label} is read-only.",
            } },
        },
        Registry = {
            GetSetting = function(_, key) return settings[key] end,
            GetAction = function(_, key) return actions[key] end,
            AllActions = function() return {} end,
        },
        NormalizeAssistantActionInput = function(action, args)
            if type(args) ~= "table" or getmetatable(args) ~= nil then return nil, "expected_object" end
            if action.key == "lab.batch" then
                if args.unit ~= "target" or type(args.count) ~= "number" or args.count ~= math.floor(args.count)
                    or args.count < 1 or args.count > 100
                then return nil, "invalid_batch" end
                for key in pairs(args) do
                    if key ~= "unit" and key ~= "count" then return nil, "unexpected_field" end
                end
                return { unit = args.unit, count = args.count }
            end
            if action.key == "lab.profile" then
                if type(args.name) ~= "string" or args.name == "" then return nil, "invalid_name" end
                for key in pairs(args) do if key ~= "name" then return nil, "unexpected_field" end end
                return { name = args.name }
            end
            return nil, "unknown_action"
        end,
        Parser = Parser,
    },
}

namespace.MSUF2.OpenExactSettingControl = function(settingKey, label, pageKey)
    opened[#opened + 1] = { kind="setting", key=settingKey, label=label, pageKey=pageKey }
    return true, "Opened exact setting control."
end
namespace.MSUF2.OpenExactCatalogControl = function(semanticId, label, pageKey)
    opened[#opened + 1] = { kind="catalog", key=semanticId, label=label, pageKey=pageKey }
    return true, "Opened exact catalog control."
end
namespace.MSUF2.RuntimeControlCatalog = {
    Resolve = function(semanticId)
        if semanticId == "control:lab.preview.scale" or semanticId == "control:lab.preview.opacity" then
            return { controlId="live." .. semanticId }
        end
        return nil
    end,
    Execute = function(controlId, value)
        catalogWrites = catalogWrites + 1
        lastCatalog = { controlId=controlId, value=value }
        return true
    end,
}

namespace.Assistant.ExecutePlan = function(plan, opts)
    planCalls = planCalls + 1
    lastPlan = plan
    if plan.kind == "changes" then
        local change = assert(plan.changes and plan.changes[1], "missing setting change")
        if change.setting.confirmRequired and not (opts and opts.confirmed) then
            return { status="confirm", text="Confirmation required before this change." }
        end
        change.setting.set(change.value)
        return { status="applied", text="Applied through the Assistant plan." }
    end
    if plan.kind == "action" then
        if plan.action.confirmRequired and not (opts and opts.confirmed) then
            return { status="confirm", text="Confirmation required before this action." }
        end
        plan.action.run(plan.args or {})
        return { status="applied", text="Action ran through the Assistant plan." }
    end
    error("unexpected plan kind " .. tostring(plan.kind))
end

_G.MSUF_NS = namespace
local chunk, loadError = loadfile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema.lua")
Check(chunk, loadError)
chunk("MidnightSimpleUnitFrames_Assistant", namespace)
local Schema = assert(namespace.Assistant.ControlSchema, "ControlSchema did not load")

local function Conversation(text)
    local result = Schema.TryConversation(text)
    Check(type(result) == "table", text .. ": missing deterministic response")
    return result
end

local function ExpectApplied(text, settingKey, expected)
    local writesBefore, rawBefore = settingWrites, catalogWrites
    local result = Conversation(text)
    Check(result.status == "applied", text .. ": expected applied, got " .. tostring(result.status))
    Check(settingWrites == writesBefore + 1 and catalogWrites == rawBefore, text .. ": wrong transaction boundary")
    Check(lastPlan and lastPlan.kind == "changes" and lastPlan.changes[1].setting.key == settingKey,
        text .. ": wrong setting mutated")
    local actual = lastPlan.changes[1].value
    if expected ~= nil then
        if type(expected) == "number" then
            Check(type(actual) == "number" and math.abs(actual - expected) < 0.0001,
                text .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        else
            Check(actual == expected, text .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        end
    end
    return result, actual
end

ExpectApplied("enable Alpha Sentinel Primary Toggle", "lab.enabled", true)
Check((writeCounts["lab.enabled.decoy"] or 0) == 0, "near-match secondary toggle was mutated")
Check(lastValueParserCall and lastValueParserCall.raw == "enable Alpha Sentinel Primary Toggle",
    "Registry value parser did not receive the original text")
ExpectApplied("disable Alpha Sentinel Primary Toggle", "lab.enabled", false)
ExpectApplied("set Gamma Width Slider to 43", "lab.width", 45)
ExpectApplied("set Gamma Width Slider to 999", "lab.width", 100)
ExpectApplied("set Delta Opacity Ratio to 35%", "lab.opacity", 0.35)
ExpectApplied("set Epsilon Scale Percent to 73%", "lab.scale", 75)
ExpectApplied("set Zeta Layout Mode to Roomy", "lab.layout", "SPACIOUS")

local _, color = ExpectApplied("set Eta Accent Color to #336699", "lab.color", nil)
Check(type(color) == "table" and math.abs(color.r - 0.2) < 0.0001
    and math.abs(color.g - 0.4) < 0.0001 and math.abs(color.b - 0.6) < 0.0001 and color.a == 1,
    "color conversation did not normalize RGB(A)")
ExpectApplied('set Theta Label Text to "Raid Anchor Name"', "lab.text", "Raid Anchor Name")

local actionPlansBefore, actionRunsBefore = planCalls, actionRuns
local actionResult = Conversation("run Iota Target Batch Action 3")
Check(actionResult.status == "applied" and planCalls == actionPlansBefore + 1 and actionRuns == actionRunsBefore + 1,
    "typed action did not execute through one Assistant plan: status=" .. tostring(actionResult.status)
        .. " plans=" .. tostring(planCalls - actionPlansBefore) .. " runs=" .. tostring(actionRuns - actionRunsBefore)
        .. " text=" .. tostring(actionResult.text))
Check(lastPlan.kind == "action" and lastPlan.args.unit == "target" and lastPlan.args.count == 3,
    "typed action args were not preserved in the plan")

actionPlansBefore, actionRunsBefore = planCalls, actionRuns
actionResult = Conversation('create Omicron Profile Action "Raid Main"')
Check(actionResult.status == "applied" and planCalls == actionPlansBefore + 1 and actionRuns == actionRunsBefore + 1,
    "text-valued action did not execute through one Assistant plan")
Check(lastPlan.args.name == "Raid Main" and actionArgumentCalls == 2,
    "text-valued action args or parseAliasArgs calls drifted")

local writesBefore, plansBefore = settingWrites, planCalls
local confirm = Conversation("enable Kappa Destructive Toggle")
Check(confirm.status == "confirm" and settingWrites == writesBefore and planCalls == plansBefore + 1,
    "confirm setting wrote before confirmation or skipped the transaction plan")

for _, guarded in ipairs({
    { text="enable Lambda Guided Toggle", needle="Lambda", status="info" },
    { text="enable Mu Read Only Toggle", needle="Mu", status="info" },
    { text="set Tau Drag Position to 10 20", needle="Tau", status="info" },
    { text="change Upsilon Reorder Row", needle="Upsilon", status="info" },
}) do
    writesBefore, plansBefore = settingWrites, planCalls
    local result = Conversation(guarded.text)
    Check(result.status == guarded.status and tostring(result.text):find(guarded.needle, 1, true),
        guarded.text .. ": missing safe guidance")
    Check(settingWrites == writesBefore and planCalls == plansBefore, guarded.text .. ": guarded control executed")
end

writesBefore, plansBefore = settingWrites, planCalls
local ambiguous = Conversation("enable Nu Twin Beacon")
Check(ambiguous.status == "needs_choice" and tostring(ambiguous.text):find("few close controls", 1, true),
    "equal-score controls were not reported as ambiguous")
Check(settingWrites == writesBefore and planCalls == plansBefore, "ambiguous controls mutated")
Check(Schema.TryConversation("Alpha Sentinel Primary Toggle") == nil,
    "non-mutating bare control text was treated as permission to write")
Check(settingWrites == writesBefore and planCalls == plansBefore, "non-mutating text changed a setting")

local openedBefore = #opened
local navigation = Conversation("show me Alpha Sentinel Primary Toggle")
Check(navigation.status == "navigated" and #opened == openedBefore + 1
    and opened[#opened].kind == "setting" and opened[#opened].key == "lab.enabled",
    "show-me navigation did not focus the exact setting")
navigation = Conversation("take me to Gamma Width Slider")
Check(navigation.status == "navigated" and opened[#opened].key == "lab.width",
    "take-me navigation did not focus the exact setting")

for _, malformed in ipairs({
    "set Gamma Width Slider",
    "set Gamma Width Slider to huge",
    "set Zeta Layout Mode to impossible",
    "set Eta Accent Color to #GGHHII",
    "set Theta Label Text",
    "run Iota Target Batch Action bananas",
}) do
    writesBefore, plansBefore, actionRunsBefore = settingWrites, planCalls, actionRuns
    local result = Conversation(malformed)
    Check(result.status == "ambiguous" or result.status == "needs_value" or result.status == "info",
        malformed .. ": malformed value was not guided")
    Check(settingWrites == writesBefore and planCalls == plansBefore and actionRuns == actionRunsBefore,
        malformed .. ": malformed value executed")
end

local rawBefore = catalogWrites
local rawResult = Conversation("set Rho Preview Scale Percent to 73%")
Check(rawResult.status == "applied" and catalogWrites == rawBefore + 1
    and lastCatalog.controlId == "live.control:lab.preview.scale" and lastCatalog.value == 75,
    "percentIsValue preview did not keep and step the whole percentage")
rawBefore = catalogWrites
rawResult = Conversation("set Sigma Preview Opacity Ratio to 35%")
Check(rawResult.status == "applied" and catalogWrites == rawBefore + 1
    and lastCatalog.controlId == "live.control:lab.preview.opacity"
    and math.abs(lastCatalog.value - 0.35) < 0.0001,
    "ratio preview did not convert percent input to a zero-to-one value")

print(string.format(
    "assistant_control_schema_conversation_smoke: ok settings=%d plans=%d actions=%d raw=%d guarded_and_malformed=true",
    settingWrites, planCalls, actionRuns, catalogWrites))
