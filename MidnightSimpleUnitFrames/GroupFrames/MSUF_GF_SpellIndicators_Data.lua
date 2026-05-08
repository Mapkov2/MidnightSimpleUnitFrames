-- MSUF_GF_SpellIndicators_Data.lua — Spell data for Group Frames Spell Indicators
-- Per-spec trackable spells, spell IDs, icon textures, default configs.
-- Secret aura classifications. Zero runtime cost (cold-path only).
-- Midnight 12.0
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local SI = {}
GF.SpellIndicators = SI

------------------------------------------------------------------------
-- Spec map (CLASS_SPECNUM → specKey)
------------------------------------------------------------------------
SI.SpecMap = {
    DRUID_4     = "RestorationDruid",
    SHAMAN_3    = "RestorationShaman",
    PRIEST_1    = "DisciplinePriest",
    PRIEST_2    = "HolyPriest",
    PALADIN_1   = "HolyPaladin",
    EVOKER_2    = "PreservationEvoker",
    EVOKER_3    = "AugmentationEvoker",
    MONK_2      = "MistweaverMonk",
}

SI.SpecInfo = {
    PreservationEvoker  = { display = "Preservation Evoker",  class = "EVOKER"  },
    AugmentationEvoker  = { display = "Augmentation Evoker",  class = "EVOKER"  },
    RestorationDruid    = { display = "Restoration Druid",    class = "DRUID"   },
    DisciplinePriest    = { display = "Discipline Priest",    class = "PRIEST"  },
    HolyPriest          = { display = "Holy Priest",          class = "PRIEST"  },
    MistweaverMonk      = { display = "Mistweaver Monk",      class = "MONK"    },
    RestorationShaman   = { display = "Restoration Shaman",   class = "SHAMAN"  },
    HolyPaladin         = { display = "Holy Paladin",         class = "PALADIN" },
}

------------------------------------------------------------------------
-- Spell IDs per spec (for runtime aura matching via reverse lookup)
------------------------------------------------------------------------
SI.SpellIDs = {
    PreservationEvoker = {
        Echo            = 364343,
        Reversion       = 366155,
        DreamBreath     = 355941,
        Lifebind        = 373267,
        DreamFlight     = 363502,
    },
    AugmentationEvoker = {
        Prescience      = 410089,
        ShiftingSands   = 413984,
        BlisteringScales = 360827,
        EbonMight       = 395152,
        SourceOfMagic   = 369459,
    },
    RestorationDruid = {
        Rejuvenation    = 774,
        Regrowth        = 8936,
        Lifebloom       = 33763,
        Germination     = 155777,
        WildGrowth      = 48438,
    },
    DisciplinePriest = {
        PowerWordShield = 17,
        Atonement       = 194384,
        PrayerOfMending = 41635,
        VoidShield      = 1253593,
    },
    HolyPriest = {
        Renew           = 139,
        EchoOfLight     = 77489,
        PrayerOfMending = 41635,
    },
    MistweaverMonk = {
        RenewingMist    = 119611,
        EnvelopingMist  = 124682,
        SoothingMist    = 115175,
    },
    RestorationShaman = {
        Riptide         = 61295,
        EarthShield     = 383648,
        EarthlivingWeapon = 382024,
    },
    HolyPaladin = {
        BeaconOfLight   = 53563,
        BeaconOfFaith   = 156910,
        EternalFlame    = 156322,
        Dawnlight       = 431381,
    },
}

-- Alternate spell IDs (same aura, different ID)
SI.AltSpellIDs = {
    RestorationShaman = {
        [974]    = "EarthShield",
        [382021] = "EarthlivingWeapon",
        [382022] = "EarthlivingWeapon",
    },
}

