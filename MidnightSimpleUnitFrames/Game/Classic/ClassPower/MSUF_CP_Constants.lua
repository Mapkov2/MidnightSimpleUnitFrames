--- MSUF_CP_Constants.lua
--- Phase 1 ClassPower split: shared constants/data extracted from the core file.
--- Loaded before the ClassPower controller.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_CP_CONST", _G.MSUF_CP_CONST or {})
local K = _G.MSUF_CP_CONST

K.CPK = {
    MODE = {
        NONE           = 0,
        SEGMENTED      = 1,
        FRACTIONAL     = 2,
        RUNE_CD        = 3,
        AURA_SEGMENTED = 4,
        AURA_SINGLE    = 5,
        CONTINUOUS     = 6,
        TIMER_BAR      = 8,
        STAGGER        = 9,
        IRONFUR        = 10,
        SIGNED_CONTINUOUS = 11,
    },
    SPEC = {
        DH_DEVOURER          = _G.SPEC_DEMONHUNTER_DEVOURER or 3,
        MAGE_ARCANE          = _G.SPEC_MAGE_ARCANE or 1,
        MAGE_FROST           = 3,
        MONK_WINDWALKER      = _G.SPEC_MONK_WINDWALKER or 3,
        MONK_BREWMASTER      = _G.SPEC_MONK_BREWMASTER or 1,
        SHAMAN_ENHANCEMENT   = 2,
        SHAMAN_ELEMENTAL     = 1,
        WARLOCK_DESTRUCTION  = _G.SPEC_WARLOCK_DESTRUCTION or 3,
        WARLOCK_DEMONOLOGY   = _G.SPEC_WARLOCK_DEMONOLOGY or 2,
        DH_VENGEANCE         = _G.SPEC_DEMONHUNTER_VENGEANCE or 2,
        HUNTER_SURVIVAL      = 3,
        EVOKER_AUG           = 3,
        PRIEST_SHADOW        = 3,
        DRUID_GUARDIAN       = 3,
        DRUID_BALANCE        = _G.SPEC_DRUID_BALANCE or 1,
    },
    SPELL = {
        DARK_HEART             = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.DARK_HEART_SPELL_ID) or 1225789,
        SILENCE_THE_WHISPERS   = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.SILENCE_THE_WHISPERS_SPELL_ID) or 1227702,
        VOID_METAMORPHOSIS     = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.VOID_METAMORPHOSIS_SPELL_ID) or 1217607,
        MAELSTROM_WEAPON       = 344179,
        MAELSTROM_WEAPON_TALENT = 187880,
        ICICLES                = 205473,
        NATURES_BALANCE        = 406890,
        SOLAR_ECLIPSE          = 1233346,
        LUNAR_ECLIPSE          = 1233272,
        CELESTIAL_ALIGNMENT    = 194223,
        ORBITAL_STRIKE_CA      = 383410,
        INCARNATION_BOOMKIN    = 102560,
        ORBITAL_STRIKE_INC     = 390414,
        AP_WRATH               = 190984,
        AP_STARFIRE            = 194153,
        SOUL_CLEAVE            = 228477,
        MISTS_ARCANE_CHARGE    = 36032,
    },
    BAL = {
        CLR_SOLAR = { 0.82, 0.56, 0.25 },
        CLR_LUNAR = { 0.41, 0.49, 0.82 },
        CLR_CA    = { 0.30, 1.00, 0.43 },
        PRED_ALPHA = 0.50,
    },
    THRESH = {
        MW_SPEND = 5,
    },
}

K.WL_LOW_SHARD_THRESHOLD = {
    [K.CPK.SPEC.WARLOCK_DEMONOLOGY] = 3,
    [K.CPK.SPEC.WARLOCK_DESTRUCTION] = 2,
}

K.AP_GENERATORS = {
    [190984] = 6,
    [194153] = 8,
    [274281] = 10,
    [274282] = 20,
    [274283] = 40,
}

