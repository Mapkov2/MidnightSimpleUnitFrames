--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua
--- Cold-path data specs for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local specs = MSUF.UFPreviewSpecs or {}
MSUF.UFPreviewSpecs = specs
local PipeRows = (MSUF.MSUF2 or _G.MSUF2).PipeRows
local function Color(text)
    local r, g, b = tostring(text or ""):match("^([^,]+),([^,]+),([^,]+)$")
    return { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1 }
end
local function Allowed(words)
    if not words or words == "" then return nil end
    local set = {}
    for key in words:gmatch("%S+") do set[key] = true end
    return function(key) return set[key] == true end
end
local function StatusRows(rows)
    local out = {}
    for _, c in ipairs(PipeRows(rows)) do
        out[#out + 1] = {
            id = c[1], show = c[2], size = c[3], anchor = c[4], x = c[5], y = c[6], layer = c[7],
            defaultLayer = tonumber(c[8]), defaultSize = tonumber(c[9]), defaultAnchor = c[10],
            defaultX = tonumber(c[11]), defaultY = tonumber(c[12]), text = c[13], color = Color(c[14]),
            label = c[15], refresh = c[16], defaultShow = c[17] == "false" and false or nil, allowed = Allowed(c[18]),
            customIcon = c[19] ~= "" and c[19] or nil,
        }
    end
    return out
