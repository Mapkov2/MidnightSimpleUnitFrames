local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local Secrets = MSUF.Secrets or {}
MSUF.Secrets = Secrets

local issecretvalue = _G.issecretvalue
local tonumber = tonumber

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

local function NotSecret(value)
    return not IsSecret(value)
end

local function IsNil(value)
    if IsSecret(value) then
        return false
    end
    return value == nil
end

local function ValueOrDefault(value, fallback)
    if IsSecret(value) then
        return value
    end
    if value == nil then
        return fallback
    end
    return value
end

local function PlainTrue(value)
    if IsSecret(value) then
        return false
    end
    return value == true or value == 1
end

local function PlainFalse(value)
    if IsSecret(value) then
        return false
    end
    return value == false or value == 0
end

local function SafeNumber(value)
    if IsSecret(value) then
        return nil
    end
    return tonumber(value)
end

local function UnitMissing(unit)
    local UnitExists = _G.UnitExists
    if not UnitExists then
        return false
    end
    return PlainFalse(UnitExists(unit))
end

local function UnitExistsPlain(unit)
    local UnitExists = _G.UnitExists
    if not UnitExists then
        return true
    end
    local exists = UnitExists(unit)
    if IsSecret(exists) then
        return true
    end
    return exists == true or exists == 1
end

Secrets.IsSecret = IsSecret
Secrets.NotSecret = NotSecret
Secrets.IsNil = IsNil
Secrets.ValueOrDefault = ValueOrDefault
Secrets.PlainTrue = PlainTrue
Secrets.PlainFalse = PlainFalse
Secrets.SafeNumber = SafeNumber
Secrets.UnitMissing = UnitMissing
Secrets.UnitExistsPlain = UnitExistsPlain
