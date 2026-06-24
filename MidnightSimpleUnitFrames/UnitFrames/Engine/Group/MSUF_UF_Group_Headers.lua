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
local InCombatLockdown = InCombatLockdown
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
  if not header then return false end
  RetireHeader(header)
  GF._headerPool[key] = header
  GF.headers[key] = nil
  return true
end

local function Defer(reason)
  if GF.DeferGroupRuntime then
    GF.DeferGroupRuntime(reason)
  else
    GF._pendingGroupRuntime = reason or true
  end
end

local function HeaderName(key)
  if key == "party" then
    GF._partyHeaderSerial = (GF._partyHeaderSerial or 0) + 1
    return "MSUF_GF_PartyHeader" .. GF._partyHeaderSerial
  end
  GF._raidHeaderSerial = (GF._raidHeaderSerial or 0) + 1
  return "MSUF_GF_RaidHeader" .. GF._raidHeaderSerial
end

local function AnchorName(key)
  return key == "party" and "MSUF_GF_PartyAnchor" or "MSUF_GF_RaidAnchor"
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

local function LayoutParts(kind, conf)
  local w, h, spacing = 80, 32, 1
  if GF.GetScaledFrameMetrics then
    w, h, spacing = GF.GetScaledFrameMetrics(kind)
  else
    w, h, spacing = conf.width or w, conf.height or h, conf.spacing or spacing
  end
  local count = ConfiguredCount(kind, conf)
  local dx, dy, totalW, totalH = 0, 0, w, h
  if GF.GetGridMetrics then
    dx, dy, totalW, totalH = GF.GetGridMetrics(kind, count)
  end
  return w, h, spacing, dx or 0, dy or 0, totalW or w, totalH or h, count
end

local function ResolveAnchorFrame(conf)
  local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
  if type(name) == "string" and name ~= "" and name ~= "FREE" then
    local UF = MSUF.UF
    if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
    if _G[name] then return _G[name] end
  end
  return UIParent
end

local function AnchorPoint(conf)
  local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
  if not VALID_POINTS[point] then
    point = "CENTER"
  end
  return point
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

