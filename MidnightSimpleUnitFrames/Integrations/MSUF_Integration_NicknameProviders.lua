--- Versioned public nickname-provider API for unit and group frame display names.
--- Providers are never invoked in combat. Changes received in combat are
--- coalesced and applied once after PLAYER_REGEN_ENABLED.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local Text = MSUF.UFText
if not Text then return end

local UnitName = Text.UnitName or _G.UnitName
local UnitFullName = _G.UnitFullName
local GetNormalizedRealmName = _G.GetNormalizedRealmName
local CreateFrame = Text.CreateFrame or _G.CreateFrame
local InCombatLockdown = Text.InCombatLockdown or _G.InCombatLockdown
local issecretvalue = _G.issecretvalue or function(_) return false end
local type = type
local pairs = pairs
local pcall = pcall
local sort = table.sort

local API = { VERSION = 1 }
local providers = {}
local orderedProviders = {}
local providerCount = 0
local resolverInstalled = false
local orderDirty = false
local pendingApply = false
local eventFrame

local resolvedByFullName = {}
local resolvedByShortName = {}
local AMBIGUOUS = {}

local function InCombat()
  return InCombatLockdown and InCombatLockdown() == true
end

local function ValidOwner(owner)
  return type(owner) == "string"
    and owner ~= ""
    and #owner <= 80
    and owner:match("^[%w_.%-]+$") ~= nil
end

local function FiniteNumber(value)
  return type(value) == "number"
    and value == value
    and value > -math.huge
    and value < math.huge
end

local function OwnerKey(owner)
  return owner:lower()
end

local function Wipe(tbl)
  for key in pairs(tbl) do
    tbl[key] = nil
  end
end

local function ClearResolvedCache()
  Wipe(resolvedByFullName)
  Wipe(resolvedByShortName)
end

local function FullNameForUnit(unit, nativeName)
  if not UnitFullName or type(unit) ~= "string" or unit == "" then
    return nil
  end
  if issecretvalue(unit) == true then
    return nil
  end

  local name, realm = UnitFullName(unit)
  if issecretvalue(name) == true or issecretvalue(realm) == true then
    return nil
  end
  if type(name) ~= "string" or name == "" then
    name = nativeName
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(realm) ~= "string" or realm == "" then
    realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
  end
  if issecretvalue(realm) == true or type(realm) ~= "string" or realm == "" then
    return nil
  end
  return name .. "-" .. realm
end

local function CacheShortName(nativeName, displayName)
  local cached = resolvedByShortName[nativeName]
  if cached == nil then
    resolvedByShortName[nativeName] = displayName
  elseif cached ~= displayName then
    resolvedByShortName[nativeName] = AMBIGUOUS
  end
end

local function FrozenDisplayName(nativeName, fullName)
  local cached = fullName and resolvedByFullName[fullName] or nil
  if type(cached) == "string" then
    return cached
  end
  cached = resolvedByShortName[nativeName]
  if type(cached) == "string" then
    return cached
  end
  return nativeName
end

local function ReportProviderError(record, err)
  local message = ("MSUF Nickname API (%s): resolver failed: %s"):format(
    record and record.owner or "?", tostring(err))
  local handler = type(_G.geterrorhandler) == "function" and _G.geterrorhandler()
  if type(handler) == "function" then
    handler(message)
  elseif type(_G.print) == "function" then
    _G.print(message)
  end
end

local function RebuildProviderOrder()
  Wipe(orderedProviders)
  providerCount = 0
  for _, record in pairs(providers) do
    providerCount = providerCount + 1
    record.failed = false
    orderedProviders[providerCount] = record
  end
  sort(orderedProviders, function(a, b)
    if a.priority == b.priority then
      return a.ownerKey < b.ownerKey
    end
    return a.priority > b.priority
  end)
  orderDirty = false
end

local function ResolveDisplayName(unit)
  if not UnitName then return nil end

  local nativeName = UnitName(unit)
  if issecretvalue(nativeName) == true
    or type(nativeName) ~= "string"
    or nativeName == "" then
    return nativeName
  end

  -- Combat is a frozen snapshot: no provider callback, cache invalidation, or
  -- frame refresh may originate here. Avoid even the extra UnitFullName lookup;
  -- unknown or ambiguous identities keep their native name until combat ends.
  if InCombat() then
    return FrozenDisplayName(nativeName, nil)
  end

  local fullName = FullNameForUnit(unit, nativeName)

  local cached = fullName and resolvedByFullName[fullName] or nil
  if cached == false then return nativeName end
  if type(cached) == "string" then return cached end
  if not fullName then
    cached = resolvedByShortName[nativeName]
    if cached == false then return nativeName end
    if type(cached) == "string" then return cached end
  end

  local displayName = nativeName
  for i = 1, providerCount do
    local record = orderedProviders[i]
    if record and not record.failed then
      local ok, result = pcall(record.resolve, unit, nativeName, fullName)
      if not ok then
        record.failed = true
        ReportProviderError(record, result)
      elseif issecretvalue(result) ~= true
        and type(result) == "string"
        and result ~= ""
        and result ~= nativeName then
        displayName = result
        break
      end
    end
  end

  if fullName then
    resolvedByFullName[fullName] = displayName ~= nativeName and displayName or false
  end
  CacheShortName(nativeName, displayName ~= nativeName and displayName or false)
  return displayName
