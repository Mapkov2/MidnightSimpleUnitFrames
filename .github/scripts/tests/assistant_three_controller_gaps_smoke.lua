-- Focused release regression for three curated Assistant controller gaps.
_G = _G or _ENV

local function Load(path, MSUF)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk("MidnightSimpleUnitFrames", MSUF)
end

local function Contains(list, value)
    for i = 1, #(list or {}) do if list[i] == value then return true end end
    return false
end

local function AssertValues(setting, expected)
    assert(setting.type == "enum", tostring(setting.key) .. " is not a typed enum")
    assert(#(setting.values or {}) == #expected, tostring(setting.key) .. " enum count drifted")
    for i = 1, #expected do assert(setting.values[i] == expected[i], tostring(setting.key) .. " enum order drifted") end
end

local MSUF = { MSUF2 = {}, Assistant = {} }
local M, A = MSUF.MSUF2, MSUF.Assistant
_G.MSUF_NS, _G.MSUF2 = MSUF, M
_G.MSUF_DB = {
    general = { bossCastbarOffsetX = 17, bossCastbarOffsetY = -31 },
    bars = { barOutlineStrata = "AUTO" },
    player = { hlOverride = true },
    gf_raid = { hlOverride = true },
    gf_mythicraid = { hlOverride = true },
}
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

M.EnsureDB = function() return _G.MSUF_DB end
M.ApplyService = { Flush = function() end }
M.RequestGeneralApply = function() return true end

local Registry = { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {} }
function Registry:RegisterSetting(spec)
    assert(type(spec) == "table" and type(spec.key) == "string")
    assert(not self.settingsByKey[spec.key], "duplicate setting " .. spec.key)
    self.settings[#self.settings + 1] = spec
    self.settingsByKey[spec.key] = spec
    return spec
end
function Registry:GetSetting(key) return self.settingsByKey[key] end
function Registry:AllSettings() return self.settings end
function Registry:GetAction(key) return self.actionsByKey[key] end
A.Registry = Registry

Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantHistory.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantUndo.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_Assistant.lua", MSUF)

local function ResetHistory()
    A.undoStack, A.redoStack = {}, {}
    A.lastAssistantTransactionError = nil
end

local applyCount = 0
local function Apply() applyCount = applyCount + 1; return true end
local function Clamp(value, minimum, maximum, step)
    value = tonumber(value) or minimum
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    if step and step > 0 then value = math.floor(value / step + 0.5) * step end
    return value
end

-- Register the production declarations for shared and scoped outline strata.
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalBarSettings_Data.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalBarSettings_Base.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GlobalBarSettings_Scoped.lua", MSUF)
local outlineValues = { "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local barData = assert(A.GlobalBarRegistry.Data)

local function RegisterBarsEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    if dbKey ~= "barOutlineStrata" then return end
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "bars." .. dbKey, label = label, category = opts.category, unit = "global",
        frameType = opts.frameType, attribute = attr, type = "enum", aliases = aliases,
        values = values, valueAliases = opts.valueAliases,
        get = function() return allowed[_G.MSUF_DB.bars[dbKey]] and _G.MSUF_DB.bars[dbKey] or defaultValue end,
        set = function(value) _G.MSUF_DB.bars[dbKey] = allowed[value] and value or defaultValue end,
        apply = opts.apply,
    })
end
-- The shared bar outline moved off the frame-strata enum onto the unified
-- numeric Layer scale, so that is the control this gate has to follow.
local function RegisterBarsNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    if dbKey ~= "barOutlineLayer" then return end
    Registry:RegisterSetting({
        key = "bars." .. dbKey, label = label, category = opts.category, unit = "global",
        frameType = opts.frameType, attribute = attr, type = "number", aliases = aliases,
        min = minValue, max = maxValue, step = opts.step,
        get = function() return tonumber(_G.MSUF_DB.bars[dbKey]) or defaultValue end,
        set = function(value) _G.MSUF_DB.bars[dbKey] = tonumber(value) or defaultValue end,
        apply = opts.apply,
    })
end
local noop = function() end
A.GlobalBarRegistry.RegisterBaseBarSettings({
    GeneralDB = function() return _G.MSUF_DB.general end,
    ApplyBars = Apply, ApplyBarOutline = Apply, ApplyRoundedBars = Apply, ApplyAggroBorder = Apply,
    ApplyDispelPurgeBorder = Apply, ApplyBossTargetBorder = Apply, ApplyHighlightBorders = Apply,
    RegisterGeneralBoolean = noop, RegisterGeneralNumberSetting = noop, RegisterGeneralEnum = noop,
    RegisterGeneralMappedEnum = noop, RegisterBarsBoolean = noop, RegisterBarsNumber = RegisterBarsNumber,
    RegisterBarsEnum = RegisterBarsEnum,
    OUTLINE_STRATA_VALUES = barData.OUTLINE_STRATA_VALUES,
    OUTLINE_STRATA_ALIASES = barData.OUTLINE_STRATA_ALIASES,
})

local scopes = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "gf_party", "gf_raid" }
local function ScopeTables(scope)
    if scope == "gf_raid" then return { _G.MSUF_DB.gf_raid, _G.MSUF_DB.gf_mythicraid } end
    _G.MSUF_DB[scope] = _G.MSUF_DB[scope] or {}
    return { _G.MSUF_DB[scope] }
