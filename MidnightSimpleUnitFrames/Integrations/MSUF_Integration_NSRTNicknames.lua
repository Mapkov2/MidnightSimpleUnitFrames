--- Integrations/MSUF_Integration_NSRTNicknames.lua
--- Optional Northern Sky Raid Tools nickname resolver for unit-frame display names.

local addonName, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

local UnitName = Text.UnitName
local UnitIsPlayer = Text.UnitIsPlayer
local CreateFrame = Text.CreateFrame
local InCombatLockdown = Text.InCombatLockdown
local UnitFullName = UnitFullName
local GetNormalizedRealmName = GetNormalizedRealmName
local issecretvalue = _G.issecretvalue or function(_) return false end
local type = type
local pairs = pairs

local CALLBACK_OWNER = "MidnightSimpleUnitFrames"
local NSRT_ADDON_KEY = "MSUF"
local NICKNAME_EVENT = "MSUF_NICKNAME_UPDATE"

local eventFrame
local resolverInstalled = false
local callbacksRegistered = false
local pendingNameRefresh = false
local nicknameByFullName = {}
local nicknameByName = {}
local nicknameCacheCount = 0

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function WipeTable(tbl)
  for key in pairs(tbl) do
    tbl[key] = nil
  end
end

local function ValidUnitToken(unit)
  if issecretvalue(unit) == true then
    return false
  end
  return type(unit) == "string" and unit ~= ""
end

local function GetNSRT()
  local api = _G.NSAPI
  local nsrt = _G.NSRT
  local settings = nsrt and nsrt.Settings
  if type(settings) ~= "table" then
    return nil
  end
  return api, settings, nsrt.NickNames
end

local function NSRTAddonKey(settings)
  if type(settings) ~= "table" then
    return nil
  end
  if settings[NSRT_ADDON_KEY] ~= nil then
    return NSRT_ADDON_KEY
  end
  if type(addonName) == "string"
    and addonName ~= ""
    and addonName ~= NSRT_ADDON_KEY
    and settings[addonName] ~= nil then
    return addonName
  end
  return nil
end

local function NSRTSettingsEnabled(settings)
  if type(settings) ~= "table" or settings.GlobalNickNames ~= true then
    return false, nil
  end
  local addonKey = NSRTAddonKey(settings)
  if addonKey and settings[addonKey] ~= true then
    return false, addonKey
  end
  return true, addonKey
end

local function CacheShortName(fullName, nickname)
  local shortName = fullName:match("^([^-]+)")
  if shortName and shortName ~= "" then
    nicknameByName[shortName] = nickname
  end
end

local function RebuildNicknameCache(nicknames)
  WipeTable(nicknameByFullName)
  WipeTable(nicknameByName)
  nicknameCacheCount = 0

  if type(nicknames) ~= "table" then
    return 0
  end

  for fullName, nickname in pairs(nicknames) do
    if type(fullName) == "string"
      and fullName ~= ""
      and issecretvalue(fullName) ~= true
      and type(nickname) == "string"
      and nickname ~= ""
      and issecretvalue(nickname) ~= true then
      nicknameByFullName[fullName] = nickname
      CacheShortName(fullName, nickname)
      nicknameCacheCount = nicknameCacheCount + 1
    end
  end

  return nicknameCacheCount
end

local function CleanDisplayName(displayName, fallback)
  if issecretvalue(displayName) == true then
    return fallback
  end
  if type(displayName) == "string" and displayName ~= "" then
    return displayName
  end
  return fallback
end

local function FullNameForUnit(unit)
  if not (UnitFullName and ValidUnitToken(unit)) then
    return nil
  end
  local name, realm = UnitFullName(unit)
  if issecretvalue(name) == true or issecretvalue(realm) == true then
    return nil
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(realm) ~= "string" or realm == "" then
    realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if issecretvalue(realm) == true or type(realm) ~= "string" or realm == "" then
      return nil
    end
  end
  return name .. "-" .. realm
end

local function ResolveDisplayName(unit)
  if not UnitName then
    return nil
  end

  local name = UnitName(unit)
  local nameSecret = issecretvalue(name) == true
  if not nameSecret and name == nil then
    return ""
  end

  if UnitIsPlayer then
    local isPlayer = UnitIsPlayer(unit)
    if issecretvalue(isPlayer) == true or isPlayer ~= true then
      return name
    end
  end

  if nameSecret then
    return name
  end

  if type(name) ~= "string" or name == "" then
    return name
  end

  if nicknameCacheCount <= 0 then
    return name
  end

  local fullName = FullNameForUnit(unit)
  if fullName then
    local fullDisplayName = nicknameByFullName[fullName]
    if fullDisplayName then
      return CleanDisplayName(fullDisplayName, name)
    end
  end

  return CleanDisplayName(nicknameByName[name], name)
