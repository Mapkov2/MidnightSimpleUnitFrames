--- UnitFrames/Engine/Group/MSUF_UF_Group_Priority.lua
--- Priority Frames selection and user interaction.
---
--- The secure header and protected geometry live in Group_Headers; this file
--- owns the cold-path roster resolver, character-local pins, hover hotkey, and
--- the small mutation API used by Menu2. It deliberately creates no event
--- frame, ticker, or OnUpdate: Group_Runtime already owns every relevant event.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local type = type
local tonumber = tonumber
local tostring = tostring
local floor = math.floor
local pairs = pairs
local table_concat = table.concat
local table_remove = table.remove
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local issecretvalue = _G.issecretvalue or function(_) return false end
local wipe = _G.wipe or table.wipe

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local MAX_PRIORITY_FRAMES = 5
local MAX_STORED_PINS = MAX_PRIORITY_FRAMES
local EMPTY_PINS = {}
local resolvedUnits = {}
local resolvedNames = {}
local seenUnits = {}
local rosterByGUID = {}
local rosterByName = {}
local rosterByFoldedName = {}
local rosterEntries = {}
local rosterCount = 0
local priorityListeners = {}
local BuildRosterIndex, ResetRosterIndex

GF.MAX_PRIORITY_FRAMES = MAX_PRIORITY_FRAMES

local function PlainString(value)
  return issecretvalue(value) ~= true and type(value) == "string" and value ~= "" and value or nil
end

local function ClampMaxFrames(value)
  value = floor((tonumber(value) or MAX_PRIORITY_FRAMES) + 0.5)
  if value < 1 then return 1 end
  if value > MAX_PRIORITY_FRAMES then return MAX_PRIORITY_FRAMES end
  return value
end

local function PriorityConf()
  -- The Group runtime repairs DB state at its OOC layout boundary and every
  -- mutation refreshes these cached references. Priority event registration is
  -- allowed in combat, so it must remain a direct cache read.
  return GF.GetPriorityConf and GF.GetPriorityConf() or nil
end

local function CurrentGroupType()
  local kind = type(GF.GetLiveGroupKind) == "function" and GF.GetLiveGroupKind() or nil
  if kind == "party" then return "party" end
  if kind == "raid" or kind == "mythicraid" then return "raid" end
  if IsInRaid and IsInRaid() then return "raid" end
  if IsInGroup and IsInGroup() then return "party" end
  return nil
end

local function PriorityBaseKind(groupType)
  groupType = groupType or CurrentGroupType()
  if groupType == "party" then return "party" end
  if groupType == "raid" then
    local kind = type(GF.GetLiveRaidKind) == "function" and GF.GetLiveRaidKind() or "raid"
    return kind == "mythicraid" and "mythicraid" or "raid"
  end
  return nil
end

function GF.GetPriorityGroupType()
  return CurrentGroupType()
end

function GF.GetPriorityBaseKind()
  return PriorityBaseKind()
end

local function CharacterKey()
  local getKey = _G.MSUF_GetCharKey
  if type(getKey) == "function" then
    local key = getKey()
    if type(key) == "string" and key ~= "" then return key end
  end
  return nil
end

local function CharacterPriorityState(create)
  local root = _G.MSUF_GlobalDB
  if type(root) ~= "table" then
    if not create then return nil end
    root = {}
    ExportPublic("MSUF_GlobalDB", root)
  end
  local chars = root.char
  if type(chars) ~= "table" then
    if not create then return nil end
    chars = {}
    root.char = chars
  end
  local key = CharacterKey()
  if not key then return nil end
  local state = chars[key]
  if type(state) ~= "table" then
    if not create then return nil end
    state = {}
    chars[key] = state
  end
  local priority = state.priorityFrames
  if type(priority) ~= "table" then
    if not create then return nil end
    priority = {}
    state.priorityFrames = priority
  end
  local pins = priority.pins
  if type(pins) ~= "table" then
    if not create then return priority end
    pins = {}
    priority.pins = pins
  end
  return priority
end

