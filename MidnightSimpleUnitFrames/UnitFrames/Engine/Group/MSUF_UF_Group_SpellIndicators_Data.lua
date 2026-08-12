--- UnitFrames/Engine/Group/MSUF_UF_Group_SpellIndicators_Data.lua
--- Built-in spell indicator defaults and spell-id metadata.
---
--- This file should stay declarative. Runtime matching, profile merging, and
--- icon lookup belong in SpellRegistry; DB first-load seeding lives in
--- GroupFrames/MSUF_GroupFrames_DB_SpellIndicators.lua.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
local ExportPublic = ns.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = ns.GF
if not GF then return end

local SI = GF.SpellIndicators or {}
GF.SpellIndicators = SI

SI.SpecMap = {}
SI.SpecInfo = {}
local function Spec(classToken, specIndex, specKey, specID, builtIn)
  SI.SpecMap[classToken .. "_" .. specIndex] = specKey
  SI.SpecInfo[specKey] = {
    display = specKey:gsub("(%l)(%u)", "%1 %2"),
    class = classToken,
    specID = specID,
    customOnly = builtIn ~= true or nil,
  }
end

-- Multi-Spec is also the unrestricted custom-buff workspace. Keep every
-- Retail specialization addressable here, even when MSUF ships no built-in
-- indicators for it, so DPS and tank specs can track arbitrary exact Aura IDs.
-- customOnly keeps those empty specs out of the single-spec preset picker.
Spec("DEATHKNIGHT", 1, "BloodDeathKnight", 250)
Spec("DEATHKNIGHT", 2, "FrostDeathKnight", 251)
Spec("DEATHKNIGHT", 3, "UnholyDeathKnight", 252)
Spec("DEMONHUNTER", 1, "HavocDemonHunter", 577)
Spec("DEMONHUNTER", 2, "VengeanceDemonHunter", 581)
Spec("DEMONHUNTER", 3, "DevourerDemonHunter", 1480)
Spec("DRUID", 1, "BalanceDruid", 102)
Spec("DRUID", 2, "FeralDruid", 103)
Spec("DRUID", 3, "GuardianDruid", 104)
Spec("DRUID", 4, "RestorationDruid", 105, true)
Spec("EVOKER", 1, "DevastationEvoker", 1467)
Spec("EVOKER", 2, "PreservationEvoker", 1468, true)
Spec("EVOKER", 3, "AugmentationEvoker", 1473, true)
Spec("HUNTER", 1, "BeastMasteryHunter", 253)
Spec("HUNTER", 2, "MarksmanshipHunter", 254)
Spec("HUNTER", 3, "SurvivalHunter", 255)
Spec("MAGE", 1, "ArcaneMage", 62)
Spec("MAGE", 2, "FireMage", 63)
Spec("MAGE", 3, "FrostMage", 64)
Spec("MONK", 1, "BrewmasterMonk", 268)
Spec("MONK", 2, "MistweaverMonk", 270, true)
Spec("MONK", 3, "WindwalkerMonk", 269)
Spec("PALADIN", 1, "HolyPaladin", 65, true)
Spec("PALADIN", 2, "ProtectionPaladin", 66, true)
Spec("PALADIN", 3, "RetributionPaladin", 70, true)
Spec("PRIEST", 1, "DisciplinePriest", 256, true)
Spec("PRIEST", 2, "HolyPriest", 257, true)
Spec("PRIEST", 3, "ShadowPriest", 258, true)
Spec("ROGUE", 1, "AssassinationRogue", 259)
Spec("ROGUE", 2, "OutlawRogue", 260)
Spec("ROGUE", 3, "SubtletyRogue", 261)
Spec("SHAMAN", 1, "ElementalShaman", 262)
Spec("SHAMAN", 2, "EnhancementShaman", 263)
Spec("SHAMAN", 3, "RestorationShaman", 264, true)
Spec("WARLOCK", 1, "AfflictionWarlock", 265)
Spec("WARLOCK", 2, "DemonologyWarlock", 266)
Spec("WARLOCK", 3, "DestructionWarlock", 267)
Spec("WARRIOR", 1, "ArmsWarrior", 71)
Spec("WARRIOR", 2, "FuryWarrior", 72)
Spec("WARRIOR", 3, "ProtectionWarrior", 73)

