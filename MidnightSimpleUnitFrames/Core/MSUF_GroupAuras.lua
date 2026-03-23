local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local pairs = pairs
local C_UnitAuras = C_UnitAuras
local CreateFrame = CreateFrame
local canaccessvalue = _G.canaccessvalue
local issecretvalue = _G.issecretvalue

local SATED = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true, [26013] = true, [71041] = true,
}

local owner = {}
local compactHooked = false
local blizzCache = {}

local function IsAccessible(v)
    if canaccessvalue then
        return canaccessvalue(v) == true
    end
    return not (issecretvalue and issecretvalue(v))
end

local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

local function ScopeForFrame(frame)
    return (frame and frame._groupScope) or "party"
end

local function GetAuraSetting(scope, key, fallback)
    if type(_G.MSUF_Group_GetSetting) == "function" then
        return _G.MSUF_Group_GetSetting(scope, "aura", key, fallback)
    end
    local shared = Shared()
    return shared[key] ~= nil and shared[key] or fallback
end

local function BuildDesignerLookup(scope)
    local designer = GetAuraSetting(scope, "designer", nil)
    local lookup = {}
    if type(designer) ~= "table" or type(designer.groups) ~= "table" then
        return lookup
    end
    for i = 1, #designer.groups do
        local entry = designer.groups[i]
        if type(entry) == "table" and type(entry.spells) == "table" then
            local key = entry.name or ("group" .. i)
            for spellID in pairs(entry.spells) do
                lookup[spellID] = key
            end
        end
    end
    return lookup
end

local function EnsureIcon(container, list, index)
    local icon = list[index]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, container, "BackdropTemplate")
    icon:SetSize(16, 16)
    icon.icon = icon:CreateTexture(nil, "ARTWORK")
    icon.icon:SetAllPoints()
    icon.count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    list[index] = icon
    return icon
end

local function LayoutIcons(container, list, maxCount, iconSize)
    container:SetSize((iconSize + 2) * maxCount, iconSize)
    for i = 1, maxCount do
        local icon = EnsureIcon(container, list, i)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", container, "LEFT", (i - 1) * (iconSize + 2), 0)
        icon:SetSize(iconSize, iconSize)
    end
end

local function ShouldSkipAura(shared, aura, excludeSated)
    if not aura then return true end
    if excludeSated == false then return false end
    local sid = aura.spellId
    if sid == nil or not IsAccessible(sid) then return false end
    return SATED[sid] == true
end

local function ApplyAura(icon, aura)
    if not icon or not aura then return false end
    icon.icon:SetTexture(aura.icon)

    local count = aura.applications
    if count ~= nil and IsAccessible(count) and count > 1 then
        icon.count:SetText(count)
    else
        icon.count:SetText("")
    end
    icon:Show()
    return true
end

local function AddAuraToList(aura, out, seen, groupSeen, designerLookup, maxCount, excludeSated, shared)
    if not aura or ShouldSkipAura(shared, aura, excludeSated) then return false end
    local groupKey
    local sid = aura.spellId
    if sid ~= nil and IsAccessible(sid) and designerLookup then
        groupKey = designerLookup[sid]
    end
    if groupKey then
        if groupSeen[groupKey] then return false end
        groupSeen[groupKey] = true
    end
    local auraInstanceID = aura.auraInstanceID
    if auraInstanceID then
        if seen[auraInstanceID] then return false end
        seen[auraInstanceID] = true
    end
    out[#out + 1] = aura
    return #out >= maxCount
end

local function AddCompactAuras(unit, cacheList, out, seen, groupSeen, designerLookup, maxCount, excludeSated, shared)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) or not cacheList then return end
    for i = 1, #cacheList do
        local auraInstanceID = cacheList[i]
        if auraInstanceID and not seen[auraInstanceID] then
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
            if aura and AddAuraToList(aura, out, seen, groupSeen, designerLookup, maxCount, excludeSated, shared) then
                return
            end
        end
    end
end

local function AddFilteredAuras(unit, filter, out, seen, groupSeen, designerLookup, maxCount, excludeSated, shared)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for idx = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, idx, filter)
        if not aura then break end
        if AddAuraToList(aura, out, seen, groupSeen, designerLookup, maxCount, excludeSated, shared) then
            return
        end
    end
end

local function DisplayAuraList(frame, key, filter, maxCount)
    local container = frame[key]
    local list = (key == "buffContainer") and frame.buffIcons or frame.debuffIcons
    if not container or not list or not C_UnitAuras then return end

    local sh = Shared()
    local scope = ScopeForFrame(frame)
    local iconSize = GetAuraSetting(scope, "iconSize", sh.auraIconSize or 16)
    LayoutIcons(container, list, maxCount, iconSize)

    local unit = frame._assignedUnit
    local shown = 0
    for i = 1, maxCount do
        list[i]:Hide()
    end
    if not unit then return end

    local cache = blizzCache[unit]
    local compactList = cache and ((key == "buffContainer") and cache.buffs or cache.debuffs) or nil
    local picked, seen, groupSeen = {}, {}, {}
    local designerLookup = BuildDesignerLookup(scope)
    local excludeSated = GetAuraSetting(scope, "excludeSated", sh.excludeSated ~= false)
    AddCompactAuras(unit, compactList, picked, seen, groupSeen, designerLookup, maxCount, excludeSated, sh)
    AddFilteredAuras(unit, filter, picked, seen, groupSeen, designerLookup, maxCount, excludeSated, sh)

    for i = 1, #picked do
        shown = shown + 1
        if not ApplyAura(list[shown], picked[i]) or shown >= maxCount then
            break
        end
    end
end

local function RefreshUnit(unit)
    local frame = Group.activeFrames and Group.activeFrames[unit]
    if not frame then return end
    local sh = Shared()
    local scope = ScopeForFrame(frame)
    DisplayAuraList(frame, "buffContainer", "HELPFUL|RAID", GetAuraSetting(scope, "maxBuffs", sh.maxBuffs or 3))
    DisplayAuraList(frame, "debuffContainer", "HARMFUL|RAID", GetAuraSetting(scope, "maxDebuffs", sh.maxDebuffs or 3))
end

local function UnitHandler(_, event, unit)
    RefreshUnit(unit)
end

function _G.MSUF_GroupAuras_RefreshAll()
    if not Group.activeFrames then return end
    for unit in pairs(Group.activeFrames) do
        RefreshUnit(unit)
    end
end

local function CacheCompactList(frame, src, list)
    if not src then return end
    for i = 1, #src do
        local auraFrame = src[i]
        if auraFrame and auraFrame.auraInstanceID then
            list[#list + 1] = auraFrame.auraInstanceID
        end
    end
end

local function HookCompactAuras()
    if compactHooked or type(hooksecurefunc) ~= "function" or type(_G.CompactUnitFrame_UpdateAuras) ~= "function" then return end
    compactHooked = true
    hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
        local unit = frame and frame.unit
        if not unit or not Group.rosterUnits or not Group.rosterUnits[unit] then return end
        local cache = blizzCache[unit] or { buffs = {}, debuffs = {} }
        blizzCache[unit] = cache
        wipe(cache.buffs)
        wipe(cache.debuffs)
        CacheCompactList(frame, frame.buffFrames, cache.buffs)
        CacheCompactList(frame, frame.debuffFrames, cache.debuffs)
        RefreshUnit(unit)
    end)
end

HookCompactAuras()
Group.AddUnitEvent(owner, "UNIT_AURA", UnitHandler)
