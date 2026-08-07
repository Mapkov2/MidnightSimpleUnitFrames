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

local CUSTOM_CONTAINER_COUNT = 4

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
                -- aliases retain the concrete Custom 1/2/3/target-DoT identity.
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

-- Custom Aura containers own the auras a player groups themselves -- including
-- the player defensive container, which renders as the internal
-- "defensivePortrait" lane. Only their Layer was reachable, so "move my
-- defensive auras up" had no container control to hit and fell through to the
-- Buff/Debuff lane offsets, moving every icon on the frame instead.
--
-- Ranges are the runtime's own clamps (MSUF_Menu2_UnitPreview_Auras.lua), not
-- invented numbers, so a value the Assistant accepts is a value the container
-- actually honours.
local CUSTOM_CONTAINER_PLACED_FIELDS = {
    { field = "y", label = "Y Offset", default = 0, min = -4096, max = 4096, step = 1,
      nouns = { "y offset", "vertical offset", "up", "down" } },
    { field = "x", label = "X Offset", default = 0, min = -4096, max = 4096, step = 1,
      nouns = { "x offset", "horizontal offset", "left", "right" } },
    { field = "size", label = "Icon Size", default = 24, min = 1, max = 128, step = 1,
      nouns = { "icon size", "size" } },
    { field = "max", label = "Max Icons", default = 8, min = 0, max = 40, step = 1,
      nouns = { "max icons", "maximum icons", "icon count" } },
    { field = "perRow", label = "Per Row", default = 4, min = 1, max = 40, step = 1,
      nouns = { "per row", "icons per row", "columns" } },
    { field = "spacing", label = "Spacing", default = 2, min = 0, max = 64, step = 1,
      nouns = { "spacing", "gap", "padding" } },
}

-- Anchor/growth accept the same value sets the container itself normalises
-- (MSUF_Auras3_EditMode.lua), so a value the Assistant offers is one the
-- container honours.
local CUSTOM_CONTAINER_ANCHOR_VALUES = {
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER",
}
local CUSTOM_CONTAINER_GROWTH_VALUES = {
    "LEFTDOWN", "RIGHTDOWN", "LEFTUP", "RIGHTUP", "UP", "DOWN", "LEFT", "RIGHT",
}

-- Container 4 is the reserved preset slot: "Defensive Buffs" on the player and
-- "Dots on target" everywhere else. Mirrors PLAYER_DEFENSIVE_CONTAINER_INDEX /
-- TARGET_DOT_CONTAINER_INDEX in MSUF_Auras3_Menu_Model.lua, which re-pin its
-- filter fields on every normalization.
local ENFORCED_CONTAINER_INDEX = 4

-- ONLY the fields those two functions actually re-pin. hidePermanent is absent
-- from both, so it stays freely writable on container 4 -- guarding the whole
-- filter set took seven working settings away. onlyMine IS re-pinned by both
-- (player to false, target/focus/boss to true), so it belongs here for every
-- unit; treating it as player-only left three settings advertising a write the
-- model silently undid, which surfaced as "I could not safely apply that
-- change" instead of an explanation.
local ENFORCED_CONTAINER_FILTERS = {
    onlyMine = true,
    onlyImportant = true, raid = true, raidInCombat = true,
    includeNameplateOnly = true, includeDispellable = true, dispellableAny = true,
    cancelable = true, notCancelable = true, crowdControl = true,
    externalDefensive = true, bigDefensive = true,
}