-- Shared Multi-Spec workspace. Custom entries stored under this key compile
-- once whenever Multi-Spec is active and therefore apply to every WoW spec.
SI.ALL_SPECS_KEY = "AllSpecs"
SI.SpecInfo[SI.ALL_SPECS_KEY] = {
  display = "All Specs (Shared)",
  customOnly = true,
  universal = true,
}

local PALADIN_BLESSING_IDS = {
  BlessingOfProtection = 1022,
  BlessingOfSacrifice  = 6940,
  BlessingOfFreedom    = 1044,
}

--- Static data contract: every Spec entry must have SpellIDs, TrackableAuras,
--- SpecDefaults, and icons for each exposed/default/secret aura. Keep new aura
--- data in these declarative tables so the repo smoke suite can validate it
--- without booting the WoW client.
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
    WealAndWoe      = 390787,
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
  ProtectionPaladin = PALADIN_BLESSING_IDS,
  RetributionPaladin = PALADIN_BLESSING_IDS,
}

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

--- User-entered custom buff IDs can be spellbook override IDs while UnitAura
--- exposes the base aura spellId. Compilers expand these only for custom IDs.
SI.AuraSpellIDAliases = {
  [403876] = { 498 }, -- Divine Protection override -> aura/base
  [498] = { 403876 }, -- Divine Protection aura/base -> override
  [642] = { 63148 }, -- Divine Shield cast -> aura
  [63148] = { 642 }, -- Divine Shield aura -> cast
}
SI.CustomAuraAliases = SI.AuraSpellIDAliases

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

local PALADIN_SECRET_BLESSINGS = PALADIN_BLESSING_IDS

SI.SecretSpellIDs = {
  PreservationEvoker = { TimeDilation = 357170, Rewind = 363534, VerdantEmbrace = 409895 },
  AugmentationEvoker = { SensePower = 361022 },
  RestorationDruid  = { IronBark = 102342 },
  DisciplinePriest  = { PainSuppression = 33206, PowerInfusion = 10060 },
  HolyPriest        = { GuardianSpirit = 47788, PowerInfusion = 10060 },
  ShadowPriest      = { PowerInfusion = 10060 },
  MistweaverMonk    = { LifeCocoon = 116849, StrengthOfTheBlackOx = 443113 },
  HolyPaladin       = { BlessingOfProtection = 1022, HolyArmaments = 432502, BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044 },
  ProtectionPaladin = PALADIN_SECRET_BLESSINGS,
  RetributionPaladin = PALADIN_SECRET_BLESSINGS,
}

-- Built-in Spell Icons that Blizzard's 12.1 aura system classifies through
-- HELPFUL|EXTERNAL_DEFENSIVE. Keep this explicit instead of inferring from a
-- spell name or the opaque SecretAuraInfo signature: both the compiler and
-- Menu2 need the same stable answer before aura data exists.
local PALADIN_EXTERNAL_DEFENSIVES = {
  BlessingOfProtection = true,
  BlessingOfSacrifice = true,
}
SI.ExternalDefensiveAuras = {
  PreservationEvoker = { TimeDilation = true },
  RestorationDruid = { IronBark = true },
  DisciplinePriest = { PainSuppression = true },
  HolyPriest = { GuardianSpirit = true },
  MistweaverMonk = { LifeCocoon = true },
  HolyPaladin = PALADIN_EXTERNAL_DEFENSIVES,
  ProtectionPaladin = PALADIN_EXTERNAL_DEFENSIVES,
  RetributionPaladin = PALADIN_EXTERNAL_DEFENSIVES,
}

local function Sig(signature)
  return { signature = signature }
end

local PALADIN_SECRET_BLESSING_INFO = {
  BlessingOfProtection = Sig("1:1:1:1"),
  BlessingOfSacrifice  = Sig("1:1:1:0"),
  BlessingOfFreedom    = Sig("1:0:0:1"),
}

