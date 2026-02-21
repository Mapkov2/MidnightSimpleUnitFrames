-- MSUF_A2_Filters.lua
-- Phase F: Centralize Auras2 filter normalization + runtime resolution.
-- Goal: keep Render orchestration-only and avoid duplicated, drift-prone filter logic.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- Locals (used in this file)
local type = type

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Filters = (type(API.Filters) == "table") and API.Filters or {}
local Filters = API.Filters

local function Default(t, key, value)
    if type(t) ~= "table" then return end
    if t[key] == nil then t[key] = value end
end

-- Normalize a filter config table to the expected schema.
-- sharedSettings is used only for one-time migration from legacy toggles.
function Filters.NormalizeFilters(f, sharedSettings, migrateFlagKey)
    if type(f) ~= "table" then return end

    Default(f, "enabled", true)
    f.buffs = (type(f.buffs) == "table") and f.buffs or {}
    f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
    local b, d = f.buffs, f.debuffs

    -- One-time migration from legacy shared toggles (Options compatibility).
    if migrateFlagKey and not f[migrateFlagKey] and type(sharedSettings) == "table" then
        if f.hidePermanent == nil then f.hidePermanent = (sharedSettings.hidePermanent == true) end
        if b.onlyMine == nil then b.onlyMine = (sharedSettings.onlyMyBuffs == true) end
        if d.onlyMine == nil then d.onlyMine = (sharedSettings.onlyMyDebuffs == true) end
        f[migrateFlagKey] = true
    end

    -- IMPORTANT split toggle migration (v1):
    -- Legacy config used f.onlyImportantAuras (single toggle) to force both buffs+debuffs to IMPORTANT.
    -- New config uses per-type toggles: f.buffs.onlyImportant and f.debuffs.onlyImportant.
    if not f._msufA2_onlyImportantSplitMigrated_v1 then
        if f.onlyImportantAuras == true then
            if b.onlyImportant == nil then b.onlyImportant = true end
            if d.onlyImportant == nil then d.onlyImportant = true end
            -- Deprecate legacy master flag so users can independently toggle buffs/debuffs.
            f.onlyImportantAuras = false
        end
        f._msufA2_onlyImportantSplitMigrated_v1 = true
    end

    Default(f, "hidePermanent", false)
    Default(b, "onlyMine", false)
    Default(b, "includeBoss", false)
    Default(b, "onlyImportant", false)
    Default(d, "onlyMine", false)
    Default(d, "includeBoss", false)
    Default(d, "onlyImportant", false)
    Default(f, "onlyBossAuras", false)
    Default(f, "onlyImportantAuras", false)
    Default(f, "onlyRaidInCombatAuras", false)
    -- Aura sort order (passed to C_UnitAuras.GetAuraSlots).
    -- 0=Unsorted (default/legacy), 1=Default, 2=BigDefensive, 3=Expiration,
    -- 4=ExpirationOnly, 5=Name, 6=NameOnly.
    Default(f, "sortOrder", 0)
    -- When true, reverses the C API sort order in Lua (e.g. Z→A instead of A→Z).
    Default(f, "sortReverse", false)
end

-- Ensure shared.filters exists, migrate legacy storage if needed, and keep legacy shared flags in sync.
-- This is called from Render.EnsureDB() after shared defaults are applied.
function Filters.EnsureSharedFilters(a2, shared)
    if type(a2) ~= "table" or type(shared) ~= "table" then return nil end

    -- Shared filter config: migrate older storage from perUnit.target.filters if needed.
    if type(shared.filters) ~= "table" then
        local migrated = (type(a2.perUnit) == "table" and type(a2.perUnit.target) == "table") and a2.perUnit.target.filters or nil
        shared.filters = (type(migrated) == "table") and migrated or {}
        if migrated then shared.filters._msufA2_sharedFiltersMigratedFromTarget = true end
    end

    local sf = shared.filters
    if type(sf) ~= "table" then
        sf = {}
        shared.filters = sf
    end

    Filters.NormalizeFilters(sf, shared, "_msufA2_sharedFiltersMigrated_v1")

    -- Compatibility: some Options builds still toggle shared.hidePermanent directly.
    -- Mirror that value into shared.filters.hidePermanent so the runtime filter respects the UI.
    if shared.hidePermanent ~= nil and sf.hidePermanent ~= shared.hidePermanent then
        sf.hidePermanent = (shared.hidePermanent == true)
    end

    -- Keep legacy shared flags synced (derived from shared.filters)
    shared.onlyMyBuffs = (sf.buffs and sf.buffs.onlyMine == true) or false
    shared.onlyMyDebuffs = (sf.debuffs and sf.debuffs.onlyMine == true) or false
    shared.hidePermanent = (sf.hidePermanent == true)

    return sf