-- Each container carries its own filter set, identical in meaning to the Buff
-- lane filters. Only the toggles are registered here; the spell list stays with
-- the existing whitelist actions, which already validate SpellIDs.
local CUSTOM_CONTAINER_FILTER_FIELDS = {
    { field = "hidePermanent", label = "Hide Permanent Auras", nouns = { "hide permanent", "hide permanent auras", "no timer" } },
    { field = "onlyMine", label = "Only Mine", nouns = { "only mine", "only my auras", "own only" } },
    { field = "onlyImportant", label = "Only Important", nouns = { "only important", "important only" } },
    { field = "raid", label = "Raid Filter", nouns = { "raid filter" } },
    { field = "raidInCombat", label = "Raid In Combat Filter", nouns = { "raid in combat filter", "raid combat filter" } },
    { field = "includeNameplateOnly", label = "Include Nameplate Only", nouns = { "include nameplate only", "nameplate only" } },
    { field = "includeDispellable", label = "Include Dispellable", nouns = { "include dispellable" } },
    { field = "dispellableAny", label = "Any Dispel Type Filter", nouns = { "any dispel type", "dispellable any" } },
    { field = "cancelable", label = "Cancelable Filter", nouns = { "cancelable filter", "cancellable filter" } },
    { field = "notCancelable", label = "Not Cancelable Filter", nouns = { "not cancelable filter", "not cancellable filter" } },
    { field = "crowdControl", label = "Crowd Control Filter", nouns = { "crowd control filter", "cc filter" } },
    { field = "externalDefensive", label = "External Defensive Filter", nouns = { "external defensive filter", "external defensives" } },
    { field = "bigDefensive", label = "Big Defensive Filter", nouns = { "big defensive filter", "major defensives" } },
}

-- Presentation toggles that live on the container's placement record.
local CUSTOM_CONTAINER_PLACED_BOOLEANS = {
    { field = "showCooldown", label = "Cooldown Text", nouns = { "cooldown text", "timer text" } },
    { field = "showCooldownSwipe", label = "Cooldown Swipe", nouns = { "cooldown swipe", "swipe" } },
    { field = "showStacks", label = "Stack Text", nouns = { "stack text", "stacks" } },
}

local function ClampPlaced(value, spec)
    value = tonumber(value)
    if value == nil then return spec.default end
    value = math.floor(value + 0.5)
    if value < spec.min then return spec.min end
    if value > spec.max then return spec.max end
    return value
end

