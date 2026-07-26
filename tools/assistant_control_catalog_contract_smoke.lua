-- Focused fail-closed contract smoke for persisted Menu2 controls.
-- Usage from repository root:
--   lua tools/lua51_bom_runner.lua tools/assistant_control_catalog_contract_smoke.lua

local requestedRoot = arg[1] or "MidnightSimpleUnitFrames"
local addonRoot = requestedRoot:gsub("MidnightSimpleUnitFrames$", "MidnightSimpleUnitFrames_Options")
if addonRoot == requestedRoot and not requestedRoot:match("MidnightSimpleUnitFrames_Options$") then
    addonRoot = requestedRoot .. "/MidnightSimpleUnitFrames_Options"
end

local function Check(value, message)
    if not value then error("CONTROL CATALOG CONTRACT FAIL: " .. tostring(message), 2) end
end

local function Read(path)
    local file, err = io.open(path, "rb")
    Check(file, err)
    local text = file:read("*a") or ""
    file:close()
    return text
end

local namespace = { MSUF2 = {} }
local chunk, err = loadfile(addonRoot .. "/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")
Check(chunk, err)
chunk("MidnightSimpleUnitFrames", namespace)
local M = namespace.MSUF2
local Catalog = M.RuntimeControlCatalog

local function Widget(kind)
    return {
        GetObjectType = function() return kind or "CheckButton" end,
    }
end

local function ToggleCommand(onSet)
    return {
        kind = "toggle",
        get = function() return false end,
        set = function(value)
            if type(onSet) == "function" then onSet(value) end
            return true
        end,
    }
end

local closureWrites, reviewedWrites, ephemeralWrites = 0, 0, 0

-- An arbitrary executable closure is capability evidence, not a semantic
-- Assistant target.  It must remain an explicit completeness gap.
Catalog.Register(Widget(), {
    controlId = "menu2.contract.closure_only",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    label = "Closure only",
    command = ToggleCommand(function() closureWrites = closureWrites + 1 end),
}, "contract-smoke")

Catalog.Register(Widget(), {
    controlId = "menu2.contract.explicit_setting",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    settingKey = "contract.explicitSetting",
    label = "Explicit setting",
    command = ToggleCommand(),
}, "contract-smoke")

for _, disposition in ipairs({ "compound", "dynamic", "duplicate" }) do
    local routeMeta = disposition == "dynamic" and {
        assistantSettingKeys = { "contract.dynamicExact" },
        assistantSettingKeyPatterns = { "^contract%.dynamic%.%w+$" },
    } or {}
    Catalog.Register(Widget(), {
        controlId = "menu2.contract.reviewed_" .. disposition,
        pageKey = "contract",
        kind = "toggle",
        classification = "setting",
        assistantDisposition = disposition,
        assistantDispositionReason = "Reviewed " .. disposition .. " control with no one-to-one target.",
        assistantSettingKeys = routeMeta.assistantSettingKeys,
        assistantSettingKeyPatterns = routeMeta.assistantSettingKeyPatterns,
        label = "Reviewed " .. disposition,
        command = ToggleCommand(function() reviewedWrites = reviewedWrites + 1 end),
    }, "contract-smoke")
end

-- A disposition without its review rationale is invalid and unresolved.
local _, invalidRecord = Catalog.Register(Widget(), {
    controlId = "menu2.contract.invalid_review",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    assistantDisposition = "dynamic",
    assistantSettingKeyPatterns = { "contract.dynamic" },
    label = "Invalid review",
    command = ToggleCommand(),
}, "contract-smoke")

Catalog.Register(Widget("Button"), {
    controlId = "menu2.contract.explicit_action",
    pageKey = "contract",
    kind = "button",
    classification = "action",
    actionKey = "contract.explicitAction",
    actionFixedArgs = { preset = "1080p", nested = { enabled = true } },
    actionInputArg = "name",
    label = "Explicit action",
    command = { kind = "button", set = function() return true end },
}, "contract-smoke")

