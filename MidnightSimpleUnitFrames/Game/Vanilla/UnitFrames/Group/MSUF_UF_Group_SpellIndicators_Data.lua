--- Classic Era group spell indicators.
--- Era has no specialization API, so each supported class uses one combined set.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
local SI = ns.GF and ns.GF.SpellIndicators
if not SI then return end

local Spec, Aura = SI.DefineClassicSpec, SI.ClassicAura
local Placed, Frame = SI.ClassicPlaced, SI.ClassicFrame

Spec("DRUID", 0, "ClassicDruid")
Spec("SHAMAN", 0, "ClassicShaman")
Spec("PRIEST", 0, "ClassicPriest")
Spec("PALADIN", 0, "ClassicPaladin")

SI.SpellIDs = {
  ClassicDruid = { Rejuvenation = 774, Regrowth = 8936 },
  ClassicShaman = {},
  ClassicPriest = { PowerWordShield = 17, Renew = 139, PowerInfusion = 10060 },
  ClassicPaladin = {
    BlessingOfProtection = 1022, BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044,
  },
}

SI.ExternalDefensiveAuras = {
  ClassicPaladin = { BlessingOfProtection = true, BlessingOfSacrifice = true },
}

SI.TrackableAuras = {
  ClassicDruid = {
    Aura("Rejuvenation", 0.51, 0.78, 0.52),
    Aura("Regrowth", 0.31, 0.76, 0.97),
  },
  ClassicShaman = {},
  ClassicPriest = {
    Aura("PowerWordShield", 1.00, 0.84, 0.28, "PW: Shield"),
    Aura("Renew", 0.56, 0.93, 0.56),
    Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion"),
  },
  ClassicPaladin = {
    Aura("BlessingOfProtection", 0.94, 0.82, 0.31, "Blessing of Protection"),
    Aura("BlessingOfSacrifice", 0.94, 0.50, 0.50, "Blessing of Sacrifice"),
    Aura("BlessingOfFreedom", 0.47, 0.77, 1.00, "Blessing of Freedom"),
  },
}

SI.SpecDefaults = {
  ClassicDruid = {
    Rejuvenation = Placed("icon", "TOPLEFT", 1, -1, 22),
    Regrowth = Placed("icon", "TOPRIGHT", -1, -1, 22),
  },
  ClassicShaman = {},
  ClassicPriest = {
    PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
    Renew = Placed("icon", "TOPLEFT", 1, -1, 22),
    PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 1),
  },
  ClassicPaladin = {
    BlessingOfProtection = Frame("border", 0.94, 0.82, 0.31, 1, 1),
    BlessingOfSacrifice = Frame("border", 0.94, 0.50, 0.50, 1, 2),
    BlessingOfFreedom = Frame("border", 0.47, 0.77, 1.00, 1, 3),
  },
}