end
local function RegisterScopedSetting(kind, scope, dbKey, attr, label, settingType, defaultValue, aliases, opts)
    if dbKey ~= "barOutlineLayer" then return end
    local allowed = {}
    for i = 1, #(opts.values or {}) do allowed[opts.values[i]] = true end
    Registry:RegisterSetting({
        key = kind .. "." .. scope .. "." .. dbKey, label = label, category = "Global / Bars / Scoped",
        unit = scope, frameType = "globalBars", attribute = attr, type = settingType, aliases = aliases,
        values = opts.values, valueAliases = opts.valueAliases, sharedKind = opts.shared,
        min = opts.min, max = opts.max, step = opts.step,
        get = function()
            local value = ScopeTables(scope)[1][dbKey]
            if settingType == "number" then
                value = tonumber(value)
                if not value then return defaultValue end
                if opts.min and value < opts.min then return opts.min end
                if opts.max and value > opts.max then return opts.max end
                return value
            end
            return allowed[value] and value or defaultValue
        end,
        set = function(value)
            if settingType == "number" then
                value = tonumber(value) or defaultValue
                if opts.min and value < opts.min then value = opts.min end
                if opts.max and value > opts.max then value = opts.max end
            else
                value = allowed[value] and value or defaultValue
            end
            local tables = ScopeTables(scope)
            for i = 1, #tables do tables[i][dbKey] = value end
        end,
        apply = opts.apply,
    })
end
A.GlobalBarRegistry.RegisterScopedOverlaySettings = function() return true end
A.GlobalBarRegistry.RegisterScopedBarSettings({
    GeneralDB = function() return _G.MSUF_DB.general end,
    ApplyBars = Apply, ApplyBarGradients = Apply, ApplyBarOutline = Apply, ApplyHighlightBorders = Apply,
    RegisterScopedSetting = RegisterScopedSetting,
    RegisterScopedOverlaySettings = function() return true end,
    GLOBAL_SCOPE_ORDER = scopes,
    GlobalScopeHasOverride = function() return true end,
    GlobalScopeSetOverride = noop,
    GlobalScopeRead = function() return nil end,
    GlobalScopeWrite = noop,
    GlobalScopeAliases = function(_, aliases) return aliases end,
    NormalizeTextureKeyForAssistant = tostring,
    GRADIENT_DIRECTION_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" },
    GRADIENT_DIRECTION_KEYS = { RIGHT = "r", LEFT = "l", UP = "u", DOWN = "d" },
    GRADIENT_DIRECTION_ALIASES = {},
    OUTLINE_STRATA_VALUES = barData.OUTLINE_STRATA_VALUES,
    OUTLINE_STRATA_ALIASES = barData.OUTLINE_STRATA_ALIASES,
})

-- Bar outline draw order: one shared Bars value plus a per-scope override, all
-- on the unified 0-30 Layer scale.
local function AssertLayerDomain(setting)
    assert(setting.type == "number", tostring(setting.key) .. " is not a numeric Layer control")
    assert(tonumber(setting.min) == 0 and tonumber(setting.max) == 30,
        tostring(setting.key) .. " left the 0-30 Layer scale")
    assert(tonumber(setting.step) == 1, tostring(setting.key) .. " left the whole-step Layer scale")
end
local sharedOutline = assert(Registry:GetSetting("bars.barOutlineLayer"))
AssertLayerDomain(sharedOutline)
for i = 1, #scopes do
    local setting = assert(Registry:GetSetting("barScope." .. scopes[i] .. ".barOutlineLayer"))
    AssertLayerDomain(setting)
    assert(setting.sharedKind == "bars", setting.key .. " does not inherit the shared Bars value")
end

