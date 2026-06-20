-- Assistant RegistryCore scoped-global access helpers.
-- Loaded before MSUF_AssistantRegistry_Core_GlobalScope.lua; registration helpers consume these exports.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB
local GLOBAL_SCOPE_META = C.GLOBAL_SCOPE_META or {}

if type(EnsureDB) ~= "function" or type(GeneralDB) ~= "function" or type(BarsDB) ~= "function" then return end

local function NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.NormalizeScopeKey) == "function" then
        scope = GP.NormalizeScopeKey(scope)
    else
        scope = tostring(scope or "shared"):lower()
        scope = scope:gsub("%s+", "")
        scope = scope:gsub("%-", "_")
        if scope == "party" or scope == "group" or scope == "groupframes" or scope == "gfparty" then scope = "gf_party" end
        if scope == "raid" or scope == "mythic" or scope == "mythicraid" or scope == "gfraid" or scope == "gf_mythicraid" then scope = "gf_raid" end
        if scope == "targetoftarget" or scope == "tot" then scope = "targettarget" end
        if scope == "focustargettarget" or scope == "focus_target" then scope = "focustarget" end
        if scope == "" or scope == "global" or scope == "all" then scope = "shared" end
    end
    if scope == "gf_mythicraid" then scope = "gf_raid" end
    if GLOBAL_SCOPE_META[scope] then return scope end
    return "shared"
end

local function GlobalScopeLabel(scope)
    scope = NormalizeGlobalScope(scope)
    local meta = GLOBAL_SCOPE_META[scope]
    return meta and meta.label or tostring(scope)
end

local function GlobalScopeDBKeys(scope)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeDBKeys) == "function" then
        local keys = GP.ScopeDBKeys(scope)
        if type(keys) == "table" then return keys end
    end
    if scope == "gf_party" then return { "gf_party" } end
    if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
    if scope ~= "shared" and GLOBAL_SCOPE_META[scope] then return { scope } end
    return nil
end

local function GlobalScopeIsGroup(scope)
    scope = NormalizeGlobalScope(scope)
    return scope == "gf_party" or scope == "gf_raid"
end

local function GlobalScopeHasOverride(scope, flag)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeHasOverride) == "function" then return GP.ScopeHasOverride(scope, flag) and true or false end
    local keys = GlobalScopeDBKeys(scope)
    if not keys then return false end
    local db = EnsureDB()
    for i = 1, #keys do
        local entry = db[keys[i]]
        if type(entry) == "table" and entry[flag] == true then return true end
    end
    return false
end

local function GlobalScopeSetOverride(scope, flag, enabled)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeSetOverride) == "function" then
        GP.ScopeSetOverride(scope, flag, enabled and true or false)
        return
    end
    local keys = GlobalScopeDBKeys(scope)
    if not keys then return end
    local db = EnsureDB()
    for i = 1, #keys do
        local key = keys[i]
        db[key] = type(db[key]) == "table" and db[key] or {}
        db[key][flag] = enabled and true or false
    end
end

local function GlobalScopeRead(scope, flag, sharedTable, key, defaultValue)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeRead) == "function" then return GP.ScopeRead(scope, flag, sharedTable, key, defaultValue) end
    if scope ~= "shared" and GlobalScopeHasOverride(scope, flag) then
        local keys = GlobalScopeDBKeys(scope)
        local db = EnsureDB()
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if type(entry) == "table" and entry[key] ~= nil then return entry[key] end
        end
    end
    local value = sharedTable and sharedTable[key]
    if value == nil then return defaultValue end
    return value
end

local function GlobalScopeWrite(scope, flag, sharedTable, key, value)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeWrite) == "function" then
        GP.ScopeWrite(scope, flag, sharedTable, key, value)
        return
    end
    if scope == "shared" then
        sharedTable[key] = value
        return
    end
    GlobalScopeSetOverride(scope, flag, true)
    local keys = GlobalScopeDBKeys(scope)
    local db = EnsureDB()
    for i = 1, #(keys or {}) do
        local keyName = keys[i]
        db[keyName] = type(db[keyName]) == "table" and db[keyName] or {}
        db[keyName][key] = value
    end
end

local function GlobalScopeAliases(scope, aliases, suffix)
    scope = NormalizeGlobalScope(scope)
    local out = {}
    local scopeAliases = GLOBAL_SCOPE_META[scope] and GLOBAL_SCOPE_META[scope].aliases or { scope }
    for i = 1, #scopeAliases do
        local scopeName = scopeAliases[i]
        for j = 1, #(aliases or {}) do
            local alias = aliases[j]
            out[#out + 1] = scopeName .. " " .. alias
            out[#out + 1] = alias .. " " .. scopeName
            if suffix then out[#out + 1] = scopeName .. " " .. alias .. " " .. suffix end
        end
    end
    return out
end

local function ScopedSharedTable(kind)
    if kind == "bars" then return BarsDB() end
    if kind == "db" then return EnsureDB() end
    return GeneralDB()
end

C.NormalizeGlobalScope = NormalizeGlobalScope
C.GlobalScopeLabel = GlobalScopeLabel
C.GlobalScopeDBKeys = GlobalScopeDBKeys
C.GlobalScopeIsGroup = GlobalScopeIsGroup
C.GlobalScopeHasOverride = GlobalScopeHasOverride
C.GlobalScopeSetOverride = GlobalScopeSetOverride
C.GlobalScopeRead = GlobalScopeRead
C.GlobalScopeWrite = GlobalScopeWrite
C.GlobalScopeAliases = GlobalScopeAliases
C.ScopedSharedTable = ScopedSharedTable
