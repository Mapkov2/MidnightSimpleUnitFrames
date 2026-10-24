-- Legacy profile migration helpers, font policy and dispel priority.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local ExportPublic = Parts.ExportPublic
local MSUF_DEFAULTS_SPEC = Parts.MSUF_DEFAULTS_SPEC
local MSUF_Defaults_IsFreshInstallProfileDB = Parts.MSUF_Defaults_IsFreshInstallProfileDB
local StateHelpers = Parts.StateHelpers
local MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = 600
--- Persisted completion marker for the broad default-fill/repair pass below.
--- Bump this whenever MSUF_EnsureDB_Heavy gains a new mandatory default or
--- one-shot repair; current profiles can then be repaired exactly once again.
--- Alias rules and their context differences live in StateHelpers.AliasMigrations.
--- This marker owns broad default filling; the shared alias ledger owns translation.
local MSUF_DEFAULTS_CURRENT_REVISION = 17
local MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = 7

local MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION = 10

--- Root tables are the contract every other module assumes after EnsureDB.
--- Add new top-level SavedVariables buckets here before modules start reading
--- them, then fill nested defaults later in MSUF_EnsureDB_Heavy.
local MSUF_DEFAULTS_ROOT_TABLE_KEYS = {
    "general",
    "classColors",
    "npcColors",
    "bars",
    "gameplay",
    "player",
    "target",
    "targettarget",
    "focustarget",
    "focus",
    "pet",
    "pettarget",
    "boss",
    "arena",
}
local function MSUF_Defaults_EnsureRootTables(profileDB)
    for _, key in ipairs(MSUF_DEFAULTS_ROOT_TABLE_KEYS) do
        if type(profileDB[key]) ~= "table" then
            profileDB[key] = {}
        end
    end
end

--- Migration helpers live above MSUF_EnsureDB_Heavy so the heavy function reads
--- as "ensure roots, migrate old profile shapes, then fill missing defaults".
--- Keep migrations idempotent: EnsureDB can be forced after imports/profile
--- switches and must be safe to run repeatedly on the same profile table.
local MSUF_DEFAULTS_UNIT_DISPEL_KEYS = {
    "unitDispelOverlayEnabled", "unitDispelOverlayStyle", "unitDispelOverlayOnHealth",
    "unitDispelOverlayAlpha", "unitDispelOverlayTrigger",
    "unitDispelSymbolEnabled", "unitDispelSymbolStyle", "unitDispelSymbolMode",
    "unitDispelSymbolTrigger", "unitDispelSymbolSize", "unitDispelSymbolSpacing",
    "unitDispelSymbolGrowth", "unitDispelSymbolAnchor", "unitDispelSymbolX",
    "unitDispelSymbolY", "unitDispelSymbolAlpha", "unitDispelSymbolLayer",
    "unitDispelSymbolStrata",
}

local function MSUF_Defaults_MigrateUnitDispelOwnership(db)
    if type(db) ~= "table" then return end
    local general = type(db.general) == "table" and db.general or {}
    if (tonumber(general.unitDispelOwnershipVersion) or 0) >= 1 then return end
    for _, unitKey in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local conf = type(db[unitKey]) == "table" and db[unitKey] or {}
        db[unitKey] = conf
        local usedUnitBars = conf.hlOverride == true
        for _, key in ipairs(MSUF_DEFAULTS_UNIT_DISPEL_KEYS) do
            -- Snapshot the value the old Bars-scoped compiler actually used.
            -- This deliberately replaces stale unit values hidden behind a
            -- disabled Bars override, preserving appearance during the split.
            local value
            if usedUnitBars then value = conf[key] end
            if value == nil then value = general[key] end
            if value ~= nil then conf[key] = value end
        end
    end
    -- This is intentionally a portable profile field, not a private _msuf key:
    -- exports strip private metadata, and replaying this flattening after an
    -- import would overwrite the independent per-unit choices it just created.
    general.unitDispelOwnershipVersion = 1
end

local MSUF_Defaults_NormalizeFontKey = MSUF.Require("MSUF_NormalizeFontKey", "State/MSUF_Defaults.lua")

local function MSUF_Defaults_NormalizeFontField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_Defaults_NormalizeFontKey(tbl.fontKey)
    local resolved = MSUF.Fonts.ResolveKeyPath(normalized)
    if type(resolved) == "string" and resolved ~= "" then
        normalized = resolved
    end
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

