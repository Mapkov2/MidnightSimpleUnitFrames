local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Group preview spec data.
-- Declarative mock layout maps, growth vectors, anchors, classes, and icon IDs for the Menu2
-- preview renderer. Live group-frame specs remain in the GroupFrames runtime.
local maskRoot = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
M.GroupPreviewSpecs = {
    SECTION_PAGE = M.KeyLabelMap [[
general=gf_layout
layout=gf_layout
sorting=gf_layout
scaling=gf_layout
border=gf_layout
anchor=gf_layout
hcolor=opt_colors
bars=opt_bars
power=gf_layout
portrait=gf_layout
text=gf_layout
dispel=gf_bars
dispelSymbol=gf_bars
dstripe=gf_bars
range=gf_layout
buffs=gf_auras
debuffs=gf_auras
externals=gf_auras
textcolor=gf_auras
autil=gf_auras
indicators=gf_indicators
sicons=gf_indicators
si=gf_auras
ci=gf_indicators
]],
    PAGE_FOCUS = M.KeyLabelMap [[
gf_layout=layout
gf_bars=dispel
gf_auras=buffs
gf_indicators=indicators
]],
    WHITE8X8 = "Interface\\Buttons\\WHITE8X8",
    ROUNDED_MASK = maskRoot .. "rounded_clean_mask_s3.png",
    ROUNDED_EDGE = maskRoot .. "rounded_clean_edge_s3.png",
    MIN_W = 380,
    MIN_H = 130,
    ROLE = "HEALER",
    ZOOM_MIN = 0.35,
    ZOOM_MAX = 4.0,
    ZOOM_STEPS = { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 },
    AUTO_ZOOM_MIN = 0.75,
    AUTO_ZOOM_MAX = 1.65,
    AUTO_ZOOM_STAGE_PAD_X = 48,
    AUTO_ZOOM_STAGE_PAD_Y = 72,
    CLASSES = M.WordList [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]],
    NAMES = M.WordList [[Thrall Jaina Sylvanas Anduin Tyrande Arthas Garrosh Yrel Vol'jin Chen Malfurion Illidan Alexstrasza]],
    ANCHOR_FRAC = {
        TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
        LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
        BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
    },
    AURA_MOCK_ICON_IDS = {
        buff = { 774, 17, 139, 33076, 33763, 81749 },
        trackedBuff = { 10060, 53563, 1022, 6940, 1044, 194384 },
        debuff = { 589, 980, 172, 12294, 1943, 5782 },
        external = { 6940, 1022, 33206, 116849, 47788, 357170 },
    },
    AURA_GROWTH_TABLE = {
        RIGHTDOWN = { px = 1, py = 0, sx = 0, sy = -1 }, RIGHTUP = { px = 1, py = 0, sx = 0, sy = 1 },
        LEFTDOWN = { px = -1, py = 0, sx = 0, sy = -1 }, LEFTUP = { px = -1, py = 0, sx = 0, sy = 1 },
        DOWNRIGHT = { px = 0, py = -1, sx = 1, sy = 0 }, DOWNLEFT = { px = 0, py = -1, sx = -1, sy = 0 },
        UPRIGHT = { px = 0, py = 1, sx = 1, sy = 0 }, UPLEFT = { px = 0, py = 1, sx = -1, sy = 0 },
        CENTER_H = { px = 1, py = 0, sx = 0, sy = -1, centered = true },
        CENTER_V = { px = 0, py = -1, sx = 1, sy = 0, centered = true },
    },
    STATUS_RUNTIME_KEYS = M.KeyLabelMap [[
roleIcon=role
leaderIcon=leader
assistIcon=assist
raidMarker=raidMarker
readyCheckIcon=readyCheck
summonIcon=summon
resurrectIcon=incomingRes
pvpIcon=pvp
phaseIcon=phase
showGroupNumber=raidGroup
]],
    OUTLINE_KEYS = { "top", "bottom", "left", "right" },
}