------------------------------------------------------------------------
-- Secret spell IDs (Phase 2 fingerprinting — spellId unreadable for
-- other players' casts, matched by localized aura name instead)
------------------------------------------------------------------------
SI.SecretSpellIDs = {
    RestorationDruid  = { IronBark = 102342 },
    DisciplinePriest  = { PainSuppression = 33206 },
    HolyPriest        = { GuardianSpirit = 47788 },
    MistweaverMonk    = { LifeCocoon = 116849 },
    HolyPaladin       = { BlessingOfProtection = 1022, BlessingOfSacrifice = 6940 },
}

------------------------------------------------------------------------
-- Build name-based reverse lookup for secret spells.
-- Called once per spec change (cold path). Uses C_Spell.GetSpellName
-- at load time to resolve localized names.
-- Returns: { [localizedName] = auraKey } or nil
------------------------------------------------------------------------
do
    local _nameCache = {} -- [spellId] = localizedName, persists across rebuilds

    function SI.BuildNameLookup(specKey)
        local secrets = SI.SecretSpellIDs[specKey]
        if not secrets then return nil end
        local lookup = {}
        local any = false
        for auraName, sid in pairs(secrets) do
            local locName = _nameCache[sid]
            if not locName and C_Spell and C_Spell.GetSpellName then
                locName = C_Spell.GetSpellName(sid)
                if locName then _nameCache[sid] = locName end
            end
            if locName then
                lookup[locName] = auraName
                any = true
            end
        end
        return any and lookup or nil
    end
end

------------------------------------------------------------------------
-- Static icon textures (avoids C_Spell.GetSpellTexture talent-swap bug)
------------------------------------------------------------------------
SI.IconTextures = {
    -- Preservation Evoker
    Echo            = 4622456,
    Reversion       = 4630467,
    DreamBreath     = 4622454,
    DreamFlight     = 4622455,
    Lifebind        = 4630453,
    -- Augmentation Evoker
    Prescience      = 5199639,
    ShiftingSands   = 5199633,
    BlisteringScales = 5199621,
    EbonMight       = 5061347,
    SourceOfMagic   = 4630412,
    -- Restoration Druid
    Rejuvenation    = 136081,
    Regrowth        = 136085,
    Lifebloom       = 134206,
    Germination     = 1033478,
    WildGrowth      = 236153,
    IronBark        = 572025,
    -- Discipline Priest
    PowerWordShield = 135940,
    Atonement       = 458720,
    PrayerOfMending = 135944,
    PainSuppression = 135936,
    -- Holy Priest
    Renew           = 135953,
    EchoOfLight     = 237537,
    GuardianSpirit  = 237542,
    -- Mistweaver Monk
    RenewingMist    = 627487,
    EnvelopingMist  = 775461,
    SoothingMist    = 606550,
    LifeCocoon      = 627485,
    -- Restoration Shaman
    Riptide         = 252995,
    EarthShield     = 136089,
    EarthlivingWeapon = 237578,
    -- Holy Paladin
    BeaconOfLight   = 236247,
    BeaconOfFaith   = 1030095,
    EternalFlame    = 135433,
    BlessingOfProtection = 135964,
    BlessingOfSacrifice  = 135966,
}

------------------------------------------------------------------------
-- Trackable auras per spec (ordered for UI display)
-- secret = true → spellId unreadable in combat, frame effects only in Phase 1
------------------------------------------------------------------------
SI.TrackableAuras = {
    PreservationEvoker = {
        { name = "Echo",         display = "Echo",          color = {0.31, 0.76, 0.97} },
        { name = "Reversion",    display = "Reversion",     color = {0.51, 0.78, 0.52} },
        { name = "DreamBreath",  display = "Dream Breath",  color = {0.47, 0.87, 0.47} },
        { name = "DreamFlight",  display = "Dream Flight",  color = {0.81, 0.58, 0.93} },
        { name = "Lifebind",     display = "Lifebind",      color = {0.94, 0.50, 0.50} },
    },
    AugmentationEvoker = {
        { name = "Prescience",       display = "Prescience",        color = {0.81, 0.58, 0.85} },
        { name = "ShiftingSands",    display = "Shifting Sands",    color = {1.00, 0.84, 0.28} },
        { name = "BlisteringScales", display = "Blistering Scales", color = {0.94, 0.50, 0.50} },
        { name = "EbonMight",        display = "Ebon Might",        color = {0.62, 0.47, 0.85} },
        { name = "SourceOfMagic",    display = "Source of Magic",   color = {0.31, 0.76, 0.97} },
    },
    RestorationDruid = {
        { name = "Rejuvenation", display = "Rejuvenation", color = {0.51, 0.78, 0.52} },
        { name = "Regrowth",     display = "Regrowth",     color = {0.31, 0.76, 0.97} },
        { name = "Lifebloom",    display = "Lifebloom",    color = {0.56, 0.93, 0.56} },
        { name = "Germination",  display = "Germination",  color = {0.77, 0.89, 0.42} },
        { name = "WildGrowth",   display = "Wild Growth",  color = {0.81, 0.58, 0.93} },
        { name = "IronBark",     display = "Ironbark",     color = {0.65, 0.47, 0.33}, secret = true },
    },
    DisciplinePriest = {
        { name = "Atonement",       display = "Atonement",        color = {0.94, 0.50, 0.50} },
        { name = "PowerWordShield", display = "PW: Shield",       color = {1.00, 0.84, 0.28} },
        { name = "PrayerOfMending", display = "Prayer of Mending",color = {0.56, 0.93, 0.56} },
        { name = "VoidShield",      display = "Void Shield",      color = {0.49, 0.77, 1.00} },
        { name = "PainSuppression", display = "Pain Suppression", color = {0.81, 0.58, 0.93}, secret = true },
    },
    HolyPriest = {
        { name = "Renew",           display = "Renew",           color = {0.56, 0.93, 0.56} },
        { name = "EchoOfLight",     display = "Echo of Light",   color = {1.00, 0.84, 0.28} },
        { name = "PrayerOfMending", display = "Prayer of Mending", color = {0.81, 0.58, 0.93} },
        { name = "GuardianSpirit",  display = "Guardian Spirit",  color = {0.94, 0.50, 0.50}, secret = true },
    },
    MistweaverMonk = {
        { name = "RenewingMist",   display = "Renewing Mist",   color = {0.56, 0.93, 0.56} },
        { name = "EnvelopingMist", display = "Enveloping Mist", color = {0.31, 0.76, 0.97} },
        { name = "SoothingMist",   display = "Soothing Mist",   color = {0.47, 0.87, 0.47} },
        { name = "LifeCocoon",     display = "Life Cocoon",     color = {0.31, 0.76, 0.97}, secret = true },
    },
    RestorationShaman = {
        { name = "Riptide",           display = "Riptide",            color = {0.31, 0.76, 0.97} },
        { name = "EarthShield",       display = "Earth Shield",       color = {0.65, 0.47, 0.33} },
        { name = "EarthlivingWeapon", display = "Earthliving Weapon", color = {0.47, 0.87, 0.47} },
    },
    HolyPaladin = {
        { name = "BeaconOfLight",        display = "Beacon of Light",       color = {1.00, 0.93, 0.47} },
        { name = "BeaconOfFaith",        display = "Beacon of Faith",       color = {1.00, 0.84, 0.28} },
        { name = "EternalFlame",         display = "Eternal Flame",         color = {1.00, 0.60, 0.28} },
        { name = "Dawnlight",            display = "Dawnlight",             color = {1.00, 0.85, 0.40} },
        { name = "BlessingOfProtection", display = "Blessing of Protection", color = {0.94, 0.82, 0.31}, secret = true },
        { name = "BlessingOfSacrifice",  display = "Blessing of Sacrifice",  color = {0.94, 0.50, 0.50}, secret = true },
    },
}

------------------------------------------------------------------------
-- Spec defaults: auto-populated when user first enables SI for a spec
------------------------------------------------------------------------
SI.SpecDefaults = {
    RestorationDruid = {
        Rejuvenation = { placed = { type = "icon",   anchor = "TOPLEFT",     x = 1, y = -1, size = 22 } },
        Regrowth     = { placed = { type = "icon",   anchor = "TOPRIGHT",    x = -1, y = -1, size = 22 } },
        Lifebloom    = { placed = { type = "icon",   anchor = "BOTTOMLEFT",  x = 1, y = 1, size = 22 } },
        WildGrowth   = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        Germination  = { placed = { type = "square", anchor = "BOTTOM",      x = 0, y = 3, size = 9 } },
        IronBark     = { frame = { type = "border",  color = {0.65, 0.47, 0.33, 1}, priority = 1 } },
    },
    DisciplinePriest = {
        Atonement       = { placed = { type = "square", anchor = "TOPLEFT", x = 2, y = -2, size = 11 },
                            frame = { type = "healthtint", color = {0.94, 0.82, 0.31, 0.20}, priority = 5 } },
        PowerWordShield = { placed = { type = "icon",   anchor = "TOPRIGHT", x = -1, y = -1, size = 22 } },
        PrayerOfMending = { placed = { type = "icon",   anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        VoidShield      = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        PainSuppression = { frame = { type = "border",  color = {0.81, 0.58, 0.93, 1}, priority = 1 } },
    },
    HolyPriest = {
        Renew           = { placed = { type = "icon",   anchor = "TOPLEFT", x = 1, y = -1, size = 22 } },
        PrayerOfMending = { placed = { type = "icon",   anchor = "TOPRIGHT", x = -1, y = -1, size = 20 } },
        EchoOfLight     = { placed = { type = "square", anchor = "BOTTOMLEFT", x = 2, y = 2, size = 9 } },
        GuardianSpirit  = { frame = { type = "border",  color = {0.94, 0.50, 0.50, 1}, priority = 1 } },
    },
    PreservationEvoker = {
        Echo         = { placed = { type = "icon", anchor = "TOPLEFT",    x = 1, y = -1, size = 22 },
                         frame = { type = "namecolor", color = {0.31, 0.76, 0.97, 1}, priority = 5 } },
        Reversion    = { placed = { type = "icon", anchor = "TOPRIGHT",   x = -1, y = -1, size = 22 } },
        DreamBreath  = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        Lifebind     = { placed = { type = "square", anchor = "CENTER",   x = 0, y = 0, size = 11 } },
    },
    AugmentationEvoker = {
        EbonMight    = { placed = { type = "icon", anchor = "TOPLEFT",  x = 1, y = -1, size = 24 },
                         frame = { type = "healthtint", color = {0.62, 0.47, 0.85, 0.20}, priority = 5 } },
        Prescience   = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 24 },
                         frame = { type = "namecolor", color = {0.81, 0.58, 0.85, 1}, priority = 5 } },
        BlisteringScales = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
    },
    MistweaverMonk = {
        RenewingMist   = { placed = { type = "icon", anchor = "TOPLEFT",    x = 1, y = -1, size = 22 } },
        EnvelopingMist = { placed = { type = "icon", anchor = "TOPRIGHT",   x = -1, y = -1, size = 22 } },
        SoothingMist   = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        LifeCocoon     = { frame = { type = "border", color = {0.31, 0.76, 0.97, 1}, priority = 1 } },
    },
    RestorationShaman = {
        Riptide     = { placed = { type = "icon", anchor = "TOPLEFT",  x = 1, y = -1, size = 22 } },
        EarthShield = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 22 } },
        EarthlivingWeapon = { placed = { type = "square", anchor = "BOTTOMLEFT", x = 2, y = 2, size = 9 } },
    },
    HolyPaladin = {
        BeaconOfLight = { placed = { type = "icon", anchor = "TOPLEFT", x = 1, y = -1, size = 24 } },
        BeaconOfFaith = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 24 } },
        EternalFlame  = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        Dawnlight     = { placed = { type = "square", anchor = "BOTTOM", x = 0, y = 3, size = 9 } },
        BlessingOfProtection = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
    },
}

