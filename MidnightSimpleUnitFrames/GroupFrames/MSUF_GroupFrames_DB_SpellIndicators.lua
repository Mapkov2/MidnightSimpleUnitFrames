--- Group Frames DB: first-load Spell Indicator default seeding.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF
local GF = MSUF.GF or {}
MSUF.GF = GF

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
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, _autoSeededSpecs = {} }
        return conf.spellIndicators, true
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

local function CopyMissingSpecDefaults(siCfg, specKey)
    local SI = GetSpellIndicatorModule()
    local defaults = SI and SI.SpecDefaults and SI.SpecDefaults[specKey]
    if not (siCfg and specKey and defaults) then return false end

    if type(SI.EnsureSpecConfig) == "function" then
        SI.EnsureSpecConfig(siCfg, specKey)
        return true
    end

    siCfg.specs = siCfg.specs or {}
    local specCfg = siCfg.specs[specKey]
    if type(specCfg) ~= "table" then
        specCfg = {}
        siCfg.specs[specKey] = specCfg
    end

    for auraName, def in pairs(defaults) do
        local entry = specCfg[auraName]
        if type(entry) ~= "table" then
            entry = GF._DeepCopyTable(def)
            if entry.onlyOwn == nil then entry.onlyOwn = true end
            specCfg[auraName] = entry
        else
            if entry.placed == nil and def.placed ~= nil then
                entry.placed = GF._DeepCopyTable(def.placed)
            end
            if entry.frame == nil and def.frame ~= nil then
                entry.frame = GF._DeepCopyTable(def.frame)
            end
            if entry.onlyOwn == nil then
                entry.onlyOwn = (def.onlyOwn ~= false)
            end
        end
    end
    return true
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
                local stamps = si._autoSeededSpecs
                if not stamps[specKey] then
                    CopyMissingSpecDefaults(si, specKey)

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
        if GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_AURAS or GF.DIRTY_ALL or 0x3F) end
        if GF.RefreshVisuals and not (InCombatLockdown and InCombatLockdown()) then GF.RefreshVisuals() end
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

_G.MSUF_GF_SeedSpellIndicatorDefaultsForSpec = GF.SeedSpellIndicatorDefaultsForSpec
_G.MSUF_GF_SeedCurrentSpecSpellIndicatorDefaults = GF.SeedCurrentSpecSpellIndicatorDefaults

--- Keep first-load SI defaults in sync with the player's actual spec. This is
--- intentionally independent from group-frame size, alpha, aura, and role layout
--- defaults so those can evolve without maintaining role layout snapshots.
do
    local seedFrame = CreateFrame("Frame")
    local queued = false
    local function QueueSeed()
        if queued then return end
        queued = true
        local function Run()
            queued = false
            if GF.EnsureDB then GF.EnsureDB() end
            if GF.SeedCurrentSpecSpellIndicatorDefaults then
                GF.SeedCurrentSpecSpellIndicatorDefaults()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
    end

    seedFrame:RegisterEvent("PLAYER_LOGIN")
    seedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    seedFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    seedFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    seedFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    seedFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    seedFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
        QueueSeed()
    end)
end