K.ECLIPSE_AURAS = {
    [K.CPK.SPELL.SOLAR_ECLIPSE]       = "SOLAR",
    [K.CPK.SPELL.LUNAR_ECLIPSE]       = "LUNAR",
    [K.CPK.SPELL.CELESTIAL_ALIGNMENT] = "CA",
    [K.CPK.SPELL.ORBITAL_STRIKE_CA]   = "CA",
    [K.CPK.SPELL.INCARNATION_BOOMKIN] = "INC",
    [K.CPK.SPELL.ORBITAL_STRIKE_INC]  = "INC",
}

K.WL_SHARD_DELTAS = {
    [1] = { [686] = 1 },
    [2] = { [686] = 1, [264178] = 2 },
    [3] = { [29722] = 0.2, [116858] = -2.0 },
}

K.ICICLES = {
    AURA_ID    = 205473,
    MAX_STACKS = 5,
}

K.MISTS_ARCANE_CHARGES = {
    AURA_ID = K.CPK.SPELL.MISTS_ARCANE_CHARGE,
    MAX_STACKS = 4,
}

K.TIP = {
    TALENT_ID = 260285,
    AURA_ID = 260286,
    KILL_COMMAND = 259489,
    TWIN_FANG = 1272139,
    TAKEDOWN = 1250646,
    PRIMAL_SURGE = 1272154,
    MAX_STACKS = 3,
    DURATION = 10,
    SPENDERS = {
        [259495] = true, [259387] = true, [271788] = true, [187708] = true,
        [1217525] = true, [320976] = true, [1206791] = true, [271014] = true,
    },
}

K.EBON = {
    SPELL_ID = 395296,
    MAX_DURATION = 20,
}

K.STAGGER = {
    YELLOW_TRANSITION = _G.STAGGER_YELLOW_TRANSITION or 0.3,
    RED_TRANSITION = _G.STAGGER_RED_TRANSITION or 0.6,
    COLOR_DEFAULTS = {
        { 0.52, 1.00, 0.52 },
        { 1.00, 0.98, 0.72 },
        { 1.00, 0.42, 0.42 },
    },
    TOKENS = { "STAGGER_GREEN", "STAGGER_YELLOW", "STAGGER_RED" },
}

local E = Enum and Enum.PowerType
K.PT = {
    Mana          = (E and E.Mana) or 0,
    ComboPoints   = (E and E.ComboPoints) or 4,
    Runes         = (E and E.Runes) or 5,
    HolyPower     = (E and E.HolyPower) or 9,
    SoulShards    = (E and E.SoulShards) or 7,
    ArcaneCharges = (E and E.ArcaneCharges) or 16,
    Chi           = (E and E.Chi) or 12,
    Essence       = (E and E.Essence) or 19,
    LunarPower    = (E and E.LunarPower) or 8,
    Energy        = (E and E.Energy) or 3,
    Insanity      = (E and E.Insanity) or 13,
    Maelstrom     = (E and E.Maelstrom) or 11,
    Rage          = (E and E.Rage) or 1,
    BurningEmbers = (E and E.BurningEmbers) or 14,
    DemonicFury   = (E and E.DemonicFury) or 15,
    Balance       = (E and E.Balance) or 26,
    ShadowOrbs    = (E and E.ShadowOrbs) or 28,
}
K.PT_STAGGER = -1

