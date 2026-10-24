--- MSUF_CP_Constants.lua
--- Phase 1 ClassPower split: shared constants/data extracted from the core file.
--- Loaded before the ClassPower controller.

local _, MSUF = ...
local ExportPublic = MSUF.ExportPublic

local K = MSUF.Optional("MSUF_CP_CONST") or {}
ExportPublic("MSUF_CP_CONST", K)

--- The builder registries the ClassPower files add their builders to. This
--- file loads first in every client TOC, so it publishes all three; a file
--- reads its registry with K.BuilderRegistry(name).
local builderRegistries = {
    MSUF_CP_CORE_BUILDERS = {},
    MSUF_CP_MODE_BUILDERS = {},
    MSUF_CP_FEATURE_BUILDERS = {},
}
ExportPublic("MSUF_CP_CORE_BUILDERS", builderRegistries.MSUF_CP_CORE_BUILDERS)
ExportPublic("MSUF_CP_MODE_BUILDERS", builderRegistries.MSUF_CP_MODE_BUILDERS)
ExportPublic("MSUF_CP_FEATURE_BUILDERS", builderRegistries.MSUF_CP_FEATURE_BUILDERS)
function K.BuilderRegistry(name)
    return builderRegistries[name]
end

--- The one reader of a class resource colour override: map[token] as
--- { r, g, b } or { r = , g = , b = }. Returns r, g, b, or nothing unless all
--- three are numbers. Every Colors panel override (class power, background,
--- charged, per slot, full, Stagger tiers, eclipse, text) is read through it.
function K.OverrideRGB(map, token)
    if type(map) ~= "table" or token == nil then return nil end
    local c = map[token]
    if type(c) ~= "table" then return nil end
    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end

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
        NATIVE_AURA    = 11,
    },
    SPEC = {
        DH_DEVOURER          = SPEC_DEMONHUNTER_DEVOURER or 3,
        MAGE_ARCANE          = SPEC_MAGE_ARCANE or 1,
        MAGE_FROST           = 3,
        MONK_WINDWALKER      = SPEC_MONK_WINDWALKER or 3,
        MONK_BREWMASTER      = SPEC_MONK_BREWMASTER or 1,
        SHAMAN_ENHANCEMENT   = 2,
        SHAMAN_ELEMENTAL     = 1,
        WARLOCK_DESTRUCTION  = SPEC_WARLOCK_DESTRUCTION or 3,
        WARLOCK_DEMONOLOGY   = SPEC_WARLOCK_DEMONOLOGY or 2,
        DH_VENGEANCE         = SPEC_DEMONHUNTER_VENGEANCE or 2,
        HUNTER_SURVIVAL      = 3,
        EVOKER_AUG           = 3,
        PRIEST_SHADOW        = 3,
        DRUID_GUARDIAN       = 3,
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

K.TIP = {
    TALENT_ID = 260285,
    KILL_COMMAND = 259489,
    TWIN_FANG = 1272139,
    TAKEDOWN = 1250646,
    TAKEDOWN_HIT = 1253859,
    PRIMAL_SURGE = 1272154,
    TWIN_FANG_GAIN = 3,
    MAX_STACKS = 3,
    DURATION = 10,
    SPENDERS = {
        [186270] = true,  -- Raptor Strike
        [265189] = true,  -- Raptor Strike (ranged)
        [1262293] = true, -- Raptor Swipe
        [1262343] = true, -- Raptor Swipe (ranged)
        [259495] = true,  -- Wildfire Bomb
        [193265] = true,  -- Hatchet Toss
        [1264949] = true, -- Chakram
        [1261193] = true, -- Boomstick
        [1253859] = true, -- Takedown impact
        [1251592] = true, -- Flamefang Pitch
    },
}

K.EBON = {
    SPELL_ID = 395296,
}

K.STAGGER = {
    YELLOW_TRANSITION = STAGGER_YELLOW_TRANSITION or 0.3,
    RED_TRANSITION = STAGGER_RED_TRANSITION or 0.6,
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
    ["ICICLES"]             = "ICICLES",
    ["EBON_MIGHT"]          = "EBON_MIGHT",
    ["IRONFUR"]             = "IRONFUR",
}

K.MAX_CLASS_POWER = 10

--- Devourer's Soul Fragment maximum is talent-dependent (30/35/50) and far
--- above MAX_CLASS_POWER, so the resource can never be one StatusBar per
--- fragment - that clamp is what made the fill saturate at ten fragments.
--- Its bar stays a single normalized fill and draws the fragment boundaries as
--- separator notches over it. A fragment count past this ceiling draws no
--- notches at all rather than dividers that no longer match the fragments.
K.MAX_FRAGMENT_NOTCHES = 64

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

--- Each mode owns its event, renderer, geometry and tick traits here.
--- Missing event traits are false; ordinary modes permit light power updates
--- and use only an already-active degraded Essence tick.
K.ModeDescriptors = {
    [K.CPK.MODE.NONE] = {},
    [K.CPK.MODE.SEGMENTED] = {
        updateKey = "Segmented", pipColors = true,
        power = true, maxPower = true, pointCharge = true, warlockPred = true,
    },
    [K.CPK.MODE.FRACTIONAL] = {
        updateKey = "Fractional", pipColors = true, power = true, maxPower = true, warlockPred = true,
    },
    [K.CPK.MODE.RUNE_CD] = {
        updateKey = "Rune", tick = "rune", powerUpdate = false, pipColors = true, barCount = 6, rune = true,
    },
    [K.CPK.MODE.AURA_SEGMENTED] = { updateKey = "AuraSegmented", pipColors = true, aura = true },
    [K.CPK.MODE.AURA_SINGLE] = { updateKey = "AuraSingle", barCount = 1, aura = true },
    [K.CPK.MODE.CONTINUOUS] = { updateKey = "Continuous", barCount = 1, power = true },
    [K.CPK.MODE.TIMER_BAR] = { updateKey = "Timer", tick = "none", powerUpdate = false, barCount = 1 },
    [K.CPK.MODE.STAGGER] = {
        updateKey = "Stagger", tick = "stagger", powerUpdate = false, barCount = 1, aura = true, health = true,
    },
    [K.CPK.MODE.IRONFUR] = { updateKey = "Ironfur", barCount = 1 },
    [K.CPK.MODE.NATIVE_AURA] = { updateKey = "NativeAura", barCount = 1 },
}
--- Compatibility event profiles share the same records; no second trait list.
ExportPublic("MSUF_CP_MODE_EVENT_PROFILE", K.ModeDescriptors)

function K.BindModeRunners(runners)
    for _, descriptor in pairs(K.ModeDescriptors) do
        descriptor.updateFn = runners[descriptor.updateKey]
    end
    --- Preserve the renderer inspection index as a view, without a second set
    --- of mode traits or bindings. Lazy Ironfur writes through to its descriptor.
    return setmetatable({}, {
        __index = function(_, mode)
            local descriptor = K.ModeDescriptors[mode]
            return descriptor and descriptor.updateFn
        end,
        __newindex = function(_, mode, updateFn) K.ModeDescriptors[mode].updateFn = updateFn end,
    })
end

local CPK, MODE = K.CPK, K.CPK.MODE

--- Classic flavors (MSUF.Client.IsClassic: Vanilla, TBC and Mists) load this
--- file as well. Their providers (Game/<Flavor>/ClassPower.lua) route the Mists
--- resources below and the Classic-only signed render mode; Mainline never
--- sees these keys.
if (MSUF.Client and MSUF.Client.IsClassic) == true then
    --- 11 is NATIVE_AURA. Mode ids key the hot-path dispatch tables, so a
    --- Classic-only mode takes the next free number instead of shadowing one.
    MODE.SIGNED_CONTINUOUS = 12
    CPK.SPELL.MISTS_ARCANE_CHARGE = 36032
    K.MISTS_ARCANE_CHARGES = {
        AURA_ID = CPK.SPELL.MISTS_ARCANE_CHARGE,
        MAX_STACKS = 4,
    }
    local PT = K.PT
    PT.BurningEmbers = (E and E.BurningEmbers) or 14
    PT.DemonicFury   = (E and E.DemonicFury) or 15
    PT.Balance       = (E and E.Balance) or 26
    PT.ShadowOrbs    = (E and E.ShadowOrbs) or 28
    local tokens = K.POWER_TYPE_TOKENS
    tokens[PT.BurningEmbers] = "BURNING_EMBERS"
    tokens[PT.DemonicFury]   = "DEMONIC_FURY"
    tokens[PT.Balance]       = "BALANCE"
    tokens[PT.ShadowOrbs]    = "SHADOW_ORBS"
    tokens.MISTS_ARCANE_CHARGES = "ARCANE_CHARGES"
    K.ModeDescriptors[MODE.SIGNED_CONTINUOUS] = {
        updateKey = "SignedContinuous", barCount = 1, power = true, aura = true,
    }
    --- WL_SHARD_DELTAS lists Midnight's shard generators only; Mists
    --- Affliction shards keep their event set without the cast events.
    K.ModeDescriptors[MODE.SEGMENTED].warlockPred = false
end

local eventTraits = { "power", "maxPower", "aura", "rune", "health", "pointCharge", "warlockPred" }
for _, descriptor in pairs(K.ModeDescriptors) do
    for _, trait in ipairs(eventTraits) do descriptor[trait] = descriptor[trait] == true end
    descriptor.tick = descriptor.tick or "essence"
    descriptor.pipColors = descriptor.pipColors == true
    if descriptor.powerUpdate == nil then descriptor.powerUpdate = true end
end

--- The Power element establishes ownership before ClassPower loads.
K.PowerOwnership = MSUF.ClassPowerOwnership