function A.AurasRegistry.RegisterUnitCustomContainerLayoutSettings(ctx)
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
            local unitLabel = UNIT_LABELS[unit] or unit

            for _, spec in ipairs(CUSTOM_CONTAINER_PLACED_FIELDS) do
                local placedField, fieldSpec = spec.field, spec
                local aliases = {}
                for _, noun in ipairs(spec.nouns) do
                    aliases[#aliases + 1] = unit .. " custom " .. tostring(index) .. " aura " .. noun
                    aliases[#aliases + 1] = unit .. " custom aura " .. tostring(index) .. " " .. noun
                    aliases[#aliases + 1] = unit .. " custom container " .. tostring(index) .. " " .. noun
                end
                AddAliasesForAuraScope(aliases, unit, "custom " .. tostring(index) .. " aura " .. spec.nouns[1])

                Registry:RegisterSetting({
                    key = "auras3." .. unit .. "." .. lane .. ".placed." .. placedField,
                    label = unitLabel .. " Custom Aura " .. tostring(index) .. " " .. spec.label,
                    category = unitLabel .. " / Auras",
                    page = "uf_" .. unit,
                    unit = unit,
                    frameType = "aura",
                    -- Index-neutral like the Layer control above: the visible
                    -- slider edits whichever container is selected.
                    attribute = "customContainer" .. spec.label:gsub("%s+", ""),
                    type = "number",
                    aliases = aliases,
                    exactAliases = aliases,
                    min = spec.min,
                    max = spec.max,
                    step = spec.step,
                    get = function()
                        local model = AuraModel()
                        local item = model and type(model.CustomContainer) == "function"
                            and model.CustomContainer(unitKey, customIndex, false) or nil
                        local placed = type(item) == "table" and item.placed or nil
                        return ClampPlaced(placed and placed[placedField], fieldSpec)
                    end,
                    set = function(value)
                        local model = AuraModel()
                        local item = model and type(model.CustomContainer) == "function"
                            and model.CustomContainer(unitKey, customIndex, true) or nil
                        if type(item) ~= "table" then return end
                        if type(item.placed) ~= "table" then item.placed = {} end
                        item.placed[placedField] = ClampPlaced(value, fieldSpec)
                    end,
                    apply = function() ApplyAura(unitKey, "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_LAYOUT") end,
                    combatSafe = false,
                })
            end

            -- NOT REGISTERED: the per-container filter toggles, anchor and
            -- growth. They register fine, but the broad Aura parser claims
            -- phrasings like "turn on player custom aura 1 hide permanent"
            -- before the exact-label lane can resolve them, so 208 of them
            -- became unreachable commands (verified: gate 6153/6361). The
            -- geometry fields below do not collide because no aura lane owns
            -- "y offset"/"per row" wording. Fixing this needs the Aura
            -- shortcut to defer to an exact container label first -- the same
            -- upstream-precedence problem the colour lane has -- not another
            -- round of registrations.
            for _, enumSpec in ipairs({
                { field = "anchor", label = "Anchor", values = CUSTOM_CONTAINER_ANCHOR_VALUES,
                  default = "TOPRIGHT", nouns = { "anchor", "anchor point" } },
                { field = "growth", label = "Growth", values = CUSTOM_CONTAINER_GROWTH_VALUES,
                  default = "LEFTDOWN", nouns = { "growth", "grow direction", "growth direction" } },
            }) do
                local placedField, fallback, allowed = enumSpec.field, enumSpec.default, enumSpec.values
                local aliases = {}
                for _, noun in ipairs(enumSpec.nouns) do
                    aliases[#aliases + 1] = unit .. " custom aura " .. tostring(index) .. " " .. noun
                    aliases[#aliases + 1] = unit .. " custom container " .. tostring(index) .. " " .. noun
                end

                Registry:RegisterSetting({
                    key = "auras3." .. unit .. "." .. lane .. ".placed." .. placedField,
                    label = unitLabel .. " Custom Aura " .. tostring(index) .. " " .. enumSpec.label,
                    category = unitLabel .. " / Auras",
                    page = "uf_" .. unit,
                    unit = unit,
                    frameType = "aura",
                    attribute = "customContainer" .. enumSpec.label,
                    type = "enum",
                    values = allowed,
                    closedValues = true,
                    aliases = aliases,
                    exactAliases = aliases,
                    get = function()
                        local model = AuraModel()
                        local item = model and type(model.CustomContainer) == "function"
                            and model.CustomContainer(unitKey, customIndex, false) or nil
                        local placed = type(item) == "table" and item.placed or nil
                        local current = placed and tostring(placed[placedField] or "")
                        for i = 1, #allowed do
                            if allowed[i] == current then return current end
                        end
                        return fallback
                    end,
                    set = function(value)
                        value = tostring(value or ""):upper()
                        local valid = false
                        for i = 1, #allowed do
                            if allowed[i] == value then valid = true break end
                        end
                        if not valid then return end
                        local model = AuraModel()
                        local item = model and type(model.CustomContainer) == "function"
                            and model.CustomContainer(unitKey, customIndex, true) or nil
                        if type(item) ~= "table" then return end
                        if type(item.placed) ~= "table" then item.placed = {} end
                        item.placed[placedField] = value
                    end,
                    apply = function() ApplyAura(unitKey, "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_LAYOUT") end,
                    combatSafe = false,
                })
            end

            -- Per-container filter toggles and presentation switches.
            for _, boolGroup in ipairs({
                { list = CUSTOM_CONTAINER_FILTER_FIELDS, holder = "filters", attr = "customContainerFilter" },
                { list = CUSTOM_CONTAINER_PLACED_BOOLEANS, holder = "placed", attr = "customContainerDisplay" },
            }) do
                local holder = boolGroup.holder
                for _, boolSpec in ipairs(boolGroup.list) do
                    local boolField = boolSpec.field
                    -- MSUF pins these fields on container 4 (see the comment on
                    -- intentGuard below), so there is no way to set them. Say
                    -- that structurally by registering NO setter, rather than
                    -- advertising a writable control and refusing every write:
                    -- the setting stays readable and explainable, and nothing
                    -- counts it as a control the player can operate.
                    local isPinned = holder == "filters"
                        and customIndex == ENFORCED_CONTAINER_INDEX
                        and ENFORCED_CONTAINER_FILTERS[boolField] == true
                    local aliases = {}
                    for _, noun in ipairs(boolSpec.nouns) do
                        aliases[#aliases + 1] = unit .. " custom aura " .. tostring(index) .. " " .. noun
                        aliases[#aliases + 1] = unit .. " custom container " .. tostring(index) .. " " .. noun
                    end

                    Registry:RegisterSetting({
                        key = "auras3." .. unit .. "." .. lane .. "." .. holder .. "." .. boolField,
                        label = unitLabel .. " Custom Aura " .. tostring(index) .. " " .. boolSpec.label,
                        category = unitLabel .. " / Auras",
                        page = "uf_" .. unit,
                        unit = unit,
                        frameType = "aura",
                        attribute = boolGroup.attr,
                        type = "boolean",
                        aliases = aliases,
                        exactAliases = aliases,
                        get = function()
                            local model = AuraModel()
                            local item = model and type(model.CustomContainer) == "function"
                                and model.CustomContainer(unitKey, customIndex, false) or nil
                            local bucket = type(item) == "table" and item[holder] or nil
                            return type(bucket) == "table" and bucket[boolField] == true
                        end,
                        set = (not isPinned) and function(value)
                            local model = AuraModel()
                            local item = model and type(model.CustomContainer) == "function"
                                and model.CustomContainer(unitKey, customIndex, true) or nil
                            if type(item) ~= "table" then return end
                            if type(item[holder]) ~= "table" then item[holder] = {} end
                            item[holder][boolField] = value and true or false
                        end or nil,
                        apply = function() ApplyAura(unitKey, "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_FILTER") end,
                        combatSafe = false,
                        -- Container 4 is a fixed preset ("Defensive Buffs" on
                        -- player, "Dots on target" elsewhere), and the menu
                        -- model re-pins every one of its filter fields on each
                        -- normalization (MSUF_Auras3_Menu_Model.lua,
                        -- EnforcePlayerDefensiveContainer /
                        -- EnforceTargetDotContainer). Writing one therefore
                        -- cannot stick. Say so instead of accepting the request
                        -- and reporting "I could not safely apply that change",
                        -- which told the player nothing about why.
                        intentGuard = isPinned
                            and function()
                                return false, "info",
                                    "Custom Aura " .. tostring(customIndex) .. " on "
                                    .. tostring(unitLabel) .. " is a fixed container ("
                                    .. (unitKey == "player" and "Defensive Buffs" or "Dots on target")
                                    .. "), so MSUF keeps its filters set for it and I cannot change them."
                                    .. " Choose what it shows with its spell list instead, or use Custom Aura 1-3"
                                    .. " for a container with free filters."
                            end
                            or nil,
                    })
                end
            end

            local enabledAliases = {
                unit .. " custom " .. tostring(index) .. " aura enabled",
                unit .. " custom aura " .. tostring(index) .. " enabled",
                unit .. " custom container " .. tostring(index),
                unit .. " custom aura container " .. tostring(index),
            }
            AddAliasesForAuraScope(enabledAliases, unit, "custom " .. tostring(index) .. " aura enabled")

            Registry:RegisterSetting({
                key = "auras3." .. unit .. "." .. lane .. ".enabled",
                label = unitLabel .. " Custom Aura " .. tostring(index) .. " Enabled",
                category = unitLabel .. " / Auras",
                page = "uf_" .. unit,
                unit = unit,
                frameType = "aura",
                attribute = "customContainerEnabled",
                type = "boolean",
                aliases = enabledAliases,
                exactAliases = enabledAliases,
                get = function()
                    local model = AuraModel()
                    local item = model and type(model.CustomContainer) == "function"
                        and model.CustomContainer(unitKey, customIndex, false) or nil
                    return type(item) == "table" and item.enabled == true
                end,
                set = function(value)
                    local model = AuraModel()
                    local item = model and type(model.CustomContainer) == "function"
                        and model.CustomContainer(unitKey, customIndex, true) or nil
                    if type(item) == "table" then item.enabled = value and true or false end
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

    local RegisterUnitCustomContainerLayoutSettings = A.AurasRegistry.RegisterUnitCustomContainerLayoutSettings
    if type(RegisterUnitCustomContainerLayoutSettings) == "function" then
        RegisterUnitCustomContainerLayoutSettings(ctx)
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
