-- Assistant Auras shared layout/sort setting registry.
-- Loaded before MSUF_AssistantRegistry_Auras_Shared.lua; the shared registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterSharedLayoutSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_GROWTH_VALUES = ctx.AURA_GROWTH_VALUES or {}
    local AURA_GROWTH_ALIASES = ctx.AURA_GROWTH_ALIASES or {}
    local AURA_ROW_WRAP_VALUES = ctx.AURA_ROW_WRAP_VALUES or {}
    local AURA_ROW_WRAP_ALIASES = ctx.AURA_ROW_WRAP_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AuraModel = ctx.AuraModel
    local AuraSharedString = ctx.AuraSharedString
    local SetAuraSharedString = ctx.SetAuraSharedString
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" then return end
    if type(AuraSharedString) ~= "function" or type(SetAuraSharedString) ~= "function" then return end
    if type(ApplyAura) ~= "function" then return end

    local function RegisterAuraSharedEnum(attr, label, values, valueAliases, defaultValue, aliases, applyReason, exactAliases, read, write)
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "auras3.shared." .. attr,
            label = "Shared " .. label,
            category = "Shared / Auras",
            unit = "shared",
            frameType = "aura",
            attribute = "aura" .. attr:gsub("^%l", string.upper),
            type = "enum",
            aliases = aliases,
            exactAliases = exactAliases,
            values = values,
            valueAliases = valueAliases,
            get = read or function() return AuraSharedString(attr, defaultValue, allowed) end,
            set = function(value)
                value = allowed[value] and value or defaultValue
                if type(write) == "function" then
                    write(value)
                else
                    SetAuraSharedString(attr, value, defaultValue, allowed)
                end
            end,
            apply = function() ApplyAura("shared", applyReason or "MSUF_ASSISTANT_AURA_LAYOUT") end,
            combatSafe = false,
        })
    end

    local function ReadLaneGrowth(lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneGrowth) == "function" then
            return Model.ReadLaneGrowth("shared", lane)
        end
        local key = lane == "debuff" and "debuffGrowthX" or "buffGrowthX"
        return AuraSharedString(key, "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
    end

    local function WriteLaneGrowth(lane, value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneGrowth) == "function" then
            Model.WriteLaneGrowth("shared", lane, value)
            return
        end
        local key = lane == "debuff" and "debuffGrowthX" or "buffGrowthX"
        SetAuraSharedString(key, value, "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
    end

    local function ReadLaneRowWrap(lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneRowWrap) == "function" then
            return Model.ReadLaneRowWrap("shared", lane)
        end
        local key = lane == "debuff" and "debuffGrowthY" or "buffGrowthY"
        return AuraSharedString(key, "DOWN", { UP = true, DOWN = true })
    end

    local function WriteLaneRowWrap(lane, value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneRowWrap) == "function" then
            Model.WriteLaneRowWrap("shared", lane, value)
            return
        end
        local key = lane == "debuff" and "debuffGrowthY" or "buffGrowthY"
        SetAuraSharedString(key, value, "DOWN", { UP = true, DOWN = true })
    end

    local function AuraSharedAliases(...)
        local aliases = {}
        for i = 1, select("#", ...) do
            local alias = select(i, ...)
            aliases[#aliases + 1] = alias
            AddAliasesForAuraScope(aliases, "shared", alias)
        end
        return aliases
    end

    RegisterAuraSharedEnum("buffGrowth", "Buff Growth", AURA_GROWTH_VALUES, AURA_GROWTH_ALIASES, "RIGHT",
        AuraSharedAliases("buff growth", "buff grow direction", "buff direction", "buff aura growth"),
        "MSUF_ASSISTANT_AURA_CAPS",
        { "buff growth", "buff grow direction", "buff direction", "buff aura growth" },
        function() return ReadLaneGrowth("buff") end,
        function(value) WriteLaneGrowth("buff", value) end)
    RegisterAuraSharedEnum("debuffGrowth", "Debuff Growth", AURA_GROWTH_VALUES, AURA_GROWTH_ALIASES, "RIGHT",
        AuraSharedAliases("debuff growth", "debuff grow direction", "debuff direction", "debuff aura growth"),
        "MSUF_ASSISTANT_AURA_CAPS",
        { "debuff growth", "debuff grow direction", "debuff direction", "debuff aura growth" },
        function() return ReadLaneGrowth("debuff") end,
        function(value) WriteLaneGrowth("debuff", value) end)
    RegisterAuraSharedEnum("buffRowWrap", "Buff Wrap Rows", AURA_ROW_WRAP_VALUES, AURA_ROW_WRAP_ALIASES, "DOWN",
        AuraSharedAliases("buff wrap rows", "buff row wrap", "buff second row", "buff row direction"),
        "MSUF_ASSISTANT_AURA_CAPS",
        { "buff wrap rows", "buff row wrap", "buff second row", "buff row direction" },
        function() return ReadLaneRowWrap("buff") end,
        function(value) WriteLaneRowWrap("buff", value) end)
    RegisterAuraSharedEnum("debuffRowWrap", "Debuff Wrap Rows", AURA_ROW_WRAP_VALUES, AURA_ROW_WRAP_ALIASES, "DOWN",
        AuraSharedAliases("debuff wrap rows", "debuff row wrap", "debuff second row", "debuff row direction"),
        "MSUF_ASSISTANT_AURA_CAPS",
        { "debuff wrap rows", "debuff row wrap", "debuff second row", "debuff row direction" },
        function() return ReadLaneRowWrap("debuff") end,
        function(value) WriteLaneRowWrap("debuff", value) end)

    local sortOrderExactAliases = { "sort order", "aura sort order", "aura sorting", "sort auras" }
    local sortOrderAliases = AuraSharedAliases("sort order", "aura sort order", "aura sorting", "sort auras")
    local sortMethodByOrder = {
        [0] = "INSTANCE_ID",
        [1] = "DEFAULT",
        [2] = "BIG_DEFENSIVE",
        [3] = "EXPIRATION",
        [4] = "EXPIRATION_ONLY",
        [5] = "NAME",
        [6] = "NAME_ONLY",
    }
    local sortOrderByMethod = {}
    local sortMethodAllowed = {}
    for order, method in pairs(sortMethodByOrder) do
        sortOrderByMethod[method] = order
        sortMethodAllowed[method] = true
    end
    Registry:RegisterSetting({
        key = "auras3.shared.sortOrder",
        label = "Shared Aura Sort Order",
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "auraSortOrder",
        type = "enum",
        aliases = sortOrderAliases,
        exactAliases = sortOrderExactAliases,
        values = { 0, 1, 2, 3, 4, 5, 6 },
        valueAliases = {
            unsorted = 0,
            native = 0,
            default_player_can_apply_id = 1,
            player_can_apply = 1,
            big_defensive = 2,
            defensive = 2,
            expiration_soonest = 3,
            soonest = 3,
            expiration = 3,
            expiration_only = 4,
            name = 5,
            alphabetical = 5,
            name_alphabetical = 5,
            name_only = 6,
        },
        get = function()
            local Model = type(AuraModel) == "function" and AuraModel() or nil
            local method
            if Model and type(Model.ReadLaneStyleString) == "function" then
                method = Model.ReadLaneStyleString("shared", "buff", "sortMethod", "INSTANCE_ID")
            else
                method = AuraSharedString("buffSortMethod", "INSTANCE_ID", sortMethodAllowed)
            end
            return sortOrderByMethod[method] or 0
        end,
        set = function(value)
            local method = sortMethodByOrder[tonumber(value)] or "INSTANCE_ID"
            local Model = type(AuraModel) == "function" and AuraModel() or nil
            if Model and type(Model.WriteLaneStyleString) == "function" then
                Model.WriteLaneStyleString("shared", "buff", "sortMethod", method)
                Model.WriteLaneStyleString("shared", "debuff", "sortMethod", method)
                return
            end
            SetAuraSharedString("buffSortMethod", method, "INSTANCE_ID", sortMethodAllowed)
            SetAuraSharedString("debuffSortMethod", method, "INSTANCE_ID", sortMethodAllowed)
        end,
        apply = function() ApplyAura("shared", "MSUF_ASSISTANT_AURA_SORT") end,
        combatSafe = false,
        description = "Compatibility control that applies the selected Auras3 sort method to both Buff and Debuff lanes.",
    })
end
