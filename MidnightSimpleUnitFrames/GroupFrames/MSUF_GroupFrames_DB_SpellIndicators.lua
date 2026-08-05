--- Group Frames DB: first-load Spell Indicator default seeding.
-- Seeds cold profile data only; runtime indicator rendering lives in UF group modules.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local GF = MSUF.GF or {}
MSUF.GF = GF
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function IsDefaultsConf(kind, conf)
    if kind == "party" then return conf == GF.PARTY_DEFAULTS end
    if kind == "raid" then return conf == GF.RAID_DEFAULTS end
    if kind == "mythicraid" then return conf == GF.MYTHIC_RAID_DEFAULTS end
    return false
end

---
--- Shared table helpers
---
function GF._DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = GF._DeepCopyTable(v)
    end
    return dst
end

---
--- Spell Indicator first-load defaults
---
--- Older builds seeded healer Spell Indicators as a side effect of applying a
--- full role layout. Keep that behavior focused:
--- the first time a profile sees a supported player spec, copy that spec's
--- Spell Indicator defaults into SavedVariables and enable SI for that scope.
--- From then on the saved config is the source of truth.
---
local GF_SI_KINDS = { "party", "raid", "mythicraid" }
local GF_SI_SEED_VERSION = 1

local function NormalizeSpellIndicatorConfig(conf)
    if type(conf) ~= "table" then return nil, false end
    local changed = false
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, iconZoom = 100, iconScale = 100, _autoSeededSpecs = {} }
        changed = true
    end

    local si = conf.spellIndicators
    if si.spec == nil or si.spec == "" then
        si.spec = "auto"
        changed = true
    end
    if type(si.specs) ~= "table" then
        si.specs = {}
        changed = true
    end
    if si.layer == nil then
        si.layer = 9
        changed = true
    end
    if si.iconZoom == nil then
        si.iconZoom = 100
        changed = true
    end
    if si.iconScale == nil then
        si.iconScale = 100
        changed = true
    end
    if type(GF.EnsureSpellIndicatorStyle) == "function" then
        local _, styleChanged = GF.EnsureSpellIndicatorStyle(conf)
        changed = styleChanged or changed
    end
    if type(si._autoSeededSpecs) ~= "table" then
        si._autoSeededSpecs = {}
        changed = true
    end
    return si, changed
end

local function GetSpellIndicatorModule()
    return GF.SpellIndicators or _G.MSUF_GF_SpellIndicators
end

local function GetCurrentSpellIndicatorSpecKey()
    local SI = GetSpellIndicatorModule()
    if SI and type(SI.GetPlayerSpec) == "function" then
        local specKey = SI.GetPlayerSpec()
        if specKey then return specKey end
    end

    local _, classToken
    if UnitClass then _, classToken = UnitClass("player") end
    local specIdx = GetSpecialization and GetSpecialization() or nil
    if not (SI and SI.SpecMap and classToken and specIdx) then return nil end
    return SI.SpecMap[classToken .. "_" .. specIdx]
end

--- Additive nil-fill of one spec's saved entries from SpecDefaults. Explicit
--- user state is never touched: existing tables keep their values, `false`
--- entries/fields (user-disabled) stay false. Returns whether anything was
--- written so callers only mark the profile dirty on a real change.
local function FillMissingSpecDefaults(siCfg, specKey)
    local SI = GetSpellIndicatorModule()
    local defaults = SI and SI.SpecDefaults and SI.SpecDefaults[specKey]
    if not (siCfg and specKey and defaults) then return false end

    siCfg.specs = siCfg.specs or {}
    local specCfg = siCfg.specs[specKey]
    if type(specCfg) ~= "table" then
        specCfg = {}
        siCfg.specs[specKey] = specCfg
    end

    local changed = false
    for auraName, def in pairs(defaults) do
        local entry = specCfg[auraName]
        if entry == nil then
            entry = GF._DeepCopyTable(def)
            if entry.onlyOwn == nil then entry.onlyOwn = true end
            specCfg[auraName] = entry
            changed = true
        elseif type(entry) == "table" then
            if entry.placed == nil and def.placed ~= nil then
                entry.placed = GF._DeepCopyTable(def.placed)
                changed = true
            end
            if entry.frame == nil and def.frame ~= nil then
                entry.frame = GF._DeepCopyTable(def.frame)
                changed = true
            end
            if entry.onlyOwn == nil then
                entry.onlyOwn = (def.onlyOwn ~= false)
                changed = true
            end
        end
    end
    return changed
end

