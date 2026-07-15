-- Focused contract/runtime regression for the selector-bound bar-gradient reset.
_G = _G or _ENV

local function Load(path, MSUF)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk("MidnightSimpleUnitFrames", MSUF)
end

local function Contains(list, value)
    for i = 1, #(list or {}) do
        if list[i] == value then return true end
    end
    return false
end

local COLOR_KEYS = {
    "healthBarGradientColorR", "healthBarGradientColorG", "healthBarGradientColorB",
    "powerBarGradientColorR", "powerBarGradientColorG", "powerBarGradientColorB",
}

local MSUF = { MSUF2 = {}, Assistant = {} }
local M, A = MSUF.MSUF2, MSUF.Assistant
_G.MSUF_NS, _G.MSUF2 = MSUF, M

local db = {
    general = { hpPowerTextSelectedKey = "shared" },
    bars = {},
    gameplay = {},
    player = {},
    gf_raid = {},
    gf_mythicraid = {},
}

local Registry = {
    settings = {}, settingsByKey = {}, aliases = {},
    actions = {}, actionsByKey = {}, todos = {},
}
A.RegistryCore = { Registry = Registry }
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ActionInputs.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Core_Registry.lua", MSUF)

local function ScopeDBKeys(scope)
    if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
    if scope == "player" then return { "player" } end
    return nil
end

M.GlobalPage = {
    CurrentBarsScope = function()
        return db.general.hpPowerTextSelectedKey or "shared"
    end,
    GradientScopeSet = function(key, value)
        local scope = db.general.hpPowerTextSelectedKey or "shared"
        if scope == "shared" then
            db.general[key] = value
            return
        end
        local scopeKeys = ScopeDBKeys(scope)
        for i = 1, #(scopeKeys or {}) do
            local entry = db[scopeKeys[i]]
            entry.hlOverride = true
            entry.gradientOverride = true
            entry.gradientOverrideVersion = 2
            entry.gradientOverrideKeys = entry.gradientOverrideKeys or {}
            entry.gradientOverrideKeys[key] = true
            entry[key] = value
        end
    end,
}