end
local function LayerRows(rows)
    local out = {}
    for _, c in ipairs(PipeRows(rows)) do
        out[#out + 1] = { key = c[1], label = c[2], color = Color(c[3]), tooltip = c[4] ~= "" and c[4] or nil }
    end
    return out
end
specs.StatusPreview = StatusRows [[
raidmarker|showRaidMarker|raidMarkerSize|raidMarkerAnchor|raidMarkerOffsetX|raidMarkerOffsetY|raidMarkerLayer|7|18|TOPLEFT|16|3|8|1,0.82,0.05|Raid marker|MSUF_RefreshRaidMarkerFrames|||raidMarkerCustomIcon
leader|showLeaderIcon|leaderIconSize|leaderIconAnchor|leaderIconOffsetX|leaderIconOffsetY|leaderIconLayer|7|14|TOPLEFT|0|3|L|0.95,0.82,0.20|Leader icon|MSUF_RefreshLeaderIconFrames||player target|leaderIconCustomIcon
assist|showLeaderIcon|leaderIconSize|leaderIconAnchor|leaderIconOffsetX|leaderIconOffsetY|leaderIconLayer|7|14|TOPLEFT|0|3|A|0.58,0.82,1.00|Assist icon|MSUF_RefreshLeaderIconFrames||player target|assistIconCustomIcon
level|showLevelIndicator|levelIndicatorSize|levelIndicatorAnchor|levelIndicatorOffsetX|levelIndicatorOffsetY|levelIndicatorLayer|7|14|NAMERIGHT|0|0|80|0.45,0.70,1.0|Level text|MSUF_RefreshIdentityTextFrames||
bossNumber|showBossNumberIndicator|bossNumberIndicatorSize|bossNumberIndicatorAnchor|bossNumberIndicatorOffsetX|bossNumberIndicatorOffsetY|bossNumberIndicatorLayer|7|14|TOPLEFT|4|-4|1|0.45,0.70,1.0|Boss number|MSUF_RefreshStatusIndicators|false|boss|
raceText|showRaceIndicator|raceIndicatorSize|raceIndicatorAnchor|raceIndicatorOffsetX|raceIndicatorOffsetY|raceIndicatorLayer|7|14|NAMERIGHT|0|0|Tauren|0.45,0.70,1.0|Race text|MSUF_RefreshIdentityTextFrames|false|
classText|showClassTextIndicator|classTextIndicatorSize|classTextIndicatorAnchor|classTextIndicatorOffsetX|classTextIndicatorOffsetY|classTextIndicatorLayer|7|14|NAMERIGHT|0|0|Warrior|0.45,0.70,1.0|Class text|MSUF_RefreshIdentityTextFrames|false|
elite|showEliteIcon|eliteIconSize|eliteIconAnchor|eliteIconOffsetX|eliteIconOffsetY|eliteIconLayer|7|20|TOPRIGHT|2|2|*|1.0,0.58,0.16|Elite icon|MSUF_RefreshEliteIconFrames||target focus targettarget focustarget boss|eliteIconCustomIcon
statusText|statusDeadTextEnabled|statusTextSize|statusTextAnchor|statusTextOffsetX|statusTextOffsetY|statusTextLayer|7|16|CENTER|0|0|DEAD|0.68,0.70,0.74|Dead / Offline text|MSUF_RequestStatusTextRefresh||
statusGhostText|statusGhostTextEnabled|statusGhostTextSize|statusGhostTextAnchor|statusGhostTextOffsetX|statusGhostTextOffsetY|statusGhostTextLayer|7|16|CENTER|0|0|GHOST|0.68,0.70,0.74|Ghost text|MSUF_RequestStatusTextRefresh||
statusAFKText|statusAFKTextEnabled|statusAFKTextSize|statusAFKTextAnchor|statusAFKTextOffsetX|statusAFKTextOffsetY|statusAFKTextLayer|7|16|CENTER|0|0|AFK|0.68,0.70,0.74|AFK text|MSUF_RequestStatusTextRefresh|false|
statusAFKTimer|statusAFKTimerEnabled|statusAFKTimerSize|statusAFKTimerAnchor|statusAFKTimerOffsetX|statusAFKTimerOffsetY|statusAFKTimerLayer|7|12|CENTER|0|-14|5m|0.55,0.75,0.62|AFK timer|MSUF_RequestStatusTextRefresh|false|
statusDNDText|statusDNDTextEnabled|statusDNDTextSize|statusDNDTextAnchor|statusDNDTextOffsetX|statusDNDTextOffsetY|statusDNDTextLayer|7|16|CENTER|0|0|DND|0.68,0.70,0.74|DND text|MSUF_RequestStatusTextRefresh|false|
statusCombat|showCombatStateIndicator|combatStateIndicatorSize|combatStateIndicatorAnchor|combatStateIndicatorOffsetX|combatStateIndicatorOffsetY|combatStateIndicatorLayer|7|18|TOPLEFT|0|0|C|1.0,0.22,0.16|Combat icon|MSUF_RequestStatusCombatIndicatorRefresh||player target|combatStateIndicatorCustomIcon
statusResting|showRestingIndicator|restedStateIndicatorSize|restedStateIndicatorAnchor|restedStateIndicatorOffsetX|restedStateIndicatorOffsetY|restedStateIndicatorLayer|25|39|TOPLEFT|-40|50|Z|0.34,0.62,1.0|Rested icon|MSUF_RequestStatusRestingIndicatorRefresh||player|restedStateIndicatorCustomIcon
statusIncomingRes|showIncomingResIndicator|incomingResIndicatorSize|incomingResIndicatorAnchor|incomingResIndicatorOffsetX|incomingResIndicatorOffsetY|incomingResIndicatorLayer|7|18|TOPRIGHT|0|0|+|0.22,1.0,0.56|Incoming Rez icon|MSUF_RequestStatusIncomingResIndicatorRefresh||player target|incomingResIndicatorCustomIcon
statusPvp|showPvpIndicator|pvpIndicatorSize|pvpIndicatorAnchor|pvpIndicatorOffsetX|pvpIndicatorOffsetY|pvpIndicatorLayer|7|18|TOPRIGHT|0|0|PVP|0.32,0.62,1.0|PvP flag (War Mode/PvP)|MSUF_RequestStatusPvpIndicatorRefresh||player target focus targettarget focustarget|pvpIndicatorCustomIcon
stance|showStanceIndicator|stanceIndicatorSize|stanceIndicatorAnchor|stanceIndicatorOffsetX|stanceIndicatorOffsetY|stanceIndicatorLayer|7|12|TOP|0|-2|Stance|0.45,0.70,1.0|Stance text|MSUF_RequestStatusIconsRefreshForCurrent|false|player|
]]
specs.PreviewLayers = LayerRows [[
guides|Guides|0.42,0.72,1.00|Mover highlights and selected borders.
nameText|Name|0.30,0.66,1.00
hpText|HP Text|0.25,0.90,0.42
powerText|Pwr Text|0.95,0.72,0.18
portrait|Portrait|0.90,0.42,1.00
texLayer|Texture|0.80,0.55,0.25|Decorative texture layer.
power|Power|0.95,0.72,0.18
classPower|Class|0.30,0.78,0.55
castbar|Cast|0.20,0.90,0.85
buff|Buffs|0.20,0.90,0.35
debuff|Debuffs|0.90,0.20,0.22
auras|Custom|0.42,0.72,1.00
dispelOverlay|Dispel Overlay|0.25,0.72,1.00|Configured cleanse-color wash over the health bar.
dispelSymbol|Dispel Symbol|0.34,0.84,1.00|Configured dispel-type symbols and placement.
status|Status|0.85,0.70,0.25
bounds|Bounds|0.25,0.75,0.88
]]