end

local function SetResolver(resolver)
  if type(Text.SetDisplayNameResolver) == "function" then
    Text.SetDisplayNameResolver(resolver)
  else
    Text._pendingDisplayNameResolver = resolver
  end
end

local function SyncResolver()
  local shouldInstall = providerCount > 0
  if shouldInstall == resolverInstalled then return end
  SetResolver(shouldInstall and ResolveDisplayName or nil)
  resolverInstalled = shouldInstall
end

local function RefreshUnitFrameName(frame, _, runtime)
  local active = frame and frame._msufActiveElements
  if not active then return false end
  local touched = false
  if active.NameText == true and runtime.UpdateName then
    runtime.UpdateName(frame, "MSUF_NICKNAME_UPDATE", frame.MSUFUnitKey)
    touched = true
  end
  if active.Text == true and runtime.UpdateInline then
    runtime.UpdateInline(frame, "MSUF_NICKNAME_UPDATE", nil)
    touched = true
  end
  return touched
end

local function RefreshUnitFrameNames()
  local UF = MSUF.UF
  local runtime = MSUF.UFTextRuntime
  if not (UF and UF.ForEachFrame and runtime) then return false end
  return UF.ForEachFrame(RefreshUnitFrameName, runtime) == true
end

local function RefreshGroupFrameNames()
  local GF = MSUF.GF
  if not (GF and GF.RefreshGroupNames) then return false end
  return GF.RefreshGroupNames() == true
end

local function ApplyChanges()
  if InCombat() then return false end
  if orderDirty then RebuildProviderOrder() end
  ClearResolvedCache()
  SyncResolver()
  RefreshUnitFrameNames()
  RefreshGroupFrameNames()
  return true
end

local function EnsurePostCombatEvent()
  if not eventFrame and CreateFrame then
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
      if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
      eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
      if pendingApply then
        pendingApply = false
        ApplyChanges()
      end
    end)
  end
  if eventFrame then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

local function RequestApply()
  if InCombat() then
    pendingApply = true
    EnsurePostCombatEvent()
    return true, "deferred_combat"
  end
  pendingApply = false
  ApplyChanges()
  return true
end

function API.GetVersion()
  return API.VERSION
end

function API.GetCapabilities()
  return {
    multipleProviders = true,
    priorities = true,
    cached = true,
    eventDriven = true,
    combatUpdates = false,
    polling = false,
  }
end

function API.RegisterProvider(owner, provider, priority)
  if not ValidOwner(owner) then return false, "invalid_owner" end

  local resolve = provider
  if type(provider) == "table" then
    resolve = provider.resolve
    priority = provider.priority
  end
  if type(resolve) ~= "function" then return false, "invalid_resolver" end
  if priority == nil then priority = 0 end
  if not FiniteNumber(priority) then return false, "invalid_priority" end

  local ownerKey = OwnerKey(owner)
  local current = providers[ownerKey]
  if current and current.resolve == resolve and current.priority == priority then
    return true, "unchanged"
  end

  providers[ownerKey] = {
    owner = owner,
    ownerKey = ownerKey,
    resolve = resolve,
    priority = priority,
  }
  orderDirty = true
  return RequestApply()
end

function API.UnregisterProvider(owner)
  if not ValidOwner(owner) then return false, "invalid_owner" end
  local ownerKey = OwnerKey(owner)
  if not providers[ownerKey] then return true, "not_registered" end
  providers[ownerKey] = nil
  orderDirty = true
  return RequestApply()
end

function API.NotifyChanged(owner)
  if not ValidOwner(owner) then return false, "invalid_owner" end
  local record = providers[OwnerKey(owner)]
  if not record then return false, "not_registered" end
  record.failed = false
  return RequestApply()
end

function API.IsProviderRegistered(owner)
  return ValidOwner(owner) and providers[OwnerKey(owner)] ~= nil or false
end

MSUF.API = MSUF.API or MSUF.Public or {}
MSUF.Public = MSUF.Public or MSUF.API
MSUF.API.Nicknames = API
MSUF.Public.Nicknames = API

-- Internal compatibility hook for the pre-provider display-name service.
Text.RefreshDisplayNames = RequestApply