local MSUF_DISPEL_PRIORITY_MIGRATION = 5
--- The migration version that lifted the Beta 38 TOP dispel symbol default to
--- ALL. Data written by that version or a later one keeps a TOP the user chose;
--- the stamp travels with exported profiles as their data-format version.
local MSUF_DISPEL_PRIORITY_TOP_LIFT = 5
local MSUF_DISPEL_TYPE_PRIORITY_KEYS = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
}
local MSUF_PRIORITY_KEY_ALIAS = {
    Dispel = "dispel",
    DISPEL = "dispel",
    Magic = "magic",
    MAGIC = "magic",
    Curse = "curse",
    CURSE = "curse",
    Disease = "disease",
    DISEASE = "disease",
    Poison = "poison",
    POISON = "poison",
    Bleed = "bleed",
    BLEED = "bleed",
    Aggro = "aggro",
    AGGRO = "aggro",
    Purge = "purge",
    PURGE = "purge",
    BossTarget = "bossTarget",
    Boss_Target = "bossTarget",
    ["Boss Target"] = "bossTarget",
    ["boss target"] = "bossTarget",
    boss_target = "bossTarget",
    bosstarget = "bossTarget",
    BOSS_TARGET = "bossTarget",
    Target = "target",
    TARGET = "target",
    Focus = "focus",
    FOCUS = "focus",
}

local function MSUF_Defaults_NormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return MSUF_PRIORITY_KEY_ALIAS[key] or key
end

local function MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    if includeTargetFocus then
        return { "dispel", "aggro", "purge", "bossTarget", "target", "focus" }
    end
    return { "dispel", "aggro", "purge", "bossTarget" }
end

local function MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
    local defaults = MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    local allowed = {}
    for i = 1, #defaults do allowed[defaults[i]] = true end
    local out, used = {}, {}
    if type(raw) == "table" then
        for i = 1, #raw do
            local key = MSUF_Defaults_NormalizePriorityKey(raw[i])
            if MSUF_DISPEL_TYPE_PRIORITY_KEYS[key] then key = "dispel" end
            if allowed[key] and not used[key] then
                out[#out + 1] = key
                used[key] = true
            end
        end
    end
    for i = 1, #defaults do
        local key = defaults[i]
        if not used[key] then
            out[#out + 1] = key
            used[key] = true
        end
    end
    return out
end

local function MSUF_Defaults_MigratePriorityScope(scope, includeTargetFocus, liftTop)
    if type(scope) ~= "table" then return end
    local raw = type(scope.hlPrioOrder) == "table" and scope.hlPrioOrder
        or (type(scope.highlightPrioOrder) == "table" and scope.highlightPrioOrder)
        or nil
    if raw then
        local visual = MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
        scope.hlPrioOrder = visual
        if type(scope.highlightPrioOrder) == "table" then
            scope.highlightPrioOrder = visual
        end
    end

    --- Debuff-type custom sorting was removed from the visible model. Old
    --- profiles are force-collapsed into the single Dispel layer and all old
    --- overlay/type priority switches are disabled so no hidden state survives.
    scope.hlDispelTypePrioEnabled = nil
    scope.hlDispelTypePrioOrder = nil
    scope.unitDispelOverlayPrioEnabled = nil
    scope.unitDispelOverlayPrioOrder = nil
    scope.unitDispelOverlayUseHighlightPriority = nil
    scope.dispelOverlayPrioEnabled = nil
    scope.dispelOverlayPrioOrder = nil
    scope.dispelOverlayUseHighlightPriority = nil

    --- The dispel symbol shipped in Beta 38 defaulting to a single symbol for the
    --- highest-priority debuff. Beta 39 makes "one per dispel type" the default,
    --- because two debuffs of different types have to read as two symbols. TOP was
    --- only ever the default in the one build that had it, so lift existing
    --- profiles once rather than leaving them silently on the old behaviour. Only
    --- data older than the lift gets it (liftTop), so a deliberate TOP survives
    --- later migration versions, profile imports and forced re-runs.
    if liftTop then
        for _, key in ipairs({ "unitDispelSymbolMode", "dispelSymbolMode" }) do
            if tostring(scope[key] or ""):upper() == "TOP" then scope[key] = "ALL" end
        end
    end

    --- PTR 5 replaces the old catch-all debuff choice with the precise native
    --- DISPELLABLE meaning: any aura carrying a dispel type. Preserve old
    --- profiles/imports by translating their former ANY_DEBUFF spelling.
    for _, key in ipairs({ "dispelBorderTrigger", "unitDispelOverlayTrigger", "dispelOverlayTrigger" }) do
        local value = tostring(scope[key] or ""):upper()
        if value == "ANY_DEBUFF" or value == "ALL_DEBUFFS" or value == "DEBUFF" or value == "ANY" then
            scope[key] = "DISPEL_TYPE"
        end
    end
end

local function MSUF_Defaults_MigrateDispelPriorityProfile(db, force)
    if type(db) ~= "table" then return false end
    --- A brand-new profile has nothing to migrate. Stamping it here, before the
    --- heavy pass, made it look used, and first installs and profile resets then
    --- never received the factory profile. The heavy pass runs this migration
    --- again right after seeding, which is when the stamp belongs.
    if MSUF_Defaults_IsFreshInstallProfileDB(db) then return false end
    --- The stamp is the version the data was last migrated to, also when it
    --- arrives inside an imported profile. A forced run (imports) still repeats
    --- every idempotent normalization below.
    local version = tonumber(db._msufDispelPriorityMigration) or 0
    if force ~= true and version == MSUF_DISPEL_PRIORITY_MIGRATION then
        return false
    end
    local liftTop = version < MSUF_DISPEL_PRIORITY_TOP_LIFT
    MSUF_Defaults_MigratePriorityScope(db.general, true, liftTop)
    for _, key in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], false, liftTop)
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], true, liftTop)
    end
    db._msufDispelPriorityMigration = MSUF_DISPEL_PRIORITY_MIGRATION
    return true
