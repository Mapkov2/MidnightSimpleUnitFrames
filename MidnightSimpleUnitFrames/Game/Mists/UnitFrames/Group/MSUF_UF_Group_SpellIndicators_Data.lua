--- Mists Classic group spell indicators.
--- Spell baseline: WeakAuras Mists templates, 2026-08-02.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
local SI = ns.GF and ns.GF.SpellIndicators
if not SI then return end

local Spec, Aura = SI.DefineClassicSpec, SI.ClassicAura
local Placed, Frame = SI.ClassicPlaced, SI.ClassicFrame

Spec("DRUID", 4, "RestorationDruid", 105)
Spec("SHAMAN", 3, "RestorationShaman", 264)
Spec("PRIEST", 1, "DisciplinePriest", 256)
Spec("PRIEST", 2, "HolyPriest", 257)
Spec("PRIEST", 3, "ShadowPriest", 258)
Spec("PALADIN", 1, "HolyPaladin", 65)
Spec("PALADIN", 2, "ProtectionPaladin", 66)
Spec("PALADIN", 3, "RetributionPaladin", 70)
Spec("MONK", 2, "MistweaverMonk", 270)

local HANDS = {
  HandOfProtection = 1022,
  HandOfSacrifice = 6940,
  HandOfFreedom = 1044,
}

SI.SpellIDs = {
  RestorationDruid = {
    Rejuvenation = 774, Regrowth = 8936, Lifebloom = 33763,
    WildGrowth = 48438, Ironbark = 102342,
  },
  RestorationShaman = {
    EarthShield = 974, Earthliving = 51945, Riptide = 61295,
    AncestralVigor = 105284,
  },
  DisciplinePriest = {
    PowerWordShield = 17, PrayerOfMending = 41635,
    PainSuppression = 33206, PowerInfusion = 10060,
  },
  HolyPriest = {
    Renew = 139, PrayerOfMending = 41635,
    GuardianSpirit = 47788, PowerInfusion = 10060,
  },
  ShadowPriest = { PowerInfusion = 10060 },
  HolyPaladin = {
    BeaconOfLight = 53563, EternalFlame = 114163,
    HandOfProtection = 1022, HandOfSacrifice = 6940, HandOfFreedom = 1044,
  },
  ProtectionPaladin = HANDS,
  RetributionPaladin = HANDS,
  MistweaverMonk = {
    SoothingMist = 115175, LifeCocoon = 116849,
    RenewingMist = 119611, EnvelopingMist = 132120,
  },
}

SI.ExternalDefensiveAuras = {
  RestorationDruid = { Ironbark = true },
  DisciplinePriest = { PainSuppression = true },
  HolyPriest = { GuardianSpirit = true },
  HolyPaladin = { HandOfProtection = true, HandOfSacrifice = true },
  ProtectionPaladin = { HandOfProtection = true, HandOfSacrifice = true },
  RetributionPaladin = { HandOfProtection = true, HandOfSacrifice = true },
  MistweaverMonk = { LifeCocoon = true },
}

