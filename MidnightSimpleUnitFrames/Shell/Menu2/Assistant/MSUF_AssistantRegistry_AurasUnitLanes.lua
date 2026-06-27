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
    local RegisterUnitLaneGeometrySettings = A.AurasRegistry and A.AurasRegistry.RegisterUnitLaneGeometrySettings

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
    if type(RegisterUnitLaneGeometrySettings) ~= "function" then return end
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
            AddAuraLaneAliases(aliases, unit, lane, "max")
            AddAuraLaneAliases(aliases, unit, lane, "max icons")
            AddAuraLaneAliases(aliases, unit, lane, "maximum")
            AddAuraLaneAliases(aliases, unit, lane, "maximum icons")
            AddAuraLaneAliases(aliases, unit, lane, "count")
            AddAuraLaneAliases(aliases, unit, lane, "cap")
            AddAuraLaneAliases(aliases, unit, lane, "limit")
            Assistant._AssistantAddAuraAllLaneNouns(aliases, unit, { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all unit", { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
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

            RegisterUnitLaneGeometrySettings(ctx, unit, laneInfo)
        end
    end
end
