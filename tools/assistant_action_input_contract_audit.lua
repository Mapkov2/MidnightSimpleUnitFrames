-- Exhaustive LoD audit for deterministic Assistant action input contracts.
_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
Loader.LoadAssistantRuntime(_G.MSUF_NS, {
    includeDashboard = true,
    includeDialogLocale = true,
    useCompanionPrivate = true,
})

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant namespace missing")
local Registry = assert(A.Registry, "Assistant Registry missing")
local Inputs = assert(A.ActionInputs, "Assistant action input catalog missing")
assert(type(Inputs.Normalize) == "function", "action input normalizer missing")
assert(type(Inputs.GetContract) == "function", "action input contract lookup missing")
assert(type(Registry.NormalizeActionInput) == "function", "registry action input normalizer export missing")
assert(A.NormalizeAssistantActionInput == Inputs.Normalize, "Assistant normalizer alias drifted")
assert(#(Inputs.CatalogErrors or {}) == 0, table.concat(Inputs.CatalogErrors or {}, "\n"))

local actions = Registry:AllActions() or {}
assert(#actions == 177, "expected 177 registered actions, got " .. tostring(#actions))

-- Reuse the existing action-contract inventory's desktop-only source-range
-- technique as a drift detector.  Production contracts never inspect source;
-- this gate merely proves that every direct args.field read remains declared.
local sourceCache = {}
local function SourceLines(path)
    path = tostring(path or ""):gsub("^@", "")
    if sourceCache[path] then return sourceCache[path] end
    local lines = {}
    local handle = io.open(path, "r")
    if handle then
        for line in handle:lines() do lines[#lines + 1] = line end
        handle:close()
    end
    sourceCache[path] = lines
    return lines
end

local function DirectArgFields(action)
    local info = type(action.run) == "function" and debug.getinfo(action.run, "S") or nil
    if not info then return {} end
    local lines = SourceLines(info.source)
    local fields, seen = {}, {}
    for lineNo = tonumber(info.linedefined) or 1, tonumber(info.lastlinedefined) or 0 do
        local line = tostring(lines[lineNo] or "")
        for field in line:gmatch("args%s*%.%s*([%a_][%w_]*)") do
            if not seen[field] then seen[field], fields[#fields + 1] = true, field end
        end
        for _, quote in ipairs({ '"', "'" }) do
            local pattern = "args%s*%[" .. quote .. "([%a_][%w_]*)" .. quote .. "%]"
            for field in line:gmatch(pattern) do
                if not seen[field] then seen[field], fields[#fields + 1] = true, field end
            end
        end
    end
    table.sort(fields)
    return fields
end

local contractCount = 0
for key in pairs(Inputs.Contracts or {}) do
    contractCount = contractCount + 1
    assert(Registry:GetAction(key), "orphan action input contract: " .. tostring(key))
end
assert(contractCount == 177, "expected 177 explicit contracts, got " .. tostring(contractCount))

local function ValidateDescriptor(descriptor, path, seen)
    assert(type(descriptor) == "table", path .. " descriptor missing")
    seen = seen or {}
    if seen[descriptor] then return end
    seen[descriptor] = true
    local kind = descriptor.type
    assert(kind == "boolean" or kind == "number" or kind == "integer" or kind == "string"
        or kind == "enum" or kind == "array" or kind == "map" or kind == "color" or kind == "oneOf",
        path .. " has unsupported descriptor type " .. tostring(kind))
    if kind == "enum" then
        assert(type(descriptor.values) == "table" and #descriptor.values > 0, path .. " enum has no values")
        assert(type(descriptor._lookup) == "table", path .. " enum lookup missing")
    elseif kind == "array" then
        ValidateDescriptor(descriptor.items, path .. "[]", seen)
    elseif kind == "map" then
        assert(type(descriptor.fields) == "table", path .. " map fields missing")
        for field, child in pairs(descriptor.fields) do
            assert(type(field) == "string", path .. " map field is not a string")
            ValidateDescriptor(child, path .. "." .. field, seen)
        end
    elseif kind == "oneOf" then
        assert(type(descriptor.choices) == "table" and #descriptor.choices > 0, path .. " union has no choices")
        for i = 1, #descriptor.choices do ValidateDescriptor(descriptor.choices[i], path .. "|" .. tostring(i), seen) end
    end
end

local function ValidateConstraintSpec(spec, fields, path)
    for _, listName in ipairs({ "required", "requireAny", "allOrNone" }) do
        local list = spec[listName]
        assert(list == nil or type(list) == "table", path .. " " .. listName .. " must be a table")
    end
    for j = 1, #(spec.required or {}) do
        assert(fields[spec.required[j]], path .. " requires unknown field " .. tostring(spec.required[j]))
    end
    for _, groupName in ipairs({ "requireAny", "allOrNone" }) do
        for j = 1, #(spec[groupName] or {}) do
            local group = spec[groupName][j]
            assert(type(group) == "table" and #group > 0, path .. " has empty " .. groupName .. " group")
            for k = 1, #group do
                assert(fields[group[k]], path .. " " .. groupName .. " references unknown field " .. tostring(group[k]))
            end
        end
    end
    for field, descriptor in pairs(spec.fieldTypes or {}) do
        assert(fields[field], path .. " fieldTypes references unknown field " .. tostring(field))
        ValidateDescriptor(descriptor, path .. ".fieldTypes." .. tostring(field))
    end
    for field, dependency in pairs(spec.dependentTypes or {}) do
        assert(fields[field], path .. " dependentTypes references unknown field " .. tostring(field))
        assert(type(dependency) == "table" and fields[dependency.by], path .. " dependent type has unknown discriminator")
        assert(dependency.default == nil or type(dependency.default) == "table", path .. " dependent default is invalid")
        if dependency.default then ValidateDescriptor(dependency.default, path .. ".dependentTypes." .. tostring(field) .. ".default") end
        assert(type(dependency.values) == "table", path .. " dependent type values missing")
        for value, descriptor in pairs(dependency.values) do
            ValidateDescriptor(descriptor, path .. ".dependentTypes." .. tostring(field) .. "." .. tostring(value))
        end
    end
end

local directFieldChecks, unknownFieldChecks = 0, 0
for i = 1, #actions do
    local action = actions[i]
    local key = tostring(action.key or "")
    local contract = Inputs.GetContract(key)
    assert(type(contract) == "table", "missing contract: " .. key)
    assert(action.assistantInput == contract, "registered action contract mismatch: " .. key)
    assert(action.assistantInputExplicit == true, "contract not marked explicit: " .. key)
    assert(action.assistantInputError == nil, "contract registration error: " .. key .. ": " .. tostring(action.assistantInputError))
    assert(action.assistantInputSource == "registry.actionInputs.v1", "contract source mismatch: " .. key)
    assert(contract.kind == "none" or contract.kind == "object", "invalid contract kind: " .. key)
    assert(type(contract.fields) == "table", "contract fields missing: " .. key)
    if contract.kind == "none" then
        assert(next(contract.fields) == nil, "none contract exposes fields: " .. key)
    else
        for field, descriptor in pairs(contract.fields) do
            assert(type(field) == "string", "non-string action field: " .. key)
            ValidateDescriptor(descriptor, key .. "." .. field)
        end
        ValidateConstraintSpec(contract, contract.fields, key)
        if contract.discriminator ~= nil then
            assert(contract.fields[contract.discriminator], key .. " has unknown discriminator field")
            assert(type(contract.variants) == "table" and next(contract.variants) ~= nil, key .. " variants missing")
            for value, variant in pairs(contract.variants) do
                assert(type(variant) == "table" and type(variant.fields) == "table", key .. " variant missing fields: " .. tostring(value))
                assert(variant.fields[contract.discriminator], key .. " variant omits discriminator: " .. tostring(value))
                for field in pairs(variant.fields) do
                    assert(contract.fields[field], key .. " variant exposes unknown field " .. tostring(field))
                end
                ValidateConstraintSpec(variant, variant.fields, key .. ".variant." .. tostring(value))
            end
        end
    end
    local directFields = DirectArgFields(action)
    for j = 1, #directFields do
        local field = directFields[j]
        assert(contract.kind == "object" and contract.fields[field],
            key .. " directly reads undeclared action input field " .. tostring(field))
        directFieldChecks = directFieldChecks + 1
    end
    local unexpected, unexpectedErr = Inputs.Normalize(key, { __msuf_unknown_action_input__ = true })
    assert(unexpected == nil and type(unexpectedErr) == "string", key .. " accepted an unknown action input field")
    unknownFieldChecks = unknownFieldChecks + 1
end

local validCases, invalidCases = 0, 0
local function Valid(key, args, verify)
    local label = type(key) == "table" and key.key or key
    local before = args
    local normalized, err = Inputs.Normalize(key, args)
    assert(type(normalized) == "table", tostring(label) .. " expected valid input: " .. tostring(err))
    if before ~= nil then assert(normalized ~= before, tostring(label) .. " returned the caller's mutable table") end
    if verify then verify(normalized) end
    validCases = validCases + 1
    return normalized
end

local function Invalid(key, args, needle)
    local label = type(key) == "table" and key.key or key
    local normalized, err = Inputs.Normalize(key, args)
    assert(normalized == nil, tostring(label) .. " unexpectedly accepted invalid input")
    assert(type(err) == "string" and err ~= "", tostring(label) .. " invalid input returned no error")
    if needle then assert(err:find(needle, 1, true), tostring(label) .. " error did not mention " .. needle .. ": " .. err) end
    invalidCases = invalidCases + 1
end

Valid("assistant_help", nil, function(out) assert(next(out) == nil) end)
Valid("assistant_help", {})
Invalid("assistant_help", { unexpected = true }, "does not accept")
Invalid("assistant_help", "", "plain object")
Invalid("assistant_help", setmetatable({}, {}), "plain object")
Invalid({ key = "assistant_help", assistantInput = { kind = "object", fields = { unexpected = { type = "boolean" } } } },
    { unexpected = true }, "does not accept")
Invalid("__missing_action_contract__", {}, "missing explicit")

Valid("toggle_absorb_bar_test", { value = "off" }, function(out) assert(out.value == false) end)
Valid("class_power_preview_animate", { value = 1 }, function(out) assert(out.value == true) end)
Invalid("toggle_absorb_bar_test", { value = "sometimes" }, "boolean")
Invalid("toggle_absorb_bar_test", { value = false, typo = true }, "unknown input field")

Valid("assistant.action.editMode.backgroundOpacity", { value = "0.75" }, function(out) assert(out.value == 0.75) end)
Valid("assistant.action.editMode.gridStep", { value = "12" }, function(out) assert(out.value == 12) end)
Invalid("assistant.action.editMode.backgroundOpacity", { value = math.huge }, "finite number")
Invalid("assistant.action.editMode.backgroundOpacity", { value = 0 / 0 }, "finite number")
Invalid("assistant.action.editMode.backgroundOpacity", { value = 1.1 }, "at most")
Invalid("assistant.action.editMode.gridStep", { value = 2.5 }, "integer")
Invalid("assistant.action.editMode.gridStep", { value = 7 }, "at least")
Invalid("assistant.action.editMode.gridStep", {}, "requires input field")

Valid("apply_global_scale_preset", { preset = "2160p" }, function(out) assert(out.preset == "4k") end)
Valid("apply_aura_quick_preset", { preset = "fast", scope = "GLOBAL" }, function(out)
    assert(out.preset == "performance" and out.scope == "shared")
end)
Invalid("apply_global_scale_preset", { preset = "8k" }, "allowed value")
Invalid("apply_aura_quick_preset", {}, "requires input field")

local copyInput = { source = "PLAYER", targets = { "target", "focus" }, scopes = { text = "on", layout = false } }
Valid("copy_unit", copyInput, function(out)
    assert(out.source == "player" and out.targets[1] == "target" and out.targets[2] == "focus")
    assert(out.scopes.text == true and out.scopes.layout == false)
    assert(copyInput.scopes.text == "on", "normalizer mutated nested caller input")
end)
Invalid("copy_unit", { source = "player", targets = { "target", "target" } }, "duplicate")
Invalid("copy_unit", { source = "player", targets = { [1] = "target", [3] = "focus" } }, "dense array")
Invalid("copy_unit", { source = "player", targets = { "target" }, scopes = { madeUp = true } }, "unknown field")
Invalid("copy_unit", { source = "player", targets = { "party" } }, "allowed value")
Invalid("copy_unit", { source = "player" }, "requires input field")
Valid("copy_group", { target = "raid" }, function(out) assert(out.target == "raid") end)
Valid("copy_group", { targets = { "raid", "mythic raid" } }, function(out) assert(out.targets[2] == "mythicraid") end)
Valid("copy_group", { target = "raid", scopes = { health = true, dispel = false } }, function(out)
    assert(out.scopes.health == true and out.scopes.dispel == false)
end)
Invalid("copy_group", {}, "requires one of")

Valid("set_global_font_color", { r = "0.1", g = 0.2, b = 0.3, label = "custom" }, function(out)
    assert(out.r == 0.1 and out.g == 0.2 and out.b == 0.3)
end)
Valid("set_global_font_color", { color = "purple" })
Invalid("set_global_font_color", { r = 0.1, g = 0.2 }, "all or none")
Invalid("set_global_font_color", {}, "requires one of")

Valid("set_group_spell_indicator_aura", {
    scope = "party", spec = "Holy Paladin", aura = "Beacon of Light", field = "frameColor",
    value = { r = 1, g = 0.5, b = 0, a = 0.8, label = "orange" },
}, function(out)
    assert(out.value.r == 1 and out.value.g == 0.5 and out.value.b == 0 and out.value.a == 0.8)
    assert(out.value.label == "orange")
end)
Valid("set_group_spell_indicator_aura", {
    text = "Holy Paladin Beacon of Light", field = "enabled", value = false,
}, function(out) assert(out.value == false) end)
Valid("set_group_spell_indicator_aura", {
    text = "Holy Paladin Beacon of Light", field = "placedSize", value = "24",
}, function(out) assert(out.value == 24) end)
Invalid("set_group_spell_indicator_aura", {
    spec = "Holy Paladin", aura = "Beacon", field = "madeUp", value = true,
}, "allowed value")
Invalid("set_group_spell_indicator_aura", {
    spec = "Holy Paladin", aura = "Beacon", field = "frameColor", value = { r = 1, g = 1, b = 1, surprise = 1 },
}, "wrong type")
Invalid("set_group_spell_indicator_aura", {
    text = "Holy Paladin Beacon of Light", field = "enabled", value = { r = 1, g = 1, b = 1 },
}, "boolean")
Invalid("set_group_spell_indicator_aura", {
    text = "Holy Paladin Beacon of Light", field = "placedSize", value = 49,
}, "at most")
Invalid("move_group_spell_indicator_order", { spec = "Holy Paladin", aura = "Beacon", position = 0 }, "at least")

local importText = "  !MSUF_TEST_PAYLOAD  "
Valid("import_profile_string", { value = importText, uufBestEffortAccepted = "yes" }, function(out)
    assert(out.value == importText and out.uufBestEffortAccepted == true, "import text was not preserved exactly")
end)
Invalid("import_profile_string", { value = "" }, "too short")
Invalid("import_profile_string_new", { value = "!MSUF_TEST" }, "requires input field")

Valid("aura_custom_whitelist_add_spell", { scope = "target", index = "3", value = 12345 }, function(out)
    assert(out.index == 3 and out.value == 12345)
end)
Invalid("aura_custom_whitelist_add_spell", { scope = "target", index = 4, value = 12345 }, "at most")
Valid("aura_group_category_blacklist_set", {
    scope = "mythic raid", lane = "debuffs", category = "exhaustion", value = "on",
}, function(out)
    assert(out.scope == "raid" and out.lane == "debuff" and out.category == "SATED" and out.value == true)
end)
Valid("aura_blacklist_summary", { scope = "shared", lane = "both" })
Invalid("aura_blacklist_add_spell", { scope = "target", value = 12345 }, "string")
Valid("preview_group_status_icon", { scope = "party", mode = "current", text = "preview group status" })

Valid("set_menu_selector_state", {
    selector = "profile_staging", field = "profileimportstring", value = " !MSUF_PAYLOAD ",
}, function(out)
    assert(out.field == "profileString" and out.value == " !MSUF_PAYLOAD ")
end)
Valid("set_menu_selector_state", {
    selector = "profile_staging", field = "profileString", value = "0",
}, function(out) assert(out.value == "0", "profile staging text was coerced") end)
Valid("set_menu_selector_state", {
    selector = "profile_staging", field = "profileExportKind", kind = "group frames",
}, function(out) assert(out.kind == "groupframe") end)
Valid("set_menu_selector_state", {
    selector = "unit_text_move_together", unit = "target", tab = "health", value = "off",
}, function(out) assert(out.tab == "hp" and out.value == false) end)
Valid("set_menu_selector_state", {
    selector = "unit_copy_scope", command = "select all", categories = { "text", "portrait" },
}, function(out)
    assert(out.command == "selectall" and out.categories[2] == "portrait")
end)
Valid("set_menu_selector_state", {
    selector = "group_copy_scope", command = "only", categories = { "health", "dispel" },
}, function(out)
    assert(out.command == "only" and out.categories[2] == "dispel")
end)
Invalid("set_menu_selector_state", { selector = "unknown_selector" }, "allowed value")
Invalid("set_menu_selector_state", { selector = "unit_text", arbitrary = "value" }, "unknown input field")
Invalid("set_menu_selector_state", { selector = "unit_text", unit = "target", tab = "hp", kind = "power" }, "does not accept field")

Valid("guided_setup", {})
Invalid("guided_setup", { style = "castbar setup guide" }, "does not accept input fields")
Valid("guided_setup_step", {})
Valid("guided_setup_step", { step = "NEXT" }, function(out) assert(out.step == "next") end)
Invalid("guided_setup_step", { step = "finish" }, "allowed value")
Valid("set_nav_search_intro", {})
Valid("reset_power_color_token", { token = "runic power" }, function(out) assert(out.token == "RUNIC_POWER") end)
Valid("reset_class_power_color_token", { token = "soul fragments" }, function(out) assert(out.token == "SOUL_FRAGMENTS") end)
Invalid("reset_class_power_color_token", { token = "COMBO_POINTS_1" }, "allowed value")
Valid("reset_class_power_slot_colors", { resourceToken = "combo_points" }, function(out) assert(out.resourceToken == "COMBO_POINTS") end)
Invalid("reset_class_power_slot_colors", { resourceToken = "NOT_A_RESOURCE" }, "allowed value")

Valid("open_page", { page = "uf_target", query = "target width", label = "Target" })
Invalid("open_page", { page = "uf target" }, "invalid format")
Invalid("open_page", { page = "uf_target", mutate = true }, "unknown input field")
Valid("open_setting_control", { settingKey = "target.width", page = "uf_target" })
Invalid("open_setting_control", { page = "uf_target" }, "requires input field")

local sourcePath = "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ActionInputs.lua"
local handle = assert(io.open(sourcePath, "rb"), "could not read action input source")
local source = handle:read("*a")
handle:close()
for _, forbidden in ipairs({
    "debug%.getinfo", "debug%.getlocal", "io%.open", "loadfile%s*%(", "dofile%s*%(",
    "CreateFrame%s*%(", "RegisterEvent%s*%(", "C_Timer", "SetScript%s*%(", "hooksecurefunc%s*%(",
}) do
    assert(not source:find(forbidden), "action input runtime contains forbidden introspection/idle work: " .. forbidden)
end

print("assistant_action_input_contract_audit: ok actions=" .. tostring(#actions)
    .. " contracts=" .. tostring(contractCount)
    .. " directFields=" .. tostring(directFieldChecks)
    .. " unknownFields=" .. tostring(unknownFieldChecks)
    .. " valid=" .. tostring(validCases)
    .. " invalid=" .. tostring(invalidCases))
