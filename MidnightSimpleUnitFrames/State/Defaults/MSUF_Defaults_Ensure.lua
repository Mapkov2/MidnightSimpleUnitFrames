-- Defaults normalization ledger, cached EnsureDB and read API.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local ExportPublic = Parts.ExportPublic
local IS_CLASSIC_FAMILY = Parts.IS_CLASSIC_FAMILY
local MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = Parts.MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
local MSUF_DEFAULTS_CURRENT_REVISION = Parts.MSUF_DEFAULTS_CURRENT_REVISION
local MSUF_DEFAULTS_ROOT_TABLE_KEYS = Parts.MSUF_DEFAULTS_ROOT_TABLE_KEYS
local MSUF_DEFAULTS_SPEC = Parts.MSUF_DEFAULTS_SPEC
local MSUF_Defaults_ClearScopedFontKeys = Parts.MSUF_Defaults_ClearScopedFontKeys
local MSUF_Defaults_CreateFactoryProfile = Parts.MSUF_Defaults_CreateFactoryProfile
local MSUF_Defaults_EnsureRootTables = Parts.MSUF_Defaults_EnsureRootTables
local MSUF_Defaults_GetEffectiveLocale = Parts.MSUF_Defaults_GetEffectiveLocale
local MSUF_Defaults_GetGlobalFontDefault = Parts.MSUF_Defaults_GetGlobalFontDefault
local MSUF_Defaults_IsFreshInstallProfileDB = Parts.MSUF_Defaults_IsFreshInstallProfileDB
local MSUF_Defaults_MigrateDispelPriorityProfile = Parts.MSUF_Defaults_MigrateDispelPriorityProfile
local MSUF_Defaults_MuteForeverHealth = Parts.MSUF_Defaults_MuteForeverHealth
local MSUF_Defaults_NormalizeFontField = Parts.MSUF_Defaults_NormalizeFontField
local MSUF_Defaults_NormalizePortraitRenderDB = Parts.MSUF_Defaults_NormalizePortraitRenderDB
local MSUF_Defaults_NormalizeProfileTo60Defaults = Parts.MSUF_Defaults_NormalizeProfileTo60Defaults
local MSUF_Defaults_PruneRetiredClassPowerTextFields = Parts.MSUF_Defaults_PruneRetiredClassPowerTextFields
local MSUF_Defaults_RepairFactoryNameShortening = Parts.MSUF_Defaults_RepairFactoryNameShortening
local MSUF_Defaults_RepairModernFactoryNamePresentation = Parts.MSUF_Defaults_RepairModernFactoryNamePresentation
local MSUF_Defaults_RepairModernFactoryPlayerStack = Parts.MSUF_Defaults_RepairModernFactoryPlayerStack
local MSUF_Defaults_RepairSparseFactoryAuraOwners = Parts.MSUF_Defaults_RepairSparseFactoryAuraOwners
local MSUF_Defaults_Stage_FillUnitDefaults = Parts.MSUF_Defaults_Stage_FillUnitDefaults
local MSUF_Defaults_Stage_MigrateUnifiedAlpha = Parts.MSUF_Defaults_Stage_MigrateUnifiedAlpha
local MSUF_Defaults_Stage_MigrateUnitTextModes = Parts.MSUF_Defaults_Stage_MigrateUnitTextModes
local MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes = Parts.MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes
local MSUF_Defaults_Stage_SeedAuraDefaults = Parts.MSUF_Defaults_Stage_SeedAuraDefaults
local MSUF_Defaults_Stage_SeedBarColorDefaults = Parts.MSUF_Defaults_Stage_SeedBarColorDefaults
local MSUF_Defaults_Stage_SeedBarTextureDefaults = Parts.MSUF_Defaults_Stage_SeedBarTextureDefaults
local MSUF_Defaults_Stage_SeedBarsTableDefaults = Parts.MSUF_Defaults_Stage_SeedBarsTableDefaults
local MSUF_Defaults_Stage_SeedCastbarCoreDefaults = Parts.MSUF_Defaults_Stage_SeedCastbarCoreDefaults
local MSUF_Defaults_Stage_SeedCastbarDetailDefaults = Parts.MSUF_Defaults_Stage_SeedCastbarDetailDefaults
local MSUF_Defaults_Stage_SeedFontDefaults = Parts.MSUF_Defaults_Stage_SeedFontDefaults
local MSUF_Defaults_Stage_SeedGameplayDefaults = Parts.MSUF_Defaults_Stage_SeedGameplayDefaults
local MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults = Parts.MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults
local MSUF_Defaults_Stage_SeedPortraitBaselineDefaults = Parts.MSUF_Defaults_Stage_SeedPortraitBaselineDefaults
local MSUF_Defaults_Stage_SeedPredictionDefaults = Parts.MSUF_Defaults_Stage_SeedPredictionDefaults
local MSUF_Defaults_Stage_SeedShellDefaults = Parts.MSUF_Defaults_Stage_SeedShellDefaults
local MSUF_Defaults_Stage_SeedStatusIndicatorDefaults = Parts.MSUF_Defaults_Stage_SeedStatusIndicatorDefaults
local MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall = Parts.MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall
local StateHelpers = Parts.StateHelpers
local MSUF_DB_LastHeavyRun
-- State schema is independent of the schema-600 wire/storage contract read by 6.50.
-- Factory seeding must precede this ledger: a stamp is saved data, never bootstrap.
MSUF.ProfileMigrations = (function()
    local Migrations = { Schema = 700 }
    local groups = { "gf_party", "gf_raid", "gf_mythicraid" }
    local units = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
    local barNames = { ["MSUF Flat"] = "Solid" }
    for _, suffix in ipairs({ "Charcoal", "Minimalist", "Slickrock", "Smooth", "Smooth v2", "Smoother" }) do
        barNames["Midnight " .. suffix] = "MSUF " .. suffix
    end
    function Migrations.RepairBarNames(profile)
        local g = type(profile) == "table" and profile.general
        if type(g) ~= "table" then return false end
        local changed = false
        for _, key in ipairs({ "barTexture", "castbarTexture" }) do
            local value = g[key]
            if type(value) == "string" and barNames[value] then
                g[key] = barNames[value]
                changed = true
            end
        end
        return changed
    end
    local Fill = MSUF.DefaultsSchema.Fill
    -- These values materialize the existing runtime fallbacks, without replaying
    -- the broader defaults stages against a persisted revision-17 profile.
    local dragon = MSUF.DefaultsSchema.Values.PortraitDragon
    local gcd = MSUF.DefaultsSchema.Values.GCD
    local trinket = MSUF.DefaultsSchema.Values.ArenaTrinket
    local happiness = MSUF.DefaultsSchema.Values.PetHappiness
    local function SeedAdditions(profile)
        Fill(profile.general, gcd)
        Fill(profile.arena, trinket)
        for _, key in ipairs(units) do Fill(profile[key], dragon) end
        if MSUF.Client.SupportsPetHappiness == true then Fill(profile.pet, happiness) end
    end
    local function StripGroupTooltips(profile)
        for _, key in ipairs(groups) do
            local scope = profile[key]
            if type(scope) == "table" then
                scope.tooltipMode = nil
                scope.tooltipModifier = nil
            end
        end
    end
    function Migrations.SeedGroupBuffStrata(scope)
        local auras = type(scope) == "table" and scope.auras
        local buff = type(auras) == "table" and auras.buff
        if type(buff) == "table" and buff.trackedStrata == nil then
            local indicators = type(scope.spellIndicators) == "table" and scope.spellIndicators
            buff.trackedStrata = buff.trackedFrameStrata or (indicators and indicators.strata) or "AUTO"
        end
    end
    local function SeedTrackedStrata(profile)
        for _, key in ipairs(groups) do Migrations.SeedGroupBuffStrata(profile[key]) end
    end
    -- Ordered ledger. Existing versioned repairs retain their own data-format
    -- decisions; the final stamp only records completion of these cold steps.
    Migrations.Ledger = {
        { revision = 700, replay = true, name = "legacy_bar_names", apply = Migrations.RepairBarNames },
        { revision = 700, replay = true, name = "dispel_priority", apply = MSUF_Defaults_MigrateDispelPriorityProfile },
        { revision = 700, replay = true, name = "classic_sparse_aura_owners", apply = function(profile)
            if IS_CLASSIC_FAMILY then MSUF_Defaults_RepairSparseFactoryAuraOwners(profile) end
        end },
        { revision = 700, name = "retired_group_tooltips", apply = StripGroupTooltips },
        { revision = 700, replay = true, name = "revision_17_additions", apply = SeedAdditions },
        { revision = 700, replay = true, name = "group_buff_strata", apply = SeedTrackedStrata },
        { revision = 700, replay = true, name = "sparse_persistence_defaults", apply = MSUF.DefaultsSchema.FillMenuDefaults },
    }
    function Migrations.Apply(profile, skipMedia)
        if type(profile) ~= "table" or MSUF.DefaultsSchema.IsQuarantinedProfile(profile)
            or MSUF_Defaults_IsFreshInstallProfileDB(profile) then return profile end
        local revision = tonumber(profile._msufStateSchema) or 0
        for _, step in ipairs(Migrations.Ledger) do
            if (not (revision >= step.revision) or step.replay == true)
                and (step.name ~= "legacy_bar_names" or skipMedia ~= true) then
                step.apply(profile)
            end
        end
        if not (revision >= Migrations.Schema) then profile._msufStateSchema = Migrations.Schema end
        return profile
    end

    function Migrations.CompleteImportedGroupFontOwnership(profile)
        -- Group repair may create owners after the defaults translator ran.
        -- Finish only its font ownership decision, previously made by the
        -- second heavy pass; do not replay broad normalization on commit.
        for _, key in ipairs(groups) do
            local scope = profile[key]
            if type(scope) == "table" then
                if scope.fontOverride == nil and StateHelpers.HasScopedFontOverrideValue(scope, StateHelpers.ProfileIOSpec) then
                    scope.fontOverride = true
                end
                if scope.fontOverride == true and not StateHelpers.HasScopedFontOverrideValue(scope, MSUF_DEFAULTS_SPEC) then
                    scope.fontOverride = false
                end
            end
        end
    end
    function Migrations.ApplyStoredProfiles(profiles)
        -- Inactive/donor media names retain their stored value until activation.
        for _, profile in pairs(profiles) do Migrations.Apply(profile, true) end
    end
    return Migrations
end)()

