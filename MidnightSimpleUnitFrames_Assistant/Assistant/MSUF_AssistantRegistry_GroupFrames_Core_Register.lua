-- Assistant GroupFrames generic setting registration helpers.
-- Loaded before MSUF_AssistantRegistry_GroupFrames_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildRegisterCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local ApplyGroup = ctx.ApplyGroup

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GroupDB) ~= "function" or type(ClampNumber) ~= "function" or type(ApplyGroup) ~= "function" then return nil end

    local function RegisterGroupBoolean(scope, attr, dbKey, label, defaultValue, mode, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. (opts.keySuffix or dbKey),
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            page = opts.page,
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            matchLabel = opts.matchLabel,
            booleanAliases = opts.booleanAliases,
            valueAliases = opts.valueAliases,
            intentGuard = opts.intentGuard,
            get = function()
                if opts.get then return opts.get(scope) end
                local value = GroupDB(scope)[dbKey]
                if value == nil then return defaultValue and true or false end
                return value and true or false
            end,
            set = function(value)
                if opts.set then opts.set(scope, value); return end
                local db = GroupDB(scope)
                local oldValue = db[dbKey]
                if oldValue == nil then oldValue = defaultValue and true or false end
                local newValue = value and true or false
                if oldValue == newValue then return end
                db[dbKey] = newValue
                if dbKey == "enabled" and type(_G.MSUF_ShowGroupFrameReloadRequiredPopup) == "function" then
                    _G.MSUF_ShowGroupFrameReloadRequiredPopup()
                end
            end,
            apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
            description = opts.description,
            combatSafe = false,
        })
    end

    local function RegisterGroupNumber(scope, attr, dbKey, label, defaultValue, minValue, maxValue, step, mode, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. dbKey,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            page = opts.page,
            attribute = attr,
            type = "number",
            aliases = aliases,
            min = minValue,
            max = maxValue,
            step = step or 1,
            percent = opts.percent == true,
            get = function()
                if opts.get then return opts.get(scope) end
                local value = tonumber(GroupDB(scope)[dbKey])
                if value == nil then return defaultValue end
                return value
            end,
            set = function(value)
                local db = GroupDB(scope)
                if dbKey == "offsetX" or dbKey == "offsetY" then
                    local gf = MSUF and MSUF.GF
                    if gf and type(gf.EnsureStableGridPosition) == "function" then
                        local count = type(gf.GetLiveLayoutCount) == "function" and gf.GetLiveLayoutCount(scope) or nil
                        gf.EnsureStableGridPosition(scope, count, db)
                    end
                end
                if opts.set then
                    opts.set(scope, value)
                else
                    db[dbKey] = ClampNumber(value, minValue, maxValue, step or 1)
                end
                if dbKey == "offsetX" or dbKey == "offsetY" then
                    db.positionMode = "GRID_BOUNDS_V2"
                end
            end,
            apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
            combatSafe = false,
            description = opts.description,
        })
    end

    local function RegisterGroupEnum(scope, attr, dbKey, label, defaultValue, values, valueAliases, mode, aliases, opts)
        opts = opts or {}
        local allowed = {}
        for i = 1, #(values or {}) do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. dbKey,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            page = opts.page,
            attribute = attr,
            type = "enum",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            values = values,
            valueAliases = valueAliases,
            get = function()
                if opts.get then return opts.get(scope) end
                local value = GroupDB(scope)[dbKey]
                if allowed[value] then return value end
                return defaultValue
            end,
            set = function(value)
                if opts.set then opts.set(scope, value); return end
                if not allowed[value] then value = defaultValue end
                GroupDB(scope)[dbKey] = value
            end,
            apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
            combatSafe = false,
            description = opts.description,
        })
    end

    local function RegisterGroupString(scope, attr, dbKey, label, defaultValue, mode, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. dbKey,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            page = opts.page,
            attribute = attr,
            type = "string",
            aliases = aliases,
            valuePrefixes = opts.valuePrefixes or aliases,
            mediaType = opts.mediaType,
            values = opts.values,
            valueAliases = opts.valueAliases,
            valueLabels = opts.valueLabels,
            closedValues = opts.closedValues,
            refreshValues = opts.refreshValues,
            normalizesValue = opts.normalizeValue ~= nil,
            get = function()
                if opts.get then return opts.get(scope) end
                local value = GroupDB(scope)[dbKey]
                if type(value) ~= "string" or value == "" then return defaultValue or "" end
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                return value
            end,
            set = function(value)
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                if opts.set then opts.set(scope, value); return end
                GroupDB(scope)[dbKey] = tostring(value or "")
            end,
            apply = function() ApplyGroup(scope, opts.mode or mode or "visual") end,
            combatSafe = false,
            description = opts.description,
        })
    end

    return {
        RegisterGroupBoolean = RegisterGroupBoolean,
        RegisterGroupNumber = RegisterGroupNumber,
        RegisterGroupEnum = RegisterGroupEnum,
        RegisterGroupString = RegisterGroupString,
    }
end
