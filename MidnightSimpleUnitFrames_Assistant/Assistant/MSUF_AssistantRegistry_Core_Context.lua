-- Assistant registry core context installer.
-- Keeps the shared context export table out of the core bootstrap.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.InstallRegistryCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local CoreData = ctx.CoreData or {}
    local DB = ctx.DBHelpers or {}
    local Apply = ctx.ApplyHelpers or {}
    local UnitAura = ctx.UnitAuraHelpers or {}
    local GroupAura = ctx.GroupAuraHelpers or {}

    local registryCore = {
        M = ctx.M,
        A = ctx.A,
        Registry = ctx.Registry,
        UNIT_LABELS = CoreData.UNIT_LABELS,
        UNIT_ALIASES = CoreData.UNIT_ALIASES,
        floor = math.floor,
        EnsureDB = DB.EnsureDB,
        UnitDB = DB.UnitDB,
        GeneralDB = DB.GeneralDB,
        BarsDB = DB.BarsDB,
        GameplayDB = DB.GameplayDB,
        GroupDB = DB.GroupDB,
        ClampNumber = DB.ClampNumber,
        CallGlobal = DB.CallGlobal,
        ApplyUnit = Apply.ApplyUnit,
        ApplyGeneral = Apply.ApplyGeneral,
        ApplyVisuals = Apply.ApplyVisuals,
        ApplyColors = Apply.ApplyColors,
        ApplyCastbarColors = Apply.ApplyCastbarColors,
        ApplyGameplayColors = Apply.ApplyGameplayColors,
        ApplyClassPowerColors = Apply.ApplyClassPowerColors,
        ApplyAuraColors = Apply.ApplyAuraColors,
        ApplyPortraitColors = Apply.ApplyPortraitColors,
        ApplyFonts = Apply.ApplyFonts,
        ApplyBars = Apply.ApplyBars,
        ApplyBarGradients = Apply.ApplyBarGradients,
        ApplyBarOutline = Apply.ApplyBarOutline,
        ApplyRoundedBars = Apply.ApplyRoundedBars,
        ApplyAggroBorder = Apply.ApplyAggroBorder,
        ApplyDispelPurgeBorder = Apply.ApplyDispelPurgeBorder,
        ApplyBossTargetBorder = Apply.ApplyBossTargetBorder,
        ApplyHighlightBorders = Apply.ApplyHighlightBorders,
        ApplyAbsorbBars = Apply.ApplyAbsorbBars,
        ApplyClassPower = Apply.ApplyClassPower,
        ApplyDetachedPowerBar = Apply.ApplyDetachedPowerBar,
        ApplyDetachedPowerBarOutline = Apply.ApplyDetachedPowerBarOutline,
        ApplyGameplay = Apply.ApplyGameplay,
        ApplyCastbar = Apply.ApplyCastbar,
        ApplyGroup = Apply.ApplyGroup,
        AuraModel = Apply.AuraModel,
        ApplyAura = Apply.ApplyAura,
        ApplyAuraText = Apply.ApplyAuraText,
        EnsureAuraFallbackDB = Apply.EnsureAuraFallbackDB,
        AURA_UNIT_FLAGS = CoreData.AURA_UNIT_FLAGS,
        AuraRuntimeUnit = UnitAura.AuraRuntimeUnit,
        AuraUnitEnabled = UnitAura.AuraUnitEnabled,
        SetAuraUnitEnabled = UnitAura.SetAuraUnitEnabled,
        AuraLaneMaxKey = UnitAura.AuraLaneMaxKey,
        AuraLaneSizeKey = UnitAura.AuraLaneSizeKey,
        AuraLaneXKey = UnitAura.AuraLaneXKey,
        AuraLaneYKey = UnitAura.AuraLaneYKey,
        AuraLaneDefaultMax = UnitAura.AuraLaneDefaultMax,
        AuraLaneDefaultY = UnitAura.AuraLaneDefaultY,
        AuraReadNumber = UnitAura.AuraReadNumber,
        AuraWriteNumber = UnitAura.AuraWriteNumber,
        AuraReadLanePerRow = UnitAura.AuraReadLanePerRow,
        AuraWriteLanePerRow = UnitAura.AuraWriteLanePerRow,
        AuraReadLaneGrowth = UnitAura.AuraReadLaneGrowth,
        AuraWriteLaneGrowth = UnitAura.AuraWriteLaneGrowth,
        AuraReadStackAnchor = UnitAura.AuraReadStackAnchor,
        AuraWriteStackAnchor = UnitAura.AuraWriteStackAnchor,
        AuraReadCooldownAnchor = UnitAura.AuraReadCooldownAnchor,
        AuraWriteCooldownAnchor = UnitAura.AuraWriteCooldownAnchor,
        AuraLaneShown = UnitAura.AuraLaneShown,
        SetAuraLaneShown = UnitAura.SetAuraLaneShown,
        AuraFiltersEnabled = UnitAura.AuraFiltersEnabled,
        AuraSetFiltersEnabled = UnitAura.AuraSetFiltersEnabled,
        AuraReadFilter = UnitAura.AuraReadFilter,
        AuraWriteFilter = UnitAura.AuraWriteFilter,
        GFAurasRoot = GroupAura.GFAurasRoot,
        GFAuraGroup = GroupAura.GFAuraGroup,
        GFAuraLaneShown = GroupAura.GFAuraLaneShown,
        SetGFAuraLaneShown = GroupAura.SetGFAuraLaneShown,
        GFReadAuraNumber = GroupAura.GFReadAuraNumber,
        GFWriteAuraNumber = GroupAura.GFWriteAuraNumber,
        GFReadAuraValue = GroupAura.GFReadAuraValue,
        GFWriteAuraValue = GroupAura.GFWriteAuraValue,
        GFReadConfValue = GroupAura.GFReadConfValue,
        GFWriteConfValue = GroupAura.GFWriteConfValue,
        UnitDefaultPower = ctx.UnitDefaultPower,
        GLOBAL_SCOPE_ORDER = CoreData.GLOBAL_SCOPE_ORDER,
        GLOBAL_SCOPE_META = CoreData.GLOBAL_SCOPE_META,
    }

    A.RegistryCore = registryCore
    return registryCore
end