--- Keep anchor frames on screen when possible; child layout remains relative to
--- the anchor so saved offsets stay meaningful.
local function ClampAnchorOnScreen(anchor, point, parent, offsetX, offsetY, totalW, totalH)
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
  local px = pLeft + (pRight - pLeft) * fx + (offsetX or 0)
  local py = pBottom + (pTop - pBottom) * fy + (offsetY or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local right = left + boxW
  local top = bottom + boxH

  local dx, dy = 0, 0
  if left < 0 then
    dx = -left
  elseif right > screenW then
    dx = (screenW - right)
    if left + dx < 0 then dx = -left end   -- box wider than screen: pin left
  end
  if bottom < 0 then
    dy = -bottom
    if top + dy > screenH then dy = screenH - top end  -- taller than screen: pin top
  elseif top > screenH then
    dy = screenH - top
  end
  if dx == 0 and dy == 0 then
    return
  end
  anchor:ClearAllPoints()
  anchor:SetPoint(point, parent, point, (offsetX or 0) + dx, (offsetY or 0) + dy)
end

local function EnsureAnchor(key, conf, totalW, totalH)
  local anchor = GF.anchors[key]
  if not anchor then
    anchor = CreateFrame("Frame", AnchorName(key), UIParent)
    anchor:EnableMouse(false)
    GF.anchors[key] = anchor
  end
  anchor:SetSize(totalW, totalH)
  anchor:ClearAllPoints()
  local point = AnchorPoint(conf)
  local parent = ResolveAnchorFrame(conf)
  anchor:SetPoint(point, parent, point, conf.offsetX or 0, conf.offsetY or 0)
  anchor:Show()
  ClampAnchorOnScreen(anchor, point, parent, conf.offsetX or 0, conf.offsetY or 0, totalW, totalH)
  return anchor
end

local function GrowthAttributes(growth, spacing)
  if growth == "UP" then
    return "BOTTOM", 0, spacing, "LEFT"
  elseif growth == "RIGHT" then
    return "LEFT", spacing, 0, "TOP"
  elseif growth == "LEFT" then
    return "RIGHT", -spacing, 0, "TOP"
  end
  return "TOP", 0, -spacing, "LEFT"
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

local function ClampInt(value, fallback, minValue, maxValue)
  value = floor((tonumber(value) or fallback or minValue or 1) + 0.5)
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function RequiredHeaderColumns(kind, conf, count)
  if kind == "party" then return 1 end
  count = floor((tonumber(count) or 0) + 0.5)
  if count < 1 then return 1 end
  if conf and conf.preserveRaidGroups == true then
    local groups = floor(((count + 4) / 5))
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    return groups
  end
  local upc = ClampInt(conf and conf.unitsPerColumn, 5, 1, 40)
  local columns = floor(((count + upc - 1) / upc))
  if columns < 1 then columns = 1 elseif columns > 40 then columns = 40 end
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
  if type(value) == "string" then
    return value ~= "" and value or nil
  elseif type(value) == "table" then
    local out = {}
    for i = 1, 8 do
      if value[i] == true or value[tostring(i)] == true then
        out[#out + 1] = tostring(i)
      end
    end
    if #out > 0 and #out < 8 then
      return table_concat(out, ",")
    end
  end
  return nil
end

local function GroupFilterAllows(conf, groupIndex, classFile, role)
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
  if UnitMissing(unit) then
    return
  end
  local subgroup
  local role = UnitRole(unit)
  local classFile = UnitClassFile(unit)
  if raidIndex and GetRaidRosterInfo then
    subgroup = select(3, GetRaidRosterInfo(raidIndex))
    if subgroup and not GroupFilterAllows(conf, subgroup, classFile, role) then
      return
    end
  end
  local name = UnitFullName(unit)
  if not name then
    return
  end
  entries[#entries + 1] = {
    name = name,
    role = role,
    index = index or 0,
    player = IsPlayerUnit(unit),
    group = subgroup or 0,
  }
end

local function BuildPlayerFirstRoleNameList(key, kind, conf)
  if conf.playerFirstInRole ~= true then
    return nil
  end
  local entries = {}
  if kind == "party" then
    local inGroup = IsInGroup and IsInGroup()
    local inRaid = IsInRaid and IsInRaid()
    if inGroup and not inRaid then
      if conf.showPlayer ~= false then
        AddNameListEntry(entries, "player", 0, conf)
      end
      for i = 1, 4 do
        AddNameListEntry(entries, "party" .. i, i, conf)
      end
    elseif conf.showSolo == true and conf.showPlayer ~= false then
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
  for i = 1, count do
    AddNameListEntry(entries, "raid" .. i, i, conf, i)
  end
  if #entries == 0 then
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
    groupingOrder = "1,2,3,4,5,6,7,8"
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

local SECURE_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate"
local PING_INIT_VERSION = 3

local function ButtonTemplate()
  if UF and type(UF.GetSecureUnitButtonTemplate) == "function" then
    return UF.GetSecureUnitButtonTemplate()
  end
  return SECURE_UNIT_BUTTON_TEMPLATE
end

local _initCfgNonce = 0
local function BuildInitialConfigFunction(w, h)
  _initCfgNonce = _initCfgNonce + 1
  local pingInit = UF and type(UF.GetSecurePingInitialConfig) == "function" and UF.GetSecurePingInitialConfig() or ""
  return string.format([[
self:ClearAllPoints()
self:SetWidth(%.3f)
self:SetHeight(%.3f)
self:SetAttribute('*type1', 'target')
self:SetAttribute('*type2', 'togglemenu')
%s
-- nonce %d
]], w, h, pingInit, _initCfgNonce)
end

local function ApplyGroupBorder(anchor, conf)
  if not anchor then return end
  if conf.groupBorderEnabled ~= true then
    if anchor.MSUFGFGroupBorder then
      for _, edge in pairs(anchor.MSUFGFGroupBorder) do edge:Hide() end
    end
    return
  end
  local edges = anchor.MSUFGFGroupBorder or {}
  anchor.MSUFGFGroupBorder = edges
  local size, pad = conf.groupBorderSize or 1, conf.groupBorderPadding or 2
  local r, g, b, a = conf.groupBorderR or 0.38, conf.groupBorderG or 0.68, conf.groupBorderB or 1, conf.groupBorderA or 0.95
  for i = 1, #BORDER_EDGE_KEYS do
    local key = BORDER_EDGE_KEYS[i]
    local edge = edges[key]
    if not edge then
      edge = anchor:CreateTexture(nil, "OVERLAY")
      edges[key] = edge
    end
    edge:SetColorTexture(r, g, b, a)
    edge:ClearAllPoints()
    if key == "top" then
      edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
      edge:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", pad, pad)
      edge:SetHeight(size)
    elseif key == "bottom" then
      edge:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -pad, -pad)
      edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
      edge:SetHeight(size)
    elseif key == "left" then
      edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
      edge:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -pad, -pad)
      edge:SetWidth(size)
    else
      edge:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", pad, pad)
      edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
      edge:SetWidth(size)
    end
    edge:Show()
  end
