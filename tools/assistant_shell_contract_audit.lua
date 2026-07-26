_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")

local function Exists(path)
    local file = io.open(path, "r")
    if file then file:close(); return true end
    return false
end

local prefix = Exists("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc") and "" or "../../"
local function Path(relative) return prefix .. relative end
local function Read(relative)
    local path = Path(relative)
    local file = assert(io.open(path, "r"), path)
    local source = file:read("*a")
    file:close()
    return source
end
local function Load(relative, addonName, namespace)
    local chunk, errorText = loadfile(Path(relative))
    assert(chunk, errorText)
    return chunk(addonName, namespace)
end
local function Require(source, marker, message)
    assert(source:find(marker, 1, true), message .. ": " .. marker)
end
local function Count(source, marker)
    local count, cursor = 0, 1
    while true do
        local found = source:find(marker, cursor, true)
        if not found then return count end
        count, cursor = count + 1, found + #marker
    end
end
local function TableCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local catalogSource = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")
local window = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua")
local nav = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_NavRail.lua")
local bridge = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_AssistantBridge.lua")
local acceptance = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantAudit.lua")
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local dropdowns = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Dropdowns.lua")

local requiredActions = {
    ["menu2.menu-chrome.window-close"] = { source = window, path = "window.close", actionKey = "menu_window_close" },
    ["menu2.menu-chrome.window-minimize"] = { source = window, path = "window.minimize", actionKey = "menu_window_minimize" },
    ["menu2.menu-chrome.window-maximize"] = { source = window, path = "window.maximize", actionKey = "menu_window_maximize" },
    ["menu2.menu-chrome.window-restore"] = { source = window, path = "window.restore", actionKey = "menu_window_restore" },
    ["menu2.menu-chrome.search-clear"] = { source = nav, path = "search.clear", actionKey = "menu_search_clear" },
    ["menu2.menu-chrome.search-intro-dismiss"] = { source = nav, path = "search.intro-dismiss", actionKey = "set_nav_search_intro" },
}

-- Keep the minimum shell surface fail-closed and prove the production call
-- sites carry the same semantic action identity that the LoD Registry exposes.
Require(catalogSource, "minimumControls = 6", "shell control minimum is not fail-closed")
Require(catalogSource, "minimumDispositions = 14", "shell disposition minimum is not fail-closed")
for controlId, expected in pairs(requiredActions) do
    Require(catalogSource, controlId, "required shell ID is absent from contract")
    Require(expected.source, '"' .. expected.path .. '"', "required shell action is not registered")
    Require(expected.source, 'actionKey = "' .. expected.actionKey .. '"',
        "required shell action lacks its canonical Assistant actionKey")
end

local expectedDispositions = {
    ["window.drag"] = "direct-manipulation",
    ["window.resize"] = "direct-manipulation",
    ["minimized-window.drag"] = "direct-manipulation",
    ["scroll.mechanics"] = "navigation-mechanic",
    ["search.input"] = "self-referential-input",
    ["assistant.input"] = "self-referential-input",
    ["assistant.run"] = "self-referential-submit",
    ["dropdown.choice-rows"] = "logical-dropdown-values",
    ["dropdown.scrollbar"] = "navigation-mechanic",
    ["toggle.label-proxy"] = "logical-toggle-component",
    ["slider.value-input"] = "logical-slider-component",
    ["slider.step-buttons"] = "logical-slider-component",
    ["segment.buttons"] = "logical-segment-component",
    ["scope-selector.buttons"] = "logical-selector-component",
}
for disposition in pairs(expectedDispositions) do
    Require(catalogSource, '["' .. disposition .. '"]',
        "interactive shell mechanic has no explicit disposition")
end

-- Preserve the real shell construction/mechanics assertions from the original
-- regression; catalog metadata must never become a substitute for the UI that
-- actually owns each button or logical component.
for _, path in ipairs({ "window.close", "window.minimize", "window.maximize", "window.restore" }) do
    Require(window, 'M.RegisterMenuChromeControl(', "window shell has no chrome registration")
    Require(window, '"' .. path .. '"', "window action is not registered")
end
assert(Count(window, "CreateWindowControlButton(") == 5,
    "window control button count changed; update REQUIRED_SHELL_CONTRACT and this audit deliberately")
Require(window, "M.MarkRuntimeControlComponent(M.minimizedBar.closeButton, close)",
    "minimized close button is not owned by logical Close")

