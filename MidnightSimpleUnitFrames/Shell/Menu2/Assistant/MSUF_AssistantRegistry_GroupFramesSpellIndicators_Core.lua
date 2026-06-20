-- Assistant GroupFrames spell/corner indicator helper core.
-- Keeps resolver and DB helper code out of the declarative setting registry.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local Namespace = ctx.MSUF or MSUF
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local ApplyGroup = ctx.ApplyGroup

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return nil end

    local SpellIndicatorData = Assistant.GroupFramesRegistry and Assistant.GroupFramesRegistry.SpellIndicatorData
    if type(SpellIndicatorData) ~= "table" then return nil end

    local SCOPES = SpellIndicatorData.SCOPES or {}
    local SPEC_VALUES = SpellIndicatorData.SPEC_VALUES or {}
    local SPEC_DISPLAY_LABELS = SpellIndicatorData.SPEC_DISPLAY_LABELS or {}
    local SPEC_ALIASES = SpellIndicatorData.SPEC_ALIASES or {}
    local CI_CATEGORY_VALUES = SpellIndicatorData.CI_CATEGORY_VALUES or {}
    local CI_MODE_VALUES = SpellIndicatorData.CI_MODE_VALUES or {}
    local CI_FILTER_VALUES = SpellIndicatorData.CI_FILTER_VALUES or {}
    local CI_CATEGORY_ALIASES = SpellIndicatorData.CI_CATEGORY_ALIASES or {}
    local CI_MODE_ALIASES = SpellIndicatorData.CI_MODE_ALIASES or {}
    local CI_FILTER_ALIASES = SpellIndicatorData.CI_FILTER_ALIASES or {}
    local CI_SLOTS = SpellIndicatorData.CI_SLOTS or {}

    local BuildSpellIndicatorSlotHelpers = Assistant.GroupFramesRegistry and Assistant.GroupFramesRegistry.BuildSpellIndicatorSlotHelpers
    local SlotCore = type(BuildSpellIndicatorSlotHelpers) == "function" and BuildSpellIndicatorSlotHelpers({
        A = Assistant,
        GroupDB = GroupDB,
        AddAliasesForUnit = AddAliasesForUnit,
        CI_SLOTS = CI_SLOTS,
    }) or nil
    if type(SlotCore) ~= "table" then return nil end

    local BuildSpellIndicatorResolvers = Assistant.GroupFramesRegistry and Assistant.GroupFramesRegistry.BuildSpellIndicatorResolvers
    local ResolverCore = type(BuildSpellIndicatorResolvers) == "function" and BuildSpellIndicatorResolvers({
        A = Assistant,
        MSUF = Namespace,
        SPEC_VALUES = SPEC_VALUES,
        SPEC_DISPLAY_LABELS = SPEC_DISPLAY_LABELS,
        SPEC_ALIASES = SPEC_ALIASES,
    }) or nil
    if type(ResolverCore) ~= "table" then return nil end

    local function Scope(scope)
        return (scope == "raid" or scope == "mythicraid") and scope or "party"
    end

    local function Clamp01(value, fallback)
        value = tonumber(value)
        if value == nil then return fallback or 0 end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    local function ColorSame(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        local ar, ag, ab = tonumber(a.r or a[1]) or 0, tonumber(a.g or a[2]) or 0, tonumber(a.b or a[3]) or 0
        local br, bg, bb = tonumber(b.r or b[1]) or 0, tonumber(b.g or b[2]) or 0, tonumber(b.b or b[3]) or 0
        return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
    end

    local function SpellDB(scope)
        local conf = GroupDB(scope)
        if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
        local si = conf.spellIndicators
        if si.spec == nil or si.spec == "" then si.spec = "auto" end
        if type(si.specs) ~= "table" then si.specs = {} end
        if si.layer == nil then si.layer = 9 end
        return si
    end

    local SpellRuntime = ResolverCore.SpellRuntime
    local SpecDisplay = ResolverCore.SpecDisplay
    local ResolveSpec = ResolverCore.ResolveSpec
    local ResolveAura = ResolverCore.ResolveAura

    local BuildSpellIndicatorStateHelpers = Assistant.GroupFramesRegistry and Assistant.GroupFramesRegistry.BuildSpellIndicatorStateHelpers
    local StateCore = type(BuildSpellIndicatorStateHelpers) == "function" and BuildSpellIndicatorStateHelpers({
        GroupDB = GroupDB,
        ApplyGroup = ApplyGroup,
        SpellRuntime = SpellRuntime,
    }) or nil
    if type(StateCore) ~= "table" then return nil end

    local SpellDB = StateCore.SpellDB
    local EnsureSpec = StateCore.EnsureSpec
    local SpellEntry = StateCore.SpellEntry
    local Placed = StateCore.Placed
    local FrameEffect = StateCore.FrameEffect
    local ApplySpell = StateCore.ApplySpell
    local CopyTable = StateCore.CopyTable

    local CustomConfig = SlotCore.CustomConfig
    local ActivateCustom = SlotCore.ActivateCustom
    local ResolveSlot = SlotCore.ResolveSlot
    local AddSlotAliases = SlotCore.AddSlotAliases

    local BuildSpellIndicatorNestedRegistrar = Assistant.GroupFramesRegistry and Assistant.GroupFramesRegistry.BuildSpellIndicatorNestedRegistrar
    local RegisterGroupNested = type(BuildSpellIndicatorNestedRegistrar) == "function" and BuildSpellIndicatorNestedRegistrar({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        ApplyGroup = ApplyGroup,
    }) or nil
    if type(RegisterGroupNested) ~= "function" then return nil end

    return {
        SCOPES = SCOPES,
        SPEC_VALUES = SPEC_VALUES,
        SPEC_DISPLAY_LABELS = SPEC_DISPLAY_LABELS,
        SPEC_ALIASES = SPEC_ALIASES,
        CI_CATEGORY_VALUES = CI_CATEGORY_VALUES,
        CI_MODE_VALUES = CI_MODE_VALUES,
        CI_FILTER_VALUES = CI_FILTER_VALUES,
        CI_CATEGORY_ALIASES = CI_CATEGORY_ALIASES,
        CI_MODE_ALIASES = CI_MODE_ALIASES,
        CI_FILTER_ALIASES = CI_FILTER_ALIASES,
        CI_SLOTS = CI_SLOTS,
        Scope = Scope,
        Clamp01 = Clamp01,
        ColorSame = ColorSame,
        SpellRuntime = SpellRuntime,
        SpellDB = SpellDB,
        SpecDisplay = SpecDisplay,
        ResolveSpec = ResolveSpec,
        ResolveAura = ResolveAura,
        EnsureSpec = EnsureSpec,
        SpellEntry = SpellEntry,
        Placed = Placed,
        FrameEffect = FrameEffect,
        ApplySpell = ApplySpell,
        CopyTable = CopyTable,
        CustomConfig = CustomConfig,
        ActivateCustom = ActivateCustom,
        ResolveSlot = ResolveSlot,
        AddSlotAliases = AddSlotAliases,
        RegisterGroupNested = RegisterGroupNested,
    }
end
