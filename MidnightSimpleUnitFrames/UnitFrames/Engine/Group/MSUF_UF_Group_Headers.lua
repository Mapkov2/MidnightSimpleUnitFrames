local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

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
local Secrets = MSUF.Secrets or {}
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local IsSecret = Secrets.IsSecret or function(_) return false end
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

GF.headers = GF.headers or {}
GF.anchors = GF.anchors or {}

local hiddenParent

local NIL_ATTR = {}

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

local function HiddenParent()
    if hiddenParent then return hiddenParent end
    hiddenParent = CreateFrame("Frame", "MSUF_GF_CoreHiddenHeaderParent", UIParent)
    hiddenParent:SetAllPoints(UIParent)
    hiddenParent:Hide()
    return hiddenParent
end

local function RetireHeaderChildren(hidden, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if child then
            if GF.UntrackFrame then GF.UntrackFrame(child) end
            if child.Hide then child:Hide() end
            if child.ClearAllPoints then child:ClearAllPoints() end
            if child.SetParent then child:SetParent(hidden) end
        end
    end
end

local function RetireHeader(header)
    if not header then return end
    local hidden = HiddenParent()
    if header.GetChildren then
        RetireHeaderChildren(hidden, header:GetChildren())
    end
    if header.Hide then header:Hide() end
    if header.ClearAllPoints then header:ClearAllPoints() end
    if header.SetParent then header:SetParent(hidden) end
end

function GF.RetireHeader(key)
    if not (GF.headers and key) then return false end
    local header = GF.headers[key]
    if not header then return false end
    RetireHeader(header)
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

local function ConfiguredCount(kind, conf)
    if kind == "party" then
        if GetNumSubgroupMembers then
            local n = GetNumSubgroupMembers() or 0
            if n > 0 and conf.showPlayer ~= false then
                n = n + 1
            elseif n == 0 and conf.showSolo == true and conf.showPlayer ~= false then
                n = 1
            end
            if n > 0 then return n end
        end
        return 5
    end
    if GetNumGroupMembers then
        local n = GetNumGroupMembers() or 0
        if n > 0 then return n end
    end
    return 40
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
    return w, h, spacing, dx or 0, dy or 0, totalW or w, totalH or h
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
    anchor:SetPoint(point, ResolveAnchorFrame(conf), point, conf.offsetX or 0, conf.offsetY or 0)
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

local function GroupFilterAllows(conf, groupIndex)
    local filter = conf and conf.groupFilter
    if type(filter) == "table" then
        local value = filter[groupIndex]
        if value == nil then
            value = filter[tostring(groupIndex)]
        end
        return value ~= false
    elseif type(filter) == "string" and filter ~= "" then
        local wanted = tostring(groupIndex)
        for token in filter:gmatch("[^,]+") do
            token = token:match("^%s*(.-)%s*$")
            if token == wanted then
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

local function IsPlayerUnit(unit)
    if not unit or unit == "" then
        return false
    end
    if unit == "player" then
        return true
    end
    if UnitGUID then
        local guid = UnitGUID(unit)
        local playerGuid = UnitGUID("player")
        if IsSecret(guid) or IsSecret(playerGuid) then
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
    if raidIndex and GetRaidRosterInfo then
        local _, _, subgroup = GetRaidRosterInfo(raidIndex)
        if subgroup and not GroupFilterAllows(conf, subgroup) then
            return
        end
    end
    local name = UnitFullName(unit)
    if not name then
        return
    end
    entries[#entries + 1] = {
        name = name,
        role = UnitRole(unit),
        index = index or 0,
        player = IsPlayerUnit(unit),
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

    if mode == "ROLE" and conf.playerFirstInRole == true then
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
        sortDir = conf.sortDescending == true and "DESC" or "ASC",
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

local BUTTON_TEMPLATE = "SecureUnitButtonTemplate,SecureHandlerStateTemplate,SecureHandlerEnterLeaveTemplate,PingableUnitFrameTemplate"
local INITIAL_CONFIG_FUNCTION = [[
local header = self:GetParent()
self:ClearAllPoints()
self:SetWidth(header:GetAttribute('initial-width'))
self:SetHeight(header:GetAttribute('initial-height'))
self:SetAttribute('*type1', 'target')
self:SetAttribute('*type2', 'togglemenu')
RegisterUnitWatch(self)
]]

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
    local keys = { "top", "bottom", "left", "right" }
    for i = 1, #keys do
        local key = keys[i]
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

local function ConfigureHeader(header, key, kind, conf, w, h, spacing)
    local point, xOffset, yOffset, columnAnchor = GrowthAttributes(conf.growth, spacing)
    local upc = ClampInt(conf.unitsPerColumn, kind == "party" and 5 or 5, 1, 40)
    local columns = ClampInt(conf.maxColumns, kind == "party" and 1 or 8, 1, 8)
    local initialWidth = floor((w or 80) + 0.5)
    local initialHeight = floor((h or 32) + 0.5)
    local sortState = BuildSortState(key, kind, conf)
    local groupFilter = sortState.sortMethod == "NAMELIST" and nil or (key == "party" and nil or ResolveGroupFilter(conf))
    local shouldHide = header.IsShown and header:IsShown()
        and (AttrChanged(header, "template", BUTTON_TEMPLATE)
            or AttrChanged(header, "initialConfigFunction", INITIAL_CONFIG_FUNCTION)
            or AttrChanged(header, "point", point)
            or AttrChanged(header, "xOffset", xOffset)
            or AttrChanged(header, "yOffset", yOffset)
            or AttrChanged(header, "columnSpacing", spacing)
            or AttrChanged(header, "columnAnchorPoint", columnAnchor)
            or AttrChanged(header, "unitsPerColumn", upc)
            or AttrChanged(header, "maxColumns", columns)
            or AttrChanged(header, "initial-width", initialWidth)
            or AttrChanged(header, "initial-height", initialHeight)
            or AttrChanged(header, "groupFilter", groupFilter)
            or SortStateChanged(header, sortState))

    if shouldHide then
        header:Hide()
    end

    local changed = false
    changed = SetAttrIfChanged(header, "template", BUTTON_TEMPLATE) or changed
    changed = SetAttrIfChanged(header, "initial-width", initialWidth) or changed
    changed = SetAttrIfChanged(header, "initial-height", initialHeight) or changed
    changed = SetAttrIfChanged(header, "initialConfigFunction", INITIAL_CONFIG_FUNCTION) or changed
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
    local w, h, spacing, dx, dy, totalW, totalH = LayoutParts(kind, conf)
    local anchor = EnsureAnchor(key, conf, totalW, totalH)
    ApplyGroupBorder(anchor, conf)

    local header = GF.headers[key]
    local newHeader = false
    if header and GF._forceRecreateHeaders == true then
        RetireHeader(header)
        header = nil
        GF.headers[key] = nil
    end
    if not header then
        header = CreateFrame("Frame", HeaderName(key), UIParent, "SecureGroupHeaderTemplate")
        header:SetParent(anchor)
        GF.headers[key] = header
        newHeader = true
    end
    local cleanRelayout = header.IsShown and header:IsShown()
    if cleanRelayout then
        header:Hide()
    end
    local attrChanged, wasHiddenForLayout = ConfigureHeader(header, key, kind, conf, w, h, spacing)
    header._msufGFKind = kind
    header._msufGFKey = key
    if header:GetParent() ~= anchor then
        header:SetParent(anchor)
    end
    header:ClearAllPoints()
    local point = AnchorPoint(conf)
    header:SetPoint(point, anchor, point, -dx, -dy)
    header:SetSize(totalW, totalH)
    if cleanRelayout or wasHiddenForLayout then
        header:Show()
    end
    if attrChanged and header.SetAttribute and not InCombat() then
        header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
    end
    if GF.ScheduleScan and (newHeader or attrChanged) then
        GF.ScheduleScan(key, kind)
    end
    return header
end