------------------------------------------------------------------------
-- Build reverse lookup: spellId → { specKey, auraName }
-- Called once per spec change, result cached.
------------------------------------------------------------------------
function SI.BuildReverseLookup(specKey)
    local lookup = {}
    local ids = SI.SpellIDs[specKey]
    if ids then
        for auraName, spellId in pairs(ids) do
            lookup[spellId] = auraName
        end
    end
    local alts = SI.AltSpellIDs[specKey]
    if alts then
        for altId, auraName in pairs(alts) do
            lookup[altId] = auraName
        end
    end
    -- Include secret spell IDs (match player's own casts by readable spellId)
    local secrets = SI.SecretSpellIDs[specKey]
    if secrets then
        for auraName, spellId in pairs(secrets) do
            lookup[spellId] = auraName
        end
    end
    return lookup
end

------------------------------------------------------------------------
-- Resolve current player spec → specKey
------------------------------------------------------------------------
function SI.GetPlayerSpec()
    local _, classToken = UnitClass("player")
    if not classToken then return nil end
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return nil end
    local key = classToken .. "_" .. specIdx
    return SI.SpecMap[key]
end

------------------------------------------------------------------------
-- Get icon texture for an aura (static first, C_Spell fallback)
------------------------------------------------------------------------
function SI.GetAuraIcon(specKey, auraName)
    local tex = SI.IconTextures[auraName]
    if tex then return tex end
    local ids = SI.SpellIDs[specKey]
    local sid = ids and ids[auraName]
    if sid and C_Spell and C_Spell.GetSpellTexture then
        local t = C_Spell.GetSpellTexture(sid)
        if t then return t end
    end
    return 136243 -- question mark
end

------------------------------------------------------------------------
_G.MSUF_GF_SpellIndicators = SI
