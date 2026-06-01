local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local VT, VTR = M.ValueTextList, M.ValueTextRows
local KLR = M.KeyLabelRows

M.AdvancedAurasSpecs = {
    AURA_SCOPES = VTR [[
shared=Shared
player=Player
target=Target
focus=Focus
boss1=Boss 1
boss2=Boss 2
boss3=Boss 3
boss4=Boss 4
boss5=Boss 5
]],

    AURA_GROWTH = VTR [[
RIGHT=Grow Right
LEFT=Grow Left
UP=Vertical Up
DOWN=Vertical Down
]],

    AURA_ROW_WRAP = VTR [[DOWN=2nd row down
UP=2nd row up]],

    AURA_STACK_ANCHORS = VTR [[
TOPLEFT=Top Left
TOPRIGHT=Top Right
BOTTOMLEFT=Bottom Left
BOTTOMRIGHT=Bottom Right
]],

    AURA_IGNORE_CATEGORIES = KLR [[
RAID_BUFFS=Raid Buffs
BLESSING_BRONZE=Blessing of the Bronze
HEALER_HOTS=Healer HoTs
ROGUE_POISONS=Rogue Poisons
SHAMAN_IMBUE=Shaman Imbuements
DESERTER=Deserter
SKYRIDING=Skyriding
SELF_BUFFS=Long-term Self Buffs
RESOURCE_AURAS=Resource-like Auras
COOLDOWNS=Cooldowns
]],

    AURA_REMINDERS = KLR [[
FORTITUDE=Power Word: Fortitude
ARCANE_INTELLECT=Arcane Intellect
MARK_OF_WILD=Mark of the Wild
BATTLE_SHOUT=Battle Shout
SKYFURY=Skyfury
SOURCE_OF_MAGIC=Source of Magic
BLESSING_BRONZE=Blessing of the Bronze
ROGUE_LETHAL=Lethal Poison (Rogue)
ROGUE_NONLETHAL=Non-Lethal Poison (Rogue)
]],

    AURA_SORT_ORDER = VT(
        0, "Unsorted (default)", 1, "Default (player > canApply > ID)", 2, "Big Defensive (longest first)",
        3, "Expiration (soonest first)", 4, "Expiration only", 5, "Name (alphabetical)", 6, "Name only"),

    PANDEMIC_MODES = VTR [[BORDER=Border
PULSE=Pulse
GLOW=Glow]],
}
