_G = _G or _ENV

local file = assert(io.open("tools/assistant_control_schema_collect.lua", "rb"))
local source = file:read("*a") or ""
file:close()
assert(source:find('_G.__MSUF_ASSISTANT_GRAPHIFY_SOURCE = "inventory"', 1, true),
    "schema collector no longer selects the tracked Graphify inventory explicitly")
local marker = 'local source = Read("tools/assistant_v1_catalog_crosswalk.lua")'
local at = assert(source:find(marker, 1, true), "collector architecture marker changed")
source = source:sub(1, at - 1) .. [==[
local function Check(value, message)
    if not value then error("ASSISTANT CONTROL SCHEMA SEMANTICS FAIL: " .. tostring(message), 2) end
end

local expectedKinds = {
    toggle = "boolean", slider = "number", dropdown = "enum", segment = "enum", color = "color",
    textinput = "string", button = "action", drag = "position", dragrow = "reorder",
}
for kind, expected in pairs(expectedKinds) do
    Check(ResolveValueKind({ kind = kind }) == expected, kind .. " value kind")
end
Check(ResolveValueKind({ kind = "button", valueKind = "text" }) == "text", "explicit action argument kind")
Check(ControlPathLabel("opt/colors/group/frame/dead/bg/a") == "Dead Background Alpha", "channel path label")
Check(ControlPathLabel("group/layout/field/scaleAt10") == "Scale at 10 Players", "numeric path label")
Check(ControlPathLabel("group/layout/field/scaleat10") == "Scale at 10 Players", "normalized path label")

local preserved = ResolveHelp({ help = "Existing menu help.", kind = "slider" }, {}, {}, "direct")
Check(preserved == "Existing menu help.", "existing Menu help must be preserved exactly")

local sliderHelp = ResolveHelp({ kind = "slider", label = "Opacity", pageKey = "gf_bars", min = 0,
    max = 1, step = 0.05 }, { description = "Controls frame opacity" }, nil, "direct")
Check(sliderHelp:find("Controls frame opacity.", 1, true), "registry description fallback")
Check(sliderHelp:find("Group Frames > Dispel Overlay", 1, true), "human page fallback")
Check(sliderHelp:find("Allowed range: 0 to 1 in increments of 0.05.", 1, true), "numeric constraints")
local priorityHelp = ResolveHelp({ kind = "toggle", label = "Enable Priority Frames", pageKey = "gf_priority" })
Check(priorityHelp:find("Group Frames > Priority", 1, true), "Priority Frames page fallback")

local enumValues = {}
for i = 1, 10 do enumValues[i] = { value = "VALUE_" .. i, text = "Choice " .. i } end
local enumHelp = ResolveHelp({ kind = "dropdown", label = "Mode", pageKey = "gameplay", values = enumValues },
    nil, nil, "guided")
Check(enumHelp:find("Available choices: Choice 1", 1, true), "enum choices")
Check(enumHelp:find("(and 2 more)", 1, true), "bounded enum choices")
Check(enumHelp:find("instead of changing it automatically", 1, true), "guided safety remains explicit")

local dynamicHelp = ResolveHelp({ kind = "dropdown", label = "Profile", pageKey = "profiles", values = {} },
    nil, nil, "readOnly")
Check(dynamicHelp:find("Choices load from the current MSUF context.", 1, true), "dynamic choices fallback")
Check(dynamicHelp:find("inspection only", 1, true), "read-only safety remains explicit")

local textActionHelp = ResolveHelp({ kind = "button", valueKind = "text", label = "Create profile",
    pageKey = "profiles" }, nil, { description = "Creates a named profile" }, "confirm")
Check(textActionHelp:find("Requires a text value.", 1, true), "text-valued action argument")
Check(textActionHelp:find("requires confirmation", 1, true), "confirmation safety remains explicit")

local fakeActions = {
    ["contract.input"] = {
        key = "contract.input", mutability = "savedState", assistantInputExplicit = true,
        assistantInput = {
            kind = "object", required = { "name" }, requireAny = {},
            fields = { name = { type = "string", minLength = 1, maxLength = 128, _lookup = { ignored = true } } },
        },
    },
    ["contract.missing"] = { key = "contract.missing", mutability = "savedState" },
}
local fakeRegistry = {
    GetSetting = function() return nil end,
    GetAction = function(_, key) return fakeActions[key] end,
}
local dynamicFields = DescriptorFields({ semanticId="control:dynamic", classification="setting", kind="slider",
    safety="guided", assistantDisposition="dynamic", min=0, max=10, step=1 }, fakeRegistry)
Check(dynamicFields[12] == "direct", "reviewed dynamic scalar transaction safety")
local orderFields = DescriptorFields({ semanticId="control:order", classification="setting", kind="dragrow",
    safety="guided", assistantDisposition="dynamic" }, fakeRegistry)
Check(orderFields[12] == "guided", "ordered state requires a typed owner")
local inputFields = DescriptorFields({ semanticId="action:input", classification="action", kind="button",
    safety="guided", actionKey="contract.input", actionInputArg="name" }, fakeRegistry)
Check(inputFields[12] == "direct" and inputFields[24] == "name" and inputFields[25] == "string"
    and tostring(inputFields[26]):find("_lookup", 1, true) == nil
    and tostring(inputFields[26]) ~= "",
    "typed action input contract was not emitted without private lookup state")
local missingActionFields = DescriptorFields({ semanticId="action:missing", classification="action", kind="button",
    safety="direct", actionKey="contract.missing" }, fakeRegistry)
Check(missingActionFields[12] == "guided", "missing action contract did not fail closed")
local function FakeDescriptor(semanticId, controlId, pageKey)
    return {
        semanticId = semanticId, controlId = controlId, pageKey = pageKey,
        controlPath = pageKey .. "/" .. controlId, classification = "setting", kind = "toggle",
        safety = "direct", identityStable = true, label = controlId,
    }
end
local descriptors = {
    FakeDescriptor("setting:shared", "shared", "uf_player"),
    FakeDescriptor("setting:default-only", "default-only", "gf_auras"),
}
local fakeCatalog = { GetAssistantDescriptors = function() return descriptors end }
Check(CaptureAssistantControlSchemaState("test_default", fakeCatalog, fakeRegistry) == 2, "default state count")
descriptors = {
    FakeDescriptor("setting:shared", "shared", "uf_player"),
    FakeDescriptor("setting:routed-only", "routed-only", "gf_auras"),
}
Check(CaptureAssistantControlSchemaState("test_routed", fakeCatalog, fakeRegistry) == 2, "routed state count")
Check(#collectionStates == 2 and collectionStateById.test_default.count == 2
    and collectionStateById.test_routed.count == 2,
    "named collection states")
local unionCount = 0
for _ in pairs(collectionUnion) do unionCount = unionCount + 1 end
Check(unionCount == 3, "semantic-ID state union")
Check(CollectionStateMembership(collectionUnion["setting:shared"]) == "*", "shared state membership")
Check(CollectionStateMembership(collectionUnion["setting:default-only"]) == "test_default", "default-only membership")
Check(CollectionStateMembership(collectionUnion["setting:routed-only"]) == "test_routed", "routed-only membership")

descriptors = { FakeDescriptor("setting:shared", "shared", "uf_player") }
descriptors[1].actionFixedArgs = { mode = "unexpected" }
local contractStable, contractError = pcall(
    CaptureAssistantControlSchemaState, "test_contract_drift", fakeCatalog, fakeRegistry)
Check(contractStable == false and tostring(contractError):find("semantic contract drift", 1, true),
    "semantic IDs must not merge different action or value-domain contracts")

descriptors = { FakeDescriptor("setting:shared", "changed-control-id", "uf_player") }
local stable, stableError = pcall(CaptureAssistantControlSchemaState, "test_identity_drift", fakeCatalog, fakeRegistry)
Check(stable == false and tostring(stableError):find("semantic identity drift", 1, true),
    "semantic-ID collisions must fail closed")

print("assistant_control_schema_collect_semantics_smoke: ok (9 kinds, help fallbacks, state union, stable contracts and IDs)")
]==]

local chunk, err = loadstring(source, "@tools/assistant_control_schema_collect.lua")
assert(chunk, err)
chunk()