end

local function MSUF_Defaults_MigrateDispelPriorityProfiles()
    local changed = false
    if type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_MigrateDispelPriorityProfile(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_MigrateDispelPriorityProfile(MSUF_DB) or changed
    end
    return changed
end

ExportPublic("MSUF_MigrateDispelPriorityProfile", MSUF_Defaults_MigrateDispelPriorityProfile)
ExportPublic("MSUF_MigrateDispelPriorityProfiles", MSUF_Defaults_MigrateDispelPriorityProfiles)

local function MSUF_ResolveFontShadowMetrics(opacity, distance, legacyStrength, fallbackOpacity, fallbackDistance)
    if legacyStrength ~= nil then
        legacyStrength = tostring(legacyStrength):upper()
        opacity = legacyStrength == "SOFT" and 0.55 or 1
        distance = legacyStrength == "DEEP" and 2 or 1
    else
        opacity = tonumber(opacity)
        if opacity == nil then opacity = tonumber(fallbackOpacity) or 1 end
        distance = tonumber(distance)
        if distance == nil then distance = tonumber(fallbackDistance) or 1 end
    end
    if opacity < 0.20 then opacity = 0.20 elseif opacity > 1 then opacity = 1 end
    distance = math.floor(distance + 0.5)
    if distance <= 1 then distance = 1 else distance = 2 end
    return opacity, distance, -distance
end
ExportPublic("MSUF_ResolveFontShadowMetrics", MSUF_ResolveFontShadowMetrics)

local function MSUF_Defaults_NormalizeFontShadowScope(scope, populateDefaults)
    if type(scope) ~= "table" then return end
    if scope.fontShadowStrength ~= nil then
        scope.fontShadowOpacity, scope.fontShadowDistance =
            MSUF_ResolveFontShadowMetrics(nil, nil, scope.fontShadowStrength)
        scope.fontShadowStrength = nil
        return
    end
    if populateDefaults or scope.fontShadowOpacity ~= nil or scope.fontShadowDistance ~= nil then
        scope.fontShadowOpacity, scope.fontShadowDistance = MSUF_ResolveFontShadowMetrics(
            scope.fontShadowOpacity, scope.fontShadowDistance)
    end
end

local function MSUF_Defaults_ClearScopedFontKeys(profileDB)
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        local scope = profileDB and profileDB[key]
        if type(scope) == "table" then
            scope.fontKey = nil
            scope.nameShortenOverride = nil
            scope._msufGFNameTruncationOverride = nil
            if scope.fontOverride == true and not StateHelpers.HasScopedFontOverrideValue(scope, MSUF_DEFAULTS_SPEC) then
                scope.fontOverride = false
            end
        end
    end
end

--- Ordered migration/seed stages of MSUF_EnsureDB_Heavy. Each stage is one
--- contiguous slice of the former single-body pass, called in exactly the
--- original order with the original arguments; `g` is MSUF_DB.general. Stages
--- that read state computed in the prologue receive it explicitly. Keep new
--- one-shot repairs inside the stage that owns the keys they touch.

--- Anchor, UI scale, Flash menu, minimap, integrations, dropdown style,
--- sounds, text colour toggles, navigation icons, menu font, edit mode.

Parts.MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
Parts.MSUF_DEFAULTS_CURRENT_REVISION = MSUF_DEFAULTS_CURRENT_REVISION
Parts.MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION
Parts.MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION = MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION
Parts.MSUF_DEFAULTS_ROOT_TABLE_KEYS = MSUF_DEFAULTS_ROOT_TABLE_KEYS
Parts.MSUF_Defaults_ClearScopedFontKeys = MSUF_Defaults_ClearScopedFontKeys
Parts.MSUF_Defaults_EnsureRootTables = MSUF_Defaults_EnsureRootTables
Parts.MSUF_Defaults_MigrateDispelPriorityProfile = MSUF_Defaults_MigrateDispelPriorityProfile
Parts.MSUF_Defaults_MigrateUnitDispelOwnership = MSUF_Defaults_MigrateUnitDispelOwnership
Parts.MSUF_Defaults_NormalizeFontField = MSUF_Defaults_NormalizeFontField
Parts.MSUF_Defaults_NormalizeFontShadowScope = MSUF_Defaults_NormalizeFontShadowScope