end

-- Resolve which filter table to use for a unit.
-- Default: shared.filters. If per-unit overrideFilters is enabled, use that unit's filters table.
-- Lazy-normalizes per-unit tables on first access (defensive against manual DB edits).
function Filters.GetEffectiveFilterTable(a2, shared, unitKey)
    if type(shared) ~= "table" then return nil end
    local tf = shared.filters

    if type(a2) == "table" and type(a2.perUnit) == "table" and unitKey ~= nil then
        local pu = a2.perUnit
        local u = pu and pu[unitKey]
        if type(u) == "table" and u.overrideFilters == true then
            local puf = u.filters
            if puf ~= nil then
                -- Lazy normalize: ensure schema is complete (one-time per profile load)
                if not puf._msufA2_normalizedRuntime then
                    Filters.NormalizeFilters(puf)
                    puf._msufA2_normalizedRuntime = true
                end
                tf = puf
            end
        end
    end

    return tf
end

-- Compute runtime flags used by Model/Render loops.
-- Returns:
--   tf, masterOn,
--   onlyBossAuras,
--   onlyImportantBuffs, onlyImportantDebuffs,
--   buffsOnlyMine, debuffsOnlyMine,
--   buffsIncludeBoss, debuffsIncludeBoss,
--   hidePermanentBuffs,
--   sortOrder, sortReverse
function Filters.ResolveRuntimeFlags(a2, shared, unitKey)
    local tf = Filters.GetEffectiveFilterTable(a2, shared, unitKey)

    local masterOn = (tf and tf.enabled == true) and true or false
    local onlyBossAuras = (masterOn and tf and tf.onlyBossAuras == true) and true or false

    -- Legacy (deprecated): a single toggle that forced BOTH buffs+debuffs to IMPORTANT.
    local legacyOnlyImportant = (masterOn and tf and tf.onlyImportantAuras == true) and true or false

    local onlyImportantBuffs, onlyImportantDebuffs = false, false

    local buffsOnlyMine, debuffsOnlyMine = false, false
    local buffsIncludeBoss, debuffsIncludeBoss = false, false
    local hidePermanentBuffs = false

    if masterOn and tf then
        local b = tf.buffs
        local d = tf.debuffs

        -- IMPORTANT per-type toggles (preferred). Fall back to legacyOnlyImportant only if missing.
        if b and b.onlyImportant ~= nil then
            onlyImportantBuffs = (b.onlyImportant == true)
        else
            onlyImportantBuffs = legacyOnlyImportant
        end
        if d and d.onlyImportant ~= nil then
            onlyImportantDebuffs = (d.onlyImportant == true)
        else
            onlyImportantDebuffs = legacyOnlyImportant
        end

        if b and b.onlyMine ~= nil then
            buffsOnlyMine = (b.onlyMine == true)
        else
            buffsOnlyMine = (type(shared) == "table" and shared.onlyMyBuffs == true) or false
        end

        if d and d.onlyMine ~= nil then
            debuffsOnlyMine = (d.onlyMine == true)
        else
            debuffsOnlyMine = (type(shared) == "table" and shared.onlyMyDebuffs == true) or false
        end

        buffsIncludeBoss = (b and b.includeBoss == true) or false
        debuffsIncludeBoss = (d and d.includeBoss == true) or false

        if tf.hidePermanent ~= nil then
            hidePermanentBuffs = (tf.hidePermanent == true)
        else
            hidePermanentBuffs = (type(shared) == "table" and shared.hidePermanent == true) or false
        end
    else
        buffsOnlyMine = (type(shared) == "table" and shared.onlyMyBuffs == true) or false
        debuffsOnlyMine = (type(shared) == "table" and shared.onlyMyDebuffs == true) or false
        hidePermanentBuffs = (type(shared) == "table" and shared.hidePermanent == true) or false
        onlyImportantBuffs = false
        onlyImportantDebuffs = false
    end

    -- Aura sort order (numeric enum for C_UnitAuras.GetAuraSlots 4th arg)
    local sortOrder = (tf and type(tf.sortOrder) == "number") and tf.sortOrder or 0
    -- Reverse the C API sort order in Lua (e.g. Z→A, longest→soonest)
    local sortReverse = (tf and tf.sortReverse == true) and true or false

    return tf, masterOn, onlyBossAuras, onlyImportantBuffs, onlyImportantDebuffs, buffsOnlyMine, debuffsOnlyMine, buffsIncludeBoss, debuffsIncludeBoss, hidePermanentBuffs, sortOrder, sortReverse
end