SI.SecretAuraInfo = {
  PreservationEvoker = {
    TimeDilation   = Sig("1:1:1:0"),
    Rewind         = Sig("1:1:0:0"),
    VerdantEmbrace = Sig("0:1:0:0"),
  },
  AugmentationEvoker = {
    SensePower = Sig("0:1:0:0"),
  },
  RestorationDruid = {
    IronBark = Sig("1:1:1:0"),
  },
  DisciplinePriest = {
    PainSuppression = Sig("1:1:1:0"),
    PowerInfusion   = Sig("1:0:0:1"),
  },
  HolyPriest = {
    GuardianSpirit = Sig("1:1:1:0"),
    PowerInfusion  = Sig("1:0:0:1"),
  },
  ShadowPriest = {
    PowerInfusion = Sig("1:0:0:1"),
  },
  MistweaverMonk = {
    LifeCocoon           = Sig("1:1:1:0"),
    StrengthOfTheBlackOx = Sig("0:1:0:1"),
  },
  HolyPaladin = {
    BlessingOfProtection = Sig("1:1:1:1"),
    HolyArmaments        = Sig("0:1:0:0"),
    BlessingOfSacrifice  = Sig("1:1:1:0"),
    BlessingOfFreedom    = Sig("1:0:0:1"),
  },
  ProtectionPaladin = PALADIN_SECRET_BLESSING_INFO,
  RetributionPaladin = PALADIN_SECRET_BLESSING_INFO,
}

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

