--- UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua
--- Secure party/raid header creation and anchoring.
---
--- This file owns protected header frames, anchor/mover geometry, sorting/group
--- attributes, and header retirement. It must avoid mutating protected header
--- attributes in combat; Runtime handles deferral and calls back here afterward.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF

local CreateFrame = CreateFrame
local UIParent = UIParent
local PetBattleFrameHider = PetBattleFrameHider
local InCombatLockdown = InCombatLockdown
local abs = math.abs
local floor = math.floor
local tonumber = tonumber
local type = type
local table_insert = table.insert
local table_concat = table.concat
local table_sort = table.sort
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitClass = UnitClass
local Secrets = MSUF.Secrets or {}
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local issecretvalue = _G.issecretvalue or function(_) return false end
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}
GF._headerPool = GF._headerPool or {}
GF._lastKnownLayoutCounts = GF._lastKnownLayoutCounts or {}

local NIL_ATTR = {}
local BORDER_EDGE_KEYS = { "top", "bottom", "left", "right" }

local IsUnitToken = UF and UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local function LiveGroupKind()
  if type(GF.GetLiveGroupKind) == "function" then return GF.GetLiveGroupKind() end
  if IsInRaid and IsInRaid() then
    return type(GF.GetLiveRaidKind) == "function" and GF.GetLiveRaidKind() or "raid"
  end
  if IsInGroup and IsInGroup() then return "party" end
  return nil
end