function GF.SeedSpellIndicatorDefaultsForSpec(specKey)
    local SI = GetSpellIndicatorModule()
    if not (SI and SI.SpecDefaults and SI.SpecDefaults[specKey]) then return false end

    local changed = false
    for i = 1, #GF_SI_KINDS do
        local kind = GF_SI_KINDS[i]
        local conf = GF.GetConf and GF.GetConf(kind) or nil
        if type(conf) == "table" and not IsDefaultsConf(kind, conf) then
            local si, normalized = NormalizeSpellIndicatorConfig(conf)
            changed = normalized or changed
            if si then
                -- The additive fill runs on every pass, stamped or not: spells
                -- added to SpecDefaults in later builds must reach specs that
                -- were seeded before those spells existed, otherwise their
                -- preview icons render from merged defaults with no saved
                -- entry behind them.
                changed = FillMissingSpecDefaults(si, specKey) or changed

                local stamps = si._autoSeededSpecs
                if not stamps[specKey] then
                    if si.enabled ~= true then
                        si.enabled = true
                    end
                    if si.spec == nil or si.spec == "" then
                        si.spec = "auto"
                    elseif si.spec == "multi" then
                        if type(si.multiSpecs) ~= "table" then si.multiSpecs = {} end
                        if not next(si.multiSpecs) then si.multiSpecs[specKey] = true end
                    end

                    stamps[specKey] = GF_SI_SEED_VERSION
                    si._autoSeedVersion = GF_SI_SEED_VERSION
                    changed = true
                end
            end
        end
    end

    if changed then
        local siModule = GetSpellIndicatorModule()
        if siModule and type(siModule.InvalidateRuntimeCaches) == "function" then
            siModule.InvalidateRuntimeCaches()
        end
        local dirty = GF.DIRTY_AURAS or GF.DIRTY_ALL or 0x3F
        -- Seeding touches only spell-indicator/aura config. Keep the refresh
        -- masked so first-login spec defaults do not replay every group element.
        if GF.MarkAllDirty then
            GF.MarkAllDirty(dirty)
        elseif GF.RefreshVisuals and not (InCombatLockdown and InCombatLockdown()) then
            GF.RefreshVisuals(nil, dirty)
        end
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if GF._RequestOptionsResync then GF._RequestOptionsResync() end
    end
    return changed
end

function GF.SeedCurrentSpecSpellIndicatorDefaults()
    local specKey = GetCurrentSpellIndicatorSpecKey()
    if not specKey then return false end
    return GF.SeedSpellIndicatorDefaultsForSpec(specKey)
end

ExportPublic("MSUF_GF_SeedSpellIndicatorDefaultsForSpec", GF.SeedSpellIndicatorDefaultsForSpec)
ExportPublic("MSUF_GF_SeedCurrentSpecSpellIndicatorDefaults", GF.SeedCurrentSpecSpellIndicatorDefaults)

--- Keep first-load SI defaults in sync with the player's actual spec. This is
--- intentionally independent from group-frame size, alpha, aura, and role layout
--- defaults so those can evolve without maintaining role layout snapshots.
do
    local seedFrame = CreateFrame("Frame")
    local queued = false
    local generation = 0
    local eventsEnabled = false
    local SEED_EVENTS = {
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED",
    }

    local function SpellIndicatorRuntimeWanted()
        for i = 1, #GF_SI_KINDS do
            local conf = GF.GetConf and GF.GetConf(GF_SI_KINDS[i]) or nil
            if conf and conf.enabled == true
                and type(conf.spellIndicators) == "table"
                and conf.spellIndicators.enabled == true then
                return true
            end
        end
        return false
    end

    local function SetSeedEventsEnabled(enabled)
        enabled = enabled == true
        if eventsEnabled == enabled then return end
        eventsEnabled = enabled
        generation = generation + 1
        queued = false
        seedFrame:UnregisterAllEvents()
        if not enabled then return end
        for i = 1, #SEED_EVENTS do seedFrame:RegisterEvent(SEED_EVENTS[i]) end
    end

    local function QueueSeed()
        if not eventsEnabled or queued then return end
        queued = true
        local queuedGeneration = generation
        local function Run()
            queued = false
            if queuedGeneration ~= generation or not eventsEnabled or not SpellIndicatorRuntimeWanted() then return end
            if GF.EnsureDB then GF.EnsureDB() end
            if GF.SeedCurrentSpecSpellIndicatorDefaults then
                GF.SeedCurrentSpecSpellIndicatorDefaults()
            end
        end
        C_Timer.After(0, Run)
    end

    seedFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
        QueueSeed()
    end)

    function GF.RefreshSpellIndicatorSeedEvents()
        local wanted = SpellIndicatorRuntimeWanted()
        SetSeedEventsEnabled(wanted)
        if wanted then QueueSeed() end
        return wanted
    end
    ExportPublic("MSUF_GF_RefreshSpellIndicatorSeedEvents", GF.RefreshSpellIndicatorSeedEvents)
    GF.RefreshSpellIndicatorSeedEvents()
end
