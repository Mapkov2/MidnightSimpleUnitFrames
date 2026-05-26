--- Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua
--- Cold-path data specs for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local specs = MSUF.UFPreviewSpecs or {}
MSUF.UFPreviewSpecs = specs

specs.StatusPreview = {
    { id = "raidmarker", show = "showRaidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerOffsetX", y = "raidMarkerOffsetY", layer = "raidMarkerLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 16, defaultY = 3, text = "8", color = { 1, 0.82, 0.05 }, label = "Raid marker", refresh = "MSUF_RefreshRaidMarkerFrames" },
    { id = "leader", show = "showLeaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconOffsetX", y = "leaderIconOffsetY", layer = "leaderIconLayer", defaultLayer = 7, defaultSize = 14, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 3, text = "L", color = { 0.95, 0.82, 0.20 }, label = "Leader icon", refresh = "MSUF_RefreshLeaderIconFrames", allowed = function(k) return k == "player" or k == "target" end },
    { id = "level", show = "showLevelIndicator", size = "levelIndicatorSize", anchor = "levelIndicatorAnchor", x = "levelIndicatorOffsetX", y = "levelIndicatorOffsetY", layer = "levelIndicatorLayer", defaultLayer = 7, defaultSize = 14, defaultAnchor = "NAMERIGHT", defaultX = 0, defaultY = 0, text = "80", color = { 0.45, 0.70, 1.0 }, label = "Level indicator", refresh = "MSUF_RefreshLevelIndicatorFrames" },
    { id = "elite", show = "showEliteIcon", size = "eliteIconSize", anchor = "eliteIconAnchor", x = "eliteIconOffsetX", y = "eliteIconOffsetY", layer = "eliteIconLayer", defaultLayer = 7, defaultSize = 20, defaultAnchor = "TOPRIGHT", defaultX = 2, defaultY = 2, text = "*", color = { 1.0, 0.58, 0.16 }, label = "Elite icon", refresh = "MSUF_RefreshEliteIconFrames", allowed = function(k) return k == "target" or k == "focus" or k == "targettarget" or k == "focustarget" or k == "boss" end },
    { id = "statusText", show = "statusTextEnabled", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusTextOffsetX", y = "statusTextOffsetY", layer = "statusTextLayer", defaultLayer = 7, defaultSize = 16, defaultAnchor = "CENTER", defaultX = 0, defaultY = 0, text = "DEAD", color = { 0.68, 0.70, 0.74 }, label = "Dead text", refresh = "MSUF_RequestStatusTextRefresh" },
    { id = "statusCombat", show = "showCombatStateIndicator", size = "combatStateIndicatorSize", anchor = "combatStateIndicatorAnchor", x = "combatStateIndicatorOffsetX", y = "combatStateIndicatorOffsetY", layer = "combatStateIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 0, text = "C", color = { 1.0, 0.22, 0.16 }, label = "Combat icon", refresh = "MSUF_RequestStatusCombatIndicatorRefresh", allowed = function(k) return k == "player" or k == "target" end },
    { id = "statusResting", show = "showRestingIndicator", size = "restedStateIndicatorSize", anchor = "restedStateIndicatorAnchor", x = "restedStateIndicatorOffsetX", y = "restedStateIndicatorOffsetY", layer = "restedStateIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 0, text = "Z", color = { 0.34, 0.62, 1.0 }, label = "Rested icon", refresh = "MSUF_RequestStatusRestingIndicatorRefresh", defaultShow = false, allowed = function(k) return k == "player" end },
    { id = "statusIncomingRes", show = "showIncomingResIndicator", size = "incomingResIndicatorSize", anchor = "incomingResIndicatorAnchor", x = "incomingResIndicatorOffsetX", y = "incomingResIndicatorOffsetY", layer = "incomingResIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPRIGHT", defaultX = 0, defaultY = 0, text = "+", color = { 0.22, 1.0, 0.56 }, label = "Incoming Rez icon", refresh = "MSUF_RequestStatusIncomingResIndicatorRefresh", allowed = function(k) return k == "player" or k == "target" end },
}

specs.PreviewLayers = {
    { key = "guides", label = "Guides", color = { 0.42, 0.72, 1.00 }, tooltip = "Mover highlights and selected borders." },
    { key = "body", label = "Body", color = { 0.36, 0.62, 0.95 } },
    { key = "nameText", label = "Name", color = { 0.30, 0.66, 1.00 } },
    { key = "hpText", label = "HP Text", color = { 0.25, 0.90, 0.42 } },
    { key = "powerText", label = "Pwr Text", color = { 0.95, 0.72, 0.18 } },
    { key = "portrait", label = "Portrait", color = { 0.90, 0.42, 1.00 } },
    { key = "power", label = "Power", color = { 0.95, 0.72, 0.18 } },
    { key = "classPower", label = "Class", color = { 0.30, 0.78, 0.55 } },
    { key = "castbar", label = "Cast", color = { 0.20, 0.90, 0.85 } },
    { key = "auras", label = "Auras", color = { 0.42, 0.72, 1.00 } },
    { key = "status", label = "Status", color = { 0.85, 0.70, 0.25 } },
    { key = "bounds", label = "Bounds", color = { 1.00, 0.22, 0.12 } },
}