K.POWER_TYPE_TOKENS = {
    [K.PT.ComboPoints]   = "COMBO_POINTS",
    [K.PT.Runes]         = "RUNES",
    [K.PT.HolyPower]     = "HOLY_POWER",
    [K.PT.SoulShards]    = "SOUL_SHARDS",
    [K.PT.ArcaneCharges] = "ARCANE_CHARGES",
    [K.PT.Chi]           = "CHI",
    [K.PT.Essence]       = "ESSENCE",
    [K.PT.Mana]          = "MANA",
    [K.PT.LunarPower]    = "ASTRAL_POWER",
    [K.PT.Insanity]      = "INSANITY",
    [K.PT.Maelstrom]     = "MAELSTROM",
    [K.PT.BurningEmbers] = "BURNING_EMBERS",
    [K.PT.DemonicFury]   = "DEMONIC_FURY",
    [K.PT.Balance]       = "BALANCE",
    [K.PT.ShadowOrbs]    = "SHADOW_ORBS",
    ["SOUL_FRAGMENTS"]      = "SOUL_FRAGMENTS",
    ["SOUL_FRAGMENTS_VENG"] = "SOUL_FRAGMENTS_VENG",
    ["MAELSTROM_WEAPON"]    = "MAELSTROM",
    ["STAGGER"]             = "STAGGER",
    ["WHIRLWIND"]           = "WHIRLWIND",
    ["TIP_OF_THE_SPEAR"]    = "TIP_OF_THE_SPEAR",
    ["ICICLES"]             = "ICICLES",
    ["EBON_MIGHT"]          = "EBON_MIGHT",
    ["IRONFUR"]             = "IRONFUR",
    ["MISTS_ARCANE_CHARGES"] = "ARCANE_CHARGES",
}

K.MAX_CLASS_POWER = 10

--- Devourer Demon Hunter segment count.
--- Blizzard's own bar (DemonHunterSoulFragmentsBar:GetCurrentMinMaxPower) reads
--- an integer maximum: the collapsing star cost inside Void Metamorphosis, Dark
--- Heart's max cumulative applications outside it. Returning 1 means "not
--- usable as a segment count" and keeps the caller on the normalized
--- single-bar rendering, which is what older clients and secret-value states
--- get. The meta state is passed in because every caller already knows it.
function K.ResolveDevourerSegments(inMeta, notSecret)
    local raw
    if inMeta then
        local cost = _G.GetCollapsingStarCost
        raw = (type(cost) == "function") and cost() or nil
    else
        local C_Spell = _G.C_Spell
        local spellMax = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
        raw = (type(spellMax) == "function") and spellMax(K.CPK.SPELL.DARK_HEART) or nil
    end
    if type(notSecret) == "function" and not notSecret(raw) then return 1 end
    raw = math.floor((tonumber(raw) or 0) + 0.5)
    if raw < 2 then return 1 end
    if raw > K.MAX_CLASS_POWER then return K.MAX_CLASS_POWER end
    return raw
end

K.CDM_FRAMES = {
    cooldown      = "EssentialCooldownViewer",
    utility       = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}
K.CDM_HOOK_DEFS = {
    { name = "EssentialCooldownViewer", flag = "_ecvHooked", mode = "cooldown" },
    { name = "UtilityCooldownViewer", flag = "_ucvHooked", mode = "utility" },
    { name = "BuffIconCooldownViewer", flag = "_bicvHooked", mode = "tracked_buffs" },
}

--- Profiles (from MSUF_CP_Profiles.lua)
--- MSUF_CP_Profiles.lua
--- Phase 1 ClassPower split: data-only event profiles for active render modes.
--- Loaded before the ClassPower controller.

local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}

ExportPublic("MSUF_CP_MODE_EVENT_PROFILE", {
    [MODE.NONE]           = { power = false, maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.SEGMENTED]      = { power = true,  maxPower = true,  aura = false, rune = false, health = false, pointCharge = true,  warlockPred = false },
    [MODE.FRACTIONAL]     = { power = true,  maxPower = true,  aura = false, rune = false, health = false, pointCharge = false, warlockPred = true  },
    [MODE.RUNE_CD]        = { power = false, maxPower = false, aura = false, rune = true,  health = false, pointCharge = false, warlockPred = false },
    [MODE.AURA_SEGMENTED] = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.AURA_SINGLE]    = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.CONTINUOUS]     = { power = true,  maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.TIMER_BAR]      = { power = false, maxPower = false, aura = true,  rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.STAGGER]        = { power = false, maxPower = false, aura = true,  rune = false, health = true,  pointCharge = false, warlockPred = false },
    [MODE.IRONFUR]        = { power = false, maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
    [MODE.SIGNED_CONTINUOUS] = { power = true, maxPower = false, aura = false, rune = false, health = false, pointCharge = false, warlockPred = false },
})
