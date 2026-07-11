-- Assistant registry core group aura helpers.
-- Loaded before MSUF_AssistantRegistry_Core.lua; the core passes DB and clamp helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildGroupAuraHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    if type(GroupDB) ~= "function" or type(ClampNumber) ~= "function" then return nil end

    local function GFAurasRoot(scope)
        local conf = GroupDB(scope)
        conf.auras = type(conf.auras) == "table" and conf.auras or {}
        if conf.auras.renderer ~= "NATIVE_12_1" then conf.auras.renderer = "NATIVE_12_1" end
        conf.auras.blizzardTypes = type(conf.auras.blizzardTypes) == "table" and conf.auras.blizzardTypes or {}
        conf.auras.buff = type(conf.auras.buff) == "table" and conf.auras.buff or {}
        conf.auras.debuff = type(conf.auras.debuff) == "table" and conf.auras.debuff or {}
        return conf.auras
    end

    local function GFAuraGroup(scope, lane)
        local root = GFAurasRoot(scope)
        lane = lane == "debuff" and "debuff" or "buff"
        root[lane] = type(root[lane]) == "table" and root[lane] or {}
        return root[lane]
    end

    local function GFAuraLaneShown(scope, lane)
        lane = lane == "debuff" and "debuff" or "buff"
        local root = GFAurasRoot(scope)
        local group = GFAuraGroup(scope, lane)
        return root.enabled ~= false and group.enabled ~= false
    end

    local function SetGFAuraLaneShown(scope, lane, shown)
        lane = lane == "debuff" and "debuff" or "buff"
        shown = shown and true or false
        local root = GFAurasRoot(scope)
        root.enabled = true
        root.blizzardTypes[lane == "buff" and "buffs" or "debuffs"] = false
        GFAuraGroup(scope, lane).enabled = shown
    end

    local function GFReadAuraNumber(scope, lane, key, defaultValue)
        return tonumber(GFAuraGroup(scope, lane)[key]) or defaultValue or 0
    end

    local function GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, step)
        GFAuraGroup(scope, lane)[key] = ClampNumber(value, minValue, maxValue, step or 1)
    end

    local function GFReadAuraValue(scope, lane, key, defaultValue)
        local value = GFAuraGroup(scope, lane)[key]
        if value == nil then return defaultValue end
        return value
    end

    local function GFWriteAuraValue(scope, lane, key, value)
        GFAuraGroup(scope, lane)[key] = value
    end

    local function GFReadConfValue(scope, key, defaultValue)
        local conf = GroupDB(scope)
        local value = conf[key]
        if value == nil then return defaultValue end
        return value
    end

    local function GFWriteConfValue(scope, key, value)
        GroupDB(scope)[key] = value
    end

    return {
        GFAurasRoot = GFAurasRoot,
        GFAuraGroup = GFAuraGroup,
        GFAuraLaneShown = GFAuraLaneShown,
        SetGFAuraLaneShown = SetGFAuraLaneShown,
        GFReadAuraNumber = GFReadAuraNumber,
        GFWriteAuraNumber = GFWriteAuraNumber,
        GFReadAuraValue = GFReadAuraValue,
        GFWriteAuraValue = GFWriteAuraValue,
        GFReadConfValue = GFReadConfValue,
        GFWriteConfValue = GFWriteConfValue,
    }
end
