-- Assistant group aura lane settings.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterGroupAuraLaneSettings(ctx)
    if type(ctx) ~= "table" then return end

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

    local PRIVATE_AURA_ANCHOR_ALIASES = {
        center = "CENTER",
        middle = "CENTER",
        top = "TOPRIGHT",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        top_right = "TOPRIGHT",
        right = "TOPRIGHT",
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top_left = "TOPLEFT",
        left = "TOPLEFT",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
        bottom_right = "BOTTOMRIGHT",
        bottom = "BOTTOMRIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom_left = "BOTTOMLEFT",
    }
    local PRIVATE_AURA_GROWTH_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" }
    local PRIVATE_AURA_GROWTH_ALIASES = {
        right = "RIGHT",
        rechts = "RIGHT",
        left = "LEFT",
        links = "LEFT",
        up = "UP",
        above = "UP",
        hoch = "UP",
        down = "DOWN",
        below = "DOWN",
        runter = "DOWN",
    }

    local function ClampGroupAuraNumber(value, defaultValue, minValue, maxValue, step)
        value = tonumber(value)
        if value == nil then value = defaultValue end
        step = tonumber(step) or 1
        if step > 0 then value = math.floor((value / step) + 0.5) * step end
        if minValue ~= nil and value < minValue then value = minValue end
        if maxValue ~= nil and value > maxValue then value = maxValue end
        return value
    end

    local function RegisterGFAuraConfBoolean(scope, attr, key, label, defaultValue, aliases, description)
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = aliases,
            get = function()
                local value = GFReadConfValue(scope, key, defaultValue)
                return value and true or false
            end,
            set = function(value) GFWriteConfValue(scope, key, value and true or false) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function RegisterGFAuraConfNumber(scope, attr, key, label, defaultValue, minValue, maxValue, step, aliases, description)
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "number",
            aliases = aliases,
            exactAliases = aliases,
            min = minValue,
            max = maxValue,
            step = step or 1,
            get = function()
                return tonumber(GFReadConfValue(scope, key, defaultValue)) or defaultValue
            end,
            set = function(value)
                GFWriteConfValue(scope, key, ClampGroupAuraNumber(value, defaultValue, minValue, maxValue, step or 1))
            end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function RegisterGFAuraConfEnum(scope, attr, key, label, values, valueAliases, defaultValue, aliases, description)
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "enum",
            aliases = aliases,
            exactAliases = aliases,
            values = values,
            valueAliases = valueAliases,
            get = function()
                local value = GFReadConfValue(scope, key, defaultValue)
                return allowed[value] and value or defaultValue
            end,
            set = function(value) GFWriteConfValue(scope, key, allowed[value] and value or defaultValue) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function PrivateAuraConfig(scope)
        local value = GFReadConfValue(scope, "privateAuras", nil)
        if type(value) ~= "table" then
            value = {}
            GFWriteConfValue(scope, "privateAuras", value)
        end
        return value
    end

    local function ReadPrivateAuraValue(scope, field, flatKey, defaultValue)
        local private = GFReadConfValue(scope, "privateAuras", nil)
        if type(private) == "table" and private[field] ~= nil then return private[field] end
        if flatKey then return GFReadConfValue(scope, flatKey, defaultValue) end
        return defaultValue
    end

    local function WritePrivateAuraValue(scope, field, value, flatKey)
        PrivateAuraConfig(scope)[field] = value
        if flatKey then GFWriteConfValue(scope, flatKey, value) end
    end

    local function RegisterPrivateAuraBoolean(scope, attr, field, flatKey, label, defaultValue, aliases, description)
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. (flatKey or ("privateAuras." .. field)),
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = aliases,
            get = function()
                local value = ReadPrivateAuraValue(scope, field, flatKey, defaultValue)
                return value and true or false
            end,
            set = function(value) WritePrivateAuraValue(scope, field, value and true or false, flatKey) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function RegisterPrivateAuraNumber(scope, attr, field, flatKey, label, defaultValue, minValue, maxValue, step, aliases, description)
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. (flatKey or ("privateAuras." .. field)),
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "number",
            aliases = aliases,
            exactAliases = aliases,
            min = minValue,
            max = maxValue,
            step = step or 1,
            get = function()
                return tonumber(ReadPrivateAuraValue(scope, field, flatKey, defaultValue)) or defaultValue
            end,
            set = function(value)
                WritePrivateAuraValue(scope, field, ClampGroupAuraNumber(value, defaultValue, minValue, maxValue, step or 1), flatKey)
            end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function RegisterPrivateAuraEnum(scope, attr, field, flatKey, label, values, valueAliases, defaultValue, aliases, description)
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. (flatKey or ("privateAuras." .. field)),
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. attr,
            type = "enum",
            aliases = aliases,
            exactAliases = aliases,
            values = values,
            valueAliases = valueAliases,
            get = function()
                local value = ReadPrivateAuraValue(scope, field, flatKey, defaultValue)
                return allowed[value] and value or defaultValue
            end,
            set = function(value) WritePrivateAuraValue(scope, field, allowed[value] and value or defaultValue, flatKey) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
            description = description,
        })
    end

    local function RegisterGroupPrivateAuraSettings(scope)
        local aliases = {}
        AddAliasesForUnit(aliases, scope, "private auras")
        AddAliasesForUnit(aliases, scope, "private aura icons")
        AddAliasesForUnit(aliases, scope, "private aura indicators")
        RegisterPrivateAuraBoolean(scope, "PrivateAuras", "enabled", "privateAurasEnabled", "Private Auras", true, aliases,
            "Shows Blizzard private-aura indicators on group frames.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura max")
        AddAliasesForUnit(aliases, scope, "private aura count")
        AddAliasesForUnit(aliases, scope, "private aura limit")
        AddAliasesForUnit(aliases, scope, "private aura icons max")
        RegisterPrivateAuraNumber(scope, "PrivateAuraMax", "max", "privateAuraMax", "Private Aura Max Icons", 4, 0, 8, 1, aliases,
            "Maximum private-aura indicators shown on each group frame.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura size")
        AddAliasesForUnit(aliases, scope, "private aura icon size")
        AddAliasesForUnit(aliases, scope, "private aura icons size")
        RegisterPrivateAuraNumber(scope, "PrivateAuraSize", "size", "privateAuraSize", "Private Aura Icon Size", 20, 8, 64, 1, aliases,
            "Private-aura indicator icon size on group frames.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura anchor")
        AddAliasesForUnit(aliases, scope, "private aura position")
        AddAliasesForUnit(aliases, scope, "private aura corner")
        RegisterPrivateAuraEnum(scope, "PrivateAuraAnchor", "anchor", "privateAuraAnchor", "Private Aura Anchor", GF_AURA_ANCHORS, PRIVATE_AURA_ANCHOR_ALIASES, "TOPRIGHT", aliases,
            "Private-aura indicator anchor on group frames.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura x")
        AddAliasesForUnit(aliases, scope, "private aura x offset")
        AddAliasesForUnit(aliases, scope, "private aura horizontal offset")
        RegisterPrivateAuraNumber(scope, "PrivateAuraX", "x", "privateAuraX", "Private Aura X Offset", 0, -160, 160, 1, aliases,
            "Private-aura indicator horizontal offset on group frames.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura y")
        AddAliasesForUnit(aliases, scope, "private aura y offset")
        AddAliasesForUnit(aliases, scope, "private aura vertical offset")
        RegisterPrivateAuraNumber(scope, "PrivateAuraY", "y", "privateAuraY", "Private Aura Y Offset", 0, -160, 160, 1, aliases,
            "Private-aura indicator vertical offset on group frames.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura countdown")
        AddAliasesForUnit(aliases, scope, "private aura timer")
        AddAliasesForUnit(aliases, scope, "private aura cooldown text")
        RegisterPrivateAuraBoolean(scope, "PrivateAuraCountdown", "showCountdown", "privateAuraCountdown", "Private Aura Countdown", true, aliases,
            "Shows countdown text on group-frame private-aura indicators.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura spacing")
        AddAliasesForUnit(aliases, scope, "private aura gap")
        AddAliasesForUnit(aliases, scope, "private aura icon spacing")
        RegisterPrivateAuraNumber(scope, "PrivateAuraSpacing", "spacing", nil, "Private Aura Spacing", 1, 0, 24, 1, aliases,
            "Spacing between group-frame private-aura indicators.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura growth")
        AddAliasesForUnit(aliases, scope, "private aura grow")
        AddAliasesForUnit(aliases, scope, "private auras grow")
        AddAliasesForUnit(aliases, scope, "private aura grow direction")
        AddAliasesForUnit(aliases, scope, "private aura direction")
        RegisterPrivateAuraEnum(scope, "PrivateAuraGrowth", "growth", nil, "Private Aura Growth", PRIVATE_AURA_GROWTH_VALUES, PRIVATE_AURA_GROWTH_ALIASES, "RIGHT", aliases,
            "Direction private-aura indicators grow from their anchor.")

        aliases = {}
        AddAliasesForUnit(aliases, scope, "private aura numbers")
        AddAliasesForUnit(aliases, scope, "private aura number text")
        AddAliasesForUnit(aliases, scope, "private aura stacks")
        AddAliasesForUnit(aliases, scope, "private aura stack text")
        RegisterPrivateAuraBoolean(scope, "PrivateAuraNumbers", "showNumbers", nil, "Private Aura Numbers", false, aliases,
            "Shows private-aura numeric text when the runtime provides a count.")
    end

    local function ReadGFCooldownSwipeDirection(scope, lane)
        if type(GFReadAuraValue) ~= "function" then return "NORMAL" end
        return GFReadAuraValue(scope, lane, "cooldownSwipeReverse", false) == true and "REVERSE" or "NORMAL"
    end

    local function WriteGFCooldownSwipeDirection(scope, lane, value)
        if type(GFWriteAuraValue) ~= "function" then return end
        GFWriteAuraValue(scope, lane, "cooldownSwipeReverse", value == "REVERSE")
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
            AddGFAuraAliases(aliases, scope, lane, "visibility")
            RegisterGFAuraBoolean(scope, lane, "Visible", "enabled", laneInfo.plural, true, aliases)

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
            RegisterGFAuraEnum(scope, lane, "FilterToken", "filterToken", laneInfo.label .. " Filter", GF_AURA_FILTER_VALUES[lane], GF_AURA_FILTER_ALIASES, "ALL", aliases, "visual")

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

        RegisterGroupPrivateAuraSettings(scope)

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