end

local function SetResolver(resolver)
  if type(Text.SetDisplayNameResolver) == "function" then
    Text.SetDisplayNameResolver(resolver)
  else
    Text._pendingDisplayNameResolver = resolver
  end
end

local function UpdateResolver()
  local _, settings, nicknames = GetNSRT()
  if not settings then
    return false
  end

  local enabled = NSRTSettingsEnabled(settings)
  local nicknameCount = enabled and RebuildNicknameCache(nicknames) or 0
  if enabled and nicknameCount > 0 then
    if not resolverInstalled then
      SetResolver(ResolveDisplayName)
      Text.ResolveDisplayName = ResolveDisplayName
      resolverInstalled = true
    end
  else
    RebuildNicknameCache(nil)
    if resolverInstalled then
      SetResolver(nil)
      resolverInstalled = false
    end
    if Text.ResolveDisplayName == ResolveDisplayName then
      Text.ResolveDisplayName = nil
    end
    if Text._pendingDisplayNameResolver == ResolveDisplayName then
      Text._pendingDisplayNameResolver = nil
    end
  end
  return true
end

local function RefreshUnitFrameName(frame, _, runtime)
  local active = frame and frame._msufActiveElements
  if not active then
    return false
  end
  local touched = false
  if active.NameText == true and runtime.UpdateName then
    runtime.UpdateName(frame, NICKNAME_EVENT, frame.unit)
    touched = true
  end
  if active.Text == true and runtime.UpdateInline then
    runtime.UpdateInline(frame, NICKNAME_EVENT, nil)
    touched = true
  end
  return touched
end

local function RefreshUnitFrameNames()
  local UF = MSUF and MSUF.UF
  local runtime = MSUF and MSUF.UFTextRuntime
  if not (UF and UF.ForEachFrame and runtime) then
    return false
  end
  return UF.ForEachFrame(RefreshUnitFrameName, runtime) == true
end

local function RefreshGroupFrameNames()
  local GF = MSUF and MSUF.GF
  if not (GF and GF.RefreshGroupNames) then
    return false
  end
  return GF.RefreshGroupNames() == true
end

local function QueuePostCombatRefresh()
  pendingNameRefresh = true
  if eventFrame then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

local function RefreshNamesNow()
  UpdateResolver()
  RefreshUnitFrameNames()
  RefreshGroupFrameNames()
end

local function RefreshNames()
  if InCombat() then
    QueuePostCombatRefresh()
    return
  end
  RefreshNamesNow()
end

local function RegisterNSRTCallbacks()
  if callbacksRegistered then
    return true
  end
  local api = GetNSRT()
  local register = api and api.RegisterCallback
  if type(register) ~= "function" then
    return false
  end
  register(CALLBACK_OWNER, "NSRT_NICKNAME_UPDATED", RefreshNames)
  register(CALLBACK_OWNER, "MSUF_NICKNAME_TOGGLE", RefreshNames)
  callbacksRegistered = true
  return true
end

local function StopDiscoveryEvents()
  if not eventFrame then
    return
  end
  eventFrame:UnregisterEvent("ADDON_LOADED")
  eventFrame:UnregisterEvent("PLAYER_LOGIN")
  eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

local function TryEnableNSRT(stopAfterThisEvent)
  local ready = UpdateResolver()
  local registered = RegisterNSRTCallbacks()
  if (ready and registered) or stopAfterThisEvent then
    StopDiscoveryEvents()
  end
  return ready
end

if CreateFrame then
  eventFrame = CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
      if not InCombat() then
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingNameRefresh then
          pendingNameRefresh = false
          RefreshNamesNow()
        end
      end
      return
    end
    TryEnableNSRT(event == "PLAYER_ENTERING_WORLD")
  end)
  eventFrame:RegisterEvent("ADDON_LOADED")
  eventFrame:RegisterEvent("PLAYER_LOGIN")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

TryEnableNSRT(false)

Text.RefreshDisplayNames = RefreshNames
