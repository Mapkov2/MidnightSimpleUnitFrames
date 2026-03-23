-- ============================================================================
-- MSUF_CP_Constants.lua
-- Phase 1 ClassPower split: shared constants/data extracted from the core file.
-- Loaded before Core/MSUF_ClassPower.lua.
-- ============================================================================

_G.MSUF_CP_CONST = _G.MSUF_CP_CONST or {}
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
    },
    SPEC = {
        DH_DEVOURER          = _G.SPEC_DEMONHUNTER_DEVOURER or 3,
        MAGE_ARCANE          = _G.SPEC_MAGE_ARCANE or 1,
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
    },
    SPELL = {
        DARK_HEART             = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.DARK_HEART_SPELL_ID) or 1225789,
        SILENCE_THE_WHISPERS   = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.SILENCE_THE_WHISPERS_SPELL_ID) or 1227702,
        VOID_METAMORPHOSIS     = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.VOID_METAMORPHOSIS_SPELL_ID) or 1217607,
        MAELSTROM_WEAPON       = 344179,
        MAELSTROM_WEAPON_TALENT = 187880,
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
    ["SOUL_FRAGMENTS"]      = "SOUL_FRAGMENTS",
    ["SOUL_FRAGMENTS_VENG"] = "SOUL_FRAGMENTS_VENG",
    ["MAELSTROM_WEAPON"]    = "MAELSTROM",
    ["STAGGER"]             = "STAGGER",
    ["WHIRLWIND"]           = "WHIRLWIND",
    ["TIP_OF_THE_SPEAR"]    = "TIP_OF_THE_SPEAR",
    ["EBON_MIGHT"]          = "EBON_MIGHT",
}

K.MAX_CLASS_POWER = 10
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
