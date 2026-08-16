local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

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
            customIcon = cols[13] ~= "0" and cols[13] or nil,
        }
    end
    return specs
end
local Specs = {
    SCOPE_VALUES = VTP "party=Party|raid=Raid|mythicraid=Mythic Raid",
    GROWTH_VALUES = VTP "DOWN=Down|UP=Up|RIGHT=Right|LEFT=Left",
    BLIZZARD_FALLBACK_VALUES = VTP "AUTO=Blizzard default|SHOW=Force Blizzard frames|NONE=Hide all frames",
    GROUP_FRAME_PROVIDER_VALUES = {
        {
            value = "MSUF",
            text = "MSUF frames",
            tooltipTitle = "MSUF frames",
            tooltip = "Uses MSUF's custom group frames for the selected Party, Raid, or Mythic Raid scope. The other scopes remain independent.",
        },
        {
            value = "AUTO",
            text = "Blizzard frames (WoW settings)",
            tooltipTitle = "Blizzard frames (WoW settings)",
            tooltip = "Turns off MSUF frames for this scope and returns control to WoW. Blizzard's own Party or Raid Frame settings decide when its frames appear.",
        },
        {
            value = "SHOW",
            text = "Force Blizzard frames",
            tooltipTitle = "Force Blizzard frames",
            tooltip = "Turns off MSUF frames for this scope and forces Blizzard group frames visible. Use this only when Blizzard's frames do not appear with the normal WoW settings option.",
        },
        {
            value = "NONE",
            text = "Hide all group frames",
            tooltipTitle = "Hide all group frames",
            tooltip = "Hides both MSUF and Blizzard group frames for this scope. Your saved MSUF layout remains unchanged.",
        },
    },
    --- Blizzard's Raid Manager is a single shared frame, so this value is not per scope
    --- even though it is stored in all three gf_* rows. Menu2 writes them together.
    GROUP_RAID_MANAGER_VALUES = {
        {
            value = "AUTO",
            text = "Automatic",
            tooltipTitle = "Automatic",
            tooltip = "Hides the Raid Manager while MSUF provides the live group frames, and leaves it to WoW otherwise. This is how MSUF has always behaved.",
        },
        {
            value = "SHOW",
            text = "Always visible",
            tooltipTitle = "Always visible",
            tooltip = "Keeps the Raid Manager reachable even with MSUF group frames on. Use this when you still want its ready check, raid markers, and role filters.",
        },
        {
            value = "MOUSEOVER",
            text = "Show on mouseover",
            tooltipTitle = "Show on mouseover",
            tooltip = "Fades the Raid Manager out until the mouse touches it. Ready check, raid markers, and role filters stay reachable, and an expanded panel stays visible until you collapse it again.",
        },
        {
            value = "HIDDEN",
            text = "Always hidden",
            tooltipTitle = "Always hidden",
            tooltip = "Keeps the Raid Manager invisible and click-through at all times. Switch back to reach its buttons again.",
        },
    },
    HEALTH_MODES = VTP "CLASS=Class|GRADIENT=Gradient|CUSTOM=Custom",
    TEXT_MODES = VTP "NONE=None|PERCENT=Percent|CURRENT=Current|FULLVALUE=Full Value|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max",
    HEALTH_TEXT_MODES = VTP "NONE=None|ABSORB=Absorb|CURRENTABSORB=Current + Absorb|FULLVALUEABSORB=Full Value + Absorb|MAXABSORB=Max + Absorb|DEFICITABSORB=Deficit + Absorb|CURMAXABSORB=Current / Max + Absorb|PERCENTABSORB=Percent + Absorb|CURPERCENTABSORB=Current / Percent + Absorb|CURMAXPERCENTABSORB=Current / Max / Percent + Absorb|MAXPERCENTABSORB=Max / Percent + Absorb|PERCENTCURABSORB=Percent / Current + Absorb|PERCENTMAXABSORB=Percent / Max + Absorb|PERCENTCURMAXABSORB=Percent / Current / Max + Absorb|PERCENT=Percent|CURRENT=Current|FULLVALUE=Full Value|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max",
    DELIMITER_VALUES = VT(" ", "Space", "  ", "Double Space", " / ", "/", " - ", "-", " : ", ":", " | ", "|"),
    ANCHORS = VTP "TOPLEFT=Top Left|TOP=Top Center|TOPRIGHT=Top Right|LEFT=Left|CENTER=Center|RIGHT=Right",
    AURA_ANCHORS = VTP "TOPLEFT=Top Left|TOPRIGHT=Top Right|BOTTOMLEFT=Bottom Left|BOTTOMRIGHT=Bottom Right",
    SORT_MODES = VTP "INDEX=Index (Default)|ROLE=By Role|GROUP=By Raid Group|GROUP_ROLE=Group + Role|NAME=Alphabetical",
    GF_BAR_MODES = VTP "GLOBAL=Follow Global Style|CLASS=Class Color|dark=Dark Mode|unified=Unified Color|GRADIENT=Health Gradient|CUSTOM=Custom Color",
    GF_ANCHOR_TO = VTP "FREE=Free (UIParent)|player=Player Frame|target=Target Frame|targettarget=Target of Target|focustarget=Focus Target|focus=Focus Frame",
    GF_ANCHOR_POINTS = VTP "TOPLEFT=TOPLEFT|TOP=TOP|TOPRIGHT=TOPRIGHT|LEFT=LEFT|CENTER=CENTER|RIGHT=RIGHT|BOTTOMLEFT=BOTTOMLEFT|BOTTOM=BOTTOM|BOTTOMRIGHT=BOTTOMRIGHT",
    STATUS_ICON_ANCHORS = VTP "TOPLEFT=Top Left|TOPRIGHT=Top Right|BOTTOMLEFT=Bottom Left|BOTTOMRIGHT=Bottom Right|CENTER=Center|TOP=Top|BOTTOM=Bottom|LEFT=Left|RIGHT=Right",
    GF_STATUS_ICON_SPECS = StatusIconSpecs [[
roleIcon|Role Icon|roleIcon|roleIconStyle|roleIconSize|roleIconAnchor|roleIconX|roleIconY|roleIconLayer|16|LEFT|1|roleIconCustomIcon
leaderIcon|Leader|leaderIcon|leaderIconStyle|leaderIconSize|leaderIconAnchor|leaderIconX|leaderIconY|leaderIconLayer|12|TOPRIGHT|2|leaderIconCustomIcon
assistIcon|Assist|assistIcon|assistIconStyle|assistIconSize|assistIconAnchor|assistIconX|assistIconY|assistIconLayer|12|TOPRIGHT|2|assistIconCustomIcon
raidMarker|Raid Marker|raidMarker|raidMarkerStyle|raidMarkerSize|raidMarkerAnchor|raidMarkerX|raidMarkerY|raidMarkerLayer|14|CENTER|3|raidMarkerCustomIcon
readyCheckIcon|Ready Check|readyCheckIcon|readyCheckIconStyle|readyCheckSize|readyCheckAnchor|readyCheckX|readyCheckY|readyCheckLayer|16|CENTER|4|readyCheckIconCustomIcon
summonIcon|Summon|summonIcon|summonIconStyle|summonIconSize|summonAnchor|summonX|summonY|summonLayer|16|CENTER|4|summonIconCustomIcon
resurrectIcon|Resurrect|resurrectIcon|resurrectIconStyle|resurrectIconSize|resurrectAnchor|resurrectX|resurrectY|resurrectLayer|16|CENTER|4|resurrectIconCustomIcon
pvpIcon|PvP Flag (War Mode/PvP)|pvpIcon|pvpIconStyle|pvpIconSize|pvpIconAnchor|pvpIconX|pvpIconY|pvpIconLayer|14|TOPLEFT|3|pvpIconCustomIcon
phaseIcon|Phase|phaseIcon|phaseIconStyle|phaseIconSize|phaseAnchor|phaseX|phaseY|phaseLayer|14|TOPLEFT|3|phaseIconCustomIcon
statusText|Dead Text|statusText|0|statusTextSize|statusTextAnchor|statusOffsetX|statusOffsetY|statusTextLayer|14|CENTER|7|0
statusGhostText|Ghost Text|statusGhostText|0|statusGhostTextSize|statusGhostTextAnchor|statusGhostOffsetX|statusGhostOffsetY|statusGhostTextLayer|14|CENTER|7|0
statusAFKText|AFK Text|statusAFKText|0|statusAFKTextSize|statusAFKTextAnchor|statusAFKOffsetX|statusAFKOffsetY|statusAFKTextLayer|14|CENTER|7|0
statusAFKTimer|AFK Timer|statusAFKTimerText|0|statusAFKTimerTextSize|statusAFKTimerTextAnchor|statusAFKTimerOffsetX|statusAFKTimerOffsetY|statusAFKTimerTextLayer|10|CENTER|7|0
statusDNDText|DND Text|statusDNDText|0|statusDNDTextSize|statusDNDTextAnchor|statusDNDOffsetX|statusDNDOffsetY|statusDNDTextLayer|14|CENTER|7|0
]],
    PLACED_INDICATOR_TYPES = VTP "none=None|icon=Icon|square=Square|bar=Bar|number=Number",
    FRAME_EFFECT_TYPES = VTP "none=None|healthtint=Health Tint|border=Border|glow=Glow|pulse=Pulse|namecolor=Name Color",
    ICON_EFFECT_TYPES = VTP "none=None|glow=Animated Glow",
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
