-- Assistant Group Aura lane helper core.
-- Builds cold alias and setting registration helpers used by the group aura lane registry.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupAuraLaneCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UNIT_ALIASES = ctx.UNIT_ALIASES or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GFAurasRoot = ctx.GFAurasRoot
    local GFAuraLaneShown = ctx.GFAuraLaneShown
    local SetGFAuraLaneShown = ctx.SetGFAuraLaneShown
    local GFReadAuraNumber = ctx.GFReadAuraNumber
    local GFWriteAuraNumber = ctx.GFWriteAuraNumber
    local GFReadAuraValue = ctx.GFReadAuraValue
    local GFWriteAuraValue = ctx.GFWriteAuraValue
    local ApplyGroup = ctx.ApplyGroup
    local AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS or {}
    local ARef = ctx.A or A
    local MAX_SETTING_ALIASES = tonumber(A.RegistryCore and A.RegistryCore.MAX_SETTING_ALIASES) or 32

    local function AppendAlias(out, value)
        if #out >= MAX_SETTING_ALIASES then return false end
        out[#out + 1] = value
        return #out < MAX_SETTING_ALIASES
    end

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" then return nil end
    if type(GFAuraLaneShown) ~= "function" or type(SetGFAuraLaneShown) ~= "function" then return nil end
    if type(GFReadAuraNumber) ~= "function" or type(GFWriteAuraNumber) ~= "function" then return nil end
    if type(GFReadAuraValue) ~= "function" or type(GFWriteAuraValue) ~= "function" then return nil end
    if type(ApplyGroup) ~= "function" then return nil end

    local function AddGFAuraAliases(out, scope, lane, noun)
        if #out >= MAX_SETTING_ALIASES then return false end
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        if not AddAliasesForUnit(out, scope, laneWord .. " " .. noun) then return false end
        if not AddAliasesForUnit(out, scope, lanePlural .. " " .. noun) then return false end
        if not AddAliasesForUnit(out, scope, "aura " .. laneWord .. " " .. noun) then return false end
        return AddAliasesForUnit(out, scope, "aura " .. lanePlural .. " " .. noun)
    end

    local function AddGFAuraStrictAliases(out, scope, lane, noun)
        if #out >= MAX_SETTING_ALIASES then return false end
        local laneWord = lane == "buff" and "buff" or "debuff"
        local lanePlural = lane == "buff" and "buffs" or "debuffs"
        local aliases = UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            if s ~= "group" and s ~= "group frames" and s ~= "gruppenframes" and s ~= "gruppe" then
                if not AppendAlias(out, s .. " " .. laneWord .. " " .. noun) then return false end
                if not AppendAlias(out, s .. " " .. lanePlural .. " " .. noun) then return false end
                if not AppendAlias(out, laneWord .. " " .. noun .. " " .. s) then return false end
                if not AppendAlias(out, lanePlural .. " " .. noun .. " " .. s) then return false end
                if not AppendAlias(out, s .. " aura " .. laneWord .. " " .. noun) then return false end
                if not AppendAlias(out, s .. " aura " .. lanePlural .. " " .. noun) then return false end
            end
        end
        return true
    end

    local function AddGFAuraRelativeSizeAliases(out, scope, lane)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            if not AddGFAuraStrictAliases(out, scope, lane, AURA_RELATIVE_SIZE_NOUNS[i]) then return false end
        end
        return true
    end

    ARef._AssistantAddGFAuraAllLaneAlias = ARef._AssistantAddGFAuraAllLaneAlias or function(out, scope, noun)
        if #out >= MAX_SETTING_ALIASES then return false end
        local aliases = UNIT_ALIASES[scope] or { scope }
        for i = 1, #aliases do
            local s = aliases[i]
            if s ~= "group" and s ~= "group frames" and s ~= "gruppenframes" and s ~= "gruppe" then
                if not AppendAlias(out, s .. " aura " .. noun) then return false end
                if not AppendAlias(out, s .. " auras " .. noun) then return false end
                if not AppendAlias(out, "aura " .. noun .. " " .. s) then return false end
                if not AppendAlias(out, "auras " .. noun .. " " .. s) then return false end
            end
        end
        return true
    end

    ARef._AssistantAddGFAuraAllLaneAliases = ARef._AssistantAddGFAuraAllLaneAliases or function(out, scope, nouns)
        for i = 1, #(nouns or {}) do
            if not ARef._AssistantAddGFAuraAllLaneAlias(out, scope, nouns[i]) then return false end
        end
        return true
    end

    ARef._AssistantAddGFAuraAllLaneRelativeSizeAliases = ARef._AssistantAddGFAuraAllLaneRelativeSizeAliases or function(out, scope)
        for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
            if not ARef._AssistantAddGFAuraAllLaneAlias(out, scope, AURA_RELATIVE_SIZE_NOUNS[i]) then return false end
        end
        return true
    end

    local function RegisterGFAuraBoolean(scope, lane, attr, key, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            page = opts.page,
            description = opts.description,
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. lane .. attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = opts.exactAliases or aliases,
            get = function()
                if key == "enabled" then return GFAuraLaneShown(scope, lane) end
                local value = GFReadAuraValue(scope, lane, key, nil)
                if value == nil and key == "showTooltip" and type(GFAurasRoot) == "function" then
                    local root = GFAurasRoot(scope)
                    value = root and root.showTooltip
                end
                if value == nil then value = defaultValue end
                return value and true or false
            end,
            set = function(value)
                if key == "enabled" then SetGFAuraLaneShown(scope, lane, value) else GFWriteAuraValue(scope, lane, key, value and true or false) end
            end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
        })
    end

    local function RegisterGFAuraNumber(scope, lane, attr, key, label, defaultValue, minValue, maxValue, aliases, mode, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            page = opts.page,
            description = opts.description,
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. lane .. attr,
            type = "number",
            aliases = aliases,
            exactAliases = opts.exactAliases or aliases,
            min = minValue,
            max = maxValue,
            step = 1,
            moveAxis = opts.moveAxis,
            moveStep = opts.moveStep,
            moveAmount = opts.moveAmount,
            get = function() return GFReadAuraNumber(scope, lane, key, defaultValue) end,
            set = function(value) GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, 1) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
        })
    end

    local function RegisterGFAuraEnum(scope, lane, attr, key, label, values, valueAliases, defaultValue, aliases, mode, opts)
        opts = opts or {}
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Auras",
            page = opts.page,
            description = opts.description,
            unit = scope,
            frameType = "groupAura",
            attribute = "gfAura" .. lane .. attr,
            type = "enum",
            aliases = aliases,
            exactAliases = opts.exactAliases or aliases,
            values = values,
            valueAliases = valueAliases,
            get = function()
                local value = GFReadAuraValue(scope, lane, key, defaultValue)
                return allowed[value] and value or defaultValue
            end,
            set = function(value) GFWriteAuraValue(scope, lane, key, allowed[value] and value or defaultValue) end,
            apply = function() ApplyGroup(scope, "auras") end,
            combatSafe = false,
        })
    end

    return {
        AddGFAuraAliases = AddGFAuraAliases,
        AddGFAuraStrictAliases = AddGFAuraStrictAliases,
        AddGFAuraRelativeSizeAliases = AddGFAuraRelativeSizeAliases,
        RegisterGFAuraBoolean = RegisterGFAuraBoolean,
        RegisterGFAuraNumber = RegisterGFAuraNumber,
        RegisterGFAuraEnum = RegisterGFAuraEnum,
    }
end