local function Pins(create)
  local state = CharacterPriorityState(create)
  local pins = state and state.pins
  return type(pins) == "table" and pins or EMPTY_PINS
end

local function PinIdentity(pin)
  if type(pin) ~= "table" then return nil, nil end
  return PlainString(pin.guid), PlainString(pin.name)
end

local function RequestRefresh(reason)
  GF._prioritySelectionRevision = (GF._prioritySelectionRevision or 0) + 1
  for _, callback in pairs(priorityListeners) do
    callback(reason or "selection")
  end
  if type(GF.RefreshPriorityFrames) == "function" then
    return GF.RefreshPriorityFrames(reason or "selection")
  end
  GF._pendingPriorityRefresh = reason or true
  return false
end

function GF.RegisterPriorityListener(owner, callback)
  if type(owner) ~= "string" or owner == "" or type(callback) ~= "function" then return false end
  priorityListeners[owner] = callback
  return true
end

function GF.UnregisterPriorityListener(owner)
  if priorityListeners[owner] == nil then return false end
  priorityListeners[owner] = nil
  return true
end

function GF.NotifyPriorityListeners(reason, count)
  for _, callback in pairs(priorityListeners) do callback(reason or "runtime", count) end
end

function GF.GetPriorityPins()
  return Pins(false)
end

function GF.GetPriorityPinCount()
  return #Pins(false)
end

local function BaseFramesEnabled(groupType)
  local kind = PriorityBaseKind(groupType)
  local baseConf = kind and type(GF.GetConf) == "function" and GF.GetConf(kind) or nil
  return baseConf and baseConf.enabled == true or false, kind
end

local function FillPriorityPinView(out, groupType, featureEnabled, baseFramesEnabled)
  out = type(out) == "table" and out or {}
  local pins = Pins(false)
  for i = 1, #pins do
    local row = out[i]
    if type(row) ~= "table" then row = {}; out[i] = row end
    local guid, name = PinIdentity(pins[i])
    local entry = guid and rosterByGUID[guid] or nil
    if not entry and name then entry = rosterByName[name] or rosterByFoldedName[name:lower()] end
    if entry and guid and entry.guid == guid and entry.name and entry.name ~= name then
      pins[i].name = entry.name
      name = entry.name
    end
    local selected = entry and seenUnits[entry.guid or entry.name] == true or false
    local active = selected and featureEnabled == true and groupType ~= nil and baseFramesEnabled == true
    row.index = i
    row.guid = guid
    row.name = entry and entry.name or name or "Unknown"
    row.present = entry ~= nil
    row.selected = selected
    row.active = active
    row.isTank = entry and entry.role == "TANK" or false
    row.unit = entry and entry.unit or nil
    row.waitingReason = not groupType and "NOT_IN_GROUP"
      or not entry and "NOT_PRESENT"
      or featureEnabled ~= true and "DISABLED"
      or baseFramesEnabled ~= true and "GROUP_FRAMES_DISABLED"
      or not selected and "CAPACITY"
      or nil
  end
  for i = #out, #pins + 1, -1 do out[i] = nil end
  return out
end

function GF.GetPriorityPinView(out)
  GF.ResolvePrioritySelection()
  local groupType = CurrentGroupType()
  local conf = PriorityConf()
  if groupType and not (conf and conf.enabled == true) then BuildRosterIndex(groupType) end
  return FillPriorityPinView(out, groupType, conf and conf.enabled == true, BaseFramesEnabled(groupType))
end

