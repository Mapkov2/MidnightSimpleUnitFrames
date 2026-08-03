--- TBC Classic group spell indicators.
--- Spell baseline: WeakAuras TBC templates, 2026-08-02.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
local SI = ns.GF and ns.GF.SpellIndicators
if not SI then return end

local Spec, Aura = SI.DefineClassicSpec, SI.ClassicAura
local Placed, Frame = SI.ClassicPlaced, SI.ClassicFrame

Spec("DRUID", 3, "RestorationDruid")
Spec("SHAMAN", 3, "RestorationShaman")
Spec("PRIEST", 1, "DisciplinePriest")
Spec("PRIEST", 2, "HolyPriest")
Spec("PRIEST", 3, "ShadowPriest")
Spec("PALADIN", 1, "HolyPaladin")
Spec("PALADIN", 2, "ProtectionPaladin")
Spec("PALADIN", 3, "RetributionPaladin")

local BLESSINGS = {
  BlessingOfProtection = 1022,
  BlessingOfSacrifice = 6940,
  BlessingOfFreedom = 1044,
}
SI.SpellIDs = {
  RestorationDruid = { Rejuvenation = 774, Regrowth = 8936, Lifebloom = 33763 },
  RestorationShaman = { EarthShield = 974 },
  DisciplinePriest = {
    PowerWordShield = 17, PrayerOfMending = 41635,
    PainSuppression = 33206, PowerInfusion = 10060,
  },
  HolyPriest = { PowerWordShield = 17, Renew = 139, PrayerOfMending = 41635 },
  ShadowPriest = { PowerInfusion = 10060 },
  HolyPaladin = BLESSINGS,
  ProtectionPaladin = BLESSINGS,
  RetributionPaladin = BLESSINGS,
}

SI.ExternalDefensiveAuras = {
  DisciplinePriest = { PainSuppression = true },
  HolyPaladin = { BlessingOfProtection = true, BlessingOfSacrifice = true },
  ProtectionPaladin = { BlessingOfProtection = true, BlessingOfSacrifice = true },
  RetributionPaladin = { BlessingOfProtection = true, BlessingOfSacrifice = true },
}

local BLESSING_AURAS = {
  Aura("BlessingOfProtection", 0.94, 0.82, 0.31, "Blessing of Protection"),
  Aura("BlessingOfSacrifice", 0.94, 0.50, 0.50, "Blessing of Sacrifice"),
  Aura("BlessingOfFreedom", 0.47, 0.77, 1.00, "Blessing of Freedom"),
}
SI.TrackableAuras = {
  RestorationDruid = {
    Aura("Rejuvenation", 0.51, 0.78, 0.52), Aura("Regrowth", 0.31, 0.76, 0.97),
    Aura("Lifebloom", 0.56, 0.93, 0.56),
  },
  RestorationShaman = { Aura("EarthShield", 0.65, 0.47, 0.33, "Earth Shield") },
  DisciplinePriest = {
    Aura("PowerWordShield", 1.00, 0.84, 0.28, "PW: Shield"),
    Aura("PrayerOfMending", 0.56, 0.93, 0.56, "Prayer of Mending"),
    Aura("PainSuppression", 0.81, 0.58, 0.93, "Pain Suppression"),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion"),
  },
  HolyPriest = {
    Aura("PowerWordShield", 1.00, 0.84, 0.28, "PW: Shield"),
    Aura("Renew", 0.56, 0.93, 0.56),
    Aura("PrayerOfMending", 0.81, 0.58, 0.93, "Prayer of Mending"),
  },
  ShadowPriest = { Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion") },
  HolyPaladin = { BLESSING_AURAS[1], BLESSING_AURAS[2], BLESSING_AURAS[3] },
  ProtectionPaladin = { BLESSING_AURAS[1], BLESSING_AURAS[2], BLESSING_AURAS[3] },
  RetributionPaladin = BLESSING_AURAS,
}

local BLESSING_DEFAULTS = {
  BlessingOfProtection = Frame("border", 0.94, 0.82, 0.31, 1, 1),
  BlessingOfSacrifice = Frame("border", 0.94, 0.50, 0.50, 1, 2),
  BlessingOfFreedom = Frame("border", 0.47, 0.77, 1.00, 1, 3),
}
SI.SpecDefaults = {
  RestorationDruid = {
    Rejuvenation = Placed("icon", "TOPLEFT", 1, -1, 22),
    Regrowth = Placed("icon", "TOPRIGHT", -1, -1, 22),
    Lifebloom = Placed("icon", "BOTTOMLEFT", 1, 1, 22),
  },
  RestorationShaman = { EarthShield = Placed("icon", "TOPRIGHT", -1, -1, 22) },
  DisciplinePriest = {
    PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    PrayerOfMending = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
    PainSuppression = Frame("border", 0.81, 0.58, 0.93, 1, 1),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
  },
  HolyPriest = {
    PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    Renew = Placed("icon", "TOPLEFT", 1, -1, 22),
    PrayerOfMending = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
  },
  ShadowPriest = { PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 1) },
  HolyPaladin = BLESSING_DEFAULTS,
  ProtectionPaladin = BLESSING_DEFAULTS,
  RetributionPaladin = BLESSING_DEFAULTS,
}
