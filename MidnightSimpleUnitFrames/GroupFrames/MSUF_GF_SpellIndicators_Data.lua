-- MSUF_GF_SpellIndicators_Data.lua â€” Spell data for Group Frames Spell Indicators
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
-- Spec map (CLASS_SPECNUM â†’ specKey)
------------------------------------------------------------------------
SI.SpecMap = {
    DRUID_4     = "RestorationDruid",
    SHAMAN_3    = "RestorationShaman",
    PRIEST_1    = "DisciplinePriest",
    PRIEST_2    = "HolyPriest",
    PRIEST_3    = "ShadowPriest",
    PALADIN_1   = "HolyPaladin",
    PALADIN_2   = "ProtectionPaladin",
    PALADIN_3   = "RetributionPaladin",
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
    ShadowPriest        = { display = "Shadow Priest",        class = "PRIEST"  },
    MistweaverMonk      = { display = "Mistweaver Monk",      class = "MONK"    },
    RestorationShaman   = { display = "Restoration Shaman",   class = "SHAMAN"  },
    HolyPaladin         = { display = "Holy Paladin",         class = "PALADIN" },
    ProtectionPaladin   = { display = "Protection Paladin",   class = "PALADIN" },
    RetributionPaladin  = { display = "Retribution Paladin",  class = "PALADIN" },
}

------------------------------------------------------------------------
-- Spell IDs per spec (for runtime aura matching via reverse lookup)
------------------------------------------------------------------------
SI.SpellIDs = {
    PreservationEvoker = {
        Echo            = 364343,
        Reversion       = 366155,
        EchoReversion   = 367364,
        DreamBreath     = 355941,
        EchoDreamBreath = 376788,
        Lifebind        = 373267,
        DreamFlight     = 363502,
        TimeDilation    = 357170,
        Rewind          = 363534,
        VerdantEmbrace  = 409895,
    },
    AugmentationEvoker = {
        Prescience      = 410089,
        ShiftingSands   = 413984,
        BlisteringScales = 360827,
        InfernosBlessing = 410263,
        SymbioticBloom  = 410686,
        EbonMight       = 395152,
        SourceOfMagic   = 369459,
        SensePower      = 361022,
    },
    RestorationDruid = {
        Rejuvenation    = 774,
        Regrowth        = 8936,
        Lifebloom       = 33763,
        Germination     = 155777,
        WildGrowth      = 48438,
        SymbioticRelationship = 474754,
        SymbioticBlooms = 439530,
    },
    DisciplinePriest = {
        PowerWordShield = 17,
        Atonement       = 194384,
        PrayerOfMending = 41635,
        VoidShield      = 1253593,
        PowerInfusion   = 10060,
    },
    HolyPriest = {
        Renew           = 139,
        EchoOfLight     = 77489,
        PrayerOfMending = 41635,
        PowerInfusion   = 10060,
    },
    ShadowPriest = {
        PowerInfusion   = 10060,
    },
    MistweaverMonk = {
        RenewingMist    = 119611,
        EnvelopingMist  = 124682,
        SoothingMist    = 115175,
        AspectOfHarmony = 450769,
        Coalescence     = 1292922,
        StrengthOfTheBlackOx = 443113,
    },
    RestorationShaman = {
        Riptide         = 61295,
        EarthShield     = 383648,
        AncestralVigor  = 207400,
        EarthlivingWeapon = 382024,
        Hydrobubble     = 444490,
    },
    HolyPaladin = {
        BeaconOfLight   = 53563,
        BeaconOfFaith   = 156910,
        BeaconOfVirtue  = 200025,
        BeaconOfTheSavior = 1244893,
        EternalFlame    = 156322,
        Dawnlight       = 431381,
        HolyArmaments   = 432502,
    },
    ProtectionPaladin = {
        BlessingOfProtection = 1022,
        BlessingOfSacrifice  = 6940,
        BlessingOfFreedom    = 1044,
    },
    RetributionPaladin = {
        BlessingOfProtection = 1022,
        BlessingOfSacrifice  = 6940,
        BlessingOfFreedom    = 1044,
    },
}

-- Alternate spell IDs (same aura, different ID)
SI.AltSpellIDs = {
    RestorationDruid = {
        [474750] = "SymbioticRelationship",
        [474760] = "SymbioticRelationship",
    },
    RestorationShaman = {
        [974]    = "EarthShield",
        [382021] = "EarthlivingWeapon",
        [382022] = "EarthlivingWeapon",
    },
    HolyPaladin = {
        [432496] = "HolyArmaments",
    },
}

