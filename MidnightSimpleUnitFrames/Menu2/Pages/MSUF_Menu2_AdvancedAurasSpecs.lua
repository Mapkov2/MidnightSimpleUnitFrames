local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

M.AdvancedAurasSpecs = {
    AURA_SCOPES = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
        { value = "boss1", text = "Boss 1" },
        { value = "boss2", text = "Boss 2" },
        { value = "boss3", text = "Boss 3" },
        { value = "boss4", text = "Boss 4" },
        { value = "boss5", text = "Boss 5" },
    },

    AURA_GROWTH = {
        { value = "RIGHT", text = "Grow Right" },
        { value = "LEFT", text = "Grow Left" },
        { value = "UP", text = "Vertical Up" },
        { value = "DOWN", text = "Vertical Down" },
    },

    AURA_ROW_WRAP = {
        { value = "DOWN", text = "2nd row down" },
        { value = "UP", text = "2nd row up" },
    },

    AURA_STACK_ANCHORS = {
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    },

    AURA_IGNORE_CATEGORIES = {
        { key = "RAID_BUFFS", label = "Raid Buffs" },
        { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
        { key = "HEALER_HOTS", label = "Healer HoTs" },
        { key = "ROGUE_POISONS", label = "Rogue Poisons" },
        { key = "SHAMAN_IMBUE", label = "Shaman Imbuements" },
        { key = "DESERTER", label = "Deserter" },
        { key = "SKYRIDING", label = "Skyriding" },
        { key = "SELF_BUFFS", label = "Long-term Self Buffs" },
        { key = "RESOURCE_AURAS", label = "Resource-like Auras" },
        { key = "COOLDOWNS", label = "Cooldowns" },
    },

    AURA_REMINDERS = {
        { key = "FORTITUDE", label = "Power Word: Fortitude" },
        { key = "ARCANE_INTELLECT", label = "Arcane Intellect" },
        { key = "MARK_OF_WILD", label = "Mark of the Wild" },
        { key = "BATTLE_SHOUT", label = "Battle Shout" },
        { key = "SKYFURY", label = "Skyfury" },
        { key = "SOURCE_OF_MAGIC", label = "Source of Magic" },
        { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
        { key = "ROGUE_LETHAL", label = "Lethal Poison (Rogue)" },
        { key = "ROGUE_NONLETHAL", label = "Non-Lethal Poison (Rogue)" },
    },

    AURA_SORT_ORDER = {
        { value = 0, text = "Unsorted (default)" },
        { value = 1, text = "Default (player > canApply > ID)" },
        { value = 2, text = "Big Defensive (longest first)" },
        { value = 3, text = "Expiration (soonest first)" },
        { value = 4, text = "Expiration only" },
        { value = 5, text = "Name (alphabetical)" },
        { value = 6, text = "Name only" },
    },

    PANDEMIC_MODES = {
        { value = "BORDER", text = "Border" },
        { value = "PULSE", text = "Pulse" },
        { value = "GLOW", text = "Glow" },
    },
}
