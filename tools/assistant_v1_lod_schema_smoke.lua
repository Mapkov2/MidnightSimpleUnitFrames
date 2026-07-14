_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")

local manifestEntries = Loader.ReadRuntimeEntries(arg and arg[1] or nil)
local loaded, private = Loader.LoadAssistantRuntime(_G.MSUF_NS, {
    root = arg and arg[1] or nil,
    includeDashboard = true,
    includeDialogLocale = true,
    useCompanionPrivate = true,
})
assert(#loaded == #manifestEntries,
    "full V1 LoD load did not execute every manifest script")
assert(private ~= _G.MSUF_NS, "schema smoke did not exercise the real companion-private namespace")

local A = assert(_G.MSUF_NS.Assistant, "V1 Assistant namespace missing")
assert(private.Assistant == A, "companion bootstrap did not bridge private and core Assistant namespaces")
assert(type(A.Parse) == "function" and type(A.HandleInput) == "function" and type(A.Submit) == "function",
    "V1 parser/submit API missing")
assert(type(A.BuildDashboardCard) == "function", "V1 Dashboard API missing")
assert(type(A.UndoLast) == "function" and type(A.RedoLast) == "function", "V1 undo/redo API missing")
assert(type(A.SetMenuRuntimeActive) == "function", "V1 menu lifecycle API missing")
assert(type(_G.MSUF_NS.AssistantDialogLocaleData) == "table", "dialog locale data did not bridge to core")

local Registry = assert(A.Registry, "V1 Registry missing")
local explicitSettings = Registry:AllSettings()
local explicitSettingCount = #explicitSettings
local autoAdded = assert(A.AutoCoverage and A.AutoCoverage.Fill, "AutoCoverage API missing")()
local settings, actions = Registry:AllSettings(), Registry:AllActions()
assert(type(autoAdded) == "number" and autoAdded >= 0, "AutoCoverage did not return its added-setting count")
assert(#settings == explicitSettingCount + autoAdded,
    "AutoCoverage count does not equal the Registry growth it reported")
assert(#settings > 0 and #actions > 0, "V1 Registry unexpectedly loaded an empty schema")
assert(Registry:GetSetting("player.showName"), "representative unit-frame setting missing")
assert(Registry:GetAction("assistant.action.editMode.enter"), "representative Edit Mode action missing")
assert(Registry:GetAction("menu_window_close"), "representative menu-shell action missing")

local settingKeys, generatedSettings = {}, 0
for i = 1, #settings do
    local setting = settings[i]
    assert(type(setting) == "table" and type(setting.key) == "string" and setting.key ~= "",
        "setting without a canonical key at index " .. tostring(i))
    assert(not settingKeys[setting.key], "duplicate setting key: " .. setting.key)
    settingKeys[setting.key] = true
    assert(Registry:GetSetting(setting.key) == setting,
        "setting list/index parity failed: " .. setting.key)
    if setting.generated == true then generatedSettings = generatedSettings + 1 end
end
assert(generatedSettings == autoAdded,
    "generated setting count does not match AutoCoverage additions")

local policyCount, savedState = 0, 0
for _ in pairs(Registry.actionPoliciesByKey or {}) do policyCount = policyCount + 1 end
assert(policyCount == #actions, "not every registered action has an explicit policy")
assert(type(Registry.actionPolicyErrors) == "table" and #Registry.actionPolicyErrors == 0, "action policy catalog has errors")
local actionKeys = {}
for i = 1, #actions do
    local action = actions[i]
    assert(type(action) == "table" and type(action.key) == "string" and action.key ~= "",
        "action without a canonical key at index " .. tostring(i))
    assert(not actionKeys[action.key], "duplicate action key: " .. action.key)
    actionKeys[action.key] = true
    assert(Registry:GetAction(action.key) == action,
        "action list/index parity failed: " .. action.key)
    assert(action.actionPolicyExplicit == true, "unclassified action: " .. tostring(action.key))
    if action.mutability == "savedState" then
        savedState = savedState + 1
        local snapshot = action.snapshotCoverage == "complete"
            and (action.captureSnapshot == true or action.captureProfileSnapshot == true)
        local adapter = type(action.transactionAdapter) == "string" and action.transactionAdapter ~= ""
            and action.transactionAdapterReady == true
        assert(snapshot or adapter, "saved-state action lacks rollback contract: " .. tostring(action.key))
    end
end
assert(savedState > 0, "saved-state action policy coverage unexpectedly disappeared")

print(string.format("assistant_v1_lod_schema_smoke: ok scripts=%d settings=%d explicit=%d actions=%d auto=%d savedState=%d",
    #loaded, #settings, explicitSettingCount, #actions, autoAdded, savedState))