end

local function ConfigureHeader(header, key, kind, conf, w, h, spacing, layoutCount)
  local buttonTemplate = ButtonTemplate()
  local point, xOffset, yOffset, columnAnchor = GrowthAttributes(conf.growth, spacing)
  local upc = ClampInt(conf.unitsPerColumn, kind == "party" and 5 or 5, 1, 40)
  local requiredColumns = RequiredHeaderColumns(kind, conf, layoutCount)
  local columns = requiredColumns
  local initialWidth = floor((w or 80) + 0.5)
  local initialHeight = floor((h or 32) + 0.5)
  local sizeChanged = AttrChanged(header, "initial-width", initialWidth)
    or AttrChanged(header, "initial-height", initialHeight)
  local pingInitChanged = AttrChanged(header, "_msufPingInitVersion", PING_INIT_VERSION)
  local initCfg = (sizeChanged or pingInitChanged) and BuildInitialConfigFunction(initialWidth, initialHeight) or nil
  local sortState = BuildSortState(key, kind, conf)
  local groupFilter = sortState.sortMethod == "NAMELIST" and nil or (key == "party" and nil or ResolveGroupFilter(conf))
  local shouldHide = header.IsShown and header:IsShown()
    and (AttrChanged(header, "template", buttonTemplate)
      or sizeChanged
      or AttrChanged(header, "point", point)
      or AttrChanged(header, "xOffset", xOffset)
      or AttrChanged(header, "yOffset", yOffset)
      or AttrChanged(header, "columnSpacing", spacing)
      or AttrChanged(header, "columnAnchorPoint", columnAnchor)
      or AttrChanged(header, "unitsPerColumn", upc)
      or AttrChanged(header, "maxColumns", columns)
      or AttrChanged(header, "groupFilter", groupFilter)
      or pingInitChanged
      or SortStateChanged(header, sortState))

  if shouldHide then
    header:Hide()
  end

  local changed = false
  changed = SetAttrIfChanged(header, "template", buttonTemplate) or changed
  changed = SetAttrIfChanged(header, "initial-width", initialWidth) or changed
  changed = SetAttrIfChanged(header, "initial-height", initialHeight) or changed
  changed = SetAttrIfChanged(header, "_msufPingInitVersion", PING_INIT_VERSION) or changed
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

function GF.SetupHeader(key, kind)
  if InCombat() then
    Defer("setup")
    return nil
  end
  if GF.EnsureDB then GF.EnsureDB() end
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  local w, h, spacing, dx, dy, totalW, totalH, layoutCount = LayoutParts(kind, conf)
  local anchor = EnsureAnchor(key, conf, totalW, totalH)
  anchor.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or (kind == "party" and "gf_party" or "gf_raid")
  anchor._msufIsGroupFrame = true
  anchor._msufGFKind = kind
  anchor._msufGFDragCenterToGridX = 0
  anchor._msufGFDragCenterToGridY = 0
  ApplyGroupBorder(anchor, conf)

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
    header = CreateFrame("Frame", HeaderName(key), UIParent, "SecureGroupHeaderTemplate")
    header:SetParent(anchor)
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
  header:SetPoint(point, anchor, point, -dx, -dy)
  if wasHiddenForLayout then
    header:Show()
  end
  local countChanged = header._msufGFLastLayoutCount ~= layoutCount
  header._msufGFLastLayoutCount = layoutCount
  if (attrChanged or countChanged) and header.SetAttribute and not InCombat() then
    header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
  end
  -- Attribute writes on a hidden header only update the secure layout recipe.
  -- Scanning children is needed for new/reused headers, explicit roster forces,
  -- or when a visible header was hide/show cycled and may have retargeted children.
  local needsChildScan = newHeader or reused or GF._forceScanHeaders == true or wasHiddenForLayout == true
  if GF.ScheduleScan and needsChildScan then
    GF.ScheduleScan(key, kind)
  end
  return header
end
