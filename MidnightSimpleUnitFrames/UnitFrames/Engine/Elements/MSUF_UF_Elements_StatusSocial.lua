local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not UF then return end

-- Guild/friend relationship resolver behind the target frame's Guild / Friend
-- status icon.
--
-- Strictly out of combat by design: every API here is documented as
-- SecretArguments=AllowedWhenUntainted, so feeding it a restricted GUID from
-- addon code would raise - and combat is exactly when identity restrictions
-- apply. Resolve() answers nil the moment lockdown is active and performs
-- zero API reads; the indicator hides until the next out-of-combat evaluation.
--
-- Identity comes primarily from a GUID cache built by iterating both friend
-- lists (character friends via C_FriendList, Battle.net friends via the
-- per-friend game accounts): the direct probes (IsFriend by GUID /
-- GetGameAccountInfoByGUID) proved unreliable in practice - IsFriend needs the
-- server-populated list and never matches a Battle.net friend's character.
-- The cache rebuilds on the friend-list events and after login's ShowFriends()
-- request; both lists are tiny, so a rebuild is a few dozen table writes.
-- Relationship priority: Battle.net friend > character friend > guild member.
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitIsInMyGuild = UnitIsInMyGuild
local CreateFrame = CreateFrame
local type = type
local pairs = pairs

local issecretvalue = _G.issecretvalue or function(_) return false end

local friendKinds = {}   -- guid -> "bnet" | "friend"
local rebuildDirty = true

local function InCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function PlainString(value)
  if issecretvalue(value) == true then return nil end
  if type(value) ~= "string" or value == "" then return nil end
  return value
end

local function PlainGUID(unit)
  if type(UnitGUID) ~= "function" then return nil end
  return PlainString(UnitGUID(unit))
end

local function PlainTrue(value)
  if issecretvalue(value) == true then return false end
  return value == true or value == 1
end

local function AddGuid(guid, kind)
  guid = PlainString(guid)
  if guid then friendKinds[guid] = kind end
end

local function RebuildCache()
  if InCombat() then
    rebuildDirty = true
    return
  end
  rebuildDirty = false
  for guid in pairs(friendKinds) do friendKinds[guid] = nil end
  local friendList = _G.C_FriendList
  local getNumFriends = friendList and friendList.GetNumFriends
  local getFriendInfo = friendList and friendList.GetFriendInfoByIndex
  if type(getNumFriends) == "function" and type(getFriendInfo) == "function" then
    local num = getNumFriends()
    if type(num) == "number" then
      for i = 1, num do
        local info = getFriendInfo(i)
        if type(info) == "table" then AddGuid(info.guid, "friend") end
      end
    end
  end
  -- Battle.net second so an account that is both stays "bnet".
  local battleNet = _G.C_BattleNet
  local getNumBnet = _G.BNGetNumFriends
  local getNumGameAccounts = battleNet and battleNet.GetFriendNumGameAccounts
  local getGameAccount = battleNet and battleNet.GetFriendGameAccountInfo
  if type(getNumBnet) == "function"
    and type(getNumGameAccounts) == "function"
    and type(getGameAccount) == "function" then
    local numBnet = getNumBnet()
    if type(numBnet) == "number" then
      for i = 1, numBnet do
        local numGame = getNumGameAccounts(i)
        if type(numGame) == "number" then
          for j = 1, numGame do
            local game = getGameAccount(i, j)
            if type(game) == "table" then AddGuid(game.playerGuid, "bnet") end
          end
        end
      end
    end
  end
end

local function RefreshTargetIndicator()
  if InCombat() then return end
  local refresh = UF.RefreshStatusIndicators
  if type(refresh) == "function" then
    refresh("target", "MSUF_SOCIAL_CACHE")
  end
end

local Social = {}

--- Returns "bnet", "friend", "guild", or nil. Never touches an API in combat:
--- the lockdown check is the first statement.
function Social.Resolve(unit)
  if InCombat() then return nil end
  if type(unit) ~= "string" or unit == "" then return nil end
  if rebuildDirty then RebuildCache() end
  local guid = PlainGUID(unit)
  if guid then
    local kind = friendKinds[guid]
    if kind then return kind end
    -- Direct probes as a safety net for cache lag (fresh login, list still
    -- streaming). Both are OOC-only here, so plain GUIDs cannot raise.
    local battleNet = _G.C_BattleNet
    local getAccount = battleNet and battleNet.GetGameAccountInfoByGUID
    if type(getAccount) == "function" then
      local info = getAccount(guid)
      if issecretvalue(info) ~= true and info ~= nil then return "bnet" end
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

local SOCIAL_CACHE_EVENTS = {
  "FRIENDLIST_UPDATE",
  "BN_FRIEND_INFO_CHANGED",
  "BN_FRIEND_LIST_SIZE_CHANGED",
  "BN_FRIEND_ACCOUNT_ONLINE",
  "BN_FRIEND_ACCOUNT_OFFLINE",
  "BN_CONNECTED",
  "BN_DISCONNECTED",
}

if type(CreateFrame) == "function" then
  local listener = CreateFrame("Frame")
  listener:RegisterEvent("PLAYER_ENTERING_WORLD")
  listener:RegisterEvent("PLAYER_REGEN_ENABLED")
  for i = 1, #SOCIAL_CACHE_EVENTS do
    listener:RegisterEvent(SOCIAL_CACHE_EVENTS[i])
  end
  listener:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      -- Request the character friend list from the server once; without this
      -- it can stay empty until the player opens the social frame.
      local friendList = _G.C_FriendList
      if not InCombat() and friendList and type(friendList.ShowFriends) == "function" then
        friendList.ShowFriends()
      end
      rebuildDirty = true
      return
    end
    if event == "PLAYER_REGEN_ENABLED" then
      if rebuildDirty then
        RebuildCache()
        RefreshTargetIndicator()
      end
      return
    end
    if InCombat() then
      rebuildDirty = true
      return
    end
    RebuildCache()
    RefreshTargetIndicator()
  end)
end