local VALID_POINTS = {
  CENTER = true,
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

local VALID_ROLES = {
  TANK = true,
  HEALER = true,
  DAMAGER = true,
  NONE = true,
}

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function ResolvePetBattleFrameHider()
  if UF and UF.GetPetBattleFrameHider then
    return UF.GetPetBattleFrameHider()
  end
  return MSUF._petBattleFrameHider or PetBattleFrameHider or UIParent
end

--- Retiring a header must also untrack its children so Adapter does not keep
--- stale unit indexes for frames hidden by a secure header rebuild.
local function SuspendHeaderChildren(...)
  for i = 1, select("#", ...) do
    local child = select(i, ...)
    if child then
      if GF.UntrackFrame then GF.UntrackFrame(child) end
      if child.Hide then child:Hide() end
    end
  end
end

local function RetireHeader(header)
  if not header then return end
  if header.GetChildren then
    SuspendHeaderChildren(header:GetChildren())
  end
  if header.Hide then header:Hide() end
end

function GF.RetireHeader(key)
  if not (GF.headers and key) then return false end
  local header = GF.headers[key]
  if not header then
    if key == "priority" then
      local anchor = GF.anchors and GF.anchors.priority
      if anchor and anchor.Hide then anchor:Hide() end
    end
    return false
  end
  RetireHeader(header)
  if key == "priority" and header.UnregisterAllEvents then
    -- SecureGroupHeaderTemplate otherwise retains its two Blizzard roster
    -- events while pooled. Priority Frames promise a truly inert disabled state.
    header:UnregisterAllEvents()
    header._msufGFPriorityHeaderEvents = nil
  end
  GF._headerPool[key] = header
  GF.headers[key] = nil
  if key == "priority" then
    local anchor = GF.anchors and GF.anchors.priority
    if anchor and anchor.Hide then anchor:Hide() end
  end
  return true
end

local function Defer(reason)
  if GF.DeferGroupRuntime then
    GF.DeferGroupRuntime(reason)
  else
    GF._pendingGroupRuntime = reason or true
  end
end

local function BeginHeaderLayoutRebind(header)
  local begin = GF.BeginHeaderLayoutRebind
  return type(begin) == "function" and begin(header) == true
end

local function EndHeaderLayoutRebind(header, active)
  if active ~= true then return end
  local finish = GF.EndHeaderLayoutRebind
  if type(finish) == "function" then finish(header) end
end

local function HeaderName(key)
  if key == "party" then
    GF._partyHeaderSerial = (GF._partyHeaderSerial or 0) + 1
    return "MSUF_GF_PartyHeader" .. GF._partyHeaderSerial
  elseif key == "priority" then
    GF._priorityHeaderSerial = (GF._priorityHeaderSerial or 0) + 1
    return "MSUF_GF_PriorityHeader" .. GF._priorityHeaderSerial
  end
  GF._raidHeaderSerial = (GF._raidHeaderSerial or 0) + 1
  return "MSUF_GF_RaidHeader" .. GF._raidHeaderSerial
end

local function AnchorName(key)
  if key == "party" then return "MSUF_GF_PartyAnchor" end
  if key == "priority" then return "MSUF_GF_PriorityAnchor" end
  return "MSUF_GF_RaidAnchor"
end

local UNKNOWN_RAID_LAYOUT_COUNT = 10

local function IsRaidLikeKind(kind)
  return kind == "raid" or kind == "mythicraid"
end

local function RememberLayoutCount(kind, count)
  count = floor((tonumber(count) or 0) + 0.5)
  if count < 1 then return 0 end
  if count > 40 then count = 40 end
  GF._lastKnownLayoutCounts[kind] = count
  return count
end

local function UnknownRaidLayoutCount(kind)
  local count = GF._lastKnownLayoutCounts and GF._lastKnownLayoutCounts[kind]
  if count and count > 0 and count <= UNKNOWN_RAID_LAYOUT_COUNT then
    return count
  end
  return UNKNOWN_RAID_LAYOUT_COUNT
end

--- Header size estimates use live roster counts when available, otherwise the
--- last known count. This keeps preview/mover geometry stable during login.
local function ConfiguredCount(kind, conf)
  if kind == "party" then
    if GetNumSubgroupMembers then
      local n = GetNumSubgroupMembers() or 0
      if n > 0 and conf.showPlayer ~= false then
        n = n + 1
      elseif n == 0 and conf.showSolo == true and conf.showPlayer ~= false then
        n = 1
      end
      if n > 0 then return RememberLayoutCount(kind, n) end
    end
    return 5
  end
  if GetNumGroupMembers then
    local n = GetNumGroupMembers() or 0
    if n > 0 then return RememberLayoutCount(kind, n) end
  end
  return UnknownRaidLayoutCount(kind)
end

function GF.GetLiveLayoutCount(kind)
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  return ConfiguredCount(kind, conf)
end

local function LayoutParts(kind, conf, configuredCount)
  local w, h, spacing = 80, 32, 1
  if GF.GetScaledFrameMetrics then
    w, h, spacing = GF.GetScaledFrameMetrics(kind)
  else
    w, h, spacing = conf.width or w, conf.height or h, conf.spacing or spacing
  end
  local count = configuredCount or ConfiguredCount(kind, conf)
  local dx, dy, totalW, totalH = 0, 0, w, h
  if GF.GetGridMetrics then
    dx, dy, totalW, totalH = GF.GetGridMetrics(kind, count)
  end
  return w, h, spacing, dx or 0, dy or 0, totalW or w, totalH or h, count
end

function GF.ResolveAnchorFrame(conf, owner)
  local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
  if name == "UI_Parent" then name = "UIParent" end
  if type(name) ~= "string" or name == "" or name == "FREE" or name == "UIParent" or name == "WorldFrame" then
    return UIParent, nil, nil
  end
  local factory = UF and UF.Factory
  local resolved, missing
  if factory and type(factory.ResolveNamedAnchor) == "function" then
    resolved, missing = factory.ResolveNamedAnchor(name)
  else
    resolved = (UF and UF.frames and UF.frames[name]) or _G[name]
    if not resolved then missing = name end
  end
  if not resolved then return UIParent, missing or name, nil end
  if resolved == owner
    or (factory and type(factory.AnchorWouldCreateCycle) == "function"
      and factory.AnchorWouldCreateCycle(owner, resolved)) then
    return UIParent, nil, name
  end
  return resolved, nil, nil
end

local function AnchorPoint(conf)
  if GF.GetAnchorPoint then return GF.GetAnchorPoint(conf) end
  local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
  if not VALID_POINTS[point] then
    point = "CENTER"
  end
  return point
end

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function ResolveAnchorPoint(kind, conf, parent)
  if GF.ResolveAnchorPoint then return GF.ResolveAnchorPoint(kind, conf, parent) end
  local point = AnchorPoint(conf)
  return point, point
end

local function PointFraction(point)
  local fx, fy
  if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
    fx = 0
  elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
    fx = 1
  else
    fx = 0.5
  end
  if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
    fy = 0
  elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
    fy = 1
  else
    fy = 0.5
  end
  return fx, fy
end

local function ClampBoxAxis(minEdge, maxEdge, screenMax)
  local size = (maxEdge or 0) - (minEdge or 0)
  if size <= 0 or not (screenMax and screenMax > 0) then
    return 0
  end
  if size <= screenMax then
    if minEdge < 0 then return -minEdge end
    if maxEdge > screenMax then return screenMax - maxEdge end
    return 0
  end
  if minEdge > 0 then return -minEdge end
  if maxEdge < screenMax then return screenMax - maxEdge end
  return 0
end

--- Keep anchor frames on screen when possible; child layout remains relative to
--- the anchor so saved offsets stay meaningful.
local function ClampAnchorOnScreen(anchor, point, relativePoint, parent, offsetX, offsetY, totalW, totalH)
  if not (anchor and parent and parent.GetLeft and UIParent and UIParent.GetWidth) then
    return
  end
  local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
  if not (screenW and screenH and screenW > 0 and screenH > 0) then
    return
  end
  local pLeft, pRight = parent:GetLeft(), parent:GetRight()
  local pBottom, pTop = parent:GetBottom(), parent:GetTop()
  if not (pLeft and pRight and pBottom and pTop) then
    return
  end
  local fx, fy = PointFraction(point)
  local rfx, rfy = PointFraction(relativePoint)
  local px = pLeft + (pRight - pLeft) * rfx + (offsetX or 0)
  local py = pBottom + (pTop - pBottom) * rfy + (offsetY or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local right = left + boxW
  local top = bottom + boxH

  local dx = ClampBoxAxis(left, right, screenW)
  local dy = ClampBoxAxis(bottom, top, screenH)
  if dx == 0 and dy == 0 then
    return
  end
  anchor:ClearAllPoints()
  anchor:SetPoint(point, parent, relativePoint, (offsetX or 0) + dx, (offsetY or 0) + dy)
end

local function EnsureAnchor(key, conf, totalW, totalH)
  local anchor = GF.anchors[key]
  local desiredParent = ResolvePetBattleFrameHider()
  if not anchor then
    anchor = CreateFrame("Frame", AnchorName(key), desiredParent)
    anchor:EnableMouse(false)
    GF.anchors[key] = anchor
  elseif anchor.GetParent and anchor.SetParent and anchor:GetParent() ~= desiredParent then
    anchor:SetParent(desiredParent)
  end
  anchor._msufOwnedAnchorRoot = true
  if key == "priority" and anchor.SetClampedToScreen and anchor._msufScreenClampEnabled ~= true then
    anchor:SetClampedToScreen(true)
    anchor._msufScreenClampEnabled = true
  end
  anchor:SetSize(totalW, totalH)
  anchor:ClearAllPoints()
  local parent, missingAnchorName, rejectedAnchorName = GF.ResolveAnchorFrame(conf, anchor)
  anchor._msufMissingAnchorName = missingAnchorName
  anchor._msufRejectedAnchorName = rejectedAnchorName
  if missingAnchorName and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
    _G.MSUF_ScheduleLateAnchorReanchor()
  end
  anchor:Show()
  -- The Anchor Point owns both sides of a group anchor; resolving it can retire
  -- a legacy relativePoint into the offsets, so read those afterwards.
  local point, relativePoint = ResolveAnchorPoint(key, conf, parent)
  local offsetX, offsetY = conf.offsetX or 0, conf.offsetY or 0
  if key ~= "priority" and GF.ConfigureAnchorPointScreenClamp then
    GF.ConfigureAnchorPointScreenClamp(anchor, point, totalW, totalH)
  end
  -- Resolve, apply and clamp in the logical anchor's coordinate space. An
  -- external parent stays live so the header follows provider movement out of
  -- combat; the Factory combat-edge freeze severs the link while a fight
  -- lasts.
  anchor:SetPoint(point, parent, relativePoint, offsetX, offsetY)
  if key == "priority" then
    ClampAnchorOnScreen(anchor, point, relativePoint, parent, offsetX, offsetY, totalW, totalH)
  end
  local ownedParent = parent == UIParent or (parent and parent._msufOwnedAnchorRoot == true)
  local resolvable = ownedParent or anchor:GetCenter() ~= nil
  if not resolvable then
    -- Never leave a secure group header attached to a provider whose geometry
    -- is temporarily unreadable: it would render nowhere. Keep the legacy
    -- offsets on UIParent and let the bounded late-anchor pass retry once the
    -- provider has settled.
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relativePoint, offsetX, offsetY)
    if parent ~= UIParent and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
      _G.MSUF_ScheduleLateAnchorReanchor()
    end
  end
  anchor._msufStableExternalAnchor = (not ownedParent and resolvable) and parent or nil
  anchor._msufExternalAnchorFrozen = nil
  return anchor
end

local function GrowthAttributes(growth, spacing, groupGrowth)
  if growth == "UP" then
    return "BOTTOM", 0, spacing, groupGrowth == "LEFT" and "RIGHT" or "LEFT"
  elseif growth == "RIGHT" then
    return "LEFT", spacing, 0, groupGrowth == "UP" and "BOTTOM" or "TOP"
  elseif growth == "LEFT" then
    return "RIGHT", -spacing, 0, groupGrowth == "UP" and "BOTTOM" or "TOP"
  end
  return "TOP", 0, -spacing, groupGrowth == "LEFT" and "RIGHT" or "LEFT"
end

local function AttrChanged(header, key, value)
  local cache = header and header._msufGFAttrCache
  if not cache then
    return true
  end
  local normalized = value == nil and NIL_ATTR or value
  return cache[key] ~= normalized
end

local function SetAttrIfChanged(header, key, value)
  local cache = header._msufGFAttrCache
  if not cache then
    cache = {}
    header._msufGFAttrCache = cache
  end
  local normalized = value == nil and NIL_ATTR or value
  if cache[key] == normalized then
    return false
  end
  header:SetAttribute(key, value)
  cache[key] = normalized
  return true
end

--- Blizzard's SecureGroupHeader reuses active children and adds their new
--- SetPoint anchors without clearing the previous anchor topology. Reset only
--- when point names or the configured row/column topology changes so pooled/live headers
--- cannot retain stale TOP/BOTTOM or LEFT/RIGHT constraints.
local function ResetManagedChildAnchors(header)
  if not (header and header.GetAttribute) then return end
  for index = 1, 40 do
    local child = header:GetAttribute("child" .. index)
    if not child then return end
    if child.ClearAllPoints then child:ClearAllPoints() end
  end
end

local function ClampInt(value, fallback, minValue, maxValue)
  value = floor((tonumber(value) or fallback or minValue or 1) + 0.5)
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function PreservedRaidGroupLimit(conf)
  if not (conf and conf.preserveRaidGroups == true) then return nil end
  return ClampInt(conf.maxColumns, 8, 1, 8)
end

local function RaidGroupingOrder(conf)
  local limit = PreservedRaidGroupLimit(conf)
  if not limit or limit >= 8 then
    return "1,2,3,4,5,6,7,8"
  end
  local out = {}
  for i = 1, limit do
    out[#out + 1] = tostring(i)
  end
  return table_concat(out, ",")
end

local function RequiredHeaderColumns(kind, conf, count)
  if kind == "party" then return 1 end
  count = floor((tonumber(count) or 0) + 0.5)
  if count < 1 then return 1 end
  if conf and conf.preserveRaidGroups == true then
    local groups = floor(((count + 4) / 5))
    local maxGroups = PreservedRaidGroupLimit(conf) or 8
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    if groups > maxGroups then groups = maxGroups end
    local upc = ClampInt(conf and conf.unitsPerColumn, 5, 1, 40)
    local primary = upc < 5 and upc or 5
    local blockColumns = floor(((5 + primary - 1) / primary))
    local columns = groups * blockColumns
    if columns < 1 then columns = 1 elseif columns > 40 then columns = 40 end
    return columns
  end
  local upc = ClampInt(conf and conf.unitsPerColumn, 5, 1, 40)
  local maxColumns = ClampInt(conf and conf.maxColumns, 8, 1, 40)
  local columns = floor(((count + upc - 1) / upc))
  if columns < 1 then columns = 1 elseif columns > 40 then columns = 40 end
  if columns > maxColumns then columns = maxColumns end
  return columns
end

local function RoleOrder(conf)
  local source = type(conf.roleOrder) == "string" and conf.roleOrder or "TANK,HEALER,DAMAGER"
  local out, seen = {}, {}
  for role in source:gmatch("[^,%s]+") do
    role = role:upper()
    if role == "DPS" or role == "MELEE" or role == "RANGED" then
      role = "DAMAGER"
    end
    if VALID_ROLES[role] and not seen[role] then
      seen[role] = true
      table_insert(out, role)
    end
  end
  if not seen.TANK then table_insert(out, "TANK") end
  if not seen.HEALER then table_insert(out, "HEALER") end
  if not seen.DAMAGER then table_insert(out, "DAMAGER") end
  if not seen.NONE then table_insert(out, "NONE") end
  return table_concat(out, ",")
end

local function RolePriority(conf)
  local priority = {}
  local order = RoleOrder(conf)
  local index = 0
  for role in order:gmatch("[^,%s]+") do
    if not priority[role] then
      index = index + 1
      priority[role] = index
    end
  end
  return priority
end

local function ResolveGroupFilter(conf)
  local value = conf and conf.groupFilter
  local groupLimit = PreservedRaidGroupLimit(conf)
  if type(value) == "string" then
    return value ~= "" and value or nil
  elseif type(value) == "table" then
    local out = {}
    for i = 1, 8 do
      if (not groupLimit or i <= groupLimit) and (value[i] == true or value[tostring(i)] == true) then
        out[#out + 1] = tostring(i)
      end
    end
    if #out > 0 and (#out < 8 or groupLimit) then
      return table_concat(out, ",")
    end
  elseif groupLimit and groupLimit < 8 then
    local out = {}
    for i = 1, groupLimit do
      out[#out + 1] = tostring(i)
    end
    return table_concat(out, ",")
  end
  return nil
end

local function GroupFilterAllows(conf, groupIndex, classFile, role)
  local groupLimit = PreservedRaidGroupLimit(conf)
  groupIndex = tonumber(groupIndex)
  if groupLimit and groupIndex and groupIndex > groupLimit then
    return false
  end
  local filter = conf and conf.groupFilter
  if type(filter) == "table" then
    local value = filter[groupIndex]
    if value == nil then
      value = filter[tostring(groupIndex)]
    end
    return value ~= false
  elseif type(filter) == "string" and filter ~= "" then
    local wanted = tostring(groupIndex)
    classFile = type(classFile) == "string" and classFile:upper() or nil
    role = type(role) == "string" and role:upper() or nil
    if role == "DPS" then role = "DAMAGER" end
    for token in filter:gmatch("[^,]+") do
      token = token:match("^%s*(.-)%s*$"):upper()
      if token == wanted or token == classFile or token == role or (token == "DPS" and role == "DAMAGER") then
        return true
      end
    end
    return false
  end
  return true
end

local function UnitFullName(unit)
  if not (unit and UnitName) then return nil end
  local name, realm = UnitName(unit)
  if not name or name == "" then
    return nil
  end
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

local function UnitRole(unit)
  local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or nil
  if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
    return role
  end
  return "DAMAGER"
end

local function UnitClassFile(unit)
  if not (UnitClass and unit) then return nil end
  local _, fileName = UnitClass(unit)
  return fileName
end

local function IsPlayerUnit(unit)
  if not IsUnitToken(unit) then
    return false
  end
  if unit == "player" then
    return true
  end
  if UnitGUID then
    local guid = UnitGUID(unit)
    local playerGuid = UnitGUID("player")
    if issecretvalue(guid) == true or issecretvalue(playerGuid) == true then
      return false
    end
    return guid ~= nil and guid == playerGuid
  end
  return false
end

local function AddNameListEntry(entries, unit, index, conf, raidIndex)
  local name, subgroup, classFile, role
  if raidIndex then
    if not GetRaidRosterInfo then return false end
    -- SecureGroupHeader_Update compares nameList entries against the exact name
    -- returned by GetRaidRosterInfo(). Use that same authoritative snapshot:
    -- UnitExists/UnitName can lag one roster dispatch and must never make a
    -- complete raid header silently publish a partial NAMELIST.
    local assignedRole
    name, _, subgroup, _, _, classFile, _, _, _, _, _, assignedRole = GetRaidRosterInfo(raidIndex)
    if issecretvalue(name) == true or type(name) ~= "string" or name == "" then return false end
    role = assignedRole == "TANK" or assignedRole == "HEALER" or assignedRole == "DAMAGER"
      and assignedRole or UnitRole(unit)
  else
    if UnitMissing(unit) then return false end
    role = UnitRole(unit)
    classFile = UnitClassFile(unit)
    name = UnitFullName(unit)
    if not name then return false end
  end
  if subgroup and not GroupFilterAllows(conf, subgroup, classFile, role) then return true end
  entries[#entries + 1] = {
    name = name,
    role = role,
    index = index or 0,
    player = IsPlayerUnit(unit),
    group = subgroup or 0,
  }
  return true
end

local function BuildPlayerFirstRoleNameList(key, kind, conf)
  if conf.playerFirstInRole ~= true then
    return nil
  end
  local entries = {}
  if kind == "party" then
    local liveKind = LiveGroupKind()
    if liveKind == "party" then
      if conf.showPlayer ~= false then
        AddNameListEntry(entries, "player", 0, conf)
      end
      for i = 1, 4 do
        AddNameListEntry(entries, "party" .. i, i, conf)
      end
    elseif liveKind == nil and conf.showSolo == true and conf.showPlayer ~= false then
      AddNameListEntry(entries, "player", 0, conf)
    end
  else
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
      AddNameListEntry(entries, "raid" .. i, i, conf, i)
    end
  end
  if #entries == 0 then
    return nil
  end

  local priority = RolePriority(conf)
  table_sort(entries, function(a, b)
    local ar = priority[a.role] or 999
    local br = priority[b.role] or 999
    if ar ~= br then
      return ar < br
    end
    if a.player ~= b.player then
      return a.player == true
    end
    return (a.index or 0) < (b.index or 0)
  end)

  local names, seen = {}, {}
  for i = 1, #entries do
    local name = entries[i].name
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    return nil
  end
  return table_concat(names, ",")
end

local function EntryRolePriority(entry, priority)
  return priority and priority[entry and entry.role] or 999
end

local function BuildRaidFreezeNameList(kind, conf, mode, descending)
  if not IsRaidLikeKind(kind) then
    return nil
  end
  local count = GetNumGroupMembers and GetNumGroupMembers() or 0
  if count <= 0 then
    return nil
  end

  local entries = {}
  local rosterComplete = true
  for i = 1, count do
    if AddNameListEntry(entries, "raid" .. i, i, conf, i) ~= true then
      rosterComplete = false
    end
  end
  -- A partial nameList is a filter, not merely an ordering hint: Blizzard will
  -- omit every roster name absent from it. Fall back to its native complete
  -- roster path until all authoritative names are available.
  if not rosterComplete or #entries == 0 then
    return nil
  end

  local priority = RolePriority(conf)
  local function SortBefore(a, b)
    if mode == "NAME" and a.name ~= b.name then
      return a.name < b.name
    elseif mode == "ROLE" then
      local ar, br = EntryRolePriority(a, priority), EntryRolePriority(b, priority)
      if ar ~= br then return ar < br end
      if conf.playerFirstInRole == true and a.player ~= b.player then return a.player == true end
    elseif mode == "GROUP" or mode == "GROUP_ROLE" then
      local ag, bg = a.group or 0, b.group or 0
      if ag ~= bg then return ag < bg end
      if mode == "GROUP_ROLE" then
        local ar, br = EntryRolePriority(a, priority), EntryRolePriority(b, priority)
        if ar ~= br then return ar < br end
        if conf.playerFirstInRole == true and a.player ~= b.player then return a.player == true end
      end
    end
    return (a.index or 0) < (b.index or 0)
  end
  table_sort(entries, function(a, b)
    if descending == true then
      return SortBefore(b, a)
    end
    return SortBefore(a, b)
  end)

  local names, seen = {}, {}
  for i = 1, #entries do
    local name = entries[i].name
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    return nil
  end
  return table_concat(names, ",")
end

local function ResolveSortMode(key, conf)
  local mode = conf.sortMode
  if mode ~= "INDEX" and mode ~= "NAME" and mode ~= "ROLE" and mode ~= "GROUP" and mode ~= "GROUP_ROLE" then
    if key ~= "party" and conf.preserveRaidGroups == true then
      mode = "GROUP"
    elseif conf.sortByRole == true then
      mode = "ROLE"
    elseif conf.sortByName == true then
      mode = "NAME"
    else
      mode = "INDEX"
    end
  end
  if key == "party" and (mode == "GROUP" or mode == "GROUP_ROLE") then
    mode = conf.sortByRole == true and "ROLE" or "INDEX"
  end
  return mode
end

local function BuildSortState(key, kind, conf)
  local mode = ResolveSortMode(key, conf)
  local sortMethod = "INDEX"
  local groupBy, groupingOrder, nameList

  if key ~= "party" then
    nameList = BuildRaidFreezeNameList(kind, conf, mode, conf.sortDescending == true)
    if nameList then
      sortMethod = "NAMELIST"
    end
  elseif mode == "ROLE" and conf.playerFirstInRole == true then
    nameList = BuildPlayerFirstRoleNameList(key, kind, conf)
    if nameList then
      sortMethod = "NAMELIST"
    end
  end

  if nameList then
    groupBy = nil
    groupingOrder = nil
  elseif mode == "NAME" then
    sortMethod = "NAME"
  elseif mode == "ROLE" then
    groupBy = "ASSIGNEDROLE"
    groupingOrder = RoleOrder(conf)
  elseif key ~= "party" and (mode == "GROUP" or mode == "GROUP_ROLE") then
    groupBy = "GROUP"
    groupingOrder = RaidGroupingOrder(conf)
  end

  return {
    mode = mode,
    sortMethod = sortMethod,
    sortDir = (nameList and key ~= "party") and "ASC" or (conf.sortDescending == true and "DESC" or "ASC"),
    groupBy = groupBy,
    groupingOrder = groupingOrder,
    nameList = nameList,
    playerFirst = conf.playerFirstInRole == true,
  }
end

local function SortStateChanged(header, state)
  return AttrChanged(header, "sortMethod", state.sortMethod)
    or AttrChanged(header, "sortDir", state.sortDir)
    or AttrChanged(header, "groupBy", state.groupBy)
    or AttrChanged(header, "groupingOrder", state.groupingOrder)
    or AttrChanged(header, "nameList", state.nameList)
    or AttrChanged(header, "_msufSortMode", state.mode)
    or AttrChanged(header, "_msufPlayerFirstInRole", state.playerFirst)
end

local function ApplySortAttributes(header, state)
  local changed = false
  if state.sortMethod == "NAMELIST" then
    changed = SetAttrIfChanged(header, "nameList", state.nameList) or changed
    changed = SetAttrIfChanged(header, "sortMethod", "NAMELIST") or changed
    changed = SetAttrIfChanged(header, "sortDir", state.sortDir) or changed
    changed = SetAttrIfChanged(header, "groupBy", nil) or changed
    changed = SetAttrIfChanged(header, "groupingOrder", nil) or changed
  else
    changed = SetAttrIfChanged(header, "nameList", nil) or changed
    changed = SetAttrIfChanged(header, "sortMethod", state.sortMethod) or changed
    changed = SetAttrIfChanged(header, "sortDir", state.sortDir) or changed
    changed = SetAttrIfChanged(header, "groupBy", state.groupBy) or changed
    changed = SetAttrIfChanged(header, "groupingOrder", state.groupingOrder) or changed
  end
  changed = SetAttrIfChanged(header, "_msufSortMode", state.mode) or changed
  changed = SetAttrIfChanged(header, "_msufPlayerFirstInRole", state.playerFirst) or changed
  return changed
end

local SECURE_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate, PingableUnitFrameTemplate"
local SECURE_AURA_CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"
local SECURE_INIT_VERSION = 7

local function ButtonTemplate()
  if UF and type(UF.GetSecureHeaderUnitButtonTemplate) == "function" then
    return UF.GetSecureHeaderUnitButtonTemplate()
  end
  return SECURE_UNIT_BUTTON_TEMPLATE
end

local _initCfgNonce = 0
local function BuildInitialConfigFunction(w, h)
  _initCfgNonce = _initCfgNonce + 1
  return string.format([[
self:ClearAllPoints()
self:SetWidth(%.3f)
self:SetHeight(%.3f)
self:SetAttribute('type1', nil)
self:SetAttribute('*type1', 'target')
self:SetAttribute('type2', nil)
self:SetAttribute('*type2', 'togglemenu')
self:SetAttribute('*clickbutton2', nil)
self:SetAttribute('toggleForVehicle', true)
self:SetAttribute('ping-receiver', true)
-- nonce %d
]], w, h, _initCfgNonce)
end

--- Draw or hide the group block border on `host`. Live headers pass their
--- anchor, the preview passes its own container, so both surfaces share one
--- geometry implementation instead of drifting apart. `enabled` lets a caller
--- force the border off while another surface owns the block.
local function ApplyGroupBorder(host, conf, enabled)
  if not host then return false end
  if enabled == nil then
    enabled = conf and conf.groupBorderEnabled == true
  end
  if type(conf) ~= "table" then enabled = false end
  if enabled ~= true then
    if host.MSUFGFGroupBorder then
      for _, edge in pairs(host.MSUFGFGroupBorder) do edge:Hide() end
    end
    local rounded = _G.MSUF_RoundedUF_OnGroupBlockBorder
    if rounded then rounded(host, conf, false) end
    return false
  end
  local edges = host.MSUFGFGroupBorder or {}
  host.MSUFGFGroupBorder = edges
  local size, pad = conf.groupBorderSize or 1, conf.groupBorderPadding or 2
  local r, g, b, a = conf.groupBorderR or 0.38, conf.groupBorderG or 0.68, conf.groupBorderB or 1, conf.groupBorderA or 0.95
  for i = 1, #BORDER_EDGE_KEYS do
    local key = BORDER_EDGE_KEYS[i]
    local edge = edges[key]
    if not edge then
      edge = host:CreateTexture(nil, "OVERLAY")
      edges[key] = edge
    end
    edge:SetColorTexture(r, g, b, a)
    edge:ClearAllPoints()
    if key == "top" then
      edge:SetPoint("TOPLEFT", host, "TOPLEFT", -pad, pad)
      edge:SetPoint("TOPRIGHT", host, "TOPRIGHT", pad, pad)
      edge:SetHeight(size)
    elseif key == "bottom" then
      edge:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -pad, -pad)
      edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", pad, -pad)
      edge:SetHeight(size)
    elseif key == "left" then
      edge:SetPoint("TOPLEFT", host, "TOPLEFT", -pad, pad)
      edge:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -pad, -pad)
      edge:SetWidth(size)
    else
      edge:SetPoint("TOPRIGHT", host, "TOPRIGHT", pad, pad)
      edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", pad, -pad)
      edge:SetWidth(size)
    end
    edge:Show()
  end
  local rounded = _G.MSUF_RoundedUF_OnGroupBlockBorder
  if rounded and rounded(host, conf, true) then
    for _, edge in pairs(edges) do edge:Hide() end
  end
  return true
end

GF.ApplyGroupBorderToFrame = ApplyGroupBorder

--- A preview replaces the whole block for its kind, and the live anchor keeps
--- its last position/size while the header is retired. Let the preview own the
--- border for that kind so the two do not draw two boxes at once.
local function GroupBorderPreviewOwned(anchorKind)
  if _G.MSUF_UnitEditModeActive == true then return false end
  local active = GF._previewActive
  if not active then return false end
  if anchorKind == "party" then return active.party == true end
  return active.raid == true or active.mythicraid == true
end

local function GroupBorderScopeActive(anchorKind, conf)
  if type(conf) ~= "table" or conf.enabled ~= true then return false end
  local liveKind = LiveGroupKind()
  if anchorKind == "party" then
    if liveKind == "party" then return true end
    return liveKind == nil and conf.showSolo == true
  end
  if anchorKind == "raid" or anchorKind == "mythicraid" then
    return liveKind == anchorKind
  end
  return false
end

local function ApplyGroupBorderForKey(key)
  local anchor = GF.anchors and GF.anchors[key]
  if not anchor then return end
  local anchorKind = anchor._msufGFKind or (key == "party" and "party" or "raid")
  local conf = GF.GetConf and GF.GetConf(anchorKind) or {}
  local enabled = conf.groupBorderEnabled == true
    and GroupBorderScopeActive(anchorKind, conf)
    and not GroupBorderPreviewOwned(anchorKind)
  ApplyGroupBorder(anchor, conf, enabled)
end

function GF.ApplyGroupBorder(kind)
  if kind == "party" then
    ApplyGroupBorderForKey("party")
  elseif kind == "raid" or kind == "mythicraid" then
    ApplyGroupBorderForKey("raid")
  else
    ApplyGroupBorderForKey("party")
    ApplyGroupBorderForKey("raid")
  end
end

local function ConfigureHeader(header, key, kind, conf, w, h, spacing, layoutCount)
  local buttonTemplate = ButtonTemplate()
  local point, xOffset, yOffset, columnAnchor = GrowthAttributes(conf.growth, spacing, conf.groupGrowth)
  local upc = ClampInt(conf.unitsPerColumn, kind == "party" and 5 or 5, 1, 40)
  local requiredColumns = RequiredHeaderColumns(kind, conf, layoutCount)
  local columns = requiredColumns
  local initialWidth = floor((w or 80) + 0.5)
  local initialHeight = floor((h or 32) + 0.5)
  local sizeChanged = AttrChanged(header, "initial-width", initialWidth)
    or AttrChanged(header, "initial-height", initialHeight)
  local secureInitChanged = AttrChanged(header, "_msufSecureInitVersion", SECURE_INIT_VERSION)
  local initCfg = (sizeChanged or secureInitChanged) and BuildInitialConfigFunction(initialWidth, initialHeight) or nil
  local sortState = BuildSortState(key, kind, conf)
  local groupFilter = sortState.sortMethod == "NAMELIST" and nil or (key == "party" and nil or ResolveGroupFilter(conf))
  local childAnchorTopologyChanged = AttrChanged(header, "point", point)
    or AttrChanged(header, "columnAnchorPoint", columnAnchor)
    or AttrChanged(header, "unitsPerColumn", upc)
    or AttrChanged(header, "maxColumns", columns)
  local shouldHide = header.IsShown and header:IsShown()
    and (AttrChanged(header, "auraContainerTemplate", SECURE_AURA_CONTAINER_TEMPLATE)
      or AttrChanged(header, "template", buttonTemplate)
      or sizeChanged
      or AttrChanged(header, "xOffset", xOffset)
      or AttrChanged(header, "yOffset", yOffset)
      or AttrChanged(header, "columnSpacing", spacing)
      or childAnchorTopologyChanged
      or AttrChanged(header, "groupFilter", groupFilter)
      or secureInitChanged
      or SortStateChanged(header, sortState))

  if shouldHide then
    header:Hide()
  end
  if childAnchorTopologyChanged then
    ResetManagedChildAnchors(header)
  end

  local changed = false
  -- 12.1 can create AuraContainers for SecureGroupHeader children inside the
  -- restricted header environment. Birth one inert native owner for every
  -- party/raid child so Auras3 can adopt it without a Lua-side frame birth,
  -- including children added while combat lockdown is active.
  changed = SetAttrIfChanged(header, "auraContainerTemplate", SECURE_AURA_CONTAINER_TEMPLATE) or changed
  changed = SetAttrIfChanged(header, "template", buttonTemplate) or changed
  changed = SetAttrIfChanged(header, "templateType", "Button") or changed
  changed = SetAttrIfChanged(header, "initial-width", initialWidth) or changed
  changed = SetAttrIfChanged(header, "initial-height", initialHeight) or changed
  changed = SetAttrIfChanged(header, "_msufSecureInitVersion", SECURE_INIT_VERSION) or changed
  changed = SetAttrIfChanged(header, "oUF-headerType", "group") or changed
  if UF and type(UF.ForEachPingBindingAttribute) == "function" then
    UF.ForEachPingBindingAttribute(function(attribute, key)
      changed = SetAttrIfChanged(header, attribute, key) or changed
    end)
  end
  if initCfg then
    header:SetAttribute("initialConfigFunction", initCfg)
    changed = true
  end
  changed = SetAttrIfChanged(header, "showPlayer", conf.showPlayer ~= false) or changed
  changed = SetAttrIfChanged(header, "showSolo", conf.showSolo == true) or changed
  changed = SetAttrIfChanged(header, "showParty", key == "party") or changed
  changed = SetAttrIfChanged(header, "showRaid", key == "raid") or changed
  changed = SetAttrIfChanged(header, "point", point) or changed
  changed = SetAttrIfChanged(header, "xOffset", xOffset) or changed
  changed = SetAttrIfChanged(header, "yOffset", yOffset) or changed
  changed = SetAttrIfChanged(header, "columnSpacing", spacing) or changed
  changed = SetAttrIfChanged(header, "columnAnchorPoint", columnAnchor) or changed
  changed = SetAttrIfChanged(header, "unitsPerColumn", upc) or changed
  changed = SetAttrIfChanged(header, "maxColumns", columns) or changed
  if sortState.sortMethod == "NAMELIST" then
    changed = ApplySortAttributes(header, sortState) or changed
    changed = SetAttrIfChanged(header, "groupFilter", nil) or changed
  else
    changed = SetAttrIfChanged(header, "groupFilter", groupFilter) or changed
    changed = ApplySortAttributes(header, sortState) or changed
  end
  return changed, shouldHide
end

local PRIORITY_SECURE_INIT_VERSION = 1

local function PriorityLayoutParts(kind, conf, count)
  local w, h = 80, 32
  if GF.GetScaledFrameMetrics then
    w, h = GF.GetScaledFrameMetrics(kind)
  else
    local raid = GF.GetConf and GF.GetConf(kind) or {}
    w, h = tonumber(raid.width) or w, tonumber(raid.height) or h
  end
  local spacing = floor((tonumber(conf and conf.spacing) or 2) + 0.5)
  if spacing < 0 then spacing = 0 elseif spacing > 40 then spacing = 40 end
  count = ClampInt(count, 1, 1, 5)
  local horizontal = conf and (conf.growth == "LEFT" or conf.growth == "RIGHT")
  local totalW = horizontal and (w * count + spacing * (count - 1)) or w
  local totalH = horizontal and h or (h * count + spacing * (count - 1))
  return w, h, spacing, totalW, totalH
end

local function PositionPriorityAnchor(anchor, conf, totalW, totalH, kind)
  local mode = conf and conf.anchorMode or "RAID_RIGHT"
  local baseAnchorKey = kind == "party" and "party" or "raid"
  local baseAnchor = GF.anchors and GF.anchors[baseAnchorKey]
  if mode ~= "FREE" and baseAnchor then
    local gap = floor((tonumber(conf.attachGap) or 8) + 0.5)
    local cross = floor((tonumber(conf.attachOffset) or 0) + 0.5)
    if gap < 0 then gap = 0 elseif gap > 100 then gap = 100 end
    anchor:ClearAllPoints()
    if mode == "RAID_LEFT" then
      anchor:SetPoint("TOPRIGHT", baseAnchor, "TOPLEFT", -gap, cross)
      ClampAnchorOnScreen(anchor, "TOPRIGHT", "TOPLEFT", baseAnchor, -gap, cross, totalW, totalH)
    elseif mode == "RAID_TOP" then
      anchor:SetPoint("BOTTOMLEFT", baseAnchor, "TOPLEFT", cross, gap)
      ClampAnchorOnScreen(anchor, "BOTTOMLEFT", "TOPLEFT", baseAnchor, cross, gap, totalW, totalH)
    elseif mode == "RAID_BOTTOM" then
      anchor:SetPoint("TOPLEFT", baseAnchor, "BOTTOMLEFT", cross, -gap)
      ClampAnchorOnScreen(anchor, "TOPLEFT", "BOTTOMLEFT", baseAnchor, cross, -gap, totalW, totalH)
    else
      anchor:SetPoint("TOPLEFT", baseAnchor, "TOPRIGHT", gap, cross)
      ClampAnchorOnScreen(anchor, "TOPLEFT", "TOPRIGHT", baseAnchor, gap, cross, totalW, totalH)
    end
  end
  anchor:SetSize(totalW, totalH)
  anchor._msufGFPriorityAnchor = true
  anchor._msufIsGroupFrame = true
  anchor.msufConfigKey = "gf_priority"
  anchor._msufGFKind = "priority"
  anchor:Show()
end

local function ConfigurePriorityHeader(header, kind, conf, nameList, w, h, spacing)
  local kindChanged = header._msufGFKind ~= nil and header._msufGFKind ~= kind
  local point, xOffset, yOffset, columnAnchor = GrowthAttributes(conf.growth, spacing)
  local initialWidth = floor((w or 80) + 0.5)
  local initialHeight = floor((h or 32) + 0.5)
  local sizeChanged = AttrChanged(header, "initial-width", initialWidth)
    or AttrChanged(header, "initial-height", initialHeight)
  local secureInitChanged = AttrChanged(header, "_msufPrioritySecureInitVersion", PRIORITY_SECURE_INIT_VERSION)
  local topologyChanged = AttrChanged(header, "point", point)
    or AttrChanged(header, "xOffset", xOffset)
    or AttrChanged(header, "yOffset", yOffset)
    or AttrChanged(header, "unitsPerColumn", 5)
  local shouldHide = header.IsShown and header:IsShown()
    and (kindChanged or sizeChanged or secureInitChanged or topologyChanged
      or AttrChanged(header, "auraContainerTemplate", SECURE_AURA_CONTAINER_TEMPLATE)
      or AttrChanged(header, "template", ButtonTemplate())
      or AttrChanged(header, "nameList", nameList))

  if shouldHide then header:Hide() end
  if topologyChanged then ResetManagedChildAnchors(header) end

  local changed = kindChanged
  changed = SetAttrIfChanged(header, "auraContainerTemplate", SECURE_AURA_CONTAINER_TEMPLATE) or changed
  changed = SetAttrIfChanged(header, "template", ButtonTemplate()) or changed
  changed = SetAttrIfChanged(header, "templateType", "Button") or changed
  changed = SetAttrIfChanged(header, "initial-width", initialWidth) or changed
  changed = SetAttrIfChanged(header, "initial-height", initialHeight) or changed
  changed = SetAttrIfChanged(header, "_msufPrioritySecureInitVersion", PRIORITY_SECURE_INIT_VERSION) or changed
  changed = SetAttrIfChanged(header, "oUF-headerType", "group") or changed
  changed = SetAttrIfChanged(header, "_msufPriorityHeader", true) or changed
  if UF and type(UF.ForEachPingBindingAttribute) == "function" then
    UF.ForEachPingBindingAttribute(function(attribute, key)
      changed = SetAttrIfChanged(header, attribute, key) or changed
    end)
  end
  if sizeChanged or secureInitChanged then
    header:SetAttribute("initialConfigFunction", BuildInitialConfigFunction(initialWidth, initialHeight))
    changed = true
  end
  changed = SetAttrIfChanged(header, "showPlayer", true) or changed
  changed = SetAttrIfChanged(header, "showSolo", false) or changed
  changed = SetAttrIfChanged(header, "showParty", kind == "party") or changed
  changed = SetAttrIfChanged(header, "showRaid", kind ~= "party") or changed
  changed = SetAttrIfChanged(header, "groupFilter", nil) or changed
  changed = SetAttrIfChanged(header, "roleFilter", nil) or changed
  changed = SetAttrIfChanged(header, "groupBy", nil) or changed
  changed = SetAttrIfChanged(header, "groupingOrder", nil) or changed
  changed = SetAttrIfChanged(header, "nameList", nameList) or changed
  changed = SetAttrIfChanged(header, "sortMethod", "NAMELIST") or changed
  changed = SetAttrIfChanged(header, "sortDir", "ASC") or changed
  changed = SetAttrIfChanged(header, "point", point) or changed
  changed = SetAttrIfChanged(header, "xOffset", xOffset) or changed
  changed = SetAttrIfChanged(header, "yOffset", yOffset) or changed
  changed = SetAttrIfChanged(header, "columnSpacing", spacing) or changed
  changed = SetAttrIfChanged(header, "columnAnchorPoint", columnAnchor) or changed
  changed = SetAttrIfChanged(header, "unitsPerColumn", 5) or changed
  changed = SetAttrIfChanged(header, "maxColumns", 1) or changed
  header._msufGFKind = kind
  header._msufGFKey = "priority"
  header._msufGFPriorityHeader = true
  return changed, shouldHide
end

--- Configure the protected duplicate strip from a resolved full-name list.
--- Every protected mutation remains on this OOC-only header ownership path.
function GF.SetupPriorityHeader(kind, nameList, count)
  if InCombat() then
    Defer("priority")
    return nil
  end
  if type(nameList) ~= "string" or nameList == "" or (tonumber(count) or 0) < 1 then
    GF.RetireHeader("priority")
    return nil
  end
  if GF.EnsureDB then GF.EnsureDB() end
  local conf = GF.GetPriorityConf and GF.GetPriorityConf() or {}
  local w, h, spacing, totalW, totalH = PriorityLayoutParts(kind, conf, count)
  local anchor = EnsureAnchor("priority", conf, totalW, totalH)
  PositionPriorityAnchor(anchor, conf, totalW, totalH, kind)

  local header = GF.headers.priority
  local newHeader, reused = false, false
  if not header and GF._forceRecreateHeaders ~= true then
    header = GF._headerPool.priority
    if header then
      GF._headerPool.priority = nil
      GF.headers.priority = header
      reused = true
    end
  end
  if header and GF._forceRecreateHeaders == true then
    RetireHeader(header)
    if header.UnregisterAllEvents then header:UnregisterAllEvents() end
    header._msufGFPriorityHeaderEvents = nil
    GF.headers.priority = nil
    GF._headerPool.priority = nil
    header = nil
  end
  if not header then
    header = CreateFrame("Frame", HeaderName("priority"), anchor, "SecureGroupHeaderTemplate")
    GF.headers.priority = header
    newHeader = true
  end

  if header._msufGFPriorityHeaderEvents ~= true and header.RegisterEvent then
    header:RegisterEvent("GROUP_ROSTER_UPDATE")
    header:RegisterEvent("UNIT_NAME_UPDATE")
    header._msufGFPriorityHeaderEvents = true
  end

  local changed, wasHidden = ConfigurePriorityHeader(header, kind, conf, nameList, w, h, spacing)
  local needsScan = changed or newHeader or reused or wasHidden or GF._forceScanHeaders == true
  if header:GetParent() ~= anchor then header:SetParent(anchor) end
  header:ClearAllPoints()
  local origin = conf.growth == "UP" and "BOTTOMLEFT"
    or conf.growth == "LEFT" and "TOPRIGHT"
    or "TOPLEFT"
  header:SetPoint(origin, anchor, origin, 0, 0)
  local coalescedShow = needsScan and BeginHeaderLayoutRebind(header)
  header:Show()
  if (changed or newHeader or reused or wasHidden) and header.SetAttribute then
    header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
  end
  EndHeaderLayoutRebind(header, coalescedShow)

  if needsScan and header.GetChildren then
    for i = 1, select("#", header:GetChildren()) do
      local child = select(i, header:GetChildren())
      if child then
        child._msufGFPriorityFrame = true
        child._msufGFKind = kind
      end
    end
  end
  if needsScan and GF.ScheduleScan then GF.ScheduleScan("priority", kind) end
  return header, needsScan
end

function GF.SetupHeader(key, kind)
  if InCombat() then
    Defer("setup")
    return nil
  end
  if GF.EnsureDB then GF.EnsureDB() end
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  local layoutCount = ConfiguredCount(kind, conf)
  if GF.EnsureStableGridPosition then
    GF.EnsureStableGridPosition(kind, layoutCount, conf)
  end
  local w, h, spacing, _, _, totalW, totalH = LayoutParts(kind, conf, layoutCount)
  local anchor = EnsureAnchor(key, conf, totalW, totalH)
  anchor.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or (kind == "party" and "gf_party" or "gf_raid")
  anchor._msufIsGroupFrame = true
  anchor._msufGFKind = kind
  anchor._msufGFDragCenterToGridX = 0
  anchor._msufGFDragCenterToGridY = 0
  ApplyGroupBorderForKey(key)

  local header = GF.headers[key]
  local newHeader = false
  local reused = false

  if not header and GF._forceRecreateHeaders ~= true then
    local pooled = GF._headerPool[key]
    if pooled then
      GF._headerPool[key] = nil
      header = pooled
      GF.headers[key] = header
      reused = true
    end
  end

  if header and GF._forceRecreateHeaders == true then
    RetireHeader(header)
    GF.headers[key] = nil
    GF._headerPool[key] = nil
    header = nil
    reused = false
  end

  if not header then
    header = CreateFrame("Frame", HeaderName(key), anchor, "SecureGroupHeaderTemplate")
    GF.headers[key] = header
    newHeader = true
  end

  local attrChanged, wasHiddenForLayout = ConfigureHeader(header, key, kind, conf, w, h, spacing, layoutCount)
  header._msufGFKind = kind
  header._msufGFKey = key
  if header:GetParent() ~= anchor then
    header:SetParent(anchor)
  end
  header:ClearAllPoints()
  local point = AnchorPoint(conf)
  --- SecureGroupHeader_Update resizes the header to the complete child
  --- footprint. Align that footprint directly with the equally sized logical
  --- anchor; applying the origin-to-center delta here a second time makes the
  --- visible block drift whenever the roster count changes.
  header:SetPoint(point, anchor, point, 0, 0)
  local coalescedShow
  if wasHiddenForLayout then
    coalescedShow = GF.ScheduleScan and BeginHeaderLayoutRebind(header)
    header:Show()
  end
  --- Filtering and preserved-group layouts can make Blizzard's real secure
  --- footprint differ from the estimate. Re-clamp against the measured header
  --- once its attributes have synchronously rebuilt the child layout.
  local actualW = header.GetWidth and header:GetWidth() or nil
  local actualH = header.GetHeight and header:GetHeight() or nil
  if actualW and actualH and actualW > 0.5 and actualH > 0.5
    and (abs(actualW - totalW) > 0.01 or abs(actualH - totalH) > 0.01) then
    totalW, totalH = actualW, actualH
    anchor = EnsureAnchor(key, conf, totalW, totalH)
  end
  local countChanged = header._msufGFLastLayoutCount ~= layoutCount
  header._msufGFLastLayoutCount = layoutCount
  if (attrChanged or countChanged) and header.SetAttribute and not InCombat() then
    header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
  end
  EndHeaderLayoutRebind(header, coalescedShow)
  -- Attribute writes on a hidden header only update the secure layout recipe.
  -- SecureGroupHeaderTemplate births its managed children from OnShow, so a
  -- new/reused hidden header cannot consume the scan here. Runtime shows it and
  -- performs the one required scan afterward. A visible hide/show rebind can be
  -- scanned synchronously here and reports that work as already handled.
  local needsChildScan = newHeader or reused or GF._forceScanHeaders == true or wasHiddenForLayout == true
  local scanHandled = false
  if GF.ScheduleScan and needsChildScan and header.IsShown and header:IsShown() then
    GF.ScheduleScan(key, kind)
    scanHandled = true
  end
  return header, scanHandled
end