-- Auras that can appear on the player with a non-player sourceUnit, so
-- HELPFUL|PLAYER does not reliably return them.
SI.SelfOnlySpellIDs = {
    RestorationDruid = {
        [474754] = "SymbioticRelationship",
    },
    AugmentationEvoker = {
        [395296] = "EbonMight",
    },
}

SI.LinkedAuraRules = {
    RestorationDruid = {
        SymbioticRelationship = {
            sourceSpellID = 474754,
            targetSpellIDs = { 474750, 474760 },
        },
    },
}

------------------------------------------------------------------------
-- Secret spell IDs: spellId may be unreadable in combat, so runtime
-- matching falls back to localized names and filter fingerprints.
------------------------------------------------------------------------
SI.SecretSpellIDs = {
    PreservationEvoker = { TimeDilation = 357170, Rewind = 363534, VerdantEmbrace = 409895 },
    AugmentationEvoker = { SensePower = 361022 },
    RestorationDruid  = { IronBark = 102342 },
    DisciplinePriest  = { PainSuppression = 33206, PowerInfusion = 10060 },
    HolyPriest        = { GuardianSpirit = 47788, PowerInfusion = 10060 },
    ShadowPriest      = { PowerInfusion = 10060 },
    MistweaverMonk    = { LifeCocoon = 116849, StrengthOfTheBlackOx = 443113 },
    HolyPaladin       = { BlessingOfProtection = 1022, HolyArmaments = 432502, BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044 },
    ProtectionPaladin = { BlessingOfProtection = 1022, BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044 },
    RetributionPaladin = { BlessingOfProtection = 1022, BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044 },
}

-- Secret aura fingerprints derived from Blizzard's own aura filters.
-- Signature format: RAID:RAID_IN_COMBAT:EXTERNAL_DEFENSIVE:RAID_PLAYER_DISPELLABLE
SI.SecretAuraInfo = {
    PreservationEvoker = {
        TimeDilation   = { signature = "1:1:1:0" },
        Rewind         = { signature = "1:1:0:0" },
        VerdantEmbrace = { signature = "0:1:0:0" },
    },
    AugmentationEvoker = {
        SensePower = { signature = "0:1:0:0" },
    },
    RestorationDruid = {
        IronBark = { signature = "1:1:1:0" },
    },
    DisciplinePriest = {
        PainSuppression = { signature = "1:1:1:0" },
        PowerInfusion   = { signature = "1:0:0:1" },
    },
    HolyPriest = {
        GuardianSpirit = { signature = "1:1:1:0" },
        PowerInfusion  = { signature = "1:0:0:1" },
    },
    ShadowPriest = {
        PowerInfusion = { signature = "1:0:0:1" },
    },
    MistweaverMonk = {
        LifeCocoon           = { signature = "1:1:1:0" },
        StrengthOfTheBlackOx = { signature = "0:1:0:1" },
    },
    HolyPaladin = {
        BlessingOfProtection = { signature = "1:1:1:1" },
        HolyArmaments        = { signature = "0:1:0:0" },
        BlessingOfSacrifice  = { signature = "1:1:1:0" },
        BlessingOfFreedom    = { signature = "1:0:0:1" },
    },
    ProtectionPaladin = {
        BlessingOfProtection = { signature = "1:1:1:1" },
        BlessingOfSacrifice  = { signature = "1:1:1:0" },
        BlessingOfFreedom    = { signature = "1:0:0:1" },
    },
    RetributionPaladin = {
        BlessingOfProtection = { signature = "1:1:1:1" },
        BlessingOfSacrifice  = { signature = "1:1:1:0" },
        BlessingOfFreedom    = { signature = "1:0:0:1" },
    },
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
    EchoReversion   = 4630469,
    DreamBreath     = 4622454,
    EchoDreamBreath = 7439198,
    DreamFlight     = 4622455,
    Lifebind        = 4630453,
    TimeDilation    = 4622478,
    Rewind          = 4622474,
    VerdantEmbrace  = 4622471,
    -- Augmentation Evoker
    Prescience      = 5199639,
    ShiftingSands   = 5199633,
    BlisteringScales = 5199621,
    InfernosBlessing = 5199632,
    SymbioticBloom  = 4554354,
    EbonMight       = 5061347,
    SourceOfMagic   = 4630412,
    SensePower      = 132160,
    -- Restoration Druid
    Rejuvenation    = 136081,
    Regrowth        = 136085,
    Lifebloom       = 134206,
    Germination     = 1033478,
    WildGrowth      = 236153,
    SymbioticRelationship = 1408837,
    SymbioticBlooms = 463540,
    IronBark        = 572025,
    -- Discipline Priest
    PowerWordShield = 135940,
    Atonement       = 458720,
    PrayerOfMending = 135944,
    VoidShield      = 7514191,
    PainSuppression = 135936,
    PowerInfusion   = 135939,
    -- Holy Priest
    Renew           = 135953,
    EchoOfLight     = 237537,
    GuardianSpirit  = 237542,
    -- Mistweaver Monk
    RenewingMist    = 627487,
    EnvelopingMist  = 775461,
    SoothingMist    = 606550,
    AspectOfHarmony = 5927638,
    Coalescence     = "Interface\\Icons\\ability_monk_effuse",
    LifeCocoon      = 627485,
    StrengthOfTheBlackOx = 615340,
    -- Restoration Shaman
    Riptide         = 252995,
    EarthShield     = 136089,
    AncestralVigor  = 237574,
    EarthlivingWeapon = 237578,
    Hydrobubble     = 1320371,
    -- Holy Paladin
    BeaconOfLight   = 236247,
    BeaconOfFaith   = 1030095,
    BeaconOfVirtue  = 1030094,
    BeaconOfTheSavior = 7514188,
    EternalFlame    = 135433,
    BlessingOfProtection = 135964,
    HolyArmaments   = 5927636,
    BlessingOfSacrifice  = 135966,
    BlessingOfFreedom    = 135968,
    Dawnlight       = 5927633,
}

