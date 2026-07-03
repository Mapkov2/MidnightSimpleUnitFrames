-- Assistant GroupFrames status icon registry data.
-- Loaded after MSUF_AssistantRegistry_GroupFrames_Data.lua and before status icon consumers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistryData = A.GroupFramesRegistryData or {}

A.GroupFramesRegistryData.GROUP_STATUS_ICON_SPECS = {
    {
        value = "roleIcon",
        label = "Role Icon",
        enabled = "roleIcon",
        iconStyle = "roleIconStyle",
        customIcon = "roleIconCustomIcon",
        size = "roleIconSize",
        anchor = "roleIconAnchor",
        x = "roleIconX",
        y = "roleIconY",
        layer = "roleIconLayer",
        defaultSize = 12,
        defaultAnchor = "TOPLEFT",
        defaultLayer = 1,
        terms = { "role icon", "role icons", "role indicator", "role indicators", "role symbol", "role symbols", "rollen icon", "rollen icons", "rollen indikator", "rollen symbol" },
    },
    {
        value = "leaderIcon",
        label = "Leader Icon",
        enabled = "leaderIcon",
        iconStyle = "leaderIconStyle",
        customIcon = "leaderIconCustomIcon",
        size = "leaderIconSize",
        anchor = "leaderIconAnchor",
        x = "leaderIconX",
        y = "leaderIconY",
        layer = "leaderIconLayer",
        defaultSize = 12,
        defaultAnchor = "TOPRIGHT",
        defaultLayer = 2,
        terms = { "leader icon", "leader icons", "leader indicator", "leader indicators", "leader symbol", "leader symbols", "gruppenleiter icon", "leader symbol", "leiter icon", "anfuehrer icon" },
    },
    {
        value = "assistIcon",
        label = "Assist Icon",
        enabled = "assistIcon",
        iconStyle = "assistIconStyle",
        customIcon = "assistIconCustomIcon",
        size = "assistIconSize",
        anchor = "assistIconAnchor",
        x = "assistIconX",
        y = "assistIconY",
        layer = "assistIconLayer",
        defaultSize = 12,
        defaultAnchor = "TOPRIGHT",
        defaultLayer = 2,
        terms = {
            "assist icon", "assist icons", "assistant icon", "assistant icons",
            "assist indicator", "assist indicators", "assistant indicator", "assistant indicators",
            "assist symbol", "assist symbols", "assistant symbol", "assistant symbols", "assistent icon", "assistenz icon",
        },
    },
    {
        value = "raidMarker",
        label = "Raid Marker",
        enabled = "raidMarker",
        iconStyle = "raidMarkerStyle",
        customIcon = "raidMarkerCustomIcon",
        size = "raidMarkerSize",
        anchor = "raidMarkerAnchor",
        x = "raidMarkerX",
        y = "raidMarkerY",
        layer = "raidMarkerLayer",
        defaultSize = 14,
        defaultAnchor = "CENTER",
        defaultLayer = 3,
        terms = {
            "raid marker", "raid marker icon", "raid marker indicator", "raid marker symbol",
            "target marker", "target marker icon", "target marker indicator", "target marker symbol", "raid markierung", "ziel markierung", "zielmarker",
        },
    },
    {
        value = "readyCheckIcon",
        label = "Ready Check Icon",
        enabled = "readyCheckIcon",
        iconStyle = "readyCheckIconStyle",
        customIcon = "readyCheckIconCustomIcon",
        size = "readyCheckSize",
        anchor = "readyCheckAnchor",
        x = "readyCheckX",
        y = "readyCheckY",
        layer = "readyCheckLayer",
        defaultSize = 16,
        defaultAnchor = "CENTER",
        defaultLayer = 4,
        terms = { "ready check", "ready check icon", "ready check indicator", "ready check symbol", "ready icon", "ready indicator", "ready symbol", "bereitschaftscheck", "bereitschaftscheck icon", "readycheck icon" },
    },
    {
        value = "summonIcon",
        label = "Summon Icon",
        enabled = "summonIcon",
        iconStyle = "summonIconStyle",
        customIcon = "summonIconCustomIcon",
        size = "summonIconSize",
        anchor = "summonAnchor",
        x = "summonX",
        y = "summonY",
        layer = "summonLayer",
        defaultSize = 16,
        defaultAnchor = "CENTER",
        defaultLayer = 4,
        terms = { "summon icon", "summon indicator", "summon symbol", "beschwoerung icon", "beschwoeren icon" },
    },
    {
        value = "resurrectIcon",
        label = "Resurrect Icon",
        enabled = "resurrectIcon",
        iconStyle = "resurrectIconStyle",
        customIcon = "resurrectIconCustomIcon",
        size = "resurrectIconSize",
        anchor = "resurrectAnchor",
        x = "resurrectX",
        y = "resurrectY",
        layer = "resurrectLayer",
        defaultSize = 16,
        defaultAnchor = "CENTER",
        defaultLayer = 4,
        terms = {
            "resurrect icon", "resurrect indicator", "resurrect symbol",
            "resurrection icon", "resurrection indicator", "resurrection symbol",
            "rez icon", "rez indicator", "rez symbol",
            "incoming resurrection", "incoming resurrection icon", "incoming resurrection indicator", "incoming resurrection symbol", "wiederbelebung icon", "wiederbelebungs icon", "eingehende wiederbelebung",
        },
    },
}

local extraSpecs = A.GroupFramesRegistryData.GROUP_STATUS_ICON_EXTRA_SPECS
if type(extraSpecs) == "table" then
    local specs = A.GroupFramesRegistryData.GROUP_STATUS_ICON_SPECS
    for i = 1, #extraSpecs do
        specs[#specs + 1] = extraSpecs[i]
    end
end
