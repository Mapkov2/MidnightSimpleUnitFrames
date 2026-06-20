-- Assistant RegistryCore setting registration helpers.
-- Defines cold-path helpers that build Registry setting specs for domain modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local Registry = C.Registry
local GeneralDB = C.GeneralDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyGeneral = C.ApplyGeneral

if type(Registry) ~= "table" or type(GeneralDB) ~= "function" then return end

local function ApplyRegistrySetting(opts, dbKey, fallback, defaultApplyOpts)
    local reason = opts.reason or ("MSUF_ASSISTANT_" .. dbKey)
    if opts.apply then
        opts.apply(reason)
    elseif defaultApplyOpts then
        fallback(reason, opts.applyOpts or defaultApplyOpts)
    else
        fallback(reason)
    end
end

local function RegisterGeneralBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        get = function()
            local value = GeneralDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            GeneralDB()[dbKey] = value and true or false
            if dbKey == "showMinimapIcon" then
                local g = GeneralDB()
                g.minimapIconDB = type(g.minimapIconDB) == "table" and g.minimapIconDB or {}
                g.minimapIconDB.hide = not (value and true or false)
            end
        end,
        apply = function()
            ApplyRegistrySetting(opts, dbKey, ApplyGeneral, { preview = false, applyAll = false })
            if dbKey == "showMinimapIcon" then
                local fn = _G.MSUF_SetMinimapIconEnabled
                if type(fn) == "function" then fn(GeneralDB().showMinimapIcon ~= false) end
            elseif dbKey == "playTargetSelectLostSounds" then
                CallGlobal("MSUF_TargetSoundDriver_ResetState")
                if GeneralDB().playTargetSelectLostSounds == true then CallGlobal("MSUF_TargetSoundDriver_Ensure") end
            elseif dbKey == "hideAdvancedMenu" and M and type(M.RefreshAdvancedNavVisibility) == "function" then
                M.RefreshAdvancedNavVisibility()
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterGeneralEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local g = GeneralDB()
            local value = g[dbKey]
            if allowed[value] then return value end
            if dbKey == "barMode" then
                if g.useClassColors == true then return "class" end
                if g.darkMode == true then return "dark" end
            end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            GeneralDB()[dbKey] = value
            if dbKey == "barMode" then
                local g = GeneralDB()
                g.darkMode = value == "dark"
                g.useClassColors = value == "class"
            end
        end,
        apply = function() ApplyRegistrySetting(opts, dbKey, ApplyGeneral, { preview = true, applyAll = false }) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local BuildGeneralValueSettingHelpers = C.BuildGeneralValueSettingHelpers
local ValueSettings = type(BuildGeneralValueSettingHelpers) == "function" and BuildGeneralValueSettingHelpers({
    Registry = Registry,
    GeneralDB = GeneralDB,
    ClampNumber = ClampNumber,
    ApplyGeneral = ApplyGeneral,
    ApplyRegistrySetting = ApplyRegistrySetting,
}) or nil
if type(ValueSettings) ~= "table" then return end

local RegisterGeneralNumberSetting = ValueSettings.RegisterGeneralNumberSetting
local RegisterGeneralString = ValueSettings.RegisterGeneralString
local RegisterGeneralMappedEnum = ValueSettings.RegisterGeneralMappedEnum
if type(RegisterGeneralNumberSetting) ~= "function" then return end
if type(RegisterGeneralString) ~= "function" then return end
if type(RegisterGeneralMappedEnum) ~= "function" then return end

C.RegisterGeneralBoolean = RegisterGeneralBoolean
C.RegisterGeneralNumberSetting = RegisterGeneralNumberSetting
C.RegisterGeneralEnum = RegisterGeneralEnum
C.RegisterGeneralString = RegisterGeneralString
C.RegisterGeneralMappedEnum = RegisterGeneralMappedEnum
