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
    local GroupDBRead = type(ctx.GroupDBRead) == "function" and ctx.GroupDBRead or function(scope)
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return nil end
        local key = (scope == "raid" or scope == "gf_raid") and "gf_raid"
            or (scope == "mythicraid" or scope == "gf_mythicraid") and "gf_mythicraid"
            or (scope == "priority" or scope == "gf_priority") and "gf_priority"
            or "gf_party"
        local conf = db[key]
        if type(conf) == "table" then return conf end
        return nil
    end

    -- Reading a setting must never write. The read path returns the saved
    -- tables as they are, or this shared empty view when a level does not
    -- exist yet; a write through the view is a bug and fails loudly instead of
    -- silently landing in a detached table. Only the write path (used by
    -- setters) materialises <scope>.auras and pins the native renderer:
    -- before this split a question about a group aura setting flipped
    -- <scope>.auras.renderer back to NATIVE_12_1 after the Auras3 group
    -- filter model had forced CUSTOM ("renderer churn").
    local EMPTY_READ_VIEW = setmetatable({}, {
        __newindex = function(_, key)
            error("MSUF Assistant: group aura read view is read-only (" .. tostring(key) .. ")", 2)
        end,
    })

    local function GFAurasRoot(scope)
        local conf = GroupDBRead(scope)
        local auras = conf and conf.auras
        if type(auras) == "table" then return auras end
        return EMPTY_READ_VIEW
    end

    local function GFAurasRootForWrite(scope)
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
        local group = root[lane]
        if type(group) == "table" then return group end
        return EMPTY_READ_VIEW
    end

    local function GFAuraGroupForWrite(scope, lane)
        local root = GFAurasRootForWrite(scope)
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
        local root = GFAurasRootForWrite(scope)
        root.enabled = true
        root.blizzardTypes[lane == "buff" and "buffs" or "debuffs"] = false
        GFAuraGroupForWrite(scope, lane).enabled = shown
    end

    local function GFReadAuraNumber(scope, lane, key, defaultValue)
        return tonumber(GFAuraGroup(scope, lane)[key]) or defaultValue or 0
    end

    local function GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, step)
        GFAuraGroupForWrite(scope, lane)[key] = ClampNumber(value, minValue, maxValue, step or 1)
    end

    local function GFReadAuraValue(scope, lane, key, defaultValue)
        local value = GFAuraGroup(scope, lane)[key]
        if value == nil then return defaultValue end
        return value
    end

    local function GFWriteAuraValue(scope, lane, key, value)
        GFAuraGroupForWrite(scope, lane)[key] = value
    end

    local function GFReadConfValue(scope, key, defaultValue)
        local conf = GroupDBRead(scope)
        local value = conf and conf[key]
        if value == nil then return defaultValue end
        return value
    end

    local function GFWriteConfValue(scope, key, value)
        GroupDB(scope)[key] = value
    end

    return {
        GFAurasRoot = GFAurasRoot,
        GFAurasRootForWrite = GFAurasRootForWrite,
        GFAuraGroup = GFAuraGroup,
        GFAuraGroupForWrite = GFAuraGroupForWrite,
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
