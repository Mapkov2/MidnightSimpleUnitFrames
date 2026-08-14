-- Assistant group aura lane settings.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

local function ClampLayer(value, fallback)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 7 end
    value = math.floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

function A.AurasRegistry.RegisterGroupExternalLayerSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GF_AURA_GROUPS = ctx.GF_AURA_GROUPS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GFAurasRoot) ~= "function" then return end
    if type(ApplyGroup) ~= "function" then return end

    for _, scope in ipairs(GF_AURA_GROUPS) do
        local scopeKey = scope
        local aliases = {
            scope .. " external defensive layer",
            scope .. " external defensives layer",
            scope .. " externals layer",
            scope .. " external aura layer",
        }
        AddAliasesForUnit(aliases, scope, "external defensive layer")
        AddAliasesForUnit(aliases, scope, "externals layer")

        Registry:RegisterSetting({
            key = "gf_" .. scope .. ".auras.externals.layer",
            label = (UNIT_LABELS[scope] or scope) .. " External Defensive Layer",
            category = (UNIT_LABELS[scope] or scope) .. " / Group Auras",
            page = "gf_auras",
            unit = scope,
            frameType = "groupAura",
            -- The selected Group scope/lane is UI state; this attribute names
            -- the visible External Defensive Layer control itself.
            attribute = "externalLayer",
            type = "number",
            aliases = aliases,
            exactAliases = aliases,
            min = 0,
            max = 30,
            step = 1,
            get = function()
                local root = GFAurasRoot(scopeKey)
                local externals = root and root.externals
                return ClampLayer(externals and externals.layer, 7)
            end,
            set = function(value)
                local root = GFAurasRoot(scopeKey)
                if not root then return end
                root.externals = type(root.externals) == "table" and root.externals or {}
                root.externals.layer = ClampLayer(value, 7)
            end,
            apply = function() ApplyGroup(scopeKey, "auras") end,
            combatSafe = false,
        })

        -- Layer was the only reachable external-defensive control, so the lane
        -- could be drawn but not turned on, capped or aimed. These are the rest
        -- of the record the group config reads
        -- (MSUF_UF_Group_Config.lua: externals.enabled/max/growth/
        -- autoBlacklistBuffs).
        local EXTERNAL_FIELDS = {
            -- Deliberately "Lane": a bare "external defensives" is the Buff
            -- filter token, and giving this setting that wording made the two
            -- indistinguishable. The lane toggle keeps the explicit noun.
            { field = "enabled", label = "External Defensive Lane", type = "boolean", default = true,
              nouns = { "external defensive lane", "externals lane", "external defensive strip" } },
            -- Both spellings on purpose: normalization keeps hyphens, so the
            -- control's OWN label ("...Auto-blacklist from Buffs") matched none
            -- of the spaced aliases and the setting could not be reached by the
            -- name the menu shows for it.
            { field = "autoBlacklistBuffs", label = "External Defensive Auto-blacklist from Buffs",
              type = "boolean", default = false,
              nouns = { "external defensive auto blacklist", "externals auto blacklist from buffs",
                "external defensive auto-blacklist", "external defensive auto-blacklist from buffs",
                "externals auto-blacklist from buffs" } },
            { field = "max", label = "External Defensive Max Icons", type = "number", default = 3,
              min = 0, max = 40, step = 1,
              nouns = { "external defensive max icons", "externals max icons", "external defensive count" } },
            { field = "growth", label = "External Defensive Growth", type = "enum", default = "RIGHTDOWN",
              values = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP", "UP", "DOWN", "LEFT", "RIGHT" },
              nouns = { "external defensive growth", "externals growth", "external defensive grow direction" } },
        }

        for _, spec in ipairs(EXTERNAL_FIELDS) do
            local externalField, fieldSpec = spec.field, spec
            local fieldAliases = {}
            for _, noun in ipairs(spec.nouns) do
                fieldAliases[#fieldAliases + 1] = scope .. " " .. noun
                AddAliasesForUnit(fieldAliases, scope, noun)
            end

            local descriptor = {
                key = "gf_" .. scope .. ".auras.externals." .. externalField,
                label = (UNIT_LABELS[scope] or scope) .. " " .. spec.label,
                category = (UNIT_LABELS[scope] or scope) .. " / Group Auras",
                page = "gf_auras",
                unit = scope,
                frameType = "groupAura",
                attribute = "external" .. spec.field:sub(1, 1):upper() .. spec.field:sub(2),
                type = spec.type,
                aliases = fieldAliases,
                exactAliases = fieldAliases,
                get = function()
                    local root = GFAurasRoot(scopeKey)
                    local externals = root and root.externals
                    -- Read with an explicit branch, NOT `cond and t[k] or nil`:
                    -- that idiom collapses a stored `false` to nil, which the
                    -- boolean branch below then reports as the default. For
                    -- External Defensive Lane (default true) it meant the lane
                    -- could be written false but always read back as ON, so the
                    -- transaction's verify step rolled every "turn it off" back.
                    local current
                    if type(externals) == "table" then current = externals[externalField] end
                    if fieldSpec.type == "boolean" then
                        if current == nil then return fieldSpec.default end
                        return current == true
                    end
                    if fieldSpec.type == "number" then
                        local value = tonumber(current)
                        if value == nil then return fieldSpec.default end
                        value = math.floor(value + 0.5)
                        if value < fieldSpec.min then return fieldSpec.min end
                        if value > fieldSpec.max then return fieldSpec.max end
                        return value
                    end
                    current = tostring(current or "")
                    for i = 1, #fieldSpec.values do
                        if fieldSpec.values[i] == current then return current end
                    end
                    return fieldSpec.default
                end,
                set = function(value)
                    local root = GFAurasRoot(scopeKey)
                    if not root then return end
                    root.externals = type(root.externals) == "table" and root.externals or {}
                    if fieldSpec.type == "boolean" then
                        root.externals[externalField] = value and true or false
                        return
                    end
                    if fieldSpec.type == "number" then
                        local number = tonumber(value)
                        if number == nil then return end
                        number = math.floor(number + 0.5)
                        if number < fieldSpec.min then number = fieldSpec.min end
                        if number > fieldSpec.max then number = fieldSpec.max end
                        root.externals[externalField] = number
                        return
                    end
                    local text = tostring(value or ""):upper()
                    for i = 1, #fieldSpec.values do
                        if fieldSpec.values[i] == text then
                            root.externals[externalField] = text
                            return
                        end
                    end
                end,
                apply = function() ApplyGroup(scopeKey, "auras") end,
                combatSafe = false,
            }
            if spec.type == "number" then
                descriptor.min, descriptor.max, descriptor.step = spec.min, spec.max, spec.step
            elseif spec.type == "enum" then
                descriptor.values, descriptor.closedValues = spec.values, true
            end
            Registry:RegisterSetting(descriptor)
        end
    end
end

function A.AurasRegistry.RegisterGroupAuraLaneSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterGroupExternalLayerSettings = A.AurasRegistry.RegisterGroupExternalLayerSettings
    if type(RegisterGroupExternalLayerSettings) == "function" then
        RegisterGroupExternalLayerSettings(ctx)
    end

    local Assistant = ctx.A or A
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local AddGFAuraAliases = ctx.AddGFAuraAliases
    local AddGFAuraStrictAliases = ctx.AddGFAuraStrictAliases
    local AddGFAuraRelativeSizeAliases = ctx.AddGFAuraRelativeSizeAliases
    local RegisterGFAuraBoolean = ctx.RegisterGFAuraBoolean
    local RegisterGFAuraNumber = ctx.RegisterGFAuraNumber
    local RegisterGFAuraEnum = ctx.RegisterGFAuraEnum
    local RegisterGroupAuraRootSettings = ctx.RegisterGroupAuraRootSettings
    local GFReadAuraValue = ctx.GFReadAuraValue
    local GFWriteAuraValue = ctx.GFWriteAuraValue
    local GFReadConfValue = ctx.GFReadConfValue
    local GFWriteConfValue = ctx.GFWriteConfValue
    local ApplyGroup = ctx.ApplyGroup
    local RegisterGroupAuraLaneGeometrySettings = A.AurasRegistry and A.AurasRegistry.RegisterGroupAuraLaneGeometrySettings
    local GF_AURA_GROUPS = ctx.GF_AURA_GROUPS or {}
    local GF_AURA_ANCHORS = ctx.GF_AURA_ANCHORS or {}
    local GF_AURA_FILTER_VALUES = ctx.GF_AURA_FILTER_VALUES or {}
    local GF_AURA_FILTER_ALIASES = ctx.GF_AURA_FILTER_ALIASES
    local AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES or {}
    local AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES or {}
    local AURA_SORT_METHOD_VALUES = ctx.AURA_SORT_METHOD_VALUES or {}
    local AURA_SORT_METHOD_ALIASES = ctx.AURA_SORT_METHOD_ALIASES or {}
    local AURA_SORT_DIRECTION_VALUES = ctx.AURA_SORT_DIRECTION_VALUES or {}
    local AURA_SORT_DIRECTION_ALIASES = ctx.AURA_SORT_DIRECTION_ALIASES or {}
    local AURA_DURATION_BAR_POSITION_VALUES = ctx.AURA_DURATION_BAR_POSITION_VALUES or {}
    local AURA_DURATION_BAR_POSITION_ALIASES = ctx.AURA_DURATION_BAR_POSITION_ALIASES or {}
    local AURA_DURATION_BAR_DISPLAY_VALUES = ctx.AURA_DURATION_BAR_DISPLAY_VALUES or {}
    local AURA_DURATION_BAR_DISPLAY_ALIASES = ctx.AURA_DURATION_BAR_DISPLAY_ALIASES or {}
    local AURA_DURATION_BAR_DIRECTION_VALUES = ctx.AURA_DURATION_BAR_DIRECTION_VALUES or {}
    local AURA_DURATION_BAR_DIRECTION_ALIASES = ctx.AURA_DURATION_BAR_DIRECTION_ALIASES or {}
    local AURA_DEBUFF_TYPE_BORDER_VALUES = ctx.AURA_DEBUFF_TYPE_BORDER_VALUES or {}
    local AURA_DEBUFF_TYPE_BORDER_ALIASES = ctx.AURA_DEBUFF_TYPE_BORDER_ALIASES or {}
    local AURA_LANES = ctx.AURA_LANES or {}

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(AddGFAuraAliases) ~= "function" or type(AddGFAuraStrictAliases) ~= "function" or type(AddGFAuraRelativeSizeAliases) ~= "function" then return end
    if type(RegisterGFAuraBoolean) ~= "function" or type(RegisterGFAuraNumber) ~= "function" or type(RegisterGFAuraEnum) ~= "function" then return end
    if type(RegisterGroupAuraLaneGeometrySettings) ~= "function" then return end

    local GroupAuraRootSettings = {
        Registry = ctx.Registry,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        GFAurasRoot = ctx.GFAurasRoot,
        ApplyGroup = ctx.ApplyGroup,
    }

    if #AURA_DEBUFF_TYPE_BORDER_VALUES == 0 then
        AURA_DEBUFF_TYPE_BORDER_VALUES = { "OFF", "BORDER", "SYMBOL" }
    end
    if #AURA_COOLDOWN_SWIPE_DIRECTION_VALUES == 0 then
        AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
    end
    if type(AURA_SORT_METHOD_VALUES.buff) ~= "table" or #AURA_SORT_METHOD_VALUES.buff == 0 then
        AURA_SORT_METHOD_VALUES.buff = { "DEFAULT", "BIG_DEFENSIVE", "IMPORTANT_FIRST", "EXPIRATION", "EXPIRATION_ONLY", "NAME", "NAME_ONLY" }
    end
    if type(AURA_SORT_METHOD_VALUES.debuff) ~= "table" or #AURA_SORT_METHOD_VALUES.debuff == 0 then
        AURA_SORT_METHOD_VALUES.debuff = { "DEFAULT", "UNIT_FRAME_DEBUFF", "IMPORTANT_FIRST", "EXPIRATION", "EXPIRATION_ONLY", "NAME", "NAME_ONLY" }
    end
    if #AURA_SORT_DIRECTION_VALUES == 0 then
        AURA_SORT_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
    end
    if #AURA_DURATION_BAR_POSITION_VALUES == 0 then
        AURA_DURATION_BAR_POSITION_VALUES = { "BOTTOM", "TOP" }
    end
    if #AURA_DURATION_BAR_DISPLAY_VALUES == 0 then
        AURA_DURATION_BAR_DISPLAY_VALUES = { "BAR_ONLY", "OVERLAY" }
    end
    if #AURA_DURATION_BAR_DIRECTION_VALUES == 0 then
        AURA_DURATION_BAR_DIRECTION_VALUES = { "REMAINING", "ELAPSED" }
    end
    if #GF_AURA_ANCHORS == 0 then
        GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
    end
    local cooldownSwipeDirectionAllowed = {}
    for i = 1, #AURA_COOLDOWN_SWIPE_DIRECTION_VALUES do cooldownSwipeDirectionAllowed[AURA_COOLDOWN_SWIPE_DIRECTION_VALUES[i]] = true end

    local function ReadGFCooldownSwipeDirection(scope, lane)
        if type(GFReadAuraValue) ~= "function" then return "NORMAL" end
        return GFReadAuraValue(scope, lane, "cooldownSwipeReverse", false) == true and "REVERSE" or "NORMAL"
    end

    local function WriteGFCooldownSwipeDirection(scope, lane, value)
        if type(GFWriteAuraValue) ~= "function" then return end
        GFWriteAuraValue(scope, lane, "cooldownSwipeReverse", value == "REVERSE")
    end

    local function ReadGFSortDirection(scope, lane)
        if type(GFReadAuraValue) ~= "function" then return "NORMAL" end
        return GFReadAuraValue(scope, lane, "sortReverse", false) == true and "REVERSE" or "NORMAL"
    end

    local function WriteGFSortDirection(scope, lane, value)
        if type(GFWriteAuraValue) ~= "function" then return end
        GFWriteAuraValue(scope, lane, "sortReverse", value == "REVERSE")
    end

    local function GFSortExactAliases(scope, lane, direction)
        local out, seen = {}, {}
        local function add(value)
            if value ~= "" and not seen[value] then seen[value] = true; out[#out + 1] = value end
        end
        local scopeWords = { scope }
        if scope == "mythicraid" then scopeWords[#scopeWords + 1] = "mythic raid" end
        local singular = lane == "buff" and "buff" or "debuff"
        local plural = lane == "buff" and "buffs" or "debuffs"
        for i = 1, #scopeWords do
            local scopeWord = scopeWords[i]
            if direction then
                add("order of " .. scopeWord .. " " .. plural)
                add(scopeWord .. " " .. plural .. " order")
                add(scopeWord .. " " .. plural .. " sort order")
                add(scopeWord .. " " .. plural .. " sort direction")
                add(scopeWord .. " " .. singular .. " order")
            else
                add("sort " .. scopeWord .. " " .. plural)
                add(scopeWord .. " " .. plural .. " sort")
                add(scopeWord .. " " .. plural .. " sort method")
                add(scopeWord .. " " .. plural .. " sorting")
                add("sort " .. scopeWord .. " " .. singular)
            end
        end
        return out
    end

    local debuffBorderAllowed = {}
    for i = 1, #AURA_DEBUFF_TYPE_BORDER_VALUES do debuffBorderAllowed[AURA_DEBUFF_TYPE_BORDER_VALUES[i]] = true end

    local function NormalizeDebuffTypeBorderMode(value)
        value = tostring(value or "OFF")
        return debuffBorderAllowed[value] and value or "OFF"
    end

    local function ReadGFDebuffTypeBorderMode(scope, lane)
        if type(GFReadAuraValue) ~= "function" then return "OFF" end
        local value = GFReadAuraValue(scope, lane, "dispelBorderMode", nil)
        if value ~= nil then
            local mode = NormalizeDebuffTypeBorderMode(value)
            return (mode == "OFF" and GFReadAuraValue(scope, lane, "showDispelBorder", false) == true) and "SYMBOL" or mode
        end
        return GFReadAuraValue(scope, lane, "showDispelBorder", false) == true and "SYMBOL" or "OFF"
    end

    local function WriteGFDebuffTypeBorderMode(scope, lane, value)
        if type(GFWriteAuraValue) ~= "function" then return end
        value = NormalizeDebuffTypeBorderMode(value)
        GFWriteAuraValue(scope, lane, "dispelBorderMode", value)
        GFWriteAuraValue(scope, lane, "showDispelBorder", value ~= "OFF")
    end

    for _, scope in ipairs(GF_AURA_GROUPS) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            local maxDefault = 6
            local sizeDefault = lane == "buff" and 22 or 20
            local perRowDefault = lane == "buff" and 4 or 3
            local layerDefault = lane == "buff" and 5 or 6
            local aliases = {}
            AddAliasesForUnit(aliases, scope, laneInfo.plural:lower())
            AddGFAuraAliases(aliases, scope, lane, "lane")
            AddGFAuraAliases(aliases, scope, lane, "visibility")
            RegisterGFAuraBoolean(scope, lane, "Visible", "enabled", laneInfo.plural, true, aliases, {
                page = "gf_auras",
                description = "Shows or hides the entire " .. tostring(UNIT_LABELS[scope]) .. " " .. laneInfo.label:lower()
                    .. " icon lane. This is lane visibility, not content filtering: it does not change the native Filter choice or Hide Permanent rule.",
            })

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "max")
            AddGFAuraAliases(aliases, scope, lane, "max icons")
            AddGFAuraAliases(aliases, scope, lane, "maximum")
            AddGFAuraAliases(aliases, scope, lane, "maximum icons")
            AddGFAuraAliases(aliases, scope, lane, "count")
            AddGFAuraAliases(aliases, scope, lane, "cap")
            AddGFAuraAliases(aliases, scope, lane, "limit")
            local exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "max", "maximum", "max icons", "maximum icons", "icon count", "count", "cap", "limit" })
            RegisterGFAuraNumber(scope, lane, "Max", "max", laneInfo.label .. " Max Icons", maxDefault, 0, 20, aliases, "visual")

            aliases = {}
            exactAliases = {}
            AddGFAuraStrictAliases(exactAliases, scope, lane, "size")
            AddGFAuraStrictAliases(exactAliases, scope, lane, "icon size")
            AddGFAuraRelativeSizeAliases(exactAliases, scope, lane)
            for i = 1, #exactAliases do aliases[#aliases + 1] = exactAliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "size", "icon size" })
            Assistant._AssistantAddGFAuraAllLaneRelativeSizeAliases(aliases, scope)
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "size", "icon size" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "size", "icon size" })
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all group")
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all")
            RegisterGFAuraNumber(scope, lane, "Size", "size", laneInfo.label .. " Icon Size", sizeDefault, 8, 64, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "per row")
            AddGFAuraAliases(aliases, scope, lane, "icons per row")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "per row", "icons per row", "wrap count", "row count" })
            RegisterGFAuraNumber(scope, lane, "PerRow", "perRow", laneInfo.label .. " Icons Per Row", perRowDefault, 1, 20, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "spacing")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "spacing", "gap", "icon gap" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "spacing", "gap", "icon gap" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "spacing", "gap", "icon gap" })
            RegisterGFAuraNumber(scope, lane, "Spacing", "spacing", laneInfo.label .. " Spacing", 1, 0, 12, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "layer")
            AddGFAuraAliases(aliases, scope, lane, "z layer")
            AddGFAuraAliases(aliases, scope, lane, "z level")
            AddGFAuraAliases(aliases, scope, lane, "z order")
            AddGFAuraAliases(aliases, scope, lane, "z index")
            AddGFAuraAliases(aliases, scope, lane, "draw layer")
            AddGFAuraAliases(aliases, scope, lane, "frame level")
            AddGFAuraAliases(aliases, scope, lane, "strata")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "layer", "z layer", "z level", "z order", "z index", "draw layer", "frame level", "strata" })
            RegisterGFAuraNumber(scope, lane, "Layer", "layer", laneInfo.label .. " Layer", layerDefault, 0, 30, aliases, "geometry")

            RegisterGroupAuraLaneGeometrySettings(ctx, scope, lane, laneInfo)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "filter")
            AddGFAuraAliases(aliases, scope, lane, "filter type")
            AddGFAuraAliases(aliases, scope, lane, "inclusive filter")
            AddGFAuraAliases(aliases, scope, lane, "native filter")
            AddGFAuraAliases(aliases, scope, lane, "content filter")
            RegisterGFAuraEnum(scope, lane, "FilterToken", "filterToken", laneInfo.label .. " Filter", GF_AURA_FILTER_VALUES[lane], GF_AURA_FILTER_ALIASES, "ALL", aliases, "visual", {
                page = "gf_auras",
                description = "Chooses which auras pass the content filter for " .. tostring(UNIT_LABELS[scope])
                    .. " " .. laneInfo.plural .. ". It does not show or hide the lane; Group Auras and the " .. laneInfo.label
                    .. " lane must be enabled separately. Big Defensive uses MSUF's curated exact Spell-ID list; Hide Permanent is an independent no-duration rule.",
            })

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown text")
            RegisterGFAuraBoolean(scope, lane, "CooldownText", "showCooldown", laneInfo.label .. " Cooldown Text", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown swipe")
            RegisterGFAuraBoolean(scope, lane, "CooldownSwipe", "showCooldownSwipe", laneInfo.label .. " Cooldown Swipe", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "tooltip")
            AddGFAuraAliases(aliases, scope, lane, "tooltips")
            AddGFAuraAliases(aliases, scope, lane, "aura tooltip")
            AddGFAuraAliases(aliases, scope, lane, "aura tooltips")
            RegisterGFAuraBoolean(scope, lane, "Tooltip", "showTooltip", laneInfo.label .. " Tooltips", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "swipe direction")
            AddGFAuraAliases(aliases, scope, lane, "cooldown swipe direction")
            AddGFAuraAliases(aliases, scope, lane, "timer swipe direction")
            AddGFAuraAliases(aliases, scope, lane, "reverse cooldown swipe")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "swipe direction", "cooldown swipe direction", "timer swipe direction", "reverse cooldown swipe" })
            Registry:RegisterSetting({
                key = "gf_" .. scope .. ".auras." .. lane .. ".cooldownSwipeReverse",
                label = UNIT_LABELS[scope] .. " " .. laneInfo.label .. " Cooldown Swipe Direction",
                category = UNIT_LABELS[scope] .. " / Group Auras",
                unit = scope,
                frameType = "groupAura",
                attribute = "gfAura" .. lane .. "CooldownSwipeReverse",
                type = "enum",
                aliases = aliases,
                exactAliases = aliases,
                values = AURA_COOLDOWN_SWIPE_DIRECTION_VALUES,
                valueAliases = AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES,
                get = function() return ReadGFCooldownSwipeDirection(scope, lane) end,
                set = function(value) WriteGFCooldownSwipeDirection(scope, lane, cooldownSwipeDirectionAllowed[value] and value or "NORMAL") end,
                apply = function() ApplyGroup(scope, "auras") end,
                combatSafe = false,
            })

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "sort")
            AddGFAuraAliases(aliases, scope, lane, "sort method")
            AddGFAuraAliases(aliases, scope, lane, "sorting")
            RegisterGFAuraEnum(scope, lane, "SortMethod", "sortMethod", laneInfo.label .. " Sort Method",
                AURA_SORT_METHOD_VALUES[lane], AURA_SORT_METHOD_ALIASES[lane] or {}, "DEFAULT", aliases, "visual", {
                    page = lane == "buff" and "auras3_buffs" or "auras3_debuffs",
                    exactAliases = GFSortExactAliases(scope, lane, false),
                    description = "Chooses the native Blizzard AuraContainer comparator for this group Aura lane; it does not enable or disable the lane.",
                })

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "sort order")
            AddGFAuraAliases(aliases, scope, lane, "order")
            AddGFAuraAliases(aliases, scope, lane, "sort direction")
            Registry:RegisterSetting({
                key = "gf_" .. scope .. ".auras." .. lane .. ".sortReverse",
                label = UNIT_LABELS[scope] .. " " .. laneInfo.label .. " Sort Order",
                category = UNIT_LABELS[scope] .. " / Group Auras",
                page = lane == "buff" and "auras3_buffs" or "auras3_debuffs",
                description = "Uses the native normal or reversed AuraContainer order without changing lane visibility.",
                unit = scope,
                frameType = "groupAura",
                attribute = "gfAura" .. lane .. "SortReverse",
                type = "enum",
                aliases = aliases,
                exactAliases = GFSortExactAliases(scope, lane, true),
                values = AURA_SORT_DIRECTION_VALUES,
                valueAliases = AURA_SORT_DIRECTION_ALIASES,
                get = function() return ReadGFSortDirection(scope, lane) end,
                set = function(value) WriteGFSortDirection(scope, lane, value == "REVERSE" and "REVERSE" or "NORMAL") end,
                apply = function() ApplyGroup(scope, "auras") end,
                combatSafe = false,
            })

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "stack count")
            AddGFAuraAliases(aliases, scope, lane, "stacks")
            RegisterGFAuraBoolean(scope, lane, "StackCount", "showStacks", laneInfo.label .. " Stack Count", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "duration bar")
            AddGFAuraAliases(aliases, scope, lane, "show duration bar")
            AddGFAuraAliases(aliases, scope, lane, "timer bar")
            AddGFAuraAliases(aliases, scope, lane, "show timer bar")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "duration bar", "show duration bar", "timer bar", "show timer bar" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "duration bar", "show duration bar", "timer bar", "show timer bar" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "duration bar", "show duration bar", "timer bar", "show timer bar" })
            RegisterGFAuraBoolean(scope, lane, "DurationBar", "showDurationBar", laneInfo.label .. " Duration Bar", false, aliases)

            if lane == "debuff" then
                aliases = {}
                AddGFAuraAliases(aliases, scope, lane, "dispel type border")
                AddGFAuraAliases(aliases, scope, lane, "debuff type border")
                AddGFAuraAliases(aliases, scope, lane, "dispel border")
                RegisterGFAuraBoolean(scope, lane, "DispelTypeBorder", "showDispelBorder", laneInfo.label .. " Dispel-type Border", false, aliases)

                aliases = {}
                AddGFAuraAliases(aliases, scope, lane, "dispel type border mode")
                AddGFAuraAliases(aliases, scope, lane, "debuff type border mode")
                AddGFAuraAliases(aliases, scope, lane, "dispel border mode")
                AddGFAuraAliases(aliases, scope, lane, "debuff border mode")
                AddGFAuraAliases(aliases, scope, lane, "dispel type border")
                AddGFAuraAliases(aliases, scope, lane, "debuff type border")
                AddGFAuraAliases(aliases, scope, lane, "dispel border")
                Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "dispel type border mode", "debuff type border mode", "dispel border mode", "debuff border mode" })
                Registry:RegisterSetting({
                    key = "gf_" .. scope .. ".auras." .. lane .. ".dispelBorderMode",
                    label = UNIT_LABELS[scope] .. " " .. laneInfo.label .. " Dispel-type Border Mode",
                    category = UNIT_LABELS[scope] .. " / Group Auras",
                    unit = scope,
                    frameType = "groupAura",
                    attribute = "gfAura" .. lane .. "DispelBorderMode",
                    type = "enum",
                    aliases = aliases,
                    exactAliases = aliases,
                    values = AURA_DEBUFF_TYPE_BORDER_VALUES,
                    valueAliases = AURA_DEBUFF_TYPE_BORDER_ALIASES,
                    get = function() return ReadGFDebuffTypeBorderMode(scope, lane) end,
                    set = function(value) WriteGFDebuffTypeBorderMode(scope, lane, value) end,
                    apply = function() ApplyGroup(scope, "auras") end,
                    combatSafe = false,
                })
            end

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown font")
            AddGFAuraAliases(aliases, scope, lane, "cooldown size")
            AddGFAuraAliases(aliases, scope, lane, "cooldown text size")
            AddGFAuraAliases(aliases, scope, lane, "timer text size")
            AddGFAuraAliases(aliases, scope, lane, "cooldown text font size")
            AddGFAuraAliases(aliases, scope, lane, "timer text font size")
            RegisterGFAuraNumber(scope, lane, "CooldownSize", "cooldownSize", laneInfo.label .. " Cooldown Font Size", 8, 6, 24, aliases, "font")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown decimals")
            AddGFAuraAliases(aliases, scope, lane, "cooldown decimal")
            AddGFAuraAliases(aliases, scope, lane, "timer decimals")
            AddGFAuraAliases(aliases, scope, lane, "decimal threshold")
            AddGFAuraAliases(aliases, scope, lane, "decimals below sec")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "cooldown decimals", "cooldown decimal", "timer decimals", "decimal threshold", "decimals below sec" })
            RegisterGFAuraNumber(scope, lane, "CooldownDecimalSeconds", "cooldownDecimalSeconds", laneInfo.label .. " Cooldown Decimal Threshold", 3, 0, 30, aliases, "visual")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "stack font")
            AddGFAuraAliases(aliases, scope, lane, "stack size")
            RegisterGFAuraNumber(scope, lane, "StackSize", "stackSize", laneInfo.label .. " Stack Font Size", 10, 6, 24, aliases, "font")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "duration bar height")
            AddGFAuraAliases(aliases, scope, lane, "timer bar height")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "duration bar height", "timer bar height" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "duration bar height", "timer bar height" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "duration bar height", "timer bar height" })
            RegisterGFAuraNumber(scope, lane, "DurationBarHeight", "durationBarHeight", laneInfo.label .. " Duration Bar Height", 2, 1, 16, aliases, "visual")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "duration bar position")
            AddGFAuraAliases(aliases, scope, lane, "timer bar position")
            AddGFAuraAliases(aliases, scope, lane, "duration bar edge")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "duration bar position", "timer bar position", "duration bar edge" })
            RegisterGFAuraEnum(scope, lane, "DurationBarPosition", "durationBarPosition", laneInfo.label .. " Duration Bar Position", AURA_DURATION_BAR_POSITION_VALUES, AURA_DURATION_BAR_POSITION_ALIASES, "BOTTOM", aliases, "visual")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "duration bar display")
            AddGFAuraAliases(aliases, scope, lane, "timer bar display")
            AddGFAuraAliases(aliases, scope, lane, "duration bar mode")
            AddGFAuraAliases(aliases, scope, lane, "timer bar mode")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "duration bar display", "timer bar display", "duration bar mode", "timer bar mode" })
            RegisterGFAuraEnum(scope, lane, "DurationBarDisplay", "durationBarDisplay", laneInfo.label .. " Duration Bar Display", AURA_DURATION_BAR_DISPLAY_VALUES, AURA_DURATION_BAR_DISPLAY_ALIASES, "BAR_ONLY", aliases, "visual")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "duration bar fill mode")
            AddGFAuraAliases(aliases, scope, lane, "duration bar direction")
            AddGFAuraAliases(aliases, scope, lane, "timer bar fill mode")
            AddGFAuraAliases(aliases, scope, lane, "timer bar direction")
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "duration bar fill mode", "duration bar direction", "timer bar fill mode", "timer bar direction" })
            RegisterGFAuraEnum(scope, lane, "DurationBarDirection", "durationBarDirection", laneInfo.label .. " Duration Bar Fill Mode", AURA_DURATION_BAR_DIRECTION_VALUES, AURA_DURATION_BAR_DIRECTION_ALIASES, "REMAINING", aliases, "visual")
        end

        if type(RegisterGroupAuraRootSettings) == "function" then
            RegisterGroupAuraRootSettings(GroupAuraRootSettings, scope)
        end


        if scope ~= "mythicraid"
            and Registry and type(Registry.RegisterSetting) == "function"
            and type(GFReadConfValue) == "function" and type(GFWriteConfValue) == "function"
            and type(ApplyGroup) == "function"
        then
            local settingScope = scope
            local aliases = {}
            AddAliasesForUnit(aliases, settingScope, "aura cooldown darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown swipe darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "darken cooldown swipe on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown swipe dunkelt")
            AddAliasesForUnit(aliases, settingScope, "cooldown dunkelt bei verlust")
            Registry:RegisterSetting({
                key = "gf_" .. settingScope .. ".cooldownSwipeDarkenOnLoss",
                label = UNIT_LABELS[settingScope] .. " Aura Cooldown Swipe Darkens on Loss",
                category = UNIT_LABELS[settingScope] .. " / Group Auras",
                unit = settingScope,
                frameType = "groupAura",
                attribute = "gfAuraCooldownSwipeDarkenOnLoss",
                type = "boolean",
                aliases = aliases,
                exactAliases = aliases,
                get = function()
                    return GFReadConfValue(settingScope, "cooldownSwipeDarkenOnLoss", false) and true or false
                end,
                set = function(value)
                    value = value and true or false
                    GFWriteConfValue(settingScope, "cooldownSwipeDarkenOnLoss", value)
                    if settingScope == "raid" then GFWriteConfValue("mythicraid", "cooldownSwipeDarkenOnLoss", value) end
                end,
                apply = function()
                    ApplyGroup(settingScope, "auras")
                    if settingScope == "raid" then ApplyGroup("mythicraid", "auras") end
                end,
                combatSafe = false,
            })
        end
    end
end