local promoteWidget = Widget()
Catalog.Register(promoteWidget, {
    controlId = "menu2.contract.promoted",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    assistantDisposition = "dynamic",
    assistantDispositionReason = "Virtual control follows a selected target before promotion.",
    assistantSettingKeys = { "contract.promotedDynamic" },
    label = "Promoted setting",
    command = ToggleCommand(),
}, "contract-smoke")
local _, promoted = Catalog.Register(promoteWidget, {
    controlId = "menu2.contract.promoted",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    settingKey = "contract.promotedSetting",
    label = "Promoted setting",
    command = ToggleCommand(),
}, "contract-smoke")
Check(promoted.assistantDisposition == "" and promoted.assistantDispositionReason == "",
    "explicit target promotion retained a stale reviewed disposition")
Check(#(promoted.assistantSettingKeys or {}) == 0 and #(promoted.assistantSettingKeyPatterns or {}) == 0,
    "explicit target promotion retained stale reviewed dynamic routes")

-- Transient workspace state is not part of the persisted denominator.
Catalog.Register(Widget(), {
    controlId = "menu2.contract.ephemeral",
    pageKey = "contract",
    kind = "toggle",
    classification = "ephemeral",
    label = "Ephemeral",
    command = ToggleCommand(function() ephemeralWrites = ephemeralWrites + 1 end),
}, "contract-smoke")

