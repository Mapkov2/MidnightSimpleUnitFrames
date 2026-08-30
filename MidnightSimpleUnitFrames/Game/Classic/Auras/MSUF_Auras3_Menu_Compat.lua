--- Classic-only bridge for legacy/portable Hide Permanent ownership.
---
--- The shared Menu Model must remain byte-identical to Retail. Classic's scan
--- backend additionally consumes legacy values stored in the effective filter
--- lane, so this post-load adapter makes the menu read that same compiled value
--- without creating an empty blacklist override merely by opening the page.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local Client = MSUF.Client
if not (Client and Client.IsClassic == true) then return end

local type, tostring, pairs = type, tostring, pairs
local A3 = MSUF.MSUF_Auras3
local Model = type(A3) == "table" and A3.MenuModel or nil
if type(Model) ~= "table" or A3.__classicAuraMenuCompatLoaded == true then return end
if type(A3._ClassicReadBlacklistHidePermanent) ~= "function"
    or type(Model.WriteBlacklistHidePermanent) ~= "function" then
    return
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return out
end

local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local BOSS_LOOKUP = {
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local ARENA_UNITS = { "arena1", "arena2", "arena3" }
local ARENA_LOOKUP = { arena1 = true, arena2 = true, arena3 = true }

local function AuraDB()
    local auras, shared
    if type(A3.EnsureDB) == "function" then auras, shared = A3.EnsureDB() end
    if type(auras) ~= "table" then
        local db = _G.MSUF_DB
        auras = type(db) == "table" and db.auras3 or nil
    end
    if type(auras) ~= "table" then return nil, nil end
    if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    shared = type(shared) == "table" and shared
        or (type(auras.shared) == "table" and auras.shared or nil)
    return auras, shared
end

local function EachRuntimeUnit(scope, callback)
    scope = tostring(scope or "player")
    if scope == "shared" then return end
    if scope == "boss" or BOSS_LOOKUP[scope] then
        for i = 1, #BOSS_UNITS do callback(BOSS_UNITS[i]) end
    elseif scope == "arena" or ARENA_LOOKUP[scope] then
        for i = 1, #ARENA_UNITS do callback(ARENA_UNITS[i]) end
    elseif scope == "target" or scope == "focus" then
        callback(scope)
    else
        callback("player")
    end
end

local function PrepareBlacklistOverride(scope)
    local auras, shared = AuraDB()
    if type(auras) ~= "table" then return end
    local sharedBlacklist = type(shared) == "table" and shared.blacklist or nil
    EachRuntimeUnit(scope, function(runtimeUnit)
        local pu = type(auras.perUnit[runtimeUnit]) == "table"
            and auras.perUnit[runtimeUnit] or {}
        auras.perUnit[runtimeUnit] = pu
        if pu.overrideBlacklist ~= true or type(pu.blacklist) ~= "table" then
            pu.blacklist = DeepCopy(type(sharedBlacklist) == "table"
                and sharedBlacklist or { spells = {} })
        end
        pu.overrideBlacklist = true
        if type(pu.blacklist.spells) ~= "table" then pu.blacklist.spells = {} end
    end)
end

local WriteBlacklistHidePermanent = Model.WriteBlacklistHidePermanent

function Model.ReadBlacklistHidePermanent(scope, kind)
    return A3._ClassicReadBlacklistHidePermanent(scope, kind) == true
end

function Model.WriteBlacklistHidePermanent(scope, kind, value)
    PrepareBlacklistOverride(scope)
    return WriteBlacklistHidePermanent(scope, kind, value)
end

A3.__classicAuraMenuCompatLoaded = true
