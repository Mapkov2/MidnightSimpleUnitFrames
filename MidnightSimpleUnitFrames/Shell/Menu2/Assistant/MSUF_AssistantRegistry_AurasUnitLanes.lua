-- Assistant Auras unit-lane registry: per-unit buff/debuff lane settings.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main domain passes its local helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterUnitLaneSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Assistant = ctx.A or A
    local AURA_UNITS = ctx.AURA_UNITS or {}
    local AURA_LANES = ctx.AURA_LANES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local AddAuraLaneRelativeSizeAliases = ctx.AddAuraLaneRelativeSizeAliases
    local RegisterAuraUnitLaneBoolean = ctx.RegisterAuraUnitLaneBoolean
    local RegisterAuraUnitLaneNumber = ctx.RegisterAuraUnitLaneNumber
    local RegisterAuraUnitLaneEnum = ctx.RegisterAuraUnitLaneEnum
    local AuraLaneDefaultMax = ctx.AuraLaneDefaultMax
    local AuraLaneMaxKey = ctx.AuraLaneMaxKey
    local AuraLaneSizeKey = ctx.AuraLaneSizeKey
    local AuraLaneXKey = ctx.AuraLaneXKey
    local AuraLaneYKey = ctx.AuraLaneYKey
    local AuraLaneDefaultY = ctx.AuraLaneDefaultY
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraReadLanePerRow = ctx.AuraReadLanePerRow
    local AuraWriteLanePerRow = ctx.AuraWriteLanePerRow
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

    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AddAuraLaneRelativeSizeAliases) ~= "function" then return end
    if type(RegisterAuraUnitLaneBoolean) ~= "function" or type(RegisterAuraUnitLaneNumber) ~= "function" then return end
    if type(RegisterAuraUnitLaneEnum) ~= "function" then return end
    if type(AuraLaneDefaultMax) ~= "function" or type(AuraLaneMaxKey) ~= "function" then return end
    if type(AuraLaneSizeKey) ~= "function" or type(AuraLaneXKey) ~= "function" then return end
    if type(AuraLaneYKey) ~= "function" or type(AuraLaneDefaultY) ~= "function" then return end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return end
    if type(AuraReadLanePerRow) ~= "function" or type(AuraWriteLanePerRow) ~= "function" then return end
    if type(AuraReadLaneGrowthPair) ~= "function" or type(AuraWriteLaneGrowthPair) ~= "function" then return end
    if type(AuraReadLaneAnchor) ~= "function" or type(AuraWriteLaneAnchor) ~= "function" then return end
    if type(AuraReadLaneLayer) ~= "function" or type(AuraWriteLaneLayer) ~= "function" then return end
    if type(Assistant._AssistantAddAuraAllLaneNouns) ~= "function" then return end
    if type(Assistant._AssistantAddAuraAllLaneRelativeSizeAliases) ~= "function" then return end
    if type(Assistant._AssistantAddAllAuraNouns) ~= "function" then return end
    if type(Assistant._AssistantAddAllAuraRelativeSizeAliases) ~= "function" then return end

    for _, unit in ipairs(AURA_UNITS) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            local aliases = {}
            AddAliasesForAuraScope(aliases, unit, laneInfo.plural:lower())
            AddAuraLaneAliases(aliases, unit, lane, "visibility")
            AddAuraLaneAliases(aliases, unit, lane, "shown")
            RegisterAuraUnitLaneBoolean(unit, lane, "visible", laneInfo.plural, aliases)

            aliases = {}
            AddAuraLaneAliases(aliases, unit, lane, "max icons")
            AddAuraLaneAliases(aliases, unit, lane, "count")
            Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "max icons", "maximum icons", "icon count", "count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "max icons", "maximum icons", "icon count", "count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "max icons", "maximum icons", "icon count", "count" })
            RegisterAuraUnitLaneNumber(unit, lane, "max", laneInfo.label .. " Max Icons", AuraLaneDefaultMax(lane), 0, 80, 1, aliases,
                function() return AuraReadNumber(unit, AuraLaneMaxKey(lane), AuraLaneDefaultMax(lane), 0, 80) end,
                function(value) AuraWriteNumber(unit, AuraLaneMaxKey(lane), value, 0, 80) end)

            aliases = {}
            AddAuraLaneAliases(aliases, unit, lane, "size")
            AddAuraLaneAliases(aliases, unit, lane, "icon size")
            AddAuraLaneRelativeSizeAliases(aliases, unit, lane)
            Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "size", "icon size" })
            Assistant._AssistantAddAuraAllLaneRelativeSizeAliases(aliases, unit)
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "size", "icon size" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "size", "icon size" })
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all unit")
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all")
            RegisterAuraUnitLaneNumber(unit, lane, "size", laneInfo.label .. " Icon Size", 26, 10, 80, 1, aliases,
                function() return AuraReadNumber(unit, AuraLaneSizeKey(lane), 26, 1, 128) end,
                function(value) AuraWriteNumber(unit, AuraLaneSizeKey(lane), value, 1, 128) end)

            aliases = {}
            AddAuraLaneAliases(aliases, unit, lane, "per row")
            AddAuraLaneAliases(aliases, unit, lane, "icons per row")
            Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "per row", "icons per row", "wrap count", "row count" })
            RegisterAuraUnitLaneNumber(unit, lane, "perRow", laneInfo.label .. " Icons Per Row", 12, 1, 40, 1, aliases,
                function() return AuraReadLanePerRow(unit, lane) end,
                function(value) AuraWriteLanePerRow(unit, lane, value) end)

            aliases = {}
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
                function() return AuraReadNumber(unit, "spacing", 2, 0, 64) end,
                function(value) AuraWriteNumber(unit, "spacing", value, 0, 64) end)

            aliases = {}
            AddAuraLaneAliases(aliases, unit, lane, "layer")
            AddAuraLaneAliases(aliases, unit, lane, "z order")
            Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "layer", "z order", "frame level" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "layer", "z order", "frame level" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "layer", "z order", "frame level" })
            RegisterAuraUnitLaneNumber(unit, lane, "layer", laneInfo.label .. " Layer", lane == "buff" and 5 or 6, 1, 15, 1, aliases,
                function() return AuraReadLaneLayer(unit, lane) end,
                function(value) AuraWriteLaneLayer(unit, lane, value) end)
        end
    end
end
