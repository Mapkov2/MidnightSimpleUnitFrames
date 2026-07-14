-- Assistant Castbars shared registry helpers and backend fallback logic.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main registry wires the returned context into split modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

local CASTBAR_KEYS = A.CastbarsRegistry.CASTBAR_KEYS
local CASTBAR_DETAIL_FIELDS = A.CastbarsRegistry.CASTBAR_DETAIL_FIELDS

function A.CastbarsRegistry.BuildCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end
    if type(CASTBAR_KEYS) ~= "table" or type(CASTBAR_DETAIL_FIELDS) ~= "table" then return nil end

    local Registry = ctx.Registry
    local RegistryCore = ctx.RegistryCore
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GeneralDB = ctx.GeneralDB
    local ClampNumber = ctx.ClampNumber
    local CallGlobal = ctx.CallGlobal
    local ApplyCastbar = ctx.ApplyCastbar
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(ClampNumber) ~= "function" or type(ApplyCastbar) ~= "function" then return nil end
    if type(RegisterGeneralEnum) ~= "function" then return nil end
    if type(CallGlobal) ~= "function" then
        CallGlobal = function(name, ...)
            local fn = _G[name]
            if type(fn) == "function" then return fn(...) end
            return nil
        end
    end

    local BuildBackendContext = A.CastbarsRegistry and A.CastbarsRegistry.BuildBackendContext
    local Backend = type(BuildBackendContext) == "function" and BuildBackendContext({
        GeneralDB = GeneralDB,
        CASTBAR_KEYS = CASTBAR_KEYS,
    }) or nil
    if type(Backend) ~= "table" then return nil end
    local GetCastbarBackend = Backend.GetCastbarBackend
    local SetCastbarBackend = Backend.SetCastbarBackend
    local NormalizeCastbarBackend = Backend.NormalizeCastbarBackend
    local SetCastbarProvider = Backend.SetCastbarProvider
    if type(GetCastbarBackend) ~= "function" or type(SetCastbarBackend) ~= "function" then return nil end
    if type(NormalizeCastbarBackend) ~= "function" or type(SetCastbarProvider) ~= "function" then return nil end

    local function RegisterUnitCastbarBoolean(unit)
        local aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar", "castbar")
        AddAliasesForUnit(aliases, unit, "cast bar", "zauberleiste")
        Registry:RegisterSetting({
            key = "general." .. CASTBAR_KEYS[unit].enable,
            label = UNIT_LABELS[unit] .. " Cast Bar",
            category = UNIT_LABELS[unit] .. " / Cast Bar",
            unit = unit,
            frameType = "castbar",
            attribute = "enabled",
            type = "boolean",
            aliases = aliases,
            get = function() return GetCastbarBackend(unit, GeneralDB()) ~= "HIDE" end,
            set = function(value) SetCastbarBackend(unit, value and true or false) end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_ENABLE", unit) end,
            combatSafe = false,
        })
    end

    local function RegisterGeneralNumber(key, unit, frameType, attr, label, defaultValue, minValue, maxValue, aliases)
        Registry:RegisterSetting({
            key = "general." .. key,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = frameType,
            attribute = attr,
            type = "number",
            aliases = aliases,
            min = minValue,
            max = maxValue,
            step = 1,
            get = function()
                local value = tonumber(GeneralDB()[key])
                if value == nil then return defaultValue end
                return value
            end,
            set = function(value)
                GeneralDB()[key] = ClampNumber(value, minValue, maxValue, 1)
            end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_GEOMETRY", unit) end,
            combatSafe = false,
        })
    end

    local function RegisterGeneralEnumSetting(key, unit, frameType, attr, label, defaultValue, values, aliases, valueAliases)
        RegisterGeneralEnum(key, attr, UNIT_LABELS[unit] .. " " .. label, defaultValue, values, aliases, {
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = frameType,
            valueAliases = valueAliases,
            reason = "MSUF_ASSISTANT_CASTBAR_DETAIL",
            apply = function(reason) ApplyCastbar(reason or "MSUF_ASSISTANT_CASTBAR_DETAIL", unit) end,
        })
    end

    local function RegisterCastbarUnitGeneralBoolean(unit, dbKey, attr, label, defaultValue, aliases)
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = "castbar",
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            get = function()
                local value = GeneralDB()[dbKey]
                if value == nil then return defaultValue and true or false end
                return value and true or false
            end,
            set = function(value)
                GeneralDB()[dbKey] = value and true or false
            end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_DETAIL", unit) end,
            combatSafe = false,
        })
    end

    local function RegisterBossCastbarDetachSetting()
        local ownedKeys = { "bossCastbarDetached", "bossCastbarOffsetX", "bossCastbarOffsetY" }
        local function CaptureOwnerState()
            local general = GeneralDB()
            local state = { fields = {} }
            for i = 1, #ownedKeys do
                local key = ownedKeys[i]
                local value = rawget(general, key)
                state.fields[key] = { present = value ~= nil, value = value }
            end
            return state
        end
        local function RestoreOwnerState(state, reason)
            if type(state) ~= "table" or type(state.fields) ~= "table" then
                error("invalid boss castbar attachment transaction state")
            end
            local general = GeneralDB()
            for i = 1, #ownedKeys do
                local key = ownedKeys[i]
                local saved = state.fields[key]
                if type(saved) == "table" and saved.present == true then
                    general[key] = saved.value
                else
                    general[key] = nil
                end
            end
            ApplyCastbar(reason or "MSUF_ASSISTANT_BOSS_CASTBAR_ATTACHMENT_RESTORE", "boss")
            return true
        end
        Registry:RegisterSetting({
            key = "general.bossCastbarDetached",
            label = "Boss Cast Bar Detached",
            category = "Boss / Cast Bar / Position",
            unit = "boss",
            frameType = "castbar",
            attribute = "detached",
            type = "boolean",
            aliases = {
                "boss castbar detached", "boss cast bar detached", "detach boss castbar", "detach boss cast bar",
                "boss castbar attached", "boss cast bar attached", "attach boss castbar", "attach boss cast bar",
                "boss castbar anchor", "boss cast bar anchor", "boss castbar attachment", "boss cast bar attachment",
            },
            exactAliases = {
                "detach boss castbar", "detach boss cast bar", "detach the boss castbar", "detach the boss cast bar",
                "attach boss castbar", "attach boss cast bar", "attach the boss castbar", "attach the boss cast bar",
                "anchor boss castbar to boss frame", "anchor boss cast bar to boss frame",
                "dock boss castbar to boss frame", "dock boss cast bar to boss frame",
            },
            valueAliases = {
                detach = true, detached = true, undock = true, separate = true,
                attach = false, attached = false, anchor = false, anchored = false, dock = false, docked = false,
            },
            dbScopes = {
                { scope = "general", dbKey = "bossCastbarDetached" },
                { scope = "general", dbKey = "bossCastbarOffsetX" },
                { scope = "general", dbKey = "bossCastbarOffsetY" },
            },
            dbScopesReplace = true,
            get = function() return GeneralDB().bossCastbarDetached == true end,
            set = function(value)
                local setAnchored = _G.MSUF_EM_SetCastbarAnchoredToUnit
                if type(setAnchored) ~= "function" then
                    error("MSUF castbar attachment controller is unavailable")
                end
                setAnchored("boss", value ~= true)
            end,
            -- The Edit Mode owner applies and refreshes synchronously. Keep the
            -- transaction Apply phase idempotent instead of applying twice.
            apply = function() return true end,
            captureTransactionState = CaptureOwnerState,
            restoreTransactionState = RestoreOwnerState,
            combatSafe = false,
            description = "Detaches the Boss cast bar from the Boss frame or attaches it again while preserving Edit Mode placement semantics.",
        })
    end

    local BuildPlayerCastbarProviderRegistrar = A.CastbarsRegistry and A.CastbarsRegistry.BuildPlayerCastbarProviderRegistrar
    local RegisterPlayerCastbarProvider = type(BuildPlayerCastbarProviderRegistrar) == "function" and BuildPlayerCastbarProviderRegistrar({
        Registry = Registry,
        AddAliasesForUnit = AddAliasesForUnit,
        GeneralDB = GeneralDB,
        CallGlobal = CallGlobal,
        ApplyCastbar = ApplyCastbar,
        CASTBAR_KEYS = CASTBAR_KEYS,
        GetCastbarBackend = GetCastbarBackend,
        NormalizeCastbarBackend = NormalizeCastbarBackend,
        SetCastbarProvider = SetCastbarProvider,
    }) or nil
    if type(RegisterPlayerCastbarProvider) ~= "function" then return nil end

    if type(RegistryCore) == "table" then
        RegistryCore.CASTBAR_KEYS = CASTBAR_KEYS
        RegistryCore.GetCastbarBackend = GetCastbarBackend
    end

    return {
        CASTBAR_KEYS = CASTBAR_KEYS,
        CASTBAR_DETAIL_FIELDS = CASTBAR_DETAIL_FIELDS,
        GetCastbarBackend = GetCastbarBackend,
        RegisterUnitCastbarBoolean = RegisterUnitCastbarBoolean,
        RegisterGeneralNumber = RegisterGeneralNumber,
        RegisterGeneralEnumSetting = RegisterGeneralEnumSetting,
        RegisterCastbarUnitGeneralBoolean = RegisterCastbarUnitGeneralBoolean,
        RegisterBossCastbarDetachSetting = RegisterBossCastbarDetachSetting,
        RegisterPlayerCastbarProvider = RegisterPlayerCastbarProvider,
    }
end
