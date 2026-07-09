local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames spell/corner indicator assistant domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for shared group helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.SpellIndicators
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
MSUF = ctx.MSUF or MSUF
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local AddAliasesForUnit = ctx.AddAliasesForUnit
local GroupDB = ctx.GroupDB
local ClampNumber = ctx.ClampNumber
local ApplyGroup = ctx.ApplyGroup

if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return end
if type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return end
do
local BuildSpellIndicatorCore = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildSpellIndicatorCore
local Core = type(BuildSpellIndicatorCore) == "function" and BuildSpellIndicatorCore({
    A = A,
    MSUF = MSUF,
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    ApplyGroup = ApplyGroup,
}) or nil
if type(Core) ~= "table" then return end

local SCOPES = Core.SCOPES or {}
local SPEC_VALUES = Core.SPEC_VALUES or {}
local SPEC_DISPLAY_LABELS = Core.SPEC_DISPLAY_LABELS or {}
local SPEC_ALIASES = Core.SPEC_ALIASES or {}
local CI_CATEGORY_VALUES = Core.CI_CATEGORY_VALUES or {}
local CI_MODE_VALUES = Core.CI_MODE_VALUES or {}
local CI_FILTER_VALUES = Core.CI_FILTER_VALUES or {}
local CI_CATEGORY_ALIASES = Core.CI_CATEGORY_ALIASES or {}
local CI_MODE_ALIASES = Core.CI_MODE_ALIASES or {}
local CI_FILTER_ALIASES = Core.CI_FILTER_ALIASES or {}
local CI_SLOTS = Core.CI_SLOTS or {}
local Scope = Core.Scope
local Clamp01 = Core.Clamp01
local ColorSame = Core.ColorSame
local SpellRuntime = Core.SpellRuntime
local SpellDB = Core.SpellDB
local SpecDisplay = Core.SpecDisplay
local ResolveSpec = Core.ResolveSpec
local ResolveAura = Core.ResolveAura
local EnsureSpec = Core.EnsureSpec
local SpellEntry = Core.SpellEntry
local Placed = Core.Placed
local FrameEffect = Core.FrameEffect
local ApplySpell = Core.ApplySpell
local CopyTable = Core.CopyTable
local CustomConfig = Core.CustomConfig
local ActivateCustom = Core.ActivateCustom
local ResolveSlot = Core.ResolveSlot
local AddSlotAliases = Core.AddSlotAliases
local RegisterGroupNested = Core.RegisterGroupNested

if type(Scope) ~= "function" or type(RegisterGroupNested) ~= "function" then return end
if type(AddSlotAliases) ~= "function" or type(ColorSame) ~= "function" then return end
if type(SpellDB) ~= "function" or type(ResolveSpec) ~= "function" or type(EnsureSpec) ~= "function" then return end
if type(CustomConfig) ~= "function" or type(ActivateCustom) ~= "function" or type(ApplySpell) ~= "function" then return end

for _, scope in ipairs(SCOPES) do
    local aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicators", "zauber indikatoren")
    AddAliasesForUnit(aliases, scope, "spell indicator", "zauber indikator")
    AddAliasesForUnit(aliases, scope, "tracked spells", "verfolgte zauber")
    RegisterGroupNested(scope, "spellIndicators.enabled", "spellIndicators", "Spell Indicators", "boolean", aliases, {
        get = function() return SpellDB(scope).enabled == true end,
        set = function(value)
            local si = SpellDB(scope)
            si.enabled = value and true or false
            local specKey = ResolveSpec(si.spec)
            if specKey and specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator layer", "zauber indikator ebene")
    AddAliasesForUnit(aliases, scope, "spell indicators layer", "zauber indikatoren ebene")
    AddAliasesForUnit(aliases, scope, "tracked spell layer", "verfolgte zauber ebene")
    RegisterGroupNested(scope, "spellIndicators.layer", "spellIndicatorLayer", "Spell Indicator Layer", "number", aliases, {
        min = 0, max = 30, step = 1,
        get = function() return tonumber(SpellDB(scope).layer) or 9 end,
        set = function(value) SpellDB(scope).layer = ClampNumber(value, 0, 30, 1) end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator spec", "zauber indikator spec")
    AddAliasesForUnit(aliases, scope, "spell indicators spec", "zauber indikatoren spec")
    AddAliasesForUnit(aliases, scope, "tracked spell spec", "verfolgte zauber spec")
    RegisterGroupNested(scope, "spellIndicators.spec", "spellIndicatorSpec", "Spell Indicator Spec", "enum", aliases, {
        values = SPEC_VALUES, displayValues = SPEC_DISPLAY_LABELS, valueAliases = SPEC_ALIASES,
        get = function() return ResolveSpec(SpellDB(scope).spec) or "auto" end,
        set = function(value)
            local specKey = ResolveSpec(value) or "auto"
            SpellDB(scope).spec = specKey
            if specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

end

local RegisterCornerIndicatorSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterCornerIndicatorSettings
if type(RegisterCornerIndicatorSettings) == "function" then
    RegisterCornerIndicatorSettings({
        SCOPES = SCOPES,
        CI_CATEGORY_VALUES = CI_CATEGORY_VALUES,
        CI_MODE_VALUES = CI_MODE_VALUES,
        CI_FILTER_VALUES = CI_FILTER_VALUES,
        CI_CATEGORY_ALIASES = CI_CATEGORY_ALIASES,
        CI_MODE_ALIASES = CI_MODE_ALIASES,
        CI_FILTER_ALIASES = CI_FILTER_ALIASES,
        CI_SLOTS = CI_SLOTS,
        AddAliasesForUnit = AddAliasesForUnit,
        AddSlotAliases = AddSlotAliases,
        GroupDB = GroupDB,
        ClampNumber = ClampNumber,
        Clamp01 = Clamp01,
        ColorSame = ColorSame,
        CustomConfig = CustomConfig,
        ActivateCustom = ActivateCustom,
        RegisterGroupNested = RegisterGroupNested,
    })
end

local RegisterSpellIndicatorActions = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterSpellIndicatorActions
if type(RegisterSpellIndicatorActions) == "function" then
    RegisterSpellIndicatorActions({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        CI_SLOTS = CI_SLOTS,
        Scope = Scope,
        GroupDB = GroupDB,
        ApplyGroup = ApplyGroup,
        ResolveSpec = ResolveSpec,
        ResolveAura = ResolveAura,
        ResolveSlot = ResolveSlot,
        SpellEntry = SpellEntry,
        SpecDisplay = SpecDisplay,
        SpellRuntime = SpellRuntime,
        SpellDB = SpellDB,
        EnsureSpec = EnsureSpec,
        ApplySpell = ApplySpell,
        CopyTable = CopyTable,
        ClampNumber = ClampNumber,
        Clamp01 = Clamp01,
        Placed = Placed,
        FrameEffect = FrameEffect,
    })
end
end