local applyCalls = {}
local function ApplyBarGradients(reason, scope)
    applyCalls[#applyCalls + 1] = { reason = reason, scope = scope }
end
local function Noop() end

Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalColorSettings_ResetContext.lua", MSUF)
assert(A.GlobalRegistry.InstallColorResetActions({
    Registry = Registry,
    GeneralDB = function() return db.general end,
    BarsDB = function() return db.bars end,
    GameplayDB = function() return db.gameplay end,
    ApplyColors = Noop,
    ApplyCastbarColors = Noop,
    ApplyBarGradients = ApplyBarGradients,
    ApplyGameplayColors = Noop,
    ApplyAuraColors = Noop,
    ApplyPortraitColors = Noop,
    ApplyClassPowerColors = Noop,
}, {
    ColorAPI = function() return {} end,
    AuraSharedDB = function() return {} end,
}, {}), "color reset context installation failed")
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalColorResetActions.lua", MSUF)

local action = assert(Registry:GetAction("reset_bar_gradient_colors"), "bar-gradient reset action was not registered")
assert(action.aliasNoArgs == true and action.combatSafe == false, "bar-gradient reset execution contract drifted")
assert(action.captureSnapshot == true and action.mutability == "savedState", "bar-gradient reset is not transactional saved state")
assert(action.actionPolicyExplicit == true and action.actionPolicyError == nil, "bar-gradient reset action policy is not explicit")
assert(action.snapshotCoverage == "complete" and action.stateOwner == "activeProfile", "bar-gradient reset snapshot owner drifted")
assert(action.assistantInputExplicit == true and action.assistantInputError == nil, "bar-gradient reset input is not explicit")
assert(action.assistantInput.kind == "none" and next(action.assistantInput.fields) == nil, "bar-gradient reset unexpectedly accepts arguments")
assert(Contains(action.aliases, "reset bar gradient colors"), "canonical bar-gradient reset alias is missing")
assert(not Contains(action.aliases, "reset gradient colors"), "bar-gradient reset captured the ambiguous health-gradient alias")
assert(type(Registry:NormalizeActionInput(action, {})) == "table", "empty bar-gradient reset input was rejected")
local normalized = Registry:NormalizeActionInput(action, { scope = "player" })
assert(normalized == nil, "selector-bound bar-gradient reset accepted a scope argument")

local menuSourceFile = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua", "rb"))
local menuSource = menuSourceFile:read("*a") or ""
menuSourceFile:close()
assert(menuSource:find('["bar_gradient.reset"] = "reset_bar_gradient_colors"', 1, true),
    "bar-gradient reset button is not mapped to its dedicated action")
local globalRegistryFile = assert(io.open("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Global.lua", "rb"))
local globalRegistrySource = globalRegistryFile:read("*a") or ""
globalRegistryFile:close()
assert(globalRegistrySource:find("ApplyBarGradients = ApplyBarGradients,", 1, true),
    "global color registry context does not expose the targeted gradient apply helper")

local function Seed(tableRef, value)
    for i = 1, #COLOR_KEYS do tableRef[COLOR_KEYS[i]] = value end
end

local function AssertReset(tableRef, label)
    for i = 1, #COLOR_KEYS do
        local key = COLOR_KEYS[i]
        assert(tableRef[key] == 0, label .. " did not reset " .. key)
    end
end

local function AssertUnchanged(tableRef, value, label)
    for i = 1, #COLOR_KEYS do
        local key = COLOR_KEYS[i]
        assert(tableRef[key] == value, label .. " unexpectedly changed " .. key)
    end
end

local function AssertOverride(tableRef, label)
    assert(tableRef.hlOverride == true and tableRef.gradientOverride == true
        and tableRef.gradientOverrideVersion == 2, label .. " override metadata was not activated")
    for i = 1, #COLOR_KEYS do
        assert(tableRef.gradientOverrideKeys[COLOR_KEYS[i]] == true,
            label .. " did not mark " .. COLOR_KEYS[i] .. " as an explicit gradient override")
    end
end

-- Shared reset changes only the six selected bar tint channels. It must not
-- invoke the older health-gradient-stop reset action by mistake.
Seed(db.general, 0.75)
db.general.healthGradientLowR, db.general.healthGradientMidG, db.general.healthGradientHighB = 0.13, 0.27, 0.91
db.general.hpPowerTextSelectedKey = "shared"
local ok, message = action.run({})
assert(ok == true and message:find("Shared", 1, true), "shared reset did not report its selected scope")
AssertReset(db.general, "shared scope")
assert(db.general.healthGradientLowR == 0.13 and db.general.healthGradientMidG == 0.27
    and db.general.healthGradientHighB == 0.91, "bar-gradient reset changed health gradient color stops")
assert(#applyCalls == 1 and applyCalls[1].reason == "MSUF_ASSISTANT_RESET_BAR_GRADIENT_COLORS"
    and applyCalls[1].scope == "shared", "shared reset did not request a targeted gradient apply")

-- A unit scope writes only its explicit override and retains shared values.
applyCalls = {}
Seed(db.general, 0.66)
Seed(db.player, 0.44)
db.general.hpPowerTextSelectedKey = "player"
ok, message = action.run({})
assert(ok == true and message:find("Player", 1, true), "player reset did not report its selected scope")
AssertReset(db.player, "player scope")
AssertUnchanged(db.general, 0.66, "shared scope")
AssertOverride(db.player, "player scope")
assert(#applyCalls == 1 and applyCalls[1].scope == "player", "player reset did not request a targeted gradient apply")

-- Raid uses the live menu writer, which mirrors both Raid storage owners.
applyCalls = {}
db.gf_raid, db.gf_mythicraid = {}, {}
db.general.hpPowerTextSelectedKey = "gf_raid"
ok, message = action.run({})
assert(ok == true and message:find("Raid", 1, true), "raid reset did not report its selected scope")
AssertReset(db.gf_raid, "raid scope")
AssertReset(db.gf_mythicraid, "mythic raid scope")
AssertOverride(db.gf_raid, "raid scope")
AssertOverride(db.gf_mythicraid, "mythic raid scope")
assert(#applyCalls == 1 and applyCalls[1].scope == "gf_raid", "raid reset did not request a targeted gradient apply")

-- Missing live UI ownership must fail before any partial profile mutation.
applyCalls = {}
db.general.hpPowerTextSelectedKey = "shared"
Seed(db.general, 0.31)
local gradientScopeSet = M.GlobalPage.GradientScopeSet
M.GlobalPage.GradientScopeSet = nil
ok, message = action.run({})
M.GlobalPage.GradientScopeSet = gradientScopeSet
assert(ok == false and message:find("unavailable", 1, true), "missing live scope writer did not fail clearly")
AssertUnchanged(db.general, 0.31, "failed shared reset")
assert(#applyCalls == 0, "failed shared reset requested a runtime apply")

print("assistant_bar_gradient_reset_smoke: ok shared=1 player=1 raidMirrors=2")
