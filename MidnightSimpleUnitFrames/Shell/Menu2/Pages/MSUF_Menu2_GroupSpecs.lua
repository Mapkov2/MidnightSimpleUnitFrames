local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

-- Group page spec catalogue.
-- Declarative dropdown values and status/indicator specs shared by group layout, bars,
-- indicators, and auras pages. Runtime group defaults live in the GroupFrames engine.
local VT, VTP = M.ValueTextList, M.ValueTextPairs
local function StatusIconSpecs(rows)
    local specs = {}
    for _, cols in ipairs(M.PipeRows(rows)) do
        specs[#specs + 1] = {
            value = cols[1], text = cols[2], enabled = cols[3], iconStyle = cols[4] ~= "0" and cols[4] or nil,
            size = cols[5], anchor = cols[6], x = cols[7], y = cols[8], layer = cols[9],
            defaultSize = tonumber(cols[10]), defaultAnchor = cols[11], defaultLayer = tonumber(cols[12]),
        }
    end
    return specs
end
local Specs = {
    SCOPE_VALUES = VTP "party=Party|raid=Raid|mythicraid=Mythic Raid",
    GROWTH_VALUES = VTP "DOWN=Down|UP=Up|RIGHT=Right|LEFT=Left",
    BLIZZARD_FALLBACK_VALUES = VTP "AUTO=Blizzard default|SHOW=Force Blizzard frames|NONE=Hide all frames",
    HEALTH_MODES = VTP "CLASS=Class|GRADIENT=Gradient|CUSTOM=Custom",
    TEXT_MODES = VTP "NONE=None|PERCENT=Percent|CURRENT=Current|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max",
    DELIMITER_VALUES = VT(" ", "Space", "  ", "Double Space", " / ", "/", " - ", "-", " : ", ":", " | ", "|"),
    ANCHORS = VTP "LEFT=Left|CENTER=Center|RIGHT=Right",
    AURA_ANCHORS = VTP "TOPLEFT=Top Left|TOPRIGHT=Top Right|BOTTOMLEFT=Bottom Left|BOTTOMRIGHT=Bottom Right",
    SORT_MODES = VTP "INDEX=Index (Default)|ROLE=By Role|GROUP=By Raid Group|GROUP_ROLE=Group + Role|NAME=Alphabetical",
    GF_BAR_MODES = VTP "GLOBAL=Follow Global Style|CLASS=Class Color|dark=Dark Mode|unified=Unified Color|GRADIENT=Health Gradient|CUSTOM=Custom Color",
    GF_ANCHOR_TO = VTP "FREE=Free (UIParent)|player=Player Frame|target=Target Frame|targettarget=Target of Target|focustarget=Focus Target|focus=Focus Frame",
    GF_ANCHOR_POINTS = VTP "TOPLEFT=TOPLEFT|TOP=TOP|TOPRIGHT=TOPRIGHT|LEFT=LEFT|CENTER=CENTER|RIGHT=RIGHT|BOTTOMLEFT=BOTTOMLEFT|BOTTOM=BOTTOM|BOTTOMRIGHT=BOTTOMRIGHT",
    STATUS_ICON_ANCHORS = VTP "TOPLEFT=Top Left|TOPRIGHT=Top Right|BOTTOMLEFT=Bottom Left|BOTTOMRIGHT=Bottom Right|CENTER=Center|TOP=Top|BOTTOM=Bottom|LEFT=Left|RIGHT=Right",
    GF_STATUS_ICON_SPECS = StatusIconSpecs [[
roleIcon|Role Icon|roleIcon|roleIconStyle|roleIconSize|roleIconAnchor|roleIconX|roleIconY|roleIconLayer|12|TOPLEFT|1
leaderIcon|Leader|leaderIcon|leaderIconStyle|leaderIconSize|leaderIconAnchor|leaderIconX|leaderIconY|leaderIconLayer|12|TOPRIGHT|2
assistIcon|Assist|assistIcon|assistIconStyle|assistIconSize|assistIconAnchor|assistIconX|assistIconY|assistIconLayer|12|TOPRIGHT|2
raidMarker|Raid Marker|raidMarker|0|raidMarkerSize|raidMarkerAnchor|raidMarkerX|raidMarkerY|raidMarkerLayer|14|CENTER|3
readyCheckIcon|Ready Check|readyCheckIcon|0|readyCheckSize|readyCheckAnchor|readyCheckX|readyCheckY|readyCheckLayer|16|CENTER|4
summonIcon|Summon|summonIcon|0|summonIconSize|summonAnchor|summonX|summonY|summonLayer|16|CENTER|4
resurrectIcon|Resurrect|resurrectIcon|0|resurrectIconSize|resurrectAnchor|resurrectX|resurrectY|resurrectLayer|16|CENTER|4
pvpIcon|PvP Flag (War Mode/PvP)|pvpIcon|0|pvpIconSize|pvpIconAnchor|pvpIconX|pvpIconY|pvpIconLayer|14|TOPLEFT|3
phaseIcon|Phase|phaseIcon|0|phaseIconSize|phaseAnchor|phaseX|phaseY|phaseLayer|14|TOPLEFT|3
statusText|Dead Text|statusText|0|statusTextSize|statusTextAnchor|statusOffsetX|statusOffsetY|statusTextLayer|14|CENTER|7
statusGhostText|Ghost Text|statusGhostText|0|statusGhostTextSize|statusGhostTextAnchor|statusGhostOffsetX|statusGhostOffsetY|statusGhostTextLayer|14|CENTER|7
statusAFKText|AFK / DND Text|statusAFKText|0|statusAFKTextSize|statusAFKTextAnchor|statusAFKOffsetX|statusAFKOffsetY|statusAFKTextLayer|14|CENTER|7
]],
    PLACED_INDICATOR_TYPES = VTP "none=None|icon=Icon|square=Square|bar=Bar|number=Number",
    FRAME_EFFECT_TYPES = VTP "none=None|healthtint=Health Tint|border=Border|glow=Glow|pulse=Pulse|namecolor=Name Color",
    SPELL_GROWTH_VALUES = VTP "RIGHTDOWN=Right then Down|LEFTDOWN=Left then Down|RIGHTUP=Right then Up|LEFTUP=Left then Up",
    CI_SLOT_VALUES = VTP "TL=Top Left|TR=Top Right|BL=Bottom Left|BR=Bottom Right|C=Center",
    CI_SLOT_DEFAULTS = {
        TL = "dispel",
        TR = "aggro",
        BL = "none",
        BR = "none",
        C = "none",
    },
    DISPEL_OVERLAY_STYLES = VTP "FULL=Full Frame|BOTTOM=Bottom Edge|TOP=Top Edge|LEFT=Left Edge|RIGHT=Right Edge",
    DEBUFF_STRIPE_EDGES = VTP "BOTTOM=Bottom Edge|TOP=Top Edge",
}
function Specs.SimpleTextures()
    return M.StatusBarTextureItems("Follow Global Style")
end
Specs.GF_STATUS_ICON_VALUES = {}
for i = 1, #Specs.GF_STATUS_ICON_SPECS do
    Specs.GF_STATUS_ICON_VALUES[i] = { value = Specs.GF_STATUS_ICON_SPECS[i].value, text = Specs.GF_STATUS_ICON_SPECS[i].text }
end
M.GroupSpecs = Specs