local function FillPriorityState(out, conf, selectedCount, names, groupType)
  out = type(out) == "table" and out or {}
  conf = conf or {}
  out.enabled = conf.enabled == true
  out.autoTanks = conf.autoTanks == true
  out.maxFrames = ClampMaxFrames(conf.maxFrames)
  out.pinCount = #Pins(false)
  out.selectedCount = selectedCount or 0
  out.groupType = groupType
  out.inGroup = groupType ~= nil
  out.inRaid = groupType == "raid"
  out.inParty = groupType == "party"
  out.baseFramesEnabled, out.baseKind = BaseFramesEnabled(groupType)
  out.groupFramesEnabled = out.baseFramesEnabled
  -- Compatibility fields remain explicit for external callers while Menu2
  -- consumes the generic base-frame state.
  out.raidFramesEnabled = out.inRaid and out.baseFramesEnabled or false
  out.partyFramesEnabled = out.inParty and out.baseFramesEnabled or false
  out.visibleCount = out.enabled and out.inGroup and out.baseFramesEnabled and out.selectedCount or 0
  -- activeCount is retained as the public compatibility field, but now means
  -- what the player can actually see rather than merely what was selected.
  out.activeCount = out.visibleCount
  out.active = out.visibleCount > 0
  out.names = names
  return out
end


function GF.GetPriorityState(out)
  local conf = PriorityConf() or {}
  local _, activeCount, _, names = GF.ResolvePrioritySelection()
  return FillPriorityState(out, conf, activeCount, names, CurrentGroupType())
end

function GF.PriorityFramesEnabled()
  local conf = PriorityConf()
  return conf and conf.enabled == true or false
end