------------------------------------------------------------------------
-- Trackable auras per spec (ordered for UI display)
-- secret = true: spellId may be unreadable in combat; filter fingerprints handle those auras.
------------------------------------------------------------------------
SI.TrackableAuras = {
    PreservationEvoker = {
        { name = "Echo",         display = "Echo",          color = {0.31, 0.76, 0.97} },
        { name = "Reversion",    display = "Reversion",     color = {0.51, 0.78, 0.52} },
        { name = "EchoReversion", display = "Echo Reversion", color = {0.40, 0.77, 0.74} },
        { name = "DreamBreath",  display = "Dream Breath",  color = {0.47, 0.87, 0.47} },
        { name = "EchoDreamBreath", display = "Echo Dream Breath", color = {0.36, 0.82, 0.60} },
        { name = "DreamFlight",  display = "Dream Flight",  color = {0.81, 0.58, 0.93} },
        { name = "Lifebind",     display = "Lifebind",      color = {0.94, 0.50, 0.50} },
        { name = "TimeDilation",  display = "Time Dilation", color = {0.94, 0.82, 0.31}, secret = true },
        { name = "Rewind",        display = "Rewind",        color = {0.74, 0.85, 0.40}, secret = true },
        { name = "VerdantEmbrace", display = "Verdant Embrace", color = {0.47, 0.87, 0.47}, secret = true },
    },
    AugmentationEvoker = {
        { name = "Prescience",       display = "Prescience",        color = {0.81, 0.58, 0.85} },
        { name = "ShiftingSands",    display = "Shifting Sands",    color = {1.00, 0.84, 0.28} },
        { name = "BlisteringScales", display = "Blistering Scales", color = {0.94, 0.50, 0.50} },
        { name = "InfernosBlessing", display = "Infernos Blessing", color = {1.00, 0.60, 0.28} },
        { name = "SymbioticBloom",   display = "Symbiotic Bloom",   color = {0.51, 0.78, 0.52} },
        { name = "EbonMight",        display = "Ebon Might",        color = {0.62, 0.47, 0.85} },
        { name = "SourceOfMagic",    display = "Source of Magic",   color = {0.31, 0.76, 0.97} },
        { name = "SensePower",       display = "Sense Power",       color = {0.94, 0.82, 0.31}, secret = true },
    },
    RestorationDruid = {
        { name = "Rejuvenation", display = "Rejuvenation", color = {0.51, 0.78, 0.52} },
        { name = "Regrowth",     display = "Regrowth",     color = {0.31, 0.76, 0.97} },
        { name = "Lifebloom",    display = "Lifebloom",    color = {0.56, 0.93, 0.56} },
        { name = "Germination",  display = "Germination",  color = {0.77, 0.89, 0.42} },
        { name = "WildGrowth",   display = "Wild Growth",  color = {0.81, 0.58, 0.93} },
        { name = "SymbioticRelationship", display = "Symbiotic Relationship", color = {0.40, 0.77, 0.74} },
        { name = "SymbioticBlooms", display = "Symbiotic Blooms", color = {0.45, 0.82, 0.55} },
        { name = "IronBark",     display = "Ironbark",     color = {0.65, 0.47, 0.33}, secret = true },
    },
    DisciplinePriest = {
        { name = "Atonement",       display = "Atonement",        color = {0.94, 0.50, 0.50} },
        { name = "PowerWordShield", display = "PW: Shield",       color = {1.00, 0.84, 0.28} },
        { name = "PrayerOfMending", display = "Prayer of Mending",color = {0.56, 0.93, 0.56} },
        { name = "VoidShield",      display = "Void Shield",      color = {0.49, 0.77, 1.00} },
        { name = "PainSuppression", display = "Pain Suppression", color = {0.81, 0.58, 0.93}, secret = true },
        { name = "PowerInfusion",   display = "Power Infusion",   color = {0.94, 0.82, 0.31}, secret = true },
    },
    HolyPriest = {
        { name = "Renew",           display = "Renew",           color = {0.56, 0.93, 0.56} },
        { name = "EchoOfLight",     display = "Echo of Light",   color = {1.00, 0.84, 0.28} },
        { name = "PrayerOfMending", display = "Prayer of Mending", color = {0.81, 0.58, 0.93} },
        { name = "GuardianSpirit",  display = "Guardian Spirit",  color = {0.94, 0.50, 0.50}, secret = true },
        { name = "PowerInfusion",   display = "Power Infusion",   color = {0.94, 0.82, 0.31}, secret = true },
    },
    ShadowPriest = {
        { name = "PowerInfusion", display = "Power Infusion", color = {0.94, 0.82, 0.31}, secret = true },
    },
    MistweaverMonk = {
        { name = "RenewingMist",   display = "Renewing Mist",   color = {0.56, 0.93, 0.56} },
        { name = "EnvelopingMist", display = "Enveloping Mist", color = {0.31, 0.76, 0.97} },
        { name = "SoothingMist",   display = "Soothing Mist",   color = {0.47, 0.87, 0.47} },
        { name = "AspectOfHarmony", display = "Aspect of Harmony", color = {0.81, 0.58, 0.93} },
        { name = "Coalescence",    display = "Coalescence",     color = {0.31, 0.76, 0.97} },
        { name = "LifeCocoon",     display = "Life Cocoon",     color = {0.31, 0.76, 0.97}, secret = true },
        { name = "StrengthOfTheBlackOx", display = "Strength of the Black Ox", color = {0.40, 0.77, 0.74}, secret = true },
    },
    RestorationShaman = {
        { name = "Riptide",           display = "Riptide",            color = {0.31, 0.76, 0.97} },
        { name = "EarthShield",       display = "Earth Shield",       color = {0.65, 0.47, 0.33} },
        { name = "AncestralVigor",    display = "Ancestral Vigor",    color = {0.56, 0.93, 0.56} },
        { name = "EarthlivingWeapon", display = "Earthliving Weapon", color = {0.47, 0.87, 0.47} },
        { name = "Hydrobubble",       display = "Hydrobubble",        color = {0.31, 0.76, 0.97} },
    },
    HolyPaladin = {
        { name = "BeaconOfLight",        display = "Beacon of Light",       color = {1.00, 0.93, 0.47} },
        { name = "BeaconOfFaith",        display = "Beacon of Faith",       color = {1.00, 0.84, 0.28} },
        { name = "BeaconOfVirtue",       display = "Beacon of Virtue",      color = {1.00, 0.88, 0.37} },
        { name = "BeaconOfTheSavior",    display = "Beacon of the Savior",  color = {0.93, 0.80, 0.47} },
        { name = "EternalFlame",         display = "Eternal Flame",         color = {1.00, 0.60, 0.28} },
        { name = "Dawnlight",            display = "Dawnlight",             color = {1.00, 0.85, 0.40} },
        { name = "BlessingOfProtection", display = "Blessing of Protection", color = {0.94, 0.82, 0.31}, secret = true },
        { name = "HolyArmaments",        display = "Holy Armaments",        color = {0.81, 0.58, 0.93}, secret = true },
        { name = "BlessingOfSacrifice",  display = "Blessing of Sacrifice",  color = {0.94, 0.50, 0.50}, secret = true },
        { name = "BlessingOfFreedom",    display = "Blessing of Freedom",    color = {0.47, 0.77, 1.00}, secret = true },
    },
    ProtectionPaladin = {
        { name = "BlessingOfProtection", display = "Blessing of Protection", color = {0.94, 0.82, 0.31}, secret = true },
        { name = "BlessingOfSacrifice",  display = "Blessing of Sacrifice",  color = {0.94, 0.50, 0.50}, secret = true },
        { name = "BlessingOfFreedom",    display = "Blessing of Freedom",    color = {0.47, 0.77, 1.00}, secret = true },
    },
    RetributionPaladin = {
        { name = "BlessingOfProtection", display = "Blessing of Protection", color = {0.94, 0.82, 0.31}, secret = true },
        { name = "BlessingOfSacrifice",  display = "Blessing of Sacrifice",  color = {0.94, 0.50, 0.50}, secret = true },
        { name = "BlessingOfFreedom",    display = "Blessing of Freedom",    color = {0.47, 0.77, 1.00}, secret = true },
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
        SymbioticRelationship = { placed = { type = "square", anchor = "CENTER", x = -8, y = 0, size = 10 } },
        SymbioticBlooms = { placed = { type = "square", anchor = "CENTER", x = 8, y = 0, size = 10 } },
        IronBark     = { frame = { type = "border",  color = {0.65, 0.47, 0.33, 1}, priority = 1 } },
    },
    DisciplinePriest = {
        Atonement       = { placed = { type = "square", anchor = "TOPLEFT", x = 2, y = -2, size = 11 },
                            frame = { type = "healthtint", color = {0.94, 0.82, 0.31, 0.20}, priority = 5 } },
        PowerWordShield = { placed = { type = "icon",   anchor = "TOPRIGHT", x = -1, y = -1, size = 22 } },
        PrayerOfMending = { placed = { type = "icon",   anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        VoidShield      = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        PainSuppression = { frame = { type = "border",  color = {0.81, 0.58, 0.93, 1}, priority = 1 } },
        PowerInfusion   = { frame = { type = "glow",    color = {0.94, 0.82, 0.31, 1}, priority = 2 } },
    },
    HolyPriest = {
        Renew           = { placed = { type = "icon",   anchor = "TOPLEFT", x = 1, y = -1, size = 22 } },
        PrayerOfMending = { placed = { type = "icon",   anchor = "TOPRIGHT", x = -1, y = -1, size = 20 } },
        EchoOfLight     = { placed = { type = "square", anchor = "BOTTOMLEFT", x = 2, y = 2, size = 9 } },
        GuardianSpirit  = { frame = { type = "border",  color = {0.94, 0.50, 0.50, 1}, priority = 1 } },
        PowerInfusion   = { frame = { type = "glow",    color = {0.94, 0.82, 0.31, 1}, priority = 2 } },
    },
    ShadowPriest = {
        PowerInfusion = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 22 },
                          frame = { type = "glow", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
    },
    PreservationEvoker = {
        Echo         = { placed = { type = "icon", anchor = "TOPLEFT",    x = 1, y = -1, size = 22 },
                         frame = { type = "namecolor", color = {0.31, 0.76, 0.97, 1}, priority = 5 } },
        Reversion    = { placed = { type = "icon", anchor = "TOPRIGHT",   x = -1, y = -1, size = 22 } },
        EchoReversion = { placed = { type = "square", anchor = "TOP", x = 0, y = -3, size = 10 } },
        DreamBreath  = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        EchoDreamBreath = { placed = { type = "square", anchor = "BOTTOM", x = 0, y = 3, size = 10 } },
        Lifebind     = { placed = { type = "square", anchor = "CENTER",   x = 0, y = 0, size = 11 } },
        TimeDilation = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
        Rewind       = { frame = { type = "glow", color = {0.74, 0.85, 0.40, 1}, priority = 2 } },
        DreamFlight  = { frame = { type = "glow", color = {0.81, 0.58, 0.93, 1}, priority = 3 } },
        VerdantEmbrace = { placed = { type = "square", anchor = "CENTER", x = 12, y = 0, size = 10 } },
    },
    AugmentationEvoker = {
        EbonMight    = { placed = { type = "icon", anchor = "TOPLEFT",  x = 1, y = -1, size = 24 },
                         frame = { type = "healthtint", color = {0.62, 0.47, 0.85, 0.20}, priority = 5 } },
        Prescience   = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 24 },
                         frame = { type = "namecolor", color = {0.81, 0.58, 0.85, 1}, priority = 5 } },
        BlisteringScales = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        InfernosBlessing = { placed = { type = "square", anchor = "BOTTOMLEFT", x = 2, y = 2, size = 9 } },
        SymbioticBloom = { placed = { type = "square", anchor = "BOTTOM", x = 0, y = 3, size = 9 } },
        SourceOfMagic = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        ShiftingSands = { placed = { type = "square", anchor = "CENTER", x = -8, y = 0, size = 9 } },
        SensePower = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
    },
    MistweaverMonk = {
        RenewingMist   = { placed = { type = "icon", anchor = "TOPLEFT",    x = 1, y = -1, size = 22 } },
        EnvelopingMist = { placed = { type = "icon", anchor = "TOPRIGHT",   x = -1, y = -1, size = 22 } },
        SoothingMist   = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        AspectOfHarmony = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        Coalescence    = { placed = { type = "icon", anchor = "BOTTOM", x = 0, y = 1, size = 20 } },
        LifeCocoon     = { frame = { type = "border", color = {0.31, 0.76, 0.97, 1}, priority = 1 } },
        StrengthOfTheBlackOx = { frame = { type = "border", color = {0.40, 0.77, 0.74, 1}, priority = 2 } },
    },
    RestorationShaman = {
        Riptide     = { placed = { type = "icon", anchor = "TOPLEFT",  x = 1, y = -1, size = 22 } },
        EarthShield = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 22 } },
        AncestralVigor = { placed = { type = "square", anchor = "BOTTOMRIGHT", x = -3, y = 3, size = 9 } },
        EarthlivingWeapon = { placed = { type = "square", anchor = "BOTTOMLEFT", x = 2, y = 2, size = 9 } },
        Hydrobubble = { placed = { type = "square", anchor = "BOTTOM", x = 0, y = 3, size = 9 } },
    },
    HolyPaladin = {
        BeaconOfLight = { placed = { type = "icon", anchor = "TOPLEFT", x = 1, y = -1, size = 24 } },
        BeaconOfFaith = { placed = { type = "icon", anchor = "TOPRIGHT", x = -1, y = -1, size = 24 } },
        BeaconOfVirtue = { placed = { type = "icon", anchor = "TOP", x = 0, y = -1, size = 22 } },
        BeaconOfTheSavior = { placed = { type = "square", anchor = "CENTER", x = -8, y = 0, size = 10 } },
        EternalFlame  = { placed = { type = "icon", anchor = "BOTTOMLEFT", x = 1, y = 1, size = 20 } },
        Dawnlight     = { placed = { type = "square", anchor = "BOTTOM", x = 0, y = 3, size = 9 } },
        BlessingOfProtection = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
        HolyArmaments = { frame = { type = "glow", color = {0.81, 0.58, 0.93, 1}, priority = 4 } },
        BlessingOfSacrifice  = { frame = { type = "border", color = {0.94, 0.50, 0.50, 1}, priority = 2 } },
        BlessingOfFreedom    = { frame = { type = "border", color = {0.47, 0.77, 1.00, 1}, priority = 3 } },
    },
    ProtectionPaladin = {
        BlessingOfProtection = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
        BlessingOfSacrifice  = { frame = { type = "border", color = {0.94, 0.50, 0.50, 1}, priority = 2 } },
        BlessingOfFreedom    = { frame = { type = "border", color = {0.47, 0.77, 1.00, 1}, priority = 3 } },
    },
    RetributionPaladin = {
        BlessingOfProtection = { frame = { type = "border", color = {0.94, 0.82, 0.31, 1}, priority = 1 } },
        BlessingOfSacrifice  = { frame = { type = "border", color = {0.94, 0.50, 0.50, 1}, priority = 2 } },
        BlessingOfFreedom    = { frame = { type = "border", color = {0.47, 0.77, 1.00, 1}, priority = 3 } },
    },
}

------------------------------------------------------------------------
-- Build reverse lookup: spellId â†’ { specKey, auraName }
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
-- Resolve current player spec â†’ specKey
------------------------------------------------------------------------
local _cachedClassToken, _cachedSpecIdx, _cachedSpecKey
function SI.GetPlayerSpec()
    local _, classToken = UnitClass("player")
    if not classToken then return nil end
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return nil end
    if classToken == _cachedClassToken and specIdx == _cachedSpecIdx then
        return _cachedSpecKey
    end
    local key = classToken .. "_" .. specIdx
    _cachedClassToken = classToken
    _cachedSpecIdx = specIdx
    _cachedSpecKey = SI.SpecMap[key]
    return _cachedSpecKey
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