Require(nav, 'M.RegisterMenuChromeControl(close, "search.intro-dismiss"', "search intro dismiss is not registered")
Require(nav, 'M.RegisterMenuChromeControl(clear, "search.clear"', "search clear is not registered")
Require(nav, 'controlId = "menu2.menu-chrome.search-intro-dismiss"',
    "lazy search intro has no frame-free contract before its button is built")
assert(Count(nav, 'CreateFrame("Button"') == 2 and Count(nav, 'CreateFrame("EditBox"') == 1 and Count(nav, "T.Button(") == 4,
    "navigation/search interaction factory count changed; classify the new shell interaction deliberately")

Require(nav, 'actionKey = "menu_history_undo"', "menu Undo has no current Registry action")
Require(nav, 'actionKey = "menu_history_redo"', "menu Redo has no current Registry action")
Require(window, 'actionKey = "assistant.action.editMode.toggle"', "Edit Mode toolbar action has no current Registry action")
Require(window, 'M.RegisterMenuChromeControl(toolbarTask, "toolbar.new-task", "New Task", "ephemeral"',
    "session-only New Task control is not explicitly ephemeral")
Require(window, 'actionKey = "menu_reset_current_page_prompt"',
    "current-page reset prompt has no current Registry action")

Require(widgets, "M.MarkRuntimeControlComponent(labelHit, btn)", "toggle label proxy is not a logical component")
Require(widgets, "M.MarkRuntimeControlComponent(edit, slider)", "slider value input is not a logical component")
Require(widgets, "M.MarkRuntimeControlComponent(btn, slider)", "slider step button is not a logical component")
Require(widgets, "M.MarkRuntimeControlComponent(btn, holder)", "segment button is not a logical component")
Require(widgets, "M.MarkRuntimeControlComponent(btn, bar)", "scope-selector button is not a logical component")
Require(dropdowns, "local function DropdownItemValue(item)", "dropdown row values have no single logical-value adapter")

-- The active architecture is the zero-idle core bridge plus the V1 LoD
-- companion. Acceptance consumes ControlCatalog coverage directly; no removed
-- MSUF_AssistantV2 module may be needed for either load or coverage.
Require(bridge, 'RUNTIME_ADDON = "MidnightSimpleUnitFrames_Assistant"', "bridge targets the wrong LoD companion")
Require(bridge, "function A.EnsureRuntimeLoaded(reason)", "bridge has no current LoD entry point")
Require(bridge, "pcall(addons.LoadAddOn, RUNTIME_ADDON)", "bridge does not use the protected WoW LoD loader")
Require(bridge, "if not runtimeLoaded then", "bridge trusts addon status without runtime API acceptance")
Require(acceptance, "local function BuildAcceptanceGate()", "current Assistant has no acceptance gate")
Require(acceptance, "M.GetRuntimeControlCoverageReport()", "acceptance gate ignores ControlCatalog coverage")
Require(acceptance, "catalog.catalogComplete == true", "acceptance gate ignores catalog completeness")
Require(acceptance, "catalog.targetValidationAvailable == true", "acceptance gate accepts coverage without Registry validation")
Require(acceptance, "catalog.unresolvedTargetCount", "acceptance gate ignores unresolved catalog targets")

-- Exercise the actual ControlCatalog, bridge, and all LoD Registry scripts.
-- Synthetic widgets represent the six real shell call sites already proven
-- above, allowing deterministic Lua 5.1 coverage without constructing WoW UI.
local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua", "MidnightSimpleUnitFrames", MSUF)
Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_AssistantBridge.lua", "MidnightSimpleUnitFrames", MSUF)

local M = assert(MSUF.MSUF2, "Menu2 namespace missing")
local Catalog = assert(M.RuntimeControlCatalog, "current RuntimeControlCatalog did not load")
local contract = assert(M.REQUIRED_SHELL_CONTRACT, "required shell contract missing at runtime")
assert(contract.minimumControls == 6 and TableCount(contract.controls) == 6,
    "required shell control contract must remain exactly six deliberate controls")
assert(contract.minimumDispositions == 14 and TableCount(contract.dispositions) == 14,
    "required shell disposition contract must remain exactly fourteen deliberate mechanics")
for disposition, expected in pairs(expectedDispositions) do
    assert(contract.dispositions[disposition] == expected,
        "shell disposition drifted: " .. tostring(disposition))
end

