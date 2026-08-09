-- Assistant Auras unit-lane geometry registry helpers.
-- Loaded before MSUF_AssistantRegistry_AurasUnitLanes.lua; the unit-lane registry calls this helper inside its loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterUnitLaneGeometrySettings(ctx, unit, laneInfo)
    if type(ctx) ~= "table" or type(laneInfo) ~= "table" then return end

    local Assistant = ctx.A or A
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local RegisterAuraUnitLaneNumber = ctx.RegisterAuraUnitLaneNumber
    local RegisterAuraUnitLaneEnum = ctx.RegisterAuraUnitLaneEnum
    local AuraLaneXKey = ctx.AuraLaneXKey
    local AuraLaneYKey = ctx.AuraLaneYKey
    local AuraLaneDefaultY = ctx.AuraLaneDefaultY
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AURA_LANE_GROWTH_VALUES = ctx.AURA_LANE_GROWTH_VALUES
    local AURA_LANE_GROWTH_ALIASES = ctx.AURA_LANE_GROWTH_ALIASES
    local AuraReadLaneGrowthPair = ctx.AuraReadLaneGrowthPair
    local AuraWriteLaneGrowthPair = ctx.AuraWriteLaneGrowthPair
    local AURA_ANCHOR_VALUES = ctx.AURA_ANCHOR_VALUES
    local AURA_ANCHOR_ALIASES = ctx.AURA_ANCHOR_ALIASES
    local AuraReadLaneAnchor = ctx.AuraReadLaneAnchor
    local AuraWriteLaneAnchor = ctx.AuraWriteLaneAnchor
    local AuraReadLaneLayer = ctx.AuraReadLaneLayer
    local AuraWriteLaneLayer = ctx.AuraWriteLaneLayer
    local AuraReadLaneSpacing = ctx.AuraReadLaneSpacing
    local AuraWriteLaneSpacing = ctx.AuraWriteLaneSpacing
    local lane = laneInfo.key

    if type(unit) ~= "string" or type(lane) ~= "string" then return end
    if type(AddAuraLaneAliases) ~= "function" then return end
    if type(RegisterAuraUnitLaneNumber) ~= "function" or type(RegisterAuraUnitLaneEnum) ~= "function" then return end
    if type(AuraLaneXKey) ~= "function" or type(AuraLaneYKey) ~= "function" then return end
    if type(AuraLaneDefaultY) ~= "function" then return end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return end
    if type(AuraReadLaneGrowthPair) ~= "function" or type(AuraWriteLaneGrowthPair) ~= "function" then return end
    if type(AuraReadLaneAnchor) ~= "function" or type(AuraWriteLaneAnchor) ~= "function" then return end
    if type(AuraReadLaneLayer) ~= "function" or type(AuraWriteLaneLayer) ~= "function" then return end
    if type(AuraReadLaneSpacing) ~= "function" or type(AuraWriteLaneSpacing) ~= "function" then return end
    if type(Assistant._AssistantAddAuraAllLaneNouns) ~= "function" then return end
    if type(Assistant._AssistantAddAllAuraNouns) ~= "function" then return end

    local aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "x")
    AddAuraLaneAliases(aliases, unit, lane, "x offset")
    AddAuraLaneAliases(aliases, unit, lane, "left")
    AddAuraLaneAliases(aliases, unit, lane, "right")
    AddAuraLaneAliases(aliases, unit, lane, "links")
    AddAuraLaneAliases(aliases, unit, lane, "rechts")
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "x", "x offset", "left", "right", "links", "rechts" })
    aliases[#aliases + 1] = "all unit aura left"
    aliases[#aliases + 1] = "all unit auras left"
    aliases[#aliases + 1] = "all unit aura right"
    aliases[#aliases + 1] = "all unit auras right"
    aliases[#aliases + 1] = "all aura left"
    aliases[#aliases + 1] = "all auras left"
    aliases[#aliases + 1] = "all aura right"
    aliases[#aliases + 1] = "all auras right"
    aliases[#aliases + 1] = lane == "buff" and "all unit buffs left" or "all unit debuffs left"
    aliases[#aliases + 1] = lane == "buff" and "all unit buffs right" or "all unit debuffs right"
    aliases[#aliases + 1] = lane == "buff" and "all buffs left" or "all debuffs left"
    aliases[#aliases + 1] = lane == "buff" and "all buffs right" or "all debuffs right"
    RegisterAuraUnitLaneNumber(unit, lane, "offsetX", laneInfo.label .. " X Offset", 0, -300, 300, 1, aliases,
        function() return AuraReadNumber(unit, AuraLaneXKey(lane), 0, -4096, 4096) end,
        function(value) AuraWriteNumber(unit, AuraLaneXKey(lane), value, -4096, 4096) end,
        { moveAxis = "x", moveStep = 10 })

    aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "y")
    AddAuraLaneAliases(aliases, unit, lane, "y offset")
    AddAuraLaneAliases(aliases, unit, lane, "up")
    AddAuraLaneAliases(aliases, unit, lane, "down")
    AddAuraLaneAliases(aliases, unit, lane, "hoch")
    AddAuraLaneAliases(aliases, unit, lane, "runter")
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "y", "y offset", "up", "down", "hoch", "runter" })
    aliases[#aliases + 1] = "all unit aura up"
    aliases[#aliases + 1] = "all unit auras up"
    aliases[#aliases + 1] = "all unit aura down"
    aliases[#aliases + 1] = "all unit auras down"
    aliases[#aliases + 1] = "all aura up"
    aliases[#aliases + 1] = "all auras up"
    aliases[#aliases + 1] = "all aura down"
    aliases[#aliases + 1] = "all auras down"
    aliases[#aliases + 1] = lane == "buff" and "all unit buffs up" or "all unit debuffs up"
    aliases[#aliases + 1] = lane == "buff" and "all unit buffs down" or "all unit debuffs down"
    aliases[#aliases + 1] = lane == "buff" and "all buffs up" or "all debuffs up"
    aliases[#aliases + 1] = lane == "buff" and "all buffs down" or "all debuffs down"
    RegisterAuraUnitLaneNumber(unit, lane, "offsetY", laneInfo.label .. " Y Offset", AuraLaneDefaultY(lane), -300, 300, 1, aliases,
        function() return AuraReadNumber(unit, AuraLaneYKey(lane), AuraLaneDefaultY(lane), -4096, 4096) end,
        function(value) AuraWriteNumber(unit, AuraLaneYKey(lane), value, -4096, 4096) end,
        { moveAxis = "y", moveStep = 10 })

    aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "growth")
    AddAuraLaneAliases(aliases, unit, lane, "grow")
    AddAuraLaneAliases(aliases, unit, lane, "growth direction")
    AddAuraLaneAliases(aliases, unit, lane, "grow direction")
    aliases[#aliases + 1] = "unit aura growth"
    aliases[#aliases + 1] = "unit auras growth"
    aliases[#aliases + 1] = "unit aura grow"
    aliases[#aliases + 1] = "all unit aura growth"
    aliases[#aliases + 1] = "all unit auras growth"
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "growth", "grow", "growth direction", "grow direction" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "growth", "grow", "growth direction", "grow direction" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "growth", "grow", "growth direction", "grow direction" })
    RegisterAuraUnitLaneEnum(unit, lane, "growth", laneInfo.label .. " Growth", AURA_LANE_GROWTH_VALUES, AURA_LANE_GROWTH_ALIASES, aliases,
        function() return AuraReadLaneGrowthPair(unit, lane) end,
        function(value) AuraWriteLaneGrowthPair(unit, lane, value) end)

    aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "anchor")
    AddAuraLaneAliases(aliases, unit, lane, "anchor point")
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "anchor", "anchor point", "position anchor" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "anchor", "anchor point", "position anchor" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "anchor", "anchor point", "position anchor" })
    RegisterAuraUnitLaneEnum(unit, lane, "anchor", laneInfo.label .. " Anchor", AURA_ANCHOR_VALUES, AURA_ANCHOR_ALIASES, aliases,
        function() return AuraReadLaneAnchor(unit, lane) end,
        function(value) AuraWriteLaneAnchor(unit, lane, value) end)

    aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "spacing")
    AddAuraLaneAliases(aliases, unit, lane, "gap")
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "spacing", "gap", "icon gap" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "spacing", "gap", "icon gap" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "spacing", "gap", "icon gap" })
    RegisterAuraUnitLaneNumber(unit, lane, "spacing", laneInfo.label .. " Spacing", 2, 0, 12, 1, aliases,
        function() return AuraReadLaneSpacing(unit, lane) end,
        function(value) AuraWriteLaneSpacing(unit, lane, value) end)

    aliases = {}
    AddAuraLaneAliases(aliases, unit, lane, "layer")
    AddAuraLaneAliases(aliases, unit, lane, "z layer")
    AddAuraLaneAliases(aliases, unit, lane, "z level")
    AddAuraLaneAliases(aliases, unit, lane, "z order")
    AddAuraLaneAliases(aliases, unit, lane, "z index")
    AddAuraLaneAliases(aliases, unit, lane, "draw layer")
    AddAuraLaneAliases(aliases, unit, lane, "frame level")
    AddAuraLaneAliases(aliases, unit, lane, "strata")
    Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
    RegisterAuraUnitLaneNumber(unit, lane, "layer", laneInfo.label .. " Layer", lane == "buff" and 5 or 6, 0, 30, 1, aliases,
        function() return AuraReadLaneLayer(unit, lane) end,
        function(value) AuraWriteLaneLayer(unit, lane, value) end)
end
