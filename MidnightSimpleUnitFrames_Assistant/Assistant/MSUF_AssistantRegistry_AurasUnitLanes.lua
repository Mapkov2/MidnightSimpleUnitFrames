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

local CUSTOM_CONTAINER_COUNT = 3

local function ClampLayer(value, fallback)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 9 end
    value = math.floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

function A.AurasRegistry.RegisterUnitCustomContainerLayerSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AURA_UNITS = ctx.AURA_UNITS or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AuraModel = ctx.AuraModel
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AuraModel) ~= "function" then return end
    if type(ApplyAura) ~= "function" then return end

    for _, unit in ipairs(AURA_UNITS) do
        for index = 1, CUSTOM_CONTAINER_COUNT do
            local unitKey, customIndex = unit, index
            local lane = "custom" .. tostring(index)
            local aliases = {
                unit .. " custom " .. tostring(index) .. " aura layer",
                unit .. " custom aura " .. tostring(index) .. " layer",
                unit .. " custom container " .. tostring(index) .. " layer",
                unit .. " custom aura container " .. tostring(index) .. " layer",
            }
            AddAliasesForAuraScope(aliases, unit, "custom " .. tostring(index) .. " aura layer")

            Registry:RegisterSetting({
                key = "auras3." .. unit .. "." .. lane .. ".layer",
                label = (UNIT_LABELS[unit] or unit) .. " Custom Aura " .. tostring(index) .. " Layer",
                category = (UNIT_LABELS[unit] or unit) .. " / Auras",
                page = "uf_" .. unit,
                unit = unit,
                frameType = "aura",
                -- The visible slider is one selected-container control. Keep
                -- its semantic attribute index-neutral; the setting key and
                -- aliases retain the concrete Custom 1/2/3 identity.
                attribute = "customContainerLayer",
                type = "number",
                aliases = aliases,
                exactAliases = aliases,
                min = 0,
                max = 30,
                step = 1,
                get = function()
                    local model = AuraModel()
                    local item = model and type(model.CustomContainer) == "function"
                        and model.CustomContainer(unitKey, customIndex, false) or nil
                    return ClampLayer(item and item.layer, 9)
                end,
                set = function(value)
                    local model = AuraModel()
                    local item = model and type(model.CustomContainer) == "function"
                        and model.CustomContainer(unitKey, customIndex, true) or nil
                    if item then item.layer = ClampLayer(value, 9) end
                end,
                apply = function() ApplyAura(unitKey, "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_LAYOUT") end,
                combatSafe = false,
            })
        end
    end
end

function A.AurasRegistry.RegisterUnitLaneSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterUnitCustomContainerLayerSettings = A.AurasRegistry.RegisterUnitCustomContainerLayerSettings
    if type(RegisterUnitCustomContainerLayerSettings) == "function" then
        RegisterUnitCustomContainerLayerSettings(ctx)
    end

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
    local unitPages = {
        player = "uf_player", target = "uf_target", focus = "uf_focus", boss = "uf_boss",
    }
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
            local unitLabel = tostring(unit):gsub("^%l", string.upper)
            local aliases = {}
            AddAliasesForAuraScope(aliases, unit, laneInfo.plural:lower())
            AddAuraLaneAliases(aliases, unit, lane, "lane")
            AddAuraLaneAliases(aliases, unit, lane, "visibility")
            AddAuraLaneAliases(aliases, unit, lane, "shown")
            RegisterAuraUnitLaneBoolean(unit, lane, "visible", laneInfo.plural, aliases, {
                page = unitPages[unit],
                description = "Shows or hides the entire " .. unitLabel .. " " .. laneInfo.label:lower()
                    .. " icon lane. This is lane visibility, not filtering: it does not change Filters Enabled, Hide Permanent, or any individual Blizzard filter token.",
            })

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