for controlId, expected in pairs(requiredActions) do
    local declared = assert(contract.controls[controlId], "runtime shell contract lost " .. controlId)
    assert(declared.classification == "action" and declared.kind == "button",
        "runtime shell contract changed semantics for " .. controlId)
    if declared.actionKey ~= nil then
        assert(declared.actionKey == expected.actionKey,
            "runtime shell contract actionKey drifted for " .. controlId)
    end
    local widget = {}
    local registeredId = assert(M.RegisterMenuChromeControl(widget, expected.path, expected.path, "action", {
        actionKey = expected.actionKey,
        historyMode = "none",
        command = { kind = "button", historyMode = "none", set = function() return true end },
    }))
    assert(registeredId == controlId, "runtime chrome registration produced the wrong controlId")
end

local beforeLoad = Catalog.GetCoverageReport()
assert(beforeLoad.targetValidationAvailable == false,
    "ControlCatalog unexpectedly loaded the Assistant before an explicit request")

M.frame = { IsShown = function() return true end }
local loadCalls, addonLoaded = 0, false
_G.C_AddOns = _G.C_AddOns or {}
_G.C_AddOns.LoadAddOn = function(addonName)
    assert(addonName == "MidnightSimpleUnitFrames_Assistant", "bridge requested the wrong addon")
    loadCalls = loadCalls + 1
    Loader.LoadAssistantRuntime(MSUF, {
        root = prefix ~= "" and prefix or nil,
        includeDashboard = true,
        includeDialogLocale = true,
        useCompanionPrivate = true,
    })
    addonLoaded = true
    return true
end
_G.C_AddOns.IsAddOnLoaded = function(addonName)
    assert(addonName == "MidnightSimpleUnitFrames_Assistant", "bridge checked the wrong addon")
    return addonLoaded, addonLoaded
end

local A = assert(MSUF.Assistant, "zero-idle Assistant bridge missing")
assert(A.IsRuntimeLoaded() == false, "Assistant runtime was not cold before EnsureRuntimeLoaded")
local loaded, loadError = A.EnsureRuntimeLoaded("shell-contract-audit")
assert(loaded == true, "Assistant LoD bridge failed: " .. tostring(loadError))
assert(loadCalls == 1 and A.IsRuntimeLoaded() == true,
    "Assistant LoD runtime was not accepted exactly once")
local loadedAgain = A.EnsureRuntimeLoaded("shell-contract-audit-repeat")
assert(loadedAgain == true and loadCalls == 1, "warm Assistant request reloaded the LoD companion")

local Registry = assert(MSUF.Assistant.Registry, "LoD Assistant Registry missing")
local coverage = Catalog.GetCoverageReport()
assert(coverage.targetValidationAvailable == true, "catalog did not attach to the loaded Assistant Registry")
assert(coverage.persistedControls == 6 and coverage.explicitTargetCount == 6,
    "six shell controls did not remain explicit persisted actions")
assert(coverage.registryValidatedTargetCount == 6 and coverage.registryMissingTargetCount == 0,
    "shell action keys do not have exact LoD Registry parity")
assert(coverage.unresolvedTargetCount == 0 and coverage.invalidAssistantDispositionCount == 0,
    "shell controls contribute unresolved or invalid Assistant contracts")
assert(coverage.assistantContractComplete == true and coverage.assistantRegistryCrosswalkComplete == true,
    "shell controls do not satisfy the current catalog/Registry contract")
for controlId, expected in pairs(requiredActions) do
    local record = assert(Catalog.Get(controlId), "catalog lost required shell record " .. controlId)
    assert(record.actionKey == expected.actionKey, "catalog actionKey drifted for " .. controlId)
    assert(Registry:GetAction(expected.actionKey), "LoD Registry missing " .. expected.actionKey)
end

-- New report fields are asserted when present so this audit remains compatible
-- with an in-flight catalog-contract patch while still failing closed once the
-- production report publishes required-shell status.
if coverage.shellContractComplete ~= nil then
    assert(coverage.shellContractComplete == true, "catalog reports an incomplete required shell contract")
end
if coverage.missingShellControls ~= nil then
    assert(#coverage.missingShellControls == 0, "catalog reports missing required shell controls")
end
if coverage.invalidShellControls ~= nil then
    assert(#coverage.invalidShellControls == 0, "catalog reports invalid required shell controls")
end
assert(coverage.catalogComplete == true, "current acceptance gate would reject the shell catalog")

print(string.format(
    "assistant_shell_contract_audit: ok controls=%d dispositions=%d registry=%d lodLoads=%d windowButtons=5",
    TableCount(contract.controls), TableCount(contract.dispositions), coverage.registryValidatedTargetCount, loadCalls))
