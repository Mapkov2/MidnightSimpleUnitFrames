-- Assistant GroupFrames secondary status icon registry data.
-- Loaded before the main status icon data file, which appends these specs in order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistryData = A.GroupFramesRegistryData or {}

A.GroupFramesRegistryData.GROUP_STATUS_ICON_EXTRA_SPECS = {
    {
        value = "pvpIcon",
        label = "PvP Flag Icon (War Mode/PvP)",
        enabled = "pvpIcon",
        iconStyle = "pvpIconStyle",
        customIcon = "pvpIconCustomIcon",
        size = "pvpIconSize",
        anchor = "pvpIconAnchor",
        x = "pvpIconX",
        y = "pvpIconY",
        layer = "pvpIconLayer",
        defaultSize = 14,
        defaultAnchor = "TOPLEFT",
        defaultLayer = 3,
        description = "Only active in War Mode, Arena/Battleground, or while the player is PvP flagged; PvE instances keep it cold.",
        terms = { "pvp flag", "pvp icon", "pvp flag icon", "pvp indicator", "pvp flag indicator", "pvp status", "war mode indicator", "flagged indicator" },
    },
    {
        value = "phaseIcon",
        label = "Phase Icon",
        enabled = "phaseIcon",
        iconStyle = "phaseIconStyle",
        customIcon = "phaseIconCustomIcon",
        size = "phaseIconSize",
        anchor = "phaseAnchor",
        x = "phaseX",
        y = "phaseY",
        layer = "phaseLayer",
        defaultSize = 14,
        defaultAnchor = "TOPLEFT",
        defaultLayer = 3,
        terms = { "phase icon", "phasing icon", "phase indicator", "phasing indicator", "phase symbol", "phasing symbol" },
    },
    {
        value = "statusText",
        label = "Dead Text",
        enabled = "statusText",
        size = "statusTextSize",
        anchor = "statusTextAnchor",
        x = "statusOffsetX",
        y = "statusOffsetY",
        layer = "statusTextLayer",
        defaultSize = 14,
        defaultAnchor = "CENTER",
        defaultLayer = 7,
        terms = {
            "dead text", "dead status text", "status text",
            "offline text", "offline status text", "offline indicator",
            "disconnected text", "connection text",
        },
    },
    {
        value = "statusGhostText",
        label = "Ghost Text",
        enabled = "statusGhostText",
        size = "statusGhostTextSize",
        anchor = "statusGhostTextAnchor",
        x = "statusGhostOffsetX",
        y = "statusGhostOffsetY",
        layer = "statusGhostTextLayer",
        defaultSize = 14,
        defaultAnchor = "CENTER",
        defaultLayer = 7,
        terms = { "ghost text", "ghost status text" },
    },
    {
        value = "statusAFKText",
        label = "AFK DND Text",
        enabled = "statusAFKText",
        size = "statusAFKTextSize",
        anchor = "statusAFKTextAnchor",
        x = "statusAFKOffsetX",
        y = "statusAFKOffsetY",
        layer = "statusAFKTextLayer",
        defaultSize = 14,
        defaultAnchor = "CENTER",
        defaultLayer = 7,
        terms = { "afk text", "dnd text", "afk dnd text", "away text" },
    },
}
