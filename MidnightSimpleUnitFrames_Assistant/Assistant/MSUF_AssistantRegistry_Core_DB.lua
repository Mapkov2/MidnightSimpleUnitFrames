-- Assistant registry core DB and scalar helper builders.
-- Loaded before MSUF_AssistantRegistry_Core.lua; keeps shared cold-path accessors isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryCoreBuilders = A.RegistryCoreBuilders or {}

function A.RegistryCoreBuilders.BuildDBHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF
    local ExportPublic = (MSUFRef and MSUFRef.ExportPublic) or function(name, value) _G[name] = value; return value end
    local floor = math.floor

    local function EnsureDB()
        if MRef and type(MRef.EnsureDB) == "function" then return MRef.EnsureDB() end
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
        return _G.MSUF_DB
    end

    local function UnitDB(unit)
        local db = EnsureDB()
        if unit == "tot" or unit == "targetoftarget" or unit == "target_of_target" then
            unit = "targettarget"
        elseif unit == "focus_target" or unit == "focustargettarget" then
            unit = "focustarget"
        end
        if unit == "targettarget" and type(db.targettarget) ~= "table" then
            db.targettarget = type(db.tot) == "table" and db.tot
                or type(db.targetoftarget) == "table" and db.targetoftarget
                or type(db.target_of_target) == "table" and db.target_of_target
                or {}
        elseif unit == "focustarget" and type(db.focustarget) ~= "table" then
            db.focustarget = type(db.focus_target) == "table" and db.focus_target
                or type(db.focustargettarget) == "table" and db.focustargettarget
                or {}
        end
        db[unit] = type(db[unit]) == "table" and db[unit] or {}
        if unit == "targettarget" then
            db.tot = nil
            db.targetoftarget = nil
            db.target_of_target = nil
        elseif unit == "focustarget" then
            db.focus_target = nil
            db.focustargettarget = nil
        end
        return db[unit]
    end

    local function GeneralDB()
        local db = EnsureDB()
        db.general = type(db.general) == "table" and db.general or {}
        return db.general
    end

    local function BarsDB()
        local db = EnsureDB()
        db.bars = type(db.bars) == "table" and db.bars or {}
        return db.bars
    end

    local function GameplayDB()
        local db = EnsureDB()
        db.gameplay = type(db.gameplay) == "table" and db.gameplay or {}
        return db.gameplay
    end

    local function GroupDB(scope)
        local db = EnsureDB()
        local key
        if scope == "raid" or scope == "gf_raid" then
            key = "gf_raid"
        elseif scope == "mythicraid" or scope == "gf_mythicraid" then
            key = "gf_mythicraid"
        elseif scope == "priority" or scope == "gf_priority" then
            key = "gf_priority"
        else
            key = "gf_party"
        end
        db[key] = type(db[key]) == "table" and db[key] or {}
        return db[key]
    end

    local function ClampNumber(value, minValue, maxValue, step)
        value = tonumber(value)
        if value == nil then return nil end
        if minValue and value < minValue then value = minValue end
        if maxValue and value > maxValue then value = maxValue end
        step = tonumber(step)
        if step and step > 0 then
            value = floor((value / step) + 0.5) * step
        end
        if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
        return value
    end
    A.ClampNumber = A.ClampNumber or ClampNumber

    local function CurrentApplyService()
        return (MRef and MRef.ApplyService) or (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    end

    local function CallGlobal(name, ...)
        local ApplyService = CurrentApplyService()
        if type(ApplyService) == "table" and type(ApplyService.CallGlobal) == "function" then
            return ApplyService.CallGlobal(name, ...)
        end
        local fn = _G[name]
        if type(fn) == "function" then return fn(...) end
    end

    return {
        EnsureDB = EnsureDB,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        BarsDB = BarsDB,
        GameplayDB = GameplayDB,
        GroupDB = GroupDB,
        ClampNumber = ClampNumber,
        CallGlobal = CallGlobal,
    }
end