function GF.PriorityFramesConfigured()
  local conf = PriorityConf()
  return conf and conf.enabled == true and (conf.autoTanks == true or #Pins(false) > 0) or false
end

local function PartyUnitName(unit)
  if not UnitName then return nil end
  local name, realm = UnitName(unit)
  name = PlainString(name)
  if not name then return end
  realm = PlainString(realm)
  return realm and (name .. "-" .. realm) or name
end

local function AddRosterUnit(unit, name)
  name = PlainString(name)
  if not name then return end
  local guid = UnitGUID and UnitGUID(unit) or nil
  guid = PlainString(guid)
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
  if issecretvalue(role) == true then role = nil end
  rosterCount = rosterCount + 1
  local entry = rosterEntries[rosterCount]
  if not entry then
    entry = {}
    rosterEntries[rosterCount] = entry
  end
  entry.unit = unit
  entry.name = name
  entry.guid = guid
  entry.role = role
  if guid then rosterByGUID[guid] = entry end
  rosterByName[name] = entry
  rosterByFoldedName[name:lower()] = entry
end

local function AddRaidRosterEntry(index)
  AddRosterUnit("raid" .. index, GetRaidRosterInfo and GetRaidRosterInfo(index) or nil)
end

ResetRosterIndex = function()
  wipe(rosterByGUID)
  wipe(rosterByName)
  wipe(rosterByFoldedName)
  for i = 1, rosterCount do
    local entry = rosterEntries[i]
    entry.unit, entry.name, entry.guid, entry.role = nil, nil, nil, nil
  end
  rosterCount = 0
end

BuildRosterIndex = function(groupType)
  ResetRosterIndex()
  groupType = groupType or CurrentGroupType()
  if groupType == "party" then
    AddRosterUnit("player", PartyUnitName("player"))
    local count = GetNumSubgroupMembers and GetNumSubgroupMembers()
    if issecretvalue(count) == true or type(count) ~= "number" then
      local total = GetNumGroupMembers and GetNumGroupMembers() or 0
      if issecretvalue(total) == true or type(total) ~= "number" then return rosterCount end
      count = total - 1
    end
    count = floor(count + 0.5)
    if count < 0 then count = 0 elseif count > 4 then count = 4 end
    for i = 1, count do AddRosterUnit("party" .. i, PartyUnitName("party" .. i)) end
    return rosterCount
  end
  if groupType ~= "raid" then return 0 end
  local count = GetNumGroupMembers and GetNumGroupMembers() or 0
  if issecretvalue(count) == true or type(count) ~= "number" then return 0 end
  count = floor(count + 0.5)
  if count > 40 then count = 40 end
  for i = 1, count do AddRaidRosterEntry(i) end
  return rosterCount
end

local function AddResolved(entry, limit)
  if not entry or #resolvedUnits >= limit then return false end
  local identity = entry.guid or entry.name
  if not identity or seenUnits[identity] then return false end
  seenUnits[identity] = true
  resolvedUnits[#resolvedUnits + 1] = entry.unit
  resolvedNames[#resolvedNames + 1] = entry.name
  return true
end

--- Resolve the exact secure name list and group-unit list. Returned tables are
--- shared cold-path scratch storage and must be consumed synchronously.
function GF.ResolvePrioritySelection()
  wipe(resolvedUnits)
  wipe(resolvedNames)
  wipe(seenUnits)

  local conf = PriorityConf()
  local groupType = CurrentGroupType()
  if not (conf and conf.enabled == true and groupType) then
    ResetRosterIndex()
    return nil, 0, resolvedUnits, resolvedNames
  end

  local limit = ClampMaxFrames(conf.maxFrames)
  BuildRosterIndex(groupType)
  if conf.autoTanks == true then
    for i = 1, rosterCount do
      local entry = rosterEntries[i]
      if entry.role == "TANK" then AddResolved(entry, limit) end
      if #resolvedUnits >= limit then break end
    end
  end

  local pins = Pins(false)
  for i = 1, #pins do
    if #resolvedUnits >= limit then break end
    local guid, name = PinIdentity(pins[i])
    local entry = guid and rosterByGUID[guid] or nil
    if not entry and name then
      entry = rosterByName[name] or rosterByFoldedName[name:lower()]
    end
    AddResolved(entry, limit)
  end

  local count = #resolvedNames
  return count > 0 and table_concat(resolvedNames, ",") or nil, count, resolvedUnits, resolvedNames
end

--- Menu2 asks for both panels together. Resolve and index the roster once so a
--- page refresh never performs two 40-member scans.
function GF.GetPriorityMenuSnapshot(stateOut, pinOut)
  local conf = PriorityConf() or {}
  local _, activeCount, _, names = GF.ResolvePrioritySelection()
  local groupType = CurrentGroupType()
  if groupType and conf.enabled ~= true then BuildRosterIndex(groupType) end
  stateOut = FillPriorityState(stateOut, conf, activeCount, names, groupType)
  pinOut = FillPriorityPinView(pinOut, groupType, stateOut.enabled, stateOut.baseFramesEnabled)
  return stateOut, pinOut
end

function GF.FindPriorityPin(guid, name)
  guid, name = PlainString(guid), PlainString(name)
  local pins = Pins(false)
  for i = 1, #pins do
    local pinGUID, pinName = PinIdentity(pins[i])
    if (guid and pinGUID == guid) or (name and pinName and pinName:lower() == name:lower()) then
      return i, pins[i]
    end
  end
  return nil
end

function GF.RemovePriorityPin(value)
  local pins = Pins(false)
  local index = tonumber(value)
  if not index and type(value) == "string" then
    index = GF.FindPriorityPin(value, value)
  end
  index = index and floor(index + 0.5) or nil
  if not index or index < 1 or index > #pins then return false, "NOT_PINNED" end
  local removed = table_remove(pins, index)
  RequestRefresh("pin-removed")
  return true, "REMOVED", removed and removed.name
end

function GF.MovePriorityPin(index, delta)
  local pins = Pins(false)
  index = floor((tonumber(index) or 0) + 0.5)
  delta = floor((tonumber(delta) or 0) + 0.5)
  local target = index + delta
  if index < 1 or index > #pins or target < 1 or target > #pins or target == index then return false end
  pins[index], pins[target] = pins[target], pins[index]
  RequestRefresh("pins-reordered")
  return true
end

function GF.ClearPriorityPins()
  local pins = Pins(false)
  if #pins == 0 then return false end
  wipe(pins)
  RequestRefresh("pins-cleared")
  return true
end

local function IsUnitForGroup(unit, groupType)
  unit = PlainString(unit)
  if groupType == "raid" then return unit and unit:match("^raid%d+$") ~= nil or false end
  if groupType == "party" then return unit == "player" or (unit and unit:match("^party[1-4]$") ~= nil) end
  return false
end

function GF.IsPriorityGroupUnit(unit)
  return IsUnitForGroup(unit, CurrentGroupType())
end

local function UnitRosterIdentity(unit)
  unit = PlainString(unit)
  local groupType = CurrentGroupType()
  if not IsUnitForGroup(unit, groupType) then return nil end
  local name
  if groupType == "raid" then
    local index = tonumber(unit:match("^raid(%d+)$"))
    name = index and GetRaidRosterInfo and GetRaidRosterInfo(index) or nil
  else
    name = PartyUnitName(unit)
  end
  name = PlainString(name)
  if not name then return nil end
  local guid = UnitGUID and UnitGUID(unit) or nil
  guid = PlainString(guid)
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
  if issecretvalue(role) == true then role = nil end
  return guid, name, role
end

function GF.TogglePriorityUnit(unit)
  if not CurrentGroupType() then return false, "NOT_IN_GROUP" end
  local guid, name, role = UnitRosterIdentity(unit)
  if not name then return false, "INVALID_UNIT" end
  local conf = PriorityConf()
  local index = GF.FindPriorityPin(guid, name)
  if index then
    local ok = GF.RemovePriorityPin(index)
    if ok and conf and conf.autoTanks == true and role == "TANK" then
      return true, "REMOVED_AUTO_TANK", name
    end
    return ok, ok and "REMOVED" or "NOT_PINNED", name
  end

  local enabledNow = conf and conf.enabled ~= true
  if enabledNow then conf.enabled = true end
  if conf and conf.autoTanks == true and role == "TANK" then
    if enabledNow then
      RequestRefresh("hotkey-enabled")
      return true, "ADDED_AUTO_TANK", name
    end
    return false, "AUTO_TANK", name
  end

  local _, resolvedCount = GF.ResolvePrioritySelection()
  local limit = ClampMaxFrames(conf and conf.maxFrames)
  if resolvedCount >= limit then
    if enabledNow then RequestRefresh("hotkey-enabled") end
    return false, "FULL", name, limit
  end

  local pins = Pins(true)
  if #pins >= MAX_STORED_PINS then
    if enabledNow then RequestRefresh("hotkey-enabled") end
    return false, "PIN_LIMIT", name, MAX_STORED_PINS
  end
  pins[#pins + 1] = { guid = guid, name = name }
  RequestRefresh("pin-added")
  return true, "ADDED", name
end

local hoveredUnit
local function FindHoveredFrame(frame, unit, kind)
  if hoveredUnit or (kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid") or not frame then return end
  if frame._msufGFIsPreviewFrame == true then return end
  if frame.IsShown and not frame:IsShown() then return end
  if frame.IsMouseOver and frame:IsMouseOver() then
    local candidate = unit or frame.MSUFUnitKey
    if GF.IsPriorityGroupUnit(candidate) then hoveredUnit = candidate; return true end
  end
end

function GF.GetHoveredPriorityUnit()
  hoveredUnit = nil
  local getFoci = _G.GetMouseFoci
  if type(getFoci) == "function" then
    local foci = getFoci()
    if type(foci) == "table" then
      for i = 1, #foci do
        local frame = foci[i]
        for _ = 1, 5 do
          if not frame then break end
          local shell = frame._msufSecureShell or frame
          local visual = shell._msufVisualFrame or shell
          local kind = visual and visual._msufGFKind
          if visual and visual._msufIsGroupFrame == true and visual._msufGFIsPreviewFrame ~= true
            and (kind == "party" or kind == "raid" or kind == "mythicraid") then
            local unit = PlainString(shell.GetAttribute and shell:GetAttribute("unit") or visual.MSUFUnitKey)
            if GF.IsPriorityGroupUnit(unit) then return unit end
          end
          frame = frame.GetParent and frame:GetParent() or nil
        end
      end
    end
  end
  if type(GF.ForEachFrame) == "function" then
    GF.ForEachFrame(FindHoveredFrame, false)
  end
  local unit = hoveredUnit
  hoveredUnit = nil
  unit = PlainString(unit)
  return GF.IsPriorityGroupUnit(unit) and unit or nil
end

local function Notify(code, name, limit)
  local message
  if code == "ADDED" then message = "Priority Frames: added " .. tostring(name)
  elseif code == "REMOVED" then message = "Priority Frames: removed " .. tostring(name)
  elseif code == "AUTO_TANK" then message = tostring(name) .. " is already included automatically as a tank."
  elseif code == "ADDED_AUTO_TANK" then message = "Priority Frames enabled; " .. tostring(name) .. " is included as a tank."
  elseif code == "REMOVED_AUTO_TANK" then message = "Manual pin removed; " .. tostring(name) .. " remains as an automatic tank."
  elseif code == "FULL" then message = "Priority Frames are full (" .. tostring(limit or MAX_PRIORITY_FRAMES) .. ")."
  elseif code == "NOT_IN_GROUP" then message = "Join a party or raid before selecting a Priority Frame."
  elseif code == "INVALID_UNIT" then message = "Hover an MSUF Party, Raid, or Priority frame, then press the Priority Frames key."
  elseif code == "PIN_LIMIT" then message = "The saved Priority Frames list is full."
  else message = "Hover an MSUF Party, Raid, or Priority frame, then press the Priority Frames key." end
  local errors = _G.UIErrorsFrame
  if errors and type(errors.AddMessage) == "function" then
    local success = code == "ADDED" or code == "REMOVED" or code == "ADDED_AUTO_TANK" or code == "REMOVED_AUTO_TANK"
    errors:AddMessage(message, success and 0.3 or 1, success and 1 or 0.82, 0.2, 1)
  elseif _G.print then
    _G.print("|cff60a5ffMSUF:|r " .. message)
  end
end

function GF.ToggleHoveredPriorityFrame()
  local unit = GF.GetHoveredPriorityUnit()
  local ok, code, name, limit = GF.TogglePriorityUnit(unit)
  Notify(code, name, limit)
  return ok, code
end
GF.TogglePriorityMouseover = GF.ToggleHoveredPriorityFrame

function GF.RequestPriorityApply(_, reason)
  return RequestRefresh(reason or "menu")
end

function GF.SetPriorityOption(key, value)
  local conf = PriorityConf()
  if not conf then return false end
  if key == "enabled" or key == "autoTanks" then
    value = value == true
  elseif key == "maxFrames" then
    value = ClampMaxFrames(value)
  elseif key == "growth" then
    if value ~= "UP" and value ~= "DOWN" and value ~= "LEFT" and value ~= "RIGHT" then return false end
  elseif key == "spacing" then
    value = floor((tonumber(value) or 2) + 0.5)
    if value < 0 then value = 0 elseif value > 40 then value = 40 end
  elseif key == "anchorMode" then
    if value ~= "RAID_RIGHT" and value ~= "RAID_LEFT" and value ~= "RAID_TOP"
      and value ~= "RAID_BOTTOM" and value ~= "FREE" then return false end
  elseif key == "point" or key == "relativePoint" then
    local valid = value == "CENTER" or value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT"
      or value == "TOPLEFT" or value == "TOPRIGHT" or value == "BOTTOMLEFT" or value == "BOTTOMRIGHT"
    if not valid then return false end
  elseif key == "attachGap" then
    value = floor((tonumber(value) or 8) + 0.5)
    if value < 0 then value = 0 elseif value > 100 then value = 100 end
  elseif key == "attachOffset" or key == "offsetX" or key == "offsetY" then
    value = floor((tonumber(value) or 0) + 0.5)
    if value < -4000 then value = -4000 elseif value > 4000 then value = 4000 end
  else
    return false
  end
  if conf[key] == value then return true end
  conf[key] = value
  RequestRefresh("option-" .. key)
  return true
end

ExportPublic("MSUF_GF_ToggleHoveredPriority", function()
  return GF.ToggleHoveredPriorityFrame()
end)
ExportPublic("MSUF_GF_GetPriorityPins", function()
  return GF.GetPriorityPins()
end)
