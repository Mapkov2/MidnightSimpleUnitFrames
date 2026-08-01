--- Auras3/MSUF_Auras3_AuraNameResolver.lua
--- Opt-in WeakAuras-style spell-name resolver for custom Aura lanes.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" or A3.AuraNameResolver then return end

local Resolver = {}
A3.AuraNameResolver = Resolver

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local math_floor = math.floor
local CreateFrame = _G.CreateFrame
local C_Spell = _G.C_Spell
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local issecretvalue = _G.issecretvalue or function(_) return false end
local canaccesstable = _G.canaccesstable

local containersByUnit = {}
local framesByUnit = {}
local pendingScopes = {}
local refreshPending = false

local function FlushScopes()
    refreshPending = false
    local scopes = pendingScopes
    pendingScopes = {}
    if type(A3.RequestScope) ~= "function" then return end
    for unit in pairs(scopes) do
        A3.RequestScope(unit, "AURAS3_NAME_ALIAS_LEARNED")
    end
end

local function QueueScope(unit)
    if type(unit) ~= "string" or unit == "" then return end
    pendingScopes[unit] = true
    if refreshPending then return end
    refreshPending = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, FlushScopes)
    else
        FlushScopes()
    end
end

local function PublicAuraField(value)
    if value == nil or issecretvalue(value) then return nil end
    return value
end

local function SpellName(spellID)
    if not (C_Spell and type(C_Spell.GetSpellName) == "function") then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    name = ok and PublicAuraField(name) or nil
    return type(name) == "string" and name ~= "" and name or nil
end

local function LearnAlias(sourceSpellID, auraSpellID)
    sourceSpellID = tonumber(PublicAuraField(sourceSpellID))
    auraSpellID = tonumber(PublicAuraField(auraSpellID))
    if not (sourceSpellID and auraSpellID and sourceSpellID > 0 and auraSpellID > 0) then return false end
    sourceSpellID = math_floor(sourceSpellID + 0.5)
    auraSpellID = math_floor(auraSpellID + 0.5)
    if sourceSpellID == auraSpellID then return false end
    A3.AuraSpellIDAliases = type(A3.AuraSpellIDAliases) == "table" and A3.AuraSpellIDAliases or {}
    local aliases = A3.AuraSpellIDAliases[sourceSpellID]
    if type(aliases) ~= "table" then
        aliases = {}
        A3.AuraSpellIDAliases[sourceSpellID] = aliases
    end
    for i = 1, #aliases do
        if tonumber(aliases[i]) == auraSpellID then return false end
    end
    aliases[#aliases + 1] = auraSpellID
    return true
end

local function ApplyAlias(container, sourceSpellID, auraSpellID)
    if not (container and LearnAlias(sourceSpellID, auraSpellID)) then return false end
    local lane = container._msufA3NativeLaneConfig
    local filters = lane and lane.candidateFilters
    local included = filters and filters.includeSpellIDs
    if type(included) == "table" then
        included[auraSpellID] = true
        lane.candidateFilterSignature = tostring(lane.candidateFilterSignature or "")
            .. ";nameAlias:" .. tostring(sourceSpellID) .. ">" .. tostring(auraSpellID)
        local groupKey = container._msufA3ManagedGroupKey
        if groupKey and type(container.SetAuraGroupCandidateFilters) == "function" then
            container:SetAuraGroupCandidateFilters(groupKey, filters)
            container._msufA3CandidateFilterSignature = lane.candidateFilterSignature
        end
    end
    QueueScope(container.unit)
    return true
end

local function ResolveAuraData(container, auraData)
    local names = container and container._msufA3AuraAliasNames
    if not (names and auraData) or issecretvalue(auraData)
        or (canaccesstable and canaccesstable(auraData) == false)
    then
        return false
    end
    local name = PublicAuraField(auraData.name)
    local auraSpellID = PublicAuraField(auraData.spellId)
    local sources = type(name) == "string" and names[name] or nil
    if not (sources and auraSpellID) then return false end
    local changed = false
    for sourceSpellID in pairs(sources) do
        changed = ApplyAlias(container, sourceSpellID, auraSpellID) or changed
    end
    return changed
end

local function ScanContainer(container)
    if not (container and C_UnitAuras and type(C_UnitAuras.GetAuraDataBySpellName) == "function") then return false end
    local lane = container._msufA3NativeLaneConfig
    local names = container._msufA3AuraAliasNames
    if not (lane and names) then return false end
    local changed = false
    for name in pairs(names) do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, container.unit, name, lane.nativeFilter)
        if ok and auraData then changed = ResolveAuraData(container, auraData) or changed end
    end
    return changed
end

local function OnEvent(_, _, unit, updateInfo)
    local containers = containersByUnit[unit]
    if not containers then return end
    if issecretvalue(updateInfo) or type(updateInfo) ~= "table"
        or (canaccesstable and canaccesstable(updateInfo) == false) then
        for container in pairs(containers) do ScanContainer(container) end
        return
    end

    local isFullUpdate = updateInfo.isFullUpdate
    local added = updateInfo.addedAuras
    if issecretvalue(isFullUpdate) or isFullUpdate == true
        or issecretvalue(added) or type(added) ~= "table"
        or (canaccesstable and canaccesstable(added) == false) then
        for container in pairs(containers) do ScanContainer(container) end
        return
    end
    for i = 1, #added do
        for container in pairs(containers) do ResolveAuraData(container, added[i]) end
    end
end

function Resolver.UnregisterContainer(container)
    local unit = container and container._msufA3AuraAliasUnit
    if not unit then return end
    local containers = containersByUnit[unit]
    if containers then
        containers[container] = nil
        if not next(containers) then
            containersByUnit[unit] = nil
            local frame = framesByUnit[unit]
            if frame then frame:UnregisterAllEvents() end
            framesByUnit[unit] = nil
        end
    end
    container._msufA3AuraAliasUnit = nil
    container._msufA3AuraAliasNames = nil
end

function Resolver.SyncContainer(container)
    Resolver.UnregisterContainer(container)
    local lane = container and container._msufA3NativeLaneConfig
    local spellIDs = lane and lane.nameAliasSpellIDs
    if type(spellIDs) ~= "table" or not next(spellIDs) then return false end
    local names = {}
    for spellID in pairs(spellIDs) do
        local name = SpellName(spellID)
        if name then
            names[name] = names[name] or {}
            names[name][spellID] = true
        end
    end
    if not next(names) then return false end
    local unit = container.unit
    if type(unit) ~= "string" or unit == "" then return false end
    local containers = containersByUnit[unit]
    if not containers then
        containers = {}
        containersByUnit[unit] = containers
    end
    containers[container] = true
    container._msufA3AuraAliasUnit = unit
    container._msufA3AuraAliasNames = names
    local frame = framesByUnit[unit]
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
        frame:RegisterUnitEvent("UNIT_AURA", unit)
        framesByUnit[unit] = frame
    end
    ScanContainer(container)
    return true
end
