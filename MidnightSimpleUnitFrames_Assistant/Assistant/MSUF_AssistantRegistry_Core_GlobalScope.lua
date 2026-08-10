-- Assistant RegistryCore scoped-global helpers.
-- Extends RegistryCore after the base DB/apply helpers are available.
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
local ClampNumber = C.ClampNumber
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeDBKeys = C.GlobalScopeDBKeys
local ScopedSharedTable = C.ScopedSharedTable

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(ClampNumber) ~= "function" then return end
if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeLabel) ~= "function" then return end
if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return end
if type(GlobalScopeDBKeys) ~= "function" then return end
if type(ScopedSharedTable) ~= "function" then return end

local function ScopedDBOwnership(scope, dbKeys, sharedKind)
    local keys
    if scope == "shared" then
        if sharedKind == "bars" then
            keys = { "bars" }
        elseif sharedKind ~= "db" then
            keys = { "general" }
        end
    else
        keys = GlobalScopeDBKeys(scope)
    end
    if type(keys) ~= "table" then return nil end
    if type(dbKeys) ~= "table" then dbKeys = { dbKeys } end
    local out = {}
    for i = 1, #keys do
        for j = 1, #dbKeys do
            if type(dbKeys[j]) == "string" and dbKeys[j] ~= "" then
                out[#out + 1] = { scope = keys[i], dbKey = dbKeys[j] }
            end
        end
    end
    return #out > 0 and out or nil
end

local function ScopedIntentScopes(scope)
    if scope == "gf_party" then return { "party", "gf_party" } end
    if scope == "gf_raid" then return { "raid", "mythicraid", "gf_raid", "gf_mythicraid" } end
    if scope == "shared" then return { "shared", "global" } end
    return { scope }
end

local function RegisterScopedSetting(kind, scope, dbKey, attr, label, settingType, defaultValue, aliases, opts)
    opts = opts or {}
    scope = NormalizeGlobalScope(scope)
    local values = opts.values or {}
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    local dbScopes = opts.dbScopes or ScopedDBOwnership(scope, opts.dbScopeKeys or dbKey, opts.shared)
    Registry:RegisterSetting({
        key = (opts.keyPrefix or kind) .. "." .. scope .. "." .. dbKey,
        label = GlobalScopeLabel(scope) .. " " .. label,
        category = opts.category or (kind == "fontScope" and "Global / Fonts / Scoped" or "Global / Bars / Scoped"),
        unit = scope,
        frameType = opts.frameType or (kind == "fontScope" and "fonts" or "globalBars"),
        attribute = attr,
        dbScopes = dbScopes,
        dbScopesReplace = type(dbScopes) == "table" and #dbScopes > 0,
        intentScopes = opts.intentScopes or ScopedIntentScopes(scope),
        type = settingType,
        mediaType = opts.mediaType,
        aliases = aliases,
        values = opts.values,
        valueAliases = opts.valueAliases,
        min = opts.min,
        max = opts.max,
        step = opts.step or 1,
        percent = opts.percent == true,
        normalizesValue = opts.normalizeValue ~= nil,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = GlobalScopeRead(scope, opts.flag, ScopedSharedTable(opts.shared), dbKey, defaultValue)
            if settingType == "boolean" then
                if value == nil then return defaultValue and true or false end
                return value and true or false
            elseif settingType == "number" then
                return tonumber(value) or defaultValue
            elseif settingType == "enum" then
                if allowed[value] then return value end
                return defaultValue
            elseif settingType == "string" then
                if type(value) ~= "string" or value == "" then return defaultValue or "" end
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                return value
            end
            return value
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            if settingType == "boolean" then
                value = value and true or false
            elseif settingType == "number" then
                value = ClampNumber(value, opts.min, opts.max, opts.step or 1)
            elseif settingType == "enum" then
                if not allowed[value] then value = defaultValue end
            elseif settingType == "string" then
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                value = tostring(value or "")
            end
            GlobalScopeWrite(scope, opts.flag, ScopedSharedTable(opts.shared), dbKey, value)
        end,
        apply = function()
            if opts.apply then opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), scope) end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        menuControlDisposition = opts.menuControlDisposition,
        menuControlDispositionReason = opts.menuControlDispositionReason,
        menuControlDispositionEvidence = opts.menuControlDispositionEvidence,
        description = opts.description,
        captureTransactionState = opts.captureTransactionState,
        restoreTransactionState = opts.restoreTransactionState,
    })
end

local function RegisterScopedMappedEnum(kind, scope, dbKey, attr, label, defaultValue, values, storageByValue, aliases, opts)
    opts = opts or {}
    local valueByStorage = {}
    for i = 1, #(values or {}) do
        local value = values[i]
        valueByStorage[storageByValue[value]] = value
    end
    local rawGet, rawSet = opts.get, opts.set
    opts.values = values
    opts.get = function(scopeKey)
        local stored = rawGet and rawGet(scopeKey) or GlobalScopeRead(scopeKey, opts.flag, ScopedSharedTable(opts.shared), dbKey, storageByValue[defaultValue])
        return valueByStorage[stored] or defaultValue
    end
    opts.set = function(scopeKey, value)
        local stored = storageByValue[value] or storageByValue[defaultValue]
        if rawSet then rawSet(scopeKey, stored) else GlobalScopeWrite(scopeKey, opts.flag, ScopedSharedTable(opts.shared), dbKey, stored) end
    end
    RegisterScopedSetting(kind, scope, dbKey, attr, label, "enum", defaultValue, aliases, opts)
end

C.RegisterScopedSetting = RegisterScopedSetting
C.RegisterScopedMappedEnum = RegisterScopedMappedEnum