SI.IconTextures = {
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
  Prescience      = 5199639,
  ShiftingSands   = 5199633,
  BlisteringScales = 5199621,
  InfernosBlessing = 5199632,
  SymbioticBloom  = 4554354,
  EbonMight       = 5061347,
  SourceOfMagic   = 4630412,
  SensePower      = 132160,
  Rejuvenation    = 136081,
  Regrowth        = 136085,
  Lifebloom       = 134206,
  Germination     = 1033478,
  WildGrowth      = 236153,
  SymbioticRelationship = 1408837,
  SymbioticBlooms = 463540,
  IronBark        = 572025,
  PowerWordShield = 135940,
  Atonement       = 458720,
  PrayerOfMending = 135944,
  WealAndWoe      = 135940,
  VoidShield      = 7514191,
  PainSuppression = 135936,
  PowerInfusion   = 135939,
  Renew           = 135953,
  EchoOfLight     = 237537,
  GuardianSpirit  = 237542,
  RenewingMist    = 627487,
  EnvelopingMist  = 775461,
  SoothingMist    = 606550,
  AspectOfHarmony = 5927638,
  Coalescence     = "Interface\\Icons\\ability_monk_effuse",
  LifeCocoon      = 627485,
  StrengthOfTheBlackOx = 615340,
  Riptide         = 252995,
  EarthShield     = 136089,
  AncestralVigor  = 237574,
  EarthlivingWeapon = 237578,
  Hydrobubble     = 1320371,
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

local AURA_LABELS = {
  SourceOfMagic = "Source of Magic",
  IronBark = "Ironbark",
  PowerWordShield = "PW: Shield",
  PrayerOfMending = "Prayer of Mending",
  WealAndWoe = "Weal and Woe",
  EchoOfLight = "Echo of Light",
  AspectOfHarmony = "Aspect of Harmony",
  StrengthOfTheBlackOx = "Strength of the Black Ox",
  BeaconOfLight = "Beacon of Light",
  BeaconOfFaith = "Beacon of Faith",
  BeaconOfVirtue = "Beacon of Virtue",
  BeaconOfTheSavior = "Beacon of the Savior",
  BlessingOfProtection = "Blessing of Protection",
  BlessingOfSacrifice = "Blessing of Sacrifice",
  BlessingOfFreedom = "Blessing of Freedom",
}

local function Aura(name, r, g, b, secret)
  return { name = name, display = AURA_LABELS[name] or name:gsub("(%l)(%u)", "%1 %2"), color = { r, g, b }, secret = secret or nil }
end

local PALADIN_TRACKABLE_BLESSINGS = {
  Aura("BlessingOfProtection", 0.94, 0.82, 0.31, true),
  Aura("BlessingOfSacrifice", 0.94, 0.50, 0.50, true),
  Aura("BlessingOfFreedom", 0.47, 0.77, 1.00, true),
}

SI.TrackableAuras = {
  PreservationEvoker = {
    Aura("Echo", 0.31, 0.76, 0.97),
    Aura("Reversion", 0.51, 0.78, 0.52),
    Aura("EchoReversion", 0.40, 0.77, 0.74),
    Aura("DreamBreath", 0.47, 0.87, 0.47),
    Aura("EchoDreamBreath", 0.36, 0.82, 0.60),
    Aura("DreamFlight", 0.81, 0.58, 0.93),
    Aura("Lifebind", 0.94, 0.50, 0.50),
    Aura("TimeDilation", 0.94, 0.82, 0.31, true),
    Aura("Rewind", 0.74, 0.85, 0.40, true),
    Aura("VerdantEmbrace", 0.47, 0.87, 0.47, true),
  },
  AugmentationEvoker = {
    Aura("Prescience", 0.81, 0.58, 0.85),
    Aura("ShiftingSands", 1.00, 0.84, 0.28),
    Aura("BlisteringScales", 0.94, 0.50, 0.50),
    Aura("InfernosBlessing", 1.00, 0.60, 0.28),
    Aura("SymbioticBloom", 0.51, 0.78, 0.52),
    Aura("EbonMight", 0.62, 0.47, 0.85),
    Aura("SourceOfMagic", 0.31, 0.76, 0.97),
    Aura("SensePower", 0.94, 0.82, 0.31, true),
  },
  RestorationDruid = {
    Aura("Rejuvenation", 0.51, 0.78, 0.52),
    Aura("Regrowth", 0.31, 0.76, 0.97),
    Aura("Lifebloom", 0.56, 0.93, 0.56),
    Aura("Germination", 0.77, 0.89, 0.42),
    Aura("WildGrowth", 0.81, 0.58, 0.93),
    Aura("SymbioticRelationship", 0.40, 0.77, 0.74),
    Aura("SymbioticBlooms", 0.45, 0.82, 0.55),
    Aura("IronBark", 0.65, 0.47, 0.33, true),
  },
  DisciplinePriest = {
    Aura("Atonement", 0.94, 0.50, 0.50),
    Aura("PowerWordShield", 1.00, 0.84, 0.28),
    Aura("PrayerOfMending", 0.56, 0.93, 0.56),
    Aura("WealAndWoe", 0.94, 0.82, 0.31),
    Aura("VoidShield", 0.49, 0.77, 1.00),
    Aura("PainSuppression", 0.81, 0.58, 0.93, true),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, true),
  },
  HolyPriest = {
    Aura("Renew", 0.56, 0.93, 0.56),
    Aura("EchoOfLight", 1.00, 0.84, 0.28),
    Aura("PrayerOfMending", 0.81, 0.58, 0.93),
    Aura("GuardianSpirit", 0.94, 0.50, 0.50, true),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, true),
  },
  ShadowPriest = {
    Aura("PowerInfusion", 0.94, 0.82, 0.31, true),
  },
  MistweaverMonk = {
    Aura("RenewingMist", 0.56, 0.93, 0.56),
    Aura("EnvelopingMist", 0.31, 0.76, 0.97),
    Aura("SoothingMist", 0.47, 0.87, 0.47),
    Aura("AspectOfHarmony", 0.81, 0.58, 0.93),
    Aura("Coalescence", 0.31, 0.76, 0.97),
    Aura("LifeCocoon", 0.31, 0.76, 0.97, true),
    Aura("StrengthOfTheBlackOx", 0.40, 0.77, 0.74, true),
  },
  RestorationShaman = {
    Aura("Riptide", 0.31, 0.76, 0.97),
    Aura("EarthShield", 0.65, 0.47, 0.33),
    Aura("AncestralVigor", 0.56, 0.93, 0.56),
    Aura("EarthlivingWeapon", 0.47, 0.87, 0.47),
    Aura("Hydrobubble", 0.31, 0.76, 0.97),
  },
  HolyPaladin = {
    Aura("BeaconOfLight", 1.00, 0.93, 0.47),
    Aura("BeaconOfFaith", 1.00, 0.84, 0.28),
    Aura("BeaconOfVirtue", 1.00, 0.88, 0.37),
    Aura("BeaconOfTheSavior", 0.93, 0.80, 0.47),
    Aura("EternalFlame", 1.00, 0.60, 0.28),
    Aura("Dawnlight", 1.00, 0.85, 0.40),
    PALADIN_TRACKABLE_BLESSINGS[1],
    Aura("HolyArmaments", 0.81, 0.58, 0.93, true),
    PALADIN_TRACKABLE_BLESSINGS[2],
    PALADIN_TRACKABLE_BLESSINGS[3],
  },
  ProtectionPaladin = {
    PALADIN_TRACKABLE_BLESSINGS[1],
    PALADIN_TRACKABLE_BLESSINGS[2],
    PALADIN_TRACKABLE_BLESSINGS[3],
  },
  RetributionPaladin = PALADIN_TRACKABLE_BLESSINGS,
}

