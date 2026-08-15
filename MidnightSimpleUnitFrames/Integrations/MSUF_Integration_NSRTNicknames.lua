--- Integrations/MSUF_Integration_NSRTNicknames.lua
--- Optional Northern Sky Raid Tools nickname resolver for unit-frame display names.

local addonName, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end
local NicknameAPI = MSUF.API and MSUF.API.Nicknames
if not (NicknameAPI and NicknameAPI.GetVersion and NicknameAPI.GetVersion() >= 1) then return end

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
local PROVIDER_OWNER = "NorthernSkyRaidTools"
local PROVIDER_PRIORITY = 100

local eventFrame
local providerRegistered = false
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

local function MSUFIntegrationEnabled()
  local db = _G.MSUF_DB
  local general = type(db) == "table" and db.general
  return not (type(general) == "table" and general.nsrtNicknameIntegration == false)
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

local function ResolveDisplayName(unit, name, fullName, playerOnlyPrevalidated, identityPrepared)
  if not UnitName then
    return nil
  end

  if name == nil and identityPrepared ~= true then
    name = UnitName(unit)
  end
  local nameSecret = issecretvalue(name) == true
  if not nameSecret and name == nil then
    return ""
  end

  if playerOnlyPrevalidated ~= true and UnitIsPlayer then
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

  if fullName == nil and identityPrepared ~= true then
    fullName = FullNameForUnit(unit)
  end
  if fullName then
    local fullDisplayName = nicknameByFullName[fullName]
    if fullDisplayName then
      return CleanDisplayName(fullDisplayName, name)
    end
  end

  return CleanDisplayName(nicknameByName[name], name)
end

local function UpdateResolver()
  local _, settings, nicknames = GetNSRT()
  if not settings then
    return false
  end

  local enabled = MSUFIntegrationEnabled() and NSRTSettingsEnabled(settings)
  local nicknameCount = enabled and RebuildNicknameCache(nicknames) or 0
  if enabled and nicknameCount > 0 then
    if not providerRegistered then
      local ok = NicknameAPI.RegisterProvider(PROVIDER_OWNER, {
        resolve = ResolveDisplayName,
        priority = PROVIDER_PRIORITY,
        playerOnly = true,
      })
      providerRegistered = ok == true
    else
      NicknameAPI.NotifyChanged(PROVIDER_OWNER)
    end
  else
    RebuildNicknameCache(nil)
    if providerRegistered then
      NicknameAPI.UnregisterProvider(PROVIDER_OWNER)
      providerRegistered = false
    end
  end
  return true
end

local function QueuePostCombatRefresh()
  pendingNameRefresh = true
  if eventFrame then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

local function RefreshNamesNow()
  UpdateResolver()
end

local function RefreshNames()
  if InCombat() then
    QueuePostCombatRefresh()
    return
  end
  RefreshNamesNow()
end

ExportPublic("MSUF_NSRTNicknames_ApplySetting", RefreshNames)

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