local HAND_AURAS = {
  Aura("HandOfProtection", 0.94, 0.82, 0.31, "Hand of Protection"),
  Aura("HandOfSacrifice", 0.94, 0.50, 0.50, "Hand of Sacrifice"),
  Aura("HandOfFreedom", 0.47, 0.77, 1.00, "Hand of Freedom"),
}
SI.TrackableAuras = {
  RestorationDruid = {
    Aura("Rejuvenation", 0.51, 0.78, 0.52), Aura("Regrowth", 0.31, 0.76, 0.97),
    Aura("Lifebloom", 0.56, 0.93, 0.56), Aura("WildGrowth", 0.81, 0.58, 0.93, "Wild Growth"),
    Aura("Ironbark", 0.65, 0.47, 0.33),
  },
  RestorationShaman = {
    Aura("Riptide", 0.31, 0.76, 0.97), Aura("EarthShield", 0.65, 0.47, 0.33, "Earth Shield"),
    Aura("AncestralVigor", 0.56, 0.93, 0.56, "Ancestral Vigor"),
    Aura("Earthliving", 0.47, 0.87, 0.47),
  },
  DisciplinePriest = {
    Aura("PowerWordShield", 1.00, 0.84, 0.28, "PW: Shield"),
    Aura("PrayerOfMending", 0.56, 0.93, 0.56, "Prayer of Mending"),
    Aura("PainSuppression", 0.81, 0.58, 0.93, "Pain Suppression"),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion"),
  },
  HolyPriest = {
    Aura("Renew", 0.56, 0.93, 0.56),
    Aura("PrayerOfMending", 0.81, 0.58, 0.93, "Prayer of Mending"),
    Aura("GuardianSpirit", 0.94, 0.50, 0.50, "Guardian Spirit"),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion"),
  },
  ShadowPriest = { Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion") },
  HolyPaladin = {
    Aura("BeaconOfLight", 1.00, 0.93, 0.47, "Beacon of Light"),
    Aura("EternalFlame", 1.00, 0.60, 0.28, "Eternal Flame"),
    HAND_AURAS[1], HAND_AURAS[2], HAND_AURAS[3],
  },
  ProtectionPaladin = { HAND_AURAS[1], HAND_AURAS[2], HAND_AURAS[3] },
  RetributionPaladin = HAND_AURAS,
  MistweaverMonk = {
    Aura("RenewingMist", 0.56, 0.93, 0.56, "Renewing Mist"),
    Aura("EnvelopingMist", 0.31, 0.76, 0.97, "Enveloping Mist"),
    Aura("SoothingMist", 0.47, 0.87, 0.47, "Soothing Mist"),
    Aura("LifeCocoon", 0.31, 0.76, 0.97, "Life Cocoon"),
  },
}

local HAND_DEFAULTS = {
  HandOfProtection = Frame("border", 0.94, 0.82, 0.31, 1, 1),
  HandOfSacrifice = Frame("border", 0.94, 0.50, 0.50, 1, 2),
  HandOfFreedom = Frame("border", 0.47, 0.77, 1.00, 1, 3),
}
SI.SpecDefaults = {
  RestorationDruid = {
    Rejuvenation = Placed("icon", "TOPLEFT", 1, -1, 22),
    Regrowth = Placed("icon", "TOPRIGHT", -1, -1, 22),
    Lifebloom = Placed("icon", "BOTTOMLEFT", 1, 1, 22),
    WildGrowth = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    Ironbark = Frame("border", 0.65, 0.47, 0.33, 1, 1),
  },
  RestorationShaman = {
    Riptide = Placed("icon", "TOPLEFT", 1, -1, 22),
    EarthShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    AncestralVigor = Placed("square", "BOTTOMRIGHT", -3, 3, 9),
    Earthliving = Placed("square", "BOTTOMLEFT", 2, 2, 9),
  },
  DisciplinePriest = {
    PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    PrayerOfMending = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    PainSuppression = Frame("border", 0.81, 0.58, 0.93, 1, 1),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
  },
  HolyPriest = {
    Renew = Placed("icon", "TOPLEFT", 1, -1, 22),
    PrayerOfMending = Placed("icon", "TOPRIGHT", -1, -1, 20),
    GuardianSpirit = Frame("border", 0.94, 0.50, 0.50, 1, 1),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
  },
  ShadowPriest = { PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 1) },
  HolyPaladin = {
    BeaconOfLight = Placed("icon", "TOPLEFT", 1, -1, 24),
    EternalFlame = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    HandOfProtection = HAND_DEFAULTS.HandOfProtection,
    HandOfSacrifice = HAND_DEFAULTS.HandOfSacrifice,
    HandOfFreedom = HAND_DEFAULTS.HandOfFreedom,
  },
  ProtectionPaladin = HAND_DEFAULTS,
  RetributionPaladin = HAND_DEFAULTS,
  MistweaverMonk = {
    RenewingMist = Placed("icon", "TOPLEFT", 1, -1, 22),
    EnvelopingMist = Placed("icon", "TOPRIGHT", -1, -1, 22),
    SoothingMist = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    LifeCocoon = Frame("border", 0.31, 0.76, 0.97, 1, 1),
  },
}
