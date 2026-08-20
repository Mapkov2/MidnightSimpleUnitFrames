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
local GetAuraDataBySpellName = C_UnitAuras
    and type(C_UnitAuras.GetAuraDataBySpellName) == "function"
    and C_UnitAuras.GetAuraDataBySpellName or nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local canaccesstable = _G.canaccesstable

local containersByUnit = {}
local framesByUnit = {}
local pendingScopes = {}
local refreshPending = false
local fallbackUnitsA, fallbackUnitsB = {}, {}
local pendingFallbackUnits = fallbackUnitsA
local fallbackDriver
local fallbackDriverArmed = false

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

local function RemoveScanName(container, name)
    local scanNames = container and container._msufA3AuraAliasScanNames
    if not (scanNames and name) then return false end
    for i = 1, #scanNames do
        if scanNames[i] == name then
            local last = #scanNames
            scanNames[i] = scanNames[last]
            scanNames[last] = nil
            return true
        end
    end
    return false
end

local function ResolveAuraData(container, auraData)
    local names = container and container._msufA3AuraAliasNames
    if not (names and auraData) or issecretvalue(auraData)
        or (canaccesstable and canaccesstable(auraData) == false)
    then
        return false, nil
    end
    local name = PublicAuraField(auraData.name)
    local auraSpellID = tonumber(PublicAuraField(auraData.spellId))
    local sources = type(name) == "string" and names[name] or nil
    if not (sources and auraSpellID and auraSpellID > 0) then return false, nil end
    local changed = false
    for sourceSpellID in pairs(sources) do
        changed = ApplyAlias(container, sourceSpellID, auraSpellID) or changed
    end
    -- A successful name lookup has now resolved this compiled source name to
    -- the visible aura spell ID. The native candidate filter owns all future
    -- display updates, so retaining the name in the secret/full fallback list
    -- would only rebuild the same AuraData table on every unrelated UNIT_AURA.
    -- SyncContainer rebuilds the list on every lane/config lifecycle refresh.
    return changed, name
end

local function ScanContainer(container)
    if not (container and GetAuraDataBySpellName) then return false end
    local lane = container._msufA3NativeLaneConfig
    local names = container._msufA3AuraAliasNames
    local scanNames = container._msufA3AuraAliasScanNames
    if not (lane and names and scanNames) then return false end
    local changed = false
    local unit, nativeFilter = container.unit, lane.nativeFilter
    local i = 1
    while i <= #scanNames do
        local scanName = scanNames[i]
        local ok, auraData = pcall(GetAuraDataBySpellName, unit, scanName, nativeFilter)
        local aliasChanged, resolvedName
        if ok and auraData then
            aliasChanged, resolvedName = ResolveAuraData(container, auraData)
            changed = aliasChanged or changed
        end
        if resolvedName then
            -- This lookup queried scanNames[i] itself, so removing the resolved
            -- entry needs no second linear name search. Fill the current slot
            -- from the tail and inspect it before advancing.
            local last = #scanNames
            scanNames[i] = scanNames[last]
            scanNames[last] = nil
        else
            i = i + 1
        end
    end
    return changed
end

local function FlushFallbackScans()
    if fallbackDriver and fallbackDriver.SetScript then
        fallbackDriver:SetScript("OnUpdate", nil)
    end
    fallbackDriverArmed = false

    local batch = pendingFallbackUnits
    pendingFallbackUnits = batch == fallbackUnitsA and fallbackUnitsB or fallbackUnitsA
    for unit in pairs(batch) do
        batch[unit] = nil
        local containers = containersByUnit[unit]
        if containers then
            for container in pairs(containers) do
                local scanNames = container._msufA3AuraAliasScanNames
                if scanNames and scanNames[1] then ScanContainer(container) end
            end
        end
    end
end

local function QueueFallbackScan(unit, containers)
    containers = containers or containersByUnit[unit]
    local hasWork = false
    if containers then
        for container in pairs(containers) do
            local scanNames = container._msufA3AuraAliasScanNames
            if scanNames and scanNames[1] then
                hasWork = true
                break
            end
        end
    end
    if not hasWork then return end
    pendingFallbackUnits[unit] = true
    if fallbackDriverArmed then return end
    if not fallbackDriver and CreateFrame then fallbackDriver = CreateFrame("Frame") end
    if not (fallbackDriver and fallbackDriver.SetScript) then
        pendingFallbackUnits[unit] = nil
        if containers then
            for container in pairs(containers) do ScanContainer(container) end
        end
        return
    end
    fallbackDriverArmed = true
    fallbackDriver:SetScript("OnUpdate", FlushFallbackScans)
end

local function OnEvent(_, _, unit, updateInfo)
    local containers = containersByUnit[unit]
    if not containers then return end
    if issecretvalue(updateInfo) or type(updateInfo) ~= "table"
        or (canaccesstable and canaccesstable(updateInfo) == false) then
        QueueFallbackScan(unit, containers)
        return
    end

    local isFullUpdate = updateInfo.isFullUpdate
    local added = updateInfo.addedAuras
    if issecretvalue(isFullUpdate) or isFullUpdate == true
        or issecretvalue(added) or type(added) ~= "table"
        or (canaccesstable and canaccesstable(added) == false) then
        QueueFallbackScan(unit, containers)
        return
    end
    for i = 1, #added do
        for container in pairs(containers) do
            local _, resolvedName = ResolveAuraData(container, added[i])
            if resolvedName then RemoveScanName(container, resolvedName) end
        end
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
            pendingFallbackUnits[unit] = nil
            fallbackUnitsA[unit] = nil
            fallbackUnitsB[unit] = nil
            local frame = framesByUnit[unit]
            if frame then frame:UnregisterAllEvents() end
            framesByUnit[unit] = nil
        end
    end
    container._msufA3AuraAliasUnit = nil
    container._msufA3AuraAliasNames = nil
    container._msufA3AuraAliasScanNames = nil
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
    -- Compile the hash keys once. Secret/full UNIT_AURA fallbacks are the hot
    -- raid path; numeric iteration avoids rebuilding a generic pairs iterator
    -- for every event while the name->source map remains available to the
    -- public incremental resolver.
    local scanNames = {}
    for name in pairs(names) do scanNames[#scanNames + 1] = name end
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
    container._msufA3AuraAliasScanNames = scanNames
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
