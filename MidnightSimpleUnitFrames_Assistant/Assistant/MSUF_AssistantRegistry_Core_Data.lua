-- Assistant RegistryCore static values.
-- Loaded before MSUF_AssistantRegistry_Core.lua so the shared helper module can stay
-- focused on behavior and registration helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.RegistryCoreData or {}
A.RegistryCoreData = Data

Data.UNIT_LABELS = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focustarget = "Focus Target",
    focus = "Focus",
    pet = "Pet",
    boss = "Boss",
    party = "Party",
    raid = "Raid",
    mythicraid = "Mythic Raid",
    priority = "Priority Frames",
}

Data.UNIT_ALIASES = {
    player = { "player", "spieler", "self", "ich" },
    target = { "target", "ziel" },
    targettarget = { "targettarget", "target of target", "tot", "ziel des ziels" },
    focustarget = { "focustarget", "focus target", "fokus ziel" },
    focus = { "focus", "fokus" },
    pet = { "pet", "begleiter" },
    boss = { "boss", "boss frames", "bossframes" },
    party = { "party", "party frame", "party frames", "partyframe", "group", "group frames", "gruppenframes", "gruppe" },
    raid = { "raid", "raid frame", "raid frames", "raidframe", "schlachtzug" },
    mythicraid = { "mythicraid", "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraidframe" },
    priority = {
        "priority frames", "priority frame", "pinned frames", "pinned frame",
        "extra group frames", "tank frames",
    },
}

Data.AURA_LANE_FIELDS = {
    buff = {
        maxKey = "maxBuffs",
        sizeKey = "buffGroupIconSize",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        defaultMax = 8,
        defaultY = 36,
    },
    debuff = {
        maxKey = "maxDebuffs",
        sizeKey = "debuffGroupIconSize",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        defaultMax = 12,
        defaultY = 6,
    },
}

Data.AURA_UNIT_FLAGS = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss = "showBoss",
}

Data.GLOBAL_SCOPE_ORDER = {
    "player",
    "target",
    "targettarget",
    "focustarget",
    "focus",
    "pet",
    "boss",
    "gf_party",
    "gf_raid",
}

Data.GLOBAL_SCOPE_META = {
    shared = { label = "Shared", aliases = { "shared", "global", "all" } },
    player = { label = "Player", aliases = { "player", "player frame", "player unitframe" } },
    target = { label = "Target", aliases = { "target", "target frame", "target unitframe" } },
    targettarget = { label = "Target of Target", aliases = { "targettarget", "target of target", "tot" } },
    focustarget = { label = "Focus Target", aliases = { "focustarget", "focus target" } },
    focus = { label = "Focus", aliases = { "focus", "focus frame", "focus unitframe" } },
    pet = { label = "Pet", aliases = { "pet", "pet frame", "pet unitframe" } },
    boss = { label = "Boss", aliases = { "boss", "boss frames", "bossframes" } },
    gf_party = { label = "Party", aliases = { "party", "party frames", "party group", "group frames", "group frame" } },
    gf_raid = { label = "Raid", aliases = { "raid", "raid frames", "mythic raid", "mythicraid", "raid group" } },
}
