local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local Secrets = MSUF.Secrets or {}
MSUF.Secrets = Secrets

-- Secret-value compatibility helpers.
-- War Within restricted APIs can return secret values that must not be compared, serialized,
-- or coerced casually. Centralize the safe predicates so element files handle them the same.
local issecretvalue = _G.issecretvalue
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


Secrets.IsSecret = IsSecret
Secrets.NotSecret = NotSecret
Secrets.IsNil = IsNil
Secrets.ValueOrDefault = ValueOrDefault
Secrets.PlainTrue = PlainTrue
Secrets.PlainFalse = PlainFalse
Secrets.SafeNumber = SafeNumber
Secrets.UnitMissing = UnitMissing
Secrets.UnitExistsPlain = UnitExistsPlain

local function PlainBool(value)
  if issecretvalue(value) == true then
    return nil
  end
  if value == true or value == 1 then
    return true
  end
  if value == false or value == 0 then
    return false
  end
  return nil
end
Secrets.PlainBool = PlainBool

function Secrets.CanAccessTable(value)
    return not issecretvalue(value) and type(value) == "table" and _G.canaccesstable(value)
end
function Secrets.CanAccessOptionalTable(value)
    if issecretvalue(value) then return false end
    return value == nil or Secrets.CanAccessTable(value)
end