local valid, errors = Catalog.ValidateRecord(invalidRecord)
Check(valid == false and #errors > 0, "invalid reviewed disposition passed schema validation")

local report = Catalog.GetCoverageReport()
Check(report.persistedControls == 8, "persisted denominator counted transient controls")
Check(report.resolvedTargets == 3 and report.explicitTargetCount == 3,
    "explicit setting/action targets were not counted exactly")
Check(report.reviewedDispositionCount == 3, "reviewed dispositions were not accounted exactly")
Check(report.reviewedDispositionCounts.compound == 1
    and report.reviewedDispositionCounts.dynamic == 1
    and report.reviewedDispositionCounts.duplicate == 1,
    "reviewed disposition breakdown drifted")
Check(report.unresolvedTargetCount == 2, "closure-only and invalid-review gaps were not retained")
Check(report.invalidAssistantDispositionCount == 1, "invalid disposition was not reported")
Check(report.reviewedDynamicRouteControlCount == 1
    and report.reviewedDynamicRouteKeyCount == 1
    and report.reviewedDynamicRoutePatternCount == 1,
    "reviewed dynamic route inventory drifted")
Check(report.invalidAssistantRouteCount == 1, "malformed dynamic route was not reported")
Check(report.assistantContractComplete == false and report.catalogComplete == false,
    "incomplete Assistant contract was presented as complete")
Check(report.resolvedTargets + report.reviewedDispositionCount + report.unresolvedTargetCount
        == report.persistedControls,
    "persisted Assistant contract denominator is internally inconsistent")

-- When the LoD registry is available, keep a separate exact-key crosswalk.
-- Catalog-local action keys remain visible instead of being mistaken for a
-- registered Assistant action.
_G.MSUF_NS = namespace
namespace.Assistant = {
    Registry = {
        GetSetting = function(_, key)
            return (key == "contract.explicitSetting" or key == "contract.promotedSetting") and {} or nil
        end,
        GetAction = function() return nil end,
    },
}
local crosswalk = Catalog.GetCoverageReport()
Check(crosswalk.targetValidationAvailable == true and crosswalk.registryValidatedTargetCount == 2
    and crosswalk.registryMissingTargetCount == 1,
    "explicit target registry crosswalk did not fail closed")
Check(crosswalk.assistantRegistryCrosswalkComplete == false and crosswalk.catalogComplete == false,
    "missing registry target was hidden from completeness")

local records = Catalog.GetRecords()
local byId = {}
for i = 1, #records do byId[records[i].controlId] = records[i] end
local descriptors, descriptorById = Catalog.GetAssistantDescriptors(), {}
for i = 1, #descriptors do descriptorById[descriptors[i].controlId] = descriptors[i] end
Check(byId["menu2.contract.closure_only"].assistantLinkDisposition == "setting.unresolved",
    "closure-only control received an inferred Assistant link")
Check(byId["menu2.contract.reviewed_dynamic"].assistantLinkDisposition == "setting.reviewed-dynamic",
    "reviewed dynamic disposition was not exposed")
Check(#(byId["menu2.contract.reviewed_dynamic"].assistantSettingKeys or {}) == 1
    and #(byId["menu2.contract.reviewed_dynamic"].assistantSettingKeyPatterns or {}) == 1,
    "reviewed dynamic route metadata was not exposed")
Check(descriptorById["menu2.contract.closure_only"].safety == "guided",
    "closure-only persisted control was not guided")
for _, disposition in ipairs({ "compound", "dynamic", "duplicate" }) do
    Check(descriptorById["menu2.contract.reviewed_" .. disposition].safety == "guided",
        "reviewed " .. disposition .. " persisted control was not guided")
end
Check(descriptorById["menu2.contract.invalid_review"].safety == "guided",
    "invalid persisted control was not guided")
Check(descriptorById["menu2.contract.explicit_action"].actionInputArg == "name"
    and descriptorById["menu2.contract.explicit_action"].actionFixedArgs.preset == "1080p"
    and descriptorById["menu2.contract.explicit_action"].actionFixedArgs.nested.enabled == true,
    "typed action identity metadata did not survive the catalog descriptor")
Check(descriptorById["menu2.contract.explicit_setting"].safety == "direct"
    and descriptorById["menu2.contract.promoted"].safety == "direct"
    and descriptorById["menu2.contract.explicit_action"].safety == "direct",
    "explicit Registry targets were not direct")
Check(descriptorById["menu2.contract.ephemeral"].safety == "nonStateful",
    "ephemeral control was not nonStateful")

local executed, reason = Catalog.Execute("menu2.contract.closure_only", true)
Check(executed == false and reason == "guided" and closureWrites == 0,
    "closure-only persisted callback crossed the transaction fence")
executed, reason = Catalog.Execute("menu2.contract.reviewed_dynamic", true)
Check(executed == false and reason == "guided" and reviewedWrites == 0,
    "reviewed dynamic callback crossed the transaction fence")
executed, reason = Catalog.Execute("menu2.contract.ephemeral", true)
Check(executed == true and ephemeralWrites == 1,
    "ephemeral nonStateful callback could not execute: " .. tostring(reason))

local dynamicExact, _, exactSource = Catalog.FindBySettingKey("contract.dynamicExact", "contract")
Check(dynamicExact and exactSource == "reviewed_dynamic_key"
    and dynamicExact.settingKey == nil and dynamicExact.resolvedSettingKey == "contract.dynamicExact",
    "finite reviewed dynamic key did not resolve without rewriting its canonical settingKey")
local dynamicPattern, _, patternSource = Catalog.FindBySettingKey("contract.dynamic.family", "contract")
Check(dynamicPattern and patternSource == "reviewed_dynamic_pattern"
    and dynamicPattern.resolvedSettingKey == "contract.dynamic.family",
    "reviewed dynamic key pattern did not resolve")

Catalog.Register(Widget(), {
    controlId = "menu2.contract.overlapping_dynamic",
    pageKey = "contract",
    kind = "toggle",
    classification = "setting",
    assistantDisposition = "dynamic",
    assistantDispositionReason = "Deliberate overlap fixture for fail-closed lookup.",
    assistantSettingKeyPatterns = { "^contract%.dynamic%.%w+$" },
    label = "Overlapping dynamic",
    command = ToggleCommand(),
}, "contract-smoke")
local ambiguous, _, ambiguousSource = Catalog.FindBySettingKey("contract.dynamic.family", "contract")
Check(ambiguous == nil and ambiguousSource == "ambiguous_reviewed_dynamic",
    "overlapping reviewed dynamic routes did not fail closed")

-- A reviewed Registry-only setting must stop before descriptor matching.  The
-- descriptor deliberately resembles the explicit fixture above; resolving it
-- there would reproduce the wrong-control class this contract prevents.
local standalone, _, standaloneSource = Catalog.FindBySettingKey("contract.standalone", "contract", {
    type = "boolean",
    attribute = "explicitSetting",
    label = "Explicit setting",
    category = "Contract",
    menuControlDisposition = "standalone",
    menuControlDispositionReason = "This fixture intentionally has no visible scalar control.",
    menuControlDispositionEvidence = "assistant_control_catalog_contract_smoke.lua standalone fixture",
})
Check(standalone == nil and standaloneSource == "reviewed_standalone",
    "reviewed standalone setting fell through to an unrelated semantic control")

Catalog.Register(Widget(), {
    controlId = "menu2.classpower.percent_symbol_alias",
    pageKey = "classpower",
    kind = "toggle",
    classification = "setting",
    settingKey = "bars.playerHPBarTextRightHidePercentSymbol",
    controlPath = "classpower/advanced/player/hp/text/player/hpbar/text/right/hide/percent/symbol",
    label = "Hide percent symbol",
    command = ToggleCommand(),
}, "contract-smoke")
local duplicateAlias, _, duplicateSource = Catalog.FindBySettingKey(
    "bars.playerHPBarTextRightPercentSymbol", "classpower", {
        type = "boolean",
        attribute = "playerHPBarTextRightPercentSymbol",
        category = "Global / Class Resources / Player HP Bar",
    })
Check(duplicateAlias and duplicateSource == "reviewed_duplicate_alias"
    and duplicateAlias.settingKey == "bars.playerHPBarTextRightHidePercentSymbol"
    and duplicateAlias.resolvedSettingKey == "bars.playerHPBarTextRightPercentSymbol",
    "reviewed inverse-setting alias did not retain the canonical control key")

-- Direct-manipulation rows carry ordered state and must never be treated as a
-- scalar click merely because a callback exists.
local dragWrites = 0
Catalog.Register(Widget(), {
    controlId = "menu2.contract.ephemeral_dragrow",
    pageKey = "contract",
    kind = "dragrow",
    classification = "ephemeral",
    label = "Ephemeral drag row",
    command = ToggleCommand(function() dragWrites = dragWrites + 1 end),
}, "contract-smoke")
executed, reason = Catalog.Execute("menu2.contract.ephemeral_dragrow", 1)
Check(executed == false and reason == "invalid_value" and dragWrites == 0,
    "drag row accepted an arbitrary scalar write")

-- The one-time FirstLoad scene has six stateful buttons.  They are discrete
-- actions, not settings inferred from their callbacks, and all receive stable
-- explicit action keys through the shared registration helper.
local firstLoad = Read(addonRoot .. "/Shell/Menu2/MSUF_Menu2_FirstLoad.lua")
Check(firstLoad:find('classification = classification or "action"', 1, true),
    "FirstLoad controls lost explicit action classification")
Check(firstLoad:find('actionKey = (classification or "action") == "action" and ("first_load." .. suffix) or nil', 1, true),
    "FirstLoad controls lost explicit action keys")
for _, id in ipairs({ "personalize", "import_profile", "use_defaults", "whats_new", "not_now", "full_settings" }) do
    Check(firstLoad:find('"' .. id .. '"', 1, true), "FirstLoad stateful control missing: " .. id)
end
Check(firstLoad:find('RegisterControl(card, data.id, data.title, "action"', 1, true),
    "FirstLoad route cards are not registered as actions")
Check(firstLoad:find('RegisterControl(button, id, label, "action"', 1, true),
    "FirstLoad footer buttons are not registered as actions")

local firstLoadChunk, firstLoadError = loadfile(addonRoot .. "/Shell/Menu2/MSUF_Menu2_FirstLoad.lua")
Check(firstLoadChunk, firstLoadError)
firstLoadChunk("MidnightSimpleUnitFrames", namespace)
for _, suffix in ipairs({ "personalize", "import_profile", "use_defaults", "whats_new", "not_now", "full_settings" }) do
    local id = "menu2.home.first_load_6." .. suffix
    local record = Catalog.Get(id)
    Check(record and record.virtual == true and record.classification == "action"
        and record.actionKey == "first_load." .. suffix
        and record.command and type(record.command.set) == "function",
        "FirstLoad conditional action is absent from the closed-scene catalog: " .. suffix)
end

print("CONTROL CATALOG ASSISTANT CONTRACT PASS")
print(string.format("persisted=%d explicit=%d reviewed=%d unresolved=%d",
    report.persistedControls, report.resolvedTargets, report.reviewedDispositionCount, report.unresolvedTargetCount))