--- Main DB repair pass. This is deliberately broad and cold: it may normalize
--- several systems in one run, but it is protected by MSUF_DB_LastHeavyRun in
--- the public wrapper below so normal callers do not pay for it repeatedly.
local function MSUF_EnsureDB_Heavy(profileDB)
    if type(profileDB) ~= "table" then
        profileDB = {}
    end
    --- Seed brand-new installs / hard-resets from the factory profile payload.
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall(profileDB)
    MSUF_Defaults_EnsureRootTables(profileDB)
    local g = profileDB.general
    MSUF_Defaults_RepairFactoryNameShortening(profileDB)
    MSUF_Defaults_RepairModernFactoryPlayerStack(profileDB)
    MSUF_Defaults_RepairModernFactoryNamePresentation(profileDB)
    MSUF_Defaults_MigrateDispelPriorityProfile(profileDB)
    MSUF_Defaults_NormalizePortraitRenderDB(profileDB)
    local nativeDispelMigration = tonumber(profileDB._msufNativeDispelTriggerMigration) or 0
    if nativeDispelMigration < 1 then
        if g.dispelBorderTrigger == nil or g.dispelBorderTrigger == "BY_ME" then
            g.dispelBorderTrigger = "DISPEL_TYPE"
        end
    end
    profileDB._msufNativeDispelTriggerMigration = 2
    local legacyPortraitOverrideState = false
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
        local u = profileDB[unitKey]
        if type(u) == "table" and u.portraitDecoOverride ~= nil then
            legacyPortraitOverrideState = true
            break
        end
    end
    if type(profileDB.classColors) ~= "table" then profileDB.classColors = {} end
    if type(profileDB.npcColors) ~= "table" then profileDB.npcColors = {} end
    if g.fontKey == nil then
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
    end
    MSUF_Defaults_NormalizeFontField(g)
    MSUF_Defaults_Stage_SeedShellDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedBarColorDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedFontDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedCastbarCoreDefaults(profileDB, g)
    MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes(g)
    MSUF_Defaults_Stage_SeedCastbarDetailDefaults(g)
    MSUF_Defaults_Stage_SeedBarTextureDefaults(g)
    MSUF_Defaults_Stage_SeedPortraitBaselineDefaults(profileDB, g)
    MSUF_Defaults_Stage_MigrateUnitTextModes(profileDB, g)
    MSUF_Defaults_Stage_SeedPredictionDefaults(g)
    MSUF_Defaults_Stage_SeedStatusIndicatorDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedBarsTableDefaults(profileDB)
    MSUF_Defaults_Stage_SeedGameplayDefaults(profileDB)
    --- 5.6 -> 6.0 shape repair for existing DBs and factory defaults.
    MSUF_Defaults_NormalizeProfileTo60Defaults(profileDB)
    --- Root toggle: Shorten unit names (Frames -> General)
    MSUF.DefaultsSchema.Fill(profileDB, MSUF.DefaultsSchema.Values.CoreShortenNames)
    MSUF_Defaults_Stage_SeedAuraDefaults(profileDB)
    MSUF_Defaults_Stage_FillUnitDefaults(profileDB, g, legacyPortraitOverrideState)
    MSUF_Defaults_Stage_MigrateUnifiedAlpha(profileDB, g)
    MSUF_Defaults_MuteForeverHealth(profileDB, false)
    for _, key in ipairs({
        "general",
        "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        MSUF_Defaults_NormalizeFontField(profileDB[key])
    end
    MSUF_Defaults_ClearScopedFontKeys(profileDB)
    if g._msufUFLocalFontKeyMigration_v407 ~= true then
        for _, key in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
            local u = profileDB[key]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
        g._msufUFLocalFontKeyMigration_v407 = true
    end
    profileDB._msufProfileSchema = MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
    profileDB._msufDefaultsRevision = MSUF_DEFAULTS_CURRENT_REVISION
    MSUF.ProfileMigrations.Apply(profileDB)
    return profileDB
end

local function MSUF_Defaults_IsCurrentProfileDB(db)
    if type(db) ~= "table"
        or tonumber(db._msufProfileSchema) ~= MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
        or tonumber(db._msufDefaultsRevision) ~= MSUF_DEFAULTS_CURRENT_REVISION then
        return false
    end
    --- Keep the fast path safe for truncated/malformed SavedVariables. Nested
    --- value validation belongs to imports (which force EnsureDB), while these
    --- root tables are the minimum runtime contract for a stored profile.
    for i = 1, #MSUF_DEFAULTS_ROOT_TABLE_KEYS do
        if type(db[MSUF_DEFAULTS_ROOT_TABLE_KEYS[i]]) ~= "table" then
            return false
        end
    end
    --- A stamped profile saved by an import that failed half way can still
    --- carry a scalar aura root or owner; the heavy pass repairs both.
    local auras = db.auras3
    if type(auras) ~= "table" then return false end
    if type(auras.perUnit) == "table" then
        for _, owner in pairs(auras.perUnit) do
            if type(owner) ~= "table" then return false end
        end
    end
    local g = db.general
    if type(g.fontKey) ~= "string" or g.fontKey == ""
        or db.shortenNames == nil
        or db.bars.barBackgroundAlpha == nil
        or db.gameplay.enableCombatTimer == nil
        or (g.barBgFillMode ~= "full" and g.barBgFillMode ~= "missing")
        or (g.barBgColorMode ~= "custom" and g.barBgColorMode ~= "match_health"
            and g.barBgColorMode ~= "class" and g.barBgColorMode ~= "health_gradient") then
        return false
    end
    return true
end

--- Cheap public guard used by the rest of the addon. Pass force=true only after
--- changing profile tables or importing data, when the full repair/migration
--- pass must be allowed to run again on the active MSUF_DB reference.
--- allowPersistedFastPath is intentionally reserved for profile initialization
--- and private export copies. Normal profile switches retain the old behavior
--- of repairing the newly selected table even when its revision is current.
--- A private copy (export, import candidate) goes through
--- MSUF_NormalizeProfileDefaults, which never touches that session cache.
MSUF.DefaultsSchema.IsCurrentProfile = MSUF_Defaults_IsCurrentProfileDB
local function MSUF_NormalizeProfileDefaults(profile, force, allowPersistedFastPath)
    assert(type(profile) == "table", "MSUF profile must be a table")
    local _, status = MSUF.DefaultsSchema.RestorePersistence(profile)
    if status == "rejected" then return MSUF.DefaultsSchema.QuarantineProfile(profile) end
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall(profile)
    MSUF.ProfileMigrations.Apply(profile)
    MSUF_Defaults_PruneRetiredClassPowerTextFields(profile)
    if force ~= true and allowPersistedFastPath == true and MSUF_Defaults_IsCurrentProfileDB(profile) then
        return profile
    end
    return MSUF_EnsureDB_Heavy(profile)
end
ExportPublic("MSUF_NormalizeProfileDefaults", MSUF_NormalizeProfileDefaults)
function MSUF.DefaultsSchema.BuildRecoveryDefaults()
    return MSUF_NormalizeProfileDefaults({}, true)
end

local function MSUF_EnsureDB(force, allowPersistedFastPath)
    local profile = MSUF_DB
    if type(profile) ~= "table" then
        profile = {}
        ExportPublic("MSUF_DB", profile)
        -- A file that reads settings while the addon loads gets here before the
        -- SavedVariables exist; State/MSUF_FirstLoad.lua must not count this
        -- table as saved data on ADDON_LOADED.
        MSUF.ProfilePolicy.NoteSessionProfileDB(profile)
    end
    if force ~= true and MSUF_DB_LastHeavyRun == profile then return profile end
    local normalized = MSUF_NormalizeProfileDefaults(profile, force, allowPersistedFastPath)
    if normalized ~= profile then
        profile = normalized
        ExportPublic("MSUF_DB", profile)
    end
    MSUF_DB_LastHeavyRun = profile
    return profile
end
function MSUF.ProfileMigrations.PrepareBinding(profile)
    return MSUF_NormalizeProfileDefaults(profile, false, true)
end
function MSUF.ProfileMigrations.AdoptNormalizedProfile(profile)
    assert(type(profile) == "table", "MSUF staged profile must be a table")
    MSUF.DefaultsSchema.ReleaseQuarantinedProfile(profile)
    MSUF_DB_LastHeavyRun = profile
end
ExportPublic("MSUF_EnsureDB", MSUF_EnsureDB)
--- Optional exports for other modules
MSUF.MSUF_CreateFactoryDefaultProfile = MSUF_Defaults_CreateFactoryProfile

do
    local factory, factoryLocale
    MSUF.Defaults = {}
    -- Scope is a root profile owner ("general", "bars", "player", ...).
    -- nil scope reads root keys. Table results are independent copies.
    function MSUF.Defaults.Get(scope, key)
        local schema = MSUF.DefaultsSchema
        local read = schema.ReadDefaults[scope]
        if read == nil and schema.Values.UnitFrames[scope] then read = schema.ReadDefaults.unit end
        if read and read[key] ~= nil then return read[key] end
        if scope == "bars" then
            local extra = MSUF.CPBuilders.ExtraAuraDefaults[key]
            if extra ~= nil then
                if type(extra) == "table" then return schema.Fill({}, extra) end
                return extra
            end
        end
        local locale = MSUF_Defaults_GetEffectiveLocale()
        if factory == nil or factoryLocale ~= locale then
            factory = MSUF_Defaults_CreateFactoryProfile() or {}
            MSUF_NormalizeProfileDefaults(factory, true)
            factoryLocale = locale
        end
        local owner = factory
        if scope ~= nil then owner = factory[scope] end
        if type(owner) ~= "table" then return nil end
        local value = owner[key]
        if type(value) == "table" then return MSUF.DefaultsSchema.Fill({}, value) end
        return value
    end
end

MSUF.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
MSUF.MSUF_EnsureDB = MSUF_EnsureDB
MSUF.EnsureDB = MSUF_EnsureDB
ExportPublic("MSUF_CreateFactoryDefaultProfile", MSUF_Defaults_CreateFactoryProfile)


-- Complete forward bindings once; gameplay closures keep direct local calls.
Parts.Bind0()
MSUF.DefaultsParts = nil
