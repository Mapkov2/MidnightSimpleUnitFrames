local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local maskRoot = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"

local function MapRows(rows)
    local out = {}
    for line in tostring(rows or ""):gmatch("[^\r\n]+") do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key then out[key] = value end
    end
    return out
end

local function AnchorRows(rows)
    local out = {}
    for line in tostring(rows or ""):gmatch("[^\r\n]+") do
        local key, x, y = line:match("^(%S+)%s+([%d%.]+)%s+([%d%.]+)$")
        if key then out[key] = { tonumber(x) or 0, tonumber(y) or 0 } end
    end
    return out
end

local function GrowthRows(rows)
    local out = {}
    for line in tostring(rows or ""):gmatch("[^\r\n]+") do
        local key, px, py, sx, sy, centered = line:match("^(%S+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*(%S*)$")
        if key then out[key] = { px = tonumber(px), py = tonumber(py), sx = tonumber(sx), sy = tonumber(sy), centered = centered == "centered" or nil } end
    end
    return out
end

M.GroupPreviewSpecs = {
    SECTION_PAGE = MapRows [[
general=gf_layout
layout=gf_layout
sorting=gf_layout
scaling=gf_layout
border=gf_layout
anchor=gf_layout
hcolor=gf_bars
bars=gf_bars
power=gf_bars
text=gf_bars
dispel=gf_bars
dstripe=gf_bars
range=gf_bars
buffs=gf_auras
debuffs=gf_auras
textcolor=gf_auras
masque=gf_auras
autil=gf_auras
indicators=gf_indicators
sicons=gf_indicators
si=gf_indicators
ci=gf_indicators
]],

    PAGE_FOCUS = MapRows [[
gf_layout=layout
gf_bars=text
gf_auras=buffs
gf_indicators=indicators
]],

    WHITE8X8 = "Interface\\Buttons\\WHITE8X8",
    ROUNDED_MASK = maskRoot .. "rounded_bar_4x.tga",
    ROUNDED_EDGE = maskRoot .. "rounded_bar_edge_4x.tga",
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

    ANCHOR_FRAC = AnchorRows [[
TOPLEFT 0 1
TOP 0.5 1
TOPRIGHT 1 1
LEFT 0 0.5
CENTER 0.5 0.5
RIGHT 1 0.5
BOTTOMLEFT 0 0
BOTTOM 0.5 0
BOTTOMRIGHT 1 0
]],

    AURA_MOCK_ICON_IDS = {
        buff = { 774, 17, 139, 33076, 33763, 81749 },
        debuff = { 589, 980, 172, 12294, 1943, 5782 },
    },

    AURA_GROWTH_TABLE = GrowthRows [[
RIGHTDOWN 1 0 0 -1
RIGHTUP 1 0 0 1
LEFTDOWN -1 0 0 -1
LEFTUP -1 0 0 1
DOWNRIGHT 0 -1 1 0
DOWNLEFT 0 -1 -1 0
UPRIGHT 0 1 1 0
UPLEFT 0 1 -1 0
CENTER_H 1 0 0 -1 centered
CENTER_V 0 -1 1 0 centered
]],

    STATUS_RUNTIME_KEYS = MapRows [[
roleIcon=role
leaderIcon=leader
assistIcon=assist
raidMarker=raidMarker
readyCheckIcon=readyCheck
summonIcon=summon
resurrectIcon=incomingRes
phaseIcon=phase
]],

    OUTLINE_KEYS = { "top", "bottom", "left", "right" },

}