local function Placed(kind, anchor, x, y, size)
  return { placed = { type = kind, anchor = anchor, x = x, y = y, size = size } }
end

local function Frame(kind, r, g, b, a, priority)
  priority = tonumber(priority) or 1
  local index = math.max(0, math.floor(priority + 0.5) - 1)
  return {
    placed = { type = "icon", anchor = "RIGHT", x = 2 + (index * 22), y = 0, size = 20 },
    frame = { type = kind, color = { r, g, b, a }, priority = priority },
  }
end

local function PlacedFrame(kind, anchor, x, y, size, frameKind, r, g, b, a, priority)
  return {
    placed = { type = kind, anchor = anchor, x = x, y = y, size = size },
    frame = { type = frameKind, color = { r, g, b, a }, priority = priority },
  }
end

local PALADIN_BLESSING_DEFAULTS = {
  BlessingOfProtection = Frame("border", 0.94, 0.82, 0.31, 1, 1),
  BlessingOfSacrifice = Frame("border", 0.94, 0.50, 0.50, 1, 2),
  BlessingOfFreedom = Frame("border", 0.47, 0.77, 1.00, 1, 3),
}

SI.SpecDefaults = {
  RestorationDruid = {
    Rejuvenation = Placed("icon", "TOPLEFT", 1, -1, 22),
    Regrowth = Placed("icon", "TOPRIGHT", -1, -1, 22),
    Lifebloom = Placed("icon", "BOTTOMLEFT", 1, 1, 22),
    WildGrowth = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    Germination = Placed("square", "BOTTOM", 0, 3, 9),
    SymbioticRelationship = Placed("square", "CENTER", -8, 0, 10),
    SymbioticBlooms = Placed("square", "CENTER", 8, 0, 10),
    IronBark = Frame("border", 0.65, 0.47, 0.33, 1, 1),
  },
  DisciplinePriest = {
    Atonement = PlacedFrame("square", "TOPLEFT", 2, -2, 11, "healthtint", 0.94, 0.82, 0.31, 0.20, 5),
    PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    PrayerOfMending = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    WealAndWoe = Placed("icon", "BOTTOM", 0, 1, 20),
    VoidShield = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    PainSuppression = Frame("border", 0.81, 0.58, 0.93, 1, 1),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
  },
  HolyPriest = {
    Renew = Placed("icon", "TOPLEFT", 1, -1, 22),
    PrayerOfMending = Placed("icon", "TOPRIGHT", -1, -1, 20),
    EchoOfLight = Placed("square", "BOTTOMLEFT", 2, 2, 9),
    GuardianSpirit = Frame("border", 0.94, 0.50, 0.50, 1, 1),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
  },
  ShadowPriest = {
    PowerInfusion = PlacedFrame("icon", "TOPRIGHT", -1, -1, 22, "glow", 0.94, 0.82, 0.31, 1, 1),
  },
  PreservationEvoker = {
    Echo = PlacedFrame("icon", "TOPLEFT", 1, -1, 22, "namecolor", 0.31, 0.76, 0.97, 1, 5),
    Reversion = Placed("icon", "TOPRIGHT", -1, -1, 22),
    EchoReversion = Placed("square", "TOP", 0, -3, 10),
    DreamBreath = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    EchoDreamBreath = Placed("square", "BOTTOM", 0, 3, 10),
    Lifebind = Placed("square", "CENTER", 0, 0, 11),
    TimeDilation = Frame("border", 0.94, 0.82, 0.31, 1, 1),
    Rewind = Frame("glow", 0.74, 0.85, 0.40, 1, 2),
    DreamFlight = Frame("glow", 0.81, 0.58, 0.93, 1, 3),
    VerdantEmbrace = Placed("square", "CENTER", 12, 0, 10),
  },
  AugmentationEvoker = {
    EbonMight = PlacedFrame("icon", "TOPLEFT", 1, -1, 24, "healthtint", 0.62, 0.47, 0.85, 0.20, 5),
    Prescience = PlacedFrame("icon", "TOPRIGHT", -1, -1, 24, "namecolor", 0.81, 0.58, 0.85, 1, 5),
    BlisteringScales = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    InfernosBlessing = Placed("square", "BOTTOMLEFT", 2, 2, 9),
    SymbioticBloom = Placed("square", "BOTTOM", 0, 3, 9),
    SourceOfMagic = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    ShiftingSands = Placed("square", "CENTER", -8, 0, 9),
    SensePower = Frame("border", 0.94, 0.82, 0.31, 1, 1),
  },
  MistweaverMonk = {
    RenewingMist = Placed("icon", "TOPLEFT", 1, -1, 22),
    EnvelopingMist = Placed("icon", "TOPRIGHT", -1, -1, 22),
    SoothingMist = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    AspectOfHarmony = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    Coalescence = Placed("icon", "BOTTOM", 0, 1, 20),
    LifeCocoon = Frame("border", 0.31, 0.76, 0.97, 1, 1),
    StrengthOfTheBlackOx = Frame("border", 0.40, 0.77, 0.74, 1, 2),
  },
  RestorationShaman = {
    Riptide = Placed("icon", "TOPLEFT", 1, -1, 22),
    EarthShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    AncestralVigor = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    EarthlivingWeapon = Placed("square", "BOTTOMLEFT", 2, 2, 9),
    Hydrobubble = Placed("square", "BOTTOM", 0, 3, 9),
  },
  HolyPaladin = {
    BeaconOfLight = Placed("icon", "TOPLEFT", 1, -1, 24),
    BeaconOfFaith = Placed("icon", "TOPRIGHT", -1, -1, 24),
    BeaconOfVirtue = Placed("icon", "TOP", 0, -1, 22),
    BeaconOfTheSavior = Placed("square", "CENTER", -8, 0, 10),
    EternalFlame = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    Dawnlight = Placed("square", "BOTTOM", 0, 3, 9),
    BlessingOfProtection = PALADIN_BLESSING_DEFAULTS.BlessingOfProtection,
    HolyArmaments = Frame("glow", 0.81, 0.58, 0.93, 1, 4),
    BlessingOfSacrifice = PALADIN_BLESSING_DEFAULTS.BlessingOfSacrifice,
    BlessingOfFreedom = PALADIN_BLESSING_DEFAULTS.BlessingOfFreedom,
  },
  ProtectionPaladin = {
    BlessingOfProtection = PALADIN_BLESSING_DEFAULTS.BlessingOfProtection,
    BlessingOfSacrifice = PALADIN_BLESSING_DEFAULTS.BlessingOfSacrifice,
    BlessingOfFreedom = PALADIN_BLESSING_DEFAULTS.BlessingOfFreedom,
  },
  RetributionPaladin = PALADIN_BLESSING_DEFAULTS,
}

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
  local secrets = SI.SecretSpellIDs[specKey]
  if secrets then
    for auraName, spellId in pairs(secrets) do
      lookup[spellId] = auraName
    end
  end
  return lookup
end

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

function SI.GetAuraIcon(specKey, auraName)
  local tex = SI.IconTextures[auraName]
  if tex then return tex end
  local ids = SI.SpellIDs[specKey]
  local sid = tonumber(auraName) or (ids and ids[auraName])
  if not sid then
    local list = SI.TrackableAuras and SI.TrackableAuras[specKey]
    if type(list) == "table" then
      for i = 1, #list do
        local info = list[i]
        if info and info.name == auraName then
          sid = tonumber(info.spellID or info.spellId or info.id)
          break
        end
      end
    end
  end
  if sid and C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(sid)
    if t then return t end
  end
  return 136243 -- question mark
end

ExportPublic("MSUF_GF_SpellIndicators", SI)
