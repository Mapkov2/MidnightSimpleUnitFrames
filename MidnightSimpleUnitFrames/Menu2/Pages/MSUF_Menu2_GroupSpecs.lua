local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Specs = {
    WARNING_HINT = { 0.90, 0.84, 0.76, 1 },
    WARNING_BG = { 0.105, 0.082, 0.052, 0.44 },
    WARNING_ARROW = { 0.88, 0.62, 0.22, 1 },
    WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 },
    WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 },
    WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 },

    SCOPE_VALUES = {
        { value = "party", text = "Party" },
        { value = "raid", text = "Raid" },
        { value = "mythicraid", text = "Mythic Raid" },
    },

    GROWTH_VALUES = {
        { value = "DOWN", text = "Down" },
        { value = "UP", text = "Up" },
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
    },

    BLIZZARD_FALLBACK_VALUES = {
        { value = "AUTO", text = "Blizzard default" },
        { value = "SHOW", text = "Force Blizzard frames" },
        { value = "NONE", text = "Hide all frames" },
    },

    HEALTH_MODES = {
        { value = "CLASS", text = "Class" },
        { value = "GRADIENT", text = "Gradient" },
        { value = "CUSTOM", text = "Custom" },
    },

    TEXT_MODES = {
        { value = "NONE", text = "None" },
        { value = "PERCENT", text = "Percent" },
        { value = "CURRENT", text = "Current" },
        { value = "MAX", text = "Max" },
        { value = "DEFICIT", text = "Deficit" },
        { value = "CURMAX", text = "Current / Max" },
        { value = "CURPERCENT", text = "Current / Percent" },
        { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
        { value = "MAXPERCENT", text = "Max / Percent" },
        { value = "PERCENTCUR", text = "Percent / Current" },
        { value = "PERCENTMAX", text = "Percent / Max" },
        { value = "PERCENTCURMAX", text = "Percent / Current / Max" },
    },

    DELIMITER_VALUES = {
        { value = " ", text = "Space" },
        { value = "  ", text = "Double Space" },
        { value = " / ", text = "/" },
        { value = " - ", text = "-" },
        { value = " : ", text = ":" },
        { value = " | ", text = "|" },
    },

    ANCHORS = {
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
    },

    AURA_ANCHORS = {
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    },

    GF_RENDERERS = {
        { value = "BLIZZARD", text = "Blizzard" },
        { value = "CUSTOM", text = "Custom" },
    },

    GF_AURA_FILTERS = {
        { value = "RAID", text = "Raid helpful" },
        { value = "ALL", text = "All" },
        { value = "PLAYER", text = "Mine only" },
    },

    GF_AURA_ORG = {
        { value = "default", text = "Default" },
        { value = "BUFFS_TOP_DEBUFFS_BOTTOM", text = "Buffs Top / Debuffs Bottom" },
        { value = "BUFFS_RIGHT_DEBUFFS_LEFT", text = "Buffs Right / Debuffs Left" },
    },

    SORT_MODES = {
        { value = "INDEX", text = "Index (Default)" },
        { value = "ROLE", text = "By Role" },
        { value = "GROUP", text = "By Raid Group" },
        { value = "GROUP_ROLE", text = "Group + Role" },
        { value = "NAME", text = "Alphabetical" },
    },

    GF_BAR_MODES = {
        { value = "GLOBAL", text = "Follow Global Style" },
        { value = "CLASS", text = "Class Color" },
        { value = "dark", text = "Dark Mode" },
        { value = "unified", text = "Unified Color" },
        { value = "GRADIENT", text = "Health Gradient" },
        { value = "CUSTOM", text = "Custom Color" },
    },

    GF_ANCHOR_TO = {
        { value = "FREE", text = "Free (UIParent)" },
        { value = "player", text = "Player Frame" },
        { value = "target", text = "Target Frame" },
        { value = "targettarget", text = "Target of Target" },
        { value = "focustarget", text = "Focus Target" },
        { value = "focus", text = "Focus Frame" },
    },

    GF_ANCHOR_POINTS = {
        { value = "TOPLEFT", text = "TOPLEFT" },
        { value = "TOP", text = "TOP" },
        { value = "TOPRIGHT", text = "TOPRIGHT" },
        { value = "LEFT", text = "LEFT" },
        { value = "CENTER", text = "CENTER" },
        { value = "RIGHT", text = "RIGHT" },
        { value = "BOTTOMLEFT", text = "BOTTOMLEFT" },
        { value = "BOTTOM", text = "BOTTOM" },
        { value = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
    },

    TOOLTIP_MODES = {
        { value = "ALWAYS", text = "Always" },
        { value = "OOC", text = "Out of Combat" },
        { value = "MODIFIER", text = "Modifier Key" },
        { value = "NEVER", text = "Never" },
    },

    TOOLTIP_MODIFIERS = {
        { value = "ALT", text = "Alt" },
        { value = "CTRL", text = "Ctrl" },
        { value = "SHIFT", text = "Shift" },
    },

    STATUS_ICON_ANCHORS = {
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
        { value = "CENTER", text = "Center" },
        { value = "TOP", text = "Top" },
        { value = "BOTTOM", text = "Bottom" },
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    },

    GF_STATUS_ICON_SPECS = {
        { value = "roleIcon", text = "Role Icon", enabled = "roleIcon", iconStyle = "roleIconStyle", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", defaultSize = 12, defaultAnchor = "TOPLEFT", defaultLayer = 1 },
        { value = "leaderIcon", text = "Leader", enabled = "leaderIcon", iconStyle = "leaderIconStyle", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
        { value = "assistIcon", text = "Assist", enabled = "assistIcon", iconStyle = "assistIconStyle", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
        { value = "raidMarker", text = "Raid Marker", enabled = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY", layer = "raidMarkerLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 3 },
        { value = "readyCheckIcon", text = "Ready Check", enabled = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY", layer = "readyCheckLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
        { value = "summonIcon", text = "Summon", enabled = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY", layer = "summonLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
        { value = "resurrectIcon", text = "Resurrect", enabled = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY", layer = "resurrectLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
        { value = "phaseIcon", text = "Phase", enabled = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", x = "phaseX", y = "phaseY", layer = "phaseLayer", defaultSize = 14, defaultAnchor = "TOPLEFT", defaultLayer = 3 },
        { value = "statusText", text = "Dead Text", enabled = "statusText", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusOffsetX", y = "statusOffsetY", layer = "statusTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
        { value = "statusGhostText", text = "Ghost Text", enabled = "statusGhostText", size = "statusGhostTextSize", anchor = "statusGhostTextAnchor", x = "statusGhostOffsetX", y = "statusGhostOffsetY", layer = "statusGhostTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
        { value = "statusAFKText", text = "AFK / DND Text", enabled = "statusAFKText", size = "statusAFKTextSize", anchor = "statusAFKTextAnchor", x = "statusAFKOffsetX", y = "statusAFKOffsetY", layer = "statusAFKTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
    },

    PLACED_INDICATOR_TYPES = {
        { value = "none", text = "None" },
        { value = "icon", text = "Icon" },
        { value = "square", text = "Square" },
        { value = "bar", text = "Bar" },
        { value = "number", text = "Number" },
    },

    FRAME_EFFECT_TYPES = {
        { value = "none", text = "None" },
        { value = "healthtint", text = "Health Tint" },
        { value = "border", text = "Border" },
        { value = "glow", text = "Glow" },
        { value = "pulse", text = "Pulse" },
        { value = "namecolor", text = "Name Color" },
    },

    SPELL_GROWTH_VALUES = {
        { value = "RIGHTDOWN", text = "Right then Down" },
        { value = "LEFTDOWN", text = "Left then Down" },
        { value = "RIGHTUP", text = "Right then Up" },
        { value = "LEFTUP", text = "Left then Up" },
    },

    CI_SLOT_VALUES = {
        { value = "TL", text = "Top Left" },
        { value = "TR", text = "Top Right" },
        { value = "BL", text = "Bottom Left" },
        { value = "BR", text = "Bottom Right" },
        { value = "C", text = "Center" },
    },

    CI_SLOT_DEFAULTS = {
        TL = "dispel",
        TR = "aggro",
        BL = "none",
        BR = "none",
        C = "none",
    },

    DISPEL_OVERLAY_STYLES = {
        { value = "FULL", text = "Full Frame" },
        { value = "BOTTOM", text = "Bottom Edge" },
        { value = "TOP", text = "Top Edge" },
        { value = "LEFT", text = "Left Edge" },
        { value = "RIGHT", text = "Right Edge" },
    },

    DEBUFF_STRIPE_EDGES = {
        { value = "BOTTOM", text = "Bottom Edge" },
        { value = "TOP", text = "Top Edge" },
    },
}

function Specs.SimpleTextures()
    local ui = MSUF and MSUF.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems("Follow Global Style")
    end
    return {
        { value = "", text = "Follow Global Style" },
        { value = "Blizzard", text = "Blizzard", texture = "Interface\\TargetingFrame\\UI-StatusBar" },
        { value = "Solid", text = "Solid", texture = "Interface\\Buttons\\WHITE8X8" },
        { value = "Flat", text = "Flat", texture = "Interface\\Buttons\\WHITE8X8" },
        { value = "MSUF Smooth v2", text = "MSUF Smooth v2", texture = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\Smoothv2.tga" },
    }
end

Specs.GF_STATUS_ICON_VALUES = {}
for i = 1, #Specs.GF_STATUS_ICON_SPECS do
    Specs.GF_STATUS_ICON_VALUES[i] = { value = Specs.GF_STATUS_ICON_SPECS[i].value, text = Specs.GF_STATUS_ICON_SPECS[i].text }
end

M.GroupSpecs = Specs
