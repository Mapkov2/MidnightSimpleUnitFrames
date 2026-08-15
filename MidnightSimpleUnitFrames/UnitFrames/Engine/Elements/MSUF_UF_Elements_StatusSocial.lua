local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not UF then return end

-- Guild/friend relationship resolver behind the target frame's Guild / Friend
-- status icon.
--
-- Strictly out of combat by design: every API here (C_FriendList.IsFriend,
-- C_BattleNet.GetGameAccountInfoByGUID, UnitIsInMyGuild) is documented as
-- SecretArguments=AllowedWhenUntainted, so feeding it a restricted GUID from
-- addon code would raise - and combat is exactly when identity restrictions
-- apply. Resolve() therefore answers nil the moment lockdown is active and
-- performs zero API reads; the indicator simply hides until the next
-- out-of-combat evaluation. Relationship priority: Battle.net friend >
-- character friend > guild member.
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitIsInMyGuild = UnitIsInMyGuild
local type = type

local issecretvalue = _G.issecretvalue or function(_) return false end

local function PlainGUID(unit)
  if type(UnitGUID) ~= "function" then return nil end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true then return nil end
  if type(guid) ~= "string" or guid == "" then return nil end
  return guid
end

local function PlainTrue(value)
  if issecretvalue(value) == true then return false end
  return value == true or value == 1
end

local Social = {}

--- Returns "bnet", "friend", "guild", or nil. Never called into while in
--- combat: the lockdown check is the first statement, before any API read.
function Social.Resolve(unit)
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    return nil
  end
  if type(unit) ~= "string" or unit == "" then return nil end
  local guid = PlainGUID(unit)
  if guid then
    local battleNet = _G.C_BattleNet
    local getAccount = battleNet and battleNet.GetGameAccountInfoByGUID
    if type(getAccount) == "function" then
      local info = getAccount(guid)
      if issecretvalue(info) ~= true and info ~= nil then
        return "bnet"
      end
    end
    local friendList = _G.C_FriendList
    local isFriend = friendList and friendList.IsFriend
    if type(isFriend) == "function" and PlainTrue(isFriend(guid)) then
      return "friend"
    end
  end
  if type(UnitIsInMyGuild) == "function" and PlainTrue(UnitIsInMyGuild(unit)) then
    return "guild"
  end
  return nil
end

MSUF.UFSocial = Social
