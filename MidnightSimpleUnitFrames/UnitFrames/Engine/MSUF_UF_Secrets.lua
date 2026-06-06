local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local Secrets = MSUF.Secrets or {}
MSUF.Secrets = Secrets

-- Capture issecretvalue once, falling back to a constant-false stub on clients
-- that predate the secret-value API. This lets every helper inline the raw
-- `issecretvalue(value) == true` test directly instead of routing through an
-- IsSecret() call: the predicates below (IsNil/PlainTrue/PlainFalse/SafeNumber/
-- ValueOrDefault) run inside the per-event power/health/prediction read loops,
-- so removing one Lua call frame per check trims real hot-path cost. IsSecret
-- stays exported as the single-call public API for callers outside this file.
local issecretvalue = _G.issecretvalue or function(...) return false end
local nativeSecrets = _G.issecretvalue ~= nil
local tonumber = tonumber

local function IsSecret(value)
    return issecretvalue(value) == true
end

local function NotSecret(value)
    return issecretvalue(value) ~= true
end

local function IsNil(value)
    if issecretvalue(value) == true then
        return false
    end
    return value == nil
end

local function ValueOrDefault(value, fallback)
    if issecretvalue(value) == true then
        return value
    end
    if value == nil then
        return fallback
    end
    return value
end

local function PlainTrue(value)
    if issecretvalue(value) == true then
        return false
    end
    return value == true or value == 1
end

local function PlainFalse(value)
    if issecretvalue(value) == true then
        return false
    end
    return value == false or value == 0
end

local function SafeNumber(value)
    if issecretvalue(value) == true then
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
    if issecretvalue(exists) == true then
        return true
    end
    return exists == true or exists == 1
end

-- When issecretvalue is absent the inner stub call in each predicate is pure
-- overhead: every check pays a full Lua call frame just to return false/nil.
-- Replace the hot-path predicates with minimal direct stubs. The exports below
-- happen after this block, so callers that localise these at module load time
-- (the common pattern) receive the fast versions automatically.
if not nativeSecrets then
    IsSecret       = function(_) return false end
    NotSecret      = function(_) return true end
    IsNil          = function(v) return v == nil end
    ValueOrDefault = function(v, fb) return v ~= nil and v or fb end
    PlainTrue      = function(v) return v == true or v == 1 end
    PlainFalse     = function(v) return v == false or v == 0 end
    SafeNumber     = tonumber
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