-- Register the production Boss castbar attachment controller.
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Core_Data.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Core_Backend.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Core_Provider.lua", MSUF)
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Castbars_Core.lua", MSUF)
local core = assert(A.CastbarsRegistry.BuildCoreContext({
    Registry = Registry, RegistryCore = {},
    UNIT_LABELS = { player = "Player", target = "Target", focus = "Focus", boss = "Boss" },
    AddAliasesForUnit = function(out, unit, phrase) out[#out + 1] = unit .. " " .. phrase end,
    GeneralDB = function() return _G.MSUF_DB.general end,
    ClampNumber = Clamp, CallGlobal = function() end, ApplyCastbar = Apply,
    RegisterGeneralEnum = noop,
}))
core.RegisterBossCastbarDetachSetting()
local bossDetach = assert(Registry:GetSetting("general.bossCastbarDetached"))
assert(bossDetach.type == "boolean" and #bossDetach.dbScopes == 3 and bossDetach.dbScopesReplace == true)
assert(Contains(bossDetach.aliases, "attach boss castbar") and Contains(bossDetach.aliases, "detach boss castbar"))

local ownerCalls = 0
local function SetBossOwner(unit, anchored)
    assert(unit == "boss")
    ownerCalls = ownerCalls + 1
    local general = _G.MSUF_DB.general
    if anchored == false then
        general.bossCastbarDetached = true
        general.bossCastbarOffsetX = 201
        general.bossCastbarOffsetY = 202
    else
        general.bossCastbarDetached = nil
    end
end
_G.MSUF_EM_SetCastbarAnchoredToUnit = SetBossOwner

-- Register the production persisted Class Resource preview Guides setting.
A.RegistryCore = { Registry = Registry, CallGlobal = function() end, GeneralDB = function() return _G.MSUF_DB.general end }
A.ClassPowerRegistryData = {
    CLASS_POWER_PREVIEW_VALUES = { "rogue_combo" },
    CLASS_POWER_PREVIEW_LABELS = { rogue_combo = "Rogue - Combo Points" },
    CLASS_POWER_PREVIEW_ALIASES = {},
}
local previewRefreshes = 0
M._msuf2ClassPowerInlinePreview = {
    layerVisibility = { guides = true },
    Refresh = function(self) previewRefreshes = previewRefreshes + 1 end,
}
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ClassPower_Preview.lua", MSUF)
local guides = assert(Registry:GetSetting("general.classPowerPreviewGuidesEnabled"))
assert(guides.type == "boolean" and Contains(guides.aliases, "show preview guides") and Contains(guides.aliases, "hide preview guides"))

-- Build a tiny schema with the real settings so invalid typed values are
-- rejected before ExecutePlan and therefore before any setter is called.
A.ControlSchemaData = {
    version = 3,
    columns = { "semanticId", "controlId", "familyId", "memberKey", "pageKey", "controlPath", "classification", "kind", "settingKey", "actionKey", "navigationKey", "safety", "valueKind", "min", "max", "step", "percentIsValue", "confirmRequired", "identityStable", "label", "help", "values", "states", "contexts" },
    records = {
        { "outline.player", "menu2.outline.player", "", "", "opt_bars", "outline/layer", "setting", "slider", "barScope.player.barOutlineLayer", "", "", "direct", "number", "0", "30", "1", "0", "0", "1", "Player outline layer", "", "", "*", "*" },
        { "boss.detach", "menu2.boss.detach", "", "", "opt_castbars", "boss/attachment", "setting", "toggle", "general.bossCastbarDetached", "", "", "direct", "boolean", "", "", "", "0", "0", "1", "Boss castbar detached", "", "", "*", "*" },
        { "preview.guides", "menu2.preview.guides", "", "", "classpower", "preview/guides", "setting", "toggle", "general.classPowerPreviewGuidesEnabled", "", "", "direct", "boolean", "", "", "", "0", "0", "1", "Preview guides", "", "", "*", "*" },
    },
}
Load("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema.lua", MSUF)
local Schema = assert(A.ControlSchema)

-- Scoped outline: invalid choice is zero-write; valid write stays scoped and
-- undo/redo uses the normal Assistant transaction.
ResetHistory()
local playerOutline = assert(Registry:GetSetting("barScope.player.barOutlineLayer"))
local beforeApply = applyCount
local ok, reason = Schema.Execute("outline.player", "NOT_A_LAYER")
assert(ok == false and reason == "invalid_value")
assert(_G.MSUF_DB.player.barOutlineLayer == nil and _G.MSUF_DB.bars.barOutlineLayer == nil and applyCount == beforeApply)
assert(Schema.Execute("outline.player", 12) == true)
assert(_G.MSUF_DB.player.barOutlineLayer == 12 and _G.MSUF_DB.bars.barOutlineLayer == nil)
assert(A.UndoLast() == true and playerOutline.get() == 0)
assert(A.RedoLast() == true and playerOutline.get() == 12)

-- Boss attachment: a later failure rolls back all three owner fields. A
-- committed detach preserves exact before/after offsets through undo/redo.
local failSetting = {
    key = "test.fail", label = "Failure", type = "boolean",
    get = function() return false end,
    set = function() error("expected failure") end,
    apply = function() end,
}
Registry:RegisterSetting(failSetting)
ResetHistory()
_G.MSUF_DB.general.bossCastbarDetached = nil
_G.MSUF_DB.general.bossCastbarOffsetX = 17
_G.MSUF_DB.general.bossCastbarOffsetY = -31
_G.MSUF_EM_SetCastbarAnchoredToUnit = function()
    _G.MSUF_DB.general.bossCastbarDetached = true
    _G.MSUF_DB.general.bossCastbarOffsetX = 999
    error("partial owner failure")
end
local partial = A.ExecutePlan({ kind = "changes", changes = { { setting = bossDetach, value = true } } })
assert((partial.status or partial.result) == "failed" and #A.undoStack == 0)
assert(_G.MSUF_DB.general.bossCastbarDetached == nil and _G.MSUF_DB.general.bossCastbarOffsetX == 17 and _G.MSUF_DB.general.bossCastbarOffsetY == -31)
_G.MSUF_EM_SetCastbarAnchoredToUnit = SetBossOwner

local failed = A.ExecutePlan({ kind = "changes", changes = {
    { setting = bossDetach, value = true }, { setting = failSetting, value = true },
} })
assert((failed.status or failed.result) == "failed" and #A.undoStack == 0)
assert(_G.MSUF_DB.general.bossCastbarDetached == nil and _G.MSUF_DB.general.bossCastbarOffsetX == 17 and _G.MSUF_DB.general.bossCastbarOffsetY == -31)

ResetHistory()
assert(Schema.Execute("boss.detach", true) == true)
assert(_G.MSUF_DB.general.bossCastbarDetached == true and _G.MSUF_DB.general.bossCastbarOffsetX == 201 and _G.MSUF_DB.general.bossCastbarOffsetY == 202)
assert(A.UndoLast() == true)
assert(_G.MSUF_DB.general.bossCastbarDetached == nil and _G.MSUF_DB.general.bossCastbarOffsetX == 17 and _G.MSUF_DB.general.bossCastbarOffsetY == -31)
assert(A.RedoLast() == true)
assert(_G.MSUF_DB.general.bossCastbarDetached == true and _G.MSUF_DB.general.bossCastbarOffsetX == 201 and _G.MSUF_DB.general.bossCastbarOffsetY == 202)

-- Preview Guides: invalid non-boolean is zero-write; mutation refreshes the
-- visible preview and remains fully undoable/redoable.
ResetHistory()
_G.MSUF_DB.general.classPowerPreviewGuidesEnabled = true
M._msuf2ClassPowerInlinePreview.layerVisibility.guides = true
beforeApply = previewRefreshes
ok, reason = Schema.Execute("preview.guides", "false")
assert(ok == false and reason == "invalid_value")
assert(_G.MSUF_DB.general.classPowerPreviewGuidesEnabled == true and previewRefreshes == beforeApply)
ok, reason = Schema.Execute("preview.guides", false)
local transactionError = A.lastAssistantTransactionError or {}
assert(ok == true, "preview guide mutation failed: " .. tostring(type(reason) == "table" and (reason.text or reason.result) or reason)
    .. " [" .. tostring(transactionError.phase) .. ":" .. tostring(transactionError.target) .. ":" .. tostring(transactionError.error) .. "]")
assert(_G.MSUF_DB.general.classPowerPreviewGuidesEnabled == false and M._msuf2ClassPowerInlinePreview.layerVisibility.guides == false)
assert(A.UndoLast() == true and guides.get() == true and M._msuf2ClassPowerInlinePreview.layerVisibility.guides == true)
assert(A.RedoLast() == true and guides.get() == false and M._msuf2ClassPowerInlinePreview.layerVisibility.guides == false)

local previewFile = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua", "rb"))
local previewSource = previewFile:read("*a")
previewFile:close()
assert(previewSource:find('settingKey = "general.classPowerPreviewGuidesEnabled"', 1, true), "Guides catalog control is not linked to its persisted setting")
assert(previewSource:find('"toggle", "setting"', 1, true), "Guides catalog control is still ephemeral")

print(string.format("assistant_three_controller_gaps_smoke: ok scopes=%d ownerCalls=%d previewRefreshes=%d", #scopes, ownerCalls, previewRefreshes))
